// pose_painter.dart
// CustomPainter を用いたスケルトン描画と判定表示

import 'package:flutter/material.dart';

class Keypoint {
  final double x, y;
  final double score;
  Keypoint(this.x, this.y, this.score);
}

class PosePainter extends CustomPainter {
  final List<Keypoint> keypoints;
  final String? judgment;

  PosePainter({required this.keypoints, this.judgment});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // example skeleton pairs for 17-keypoint model
    final pairs = const [
      [5,7],[7,9],[6,8],[8,10],[5,6],[11,12],[11,13],[13,15],[12,14],[14,16]
    ];

    for (var p in pairs) {
      // index bounds check to avoid RangeError when keypoints list is shorter than expected
      final int i = p[0];
      final int j = p[1];
      if (i < 0 || j < 0) continue;
      if (i >= keypoints.length || j >= keypoints.length) continue;

      final a = keypoints[i];
      final b = keypoints[j];
      if (a.score > 0.2 && b.score > 0.2) {
        canvas.drawLine(
          Offset(a.x * size.width, a.y * size.height),
          Offset(b.x * size.width, b.y * size.height),
          paint,
        );
      }
    }

    for (var k in keypoints) {
      if (k.score > 0.2) {
        canvas.drawCircle(Offset(k.x*size.width, k.y*size.height), 5.0, Paint()..color = Colors.blueAccent);
      }
    }

    if (judgment != null) {
      final textStyle = TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius:4.0, color:Colors.black45, offset: Offset(2,2))]);
      final textSpan = TextSpan(text: judgment!, style: textStyle);
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset((size.width - tp.width)/2, size.height * 0.08));
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    // Repaint if judgment text changed
    if (oldDelegate.judgment != judgment) return true;
    // Repaint if number of keypoints changed
    if (oldDelegate.keypoints.length != keypoints.length) return true;
    // Repaint if any keypoint changed
    for (var i = 0; i < keypoints.length; i++) {
      final a = keypoints[i];
      final b = oldDelegate.keypoints[i];
      if (a.x != b.x || a.y != b.y || a.score != b.score) return true;
    }
    return false;
  }
}
