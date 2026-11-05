---
name: pr-review-loop
description: >-
  Open a PR against dev and drive it through review to green. Use whenever the
  user says "create a PR", "open a PR", "ship this", "PR this", or otherwise
  asks to raise a pull request for the current branch. Creates the PR against
  dev, runs /multi-review over it, then runs the local /code-review agent and
  applies the valid findings from both.
---

# PR review loop

Take the current branch to a reviewed PR against `dev`. Follow the five steps in
order.

## Rules for the whole loop

**Write in unslop style.** Everything you write follows
[`../multi-review/references/unslop.md`](../multi-review/references/unslop.md).
That covers the PR title and body, commit messages, code comments in your fixes,
the reasons you give for skipping a finding, your messages to the user while you
work, and the final report. Quoted material such as code, log output and the
reviewers' own words stays as written, and so do code identifiers.

**Drop everything on the "Never raise" list.** The list sits at the top of
[`../multi-review/references/tripwires.md`](../multi-review/references/tripwires.md).
Read it before you read either review. `/code-review` never sees that file, so
its findings need this filter most. Drizzle migration numbering is one example:
a shared number, journal or snapshot order, or a conflict confined to
`*/migrations/`. Drop any finding on a listed topic whatever its severity. Don't
apply a fix for one, don't list it as skipped, and don't mention it in the
report.

## 1. Create the PR against dev

- Check that you are not on `dev`. If you are, stop and tell the user there is
  nothing to PR.
- If this session entered a worktree, confirm the branch has the name you meant.
  `EnterWorktree` creates `worktree-<name>`, not the name you asked for. Rename
  the branch before you push.
- Check that what you are about to commit is yours. In a worktree, `git diff` and
  `git add <dir>` can sweep in another session's edits. Stage explicit paths and
  compare them against a list of what you meant to change.
- Push the branch with `git push -u origin HEAD`.
- Open the PR with `gh pr create --base dev --fill`. If `--fill` gives a thin
  title or body, write them from the diff instead. End the body with the Claude
  Code attribution line.
- The body's verification section must point at an automated test, not at a list
  of commands you ran. If the change is testable in CI and has no test, write the
  test before you open the PR. The review would flag it anyway.
- Note the PR number from the output.

## 2. Multi-agent review

- Run the `multi-review` skill with the PR number from step 1.
- Every finding it shows you has already survived an adversarial verifier, so
  treat the list as real unless a finding has the `[unverified]` label. Don't
  argue a finding again from scratch.
- `multi-review` stops to ask which findings to keep and which verdict to post.
  Let the user answer that question, and don't answer it for them.
- Apply the kept findings. Skip the rest with a one-line reason each.
- Commit and push.

## 3. Let multi-review check its own fixes

- Run `multi-review` step 7 over the fixup commits only.
- A fix that answers a finding can still be wrong. This step catches a bad fix
  that the original finding asked for without meaning to.
- Apply anything it turns up, then push.

## 4. Run your own code review

- Run the `/code-review` skill on the diff at the default effort.
- Skip anything multi-review already covered and act only on new findings. If it
  returns mostly repeats, say so and stop.
- Apply the valid findings. Skip the rest with a one-line reason each.
- Commit and push.

> For a large or high-risk PR, `/code-review ultra` is the deeper multi-agent
> pass and covers most of steps 2 to 4. The user triggers it and pays for it, so
> offer it and don't launch it.

## 5. Report

- **Check CI before you declare anything.** Run `gh pr checks <n>`. A PR with red
  checks is not green, whatever the reviews said. Report the failing check names.
- Write one short summary. Give the PR link, what multi-review flagged and what
  you applied or skipped, the same for your own review, and then the CI status.

Apply real bugs, skip noise, and don't argue again over a call the user already
made.
