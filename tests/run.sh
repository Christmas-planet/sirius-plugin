#!/bin/zsh
# Offline tests for sirius-config, sirius-lease, and the guard hook.
set -u
cd "${0:A:h}/.."
fail=0
check() { if eval "$2"; then print "ok   $1"; else print "FAIL $1"; fail=1; fi }

export SIRIUS_HOME="$(mktemp -d)"
mkdir -p "$SIRIUS_HOME/projects"
cp templates/config.yaml "$SIRIUS_HOME/config.yaml"
cp templates/project.yaml "$SIRIUS_HOME/projects/my-project.yaml"

check "template validates" 'bin/sirius-config validate >/dev/null'
check "manual ceiling caps auto" '
  sed -i "" "s/^merge: manual/merge: auto/" "$SIRIUS_HOME/projects/my-project.yaml"
  [[ $(bin/sirius-config project my-project | python3 -c "import json,sys;print(json.load(sys.stdin)[\"merge\"])") == manual ]]'
check "auto without reviewer identity falls back" '
  sed -i "" "s/^merge: manual/merge: auto/" "$SIRIUS_HOME/config.yaml"
  bin/sirius-config project my-project | grep -q "needs identities.reviewer"'
check "same implementer and reviewer falls back" '
  sed -i "" "s/^reviewer: codex/reviewer: claude/" "$SIRIUS_HOME/config.yaml"
  bin/sirius-config project my-project | grep -q "different from the implementer"'
check "needs_review forces human gate" '
  print "needs_review: true" >> "$SIRIUS_HOME/projects/my-project.yaml"
  bin/sirius-config project my-project | grep -q "\"implement_gate\": \"human\""'
check "wildcard source rejected" '
  sed "s/name: my-project/name: bad/; s/C0123456789/C*/" templates/project.yaml > "$SIRIUS_HOME/projects/bad.yaml"
  ! bin/sirius-config validate >/dev/null'
rm "$SIRIUS_HOME/projects/bad.yaml"
check "duplicate repo rejected" '
  sed "s/name: my-project/name: dup/" templates/project.yaml > "$SIRIUS_HOME/projects/dup.yaml"
  bin/sirius-config validate | grep -q "claimed by both"'
rm "$SIRIUS_HOME/projects/dup.yaml"

check "lease excludes a second run" 'bin/sirius-lease acquire a >/dev/null && ! bin/sirius-lease acquire b >/dev/null'
check "lease release by owner only" '! bin/sirius-lease release b >/dev/null && bin/sirius-lease release a >/dev/null'

g() { print -r -- "$1" | scripts/guard >/dev/null 2>&1; }
check "guard blocks gh pr merge" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr merge 1\"}}"'
check "guard blocks merge API" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh api -X PUT repos/o/r/pulls/1/merge\"}}"'
check "guard blocks --admin" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr review 1 --admin\"}}"'
check "guard blocks force push" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push -f origin x\"}}"'
check "guard blocks self-applied implement" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh issue edit 1 --add-label implement\"}}"'
check "guard allows working label" 'g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh issue edit 1 --add-label working\"}}"'
check "guard allows normal push" 'g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin sirius/issue-1-x\"}}"'
check "guard blocks shell write to settings" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > $SIRIUS_HOME/config.yaml\"}}"'
check "guard blocks ruleset PATCH" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh api -X PATCH repos/o/r/rulesets/1\"}}"'
check "guard allows ruleset read" 'g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh ruleset list -R o/r\"}}"'
check "guard allows human-merge label" 'g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr edit 1 --add-label human-merge\"}}"'
check "guard blocks implement in a label list" '! g "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh issue edit 1 --add-label sirius,implement\"}}"'
check "guard blocks \$HOME write to settings" '! print -r -- "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo x > \\\"\$HOME/.sirius/config.yaml\\\"\"}}" | SIRIUS_HOME=$HOME/.sirius scripts/guard 2>/dev/null'
check "negative approvals rejected" '
  sed "s/name: my-project/name: neg/; s#acme/my-project#acme/neg#; s/approvals: 0/approvals: -1/" templates/project.yaml > "$SIRIUS_HOME/projects/neg.yaml"
  bin/sirius-config validate | grep -q "non-negative"'
rm -f "$SIRIUS_HOME/projects/neg.yaml"
check "misspelled rule key rejected" '
  sed "s/name: my-project/name: typo/; s#acme/my-project#acme/typo#; s/approvals: 0/approval: 2/" templates/project.yaml > "$SIRIUS_HOME/projects/typo.yaml"
  bin/sirius-config validate | grep -q "unknown keys"'
rm -f "$SIRIUS_HOME/projects/typo.yaml"
check "repo case duplicate rejected" '
  sed "s/name: my-project/name: upper/; s#acme/my-project#ACME/My-Project#g" templates/project.yaml > "$SIRIUS_HOME/projects/upper.yaml"
  bin/sirius-config validate | grep -q "claimed by both"'
rm -f "$SIRIUS_HOME/projects/upper.yaml"
check "concurrent acquire yields one owner" '
  [[ $(for i in 1 2 3 4 5 6 7 8; do bin/sirius-lease acquire c$i & done 2>/dev/null; wait) == *acquired\"\:\ true* ]] &&
  [[ $(for i in 1 2 3 4 5 6 7 8; do bin/sirius-lease acquire d$i & done 2>/dev/null; wait) != *acquired\"\:\ true* ]]'
check "guard asks on Write to settings" '
  print -r -- "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SIRIUS_HOME/projects/x.yaml\"}}" | scripts/guard | grep -q "\"ask\""'

rm -rf "$SIRIUS_HOME"
exit $fail
