;;; yeah-mcp-http.el --- the HTTP transport of MCP -*- lexical-binding: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; An MCP server that speaks HTTP is reached over a socket.  The kernel asks
;; it over HTTP/1.1 and reads the answer: the request goes out, and the answer
;; comes back through the filter of the socket, the way the answer of a server
;; of stdio comes back.
;;
;; The transport of MCP over HTTP answers with a stream of events (SSE), and
;; the stream of a server that keeps no state never ends: the answer of the
;; request is one event of that stream, and the socket is closed as soon as
;; the event arrived.  A server that answers with plain JSON is read as well:
;; both shapes are the shapes of the transport, and a client that knows only
;; one of them loses the tools of a server that speaks the other.
;;
;; Nothing here blocks.  The rules of the kernel say that the main loop never
;; waits, and a tool of a server of a session may take as long as the server
;; wants: the answer comes back when it comes.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-text)

(defgroup yeah-mcp-http nil
  "The HTTP transport of MCP."
  :group 'yeah)

(defconst yeah-mcp-http--protocol-version "2025-06-18"
  "The version of the protocol of MCP that the kernel speaks.")

(defcustom yeah-mcp-http-timeout 30
  "How long the kernel waits for the answer of an MCP server over HTTP, in
seconds.  A server that does not answer in this time is a server the session
cannot use: the session is refused rather than opened without the tools the
client asked for."
  :type 'number
  :group 'yeah-mcp-http)

(cl-defstruct (yeah-mcp-http (:constructor yeah-mcp-http--make))
  "One request to an MCP server over HTTP.
ADDRESS is the address of the server.  HEADERS are the headers the client
named, as an alist of a name and a value.  PROCESS is the socket the request
went out on.  PENDING holds the text that came and was not read yet.  PHASE
says what is being read: the head of the answer or its body.  STATUS and
RESPONSE-HEADERS hold what the head said.  BODY holds the text of the body
that was read.  LENGTH is the length the head promised, or nil when the head
promised none.  EVENTS holds the text of the body that was not split into
events yet.  CHUNKED says that the body comes in pieces.  LEFT holds how many
characters of the piece are still to come.  FINISHED says that the body is
whole.  CALLBACK receives every JSON-RPC message the answer carried."
  address host port target headers
  process pending phase status response-headers body length events
  chunked left finished callback)

(defun yeah-mcp-http--host (authority)
  "Return the host and the port of the authority AUTHORITY.
The authority may hold the user information and the port, and the host may
be an IPv6 address in brackets."
  (let ((host authority)
        (port nil))
    (when (string-match "@" host)
      (setq host (substring host (1+ (string-match "@" host)))))
    (cond
     ((string-prefix-p "[" host)
      (let ((end (string-match "]" host)))
        (when end
          (setq host (substring host 1 end))
          (when (string-match ":\\([0-9]+\\)\\'" authority)
            (setq port (string-to-number (match-string 1 authority)))))))
     ((string-match ":\\([0-9]+\\)\\'" host)
      (setq port (string-to-number (match-string 1 host))
            host (substring host 0 (match-beginning 0)))))
    (list :host host :port port)))

(defun yeah-mcp-http--address (address)
  "Return the host, the port and the target of the request ADDRESS.
The target is the path of the address with its query, the way a server
reads the line of a request."
  (let* ((text (string-trim (or address "")))
         (scheme-end (string-match "://" text)))
    (unless scheme-end
      (signal 'user-error
              (list (format "the MCP server speaks http but its address %s names no scheme"
                            address))))
    (let* ((scheme (downcase (substring text 0 scheme-end)))
           (rest (substring text (+ scheme-end 3)))
           (slash (or (string-match "/" rest) (length rest)))
           (authority (substring rest 0 slash))
           (path (substring rest slash))
           (parts (yeah-mcp-http--host authority)))
      (unless (equal scheme "http")
        (signal 'user-error
                (list (format "the MCP server speaks %s; Yeah speaks http only" scheme))))
      (list :host (plist-get parts :host)
            :port (or (plist-get parts :port) 80)
            :target (if (string-empty-p path) "/" path)))))

(defun yeah-mcp-http--head-line (status-line)
  "Return the status of the answer whose first line is STATUS-LINE."
  (let ((parts (split-string status-line " " t)))
    (if (and (>= (length parts) 2) (string-match-p "^[0-9]+$" (nth 1 parts)))
        (string-to-number (nth 1 parts))
      0)))

(defun yeah-mcp-http--headers (lines)
  "Return the headers of the answer LINES as an alist of a name and a value.
The names of the headers are downcased: the head of a response names them in
any case, and a header is looked up by its name."
  (let (headers)
    (dolist (line lines)
      (when (string-match "^\\([^:]+\\):[ \t]*\\(.*\\)$" line)
        (push (cons (downcase (string-trim (match-string 1 line)))
                    (string-trim (match-string 2 line)))
              headers)))
    (nreverse headers)))

(defun yeah-mcp-http--header (headers name)
  "Return the value of the header NAME of HEADERS, or nil."
  (cdr (assoc (downcase name) headers)))

(defun yeah-mcp-http--request (client body)
  "Return the text of the request that carries BODY to the server of CLIENT.
The request is a POST: the transport of MCP over HTTP asks with POST, and
the server answers with the stream of the events of the answer.  The length
of the body is counted in bytes: the length of a piece of a chunked answer
is counted in bytes too, and a length counted in characters would cut the
answer in the wrong place."
  (let* ((host (yeah-mcp-http-host client))
         (port (yeah-mcp-http-port client))
         (head (format "POST %s HTTP/1.1\r\nHost: %s:%s\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nContent-Length: %s\r\nConnection: close\r\n"
                        (yeah-mcp-http-target client)
                        host port
                        (string-bytes body)))
         (named (mapcar (lambda (pair)
                          (format "%s: %s\r\n" (car pair) (cdr pair)))
                        (yeah-mcp-http-headers client))))
    (concat head (mapconcat #'identity named "") "\r\n" body)))

(defun yeah-mcp-http--start (client body)
  "Open the socket of CLIENT and send BODY over it."
  (setf (yeah-mcp-http-process client)
        (make-network-process
         :name (format "yeah-mcp-http-%s" (yeah-mcp-http-host client))
         :host (yeah-mcp-http-host client)
         :service (yeah-mcp-http-port client)
         ;; The socket carries bytes: the pieces of a chunked answer are
         ;; counted in bytes, and a text that was read as bytes is turned
         ;; into text where it matters.
         :coding 'binary
         :noquery t
         :filter (lambda (_process chunk)
                   (yeah-mcp-http--filter client chunk))
         :sentinel (lambda (_process event)
                     (yeah-mcp-http--eof client event))))
  ;; The data of a socket that is not connected yet waits in the process and
  ;; goes out when the connection is made: the request is not lost.
  (process-send-string (yeah-mcp-http-process client)
                        (yeah-mcp-http--request client body)))

(defun yeah-mcp-http--filter (client chunk)
  "Read the CHUNK that came to CLIENT."
  (setf (yeah-mcp-http-pending client)
        (concat (yeah-mcp-http-pending client) chunk))
  (yeah-mcp-http--read client))

(defun yeah-mcp-http--read (client)
  "Read the head and the body of the answer of CLIENT."
  (when (eq (yeah-mcp-http-phase client) :head)
    (let ((end (string-search "\r\n\r\n" (yeah-mcp-http-pending client))))
      (when end
        (let* ((head (substring (yeah-mcp-http-pending client) 0 end))
               (lines (split-string head "\r\n"))
               (headers (yeah-mcp-http--headers (cdr lines)))
               (length (yeah-mcp-http--header headers "content-length")))
          (setf (yeah-mcp-http-status client)
                (yeah-mcp-http--head-line (or (car lines) ""))
                (yeah-mcp-http-response-headers client) headers
                (yeah-mcp-http-phase client) :body
                (yeah-mcp-http-pending client)
                (substring (yeah-mcp-http-pending client) (+ end 4))
                (yeah-mcp-http-chunked client)
                (equal (yeah-mcp-http--header headers "transfer-encoding") "chunked")
                (yeah-mcp-http-length client)
                (and length (string-to-number length)))))))
  (when (eq (yeah-mcp-http-phase client) :body)
    (yeah-mcp-http--body client))
  client)

(defun yeah-mcp-http--body (client)
  "Read the body of the answer of CLIENT."
  (if (yeah-mcp-http-chunked client)
      (yeah-mcp-http--chunks client)
    (yeah-mcp-http--plain client))
  (yeah-mcp-http--events client))

(defun yeah-mcp-http--plain (client)
  "Read the body of an answer that comes whole."
  (let ((pending (yeah-mcp-http-pending client)))
    (setf (yeah-mcp-http-pending client) "")
    (setf (yeah-mcp-http-body client)
          (concat (yeah-mcp-http-body client) pending))
    (let ((length (yeah-mcp-http-length client)))
      (when (and length (>= (length (yeah-mcp-http-body client)) length))
        (setf (yeah-mcp-http-body client)
              (substring (yeah-mcp-http-body client) 0 length))
        (setf (yeah-mcp-http-finished client) t)))))

(defun yeah-mcp-http--chunks (client)
  "Read the body of an answer that comes in pieces."
  (let ((stop nil))
    (while (and (not stop)
                (not (yeah-mcp-http-finished client))
                (yeah-mcp-http-pending client))
      (if (> (yeah-mcp-http-left client) 0)
          ;; Inside a piece: take what came and count what did not.
          (let ((take (min (yeah-mcp-http-left client)
                            (length (yeah-mcp-http-pending client)))))
            (setf (yeah-mcp-http-body client)
                  (concat (yeah-mcp-http-body client)
                          (substring (yeah-mcp-http-pending client) 0 take)))
            (setf (yeah-mcp-http-pending client)
                  (substring (yeah-mcp-http-pending client) take))
            (setf (yeah-mcp-http-left client)
                  (- (yeah-mcp-http-left client) take))
            (when (= (yeah-mcp-http-left client) 0)
              ;; The piece is over, and the line that ends it comes next.
              (when (string-prefix-p "\r\n" (yeah-mcp-http-pending client))
                (setf (yeah-mcp-http-pending client)
                      (substring (yeah-mcp-http-pending client) 2)))))
        ;; The size of the next piece is a line of its own.
        (let* ((pending (yeah-mcp-http-pending client))
               (eol (string-search "\n" pending)))
          (if (null eol)
              (setq stop t)
            (let* ((line (substring pending 0 eol))
                   (size (string-to-number
                          (string-trim (car (string-split line ";")) " \t\r") 16)))
              ;; The line ends with a line feed, and a carriage return may
              ;; stand before it: the whole end of the line goes, or the
              ;; body of the answer is shifted by a byte.
              (setf (yeah-mcp-http-pending client) (substring pending (1+ eol)))
              (if (= size 0)
                  (setf (yeah-mcp-http-finished client) t)
                (setf (yeah-mcp-http-left client) size)))))))))

(defun yeah-mcp-http--events (client)
  "Deliver the events of the body of CLIENT.
The events of the transport of MCP over HTTP are separated by an empty line,
and the data of an event is the message of JSON-RPC that it carries."
  (setf (yeah-mcp-http-events client)
        (concat (yeah-mcp-http-events client)
                (replace-regexp-in-string "\r" "" (yeah-mcp-http-body client))))
  (setf (yeah-mcp-http-body client) "")
  (let ((events (yeah-mcp-http-events client)))
    (while (string-match "\n\n" events)
      (let* ((event (substring events 0 (match-beginning 0)))
             (rest (substring events (match-end 0))))
        (setf (yeah-mcp-http-events client) rest)
        (yeah-mcp-http--event client event)
        (setq events (yeah-mcp-http-events client)))))
  client)

(defun yeah-mcp-http--event (client event)
  "Deliver the message of the event EVENT of CLIENT.
The event came as bytes, and the data of it is turned into text before it
is read: the bytes of the wire are not text, and the text of the harness
is always text."
  (let (data)
    (dolist (line (split-string event "\n"))
      (when (string-prefix-p "data:" line)
        (setq data (concat (or data "") "\n"
                           (string-trim (substring line 5) " \t")))))
    (when (and data (not (string-empty-p (string-trim data))))
      (let ((object (condition-case nil
                        (json-parse-string (yeah-text-valid data)
                                           :object-type 'plist :array-type 'list)
                      (error nil))))
        (when object
          (yeah-mcp-http--deliver client object))))))

(defun yeah-mcp-http--deliver (client object)
  "Deliver the message OBJECT to the callback of CLIENT.
A message that carries an id is the answer of the request: the socket is
closed as soon as it arrived, because the stream of a server that keeps no
state does not end by itself."
  (let ((callback (yeah-mcp-http-callback client)))
    (when callback
      (funcall callback object))
    (when (plist-get object :id)
      (yeah-mcp-http-close client))))

(defun yeah-mcp-http--eof (client event)
  "Read what is left of the answer of CLIENT when its socket ended with EVENT.
The end of the socket is the end of the body of an answer that named no
length: the events that came are read, and the last of them is delivered."
  (when (and (eq (yeah-mcp-http-phase client) :body)
             (not (yeah-mcp-http-finished client)))
    (setf (yeah-mcp-http-finished client) t)
    (yeah-mcp-http--events client))
  (unless (equal event "exit")
    (message "yeah-mcp-http: %s ended (%s)"
             (yeah-mcp-http-host client) event))
  (setf (yeah-mcp-http-process client) nil))

(defun yeah-mcp-http-close (client)
  "Close the socket of CLIENT."
  (when-let ((process (yeah-mcp-http-process client)))
    (when (process-live-p process)
      (delete-process process)))
  (setf (yeah-mcp-http-process client) nil)
  client)

(defun yeah-mcp-http-post (client body headers callback)
  "Send BODY to the server of CLIENT and deliver the answer to CALLBACK.
HEADERS are the headers the request carries.  CALLBACK receives every message
of JSON-RPC that the answer carried."
  (setf (yeah-mcp-http-callback client) callback
        (yeah-mcp-http-headers client) headers
        (yeah-mcp-http-pending client) ""
        (yeah-mcp-http-body client) ""
        (yeah-mcp-http-events client) ""
        (yeah-mcp-http-left client) 0
        (yeah-mcp-http-finished client) nil
        (yeah-mcp-http-phase client) :head)
  (yeah-mcp-http--start client body)
  client)

(defun yeah-mcp-http-connect (address headers)
  "Return the client of the MCP server at ADDRESS with the headers HEADERS.
HEADERS is an alist of a name and a value."
  (let* ((parts (yeah-mcp-http--address address))
         (client (yeah-mcp-http--make
                  :address address
                  :host (plist-get parts :host)
                  :port (plist-get parts :port)
                  :target (plist-get parts :target)
                  :headers headers)))
    client))

(provide 'yeah-mcp-http)
;;; yeah-mcp-http.el ends here
