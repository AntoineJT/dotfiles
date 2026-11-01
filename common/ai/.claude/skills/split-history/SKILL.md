---
name: split-history
description: "Rewrite a branch's history into reviewable commits, or split a WIP commit, so that every commit builds and passes the tests and the final tree stays byte-identical to the original. Backs the branch up, squashes it onto its merge-base, recommits it by concern without interactive git, proves each commit and the final tree with scripts, and asks before any force-push. Use whenever the user wants commits cut, regrouped, reordered or cleaned up before review — « découpe le WIP en vrais commits », « réécris l'historique de la PR », « la PR est trop grosse, redécoupe-la », \"split this branch into commits\", \"clean up the history before review\" — even when they do not say rebase. Not for rebasing stacked branches (pr-stack), rewording one message, squash-merging, reverting, or splitting a PR into several PRs (this keeps one branch)."
---

Rewrite the history of: **$ARGUMENTS** (the current branch when nothing is named).

The result must be a history a reviewer reads once, top to bottom: each commit one concern, each commit green, and the last one holding exactly the tree the user had — not a near copy.

## 1. Read the ground

- **Base ref**: `git fetch origin`, then the default branch — `git symbolic-ref --short refs/remotes/origin/HEAD` (prints `origin/<name>`; unset: `git remote set-head origin -a`). For a WIP commit at the tip of an otherwise clean branch, the base is `HEAD~1`, not the default branch.
- **The check that proves a commit**: the repo's build and test commands, from its `CLAUDE.md`/`AGENTS.md`, `CONTRIBUTING`, `package.json` scripts, `Makefile` or CI workflow. Run it once on the current tip before touching anything: a tip that already fails cannot prove its commits; tell the user and stop. Note how the test runner reports its count — it goes in the summary for every commit.
- **The message convention**: a commitlint (or similar) config in the repo, `CONTRIBUTING`, and `git log --format=%s -20 <base ref>` — scope style, language, case. If a linter exists, it is a second check on every commit.
- **Behind its upstream** (`git status -sb` says `behind`): someone pushed commits the rewrite would drop. Stop and integrate them first.
- **Branches built on this one**: `git for-each-ref --format='%(refname:short)' --contains "$(git rev-list --reverse <base>..HEAD | head -1)" refs/heads`, minus this branch. They will need rebasing after the rewrite — note them now.

## 2. Plan the commits

Read the whole change (`git diff --stat <base>...HEAD`, then the diff, and the existing commit messages — they often name the concerns already). Group by concern and order so that each commit compiles on its own:

1. shared code first (libraries, types, schema/migrations, helpers),
2. then the feature that uses it,
3. then the wiring (registration, configuration, routes, entry points),
4. docs with the step they document.

Tests go **with the code they test**, in the same commit — a commit of code without its tests is unproven, and a trailing "add tests" commit proves nothing about the commits before it.

Two rules decide the boundaries:

- **Fewer commits beat fabricated ones.** If separating two concerns means writing an intermediate version of some code that never existed and was never tested — a stub, a half-function, a temporary import — keep them in one commit and say why in its body. Planning four commits and shipping three is a good outcome when the fourth needed invented code.
- **Remove before add.** Never split out code that a later commit deletes or rewrites: the reviewer would read, and judge, code that does not survive. If the branch added something and later replaced it, the history shows only the final version.

Intermediate states come from states that existed: the final tree, or a file as it was in one of the original commits (`git show <old-commit>:<path>`). Show the plan (titles, files per commit) in a few lines and proceed — a local rewrite is reversible from the backup.

## 3. Back up and collapse

```bash
bash ~/.claude/skills/split-history/scripts/prepare-split.sh <reason> [<base-ref>]
```

It creates `backup/<branch>-<reason>` (e.g. `backup/feature/x-split` for `feature/x`), then resets HEAD and the index to the merge-base while the work tree keeps the final state; it prints `backup`, `base` and `tree` lines — keep the base sha and backup name for § 4–5, they do not survive between shell calls.

## 4. Recommit, concern by concern

The work tree is the final state; stage each commit's share of it, oldest first, and commit with the title in the repo's convention and a body that says **why** (the diff already says what):

| The commit takes… | Stage it with |
| --- | --- |
| whole files | `git add -- <paths>` (a force-added ignored file: `git add -f`; a file the branch untracked but kept on disk: `git rm --cached -- <path>`) |
| a file as an original commit had it | `git restore --source=<old-commit> --staged -- <path>` (the work tree is not touched) |
| some hunks of a file | `git add -N -- <path>` if the branch created it, `git diff -- <path> > <tmp>.diff` (`<tmp>` from `mktemp`), delete the unwanted hunks or `+` lines from it, `git apply --cached --recount <tmp>.diff` |

Commit with `git commit -F <file>` or `-m <title> -m <body>`. After the last commit, `git status` shows nothing tracked left over (a forgotten new file shows only as untracked — the tree check in § 5 catches it). New commits carry the current git identity: when the branch's commits are someone else's, pass `--author="$(git log -1 --format='%an <%ae>' <backup>)"`.

**No interactive git**: never `git rebase -i`, `git add -p` or `git commit` without `-m`/`-F` — they wait for an editor or a keyboard that does not exist here. To fix a commit already made: commit the fix with `git commit --fixup=<sha>` and fold it in with `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash --autostash <base>` (the `:` editor accepts the todo unchanged; `--autostash` because the rest of the final state is still unstaged — `git reset -- <path>` any `add -N` file first, or the stash fails; on a conflict, `git rebase --abort`). To change the grouping wholesale, start over: `git reset -q <base>` — the work tree is still the final state, the backup is untouched.

## 5. Prove, then ask

```bash
bash ~/.claude/skills/split-history/scripts/verify-split.sh --base <base> --tree <backup> --exec '<build && test>' [--msg '<message linter reading stdin>']
```

The check must rebuild what it depends on — build output from the final state stays on disk while earlier commits are checked out (see the script's header). A `FAIL` names the commit: read its log, regroup (§ 2 rules still apply), rerun. A `(checkout)` failure is usually a file the check generated that a later commit tracks: make the check clean its output, or commit that file earlier. Long test suites: give the call a generous timeout. Then show the user:

- old vs new: `git log --oneline <base>..<backup>` and `git log --oneline <base>..HEAD`;
- the `tree equal` line;
- per commit: pass/fail and its test count — grep each `exec` log for the count line noted in § 1;
- any concern kept together on purpose, and why.

Rewriting published history needs the user's yes. Only then: `git push --force-with-lease --force-if-includes origin <branch>`. Branches noted in § 1 as built on this one are rebased next with `pr-stack`. The backup branch stays until the user deletes it.
