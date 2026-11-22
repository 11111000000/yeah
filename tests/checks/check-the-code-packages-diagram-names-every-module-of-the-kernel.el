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
;;   4. every module of `lib/' -- in every directory of `lib/' -- is named
;;      inside one of the nine packages or is listed in the note of the
;;      modules the picture does not name, with the reason why it is not in
;;      the picture;
;;   5. a module is named in one package and not in two: a module in two
;;      packages has no place of its own, and the refusal names the module
;;      and the two packages that name it;
;;   6. the note of the modules the picture does not name names no module
;;      that is not there, names every module with the reason why it is not
;;      in the picture, and names no module that a package names as well.
;;
;; The rule of the reference, the rule of the package, the rule of the
;; note, the rule of the exclusion and the walk of the modules of `lib/'
;; live in one place: `tests/support/yeah-diagram-files.el'.  A copy of a
;; rule in a check is a rule that drifts away from the rule of the other
;; checks, and two checks that read one picture two ways give two
;; verdicts for one picture.
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

(defconst yeah-check--expected-packages
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

(defun yeah-check--packages-by-module (named-by)
  "Return the packages of the picture that name each module.
NAMED-BY is a list of (PACKAGE . MODULES): the name of a package of the
picture and the modules it names.  The answer is a list of (MODULE .
PACKAGES): the module and the names of the packages that name it, in the
order of the picture.

The packages that name a module are counted, and not the names of the
module: a module that two packages name is a module that has no place of
its own, and the check must be able to name the two packages."
  (let (by-module)
    (dolist (entry named-by)
      (dolist (module (cdr entry))
        (let ((found (assoc module by-module)))
          (if found
              (setcdr found (append (cdr found) (list (car entry))))
            (push (cons module (list (car entry))) by-module)))))
    (nreverse by-module)))

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
           (package-names (yeah-diagram--package-names text))
           (packages (yeah-diagram--packages text))
           (exclusions (delq nil (mapcar #'yeah-diagram--exclusion (yeah-diagram--note-lines text))))
           (named-by (mapcar (lambda (package)
                               (cons (nth 0 package)
                                     (delete-dups
                                      (mapcar #'car
                                              (yeah-diagram--references (nth 1 package))))))
                             packages))
           (all-named (delete-dups (apply #'append (mapcar #'cdr named-by))))
           (modules (yeah-diagram--modules-of root)))
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
      (unless (= (length package-names) (length yeah-check--expected-packages))
        (push (format "the picture has %d package(s), and it must have exactly %d: the nine packages of the code of Yeah"
                      (length package-names) (length yeah-check--expected-packages))
              yeah-check--failures))
      (dolist (name yeah-check--expected-packages)
        (unless (cl-find name package-names :test #'string=)
          (push (format "the picture has no package %s: the nine packages of the code of Yeah are %s"
                        name (string-join yeah-check--expected-packages ", "))
                yeah-check--failures)))
      (dolist (name package-names)
        (unless (cl-find name yeah-check--expected-packages :test #'string=)
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
      (dolist (entry (yeah-check--packages-by-module named-by))
        (let ((module (car entry))
              (packages (cdr entry)))
          (when (> (length packages) 1)
            (push (format "the module %s is named by two packages of the picture: %s"
                          module (string-join packages " and "))
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
