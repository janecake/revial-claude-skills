---
name: pr-magic
description: >-
  Take one of my PRs from "changes requested" to ready to merge. Use whenever
  the user says "pr-magic", "address the review", "fix the review comments",
  "the reviewer requested changes on #1234", "handle the feedback on my PR", or
  otherwise asks to work through review feedback on an open PR. Reads every
  unanswered review comment, applies the fixes, merges the base branch in,
  replies to each comment with the fix, gets CI green and re-requests review.
---

# PR magic

Take an open PR whose review says "changes requested" and leave it with every
comment answered, the base branch merged in, CI green and the reviewer asked to
look again. Follow the steps in order.

## Rules for the whole run

**Write in unslop style.** Everything you write follows
[`../multi-review/references/unslop.md`](../multi-review/references/unslop.md):
replies on the PR, commit messages, code comments in your fixes, your messages to
the user and the final report. Quoted code, log output and the reviewer's own
words stay as written.

**Follow the target repo's `CLAUDE.md`.** The fixes are ordinary code changes, so
every rule there applies: the 300-line cap, tests for new behaviour, Drizzle for
new queries, `errFields(err)` for error logs, Bash timeouts.

**Never rewrite published history.** No rebase, no amend of a pushed commit, no
force push. The reviewer reads the PR commit by commit, and the replies point at
commit SHAs that must stay valid.

**Ask before disagreeing.** Replies post without asking, but a reply that pushes
back on the reviewer does not. Step 3 covers this.

## 1. Find the PR and get the branch ready

- Take the PR number from the user's message. If there is none, use
  `gh pr view --json number` on the current branch.
- Read the state with
  `gh pr view <n> --json number,url,author,headRefName,baseRefName,reviewDecision,mergeStateStatus,state`.
  Stop if the PR is closed or merged. If `reviewDecision` is not
  `CHANGES_REQUESTED`, say so and ask whether to carry on anyway: there may still
  be comments worth answering.
- Make sure the working tree is clean before you switch branches. If it isn't,
  stop and ask. Uncommitted work follows a checkout and lands on the wrong branch.
- Check out `headRefName` and `git pull --ff-only`. If the pull can't
  fast-forward, stop and ask: someone pushed to the branch from somewhere else.

## 2. Collect the feedback

Read all three sources. Reviewers spread findings across them.

**Inline threads.** One GraphQL call returns them with their state:

```bash
gh api graphql -F n=<n> -f o=<owner> -f r=<repo> -f query='
query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  reviewThreads(first:100){nodes{id isResolved isOutdated path line
    comments(first:50){nodes{databaseId author{login} body createdAt}}}}}}}'
```

A thread needs an answer when it is unresolved and its last comment is not by the
PR author. Threads stay unresolved after the author replies, so "unresolved"
alone over-counts. Outdated threads still count: the code moved, but the
reviewer's point may still stand.

**Review bodies.** `gh pr view <n> --json reviews` returns them. Read the body of
the latest `CHANGES_REQUESTED` or `COMMENTED` review from each reviewer. Findings
written only in a body have no thread to reply to.

**Conversation comments.** `gh pr view <n> --json comments` returns them. Read
the ones posted after the author's last comment or push.

Skip the author's own comments and anything already answered. Keep each item's
reviewer, comment id (`databaseId`), path, line and text.

## 3. Triage

Read the code each comment points at, as it stands on the branch now, before you
decide anything. Put each item in one group:

- **Fix.** The reviewer is right, and the change belongs in this PR.
- **Already done.** A later commit fixed it. Note the SHA.
- **Question.** The reviewer asked something and needs an answer, not a change.
- **Disagree.** You think the reviewer is wrong, the change is out of scope, or
  it conflicts with `CLAUDE.md` or another reviewer.

Don't assume a comment is wrong because a fix is awkward. Reviewers on this repo
usually check their findings against the code before they post.

If anything landed in **Disagree**, stop and ask the user before you write any
code. Use `AskUserQuestion`, one question per item, showing the reviewer's point
and your reason. Offer: fix it anyway, reply with my reasoning, or leave it for
me. An item left for the user gets no reply and goes in the final report.

## 4. Apply the fixes

- Make each fix the smallest change that answers the comment. Don't refactor
  around it.
- Commit related fixes together and unrelated ones apart, so each reply can point
  at one SHA that shows only its fix. Commit messages follow the repo's
  `type: summary` form.
- Add or update a test whenever a fix changes behaviour. If the reviewer flagged
  missing coverage, the test is the fix.
- Before you push, run the tests for each package you touched, and the root
  `npm run typecheck`. The root typecheck also covers `scripts/`, which per-package
  `tsc` misses, and it is the one CI gates on.

## 5. Merge the base branch in

- `git fetch origin` then `git merge origin/<baseRefName>`. Use the PR's real
  base: for a stacked PR it is the parent branch, not `dev`.
- Resolve conflicts by reading both sides. If a resolution needs a judgement
  call about behaviour, stop and ask.
- A Drizzle migration number collision has a fixed answer: keep the base branch's
  migration at its index, delete yours and run `npm run db:generate` again. The
  regenerated SQL should match your old file, which proves nothing drifted.
- If the merge goes wrong, don't reach for `git merge --abort`, which can leave
  the tree half-applied. Check `git status` and ask.
- After the merge, run the tests and the root typecheck again. Code from the base
  branch can break your changes without a single conflict.
- Push with `git push`.

## 6. Reply to every comment

Post right away. Don't show drafts first. Every reply goes in the thread it
answers.

- Inline thread:
  `gh api repos/<owner>/<repo>/pulls/<n>/comments/<databaseId>/replies -f body='...'`,
  using the first comment's `databaseId`.
- A finding from a review body or the conversation goes in one conversation
  comment that quotes each point and answers it underneath:
  `gh pr comment <n> --body-file <file>`.

How to word each reply:

- **Fix:** `Fixed in <short-sha>.` and then one or two sentences on what changed.
  If the fix differs from what the reviewer suggested, say how and why. Name the
  test that now covers it.
- **Already done:** `Fixed in <short-sha>` with the earlier SHA, and what it did.
- **Question:** the answer, pointing at code where it helps.
- **Disagree, reply chosen:** the reasoning the user approved, stated plainly.
  Say what would change your mind if that is useful.

Don't resolve threads. The reviewer resolves them.

## 7. Get CI green

- Wait for the checks: `gh pr checks <n> --watch`, run in the background with a
  generous timeout. Don't poll in a loop.
- A PR with merge conflicts runs no checks at all, so "no failures" can mean
  nothing ran. Confirm the checks actually started.
- For each red check, read the log with `gh run view <run-id> --log-failed`.
- If the failure comes from this PR, fix it, commit, push and wait again. If the
  fix touches code a reviewer commented on, add a line to that thread.
- If the failure looks unrelated, check whether the same check is red on `dev` or
  on other open PRs (`gh run list --workflow <name> --branch dev --limit 5`). If
  it is, re-run it once with `gh run rerun <run-id> --failed`. If it fails again,
  report it as pre-existing, with the evidence, and don't try to fix it.
- A stacked PR whose base is not `dev` runs only a few jobs, so green there proves
  less. Say so in the report.

## 8. Re-request review

When CI is green, or red only on checks you showed are pre-existing, ask the
reviewers to look again:

```bash
gh api -X POST repos/<owner>/<repo>/pulls/<n>/requested_reviewers \
  -f 'reviewers[]=<login>'
```

Include every reviewer whose latest review is `CHANGES_REQUESTED`. Skip the PR
author, since GitHub rejects a request to review your own PR, and skip bots.

## 9. Report

Run `gh pr view <n> --json mergeable,mergeStateStatus,reviewDecision` one last
time, then write a short summary:

- the PR link
- each comment and what happened to it: fixed in which SHA, answered, or left for
  the user
- the base branch merge, and whether it needed conflict resolution
- CI status, naming any check that is red and why
- what still stands between the PR and merging. Usually that is the reviewer's
  approval, because `CHANGES_REQUESTED` stays until they review again.
