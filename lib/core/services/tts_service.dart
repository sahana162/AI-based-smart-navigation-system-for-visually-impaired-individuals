import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Explicit priority tiers for assistive speech delivery.
enum TtsPriority {
  emergency, // Priority 0: Life-safety SOS alerts, immediate stop commands (cuts off all)
  hazard, // Priority 1: Obstacle proximity alerts and overhead hazard warnings
  navigation, // Priority 2: Turn-by-turn guidance and waypoint maneuvers
  ambient, // Priority 3: General descriptive scenery, bus stops, non-urgent OCR text
}

class TtsQueueItem {
  final String text;
  final TtsPriority priority;
  final Completer<void> completer;

  TtsQueueItem({
    required this.text,
    required this.priority,
    required this.completer,
  });
}

/// Text-to-Speech wrapper around [FlutterTts] with priority audio arbitration.
///
/// Extends [ChangeNotifier] so services and widgets know when speech begins and ends,
/// preventing microphone feedback loops where the assistant hears its own voice.
class TtsService extends ChangeNotifier {
  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  TtsPriority _currentSpeakingPriority = TtsPriority.ambient;
  String _lastMessage = '';
  DateTime? _lastSpeakTime;

  String _currentLocale = 'en-US';
  double _speechRate = 0.5;
  double _speechPitch = 1.0;
  VoidCallback? onSpeechCompleted;
  Function(TtsPriority priority)? onSpeechStarting;

  final List<TtsQueueItem> _queue = [];
  bool _isProcessingQueue = false;

  bool get isSpeaking => _isSpeaking;
  String get lastMessage => _lastMessage;
  String get currentLocale => _currentLocale;
  String get currentLanguage => _currentLocale;
  bool get isKannada => _currentLocale.toLowerCase().startsWith('kn');
  TtsPriority get currentPriority => _currentSpeakingPriority;

  TtsService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage(_currentLocale);
      await _tts.setSpeechRate(_speechRate);
      await _tts.setPitch(_speechPitch);
      await _tts.setVolume(1.0);
      await _tts.awaitSynthCompletion(true);

      // Bypass iOS hardware silent switch and duck background audio
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
      );

      _tts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _currentSpeakingPriority = TtsPriority.ambient;
        notifyListeners();
        onSpeechCompleted?.call();
        _processNextInQueue();
      });

      _tts.setErrorHandler((dynamic msg) {
        debugPrint('[TtsService] Engine error: $msg');
        _isSpeaking = false;
        _currentSpeakingPriority = TtsPriority.ambient;
        notifyListeners();
        _processNextInQueue();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _currentSpeakingPriority = TtsPriority.ambient;
        notifyListeners();
        _processNextInQueue();
      });
    } catch (e) {
      debugPrint('[TtsService] _initTts exception: $e');
    }
  }

  /// Initialise with optional [rate] (0.0–1.0), [pitch] (0.5–2.0), and [language].
  Future<void> initialize({
    double rate = 0.5,
    double pitch = 1.0,
    String language = 'en-US',
  }) async {
    _currentLocale = language;
    _speechRate = rate;
    _speechPitch = pitch;
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(1.0);
      await _tts.awaitSynthCompletion(true);
    } catch (e) {
      debugPrint('TtsService.initialize platform exception: $e');
    }
  }

  // ── Playback with Priority Queue & Preemption ──────────────────────────────

  /// Primary speak method with automatic priority-based preemption.
  Future<void> speak(
    String text, {
    TtsPriority priority = TtsPriority.ambient,
    bool force = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Deduplicate identical speech within 1.5 seconds unless forced
    final now = DateTime.now();
    if (!force &&
        _lastMessage.trim().toLowerCase() == trimmed.toLowerCase() &&
        _lastSpeakTime != null &&
        now.difference(_lastSpeakTime!).inMilliseconds < 1500) {
      debugPrint('[TtsService] Suppressed duplicate speech within 1500ms: "$trimmed"');
      return;
    }

    // Preemption Rule: If incoming message is emergency or hazard, or has higher priority than currently speaking message:
    if (_isSpeaking && (priority == TtsPriority.emergency || priority == TtsPriority.hazard || priority.index < _currentSpeakingPriority.index)) {
      debugPrint('[TtsService] Preempting ${_currentSpeakingPriority.name} for higher priority: ${priority.name}');
      await _tts.stop();
      _isSpeaking = false;
      _queue.removeWhere((item) => item.priority.index > priority.index);
    }

    final completer = Completer<void>();
    final newItem = TtsQueueItem(text: trimmed, priority: priority, completer: completer);

    // Insert sorted by priority (lowest enum index = highest priority)
    int insertIndex = _queue.indexWhere((item) => item.priority.index > priority.index);
    if (insertIndex == -1) {
      _queue.add(newItem);
    } else {
      _queue.insert(insertIndex, newItem);
    }

    if (!_isSpeaking && !_isProcessingQueue) {
      _processNextInQueue();
    }

    return completer.future;
  }

  /// Emergency alert: cuts off all ongoing audio instantly and sets maximum volume.
  Future<void> emergencySpeak(String text) async {
    _queue.clear();
    await _tts.stop();
    _isSpeaking = false;
    await _tts.setVolume(1.0);
    return speak(text, priority: TtsPriority.emergency, force: true);
  }

  Future<void> _processNextInQueue() async {
    if (_queue.isEmpty || _isSpeaking) return;
    _isProcessingQueue = true;

    final nextItem = _queue.removeAt(0);
    _currentSpeakingPriority = nextItem.priority;
    _lastMessage = nextItem.text;
    _lastSpeakTime = DateTime.now();
    onSpeechStarting?.call(nextItem.priority);

    try {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        _isSpeaking = true;
        notifyListeners();
      }
      await _tts.speak(nextItem.text);
      if (!nextItem.completer.isCompleted) {
        nextItem.completer.complete();
      }
    } catch (e) {
      debugPrint('[TtsService] Error speaking: $e');
      if (!nextItem.completer.isCompleted) {
        nextItem.completer.completeError(e);
      }
    } finally {
      _isProcessingQueue = false;
      if (Platform.environment.containsKey('FLUTTER_TEST') && _queue.isNotEmpty) {
        _processNextInQueue();
      }
    }
  }

  /// Stops the currently playing speech immediately and clears the queue.
  Future<void> stop() async {
    _queue.clear();
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TtsService.stop platform exception: $e');
    }
    if (_isSpeaking) {
      _isSpeaking = false;
      _currentSpeakingPriority = TtsPriority.ambient;
      notifyListeners();
    }
  }

  /// Repeats the last spoken message, or speaks [emptyMessage] if none exists.
  Future<void> repeat({String emptyMessage = 'No message to repeat.'}) {
    if (_lastMessage.isEmpty) {
      return speak(emptyMessage);
    }
    // Explicit user request to repeat: reset debounce timestamp so it is never dropped
    _lastSpeakTime = null;
    return speak(_lastMessage, force: true);
  }

  /// Sets audio output volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    try {
      await _tts.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('TtsService.setVolume platform exception: $e');
    }
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  /// Updates speech [rate] and/or [pitch] at runtime.
  Future<void> updateSettings({double? rate, double? pitch}) async {
    try {
      if (rate != null) {
        _speechRate = rate.clamp(0.0, 1.0);
        await _tts.setSpeechRate(_speechRate);
      }
      if (pitch != null) {
        _speechPitch = pitch.clamp(0.5, 2.0);
        await _tts.setPitch(_speechPitch);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('TtsService.updateSettings platform exception: $e');
    }
  }

  /// Sets the TTS speaking rate (0.0 to 1.0).
  Future<void> setSpeechRate(double rate) => updateSettings(rate: rate);

  /// Sets the TTS pitch (0.5 to 2.0).
  Future<void> setPitch(double pitch) => updateSettings(pitch: pitch);

  /// Attempts to switch TTS to [locale] (e.g. 'en-US' or 'kn-IN').
  Future<bool> setLanguage(String locale) async {
    _currentLocale = locale;
    try {
      final result = await _tts.setLanguage(locale);
      notifyListeners();
      if (result == 1) {
        return true;
      }
      await _tts.setLanguage('en-US');
      _currentLocale = 'en-US';
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('TtsService.setLanguage platform exception: $e');
      notifyListeners();
      return false;
    }
  }

  /// Checks whether [locale] is available on the current device's TTS engine.
  Future<bool> isLanguageAvailable(String locale) async {
    try {
      final available = await _tts.isLanguageAvailable(locale);
      return available == true || available == 1;
    } catch (_) {
      return false;
    }
  }
}
