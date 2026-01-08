# BGM・効果音セットアップガイド

このアプリはBGMと効果音を使用します。以下の手順でフリーのオーディオファイルを配置してください。

## 必要なファイル

1. **bgm.mp3** - ゲーム用BGM
   - 推奨: 30秒～1分程度のループBGM
   - フォーマット: MP3

2. **success.wav** - 成功時の効果音
   - 推奨: 1秒以下のビープ音またはジングル
   - フォーマット: WAV

## ダウンロードリソース

### フリーBGM

**Pixabay Music** (推奨)
- URL: https://pixabay.com/music/
- ライセンス: CC0（著作権フリー）
- ユーザー登録不要
- 検索: 「game」「rhythm」「electronic」

**Freepd.com**
- URL: https://freepd.com/
- ライセンス: CC0
- ゲーム向けBGMが豊富
- タグ: 「game」「loop」で検索

**OpenGameArt.org**
- URL: https://opengameart.org/content/type/audio/music
- ライセンス: CC0, CC-BY等
- ゲーム向け多数

### 効果音

**FreeSound.org**
- URL: https://freesound.org/
- ライセンス: CC0またはCC-BY
- 検索: 「success」「beep」「ding」「ping」

**Pixabay Sound Effects**
- URL: https://pixabay.com/sound-effects/
- ライセンス: CC0
- 効果音の種類が豊富

**Freepd.com (SFX)**
- URL: https://freepd.com/?sound-effects=1
- ライセンス: CC0

## インストール手順

1. **フリーBGMをダウンロード**
   ```bash
   # Pixabay Musicから例
   # https://pixabay.com/ → Music → Game カテゴリ
   # 30秒～1分のループBGM をダウンロード
   ```

2. **効果音をダウンロード**
   ```bash
   # FreeSound.org や Pixabay から
   # 成功時のビープ音やジングルをダウンロード
   ```

3. **ファイルを配置**
   ```bash
   # flutter_application_1/assets/audio/ に配置
   flutter_application_1/assets/audio/
   ├── bgm.mp3           # ゲームBGM
   ├── success.wav       # 成功音
   └── .gitkeep
   ```

4. **ビルド**
   ```bash
   cd flutter_application_1
   flutter pub get
   flutter build apk --debug --no-shrink
   ```

## 代替案：オンラインで探す

もしアセット検索に時間をかけたくない場合、以下の方法があります：

### 方法1: YouTubeオーディオライブラリ（YouTubeアカウント必須）
- YouTube Studio → オーディオライブラリ
- ゲーム向けBGMと効果音が検索可能
- フリーでダウンロード可能

### 方法2: 一時的にビルドをスキップ
- `pubspec.yaml` の assets セクションを編集
- オーディオ行をコメントアウト
- アプリが音無しで動作

```yaml
flutter:
  uses-material-design: true
  assets:
    # - assets/audio/bgm.mp3        # 後で有効化
    # - assets/audio/success.wav
```

## 注意事項

- **ライセンス確認**: CC0 または CC-BY ライセンスのファイルを選択
- **ファイルサイズ**: APKサイズの肥大化を避けるため、各ファイルは3MB以下推奨
- **フォーマット**: MP3 (BGM), WAV (効果音) を推奨
- **サンプリングレート**: 44.1kHz or 48kHz推奨

## デバッグ

ファイルが見つからない場合、コンソールに以下のログが出力されます：
```
Failed to load BGM: FileSystemException
```

その場合は：
1. ファイルパスが正しいか確認
2. ファイルが実際に配置されているか確認
3. ファイル名の大文字小文字を確認
4. `flutter clean` → `flutter pub get` を実行

## サポート

ファイルの変換が必要な場合（例：WAV→MP3）、以下のツールを使用できます：
- ffmpeg: `ffmpeg -i input.wav output.mp3`
- Audacity: https://www.audacityteam.org/ (GUIツール)
- Online-Convert: https://audio.online-convert.com/ (オンライン変換)
