# CI: Android APK の自動ビルド

このリポジトリには GitHub Actions のワークフローを用意しています。ワークフローは push（`main` または `master`）時と手動トリガー（`workflow_dispatch`）で実行され、**debug APK（unsigned）** をビルドして Actions の成果物としてアップロードします。

## 使い方
1. 変更をリモート（GitHub）に push してください（例: `git push origin main`）。
2. GitHub の `Actions` タブで `Build Debug Android APK` ワークフローの実行を確認できます。
3. 実行完了後、該当ワークフロー実行ページの `Artifacts` から `app-debug.apk` をダウンロードできます。

## 備考
- このワークフローは **debug APK** を作成します。Play ストア公開向けの署名済みリリース APK を作る場合は別途 keystore を用意し、`gradle.properties` / `android/app/build.gradle` に署名設定を追加する必要があります。
- ビルドに失敗する場合、ログ（Actions 実行ログ）を貼っていただければ解析して対処します。
