;;; yeah-wire-socket.el --- the socket transport for Yeah's wire protocols -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The stdio transport of a wire protocol reads standard input with a
;; blocking read.  While that read blocks, the event loop of Emacs does
;; not run, so a notification that arrives while a request is being
;; answered is read only after the answer settled.  A reader thread does
;; not help: a thread blocked in `read-string' holds the interpreter lock,
;; and the whole Emacs stops until the read returns.
;;
;; A socket does help.  Emacs represents a connection as a process, so the
;; data of a connection arrives in a filter and the event loop keeps
;; running while the server waits.  A `session/cancel' that arrives during
;; a running prompt is therefore handled while the prompt is still
;; running, and two connections can be served at the same time.
;;
;; The transport is a local Unix socket by default; `ipv4' serves a
;; loopback TCP port instead.

;;; Code:

(require 'cl-lib)

(defgroup yeah-wire-socket nil
  "The socket transport of Yeah's wire protocols."
  :group 'yeah)

(defvar yeah-wire-socket--pending (make-hash-table :test 'eq)
  "The part of the last line received on each connection.")

(defun yeah-wire-socket--lines (connection chunk)
  "Return the complete lines in CHUNK for CONNECTION and keep the rest.
The incomplete tail of CONNECTION is kept for the next chunk."
  (let* ((pending (gethash connection yeah-wire-socket--pending ""))
         (combined (concat pending chunk))
         (parts (split-string combined "\n"))
         (complete (if (string-suffix-p "\n" combined)
                        parts
                      (butlast parts)))
         (tail (if (string-suffix-p "\n" combined)
                    ""
                  (car (last parts)))))
    (puthash connection tail yeah-wire-socket--pending)
    complete))

(defun yeah-wire-socket--respond (connection text)
  "Send TEXT to CONNECTION as one line."
  (when (process-live-p connection)
    (process-send-string connection (concat text "\n"))))

;;;###autoload
(defun yeah-wire-socket-server (service handler &optional family)
  "Listen on the local socket SERVICE and serve connections with HANDLER.
FAMILY is `local' for a Unix socket and `ipv4' for a loopback TCP port.
HANDLER is called with (LINE RESPOND) for every complete line of input;
RESPOND takes one message and sends it back to that connection.
Return the server process."
  (make-network-process
   :name "yeah-wire-socket"
   :server t
   :family (or family 'local)
   :service service
   :noquery t
   :filter
   (lambda (connection chunk)
     (cond
      ((string= chunk "")
       (remhash connection yeah-wire-socket--pending))
      (t
       (dolist (line (yeah-wire-socket--lines connection chunk))
         (unless (string-blank-p line)
           (funcall handler line
                    (lambda (text) (yeah-wire-socket--respond connection text))))))))))

;;;###autoload
(defun yeah-wire-socket-serve (service handler &optional family)
  "Serve connections on SERVICE with HANDLER until the server stops.
FAMILY and HANDLER mean what they mean in `yeah-wire-socket-server'."
  (let ((server (yeah-wire-socket-server service handler family)))
    (while (process-live-p server)
      (accept-process-output nil 0.05))
    server))

(provide 'yeah-wire-socket)
;;; yeah-wire-socket.el ends here
