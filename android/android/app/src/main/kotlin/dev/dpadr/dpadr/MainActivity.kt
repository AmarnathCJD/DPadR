package dev.dpadr.dpadr

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "dpadr/sdp"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceUuids" -> {
                    val address = call.argument<String>("address")
                    if (address == null) {
                        result.error("bad_args", "missing address", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        if (adapter == null) {
                            result.success(emptyList<String>())
                            return@setMethodCallHandler
                        }
                        val device: BluetoothDevice = adapter.getRemoteDevice(address)
                        // Returns the cached SDP UUIDs from the last pairing/scan.
                        // Does not perform a fresh SDP query — that requires
                        // fetchUuidsWithSdp() which is async and pricier.
                        val uuids = device.uuids ?: emptyArray()
                        val out = uuids.map { it.uuid.toString().lowercase() }
                        result.success(out)
                    } catch (e: SecurityException) {
                        result.error("perm", e.message, null)
                    } catch (e: Throwable) {
                        result.error("err", e.message, null)
                    }
                }
                "getMajorDeviceClass" -> {
                    val address = call.argument<String>("address")
                    if (address == null) {
                        result.error("bad_args", "missing address", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val adapter = BluetoothAdapter.getDefaultAdapter()
                        if (adapter == null) {
                            result.success(-1)
                            return@setMethodCallHandler
                        }
                        val device: BluetoothDevice = adapter.getRemoteDevice(address)
                        val cls = device.bluetoothClass
                        // BluetoothClass.Device.Major.* values: 0x100 = Computer,
                        // 0x200 = Phone, etc. Return the major class shifted so
                        // 1 = Computer, 2 = Phone, etc.
                        val major = if (cls != null) cls.majorDeviceClass shr 8 else -1
                        result.success(major)
                    } catch (e: SecurityException) {
                        result.error("perm", e.message, null)
                    } catch (e: Throwable) {
                        result.error("err", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
