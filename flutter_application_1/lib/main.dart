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

  // 動作検出
  int _squatCount = 0;
  int _stepLeftCount = 0;
  int _stepRightCount = 0;
  String _lastDetected = '';
  DateTime? _lastDetectionTime;
  
  // 検出閾値
  final double _squatThreshold = 0.15;
  final double _stepHeightThreshold = 0.08;
  
  // 前回の状態（連続検出防止）
  bool _wasSquatting = false;
  bool _wasSteppingLeft = false;
  bool _wasSteppingRight = false;

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
          _detectMotions();
        });
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    }

    _isDetecting = false;
  }
  
  void _detectMotions() {
    if (_currentPose == null) return;
    
    final landmarks = _currentPose!.landmarks;
    
    // スクワット検出
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    
    if (leftHip != null && leftKnee != null && leftHip.y > 0) {
      final ratio = (leftHip.y - leftKnee.y).abs() / leftHip.y;
      final isSquatting = ratio < _squatThreshold;
      
      if (isSquatting && !_wasSquatting) {
        _squatCount++;
        _lastDetected = 'スクワット';
        _lastDetectionTime = DateTime.now();
        debugPrint('スクワット検出！ カウント: $_squatCount');
      }
      _wasSquatting = isSquatting;
    }
    
    // 左足踏み検出
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final leftKneeForStep = landmarks[PoseLandmarkType.leftKnee];
    
    if (leftAnkle != null && leftKneeForStep != null) {
      final isSteppingLeft = leftAnkle.y < (leftKneeForStep.y - _stepHeightThreshold);
      
      if (isSteppingLeft && !_wasSteppingLeft) {
        _stepLeftCount++;
        _lastDetected = '左足踏み';
        _lastDetectionTime = DateTime.now();
        debugPrint('左足踏み検出！ カウント: $_stepLeftCount');
      }
      _wasSteppingLeft = isSteppingLeft;
    }
    
    // 右足踏み検出
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];
    
    if (rightAnkle != null && rightKnee != null) {
      final isSteppingRight = rightAnkle.y < (rightKnee.y - _stepHeightThreshold);
      
      if (isSteppingRight && !_wasSteppingRight) {
        _stepRightCount++;
        _lastDetected = '右足踏み';
        _lastDetectionTime = DateTime.now();
        debugPrint('右足踏み検出！ カウント: $_stepRightCount');
      }
      _wasSteppingRight = isSteppingRight;
    }
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
        title: const Text('動作検出トラッカー'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _squatCount = 0;
                _stepLeftCount = 0;
                _stepRightCount = 0;
                _lastDetected = '';
                _lastDetectionTime = null;
              });
            },
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
          // 検出カウント表示
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'スクワット: $_squatCount',
                    style: const TextStyle(
                      color: Colors.cyan,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '左足踏み: $_stepLeftCount',
                    style: const TextStyle(
                      color: Colors.pink,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '右足踏み: $_stepRightCount',
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 最新の検出表示
          if (_lastDetected.isNotEmpty && _lastDetectionTime != null)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: DateTime.now().difference(_lastDetectionTime!).inMilliseconds < 1000 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      '$_lastDetected 検出！',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
