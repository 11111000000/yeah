;;; yeah-undo.el --- per-tick undo boundary -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The agent loop mutates buffers as a side effect of every
;; tool call. Strong invariant A3 requires that
;; `buffer-undo-list' carry a recoverable record around every
;; such side effect so that `M-x undo' (or programmatic
;; `undo') reverts the change cleanly.
;;
;; This module is the thin wrapper that places an
;; `(undo-boundary)' marker in the buffer before and after a
;; thunk. The boundary is recorded in the buffer's local
;; `buffer-undo-list'; one `undo' step rolls back everything
;; the thunk did.
;;
;; Public surface (see `decisions/undo-impl@0'):
;;
;;   * `yeah-undo-around-buffer BUFFER THUNK'
;;   * `yeah-undo-around-file PATH THUNK'
;;   * `yeah-undo-cleanup'
;;   * `yeah-undo-list-size BUFFER'
;;   * `yeah-undo-reset-for-test'
;;
;; Buffers opened by `yeah-undo-around-file' are tracked in
;; `yeah-undo--opened-buffers' so `yeah-undo-cleanup' can kill
;; them in LIFO order.

;;; Code:

(require 'cl-lib)

(defvar buffer-undo-list nil
  "Buffer-local undo history list (forward declaration for byte-compiler).
The real definition lives in `simple.el'; we declare it here
so that `yeah-undo-list-size' compiles without a free-variable
warning. Rebind with `setq', not `let'.")

(defgroup yeah-undo nil
  "The Yeah per-tick undo boundary."
  :group 'yeah)

(defvar yeah-undo--opened-buffers nil
  "Stack of buffers opened by `yeah-undo-around-file'.
A buffer is pushed when `find-file-noselect' is called; the
most-recently-opened buffer is at the head of the list.
`yeah-undo-cleanup' walks the list in order, killing each
buffer and emptying the stack. Rebind with `setq', not `let'.")

(defun yeah-undo-around-buffer (buffer thunk)
  "Execute THUNK inside BUFFER with an `(undo-boundary)' before and after.
BUFFER is the buffer to wrap; when `nil', the current buffer
is used. THUNK is a function of no arguments. Returns the
result of THUNK. If THUNK signals an error, the after-boundary
still runs and the error re-propagates.
`(buffer-enable-undo)' is called so the boundary is recorded
even when the buffer starts with undo disabled."
  (let ((target (or buffer (current-buffer))))
    (with-current-buffer target
      (buffer-enable-undo)
      (undo-boundary)
      (unwind-protect
          (funcall thunk)
        (undo-boundary)))))

(defun yeah-undo-around-file (path thunk)
  "Execute THUNK inside the buffer visiting PATH with an undo boundary.
PATH is a filename. If a buffer already visits PATH (per
`find-buffer-visiting'), it is used; otherwise the file is
opened via `find-file-noselect' and the resulting buffer is
recorded on `yeah-undo--opened-buffers' for later cleanup.
Returns the result of THUNK."
  (unless (stringp path)
    (signal 'user-error
            (list (format "yeah-undo-around-file: path must be a string, got %S"
                          (type-of path)))))
  (let* ((existing (find-buffer-visiting path))
         (buffer   (or existing (find-file-noselect path))))
    (unless buffer
      (signal 'user-error
              (list (format "yeah-undo-around-file: could not open buffer for %S"
                                          path))))
    (unless existing
      (setq yeah-undo--opened-buffers
            (cons buffer yeah-undo--opened-buffers)))
    (yeah-undo-around-buffer buffer thunk)))

(defun yeah-undo-cleanup ()
  "Kill every buffer opened by `yeah-undo-around-file' since the last call.
Walks `yeah-undo--opened-buffers' in LIFO order, killing each
buffer and emptying the stack. Returns the number of buffers
killed."
  (let ((--count 0)
        (stack yeah-undo--opened-buffers))
    (setq yeah-undo--opened-buffers nil)
    (dolist (buf stack)
      (when (bufferp buf)
        (when (buffer-live-p buf)
          (kill-buffer buf)
          (setq --count (1+ --count)))))
    --count))

(defun yeah-undo-list-size (buffer)
  "Return the length of BUFFER's `buffer-undo-list' as an integer.
Convenience for tests that want to assert the `(undo-boundary)'
markers were recorded. Returns 0 when undo is disabled (the
buffer-local value of `buffer-undo-list' is then `t')."
  (with-current-buffer buffer
    (let ((ul (symbol-value 'buffer-undo-list)))
      (if (listp ul) (length ul) 0))))

(defun yeah-undo-reset-for-test ()
  "Drop every opened buffer from `yeah-undo--opened-buffers'. Tests only.
Matches the `yeah-tools-reset-for-test' /
`yeah-perm-rules-reset-for-test' convention. Does not kill the
buffers themselves."
  (setq yeah-undo--opened-buffers nil))

(provide 'yeah-undo)
;;; yeah-undo.el ends here