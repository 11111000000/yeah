;;; check-wire-control.el --- the wire carries the control -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A real Emacs process serves ACP on a local socket.  The model is a FAKE
;; that answers only the prompt that asks to be answered; every other prompt
;; stays open, so a run can be held active on purpose.
;;
;; The client sends `session/prompt', waits until the server has really
;; started the turn, sends `session/steer' -- the clarification waits in the
;; queue of the session and is named by an input id -- and then sends
;; `session/cancel'.  The prompt must answer with the cancelled stop reason
;; instead of waiting for a model that will never answer, and a later prompt
;; must still work.
;;
;; The queue of the session is visible in the wire: the events that move an
;; input in or out of the queue arrive as `session/update' notifications.
;;
;; The client also drives the queue itself: `session/withdraw' takes a
;; pending input out of the queue and says whether it really was pending,
;; and `session/recover' starts a waiting input on the explicit request of
;; the person.  A run that is already active is not an error of the
;; protocol: `session/recover' answers that nothing was started.
;;
;; `session/load' opens the session again and replays its journal: the
;; client must see the earlier words as `session/update' notifications.
;; Opening the session again also gives the session a controller with no
;; active turn, which is the state a recovery needs: the queue of the
;; session survives the reopening.
;;
;; No network is involved: the socket is a file in a temporary directory.

;;; Code:

(require 'cl-lib)
(require 'json)
(load (expand-file-name "tests/support/yeah-journal-files.el") nil t)

(defvar yeah-check--position nil
  "Position in the client buffer after the last line consumed.")

(defvar yeah-check--seen nil
  "The messages the client received and did not consume.")

(defun yeah-check--emacs ()
  "Return the Emacs program to run the server.
The server runs the same Emacs as this one: the running binary when the
platform can name it, so the check works where `emacs' is not on PATH."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-check--start-server (data-home socket)
  "Start the ACP server process and return it with its output buffer.
The fake transport of the server answers the prompt \"again\" and leaves
every other prompt open.  The pending queue of a session lives in
DATA-HOME, so the check leaves nothing behind."
  (let ((buffer (generate-new-buffer "*yeah-control-server*")))
    (list (make-process
           :name "yeah-control-server"
           :buffer buffer
           :command
           (list (yeah-check--emacs) "-Q" "--batch"
                 "-L" (yeah-check--lib-directory)
                 "-l" "yeah-acp"
                 "--eval"
                 (format
                  (concat "(progn (setq yeah-data-home %S) "
                          "(setq yeah-input-directory %S) "
                          "(defun yeah-check--transport (prompt callback) "
                          "(if (equal prompt \"again\") "
                          "(funcall callback \"done\") "
                          "nil)) "
                          "(yeah-acp-serve-socket %S #'yeah-check--transport))")
                  data-home
                  (expand-file-name "pending/" data-home)
                  socket))
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer buffer
                       (insert chunk))))
          buffer)))

(defun yeah-check--connect (socket)
  "Connect to the server on SOCKET and return the connection process.
The connection is retried until the server is listening."
  (let ((deadline (+ (float-time) 10))
        (connection nil))
    (while (and (null connection) (< (float-time) deadline))
      (setq connection
            (condition-case nil
                (make-network-process
                 :name "yeah-control-client"
                 :family 'local
                 :service socket
                 :noquery t
                 :filter (lambda (_process chunk)
                           (with-current-buffer yeah-check--buffer
                             (insert chunk))))
              (file-missing nil)))
      (unless connection
        (accept-process-output nil 0.05)))
    connection))

(defvar yeah-check--buffer nil
  "The buffer collecting the messages the client received.")

(defun yeah-check--send (connection object)
  "Send OBJECT as one JSON line to CONNECTION."
  (process-send-string connection (concat (json-serialize object) "\n")))

(defun yeah-check--next-message (&optional timeout)
  "Return the next message the client received, or nil.
TIMEOUT defaults to 5 seconds."
  (let ((deadline (+ (float-time) (or timeout 5)))
        (message nil))
    (while (and (null message) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (with-current-buffer yeah-check--buffer
        (goto-char yeah-check--position)
        (when (re-search-forward "^\\(.+\\)\n" nil t)
          (setq message (json-parse-string (match-string 1)
                                          :object-type 'plist :array-type 'list))
          (setq yeah-check--position (match-end 0)))))
    message))

(defun yeah-check--await (predicate &optional timeout)
  "Return the next message that satisfies PREDICATE.
Messages that do not satisfy it are kept in `yeah-check--seen', so that a
later check can look at them.  TIMEOUT defaults to 5 seconds."
  (let ((deadline (+ (float-time) (or timeout 5)))
        (message nil))
    (while (and (null message) (< (float-time) deadline))
      (let ((candidate (yeah-check--next-message 1)))
        (when candidate
          (if (funcall predicate candidate)
              (setq message candidate)
            (push candidate yeah-check--seen)))))
    message))

(defun yeah-check--response (id)
  "Return a predicate matching the JSON-RPC response with ID."
  (lambda (message)
    (and (equal (plist-get message :id) id)
         (not (plist-get message :method)))))

(defun yeah-check--update (message)
  "Return the update object of MESSAGE, or nil."
  (plist-get (plist-get message :params) :update))

(defun yeah-check--update-of-kind-p (kind)
  "Return a predicate matching a session/update of KIND."
  (lambda (message)
    (and (equal (plist-get message :method) "session/update")
         (equal (plist-get (yeah-check--update message) :sessionUpdate) kind))))

(defun yeah-check--update-text (message)
  "Return the text a session/update MESSAGE carries."
  (let* ((content (plist-get (yeah-check--update message) :content))
         (blocks (cond ((vectorp content) (append content nil))
                       ((and (listp content) (consp (car content))) content)
                       (t (list content)))))
    (string-join (mapcar (lambda (block) (or (plist-get block :text) ""))
                         blocks)
                 "")))

(defun yeah-check--update-with-text-p (text)
  "Return a predicate matching a session/update that carries TEXT."
  (lambda (message)
    (and (equal (plist-get message :method) "session/update")
         (equal (yeah-check--update-text message) text))))

(defun yeah-check--update-with-kind-and-text-p (kind text)
  "Return a predicate matching a session/update of KIND that carries TEXT."
  (lambda (message)
    (and (equal (plist-get message :method) "session/update")
         (equal (plist-get (yeah-check--update message) :sessionUpdate) kind)
         (equal (yeah-check--update-text message) text))))

(defun yeah-check--journal-records-p (data-home type)
  "Return non-nil when a journal under DATA-HOME records an event of TYPE."
  (let ((found nil))
    (dolist (file (yeah-journal-files--files data-home))
      (when (and (not found)
                 (string-match-p (format "\"type\"[[:space:]]*:[[:space:]]*\"%s\"" type)
                                 (yeah-journal-files--read file)))
        (setq found t)))
    found))

(defun yeah-check--journal-records (data-home)
  "Return the records of every journal under DATA-HOME."
  (let (records)
    (dolist (file (yeah-journal-files--files data-home))
      (dolist (line (split-string (yeah-journal-files--read file) "\n" t))
        (unless (string-empty-p (string-trim line))
          (let ((record (json-parse-string line :object-type 'plist
                                          :array-type 'list
                                          :null-object nil
                                          :false-object nil)))
            (when record
              (push record records))))))
    (nreverse records)))

(defun yeah-check--journal-names-p (data-home type id)
  "Return non-nil when a journal under DATA-HOME records TYPE naming ID."
  (cl-some (lambda (record)
             (and (equal (plist-get record :type) type)
                  (equal (plist-get record :input_id) id)))
           (yeah-check--journal-records data-home)))

(defun yeah-check--json-true-p (value)
  "Return non-nil when VALUE is the JSON true."
  (and value (not (memq value '(:false)))))

(defun yeah-check--json-false-p (value)
  "Return non-nil when VALUE is the JSON false."
  (memq value '(:false nil)))

(let ((failures nil)
      (data-home (make-temp-file "yeah-control-data" t))
      (socket nil)
      (server-output nil)
      (pending-input nil))
  (unwind-protect
      (progn
        (setq socket (expand-file-name "yeah-acp.sock" data-home))
        (setq yeah-check--buffer (generate-new-buffer "*yeah-control-client*"))
        (with-current-buffer yeah-check--buffer
          (setq-local yeah-check--position (point-min)))
        (let* ((started (yeah-check--start-server data-home socket))
               (server (nth 0 started))
               (connection (yeah-check--connect socket))
               (session-id nil))
          (setq server-output (nth 1 started))
          (unless connection
            (push "the client could not connect to the server" failures))
          (unwind-protect
              (when connection
                ;; --- the handshake ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 1 :method "initialize"
                       :params (list :protocolVersion 1)))
                (let ((response (yeah-check--await (yeah-check--response 1))))
                  (unless (equal 1 (plist-get (plist-get response :result)
                                              :protocolVersion))
                    (push (format "ACP initialize did not answer: %S" response)
                          failures)))
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 2 :method "session/new"
                       :params (list :cwd data-home :mcpServers nil)))
                (let ((response (yeah-check--await (yeah-check--response 2))))
                  (setq session-id (plist-get (plist-get response :result)
                                              :sessionId))
                  (unless (stringp session-id)
                    (push (format "ACP session/new did not answer: %S" response)
                          failures)))
                (when session-id
                ;; --- a prompt that the model never answers ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                       :params (list :sessionId session-id
                                     :prompt (vector (list :type "text"
                                                           :text "wait")))))
                (let ((started (yeah-check--await
                                (yeah-check--update-of-kind-p
                                 "user_message_chunk")
                                10)))
                  (unless started
                    (push "the server did not report the started prompt"
                          failures)))
                ;; --- a clarification that waits in the queue ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 4 :method "session/steer"
                       :params (list :sessionId session-id
                                     :prompt "focus on the tests")))
                (let ((response (yeah-check--await (yeah-check--response 4) 4)))
                  (let ((input-id (plist-get (plist-get response :result)
                                             :inputId)))
                    (unless (stringp input-id)
                      (push (format "session/steer did not answer with an input id: %S"
                                    response)
                            failures))
                    ;; the queue of the session reaches the client as an update
                    (unless
                        (cl-some
                         (lambda (message)
                           (and (equal (plist-get (yeah-check--update message)
                                                  :sessionUpdate)
                                       "input_queued")
                                (equal (plist-get (yeah-check--update message)
                                                  :inputId)
                                       input-id)))
                         yeah-check--seen)
                      (push "the queued input did not reach the client as an update"
                            failures))
                    ;; --- the client withdraws the waiting input ---
                    (yeah-check--send
                     connection
                     (list :jsonrpc "2.0" :id 7 :method "session/withdraw"
                           :params (list :sessionId session-id
                                         :inputId input-id)))
                    (let* ((response (yeah-check--await
                                      (yeah-check--response 7) 4))
                           (result (plist-get response :result)))
                      (unless response
                        (push "session/withdraw did not answer" failures))
                      (unless (equal input-id (plist-get result :inputId))
                        (push (format "session/withdraw did not name the input: %S"
                                      result)
                              failures))
                      (unless (and (plist-member result :withdrawn)
                                    (yeah-check--json-true-p
                                     (plist-get result :withdrawn)))
                        (push (format "session/withdraw did not withdraw the input: %S"
                                      result)
                              failures)))
                    ;; the same input is not withdrawn twice
                    (yeah-check--send
                     connection
                     (list :jsonrpc "2.0" :id 8 :method "session/withdraw"
                           :params (list :sessionId session-id
                                         :inputId input-id)))
                    (let* ((response (yeah-check--await
                                      (yeah-check--response 8) 4))
                           (result (plist-get response :result)))
                      (unless response
                        (push "the second session/withdraw did not answer" failures))
                      (unless (equal input-id (plist-get result :inputId))
                        (push (format "the second session/withdraw did not name the input: %S"
                                      result)
                              failures))
                      (unless (and (plist-member result :withdrawn)
                                    (yeah-check--json-false-p
                                     (plist-get result :withdrawn)))
                        (push (format "the second session/withdraw withdrew the input again: %S"
                                      result)
                              failures)))
                    ;; the journal names the withdrawn input
                    (unless (yeah-check--journal-names-p
                             data-home "input-withdrawn" input-id)
                      (push (format "the journal does not record the withdrawal of %s"
                                    input-id)
                            failures))))
                ;; --- a recovery while a run is active starts nothing ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 9 :method "session/recover"
                       :params (list :sessionId session-id)))
                (let* ((response (yeah-check--await (yeah-check--response 9) 4))
                       (result (plist-get response :result)))
                  (unless (and (plist-member result :started)
                                (yeah-check--json-false-p
                                 (plist-get result :started)))
                    (push (format "session/recover started a run while another one was active: %S"
                                  result)
                          failures)))
                ;; --- the cancel stops the running prompt ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :method "session/cancel"
                       :params (list :sessionId session-id)))
                (let ((response (yeah-check--await (yeah-check--response 3) 4)))
                  (unless (equal "cancelled"
                                 (plist-get (plist-get response :result)
                                            :stopReason))
                    (push (format "the prompt was not cancelled: %S" response)
                          failures)))
                (unless (yeah-check--journal-records-p data-home "cancel")
                  (push "the journal does not record the cancellation" failures))

                ;; --- the server is still usable ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 5 :method "session/prompt"
                       :params (list :sessionId session-id
                                     :prompt (vector (list :type "text"
                                                           :text "again")))))
                (let ((response (yeah-check--await (yeah-check--response 5) 4)))
                  (unless (equal "end_turn"
                                 (plist-get (plist-get response :result)
                                            :stopReason))
                    (push (format "the next prompt did not complete: %S"
                                  response)
                          failures)))

                ;; --- the session opens again and replays its journal ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 6 :method "session/load"
                       :params (list :sessionId session-id
                                     :cwd data-home
                                     :mcpServers nil)))
                (let ((response (yeah-check--await (yeah-check--response 6) 4)))
                  (unless (equal session-id
                                 (plist-get (plist-get response :result)
                                            :sessionId))
                    (push (format "session/load did not answer: %S" response)
                          failures))
                  (unless (> (or (plist-get (plist-get response :result)
                                             :replayed)
                                  0)
                             0)
                    (push (format "session/load replayed nothing: %S" response)
                          failures)))
                ;; the replay arrives before the answer of the request
                (let ((replayed (or (cl-find-if (yeah-check--update-with-text-p
                                                "wait")
                                               yeah-check--seen)
                                    (yeah-check--await
                                     (yeah-check--update-with-text-p "wait")
                                     10))))
                  (unless replayed
                    (push "the replay did not carry the earlier words" failures)))

                ;; --- a prompt that stays open, and a second one that waits
                ;; --- in the queue of the session ---
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 10 :method "session/prompt"
                       :params (list :sessionId session-id
                                     :prompt (vector (list :type "text"
                                                           :text "hold")))))
                (yeah-check--send
                 connection
                 (list :jsonrpc "2.0" :id 11 :method "session/prompt"
                       :params (list :sessionId session-id
                                     :prompt (vector (list :type "text"
                                                           :text "later")))))
                ;; the waiting prompt reaches the client as an update
                (let ((queued (yeah-check--await
                               (yeah-check--update-with-kind-and-text-p
                                "input_queued" "later")
                               10)))
                  (unless queued
                    (push "the waiting prompt did not reach the client as an update"
                          failures))
                  (setq pending-input
                        (plist-get (yeah-check--update queued) :inputId))
                  ;; --- the session opens again: the queue of the session
                  ;; --- survives, and no run is active ---
                  (yeah-check--send
                   connection
                   (list :jsonrpc "2.0" :id 12 :method "session/load"
                         :params (list :sessionId session-id
                                       :cwd data-home
                                       :mcpServers nil)))
                  (let ((response (yeah-check--await (yeah-check--response 12) 4)))
                    (unless (equal session-id
                                   (plist-get (plist-get response :result)
                                              :sessionId))
                      (push (format "the second session/load did not answer: %S"
                                    response)
                            failures)))
                  ;; --- the person recovers the waiting input ---
                  (yeah-check--send
                   connection
                   (list :jsonrpc "2.0" :id 13 :method "session/recover"
                         :params (list :sessionId session-id)))
                  (let* ((response (yeah-check--await
                                    (yeah-check--response 13) 4))
                         (result (plist-get response :result)))
                    (unless (and (plist-member result :started)
                                  (yeah-check--json-true-p
                                   (plist-get result :started)))
                      (push (format "session/recover did not start the waiting input: %S"
                                    result)
                            failures))
                    (unless (equal pending-input
                                   (plist-get result :inputId))
                      (push (format "session/recover did not name the recovered input: %S"
                                    result)
                            failures)))
                  ;; --- the journal says that the input was recovered ---
                  (unless (yeah-check--journal-names-p
                           data-home "input-recovered" pending-input)
                    (push (format "the journal does not record the recovery of %s"
                                  pending-input)
                          failures))
                  ;; --- the recovery reaches the client as an update ---
                  (let ((recovered (or (cl-find-if
                                        (yeah-check--update-of-kind-p
                                         "input_recovered")
                                        yeah-check--seen)
                                      (yeah-check--await
                                       (yeah-check--update-of-kind-p
                                        "input_recovered")
                                       10))))
                    (unless (and recovered
                                 (equal pending-input
                                        (plist-get (yeah-check--update recovered)
                                                   :inputId)))
                      (push "the recovery did not reach the client as an update"
                            failures)))))))
            (when connection
              (ignore-errors (delete-process connection)))
            (when (process-live-p server)
              (ignore-errors (delete-process server))))))

    (dolist (failure failures)
      (message "control: %s" failure))
    (when (and failures server-output)
      (with-current-buffer server-output
        (message "control: the server said:\n%s" (buffer-string))))
    (when failures
      (dolist (file (yeah-journal-files--files data-home))
        (message "control: journal %s:\n%s" file
                 (yeah-journal-files--read file)))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-file socket))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-wire-control.el ends here
