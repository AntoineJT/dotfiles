---
name: pull-request
description: Open or update a pull/merge request on GitHub (`gh`) or GitLab (`glab`). Detects the forge, always checks for an existing PR first (never duplicates), writes a whole-diff description at a higher altitude than the commits — bilingual 🇬🇧/🇫🇷 by default, configurable with `--lang=<ISO 639-1 codes>` — applies only labels that already exist (suggests new ones but never creates them implicitly), and keeps an existing PR's description in sync. Use when asked to open/create/raise/update a PR/MR/pull request/merge request.
allowed-tools: Bash, Read, Grep, Glob
---

Open or update the pull/merge request for: **$ARGUMENTS**

**Vocabulary.** This file says **PR** throughout. GitHub calls it a *pull request*, GitLab a *merge request* — the workflow is the same, only the CLI and a few flags differ. When talking back to the user, use **their forge's word** ("MR" on GitLab), and use it in the description too.

The golden rules:

- 🚫 **Never create a duplicate** — always check for an existing PR on the source branch first.
- 🏷️ **Never create labels implicitly** — apply only labels that already exist; *suggest* new ones (matching the repo's conventions) and create them only on explicit user approval.
- 📄 **The description describes the *whole* diff** (target…HEAD), at a higher altitude than the commits. Per-step detail already lives in the commit messages — do not just concatenate them.
- ✅ Confirm the title / description / labels with the user before the create/update call (a PR is outward-facing).
- 🖥️ **CLI only** — never the web UI. If the forge's CLI is missing or unauthenticated, stop and tell the user (`gh auth login` / `glab auth login`).

> **Local conventions layer on top.** Label taxonomy, commit-footer requirements, branch
> hierarchy and forge choice are org- and repo-specific. A wrapper skill (e.g. `{org}-pr`)
> may invoke this one and add them; wherever a wrapper's rule conflicts with this file,
> **the wrapper wins**. With no wrapper, follow this file as written and read the conventions
> off the repo itself (recent PRs, the label list).

## ⚙️ Options

| Option | Default | Effect |
| --- | --- | --- |
| `--lang=<codes>` | `en,fr` | Ordered, comma-separated **ISO 639-1** codes for the description. The **first is primary** and opens the body. One code → monolingual. Two or more → one mirrored block per language (see Step 2). |
| `--forge=<github\|gitlab>` | auto-detected | Forces the forge when detection is ambiguous (self-hosted instance, several remotes). |

Read options off `$ARGUMENTS`; everything left over is the change to describe. A wrapper skill may pin different defaults — honour them even when the user's invocation omits the flag, unless the user explicitly passes another value. If a language code isn't valid ISO 639-1 (`fr`, not `fra` or `fr-FR`), ask rather than guess.

## 🔀 Forge detection and command mapping

```bash
git remote get-url origin     # the host names the forge
```

Match the host as a **substring**, not by equality — a remote may carry a service prefix (`git@ssh.gitlab.example.io:…`). `github.` → **GitHub / `gh`**; `gitlab.` → **GitLab / `glab`**. When the host names neither, probe: `gh repo view` in a non-GitHub repo fails with *"none of the git remotes configured for this repository point to a known GitHub host"*, which is itself a usable signal. `--forge=` overrides everything.

Every step below is forge-neutral prose plus this mapping:

| Action | GitHub (`gh`) | GitLab (`glab`) |
| --- | --- | --- |
| Auth check | `gh auth status` | `glab auth status` |
| Repo resolves | `gh repo view` | `glab repo view` |
| Existing PR on branch | `gh pr list --head "$BRANCH" --state all` | `glab mr list --source-branch "$BRANCH" --all` |
| Read one PR | `gh pr view <n> --json title,body,labels,baseRefName,state` | `glab mr view <n> --output json` |
| Create | `gh pr create --head "$BRANCH" --base "<target>" --title … --body-file <f> --label …` | `glab mr create --source-branch "$BRANCH" --target-branch "<target>" --title … --description "$(cat <f>)" --label … --yes` |
| Update body | `gh pr edit <n> --body-file <f>` | `glab mr update <n> --description "$(cat <f>)"` |
| Update title | `gh pr edit <n> --title …` | `glab mr update <n> --title …` |
| Add / remove label | `gh pr edit <n> --add-label … --remove-label …` | `glab mr update <n> --label … --unlabel …` |
| Draft | `--draft` on create | `--draft` on create (GitLab implements it as a `Draft:` title prefix) |
| Delete source branch on merge | repo-level (`gh repo edit --delete-branch-on-merge`) or `gh pr merge --delete-branch` — **no per-PR create flag** | `--remove-source-branch` on create |
| List labels | `gh label list` | `glab label list` |
| Create label | `gh label create <name> --color <rrggbb> --description …` — name is **positional**, colour is 6 hex chars **without `#`**, and gh picks a **random colour** when you omit it, so always pass one | `glab label create --name <name> --color '#rrggbb' --description …` — name is a **flag**, colour takes the leading `#` |

Write the body to a **file** and pass it by path (`--body-file`) or by substitution (`"$(cat …)"`) — never inline a multi-paragraph description in the shell, where quoting and emoji get mangled.

⚠️ **`-` means opposite things on the two CLIs.** `gh … --body-file -` reads the body **from stdin**. `glab … --description -` **opens an editor** — which hangs a non-interactive session. So on GitLab always pass the text itself (`--description "$(cat <f>)"`), never `-`; `glab` has no description-from-file flag at all.

⚠️ **On GitLab, editing the title of a draft MR un-drafts it — silently.** GitLab has no draft field; it *is* the `Draft: ` title prefix, which the table above notes for creation and which bites hardest on update. `glab mr update <n> --title "…"` therefore replaces the prefix with nothing, reports `✓ updated title to …`, and says not a word about the MR having become reviewable. So when changing a draft's title, **carry the prefix yourself** (`--title "Draft: <new title>"`), then verify — the CLI's success line is not evidence:

```bash
glab api "projects/:id/merge_requests/<n>" | jq -r .draft   # must print true
```

**GitHub is not affected**: a PR there has a real `isDraft` boolean, moved with `gh pr ready`, so `gh pr edit --title` leaves the draft state alone. It is a GitLab-only trap, which is what makes it easy to carry the wrong assumption across forges.

When a flag is uncertain, run `<cli> <command> --help` rather than guessing: the two CLIs diverge in naming more than you'd expect (`--body` vs `--description`, positional vs flag label name, `--add-label` vs `--label`).

## Step 0 — Preconditions

Auth check + repo resolution per the table, then:

```bash
BRANCH=$(git branch --show-current)
```

Pick the **target branch** (do not assume the default branch): if the source looks like a sub-branch of another in-flight branch, the target is usually that parent. Determine the merge-base parent (`git log --decorate`, the tracking branch, or the branch it was cut from); if ambiguous, ask. Default to the repo's default branch only when nothing else fits.

Ensure the branch is pushed (PR creation needs it on the remote):

```bash
git push -u origin "$BRANCH"   # confirm with the user first if it would publish new commits
```

## Step 1 — Does a PR already exist? (never duplicate)

Run the *existing PR on branch* command from the table.

- **Open PR exists** → switch to **update mode** (Step 4b). Do not create another.
- **Merged/closed PR exists** → report its state and ask before doing anything (a new PR for a merged branch is almost always a mistake).
- **None** → if the user asked to create one, go to Step 2.

If the user's wording implies a PR may already exist ("update the PR", "the MR for…"), this check is mandatory before anything else.

## Step 2 — Build the whole-diff description

```bash
git diff <target>...HEAD --stat      # scope of the whole change
git log <target>..HEAD --format='%s' # the commits (for orientation, not for copying)
```

Synthesize a reviewer-facing summary of the **entire** branch — what it does and why, the shape of the change, notable decisions, validation, and any follow-ups. Higher altitude than the commits.

**Whenever the objective is not trivially inferable, give it its own `## 🤔 Motivation` section** — don't bury the *why* in the summary line. A reviewer should never have to ask "why did they do this?". If *what* the change does already makes the *why* obvious (e.g. "fix typo in error message"), omit the section entirely; but whenever the goal is non-obvious (a coupling, a skip, an exclusion, an unusual mechanism, a trade-off), spell out the problem it solves, the cost it avoids, or the constraint it works around. The Motivation section sits right after `## 🎯 Summary` and stays at problem-level — no implementation detail, that belongs in `## 📦 What's included`.

Single-language skeleton (`--lang=en`):

```markdown
## 🎯 Summary
<one short paragraph: what this PR delivers>

## 🤔 Motivation
<why — problem solved / cost avoided / constraint worked around. Include whenever the goal
isn't trivially inferable from the "what"; omit the whole section when the what makes the
why obvious. Problem-level, no implementation detail.>

## 📦 What's included
- ✨ <feature / addition>
- 🔧 <change / refactor>
- 📝 <docs>
- ✅ <tests / validation: what was run, results>

## 🧭 Notes
- ⚠️ <caveat, breaking change, ordering dependency>
- 🔭 <known follow-ups / open items>

---

## 📋 Checklist
- [ ] <still-to-do item>
```

Drop any section that would be empty. Keep emojis to roughly one per section heading + one per bullet; no decorative spam (tasteful — we're not on LinkedIn). With a single `--lang` code, write the whole body in that language, headings included.

### 🗣️ Two or more languages (`--lang`, default `en,fr`)

With two or more codes, the body carries **one block per language, in the order given**, separated by `---`; the primary language leads. Top-level headings become `## <flag> <Language name>` and the content headings drop one level to `###`.

- **Mirror strictly**: same set of changes, same bullets in the same order, the same emoji prefix on each matching bullet, the same sections present or omitted. A reader of either language must come away with exactly the same information — never an abridged second block.
- **Write each side idiomatically** — never a word-for-word translation. Translate the section headings too, but keep their emoji identical across blocks so the structure stays scannable whatever the language. Avoid calques and anglicisms in the non-English blocks; leave code identifiers, CI job names, flags and file paths untranslated.
- **Drop an empty section in every language**, not just one.
- **The Checklist is not duplicated per language** — it holds tasks, not prose. It sits once below all language blocks, each item on a single line with the languages separated by ` / `, each prefixed by its flag.

**Flags.** ISO 639-1 codes name languages, not countries, so there is no canonical flag. Use the conventional one when unambiguous (`en` → 🇬🇧, `fr` → 🇫🇷, `es` → 🇪🇸, `de` → 🇩🇪, `it` → 🇮🇹, `nl` → 🇳🇱, `ja` → 🇯🇵) and fall back to the uppercase code as a text badge (`[PT]`, `[AR]`) for a language spread across many countries, or where picking a flag would be a political statement.

Worked example for the default `--lang=en,fr`:

```markdown
## 🇬🇧 English

### 🎯 Summary
<one short paragraph: what this PR delivers>

### 🤔 Motivation
<why — same inclusion rule as above; omit in BOTH languages or neither>

### 📦 What's included
- ✨ <feature / addition>
- 🔧 <change / refactor>
- 📝 <docs>
- ✅ <tests / validation: what was run, results>

### 🧭 Notes
- ⚠️ <caveat, breaking change, ordering dependency>
- 🔭 <known follow-ups / open items>

---

## 🇫🇷 Français

### 🎯 Résumé
<un court paragraphe : ce que livre cette MR>

### 🤔 Motivation
<le pourquoi — mêmes règles d'inclusion que côté anglais>

### 📦 Contenu
- ✨ <fonctionnalité / ajout>
- 🔧 <changement / refactor>
- 📝 <docs>
- ✅ <tests / validation : ce qui a été lancé, résultats>

### 🧭 À noter
- ⚠️ <réserve, rupture, dépendance d'ordre>
- 🔭 <suites connues / points ouverts>

---

## 📋 Checklist
- [ ] 🇬🇧 <english text> / 🇫🇷 <texte français>
```

**Checklist (to-do items).** Actionable steps the reviewer (or author) still has to *do* — tests to run, manual verifications, follow-up actions — go in a single `## 📋 Checklist` section at the very bottom, preceded by its own `---` separator. Use task boxes (`- [ ]`) so they render as a tickable checklist on both forges. This is distinct from the `✅ tests / validation` bullet under *What's included*, which records what was **already run**; the Checklist is the **still-to-do** list. Omit the whole section when there is nothing left to do.

Prefer a checklist item that is actually **verifiable in this PR's context**. When a claim can only be observed elsewhere (a CI job that only triggers on paths this PR doesn't touch, a stage this branch doesn't reach), say so explicitly rather than writing an item nobody can tick.

### 🐛 Bugfix PRs — the four required beats

For any PR that fixes a defect (`fix(...)`, a regression, a wrong behaviour), the `🤔 Motivation` section is **mandatory** and carries four labelled beats, in this order. A reviewer must be able to reproduce the reasoning without asking a single question.

1. **Observed** — the wrong behaviour, with the **verbatim** evidence: the error, the stack trace line, the failing exit code, the misleading success message. Quote it in a fenced block; do not paraphrase a log you have in hand. If the failure was *silent* or pointed elsewhere, say so — that misdirection is usually the expensive part of the bug.
2. **Expected** — what should happen instead, and ideally the neighbouring case that already behaves correctly ("the 62 provider-managed resources already did this; only these two didn't"). It shows the fix restores consistency rather than inventing a rule.
3. **Discovery context** — how the bug surfaced: which task was underway, what triggered it. Add why it had escaped until then when that is instructive (a path that only exists on a cold start, on a fresh volume, after a wipe…).
4. **Root cause** — the mechanism, one or two sentences, only when it is not obvious from the fix itself. Keep the implementation detail for `📦 What's included`.

Then, still for bugfixes:

- `📦 What's included` must carry a **regression-test bullet stating it was proven red before the fix and green after** — a regression test nobody watched fail is not evidence. Give the counts (`5 new tests, 22 green in the module`).
- Add a separate **real-conditions validation** bullet whenever the fix was exercised outside the test suite, with the before/after figures of the *same* command (`exited 1 with "3 errored"` → `exits 0 with "+ 62 to create"`). This is what convinces a reviewer the fix works where it matters, not only under mocks.
- `🧭 Notes` should state the **deliberate non-fix**: the adjacent case you chose to keep failing, and why (e.g. a refused connection is not evidence of deletion). Reviewers otherwise read the narrower fix as an oversight.
- Also note any **migration or ordering caveat** that makes the fix look inoperative — state serialized in a checkpoint, a cache to clear, a dependent branch to merge first. Without it, whoever tests the fix on pre-existing state will conclude it does not work.

With several `--lang` codes, every beat is mirrored in each language like the rest of the body — including the verbatim evidence block, which is quoted identically (never translated).

Derive the **title** from the change as a whole, following the convention of recent PRs (list them to see the house style — Conventional-Commits prefix, ticket key, etc.). One line, imperative, no trailing period.

## Step 3 — Labels (only existing; suggest, never auto-create)

List the labels per the table, then:

- Map the change to the **existing** labels that fit. **Read the convention off the list rather than assuming one**: the grouping prefix and its separator, the casing, whether emojis are part of the name, and the colour used per group. A new label must match its group exactly.
- **Grouping by a plain prefix (`Group | Name`, `area/backend`) carries no exclusivity.** Several values of the same group can legitimately coexist on one PR — never drop one to add another unless the axis is genuinely exclusive (priority typically is; scope and impact typically are not).
- **GitLab only — scoped labels** (`key::value`) *do* enforce one value per key, server-side: applying `Priority::P1` removes `Priority::P3` automatically. They are a **Premium/Ultimate** feature, so they work only on a licensed instance — check that the label list actually shows `::` names before assuming they are available. **GitHub has no equivalent**: there, exclusivity is convention only, enforced by nobody.
- If a relevant category has **no** existing label, propose new label name(s) that follow the observed convention (same prefix, casing, emoji style, and the group's colour), and present them for approval. **Only** create a label if the user explicitly says yes.
- Build the label argument from existing (or just-approved) labels only.

## Step 4a — Create (no existing PR)

Show the user the resolved **title / target / description / labels**, get a yes, then run the *Create* command from the table. Add `--draft` if the work isn't ready for review. On GitLab, add `--remove-source-branch` when the branch should die with the merge; on GitHub that is a repo setting, not a create flag — mention it rather than silently skipping it. Report the PR URL.

## Step 4b — Update (existing open PR)

Read the live PR (see the table) and compare against reality. Update **only what drifted**:

- 🔁 **Description**: if commits were added since the PR was opened, or sections are stale/missing, regenerate the whole-diff description (Step 2) and push it with the *Update body* command. If it's already accurate, say so and change nothing.
- 🏷️ **Labels**: add missing fitting labels, remove now-wrong ones — existing labels only; suggest new ones per Step 3.
- ✏️ **Title**: update only if the scope materially changed. On GitLab, if the MR is a draft, carry the `Draft: ` prefix into the new title and read `.draft` back afterwards — see the warning under the command table; dropping the prefix quietly opens the MR for review.

A rebase is a common reason to re-check: the target may have moved, and description claims about triggers, dependencies or "still in flight" work can go stale even when the diff itself is unchanged.

After pushing an update, **read the description back and diff it against what you sent** — emoji, quoting and long bodies are exactly where a silent truncation would hide.

Always state what you changed (or that nothing needed changing). Never recreate the PR.

## Reminders

- 🔒 No secrets/credentials in the description.
- 🧭 If the forge CLI is missing or auth fails, stop and tell the user — never fall back to the web UI, and never substitute the other forge's CLI.
- 🙅 One PR per branch. When in doubt about target branch or duplicate state, ask rather than create.
