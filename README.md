# Revial Claude Code skills

Three Claude Code skills for the PR workflow on [`revial-sst`](https://github.com/Revial-ai/revial-sst).
One opens a PR, one reviews it with specialist agents running in parallel, and
one writes a Slack post that announces a stack of PRs.

The skills are plain Markdown. Claude reads a skill when its description matches
your request, so there is nothing to build or run.

## Install

```bash
git clone https://github.com/janecake/revial-claude-skills.git ~/src/revial-claude-skills
cd ~/src/revial-claude-skills
./install.sh
```

`install.sh` symlinks each skill into `~/.claude/skills/`, so a `git pull` here
updates what Claude uses. If something already exists at that path, the script
moves it to `~/.claude/skills/.backup-<timestamp>/` first and overwrites nothing.

Pass `--copy` to install independent copies that you can edit without touching
the repo.

To check the install, type `/multi-review` in Claude Code. It should appear in the
list.

## The skills

### `multi-review`

```
/multi-review 2847
```

Seven specialist reviewers read the diff in parallel. They cover correctness,
edge cases, security and tenancy, conventions, data and migrations, tests and
verification, and infra and queues. For every finding, a second agent reads the
real file and tries to disprove it. The skill drops each finding that agent
refutes.

Then the skill stops, shows you the findings that survived, and asks which to
keep and which verdict to post. It posts nothing until you answer.

It differs from a single reviewer reading a diff in two ways.

- **Verification.** An agent that is wrong is usually confident, so its own
  confidence tells you nothing. Each surviving finding gets a fresh agent whose
  only job is to disprove it. That step decides whether the author trusts your
  next review.
- **Repo knowledge.** The reviewers load
  [`skills/multi-review/references/tripwires.md`](skills/multi-review/references/tripwires.md),
  a list of twelve things that have shipped broken in this codebase. Each entry
  names the diff pattern that gives it away. Examples include RLS lost in a
  Supabase-to-Drizzle port, an SQS subscription missing `partialResponses` so
  failed jobs vanish instead of reaching a DLQ, and a classification rule changed
  without its fixture row.

The skill's chat messages, findings table, review body and inline comments follow
[`skills/multi-review/references/unslop.md`](skills/multi-review/references/unslop.md).
Those rules ban em dashes and bold emphasis, and they ask for active voice and
plain words.

Expect 10 to 20 agents on a normal PR. For a two-line diff, Claude skips the
fan-out and reads the diff itself.

### `pr-review-loop`

```
create a PR
```

Pushes the branch, opens a PR against `dev`, runs `multi-review` and re-reviews
the fixes. It then runs the built-in `/code-review` over whatever is left, and
checks CI before it reports anything as green. It writes the PR body, commit
messages and its report in the same unslop style as `multi-review`, and it drops
any finding that `tripwires.md` marks "Not a finding".

### `pr-stack-announce`

```
announce this stack
```

Works out the real parent of each branch, since PR base fields go stale after a
rebase. It counts reviewable lines and leaves out generated files, because a PR
can show 24,000 lines and contain 300 that need review. Then it writes a message
in Slack's markdown that gives the review order. It prints the text, and you post
it.

## Adapting this to another codebase

Start by replacing `skills/multi-review/references/tripwires.md`, which holds most
of the Revial-specific content. The reviewer table in `skills/multi-review/SKILL.md`
also names a few Revial checks, such as RLS on Drizzle ports and replay-registry
classes, so edit those rows too. The `conventions` reviewer reads the target
repo's `CLAUDE.md` fresh on each run, so it never goes stale.

`pr-review-loop` assumes a `dev` base branch, and `pr-stack-announce` excludes
Drizzle snapshot paths. Each is a one-line change.

## Keeping the tripwires current

The file is worth its length only if it grows when a bug gets through. When a bug
that the review missed reaches production, add an entry with what broke, the diff
pattern that would have caught it, and the severity. If nobody could act on an
entry from a diff alone, it doesn't belong there.

Noise goes in the same file. When reviews keep raising something you never want
to see, add a "Not a finding" paragraph to the relevant section. Reviewers skip
those, and the merge step drops any that get through.

## Writing rules

`skills/multi-review/references/unslop.md` is a copy of the rules in the `unslop`
skill, which lives outside this repo. `multi-review` and `pr-review-loop` both
follow it. If you change a rule in one place, copy the change to the other.

## Conventions these skills enforce

The authority is [`CLAUDE.md`](https://github.com/Revial-ai/revial-sst/blob/dev/CLAUDE.md)
in `revial-sst`, not this repo. `tripwires.md` explains why each rule exists and
how to spot a violation. It doesn't restate the rules.
