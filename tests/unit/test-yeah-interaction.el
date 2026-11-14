;;; test-yeah-interaction.el --- ERT tests for Yeah interaction components -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-approval-ui)
(require 'yeah-compose)
(require 'yeah-diff)
(require 'yeah-doctor-ui)
(require 'yeah-session-list)

(defun yeah-interaction-test--temporary-file (content)
  "Return a path to a temporary file containing CONTENT."
  (let ((path (make-temp-file "yeah-interaction" nil)))
    (with-temp-buffer
      (insert content)
      (write-region (point-min) (point-max) path nil 'silent))
    path))

(ert-deftest yeah-compose-sends-text-and-explicit-context ()
  (let ((sent nil))
    (let* ((buffer (yeah-compose-open
                    (lambda (text context)
                      (setq sent (list text context)))
                    :ask "hello"))
           (file (yeah-interaction-test--temporary-file "content")))
      (unwind-protect
          (progn
            (with-current-buffer buffer
              (setq yeah-compose--context (list :file file)))
            (yeah-compose-send))
        (when (buffer-live-p buffer) (kill-buffer buffer)))
      (should (equal (car sent) "hello"))
      (should (equal (plist-get (cadr sent) :file) file)))))

(ert-deftest yeah-compose-history-is-bounded-and-usable ()
  (let ((original yeah-compose--history))
    (setq yeah-compose--history (make-ring yeah-compose-history-limit))
    (unwind-protect
        (progn
          (yeah-compose-history-add "first")
          (yeah-compose-history-add "second")
          (should (equal (yeah-compose-history-list) '("second" "first")))
          (let ((buffer (yeah-compose-open (lambda (_text _context) nil))))
            (unwind-protect
                (with-current-buffer buffer
                  (yeah-compose-history-previous)
                  (should (equal (buffer-string) "second")))
              (when (buffer-live-p buffer) (kill-buffer buffer)))))
      (setq yeah-compose--history original))))

(ert-deftest yeah-diff-previews-edit-and-write-without-mutation ()
  (let* ((path (yeah-interaction-test--temporary-file "one\ntwo\n"))
         (before (with-temp-buffer (insert-file-contents path) (buffer-string))))
    (unwind-protect
        (let* ((edit (yeah-diff-preview
                      "edit" (list path "one" "ONE")))
               (write (yeah-diff-preview
                       "write" (list path "new\n"))))
          (should (plist-get edit :ok))
          (should (string-match-p "ONE" (plist-get edit :text)))
          (should (plist-get write :ok))
          (should (equal before
                         (with-temp-buffer
                           (insert-file-contents path)
                           (buffer-string)))))
      (ignore-errors (delete-file path)))))

(ert-deftest yeah-diff-does-not-change-a-visited-buffer ()
  (let ((path (yeah-interaction-test--temporary-file "one\ntwo\n")))
    (unwind-protect
        (let* ((buffer (find-file-noselect path))
               (tick (buffer-chars-modified-tick buffer))
               (undo (buffer-local-value 'buffer-undo-list buffer)))
          (yeah-diff-preview "edit" (list path "one" "ONE"))
          (should (= tick (buffer-chars-modified-tick buffer)))
          (should (eq undo (buffer-local-value 'buffer-undo-list buffer)))
          (kill-buffer buffer))
      (ignore-errors (delete-file path)))))

(ert-deftest yeah-approval-shows-and-returns-one-decision ()
  (let ((reply nil))
    (let ((buffer (yeah-approval-open
                   (list :action "edit" :resource "/tmp/example"
                         :arguments '("/tmp/example" "old" "new"))
                   (lambda (answer) (setq reply answer)))))
      (unwind-protect
          (with-current-buffer buffer
            (should (string-match-p "edit" (buffer-string)))
            (should (string-match-p "/tmp/example" (buffer-string)))
            (yeah-approval-allow-once))
        (when (buffer-live-p buffer) (kill-buffer buffer)))
      (should (eq reply :once)))))

(ert-deftest yeah-doctor-ui-is-actionable-and-redacted ()
  (let* ((report (yeah-doctor-ui--report))
         (buffer (yeah-doctor-ui-open)))
    (unwind-protect
        (progn
          (should (> (length report) 5))
          (with-current-buffer buffer
            (should (string-match-p "Yeah Doctor" (buffer-string)))
            (should-not (string-match-p "Bearer" (buffer-string)))
            (should-not (string-match-p "api[_-]?key" (buffer-string)))))
      (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest yeah-session-list-opens-a-session-without-deleting-it ()
  (let ((root (make-temp-file "yeah-session-list" t)))
    (unwind-protect
        (progn
          (yeah-session-open "alpha" root)
          (let ((opened (list nil)))
            (let ((buffer (yeah-session-list-open
                           root (lambda (id) (setf (car opened) id)))))
              (unwind-protect
                  (progn
                    (should (string-match-p "alpha" (with-current-buffer buffer
                                                     (buffer-string))))
                    (with-current-buffer buffer
                      (goto-char (point-min))
                      (yeah-session-list-open-session))
                    (should (equal (car opened) "alpha")))
                (when (buffer-live-p buffer) (kill-buffer buffer)))))
      (ignore-errors (delete-directory root t))))))

(provide 'test-yeah-interaction)
;;; test-yeah-interaction.el ends here
