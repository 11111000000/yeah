;;; yeah-bridge.el --- the emacsclient bridge -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; An explicit, permissioned bridge to the buffers of an attached
;; Emacs, reached through `emacsclient'.  The bridge is a capability
;; and not a convenience: the two tools carry their own names, so
;; the permission system can approve `bridge__eval' and
;; `bridge__buffer_read' separately, and nothing enters the tool
;; registry until the operator asks for it with `yeah-bridge-register'.
;;
;; The program is started with `make-process' -- never through a
;; shell -- and every call is bounded by a short timeout, so a busy
;; or absent server cannot hang the agent.

;;; Code:

(require 'yeah-tools)

(defgroup yeah-bridge nil
  "The Yeah emacsclient bridge."
  :group 'yeah)

(defcustom yeah-bridge-program "emacsclient"
  "Program used to reach the attached Emacs.
The program is run directly, without a shell, so it must be an
executable found on `exec-path' or the path of an executable file."
  :type 'string
  :group 'yeah-bridge)

(defcustom yeah-bridge-server nil
  "Name of the Emacs server the bridge connects to.
When nil, `emacsclient' connects to the default server.  A service
placement reaches a specific attached Emacs, so the name is a
capability: the operator names which Emacs the bridge may reach."
  :type '(choice (const nil) string)
  :group 'yeah-bridge)

(defconst yeah-bridge--timeout 2
  "Seconds a bridge call may take before its process is killed.")

(defconst yeah-bridge--probe "t"
  "Expression evaluated to find out whether the attached Emacs answers.")

(defun yeah-bridge--program-path ()
  "Return the path of the executable bridge program, or nil.
The program is not found when `yeah-bridge-program' is empty or
names a file that cannot be executed."
  (let ((program yeah-bridge-program))
    (and (stringp program)
         (> (length program) 0)
         (executable-find program))))

(defun yeah-bridge--trim (text)
  "Return TEXT without its trailing newlines."
  (let* ((text (or text ""))
         (end (length text)))
    (while (and (> end 0)
                (memq (aref text (1- end)) '(?\n ?\r)))
      (setq end (1- end)))
    (substring text 0 end)))

(defun yeah-bridge--stderr-text (buffer)
  "Return the text collected in the stderr BUFFER."
  (with-current-buffer buffer
    (buffer-string)))

(defun yeah-bridge--wait (process timeout)
  "Wait for PROCESS to exit, but no longer than TIMEOUT seconds.
Return non-nil when the process exited in time."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (process-live-p process)
                (< (float-time) deadline))
      (accept-process-output process 0.05))
    (not (process-live-p process))))

(defun yeah-bridge--run-program (path args timeout)
  "Run PATH with ARGS and collect what it printed.
Return a plist with the keys `:ok', `:status', `:output' and
`:message'; see `yeah-bridge--run' for their meaning."
  (let ((output "")
        (stderr-buffer (generate-new-buffer " *yeah-bridge stderr*"))
        (process nil))
    (unwind-protect
        (condition-case err
            (progn
              (setq process (make-process
                             :name "yeah-bridge"
                             :command (cons path args)
                             :connection-type 'pipe
                             :noquery t
                             :coding '(utf-8 . utf-8)
                             :filter (lambda (_process chunk)
                                       (setq output (concat output chunk)))
                             :stderr stderr-buffer))
              (yeah-bridge--wait process timeout)
              (let ((timed-out (process-live-p process)))
                (when timed-out
                  (ignore-errors (kill-process process)))
                (let ((status (unless timed-out (process-exit-status process))))
                  (list :ok (and (not timed-out) (eq status 0))
                        :status status
                        :output (yeah-bridge--trim output)
                        :message
                        (cond
                         (timed-out
                          (format "the attached Emacs did not answer within %s seconds"
                                  timeout))
                         ((not (eq status 0))
                          (let ((text (yeah-bridge--trim
                                       (yeah-bridge--stderr-text stderr-buffer))))
                            (if (> (length text) 0)
                                (format "the attached Emacs reported: %s" text)
                              "the attached Emacs reported an error")))
                         (t nil))))))
          (error
           (list :ok nil
                 :status nil
                 :output ""
                 :message (error-message-string err))))
      (when (and process (process-live-p process))
        (ignore-errors (delete-process process)))
      (when (buffer-live-p stderr-buffer)
        (kill-buffer stderr-buffer)))))

(defun yeah-bridge--run (args &optional timeout)
  "Run the bridge program with ARGS and collect what it printed.
ARGS is the list of command-line arguments without the program
itself.  TIMEOUT is the number of seconds the process may run.

Return a plist with the keys `:ok' (non-nil when the program
answered successfully), `:status' (the exit status), `:output' (the
standard output without trailing newlines) and `:message' (why the
call failed, or nil)."
  (let ((path (yeah-bridge--program-path))
        (args (append (when (and (stringp yeah-bridge-server)
                                 (> (length yeah-bridge-server) 0))
                        (list "-s" yeah-bridge-server))
                      args)))
    (if (null path)
        (list :ok nil
              :status nil
              :output ""
              :message (format "the bridge program %S is not executable"
                               yeah-bridge-program))
      (yeah-bridge--run-program path args (or timeout yeah-bridge--timeout)))))

(defun yeah-bridge-available-p ()
  "Return non-nil when the attached Emacs answers the bridge program.
The program must be executable and the attached Emacs must reply
within the bridge timeout.  This never signals: any failure means
that the bridge is unavailable."
  (condition-case nil
      (let ((result (yeah-bridge--run (list "--eval" yeah-bridge--probe))))
        (and (plist-get result :ok)
             (> (length (or (plist-get result :output) "")) 0)))
    (error nil)))

(defun yeah-bridge-eval (expression)
  "Evaluate EXPRESSION in the attached Emacs and return the printed result.
EXPRESSION is a string of Elisp code.  The result is the printed
value, as a string, without trailing newlines.

Signals `user-error' when the bridge is unavailable and when the
evaluation itself fails; the message says which of the two happened."
  (unless (stringp expression)
    (signal 'user-error
            (list (format "yeah-bridge-eval: expression must be a string, got %S"
                          (type-of expression)))))
  (let ((result (yeah-bridge--run (list "--eval" expression))))
    (if (plist-get result :ok)
        (plist-get result :output)
      (signal 'user-error
              (list (format "yeah-bridge-eval: %s"
                            (if (yeah-bridge-available-p)
                                (format "evaluation failed: %s"
                                        (or (plist-get result :message)
                                            "unknown error"))
                              "the bridge is unavailable")))))))

(defun yeah-bridge--decode (output)
  "Return the string OUTPUT holds, decoding its printed form.
`emacsclient --eval' prints the value of the evaluation: a string
arrives quoted, as its printed form.  When OUTPUT looks like a printed
string it is read back; anything else is returned unchanged."
  (if (and (stringp output)
           (> (length output) 1)
           (eq (aref output 0) ?\"))
      (condition-case nil (read output) (error output))
    output))

(defun yeah-bridge-buffer-read (name)
  "Return the text of the live buffer NAME of the attached Emacs.
NAME is the name of a buffer in the attached Emacs.  The result is
its text, as a string, without trailing newlines.

Signals `user-error' when the bridge is unavailable and when the
buffer cannot be read there; the message says which of the two
happened."
  (unless (stringp name)
    (signal 'user-error
            (list (format "yeah-bridge-buffer-read: name must be a string, got %S"
                          (type-of name)))))
  (let* ((expression
          (format (concat "(with-current-buffer %S "
                          "(buffer-substring-no-properties (point-min) (point-max)))")
                  name))
         (result (yeah-bridge--run (list "--eval" expression))))
    (if (plist-get result :ok)
        (yeah-bridge--decode (plist-get result :output))
      (signal 'user-error
              (list (format "yeah-bridge-buffer-read: %s"
                            (if (yeah-bridge-available-p)
                                (format "buffer %S could not be read: %s"
                                        name
                                        (or (plist-get result :message)
                                            "unknown error"))
                              "the bridge is unavailable")))))))

(defun yeah-bridge-tool-specs ()
  "Return the bridge tool specifications, in registration order."
  (list
   (list :name "bridge__eval"
         :description
         "Evaluate an Elisp expression in the attached Emacs and return the printed value."
         :input (list (list :name "expression" :type 'string))
         :handler #'yeah-bridge-eval)
   (list :name "bridge__buffer_read"
         :description
         "Return the contents of a live buffer of the attached Emacs."
         :input (list (list :name "name" :type 'string))
         :handler #'yeah-bridge-buffer-read)))

(defun yeah-bridge-register ()
  "Register the bridge tools in the tool registry and return them.
The registration is idempotent: a tool that is already registered is
kept as it is, so calling this twice does not raise an error.
The permission system matches the tool name as the action, so
`\"bridge__eval\"' and `\"bridge__buffer_read\"' are approved on
their own."
  (let ((specs (yeah-bridge-tool-specs)))
    (dolist (spec specs)
      (unless (yeah-tools-get (plist-get spec :name))
        (yeah-tools-register spec)))
    specs))

(provide 'yeah-bridge)
;;; yeah-bridge.el ends here
