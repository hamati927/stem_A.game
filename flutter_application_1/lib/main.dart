import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:audioplayers/audioplayers.dart';
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
      title: 'Lower Body Rhythm Game',
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
  
  // ゲーム状態
  late List<GameAction> _actions;
  late DateTime _gameStartTime;
  int _score = 0;
  bool _gameFinished = false;
  bool _showSuccess = false;
  
  // 検出閾値
  double _squatThreshold = 0.15;
  double _stepHeightThreshold = 0.08;
  
  // デバッグモード
  bool _debugMode = false;
  String _debugInfo = '';
  double? _currentSquatRatio;
  double? _currentLeftStepHeight;
  double? _currentRightStepHeight;
  
  // 音声プレイヤー
  late AudioPlayer _bgmPlayer;
  late AudioPlayer _successPlayer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(),
    );
    _initializeAudio();
    _initializeGame();
  }
  
  void _initializeAudio() {
    _bgmPlayer = AudioPlayer();
    _successPlayer = AudioPlayer();
  }
  
  void _initializeGame() {
    _actions = [
      GameAction(timeS: 2.0, actionType: ActionType.squat),
      GameAction(timeS: 6.0, actionType: ActionType.stepLeft),
      GameAction(timeS: 10.0, actionType: ActionType.stepRight),
      GameAction(timeS: 14.0, actionType: ActionType.squat),
      GameAction(timeS: 18.0, actionType: ActionType.stepLeft),
      GameAction(timeS: 22.0, actionType: ActionType.squat),
      GameAction(timeS: 26.0, actionType: ActionType.stepRight),
      GameAction(timeS: 30.0, actionType: ActionType.squat),
    ];
    _gameStartTime = DateTime.now();
    _score = 0;
    _gameFinished = false;
    
    // BGM再生開始
    _playBgm();
  }
  
  Future<void> _playBgm() async {
    try {
      await _bgmPlayer.play(AssetSource('audio/bgm.wav'), volume: 0.5);
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('Failed to load BGM: $e');
    }
  }
  
  Future<void> _playSuccessSound() async {
    try {
      await _successPlayer.play(AssetSource('audio/success.wav'), volume: 0.7);
    } catch (e) {
      debugPrint('Failed to play success sound: $e');
    }
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
    );

    await _cameraController!.initialize();
    _cameraController!.startImageStream(_processCameraImage);

    if (mounted) {
      setState(() {});
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
          _updateGameState();
        });
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    }

    _isDetecting = false;
  }
  
  void _updateGameState() {
    if (_gameFinished) return;
    
    final now = DateTime.now().difference(_gameStartTime).inMilliseconds / 1000.0;
    
    // 現在のアクションを探す
    GameAction? currentAction;
    for (final action in _actions) {
      if (action.completed) continue;
      if (now < action.timeS) continue;
      
      // 期限切れチェック
      if (now > action.deadline) {
        action.completed = true;
        debugPrint('失敗: ${action.displayName} (時間切れ)');
        continue;
      }
      
      currentAction = action;
      break;
    }
    
    // 動作検出
    if (currentAction != null && _currentPose != null) {
      bool detected = false;
      
      switch (currentAction.actionType) {
        case ActionType.squat:
          detected = _detectSquat(_currentPose!);
          break;
        case ActionType.stepLeft:
          detected = _detectStepLeft(_currentPose!);
          break;
        case ActionType.stepRight:
          detected = _detectStepRight(_currentPose!);
          break;
      }
      
      if (detected) {
        currentAction.completed = true;
        _score++;
        _showSuccess = true;
        _playSuccessSound();
        debugPrint('成功: ${currentAction.displayName}');
        
        // 成功表示を1秒後に消す
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _showSuccess = false;
            });
          }
        });
      }
    }
    
    // ゲーム終了チェック
    if (_actions.every((a) => a.completed)) {
      _gameFinished = true;
    }
  }
  
  bool _detectSquat(Pose pose) {
    final landmarks = pose.landmarks;
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    
    if (leftHip == null || leftKnee == null) return false;
    
    final hipKneeDist = (leftHip.y - leftKnee.y).abs();
    final hipY = leftHip.y;
    
    if (hipY <= 0) return false;
    
    final ratio = hipKneeDist / hipY;
    _currentSquatRatio = ratio;
    
    if (_debugMode) {
      _debugInfo = 'Squat Ratio: ${ratio.toStringAsFixed(3)} (threshold: $_squatThreshold)\n'
                   'Hip confidence: ${leftHip.z.toStringAsFixed(2)}\n'
                   'Knee confidence: ${leftKnee.z.toStringAsFixed(2)}';
    }
    
    return ratio < _squatThreshold;
  }
  
  bool _detectStepLeft(Pose pose) {
    final landmarks = pose.landmarks;
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];
    final leftKnee = landmarks[PoseLandmarkType.leftKnee];
    
    if (leftAnkle == null || leftKnee == null) return false;
    
    final heightDiff = (leftKnee.y - leftAnkle.y);
    _currentLeftStepHeight = heightDiff;
    
    if (_debugMode) {
      _debugInfo = 'Left Step Height: ${heightDiff.toStringAsFixed(3)} (threshold: $_stepHeightThreshold)\n'
                   'Ankle confidence: ${leftAnkle.z.toStringAsFixed(2)}\n'
                   'Knee confidence: ${leftKnee.z.toStringAsFixed(2)}';
    }
    
    return leftAnkle.y < (leftKnee.y - _stepHeightThreshold);
  }
  
  bool _detectStepRight(Pose pose) {
    final landmarks = pose.landmarks;
    final rightAnkle = landmarks[PoseLandmarkType.rightAnkle];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];
    
    if (rightAnkle == null || rightKnee == null) return false;
    
    final heightDiff = (rightKnee.y - rightAnkle.y);
    _currentRightStepHeight = heightDiff;
    
    if (_debugMode) {
      _debugInfo = 'Right Step Height: ${heightDiff.toStringAsFixed(3)} (threshold: $_stepHeightThreshold)\n'
                   'Ankle confidence: ${rightAnkle.z.toStringAsFixed(2)}\n'
                   'Knee confidence: ${rightKnee.z.toStringAsFixed(2)}';
    }
    
    return rightAnkle.y < (rightKnee.y - _stepHeightThreshold);
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

    final InputImageRotation rotation = InputImageRotation.rotation0deg;
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
    _bgmPlayer.release();
    _successPlayer.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    final now = DateTime.now().difference(_gameStartTime).inMilliseconds / 1000.0;
    GameAction? currentAction;
    double? remainingTime;
    
    for (final action in _actions) {
      if (action.completed) continue;
      if (now < action.timeS) continue;
      if (now > action.deadline) continue;
      
      currentAction = action;
      remainingTime = action.deadline - now;
      break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('下半身リズムゲーム'),
        actions: [
          IconButton(
            icon: Icon(_debugMode ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () {
              setState(() {
                _debugMode = !_debugMode;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _bgmPlayer.stop();
              setState(() {
                _initializeGame();
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
            painter: GameOverlayPainter(
              pose: _currentPose,
              currentAction: currentAction,
              debugMode: _debugMode,
            ),
          ),
          // デバッグ情報パネル
          if (_debugMode)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyan, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DEBUG INFO',
                      style: TextStyle(
                        color: Colors.cyan,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _debugInfo.isEmpty ? 'Waiting for pose...' : _debugInfo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Squat Threshold: ${_squatThreshold.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.yellow, fontSize: 10),
                    ),
                    Text(
                      'Step Height Threshold: ${_stepHeightThreshold.toStringAsFixed(3)}',
                      style: const TextStyle(color: Colors.yellow, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          // HUD
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'スコア: $_score / ${_actions.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
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

class GameOverlayPainter extends CustomPainter {
  final Pose? pose;
  final GameAction? currentAction;
  final bool debugMode;

  GameOverlayPainter({this.pose, this.currentAction, this.debugMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    // 骨格を描画
    if (pose != null) {
      _drawSkeleton(canvas, size, pose!);
      
      // デバッグモード時にランドマーク情報を表示
      if (debugMode) {
        _drawDebugInfo(canvas, size, pose!);
      }
    }
    
    // 現在のアクションの見本を描画
    if (currentAction != null && !debugMode) {
      _drawActionGuide(canvas, currentAction!);
    }
  }
  
  void _drawDebugInfo(Canvas canvas, Size size, Pose pose) {
    final paint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    
    // 主要なランドマークの座標を描画
    const landmarks = [
      PoseLandmarkType.leftHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.rightAnkle,
    ];
    
    for (final landmarkType in landmarks) {
      final landmark = pose.landmarks[landmarkType];
      if (landmark != null) {
        final x = landmark.x * size.width;
        final y = landmark.y * size.height;
        
        // 信頼度に応じた色
        final confidence = landmark.z;
        Color color = confidence > 0.7 ? Colors.green : (confidence > 0.5 ? Colors.yellow : Colors.red);
        
        canvas.drawCircle(
          Offset(x, y),
          10,
          Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2,
        );
      }
    }
  }
  
  void _drawSkeleton(Canvas canvas, Size size, Pose pose) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    
    // ランドマークを描画
    for (final landmark in pose.landmarks.values) {
      canvas.drawCircle(
        Offset(landmark.x * size.width, landmark.y * size.height),
        6,
        paint,
      );
    }
    
    // 主要な骨格線を描画
    _drawLine(canvas, size, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, linePaint);
    _drawLine(canvas, size, pose, PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, linePaint);
    _drawLine(canvas, size, pose, PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, linePaint);
    _drawLine(canvas, size, pose, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, linePaint);
    _drawLine(canvas, size, pose, PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, linePaint);
    _drawLine(canvas, size, pose, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, linePaint);
    _drawLine(canvas, size, pose, PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, linePaint);
    _drawLine(canvas, size, pose, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, linePaint);
  }
  
  void _drawLine(Canvas canvas, Size size, Pose pose, PoseLandmarkType start, PoseLandmarkType end, Paint paint) {
    final startLandmark = pose.landmarks[start];
    final endLandmark = pose.landmarks[end];
    
    if (startLandmark != null && endLandmark != null) {
      canvas.drawLine(
        Offset(startLandmark.x * size.width, startLandmark.y * size.height),
        Offset(endLandmark.x * size.width, endLandmark.y * size.height),
        paint,
      );
    }
  }
  
  void _drawActionGuide(Canvas canvas, GameAction action) {
    final paint = Paint()
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    
    final fillPaint = Paint()
      ..style = PaintingStyle.fill;
    
    // 見本描画位置（右上）
    const baseX = 300.0;
    const baseY = 120.0;
    const scale = 40.0;
    
    switch (action.actionType) {
      case ActionType.squat:
        paint.color = Colors.cyan;
        fillPaint.color = Colors.cyan;
        // スクワット姿勢（膝が曲がった状態）
        _drawStickFigure(canvas, baseX, baseY, scale, paint, fillPaint, squatting: true);
        break;
      case ActionType.stepLeft:
        paint.color = Colors.pink;
        fillPaint.color = Colors.pink;
        // 左足を上げた状態
        _drawStickFigure(canvas, baseX, baseY, scale, paint, fillPaint, leftLegUp: true);
        break;
      case ActionType.stepRight:
        paint.color = Colors.yellow;
        fillPaint.color = Colors.yellow;
        // 右足を上げた状態
        _drawStickFigure(canvas, baseX, baseY, scale, paint, fillPaint, rightLegUp: true);
        break;
    }
  }
  
  void _drawStickFigure(Canvas canvas, double x, double y, double scale, Paint linePaint, Paint circlePaint, 
      {bool squatting = false, bool leftLegUp = false, bool rightLegUp = false}) {
    // 頭
    canvas.drawCircle(Offset(x, y), scale * 0.3, circlePaint);
    
    // 胴体
    final bodyBottom = squatting ? y + scale * 0.8 : y + scale;
    canvas.drawLine(Offset(x, y + scale * 0.3), Offset(x, bodyBottom), linePaint);
    
    // 腕（簡略化）
    canvas.drawLine(Offset(x, y + scale * 0.5), Offset(x - scale * 0.4, y + scale * 0.7), linePaint);
    canvas.drawLine(Offset(x, y + scale * 0.5), Offset(x + scale * 0.4, y + scale * 0.7), linePaint);
    
    // 脚
    if (squatting) {
      // スクワット姿勢
      canvas.drawLine(Offset(x, bodyBottom), Offset(x - scale * 0.3, bodyBottom + scale * 0.5), linePaint);
      canvas.drawLine(Offset(x, bodyBottom), Offset(x + scale * 0.3, bodyBottom + scale * 0.5), linePaint);
    } else if (leftLegUp) {
      // 右脚は下、左脚は上げる
      canvas.drawLine(Offset(x, bodyBottom), Offset(x + scale * 0.2, bodyBottom + scale), linePaint);
      canvas.drawLine(Offset(x, bodyBottom), Offset(x - scale * 0.2, bodyBottom + scale * 0.3), linePaint);
    } else if (rightLegUp) {
      // 左脚は下、右脚は上げる
      canvas.drawLine(Offset(x, bodyBottom), Offset(x - scale * 0.2, bodyBottom + scale), linePaint);
      canvas.drawLine(Offset(x, bodyBottom), Offset(x + scale * 0.2, bodyBottom + scale * 0.3), linePaint);
    } else {
      // 通常の立ち姿勢
      canvas.drawLine(Offset(x, bodyBottom), Offset(x - scale * 0.2, bodyBottom + scale), linePaint);
      canvas.drawLine(Offset(x, bodyBottom), Offset(x + scale * 0.2, bodyBottom + scale), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GameOverlayPainter oldDelegate) {
    return pose != oldDelegate.pose || currentAction != oldDelegate.currentAction || debugMode != oldDelegate.debugMode;
  }
}
