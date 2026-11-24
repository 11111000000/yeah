;;; live-child-on-the-model-of-its-preset.el --- a child of a live provider on the model of its preset -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; This check is the part of the delegation that only a real model can do: the
;; parent runs on one model, the preset of the child names another, and the
;; check reads the journal of the parent and the journal of the child
;; afterwards.
;;
;; What it measures:
;;
;; 1. the journal of the parent holds the spawn of a child, and every spawn
;;    names the model of the preset -- the model the child runs on, and not the
;;    model of the parent;
;; 2. the short ids of the children differ -- two children are two children;
;; 3. the journal of the child holds the record of where the child stands in
;;    the tree of the delegations, and that record names the same model;
;; 4. the child ends on its own, through the tool `finish' -- the child of a
;;    live provider really works.
;;
;; The child of the preset has ONE tool: `finish'.  A model that is asked to
;; finish and may also search is a model that searches, and the run of the
;; child is then a run that never ends -- the first attempt of this check
;; measured exactly that (fourteen calls of tools and no end).
;;
;; The model is real and the provider is real.  The configuration comes from
;; the environment, so that no key is ever written into this repository:
;;
;;   YEAH_TEST_KEY          the API key; without it the check skips
;;   YEAH_TEST_HOST         the API host, for example api.minimax.io
;;   YEAH_TEST_MODEL        the model of the parent, for example MiniMax-M2.7
;;   YEAH_TEST_CHILD_MODEL  the model of the preset of the child; it must be
;;                          another model than the model of the parent, or
;;                          there is nothing to measure
;;
;; This check lives OUTSIDE the map of the method: it needs a provider, and a
;; provider is not a proof that the kernel can be trusted.
;;
;; Exit codes: 0 — a child of a live provider ran on the model of its preset;
;; 1 — it did not; 2 — the model of the child is the model of the parent.

;;; Code:

(require 'gptel)
(require 'gptel-openai)
(require 'yeah-control)
(require 'yeah-delegate)
(require 'yeah-gptel)
(require 'yeah-perm)
(require 'yeah-session)
(require 'yeah-turn)

(defconst yeah-live-model--preset
  "---
name: reviewer
description: Reviews a short text and says what is wrong with it.
model: %s
tools: finish
depth: 1
budget: 2000
timeout: 300
---

You review a short text and say what is wrong with it.  You have one tool:
`finish'.  Call it once with your answer, and say nothing else.
"
  "The preset the child is delegated to.
The model is the one of the preset, and it is NOT the model of the parent:
that is what the check measures.  The child has the tool `finish`, or it
could never end: a run that cannot end is a run that works for ever.  The child
has no other tool: a model that is asked to finish and may also search is a
model that searches, and the run of the child is then a run that never ends.")

(defun yeah-live-model--directory (model)
  "Return a directory with the preset of the child, for MODEL."
  (let ((directory (make-temp-file "yeah-live-model" t)))
    (with-temp-buffer
      (insert (format yeah-live-model--preset model))
      (write-region (point-min) (point-max)
                    (expand-file-name "reviewer.md" directory)))
    directory))

(defun yeah-live-model--wait (turn &optional timeout)
  "Wait for TURN to end and return its state."
  (let ((deadline (+ (float-time) (or timeout 600))))
    (while (and (not (yeah-turn-done turn)) (< (float-time) deadline))
      (accept-process-output nil 0.2))
    (yeah-turn-state turn)))

(defun yeah-live-model--records (session type)
  "Return the records of TYPE in the journal of SESSION."
  (let ((found nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) type)
        (push record found)))
    (nreverse found)))

(defun yeah-live-model--all-records (session)
  "Return every record of the journal of SESSION."
  (yeah-session-records session))

(defun yeah-live-model--positions (types type)
  "Return the positions of TYPE in TYPES, in order."
  (let ((position 0)
        (found nil))
    (dolist (one types)
      (setq position (1+ position))
      (when (equal one type)
        (push position found)))
    (nreverse found)))

(defun yeah-live-model--run ()
  "Run the parent turn and return a failure message, or nil.
The parent asks for ONE delegation, the preset of the child names another
model than the model of the parent, and the check reads the journals of the
two runs."
  (let* ((key (getenv "YEAH_TEST_KEY"))
         (host (or (getenv "YEAH_TEST_HOST") "api.minimax.io"))
         (model (or (getenv "YEAH_TEST_MODEL") "MiniMax-M3.1-Flash"))
         (child-model (or (getenv "YEAH_TEST_CHILD_MODEL") "MiniMax-M2.7"))
         (directory nil)
         (failure nil))
    (unless key
      (message "live model: skipped — no YEAH_TEST_KEY in the environment")
      (kill-emacs 0))
    (when (equal model child-model)
      (message "live model: the model of the child is the model of the parent (%s): there is nothing to measure"
               model)
      (kill-emacs 2))
    (setq directory (yeah-live-model--directory child-model))
    (setq gptel-backend
          (gptel-make-openai "yeah-live-model"
            :host host
            :endpoint "/v1/chat/completions"
            :key key
            :models (list (intern model) (intern child-model))))
    (setq gptel-model (intern model))
    ;; The tools of a child run in the event loop, long after this function
    ;; returned: a let of a global variable is not in their dynamic
    ;; environment, so the directories of the presets and the budget of the
    ;; nudges of a child are set for the process of this check.
    (setq yeah-agent-directories (list directory)
          yeah-subagent-max-nudges 3)
    (yeah-delegate-register)
    (dolist (tool '("delegate" "delegate-result" "read" "grep"))
      (yeah-perm-rules-add (yeah-perm-rule-make tool "*" 'allow)))
    (let* ((session (yeah-session-open "live-model" directory))
           (control (yeah-control-new
                     session
                     (lambda (prompt callback)
                       (yeah-gptel-request
                        prompt callback
                        :system "You are an agent inside Emacs.  You have the tool delegate, which starts a child agent with its own model.  Ask for a delegation of the agent reviewer once, with one short text to review, and then finish the turn with the finish tool.  The child works while you work: do not wait for it, do not ask for its result, and do not call any other tool."
                        ))
                     nil nil 3))
           (turn nil))
      (yeah-control-ask
       control
       "Ask for one delegation of the agent reviewer, with the task: review the text \"the quick brown fox jumps over the lazy dog\".  Then call the finish tool immediately: do not wait for the child and do not ask for its result."
       nil)
      (setq turn (yeah-control-active-turn control))
      (unless turn
        (message "live model: the run did not start")
        (kill-emacs 1))
      (message "live model: state=%S" (yeah-live-model--wait turn))
      (dolist (event (yeah-session-records session))
        (message "live model: %s" event))
      ;; 1. the journal of the parent holds the spawn of a child, and every
      ;;    spawn names the model of the preset
      (let* ((spawns (yeah-live-model--records session "spawn"))
             (ids (mapcar (lambda (record) (plist-get record :short-id)) spawns))
             (models (mapcar (lambda (record) (plist-get record :model)) spawns)))
        (message "live model: the parent runs on the model %s, the preset names %s"
                 model child-model)
        (unless (>= (length spawns) 1)
          (setq failure (format "the journal of the parent holds %d spawn(s) of a child, not one: %S"
                                (length spawns) ids)))
        (unless (equal models (mapcar (lambda (_) child-model) spawns))
          (setq failure (format "the spawn(s) of the children name the models %S, and the preset names %s"
                                models child-model)))
        (unless (= (length ids) (length (delete-dups ids)))
          (setq failure (format "the children carry the short ids %S, and two of them carry the same one"
                                ids)))
        (message "live model: the parent spawned %d child(ren): %S"
                 (length spawns) ids))
      ;; 2. the journal of the child names the same model, and the child
      ;;    ends on its own
      (let ((deadline (+ (float-time) 300)))
        (while (and (not failure)
                    (< (length (yeah-live-model--records session "child-end")) 1)
                    (< (float-time) deadline))
          (accept-process-output nil 0.2))
        (message "live model: the parent holds %d end(s) of a child"
                 (length (yeah-live-model--records session "child-end")))
        (let* ((child (yeah-session-open "live-model.sub-1" directory))
               (starts (yeah-live-model--records child "child-start"))
               (model (and (= 1 (length starts)) (plist-get (car starts) :model))))
          (dolist (record (yeah-live-model--all-records child))
            (message "live model:   child: %s" record))
          (unless (equal model child-model)
            (setq failure (format "the journal of the child names the model %S, and the preset names %s"
                                  model child-model)))
          ;; the child ended through the `finish' tool and not by a timeout
          (unless (= 1 (length (yeah-live-model--records child "finish")))
            (setq failure (format "the child of a live provider did not end through the finish tool: %d record(s) of the end"
                                  (length (yeah-live-model--records child "finish")))))
          (unless (= 1 (length (yeah-live-model--records session "child-end")))
            (setq failure "the child of a live provider did not end on its own")))))
    failure))

(let ((failure (yeah-live-model--run)))
  (when failure
    (message "live model: %s" failure)
    (kill-emacs 1))
  (message "live model: a child of a live provider ran on the model of its preset")
  (kill-emacs 0))

;;; live-child-on-the-model-of-its-preset.el ends here
