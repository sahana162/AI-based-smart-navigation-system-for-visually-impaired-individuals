import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Callback invoked as the user speaks.
///
/// [words] is the current transcript, [isFinal] is true on the last result.
typedef SpeechResultCallback = void Function(String words, bool isFinal);

enum SpeechErrorCategory {
  timeout,
  noMatch,
  permission,
  network,
  serviceUnavailable,
  other,
}

/// Speech-to-Text wrapper around [SpeechToText].
///
/// Extends [ChangeNotifier] so widgets can rebuild when [isListening] changes.
class SpeechService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;
  String? _lastError;
  SpeechErrorCategory? _lastErrorCategory;
  List<String> _availableLocales = [];
  String _currentTranscript = '';
  bool _finalDelivered = false;
  SpeechResultCallback? _activeResultCallback;

  VoidCallback? onListeningTimeout;
  void Function(String error, SpeechErrorCategory category)? onErrorOccurred;

  bool get isListening => _isListening;
  String? get lastError => _lastError;
  SpeechErrorCategory? get lastErrorCategory => _lastErrorCategory;
  String get currentTranscript => _currentTranscript;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Requests microphone permission and initialises the STT engine.
  Future<bool> initialize() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _lastError = 'Microphone permission denied.';
      _lastErrorCategory = SpeechErrorCategory.permission;
      debugPrint('[STT] Permission denied.');
      return false;
    }

    _isInitialized = await _stt.initialize(
      onError: (error) {
        debugPrint('[STT] Engine error: ${error.errorMsg} (permanent: ${error.permanent})');
        _lastError = error.errorMsg;
        final lower = error.errorMsg.toLowerCase();

        final SpeechErrorCategory category;
        if (lower.contains('timeout') || lower.contains('error_speech_timeout')) {
          category = SpeechErrorCategory.timeout;
        } else if (lower.contains('no_match') || lower.contains('error_no_match') || lower.contains('client')) {
          category = SpeechErrorCategory.noMatch;
        } else if (lower.contains('network') || lower.contains('error_network')) {
          category = SpeechErrorCategory.network;
        } else if (lower.contains('busy') || lower.contains('not_available')) {
          category = SpeechErrorCategory.serviceUnavailable;
        } else {
          category = SpeechErrorCategory.other;
        }
        _lastErrorCategory = category;

        if (_isListening) {
          _isListening = false;
          notifyListeners();
        }

        // If we have an existing partial transcript when timeout/no_match arrives,
        // salvage it as the final transcript!
        if (_currentTranscript.trim().isNotEmpty && !_finalDelivered && _activeResultCallback != null) {
          debugPrint('[STT] Salvaging partial transcript on error: "$_currentTranscript"');
          _finalDelivered = true;
          final cb = _activeResultCallback;
          _activeResultCallback = null;
          cb?.call(_currentTranscript.trim(), true);
          return;
        }

        if (category == SpeechErrorCategory.timeout || category == SpeechErrorCategory.noMatch) {
          onListeningTimeout?.call();
        } else {
          onErrorOccurred?.call(error.errorMsg, category);
        }
      },
      onStatus: (status) {
        debugPrint('[STT] Engine status: $status');
        final nowListening = status == 'listening';
        if (nowListening != _isListening) {
          _isListening = nowListening;
          notifyListeners();
        }

        // When status transitions to done/notListening, check if we need to deliver buffered transcript
        if ((status == 'notListening' || status == 'done') &&
            _currentTranscript.trim().isNotEmpty &&
            !_finalDelivered &&
            _activeResultCallback != null) {
          debugPrint('[STT] Delivering final words on session completion: "$_currentTranscript"');
          _finalDelivered = true;
          final cb = _activeResultCallback;
          _activeResultCallback = null;
          cb?.call(_currentTranscript.trim(), true);
        }
      },
    );

    if (_isInitialized) {
      final locales = await _stt.locales();
      _availableLocales = locales.map((l) => l.localeId).toList();
      debugPrint('[STT] Engine initialized. Available locales: ${_availableLocales.length}');
    }

    return _isInitialized;
  }

  // ── Listening control ─────────────────────────────────────────────────────

  /// Starts listening for speech in [localeId] (e.g. 'en_US' or 'kn_IN').
  ///
  /// Prevents duplicate sessions, supports 14s listening window, and 3.5s normal pause tolerance.
  Future<bool> startListening({
    required SpeechResultCallback onResult,
    String localeId = 'en_US',
  }) async {
    // Prevent overlapping sessions
    if (_isListening) {
      debugPrint('[STT] Already listening. Ignoring duplicate start request.');
      return true;
    }

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return false;
    }

    _lastError = null;
    _lastErrorCategory = null;
    _currentTranscript = '';
    _finalDelivered = false;
    _activeResultCallback = onResult;

    debugPrint('[STT] Listening started (locale: $localeId, maxDuration: 14s, pauseTolerance: 3500ms)');

    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult result) {
          _currentTranscript = result.recognizedWords;
          if (result.finalResult) {
            if (_finalDelivered) {
              debugPrint('[STT] Dropping redundant final transcript from native engine: "${result.recognizedWords}"');
              return;
            }
            _finalDelivered = true;
            debugPrint('[STT] Final transcript received: "${result.recognizedWords}"');
            final cb = _activeResultCallback;
            _activeResultCallback = null;
            cb?.call(result.recognizedWords, true);
          } else {
            if (!_finalDelivered) {
              _activeResultCallback?.call(result.recognizedWords, false);
            }
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 14),
          pauseFor: const Duration(milliseconds: 3500),
          cancelOnError: false,
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('[STT] Exception during listen(): $e');
      _lastError = e.toString();
      _lastErrorCategory = SpeechErrorCategory.other;
      _isListening = false;
      _activeResultCallback = null;
      notifyListeners();
      return false;
    }

    _isListening = _stt.isListening;
    notifyListeners();
    return _isListening;
  }

  /// Stops an active listening session cleanly.
  Future<void> stopListening() async {
    if (!_isListening && !_stt.isListening) return;
    debugPrint('[STT] Stopping active listening session.');
    _activeResultCallback = null;
    _isListening = false;
    notifyListeners();
    try {
      await _stt.stop();
    } catch (e) {
      debugPrint('[STT] Exception during stop: $e');
    }
  }

  // ── Locale helpers ────────────────────────────────────────────────────────

  bool isLocaleSupported(String localeId) {
    if (_availableLocales.isEmpty) return false;
    return _availableLocales.any(
      (l) => l.toLowerCase().startsWith(localeId.toLowerCase().split('_').first),
    );
  }
}
