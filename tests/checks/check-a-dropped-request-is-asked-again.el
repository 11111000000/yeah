;;; check-a-dropped-request-is-asked-again.el --- a request the provider dropped is asked again -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A provider that drops the connection (a timeout of the transport, a closed
;; connection, a server that is too busy) did not refuse the request: the
;; request never reached an answer.  The harness ended the run on such a
;; failure, and three live runs of the wave 41 died that way — the run of
;; 16:15 with "Curl failed with exit code 28", the run of 16:26 with "Curl
;; failed with exit code 16", and the run of 17:10 with "Curl failed with
;; exit code 28" — after 108, 122 and 70 calls of tools.
;;
;; The request is asked again instead.  The retry is bounded, and the model
;; is told what happened and what the run has done (wave 47), so that the
;; retry continues the work instead of starting it over.
;;
;; Four things are checked here.
;;
;; 1. A request that the provider dropped is asked again, and the run goes on:
;;    the journal holds the retry, and the model is asked the same question
;;    with the transcript of the run in front of it.
;; 2. A provider that is busy is asked again: it did not answer and it did
;;    not refuse.
;; 3. A provider that drops every request still ends the run: the budget of
;;    the retries bounds the tries, and the run says why it stopped.
;; 4. A request that the provider refused is not asked again: a refusal is an
;;    answer, and the run fails at once.
;;
;; The model here is a FAKE: a provider that plays the shape of the live
;; run.  No network is touched.
;;
;; Exit codes: 0 — the dropped request was asked again and the refusal was
;; not; 1 — it was not.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-tools)
(require 'yeah-turn)

(defconst yeah-check--dropped-reason
  "Curl failed with exit code 28. See Curl manpage for details."
  "The reason a provider that dropped the connection gives.")

(defconst yeah-check--busy-reason
  "the provider is busy and refused the request"
  "The reason a provider that is busy gives.")

(defconst yeah-check--refused-reason
  "the provider refused the request"
  "The reason a provider that refuses a request gives.")

(defun yeah-check--fail (ok message)
  "Return MESSAGE when OK is nil, and nil when OK holds."
  (unless ok
    message))

(defun yeah-check--records-of-type (records type)
  "Return the records of TYPE in RECORDS."
  (cl-remove-if-not (lambda (record)
                      (equal type (plist-get record :type)))
                    records))

(defun yeah-check--probe ()
  "Register the tool the fake model calls, and allow it."
  (yeah-tools-reset-for-test)
  (yeah-perm-rules-reset-for-test)
  (yeah-tools-register
   (list :name "probe" :description "probe" :input nil
         :handler (lambda () "the output of the probe")))
  (yeah-perm-rules-add (yeah-perm-rule-make "probe" "*" 'allow)))

(defun yeah-check--play (script cell callback)
  "Play the next action of SCRIPT into CALLBACK.
CELL is the cell that holds the place of the script: it is shared by the
transport and by the continuation of a call, so that the actions are played
once and in order.  The action `tool' calls the tool of the model, and the
answer that follows the call is the next action of the script: the results
of a tool reach the model inside the same request, and the provider may drop
that request too."
  (let* ((index (aref cell 0))
         (action (if (< index (length script)) (nth index script) 'text)))
    (aset cell 0 (1+ index))
    (pcase action
      ('drop
       ;; The shape of a transport that died: the request never reached an
       ;; answer, and the info of the request names the failure.
       (funcall callback (cons 'error yeah-check--dropped-reason)
                (list :error yeah-check--dropped-reason)))
      ('busy
       ;; The shape of a provider that is too busy: the status of the
       ;; wire is a string, and the info names it.
       (funcall callback (cons 'error yeah-check--busy-reason)
                (list :error yeah-check--busy-reason :http-status "529")))
      ('refuse
       ;; The shape of a provider that refused the request: the status of
       ;; the wire is a string, and the request is not asked again.
       (funcall callback (cons 'error yeah-check--refused-reason)
                (list :error yeah-check--refused-reason :http-status "400")))
      ('tool
       (funcall callback
                (list 'tool-call
                      (list (list :name "probe") (list)
                            (lambda (_value)
                              (yeah-check--play script cell callback))))))
      ('plan
       (funcall callback "I'll read the file next."))
      (_
       ;; The model ends the run through the call of `finish': a supervised
       ;; run does not end on the words of the model (wave 53).
       (funcall callback
                (list 'tool-call
                      (list (list :name "finish")
                            (list "the work is done")
                            (lambda (_answer) nil))))))))

(defun yeah-check--transport (script record)
  "Return a transport that plays SCRIPT, and that tells RECORD every prompt.
RECORD is called with the prompt of every request of the model."
  (let ((cell (vector 0)))
    (lambda (prompt callback)
      (funcall record prompt)
      (yeah-check--play script cell callback))))

(defun yeah-check--wait (turn)
  "Wait until TURN is done, or ten seconds pass."
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (yeah-turn-done turn))
                (< (float-time) deadline))
      (accept-process-output nil 0.02))))

(defun yeah-check--run (actions &optional max-retries)
  "Run the turn with the script ACTIONS and return the run of the model.
MAX-RETRIES bounds the tries of a request that the provider dropped."
  (let* ((root (make-temp-file "yeah-retry" t))
         (session (yeah-session-open "retry" root))
         (prompts nil))
    (yeah-check--probe)
    (let ((turn (yeah-turn-run session "start"
                               (yeah-check--transport
                                actions
                                (lambda (prompt) (push prompt prompts)))
                               nil 60000 3 nil nil nil nil nil max-retries)))
      (yeah-check--wait turn)
      (let ((result (list :turn turn
                           :records (yeah-session-records session)
                           :prompts (nreverse prompts))))
        (ignore-errors (delete-directory root t t))
        result))))

(defun yeah-check--a-dropped-request-is-asked-again ()
  "A request that the provider dropped is asked again, and the run goes on."
  (let* ((result (yeah-check--run '(tool drop text)))
         (turn (plist-get result :turn))
         (prompts (plist-get result :prompts))
         (records (plist-get result :records))
         (retries (yeah-check--records-of-type records "retry"))
         (retry (nth 1 prompts)))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'completed)
      (format "the run did not go on after the dropped request: %S"
              (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length prompts) 2)
      (format "the model was asked %d times, not twice" (length prompts)))
     (yeah-check--fail
      (= (length retries) 1)
      (format "the journal holds %d retries, not one" (length retries)))
     (yeah-check--fail
      (and retry (string-match-p "\\[retry\\] the provider dropped the request"
                                retry))
      (format "the retry does not tell the model what happened: %S" retry))
     (yeah-check--fail
      (and retry (string-match-p "the output of the probe" retry))
      (format "the retry does not carry the work of the run: %S" retry))
     (yeah-check--fail
      (and retry (string-match-p "start" retry))
      (format "the retry does not ask the question of the run again: %S" retry))
     (yeah-check--fail
      (and (nth 0 prompts) (equal "start" (nth 0 prompts)))
      (format "the first request of the run is %S, not the request itself"
              (nth 0 prompts)))
     (yeah-check--fail
      (null (cl-find-if (lambda (record)
                          (and (equal "user-message"
                                      (plist-get record :type))
                               (stringp (plist-get record :payload))
                               (string-match-p "This is what has been done"
                                               (plist-get record :payload))))
                        records))
      "the journal holds the transcript: the projection is a copy of the run"))))

(defun yeah-check--a-busy-provider-is-asked-again ()
  "A provider that is busy is asked again: it did not answer and did not refuse."
  (let* ((result (yeah-check--run '(tool busy text)))
         (turn (plist-get result :turn))
         (prompts (plist-get result :prompts))
         (records (plist-get result :records))
         (retries (yeah-check--records-of-type records "retry")))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'completed)
      (format "the run did not go on after the busy provider: %S"
              (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length retries) 1)
      (format "the journal holds %d retries, not one" (length retries)))
     (yeah-check--fail
      (= (length prompts) 2)
      (format "the model was asked %d times, not twice" (length prompts))))))

(defun yeah-check--a-provider-that-drops-everything-still-ends-the-run ()
  "A provider that drops every request still ends the run, and says why."
  (let* ((result (yeah-check--run '(drop drop drop drop drop) 2))
         (turn (plist-get result :turn))
         (prompts (plist-get result :prompts))
         (records (plist-get result :records))
         (errors (yeah-check--records-of-type records "error"))
         (retries (yeah-check--records-of-type records "retry")))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'failed)
      (format "the run did not end after the budget of the retries: %S"
              (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length prompts) 3)
      (format "the model was asked %d times, not once and twice"
              (length prompts)))
     (yeah-check--fail
      (= (length retries) 2)
      (format "the journal holds %d retries, not two" (length retries)))
     (yeah-check--fail
      (= (length errors) 1)
      (format "the journal holds %d errors, not one" (length errors)))
     (yeah-check--fail
      (and errors
           (string-match-p "exit code 28" (or (plist-get (car errors) :payload) "")))
      "the run does not say why it stopped"))))

(defun yeah-check--a-refused-request-is-not-asked-again ()
  "A request that the provider refused is not asked again."
  (let* ((result (yeah-check--run '(refuse)))
         (turn (plist-get result :turn))
         (prompts (plist-get result :prompts))
         (records (plist-get result :records)))
    (list
     (yeah-check--fail
      (eq (yeah-turn-state turn) 'failed)
      (format "the run did not end on the refusal: %S" (yeah-turn-state turn)))
     (yeah-check--fail
      (= (length prompts) 1)
      (format "the model was asked %d times, not once" (length prompts)))
     (yeah-check--fail
      (null (yeah-check--records-of-type records "retry"))
      "the journal holds a retry of a request that was refused"))))

(let ((failures (delq nil
                     (append
                      (yeah-check--a-dropped-request-is-asked-again)
                      (yeah-check--a-busy-provider-is-asked-again)
                      (yeah-check--a-provider-that-drops-everything-still-ends-the-run)
                      (yeah-check--a-refused-request-is-not-asked-again)))))
  (dolist (failure failures)
    (message "retry: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-dropped-request-is-asked-again.el ends here
