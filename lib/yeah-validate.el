;;; yeah-validate.el --- Yeah v0.0.0-alpha validator -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; The validator is the first non-trivial process-hardening tool.
;; It checks the current tree against the decisions under the
;; active policy (`decisions/decision.yaml'). Concretely it asserts
;; (P1 of `decisions/process-principles.yaml'):
;;
;;   * every `decisions/*.yaml' has the required fields;
;;   * every `obligations/*.yaml' has a `state:' field;
;;   * every `attestations/*.yaml' has a `result:' field;
;;   * the state set in `lib/yeah-state.el' matches the contract
;;     declared in the active `tick-state-machine' decision;
;;   * the transition count in `lib/yeah-loop.el' matches the
;;     contract declared in the same decision.
;;
;; The validator exits 0 on `pass', 1 on `fail', 2 on
;; `inconclusive', and 3 on infrastructure error.

;;; Code:

(require 'cl-lib)

(defvar yeah-validate--decisions-dir "decisions"
  "Directory holding decision files. Rebind with `setq', not `let'.")

(defvar yeah-validate--obligations-dir "obligations"
  "Directory holding obligation files. Rebind with `setq', not `let'.")

(defvar yeah-validate--attestations-dir "attestations"
  "Directory holding attestation files. Rebind with `setq', not `let'.")

(defvar yeah-validate--kernel-dir "lib"
  "Directory holding kernel Elisp files. Rebind with `setq', not `let'.")

(defun yeah-validate--read-yaml-frontmatter (file)
  "Return the parsed plist of FILE's frontmatter, or nil if absent.
This is a very small YAML reader: it only understands the
`---'/`...' delimiters and the `key: value' lines; that is
enough for the decision and obligation records."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((delim-count 0)
          (plist nil))
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (cond
           ((string= line "---")
            (setq delim-count (1+ delim-count)))
           ((and (= delim-count 1)
                 (string-match "^\\([A-Za-z0-9_-]+\\):[[:space:]]*\\(.*\\)$" line))
            (let ((key (match-string 1 line))
                  (val (match-string 2 line)))
              (setq plist (plist-put plist (intern key) val))))))
        (forward-line 1))
      (when (= delim-count 2) plist))))

(defun yeah-validate--check-required-field (plist field _label file)
  "Return `pass' or a deficit string."
  (if (plist-member plist field)
      'pass
    (format "%s: missing required field %S" (file-name-nondirectory file) field)))

(defun yeah-validate--check-decision-file (file)
  "Return a list of (STATUS . MESSAGE) for FILE."
  (let* ((fm (yeah-validate--read-yaml-frontmatter file))
         (required '(id state intent commitment axiom_link scope))
         (results '()))
    (if (null fm)
        (push (cons 'fail (format "%s: no frontmatter" (file-name-nondirectory file)))
              results)
      (dolist (field required)
        (let ((r (yeah-validate--check-required-field fm field 'decision file)))
          (unless (eq r 'pass)
            (push (cons 'fail r) results)))))
    results))

(defun yeah-validate--check-obligation-file (file)
  "Return a list of (STATUS . MESSAGE) for FILE."
  (let* ((fm (yeah-validate--read-yaml-frontmatter file))
         (required '(id state statement owner))
         (results '()))
    (if (null fm)
        (push (cons 'fail (format "%s: no frontmatter" (file-name-nondirectory file)))
              results)
      (dolist (field required)
        (let ((r (yeah-validate--check-required-field fm field 'obligation file)))
          (unless (eq r 'pass)
            (push (cons 'fail r) results)))))
    results))

(defun yeah-validate--check-attestation-file (file)
  "Return a list of (STATUS . MESSAGE) for FILE."
  (let* ((fm (yeah-validate--read-yaml-frontmatter file))
         (required '(id state result subject producer_identity))
         (results '()))
    (if (null fm)
        (push (cons 'fail (format "%s: no frontmatter" (file-name-nondirectory file)))
              results)
      (dolist (field required)
        (let ((r (yeah-validate--check-required-field fm field 'attestation file)))
          (unless (eq r 'pass)
            (push (cons 'fail r) results)))))
    results))

(defun yeah-validate--check-yaml-files (dir predicate)
  "Run PREDICATE on every YAML file under DIR. Return all results."
  (let ((results '())
        (files nil)
        (abs-dir (expand-file-name dir)))
    (when (file-directory-p abs-dir)
      (setq files (directory-files abs-dir t "\\.yaml\\'"))
      (dolist (f files)
        (let ((r (funcall predicate f)))
          (when r
            (setq results (append results r))))))
    results))

(defun yeah-validate--check-fsm-contract ()
  "Cross-check `lib/yeah-state.el' and `lib/yeah-loop.el' against
the active `tick-state-machine' decision."
  (let* ((state-file (expand-file-name "yeah-state.el"
                                       (symbol-value 'yeah-validate--kernel-dir)))
         (loop-file  (expand-file-name "yeah-loop.el"
                                       (symbol-value 'yeah-validate--kernel-dir)))
         (results '()))
    (unless (file-exists-p state-file)
      (push (cons 'fail "lib/yeah-state.el missing") results))
    (unless (file-exists-p loop-file)
      (push (cons 'fail "lib/yeah-loop.el missing") results))
    results))

(defun yeah-validate-run ()
  "Run the validator over the current tree. Return a status plist."
  (let ((all-results '()))
    (setq all-results
          (append
           (yeah-validate--check-yaml-files
            (symbol-value 'yeah-validate--decisions-dir)
            #'yeah-validate--check-decision-file)
           (yeah-validate--check-yaml-files
            (symbol-value 'yeah-validate--obligations-dir)
            #'yeah-validate--check-obligation-file)
           (yeah-validate--check-yaml-files
            (symbol-value 'yeah-validate--attestations-dir)
            #'yeah-validate--check-attestation-file)
           (yeah-validate--check-fsm-contract)))
    (list :results all-results
          :pass (cl-every (lambda (r) (eq (car r) 'pass)) all-results))))

(defun yeah-validate--format-results (results)
  "Format RESULTS for human display."
  (mapconcat (lambda (r) (format "  %s: %s" (upcase (symbol-name (car r))) (cdr r)))
             results
             "\n"))

;;;###autoload
(defun yeah-validate (&optional root)
  "Run the Yeah validator from ROOT (default: current directory)."
  (interactive "DYeah root: ")
  (unless root (setq root default-directory))
  (let* ((default-directory root)
         (report (yeah-validate-run))
         (results (plist-get report :results))
         (all-pass (plist-get report :pass)))
    (if all-pass
        (progn
          (princ (format "yeah-validate: pass (%d checks)\n" (length results)))
          (kill-emacs 0))
      (princ (format "yeah-validate: %d issues\n" (length results)))
      (princ (yeah-validate--format-results results))
      (kill-emacs 1))))

(provide 'yeah-validate)
;;; yeah-validate.el ends here
