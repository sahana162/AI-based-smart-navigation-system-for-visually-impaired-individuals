package com.example.blind_navigation

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "UvcCameraService"
        private const val USB_CHANNEL = "com.example.blind_navigation/usb_permissions"
        private const val ACTION_USB_PERMISSION = "com.example.blind_navigation.USB_PERMISSION"
    }

    private var usbReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USB_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "logNative" -> {
                    val tag = call.argument<String>("tag") ?: TAG
                    val message = call.argument<String>("message") ?: ""
                    val isError = call.argument<Boolean>("isError") ?: false
                    if (isError) {
                        Log.e(tag, message)
                    } else {
                        Log.i(tag, message)
                    }
                    result.success(null)
                }

                "queryAndRequestUsbDevice" -> {
                    try {
                        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
                        val deviceList = usbManager.deviceList
                        Log.i(TAG, "Native queryAndRequestUsbDevice: ${deviceList.size} USB device(s) connected.")

                        if (deviceList.isEmpty()) {
                            Log.i(TAG, "No USB devices connected to OTG host.")
                            result.success(mapOf(
                                "deviceFound" to false,
                                "message" to "No USB devices detected on OTG port."
                            ))
                            return@setMethodCallHandler
                        }

                        var matchingDevice: UsbDevice? = null
                        var isRealtekYjx = false

                        for (device in deviceList.values) {
                            val vid = device.vendorId
                            val pid = device.productId
                            val devClass = device.deviceClass
                            val mfg = try { device.manufacturerName } catch (_: Exception) { null }
                            val prod = try { device.productName } catch (_: Exception) { null }

                            Log.i(TAG, "Inspecting USB Device: name=${device.deviceName}, VID=$vid (0x${Integer.toHexString(vid)}), PID=$pid (0x${Integer.toHexString(pid)}), Class=$devClass, Mfg=$mfg, Prod=$prod")

                            // Match YJX-C5 (VID: 3034 / 0x0BDA, PID: 1381 / 0x0565, Mfg: GYY) or general UVC (class 14 / 239)
                            val isYjxC5VidPid = (vid == 3034 && pid == 1381)
                            val isRealtek = (vid == 3034)
                            val isUvcClass = (devClass == 14 || devClass == 239) ||
                                    (device.interfaceCount > 0 && (0 until device.interfaceCount).any { i ->
                                        val iface = device.getInterface(i)
                                        iface.interfaceClass == 14 || iface.interfaceClass == 239
                                    })

                            if (isYjxC5VidPid || isRealtek || isUvcClass) {
                                matchingDevice = device
                                isRealtekYjx = isYjxC5VidPid || isRealtek
                                break
                            }
                        }

                        if (matchingDevice == null) {
                            Log.w(TAG, "No matching UVC/YJX-C5 video device found in connected devices.")
                            result.success(mapOf(
                                "deviceFound" to false,
                                "message" to "USB devices found, but none match UVC video camera specs."
                            ))
                            return@setMethodCallHandler
                        }

                        val target = matchingDevice
                        val hasPerm = usbManager.hasPermission(target)
                        val displayName = if (isRealtekYjx) "YJX-C5 Smart Glasses" else (target.productName ?: "UVC Smart Glasses")
                        Log.i(TAG, "Found target camera: $displayName (VID=${target.vendorId}, PID=${target.productId}), hasPermission=$hasPerm")

                        if (!hasPerm) {
                            Log.i(TAG, "Permission NOT granted yet for $displayName. Registering receiver and requesting UsbManager permission...")
                            registerUsbPermissionReceiver(target, flutterEngine)

                            // FLAG_MUTABLE is mandatory on Android 12+ (SDK >= 31) for UsbManager permission PendingIntent
                            val flags = if (Build.VERSION.SDK_INT >= 31) {
                                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                            } else {
                                PendingIntent.FLAG_UPDATE_CURRENT
                            }
                            val intent = Intent(ACTION_USB_PERMISSION).apply {
                                setPackage(packageName)
                            }
                            val permissionIntent = PendingIntent.getBroadcast(this, 0, intent, flags)
                            usbManager.requestPermission(target, permissionIntent)

                            result.success(mapOf(
                                "deviceFound" to true,
                                "hasPermission" to false,
                                "permissionRequested" to true,
                                "deviceName" to displayName,
                                "vendorId" to target.vendorId,
                                "productId" to target.productId
                            ))
                        } else {
                            Log.i(TAG, "Runtime USB permission already active for $displayName.")
                            result.success(mapOf(
                                "deviceFound" to true,
                                "hasPermission" to true,
                                "permissionRequested" to false,
                                "deviceName" to displayName,
                                "vendorId" to target.vendorId,
                                "productId" to target.productId
                            ))
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "queryAndRequestUsbDevice error: ${e.message}", e)
                        result.error("USB_ERROR", e.message, null)
                    }
                }

                "requestUsbPermission" -> {
                    // Fallback shortcut for compatibility
                    val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
                    val hasPerm = usbManager.deviceList.values.any { it.vendorId == 3034 && usbManager.hasPermission(it) }
                    result.success(hasPerm)
                }

                "hasUsbPermission" -> {
                    val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
                    val hasPerm = usbManager.deviceList.values.any { device ->
                        (device.vendorId == 3034 || device.deviceClass == 14 || device.deviceClass == 239) &&
                                usbManager.hasPermission(device)
                    }
                    result.success(hasPerm)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun registerUsbPermissionReceiver(targetDevice: UsbDevice, flutterEngine: FlutterEngine) {
        if (usbReceiver != null) {
            try {
                unregisterReceiver(usbReceiver)
            } catch (_: Exception) {}
        }

        usbReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_USB_PERMISSION) {
                    synchronized(this) {
                        val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                        }
                        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                        Log.i(TAG, "BroadcastReceiver ACTION_USB_PERMISSION result: granted=$granted for VID:${device?.vendorId ?: targetDevice.vendorId}")

                        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USB_CHANNEL)
                        channel.invokeMethod("onUsbPermissionResult", mapOf(
                            "granted" to granted,
                            "vendorId" to (device?.vendorId ?: targetDevice.vendorId),
                            "productId" to (device?.productId ?: targetDevice.productId)
                        ))
                    }
                }
            }
        }

        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(usbReceiver, filter)
        }
    }

    override fun onDestroy() {
        if (usbReceiver != null) {
            try {
                unregisterReceiver(usbReceiver)
            } catch (_: Exception) {}
            usbReceiver = null
        }
        super.onDestroy()
    }
}
