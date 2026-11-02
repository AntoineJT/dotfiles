#!/usr/bin/env bash
# stack-verify.sh — prove that a rewritten branch carries the same change as before.
#
#   stack-verify.sh <old-base> <old-tip> <new-base> <new-tip>
#
# Compares the commits <old-base>..<old-tip> with <new-base>..<new-tip>. Prints:
#
#   commits  <n> = , <m> changed, <a> added, <r> removed   (from git range-diff)
#   patch    identical | differs     (base...tip, the tip's own diff since it forked, by stable patch-id)
#   tree     identical | differs     (<old-tip>^{tree} against <new-tip>^{tree})
#
# then, when any commit is not `=`, the full range-diff, and when the trees differ, the
# `git diff --stat` between the two tips. `tree differs` alone is expected when the new base
# brought other work; `patch identical` with every commit `=` is the proof.
#
# Exit: 0 every commit `=` and the patch identical; 1 something differs; 2 usage or a ref
# that does not resolve.
set -uo pipefail

[ $# -eq 4 ] || { echo "usage: $0 <old-base> <old-tip> <new-base> <new-tip>" >&2; exit 2; }
for r in "$@"; do
  git rev-parse -q --verify "$r^{commit}" >/dev/null || { echo "not a commit: $r" >&2; exit 2; }
done
ob="$1" ot="$2" nb="$3" nt="$4"

rd="$(git range-diff --no-color "$ob..$ot" "$nb..$nt" 2>&1)" || { printf 'git range-diff failed: %s\n' "$(printf '%s\n' "$rd" | head -1)" >&2; exit 2; }
# A range-diff header line reads `<i>:  <sha> <op> <j>:  <sha> <subject>`, op one of = ! < >.
ops="$(printf '%s\n' "$rd" | awk '/^ *(-|[0-9]+): +[-0-9a-f]+ [=!<>] (-|[0-9]+): +[-0-9a-f]+ / { for (i = 1; i <= NF; i++) if ($i ~ /^[=!<>]$/) { print $i; break } }')"
count() { printf '%s\n' "$ops" | grep -c "^$1\$"; }
eq=$(count =) ch=$(count '!') rm=$(count '<') ad=$(count '>')
echo "commits  $eq = , $ch changed, $ad added, $rm removed"

# Three dots: a parent that gained commits after the child was cut must not count as a change.
pid() { git diff "$1...$2" | git patch-id --stable | cut -d' ' -f1; }
if [ "$(pid "$ob" "$ot")" = "$(pid "$nb" "$nt")" ]; then patch=identical; else patch=differs; fi
echo "patch    $patch"

if [ "$(git rev-parse "$ot^{tree}")" = "$(git rev-parse "$nt^{tree}")" ]; then tree=identical; else tree=differs; fi
echo "tree     $tree"

[ $((ch + rm + ad)) -eq 0 ] || { echo; printf '%s\n' "$rd"; }
[ "$tree" = identical ] || { echo; git diff --stat "$ot" "$nt"; }
[ $((ch + rm + ad)) -eq 0 ] && [ "$patch" = identical ]
