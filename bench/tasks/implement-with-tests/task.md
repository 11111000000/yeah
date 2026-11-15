# Implement a module and a second function, with tests

**Kind:** multi-step implement-with-tests

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. Two steps. First implement the three functions of `stack.el`: `stack-push` pushes a value on a stack and returns the new stack, `stack-pop` removes the top value of a stack and returns the new stack, and `stack-peek` returns the top value without removing it. Second create the new file `stack-depth.el` with the function `stack-depth`, which returns the number of items on a stack; the file must provide the feature `stack-depth`, that is, it must end with `(provide 'stack-depth)`. Do not change `stack-test.el` or `stack-depth-test.el`.
```

## Done means

- `emacs -Q --batch -L . -l stack-test.el -f ert-run-tests-batch-and-exit` exits 0:
  the stack holds the items in the order they were pushed, `stack-peek` reads the
  top without removing it and `stack-pop` removes it.
- `emacs -Q --batch -L . -l stack-depth-test.el -f ert-run-tests-batch-and-exit`
  exits 0: `stack-depth.el` exists and provides the feature `stack-depth`.
- Neither test file is changed.
