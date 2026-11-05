# Revial tripwires

Each entry here has shipped broken in this codebase. Each is cheap to spot in a
diff and expensive to find in production.

This file holds the Revial-specific review knowledge for `multi-review`. To fork
the skill for another codebase, start by replacing this file.

Read the target repo's `CLAUDE.md` as well. It is the authority on current rules,
and the rules change. This file records why each rule bit us and how to spot a
violation. It doesn't copy the rules.

---

## Never raise

The human has asked never to see these. Drop them at every step: reviewer,
verifier, merge, the preflight summary and the re-review. A verifier's
`CONFIRMED` doesn't save one, and neither does severity. Don't mention that you
dropped them, and don't raise them as a question, a note or a nit.

### Drizzle migration numbering

CI already catches it. Anything about where a migration sits in the sequence is
out of scope, in whatever words it comes:

- two PRs, or a PR and the base branch, using the same migration number or
  file prefix such as `0123_`
- a duplicate, skipped or out-of-order `idx`, `tag` or `when` in
  `meta/_journal.json`
- a snapshot `id` or `prevId` chain under `meta/` that doesn't line up
- "needs renumbering", "regenerate after rebase", "conflicts with the migration
  on dev"
- a merge conflict, or `mergeable: CONFLICTING`, when the conflicting files are
  only under `*/migrations/`

What the migration SQL does is still in scope. See section 10.

---

## 1. RLS lost in a Supabase-to-Drizzle port

The repo is moving reads and writes off the Supabase client onto Drizzle, one
file at a time. The Supabase client applies row-level security through the
user's JWT. A Drizzle port on the service-role connection bypasses RLS. The query
still returns rows, but it returns every team's rows.

**In a diff.** Look for any `.from('…').select()/insert()/update()/delete()/upsert()`
replaced by Drizzle. Ask which connection it uses, and whether the test proves the
same rows come back, including for a user who shouldn't see them.

A missed case is a `blocker`, because it exposes one team's data to another.

## 2. New SQS subscription without `partialResponses`

Without it, the Lambda reports a batch with one failed message as a full success.
SQS deletes the failed job after one attempt, so the DLQ never fills and nothing
alerts. `infra/worker-defaults.ts` says the flag is required.

**In a diff.** Look for a new `subscribeWorker({…})` block in `infra/functions.ts`
with no `partialResponses: true`.

Several existing subscriptions still lack it. A neighbouring subscription that
lacks it too doesn't excuse a new one.

## 3. Classification rules changed without a fixture row

Six modules own a classification decision outright, and each pins it with a
fixture conformance table. `CLAUDE.md` describes each one.

- `meeting-classification` decides whether an event becomes a session, a bot join
  or a briefing, and whether it is internal or external. It feeds
  `attendee_emails`, which is an RLS input. A row that flips to `internal`
  changes who can read the session.
- `question-classification` decides whether each question is open- or
  close-ended, and owns three reconciling counts on `meeting_metrics`.
- `competitor-classification` decides which named companies count as
  competitors, and whether each one is `playbook` or `inferred`.
- `seller-question-labels` decides business, pitch, rapport or filler, the
  build-on judgement, and six label counts on `meeting_metrics`.
- `coaching-eligibility` decides whether a scored meeting counts toward the
  seller's coaching, and which voices belong to the session owner.
- `at-risk` decides which open deals are at risk and how badly. Severity is a
  fold across every matching scenario.

The contract is that a change to the rules, or to any site that consumes them,
adds or updates a fixture row in the same commit. No call site may reimplement
any part of the decision.

**In a diff.** Look for a rules file touched with no fixture change, or a call
site that re-derives something the module already decides.

## 4. Silent fallbacks

`CLAUDE.md` forbids defaulting a missing value to hide that it is missing. A
`?? 0`, a `|| ''`, or an optional payload field with a default turns missing data
into a plausible wrong number downstream. A throw would have shown the gap at
once.

**In a diff.** Look for `??` and `||` defaults on config, env or SQS payload
fields, and Zod schemas with `.default()` or `.optional()` on a field the handler
needs.

A `??` local default also fails against `sst shell`, which injects the dev
`DATABASE_URL` into the environment. `dbAdmin()` follows it.

## 5. Verification that is a manual test plan

`CLAUDE.md` tells reviewers to push back on this, so it is in scope by policy. A
PR whose verification section lists "commands executed" or a screenshot is not
verified when an automated test was feasible.

Also check anything new under `scripts/`. That directory is only for verification
that can't run in CI, such as a live external tenant or output that only a human
can judge. Needing local infrastructure is not a reason, because the MCP e2e
workflow already runs real handlers against local Supabase. Tests under
`scripts/**/__tests__/` do run in CI through `scripts/vitest.config.ts`, but that
config exists to gate logic already in `scripts/`. A new test there belongs next
to the code it tests.

## 6. Vacuous or mis-wired tests

- A test that asserts only what a mock was told to return proves nothing. Mock
  infrastructure boundaries such as the Supabase client or an external API. Never
  mock business logic.
- `vi.mock()` of a path that doesn't exist does nothing and raises no error. A
  global stub in `setupFiles` can hide the dead mock.
- `beforeEach(() => spy.mockReset())` returns the spy. Vitest treats a function
  returned from `beforeEach` as a teardown and calls it after each test. Use
  braces.
- `describe.skipIf(!TEST_DATABASE_URL)` means a green core suite may never have
  run its integration tests.

## 7. Real names in fixtures

Screenshots, seeds, replay data and PR text can carry production CRM data. Invent
deal and company names for anything you commit or paste.

## 8. `\b` against Finnish text

JS `\b` is ASCII-only. It never fires after `ä` or `ö`, and it fails without an
error. The regex just stops matching. Treat any word-boundary regex over user text
or transcripts as suspect.

## 9. New table without a replay-registry class

A new table with no `team_id` fails `test:replay` until someone declares it
parent-scoped in `scripts/replay/table-registry.ts`.

## 10. Migrations

Drizzle owns the schema in `packages/db`, not the Supabase CLI. New files must not
go into `packages/app/supabase/migrations/`, which is bootstrap-only legacy.

Check for destructive or irreversible steps, lock risk on a large table, and a
backfill for existing rows. A new non-null column with no backfill breaks reads
for every row already in the table.

Dev Supabase has drifted from production. It has columns that production lacks,
and `gen:types` commits them into `database.types.ts`. A type in that file doesn't
prove the column exists in production.

Migration numbering, the journal and snapshot ordering are on the "Never raise"
list at the top of this file.

## 11. AI provider

Requesty is the only router, through `REQUESTY_API_KEY` and `REQUESTY_BASE_URL`.
The repo has no direct OpenAI or Anthropic integration and no Whisper anywhere in
the runtime. A new `openai` or `@anthropic-ai` import is a finding, and so is a
hardcoded model id that bypasses the router policy.

Structured-output schemas sent to Gemini must have no optional properties. Use a
required, nullable property instead. An optional string under `response_format`
caused three days of coaching-agent timeouts that logged no error.

## 12. Conventions you can check mechanically

- The 300-line cap applies to application code. `infra/*.ts` and `scripts/**` are
  exempt, so don't flag those for length.
- Every Lambda gets its own folder with a thin `handler.ts`. Business logic lives
  in `packages/core/`.
- Shared code goes in a domain folder with an `index.ts`. Never put loose files
  directly in `packages/core/src/shared/`.
- Errors serialise as `{ errMsg, errStack }`. Pino does not serialise an `Error`
  under a generic key, so `{ error }` logs `{}`.
- `job_type` is kebab-case and matches the ingress `QUEUE_MAP` key.
- Comments state what is true now. A comment that narrates the diff, such as
  "changed this to…" or "previously we…", is a finding. Git holds the history.
- Flag accidental files such as `foo 2.ts` duplicates, editor backups and a
  committed `.env`.
