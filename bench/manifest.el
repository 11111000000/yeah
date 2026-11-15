;;; manifest.el --- the task set of the Yeah benchmark -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The task set of the comparative benchmark, and the single place the runner
;; reads it from.  Loading this file has no effect besides defining the
;; constant below: it creates nothing, runs nothing and reads no environment.
;;
;; Every entry is a plist:
;;
;;   :id         the stable name of the task
;;   :title      the human-readable title
;;   :directory  the directory of the task, relative to the root of the checkout
;;   :prompt     the exact prompt the person gives the agent
;;   :check      the command that judges the task, run in the task workspace
;;
;; The prompt holds the literal text `%workspace%'.  The runner replaces it
;; with the absolute path of the task workspace before the prompt reaches any
;; harness, so that the same task can be run in a fresh temporary workspace
;; and still name an absolute path.  Every other character is the person's
;; own text.
;;
;; The check command is a shell command line.  A word that starts with `./' is
;; resolved against the directory of the task, every other word is passed on
;; as it is; the command runs with the task workspace as its working
;; directory.

;;; Code:

(defconst yeah-bench-manifest
  '((:id "read-answer"
     :title "Read a file and answer with a number"
     :directory "bench/tasks/read-answer"
     :prompt "The task workspace is %workspace%. Read the file `sales.csv` in it and write the total revenue of the whole file - the sum of quantity times unit_price over every row - as a plain integer into `answer.txt` in the same directory. Write only that number in the file."
     :check "bash ./check.sh")
    (:id "fix-failing-test"
     :title "Fix the function that breaks the test"
     :directory "bench/tasks/fix-failing-test"
     :prompt "The task workspace is %workspace%. The test `calc-test.el` fails. Fix the code in `calc.el` so that the test passes: `calc-average` must return the average of the numbers as a fraction, not as a truncated integer. Do not change `calc-test.el`."
     :check "bash ./check.sh")
    (:id "write-new-file"
     :title "Write a new file that a test expects"
     :directory "bench/tasks/write-new-file"
     :prompt "The task workspace is %workspace%. Create a new file `greet.el` in it that defines the function `greet`: `(greet NAME)` returns the string `Hello, NAME!`, and when NAME is nil or the empty string it returns `Hello, world!`. The file must provide the feature `greet`, that is, it must end with `(provide 'greet)`, so that `(require 'greet)` works. Do not change `greet-test.el`."
     :check "bash ./check.sh")
    (:id "change-existing-behaviour"
     :title "Change what an existing function does"
     :directory "bench/tasks/change-existing-behaviour"
     :prompt "The task workspace is %workspace%. The function `trim-spaces` in `strings.el` removes the spaces at the start of the string but leaves the ones at the end. Change it so that it removes the spaces at both ends. Keep the name `trim-spaces` and its one argument, and keep the behaviour of the rest of the file. Do not change `strings-test.el`."
     :check "bash ./check.sh")
    (:id "run-command-and-report"
     :title "Run a command and report what it said"
     :directory "bench/tasks/run-command-and-report"
     :prompt "The task workspace is %workspace%. Run `./compute.sh` in it and write the output of the command, exactly as the command printed it and nothing else, into `output.txt` in the same directory."
     :check "bash ./check.sh")
    (:id "refactor-with-callers"
     :title "Rename a function and update its callers"
     :directory "bench/tasks/refactor-with-callers"
     :prompt "The task workspace is %workspace%. The function `legacy-format` in `records.el` has a name that does not describe it any more. Rename it to `record-format` and update every caller - `main.el` calls it too. Keep the behaviour of the function exactly as it is. Do not change `refactor-test.el`."
     :check "bash ./check.sh")
    (:id "diagnose-a-failure"
     :title "Diagnose a command that fails"
     :directory "bench/tasks/diagnose-a-failure"
     :prompt "The task workspace is %workspace%. The command `./build.sh` in it fails. Run it and write a report to `report.txt` in the same directory. The report has exactly two lines: the first line is `exit-code: N`, where N is the exit code of `./build.sh`; the second line is `error: MESSAGE`, where MESSAGE is the text the command printed on its standard error, copied exactly."
     :check "bash ./check.sh")
    (:id "write-documentation"
     :title "Document two functions"
     :directory "bench/tasks/write-documentation"
     :prompt "The task workspace is %workspace%. Write the file `money.md` in it. It documents the two functions of `money.el`: for each of `money-add` and `money-zero-p` there must be a section whose heading is exactly `## money-add` or `## money-zero-p`, and under that heading a line that starts with `Signature:` and names the function with its arguments, and a line that starts with `Summary:` with one sentence about what the function does."
     :check "bash ./check.sh")
    (:id "emacs-introspection"
     :title "Find the Emacs function that does the job"
     :directory "bench/tasks/emacs-introspection"
     :prompt "The task workspace is %workspace%. The function `text-trim` in `text.el` removes only the whitespace at the start of the string. Use Emacs's own introspection - the `introspect` tool, `describe-function` or `apropos` - to find the standard Emacs function that removes the whitespace at both ends, and make `text-trim` call that function instead of its own regular expression. Do not write your own regular expression and do not change `text-test.el`."
     :check "bash ./check.sh")
    (:id "implement-with-tests"
     :title "Implement a module and a second function, with tests"
     :directory "bench/tasks/implement-with-tests"
     :prompt "The task workspace is %workspace%. Two steps. First implement the three functions of `stack.el`: `stack-push` pushes a value on a stack and returns the new stack, `stack-pop` removes the top value of a stack and returns the new stack, and `stack-peek` returns the top value without removing it. Second create the new file `stack-depth.el` with the function `stack-depth`, which returns the number of items on a stack; the file must provide the feature `stack-depth`, that is, it must end with `(provide 'stack-depth)`. Do not change `stack-test.el` or `stack-depth-test.el`."
     :check "bash ./check.sh"))
  "The task set of the comparative benchmark.

Every entry is a plist with the keys `:id', `:title', `:directory', `:prompt'
and `:check'.  The runner reads the task set from this constant and from
nowhere else.")

;;; manifest.el ends here
