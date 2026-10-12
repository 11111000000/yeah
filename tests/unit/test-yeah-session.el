;;; test-yeah-session.el --- ERT tests for yeah-session -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-session.el'.
;; The seven required cases:
;;
;;   * yeah-session-open-creates-empty-log
;;   * yeah-session-append-adds-record
;;   * yeah-session-records-returns-in-order
;;   * yeah-session-project-returns-full-log-when-no-compaction
;;   * yeah-session-record-compaction-makes-projection-shorter
;;   * yeah-session-append-after-compaction-preserves-source-records
;;   * yeah-session-no-delete-or-rewrite-api

;;; Code:

(require 'ert)
(require 'yeah-session)

(defun yeah-session-test--make-tmpdir ()
  "Create a fresh temp directory; return its absolute path.
Caller is responsible for `delete-directory' cleanup."
  (file-name-as-directory
   (make-temp-file "yeah-session-" t)))

(defun yeah-session-test--cleanup (dir)
  "Best-effort cleanup of DIR, ignoring errors."
  (ignore-errors (delete-directory dir t t)))

(ert-deftest yeah-session-open-creates-empty-log ()
  "Opening a new session creates the JSONL file with a header."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (path   nil))
    (unwind-protect
        (progn
          (let* ((s (yeah-session-open "alpha" tmpdir))
                 (path (plist-get s :path)))
            (should (stringp (plist-get s :id)))
            (should (string= (plist-get s :id) "alpha"))
            (should (stringp path))
            (should (string-suffix-p "alpha.jsonl" path))
            (should (file-exists-p path))
            (let ((records (yeah-session-records s)))
              (should (= (length records) 1))
              (should (string= (plist-get (nth 0 records) :type) "header")))
            (should (yeah-session-idle-p s))))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-append-adds-record ()
  "`yeah-session-append' writes a record and returns a fresh id."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (s (yeah-session-open "append" tmpdir)))
    (unwind-protect
        (progn
          (let ((id1 (yeah-session-append s (list :type "message"
                                                   :role "user"
                                                   :text "hello"))))
            (should (integerp id1))
            (should (= id1 1)))
          (let ((id2 (yeah-session-append s (list :type "tool-call"
                                                   :tool "read"
                                                   :args '(:path "/foo")))))
            (should (integerp id2))
            (should (= id2 2)))
          (should (= (length (yeah-session-records s)) 3)))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-records-returns-in-order ()
  "`yeah-session-records' returns records in append order."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (s (yeah-session-open "order" tmpdir)))
    (unwind-protect
        (progn
          (yeah-session-append s (list :type "message" :role "user" :text "u1"))
          (yeah-session-append s (list :type "message" :role "assistant" :text "a1"))
          (yeah-session-append s (list :type "tool-call" :tool "eval"))
          (let* ((records (yeah-session-records s))
                 (ids (mapcar (lambda (r) (plist-get r :id)) records)))
            (should (equal ids '(0 1 2 3)))
            (should (string= (plist-get (nth 1 records) :role) "user"))
            (should (string= (plist-get (nth 2 records) :role) "assistant"))
            (should (string= (plist-get (nth 3 records) :tool) "eval"))))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-project-returns-full-log-when-no-compaction ()
  "Without a compaction record, the projection equals the full log."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (s (yeah-session-open "no-compact" tmpdir)))
    (unwind-protect
        (progn
          (yeah-session-append s (list :type "message" :text "u1"))
          (yeah-session-append s (list :type "message" :text "a1"))
          (let* ((all   (yeah-session-records s))
                 (proj  (yeah-session-project s)))
            (should (= (length proj) (length all)))
            (should (equal proj all))))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-record-compaction-makes-projection-shorter ()
  "Recording a compaction shrinks the projection."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (s (yeah-session-open "compact" tmpdir)))
    (unwind-protect
        (progn
          (yeah-session-append s (list :type "message" :text "u1"))
          (yeah-session-append s (list :type "message" :text "a1"))
          (yeah-session-append s (list :type "tool-call" :tool "read"))
          (yeah-session-append s (list :type "tool-result" :output "ok"))
          (let* ((all-before (length (yeah-session-records s)))
                 (proj-before (length (yeah-session-project s))))
            (should (= proj-before all-before)))
          (yeah-session-record-compaction s (list :cut-point 1 :summary "summary through id 1"))
          (let* ((all-after (length (yeah-session-records s)))
                 (proj      (yeah-session-project s)))
            (should (= all-after 6))
            (should (= (length proj) 4))
            (should (string= (plist-get (nth 0 proj) :type) "compaction"))
            (should (= (plist-get (nth 0 proj) :cut_point) 1))
            (should (string= (plist-get (nth 0 proj) :summary) "summary through id 1"))))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-append-after-compaction-preserves-source-records ()
  "Appending after a compaction does not delete source records;
the projection tail grows, but the source-of-truth log only grows."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (s (yeah-session-open "post" tmpdir)))
    (unwind-protect
        (progn
          (yeah-session-append s (list :type "message" :text "u1"))
          (yeah-session-append s (list :type "message" :text "a1"))
          (yeah-session-append s (list :type "message" :text "u2"))
          (yeah-session-record-compaction s (list :cut-point 1 :summary "through 1"))
          (let* ((source-before (length (yeah-session-records s)))
                 (proj-before   (length (yeah-session-project s))))
            (yeah-session-append s (list :type "message" :text "a2"))
            (let* ((source-after (length (yeah-session-records s)))
                   (proj-after   (length (yeah-session-project s))))
              (should (= source-after (1+ source-before)))
              (should (= proj-after (1+ proj-before)))
              (let* ((src (yeah-session-records s))
                     (u1  (nth 1 src)))
                (should (string= (plist-get u1 :text) "u1"))))))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-no-delete-or-rewrite-api ()
  "The forbidden symbols `yeah-session-delete' and
`yeah-session-rewrite' must not exist as functions. This is
the load-bearing assertion of the append-only contract."
  (should-not (fboundp 'yeah-session-delete))
  (should-not (fboundp 'yeah-session-rewrite)))

(provide 'test-yeah-session)
;;; test-yeah-session.el ends here