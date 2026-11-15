;;; render-interface.el --- render one view of the interface for the picture -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; One view of the interface, drawn in a terminal and left on the screen.
;; The picture check runs this inside a terminal under a virtual frame
;; server, photographs the screen and compares the pictures.
;;
;; The environment says which view to draw and where to say that the
;; screen is ready:
;;
;;   YEAH_PIXEL_VIEW   journal, empty or approval
;;   YEAH_PIXEL_READY  the file to write when the screen is ready
;;   YEAH_PIXEL_HOLD   how long to leave the view on the screen, in seconds

;;; Code:

(require 'yeah-approval)
(require 'yeah-approval-ui)
(require 'yeah-journal)
(require 'yeah-ui)
(require 'yeah-ui-fixtures
         (expand-file-name "tests/support/yeah-ui-fixtures.el"))

(defun render-interface--say (text)
  "Say TEXT where the person running the check can read it."
  (princ (concat text "\n") #'external)
  (flush-output #'external))

(defun render-interface--journal ()
  "Draw the journal of the fixture in the current buffer."
  (let* ((view (yeah-ui-view (yeah-ui-fixture-parallel)))
         (buffer (get-buffer-create "*Yeah picture journal*")))
    (with-current-buffer buffer
      (yeah-journal-mode)
      (set-buffer-modified-p nil))
    (switch-to-buffer buffer)
    (let ((journal (yeah-journal--make :buffer buffer :driver nil)))
      (yeah-journal-full-render journal view))
    (with-current-buffer buffer
      (set-buffer-modified-p nil))))

(defun render-interface--empty ()
  "Leave the frame of the journal without the interface on the screen.
The buffer is the journal's own buffer with its content taken away, so the
mode line and the frame stay exactly as they were: what the two pictures
differ by is the interface and nothing else."
  (render-interface--journal)
  (let ((buffer (get-buffer-create "*Yeah picture journal*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer))
      (goto-char (point-min))
      (set-buffer-modified-p nil))
    (switch-to-buffer buffer)))

(defun render-interface--approval ()
  "Draw the approval view in the current buffer."
  (let* ((request (yeah-approval-request "edit" "/tmp/picture-example.el" nil "call-picture"))
         (buffer (get-buffer-create "*Yeah picture approval*")))
    (with-current-buffer buffer
      (yeah-approval-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (yeah-approval--render request)))
      (goto-char (point-min))
      (set-buffer-modified-p nil))
    (switch-to-buffer buffer)))

(defun render-interface--ready (marker)
  "Say that the screen is ready by writing MARKER."
  (when marker
    (with-temp-file marker
      (insert "ready\n"))))

(defun render-interface--main ()
  "Draw the view the environment asks for and leave it on the screen."
  (let ((view (getenv "YEAH_PIXEL_VIEW"))
        (marker (getenv "YEAH_PIXEL_READY"))
        (hold (or (getenv "YEAH_PIXEL_HOLD") "25")))
    (unless view
      (error "render-interface: YEAH_PIXEL_VIEW is not set"))
    (setq confirm-exit nil)
    (cond
     ((string= view "journal") (render-interface--journal))
     ((string= view "empty") (render-interface--empty))
     ((string= view "approval") (render-interface--approval))
     (t (error "render-interface: unknown view `%s'" view)))
    (redisplay t)
    (sit-for 0.5)
    (render-interface--ready marker)
    ;; The picture is taken while the view is on the screen.
    (sleep-for (string-to-number hold))
    (kill-emacs 0)))

;; A terminal Emacs stays alive when a file fails to load, so the failure has
;; to leave Emacs by itself: a check that hangs is a check that cannot fail.
(condition-case err
    (render-interface--main)
  (error
   (render-interface--say (error-message-string err))
   (kill-emacs 1)))

;;; render-interface.el ends here
