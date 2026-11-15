# Read a file and answer with a number

**Kind:** read-and-answer

## Prompt

The exact text given to the agent.  The runner replaces `%workspace%` with the
absolute path of the task workspace before the agent sees it; every other
character is the person's own text.

```text
The task workspace is %workspace%. Read the file `sales.csv` in it and write the total revenue of the whole file - the sum of quantity times unit_price over every row - as a plain integer into `answer.txt` in the same directory. Write only that number in the file.
```

## Done means

- `answer.txt` exists in the workspace.
- It holds the integer `100` (3x15 + 2x20 + 5x3) and nothing else.
