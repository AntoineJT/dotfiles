#!/usr/bin/env bash
# prepare-split.test.sh — Tests for scripts/prepare-split.sh, on throwaway git repositories.
set -uo pipefail
# Under a git hook, an inherited GIT_DIR would point the fixtures at the real repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR

SUT="$(cd "$(dirname "$0")/.." && pwd)/prepare-split.sh"
PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1 HOME="$WORK"

assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; PASS=$((PASS + 1))
  else echo "  ✗ $1"; echo "    expected: $2"; echo "    actual:   $3"; FAIL=$((FAIL + 1)); fi
}

# repo <name>: origin with master (a.txt), clone with origin/HEAD set, branch feat with two commits.
repo() {
  local o="$WORK/$1-origin" r="$WORK/$1"
  git init -q -b master "$o"
  echo a >"$o/a.txt"; git -C "$o" add a.txt; git -C "$o" commit -qm base
  git clone -q "$o" "$r"
  git -C "$r" checkout -qb feat
  echo b >"$r/b.txt"; git -C "$r" add b.txt; git -C "$r" commit -qm "add b"
  echo c >"$r/c.txt"; git -C "$r" add c.txt; git -C "$r" commit -qm "add c"
}
run() { (cd "$WORK/$1" && bash "$SUT" "${@:2}"); }

echo "prepare-split.sh"

repo ok
tip="$(git -C "$WORK/ok" rev-parse HEAD)"
tree="$(git -C "$WORK/ok" rev-parse HEAD^{tree})"
base="$(git -C "$WORK/ok" rev-parse origin/master)"
out="$(run ok split)"
assert_eq "a clean branch exits 0" "0" "$?"
assert_eq "prints backup, base and tree" "backup backup/feat-split $tip
base $base
tree $tree" "$out"
assert_eq "the backup points at the old tip" "$tip" "$(git -C "$WORK/ok" rev-parse backup/feat-split)"
assert_eq "HEAD is back at the base" "$base" "$(git -C "$WORK/ok" rev-parse HEAD)"
assert_eq "still on the branch" "feat" "$(git -C "$WORK/ok" symbolic-ref --short HEAD)"
assert_eq "the work tree keeps the final files, unstaged" "?? b.txt
?? c.txt" "$(git -C "$WORK/ok" status --porcelain)"

out="$(run ok split 2>&1)"
assert_eq "an existing backup is refused" "2" "$?"
case "$out" in *"already exists"*) r=named ;; *) r="$out" ;; esac
assert_eq "and named" "named" "$r"

repo wip
tip="$(git -C "$WORK/wip" rev-parse HEAD)"
out="$(run wip wip HEAD~1)"
assert_eq "an explicit base splits only the last commit" "$(git -C "$WORK/wip" rev-parse backup/feat-wip~1)" "$(git -C "$WORK/wip" rev-parse HEAD)"
assert_eq "leaving only that commit's file unstaged" "?? c.txt" "$(git -C "$WORK/wip" status --porcelain)"

repo dirty
echo changed >>"$WORK/dirty/b.txt"
run dirty split >/dev/null 2>&1
assert_eq "unstaged changes are refused" "2" "$?"
git -C "$WORK/dirty" add b.txt
run dirty split >/dev/null 2>&1
assert_eq "staged changes are refused" "2" "$?"
assert_eq "and no backup is created" "" "$(git -C "$WORK/dirty" branch --list 'backup/*')"

repo untracked
echo u >"$WORK/untracked/u.txt"
run untracked split >/dev/null 2>&1
assert_eq "an untracked file does not block" "0" "$?"

repo detached
git -C "$WORK/detached" checkout -q --detach
run detached split >/dev/null 2>&1
assert_eq "a detached HEAD is refused" "2" "$?"

repo nohead
git -C "$WORK/nohead" remote set-head origin -d
out="$(run nohead split 2>&1)"
assert_eq "no origin/HEAD and no base is refused" "2" "$?"
case "$out" in *"set-head origin -a"*) r=hint ;; *) r="$out" ;; esac
assert_eq "with the command that fixes it" "hint" "$r"

repo same
git -C "$WORK/same" checkout -q master
run same split >/dev/null 2>&1
assert_eq "a branch at its base is refused" "2" "$?"

repo badbase
run badbase split no-such-ref >/dev/null 2>&1
assert_eq "an unknown base is refused" "2" "$?"

repo slug
run slug "a b" >/dev/null 2>&1
assert_eq "a reason that is not a slug is refused" "2" "$?"
run slug >/dev/null 2>&1
assert_eq "no reason is a usage error" "2" "$?"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
