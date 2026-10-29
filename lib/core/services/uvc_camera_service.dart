import 'dart:async';
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

  UVCCameraController? _controller;
  UvcConnectionState _connectionState = UvcConnectionState.disconnected;
  String? _statusMessage;

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

  /// Attempts to find, request permission, and open the UVC camera device.
  /// Retries up to [maxAttempts] times with a short interval before falling back.
  Future<bool> initialize({int maxAttempts = 3}) async {
    if (_connectionState == UvcConnectionState.connecting) {
      debugPrint('[UvcCameraService] Connection attempt already in progress.');
      return false;
    }

    _connectionState = UvcConnectionState.connecting;
    _statusMessage = 'Connecting to smart glasses camera...';
    notifyListeners();

    try {
      // 1. Clean up any existing controller instance before reinitializing
      await _cleanupController();

      final ctrl = UVCCameraController();
      bool opened = false;

      ctrl.cameraStateCallback = (state) {
        debugPrint('[UvcCameraService] Native cameraStateCallback: $state');
        if (state == UVCCameraState.opened) {
          opened = true;
          _connectionState = UvcConnectionState.connected;
          _statusMessage = 'Smart glasses camera connected.';
          notifyListeners();
        } else if (state == UVCCameraState.closed) {
          _handleCameraClosed();
        }
      };

      _controller = ctrl;

      // 2. Open UVC Camera with retry loop
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        debugPrint('[UvcCameraService] Open UVC camera attempt $attempt of $maxAttempts...');
        try {
          await ctrl.openUVCCamera();
        } catch (e) {
          debugPrint('[UvcCameraService] openUVCCamera threw on attempt $attempt: $e');
        }

        // Wait briefly for the native opened callback
        await Future.delayed(const Duration(milliseconds: 1000));

        if (opened || _connectionState == UvcConnectionState.connected) {
          break;
        }
      }

      if (_connectionState == UvcConnectionState.connected) {
        debugPrint('[UvcCameraService] Smart glasses camera successfully opened.');
        return true;
      } else {
        debugPrint('[UvcCameraService] Smart glasses camera not opened — no device detected.');
        await _cleanupController();
        _connectionState = UvcConnectionState.disconnected;
        _statusMessage = null;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('[UvcCameraService] Initialization error: $e');
      await _cleanupController();
      _connectionState = UvcConnectionState.error;
      _statusMessage = 'Smart glasses connection error: $e';
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

      if (bytes.isNotEmpty) {
        _latestFrameBytes = bytes;
        _latestFrameTimestamp = DateTime.now();
        return bytes;
      }
      return null;
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
