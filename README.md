# Revial Claude Code skills

Three Claude Code skills for the PR workflow on [`revial-sst`](https://github.com/Revial-ai/revial-sst):
open a PR, review it with a fan-out of specialist agents, and announce a stack of
PRs in Slack.

They are plain Markdown. Claude reads a skill when its description matches what
you asked for — there is nothing to build or run.

## Install

```bash
git clone <this repo> ~/src/revial-claude-skills
cd ~/src/revial-claude-skills
./install.sh
```

`install.sh` symlinks each skill into `~/.claude/skills/`, so a `git pull` here
updates what Claude uses. Anything already at that path is moved aside to
`~/.claude/skills/.backup-<timestamp>/` first — nothing is overwritten.

Pass `--copy` instead if you'd rather have independent copies you can edit
without touching the repo.

Verify with `/multi-review` in Claude Code — it should be listed.

## The skills

### `multi-review` — review a PR with parallel agents

```
/multi-review 2847
```

Fans out seven specialist reviewers over the diff (correctness, edge cases,
security and tenancy, conventions, data and migrations, tests and verification,
infra and queues), then **adversarially verifies every finding** against the real
file with a second agent before you see it. Refuted findings are dropped.

Then it stops, shows you what survived, and asks what to keep and what verdict to
post. **It never posts anything without that answer.**

Two things make this different from a single reviewer reading a diff:

- **Verification.** An agent that is wrong is usually confident, so self-reported
  confidence is worthless. Each surviving finding gets a fresh agent whose only
  job is to disprove it. This is the step that decides whether the author trusts
  the next review you send them.
- **Repo knowledge.** The reviewers load
  [`skills/multi-review/references/tripwires.md`](skills/multi-review/references/tripwires.md)
  — twelve things that have actually shipped broken in this codebase, with the
  diff pattern that gives each one away. RLS silently lost in a Supabase→Drizzle
  port, an SQS subscription missing `partialResponses` so failures vanish instead
  of reaching a DLQ, a classification rule changed without its fixture row.

Expect 10–20 agents on a normal PR. For a two-line diff, Claude should skip the
fan-out and just read it.

### `pr-review-loop` — branch to reviewed PR

```
create a PR
```

Pushes the branch, opens it against `dev`, runs `multi-review`, re-reviews the
fixes, then runs the built-in `/code-review` over whatever is left, and checks CI
before claiming anything is green.

### `pr-stack-announce` — Slack post for a stacked chain

```
announce this stack
```

Works out the real parent of each branch (PR base fields go stale after a
rebase), counts *reviewable* lines excluding generated files — a PR can show
24,000 lines and contain 300 real ones — and writes a review-order message in
Slack's markdown. It prints the text; you post it.

## Adapting this to another codebase

Replace `skills/multi-review/references/tripwires.md`. That file is the only
Revial-specific content; `SKILL.md` carries none, and the `conventions` reviewer
reads the target repo's `CLAUDE.md` fresh each run so it can't go stale.

`pr-review-loop` assumes a `dev` base branch and `pr-stack-announce` excludes
Drizzle snapshot paths — both one-line changes.

## Keeping the tripwires alive

The file is only worth its length if it grows when something bites. When a bug
reaches production and the review missed it, add the entry: what broke, the diff
pattern that would have caught it, and the severity. An entry nobody could act on
from a diff doesn't belong there.

## Conventions these skills enforce

The authority is [`CLAUDE.md`](https://github.com/Revial-ai/revial-sst/blob/dev/CLAUDE.md)
in `revial-sst`, not this repo. `tripwires.md` explains *why* a rule exists and
how to spot a violation — it deliberately does not restate the rules.
