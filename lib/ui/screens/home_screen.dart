import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/localization/app_strings.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/voice_command_parser.dart';
import '../../core/services/voice_session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/voice_command.dart';
import '../widgets/live_waveform_visualizer.dart';
import 'feature_detail_screen.dart';
import 'navigation_screen.dart';
import 'settings_screen.dart';

/// Clean, high-contrast, voice-first home screen.
///
/// Implements True Assistive UI Architecture:
/// - Zone 1: Top Navigation Zone (~40% height) - Massive tactile card to start navigation.
/// - Zone 2: Center/Lower Voice Zone (~45% height) - Massive circular mic touch area to talk to Lux.
/// - Zone 3: Persistent Safety Bottom Dock (~15% height) - 2 spacious buttons: "Repeat Last Audio" and "EMERGENCY SOS".
class HomeScreen extends StatefulWidget {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService speechService;
  final VoiceSessionCoordinator? voiceCoordinator;

  const HomeScreen({
    super.key,
    required this.storageService,
    required this.ttsService,
    required this.speechService,
    this.voiceCoordinator,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements VoiceCommandDelegate {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  String _lastVoiceTranscript = '';
  String _assistantStatus = '';
  bool _hasSpokenGreeting = false;
  final bool _isProcessing = false;

  @override
  String get screenName => 'Home';

  AppLanguage get _currentLanguage =>
      AppLanguage.fromCode(widget.storageService.appLanguage);

  AppStrings get _strings => AppStrings(_currentLanguage);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    widget.voiceCoordinator?.registerDelegate(this);
    widget.voiceCoordinator?.addListener(_onCoordinatorUpdate);
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakWelcomeGreeting();
    });
  }

  void _onCoordinatorUpdate() {
    if (!mounted || widget.voiceCoordinator == null) return;
    final isListening = widget.voiceCoordinator!.isListening;
    if (isListening && !_animController.isAnimating) {
      _animController.repeat(reverse: true);
    } else if (!isListening && _animController.isAnimating) {
      _animController.stop();
      _animController.reset();
    }

    setState(() {
      if (widget.voiceCoordinator!.lastTranscript.isNotEmpty) {
        _lastVoiceTranscript = widget.voiceCoordinator!.lastTranscript;
      }
      if (widget.voiceCoordinator!.statusText.isNotEmpty) {
        _assistantStatus = widget.voiceCoordinator!.statusText;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    widget.voiceCoordinator?.removeListener(_onCoordinatorUpdate);
    widget.voiceCoordinator?.unregisterDelegate(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[HomeScreen] App resumed. Re-arming wake word standby.');
      if (widget.voiceCoordinator != null &&
          !widget.voiceCoordinator!.isListening &&
          !widget.ttsService.isSpeaking) {
        widget.voiceCoordinator!.startWakeWordStandby();
      }
    }
  }

  Future<void> _speakWelcomeGreeting() async {
    if (_hasSpokenGreeting) return;
    _hasSpokenGreeting = true;
    final name = widget.storageService.assistantName;
    final strings = _strings;
    final isKn = strings.isKannada;
    final hasCompleted = widget.storageService.hasCompletedOnboarding;

    if (!hasCompleted) {
      await widget.storageService.setCompletedOnboarding(true);
      final walkthrough = isKn
          ? 'ಸ್ಮಾರ್ಟ್ ನ್ಯಾವಿಗೇಷನ್‌ಗೆ ಸುಸ್ವಾಗತ. ನಾನು ನಿಮ್ಮ ಧ್ವನಿ ಸಹಾಯಕ $name. ನ್ಯಾವಿಗೇಷನ್‌ಗಾಗಿ ಮೇಲ್ಭಾಗವನ್ನು ಟ್ಯಾಪ್ ಮಾಡಿ, ಅಥವಾ ಮಾತನಾಡಲು ಮಧ್ಯಭಾಗವನ್ನು ಟ್ಯಾಪ್ ಮಾಡಿ.'
          : 'Welcome to Smart Navigation. I am $name. Tap the top area to start navigation, or tap the large center circle to talk to me. In an emergency, tap the red SOS button at the bottom right.';
      setState(() {
        _assistantStatus = strings.assistantReady(name);
      });
      await widget.ttsService.speak(walkthrough);
      widget.voiceCoordinator?.startWakeWordStandby();
      return;
    }

    final welcome = strings.welcomeGreeting(name);
    setState(() {
      _assistantStatus = strings.assistantReady(name);
    });
    await widget.ttsService.speak(welcome);
    widget.voiceCoordinator?.startWakeWordStandby();
  }

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.startNavigation:
        _openNavigationScreen(promptDestination: true);
        return true;
      case VoiceCommandType.stopNavigation:
        widget.ttsService.speak(_strings.navNotActive);
        return true;
      case VoiceCommandType.openSettings:
        _openSettings();
        return true;
      case VoiceCommandType.help:
        _speakHelp();
        return true;
      case VoiceCommandType.takeMeTo:
        final destination = command.argument ?? 'destination';
        _openNavigationScreen(destination: destination);
        return true;
      case VoiceCommandType.switchLanguage:
        final targetLang = command.argument ?? 'en';
        _switchLanguage(targetLang);
        return true;
      case VoiceCommandType.repeat:
        widget.ttsService.repeat(emptyMessage: _strings.noMessageToRepeat);
        return true;
      case VoiceCommandType.stopSpeaking:
        widget.ttsService.stop();
        setState(() {
          _assistantStatus = _strings.audioStopped;
        });
        return true;
      case VoiceCommandType.stopListening:
        if (widget.voiceCoordinator != null) {
          widget.voiceCoordinator!.stopListening(spokenFeedback: true);
        } else {
          widget.speechService.stopListening();
          widget.ttsService.speak(_strings.stoppedListening);
        }
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleMicToggle() async {
    if (widget.ttsService.isSpeaking) {
      await widget.ttsService.stop();
      return;
    }

    if (widget.voiceCoordinator != null) {
      await widget.voiceCoordinator!.toggleListening();
      return;
    }

    final speechService = widget.speechService;
    final ttsService = widget.ttsService;
    final strings = _strings;
    final lang = _currentLanguage;

    if (speechService.isListening) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.lightImpact();
      await speechService.stopListening();
      setState(() {
        _assistantStatus = strings.micTurnedOff;
      });
      await ttsService.speak(strings.stoppedListening);
    } else {
      await ttsService.stop();
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
      setState(() {
        _assistantStatus = strings.micListening;
        _lastVoiceTranscript = '';
      });

      final started = await speechService.startListening(
        localeId: lang.sttLocale,
        onResult: (words, isFinal) async {
          setState(() {
            _lastVoiceTranscript = words;
            _assistantStatus = strings.heardText(words);
          });
          if (isFinal && words.trim().isNotEmpty) {
            await speechService.stopListening();
            _executeVoiceCommand(words);
          }
        },
      );

      if (!started) {
        final err = speechService.lastError ?? 'Unable to activate microphone.';
        setState(() {
          _assistantStatus = err;
        });
        await ttsService.speak('Could not start microphone: $err');
      }
    }
  }

  Future<void> _switchLanguage(String code) async {
    final newLang = AppLanguage.fromCode(code);
    await widget.storageService.setAppLanguage(code);
    final isAvailable = await widget.ttsService.setLanguage(newLang.ttsLocale);

    setState(() {});

    final strings = AppStrings(newLang);
    if (newLang == AppLanguage.kn && !isAvailable) {
      await widget.ttsService.speak(strings.kannadaTtsUnavailableWarning);
    } else {
      await widget.ttsService.speak(strings.languageChangedConfirmation(newLang));
    }
  }

  void _executeVoiceCommand(String rawText) {
    if (widget.voiceCoordinator != null) {
      widget.voiceCoordinator!.processRecognizedText(rawText);
      return;
    }

    final assistantName = widget.storageService.assistantName;
    final command = VoiceCommandParser.parse(rawText, assistantName);

    if (handleVoiceCommand(command)) return;

    final reply = _strings.unknownCommand(command.rawText);
    setState(() {
      _assistantStatus = reply;
    });
    widget.ttsService.speak(reply);
  }

  void _speakHelp() {
    final name = widget.storageService.assistantName;
    final strings = _strings;
    final helpText = strings.helpCommands(name);
    setState(() {
      _assistantStatus = strings.help;
    });
    widget.ttsService.speak(helpText);
  }

  void _openNavigationScreen({
    String? destination,
    String? visionAction,
    String? visionArg,
    bool promptDestination = false,
  }) {
    final name = widget.storageService.assistantName;
    final strings = _strings;
    if (destination == null && visionAction == null && !promptDestination) {
      widget.ttsService.speak(strings.navStarting(name));
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NavigationScreen(
          storageService: widget.storageService,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          initialDestination: destination,
          initialVisionAction: visionAction,
          initialVisionArg: visionArg,
          promptDestinationOnLoad: promptDestination,
          voiceCoordinator: widget.voiceCoordinator,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          storageService: widget.storageService,
          ttsService: widget.ttsService,
          speechService: widget.speechService,
          voiceCoordinator: widget.voiceCoordinator,
          onSettingsUpdated: () {
            setState(() {});
          },
        ),
      ),
    );
  }

  void _triggerEmergency() {
    HapticFeedback.heavyImpact();
    final contact = widget.storageService.emergencyContact;
    final isKn = _strings.isKannada;
    widget.ttsService.speak(
      isKn
          ? 'ತುರ್ತು ಮೋಡ್ ಸಕ್ರಿಯವಾಗಿದೆ. ತುರ್ತು ಸಂಪರ್ಕ: $contact. ಸಹಾಯಕ್ಕಾಗಿ 112 ಕರೆ ಮಾಡಿ.'
          : 'Emergency assistance active. Contact is $contact. Calling 112 if needed.',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeatureDetailScreen(
          title: _strings.featEmergencyTitle,
          status: _strings.statusAvailable,
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

  void _showAllFeaturesDialog() {
    final strings = _strings;
    final isKn = strings.isKannada;
    HapticFeedback.selectionClick();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  isKn ? 'ವೈಶಿಷ್ಟ್ಯಗಳ ಪರಿಚಯ' : 'Assistive Capabilities Guide',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              _buildFeatureTile(
                icon: Icons.explore,
                title: isKn ? 'ಪಾದಚಾರಿ ಮಾರ್ಗದರ್ಶನ' : 'Walking Navigation',
                subtitle: isKn ? 'ಟರ್ನ್-ಬೈ-ಟರ್ನ್ ಆಡಿಯೋ & ಹ್ಯಾಪ್ಟಿಕ್ಸ್' : 'Turn-by-turn guidance with clock directions & haptics',
                onTap: () {
                  Navigator.pop(ctx);
                  _openNavigationScreen(promptDestination: true);
                },
              ),
              _buildFeatureTile(
                icon: Icons.search,
                title: isKn ? 'ವಸ್ತು ಹುಡುಕಿ' : 'Find My Item',
                subtitle: isKn ? 'ಕಳೆದುಹೋದ ವಸ್ತುಗಳಿಗೆ ಪ್ರಾದೇಶಿಕ ಮಾರ್ಗದರ್ಶನ' : 'Live spatial search for lost objects',
                onTap: () {
                  Navigator.pop(ctx);
                  _openNavigationScreen(visionAction: 'find', visionArg: 'item');
                },
              ),
              _buildFeatureTile(
                icon: Icons.people,
                title: isKn ? 'ಸ್ನೇಹಿತರು ಮತ್ತು ಮುಖಗಳು' : 'Friends & Faces',
                subtitle: isKn ? 'ಸ್ನೇಹಿತರ ಮುಖ ಉಳಿಸಿ ಮತ್ತು ಗುರುತಿಸಿ' : 'Recognize enrolled friends and notify proximity',
                onTap: () {
                  Navigator.pop(ctx);
                  _openNavigationScreen(visionAction: 'whoIsHere');
                },
              ),
              _buildFeatureTile(
                icon: Icons.payments,
                title: strings.featCurrencyTitle,
                subtitle: strings.featCurrencyDesc,
                onTap: () {
                  Navigator.pop(ctx);
                  _openNavigationScreen(visionAction: 'currency');
                },
              ),
              _buildFeatureTile(
                icon: Icons.document_scanner,
                title: strings.featOcrTitle,
                subtitle: strings.featOcrDesc,
                onTap: () {
                  Navigator.pop(ctx);
                  _openNavigationScreen(visionAction: 'ocr');
                },
              ),
              _buildFeatureTile(
                icon: Icons.directions_bus,
                title: isKn ? 'ಬಸ್ ಮಾರ್ಗ ರೀಡರ್' : 'Bus Route Reader',
                subtitle: isKn ? 'ಬಸ್ ಬೋರ್ಡ್ ಸಂಖ್ಯೆ ಓದುವಿಕೆ' : 'Reads incoming bus route boards',
                onTap: () {
                  Navigator.pop(ctx);
                  _openNavigationScreen(visionAction: 'bus');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHighlight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 26),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.textMuted),
        onTap: onTap,
      ),
    );
  }

  AssistantState _getCurrentState() {
    if (widget.voiceCoordinator != null) {
      return widget.voiceCoordinator!.assistantState;
    }
    if (_isProcessing) return AssistantState.processing;
    if (widget.ttsService.isSpeaking) return AssistantState.speaking;
    if (widget.speechService.isListening) return AssistantState.listening;
    return AssistantState.ready;
  }

  @override
  Widget build(BuildContext context) {
    final assistantName = widget.storageService.assistantName;
    final strings = _strings;
    final state = _getCurrentState();
    final bool isKn = strings.isKannada;
    final isListening = state == AssistantState.listening || widget.speechService.isListening;
    final isGeminiLive = widget.storageService.useGeminiLive;

    final String stateLabel;
    final Color stateColor;
    switch (state) {
      case AssistantState.listening:
        stateLabel = isKn ? 'ಆಲಿಸುತ್ತಿದೆ...' : 'Listening...';
        stateColor = AppTheme.accentCyan;
        break;
      case AssistantState.processing:
        stateLabel = isKn ? 'ಪ್ರಕ್ರಿಯೆಗೊಳಿಸಲಾಗುತ್ತಿದೆ...' : 'Processing...';
        stateColor = AppTheme.primary;
        break;
      case AssistantState.speaking:
        stateLabel = isKn ? 'ಮಾತನಾಡುತ್ತಿದೆ...' : 'Speaking...';
        stateColor = AppTheme.success;
        break;
      case AssistantState.ready:
        stateLabel = isKn ? 'ಸಿದ್ಧ' : 'Ready';
        stateColor = AppTheme.textSecondary;
        break;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Text(
          strings.appTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          Semantics(
            button: true,
            label: isKn ? 'ವೈಶಿಷ್ಟ್ಯಗಳ ಪರಿಚಯ' : 'Capabilities Guide',
            hint: 'Opens comprehensive guide of all navigation and vision features',
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: const Icon(Icons.menu_book, size: 20, color: AppTheme.accentCyan),
              ),
              onPressed: _showAllFeaturesDialog,
            ),
          ),
          Semantics(
            button: true,
            label: strings.settingsTitle,
            hint: 'Opens voice, speed, and language configuration',
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: const Icon(Icons.settings, size: 20, color: AppTheme.textPrimary),
              ),
              onPressed: _openSettings,
            ),
          ),
          Semantics(
            button: true,
            label: strings.help,
            hint: 'Speaks available voice commands',
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: const Icon(Icons.help_outline, size: 20, color: AppTheme.primary),
              ),
              onPressed: _speakHelp,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Status & Engine Pulse Strip
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isGeminiLive ? AppTheme.success : AppTheme.primary,
                          boxShadow: [
                            BoxShadow(
                              color: (isGeminiLive ? AppTheme.success : AppTheme.primary)
                                  .withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isGeminiLive ? 'Lux AI • Gemini Live' : 'Lux AI • Offline Vision',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isGeminiLive ? AppTheme.success : AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const Row(
                    children: [
                      Icon(Icons.gps_fixed, size: 12, color: AppTheme.accentCyan),
                      SizedBox(width: 4),
                      Text(
                        'GPS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.accentCyan),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.battery_charging_full, size: 14, color: AppTheme.success),
                    ],
                  ),
                ],
              ),
            ),

            // ZONE 1: Top Navigation Zone (~40% height)
            Expanded(
              flex: 40,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Semantics(
                  button: true,
                  label: isKn
                      ? 'ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ. ಲೈವ್ ಕ್ಯಾಮೆರಾ ಮತ್ತು ಮಾರ್ಗದರ್ಶನ'
                      : 'Start Navigation. Live Vision and Walking Guidance',
                  hint: 'Double tap anywhere in this area to open camera navigation',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _openNavigationScreen(promptDestination: true);
                      },
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFD97706), Color(0xFFB45309)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          border: Border.all(color: Colors.amber.shade200, width: 2),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                              child: const Icon(
                                Icons.explore,
                                color: Color(0xFFF59E0B),
                                size: 42,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isKn ? 'ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ' : 'START NAVIGATION',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                  letterSpacing: 1.2,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isKn ? 'ಲೈವ್ ದೃಷ್ಟಿ & ಪಾದಚಾರಿ ಮಾರ್ಗದರ್ಶನ' : 'Live Vision & Walking Guidance',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ZONE 2: Center/Lower Voice Zone (~45% height)
            Expanded(
              flex: 45,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Semantics(
                  button: true,
                  label: isKn
                      ? '$assistantName ಸಹಾಯಕನೊಂದಿಗೆ ಮಾತನಾಡಿ'
                      : 'Tap to talk to $assistantName',
                  hint: 'Double tap anywhere in this area to activate voice assistant',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _handleMicToggle();
                      },
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isListening ? AppTheme.accentCyan : AppTheme.glassBorder,
                            width: isListening ? 2.5 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isListening ? AppTheme.accentCyan : Colors.black)
                                  .withValues(alpha: isListening ? 0.35 : 0.5),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Live Waveform visualizer
                            LiveWaveformVisualizer(
                              isActive: isListening || state == AssistantState.speaking,
                              barColor: isListening ? AppTheme.accentCyan : AppTheme.primary,
                              height: 26,
                            ),
                            const SizedBox(height: 10),
                            // Large circular touch surface
                            ScaleTransition(
                              scale: isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: isListening
                                        ? [const Color(0xFF06B6D4), const Color(0xFF0891B2)]
                                        : [AppTheme.surfaceHighlight, const Color(0xFF1E293B)],
                                  ),
                                  border: Border.all(
                                    color: isListening ? Colors.white : AppTheme.accentCyan,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isListening ? AppTheme.accentCyan : AppTheme.primary)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isListening ? Icons.mic : Icons.mic_none,
                                  color: isListening ? Colors.black : AppTheme.primary,
                                  size: 44,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isKn
                                    ? '$assistantName ನೊಂದಿಗೆ ಮಾತನಾಡಿ'
                                    : 'TAP TO TALK TO ${assistantName.toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: 0.8,
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Status indicator pill
                            Semantics(
                              label: _assistantStatus.isNotEmpty ? _assistantStatus : stateLabel,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceHighlight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.glassBorder),
                                ),
                                child: Text(
                                  stateLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: stateColor,
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                            if (_lastVoiceTranscript.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  '"$_lastVoiceTranscript"',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: AppTheme.accentCyan,
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                isKn
                                    ? 'ಪಠ್ಯ ಓದಲು, ವಸ್ತು ಹುಡುಕಲು, ಕರೆನ್ಸಿ ಅಥವಾ ಮಾರ್ಗಗಳನ್ನು ಕೇಳಿ'
                                    : 'Ask to read text, find objects, check currency, or routes',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ZONE 3: Persistent Safety Bottom Dock (~15% height)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: const Border(
                  top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 18,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // Left: "Repeat Last Audio"
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: isKn ? 'ಕೊನೆಯ ಆಡಿಯೋ ಪುನರಾವರ್ತಿಸಿ' : 'Repeat Last Audio',
                        hint: 'Reads the last spoken message again',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.ttsService.repeat(
                                emptyMessage: strings.noMessageToRepeat,
                              );
                            },
                            child: Container(
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceHighlight,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.primary, width: 1.5),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.replay, color: AppTheme.primary, size: 24),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        isKn ? 'ಮತ್ತೆ ಹೇಳಿ' : 'Repeat Last Audio',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primary,
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Right: "EMERGENCY SOS"
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: isKn ? 'ತುರ್ತು ಎಸ್‌ಒಎಸ್' : 'EMERGENCY SOS',
                        hint: 'Activates emergency mode and calls emergency contact',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              HapticFeedback.heavyImpact();
                              _triggerEmergency();
                            },
                            child: Container(
                              height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.emergency, color: Colors.white, size: 24),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'EMERGENCY SOS',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
