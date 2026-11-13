;;; test-yeah-git.el --- ERT tests for yeah-git -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-git)
(require 'yeah-perm)
(require 'yeah-result)
(require 'yeah-tools)

(defmacro yeah-git-test--with-directory (variable &rest body)
  "Create a temporary directory as VARIABLE and run BODY."
  (declare (indent 1))
  `(let ((,variable (make-temp-file "yeah-git-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,variable t))))

(defun yeah-git-test--call (name args)
  "Call the tool NAME with ARGS and return its result.
The git tools are asynchronous, so the event loop is pumped until the
continuation answers."
  (let ((spec (cl-find name (yeah-git-tools)
                       :key (lambda (candidate) (plist-get candidate :name))
                       :test #'string=)))
    (should spec)
    (let ((cell (list nil)))
      (funcall (plist-get spec :handler)
               args
               (lambda (result) (setf (car cell) result)))
      (let ((deadline (+ (float-time) 30)))
        (while (and (null (car cell)) (< (float-time) deadline))
          (accept-process-output nil 0.05)))
      (or (car cell) (yeah-result-error "the tool never answered")))))

(defun yeah-git-test--refused-p (thunk)
  "Return non-nil when THUNK signals a user-error."
  (condition-case nil
      (funcall thunk)
    (user-error t)))

(ert-deftest yeah-git-tools-register-with-registry ()
  "All git tool specifications are accepted by the existing registry."
  (yeah-tools-reset-for-test)
  (unwind-protect
      (progn
        (dolist (name '("git_status" "git_diff" "git_commit"))
          (yeah-tools-unregister name))
        (dolist (spec (yeah-git-tools))
          (should (eq spec (yeah-tools-register spec)))
          (should (eq spec (yeah-tools-get (plist-get spec :name))))))
    (yeah-tools-reset-for-test)))

(ert-deftest yeah-git-tools-declare-their-inputs ()
  "The git tools declare their parameters and run asynchronously."
  (let ((specs (yeah-git-tools)))
    (should (equal (mapcar (lambda (spec) (plist-get spec :name)) specs)
                   '("git_status" "git_diff" "git_commit")))
    (dolist (spec specs)
      (should (eq t (plist-get spec :async)))
      (should (listp (plist-get spec :input))))
    (let ((commit (cl-find "git_commit" specs
                            :key (lambda (spec) (plist-get spec :name))
                            :test #'string=)))
      (should (equal (mapcar (lambda (param) (plist-get param :name))
                              (plist-get commit :input))
                     '("directory" "message" "files")))
      (should (eq 'exclusive (plist-get commit :concurrency))))))

(ert-deftest yeah-git-split-files-separates-commas-and-newlines ()
  "The paths of a commit are separated by commas and by newlines."
  (should (equal (yeah-git--split-files "a.el") '("a.el")))
  (should (equal (yeah-git--split-files "a.el, b.el") '("a.el" "b.el")))
  (should (equal (yeah-git--split-files "a.el\nb.el") '("a.el" "b.el")))
  (should (equal (yeah-git--split-files "a.el,\n b.el") '("a.el" "b.el")))
  (should (equal (yeah-git--split-files "") nil))
  (should (equal (yeah-git--split-files nil) nil))
  (should-error (yeah-git--split-files 42) :type 'user-error))

(ert-deftest yeah-git-commit-commands-stage-what-they-name ()
  "A commit with paths stages them; without paths it commits what is staged."
  (should (equal (yeah-git--commit-commands "the change" nil)
                 '(("--no-pager" "commit" "--no-gpg-sign" "-m" "the change"))))
  (should (equal (yeah-git--commit-commands "the change" '("a.el"))
                 '(("--no-pager" "add" "--" "a.el")
                   ("--no-pager" "commit" "--no-gpg-sign" "-m" "the change" "--"
                    "a.el")))))

(ert-deftest yeah-git-effect-denies-over-allows ()
  "A deny on any name of the project denies the commit."
  (let ((rules (list (yeah-perm-rule-make "git_commit" "/a" 'allow)
                     (yeah-perm-rule-make "git_commit" "/b" 'deny))))
    (should (eq (yeah-git--effect '("/a") rules) 'allow))
    (should (eq (yeah-git--effect '("/b") rules) 'deny))
    (should (eq (yeah-git--effect '("/a" "/b") rules) 'deny))
    (should (eq (yeah-git--effect '("/c") rules) 'ask))))

(ert-deftest yeah-git-authorize-needs-a-rule-that-allows-the-commit ()
  "The gate refuses without a rule and opens with one."
  (yeah-perm-rules-reset-for-test)
  (yeah-git-test--with-directory root
    (should (yeah-git-test--refused-p
             (lambda () (yeah-git--authorize root root))))
    (yeah-perm-rules-add (yeah-perm-rule-make "git_commit" "*" 'deny))
    (should (yeah-git-test--refused-p
             (lambda () (yeah-git--authorize root root))))
    (yeah-perm-rules-add (yeah-perm-rule-make "git_commit" "*" 'allow))
    (should-not (yeah-git-test--refused-p
                 (lambda () (yeah-git--authorize root root))))
    (should (eq (yeah-git--effect (list root) (yeah-perm-rules-list)) 'allow)))
  (yeah-perm-rules-reset-for-test))

(ert-deftest yeah-git-commit-refuses-without-a-rule-and-writes-nothing ()
  "The commit tool refuses without a rule and leaves the project alone."
  (yeah-perm-rules-reset-for-test)
  (yeah-git-test--with-directory root
    (let ((result (yeah-git-test--call "git_commit"
                                       (list root "the change" "a.el"))))
      (should-not (plist-get result :ok))
      (should (string-match-p "rules" (plist-get result :error)))
      ;; the gate is before the subprocess: the project was never touched
      (should-not (file-directory-p (expand-file-name ".git" root)))))
  (yeah-perm-rules-reset-for-test))

(ert-deftest yeah-git-tools-report-a-directory-that-is-not-there ()
  "A project directory that does not exist is a structured failure."
  (yeah-git-test--with-directory root
    (let ((result (yeah-git-test--call
                   "git_status" (list (expand-file-name "missing" root)))))
      (should-not (plist-get result :ok))
      (should (stringp (plist-get result :error))))))

(ert-deftest yeah-git-status-in-a-project-that-is-not-a-repository ()
  "A directory that is not a repository is a failure, not a false success."
  (yeah-git-test--with-directory root
    (let ((result (yeah-git-test--call "git_status" (list root))))
      (should-not (plist-get result :ok))
      (should (stringp (plist-get result :error)))
      (should (plist-get result :metadata)))))

(provide 'test-yeah-git)
;;; test-yeah-git.el ends here
