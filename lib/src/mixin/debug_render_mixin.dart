import 'package:flutter/material.dart';

/// A mixin that adds debug outline rendering capabilities to a class.
mixin DebugRenderMixin {
  void renderBoundingBox(Canvas canvas, Rect renderArea) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(renderArea, paint);
  }
}
