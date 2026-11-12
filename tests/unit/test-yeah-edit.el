;;; test-yeah-edit.el --- ERT tests for yeah-edit -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; Guarded edit and explicit write tests through the in-process registry.

;;; Code:

(require 'ert)
(require 'yeah-edit)
(require 'yeah-tools)

(defmacro yeah-edit-test--with-tools (&rest body)
  "Register the edit tools around BODY and restore the test registry."
  (declare (indent 0) (debug t))
  `(unwind-protect
       (progn
         (yeah-tools-reset-for-test)
         (yeah-tools-unregister "edit")
         (yeah-tools-unregister "write")
         (dolist (spec (yeah-edit-tools))
           (yeah-tools-register spec))
         ,@body)
     (yeah-tools-reset-for-test)))

(defun yeah-edit-test--cleanup (path)
  "Delete PATH and kill its visiting buffer without saving."
  (let ((buffer (find-buffer-visiting path)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (set-buffer-modified-p nil))
      (kill-buffer buffer)))
  (when (file-exists-p path)
    (delete-file path)))

(defun yeah-edit-test--file-contents (path)
  "Return PATH decoded as UTF-8."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (buffer-string)))

(ert-deftest yeah-edit-unique-edit-updates-buffer-and-saves ()
  "A unique match is replaced in memory and the file is saved."
  (yeah-edit-test--with-tools
    (let ((path (make-temp-file "yeah-edit-unique-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path
              (insert "alpha beta gamma"))
            (let* ((buffer (find-file-noselect path))
                   (old-tick (with-current-buffer buffer
                               (buffer-chars-modified-tick)))
                   (undo-before (yeah-undo-list-size buffer))
                   (result (yeah-tools-call
                            "edit" (list path "beta" "omega" old-tick)))
                   (metadata (plist-get result :metadata)))
              (should (yeah-result-success-p result))
              (should (= 1 (plist-get metadata :changed)))
              (should (equal (expand-file-name path)
                             (plist-get metadata :path)))
              (should (> (plist-get metadata :tick) old-tick))
              (should (eq t (plist-get metadata :saved)))
              (should-not (plist-get metadata :modified))
              (should (equal "alpha omega gamma"
                             (with-current-buffer buffer (buffer-string))))
              (should (> (yeah-undo-list-size buffer) undo-before))
              (should (equal "alpha omega gamma"
                             (yeah-edit-test--file-contents path)))))
        (yeah-edit-test--cleanup path)))))

(ert-deftest yeah-edit-stale-tick-refuses-without-mutation ()
  "A stale tick returns an error without changing text or undo history."
  (yeah-edit-test--with-tools
    (let ((path (make-temp-file "yeah-edit-stale-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path
              (insert "before after"))
            (let* ((buffer (find-file-noselect path))
                   (stale-tick (with-current-buffer buffer
                                 (buffer-chars-modified-tick))))
              (with-current-buffer buffer
                (goto-char (point-max))
                (insert " user"))
              (let ((expected "before after user")
                    (expected-tick (with-current-buffer buffer
                                     (buffer-chars-modified-tick)))
                    (undo-before (yeah-undo-list-size buffer)))
                (let ((result (yeah-tools-call
                               "edit"
                               (list path "before" "changed" stale-tick))))
                  (should-not (yeah-result-success-p result))
                  (should (string-match-p "stale tick"
                                          (plist-get result :error)))
                  (should (= expected-tick
                             (plist-get (plist-get result :metadata) :tick)))
                  (should (equal expected
                                 (with-current-buffer buffer (buffer-string))))
                  (should (= expected-tick
                             (with-current-buffer buffer
                               (buffer-chars-modified-tick))))
                  (should (= undo-before (yeah-undo-list-size buffer)))
                  (should (equal "before after"
                                 (yeah-edit-test--file-contents path)))))))
        (yeah-edit-test--cleanup path)))))

(ert-deftest yeah-edit-nonunique-old-str-is-refused ()
  "Without replace_all, more than one exact match is refused."
  (yeah-edit-test--with-tools
    (let ((path (make-temp-file "yeah-edit-nonunique-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path
              (insert "same and same"))
            (let* ((buffer (find-file-noselect path))
                   (tick (with-current-buffer buffer
                           (buffer-chars-modified-tick)))
                   (undo-before (yeah-undo-list-size buffer))
                   (result (yeah-tools-call
                            "edit" (list path "same" "different" tick))))
              (should-not (yeah-result-success-p result))
              (should (string-match-p "exactly once"
                                      (plist-get result :error)))
              (should (equal "same and same"
                             (with-current-buffer buffer (buffer-string))))
              (should (= tick (with-current-buffer buffer
                                (buffer-chars-modified-tick))))
              (should (= undo-before (yeah-undo-list-size buffer)))))
        (yeah-edit-test--cleanup path)))))

(ert-deftest yeah-edit-no-op-has-no-undo-history ()
  "Replacing text with itself succeeds without a tick or undo change."
  (yeah-edit-test--with-tools
    (let ((path (make-temp-file "yeah-edit-noop-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path
              (insert "alpha beta"))
            (let* ((buffer (find-file-noselect path))
                   (tick (with-current-buffer buffer
                           (buffer-chars-modified-tick)))
                   (undo-before (yeah-undo-list-size buffer))
                   (result (yeah-tools-call
                            "edit" (list path "alpha" "alpha" tick)))
                   (metadata (plist-get result :metadata)))
              (should (yeah-result-success-p result))
              (should (= 0 (plist-get metadata :changed)))
              (should (= tick (plist-get metadata :tick)))
              (should-not (plist-get metadata :modified))
              (should (= undo-before (yeah-undo-list-size buffer)))
              (should (equal "alpha beta"
                             (with-current-buffer buffer (buffer-string))))))
        (yeah-edit-test--cleanup path)))))

(ert-deftest yeah-edit-replace-all-is-one-undo-step ()
  "replace_all changes every match bottom-up in one logical edit."
  (yeah-edit-test--with-tools
    (let ((path (make-temp-file "yeah-edit-all-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path
              (insert "one two one three one"))
            (let* ((buffer (find-file-noselect path))
                   (tick (with-current-buffer buffer
                           (buffer-chars-modified-tick)))
                   (result (yeah-tools-call
                            "edit" (list path "one" "1" tick t)))
                   (metadata (plist-get result :metadata)))
              (should (yeah-result-success-p result))
              (should (= 3 (plist-get metadata :changed)))
              (should (equal "1 two 1 three 1"
                             (with-current-buffer buffer (buffer-string))))
              (with-current-buffer buffer
                (undo)
                (should (equal "one two one three one" (buffer-string))))))
        (yeah-edit-test--cleanup path)))))

(ert-deftest yeah-edit-write-refuses-overwrite-by-default ()
  "Write preserves an existing file unless overwrite is explicitly true."
  (yeah-edit-test--with-tools
    (let ((path (make-temp-file "yeah-edit-write-" nil ".txt")))
      (unwind-protect
          (progn
            (with-temp-file path
              (insert "original"))
            (let ((refused (yeah-tools-call "write" (list path "replacement"))))
              (should-not (yeah-result-success-p refused))
              (should (string-match-p "file exists"
                                      (plist-get refused :error)))
              (should (equal "original"
                             (yeah-edit-test--file-contents path))))
            (let* ((content "replacement λ\n")
                   (written (yeah-tools-call
                             "write" (list path content t)))
                   (metadata (plist-get written :metadata)))
              (should (yeah-result-success-p written))
              (should (equal content (yeah-edit-test--file-contents path)))
              (should (eq t (plist-get metadata :overwritten)))
              (should (= (length (encode-coding-string content 'utf-8))
                         (plist-get metadata :bytes)))))
        (yeah-edit-test--cleanup path)))))

(ert-deftest yeah-edit-write-creates-new-utf8-file ()
  "Write creates a missing file without requiring overwrite."
  (yeah-edit-test--with-tools
    (let ((path (make-temp-file "yeah-edit-create-" nil ".txt")))
      (delete-file path)
      (unwind-protect
          (let ((result (yeah-tools-call "write" (list path "new λ\n"))))
            (should (yeah-result-success-p result))
            (should (file-exists-p path))
            (should (equal "new λ\n" (yeah-edit-test--file-contents path)))
            (should-not (plist-get (plist-get result :metadata) :overwritten)))
        (yeah-edit-test--cleanup path)))))

(provide 'test-yeah-edit)
;;; test-yeah-edit.el ends here
