;;; run-bench.el --- run the comparative benchmark task set -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Development-only apparatus.  It gives the task set of `bench/tasks/' to the
;; harnesses that are configured, runs the check of every task in a fresh
;; temporary workspace, and writes what it measured.  Nothing under `lib/'
;; requires this file, the package does not ship it, and no existing test
;; depends on it: it is a tool of the person who owns the benchmark, not a
;; part of Yeah.
;;
;; Usage:
;;
;;   emacs -Q --batch -L lib -l bench/run-bench.el -- --self-check
;;   emacs -Q --batch -L lib -l bench/run-bench.el -- --run
;;
;; `--self-check' proves three things without a model: every task exists, has a
;; prompt, and has an executable `check.sh' that fails on an untouched
;; workspace; the runner records a harness that could not run as
;; `skipped: no provider', never as a pass; and the filter of the measurement
;; selects exactly the tasks it was asked for and refuses a name the set does
;; not hold.  `--run' measures: it gives every task to every configured
;; harness and records one JSON line per (task, harness) in
;; `bench/results/<timestamp>.jsonl'.
;;
;; The runner reports measurements, never a verdict.  No acceptance threshold
;; for parity is declared, so no status below says that Yeah is as good as
;; another harness; that decision belongs to the owner (docs/PLAN.md, 13).
;;
;; Environment:
;;
;;   YEAH_TEST_KEY             the provider key of the Yeah harness
;;   YEAH_TEST_HOST            the provider host, for example api.minimax.io
;;   YEAH_TEST_MODEL           the model, for example MiniMax-M3
;;   YEAH_BENCH_EXTERNAL_COMMAND  the command template of the external harness
;;   YEAH_BENCH_EXTERNAL_NAME     the label of the external harness
;;   YEAH_BENCH_TASKS          the tasks of the measurement, comma separated;
;;                             every task of the set when it is not set
;;
;; Exit codes:
;;
;;   0  the apparatus did its work; a measurement is not a parity verdict
;;   1  a task of the set is malformed, or the self-check did not hold
;;   2  the arguments or the task set are unusable

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)

(defconst yeah-bench--statuses '("passed" "failed" "blocked" "skipped" "not-available")
  "The five statuses a measurement may carry.  `blocked' means that the
provider failed and the agent was never measured; it is neither a pass nor a
failure of the agent.")

(defconst yeah-bench--outcomes '("ran" "skipped" "not-available")
  "The outcomes a harness may report before the check decides the status.")

(defconst yeah-bench--provider-markers
  '("overloaded_error" "rate_limit" "rate limit" "server_error"
    "insufficient capacity" "service unavailable" "no available channel"
    ":http_code \"5" "http_code 5" "http 5")
  "Markers that name a failure of the provider in the text of a run.
A provider that fails is not an agent that fails: the run it stops was never
measured, and a measurement of nothing is not a failure of the agent.")

(defun yeah-bench--provider-error (text)
  "Return the marker that names a provider failure in TEXT, or nil."
  (when (stringp text)
    (let ((down (downcase text)))
      (cl-find-if (lambda (marker) (string-match-p (regexp-quote marker) down))
                  yeah-bench--provider-markers))))

(defconst yeah-bench--yeah-tools
  '("read" "glob" "grep" "edit" "write" "bash" "job-status" "job-read"
    "elisp-check" "introspect" "finish")
  "The tools the Yeah harness may use in a benchmark task.
`finish' is in the list because the system prompt of the harness asks the
model to end the run with it, and the run layer allows it anyway; a tool the
prompt names and the permission refuses is a contradiction the model pays
for in turns.")

(defconst yeah-bench--check-timeout 300
  "Seconds a task check may run before the runner stops it.")

(defconst yeah-bench--turn-timeout 900
  "Seconds one agent turn may run before the runner stops waiting for it.")

(declare-function yeah-session-open "yeah-session" (session-id &optional root))
(declare-function yeah-control-new "yeah-control"
  (session &optional transport answerer budget max-nudges frozen))
(declare-function yeah-control-ask "yeah-control" (control prompt &optional frozen))
(declare-function yeah-control-active-turn "yeah-control" (control))
(declare-function yeah-gptel-request "yeah-gptel" (prompt callback &rest args))
(declare-function yeah-tools-names "yeah-tools" ())
(declare-function yeah-gptel-tool-for "yeah-gptel" (name))
(declare-function yeah-turn-done "yeah-turn" (turn))
(declare-function yeah-turn-state "yeah-turn" (turn))
(declare-function gptel-make-openai "gptel-openai" (name &rest args))

;;; The task set.

(defvar yeah-bench--directory nil
  "The directory that holds this runner, the manifest and the tasks.
It is remembered while the runner is loaded, because the name of the file
being loaded is only bound during the load.")

(defun yeah-bench--remember-directory ()
  "Remember the directory of the runner; called while the runner is loaded."
  (setq yeah-bench--directory
        (file-name-directory
         (expand-file-name (or load-file-name buffer-file-name default-directory)))))

(defun yeah-bench--root ()
  "Return the root directory of the checkout."
  (expand-file-name ".." (or yeah-bench--directory default-directory)))

(defun yeah-bench--results-directory ()
  "Return the directory that holds the result files."
  (expand-file-name "results" (or yeah-bench--directory default-directory)))

(defun yeah-bench--manifest ()
  "Return the task list of the manifest."
  (let ((file (expand-file-name "manifest.el"
                                (or yeah-bench--directory default-directory))))
    (unless (file-readable-p file)
      (error "the benchmark manifest is not readable: %s" file))
    (load file nil t)
    (let ((manifest (and (boundp 'yeah-bench-manifest) yeah-bench-manifest)))
      (unless (and (listp manifest) manifest)
        (error "the benchmark manifest does not define `yeah-bench-manifest'"))
      manifest)))

(defun yeah-bench--task-directory (task)
  "Return the directory of TASK."
  (expand-file-name (plist-get task :directory) (yeah-bench--root)))

(defun yeah-bench--task-filter ()
  "Return the ids of the tasks the environment asks for.
The names come from `YEAH_BENCH_TASKS', comma separated.  The list is nil
when the environment does not ask for a subset: then every task of the set
is measured."
  (let ((raw (getenv "YEAH_BENCH_TASKS")))
    (when (and (stringp raw) (> (length (string-trim raw)) 0))
      (let ((names (mapcar #'string-trim (split-string (string-trim raw) "," t))))
        (unless (seq-every-p (lambda (name) (> (length name) 0)) names)
          (error "the task filter names an empty task"))
        names))))

(defun yeah-bench--selected-tasks (tasks)
  "Return the tasks of TASKS the environment asks for.
A name the set does not hold is an error, never an empty run: a pilot that
measured nothing would look like a pilot that measured everything."
  (let ((filter (yeah-bench--task-filter)))
    (if (null filter)
        tasks
      (let* ((known (mapcar (lambda (task) (plist-get task :id)) tasks))
             (missing (seq-difference filter known)))
        (when missing
          (error "the task set does not hold the task(s) %s"
                 (string-join missing ", ")))
        (seq-filter (lambda (task) (member (plist-get task :id) filter)) tasks)))))

;;; The validation of the task set.

(defun yeah-bench--rubber-stamp-p (file)
  "Return non-nil when the check FILE is a script that cannot fail."
  (let (code)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties (line-beginning-position)
                                                   (line-end-position))))
          (unless (or (string-match-p "\\`[ \t]*\\'" line)
                      (string-match-p "\\`[ \t]*#" line))
            (push line code)))
        (forward-line 1)))
    (or (null code)
        (cl-every (lambda (line)
                    (member (string-trim line) '("true" ":" "exit 0")))
                  code))))

(defun yeah-bench--problems (task)
  "Return the list of what is wrong with TASK; empty when TASK is well formed."
  (let ((problems nil)
        (id (plist-get task :id))
        (title (plist-get task :title))
        (directory (plist-get task :directory))
        (prompt (plist-get task :prompt))
        (check (plist-get task :check)))
    (unless (and (stringp id) (> (length id) 0))
      (push "the task has no id" problems))
    (unless (and (stringp title) (> (length title) 0))
      (push "the task has no title" problems))
    (unless (and (stringp directory) (> (length directory) 0))
      (push "the task has no directory" problems))
    (unless (and (stringp prompt) (> (length prompt) 0))
      (push "the task has no prompt" problems))
    (unless (and (stringp check) (> (length check) 0))
      (push "the task has no check command" problems))
    (when (and (stringp directory) (> (length directory) 0))
      (let ((dir (yeah-bench--task-directory task)))
        (unless (file-directory-p dir)
          (push (format "the directory of the task does not exist: %s" dir)
                problems))
        (when (file-directory-p dir)
          (let ((task-file (expand-file-name "task.md" dir))
                (check-file (expand-file-name "check.sh" dir)))
            (unless (file-readable-p task-file)
              (push "task.md is missing" problems))
            (when (and (file-readable-p task-file)
                       (stringp prompt) (> (length prompt) 0))
              (unless (string-match
                       (regexp-quote prompt)
                       (with-temp-buffer
                         (insert-file-contents task-file)
                         (buffer-string)))
                (push "task.md does not carry the prompt of the manifest"
                      problems)))
            (unless (file-executable-p check-file)
              (push "check.sh is missing or is not executable" problems))
            (when (file-executable-p check-file)
              (when (yeah-bench--rubber-stamp-p check-file)
                (push "check.sh cannot fail; it is a rubber stamp" problems)))))))
    (nreverse problems)))

;;; The workspace of a task.

(defun yeah-bench--copy-tree (from to)
  "Copy every file under FROM into the directory TO."
  (dolist (file (directory-files-recursively from "" nil nil t))
    (let ((relative (file-relative-name file from)))
      (unless (or (string= relative "") (string= relative "."))
        (let ((target (expand-file-name relative to)))
          (make-directory (file-name-directory target) t)
          (copy-file file target t)
          (when (file-executable-p file)
            (set-file-modes target (file-modes file))))))))

(defun yeah-bench--workspace (task)
  "Return a fresh workspace for TASK, with the setup of the task copied in."
  (let* ((workspace (make-temp-file "yeah-bench-" t))
         (setup (expand-file-name "setup" (yeah-bench--task-directory task))))
    (when (file-directory-p setup)
      (yeah-bench--copy-tree setup workspace))
    workspace))

;;; The processes.

(defun yeah-bench--run (directory command &optional timeout)
  "Run COMMAND in DIRECTORY and return (STATUS . OUTPUT).
STATUS is the exit code of the command, or 124 when it had to be stopped."
  (let* ((buffer (generate-new-buffer " *yeah-bench-run*"))
         (deadline (+ (float-time) (or timeout yeah-bench--check-timeout)))
         ;; A process takes its working directory from `default-directory'.
         (process (let ((default-directory directory))
                    (make-process :name "yeah-bench-run"
                                  :buffer buffer
                                  :command command
                                  :connection-type 'pipe
                                  :noquery t))))
    (with-current-buffer buffer
      (while (and (process-live-p process) (< (float-time) deadline))
        (accept-process-output process 0.1))
      (if (process-live-p process)
          (progn
            (kill-process process)
            (accept-process-output process 0.1)
            (cons 124 (buffer-string)))
        (cons (process-exit-status process) (buffer-string))))))

(defun yeah-bench--check-command (task)
  "Return the command that runs the check of TASK, as a list of words."
  (let* ((words (split-string (or (plist-get task :check) "")))
         (directory (yeah-bench--task-directory task)))
    (unless words
      (error "the task has no check command"))
    (cons (car words)
          (mapcar (lambda (word)
                    (if (string-prefix-p "./" word)
                        (expand-file-name word directory)
                      word))
                  (cdr words)))))

(defun yeah-bench--check (task workspace)
  "Run the check of TASK in WORKSPACE and return (STATUS . OUTPUT)."
  (yeah-bench--run workspace
                   (yeah-bench--check-command task)
                   yeah-bench--check-timeout))

(defun yeah-bench--prompt (task workspace)
  "Return the prompt of TASK for the workspace WORKSPACE."
  (replace-regexp-in-string "%workspace%" workspace
                            (or (plist-get task :prompt) "")
                            t t))

;;; The harnesses.

(defun yeah-bench--answerer (request)
  "Answer REQUEST with the rules of the benchmark: the tools of the task, no more."
  (let ((action (plist-get request :action)))
    (if (member action yeah-bench--yeah-tools)
        (list :effect :allow :reply :once)
      (list :effect :deny :reply :reject
            :reason (format "the benchmark does not allow %s" action)))))

(defun yeah-bench--yeah-system (workspace)
  "Return the system prompt of the Yeah harness for the workspace WORKSPACE."
  (format "You are an agent inside Emacs, working in the task workspace %s. You have the tools: %s. Act with the tools; do not describe what you are about to do. Give every file and every command the absolute path inside %s, and give the bash tool that directory as its `directory' argument. When the work is done and you have checked it, call the finish tool with a summary."
          workspace
          (string-join yeah-bench--yeah-tools ", ")
          workspace))

(defun yeah-bench--yeah-tool-objects ()
  "Return the gptel descriptions of the tools the benchmark permits.
The harness offers the model exactly the tools it may use: a model that is
offered a tool it may not use spends its turns on refusals, and the
measurement would then say more about the harness than about the agent."
  (require 'yeah-tools)
  ;; The registry registers the built-in tools when it is asked for their
  ;; names; the descriptions need them to be there.
  (yeah-tools-names)
  (mapcar #'yeah-gptel-tool-for yeah-bench--yeah-tools))

(defun yeah-bench--wait (turn)
  "Wait for TURN to finish and return the state it ended in."
  (let ((deadline (+ (float-time) yeah-bench--turn-timeout)))
    (while (and (not (yeah-turn-done turn)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (yeah-turn-state turn)))

(defun yeah-bench--journal-provider-error (path)
  "Return the provider failure that the journal at PATH names, or nil.
Only the error records count: a tool output that quotes a provider message
is not a failure of the provider, and a run the provider stopped is a run
that was never measured."
  (when (and (stringp path) (file-exists-p path))
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8-unix))
        (ignore-errors (insert-file-contents path)))
      (goto-char (point-min))
      (let ((found nil))
        (while (and (not found) (not (eobp)))
          (let* ((line (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position)))
                 (record (and (not (string-empty-p (string-trim line)))
                               (ignore-errors
                                 (json-parse-string line :object-type 'alist)))))
            (when (and (consp record)
                       (equal (alist-get 'type record) "error"))
              (setq found (yeah-bench--provider-error
                           (format "%s" (alist-get 'payload record))))))
          (forward-line 1))
        found))))

(defun yeah-bench--yeah-harness (task workspace prompt session-root)
  "Give TASK to Yeah in WORKSPACE with PROMPT and return the outcome.
SESSION-ROOT is the directory that holds the journal of the run."
  (let ((key (getenv "YEAH_TEST_KEY")))
    (if (or (null key) (string-empty-p key))
        (list :outcome "skipped" :reason "no provider")
      (condition-case err
          (yeah-bench--yeah-turn task workspace prompt session-root)
        (error (list :outcome "not-available"
                     :reason (format "the Yeah harness could not run: %s"
                                     (error-message-string err))))))))

(defun yeah-bench--yeah-turn (task workspace prompt session-root)
  "Run one Yeah turn for TASK in WORKSPACE and return the outcome."
  (require 'gptel)
  (require 'gptel-openai)
  (require 'yeah-control)
  (require 'yeah-gptel)
  (require 'yeah-session)
  (require 'yeah-turn)
  (let* ((key (getenv "YEAH_TEST_KEY"))
         (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
         (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M3"))
         (backend (gptel-make-openai "yeah-bench"
                                     :host host
                                     :endpoint "/v1/chat/completions"
                                     :key key
                                     :models (list (intern model))))
         (session (yeah-session-open (format "bench-%s" (plist-get task :id))
                                      session-root))
         (system (yeah-bench--yeah-system workspace))
         (control nil)
         (turn nil))
    (setq control
          (yeah-control-new
           session
           (lambda (request callback)
             (yeah-gptel-request request callback
                                 :backend backend
                                 :model (intern model)
                                 :system system
                                 :tools (yeah-bench--yeah-tool-objects)))
           #'yeah-bench--answerer
           nil 3))
    (yeah-control-ask control prompt)
    (setq turn (yeah-control-active-turn control))
    (unless turn
      (error "the run did not start"))
    (list :outcome "ran"
          :note (format "the turn ended in %s" (yeah-bench--wait turn))
          :provider-error (yeah-bench--journal-provider-error
                           (plist-get session :path)))))

(defun yeah-bench--external-template ()
  "Return the command template of the external harness, or nil."
  (let ((template (getenv "YEAH_BENCH_EXTERNAL_COMMAND")))
    (and (stringp template)
         (> (length (string-trim template)) 0)
         (string-trim template))))

(defun yeah-bench--external-name ()
  "Return the label of the external harness."
  (let ((name (getenv "YEAH_BENCH_EXTERNAL_NAME")))
    (if (and (stringp name) (> (length (string-trim name)) 0))
        (string-trim name)
      "external")))

(defun yeah-bench--external-binary (template)
  "Return the executable that TEMPLATE names, or nil when it is not installed."
  (let ((first (car (split-string template))))
    (and (stringp first)
         (if (string-match-p "[/\\\\]" first)
             (and (file-executable-p first) first)
           (executable-find first)))))

(defun yeah-bench--external-command (template workspace prompt)
  "Return the words of the external command for WORKSPACE and PROMPT."
  (let ((workspace-argument (shell-quote-argument workspace))
        (prompt-argument (shell-quote-argument prompt)))
    (mapcar (lambda (word)
              (replace-regexp-in-string
               "%prompt%" prompt-argument
               (replace-regexp-in-string "%workspace%" workspace-argument word t t)
               t t))
            (split-string template))))

(defun yeah-bench--external-harness (_task workspace prompt _session-root)
  "Give TASK to the external harness in WORKSPACE with PROMPT.
Return the outcome of the harness."
  (let ((template (yeah-bench--external-template)))
    (if (null template)
        (list :outcome "not-available" :reason "no external harness is configured")
      (if (null (yeah-bench--external-binary template))
          (list :outcome "not-available"
                :reason (format "the external harness %s is not installed"
                                (car (split-string template))))
        (let* ((command (yeah-bench--external-command template workspace prompt))
               ;; The harness gets the end of its standard input at once.  A
               ;; harness that reads it waits for the end of the pipe, and the
               ;; pipe of the runner never ends: the harness would wait for
               ;; the whole turn timeout and be counted as a failure that the
               ;; harness never had a chance to avoid.
               (result (yeah-bench--run workspace
                                         (list "sh" "-c"
                                               (format "%s < /dev/null"
                                                       (string-join command " ")))
                                         yeah-bench--turn-timeout))
               (output (cdr result))
               (tail (if (> (length output) 8000)
                         (substring output (- (length output) 8000))
                       output)))
          (list :outcome "ran"
                :note (format "the external harness exited with %s" (car result))
                :provider-error (yeah-bench--provider-error tail)))))))

;;; The measurement.

(defun yeah-bench--harnesses ()
  "Return the list of (NAME FUNCTION) harnesses that are configured."
  (let ((harnesses (list (list "yeah" #'yeah-bench--yeah-harness))))
    (when (yeah-bench--external-template)
      (push (list (yeah-bench--external-name) #'yeah-bench--external-harness)
            harnesses))
    (nreverse harnesses)))

(defun yeah-bench--excerpt (text)
  "Return a short one-line excerpt of TEXT for the reason of a measurement."
  (let* ((lines (split-string (or text "") "\n" t))
         (kept (cl-subseq lines (max 0 (- (length lines) 2))))
         (one (string-join kept " | ")))
    (if (> (length one) 160)
        (concat (substring one 0 157) "...")
      one)))

(defun yeah-bench--measure (name function task workspace prompt session-root)
  "Measure the harness NAME (FUNCTION) on TASK in WORKSPACE and return it."
  (let* ((outcome (condition-case err
                      (funcall function task workspace prompt session-root)
                    (error (list :outcome "not-available"
                                 :reason (format "the harness could not run: %s"
                                                 (error-message-string err))))))
         (kind (or (plist-get outcome :outcome) "not-available"))
         (reason (or (plist-get outcome :reason) (plist-get outcome :note) ""))
         (provider-error (plist-get outcome :provider-error)))
    (unless (member kind yeah-bench--outcomes)
      (error "the harness %s returned the unknown outcome %s" name kind))
    (cond
     ((equal kind "skipped")
      (list :task (plist-get task :id)
            :harness name
            :status "skipped"
            :check-exit nil
            :reason reason))
     ((equal kind "not-available")
      (list :task (plist-get task :id)
            :harness name
            :status "not-available"
            :check-exit nil
            :reason reason))
     (t
      (let* ((result (yeah-bench--check task workspace))
             (exit (car result))
             (status (cond ((memq exit '(126 127)) "not-available")
                           ((= 0 exit) "passed")
                           ((and (stringp provider-error)
                                 (> (length provider-error) 0))
                            "blocked")
                           (t "failed")))
             (why (cond
                   ((memq exit '(126 127))
                    (format "the check could not run (exit %s); is emacs on PATH or is EMACS set?"
                            exit))
                   ((= 0 exit)
                    (format "the check exited 0%s"
                            (if (> (length reason) 0) (format "; %s" reason) "")))
                   ((and (stringp provider-error)
                         (> (length provider-error) 0))
                    (format "the provider failed, so the agent was not measured: %s; the check exited %s: %s"
                            provider-error exit (yeah-bench--excerpt (cdr result))))
                   (t (format "the check exited %s: %s"
                              exit (yeah-bench--excerpt (cdr result)))))))
        (unless (member status yeah-bench--statuses)
          (error "the measurement has the unknown status %s" status))
        (list :task (plist-get task :id)
              :harness name
              :status status
              :check-exit exit
              :reason why))))))

;;; The results.

(defun yeah-bench--timestamp ()
  "Return the timestamp of the run, as the name of its result file."
  (format-time-string "%Y%m%dT%H%M%SZ" (current-time)))

(defun yeah-bench--result-file (timestamp)
  "Return the file that holds the results of the run TIMESTAMP."
  (expand-file-name (concat timestamp ".jsonl")
                     (yeah-bench--results-directory)))

(defun yeah-bench--write-result (file measurement)
  "Append MEASUREMENT to the result file FILE as one JSON line."
  (let ((line (json-encode
               (list (cons "task" (plist-get measurement :task))
                     (cons "harness" (plist-get measurement :harness))
                     (cons "status" (plist-get measurement :status))
                     (cons "check_exit" (plist-get measurement :check-exit))
                     (cons "reason" (plist-get measurement :reason))))))
    (make-directory (file-name-directory file) t)
    (with-temp-buffer
      (let ((coding-system-for-write 'utf-8))
        (insert line "\n")
        (write-region (point-min) (point-max) file 'append 'no-message)))
    measurement))

(defun yeah-bench--read-records (file)
  "Return the records of the result file FILE, as alists.
The keys of a record are the symbols of its fields."
  (with-temp-buffer
    (insert-file-contents file)
    (let (records)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties (line-beginning-position)
                                                   (line-end-position))))
          (unless (string-empty-p (string-trim line))
            (push (json-parse-string line :object-type 'alist) records)))
        (forward-line 1))
      (nreverse records))))

(defun yeah-bench--print-row (row widths)
  "Print ROW, padded to the column WIDTHS; the last column is not padded."
  (let ((cells nil)
        (rest row)
        (padded (butlast widths)))
    (while rest
      (let ((cell (car rest)))
        (push (if padded
                  (format (format "%%-%ds" (car padded)) cell)
                cell)
              cells))
      (setq rest (cdr rest)
            padded (cdr padded)))
    (princ (string-join (nreverse cells) "  "))
    (princ "\n")))

(defun yeah-bench--print-table (measurements)
  "Print the comparison table of MEASUREMENTS."
  (let* ((rows (mapcar (lambda (measurement)
                         (list (plist-get measurement :task)
                               (plist-get measurement :harness)
                               (plist-get measurement :status)
                               (if (plist-get measurement :check-exit)
                                   (number-to-string (plist-get measurement :check-exit))
                                 "-")
                               (plist-get measurement :reason)))
                       measurements))
         (headers (list "TASK" "HARNESS" "STATUS" "CHECK" "REASON"))
         (widths (mapcar (lambda (index)
                           (apply #'max
                                  (length (nth index headers))
                                  (mapcar (lambda (row) (length (nth index row)))
                                          rows)))
                         '(0 1 2 3 4))))
    (yeah-bench--print-row headers widths)
    (dolist (row rows)
      (yeah-bench--print-row row widths))))

;;; The honesty of the runner.

(defun yeah-bench--filter-problems (tasks)
  "Return the ways in which the filter of the measurement is not honest.
The filter must select exactly the tasks it was asked for, must refuse a name
the set does not hold, and must not drop a task when it is not asked to."
  (let* ((problems nil)
         (saved (getenv "YEAH_BENCH_TASKS"))
         (known (mapcar (lambda (task) (plist-get task :id)) tasks))
         (asked (cl-subseq known 0 (min 2 (length known)))))
    (unwind-protect
        (progn
          (setenv "YEAH_BENCH_TASKS" (string-join asked ","))
          (let ((selected (mapcar (lambda (task) (plist-get task :id))
                                   (yeah-bench--selected-tasks tasks))))
            (unless (equal selected asked)
              (push (format "the filter selected %s instead of the tasks it was asked for: %s"
                            (string-join selected ", ")
                            (string-join asked ", "))
                    problems)))
          (setenv "YEAH_BENCH_TASKS" "no-such-task-in-the-set")
          (unless (condition-case err
                      (progn (yeah-bench--selected-tasks tasks) nil)
                    (error t))
            (push "the filter accepted a task that the set does not hold: a pilot that measured nothing would look like a pilot that measured everything"
                  problems))
          (setenv "YEAH_BENCH_TASKS" nil)
          (unless (= (length (yeah-bench--selected-tasks tasks)) (length tasks))
            (push "the filter dropped tasks when it was not asked to"
                  problems)))
      (setenv "YEAH_BENCH_TASKS" saved))))

(defun yeah-bench--honesty-records (tasks)
  "Give every task of TASKS to the Yeah harness without credentials.
Return the records the runner wrote.  The records go to a scratch results
directory under `temporary-file-directory', never to `bench/results'."
  (let* ((scratch (make-temp-file "yeah-bench-self-check-" t))
         (file (expand-file-name "results/honesty.jsonl" scratch))
         (key (getenv "YEAH_TEST_KEY")))
    (unwind-protect
        (progn
          ;; The harness must meet the no-provider branch, whatever the
          ;; environment of the machine holds.
          (setenv "YEAH_TEST_KEY" nil)
          (dolist (task tasks)
            (let* ((workspace (yeah-bench--workspace task))
                   (prompt (yeah-bench--prompt task workspace))
                   (measurement (yeah-bench--measure
                                 "yeah" #'yeah-bench--yeah-harness
                                 task workspace prompt scratch)))
              (ignore-errors (delete-directory workspace t))
              (yeah-bench--write-result file measurement)))
          (yeah-bench--read-records file))
      (when key
        (setenv "YEAH_TEST_KEY" key))
      (ignore-errors (delete-directory scratch t)))))

(defun yeah-bench--honesty-problems (tasks records)
  "Return the ways in which RECORDS are not honest for TASKS.
A harness that could not run is `skipped' or `not-available'; it is never
a `passed' and never a `failed'."
  (let ((problems nil)
        (skipped 0))
    (dolist (record records)
      (let ((task (alist-get 'task record))
            (status (alist-get 'status record))
            (reason (alist-get 'reason record)))
        (cond
         ((equal status "passed")
          (push (format "%s: the runner recorded a pass for a harness that did not run"
                        task)
                problems))
         ((equal status "failed")
          (push (format "%s: the runner recorded a failure of the agent for a harness that did not run"
                        task)
                problems))
         ((equal status "skipped")
          (setq skipped (1+ skipped))
          (unless (and (stringp reason) (string-match-p "no provider" reason))
            (push (format "%s: the runner skipped the task without naming the cause: %s"
                          task reason)
                  problems)))
         ((equal status "blocked")
          (push (format "%s: the runner recorded a provider failure for a harness that did not run"
                        task)
                problems))
         ((equal status "not-available")
          nil)
         (t
          (push (format "%s: the runner recorded the unknown status %s for a harness that did not run"
                        task status)
                problems)))))
    (dolist (task tasks)
      (let ((id (plist-get task :id)))
        (unless (seq-find (lambda (record)
                             (equal (alist-get 'task record) id))
                           records)
          (push (format "%s: the runner recorded nothing for the task" id)
                problems))))
    (when (and (> (length tasks) 0) (= 0 skipped))
      (push "the no-provider branch did not fire: no task was recorded as skipped with the reason \"no provider\""
            problems))
    (nreverse problems)))

;;; The two modes.

(defun yeah-bench--provider-problems (tasks)
  "Return the ways in which the runner counts a provider failure as a failure
of the agent.  A provider that fails is not an agent that fails: the run it
stopped was never measured, and the measurement of nothing must not be
recorded as a failure."
  (let ((problems nil)
        (task (car tasks)))
    (when task
      (let* ((root (make-temp-file "yeah-bench-provider-" t))
             (journal (expand-file-name "bench.jsonl" root)))
        (unwind-protect
            (progn
              (with-temp-file journal
                (insert (json-encode
                         (list (cons "type" "error")
                               (cons "payload"
                                     "(:type \"overloaded_error\" :http_code \"529\")")))
                        "\n"))
              (unless (yeah-bench--journal-provider-error journal)
                (push "the journal of a provider failure was not read as a failure of the provider"
                      problems))
              (let* ((workspace (yeah-bench--workspace task))
                     (measurement (yeah-bench--measure
                                   "yeah"
                                   (lambda (_task _workspace _prompt _session-root)
                                     (list :outcome "ran"
                                           :note "the turn ended in failed"
                                           :provider-error "overloaded_error"))
                                   task workspace "a prompt" root)))
                (unless (equal (plist-get measurement :status) "blocked")
                  (push (format "the runner recorded %s for a run the provider stopped"
                                (plist-get measurement :status))
                        problems))
                (ignore-errors (delete-directory workspace t))))
          (ignore-errors (delete-directory root t)))))
    (nreverse problems)))
(defun yeah-bench--self-check ()
  "Validate the task set without a model; exit 0 when it holds, 1 when it does not."
  (let* ((tasks (yeah-bench--manifest))
         (problems nil))
    (when (null tasks)
      (princ "self-check: the task set is empty\n")
      (kill-emacs 1))
    (dolist (task tasks)
      (dolist (problem (yeah-bench--problems task))
        (push (format "%s: %s" (plist-get task :id) problem) problems)))
    (when problems
      (dolist (problem (nreverse problems))
        (princ (format "self-check: %s\n" problem)))
      (princ "self-check: the task set is malformed\n")
      (kill-emacs 1))
    (dolist (task tasks)
      (let* ((workspace (yeah-bench--workspace task))
             (result (yeah-bench--check task workspace)))
        (ignore-errors (delete-directory workspace t))
        (cond
         ((memq (car result) '(126 127))
          (princ (format "self-check: %s: the check could not run (exit %s); is emacs on PATH or is EMACS set?\n"
                         (plist-get task :id) (car result)))
          (kill-emacs 1))
         ((= 0 (car result))
          (princ (format "self-check: %s: the check passes on an untouched workspace; it is a rubber stamp\n"
                         (plist-get task :id)))
          (kill-emacs 1))
         (t
          (princ (format "self-check: %s: the check exits %s on an untouched workspace\n"
                         (plist-get task :id) (car result)))))))
    (let ((dishonest (yeah-bench--honesty-problems
                      tasks (yeah-bench--honesty-records tasks))))
      (when dishonest
        (dolist (problem dishonest)
          (princ (format "self-check: %s\n" problem)))
        (princ "self-check: the runner was not honest about a harness that could not run\n")
        (kill-emacs 1)))
    (let ((dishonest (yeah-bench--filter-problems tasks)))
      (when dishonest
        (dolist (problem dishonest)
          (princ (format "self-check: %s\n" problem)))
        (princ "self-check: the filter of the measurement was not honest\n")
        (kill-emacs 1)))
    (let ((dishonest (yeah-bench--provider-problems tasks)))
      (when dishonest
        (dolist (problem dishonest)
          (princ (format "self-check: %s\n" problem)))
        (princ "self-check: the runner counted a failure of the provider as a failure of the agent\n")
        (kill-emacs 1)))
    (princ (format "self-check: %s tasks, every check fails before the work\n"
                   (length tasks)))
    (princ (format "self-check: %s tasks, every harness that could not run is recorded as skipped: no provider\n"
                   (length tasks)))
    (princ (format "self-check: %s tasks, a run the provider stopped is recorded as blocked, not as a failure of the agent\n"
                   (length tasks)))
    (princ (format "self-check: %s tasks, the filter selects exactly the tasks it is asked for\n"
                   (length tasks)))
    (kill-emacs 0)))

(defun yeah-bench--run-bench ()
  "Measure every task with every configured harness.
Return a plist (:measurements LIST :file FILE)."
  (let* ((tasks (yeah-bench--selected-tasks (yeah-bench--manifest)))
         (timestamp (yeah-bench--timestamp))
         (file (yeah-bench--result-file timestamp))
         (session-root (expand-file-name timestamp (yeah-bench--results-directory)))
         (measurements nil))
    (make-directory (yeah-bench--results-directory) t)
    (dolist (task tasks)
      (dolist (harness (yeah-bench--harnesses))
        (let* ((name (nth 0 harness))
               (function (nth 1 harness))
               (workspace (yeah-bench--workspace task))
               (prompt (yeah-bench--prompt task workspace))
               (measurement nil))
          (setq measurement (yeah-bench--measure name function task workspace
                                                 prompt session-root))
          (ignore-errors (delete-directory workspace t))
          (push (yeah-bench--write-result file measurement) measurements))))
    (list :measurements (nreverse measurements) :file file)))

(defun yeah-bench--main ()
  "Run the benchmark as the command line asks; exit with the code of the mode."
  (let ((arguments (append command-line-args-left nil)))
    (cond
     ((member "--self-check" arguments)
      (yeah-bench--self-check))
     ((member "--run" arguments)
      (condition-case err
          (let* ((run (yeah-bench--run-bench))
                 (measurements (plist-get run :measurements)))
            (yeah-bench--print-table measurements)
            (princ (format "\nthe results are in %s\n" (plist-get run :file)))
            (kill-emacs 0))
        (error
         ;; The task set and the filter are the input of the measurement: an
         ;; unusable one is a blocked measurement, not a failed task.
         (princ (format "the measurement cannot run: %s\n"
                        (error-message-string err)))
         (kill-emacs 2))))
     (t
      (princ "usage: emacs -Q --batch -L lib -l bench/run-bench.el -- [--self-check|--run]\n")
      (kill-emacs 2)))))

(yeah-bench--remember-directory)

(when (or (member "--self-check" command-line-args-left)
          (member "--run" command-line-args-left))
  (yeah-bench--main))

;;; run-bench.el ends here
