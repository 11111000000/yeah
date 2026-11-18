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
;; Every record belongs to the declared vocabulary.  Writers validate the
;; event-specific payload before `yeah-session' adds the common envelope.
;; Readers continue to accept older records without that envelope.
;;
;; The pending queue of a session is visible in the log: `input-queued',
;; `input-taken', `input-recovered' and `input-withdrawn' name the input
;; they concern, so the queue of the person is a projection of the records
;; and not a second state.
;;
;; `yeah-events-write' retains its original calling convention.
;; `yeah-events-write-with-context' additionally takes explicit correlation
;; metadata; no ambient current-run variable is consulted.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)

(defconst yeah-events--envelope-required
  '(:schema_version :session_id :timestamp)
  "Envelope fields required in new records, except `:id' and `:type'.")

(defconst yeah-events--envelope-optional
  '(:run_id :turn_id :tool_call_id :parent_event_id)
  "Optional correlation fields accepted by the context-writing API.")

(defconst yeah-events--vocabulary
  '((:type "header"
     :required (:session_id :timestamp))
    (:type "user-message"
     :required (:payload))
    (:type "assistant-message"
     :required (:payload))
    (:type "tool-request"
     :required (:tool :args)
     :optional (:kind :named_args))
    (:type "permission-request"
     :required (:action :resource)
     :optional (:arguments))
    (:type "permission-decision"
     :required (:action :resource :effect)
     :optional (:reply :reason))
    (:type "tool-end"
     :required (:tool :ok :payload)
     :optional (:details :kind))
    (:type "tool-dropped"
     :required (:tool :reason)
     :optional (:args))
    (:type "compaction"
     :required (:cut_point :summary :timestamp))
    (:type "compaction-failed"
     :required (:reason))
    (:type "pruning"
     :required (:keep-chars))
    (:type "steering"
     :required (:payload))
    (:type "nudge"
     :required (:payload))
    (:type "retry"
     :required (:payload))
    (:type "cancel"
     :required (:payload))
    (:type "spawn"
     :required (:child :role :depth)
     :optional (:short-id))
    (:type "child-start"
     :required (:parent :depth)
     :optional (:short-id :role))
    (:type "child-end"
     :required (:child :role :ok :summary))
    (:type "input-queued"
     :required (:input_id :input_kind :prompt)
     :optional (:frozen))
    (:type "input-taken"
     :required (:input_id)
     :optional (:input_kind :prompt))
    (:type "input-recovered"
     :required (:input_id)
     :optional (:input_kind :prompt))
    (:type "input-withdrawn"
     :required (:kind :reason)
     :optional (:input_id))
    (:type "usage"
     :required (:input :output))
    (:type "todo"
     :required (:items :operation))
    (:type "error"
     :required (:payload))
    (:type "unfinished"
     :required (:payload :reason))
    (:type "finish"
     :required (:summary))
    (:type "session-mode"
     :required (:mode))
    (:type "session-model"
     :required (:model)))
  "The event vocabulary, with required and optional payload fields.")

(defun yeah-events-types ()
  "Return the names of the event types, in the order of the vocabulary."
  (mapcar (lambda (entry) (plist-get entry :type)) yeah-events--vocabulary))

(defun yeah-events-spec (type)
  "Return the specification of event TYPE, or nil when it is unknown.
`:required' and `:optional' describe event-specific writer fields.
The compatibility `:fields' value also includes the required on-disk envelope,
excluding `:id' and `:type', for readers that validate complete records."
  (when-let ((entry (cl-find-if
                     (lambda (candidate)
                       (equal (plist-get candidate :type) type))
                     yeah-events--vocabulary)))
    (let ((required (append yeah-events--envelope-required
                            (plist-get entry :required))))
      (plist-put (copy-sequence entry) :fields
                 (seq-uniq (copy-sequence required))))))

(defun yeah-events--keys (plist)
  "Return the keys of PLIST in their original order."
  (unless (and (proper-list-p plist) (zerop (% (length plist) 2)))
    (signal 'user-error (list "yeah-events: fields must be a proper plist")))
  (let ((keys nil)
        (rest plist))
    (while rest
      (push (car rest) keys)
      (setq rest (cddr rest)))
    (nreverse keys)))

(defun yeah-events--check (type fields)
  "Signal `user-error' unless TYPE accepts the payload FIELDS."
  (let ((spec (yeah-events-spec type)))
    (unless spec
      (signal 'user-error
              (list (format "yeah-events: unknown event type: %S" type))))
    (let* ((required (plist-get spec :required))
           (optional (plist-get spec :optional))
           (given (yeah-events--keys fields))
           (missing (seq-remove (lambda (key) (memq key given)) required))
           (unknown (seq-remove (lambda (key) (memq key (append required optional)))
                                given)))
      (when (or missing unknown)
        (signal 'user-error
                (list (format "yeah-events: %S has missing fields %S and unknown fields %S"
                              type missing unknown)))))))

(defun yeah-events--context (context)
  "Validate CONTEXT and return its non-nil correlation fields in canonical order."
  (dolist (key (yeah-events--keys context))
    (unless (memq key yeah-events--envelope-optional)
      (signal 'user-error
              (list (format "yeah-events: unknown context field %S" key)))))
  (dolist (key '(:run_id :turn_id :tool_call_id))
    (when-let ((value (plist-get context key)))
      (unless (and (stringp value) (not (string-empty-p value)))
        (signal 'user-error
                (list (format "yeah-events: %S must be a nonempty string" key))))))
  (when-let ((parent (plist-get context :parent_event_id)))
    (unless (and (integerp parent) (>= parent 0))
      (signal 'user-error
              (list "yeah-events: :parent_event_id must be a nonnegative integer"))))
  (let ((normalized nil))
    (dolist (key yeah-events--envelope-optional)
      (when (plist-get context key)
        (setq normalized (append normalized (list key (plist-get context key))))))
    normalized))

(defun yeah-events-boolean-p (value)
  "Return non-nil when VALUE is a true boolean of a journal record.
The journal writes a failure as JSON `false', which reads back as the
symbol `:false'; an older record wrote it as an empty object, which
reads back as nil.  Both mean the same thing: not true."
  (and value (not (eq value :false))))

(defvar yeah-events-write-functions nil
  "Functions called with (SESSION TYPE FIELDS ID) after a validated append.
FIELDS contains the event payload and any explicit correlation fields.
Observers are observational: errors are reported and do not stop other
listeners or the write.")

(defun yeah-events--write (session type context fields)
  "Append TYPE with FIELDS and CONTEXT to SESSION and notify observers."
  (yeah-events--check type fields)
  (let* ((normalized (yeah-events--context context))
         (id (yeah-session-append session (cons :type (cons type fields))
                                  normalized)))
    (dolist (listener yeah-events-write-functions)
      (condition-case err
          (funcall listener session type (append fields normalized) id)
        (error
         (message "yeah-events listener failed: %s" (error-message-string err)))))
    id))

;;;###autoload
(defun yeah-events-write (session type &rest fields)
  "Append an event of TYPE with FIELDS to the log of SESSION.
FIELDS are the required and optional payload fields declared for TYPE.
Return the monotonic integer identifier of the new record."
  (yeah-events--write session type nil fields))

;;;###autoload
(defun yeah-events-write-with-context (session type context &rest fields)
  "Append TYPE with FIELDS and explicit correlation CONTEXT to SESSION.
CONTEXT accepts only `:run_id', `:turn_id', `:tool_call_id' and
`:parent_event_id'.  Nil optional values are omitted.  The common schema,
session, id and timestamp envelope is always supplied by `yeah-session'.
Return the monotonic integer identifier of the new record."
  (yeah-events--write session type context fields))

(provide 'yeah-events)
;;; yeah-events.el ends here
