import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import 'bt_client.dart';
import 'main.dart';
import 'remote_page.dart';

class HomePage extends StatefulWidget {
  final BtClient client;
  final VoidCallback onToggleTheme;
  const HomePage({super.key, required this.client, required this.onToggleTheme});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<BluetoothDevice> _devices = [];
  bool _scanning = false;
  bool _btOff = false;
  String? _connectingAddress;
  String? _error;
  String? _lastAddress;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onClientChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientChanged);
    super.dispose();
  }

  void _onClientChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final last = await widget.client.lastConnectedDevice();
    if (mounted && last != null) {
      setState(() => _lastAddress = last.address);
    }
    await _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final granted = await widget.client.requestPermissions();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _error = 'Bluetooth + Location permission needed.';
        });
        return;
      }
      final on = await widget.client.isBluetoothOn();
      if (!on) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _btOff = true;
        });
        return;
      }
      final list = await widget.client.listComputerDevices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _scanning = false;
        _btOff = false;
      });
    } catch (e, st) {
      debugPrint('dpadr: _scan failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = 'Could not load devices.';
      });
    }
  }

  Future<void> _openBluetoothSettings() async {
    try {
      await FlutterBluetoothSerial.instance.openSettings();
    } catch (_) {}
  }

  Future<void> _connect(BluetoothDevice d) async {
    setState(() {
      _connectingAddress = d.address;
      _error = null;
    });

    String? initialSerial;
    Object? lastErr;
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        await widget.client.connect(d);
        final devs = await widget.client.listDevices();
        if (devs.isNotEmpty) {
          initialSerial = devs.firstWhere((x) => x.online, orElse: () => devs.first).serial;
        }
        lastErr = null;
        break;
      } catch (e, st) {
        lastErr = e;
        debugPrint('dpadr: connect attempt $attempt failed: $e\n$st');
        if (attempt == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }

    if (mounted) {
      setState(() {
        _connectingAddress = null;
        if (lastErr != null) {
          _error = "Couldn't reach ${d.name ?? d.address}.";
        }
      });
    }

    if (!mounted || initialSerial == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RemotePage(
        client: widget.client,
        initialSerial: initialSerial!,
        initialDisplay: null,
        onToggleTheme: widget.onToggleTheme,
      ),
    ));
  }

  BluetoothDevice? _heroDevice() {
    if (_devices.isEmpty) return null;
    if (_lastAddress != null) {
      for (final d in _devices) {
        if (d.address == _lastAddress) return d;
      }
    }
    return _devices.first;
  }

  List<BluetoothDevice> _otherDevices(BluetoothDevice? hero) {
    if (hero == null) return _devices;
    return _devices.where((d) => d.address != hero.address).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final hero = _heroDevice();
    final others = _otherDevices(hero);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connecting = _connectingAddress != null;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _Header(
              isDark: isDark,
              refreshing: _scanning,
              onRefresh: _scanning ? null : _scan,
              onToggleTheme: widget.onToggleTheme,
            ),
            const SizedBox(height: 32),
            if (_btOff)
              _BluetoothOffPanel(onOpenSettings: _openBluetoothSettings)
            else if (_scanning && _devices.isEmpty)
              const _ScanningPanel()
            else if (hero == null)
              _NoComputersPanel(onOpenSettings: _openBluetoothSettings)
            else
              _DeviceHero(
                device: hero,
                isLastConnected: hero.address == _lastAddress,
                connecting: _connectingAddress == hero.address,
                disabled: connecting && _connectingAddress != hero.address,
                onConnect: () => _connect(hero),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorNote(message: _error!, onDismiss: () => setState(() => _error = null)),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: 36),
              _SectionLabel(text: 'Other computers'),
              const SizedBox(height: 12),
              for (final d in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OtherDeviceCard(
                    device: d,
                    busy: _connectingAddress == d.address,
                    disabled: connecting && _connectingAddress != d.address,
                    onTap: () => _connect(d),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────── HEADER ───────────

class _Header extends StatelessWidget {
  final bool isDark;
  final bool refreshing;
  final VoidCallback? onRefresh;
  final VoidCallback onToggleTheme;
  const _Header({
    required this.isDark,
    required this.refreshing,
    required this.onRefresh,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    return Row(
      children: [
        // Logomark — a friendly dot composition
        SizedBox(
          width: 32,
          height: 32,
          child: CustomPaint(painter: _LogoPainter(p.accent, p.ink)),
        ),
        const SizedBox(width: 12),
        Text(
          'dpadr',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: -0.3),
        ),
        const Spacer(),
        _RoundIcon(
          onTap: onRefresh,
          child: refreshing
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: p.muted),
                )
              : Icon(Icons.refresh_rounded, size: 18, color: p.ink),
        ),
        const SizedBox(width: 8),
        _RoundIcon(
          onTap: onToggleTheme,
          child: Icon(
            isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
            size: 16,
            color: p.ink,
          ),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  final Color accent;
  final Color ink;
  _LogoPainter(this.accent, this.ink);
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 6;
    final inkP = Paint()..color = ink;
    final accP = Paint()..color = accent;
    // Plus-shape made of dots — up/left/right/down + center
    canvas.drawCircle(Offset(size.width / 2, r), r, inkP);
    canvas.drawCircle(Offset(r, size.height / 2), r, inkP);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), r * 1.2, accP);
    canvas.drawCircle(Offset(size.width - r, size.height / 2), r, inkP);
    canvas.drawCircle(Offset(size.width / 2, size.height - r), r, inkP);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _RoundIcon extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _RoundIcon({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: dpadrShadows(context, depth: 0.3),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

// ─────────── SECTION LABEL ───────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

// ─────────── HERO CARD ───────────

class _DeviceHero extends StatelessWidget {
  final BluetoothDevice device;
  final bool isLastConnected;
  final bool connecting;
  final bool disabled;
  final VoidCallback onConnect;

  const _DeviceHero({
    required this.device,
    required this.isLastConnected,
    required this.connecting,
    required this.disabled,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final t = Theme.of(context).textTheme;
    final name = device.name?.isNotEmpty == true ? device.name! : device.address;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dpadrShadows(context, depth: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: device class + last-used pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: p.sunken,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.computer_rounded, size: 13, color: p.muted),
                    const SizedBox(width: 6),
                    Text(
                      'Computer',
                      style: t.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (isLastConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 12, color: p.accent),
                      const SizedBox(width: 5),
                      Text(
                        'Last used',
                        style: t.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: p.accent,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 28),
          // Big device name
          Text(
            name,
            style: t.displayMedium,
            maxLines: 2,
          ),
          const SizedBox(height: 6),
          // MAC address mono
          Text(
            device.address,
            style: dpadrMono(context, size: 12, color: p.muted, letter: 0.4),
          ),
          const SizedBox(height: 28),
          // Connect button — terracotta accent
          _ConnectButton(
            connecting: connecting,
            disabled: disabled,
            onTap: disabled || connecting ? null : onConnect,
          ),
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  final bool connecting;
  final bool disabled;
  final VoidCallback? onTap;
  const _ConnectButton({
    required this.connecting,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final inactive = onTap == null;
    return Material(
      color: inactive ? p.sunken : p.accent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: inactive
                ? null
                : [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                      spreadRadius: -4,
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (connecting) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: p.onAccent.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Icon(Icons.bluetooth_connected_rounded, color: inactive ? p.muted : p.onAccent, size: 18),
                const SizedBox(width: 10),
              ],
              Text(
                connecting ? 'Connecting' : 'Connect',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: inactive ? p.muted : p.onAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────── EMPTY / SCANNING / OFF PANELS ───────────

class _ScanningPanel extends StatelessWidget {
  const _ScanningPanel();

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dpadrShadows(context),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: p.accent),
          ),
          const SizedBox(height: 18),
          Text('Looking for computers', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Reading paired devices…', style: t.bodySmall),
        ],
      ),
    );
  }
}

class _NoComputersPanel extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _NoComputersPanel({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dpadrShadows(context),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: p.sunken,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.computer_outlined, size: 28, color: p.muted),
          ),
          const SizedBox(height: 18),
          Text('No paired computers', style: t.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Pair your laptop in Bluetooth settings, then come back.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_bluetooth, size: 16),
            label: const Text('Open settings'),
          ),
        ],
      ),
    );
  }
}

class _BluetoothOffPanel extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const _BluetoothOffPanel({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(28),
        boxShadow: dpadrShadows(context),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.bluetooth_disabled, size: 26, color: p.accent),
          ),
          const SizedBox(height: 18),
          Text('Bluetooth is off', style: t.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Turn on Bluetooth to find your computer.',
            style: t.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onOpenSettings,
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
            ),
            icon: const Icon(Icons.settings_bluetooth, size: 16),
            label: const Text('Open settings'),
          ),
        ],
      ),
    );
  }
}

// ─────────── OTHER DEVICE ROW ───────────

class _OtherDeviceCard extends StatelessWidget {
  final BluetoothDevice device;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;
  const _OtherDeviceCard({
    required this.device,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    final t = Theme.of(context).textTheme;
    final name = device.name?.isNotEmpty == true ? device.name! : device.address;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: dpadrShadows(context, depth: 0.4),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.sunken,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.computer_rounded,
                  size: 18,
                  color: disabled ? p.muted : p.ink,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: t.titleSmall?.copyWith(
                        fontSize: 14.5,
                        color: disabled ? p.muted : p.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.address,
                      style: dpadrMono(context, size: 11, color: p.muted, letter: 0.3),
                    ),
                  ],
                ),
              ),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: p.accent),
                )
              else
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: disabled ? p.line : p.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────── ERROR NOTE ───────────

class _ErrorNote extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorNote({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final p = DpadrThemeProvider.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_rounded, size: 18, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.ink),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 16, color: p.muted),
          ),
        ],
      ),
    );
  }
}
