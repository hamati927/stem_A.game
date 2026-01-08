import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'dart:typed_data';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rhythm Game',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const RhythmGameScreen(),
    );
  }
}

class RhythmGameScreen extends StatefulWidget {
  const RhythmGameScreen({Key? key}) : super(key: key);

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen> {
  late CameraController _cameraController;
  late PoseDetector _poseDetector;
  List<Pose>? _poses;
  bool _isProcessing = false;
  int _score = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _initializeCamera();
      _initializePoseDetector();
      setState(() => _initialized = true);
    } catch (e) {
      print('Initialization error: $e');
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _cameraController = CameraController(frontCamera, ResolutionPreset.medium);
    await _cameraController.initialize();
    _cameraController.startImageStream(_processCameraImage);
  }

  void _initializePoseDetector() {
    final options = PoseDetectorOptions();
    _poseDetector = PoseDetector(options: options);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image);
      final poses = await _poseDetector.processImage(inputImage);
      setState(() => _poses = poses);
    } catch (e) {
      print('Pose detection error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage _convertCameraImage(CameraImage image) {
    final bytes = Uint8List.fromList(
      image.planes.fold<List<int>>(
        [],
        (List<int> previousValue, element) => previousValue..addAll(element.bytes),
      ),
    );

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final InputImageRotation imageRotation = InputImageRotation.rotation0deg;

    final InputImageFormat inputImageFormat = InputImageFormat.nv21;

    final planeData = image.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    return InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || !_cameraController.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Rhythm Game')),
      body: Stack(
        children: [
          CameraPreview(_cameraController),
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Score: $_score',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: CustomPaint(
                    painter: GameOverlayPainter(_poses),
                    size: Size.infinite,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GameOverlayPainter extends CustomPainter {
  final List<Pose>? poses;
  GameOverlayPainter(this.poses);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw lanes
    final lanePaint = Paint()..color = Colors.cyan..strokeWidth = 2;
    final laneWidth = size.width / 4;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(i * laneWidth, 0), Offset(i * laneWidth, size.height), lanePaint);
    }

    // Draw hit line
    final hitLinePaint = Paint()..color = Colors.yellow..strokeWidth = 4;
    canvas.drawLine(Offset(0, size.height * 0.8), Offset(size.width, size.height * 0.8), hitLinePaint);

    // Draw pose landmarks
    if (poses != null && poses!.isNotEmpty) {
      final posePaint = Paint()..color = Colors.red..strokeWidth = 2;
      for (var pose in poses!) {
        for (var landmark in pose.landmarks.values) {
          final x = landmark.x * size.width;
          final y = landmark.y * size.height;
          canvas.drawCircle(Offset(x, y), 5, posePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(GameOverlayPainter oldDelegate) => poses != oldDelegate.poses;
}
