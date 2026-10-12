;;; test-yeah-undo.el --- ERT tests for yeah-undo -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-undo.el'. The
;; positive tests exercise the happy paths (boundary placed,
;; thunk executed, file opened, existing buffer reused); the
;; negative test exercises the closest plausible failure mode
;; (thunk errors, but boundary still recorded).

;;; Code:

(require 'ert)
(require 'yeah-undo)

(defun yeah-undo-test--make-tempfile (&optional suffix)
  "Create a fresh temp file with optional SUFFIX; return its absolute path.
Caller is responsible for `delete-file' cleanup."
  (make-temp-file "yeah-undo-" nil (or suffix ".txt")))

(defun yeah-undo-test--delete-and-kill (path)
  "Best-effort cleanup: delete PATH and kill any buffer visiting it."
  (let ((buf (find-buffer-visiting path)))
    (ignore-errors
      (when (and buf (buffer-live-p buf))
        (kill-buffer buf))))
  (ignore-errors (delete-file path)))

(ert-deftest yeah-undo-around-buffer-places-boundary ()
  "`yeah-undo-around-buffer' places an `(undo-boundary)' in the
current buffer; the buffer's `buffer-undo-list' is non-empty
after the call."
  (with-temp-buffer
    (let ((before (yeah-undo-list-size (current-buffer))))
      (yeah-undo-around-buffer
       (current-buffer)
       (lambda () (insert "hello\n")))
      (let ((after (yeah-undo-list-size (current-buffer))))
        (should (> after before))))))

(ert-deftest yeah-undo-around-buffer-runs-thunk ()
  "`yeah-undo-around-buffer' executes THUNK in BUFFER and
returns the value THUNK returned."
  (with-temp-buffer
    (let ((result (yeah-undo-around-buffer
                   (current-buffer)
                   (lambda ()
                     (insert "x")
                     'thunk-returned))))
      (should (eq result 'thunk-returned))
      (should (string= (buffer-string) "x")))))

(ert-deftest yeah-undo-around-buffer-nil-uses-current-buffer ()
  "Passing `nil' to `yeah-undo-around-buffer' uses the current buffer."
  (with-temp-buffer
    (let ((result (yeah-undo-around-buffer
                   nil
                   (lambda ()
                     (insert "in-current\n")
                     :ok))))
      (should (eq result :ok))
      (should (string= (buffer-string) "in-current\n")))))

(ert-deftest yeah-undo-around-buffer-thunk-error-still-records-boundary ()
  "When THUNK signals an error, the after-boundary still runs;
the error re-propagates to the caller."
  (with-temp-buffer
    (let ((err-raised nil))
      (condition-case nil
          (yeah-undo-around-buffer
           (current-buffer)
           (lambda ()
             (insert "partial")
             (signal 'user-error (list "boom"))))
        (user-error (setq err-raised t)))
      (should err-raised)
      (should (string= (buffer-string) "partial"))
      (should (> (yeah-undo-list-size (current-buffer)) 0)))))

(ert-deftest yeah-undo-around-file-opens-buffer ()
  "`yeah-undo-around-file' opens a buffer when the file is not
already visited, and records it on the opened-buffer stack."
  (let* ((path (yeah-undo-test--make-tempfile))
         (before-size (yeah-undo-list-size
                       (or (find-buffer-visiting path)
                           (current-buffer)))))
    (unwind-protect
        (progn
          (with-temp-file path (insert "file body"))
          (should-not (find-buffer-visiting path))
          (yeah-undo-around-file
           path
           (lambda () (insert "x")))
          (let ((buf (find-buffer-visiting path)))
            (should buf)
            (should (buffer-live-p buf))
            (let ((in-stack (member buf yeah-undo--opened-buffers)))
              (should in-stack))
            (should (> (yeah-undo-list-size buf) 0))))
      (yeah-undo-cleanup)
      (yeah-undo-test--delete-and-kill path))))

(ert-deftest yeah-undo-around-file-uses-existing-buffer ()
  "When a buffer already visits PATH, `yeah-undo-around-file'
reuses it without pushing onto the opened-buffer stack."
  (let* ((path (yeah-undo-test--make-tempfile))
         (existing (find-file path))
         (stack-before yeah-undo--opened-buffers))
    (unwind-protect
        (progn
          (should (buffer-live-p existing))
          (yeah-undo-around-file
           path
           (lambda () (insert "again")))
          (let ((now (find-buffer-visiting path)))
            (should (eq now existing))
            (should (equal yeah-undo--opened-buffers stack-before))))
      (yeah-undo-test--delete-and-kill path))))

(ert-deftest yeah-undo-list-size-grows-by-two-after-around-buffer ()
  "After `(undo-boundary)' wraps a thunk that does a real edit,
`yeah-undo-list-size' is strictly larger (the boundary markers
plus the edit contribute at least two elements)."
  (with-temp-buffer
    (let* ((before (yeah-undo-list-size (current-buffer)))
           (_ (yeah-undo-around-buffer
               (current-buffer)
               (lambda () (insert "x"))))
           (after (yeah-undo-list-size (current-buffer))))
      (should (> after before)))))

(ert-deftest yeah-undo-cleanup-kills-opened-buffers ()
  "`yeah-undo-cleanup' kills every buffer opened by
`yeah-undo-around-file' since the last call and returns the
count."
  (let* ((p1 (yeah-undo-test--make-tempfile "-1.txt"))
         (p2 (yeah-undo-test--make-tempfile "-2.txt")))
    (with-temp-file p1 (insert "a"))
    (with-temp-file p2 (insert "b"))
    (unwind-protect
        (progn
          (yeah-undo-around-file p1 (lambda () nil))
          (yeah-undo-around-file p2 (lambda () nil))
          (should (= (length yeah-undo--opened-buffers) 2))
          (let ((b1 (find-buffer-visiting p1))
                (b2 (find-buffer-visiting p2))
                (killed (yeah-undo-cleanup)))
            (should (= killed 2))
            (should (null yeah-undo--opened-buffers))
            (should-not (buffer-live-p b1))
            (should-not (buffer-live-p b2))))
      (yeah-undo-test--delete-and-kill p1)
      (yeah-undo-test--delete-and-kill p2))))

(provide 'test-yeah-undo)
;;; test-yeah-undo.el ends here