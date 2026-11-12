;;; check-product-installs.el --- product entry and bootstrap canary -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Verify the package entry point and bootstrap text without installing
;; anything or touching the network.  The bootstrap remains an explicit user
;; action; this check only proves that the documented path is present.

;;; Code:

(require 'yeah)

(let ((failures nil))
  (unless (fboundp 'yeah)
    (push "M-x yeah is not available" failures))
  (unless (fboundp 'yeah-doctor)
    (push "M-x yeah-doctor is not available" failures))
  (unless (fboundp 'yeah-ask)
    (push "M-x yeah-ask is not available" failures))
  (with-temp-buffer
    (insert-file-contents "yeah.el")
    (goto-char (point-min))
    (unless (re-search-forward "Package-Requires:.*emacs.*30\\.2.*gptel.*0\\.9\\.9\\.5" nil t)
      (push "the package does not declare supported Emacs/gptel versions" failures)))
  (with-temp-buffer
    (insert-file-contents "install/yeah-bootstrap.el")
    (goto-char (point-min))
    (dolist (required '("melpa.org/packages" "package-vc-install"
                        "11111000000/yeah.git" "M-x yeah-doctor"))
      (unless (search-forward required nil t)
        (push (format "bootstrap is missing %s" required) failures)))
    (when (or (search-forward "mathc" nil t)
              (progn (goto-char (point-min)) (search-forward "nix " nil t)))
      (push "bootstrap depends on development tooling" failures)))
  (dolist (failure failures)
    (message "product install: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-product-installs.el ends here
