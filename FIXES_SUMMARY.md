# lib内プログラミングの修正内容

## 概要
rhythm_game/lib内の3つのDartファイルにおける問題を修正しました。

---

## 1. camera_handler.dart

### 問題
- `startImageStream` コールバック内で `async` キーワードが使用されているが、戻り値を待たずに次フレームに進む
- `_controller.value.deviceOrientation.index` が存在しない（ビルドエラー）

### 修正
```dart
// ❌ 問題: async を付けているが待たない
_controller.startImageStream((CameraImage image) async {

// ✅ 修正: async を削除
_controller.startImageStream((CameraImage image) {
```

```dart
// ❌ 問題: deviceOrientation.index は存在しない
onFrame(transferable, image.width, image.height, _controller.value.deviceOrientation.index);

// ✅ 修正: sensorOrientation を使用（0, 90, 180, 270の整数値）
final rotation = _controller.description.sensorOrientation;
onFrame(transferable, image.width, image.height, rotation);
```

### 修正箇所
- `startImageStream()` メソッド内のフレームコールバック

---

## 2. pose_isolate.dart

### 問題
- `list.reshape()` が Dart に存在しない（擬似コード状態）
- モデル読み込み時にエラーハンドリングがない
- テンソル操作が不正確（フラット配列を多次元として扱っている）

### 修正
```dart
// ❌ 問題: reshape は存在しない
final input = List.filled(inputSize * inputSize * 3, 0.0).reshape([1, inputSize, inputSize, 3]);
final output = List.filled(1 * 17 * 3, 0.0).reshape([1, 17, 3]);

// ✅ 修正: フラット配列で管理し、インデックスで アクセス
final inputList = List<double>.filled(inputSize * inputSize * 3, 0.0);
final input = [inputList];
final output = List<double>.filled(1 * numKeypoints * 3, 0.0);
```

```dart
// ❌ 問題: エラーハンドリングなし
final interpreter = await Interpreter.fromAsset('movenet.tflite');

// ✅ 修正: try-catch でラップ
Interpreter? interpreter;
try {
  interpreter = await Interpreter.fromAsset('movenet.tflite');
} catch (e) {
  debugPrint('Failed to load model: $e');
  sendPort.send({'error': 'Model load failed: $e'});
  return;
}
```

```dart
// ❌ 問題: 多次元インデックスアクセス（存在しない）
final y = output[0][i][0];
final x = output[0][i][1];

// ✅ 修正: フラット配列での正しいインデックス計算
final baseIdx = i * 3;
final y = baseIdx < output.length ? output[baseIdx] : 0.0;
final x = (baseIdx + 1) < output.length ? output[baseIdx + 1] : 0.0;
final score = (baseIdx + 2) < output.length ? output[baseIdx + 2] : 0.0;
```

### 修正箇所
- `poseIsolateEntry()` 関数全体
- モデル読み込み時のエラーハンドリング追加
- テンソル初期化とインデックスアクセス修正
- インポートに `package:flutter/foundation.dart` を追加（debugPrint 用）

### 実装時の推奨事項
- 本番環境では `tflite_flutter_helper` を使用してTensorImage/TensorBufferを正しく構築することを推奨
- ImageProcessorBuilderを使用したリサイズ・正規化処理を実装してください

---

## 3. pose_painter.dart

### 問題
- `shouldRepaint()` メソッドで配列範囲チェックがないため、`keypoints` の長さが変わると IndexError が発生

### 修正
```dart
// ❌ 問題: 範囲外アクセスの可能性
for (var i = 0; i < keypoints.length; i++) {
  final a = keypoints[i];
  final b = oldDelegate.keypoints[i];  // oldDelegate が短い場合エラー
}

// ✅ 修正: 最小長でループ
final minLen = keypoints.length < oldDelegate.keypoints.length
    ? keypoints.length
    : oldDelegate.keypoints.length;
for (var i = 0; i < minLen; i++) {
  final a = keypoints[i];
  final b = oldDelegate.keypoints[i];
  if (a.x != b.x || a.y != b.y || a.score != b.score) return true;
}
```

### 修正箇所
- `shouldRepaint()` メソッド内のループ処理

---

## 修正優先度（実装順）
1. **pose_isolate.dart** ⚠️ 最高 → API互換性エラーで動作しない
2. **camera_handler.dart** ⚠️ 高 → ビルドエラーの原因
3. **pose_painter.dart** ⚠️ 中 → 実行時クラッシュのリスク

---

## 実装状況
✅ **完了**: 3ファイル全て修正実装

**修正日**: 2026-01-09

**注意**: これらのファイルは概念実装であり、実際のプロジェクト（flutter_application_1）に統合する場合は、依存関係（camera, tflite_flutter など）の追加が必要です。
