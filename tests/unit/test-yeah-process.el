;;; test-yeah-process.el --- ERT tests for yeah-process -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-process)

(defun yeah-process-test--handler (name)
  "Return the handler for the process tool named NAME."
  (plist-get
   (cl-find-if (lambda (spec) (equal name (plist-get spec :name)))
               (yeah-process-tools))
   :handler))

(defun yeah-process-test--wait (predicate)
  "Pump process and timer events until PREDICATE is true or a deadline passes."
  (let ((deadline (+ (float-time) 6)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.02))
    (should (funcall predicate))))

(defmacro yeah-process-test--with-registry (&rest body)
  "Run BODY with an isolated job registry and clean up its live processes."
  (declare (indent 0))
  `(let ((yeah-process--jobs (make-hash-table :test 'equal))
         (yeah-process--next-id 0))
     (unwind-protect
         (progn ,@body)
       (maphash
        (lambda (_id job)
          (unless (yeah-process--job-settled job)
            (yeah-process--settle job "cancelled" nil nil t)))
        yeah-process--jobs))))

(ert-deftest yeah-process-tools-specs ()
  "The four process tools have registry-compatible specifications."
  (let ((specs (yeah-process-tools)))
    (should (equal '("bash" "job-status" "job-read" "job-cancel")
                   (mapcar (lambda (spec) (plist-get spec :name)) specs)))
    (dolist (spec specs)
      (should (stringp (plist-get spec :description)))
      (should (listp (plist-get spec :input)))
      (should (functionp (plist-get spec :handler))))
    (let ((bash (car specs)))
      (should (eq t (plist-get bash :async)))
      (should (equal '("command" "timeout" "directory" "idle")
                     (mapcar (lambda (input) (plist-get input :name))
                             (plist-get bash :input)))))
    (dolist (spec (cdr specs))
      (should-not (plist-get spec :async)))))

(ert-deftest yeah-process-bash-success-combines-output ()
  "A successful command returns combined output and its working directory."
  (yeah-process-test--with-registry
    (let ((directory (file-name-as-directory
                      (make-temp-file "yeah-process-test-" t))))
      (unwind-protect
          (let ((default-directory directory)
                (command "printf 'out\\n'; printf 'err\\n' >&2; pwd")
                (calls 0)
                result)
            (let ((id (funcall (yeah-process-test--handler "bash")
                               (list command 2)
                               (lambda (value)
                                 (setq calls (1+ calls)
                                       result value)))))
              (should (stringp id))
              (yeah-process-test--wait (lambda () result))
              (should (= 1 calls))
              (should (plist-get result :ok))
              (should (string-match-p "out" (plist-get result :content)))
              (should (string-match-p "err" (plist-get result :content)))
              (should (string-match-p (regexp-quote (directory-file-name directory))
                                      (plist-get result :content)))
              (let ((metadata (plist-get result :metadata)))
                (should (equal id (plist-get metadata :id)))
                (should (equal "exited" (plist-get metadata :status)))
                (should (= 0 (plist-get metadata :exit)))
                (should-not (plist-get metadata :timeout))
                (should (equal command (plist-get metadata :command)))
                (should (equal directory (plist-get metadata :directory))))
              (let ((job (gethash id yeah-process--jobs)))
                (should (equal (list "sh" "-c" command)
                               (process-command (yeah-process--job-process job)))))
              (let ((status (yeah-process-job-status id)))
                (should (equal "exited"
                               (plist-get (plist-get status :metadata) :status)))
                (should (= 0 (plist-get (plist-get status :metadata) :exit))))))
        (delete-directory directory t)))))

(ert-deftest yeah-process-bash-nonzero-exit ()
  "A nonzero command preserves its output and exit status."
  (yeah-process-test--with-registry
    (let ((calls 0)
          result)
      (let ((id (funcall (yeah-process-test--handler "bash")
                         '("printf 'failure\\n'; exit 7" 2)
                         (lambda (value)
                           (setq calls (1+ calls)
                                 result value)))))
        (yeah-process-test--wait (lambda () result))
        (should (= 1 calls))
        (should (equal "failure\n" (plist-get result :content)))
        (should (= 7 (plist-get (plist-get result :metadata) :exit)))
        (should (equal "exited"
                       (plist-get (plist-get result :metadata) :status)))
        (yeah-process--sentinel (gethash id yeah-process--jobs)
                                (yeah-process--job-process
                                 (gethash id yeah-process--jobs)))
        (should (= 1 calls))))))

(ert-deftest yeah-process-bash-timeout-settles-once ()
  "The timeout deletes the managed process and wins over its sentinel."
  (yeah-process-test--with-registry
    (let ((calls 0)
          result)
      (let ((id (funcall (yeah-process-test--handler "bash")
                         '("printf 'before-timeout\\n'; exec sleep 5" 1)
                         (lambda (value)
                           (setq calls (1+ calls)
                                 result value)))))
        (yeah-process-test--wait (lambda () result))
        (should (= 1 calls))
        (should (string-match-p "before-timeout" (plist-get result :content)))
        (let ((metadata (plist-get result :metadata)))
          (should (equal "timeout" (plist-get metadata :status)))
          (should (eq t (plist-get metadata :timeout)))
          (should-not (plist-get metadata :exit)))
        (let ((job (gethash id yeah-process--jobs)))
          (should-not (process-live-p (yeah-process--job-process job)))
          (yeah-process--sentinel job (yeah-process--job-process job)))
        (should (= 1 calls))
        (should (equal "timeout"
                       (plist-get
                        (plist-get (yeah-process-job-status id) :metadata)
                        :status)))))))

(ert-deftest yeah-process-bash-idle-timeout-settles-once ()
  "A process that produces no output within IDLE is cut without waiting for max timeout."
  (yeah-process-test--with-registry
    (let ((calls 0)
          result)
      (let ((id (funcall (yeah-process-test--handler "bash")
                         '("printf 'start\\n'; exec sleep 5" 5 nil 1)
                         (lambda (value)
                           (setq calls (1+ calls)
                                 result value)))))
        (yeah-process-test--wait (lambda () result))
        (should (= 1 calls))
        (should (string-match-p "start" (plist-get result :content)))
        (let ((metadata (plist-get result :metadata)))
          (should (equal "idle-timeout" (plist-get metadata :status)))
          (should (eq t (plist-get metadata :timeout)))
          (should (= 1 (plist-get metadata :idle-seconds))))
        (yeah-process--sentinel (gethash id yeah-process--jobs)
                                (yeah-process--job-process
                                 (gethash id yeah-process--jobs)))
        (should (= 1 calls))))))

(ert-deftest yeah-process-job-read-slices-characters ()
  "Job reads honor character offsets, limits, and completion metadata."
  (yeah-process-test--with-registry
    (let (result)
      (let ((id (funcall (yeah-process-test--handler "bash")
                         '("printf 'abcdef'" 2)
                         (lambda (value) (setq result value)))))
        (yeah-process-test--wait (lambda () result))
        (let* ((first (yeah-process-job-read id 1 3))
               (first-metadata (plist-get first :metadata)))
          (should (equal "bcd" (plist-get first :content)))
          (should (= 4 (plist-get first-metadata :next-offset)))
          (should-not (plist-get first-metadata :complete)))
        (let* ((second (yeah-process-job-read id 4 3))
               (second-metadata (plist-get second :metadata)))
          (should (equal "ef" (plist-get second :content)))
          (should (= 6 (plist-get second-metadata :next-offset)))
          (should (eq t (plist-get second-metadata :complete)))
          (should (= 6 (plist-get second-metadata :output-length))))
        (let ((past-end (yeah-process-job-read id 20 2)))
          (should (equal "" (plist-get past-end :content)))
          (should (= 6 (plist-get (plist-get past-end :metadata) :next-offset)))
          (should (plist-get (plist-get past-end :metadata) :complete)))))))

(ert-deftest yeah-process-job-cancel-deletes-managed-process ()
  "Cancellation settles a live job once without claiming descendant rollback."
  (yeah-process-test--with-registry
    (let ((calls 0)
          result)
      (let ((id (funcall (yeah-process-test--handler "bash")
                         '("printf 'ready\\n'; exec sleep 30" 10)
                         (lambda (value)
                           (setq calls (1+ calls)
                                 result value)))))
        (yeah-process-test--wait
         (lambda ()
           (string-match-p
            "ready" (or (plist-get (yeah-process-job-status id) :content) ""))))
        (let ((live-read (yeah-process-job-read id 0 5)))
          (should (equal "ready" (plist-get live-read :content)))
          (should-not (plist-get (plist-get live-read :metadata) :complete)))
        (let* ((job (gethash id yeah-process--jobs))
               (process (yeah-process--job-process job))
               (cancelled (yeah-process-job-cancel id)))
          (should-not (process-live-p process))
          (should (eq cancelled result))
          (should (= 1 calls))
          (should (equal "cancelled"
                         (plist-get (plist-get cancelled :metadata) :status)))
          (should-not (plist-get (plist-get cancelled :metadata) :rollback))
          (yeah-process--sentinel job process)
          (should (eq cancelled (yeah-process-job-cancel id)))
          (should (= 1 calls)))))))

(provide 'test-yeah-process)
;;; test-yeah-process.el ends here
