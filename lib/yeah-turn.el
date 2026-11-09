;;; yeah-turn.el --- one turn of the model -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; One turn of the agent loop: ask the model, take the tool calls it asked
;; for, decide whether each of them may run, run it through the registry,
;; write what happened into the append-only log, and hand the result back
;; so that the model can answer again.
;;
;; The turn does not know how the model is reached. It is handed a
;; TRANSPORT: a function of (PROMPT CALLBACK) that calls CALLBACK with the
;; model's answer. The shape of the answer is the one gptel uses, because
;; gptel is the transport:
;;
;;   a string
;;       the model has answered with text;
;;
;;   (tool-call . ((TOOL ARGS CB) ...))
;;       the model has asked for tools; CB continues the conversation once
;;       the result of the call is known.
;;
;; The transport in `lib/yeah-gptel.el' is the one that speaks gptel; the
;; transport in the checks is a fake. Nothing else in the kernel knows
;; that gptel exists.
;;
;; What the turn owns is the part that must not be given away: the
;; permission system decides whether a call may run, the registry decides
;; whether its arguments are well formed, and the log remembers what
;; happened. The model proposes; it does not decide.

;;; Code:

(require 'cl-lib)
(require 'yeah-state)
(require 'yeah-loop)
(require 'yeah-tools)
(require 'yeah-perm)
(require 'yeah-session)

;; A tool of the model is a gptel-tool struct when gptel is loaded, and a
;; plist with a :name key otherwise; the checks use the latter.
(declare-function gptel-tool-p "gptel" (object))
(declare-function gptel-tool-name "gptel" (tool))

(defconst yeah-turn--max-calls 32
  "The most tool calls one turn may dispatch before it stops and says so.
A model that asks for the same thing for ever must not spend somebody
else's money for ever.")

(cl-defstruct (yeah-turn (:constructor yeah-turn--make))
  "One run of the agent loop.

SESSION is the session the run writes into. STATE is the state of the
machine. STATES is the list of states the run has been in, in order.
CALLS is the number of tool calls dispatched. TURNS is the number of
times the model was asked. DONE says whether the model has finished.
ERROR holds the reason when the run stopped for a reason of its own."
  (session nil)
  (state 'idle)
  (states nil)
  (calls 0)
  (turns 0)
  (done nil)
  (error nil))

(defun yeah-turn--tool-name (tool)
  "Return the name of the gptel-shaped TOOL.
TOOL is a gptel-tool struct when gptel is loaded, and a plist with a
`:name' key otherwise; the checks use the latter."
  (cond ((and (fboundp 'gptel-tool-name) (gptel-tool-p tool))
         (gptel-tool-name tool))
        ((plist-get tool :name) (plist-get tool :name))
        (t (signal 'user-error
                   (list (format "yeah-turn: cannot read the name of a tool: %S"
                                 tool))))))

(defun yeah-turn--tick (turn label)
  "Move TURN on LABEL and record the state it moved to.
Return the new state. A transition that the machine does not have is a
bug in the turn, and the run stops with that reason."
  (let ((from (yeah-turn-state turn)))
    (condition-case err
        (let ((to (yeah-loop-tick from label)))
          (setf (yeah-turn-state turn) to)
          (setf (yeah-turn-states turn)
                (append (yeah-turn-states turn) (list to)))
          to)
      (user-error
       (yeah-turn--fail turn (error-message-string err))
       (yeah-turn-state turn)))))

(defun yeah-turn--fail (turn reason)
  "Stop TURN because of REASON, and say why in the log."
  (when (eq (yeah-turn-state turn) 'deciding)
    (yeah-turn--tick turn 'error))
  (setf (yeah-turn-error turn) reason
        (yeah-turn-done turn) t)
  (when (yeah-turn-session turn)
    (yeah-session-append (yeah-turn-session turn)
                          (list :type "error" :payload reason)))
  reason)

(defun yeah-turn--resource (args)
  "Return the resource the tool acts on: its first argument when that
argument names a thing, and the printed arguments otherwise. The rules
of the permission system match this, so `read' on a file is matched by
the path and not by a printed list of arguments."
  (or (and (stringp (car args)) (car args))
      (format "%S" args)))

(defun yeah-turn--dispatch (turn call)
  "Run one tool CALL on behalf of TURN.
Return the outcome plist: `(:name NAME :ok BOOL :result VALUE)' or
`(:name NAME :ok nil :error REASON)'."
  (let* ((name (yeah-turn--tool-name (nth 0 call)))
         (args (nth 1 call))
         (outcome
          (condition-case err
              (let ((decision (yeah-perm-evaluate name (yeah-turn--resource args))))
                (if (eq decision :allow)
                    (list :name name :ok t
                          :result (yeah-tools-call name args))
                  (list :name name :ok nil
                        :error (format "the rules say %s" decision))))
            (user-error
             (list :name name :ok nil :error (error-message-string err))))))
    (cl-incf (yeah-turn-calls turn))
    (yeah-session-append
     (yeah-turn-session turn)
     (list :type "tool-result"
           :tool name
           :ok (plist-get outcome :ok)
           :payload (let ((value (if (plist-get outcome :ok)
                                    (plist-get outcome :result)
                                  (plist-get outcome :error))))
                      (if (stringp value) value (format "%S" value)))))
    outcome))

(defun yeah-turn--answer (turn answer)
  "Handle the model's ANSWER in TURN."
  (unless (yeah-turn-done turn)
    (cond
     ((stringp answer)
      ;; The model has answered with text and asks for nothing.
      (yeah-turn--tick turn 'stream-end)
      (yeah-turn--tick turn 'no-tool-calls)
      (setf (yeah-turn-done turn) t)
      (yeah-session-append (yeah-turn-session turn)
                            (list :type "assistant" :payload answer)))
     ((and (consp answer) (eq (car answer) 'tool-call))
      (yeah-turn--tick turn 'stream-end)
      (let (continues)
        (dolist (call (cdr answer))
          (unless (yeah-turn-done turn)
            (yeah-turn--tick turn 'tool-call)
            (let* ((outcome (yeah-turn--dispatch turn call))
                   (continue (nth 2 call)))
              (when continue
                (push (cons continue (if (plist-get outcome :ok)
                                         (plist-get outcome :result)
                                       (plist-get outcome :error)))
                      continues)))
            (yeah-turn--tick turn 'tool-end)
            (yeah-turn--tick turn 'budget-ok)))
        ;; Everything that was asked for has been dispatched; the model is
        ;; asked again with the results. The continuation is called after
        ;; the machine has recorded the batch, because it may answer at
        ;; once and the answer must arrive in a state that can receive it.
        (unless (yeah-turn-done turn)
          (yeah-turn--tick turn 'continue))
        (dolist (pair (nreverse continues))
          (funcall (car pair) (cdr pair)))))
     (t
      (yeah-turn--fail turn (format "the model answered with %S" answer))))))

(defun yeah-turn--ask (turn prompt transport)
  "Ask the model PROMPT with TRANSPORT, and continue TURN when it answers."
  (unless (yeah-turn-done turn)
    (when (eq (yeah-turn-state turn) 'idle)
      (yeah-turn--tick turn 'user-prompt))
    (cl-incf (yeah-turn-turns turn))
    (yeah-session-append (yeah-turn-session turn)
                          (list :type "user" :payload prompt))
    (funcall transport prompt
              (lambda (answer &optional _info)
                (yeah-turn--answer turn answer)))))

;;;###autoload
(defun yeah-turn-run (session prompt &optional transport)
  "Run the agent loop over SESSION with PROMPT and return the run.

TRANSPORT is a function of (PROMPT CALLBACK) that calls CALLBACK with
the model's answer; it defaults to `yeah-gptel-request', the one place
where Yeah calls the model. The returned run is a `yeah-turn' record:
it carries the session as it stands, the state of the machine, the
states it has been in, and the reason if the run stopped for a reason
of its own.

The transport may answer now or later: with gptel the answer arrives
when the model has finished, so the record is filled in over time and
the caller watches it."
  (let ((transport (or transport
                      (and (fboundp 'yeah-gptel-request) #'yeah-gptel-request))))
    (unless transport
      (signal 'user-error
              (list "yeah-turn-run: no transport: gptel is not loaded and no \
transport was given")))
    (let ((turn (yeah-turn--make :session session)))
      (yeah-turn--ask turn prompt transport)
      turn)))

(provide 'yeah-turn)
;;; yeah-turn.el ends here
