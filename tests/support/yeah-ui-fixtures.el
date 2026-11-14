;;; yeah-ui-fixtures.el --- journal fixtures for the pure UI projection -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;; Fixtures owned by the view-model tests.  They do not depend on the event
;; writer or turn implementation.

;;; Code:

(defun yeah-ui-fixture-event (id type &rest fields)
  "Return a new-contract event of TYPE with numeric ID and FIELDS.
Every fixture record carries the complete envelope, including nil optional ids."
  (let ((record (list :schema_version 1
                      :session_id "fixture-session"
                      :id id
                      :timestamp (format "2026-01-01T00:00:%02d+0000" id)
                      :run_id "run-1"
                      :turn_id "turn-1"
                      :tool_call_id nil
                      :parent_event_id nil
                      :type type)))
    (while fields
      (setq record (plist-put record (car fields) (cadr fields)))
      (setq fields (cddr fields)))
    record))

(defun yeah-ui-fixture-header (&rest fields)
  "Return a new-contract header with optional metadata FIELDS."
  (apply #'yeah-ui-fixture-event 0 "header" fields))

(defun yeah-ui-fixture-parallel ()
  "Return two same-name calls whose ends arrive in reverse order."
  (list
   (yeah-ui-fixture-header :title "Parallel fixture"
                           :project "/tmp/project"
                           :placement "service"
                           :profile "build"
                           :model "fake-model"
                           :capabilities '(:ask :cancel))
   (yeah-ui-fixture-event 1 "user-message" :payload "run both")
   (yeah-ui-fixture-event 2 "tool-request"
                          :tool_call_id "call-a" :parent_event_id 1
                          :tool "probe" :args '("/tmp/a"))
   (yeah-ui-fixture-event 3 "permission-request"
                          :tool_call_id "call-a" :parent_event_id 2
                          :action "probe" :resource "/tmp/a"
                          :arguments '("/tmp/a"))
   (yeah-ui-fixture-event 4 "permission-decision"
                          :tool_call_id "call-a" :parent_event_id 3
                          :action "probe" :resource "/tmp/a" :effect "allow")
   (yeah-ui-fixture-event 5 "tool-request"
                          :tool_call_id "call-b" :parent_event_id 1
                          :tool "probe" :args '("/tmp/b"))
   (yeah-ui-fixture-event 6 "permission-request"
                          :tool_call_id "call-b" :parent_event_id 5
                          :action "probe" :resource "/tmp/b"
                          :arguments '("/tmp/b"))
   (yeah-ui-fixture-event 7 "permission-decision"
                          :tool_call_id "call-b" :parent_event_id 6
                          :action "probe" :resource "/tmp/b" :effect "allow")
   (yeah-ui-fixture-event 8 "tool-end"
                          :tool_call_id "call-b" :parent_event_id 5
                          :tool "probe" :ok t :payload "second result"
                          :artifacts '("/tmp/second.out")
                          :truncated t :metadata '(:exit-status 0))
   (yeah-ui-fixture-event 9 "tool-end"
                          :tool_call_id "call-a" :parent_event_id 2
                          :tool "probe" :ok t :payload "first result")
   (yeah-ui-fixture-event 10 "assistant-message" :payload "both finished")
   (yeah-ui-fixture-event 11 "usage" :input 12 :output 7)))

(defun yeah-ui-fixture-legacy ()
  "Return an old journal without envelope correlation metadata."
  (list
   (list :type "header" :id 0 :session_id "legacy-session"
         :timestamp "2025-01-01T00:00:00+0000")
   (list :type "user-message" :id 1 :payload "legacy question")
   (list :type "tool-request" :id 2 :tool "probe"
         :args "(\"/tmp/legacy\")")
   (list :type "permission-request" :id 3
         :action "probe" :resource "/tmp/legacy")
   (list :type "permission-decision" :id 4
         :action "probe" :resource "/tmp/legacy" :effect "allow")
   (list :type "tool-end" :id 5 :tool "probe" :ok t
         :payload "legacy result")
   (list :type "assistant-message" :id 6 :payload "legacy answer")))

(defun yeah-ui-fixture-legacy-ambiguous ()
  "Return an old same-name batch whose result cannot be paired safely."
  (list
   (list :type "header" :id 0 :session_id "legacy-ambiguous")
   (list :type "user-message" :id 1 :payload "run both")
   (list :type "tool-request" :id 2 :tool "probe" :args "(\"first\")")
   (list :type "tool-request" :id 3 :tool "probe" :args "(\"second\")")
   (list :type "tool-end" :id 4 :tool "probe" :ok t
         :payload "unassignable result")))

(defun yeah-ui-fixture-child ()
  "Return linked spawn/child-end records followed by finish."
  (list
   (yeah-ui-fixture-header)
   (yeah-ui-fixture-event 1 "user-message" :payload "delegate")
   (yeah-ui-fixture-event 2 "spawn" :parent_event_id 1
                          :child "fixture-session.child"
                          :role "researcher" :depth 1)
   (yeah-ui-fixture-event 3 "child-end" :parent_event_id 2
                          :child "fixture-session.child"
                          :role "researcher" :ok t
                          :summary "child summary")
   (yeah-ui-fixture-event 4 "finish" :summary "finished")))

(defun yeah-ui-fixture-pending ()
  "Return one pending approval and one pending input after a withdrawal."
  (list
   (yeah-ui-fixture-header :capabilities '(:ask :steer :permissions :pending))
   (yeah-ui-fixture-event 1 "user-message" :payload "start")
   (yeah-ui-fixture-event 2 "input-queued"
                          :input_id "input-b" :input_kind "ask"
                          :prompt "second" :frozen '(:budget 10))
   (yeah-ui-fixture-event 3 "input-queued"
                          :input_id "input-a" :input_kind "steering"
                          :prompt "clarify" :frozen '(:budget 10))
   (yeah-ui-fixture-event 4 "input-withdrawn"
                          :input_id "input-b" :kind "ask"
                          :reason "withdrawn by test")
   (yeah-ui-fixture-event 5 "tool-request"
                          :tool_call_id "call-pending"
                          :tool "probe" :args '("target"))
   (yeah-ui-fixture-event 6 "permission-request"
                          :tool_call_id "call-pending" :parent_event_id 5
                          :action "probe" :resource "target"
                          :arguments '("target"))))

(defun yeah-ui-fixture-deferred ()
  "Return a stable-id permission sequence through its deferred marker."
  (list
   (yeah-ui-fixture-header)
   (yeah-ui-fixture-event 1 "user-message" :payload "ask the person")
   (yeah-ui-fixture-event 2 "tool-request"
                          :tool_call_id "call-deferred"
                          :tool "probe" :args '("target"))
   (yeah-ui-fixture-event 3 "permission-request"
                          :tool_call_id "call-deferred" :parent_event_id 2
                          :action "probe" :resource "target"
                          :arguments '("target"))
   (yeah-ui-fixture-event 4 "permission-decision"
                          :tool_call_id "call-deferred" :parent_event_id 3
                          :action "probe" :resource "target"
                          :effect "defer" :request_id "permission-7")))

(defun yeah-ui-fixture-without-usage ()
  "Return a complete conversation with no provider usage record."
  (list
   (yeah-ui-fixture-header)
   (yeah-ui-fixture-event 1 "user-message" :payload "question")
   (yeah-ui-fixture-event 2 "assistant-message" :payload "answer")))

(defun yeah-ui-fixture-block-kinds ()
  "Return records exercising every explicit block kind and generic fallback."
  (list
   (yeah-ui-fixture-header)
   (yeah-ui-fixture-event 1 "user-message" :payload "question")
   (yeah-ui-fixture-event 2 "assistant-message" :payload "answer")
   (yeah-ui-fixture-event 3 "reasoning" :payload "thinking")
   (yeah-ui-fixture-event 4 "tool-request"
                          :tool_call_id "call-x" :tool "probe" :args '("x"))
   (yeah-ui-fixture-event 5 "permission-request"
                          :tool_call_id "call-x" :parent_event_id 4
                          :action "probe" :resource "x")
   (yeah-ui-fixture-event 6 "permission-decision"
                          :tool_call_id "call-x" :parent_event_id 5
                          :action "probe" :resource "x" :effect "allow")
   (yeah-ui-fixture-event 7 "tool-end"
                          :tool_call_id "call-x" :parent_event_id 4
                          :tool "probe" :ok t :payload "x done")
   (yeah-ui-fixture-event 8 "compaction" :cut_point 2 :summary "summary")
   (yeah-ui-fixture-event 9 "pruning" :keep-chars 100)
   (yeah-ui-fixture-event 10 "steering" :payload "steer")
   (yeah-ui-fixture-event 11 "nudge" :payload "nudge")
   (yeah-ui-fixture-event 12 "spawn" :child "child-x" :role "worker" :depth 1)
   (yeah-ui-fixture-event 13 "child-end" :parent_event_id 12
                          :child "child-x" :role "worker" :ok :false
                          :summary "failed child")
   (yeah-ui-fixture-event 14 "input-withdrawn"
                          :input_id "queued-x" :kind "ask" :reason "not needed")
   (yeah-ui-fixture-event 15 "finish" :summary "done")
   (yeah-ui-fixture-event 16 "cancel" :payload "cancelled")
   (yeah-ui-fixture-event 17 "error" :payload "broken")
   (yeah-ui-fixture-event 18 "future-event" :payload "preserve me")))

(provide 'yeah-ui-fixtures)
;;; yeah-ui-fixtures.el ends here
