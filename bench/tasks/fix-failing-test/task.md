# Fix the function that breaks the test

**Kind:** fix-a-failing-test

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. The test `calc-test.el` fails. Fix the code in `calc.el` so that the test passes: `calc-average` must return the average of the numbers as a fraction, not as a truncated integer. Do not change `calc-test.el`.
```

## Done means

- `emacs -Q --batch -L . -l calc-test.el -f ert-run-tests-batch-and-exit` exits 0.
- `calc-average` of `(1 2 3 4)` is `2.5` and of `(2 3 4)` is `3.0`.
- `calc-test.el` is unchanged.
