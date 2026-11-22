;;; check-the-code-packages-diagram-names-every-module-of-the-kernel.el --- the code-packages diagram names every module of the kernel -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The picture of the packages of the code answers the question of a person
;; who reads the code of Yeah: where does this live?  `lib/' is one
;; directory, and the modules of it are dozens of files that a reader has
;; to know by heart.  The picture puts them into nine packages and names
;; every one of them with the line of its definition.
;;
;; A picture that drops a module without saying so is worse than no picture
;; at all: the reader of the picture cannot tell a module that was dropped
;; from a module that was never there.  This check reads
;; `site/diagrams/code-packages.puml' and measures six things:
;;
;;   1. the file is there, it is not empty, and it is a diagram of
;;      PlantUML: the first line is `@startuml code-packages' and the last
;;      line is `@enduml';
;;   2. the picture has exactly nine packages, and they are the nine of
;;      `docs/SITE-DIAGRAMS-PLAN.md' §8 (D8).  A tenth package is a
;;      package the picture did not promise, and a missing one is a part of
;;      the code with no place in the picture;
;;   3. every name of the form `file:line' points at a file of this
;;      repository, at a line of that file, and at a line that carries a
;;      definition -- an empty line names no code, and a line that holds
;;      code and no definition names no definition;
;;   4. every module of `lib/' is named inside one of the nine packages or
;;      is listed in the note of the modules the picture does not name, with
;;      the reason why it is not in the picture;
;;   5. a module is named in one package and not in two: a module in two
;;      packages has no place of its own;
;;   6. the note of the modules the picture does not name names no module
;;      that is not there, names every module with the reason why it is not
;;      in the picture, and names no module that a package names as well.
;;
;; The rule of the reference lives in one place:
;; `tests/support/yeah-diagram-files.el'.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the picture names every module of the kernel; 1 -- it
;; does not, or it points at something that is not there; 2 -- the tree is
;; not where we think, and the check cannot answer.

;;; Code:

(require 'cl-lib)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defvar yeah-check--blockers nil
  "The reasons why this check cannot answer.")

(defconst yeah-check--package-names
  '("journal and projections"
    "run control"
    "model adapter"
    "tools and registry"
    "rights and approvals"
    "protocols and wire"
    "interface and product"
    "delegation and subagents"
    "placements and plumbing")
  "The nine packages of the code of Yeah.
The nine packages are the nine of `docs/SITE-DIAGRAMS-PLAN.md' §8 (D8): the
journal and the projections, the control of a run, the adapter of the model,
the tools and the registry, the rights and the approvals, the protocols and
the wire, the interface and the product, the delegation and the subagents,
the placements and the plumbing.")

(defconst yeah-check--package-pattern
  "\\`[[:space:]]*package[[:space:]]+\"\\([^\"]*\\)\"[[:space:]]+as[[:space:]]+\\([^[:space:]]+\\)[[:space:]]*{\\'"
  "The pattern of a package of the picture.
The rule is the rule of the check of the diagram of the layers: a package
is a line of the form `package \"NAME\" as alias {'.")

(defun yeah-check--package-lines (text)
  "Return the names of the packages of the picture in TEXT.
A package that is never closed is a package of the picture all the same:
the count is the count of the lines that open a package."
  (let (names)
    (dolist (line (split-string text "\n" t))
      (when (string-match yeah-check--package-pattern line)
        (push (match-string 1 line) names)))
    (nreverse names)))

(defun yeah-check--packages (text)
  "Return the packages of the picture in TEXT.
A package is a list (NAME BODY): the name of the package and the text of
the lines that stand in it.  The braces are counted, so the lines that
stand outside of a package -- the note at the end -- are the lines of no
package."
  (let (stack packages)
    (dolist (line (split-string text "\n" t))
      (cond
       ((string-match yeah-check--package-pattern line)
        (push (list (match-string 1 line) "") stack))
       ((and stack (string-match "\\`[[:space:]]*}" line))
        (push (pop stack) packages))
       (stack
        (setcdr (car stack) (list (concat (nth 1 (car stack)) "\n" line))))))
    (nreverse packages)))

(defun yeah-check--note-lines (text)
  "Return the lines of the note of the picture in TEXT."
  (let (lines in-note)
    (dolist (line (split-string text "\n" t))
      (cond
       ((string-match "\\`[[:space:]]*note\\b" line)
        (setq in-note t))
       ((and in-note (string-match "\\`[[:space:]]*end note\\'" line))
        (setq in-note nil))
       (in-note (push line lines))))
    (nreverse lines)))

(defun yeah-check--exclusion (line)
  "Return the exclusion of LINE, or nil.
An exclusion is a module of `lib/' and the reason why the picture does not
name it.  The reason of an exclusion may be nothing: the check then says
that the note names a module and says nothing about it."
  (when (string-match "\\`[[:space:]]*\\(lib/[A-Za-z0-9._-]+\\.el\\)\\b" line)
    (let ((module (match-string 1 line)))
      (if (string-match "--[[:space:]]*\\(.*\\)\\'" line)
          (list module (string-trim (match-string 1 line)))
        (list module nil)))))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/code-packages.puml" root)))
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
    (push "the tree of the repository is not where we think: there is no site/diagrams/code-packages.puml"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (lines (yeah-diagram--drawing-lines text))
           (package-names (yeah-check--package-lines text))
           (packages (yeah-check--packages text))
           (exclusions (delq nil (mapcar #'yeah-check--exclusion (yeah-check--note-lines text))))
           (named (mapcar (lambda (package)
                            (mapcar #'car (yeah-diagram--references (nth 1 package))))
                          packages))
           (all-named (delete-dups (apply #'append named)))
           (modules (mapcar (lambda (module) (file-relative-name module root))
                             (file-expand-wildcards (expand-file-name "lib/*.el" root)))))
      ;; 1. the file is a diagram of PlantUML and it is not empty.
      (when (string-empty-p (string-trim text))
        (push "site/diagrams/code-packages.puml is empty: there is no picture of the code"
              yeah-check--failures))
      (unless (string= (string-trim (or (car lines) "")) "@startuml code-packages")
        (push (format "site/diagrams/code-packages.puml starts with %s, and the first line of a diagram is `@startuml code-packages'"
                      (format "%S" (string-trim (or (car lines) ""))))
              yeah-check--failures))
      (unless (string= (string-trim (or (car (last lines)) "")) "@enduml")
        (push (format "site/diagrams/code-packages.puml ends with %s, and the last line of a diagram is `@enduml'"
                      (string-trim (or (car (last lines)) "")))
              yeah-check--failures))
      ;; 2. exactly nine packages, and they are the nine of the plan.
      (unless (= (length package-names) (length yeah-check--package-names))
        (push (format "the picture has %d package(s), and it must have exactly %d: the nine packages of the code of Yeah"
                      (length package-names) (length yeah-check--package-names))
              yeah-check--failures))
      (dolist (name yeah-check--package-names)
        (unless (cl-find name package-names :test #'string=)
          (push (format "the picture has no package %s: the nine packages of the code of Yeah are %s"
                        name (string-join yeah-check--package-names ", "))
                yeah-check--failures)))
      (dolist (name package-names)
        (unless (cl-find name yeah-check--package-names :test #'string=)
          (push (format "the picture has a package %s, and it is not one of the nine packages of the code of Yeah"
                        name)
                yeah-check--failures)))
      ;; 3. every name of a file points at code that is there.
      (dolist (broken (yeah-diagram--broken-references root (yeah-diagram--references text)))
        (push (format "the picture of the code names %s:%d, and %s"
                      (nth 0 (car broken)) (nth 1 (car broken)) (nth 1 broken))
              yeah-check--failures))
      (when (null (yeah-diagram--references text))
        (push "the picture of the code names no file at all: this check cannot tell a good name from a bad one"
              yeah-check--failures))
      ;; 4. every module of lib/ is named inside a package or listed in the
      ;; note of the modules the picture does not name.
      (dolist (module modules)
        (unless (or (cl-find module all-named :test #'string=)
                    (cl-find module (mapcar #'car exclusions) :test #'string=))
          (push (format "the module %s is neither named by a package of the picture nor listed in the note of the modules the picture does not name"
                        module)
                yeah-check--failures)))
      ;; 5. a module is named in one package and not in two.
      (dolist (module all-named)
        (let ((places (cl-count module all-named :test #'string=)))
          (when (> places 1)
            (push (format "the module %s is named %d times: a module of the code has one place and not two"
                          module places)
                  yeah-check--failures))))
      ;; 6. the note of the modules the picture does not name.
      (dolist (exclusion exclusions)
        (let ((module (nth 0 exclusion))
              (reason (nth 1 exclusion)))
          (unless (file-exists-p (expand-file-name module root))
            (push (format "the note names %s, and there is no such module" module)
                  yeah-check--failures))
          (when (null reason)
            (push (format "the note names %s, and it does not say why the picture does not name it" module)
                  yeah-check--failures))
          (when (cl-find module all-named :test #'string=)
            (push (format "the module %s is named by a package of the picture and listed in the note as a module the picture does not name"
                          module)
                  yeah-check--failures))))
      (dolist (failure yeah-check--failures)
        (message "code-packages-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "code-packages-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-the-code-packages-diagram-names-every-module-of-the-kernel.el ends here
