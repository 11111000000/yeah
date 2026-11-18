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
(require 'yeah-untrusted)
(require 'yeah-version)

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
               :version (yeah-version-file path)
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

(defun yeah-edit--edit-validated (path old-str new-str expected-tick replace-all expected-version)
  "Edit PATH replacing OLD-STR with NEW-STR.
EXPECTED-TICK is an optional expected modification tick.  REPLACE_ALL controls
whether all matches or exactly one match are accepted.  EXPECTED-VERSION is an
optional expected version token of the file."
  ;; A tick is a promise about the state the model saw, and only a buffer
  ;; that visits the file can hand out a tick.  When no buffer visits the
  ;; file, the model had no tick to read, so the number it sends is a
  ;; guess; comparing a guess with the counter of Emacs refuses an edit of
  ;; a file that did not change.  A guessed tick is ignored, and the guard
  ;; keeps the ticks that a read could have handed out.
  (let* ((expanded (expand-file-name path))
         (existing (find-buffer-visiting expanded))
         (buffer existing)
         (tick (if existing expected-tick nil))
         (refusal nil))
    (unless buffer
      (unless (file-exists-p expanded)
        (user-error "edit: file does not exist: %s" expanded))
      ;; The file belongs to an untrusted project.  Emacs runs the local
      ;; variables of a file and the directory-local variables of its
      ;; directory when it opens it, and that code is the code of the
      ;; project: the harness does not run it in the Emacs of the person.
      (setq buffer (yeah-untrusted-open-file expanded)))
    (with-current-buffer buffer
      (unless (verify-visited-file-modtime buffer)
        (user-error "edit: %s changed on disk; read fresh state before retrying"
                    expanded)))
    ;; A version token is the guard of the file that no buffer visits.  The
    ;; read that handed it out saw the file on disk, and the token says
    ;; which file that was; when the file changed since that read, the edit
    ;; would land on text the model never read, so it is refused.
    ;;
    ;; The refusal names the token and not the file: a token that was copied
    ;; wrong does not mean that the file changed, and a model that is told
    ;; about a change that did not happen goes looking for one.
    (when expected-version
      (let ((current-version (yeah-version-file expanded)))
        (cond
         ((not (equal current-version expected-version))
          (setq refusal
                (yeah-result-error
                 (format "edit: stale version for %s; the version you present is not the version of the file now. The file may be unchanged and the token may have been copied wrong; read the file again and use the version it reports"
                         expanded)
                 (list :path expanded
                       :changed 0
                       :version current-version)))))))
    ;; A read of a file shows the disk, and the tick it hands out belongs to
    ;; the buffer that visits the file.  When Emacs holds unsaved changes of
    ;; that file, an edit lands on the buffer and overwrites the changes of
    ;; the person with text the model never read.  The refusal does not
    ;; depend on a version: a model that presents no version has seen the
    ;; same disk and deserves the same answer.  D5 promises this of every
    ;; edit, and the code kept it only for the edits that presented a
    ;; version.
    (if refusal
        refusal
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
            (if (with-current-buffer buffer (buffer-modified-p))
                (yeah-result-error
                 (format "edit: %s has unsaved changes in Emacs that a read cannot show; ask the person to save them before editing"
                         expanded)
                 (list :path expanded
                       :changed 0))
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
                    (yeah-edit--ok expanded buffer (length positions)))))))))))))

(defun yeah-edit--edit (path old-str new-str &optional tick replace-all version)
  "Return a structured result for a guarded edit of PATH.
OLD_STR must be nonempty.  NEW_STR may be empty.  TICK, when non-nil, must
match `buffer-chars-modified-tick'.  REPLACE_ALL permits multiple matches.
VERSION, when non-nil, must be the version token of the file as a read
reported it."
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
        (when (and version (not (stringp version)))
          (user-error "edit: version must be a string"))
        (yeah-edit--edit-validated path old-str new-str tick replace-all version))
    (error
     (yeah-result-error (error-message-string err)))))

(defun yeah-edit--write (path content &optional overwrite version)
  "Write CONTENT to PATH as UTF-8 and return a structured result.
Refuse an existing PATH unless OVERWRITE is non-nil.
VERSION, when non-nil, must be the version token of the file as a read
reported it.  A write that replaces a file whose version has changed since
that read is refused, so that a write never lands on a file the model did not
read."
  (condition-case err
      (progn
        (unless (and (stringp path) (not (string= path "")))
          (user-error "write: path must be a nonempty string"))
        (unless (stringp content)
          (user-error "write: content must be a string"))
        (when (and overwrite (not (booleanp overwrite)))
          (user-error "write: overwrite must be a boolean"))
        (when (and version (not (stringp version)))
          (user-error "write: version must be a string"))
        (let* ((expanded (expand-file-name path))
               (existed (file-exists-p expanded))
               (bytes (length (encode-coding-string content 'utf-8)))
               (current-version (and existed (yeah-version-file expanded))))
          (cond
           ((and existed (not overwrite))
            (yeah-result-error
             (format "write: file exists; set overwrite to true to replace %s"
                     expanded)
             (list :path expanded :overwritten nil)))
           ((and existed version (not (equal current-version version)))
            (yeah-result-error
             (format "write: stale version for %s; the version you present is not the version of the file now. The file may be unchanged and the token may have been copied wrong; read the file again and use the version it reports"
                     expanded)
             (list :path expanded
                   :changed 0
                   :version current-version)))
           (t
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
                   :overwritten (and existed t)))))))
    (error
     (yeah-result-error (error-message-string err)))))

(defun yeah-edit-tools ()
  "Return guarded Edit and Write specifications for Yeah's tool registry."
  (list
   (list :name "edit"
         :description
         "Replace exact text in a file, guarded by an optional modification tick and an optional version token. old_str must be nonempty and must match exactly once unless replace_all is true. tick is optional: pass the tick that the read of this file reported; the edit is refused when the file changed since that tick was taken, and the refusal reports the current tick, so you can retry with it. If the read of the file reported no tick, omit tick: a tick that no read handed out is ignored, and omitting tick edits the file without that guard. version is optional in the same way: pass the short version token that the read of this file reported, and the edit is refused when that token is not the version of the file now, so an edit never lands on a file you did not read. A token that does not match may have been copied wrong and not mean that the file changed: the refusal names the token, reports the current one, and you can retry with it. An edit of a file that Emacs holds unsaved changes of is refused as well, with or without a token: a read of the disk cannot show them, and the refusal asks the person to save the file first. The replacement is one undo step, and the file is saved unless yeah-edit-save-after-edit is nil. After a refusal, read the file again before retrying."
         :input (list (list :name "path" :type 'string)
                      (list :name "old_str" :type 'string)
                      (list :name "new_str" :type 'string)
                      (list :name "tick" :type 'integer :optional t)
                      (list :name "replace_all" :type 'boolean :optional t)
                      (list :name "version" :type 'string :optional t))
         :kind "edit"
         :handler #'yeah-edit--edit
         :concurrency 'exclusive)
   (list :name "write"
         :description
         "Write UTF-8 content to a new file, creating it. An existing file is refused unless overwrite is true; to change part of a file that already exists, use the edit tool instead. version is optional: pass the short version token that the read of this file reported, and the write is refused when that token is not the version of the file now, so that a write never lands on a file you did not read. A token that does not match may have been copied wrong and not mean that the file changed: the refusal names the token and reports the current one, and you can retry with it. A write of a file that does not exist needs no token."
         :input (list (list :name "path" :type 'string)
                      (list :name "content" :type 'string)
                      (list :name "overwrite" :type 'boolean :optional t)
                      (list :name "version" :type 'string :optional t))
         :kind "edit"
         :handler #'yeah-edit--write
         :concurrency 'exclusive)))

(provide 'yeah-edit)
;;; yeah-edit.el ends here
