import 'package:flutter/material.dart';
import 'core/localization/app_strings.dart';
import 'core/services/speech_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/tts_service.dart';
import 'core/services/voice_session_coordinator.dart';
import 'core/services/gemini_live_service.dart';
import 'core/services/uvc_camera_service.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/feature_detail_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/navigation_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize persistent storage for assistant name and settings
  final storageService = await StorageService.initialize();

  // 2. Initialize Text-to-Speech service with saved language
  final ttsService = TtsService();
  final initialTtsLocale = AppLanguage.fromCode(storageService.appLanguage).ttsLocale;
  await ttsService.initialize(
    rate: storageService.speechRate,
    pitch: storageService.speechPitch,
    language: initialTtsLocale,
  );

  // 3. Initialize Speech-to-Text service
  final speechService = SpeechService();
  speechService.initialize().catchError((e) {
    debugPrint('Initial speech recognition error: $e');
    return false;
  });

  // 4. Initialize Gemini Live service for Gemini
  final geminiLiveService = GeminiLiveService();
  if (storageService.useGeminiLive && storageService.geminiApiKey.isNotEmpty) {
    geminiLiveService.connect(apiKey: storageService.geminiApiKey).catchError((e) {
      debugPrint('Gemini Live auto-connect error: $e');
      return false;
    });
  }

  // 5. Initialize shared UvcCameraService singleton for smart glasses
  final uvcCameraService = UvcCameraService();
  if (!storageService.usePhoneCamera) {
    uvcCameraService.initialize().catchError((e) {
      debugPrint('UVC camera auto-connect notice: $e');
      return false;
    });
  }

  runApp(BlindNavigationApp(
    storageService: storageService,
    ttsService: ttsService,
    speechService: speechService,
    geminiLiveService: geminiLiveService,
    uvcCameraService: uvcCameraService,
  ));
}

/// Global navigator key enabling seamless transitions and action routing across the app lifecycle.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class BlindNavigationApp extends StatefulWidget {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService speechService;
  final GeminiLiveService? geminiLiveService;
  final UvcCameraService? uvcCameraService;
  final VoiceSessionCoordinator? voiceCoordinator;
  final GlobalKey<NavigatorState>? navigatorKey;

  const BlindNavigationApp({
    super.key,
    required this.storageService,
    required this.ttsService,
    required this.speechService,
    this.geminiLiveService,
    this.uvcCameraService,
    this.voiceCoordinator,
    this.navigatorKey,
  });

  @override
  State<BlindNavigationApp> createState() => _BlindNavigationAppState();
}

class _BlindNavigationAppState extends State<BlindNavigationApp> {
  late final GlobalKey<NavigatorState> _navigatorKey;
  late final VoiceSessionCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _navigatorKey = widget.navigatorKey ?? appNavigatorKey;
    _coordinator = widget.voiceCoordinator ??
        VoiceSessionCoordinator(
          storageService: widget.storageService,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          navigatorKey: _navigatorKey,
          geminiLiveService: widget.geminiLiveService,
        );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Smart Navigation',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.highContrastDarkTheme,
      home: HomeScreen(
        storageService: widget.storageService,
        ttsService: widget.ttsService,
        speechService: widget.speechService,
        voiceCoordinator: _coordinator,
      ),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/navigation':
            final args = settings.arguments;
            String? dest;
            String? visionAction;
            String? visionArg;
            bool promptDest = false;
            if (args is String) {
              dest = args;
            } else if (args is Map<String, dynamic>) {
              dest = args['destination'] as String?;
              visionAction = args['visionAction'] as String?;
              visionArg = args['visionArg'] as String?;
              promptDest = args['promptDestination'] as bool? ?? false;
            }
            return MaterialPageRoute(
              builder: (_) => NavigationScreen(
                storageService: widget.storageService,
                ttsService: widget.ttsService,
                speechService: widget.speechService,
                initialDestination: dest,
                initialVisionAction: visionAction,
                initialVisionArg: visionArg,
                initialOcrMode: args is Map ? args['ocrMode'] as String? : null,
                isSavedLookup: args is Map ? args['isSavedLookup'] as bool? : null,
                savedNotes: args is Map ? args['savedNotes'] as String? : null,
                promptDestinationOnLoad: promptDest,
                voiceCoordinator: _coordinator,
                uvcCameraService: widget.uvcCameraService,
              ),
            );
          case '/settings':
            return MaterialPageRoute(
              builder: (_) => SettingsScreen(
                storageService: widget.storageService,
                ttsService: widget.ttsService,
                speechService: widget.speechService,
                voiceCoordinator: _coordinator,
                onSettingsUpdated: () {
                  if (mounted) setState(() {});
                },
              ),
            );
          case '/feature_detail':
            final args = settings.arguments as Map<String, dynamic>? ?? {};
            return MaterialPageRoute(
              builder: (_) => FeatureDetailScreen(
                title: args['title'] as String? ?? 'Feature',
                status: args['status'] as String? ?? 'Available',
                explanation: args['explanation'] as String? ?? '',
                technicalNotes: args['technicalNotes'] as String? ?? '',
                icon: args['icon'] as IconData? ?? Icons.info,
                ttsService: widget.ttsService,
                speechService: widget.speechService,
                storageService: widget.storageService,
                voiceCoordinator: _coordinator,
                assistantName: widget.storageService.assistantName,
                visionAction: args['visionAction'] as String?,
                visionArg: args['visionArg'] as String?,
              ),
            );
          default:
            return null;
        }
      },
    );
  }
}
