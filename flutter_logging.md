# Flutter ログ収集の実装メモ

目的
- 実機テスト時に必要な情報（t_ref, t_user,角度差,キーフレームなど）を確実に収集する。
- ログは端末内に保存し、後で解析できるJSON Lines形式を推奨。

推奨スキーマ（1行＝1イベント）
{
  "session_id": "uuid",
  "t_ref": 12.4,
  "t_user": 13.1,
  "dt": 0.7,
  "angles_ref": {"left_knee": 35.2, ...},
  "angles_user": {"left_knee": 36.4, ...},
  "angle_diff": 1.8,
  "judgment": "Perfect",
  "timestamp": 1690000000.123,
  "frame_keypoints": [{"name":"left_knee","x":0.42,"y":0.72,"score":0.92}, ...]
}

簡単な実装方針（Dart）:
- `path_provider` でアプリのドキュメントディレクトリを取得
- ログは `File('.../session_<id>.log')` に追記する
- セッション開始時に `session_id` を生成

サンプルコード（概念）:

```dart
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class Logger {
  final String sessionId;
  late File _file;

  Logger(this.sessionId);

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/session_${sessionId}.log');
    if (!(await _file.exists())) await _file.create();
  }

  Future<void> logEvent(Map<String, dynamic> event) async {
    await _file.writeAsString(jsonEncode(event) + '\n', mode: FileMode.append);
  }
}

// 判定してログするフロー例
void onMatchDetected(double tRef, double tUser, Map<String,double> anglesRef, Map<String,double> anglesUser, String judgment) async {
  final event = {
    'session_id': sessionId,
    't_ref': tRef,
    't_user': tUser,
    'dt': tUser - tRef,
    'angles_ref': anglesRef,
    'angles_user': anglesUser,
    'angle_diff': computeAngleDiff(anglesRef, anglesUser),
    'judgment': judgment,
    'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0
  };
  await logger.logEvent(event);
}
```

---

エクスポートボタン（Dart サンプル）:

```dart
import 'package:share_plus/share_plus.dart';

Future<void> exportLogFile(File file) async {
  // 共有シートで送る
  await Share.shareFiles([file.path], text: 'Session log');
}

// ファイル保存と共有の呼び出し例
ElevatedButton(onPressed: () async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/session_${sessionId}.log');
  if (await file.exists()) {
    await exportLogFile(file);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Log not found')));
  }
}, child: Text('Export Log'))
```


運用上の注意
- 個人情報を含めない（氏名や顔画像をログする場合は参加者の明確な同意を取得）
- ログの暗号化/保護が必要な場合はファイルを暗号化して保存


