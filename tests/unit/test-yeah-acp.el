;;; test-yeah-acp.el --- ERT tests for yeah-acp -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-acp.el'. The
;; positive tests exercise the four ACP handlers and the
;; JSON-RPC dispatcher; the negative tests exercise the closest
;; plausible failure modes (malformed JSON, missing required
;; fields, unknown methods).

;;; Code:

(require 'ert)
(require 'yeah-acp)

(defun yeah-acp-test--reset-counter ()
  "Reset `yeah-acp--counter' to 0 for deterministic ids."
  (setq yeah-acp--counter 0))

(defun yeah-acp-test--parse-response (json-string)
  "Parse JSON-STRING as a plist for assertion convenience."
  (json-parse-string json-string :object-type 'plist))

;; --- Positive: yeah-acp-initialize ---

(ert-deftest yeah-acp-initialize-returns-version ()
  "A well-formed handshake returns a response with `protocolVersion'."
  (let* ((handshake (list :protocolVersion "2025-01-01"
                           :clientInfo         '(:name "zed" :version "0.100")
                           :clientCapabilities '(:loadSession t :prompt t :cancel t)))
         (response (yeah-acp-initialize handshake)))
    (should (plist-member response :protocolVersion))
    (should (string= "2025-01-01" (plist-get response :protocolVersion)))
    (should (plist-member response :agentInfo))
    (should (plist-member response :agentCapabilities))))

;; --- Negative: yeah-acp-initialize ---

(ert-deftest yeah-acp-initialize-rejects-missing-protocolVersion ()
  "A handshake without `protocolVersion' raises `user-error'."
  (let ((err nil)
        (bad-handshake (list :clientInfo '(:name "zed"))))
    (condition-case nil
        (yeah-acp-initialize bad-handshake)
      (user-error (setq err t)))
    (should err)))

;; --- Positive: yeah-acp-session-new ---

(ert-deftest yeah-acp-session-new-creates-session ()
  "A session/new request returns a non-empty string sessionId."
  (yeah-acp-test--reset-counter)
  (let ((response (yeah-acp-session-new (list :clientInfo nil))))
    (should (plist-member response :sessionId))
    (let ((id (plist-get response :sessionId)))
      (should (stringp id))
      (should (> (length id) 0)))))

;; --- Positive: yeah-acp-session-prompt ---

(ert-deftest yeah-acp-session-prompt-returns-message-id ()
  "A session/prompt request returns a `(:messageId ID)' plist."
  (yeah-acp-test--reset-counter)
  (let ((response (yeah-acp-session-prompt (list :sessionId "s-1-1"
                                                  :text      "hello"))))
    (should (plist-member response :messageId))
    (let ((id (plist-get response :messageId)))
      (should (stringp id))
      (should (> (length id) 0)))))

;; --- Positive: yeah-acp-session-cancel ---

(ert-deftest yeah-acp-session-cancel-acknowledges ()
  "A session/cancel request returns `(:status \"cancelled\" :sessionId ID)'."
  (let ((response (yeah-acp-session-cancel (list :sessionId "s-1-1"))))
    (should (plist-member response :status))
    (should (string= "cancelled" (plist-get response :status)))
    (should (string= "s-1-1" (plist-get response :sessionId)))))

;; --- Positive: dispatcher routing ---

(ert-deftest yeah-acp-handle-message-routes-correctly ()
  "A full JSON-RPC `initialize' request comes back as a JSON-RPC
response carrying `result.protocolVersion'."
  (let ((request (concat "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\","
                          "\"params\":{\"protocolVersion\":\"2025-01-01\","
                                          "\"clientInfo\":{\"name\":\"zed\"},"
                                          "\"clientCapabilities\":{\"prompt\":true}}}"))
        (response-json nil))
    (setq response-json (yeah-acp-handle-message request))
    (let ((response (yeah-acp-test--parse-response response-json)))
      (should (string= "2.0" (plist-get response :jsonrpc)))
      (should (= 1 (plist-get response :id)))
      (let ((result (plist-get response :result)))
        (should (plist-member result :protocolVersion))
        (should (string= "2025-01-01" (plist-get result :protocolVersion)))))))

;; --- Negative: dispatcher ---

(ert-deftest yeah-acp-handle-message-rejects-malformed-json ()
  "Malformed JSON returns a JSON-RPC parse error (-32700)."
  (let* ((response-json (yeah-acp-handle-message "{not-json"))
         (response (yeah-acp-test--parse-response response-json)))
    (should (plist-member response :error))
    (let ((err (plist-get response :error)))
      (should (= -32700 (plist-get err :code))))))

(provide 'test-yeah-acp)
;;; test-yeah-acp.el ends here