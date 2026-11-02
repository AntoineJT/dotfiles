#!/usr/bin/env bash
# restack.test.sh — Tests for scripts/restack.sh (and, through it, stack-verify.sh).
#
# Builds a throwaway stack master <- a <- b <- c, squash-merges `a` into master the way a
# forge does, then restacks b and c and checks every refusal and output line.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT="$SCRIPT_DIR/../restack.sh"

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
fixture() {
  rm -rf "$R"; git init -q -b master "$R"; g remote add origin "$WORK/no-such-remote.git"
  c base.txt base "base"
  g switch -qc a; c a.txt a1 "a1"; c a.txt a2 "a2"
  g switch -qc b; c b.txt b1 "b1"
  g switch -qc c; c c.txt c1 "c1"
  g switch -q master; g merge -q --squash a >/dev/null; g commit -qm "a (#12)"
}
run() { (cd "$R" && bash "$SUT" "$@" 2>&1); }

echo "restack.sh"

fixture
run master a >/dev/null; assert_eq "two arguments is usage" "2" "$?"
out="$(run --remote upstream master a b)"; assert_eq "an unknown remote is refused" "refused: no remote named upstream: pass --remote <name>" "$out"
run --reason 'a b' master a b >/dev/null; assert_eq "a reason with a space is usage" "2" "$?"
out="$(run master nope b)"; assert_eq "an unknown ref is refused" "1" "$?"
assert_eq "and named" "refused: not a commit: nope" "$out"
out="$(run master a nobranch)"; assert_eq "a missing local branch is refused" "no local branch nobranch" "${out#refused: }"
out="$(run master b b)"; assert_eq "an empty range is refused" "refused: b..b is empty: nothing to replay" "$out"

before="$(g rev-parse b)"
out="$(run --dry-run master a b)"; assert_eq "dry run exits 0" "0" "$?"
assert_eq "dry run lists the commits" "replay 1 commits onto master:
$(g log --oneline --no-decorate -1 b)" "$out"
assert_eq "dry run leaves the branch" "$before" "$(g rev-parse b)"
assert_eq "dry run makes no backup" "" "$(g branch --list 'backup/*')"

wts="$(g worktree list | wc -l)"
out="$(run master a b)"; assert_eq "restacking b exits 0" "0" "$?"
assert_has "the backup is named" "backup backup/b-restack $before" "$out"
assert_eq "the backup holds the old tip" "$before" "$(g rev-parse backup/b-restack)"
assert_has "the rebase is reported" "rebased b $before -> $(g rev-parse b)" "$out"
assert_has "every commit is =" "commits  1 = , 0 changed, 0 added, 0 removed" "$out"
assert_has "the patch is identical" "patch    identical" "$out"
assert_has "the tree is identical (squash = parent tip)" "tree     identical" "$out"
assert_eq "b now sits on master" "$(g rev-parse master)" "$(g rev-parse b~1)"
assert_eq "the temporary worktree is gone" "$wts" "$(g worktree list | wc -l)"
assert_eq "the current checkout did not move" "master" "$(g branch --show-current)"

out="$(run master a b)"; assert_eq "a second run is refused" "refused: b already contains master" "$out"

g worktree add -q "$WORK/wt-c" c
out="$(run b backup/b-restack c)"; assert_eq "restacking c in its own worktree exits 0" "0" "$?"
assert_eq "that worktree's checkout followed" "$(g rev-parse c)" "$(git -C "$WORK/wt-c" rev-parse HEAD)"
assert_eq "c now sits on the new b" "$(g rev-parse b)" "$(g rev-parse c~1)"

fixture
g worktree add -q "$WORK/wt-b" b
printf 'dirty\n' >> "$WORK/wt-b/b.txt"
out="$(run master a b)"; assert_eq "a dirty worktree is refused" "refused: $WORK/wt-b has uncommitted changes" "$out"
git -C "$WORK/wt-b" checkout -q -- b.txt
printf 'new\n' > "$WORK/wt-b/untracked.txt"
run --dry-run master a b >/dev/null; assert_eq "an untracked file does not block" "0" "$?"
g worktree remove --force "$WORK/wt-b"

fixture
g branch backup/b-restack a
out="$(run master a b)"; assert_eq "a backup at another commit is refused" "1" "$?"
assert_has "and says how to go on" "pass another --reason" "$out"
run --reason second master a b >/dev/null; assert_eq "another reason goes through" "0" "$?"

fixture
g switch -q --detach master; c b.txt b1 "b1"; g update-ref refs/remotes/origin/b HEAD; g switch -q master
before="$(g rev-parse b)"
out="$(run master a b)"; assert_eq "a remote branch already restacked is refused" "1" "$?"
assert_has "and points at the comparison" "stack-verify.sh" "$out"
assert_eq "the local branch is untouched" "$before" "$(g rev-parse b)"

fixture
g update-ref refs/remotes/origin/b b
g switch -q --detach b; c b.txt b2 "pushed by a teammate"; g update-ref refs/remotes/origin/b HEAD; g switch -q master
out="$(run master a b)"; assert_eq "a remote branch ahead of the local one is refused" "1" "$?"
assert_has "and asks for a sync first" "fast-forward or sync the local branch first" "$out"
g update-ref refs/remotes/origin/b b~1
run --dry-run master a b >/dev/null; assert_eq "a remote branch behind the local one is fine" "0" "$?"

fixture
g update-ref refs/remotes/origin/b b
run master a b >/dev/null
g switch -q --detach master; c base.txt more "master moves before the push"; g branch -f master HEAD; g switch -q master
out="$(run --reason again master master~1 b)"; assert_eq "your own unpushed restack can be restacked again" "0" "$?"

fixture
g branch b-x b; g switch -q b-x; c x.txt x "work on a sibling branch b-x"; g switch -q master
g branch backup/b-x-restack b-x; g update-ref refs/remotes/origin/b b-x
out="$(run master a b)"; assert_eq "a sibling branch's backup does not exempt the remote check" "1" "$?"
run --reason 'a-b' master a b >/dev/null; assert_eq "a reason with a dash is usage (it would blur backup names)" "2" "$?"

fixture
g update-ref refs/remotes/origin/b b; c2() { g switch -q b; c b.txt b2 "local, unpushed"; g switch -q master; }; c2
run master a b >/dev/null
g switch -q --detach master; c base.txt more "master moves again"; g branch -f master HEAD; g switch -q master
run --reason again master master~1 b >/dev/null; assert_eq "a restack of a branch that was ahead can be restacked again" "0" "$?"

fixture
g switch -q master; printf 'other\n' > "$R/b.txt"; g add b.txt; g commit -qm "conflicting"
out="$(run master a b)"; wt="$(printf '%s\n' "$out" | sed -n 's/^conflict: the rebase is in progress in //p')"
out="$(run --reason again master a b)"; assert_eq "a rebase left in progress elsewhere is refused" "refused: a rebase of b is in progress in $(cd "$wt" && pwd -P): continue or abort it there, or \`git worktree prune\` if that folder is gone" "$out"
assert_eq "before any backup" "" "$(g branch --list 'backup/b-again')"
wtp="$(cd "$wt" && pwd -P)"; mv "$wt" "$WORK/purged"
out="$(run --reason again master a b)"; assert_has "even once its folder is gone (a purged temp dir)" "refused: a rebase of b is in progress in $wtp" "$out"
assert_has "and names the way out" "git worktree prune" "$out"
assert_eq "still before any backup" "" "$(g branch --list 'backup/b-again')"
mv "$WORK/purged" "$wt"; git -C "$wt" rebase --abort; g worktree remove "$wt"

fixture
g config rebase.updateRefs true
old_b="$(g rev-parse b)"
run master a b >/dev/null; assert_eq "rebase.updateRefs does not move the backup" "$old_b" "$(g rev-parse backup/b-restack)"

fixture
g worktree add -q "$WORK/wt-b2" b
g switch -q --detach master; c c.txt master-c "c.txt lands on master"; g branch -f master HEAD; g switch -q master
printf 'untracked\n' > "$WORK/wt-b2/c.txt"
before="$(g rev-parse b)"
out="$(run master a b)"; assert_eq "a rebase git will not start is refused, not a conflict" "1" "$?"
assert_has "with git's reason" "refused: git did not start the rebase" "$out"
assert_eq "and leaves the branch" "$before" "$(g rev-parse b)"
rm "$WORK/wt-b2/c.txt"; g worktree remove "$WORK/wt-b2"

fixture
g switch -q master; printf 'other\n' > "$R/b.txt"; g add b.txt; g commit -qm "conflicting"
out="$(run master a b)"; code=$?
assert_eq "a conflict exits 3" "3" "$code"
wt="$(printf '%s\n' "$out" | sed -n 's/^conflict: the rebase is in progress in //p')"
assert_eq "the rebase waits in the printed worktree" "yes" "$([ -d "$(git -C "$wt" rev-parse --path-format=absolute --git-path rebase-merge)" ] && echo yes)"
git -C "$wt" rebase --abort; g worktree remove "$wt"
out="$(run master a b)"; assert_eq "after an abort, a rerun reuses the backup" "3" "$?"
wt="$(printf '%s\n' "$out" | sed -n 's/^conflict: the rebase is in progress in //p')"
git -C "$wt" rebase --abort; g worktree remove "$wt"

fixture
g switch -q --detach master; c a.txt a3 "a3 lands with the squash"; g branch -f master HEAD; g switch -q master
out="$(run master a b)"; assert_eq "an extra change on the base still restacks cleanly" "0" "$?"
assert_has "the tree then differs" "tree     differs" "$out"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
