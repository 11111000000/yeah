;;; yeah-input.el --- persistent pending user inputs -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Pending inputs are a bounded, per-session FIFO stored as Lisp data.  Loading
;; a queue never executes its inputs.  Every mutation is written to a temporary
;; file in the queue directory and atomically renamed into place.

;;; Code:

(require 'cl-lib)

(defvar read-eval nil
  "Disable read-time evaluation when restoring pending input data.")

(defgroup yeah-input nil
  "Persistent pending user input."
  :group 'yeah)

(defcustom yeah-input-directory
  (expand-file-name "yeah/pending/" user-emacs-directory)
  "Directory containing per-session pending input queues."
  :type 'directory
  :group 'yeah-input)

(defconst yeah-input--max-entries 8)
(defconst yeah-input--max-bytes 262144)

(defun yeah-input--plist-p (value)
  "Return non-nil when VALUE is a proper plist with symbol keys."
  (and (proper-list-p value)
       (zerop (% (length value) 2))
       (cl-loop for tail on value by #'cddr
                always (symbolp (car tail)))))

(defun yeah-input--serializable-p (value &optional seen)
  "Return non-nil when VALUE consists of readable, acyclic Lisp data.
SEEN tracks conses and vectors along the current recursion path."
  (cond
   ((or (stringp value) (numberp value) (symbolp value)) t)
   ((or (consp value) (vectorp value))
    (let ((seen (or seen (make-hash-table :test #'eq))))
      (and (not (gethash value seen))
           (progn
             (puthash value t seen)
             (prog1
                 (if (vectorp value)
                     (cl-loop for item across value
                              always (yeah-input--serializable-p item seen))
                   (and (yeah-input--serializable-p (car value) seen)
                        (yeah-input--serializable-p (cdr value) seen)))
               (remhash value seen))))))
   (t nil)))

(defun yeah-input--session-id (session)
  "Return SESSION's validated id."
  (unless (yeah-input--plist-p session)
    (user-error "yeah-input: SESSION must be a plist"))
  (let ((session-id (plist-get session :id)))
    (unless (and (stringp session-id) (> (length session-id) 0))
      (user-error "yeah-input: SESSION :id must be a nonempty string"))
    session-id))

(defun yeah-input--path (session-id)
  "Return the queue path for validated SESSION-ID."
  (let ((filename (concat (secure-hash
                           'sha256 (encode-coding-string session-id 'utf-8))
                          ".eld")))
    (expand-file-name
     filename
     (file-name-as-directory (expand-file-name yeah-input-directory)))))

(defun yeah-input--new-id (session-id input existing)
  "Return a fresh input id for SESSION-ID, INPUT and EXISTING entries."
  (let ((nonce 0)
        candidate)
    (while
        (progn
          (setq candidate
                (format "input-%s"
                        (secure-hash
                         'sha256
                         (format "%S-%S-%S-%S-%S-%d"
                                 session-id input (float-time) (emacs-pid)
                                 (make-temp-name "input") nonce))))
          (cl-find candidate existing
                   :key (lambda (entry) (plist-get entry :id))
                   :test #'string=))
      (setq nonce (1+ nonce)))
    candidate))

(defun yeah-input--normalize (input session-id existing &optional stored)
  "Return INPUT in canonical form.
SESSION-ID and EXISTING are used for id generation and uniqueness.  When
STORED is non-nil, ids and timestamps must already be present and the complete
stored shape is required."
  (unless (and (yeah-input--plist-p input)
               (cl-loop for tail on input by #'cddr
                        always (memq (car tail)
                                     '(:kind :prompt :frozen :id :created-at)))
               (plist-member input :kind)
               (plist-member input :prompt)
               (plist-member input :frozen)
               (or (not stored)
                   (and (= (length input) 10)
                        (plist-member input :id)
                        (plist-member input :created-at))))
    (user-error "yeah-input: malformed input plist"))
  (let ((kind (plist-get input :kind))
        (prompt (plist-get input :prompt))
        (frozen (plist-get input :frozen))
        (id (if (plist-member input :id)
                (plist-get input :id)
              (yeah-input--new-id session-id input existing)))
        (created-at (if (plist-member input :created-at)
                        (plist-get input :created-at)
                      (format-time-string "%Y-%m-%dT%H:%M:%S%z"))))
    (unless (memq kind '(ask steering))
      (user-error "yeah-input: :kind must be `ask' or `steering'"))
    (unless (stringp prompt)
      (user-error "yeah-input: :prompt must be a string"))
    (unless (yeah-input--plist-p frozen)
      (user-error "yeah-input: :frozen must be a plist"))
    (unless (yeah-input--serializable-p frozen)
      (user-error "yeah-input: :frozen must contain serializable data"))
    (unless (and (stringp id) (> (length id) 0))
      (user-error "yeah-input: :id must be a nonempty string"))
    (when (cl-find id existing
                   :key (lambda (entry) (plist-get entry :id))
                   :test #'string=)
      (user-error "yeah-input: duplicate input id"))
    (unless (and (stringp created-at) (> (length created-at) 0))
      (user-error "yeah-input: :created-at must be a nonempty string"))
    (list :kind kind :prompt prompt :frozen (copy-tree frozen)
          :id id :created-at created-at)))

(defun yeah-input--payload-bytes (content)
  "Return the number of bytes in CONTENT encoded as UTF-8."
  (string-bytes (encode-coding-string content 'utf-8)))

(defun yeah-input--serialize (queue)
  "Serialize QUEUE as one readable Lisp form."
  (let ((print-length nil)
        (print-level nil)
        (print-circle nil))
    (concat (prin1-to-string queue) "\n")))

(defun yeah-input--read-queue (path session-id)
  "Read and validate SESSION-ID's queue at PATH.
A missing file is an empty queue.  Any invalid existing file signals
`user-error' and is left untouched."
  (if (not (file-exists-p path))
      nil
    (condition-case err
        (progn
          (when (> (file-attribute-size (file-attributes path))
                   yeah-input--max-bytes)
            (user-error "pending input file exceeds the byte limit"))
          (with-temp-buffer
            (let ((coding-system-for-read 'utf-8-unix))
              (insert-file-contents path))
            (goto-char (point-min))
            (let ((read-eval nil)
                  data)
              (setq data (read (current-buffer)))
              (skip-chars-forward " \t\r\n\f")
              (unless (eobp)
                (user-error "pending input file contains trailing data"))
              (unless (proper-list-p data)
                (user-error "pending input file must contain a list"))
              (when (> (length data) yeah-input--max-entries)
                (user-error "pending input file exceeds the entry limit"))
              (let (queue)
                (dolist (input data)
                  (setq queue
                        (append queue
                                (list (yeah-input--normalize
                                       input session-id queue t)))))
                queue))))
      (error
       (signal 'user-error
               (list (format "yeah-input: invalid queue %s: %s"
                             path (error-message-string err))))))))

(defun yeah-input--write-queue (session-id queue)
  "Atomically persist SESSION-ID's QUEUE with private permissions."
  (when (> (length queue) yeah-input--max-entries)
    (user-error "yeah-input: pending input is limited to %d entries"
                yeah-input--max-entries))
  (let ((content (yeah-input--serialize queue)))
    (when (> (yeah-input--payload-bytes content) yeah-input--max-bytes)
      (user-error "yeah-input: pending input exceeds %d UTF-8 bytes"
                  yeah-input--max-bytes))
    (let* ((directory (file-name-as-directory
                       (expand-file-name yeah-input-directory)))
           (path (yeah-input--path session-id)))
      (make-directory directory t)
      (set-file-modes directory #o700)
      (let ((temporary (make-temp-file
                        (expand-file-name ".pending-" directory) nil ".eld")))
        (unwind-protect
            (progn
              (let ((coding-system-for-write 'utf-8-unix))
                (with-temp-buffer
                  (insert content)
                  (write-region (point-min) (point-max) temporary nil 'silent)))
              (set-file-modes temporary #o600)
              (rename-file temporary path t)
              (setq temporary nil))
          (when (and temporary (file-exists-p temporary))
            (delete-file temporary)))))))

(defun yeah-input-enqueue (session input)
  "Validate INPUT, append it to SESSION's FIFO, and return its normal form.
INPUT requires :kind (`ask' or `steering'), a string :prompt and a serializable
plist :frozen.  Missing string :id and :created-at fields are generated.  The
queue is persisted before this function returns.  Either limit rejects the new
input without evicting an older one."
  (let* ((session-id (yeah-input--session-id session))
         (queue (yeah-input--read-queue
                 (yeah-input--path session-id) session-id)))
    (when (>= (length queue) yeah-input--max-entries)
      (user-error "yeah-input: pending input is limited to %d entries"
                  yeah-input--max-entries))
    (let ((normalized (yeah-input--normalize input session-id queue)))
      (yeah-input--write-queue session-id (append queue (list normalized)))
      normalized)))

(defun yeah-input-pending (session)
  "Return SESSION's queued inputs oldest first without executing them."
  (let ((session-id (yeah-input--session-id session)))
    (yeah-input--read-queue (yeah-input--path session-id) session-id)))

(defun yeah-input-pop (session)
  "Remove and return SESSION's oldest input, or nil when its queue is empty."
  (let* ((session-id (yeah-input--session-id session))
         (queue (yeah-input--read-queue
                 (yeah-input--path session-id) session-id)))
    (when queue
      (yeah-input--write-queue session-id (cdr queue)))
    (car queue)))

(defun yeah-input-withdraw (session id)
  "Remove and return the input identified by ID from SESSION.
Return nil when ID is absent.  A removal is persisted before returning."
  (unless (and (stringp id) (> (length id) 0))
    (user-error "yeah-input: ID must be a nonempty string"))
  (let* ((session-id (yeah-input--session-id session))
         (queue (yeah-input--read-queue
                 (yeah-input--path session-id) session-id))
         found
         remaining)
    (dolist (entry queue)
      (if (and (not found) (string= id (plist-get entry :id)))
          (setq found entry)
        (push entry remaining)))
    (when found
      (yeah-input--write-queue session-id (nreverse remaining)))
    found))

(defun yeah-input-take (session kind)
  "Remove and return the oldest input of KIND in SESSION, or nil.
KIND is `ask' or `steering'.  The other inputs keep their order."
  (unless (memq kind '(ask steering))
    (user-error "yeah-input: KIND must be `ask' or `steering'"))
  (let* ((session-id (yeah-input--session-id session))
         (queue (yeah-input--read-queue
                 (yeah-input--path session-id) session-id))
         (taken nil)
         (remaining nil))
    (dolist (entry queue)
      (if (and (null taken) (eq kind (plist-get entry :kind)))
          (setq taken entry)
        (push entry remaining)))
    (when taken
      (yeah-input--write-queue session-id (nreverse remaining)))
    taken))

(defun yeah-input-rekind (session id kind)
  "Change the kind of the pending input ID in SESSION to KIND.
KIND is `ask' or `steering'.  Return the changed input, or nil when
there is no such input.  The change is persisted before returning."
  (unless (and (stringp id) (> (length id) 0))
    (user-error "yeah-input: ID must be a nonempty string"))
  (unless (memq kind '(ask steering))
    (user-error "yeah-input: KIND must be `ask' or `steering'"))
  (let* ((session-id (yeah-input--session-id session))
         (queue (yeah-input--read-queue
                 (yeah-input--path session-id) session-id))
         (changed nil)
         (remaining nil))
    (dolist (entry queue)
      (if (and (null changed) (string= id (plist-get entry :id)))
          (setq changed (plist-put (copy-tree entry) :kind kind))
        (push entry remaining)))
    (when changed
      (yeah-input--write-queue session-id (nreverse remaining)))
    changed))

(defun yeah-input-count (session)
  "Return the number of pending inputs in SESSION."
  (length (yeah-input-pending session)))

(provide 'yeah-input)
;;; yeah-input.el ends here
