;;; check-the-placements-diagram-shows-the-placements-and-the-protocols.el --- the placements diagram shows the placements and the protocols -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The diagram of the placements answers the first question of a person
;; who installs Yeah: where does it run, and who talks to it.  The
;; picture is written by hand, and a picture that has drifted from the
;; code is worse than no picture at all: the reader of the site reads it
;; as the truth about the product.
;;
;; This check reads `site/diagrams/placements.puml' and measures four
;; things:
;;
;;   1. the file is there, it is not empty, and it is a diagram of the
;;      placements: it begins with `@startuml placements' and it ends
;;      with `@enduml';
;;   2. every name of the form `file:line' points at a file of this
;;      repository, at a line of that file, and at a line that carries a
;;      definition -- an empty line names no code, and a line that holds
;;      code and no definition names no definition;
;;   3. the picture names the seven modules that implement the
;;      placements and the protocols, each of them with a line that
;;      carries a definition;
;;   4. the drawing shows the three placements -- attached, service and
;;      batch -- and the two protocols -- ACP and MCP -- and it shows
;;      the honest limit of the wire: on stdio a cancel cannot interrupt
;;      a running prompt, and the local socket is what can.
;;
;; A word of the picture is a word of the drawing and not a word of the
;; comment at the top of the file: a comment that names a placement does
;; not show it.  A name of a file is not the picture saying the name of
;; the module either.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the diagram shows the placements and the protocols;
;; 1 -- it does not, or it points at something that is not there; 2 --
;; the tree is not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--required-modules
  '("lib/yeah-product.el"
    "lib/yeah-service.el"
    "lib/yeah-placement.el"
    "lib/yeah-acp.el"
    "lib/yeah-mcp.el"
    "lib/yeah-wire.el"
    "lib/yeah-wire-socket.el")
  "The modules that the diagram of the placements has to name.
The placements are in `yeah-placement.el' and the product layer, the
protocols are in `yeah-acp.el' and `yeah-mcp.el', and the wire that
carries them is in `yeah-wire.el' and `yeah-wire-socket.el'.")

(defconst yeah-check--required-words
  '(("attached" "the attached placement")
    ("service" "the service placement")
    ("batch" "the batch placement")
    ("ACP" "the ACP protocol")
    ("MCP" "the MCP protocol")
    ("stdio" "the transport that cannot cancel a running prompt")
    ("socket" "the transport that can cancel a running prompt")
    ("cancel" "the honest limit of the wire")
    ("cannot" "the honest limit of the wire"))
  "The words of the drawing that the diagram of the placements must show.
Every word is a word of the picture and not a word of its comment.")

(defun yeah-check--root ()
  "Return the root of the project."
  (expand-file-name default-directory))

(let* ((root (yeah-check--root))
       (diagrams (expand-file-name "site/diagrams" root))
       (diagram (expand-file-name "site/diagrams/placements.puml" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/" yeah-check--blockers))
  (unless (file-directory-p diagrams)
    (push "the tree of the repository is not where we think: there is no site/diagrams/"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    ;; The reader of the diagrams is one reader for every check of them.
    (load (expand-file-name "tests/support/yeah-diagram-files.el" root) nil t)
    (if (not (file-readable-p diagram))
        (push "the diagram site/diagrams/placements.puml is not there"
              yeah-check--failures)
      (let* ((text (yeah-diagram--text diagram))
             (raw (split-string text "\n" t)))
        (when (string-empty-p (string-trim text))
          (push "the diagram site/diagrams/placements.puml is empty"
                yeah-check--failures))
        ;; 1. the format of the diagram.
        (unless (equal (string-trim (or (car raw) "")) "@startuml placements")
          (push (format "the diagram site/diagrams/placements.puml begins with %S, and it must begin with `@startuml placements'"
                        (string-trim (or (car raw) "")))
                yeah-check--failures))
        (unless (equal (string-trim (or (car (last raw)) "")) "@enduml")
          (push (format "the diagram site/diagrams/placements.puml ends with %S, and it must end with `@enduml'"
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
          ;; 3. the seven modules of the placements and the protocols.
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
          ;; 4. the drawing shows the placements, the protocols and the limit.
          (dolist (word yeah-check--required-words)
            (unless (yeah-diagram--says-p content (car word))
              (push (format "the drawing does not say %s: the picture must show %s"
                            (car word) (cadr word))
                    yeah-check--failures)))))))
  (when yeah-check--failures
    (dolist (failure yeah-check--failures)
      (message "placements-diagram: %s" failure))
    (kill-emacs 1))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "placements-diagram: %s" blocker))
    (kill-emacs 2))
  (kill-emacs 0))

;;; check-the-placements-diagram-shows-the-placements-and-the-protocols.el ends here
