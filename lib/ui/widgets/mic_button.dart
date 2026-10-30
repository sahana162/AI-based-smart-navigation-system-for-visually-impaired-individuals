import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';

class MicButton extends StatefulWidget {
  final bool isListening;
  final VoidCallback onTap;
  final String assistantName;
  final AppLanguage? language;

  const MicButton({
    super.key,
    required this.isListening,
    required this.onTap,
    required this.assistantName,
    this.language,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _animController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _animController.stop();
      _animController.reset();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isListening = widget.isListening;
    final isKannada = widget.language == AppLanguage.kn;

    final semanticLabel = isKannada
        ? (isListening
            ? 'ಮೈಕ್ರೊಫೋನ್ ಸಕ್ರಿಯವಾಗಿದೆ. ${widget.assistantName} ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದಾರೆ. ನಿಲ್ಲಿಸಲು ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ.'
            : 'ಮಾತನಾಡಲು ಟ್ಯಾಪ್ ಮಾಡಿ. ${widget.assistantName} ಜೊತೆ ಮಾತನಾಡಿ. ಮೈಕ್ರೊಫೋನ್ ಸಕ್ರಿಯಗೊಳಿಸಲು ಡಬಲ್ ಟ್ಯಾಪ್ ಮಾಡಿ.')
        : (isListening
            ? 'Microphone active. ${widget.assistantName} is listening. Double tap to stop.'
            : 'Tap to speak. Talk to ${widget.assistantName}. Double tap to activate microphone.');

    final semanticHint = isKannada
        ? (isListening
            ? 'ಧ್ವನಿ ಗುರುತಿಸುವಿಕೆಯನ್ನು ನಿಲ್ಲಿಸುತ್ತದೆ.'
            : 'ನ್ಯಾವಿಗೇಷನ್ ಪ್ರಾರಂಭಿಸಿ, ವಿವರಣೆ ನೀಡಿ, ಅಥವಾ ಸಹಾಯ ಆಜ್ಞೆಗಳಿಗಾಗಿ ಕೇಳಲು ಪ್ರಾರಂಭಿಸುತ್ತದೆ.')
        : (isListening
            ? 'Stops voice recognition.'
            : 'Starts listening for voice commands like Start navigation, Describe surroundings, or Help.');

    final labelText = isKannada
        ? (isListening
            ? 'ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದ್ದೇನೆ... (ನಿಲ್ಲಿಸಿ)'
            : '${widget.assistantName} ಜೊತೆ ಮಾತನಾಡಿ')
        : (isListening
            ? 'Listening... (Tap to stop)'
            : 'Tap to Talk to ${widget.assistantName}');

    final Color bgColor = isListening ? AppTheme.danger : AppTheme.accentCyan;
    final Color textColor = Colors.black;

    return Semantics(
      button: true,
      label: semanticLabel,
      hint: semanticHint,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final scale = isListening ? _scaleAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onTap();
                },
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: bgColor.withValues(alpha: isListening ? 0.6 : 0.3),
                        blurRadius: isListening ? 20 : 10,
                        spreadRadius: isListening ? 4 : 1,
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white,
                      width: 2.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isListening ? Icons.mic : Icons.mic_none,
                        size: 36,
                        color: textColor,
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          labelText,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
