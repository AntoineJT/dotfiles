---
name: pr-stack
description: "Manage stacked pull/merge requests — PR B targets PR A's branch, C targets B — on GitHub (`gh`) or GitLab (`glab`). Maps the stack (bases, heads, local branches, which worktree holds each), restacks children after a parent is merged (squash merges included) or rewritten with `git rebase --onto`, keeps a backup branch, proves with range-diff, patch-id and tree comparison that nothing changed, retargets bases, and force-pushes only with the user's yes. Use whenever the user asks to rebase, restack, sync or retarget PRs that depend on each other (« rebase la 13 14 », « la 12 est mergée, rebase les suivantes »), to open a PR on top of another in-flight PR, or mentions stacked PRs, gh-stack or GitHub Stacks — even when they only give PR numbers. Not for a plain rebase of one branch on the default branch, nor for a branch known to have no PR stacked on it."
allowed-tools: Bash, Read, Grep, Glob
---

Stack to handle: **$ARGUMENTS**

A **stack** is a chain of PRs where each one's base (target) branch is the previous one's head branch: `#12 (feat-a → master) ← #13 (feat-b → feat-a) ← #14 (feat-c → feat-b)`. When a lower PR changes (merged, rebased, amended), every PR above it must be moved onto its new tip.

**PR** means pull request or merge request throughout; use the forge's word with the user. Run the scripts from the user's repository as `bash <skill-dir>/scripts/<name>.sh`, `<skill-dir>` being the absolute folder this file was loaded from; each script's header is its contract (arguments, output lines, exit codes).

Rules, each because a hand-run stack broke on it:

- **Record every old tip before rewriting anything.** Once a parent moves, its old tip is what tells `rebase --onto` which commits belong to the child. `restack.sh` keeps it as `backup/<branch>-<reason>`; that backup is also the undo.
- **A branch checked out in another worktree** cannot be moved with `git branch -f` or checked out here. Work inside that worktree (`git -C <path>`), as the scripts do; never switch branches in a checkout someone else may be using.

## 0. Tooling

- Forge and CLI: as in the `pull-request` skill (remote host contains `github.` → `gh`, `gitlab.` → `glab`). Check auth (`gh auth status` / `glab auth status`); stop and tell the user if it fails.
- **GitHub's official stack extension**: `gh extension list | grep -q 'github/gh-stack'`. If installed, prefer it — it creates, rebases and syncs a whole stack, branches spread over several worktrees included; read `gh stack --help` before the first call rather than guessing subcommands, and still run § 4's proof and ask before anything it pushes. If it is absent, do not install it (`gh extension install github/gh-stack`) without asking; the steps below work without it.
- **GitHub native Stacks** (forge-side record of a stack): plain `gh` has no command and `gh pr view --json` does not expose it. Read it with `gh api repos/{owner}/{repo}/pulls/<n> --jq .stack` and `gh api repos/{owner}/{repo}/stacks/<id>` (gh fills `{owner}/{repo}`). Creating a stack or adding a PR to one through the API is **unverified**: say so, and point the user to the web UI or gh-stack rather than guessing an endpoint.

## 1. Map the stack

```bash
git fetch <remote>                      # origin unless the user's remotes say otherwise
bash <skill-dir>/scripts/stack-map.sh [--remote <remote>] <n>...   # GitHub; every PR the user named — open children are added
git worktree list
```

`stack-map.sh` prints one line per PR: state, base, head, the forge's head commit, how the local branch compares to it (`unfetched`, `absent`, `same`, `ahead`, `behind`, `diverged`, `restacked`), and the worktree that has it checked out. A child the forge already retargeted off a merged parent is found by ancestry, which needs its head locally: for an `unfetched` row (a fork's branch, a deleted one), `git fetch <remote> pull/<n>/head` and re-run; a fork's branch is pushed to the fork's remote, not `<remote>`. If the user speaks of PRs that follow and the map shows none, ask for their numbers. On GitLab, build the same table by hand: `glab mr view <n> --output json` (`source_branch`, `target_branch`, `state`, `sha`), children with `glab mr list --target-branch <head>`, plus the open MRs targeting `<default>` whose `sha` contains the merged MR's first commit (`git rev-list --reverse --topo-order <its sha> --not <remote>/<default> | head -1`, checked with `git merge-base --is-ancestor`), already retargeted.

Read it before acting, local-state rows (`behind`, `diverged`, `restacked`, `ahead`, `absent`) first:

| What the map shows | What it means | Do |
| --- | --- | --- |
| A PR `MERGED`, the next one still contains its commits (its base may already read `<default>`) | the parent landed; with a squash or rebase merge its commits are **not** ancestors of the default branch | restack the child onto `<remote>/<default>` from the parent's old head (the merged PR's `remote-sha`, still known to the forge: `git fetch <remote> pull/<n>/head` on GitHub, `merge-requests/<n>/head` on GitLab, if the object is missing) |
| A PR `MERGED` by a merge commit | the parent's commits are already in the default branch | `git merge-base --is-ancestor <old-parent-tip> <remote>/<default>` confirms it; the child only needs retargeting (§ 5), or a plain restack if the user wants it on the latest default branch |
| The user says « rebase 12 » | the default branch moved | restack #12 onto `<remote>/<default>` from `git merge-base <head> <remote>/<default>`, then each child from its parent's backup |
| Local `behind` | someone pushed commits on top | fast-forward first — `git -C <worktree> merge --ff-only <remote>/<b>`, or `git branch -f <b> <remote>/<b>` when no worktree holds it — then restack as usual. Default-branch commits in the dry run, or an `already contains` refusal, mean the forge merged the default branch in: ask whether the user wants a linear history |
| Local `diverged` (`restack.sh` refuses: the remote has commits the local branch lacks) | GitHub or a teammate already rebased the remote branch, or both sides have new work | compare: `stack-verify.sh <old-parent-tip> <b> <base the remote branch now sits on> <remote>/<b>` (that base: `<remote>/<parent-head>`, or `<remote>/<default>` once the parent is merged). All `=`: **sync instead of rebasing** — `git branch backup/<b>-sync <b>`, then `git -C <worktree> reset --keep <remote>/<b>` (or `git branch -f` when no worktree holds it). Anything else: show the user both sides and ask |
| Local `restacked` | an earlier run restacked it (the forge's commit is its backup) and did not push | never sync it, that would undo the restack: go on from the next branch up, its `<old-parent-tip>` being the backup the row names, then § 4 |
| Local `ahead` | unpushed local commits | they are part of what will be pushed: mention them to the user before § 4 |
| Local `absent` on an open PR | no local branch | `git branch <head> <remote>/<head>` before restacking it |

## 2. Restack, bottom-up

For each branch from the lowest one that moved to the top of the stack:

```bash
bash <skill-dir>/scripts/restack.sh --dry-run <new-base> <old-parent-tip> <branch>   # lists the commits it would replay
bash <skill-dir>/scripts/restack.sh <new-base> <old-parent-tip> <branch>
```

Add `--remote <remote>` when it is not `origin`: the script checks that the remote branch holds nothing the local one lacks.

- Check the dry run's list: it must be exactly the child's own commits. Extra commits mean `<old-parent-tip>` is wrong (often: the parent was rewritten after the child was cut — use the parent commit the child was actually cut from: `git merge-base --fork-point <remote>/<parent-head> <child>` while that ref's reflog has it, or the parent's last commit in `git log --oneline <new-base>..<child>`).
- For the next child up, `<new-base>` is the branch just restacked and `<old-parent-tip>` is its backup, the `backup` line `restack.sh` printed (`backup/<branch>-restack` by default, `-sync` if it was synced). A stack #12 (merged) ← #13 ← #14:

  ```bash
  bash <skill-dir>/scripts/restack.sh origin/master <old head of #12> feat-b
  bash <skill-dir>/scripts/restack.sh feat-b backup/feat-b-restack feat-c
  ```

- **Exit 3 — conflict**: the rebase waits in the worktree printed. Show the user the conflicting files (`git -C <wt> status --short`), resolve with them, then `git -C <wt> rebase --continue`, or `--abort` to put everything back; afterwards run the proof (`stack-verify.sh <old-parent-tip> backup/<b>-<reason> <new-base> <b>`) and `git worktree remove <wt>` if it was a temporary one. A resolved conflict makes that commit `!` in the range-diff (or a `<`/`>` pair with the same subject, when it changed most of a small commit), which is expected — say which commit and why.
- **Exit 1 — refused**: read the sentence; it names the fix (another `--reason`, a dirty worktree, a rebase an earlier run left on a conflict, a remote branch to sync first: § 1's `behind` / `diverged` rows).
- **Exit 4**: rebased, but the proof found a difference. Read the range-diff before going on.

## 3. Prove nothing changed

`restack.sh` ends with `stack-verify.sh`'s verdict (its header says how to read it); run it yourself for a branch moved any other way — by gh-stack, by syncing, by hand.

## 4. Push — only with the user's yes

Skip branches whose tip already equals the map's `remote-sha` (synced ones). For the others show the `stack-verify.sh` verdict, `git log --oneline <new-base>..<branch>` (the restack's base, not the PR's current one), and the remote commit it will replace (`remote-sha`); a restacked branch now reads `restacked` in the map, as expected. Ask. Then:

```bash
git push --force-with-lease=<branch>:<remote-sha> <remote> <branch>
```

The explicit `<remote-sha>` makes the push fail if someone pushed since you mapped; a bare `--force-with-lease` would compare against a remote-tracking ref that a later `git fetch` already updated; when it is rejected, re-run § 1 rather than retrying without it. Push the stack bottom-up, and retarget a child still based on a merged branch (§ 5, under the same yes) before pushing it, or its PR shows the parent's changes again.

## 5. Retarget and tidy

- After a parent merges, its children must point at the default branch. GitHub retargets them automatically when the merged head branch is deleted; GitLab may as well. Re-run the map with every PR number of the stack (restacked children no longer descend from the merged one), list the PRs still based on a merged branch, ask, then `gh pr edit <n> --base <default>` / `glab mr update <n> --target-branch <default>`.
- A new PR on top of an in-flight one: open it with the `pull-request` skill targeting the parent's head branch, and say in its description that it depends on the parent. On GitLab the target branch is what enforces the order; MR dependencies are recorded and shown, but not enforced on tiers without the feature.
- Update a PR description only if it quotes commit counts or hashes the rewrite changed.
- Leave the `backup/*` branches and list them in your report; delete them (`git branch -D backup/<…>`) only when the user says so.
