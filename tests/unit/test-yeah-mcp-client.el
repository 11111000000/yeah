;;; test-yeah-mcp-client.el --- MCP client round trip -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-mcp-client)
(require 'yeah-tools)

(defun yeah-mcp-client-test--emacs ()
  "Return the Emacs program to use for a server process."
  (or (and (getenv "EMACS") (file-executable-p (getenv "EMACS")) (getenv "EMACS"))
      (executable-find "emacs")
      (expand-file-name "~/.nix-profile/bin/emacs")))

(defun yeah-mcp-client-test--lib-directory ()
  "Return the directory holding Yeah's Elisp modules."
  (file-name-directory (or (locate-library "yeah-mcp") "yeah-mcp.el")))

(defun yeah-mcp-client-test--wait (predicate)
  "Pump the event loop until PREDICATE is true or five seconds pass."
  (let ((deadline (+ (float-time) 5)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(ert-deftest yeah-mcp-client-round-trip-with-a-real-server ()
  (let* ((client
          (yeah-mcp-client-connect
           "yeah" (yeah-mcp-client-test--emacs)
           (list "-Q" "--batch"
                 "-L" (yeah-mcp-client-test--lib-directory)
                 "-l" "yeah-mcp"
                 "--eval" "(yeah-mcp-serve)")))
         (initialized nil)
         (tools nil)
         (result nil))
    (unwind-protect
        (progn
          (yeah-mcp-client-initialize
           client (lambda (object) (setq initialized object)))
          (should (yeah-mcp-client-test--wait (lambda () initialized)))
          (should (plist-get initialized :result))
          (yeah-mcp-client-list-tools
           client (lambda (object)
                     (setq tools (plist-get (plist-get object :result) :tools))))
          (should (yeah-mcp-client-test--wait (lambda () tools)))
          (should (cl-some (lambda (tool)
                             (equal "emacs__buffer_list" (plist-get tool :name)))
                           tools))
          (yeah-mcp-client-call-tool
           client "emacs__buffer_list" nil
           (lambda (object) (setq result object)))
          (should (yeah-mcp-client-test--wait (lambda () result)))
          (let ((content (plist-get (plist-get result :result) :content)))
            (should (listp content))
            (should (string-match-p "scratch"
                                    (plist-get (car content) :text))))
          (let ((imported (yeah-mcp-client-import-tools client)))
            (should (member "mcp--yeah--emacs__buffer_list" imported))
            (should (yeah-tools-get "mcp--yeah--emacs__buffer_list"))))
      (yeah-mcp-client-close client))))

(ert-deftest yeah-mcp-client-import-namespaces-remote-tools ()
  (let* ((client (yeah-mcp-client--make
                  :name "remote"
                  :pending (make-hash-table :test 'equal)
                  :counter 0
                  :tools (list (list :name "ping"
                                     :description "ping the server"
                                     :inputSchema
                                     (list :type "object"
                                           :properties (make-hash-table :test 'equal)
                                           :required nil)))))
         (imported (yeah-mcp-client-import-tools client "srv")))
    (unwind-protect
        (progn
          (should (equal '("mcp--srv--ping") imported))
          (should (yeah-tools-get "mcp--srv--ping")))
      (yeah-tools-unregister "mcp--srv--ping"))))

(provide 'test-yeah-mcp-client)
;;; test-yeah-mcp-client.el ends here
