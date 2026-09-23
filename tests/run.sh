#!/bin/zsh
# Offline tests for sirius-config, sirius-lease, and the guard hook.
set -u
cd "${0:A:h}/.."
fail=0
check() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fail=1; fi }

export SIRIUS_HOME="$(mktemp -d)"
mkdir -p "$SIRIUS_HOME/repos"
cp templates/config.yaml "$SIRIUS_HOME/config.yaml"
cp templates/repo.yaml "$SIRIUS_HOME/repos/acme__my-repo.yaml"

jget() { python3 -c "import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split('.'): d=d[k]
print(d)" "$1"; }

check "template validates" 'bin/sirius-config validate >/dev/null'
check "manual ceiling caps auto" '
  sed -i "" "s/^  mode: manual/  mode: auto/" "$SIRIUS_HOME/repos/acme__my-repo.yaml"
  [[ $(bin/sirius-config repo acme/my-repo | jget merge.mode) == manual ]]'
check "auto without reviewer identity falls back" '
  sed -i "" "s/^merge: manual/merge: auto/" "$SIRIUS_HOME/config.yaml"
  bin/sirius-config repo acme/my-repo | grep -q "needs identities.reviewer"'
check "same implementer and reviewer falls back" '
  sed -i "" "s/^reviewer: codex/reviewer: claude/" "$SIRIUS_HOME/config.yaml"
  bin/sirius-config repo acme/my-repo | grep -q "different from the implementer"'
check "repo review.reviewer overriding the global reviewer is checked against the implementer too" '
  sed -i "" "s/^reviewer: claude/reviewer: codex/" "$SIRIUS_HOME/config.yaml"
  sed "s#repo: acme/my-repo#repo: acme/samereviewer#; s/^  reviewer: \"\"/  reviewer: claude/; s/^  mode: manual/  mode: auto/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__samereviewer.yaml"
  bin/sirius-config repo acme/samereviewer | grep -q "different from the implementer"'
rm -f "$SIRIUS_HOME/repos/acme__samereviewer.yaml"
check "needs_review forces human gate, manual merge, and draft reply" '
  sed -i "" "s/^needs_review: false/needs_review: true/" "$SIRIUS_HOME/repos/acme__my-repo.yaml"
  out=$(bin/sirius-config repo acme/my-repo)
  [[ $(print -r -- "$out" | jget implement.gate) == human ]] &&
  [[ $(print -r -- "$out" | jget merge.mode) == manual ]] &&
  [[ $(print -r -- "$out" | jget reply.mode) == draft ]]'
check "reply send is capped to draft by config.yaml default" '
  sed "s#repo: acme/my-repo#repo: acme/replytest#; s/needs_review: false/needs_review: false/; s/^  mode: draft/  mode: send/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__replytest.yaml"
  bin/sirius-config repo acme/replytest | grep -q "reply capped at .draft. by config.yaml"'
rm -f "$SIRIUS_HOME/repos/acme__replytest.yaml"
check "reply send allowed when config.yaml also allows send" '
  sed -i "" "s/^reply: {mode: draft}/reply: {mode: send}/" "$SIRIUS_HOME/config.yaml"
  sed "s#repo: acme/my-repo#repo: acme/sendtest#; s/^  mode: draft/  mode: send/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__sendtest.yaml"
  [[ $(bin/sirius-config repo acme/sendtest | jget reply.mode) == send ]]'
rm -f "$SIRIUS_HOME/repos/acme__sendtest.yaml"
sed -i "" "s/^reply: {mode: send}/reply: {mode: draft}/" "$SIRIUS_HOME/config.yaml"
check "wildcard source rejected" '
  sed "s#repo: acme/my-repo#repo: acme/bad#; s/C0123456789/C*/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__bad.yaml"
  ! bin/sirius-config validate >/dev/null'
rm -f "$SIRIUS_HOME/repos/acme__bad.yaml"
check "repo field must match file name" '
  sed "s#repo: acme/my-repo#repo: acme/other-name#" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__mismatch.yaml"
  bin/sirius-config validate | grep -q "file name must be"'
rm -f "$SIRIUS_HOME/repos/acme__mismatch.yaml"
check "second file claiming the same repo is rejected" '
  cp templates/repo.yaml "$SIRIUS_HOME/repos/acme__my-repo-again.yaml"
  bin/sirius-config validate | grep -q "file name must be"'
rm -f "$SIRIUS_HOME/repos/acme__my-repo-again.yaml"
check "unknown top-level key rejected" '
  print "name: leftover" >> "$SIRIUS_HOME/repos/acme__my-repo.yaml"
  ! bin/sirius-config validate >/dev/null'
sed -i "" "/^name: leftover/d" "$SIRIUS_HOME/repos/acme__my-repo.yaml"

check "lease excludes a second run" 'bin/sirius-lease acquire a >/dev/null && ! bin/sirius-lease acquire b >/dev/null'
check "lease release by owner only" '! bin/sirius-lease release b >/dev/null && bin/sirius-lease release a >/dev/null'
check "lease scopes are independent" '
  bin/sirius-lease acquire r1 --scope repo:acme/one >/dev/null &&
  bin/sirius-lease acquire r2 --scope repo:acme/two >/dev/null &&
  ! bin/sirius-lease acquire r3 --scope repo:acme/one >/dev/null &&
  bin/sirius-lease release r1 --scope repo:acme/one >/dev/null &&
  bin/sirius-lease release r2 --scope repo:acme/two >/dev/null'
check "line scope is a separate lock from a repo scope" '
  bin/sirius-lease acquire l1 --scope line >/dev/null &&
  bin/sirius-lease acquire r1 --scope repo:acme/one >/dev/null &&
  bin/sirius-lease release l1 --scope line >/dev/null &&
  bin/sirius-lease release r1 --scope repo:acme/one >/dev/null'
check "lease status reports the requested scope" '
  bin/sirius-lease acquire s1 --scope line >/dev/null
  bin/sirius-lease status --scope line | grep -q "\"scope\": \"line\""
  bin/sirius-lease release s1 --scope line >/dev/null'

g() { print -r -- "$1" | scripts/guard >/dev/null 2>&1; }
check "guard blocks gh pr merge" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"'
check "guard blocks merge API" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh api -X PUT repos/o/r/pulls/1/merge\"}}"'
check "guard blocks --admin" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr review 1 --admin\"}}"'
check "guard blocks force push" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push -f origin x\"}}"'
check "guard allows normal push" 'g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin sirius/issue-1-x\"}}"'
check "guard blocks shell write to settings" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $SIRIUS_HOME/config.yaml\"}}"'
check "guard blocks ruleset PATCH" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh api -X PATCH repos/o/r/rulesets/1\"}}"'
check "guard allows ruleset read" 'g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh ruleset list -R o/r\"}}"'
check "guard blocks \$HOME write to settings" '! print -r -- "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > \\\"\$HOME/.sirius/config.yaml\\\"\"}}" | SIRIUS_HOME=$HOME/.sirius scripts/guard 2>/dev/null'
check "negative approvals rejected" '
  sed "s#repo: acme/my-repo#repo: acme/neg#; s/  approvals: 0/  approvals: -1/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__neg.yaml"
  bin/sirius-config validate | grep -q "non-negative"'
rm -f "$SIRIUS_HOME/repos/acme__neg.yaml"
check "misspelled merge rule key rejected" '
  sed "s#repo: acme/my-repo#repo: acme/typo#; s/  approvals: 0/  approval: 2/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__typo.yaml"
  bin/sirius-config validate | grep -q "unknown keys"'
rm -f "$SIRIUS_HOME/repos/acme__typo.yaml"
check "reply.mode value rejected" '
  sed "s#repo: acme/my-repo#repo: acme/badreply#; s/  mode: draft/  mode: maybe/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__badreply.yaml"
  bin/sirius-config validate | grep -q "reply.mode must be"'
rm -f "$SIRIUS_HOME/repos/acme__badreply.yaml"
check "investigate.knowledge shape enforced" '
  sed "s#repo: acme/my-repo#repo: acme/badknow#; s/  knowledge: \[\]/  knowledge: [{where: x}]/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__badknow.yaml"
  bin/sirius-config validate | grep -q "knowledge\[0\]: missing keys"'
rm -f "$SIRIUS_HOME/repos/acme__badknow.yaml"
check "review.reviewer must be a known agent" '
  sed "s#repo: acme/my-repo#repo: acme/badreviewer#; s/  reviewer: \"\"/  reviewer: gemini/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__badreviewer.yaml"
  bin/sirius-config validate | grep -q "review.reviewer must be"'
rm -f "$SIRIUS_HOME/repos/acme__badreviewer.yaml"
check "forbidden must be a list of strings" '
  sed "s#repo: acme/my-repo#repo: acme/badforbid#; s/^forbidden: \[\]/forbidden: {x: y}/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__badforbid.yaml"
  bin/sirius-config validate | grep -q "forbidden must be a list"'
rm -f "$SIRIUS_HOME/repos/acme__badforbid.yaml"
check "concurrent acquire yields one owner" '
  [[ $(for i in 1 2 3 4 5 6 7 8; do bin/sirius-lease acquire c$i & done 2>/dev/null; wait) == *acquired\"\:\ true* ]] &&
  [[ $(for i in 1 2 3 4 5 6 7 8; do bin/sirius-lease acquire d$i & done 2>/dev/null; wait) != *acquired\"\:\ true* ]]'
# Title-prefix gates. The template repo is human/manual; "fast" is auto/auto.
sed "s#repo: acme/my-repo#repo: acme/fast#; s/^  gate: human/  gate: auto/; s/^  mode: manual/  mode: auto/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__fast.yaml"
sed -i "" "/^needs_review/d" "$SIRIUS_HOME/repos/acme__fast.yaml"
sed -i "" "s/^reviewer: claude/reviewer: codex/; s/^implement_gate: human/implement_gate: auto/" "$SIRIUS_HOME/config.yaml"
sed -i "" "s/^identities: {}/identities: {reviewer: {login: bot, gh_config_dir: \/tmp\/x}}/" "$SIRIUS_HOME/config.yaml"
gt() { g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"}}"; }
check "guard blocks [implement] on a human-gate repo" '! gt "gh issue edit 1 -R acme/my-repo --title \\\"[implement] x\\\""'
check "guard allows [implement] on an auto-gate repo" 'gt "gh issue create -R acme/fast --title \\\"[implement] x\\\" --body y"'
check "guard requires -R for [implement]" '! gt "gh issue edit 1 --title \\\"[implement] x\\\""'
check "guard blocks [merge] on a manual repo" '! gt "gh pr edit 2 -R acme/my-repo -t \\\"[merge] x\\\""'
check "guard allows [merge] on an auto repo" 'gt "gh pr edit 2 -R acme/fast --title \\\"[merge] x\\\""'
check "guard allows plain titles" 'gt "gh issue edit 1 -R acme/my-repo --title \\\"Fix login\\\""'
check "guard blocks title prefix via API" '! gt "gh api -X PATCH repos/acme/fast/issues/1 -f title=[implement]x"'
rm -f "$SIRIUS_HOME/repos/acme__fast.yaml"
check "guard asks on Write to settings" '
  print -r -- "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SIRIUS_HOME/repos/x.yaml\"}}" | scripts/guard | grep -q "\"ask\""'

rm -rf "$SIRIUS_HOME"
exit $fail
