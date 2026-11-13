;;; check-todo.el --- canary for the task list of a run -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;; The task list of a run is not a variable of the run: it is a projection
;; of its journal.  The check says so, and it says it in the way that can
;; fail — the list is built by the tools, read back from the log after a
;; restart, and then the log loses the events the list was made of.
;;
;; Three things are checked:
;;
;;   1. the tools of the list (todo_add, todo_update, todo_list) are
;;      registered, and add, update and list leave the list the way they
;;      say they do;
;;   2. a run that asks for a task writes the task into the journal of that
;;      run — the tool finds the journal of the run that called it;
;;   3. a restart that reads the journal again finds the same list, and a
;;      journal that lost the todo events has no list: the projection
;;      comes from the log, not from the memory of the process.
;;
;; The third point is the control: when the module stops reading the
;; journal, the check fails on an assertion, not on a crash.  A tool that
;; refuses the call is a failure of the check, and the check says so
;; instead of ending in a backtrace.
;;
;; Exit codes: 0 — the list is the journal; 1 — it is not.

;;; Code:

(require 'cl-lib)
(require 'yeah-events)
(require 'yeah-perm)
(require 'yeah-result)
(require 'yeah-session)
(require 'yeah-todo)
(require 'yeah-tools)
(require 'yeah-turn)

(defun yeah-check--records (root name)
  "Return the records of the log of session NAME under ROOT."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "sessions/%s.jsonl" name) root))
    (mapcar (lambda (line) (json-parse-string line :object-type 'plist))
            (split-string (buffer-string) "\n" t))))

(defun yeah-check--todo-records (records)
  "Return the `todo' records of RECORDS."
  (seq-filter (lambda (record) (equal (plist-get record :type) "todo"))
              records))

(defun yeah-check--keys (plist)
  "Return the keys of the plist PLIST, in the order they are in."
  (let ((keys nil) (rest plist))
    (while rest
      (setq keys (cons (car rest) keys))
      (setq rest (cddr rest)))
    (nreverse keys)))

(defun yeah-check--drop-todo-records (path)
  "Remove the `todo' records from the JSONL file at PATH.
This is the control of the check: the journal loses what the task list was
made of, and the list must be empty afterwards."
  (with-temp-buffer
    (insert-file-contents path)
    (let ((kept nil))
      (dolist (line (split-string (buffer-string) "\n" t))
        (let ((record (json-parse-string line :object-type 'plist)))
          (unless (equal (plist-get record :type) "todo")
            (setq kept (cons line kept)))))
      (let ((coding-system-for-write 'utf-8))
        (with-temp-buffer
          (dolist (line (nreverse kept))
            (insert line "\n"))
          (write-region (point-min) (point-max) path nil 'silent))))))

(defun yeah-check--call (name args)
  "Call the tool NAME with ARGS and return `(:result RESULT :error MESSAGE)'.
MESSAGE is nil when the tool succeeded.  A tool that refuses the call is a
failure of the check, not a crash of Emacs."
  (condition-case err
      (let ((result (yeah-tools-call name args)))
        (if (yeah-result-success-p result)
            (list :result result :error nil)
          (list :result result
                :error (format "the tool %s did not succeed" name))))
    (user-error
     (list :result nil
           :error (format "the tool %s failed: %s" name
                          (error-message-string err))))))

(defun yeah-check--expected ()
  "Return the task list the check expects after add, add, update and update."
  (list (list :id "1" :text "write the module" :status "in-progress")
        (list :id "2" :text "write the canary" :status "done")))

(let ((failures nil)
      (root (make-temp-file "yeah-todo-check" t)))
  (unwind-protect
      (progn
        ;; --- the tools are registered ------------------------------------
        (yeah-tools-reset-for-test)
        (dolist (name '("todo_add" "todo_update" "todo_list"))
          (unless (yeah-tools-get name)
            (push (format "the tool %s is not registered" name) failures)))

        ;; --- add, update and list through the registry --------------------
        (let ((session (yeah-session-open "todo" root)))
          (yeah-todo-with-session
           session
            (dolist (call '(("todo_add" "write the module")
                            ("todo_add" "write the canary")
                            ("todo_update" "1" "in-progress")
                            ("todo_update" "2" "done")))
              (let* ((outcome (yeah-check--call (car call) (cdr call)))
                     (error (plist-get outcome :error)))
                (when error
                  (push error failures))))
            (let* ((outcome (yeah-check--call "todo_list" nil))
                   (error (plist-get outcome :error))
                   (text (yeah-result-model-text (plist-get outcome :result))))
              (when error
                (push error failures))
              (unless (and (null error)
                           (string-match-p "in-progress" text)
                           (string-match-p "done" text)
                           (string-match-p "write the module" text))
                (push (format "todo_list does not show the list: %s" text)
                      failures))))

          ;; The list is what the journal says.
          (let ((items (yeah-todo-items session)))
            (unless (equal items (yeah-check--expected))
              (push (format "the projection of the journal is wrong: %S" items)
                    failures)))

          ;; The journal holds the tasks as events of the declared shape.
          (let* ((records (yeah-check--records root "todo"))
                 (events (yeah-check--todo-records records)))
            (unless (= (length events) 4)
              (push (format "the journal holds %d todo events, not 4"
                            (length events))
                    failures))
            (dolist (event events)
              (let ((declared (plist-get (yeah-events-spec "todo") :fields))
                    (given (delq :id (delq :type (yeah-check--keys event)))))
                (unless (equal (sort (copy-sequence declared) #'string<)
                               (sort (copy-sequence given) #'string<))
                  (push (format "the todo event declares %S and was given %S"
                                declared given)
                        failures)))
              (unless (member (plist-get event :operation) '("add" "update"))
                (push (format "the todo event carries the unknown operation %S"
                              (plist-get event :operation))
                      failures))
              (let ((items (plist-get event :items)))
                (unless (and (vectorp items)
                             (= (length items) 1)
                             (stringp (plist-get (aref items 0) :id))
                             (stringp (plist-get (aref items 0) :text))
                             (member (plist-get (aref items 0) :status)
                                     '("pending" "in-progress" "done")))
                  (push (format "the todo event does not carry its task: %S"
                                items)
                        failures))))))

        ;; --- a run that asks for a task ------------------------------------
        (let ((session (yeah-session-open "run" root)))
          (yeah-perm-rules-reset-for-test)
          (yeah-perm-rules-add (yeah-perm-rule-make "todo_add" "*" 'allow))
          (condition-case err
              (let* ((transport
                      (lambda (_prompt callback)
                        (funcall callback
                                 (list 'tool-call
                                       (list (list :name "todo_add")
                                             (list "ask the model")
                                             (lambda (_value)
                                               (funcall callback "the model is done")))))))
                     (turn (yeah-turn-run session "do the work" transport)))
                (unless (yeah-turn-done turn)
                  (push "the run did not finish" failures))
                (let ((items (yeah-todo-items session)))
                  (unless (equal (mapcar (lambda (item) (plist-get item :text))
                                         items)
                                 '("ask the model"))
                    (push (format "the run did not write its task into its journal: %S"
                                  items)
                          failures))))
            (error
             (push (format "the run failed: %s" (error-message-string err))
                   failures))))

        ;; --- a restart reads the journal again ------------------------------
        (let* ((session (yeah-session-open "todo" root))
               (items (yeah-todo-items session)))
          (unless (equal items (yeah-check--expected))
            (push (format "the restart did not restore the list: %S" items)
                  failures)))

        ;; --- the control: the journal loses the todo events ----------------
        (let ((path (yeah-session--path-for "todo" root)))
          (yeah-check--drop-todo-records path)
          (let* ((session (yeah-session-open "todo" root))
                 (items (yeah-todo-items session)))
            (unless (null items)
              (push (format "the list survived the loss of its events: %S" items)
                    failures)))))
    (ignore-errors (delete-directory root t t)))

  (dolist (failure failures)
    (message "todo: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-todo.el ends here
