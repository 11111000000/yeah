# Write a new file that a test expects

**Kind:** write-a-new-file

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. Create a new file `greet.el` in it that defines the function `greet`: `(greet NAME)` returns the string `Hello, NAME!`, and when NAME is nil or the empty string it returns `Hello, world!`. The file must provide the feature `greet`, that is, it must end with `(provide 'greet)`, so that `(require 'greet)` works. Do not change `greet-test.el`.
```

## Done means

- `greet.el` exists in the workspace and provides the feature `greet`.
- `emacs -Q --batch -L . -l greet-test.el -f ert-run-tests-batch-and-exit` exits 0.
- `greet-test.el` is unchanged.
