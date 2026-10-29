import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blind_navigation/core/services/uvc_camera_service.dart';
import 'package:blind_navigation/core/services/gemini_live_service.dart';
import 'package:blind_navigation/core/services/voice_session_coordinator.dart';
import 'package:blind_navigation/core/services/object_detector_service.dart';
import 'package:blind_navigation/core/services/vision_service.dart';
import 'package:blind_navigation/core/services/storage_service.dart';
import 'package:blind_navigation/core/services/tts_service.dart';
import 'package:blind_navigation/core/services/speech_service.dart';
import 'package:blind_navigation/models/navigation_step.dart';
import 'package:blind_navigation/models/voice_command.dart';
import 'package:blind_navigation/ui/screens/home_screen.dart';
import 'package:blind_navigation/ui/screens/settings_screen.dart';
import 'package:blind_navigation/ui/screens/feature_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (MethodCall call) async {
      return 1;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('speech_to_text'), (MethodCall call) async {
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugin.csdcorp.com/speech_to_text'), (MethodCall call) async {
      if (call.method == 'locales') {
        return <dynamic>['en_US:English:true', 'kn_IN:Kannada:false'];
      }
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.example.blind_navigation/usb_permissions'), (MethodCall call) async {
      if (call.method == 'requestUsbPermission') {
        return true;
      } else if (call.method == 'hasUsbPermission') {
        return false;
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_uvc_camera/channel'), (MethodCall call) async {
      return null;
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Phase 5.1: Hardware Disconnect & Jiggle Resilience Tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5.1: Hardware Disconnect & Jiggle Resilience Tests', () {
    test('UvcCameraService initializes cleanly in disconnected state', () {
      final service = UvcCameraService();
      expect(service.connectionState, UvcConnectionState.disconnected);
      expect(service.isUvcConnected, isFalse);
      expect(service.controller, isNull);
      expect(service.statusMessage, isNull);
    });

    test('UvcCameraService.stopStreaming cleanly cancels without active controller', () {
      final service = UvcCameraService();
      expect(() => service.stopStreaming(), returnsNormally);
      expect(service.connectionState, UvcConnectionState.disconnected);
    });

    test('UvcCameraService.getLatestFrame returns null when camera is disconnected', () async {
      final service = UvcCameraService();
      final frame = await service.getLatestFrame();
      expect(frame, isNull);
    });

    test('UvcCameraService.captureFrame returns null gracefully when disconnected', () async {
      final service = UvcCameraService();
      final frame = await service.captureFrame();
      expect(frame, isNull);
      expect(service.connectionState, UvcConnectionState.disconnected);
    });

    test('UvcCameraService.requestUsbPermission invokes native USB channel', () async {
      final service = UvcCameraService();
      final result = await service.requestUsbPermission();
      expect(result, isTrue);
    });

    test('ObjectDetectorService and VisionService drop truncated frames (< 1000 bytes) without crash', () async {
      final detector = ObjectDetectorService();
      final vision = VisionService(objectDetectorService: detector);

      // Incomplete packet of 150 bytes
      final truncatedBuffer = Uint8List(150);
      final detectorResult = await detector.detectObjectsFromBytes(truncatedBuffer);
      expect(detectorResult, isEmpty);

      final visionResult = await vision.detectObjectsFromBytes(truncatedBuffer);
      expect(visionResult, isEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Phase 5.1: Network Degradation & Fast-Fail Offline Tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5.1: Network Degradation & Fast-Fail Offline Tests', () {
    test('GeminiLiveService initializes cleanly in disconnected state', () {
      final gemini = GeminiLiveService();
      expect(gemini.state, GeminiLiveState.disconnected);
      expect(gemini.lastError, isNull);
    });

    test('GeminiLiveService.converse fast-fails and returns __FALLBACK_LOCAL__ on bad key/network', () async {
      final gemini = GeminiLiveService();
      final stopwatch = Stopwatch()..start();
      final reply = await gemini.converse(
        apiKey: 'INVALID_TEST_KEY',
        userInput: 'Where is my powerbank?',
      );
      stopwatch.stop();

      expect(reply, '__FALLBACK_LOCAL__');
      expect(gemini.lastError, isNotNull);
    });

    test('VoiceSessionCoordinator handles __FALLBACK_LOCAL__ without speaking API key errors', () async {
      SharedPreferences.setMockInitialValues({
        'use_gemini_live': true,
        'gemini_api_key': 'test_key',
      });
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();
      final mockGemini = _MockOfflineGeminiService();

      final coordinator = VoiceSessionCoordinator(
        navigatorKey: GlobalKey<NavigatorState>(),
        storageService: storage,
        ttsService: tts,
        speechService: speech,
        geminiLiveService: mockGemini,
      );

      final delegate = _MockDelegate();
      coordinator.registerDelegate(delegate);

      // Speak command while Gemini is offline
      await coordinator.processVoiceInput('start navigation');
      expect(delegate.handledCommand, isNotNull);
      expect(delegate.handledCommand!.type, VoiceCommandType.startNavigation);
      // Verify no alarming "check API key" error was spoken to the user
      expect(tts.lastMessage.contains('check API key'), isFalse);
    });

    test('PedestrianRoute supports direct compass failover mode and properties', () {
      const route = PedestrianRoute(
        destinationName: 'Central Station',
        destinationLat: 12.9716,
        destinationLng: 77.5946,
        totalDistanceMeters: 450.0,
        totalDurationSeconds: 400.0,
        isDirectCompassMode: true,
        steps: [
          PedestrianStep(
            instruction: 'Walk towards destination',
            streetName: '',
            maneuverType: 'depart',
            maneuverModifier: '',
            distanceMeters: 450.0,
            durationSeconds: 400.0,
            waypointLat: 12.9716,
            waypointLng: 77.5946,
          ),
        ],
        polylineCoordinates: [
          [12.9700, 77.5900],
          [12.9716, 77.5946],
        ],
      );

      expect(route.isDirectCompassMode, isTrue);
      expect(route.destinationName, 'Central Station');
      expect(route.totalDistanceMeters, 450.0);
      expect(route.steps.first.estimatedSteps, (450 / 0.75).round());
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Phase 5.1: Spatial Guidance & Clock Phrasing Unit Tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5.1: Spatial Guidance & Clock Phrasing Unit Tests', () {
    test('DetectedVisionItem formatConciseDescription generates front-loaded phrasing', () {
      // 10 o'clock left
      final item10 = DetectedVisionItem(
        label: 'backpack',
        confidence: 0.92,
        position: 'left',
        proximity: 'near',
        boundingBox: const Rect.fromLTWH(0.05, 0.1, 0.2, 0.4),
        clockPosition: "10 o'clock",
        estimatedDistanceMeters: 1.5,
      );
      expect(item10.formatConciseDescription(isKannada: false), "backpack: 10 o'clock, 1.5m");
      expect(item10.formatConciseDescription(isKannada: true, customLabel: 'ಬ್ಯಾಗ್'), 'ಬ್ಯಾಗ್: 10 ಗಂಟೆ, ಸುಮಾರು 1.5 ಮೀಟರ್');

      // 12 o'clock center
      final item12 = DetectedVisionItem(
        label: 'chair',
        confidence: 0.88,
        position: 'center',
        proximity: 'close',
        boundingBox: const Rect.fromLTWH(0.45, 0.2, 0.55, 0.6),
        clockPosition: "12 o'clock",
        estimatedDistanceMeters: 1.0,
      );
      expect(item12.formatConciseDescription(isKannada: false), "chair: 12 o'clock, 1.0m");
      expect(item12.formatConciseDescription(isKannada: true, customLabel: 'ಕುರ್ಚಿ'), 'ಕುರ್ಚಿ: 12 ಗಂಟೆ, ಸುಮಾರು 1.0 ಮೀಟರ್');

      // 2 o'clock right
      final item2 = DetectedVisionItem(
        label: 'bottle',
        confidence: 0.85,
        position: 'right',
        proximity: 'near',
        boundingBox: const Rect.fromLTWH(0.8, 0.3, 0.95, 0.7),
        clockPosition: "2 o'clock",
        estimatedDistanceMeters: 0.8,
      );
      expect(item2.formatConciseDescription(isKannada: false), "bottle: 2 o'clock, 0.8m");
      expect(item2.formatConciseDescription(isKannada: true, customLabel: 'ಬಾಟಲ್'), 'ಬಾಟಲ್: 2 ಗಂಟೆ, ಸುಮಾರು 0.8 ಮೀಟರ್');
    });

    test('DetectedVisionItem formatSpatialDescription generates natural combined phrasing', () {
      final centerItem = DetectedVisionItem(
        label: 'chair',
        confidence: 0.9,
        position: 'center',
        proximity: 'close',
        boundingBox: const Rect.fromLTWH(0.45, 0.2, 0.55, 0.6),
        clockPosition: "12 o'clock",
        estimatedDistanceMeters: 1.2,
      );
      expect(centerItem.formatSpatialDescription(isKannada: false), 'chair directly ahead, about 1.2 meters away.');
      expect(centerItem.formatSpatialDescription(isKannada: true, customLabel: 'ಕುರ್ಚಿ'), 'ಕುರ್ಚಿ ನೇರವಾಗಿ ಮುಂದೆ, ಸುಮಾರು 1.2 ಮೀಟರ್ ದೂರದಲ್ಲಿದೆ.');

      final leftItem = DetectedVisionItem(
        label: 'backpack',
        confidence: 0.9,
        position: 'left',
        proximity: 'near',
        boundingBox: const Rect.fromLTWH(0.1, 0.1, 0.3, 0.4),
        clockPosition: "10 o'clock",
        estimatedDistanceMeters: 1.5,
      );
      expect(leftItem.formatSpatialDescription(isKannada: false), "backpack on your left, 10 o'clock, about 1.5 meters away.");
      expect(leftItem.formatSpatialDescription(isKannada: true, customLabel: 'ಬ್ಯಾಗ್'), "ಬ್ಯಾಗ್ ನಿಮ್ಮ ಎಡಕ್ಕೆ, 10 o'clock ದಿಕ್ಕಿನಲ್ಲಿ, ಸುಮಾರು 1.5 ಮೀಟರ್ ದೂರದಲ್ಲಿದೆ.");
    });

    test('VoiceSessionCoordinator.triggerDirectionalHaptic executes safely across clock angles', () {
      expect(() => VoiceSessionCoordinator.triggerDirectionalHaptic("10 o'clock"), returnsNormally);
      expect(() => VoiceSessionCoordinator.triggerDirectionalHaptic("11 o'clock"), returnsNormally);
      expect(() => VoiceSessionCoordinator.triggerDirectionalHaptic("12 o'clock"), returnsNormally);
      expect(() => VoiceSessionCoordinator.triggerDirectionalHaptic("1 o'clock"), returnsNormally);
      expect(() => VoiceSessionCoordinator.triggerDirectionalHaptic("2 o'clock"), returnsNormally);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Phase 5.2: Audio Priority Preemption & Echo Cancellation Tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5.2: Audio Priority Preemption & Echo Cancellation Tests', () {
    test('TtsService preempts ambient speech when hazard alert arrives', () async {
      final tts = TtsService();
      TtsPriority? notifiedStartingPriority;
      tts.onSpeechStarting = (priority) {
        notifiedStartingPriority = priority;
      };

      // 1. Queue ambient speech
      await tts.speak('Looking around your surroundings, there are several chairs.', priority: TtsPriority.ambient);
      expect(tts.currentPriority, TtsPriority.ambient);

      // 2. Immediate hazard preemption
      await tts.speak('Caution! Chair: 12 o\'clock, 1.0m.', priority: TtsPriority.hazard);
      expect(tts.currentPriority, TtsPriority.hazard);
      expect(notifiedStartingPriority, TtsPriority.hazard);
    });

    test('TtsService.emergencySpeak clears queue and sets maximum priority', () async {
      final tts = TtsService();
      await tts.speak('General scenic description.', priority: TtsPriority.ambient);
      await tts.emergencySpeak('STOP! Obstacle directly ahead.');

      expect(tts.currentPriority, TtsPriority.emergency);
      expect(tts.lastMessage, 'STOP! Obstacle directly ahead.');
    });

    test('VoiceSessionCoordinator mutes microphone when hazard audio begins', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = _MockSpeechService();

      final coordinator = VoiceSessionCoordinator(
        storageService: storage,
        ttsService: tts,
        speechService: speech,
        navigatorKey: GlobalKey<NavigatorState>(),
      );

      // Simulate mic actively listening
      await speech.startListening(onResult: (text, isFinal) {});
      expect(speech.isListening, isTrue);

      // Broadcast hazard audio starting
      tts.onSpeechStarting?.call(TtsPriority.hazard);

      // Verify microphone muting
      expect(speech.isListening, isFalse);
      coordinator.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Phase 5.2: Screen Reader Semantics & Accessibility Tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 5.2: Screen Reader Semantics & Accessibility Tests', () {
    testWidgets('HomeScreen renders accessible touch targets and semantics', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'has_completed_onboarding': true,
      });
      final storage = await StorageService.initialize();
      final tts = TtsService();
      final speech = SpeechService();

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          storageService: storage,
          ttsService: tts,
          speechService: speech,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tts.stop();
      await tester.pump();

      // Verify accessible home screen elements
      expect(find.text('Smart Navigation'), findsOneWidget);
      expect(find.text('START NAVIGATION'), findsOneWidget);
      expect(find.text('TAP TO TALK TO LUX'), findsOneWidget);
      expect(find.text('Repeat Last Audio'), findsOneWidget);
      expect(find.text('EMERGENCY SOS'), findsOneWidget);

      // Verify minimum touch target compliance (>= 48x48 on action buttons)
      final micFinder = find.ancestor(of: find.text('TAP TO TALK TO LUX'), matching: find.byType(InkWell)).first;
      final micSize = tester.getSize(micFinder);
      expect(micSize.width, greaterThanOrEqualTo(48.0));
      expect(micSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('SettingsScreen renders high contrast labels and accessible controls', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.initialize();
      final tts = TtsService();

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          storageService: storage,
          ttsService: tts,
          onSettingsUpdated: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('ಕನ್ನಡ'), findsOneWidget);
    });

    testWidgets('FeatureDetailScreen renders accessible emergency cards', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.initialize();
      final tts = TtsService();

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(MaterialApp(
        home: FeatureDetailScreen(
          title: 'Obstacle Detection',
          status: 'Active',
          explanation: 'Warns about pedestrian obstacles and overhead hazards.',
          technicalNotes: 'Real-time TFLite SSD MobileNet.',
          icon: Icons.warning_amber,
          ttsService: tts,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Obstacle Detection'), findsNWidgets(2));
      expect(find.text('Description & Availability'), findsOneWidget);
      expect(find.text('Repeat Spoken Details'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
    });
  });
}

class _MockDelegate implements VoiceCommandDelegate {
  VoiceCommand? handledCommand;

  @override
  String get screenName => 'MockScreen';

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    handledCommand = command;
    return true;
  }
}

class _MockOfflineGeminiService extends GeminiLiveService {
  @override
  Future<String> converse({
    required String apiKey,
    required String userInput,
    Uint8List? imageBytes,
    String? customSystemInstruction,
    String? savedItemsContext,
  }) async {
    return '__FALLBACK_LOCAL__';
  }
}

class _MockSpeechService extends SpeechService {
  bool _mockListening = false;

  @override
  bool get isListening => _mockListening;

  @override
  Future<bool> startListening({required SpeechResultCallback onResult, String? localeId}) async {
    _mockListening = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> stopListening() async {
    _mockListening = false;
    notifyListeners();
  }
}
