;;; check-the-fixed-point-diagram-shows-the-loop-of-the-delegation.el --- the fixed point diagram shows the loop of the delegation -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The diagram of the fixed point is the sentence of the name of Yeah:
;; person -> environment -> agent -> environment.  The picture is written
;; by hand, and a picture that has drifted from the code is worse than no
;; picture at all: the reader of the site reads it as the truth about the
;; product.
;;
;; This check reads `site/diagrams/fixed-point.puml' and measures four
;; things:
;;
;;   1. the file is there, it is not empty, and it is a diagram of the
;;      fixed point: it begins with `@startuml fixed-point' and it ends
;;      with `@enduml';
;;   2. every name of the form `file:line' points at a file of this
;;      repository, at a line of that file, and at a line that carries a
;;      definition -- an empty line names no code, and a line that holds
;;      code and no definition names no definition;
;;   3. the picture names the four modules that carry the loop -- the
;;      delegation, the child, the preset of the child and the state of
;;      Emacs -- each of them with a line that carries a definition;
;;   4. the drawing shows the loop and the bounds of it: the delegation
;;      names a preset, the child runs in a session and a journal of its
;;      own at a depth of its own, the bounds of the tree are named, the
;;      agent runs a check of the environment, and the environment is
;;      what the agent changes and what the agent reads again.
;;
;; A word of the picture is a word of the drawing and not a word of the
;; comment at the top of the file: a comment that names a part of the
;; loop does not show it.  A name of a file is not the picture saying the
;; name of the module either.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the diagram shows the loop of the delegation; 1 -- it
;; does not, or it points at something that is not there; 2 -- the tree is
;; not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--required-modules
  '("lib/yeah-delegate.el"
    "lib/yeah-subagent.el"
    "lib/yeah-agent.el"
    "lib/yeah-emacs.el")
  "The modules that the diagram of the fixed point has to name.
The delegation is in `yeah-delegate.el', the child and its bounds are in
`yeah-subagent.el', the preset of the child is in `yeah-agent.el', and
the state of Emacs that the agent reads and writes is in
`yeah-emacs.el'.")

(defconst yeah-check--required-words
  '(("delegate" "the delegation that makes the loop a loop")
    ("preset" "the preset that the delegation names")
    ("session" "the session of its own that the child runs in")
    ("journal" "the journal of its own that the child writes into")
    ("depth" "the depth of the tree of the children")
    ("budget" "the bound of the tree of the children")
    ("check" "the check that decides whether the loop is closed")
    ("environment" "the environment that the agent changes and reads again"))
  "The words of the drawing that the diagram of the fixed point must show.
Every word is a word of the picture and not a word of its comment.")

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(let* ((root (yeah-check--root))
       (diagrams (expand-file-name "site/diagrams" root))
       (diagram (expand-file-name "site/diagrams/fixed-point.puml" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/" yeah-check--blockers))
  (unless (file-directory-p diagrams)
    (push "the tree of the repository is not where we think: there is no site/diagrams/"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    ;; The reader of the diagrams is one reader for every check of them.
    (load (expand-file-name "tests/support/yeah-diagram-files.el" root) nil t)
    (if (not (file-readable-p diagram))
        (push "the diagram site/diagrams/fixed-point.puml is not there"
              yeah-check--failures)
      (let* ((text (yeah-diagram--text diagram))
             (raw (split-string text "\n" t)))
        (when (string-empty-p (string-trim text))
          (push "the diagram site/diagrams/fixed-point.puml is empty"
                yeah-check--failures))
        ;; 1. the format of the diagram.
        (unless (equal (string-trim (or (car raw) "")) "@startuml fixed-point")
          (push (format "the diagram site/diagrams/fixed-point.puml begins with %S, and it must begin with `@startuml fixed-point'"
                        (string-trim (or (car raw) "")))
                yeah-check--failures))
        (unless (equal (string-trim (or (car (last raw)) "")) "@enduml")
          (push (format "the diagram site/diagrams/fixed-point.puml ends with %S, and it must end with `@enduml'"
                        (string-trim (or (car (last raw)) "")))
                yeah-check--failures))
        (let* ((references (yeah-diagram--references text))
               (content (yeah-diagram--drawing-lines text)))
          ;; 2. every name of a file points at code that is there.
          (dolist (reference references)
            (let ((defect (yeah-diagram--reference-defect root
                                                          (nth 0 reference)
                                                          (nth 1 reference))))
              (when defect
                (push defect yeah-check--failures))))
          ;; A diagram that names nothing cannot tell a good name from a bad one.
          (when (null references)
            (push "the diagram names no file at all: this check cannot tell a good name from a bad one"
                  yeah-check--failures))
          ;; 3. the four modules that carry the loop.
          (dolist (module yeah-check--required-modules)
            (unless (cl-find-if
                     (lambda (reference)
                       (and (string= module (nth 0 reference))
                            (null (yeah-diagram--reference-defect root
                                                                 (nth 0 reference)
                                                                 (nth 1 reference)))))
                     references)
              (push (format "the diagram does not name %s with a line that carries a definition"
                            module)
                    yeah-check--failures)))
          ;; 4. the drawing shows the loop and the bounds of it.
          (dolist (word yeah-check--required-words)
            (unless (yeah-diagram--says-p content (car word))
              (push (format "the drawing does not say %s: the picture must show %s"
                            (car word) (cadr word))
                    yeah-check--failures)))))))
  (when yeah-check--failures
    (dolist (failure yeah-check--failures)
      (message "fixed-point-diagram: %s" failure))
    (kill-emacs 1))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "fixed-point-diagram: %s" blocker))
    (kill-emacs 2))
  (kill-emacs 0))

;;; check-the-fixed-point-diagram-shows-the-loop-of-the-delegation.el ends here
