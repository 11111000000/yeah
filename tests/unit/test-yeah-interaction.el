;;; test-yeah-interaction.el --- ERT tests for Yeah interaction components -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-acp)
(require 'yeah-approval-ui)
(require 'yeah-product)
(require 'yeah-service-ui)
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

(ert-deftest yeah-both-paths-ask-in-the-approval-view ()
  "Both paths ask the permission in the shared approval view: the attached
path and the service path.  A path that asked somewhere else would leave
the view unopened."
  (let ((asked nil))
    (cl-letf (((symbol-function 'yeah-approval-answer)
                (lambda (request)
                  (setq asked (cons request asked))
                  (list :effect :allow :reply :once))))
      (should (eq (plist-get (yeah-product--human-answerer
                              (list :action "edit" :resource "/tmp/x.el"
                                    :args nil))
                           :effect)
                  :allow))
      (should asked))
    (setq asked nil)
    (cl-letf (((symbol-function 'yeah-approval-answer)
                (lambda (request)
                  (setq asked (cons request asked))
                  (list :effect :allow :reply :always))))
      (should (equal (yeah-service-ui--approval-prompter
                      "edit on /tmp/x.el" '("a" "b"))
                     "allow-always"))
      (should asked))))

(ert-deftest yeah-wire-answer-of-always-is-allowed-and-remembered ()
  "The wire answer `allow-always' permits the effect and asks the kernel to
remember the decision; any other answer refuses."
  (should (equal (yeah-acp--permission-decision
                  (list :result (list :outcome (list :optionId "allow-always"))))
                 (list :effect :allow :reply :always)))
  (should (equal (yeah-acp--permission-decision
                  (list :result (list :outcome (list :optionId "allow-once"))))
                 (list :effect :allow :reply :once)))
  (should (eq (plist-get (yeah-acp--permission-decision
                          (list :result (list :outcome
                                              (list :optionId "something-else"))))
                     :effect)
              :deny))
  (should (eq (plist-get (yeah-acp--permission-decision
                          (list :error (list :code -32600 :message "bad")))
                     :effect)
              :deny)))

(ert-deftest yeah-approval-view-names-the-action-the-target-and-the-arguments ()
  "The approval view shows what the person is asked about: the action, the
resource it acts on and the arguments it would run with."
  (let ((buffer (yeah-approval-open
                 (list :action "edit" :resource "/tmp/x.el"
                       :arguments '("old text" "new text"))
                 #'ignore)))
    (unwind-protect
        (with-current-buffer buffer
          (should (string-match-p "edit" (buffer-string)))
          (should (string-match-p "/tmp/x.el" (buffer-string)))
          (should (string-match-p "old text" (buffer-string)))
          (should (string-match-p "new text" (buffer-string))))
      (kill-buffer buffer))))

(ert-deftest yeah-approval-answer-returns-the-decision-of-the-person ()
  "The shared approval view answers the question: the person decides once,
always or reject, and the decision is what the caller receives."
  (let ((decide (lambda (reply)
                  (run-at-time 0.05 nil
                    (lambda ()
                      (with-current-buffer "*Yeah Approval*"
                        (yeah-approval--decide reply)))))))
    (funcall decide :once)
    (let ((decision (yeah-approval-answer
                      (list :action "edit" :resource "/tmp/x.el" :arguments nil))))
      (should (eq (plist-get decision :effect) :allow))
      (should (eq (plist-get decision :reply) :once)))
    (funcall decide :always)
    (let ((decision (yeah-approval-answer
                      (list :action "edit" :resource "/tmp/x.el" :arguments nil))))
      (should (eq (plist-get decision :effect) :allow))
      (should (eq (plist-get decision :reply) :always)))
    (funcall decide :reject)
    (let ((decision (yeah-approval-answer
                      (list :action "edit" :resource "/tmp/x.el" :arguments nil))))
      (should (eq (plist-get decision :effect) :deny))
      (should (eq (plist-get decision :reply) :reject)))))

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

(ert-deftest yeah-diff-previews-an-edit-in-the-middle-of-a-file ()
  (let* ((path (yeah-interaction-test--temporary-file "one\ntwo\nthree\n"))
         (edit (yeah-diff-preview "edit" (list path "two" "TWO"))))
    (unwind-protect
        (should (plist-get edit :ok))
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
          ;; a session that wrote something is a session of the project; a
          ;; session that wrote nothing has no file and is not listed
          (let ((session (yeah-session-open "alpha" root)))
            (yeah-session-append session (list :type "user" :payload "hello")))
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
