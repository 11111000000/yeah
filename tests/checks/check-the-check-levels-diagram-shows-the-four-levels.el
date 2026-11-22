;;; check-the-check-levels-diagram-shows-the-four-levels.el --- the check-levels diagram shows the four levels -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The picture of the levels of verification answers the question of the
;; reader of the section *Messages*: "is this true?".  It says what the four
;; levels of `docs/ARCHITECTURE.md' §10 are, where each of them lives in the
;; tree, and -- the main thought of the section -- where the proof of a
;; level ends.  A green module is not a working product, and a picture that
;; shows only the green modules says the opposite.
;;
;; This check reads `site/diagrams/check-levels.puml' and measures six
;; things:
;;
;;   1. the file is there, it is not empty, and it is a diagram of
;;      PlantUML: the first line is `@startuml check-levels' and the last
;;      line is `@enduml';
;;   2. the picture is an activity: it has a `start' and a `stop';
;;   3. the four levels are named in the drawing as words of their own --
;;      unit, contract, integration and live.  A name that is only a part
;;      of a path is not a name of the level: the directory `tests/unit'
;;      does not say that the picture shows the level unit;
;;   4. the four places of the levels are named in the drawing -- the three
;;      directories of the tests and the gate -- and every one of them is
;;      there in the tree: a picture that names a place that does not
;;      exist sends the reader to a place that does not exist;
;;   5. the levels stand in the order of the strength of their proof: unit,
;;      then contract, then integration, then live.  The order is the
;;      claim of the picture, and a picture that shows the levels in
;;      another order shows another ladder;
;;   6. the boundary is on the picture: the drawing says what a level
;;      proves, and it says where the proof of a level ends.
;;
;; The rule of the reference and the rule of the word live in one place:
;; `tests/support/yeah-diagram-files.el'.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the picture shows the four levels and the boundary; 1
;; -- it does not, or it names a place that is not there; 2 -- the tree is
;; not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--levels
  '("unit" "contract" "integration" "live")
  "The four levels of verification, in the order of the strength of their proof.
The levels are the four of `docs/ARCHITECTURE.md' §10: the unit, the
contract (the canary), the integration and the live (the evaluation).")

(defconst yeah-check--places
  '(("tests/unit" . directory)
    ("tests/checks" . directory)
    ("tests/live" . directory)
    ("scripts/gate" . file))
  "The places of the levels, and what each of them is.
The three directories hold the tests of the three lower levels, and the
gate is the runner of the checks of the tree.")

(defun yeah-check--says-level-p (lines word)
  "Return non-nil when one of LINES says WORD as a word of its own.
The names of the places are taken out of the lines before the word is
looked for: the word `unit' of `tests/unit' says where the level lives and
not what the level is.  The rule of the place is the rule of every picture
of the site and it lives in one place: `tests/support/yeah-diagram-files.el'."
  (yeah-diagram--says-p (mapcar #'yeah-diagram--without-places lines) word))

(defun yeah-check--first-level (lines word)
  "Return the number of the first of LINES that says WORD, or nil."
  (cl-position-if (lambda (line) (yeah-check--says-level-p (list line) word))
                  lines))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/check-levels.puml" root)))
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
    (push "the tree of the repository is not where we think: there is no site/diagrams/check-levels.puml"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (lines (yeah-diagram--drawing-lines text)))
      ;; 1. the file is a diagram of PlantUML and it is not empty.
      (when (string-empty-p (string-trim text))
        (push "site/diagrams/check-levels.puml is empty: there is no picture of the levels"
              yeah-check--failures))
      (unless (string= (string-trim (or (car lines) "")) "@startuml check-levels")
        (push (format "site/diagrams/check-levels.puml starts with %s, and the first line of a diagram is `@startuml check-levels'"
                      (string-trim (or (car lines) "")))
              yeah-check--failures))
      (unless (string= (string-trim (or (car (last lines)) "")) "@enduml")
        (push (format "site/diagrams/check-levels.puml ends with %s, and the last line of a diagram is `@enduml'"
                      (string-trim (or (car (last lines)) "")))
              yeah-check--failures))
      ;; 2. the picture is an activity: it starts and it stops.
      (unless (member "start" lines)
        (push "the picture of the levels has no `start': the levels are an activity, and an activity begins"
              yeah-check--failures))
      (unless (member "stop" lines)
        (push "the picture of the levels has no `stop': the levels are an activity, and an activity ends"
              yeah-check--failures))
      ;; 3. the four levels are named as words of their own.
      (dolist (level yeah-check--levels)
        (unless (yeah-check--says-level-p lines level)
          (push (format "the drawing does not say %s: the picture must show the level %s, and a name that is only a part of a path is not the name of a level"
                        level level)
                yeah-check--failures)))
      ;; 4. the places of the levels are named, and they are there.
      (dolist (place yeah-check--places)
        (let ((name (car place))
              (kind (cdr place)))
          (unless (yeah-diagram--says-p lines name)
            (push (format "the drawing does not say %s: the picture must show where the level lives"
                          name)
                  yeah-check--failures))
          (let ((path (expand-file-name name root)))
            (cond
             ((and (eq kind 'directory) (not (file-directory-p path)))
              (push (format "the picture names %s, and there is no such directory in the tree" name)
                    yeah-check--failures))
             ((and (eq kind 'file) (not (file-regular-p path)))
              (push (format "the picture names %s, and there is no such file in the tree" name)
                    yeah-check--failures))))))
      ;; 5. the levels stand in the order of the strength of their proof.
      (let ((positions (mapcar (lambda (level) (yeah-check--first-level lines level))
                                yeah-check--levels)))
        (when (cl-every #'numberp positions)
          (let ((rest positions)
                (ordered t))
            (while (and rest (cdr rest))
              (unless (< (car rest) (cadr rest))
                (setq ordered nil))
              (setq rest (cdr rest)))
            (unless ordered
              (push (format "the levels of the picture do not stand in the order of the strength of their proof: the order of the levels is %s"
                            (string-join yeah-check--levels ", "))
                    yeah-check--failures)))))
      ;; 6. the boundary of the proof is on the picture.
      (unless (yeah-check--says-level-p lines "boundary")
        (push "the drawing does not say `boundary': the picture must show where the proof of a level ends"
              yeah-check--failures))
      (unless (yeah-check--says-level-p lines "proves")
        (push "the drawing does not say `proves': the picture must say what a level proves"
              yeah-check--failures))
      (dolist (failure yeah-check--failures)
        (message "check-levels-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "check-levels-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-the-check-levels-diagram-shows-the-four-levels.el ends here
