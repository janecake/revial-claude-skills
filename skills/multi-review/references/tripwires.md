# Revial tripwires

Things that have actually shipped broken in this codebase. Each one is cheap to
spot in a diff and expensive to find in production.

This file is the **only** Revial-specific part of `multi-review`. Forking the
skill for another codebase means replacing this file and nothing else.

Read the target repo's `CLAUDE.md` as well — it is the authority on current
rules, and it changes. This file is the *why it bit us*, not a copy of the rules.

---

## 1. RLS lost in a Supabase → Drizzle port

The repo is incrementally moving reads/writes off the Supabase client onto
Drizzle. The Supabase client applies row-level security via the user's JWT. A
Drizzle port on the service-role connection **bypasses RLS entirely** — the query
still returns rows, just everyone's rows.

**In a diff:** any `.from('…').select()/insert()/update()/delete()/upsert()`
replaced by Drizzle. Ask which connection it uses, and whether the test proves
the same rows come back *including* for a user who shouldn't see them.

Severity when missed: `blocker` — this is cross-team data exposure.

## 2. New SQS subscription without `partialResponses`

Without it, a batch where one message fails is reported as wholly successful: the
failed job is dropped after a single attempt and **the DLQ never fills**, so
nothing alerts. `infra/worker-defaults.ts` says it plainly — required, not a
tuning knob.

**In a diff:** a new `subscribeWorker({…})` block in `infra/functions.ts` with no
`partialResponses: true`.

Still missing on `calendarSyncQueue`, `calendarInboxQueue` and
`crmDisconnectQueue` as of 2026-10-02 — so "the file next to it doesn't have it
either" is not a defence.

## 3. Classification rules changed without a fixture row

Four modules own a classification decision outright, and each pins it with a
fixture conformance table:

- `meeting-classification` — whether an event becomes a session / bot join /
  briefing, and internal vs external. Feeds `attendee_emails`, which is an **RLS
  input**: a row flipping to `internal` changes who can read the session.
- `question-classification` — open vs close-ended, plus three reconciling counts
  on `meeting_metrics`.
- `competitor-classification` — which named companies count as competitors, and
  `playbook` vs `inferred`.
- `seller-question-labels` — business/pitch/rapport/filler, build-on judgement,
  and six label counts on `meeting_metrics`.

The contract: **a change to the rules, or to any site consuming them, adds or
updates a fixture row in the same commit.** And no call site may reimplement any
part of the decision.

**In a diff:** a rules file touched with no fixture change, or a call site
re-deriving something the module already decides.

## 4. Silent fallbacks

`CLAUDE.md` forbids defaulting a missing value to hide its absence. A `?? 0`,
`|| ''`, or an optional field with a default in a message payload turns missing
data into a plausible-looking wrong number downstream instead of a loud throw.

**In a diff:** `??` / `||` defaults on config, env, or SQS payload fields; Zod
schemas with `.default()` or `.optional()` on something the handler needs.

Related: a `??` local default will not protect you from `sst shell`, which
injects the **dev** `DATABASE_URL` into the environment — `dbAdmin()` follows it.

## 5. Verification that is a manual test plan

`CLAUDE.md` instructs reviewers to push back here, so this is in scope by policy,
not taste. A PR whose verification section lists "commands executed" or a
screenshot, where an automated test was feasible, is not verified.

Also scrutinise anything new under `scripts/`: that directory is only for
verification genuinely impossible in CI — a live external tenant, or output only
a human can judge. "Needed local infrastructure" is not a reason; the MCP e2e
workflow already runs real handlers against local Supabase. And a `__tests__/`
folder under `scripts/` is matched by **no vitest config** — those tests run
nowhere.

## 6. Vacuous or mis-wired tests

- A test that asserts only what a mock was told to return proves nothing. Mock
  infrastructure boundaries (Supabase client, external API), never business logic.
- `vi.mock()` of a path that doesn't exist is a **silent no-op** — and a dead
  mock can hide behind a global stub in `setupFiles`.
- `beforeEach(() => spy.mockReset())` returns the call's result, which vitest
  treats as a teardown function and re-invokes after each test. Use braces.
- `describe.skipIf(!TEST_DATABASE_URL)` means a green core suite may never have
  run its integration tests at all.

## 7. Real names in fixtures

Screenshots, seeds, replay data and PR text carry production CRM data. Invent
deal and company names for anything committed or pasted.

## 8. `\b` against Finnish text

JS `\b` is ASCII-only: it never fires after `ä` or `ö`, and it fails **silently**
— the regex just stops matching. Any word-boundary regex over user text or
transcripts is suspect.

## 9. New table without a replay-registry class

A new table with no `team_id` fails `test:replay` until it's declared
parent-scoped in `scripts/replay/table-registry.ts`.

## 10. Migrations

Drizzle owns schema (`packages/db`), not the Supabase CLI. New files must not go
into `packages/app/supabase/migrations/` — that is bootstrap-only legacy.

Check: destructive or irreversible steps, lock risk on a large table, and whether
**existing rows are backfilled** (a new non-null column with no backfill breaks
reads for every row already there).

Dev Supabase has drifted from production — it has columns production lacks, and
`gen:types` commits them into `database.types.ts`. A type existing is not proof
the column exists in production.

## 11. AI provider

Requesty is the only router (`REQUESTY_API_KEY`, `REQUESTY_BASE_URL`). There is
no direct OpenAI or Anthropic integration and no Whisper anywhere in the runtime.
A new `openai` / `@anthropic-ai` import, or a hardcoded model id bypassing the
router policy, is a finding.

Structured-output schemas sent to Gemini must have **no optional properties**
(use required + nullable). An optional string under `response_format` caused a
month of silent coaching-agent timeouts.

## 12. Conventions that are mechanically checkable

- 300-line cap on application code. `infra/*.ts` and `scripts/**/*.ts` are exempt
  — do not flag those for length.
- Every Lambda gets its own folder with a thin `handler.ts`; business logic lives
  in `packages/core/`.
- Shared code is grouped by domain into a folder with an `index.ts`. Never loose
  files directly in `packages/core/src/shared/`.
- Errors serialise as `{ errMsg, errStack }` — pino does not serialise an `Error`
  under a generic key, so `{ error }` logs `{}`.
- `job_type` is kebab-case, matching the ingress `QUEUE_MAP` key.
- Comments state what is true now. A comment narrating the diff ("changed this
  to…", "previously we…") is a finding; git holds the history.
- Accidental files: `foo 2.ts` duplicates, editor backups, committed `.env`.
