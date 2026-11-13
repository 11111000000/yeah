;;; yeah-builtins.el --- built-in tool specifications -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; One registration point for file, editing, process, Emacs-native and task
;; list tools.  Modules provide specifications; `yeah-tools' owns registration
;; and dispatch.

;;; Code:

(require 'yeah-files)
(require 'yeah-edit)
(require 'yeah-process)
(require 'yeah-emacs)
(require 'yeah-git)
(require 'yeah-todo)

(defun yeah-builtins-specs ()
  "Return all built-in tool specifications in stable registration order."
  (append (yeah-files-tools)
          (yeah-edit-tools)
          (yeah-process-tools)
          (yeah-emacs-tools)
          (yeah-todo-tools)
          (yeah-git-tools)
          (list (list :name "finish"
                      :description
                      "End the run. Call this only when the task is done and its work is verified: the run stops with your summary. A run that has not touched anything yet has nothing to finish."
                      :input (list (list :name "summary" :type 'string))
                      :handler (lambda (summary) summary)
                      :concurrency 'exclusive))))

(provide 'yeah-builtins)
;;; yeah-builtins.el ends here
