/// Supported application languages.
enum AppLanguage {
  en,
  kn;

  /// TTS locale string accepted by flutter_tts.
  String get ttsLocale => switch (this) {
        AppLanguage.en => 'en-US',
        AppLanguage.kn => 'kn-IN',
      };

  /// STT locale identifier accepted by speech_to_text.
  String get sttLocale => switch (this) {
        AppLanguage.en => 'en_US',
        AppLanguage.kn => 'kn_IN',
      };

  /// Human-readable display name.
  String get displayName => switch (this) {
        AppLanguage.en => 'English',
        AppLanguage.kn => 'ಕನ್ನಡ',
      };

  /// Create an [AppLanguage] from a short code string ('en' or 'kn').
  /// Falls back to [AppLanguage.en] for any unrecognised code.
  static AppLanguage fromCode(String code) =>
      code == 'kn' ? AppLanguage.kn : AppLanguage.en;
}

/// All localised strings for the Blind Navigation app.
///
/// Instantiate with the current [AppLanguage] and access properties directly:
/// ```dart
/// final s = AppStrings(AppLanguage.en);
/// print(s.appTitle);
/// ```
class AppStrings {
  final AppLanguage language;

  const AppStrings(this.language);

  bool get isKannada => language == AppLanguage.kn;

  // ── General ──────────────────────────────────────────────────────────────

  String get appTitle =>
      isKannada ? 'ಸ್ಮಾರ್ಟ್ ನ್ಯಾವಿಗೇಷನ್' : 'Smart Navigation';

  String get safetyBanner => isKannada
      ? 'ಸ್ಮಾರ್ಟ್ ಸಹಾಯಕ ಉಪಯೋಗಿಸುವಾಗ ಯಾವಾಗಲೂ ಸಾಕಷ್ಟು ಎಚ್ಚರಿಕೆ ವಹಿಸಿ. ಸ್ವಾಯತ್ತ ನ್ಯಾವಿಗೇಷನ್ ಅಲ್ಲ.'
      : 'Always remain cautious when using this assistant. This is not autonomous navigation.';

  // ── Home screen ───────────────────────────────────────────────────────────

  String assistantLabel(String name) =>
      isKannada ? 'ಸಹಾಯಕ: $name' : 'Assistant: $name';

  String assistantReady(String name) =>
      isKannada ? '$name ಸಿದ್ಧ.' : '$name is ready.';

  String welcomeGreeting(String name) => isKannada
      ? 'ನಮಸ್ಕಾರ! ನಾನು $name. ಮಾತನಾಡಲು ಪರದೆಯ ಮೇಲೆ ಎಲ್ಲಿಯಾದರೂ ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ, ಅಥವಾ ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ.'
      : 'Hello! I am $name. Double tap anywhere on screen to speak, or tap Start Navigation.';

  String get tapMicOrCommand => isKannada
      ? 'ಮಾತನಾಡಲು ಮೈಕ್ ಟ್ಯಾಪ್ ಮಾಡಿ.'
      : 'Tap the mic button to speak a command.';

  String get micListening =>
      isKannada ? 'ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ...' : 'Listening...';

  String get micTurnedOff =>
      isKannada ? 'ಮೈಕ್ ಆಫ್ ಆಗಿದೆ.' : 'Microphone turned off.';

  String get stoppedListening =>
      isKannada ? 'ನಿಲ್ಲಿಸಲಾಗಿದೆ.' : 'Stopped listening.';

  String heardText(String words) =>
      isKannada ? 'ಕೇಳಿದ್ದು: "$words"' : 'Heard: "$words"';

  String get audioStopped =>
      isKannada ? 'ಆಡಿಯೋ ನಿಲ್ಲಿಸಲಾಗಿದೆ.' : 'Audio stopped.';

  String get startNavigation =>
      isKannada ? 'ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ (ಕ್ಯಾಮೆರಾ)' : 'Start Navigation (Camera)';

  String get startNavigationHint => isKannada
      ? 'ಕ್ಯಾಮೆರಾ ನ್ಯಾವಿಗೇಷನ್ ವ್ಯೂ ತೆರೆಯುತ್ತದೆ.'
      : 'Opens the camera navigation view.';

  String get openingCamera =>
      isKannada ? 'ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ...' : 'Opening camera...';

  String navStarting(String name) => isKannada
      ? '$name: ನ್ಯಾವಿಗೇಷನ್ ಸಹಾಯ ಪ್ರಾರಂಭಿಸುತ್ತಿದ್ದೇನೆ. ಕ್ಯಾಮೆರಾ ಸಿದ್ಧ.'
      : '$name: Starting navigation assistance. The camera is ready.';

  String get navNotActive =>
      isKannada ? 'ನ್ಯಾವಿಗೇಷನ್ ಸಕ್ರಿಯವಾಗಿಲ್ಲ.' : 'Navigation is not currently active.';

  String get repeat => isKannada ? 'ಪುನರಾವರ್ತಿಸಿ' : 'Repeat';

  String get repeatHint =>
      isKannada ? 'ಕೊನೆಯ ಸಂದೇಶ ಮತ್ತೆ ಓದಿ.' : 'Reads the last message again.';

  String get noMessageToRepeat =>
      isKannada ? 'ಪುನರಾವರ್ತಿಸಲು ಯಾವ ಸಂದೇಶ ಇಲ್ಲ.' : 'No message to repeat.';

  String get help => isKannada ? 'ಸಹಾಯ' : 'Help';

  String get helpHint =>
      isKannada ? 'ಲಭ್ಯ ಆಜ್ಞೆಗಳನ್ನು ಓದಿ.' : 'Reads the list of available commands.';

  String helpCommands(String name) => isKannada
      ? '''$name ಕೆಳಗಿನ ಆಜ್ಞೆಗಳನ್ನು ಅರ್ಥ ಮಾಡಿಕೊಳ್ಳುತ್ತದೆ:
ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ.
ನ್ಯಾವಿಗೇಷನ್ ನಿಲ್ಲಿಸಿ.
ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆ.
ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ.
ಪಠ್ಯ ಓದಿ.
ವಸ್ತು ಹುಡುಕಿ — ಉದಾಹರಣೆಗೆ ಕೀ ಹುಡುಕಿ.
ವಸ್ತು ಉಳಿಸಿ — ಉದಾಹರಣೆಗೆ ಕೀ ನೆನಪಿಡಿ.
ಮತ್ತೆ ಹೇಳಿ.
ಸೆಟ್ಟಿಂಗ್ಸ್.
ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸಿ ಅಥವಾ ಇಂಗ್ಲಿಷ್‌ಗೆ ಬದಲಾಯಿಸಿ.
ತುರ್ತು ಸಹಾಯ.'''
      : '''$name understands the following voice commands:
Start navigation.
Stop navigation.
Toggle obstacle alerts.
Describe surroundings.
Read text.
Find — followed by an item name.
Save item — followed by an item name.
Repeat.
Help.
Open settings.
Be quiet.
Switch to Kannada or Switch to English.
Emergency.''';

  String unknownCommand(String rawText) => isKannada
      ? 'ಕ್ಷಮಿಸಿ, "$rawText" ಅರ್ಥ ಆಗಲಿಲ್ಲ. "ಸಹಾಯ" ಎಂದು ಹೇಳಿ ಆಜ್ಞೆಗಳ ಪಟ್ಟಿ ಪಡೆಯಿರಿ.'
      : 'Sorry, I did not understand "$rawText". Say "Help" to hear available commands.';

  // ── Features header & cards ───────────────────────────────────────────────

  String get featuresHeader =>
      isKannada ? 'ವೈಶಿಷ್ಟ್ಯಗಳು' : 'Features';

  String get statusAvailable => isKannada ? 'ಲಭ್ಯ' : 'Available';
  String get statusActive => isKannada ? 'ಸಕ್ರಿಯ' : 'Active';
  String get statusComingSoon => isKannada ? 'ಶೀಘ್ರದಲ್ಲಿ' : 'Coming Soon';

  String get featObjTitle => isKannada ? 'ವಸ್ತು ಪತ್ತೆ' : 'Object Detection';
  String get featObjDesc => isKannada
      ? 'ಕ್ಯಾಮೆರಾ ಮೂಲಕ ಅಡೆತಡೆಗಳು ಮತ್ತು ವಸ್ತುಗಳ ಪತ್ತೆ.'
      : 'Detect obstacles and objects through the camera.';

  String get featSceneTitle => isKannada ? 'ದೃಶ್ಯ ವಿವರಣೆ' : 'Scene Description';
  String get featSceneDesc => isKannada
      ? 'ಒಟ್ಟಾರೆ ಪರಿಸರದ ಶ್ರವ್ಯ ವಿವರಣೆ.'
      : 'Audible description of the overall environment.';

  String get featOcrTitle => isKannada ? 'ಪಠ್ಯ ಓದಿ (OCR)' : 'Read Text (OCR)';
  String get featOcrDesc => isKannada
      ? 'ಫಲಕಗಳು ಮತ್ತು ದಾಖಲೆಗಳ ಮೇಲಿನ ಪಠ್ಯ ಓದಿ.'
      : 'Read text from signs, labels, and documents.';

  String get featCurrencyTitle =>
      isKannada ? 'ಕರೆನ್ಸಿ ಗುರುತಿಸುವಿಕೆ' : 'Currency Recognition';
  String get featCurrencyDesc => isKannada
      ? 'ಕ್ಯಾಮೆರಾ ಬಳಸಿ ನೋಟುಗಳ ಮೌಲ್ಯ ಗುರುತಿಸಿ.'
      : 'Identify banknote values using the camera.';

  String get featLostItemTitle =>
      isKannada ? 'ಕಳೆದ ವಸ್ತು ಹುಡುಕಿ' : 'Find Lost Items';
  String get featLostItemDesc => isKannada
      ? 'ಧ್ವನಿ ಮೂಲಕ ವ್ಯಕ್ತಿಗತ ವಸ್ತುಗಳನ್ನು ಹುಡುಕಿ.'
      : 'Locate personal items using voice queries.';

  String get featEmergencyTitle =>
      isKannada ? 'ತುರ್ತು ಸಹಾಯ' : 'Emergency Assistance';
  String get featEmergencyDesc => isKannada
      ? 'ತಕ್ಷಣ ತುರ್ತು ಸೇವೆಗಳು ಮತ್ತು ಸಹಾಯ.'
      : 'Immediate emergency services and guidance.';

  // ── Settings screen ───────────────────────────────────────────────────────

  String get settingsTitle => isKannada ? 'ಸೆಟ್ಟಿಂಗ್ಸ್' : 'Settings';
  String get backToHome => isKannada ? 'ಮನೆ ಪರದೆಗೆ ಹಿಂದೆ' : 'Back to home screen';
  String get backToHomeHint =>
      isKannada ? 'ಹಿಂದಕ್ಕೆ ಹೋಗಲು ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ' : 'Double tap to go back';

  String get languageSectionTitle => isKannada ? 'ಭಾಷೆ' : 'Language';

  String get assistantNameTitle =>
      isKannada ? 'ಸಹಾಯಕನ ಹೆಸರು' : 'Assistant Name';
  String get currentlySetTo => isKannada ? 'ಪ್ರಸ್ತುತ:' : 'Currently set to:';
  String get customNameLabel =>
      isKannada ? 'ಕಸ್ಟಮ್ ಹೆಸರು' : 'Custom name';
  String get saveNameBtn => isKannada ? 'ಹೆಸರು ಉಳಿಸಿ' : 'Save Name';
  String get choosePreset => isKannada ? 'ಪ್ರಿಸೆಟ್ ಆಯ್ಕೆ ಮಾಡಿ:' : 'Or choose a preset:';

  String get speechSpeedTitle => isKannada ? 'ಮಾತಿನ ವೇಗ' : 'Speech Speed';
  String get slowerBtn => isKannada ? 'ನಿಧಾನ' : 'Slower';
  String get fasterBtn => isKannada ? 'ವೇಗ' : 'Faster';

  String get voicePitchTitle => isKannada ? 'ಧ್ವನಿ ಪಿಚ್' : 'Voice Pitch';

  String get hapticsTitle => isKannada ? 'ಕಂಪನ ಪ್ರತಿಕ್ರಿಯೆ' : 'Haptic Feedback';
  String get hapticsSubtitle => isKannada
      ? 'ಮೈಕ್ ಮತ್ತು ಆಜ್ಞೆಗಳ ಮೇಲೆ ಕಂಪನ.'
      : 'Vibrate on microphone activation and commands.';

  String get emergencyContactTitle => isKannada ? 'ತುರ್ತು ಸಂಪರ್ಕ ಸಂಖ್ಯೆ' : 'Emergency Contact Number';
  String get emergencyContactSubtitle => isKannada
      ? 'ತುರ್ತು ಎಸ್‌ಒಎಸ್ ಸಮಯದಲ್ಲಿ ಹೇಳಲಾಗುವ ಮುಖ್ಯ ಸಂಖ್ಯೆ (ಡೀಫಾಲ್ಟ್: 112).'
      : 'Primary contact announced during SOS alerts (default: 112).';
  String get saveContactBtn => isKannada ? 'ಸಂಪರ್ಕ ಉಳಿಸಿ' : 'Save Contact';

  String get obstacleAlertsDefaultTitle =>
      isKannada ? 'ಡೀಫಾಲ್ಟ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳು' : 'Default Obstacle Alerts';
  String get obstacleAlertsDefaultSubtitle => isKannada
      ? 'ಕ್ಯಾಮೆರಾ ತೆರೆದ ತಕ್ಷಣ ಅಡೆತಡೆಗಳಿಗಾಗಿ ಲೈವ್ ಮಾನಿಟರಿಂಗ್ ಪ್ರಾರಂಭಿಸಿ.'
      : 'Automatically monitor forward path for obstacles upon opening camera navigation.';

  String get savedItemsTitle =>
      isKannada ? 'ಉಳಿಸಿದ ವಸ್ತುಗಳು (ಮೆಮೊರಿ)' : 'Saved Items Memory';
  String get savedItemsSubtitle => isKannada
      ? 'ಸಹಾಯಕನ ಮೆಮೊರಿಯಲ್ಲಿ ನೀವು ಉಳಿಸಿರುವ ವೈಯಕ್ತಿಕ ವಸ್ತುಗಳು.'
      : 'Personal belongings remembered by the assistant.';
  String get noSavedItems => isKannada
      ? 'ಯಾವುದೇ ವಸ್ತುಗಳು ಉಳಿಸಲಾಗಿಲ್ಲ. "ವಸ್ತು ನೆನಪಿಡಿ" ಎಂದು ಹೇಳಿ ಹೊಸ ವಸ್ತುಗಳನ್ನು ಸೇರಿಸಿ.'
      : 'No items saved yet. Say "Lux, save item keys" to remember personal belongings.';
  String get clearAllSavedBtn =>
      isKannada ? 'ಎಲ್ಲ ವಸ್ತುಗಳನ್ನು ಅಳಿಸಿ' : 'Clear All Saved Items';
  String get addItemBtn => isKannada ? 'ವಸ್ತು ಸೇರಿಸಿ' : 'Add Item';
  String get itemNameLabel => isKannada ? 'ವಸ್ತುವಿನ ಹೆಸರು' : 'Item Name';
  String get itemNotesLabel => isKannada ? 'ಟಿಪ್ಪಣಿ (ಐಚ್ಛಿಕ)' : 'Notes (Optional)';

  String get cachedDestinationsTitle =>
      isKannada ? 'ಉಳಿಸಿದ ಸ್ಥಳಗಳು (ಆಫ್‌ಲೈನ್ ಕ್ಯಾಶ್)' : 'Cached Destinations & Offline Places';
  String get cachedDestinationsSubtitle => isKannada
      ? 'ಇಂಟರ್ನೆಟ್ ಇಲ್ಲದೆಯೂ ತಕ್ಷಣ ನ್ಯಾವಿಗೇಟ್ ಮಾಡಲು ಉಳಿಸಿದ ಸ್ಥಳಗಳು.'
      : 'Previously visited places saved for instant offline routing.';
  String get noCachedDestinations => isKannada
      ? 'ಯಾವುದೇ ಸ್ಥಳಗಳ ಕ್ಯಾಶ್ ಉಳಿಸಲಾಗಿಲ್ಲ.'
      : 'No destination cache yet. Searched locations are automatically saved here.';
  String get readDestinationsBtn =>
      isKannada ? 'ಸ್ಥಳಗಳನ್ನು ಗಟ್ಟಿಯಾಗಿ ಓದಿ' : 'Read Saved Places Aloud';
  String get clearCacheBtn =>
      isKannada ? 'ಕ್ಯಾಶ್ ತೆರವುಗೊಳಿಸಿ' : 'Clear Destination Cache';

  String get testVoiceBtn => isKannada ? 'ಧ್ವನಿ ಪರೀಕ್ಷೆ' : 'Test Voice';
  String get resetDefaultsBtn =>
      isKannada ? 'ಡೀಫಾಲ್ಟ್‌ಗೆ ಮರಳಿಸಿ' : 'Reset to Defaults';

  String testVoiceMessage(String name) => isKannada
      ? 'ನಾನು $name. ಧ್ವನಿ ಮತ್ತು ವೇಗ ಪರಿಶೀಲಿಸುತ್ತಿದ್ದೇನೆ. ಎಲ್ಲವೂ ಸರಿಯಾಗಿ ಕೆಲಸ ಮಾಡುತ್ತಿದೆ.'
      : 'I am $name. Testing voice and speed settings. Everything is working correctly.';

  String get resetDefaultsMessage => isKannada
      ? 'ಎಲ್ಲ ಸೆಟ್ಟಿಂಗ್ಸ್ ಡೀಫಾಲ್ಟ್‌ಗೆ ಮರಳಿಸಲಾಗಿದೆ. ಸಹಾಯಕನ ಹೆಸರು Lux.'
      : 'All settings have been reset to defaults. Assistant name is Lux.';

  // ── Language confirmation & warnings ─────────────────────────────────────

  String languageChangedConfirmation(AppLanguage lang) => lang == AppLanguage.kn
      ? 'ಭಾಷೆ ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸಲಾಗಿದೆ.'
      : 'Language changed to English.';

  String get kannadaTtsUnavailableWarning =>
      'Kannada text-to-speech is not installed on this device. '
      'To enable Kannada speech, go to Android Settings, '
      'then Language and Input, then Text-to-Speech, '
      'then install the Google Kannada language pack. '
      'Continuing in English until Kannada TTS is available.';

  // ── Navigation screen ─────────────────────────────────────────────────────

  String get navScreenTitle =>
      isKannada ? 'ನ್ಯಾವಿಗೇಷನ್ ಕ್ಯಾಮೆರಾ' : 'Navigation Camera';

  String get cameraNotAvailable =>
      isKannada ? 'ಕ್ಯಾಮೆರಾ ಲಭ್ಯವಿಲ್ಲ.' : 'Camera is not available.';

  String get cameraPermissionDenied =>
      isKannada ? 'ಕ್ಯಾಮೆರಾ ಅನುಮತಿ ನಿರಾಕರಿಸಲಾಗಿದೆ.' : 'Camera permission denied.';

  String get cameraInitializing =>
      isKannada ? 'ಕ್ಯಾಮೆರಾ ಸಿದ್ಧಗೊಳ್ಳುತ್ತಿದೆ...' : 'Initializing camera...';

  String get cameraReady =>
      isKannada ? 'ಕ್ಯಾಮೆರಾ ಸಿದ್ಧ.' : 'Camera is ready.';

  String get cameraError =>
      isKannada ? 'ಕ್ಯಾಮೆರಾ ದೋಷ.' : 'Camera error.';

  String get stopNavBtn => isKannada ? 'ನಿಲ್ಲಿಸಿ' : 'Stop';

  String get navSafetyCaution => isKannada
      ? 'ಎಚ್ಚರಿಕೆ: ಈ ಅಪ್ಲಿಕೇಶನ್ ಸ್ವಾಯತ್ತ ನ್ಯಾವಿಗೇಷನ್ ಒದಗಿಸುವುದಿಲ್ಲ. ಯಾವಾಗಲೂ ಎಚ್ಚರವಾಗಿರಿ.'
      : 'Caution: This app does not provide autonomous navigation. Always stay alert.';

  // ── Saved Friends strings ────────────────────────────────────────────────
  String get savedFriendsTitle =>
      isKannada ? 'ಉಳಿಸಿದ ಸ್ನೇಹಿತರು & ಮುಖ ಗುರುತಿಸುವಿಕೆ' : 'Saved Friends & Faces';

  String get savedFriendsSubtitle => isKannada
      ? 'ಸ್ನೇಹಿತರು ಹತ್ತಿರ ಬಂದಾಗ ಗುರುತಿಸಲು ಅವರ ಮುಖಗಳನ್ನು ಉಳಿಸಿ.'
      : 'Remember friend faces to get spatial proximity alerts when they approach.';

  String get noSavedFriends => isKannada
      ? 'ಯಾವುದೇ ಸ್ನೇಹಿತರ ಮುಖಗಳನ್ನು ಉಳಿಸಲಾಗಿಲ್ಲ. "ಸ್ನೇಹಿತ [ಹೆಸರು] ಉಳಿಸಿ" ಎಂದು ಹೇಳಿ ಅಥವಾ ಕೆಳಗೆ ಸೇರಿಸಿ.'
      : 'No saved friends yet. Say "Remember this face as [Name]" or tap Add Friend below.';

  String get addFriendBtn => isKannada ? 'ಸ್ನೇಹಿತರನ್ನು ಸೇರಿಸಿ' : 'Add Friend';
  String get friendNameHint => isKannada ? 'ಸ್ನೇಹಿತರ ಹೆಸರು' : 'Friend Name';
}
