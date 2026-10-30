import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/pedestrian_navigation_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/services/voice_command_parser.dart';
import '../../core/services/voice_session_coordinator.dart';
import '../../core/theme/app_theme.dart';
import '../../models/voice_command.dart';
import '../widgets/accessible_button.dart';

class FeatureDetailScreen extends StatefulWidget {
  final String title;
  final String status;
  final String explanation;
  final String technicalNotes;
  final IconData icon;
  final TtsService ttsService;
  final SpeechService? speechService;
  final StorageService? storageService;
  final VoiceSessionCoordinator? voiceCoordinator;
  final String assistantName;
  final String? visionAction;
  final String? visionArg;

  const FeatureDetailScreen({
    super.key,
    required this.title,
    required this.status,
    required this.explanation,
    required this.technicalNotes,
    required this.icon,
    required this.ttsService,
    this.speechService,
    this.storageService,
    this.voiceCoordinator,
    this.assistantName = 'Lux',
    this.visionAction,
    this.visionArg,
  });

  @override
  State<FeatureDetailScreen> createState() => _FeatureDetailScreenState();
}

class _FeatureDetailScreenState extends State<FeatureDetailScreen>
    implements VoiceCommandDelegate {
  PedestrianNavigationService? _emergencyNavService;
  Map<String, dynamic>? _emergencyLocation;
  bool _isLoadingGps = false;
  bool _hasSpokenGreeting = false;

  bool get _isEmergency => widget.icon == Icons.emergency;

  String? get _resolvedAction {
    if (widget.visionAction != null) return widget.visionAction;
    final t = widget.title.toLowerCase();
    final ic = widget.icon;

    if (ic == Icons.emergency) return null;
    if (ic == Icons.traffic || t.contains('traffic') || t.contains('signal')) return 'trafficLight';
    if (ic == Icons.directions_bus || t.contains('bus')) return 'bus';
    if (ic == Icons.payments || ic == Icons.attach_money || t.contains('currency')) return 'currency';
    if (ic == Icons.document_scanner || t.contains('ocr') || t.contains('text')) return 'ocr';
    if (ic == Icons.visibility || t.contains('scene') || t.contains('describe')) return 'describe';
    if (ic == Icons.search || t.contains('lost') || t.contains('item')) return 'find';
    if (ic == Icons.radar || t.contains('around')) return 'around_me';
    if (ic == Icons.explore || ic == Icons.view_in_ar || t.contains('object')) return 'navigation';
    return null;
  }

  String _getActionLaunchLabel(String action, bool isKn) {
    switch (action) {
      case 'trafficLight':
        return isKn ? 'ಟ್ರಾಫಿಕ್ ಸಿಗ್ನಲ್ ಪರಿಶೀಲಿಸಿ' : 'Inspect Traffic Light Color';
      case 'bus':
        return isKn ? 'ಬಸ್ ಸಂಖ್ಯೆ ಸ್ಕ್ಯಾನರ್ ಪ್ರಾರಂಭಿಸಿ' : 'Scan Bus Route & Numbers Now';
      case 'currency':
        return isKn ? 'ಕರೆನ್ಸಿ ಸ್ಕ್ಯಾನರ್ ಪ್ರಾರಂಭಿಸಿ' : 'Scan Notes & Coins Now';
      case 'ocr':
        return isKn ? 'ಪಠ್ಯ ಓದುವಿಕೆ ಪ್ರಾರಂಭಿಸಿ' : 'Read Text & Signs Now';
      case 'describe':
        return isKn ? 'ಸುತ್ತಮುತ್ತಲಿನ ವಿವರಣೆ ಪ್ರಾರಂಭಿಸಿ' : 'Describe Surroundings Now';
      case 'find':
        return isKn ? 'ವಸ್ತು ಹುಡುಕಾಟ ಪ್ರಾರಂಭಿಸಿ' : 'Search for Items with Camera';
      case 'around_me':
        return isKn ? 'ಸುತ್ತಮುತ್ತಲಿನ ಸ್ಥಳಗಳನ್ನು ಹುಡುಕಿ' : 'Explore Nearby Places Now';
      case 'navigation':
      default:
        return isKn ? 'ಅಡೆತಡೆ ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ' : 'Start Camera Obstacle Navigation';
    }
  }

  IconData _getActionLaunchIcon(String action) {
    switch (action) {
      case 'trafficLight':
        return Icons.traffic;
      case 'bus':
        return Icons.directions_bus;
      case 'currency':
        return Icons.payments;
      case 'ocr':
        return Icons.document_scanner;
      case 'describe':
        return Icons.visibility;
      case 'find':
        return Icons.search;
      case 'around_me':
        return Icons.radar;
      case 'navigation':
      default:
        return Icons.explore;
    }
  }

  Future<void> _launchFeatureNow() async {
    final action = _resolvedAction;
    if (action == null) return;
    HapticFeedback.mediumImpact();

    final isKn = widget.ttsService.isKannada;
    if (action == 'around_me') {
      final nav = _emergencyNavService ??
          PedestrianNavigationService(
            ttsService: widget.ttsService,
            storageService: widget.storageService,
          );
      await nav.announceNearbyAmenities();
      return;
    }

    final confirm = isKn
        ? '${widget.title} ಪ್ರಾರಂಭಿಸಲಾಗುತ್ತಿದೆ. ಕ್ಯಾಮೆರಾ ತೆರೆಯಲಾಗುತ್ತಿದೆ.'
        : 'Starting ${widget.title}. Opening camera.';
    await widget.ttsService.speak(confirm);

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/navigation', arguments: {
      'visionAction': action == 'navigation' ? null : action,
      'visionArg': widget.visionArg ?? (action == 'find' ? 'item' : null),
    });
  }

  @override
  String get screenName => widget.title;

  @override
  void initState() {
    super.initState();
    widget.voiceCoordinator?.registerDelegate(this);

    if (_isEmergency) {
      _emergencyNavService = PedestrianNavigationService(
        ttsService: widget.ttsService,
        storageService: widget.storageService,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerEmergencyBroadcast();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hasSpokenGreeting || !mounted) return;
        _hasSpokenGreeting = true;
        final speech = '${widget.title}. Status: ${widget.status}. ${widget.explanation}';
        widget.ttsService.speak(speech);
      });
    }
  }

  @override
  void dispose() {
    _emergencyNavService?.dispose();
    widget.voiceCoordinator?.unregisterDelegate(this);
    super.dispose();
  }

  Future<void> _triggerEmergencyBroadcast() async {
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() {
      _isLoadingGps = true;
    });

    final loc = await _emergencyNavService?.announceCurrentLocation(isEmergency: true);

    if (mounted) {
      setState(() {
        _emergencyLocation = loc;
        _isLoadingGps = false;
      });
    }
  }

  @override
  bool handleVoiceCommand(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.goBack:
        widget.ttsService.speak('Returning to home screen.');
        Navigator.pop(context);
        return true;
      case VoiceCommandType.repeat:
        widget.ttsService.speak('${widget.title}. Status: ${widget.status}. ${widget.explanation}');
        return true;
      case VoiceCommandType.help:
        widget.ttsService.speak('Say: Repeat, Help, Stop speaking, or Go back.');
        return true;
      case VoiceCommandType.whereAmI:
      case VoiceCommandType.emergency:
        if (_isEmergency) {
          _triggerEmergencyBroadcast();
          return true;
        }
        return false;
      case VoiceCommandType.startNavigation:
      case VoiceCommandType.describeSurroundings:
      case VoiceCommandType.readText:
      case VoiceCommandType.recognizeCurrency:
      case VoiceCommandType.readBusRoute:
      case VoiceCommandType.checkTrafficLight:
      case VoiceCommandType.findItem:
      case VoiceCommandType.aroundMe:
        if (_resolvedAction != null) {
          _launchFeatureNow();
          return true;
        }
        return false;
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

    final cmd = VoiceCommandParser.parse(rawText, widget.assistantName);

    if (handleVoiceCommand(cmd)) return;

    widget.ttsService.speak(cmd.rawText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: Semantics(
          label: 'Back to Home',
          hint: 'Double tap to return to the previous screen',
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
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceHighlight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.border, width: 2),
                          ),
                          child: Icon(
                            widget.icon,
                            size: 44,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.status == 'Available'
                                ? AppTheme.success.withValues(alpha: 0.2)
                                : AppTheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: widget.status == 'Available'
                                  ? AppTheme.success
                                  : AppTheme.primary,
                            ),
                          ),
                          child: Text(
                            'Status: ${widget.status}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: widget.status == 'Available'
                                  ? AppTheme.success
                                  : AppTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Semantics(
                          container: true,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Description & Availability',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.explanation,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          container: true,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Technical Implementation Status',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.technicalNotes,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.5,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.icon == Icons.emergency) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.danger, width: 2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 26),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Live Emergency Location',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_isLoadingGps)
                                  const Row(
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.danger),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Acquiring GPS fix and nearest address...',
                                          style: TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontStyle: FontStyle.italic),
                                        ),
                                      ),
                                    ],
                                  )
                                else if (_emergencyLocation != null) ...[
                                  Text(
                                    'GPS: ${(_emergencyLocation!['latitude'] as double?)?.toStringAsFixed(5)}, ${(_emergencyLocation!['longitude'] as double?)?.toStringAsFixed(5)} (±${(_emergencyLocation!['accuracy'] as num?)?.round() ?? 0}m)',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if ((_emergencyLocation!['road'] as String?)?.isNotEmpty == true ||
                                      (_emergencyLocation!['displayName'] as String?)?.isNotEmpty == true)
                                    Text(
                                      'Near: ${_emergencyLocation!['road']?.isNotEmpty == true ? _emergencyLocation!['road'] : _emergencyLocation!['displayName']}${_emergencyLocation!['suburb']?.isNotEmpty == true ? ', ${_emergencyLocation!['suburb']}' : ''}',
                                      style: const TextStyle(fontSize: 15, color: AppTheme.accentYellow, fontWeight: FontWeight.w600),
                                    ),
                                ] else
                                  const Text(
                                    'GPS coordinates pending. Tap below to acquire location.',
                                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                  ),
                                const Divider(height: 24, color: AppTheme.danger),
                                Row(
                                  children: [
                                    const Icon(Icons.contact_phone, color: AppTheme.danger, size: 22),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Emergency Contact',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Primary Number: ${widget.storageService?.emergencyContact ?? "112"}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Always dial local emergency services (112 / 911) directly in an immediate crisis.',
                                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.icon == Icons.search) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.accentCyan, width: 1.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.bookmark, color: AppTheme.accentCyan, size: 24),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Registered Items (${widget.storageService?.savedItems.length ?? 0})',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.accentCyan,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (widget.storageService != null && widget.storageService!.savedItems.isNotEmpty)
                                  ...widget.storageService!.savedItems.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle_outline, size: 18, color: AppTheme.success),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${item['name']} — ${item['notes'] ?? ''}',
                                              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  const Text(
                                    'No saved items yet. Say "Save item [name]" to register your cane, keys, or bag.',
                                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.icon == Icons.emergency) ...[
                  AccessibleButton(
                    label: _isLoadingGps ? 'Acquiring GPS Fix...' : 'Announce Emergency GPS Location',
                    icon: Icons.my_location,
                    isDestructive: true,
                    semanticHint: 'Retrieves device GPS and announces your location aloud',
                    onPressed: _isLoadingGps ? null : _triggerEmergencyBroadcast,
                  ),
                  const SizedBox(height: 12),
                  AccessibleButton(
                    label: 'Call Emergency (${widget.storageService?.emergencyContact ?? "112"})',
                    icon: Icons.phone_in_talk,
                    isDestructive: true,
                    semanticHint: 'Calls primary emergency number',
                    onPressed: () async {
                      final contact = widget.storageService?.emergencyContact ?? '112';
                      final isKn = widget.ttsService.isKannada;
                      await widget.ttsService.speak(
                        isKn
                            ? 'ತುರ್ತು ಸಂಪರ್ಕ $contact ಗೆ ಕರೆ ಮಾಡಲಾಗುತ್ತಿದೆ. ದಯವಿಟ್ಟು ಫೋನ್ ಡಯಲರ್ ಪರಿಶೀಲಿಸಿ.'
                            : 'Dialing emergency contact $contact. Please confirm in your device phone dialer.',
                      );
                      Clipboard.setData(ClipboardData(text: contact));
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.icon == Icons.search) ...[
                  AccessibleButton(
                    label: 'List Saved Items Aloud',
                    icon: Icons.inventory_2,
                    semanticHint: 'Speaks the list of all registered items',
                    onPressed: () {
                      final items = widget.storageService?.savedItems ?? [];
                      if (items.isEmpty) {
                        widget.ttsService.speak('You have no registered items yet. Say Save item followed by the name to add one.');
                      } else {
                        final names = items.map((e) => e['name'] ?? '').join(', ');
                        widget.ttsService.speak('You have ${items.length} saved items: $names.');
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_resolvedAction != null) ...[
                  AccessibleButton(
                    label: _getActionLaunchLabel(_resolvedAction!, widget.ttsService.isKannada),
                    icon: _getActionLaunchIcon(_resolvedAction!),
                    isPrimary: true,
                    semanticHint: 'Activates this feature immediately',
                    onPressed: _launchFeatureNow,
                  ),
                  const SizedBox(height: 12),
                ],
                AccessibleButton(
                  label: widget.ttsService.isKannada ? 'ವಿವರಗಳನ್ನು ಮತ್ತೆ ಹೇಳಿ' : 'Repeat Spoken Details',
                  icon: Icons.replay,
                  semanticHint: 'Speaks the feature explanation and status again',
                  onPressed: () {
                    widget.ttsService.speak(
                      '${widget.title}. Status: ${widget.status}. ${widget.explanation}',
                    );
                  },
                ),
                const SizedBox(height: 12),
                AccessibleButton(
                  label: widget.ttsService.isKannada ? 'ಮನೆ ಪರದೆಗೆ ಹಿಂದೆ' : 'Back to Home',
                  icon: Icons.arrow_back,
                  isPrimary: _resolvedAction == null,
                  semanticHint: 'Returns to main screen',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
