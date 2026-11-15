;;; check-service-control.el --- service control reaches the editor -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License 2.0.

;;; Commentary:
;;
;; This check drives the editor client against a small stub ACP server.  The
;; stub answers session/new and the three control methods, and sends one
;; input_queued notification over the wire.  The check proves that the
;; editor sends the control requests with the right parameters and projects
;; the queued input into the shared journal view.  It does not use the real
;; service's control implementation.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-client)
(require 'yeah-journal)
(require 'yeah-service-ui)
(require 'yeah-wire-socket)

(defun yeah-service-control-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 5))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-service-control-check--request (requests method)
  "Return the request METHOD among REQUESTS."
  (cl-find method requests
           :key (lambda (request) (plist-get request :method))
           :test #'equal))

(let* ((directory (make-temp-file "yeah-service-control-check" t))
       (socket (expand-file-name "stub.sock" directory))
       (requests nil)
       (server nil)
       (client nil)
       (journal nil)
       (buffer nil)
       (failures nil))
  (unwind-protect
      (progn
        (setq server
              (yeah-wire-socket-server
               socket
               (lambda (line respond connection)
                 (let* ((request (json-parse-string line
                                                    :object-type 'plist
                                                    :array-type 'list))
                        (id (plist-get request :id))
                        (method (plist-get request :method))
                        (params (plist-get request :params)))
                   (push request requests)
                   (pcase method
                     ("initialize"
                      (funcall respond
                       (json-serialize
                        (list :jsonrpc "2.0" :id id
                              :result (list :protocolVersion 1)))))
                     ("session/new"
                      (funcall respond
                       (json-serialize
                        (list :jsonrpc "2.0" :id id
                              :result (list :sessionId "stub-session")))))
                     ("session/steer"
                      (funcall respond
                       (json-serialize
                        (list :jsonrpc "2.0" :id id
                              :result (list :inputId "input-1"))))
                      (process-send-string
                       connection
                       (concat
                        (json-serialize
                         (list :jsonrpc "2.0"
                               :method "session/update"
                               :params
                               (list :sessionId "stub-session"
                                     :update
                                     (list :sessionUpdate "input_queued"
                                           :inputId "input-1"
                                           :inputKind "steering"
                                           :content
                                           (vector
                                            (list :type "text"
                                                  :text "clarify"))))))
                        "\n")))
                     ("session/withdraw"
                      (funcall respond
                       (json-serialize
                        (list :jsonrpc "2.0" :id id
                              :result (make-hash-table :test #'equal)))))
                     ("session/recover"
                      (funcall respond
                       (json-serialize
                        (list :jsonrpc "2.0" :id id
                              :result (list :started t
                                            :inputId "input-1")))))
                     (_
                      (funcall respond
                       (json-serialize
                        (list :jsonrpc "2.0" :id id
                              :error (list :code -32601
                                           :message "unknown stub method"))))))))
               'local))
        (setq client
              (yeah-client-connect
               socket
               :on-notification
               (lambda (message)
                 (when (equal (plist-get message :method) "session/update")
                   (yeah-service-ui--render-update buffer message)))))
        (setq journal
              (yeah-journal-open
               nil nil
               (format "*Yeah service control check %d*" (random 1000000))))
        (setf (yeah-journal-driver journal) (yeah-service-ui--driver journal))
        (setq buffer (yeah-journal-buffer journal))
        (with-current-buffer buffer
          (yeah-service-ui-mode)
          (setq yeah-journal--current journal
                yeah-service-ui--client client
                yeah-service-ui--session-id nil
                yeah-service-ui--busy nil
                yeah-service-ui--records nil
                yeah-service-ui--event-id 0))
        (let ((session-id nil))
          (yeah-client-request
           client "session/new"
           (list :cwd directory :mcpServers nil)
           (lambda (result _error)
             (setq session-id (plist-get result :sessionId))))
          (yeah-service-control-check--await
           (lambda () session-id))
          (unless (equal session-id "stub-session")
            (push "the stub did not answer session/new" failures))
          (with-current-buffer buffer
            (setq yeah-service-ui--session-id session-id)))
        (with-current-buffer buffer
          (yeah-service-ui-steer "clarify"))
        (yeah-service-control-check--await
         (lambda ()
           (with-current-buffer buffer
             (plist-get (yeah-ui-view yeah-service-ui--records)
                        :pending-inputs)))
         5)
        (with-current-buffer buffer
          (yeah-service-ui-withdraw "input-1")
          (yeah-service-ui-recover))
        (yeah-service-control-check--await
         (lambda ()
           (and (yeah-service-control-check--request requests "session/steer")
                (yeah-service-control-check--request requests "session/withdraw")
                (yeah-service-control-check--request requests "session/recover"))))
        (let ((steer (yeah-service-control-check--request
                      requests "session/steer"))
              (withdraw (yeah-service-control-check--request
                         requests "session/withdraw"))
              (recover (yeah-service-control-check--request
                        requests "session/recover"))
              (pending (with-current-buffer buffer
                         (plist-get (yeah-ui-view yeah-service-ui--records)
                                    :pending-inputs))))
          (unless steer
            (push "the client did not send session/steer" failures))
          (when steer
            (unless (equal (plist-get (plist-get steer :params) :sessionId)
                           "stub-session")
              (push "session/steer named the wrong session" failures))
            (unless (equal (plist-get (plist-get steer :params) :prompt)
                           "clarify")
              (push "session/steer sent the wrong prompt" failures)))
          (unless withdraw
            (push "the client did not send session/withdraw" failures))
          (when withdraw
            (unless (equal (plist-get (plist-get withdraw :params) :sessionId)
                           "stub-session")
              (push "session/withdraw named the wrong session" failures))
            (unless (equal (plist-get (plist-get withdraw :params) :inputId)
                           "input-1")
              (push "session/withdraw sent the wrong input id" failures)))
          (unless recover
            (push "the client did not send session/recover" failures))
          (when recover
            (unless (equal (plist-get (plist-get recover :params) :sessionId)
                           "stub-session")
              (push "session/recover named the wrong session" failures)))
          (unless (= 1 (length pending))
            (push "the queued wire event is not one pending input" failures))
          (when pending
            (unless (equal (plist-get (car pending) :id) "input-1")
              (push "the queued wire event has the wrong input id" failures))
            (unless (equal (plist-get (car pending) :prompt) "clarify")
              (push "the queued wire event has the wrong prompt" failures))))))
    (when client
      (yeah-client-close client))
    (when (and server (process-live-p server))
      (delete-process server))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))
    (ignore-errors (delete-file socket))
    (ignore-errors (delete-directory directory t))
    (dolist (failure failures)
      (message "service-control: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0)))

;;; check-service-control.el ends here
