---
name: blather-commit
description: Review Blather's pending Git changes, derive a conventional commit message, create the commit, then ask whether to push it. Use when the user asks to commit work in this repository.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Execute
  - AskUser
enabled: true
user-invocable: true
disable-model-invocation: true
version: 1.0.0
---

# Blather Commit

Create an atomic commit for the current Blather worktree, then explicitly ask the user whether to publish it.

## Rules

- Use Conventional Commits: `<type>(<scope>): <short imperative summary>`.
- Do **not** require or add a Jira ticket prefix.
- Never amend an existing commit unless the user explicitly asks.
- Treat unstaged, staged, and untracked files as user work. Do not discard, restore, clean, or overwrite them.
- Include `Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>` in every commit message.
- Do not push until after the commit succeeds and the user explicitly confirms when asked.

## Workflow

1. Inspect `git status --short --branch`, the staged and unstaged diffs, the untracked-file list, and recent commits.
2. Determine whether the pending changes form one cohesive, independently working change:
   - If they do, derive the most accurate Conventional Commit type, optional scope, and imperative summary from the diff.
   - If they do not, explain the groups and ask the user which group to commit. Do not combine unrelated changes.
3. Run the narrowest relevant validation described by the repository scripts or changed areas. If validation fails, report the failure and ask whether to fix it or proceed. Never claim validation passed when it did not.
4. Stage only the files belonging to the selected cohesive change. Review `git diff --staged` and `git diff --staged --check`.
5. Create the commit with the derived Conventional Commit subject and required co-author trailer. Use a safely quoted multiline message.
6. Confirm the commit with `git show --stat --oneline -1` and report its subject and hash.
7. Ask a single, explicit question: whether to push this commit to its configured remote.
   - Push only if the user answers yes.
   - Before pushing, confirm the target branch and remote with `git status --short --branch` and `git remote -v`.
   - Report the push result and any remaining local, uncommitted changes.

## Success Criteria

- The new commit is atomic, uses Conventional Commits, and has no Jira prefix.
- The commit contains only the selected changes and includes the co-author trailer.
- Validation results and the final Git state are reported accurately.
- No remote is changed unless the user approves the push after the commit.
