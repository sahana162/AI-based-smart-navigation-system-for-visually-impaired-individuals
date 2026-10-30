import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Glowing 5-bar live audio waveform visualizer for assistive feedback.
/// Oscillates dynamically when voice recognition or speech synthesis is active.
class LiveWaveformVisualizer extends StatefulWidget {
  final bool isActive;
  final Color? barColor;
  final double height;
  final double width;

  const LiveWaveformVisualizer({
    super.key,
    required this.isActive,
    this.barColor,
    this.height = 36.0,
    this.width = 72.0,
  });

  @override
  State<LiveWaveformVisualizer> createState() => _LiveWaveformVisualizerState();
}

class _LiveWaveformVisualizerState extends State<LiveWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isActive) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LiveWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _animController.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
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
    final effectiveColor = widget.barColor ?? AppTheme.accentCyan;

    return Semantics(
      label: widget.isActive ? 'Audio visualizer active' : 'Audio visualizer idle',
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(5, (index) {
                // Staggered sine phase for each bar
                final phase = (index * 0.4) + (_animController.value * 2 * math.pi);
                final wave = widget.isActive ? (math.sin(phase).abs() * 0.75 + 0.25) : 0.2;
                final barHeight = (widget.height * wave).clamp(4.0, widget.height);

                return Container(
                  width: 4.5,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: effectiveColor,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: widget.isActive
                        ? [
                            BoxShadow(
                              color: effectiveColor.withValues(alpha: 0.6),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
