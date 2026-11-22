;;; check-a-killed-gate-run-restarts-and-reaches-the-end.el --- a killed gate run restarts and reaches the end -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The gate of the project is a run of the method and the map that follows
;; it.  Three runs of the method died with SIGTERM on 2026-11-18, and the
;; way around it was a watchdog: a detached process that read a log file
;; every five seconds and started the run again.  The price was forty-four
;; minutes of waiting a day and copies of the run left behind.
;;
;; This check covers the way out of that: the gate itself waits for the
;; run, and the gate itself starts a run again when the run was killed.
;; No second process watches the first one, and no log is read.
;;
;; The check starts the real gate the way a person starts it -- through the
;; wrapper of the project (scripts/dev gate) -- with a stand-in for the
;; method (tests/support/yeah-fake-method.sh): the real method takes
;; minutes and writes the evidence trail of the project, and a check must
;; not do either.  The stand-in answers like the method in the two ways
;; the gate depends on: its first attempt waits for ever, and its map is
;; written when the run ends.
;;
;; The check kills the first attempt of the run -- the way an unknown
;; sender killed three runs of the method -- and proves five things: the
;; run was started again, the map reached the end, the gate answered the
;; verdict of the run, nothing of the run was left behind when the gate
;; answered, and the wrapper kept no gate of its own.
;;
;; The state of the run is read when it has settled.  The writer of the
;; state is the run -- the file of the attempts and the file of the map --
;; and the reader of it is the check, and the two are not one process: a
;; reader that judges the state before the writer has finished it judges
;; a state that is not there yet.  The check therefore waits for the
;; state to settle -- the file of the attempts shows the restart and the
;; file of the map holds the marker of the end of the run -- and it waits
;; a bounded time: a state that does not settle is a refusal of the
;; check, and not a comment.  The refusal names the file and the value
;; the check waited for, and it says how long the check waited.
;;
;; The words of the gate are read when they have come.  The output of the
;; gate is a pipe, and Emacs drains the pipe after the process of the
;; gate is reaped: a reader that reads the buffer of the output at the
;; death of the process reads a tail that has not come yet.  The check
;; waits for the output to stop growing, and the refusal of the check
;; names the words of the gate: the gate says why its map is not there,
;; and a refusal that loses that word names a subject that is not the
;; real one.  The diagnostic of the refusal -- the output of the gate --
;; is whole.
;;
;; The control of the claim takes the restart away from the gate: the
;; gate answers the kill and stops there, and the check then fails by its
;; own assertion -- the killed run was not started again.  The control
;; that takes the wait away leaves the run behind, and the check fails by
;; the other of its assertions.
;;
;; The check measures the subject by the run it started and not by the
;; machine it runs on: the processes of the run are the processes that
;; hold the directory of the run in their environment -- every process
;; the run starts inherits it -- and the pids the check knows, the pid
;; of the gate and the pid of every attempt of the run.  A process that
;; only mentions the stand-in of the method is not a process of this
;; run, and a check that names it names a process that is not the run
;; of the check.  It does not ask the gate whether it is alive: a gate
;; that answers is a gate that lives.  The state of the process decides
;; whether it lives: `S' and `R' are a process that runs, and `Z' is a
;; zombie -- a process that has died already and waits to be reaped.
;; The rule is the one of the kernel (`lib/yeah-proc.el').
;;
;; The processes of the run get a moment to go before the check calls them
;; leftovers: what the pilot of the run removes when it ends is not a
;; leftover of the run -- it is the opposite of one.  A process that is
;; still there after that moment is a leftover, and the check names it.
;;
;; No network is involved: the method is a stand-in and the files of the
;; run live in a private temporary directory.
;;
;; Exit codes: 0 -- the killed run was started again and the map reached
;; the end; 1 -- it was not.

;;; Code:

(require 'cl-lib)
(require 'yeah-proc)

(defvar yeah-gate--failures nil
  "The failures this check found.")

(defconst yeah-gate--settle-timeout 5
  "The seconds the check waits for the state of the run to settle.
The wait is bounded on purpose: a state that does not settle is a
refusal of the check and not a comment, and a check that waits for ever
is a check that cannot fail.")

(defconst yeah-gate--output-timeout 5
  "The seconds the check waits for the words of the gate to come.
The words of the gate are a pipe, and the pipe is drained by Emacs after
the process is reaped: a reader that reads the buffer of the output at
the death of the process reads a tail that has not come yet.")

(defconst yeah-gate--output-quiet 0.2
  "The seconds the output of the gate must be quiet to be called settled.")

(defun yeah-gate--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline) (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-gate--await-dead (pid timeout)
  "Return non-nil when the process PID is gone, at most TIMEOUT seconds.
The process is gone when the state of it says so: a zombie is gone, it
has died already and waits to be reaped."
  (yeah-gate--await
   (lambda () (not (yeah-proc-alive-p (yeah-proc-state pid))))
   timeout))

(defun yeah-gate--kill (pid)
  "Kill the process PID with SIGKILL and return non-nil when the signal was sent."
  (and pid (integerp pid) (> pid 0)
       (condition-case nil
           (progn (signal-process pid 'KILL) t)
         (error nil))))

(defun yeah-gate--read-attempts (path)
  "Return the attempts of the run in PATH as a list of alists, or nil.
The file holds one line per attempt: `run=N pid=P' for an attempt that
started and `done=N' for an attempt that ended.

The attempt is an alist and not a plist on purpose: `assq' reads an
alist, and `assq' on a plist answers nil without a word -- a silent
miss that looks like a run that never started."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (let (attempts)
        (dolist (line (split-string (buffer-string) "\n" t))
          (cond
           ((string-match "^run=\\([0-9]+\\) pid=\\([0-9]+\\)$" line)
            (push (list (cons :run (string-to-number (match-string 1 line)))
                        (cons :pid (string-to-number (match-string 2 line))))
                  attempts))
           ((string-match "^done=\\([0-9]+\\)$" line)
            (push (list (cons :done (string-to-number (match-string 1 line))))
                  attempts))))
        (when attempts (nreverse attempts))))))

(defun yeah-gate--started-p (attempts)
  "Return non-nil when ATTEMPTS holds an attempt that started."
  (and attempts (cl-some (lambda (attempt) (assq :run attempt)) attempts)))

(defun yeah-gate--map-content (path)
  "Return the text of the map in PATH, or nil when the file is not there."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (buffer-string))))

(defun yeah-gate--map-complete-p (path)
  "Return non-nil when the map in PATH holds the marker of the end of the run."
  (let ((content (yeah-gate--map-content path)))
    (and content (string-match-p "map=complete" content))))

(defun yeah-gate--restarted-p (path)
  "Return non-nil when the attempts file in PATH shows the restart of the run.
The restart is the second start of the run: the first attempt was killed
and the gate started the run again."
  (>= (cl-count-if (lambda (attempt) (assq :run attempt))
                   (yeah-gate--read-attempts path))
      2))

(defun yeah-gate--settled-p (attempts-file map-file)
  "Return non-nil when the state of the run has settled.
The state has settled when the file of the attempts shows the restart and
the file of the map holds the marker of the end of the run.  The state is
written by the run, and the state is read by the check: the two are not
one process."
  (and (yeah-gate--restarted-p attempts-file)
       (yeah-gate--map-complete-p map-file)))

(defun yeah-gate--await-settled (attempts-file map-file timeout)
  "Wait until the state of the run has settled, at most TIMEOUT seconds.
Return the seconds the wait took.  A state that does not settle in that
time is not a state the check may judge: the check judges it as it is and
refuses it by its own assertion."
  (let ((started (float-time)))
    (yeah-gate--await (lambda () (yeah-gate--settled-p attempts-file map-file))
                       timeout)
    (- (float-time) started)))

(defun yeah-gate--output-size ()
  "Return the number of characters in the buffer of the output of the gate."
  (with-current-buffer (get-buffer-create " *yeah gate*")
    (buffer-size)))

(defun yeah-gate--output-text ()
  "Return the whole output of the gate, as it stands in its buffer."
  (with-current-buffer (get-buffer-create " *yeah gate*")
    (buffer-string)))

(defun yeah-gate--await-output (timeout quiet)
  "Wait until the output of the gate stops growing, at most TIMEOUT seconds.
Return the seconds the wait took.  The output of the gate is a pipe, and
Emacs drains the pipe after the process of the gate is reaped: a reader
that reads the buffer at the death of the process reads a tail that has
not come yet.  The output has settled when it did not grow for QUIET
seconds."
  (let ((started (float-time))
        (deadline (+ (float-time) timeout))
        (size (yeah-gate--output-size))
        (changed (float-time))
        (settled nil))
    (while (and (not settled) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (let ((now (yeah-gate--output-size)))
        (if (/= now size)
            (setq size now changed (float-time))
          (when (> (- (float-time) changed) quiet)
            (setq settled t)))))
    (- (float-time) started)))

(defun yeah-gate--map-reason ()
  "Return the line of the output of the gate that speaks about the map, or nil.
The gate says why the map of the project is not green when the step of the
map failed, and that line is the reason of the run: a refusal that loses
it names a subject that is not the real one.  The word is looked for in
the message of the line and not in the name of the program: the path of a
copy of the tree may hold the letters of the map and says nothing about
it."
  (let (found)
    (dolist (line (split-string (yeah-gate--output-text) "\n" t))
      (let ((message (and (string-match ":[ \t]" line)
                          (substring line (match-end 0)))))
        (when (and message (string-match-p "\\<map\\>" message))
          (setq found line))))
    found))

(defun yeah-gate--map-note (reason waited)
  "Return the tail of a refusal about the map of the run.
REASON is the line the gate said about the map (or nothing), and WAITED is
the seconds the check waited for the state of the run to settle.  The
refusal names what the gate said: the gate knows why its map is not
there, and a refusal that loses that word names a subject that is not the
real one."
  (concat (if reason (format "; the gate said: %s" reason) "")
          (format "; the state of the run did not settle in %.1f seconds" waited)))

(defun yeah-gate--await-all-dead (pids timeout)
  "Return non-nil when every process of PIDS is gone, at most TIMEOUT seconds.
The processes of the run get a moment to go: the pilot of the run removes
what the run left behind when it ends, and a helper of that removal is not
a leftover of the run -- it is the opposite of one."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (< (float-time) deadline)
                (cl-some (lambda (pid) (yeah-proc-alive-p (yeah-proc-state pid))) pids))
      (accept-process-output nil 0.05))
    (not (cl-some (lambda (pid) (yeah-proc-alive-p (yeah-proc-state pid))) pids))))

(defun yeah-gate--pids-of-run (gate-pid attempts)
  "Return the pids the check knows of the run.
GATE-PID is the pid of the gate and ATTEMPTS are the attempts of the run,
as the attempts file holds them.  The gate and every attempt of the run
are the processes the check waits for and the processes it kills."
  (cons gate-pid
        (cl-remove-if nil
                      (mapcar (lambda (attempt) (cdr (assq :pid attempt)))
                              attempts))))

(defun yeah-gate--processes-of-run (dir pids)
  "Return the pids of the processes of the run of this check.
DIR is the directory of the run and PIDS are the pids the check knows.

A process of the run is a process that holds the directory of the run in
its environment: every process the run starts inherits it.  A process
that only mentions the stand-in of the method is not a process of this
run, and a check that names it names a process that is not the run of
the check."
  (let (found)
    (dolist (entry (directory-files "/proc" t "\\`[0-9]+\\'" nil))
      (let* ((name (file-name-nondirectory entry))
             (environment
              (with-temp-buffer
                (ignore-errors
                  (insert-file-contents (expand-file-name "environ" entry)))
                (buffer-string))))
        (when (and (string-match-p "\\`[0-9]+\\'" name)
                   (string-match-p (regexp-quote (concat "YEAH_FAKE_METHOD_DIR=" dir))
                                   environment))
          (push (string-to-number name) found))))
    (dolist (pid pids)
      (unless (memq pid found)
        (push pid found)))
    found))

(defun yeah-gate--sleeps-p (path)
  "Return non-nil when the script PATH holds a command that sleeps.
A comment is not a command: the lines that begin with a sharp sign are
skipped, because the gate says in its own comments that it does not
poll."
  (with-temp-buffer
    (insert-file-contents path)
    (let ((found nil))
      (dolist (line (split-string (buffer-string) "\n" t))
        (unless (string-match-p "^[[:space:]]*#" line)
          (when (string-match-p "\\bsleep\\b" line)
            (setq found t))))
      found)))

(defun yeah-gate--dev-gate-branch (root)
  "Return the text of the gate branch of scripts/dev in ROOT, or nil.
The branch is the case of the subcommand `gate' and everything up to the
end of the case."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "scripts/dev" root))
    (goto-char (point-min))
    (when (re-search-forward "^  gate)$" nil t)
      (let ((start (point)))
        (if (re-search-forward "^  [^ ]" nil t)
            (buffer-substring start (match-beginning 0))
          (buffer-substring start (point-max)))))))

(defun yeah-gate--one-gate-p (root)
  "Return non-nil when the wrapper runs the one gate of the project.
The wrapper must hand the gate to scripts/gate and must not keep a
second run of the method of its own: two gates are two verdicts."
  (let ((branch (yeah-gate--dev-gate-branch root)))
    (and branch
         (string-match-p "/gate\"" branch)
         (not (string-match-p "mathc" branch)))))

(let* ((root (expand-file-name default-directory))
       (gate (expand-file-name "scripts/gate" root))
       (fake (expand-file-name "tests/support/yeah-fake-method.sh" root))
       (dir (make-temp-file "yeah-gate" t))
       (attempts-file (expand-file-name "attempts" dir))
       (map-file (expand-file-name "map" dir))
       (gate-process
        (let ((process-environment
               (cons (format "MATHC=%s" fake)
                     (cons (format "YEAH_FAKE_METHOD_DIR=%s" dir)
                           process-environment))))
          (make-process
           :name "yeah-gate"
           :command (list "bash" (expand-file-name "scripts/dev" root)
                          "gate" "--limit" "60" "--attempts" "3")
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer (get-buffer-create " *yeah gate*")
                       (goto-char (point-max))
                       (insert chunk))))))
       (gate-pid (and gate-process (process-id gate-process)))
       (attempts nil)
       (left nil)
       (killed 0))
  (unwind-protect
      (progn
        (unless (file-directory-p "/proc")
          (push "the check cannot measure a process without /proc"
                yeah-gate--failures))
        (when (null yeah-gate--failures)
          ;; the run starts and reports itself
          (setq attempts
                (yeah-gate--await
                 (lambda ()
                   (let ((lines (yeah-gate--read-attempts attempts-file)))
                     (when (yeah-gate--started-p lines) lines)))
                 30))
          (unless attempts
            (push "the run of the gate never started" yeah-gate--failures))
          (when attempts
            (setq killed (cdr (assq :pid (car attempts))))
            (unless (and (assq :run (car attempts))
                         killed (> killed 0))
              (push "the first attempt of the run did not report its run number and its pid"
                    yeah-gate--failures))))
          ;; the run is killed the way an unknown sender killed three runs
          ;; of the method on 2026-11-18
          (when (and killed (> killed 0))
            (unless (yeah-gate--kill killed)
              (push (format "the first attempt of the run could not be killed (pid %d)"
                            killed)
                    yeah-gate--failures)))
          ;; the gate answers
          (unless (yeah-gate--await-dead gate-pid 60)
            (push (format "the gate did not answer (pid %d)" gate-pid)
                  yeah-gate--failures))
          (let ((status (and gate-process (process-exit-status gate-process))))
            (unless (and status (= status 0))
              (push (format "the gate answered %s, the answer of a run that held is 0"
                            (or status "nothing"))
                    yeah-gate--failures)))
          ;; the words of the gate come before the check reads them: the
          ;; output of the gate is a pipe, and Emacs drains the pipe after
          ;; the process of the gate is reaped, so a reader that reads the
          ;; buffer at the death of the process reads a tail that has not
          ;; come yet.  The refusal of the check names the words of the
          ;; gate, and the diagnostic of the refusal shows them whole.
          (yeah-gate--await-output yeah-gate--output-timeout
                                   yeah-gate--output-quiet)
          ;; the state of the run settles before the check judges it: the
          ;; run writes the file of the attempts and the file of the map,
          ;; and the check reads them -- two processes, and the reader
          ;; waits for the writer.  The wait is bounded, and a state that
          ;; does not settle is a refusal and not a comment.
          (let* ((waited (yeah-gate--await-settled attempts-file map-file
                                                       yeah-gate--settle-timeout))
                 (attempts-now (yeah-gate--read-attempts attempts-file))
                 (content (yeah-gate--map-content map-file))
                 (reason (yeah-gate--map-reason)))
            ;; the killed run was started again
            (let ((runs (cl-count-if (lambda (attempt) (assq :run attempt))
                                     attempts-now)))
              (unless (= runs 2)
                (push (format "the killed run was not started again: the run was started %s time(s), the second start is the restart (the state of the run did not settle in %.1f seconds)"
                              runs waited)
                      yeah-gate--failures)))
            ;; the map reached the end
            (cond
             ((null content)
              (push (format "the map of the run was not written: the file %s is not there%s"
                            map-file
                            (yeah-gate--map-note reason waited))
                    yeah-gate--failures))
             ((not (string-match-p "map=complete" content))
              (push (format "the map of the run did not reach the end: the file %s holds %S, not the marker map=complete%s"
                            map-file (string-trim content)
                            (yeah-gate--map-note reason waited))
                    yeah-gate--failures))))
          ;; nothing of the run was left behind when the gate answered
          (setq left
                (cl-remove-if (lambda (pid) (yeah-gate--await-dead pid 0))
                              (yeah-gate--processes-of-run
                               dir
                               (yeah-gate--pids-of-run
                                gate-pid
                                (yeah-gate--read-attempts attempts-file)))))
          ;; the processes of the run get a moment to go: what the pilot of
          ;; the run removes when it ends is not a leftover of the run
          (yeah-gate--await-all-dead left 5)
          (setq left
                (cl-remove-if (lambda (pid) (yeah-gate--await-dead pid 0)) left))
          (when left
            (push (format "the run of the gate was left behind when the gate answered: the pids %S are still alive a moment later"
                          left)
                  yeah-gate--failures))
          ;; the run that was killed is gone.  It is measured by its pid:
          ;; the command line of the run is the command it waits with, and
          ;; it does not hold the name of the method.
          (when (and killed (> killed 0))
            (unless (yeah-gate--await-dead killed 10)
              (push (format "the killed run was still alive when the gate answered (pid %d)"
                            killed)
                    yeah-gate--failures)))
          ;; the gate waits, it does not poll
          (when (yeah-gate--sleeps-p gate)
            (push "the gate holds a command that sleeps: the gate must wait, not poll"
                  yeah-gate--failures))
          ;; the wrapper runs the one gate of the project
          (unless (yeah-gate--one-gate-p root)
            (push "the wrapper does not run the one gate of the project: it keeps a gate of its own"
                  yeah-gate--failures))))
    ;; the check leaves nothing behind: the processes of the run that it
    ;; found are killed, the gate is killed and the run that was killed is
    ;; killed
    (dolist (pid left)
      (yeah-gate--kill pid))
    (yeah-gate--kill gate-pid)
    (yeah-gate--kill killed)
    (ignore-errors (delete-directory dir t)))
  (dolist (failure yeah-gate--failures)
    (message "gate: %s" failure))
  (when yeah-gate--failures
    (with-current-buffer (get-buffer-create " *yeah gate*")
      (message "gate output:\n%s" (buffer-string))))
  (if yeah-gate--failures
      (kill-emacs 1)
    (kill-emacs 0))

;;; check-a-killed-gate-run-restarts-and-reaches-the-end.el ends here
