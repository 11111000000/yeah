;;; check-an-answer-carries-a-scope.el --- an answer carries a scope -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; An answer of a person is two things: the answer itself and the scope
;; it holds.  The answer says what the answer does -- once, session,
;; project, global or reject; the legacy name `always' is read as
;; `session' -- and the scope says where the rule that remembers it
;; lives: the rules of the run, the rules of the session, the file of the
;; project or the file of the user.
;;
;; This check measures that:
;;
;;   1. an answer carries a scope, and the scope is a canonical name;
;;   2. the rule that the answer writes carries the same scope;
;;   3. the second call of the same action in the same session does not
;;      ask again -- the scope did not break the remembering;
;;   4. the journal carries the scope of the decision;
;;   5. a decision that names a scope its answer does not name is refused
;;      by name, and the refusal says why;
;;   6. the dictionary of the answers and the dictionary of the scopes
;;      are written in one place each -- this check names a second
;;      writing when there is one;
;;   7. the projection of the interface tells the truth: an answer that
;;      allows is written as an allowance, not as a refusal.
;;
;; Exit codes: 0 — the answer carries a scope; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-approval)
(require 'yeah-acp)
(require 'yeah-events)
(require 'yeah-perm)
(require 'yeah-run)
(require 'yeah-service-ui)
(require 'yeah-session)
(require 'yeah-tools)

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(defun yeah-check--reply-kinds ()
  "Return the canonical kinds of answer of the kernel, or nil.
A kernel that has no such dictionary has no canonical answers, and this
check says so instead of dying."
  (and (fboundp 'yeah-approval-reply-kinds)
       (yeah-approval-reply-kinds)))

(defun yeah-check--scopes ()
  "Return the canonical scopes of the kernel, or nil.
A kernel that has no such dictionary has no canonical scopes, and this
check says so instead of dying."
  (and (fboundp 'yeah-perm-scopes)
       (yeah-perm-scopes)))

(defun yeah-check--name (x)
  "Return the plain name of the kind X, without a colon."
  (cond ((stringp x) x)
        ((symbolp x)
         (let ((name (symbol-name x)))
           (if (string-prefix-p ":" name) (substring name 1) name)))
        (t (format "%S" x))))

(defun yeah-check--writing-of-kinds-p (list kinds)
  "Return non-nil when LIST is a writing of the dictionary KINDS.
A writing is a quoted list that names the kinds of the dictionary: the
whole of it, or a part of it.  A symbol and a keyword of the same name
are the same kind."
  (and (proper-list-p list)
       (>= (length list) 2)
       (cl-every (lambda (element)
                   (and (symbolp element)
                        (member (yeah-check--name element)
                                (mapcar #'yeah-check--name kinds))))
                 list)))

(defun yeah-check--lists-of-kinds-in (node kinds found)
  "Return FOUND with the writings of KINDS in NODE added."
  (cond
   ((and (consp node) (eq (car node) 'quote))
    (if (yeah-check--writing-of-kinds-p (cadr node) kinds)
        (cons (cadr node) found)
      found))
   ((consp node)
    (let ((acc found))
      (dolist (element node)
        (setq acc (yeah-check--lists-of-kinds-in element kinds acc)))
      acc))
   ((vectorp node)
    (let ((acc found))
      (dotimes (index (length node))
        (setq acc (yeah-check--lists-of-kinds-in (aref node index) kinds acc)))
      acc))
   (t found)))

(defun yeah-check--lists-of-kinds (form kinds)
  "Return the writings of KINDS in FORM.
A quoted list is a writing of the dictionary; a list in a string is
prose and not a writing."
  (yeah-check--lists-of-kinds-in form kinds nil))

(defun yeah-check--declarations (root kinds)
  "Return the places of ROOT where the dictionary KINDS is written.
Each place is a list (FILE LINE); the file is named relative to ROOT.
Only the modules of `lib/' are read: the dictionary of the kernel is
written there."
  (let ((found nil))
    (dolist (file (file-expand-wildcards (expand-file-name "lib/*.el" root)))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (condition-case nil
            (while t
              (let ((start (point)))
                (let ((form (read (current-buffer))))
                  (when (yeah-check--lists-of-kinds form kinds)
                    (push (list (file-relative-name file root)
                                (line-number-at-pos start))
                          found)))))
          (end-of-file nil))))
    found))

(defun yeah-check--decisions (session)
  "Return every permission decision of SESSION."
  (seq-filter (lambda (record)
                (equal "permission-decision" (plist-get record :type)))
              (yeah-session-records session)))

(let ((failures nil))

  ;; --- 1. the answer carries a canonical scope --------------------------
  (yeah-perm-rules-reset-for-test)
  (let* ((request (yeah-approval-request "edit" "/tmp/file.el"))
         (once (yeah-approval-reply-decision request 'once))
         (always (yeah-approval-reply-decision request 'always))
         (reject (yeah-approval-reply-decision request 'reject)))
    (unless (eq :once (plist-get once :scope))
      (push (format "the answer once carries the scope %S, not :once"
                    (plist-get once :scope))
            failures))
    (unless (eq :global (plist-get always :scope))
      (push (format "the answer always carries the scope %S, not :global"
                    (plist-get always :scope))
            failures))
    (unless (null (plist-get reject :scope))
      (push "a refusal carries a scope" failures))
    (dolist (decision (list once always))
      (unless (memq (plist-get decision :scope) (yeah-check--scopes))
        (push (format "the scope %S of an answer is not a canonical scope"
                      (plist-get decision :scope))
              failures)))
    ;; --- 2. the rule the answer wrote carries the same scope ------------
    (let ((rule (car (yeah-perm-rules-list))))
      (unless rule
        (push "the answer always wrote no rule" failures))
      (unless (eq :global (plist-get rule :scope))
        (push (format "the rule of the answer carries the scope %S, not :global"
                      (plist-get rule :scope))
              failures))))
  (yeah-perm-rules-reset-for-test)

  ;; --- the run: the answer, its rule and the journal --------------------
  (yeah-tools-reset-for-test)
  (unwind-protect
      (let* ((session (yeah-session-open "scope" (make-temp-file "yeah-scope" t)))
             (context nil))
        ;; The run calls the tool `probe', and the tool must exist: the run
        ;; takes its tools from the registry of the moment.
        (yeah-tools-register
         (list :name "probe" :description "probe" :input nil
               :handler (lambda () "ok")))
        (setq context
              (yeah-run-context-create
               :placement 'attached
               :session session
               :rules nil
               ;; The run asks for no supervision: the subject of
               ;; this check is the scope of the decision, and a
               ;; supervised run ends through the `finish' tool.
               :max-nudges 0
               :transport
               (lambda (_prompt callback)
                 (funcall callback
                          (list 'tool-call
                                (list (list :name "probe") nil
                                      (lambda (_value)
                                        (funcall callback "done"))))))
               :answerer
               (lambda (_request)
                 (list :effect :allow :reply :always))))
        (let ((decision (progn (yeah-run-context-start context "the task")
                                (car (yeah-check--decisions session)))))
          ;; the journal of the run names the scope of the run
          (unless decision
            (push "the run wrote no permission decision" failures))
          (unless (equal "run" (plist-get decision :scope))
            (push (format "the answer of the run carries the scope %S, not \"run\""
                          (plist-get decision :scope))
                  failures))
          ;; the rule of the run carries the same scope
          (let ((rule (car (yeah-run-context-rules context))))
            (unless rule
              (push "the answer of the run wrote no rule into the run" failures))
            (unless (eq :run (plist-get rule :scope))
              (push (format "the rule of the run carries the scope %S, not :run"
                            (plist-get rule :scope))
                    failures)))))
    (yeah-tools-reset-for-test))

  ;; --- 5. a scope without a carrier is refused by name ------------------
  (let* ((context (yeah-run-context-create
                   :placement 'attached
                   :rules nil
                   :answerer (lambda (_request)
                               (list :effect :allow :reply :always
                                     :scope :project))))
         (decision (funcall (yeah-run-context-policy context)
                            (list :action "write" :resource "/tmp/x.el"))))
    (unless (eq :deny (plist-get decision :effect))
      (push "the scope without a carrier was not refused" failures))
    (unless (string-match-p "project" (or (plist-get decision :reason) ""))
      (push (format "the refusal does not name the scope: %S"
                    (plist-get decision :reason))
            failures))
    (unless (string-match-p "carrier" (or (plist-get decision :reason) ""))
      (push (format "the refusal does not say why: %S"
                    (plist-get decision :reason))
            failures)))

  ;; --- the session: the answer, its rule and the second call ------------
  (let* ((directory (make-temp-file "yeah-scope-acp" t))
         (yeah-data-home directory)
         (yeah-input-directory (expand-file-name "pending/" directory))
         (yeah-acp--transport nil)
         (yeah-acp--answerer nil)
         (yeah-acp--output-function nil))
    (unwind-protect
        (progn
          (yeah-acp--reset-for-test)
          (yeah-perm-rules-reset-for-test)
          (let* ((session-id
                  (plist-get (yeah-acp-session-new
                               (list :cwd (file-truename yeah-data-home)
                                     :mcpServers nil))
                              :sessionId))
                 (asked nil)
                 (answerer (yeah-acp--client-answerer
                            session-id (lambda (text) (push text asked))))
                 (request (list :action "write" :resource "/tmp/x.el"
                                 :args nil))
                 (deferral (funcall answerer request))
                 (id (plist-get deferral :defer))
                 (question (gethash id yeah-acp--pending-permissions)))
            (unless id
              (push "the session did not ask the client" failures))
            (unless asked
              (push "the client was not asked" failures))
            ;; the answer of the client is `allow-always'
            (let ((scoped (yeah-acp--remember-decision
                           question
                           (yeah-acp--permission-decision
                            (list :result
                                  (list :outcome
                                        (list :optionId "allow-always")))))))
              ;; --- 1. the answer of the session carries its scope -------
              (unless (eq :session (plist-get scoped :scope))
                (push (format "the answer of the session carries the scope %S, not :session"
                              (plist-get scoped :scope))
                      failures))
              ;; --- 2. the rule of the session carries the same scope -----
              (let ((rule (car (plist-get (yeah-acp--session-state session-id)
                                          :rules))))
                (unless rule
                  (push "the answer of the session wrote no rule" failures))
                (unless (eq :session (plist-get rule :scope))
                  (push (format "the rule of the session carries the scope %S, not :session"
                                (plist-get rule :scope))
                        failures))))
            ;; --- 3. the second call of the same action does not ask ------
            (let ((second (funcall answerer request)))
              (unless (eq :allow (plist-get second :effect))
                (push "the second call of the same action did not answer itself"
                      failures))
              (unless (null (plist-get second :defer))
                (push "the second call of the same action asked the client again"
                      failures))))
          (yeah-acp--reset-for-test))
      (yeah-acp--reset-for-test)
      (ignore-errors (delete-directory directory t t))))

  ;; --- 4. the journal carries the scope of the decision -----------------
  (yeah-tools-reset-for-test)
  (unwind-protect
      (let* ((session (yeah-session-open "scope" (make-temp-file "yeah-scope-j" t)))
             (context nil))
        (yeah-tools-register
         (list :name "probe" :description "probe" :input nil
               :handler (lambda () "ok")))
        (setq context
              (yeah-run-context-create
               :placement 'attached
               :session session
               :rules nil
               :max-nudges 0
               :transport
               (lambda (_prompt callback)
                 (funcall callback
                          (list 'tool-call
                                (list (list :name "probe") nil
                                      (lambda (_value)
                                        (funcall callback "done"))))))
               :answerer
               (lambda (_request)
                 (list :effect :allow :reply :always))))
        (yeah-run-context-start context "the task")
        (let* ((records (yeah-check--decisions session))
               (record (car records)))
          (unless record
            (push "the journal holds no permission decision" failures))
          (unless (equal "run" (plist-get record :scope))
            (push (format "the journal carries the scope %S, not \"run\""
                          (plist-get record :scope))
                  failures))))
    (yeah-tools-reset-for-test))

  ;; --- 6. the dictionaries are written in one place each ----------------
  (let* ((root (yeah-check--root))
         (replies (yeah-check--declarations root (yeah-check--reply-kinds)))
         (scopes (yeah-check--declarations root (yeah-check--scopes))))
    (unless (= 1 (length replies))
      (push (format "the answers are written in %d place(s): %S"
                    (length replies) replies)
            failures))
    (unless (= 1 (length scopes))
      (push (format "the scopes are written in %d place(s): %S"
                    (length scopes) scopes)
            failures)))

  ;; --- 7. the projection of the interface tells the truth ----------------
  (let* ((buffer (get-buffer-create "*Yeah scope projection*"))
         (params (list :toolCall (list :toolCallId "call-1"
                                        :title "write on /tmp/x.el"
                                        :rawInput '("a"))))
         (answered nil))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq yeah-service-ui--records nil
                  yeah-service-ui--event-id 0
                  yeah-service-ui-permission-prompter
                  (lambda (_title _raw-input) "allow-always")))
          (yeah-service-ui--handle-request
           buffer "session/request_permission" params
           (lambda (result) (setq answered result)))
          (let ((deadline (+ (float-time) 5)))
            (while (and (null answered) (< (float-time) deadline))
              (accept-process-output nil 0.05)))
          (with-current-buffer buffer
            (let ((record
                   (seq-find (lambda (candidate)
                               (equal "permission-decision"
                                      (plist-get candidate :type)))
                             yeah-service-ui--records)))
              (unless record
                (push "the interface wrote no permission decision" failures))
              (unless (equal "allow" (plist-get record :effect))
                (push (format "the interface wrote the effect %S, not \"allow\""
                              (plist-get record :effect))
                      failures))
              (unless (equal "session" (plist-get record :scope))
                (push (format "the interface wrote the scope %S, not \"session\""
                              (plist-get record :scope))
                      failures)))))
      (when (buffer-live-p buffer) (kill-buffer buffer))))

  (dolist (failure failures)
    (message "scope: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-an-answer-carries-a-scope.el ends here
