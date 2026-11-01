#!/usr/bin/env bash
# verify-split.sh — prove a rewritten history: every commit passes the checks, and the
# final tree is byte-identical to the original.
#
#   verify-split.sh --base <ref> [--tree <ref>] [--exec <cmd>] [--msg <cmd>]
#
# --base <ref>  the commit the rewrite starts from (prepare-split.sh's `base`); every commit
#               of <ref>..HEAD is checked, oldest first
# --tree <ref>  the original (the backup branch): HEAD's tree must equal its tree
# --exec <cmd>  run by `sh -c` at the root of the work tree, with each commit checked out
#               (detached); typically the build and the tests
# --msg <cmd>   run by `sh -c` at the root, with the commit's full message on stdin, from the current
#               checkout (the linter and its config as of HEAD), e.g. `pnpm exec commitlint`
# At least one of --tree, --exec, --msg.
#
# Refuses (exit 2) on staged or unstaged changes to tracked files: checking commits out
# would carry them along; and on an ignored file at a path some commit of the range
# touches (a local `.env` the branch untracked, say): checkouts would overwrite, then
# delete it. Other untracked and ignored files (dependencies, build output) stay
# across checkouts: <cmd> must regenerate what it depends on, or an early commit may pass
# on an artifact only the final state produces. A check that modifies tracked files
# (formatter, snapshot update, lockfile) fails that commit — the commit is not what it
# tests — and its changes are discarded (diff in the log) before the next checkout.
# Initialised submodules follow each commit (`git submodule update --recursive`); optional
# ones are not cloned. The branch
# is checked out again on exit, even after a failure or Ctrl-C.
#
# Output (stdout), one line per check, in this order:
#   exec <pass|FAIL> <short sha> <subject>[ (modified tracked files)| (checkout)]
#                    per commit, with --exec; `(checkout)` stops the run: usually an
#                    untracked file the check generated, which a later commit tracks
#   msg <pass|FAIL> <short sha> <subject>    per commit, with --msg
#   tree <equal|DIFFERENT> <HEAD tree> <ref tree>
#   logs <dir>   with --exec or --msg: <dir>/<n>-<short sha>.log and msg-<n>-<short sha>.log
#                hold each output (<dir> is created under $TMPDIR, default /tmp)
#
# Exit: 0 every check passed; 1 at least one FAIL or DIFFERENT; 2 usage or refusal.
set -uo pipefail

die() { echo "verify-split: $*" >&2; exit 2; }
usage() { die "usage: verify-split.sh --base <ref> [--tree <ref>] [--exec <cmd>] [--msg <cmd>]"; }

base='' tree_ref='' exec_cmd='' msg_cmd=''
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --base) base="$2" ;;
    --tree) tree_ref="$2" ;;
    --exec) exec_cmd="$2" ;;
    --msg) msg_cmd="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$base" ] || usage
[ -n "$tree_ref$exec_cmd$msg_cmd" ] || die "nothing to check: pass --tree, --exec or --msg"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git work tree"
# From the root: a subdirectory only later commits contain would vanish under an early checkout.
cd "$(git rev-parse --show-toplevel)" || die "cannot enter the work tree's root"
git rev-parse -q --verify "$base^{commit}" >/dev/null || die "unknown base '$base'"
[ -z "$tree_ref" ] || git rev-parse -q --verify "$tree_ref^{commit}" >/dev/null || die "unknown tree ref '$tree_ref'"
git merge-base --is-ancestor "$base" HEAD || die "'$base' is not an ancestor of HEAD"

failed=0
commits="$(git rev-list --reverse "$base..HEAD")"
[ -n "$commits" ] || die "no commit between '$base' and HEAD"

clean() { git diff --quiet && git diff --cached --quiet; }
logs=''
if [ -n "$exec_cmd$msg_cmd" ]; then
  [ -z "$exec_cmd" ] || clean \
    || die "tracked files have uncommitted changes: commit or stash them before checking commits out"
  logs="$(mktemp -d "${TMPDIR:-/tmp}/verify-split.XXXXXX")" || die "mktemp failed"
fi

if [ -n "$exec_cmd" ]; then
  start="$(git symbolic-ref --short -q HEAD || git rev-parse HEAD)"
  # One pass over both lists: an ignored entry is at risk when a path the range touches is
  # that entry, or lies under it (a `dir/` entry).
  touched="$(git log --format= --name-only -z "$base..HEAD" | tr '\0' '\n' | sort -u)"
  at_risk="$( (printf '%s\n' "$touched"; echo '//'; git ls-files -z -o -i --exclude-standard --directory | tr '\0' '\n') |
    awk '$0 == "//" { list = 1; next }
         !list { t[$0] = 1; next }
         $0 in t { print; next }
         /\/$/ { for (x in t) if (index(x, $0) == 1) { print; next } }')"
  [ -z "$at_risk" ] || die "ignored files at paths the branch touches would be overwritten by the checkouts; move them aside first: $(printf '%s' "$at_risk" | tr '\n' ' ')"
  # goto <checkout args>: a checkout that submodules follow. -f only where the changes in the
  # way came from the check (the tree was clean at the start): never over the user's files.
  goto() {
    git checkout -q "$@" || return 1
    # Initialised submodules only: --init would clone optional ones, or fail offline.
    [ ! -f .gitmodules ] || git submodule update --recursive -q
  }
  trap 'goto -f "$start" -- 2>/dev/null || echo "verify-split: could not check out $start again" >&2' EXIT
  trap 'exit 130' INT TERM
  n=0
  for c in $commits; do
    n=$((n + 1))
    short="$(git rev-parse --short "$c")"
    subject="$(git log -1 --format=%s "$c")"
    log="$logs/$n-$short.log"
    if ! goto --detach "$c" >"$log" 2>&1; then
      echo "exec FAIL $short $subject (checkout)"
      echo "verify-split: could not check out $short (see $log); stopping" >&2
      failed=1
      break
    fi
    if sh -c "$exec_cmd" >>"$log" 2>&1; then status=pass; else status=FAIL; fi
    if clean; then
      echo "exec $status $short $subject"
    else
      echo "exec FAIL $short $subject (modified tracked files)"
      { echo "--- tracked changes made by the check:"; git diff HEAD; } >>"$log" 2>&1
      status=FAIL
      goto -f --detach "$c" >>"$log" 2>&1 || { echo "verify-split: could not reset $short (see $log); stopping" >&2; failed=1; break; }
    fi
    [ "$status" = pass ] || failed=1
  done
  trap - EXIT INT TERM
  goto -f "$start" -- || { echo "verify-split: could not check out $start again" >&2; failed=1; }
fi

if [ -n "$msg_cmd" ]; then
  n=0
  for c in $commits; do
    n=$((n + 1))
    short="$(git rev-parse --short "$c")"
    subject="$(git log -1 --format=%s "$c")"
    if git log -1 --format=%B "$c" | sh -c "$msg_cmd" >"$logs/msg-$n-$short.log" 2>&1; then
      echo "msg pass $short $subject"
    else
      echo "msg FAIL $short $subject"
      failed=1
    fi
  done
fi

if [ -n "$tree_ref" ]; then
  mine="$(git rev-parse "HEAD^{tree}")"
  theirs="$(git rev-parse "$tree_ref^{tree}")"
  if [ "$mine" = "$theirs" ]; then
    echo "tree equal $mine $theirs"
  else
    echo "tree DIFFERENT $mine $theirs"
    failed=1
  fi
fi

[ -z "$logs" ] || echo "logs $logs"
exit "$failed"
