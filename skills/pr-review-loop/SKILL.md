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

Take the current branch to a reviewed PR against `dev`. Five steps, in order.

## 1. Create the PR against dev

- Ensure you are NOT on `dev`; if you are, stop and tell the user (nothing to PR).
- If this session entered a worktree, confirm the branch name is the one you
  intend — `EnterWorktree` creates `worktree-<name>`, not the name you asked for.
  Rename before pushing.
- Check what you are about to commit is yours: in a worktree, `git diff` and
  `git add <dir>` can sweep in another session's edits. Stage explicit paths and
  compare against a list of what you meant to change.
- Push the branch: `git push -u origin HEAD`.
- Open it: `gh pr create --base dev --fill` (or write a title/body from the diff
  if `--fill` is thin). End the body with the Claude Code attribution line.
- **The body's verification section must point at an automated test**, not a list
  of commands you ran. If the change is testable in CI and isn't tested, write the
  test before opening the PR — the review will flag it anyway.
- Capture the PR number from the output.

## 2. Multi-agent review

- Run the `multi-review` skill with the PR number from step 1.
- Every finding it shows you has already survived an adversarial verifier, so
  treat the list as real unless it is labelled `[unverified]`. Do not re-argue it
  from scratch.
- It stops for approval on which findings to keep and the review verdict — that
  stop is the skill's. Let the user answer it; don't pre-empt it.
- Apply the kept findings. Skip the rest with a one-line reason each.
- Commit and push.

## 3. Let multi-review check its own fixes

- Run `multi-review` step 7 over the fixup commits only.
- A fix written against a finding is not a fix verified against the code. This
  catches the bad fix the original finding implicitly asked for.
- Apply anything it turns up; push.

## 4. Run your own code review

- Run the `/code-review` skill on the diff (default effort).
- Skip anything multi-review already covered — only act on what's new. If it
  returns mostly repeats, say so and stop rather than padding the loop.
- Apply the valid findings, skip the rest with a one-line reason each.
- Commit and push.

> For a large or high-risk PR, `/code-review ultra` is the deeper multi-agent
> pass and largely subsumes steps 2–4. It is user-triggered and billed — offer it,
> don't launch it.

## 5. Report

- **Check CI before declaring anything.** `gh pr checks <n>`. A PR with red checks
  is not green, whatever the reviews said. Report the failing check names.
- One short summary: PR link, what multi-review flagged and what you
  applied/skipped, the same for your own review, then CI status.

Keep judgement lazy — apply real bugs, skip noise, don't re-argue a call the
user already made.
