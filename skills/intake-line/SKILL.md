---
name: intake-line
description: ~/.sirius/repos/*.yamlに列挙されたLINEチャットを、ネイティブのmacOS LINEアプリで凍結された時間窓だけ読み、未解決の依頼をcreate-issue経由で重複排除しつつGitHub Issueにする。Sirius runスキルから呼ばれ、Computer Useのあるローカルセッションが必要。
user-invocable: false
---

# LINE取り込み

まず[取り込み契約](../../references/intake-contract.md)を完全に読む。このファイルはLINE固有の内容だけを追加する。

## ツールと制限

- ネイティブのmacOS LINEアプリに対してComputer Useだけを使う。ブラウザ、他アプリのOCR、DBリーダー、LINE Messaging APIは使わない。
- ローカルのMacセッションが必要。クラウドのルーチンでは `disabled: no desktop` を返し、チェックポイントは変更しない。
- LINEへのComputer Useアクセスが許可されていない場合は `unavailable` を返し、チェックポイントは変更しない。

LINEは読み取り専用のまま扱う: 送信、リアクション、送信取消、転送、通話、ダウンロード、入力欄への入力は一切しない。

## 収集

1. 何かを開く前に、一覧にある各チャット名の未読バッジ数を記録する。チャットを開くと未読が消えることがある。
2. 一覧にあるチャット名と完全一致する行だけを開く。同じ名前の行が2つあれば、そのチャットは中断して曖昧さを報告する。
3. 開いた後、チャットヘッダーがそのチャット名と完全一致することを確認する。
4. `last_completed_cutoff` より古いメッセージになるまで上へスクロールし、そこから `run_cutoff` まで前方向に読む。
5. チャット名、タイムスタンプ、送信者、正規化した表示テキストで重複排除する。
6. グループチャットでは、解釈に関わる事実ごとに送信者を記録する。

LINEには信頼できるパーマリンクがない。`resume_cursor` は次の未処理メッセージの `{chat, timestamp, sender, text_hash}` とする。

## パケット固有の項目

`source: line`、`conversation` にチャット名、`workspace: null`、`permalink: null` を設定する。非公開リポジトリでは、Issueにチャット名・送信者・時刻を書いてよい。公開リポジトリでは `create-issue` がそれらを取り除く。

## reply.mode について

LINEには下書きを送る仕組みがない。対象リポジトリの `reply.mode` が `draft` のときは、LINEアプリを操作して送信することは絶対にせず、提案する返信文をIssueかこの実行のレポートに書くだけにする。`send` が設定されていても、LINE用の送信手段が用意されるまでは同じ扱いにし、その旨をレポートに明記する。

開く前に記録した未読数と、どのバッジが開いたことで消えた可能性があるかを報告する。
