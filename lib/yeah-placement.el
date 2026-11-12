;;; yeah-placement.el --- attached, service and batch -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The kernel does not know where it runs.  It knows a session, a transport
;; and an answerer, and it is given those three things.  This module is the
;; three ways of giving them:
;;
;;   * ATTACHED — the run lives in the Emacs of the person.  The person
;;     answers the requests for permission, and the run must not block the
;;     editor while it works.
;;
;;   * SERVICE — the run lives in an Emacs of its own.  Nobody is at that
;;     keyboard, so the rules answer, and the bridge reaches back to the
;;     attached Emacs for the things only a person has.
;;
;;   * BATCH — the run lives in a process that has one task and then exits.
;;     Nobody is there at all: the headless allowlist is the whole of the
;;     policy, and the exit code says what happened.
;;
;; The three differ in the process, in who may answer, and in what happens
;; at the end.  They do not differ in what the run writes down: the
;; canonical projection of the events is the same for the same task, and
;; `yeah-placement-canonical-events' is what makes that checkable.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-product)
(require 'yeah-run)
(require 'yeah-session)

(defgroup yeah-placement nil
  "The placements of Yeah: attached, service and batch."
  :group 'yeah)

(defconst yeah-placement--placements '(attached service batch)
  "The placements a run may live in.")

(defconst yeah-placement--volatile-fields '(:timestamp :id)
  "Event fields a placement is allowed to differ in.
The identifiers and the timestamps are not part of what the run did.")

(defcustom yeah-placement-timeout 120
  "Seconds a placement waits for a run to reach a terminal state."
  :type 'number
  :group 'yeah-placement)

(defun yeah-placement-placements ()
  "Return the names of the placements."
  yeah-placement--placements)

(defun yeah-placement--fields (record)
  "Return the fields of RECORD without the pair that names its type."
  (let ((rest record)
        (fields nil))
    (while rest
      (when (eq (car rest) :type)
        (setq fields (cddr rest)))
      (setq rest (cddr rest)))
    fields))

(defun yeah-placement--canonical-fields (fields)
  "Return the FIELDS of a record without the volatile ones, sorted by name."
  (let ((pairs nil)
        (rest fields))
    (while rest
      (unless (memq (car rest) yeah-placement--volatile-fields)
        (push (cons (car rest) (cadr rest)) pairs))
      (setq rest (cddr rest)))
    (apply #'append
           (mapcar (lambda (pair) (list (car pair) (cdr pair)))
                   (sort pairs (lambda (left right)
                                 (string< (symbol-name (car left))
                                          (symbol-name (car right)))))))))

(defun yeah-placement-canonical-events (session)
  "Return the canonical projection of the events of SESSION.

The projection is the list of what happened, in order, without the
fields a placement is allowed to differ in.  Two placements that did the
same work produce the same list; that is the claim the placements are
checked against."
  (mapcar
   (lambda (record)
     (cons (plist-get record :type)
           (yeah-placement--canonical-fields (yeah-placement--fields record))))
   (seq-remove (lambda (record) (equal (plist-get record :type) "header"))
               (yeah-session-records session))))

(defun yeah-placement-session-id (placement)
  "Return a session id for the PLACEMENT of this run."
  (format "%s-%s"
          placement
          (format-time-string "%Y%m%d-%H%M%S" (current-time))))

(defun yeah-placement-session (root &optional placement id)
  "Open a session for the project ROOT and return it.

PLACEMENT names the session; ID names the session file when given."
  (let* ((root (file-truename (expand-file-name root)))
         (session-root (yeah-product-session-root root)))
    (yeah-session-open (or id (yeah-placement-session-id (or placement "run")))
                        session-root)))

(defun yeah-placement-allow-rules (names)
  "Return the rules that allow the tool NAMEs and nothing else.
This is the headless allowlist: the tools that are named may run, and
every other tool is refused, because there is nobody to ask."
  (mapcar (lambda (name) (yeah-perm-rule-make name "*" 'allow)) names))

(cl-defun yeah-placement-context (placement &key root id transport answerer
                                         rules budget deadline session)
  "Return a run context for PLACEMENT.

ROOT is the project the run works in.  TRANSPORT reaches the model.
ANSWERER answers the requests the rules do not decide: the attached
placement has a person, the other two have nobody.  RULES are the
permission rules of the run; when they are nil the headless allowlist
is empty, which refuses everything that was not allowed before."
  (unless (memq placement yeah-placement--placements)
    (signal 'user-error
            (list (format "yeah-placement-context: unknown placement %S"
                          placement))))
  (let* ((root (or root (yeah-product-project-root)))
         (session (or session (yeah-placement-session root placement id))))
    (yeah-run-context-create
     :placement placement
     :session session
     :transport transport
     :answerer answerer
     :rules rules
     :budget budget
     :deadline deadline)))

(defun yeah-placement-run (context prompt)
  "Start the run of CONTEXT with PROMPT and return CONTEXT."
  (yeah-run-context-start context prompt)
  context)

(defun yeah-placement-await (turn &optional timeout)
  "Wait for TURN to reach a terminal state and return that state."
  (let ((deadline (+ (float-time) (or timeout yeah-placement-timeout))))
    (while (and (not (yeah-turn-done turn)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (yeah-turn-state turn)))

(defun yeah-placement-exit-code (state)
  "Return the exit code that STATE of a run deserves.
Zero means the work was done; one means it failed; four means it was
cancelled; two means the placement was asked to do something it could
not do at all."
  (pcase state
    ('completed 0)
    ('failed 1)
    ('interrupted 4)
    ('refused 2)
    (_ 3)))

(defun yeah-placement--transport ()
  "Return the transport of this placement.
The scenario of a check names one; otherwise gptel is the transport."
  (or (and (fboundp 'yeah-scenario-transport) #'yeah-scenario-transport)
      (and (fboundp 'yeah-gptel-request) #'yeah-gptel-request)))

(cl-defun yeah-placement-attach (prompt &key root transport answerer rules
                                       budget deadline)
  "Run PROMPT in the attached placement: in this Emacs, with a person.

ANSWERER answers the requests for permission; when it is nil the
person is asked through the one-key approval of the product."
  (let* ((context (yeah-placement-context
                   'attached
                   :root root
                   :transport (or transport (yeah-placement--transport))
                   :answerer (or answerer #'yeah-product-human-answerer)
                   :rules rules
                   :budget budget
                   :deadline deadline)))
    (yeah-placement-run context prompt)))

(cl-defun yeah-placement-service (prompt &key root transport answerer rules
                                         budget deadline)
  "Run PROMPT in the service placement: in this Emacs, with nobody.

The service placement is this process: an Emacs of its own, started by
`yeah-placement-service-start'.  Nobody is at that keyboard, so the
rules answer, and a request the rules do not decide is refused."
  (let* ((context (yeah-placement-context
                   'service
                   :root root
                   :transport (or transport (yeah-placement--transport))
                   :answerer answerer
                   :rules rules
                   :budget budget
                   :deadline deadline)))
    (yeah-placement-run context prompt)))

(cl-defun yeah-placement-batch (prompt &key root transport answerer rules
                                       budget deadline)
  "Run PROMPT in the batch placement: in this Emacs, with nobody.

The batch placement is one task and one exit code.  Its policy is the
headless allowlist and nothing else."
  (let* ((context (yeah-placement-context
                   'batch
                   :root root
                   :transport (or transport (yeah-placement--transport))
                   :answerer answerer
                   :rules rules
                   :budget budget
                   :deadline deadline)))
    (yeah-placement-run context prompt)))

(defun yeah-placement-child-command (placement prompt root allow scenario)
  "Return the command that runs PLACEMENT in a child Emacs.

PROMPT is the task, ROOT is the project, ALLOW is the comma-separated
list of the tools the run may use and SCENARIO names an Elisp file the
child loads before the run.  The arguments travel on the command line:
a child process of Emacs inherits the environment of its parent, and
the environment of a person is not something a placement may change."
  (list (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS"))
                  (getenv "EMACS"))
             (executable-find "emacs")
             (expand-file-name "~/.nix-profile/bin/emacs"))
        "-Q" "--batch"
        "-L" (file-name-directory (or (locate-library "yeah-placement")
                                       "yeah-placement.el"))
        "-l" "yeah-placement"
        "--eval"
        (format "(yeah-placement-main %S %S %S %S %S %S)"
                placement
                prompt
                (expand-file-name root)
                (expand-file-name yeah-data-home)
                (or allow "")
                (if scenario (expand-file-name scenario) ""))))

(defun yeah-placement--start-child (name placement prompt root allow scenario)
  "Start a child Emacs running PLACEMENT and return the process.

NAME names the process, PROMPT is the task, ROOT is the project, ALLOW
is the comma-separated list of the tools the run may use and SCENARIO
names an Elisp file the child loads before the run."
  (let* ((root (expand-file-name (or root (yeah-product-project-root))))
         (buffer (generate-new-buffer (format "*yeah-%s*" name)))
         (process nil))
    (with-current-buffer buffer
      (setq process
            (make-process
             :name (format "yeah-%s" name)
             :buffer buffer
             :command (yeah-placement-child-command
                       placement prompt root allow scenario)
             :connection-type 'pipe
             :noquery t
             :filter (lambda (_process chunk)
                       (with-current-buffer buffer (insert chunk))))))
    process))

(cl-defun yeah-placement-service-start (prompt &key root allow scenario)
  "Start the service placement in a child Emacs and return the process.

PROMPT is the task, ROOT is the project and ALLOW is the comma-separated
list of the tools the run may use.  SCENARIO names an Elisp file that
the child loads before the run."
  (yeah-placement--start-child "service" "service" prompt root allow scenario))

(cl-defun yeah-placement-batch-start (prompt &key root allow scenario)
  "Start the batch placement in a child Emacs and return the process."
  (yeah-placement--start-child "batch" "batch" prompt root allow scenario))

(defun yeah-placement--allow-list (allow)
  "Return the tool names of the comma-separated ALLOW list."
  (let ((names nil))
    (dolist (part (split-string (or allow "") "," t))
      (unless (string-empty-p part)
        (push (string-trim part) names)))
    (nreverse names)))

(defun yeah-placement-main (placement prompt root data-home allow scenario)
  "Run PLACEMENT with PROMPT and exit with the code of the run.

ROOT is the project, DATA-HOME is where the journal is written, ALLOW
is the comma-separated list of the tools the run may use and SCENARIO
names an Elisp file that is loaded before the run."
  (let ((rules (yeah-placement-allow-rules (yeah-placement--allow-list allow)))
        (name (intern (string-trim (or placement "batch")))))
    (when (and data-home (not (string-empty-p data-home)))
      (setq yeah-data-home data-home))
    (when (and scenario (not (string-empty-p scenario))
               (file-exists-p scenario))
      (load (expand-file-name scenario) nil t))
    (let ((context (pcase name
                     ('attached
                      (yeah-placement-attach prompt :root root :rules rules))
                     ('service
                      (yeah-placement-service prompt :root root :rules rules))
                     ('batch
                      (yeah-placement-batch prompt :root root :rules rules))
                     (_
                      (message "yeah: unknown placement %S" placement)
                      (kill-emacs 2)))))
      (let ((turn (yeah-run-context-turn context)))
        (unless turn
          (kill-emacs 2))
        (kill-emacs (yeah-placement-exit-code (yeah-placement-await turn)))))))

(provide 'yeah-placement)
;;; yeah-placement.el ends here
