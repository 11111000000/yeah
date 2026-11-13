;;; yeah-client.el --- an ACP client for the editor -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The editor is a client of a service Emacs.  This module is the client:
;; it speaks ACP over a local socket, matches answers to requests by their
;; id, and hands the session/update notifications to the caller.  The
;; session's journal is the service's truth; the client renders the stream
;; the service sends.

;;; Code:

(require 'cl-lib)
(require 'json)

(defgroup yeah-client nil
  "The Yeah ACP client."
  :group 'yeah)

(cl-defstruct (yeah-client (:constructor yeah-client--make))
  "One connection to a service Emacs.

CONNECTION is the network process.  PENDING maps request ids to their
answer callbacks.  ON-NOTIFICATION is called with each session/update.
ON-REQUEST is called with (METHOD PARAMS RESPOND) for each request the
service sends (such as session/request_permission); RESPOND takes the
result plist and answers the request.  ON-CLOSE is called once when the
connection drops without the client closing it.  COUNTER is the next
request id."
  (connection nil)
  (pending nil)
  (on-notification nil)
  (on-request nil)
  (on-close nil)
  (counter 0)
  (partial ""))

(defun yeah-client--filter (client _process chunk)
  "Accumulate CHUNK and dispatch the complete lines of CLIENT."
  (let* ((combined (concat (yeah-client-partial client) chunk))
         (parts (split-string combined "\n"))
         (complete (if (string-suffix-p "\n" combined) parts (butlast parts)))
         (tail (if (string-suffix-p "\n" combined) "" (car (last parts)))))
    (setf (yeah-client-partial client) tail)
    (dolist (line complete)
      (unless (string-blank-p line)
        (yeah-client--handle client line)))))

(defun yeah-client--handle (client line)
  "Handle one JSON LINE received by CLIENT."
  (condition-case nil
      (let* ((message (json-parse-string line :object-type 'plist
                                          :array-type 'list))
             (id (plist-get message :id))
             (method (plist-get message :method)))
        (cond
         ((and id (plist-get message :result))
          (when-let ((answer (gethash id (yeah-client-pending client))))
            (remhash id (yeah-client-pending client))
            (funcall answer (plist-get message :result) nil)))
         ((and id (plist-get message :error))
          (when-let ((answer (gethash id (yeah-client-pending client))))
            (remhash id (yeah-client-pending client))
            (funcall answer nil (plist-get message :error))))
         ((and method id)
          ;; a request of the service (session/request_permission): it
          ;; must be answered, not dropped
          (if-let ((on-request (yeah-client-on-request client)))
              (funcall on-request method (plist-get message :params)
                       (lambda (result)
                         (yeah-client--send client
                           (list :jsonrpc "2.0" :id id :result result))))
            (yeah-client--send client
              (list :jsonrpc "2.0" :id id
                    :error (list :code -32601
                                 :message (format "the client does not answer %s"
                                                  method))))))
         (method
          (when-let ((on-notification (yeah-client-on-notification client)))
            (funcall on-notification message)))))
    (error nil)))

;;;###autoload
(cl-defun yeah-client-connect (socket &key on-notification on-request on-close
                                         timeout)
  "Connect to the service on SOCKET and return the client.
ON-NOTIFICATION is called with each notification the service sends.
ON-REQUEST is called with (METHOD PARAMS RESPOND) for each request the
service sends; RESPOND takes the result plist and answers the request.
ON-CLOSE is called once when the connection drops without the client
closing it.
Waits up to TIMEOUT seconds (default 10) for the socket to appear."
  (let ((deadline (+ (float-time) (or timeout 10)))
        (connection nil))
    (while (and (null connection) (< (float-time) deadline))
      (setq connection
            (condition-case nil
                (make-network-process
                 :name (format "yeah-client-%s" (file-name-nondirectory socket))
                 :family 'local
                 :service socket
                 :noquery t)
              (file-missing nil)))
      (unless connection
        (accept-process-output nil 0.05)))
    (unless connection
      (signal 'user-error
              (list (format "yeah-client-connect: no service on %s" socket))))
    (let ((client (yeah-client--make
                   :pending (make-hash-table :test 'equal)
                   :on-notification on-notification
                   :on-request on-request
                   :on-close on-close
                   :connection connection)))
      (set-process-filter connection
                          (lambda (process chunk)
                            (yeah-client--filter client process chunk)))
      (set-process-sentinel
       connection
       (lambda (process _event)
         (when (and (eq (process-status process) 'closed)
                    (yeah-client-connection client)
                    (functionp (yeah-client-on-close client)))
           (setf (yeah-client-connection client) nil)
           (funcall (yeah-client-on-close client) client))))
      client)))

(defun yeah-client--send (client object)
  "Send OBJECT as one JSON line from CLIENT."
  (process-send-string (yeah-client-connection client)
                       (concat (json-serialize object) "\n")))

;;;###autoload
(defun yeah-client-request (client method params on-answer)
  "Send a request with METHOD and PARAMS; ON-ANSWER gets (RESULT ERROR)."
  (let ((id (cl-incf (yeah-client-counter client))))
    (puthash id on-answer (yeah-client-pending client))
    (yeah-client--send client (list :jsonrpc "2.0" :id id
                                    :method method :params params))
    id))

;;;###autoload
(defun yeah-client-notify (client method params)
  "Send a notification with METHOD and PARAMS."
  (yeah-client--send client (list :jsonrpc "2.0"
                                  :method method :params params)))

;;;###autoload
(defun yeah-client-close (client)
  "Close the connection of CLIENT.
A close the client asked for is not a death: the sentinel is removed
before the process is deleted, so ON-CLOSE does not fire for it."
  (when-let ((connection (yeah-client-connection client)))
    (setf (yeah-client-connection client) nil)
    (set-process-sentinel connection nil)
    (when (process-live-p connection)
      (delete-process connection))))

(provide 'yeah-client)
;;; yeah-client.el ends here
