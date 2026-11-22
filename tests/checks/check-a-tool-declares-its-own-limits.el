;;; check-a-tool-declares-its-own-limits.el --- a tool declares its own limits -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A tool says how much it may do at once.  The fields are `:timeout' — the
;; upper bound of the work one call of the tool may start, in seconds — and
;; `:output-limit' — the upper bound of the output one call of the tool may
;; hand to the model, in characters.
;;
;; The defect this check hunts: the declaration is a word in the
;; specification and nothing else.  A registry that takes `:output-limit' and
;; drops it, a turn that builds a call without it and a scheduler that does
;; not read the timeout all look the same from the outside: the model reads
;; a megabyte of output, and a call that runs for an hour is still waited
;; for.
;;
;; The check runs REAL TURNS with a fake model, so that the whole path is
;; covered: the registry holds the declaration, the turn builds the call out
;; of the registry, and the scheduler decides what runs together.  A check
;; that drove the scheduler alone would pass even when the turn dropped the
;; declaration on the way.
;;
;; Eight things are proved:
;;
;;   1. a tool that declares an output limit hands the model no more than
;;      that many characters, and the whole text of the output lies in a
;;      private artifact;
;;   2. a tool that declares no limit works by the global limit, which is
;;      `yeah-result-output-limit' (32768);
;;   3. the global limit is a ceiling: when the global limit is below the
;;      declared one, the global limit is the one that applies, and a
;;      declaration never raises the global limit;
;;   4. a call that crossed the timeout of its tool is closed by a failure
;;      that names the bound, and the model reads that failure;
;;   5. the registration refuses the timeout of a synchronous tool by name:
;;      the kernel cannot interrupt a handler that does not take a
;;      continuation, and a promise it cannot keep is refused there;
;;   6. the registration refuses a limit that is not a positive integer, by
;;      name;
;;   7. a call that asks for a duration longer than the timeout of the tool
;;      is refused by name: the model does not lift the limit of the
;;      registry by asking for more work;
;;   8. the declaration travels from the registry to the call of the
;;      scheduler.
;;
;; The probes wait on a timer, which is what a tool that waits does.  The
;; event loop is pumped in small steps, because a timer that is started
;; inside another timer is only reached by a later turn of the loop.
;;
;; Exit codes: 0 -- the tool declares its own limits and the limits hold;
;; 1 -- they do not.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-result)
(require 'yeah-scheduler)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defconst yeah-check--global-limit yeah-result-output-limit
  "The global limit of the output of one tool result, in characters.
The check binds the variable itself when it needs a smaller ceiling, so
the value here is the default of the kernel.")

(defun yeah-check--pump (&optional steps)
  "Let the event loop run for a while, in small steps.
A timer that is started inside another timer is only reached by a later
turn of the loop, so the loop is pumped rather than slept through.
STEPS is the number of the steps, and every step lasts a twentieth of a
second."
  (dotimes (_ (or steps 4)) (sleep-for 0.05)))

(defun yeah-check--output-probe (name limit text)
  "Return the specification of a tool named NAME that hands TEXT to the model.
LIMIT is the output limit the tool declares, or nil when it declares none.
The field is left out of the specification when there is none: a
declaration that is not a positive integer is refused by the registry."
  (let ((spec (list :name name
                    :description "A probe of the limit of the output of a tool."
                    :input nil
                    :risk "read"
                    :handler (lambda () text))))
    (if limit
        (plist-put spec :output-limit limit)
      spec)))

(defun yeah-check--timeout-probe (name timeout)
  "Return the specification of a tool named NAME that never answers.
The tool declares the timeout TIMEOUT, and its handler waits for a
continuation that never comes: the kernel has to close the call."
  (list :name name
        :description "A probe of the timeout of a tool."
        :input nil
        :risk "read"
        :async t
        :timeout timeout
        :handler (lambda (_args _done) nil)))

(defun yeah-check--run-turn (name args &optional steps)
  "Run one turn whose model asks for the tool NAME with ARGS.
Return the text the model read when the tool had answered, or nil when
the model read nothing.  STEPS is the number of the steps of the event
loop that the turn is given after the answer."
  (let* ((root (make-temp-file "yeah-tool-limits" t))
         (session (yeah-session-open "tool-limits" root))
         (seen nil))
    (unwind-protect
        (progn
          (yeah-perm-rules-add (yeah-perm-rule-make name "*" 'allow))
          (yeah-turn-run
           session "probe the limits of the tool"
           (lambda (_prompt callback)
             (funcall callback
                      (cons 'tool-call
                            (list (list (list :name name) args
                                         (lambda (value)
                                           ;; the model answers with a
                                           ;; text when the tool is done,
                                           ;; and the run ends there
                                           (setq seen value)
                                           (funcall callback "the probe is done")))))))
           ;; The run is not supervised: the subject of this check is the
           ;; limits of the tool and not the path of the completion.
           nil 60000 0)
          (yeah-check--pump steps)
          seen)
      (ignore-errors (delete-directory root t t)))))

(defun yeah-check--output-of (model-text)
  "Return the part of MODEL-TEXT that is the output of the tool.
The output is the first line of the text: the lines that follow it are
the marks the harness adds to the text of the model."
  (and model-text (car (split-string model-text "\n"))))

(defun yeah-check--artifacts-of (model-text)
  "Return the paths of the artifacts the MODEL-TEXT names."
  (when (and model-text (string-match "\n\\[Full output: \\(.*\\)\\]$" model-text))
    (split-string (match-string 1 model-text) ", ")))

(defun yeah-check--private-p (path)
  "Return non-nil when PATH is a file that nobody else may read."
  (and (file-exists-p path)
       (zerop (logand (file-modes path) #o77))))

(defun yeah-check--file-text (path)
  "Return the text of the file PATH, or nil when it cannot be read."
  (when (file-exists-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (buffer-string))))

(let ((failures nil))

  ;; --- 1. the declared limit bounds the output of the tool ----------------
  ;; The model reads no more than the limit the tool declares, and the
  ;; whole text of the output lies in a private artifact.
  (let* ((text (make-string 500 ?x))
         (seen (progn
                 (yeah-tools-register
                  (yeah-check--output-probe "probe-limit" 100 text))
                 (yeah-check--run-turn "probe-limit" nil)))
         (output (yeah-check--output-of seen))
         (artifacts (yeah-check--artifacts-of seen)))
    (unless (and output (= (length output) 100))
      (push (format "the model read %d characters of an output that declares the limit of 100"
                    (length output))
            failures))
    (unless artifacts
      (push "the whole output of the tool lies in no artifact" failures))
    (dolist (path artifacts)
      (unless (equal text (yeah-check--file-text path))
        (push (format "the artifact %S does not hold the whole output" path)
              failures))
      (unless (yeah-check--private-p path)
        (push (format "the artifact %S is not private" path) failures))))

  ;; --- 2. a tool that declares no limit works by the global limit --------
  (let* ((text (make-string (+ yeah-check--global-limit 100) ?y))
         (seen (progn
                 (yeah-tools-register
                  (yeah-check--output-probe "probe-global" nil text))
                 (yeah-check--run-turn "probe-global" nil)))
         (output (yeah-check--output-of seen)))
    (unless (and output (= (length output) yeah-check--global-limit))
      (push (format "the model read %d characters of an output that declares no limit, and the global limit is %d"
                    (length output) yeah-check--global-limit)
            failures)))

  ;; --- 3. the global limit is a ceiling -----------------------------------
  ;; The tool declares 100 characters and the global limit is 50: the
  ;; global limit is the one that applies.  A declaration never raises the
  ;; global limit, and the global limit never lets a tool read more than
  ;; it declared.
  (let* ((text (make-string 500 ?w))
         (seen (let ((yeah-result-output-limit 50))
                 (yeah-tools-register
                  (yeah-check--output-probe "probe-ceiling" 100 text))
                 (yeah-check--run-turn "probe-ceiling" nil)))
         (output (yeah-check--output-of seen)))
    (unless (and output (= (length output) 50))
      (push (format "the model read %d characters under a global limit of 50, and the tool declares 100"
                    (length output))
            failures)))

  ;; --- 4. a call that crossed its timeout is closed by a failure ----------
  ;; The probe never answers.  The kernel stops waiting for it at the bound
  ;; the tool declared, closes the call with a failure that names the
  ;; bound, and the model reads that failure.
  (let ((seen (progn
                (yeah-tools-register
                 (yeah-check--timeout-probe "probe-timeout" 1))
                ;; the probe never answers: the loop is pumped long enough
                ;; for the timer of the bound to fire
                (yeah-check--run-turn "probe-timeout" nil 60))))
    (unless (and seen
                 (string-match-p "probe-timeout" seen)
                 (string-match-p "timeout of 1 seconds" seen))
      (push (format "the call that crossed its timeout was not closed by a failure that names the bound: %S"
                    seen)
            failures)))

  ;; --- 5. the registration refuses the timeout of a synchronous tool ------
  ;; The kernel cannot interrupt a handler that does not take a
  ;; continuation, so a promise it cannot keep is refused at the
  ;; registration, and the refusal names the tool.
  (let ((refusal nil))
    (condition-case err
        (yeah-tools-register
         (list :name "probe-sync-timeout" :description "probe" :input nil
               :timeout 5 :handler (lambda () "never")))
      (user-error (setq refusal err)))
    (unless refusal
      (push "the registry took the timeout of a synchronous tool" failures))
    (when refusal
      (unless (string-match-p "probe-sync-timeout"
                              (error-message-string refusal))
        (push (format "the refusal of the timeout of a synchronous tool named no tool: %s"
                      (error-message-string refusal))
              failures))))

  ;; --- 6. the registration refuses a limit that is not a positive integer -
  (dolist (bad (list "120" 1.5 0 -1))
    (let ((refusal nil))
      (condition-case err
          (yeah-tools-register
           (list :name "probe-bad-timeout" :description "probe" :input nil
                 :async t :timeout bad :handler (lambda (_args _done) nil)))
        (user-error (setq refusal err)))
      (unless refusal
        (push (format "the registry took the timeout %S" bad) failures))
      (when refusal
        (unless (string-match-p "probe-bad-timeout"
                                (error-message-string refusal))
          (push (format "the refusal of the timeout %S named no tool: %s"
                        bad (error-message-string refusal))
                failures))))
    (let ((refusal nil))
      (condition-case err
          (yeah-tools-register
           (list :name "probe-bad-output" :description "probe" :input nil
                 :output-limit bad :handler (lambda () "never")))
        (user-error (setq refusal err)))
      (unless refusal
        (push (format "the registry took the output limit %S" bad) failures))
      (when refusal
        (unless (string-match-p "probe-bad-output"
                                (error-message-string refusal))
          (push (format "the refusal of the output limit %S named no tool: %s"
                        bad (error-message-string refusal))
                failures)))))

  ;; --- 7. a duration longer than the timeout of the tool is refused ------
  ;; The model asks `bash' for 300 seconds, and `bash' declares a timeout
  ;; of 120 seconds.  The refusal names the tool and the bound, and the
  ;; model reads it.
  (let ((seen (yeah-check--run-turn "bash" (list "printf hello" 300))))
    (unless (and seen
                 (string-match-p "bash" seen)
                 (string-match-p "timeout of 120 seconds" seen))
      (push (format "the call that asked for more work than the tool declares was not refused: %S"
                    seen)
            failures)))

  ;; --- 8. the declaration travels from the registry to the call ----------
  ;; The call the turn builds out of the registry carries the limits the
  ;; registry holds.  The proofs above run through that call: a turn that
  ;; dropped the declaration would let the model read more than the tool
  ;; declared.
  (let* ((limit-call (yeah-turn--call-spec
                      nil (list :name "probe-limit" :args nil
                                 :spec (yeah-tools-get "probe-limit"))))
         (timeout-call (yeah-turn--call-spec
                       nil (list :name "probe-timeout" :args nil
                                  :spec (yeah-tools-get "probe-timeout")))))
    (unless (equal (plist-get limit-call :output-limit) 100)
      (push (format "the call of the scheduler carries the output limit %S"
                    (plist-get limit-call :output-limit))
            failures))
    (unless (equal (plist-get timeout-call :timeout) 1)
      (push (format "the call of the scheduler carries the timeout %S"
                    (plist-get timeout-call :timeout))
            failures)))

  (dolist (failure failures)
    (message "tool limits: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-tool-declares-its-own-limits.el ends here
