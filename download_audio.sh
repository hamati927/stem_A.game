#!/bin/bash
# Download free BGM and sound effects for the rhythm game

set -e

AUDIO_DIR="flutter_application_1/assets/audio"
mkdir -p "$AUDIO_DIR"

echo "フリーBGMと効果音をダウンロード中..."

# フリーのゲームBGMをダウンロード（Pixabay Music）
# https://pixabay.com/users/evgeniy_1-6449838/の作品を例として使用
# または、ローカルで生成

# bgm.mp3をダウンロード（30秒のゲーム用ループBGM）
if [ ! -f "$AUDIO_DIR/bgm.mp3" ]; then
    echo "BGMをダウンロード中... (Pixabay Music)"
    # curl -L https://download.pixabay.com/mp3/upbeat-gaming-bg-music-150bpm-7008.mp3 -o "$AUDIO_DIR/bgm.mp3" 2>/dev/null || {
    echo "警告: BGMのダウンロードに失敗しました。以下の手順で手動ダウンロードしてください："
    echo "1. https://pixabay.com/music/ を開く"
    echo "2. 検索: 'game' または 'rhythm'"
    echo "3. ダウンロード対象:"
    echo "   - ゲーム向けの短いBGM（30秒〜1分推奨）"
    echo "4. ファイルを $AUDIO_DIR/bgm.mp3 に配置"
    echo ""
    # }
fi

# success.wavをダウンロード（成功音）
if [ ! -f "$AUDIO_DIR/success.wav" ]; then
    echo "効果音をダウンロード中... (success sound)"
    # curl -L https://freepd.com/api/download/audio/xyz -o "$AUDIO_DIR/success.wav" 2>/dev/null || {
    echo "警告: 効果音のダウンロードに失敗しました。以下の手順で手動ダウンロードしてください："
    echo "1. https://freepd.com/ または https://freesound.org/ を開く"
    echo "2. 検索: 'success' または 'beep' または 'ding'"
    echo "3. 短い効果音（1秒以下推奨）をダウンロード"
    echo "4. ファイルを WAV 形式に変換（必要に応じて ffmpeg を使用）"
    echo "5. ファイルを $AUDIO_DIR/success.wav に配置"
    echo ""
    # }
fi

echo ""
echo "=== フリーBGMの推奨リソース ==="
echo "Pixabay Music: https://pixabay.com/music/"
echo "  - ユーザー登録不要、CC0ライセンス"
echo "  - 推奨: Game, Electronic, Upbeat カテゴリ"
echo ""
echo "Freepd.com: https://freepd.com/"
echo "  - CC0ライセンス、ゲーム向けBGM多数"
echo "  - Tag: 'game', 'loop' で検索"
echo ""
echo "OpenGameArt.org: https://opengameart.org/content/type/audio/music"
echo "  - ゲーム向けのBGMが豊富"
echo ""
echo "FreeSound.org: https://freesound.org/"
echo "  - 効果音が豊富（CC0またはCC-BY）"
echo ""

echo "📁 $AUDIO_DIR/ に以下ファイルを配置してください："
echo "  - bgm.mp3 (ゲームBGM, 30秒〜1分程度のループ)"
echo "  - success.wav (成功音, 1秒以下)"
echo ""
echo "配置完了後、flutter pub get && flutter build apk を実行してください。"
