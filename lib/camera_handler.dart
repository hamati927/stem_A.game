// camera_handler.dart
// カメラ初期化・フレーム送信ユーティリティ（概念実装）

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';

typedef FrameCallback = void Function(TransferableTypedData frameData, int width, int height, int rotation);

class CameraHandler {
  final CameraDescription cameraDescription;
  late CameraController _controller;
  bool _isStreaming = false;
  StreamSubscription? _sub;

  CameraHandler(this.cameraDescription);

  Future<void> initialize() async {
    _controller = CameraController(cameraDescription, ResolutionPreset.medium, enableAudio: false);
    await _controller.initialize();
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller.dispose();
  }

  CameraPreview buildPreview() => CameraPreview(_controller);

  Future<void> startImageStream(FrameCallback onFrame) async {
    if (_isStreaming) return;
    _isStreaming = true;

    _controller.startImageStream((CameraImage image) async {
      // ここで CameraImage を Isolate に安全に送るために TransferableTypedData に変換する
      // 実運用ではプラットフォーム向けに最適化した YUV->RGB 変換を Isolate 側で行うのが良い

      // シンプル実装: 各 plane を連結して送る（受け側で復元）
      final planes = image.planes;
      final bytes = <int>[];
      for (final p in planes) {
        bytes.addAll(p.bytes);
      }
      final transferable = TransferableTypedData.fromList([Uint8List.fromList(bytes)]);
      onFrame(transferable, image.width, image.height, _controller.value.deviceOrientation.index);
    });
  }

  Future<void> stopImageStream() async {
    if (!_isStreaming) return;
    _isStreaming = false;
    try {
      await _controller.stopImageStream();
    } catch (_) {}
  }

  bool get isInitialized => _controller.value.isInitialized;
  int get previewWidth => _controller.value.previewSize?.width?.toInt() ?? 0;
  int get previewHeight => _controller.value.previewSize?.height?.toInt() ?? 0;
}
