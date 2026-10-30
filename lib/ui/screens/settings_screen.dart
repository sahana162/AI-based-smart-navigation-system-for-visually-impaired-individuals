import 'package:flutter/material.dart';
import '../../core/localization/app_strings.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/voice_command_parser.dart';
import '../../core/services/voice_session_coordinator.dart';
import '../../models/voice_command.dart';
import '../widgets/accessible_button.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService? speechService;
  final VoiceSessionCoordinator? voiceCoordinator;
  final VoidCallback onSettingsUpdated;

  const SettingsScreen({
    super.key,
    required this.storageService,
    required this.ttsService,
    this.speechService,
    this.voiceCoordinator,
    required this.onSettingsUpdated,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    implements VoiceCommandDelegate {
  late TextEditingController _nameController;
  late TextEditingController _emergencyContactController;
  final TextEditingController _newItemNameController = TextEditingController();
  final TextEditingController _newItemNotesController = TextEditingController();
  late double _speechRate;
  late double _speechPitch;
  late bool _hapticsEnabled;
  late bool _obstacleAlertsDefault;
  late bool _sonarCuesEnabled;
  late bool _autoTorchEnabled;
  late bool _directionalHapticsEnabled;
  late String _currentLanguageCode;
  late TextEditingController _geminiApiKeyController;
  late bool _useGeminiLive;
  bool _isAddingItem = false;
  bool _isAddingFriend = false;
  final TextEditingController _friendNameController = TextEditingController();
  bool _hasSpokenGreeting = false;

  final List<String> _namePresets = ['Lux', 'Gemini', 'Nova', 'Companion'];

  @override
  String get screenName => 'Settings';

  @override
  void initState() {
    super.initState();
    widget.voiceCoordinator?.registerDelegate(this);
    _nameController =
        TextEditingController(text: widget.storageService.assistantName);
    _emergencyContactController =
        TextEditingController(text: widget.storageService.emergencyContact);
    _geminiApiKeyController =
        TextEditingController(text: widget.storageService.geminiApiKey);
    _useGeminiLive = widget.storageService.useGeminiLive;
    _speechRate = widget.storageService.speechRate;
    _speechPitch = widget.storageService.speechPitch;
    _hapticsEnabled = widget.storageService.hapticsEnabled;
    _obstacleAlertsDefault = widget.storageService.obstacleAlertsDefaultEnabled;
    _sonarCuesEnabled = widget.storageService.sonarCuesEnabled;
    _autoTorchEnabled = widget.storageService.autoTorchEnabled;
    _directionalHapticsEnabled = widget.storageService.directionalHapticsEnabled;
    _currentLanguageCode = widget.storageService.appLanguage;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasSpokenGreeting || !mounted) return;
      _hasSpokenGreeting = true;
      final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
      final greeting = strings.isKannada
          ? 'ಸೆಟ್ಟಿಂಗ್ಸ್ ಪರದೆ. ನೀವು ಸಹಾಯಕನ ಹೆಸರು, ಭಾಷೆ ಮತ್ತು ಧ್ವನಿ ವೇಗವನ್ನು ಕಸ್ಟಮೈಸ್ ಮಾಡಬಹುದು.'
          : 'Settings screen. You can customize the assistant name, language, speech rate, and preferences here.';
      widget.ttsService.speak(greeting);
    });
  }

  @override
  void dispose() {
    widget.voiceCoordinator?.unregisterDelegate(this);
    _nameController.dispose();
    _emergencyContactController.dispose();
    _newItemNameController.dispose();
    _newItemNotesController.dispose();
    _geminiApiKeyController.dispose();
    _friendNameController.dispose();
    super.dispose();
  }

  Future<void> _switchLanguage(String code) async {
    final newLang = AppLanguage.fromCode(code);
    final strings = AppStrings(newLang);

    setState(() {
      _currentLanguageCode = code;
    });

    await widget.storageService.setAppLanguage(code);

    // Verify TTS availability on device
    final isAvailable = await widget.ttsService.setLanguage(newLang.ttsLocale);

    widget.onSettingsUpdated();

    if (newLang == AppLanguage.kn && !isAvailable) {
      await widget.ttsService.speak(
        strings.kannadaTtsUnavailableWarning,
      );
    } else {
      await widget.ttsService.speak(
        strings.languageChangedConfirmation(newLang),
      );
    }
  }

  Future<void> _saveAssistantName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    await widget.storageService.setAssistantName(clean);
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? 'ಸಹಾಯಕನ ಹೆಸರನ್ನು $clean ಗೆ ನವೀಕರಿಸಲಾಗಿದೆ.'
        : 'Assistant name updated to $clean.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _saveSpeechRate(double rate) async {
    setState(() => _speechRate = rate);
    await widget.storageService.setSpeechRate(rate);
    await widget.ttsService.updateSettings(rate: rate);
    widget.onSettingsUpdated();
  }

  Future<void> _saveSpeechPitch(double pitch) async {
    setState(() => _speechPitch = pitch);
    await widget.storageService.setSpeechPitch(pitch);
    await widget.ttsService.updateSettings(pitch: pitch);
    widget.onSettingsUpdated();
  }

  Future<void> _toggleHaptics(bool val) async {
    setState(() => _hapticsEnabled = val);
    await widget.storageService.setHapticsEnabled(val);
    widget.onSettingsUpdated();

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? (val ? 'ಕಂಪನ ಪ್ರತಿಕ್ರಿಯೆ ಸಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.' : 'ಕಂಪನ ಪ್ರತಿಕ್ರಿಯೆ ನಿಷ್ಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.')
        : (val ? 'Vibration and haptics enabled.' : 'Vibration and haptics disabled.');
    await widget.ttsService.speak(speech);
  }

  Future<void> _saveEmergencyContact(String contact) async {
    final clean = contact.trim();
    if (clean.isEmpty) return;
    await widget.storageService.setEmergencyContact(clean);
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? 'ತುರ್ತು ಸಂಪರ್ಕ ಸಂಖ್ಯೆಯನ್ನು $clean ಗೆ ಉಳಿಸಲಾಗಿದೆ.'
        : 'Emergency contact number saved as $clean.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _toggleObstacleAlertsDefault(bool val) async {
    setState(() => _obstacleAlertsDefault = val);
    await widget.storageService.setObstacleAlertsDefaultEnabled(val);
    widget.onSettingsUpdated();

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? (val
            ? 'ಡೀಫಾಲ್ಟ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ಸಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.'
            : 'ಡೀಫಾಲ್ಟ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ನಿಷ್ಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.')
        : (val
            ? 'Default obstacle alerts enabled.'
            : 'Default obstacle alerts disabled.');
    await widget.ttsService.speak(speech);
  }

  Future<void> _toggleSonarCues(bool val) async {
    setState(() => _sonarCuesEnabled = val);
    await widget.storageService.setSonarCuesEnabled(val);
    widget.onSettingsUpdated();

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? (val ? 'ಅಕೌಸ್ಟಿಕ್ ಸೋನಾರ್ ಸಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.' : 'ಅಕೌಸ್ಟಿಕ್ ಸೋನಾರ್ ನಿಷ್ಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.')
        : (val ? 'Acoustic sonar cues enabled.' : 'Acoustic sonar cues disabled.');
    await widget.ttsService.speak(speech);
  }

  Future<void> _toggleAutoTorch(bool val) async {
    setState(() => _autoTorchEnabled = val);
    await widget.storageService.setAutoTorchEnabled(val);
    widget.onSettingsUpdated();

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? (val ? 'ಸ್ವಯಂಚಾಲಿತ ಬೆಳಕು ಸಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.' : 'ಸ್ವಯಂಚಾಲಿತ ಬೆಳಕು ನಿಷ್ಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.')
        : (val ? 'Automatic low-light flashlight enabled.' : 'Automatic low-light flashlight disabled.');
    await widget.ttsService.speak(speech);
  }

  Future<void> _toggleDirectionalHaptics(bool val) async {
    setState(() => _directionalHapticsEnabled = val);
    await widget.storageService.setDirectionalHapticsEnabled(val);
    widget.onSettingsUpdated();

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? (val
            ? 'ದಿಕ್ಕಿನ ತಿರುವು ಕಂಪನ ಮಾರ್ಗದರ್ಶನ ಸಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.'
            : 'ದಿಕ್ಕಿನ ತಿರುವು ಕಂಪನ ಮಾರ್ಗದರ್ಶನ ನಿಷ್ಕ್ರಿಯಗೊಳಿಸಲಾಗಿದೆ.')
        : (val
            ? 'Directional turn haptic pulses enabled.'
            : 'Directional turn haptic pulses disabled.');
    await widget.ttsService.speak(speech);
  }

  Future<void> _removeFavoritePlace(String key) async {
    await widget.storageService.removeFavoritePlace(key);
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? '$key ಸ್ಥಳವನ್ನು ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳಿಂದ ತೆಗೆದುಹಾಕಲಾಗಿದೆ.'
        : '$key removed from favorite places.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _clearFavoritePlaces() async {
    await widget.storageService.clearFavoritePlaces();
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? 'ಎಲ್ಲ ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳನ್ನು ತೆರವುಗೊಳಿಸಲಾಗಿದೆ.'
        : 'All favorite places cleared.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _readFavoritePlaces() async {
    final places = widget.storageService.favoritePlaces;
    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    if (places.isEmpty) {
      final msg = strings.isKannada
          ? 'ಯಾವುದೇ ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳು ಉಳಿಸಲಾಗಿಲ್ಲ. ನೀವು "ಸೇವ್ ಆಸ್ ಹೋಮ್" ಎಂದು ಹೇಳಿ ನಿಮ್ಮ ಪ್ರಸ್ತುತ ಸ್ಥಳವನ್ನು ಉಳಿಸಬಹುದು.'
          : 'No favorite places saved yet. You can say "Save as home" or "Save as work" during navigation to save your current location.';
      await widget.ttsService.speak(msg);
      return;
    }

    final buffer = StringBuffer();
    for (final data in places) {
      final name = data['name'] ?? data['tag'] ?? 'Place';
      buffer.write('$name, ');
    }
    final listText = buffer.toString();
    final msg = strings.isKannada
        ? 'ಉಳಿಸಲಾದ ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳು: $listText'
        : 'Your saved favorite places: $listText';
    await widget.ttsService.speak(msg);
  }

  Future<void> _deleteSavedItem(String name) async {
    await widget.storageService.removeSavedItem(name);
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? '$name ವಸ್ತುವನ್ನು ನೆನಪಿನಿಂದ ತೆಗೆದುಹಾಕಲಾಗಿದೆ.'
        : '$name removed from memory.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _addManualSavedItem() async {
    final name = _newItemNameController.text.trim();
    final notes = _newItemNotesController.text.trim();
    if (name.isEmpty) return;

    await widget.storageService.addSavedItem(name, notes: notes.isNotEmpty ? notes : null);
    _newItemNameController.clear();
    _newItemNotesController.clear();
    _isAddingItem = false;
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? '$name ವಸ್ತುವನ್ನು ಮೆಮೊರಿಯಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ.'
        : '$name saved to memory.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _clearAllSavedItems() async {
    await widget.storageService.clearAllSavedItems();
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? 'ಎಲ್ಲ ಉಳಿಸಿದ ವಸ್ತುಗಳನ್ನು ತೆರವುಗೊಳಿಸಲಾಗಿದೆ.'
        : 'All saved items have been cleared from memory.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _addManualFriend() async {
    final name = _friendNameController.text.trim();
    if (name.isEmpty) return;
    final friend = FriendProfile(
      id: 'friend_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      imagePath: '',
      enrolledAt: DateTime.now(),
    );
    await widget.storageService.saveFriend(friend);
    _friendNameController.clear();
    widget.onSettingsUpdated();
    setState(() => _isAddingFriend = false);
    await widget.ttsService.speak('Added $name to saved friends.');
  }

  Future<void> _deleteFriend(String id, String name) async {
    await widget.storageService.deleteFriend(id);
    widget.onSettingsUpdated();
    setState(() {});
    await widget.ttsService.speak('Removed $name from saved friends.');
  }

  Future<void> _clearDestinationCache() async {
    await widget.storageService.clearDestinationCache();
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final speech = strings.isKannada
        ? 'ಸ್ಥಳಗಳ ಕ್ಯಾಶ್ ತೆರವುಗೊಳಿಸಲಾಗಿದೆ.'
        : 'Destination location cache has been cleared.';
    await widget.ttsService.speak(speech);
  }

  Future<void> _readCachedDestinations() async {
    final places = widget.storageService.recentDestinations;
    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    if (places.isEmpty) {
      await widget.ttsService.speak(strings.noCachedDestinations);
      return;
    }
    final names = places.map((p) => p['query'] ?? p['display_name'] ?? '').where((s) => s.isNotEmpty).join(', ');
    final msg = strings.isKannada
        ? 'ಕ್ಯಾಶ್ ಮಾಡಲಾದ ${places.length} ಸ್ಥಳಗಳು: $names.'
        : 'You have ${places.length} cached destinations: $names.';
    await widget.ttsService.speak(msg);
  }

  Future<void> _testVoice() async {
    final name = widget.storageService.assistantName;
    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    await widget.ttsService.speak(strings.testVoiceMessage(name));
  }

  Future<void> _resetDefaults() async {
    await widget.storageService.resetToDefaults();
    _nameController.text = StorageService.defaultAssistantName;
    _emergencyContactController.text = StorageService.defaultEmergencyContact;
    _speechRate = StorageService.defaultSpeechRate;
    _speechPitch = StorageService.defaultSpeechPitch;
    _hapticsEnabled = StorageService.defaultHapticsEnabled;
    _obstacleAlertsDefault = StorageService.defaultObstacleAlertsEnabled;
    _sonarCuesEnabled = StorageService.defaultSonarCuesEnabled;
    _autoTorchEnabled = StorageService.defaultAutoTorchEnabled;
    _directionalHapticsEnabled = StorageService.defaultDirectionalHapticsEnabled;
    _currentLanguageCode = StorageService.defaultAppLanguage;

    await widget.ttsService.setLanguage(AppLanguage.en.ttsLocale);
    await widget.ttsService.updateSettings(rate: _speechRate, pitch: _speechPitch);
    widget.onSettingsUpdated();
    setState(() {});

    final strings = AppStrings(AppLanguage.en);
    await widget.ttsService.speak(strings.resetDefaultsMessage);
  }

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.goBack:
        widget.ttsService.speak('Returning to home screen.');
        Navigator.pop(context);
        return true;
      case VoiceCommandType.increaseSpeechSpeed:
        _saveSpeechRate((_speechRate + 0.1).clamp(0.2, 1.0));
        widget.ttsService.speak('Speech speed increased.');
        return true;
      case VoiceCommandType.decreaseSpeechSpeed:
        _saveSpeechRate((_speechRate - 0.1).clamp(0.2, 1.0));
        widget.ttsService.speak('Speech speed decreased.');
        return true;
      case VoiceCommandType.switchLanguage:
        final target = command.argument ?? 'en';
        _switchLanguage(target);
        return true;
      case VoiceCommandType.toggleObstacleAlerts:
        _toggleObstacleAlertsDefault(!_obstacleAlertsDefault);
        return true;
      case VoiceCommandType.repeat:
        _testVoice();
        return true;
      case VoiceCommandType.help:
        widget.ttsService.speak(
          'In settings, say: Go back, Faster, Slower, Toggle obstacle alerts, Test voice, Switch to Kannada, or Reset defaults.',
        );
        return true;
      case VoiceCommandType.stopSpeaking:
        widget.ttsService.stop();
        return true;
      case VoiceCommandType.stopListening:
        if (widget.voiceCoordinator != null) {
          widget.voiceCoordinator!.stopListening(spokenFeedback: true);
        } else {
          widget.speechService?.stopListening();
          widget.ttsService.speak('Stopped listening.');
        }
        return true;
      default:
        return false;
    }
  }

  Future<void> _handleMicToggle() async {
    if (widget.voiceCoordinator != null) {
      await widget.voiceCoordinator!.toggleListening();
      return;
    }

    final speechService = widget.speechService;
    if (speechService == null) return;
    final ttsService = widget.ttsService;

    if (speechService.isListening) {
      await speechService.stopListening();
      await ttsService.speak('Stopped listening.');
    } else {
      await ttsService.stop();
      final started = await speechService.startListening(
        localeId: _currentLanguageCode == 'kn' ? 'kn_IN' : 'en_US',
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

  Future<void> _saveGeminiApiKey(String key) async {
    final clean = key.trim();
    await widget.storageService.setGeminiApiKey(clean);
    widget.onSettingsUpdated();
    setState(() {});
    final isKn = widget.storageService.appLanguage == 'kn';
    final msg = isKn
        ? 'ಜೆಮಿನಿ ಎಪಿಐ ಕೀಯನ್ನು ಉಳಿಸಲಾಗಿದೆ.'
        : 'Gemini API key saved.';
    widget.ttsService.speak(msg);
  }

  Future<void> _toggleGeminiLive(bool val) async {
    setState(() {
      _useGeminiLive = val;
    });
    await widget.storageService.setUseGeminiLive(val);
    widget.onSettingsUpdated();
    final isKn = widget.storageService.appLanguage == 'kn';
    final msg = isKn
        ? (val ? 'ಜೆಮಿನಿ ಲೈವ್ ಮೋಡ್ ಸಕ್ರಿಯವಾಗಿದೆ.' : 'ಜೆಮಿನಿ ಲೈವ್ ಮೋಡ್ ನಿಷ್ಕ್ರಿಯವಾಗಿದೆ.')
        : (val ? 'Gemini Live multimodal mode enabled.' : 'Gemini Live multimodal mode disabled.');
    widget.ttsService.speak(msg);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(AppLanguage.fromCode(_currentLanguageCode));
    final currentName = widget.storageService.assistantName;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.settingsTitle),
        leading: Semantics(
          label: strings.backToHome,
          hint: strings.backToHomeHint,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          if (widget.speechService != null)
            AnimatedBuilder(
              animation: widget.speechService!,
              builder: (context, _) => IconButton(
                icon: Icon(
                  widget.speechService!.isListening ? Icons.mic : Icons.mic_none,
                  color: widget.speechService!.isListening ? AppTheme.danger : AppTheme.primary,
                  size: 28,
                ),
                onPressed: _handleMicToggle,
                tooltip: 'Tap to talk',
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTap: _handleMicToggle,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
            // Section 1: Language Selection
            Semantics(
              header: true,
              child: Text(
                strings.languageSectionTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: _currentLanguageCode == 'en',
                    label: 'English language',
                    hint: _currentLanguageCode == 'en'
                        ? 'Currently selected'
                        : 'Double tap to switch to English',
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentLanguageCode == 'en'
                            ? AppTheme.accentCyan
                            : AppTheme.surface,
                        foregroundColor: _currentLanguageCode == 'en'
                            ? Colors.black
                            : AppTheme.textPrimary,
                        minimumSize: const Size(double.infinity, 54),
                        side: BorderSide(
                          color: _currentLanguageCode == 'en'
                              ? AppTheme.accentCyan
                              : AppTheme.border,
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _switchLanguage('en'),
                      child: const Text(
                        'English',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: _currentLanguageCode == 'kn',
                    label: 'Kannada language ಕನ್ನಡ',
                    hint: _currentLanguageCode == 'kn'
                        ? 'Currently selected'
                        : 'ಕನ್ನಡ ಭಾಷೆಗೆ ಬದಲಾಯಿಸಲು ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ',
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentLanguageCode == 'kn'
                            ? AppTheme.accentCyan
                            : AppTheme.surface,
                        foregroundColor: _currentLanguageCode == 'kn'
                            ? Colors.black
                            : AppTheme.textPrimary,
                        minimumSize: const Size(double.infinity, 54),
                        side: BorderSide(
                          color: _currentLanguageCode == 'kn'
                              ? AppTheme.accentCyan
                              : AppTheme.border,
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _switchLanguage('kn'),
                      child: const Text(
                        'ಕನ್ನಡ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 2: Assistant Name
            Semantics(
              header: true,
              child: Text(
                strings.assistantNameTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${strings.currentlySetTo} $currentName',
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: '${strings.customNameLabel}. $currentName',
              hint: strings.saveNameBtn,
              textField: true,
              child: TextField(
                controller: _nameController,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.surface,
                  labelText: strings.customNameLabel,
                  labelStyle: const TextStyle(color: AppTheme.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.border, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
                onSubmitted: _saveAssistantName,
              ),
            ),
            const SizedBox(height: 12),
            AccessibleButton(
              label: strings.saveNameBtn,
              icon: Icons.check,
              isPrimary: true,
              semanticHint: strings.saveNameBtn,
              onPressed: () => _saveAssistantName(_nameController.text),
            ),
            const SizedBox(height: 14),
            Text(
              strings.choosePreset,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _namePresets.map((preset) {
                final isSelected = currentName.toLowerCase() == preset.toLowerCase();
                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: '${strings.assistantNameTitle} $preset',
                  hint: isSelected ? 'Currently active' : 'Double tap to select',
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isSelected ? AppTheme.accentCyan : AppTheme.surface,
                      foregroundColor:
                          isSelected ? Colors.black : AppTheme.textPrimary,
                      minimumSize: const Size(120, 50),
                      side: BorderSide(
                        color: isSelected ? AppTheme.accentCyan : AppTheme.border,
                        width: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      _nameController.text = preset;
                      _saveAssistantName(preset);
                    },
                    child: Text(
                      preset,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section: Gemini Multimodal Live AI Companion
            Semantics(
              header: true,
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppTheme.accentCyan, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      strings.isKannada ? 'ಜೆಮಿನಿ ಲೈವ್ AI ಸಹಾಯಕ' : 'Gemini Live Multimodal AI',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentCyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.isKannada
                  ? 'ನೈಜ ಸಮಯದ ಧ್ವನಿ, ನಿರಂತರ ಕ್ಯಾಮೆರಾ ದೃಷ್ಟಿ ಮತ್ತು ಸ್ವಾಭಾವಿಕ ಕನ್ನಡ ಮತ್ತು ಇಂಗ್ಲಿಷ್ ಸಂವಾದಕ್ಕಾಗಿ ಗೂಗಲ್ ಜೆಮಿನಿ ಲೈವ್ ಬಳಸಿ.'
                  : 'Power Gemini with real-time bidirectional audio, continuous vision perception, and natural Kannada & English conversation.',
              style: const TextStyle(
                fontSize: 15,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _useGeminiLive ? AppTheme.accentCyan : AppTheme.border,
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        strings.isKannada ? 'ಜೆಮಿನಿ ಲೈವ್ ಸಹಾಯಕ ಸಕ್ರಿಯಗೊಳಿಸಿ' : 'Enable Gemini Live Companion',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      subtitle: Text(
                        _useGeminiLive
                            ? (strings.isKannada ? 'ಸಕ್ರಿಯವಾಗಿದೆ - ನೈಜ ಸಮಯದ ಬುದ್ಧಿವಂತ ಸಹಾಯಕ' : 'Active - Intelligent multimodal companion')
                            : (strings.isKannada ? 'ಸ್ಥಳೀಯ ಆಫ್‌ಲೈನ್ ಪರಿಕರಗಳನ್ನು ಬಳಸಲಾಗುತ್ತಿದೆ' : 'Offline local rules engine mode'),
                        style: TextStyle(
                          fontSize: 14,
                          color: _useGeminiLive ? AppTheme.success : AppTheme.textMuted,
                        ),
                      ),
                      value: _useGeminiLive,
                      activeThumbColor: AppTheme.accentCyan,
                      onChanged: _toggleGeminiLive,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    label: strings.isKannada ? 'ಜೆಮಿನಿ ಎಪಿಐ ಕೀ ನಮೂದಿಸಿ' : 'Enter Gemini API Key',
                    textField: true,
                    child: TextField(
                      controller: _geminiApiKeyController,
                      obscureText: true,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.background,
                        labelText: strings.isKannada ? 'ಜೆಮಿನಿ ಎಪಿಐ ಕೀ (API Key)' : 'Google Gemini API Key',
                        labelStyle: const TextStyle(color: AppTheme.primary, fontSize: 16),
                        hintText: 'AIzaSy...',
                        hintStyle: const TextStyle(color: AppTheme.textMuted),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.accentCyan, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  AccessibleButton(
                    label: strings.isKannada ? 'ಎಪಿಐ ಕೀ ಉಳಿಸಿ' : 'Save Gemini API Key',
                    icon: Icons.key,
                    onPressed: () => _saveGeminiApiKey(_geminiApiKeyController.text),
                  ),
                ],
              ),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 3: Speech Speed
            Semantics(
              header: true,
              child: Text(
                strings.speechSpeedTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Rate: ${_speechRate.toStringAsFixed(2)}x',
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            Semantics(
              label: '${strings.speechSpeedTitle} ${_speechRate.toStringAsFixed(2)}',
              slider: true,
              child: Slider(
                value: _speechRate,
                min: 0.2,
                max: 1.0,
                divisions: 8,
                activeColor: AppTheme.primary,
                inactiveColor: AppTheme.border,
                onChanged: (val) => _saveSpeechRate(val),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: AccessibleButton(
                    label: strings.slowerBtn,
                    icon: Icons.remove,
                    semanticHint: strings.slowerBtn,
                    onPressed: _speechRate > 0.25
                        ? () => _saveSpeechRate((_speechRate - 0.1).clamp(0.2, 1.0))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AccessibleButton(
                    label: strings.fasterBtn,
                    icon: Icons.add,
                    semanticHint: strings.fasterBtn,
                    onPressed: _speechRate < 0.95
                        ? () => _saveSpeechRate((_speechRate + 0.1).clamp(0.2, 1.0))
                        : null,
                  ),
                ),
              ],
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 4: Speech Pitch
            Semantics(
              header: true,
              child: Text(
                strings.voicePitchTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pitch: ${_speechPitch.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            Semantics(
              label: '${strings.voicePitchTitle} ${_speechPitch.toStringAsFixed(2)}',
              slider: true,
              child: Slider(
                value: _speechPitch,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                activeColor: AppTheme.primary,
                inactiveColor: AppTheme.border,
                onChanged: (val) => _saveSpeechPitch(val),
              ),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 5: Haptic Feedback Toggle
            Semantics(
              label: strings.hapticsTitle,
              hint: _hapticsEnabled ? 'Currently enabled' : 'Currently disabled',
              toggled: _hapticsEnabled,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.primary,
                title: Text(
                  strings.hapticsTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  strings.hapticsSubtitle,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                value: _hapticsEnabled,
                onChanged: _toggleHaptics,
              ),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 5b: Default Live Obstacle Alerts
            Semantics(
              label: strings.obstacleAlertsDefaultTitle,
              hint: _obstacleAlertsDefault ? 'Currently enabled' : 'Currently disabled',
              toggled: _obstacleAlertsDefault,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.accentCyan,
                title: Text(
                  strings.obstacleAlertsDefaultTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  strings.obstacleAlertsDefaultSubtitle,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                value: _obstacleAlertsDefault,
                onChanged: _toggleObstacleAlertsDefault,
              ),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 5c: Acoustic Sonar Earcons
            Semantics(
              label: strings.isKannada ? 'ಅಕೌಸ್ಟಿಕ್ ಸೋನಾರ್' : 'Acoustic Sonar Distance Cues',
              hint: _sonarCuesEnabled ? 'Currently enabled' : 'Currently disabled',
              toggled: _sonarCuesEnabled,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.primary,
                title: Text(
                  strings.isKannada ? 'ಅಕೌಸ್ಟಿಕ್ ಸೋನಾರ್ (ಶಬ್ದ ಸಂಕೇತ)' : 'Acoustic Sonar Distance Cues',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  strings.isKannada
                      ? 'ಅಡೆತಡೆ ಸಮೀಪಿಸಿದಾಗ ವೇಗವಾಗಿ ಶಬ್ದ ಕ್ಲಿಕ್ ಮಾಡುತ್ತದೆ, ರಸ್ತೆ ಶಬ್ದ ಕೇಳಲು ಅನುವು ಮಾಡಿಕೊಡುತ್ತದೆ'
                      : 'Emits gentle audio sonar pulses that accelerate near obstacles without constant talking',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                value: _sonarCuesEnabled,
                onChanged: _toggleSonarCues,
              ),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 5d: Automatic Low-Light Flashlight
            Semantics(
              label: strings.isKannada ? 'ಸ್ವಯಂಚಾಲಿತ ಬೆಳಕು' : 'Low-Light Auto Flashlight',
              hint: _autoTorchEnabled ? 'Currently enabled' : 'Currently disabled',
              toggled: _autoTorchEnabled,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.accentYellow,
                title: Text(
                  strings.isKannada ? 'ಸ್ವಯಂಚಾಲಿತ ಬೆಳಕು (ಆಟೋ ಟಾರ್ಚ್)' : 'Low-Light Auto Flashlight',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  strings.isKannada
                      ? 'ಕತ್ತಲೆಯ ಕೋಣೆಗಳು ಅಥವಾ ರಾತ್ರಿ ವೇಳೆ ಕ್ಯಾಮೆರಾ ಬೆಳಕನ್ನು ಸ್ವಯಂಚಾಲಿತವಾಗಿ ಆನ್ ಮಾಡುತ್ತದೆ'
                      : 'Automatically illuminates the camera torch in pitch black or poorly lit environments',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                value: _autoTorchEnabled,
                onChanged: _toggleAutoTorch,
              ),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 5e: Directional Turn Haptic Pulses
            Semantics(
              label: strings.isKannada ? 'ದಿಕ್ಕಿನ ತಿರುವು ಕಂಪನ ಮಾರ್ಗದರ್ಶನ' : 'Directional Turn Haptics',
              hint: _directionalHapticsEnabled ? 'Currently enabled' : 'Currently disabled',
              toggled: _directionalHapticsEnabled,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.accentCyan,
                title: Text(
                  strings.isKannada ? 'ದಿಕ್ಕಿನ ತಿರುವು ಕಂಪನ ಮಾರ್ಗದರ್ಶನ' : 'Directional Turn Haptics',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  strings.isKannada
                      ? 'ತಿರುವುಗಳ ವಿಭಿನ್ನ ಕಂಪನ ಮಾದರಿ: ಎಡಕ್ಕೆ 2 ಕಂಪನಗಳು, ಬಲಕ್ಕೆ 3 ಕಂಪನಗಳು, ತಲುಪಿದಾಗ ಡಬಲ್ ಹೆವಿ ಇಂಪ್ಯಾಕ್ಟ್'
                      : 'Distinct tactile pulses for turns: 2 pulses for left, 3 pulses for right, double impact upon arrival',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                value: _directionalHapticsEnabled,
                onChanged: _toggleDirectionalHaptics,
              ),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 6: Emergency Contact Number
            Semantics(
              header: true,
              child: Text(
                strings.emergencyContactTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.danger,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.emergencyContactSubtitle,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: '${strings.emergencyContactTitle}. ${_emergencyContactController.text}',
              hint: strings.saveContactBtn,
              textField: true,
              child: TextField(
                controller: _emergencyContactController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.surface,
                  prefixIcon: const Icon(Icons.phone_in_talk, color: AppTheme.danger),
                  labelText: strings.emergencyContactTitle,
                  labelStyle: const TextStyle(color: AppTheme.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.border, width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.danger, width: 2),
                  ),
                ),
                onSubmitted: _saveEmergencyContact,
              ),
            ),
            const SizedBox(height: 12),
            AccessibleButton(
              label: strings.saveContactBtn,
              icon: Icons.check,
              isDestructive: true,
              semanticHint: strings.saveContactBtn,
              onPressed: () => _saveEmergencyContact(_emergencyContactController.text),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ['112', '108', '100', '911'].map((preset) {
                final isSelected = _emergencyContactController.text.trim() == preset;
                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Emergency number $preset',
                  hint: isSelected ? 'Currently set' : 'Double tap to set',
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? AppTheme.danger : AppTheme.surface,
                      foregroundColor: isSelected ? Colors.white : AppTheme.textPrimary,
                      minimumSize: const Size(80, 44),
                      side: BorderSide(
                        color: isSelected ? AppTheme.danger : AppTheme.border,
                        width: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      _emergencyContactController.text = preset;
                      _saveEmergencyContact(preset);
                    },
                    child: Text(
                      preset,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 7: Saved Items Memory
            Semantics(
              header: true,
              child: Text(
                strings.savedItemsTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.savedItemsSubtitle,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.storageService.savedItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: AppTheme.textMuted, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.noSavedItems,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Column(
                children: widget.storageService.savedItems.map((item) {
                  final itemName = item['name'] ?? 'Item';
                  final itemNotes = item['notes'] ?? '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark, color: AppTheme.primary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (itemNotes.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  itemNotes,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Semantics(
                          label: 'Delete $itemName from memory',
                          hint: 'Double tap to remove item',
                          button: true,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 26),
                            onPressed: () => _deleteSavedItem(itemName),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              AccessibleButton(
                label: strings.clearAllSavedBtn,
                icon: Icons.delete_sweep,
                isDestructive: true,
                semanticHint: strings.clearAllSavedBtn,
                onPressed: _clearAllSavedItems,
              ),
            ],
            const SizedBox(height: 14),
            if (!_isAddingItem)
              AccessibleButton(
                label: strings.addItemBtn,
                icon: Icons.add,
                onPressed: () => setState(() => _isAddingItem = true),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.accentCyan, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _newItemNameController,
                      style: const TextStyle(fontSize: 17, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.background,
                        labelText: strings.itemNameLabel,
                        labelStyle: const TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newItemNotesController,
                      style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.background,
                        labelText: strings.itemNotesLabel,
                        labelStyle: const TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AccessibleButton(
                            label: strings.saveNameBtn,
                            icon: Icons.check,
                            isPrimary: true,
                            onPressed: _addManualSavedItem,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AccessibleButton(
                            label: 'Cancel',
                            icon: Icons.close,
                            onPressed: () => setState(() => _isAddingItem = false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 7b: Saved Favorite Places (Home & Work)
            Semantics(
              header: true,
              child: Text(
                strings.isKannada ? 'ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳು (ಮನೆ ಮತ್ತು ಕಚೇರಿ)' : 'Favorite Places (Home & Work)',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accentGreen,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.isKannada
                  ? 'ನ್ಯಾವಿಗೇಷನ್ ಸಮಯದಲ್ಲಿ "ಸೇವ್ ಆಸ್ ಹೋಮ್" ಎಂದು ಹೇಳುವ ಮೂಲಕ ನಿಮ್ಮ ಜಿಪಿಎಸ್ ಸ್ಥಳವನ್ನು ತ್ವರಿತ ಬುಕ್‌ಮಾರ್ಕ್ ಮಾಡಿ'
                  : 'Quick bookmarks for instant routing. Say "Save as home" or "Save as work" during navigation to save GPS coordinates.',
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.storageService.favoritePlaces.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_outline, color: AppTheme.textMuted, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.isKannada
                            ? 'ಯಾವುದೇ ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳು ಉಳಿಸಲಾಗಿಲ್ಲ. "ನ್ಯಾವಿಗೇಟ್ ಟು ಹೋಮ್" ಎಂದು ಹೇಳುವ ಮೊದಲು ಸ್ಥಳವನ್ನು ಸೇವ್ ಮಾಡಿ.'
                            : 'No favorite places saved yet. Say "Save as home" while at home to bookmark it.',
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Column(
                children: widget.storageService.favoritePlaces.map((data) {
                  final key = data['tag']?.toString() ?? data['name']?.toString() ?? '';
                  final name = data['name']?.toString() ?? key;
                  final addr = data['address']?.toString() ?? '';
                  final lat = data['lat'] != null ? (data['lat'] as num).toDouble().toStringAsFixed(4) : '';
                  final lon = data['lon'] != null ? (data['lon'] as num).toDouble().toStringAsFixed(4) : '';
                  final isHome = key.toLowerCase() == 'home';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isHome ? AppTheme.accentGreen : AppTheme.accentCyan,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isHome ? Icons.home_rounded : Icons.work_rounded,
                          color: isHome ? AppTheme.accentGreen : AppTheme.accentCyan,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (addr.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  addr,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                              if (lat.isNotEmpty && lon.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'GPS: $lat, $lon',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    color: AppTheme.accentYellow,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Semantics(
                          label: 'Delete $name from favorite places',
                          hint: 'Double tap to remove bookmark',
                          button: true,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 26),
                            onPressed: () => _removeFavoritePlace(key),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              AccessibleButton(
                label: strings.isKannada ? 'ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳನ್ನು ಆಲಿಸಿ' : 'Read Favorite Places Aloud',
                icon: Icons.record_voice_over,
                semanticHint: strings.isKannada ? 'ಉಳಿಸಲಾದ ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳನ್ನು ಓದುತ್ತದೆ' : 'Speaks saved favorite places',
                onPressed: _readFavoritePlaces,
              ),
              const SizedBox(height: 10),
              AccessibleButton(
                label: strings.isKannada ? 'ಎಲ್ಲ ಮೆಚ್ಚಿನ ಸ್ಥಳಗಳನ್ನು ತೆರವುಗೊಳಿಸಿ' : 'Clear Favorite Places',
                icon: Icons.delete_sweep,
                isDestructive: true,
                semanticHint: 'Deletes all saved favorite locations',
                onPressed: _clearFavoritePlaces,
              ),
            ],

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 7c: Saved Friends & Proximity Reminders
            Semantics(
              header: true,
              child: Text(
                strings.savedFriendsTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.savedFriendsSubtitle,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.storageService.getSavedFriends().isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline, color: AppTheme.textMuted, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.noSavedFriends,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Column(
                children: widget.storageService.getSavedFriends().map((friend) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.face, color: AppTheme.primary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                friend.name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Enrolled: ${friend.enrolledAt.toString().split(' ')[0]}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Semantics(
                          label: 'Delete ${friend.name} from saved friends',
                          hint: 'Double tap to remove friend',
                          button: true,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 26),
                            onPressed: () => _deleteFriend(friend.id, friend.name),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            if (!_isAddingFriend)
              AccessibleButton(
                label: strings.addFriendBtn,
                icon: Icons.person_add,
                onPressed: () => setState(() => _isAddingFriend = true),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.accentCyan, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _friendNameController,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.background,
                        labelText: strings.friendNameHint,
                        labelStyle: const TextStyle(color: AppTheme.textSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AccessibleButton(
                            label: 'Save Friend',
                            icon: Icons.check,
                            isPrimary: true,
                            onPressed: _addManualFriend,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AccessibleButton(
                            label: 'Cancel',
                            icon: Icons.close,
                            onPressed: () => setState(() => _isAddingFriend = false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 8: Cached Destinations & Offline Places
            Semantics(
              header: true,
              child: Text(
                strings.cachedDestinationsTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.cachedDestinationsSubtitle,
              style: const TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.storageService.recentDestinations.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border, width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_off_outlined, color: AppTheme.textMuted, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.noCachedDestinations,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Column(
                children: widget.storageService.recentDestinations.map((dest) {
                  final q = dest['query']?.toString() ?? 'Location';
                  final desc = dest['display_name']?.toString() ?? '';
                  final lat = dest['lat'] != null ? (dest['lat'] as num).toDouble().toStringAsFixed(4) : '';
                  final lon = dest['lon'] != null ? (dest['lon'] as num).toDouble().toStringAsFixed(4) : '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: AppTheme.accentCyan, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                q,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  desc,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                              if (lat.isNotEmpty && lon.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'GPS: $lat, $lon',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    color: AppTheme.accentYellow,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              AccessibleButton(
                label: strings.readDestinationsBtn,
                icon: Icons.record_voice_over,
                semanticHint: strings.readDestinationsBtn,
                onPressed: _readCachedDestinations,
              ),
              const SizedBox(height: 10),
              AccessibleButton(
                label: strings.clearCacheBtn,
                icon: Icons.delete_sweep,
                isDestructive: true,
                semanticHint: strings.clearCacheBtn,
                onPressed: _clearDestinationCache,
              ),
            ],

            const Divider(color: AppTheme.border, height: 40, thickness: 1.5),

            // Section 9: Voice Test and Defaults
            AccessibleButton(
              label: strings.testVoiceBtn,
              icon: Icons.volume_up,
              semanticHint: strings.testVoiceBtn,
              onPressed: _testVoice,
            ),
            const SizedBox(height: 14),
            AccessibleButton(
              label: strings.resetDefaultsBtn,
              icon: Icons.restore,
              isDestructive: true,
              semanticHint: strings.resetDefaultsBtn,
              onPressed: _resetDefaults,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
  }
}
