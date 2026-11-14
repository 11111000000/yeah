;;; test-yeah-journal.el --- ERT tests for yeah-journal -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-journal)
(require 'yeah-ui)

(defun yeah-journal-test--view (&optional assistant)
  "Return a small journal VIEW with ASSISTANT as its final answer."
  (yeah-ui-view
   (list (list :type "user-message" :id 1 :payload "hello")
         (list :type "tool-request" :id 2 :tool "read"
               :args "(\"/tmp/example\")" :tool_call_id "call-1")
         (list :type "permission-request" :id 3 :action "read"
               :resource "/tmp/example" :tool_call_id "call-1")
         (list :type "permission-decision" :id 4 :action "read"
               :resource "/tmp/example" :effect "allow"
               :tool_call_id "call-1")
         (list :type "tool-end" :id 5 :tool "read" :ok t :payload "ok"
               :tool_call_id "call-1")
         (list :type "assistant-message" :id 6
               :payload (or assistant "done")))))

(defun yeah-journal-test--driver (&optional record)
  "Return a journal DRIVER sending calls to RECORD."
  (let ((record (or record (lambda (_call) nil))))
    (list :ask (lambda (text _context _callback)
                 (funcall record (list :ask text))
                 t)
          :steer (lambda (text _context _callback)
                   (funcall record (list :steer text))
                   t)
          :cancel (lambda (_callback)
                    (funcall record (list :cancel))
                    t)
          :capabilities '(:ask :steer :cancel))))

(ert-deftest yeah-journal-open-renders-a-readable-read-only-transcript ()
  (let* ((calls nil)
         (journal (yeah-journal-open (yeah-journal-test--driver calls)
                                      (yeah-journal-test--view))))
    (unwind-protect
        (with-current-buffer (yeah-journal-buffer journal)
          (should (derived-mode-p 'yeah-journal-mode))
          (should buffer-read-only)
          (should (string-match-p "\\* User" (buffer-string)))
          (should (string-match-p "hello" (buffer-string)))
          (should (string-match-p "\\* Activity" (buffer-string)))
          (should (string-match-p "read" (buffer-string)))
          (should (string-match-p "\\* Yeah" (buffer-string)))
          (should (string-match-p "done" (buffer-string)))
          (should header-line-format))
      (yeah-journal-close journal))))

(ert-deftest yeah-journal-header-keeps-status-before-long-metadata ()
  (let* ((project "Очень-длинный-путь-проекта-который-не-помещается-в-окне")
         (view (list :session (list :title "Очень длинное название сессии"
                                    :project project
                                    :placement "attached"
                                    :profile "build"
                                    :model "provider/model-with-a-long-name")
                     :status (list :state "running")
                     :usage (list :input nil :output nil :reported-p nil)))
         (header (yeah-journal--header view))
         (project-part
          (seq-find (lambda (part)
                      (eq (get-text-property 0 'face part) 'dired-header))
                    header))
         (state-index
          (cl-position-if (lambda (part)
                            (eq (get-text-property 0 'face part) 'mode-line))
                          header))
         (project-index
          (cl-position-if (lambda (part)
                            (eq (get-text-property 0 'face part) 'dired-header))
                          header)))
    (should project-part)
    (should (< state-index project-index))
    (should (string-suffix-p "…" (substring-no-properties project-part)))
    (should (equal project (get-text-property 0 'help-echo project-part)))
    (should (string-match-p "running"
                            (mapconcat (lambda (part)
                                         (if (stringp part)
                                             (substring-no-properties part)
                                           ""))
                                       header "")))))

(ert-deftest yeah-journal-update-preserves-a-reading-place ()
  (let* ((journal (yeah-journal-open
                   (yeah-journal-test--driver)
                   (yeah-journal-test--view)))
         (buffer (yeah-journal-buffer journal)))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (goto-char (point-min))
            (search-forward "hello")
            (goto-char (match-beginning 0)))
          (let ((point (with-current-buffer buffer (point))))
            (yeah-journal-update journal (yeah-journal-test--view "changed"))
            (yeah-journal--flush-pending journal)
            (should (= point (with-current-buffer buffer (point))))
            (should (string-match-p "changed" (with-current-buffer buffer
                                                 (buffer-string))))))
      (yeah-journal-close journal))))

(ert-deftest yeah-journal-update-replaces-only-the-changed-block ()
  (let* ((journal (yeah-journal-open
                   (yeah-journal-test--driver)
                   (yeah-journal-test--view)))
         (buffer (yeah-journal-buffer journal)))
    (unwind-protect
        (progn
          (yeah-journal-update journal (yeah-journal-test--view "changed"))
          (yeah-journal--flush-pending journal)
          (with-current-buffer buffer
            (should (string-match-p "hello" (buffer-string)))
            (should (string-match-p "changed" (buffer-string)))
            (should-not (string-match-p "\\* Yeah\ndone" (buffer-string)))))
      (yeah-journal-close journal))))

(ert-deftest yeah-journal-driver-actions-are-called-once ()
  (let ((calls nil))
    (let* ((record (lambda (call) (setq calls (append calls (list call)))))
           (journal (yeah-journal-open
                     (yeah-journal-test--driver record)
                     (yeah-journal-test--view))))
      (unwind-protect
          (progn
            (yeah-journal-ask journal "do it")
            (yeah-journal-steer journal "wait")
            (yeah-journal-cancel journal)
            (should (equal (length calls) 3))
            (should (equal (plist-get (nth 0 calls) :ask) "do it"))
            (should (equal (plist-get (nth 1 calls) :steer) "wait")))
        (yeah-journal-close journal)))))

(ert-deftest yeah-journal-unsupported-capability-is-explicit ()
  (let ((journal (yeah-journal-open
                  (list :capabilities '(:ask))
                  (yeah-journal-test--view))))
    (unwind-protect
        (should-error (yeah-journal-cancel journal) :type 'user-error)
      (yeah-journal-close journal))))

(ert-deftest yeah-journal-navigation-moves-between-blocks ()
  (let* ((journal (yeah-journal-open
                   (yeah-journal-test--driver)
                   (yeah-journal-test--view)))
         (buffer (yeah-journal-buffer journal)))
    (unwind-protect
        (with-current-buffer buffer
          (goto-char (point-min))
          (yeah-journal-goto-next)
          (should (> (point) (point-min)))
          (let ((second (point)))
            (yeah-journal-goto-next)
            (should (> (point) second))))
      (yeah-journal-close journal))))

(ert-deftest yeah-journal-close-cancels-a-pending-update ()
  (let ((journal (yeah-journal-open
                  (yeah-journal-test--driver)
                  (yeah-journal-test--view))))
    (yeah-journal-update journal (yeah-journal-test--view "later"))
    (should (yeah-journal-timer journal))
    (yeah-journal-close journal)
    (should-not (yeah-journal-timer journal))
    (should-not (yeah-journal-pending journal))))

(provide 'test-yeah-journal)
;;; test-yeah-journal.el ends here
