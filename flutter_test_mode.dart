// flutter_test_mode.dart
// サンプル: テストモード用の Flutter ウィジェット（概念実装）
// 実際はプロジェクトの lib/ 配下に配置し、依存に path_provider / share / uuid などを追加してください.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart' show rootBundle;

class Participant {
  String id;
  String name;
  int age;
  String cohort; // e.g., 'elderly'
  Participant({required this.id, this.name = '', this.age = 0, this.cohort = 'adult_novice'});
}

class TestModeHome extends StatefulWidget {
  @override
  _TestModeHomeState createState() => _TestModeHomeState();
}

class _TestModeHomeState extends State<TestModeHome> {
  Participant participant = Participant(id: Uuid().v4());
  bool loggingEnabled = true;
  Map<String,dynamic>? cohortDefaults;

  @override
  void initState() {
    super.initState();
    loadCohortDefaults();
  }

  Future<void> loadCohortDefaults() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/configs/cohort_defaults.json');
      setState(() {
        cohortDefaults = json.decode(jsonStr);
      });
    } catch (e) {
      // assets 配置がない場合はローカルファイルやサーバから読む実装に変更
      print('Failed to load cohort defaults: $e');
    }
  }

  void onStartSession() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TestSessionScreen(participant: participant, loggingEnabled: loggingEnabled, cohortDefaults: cohortDefaults)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Test Mode')), 
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(labelText: 'Name'),
              onChanged: (v) => participant.name = v,
            ),
            TextField(
              decoration: InputDecoration(labelText: 'Age'),
              keyboardType: TextInputType.number,
              onChanged: (v) => participant.age = int.tryParse(v) ?? 0,
            ),
            DropdownButton<String>(
              value: participant.cohort,
              items: ['young_active','adult_novice','elderly'].map((c) => DropdownMenuItem(child: Text(c), value: c)).toList(),
              onChanged: (v) => setState(() => participant.cohort = v ?? 'adult_novice'),
            ),
            SwitchListTile(
              title: Text('Enable Logging'),
              value: loggingEnabled,
              onChanged: (v) => setState(() => loggingEnabled = v),
            ),
            SizedBox(height: 20),
            ElevatedButton(onPressed: onStartSession, child: Text('Start Test Session')),
            SizedBox(height: 8),
            ElevatedButton(onPressed: () async {
              // Export cohort defaults JSON for review
              final dir = await getApplicationDocumentsDirectory();
              final file = File('${dir.path}/cohort_defaults_export.json');
              await file.writeAsString(json.encode(cohortDefaults ?? {}));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
            }, child: Text('Export Defaults'))
          ],
        ),
      ),
    );
  }
}

class TestSessionScreen extends StatefulWidget {
  final Participant participant;
  final bool loggingEnabled;
  final Map<String,dynamic>? cohortDefaults;
  TestSessionScreen({required this.participant, required this.loggingEnabled, this.cohortDefaults});

  @override
  _TestSessionScreenState createState() => _TestSessionScreenState();
}

class _TestSessionScreenState extends State<TestSessionScreen> {
  late File logFile;
  bool sessionActive = false;

  @override
  void initState() {
    super.initState();
    _prepareLogFile();
  }

  Future<void> _prepareLogFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/session_${widget.participant.id}.log';
    logFile = File(path);
    if (!(await logFile.exists())) await logFile.create();
  }

  Future<void> logEvent(Map<String,dynamic> event) async {
    if (!widget.loggingEnabled) return;
    event['session_id'] = widget.participant.id;
    event['timestamp'] = DateTime.now().millisecondsSinceEpoch / 1000.0;
    await logFile.writeAsString(jsonEncode(event) + '\n', mode: FileMode.append);
  }

  void startSession() async {
    setState(() => sessionActive = true);
    // Start camera + pose detection
    final cameras = await availableCameras();
    final handler = CameraHandler(cameras.first);
    await handler.initialize();
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(poseIsolateEntry, receivePort.sendPort);
    final sendPort = await receivePort.first as SendPort;

    // Start streaming
    handler.startImageStream((frameData, width, height, rotation) {
      // send InferenceRequest to isolate
      final completer = Completer();
      final respPort = ReceivePort();
      respPort.listen((msg) async {
        // msg: {'keypoints':..., 'timestamp':...}
        final result = msg as Map<String,dynamic>;
        // convert to Keypoint list and update painter state
        final kps = (result['keypoints'] as List).map((e) => Keypoint(e['x'], e['y'], e['score'])).toList();
        setState(() {
          // update painter overlay
          // store last judgment for demo
        });
        // Example: log a dummy event (in real flow you'd run judge logic)
        logEvent({'t_ref': 0.0, 't_user': result['timestamp'], 'angles_ref': {}, 'angles_user': {}, 'angle_diff': 0.0, 'judgment': 'Simulated', 'frame_keypoints': result['keypoints']});
        respPort.close();
        completer.complete();
      });

      final req = InferenceRequest(frameData, width, height, respPort.sendPort);
      sendPort.send(req);
    });

    // Save handlers so that endSession can stop them
    _sessionCameraHandler = handler;
    _sessionIsolate = isolate;
  }

  void endSession() {
    setState(() => sessionActive = false);
    // close resources
  }

  Future<void> exportLog() async {
    final dir = await getApplicationDocumentsDirectory();
    final exportPath = '${dir.path}/session_${widget.participant.id}.log';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Log saved at $exportPath')));
    // Optionally implement share sheet via share package
  }

  @override
  Widget build(BuildContext context) {
    final defaults = widget.cohortDefaults?[widget.participant.cohort];
    return Scaffold(
      appBar: AppBar(title: Text('Test Session')),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Participant: ${widget.participant.name} (age ${widget.participant.age})'),
            SizedBox(height: 8),
            Text('Cohort defaults: ${defaults ?? 'none loaded'}'),
            SizedBox(height: 8),
            Row(children: [
              ElevatedButton(onPressed: sessionActive ? null : startSession, child: Text('Start')),
              SizedBox(width: 8),
              ElevatedButton(onPressed: sessionActive ? endSession : null, child: Text('End')),
              SizedBox(width: 8),
              ElevatedButton(onPressed: exportLog, child: Text('Export Log')),
            ]),
            SizedBox(height: 12),
            Expanded(
              child: Container(
                color: Colors.black12,
                child: Center(child: Text(sessionActive ? 'Camera & Pose Preview (mock)' : 'Session inactive', style: TextStyle(fontSize: 18))),
              ),
            )
          ],
        ),
      ),
    );
  }
}
