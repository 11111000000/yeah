;;; yeah-ui.el --- a pure projection of the session journal -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; `yeah-ui-view' is a one-pass, side-effect-free projection of journal
;; records.  It does not read files, create buffers, choose faces or depend on
;; the execution kernel.  Stable envelope ids correlate tool calls, approvals
;; and child work.  Records from older journals use a deliberately conservative
;; positional fallback: only a unique candidate is correlated; ambiguity is
;; represented as unknown rather than guessed.

;;; Code:

(require 'cl-lib)

(cl-defstruct (yeah-ui--projection (:constructor yeah-ui--make-projection))
  session
  capabilities
  blocks
  calls
  approvals
  inputs
  (calls-by-id (make-hash-table :test 'equal))
  (calls-by-request (make-hash-table :test 'equal))
  (legacy-calls (make-hash-table :test 'equal))
  (approvals-by-tool (make-hash-table :test 'equal))
  (approvals-by-request (make-hash-table :test 'equal))
  (legacy-approvals (make-hash-table :test 'equal))
  (inputs-by-id (make-hash-table :test 'equal))
  (children (make-hash-table :test 'equal))
  current-activity
  current-activity-key
  (activity-children (make-hash-table :test 'eq))
  usage-input
  usage-output
  usage-reported-p
  (estimated 0)
  (state 'idle)
  error)

(defun yeah-ui--value (record &rest keys)
  "Return the value of the first of KEYS present in RECORD."
  (cl-loop for key in keys
           when (plist-member record key)
           return (plist-get record key)))

(defun yeah-ui--event-key (record index)
  "Return a deterministic key for RECORD at zero-based INDEX."
  (or (plist-get record :id) (format "record-%d" index)))

(defun yeah-ui--event-block-id (record index)
  "Return the stable block id for RECORD at zero-based INDEX."
  (format "event:%s" (yeah-ui--event-key record index)))

(defun yeah-ui--block (record _index kind id &rest fields)
  "Build a block of KIND with ID from RECORD and append FIELDS."
  (append
   (list :kind kind
         :id id
         :event-id (plist-get record :id)
         :timestamp (plist-get record :timestamp)
         :run-id (yeah-ui--value record :run_id :run-id)
         :turn-id (yeah-ui--value record :turn_id :turn-id)
         :parent-event-id (yeah-ui--value record :parent_event_id
                                          :parent-event-id))
   fields))

(defun yeah-ui--add-block (projection block)
  "Add BLOCK to PROJECTION and return it."
  (push block (yeah-ui--projection-blocks projection))
  block)

(defun yeah-ui--generic (projection record index &optional reason)
  "Add an explicit generic block for RECORD at INDEX with optional REASON."
  (yeah-ui--add-block
   projection
   (yeah-ui--block record index :event (yeah-ui--event-block-id record index)
                   :event-type (plist-get record :type)
                   :record record
                   :fallback-reason reason)))

(defun yeah-ui--true-p (value)
  "Return non-nil when journal VALUE represents true."
  (and value (not (memq value '(:false :json-false)))))

(defun yeah-ui--allowed-p (effect)
  "Return non-nil when permission EFFECT allows execution."
  (or (eq effect 'allow) (eq effect :allow) (equal effect "allow")))

(defun yeah-ui--normalize-args (record)
  "Return normalized arguments carried by RECORD.
New records carry their normalized value directly.  Older records printed the
argument list; read that printed representation without read-time evaluation,
and retain the original string when it is not one complete readable value."
  (let ((args (yeah-ui--value record :arguments :args)))
    (if (not (stringp args))
        args
      (condition-case nil
          (let* ((read-eval nil)
                 (parsed (read-from-string args))
                 (rest (substring args (cdr parsed))))
            (if (string-match-p "\\`[ \t\n\r\f]*\\'" rest)
                (car parsed)
              args))
        (error args)))))

(defun yeah-ui--close-activity (projection)
  "End the current contiguous tool activity in PROJECTION."
  (setf (yeah-ui--projection-current-activity projection) nil
        (yeah-ui--projection-current-activity-key projection) nil))

(defun yeah-ui--start-activity (projection record index &optional explicit)
  "Start and add an activity for RECORD at INDEX.
EXPLICIT is the activity id supplied by a real activity event, if any."
  (let* ((key (or (yeah-ui--value record :turn_id :turn-id)
                  (yeah-ui--value record :run_id :run-id)
                  'session))
         (activity
          (yeah-ui--block
           record index :activity
           (or explicit (format "activity:%s" (yeah-ui--event-key record index)))
           :text (plist-get record :payload)
           :state 'running
           :children nil)))
    (yeah-ui--add-block projection activity)
    (setf (yeah-ui--projection-current-activity projection) activity
          (yeah-ui--projection-current-activity-key projection) key)
    activity))

(defun yeah-ui--activity-for (projection record index)
  "Return the activity that owns a tool RECORD at INDEX."
  (let ((key (or (yeah-ui--value record :turn_id :turn-id)
                 (yeah-ui--value record :run_id :run-id)
                 'session)))
    (unless (and (yeah-ui--projection-current-activity projection)
                 (equal key (yeah-ui--projection-current-activity-key projection)))
      (yeah-ui--start-activity projection record index))
    (yeah-ui--projection-current-activity projection)))

(defun yeah-ui--start-call (projection record index request-p stable-p)
  "Create a tool block from RECORD at INDEX.
REQUEST-P says whether this is a request rather than an unmatched end.
STABLE-P says whether the record has a stable tool call id."
  (let* ((activity (yeah-ui--activity-for projection record index))
         (name (plist-get record :tool))
         (call-id (if stable-p
                      (yeah-ui--value record :tool_call_id :tool-call-id)
                    (format "legacy-tool:%s" (yeah-ui--event-key record index))))
         (request-id (if request-p
                         (plist-get record :id)
                       (yeah-ui--value record :request_event_id :request-event-id)))
         (call (yeah-ui--block
                record index :tool call-id
                :tool name
                :name name
                :args (and request-p (yeah-ui--normalize-args record))
                :state 'running
                :ok nil
                :result nil
                :artifacts nil
                :truncated nil
                :metadata nil
                :request-id request-id
                :tool-call-id (and stable-p call-id)
                :activity-id (plist-get activity :id)
                :correlation (if stable-p 'by-id 'legacy))))
    (push call (gethash activity (yeah-ui--projection-activity-children projection)))
    (push call (yeah-ui--projection-calls projection))
    (when (and request-p stable-p)
      (puthash call-id call (yeah-ui--projection-calls-by-id projection)))
    (when (and request-p request-id)
      (puthash request-id call (yeah-ui--projection-calls-by-request projection)))
    (when (and request-p (not stable-p))
      (push call (gethash name (yeah-ui--projection-legacy-calls projection))))
    (setf (yeah-ui--projection-state projection) 'running)
    call))

(defun yeah-ui--mark-ambiguous-calls (projection name record index)
  "Mark same-name legacy calls ambiguous and preserve RECORD as a generic event.
PROJECTION and NAME select the ambiguous candidates; INDEX locates RECORD."
  (let ((calls (gethash name (yeah-ui--projection-legacy-calls projection))))
    (dolist (call calls)
      (setf (plist-get call :state) 'unknown
            (plist-get call :correlation) 'ambiguous))
    (remhash name (yeah-ui--projection-legacy-calls projection))
    (yeah-ui--generic projection record index 'ambiguous-tool-correlation)))

(defun yeah-ui--finish-call (call record)
  "Update tool CALL from its correlated terminal RECORD."
  (let* ((ok (yeah-ui--true-p (plist-get record :ok)))
         (refused (eq (plist-get call :state) 'refused))
         (result (yeah-ui--value record :payload :result))
         (nested (and (listp result) result)))
    (setf (plist-get call :event-id) (plist-get record :id)
          (plist-get call :result) result
          (plist-get call :artifacts)
          (or (plist-get record :artifacts)
              (and nested (plist-get nested :artifacts)))
          (plist-get call :truncated)
          (or (plist-get record :truncated)
              (and nested (plist-get nested :truncated)))
          (plist-get call :metadata)
          (or (plist-get record :metadata)
              (and nested (plist-get nested :metadata)))
          (plist-get call :ok) (and ok (not refused) t)
          (plist-get call :state) (cond (refused 'refused)
                                        (ok 'done)
                                        (t 'failed)))))

(defun yeah-ui--end-call (projection record index)
  "Correlate one tool-end RECORD at INDEX in PROJECTION."
  (let* ((call-id (yeah-ui--value record :tool_call_id :tool-call-id))
         (request-id (yeah-ui--value record :request_event_id :request-event-id))
         (name (plist-get record :tool))
         (call (cond
                (call-id (gethash call-id (yeah-ui--projection-calls-by-id projection)))
                (request-id
                 (gethash request-id (yeah-ui--projection-calls-by-request projection)))
                (t nil))))
    (cond
     (call
      (unless call-id
        (remhash name (yeah-ui--projection-legacy-calls projection)))
      (yeah-ui--finish-call call record))
     (call-id
      (yeah-ui--finish-call
       (yeah-ui--start-call projection record index nil t) record))
     (request-id
      (yeah-ui--generic projection record index 'unmatched-tool-end))
     (t
      (let ((candidates (gethash name (yeah-ui--projection-legacy-calls projection))))
        (cond
         ((= (length candidates) 1)
          (remhash name (yeah-ui--projection-legacy-calls projection))
          (yeah-ui--finish-call (car candidates) record))
         ((> (length candidates) 1)
          (yeah-ui--mark-ambiguous-calls projection name record index))
         (t
          (yeah-ui--generic projection record index 'unmatched-tool-end))))))))

(defun yeah-ui--approval-key (record)
  "Return the legacy correlation key of an approval RECORD."
  (list (plist-get record :action) (plist-get record :resource)))

(defun yeah-ui--forget-approval (projection approval)
  "Remove APPROVAL from the pending correlation indexes of PROJECTION."
  (let ((tool-id (plist-get approval :tool-call-id))
        (request-id (plist-get approval :request-id))
        (key (plist-get approval :legacy-key)))
    (when tool-id
      (puthash tool-id
               (delq approval
                     (gethash tool-id (yeah-ui--projection-approvals-by-tool projection)))
               (yeah-ui--projection-approvals-by-tool projection)))
    (when request-id
      (remhash request-id (yeah-ui--projection-approvals-by-request projection)))
    (puthash key
             (delq approval
                   (gethash key (yeah-ui--projection-legacy-approvals projection)))
             (yeah-ui--projection-legacy-approvals projection))))

(defun yeah-ui--request-approval (projection record index)
  "Project one permission-request RECORD at INDEX."
  (let* ((tool-id (yeah-ui--value record :tool_call_id :tool-call-id))
         (id (yeah-ui--event-block-id record index))
         (key (yeah-ui--approval-key record))
         (approval
          (yeah-ui--block
           record index :approval id
           :action (plist-get record :action)
           :resource (plist-get record :resource)
           :arguments (yeah-ui--normalize-args record)
           :state 'pending
           :effect nil
           :request-id (plist-get record :id)
           :decision-id nil
           :defer-event-id nil
           :deferred-request-id nil
           :tool-call-id tool-id
           :legacy-key key
           :correlation (if tool-id 'by-id 'legacy))))
    (yeah-ui--add-block projection approval)
    (push approval (yeah-ui--projection-approvals projection))
    (when tool-id
      (push approval
            (gethash tool-id (yeah-ui--projection-approvals-by-tool projection)))
      (when-let ((call (gethash tool-id (yeah-ui--projection-calls-by-id projection))))
        (when (eq (plist-get call :state) 'running)
          (setf (plist-get call :state) 'awaiting-approval))))
    (unless tool-id
      (let ((calls (gethash (plist-get record :action)
                            (yeah-ui--projection-legacy-calls projection))))
        (when (and (= (length calls) 1)
                   (eq (plist-get (car calls) :state) 'running))
          (setf (plist-get (car calls) :state) 'awaiting-approval))))
    (when (plist-get record :id)
      (puthash (plist-get record :id) approval
               (yeah-ui--projection-approvals-by-request projection)))
    (push approval
          (gethash key (yeah-ui--projection-legacy-approvals projection)))
    (setf (yeah-ui--projection-state projection) 'awaiting-approval)
    approval))

(defun yeah-ui--decision-candidates (projection record)
  "Return uniquely indexed pending approval candidates for RECORD."
  (let* ((tool-id (yeah-ui--value record :tool_call_id :tool-call-id))
         (parent-id (yeah-ui--value record :parent_event_id :parent-event-id))
         (request-id (yeah-ui--value record :request_event_id :request-event-id))
         (by-tool (and tool-id
                       (gethash tool-id (yeah-ui--projection-approvals-by-tool projection))))
         (by-request
          (or (and request-id
                   (when-let ((approval
                               (gethash request-id
                                        (yeah-ui--projection-approvals-by-request projection))))
                     (list approval)))
              (and parent-id
                   (when-let ((approval
                               (gethash parent-id
                                        (yeah-ui--projection-approvals-by-request projection))))
                     (list approval))))))
    (or by-tool by-request
        (gethash (yeah-ui--approval-key record)
                 (yeah-ui--projection-legacy-approvals projection)))))

(defun yeah-ui--decide-approval (projection record index)
  "Project one permission-decision RECORD at INDEX.
A defer marker keeps the approval pending; only a final allow or deny resolves
it.  The deferred wire request id is metadata, not a second tool correlation
key."
  (let ((candidates (yeah-ui--decision-candidates projection record))
        (effect (plist-get record :effect))
        (deferred (let ((value (plist-get record :effect)))
                    (or (memq value '(defer :defer)) (equal value "defer")))))
    (cond
     ((= (length candidates) 1)
      (let* ((approval (car candidates))
             (allowed (yeah-ui--allowed-p effect))
             (tool-id (plist-get approval :tool-call-id))
             (call (or (and tool-id
                            (gethash tool-id
                                     (yeah-ui--projection-calls-by-id projection)))
                       (let ((calls (gethash (plist-get record :action)
                                             (yeah-ui--projection-legacy-calls projection))))
                         (and (= (length calls) 1) (car calls))))))
        (if deferred
            (progn
              (setf (plist-get approval :state) 'deferred
                    (plist-get approval :effect) effect
                    (plist-get approval :defer-event-id) (plist-get record :id)
                    (plist-get approval :deferred-request-id)
                    (yeah-ui--value record :deferred_request_id
                                    :deferred-request-id :request_id :defer)
                    (plist-get approval :event-id) (plist-get record :id))
              (when (and call (eq (plist-get call :state) 'running))
                (setf (plist-get call :state) 'awaiting-approval))
              (setf (yeah-ui--projection-state projection) 'awaiting-approval))
          (yeah-ui--forget-approval projection approval)
          (setf (plist-get approval :state) (if allowed 'approved 'refused)
                (plist-get approval :effect) effect
                (plist-get approval :decision-id) (plist-get record :id)
                (plist-get approval :event-id) (plist-get record :id))
          (when call
            (cond
             ((not allowed)
              (setf (plist-get call :state) 'refused
                    (plist-get call :ok) nil))
             ((eq (plist-get call :state) 'awaiting-approval)
              (setf (plist-get call :state) 'running))))
          (setf (yeah-ui--projection-state projection) 'running))))
     ((> (length candidates) 1)
      (dolist (approval candidates)
        (yeah-ui--forget-approval projection approval)
        (setf (plist-get approval :state) 'unknown
              (plist-get approval :correlation) 'ambiguous)
        (when-let ((call (and (plist-get approval :tool-call-id)
                              (gethash (plist-get approval :tool-call-id)
                                       (yeah-ui--projection-calls-by-id projection)))))
          (setf (plist-get call :state) 'unknown
                (plist-get call :correlation) 'ambiguous)))
      (let ((calls (gethash (plist-get record :action)
                            (yeah-ui--projection-legacy-calls projection))))
        (dolist (call calls)
          (setf (plist-get call :state) 'unknown
                (plist-get call :correlation) 'ambiguous))
        (when calls
          (remhash (plist-get record :action)
                   (yeah-ui--projection-legacy-calls projection))))
      (setf (yeah-ui--projection-state projection) 'unknown)
      (yeah-ui--generic projection record index 'ambiguous-permission-correlation))
     (t
      (yeah-ui--generic projection record index 'unmatched-permission-decision)))))

(defun yeah-ui--spawn (projection record index)
  "Project one spawn RECORD at INDEX."
  (let* ((child (plist-get record :child))
         (spawn-id (plist-get record :id))
         (spawn (yeah-ui--block
                 record index :spawn (yeah-ui--event-block-id record index)
                 :child child
                 :role (plist-get record :role)
                 :depth (plist-get record :depth)
                 :state 'running
                 :spawn-id spawn-id
                 :child-end-id nil
                 :summary nil
                 :lineage-id child
                 :correlation 'by-child-id)))
    (yeah-ui--add-block projection spawn)
    (push spawn (gethash child (yeah-ui--projection-children projection)))
    (yeah-ui--close-activity projection)
    (setf (yeah-ui--projection-state projection) 'running)
    spawn))

(defun yeah-ui--child-end (projection record index)
  "Project one child-end RECORD at INDEX and link its unique spawn."
  (let* ((child (plist-get record :child))
         (candidates (gethash child (yeah-ui--projection-children projection)))
         (ok (yeah-ui--true-p (plist-get record :ok)))
         (spawn (and (= (length candidates) 1) (car candidates)))
         (block
          (yeah-ui--block
           record index :child-end (yeah-ui--event-block-id record index)
           :child child
           :role (plist-get record :role)
           :ok (and ok t)
           :summary (plist-get record :summary)
           :state (if spawn (if ok 'done 'failed) 'unknown)
           :spawn-id (and spawn (plist-get spawn :spawn-id))
           :lineage-id child
           :correlation (cond (spawn 'by-child-id)
                              (candidates 'ambiguous)
                              (t 'unmatched)))))
    (cond
     (spawn
      (remhash child (yeah-ui--projection-children projection))
      (setf (plist-get spawn :state) (if ok 'done 'failed)
            (plist-get spawn :child-end-id) (plist-get record :id)
            (plist-get spawn :summary) (plist-get record :summary))
      (unless (plist-get block :parent-event-id)
        (setf (plist-get block :parent-event-id) (plist-get spawn :spawn-id))))
     (candidates
      (dolist (candidate candidates)
        (setf (plist-get candidate :state) 'unknown
              (plist-get candidate :correlation) 'ambiguous))
      (remhash child (yeah-ui--projection-children projection))))
    (yeah-ui--add-block projection block)
    (yeah-ui--close-activity projection)
    block))

(defun yeah-ui--input (record)
  "Return the pending input represented by RECORD."
  (let ((nested (plist-get record :input)))
    (if (and (plist-member record :input) (listp nested))
        (copy-tree nested)
      (list :id (yeah-ui--value record :input_id :input-id)
            :kind (yeah-ui--value record :input_kind :input-kind :kind)
            :prompt (yeah-ui--value record :prompt :payload)
            :frozen (plist-get record :frozen)
            :created-at (or (yeah-ui--value record :created_at :created-at)
                            (plist-get record :timestamp))))))

(defun yeah-ui--queue-input (projection record)
  "Add the pending input of RECORD to PROJECTION."
  (let* ((input (yeah-ui--input record))
         (id (plist-get input :id)))
    (when (and id (not (gethash id (yeah-ui--projection-inputs-by-id projection))))
      (puthash id input (yeah-ui--projection-inputs-by-id projection))
      (push input (yeah-ui--projection-inputs projection)))))

(defun yeah-ui--dequeue-input (projection record)
  "Remove the explicitly identified pending input of RECORD from PROJECTION."
  (when-let ((id (yeah-ui--value record :input_id :input-id)))
    (remhash id (yeah-ui--projection-inputs-by-id projection))))

(defun yeah-ui--message (projection record index kind role)
  "Add a message block of KIND and ROLE for RECORD at INDEX."
  (let ((text (plist-get record :payload)))
    (yeah-ui--add-block
     projection
     (yeah-ui--block record index kind (yeah-ui--event-block-id record index)
                     :role role
                     :text text))
    (when (and (eq kind :user)
               (not (plist-get (yeah-ui--projection-session projection) :title)))
      (setf (plist-get (yeah-ui--projection-session projection) :title) text))
    (yeah-ui--close-activity projection)
    (setf (yeah-ui--projection-state projection)
          (if (eq kind :assistant) 'completed 'running))
    (when (eq kind :user)
      (setf (yeah-ui--projection-error projection) nil))))

(defun yeah-ui--simple-event (projection record index kind fields state)
  "Add a block of KIND with FIELDS for RECORD at INDEX and set STATE."
  (yeah-ui--add-block
   projection
   (apply #'yeah-ui--block record index kind
          (yeah-ui--event-block-id record index) fields))
  (yeah-ui--close-activity projection)
  (when state
    (setf (yeah-ui--projection-state projection) state)))

(defun yeah-ui--header (projection record)
  "Apply session metadata from the header RECORD to PROJECTION."
  (let ((session (yeah-ui--projection-session projection)))
    (dolist (entry '((:id :session_id :session-id)
                     (:title :title)
                     (:project :project :project_root :project-root)
                     (:placement :placement)
                     (:profile :profile)
                     (:model :model)))
      (when-let ((value (apply #'yeah-ui--value record (cdr entry))))
        (setf (plist-get session (car entry)) value)))
    (when (plist-member record :capabilities)
      (setf (yeah-ui--projection-capabilities projection)
            (plist-get record :capabilities)))))

(defun yeah-ui--handle (projection record index)
  "Fold one RECORD at INDEX into PROJECTION."
  (let ((type (plist-get record :type)))
    (unless (equal type "usage")
      (setf (yeah-ui--projection-estimated projection)
            (+ (yeah-ui--projection-estimated projection)
               (max 1 (ceiling (/ (length (format "%S" record)) 4.0))))))
    (unless (plist-get (yeah-ui--projection-session projection) :id)
      (when-let ((id (yeah-ui--value record :session_id :session-id)))
        (setf (plist-get (yeah-ui--projection-session projection) :id) id)))
    (pcase type
      ("header" (yeah-ui--header projection record))
      ("user-message" (yeah-ui--message projection record index :user "user"))
      ("assistant-message"
       (yeah-ui--message projection record index :assistant "assistant"))
      ("reasoning"
       (yeah-ui--simple-event projection record index :reasoning
                              (list :text (or (plist-get record :payload)
                                              (plist-get record :text)))
                              'running))
      ("activity"
       (yeah-ui--start-activity
        projection record index
        (or (yeah-ui--value record :activity_id :activity-id)
            (yeah-ui--event-block-id record index)))
       (setf (yeah-ui--projection-state projection) 'running))
      ("tool-request" (yeah-ui--start-call projection record index t
                                           (and (yeah-ui--value record :tool_call_id
                                                                     :tool-call-id)
                                                t)))
      ("tool-end" (yeah-ui--end-call projection record index)
       (setf (yeah-ui--projection-state projection) 'running))
      ("permission-request" (yeah-ui--request-approval projection record index))
      ("permission-decision" (yeah-ui--decide-approval projection record index))
      ("compaction"
       (yeah-ui--simple-event
        projection record index :compaction
        (list :cut-point (yeah-ui--value record :cut_point :cut-point)
              :summary (plist-get record :summary)
              :text (plist-get record :summary))
        'running))
      ("pruning"
       (yeah-ui--simple-event projection record index :pruning
                              (list :keep-chars (plist-get record :keep-chars))
                              'running))
      ("steering"
       (yeah-ui--simple-event projection record index :steering
                              (list :text (plist-get record :payload)
                                    :payload (plist-get record :payload))
                              'running))
      ("nudge"
       (yeah-ui--simple-event projection record index :nudge
                              (list :text (plist-get record :payload)
                                    :payload (plist-get record :payload))
                              'running))
      ("cancel"
       (yeah-ui--simple-event projection record index :cancel
                              (list :text (plist-get record :payload)
                                    :payload (plist-get record :payload))
                              'cancelled))
      ("finish"
       (yeah-ui--simple-event projection record index :finish
                              (list :summary (plist-get record :summary)
                                    :text (plist-get record :summary))
                              'completed))
      ("error"
       (let ((reason (plist-get record :payload)))
         (yeah-ui--simple-event projection record index :error
                                (list :error reason :text reason)
                                'failed)
         (setf (yeah-ui--projection-error projection) reason)))
      ("spawn" (yeah-ui--spawn projection record index))
      ("child-end" (yeah-ui--child-end projection record index))
      ("input-queued"
       (yeah-ui--queue-input projection record)
       (yeah-ui--generic projection record index)
       (yeah-ui--close-activity projection))
      ((or "input-taken" "input-recovered")
       (yeah-ui--dequeue-input projection record)
       (yeah-ui--generic projection record index)
       (yeah-ui--close-activity projection))
      ("input-withdrawn"
       (yeah-ui--dequeue-input projection record)
       (yeah-ui--simple-event
        projection record index :input-withdrawn
        (list :input-id (yeah-ui--value record :input_id :input-id)
              :input-kind (plist-get record :kind)
              :reason (plist-get record :reason))
        nil))
      ("usage"
       (let ((input (plist-get record :input))
             (output (plist-get record :output)))
         (when (numberp input)
           (setf (yeah-ui--projection-usage-input projection)
                 (+ (or (yeah-ui--projection-usage-input projection) 0) input)
                 (yeah-ui--projection-usage-reported-p projection) t))
         (when (numberp output)
           (setf (yeah-ui--projection-usage-output projection)
                 (+ (or (yeah-ui--projection-usage-output projection) 0) output)
                 (yeah-ui--projection-usage-reported-p projection) t))))
      (_
       (yeah-ui--generic projection record index)
       (yeah-ui--close-activity projection)))))

(defun yeah-ui-view (records)
  "Return a pure, deterministic view of journal RECORDS.

The new view has this shape:

  (:session (:id ID :title TITLE :project ROOT :placement PLACEMENT
            :profile PROFILE :model MODEL)
   :status (:state STATE :active-tool-count N :error ERROR)
   :blocks (BLOCK ...)
   :pending-approvals (APPROVAL ...)
   :pending-inputs (INPUT ...)
   :usage (:input N-OR-NIL :output N-OR-NIL
           :reported-p BOOL :estimated N)
   :capabilities CAPS)

Every block has :kind, stable :id, :event-id, :timestamp, :run-id, :turn-id
and :parent-event-id.  Message blocks also have :role and :text.  Tool blocks
are children of :activity blocks and have :id (the tool_call_id when present),
:tool/:name, normalized :args, :state, :ok, :result, :artifacts, :truncated,
:metadata, :request-id and :tool-call-id.  Their states are running,
awaiting-approval, done, failed, refused or unknown.  Approval blocks carry
:action, :resource, :arguments, :request-id, :decision-id, :effect and :state;
their states are pending, deferred, approved, refused or unknown.  A deferred
approval also has :defer-event-id and the wire's :deferred-request-id, and stays
in :pending-approvals until a final decision.  Compaction,
pruning, steering, nudge, cancel, finish, error, spawn, child-end and
input-withdrawn have their own kinds.  Unknown or uncorrelatable records become
explicit :event blocks carrying the original :record and, when applicable,
:fallback-reason.

Stable tool_call_id correlation is used whenever available.  Without metadata,
only a unique tool name or action/resource candidate is matched.  Multiple
candidates are all marked unknown and the terminal record remains visible as
an :event; no result is assigned by guessing.  Spawn and child-end blocks are
linked by :spawn-id/:child-end-id and :lineage-id.

Provider usage is accumulated independently for input and output.  A missing
side stays nil; :reported-p is nil when no numeric provider value exists.
:estimated is a separate record-text heuristic, never a substitute for reported
usage and never a dollar cost.

For compatibility, :transcript contains the same user/assistant block objects,
:calls the same tool block objects and :pending the same pending approval
objects as the new fields.  These aliases do not introduce another truth."
  (let ((projection
         (yeah-ui--make-projection
          :session (list :id nil :title nil :project nil :placement nil
                         :profile nil :model nil))))
    (cl-loop for record in records
             for index from 0
             do (yeah-ui--handle projection record index))
    (let* ((blocks (nreverse (yeah-ui--projection-blocks projection)))
           (calls (nreverse (yeah-ui--projection-calls projection)))
           (approvals (nreverse (yeah-ui--projection-approvals projection)))
           (inputs (nreverse (yeah-ui--projection-inputs projection)))
           (pending-approvals
            (cl-remove-if-not (lambda (approval)
                                (memq (plist-get approval :state)
                                      '(pending deferred)))
                              approvals))
           (pending-inputs
            (cl-remove-if-not
             (lambda (input)
               (gethash (plist-get input :id)
                        (yeah-ui--projection-inputs-by-id projection)))
             inputs))
           (active-count
            (cl-count-if (lambda (call)
                           (eq (plist-get call :state) 'running))
                         calls))
           (state (yeah-ui--projection-state projection))
           (status-state
            (cond ((memq state '(completed cancelled failed)) state)
                  (pending-approvals 'awaiting-approval)
                  ((> active-count 0) 'running)
                  (t state)))
           (usage (list :input (yeah-ui--projection-usage-input projection)
                        :output (yeah-ui--projection-usage-output projection)
                        :reported-p (and (yeah-ui--projection-usage-reported-p
                                          projection)
                                         t)
                        :estimated (yeah-ui--projection-estimated projection))))
      (dolist (block blocks)
        (when (eq (plist-get block :kind) :activity)
          (let ((children
                 (nreverse
                  (gethash block (yeah-ui--projection-activity-children projection)))))
            (setf (plist-get block :children) children
                  (plist-get block :state)
                  (cond
                   ((cl-some (lambda (call)
                               (memq (plist-get call :state)
                                     '(running awaiting-approval)))
                             children)
                    'running)
                   ((cl-some (lambda (call)
                               (eq (plist-get call :state) 'unknown))
                             children)
                    'unknown)
                   (t 'done))))))
      (list :session (yeah-ui--projection-session projection)
            :status (list :state status-state
                          :active-tool-count active-count
                          :error (yeah-ui--projection-error projection))
            :blocks blocks
            :pending-approvals pending-approvals
            :pending-inputs pending-inputs
            :usage usage
            :capabilities (yeah-ui--projection-capabilities projection)
            :transcript (cl-remove-if-not
                         (lambda (block)
                           (memq (plist-get block :kind) '(:user :assistant)))
                         blocks)
            :calls calls
            :pending pending-approvals))))

(provide 'yeah-ui)
;;; yeah-ui.el ends here
