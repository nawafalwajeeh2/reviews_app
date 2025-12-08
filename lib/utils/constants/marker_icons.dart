import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:reviews_app/utils/constants/colors.dart';
import '../../features/review/models/place_model.dart';
import '../../features/review/models/category_mapper.dart';

class CustomMarkerGenerator {
  /// Creates a beautiful 3D circular badge marker with category icon
  static Future<BitmapDescriptor> createPlaceMarker({
    required String title,
    required double rating,
    required bool isSelected,
    String? categoryId,
  }) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    // Increased badge dimensions for better visibility
    final double badgeSize = isSelected ? 95.0 : 75.0;
    final double totalHeight = badgeSize + 60;

    // Get category icon using the helper method
    final IconData categoryIcon = _getCategoryIcon(categoryId);

    // Draw beautiful shadow with depth
    _draw3DShadow(canvas, badgeSize, isSelected);

    // Draw main circular badge with 3D effect
    _draw3DCircularBadge(canvas, badgeSize, rating, isSelected);

    // Draw category icon at the top
    await _drawCategoryIcon(canvas, badgeSize, categoryIcon, isSelected);

    // Draw rating below the icon
    _drawRatingWithStar(canvas, badgeSize, rating, isSelected);

    // Draw smooth pointer
    _drawSmoothPointer(canvas, badgeSize, rating, isSelected);

    // Draw premium floating label
    _drawFloatingLabel(canvas, title, badgeSize, totalHeight, isSelected);

    // Convert to image
    final image = await pictureRecorder.endRecording().toImage(
      (badgeSize + 30).toInt(),
      totalHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    // return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  static void _draw3DShadow(Canvas canvas, double size, bool isSelected) {
    final centerX = size / 2 + 15;
    final centerY = size / 2 + 15;
    final radius = size * 0.45;

    // Multi-layer shadow for realistic 3D depth
    final shadows = [
      {'offset': Offset(0, 8), 'blur': 20.0, 'alpha': 0.25},
      {'offset': Offset(0, 4), 'blur': 12.0, 'alpha': 0.18},
      {'offset': Offset(0, 2), 'blur': 6.0, 'alpha': 0.12},
    ];

    for (var shadow in shadows) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: shadow['alpha']! as double)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          shadow['blur']! as double,
        );

      canvas.drawCircle(
        Offset(centerX, centerY) + (shadow['offset']! as Offset),
        radius,
        shadowPaint,
      );
    }
  }

  static void _draw3DCircularBadge(
    Canvas canvas,
    double size,
    double rating,
    bool isSelected,
  ) {
    final centerX = size / 2 + 15;
    final centerY = size / 2 + 15;
    final radius = size * 0.45;
    final color = _getRatingColor(rating);

    // Outer glow ring for selected state
    if (isSelected) {
      final glowRings = [
        {'radius': radius + 16, 'alpha': 0.12},
        {'radius': radius + 10, 'alpha': 0.18},
        {'radius': radius + 5, 'alpha': 0.25},
      ];

      for (var ring in glowRings) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: ring['alpha']!)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);

        canvas.drawCircle(Offset(centerX, centerY), ring['radius']!, glowPaint);
      }
    }

    // Main circle with radial gradient for 3D effect
    final gradient = RadialGradient(
      center: Alignment(-0.3, -0.4),
      radius: 1.2,
      colors: [
        color.withValues(alpha: 1.0),
        color.withValues(alpha: 0.95),
        color.withValues(alpha: 0.88),
      ],
      stops: [0.0, 0.6, 1.0],
    );

    final rect = Rect.fromCircle(
      center: Offset(centerX, centerY),
      radius: radius,
    );

    final circlePaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, centerY), radius, circlePaint);

    // Glossy highlight for 3D depth
    final highlightGradient = RadialGradient(
      center: Alignment(-0.4, -0.5),
      radius: 0.8,
      colors: [
        Colors.white.withValues(alpha: 0.4),
        Colors.white.withValues(alpha: 0.2),
        Colors.white.withValues(alpha: 0.0),
      ],
    );

    final highlightPaint = Paint()
      ..shader = highlightGradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, centerY), radius, highlightPaint);

    // Inner shadow for depth
    final innerShadowGradient = RadialGradient(
      center: Alignment(0.5, 0.6),
      radius: 1.0,
      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.08)],
    );

    final innerShadowPaint = Paint()
      ..shader = innerShadowGradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, centerY), radius, innerShadowPaint);

    // White border with subtle shadow
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 4.0 : 3.0;

    canvas.drawCircle(Offset(centerX, centerY), radius, borderPaint);

    // Inner subtle border for extra depth
    final innerBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(Offset(centerX, centerY), radius - 4, innerBorderPaint);
  }

  static Future<void> _drawCategoryIcon(
    Canvas canvas,
    double size,
    IconData icon,
    bool isSelected,
  ) async {
    final centerX = size / 2 + 15;
    final centerY = size / 2 + 15;
    final iconSize = isSelected ? 24.0 : 20.0;

    // Create icon painter
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        centerX - textPainter.width / 2,
        centerY - textPainter.height / 2 - (isSelected ? 10 : 8),
      ),
    );
  }

  static void _drawRatingWithStar(
    Canvas canvas,
    double size,
    double rating,
    bool isSelected,
  ) {
    final centerX = size / 2 + 15;
    final centerY = size / 2 + 15;

    // Rating number
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.text = TextSpan(
      text: rating.toStringAsFixed(1),
      style: TextStyle(
        fontSize: isSelected ? 16.0 : 13.5,
        fontWeight: FontWeight.w900,
        color: Colors.white,
        letterSpacing: -0.5,
        height: 1.0,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        centerX - textPainter.width / 2,
        centerY - textPainter.height / 2 + (isSelected ? 6 : 5),
      ),
    );

    // Small star icon
    _drawPerfectStar(
      canvas,
      Offset(
        centerX,
        centerY + textPainter.height / 2 + (isSelected ? 11 : 10),
      ),
      isSelected ? 7.0 : 6.0,
      Colors.white,
    );
  }

  static void _drawPerfectStar(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    final path = Path();
    const points = 5;
    final angle = (math.pi * 2) / points;

    for (int i = 0; i < points * 2; i++) {
      final radius = i.isEven ? size : size * 0.4;
      final x = center.dx + radius * math.cos(i * angle / 2 - math.pi / 2);
      final y = center.dy + radius * math.sin(i * angle / 2 - math.pi / 2);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path.shift(Offset(0, 1)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  static void _drawSmoothPointer(
    Canvas canvas,
    double size,
    double rating,
    bool isSelected,
  ) {
    final centerX = size / 2 + 15;
    final bottomY = size + 15;
    final pointerHeight = isSelected ? 14.0 : 12.0;
    final color = _getRatingColor(rating);

    // Pointer shadow
    final shadowPath = Path()
      ..moveTo(centerX - 10, bottomY)
      ..quadraticBezierTo(
        centerX,
        bottomY + pointerHeight + 2,
        centerX,
        bottomY + pointerHeight + 2,
      )
      ..quadraticBezierTo(
        centerX,
        bottomY + pointerHeight + 2,
        centerX + 10,
        bottomY,
      )
      ..close();

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawPath(shadowPath.shift(Offset(0, 2)), shadowPaint);

    // Main pointer with smooth curves
    final pointerPath = Path()
      ..moveTo(centerX - 10, bottomY)
      ..quadraticBezierTo(
        centerX,
        bottomY + pointerHeight,
        centerX,
        bottomY + pointerHeight,
      )
      ..quadraticBezierTo(
        centerX,
        bottomY + pointerHeight,
        centerX + 10,
        bottomY,
      )
      ..close();

    final pointerGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color, color.withValues(alpha: 0.9)],
    );

    final pointerPaint = Paint()
      ..shader = pointerGradient.createShader(pointerPath.getBounds());

    canvas.drawPath(pointerPath, pointerPaint);

    // Pointer border
    final pointerBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawPath(pointerPath, pointerBorder);
  }

  static void _drawFloatingLabel(
    Canvas canvas,
    String title,
    double badgeSize,
    double totalHeight,
    bool isSelected,
  ) {
    final centerX = badgeSize / 2 + 15;
    final labelY = badgeSize + 24;
    final labelHeight = isSelected ? 28.0 : 24.0;
    final maxWidth = badgeSize + 60;

    // Label container
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX, labelY + labelHeight / 2),
        width: maxWidth,
        height: labelHeight,
      ),
      Radius.circular(labelHeight / 2),
    );

    // Elegant shadow layers
    final shadowLayers = [
      {'offset': 5.0, 'blur': 12.0, 'alpha': 0.18},
      {'offset': 2.0, 'blur': 6.0, 'alpha': 0.12},
    ];

    for (var shadow in shadowLayers) {
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: shadow['alpha']!)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadow['blur']!);

      canvas.drawRRect(
        labelRect.shift(Offset(0, shadow['offset']!)),
        shadowPaint,
      );
    }

    // Label gradient
    final labelGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, Color(0xFFFCFCFC)],
    );

    final labelPaint = Paint()
      ..shader = labelGradient.createShader(labelRect.outerRect);

    canvas.drawRRect(labelRect, labelPaint);

    // Subtle border
    final labelBorder = Paint()
      ..color = Color(0xFFE5E5E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(labelRect, labelBorder);

    // Place name
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    );

    final truncatedTitle = _truncateText(title, isSelected ? 20 : 16);

    textPainter.text = TextSpan(
      text: truncatedTitle,
      style: TextStyle(
        fontSize: isSelected ? 12.5 : 11.0,
        fontWeight: FontWeight.w700,
        color: Color(0xFF2C2C2C),
        letterSpacing: -0.2,
      ),
    );

    textPainter.layout(maxWidth: maxWidth - 24);
    textPainter.paint(
      canvas,
      Offset(
        centerX - textPainter.width / 2,
        labelY + (labelHeight - textPainter.height) / 2,
      ),
    );
  }

  static Color _getRatingColor(double rating) {
    if (rating >= 4.5) {
      return Color(0xFF10B981); // Emerald
    } else if (rating >= 4.0) {
      return Color(0xFF22C55E); // Green
    } else if (rating >= 3.5) {
      return Color(0xFF84CC16); // Lime
    } else if (rating >= 3.0) {
      return Color(0xFFF59E0B); // Amber
    } else if (rating >= 2.5) {
      return Color(0xFFF97316); // Orange
    } else if (rating >= 2.0) {
      return Color(0xFFEF4444); // Red
    } else {
      return Color(0xFFDC2626); // Dark Red
    }
  }

  static String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 1)}…';
  }

  /// Helper method to get category icon from categoryId
  static IconData _getCategoryIcon(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      return Icons.place_rounded;
    }

    try {
      // Find the category by ID from allMockCategories
      final category = allMockCategories.firstWhere(
        (cat) => cat.id == categoryId,
        orElse: () => throw Exception('Category not found'),
      );

      // Use the iconKey to get the actual icon
      return CategoryMapper.getIcon(category.iconKey);
    } catch (e) {
      // Fallback to default icon if category not found
      return Icons.place_rounded;
    }
  }

  static Future<BitmapDescriptor> generatePlaceMarker(
    PlaceModel place, {
    bool isSelected = false,
  }) async {
    return createPlaceMarker(
      title: place.title,
      rating: place.averageRating,
      isSelected: isSelected,
      categoryId: place.categoryId,
    );
  }

  static Future<BitmapDescriptor> getCurrentLocationMarker() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Size size = Size(80.0, 80.0);

    // Soft pulse rings
    final pulseRings = [
      {'radius': 38.0, 'alpha': 0.08},
      {'radius': 28.0, 'alpha': 0.15},
      {'radius': 20.0, 'alpha': 0.22},
    ];

    for (var ring in pulseRings) {
      final pulsePaint = Paint()
        ..color = AppColors.primaryColor.withValues(alpha: ring['alpha']!)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        ring['radius']!,
        pulsePaint,
      );
    }

    // Main circle with 3D effect
    final mainGradient = RadialGradient(
      center: Alignment(-0.3, -0.3),
      radius: 1.0,
      colors: [
        AppColors.primaryColor,
        AppColors.primaryColor.withValues(alpha: 0.95),
      ],
    );

    final mainRect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: 15.0,
    );

    final mainPaint = Paint()..shader = mainGradient.createShader(mainRect);

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 15.0, mainPaint);

    // White ring
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 15.0, ringPaint);

    // Center dot
    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      6.0,
      centerPaint,
    );

    final image = await pictureRecorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    // return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  static Future<BitmapDescriptor> getSelectedLocationMarker() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Size size = Size(80.0, 100.0);

    final centerX = size.width / 2;
    final centerY = size.height * 0.3;
    final radius = size.width * 0.35;

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0);

    canvas.drawCircle(Offset(centerX + 2, centerY + 2), radius, shadowPaint);

    // Main circle with gradient
    final circleGradient = RadialGradient(
      center: Alignment(-0.3, -0.3),
      radius: 1.0,
      colors: [
        AppColors.primaryColor,
        AppColors.primaryColor.withValues(alpha: 0.9),
      ],
    );

    final circlePaint = Paint()
      ..shader = circleGradient.createShader(
        Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      );

    canvas.drawCircle(Offset(centerX, centerY), radius, circlePaint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    canvas.drawCircle(Offset(centerX, centerY), radius, borderPaint);

    // Pointer
    final pointerPath = Path()
      ..moveTo(centerX - 8, centerY + radius - 2)
      ..quadraticBezierTo(centerX, size.height - 10, centerX, size.height - 10)
      ..quadraticBezierTo(
        centerX,
        size.height - 10,
        centerX + 8,
        centerY + radius - 2,
      )
      ..close();

    canvas.drawPath(pointerPath, Paint()..color = AppColors.primaryColor);
    canvas.drawPath(pointerPath, borderPaint);

    // Inner circle
    final innerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(centerX, centerY), radius * 0.5, innerPaint);

    // Center dot
    final dotPaint = Paint()..color = AppColors.primaryColor;
    canvas.drawCircle(Offset(centerX, centerY), radius * 0.25, dotPaint);

    final image = await pictureRecorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    // return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }
}
