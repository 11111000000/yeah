;;; check-wire-carries-the-text.el --- the bytes on the wire are the bytes of the text -*- lexical-binding: t; coding: utf-8; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A real Emacs process serves ACP on its standard output, and a client
;; reads the bytes that leave it.  The model is a fake that answers at
;; once with the `finish' tool and says nothing else; its answer is a
;; Russian sentence.
;;
;; The sentence must reach the client as the same sentence.  A client
;; that reads UTF-8 and gets the bytes of a Latin-1 reading of the same
;; bytes sees mojibake, and an agent that wrote Russian looks like an
;; agent that wrote nonsense.  The answer must also arrive as the
;; message of the agent, not only as the output of a tool.
;;
;; Exit codes: 0 — the bytes on the wire are the bytes of the answer and
;; the answer arrived as the message of the agent; 1 — they are not.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--chunks nil
  "The raw chunks the server wrote to its standard output.")

(defun yeah-check--emacs ()
  "Return the Emacs program to run the server."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (and (file-executable-p "/proc/self/exe") "/proc/self/exe")
      (and (file-executable-p (expand-file-name "~/.nix-profile/bin/emacs"))
           (expand-file-name "~/.nix-profile/bin/emacs"))))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))

(defun yeah-check--answer ()
  "Return the answer of the fake model."
  "Emacs — это расширяемый текстовый редактор и вычислительная среда.")

(defun yeah-check--contains-p (haystack needle)
  "Return non-nil when NEEDLE, a unibyte string, is inside HAYSTACK.
The comparison is over bytes, not over characters: the question is what
the client reads from the wire, and a byte that was written twice over
is not the byte that was meant."
  (let ((h (string-to-list haystack))
        (n (string-to-list needle))
        (found nil))
    (while (and h (not found))
      (when (equal n (take (length n) h))
        (setq found t))
      (setq h (cdr h)))
    found))

(defun yeah-check--write-answer (path)
  "Write the answer of the fake model to PATH as UTF-8."
  (with-temp-file path
    (let ((coding-system-for-write 'utf-8))
      (insert (yeah-check--answer))))
  path)

(defun yeah-check--child-command (data-home answer-path)
  "Return the argv of the server process.
DATA-HOME is the data home of the server and ANSWER-PATH is the file
that holds the answer of the fake model."
  (list (yeah-check--emacs) "-Q" "--batch"
        "-L" (yeah-check--lib-directory)
        "-l" "yeah-acp"
        "--eval"
        (format
         (concat "(progn (setq yeah-data-home %S) "
                 "(defun yeah-check--answer () "
                 "(with-temp-buffer (let ((coding-system-for-read 'utf-8)) "
                 "(insert-file-contents %S)) (buffer-string))) "
                 "(defun yeah-check--transport (prompt callback) "
                 "(funcall callback (list 'tool-call "
                 "(list (list :name \"finish\") (list (yeah-check--answer)) "
                 "(lambda (_value) nil))))) "
                 "(yeah-acp-serve #'yeah-check--transport))")
         data-home answer-path)))

(defun yeah-check--start (command)
  "Start the server process with COMMAND and return it.
The output is read as bytes: the question of this check is what the
client reads, and a character set would answer a different question."
  (setq yeah-check--chunks nil)
  (make-process :name "yeah-wire-text"
                :buffer nil
                :command command
                :coding 'binary
                :filter (lambda (_process chunk)
                          (push chunk yeah-check--chunks))))

(defun yeah-check--raw ()
  "Return the bytes the server wrote so far."
  (apply #'concat (nreverse yeah-check--chunks)))

(defun yeah-check--all-lines ()
  "Return the lines the server wrote so far.
A line that is not complete yet is not a line: the server writes it
whole."
  (let ((raw (yeah-check--raw)))
    (if (string-empty-p raw)
        nil
      (split-string (decode-coding-string raw 'utf-8) "\n" t))))

(defun yeah-check--await (predicate &optional timeout)
  "Pump the event loop until PREDICATE returns non-nil, at most TIMEOUT seconds."
  (let ((deadline (+ (float-time) (or timeout 20))))
    (while (and (< (float-time) deadline)
                (not (funcall predicate)))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun yeah-check--send (process object)
  "Send OBJECT as one JSON line to PROCESS."
  (process-send-string process (concat (json-serialize object) "\n")))

(defun yeah-check--await-response (process id &optional timeout)
  "Wait for the response with ID from PROCESS and return its result."
  (let ((result nil)
        (found nil))
    (yeah-check--await
     (lambda ()
       (dolist (line (yeah-check--all-lines))
         (let ((message (condition-case nil
                           (json-parse-string line :object-type 'plist
                                              :array-type 'list)
                         (error nil))))
           (when (and message (equal id (plist-get message :id)))
             (setq result (plist-get message :result)
                   found t))))
       found)
     timeout)
    result))

(defun yeah-check--agent-messages ()
  "Return the texts the agent sent as its message."
  (let (texts)
    (dolist (line (yeah-check--all-lines))
      (let ((message (condition-case nil
                        (json-parse-string line :object-type 'plist
                                           :array-type 'list)
                      (error nil))))
        (when (and message (equal "session/update" (plist-get message :method)))
          (let* ((params (plist-get message :params))
                 (update (plist-get params :update))
                 (content (plist-get update :content)))
            (when (equal "agent_message_chunk" (plist-get update :sessionUpdate))
              ;; the content of a chunk is one content block
              (when (listp content)
                (push (plist-get content :text) texts)))))))
    texts))

(let ((data-home (make-temp-file "yeah-wire-text" t))
      (answer-path (expand-file-name "answer.txt" (make-temp-file "yeah-wire-text" t)))
      (process nil))
  (unwind-protect
      (progn
        (yeah-check--write-answer answer-path)
        (setq process (yeah-check--start
                       (yeah-check--child-command data-home answer-path)))
        ;; the handshake
        (yeah-check--send
         process
         (list :jsonrpc "2.0" :id 1 :method "initialize"
               :params (list :protocolVersion 1 :clientCapabilities (list))))
        (unless (yeah-check--await-response process 1 20)
          (push "the handshake was not answered" yeah-check--failures))
        ;; a session
        (yeah-check--send
         process
         (list :jsonrpc "2.0" :id 2 :method "session/new"
               :params (list :cwd data-home :mcpServers nil)))
        (let* ((session (yeah-check--await-response process 2 20))
               (session-id (plist-get session :sessionId)))
          (unless session-id
            (push "the session was not created" yeah-check--failures))
          (when session-id
            ;; a prompt: the fake model answers at once
            (yeah-check--send
             process
             (list :jsonrpc "2.0" :id 3 :method "session/prompt"
                   :params (list :sessionId session-id
                                 :prompt (vector (list :type "text"
                                                       :text "answer")))))
            (yeah-check--await
             (lambda ()
               (and (cl-find-if (lambda (text)
                                  (equal (yeah-check--answer) text))
                                 (yeah-check--agent-messages))
                    t))
             30))))
    ;; the bytes on the wire
    (let* ((answer (yeah-check--answer))
           (expected (encode-coding-string answer 'utf-8))
           (twice (encode-coding-string
                   (decode-coding-string expected 'latin-1) 'utf-8))
           (raw (yeah-check--raw)))
      (unless (yeah-check--contains-p raw expected)
        (push "the text of the answer is not on the wire as it was written"
              yeah-check--failures))
      (when (yeah-check--contains-p raw twice)
        (push "the text of the answer is on the wire written twice over"
              yeah-check--failures))
      (unless (cl-find-if (lambda (text) (equal answer text))
                          (yeah-check--agent-messages))
        (push "the answer of the agent did not reach the client as its message"
              yeah-check--failures)))
    (dolist (failure yeah-check--failures)
      (message "wire-text: %s" failure))
    (when (process-live-p process)
      (ignore-errors (process-send-eof process)))
    (ignore-errors (delete-directory data-home t))
    (ignore-errors (delete-directory
                    (file-name-directory answer-path) t))
    (if yeah-check--failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-wire-carries-the-text.el ends here
