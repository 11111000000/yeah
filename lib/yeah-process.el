;;; yeah-process.el --- asynchronous shell processes and jobs -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The Bash tool starts a managed shell process and returns its job ID.  Its
;; continuation receives one bounded result when the process exits, times out,
;; or is cancelled.  Job tools expose the same output without waiting for the
;; process.  Cancellation deletes only the managed process; it does not claim
;; to terminate descendants or roll back their effects.

;;; Code:

(require 'cl-lib)
(require 'yeah-result)

(defconst yeah-process--default-timeout 120
  "Default maximum process runtime in seconds.")

(defvar yeah-process--jobs (make-hash-table :test 'equal)
  "Map job IDs to their managed process records.")

(defvar yeah-process--next-id 0
  "Last numeric suffix allocated to a process job.")

(defvar yeah-process--current-run-id nil
  "Run identifier captured when a job is started, or nil for an independent job.")

(cl-defstruct (yeah-process--job
               (:constructor yeah-process--make-job)
               (:conc-name yeah-process--job-))
  "Mutable state for one managed process.
OUTPUT is the final output after settlement.  Before then, output is read
from BUFFER.  SETTLED is the once-only guard shared by the sentinel, timer,
and cancellation path."
  id
  run-id
  process
  stderr-process
  buffer
  timer
  done
  command
  directory
  timeout
  idle
  idle-timer
  (status "running")
  exit
  (timed-out nil)
  (output "")
  result
  (settled nil))

(defun yeah-process--new-id ()
  "Allocate an ID that is not present in the job registry."
  (let (id)
    (while (or (null id) (gethash id yeah-process--jobs))
      (setq yeah-process--next-id (1+ yeah-process--next-id)
            id (format "job-%d" yeah-process--next-id)))
    id))

(defun yeah-process--list-length (args name minimum maximum)
  "Validate ARGS as a list for NAME with MINIMUM..MAXIMUM items."
  (unless (listp args)
    (signal 'user-error (list (format "yeah-process-%s: args must be a list"
                                      name))))
  (let ((count (condition-case nil (length args) (error -1))))
    (unless (and (>= count minimum) (<= count maximum))
      (signal 'user-error
              (list (format "yeah-process-%s: expected %d..%d args, got %S"
                            name minimum maximum args))))
    count))

(defun yeah-process--directory (directory)
  "Return DIRECTORY as an absolute, existing directory name."
  (let ((expanded (file-name-as-directory
                   (expand-file-name (or directory default-directory)))))
    (unless (file-directory-p expanded)
      (signal 'user-error
              (list (format "yeah-process-bash: not a directory: %s"
                            expanded))))
    expanded))

(defun yeah-process--output (job)
  "Return JOB's currently available combined standard output and error."
  (let ((buffer (yeah-process--job-buffer job)))
    (if (buffer-live-p buffer)
        (with-current-buffer buffer
          (buffer-substring-no-properties (point-min) (point-max)))
      (yeah-process--job-output job))))

(defun yeah-process--metadata (job)
  "Return serializable status metadata for JOB."
  (list :id (yeah-process--job-id job)
        :run-id (yeah-process--job-run-id job)
        :status (yeah-process--job-status job)
        :exit (yeah-process--job-exit job)
        :timeout (yeah-process--job-timed-out job)
        :command (yeah-process--job-command job)
        :directory (yeah-process--job-directory job)
        :timeout-seconds (yeah-process--job-timeout job)
        :idle-seconds (yeah-process--job-idle job)))

(defun yeah-process--settle (job status exit timed-out &optional kill)
  "Settle JOB with STATUS, EXIT, and TIMED-OUT unless it already settled.
When KILL is non-nil, delete the managed process after winning settlement.
The stored continuation is called only by the winning path.  Return the
job's result."
  (if (yeah-process--job-settled job)
      (yeah-process--job-result job)
    (let ((output (yeah-process--output job))
          (process (yeah-process--job-process job))
          (stderr-process (yeah-process--job-stderr-process job))
          (timer (yeah-process--job-timer job))
          (idle-timer (yeah-process--job-idle-timer job))
          (buffer (yeah-process--job-buffer job)))
      (setf (yeah-process--job-settled job) t
            (yeah-process--job-status job) status
            (yeah-process--job-exit job) exit
            (yeah-process--job-timed-out job) timed-out
            (yeah-process--job-output job) output)
      (when timer
        (cancel-timer timer)
        (setf (yeah-process--job-timer job) nil))
      (when idle-timer
        (cancel-timer idle-timer)
        (setf (yeah-process--job-idle-timer job) nil))
      (when kill
        (when (processp process)
          (set-process-sentinel process nil)
          (when (process-live-p process)
            (delete-process process)))
        (when (processp stderr-process)
          (set-process-sentinel stderr-process nil)
          (when (process-live-p stderr-process)
            (delete-process stderr-process))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (setf (yeah-process--job-result job)
            (yeah-result-from-output output nil (yeah-process--metadata job)))
      (funcall (yeah-process--job-done job) (yeah-process--job-result job))
      (yeah-process--job-result job))))

(defun yeah-process--arm-idle-timer (job)
  "Restart JOB's idle timer after process activity, when configured."
  (when-let ((seconds (yeah-process--job-idle job)))
    (when-let ((timer (yeah-process--job-idle-timer job)))
      (cancel-timer timer))
    (setf (yeah-process--job-idle-timer job)
          (run-at-time seconds nil
                       (lambda ()
                         (yeah-process--settle job "idle-timeout" nil t t))))))

(defun yeah-process--sentinel (job process)
  "Settle JOB after PROCESS reaches a terminal state."
  (when (memq (process-status process) '(exit signal closed failed))
    (yeah-process--settle
     job
     (if (eq (process-status process) 'exit) "exited" "signaled")
     (process-exit-status process)
     nil)))

(defun yeah-process-bash (args done)
  "Run a Bash ARGS specification and eventually call DONE exactly once.
ARGS contains COMMAND, optional TIMEOUT seconds, optional DIRECTORY and
optional IDLE seconds without output.  Return the job ID immediately."
  (yeah-process--list-length args "bash" 1 4)
  (let ((command (nth 0 args))
        (timeout (or (nth 1 args) yeah-process--default-timeout))
        (directory (nth 2 args))
        (idle (nth 3 args)))
    (unless (stringp command)
      (signal 'user-error (list "yeah-process-bash: command must be a string")))
    (unless (and (integerp timeout) (> timeout 0))
      (signal 'user-error
              (list "yeah-process-bash: timeout must be a positive integer")))
    (unless (or (null directory) (stringp directory))
      (signal 'user-error
              (list "yeah-process-bash: directory must be a string")))
    (unless (or (null idle) (and (integerp idle) (> idle 0)))
      (signal 'user-error
              (list "yeah-process-bash: idle must be a positive integer")))
    (unless (functionp done)
      (signal 'user-error (list "yeah-process-bash: done must be a function")))
    (let* ((directory (yeah-process--directory directory))
           (id (yeah-process--new-id))
           (buffer (generate-new-buffer (format " *yeah-process-%s*" id)))
           (job (yeah-process--make-job
                 :id id
                 :run-id yeah-process--current-run-id
                 :buffer buffer
                 :done done
                 :command command
                 :directory directory
                 :timeout timeout
                 :idle idle)))
      (condition-case err
          (progn
            (let* ((default-directory directory)
                   (stderr-process
                    (make-pipe-process
                     :name (format "yeah-stderr-%s" id)
                     :buffer buffer
                     :coding '(utf-8 . utf-8)
                     :noquery t
                     :filter (lambda (_process chunk)
                               (when (buffer-live-p buffer)
                                 (with-current-buffer buffer
                                   (insert chunk)))
                               (yeah-process--arm-idle-timer job))
                     :sentinel (lambda (_process _event) nil))))
              (setf (yeah-process--job-stderr-process job) stderr-process)
              (setf (yeah-process--job-process job)
                    (make-process
                     :name (format "yeah-process-%s" id)
                     :buffer buffer
                     :command (list "sh" "-c" command)
                     :coding '(utf-8 . utf-8)
                     :connection-type 'pipe
                     :noquery t
                     :stderr stderr-process
                     :filter (lambda (_process chunk)
                               (when (buffer-live-p buffer)
                                 (with-current-buffer buffer
                                   (insert chunk)))
                               (yeah-process--arm-idle-timer job))
                     :sentinel (lambda (process _event)
                                 (yeah-process--sentinel job process)))))
            (puthash id job yeah-process--jobs)
            (setf (yeah-process--job-timer job)
                  (run-at-time
                   timeout nil
                   (lambda ()
                     (yeah-process--settle job "timeout" nil t t))))
            (yeah-process--arm-idle-timer job)
            id)
        (error
         (let ((process (yeah-process--job-process job))
               (stderr-process (yeah-process--job-stderr-process job)))
           (when (processp process)
             (set-process-sentinel process nil)
             (when (process-live-p process)
               (delete-process process)))
           (when (processp stderr-process)
             (set-process-sentinel stderr-process nil)
             (when (process-live-p stderr-process)
               (delete-process stderr-process))))
         (when (buffer-live-p buffer)
           (kill-buffer buffer))
         (remhash id yeah-process--jobs)
         (signal (car err) (cdr err)))))))

(defun yeah-process--lookup (id operation)
  "Return job ID's record, or signal a user error for OPERATION."
  (unless (stringp id)
    (signal 'user-error
            (list (format "yeah-process-%s: id must be a string" operation))))
  (or (gethash id yeah-process--jobs)
      (signal 'user-error
              (list (format "yeah-process-%s: unknown job: %s" operation id)))))

(defun yeah-process-job-status (id)
  "Return ID's status, exit metadata, and a bounded output excerpt."
  (let ((job (yeah-process--lookup id "job-status")))
    (yeah-result-from-output
     (yeah-process--output job) nil (yeah-process--metadata job))))

(defun yeah-process-job-read (id &optional offset limit)
  "Return ID's output beginning at zero-based character OFFSET.
Read at most LIMIT characters, defaulting to `yeah-result-output-limit'.
`:next-offset' identifies the next unread character.  `:complete' is true
only when the job has settled and this read reaches the end of its output."
  (let* ((job (yeah-process--lookup id "job-read"))
         (offset (or offset 0))
         (limit (or limit yeah-result-output-limit)))
    (unless (and (integerp offset) (>= offset 0))
      (signal 'user-error
              (list "yeah-process-job-read: offset must be a nonnegative integer")))
    (unless (and (integerp limit) (> limit 0))
      (signal 'user-error
              (list "yeah-process-job-read: limit must be a positive integer")))
    (let* ((output (yeah-process--output job))
           (length (length output))
           (start (min offset length))
           (end (min length (+ start limit))))
      (yeah-result-ok
       (substring output start end)
       (append
        (yeah-process--metadata job)
        (list :offset start
              :limit limit
              :next-offset end
              :complete (and (yeah-process--job-settled job)
                             (= end length))
              :output-length length))))))

(defun yeah-process-job-cancel (id)
  "Cancel ID's live managed process and settle it as cancelled.
Only the process created by Yeah is deleted.  No descendant termination or
rollback is implied.  Cancelling an already settled job returns its result
without changing its status."
  (let ((job (yeah-process--lookup id "job-cancel")))
    (if (yeah-process--job-settled job)
        (yeah-process--job-result job)
      (yeah-process--settle job "cancelled" nil nil t))))

(defun yeah-process-cancel-run (run-id)
  "Cancel all live jobs associated with RUN-ID and return their count."
  (let ((count 0))
    (maphash
     (lambda (_id job)
       (when (and (equal run-id (yeah-process--job-run-id job))
                  (not (yeah-process--job-settled job)))
         (setq count (1+ count))
         (yeah-process--settle job "cancelled" nil nil t)))
     yeah-process--jobs)
    count))

(defun yeah-process-tools ()
  "Return Bash and job tool specifications for Yeah's tool registry."
  (list
   (list :name "bash"
         :description "Run a command asynchronously with sh -c and bounded output."
         :input (list (list :name "command" :type 'string)
                      (list :name "timeout" :type 'integer :optional t)
                      (list :name "directory" :type 'string :optional t)
                      (list :name "idle" :type 'integer :optional t))
         :async t
         :handler #'yeah-process-bash)
   (list :name "job-status"
         :description "Return a job's status and a bounded output excerpt."
         :input (list (list :name "id" :type 'string))
         :handler #'yeah-process-job-status)
   (list :name "job-read"
         :description "Read a character slice of a job's combined output."
         :input (list (list :name "id" :type 'string)
                      (list :name "offset" :type 'integer :optional t)
                      (list :name "limit" :type 'integer :optional t))
         :handler #'yeah-process-job-read)
   (list :name "job-cancel"
         :description "Delete a job's managed process; descendants are not guaranteed to stop."
         :input (list (list :name "id" :type 'string))
         :handler #'yeah-process-job-cancel)))

(provide 'yeah-process)
;;; yeah-process.el ends here
