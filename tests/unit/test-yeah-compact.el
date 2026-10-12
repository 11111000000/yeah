;;; test-yeah-compact.el --- ERT tests for yeah-compact -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-compact.el'.
;; The seven required cases:
;;
;;   * yeah-compact-cut-point-finds-the-target
;;   * yeah-compact-cut-point-nil-when-under-target
;;   * yeah-compact-summarize-default-format
;;   * yeah-compact-summarize-custom-summarizer
;;   * yeah-compact-run-noop-when-under-target
;;   * yeah-compact-run-records-compaction
;;   * yeah-compact-projection-length-shrinks-after-compaction

;;; Code:

(require 'ert)
(require 'yeah-session)
(require 'yeah-compact)

(defun yeah-compact-test--make-tmpdir ()
  "Create a fresh temp directory; return its absolute path.
Caller is responsible for `delete-directory' cleanup."
  (file-name-as-directory
   (make-temp-file "yeah-compact-" t)))

(defun yeah-compact-test--cleanup (dir)
  "Best-effort cleanup of DIR, ignoring errors."
  (ignore-errors (delete-directory dir t t)))

(defun yeah-compact-test--make-session (tmpdir id n)
  "Open a session in TMPDIR named ID and append N small message records.
Each message is `:type \"message\" :text \"text-<i>\"'. Returns the session."
  (let ((s (yeah-session-open id tmpdir)))
    (dotimes (i n)
      (yeah-session-append s (list :type "message"
                                   :text (format "text-%d" i))))
    s))

(ert-deftest yeah-compact-cut-point-finds-the-target ()
  "`yeah-compact-cut-point' walks oldest-to-newest and returns the
id of the first record whose cumulative `prin1'-length crosses
TARGET-CHARS."
  (let* ((tmpdir (yeah-compact-test--make-tmpdir))
         (s (yeah-compact-test--make-session tmpdir "cut" 5)))
    (unwind-protect
        (let* ((records (yeah-session-records s))
               (cumulative
                (let ((acc 0) (out '()))
                  (dolist (r records)
                    (setq acc (+ acc (length (prin1-to-string r)))))
                  (setq acc 0)
                  (dolist (r records)
                    (setq acc (+ acc (length (prin1-to-string r)))))
                  acc))
               (per (mapcar (lambda (r) (length (prin1-to-string r))) records))
               (total (apply #'+ per))
               (target (1- total))
               (cut (yeah-compact-cut-point s target)))
          (should (integerp cut))
          (should (>= cut 1))
          (should (<= cut 5)))
      (yeah-compact-test--cleanup tmpdir))))

(ert-deftest yeah-compact-cut-point-nil-when-under-target ()
  "`yeah-compact-cut-point' returns nil when the budget is large
enough to hold every record (no compaction needed)."
  (let* ((tmpdir (yeah-compact-test--make-tmpdir))
         (s (yeah-compact-test--make-session tmpdir "noop" 4)))
    (unwind-protect
        (let* ((records (yeah-session-records s))
               (total (apply #'+ (mapcar (lambda (r) (length (prin1-to-string r))) records)))
               (cut (yeah-compact-cut-point s (1+ total))))
          (should (null cut)))
      (yeah-compact-test--cleanup tmpdir))))

(ert-deftest yeah-compact-summarize-default-format ()
  "`yeah-compact-summarize' with no SUMMARIZER uses the default
placeholder and returns a deterministic string of the documented
shape."
  (let* ((tmpdir (yeah-compact-test--make-tmpdir))
         (s (yeah-compact-test--make-session tmpdir "summary-default" 3)))
    (unwind-protect
        (let* ((summary (yeah-compact-summarize s 3)))
          (should (stringp summary))
          (should (string-prefix-p "summary of 3 records" summary))
          (should (string-match-p "first=" summary))
          (should (string-match-p "last=" summary)))
      (yeah-compact-test--cleanup tmpdir))))

(ert-deftest yeah-compact-summarize-custom-summarizer ()
  "`yeah-compact-summarize' calls the custom SUMMARIZER with the
records before the cut-point and returns its result."
  (let* ((tmpdir (yeah-compact-test--make-tmpdir))
         (s (yeah-compact-test--make-session tmpdir "summary-custom" 4))
         (result nil))
    (unwind-protect
        (setq result
              (yeah-compact-summarize
               s 4
               (lambda (records)
                 (format "custom=%d" (length records)))))
      (yeah-compact-test--cleanup tmpdir))
    (should (stringp result))
    (should (string= result "custom=4"))))

(ert-deftest yeah-compact-run-noop-when-under-target ()
  "`yeah-compact-run' is a no-op when the budget exceeds every record.
It must NOT call `yeah-session-record-compaction': the source-of-truth
log stays at its original length."
  (let* ((tmpdir (yeah-compact-test--make-tmpdir))
         (s (yeah-compact-test--make-session tmpdir "run-noop" 3)))
    (unwind-protect
        (let* ((records (yeah-session-records s))
               (total (apply #'+ (mapcar (lambda (r) (length (prin1-to-string r))) records)))
               (report (yeah-compact-run s (1+ total))))
          (should (null (plist-get report :cut-point)))
          (should (null (plist-get report :summary)))
          (should (= (plist-get report :projection-count) (length records)))
          (should (= (length (yeah-session-records s)) (length records)))
          (should (null (yeah-compact-cut-point s (1+ total)))))
      (yeah-compact-test--cleanup tmpdir))))

(ert-deftest yeah-compact-run-records-compaction ()
  "`yeah-compact-run' records a compaction when the budget is tight,
and returns a plist whose `:cut-point' and `:summary' are non-nil."
  (let* ((tmpdir (yeah-compact-test--make-tmpdir))
         (s (yeah-compact-test--make-session tmpdir "run-ok" 5)))
    (unwind-protect
        (let* ((records (yeah-session-records s))
               (total (apply #'+ (mapcar (lambda (r) (length (prin1-to-string r))) records)))
               (report (yeah-compact-run s (1- total))))
          (should (integerp (plist-get report :cut-point)))
          (should (>= (plist-get report :cut-point) 1))
          (should (stringp (plist-get report :summary)))
          (should (string-prefix-p "summary of " (plist-get report :summary)))
          (should (integerp (plist-get report :projection-count)))
          (let* ((proj (yeah-session-project s))
                 (head-type (plist-get (nth 0 proj) :type)))
            (should (string= head-type "compaction"))))
      (yeah-compact-test--cleanup tmpdir))))

(ert-deftest yeah-compact-projection-length-shrinks-after-compaction ()
  "`yeah-compact-projection-length' returns a smaller count after a
successful `yeah-compact-run' than before."
  (let* ((tmpdir (yeah-compact-test--make-tmpdir))
         (s (yeah-compact-test--make-session tmpdir "shrink" 6)))
    (unwind-protect
        (let* ((before (yeah-compact-projection-length s))
               (records (yeah-session-records s))
               (total (apply #'+ (mapcar (lambda (r) (length (prin1-to-string r))) records)))
               (_ (yeah-compact-run s (1- total)))
               (after (yeah-compact-projection-length s)))
          (should (> before after))
          (should (< after (length (yeah-session-records s)))))
      (yeah-compact-test--cleanup tmpdir))))

(provide 'test-yeah-compact)
;;; test-yeah-compact.el ends here