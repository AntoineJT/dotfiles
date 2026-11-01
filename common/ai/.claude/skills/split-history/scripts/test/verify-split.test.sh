#!/usr/bin/env bash
# verify-split.test.sh — Tests for scripts/verify-split.sh, on throwaway git repositories.
set -uo pipefail
# Under a git hook, an inherited GIT_DIR would point the fixtures at the real repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR

SUT="$(cd "$(dirname "$0")/.." && pwd)/verify-split.sh"
PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1 HOME="$WORK" TMPDIR="$WORK"
# Local submodule URLs are refused by default (git >= 2.38).
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always

assert_eq() {
  if [ "$2" = "$3" ]; then echo "  ✓ $1"; PASS=$((PASS + 1))
  else echo "  ✗ $1"; echo "    expected: $2"; echo "    actual:   $3"; FAIL=$((FAIL + 1)); fi
}

# repo <name>: master (lib.sh), branch feat: "feat: lib" adds ok(), "feat: use" calls it.
# The check `sh check.sh` passes only when every function called is defined.
repo() {
  local r="$WORK/$1"
  git init -q -b master "$r"
  printf 'grep -q "^ok()" lib.sh 2>/dev/null || ! grep -q "^ok$" main.sh 2>/dev/null\n' >"$r/check.sh"
  echo '# lib' >"$r/lib.sh"
  git -C "$r" add . && git -C "$r" commit -qm "chore: base"
  git -C "$r" checkout -qb feat
  echo 'ok() { :; }' >>"$r/lib.sh"; git -C "$r" commit -qam "feat: lib"
  echo ok >"$r/main.sh"; git -C "$r" add main.sh; git -C "$r" commit -qm "feat: use"
}
run() { (cd "$WORK/$1" && bash "$SUT" "${@:2}"); }
sha() { git -C "$WORK/$1" rev-parse --short "$2"; }

echo "verify-split.sh"

repo good
git -C "$WORK/good" branch backup
out="$(run good --base master --tree backup --exec 'sh check.sh' --msg 'grep -q "^feat: "')"
assert_eq "a good history exits 0" "0" "$?"
t="$(git -C "$WORK/good" rev-parse HEAD^{tree})"
logs="$(printf '%s\n' "$out" | sed -n 's/^logs //p')"
assert_eq "one line per check, in order" "exec pass $(sha good HEAD~1) feat: lib
exec pass $(sha good HEAD) feat: use
msg pass $(sha good HEAD~1) feat: lib
msg pass $(sha good HEAD) feat: use
tree equal $t $t
logs $logs" "$out"
assert_eq "one exec and one msg log per commit" "4" "$(ls "$logs" | wc -l | tr -d ' ')"
assert_eq "the branch is checked out again" "feat" "$(git -C "$WORK/good" symbolic-ref --short HEAD)"

# Wrong order: the call lands before the definition.
repo order
r="$WORK/order"
git -C "$r" checkout -qb reordered master
echo ok >"$r/main.sh"; git -C "$r" add main.sh; git -C "$r" commit -qm "feat: use"
git -C "$r" checkout -q feat -- lib.sh; git -C "$r" commit -qm "feat: lib"
out="$(run order --base master --tree feat --exec 'sh check.sh')"
assert_eq "a commit that fails its check exits 1" "1" "$?"
assert_eq "and is the one marked FAIL" "exec FAIL $(sha order HEAD~1) feat: use
exec pass $(sha order HEAD) feat: lib" "$(printf '%s\n' "$out" | grep '^exec')"
assert_eq "the branch is checked out again after a failure" "reordered" "$(git -C "$r" symbolic-ref --short HEAD)"
assert_eq "an equal tree still says so" "equal" "$(printf '%s\n' "$out" | sed -n 's/^tree \([a-zA-Z]*\) .*/\1/p')"

repo diverged
git -C "$WORK/diverged" branch backup
echo extra >>"$WORK/diverged/main.sh"; git -C "$WORK/diverged" commit -qam "feat: extra"
out="$(run diverged --base master --tree backup)"
assert_eq "a different final tree exits 1" "1" "$?"
assert_eq "and is named DIFFERENT" "DIFFERENT" "$(printf '%s\n' "$out" | cut -d' ' -f2)"

repo msg
out="$(run msg --base master --msg 'grep -q "^chore: " || echo "bad title"')"
assert_eq "only the linter's exit code counts, not its output" "0" "$?"
out="$(run msg --base master --msg 'grep -q "^chore: " || { echo "bad title"; exit 1; }')"
assert_eq "a message the linter rejects exits 1" "1" "$?"
assert_eq "each rejected message is marked" "2" "$(printf '%s\n' "$out" | grep -c '^msg FAIL')"
logs="$(printf '%s\n' "$out" | sed -n 's/^logs //p')"
assert_eq "and the linter's words are kept in its log" "bad title" "$(cat "$logs/msg-1-$(sha msg HEAD~1).log")"

# A check that rewrites a tracked file (a formatter, a snapshot update).
repo modify
out="$(run modify --base master --tree feat --exec 'echo formatted >> lib.sh')"
assert_eq "a check that modifies tracked files exits 1" "1" "$?"
assert_eq "and fails every commit it modified, saying why" "exec FAIL $(sha modify HEAD~1) feat: lib (modified tracked files)
exec FAIL $(sha modify HEAD) feat: use (modified tracked files)" "$(printf '%s\n' "$out" | grep '^exec')"
assert_eq "its changes do not leak into the user's tree" "" "$(git -C "$WORK/modify" status --porcelain)"
assert_eq "the branch is checked out again" "feat" "$(git -C "$WORK/modify" symbolic-ref --short HEAD)"
logs="$(printf '%s\n' "$out" | sed -n 's/^logs //p')"
assert_eq "the diff it made is in the log" "1" "$(grep -c '^+formatted' "$logs/1-$(sha modify HEAD~1).log")"

repo dirty
echo x >>"$WORK/dirty/lib.sh"
run dirty --base master --exec true >/dev/null 2>&1
assert_eq "uncommitted tracked changes are refused with --exec" "2" "$?"
run dirty --base master --tree feat >/dev/null 2>&1
assert_eq "but do not matter for the tree alone" "0" "$?"

repo detached
git -C "$WORK/detached" checkout -q --detach
before="$(git -C "$WORK/detached" rev-parse HEAD)"
run detached --base master --exec true >/dev/null
assert_eq "a detached start is restored" "$before" "$(git -C "$WORK/detached" rev-parse HEAD)"

# A branch that untracks a local file and ignores it: checkouts would overwrite then delete it.
repo ignored
r="$WORK/ignored"
echo secret >"$r/.env"; git -C "$r" add .env; git -C "$r" commit -qm "feat: env"
git -C "$r" rm -q --cached .env; echo .env >"$r/.gitignore"; git -C "$r" add .gitignore; git -C "$r" commit -qm "feat: ignore env"
echo mine >"$r/.env"
out="$(run ignored --base master --exec true 2>&1)"
assert_eq "an ignored file the range touches is refused" "2" "$?"
case "$out" in *"move them aside"*".env"*) r2=named ;; *) r2="$out" ;; esac
assert_eq "naming it" "named" "$r2"
assert_eq "and left as it was" "mine" "$(cat "$r/.env")"

# Ignored files the range does not touch do not block, even when their names look like patterns.
repo ignored2
r="$WORK/ignored2"
mkdir -p "$r/node_modules/x"; echo m >"$r/node_modules/x/i.js"; echo g >"$r/a[1].txt"
printf 'node_modules/\na\\[1\\].txt\n' >"$r/.git/info/exclude"
echo t >"$r/a1.txt"; git -C "$r" add a1.txt; git -C "$r" commit -qm "feat: a1"
run ignored2 --base master --exec true >/dev/null 2>&1
assert_eq "ignored files elsewhere do not block" "0" "$?"

# The check generates an untracked file that a later commit tracks: the checkout stops.
repo generated
r="$WORK/generated"
echo gen >"$r/gen.txt"; git -C "$r" add gen.txt; git -C "$r" commit -qm "feat: gen"
out="$(run generated --base master --exec 'echo other > gen.txt' 2>/dev/null)"
assert_eq "a blocked checkout exits 1" "1" "$?"
assert_eq "and is labelled as such" "exec FAIL $(sha generated HEAD) feat: gen (checkout)" "$(printf '%s\n' "$out" | grep '(checkout)')"
assert_eq "the branch is checked out again" "feat" "$(git -C "$r" symbolic-ref --short HEAD)"

# Run from a directory only the last commit contains.
repo subdir
r="$WORK/subdir"
mkdir "$r/docs"; echo d >"$r/docs/d.md"; git -C "$r" add docs; git -C "$r" commit -qm "docs: d"
out="$(cd "$r/docs" && bash "$SUT" --base master --exec 'sh check.sh' --msg 'grep -q "^[a-z]*: "')"
assert_eq "a run from a subdirectory early commits lack passes" "0" "$?"
assert_eq "checking every commit" "3" "$(printf '%s\n' "$out" | grep -c '^exec pass')"

# A branch that bumps a submodule: each commit is checked with the submodule it pins.
git init -q -b master "$WORK/sub"
echo v1 >"$WORK/sub/v"; git -C "$WORK/sub" add v; git -C "$WORK/sub" commit -qm v1
repo super
r="$WORK/super"
git -C "$r" checkout -q master
git -C "$r" submodule -q add "$WORK/sub" sub; git -C "$r" commit -qm "chore: sub"
git -C "$r" checkout -q feat 2>/dev/null; git -C "$r" rebase -q master
echo v2 >"$WORK/sub/v"; git -C "$WORK/sub" commit -qam v2
git -C "$r/sub" pull -q; git -C "$r" add sub; git -C "$r" commit -qm "feat: bump sub"
out="$(run super --base master --exec 'cat sub/v >> /dev/null; echo "$(git rev-parse --short HEAD) $(cat sub/v)"')"
assert_eq "a submodule bump passes" "0" "$?"
logs="$(printf '%s\n' "$out" | sed -n 's/^logs //p')"
assert_eq "the commit before the bump sees the old submodule" "v1" "$(cut -d' ' -f2 "$logs/2-$(sha super HEAD~1).log")"
assert_eq "the bump sees the new one" "v2" "$(cut -d' ' -f2 "$logs/3-$(sha super HEAD).log")"
assert_eq "and the submodule is back at the tip's commit" "v2" "$(cat "$r/sub/v")"

repo usage
run usage --tree feat >/dev/null 2>&1
assert_eq "no --base is a usage error" "2" "$?"
run usage --base master >/dev/null 2>&1
assert_eq "no check at all is refused" "2" "$?"
run usage --base nope --tree feat >/dev/null 2>&1
assert_eq "an unknown base is refused" "2" "$?"
run usage --base HEAD --tree feat >/dev/null 2>&1
assert_eq "an empty range is refused" "2" "$?"
git -C "$WORK/usage" checkout -q -b other master
echo o >"$WORK/usage/o.txt"; git -C "$WORK/usage" add o.txt; git -C "$WORK/usage" commit -qm other
run usage --base feat --tree feat >/dev/null 2>&1
assert_eq "a base that is not an ancestor is refused" "2" "$?"
run usage --base master --exec >/dev/null 2>&1
assert_eq "an option without its value is a usage error" "2" "$?"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
