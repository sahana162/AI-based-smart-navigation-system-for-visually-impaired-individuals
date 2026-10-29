import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/pedestrian_navigation_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/vision_service.dart';
import '../../core/services/voice_command_parser.dart';
import '../../core/services/voice_session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/voice_command.dart';
import '../widgets/accessible_button.dart';
import '../widgets/live_waveform_visualizer.dart';
import '../widgets/mic_button.dart';
import '../widgets/viewfinder_reticle.dart';
import 'feature_detail_screen.dart';
import '../../core/services/uvc_camera_service.dart';
import 'package:flutter_uvc_camera/flutter_uvc_camera.dart';

class NavigationScreen extends StatefulWidget {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService speechService;
  final String? initialDestination;
  final String? initialVisionAction;
  final String? initialVisionArg;
  final String? initialOcrMode;
  final bool? isSavedLookup;
  final String? savedNotes;
  final bool promptDestinationOnLoad;
  final PedestrianNavigationService? navigationService;
  final VisionService? visionService;
  final VoiceSessionCoordinator? voiceCoordinator;
  final UvcCameraService? uvcCameraService;

  const NavigationScreen({
    super.key,
    required this.storageService,
    required this.ttsService,
    required this.speechService,
    this.initialDestination,
    this.initialVisionAction,
    this.initialVisionArg,
    this.initialOcrMode,
    this.isSavedLookup,
    this.savedNotes,
    this.promptDestinationOnLoad = false,
    this.navigationService,
    this.visionService,
    this.voiceCoordinator,
    this.uvcCameraService,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver
    implements NavigationVoiceDelegate {
  // ── Dual Camera Support (External Smart Glasses vs Internal Phone Camera) ───
  late final UvcCameraService _uvcService;
  bool _lastUvcConnectedState = false;
  bool _isGlassesConnected = false;
  CameraController? _phoneCameraController;
  bool _usePhoneCamera = false;

  bool _isCameraInitialized = false;
  bool _isPermissionDenied = false;
  bool _isTorchOn = false;
  int _darkFrameCount = 0;
  String _statusMessage = 'Initializing camera...';
  final List<CameraDescription> _availableCameras = [];

  bool get _isUvcActive => !_usePhoneCamera && _isGlassesConnected;
  bool get _isAnyCameraActive => _usePhoneCamera
      ? (_phoneCameraController != null && _phoneCameraController!.value.isInitialized)
      : (_isGlassesConnected && _uvcService.controller != null);

  bool _isLiveMonitoringActive = false;
  bool _isProcessingFrame = false;
  StreamSubscription<Uint8List>? _uvcStreamSubscription;
  final Map<String, DateTime> _objectAlertCooldowns = {};
  DateTime? _lastFrameProcessTime;
  bool _isIdentifyingFriend = false;
  DateTime? _lastFriendScanTime;
  final Map<String, DateTime> _friendCooldowns = {};

  late final PedestrianNavigationService _navService;
  bool _isLocalNavService = false;

  late final VisionService _visionService;
  bool _isLocalVisionService = false;

  @override
  String get screenName => 'Navigation';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.voiceCoordinator?.registerDelegate(this);

    _uvcService = widget.uvcCameraService ?? UvcCameraService();
    _lastUvcConnectedState = _uvcService.isUvcConnected;
    _isGlassesConnected = _uvcService.isUvcConnected;
    _uvcService.addListener(_onUvcServiceChanged);

    if (widget.navigationService != null) {
      _navService = widget.navigationService!;
    } else {
      _navService = PedestrianNavigationService(
        ttsService: widget.ttsService,
        storageService: widget.storageService,
      );
      _isLocalNavService = true;
    }

    if (widget.visionService != null) {
      _visionService = widget.visionService!;
    } else {
      _visionService = VisionService();
      _isLocalVisionService = true;
    }

    _navService.addListener(_onNavServiceUpdated);
    _usePhoneCamera = widget.storageService.usePhoneCamera;
    _initializeCamera();

    if (widget.initialDestination != null && widget.initialDestination!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navService.startNavigationToDestination(widget.initialDestination!);
      });
    } else if (widget.promptDestinationOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptForDestination();
      });
    }
  }

  void _onUvcServiceChanged() {
    if (!mounted) return;
    final currentlyConnected = _uvcService.isUvcConnected;
    if (_lastUvcConnectedState != currentlyConnected) {
      final wasConnected = _lastUvcConnectedState;
      _lastUvcConnectedState = currentlyConnected;

      if (wasConnected && !currentlyConnected && !_usePhoneCamera) {
        // Disconnected while actively using glasses:
        // Spoken alert + heavy vibration + auto-switch to phone camera
        debugPrint('[NavigationScreen] Glasses disconnected! Initiating auto-fallback to phone camera.');
        HapticFeedback.heavyImpact();
        widget.ttsService.speak('Glasses disconnected. Switching to phone camera.');
        _switchCameraSource(true);
      } else if (!wasConnected && currentlyConnected) {
        // Reconnected or runtime USB permission granted:
        // Spoken alert + medium vibration + auto-restore glasses
        debugPrint('[NavigationScreen] Glasses connected! Restoring glasses stream.');
        HapticFeedback.mediumImpact();
        widget.ttsService.speak('Glasses connected.');
        if (_usePhoneCamera) {
          _switchCameraSource(false);
        } else {
          if (widget.storageService.obstacleAlertsDefaultEnabled) {
            _startLiveObstacleMonitoring();
          }
        }
      }
    }

    setState(() {
      _isGlassesConnected = _uvcService.isUvcConnected;
      if (_isGlassesConnected && !_usePhoneCamera) {
        _isCameraInitialized = true;
        _statusMessage = _uvcService.statusMessage ?? 'Smart glasses camera active. Forward path monitored.';
      } else if (!_usePhoneCamera) {
        _statusMessage = _uvcService.statusMessage ?? _statusMessage;
      }
    });

    if (_isGlassesConnected && widget.initialVisionAction != null && mounted) {
      _runInitialVisionAction(
        widget.initialVisionAction!,
        widget.initialVisionArg,
        ocrMode: widget.initialOcrMode,
        isSavedLookup: widget.isSavedLookup ?? false,
        savedNotes: widget.savedNotes,
      );
    }
  }

  void _onNavServiceUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopLiveObstacleMonitoring();
      if (_phoneCameraController != null && _phoneCameraController!.value.isInitialized) {
        _phoneCameraController?.dispose();
        _phoneCameraController = null;
      }
      _uvcService.stopStreaming();
      _isCameraInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      if (!_isPermissionDenied) {
        _initializeCamera();
      }
    }
  }

  // ── Camera Initialization & Pipeline Orchestrator ─────────────────────────

  /// Primary camera initializer.
  /// Selects either Smart Glasses (UVC) or internal Phone camera according to user preference.
  Future<void> _initializeCamera() async {
    _usePhoneCamera = widget.storageService.usePhoneCamera;
    if (_usePhoneCamera) {
      await _initPhoneCamera();
    } else {
      await _initUvcPipeline();
    }
  }

  /// Toggles between Smart Glasses and Phone Camera.
  Future<void> _toggleCameraSource() async {
    await _switchCameraSource(!_usePhoneCamera);
  }

  /// Switches active camera mode between Smart Glasses and Phone Camera.
  Future<void> _switchCameraSource(bool toPhone) async {
    HapticFeedback.mediumImpact();
    if (_usePhoneCamera == toPhone && _isCameraInitialized) return;

    setState(() {
      _usePhoneCamera = toPhone;
      _isCameraInitialized = false;
      _statusMessage = toPhone
          ? 'Switching to phone camera...'
          : 'Switching to smart glasses camera...';
    });
    await widget.storageService.setUsePhoneCamera(toPhone);

    if (toPhone) {
      await _stopLiveObstacleMonitoring();
      _uvcService.stopStreaming();
      await _initPhoneCamera();
    } else {
      await _stopLiveObstacleMonitoring();
      if (_phoneCameraController != null) {
        try {
          if (_phoneCameraController!.value.isStreamingImages) {
            await _phoneCameraController!.stopImageStream();
          }
          await _phoneCameraController!.dispose();
        } catch (_) {}
        _phoneCameraController = null;
      }
      await _initUvcPipeline();
    }
  }

  /// Initializes internal phone camera
  Future<void> _initPhoneCamera() async {
    if (mounted) {
      setState(() => _statusMessage = 'Starting phone camera...');
    }

    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _isPermissionDenied = true;
          _statusMessage = 'Camera permission denied.';
        });
      }
      widget.ttsService.speak('Camera permission denied.');
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _statusMessage = 'No phone camera found.');
        return;
      }
      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final ctrl = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      setState(() {
        _phoneCameraController = ctrl;
        _isCameraInitialized = true;
        _statusMessage = 'Phone camera active. Forward path monitored.';
      });
      widget.ttsService.speak('Phone camera active.');

      if (widget.storageService.obstacleAlertsDefaultEnabled) {
        _startLiveObstacleMonitoring();
      }

      if (widget.initialVisionAction != null && mounted) {
        _runInitialVisionAction(
          widget.initialVisionAction!,
          widget.initialVisionArg,
          ocrMode: widget.initialOcrMode,
          isSavedLookup: widget.isSavedLookup ?? false,
          savedNotes: widget.savedNotes,
        );
      }
    } catch (e) {
      debugPrint('[NavigationScreen] Phone camera init error: $e');
      if (mounted) {
        setState(() => _statusMessage = 'Phone camera error: $e');
      }
    }
  }

  /// Probes and initiates handshake with the Smart Glasses UVC Camera.
  /// Includes retry loop so when the user confirms the Android USB dialog,
  /// the active pipeline claims the granted device handle immediately.
  Future<void> _initUvcPipeline() async {
    if (mounted) {
      setState(() => _statusMessage = 'Waiting for Smart Glasses...');
    }

    // 1. Request microphone and camera permissions required by Android for composite audio/video
    await Permission.microphone.request();
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _isPermissionDenied = true;
          _statusMessage =
              'Camera permission denied. Visual navigation cannot proceed without camera access.';
        });
      }
      await widget.ttsService.speak(
        'Camera permission was denied. Please allow camera access in app settings to use visual navigation.',
      );
      return;
    }

    try {
      if (mounted) setState(() {});
      final connected = await _uvcService.initialize();
      if (connected && mounted) {
        setState(() {
          _isGlassesConnected = true;
          _isCameraInitialized = true;
          _statusMessage = 'Smart glasses camera active. Forward path monitored.';
        });

        if (widget.storageService.obstacleAlertsDefaultEnabled) {
          _startLiveObstacleMonitoring();
        }
      } else if (mounted) {
        setState(() {
          _isGlassesConnected = _uvcService.isUvcConnected;
          _statusMessage = _uvcService.statusMessage ?? 'Waiting for Smart Glasses...';
        });
      }
    } catch (e) {
      debugPrint('[NavigationScreen] UVC initialization error: $e');
    }
  }

  void _startLiveObstacleMonitoring() {
    if (_isLiveMonitoringActive) return;

    if (_isUvcActive) {
      _isLiveMonitoringActive = true;
      if (mounted) setState(() {});
      _uvcStreamSubscription?.cancel();
      _uvcStreamSubscription = _uvcService.onFrameStream.listen(_handleUvcFrame);
      _uvcService.startStreaming(targetFps: 2);
      debugPrint('[NavigationScreen] Smart glasses live obstacle streaming started.');
      return;
    }

    if (_phoneCameraController == null || !_phoneCameraController!.value.isInitialized) return;

    _isLiveMonitoringActive = true;
    if (mounted) setState(() {});

    try {
      _phoneCameraController!.startImageStream(_handleCameraFrame);
      debugPrint('[NavigationScreen] Live obstacle streaming started.');
    } catch (e) {
      debugPrint('[NavigationScreen] Error starting image stream: $e');
    }
  }

  Future<void> _stopLiveObstacleMonitoring() async {
    if (!_isLiveMonitoringActive) return;
    _isLiveMonitoringActive = false;
    if (mounted) setState(() {});

    _uvcStreamSubscription?.cancel();
    _uvcStreamSubscription = null;
    _uvcService.stopStreaming();

    try {
      if (_phoneCameraController?.value.isStreamingImages ?? false) {
        await _phoneCameraController!.stopImageStream();
        debugPrint('[NavigationScreen] Live obstacle streaming stopped.');
      }
    } catch (e) {
      debugPrint('[NavigationScreen] Error stopping image stream: $e');
    }
  }

  Future<void> _handleUvcFrame(Uint8List frameBytes) async {
    if (!_isLiveMonitoringActive || _isProcessingFrame) return;
    if (frameBytes.length < 1000) return; // Guard against corrupted or truncated frames

    final now = DateTime.now();
    // Throttle UVC inference to at least 450ms
    if (_lastFrameProcessTime != null && now.difference(_lastFrameProcessTime!).inMilliseconds < 450) {
      return;
    }

    _lastFrameProcessTime = now;
    _isProcessingFrame = true;

    try {
      final items = await _visionService.detectObjectsFromBytes(frameBytes);
      if (!mounted || !_isLiveMonitoringActive) return;
      await _processDetectedObstacles(items, now);
    } catch (e) {
      debugPrint('[NavigationScreen] UVC live frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _processDetectedObstacles(List<DetectedVisionItem> items, DateTime now) async {
    final obstacles = items.where((i) => i.isHighConfidence && (i.proximity == 'close' || i.proximity == 'near')).toList();

    if (obstacles.isNotEmpty) {
      obstacles.sort((a, b) => a.proximity == 'close' ? -1 : 1);
      final mostUrgent = obstacles.first;

      // Critical path check: If obstacle is directly ahead (< 1.2m) or overhead, bypass cooldown
      final bool isCriticalForwardHazard = (mostUrgent.position == 'center' && (mostUrgent.estimatedDistanceMeters ?? 99.0) < 1.2) ||
          mostUrgent.isOverheadHazard;

      // 12-second fatigue suppression window per object class
      final lastAnnouncedTime = _objectAlertCooldowns[mostUrgent.label];
      final int elapsedSec = lastAnnouncedTime == null ? 999 : now.difference(lastAnnouncedTime).inSeconds;
      final bool shouldAnnounce = isCriticalForwardHazard || elapsedSec >= 12;

      if (shouldAnnounce) {
        _objectAlertCooldowns[mostUrgent.label] = now;

        final bool isKn = widget.ttsService.isKannada;
        final bool useSonar = widget.storageService.sonarCuesEnabled;
        final String spokenAlert;
        final distStr = mostUrgent.estimatedDistanceMeters != null
            ? '${mostUrgent.estimatedDistanceMeters}m'
            : '';

        if (isKn) {
          final labelKn = VisionService.translateLabelToKannada(mostUrgent.label);
          if (mostUrgent.isOverheadHazard) {
            spokenAlert = 'ಎಚ್ಚರಿಕೆ! ತಲೆಯ ಮಟ್ಟದಲ್ಲಿ $labelKn: 12 ಗಂಟೆ, ಬಾಗಿ ಅಥವಾ ನಿಲ್ಲಿ.';
            if (useSonar) SystemSound.play(SystemSoundType.click);
            HapticFeedback.heavyImpact();
          } else if (mostUrgent.proximity == 'close' && mostUrgent.position == 'center') {
            final dText = distStr.isNotEmpty ? 'ಸುಮಾರು ${mostUrgent.estimatedDistanceMeters} ಮೀಟರ್' : 'ಸಮೀಪದಲ್ಲಿದೆ';
            spokenAlert = 'ಎಚ್ಚರಿಕೆ! $labelKn: 12 ಗಂಟೆ, $dText.';
            if (useSonar) SystemSound.play(SystemSoundType.click);
            HapticFeedback.heavyImpact();
          } else if (mostUrgent.position == 'center') {
            final dText = distStr.isNotEmpty ? ', ಸುಮಾರು ${mostUrgent.estimatedDistanceMeters} ಮೀಟರ್' : '';
            spokenAlert = 'ಮುಂದೆ ಅಡೆತಡೆ: $labelKn$dText.';
            if (useSonar) SystemSound.play(SystemSoundType.click);
            HapticFeedback.heavyImpact();
          } else {
            final posKn = mostUrgent.position == 'left' ? 'ಎಡಕ್ಕೆ' : 'ಬಲಕ್ಕೆ';
            spokenAlert = '$labelKn: ${mostUrgent.clockPosition}, ನಿಮ್ಮ $posKn.';
            if (mostUrgent.position == 'left') {
              HapticFeedback.mediumImpact();
            } else {
              HapticFeedback.selectionClick();
            }
          }
        } else {
          if (mostUrgent.isOverheadHazard) {
            spokenAlert = 'Warning! Head-level obstacle: ${mostUrgent.label}, 12 o\'clock.';
            if (useSonar) SystemSound.play(SystemSoundType.click);
            HapticFeedback.heavyImpact();
          } else if (mostUrgent.proximity == 'close' && mostUrgent.position == 'center') {
            final dText = distStr.isNotEmpty ? 'about ${mostUrgent.estimatedDistanceMeters} meters away' : 'close by';
            spokenAlert = 'Caution! ${mostUrgent.label}: 12 o\'clock, $dText.';
            if (useSonar) SystemSound.play(SystemSoundType.click);
            HapticFeedback.heavyImpact();
          } else if (mostUrgent.position == 'center') {
            final dText = distStr.isNotEmpty ? ' about ${mostUrgent.estimatedDistanceMeters} meters away' : '';
            spokenAlert = 'Obstacle ahead: ${mostUrgent.label}$dText.';
            if (useSonar) SystemSound.play(SystemSoundType.click);
            HapticFeedback.heavyImpact();
          } else {
            spokenAlert = '${mostUrgent.label}: ${mostUrgent.clockPosition}, on your ${mostUrgent.position}.';
            if (mostUrgent.position == 'left') {
              HapticFeedback.mediumImpact();
            } else {
              HapticFeedback.selectionClick();
            }
          }
        }

        setState(() {
          _statusMessage = spokenAlert;
        });

        final bool isGeminiLiveActive = widget.storageService.useGeminiLive &&
            widget.storageService.geminiApiKey.isNotEmpty;

        if (isGeminiLiveActive) {
          if (useSonar) SystemSound.play(SystemSoundType.click);
          if (mostUrgent.isOverheadHazard || (mostUrgent.proximity == 'close' && mostUrgent.position == 'center')) {
            HapticFeedback.heavyImpact();
          } else if (mostUrgent.position == 'center') {
            HapticFeedback.mediumImpact();
          } else {
            HapticFeedback.lightImpact();
          }
        } else {
          if (useSonar) SystemSound.play(SystemSoundType.click);
          if (mostUrgent.isOverheadHazard || (mostUrgent.proximity == 'close' && mostUrgent.position == 'center')) {
            HapticFeedback.heavyImpact();
          } else if (mostUrgent.position == 'center') {
            HapticFeedback.mediumImpact();
          } else {
            HapticFeedback.lightImpact();
          }
          await widget.ttsService.speak(spokenAlert, priority: TtsPriority.hazard);
        }
      } else if (mostUrgent.proximity == 'close' || mostUrgent.position == 'center') {
        if (widget.storageService.sonarCuesEnabled) {
          SystemSound.play(SystemSoundType.click);
        }
        HapticFeedback.selectionClick();
      }
    }
  }

  Future<void> _handleCameraFrame(CameraImage image) async {
    if (!_isLiveMonitoringActive || _isProcessingFrame) return;

    final now = DateTime.now();
    // Throttle inference: process 1 frame every 750 milliseconds
    if (_lastFrameProcessTime != null && now.difference(_lastFrameProcessTime!).inMilliseconds < 750) {
      return;
    }

    _lastFrameProcessTime = now;
    _isProcessingFrame = true;

    try {
      // Auto-exposure dark environment detection & auto-torch
      if (image.planes.isNotEmpty && image.planes.first.bytes.isNotEmpty) {
        final bytes = image.planes.first.bytes;
        int totalLum = 0;
        final int sampleStep = (bytes.length / 40).floor().clamp(1, 1000);
        int sampleCount = 0;
        for (int i = 0; i < bytes.length; i += sampleStep) {
          totalLum += bytes[i];
          sampleCount++;
        }
        if (sampleCount > 0) {
          final double avgLum = totalLum / sampleCount;
          if (avgLum < 20 && !_isTorchOn && widget.storageService.autoTorchEnabled) {
            _darkFrameCount++;
            if (_darkFrameCount >= 3) {
              _darkFrameCount = 0;
              _toggleTorch(true);
            }
          } else if (avgLum > 100) {
            _darkFrameCount = 0;
          }
        }
      }

      final sensorOrientation = _availableCameras.isNotEmpty
          ? _availableCameras.first.sensorOrientation
          : 90;

      final items = await _visionService.detectObjectsFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
      );

      if (!mounted || !_isLiveMonitoringActive) return;
      await _processDetectedObstacles(items, now);

      // Friend face recognition & proximity reminder
      final savedFriends = widget.storageService.getSavedFriends();
      if (savedFriends.isNotEmpty && widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
        final nearbyPersons = items.where((i) =>
            i.label.toLowerCase() == 'person' &&
            (i.proximity == 'close' || i.proximity == 'near' || (i.estimatedDistanceMeters != null && i.estimatedDistanceMeters! < 3.0))
        ).toList();

        if (nearbyPersons.isNotEmpty && !_isIdentifyingFriend) {
          final person = nearbyPersons.first;
          final lastCheckElapsed = _lastFriendScanTime == null
              ? 999
              : now.difference(_lastFriendScanTime!).inSeconds;

          if (lastCheckElapsed >= 4) {
            _lastFriendScanTime = now;
            _checkApproachingFriendProximity(person, savedFriends);
          }
        }
      }
    } catch (e) {
      debugPrint('[NavigationScreen] Live frame processing error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<XFile?> _captureImageSafely() async {
    if (_usePhoneCamera) {
      if (_phoneCameraController == null || !_phoneCameraController!.value.isInitialized) {
        debugPrint('[_captureImageSafely] Phone camera not ready.');
        return null;
      }
      try {
        final photo = await _phoneCameraController!.takePicture();
        return photo;
      } catch (e) {
        debugPrint('[_captureImageSafely] Phone camera error: $e');
        return null;
      }
    }

    if (!_isGlassesConnected || _uvcService.controller == null) {
      debugPrint('[_captureImageSafely] Smart glasses camera not ready.');
      return null;
    }

    try {
      final frameBytes = await _uvcService.getLatestFrame(forceFresh: true);
      if (frameBytes != null && frameBytes.isNotEmpty) {
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/uvc_frame_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(frameBytes);
        return XFile(tempFile.path);
      }
    } catch (e) {
      debugPrint('[_captureImageSafely] UVC capture error: $e');
    }
    return null;
  }

  Future<void> _runInitialVisionAction(
    String action,
    String? arg, {
    String? ocrMode,
    bool isSavedLookup = false,
    String? savedNotes,
  }) async {
    // Wait for active camera to be ready
    int waitCount = 0;
    while (!_isCameraInitialized && waitCount < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }
    switch (action) {
      case 'describe':
        await _describeSurroundings();
        break;
      case 'detect':
      case 'obstacles':
        if (!_isLiveMonitoringActive) {
          _startLiveObstacleMonitoring();
        }
        await _detectObjects();
        break;
      case 'ocr':
        final mode = ocrMode == 'all'
            ? OcrReadingMode.all
            : (ocrMode == 'continue' ? OcrReadingMode.continueReading : OcrReadingMode.smart);
        await _readText(mode: mode);
        break;
      case 'currency':
        await _recognizeCurrency();
        break;
      case 'bus':
        await _recognizeBusRoute();
        break;
      case 'trafficLight':
        await _checkTrafficLight();
        break;
      case 'find':
        await _findItem(arg ?? 'item', isSavedLookup: isSavedLookup, savedNotes: savedNotes);
        break;
      case 'whoIsHere':
        await _whoIsHere();
        break;
      case 'enroll':
      case 'enrollFriend':
        if (widget.voiceCoordinator != null) {
          await widget.voiceCoordinator!.enrollFriend(arg ?? 'Friend');
        }
        break;
      case 'torch':
        final state = arg == 'on' ? true : (arg == 'off' ? false : null);
        await _toggleTorch(state);
        break;
      case 'toggleAlerts':
        if (_isLiveMonitoringActive) {
          await _stopLiveObstacleMonitoring();
          await widget.ttsService.speak(
            widget.ttsService.isKannada ? 'ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ವಿರಾಮಗೊಳಿಸಲಾಗಿದೆ.' : 'Live obstacle alerts paused.',
          );
        } else {
          _startLiveObstacleMonitoring();
          await widget.ttsService.speak(
            widget.ttsService.isKannada ? 'ಲೈವ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳು ಸಕ್ರಿಯವಾಗಿವೆ.' : 'Live obstacle alerts active.',
          );
        }
        break;
      default:
        await _describeSurroundings();
        break;
    }
  }

  void _safeDeleteFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.delete().catchError((_) => file);
      }
    } catch (_) {}
  }

  void _triggerEmergency() {
    HapticFeedback.heavyImpact();
    final contact = widget.storageService.emergencyContact;
    final isKn = widget.ttsService.isKannada;
    widget.ttsService.emergencySpeak(
      isKn
          ? 'ತುರ್ತು ಮೋಡ್ ಸಕ್ರಿಯವಾಗಿದೆ. ತುರ್ತು ಸಂಪರ್ಕ: $contact. ಸಹಾಯಕ್ಕಾಗಿ 112 ಕರೆ ಮಾಡಿ.'
          : 'Emergency alert activated. Emergency contact is $contact. Calling 112 if needed.',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeatureDetailScreen(
          title: isKn ? 'ತುರ್ತು ಸಹಾಯ' : 'Emergency SOS',
          status: isKn ? 'ಲಭ್ಯವಿದೆ' : 'Active',
          explanation: isKn
              ? 'ತುರ್ತು ಸಂಪರ್ಕ: $contact. ತಕ್ಷಣ ಸ್ಥಳೀಯ ತುರ್ತು ಸೇವೆಗಳಿಗೆ ಕರೆ ಮಾಡಿ.'
              : 'Emergency contact: $contact. Call local emergency services immediately for medical or physical danger.',
          technicalNotes: 'Direct phone dial and GPS location guidance.',
          icon: Icons.emergency,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          storageService: widget.storageService,
          voiceCoordinator: widget.voiceCoordinator,
          assistantName: widget.storageService.assistantName,
        ),
      ),
    );
  }

  Future<void> _describeSurroundings() async {
    if (!_isAnyCameraActive) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    final bool isKn = widget.ttsService.isKannada;
    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final prompt = isKn
          ? 'ನನ್ನ ಮುಂದೆ ಮತ್ತು ಸುತ್ತಮುತ್ತ ಏನಿದೆ ಎಂಬುದನ್ನು ಎಡ, ಮಧ್ಯ, ಬಲ ದಿಕ್ಕಿನಲ್ಲಿ ವಿವರಿಸಿ.'
          : 'Describe what is around me and in front of me, guiding me spatially (left, center, right).';
      await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final preview = _phoneCameraController?.value.previewSize;
      final width = preview?.width.toDouble() ?? 720.0;

      final description = await _visionService.describeSceneFromPath(
        xFile.path,
        imageWidth: width,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = description;
      });
      await widget.ttsService.speak(description);
    } catch (e) {
      debugPrint('Describe surroundings error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ ಪಡೆಯಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not inspect surroundings: $e',
      );
    } finally {
      _safeDeleteFile(tempPath);
    }
  }

  Future<void> _detectObjects() async {
    if (!_isAnyCameraActive) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    final bool isKn = widget.ttsService.isKannada;
    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final prompt = isKn
          ? 'ನನ್ನ ಮುಂದೆ ಇರುವ ಅಡೆತಡೆಗಳು ಮತ್ತು ವಸ್ತುಗಳನ್ನು ಎಡ, ಮಧ್ಯ, ಬಲ ದಿಕ್ಕಿನಲ್ಲಿ ತಿಳಿಸಿ.'
          : 'Identify any obstacles or objects directly in front of me and guide me spatially (left, center, right).';
      await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final preview = _phoneCameraController?.value.previewSize;
      final width = preview?.width.toDouble() ?? 720.0;

      final items = await _visionService.detectObjectsFromPath(
        xFile.path,
        imageWidth: width,
      );

      final bool isKn = widget.ttsService.isKannada;
      final String message;
      if (items.isEmpty) {
        message = isKn
            ? 'ನೇರವಾಗಿ ಮುಂದೆ ಯಾವುದೇ ಅಡೆತಡೆಗಳು ಅಥವಾ ವಸ್ತುಗಳು ಪತ್ತೆಯಾಗಿಲ್ಲ.'
            : 'No obstacles or objects detected directly ahead.';
      } else {
        if (isKn) {
          final summary = items.map((i) {
            final labelKn = VisionService.translateLabelToKannada(i.label);
            final posKn = i.position == 'left'
                ? 'ಎಡಕ್ಕೆ'
                : (i.position == 'right' ? 'ಬಲಕ್ಕೆ' : 'ಮುಂದೆ');
            return '$labelKn ನಿಮ್ಮ $posKn';
          }).toSet().join(', ');
          message = 'ಪತ್ತೆಯಾದವು: $summary.';
        } else {
          final summary = items.map((i) => '${i.label} on your ${i.position}').toSet().join(', ');
          message = 'Detected: $summary.';
        }
      }

      setState(() {
        _statusMessage = message;
      });
      await widget.ttsService.speak(message);
    } catch (e) {
      debugPrint('Detect objects error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ವಸ್ತುಗಳನ್ನು ಪತ್ತೆಹಚ್ಚಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not detect objects: $e',
      );
    } finally {
      _safeDeleteFile(tempPath);
    }
  }

  Future<void> _readText({OcrReadingMode mode = OcrReadingMode.smart}) async {
    if (!_isAnyCameraActive) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    final bool isKn = widget.ttsService.isKannada;
    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final prompt = isKn
          ? 'ಈ ಕ್ಯಾಮೆರಾ ನೋಟದಲ್ಲಿರುವ ಪ್ರಮುಖ ಸೈನ್ ಬೋರ್ಡ್‌ಗಳು ಮತ್ತು ಪಠ್ಯವನ್ನು ನಿಖರವಾಗಿ ಓದಿ.'
          : 'Read the relevant signs, labels, or text in this view accurately.';
      await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final text = await _visionService.recognizeTextFromPath(
        xFile.path,
        mode: mode,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = text;
      });
      await widget.ttsService.speak(text);
    } catch (e) {
      debugPrint('Read text error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಪಠ್ಯವನ್ನು ಓದಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Unable to read text: $e',
      );
    } finally {
      _safeDeleteFile(tempPath);
    }
  }

  Future<void> _findItem(
    String target, {
    bool isSavedLookup = false,
    String? savedNotes,
  }) async {
    if (!_isAnyCameraActive) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    // Clean itemName if needed (e.g. "my keys" -> "keys", "ನನ್ನ ಬಾಟಲ್" -> "ಬಾಟಲ್")
    String itemName = target.trim();
    if (itemName.toLowerCase().startsWith('my ')) {
      itemName = itemName.substring(3).trim();
    } else if (itemName.startsWith('ನನ್ನ ')) {
      itemName = itemName.substring(5).trim();
    }

    final bool isKn = widget.ttsService.isKannada;
    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final noteDetail = (savedNotes != null && savedNotes.isNotEmpty) ? ' (notes: $savedNotes)' : '';
      final prompt = isKn
          ? 'ದೃಷ್ಟಿಹೀನ ಬಳಕೆದಾರರು ತಮ್ಮ "$itemName"$noteDetail ವಸ್ತುವನ್ನು ಹುಡುಕುತ್ತಿದ್ದಾರೆ. ಕ್ಯಾಮೆರಾ ನೋಟವನ್ನು ಎಚ್ಚರಿಕೆಯಿಂದ ಸ್ಕ್ಯಾನ್ ಮಾಡಿ. ಅದು ಕಂಡುಬಂದರೆ, ಪ್ರಾದೇಶಿಕ ಗಡಿಯಾರ ದಿಕ್ಕುಗಳನ್ನು ಬಳಸಿ (ಉದಾಹರಣೆಗೆ "ನಿಮ್ಮ $itemName ಎಡಭಾಗದಲ್ಲಿರುವ ಮೇಜಿನ ಮೇಲಿದೆ, ಸುಮಾರು 10 ಗಂಟೆಯ ದಿಕ್ಕಿನಲ್ಲಿ, 1.5 ಮೀಟರ್ ದೂರದಲ್ಲಿದೆ") ತಕ್ಷಣ ತಿಳಿಸಿ. ಚೌಕಟ್ಟಿನಲ್ಲಿ ಇಲ್ಲದಿದ್ದರೆ "ನಿಮ್ಮ $itemName ಇನ್ನೂ ಕಾಣಿಸುತ್ತಿಲ್ಲ, ನಿಧಾನವಾಗಿ ಕ್ಯಾಮೆರಾ ತಿರುಗಿಸಿ" ಎಂದು ಹೇಳಿ.'
          : "The visually impaired user is looking for their '$itemName'$noteDetail. Scan the camera view carefully. If you see it, tell them immediately where it is using spatial clock directions (e.g., 'Your $itemName is on the table to your left, around 10 o\\'clock, about 1.5 meters away'). If it is not in the frame, say 'I don\\'t see your $itemName yet, slowly pan the camera'.";
      final handled = await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      if (handled) {
        final reply = widget.voiceCoordinator!.statusText.toLowerCase();
        final notFound = reply.contains("don't see") ||
            reply.contains("do not see") ||
            reply.contains("not found") ||
            reply.contains("not in the frame") ||
            reply.contains("not visible") ||
            reply.contains("ಕಾಣಿಸುತ್ತಿಲ್ಲ") ||
            reply.contains("ಇನ್ನೂ ಕಾಣಿಸುತ್ತಿಲ್ಲ") ||
            reply.contains("ಕಂಡುಬಂದಿಲ್ಲ");
        if (!notFound && reply.isNotEmpty) {
          HapticFeedback.mediumImpact();
        }
      }
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final preview = _phoneCameraController?.value.previewSize;
      final width = preview?.width.toDouble() ?? 720.0;

      final result = await _visionService.searchForObject(
        xFile.path,
        itemName,
        imageWidth: width,
        isSavedLookup: isSavedLookup,
        savedNotes: savedNotes,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = result;
      });
      if (!result.toLowerCase().contains('not found') && !result.contains('ಕಂಡುಬಂದಿಲ್ಲ')) {
        HapticFeedback.mediumImpact();
      }
      await widget.ttsService.speak(result);
    } catch (e) {
      debugPrint('Find item error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? '$itemName ಹುಡುಕಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not search for $itemName: $e',
      );
    } finally {
      _safeDeleteFile(tempPath);
    }
  }

  /// Direct prompt to inspect anyone in front of the camera and match against saved friends.
  Future<void> _whoIsHere() async {
    if (!_isAnyCameraActive) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    final bool isKn = widget.ttsService.isKannada;
    final friends = widget.storageService.getSavedFriends();
    final names = friends.map((f) => f.name).join(', ');

    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final prompt = friends.isNotEmpty
          ? (isKn
              ? 'ಕ್ಯಾಮೆರಾ ಮುಂದೆ ಯಾರು ಇದ್ದಾರೆ? ಉಳಿಸಿದ ಸ್ನೇಹಿತರ ಪಟ್ಟಿ: $names. ಈ ವ್ಯಕ್ತಿ ಯಾರಾದರೂ ಸ್ನೇಹಿತರಿಗೆ ಸರಿಹೊಂದುತ್ತಾರೆಯೇ ಅಥವಾ ಯಾರು ಎಂದು ಪ್ರಾದೇಶಿಕವಾಗಿ (ಎಡ, ಮಧ್ಯ, ಬಲ) ವಿವರಿಸಿ.'
              : "Who is in front of the camera? Saved friend profiles: $names. Check if this person matches any saved friend, or describe who is standing in front of the visually impaired user spatially (left, center, right).")
          : (isKn
              ? 'ಕ್ಯಾಮೆರಾ ಮುಂದೆ ಯಾರು ಇದ್ದಾರೆ ಎಂಬುದನ್ನು ಪ್ರಾದೇಶಿಕವಾಗಿ (ಎಡ, ಮಧ್ಯ, ಬಲ) ವಿವರಿಸಿ.'
              : "Who is in front of the camera? Describe the person in front of the visually impaired user spatially (left, center, right).");
      await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      return;
    }

    await _detectObjects();
  }

  /// Automatically matches an approaching person against saved friend profiles.
  Future<void> _checkApproachingFriendProximity(
    DetectedVisionItem person,
    List<FriendProfile> friends,
  ) async {
    if (_isIdentifyingFriend || widget.voiceCoordinator?.geminiLiveService == null) return;
    _isIdentifyingFriend = true;

    try {
      final frameBytes = await getLatestFrameJpeg();
      if (frameBytes == null || frameBytes.isEmpty) return;

      final friendNames = friends.map((f) => f.name).join(', ');
      final prompt =
          "Here is a face from the camera. Saved friend profiles: $friendNames. Does this person match any saved friend? If yes, respond ONLY with: 'MATCH: [Name]'. If no, respond 'NO_MATCH'.";

      final reply = await widget.voiceCoordinator!.geminiLiveService!.converse(
        apiKey: widget.storageService.geminiApiKey,
        userInput: prompt,
        imageBytes: frameBytes,
      );

      final matchRegex = RegExp(r'MATCH:\s*([A-Za-z0-9_\s]+)', caseSensitive: false);
      final match = matchRegex.firstMatch(reply);
      if (match != null) {
        final matchedName = match.group(1)?.trim() ?? '';
        final lowerName = matchedName.toLowerCase();

        final lastSpoken = _friendCooldowns[lowerName];
        final elapsed = lastSpoken == null ? 999 : DateTime.now().difference(lastSpoken).inSeconds;

        if (elapsed >= 20 && matchedName.isNotEmpty) {
          _friendCooldowns[lowerName] = DateTime.now();

          final dist = person.estimatedDistanceMeters != null
              ? person.estimatedDistanceMeters!.toStringAsFixed(1)
              : (person.proximity == 'close' ? '1.0' : '2.0');

          final isKn = widget.ttsService.isKannada;
          final pos = person.position;
          final posKn = pos == 'left' ? 'ಎಡಕ್ಕೆ' : (pos == 'right' ? 'ಬಲಕ್ಕೆ' : 'ಮುಂದೆ');

          final announcement = isKn
              ? '$matchedName ನಿಮ್ಮ $posKn, ಸುಮಾರು $dist ಮೀಟರ್ ದೂರದಲ್ಲಿದ್ದಾರೆ.'
              : '$matchedName is in front of you on your $pos, about $dist meters away.';

          setState(() {
            _statusMessage = announcement;
          });

          // Friendly two-beat haptic pattern (··)
          HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 150));
          HapticFeedback.mediumImpact();

          await widget.ttsService.speak(announcement);
        }
      }
    } catch (e) {
      debugPrint('[NavigationScreen] Friend proximity check error: $e');
    } finally {
      _isIdentifyingFriend = false;
    }
  }

  Future<void> _recognizeCurrency() async {
    if (!_isAnyCameraActive) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    final bool isKn = widget.ttsService.isKannada;
    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final prompt = isKn
          ? 'ಈ ಕ್ಯಾಮೆರಾ ನೋಟದಲ್ಲಿರುವ ಭಾರತೀಯ ರೂಪಾಯಿ ನೋಟುಗಳು ಅಥವಾ ನಾಣ್ಯಗಳನ್ನು ಗುರುತಿಸಿ ಮೌಲ್ಯವನ್ನು ತಿಳಿಸಿ.'
          : 'Identify any Indian Rupee banknotes or coins in this view and tell me their denomination.';
      await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      return;
    }

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;
      final result = await _visionService.recognizeCurrency(
        xFile.path,
        isKannada: widget.ttsService.isKannada,
      );

      setState(() {
        _statusMessage = result;
      });
      await widget.ttsService.speak(result);
    } catch (e) {
      debugPrint('Recognize currency error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕರೆನ್ಸಿ ಪರಿಶೀಲಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ: $e' : 'Could not check currency: $e',
      );
    } finally {
      _safeDeleteFile(tempPath);
    }
  }

  /// Inspects approaching city bus to announce route number and destination board.
  Future<void> _recognizeBusRoute() async {
    final bool isKn = widget.ttsService.isKannada;
    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final prompt = isKn
          ? 'ಮುಂದೆ ಬರುತ್ತಿರುವ ಬಸ್ ಸಂಖ್ಯೆ ಮತ್ತು ಗಮ್ಯಸ್ಥಾನ ಬೋರ್ಡ್ ಓದಿ ಹೇಳಿ.'
          : 'Identify the approaching bus route number and destination board.';
      await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      return;
    }

    final xfile = await _captureImageSafely();
    if (xfile == null) return;
    String? tempPath = xfile.path;
    try {
      final result = await _visionService.recognizeBusRoute(tempPath, isKannada: isKn);
      if (!mounted) return;
      setState(() {
        _statusMessage = result;
      });
      HapticFeedback.mediumImpact();
      await widget.ttsService.speak(result);
    } catch (e) {
      debugPrint('Recognize bus route error: $e');
      await widget.ttsService.speak(
        widget.ttsService.isKannada
            ? 'ಬಸ್ ಸಂಖ್ಯೆ ಗುರುತಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.'
            : 'Could not read bus route: $e',
      );
    } finally {
      _safeDeleteFile(tempPath);
    }
  }

  /// Inspects oncoming traffic light color and pedestrian crossing signals.
  Future<void> _checkTrafficLight() async {
    if (!_isAnyCameraActive) {
      await widget.ttsService.speak(
        widget.ttsService.isKannada ? 'ಕ್ಯಾಮೆರಾ ಇನ್ನೂ ಸಿದ್ಧವಾಗಿಲ್ಲ.' : 'Camera is not ready yet.',
      );
      return;
    }

    final bool isKn = widget.ttsService.isKannada;
    if (widget.voiceCoordinator != null && widget.storageService.useGeminiLive) {
      final prompt = isKn
          ? 'ಮುಂದೆ ಇರುವ ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ದೀಪದ ಬಣ್ಣ (ಕೆಂಪು, ಹಳದಿ, ಹಸಿರು) ಮತ್ತು ರಸ್ತೆ ದಾಟಲು ಸುರಕ್ಷಿತವೇ ಎಂದು ತಿಳಿಸಿ.'
          : 'Inspect the oncoming traffic signal or pedestrian light in this view and tell me its color and whether it is safe to cross.';
      await widget.voiceCoordinator!.askGeminiWithVision(prompt);
      return;
    }

    await widget.ttsService.stop();
    HapticFeedback.mediumImpact();
    await widget.ttsService.speak(
      isKn ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...' : 'Checking traffic signal...',
    );

    String? tempPath;
    try {
      final xFile = await _captureImageSafely();
      if (xFile == null) return;
      tempPath = xFile.path;

      final analysis = await _visionService.analyzeTrafficSignal(
        xFile.path,
        isKannada: isKn,
      );

      if (analysis.state == TrafficSignalState.red || analysis.state == TrafficSignalState.stopSign) {
        HapticFeedback.heavyImpact();
      } else if (analysis.state == TrafficSignalState.green) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }

      final speech = isKn ? analysis.descriptionKn : analysis.descriptionEn;
      if (mounted) {
        setState(() {
          _statusMessage = speech;
        });
      }
      await widget.ttsService.speak(speech);
    } catch (e) {
      debugPrint('[NavigationScreen] Traffic light inspection error: $e');
      await widget.ttsService.speak(
        isKn ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.' : 'Unable to inspect traffic signal at this moment.',
      );
    } finally {
      _safeDeleteFile(tempPath);
    }
  }

  /// Toggles device camera flashlight / torch for low-light obstacle & text detection.
  Future<void> _toggleTorch([bool? forceState]) async {
    if (_phoneCameraController == null || !_phoneCameraController!.value.isInitialized) {
      final msg = widget.ttsService.isKannada
          ? 'ಕ್ಯಾಮೆರಾ ಸಿದ್ಧವಾಗಿಲ್ಲ.'
          : 'Camera is not ready.';
      await widget.ttsService.speak(msg);
      return;
    }
    try {
      final target = forceState ?? !_isTorchOn;
      await _phoneCameraController!.setFlashMode(target ? FlashMode.torch : FlashMode.off);
      if (mounted) {
        setState(() {
          _isTorchOn = target;
        });
      }
      HapticFeedback.mediumImpact();
      final feedback = target
          ? (widget.ttsService.isKannada ? 'ಬೆಳಕು ಆನ್ ಆಗಿದೆ.' : 'Flashlight on.')
          : (widget.ttsService.isKannada ? 'ಬೆಳಕು ಆಫ್ ಆಗಿದೆ.' : 'Flashlight off.');
      await widget.ttsService.speak(feedback);
    } catch (e) {
      final err = widget.ttsService.isKannada
          ? 'ಟಾರ್ಚ್ ನಿಯಂತ್ರಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.'
          : 'Unable to toggle flashlight.';
      await widget.ttsService.speak(err);
    }
  }

  @override
  Future<Uint8List?> getLatestFrameJpeg() async {
    if (_usePhoneCamera) {
      if (_phoneCameraController == null || !_phoneCameraController!.value.isInitialized) {
        debugPrint('[NavigationScreen] Phone camera not ready.');
        return null;
      }
      try {
        final photo = await _phoneCameraController!.takePicture();
        final bytes = await photo.readAsBytes();
        try { File(photo.path).delete(); } catch (_) {}
        if (bytes.length > 5000) {
          return bytes;
        }
      } catch (e) {
        debugPrint('[NavigationScreen] Phone camera capture error: $e');
      }
      return null;
    }

    if (!_isGlassesConnected || _uvcService.controller == null) {
      debugPrint('[NavigationScreen] Smart glasses camera not ready.');
      return null;
    }

    try {
      final bytes = await _uvcService.getLatestFrame();
      if (bytes != null && bytes.length > 1000) {
        debugPrint('[NavigationScreen] UVC in-memory frame acquired (${bytes.length} bytes).');
        return bytes;
      }
      debugPrint('[NavigationScreen] Smart glasses camera returned empty frame.');
      return null;
    } catch (e) {
      debugPrint('[NavigationScreen] getLatestFrameJpeg error: $e');
      return null;
    }
  }

  @override
  bool handleVisionAction(String action, [String? arg]) {
    _runInitialVisionAction(action, arg);
    return true;
  }

  @override
  bool handleDestination(String destination) {
    _navService.startNavigationToDestination(destination);
    return true;
  }

  @override
  bool handleStopNavigation() {
    _stopNavigation();
    return true;
  }

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.stopNavigation:
      case VoiceCommandType.goBack:
        _stopNavigation();
        return true;

      case VoiceCommandType.startNavigation:
        _promptForDestination();
        return true;

      case VoiceCommandType.takeMeTo:
        final destination = command.argument ?? 'destination';
        _navService.startNavigationToDestination(destination);
        return true;

      case VoiceCommandType.whereAmI:
        _navService.announceCurrentLocation();
        return true;

      case VoiceCommandType.describeSurroundings:
        _describeSurroundings();
        return true;

      case VoiceCommandType.detectObjects:
        _detectObjects();
        return true;

      case VoiceCommandType.toggleObstacleAlerts:
        if (_isLiveMonitoringActive) {
          _stopLiveObstacleMonitoring();
          widget.ttsService.speak('Live obstacle alerts paused.');
        } else {
          _startLiveObstacleMonitoring();
          widget.ttsService.speak('Live obstacle alerts active.');
        }
        return true;

      case VoiceCommandType.toggleTorch:
        if (command.argument == 'on') {
          _toggleTorch(true);
        } else if (command.argument == 'off') {
          _toggleTorch(false);
        } else {
          _toggleTorch();
        }
        return true;

      case VoiceCommandType.aroundMe:
        _navService.announceNearbyAmenities();
        return true;

      case VoiceCommandType.facingDirection:
        _navService.announceFacingDirection();
        return true;

      case VoiceCommandType.readText:
        final mode = command.argument == 'all'
            ? OcrReadingMode.all
            : (command.argument == 'continue' ? OcrReadingMode.continueReading : OcrReadingMode.smart);
        _readText(mode: mode);
        return true;

      case VoiceCommandType.findItem:
        final item = command.argument ?? 'item';
        final isSaved = command.rawText.toLowerCase().contains('saved') ||
            command.rawText.toLowerCase().contains('leave') ||
            command.rawText.toLowerCase().contains('left') ||
            command.rawText.toLowerCase().contains('put');
        _findItem(item, isSavedLookup: isSaved);
        return true;

      case VoiceCommandType.recognizeCurrency:
        _recognizeCurrency();
        return true;

      case VoiceCommandType.readBusRoute:
        _recognizeBusRoute();
        return true;

      case VoiceCommandType.checkTrafficLight:
        _checkTrafficLight();
        return true;

      case VoiceCommandType.saveFavoritePlace:
        final tag = command.argument ?? 'home';
        _navService.saveCurrentLocationAsFavorite(tag: tag);
        return true;

      case VoiceCommandType.repeat:
        if (_navService.isNavigating) {
          _navService.repeatCurrentInstruction();
        } else if (_visionService.lastRecognizedText.isNotEmpty) {
          widget.ttsService.speak(_visionService.lastRecognizedText);
        } else {
          widget.ttsService.repeat();
        }
        return true;

      case VoiceCommandType.help:
        widget.ttsService.speak(
          'In camera mode, you can say: What can you see, Read the sign, Detect objects, Find an item, Where am I, Take me to a destination, or Stop navigation.',
        );
        return true;

      case VoiceCommandType.stopSpeaking:
        widget.ttsService.stop();
        return true;

      case VoiceCommandType.stopListening:
        if (widget.voiceCoordinator != null) {
          widget.voiceCoordinator!.stopListening(spokenFeedback: true);
        } else {
          widget.speechService.stopListening();
          widget.ttsService.speak('Stopped listening.');
        }
        return true;

      default:
        final raw = command.rawText.toLowerCase();
        if (raw.contains('switch camera') ||
            raw.contains('change camera') ||
            raw.contains('phone camera') ||
            raw.contains('glasses camera') ||
            raw.contains('ಕ್ಯಾಮೆರಾ ಬದಲಾಯಿಸಿ')) {
          _toggleCameraSource();
          return true;
        }
        return false; // Delegate back to coordinator for global commands
    }
  }

  Future<void> _handleMicToggle() async {
    if (widget.voiceCoordinator != null) {
      await widget.voiceCoordinator!.toggleListening();
      return;
    }

    final speechService = widget.speechService;
    final ttsService = widget.ttsService;

    if (speechService.isListening) {
      await speechService.stopListening();
      await ttsService.speak('Stopped listening.');
    } else {
      await ttsService.stop();
      final started = await speechService.startListening(
        localeId: widget.storageService.appLanguage == 'kn' ? 'kn_IN' : 'en_US',
        onResult: (text, isFinal) async {
          if (isFinal && text.trim().isNotEmpty) {
            await speechService.stopListening();
            _executeVoiceCommand(text);
          }
        },
      );
      if (!started) {
        final err = speechService.lastError ?? 'Unable to activate microphone.';
        await ttsService.speak(err);
      }
    }
  }

  void _executeVoiceCommand(String rawText) {
    if (widget.voiceCoordinator != null) {
      widget.voiceCoordinator!.processRecognizedText(rawText);
      return;
    }

    final assistantName = widget.storageService.assistantName;
    final cmd = VoiceCommandParser.parse(rawText, assistantName);

    if (handleVoiceCommand(cmd)) return;

    widget.ttsService.speak(cmd.rawText);
  }

  void _stopNavigation() {
    _navService.stopNavigation();
    final isKn = widget.ttsService.isKannada;
    widget.ttsService.speak(
      isKn
          ? 'ನ್ಯಾವಿಗೇಷನ್ ನಿಲ್ಲಿಸಲಾಗಿದೆ. ಮನೆ ಪರದೆಗೆ ಮರಳುತ್ತಿದೆ.'
          : 'Navigation stopped. Returning to home screen.',
    );
    Navigator.of(context).pop();
  }

  Future<void> _promptForDestination() async {
    final isKn = widget.ttsService.isKannada;
    final promptMsg = isKn
        ? 'ನೀವು ಎಲ್ಲಿಗೆ ಹೋಗಲು ಬಯಸುತ್ತೀರಿ? ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನವನ್ನು ಹೇಳಿ ಅಥವಾ ಉಳಿಸಿದ ಸ್ಥಳವನ್ನು ಆಯ್ಕೆಮಾಡಿ.'
        : 'Where would you like to go? Speak your destination, choose a favorite place, or type it below.';
    await widget.ttsService.speak(promptMsg);

    if (!mounted) return;

    final TextEditingController destController = TextEditingController();
    bool isListeningForDest = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: AppTheme.primary, width: 2),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final favorites = widget.storageService.favoritePlaces;

            Future<void> startListeningInModal() async {
              if (widget.speechService.isListening) {
                await widget.speechService.stopListening();
                setModalState(() => isListeningForDest = false);
                return;
              }

              await widget.ttsService.stop();
              setModalState(() => isListeningForDest = true);

              final started = await widget.speechService.startListening(
                localeId: widget.storageService.appLanguage == 'kn' ? 'kn_IN' : 'en_US',
                onResult: (text, isFinal) {
                  if (text.trim().isNotEmpty) {
                    setModalState(() {
                      destController.text = text.trim();
                    });
                  }
                  if (isFinal && text.trim().isNotEmpty) {
                    setModalState(() => isListeningForDest = false);
                    Navigator.of(modalContext).pop();
                    _navService.startNavigationToDestination(text.trim());
                  }
                },
              );
              if (!started) {
                setModalState(() => isListeningForDest = false);
                final err = widget.speechService.lastError ??
                    (isKn ? 'ಧ್ವನಿ ಗುರುತಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ.' : 'Unable to activate microphone.');
                widget.ttsService.speak(err);
              }
            }

            void submitDestination(String dest) {
              final query = dest.trim();
              if (query.isNotEmpty) {
                Navigator.of(modalContext).pop();
                _navService.startNavigationToDestination(query);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isKn ? 'ಗಮ್ಯಸ್ಥಾನವನ್ನು ಆಯ್ಕೆಮಾಡಿ' : 'Set Destination',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 28),
                          tooltip: isKn ? 'ಮುಚ್ಚಿ' : 'Close',
                          onPressed: () {
                            if (isListeningForDest) {
                              widget.speechService.stopListening();
                            }
                            Navigator.of(modalContext).pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AccessibleButton(
                      label: isListeningForDest
                          ? (isKn ? 'ಆಲಿಸುತ್ತಿದೆ... ಮಾತನಾಡಿ' : 'Listening... Speak now')
                          : (isKn ? 'ಗಮ್ಯಸ್ಥಾನವನ್ನು ಧ್ವನಿಯಲ್ಲಿ ಹೇಳಿ' : 'Speak Destination'),
                      icon: isListeningForDest ? Icons.mic : Icons.mic_none,
                      backgroundColor: isListeningForDest ? AppTheme.accentGreen : AppTheme.primary,
                      textColor: Colors.black,
                      semanticHint: isKn
                          ? 'ಧ್ವನಿಯ ಮೂಲಕ ಗಮ್ಯಸ್ಥಾನವನ್ನು ನಮೂದಿಸಲು ಟ್ಯಾಪ್ ಮಾಡಿ'
                          : 'Tap to speak your destination address or landmark',
                      onPressed: startListeningInModal,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: destController,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: isKn ? 'ಸ್ಥಳವನ್ನು ಟೈಪ್ ಮಾಡಿ...' : 'Type destination or landmark...',
                              hintStyle: const TextStyle(color: AppTheme.textMuted),
                              filled: true,
                              fillColor: AppTheme.surface,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.border, width: 2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppTheme.accentCyan, width: 2),
                              ),
                            ),
                            onSubmitted: submitDestination,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Semantics(
                          label: isKn ? 'ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ' : 'Start Navigation',
                          button: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => submitDestination(destController.text),
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: AppTheme.accentCyan,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                isKn ? 'ಹೋಗು' : 'Go',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (favorites.isNotEmpty) ...[
                      Text(
                        isKn ? 'ಉಳಿಸಿದ ಸ್ಥಳಗಳು' : 'Favorite Places',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentYellow,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: favorites.map((fav) {
                          final name = fav['name']?.toString() ?? fav['tag']?.toString() ?? 'Place';
                          final isHome = (fav['tag']?.toString().toLowerCase() == 'home') ||
                              name.toLowerCase().contains('home') ||
                              name.contains('ಮನೆ');
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => submitDestination(name),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isHome ? AppTheme.accentGreen : AppTheme.accentCyan,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isHome ? Icons.home_rounded : Icons.star,
                                    color: isHome ? AppTheme.accentGreen : AppTheme.accentCyan,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      isKn ? 'ತ್ವರಿತ ಸ್ಥಳಗಳು' : 'Quick Destinations',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _quickNavChip(isKn ? 'ಬಸ್ ನಿಲ್ದಾಣ' : 'Bus Stop', Icons.directions_bus, submitDestination),
                        _quickNavChip(isKn ? 'ಮೆಟ್ರೋ ನಿಲ್ದಾಣ' : 'Metro Station', Icons.subway, submitDestination),
                        _quickNavChip(isKn ? 'ಆಸ್ಪತ್ರೆ' : 'Hospital', Icons.local_hospital, submitDestination),
                        _quickNavChip(isKn ? 'ಔಷಧ ಅಂಗಡಿ' : 'Pharmacy', Icons.medication, submitDestination),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _quickNavChip(String label, IconData icon, Function(String) onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: AppTheme.accentCyan),
      label: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
      backgroundColor: AppTheme.surface,
      side: const BorderSide(color: AppTheme.border, width: 1.5),
      onPressed: () => onTap(label),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.voiceCoordinator?.unregisterDelegate(this);
    _navService.removeListener(_onNavServiceUpdated);
    _isLiveMonitoringActive = false;

    // ── Teardown Smart Glasses UVC listeners ────────────────────────────────────
    _uvcStreamSubscription?.cancel();
    _uvcStreamSubscription = null;
    _uvcService.removeListener(_onUvcServiceChanged);
    _uvcService.stopStreaming();
    _isGlassesConnected = false;

    // ── Dispose phone camera pipeline ────────────────────────────────────────
    final controller = _phoneCameraController;
    _phoneCameraController = null;
    if (_isTorchOn) {
      try {
        controller?.setFlashMode(FlashMode.off);
      } catch (_) {}
    }
    if (_isLocalNavService) {
      _navService.dispose();
    }
    if (_isLocalVisionService) {
      _visionService.dispose();
    }
    if (controller != null && controller.value.isInitialized) {
      try {
        if (controller.value.isStreamingImages) {
          controller.stopImageStream().then((_) {
            try {
              controller.dispose();
            } catch (_) {}
          }).catchError((_) {
            try {
              controller.dispose();
            } catch (_) {}
          });
        } else {
          controller.dispose();
        }
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assistantName = widget.storageService.assistantName;
    final bool isKn = widget.ttsService.isKannada;

    return Scaffold(
      backgroundColor: AppTheme.oledBlack,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text(
          _navService.isNavigating
              ? (isKn ? 'ಪಾದಚಾರಿ ಮಾರ್ಗದರ್ಶನ' : 'Pedestrian Guidance')
              : (isKn
                    ? (_isUvcActive ? 'USB ಕ್ಯಾಮೆರಾ HUD' : 'ಲೈವ್ ದೃಷ್ಟಿ HUD')
                    : (_isUvcActive ? 'USB Cam HUD' : 'Live Sight HUD')),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
        leading: Semantics(
          label: isKn ? 'ನ್ಯಾವಿಗೇಷನ್ ನಿಲ್ಲಿಸಿ ಮತ್ತು ಮನೆಗೆ ಮರಳಿ' : 'Stop Navigation and return home',
          hint: isKn ? 'ಕ್ಯಾಮೆರಾ ಮುಚ್ಚಿ ಮನೆ ಪರದೆಗೆ ಮರಳುತ್ತದೆ' : 'Exits camera mode and returns to home screen',
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: const Icon(Icons.close, size: 20, color: AppTheme.textPrimary),
            ),
            onPressed: _stopNavigation,
          ),
        ),
        actions: [
          // Quick Camera Source Switcher Pill (Glasses vs Phone)
          Semantics(
            label: _usePhoneCamera
                ? (isKn ? 'ಸ್ಮಾರ್ಟ್ ಗ್ಲಾಸಸ್ ಕ್ಯಾಮೆರಾಕ್ಕೆ ಬದಲಾಯಿಸಿ' : 'Switch to Smart Glasses camera')
                : (isKn ? 'ಫೋನ್ ಕ್ಯಾಮೆರಾಕ್ಕೆ ಬದಲಾಯಿಸಿ' : 'Switch to Phone camera'),
            hint: isKn ? 'ಕ್ಯಾಮೆರಾ ಮೂಲ ಬದಲಾಯಿಸಲು ಟ್ಯಾಪ್ ಮಾಡಿ' : 'Tap to switch active camera',
            child: InkWell(
              onTap: _toggleCameraSource,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _usePhoneCamera
                      ? AppTheme.accentCyan.withValues(alpha: 0.2)
                      : Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _usePhoneCamera ? AppTheme.accentCyan : Colors.amber,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _usePhoneCamera ? Icons.phone_android : Icons.usb,
                      color: _usePhoneCamera ? AppTheme.accentCyan : Colors.amber,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _usePhoneCamera ? 'Phone' : 'Glasses',
                      style: TextStyle(
                        color: _usePhoneCamera ? AppTheme.accentCyan : Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            label: isKn
                ? (_isTorchOn ? 'ಬೆಳಕು ಆಫ್ ಮಾಡಿ' : 'ಬೆಳಕು ಆನ್ ಮಾಡಿ')
                : (_isTorchOn ? 'Turn off flashlight' : 'Turn on flashlight'),
            hint: isKn ? 'ಕ್ಯಾಮೆರಾ ಬೆಳಕನ್ನು ನಿಯಂತ್ರಿಸುತ್ತದೆ' : 'Controls camera torch light',
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: Icon(
                  _isTorchOn ? Icons.flash_on : Icons.flash_off,
                  color: _isTorchOn ? AppTheme.accentYellow : AppTheme.textMuted,
                  size: 20,
                ),
              ),
              onPressed: () => _toggleTorch(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Semantics(
          label: isKn
              ? '$assistantName ಜೊತೆ ಮಾತನಾಡಲು ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ, ಅಥವಾ ಸ್ಥಿತಿ ಕೇಳಲು ಒಮ್ಮೆ ಟ್ಯಾಪ್ ಮಾಡಿ'
              : 'Single tap to hear status, double tap to talk to $assistantName, or swipe horizontally to toggle flashlight',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              HapticFeedback.selectionClick();
              if (_navService.isNavigating) {
                _navService.repeatCurrentInstruction();
              } else {
                widget.ttsService.speak(_statusMessage);
              }
            },
            onDoubleTap: _handleMicToggle,
            onLongPress: _triggerEmergency,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 200) {
                _toggleTorch();
              }
            },
            child: Column(
              children: [
                // Safety Disclaimer Banner (OLED True Black)
                Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppTheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isKn
                              ? 'ಸುರಕ್ಷತೆ: ಯಾವಾಗಲೂ ನಿಮ್ಮ ವಾಕಿಂಗ್ ಸ್ಟಿಕ್ ಬಳಸಿ. ಕ್ಯಾಮೆರಾವನ್ನು ಮಾತ್ರ ಅವಲಂಬಿಸಬೇಡಿ.'
                              : 'SAFETY: Always use your cane or mobility aid. Never rely on camera alone.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Edge-to-Edge Camera & Viewfinder Viewport
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_usePhoneCamera) ...[
                        if (_phoneCameraController != null && _phoneCameraController!.value.isInitialized)
                          ViewfinderReticle(
                            cornerColor: AppTheme.accentCyan,
                            child: CameraPreview(_phoneCameraController!),
                          )
                        else
                          Container(
                            color: Colors.black,
                            child: const Center(
                              child: CircularProgressIndicator(color: AppTheme.accentCyan),
                            ),
                          ),
                      ] else ...[
                        // Mount UVCCameraView unconditionally with concrete pixel bounds for Android SurfaceTexture
                        if (_uvcService.controller != null)
                          ViewfinderReticle(
                            cornerColor: AppTheme.accentCyan,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final w = constraints.maxWidth > 0
                                    ? constraints.maxWidth
                                    : MediaQuery.of(context).size.width;
                                final h = constraints.maxHeight > 0
                                    ? constraints.maxHeight
                                    : MediaQuery.of(context).size.height;
                                return UVCCameraView(
                                  cameraController: _uvcService.controller!,
                                  width: w,
                                  height: h,
                                  params: const UVCCameraViewParamsEntity(
                                    minFps: 10,
                                    maxFps: 30,
                                    frameFormat: 1, // MJPEG standard for OV5648
                                    bandwidthFactor: 1.0,
                                  ),
                                );
                              },
                            ),
                          ),

                        if (!_isGlassesConnected)
                          Container(
                            color: Colors.black,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isPermissionDenied) ...[
                                      const Icon(
                                        Icons.no_photography,
                                        size: 64,
                                        color: AppTheme.danger,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _statusMessage,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          color: AppTheme.textPrimary,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      AccessibleButton(
                                        label: isKn ? 'ಸೆಟ್ಟಿಂಗ್ಸ್ ತೆರೆಯಿರಿ' : 'Open App Settings',
                                        icon: Icons.settings,
                                        onPressed: () => openAppSettings(),
                                      ),
                                    ] else ...[
                                      const Icon(Icons.usb, size: 64, color: Colors.amber),
                                      const SizedBox(height: 16),
                                      Text(
                                        _uvcService.statusMessage ?? _statusMessage,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        alignment: WrapAlignment.center,
                                        children: [
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.amber,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            ),
                                            onPressed: () {
                                              _initUvcPipeline();
                                            },
                                            icon: const Icon(Icons.refresh),
                                            label: const Text(
                                              "Retry Connection",
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.accentCyan,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                            ),
                                            onPressed: () {
                                              _switchCameraSource(true);
                                            },
                                            icon: const Icon(Icons.phone_android),
                                            label: const Text(
                                              "Use Phone Camera",
                                              style: TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],

                      // Floating Top Spatial Guidance Strip (Frosted Glass HUD Pill)
                      Positioned(
                        top: 14,
                        left: 14,
                        right: 14,
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.glassSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _navService.isNavigating
                                    ? AppTheme.accentCyan
                                    : (_isCameraInitialized
                                        ? AppTheme.success
                                        : AppTheme.primary),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (_navService.isNavigating
                                            ? AppTheme.accentCyan
                                            : (_isCameraInitialized
                                                ? AppTheme.success
                                                : AppTheme.primary))
                                        .withValues(alpha: 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _navService.isNavigating
                                        ? Icons.directions_walk
                                        : (_isCameraInitialized
                                            ? Icons.videocam
                                            : Icons.hourglass_top),
                                    color: _navService.isNavigating
                                        ? AppTheme.accentCyan
                                        : (_isCameraInitialized
                                            ? AppTheme.success
                                            : AppTheme.primary),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.navigation, size: 12, color: AppTheme.primary),
                                          const SizedBox(width: 4),
                                          Text(
                                            _navService.isNavigating
                                                ? (isKn
                                                    ? 'ಗಮ್ಯಸ್ಥಾನ: ${_navService.currentRoute?.destinationName ?? ""}'
                                                    : 'Heading • 12 o\'clock')
                                                : (isKn
                                                    ? '12 ಗಂಟೆಯ ದಿಕ್ಕು • ಮುಂದೆ'
                                                    : '12 o\'clock • Straight ahead'),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primary,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _navService.isNavigating
                                            ? _navService.statusMessage
                                            : (_isCameraInitialized
                                                ? (isKn
                                                    ? 'ಪಾದಚಾರಿ ಮಾರ್ಗದರ್ಶನ ಸಿದ್ಧವಾಗಿದೆ. ಗಮ್ಯಸ್ಥಾನ ಹೊಂದಿಸಲು "ನ್ಯಾವಿಗೇಟ್" ಟ್ಯಾಪ್ ಮಾಡಿ.'
                                                    : 'Live Sight Active. Forward path monitored.')
                                                : _statusMessage),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                LiveWaveformVisualizer(
                                  isActive: widget.ttsService.isSpeaking || widget.speechService.isListening,
                                  barColor: AppTheme.accentCyan,
                                  height: 24,
                                  width: 44,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Imminent Obstacle & Safety Status Badge
                      Positioned(
                        top: 92,
                        left: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isLiveMonitoringActive
                                ? AppTheme.surface.withValues(alpha: 0.95)
                                : Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _isLiveMonitoringActive ? AppTheme.success : AppTheme.textMuted,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isLiveMonitoringActive ? AppTheme.success : AppTheme.textMuted,
                                  boxShadow: _isLiveMonitoringActive
                                      ? [
                                          BoxShadow(
                                            color: AppTheme.success.withValues(alpha: 0.6),
                                            blurRadius: 6,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isLiveMonitoringActive
                                    ? (isKn ? 'ಅಡೆತಡೆ ರಕ್ಷಣಾ ಕವಚ: ಸಕ್ರಿಯ' : 'Path Guard: Active (<3m)')
                                    : (isKn ? 'ಅಡೆತಡೆ ಕವಚ: ಆಫ್' : 'Path Guard: Idle'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _isLiveMonitoringActive ? AppTheme.success : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Ergonomic HUD Action Palette
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(color: AppTheme.glassBorder, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        blurRadius: 20,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tactile Quick-Action Edge Chips (Oversized, accessible without looking)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            _buildHudChip(
                              label: isKn ? 'ಪಠ್ಯ ಓದಿ' : 'Read Sign',
                              icon: Icons.document_scanner,
                              accentColor: AppTheme.accentCyan,
                              onTap: () => _readText(),
                            ),
                            const SizedBox(width: 8),
                            _buildHudChip(
                              label: isKn ? 'ಕರೆನ್ಸಿ' : 'Scan Note',
                              icon: Icons.payments,
                              accentColor: AppTheme.success,
                              onTap: () => _recognizeCurrency(),
                            ),
                            const SizedBox(width: 8),
                            _buildHudChip(
                              label: isKn ? 'ವಸ್ತು ಹುಡುಕಿ' : 'Find Item',
                              icon: Icons.search,
                              accentColor: AppTheme.primary,
                              onTap: () => _findItem('item'),
                            ),
                            const SizedBox(width: 8),
                            _buildHudChip(
                              label: isKn ? 'ಯಾರಿದು' : 'Who Is Here',
                              icon: Icons.people_alt,
                              accentColor: AppTheme.accentCyan,
                              onTap: () => _whoIsHere(),
                            ),
                            const SizedBox(width: 8),
                            _buildHudChip(
                              label: _isLiveMonitoringActive
                                  ? (isKn ? 'ಅಡೆತಡೆ: ಆನ್' : 'Alerts: ON')
                                  : (isKn ? 'ಅಡೆತಡೆ: ಆಫ್' : 'Alerts: OFF'),
                              icon: _isLiveMonitoringActive ? Icons.notifications_active : Icons.notifications_off,
                              accentColor: _isLiveMonitoringActive ? AppTheme.success : AppTheme.textMuted,
                              onTap: () async {
                                if (_isLiveMonitoringActive) {
                                  await _stopLiveObstacleMonitoring();
                                  await widget.ttsService.speak(
                                    isKn ? 'ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ವಿರಾಮಗೊಳಿಸಲಾಗಿದೆ.' : 'Live obstacle alerts paused.',
                                  );
                                } else {
                                  _startLiveObstacleMonitoring();
                                  await widget.ttsService.speak(
                                    isKn ? 'ಲೈವ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳು ಸಕ್ರಿಯವಾಗಿವೆ.' : 'Live obstacle alerts active.',
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Microphone Interaction Button
                      AnimatedBuilder(
                        animation: widget.speechService,
                        builder: (context, _) {
                          return MicButton(
                            isListening: widget.speechService.isListening,
                            onTap: _handleMicToggle,
                            assistantName: assistantName,
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // Navigation Control Rows
                      if (!_navService.isNavigating) ...[
                        Row(
                          children: [
                            Expanded(
                              child: AccessibleButton(
                                label: isKn ? 'ನ್ಯಾವಿಗೇಟ್...' : 'Navigate To...',
                                icon: Icons.explore,
                                backgroundColor: AppTheme.primary,
                                textColor: Colors.black,
                                minHeight: 56,
                                semanticLabel: isKn ? 'ಗಮ್ಯಸ್ಥಾನವನ್ನು ಆಯ್ಕೆಮಾಡಿ' : 'Set Destination for Navigation',
                                semanticHint: isKn
                                    ? 'ಪಾದಚಾರಿ ಮಾರ್ಗದರ್ಶನಕ್ಕಾಗಿ ಗಮ್ಯಸ್ಥಾನವನ್ನು ಆಯ್ಕೆಮಾಡಲು ಅಥವಾ ಹೇಳಲು ಟ್ಯಾಪ್ ಮಾಡಿ'
                                    : 'Tap to choose or speak your destination',
                                onPressed: _promptForDestination,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AccessibleButton(
                                label: isKn ? 'ನನ್ನ ಸ್ಥಳ' : 'Where Am I',
                                icon: Icons.my_location,
                                minHeight: 56,
                                semanticLabel: isKn ? 'ಪ್ರಸ್ತುತ ಸ್ಥಳ ಹೇಳಿ' : 'Speak current location',
                                semanticHint: isKn ? 'ಪ್ರಸ್ತುತ ಜಿಪಿಎಸ್ ವಿಳಾಸವನ್ನು ಹೇಳುತ್ತದೆ' : 'Speaks current GPS street address',
                                onPressed: () => _navService.announceCurrentLocation(),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: AccessibleButton(
                                label: isKn ? 'ಮತ್ತೆ ಹೇಳಿ' : 'Repeat Turn',
                                icon: Icons.replay,
                                minHeight: 56,
                                semanticHint: isKn ? 'ಕೊನೆಯ ಮಾರ್ಗದರ್ಶನವನ್ನು ಮತ್ತೆ ಹೇಳುತ್ತದೆ' : 'Repeats the last turn-by-turn guidance',
                                onPressed: () {
                                  _navService.repeatCurrentInstruction();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AccessibleButton(
                                label: isKn ? 'ನಿಲ್ಲಿಸಿ' : 'Stop Nav',
                                icon: Icons.stop_circle,
                                isDestructive: true,
                                minHeight: 56,
                                semanticHint: isKn ? 'ನ್ಯಾವಿಗೇಷನ್ ಮುಗಿಸಿ ಮನೆ ಪರದೆಗೆ ಮರಳುತ್ತದೆ' : 'Exits navigation and returns to home screen',
                                onPressed: _stopNavigation,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHudChip({
    required String label,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppTheme.surfaceHighlight,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
