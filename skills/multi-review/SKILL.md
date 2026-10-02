---
name: multi-review
description: >-
  Multi-agent PR review. Fans out specialist reviewers over a PR diff, has every
  finding adversarially verified against the real file, merges what survives,
  shows it to the human for approval, then posts the review. Use when the user
  says "multi-review", "review this PR with agents", or "/multi-review <pr>".
---

# multi-review

Review a PR with parallel specialist agents. Two hard rules:

1. **Nothing is posted without explicit human approval.**
2. **No finding reaches the human until a second agent has confirmed it against
   the real file.** Reviewers are confidently wrong often enough that an
   unverified list wastes the author's time and trains them to ignore you.

Repo-specific checks live in [`references/tripwires.md`](references/tripwires.md).
Reviewers load it; this file stays generic.

## 0. Preflight

```bash
gh pr view <pr> --json number,title,body,baseRefName,headRefName,additions,deletions,changedFiles,isDraft,mergeable
gh pr checks <pr>
```

**CI first.** If checks are red, say so before anything else. A review that ends
in `--approve` over a failing build is a bad review regardless of the findings.
Report the failing check names at the human gate; don't block the review on them.

**Get the right code on disk.** Subagents share your working directory, so if the
tree isn't at the PR head they will read stale code and invent findings. Compare
`git rev-parse --abbrev-ref HEAD` to `headRefName`. If they differ, make a
worktree and give every agent *that* path explicitly:

```bash
git fetch origin "pull/<pr>/head:pr-<pr>"
git worktree add "<scratchpad>/pr-<pr>" "pr-<pr>"
```

Reviewers only read, so the worktree needs no `npm install` — and never symlink
`node_modules` into it, that makes `@revial-sst/*` resolve to the main checkout.
Remove the worktree when done (`git worktree remove`).

## 1. Scope

```bash
gh pr diff <pr> > "<scratchpad>/pr.diff"
gh pr diff <pr> --name-only > "<scratchpad>/files.txt"
```

**Large PRs.** Over ~2000 diff lines or ~40 files, do not hand every reviewer the
whole diff — a reviewer whose context is full stops reading and starts
pattern-matching. Split `files.txt` by directory into coherent chunks and give
each reviewer its chunk plus the full file list for orientation. Say in the final
report that the PR was chunked.

Exclude generated files from reviewer attention: lockfiles, `*/migrations/meta/*`
(Drizzle snapshots), `database.types.ts`, build output. Name them as excluded
rather than silently dropping them.

## 2. Fan out reviewers

Spawn all reviewers in ONE message so they run concurrently
(`subagent_type: general-purpose`).

Every agent gets: the PR number, the path to `pr.diff`, the path to the checkout
to read from, the path to `references/tripwires.md`, and these rules verbatim:

- **Do not modify any file.** You are reading only. (A read-only agent type still
  has Bash — this has to be said.)
- **Return findings only.** No PR summary, no description of what the code does,
  no praise, no "overall this looks good". Those are tokens the human then has to
  skim past.
- **Read the full file around every hunk before claiming anything.** A diff hunk
  is not enough context to call a bug — the guard you think is missing is often
  six lines above the hunk.
- **Quote the exact line** your claim is about.
- **Stay in the diff's scope.** Pre-existing problems the PR merely sits next to
  are not this PR's findings.
- If you find nothing, return exactly `NO FINDINGS`. Do not pad to look useful.

Finding format, one per line:

```
SEVERITY | file:line | one-line claim | why it breaks | suggested fix
```

Severity ladder — give agents this definition, or `blocker` inflates:

| Severity | Means |
|---|---|
| `blocker` | Breaks production, loses or corrupts data, or leaks data across teams/tenants |
| `major` | Wrong behaviour on a realistic input, with no workaround |
| `minor` | Correct today but fragile, or violates a stated repo rule |
| `nit` | Naming, style, comment wording |

### The reviewers

| Agent | Looks for |
|---|---|
| `correctness` | Logic bugs, inverted or wrong conditions, off-by-one, broken control flow, unhandled promise rejections, `catch` blocks that swallow, early returns that skip cleanup |
| `edge-cases` | Null/empty/huge inputs, races and concurrent writes, retry and idempotency, partial failure, timezone and locale, non-ASCII text (JS `\b` never fires after `ä`/`ö`) |
| `security-and-tenancy` | Authz on every new API route, team/tenant isolation, **RLS preserved on any Supabase→Drizzle port**, injection, SSRF, XSS, unsafe embeds, secret leakage into logs or client bundles |
| `conventions` | Read the target repo's `CLAUDE.md` fresh, plus `tripwires.md`. Also accidental files (`foo 2.ts`, editor backups), stray scripts, committed secrets, debug logging left in |
| `data-and-migrations` | Migration safety (destructive, irreversible, lock risk on a large table), schema-vs-model drift, whether existing rows are backfilled, new tables that need a replay-registry class |
| `tests-and-verification` | Whether the PR's claimed verification actually holds: is there an automated test, does it call production code or re-implement it, is it vacuous (asserting only what a mock was told to return), does any new `scripts/` file clear the bar in `CLAUDE.md`, do rules changes carry their fixture rows |
| `infra-and-queues` | New queue or subscription wired with `partialResponses` and a DLQ, alarms, cron schedule overlap, secrets linked, correct `Resource.*` usage, VPC/arch settings consistent with the rest |

Drop an agent whose domain the PR doesn't touch — a pure-frontend PR needs no
`infra-and-queues`. Say which you dropped and why.

## 3. Verify every finding

This is the step that decides whether the review is worth reading.

For each finding of `minor` or above, spawn one verifier whose **only** job is to
try to disprove it. Fan out in one message per batch.

Each verifier gets the single finding and these rules:

- Read the full file at head, and the callers if the claim depends on them.
- Return exactly one of:
  - `CONFIRMED` — quote the lines that prove it.
  - `REFUTED` — say precisely what the reviewer missed.
  - `UNPROVABLE` — the claim needs runtime or external knowledge the code doesn't settle.
- **Do not introduce new findings.** Anything else you notice goes on a separate
  `incidental:` line and will be discarded.

Then: drop every `REFUTED`. Keep `UNPROVABLE` only at `blocker`/`major`, labelled
`[unverified]` so the human can weigh it. `nit`s skip verification — and a `nit`
never justifies request-changes.

Two agents independently reporting the same thing is *weak* corroboration, not
strong: they read the same diff with similar priors. It does not substitute for
verification.

## 4. Merge

- Dedupe on `file:line` + claim; keep the better-written one, note the agreement.
- Sort `blocker` → `nit`.
- **The cap applies to `minor` and `nit` only.** Show every `blocker` and `major`,
  however many there are. Fold minors/nits to ~10 and state how many were folded.
- If every reviewer returned `NO FINDINGS`, say exactly that and go to the gate
  recommending approve. Do not manufacture a finding to justify the run.

## 5. Human gate (mandatory)

Present in chat:

- CI status, stated first.
- A numbered table: `# | severity | file:line | claim | suggested fix`.
- How many minors/nits were folded, and which reviewers were dropped.

Then **STOP** and ask:

- which findings to keep
- the verdict — comment / request-changes / approve

Use `AskUserQuestion` for the verdict. **Do not call `gh pr review` or `gh api`
before that answer exists.**

## 6. Post

Write the body to `<scratchpad>/review.md`. Prefer inline anchoring — a finding
shown at its line gets fixed, a finding in a wall of text gets skimmed.

```bash
# <scratchpad>/review.json
# {
#   "event": "COMMENT",            # or REQUEST_CHANGES / APPROVE
#   "body": "<summary + anything not anchorable>",
#   "comments": [
#     { "path": "packages/core/src/x.ts", "line": 42, "side": "RIGHT", "body": "..." }
#   ]
# }
gh api "repos/<owner>/<repo>/pulls/<pr>/reviews" --method POST \
  --input "<scratchpad>/review.json"
```

**Caveat:** an inline comment must target a line present in the PR's diff. The
whole call fails if one doesn't, so put any finding outside the diff in `body`
instead. If the inline call fails, fall back to:

```bash
gh pr review <pr> --comment --body-file "<scratchpad>/review.md"
```

Confirm the review URL back to the user.

## 7. Re-review the fixes

Once fixes are pushed, check them — a fix written against a finding is not a fix
verified against the code.

```bash
git log --oneline <sha-at-review-time>..HEAD
gh pr diff <pr>
```

One agent, two questions per fix: does it actually resolve the finding, and does
it introduce anything new? Report both. This is cheap and catches the bad fix
that the original review implicitly asked for.

## Cost

Roughly 7 reviewers plus one verifier per finding. On a typical PR that's
10–20 agents. For a two-line diff, skip the fan-out and review it yourself —
say that's what you did.
