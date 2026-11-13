;;; check-wire-speaks-over-stdio.el --- real ACP and MCP servers over stdio -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Start real Emacs processes serving ACP and MCP on stdio, exchange JSON-RPC
;; lines with them and read the answers back.  No network is involved.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar-local yeah-check--position nil
  "Position in the server output buffer after the last line consumed.")

(defun yeah-check--emacs ()
  "Return the Emacs program to run the servers."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs")))

(defun yeah-check--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-mcp") "yeah-mcp.el")))

(defun yeah-check--start-server (feature expression)
  "Start a server process serving FEATURE with EXPRESSION.
Return the process and the buffer holding its output."
  (let ((buffer (generate-new-buffer "*yeah-wire-test*")))
    (with-current-buffer buffer
      (setq-local yeah-check--position (point-min)))
    (list (make-process
           :name "yeah-wire-test"
           :buffer buffer
           :command (list (yeah-check--emacs) "-Q" "--batch"
                          "-L" (yeah-check--lib-directory)
                          "-l" feature "--eval" expression)
           :connection-type 'pipe
           :noquery t
           :filter (lambda (_process chunk)
                     (with-current-buffer buffer
                       (insert chunk))))
          buffer)))

(defun yeah-check--send (process object)
  "Send OBJECT as one JSON line to PROCESS."
  (process-send-string process (concat (json-serialize object) "\n")))

(defun yeah-check--await-line (buffer &optional timeout)
  "Return the next complete JSON line in BUFFER, waiting at most TIMEOUT."
  (let ((deadline (+ (float-time) (or timeout 10)))
        (line nil))
    (while (and (null line) (< (float-time) deadline))
      (accept-process-output nil 0.05)
      (with-current-buffer buffer
        (goto-char yeah-check--position)
        (when (re-search-forward "^\\(.+\\)\n" nil t)
          (setq line (match-string 1))
          (setq yeah-check--position (match-end 0)))))
    (and line (json-parse-string line :object-type 'plist :array-type 'list))))

(let ((failures nil)
      (data-home (make-temp-file "yeah-wire-data" t)))
  (unwind-protect
      (progn
        ;; --- MCP over stdio ---
        (let* ((started (yeah-check--start-server
                         "yeah-mcp"
                         (format "(progn (setq yeah-data-home %S) (yeah-mcp-serve))"
                                 data-home)))
               (process (nth 0 started))
               (buffer (nth 1 started)))
          (yeah-check--send
           process
           (list :jsonrpc "2.0" :id 1 :method "initialize"
                 :params (list :protocolVersion "2025-06-18")))
          (let ((response (yeah-check--await-line buffer)))
            (unless (equal "2025-06-18"
                           (plist-get (plist-get response :result)
                                      :protocolVersion))
              (push (format "MCP initialize did not answer: %S" response)
                    failures)))
          (yeah-check--send process (list :jsonrpc "2.0" :id 2 :method "tools/list"))
          (let ((response (yeah-check--await-line buffer)))
            (let ((tools (plist-get (plist-get response :result) :tools)))
              (unless (and (listp tools)
                           (cl-some (lambda (tool)
                                       (equal "emacs__buffer_list"
                                              (plist-get tool :name)))
                                     tools))
                (push (format "MCP tools/list did not publish the tools: %S"
                              response)
                      failures))))
          (when (process-live-p process)
            (delete-process process)))

        ;; --- ACP over stdio ---
        (let* ((started (yeah-check--start-server
                         "yeah-acp"
                         (format "(progn (setq yeah-data-home %S) (yeah-acp-serve))"
                                 data-home)))
               (process (nth 0 started))
               (buffer (nth 1 started)))
          (yeah-check--send
           process
           (list :jsonrpc "2.0" :id 1 :method "initialize"
                 :params (list :protocolVersion 1)))
          (let ((response (yeah-check--await-line buffer)))
            (unless (equal 1 (plist-get (plist-get response :result)
                                        :protocolVersion))
              (push (format "ACP initialize did not answer: %S" response)
                    failures)))
          (yeah-check--send
           process
           (list :jsonrpc "2.0" :id 2 :method "session/new"
                 :params (list :cwd data-home :mcpServers nil)))
          (let ((response (yeah-check--await-line buffer)))
            (unless (stringp (plist-get (plist-get response :result) :sessionId))
              (push (format "ACP session/new did not answer: %S" response)
                    failures)))
          (when (process-live-p process)
            (delete-process process))))

    (dolist (failure failures)
      (message "wire: %s" failure))
    (ignore-errors (delete-directory data-home t))
    (if failures
        (kill-emacs 1)
      (kill-emacs 0))))

;;; check-wire-speaks-over-stdio.el ends here
