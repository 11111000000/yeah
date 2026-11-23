;;; check-the-placements-diagram-shows-the-placements-and-the-protocols.el --- the placements show the placements and the protocols -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The picture of the placements is written by hand in the notation of D2,
;; and every leaf of it names the file of the kernel that implements the
;; leaf.  The three placements -- attached, service and batch -- are three
;; ways of giving the kernel a session, a transport and an answerer, and
;; the picture says where each of them lives and what speaks to it.
;;
;; This check reads `site/diagrams/placements.d2` and measures:
;;
;;   1. the picture is not empty and it has nodes;
;;   2. every name of a file points at code that is there, at a line that
;;      carries a definition; a picture that names no file at all cannot
;;      tell a good name from a bad one;
;;   3. the seven modules of the placements and the protocols are named:
;;      the placements are in `yeah-placement.el` and the product layer,
;;      the protocols are in `yeah-acp.el` and `yeah-mcp.el`, and the
;;      wire that carries them is in `yeah-wire.el` and `yeah-wire-socket.el`;
;;   4. the drawing shows the placements and the protocols;
;;   5. the honest limit of the wire is one note: the part of the note
;;      that speaks of stdio says that a cancel cannot interrupt a running
;;      prompt, and the part of the note that speaks of the local socket
;;      says that a cancel is handled while the prompt is still running.  A
;;      note that swapped the two halves says the opposite of the truth and
;;      says every word of the truth.
;;
;; The rules of the reader of the pictures live in one place:
;; `tests/support/yeah-diagram-files.el`.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the picture shows the placements and the protocols; 1 --
;; it does not; 2 -- the tree is not where we think, and the check cannot
;; answer.

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
The placements are in `yeah-placement.el` and the product layer, the
protocols are in `yeah-acp.el` and `yeah-mcp.el`, and the wire that
carries them is in `yeah-wire.el` and `yeah-wire-socket.el`.")

(defconst yeah-check--required-words
  '(("attached" "the attached placement")
    ("service" "the service placement")
    ("batch" "the batch placement")
    ("ACP" "the ACP protocol")
    ("MCP" "the MCP protocol"))
  "The words of the drawing that the diagram of the placements must show.
Every word is a word of the picture and not a word of its comment.

The words of the limit of the wire are not in this list: the limit is a
relation between the two transports and not a bag of words, and a bag of
words says nothing about which transport is which.")

(defun yeah-check--word-place (word words)
  "Return the place of WORD in WORDS, or nil.
The place of a word is its number in the list of the words, counted from
zero.  The words are compared as words and not as pieces of text."
  (let ((place 0))
    (catch 'found
      (dolist (candidate words)
        (when (string= word candidate)
          (throw 'found place))
        (setq place (1+ place)))
      nil)))

(defun yeah-check--missing-words (words names)
  "Return the names of NAMES that the list of WORDS does not hold.
The names are compared as words and not as pieces of text."
  (let (missing)
    (dolist (name names)
      (unless (member name words)
        (push name missing)))
    (nreverse missing)))

(let* ((root (expand-file-name default-directory))
       (reader (expand-file-name "tests/support/yeah-diagram-files.el" root))
       (diagram (expand-file-name "site/diagrams/placements.d2" root)))
  (unless (file-directory-p (expand-file-name "lib" root))
    (push "the tree of the repository is not where we think: there is no lib/"
          yeah-check--blockers))
  (unless (file-readable-p reader)
    (push "the tree of the repository is not where we think: there is no tests/support/yeah-diagram-files.el"
          yeah-check--blockers))
  (unless (file-readable-p diagram)
    (push "the tree of the repository is not where we think: there is no site/diagrams/placements.d2"
          yeah-check--blockers))
  (when (null yeah-check--blockers)
    (load reader nil t)
    (let* ((text (yeah-diagram--text diagram))
           (engine (yeah-diagram--engine-of diagram))
           (blocks (yeah-diagram--d2-blocks text))
           (content (yeah-diagram--d2-drawing-lines text))
           (references (yeah-diagram--references text engine))
           (note (yeah-diagram--d2-note text)))
      ;; 1. the picture is there and it is not empty.
      (when (string-empty-p (string-trim text))
        (push "the diagram site/diagrams/placements.d2 is empty" yeah-check--failures))
      (when (null blocks)
        (push "the diagram site/diagrams/placements.d2 has no node" yeah-check--failures))
      ;; 2. every name of a file points at code that is there.
      (dolist (reference references)
        (let ((defect (yeah-diagram--reference-defect root
                                                          (nth 0 reference)
                                                          (nth 1 reference))))
          (when defect
            (push defect yeah-check--failures))))
      ;; A picture that names nothing cannot tell a good name from a bad one.
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
      ;; 4. the drawing shows the placements and the protocols.
      (dolist (word yeah-check--required-words)
        (unless (yeah-diagram--says-p content (car word))
          (push (format "the drawing does not say %s: the picture must show %s"
                        (car word) (cadr word))
                yeah-check--failures)))
      ;; 5. the honest limit of the wire.
      (let* ((words (apply #'append (mapcar #'yeah-diagram--words note)))
             (stdio (yeah-check--word-place "stdio" words))
             (socket (and stdio
                           (let ((rest (nthcdr stdio words)))
                             (and rest
                                  (let ((place (yeah-check--word-place "socket" rest)))
                                    (and place (+ stdio place)))))))
             (before (and stdio socket (cl-subseq (nthcdr stdio words) 0 (- socket stdio))))
             (after (and socket (nthcdr socket words)))
             (missing-stdio (and before (yeah-check--missing-words before '("cancel" "cannot"))))
             (missing-socket (and after (yeah-check--missing-words after '("cancel" "handled")))))
        (when (null note)
          (push "the picture has no note at all: the picture must say the honest limit of the wire"
                yeah-check--failures))
        (when (null stdio)
          (push "the note of the picture does not name stdio: the note must say that a cancel cannot interrupt a running prompt on stdio"
                yeah-check--failures))
        (when (null socket)
          (push "the note of the picture does not name the local socket: the note must say that a cancel is handled while the prompt is still running"
                yeah-check--failures))
        (when (and missing-stdio (not (null missing-stdio)))
          (push (format "the part of the note about stdio does not say that a cancel cannot interrupt a running prompt: the word %s is not there"
                        (car missing-stdio))
                yeah-check--failures))
        (when (and missing-socket (not (null missing-socket)))
          (push (format "the part of the note about the local socket does not say that a cancel is handled while the prompt is still running: the word %s is not there"
                        (car missing-socket))
                yeah-check--failures)))
      (dolist (failure yeah-check--failures)
        (message "placements-diagram: %s" failure))
      (if yeah-check--failures
          (kill-emacs 1)
        (kill-emacs 0))))
  (when yeah-check--blockers
    (dolist (blocker yeah-check--blockers)
      (message "placements-diagram: %s" blocker))
    (kill-emacs 2)))

;;; check-the-placements-diagram-shows-the-placements-and-the-protocols.el ends here
