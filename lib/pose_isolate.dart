// pose_isolate.dart
// Isolate エントリと推論ワーカー（概念実装）

import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
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

  Interpreter? interpreter;
  try {
    // モデルロード（例: movenet.tflite を assets に配置）
    interpreter = await Interpreter.fromAsset('movenet.tflite');
  } catch (e) {
    debugPrint('Failed to load model: $e');
    sendPort.send({'error': 'Model load failed: $e'});
    return;
  }

  final inputSize = 192; // モデル依存
  const numKeypoints = 17;

  await for (final msg in port) {
    if (msg is InferenceRequest) {
      try {
        final data = msg.frameData.materialize().asUint8List();
        // TODO: data から RGB テンソルを作成する前処理を実装
        // 実装では tflite_flutter_helper を使用することを推奨:
        // final imageProcessor = ImageProcessorBuilder()
        //   .add(ResizeOp(inputSize, inputSize, ResizeOp.BILINEAR))
        //   .build();
        // final tensorImage = imageProcessor.process(inputImage);

        // ここでは簡易版: 実装時に正しいテンソル構築が必要
        final inputList = List<double>.filled(inputSize * inputSize * 3, 0.0);
        final input = [inputList];
        
        // 実行
        final output = List<double>.filled(1 * numKeypoints * 3, 0.0);
        if (interpreter != null) {
          interpreter.run(input, output);
        }

        // output を keypoints に変換
        final keypoints = <Map<String, dynamic>>[];
        for (int i = 0; i < numKeypoints; i++) {
          final baseIdx = i * 3;
          final y = baseIdx < output.length ? output[baseIdx] : 0.0;
          final x = (baseIdx + 1) < output.length ? output[baseIdx + 1] : 0.0;
          final score = (baseIdx + 2) < output.length ? output[baseIdx + 2] : 0.0;
          keypoints.add({'index': i, 'x': x, 'y': y, 'score': score});
        }

        msg.replyTo.send({
          'keypoints': keypoints,
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
          'width': msg.width,
          'height': msg.height,
        });
      } catch (e) {
        msg.replyTo.send({'error': 'Inference failed: $e'});
      }
    }
  }
}

// 注意: Dart の list.reshape は存在しないので上記は擬似コードです。
// 実装では tflite_flutter_helper を使って TensorImage/TensorBuffer を組み立ててください。
