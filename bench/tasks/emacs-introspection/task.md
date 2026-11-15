# Find the Emacs function that does the job

**Kind:** use-Emacs-introspection

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. The function `text-trim` in `text.el` removes only the whitespace at the start of the string. Use Emacs's own introspection - the `introspect` tool, `describe-function` or `apropos` - to find the standard Emacs function that removes the whitespace at both ends, and make `text-trim` call that function instead of its own regular expression. Do not write your own regular expression and do not change `text-test.el`.
```

## Done means

- `emacs -Q --batch -L . -l text-test.el -f ert-run-tests-batch-and-exit` exits 0.
- `text.el` calls the built-in `string-trim`, the Emacs function that removes
  whitespace at both ends.
- `text-test.el` is unchanged.
