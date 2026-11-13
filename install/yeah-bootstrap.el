;;; yeah-bootstrap.el --- install Yeah on a clean Emacs -*- lexical-binding: t; no-byte-compile: t -*-
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

;; gptel is installed from a pinned revision, not from the archive: the
;; current MELPA snapshot does not byte-compile cleanly on a clean Emacs,
;; and Yeah supports a specific gptel contract (see
;; `yeah-gptel--supported-versions' in lib/yeah-gptel.el).
(defconst yeah-bootstrap--gptel-revision "v0.9.9.6"
  "The gptel revision this bootstrap installs.")

(unless (package-installed-p 'gptel)
  (package-refresh-contents)
  (package-vc-install
   (list 'gptel :url "https://github.com/karthink/gptel.git"
         :branch yeah-bootstrap--gptel-revision)))

(unless (package-installed-p 'yeah)
  (package-vc-install
   '(yeah :url "https://github.com/11111000000/yeah.git" :lisp-dir "lib")))

(message "Yeah installed. Run M-x yeah-doctor, configure gptel, then M-x yeah.")

;;; yeah-bootstrap.el ends here
