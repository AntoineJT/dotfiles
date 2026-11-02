#!/usr/bin/env bash
# stack-verify.test.sh — Tests for scripts/stack-verify.sh.
#
# One branch replayed three ways onto a moved base: unchanged, with a commit altered, and with
# a commit dropped. Each must print its own verdict and exit code.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT="$SCRIPT_DIR/../stack-verify.sh"

PASS=0 FAIL=0
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; PASS=$((PASS + 1))
  else echo "  ✗ $1"; echo "    expected: $2"; echo "    actual:   $3"; FAIL=$((FAIL + 1)); fi
}
assert_has() {
  case "$3" in *"$2"*) echo "  ✓ $1"; PASS=$((PASS + 1)) ;;
  *) echo "  ✗ $1"; echo "    missing:  $2"; echo "    in:       $3"; FAIL=$((FAIL + 1)) ;; esac
}

R="$WORK/repo"
g() { git -C "$R" "$@"; }
c() { printf '%s\n' "$2" >> "$R/$1"; g add "$1"; g commit -qm "$3"; }
git init -q -b master "$R"
c base.txt base "base"
g switch -qc old; c x.txt x1 "x1"; c y.txt "$(seq 1 20)" "y1"
g switch -q master; c other.txt o "other work"
pick() { g cherry-pick "$@" >/dev/null; }
g switch -qc same; pick old~1 old
g switch -qc changed master; pick old~1; c y.txt "$(seq 1 20 | sed 's/^3$/3-edited/')" "y1"
g switch -qc dropped master; pick old~1
v() { (cd "$R" && bash "$SUT" "$@" 2>&1); }

echo "stack-verify.sh"

v a b c >/dev/null; assert_eq "three arguments is usage" "2" "$?"
out="$(v master~1 old master nope)"; assert_eq "an unknown ref exits 2" "2" "$?"
assert_eq "and is named" "not a commit: nope" "$out"

out="$(v master~1 old master same)"; assert_eq "an unchanged replay exits 0" "0" "$?"
assert_eq "and prints three verdicts, then the tree stat" "commits  2 = , 0 changed, 0 added, 0 removed
patch    identical
tree     differs" "$(printf '%s\n' "$out" | sed -n 1,3p)"
assert_has "the stat names the base's own file" "other.txt" "$out"

out="$(v master~1 old master changed)"; assert_eq "an altered commit exits 1" "1" "$?"
assert_has "counted as changed" "commits  1 = , 1 changed, 0 added, 0 removed" "$out"
assert_has "the patch differs" "patch    differs" "$out"
assert_has "the range-diff is shown" "3-edited" "$out"

out="$(v master~1 old master dropped)"; assert_eq "a dropped commit exits 1" "1" "$?"
assert_has "counted as removed" "commits  1 = , 0 changed, 0 added, 1 removed" "$out"

g switch -q old; g switch -qc parent-moved master~1; c base.txt "review fix" "review fix on the parent"; g switch -q master
out="$(v parent-moved old master same)"; assert_eq "a parent that gained commits after the child was cut is not a change" "0" "$?"
assert_has "the patch is identical" "patch    identical" "$out"

out="$(v master~1 old master~1 old)"; assert_eq "a range against itself exits 0" "0" "$?"
assert_has "with an identical tree" "tree     identical" "$out"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
