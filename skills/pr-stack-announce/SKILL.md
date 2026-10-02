---
name: pr-stack-announce
description: >-
  Generate a Slack message announcing a stacked-PR chain for review. Use when
  the user says "announce this stack", "Slack message for these PRs", "post the
  stack to the channel", "ask the team to review this stack", or wants a
  ready-to-paste Slack post for a set of related PRs. Outputs the message text
  only — it never posts to Slack.
---

# PR stack announce

Produce a ready-to-paste Slack message for a stack of related PRs. Output is
text for the user to post themselves — never post to Slack, never use a Slack
MCP tool here.

## 1. Collect the stack

Find the PRs (Linear project, branch prefix, or the list the user gave):

```
gh pr list --state open --json number,headRefName,baseRefName,title,url,isDraft,mergeable --limit 60
```

Determine the real parent of each branch with `git merge-base --is-ancestor`
rather than trusting the PR base field — a rebased stack often has stale bases.
If a base is stale, say so and offer to fix it with `gh pr edit <n> --base <parent>`;
a stale base makes a PR's diff include its parent's changes, which wastes reviewers.

## 2. Get the facts that decide review order

Per PR, compute:

- **Reviewable lines** — total diff minus generated files. Exclude
  `*/migrations/meta/*` (Drizzle snapshots), `package-lock.json`, and any other
  lockfile/codegen. This matters: a PR can show 24,000 lines and contain 300
  reviewable ones.
- **CI status** — `gh pr checks <n>`. Never announce a stack as ready with red
  CI. If it's red, fix or flag it first; a stack that fails CI wastes every
  reviewer who opens it.
- **Test coverage gaps** — a PR adding routes/handlers with no test files is
  worth flagging to reviewers by name.

Compute reviewable lines with an explicit range (`git diff --numstat base..head`);
avoid clever one-liners that silently produce zeros.

## 3. Write the message

Structure, in this order:

1. **One sentence** on what the stack does. One — not a paragraph.
2. **Review order list** — bottom of the stack first, since that is the order
   they must merge. One line per PR: URL, short label, reviewable line count.

   **Link format: paste the bare URL. Nothing else.**

   ```
   • https://github.com/org/repo/pull/123 — connection model · ~320 lines
   ```

   Do NOT use the `<url|text>` angle-bracket form: when the message is pasted
   rather than sent through the API, the `|` gets URL-encoded to `%7C` and the
   link renders broken (`…/pull/123%7C#123`). Bare URLs always unfurl correctly.

   Never put `#123` next to the URL either — Slack renders a bare `#` as a
   channel reference, and it duplicates the number already in the URL. If you
   need the PR number in prose, write it plainly as `PR 123`.
3. **How to review** — the stack-specific guidance a reviewer can't guess:
   - review bottom-up, and why (each PR's diff is against its parent)
   - which PRs are mostly generated files and what to collapse
   - where to start if someone only has time for one
   - any deliberate oddity that will otherwise get flagged (disabled code,
     dev-only scripts, follow-up work already ticketed)

Keep it scannable. No preamble, no "hey team 👋", no restating the ticket.
Plain Slack markdown — `*bold*`, `•` bullets, bare URLs. Do not use `**bold**`
(that is Markdown, not Slack), do not use `<url|text>` links (see above), and do
not wrap the whole thing in a code fence.

Before handing the message over, re-read it and check that every URL is bare —
no `<`, no `|`, no `#` adjacent to it. This is the detail that most often ships
broken.

## 4. Hand it over

Print the message in one code block so it can be copied whole. Below it, note
anything the user should decide before posting (red CI, stale bases, PRs that
still need a description).

Keep it lazy: the message should be the shortest thing that gets the stack
reviewed in the right order.
