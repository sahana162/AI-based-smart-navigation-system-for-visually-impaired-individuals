import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

class FeatureCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isAvailable;
  final VoidCallback onTap;
  final String? availabilityText;

  const FeatureCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.isAvailable,
    required this.onTap,
    this.availabilityText,
  });

  @override
  Widget build(BuildContext context) {
    final status = availabilityText ?? (isAvailable ? 'Available' : 'Coming Soon');
    final semanticLabel = '$title. Status: $status. $description';
    final semanticHint = isAvailable
        ? 'Double tap to open $title.'
        : 'Double tap to hear details about this upcoming feature.';

    return Semantics(
      button: true,
      label: semanticLabel,
      hint: semanticHint,
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isAvailable ? AppTheme.accentCyan : AppTheme.border,
                width: isAvailable ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? AppTheme.accentCyan.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 30,
                    color: isAvailable ? AppTheme.accentCyan : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isAvailable
                                  ? AppTheme.success.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isAvailable
                                    ? AppTheme.success
                                    : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
