#!/usr/bin/env bash
# stack-map.sh — map a stack of GitHub pull requests onto the local repository.
#
#   stack-map.sh [--remote <name>] <pr-number>...
#
# Run inside the repository, after `git fetch <remote>`. For each PR given, and for every open
# PR whose base is the head branch of a PR already listed, or whose head contains a listed
# MERGED PR's first commit while its base (<remote>/<base>) does not (a child the forge already
# retargeted), followed recursively, prints one tab-separated line after a `#`-prefixed header:
#
#   <number> <state> <base> <head> <remote-sha> <local> <worktree>
#
#   remote-sha  the PR's head commit on the forge (headRefOid), in full: the push lease
#   local       the local branch <head> against that commit: unfetched (commit not in the
#               local object store: fetch it first) | absent (no local branch) | same |
#               ahead N | behind N | diverged +A -B | restacked +A -B <backup> (diverged, and the
#               forge's commit is in <backup>, a backup/<head>-<reason> restack.sh made: restacked,
#               not pushed yet; <backup> is the next child's <old-parent-tip>)
#   worktree    the worktree that has <head> checked out, or `-`
#
# Rows come in discovery order; the base and head columns give the stack's order.
# Read-only: it never fetches, checks out or edits anything.
# Exit: 0 printed; 1 a `gh` call failed (the message says which); 2 usage.
# Environment: GH — the gh binary (default `gh`; the suite points it at a stub).
set -uo pipefail
GH="${GH:-gh}"

usage() { echo "usage: $0 [--remote <name>] <pr-number>..." >&2; exit 2; }
remote=origin
[ "${1:-}" = --remote ] && { [ $# -ge 2 ] || usage; remote="$2"; shift 2; }
[ $# -ge 1 ] || usage
for n in "$@"; do case "$n" in ''|*[!0-9]*) usage ;; esac; done
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not inside a git repository" >&2; exit 2; }

# worktree_of <branch>: path of the worktree that has refs/heads/<branch> checked out.
worktree_of() {
  git worktree list --porcelain | awk -v ref="refs/heads/$1" '
    /^worktree / { path = substr($0, 10) }
    $0 == "branch " ref { print path; exit }'
}

local_state() { # <branch> <remote-sha>
  local b="$1" sha="$2" bk
  git cat-file -e "$2^{commit}" 2>/dev/null || { echo unfetched; return; }
  git rev-parse -q --verify "refs/heads/$1" >/dev/null || { echo absent; return; }
  set -- $(git rev-list --left-right --count "refs/heads/$1...$2")
  if [ "$1" -eq 0 ] && [ "$2" -eq 0 ]; then echo same
  elif [ "$2" -eq 0 ]; then echo "ahead $1"
  elif [ "$1" -eq 0 ]; then echo "behind $2"
  elif bk="$(git for-each-ref --contains "$sha" --format='%(refname)' refs/heads/backup/ \
    | awk -v p="refs/heads/backup/$b-" 'index($0, p) == 1 && substr($0, length(p) + 1) !~ /[-\/]/ { print substr($0, 12); exit }')" \
    && [ -n "$bk" ]; then
    echo "restacked +$1 -$2 $bk"
  else echo "diverged +$1 -$2"; fi
}

queue=" $* " seen=" "
printf '#pr\tstate\tbase\thead\tremote-sha\tlocal\tworktree\t(remote %s)\n' "$remote"
while :; do
  set -- $queue
  [ $# -gt 0 ] || break
  n="$1"; shift; queue=" $* "
  case "$seen" in *" $n "*) continue ;; esac
  seen="$seen$n "
  line="$("$GH" pr view "$n" --json number,state,baseRefName,headRefName,headRefOid \
    --jq '[.number, .state, .baseRefName, .headRefName, .headRefOid] | @tsv')" \
    || { echo "gh pr view $n failed" >&2; exit 1; }
  IFS="$(printf '\t')" read -r num state base head sha <<EOF
$line
EOF
  wt="$(worktree_of "$head")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$num" "$state" "$base" "$head" \
    "$sha" "$(local_state "$head" "$sha")" "${wt:--}"
  kids="$("$GH" pr list --base "$head" --state open --limit 1000 --json number --jq '.[].number')" \
    || { echo "gh pr list --base $head failed" >&2; exit 1; }
  if [ "$state" = MERGED ]; then
    # Its first commit, not its final head: a child is often cut before the parent's review fixes.
    # Found locally, in topological order; none when its base already holds it (a merge commit);
    # its head when <remote>/<base> is gone.
    first="$sha"
    if git rev-parse -q --verify "refs/remotes/$remote/$base" >/dev/null; then
      first="$(git rev-list --reverse --topo-order "$sha" --not "refs/remotes/$remote/$base" 2>/dev/null | head -1)"
    fi
    open_prs="$("$GH" pr list --state open --limit 1000 --json number,headRefOid,baseRefName \
      --jq '.[] | "\(.number) \(.headRefOid) \(.baseRefName)"')" \
      || { echo "gh pr list --state open failed" >&2; exit 1; }
    while read -r k ksha kbase; do
      [ -n "$k" ] && [ -n "$first" ] || continue
      git merge-base --is-ancestor "$first" "$ksha" 2>/dev/null \
        && ! git merge-base --is-ancestor "$first" "refs/remotes/$remote/$kbase" 2>/dev/null \
        && kids="$kids $k"
    done <<LIST
$open_prs
LIST
  fi
  queue="$queue$(echo $kids) "
done
