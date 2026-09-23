---
name: create-issue
description: Sirius取り込みからのアクションパケット1件（workspaceのソースでは同じ依頼から分けたパケットのグループ）を検証し、機微な内容を取り除き、重複を検索して、パケットごとに証跡付きのGitHub Issueを最大1件作成し、同じ依頼のIssue同士をリンクする。チャットソースは読まず、実装も行わない。
user-invocable: false
---

# Issue作成

アクションパケット1件を、最大1件のGitHub Issueに変換する。workspace のソースからは、同じ依頼をリポジトリごとに分けたパケットのグループ（共通の `request_group`）がまとめて渡される。そのときも1パケット=最大1件で、下の「グループ」の手順でまとめて扱う。ソーススキルはメッセージを集めるだけで、Issueへの書き込みはすべてこのスキルが持つ。

## ツール

認証済みの `gh` CLI か、接続済みのGitHubツールがあればそれを使う。ブラウザは使わない。

## 必須の入力

[取り込み契約](../../references/intake-contract.md)の形をしたアクションパケットと、`sirius-config repo <owner/repo>` で得た、そのリポジトリの解決済み設定（`forbidden`、`investigate.ask_user_when`、`notes` を含む）。

ここからSlackやLINEを読み直さない。フィールドが欠けていたら、ソーススキルが集めるべきものを添えて `blocked` を返す。

## 検証

次のすべてが成り立つときだけIssueを作る:

1. 作業が未解決で、追跡が必要である。
2. パケットの `repo` が扱っているリポジトリの範囲内である。
3. 問題と完了条件を書くのに十分な、裏付けのある文脈がある。
4. `forbidden` に挙がっている行為を求めるものではない。求めている場合は、その旨を明記した上で `not_actionable` を返す。
5. 秘密情報や不適切な私的データなしに本文を書ける。

FYIや了解の返事、解決済みの項目、成功の通知、チャットの返信だけで済むものには `not_actionable` を返す。チャットの返信だけで済むもの（依頼者が答えを待っている質問、確認、日程調整）のときだけ `reply_only: true` を付け、取り込み側が返信できるようにする。

## リポジトリ

パケットの `repo` は、そのソースの持ち主が許す範囲の1つのリポジトリでなければならない: リポジトリが持つソースならそのリポジトリ、workspace が持つソースならその workspace のメンバー（`candidate_repos`）のどれか。範囲外なら `blocked` を返す。渡された `repo` 以外のリポジトリに作成したり、カレントディレクトリのリモートにフォールバックしたりは絶対にしない。

`repo: null` のパケット（取り込み側が振り分けに確信を持てなかったもの）は、検索も本文作成もせず `confirmation_required` を返す。質問は「この依頼をどのリポジトリで対応するか」、`options` は `candidate_repos` の各リポジトリと、複数にまたがる場合の組み合わせ、それぞれの根拠。回答が来たら、取り込み側がその回答どおりにパケットを分け直して再度渡す。

## グループ（workspace のソース）

1. `depends_on` に従って、依存される側から順に処理する。各パケットの検証・私的データ・重複排除は1件のときと同じ。
2. 本文の末尾（markerコメントの前）に次の節を足す。同じグループで先に作成・重複判定済みのIssueはリンクを書く。

   ```md
   ## Related
   - 同じ依頼: owner/repo#<n>, owner/repo#<n>
   - Depends on owner/repo#<n>
   ```

   `Depends on` の行は `depends_on` にあるリポジトリのIssueについてだけ書く。`implement` スキルはこの行を依存関係として読み、依存先がクローズされるまで着手しない。
3. 全パケットが終わったら、先に作ったIssueの `## Related` に、後から作ったIssueへのリンクを `gh issue edit -R owner/repo --body-file` で追記する。既存の本文は変えない。
4. どれかが `confirmation_required` になったら、そのグループの残りは処理せず止める（先に作成したものはそのまま残し、結果に含める）。回答後に残りを処理する。
5. `[implement]` を付けるかどうかはパケットごとに、そのリポジトリの `implement.gate` で決める。依存しているIssueにも付けてよい。着手の順序は `Depends on` の行が守る。

## 私的データを守る

まずリポジトリの公開設定を `gh repo view <repo> --json visibility` で確認する。

- 資格情報、トークン、クッキー、秘密鍵、ワンタイムパスワード、パスワード、個人の住所、無関係な会話は常に取り除く。省略ではなく削除する。
- 公開リポジトリでは、加えて私的なパーマリンク、チャット名、顧客名、内部ホスト名、抜粋も取り除く。残った内容で行動できないなら `confirmation_required` を、想定する文面を添えて返す。
- 引用ではなく言い換える。

## 重複排除

作成する前に、対象リポジトリのオープンIssueを次の観点で検索する:

- 安全に検索できる場合はソースのパーマリンクやソース識別子;
- エラーコード、チケット番号、デプロイ名などの特徴的な識別子;
- 提案するタイトルの主要な語句。

パケットがリグレッションを示している可能性があるときは、最近クローズされたIssueも確認する。すでに追跡しているオープンIssueがあれば `duplicate` をそのURLとともに返し、コメントはしない。クローズ済みのものが一致し、問題が再発しているなら、その古いIssueへリンクする新しいIssueを作る。

## 作成する本文

独立したアクション1件につきIssue1件。タイトルは成果に焦点を当て、80文字程度以内にする。「Slack」や「LINE」を接頭辞にしない。

```md
## Summary
<verified problem or request, and why it matters>

## Evidence
- Observed: <facts, times, errors>
- Source: <minimal safe reference>

## Required action
<the work>

## Acceptance criteria
- [ ] <verifiable result>

## Open questions
- <non-blocking gaps>

<!-- sirius-source: <source>:<stable id hash> -->
```

推測は推測だと明記する。要求内容を変えるような受入条件を勝手に作らない。

## タイトル接頭辞、ラベルなし

Siriusはラベルを使わない。タイトルにある唯一の状態は `[implement]` 接頭辞で、これが実装の合図になる。

- `implement.gate: auto`: パケットが実装候補で、受入条件が検証可能なら、タイトルの先頭に `[implement] ` を付ける。そうでなければ付けず、足りないものを「Open questions」に列挙する。
- `implement.gate: human`: `[implement]` を絶対に付けない。人がIssueを読んだ後に付ける。guard hookがこのスキルからの付与を拒否する。

`gh issue create` には常に `-R owner/repo` を渡し、guardがリポジトリのゲートを確認できるようにする。

アサインは、パケットに明示されたGitHubログインがあるときだけ行う。

## 作成と確認

`gh issue create` で作成した後、取り直して、リポジトリ、番号、状態、タイトル、URLを確認する。この確認が通るまで `created` を報告しない。

## 返す状態は必ず1つ（パケットごと）

```yaml
status: created | duplicate | not_actionable | confirmation_required | blocked
repo: <owner/repo>
issue: <number and URL>          # created, duplicate
reason: <short evidence>         # not_actionable, blocked
reply_only: <bool>               # not_actionable のとき: チャットの返信だけで済む質問・確認・日程調整なら true
confirmation_id: <stable id>     # confirmation_required
question: <one question>
options: [{value: <choice>, evidence: <why>}]
pending_packet: <the unchanged packet>
```

グループのときは、パケットごとの結果を `request_group` とともに並べて返す。

`confirmation_required` のときは、それ以上検索も本文の作成もせずに止まる。ユーザーがスキップを選んだら、次回の呼び出しは `not_actionable`（reason: `user_skipped`）を返す。
