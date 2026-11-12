;;; yeah-subagent.el --- sub-agent delegation -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A sub-agent is a run of its own: its own session, its own context, its
;; own journal, and a set of tools it may use that is smaller than the set
;; its parent may use.  The child cannot exceed what it was granted, and
;; every attempt to do so is in its journal, where the parent can read it.
;;
;; The lineage is in the names: the session of a child is
;; `<parent>.sub-<n>', so the tree of a session is readable from the files
;; alone.  The parent is told what happened, too: the journal of the parent
;; carries a `spawn' event and a `child-end' event.
;;
;; The depth is bounded: a child whose depth would reach the limit is
;; refused, and the refusal is a `user-error' rather than a silent
;; truncation.
;;
;; Public API:
;;
;;   * `yeah-subagent-spawn' PARENT-SESSION ROLE PROMPT &key ...
;;   * `yeah-subagent-wait' CHILD-ID
;;   * `yeah-subagent-cancel' CHILD-ID
;;   * `yeah-subagent-children' PARENT-SESSION
;;   * `yeah-subagent-fork-summary' PARENT-SESSION CHILD-SESSION
;;   * `yeah-subagent-depth-limit'
;;   * `yeah-subagent-reset-for-test'

;;; Code:

(require 'cl-lib)
(require 'yeah-events)
(require 'yeah-perm)
(require 'yeah-run)
(require 'yeah-session)

(defgroup yeah-subagent nil
  "Yeah sub-agent delegation."
  :group 'yeah)

(defvar yeah-subagent--max-depth 3
  "Maximum sub-agent depth. The top-level loop is at depth 0.
A child whose depth would be equal to or greater than this limit is refused.")

(defvar yeah-subagent--active (make-hash-table :test 'eq :size 8)
  "Table mapping child ids to child record plists.
Each record has shape (:id ID :role ROLE :prompt PROMPT :depth DEPTH
:child-session SESSION :status STATUS :result RESULT :turn TURN
:parent-id PARENT :tools TOOLS).")

(defvar yeah-subagent--sessions (make-hash-table :test 'eq :size 8)
  "Table mapping child ids to the session of their parent.")

(defvar yeah-subagent--next-id 0
  "Next monotonic child id to assign.")

(defun yeah-subagent--reset-table ()
  "Replace the active-sub-agents hash with a fresh empty one."
  (setq yeah-subagent--active (make-hash-table :test 'eq :size 8)))

(defun yeah-subagent--root-from (session)
  "Return the root directory of SESSION, the directory that holds the
`sessions/' subdir holding the JSONL file."
  (let ((path (plist-get session :path)))
    (when (stringp path)
      (let* ((dir (file-name-directory path))
             (sessions-dir (and dir (directory-file-name dir)))
             (root (and sessions-dir
                        (file-name-directory
                         (directory-file-name sessions-dir)))))
        (when root
          (directory-file-name root))))))

(defun yeah-subagent--validate (parent-session role prompt depth)
  "Validate the arguments of a spawn.  Signals `user-error' on a bad shape."
  (unless (and (consp parent-session) (plist-get parent-session :path))
    (signal 'user-error
            (list (format "yeah-subagent-spawn: bad parent session %S"
                          parent-session))))
  (unless (and (stringp role) (> (length role) 0))
    (signal 'user-error
            (list (format "yeah-subagent-spawn: ROLE must be a non-empty string, got %S"
                          role))))
  (unless (stringp prompt)
    (signal 'user-error
            (list (format "yeah-subagent-spawn: PROMPT must be a string, got %S"
                          prompt))))
  (unless (and (integerp depth) (>= depth 0))
    (signal 'user-error
            (list (format "yeah-subagent-spawn: DEPTH must be a non-negative integer, got %S"
                          depth))))
  (when (>= (1+ depth) yeah-subagent--max-depth)
    (signal 'user-error
            (list (format "yeah-subagent-spawn: child depth %d would exceed limit %d"
                          (1+ depth) yeah-subagent--max-depth))))
  nil)

(defun yeah-subagent--rules (tools)
  "Return the rules that allow the tools named TOOLS and nothing else."
  (mapcar (lambda (name) (yeah-perm-rule-make name "*" 'allow)) tools))

(defun yeah-subagent--last-answer (session)
  "Return the last thing the model said in SESSION, or nil."
  (let ((answer nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) "assistant-message")
        (setq answer (plist-get record :payload))))
    answer))

(defun yeah-subagent--finish (child-id turn)
  "Record the end of the child CHILD-ID, whose TURN has finished."
  (let ((record (gethash child-id yeah-subagent--active)))
    (when record
      (let* ((session (plist-get record :child-session))
             (answer (yeah-subagent--last-answer session))
             (ok (eq 'completed (yeah-turn-state turn)))
             (parent (gethash child-id yeah-subagent--sessions)))
        (setf (plist-get record :status) (if ok 'completed 'failed)
              (plist-get record :result) (or answer ""))
        (when parent
          (yeah-events-write parent "child-end"
                             :child (plist-get session :id)
                             :role (plist-get record :role)
                             :ok ok
                             :summary (or answer "")))))))

(cl-defun yeah-subagent-spawn (parent-session role prompt
                                  &key depth transport tools budget answerer)
  "Spawn a child sub-agent and return its record.

PARENT-SESSION is the session of the parent.  ROLE names what the child
does.  PROMPT is the task of the child.  DEPTH is the depth of the
caller; the child is one deeper.  TRANSPORT reaches the model; it
defaults to gptel.  TOOLS are the tools the child may use: every other
tool is refused, and the refusal is in the journal of the child.  BUDGET
is the context budget of the child.

The child runs in its own session, whose id carries the lineage:
`<parent-id>.sub-<n>'.  The spawn is asynchronous: the record comes
back with the status `running', and `yeah-subagent-wait' waits for the
child to finish.

Signals `user-error' when the depth of the child would reach
`yeah-subagent-depth-limit'."
  (let ((d (or depth 0)))
    (yeah-subagent--validate parent-session role prompt d)
    (let* ((root (yeah-subagent--root-from parent-session))
           (child-id (cl-incf yeah-subagent--next-id))
           (parent-id (plist-get parent-session :id))
           (child-session-id (format "%s.sub-%d" parent-id child-id))
           (child-session (yeah-session-open child-session-id root))
           (child-depth (1+ d))
           (record nil))
      (setq record (list :id child-id
                          :role role
                          :prompt prompt
                          :depth child-depth
                          :child-session child-session
                          :status 'running
                          :result nil
                          :turn nil
                          :parent-id parent-id
                          :parent-session-id parent-id
                          :tools tools))
      (puthash child-id record yeah-subagent--active)
      (puthash child-id parent-session yeah-subagent--sessions)
      (yeah-events-write parent-session "spawn"
                         :child child-session-id :role role :depth child-depth)
      (let ((context (yeah-run-context-create
                      :placement 'service
                      :session child-session
                      :transport transport
                      :answerer answerer
                      :rules (yeah-subagent--rules tools)
                      :budget budget
                      :on-done (lambda (turn)
                                 (yeah-subagent--finish child-id turn)))))
        (setf (plist-get record :turn)
              (yeah-run-context-start context prompt))
        record))))

(defun yeah-subagent-wait (child-id &optional timeout)
  "Wait for the child CHILD-ID to finish and return its record.
The wait is bounded by TIMEOUT seconds.  Signals `user-error' when
CHILD-ID does not name a sub-agent."
  (let ((record (gethash child-id yeah-subagent--active)))
    (unless record
      (signal 'user-error
              (list (format "yeah-subagent-wait: no active sub-agent %S"
                            child-id))))
    (let ((turn (plist-get record :turn))
          (deadline (+ (float-time) (or timeout 60))))
      (while (and turn
                  (not (yeah-turn-done turn))
                  (< (float-time) deadline))
        (accept-process-output nil 0.05))
      record)))

(defun yeah-subagent-cancel (child-id &optional reason)
  "Cancel the child CHILD-ID and everything it spawned.
Return non-nil when a running child was cancelled."
  (let ((record (gethash child-id yeah-subagent--active)))
    (when record
      (let ((cancelled nil))
        (dolist (child (yeah-subagent--children-of child-id))
          (when (yeah-subagent-cancel (plist-get child :id) reason)
            (setq cancelled t)))
        (let ((turn (plist-get record :turn)))
          (when (and turn (not (yeah-turn-done turn)))
            (yeah-turn-cancel turn (or reason "cancelled by the parent"))
            (setq cancelled t)))
        cancelled))))

(defun yeah-subagent--children-of (child-id)
  "Return the records of the children of the child CHILD-ID."
  (let ((children nil)
        (record (gethash child-id yeah-subagent--active)))
    (when record
      (let ((parent (plist-get record :child-session)))
        (maphash
         (lambda (_id other)
           (when (equal (plist-get other :parent-session-id)
                        (plist-get parent :id))
             (push other children)))
         yeah-subagent--active)))
    (nreverse children)))

(defun yeah-subagent-children (parent-session)
  "Return the records of the children of PARENT-SESSION."
  (let ((children nil)
        (parent-id (plist-get parent-session :id)))
    (maphash
     (lambda (_id record)
       (when (equal (plist-get record :parent-session-id) parent-id)
         (push record children)))
     yeah-subagent--active)
    (sort children (lambda (left right) (< (plist-get left :id)
                                           (plist-get right :id))))))

(defun yeah-subagent--find-id-by-session (child-session)
  "Return the child id whose `:child-session' equals CHILD-SESSION, or nil."
  (let ((target child-session)
        (found nil))
    (maphash
     (lambda (id record)
       (when (and (null found)
                  (eq (plist-get record :child-session) target))
         (setq found id)))
     yeah-subagent--active)
    found))

(defun yeah-subagent-fork-summary (parent-session child-session)
  "Return a summary of what CHILD-SESSION did, for PARENT-SESSION.
The summary is backed by the journal of the child: it says what the
child answered, and it names the child."
  (ignore parent-session)
  (let* ((id (yeah-subagent--find-id-by-session child-session))
         (record (and id (gethash id yeah-subagent--active))))
    (unless record
      (signal 'user-error
              (list (format "yeah-subagent-fork-summary: no active sub-agent for session %S"
                            child-session))))
    (format "[sub-agent %d] %s"
            id
            (or (plist-get record :result)
                (yeah-subagent--last-answer child-session)
                ""))))

(defun yeah-subagent-depth-limit ()
  "Return the maximum sub-agent depth."
  yeah-subagent--max-depth)

(defun yeah-subagent-reset-for-test ()
  "Drop every active sub-agent and reset the id counter.
Tests only."
  (yeah-subagent--reset-table)
  (setq yeah-subagent--next-id 0
        yeah-subagent--sessions (make-hash-table :test 'eq :size 8)))

(provide 'yeah-subagent)
;;; yeah-subagent.el ends here
