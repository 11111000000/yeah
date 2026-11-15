# Rename a function and update its callers

**Kind:** refactor-with-callers

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. The function `legacy-format` in `records.el` has a name that does not describe it any more. Rename it to `record-format` and update every caller - `main.el` calls it too. Keep the behaviour of the function exactly as it is. Do not change `refactor-test.el`.
```

## Done means

- `records.el` defines `record-format` and no longer defines `legacy-format`.
- `main.el` calls the new name, so `(render-records ...)` still works.
- `emacs -Q --batch -L . -l refactor-test.el -f ert-run-tests-batch-and-exit` exits 0.
- `refactor-test.el` is unchanged.
