---
name: stop
description: ~/.sirius/STOPを作ってSiriusを直ちに止める。これがあるとすべての実行とすべてのマージが止まる。引数"resume"を付けると削除する。/sirius:stop、またはユーザーがSiriusを止めるよう言ったときに使う。
disable-model-invocation: true
argument-hint: "[resume]"
---

# Siriusを止める

引数なしのとき:

1. `touch ~/.sirius/STOP`。まずこれを、他の何よりも先に行う。
2. `sirius-lease status --scope run` を表示する。すでに進行中の実行は、今のステップを終わらせてから止まる。このファイルがある間、`sirius-merge` はすべてのマージを拒否し、次の実行は直ちに終了する。
3. スケジューラが `launchd` なら、完全に止めるために `launchctl bootout gui/$(id -u)/ai.sirius.tick` もユーザーに伝える。

`resume` のとき:

1. `sirius-config validate` を表示する。エラーがあれば、次の実行はそこで止まると伝える。
2. ユーザーに確認してから `rm ~/.sirius/STOP` する。
