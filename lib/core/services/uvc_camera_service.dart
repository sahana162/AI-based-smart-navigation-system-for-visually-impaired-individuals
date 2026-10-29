import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_uvc_camera/flutter_uvc_camera.dart';

/// Connection and streaming state of the USB UVC smart glasses camera.
enum UvcConnectionState {
  disconnected,
  connecting,
  connected,
  streaming,
  error,
}

/// Authoritative manager for external USB UVC camera (e.g. YJX-C5 / OV5648).
///
/// Features:
/// - Single controller lifecycle management (prevents multiple open controllers).
/// - Resilient state machine with automatic retry and callback recovery.
/// - In-memory frame buffer with continuous throttled 2 fps stream for background vision.
/// - On-demand zero-latency frame snapshots for real-time voice queries.
/// - Safe cleanup of native resources and temp files without disk pollution.
class UvcCameraService extends ChangeNotifier {
  static final UvcCameraService _instance = UvcCameraService._internal();

  /// Factory constructor to ensure singleton usage across screens and services.
  factory UvcCameraService() => _instance;

  UvcCameraService._internal();

  static const MethodChannel _usbPermissionChannel =
      MethodChannel('com.example.blind_navigation/usb_permissions');

  UVCCameraController? _controller;
  UvcConnectionState _connectionState = UvcConnectionState.disconnected;
  String? _statusMessage;
  bool _isUsbPermissionListenerSetup = false;
  Completer<bool>? _permissionCompleter;

  // Frame streaming & caching
  Timer? _streamTimer;
  bool _isCapturing = false;
  Uint8List? _latestFrameBytes;
  DateTime? _latestFrameTimestamp;
  final StreamController<Uint8List> _frameStreamController =
      StreamController<Uint8List>.broadcast();

  // Public Getters
  UVCCameraController? get controller => _controller;
  UvcConnectionState get connectionState => _connectionState;
  bool get isUvcConnected =>
      _connectionState == UvcConnectionState.connected ||
      _connectionState == UvcConnectionState.streaming;
  bool get isStreaming => _connectionState == UvcConnectionState.streaming;
  bool get isInitialized => isUvcConnected;
  String? get statusMessage => _statusMessage;
  Uint8List? get cachedFrame => _latestFrameBytes;
  Stream<Uint8List> get onFrameStream => _frameStreamController.stream;

  /// Native Android logging visible in logcat even in release mode.
  static void log(String message, {bool isError = false}) {
    developer.log(message, name: 'UvcCameraService');
    debugPrint('[UvcCameraService] $message');
    try {
      _usbPermissionChannel.invokeMethod('logNative', {
        'tag': 'UvcCameraService',
        'message': message,
        'isError': isError,
      });
    } catch (_) {}
  }

  /// Requests explicit Android OS runtime USB permission via UsbManager.
  Future<bool> requestUsbPermission() async {
    try {
      final bool? requested =
          await _usbPermissionChannel.invokeMethod<bool>('requestUsbPermission');
      log('requestUsbPermission invocation returned: $requested');
      return requested ?? false;
    } catch (e) {
      log('Native requestUsbPermission error: $e', isError: true);
      return false;
    }
  }

  /// Sets up broadcast listener for Android ACTION_USB_PERMISSION events.
  void _ensureUsbPermissionListener() {
    if (_isUsbPermissionListenerSetup) return;
    _isUsbPermissionListenerSetup = true;

    _usbPermissionChannel.setMethodCallHandler((call) async {
      if (call.method == 'onUsbPermissionResult') {
        final granted = call.arguments['granted'] as bool? ?? false;
        log('BroadcastReceiver onUsbPermissionResult: granted=$granted');
        if (_permissionCompleter != null && !_permissionCompleter!.isCompleted) {
          _permissionCompleter!.complete(granted);
        }
        if (granted) {
          _statusMessage = 'Opening camera feed (640x480)...';
          notifyListeners();
          try {
            await _controller?.initializeCamera();
            _controller?.updateResolution(PreviewSize(width: 640, height: 480));
            await _controller?.openUVCCamera();
          } catch (e) {
            log('openUVCCamera on permission grant error: $e', isError: true);
          }
        } else {
          _connectionState = UvcConnectionState.error;
          _statusMessage = 'USB permission denied by user.';
          notifyListeners();
        }
      }
    });
  }

  Future<bool> _waitForUsbPermission({Duration timeout = const Duration(seconds: 10)}) async {
    _permissionCompleter = Completer<bool>();
    try {
      return await _permissionCompleter!.future.timeout(timeout);
    } on TimeoutException {
      log('Timed out waiting for USB permission dialog grant.', isError: true);
      return false;
    }
  }

  /// Attempts to find, request permission, and open the UVC camera device.
  /// Explicitly queries UsbManager and negotiates 640x480 @ 30fps.
  Future<bool> initialize({int maxAttempts = 3}) async {
    if (_connectionState == UvcConnectionState.connecting) {
      log('Connection attempt already in progress.');
      return false;
    }

    _connectionState = UvcConnectionState.connecting;
    _statusMessage = 'Checking for smart glasses...';
    notifyListeners();

    try {
      _ensureUsbPermissionListener();

      // 1. Query connected USB devices from Android UsbManager
      Map<String, dynamic>? devInfo;
      try {
        final rawMap = await _usbPermissionChannel.invokeMapMethod<String, dynamic>('queryAndRequestUsbDevice');
        devInfo = rawMap;
      } catch (e) {
        log('queryAndRequestUsbDevice error: $e', isError: true);
      }

      final deviceFound = devInfo?['deviceFound'] as bool? ?? false;
      final devName = devInfo?['deviceName'] as String? ?? 'YJX-C5';
      final hasPermission = devInfo?['hasPermission'] as bool? ?? false;

      if (!deviceFound) {
        log('No smart glasses detected on USB OTG host.');
        _statusMessage = 'Waiting for Smart Glasses...';
        _connectionState = UvcConnectionState.disconnected;
        notifyListeners();
        return false;
      }

      log('USB device detected: $devName (hasPermission=$hasPermission)');

      // 2. Request permission if not yet granted
      if (!hasPermission) {
        _statusMessage = 'USB device detected: $devName. Requesting USB permission...';
        notifyListeners();
        log('Waiting for user to grant USB permission dialog...');

        final granted = await _waitForUsbPermission(timeout: const Duration(seconds: 10));
        if (!granted) {
          log('USB permission denied or dismissed for $devName.', isError: true);
          _connectionState = UvcConnectionState.error;
          _statusMessage = 'USB permission denied for $devName.';
          notifyListeners();
          return false;
        }
      }

      _statusMessage = 'Opening camera feed (640x480)...';
      notifyListeners();

      // 3. Ensure UVCCameraController is allocated & configured
      if (_controller == null) {
        final ctrl = UVCCameraController();
        ctrl.cameraStateCallback = (state) {
          log('Native cameraStateCallback: $state');
          if (state == UVCCameraState.opened) {
            _connectionState = UvcConnectionState.connected;
            _statusMessage = 'Smart glasses camera active (640x480 @ 30fps).';
            notifyListeners();
          } else if (state == UVCCameraState.closed) {
            _handleCameraClosed();
          } else if (state == UVCCameraState.error) {
            final errMsg = ctrl.getCameraErrorMsg;
            log('Native cameraStateCallback error: $errMsg', isError: true);
            if (errMsg.toLowerCase().contains('permission denied')) {
              _connectionState = UvcConnectionState.error;
              _statusMessage = 'USB permission denied for smart glasses.';
              notifyListeners();
            }
          }
        };
        _controller = ctrl;
      }

      final ctrl = _controller!;

      // 4. Initialize camera platform view & hardcode 640x480 resolution negotiation
      try {
        await ctrl.initializeCamera();
        ctrl.updateResolution(PreviewSize(width: 640, height: 480));
      } catch (e) {
        log('initializeCamera error: $e', isError: true);
      }

      // 5. Open UVC Camera with retry loop
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        log('Open UVC camera attempt $attempt of $maxAttempts for $devName...');
        try {
          await ctrl.openUVCCamera();
        } catch (e) {
          log('openUVCCamera threw on attempt $attempt: $e', isError: true);
        }

        // Wait briefly for native opened callback
        await Future.delayed(const Duration(milliseconds: 1000));

        if (_connectionState == UvcConnectionState.connected) {
          break;
        }
      }

      if (_connectionState == UvcConnectionState.connected) {
        _statusMessage = 'Smart glasses camera active (640x480 @ 30fps).';
        notifyListeners();
        log('Smart glasses camera successfully opened at 640x480.');
        return true;
      } else {
        log('Smart glasses camera opening pending or device busy.');
        if (_connectionState != UvcConnectionState.error) {
          _connectionState = UvcConnectionState.disconnected;
          _statusMessage = 'Opening camera feed (640x480)...';
        }
        notifyListeners();
        return false;
      }
    } catch (e) {
      log('Initialization error: $e', isError: true);
      _connectionState = UvcConnectionState.error;
      _statusMessage = 'Connection error: $e';
      notifyListeners();
      return false;
    }
  }

  /// Starts throttled in-memory frame capture (default: 2 fps) for background
  /// pedestrian safety, collision, and obstacle scanning.
  void startStreaming({int targetFps = 2}) {
    if (!isUvcConnected || _controller == null) {
      debugPrint('[UvcCameraService] Cannot start streaming: camera not connected.');
      return;
    }
    if (_streamTimer != null && _streamTimer!.isActive) {
      return; // Already streaming
    }

    _connectionState = UvcConnectionState.streaming;
    notifyListeners();

    final intervalMs = (1000 / targetFps.clamp(1, 10)).round();
    debugPrint('[UvcCameraService] Starting in-memory frame stream at $targetFps fps ($intervalMs ms interval).');

    _streamTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      if (!isUvcConnected || _controller == null) {
        stopStreaming();
        return;
      }
      final frame = await captureFrame();
      if (frame != null && !_frameStreamController.isClosed) {
        _frameStreamController.add(frame);
      }
    });
  }

  /// Stops the background streaming timer while preserving the camera connection.
  void stopStreaming() {
    _streamTimer?.cancel();
    _streamTimer = null;
    if (_connectionState == UvcConnectionState.streaming) {
      _connectionState = UvcConnectionState.connected;
      notifyListeners();
    }
  }

  /// Captures a single JPEG frame in-memory from the UVC camera.
  /// Safely cleans up the temporary file immediately after reading bytes into memory.
  Future<Uint8List?> captureFrame() async {
    if (!isUvcConnected || _controller == null) return null;
    if (_isCapturing) return _latestFrameBytes; // Prevent overlapping capture requests

    _isCapturing = true;
    try {
      if (_controller == null || !isUvcConnected) return null;
      final String? filePath = await _controller!.takePicture();
      if (filePath == null || filePath.isEmpty) return null;

      final file = File(filePath);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();

      // Clean up the temporary file immediately to prevent disk pollution
      try {
        await file.delete();
      } catch (_) {}

      // Frame Sizing & Crash Guard: Ensure any buffer < 1000 bytes during hot-plug
      // handshakes is safely dropped before decoding to prevent native JNI segmentation faults.
      if (bytes.length >= 1000) {
        _latestFrameBytes = bytes;
        _latestFrameTimestamp = DateTime.now();
        return bytes;
      } else {
        debugPrint('[UvcCameraService] Dropped truncated UVC frame (${bytes.length} bytes < 1000 bytes threshold).');
        return null;
      }
    } on PlatformException catch (e) {
      debugPrint('[UvcCameraService] PlatformException during capture (device disconnected): $e');
      _handleCameraClosed();
      return null;
    } catch (e) {
      debugPrint('[UvcCameraService] Frame capture error: $e');
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('disconnect') ||
          errorStr.contains('closed') ||
          errorStr.contains('null') ||
          errorStr.contains('dead') ||
          errorStr.contains('jni') ||
          errorStr.contains('usb')) {
        _handleCameraClosed();
      }
      return null;
    } finally {
      _isCapturing = false;
    }
  }

  /// Returns the most recent in-memory frame snapshot.
  /// If the cached frame is fresh (<500ms old) and [forceFresh] is false,
  /// returns cached bytes immediately with zero latency.
  Future<Uint8List?> getLatestFrame({bool forceFresh = false}) async {
    if (!isUvcConnected) return null;

    final now = DateTime.now();
    if (!forceFresh &&
        _latestFrameBytes != null &&
        _latestFrameTimestamp != null &&
        now.difference(_latestFrameTimestamp!).inMilliseconds < 500) {
      return _latestFrameBytes;
    }

    return await captureFrame();
  }

  /// Handles unexpected native disconnect or cable pull.
  void _handleCameraClosed() {
    debugPrint('[UvcCameraService] Camera disconnected or closed by OS/device.');
    stopStreaming();
    _connectionState = UvcConnectionState.disconnected;
    _statusMessage = 'Smart glasses disconnected.';
    _latestFrameBytes = null;
    _latestFrameTimestamp = null;
    _controller = null;
    notifyListeners();
  }

  /// Safely cleans up controller references.
  Future<void> _cleanupController() async {
    stopStreaming();
    if (_controller != null) {
      try {
        _controller!.closeCamera();
      } catch (e) {
        debugPrint('[UvcCameraService] Error closing controller: $e');
      }
      _controller = null;
    }
  }

  @override
  void dispose() {
    _cleanupController();
    _frameStreamController.close();
    super.dispose();
  }
}
