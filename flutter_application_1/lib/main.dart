import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
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
      title: '全身骨格トラッカー (MoveNet)',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: PoseTrackerScreen(cameras: cameras),
    );
  }
}

// MoveNet output format: 17 keypoints, each (y, x, score)
class PoseLandmark {
  final double y;
  final double x;
  final double score;
  final int index;
  
  PoseLandmark({
    required this.y,
    required this.x,
    required this.score,
    required this.index,
  });
}

class Pose {
  final List<PoseLandmark> landmarks;
  
  Pose({required this.landmarks});
}

class PoseTrackerScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const PoseTrackerScreen({super.key, required this.cameras});

  @override
  State<PoseTrackerScreen> createState() => _PoseTrackerScreenState();
}

class _PoseTrackerScreenState extends State<PoseTrackerScreen> {
  static const int inputSize = 192;
  
  CameraController? _cameraController;
  CameraDescription? _currentCamera;
  Interpreter? _tfliteInterpreter;
  bool _isDetecting = false;
  Pose? _currentPose;
  bool _useFrontCamera = true;
  bool _logged = false;

  // MoveNet keypoint names (17 points)
  static const List<String> keypointNames = [
    'nose',
    'leftEye', 'rightEye',
    'leftEar', 'rightEar',
    'leftShoulder', 'rightShoulder',
    'leftElbow', 'rightElbow',
    'leftWrist', 'rightWrist',
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
    'leftAnkle', 'rightAnkle',
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadTFLiteModel();
  }

  Future<void> _loadTFLiteModel() async {
    try {
      _tfliteInterpreter = await Interpreter.fromAsset('assets/models/movenet_singlepose_lightning.tflite');
      debugPrint('TFLite model loaded successfully');
    } catch (e) {
      debugPrint('Error loading TFLite model: $e');
    }
  }

  Future<void> _initializeCamera() async {
    await _cameraController?.dispose();
    _currentPose = null;
    
    final preferred =
      _useFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;

    CameraDescription camera;
    try {
      camera = widget.cameras.firstWhere((c) => c.lensDirection == preferred);
    } catch (_) {
      camera = widget.cameras.first;
    }
    
    _currentCamera = camera;
    
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    
    await _cameraController!.initialize();
    debugPrint('Using camera: ${_currentCamera?.lensDirection}');
    
    if (!mounted) return;
    await _cameraController!.startImageStream(_processCameraImage);
    setState(() {});
  }
  
  Future<void> _switchCamera() async {
    setState(() {
      _useFrontCamera = !_useFrontCamera;
    });
    await _initializeCamera();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDetecting || _tfliteInterpreter == null) return;

    if (!_logged) {
      debugPrint('CameraImage: w=${image.width}, h=${image.height}, planes=${image.planes.length}');
      _logged = true;
    }

    _isDetecting = true;

    try {
      // Convert YUV420 to RGB and resize
      final inputData = await _yuvToRgbAndNormalize(image);
      
      // Run TFLite inference
      final outputData = List<double>.filled(1 * 17 * 3, 0.0);
      _tfliteInterpreter!.runForMultipleInputs([inputData], {'output': outputData} as Map<int, Object>);
      
      // Parse output: [1, 17, 3] -> 17 keypoints with (y, x, score)
      final List<PoseLandmark> landmarks = [];
      
      for (int i = 0; i < 17; i++) {
        final idx = i * 3;
        final y = (outputData[idx] as double) / inputSize;
        final x = (outputData[idx + 1] as double) / inputSize;
        final score = (outputData[idx + 2] as double);
        
        landmarks.add(PoseLandmark(
          y: y.clamp(0.0, 1.0),
          x: x.clamp(0.0, 1.0),
          score: score,
          index: i,
        ));
      }
      
      debugPrint('Detected ${landmarks.length} keypoints');
      
      if (mounted) {
        setState(() {
          _currentPose = Pose(landmarks: landmarks);
        });
      }
    } catch (e, st) {
      debugPrint('Error processing image: $e\n$st');
    }

    _isDetecting = false;
  }

  Future<List> _yuvToRgbAndNormalize(CameraImage image) async {
    final int width = image.width;
    final int height = image.height;
    final List<dynamic> output = [];
    
    // Simple YUV420 to RGB conversion
    final Uint8List yPlane = image.planes[0].bytes;
    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;
    
    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
    
    for (int y = 0; y < height; y++) {
      final List<num> row = [];
      for (int x = 0; x < width; x++) {
        final int yIdx = y * yRowStride + x;
        final int uvIdx = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
        
        final int yVal = yPlane[yIdx] & 0xff;
        final int uVal = (uPlane[uvIdx] & 0xff) - 128;
        final int vVal = (vPlane[uvIdx] & 0xff) - 128;
        
        int r = (yVal + (1.402 * vVal)).clamp(0, 255).toInt();
        int g = (yVal - (0.344 * uVal) - (0.714 * vVal)).clamp(0, 255).toInt();
        int b = (yVal + (1.772 * uVal)).clamp(0, 255).toInt();
        
        row.addAll([(r / 127.5 - 1.0), (g / 127.5 - 1.0), (b / 127.5 - 1.0)]);
      }
      output.add(row);
    }
    
    return [output];
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _tfliteInterpreter?.close();
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
        title: const Text('全身骨格トラッカー (MoveNet)'),
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
            painter: PoseOverlayPainter(pose: _currentPose),
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
                  'Landmarks: ${_currentPose!.landmarks.length}/17 (MoveNet)',
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

    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    int linesDrawn = 0;

    // Filter landmarks by confidence
    final validLandmarks = {
      for (var lm in landmarks)
        lm.index: lm
    };

    void drawLine(int aIdx, int bIdx) {
      final la = validLandmarks[aIdx];
      final lb = validLandmarks[bIdx];
      if (la != null && lb != null && la.score > confidenceThreshold && lb.score > confidenceThreshold) {
        canvas.drawLine(
          Offset(la.x * size.width, la.y * size.height),
          Offset(lb.x * size.width, lb.y * size.height),
          linePaint,
        );
        linesDrawn++;
      }
    }

    // Draw all keypoints
    for (final lm in landmarks) {
      if (lm.score > confidenceThreshold) {
        canvas.drawCircle(Offset(lm.x * size.width, lm.y * size.height), 4, pointPaint);
      }
    }

    // MoveNet keypoint indices:
    // 0=nose, 1=leftEye, 2=rightEye, 3=leftEar, 4=rightEar,
    // 5=leftShoulder, 6=rightShoulder, 7=leftElbow, 8=rightElbow,
    // 9=leftWrist, 10=rightWrist, 11=leftHip, 12=rightHip,
    // 13=leftKnee, 14=rightKnee, 15=leftAnkle, 16=rightAnkle

    // Head connections
    drawLine(1, 2);   // leftEye - rightEye
    drawLine(1, 3);   // leftEye - leftEar
    drawLine(3, 0);   // leftEar - nose
    drawLine(0, 4);   // nose - rightEar
    drawLine(4, 2);   // rightEar - rightEye

    // Body connections
    drawLine(5, 6);   // leftShoulder - rightShoulder
    drawLine(5, 11);  // leftShoulder - leftHip
    drawLine(6, 12);  // rightShoulder - rightHip
    drawLine(11, 12); // leftHip - rightHip

    // Left arm
    drawLine(5, 7);   // leftShoulder - leftElbow
    drawLine(7, 9);   // leftElbow - leftWrist

    // Right arm
    drawLine(6, 8);   // rightShoulder - rightElbow
    drawLine(8, 10);  // rightElbow - rightWrist

    // Left leg
    drawLine(11, 13); // leftHip - leftKnee
    drawLine(13, 15); // leftKnee - leftAnkle

    // Right leg
    drawLine(12, 14); // rightHip - rightKnee
    drawLine(14, 16); // rightKnee - rightAnkle

    debugPrint('Skeleton: ${landmarks.length} landmarks, $linesDrawn lines drawn');
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return pose != oldDelegate.pose;
  }
}
