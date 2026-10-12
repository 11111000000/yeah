;;; yeah-subagent.el --- sub-agent delegation API (stub) -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A sub-agent is a child gptel session that runs in its own
;; buffer and returns a summary to the parent when it finishes.
;; The sub-agent inherits the parent's `yeah-session' root and
;; the parent's `yeah-tools' registry reference but has its own
;; message log and its own buffer.
;;
;; Public API (see `decisions/subagent-impl@0'):
;;
;;   * `yeah-subagent-spawn PARENT-SESSION ROLE PROMPT &optional DEPTH'
;;   * `yeah-subagent-wait CHILD-ID'
;;   * `yeah-subagent-fork-summary PARENT-SESSION CHILD-SESSION'
;;   * `yeah-subagent-depth-limit'
;;   * `yeah-subagent-reset-for-test'
;;
;; This module is a **stub**. The child does not actually run
;; gptel asynchronously; the replacement hook is documented
;; inline and lands with `subagent-impl@1'.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)

(defgroup yeah-subagent nil
  "Yeah sub-agent delegation API."
  :group 'yeah)

(defvar yeah-subagent--max-depth 3
  "Maximum sub-agent depth. The top-level loop is at depth 0.
Spawning a child whose depth would be equal to or greater than
this value raises `user-error'. Rebind with `setq', not `let'.")

(defvar yeah-subagent--active (make-hash-table :test 'eq :size 8)
  "Hash table mapping a child id (integer) to the child's
result plist. The plist has shape

  (:id ID :role STRING :prompt STRING :depth INTEGER
   :child-session SESSION :status SYMBOL :result STRING)

Rebind with `setq', not `let'.")

(defvar yeah-subagent--next-id 0
  "Next monotonic child id to assign. Rebind with `setq', not `let'.")

(defun yeah-subagent--reset-table ()
  "Replace the active-sub-agents hash with a fresh empty one."
  (setq yeah-subagent--active (make-hash-table :test 'eq :size 8)))

(defun yeah-subagent--root-from (session)
  "Return the root directory of `session', the directory that
holds the `sessions/' subdir holding the JSONL file. Recovered
by walking up two levels from the `:path'."
  (let ((path (plist-get session :path)))
    (when (stringp path)
      (let* ((dir (file-name-directory path))
             (sessions-dir (and dir (directory-file-name dir)))
             (root (and sessions-dir
                        (file-name-directory
                         (directory-file-name sessions-dir)))))
        (when root
          (directory-file-name root))))))

(defun yeah-subagent--buffer-name (role id)
  "Return the buffer name for a child with ROLE and id ID."
  (format "*yeah-subagent-%s-%d*" role id))

(defun yeah-subagent--validate-spawn-args (parent-session role prompt depth)
  "Validate the args of a call to `yeah-subagent-spawn'.
Signals `user-error' on a bad shape. Returns nil."
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
  (let ((child-depth (1+ depth))
        (limit       yeah-subagent--max-depth))
    (when (>= child-depth limit)
      (signal 'user-error
              (list (format
                      "yeah-subagent-spawn: child depth %d would exceed limit %d"
                      child-depth limit)))))
  nil)

(defun yeah-subagent--stub-result (prompt)
  "Return the placeholder result string for the stub.
Echoes the first 80 characters of PROMPT so tests can assert
that the prompt reached the child."
  (let ((snippet (substring prompt 0 (min (length prompt) 80))))
    (format "stub: %s" snippet)))

(defun yeah-subagent-spawn (parent-session role prompt &optional depth)
  "Spawn a child sub-agent and return its result plist.

PARENT-SESSION is the parent's session plist (from
`yeah-session-open'). ROLE is a string identifying the role
the child plays (e.g. \"explore\", \"review\", \"worker\").
PROMPT is the user message. DEPTH is the depth of the caller
in the sub-agent tree; the top-level loop passes 0; a child at
depth 1 passes 1. The child's depth is `1+ DEPTH'.

Signals `user-error' when the child's depth would be equal to
or greater than `yeah-subagent-depth-limit'. The child
session is a new `yeah-session-open' under the parent's root
directory. The child has its own buffer named
`*yeah-subagent-<ROLE>-<id>*'.

This is a **stub**: it does not actually run gptel. The
result plist has shape

  (:id ID :role ROLE :prompt PROMPT :depth CHILD-DEPTH
   :child-session SESSION :status completed :result STRING)

and is also stored in `yeah-subagent--active' under ID for
later lookup by `yeah-subagent-wait' or
`yeah-subagent-fork-summary'.

DEPTH defaults to 0 (top-level loop)."
  (let ((d (or depth 0)))
    (yeah-subagent--validate-spawn-args parent-session role prompt d)
    (let* ((root             (yeah-subagent--root-from parent-session))
           (parent-id        (plist-get parent-session :id))
           (child-id         yeah-subagent--next-id)
           (child-session-id (format "%s.sub-%d" parent-id child-id))
           (child-session    (yeah-session-open child-session-id root))
           (child-depth      (1+ d))
           (result-string    (yeah-subagent--stub-result prompt))
           (record (list :id child-id
                         :role role
                         :prompt prompt
                         :depth child-depth
                         :child-session child-session
                         :status 'completed
                         :result result-string)))
      (setq yeah-subagent--next-id (1+ yeah-subagent--next-id))
      (puthash child-id record yeah-subagent--active)
      (let ((child-buffer-name (yeah-subagent--buffer-name role child-id)))
        (condition-case nil
            (get-buffer-create child-buffer-name)
          (error nil)))
      record)))

(defun yeah-subagent-wait (child-id)
  "Return the result plist for CHILD-ID.
The stub is synchronous: the result is the one recorded at
spawn time, with `:status completed'. Signals `user-error'
if CHILD-ID does not name an active sub-agent."
  (let ((record (gethash child-id yeah-subagent--active)))
    (unless record
      (signal 'user-error
              (list (format "yeah-subagent-wait: no active sub-agent %S"
                            child-id))))
    record))

(defun yeah-subagent--find-id-by-session (child-session)
  "Return the child id whose `:child-session' equals CHILD-SESSION,
or nil if no such child exists."
  (let ((target child-session)
        (found  nil))
    (maphash
     (lambda (id record)
       (when (and (null found)
                  (eq (plist-get record :child-session) target))
         (setq found id)))
     yeah-subagent--active)
    found))

(defun yeah-subagent-fork-summary (parent-session child-session)
  "Return a one-line summary string for CHILD-SESSION.
The summary has shape `[sub-agent N] <result>' where N is the
child id and `<result>' is the result string recorded at
spawn time. PARENT-SESSION is accepted for symmetry with the
public API but is not used to compute the summary.

Signals `user-error' if CHILD-SESSION does not name an
active sub-agent."
  (ignore parent-session)
  (let* ((id     (yeah-subagent--find-id-by-session child-session))
         (record (and id (gethash id yeah-subagent--active))))
    (unless record
      (signal 'user-error
              (list (format "yeah-subagent-fork-summary: no active sub-agent for session %S"
                            child-session))))
    (let ((result-string (plist-get record :result)))
      (format "[sub-agent %d] %s" id result-string))))

(defun yeah-subagent-depth-limit ()
  "Return the maximum sub-agent depth.
Reads the dynamic `yeah-subagent--max-depth' so tests can
override the value with `setq'."
  yeah-subagent--max-depth)

(defun yeah-subagent-reset-for-test ()
  "Drop every active sub-agent and reset the id counter.
Tests only. Matches the convention of
`yeah-tools-reset-for-test' and `yeah-perm-rules-reset-for-test'."
  (yeah-subagent--reset-table)
  (setq yeah-subagent--next-id 0))

(provide 'yeah-subagent)
;;; yeah-subagent.el ends here