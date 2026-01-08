import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'dart:typed_data';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pose Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: RhythmGameScreen(cameras: cameras),
    );
  }
}

// アクションの種類
enum ActionType {
  squat,
  stepLeft,
  stepRight,
}

// アクション（譜面の1要素）
class GameAction {
  final double timeS;
  final ActionType actionType;
  bool completed;
  final double deadline;

  GameAction({
    required this.timeS,
    required this.actionType,
    this.completed = false,
  }) : deadline = timeS + 3.0;

  String get displayName {
    switch (actionType) {
      case ActionType.squat:
        return 'スクワット';
      case ActionType.stepLeft:
        return '左足踏み';
      case ActionType.stepRight:
        return '右足踏み';
    }
  }
}

class RhythmGameScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const RhythmGameScreen({super.key, required this.cameras});

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen> {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;
  bool _isDetecting = false;
  Pose? _currentPose;

  // 画像回転（カメラのセンサー向き）
  InputImageRotation? _imageRotation;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _poseDetector = PoseDetector(options: PoseDetectorOptions());
  }

  Future<void> _initializeCamera() async {
    final camera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    _cameraController!.startImageStream(_processCameraImage);

    // カメラのセンサー向きから回転を設定
    try {
      final degrees = _cameraController!.description.sensorOrientation;
      _imageRotation = _rotationFromDegrees(degrees);
    } catch (_) {
      _imageRotation = InputImageRotation.rotation0deg;
    }

    if (mounted) {
      setState(() {});
    }
  }

  InputImageRotation _rotationFromDegrees(int degrees) {
    switch (degrees) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || _poseDetector == null) return;

    _isDetecting = true;

    try {
      final InputImage inputImage = _convertCameraImage(image);
      final poses = await _poseDetector!.processImage(inputImage);

      if (mounted) {
        setState(() {
          _currentPose = poses.isNotEmpty ? poses.first : null;
        });
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    }

    _isDetecting = false;
  }

  InputImage _convertCameraImage(CameraImage image) {
    final bytes = Uint8List.fromList(
      image.planes.fold<List<int>>(
        [],
        (previousValue, plane) => previousValue..addAll(plane.bytes),
      ),
    );

    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final InputImageRotation rotation = _imageRotation ?? InputImageRotation.rotation0deg;
    final InputImageFormat format = InputImageFormat.nv21;

    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageMetadata,
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _poseDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('全身骨格トラッカー'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          CustomPaint(
            painter: PoseOverlayPainter(
              pose: _currentPose,
            ),
          ),
          if (_currentPose == null)
            Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'No pose detected...（カメラ位置・照明を調整してください）',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
          // 現在のアクション表示
          if (currentAction != null && remainingTime != null && !_debugMode)
            Positioned(
              top: 100,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentAction.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '残り: ${remainingTime.toStringAsFixed(1)}秒',
                      style: TextStyle(
                        color: remainingTime < 1.0 ? Colors.red : Colors.white,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // デバッグ用の閾値調整スライダー
          if (_debugMode)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.yellow, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Squat Threshold Adjustment',
                      style: TextStyle(color: Colors.yellow, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text('${_squatThreshold.toStringAsFixed(3)}', style: const TextStyle(color: Colors.white)),
                        Expanded(
                          child: Slider(
                            value: _squatThreshold,
                            min: 0.05,
                            max: 0.5,
                            onChanged: (value) {
                              setState(() => _squatThreshold = value);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Step Height Threshold Adjustment',
                      style: TextStyle(color: Colors.yellow, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text('${_stepHeightThreshold.toStringAsFixed(3)}', style: const TextStyle(color: Colors.white)),
                        Expanded(
                          child: Slider(
                            value: _stepHeightThreshold,
                            min: 0.01,
                            max: 0.3,
                            onChanged: (value) {
                              setState(() => _stepHeightThreshold = value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // 成功表示
          if (_showSuccess)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'SUCCESS!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          // ゲーム終了表示
          if (_gameFinished)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ゲーム終了!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'スコア: $_score / ${_actions.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initializeGame();
                        });
                      },
                      child: const Text('もう一度'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PoseOverlayPainter extends CustomPainter {
  final Pose? pose;

  PoseOverlayPainter({this.pose});

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null) return;
    final landmarks = pose!.landmarks;

    // 点の描画
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    for (final lm in landmarks.values) {
      canvas.drawCircle(Offset(lm.x * size.width, lm.y * size.height), 5, pointPaint);
    }

    // 線の描画（全身）
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    void draw(PoseLandmarkType a, PoseLandmarkType b) {
      final la = landmarks[a];
      final lb = landmarks[b];
      if (la != null && lb != null) {
        canvas.drawLine(
          Offset(la.x * size.width, la.y * size.height),
          Offset(lb.x * size.width, lb.y * size.height),
          linePaint,
        );
      }
    }

    // 頭部
    draw(PoseLandmarkType.leftEye, PoseLandmarkType.rightEye);
    draw(PoseLandmarkType.leftEye, PoseLandmarkType.leftEar);
    draw(PoseLandmarkType.rightEye, PoseLandmarkType.rightEar);
    draw(PoseLandmarkType.nose, PoseLandmarkType.leftEye);
    draw(PoseLandmarkType.nose, PoseLandmarkType.rightEye);

    // 胴体
    draw(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    draw(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    draw(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    draw(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);

    // 左腕
    draw(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
    draw(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);

    // 右腕
    draw(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
    draw(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);

    // 左脚
    draw(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
    draw(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);

    // 右脚
    draw(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
    draw(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return pose != oldDelegate.pose;
  }
}
