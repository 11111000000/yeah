;;; scenario.el --- the scripted model of the placement check -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The model of the placement check is a FAKE: a transport that asks for one
;; tool and answers with text once the tool has run.  The same file is
;; loaded by the check and by the child processes it starts, so that the
;; three placements do the same work.
;;
;; The file is loaded, not required: it defines the transport and registers
;; the tool it asks for.

;;; Code:

(require 'yeah-tools)

(defun yeah-scenario--probe (path)
  "Return the text the probe saw at PATH."
  (format "probe saw %s" path))

(defun yeah-scenario-register ()
  "Register the probe tool, idempotently."
  (unless (yeah-tools-get "probe")
    (yeah-tools-register
     (list :name "probe"
           :description "A tool that records that it ran."
           :input (list (list :name "path" :type 'string))
           :handler #'yeah-scenario--probe)))
  (yeah-tools-get "probe"))

(defun yeah-scenario-transport (prompt callback)
  "Ask for the probe, then answer with what the probe saw.

PROMPT is what the turn asked; CALLBACK takes the answer in the shape
gptel uses."
  (funcall callback
           (list 'tool-call
                 (list (list :name "probe")
                       (list "/tmp/probe-target")
                       (lambda (value)
                         (funcall callback (format "done: %s" value)))))))

(yeah-scenario-register)

(provide 'yeah-scenario)
;;; scenario.el ends here
