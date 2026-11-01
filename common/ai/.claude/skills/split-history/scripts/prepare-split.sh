#!/usr/bin/env bash
# prepare-split.sh — back up the current branch, then collapse it onto its base, ready to
# be recommitted piece by piece.
#
#   prepare-split.sh <reason> [<base-ref>]
#
# <reason>    a short slug for the backup's name: backup/<branch>-<reason>
# <base-ref>  what the branch is split against; the script uses its merge-base with HEAD.
#             Default: origin's default branch (origin/HEAD). To split only the last WIP
#             commit, pass HEAD~1.
#
# Refuses (exit 2, nothing changed) on: detached HEAD, staged or unstaged changes to tracked
# files, an existing backup branch, no origin/HEAD and no <base-ref>, a base that is HEAD
# itself (nothing to split).
#
# Then: creates the backup branch at HEAD, and `git reset --mixed <merge-base>` — the
# working tree keeps the final state untouched, the index and HEAD go back to the base, so
# every file of the branch shows as an unstaged change to commit again.
#
# Output (stdout), one line each:
#   backup <branch> <sha>
#   base <merge-base sha>
#   tree <the backup's tree hash — the final tree every rewrite must reproduce>
#
# Exit: 0 done; 2 refused or usage.
set -uo pipefail

die() { echo "prepare-split: $*" >&2; exit 2; }

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: prepare-split.sh <reason> [<base-ref>]"
reason="$1"
case "$reason" in
  '' | *[!A-Za-z0-9._-]*) die "reason must be a slug (letters, digits, . _ -), got '$reason'" ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git work tree"
branch="$(git symbolic-ref --short -q HEAD)" || die "HEAD is detached: check out the branch to split first"
git diff --quiet && git diff --cached --quiet \
  || die "tracked files have uncommitted changes: commit or stash them first, they would end up mixed into the split"

if [ $# -eq 2 ]; then
  base_ref="$2"
else
  base_ref="$(git symbolic-ref --short -q refs/remotes/origin/HEAD)" \
    || die "origin/HEAD is unset: run 'git remote set-head origin -a', or pass the base ref"
fi
git rev-parse -q --verify "$base_ref^{commit}" >/dev/null || die "unknown base ref '$base_ref'"

backup="backup/$branch-$reason"
git check-ref-format --branch "$backup" >/dev/null 2>&1 || die "'$backup' is not a valid branch name"
git rev-parse -q --verify "refs/heads/$backup" >/dev/null \
  && die "branch '$backup' already exists: pick another reason, or delete it if it is stale"

head="$(git rev-parse HEAD)"
base="$(git merge-base "$base_ref" HEAD)" || die "'$base_ref' and HEAD share no history"
[ "$base" != "$head" ] || die "HEAD is the base itself: there is nothing to split"

git branch "$backup" "$head" || die "could not create '$backup'"
git reset -q --mixed "$base" || die "reset failed; the branch is intact at $backup"

echo "backup $backup $head"
echo "base $base"
echo "tree $(git rev-parse "$head^{tree}")"
