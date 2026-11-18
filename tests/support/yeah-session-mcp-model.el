;;; yeah-session-mcp-model.el --- the fake model of the checks of the MCP servers -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the MCP servers of a session needs a model that calls a tool
;; of a server: the tools of the servers the client names have to reach the
;; model, and the model has to use one of them.  The model of this file is a
;; FAKE.
;;
;; The model finds its tool among the tools of the run: the registry of the
;; run is what the model sees, and a tool of an MCP server is in it exactly
;; when the tools of the server reached the model.  The model then calls that
;; tool and writes what it answered into the file the prompt names.  The
;; answer of the server is the only thing that can be in that file, because
;; the model does not know it.
;;
;; The file is loaded, not required: it defines the transport of the model
;; and the check names it.  The server process of the check loads it too, so
;; that the check and the server run the same model.

;;; Code:

(require 'yeah-tools)

(defconst yeah-session-mcp-model--prompt-regexp
  "the answer of the MCP tool goes to the file \\([^ \t]+\\); call the tool with the text \\([^ \t]+\\)"
  "The regexp that names the file of the answer and the text of the call.")

(defun yeah-session-mcp-model--finish ()
  "Return the answer that ends the run of the fake model.
The answer is a call of the `finish' tool: a supervised run does not end
with words (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list "the model of the check is done")
              (lambda (_value) nil))))

(defun yeah-session-mcp-model--tool ()
  "Return the name of the tool of the MCP server that the run offers.
The tools of a server of a session are named `mcp--<server>--<tool>'; a
run that offers none of them is a run whose model cannot use the server."
  (seq-find (lambda (name) (string-prefix-p "mcp--" name))
            (yeah-tools-names)))

(defun yeah-session-mcp-model--write (file name value)
  "Write the name NAME of the tool and its answer VALUE into the file FILE."
  (with-temp-file file
    (insert (format "tool: %s\nanswer: %s\n" name value))))

(defun yeah-session-mcp-model-transport (prompt callback)
  "Call the tool of the MCP server and end the run.
PROMPT names the file of the answer and the text of the call; CALLBACK
takes the answer in the shape gptel uses."
  (let* ((match (string-match yeah-session-mcp-model--prompt-regexp prompt))
         (file (and match (match-string 1 prompt)))
         (text (and match (match-string 2 prompt)))
         (name (yeah-session-mcp-model--tool)))
    (if (and file text name)
        (funcall callback
                 (list 'tool-call
                       (list (list :name name)
                             (list text)
                             (lambda (value)
                               (yeah-session-mcp-model--write file name value)
                               (funcall callback (yeah-session-mcp-model--finish))))))
      ;; The tool of the server did not reach the model.  The file says so,
      ;; and the check reads it and fails by its own assertion.
      (when file
        (yeah-session-mcp-model--write
         file "none" "the tool of the server did not reach the model"))
      (funcall callback (yeah-session-mcp-model--finish)))))

(provide 'yeah-session-mcp-model)
;;; yeah-session-mcp-model.el ends here
