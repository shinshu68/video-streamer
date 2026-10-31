# 配置・運用 (Windows)

サーバーを Windows 上で動かすための手順と注意点。手順が確定していない項目は「未定」とし、決まり次第更新する。

## 配置

1. Windows 上で exe をビルドする (コマンドは server/CLAUDE.md を参照)
2. 開発用の `server\bin` と分けて、exe と設定ファイル (`config.json`) を `%LOCALAPPDATA%\video-streamer\` に置く。動作中の exe はビルドで上書きできないため
3. 設定ファイルに公開フォルダのパス、ポート番号、キャッシュの置き場所を書く

server/ で次を実行する。`<設定ファイル>` には、本番用の設定を書いたファイルを指定する。

```powershell
$dir = "$env:LOCALAPPDATA\video-streamer"
```

```powershell
New-Item -ItemType Directory -Force $dir
```

```powershell
go build -o "$dir\video-streamer-server.exe" .
```

```powershell
Copy-Item <設定ファイル> "$dir\config.json"
```

## 設定ファイル

JSON 形式。既定では exe と同じフォルダの `config.json` を読む。`-config <パス>` で別のファイルを指定できる。ひな形は server/config.example.json。

```json
{
  "root": "E:\\Videos",
  "port": 8765,
  "cache": "E:\\video-streamer-cache"
}
```

| 項目 | 内容 |
| --- | --- |
| `root` | 公開フォルダのパス (外付けHDD上のフォルダ)。JSON のため `\` は `\\` と書く。`/` 区切りでもよい |
| `port` | 待ち受けるポート番号 |
| `cache` | サムネイルなどのキャッシュを置くフォルダのパス (外付けHDD上のフォルダ)。なければ作る。公開フォルダの中に置いてもよく、その場合は一覧に出さず、配信もしない。公開フォルダそのものや、公開フォルダを含むフォルダは指定できない |
| `ffmpeg` | 省略可。ffmpeg.exe のパス。省略すると PATH から探す。ffprobe.exe は ffmpeg.exe と同じフォルダから探す |

`root`・`port`・`cache` は必須で、欠けている場合は起動時にエラーで終了する。外付けHDDのドライブ文字が変わった場合は、`root` と `cache` を書き換えて対応する。

## ログ

`-log <パス>` を指定すると、ログをそのファイルに追記する。省略すると標準エラーに出す。常駐中はコンソールがないため、`%LOCALAPPDATA%\video-streamer\server.log` に書く。

## 常駐方法

タスクスケジューラで PC の起動時に実行する。ログオン前から動き、コンソールの画面も出ない。Windows サービスは外部パッケージの追加が必要なため採用しない。

登録する前に、設定ファイルの `ffmpeg` に ffmpeg.exe のフルパスを書く。ログオンせずに動くため、ユーザーの PATH に頼らない。

管理者の PowerShell で次を実行する。タスクは今のユーザーで、パスワードを保存せずに動く。

```powershell
$dir = "$env:LOCALAPPDATA\video-streamer"
```

```powershell
$action = New-ScheduledTaskAction -Execute "$dir\video-streamer-server.exe" -Argument "-log `"$dir\server.log`"" -WorkingDirectory $dir
```

```powershell
$trigger = New-ScheduledTaskTrigger -AtStartup
```

```powershell
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited
```

```powershell
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
```

```powershell
Register-ScheduledTask -TaskName video-streamer-server -Action $action -Trigger $trigger -Principal $principal -Settings $settings
```

すぐに動かすときや、止めるときは次を実行する。

```powershell
Start-ScheduledTask -TaskName video-streamer-server
```

```powershell
Stop-ScheduledTask -TaskName video-streamer-server
```

サーバーを更新するときは、タスクを止めて「配置」の `go build` をやり直し、タスクを起動する。

## ファイアウォール

Windows ファイアウォールで、サーバーのポートへの受信をプライベートネットワークに限って許可する。規則は exe のパスごとにあるため、`server\bin` の exe の規則とは別に作る。管理者の PowerShell で次を実行する。`-LocalPort` は設定ファイルの `port` に合わせる。

```powershell
New-NetFirewallRule -DisplayName video-streamer-server -Direction Inbound -Action Allow -Profile Private -Protocol TCP -LocalPort 8765 -Program "$env:LOCALAPPDATA\video-streamer\video-streamer-server.exe"
```

## IP アドレスの固定

アプリにはサーバーのアドレスを手入力して保存するため、PC の IP アドレスが変わると入力し直しになる。ルーターの DHCP 予約 (固定割り当て) で、PC の IP アドレスを固定しておく。

## ffmpeg

サムネイル生成に使う。動画の長さを調べるために、同梱の ffprobe も使う。winget でインストールし、サーバーは PATH から探す。PATH に入っていない場所の ffmpeg を使う場合や、常駐させる場合は、設定ファイルの `ffmpeg` にパスを書く。

```powershell
winget install --id Gyan.FFmpeg --exact
```

インストール後は、PATH の変更を反映するためにサーバーを起動し直す。VS Code など、インストール前から起動しているアプリのターミナルは古い PATH を引き継ぐため、アプリごと起動し直すか、ターミナルで次を実行して PATH を読み直す。

```powershell
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
```

更新は `winget upgrade --id Gyan.FFmpeg --exact` で行う。

ffmpeg がなくても一覧と再生は動き、サムネイルだけが取得できない (アプリは代わりのアイコンを表示する)。

## サムネイルのキャッシュ

生成したサムネイルは、設定の `cache` のフォルダの中の `thumbnails\` に保存する。フォルダごと消してもよく、消した分は次に要求されたときに作り直す。

## 動画の識別子の索引

動画の識別子とパスの索引は、設定の `cache` のフォルダの中の `index.json` に保存する。消してもよく、次に一覧や動画の取得を要求されたときに作り直す。

## 運用上の注意

- 外付けHDDがスリープから復帰するまで、最初のアクセスが遅れることがある
- 外付けHDDが接続されていなくてもサーバーは起動する。接続するまでアプリの一覧は表示できず、接続すれば再起動しなくても動く
