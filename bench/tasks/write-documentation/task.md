# Document two functions

**Kind:** write-documentation

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. Write the file `money.md` in it. It documents the two functions of `money.el`: for each of `money-add` and `money-zero-p` there must be a section whose heading is exactly `## money-add` or `## money-zero-p`, and under that heading a line that starts with `Signature:` and names the function with its arguments, and a line that starts with `Summary:` with one sentence about what the function does.
```

## Done means

- `money.md` exists in the workspace.
- It has the headings `## money-add` and `## money-zero-p`.
- Each function has a `Signature:` line that names it and a `Summary:` line.
