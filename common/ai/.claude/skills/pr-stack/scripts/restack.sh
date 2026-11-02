#!/usr/bin/env bash
# restack.sh — move one branch of a stack onto its parent's new tip, with a backup and a proof.
#
#   restack.sh [--dry-run] [--reason <word, no dash>] [--remote <name>] <new-base> <old-parent-tip> <branch>
#
# Replays the commits <old-parent-tip>..<branch> onto <new-base> (`git rebase --onto`).
# <old-parent-tip> is where the parent stood before it moved: its backup branch, the PR's old
# head commit, or, for the bottom of the stack, `git merge-base <branch> <old-default-tip>`.
#
# Where: in the worktree that has <branch> checked out; when none has, in a temporary
# worktree it creates and removes, so no checkout in use changes branch.
#
# Prints `replay <n> commits onto <new-base>:` and their one-line log, then (not with
# --dry-run): `backup <ref> <sha>`, `rebased <branch> <old-sha> -> <new-sha>`, and the output
# of stack-verify.sh comparing the two ranges.
#
# Refuses (exit 1, nothing rewritten) when: <remote> is not a configured remote; a ref does not
# resolve; the worktree holding the branch has uncommitted changes to tracked files or an
# operation in progress; nothing would be replayed; <branch> already contains <new-base>;
# <remote>/<branch> has commits the local branch lacks (pushed or restacked elsewhere: sync the
# local branch first, or a later push would drop them) and is not contained in one of its
# backup/<branch>-<reason> (your own restack, not pushed yet); a rebase of <branch> is in progress
# in another worktree (a conflict left by an earlier run); the backup ref backup/<branch>-<reason>
# exists at another commit; git refuses to start the rebase (its message follows).
#
# Exit: 0 rebased and every commit `=`; 1 refused; 2 usage; 3 conflict — the rebase is left in
# progress in the worktree printed (resolve then `git -C <wt> rebase --continue`, or
# `git -C <wt> rebase --abort`; a temporary worktree is then removed with
# `git worktree remove <wt>`); 4 rebased, but stack-verify.sh found a difference (read it).
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

usage() { echo "usage: $0 [--dry-run] [--reason <word>] [--remote <name>] <new-base> <old-parent-tip> <branch>" >&2; exit 2; }
refuse() { echo "refused: $*" >&2; exit 1; }
dry=0 reason=restack remote=origin
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --reason) [ $# -ge 2 ] || usage; reason="$2"; shift 2 ;;
    --remote) [ $# -ge 2 ] || usage; remote="$2"; shift 2 ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -eq 3 ] || usage
case "$reason" in ''|*[!A-Za-z0-9._]*) usage ;; esac  # no dash: backup/<branch>-<reason> stays unambiguous
newbase="$1" from="$2" branch="$3"

commit() { git rev-parse -q --verify "$1^{commit}"; }
# own_backup <sha>: a backup/<branch>-<reason> that contains <sha> (not a sibling's backup/<branch>-x-<reason>).
own_backup() {
  git for-each-ref --contains "$1" --format='%(refname)' refs/heads/backup/ \
    | awk -v p="refs/heads/backup/$branch-" 'index($0, p) == 1 && substr($0, length(p) + 1) !~ /[-\/]/ { print substr($0, 12); exit }'
}
git remote get-url "$remote" >/dev/null 2>&1 || refuse "no remote named $remote: pass --remote <name>"
nb="$(commit "$newbase")" || refuse "not a commit: $newbase"
fr="$(commit "$from")" || refuse "not a commit: $from"
old="$(commit "refs/heads/$branch")" || refuse "no local branch $branch"

n="$(git rev-list --count "$fr..$old")"
[ "$n" -gt 0 ] || refuse "$from..$branch is empty: nothing to replay"
git merge-base --is-ancestor "$nb" "$old" && refuse "$branch already contains $newbase"
if rem="$(commit "refs/remotes/$remote/$branch")" && ! git merge-base --is-ancestor "$rem" "$old" \
  && [ -z "$(own_backup "$rem")" ]; then
  refuse "$remote/$branch has commits $branch lacks (pushed or restacked elsewhere): fast-forward or sync the local branch first. To compare: bash $here/stack-verify.sh $fr $branch <parent's new tip> $remote/$branch"
fi

wt="$(git worktree list --porcelain | awk -v ref="refs/heads/$branch" '
  /^worktree / { path = substr($0, 10) }
  $0 == "branch " ref { print path; exit }')"
if [ -n "$wt" ]; then
  [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ] || refuse "$wt has uncommitted changes"
  for op in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    p="$(git -C "$wt" rev-parse --path-format=absolute --git-path "$op")"
    [ ! -e "$p" ] || refuse "$wt has an operation in progress ($op)"
  done
fi

# A rebase stopped on a conflict runs detached: find it by its head-name, in git's own state
# files, which outlive a temporary worktree folder the system purged.
common="$(git rev-parse --path-format=absolute --git-common-dir)"
for h in "$common"/rebase-*/head-name "$common"/worktrees/*/rebase-*/head-name; do
  [ -f "$h" ] && [ "$(cat "$h")" = "refs/heads/$branch" ] || continue
  d="${h%/rebase-*}"
  if [ "$d" = "$common" ]; then p="$(cd "$common/.." && pwd -P)"; else p="$(sed 's#/\.git$##' "$d/gitdir")"; fi
  refuse "a rebase of $branch is in progress in $p: continue or abort it there, or \`git worktree prune\` if that folder is gone"
done

backup="backup/$branch-$reason"
if b="$(commit "refs/heads/$backup")" && [ "$b" != "$old" ]; then
  refuse "$backup exists at another commit ($b): pass another --reason"
fi

echo "replay $n commits onto $newbase:"
git log --oneline --no-decorate "$fr..$old"
[ "$dry" -eq 0 ] || exit 0

git branch -f "$backup" "$old" >/dev/null || refuse "could not create $backup"
echo "backup $backup $old"

tmp=""
if [ -z "$wt" ]; then
  tmp="$(mktemp -d)" || refuse "mktemp failed"
  wt="$tmp"
  git worktree add -q "$wt" "$branch" || refuse "could not add a temporary worktree for $branch"
fi
# rebase.updateRefs would move the backup along with the branch, and lose the old tip.
if ! err="$(git -C "$wt" -c rebase.updateRefs=false rebase -q --onto "$nb" "$fr" "$branch" 2>&1)"; then
  if [ -e "$(git -C "$wt" rev-parse --path-format=absolute --git-path rebase-merge)" ] \
    || [ -e "$(git -C "$wt" rev-parse --path-format=absolute --git-path rebase-apply)" ]; then
    printf '%s\n' "$err" >&2
    echo "conflict: the rebase is in progress in $wt" >&2
    exit 3
  fi
  [ -z "$tmp" ] || git worktree remove --force "$wt"
  refuse "git did not start the rebase: $err"
fi
[ -z "$tmp" ] || git worktree remove "$wt"

new="$(commit "refs/heads/$branch")"
echo "rebased $branch $old -> $new"
bash "$here/stack-verify.sh" "$fr" "$old" "$nb" "$new" || exit 4
