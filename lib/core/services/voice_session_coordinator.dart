import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/voice_command.dart';
import '../localization/app_strings.dart';
import 'pedestrian_navigation_service.dart';
import 'speech_service.dart';
import 'storage_service.dart';
import 'tts_service.dart';
import 'voice_command_parser.dart';
import 'gemini_live_service.dart';
import 'uvc_camera_service.dart';
import 'vision_service.dart';

/// Current conversational and visual processing state of Gemini.
enum AssistantState {
  ready,
  listening,
  processing,
  speaking,
}

/// Interface for screens that provide contextual handling for voice commands.
abstract class VoiceCommandDelegate {
  /// Attempt to handle [command]. Returns `true` if handled, `false` to let coordinator handle it.
  bool handleVoiceCommand(VoiceCommand command);

  /// Human-readable screen title for accessible announcements.
  String get screenName;
}

/// Specialized voice delegate interface for visual pedestrian navigation screens.
abstract class NavigationVoiceDelegate extends VoiceCommandDelegate {
  /// Direct vision action handler for active visual navigation screens.
  bool handleVisionAction(String action, [String? arg]);

  /// Direct destination handler for active navigation screens.
  bool handleDestination(String destination);

  /// Direct stop navigation handler for active navigation screens.
  bool handleStopNavigation();

  /// Captures and returns the current camera snapshot as JPEG bytes for Gemini Live multimodal vision.
  Future<Uint8List?> getLatestFrameJpeg() async => null;
}

/// Centralized voice interaction coordinator for the entire application.
///
/// Ensures a single voice session lifecycle, eliminates duplicate command parsing,
/// prevents TTS acoustic feedback loops, and enables voice-first navigation across screens.
class VoiceSessionCoordinator extends ChangeNotifier {
  final StorageService storageService;
  final TtsService ttsService;
  final SpeechService speechService;
  final GlobalKey<NavigatorState> navigatorKey;
  final GeminiLiveService? geminiLiveService;

  VoiceCommandDelegate? _activeDelegate;
  bool _isSessionActive = false;
  bool _isProcessing = false;
  bool _awaitingConversationalReply = false;
  bool _isWakeWordStandby = false;
  int _emptyTimeoutCount = 0;
  int _standbyCycles = 0;
  int _standbyConsecutiveErrors = 0;
  static const int _maxIdleStandbyCycles = 150; // ~10-12 minutes continuous silence without user activity
  static const int _maxConsecutiveStandbyErrors = 10;
  String _lastTranscript = '';
  String _statusText = '';
  DateTime? _lastCommandTime;
  String _lastProcessedText = '';

  VoiceSessionCoordinator({
    required this.storageService,
    required this.ttsService,
    required this.speechService,
    required this.navigatorKey,
    this.geminiLiveService,
  }) {
    _initGeminiLiveTools();

    // When TTS finishes, pause briefly to clear audio echo then resume listening or standby.
    ttsService.onSpeechCompleted = _handleSpeechCompleted;
    ttsService.addListener(notifyListeners);
    speechService.addListener(notifyListeners);

    // Controlled timeout handling with silent standby recovery & battery protection
    speechService.onListeningTimeout = () async {
      debugPrint('[Coordinator] Listening timeout. emptyCount: $_emptyTimeoutCount, awaitingReply: $_awaitingConversationalReply, isWakeWordStandby: $_isWakeWordStandby');
      if (!_isSessionActive) return;

      // Normal silence / timeout during wake-word standby is silent, with battery quota guard:
      if (_isWakeWordStandby) {
        _standbyCycles++;
        if (_standbyCycles >= _maxIdleStandbyCycles) {
          _isWakeWordStandby = false;
          _isSessionActive = false;
          _statusText = strings.isKannada
              ? 'ಬ್ಯಾಟರಿ ಉಳಿಸಲು ಸ್ಟ್ಯಾಂಡ್‌ಬೈ ವಿರಾಮಗೊಂಡಿದೆ. ಮೈಕ್ ಟ್ಯಾಪ್ ಮಾಡಿ.'
              : 'Standby resting to save battery. Tap mic to wake.';
          notifyListeners();
          return;
        }

        Future.delayed(const Duration(milliseconds: 600), () {
          if (_isSessionActive && _isWakeWordStandby && !speechService.isListening && !ttsService.isSpeaking) {
            startWakeWordStandby();
          }
        });
        return;
      }

      if (_emptyTimeoutCount == 0 && _awaitingConversationalReply) {
        _emptyTimeoutCount++;
        _statusText = strings.isKannada
            ? 'ನಾನು ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ, ದಯವಿಟ್ಟು ನಿಮ್ಮ ಆಜ್ಞೆಯನ್ನು ಹೇಳಿ.'
            : 'I am listening. Please speak your command.';
        notifyListeners();
        await ttsService.speak(_statusText);
      } else {
        // Quietly return to wake-word standby without complaining or saying "I cannot understand"
        _emptyTimeoutCount = 0;
        _awaitingConversationalReply = false;
        _statusText = strings.stoppedListening;
        notifyListeners();
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_isSessionActive && !speechService.isListening && !ttsService.isSpeaking) {
            startWakeWordStandby();
          }
        });
      }
    };

    speechService.onErrorOccurred = (errorMsg, category) {
      debugPrint('[Coordinator] STT error occurred: $errorMsg ($category)');
      _emptyTimeoutCount = 0;
      _awaitingConversationalReply = false;
      if (_isSessionActive) {
        if (_isWakeWordStandby) {
          // In standby, retry with exponential backoff up to max errors to protect against quota exhaustion
          if (category != SpeechErrorCategory.permission) {
            _standbyConsecutiveErrors++;
            if (_standbyConsecutiveErrors >= _maxConsecutiveStandbyErrors) {
              _isWakeWordStandby = false;
              _isSessionActive = false;
              _statusText = strings.isKannada
                  ? 'ಧ್ವನಿ ಸೇವೆ ವಿರಾಮದಲ್ಲಿದೆ. ಮಾತನಾಡಲು ಮೈಕ್ ಟ್ಯಾಪ್ ಮಾಡಿ.'
                  : 'Speech service resting. Tap mic to activate.';
              notifyListeners();
              return;
            }

            final delayMs = 600 * _standbyConsecutiveErrors.clamp(1, 4);
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (_isSessionActive && _isWakeWordStandby && !speechService.isListening && !ttsService.isSpeaking) {
                startWakeWordStandby();
              }
            });
            return;
          }
        }
        _isSessionActive = false;
        _statusText = 'Microphone: $errorMsg';
        notifyListeners();
      }
    };
  }

  bool get isSessionActive => _isSessionActive;
  bool get isListening => speechService.isListening;
  bool get isProcessing => _isProcessing;
  bool get isWakeWordStandby => _isWakeWordStandby;
  String get lastTranscript => _lastTranscript;
  String get statusText => _statusText;

  AssistantState get assistantState {
    if (ttsService.isSpeaking) return AssistantState.speaking;
    if (_isProcessing) return AssistantState.processing;
    if (speechService.isListening) {
      return _isWakeWordStandby ? AssistantState.ready : AssistantState.listening;
    }
    return AssistantState.ready;
  }

  AppLanguage get currentLanguage =>
      AppLanguage.fromCode(storageService.appLanguage);

  AppStrings get strings => AppStrings(currentLanguage);

  // ── Screen Delegate Registration ──────────────────────────────────────────

  void registerDelegate(VoiceCommandDelegate delegate) {
    _activeDelegate = delegate;
  }

  void unregisterDelegate(VoiceCommandDelegate delegate) {
    if (_activeDelegate == delegate) {
      _activeDelegate = null;
    }
  }

  // ── Session Control ───────────────────────────────────────────────────────

  /// Starts or toggles listening. Can be triggered from any button or gesture.
  Future<void> toggleListening() async {
    if (speechService.isListening) {
      await stopListening(spokenFeedback: true);
    } else {
      await startListening();
    }
  }

  /// Starts an active voice listening session for commands.
  Future<bool> startListening({
    bool isInteractiveSession = true,
    bool awaitingReply = true,
  }) async {
    _isSessionActive = isInteractiveSession;
    _awaitingConversationalReply = awaitingReply;
    _isWakeWordStandby = false;
    _standbyCycles = 0;
    _standbyConsecutiveErrors = 0;

    // 1. Prevent feedback: stop any ongoing TTS before opening the mic
    await ttsService.stop();

    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();

    _statusText = strings.micListening;
    _lastTranscript = '';
    notifyListeners();

    final lang = currentLanguage;
    final started = await speechService.startListening(
      localeId: lang.sttLocale,
      onResult: (words, isFinal) async {
        _lastTranscript = words;
        _statusText = strings.heardText(words);
        notifyListeners();

        if (isFinal && words.trim().isNotEmpty) {
          _emptyTimeoutCount = 0;
          _awaitingConversationalReply = false;
          // Stop listening immediately before processing command
          await speechService.stopListening();
          await processRecognizedText(words);
        }
      },
    );

    if (!started) {
      _isSessionActive = false;
      _awaitingConversationalReply = false;
      final errorMsg = speechService.lastError ?? 'Unable to activate microphone.';
      _statusText = errorMsg;
      notifyListeners();
      await ttsService.speak('Microphone error: $errorMsg');
      return false;
    }

    return true;
  }

  /// Starts passive listening for the wake word ("Gemini").
  /// Treats silences and timeouts as normal standby without any spoken error announcements.
  Future<bool> startWakeWordStandby() async {
    _isSessionActive = true;
    _awaitingConversationalReply = false;
    _isWakeWordStandby = true;
    _emptyTimeoutCount = 0;

    // Prevent acoustic feedback
    await ttsService.stop();

    _statusText = 'Ready. Say "${storageService.assistantName}" to begin.';
    _lastTranscript = '';
    notifyListeners();

    final lang = currentLanguage;
    final started = await speechService.startListening(
      localeId: lang.sttLocale,
      onResult: (words, isFinal) async {
        _lastTranscript = words;
        _statusText = words;
        notifyListeners();

        final assistantName = storageService.assistantName.toLowerCase().trim();
        final lower = words.toLowerCase().trim();

        // Check if wake word is uttered ("Lux", "Hey Lux", "Gemini", "Hey Gemini", "ಲಕ್ಸ್", "ಜೆಮಿನಿ", and phonetic accents)
        final containsWakeWord = lower.contains(assistantName) ||
            lower.contains('hey $assistantName') ||
            lower.contains('lux') ||
            lower.contains('hey lux') ||
            lower.contains('looks') ||
            lower.contains('hey looks') ||
            lower.contains('luxe') ||
            lower.contains('luck') ||
            lower.contains('locks') ||
            lower.contains('lakhs') ||
            lower.contains('lex') ||
            lower.contains('ಲಕ್ಸ್') ||
            lower.contains('ಹೇ ಲಕ್ಸ್') ||
            lower.contains('ಲಕ್ಷ್') ||
            lower.contains('ಜೆಮಿನಿ') ||
            lower.contains('gemini') ||
            lower.contains('hey gemini');

        if (containsWakeWord) {
          // Check if user spoke a question or command along with the wake word
          final queryContent = lower
              .replaceAll('hey', '')
              .replaceAll('ok', '')
              .replaceAll('okay', '')
              .replaceAll(assistantName, '')
              .replaceAll('lux', '')
              .replaceAll('looks', '')
              .replaceAll('luxe', '')
              .replaceAll('luck', '')
              .replaceAll('locks', '')
              .replaceAll('lakhs', '')
              .replaceAll('lex', '')
              .replaceAll('gemini', '')
              .replaceAll('ಹೇ', '')
              .replaceAll('ಲಕ್ಸ್', '')
              .replaceAll('ಲಕ್ಷ್', '')
              .replaceAll('ಜೆಮಿನಿ', '')
              .replaceAll(RegExp(r'[,.!?]'), '')
              .trim();

          if (queryContent.length > 2) {
            // User uttered a query along with the wake word: process naturally immediately!
            _isWakeWordStandby = false;
            _standbyCycles = 0;
            _standbyConsecutiveErrors = 0;
            await speechService.stopListening();
            await processRecognizedText(words);
          } else if (isFinal) {
            // Wake word alone ("Hey Lux"): prompt user and await their request
            _isWakeWordStandby = false;
            _standbyCycles = 0;
            _standbyConsecutiveErrors = 0;
            await speechService.stopListening();
            _awaitingConversationalReply = true;
            final prompt = strings.isKannada
                ? 'ಹೇಳಿ, ನಾನು ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ.'
                : 'Yes? How can I help?';
            _statusText = prompt;
            notifyListeners();
            await ttsService.speak(prompt);
          }
        } else if (isFinal && words.trim().isNotEmpty) {
          // In standby, if an utterance finishes, process it
          _isWakeWordStandby = false;
          await speechService.stopListening();
          await processRecognizedText(words);
        }
      },
    );

    if (started) {
      _standbyConsecutiveErrors = 0;
    } else {
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (_isSessionActive && _isWakeWordStandby && !speechService.isListening && !ttsService.isSpeaking) {
          startWakeWordStandby();
        }
      });
    }

    return started;
  }

  /// Stops listening cleanly.
  Future<void> stopListening({bool spokenFeedback = false}) async {
    _isSessionActive = false;
    _awaitingConversationalReply = false;
    _isWakeWordStandby = false;
    _emptyTimeoutCount = 0;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    await speechService.stopListening();
    _statusText = strings.micTurnedOff;
    notifyListeners();

    if (spokenFeedback) {
      await ttsService.speak(strings.stoppedListening);
    }
  }

  void _handleSpeechCompleted() {
    debugPrint('[Coordinator] TTS completed. awaitingReply: $_awaitingConversationalReply, sessionActive: $_isSessionActive');

    // Cooldown grace period of 600ms ensures speaker audio has cleared the microphone
    Future.delayed(const Duration(milliseconds: 600), () {
      if (ttsService.isSpeaking) return;
      if (_awaitingConversationalReply && !speechService.isListening) {
        startListening(isInteractiveSession: true, awaitingReply: true);
      } else if (!speechService.isListening) {
        // Return to wake-word standby automatically after responding
        startWakeWordStandby();
      }
    });
  }

  // ── Centralized Command Processing ────────────────────────────────────────

  static const String luxSystemInstruction = GeminiLiveService.defaultSystemInstruction;

  /// Asks Gemini Live a vision-based prompt, automatically capturing and attaching the latest camera frame.
  /// Returns `true` if Gemini Live successfully responded, or `false` to fall back to local offline logic.
  Future<bool> askGeminiWithVision(String prompt) async {
    final assistantName = storageService.assistantName;
    debugPrint('[VoiceCoordinator] useGeminiLive: ${storageService.useGeminiLive}, hasKey: ${storageService.geminiApiKey.isNotEmpty}');

    if (geminiLiveService == null || !storageService.useGeminiLive) {
      debugPrint('[Coordinator] Gemini Live unavailable or disabled for vision query.');
      return false;
    }

    if (storageService.geminiApiKey.isEmpty) {
      const errMsg = 'Gemini Live connection failed, check API key: API key is empty';
      debugPrint('[Coordinator] $errMsg');
      _statusText = errMsg;
      notifyListeners();
      await ttsService.speak('Gemini Live connection failed, check API key');
      return false;
    }

    // If camera is not active yet, route to NavigationScreen first
    if (_navDelegate == null) {
      debugPrint('[Coordinator] askGeminiWithVision called with no active camera. Redirecting to NavigationScreen.');
      final transitionMsg = strings.openingCamera;
      _statusText = transitionMsg;
      notifyListeners();
      await ttsService.speak(transitionMsg);

      final lowerPrompt = prompt.toLowerCase();
      String action = 'describe';
      String? arg;
      if (lowerPrompt.contains('ಹುಡುಕುತ್ತಿದ್ದಾರೆ') || lowerPrompt.contains('looking for their')) {
        action = 'find';
        final m = RegExp(r"['\x22]([^'\x22]+)['\x22]").firstMatch(prompt);
        if (m != null) arg = m.group(1);
      } else if (lowerPrompt.contains('ಕರೆನ್ಸಿ') || lowerPrompt.contains('banknote') || lowerPrompt.contains('coin') || lowerPrompt.contains('currency')) {
        action = 'currency';
      } else if (lowerPrompt.contains('ಪಠ್ಯ') || lowerPrompt.contains('sign') || lowerPrompt.contains('text')) {
        action = 'ocr';
      } else if (lowerPrompt.contains('ಬಸ್') || lowerPrompt.contains('bus')) {
        action = 'bus';
      } else if (lowerPrompt.contains('ಅಡೆತಡೆ') || lowerPrompt.contains('obstacle')) {
        action = 'obstacles';
      } else if (lowerPrompt.contains('ಯಾರು') || lowerPrompt.contains('friend') || lowerPrompt.contains('who is in front')) {
        action = 'whoIsHere';
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': action,
          'visionArg': arg,
        });
      });
      return true;
    }

    _isProcessing = true;
    _statusText = strings.isKannada ? '$assistantName ನೋಡುತ್ತಿದೆ...' : '$assistantName is looking...';
    notifyListeners();

    try {
      // 1. Fetch current camera snapshot frame from navigation delegate if available
      Uint8List? frameBytes;
      if (_navDelegate != null) {
        try {
          frameBytes = await _navDelegate!.getLatestFrameJpeg();
          // Ensure captured JPEG bytes are valid (bytes != null && bytes.length > 5000). If invalid, wait 250ms and retry capture once before dispatching to Gemini.
          if (frameBytes == null || frameBytes.length <= 5000) {
            debugPrint('[Coordinator] Frame bytes invalid (${frameBytes?.length ?? 0} <= 5000). Waiting 250ms and retrying capture.');
            await Future.delayed(const Duration(milliseconds: 250));
            frameBytes = await _navDelegate!.getLatestFrameJpeg();
          }
        } catch (e) {
          debugPrint('[Coordinator] Frame capture error for askGeminiWithVision: $e');
        }
      }

      final rememberedItems = storageService.getRememberedItems();
      String? savedItemsContext;
      if (rememberedItems.isNotEmpty) {
        final itemsList = rememberedItems
            .take(15)
            .map((it) => '${it.itemName} ${it.locationDescription}')
            .join(', ');
        savedItemsContext = 'Known item locations: $itemsList.';
      }

      // 2. Query Gemini Live passing the image and specialized Lux system instruction
      final reply = await geminiLiveService!.converse(
        apiKey: storageService.geminiApiKey,
        userInput: prompt,
        imageBytes: frameBytes,
        customSystemInstruction: luxSystemInstruction,
        savedItemsContext: savedItemsContext,
      );

      if (reply.isNotEmpty && reply != '__FALLBACK_LOCAL__') {
        _statusText = reply;
        notifyListeners();
        _isSessionActive = true;
        _awaitingConversationalReply = true;
        await ttsService.speak(reply);
        return true;
      }

      final reason = geminiLiveService!.lastError ?? 'Model response empty or failed';
      debugPrint('[Coordinator] askGeminiWithVision failed: $reason (reply: $reply)');

      final bool isOffline = reply == '__FALLBACK_LOCAL__' ||
          reason.toLowerCase().contains('offline') ||
          reason.toLowerCase().contains('network') ||
          reason.toLowerCase().contains('socket');

      if (isOffline) {
        final transitionMsg = strings.isKannada
            ? 'ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿದೆ, ಸ್ಥಳೀಯ ಕ್ಯಾಮೆರಾ ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ...'
            : 'Operating offline. Checking with local vision...';
        _statusText = transitionMsg;
        notifyListeners();
        await ttsService.speak(transitionMsg);

        // Fall back to local vision action if prompt matches any vision intent
        final lowerPrompt = prompt.toLowerCase();
        if (lowerPrompt.contains('find') || lowerPrompt.contains('ಹುಡುಕು') || lowerPrompt.contains('looking for')) {
          final m = RegExp(r"['\x22]([^'\x22]+)['\x22]").firstMatch(prompt);
          final item = m != null ? m.group(1) : prompt.split(' ').last;
          if (item != null && item.isNotEmpty) {
            await executeGlobalCommand(VoiceCommand(
              type: VoiceCommandType.findItem,
              argument: item,
              rawText: prompt,
            ));
            return true;
          }
        }
        return false;
      }

      _statusText = 'Gemini Live failed: $reason';
      notifyListeners();
      await ttsService.speak('Gemini Live connection failed, check API key');
      return false;
    } catch (e) {
      debugPrint('[Coordinator] Error in askGeminiWithVision: $e');
      await ttsService.speak('Gemini Live connection failed, check API key');
      return false;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Enrolls a friend's face by capturing the latest frame, saving it to app_flutter/friends,
  /// and persisting the profile into StorageService.
  Future<void> enrollFriend(String rawName) async {
    String name = rawName.trim();
    if (name.isEmpty) name = 'Friend';
    if (name.length > 1) {
      name = name[0].toUpperCase() + name.substring(1);
    }

    _isProcessing = true;
    _statusText = strings.isKannada ? '$name ಅವರ ಮುಖವನ್ನು ಉಳಿಸಲಾಗುತ್ತಿದೆ...' : "Saving $name's face...";
    notifyListeners();

    try {
      Uint8List? frameBytes;
      if (_navDelegate != null) {
        try {
          frameBytes = await _navDelegate!.getLatestFrameJpeg();
        } catch (e) {
          debugPrint('[Coordinator] Frame capture error for enrollFriend: $e');
        }
      }

      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${safeName}_$timestamp.jpg';

      Directory friendsDir;
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          friendsDir = Directory('/data/user/0/com.example.blind_navigation/app_flutter/friends');
          if (!friendsDir.existsSync()) {
            friendsDir = Directory('${Directory.systemTemp.path}/app_flutter/friends');
          }
        } else {
          friendsDir = Directory('${Directory.systemTemp.path}/app_flutter/friends');
        }
        if (!friendsDir.existsSync()) {
          friendsDir.createSync(recursive: true);
        }
      } catch (_) {
        friendsDir = Directory('${Directory.systemTemp.path}/app_flutter/friends');
        if (!friendsDir.existsSync()) friendsDir.createSync(recursive: true);
      }

      final savedFile = File('${friendsDir.path}/$fileName');
      try {
        if (frameBytes != null && frameBytes.isNotEmpty) {
          await savedFile.writeAsBytes(frameBytes);
        } else {
          await savedFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
        }
      } catch (e) {
        debugPrint('[Coordinator] Failed writing friend image: $e');
      }

      final profile = FriendProfile(
        id: 'friend_$timestamp',
        name: name,
        imagePath: savedFile.path,
        enrolledAt: DateTime.now(),
      );

      await storageService.saveFriend(profile);

      final confirmation = strings.isKannada
          ? 'ನಾನು $name ಅವರ ಮುಖವನ್ನು ಉಳಿಸಿದ್ದೇನೆ. ಅವರು ಹತ್ತಿರ ಬಂದಾಗ ನಾನು ನಿಮಗೆ ತಿಳಿಸುತ್ತೇನೆ.'
          : "I've saved $name's face. I'll let you know whenever they come near.";

      _statusText = confirmation;
      notifyListeners();
      await ttsService.speak(confirmation);
    } catch (e) {
      debugPrint('[Coordinator] enrollFriend error: $e');
      await ttsService.speak("Could not save friend's face: $e");
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Public alias for processing voice input strings directly.
  Future<void> processVoiceInput(String rawText) => processRecognizedText(rawText);

  /// Normalizes, parses, and executes any voice input.
  /// Prevents concurrent execution and debounces identical commands within 1500ms.
  Future<void> processRecognizedText(String rawText) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    if (_isProcessing) {
      debugPrint('[Coordinator] Already processing a command. Skipping concurrent: "$trimmed"');
      return;
    }
    if (_lastCommandTime != null &&
        now.difference(_lastCommandTime!).inMilliseconds < 1500 &&
        _lastProcessedText.toLowerCase() == trimmed.toLowerCase()) {
      debugPrint('[Coordinator] Debouncing identical repeated command within 1500ms: "$trimmed"');
      return;
    }

    _lastCommandTime = now;
    _lastProcessedText = trimmed;
    _isProcessing = true;
    _emptyTimeoutCount = 0;
    _awaitingConversationalReply = false;
    notifyListeners();

    try {
      final assistantName = storageService.assistantName;
      debugPrint('[VoiceCoordinator] Received utterance: "$trimmed"');

      // 1. Immediate local silence / emergency shortcuts (0ms latency for safety)
      final lowerTrimmed = trimmed.toLowerCase();
      if (lowerTrimmed == 'stop' ||
          lowerTrimmed == 'stop speaking' ||
          lowerTrimmed == 'quiet' ||
          lowerTrimmed == 'silence' ||
          lowerTrimmed == 'ನಿಲ್ಲಿಸು' ||
          lowerTrimmed == 'ಸುಮ್ಮನಿರು') {
        await ttsService.stop();
        _statusText = strings.audioStopped;
        notifyListeners();
        return;
      }

      if (lowerTrimmed == 'emergency' ||
          lowerTrimmed == 'sos' ||
          lowerTrimmed == 'help' ||
          lowerTrimmed == 'ತುರ್ತು' ||
          lowerTrimmed == 'ಸಹಾಯ') {
        final command = VoiceCommand(type: VoiceCommandType.emergency, rawText: trimmed);
        if (_activeDelegate != null && _activeDelegate!.handleVoiceCommand(command)) {
          return;
        }
        await executeGlobalCommand(command);
        return;
      }

      // Conversational farewell check
      if (lowerTrimmed == 'goodbye' ||
          lowerTrimmed == 'bye' ||
          lowerTrimmed == 'bye lux' ||
          lowerTrimmed == 'goodbye lux' ||
          lowerTrimmed == 'bye gemini' ||
          lowerTrimmed == 'goodbye gemini' ||
          lowerTrimmed == 'that is all' ||
          lowerTrimmed == "that's all" ||
          lowerTrimmed == 'ಧನ್ಯವಾದಗಳು' ||
          lowerTrimmed == 'ಬೈ') {
        _awaitingConversationalReply = false;
        final farewell = strings.isKannada
            ? 'ಸರಿ, ಅಗತ್ಯವಿದ್ದಾಗ "ಹೇ $assistantName" ಎಂದು ಕರೆಯಿರಿ.'
            : 'Goodbye! Say "Hey $assistantName" whenever you need me.';
        _statusText = farewell;
        notifyListeners();
        await ttsService.speak(farewell);
        return;
      }

      // 2. PRIMARY AGENTIC ROUTING: Gemini Live Multimodal AI & Action Dispatcher
      // Eliminate hardcoded regex command parsing as the gatekeeper for user requests.
      // Every natural voice query goes directly to Gemini.
      debugPrint('[VoiceCoordinator] useGeminiLive: ${storageService.useGeminiLive}, hasKey: ${storageService.geminiApiKey.isNotEmpty}');

      if (geminiLiveService != null && storageService.useGeminiLive && storageService.geminiApiKey.isNotEmpty) {
        // Query latest camera snapshot frame if navigation view is active
        Uint8List? currentCameraSnapshot;
        if (_navDelegate != null) {
          try {
            currentCameraSnapshot = await _navDelegate!.getLatestFrameJpeg();
          } catch (e) {
            debugPrint('[Coordinator] Frame capture error: $e');
          }
        }

        _statusText = strings.isKannada ? '$assistantName ಯೋಚಿಸುತ್ತಿದೆ...' : '$assistantName is thinking...';
        notifyListeners();

        final rememberedItems = storageService.getRememberedItems();
        String? savedItemsContext;
        if (rememberedItems.isNotEmpty) {
          final itemsList = rememberedItems
              .take(15)
              .map((it) => '${it.itemName} ${it.locationDescription}')
              .join(', ');
          savedItemsContext = 'Known item locations: $itemsList.';
        }

        final rawResponse = await geminiLiveService!.converse(
          apiKey: storageService.geminiApiKey,
          userInput: trimmed,
          imageBytes: currentCameraSnapshot,
          customSystemInstruction: luxSystemInstruction,
          savedItemsContext: savedItemsContext,
        );

        if (rawResponse.isNotEmpty && rawResponse != '__FALLBACK_LOCAL__') {
          // Inspect Gemini's response for action tags
          final actionRegex = RegExp(r'\[ACTION:\s*([^\]]+)\]', caseSensitive: false);
          final match = actionRegex.firstMatch(rawResponse);

          if (match != null) {
            final tagContent = match.group(1)!.trim();
            final upperTag = tagContent.toUpperCase();
            debugPrint('[Coordinator] Gemini Action Tag: $tagContent');

            // Remove the [ACTION:...] tag from the response text so TTS only speaks spoken acknowledgment
            String acknowledgment = rawResponse.replaceAll(actionRegex, '').trim();

            if (upperTag.startsWith('OPEN_CAMERA')) {
              // Extract the action (describe, find, currency, ocr, bus, whoIsHere, enroll) and optional argument (e.g. powerbank)
              final parts = tagContent.split(':');
              String action = parts.length > 1 ? parts[1].trim() : 'describe';
              String? arg = parts.length > 2 ? parts.sublist(2).join(':').trim() : null;

              if (acknowledgment.isEmpty) {
                acknowledgment = strings.openingCamera;
              }

              _statusText = acknowledgment;
              notifyListeners();
              await ttsService.speak(acknowledgment);

              // Using appNavigatorKey (ensuring safe execution via post-frame when frame in progress),
              // push /navigation with route arguments:{'visionAction': action, 'visionArg': arg}
              _safePostFrame(() {
                if (_navDelegate != null) {
                  _navDelegate!.handleVisionAction(action, arg);
                } else {
                  final mappedAction = (action.toLowerCase() == 'enroll' || action.toLowerCase() == 'enrollfriend')
                      ? 'enrollFriend'
                      : (action.toLowerCase() == 'whoishere' || action.toLowerCase() == 'who_is_here'
                          ? 'whoIsHere'
                          : action);

                  navigatorKey.currentState?.pushNamed(
                    '/navigation',
                    arguments: {
                      'visionAction': mappedAction,
                      if (arg != null && arg.isNotEmpty) 'visionArg': arg,
                      if (mappedAction == 'ocr') 'ocrMode': 'smart',
                    },
                  );
                }
              });
              return;
            } else if (upperTag == 'START_NAVIGATION') {
              if (acknowledgment.isEmpty) {
                acknowledgment = strings.navStarting(assistantName);
              }
              _statusText = acknowledgment;
              notifyListeners();
              await ttsService.speak(acknowledgment);

              _safePostFrame(() {
                if (_navDelegate != null) {
                  _navDelegate!.handleVoiceCommand(VoiceCommand(
                    type: VoiceCommandType.startNavigation,
                    rawText: trimmed,
                  ));
                } else {
                  navigatorKey.currentState?.pushNamed('/navigation');
                }
              });
              return;
            } else if (upperTag == 'TOGGLE_TORCH') {
              if (acknowledgment.isEmpty) {
                acknowledgment = 'Flashlight toggled.';
              }
              _statusText = acknowledgment;
              notifyListeners();
              await ttsService.speak(acknowledgment);

              _safePostFrame(() {
                if (_navDelegate != null) {
                  _navDelegate!.handleVisionAction('torch');
                } else {
                  navigatorKey.currentState?.pushNamed(
                    '/navigation',
                    arguments: {'visionAction': 'torch'},
                  );
                }
              });
              return;
            } else if (upperTag.startsWith('REMEMBER_ITEM')) {
              // Extract item and location: [ACTION:REMEMBER_ITEM:<item>:<location>]
              final colonIdx = tagContent.indexOf(':');
              final rest = colonIdx != -1 ? tagContent.substring(colonIdx + 1).trim() : '';
              final parts = rest.split(':');
              final item = parts.isNotEmpty ? parts[0].trim() : 'item';
              final location = parts.length > 1 ? parts.sublist(1).join(':').trim() : 'saved location';

              await storageService.saveRememberedItem(item, location);

              final confirmation = strings.isKannada
                  ? 'ನಿಮ್ಮ $item $location ಇದೆ ಎಂದು ನಾನು ನೆನಪಿಟ್ಟುಕೊಳ್ಳುತ್ತೇನೆ.'
                  : 'I will remember that your $item is $location.';

              _statusText = confirmation;
              notifyListeners();
              await ttsService.speak(confirmation);
              return;
            } else if (upperTag.startsWith('RECALL_ITEM')) {
              // Extract item: [ACTION:RECALL_ITEM:<item>]
              final colonIdx = tagContent.indexOf(':');
              final item = colonIdx != -1 ? tagContent.substring(colonIdx + 1).trim() : 'item';

              // 1. Instant Dual-Check: First check live in-memory camera frame with clock direction
              Uint8List? liveFrame;
              if (_navDelegate != null) {
                liveFrame = await _navDelegate!.getLatestFrameJpeg();
              } else if (UvcCameraService().isUvcConnected) {
                liveFrame = await UvcCameraService().getLatestFrame();
              }

              if (liveFrame != null && liveFrame.isNotEmpty) {
                final liveVisionResult = await VisionService().searchForObjectFromBytes(
                  liveFrame,
                  item,
                  isKannada: strings.isKannada,
                );
                if (liveVisionResult != null && liveVisionResult.isNotEmpty) {
                  final response = strings.isKannada
                      ? 'ಕಂಡುಬಂದಿದೆ: $liveVisionResult'
                      : 'I see your $item right now, $liveVisionResult';
                  _statusText = response;
                  notifyListeners();
                  await ttsService.speak(response);
                  return;
                }
              }

              // 2. Memory Fallback: If not visible in current view, fall back to stored RememberedItem
              final remembered = storageService.findRememberedItem(item);
              if (remembered != null) {
                final response = liveFrame != null
                    ? (strings.isKannada
                        ? 'ಪ್ರಸ್ತುತ ವೀಕ್ಷಣೆಯಲ್ಲಿ ಕಂಡುಬಂದಿಲ್ಲ. ನೀವು ಕೊನೆಯದಾಗಿ ಉಳಿಸಿದ್ದು: ನಿಮ್ಮ ${remembered.itemName} ${remembered.locationDescription} ಇದೆ.'
                        : 'Not visible in your current view. You last remembered that your ${remembered.itemName} is ${remembered.locationDescription}.')
                    : (strings.isKannada
                        ? 'ನೀವು ನಿಮ್ಮ ${remembered.itemName} ${remembered.locationDescription} ಇದೆ ಎಂದು ಉಳಿಸಿದ್ದೀರಿ. ಅದನ್ನು ಹುಡುಕಲು ನಾನು ಕ್ಯಾಮೆರಾವನ್ನು ತೆರೆಯಬೇಕೇ?'
                        : 'You saved that your ${remembered.itemName} is ${remembered.locationDescription}. Would you like me to open the camera to look for it?');

                _statusText = response;
                notifyListeners();
                await ttsService.speak(response);
                return;
              } else {
                // If not found in storage: Trigger visual camera search directly: [ACTION:OPEN_CAMERA:find:<item>]
                final transitionMsg = strings.isKannada
                    ? 'ನಿಮ್ಮ $item ಎಲ್ಲಿ ಇರಿಸಲಾಗಿದೆ ಎಂಬ ದಾಖಲೆ ಇಲ್ಲ. ಅದನ್ನು ಹುಡುಕಲು ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ...'
                    : "I don't have a saved record of where you kept your $item. Opening camera to look for it...";

                _statusText = transitionMsg;
                notifyListeners();
                await ttsService.speak(transitionMsg);

                _safePostFrame(() {
                  if (_navDelegate != null) {
                    _navDelegate!.handleVisionAction('find', item);
                  } else {
                    navigatorKey.currentState?.pushNamed(
                      '/navigation',
                      arguments: {
                        'visionAction': 'find',
                        'visionArg': item,
                      },
                    );
                  }
                });
                return;
              }
            }
          }

          // If no action tag is present:
          // Directly speak Gemini's natural conversational response via ttsService.speak()
          _statusText = rawResponse;
          notifyListeners();
          _isSessionActive = true;
          _awaitingConversationalReply = true;
          await ttsService.speak(rawResponse);
          return;
        }

        final reason = geminiLiveService!.lastError ?? 'Model response empty';
        debugPrint('[VoiceCoordinator] Gemini Live failed ($reason), executing offline fallback.');
      }

      // 3. OFFLINE / LOCAL FALLBACK (When Gemini Live is disabled, missing key, or returned fallback)
      final command = VoiceCommandParser.parse(trimmed, assistantName);
      debugPrint('[Coordinator] Offline Fallback parsed command: ${command.type}');

      // Vision inquiry offline camera transition
      if (_navDelegate == null && _isVisionIntent(command, trimmed)) {
        final transitionMsg = strings.openingCamera;
        _statusText = transitionMsg;
        notifyListeners();
        await ttsService.speak(transitionMsg);
        final actionMap = _resolveVisionAction(command, trimmed);
        navigatorKey.currentState?.pushNamed(
          '/navigation',
          arguments: {
            'visionAction': actionMap['action'],
            'visionArg': actionMap['arg'],
            'ocrMode': actionMap['ocrMode'],
          },
        );
        return;
      }

      if (_activeDelegate != null && _activeDelegate!.handleVoiceCommand(command)) {
        return;
      }
      await executeGlobalCommand(command);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void _safePostFrame(VoidCallback callback) {
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      callback();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
  }

  /// Checks whether an utterance or command is a visual inquiry requiring camera feed.
  bool _isVisionIntent(VoiceCommand command, String rawText) {
    switch (command.type) {
      case VoiceCommandType.findItem:
      case VoiceCommandType.recognizeCurrency:
      case VoiceCommandType.readText:
      case VoiceCommandType.readBusRoute:
      case VoiceCommandType.describeSurroundings:
      case VoiceCommandType.detectObjects:
      case VoiceCommandType.whoIsHere:
      case VoiceCommandType.enrollFriend:
      case VoiceCommandType.checkTrafficLight:
        return true;
      default:
        break;
    }

    final lower = rawText.toLowerCase().trim();

    // Check conversational vision phrases in English
    final visionKeywords = [
      'find my', 'where is my', "where's my", 'look for my', 'search for my',
      'what note', 'which note', 'what currency', 'scan money', 'check money',
      'how much money', 'count money', 'scan note', 'rupee note',
      'read text', 'read sign', 'read this', 'what does this say', 'what is written',
      "what's written", 'read document', 'read board', 'read label',
      'what bus', 'which bus', 'check bus', 'bus arriving', 'bus is arriving', 'bus coming',
      'what is in front of me', "what's in front of me", 'what is in front', "what's in front",
      'what do you see', 'describe view', 'describe surroundings', 'look around',
      'what am i looking at', 'look in front', 'what can you see', 'what is around me',
      'any obstacle', 'any obstacles', 'check path', 'is path clear', 'obstacles ahead',
      'who is in front of me', "who's in front of me", 'who is in front', "who's in front",
      'who is that', 'who is here', "who's here", 'who is this person', 'who is standing',
      'remember this face as', 'remember this face', 'remember face as', 'remember face',
      'save face as', 'save face', 'enroll friend', 'save friend',
      'traffic light', 'traffic signal', 'signal color', 'what color light',
    ];

    for (final kw in visionKeywords) {
      if (lower.contains(kw)) return true;
    }

    // Check conversational vision phrases in Kannada
    final kannadaKeywords = [
      'ಹುಡುಕು', 'ಹುಡುಕಿ', 'ಎಲ್ಲಿದೆ ನನ್ನ', 'ಎಲ್ಲಿದೆ',
      'ನೋಟು', 'ಹಣ', 'ಕರೆನ್ಸಿ',
      'ಪಠ್ಯ', 'ಓದು', 'ಓದಿ', 'ಏನು ಬರೆದಿದೆ',
      'ಬಸ್', 'ಯಾವ ಬಸ್',
      'ಮುಂದೆ ಏನಿದೆ', 'ಏನು ಕಾಣಿಸುತ್ತಿದೆ', 'ವಿವರಿಸು', 'ನೋಡು', 'ನೋಡಿ',
      'ಅಡೆತಡೆ', 'ದಾರಿ ಸ್ಪಷ್ಟವಾಗಿದೆಯೇ',
      'ಯಾರು ಇದ್ದಾರೆ', 'ಯಾರು ಇದು', 'ಯಾರು ಮುಂದೆ',
      'ಮುಖ ನೆನಪಿಡು', 'ಮುಖ ಉಳಿಸು',
      'ಸಿಗ್ನಲ್', 'ಟ್ರಾಫಿಕ್ ಲೈಟ್',
    ];

    for (final kw in kannadaKeywords) {
      if (lower.contains(kw)) return true;
    }

    return false;
  }

  /// Maps a vision-dependent command/query to its corresponding navigation route arguments.
  Map<String, dynamic> _resolveVisionAction(VoiceCommand command, String rawText) {
    final lower = rawText.toLowerCase().trim();

    // 1. Find Item
    if (command.type == VoiceCommandType.findItem ||
        lower.contains('find my') ||
        lower.contains('where is my') ||
        lower.contains("where's my") ||
        lower.contains('look for my') ||
        lower.contains('search for my') ||
        lower.contains('ಹುಡುಕು') ||
        lower.contains('ಹುಡುಕಿ') ||
        lower.contains('ಎಲ್ಲಿದೆ ನನ್ನ')) {
      String item = command.argument ?? '';
      if (item.isEmpty) {
        final findRegex = RegExp(r"(?:find my|where is my|where\'s my|look for my|search for my)\s+([^?.!]+)", caseSensitive: false);
        final match = findRegex.firstMatch(rawText);
        if (match != null) {
          item = match.group(1)?.trim() ?? '';
        } else if (lower.contains('ಎಲ್ಲಿದೆ ನನ್ನ')) {
          item = rawText.replaceAll('ಎಲ್ಲಿದೆ ನನ್ನ', '').replaceAll('?', '').trim();
        } else if (lower.contains('ನನ್ನ') && (lower.contains('ಹುಡುಕು') || lower.contains('ಹುಡುಕಿ'))) {
          item = rawText.replaceAll('ನನ್ನ', '').replaceAll('ಹುಡುಕು', '').replaceAll('ಹುಡುಕಿ', '').replaceAll('?', '').trim();
        }
      }
      if (item.toLowerCase().startsWith('my ')) item = item.substring(3).trim();
      if (item.startsWith('ನನ್ನ ')) item = item.substring(5).trim();
      if (item.isEmpty) item = 'item';
      return {'action': 'find', 'arg': item};
    }

    // 2. Enroll Friend
    if (command.type == VoiceCommandType.enrollFriend ||
        lower.contains('remember this face as') ||
        lower.contains('remember face as') ||
        lower.contains('save face as') ||
        lower.contains('ಮುಖ ನೆನಪಿಡು') ||
        lower.contains('ಮುಖ ಉಳಿಸು')) {
      String name = command.argument ?? '';
      if (name.isEmpty) {
        final nameRegex = RegExp(r'(?:remember this face as|remember face as|save face as)\s+([A-Za-z0-9_\s]+)', caseSensitive: false);
        final match = nameRegex.firstMatch(rawText);
        if (match != null) {
          name = match.group(1)?.trim() ?? '';
        }
      }
      if (name.isEmpty) name = 'Friend';
      if (name.length > 1) {
        name = name[0].toUpperCase() + name.substring(1);
      }
      return {'action': 'enrollFriend', 'arg': name};
    }

    // 3. Currency
    if (command.type == VoiceCommandType.recognizeCurrency ||
        lower.contains('what note') ||
        lower.contains('which note') ||
        lower.contains('what currency') ||
        lower.contains('scan money') ||
        lower.contains('check money') ||
        lower.contains('count money') ||
        lower.contains('scan note') ||
        lower.contains('how much money') ||
        lower.contains('rupee note') ||
        lower.contains('ನೋಟು') ||
        lower.contains('ಹಣ') ||
        lower.contains('ಕರೆನ್ಸಿ')) {
      return {'action': 'currency'};
    }

    // 4. Text Reading (OCR)
    if (command.type == VoiceCommandType.readText ||
        lower.contains('read text') ||
        lower.contains('read sign') ||
        lower.contains('read this') ||
        lower.contains('what does this say') ||
        lower.contains('what is written') ||
        lower.contains("what's written") ||
        lower.contains('read document') ||
        lower.contains('read board') ||
        lower.contains('read label') ||
        lower.contains('ಪಠ್ಯ') ||
        lower.contains('ಓದು') ||
        lower.contains('ಓದಿ') ||
        lower.contains('ಏನು ಬರೆದಿದೆ')) {
      final ocrMode = command.argument ?? 'smart';
      return {'action': 'ocr', 'ocrMode': ocrMode};
    }

    // 5. Bus Route
    if (command.type == VoiceCommandType.readBusRoute ||
        lower.contains('what bus') ||
        lower.contains('which bus') ||
        lower.contains('check bus') ||
        lower.contains('bus arriving') ||
        lower.contains('bus is arriving') ||
        lower.contains('bus coming') ||
        lower.contains('bus route') ||
        lower.contains('bus number') ||
        lower.contains('ಯಾವ ಬಸ್') ||
        lower.contains('ಬಸ್')) {
      return {'action': 'bus'};
    }

    // 6. Who is Here
    if (command.type == VoiceCommandType.whoIsHere ||
        lower.contains('who is in front of me') ||
        lower.contains("who's in front of me") ||
        lower.contains('who is in front') ||
        lower.contains("who's in front") ||
        lower.contains('who is that') ||
        lower.contains('who is here') ||
        lower.contains("who's here") ||
        lower.contains('who is this person') ||
        lower.contains('who is standing') ||
        lower.contains('recognize face') ||
        lower.contains('ಯಾರು ಇದ್ದಾರೆ') ||
        lower.contains('ಯಾರು ಮುಂದೆ') ||
        lower.contains('ಯಾರು ಇದು')) {
      return {'action': 'whoIsHere'};
    }

    // 7. Obstacles
    if (command.type == VoiceCommandType.detectObjects ||
        lower.contains('any obstacle') ||
        lower.contains('any obstacles') ||
        lower.contains('check path') ||
        lower.contains('is path clear') ||
        lower.contains('obstacles ahead') ||
        lower.contains('check obstacles') ||
        lower.contains('detect obstacles') ||
        lower.contains('ಅಡೆತಡೆ') ||
        lower.contains('ದಾರಿ ಸ್ಪಷ್ಟವಾಗಿದೆಯೇ')) {
      return {'action': 'obstacles'};
    }

    // 8. Traffic Light
    if (command.type == VoiceCommandType.checkTrafficLight ||
        lower.contains('traffic light') ||
        lower.contains('traffic signal') ||
        lower.contains('signal color') ||
        lower.contains('light color') ||
        lower.contains('ಸಿಗ್ನಲ್') ||
        lower.contains('ಟ್ರಾಫಿಕ್ ಲೈಟ್')) {
      return {'action': 'trafficLight'};
    }

    // 9. Describe Surroundings (Default for any general visual inquiry)
    return {'action': 'describe'};
  }

  Future<void> executeCommand(VoiceCommand command) async {
    if (_activeDelegate != null && _activeDelegate!.handleVoiceCommand(command)) {
      return;
    }
    await executeGlobalCommand(command);
  }

  Future<void> executeGlobalCommand(VoiceCommand command) async {
    switch (command.type) {
      case VoiceCommandType.startListening:
        _isSessionActive = true;
        _awaitingConversationalReply = true;
        await ttsService.speak('Listening. What can I do for you?');
        break;

      case VoiceCommandType.stopListening:
        await stopListening(spokenFeedback: true);
        break;

      case VoiceCommandType.stopSpeaking:
        await ttsService.stop();
        _statusText = strings.audioStopped;
        notifyListeners();
        break;

      case VoiceCommandType.repeat:
        await ttsService.repeat(emptyMessage: strings.noMessageToRepeat);
        break;

      case VoiceCommandType.help:
        final name = storageService.assistantName;
        await ttsService.speak(strings.helpCommands(name));
        break;

      case VoiceCommandType.openSettings:
        await ttsService.speak('Opening settings.');
        navigatorKey.currentState?.pushNamed('/settings');
        break;

      case VoiceCommandType.goBack:
        if (navigatorKey.currentState?.canPop() == true) {
          await ttsService.speak('Going back.');
          navigatorKey.currentState?.pop();
        } else {
          await ttsService.speak('Already at home screen.');
        }
        break;

      case VoiceCommandType.startNavigation:
        await ttsService.speak(strings.navStarting(storageService.assistantName));
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'promptDestination': true});
        break;

      case VoiceCommandType.stopNavigation:
        if (navigatorKey.currentState?.canPop() == true) {
          await ttsService.speak('Navigation stopped. Returning to home.');
          navigatorKey.currentState?.pop();
        } else {
          await ttsService.speak(strings.navNotActive);
        }
        break;

      case VoiceCommandType.takeMeTo:
        final destination = command.argument ?? 'destination';
        await ttsService.speak('Setting route to $destination. Opening navigation.');
        navigatorKey.currentState?.pushNamed('/navigation', arguments: destination);
        break;

      case VoiceCommandType.whereAmI:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        try {
          await nav.announceCurrentLocation();
        } finally {
          nav.dispose();
        }
        break;

      case VoiceCommandType.describeSurroundings:
        await ttsService.speak(
          strings.isKannada
              ? 'ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆಗಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Looking around.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'describe'});
        break;

      case VoiceCommandType.detectObjects:
        await ttsService.speak(
          strings.isKannada
              ? 'ವಸ್ತು ಪತ್ತೆಗಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Checking for obstacles.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'detect'});
        break;

      case VoiceCommandType.readText:
        final ocrMode = command.argument ?? 'smart';
        await ttsService.speak(
          strings.isKannada
              ? 'ಪಠ್ಯವನ್ನು ಓದಲಾಗುತ್ತಿದೆ.'
              : (ocrMode == 'all' ? 'Reading all text in view.' : 'Reading text in view.'),
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'ocr',
          'ocrMode': ocrMode,
        });
        break;

      case VoiceCommandType.recognizeCurrency:
        await ttsService.speak(
          strings.isKannada
              ? 'ಕರೆನ್ಸಿ ಪರಿಶೀಲಿಸಲಾಗುತ್ತಿದೆ.'
              : 'Checking currency.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'currency'});
        break;

      case VoiceCommandType.readBusRoute:
        await ttsService.speak(
          strings.isKannada
              ? 'ಬಸ್ ಸಂಖ್ಯೆ ಪರಿಶೀಲಿಸಲು ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Checking approaching bus route number.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'bus'});
        break;

      case VoiceCommandType.saveItem:
        final raw = command.argument ?? 'item';
        String itemName = raw;
        String locationDesc = '';
        final locationRegex = RegExp(r'\b(in|on|at|under|near|beside|by|inside)\b', caseSensitive: false);
        final locMatch = locationRegex.firstMatch(raw);
        if (locMatch != null && locMatch.start > 0) {
          itemName = raw.substring(0, locMatch.start).trim();
          locationDesc = raw.substring(locMatch.start).trim();
          if (itemName.toLowerCase().startsWith('my ')) itemName = itemName.substring(3).trim();
          if (itemName.toLowerCase().startsWith('where i kept ')) itemName = itemName.substring(13).trim();
          if (itemName.toLowerCase().startsWith('i kept ')) itemName = itemName.substring(7).trim();
          if (itemName.toLowerCase().startsWith('where i put ')) itemName = itemName.substring(12).trim();
          if (itemName.toLowerCase().startsWith('i put ')) itemName = itemName.substring(6).trim();
        }

        if (locationDesc.isNotEmpty) {
          await storageService.saveRememberedItem(itemName, locationDesc);
          final confirmation = strings.isKannada
              ? 'ನಿಮ್ಮ $itemName $locationDesc ಇದೆ ಎಂದು ನಾನು ನೆನಪಿಟ್ಟುಕೊಳ್ಳುತ್ತೇನೆ.'
              : 'I will remember that your $itemName is $locationDesc.';
          _statusText = confirmation;
          notifyListeners();
          await ttsService.speak(confirmation);
        } else {
          await storageService.addSavedItem(
            raw,
            notes: 'Saved on ${DateTime.now().toString().split('.')[0]}',
          );
          await ttsService.speak(
            strings.isKannada
                ? '$raw ವಸ್ತುವನ್ನು ಯಶಸ್ವಿಯಾಗಿ ಉಳಿಸಲಾಗಿದೆ.'
                : 'Registered "$raw" in your saved items list.',
          );
        }
        break;

      case VoiceCommandType.findItem:
        final rawItem = command.argument ?? 'item';
        String item = rawItem;
        if (item.toLowerCase().startsWith('my ')) item = item.substring(3).trim();
        if (item.startsWith('ನನ್ನ ')) item = item.substring(5).trim();

        // 1. Instant Dual-Check: First check live in-memory camera frame
        Uint8List? liveFrame;
        if (_navDelegate != null) {
          liveFrame = await _navDelegate!.getLatestFrameJpeg();
        } else if (UvcCameraService().isUvcConnected) {
          liveFrame = await UvcCameraService().getLatestFrame();
        }

        if (liveFrame != null && liveFrame.isNotEmpty) {
          final liveVisionResult = await VisionService().searchForObjectFromBytes(
            liveFrame,
            item,
            isKannada: strings.isKannada,
          );
          if (liveVisionResult != null && liveVisionResult.isNotEmpty) {
            final response = strings.isKannada
                ? 'ಕಂಡುಬಂದಿದೆ: $liveVisionResult'
                : 'I see your $item right now, $liveVisionResult';
            _statusText = response;
            notifyListeners();
            await ttsService.speak(response);
            break;
          }
        }

        // 2. Memory Fallback: If not visible in current view, fall back to stored RememberedItem
        final remembered = storageService.findRememberedItem(item);
        if (remembered != null) {
          final response = strings.isKannada
              ? 'ಪ್ರಸ್ತುತ ವೀಕ್ಷಣೆಯಲ್ಲಿ ಕಂಡುಬಂದಿಲ್ಲ. ನೀವು ಕೊನೆಯದಾಗಿ ಉಳಿಸಿದ್ದು: ನಿಮ್ಮ ${remembered.itemName} ${remembered.locationDescription} ಇದೆ.'
              : 'Not visible in your current view. You last remembered that your ${remembered.itemName} is ${remembered.locationDescription}.';
          _statusText = response;
          notifyListeners();
          await ttsService.speak(response);
          break;
        }

        final lowerRaw = command.rawText.toLowerCase();
        final isSavedLookup = lowerRaw.contains('saved') ||
            lowerRaw.contains('leave') ||
            lowerRaw.contains('left') ||
            lowerRaw.contains('put');

        final matches = storageService.savedItems.where(
          (e) => (e['name'] ?? '').toLowerCase() == item.toLowerCase() ||
                 (e['name'] ?? '').toLowerCase() == rawItem.toLowerCase(),
        ).toList();

        if (isSavedLookup && matches.isNotEmpty) {
          final notes = matches.first['notes'];
          final noteDetail = (notes != null && notes.isNotEmpty) ? ', noted: $notes' : '';
          await ttsService.speak(
            strings.isKannada
                ? 'ಉಳಿಸಿದ ವಸ್ತು $item ಹುಡುಕಲಾಗುತ್ತಿದೆ.'
                : 'Searching for your saved $item$noteDetail.',
          );
        } else {
          await ttsService.speak(
            strings.isKannada
                ? '$item ಹುಡುಕಲಾಗುತ್ತಿದೆ.'
                : 'Searching for $item.',
          );
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'find',
          'visionArg': item,
          'isSavedLookup': isSavedLookup,
          'savedNotes': matches.isNotEmpty ? matches.first['notes'] : null,
        });
        break;

      case VoiceCommandType.enrollFriend:
        await enrollFriend(command.argument ?? 'Friend');
        break;

      case VoiceCommandType.whoIsHere:
        final friends = storageService.getSavedFriends();
        final names = friends.map((f) => f.name).join(', ');
        final prompt = friends.isNotEmpty
            ? (strings.isKannada
                ? 'ಕ್ಯಾಮೆರಾ ಮುಂದೆ ಯಾರು ಇದ್ದಾರೆ? ಉಳಿಸಿದ ಸ್ನೇಹಿತರ ಪಟ್ಟಿ: $names. ಈ ವ್ಯಕ್ತಿ ಯಾರಾದರೂ ಸ್ನೇಹಿತರಿಗೆ ಸರಿಹೊಂದುತ್ತಾರೆಯೇ ಎಂದು ತಿಳಿಸಿ.'
                : "Who is in front of the camera? Saved friend profiles: $names. Check if this person matches any saved friend, or describe who is standing in front of the user spatially (left, center, right).")
            : (strings.isKannada
                ? 'ಕ್ಯಾಮೆರಾ ಮುಂದೆ ಯಾರು ಇದ್ದಾರೆ ಎಂಬುದನ್ನು ಪ್ರಾದೇಶಿಕವಾಗಿ ತಿಳಿಸಿ.'
                : "Who is in front of the camera? Describe the person in front of the user spatially (left, center, right).");

        if (_navDelegate != null && storageService.useGeminiLive) {
          await askGeminiWithVision(prompt);
        } else {
          navigatorKey.currentState?.pushNamed('/navigation', arguments: {
            'visionAction': 'whoIsHere',
          });
        }
        break;

      case VoiceCommandType.findPerson:
        navigatorKey.currentState?.pushNamed('/feature_detail', arguments: {
          'title': 'Face Recognition',
          'status': 'In Development',
          'explanation': 'Face recognition and saved people requires explicit biometric enrollment with privacy safeguards.',
          'technicalNotes': 'On-device face embeddings using privacy-preserving local storage.',
          'icon': Icons.face,
        });
        break;

      case VoiceCommandType.increaseSpeechSpeed:
        final newRate = (storageService.speechRate + 0.1).clamp(0.2, 1.0);
        await storageService.setSpeechRate(newRate);
        await ttsService.updateSettings(rate: newRate);
        await ttsService.speak('Speech speed increased to ${(newRate * 2).toStringAsFixed(1)}x.');
        break;

      case VoiceCommandType.decreaseSpeechSpeed:
        final newRate = (storageService.speechRate - 0.1).clamp(0.2, 1.0);
        await storageService.setSpeechRate(newRate);
        await ttsService.updateSettings(rate: newRate);
        await ttsService.speak('Speech speed decreased to ${(newRate * 2).toStringAsFixed(1)}x.');
        break;

      case VoiceCommandType.switchLanguage:
        final targetLang = command.argument ?? 'en';
        final newLang = AppLanguage.fromCode(targetLang);
        await storageService.setAppLanguage(targetLang);
        final isAvailable = await ttsService.setLanguage(newLang.ttsLocale);
        final newStrings = AppStrings(newLang);

        if (newLang == AppLanguage.kn && !isAvailable) {
          await ttsService.speak(newStrings.kannadaTtsUnavailableWarning);
        } else {
          await ttsService.speak(newStrings.languageChangedConfirmation(newLang));
        }
        notifyListeners();
        break;

      case VoiceCommandType.emergency:
        HapticFeedback.heavyImpact();
        final contact = storageService.emergencyContact;
        await ttsService.speak(
          strings.isKannada
              ? 'ತುರ್ತು ಮೋಡ್ ಸಕ್ರಿಯವಾಗಿದೆ. ನಿಮ್ಮ ತುರ್ತು ಸಂಪರ್ಕ ಸಂಖ್ಯೆ $contact. ಸಹಾಯಕ್ಕಾಗಿ 112 ಕರೆ ಮಾಡಿ.'
              : 'Emergency mode active. Emergency contact is $contact. Opening emergency assistance and acquiring location.',
        );
        navigatorKey.currentState?.pushNamed('/feature_detail', arguments: {
          'title': strings.featEmergencyTitle,
          'status': strings.statusAvailable,
          'explanation': strings.isKannada
              ? 'ತುರ್ತು ಸಂಪರ್ಕ: $contact. ತುರ್ತು ಪರಿಸ್ಥಿತಿಯಲ್ಲಿ ತಕ್ಷಣ 112 ಅಥವಾ ನಿಮ್ಮ ತುರ್ತು ಸಂಪರ್ಕಕ್ಕೆ ಕರೆ ಮಾಡಿ.'
              : 'Emergency contact: $contact. In an emergency, always call 112 or your emergency contact immediately.',
          'technicalNotes': 'GPS location and emergency contact guidance ready.',
          'icon': Icons.emergency,
        });
        break;

      case VoiceCommandType.aroundMe:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        try {
          await nav.announceNearbyAmenities();
        } finally {
          nav.dispose();
        }
        break;

      case VoiceCommandType.toggleTorch:
        await ttsService.speak(
          strings.isKannada
              ? 'ಟಾರ್ಚ್ ನಿಯಂತ್ರಣಕ್ಕಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Opening camera for flashlight control.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'torch',
          'torchState': command.argument,
        });
        break;

      case VoiceCommandType.toggleObstacleAlerts:
        await ttsService.speak(
          strings.isKannada
              ? 'ಲೈವ್ ಅಡೆತಡೆ ಎಚ್ಚರಿಕೆಗಳನ್ನು ನಿಯಂತ್ರಿಸಲು ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Opening camera navigation for obstacle alerts.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'toggleAlerts',
        });
        break;

      case VoiceCommandType.batteryStatus:
        final isKn = strings.isKannada;
        final hasLocation = await Geolocator.isLocationServiceEnabled();
        final emergency = storageService.emergencyContact;
        final langName = isKn ? 'ಕನ್ನಡ' : 'English';
        final speed = (storageService.speechSpeed * 100).round();

        if (isKn) {
          final locStatus = hasLocation ? 'ಜಿಪಿಎಸ್ ಸಕ್ರಿಯವಾಗಿದೆ' : 'ಜಿಪಿಎಸ್ ಆಫ್ ಆಗಿದೆ';
          await ttsService.speak(
            'ಡಿವೈಸ್ ಸ್ಥಿತಿ: $locStatus. ಭಾಷೆ $langName, ಧ್ವನಿ ವೇಗ ಶೇಕಡಾ $speed. ತುರ್ತು ಸಂಪರ್ಕ ಸಂಖ್ಯೆ $emergency. ಎಲ್ಲ ವ್ಯವಸ್ಥೆಗಳು ಕಾರ್ಯನಿರ್ವಹಿಸುತ್ತಿವೆ.',
          );
        } else {
          final locStatus = hasLocation ? 'GPS is active' : 'GPS location is disabled';
          await ttsService.speak(
            'Device status: $locStatus. Assistant language is $langName, speech rate is $speed percent. Emergency contact is $emergency. All systems operational.',
          );
        }
        break;

      case VoiceCommandType.facingDirection:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        await nav.announceFacingDirection();
        break;

      case VoiceCommandType.checkTrafficLight:
        await ttsService.speak(
          strings.isKannada
              ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲನೆಗಾಗಿ ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
              : 'Opening camera to inspect traffic signal color.',
        );
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'trafficLight',
        });
        break;

      case VoiceCommandType.saveFavoritePlace:
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        final tag = command.argument ?? 'home';
        await nav.saveCurrentLocationAsFavorite(tag: tag);
        break;

      case VoiceCommandType.none:
        // Silence or empty input: silently return to standby without any error speech
        break;

      case VoiceCommandType.unknown:
        final raw = command.rawText.trim();
        // Ignore very short noise, coughs, or single stray characters
        if (raw.length <= 2) {
          break;
        }

        // If Gemini Live is enabled, process open-ended conversational intent via Gemini!
        if (geminiLiveService != null && storageService.useGeminiLive && storageService.geminiApiKey.isNotEmpty) {
          _statusText = 'Gemini is thinking...';
          notifyListeners();
          final aiResponse = await geminiLiveService!.queryGeminiFlash(
            apiKey: storageService.geminiApiKey,
            prompt: 'User said: "$raw". As Gemini, the intelligent mobility companion for blind pedestrians, answer concisely, empathetically, with clock bearings and step distances where applicable, and guide them.',
          );
          _statusText = aiResponse;
          notifyListeners();
          await ttsService.speak(aiResponse);
          break;
        }

        final reply = strings.unknownCommand(command.rawText);
        _statusText = reply;
        notifyListeners();
        await ttsService.speak(reply);
        break;
    }
  }

  NavigationVoiceDelegate? get _navDelegate =>
      _activeDelegate is NavigationVoiceDelegate ? _activeDelegate as NavigationVoiceDelegate : null;

  void _initGeminiLiveTools() {
    if (geminiLiveService == null) return;

    geminiLiveService!.setToolHandlers(GeminiLiveToolHandlers(
      onNavigateTo: (destination) async {
        if (_navDelegate?.handleDestination(destination) == true) {
          return 'Route updated to $destination.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: destination);
        return 'Starting pedestrian navigation to $destination.';
      },
      onGetCurrentLocation: () async {
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        try {
          final loc = await nav.resolveCurrentLocation();
          if (loc == null) return 'Unable to get GPS satellite fix.';
          return 'Current location: ${loc['road']}, ${loc['suburb']}. Coordinates: ${loc['latitude']}, ${loc['longitude']}.';
        } finally {
          nav.dispose();
        }
      },
      onGetNearbyPlaces: (radius) async {
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        try {
          final places = await nav.exploreNearbyAmenities(radiusMeters: radius);
          if (places.isEmpty) return 'No notable civic places found within $radius meters.';
          final list = places.take(4).map((p) => '${p['name']} (${p['distance']}m, ${p['type']})').join(', ');
          return 'Found nearby: $list.';
        } finally {
          nav.dispose();
        }
      },
      onVerifyCurrency: () async {
        if (_navDelegate?.handleVisionAction('currency') == true) {
          return 'Scanning currency note.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'currency'});
        return 'Opening camera to scan and authenticate Indian banknote or coin.';
      },
      onReadBusRoute: () async {
        if (_navDelegate?.handleVisionAction('bus') == true) {
          return 'Scanning oncoming bus route.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'bus'});
        return 'Opening camera to scan oncoming city bus route number.';
      },
      onCheckTrafficLight: () async {
        if (_navDelegate?.handleVisionAction('trafficLight') == true) {
          return 'Checking traffic light.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'trafficLight'});
        return 'Opening camera to inspect traffic light and pedestrian crossing.';
      },
      onDetectObstacles: () async {
        if (_navDelegate?.handleVisionAction('detect') == true) {
          return 'Active obstacle detection running.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'detect'});
        return 'Opening camera for real-time obstacle detection and distance tracking.';
      },
      onDescribeSurroundings: () async {
        if (_navDelegate?.handleVisionAction('describe') == true) {
          return 'Inspecting surroundings.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'describe'});
        return 'Opening camera to inspect and describe your visual surroundings.';
      },
      onReadText: (mode) async {
        if (_navDelegate?.handleVisionAction('ocr', mode) == true) {
          return 'Reading text from camera view.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'ocr', 'ocrMode': mode ?? 'smart'});
        return 'Opening camera to read text and signage.';
      },
      onStopNavigation: () async {
        if (_navDelegate?.handleStopNavigation() == true) {
          return 'Navigation stopped. Returned to home screen.';
        }
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState?.pop();
          return 'Navigation stopped. Returned to home screen.';
        }
        return 'Navigation is not currently active.';
      },
      onGoBack: () async {
        if (navigatorKey.currentState?.canPop() == true) {
          navigatorKey.currentState?.pop();
          return 'Navigated back.';
        }
        return 'Already at home screen.';
      },
      onOpenSettings: () async {
        navigatorKey.currentState?.pushNamed('/settings');
        return 'Opening settings screen.';
      },
      onChangeLanguage: (lang) async {
        final code = (lang.toLowerCase().contains('kn') || lang.toLowerCase().contains('kannada')) ? 'kn' : 'en';
        await storageService.setAppLanguage(code);
        await ttsService.setLanguage(code == 'kn' ? 'kn-IN' : 'en-US');
        notifyListeners();
        return code == 'kn' ? 'ಭಾಷೆಯನ್ನು ಕನ್ನಡಕ್ಕೆ ಬದಲಾಯಿಸಲಾಗಿದೆ.' : 'Language changed to English.';
      },
      onSetSpeechSpeed: (speed) async {
        final lower = speed.toLowerCase();
        double current = storageService.speechRate;
        if (lower.contains('faster') || lower.contains('fast')) {
          current = (current + 0.1).clamp(0.2, 1.0);
        } else if (lower.contains('slower') || lower.contains('slow')) {
          current = (current - 0.1).clamp(0.2, 1.0);
        } else {
          current = 0.5;
        }
        await storageService.setSpeechRate(current);
        await ttsService.setSpeechRate(current);
        return 'Speech rate adjusted to ${(current * 2).toStringAsFixed(1)}x.';
      },
      onTriggerEmergencySOS: () async {
        navigatorKey.currentState?.pushNamed('/feature_detail', arguments: {
          'title': 'Emergency SOS',
          'status': 'Active',
          'explanation': 'Emergency contact: ${storageService.emergencyContact}',
          'technicalNotes': 'GPS location and emergency broadcast active.',
          'icon': Icons.emergency,
        });
        return 'Emergency SOS activated. Announcing coordinates and ready to dial ${storageService.emergencyContact}.';
      },
      onFindItem: (item) async {
        if (_navDelegate?.handleVisionAction('find', item) == true) {
          return 'Searching for $item.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'find', 'visionArg': item});
        return 'Opening camera to search for $item.';
      },
      onSaveFavoritePlace: (tag, name) async {
        final nav = PedestrianNavigationService(
          ttsService: ttsService,
          storageService: storageService,
        );
        try {
          final ok = await nav.saveCurrentLocationAsFavorite(tag: tag, customName: name);
          return ok ? 'Successfully bookmarked current GPS location as $tag.' : 'Could not save bookmark.';
        } finally {
          nav.dispose();
        }
      },
      onToggleTorch: (enabled) async {
        if (_navDelegate?.handleVisionAction('torch', enabled ? 'on' : 'off') == true) {
          return 'Flashlight torch turned ${enabled ? 'on' : 'off'}.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {
          'visionAction': 'torch',
          'torchState': enabled ? 'on' : 'off',
        });
        return 'Flashlight torch turned ${enabled ? 'on' : 'off'}.';
      },
      onGetDeviceStatus: () async {
        final hasLocation = await Geolocator.isLocationServiceEnabled();
        return 'Device GPS: ${hasLocation ? "Active" : "Disabled"}. Emergency contact: ${storageService.emergencyContact}. Language: ${storageService.appLanguage}. All systems operational.';
      },
      onWhoIsHere: () async {
        if (_navDelegate?.handleVisionAction('whoIsHere') == true) {
          return 'Checking who is in front of the camera.';
        }
        navigatorKey.currentState?.pushNamed('/navigation', arguments: {'visionAction': 'whoIsHere'});
        return 'Opening camera to identify who is in front of you.';
      },
      onEnrollFriend: (name) async {
        if (_navDelegate?.handleVisionAction('enrollFriend', name) == true) {
          return 'Enrolling friend $name.';
        }
        navigatorKey.currentState?.pushNamed(
          '/navigation',
          arguments: {'visionAction': 'enrollFriend', 'visionArg': name},
        );
        return 'Opening camera to remember $name.';
      },
      onRememberItem: (item, location) async {
        await storageService.saveRememberedItem(item, location);
        return 'I will remember that your $item is $location.';
      },
      onRecallItem: (item) async {
        final remembered = storageService.findRememberedItem(item);
        if (remembered != null) {
          return 'You saved that your ${remembered.itemName} is ${remembered.locationDescription}.';
        }
        return 'No saved record for $item.';
      },
    ));
  }
}
