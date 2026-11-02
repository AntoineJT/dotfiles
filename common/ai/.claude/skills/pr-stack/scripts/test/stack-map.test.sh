#!/usr/bin/env bash
# stack-map.test.sh — Tests for scripts/stack-map.sh.
#
# `gh` is a stub that answers from files: view-<n> holds the TSV line `gh pr view <n> --jq …`
# kids-<branch> the numbers `gh pr list --base <branch> --jq …` would print.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT="$SCRIPT_DIR/../stack-map.sh"

PASS=0 FAIL=0
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; PASS=$((PASS + 1))
  else echo "  ✗ $1"; echo "    expected: $2"; echo "    actual:   $3"; FAIL=$((FAIL + 1)); fi
}

STUB="$WORK/stub"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
d="$(dirname "$0")"
case "$1 $2" in
  "pr view") [ -f "$d/view-$3" ] || { echo "no PR $3" >&2; exit 1; }; cat "$d/view-$3" ;;
  "pr list") f="$d/kids-$(printf %s "$4" | tr / _)"; [ ! -f "$f" ] || cat "$f" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
export GH="$STUB/gh"

R="$WORK/repo"
g() { git -C "$R" "$@"; }
c() { printf '%s\n' "$2" >> "$R/$1"; g add "$1"; g commit -qm "$3"; }
git init -q -b master "$R"
c f base base
g switch -qc feat/a; c f a "a"
g switch -qc b; c f b "b"
g switch -qc c; c f c1 "c1"; c f c2 "c2"
g switch -q master
T="$(printf '\t')"
view() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" > "$STUB/view-$1"; }
view 12 MERGED master feat/a "$(g rev-parse feat/a)"
view 13 OPEN feat/a b "$(g rev-parse b~0)"
view 14 OPEN b c "$(g rev-parse c~1)"
echo 13 > "$STUB/kids-feat_a"
echo 14 > "$STUB/kids-b"
g worktree add -q "$WORK/wt-b" b
m() { (cd "$R" && bash "$SUT" "$@" 2>&1); }
s9() { g rev-parse "$1"; }

echo "stack-map.sh"

m >/dev/null; assert_eq "no PR is usage" "2" "$?"
m 12x >/dev/null; assert_eq "a non-number is usage" "2" "$?"
(cd "$WORK" && bash "$SUT" 12 >/dev/null 2>&1); assert_eq "outside a repository is usage" "2" "$?"

out="$(m 12)"; assert_eq "the stack is followed from its bottom" "0" "$?"
assert_eq "one line per PR, children found recursively" "#pr${T}state${T}base${T}head${T}remote-sha${T}local${T}worktree${T}(remote origin)
12${T}MERGED${T}master${T}feat/a${T}$(s9 feat/a)${T}same${T}-
13${T}OPEN${T}feat/a${T}b${T}$(s9 b)${T}same${T}$WORK/wt-b
14${T}OPEN${T}b${T}c${T}$(s9 c~1)${T}ahead 1${T}-" "$out"

view 13 OPEN master b "$(g rev-parse b)"; rm "$STUB/kids-feat_a"
printf '13 %s master\n14 %s b\n' "$(g rev-parse b)" "$(g rev-parse c~1)" > "$STUB/kids-open"
assert_eq "a child already retargeted off a merged parent is found by ancestry" "12 13 14" "$(m 12 | awk -F"$T" 'NR>1 { printf "%s ", $1 }' | sed 's/ $//')"
g update-ref refs/remotes/origin/master feat/a
view 13 OPEN feat/a b "$(g rev-parse b)"
printf '13 %s feat/a\n14 %s b\n20 %s master\n' "$(g rev-parse b)" "$(g rev-parse c~1)" "$(g rev-parse feat/a)" > "$STUB/kids-open"
view 20 OPEN master unrelated "$(g rev-parse feat/a)"; echo 13 > "$STUB/kids-feat_a"
assert_eq "a PR cut from a base that already holds the merge is not a child" "12 13 14" "$(m 12 | awk -F"$T" 'NR>1 { printf "%s ", $1 }' | sed 's/ $//')"

g switch -qc p master; c p p1 "p1"; g switch -qc q; c q q1 "q1"
g switch -q p; c p p2 "review fix after q was cut"; g switch -q master
g update-ref refs/remotes/origin/master master
view 30 MERGED master p "$(g rev-parse p)"
view 31 OPEN master q "$(g rev-parse q)"
printf '31 %s master\n' "$(g rev-parse q)" > "$STUB/kids-open"
assert_eq "a retargeted child cut before the parent's last commit is found" "30 31" "$(m 30 | awk -F"$T" 'NR>1 { printf "%s ", $1 }' | sed 's/ $//')"
rm "$STUB/kids-open"

out="$(m 14 13 14)"
assert_eq "a PR listed twice, or reached twice, prints once" "2" "$(printf '%s\n' "$out" | grep -c '^1[34]')"

g switch -q --detach b; c g other "other"; other="$(g rev-parse HEAD)"; g switch -q master
view 14 OPEN b c "$other"
assert_eq "diverged" "diverged +2 -1" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"
g branch backup/c-restack "$other"
assert_eq "diverged from a remote its backup holds: restacked, not pushed" "restacked +2 -1 backup/c-restack" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"
g switch -q --detach "$other"; c g more "a local commit on top before the restack"; g branch -f backup/c-restack HEAD; g switch -q master
assert_eq "or a remote its backup contains (the branch was ahead)" "restacked +2 -1 backup/c-restack" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"
g branch -f backup/c-restack "$other"
g branch -m backup/c-restack backup/c-x-restack
assert_eq "a sibling's backup does not count" "diverged +2 -1" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"
g branch -D -q backup/c-x-restack
view 14 OPEN b gone "$other"
assert_eq "absent" "absent" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"
view 14 OPEN b c 0123456789abcdef0123456789abcdef01234567
assert_eq "unfetched" "unfetched" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"
view 14 OPEN b gone 0123456789abcdef0123456789abcdef01234567
assert_eq "unfetched wins over absent: the commit must be fetched first" "unfetched" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"
view 14 OPEN b c "$(g rev-parse c)"
g branch -f c c~1
assert_eq "behind N" "behind 1" "$(m 14 | awk -F"$T" 'NR==2 { print $6 }')"

out="$(m 99)"; assert_eq "a gh failure exits 1" "1" "$?"
assert_eq "and names the call" "gh pr view 99 failed" "$(printf '%s\n' "$out" | tail -1)"
assert_eq "--remote is echoed in the header" "(remote upstream)" "$(m --remote upstream 14 | head -1 | awk -F"$T" '{ print $8 }')"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
