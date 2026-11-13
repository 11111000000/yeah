;;; yeah-events.el --- the vocabulary of the session log -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The session log was append-only and honest, and its records had no
;; vocabulary: there was no type for the start of a tool call, for the
;; end of one, for the request of a permission, for the refusal of one,
;; for the spend of tokens. A log that cannot be read without knowing
;; the code that wrote it is a trace, not a specification.
;;
;; This module gives the log its vocabulary. Every record is one of the
;; declared events, and it carries the fields its type declares. The
;; vocabulary is not a description of what happens to be written: writing
;; an event of an unknown type, or with fields that are not the declared
;; ones, is refused.
;;
;; The log is still append-only, and it is still a log of what happened
;; rather than a story about it: the order of the records is the order of
;; the events.
;;
;; The task list of a run is a part of this vocabulary: a `todo' event
;; carries the tasks that were added or changed, so that the list of the
;; run is what the log says when it is read from the beginning.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)

(defconst yeah-events--vocabulary
  '((:type "header"             :fields (:session_id :timestamp))
    (:type "user-message"       :fields (:payload))
    (:type "assistant-message"  :fields (:payload))
    (:type "tool-request"       :fields (:tool :args))
    (:type "permission-request" :fields (:action :resource))
    (:type "permission-decision" :fields (:action :resource :effect))
    (:type "tool-end"           :fields (:tool :ok :payload))
    (:type "compaction"         :fields (:cut_point :summary :timestamp))
    (:type "pruning"            :fields (:keep-chars))
    (:type "steering"           :fields (:payload))
    (:type "nudge"              :fields (:payload))
    (:type "cancel"             :fields (:payload))
    (:type "spawn"              :fields (:child :role :depth))
    (:type "child-end"          :fields (:child :role :ok :summary))
    (:type "input-withdrawn"    :fields (:kind :reason))
    (:type "usage"              :fields (:input :output))
    (:type "todo"               :fields (:items :operation))
    (:type "error"              :fields (:payload))
    (:type "finish"             :fields (:summary)))
  "The vocabulary of the event log.

Every record of the log is one of these, and it carries the fields its
type declares. A record also carries the `:type' that names it and the
`:id' the log gives it; those two are not among the declared fields.")

(defun yeah-events-types ()
  "Return the names of the event types, in the order of the vocabulary."
  (mapcar (lambda (entry) (plist-get entry :type)) yeah-events--vocabulary))

(defun yeah-events-spec (type)
  "Return the specification of the event TYPE, or nil when it is unknown."
  (cl-find-if (lambda (entry) (equal (plist-get entry :type) type))
              yeah-events--vocabulary))

(defun yeah-events--same-fields-p (a b)
  "Non-nil when the field names A and B are the same, in any order."
  (equal (sort (copy-sequence a) #'string<)
         (sort (copy-sequence b) #'string<)))

(defun yeah-events--keys (plist)
  "Return the keys of the plist PLIST, in the order they are in."
  (let ((keys nil) (rest plist))
    (while rest
      (setq keys (cons (car rest) keys))
      (setq rest (cddr rest)))
    (nreverse keys)))

(defun yeah-events--check (type fields)
  "Signal a `user-error' unless TYPE is known and FIELDS are its fields.
FIELDS is a plist of keyword pairs."
  (unless (yeah-events-spec type)
    (signal 'user-error
            (list (format "yeah-events: unknown event type: %S" type))))
  (let* ((declared (plist-get (yeah-events-spec type) :fields))
         (given (yeah-events--keys fields)))
    (unless (yeah-events--same-fields-p declared given)
      (signal 'user-error
              (list (format "yeah-events: the event %S declares %S and was given %S"
                            type declared given))))))

(defun yeah-events-boolean-p (value)
  "Return non-nil when VALUE is a true boolean of a journal record.
The journal writes a failure as JSON `false', which reads back as the
symbol `:false'; an older record wrote it as an empty object, which
reads back as nil.  Both mean the same thing: not true."
  (and value (not (eq value :false))))

(defvar yeah-events-write-functions nil
  "Functions called with (SESSION TYPE FIELDS ID) after a validated append.
Observers are observational: errors are reported and do not stop other
listeners or the write.")

;;;###autoload
(defun yeah-events-write (session type &rest fields)
  "Append an event of TYPE with FIELDS to the log of SESSION.
FIELDS are keyword pairs and must be exactly the fields TYPE declares.
Return the identifier of the new record."
  (yeah-events--check type fields)
  (let ((id (yeah-session-append session (cons :type (cons type fields)))))
    (dolist (listener yeah-events-write-functions)
      (condition-case err
          (funcall listener session type fields id)
        (error
         (message "yeah-events listener failed: %s" (error-message-string err)))))
    id))

(provide 'yeah-events)
;;; yeah-events.el ends here
