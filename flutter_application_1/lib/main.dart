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
  CameraDescription? _currentCamera;
  PoseDetector? _poseDetector;
  bool _isDetecting = false;
  Pose? _currentPose;
  bool _useFrontCamera = true;

  // 画像回転（カメラのセンサー向き）
  InputImageRotation? _imageRotation;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _poseDetector = PoseDetector(options: PoseDetectorOptions());
  }

  Future<void> _initializeCamera() async {
    // Dispose previous controller before switching
    await _cameraController?.dispose();
    _currentPose = null;

    final preferred = _useFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;
    CameraDescription? camera;
    try {
      camera = widget.cameras.firstWhere((c) => c.lensDirection == preferred);
    } catch (_) {
      camera = null;
    }
    camera ??= widget.cameras.firstWhere(
      (c) => c.lensDirection != preferred,
      orElse: () => widget.cameras.first,
    );
    _currentCamera = camera;

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    debugPrint('Using camera: ${_currentCamera?.name ?? _currentCamera?.lensDirection}');
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

  Future<void> _switchCamera() async {
    setState(() {
      _useFrontCamera = !_useFrontCamera;
    });
    await _initializeCamera();
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
        actions: [
          IconButton(
            tooltip: 'カメラ切替 (前/後)',
            icon: const Icon(Icons.cameraswitch),
            onPressed: _switchCamera,
          ),
        ],
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
          if (_currentPose != null)
            Positioned(
              top: 56,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Landmarks: ${_currentPose!.landmarks.length}/33',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
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
  static const double confidenceThreshold = 0.5;

  PoseOverlayPainter({this.pose});

  @override
  void paint(Canvas canvas, Size size) {
    if (pose == null) return;
    final landmarks = pose!.landmarks;

    // Full body skeleton with confidence filtering
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    void drawLine(PoseLandmarkType a, PoseLandmarkType b) {
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

    // Draw all keypoints
    for (final lm in landmarks.values) {
      canvas.drawCircle(Offset(lm.x * size.width, lm.y * size.height), 4, pointPaint);
    }

    // Head connections
    drawLine(PoseLandmarkType.leftEye, PoseLandmarkType.rightEye);
    drawLine(PoseLandmarkType.leftEar, PoseLandmarkType.leftEye);
    drawLine(PoseLandmarkType.rightEar, PoseLandmarkType.rightEye);

    // Body connections
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder);
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
    drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);

    // Left arm
    drawLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
    drawLine(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);

    // Right arm
    drawLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
    drawLine(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);

    // Left leg
    drawLine(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
    drawLine(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);

    // Right leg
    drawLine(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
    drawLine(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return pose != oldDelegate.pose;
  }
}
