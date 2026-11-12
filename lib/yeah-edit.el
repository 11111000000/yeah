;;; yeah-edit.el --- guarded editing tools -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Registry-ready tools for guarded in-memory edits and explicit UTF-8 file
;; writes.  Edit never saves.  The model should read fresh state before
;; retrying a rejected edit, especially after a stale modification tick.

;;; Code:

(require 'cl-lib)
(require 'yeah-result)
(require 'yeah-undo)

(defcustom yeah-edit-save-after-edit t
  "Non-nil means `edit' saves the buffer after a guarded edit.
An agent that cannot save cannot finish a coding task: the file it is
asked to fix would stay broken on disk.  Set this to nil when edits
should stay in the buffer for the person to save by hand.  The undo
boundary is recorded in both cases, so the person can revert."
  :type 'boolean
  :group 'yeah)

(defun yeah-edit--save (buffer)
  "Save BUFFER when `yeah-edit-save-after-edit' is non-nil, and return
non-nil when the buffer was saved.  Saving writes the buffer to the file
it visits; it never discards the person's unsaved changes, because those
changes live in the buffer, not in the file.  When the file changed on
disk since the buffer was read, saving is refused cleanly instead of
asking a question that a batch Emacs cannot answer."
  (with-current-buffer buffer
    (when yeah-edit-save-after-edit
      (unless (verify-visited-file-modtime buffer)
        (user-error "edit: the file changed on disk; not saving"))
      (let ((require-final-newline nil))
        (save-buffer))
      t)))

(defun yeah-edit--ok (path buffer changed)
  "Return a successful edit result for PATH, BUFFER and CHANGED."
  (let ((saved (yeah-edit--save buffer)))
    (with-current-buffer buffer
      (let ((tick (buffer-chars-modified-tick)))
        (yeah-result-ok
         (if (zerop changed)
             (format "No changes; tick %d%s." tick
                     (if saved "; saved" ""))
           (format "Replaced %d occurrence%s; tick %d%s."
                   changed (if (= changed 1) "" "s") tick
                   (if saved "; saved" "")))
         (list :path path
               :changed changed
               :tick tick
               :saved (and saved t)
               :modified (buffer-modified-p)))))))

(defun yeah-edit--match-positions (old-str)
  "Return exact match positions for OLD-STR, latest first."
  (save-restriction
    (widen)
    (save-excursion
      (save-match-data
        (let ((case-fold-search nil)
              positions)
          (goto-char (point-min))
          (while (search-forward old-str nil t)
            (push (- (point) (length old-str)) positions))
          positions)))))

(defun yeah-edit--edit-validated (path old-str new-str tick replace-all)
  "Edit PATH replacing OLD-STR with NEW-STR.
TICK is an optional expected modification tick.  REPLACE_ALL controls whether
all matches or exactly one match are accepted."
  (let ((expanded (expand-file-name path))
        (buffer (find-buffer-visiting path)))
    (unless buffer
      (unless (file-exists-p expanded)
        (user-error "edit: file does not exist: %s" expanded))
      (setq buffer (find-file-noselect expanded)))
    (with-current-buffer buffer
      (unless (verify-visited-file-modtime buffer)
        (user-error "edit: %s changed on disk; read fresh state before retrying"
                    expanded)))
    (with-current-buffer buffer
      (let ((current-tick (buffer-chars-modified-tick)))
        (if (and tick (/= tick current-tick))
            (yeah-result-error
             (format
              "edit: stale tick for %s: expected %d, current %d; read fresh state before retrying"
              expanded tick current-tick)
             (list :path expanded
                   :changed 0
                   :tick current-tick
                   :modified (buffer-modified-p)))
          (if (string= old-str new-str)
              (yeah-edit--ok expanded buffer 0)
            (let ((positions (yeah-edit--match-positions old-str)))
              (cond
               ((null positions)
                (yeah-result-error
                 (format "edit: old_str not found in %s; read fresh state before retrying"
                         expanded)
                 (list :path expanded :changed 0 :tick current-tick)))
               ((and (not replace-all) (cdr positions))
                (yeah-result-error
                 (format
                  "edit: old_str must match exactly once in %s (found %d); read fresh state before retrying"
                  expanded (length positions))
                 (list :path expanded :changed 0 :tick current-tick)))
               (t
                (save-restriction
                  (widen)
                  (save-excursion
                    (yeah-undo-around-buffer
                     buffer
                     (lambda ()
                       (atomic-change-group
                         (dolist (start positions)
                           (goto-char start)
                           (delete-region start (+ start (length old-str)))
                           (insert new-str)))))))
                (yeah-edit--ok expanded buffer (length positions)))))))))))

(defun yeah-edit--edit (path old-str new-str &optional tick replace-all)
  "Return a structured result for a guarded edit of PATH.
OLD_STR must be nonempty.  NEW_STR may be empty.  TICK, when non-nil, must
match `buffer-chars-modified-tick'.  REPLACE_ALL permits multiple matches."
  (condition-case err
      (progn
        (unless (and (stringp path) (not (string= path "")))
          (user-error "edit: path must be a nonempty string"))
        (unless (and (stringp old-str) (not (string= old-str "")))
          (user-error "edit: old_str must be a nonempty string"))
        (unless (stringp new-str)
          (user-error "edit: new_str must be a string"))
        (when (and tick (not (integerp tick)))
          (user-error "edit: tick must be an integer"))
        (when (and replace-all (not (booleanp replace-all)))
          (user-error "edit: replace_all must be a boolean"))
        (yeah-edit--edit-validated path old-str new-str tick replace-all))
    (error
     (yeah-result-error (error-message-string err)))))

(defun yeah-edit--write (path content &optional overwrite)
  "Write CONTENT to PATH as UTF-8 and return a structured result.
Refuse an existing PATH unless OVERWRITE is non-nil."
  (condition-case err
      (progn
        (unless (and (stringp path) (not (string= path "")))
          (user-error "write: path must be a nonempty string"))
        (unless (stringp content)
          (user-error "write: content must be a string"))
        (when (and overwrite (not (booleanp overwrite)))
          (user-error "write: overwrite must be a boolean"))
        (let* ((expanded (expand-file-name path))
               (existed (file-exists-p expanded))
               (bytes (length (encode-coding-string content 'utf-8))))
          (if (and existed (not overwrite))
              (yeah-result-error
               (format "write: file exists; set overwrite to true to replace %s"
                       expanded)
               (list :path expanded :overwritten nil))
            (let ((coding-system-for-write 'utf-8))
              (with-temp-buffer
                (insert content)
                (write-region (point-min) (point-max) expanded nil 'silent nil
                              (unless overwrite 'excl))))
            (yeah-result-ok
             (format "%s %s (%d bytes)."
                     (if existed "Overwrote" "Created") expanded bytes)
             (list :path expanded
                   :bytes bytes
                   :characters (length content)
                   :overwritten (and existed t))))))
    (error
     (yeah-result-error (error-message-string err)))))

(defun yeah-edit-tools ()
  "Return guarded Edit and Write specifications for Yeah's tool registry."
  (list
   (list :name "edit"
         :description
         "Replace exact text in a visiting buffer or a file opened in a buffer. old_str must be nonempty and match exactly once unless replace_all is true. When supplied, tick guards against stale buffer state; pass the tick from the result of the read tool, or omit it to skip the guard. The edit is one undo step and the buffer is saved (see `yeah-edit-save-after-edit'). After any rejection, read fresh state before retrying with a fresh tick."
         :input (list (list :name "path" :type 'string)
                      (list :name "old_str" :type 'string)
                      (list :name "new_str" :type 'string)
                      (list :name "tick" :type 'integer :optional t)
                      (list :name "replace_all" :type 'boolean :optional t))
         :handler #'yeah-edit--edit
         :concurrency 'exclusive)
   (list :name "write"
         :description
         "Write UTF-8 content to a new file. Existing files are refused unless overwrite is true; edit changes buffers but this is the tool that writes files."
         :input (list (list :name "path" :type 'string)
                      (list :name "content" :type 'string)
                      (list :name "overwrite" :type 'boolean :optional t))
         :handler #'yeah-edit--write
         :concurrency 'exclusive)))

(provide 'yeah-edit)
;;; yeah-edit.el ends here
