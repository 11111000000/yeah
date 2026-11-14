;;; test-yeah-acp.el --- ERT tests for the ACP v1 agent -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-acp)

(defun yeah-acp-test--parse (json-string)
  "Parse JSON-STRING as a plist."
  (json-parse-string json-string :object-type 'plist :array-type 'list))

(defun yeah-acp-test--prompt-request (id session-id text)
  "Return one valid ACP prompt request string for ID, SESSION-ID and TEXT."
  (json-serialize
   (list :jsonrpc "2.0"
         :id id
         :method "session/prompt"
         :params (list :sessionId session-id
                       :prompt (vector (list :type "text" :text text))))))

(defun yeah-acp-test--find-response (emitted id)
  "Return the emitted message answering request ID, or nil."
  (cl-find-if
   (lambda (text)
     (equal id (plist-get (yeah-acp-test--parse text) :id)))
   emitted))

(defun yeah-acp-test--stop-reason (text)
  "Return the stopReason carried by the response TEXT."
  (plist-get (plist-get (yeah-acp-test--parse text) :result) :stopReason))

(defmacro yeah-acp-test--with-server (&rest body)
  "Run BODY with isolated ACP state, model transport and output."
  (declare (indent 0))
  `(let* ((directory (make-temp-file "yeah-acp-test" t))
          (yeah-data-home directory)
          (yeah-acp--transport nil)
          (yeah-acp--answerer nil)
          (yeah-acp--output-function nil))
     (unwind-protect
         (progn
           (yeah-acp--reset-for-test)
           ,@body)
       (yeah-acp--reset-for-test)
       (ignore-errors (delete-directory directory t t)))))

(defun yeah-acp-test--new-session ()
  "Create a session in the isolated ACP test server and return its id."
  (plist-get
   (yeah-acp-session-new (list :cwd (file-truename yeah-data-home)
                               :mcpServers nil))
   :sessionId))

(ert-deftest yeah-acp-initialize-negotiates-protocol-one ()
  (yeah-acp-test--with-server
    (let ((response (yeah-acp-initialize
                     (list :protocolVersion 1 :clientInfo '(:name "zed")))))
      (should (= 1 (plist-get response :protocolVersion)))
      (should (equal "yeah" (plist-get (plist-get response :agentInfo) :name)))
      (should (eq t (plist-get (plist-get response :agentCapabilities)
                               :loadSession))))))

(ert-deftest yeah-acp-initialize-rejects-string-protocol-version ()
  (yeah-acp-test--with-server
    (should-error (yeah-acp-initialize '(:protocolVersion "1"))
                  :type 'user-error)))

(ert-deftest yeah-acp-session-new-load-and-updates ()
  (yeah-acp-test--with-server
    (let* ((updates nil)
           (session-id (yeah-acp-test--new-session))
           (session (plist-get (yeah-acp--session-state session-id) :session)))
      (setq yeah-acp--output-function (lambda (text) (push text updates)))
      (yeah-events-write session "assistant-message" :payload "hello")
      (should (= 1 (length updates)))
      (let* ((update (yeah-acp-test--parse (car updates)))
             (params (plist-get update :params)))
        (should (equal "session/update" (plist-get update :method)))
        (should (equal session-id (plist-get params :sessionId)))
        (should (equal "agent_message_chunk"
                       (plist-get (plist-get params :update) :sessionUpdate))))
      (let ((loaded (yeah-acp-session-load
                     (list :sessionId session-id :cwd yeah-data-home
                           :mcpServers nil))))
        (should (equal session-id (plist-get loaded :sessionId)))
        (should (yeah-acp--session-state session-id))))))

(ert-deftest yeah-acp-prompt-answers-with-end-turn-stop-reason ()
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (setq yeah-acp--transport
            (lambda (_prompt callback) (funcall callback "the answer")))
      (should-not
       (yeah-acp-handle-message
        (yeah-acp-test--prompt-request 7 session-id "hello")))
      (let ((response (yeah-acp-test--find-response emitted 7)))
        (should response)
        (should (equal "end_turn" (yeah-acp-test--stop-reason response))))
      (should (cl-some (lambda (text)
                         (string-match-p "agent_message_chunk" text))
                       emitted)))))

(ert-deftest yeah-acp-cancel-answers-prompt-with-cancelled ()
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (setq yeah-acp--transport (lambda (_prompt _callback) nil))
      (should-not
       (yeah-acp-handle-message
        (yeah-acp-test--prompt-request 9 session-id "wait")))
      (yeah-acp-handle-message
       (json-serialize
        (list :jsonrpc "2.0"
              :method "session/cancel"
              :params (list :sessionId session-id))))
      (let ((response (yeah-acp-test--find-response emitted 9)))
        (should response)
        (should (equal "cancelled" (yeah-acp-test--stop-reason response))))
      (should-not (gethash session-id yeah-acp--active-turns)))))

(ert-deftest yeah-acp-prompt-rejects-unsupported-content-block ()
  (yeah-acp-test--with-server
    (let* ((session-id (yeah-acp-test--new-session))
           (request
            (format
             (concat "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"session/prompt\","
                     "\"params\":{\"sessionId\":\"%s\",\"prompt\":[{\"type\":\"image\"}]}}")
             session-id))
           (response (yeah-acp-test--parse (yeah-acp-handle-message request))))
      (should (= -32602 (plist-get (plist-get response :error) :code))))))

(ert-deftest yeah-acp-handle-message-rejects-malformed-json ()
  (yeah-acp-test--with-server
    (let* ((response (yeah-acp-test--parse
                      (yeah-acp-handle-message "{not-json"))))
      (should (= -32700 (plist-get (plist-get response :error) :code))))))

(ert-deftest yeah-acp-handle-message-refuses-unknown-method ()
  (yeah-acp-test--with-server
    (let ((response
           (yeah-acp-test--parse
            (yeah-acp-handle-message
             (concat "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"unknown\","
                     "\"params\":{}}")))))
      (should (= -32601 (plist-get (plist-get response :error) :code))))))

(ert-deftest yeah-acp-permission-response-allows-only-an-explicit-allow ()
  "Unknown, failed, cancelled and rejected responses never allow an effect."
  (should (equal (plist-get
                  (yeah-acp--permission-decision
                   (list :result (list :outcome
                                       (list :outcome "selected"
                                             :optionId "allow-once"))))
                 :effect)
                 :allow))
  (dolist (message
           (list (list :error (list :code -32601 :message "unsupported"))
                 (list :result (list :outcome (list :outcome "cancelled")))
                 (list :result (list :outcome (list :outcome "selected"
                                                      :optionId "reject-once")))
                 (list :result (list :outcome (list :outcome "selected"
                                                      :optionId "unknown")))
                 (list)))
    (should (eq (plist-get (yeah-acp--permission-decision message) :effect)
                :deny))))

(provide 'test-yeah-acp)
;;; test-yeah-acp.el ends here
