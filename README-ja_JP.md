# Rootless-DevBox（特定の/外部nixキャッシュフォルダー付き）

sudoやroot権限なしでルートレス環境にDevboxを自動インストールできるシンプルなソリューションです。元のバージョン: https://github.com/nebstudio/Rootless-DevBox

**フォーク情報:**
https://github.com/twoelz によるこのフォークは、外部ストレージのインストールをサポートし、全体的なインストール体験を向上させるためのいくつかの機能強化を追加します。主な追加機能には以下が含まれます:

**主な機能:**
1. **カスタムNixストア場所**: ハードコードされた`~/.nix`の代わりに、外部ストレージ（例：42 schoolの`/sgoinfre`）にNixストアをインストールするためのインタラクティブプロンプト
2. **スマートキャッシュシンボリックリンク**: キャッシュのみを外部ストレージにシンボリックリンクし、重要なデータベースをローカルに保持
3. **マルチシェルサポート**: bash、zsh、fishシェルを設定（オリジナルはbashのみサポート）
4. **中国ネットワークミラー**: 中国本土のユーザー向けのオプションのSJTU/Tsinghuaミラー
5. **自動chroot機能**: シェル起動時のnix-chrootへのオプション自動エントリ
6. **強化されたアンインストーラー**: カスタムインストール場所を検出し、すべてのコンポーネントを安全に削除


以下は、シンボリックリンクアプローチの詳細な説明です:

カスタムロケーション（例：外部ストレージ）にNixをインストールする際、インストーラーはNixキャッシュディレクトリのシンボリックリンクを作成します:

~/.cache/nix → <カスタムロケーション>/cache/nix

**なぜキャッシュのみ（データ/データベースは含まない）:**

- キャッシュディレクトリ: 大きい（GB単位）、再生成可能、クリアしても安全 → 外部ストレージへ
- データディレクトリ: 小さい（MB単位）、重要なSQLiteデータベースを含む → 信頼性とパフォーマンスのためローカルに保持

**メリット:**

- スペース節約: Nixのダウンロードキャッシュ（ストア以外で最大の消費者）を外部ストレージに配置
- 一貫性: グローバルNixコマンドとnix-chrootの両方が同じキャッシュを使用し、重複を防止
- 分離: Nixキャッシュのみがリダイレクトされ、他のアプリケーションは通常通り~/.cacheを使用
- 信頼性: 重要なデータベースは高速で信頼性の高いローカルストレージ（~/.local/share/nix）に保持
- Nix準拠: Nixストア自体（~/.nixまたはカスタムロケーション）は実際のディレクトリのまま（シンボリックリンクではない）

**動作:**

- デフォルトインストール（~/.nix）: シンボリックリンクは作成されず、標準のXDGロケーションを使用
- カスタムインストール: キャッシュシンボリックリンクを作成し、既存の~/.cache/nixディレクトリをバックアップ
- データベース/状態は安全のため~/.local/share/nixに保持

このアプローチは、システム全体のすべてのアプリケーションに影響を与えるグローバルなXDG_CACHE_HOMEおよびXDG_DATA_HOME変数の設定を回避します。

**シェル設定:**
インストーラーはシェルのdotfiles（bash/zsh/fish）に設定を追加します。この設定は:
- `~/.local/bin`と`~/.nix-profile/bin`をPATHに追加（devbox/nixコマンドを実行するため）
- Nix自身の環境設定をソース
- XDG変数をグローバルに設定しない（キャッシュリダイレクトには代わりにシンボリックリンクを使用）

[![GitHub License](https://img.shields.io/github/license/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/blob/main/LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/nebstudio/Rootless-DevBox?style=social)](https://github.com/nebstudio/Rootless-DevBox/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/nebstudio/Rootless-DevBox)](https://github.com/nebstudio/Rootless-DevBox/issues)

## Rootless-DevBoxとは？

Rootless-DevBoxは、[Devbox](https://github.com/jetify-com/devbox) をroot権限なしで（共有ホスティング、大学のシステム、制限された企業環境など）インストール・利用できるプロジェクトです。[nix-user-chroot](https://github.com/nix-community/nix-user-chroot) を活用し、NixとDevboxをユーザー権限のみでコンテナ化環境にて動作させます。

## 特徴

- 🛡️ **root不要**: sudoやroot権限なしでDevboxをインストール・利用可能
- 🔄 **分離環境**: システムに影響を与えず、パッケージを分離環境で実行
- 🚀 **簡単セットアップ**: 1つのスクリプトで全自動セットアップ
- 💻 **クロスプラットフォーム**: 多様なLinuxディストリビューション・アーキテクチャ対応
- 🔒 **安全**: システムファイルを変更せず、ユーザー環境のみを変更

## クイックスタート

> **注意:**  
> インストールスクリプトは**対話式**で、複数のステップで入力を求めます。  
> これは、インストール中に選択肢を与え、各ステップを理解し、環境に合わせて柔軟に対応できるように設計されています。  
> プロンプトが多くても複雑に感じないでください。これは互換性とユーザーコントロールを最大化するためのものです。

以下のコマンドをターミナルで実行してください：

```bash
# インストーラーをダウンロード
curl -o rootless-devbox-installer.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/install.sh

# 実行権限を付与
chmod +x rootless-devbox-installer.sh

# インストーラーを実行
./rootless-devbox-installer.sh
```

## 仕組み

Rootless-DevBoxは主に3つのステップで環境を構築します：

1. **nix-user-chrootのインストール**: ユーザースペースchroot環境を作るツールをダウンロード・設定
2. **Nix環境の作成**: ユーザーディレクトリにNixのコンテナ環境を構築
3. **Devboxのインストール**: この環境内にDevboxをインストール

インストール後は、`nix-chroot`コマンドで開発環境にアクセスできます。

## 使い方

### Nix環境に入る

インストール後、以下を実行：

```bash
nix-chroot
```

プロンプトが以下のように変わります：

```
(nix-chroot) user@hostname:~$
```

### Devboxの利用

nix-chroot環境内でDevboxを利用できます：

```bash
# ヘルプ表示
devbox help

# 新規プロジェクト初期化
devbox init

# パッケージ追加
devbox add nodejs python

# 開発環境シェル起動
devbox shell
```

### 環境からの退出

```bash
exit
```

## 必要条件

- LinuxベースのOS
- Bashシェル
- インターネット接続
- root権限不要

## サポートアーキテクチャ

- x86_64
- aarch64/arm64
- armv7
- i686/i386

## トラブルシューティング

**Q: nix-chrootが見つからないと言われる**  
A: `~/.local/bin`がPATHに含まれているか確認してください。`source ~/.bashrc`を実行するか、ターミナルを再起動してください。

**Q: nix-user-chrootのダウンロードに失敗する**  
A: ネットワーク接続を確認してください。問題が続く場合は[リリースページ](https://github.com/nix-community/nix-user-chroot/releases)から手動でバイナリをダウンロードしてください。

**Q: Nix環境でパッケージがインストールできない**  
A: システムのクォータやディスク容量制限の可能性があります。`df -h ~`で空き容量を確認してください。

さらなるサポートが必要な場合は[issueを作成](https://github.com/nebstudio/Rootless-DevBox/issues)してください。

## アンインストール

Rootless-DevBoxを削除するには2つの方法があります：

### 方法1: アンインストールスクリプトを使用

アンインストールスクリプトを提供しています：

```bash
# アンインストーラーをダウンロード
curl -o rootless-devbox-uninstaller.sh https://raw.githubusercontent.com/nebstudio/Rootless-DevBox/main/uninstall.sh

# 実行権限を付与
chmod +x rootless-devbox-uninstaller.sh

# アンインストーラーを実行
./rootless-devbox-uninstaller.sh
```

### 方法2: 手動アンインストール（推奨）

1. **インストール済みバイナリを削除**:
   ```bash
   rm -f ~/.local/bin/devbox
   rm -f ~/.local/bin/nix-chroot
   rm -f ~/.local/bin/nix-user-chroot
   ```

2. **Nixディレクトリのクリーンアップ**（任意、全Nixパッケージ削除）:
   ```bash
   rm -rf ~/.nix
   ```

3. **⚠️ 重要: シェル設定ファイルの編集**（`~/.bashrc`や`~/.zshrc`など）:

   - PATH追加行を削除:
     ```bash
     export PATH="$HOME/.local/bin:$PATH" # Added by Rootless-DevBox
     ```
   - PS1プロンプトブロックを削除:
     ```bash
     # Rootless-DevBox nix-chroot environment indicator
     if [ "$NIX_CHROOT" = "1" ]; then
       PS1="(nix-chroot) \[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
     fi
     ```

   編集後、以下を実行:
   ```bash
   source ~/.bashrc
   ```

> **注意:** アンインストールスクリプトは自動で設定ファイルを編集しますが、**手動で確認・削除することを推奨します**。

アンインストール後はターミナルを再起動してください。

## コントリビュート

貢献は大歓迎です！Pull Requestをお送りください。

1. リポジトリをフォーク
2. ブランチ作成: `git checkout -b feature/your-feature`
3. 変更をコミット: `git commit -m 'Add your feature'`
4. ブランチをプッシュ: `git push origin feature/your-feature`
5. Pull Request作成

## 謝辞

本プロジェクトは以下の素晴らしいプロジェクトに支えられています：

- [nix-user-chroot](https://github.com/nix-community/nix-user-chroot)
- [Devbox](https://github.com/jetify-com/devbox)
- [Nix](https://nixos.org/)

## ライセンス

MITライセンスです。詳細は[LICENSE](LICENSE)をご覧ください。

## セキュリティについて

Rootless-DevBoxはユーザーホームディレクトリ内のファイルのみを変更し、root権限を必要としません。制限された環境でも安全に利用できます。

---

⭐ このプロジェクトが役立った場合は、ぜひGitHubでスターをお願いします！ ⭐

[nebstudio](https://github.com/nebstudio) 制作 ❤️