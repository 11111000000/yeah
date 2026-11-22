;;; check-a-scope-decides-where-the-rule-lives.el --- where the rule lives -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The scope of a rule says where the rule lives, and the carrier of a
;; scope is what holds it.  This check measures that:
;;
;;   1. every scope of the dictionary has exactly one carrier, and no
;;      carrier holds the rules of two scopes;
;;   2. the correspondence between a scope and its carrier is written in
;;      one place: this check names a second writing when there is one;
;;   3. the paths of the carriers come from one place as well: the file of
;;      the project is `.yeah/rules.json' of the project, the file of the
;;      user is `yeah/rules.json' of the configuration of the user, and
;;      the configuration of the user is the one of `XDG_CONFIG_HOME';
;;   4. the three paths that write a rule write it into the carrier of the
;;      scope of that rule: the person writes into the file of the user,
;;      the run writes into the run, the session writes into the session;
;;   5. a rule of the project lands in the file of the project and in no
;;      other carrier;
;;   6. a scope that holds no rule is refused by name;
;;   7. a rule that is saved in a file is read back when the permission is
;;      computed: a rule that is saved and never read does not exist;
;;   8. a file that is not there is a file of no rules, and a file that is
;;      broken is a refusal that names the file and the reason;
;;   9. a rule that goes into a file comes back out of it unchanged.
;;
;; The check works in a temporary directory: it writes nothing into the
;; project of the person and nothing into the configuration of the person.
;;
;; Exit codes: 0 — the scope decides where the rule lives; 1 — it does not.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'yeah-approval)
(require 'yeah-acp)
(require 'yeah-perm)
(require 'yeah-run)
(require 'yeah-session)
(require 'yeah-tools)

(defun yeah-check--scopes ()
  "Return the canonical scopes of the kernel, or nil.
A kernel that has no such dictionary has no canonical scopes, and this
check says so instead of dying."
  (and (fboundp 'yeah-perm-scopes)
       (yeah-perm-scopes)))

(defun yeah-check--carriers ()
  "Return the table of the carriers of the scopes, or nil.
The table is the one place where the correspondence between a scope and
its carrier is written."
  (and (boundp 'yeah-perm--carriers)
       yeah-perm--carriers))

(defun yeah-check--carrier-names ()
  "Return the names of the carriers of the scopes."
  (mapcar (lambda (entry) (nth 1 entry)) (yeah-check--carriers)))

(defun yeah-check--pair-of (list scopes carriers)
  "Return the (SCOPE . CARRIER) pair that LIST writes, or nil.
A pair is a list that names a scope of the dictionary and a carrier of
the scopes next to each other: that is the writing of a correspondence."
  (when (proper-list-p list)
    (let ((scope (seq-find (lambda (element) (memq element scopes)) list))
          (carrier (seq-find (lambda (element)
                               (and (symbolp element)
                                    (not (keywordp element))
                                    (memq element carriers)))
                             list)))
      (and scope carrier (cons scope carrier)))))

(defun yeah-check--walk-list (list scopes carriers found)
  "Return FOUND with the pairs written in LIST and in the lists inside it."
  (let ((acc found)
        (pair (yeah-check--pair-of list scopes carriers)))
    (when pair
      (setq acc (cons pair acc)))
    (when (proper-list-p list)
      (dolist (element list)
        (when (and (consp element) (proper-list-p element))
          (setq acc (yeah-check--walk-list element scopes carriers acc)))))
    acc))

(defun yeah-check--walk (node scopes carriers found)
  "Return FOUND with the pairs written in NODE and in the forms inside it."
  (cond
   ((and (consp node) (eq (car node) 'quote))
    (yeah-check--walk-list (cadr node) scopes carriers found))
   ((consp node)
    (let ((acc found))
      (dolist (element node)
        (setq acc (yeah-check--walk element scopes carriers acc)))
      acc))
   ((vectorp node)
    (let ((acc found))
      (dotimes (index (length node))
        (setq acc (yeah-check--walk (aref node index) scopes carriers acc)))
      acc))
   (t found)))

(defun yeah-check--places (root failures)
  "Return the places of ROOT where a scope is written next to a carrier.
Each place is a list (FILE LINE SCOPE CARRIER); the file is named
relative to ROOT.  Only the modules of `lib/' are read: the
correspondence of the kernel is written there.  FAILURES is the list of
the failures of the check: a file that cannot be read is named there and
the scan goes on."
  (let ((found nil)
        (scopes (yeah-check--scopes))
        (carriers (yeah-check--carrier-names)))
    (dolist (file (file-expand-wildcards (expand-file-name "lib/*.el" root)))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        ;; The reader says when the file is over: the loop ends there and
        ;; not one form earlier.
        (condition-case err
            (while t
              (let ((start (point)))
                (let ((form (read (current-buffer))))
                  (dolist (pair (yeah-check--walk form scopes carriers nil))
                    (push (list (file-relative-name file root)
                                (line-number-at-pos start)
                                (car pair)
                                (cdr pair))
                          found)))))
          (end-of-file nil)
          (error
           (push (format "the file %s could not be read: %s"
                         file (error-message-string err))
                 failures)))))
    found))

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

(defun yeah-check--holds-p (rules rule)
  "Non-nil when RULES holds RULE."
  (and (member rule rules) t))

(let ((failures nil)
      (repo (expand-file-name default-directory))
      (project (yeah-check--temp-directory "yeah-c2-project"))
      (config (yeah-check--temp-directory "yeah-c2-config"))
      (saved-xdg (getenv "XDG_CONFIG_HOME")))

  (unwind-protect
      (progn
        (setenv "XDG_CONFIG_HOME" config)
        (let ((default-directory project))
          (cl-letf (((symbol-function 'yeah-product-project-root)
                      (lambda () project)))

            ;; --- 1. one carrier for every scope ---------------------------
            (let ((carriers (yeah-check--carriers))
                  (scopes (yeah-check--scopes)))
              (unless carriers
                (push "the kernel has no table of the carriers" failures))
              (unless scopes
                (push "the kernel has no dictionary of the scopes" failures))
              (when (and carriers scopes)
                (dolist (scope scopes)
                  (let ((entries (seq-filter (lambda (entry)
                                               (eq (nth 0 entry) scope))
                                             carriers)))
                    (unless (= 1 (length entries))
                      (push (format "the scope %s has %d carriers, not one"
                                    scope (length entries))
                            failures))
                    (when (= 1 (length entries))
                      (let ((entry (car entries)))
                        (unless (and (symbolp (nth 1 entry))
                                     (stringp (nth 2 entry)))
                          (push (format "the carrier of the scope %s is not named: %S"
                                        scope entry)
                                failures))
                        ;; a carrier holds the rules of one scope and of no other
                        (let ((twins (seq-filter (lambda (other)
                                                   (eq (nth 1 other) (nth 1 entry)))
                                                 carriers)))
                          (unless (= 1 (length twins))
                            (push (format "the carrier %s holds the rules of %d scopes"
                                          (nth 1 entry) (length twins))
                                  failures))))))
                (dolist (entry carriers)
                  (unless (memq (nth 0 entry) scopes)
                    (push (format "the carrier %s holds the rules of the scope %S, which is not a scope"
                                  (nth 1 entry) (nth 0 entry))
                          failures)))
                (unless (= (length scopes) (length carriers))
                  (push (format "the table holds %d carriers for %d scopes"
                                (length carriers) (length scopes))
                        failures)))))

            ;; --- 2. the correspondence is written in one place ------------
            (let ((places (yeah-check--places repo failures)))
              (dolist (place places)
                (unless (equal "lib/yeah-perm.el" (nth 0 place))
                  (push (format "the scope %s is written next to the carrier %s in %s:%s"
                                (nth 2 place) (nth 3 place) (nth 0 place) (nth 1 place))
                        failures)))
              ;; every pair of the table is written, and nothing else
              (let ((expected (mapcar (lambda (entry) (cons (nth 0 entry) (nth 1 entry)))
                                      (yeah-check--carriers)))
                    (found (mapcar (lambda (place) (cons (nth 2 place) (nth 3 place)))
                                   places)))
                (unless (equal (sort (mapcar (lambda (pair) (format "%S" pair)) expected) #'string<)
                             (sort (mapcar (lambda (pair) (format "%S" pair)) found) #'string<))
                  (push (format "the correspondence of the scopes and the carriers is %S, not %S"
                                found expected)
                        failures))))

            ;; --- 3. the paths of the carriers come from one place ---------
            (let ((project-file (yeah-perm--project-rules-file))
                  (user-file (yeah-perm--user-rules-file)))
              (unless (equal (expand-file-name ".yeah/rules.json" project) project-file)
                (push (format "the file of the project is %s, not the one of the project"
                              project-file)
                      failures))
              (unless (equal (expand-file-name "yeah/rules.json" config) user-file)
                (push (format "the file of the user is %s, not the one of the configuration"
                              user-file)
                      failures))
              ;; the configuration of the user is the one of XDG_CONFIG_HOME
              (let ((saved (getenv "XDG_CONFIG_HOME")))
                (unwind-protect
                    (progn
                      (setenv "XDG_CONFIG_HOME" nil)
                      (unless (equal (expand-file-name
                                      "yeah/rules.json"
                                      (expand-file-name ".config" (getenv "HOME")))
                                     (yeah-perm--user-rules-file))
                        (push (format "the file of the user is %s without XDG_CONFIG_HOME"
                                      (yeah-perm--user-rules-file))
                              failures)))
                  (setenv "XDG_CONFIG_HOME" saved))))

            ;; --- 4. the person writes into the file of the user -----------
            (let ((request (yeah-approval-request "edit" "/tmp/c2-human.el")))
              (yeah-approval-reply-decision request 'always)
              (let ((user-file (yeah-perm--user-rules-file))
                    (project-file (yeah-perm--project-rules-file)))
                (unless (file-exists-p user-file)
                  (push "the person wrote no file" failures))
                (when (file-exists-p project-file)
                  (push "the person wrote into the file of the project" failures))
                (let ((rules (yeah-check--rules-of-file user-file)))
                  (unless (seq-find (lambda (rule)
                                      (and (equal "edit" (plist-get rule :action))
                                           (equal "/tmp/c2-human.el" (plist-get rule :resource))))
                                    rules)
                    (push "the file of the user holds no rule of the person" failures))
                  (dolist (rule rules)
                    (unless (eq :global (plist-get rule :scope))
                      (push (format "the rule of the file of the user carries the scope %S, not :global"
                                    (plist-get rule :scope))
                            failures))))))

            ;; --- 5. the run writes into the run ---------------------------
            (let ((session (yeah-session-open "scope" (make-temp-file "yeah-c2-run" t)))
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
                             (list :effect :allow :reply :always))))
                    (yeah-run-context-start context "the task")
                    (let ((rules (yeah-run-context-rules context)))
                      (unless (seq-find (lambda (rule)
                                          (eq :run (plist-get rule :scope)))
                                        rules)
                        (push "the run wrote no rule of the run" failures))
                      ;; the rule of the run is the last one it wrote
                      (let ((own (car (last rules))))
                        (unless (eq :run (plist-get own :scope))
                          (push (format "the rule of the run carries the scope %S, not :run"
                                        (plist-get own :scope))
                                failures))))
                    ;; the run wrote nothing on the disk
                    (when (file-exists-p (yeah-perm--project-rules-file))
                      (push "the run wrote into the file of the project" failures))
                    (let ((rules (yeah-check--rules-of-file (yeah-perm--user-rules-file))))
                      (when (seq-find (lambda (rule)
                                        (eq :run (plist-get rule :scope)))
                                      rules)
                        (push "the run wrote into the file of the user" failures)))
                    ;; the rule of the run stayed in the run
                    (when (seq-find (lambda (rule)
                                      (eq :run (plist-get rule :scope)))
                                    (yeah-perm-rules-list))
                      (push "the run wrote into the rules of the process" failures)))
                (yeah-tools-reset-for-test)))

            ;; --- 6. the session writes into the session -------------------
            (let* ((directory (yeah-check--temp-directory "yeah-c2-session"))
                   (yeah-data-home directory)
                   (yeah-input-directory (expand-file-name "pending/" directory))
                   (yeah-acp--transport nil)
                   (yeah-acp--answerer nil)
                   (yeah-acp--output-function nil))
              (unwind-protect
                  (progn
                    (yeah-acp--reset-for-test)
                    (let* ((session-id
                            (plist-get (yeah-acp-session-new
                                        (list :cwd (file-truename yeah-data-home)
                                              :mcpServers nil))
                                       :sessionId))
                           (answerer (yeah-acp--client-answerer
                                      session-id (lambda (_text) nil)))
                           (request (list :action "write" :resource "/tmp/c2-session.el"
                                           :args nil))
                           (deferral (funcall answerer request))
                           (id (plist-get deferral :defer))
                           (question (gethash id yeah-acp--pending-permissions)))
                      (let ((scoped (yeah-acp--remember-decision
                                     question
                                     (yeah-acp--permission-decision
                                      (list :result
                                            (list :outcome
                                                  (list :optionId "allow-always")))))))
                        (unless (eq :session (plist-get scoped :scope))
                          (push (format "the answer of the session carries the scope %S, not :session"
                                        (plist-get scoped :scope))
                                failures))
                        (let ((rules (plist-get (yeah-acp--session-state session-id) :rules)))
                          (unless (seq-find (lambda (rule)
                                              (eq :session (plist-get rule :scope)))
                                            rules)
                            (push "the session wrote no rule of the session" failures))))
                    ;; the session wrote nothing on the disk
                    (when (file-exists-p (yeah-perm--project-rules-file))
                      (push "the session wrote into the file of the project" failures))
                    (let ((rules (yeah-check--rules-of-file (yeah-perm--user-rules-file))))
                      (when (seq-find (lambda (rule)
                                        (eq :session (plist-get rule :scope)))
                                      rules)
                        (push "the session wrote into the file of the user" failures)))
                    ;; the rule of the session stayed in the session
                    (when (seq-find (lambda (rule)
                                      (eq :session (plist-get rule :scope)))
                                    (yeah-perm-rules-list))
                      (push "the session wrote into the rules of the process" failures)))
                (yeah-acp--reset-for-test)
                (ignore-errors (delete-directory directory t t)))))

            ;; --- 7. a rule of the project lands in the file of the project --
            (let ((rule (yeah-perm-rule-make "edit" "/tmp/c2-project.el" 'allow :project)))
              (yeah-perm-rule-store rule)
              (let ((project-file (yeah-perm--project-rules-file))
                    (user-file (yeah-perm--user-rules-file)))
                (unless (file-exists-p project-file)
                  (push "the rule of the project landed in no file" failures))
                (unless (yeah-check--holds-p (yeah-check--rules-of-file project-file) rule)
                  (push "the file of the project holds no rule of the project" failures))
                ;; and in no other carrier
                (when (yeah-check--holds-p (yeah-check--rules-of-file user-file) rule)
                  (push "the rule of the project landed in the file of the user" failures))
                (when (yeah-check--holds-p (yeah-perm-rules-list) rule)
                  (push "the rule of the project landed in the rules of the process" failures))))

            ;; --- 8. a scope that holds no rule is refused by name ----------
            (let ((message (condition-case err
                               (yeah-perm-rule-store
                                (yeah-perm-rule-make "edit" "/tmp/c2-once.el" 'allow :once))
                             (error (error-message-string err)))))
              (unless (and message (string-match-p "once" message))
                (push (format "the scope once was not refused by name: %S" message)
                      failures)))
            (let ((message (condition-case err
                               (yeah-perm-rule-store
                                (list :action "edit" :resource "/tmp/c2-nowhere.el"
                                      :effect 'allow :scope :nowhere))
                             (error (error-message-string err)))))
              (unless (and message (string-match-p "nowhere" message))
                (push (format "the scope that is not a scope was not refused by name: %S"
                              message)
                      failures)))

            ;; --- 9. a rule that is saved is read back ----------------------
            ;; The memory of the process is empty: the rule that allows the
            ;; call can only come from the files of the carriers.
            (let ((yeah-perm--rules nil))
              (unless (eq 'allow (yeah-perm-effect "edit" "/tmp/c2-project.el"))
                (push "the rule of the file of the project was not read back" failures))
              (unless (eq 'allow (yeah-perm-effect "edit" "/tmp/c2-human.el"))
                (push "the rule of the file of the user was not read back" failures)))

            ;; --- 10. a file that is not there, a file that is broken ------
            (let ((missing (expand-file-name "c2-missing.json" project)))
              (when (condition-case err
                        (yeah-perm--read-rules-file missing)
                      (error (error-message-string err)))
                (push "a file that is not there was refused" failures)))
            (dolist (broken '("{not json" "{\"action\":\"edit\"}" "[{\"action\":\"edit\"}]"))
              (let* ((file (expand-file-name "c2-broken.json" project))
                     (message (condition-case err
                                 (progn
                                   (with-temp-file file (insert broken))
                                   (yeah-perm--read-rules-file file))
                               (error (error-message-string err)))))
                (unless message
                  (push (format "the broken file %s was not refused" broken) failures))
                (when message
                  (unless (string-match-p "c2-broken.json" message)
                    (push (format "the refusal does not name the file: %S" message)
                          failures))
                  (let ((reason (and (string-match (regexp-quote file) message)
                                      (string-trim (substring message (match-end 0))))))
                    (unless (and reason (> (length reason) 0))
                      (push (format "the refusal does not say why: %S" message)
                            failures))))))

            ;; --- 11. the round trip ----------------------------------------
            (let* ((rule (yeah-perm-rule-make "read" "/tmp/c2-round.el" 'deny :project))
                   (file (yeah-perm--project-rules-file)))
              (yeah-perm--write-rules-file file (list rule))
              (unless (equal (yeah-perm--read-rules-file file) (list rule))
                (push "the rule came back out of the file changed" failures)))

            ;; the rules of the process are taken back: the check leaves no
            ;; rule in the file of the person
            (yeah-perm-rules-reset-for-test))))

    (setenv "XDG_CONFIG_HOME" saved-xdg)
    (ignore-errors (delete-directory project t))
    (ignore-errors (delete-directory config t)))

  (dolist (failure failures)
    (message "carrier: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-scope-decides-where-the-rule-lives.el ends here
