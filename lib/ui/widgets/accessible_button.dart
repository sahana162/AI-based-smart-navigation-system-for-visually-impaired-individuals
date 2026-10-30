import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

class AccessibleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final String? semanticLabel;
  final String? semanticHint;
  final double minHeight;
  final bool isPrimary;
  final bool isDestructive;

  const AccessibleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.semanticLabel,
    this.semanticHint,
    this.minHeight = 56.0,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    if (isDestructive) {
      bg = AppTheme.danger;
      fg = Colors.black;
    } else if (isPrimary) {
      bg = AppTheme.primary;
      fg = AppTheme.onPrimary;
    } else {
      bg = backgroundColor ?? AppTheme.surface;
      fg = textColor ?? AppTheme.textPrimary;
    }

    final effectiveSemanticLabel = semanticLabel ?? label;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: effectiveSemanticLabel,
      hint: semanticHint,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minHeight,
          minWidth: 48.0,
        ),
        child: Material(
          color: onPressed != null ? bg : bg.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    onPressed!();
                  },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPrimary
                      ? Colors.transparent
                      : (isDestructive ? Colors.transparent : AppTheme.border),
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 28, color: fg),
                    const SizedBox(width: 12),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: fg,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
