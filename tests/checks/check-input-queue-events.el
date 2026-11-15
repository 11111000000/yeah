;;; check-input-queue-events.el --- the pending queue is in the journal -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The pending queue of a session is a projection of the journal: what the
;; person asked is written into the log when it enters the queue, when it
;; starts a run, when it is recovered and when it is withdrawn.  There is no
;; second, invisible state.
;;
;; The check drives a controller with a FAKE transport that never answers,
;; so that the run stays active and the queue keeps what the person left in
;; it.  It then reads the truth twice: as the records the journal holds, and
;; as the projection the editor builds from them (`yeah-ui-view').  The
;; pending list of the controller and the pending list of the editor must
;; be the same list, and a withdrawn input must leave both.
;;
;; Recovery is covered too, and it is covered honestly.  The completion
;; callback of a finished run starts the next ask by itself: the journal
;; says `input-taken' for that ask.  An explicit recovery therefore needs a
;; controller with no active turn, and the check gets one the way a restart
;; gets one: a fresh controller over the same session, whose pending queue
;; survives.  The check proves that the recovered input is named by an
;; `input-recovered' record and not by an `input-taken' one.
;;
;; Exit codes: 0 — the journal and the queue agree; 1 — they do not.

;;; Code:

(require 'cl-lib)
(require 'yeah-control)
(require 'yeah-input)
(require 'yeah-session)
(require 'yeah-ui)

(defun yeah-check--queue-events (records type)
  "Return every record of RECORDS whose type is TYPE."
  (seq-filter (lambda (record) (equal (plist-get record :type) type))
              records))

(defun yeah-check--pending-ids (inputs)
  "Return the id of every input in INPUTS."
  (mapcar (lambda (input) (plist-get input :id)) inputs))

(defun yeah-check--named-p (records type id)
  "Return non-nil when a record of TYPE in RECORDS names ID."
  (cl-some (lambda (record) (equal (plist-get record :input_id) id))
           (yeah-check--queue-events records type)))

(let ((failures nil)
      (root (make-temp-file "yeah-queue-events" t)))
  (unwind-protect
      (progn
        (let* ((yeah-input-directory root)
               (session (yeah-session-open "queue-events" root))
               (control (yeah-control-new
                         session
                         (lambda (_prompt _callback) nil)
                         nil 60000 0))
               ;; A fresh controller over the same session: the state after a
               ;; restart.  The pending queue of the session survives it, and
               ;; no turn is active, so an explicit recovery is possible.
               (restart (yeah-control-new
                         session
                         (lambda (_prompt _callback) nil)
                         nil 60000 0)))
          ;; --- the person asks twice: the first one starts a run, the
          ;; --- second one waits in the queue
          (let* ((first (yeah-control-submit control "first"))
                 (second (yeah-control-submit control "second"))
                 (records (yeah-session-records session))
                 (queued (yeah-check--queue-events records "input-queued"))
                 (taken (yeah-check--queue-events records "input-taken")))
            ;; --- the journal carries the queue, with the right ids ---
            (unless (= 2 (length queued))
              (push (format "the journal holds %d queued inputs, expected 2"
                            (length queued))
                    failures))
            (unless (equal first (plist-get (car queued) :input_id))
              (push "the journal does not name the first queued input" failures))
            (unless (equal second (plist-get (nth 1 queued) :input_id))
              (push "the journal does not name the second queued input" failures))
            (unless (equal "ask" (plist-get (car queued) :input_kind))
              (push "the journal does not name the kind of a queued input"
                    failures))
            (unless (= 1 (length taken))
              (push (format "the journal holds %d taken inputs, expected 1"
                            (length taken))
                    failures))
            (unless (equal first (plist-get (car taken) :input_id))
              (push "the journal does not name the input that started the run"
                    failures))
            ;; --- the queue of the control and the projection of the
            ;; --- editor are the same list ---
            (let ((pending (yeah-control-pending control))
                  (projected (plist-get (yeah-ui-view records) :pending-inputs)))
              (unless (equal (yeah-check--pending-ids pending)
                             (yeah-check--pending-ids projected))
                (push (format "the editor sees %S and the control holds %S"
                              (yeah-check--pending-ids projected)
                              (yeah-check--pending-ids pending))
                      failures)))
            ;; --- the person withdraws the waiting input ---
            (yeah-control-withdraw control second)
            (let ((withdrawn (yeah-check--queue-events
                              (yeah-session-records session)
                              "input-withdrawn")))
              (unless (= 1 (length withdrawn))
                (push (format "the journal holds %d withdrawals, expected 1"
                              (length withdrawn))
                      failures))
              (unless (equal second (plist-get (car withdrawn) :input_id))
                (push "the journal does not name the withdrawn input" failures)))
            (unless (= 0 (length (yeah-control-pending control)))
              (push "the withdrawn input is still in the queue of the control"
                    failures))
            (let ((projected (plist-get (yeah-ui-view (yeah-session-records session))
                                        :pending-inputs)))
              (unless (= 0 (length projected))
                (push (format "the editor still shows %d pending inputs"
                              (length projected))
                      failures))))
          ;; --- the person asks twice more while the first run is active ---
          (let* ((third (yeah-control-submit control "third"))
                 (fourth (yeah-control-submit control "fourth")))
            ;; --- the person cancels the running turn ---
            ;; The completion callback of a cancelled run starts the next ask
            ;; by itself: the journal says `input-taken' for the oldest ask,
            ;; and the ask behind it keeps waiting in the queue.
            (yeah-control-cancel control "the person cancelled the run")
            (let ((pending (yeah-check--pending-ids (yeah-control-pending control)))
                  (projected (plist-get (yeah-ui-view (yeah-session-records session))
                                        :pending-inputs)))
              (unless (equal pending (list fourth))
                (push (format "the queue of the control holds %S after the cancellation, expected %S"
                              pending (list fourth))
                      failures))
              (unless (equal (yeah-check--pending-ids projected) (list fourth))
                (push (format "the editor sees %S after the cancellation, expected %S"
                              (yeah-check--pending-ids projected) (list fourth))
                      failures)))
            ;; --- the person recovers the waiting input explicitly ---
            ;; Recovery needs a controller with no active turn: the
            ;; completion callback of a running turn would start the next ask
            ;; by itself.  A fresh controller over the same session is the
            ;; state after a restart: the queue of the session survives.
            (let ((outcome (condition-case error
                               (list :turn (yeah-control-recover-next restart))
                             (error (list :error error)))))
              (if (plist-get outcome :error)
                  (push (format "the recovery failed: %S"
                                (plist-get outcome :error))
                        failures)
                (unless (plist-get outcome :turn)
                  (push "the recovery did not start a run" failures))))
            ;; --- the journal says that the input was recovered ---
            (let* ((records (yeah-session-records session))
                   (recovered (yeah-check--queue-events records "input-recovered")))
              (unless (= 1 (length recovered))
                (push (format "the journal holds %d recovered inputs, expected 1"
                              (length recovered))
                      failures))
              (when recovered
                (unless (equal fourth (plist-get (car recovered) :input_id))
                  (push "the journal does not name the recovered input" failures)))
              ;; the automatic continuation is not a recovery: the input the
              ;; run started by itself is named by an `input-taken' record
              (unless (yeah-check--named-p records "input-taken" third)
                (push "the journal does not name the input the cancelled run started by itself"
                      failures))
              (when (yeah-check--named-p records "input-taken" fourth)
                (push "the recovered input was taken by the automatic continuation"
                      failures)))
            ;; --- the recovered input left the queue of both ---
            (unless (= 0 (length (yeah-control-pending control)))
              (push "the recovered input is still in the queue of the control"
                    failures))
            (unless (= 0 (length (yeah-control-pending restart)))
              (push "the recovered input is still in the queue of the restart"
                    failures))
            (let ((projected (plist-get (yeah-ui-view (yeah-session-records session))
                                        :pending-inputs)))
              (unless (= 0 (length projected))
                (push (format "the editor still shows %d pending inputs"
                              (length projected))
                      failures)))))
      (dolist (failure failures)
        (message "queue: %s" failure))
      (ignore-errors (delete-directory root t))
      (if failures
          (kill-emacs 1)
        (kill-emacs 0)))))

;;; check-input-queue-events.el ends here
