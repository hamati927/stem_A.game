"""
実運用向け実装ガイド（Flutter + MoveNet / MediaPipe）

このファイルは Flutter プロジェクトに組み込む際の詳細な実装例と手順をまとめたドキュメントです。
主な項目：
  - カメラフレームの変換（YUV -> RGB -> リサイズ）
  - Isolate を使った推論（モデルは Isolate 内でロード）
  - UI 描画（スケルトンオーバーレイ、判定表示）
  - MediaPipe をネイティブで使う場合の統合手順（Android/iOS）

設計方針（要点）:
  - リアルタイム性重視：推論はメインスレッドから切り離す
  - 低遅延化：モデル量子化、入力サイズ調整（例 192x192）、フレームスキップ戦略
  - ユーザ安全性：簡潔なフィードバックと中止ボタン

---
1) 必要な pubspec 依存（例）

dependencies:
  flutter:
    sdk: flutter
  camera: ^0.10.0
  tflite_flutter: ^0.11.0
  tflite_flutter_helper: ^0.3.0
  image: ^4.0.21      # 画像処理（オプション）
  provider: ^6.0.5
  just_audio: ^0.9.20

dev_dependencies:
  flutter_test:
    sdk: flutter

---
2) カメラフレームの前処理（YUV420 -> RGB -> リサイズ）

ポイント：CameraImage はプラットフォーム固有で YUV420 形式の場合が多い。
MoveNet の入力は正方形（例 192x192）で RGB の float32 / uint8 など。

Dart の概念コード（変換関数の例）:

```dart
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

// YUV420 -> RGB への変換（簡易版）
img.Image convertYUV420ToImage(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;
  final uvRowStride = cameraImage.planes[1].bytesPerRow;
  final uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

  final image = img.Image(width, height);

  for (int y = 0; y < height; y++) {
    final int uvRow = (y / 2).floor();
    for (int x = 0; x < width; x++) {
      final int uvCol = (x / 2).floor();
      final int indexY = y * cameraImage.planes[0].bytesPerRow + x;
      final int indexU = uvRow * uvRowStride + uvCol * uvPixelStride;
      final int indexV = uvRow * cameraImage.planes[2].bytesPerRow + uvCol * uvPixelStride;

      final yVal = cameraImage.planes[0].bytes[indexY];
      final uVal = cameraImage.planes[1].bytes[indexU];
      final vVal = cameraImage.planes[2].bytes[indexV];

      // YUV -> RGB
      int r = (yVal + (1.370705 * (vVal - 128))).round();
      int g = (yVal - (0.337633 * (uVal - 128)) - (0.698001 * (vVal - 128))).round();
      int b = (yVal + (1.732446 * (uVal - 128))).round();

      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      image.setPixelRgba(x, y, r, g, b);
    }
  }
  return image;
}

// リサイズして Float32List に変換
Float32List imageToInputTensor(img.Image src, int inputSize) {
  final resized = img.copyResize(src, width: inputSize, height: inputSize);
  final input = Float32List(inputSize * inputSize * 3);
  int idx = 0;
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final p = resized.getPixel(x, y);
      input[idx++] = (img.getRed(p) / 255.0);
      input[idx++] = (img.getGreen(p) / 255.0);
      input[idx++] = (img.getBlue(p) / 255.0);
    }
  }
  return input;
}
```

注意：変換はコストが高いので Isolate（別スレッド）で行う、またはネイティブで最適化することを推奨します。

---
3) Isolate を使った推論パターン（設計）

- メインスレッド：カメラフレーム受信 -> 必要最小限の前処理（または生データのまま） -> TransferableTypedData で Isolate に送信
- Isolate：Interpreter をロード（Isolate ごとにモデルはロード） -> 推論 -> keypoints を返す

ポイント：tflite インタプリタは Isolate 内で生成する（インタプリタのインスタンスはスレッドセーフでないことが多い）。

概念コード（Isolate 用 Worker）:

```dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

class InferenceRequest {
  final TransferableTypedData imageData;
  final SendPort replyPort;
  InferenceRequest(this.imageData, this.replyPort);
}

void inferenceIsolateEntry(InferenceRequest req) async {
  final interpreter = await Interpreter.fromAsset('movenet.tflite');
  final inputSize = 192; // モデルに依存

  final data = req.imageData.materialize().asUint8List();
  // data から Float32List を作る/前処理（省略）

  // 入力テンソル作成
  var input = Float32List(inputSize * inputSize * 3);

  // 実行
  final output = List.filled(1 * 17 * 3, 0.0); // 例: [1,17,3]
  interpreter.run(input, output);

  // postprocess: keypoints に変換
  final keypoints = parseOutput(output);

  req.replyPort.send(keypoints);
  interpreter.close();
}
```

メイン側では Isolate を spawn して SendPort を保存しておき、フレームごとに TransferableTypedData で送る。

---
4) Postprocess と座標のマッピング

- MoveNet は正規化された座標（0..1）を返す。オーバーレイ描画時には画面座標にマッピングする。
- カメラの向き（前面/背面）や回転（端末の向き）を考慮して補正する。

例：画面上の x = normalizedX * previewWidth, y = normalizedY * previewHeight

---
5) UI オーバーレイ（CustomPainter）

- CustomPainter を使って keypoints（円）と骨格線（線）を描画。
- 判定結果（Perfect/Great/Good）は大きく中央に表示、及び小さなエフェクト（色・スコア）を表示。

Dart の概念コード（Painter）:

```dart
import 'package:flutter/material.dart';

class PosePainter extends CustomPainter {
  final List<Keypoint> keypoints; // Keypoint {x,y,score}
  final String? judgment; // 'Perfect' etc
  PosePainter({required this.keypoints, this.judgment});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    // draw skeleton lines (example index pairs)
    final pairs = [ [5,7], [7,9], [6,8], [8,10], [5,6], [11,12] ];
    for (var p in pairs) {
      final a = keypoints[p[0]];
      final b = keypoints[p[1]];
      if (a.score > 0.3 && b.score > 0.3) {
        canvas.drawLine(Offset(a.x*size.width, a.y*size.height), Offset(b.x*size.width, b.y*size.height), paint);
      }
    }

    // draw keypoints
    for (var k in keypoints) {
      if (k.score > 0.3) {
        canvas.drawCircle(Offset(k.x*size.width, k.y*size.height), 6.0, Paint()..color=Colors.blue);
      }
    }

    // judgment
    if (judgment != null) {
      final textPainter = TextPainter(
        text: TextSpan(text: judgment, style: TextStyle(fontSize: 48, color: Colors.white, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset((size.width-textPainter.width)/2, size.height*0.1));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
```

---
6) 判定アルゴリズム（実装のポイント）

- 見本（reference）ポーズはタイムスタンプ付きのキーフレームで保存
- ユーザの成功は「時間窓内に角度誤差が閾値以下」であること
- 具体的手順：
  1. 正規化 → 角度算出（例：膝角 = angle(hip, knee, ankle)）
  2. 各キーフレーム毎に角度差の平均を計算
  3. 類似度閾値以下かつ最初の成功時間 t_user を検出
  4. Δt = t_user - t_ref により Perfect/Great/Good を決定

- 早さや遅れに柔軟に対応するには DTW を組み込む

簡易 DART 判定スニペット（擬似）:

```dart
String judge(double dtSeconds, double angleDiff, double thresh) {
  if (angleDiff > thresh) return 'Miss';
  if (dtSeconds.abs() <= 2.0) return 'Perfect';
  if (dtSeconds.abs() <= 4.0) return 'Great';
  if (dtSeconds.abs() <= 6.0) return 'Good';
  return 'Miss';
}
```

---
7) MediaPipe をネイティブで使う場合の高レベル手順

目的：MediaPipe の高度な追跡や 3D 推定が必要なケースでネイティブで処理し、Flutter と PlatformChannel で連携する。

Android（Kotlin）:
 1. MediaPipe Android ソリューションをプロジェクトに追加（公式 repo を参照）。
 2. Pose ライブラリを組み込み、CameraX でフレームを受け取る。
 3. 推論結果（ランドマーク）を JSON などでシリアライズして Flutter 側へ送る。
 4. Flutter とネイティブは MethodChannel で通信（例: "pose#start", "pose#stop", "pose#events"）。

iOS（Swift）:
 1. CocoaPods / SPM 経由で MediaPipe を組み込む（公式手順参照）。
 2. AVFoundation でカメラ取得 -> MediaPipe Pose パイプラインへ入力。
 3. ランドマークをシリアライズして Flutter へ送る（MethodChannel）。

注意点:
- ネイティブで処理すると高精度（3Dや連続トラッキング）が得られるが、ビルドやメンテナンスコストが上がる。
- 標準的な選択はまず TFLite (MoveNet) の Flutter 直接実装、必要ならネイティブ MediaPipe に切り替える戦略が現実的。

---
8) 性能・バッテリー最適化のヒント
- 入力解像度を下げる（例 192x192）
- モデル量子化（int8）で推論高速化
- フレームレート制御（例 15-20 FPS）またはフレームスキップ
- GPU delegate の活用（可能な場合）
- プロファイリングツールでメモリと CPU を観察

---
9) テストと閾値チューニング
- 高齢者や初心者を含むユーザーテストで閾値（角度、時間窓）を実地調整
- ログを取って角度分布・判定の真偽率を可視化

---
最後に：このドキュメントを `lib/` に入れる際は、実用コードを小さなコンポーネント（camera_handler.dart, pose_detector.dart, pose_painter.dart, judge.dart）に分割してテストしやすくしてください。

"""
