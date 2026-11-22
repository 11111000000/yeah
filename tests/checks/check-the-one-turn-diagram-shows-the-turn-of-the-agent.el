;;; check-the-one-turn-diagram-shows-the-turn-of-the-agent.el --- the one-turn diagram shows the turn of the agent -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The picture of one turn of the agent is written by hand, and it says
;; what the turn is: the model proposes a call of a tool, the registry
;; checks the call, the policy decides whether the call may run, the
;; person answers when the rules ask, the scheduler runs what may run,
;; the journal keeps what happened and the result goes back to the
;; model.
;;
;; A picture of the loop that dropped one of these steps shows a loop
;; that does not exist, and a picture that names a module that is not
;; there sends the reader to a file that is not there.  This check reads
;; `site/diagrams/one-turn.puml' and measures five things:
;;
;;   1. the file is there, it is not empty, and it is a diagram of
;;      PlantUML: the first line is `@startuml one-turn' and the last
;;      line is `@enduml';
;;   2. every reference of the form `file:line' names a file of this
;;      repository, a line of that file and a line that carries a
;;      definition -- a line that holds code and no definition names no
;;      definition;
;;   3. the picture names the six modules that hold the turn together:
;;      `lib/yeah-turn.el', `lib/yeah-tools.el', `lib/yeah-perm.el',
;;      `lib/yeah-approval.el', `lib/yeah-scheduler.el' and
;;      `lib/yeah-session.el'.  A step of the turn that is not in the
;;      picture is a step the reader does not see;
;;   4. one line of the picture names the five answers the person may
;;      give to a request for permission -- `:once', `:session',
;;      `:project', `:global' and `:reject'.  The person answers in the
;;      words of the kernel, and the picture that shows other words
;;      shows a dialogue that the kernel does not have;
;;   5. the seven steps of the turn are in the picture, and they stand in
;;      the order of the turn: every step is a *block* of the picture --
;;      a step that the reader of the picture does not see is not a step
;;      -- every step is named by its own words, the seven blocks are
;;      seven different blocks, and the block of the first step stands
;;      before the block of the second one, and so on.  A picture whose
;;      seven blocks say the same thing, or whose blocks stand in the
;;      wrong order, shows a turn that does not happen;
;;   6. the picture says the rest of the promise of the turn in its own
;;      words: a *block* of the picture says that the call may run, and
;;      a *line* of the picture says that the rules ask the person.  A
;;      line of the picture is a line of the drawing and not a line of
;;      the comment at the top of the file: the comment says the
;;      promise, and a picture that dropped the lines of the promise says
;;      nothing about it.
;;
;; The rule of the reference is the rule of every diagram of the site and
;; it lives in one place: `tests/support/yeah-diagram-files.el'.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the picture shows the turn of the agent; 1 -- it does
;; not, or it points at something that is not there; 2 -- the tree is not
;; where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--turn-modules
  '("lib/yeah-turn.el"
    "lib/yeah-tools.el"
    "lib/yeah-perm.el"
    "lib/yeah-approval.el"
    "lib/yeah-scheduler.el"
    "lib/yeah-session.el")
  "The modules the picture of the turn has to name.")

(defconst yeah-check--turn-steps
  '(("model" . ("model" "proposes" "call" "tool"))
    ("registry" . ("registry" "checks" "call"))
    ("policy" . ("policy" "decides"))
    ("person" . ("person" "answers"))
    ("scheduler" . ("scheduler" "runs"))
    ("journal" . ("journal" "keeps"))
    ("result" . ("result" "model")))
  "The seven steps of the turn, with the words that name each of them.
Every step is a pair: the name of the step and the words that the
block of that step has to say.  The name of a step is the name of the
thing the step is about, and it is one of the words of the step: a
block that names the scheduler and says nothing else does not name
the step of the scheduler.

The first step is a call of a tool and not a call of nothing: the block
of the model names the tool as well, and a picture that says `the model
proposes a call' shows a turn without a tool in it.

The steps stand in the order of the turn, and the order is the order
of this list.")

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/one-turn.puml" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/"
          yeah-check--blockers))
  (unless (file-directory-p (expand-file-name "site/diagrams" root))
    (push "the tree of the repository is not where we think: there is no site/diagrams/"
          yeah-check--blockers))
  (unless (file-readable-p reader)
    (push "the tree of the repository is not where we think: there is no tests/support/yeah-diagram-files.el"
          yeah-check--blockers))
  (unless (file-readable-p diagram)
    (push "the tree of the repository is not where we think: there is no site/diagrams/one-turn.puml"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (lines (yeah-diagram--drawing-lines text))
           (blocks (yeah-diagram--blocks text))
           (references (yeah-diagram--references text))
           (named (delete-dups (mapcar #'car references))))
      ;; 1. the file is a diagram of PlantUML and it is not empty.
      (when (string-empty-p (string-trim text))
        (push "site/diagrams/one-turn.puml is empty: there is no picture of the turn"
              yeah-check--failures))
      (unless (string= (string-trim (or (car lines) "")) "@startuml one-turn")
        (push (format "site/diagrams/one-turn.puml starts with %s, and the first line of a diagram is `@startuml one-turn'"
                      (format "%S" (string-trim (or (car lines) ""))))
              yeah-check--failures))
      (unless (string= (string-trim (or (car (last lines)) "")) "@enduml")
        (push (format "site/diagrams/one-turn.puml ends with %s, and the last line of a diagram is `@enduml'"
                      (format "%S" (string-trim (or (car (last lines)) ""))))
              yeah-check--failures))
      ;; 2. every reference points at a file, at a line and at code.
      (dolist (broken (yeah-diagram--broken-references root references))
        (push (format "the picture of the turn names %s:%d, and %s"
                      (nth 0 (car broken)) (nth 1 (car broken)) (nth 1 broken))
              yeah-check--failures))
      (when (null references)
        (push "the picture of the turn names no file at all: this check cannot tell a good name from a bad one"
              yeah-check--failures))
      ;; 3. the six modules that hold the turn together are named.
      (dolist (module yeah-check--turn-modules)
        (unless (member module named)
          (push (format "the picture of the turn does not name %s: the step it holds is not in the picture"
                        module)
                yeah-check--failures)))
      ;; 4. the answers of the person are the words of the kernel.
      (unless (yeah-diagram--answers-p lines)
        (push "the picture of the turn has no line that names the answers of the person: once, session, project, global and reject"
              yeah-check--failures))
      ;; 5. the seven steps of the turn are in the picture and in the order
      ;; of the turn.  Every step is a block of its own, and the block of
      ;; a step stands before the block of the step that follows it.
      (let ((previous -1)
            (previous-step nil))
        (dolist (step yeah-check--turn-steps)
          (let* ((name (car step))
                 (words (cdr step))
                 (places (yeah-diagram--block-places blocks words)))
            (cond
             ((null places)
              (push (format "the picture of the turn has no block that names the step of the %s: the words %s"
                            name (yeah-diagram--words-text words))
                    yeah-check--failures))
             (t
              (let ((place (cl-find-if (lambda (p) (> p previous)) places)))
                (if (null place)
                    (push (format "the picture of the turn does not stand the steps of the turn in the order of the turn: the step of the %s stands before the step of the %s"
                                  name previous-step)
                          yeah-check--failures)
                  (setq previous place)
                  (setq previous-step name))))))))
      ;; 6. the promise of the turn is in the picture, and it is in the
      ;;    picture and not in the comment at the top of the file.  A
      ;;    block says that the call may run, and a line says that the
      ;;    rules ask the person.
      (unless (cl-some (lambda (block)
                         (yeah-diagram--names-all-p block '("call" "may" "run")))
                       blocks)
        (push "the picture of the turn has no block that says that the call may run: the promise of the turn is not in the picture"
              yeah-check--failures))
      (unless (cl-some (lambda (line)
                         (yeah-diagram--names-all-p line '("rules" "ask" "person")))
                       lines)
        (push "the picture of the turn has no line that says that the rules ask the person: the promise of the turn is not in the picture"
              yeah-check--failures)))
      (dolist (failure yeah-check--failures)
        (message "one-turn-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "one-turn-diagram: %s" blocker))
    (kill-emacs 2))

;;; check-the-one-turn-diagram-shows-the-turn-of-the-agent.el ends here
