package com.example.blind_navigation

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val USB_CHANNEL = "com.example.blind_navigation/usb_permissions"
    private val ACTION_USB_PERMISSION = "com.example.blind_navigation.USB_PERMISSION"

    private var usbReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USB_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestUsbPermission" -> {
                    val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
                    val deviceList = usbManager.deviceList
                    var requested = false

                    if (deviceList.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    for (device in deviceList.values) {
                        // Check for Realtek / YJX-C5 (VID: 3034 / 0x0BDA, PID: 1381 / 0x0565) or UVC / AV classes
                        val isYjxC5 = device.vendorId == 3034 && device.productId == 1381
                        val isRealtek = device.vendorId == 3034
                        val isVideoClass = device.deviceClass == 14 || device.deviceClass == 239 ||
                                (device.interfaceCount > 0 && (0 until device.interfaceCount).any { i ->
                                    val iface = device.getInterface(i)
                                    iface.interfaceClass == 14 || iface.interfaceClass == 239
                                })

                        if (isYjxC5 || isRealtek || isVideoClass) {
                            if (!usbManager.hasPermission(device)) {
                                registerUsbPermissionReceiver(device, flutterEngine)
                                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                    PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                                } else {
                                    PendingIntent.FLAG_UPDATE_CURRENT
                                }
                                val intent = Intent(ACTION_USB_PERMISSION).apply {
                                    setPackage(packageName)
                                }
                                val permissionIntent = PendingIntent.getBroadcast(this, 0, intent, flags)
                                usbManager.requestPermission(device, permissionIntent)
                                requested = true
                            } else {
                                // Already granted runtime permission
                                result.success(true)
                                return@setMethodCallHandler
                            }
                        }
                    }
                    result.success(requested)
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
