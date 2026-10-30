import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Full-bleed HUD camera viewfinder with curved corner targeting brackets.
/// Provides high-contrast spatial framing for visually impaired and low-vision users.
class ViewfinderReticle extends StatelessWidget {
  final Color cornerColor;
  final double cornerLength;
  final double cornerThickness;
  final double borderRadius;
  final Widget? child;

  const ViewfinderReticle({
    super.key,
    this.cornerColor = AppTheme.accentCyan,
    this.cornerLength = 38.0,
    this.cornerThickness = 3.5,
    this.borderRadius = 16.0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ?child,
        // Custom painted HUD corner brackets
        IgnorePointer(
          child: CustomPaint(
            painter: _CornerBracketPainter(
              color: cornerColor,
              length: cornerLength,
              thickness: cornerThickness,
              radius: borderRadius,
            ),
          ),
        ),
      ],
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color color;
  final double length;
  final double thickness;
  final double radius;

  _CornerBracketPainter({
    required this.color,
    required this.length,
    required this.thickness,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = thickness * 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    const margin = 20.0;
    final w = size.width;
    final h = size.height;

    // Helper to draw bracket
    void drawBracket(Path path) {
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, paint);
    }

    // Top-Left
    final tl = Path()
      ..moveTo(margin, margin + length)
      ..lineTo(margin, margin + radius)
      ..quadraticBezierTo(margin, margin, margin + radius, margin)
      ..lineTo(margin + length, margin);
    drawBracket(tl);

    // Top-Right
    final tr = Path()
      ..moveTo(w - margin - length, margin)
      ..lineTo(w - margin - radius, margin)
      ..quadraticBezierTo(w - margin, margin, w - margin, margin + radius)
      ..lineTo(w - margin, margin + length);
    drawBracket(tr);

    // Bottom-Left
    final bl = Path()
      ..moveTo(margin, h - margin - length)
      ..lineTo(margin, h - margin - radius)
      ..quadraticBezierTo(margin, h - margin, margin + radius, h - margin)
      ..lineTo(margin + length, h - margin);
    drawBracket(bl);

    // Bottom-Right
    final br = Path()
      ..moveTo(w - margin - length, h - margin)
      ..lineTo(w - margin - radius, h - margin)
      ..quadraticBezierTo(w - margin, h - margin, w - margin, h - margin - radius)
      ..lineTo(w - margin, h - margin - length);
    drawBracket(br);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.length != length ||
        oldDelegate.thickness != thickness;
  }
}
