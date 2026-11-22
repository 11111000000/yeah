;;; check-the-emacs-layer-diagram-shows-the-bridge-and-the-scopes.el --- the Emacs-layer diagram shows the bridge and the scopes -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The picture of the Emacs layer is written by hand, and it says what
;; the layer is: the person works in the editor's Emacs, the kernel of
;; the agent runs in the agent's Emacs, and the bridge is the only path
;; from the harness to the live state of the editor's Emacs -- a
;; capability the person approves on purpose.
;;
;; A picture of the layer that dropped the bridge shows a layer in which
;; the harness reaches the live state some other way, and a picture that
;; shows other answers than the kernel knows shows a dialogue that does
;; not exist.  This check reads `site/diagrams/emacs-layer.puml' and
;; measures seven things:
;;
;;   1. the file is there, it is not empty, and it is a diagram of
;;      PlantUML: the first line is `@startuml emacs-layer' and the last
;;      line is `@enduml';
;;   2. every reference of the form `file:line' names a file of this
;;      repository, a line of that file and a line that carries a
;;      definition -- a line that holds code and no definition names no
;;      definition;
;;   3. the picture names the five modules that hold the layer together:
;;      `lib/yeah-emacs.el', `lib/yeah-bridge.el', `lib/yeah-compose.el',
;;      `lib/yeah-doctor-ui.el' and `lib/yeah-approval-ui.el'.  A
;;      capability of the layer that is not in the picture is a
;;      capability the reader does not see;
;;   4. every block of the picture names a file, and the bridge is a
;;      block of its own: the block with the alias `bridge' names the
;;      code of the bridge.  A picture in which the bridge is one word
;;      among the others shows a bridge that is not the path to the live
;;      state;
;;   5. one line of the picture names the five answers the person may
;;      give to a request for permission -- `:once', `:session',
;;      `:project', `:global' and `:reject'.  The same line names them in
;;      the picture of the turn of the agent, because the person answers
;;      the same way in both;
;;   6. every one of the six capabilities of the layer -- BUFFERS,
;;      INTROSPECT, EDIT, DIAGNOSE, COMPOSE and RECOVER -- is named by a
;;      *title* of the picture: a title is a quoted string of a line, and
;;      a capability that is only in the body of a block is not the
;;      title of that block;
;;   7. the three hosts of the picture are there: a title names the
;;      person and names neither the editor nor the agent, a title names
;;      the editor's Emacs and the agent does not, and a title names the
;;      agent's Emacs and the editor does not.  A picture that calls the
;;      person the user and the hosts the first and the second host
;;      shows a layer without a person and without two Emacs.
;;
;; The rule of the reference is the rule of every diagram of the site and
;; it lives in one place: `tests/support/yeah-diagram-files.el'.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the picture shows the layer; 1 -- it does not, or it
;; points at something that is not there; 2 -- the tree is not where we
;; think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--layer-modules
  '("lib/yeah-emacs.el"
    "lib/yeah-bridge.el"
    "lib/yeah-compose.el"
    "lib/yeah-doctor-ui.el"
    "lib/yeah-approval-ui.el")
  "The modules the picture of the Emacs layer has to name.")

(defconst yeah-check--answers
  '("once" "session" "project" "global" "reject")
  "The answers the person may give to a request for permission.")

(defconst yeah-check--layer-capabilities
  '("BUFFERS" "INTROSPECT" "EDIT" "DIAGNOSE" "COMPOSE" "RECOVER")
  "The six capabilities of the Emacs layer.
Every one of them is named by a title of the picture.  The case
matters: the picture says `EDIT' and the word `edit' is not the word
`EDIT'.")

(defun yeah-check--names-p (line word)
  "Return non-nil when LINE names WORD as a whole word.
The name of a file is not a word of the picture, and the case
matters: the word `ACP' is not the word `acp'."
  (and (yeah-diagram--names-all-p line (list word)) t))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/emacs-layer.puml" root)))
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
    (push "the tree of the repository is not where we think: there is no site/diagrams/emacs-layer.puml"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (lines (yeah-diagram--drawing-lines text))
           (titles (yeah-diagram--titles text))
           (references (yeah-diagram--references text))
           (components (yeah-diagram--components text))
           (named (delete-dups (mapcar #'car references))))
      ;; 1. the file is a diagram of PlantUML and it is not empty.
      (when (string-empty-p (string-trim text))
        (push "site/diagrams/emacs-layer.puml is empty: there is no picture of the layer"
              yeah-check--failures))
      (unless (string= (string-trim (or (car lines) "")) "@startuml emacs-layer")
        (push (format "site/diagrams/emacs-layer.puml starts with %s, and the first line of a diagram is `@startuml emacs-layer'"
                      (format "%S" (string-trim (or (car lines) ""))))
              yeah-check--failures))
      (unless (string= (string-trim (or (car (last lines)) "")) "@enduml")
        (push (format "site/diagrams/emacs-layer.puml ends with %s, and the last line of a diagram is `@enduml'"
                      (format "%S" (string-trim (or (car (last lines)) ""))))
              yeah-check--failures))
      ;; 2. every reference points at a file, at a line and at code.
      (dolist (broken (yeah-diagram--broken-references root references))
        (push (format "the picture of the Emacs layer names %s:%d, and %s"
                      (nth 0 (car broken)) (nth 1 (car broken)) (nth 1 broken))
              yeah-check--failures))
      (when (null references)
        (push "the picture of the Emacs layer names no file at all: this check cannot tell a good name from a bad one"
              yeah-check--failures))
      ;; 3. the five modules that hold the layer together are named.
      (dolist (module yeah-check--layer-modules)
        (unless (member module named)
          (push (format "the picture of the Emacs layer does not name %s: the capability it holds is not in the picture"
                        module)
                yeah-check--failures)))
      ;; 4. every block names a file, and the bridge is a block of its own.
      (dolist (component components)
        (unless (nth 1 component)
          (push (format "the block %s of the picture names no file" (nth 0 component))
                yeah-check--failures)))
      (let ((bridge (cl-find "bridge" components :key #'car :test #'string=)))
        (unless bridge
          (push "the picture of the Emacs layer has no block of the bridge: the bridge is the subject of the picture"
                yeah-check--failures))
        (unless (and bridge (member "lib/yeah-bridge.el" (mapcar #'car (nth 1 bridge))))
          (push "the block of the bridge names no file of lib/yeah-bridge.el: the bridge is the only path to the live state of the editor's Emacs"
                yeah-check--failures)))
      ;; 5. the answers of the person are the words of the kernel.
      (unless (cl-some (lambda (line) (yeah-diagram--names-all-p line yeah-check--answers))
                       lines)
        (push "the picture of the Emacs layer has no line that names the answers of the person: once, session, project, global and reject"
              yeah-check--failures))
      ;; 6. the six capabilities of the layer are named by a title.
      (dolist (capability yeah-check--layer-capabilities)
        (unless (cl-some (lambda (title) (yeah-check--names-p title capability))
                         titles)
          (push (format "the picture of the Emacs layer has no title that names the capability %s: the capability of the layer is not in the picture"
                        capability)
                yeah-check--failures)))
      ;; 7. the three hosts of the picture are there.
      (unless (cl-some (lambda (title)
                         (and (yeah-check--names-p title "person")
                              (not (yeah-check--names-p title "editor"))
                              (not (yeah-check--names-p title "agent"))))
                       titles)
        (push "the picture of the Emacs layer has no title that names the person and names neither the editor nor the agent: the person is one of the three hosts of the picture"
              yeah-check--failures))
      (unless (cl-some (lambda (title)
                         (and (yeah-check--names-p title "editor")
                              (yeah-check--names-p title "Emacs")
                              (not (yeah-check--names-p title "agent"))))
                       titles)
        (push "the picture of the Emacs layer has no title that names the editor's Emacs and the Emacs itself and names no agent: the editor's Emacs is one of the three hosts of the picture"
              yeah-check--failures))
      (unless (cl-some (lambda (title)
                         (and (yeah-check--names-p title "agent")
                              (yeah-check--names-p title "Emacs")
                              (not (yeah-check--names-p title "editor"))))
                       titles)
        (push "the picture of the Emacs layer has no title that names the agent's Emacs and the Emacs itself and names no editor: the agent's Emacs is one of the three hosts of the picture"
              yeah-check--failures))
      (dolist (failure yeah-check--failures)
        (message "emacs-layer-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "emacs-layer-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-the-emacs-layer-diagram-shows-the-bridge-and-the-scopes.el ends here
