import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefLastAddress = 'dpadr.lastDeviceAddress';
const String _prefLastName = 'dpadr.lastDeviceName';

/// Standard SPP UUID — the same one our Go server registers via WSASetService.
const String sppUuid = '00001101-0000-1000-8000-00805f9b34fb';
const MethodChannel _sdpChannel = MethodChannel('dpadr/sdp');

class AdbDevice {
  final String serial;
  final String state;
  AdbDevice(this.serial, this.state);

  factory AdbDevice.fromJson(Map<String, dynamic> j) =>
      AdbDevice(j['serial'] as String, j['state'] as String);

  bool get online => state == 'device';
}

class AdbDisplay {
  final int id;
  final String name;
  AdbDisplay(this.id, this.name);

  factory AdbDisplay.fromJson(Map<String, dynamic> j) =>
      AdbDisplay(j['id'] as int, j['name'] as String);
}

enum BtState { disconnected, connecting, connected, reconnecting }

class BtClient extends ChangeNotifier {
  BluetoothConnection? _conn;
  final _bt = FlutterBluetoothSerial.instance;

  BtState _state = BtState.disconnected;
  BtState get state => _state;

  String? _peerName;
  String? get peerName => _peerName;

  String? _lastError;
  String? get lastError => _lastError;

  // Pending request map: id → completer waiting for the matching response.
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 1;

  // Reads on the BT channel arrive in chunks; we frame on '\n'.
  final _readBuf = BytesBuilder(copy: false);

  /// Asks for the runtime permissions the plugin needs. On Android 12+ this is
  /// BLUETOOTH_CONNECT + BLUETOOTH_SCAN. We *also* request location because
  /// flutter_bluetooth_serial 0.4.0 unconditionally checks ACCESS_FINE_LOCATION
  /// inside getBondedDevices() and throws "discovering other devices requires
  /// location access" otherwise — even on Android 12+ where it isn't actually
  /// needed by the OS.
  ///
  /// Returns true if every required permission was granted.
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<List<BluetoothDevice>> listBondedDevices() async {
    return _bt.getBondedDevices();
  }

  /// Returns only the bonded devices that advertise our SPP service UUID in
  /// their cached SDP record (i.e. the laptop is running dpadr's Go server).
  /// Devices whose UUID list can't be fetched (permission, transient error)
  /// fall through and are included — better to show them than hide a working
  /// peer because of a stale cache.
  Future<List<BluetoothDevice>> listDpadrDevices() async {
    final all = await _bt.getBondedDevices();
    final filtered = <BluetoothDevice>[];
    for (final d in all) {
      if (await _hasSppUuid(d.address)) filtered.add(d);
    }
    return filtered;
  }

  Future<bool> _hasSppUuid(String address) async {
    try {
      final uuids = await _sdpChannel.invokeMethod<List<dynamic>>(
        'getDeviceUuids',
        {'address': address},
      );
      final lower = (uuids ?? const [])
          .map((u) => (u as String).toLowerCase())
          .toSet();
      // Empty cache → can't tell, include.
      // Has SPP → include.
      return lower.isEmpty || lower.contains(sppUuid);
    } catch (e) {
      debugPrint('dpadr: SDP filter error for $address: $e — including anyway');
      return true;
    }
  }

  /// Returns bonded devices whose Bluetooth class-of-device looks like a
  /// computer (laptop / desktop). No active inquiry — fast, just reads the
  /// cached pairing info. The major class for "Computer" is 0x01.
  Future<List<BluetoothDevice>> listComputerDevices() async {
    final all = await _bt.getBondedDevices();
    final result = <BluetoothDevice>[];
    for (final d in all) {
      final majorClass = await _majorDeviceClass(d.address);
      // 1 = Computer; -1 = unknown (include — be permissive).
      if (majorClass == 1 || majorClass < 0) {
        result.add(d);
      }
    }
    return result;
  }

  Future<int> _majorDeviceClass(String address) async {
    try {
      final v = await _sdpChannel.invokeMethod<int>(
        'getMajorDeviceClass',
        {'address': address},
      );
      return v ?? -1;
    } catch (e) {
      debugPrint('dpadr: majorDeviceClass error for $address: $e');
      return -1;
    }
  }

  Future<void> stopDiscovery() async {
    try {
      await _bt.cancelDiscovery();
    } catch (_) {}
  }

  /// Returns true if Bluetooth is currently enabled. Does NOT call requestEnable()
  /// — that path triggers a known double-reply crash on Android 13+ in
  /// flutter_bluetooth_serial 0.4.0. The UI surfaces an "enable Bluetooth" hint
  /// instead and the user toggles it from system settings.
  Future<bool> isBluetoothOn() async {
    return (await _bt.isEnabled) ?? false;
  }

  Future<void> connect(BluetoothDevice device) async {
    _setState(BtState.connecting);
    _peerName = device.name ?? device.address;
    try {
      _conn = await BluetoothConnection.toAddress(device.address);
      _conn!.input!.listen(
        _onBytes,
        onDone: _onClosed,
        onError: (e) {
          _lastError = e.toString();
          _onClosed();
        },
        cancelOnError: true,
      );
      _setState(BtState.connected);
      // Remember this device so the hero card on the home screen can
      // surface it on next launch.
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_prefLastAddress, device.address);
        await p.setString(_prefLastName, device.name ?? device.address);
      } catch (_) {}
    } catch (e) {
      _lastError = e.toString();
      _setState(BtState.disconnected);
      rethrow;
    }
  }

  /// Returns the address + display name of the most recently connected device,
  /// or null if none was ever stored. Used to highlight a "preferred" device
  /// on the home screen.
  Future<({String address, String name})?> lastConnectedDevice() async {
    try {
      final p = await SharedPreferences.getInstance();
      final addr = p.getString(_prefLastAddress);
      final name = p.getString(_prefLastName);
      if (addr == null || addr.isEmpty) return null;
      return (address: addr, name: name ?? addr);
    } catch (_) {
      return null;
    }
  }

  void _onBytes(Uint8List chunk) {
    _readBuf.add(chunk);
    final bytes = _readBuf.toBytes();
    int start = 0;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A /* '\n' */) {
        final line = bytes.sublist(start, i);
        _onLine(line);
        start = i + 1;
      }
    }
    _readBuf.clear();
    if (start < bytes.length) {
      _readBuf.add(bytes.sublist(start));
    }
  }

  void _onLine(Uint8List line) {
    if (line.isEmpty) return;
    try {
      final obj = jsonDecode(utf8.decode(line)) as Map<String, dynamic>;
      final id = obj['id'] as int? ?? 0;
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(obj);
      }
    } catch (e) {
      debugPrint('bt: parse error: $e on line: ${utf8.decode(line, allowMalformed: true)}');
    }
  }

  void _onClosed() {
    _conn = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('disconnected'));
    }
    _pending.clear();
    _setState(BtState.disconnected);
  }

  Future<void> disconnect() async {
    try {
      await _conn?.close();
    } catch (_) {}
    _conn = null;
    _setState(BtState.disconnected);
  }

  void _setState(BtState s) {
    _state = s;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _request(Map<String, dynamic> body) {
    final id = _nextId++;
    body['id'] = id;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final line = utf8.encode('${jsonEncode(body)}\n');
    final c = _conn;
    if (c == null) {
      _pending.remove(id);
      return Future.error(StateError('not connected'));
    }
    c.output.add(Uint8List.fromList(line));
    c.output.allSent.catchError((e) {
      final pending = _pending.remove(id);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(e);
      }
    });

    return completer.future.timeout(const Duration(seconds: 6), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('no response from server');
    });
  }

  Future<List<AdbDevice>> listDevices() async {
    final r = await _request({'type': 'listDevices'});
    if (r['ok'] != true) throw Exception(r['error'] ?? 'failed');
    final data = r['data'] as List? ?? [];
    return data.map((e) => AdbDevice.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AdbDisplay>> listDisplays(String serial) async {
    final r = await _request({'type': 'listDisplays', 'serial': serial});
    if (r['ok'] != true) throw Exception(r['error'] ?? 'failed');
    final data = r['data'] as List? ?? [];
    return data.map((e) => AdbDisplay.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> sendKey(String serial, String key, {int? display}) async {
    final body = <String, dynamic>{'type': 'keyevent', 'serial': serial, 'key': key};
    if (display != null) body['display'] = display;
    final r = await _request(body);
    if (r['ok'] != true) throw Exception(r['error'] ?? 'failed');
  }

  Future<void> sendText(String serial, String text, {int? display}) async {
    if (text.isEmpty) return;
    final body = <String, dynamic>{'type': 'text', 'serial': serial, 'text': text};
    if (display != null) body['display'] = display;
    final r = await _request(body);
    if (r['ok'] != true) throw Exception(r['error'] ?? 'failed');
  }
}
