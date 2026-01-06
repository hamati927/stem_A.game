// pose_isolate.dart
// Isolate エントリと推論ワーカー（概念実装）

import 'dart:isolate';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

// 送受信用のメッセージ構造
class InferenceRequest {
  final TransferableTypedData frameData;
  final int width;
  final int height;
  final SendPort replyTo;
  InferenceRequest(this.frameData, this.width, this.height, this.replyTo);
}

// 返却: Map<String, dynamic> の keypoints 等

// Isolate エントリ
void poseIsolateEntry(SendPort sendPort) async {
  final port = ReceivePort();
  sendPort.send(port.sendPort);

  // モデルロード（例: movenet.tflite を assets に配置）
  final interpreter = await Interpreter.fromAsset('movenet.tflite');
  final inputSize = 192; // モデル依存

  await for (final msg in port) {
    if (msg is InferenceRequest) {
      final data = msg.frameData.materialize().asUint8List();
      // TODO: data から RGB テンソルを作成する前処理を実装
      // ここでは擬似処理
      final input = List.filled(inputSize * inputSize * 3, 0.0).reshape([1, inputSize, inputSize, 3]);
      // 実行
      final output = List.filled(1 * 17 * 3, 0.0).reshape([1, 17, 3]);
      interpreter.run(input, output);

      // output を keypoints に変換（例: [{'x':..,'y':..,'score':..},...])
      final keypoints = <Map<String, dynamic>>[];
      for (int i = 0; i < 17; i++) {
        final y = output[0][i][0];
        final x = output[0][i][1];
        final score = output[0][i][2];
        keypoints.add({'index': i, 'x': x, 'y': y, 'score': score});
      }

      msg.replyTo.send({'keypoints': keypoints, 'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0});
    }
  }
}

// 注意: Dart の list.reshape は存在しないので上記は擬似コードです。
// 実装では tflite_flutter_helper を使って TensorImage/TensorBuffer を組み立ててください。
