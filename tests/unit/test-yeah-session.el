;;; test-yeah-session.el --- ERT tests for yeah-session -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-session.el'.
;; The required cases:
;;
;;   * yeah-session-open-creates-empty-log
;;   * yeah-session-append-adds-record
;;   * yeah-session-records-returns-in-order
;;   * yeah-session-project-returns-full-log-when-no-compaction
;;   * yeah-session-record-compaction-makes-projection-shorter
;;   * yeah-session-append-after-compaction-preserves-source-records
;;   * yeah-session-open-recovers-malformed-unterminated-tail
;;   * yeah-session-open-clean-log-has-no-recovery-metadata
;;   * yeah-session-open-reports-wholly-malformed-log
;;   * yeah-session-no-delete-or-rewrite-api

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'yeah-session)
(require 'yeah-events)

(defun yeah-session-test--make-tmpdir ()
  "Create a fresh temp directory; return its absolute path.
Caller is responsible for `delete-directory' cleanup."
  (file-name-as-directory
   (make-temp-file "yeah-session-" t)))

(defun yeah-session-test--cleanup (dir)
  "Best-effort cleanup of DIR, ignoring errors."
  (ignore-errors (delete-directory dir t t)))

(defun yeah-session-test--write-log (root session-id contents)
  "Write CONTENTS as an existing SESSION-ID log under ROOT."
  (let ((path (expand-file-name (concat session-id ".jsonl")
                                (expand-file-name "sessions" root))))
    (make-directory (file-name-directory path) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file path
        (insert contents)))
    path))

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

(ert-deftest yeah-session-open-recovers-malformed-unterminated-tail ()
  "A malformed partial tail is diagnosed without losing or rewriting data."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (contents (concat "{\"type\":\"header\",\"id\":0}\n"
                           "{\"type\":\"message\",\"id\":1"))
         (path nil))
    (unwind-protect
        (progn
          (setq path (yeah-session-test--write-log tmpdir "partial" contents))
          (let ((warnings nil))
            (cl-letf (((symbol-function 'display-warning)
                       (lambda (_type message &optional _level _buffer-name)
                         (push message warnings))))
              (let* ((session (yeah-session-open "partial" tmpdir))
                     (records (yeah-session-records session))
                     (recovery (plist-get session :recovery)))
                (should (= (length records) 1))
                (should (string= (plist-get (car records) :type) "header"))
                (should (= (plist-get session :next-id) 1))
                (should recovery)
                (should (= (plist-get recovery :malformed-lines) 1))
                (should (eq (plist-get recovery :partial-tail) t))
                (should (string-match-p "malformed"
                                        (plist-get recovery :message)))
                (should (string-match-p "truncated"
                                        (plist-get recovery :message)))
                (should (equal warnings
                               (list (plist-get recovery :message)))))))
          (should (string= (yeah-session--read-file path) contents)))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-open-clean-log-has-no-recovery-metadata ()
  "Clean JSONL has no recovery metadata or warning, even without a final newline."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (contents (concat "{\"type\":\"header\",\"id\":0}\n"
                           "{\"type\":\"message\",\"id\":1,\"text\":\"ok\"}"))
         (warnings nil))
    (unwind-protect
        (progn
          (yeah-session-test--write-log tmpdir "clean" contents)
          (cl-letf (((symbol-function 'display-warning)
                     (lambda (_type message &optional _level _buffer-name)
                       (push message warnings))))
            (let ((session (yeah-session-open "clean" tmpdir)))
              (should-not (plist-get session :recovery))
              (should (= (length (yeah-session-records session)) 2))
              (should (= (plist-get session :next-id) 2))))
          (should-not warnings))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-open-reports-wholly-malformed-log ()
  "Malformed JSON is not a record; an empty recovery still has a safe next id."
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (contents "{not-json}\n")
         (warnings nil))
    (unwind-protect
        (progn
          (yeah-session-test--write-log tmpdir "malformed" contents)
          (cl-letf (((symbol-function 'display-warning)
                     (lambda (_type message &optional _level _buffer-name)
                       (push message warnings))))
            (let* ((session (yeah-session-open "malformed" tmpdir))
                   (recovery (plist-get session :recovery)))
              (should-not (yeah-session-records session))
              (should (= (plist-get session :next-id) 1))
              (should recovery)
              (should (= (plist-get recovery :malformed-lines) 1))
              (should-not (plist-get recovery :partial-tail))
              (should (stringp (plist-get recovery :message)))))
          (should (= (length warnings) 1)))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-no-delete-or-rewrite-api ()
  "The forbidden symbols `yeah-session-delete' and
`yeah-session-rewrite' must not exist as functions. This is
the load-bearing assertion of the append-only contract."
  (should-not (fboundp 'yeah-session-delete))
  (should-not (fboundp 'yeah-session-rewrite)))

(ert-deftest yeah-session-append-adds-envelope-and-explicit-correlation ()
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (session (yeah-session-open "envelope" tmpdir)))
    (unwind-protect
        (let ((id (yeah-events-write-with-context
                   session "user-message"
                   '(:run_id "run-7" :turn_id "run-7-turn-1"
                     :tool_call_id "run-7-call-1" :parent_event_id 0)
                   :payload "hello")))
          (should (= 1 id))
          (let ((record (car (last (yeah-session-records session)))))
            (should (= 1 (plist-get record :schema_version)))
            (should (equal "envelope" (plist-get record :session_id)))
            (should (stringp (plist-get record :timestamp)))
            (should (equal "run-7" (plist-get record :run_id)))
            (should (equal "run-7-turn-1" (plist-get record :turn_id)))
            (should (equal "run-7-call-1" (plist-get record :tool_call_id)))
            (should (= 0 (plist-get record :parent_event_id)))
            (let ((fields (yeah-session-record-fields record)))
              (should (equal "hello" (plist-get fields :payload)))
              (should (= 1 (plist-get fields :id)))
              (should (equal "envelope" (plist-get fields :session_id)))
              (should (stringp (plist-get fields :timestamp)))
              (should (equal "run-7-call-1" (plist-get fields :tool_call_id)))
              (should-not (plist-get fields :schema_version)))))
      (yeah-session-test--cleanup tmpdir))))

(ert-deftest yeah-session-open-legacy-log-is-byte-identical ()
  (let* ((tmpdir (yeah-session-test--make-tmpdir))
         (contents (concat "{\"type\":\"header\",\"id\":0,\"timestamp\":\"old\",\"session_id\":\"legacy\"}\n"
                           "{\"type\":\"user-message\",\"id\":7,\"payload\":\"old\"}"))
         (path (yeah-session-test--write-log tmpdir "legacy" contents)))
    (unwind-protect
        (let ((session (yeah-session-open "legacy" tmpdir)))
          (should (= 8 (plist-get session :next-id)))
          (should (equal "old" (plist-get (nth 1 (yeah-session-records session))
                                           :payload)))
          (should-not (plist-get (car (yeah-session-records session))
                                 :schema_version))
          (should (equal contents (yeah-session--read-file path))))
      (yeah-session-test--cleanup tmpdir))))

(provide 'test-yeah-session)
;;; test-yeah-session.el ends here