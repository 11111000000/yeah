;;; test-yeah-service-control.el --- service control tests -*- lexical-binding: t; no-byte-compile: t -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; Part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License 2.0.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'yeah-client)
(require 'yeah-service-ui)

(defun test-yeah-service-control--messages (output)
  "Return the JSON-RPC messages in OUTPUT."
  (mapcar (lambda (line)
            (json-parse-string line :object-type 'plist :array-type 'list))
          (split-string output "\n" t)))

(defun test-yeah-service-control--message (messages method)
  "Return the request METHOD in MESSAGES."
  (cl-find method messages
           :key (lambda (message) (plist-get message :method))
           :test #'equal))

(defun test-yeah-service-control--queue-message
    (kind &optional input-id prompt reason)
  "Return a session/update notification for queue event KIND.
INPUT-ID names the input, PROMPT is its text and REASON explains a removal."
  (list :method "session/update"
        :params
        (list :sessionId "session-1"
              :update
              (append
               (list :sessionUpdate kind
                     :inputId input-id
                     :inputKind "steering")
               (when prompt
                 (list :content
                       (vector (list :type "text" :text prompt))))
               (when reason
                 (list :reason reason))))))

(ert-deftest yeah-service-control-sends-steer-withdraw-and-recover ()
  (let ((process (make-process :name "yeah-service-control-fake"
                                :command '("cat")
                                :noquery t))
        (output "")
        (client nil))
    (unwind-protect
        (progn
          (set-process-filter process
                              (lambda (_process chunk)
                                (setq output (concat output chunk))))
          (setq client
                (yeah-client--make
                 :connection process
                 :pending (make-hash-table :test 'equal)
                 :counter 0))
          (with-temp-buffer
            (yeah-service-ui-mode)
            (setq yeah-service-ui--client client
                  yeah-service-ui--session-id "session-1"
                  yeah-service-ui--records nil
                  yeah-service-ui--event-id 0)
            (yeah-service-ui-steer "clarify the result")
            (yeah-service-ui-withdraw "input-1")
            (yeah-service-ui-recover))
          (let ((deadline (+ (float-time) 2)))
            (while (and (< (length (split-string output "\n" t)) 3)
                        (< (float-time) deadline))
              (accept-process-output process 0.05)))
          (let* ((messages (test-yeah-service-control--messages output))
                 (steer (test-yeah-service-control--message
                         messages "session/steer"))
                 (withdraw (test-yeah-service-control--message
                            messages "session/withdraw"))
                 (recover (test-yeah-service-control--message
                           messages "session/recover")))
            (should steer)
            (should withdraw)
            (should recover)
            (should (equal (plist-get (plist-get steer :params) :sessionId)
                           "session-1"))
            (should (equal (plist-get (plist-get steer :params) :prompt)
                           "clarify the result"))
            (should (equal (plist-get (plist-get withdraw :params) :sessionId)
                           "session-1"))
            (should (equal (plist-get (plist-get withdraw :params) :inputId)
                           "input-1"))
            (should (equal (plist-get (plist-get recover :params) :sessionId)
                           "session-1"))))
      (when (process-live-p process)
        (delete-process process)))))

(ert-deftest yeah-service-control-projects-queue-events-for-the-view ()
  (with-temp-buffer
    (yeah-service-ui-mode)
    (setq yeah-service-ui--records nil
          yeah-service-ui--event-id 0)
    (dolist (event
             (list
              (test-yeah-service-control--queue-message
               "input_queued" "input-1" "first question")
              (test-yeah-service-control--queue-message
               "input_taken" "input-1")
              (test-yeah-service-control--queue-message
               "input_queued" "input-2" "second question")
              (test-yeah-service-control--queue-message
               "input_recovered" "input-2")
              (test-yeah-service-control--queue-message
               "input_queued" "input-3" "third question")
              (test-yeah-service-control--queue-message
               "input_withdrawn" "input-3" nil "not needed")))
      (yeah-service-ui--render-update (current-buffer) event))
    (let* ((records yeah-service-ui--records)
           (queued (cl-find "input-queued" records
                            :key (lambda (record) (plist-get record :type))
                            :test #'equal))
           (taken (cl-find "input-taken" records
                           :key (lambda (record) (plist-get record :type))
                           :test #'equal))
           (recovered (cl-find "input-recovered" records
                               :key (lambda (record) (plist-get record :type))
                               :test #'equal))
           (withdrawn (cl-find "input-withdrawn" records
                               :key (lambda (record) (plist-get record :type))
                               :test #'equal))
           (pending (plist-get (yeah-ui-view records) :pending-inputs)))
      (should (equal "input-queued" (plist-get queued :type)))
      (should (equal "input-1" (plist-get queued :input_id)))
      (should (equal "steering" (plist-get queued :input_kind)))
      (should (equal "first question" (plist-get queued :prompt)))
      (should (equal "input-1" (plist-get taken :input_id)))
      (should (equal "input-2" (plist-get recovered :input_id)))
      (should (equal "input-3" (plist-get withdrawn :input_id)))
      (should (equal "steering" (plist-get withdrawn :input_kind)))
      (should (equal "steering" (plist-get withdrawn :kind)))
      (should (equal "not needed" (plist-get withdrawn :reason)))
      (should (null pending)))))

(ert-deftest yeah-service-control-queue-event-is-a-pending-view-input ()
  (with-temp-buffer
    (yeah-service-ui-mode)
    (setq yeah-service-ui--records nil
          yeah-service-ui--event-id 0)
    (yeah-service-ui--render-update
     (current-buffer)
     (test-yeah-service-control--queue-message
      "input_queued" "input-1" "choose one"))
    (let ((pending (plist-get (yeah-ui-view yeah-service-ui--records)
                               :pending-inputs)))
      (should (= 1 (length pending)))
      (should (equal "input-1" (plist-get (car pending) :id)))
      (should (equal "steering" (plist-get (car pending) :kind)))
      (should (equal "choose one" (plist-get (car pending) :prompt))))))

(ert-deftest yeah-service-control-uses-the-selected-network-family ()
  (let ((directory (make-temp-file "yeah-service-control" t)))
    (unwind-protect
        (let* ((socket (expand-file-name "service.sock" directory))
               (port-file (yeah-client-port-file socket)))
          (with-temp-file port-file
            (insert "43210"))
          (let ((yeah-client-network-family 'local))
            (let ((params (yeah-client-connection-params socket)))
              (should (eq (plist-get params :family) 'local))
              (should (equal (plist-get params :service) socket))))
          (let ((yeah-client-network-family 'ipv4))
            (let ((params (yeah-client-connection-params socket)))
              (should (eq (plist-get params :family) 'ipv4))
              (should (equal (plist-get params :host) "127.0.0.1"))
              (should (equal (plist-get params :service) 43210))))
          (let ((yeah-client-network-family nil))
            (should (eq (yeah-client-effective-network-family)
                        (yeah-client-automatic-network-family)))))
      (ignore-errors (delete-directory directory t)))))

(ert-deftest yeah-service-control-settles-an-empty-result ()
  (let* ((client (yeah-client--make
                   :pending (make-hash-table :test 'equal)
                   :counter 0))
         (answer nil))
    (puthash 7 (lambda (result error)
                 (setq answer (list result error)))
              (yeah-client-pending client))
    (yeah-client--handle client "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{}}")
    (should (equal answer (list nil nil)))))

(ert-deftest yeah-service-control-exposes-the-control-keys ()
  (should (eq (lookup-key yeah-service-ui-mode-map (kbd "s"))
              #'yeah-service-ui-steer))
  (should (eq (lookup-key yeah-service-ui-mode-map (kbd "r"))
              #'yeah-service-ui-recover))
  (should (eq (lookup-key yeah-service-ui-mode-map (kbd "w"))
              #'yeah-service-ui-withdraw)))

(ert-deftest yeah-service-control-driver-has-the-attached-capabilities ()
  (let ((journal (yeah-journal-open nil nil "*yeah service control test*")))
    (unwind-protect
        (let ((driver (yeah-service-ui--driver journal)))
          (should (equal (plist-get driver :capabilities)
                         '(:ask :steer :cancel :export)))
          (should (functionp (plist-get driver :steer)))
          (should (functionp (plist-get driver :export)))
          (should-not (null (plist-get driver :capabilities))))
      (when (buffer-live-p (yeah-journal-buffer journal))
        (kill-buffer (yeah-journal-buffer journal))))))

(provide 'test-yeah-service-control)
;;; test-yeah-service-control.el ends here
