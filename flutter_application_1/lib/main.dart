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
      title: '全身骨格トラッカー',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: PoseTrackerScreen(cameras: cameras),
    );
  }
}

class PoseTrackerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const PoseTrackerScreen({super.key, required this.cameras});

  @override
  State<PoseTrackerScreen> createState() => _PoseTrackerScreenState();
}

class _PoseTrackerScreenState extends State<PoseTrackerScreen> {
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
