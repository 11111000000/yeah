;;; yeah-org.el --- the session as an Org file -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; A session is a journal, and a journal is a file that only Yeah reads.
;; The person who lives in Emacs reads Org.  This module writes a session
;; as an Org file: one heading per event, the fields of the event as
;; properties, and the text of the event in a block that cannot be
;; confused with Org syntax.
;;
;; The export is a projection: nothing is lost from the journal, and
;; nothing is added to it.  The Org file is for the person.

;;; Code:

(require 'cl-lib)
(require 'yeah-session)

(defgroup yeah-org nil
  "Yeah session export to Org."
  :group 'yeah)

(defconst yeah-org--block-begin "#+BEGIN_example"
  "The beginning of the block that carries the text of an event.")

(defconst yeah-org--block-end "#+END_example"
  "The end of the block that carries the text of an event.")

(defun yeah-org--escape (text)
  "Return TEXT in a block that Org cannot read as anything else."
  (concat yeah-org--block-begin "\n"
          (or text "")
          "\n"
          yeah-org--block-end "\n"))

(defun yeah-org--property-name (key)
  "Return the Org name of the property KEY.
A keyword carries its colon in its name in Emacs 30, and the colon is
not part of an Org property name."
  (let ((name (symbol-name key)))
    (upcase (if (and (> (length name) 0) (eq (aref name 0) ?:))
                 (substring name 1)
               name))))

(defun yeah-org--properties (record)
  "Return the Org properties of the RECORD."
  (let ((fields (yeah-session-record-fields record))
        (properties nil))
    (while fields
      (let ((key (car fields))
            (value (cadr fields)))
        (setq properties
              (concat properties
                      (format ":%s: %s\n"
                              (yeah-org--property-name key)
                              (if (or (null value) (eq value t))
                                  (if (eq value t) "t" "")
                                (format "%s" value))))))
      (setq fields (cddr fields)))
    (if (string-empty-p properties)
        ""
      (concat ":PROPERTIES:\n" properties ":END:\n"))))

(defun yeah-org--event (record)
  "Return the Org text of the journal RECORD."
  (let ((type (or (plist-get record :type) "event"))
        (payload (plist-get record :payload)))
    (concat (format "* %s\n" type)
            (yeah-org--properties record)
            (if (or (null payload) (and (stringp payload)
                                        (string-empty-p payload)))
                ""
              (yeah-org--escape (if (stringp payload)
                                    payload
                                  (format "%S" payload)))))))

(defun yeah-org-session-text (session)
  "Return the Org text of SESSION."
  (let* ((id (plist-get session :id))
         (records (yeah-session-records session)))
    (concat (format "#+TITLE: Yeah session %s\n" (or id "unknown"))
            "#+STARTUP: overview\n\n"
            (mapconcat #'yeah-org--event
                       (seq-remove (lambda (record)
                                     (equal (plist-get record :type) "header"))
                                     records)
                       ""))))

(defun yeah-org-export-session (session &optional file)
  "Return the Org text of SESSION and write it to FILE when FILE is given."
  (let ((text (yeah-org-session-text session)))
    (when file
      (let ((coding-system-for-write 'utf-8-unix))
        (with-temp-file file
          (insert text))))
    text))

(defun yeah-org-export-file (session directory)
  "Write SESSION as an Org file in DIRECTORY and return the path."
  (let ((file (expand-file-name (format "%s.org" (or (plist-get session :id)
                                                     "session"))
                                directory)))
    (make-directory directory t)
    (yeah-org-export-session session file)
    file))

(provide 'yeah-org)
;;; yeah-org.el ends here
