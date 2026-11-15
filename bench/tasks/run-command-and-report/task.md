# Run a command and report what it said

**Kind:** run-a-command-and-report

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. Run `./compute.sh` in it and write the output of the command, exactly as the command printed it and nothing else, into `output.txt` in the same directory.
```

## Done means

- `output.txt` exists in the workspace and holds the line `sum=15`.
- `compute.sh` is the command that was there before the run: it still sums
  `numbers.txt` itself, so the report cannot be a guess.
