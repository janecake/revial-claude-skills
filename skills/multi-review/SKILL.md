---
name: multi-review
description: >-
  Multi-agent PR review. Specialist reviewers read a PR diff in parallel, a
  second agent tries to disprove every finding against the real file, and the
  human approves what survives before the skill posts the review. Use when the
  user says "multi-review", "review this PR with agents", or "/multi-review <pr>".
---

# multi-review

Review a PR with parallel specialist agents. Two rules hold on every run:

1. Post nothing until the human has approved it.
2. Show the human no finding until a second agent has confirmed it against the
   real file. Reviewers are often confident and wrong. An unverified list wastes
   the author's time and teaches them to ignore your reviews.

Repo-specific checks live in [`references/tripwires.md`](references/tripwires.md),
and reviewers load it.

## Writing

Everything the skill writes follows [`references/unslop.md`](references/unslop.md).
That covers your messages to the human while you work, the findings table, the
review body, inline comments and the re-review report. Read the file before you
send the first message of the run. Reviewers and verifiers follow it too, because
their claims become comment text.

There are two exceptions. Quoted material stays as written, which includes lines
of code, log output and the PR author's words. Code identifiers stay as they are.

## 0. Preflight

```bash
gh pr view <pr> --json number,title,body,baseRefName,headRefName,additions,deletions,changedFiles,isDraft,mergeable
gh pr checks <pr>
```

**CI first.** If checks are red, say so before anything else. A review that ends
in `--approve` over a failing build is a bad review whatever the findings say.
Report the failing check names at the human gate, and don't block the review on
them.

**Get the right code on disk.** Subagents share your working directory. If the
tree isn't at the PR head, they read stale code and invent findings. Compare
`git rev-parse --abbrev-ref HEAD` to `headRefName`. If they differ, make a
worktree and give every agent its path:

```bash
git fetch origin "pull/<pr>/head:pr-<pr>"
git worktree add "<scratchpad>/pr-<pr>" "pr-<pr>"
```

Reviewers only read, so the worktree needs no `npm install`. Never symlink
`node_modules` into it, because then workspace packages resolve to the main
checkout. Remove the worktree with `git worktree remove` when you are done.

## 1. Scope

```bash
gh pr diff <pr> > "<scratchpad>/pr.diff"
gh pr diff <pr> --name-only > "<scratchpad>/files.txt"
```

**Large PRs.** Over about 2000 diff lines or 40 files, don't hand every reviewer
the whole diff. A reviewer with a full context stops reading and starts
pattern-matching. Split `files.txt` by directory into chunks that belong
together, and give each reviewer its chunk plus the full file list. Say in the
final report that you split the PR.

Keep generated files away from reviewers. These are lockfiles, Drizzle snapshots
under `*/migrations/meta/*`, `database.types.ts` and build output. List the files
you excluded instead of dropping them without a word.

## 2. Fan out reviewers

Spawn all reviewers in one message so they run concurrently, with
`subagent_type: general-purpose`.

Every agent gets the PR number, the path to `pr.diff`, the checkout path to read
from, the paths to `references/tripwires.md` and `references/unslop.md`, and
these rules verbatim:

- **Do not modify any file.** You only read. A read-only agent type still has
  Bash, so this has to be said.
- **Return findings only.** Leave out a PR summary, a description of what the
  code does, praise, and "overall this looks good". The human has to skim past
  every one of those words.
- **Read the full file around every hunk before you claim anything.** A diff hunk
  doesn't give enough context to call a bug. The guard you think is missing is
  often six lines above the hunk.
- **Quote the line your claim is about.**
- **Stay in the diff's scope.** A problem in code the PR doesn't change is not
  this PR's finding.
- **Skip anything `tripwires.md` marks "Not a finding".** The human has asked
  never to see those.
- **Write the claim, the reason and the fix in the style of `unslop.md`.** They
  become review comment text.
- If you find nothing, return exactly `NO FINDINGS`. Don't pad the list to look
  useful.

Finding format, one per line:

```
SEVERITY | file:line | one-line claim | why it breaks | suggested fix
```

Give agents this severity ladder, or they inflate `blocker`:

| Severity | Means |
|---|---|
| `blocker` | Breaks production, loses or corrupts data, or leaks data across teams or tenants |
| `major` | Wrong behaviour on a realistic input, with no workaround |
| `minor` | Correct today but fragile, or breaks a stated repo rule |
| `nit` | Naming, style, comment wording |

### The reviewers

| Agent | Looks for |
|---|---|
| `correctness` | Logic bugs, inverted or wrong conditions, off-by-one errors, broken control flow, unhandled promise rejections, `catch` blocks that swallow errors, early returns that skip cleanup |
| `edge-cases` | Null, empty and huge inputs, races and concurrent writes, retries and idempotency, partial failure, timezone and locale, non-ASCII text. JS `\b` never fires after `ä` or `ö`. |
| `security-and-tenancy` | Authz on every new API route, team and tenant isolation, RLS kept on any Supabase-to-Drizzle port, injection, SSRF, XSS, unsafe embeds, secrets leaking into logs or client bundles |
| `conventions` | Reads the target repo's `CLAUDE.md` fresh, plus `tripwires.md`. Also accidental files such as `foo 2.ts` and editor backups, stray scripts, committed secrets, leftover debug logging |
| `data-and-migrations` | Destructive or irreversible migrations, lock risk on a large table, drift between schema and model, whether existing rows get a backfill, new tables that need a replay-registry class |
| `tests-and-verification` | Whether the PR's claimed verification holds. Is there an automated test? Does it call production code or re-implement it? Does it assert only what a mock was told to return? Does any new `scripts/` file clear the bar in `CLAUDE.md`? Do rules changes carry their fixture rows? |
| `infra-and-queues` | New queues or subscriptions wired with `partialResponses` and a DLQ, alarms, cron schedule overlap, linked secrets, correct `Resource.*` usage, VPC and arch settings that match the rest |

Drop an agent whose domain the PR doesn't touch. A pure-frontend PR needs no
`infra-and-queues`. Say which agents you dropped and why.

## 3. Verify every finding

This step decides whether the review is worth reading.

For each finding of `minor` or above, spawn one verifier whose only job is to try
to disprove it. Spawn each batch in one message.

Each verifier gets the single finding and these rules:

- Read the full file at head, and the callers if the claim depends on them.
- Return exactly one of:
  - `CONFIRMED`, quoting the lines that prove it.
  - `REFUTED`, saying exactly what the reviewer missed.
  - `UNPROVABLE`, when the claim needs runtime or external knowledge that the
    code doesn't settle.
- **Do not introduce new findings.** Put anything else you notice on a separate
  `incidental:` line. The merge step discards it.

Then drop every `REFUTED`. Keep `UNPROVABLE` only at `blocker` or `major`, and
label it `[unverified]` so the human can weigh it. A `nit` skips verification and
never justifies request-changes.

Two agents reporting the same thing is weak corroboration. They read the same
diff with similar priors, so their agreement doesn't replace verification.

## 4. Merge

- Drop any finding that `tripwires.md` marks "Not a finding", even if a verifier
  confirmed it.
- Dedupe on `file:line` plus claim. Keep the better-written one and note that two
  reviewers agreed.
- Sort from `blocker` to `nit`.
- The cap applies to `minor` and `nit` only. Show every `blocker` and `major`,
  however many there are. Fold minors and nits to about 10 and state how many you
  folded.
- If every reviewer returned `NO FINDINGS`, say exactly that and go to the gate
  recommending approve. Don't invent a finding to justify the run.
- Check every claim, reason and fix against `unslop.md`, and rewrite the ones that
  break a rule. Leave quoted code as it is.

## 5. Human gate

This step is mandatory. Present in chat:

- CI status, stated first.
- A numbered table: `# | severity | file:line | claim | suggested fix`.
- How many minors and nits you folded, and which reviewers you dropped.

Then stop and ask:

- which findings to keep
- the verdict, which is comment, request-changes or approve

Use `AskUserQuestion` for the verdict. Don't call `gh pr review` or `gh api`
until you have the answer.

## 6. Post

Write the body to `<scratchpad>/review.md` in the style of `unslop.md`. Anchor
findings inline where you can. An author fixes a finding shown at its line and
skims one buried in a long body.

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

**Inline comments must target diff lines.** One comment on a line outside the
PR's diff fails the whole call, so put any such finding in `body`. If the inline
call fails anyway, fall back to:

```bash
gh pr review <pr> --comment --body-file "<scratchpad>/review.md"
```

Give the user the review URL.

## 7. Re-review the fixes

Once the author pushes fixes, check each one against the code. A fix that
answers a finding can still be wrong.

```bash
git log --oneline <sha-at-review-time>..HEAD
gh pr diff <pr>
```

One agent answers two questions per fix. Does it resolve the finding? Does it
introduce anything new? Report both answers. This step is cheap, and it catches a
bad fix that the original review asked for without meaning to.

## Cost

A run uses about 7 reviewers plus one verifier per finding, which comes to 10 to
20 agents on a typical PR. For a two-line diff, skip the fan-out, review it
yourself, and say that you did.
