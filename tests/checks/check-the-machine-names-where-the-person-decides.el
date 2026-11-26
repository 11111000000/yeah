;;; check-the-machine-names-where-the-person-decides.el --- the machine names where the person decides -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The machine of the states of a run has a subject: the state where the
;; person decides.  The human is an asynchronous master, and the machine
;; waits there -- awaiting-user-permission is the one state of the
;; picture whose name says that a person is expected, and the picture
;; names it twice: the wash of the subject covers the state, and the
;; boundary of the picture hangs under it.
;;
;; The wash is a token, and the token lives in places that must agree:
;; the stylesheet of the site names it for the light and for the dark
;; frame (--diagram-subject-bg), the palette of every theme defines it
;; for the pictures of that theme (!define SUBJECT_BG), the source of
;; the machine carries it on the subject state, and the rendered
;; picture of every theme draws it.  Three names of one value that
;; disagree are three values, and the picture the reader sees is the
;; fourth.
;;
;; This check reads those places and holds them together:
;;
;;   1. the stylesheet names the wash twice -- the light frame and the
;;      dark frame -- and the two washes differ;
;;   2. the palette of every theme defines SUBJECT_BG with the value of
;;      its frame;
;;   3. the source of the machine carries the wash on the subject state,
;;      and the boundary of the picture hangs under that state;
;;   4. the rendered picture of every theme draws the wash of its frame.
;;
;; That the source of the machine is a function of the code is the claim
;; of another check (check-the-state-diagram-comes-from-the-code): this
;; check reads the source the tree carries.
;;
;; The seam of the control of the claim is the define of the palette of
;; the light theme: a palette that names no wash must make this check
;; fail by its own assertion.
;;
;; The tree of the repository is never written: this check only reads.
;;
;; Exit codes: 0 -- the machine names where the person decides; 1 -- it
;; does not; 2 -- the tree is not where we think.

;;; Code:

(defvar yeah-subject--failures nil
  "The failures this check found.")

(defconst yeah-subject--light-value "eaf4ea"
  "The wash of the subject in the light frame, as the stylesheet names it.")

(defconst yeah-subject--dark-value "0e3a2c"
  "The wash of the subject in the dark frame, as the stylesheet names it.")

(defun yeah-subject--wash-values (text)
  "Return the wash values named in the stylesheet TEXT, in order."
  (let ((values nil)
        (pos 0))
    (while (string-match "--diagram-subject-bg:[[:space:]]*\\([^;]+\\);" text pos)
      (push (string-trim (match-string 1 text)) values)
      (setq pos (match-end 0)))
    (nreverse values)))

(defun yeah-subject--downcase-hex (value)
  "Return VALUE as a lower-case hex word without a fragment sign."
  (downcase (string-trim (replace-regexp-in-string "\\`#" "" value))))

(defun yeah-subject--read (path)
  "Return the text of the file at PATH, or nil when it cannot be read."
  (condition-case err
      (with-temp-buffer
        (insert-file-contents path)
        (buffer-string))
    (error nil)))

(let* ((root (expand-file-name default-directory))
       (stylesheet (expand-file-name "site/styles.css" root)))
  (unless (file-readable-p stylesheet)
    (message "subject: the stylesheet of the site is not there: %s" stylesheet)
    (kill-emacs 2))
  ;; 1. the stylesheet names the wash of both frames
  (let ((values (yeah-subject--wash-values (yeah-subject--read stylesheet))))
    (unless (= 2 (length values))
      (push (format "the stylesheet names %d wash(es) of the subject, and the light and the dark frame need two"
                    (length values))
            yeah-subject--failures))
    (when (= 2 (length values))
      (unless (string= (yeah-subject--downcase-hex (nth 0 values))
                       yeah-subject--light-value)
        (push (format "the light frame names the wash %S, and the floor of this check is %S"
                      (nth 0 values) yeah-subject--light-value)
              yeah-subject--failures))
      (unless (string= (yeah-subject--downcase-hex (nth 1 values))
                       yeah-subject--dark-value)
        (push (format "the dark frame names the wash %S, and the floor of this check is %S"
                      (nth 1 values) yeah-subject--dark-value)
              yeah-subject--failures))
      (when (string= (yeah-subject--downcase-hex (nth 0 values))
                     (yeah-subject--downcase-hex (nth 1 values)))
        (push "the light and the dark frame name one wash: a wash that does not change with the theme is a picture drawn for one theme"
              yeah-subject--failures))))
  ;; 2. the palette of every theme defines the wash of its frame.  The
  ;;    value is read by splitting the palette into lines and the line
  ;;    into words: a character class that decides what a space is has
  ;;    already read one define past its own line, and a value that
  ;;    reaches into the next line is a value the palette does not name.
  (dolist (theme '(("light" yeah-subject--light-value) ("dark" yeah-subject--dark-value)))
    (let* ((name (car theme))
           (value (symbol-value (cadr theme)))
           (path (expand-file-name (format "site/diagrams/palette-%s.puml" name) root))
           (text (and (file-readable-p path) (yeah-subject--read path))))
      (unless text
        (push (format "the palette of the %s theme is not there: %s" name path)
              yeah-subject--failures))
      (when text
        (let ((named nil))
          (dolist (line (split-string text "\n" t) )
            (when (string-prefix-p "!define SUBJECT_BG" line)
              (setq named (caddr (split-string line "[[:space:]]+" t)))))
          (unless named
            (push (format "the palette of the %s theme defines no SUBJECT_BG" name)
                  yeah-subject--failures))
          (when named
            (unless (string= (yeah-subject--downcase-hex named) value)
              (push (format "the palette of the %s theme defines the wash %S, and the stylesheet names %S"
                            name named value)
                    yeah-subject--failures)))))))

  ;; 3. the source of the machine carries the wash on the subject state,
  ;;    and the boundary hangs under it
  (let* ((path (expand-file-name "site/diagrams/state-machine.puml" root))
         (text (and (file-readable-p path) (yeah-subject--read path))))
    (unless text
      (message "subject: the source of the machine is not there: %s" path)
      (kill-emacs 2))
    (unless (string-match "awaiting-user-permission.*SUBJECT_BG" text)
      (push "the source of the machine carries the wash on no state: the subject where the person decides is not named"
            yeah-subject--failures))
    (unless (string-match "note bottom of awaiting_user_permission" text)
      (push "the boundary of the machine hangs under no subject: note bottom of awaiting_user_permission is not there"
            yeah-subject--failures)))
  ;; 4. the rendered picture of every theme draws the wash
  (dolist (theme '(("light" yeah-subject--light-value) ("dark" yeah-subject--dark-value)))
    (let* ((name (car theme))
           (value (symbol-value (cadr theme)))
           (path (expand-file-name (format "site/assets/diagrams/state-machine-%s.svg" name) root))
           (text (and (file-readable-p path) (yeah-subject--read path))))
      (unless text
        (push (format "the rendered picture of the %s theme is not there: %s" name path)
              yeah-subject--failures))
      (when text
        (unless (string-match-p (regexp-quote value) (downcase text))
          (push (format "the rendered picture of the %s theme draws no wash of the subject (%s)" name value)
                yeah-subject--failures)))))
  (if yeah-subject--failures
      (progn
        (dolist (failure (nreverse yeah-subject--failures))
          (message "subject: %s" failure))
        (kill-emacs 1))
    (message "subject: the machine names where the person decides -- the wash of both themes, the source and the rendered pictures agree")
    (kill-emacs 0)))

;;; check-the-machine-names-where-the-person-decides.el ends here
