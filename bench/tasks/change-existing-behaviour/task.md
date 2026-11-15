# Change what an existing function does

**Kind:** change-existing-behaviour

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. The function `trim-spaces` in `strings.el` removes the spaces at the start of the string but leaves the ones at the end. Change it so that it removes the spaces at both ends. Keep the name `trim-spaces` and its one argument, and keep the behaviour of the rest of the file. Do not change `strings-test.el`.
```

## Done means

- `emacs -Q --batch -L . -l strings-test.el -f ert-run-tests-batch-and-exit` exits 0.
- `(trim-spaces "  hi  ")` is `"hi"`, so the trailing spaces are gone.
- `strings-test.el` is unchanged.
