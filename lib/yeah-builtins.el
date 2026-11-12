;;; yeah-builtins.el --- built-in tool specifications -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; One registration point for file, editing, process and Emacs-native tools.
;; Modules provide specifications; `yeah-tools' owns registration and dispatch.

;;; Code:

(require 'yeah-files)
(require 'yeah-edit)
(require 'yeah-process)
(require 'yeah-emacs)

(defun yeah-builtins-specs ()
  "Return all built-in tool specifications in stable registration order."
  (append (yeah-files-tools)
          (yeah-edit-tools)
          (yeah-process-tools)
          (yeah-emacs-tools)))

(provide 'yeah-builtins)
;;; yeah-builtins.el ends here
