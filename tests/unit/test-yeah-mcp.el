;;; test-yeah-mcp.el --- tests for the MCP server and the emacs__* tools -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-mcp)
(require 'yeah-emcp)

(defun yeah-mcp-test--parse (json-string)
  "Parse JSON-STRING as a plist."
  (json-parse-string json-string :object-type 'plist :array-type 'list))

(defun yeah-mcp-test--request (method params)
  "Return the parsed response for METHOD with PARAMS."
  (yeah-mcp-test--parse
   (yeah-mcp-handle-message
    (json-serialize (list :jsonrpc "2.0" :id 1 :method method :params params)))))

(ert-deftest yeah-mcp-initialize-advertises-tools ()
  (let* ((response (yeah-mcp-test--request "initialize"
                                         (list :protocolVersion "2025-06-18")))
         (result (plist-get response :result)))
    (should (equal "2025-06-18" (plist-get result :protocolVersion)))
    (should (equal "yeah" (plist-get (plist-get result :serverInfo) :name)))))

(ert-deftest yeah-mcp-tools-list-publishes-read-only-surface ()
  (let* ((response (yeah-mcp-test--request "tools/list" nil))
         (tools (plist-get (plist-get response :result) :tools))
         (names (mapcar (lambda (tool) (plist-get tool :name)) tools)))
    (should (member "emacs__buffer_list" names))
    (should (member "emacs__describe_function" names))
    (should-not (member "emacs__buffer_write" names))
    (should-not (member "emacs__eval" names))))

(ert-deftest yeah-mcp-tools-call-runs-the-real-tool ()
  (let* ((response
          (yeah-mcp-test--request
           "tools/call"
           (list :name "emacs__buffer_list")))
         (result (plist-get response :result))
         (content (plist-get result :content))
         (text (plist-get (car content) :text)))
    (should (memq (plist-get result :isError) '(nil :false)))
    (should (stringp text))
    (should (string-match-p "scratch" text))))

(ert-deftest yeah-mcp-tools-call-rejects-unknown-tool ()
  (let ((response (yeah-mcp-test--request
                   "tools/call" (list :name "emacs__nope"))))
    (should (= -32602 (plist-get (plist-get response :error) :code)))))

(ert-deftest yeah-mcp-handle-message-rejects-malformed-json ()
  (let ((response (yeah-mcp-test--parse (yeah-mcp-handle-message "{oops"))))
    (should (= -32700 (plist-get (plist-get response :error) :code)))))

(ert-deftest yeah-emcp-buffer-list-returns-live-buffers ()
  (let ((result (yeah-emcp-handle-call "emacs__buffer_list" nil)))
    (should (listp result))
    (should (cl-some (lambda (name) (stringp name)) result))))

(ert-deftest yeah-emcp-describe-function-returns-documentation ()
  (let ((result (yeah-emcp-handle-call "emacs__describe_function"
                                     (list :symbol "car"))))
    (should (stringp result))
    (should (> (length result) 0))))

(ert-deftest yeah-emcp-dired-list-reads-a-directory ()
  (let ((result (yeah-emcp-handle-call "emacs__dired_list"
                                     (list :directory temporary-file-directory))))
    (should (listp result))))

(ert-deftest yeah-emcp-unknown-tool-is-refused ()
  (should-error (yeah-emcp-handle-call "emacs__nope" nil) :type 'user-error))

(provide 'test-yeah-mcp)
;;; test-yeah-mcp.el ends here
