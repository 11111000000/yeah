;;; check-service-tcp.el --- the editor finds a service over TCP -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License 2.0.

;;; Commentary:
;;
;; The editor finds a service in one of two ways, and this check proves both
;; halves of that choice.
;;
;; With the default settings on this Unix host the effective family is
;; `local': the client asks for a Unix-domain socket and the socket path of
;; the service is the whole address.
;;
;; When the family is `ipv4' the service publishes its loopback port in a
;; file next to the socket path; the client reads that file, connects to
;; 127.0.0.1, exchanges one ACP request, and the service removes the port
;; file when it stops.  The port file contains the port number only.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-client)
(require 'yeah-service)

(defun yeah-service-tcp-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE holds, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 5))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(let* ((yeah-client-network-family 'ipv4)
       (name (format "yeah-service-tcp-%d" (random 1000000)))
       (data-home (make-temp-file "yeah-service-tcp-check" t))
       (socket (yeah-service-socket-path name))
       (port-file (yeah-client-port-file socket))
       (service-process nil)
       (client nil)
       (failures nil))
  (unwind-protect
      (progn
        ;; --- the default family of this platform: a Unix-domain socket ---
        (let ((yeah-client-network-family nil))
          (unless (eq (yeah-client-effective-network-family) 'local)
            (push "the default family of the client is not the Unix-domain socket"
                  failures))
          (let ((params (yeah-client-connection-params socket)))
            (unless (eq (plist-get params :family) 'local)
              (push "the client did not ask for a Unix-domain socket" failures))
            (unless (equal (plist-get params :service) socket)
              (push "the client did not ask for the socket of the service"
                    failures))))
        (setq service-process
              (yeah-service-start
               name
               (concat "(defun yeah-service-tcp-check--transport "
                       "(prompt callback) "
                       "(funcall callback \"the answer\"))")
               data-home
               "#'yeah-service-tcp-check--transport"
               t))
        (unless (file-exists-p port-file)
          (push "the IPv4 service did not publish a port file" failures))
        (let ((port nil))
          (when (file-readable-p port-file)
            (with-temp-buffer
              (insert-file-contents port-file)
              (let ((text (string-trim (buffer-string))))
                (unless (string-match-p "\\`[0-9]+\\'" text)
                  (push (format "the port file is not a port number: %S" text)
                        failures))
                (setq port (string-to-number text)))))
          (unless (and port (> port 0) (<= port 65535))
            (push "the published TCP port is invalid" failures))
          (when port
            (let ((params (yeah-client-connection-params socket)))
              (unless (eq (yeah-client-effective-network-family) 'ipv4)
                (push "the effective family of the client is not IPv4" failures))
              (unless (eq (plist-get params :family) 'ipv4)
                (push "the client did not choose the IPv4 family" failures))
              (unless (equal (plist-get params :host) "127.0.0.1")
                (push "the client did not choose the loopback host" failures))
              (unless (equal (plist-get params :service) port)
                (push "the client did not read the published port" failures)))))
        (setq client
              (condition-case error
                  (yeah-client-connect socket :timeout 10)
                (error
                 (push (format "the client could not connect over TCP: %S" error)
                       failures)
                 nil)))
        (when client
          (let ((result nil)
                (error nil))
            (yeah-client-request
             client "initialize"
             (list :protocolVersion 1)
             (lambda (answer failure)
               (setq result answer
                     error failure)))
            (yeah-service-tcp-check--await
             (lambda () (or result error)))
            (when error
              (push (format "the TCP initialize request failed: %S" error)
                    failures))
            (unless (equal (plist-get result :protocolVersion) 1)
              (push "the TCP service did not answer initialize" failures))))
        (yeah-service-stop name)
        (when (file-exists-p port-file)
          (push "the port file remained after the service stopped" failures))
        (when (and service-process (process-live-p service-process))
          (push "the service process remained alive after stop" failures)))
    (when client
      (yeah-client-close client))
    (when (and service-process
               (process-live-p service-process))
      (delete-process service-process))
    (when (and service-process (process-buffer service-process))
      (kill-buffer (process-buffer service-process)))
    (ignore-errors (delete-file port-file))
    (ignore-errors (delete-file socket))
    (ignore-errors (delete-directory data-home t))
    (dolist (failure failures)
      (message "service-tcp: %s" failure))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-service-tcp.el ends here
