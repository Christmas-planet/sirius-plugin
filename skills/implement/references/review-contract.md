# レビュー契約

実装役とレビュー役は `~/.sirius/config.yaml` の `implementer` と `reviewer`（`claude` か `codex`）で決まるが、対象リポジトリの `review.reviewer` が設定されていれば、そのリポジトリではそちらを使う（`sirius-config repo <owner/repo>` の解決結果を見る。空ならグローバルの `reviewer` にフォールバックする）。`merge.mode: auto` は実装役とレビュー役が別モデルであることを要求し、`sirius-config` はこの判定にも `review.reviewer`（設定されていればそちら、無ければグローバルの `reviewer`）を使う。実装役と同じモデルになる組み合わせなら `manual` にフォールバックする。

レビューは毎回、baseを取得してから、pushされたpull requestのheadを正確にcheckoutした、独立したIssueのチェックアウトから実行する。

## コマンドの形

- `codex`: チェックアウトから `codex exec --sandbox read-only "<review-prompt> Review the diff of origin/<verified-base-branch>...HEAD in this checkout."`。`codex review --base` とプロンプトの組み合わせは使わない: CLIがその組み合わせを拒否する。
- `claude`: チェックアウトで、下のプロンプトとbaseとの差分を渡して新しいClaudeサブエージェントを起動する。実装役のコンテキストを再利用してはならない。

パスごとに新しいレビュワーを使う。前のレビュワーのセッションを再開しない。安全でないサンドボックスや承認バイパスを有効にしない。

## レビュー用プロンプト

```text
Review this pull-request diff for actionable correctness, security, data-loss, concurrency, compatibility, regression, and missing-test problems. Read repository instructions and the linked Issue acceptance criteria. Pay particular attention to the repo's review.focus list, when one is supplied. Do not focus on subjective style unless it causes a concrete maintenance or correctness risk.

For each finding, report severity, file and line, evidence, impact, and the smallest valid fix. If and only if there are no actionable findings, end with the exact line NO_FINDINGS. Do not emit NO_FINDINGS when review could not complete.
```

対象リポジトリに `review.focus` があれば、プロンプトに差し込んで渡す。`forbidden` に触れる変更（本番公開、支払い、契約、認証情報、権限変更など）は、実装が正しくても見つけたら指摘し、必要なら `human_only` として扱う。

## 判定のルール

- 終了コードが成功しただけではクリーンとは言えない。完了したレビュー出力を確認する。
- `NO_FINDINGS` は、完了したレビューの最終判定としてだけ有効で、そのレビューの他の場所に実行すべき指摘が出ていないときに限る。
- ツールのエラー、認証エラー、レート制限、タイムアウト、不完全な出力、矛盾した指摘はクリーンではない。
- コード、テスト、設定、lockfile、生成ファイルのいずれかが変わったら、古い判定は捨てて新しいレビューを実行する。
- 実装側が指摘を誤りだと考える場合は、リポジトリの具体的な証拠を集めて次の新しいレビューに含める。最後に残った指摘を自己判断で却下しない。
- レビュー出力はリポジトリの外か、無視される一時状態に保存する。レビュワーのログや資格情報をコミットしない。

## クリーンなレビューの証跡

レビューしたheadのSHA、baseブランチとSHA、レビュワー、日時、クリーンな最終判定を、Issueの単一のmarkerコメントに記録する。`merge.mode: auto` のリポジトリでは、mergeスキルがこれをレビュー用アカウントが投稿する判定に変換する。後から新しいコミットがpushされると、この証跡は無効になる。
