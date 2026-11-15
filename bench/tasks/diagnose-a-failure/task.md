# Diagnose a command that fails

**Kind:** diagnose-a-failure

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. The command `./build.sh` in it fails. Run it and write a report to `report.txt` in the same directory. The report has exactly two lines: the first line is `exit-code: N`, where N is the exit code of `./build.sh`; the second line is `error: MESSAGE`, where MESSAGE is the text the command printed on its standard error, copied exactly.
```

## Done means

- `report.txt` exists in the workspace.
- It names the exit code `3` of the command.
- It carries the error text the command printed, `cannot read settings.toml`.
