;;; check-the-question-offers-the-scope.el --- the question offers the scope -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The question of a permission offers the scopes of the answers: `once',
;; `session', `project' and `global', and the refusal.  This check
;; measures that:
;;
;;   1. the dictionary of the answers is the four scopes and the refusal,
;;      and the legacy `always' is read as the answer `session' -- in
;;      Elisp and on the wire;
;;   2. the shared view offers the four scopes and the refusal, and the
;;      answer that comes out of it carries the reply and the scope that
;;      reply named;
;;   3. the question over the wire carries the four options and the
;;      refusal, and the answer that comes back over the wire carries the
;;      scope;
;;   4. the scope decides where the rule lives: `once' writes no rule,
;;      `session' writes into the carrier of the path that asks (the
;;      rules of the run in the attached path, the rules of the session in
;;      the ACP path), `project' writes into the file of the project and
;;      `global' writes into the file of the user;
;;   5. the legacy `allow-always' still lands in the carrier of the path;
;;   6. the schema of the wire declares the method of the question, with
;;      the params the kernel sends and the result it reads;
;;   7. a scope that the path cannot hold is refused by name.
;;
;; The moves are real: the view is opened and answered, a run runs, and
;; the question and the answer travel over the wire as the text of the
;; protocol.  The check works in temporary directories and binds the
;; configuration of the user and the root of the project to them: it
;; writes nothing into the configuration of the person and nothing into
;; the project of the person.
;;
;; Exit codes: 0 — the question offers the scope; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'yeah-approval)
(require 'yeah-approval-ui)
(require 'yeah-acp)
(require 'yeah-perm)
(require 'yeah-run)
(require 'yeah-session)
(require 'yeah-tools)

(defun yeah-check--temp-directory (prefix)
  "Return a fresh temporary directory whose name starts with PREFIX."
  (let* ((file (make-temp-file prefix))
         (directory (file-name-concat (file-name-directory file)
                                      (file-name-nondirectory file))))
    (delete-file file)
    (make-directory directory t)
    directory))

(defun yeah-check--rules-of-file (file)
  "Return the rules that FILE holds, or nil when there is no file."
  (when (file-exists-p file)
    (yeah-perm--read-rules-file file)))

(defun yeah-check--rule-of (rules action resource)
  "Return the rule of RULES for ACTION on RESOURCE, or nil."
  (seq-find (lambda (rule)
              (and (equal action (plist-get rule :action))
                   (equal resource (plist-get rule :resource))))
            rules))

(defun yeah-check--scope-of-rule (rules)
  "Return the scopes the rules of RULES carry."
  (mapcar (lambda (rule) (plist-get rule :scope)) rules))

(defvar yeah-check--token nil
  "The token of the question of the view that is open now.")

(defun yeah-check--ask-the-view (request reply)
  "Ask the person about REQUEST in the shared view and answer with REPLY.
Return the decision that the view built.

The person answers in the buffer of the view, as the person does: the
answer is given by the command of the view, and the decision is the one
the view builds.  A view that takes no answer is a failure of the check
and not a check that waits for an hour."
  (let ((token (list t)))
    (setq yeah-check--token token)
    (run-at-time 0.05 nil
                  (lambda ()
                    (condition-case err
                        (with-current-buffer "*Yeah Approval*"
                          (yeah-approval--decide reply))
                      (error
                       (when (eq yeah-check--token token)
                         (message "scope: the view took no answer %s: %s"
                                  reply (error-message-string err))
                         (kill-emacs 1))))))
    (run-at-time 10 nil
                  (lambda ()
                    (when (eq yeah-check--token token)
                      (message "scope: the view took no answer %s" reply)
                      (kill-emacs 1))))
    (let ((decision (yeah-approval-answer request)))
      (setq yeah-check--token nil)
      decision)))

(defun yeah-check--question-of (text)
  "Return the message of the wire that TEXT carries."
  (json-parse-string text :object-type 'plist :array-type 'list))

(defun yeah-check--answer-text (id option)
  "Return the text of the wire answer of the question ID with OPTION."
  (json-serialize
   (list :jsonrpc "2.0" :id id
         :result (list :outcome (list :outcome "selected" :optionId option)))))

(let ((failures nil)
      (project (yeah-check--temp-directory "yeah-c3-project"))
      (config (yeah-check--temp-directory "yeah-c3-config"))
      (data (yeah-check--temp-directory "yeah-c3-data")))

  (unwind-protect
      (progn
        (let ((yeah-perm-config-home config)
              (yeah-data-home data)
              (yeah-input-directory (expand-file-name "pending/" data)))
          (cl-letf (((symbol-function 'yeah-product-project-root)
                      (lambda () project)))

            (let ((request (list :action "edit" :resource "/tmp/c3-file.el"
                                  :args nil)))

              ;; --- 1. the dictionary of the answers -----------------------
              (let ((answers (yeah-approval-reply-kinds)))
                (unless (equal answers '(:once :session :project :global :reject))
                  (push (format "the dictionary of the answers is %S, not the four scopes and the refusal"
                                answers)
                        failures))
                ;; the scope of the run is not an answer: the person is
                ;; never asked to make a rule that dies with the run.
                (when (memq :run answers)
                  (push "the scope of the run is offered as an answer" failures))
                (unless (equal (seq-remove (lambda (scope) (eq scope :run))
                                           (yeah-perm-scopes))
                               '(:once :session :project :global))
                  (push "the scopes of the answers are not the scopes of the kernel"
                        failures)))
              ;; the legacy answer `always' is the answer `session'
              (unless (eq (yeah-approval-reply-canonical 'always) :session)
                (push "the legacy answer always is not the answer session"
                      failures))
              (unless (eq (yeah-approval-reply-canonical :always) :session)
                (push "the legacy answer :always is not the answer session"
                      failures))
              (let ((reply (yeah-approval-reply-from-wire "allow-always")))
                (unless (and reply
                             (eq (yeah-approval-reply-canonical reply) :session))
                  (push "the legacy wire answer allow-always is not the answer session"
                        failures)))
              ;; an answer that is not an answer is refused
              (unless (condition-case nil
                          (progn
                            (yeah-approval-reply-decision request 'perhaps)
                            nil)
                        (user-error t))
                (push "an answer that is not an answer was accepted" failures))

              ;; --- 2. the view offers the four scopes and the refusal ----
              (let ((buffer (yeah-approval-open request #'ignore)))
                (unwind-protect
                    (with-current-buffer buffer
                      (let ((text (buffer-string)))
                        (dolist (label '("Allow once" "Allow for this session"
                                         "Allow for this project" "Allow always"
                                         "Reject"))
                          (unless (string-match-p (regexp-quote label) text)
                            (push (format "the view does not offer %s" label)
                                  failures)))))
                  (when (buffer-live-p buffer) (kill-buffer buffer))))
              (dolist (key '("o" "s" "p" "a" "r"))
                (unless (lookup-key yeah-approval-mode-map (kbd key))
                  (push (format "the view binds no key %s" key) failures)))
              ;; the answer that comes out of the view carries the reply,
              ;; and the scope that reply named reaches the decision of the
              ;; path that asks.  The plain path has no session of its own:
              ;; its carrier is the file of the user, and the scope of its
              ;; answer `session' is the scope of that carrier.
              (yeah-perm-rules-reset-for-test)
              (dolist (answer '(:once :session :project :global :reject))
                (let ((decision (yeah-check--ask-the-view request answer)))
                  (unless (eq (plist-get decision :effect)
                              (if (eq answer :reject) :deny :allow))
                    (push (format "the answer %s of the view decided nothing" answer)
                          failures))
                  (unless (eq (plist-get decision :reply) answer)
                    (push (format "the decision of the view carries the reply %S, not %s"
                                  (plist-get decision :reply) answer)
                          failures))
                  ;; the path that asks resolves the scope of the reply
                  (let* ((answerer (yeah-approval-person-answerer
                                    (lambda (_request) answer)))
                         (scoped (funcall answerer request))
                         (expected (pcase answer
                                    (:once :once)
                                    (:session :global)
                                    (:project :project)
                                    (:global :global)
                                    (_ nil))))
                    (unless (eq (plist-get scoped :scope) expected)
                      (push (format "the answer %s of the view carries the scope %S, not %S"
                                    answer (plist-get scoped :scope) expected)
                            failures)))))
              (yeah-perm-rules-reset-for-test)

              ;; --- 3. the question over the wire ------------------------
              (let* ((question-text nil)
                     (session-id
                      (plist-get (yeah-acp-session-new
                                  (list :cwd (file-truename data)
                                        :mcpServers nil))
                                 :sessionId))
                     (answerer (yeah-acp--client-answerer
                                session-id
                                (lambda (text) (setq question-text text))))
                     (deferral (funcall answerer request)))
                (unless (plist-get deferral :defer)
                  (push "the wire did not ask the client" failures))
                (unless question-text
                  (push "the wire sent no question" failures))
                (let* ((question (and question-text
                                      (yeah-check--question-of question-text)))
                       (params (and question (plist-get question :params)))
                       (tool-call (and params (plist-get params :toolCall)))
                       (options (and params (plist-get params :options))))
                  (unless (and question
                               (equal (plist-get question :method)
                                      "session/request_permission"))
                    (push "the wire did not ask with session/request_permission"
                          failures))
                  (unless (and params (plist-get params :sessionId))
                    (push "the question names no session" failures))
                  (unless (and tool-call
                               (plist-get tool-call :toolCallId)
                               (plist-get tool-call :title))
                    (push "the question names no tool call" failures))
                  ;; the four scopes and the refusal
                  (let ((ids (and options
                                  (mapcar (lambda (option)
                                            (plist-get option :optionId))
                                          options))))
                    (unless (equal ids '("allow-once" "allow-session"
                                         "allow-project" "allow-global"
                                         "reject-once"))
                      (push (format "the options of the question are %S, not the four scopes and the refusal"
                                    ids)
                            failures))
                    (dolist (option options)
                      (unless (plist-get option :name)
                        (push "an option of the question names nothing" failures))
                      (unless (member (plist-get option :kind)
                                      '("allow_once" "allow_always" "reject_once"))
                        (push (format "the kind of an option is %S, and it is not the vocabulary of ACP"
                                      (plist-get option :kind))
                              failures))))
                  ;; --- 4. the scope decides where the rule lives ---------
                  ;; the answer of the session lands in the carrier of the
                  ;; path that asks: the session itself.
                  (let ((answer (yeah-check--answer-text
                                 (plist-get deferral :defer) "allow-session")))
                    (yeah-acp-handle-message answer))
                  (let ((rules (plist-get (yeah-acp--session-state session-id)
                                          :rules)))
                    (unless (seq-find (lambda (rule)
                                        (eq :session (plist-get rule :scope)))
                                      rules)
                      (push "the answer of the session wrote no rule of the session"
                            failures))
                    (unless (null (seq-filter (lambda (rule)
                                                 (eq :session (plist-get rule :scope)))
                                               (yeah-perm-rules-list)))
                      (push "the rule of the session landed in the rules of the process"
                            failures))
                    (unless (null (seq-filter (lambda (rule)
                                                 (eq :session (plist-get rule :scope)))
                                               (yeah-check--rules-of-file
                                                (yeah-perm--user-rules-file))))
                      (push "the rule of the session landed in the file of the user"
                            failures)))
                  ;; the scope of the answer that came back over the wire
                  (let* ((message (yeah-check--question-of
                                   (yeah-check--answer-text
                                    (plist-get deferral :defer) "allow-project")))
                         (decision (yeah-acp--permission-decision message))
                         (scoped (yeah-approval-scope-decision decision 'session)))
                    (unless (eq (plist-get scoped :scope) :project)
                      (push (format "the answer that came back over the wire carries the scope %S, not :project"
                                    (plist-get scoped :scope))
                            failures)))
                  ;; --- 5. the legacy `allow-always' still lands in the
                  ;; carrier of the path ---------------------------------
                  (let ((answer (yeah-check--answer-text
                                 (plist-get deferral :defer) "allow-always")))
                    (yeah-acp-handle-message answer))
                  (let ((rules (plist-get (yeah-acp--session-state session-id)
                                          :rules)))
                    (unless (seq-find (lambda (rule)
                                        (and (eq :session (plist-get rule :scope))
                                             (equal "edit"
                                                    (plist-get rule :action))))
                                      rules)
                      (push "the legacy answer allow-always wrote no rule of the session"
                            failures)))
                (yeah-acp--reset-for-test))

              ;; --- 4. the scope decides where the rule lives -------------
              ;; `once' writes no rule at all
              (yeah-perm-rules-reset-for-test)
              (let ((decision (yeah-approval-reply-decision request 'once)))
                (unless (eq (plist-get decision :scope) :once)
                  (push (format "the answer once carries the scope %S, not :once"
                                (plist-get decision :scope))
                        failures))
                (unless (null (yeah-perm-rules-list))
                  (push "the answer once wrote a rule into the rules of the process"
                        failures))
                (unless (null (yeah-check--rules-of-file
                               (yeah-perm--user-rules-file)))
                  (push "the answer once wrote a rule into the file of the user"
                        failures)))
              ;; `session' writes into the carrier of the path that asks:
              ;; the rules of the run in the attached path
              (yeah-perm-rules-reset-for-test)
              (let ((session (yeah-session-open "scope"
                                                (make-temp-file "yeah-c3-run" t)))
                    (context nil))
                (yeah-tools-register
                 (list :name "probe" :description "probe" :input nil
                       :handler (lambda () "ok")))
                (unwind-protect
                    (progn
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
                               (list :effect :allow :reply :session))))
                      (yeah-run-context-start context "the task")
                      (let ((rules (yeah-run-context-rules context)))
                        (unless (seq-find (lambda (rule)
                                            (eq :run (plist-get rule :scope)))
                                          rules)
                          (push "the answer session wrote no rule of the run"
                                failures))
                        ;; the rule of the run stayed in the run
                        (unless (null (seq-filter (lambda (rule)
                                                     (eq :run (plist-get rule :scope)))
                                                   (yeah-perm-rules-list)))
                          (push "the rule of the run landed in the rules of the process"
                                failures))
                        (unless (null (seq-filter (lambda (rule)
                                                     (eq :run (plist-get rule :scope)))
                                                   (yeah-check--rules-of-file
                                                    (yeah-perm--user-rules-file))))
                          (push "the rule of the run landed in the file of the user"
                                failures))))
                  (yeah-tools-reset-for-test)))
              (yeah-perm-rules-reset-for-test)
              ;; `project' writes into the file of the project, and into no
              ;; other carrier
              (yeah-approval-reply-decision request 'project)
              (let ((rules (yeah-check--rules-of-file
                            (yeah-perm--project-rules-file))))
                (unless (yeah-check--rule-of rules "edit" "/tmp/c3-file.el")
                  (push "the answer project wrote no rule into the file of the project"
                        failures))
                (dolist (rule rules)
                  (unless (eq :project (plist-get rule :scope))
                    (push (format "the rule of the file of the project carries the scope %S, not :project"
                                  (plist-get rule :scope))
                          failures)))
                (unless (null (yeah-check--rules-of-file
                               (yeah-perm--user-rules-file)))
                  (push "the rule of the project landed in the file of the user"
                        failures))
                (unless (null (yeah-check--rule-of (yeah-perm-rules-list)
                                                   "edit" "/tmp/c3-file.el"))
                  (push "the rule of the project landed in the rules of the process"
                        failures)))
              (yeah-perm-rules-reset-for-test)
              ;; `global' writes into the file of the user, and into no other
              ;; carrier
              (yeah-approval-reply-decision request 'global)
              (let ((rules (yeah-check--rules-of-file
                            (yeah-perm--user-rules-file))))
                (unless (yeah-check--rule-of rules "edit" "/tmp/c3-file.el")
                  (push "the answer global wrote no rule into the file of the user"
                        failures))
                (dolist (rule rules)
                  (unless (eq :global (plist-get rule :scope))
                    (push (format "the rule of the file of the user carries the scope %S, not :global"
                                  (plist-get rule :scope))
                          failures)))
                (unless (null (yeah-check--rules-of-file
                               (yeah-perm--project-rules-file)))
                  (push "the rule of the user landed in the file of the project"
                        failures)))
              (yeah-perm-rules-reset-for-test)

              ;; --- 6. the schema declares the method of the question -----
              (let* ((file (expand-file-name "schemas/acp-v1.json"
                                              (expand-file-name default-directory)))
                     (schema (and (file-exists-p file)
                                   (with-temp-buffer
                                     (insert-file-contents file)
                                     (json-parse-string (buffer-string)
                                                        :object-type 'plist
                                                        :array-type 'list))))
                     (methods (and schema (plist-get schema :methods)))
                     (method (and methods
                                  (plist-get methods :session/request_permission))))
                (unless method
                  (push "the schema does not declare session/request_permission"
                        failures))
                (when method
                  (let* ((definitions (plist-get schema :definitions))
                         (params (plist-get definitions :RequestPermissionRequest))
                         (result (plist-get definitions :RequestPermissionResponse)))
                    (unless params
                      (push "the schema declares no params of the question" failures))
                    (unless result
                      (push "the schema declares no result of the question" failures))
                    (when params
                      (let* ((properties (plist-get params :properties))
                             (tool-call (plist-get (plist-get properties :toolCall)
                                                   :properties))
                             (option (plist-get definitions :PermissionOption)))
                        (dolist (key '(:sessionId :toolCall :options))
                          (unless (plist-get properties key)
                            (push (format "the params of the question declare no %s" key)
                                  failures)))
                        (dolist (key '(:toolCallId :title :rawInput))
                          (unless (plist-get tool-call key)
                            (push (format "the tool call of the question declares no %s" key)
                                  failures)))
                        (unless option
                          (push "the schema declares no option of the question" failures))
                        (when option
                          (dolist (key '(:optionId :name :kind))
                            (unless (plist-get (plist-get option :properties) key)
                              (push (format "an option of the question declares no %s" key)
                                    failures))))))
                    (when result
                      (let ((outcome (plist-get (plist-get (plist-get result :properties)
                                                          :outcome)
                                                :properties)))
                        (unless outcome
                          (push "the result of the question declares no outcome" failures))
                        (when outcome
                          (unless (plist-get outcome :outcome)
                            (push "the outcome of the question declares no outcome"
                                  failures))
                          (unless (plist-get outcome :optionId)
                            (push "the outcome of the question declares no optionId"
                                  failures)))))))))

              ;; --- 7. a scope that the path cannot hold is refused ---------
              (let* ((context (yeah-run-context-create
                               :placement 'attached
                               :rules nil
                               :answerer (lambda (_request)
                                           (list :effect :allow
                                                 :reply :session
                                                 :scope :project))))
                     (decision (funcall (yeah-run-context-policy context)
                                        request)))
                (unless (eq (plist-get decision :effect) :deny)
                  (push "the scope that the run cannot hold was not refused"
                        failures))
                (unless (string-match-p "project"
                                        (or (plist-get decision :reason) ""))
                  (push (format "the refusal does not name the scope: %S"
                                (plist-get decision :reason))
                        failures))
                (unless (string-match-p "carrier"
                                        (or (plist-get decision :reason) ""))
                  (push (format "the refusal does not say why: %S"
                                (plist-get decision :reason))
                        failures)))

              ;; --- the check leaves no rule behind -------------------------
              (yeah-perm-rules-reset-for-test)
              (unless (null (yeah-perm-rules-list))
                (push "the check left a rule in the rules of the process" failures))
              (unless (null (yeah-perm-file-rules))
                (push "the check left a rule in a file of the person behind" failures))))))

    (ignore-errors (delete-directory project t))
    (ignore-errors (delete-directory config t))
    (ignore-errors (delete-directory data t)))

  (dolist (failure failures)
    (message "scope: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-question-offers-the-scope.el ends here
