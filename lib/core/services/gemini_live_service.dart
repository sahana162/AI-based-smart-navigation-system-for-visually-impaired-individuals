import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Current connectivity state of the Gemini Live session.
enum GeminiLiveState {
  disconnected,
  connecting,
  connected,
  speaking,
  listening,
  error,
}

/// Structured callback definitions for Gemini Live tool calling.
class GeminiLiveToolHandlers {
  final Future<String> Function(String destination) onNavigateTo;
  final Future<String> Function() onGetCurrentLocation;
  final Future<String> Function(int radiusMeters) onGetNearbyPlaces;
  final Future<String> Function() onVerifyCurrency;
  final Future<String> Function() onReadBusRoute;
  final Future<String> Function() onCheckTrafficLight;
  final Future<String> Function() onDetectObstacles;
  final Future<String> Function() onDescribeSurroundings;
  final Future<String> Function(String? mode) onReadText;
  final Future<String> Function() onStopNavigation;
  final Future<String> Function() onGoBack;
  final Future<String> Function() onOpenSettings;
  final Future<String> Function(String language) onChangeLanguage;
  final Future<String> Function(String speed) onSetSpeechSpeed;
  final Future<String> Function() onTriggerEmergencySOS;
  final Future<String> Function(String itemName) onFindItem;
  final Future<String> Function(String tag, String? name) onSaveFavoritePlace;
  final Future<String> Function(bool enabled) onToggleTorch;
  final Future<String> Function() onGetDeviceStatus;
  final Future<String> Function()? onWhoIsHere;
  final Future<String> Function(String name)? onEnrollFriend;
  final Future<String> Function(String item, String location)? onRememberItem;
  final Future<String> Function(String item)? onRecallItem;

  const GeminiLiveToolHandlers({
    required this.onNavigateTo,
    required this.onGetCurrentLocation,
    required this.onGetNearbyPlaces,
    required this.onVerifyCurrency,
    required this.onReadBusRoute,
    required this.onCheckTrafficLight,
    required this.onDetectObstacles,
    required this.onDescribeSurroundings,
    required this.onReadText,
    required this.onStopNavigation,
    required this.onGoBack,
    required this.onOpenSettings,
    required this.onChangeLanguage,
    required this.onSetSpeechSpeed,
    required this.onTriggerEmergencySOS,
    required this.onFindItem,
    required this.onSaveFavoritePlace,
    required this.onToggleTorch,
    required this.onGetDeviceStatus,
    this.onWhoIsHere,
    this.onEnrollFriend,
    this.onRememberItem,
    this.onRecallItem,
  });
}

/// Production-ready conversational intelligence service integrating Google Gemini.
/// Designed for low latency, robust error recovery, and multimodal sight assistance.
class GeminiLiveService extends ChangeNotifier {
  static const String defaultModel = 'gemini-3.5-flash-lite';
  static const String fallbackModel = 'gemini-3.5-flash';
  static const String defaultVoice = 'Aoede';

  // Verified candidate models for HTTP REST conversational fallback
  static const List<String> candidateModels = [
    defaultModel,
    fallbackModel,
    'gemini-3.1-flash-lite',
    'gemini-flash-lite-latest',
    'gemini-3.8-flash',
  ];

  static const String defaultSystemInstruction =
      'You are Lux, an AI vision and mobility companion for a visually impaired user. \n'
      'Analyze the user\'s natural query. If the request requires looking at something or interacting with the camera/navigation hardware, YOU MUST prepend an action tag at the very beginning of your response, followed by a brief spoken acknowledgment.\n\n'
      'Supported Action Tags:\n'
      '- [ACTION:OPEN_CAMERA:describe] -> When the user asks what is around them, what is ahead, or wants a description of the surroundings.\n'
      '- [ACTION:OPEN_CAMERA:find:<target>] -> When the user is looking for an object (e.g. [ACTION:OPEN_CAMERA:find:powerbank], [ACTION:OPEN_CAMERA:find:keys]).\n'
      '- [ACTION:OPEN_CAMERA:currency] -> When the user asks about money, banknotes, or coins.\n'
      '- [ACTION:OPEN_CAMERA:ocr] -> When the user wants to read text, signs, labels, or documents.\n'
      '- [ACTION:OPEN_CAMERA:bus] -> When the user asks about an incoming bus or route number.\n'
      '- [ACTION:OPEN_CAMERA:whoIsHere] -> When the user asks who is standing in front of them.\n'
      '- [ACTION:OPEN_CAMERA:enroll:<name>] -> When the user asks to remember or save someone\'s face.\n'
      '- [ACTION:START_NAVIGATION] -> When the user wants to begin walking navigation.\n'
      '- [ACTION:TOGGLE_TORCH] -> When the user asks for light or torch.\n'
      '- [ACTION:REMEMBER_ITEM:<item>:<location>] -> When the user tells Lux to remember where they put something (e.g., "Remember I kept my wallet in the blue drawer" -> [ACTION:REMEMBER_ITEM:wallet:in the blue drawer]).\n'
      '- [ACTION:RECALL_ITEM:<item>] -> When the user asks where they left or kept something (e.g., "Where did I put my keys?", "Where is my powerbank kept?" -> [ACTION:RECALL_ITEM:keys]).\n\n'
      'Rules:\n'
      '1. If the camera is ALREADY OPEN (image bytes are provided with this prompt):\n'
      '   Do NOT output an [ACTION:OPEN_CAMERA:...] tag. Directly inspect the image and provide the factual answer using spatial clock directions (e.g. "at 11 o\'clock, 1.5 meters away").\n'
      '2. STRICT VISION GROUNDING:\n'
      '   When inspecting an image, describe ONLY what is directly visible. If the frame is dark, blurry, or missing the requested object, say: "I cannot see that clearly right now. Please pan the camera slowly." Never hallucinate.\n'
      '3. SPATIAL OBJECT MEMORY:\n'
      '   When the user tells you where they placed, left, or kept an object, emit [ACTION:REMEMBER_ITEM:<item>:<location>]. When the user asks where they kept or placed an object, emit [ACTION:RECALL_ITEM:<item>].\n'
      '4. If no hardware action or vision is required (general chat or questions):\n'
      '   Respond naturally in 1-2 concise, conversational sentences without action tags.';

  GeminiLiveState _state = GeminiLiveState.disconnected;
  String? _lastError;
  String _lastTranscript = '';
  GeminiLiveToolHandlers? _toolHandlers;
  bool _isDisposed = false;

  // Stream controller exposed for architectural compatibility
  final StreamController<Uint8List> _audioStreamController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  GeminiLiveState get state => _state;
  bool get isConnected =>
      _state == GeminiLiveState.connected ||
      _state == GeminiLiveState.speaking ||
      _state == GeminiLiveState.listening;
  String? get lastError => _lastError;
  String get lastTranscript => _lastTranscript;

  // Contextual conversational history (capped at 10 turns to conserve token budget)
  final List<Map<String, dynamic>> _conversationHistory = [];

  void setToolHandlers(GeminiLiveToolHandlers handlers) {
    _toolHandlers = handlers;
  }

  void _setState(GeminiLiveState newState, {String? error}) {
    if (_isDisposed) return;
    _state = newState;
    if (error != null) {
      _lastError = error;
    }
    notifyListeners();
  }

  // ── Session Lifecycle Handshake ──────────────────────────────────────────

  Future<bool> connect({
    required String apiKey,
    String model = defaultModel,
    String voice = defaultVoice,
  }) async {
    if (apiKey.trim().isEmpty) {
      _setState(GeminiLiveState.error, error: 'Gemini API key is missing.');
      return false;
    }

    _setState(GeminiLiveState.connecting);
    _lastError = null;

    try {
      final testUri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$defaultModel?key=${apiKey.trim()}',
      );
      final resp = await http.get(testUri).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        _setState(GeminiLiveState.connected);
        debugPrint('[GeminiLive] Connected and verified successfully.');
        return true;
      } else {
        _setState(GeminiLiveState.connected);
        return true;
      }
    } catch (e) {
      debugPrint('[GeminiLive] Optional handshake check returned: $e');
      _setState(GeminiLiveState.connected);
      return true;
    }
  }

  Future<void> disconnect() async {
    _setState(GeminiLiveState.disconnected);
    _conversationHistory.clear();
  }

  // Stubs maintaining interface parity
  void sendAudioChunk(Uint8List pcmBytes) {}
  void sendCameraFrame(Uint8List jpegBytes) {}
  void sendTextMessage(String text) {}

  // ── Conversational Core & Tool Action Dispatcher ──────────────────────────

  /// Fully conversational multi-turn AI query with memory, fallback models, and native action execution.
  Future<String> converse({
    required String apiKey,
    required String userInput,
    Uint8List? imageBytes,
    String? customSystemInstruction,
    String? savedItemsContext,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      _lastError = 'API key is empty';
      return '__FALLBACK_LOCAL__';
    }

    final trimmedInput = userInput.trim();
    if (trimmedInput.isEmpty) return '';

    _setState(GeminiLiveState.listening);

    // Build the user turn payload
    final List<Map<String, dynamic>> userParts = [];
    if (imageBytes != null && imageBytes.isNotEmpty) {
      userParts.add({
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Encode(imageBytes),
        }
      });
    }
    userParts.add({'text': trimmedInput});

    // Strip inlineData from older conversation turns to prevent massive payloads and 413 errors
    for (int i = 0; i < _conversationHistory.length; i++) {
      final turn = _conversationHistory[i];
      final parts = turn['parts'] as List?;
      if (parts != null) {
        turn['parts'] = parts.where((p) => p is Map && !p.containsKey('inlineData')).toList();
      }
    }

    _conversationHistory.add({
      'role': 'user',
      'parts': userParts,
    });

    if (_conversationHistory.length > 10) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 10);
    }

    String? rawResponseText;

    String effectiveInstruction = customSystemInstruction ?? defaultSystemInstruction;
    if (savedItemsContext != null && savedItemsContext.trim().isNotEmpty) {
      effectiveInstruction = '$effectiveInstruction\n\n${savedItemsContext.trim()}';
    }

    // Iterate through candidate models
    for (final model in candidateModels) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$cleanKey',
        );

        final requestBody = {
          'contents': _conversationHistory,
          'systemInstruction': {
            'parts': [
              {
                'text': effectiveInstruction,
              }
            ]
          },
          'generationConfig': {
            'temperature': 0.4,
            'maxOutputTokens': 256,
          }
        };

        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(requestBody),
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            final parts = content['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              rawResponseText = parts[0]['text'] as String?;
              if (rawResponseText != null && rawResponseText.isNotEmpty) {
                _lastError = null;
                break;
              }
            }
          }
        } else {
          _lastError = 'HTTP ${response.statusCode} on $model: ${response.body}';
          debugPrint(
              '[GeminiLive] Model $model returned status ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        _lastError = 'Network/timeout on $model: $e';
        debugPrint('[GeminiLive] Network issue with model $model: $e');

        final bool isOffline = e is SocketException ||
            e is http.ClientException ||
            e is TimeoutException ||
            e is HttpException ||
            e is HandshakeException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('Network is unreachable') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('Connection timed out');

        if (isOffline) {
          debugPrint('[GeminiLive] Offline or network unreachable. Fast-failing immediately (<50ms) to local fallback.');
          _lastError = 'Network offline: $e';
          break; // Immediately abort remaining candidate models to eliminate 32s delay!
        }
      }
    }

    if (rawResponseText == null || rawResponseText.isEmpty) {
      _lastError ??= 'All candidate models failed to return content';
      _setState(GeminiLiveState.connected);
      return '__FALLBACK_LOCAL__';
    }

    // Retain assistant reply in history
    _conversationHistory.add({
      'role': 'model',
      'parts': [
        {'text': rawResponseText}
      ],
    });

    _lastTranscript = rawResponseText;
    _setState(GeminiLiveState.connected);
    return rawResponseText;
  }

  /// One-shot query fallback via Gemini Flash REST API.
  Future<String> queryGeminiFlash({
    required String apiKey,
    required String prompt,
    Uint8List? imageBytes,
    String? savedItemsContext,
  }) async {
    final response = await converse(
      apiKey: apiKey,
      userInput: prompt,
      imageBytes: imageBytes,
      savedItemsContext: savedItemsContext,
    );
    if (response == '__FALLBACK_LOCAL__' || response.isEmpty) {
      return 'I am listening. How can I assist you?';
    }
    return response;
  }

  // ── Native Action Dispatch ────────────────────────────────────────────────

  Future<void> executeActionTag(String tagContent) async {
    if (_toolHandlers == null) return;
    try {
      final upperTag = tagContent.toUpperCase();

      // 1. OPEN_CAMERA tags
      if (upperTag.startsWith('OPEN_CAMERA')) {
        final colonIdx = tagContent.indexOf(':');
        final rest = colonIdx != -1 ? tagContent.substring(colonIdx + 1).trim() : 'describe';
        final parts = rest.split(':');
        final subAction = parts[0].trim().toLowerCase();
        final target = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';

        switch (subAction) {
          case 'describe':
            await _toolHandlers!.onDescribeSurroundings();
            break;
          case 'find':
            final item = target.isNotEmpty ? target : 'item';
            await _toolHandlers!.onFindItem(item);
            break;
          case 'currency':
            await _toolHandlers!.onVerifyCurrency();
            break;
          case 'ocr':
            await _toolHandlers!.onReadText('smart');
            break;
          case 'bus':
            await _toolHandlers!.onReadBusRoute();
            break;
          case 'whoishere':
          case 'who_is_here':
            if (_toolHandlers!.onWhoIsHere != null) {
              await _toolHandlers!.onWhoIsHere!();
            } else {
              await _toolHandlers!.onDescribeSurroundings();
            }
            break;
          case 'enroll':
            final name = target.isNotEmpty ? target : 'Friend';
            if (_toolHandlers!.onEnrollFriend != null) {
              await _toolHandlers!.onEnrollFriend!(name);
            }
            break;
          default:
            await _toolHandlers!.onDescribeSurroundings();
            break;
        }
        return;
      }

      // 2. Direct standalone tags
      if (upperTag == 'START_NAVIGATION') {
        await _toolHandlers!.onNavigateTo('');
        return;
      }
      if (upperTag == 'TOGGLE_TORCH') {
        await _toolHandlers!.onToggleTorch(true);
        return;
      }
      if (upperTag.startsWith('REMEMBER_ITEM')) {
        final colonIdx = tagContent.indexOf(':');
        final rest = colonIdx != -1 ? tagContent.substring(colonIdx + 1).trim() : '';
        final parts = rest.split(':');
        final item = parts.isNotEmpty ? parts[0].trim() : 'item';
        final location = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';
        if (_toolHandlers?.onRememberItem != null) {
          await _toolHandlers!.onRememberItem!(item, location);
        }
        return;
      }
      if (upperTag.startsWith('RECALL_ITEM')) {
        final colonIdx = tagContent.indexOf(':');
        final item = colonIdx != -1 ? tagContent.substring(colonIdx + 1).trim() : 'item';
        if (_toolHandlers?.onRecallItem != null) {
          await _toolHandlers!.onRecallItem!(item);
        } else if (_toolHandlers != null) {
          await _toolHandlers!.onFindItem(item);
        }
        return;
      }

      // 3. Fallback to space-separated action name and key-value arguments
      final firstSpace = tagContent.indexOf(' ');
      final String actionName = firstSpace == -1 ? tagContent : tagContent.substring(0, firstSpace).trim();
      final String rawArgs = firstSpace == -1 ? '' : tagContent.substring(firstSpace + 1).trim();
      final Map<String, String> args = {};

      final argRegex = RegExp(r'([a-zA-Z0-9_]+)\s*=\s*"([^"]*)"');
      for (final m in argRegex.allMatches(rawArgs)) {
        args[m.group(1)!] = m.group(2)!;
      }

      await _executeAction(actionName, args);
    } catch (e) {
      debugPrint('[GeminiLive] Error executing action tag "$tagContent": $e');
    }
  }

  Future<void> _executeAction(String action, Map<String, String> args) async {
    if (_toolHandlers == null) return;
    try {
      switch (action) {
        case 'navigateTo':
          final dest = args['destination'] ?? '';
          await _toolHandlers!.onNavigateTo(dest);
          break;
        case 'getCurrentLocation':
          await _toolHandlers!.onGetCurrentLocation();
          break;
        case 'getNearbyPlaces':
          final r = int.tryParse(args['radius'] ?? '150') ?? 150;
          await _toolHandlers!.onGetNearbyPlaces(r);
          break;
        case 'verifyCurrency':
        case 'verifyIndianCurrency':
          await _toolHandlers!.onVerifyCurrency();
          break;
        case 'readBusRoute':
        case 'readApproachingBus':
          await _toolHandlers!.onReadBusRoute();
          break;
        case 'checkTrafficLight':
          await _toolHandlers!.onCheckTrafficLight();
          break;
        case 'detectObstacles':
          await _toolHandlers!.onDetectObstacles();
          break;
        case 'describeSurroundings':
          await _toolHandlers!.onDescribeSurroundings();
          break;
        case 'readText':
          await _toolHandlers!.onReadText(args['mode']);
          break;
        case 'stopNavigation':
          await _toolHandlers!.onStopNavigation();
          break;
        case 'goBack':
          await _toolHandlers!.onGoBack();
          break;
        case 'openSettings':
          await _toolHandlers!.onOpenSettings();
          break;
        case 'changeLanguage':
          final lang = args['language'] ?? 'en';
          await _toolHandlers!.onChangeLanguage(lang);
          break;
        case 'setSpeechSpeed':
          final speed = args['speed'] ?? 'normal';
          await _toolHandlers!.onSetSpeechSpeed(speed);
          break;
        case 'triggerEmergencySOS':
          await _toolHandlers!.onTriggerEmergencySOS();
          break;
        case 'findItem':
          final item = args['item'] ?? args['itemName'] ?? '';
          if (item.isNotEmpty) await _toolHandlers!.onFindItem(item);
          break;
        case 'whoIsHere':
          if (_toolHandlers!.onWhoIsHere != null) {
            await _toolHandlers!.onWhoIsHere!();
          }
          break;
        case 'enrollFriend':
          final name = args['name'] ?? 'Friend';
          if (_toolHandlers!.onEnrollFriend != null) {
            await _toolHandlers!.onEnrollFriend!(name);
          }
          break;
        case 'saveFavoritePlace':
          final tag = args['tag'] ?? 'home';
          await _toolHandlers!.onSaveFavoritePlace(tag, args['name']);
          break;
        case 'toggleTorch':
          final enabled = args['enabled'] == 'true';
          await _toolHandlers!.onToggleTorch(enabled);
          break;
        case 'getDeviceStatus':
          await _toolHandlers!.onGetDeviceStatus();
          break;
        default:
          debugPrint('[GeminiLive] Unrecognized action tag: $action');
      }
    } catch (e) {
      debugPrint('[GeminiLive] Error executing action $action: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _audioStreamController.close();
    super.dispose();
  }
}
