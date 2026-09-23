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
check "merge ceiling raised to auto is honored" '
  sed -i "" "s/^merge: manual/merge: auto/" "$SIRIUS_HOME/config.yaml"
  [[ $(bin/sirius-config repo acme/my-repo | jget merge.mode) == auto ]]'
check "same implementer and reviewer falls back" '
  sed -i "" "s/^reviewer: codex/reviewer: claude/" "$SIRIUS_HOME/config.yaml"
  bin/sirius-config repo acme/my-repo | grep -q "different from the implementer"'
check "repo review.reviewer overriding the global reviewer is checked against the implementer too" '
  sed -i "" "s/^reviewer: claude/reviewer: codex/" "$SIRIUS_HOME/config.yaml"
  sed "s#repo: acme/my-repo#repo: acme/samereviewer#; s/^  reviewer: \"\"/  reviewer: claude/; s/^  mode: manual/  mode: auto/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__samereviewer.yaml"
  bin/sirius-config repo acme/samereviewer | grep -q "different from the implementer"'
rm -f "$SIRIUS_HOME/repos/acme__samereviewer.yaml"
check "reply send is capped to draft by config.yaml default" '
  sed "s#repo: acme/my-repo#repo: acme/replytest#; s/^  mode: draft/  mode: send/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__replytest.yaml"
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

# Workspaces: sources shared by several repos. acme/api gets its own distinct sources.
mkdir -p "$SIRIUS_HOME/workspaces"
sed "s#repo: acme/my-repo#repo: acme/api#; s/C0123456789/C0000000API/; s/正確なチャット名/api-chat/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__api.yaml"
ws() { sed "s#acme/web#acme/my-repo#; s/C0123456789/C0000000WS1/; $1" templates/workspace.yaml > "$SIRIUS_HOME/workspaces/${2:-acme-suite}.yaml"; }
check "workspace template validates" '
  ws "" && bin/sirius-config validate | grep -q "\"acme-suite\""'
check "repo reports its workspace" '[[ $(bin/sirius-config repo acme/api | jget workspace) == acme-suite ]]'
check "workspace lookup by name" 'bin/sirius-config workspace acme-suite | grep -q "\"acme/my-repo\""'
check "source listed in a workspace and a member repo is rejected" '
  ws "s/C0000000WS1/C0123456789/" && bin/sirius-config validate | grep -q "is listed in both"'
check "source listed in two repos is rejected" '
  ws "" && sed "s#repo: acme/my-repo#repo: acme/dup#" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__dup.yaml"
  bin/sirius-config validate | grep -q "is listed in both"'
rm -f "$SIRIUS_HOME/repos/acme__dup.yaml"
check "workspace member needs a repo file" '
  ws "s#acme/api#acme/ghost#" && bin/sirius-config validate | grep -q "has no file in repos/"'
check "workspace file name must match its name" '
  ws "" other && bin/sirius-config validate | grep -q "file name must be acme-suite.yaml"'
rm -f "$SIRIUS_HOME/workspaces/other.yaml"
check "workspace reply send is capped by config.yaml" '
  ws "s/^  mode: draft/  mode: send/" && bin/sirius-config workspace acme-suite | grep -q "reply capped at .draft. by config.yaml"'
check "guard asks on Write to a workspace" '
  print -r -- "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SIRIUS_HOME/workspaces/x.yaml\"}}" | scripts/guard | grep -q "\"ask\""'
rm -rf "$SIRIUS_HOME/workspaces" "$SIRIUS_HOME/repos/acme__api.yaml"

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
cp templates/repo.yaml "$SIRIUS_HOME/repos/acme__my-repo.yaml"
sed "s#repo: acme/my-repo#repo: acme/fast#; s/^  gate: human/  gate: auto/; s/^  mode: manual/  mode: auto/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__fast.yaml"
sed -i "" "s/^reviewer: claude/reviewer: codex/; s/^implement_gate: human/implement_gate: auto/" "$SIRIUS_HOME/config.yaml"
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

# implementer: pstack hands work to pstack's poteto-agent, which reviews with its own models.
sed "s#repo: acme/my-repo#repo: acme/pstk#; s/^  mode: manual/  mode: auto/" templates/repo.yaml > "$SIRIUS_HOME/repos/acme__pstk.yaml"
check "implementer pstack validates" '
  sed -i "" "s/^implementer: claude/implementer: pstack/; s/^reviewer: codex/reviewer: claude/" "$SIRIUS_HOME/config.yaml"
  [[ $(bin/sirius-config repo acme/pstk | jget implement.implementer) == pstack ]]'
check "implementer pstack keeps merge auto" '[[ $(bin/sirius-config repo acme/pstk | jget merge.mode) == auto ]]'
check "unknown implementer rejected" '
  sed -i "" "s/^implementer: pstack/implementer: cursor/" "$SIRIUS_HOME/config.yaml"
  ! bin/sirius-config validate >/dev/null'
sed -i "" "s/^implementer: cursor/implementer: claude/; s/^reviewer: claude/reviewer: codex/" "$SIRIUS_HOME/config.yaml"
check "verify.deploy list resolves" '
  sed -i "" "s#^  deploy: \[\]#  deploy: [\"STG: gh workflow run cd-staging.yml --ref <branch>\"]#" "$SIRIUS_HOME/repos/acme__pstk.yaml"
  bin/sirius-config repo acme/pstk | grep -q "cd-staging.yml"'
check "verify.deploy must be a list of strings" '
  sed -i "" "s#^  deploy: .*#  deploy: {staging: x}#" "$SIRIUS_HOME/repos/acme__pstk.yaml"
  bin/sirius-config validate | grep -q "verify.deploy must be a list"'
rm -f "$SIRIUS_HOME/repos/acme__pstk.yaml"

rm -rf "$SIRIUS_HOME"
exit $fail
