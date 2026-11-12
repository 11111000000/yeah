;;; yeah-bootstrap.el --- install Yeah on a clean Emacs -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; Install with:
;;   emacs -Q --batch -l install/yeah-bootstrap.el
;;
;; The script installs gptel from MELPA when absent and installs Yeah from the
;; pinned repository URL with package-vc.  No API key, Nix, mathc or other
;; development tool is required or printed.

;;; Code:

(require 'package)
(require 'package-vc)

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

(unless (package-installed-p 'gptel)
  (package-refresh-contents)
  (package-install 'gptel))

(unless (package-installed-p 'yeah)
  (package-vc-install "https://github.com/11111000000/yeah.git"
                      nil nil 'yeah))

(message "Yeah installed. Run M-x yeah-doctor, configure gptel, then M-x yeah.")

;;; yeah-bootstrap.el ends here
