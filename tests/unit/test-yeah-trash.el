;;; test-yeah-trash.el --- tests of the trash and of the guard -*- lexical-binding: t; no-byte-compile: t -*-

;;; Commentary:
;; The trash of the agent and the guard of the shell of the agent: a
;; deletion is a move that can be taken back, and the commands that
;; destroy in place are refused by name.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-trash)
(require 'yeah-shell-guard)

(defmacro yeah-trash-test--with-home (&rest body)
  "Run BODY with the data of the user in a directory of its own.
The trash of the agent lives in the data of the user, and a test that
wrote into the trash of the person would leave its rubbish there."
  (declare (indent 0) (debug t))
  `(let ((XDG_DATA_HOME (file-name-as-directory (make-temp-file "yeah-trash-home" t)))
         (home (getenv "HOME")))
     (unwind-protect
         (progn
           (setenv "XDG_DATA_HOME" XDG_DATA_HOME)
           (let ((yeah-data-home (expand-file-name "yeah/" XDG_DATA_HOME)))
             ,@body))
       (setenv "XDG_DATA_HOME" (or home ""))
       (delete-directory XDG_DATA_HOME t))))

(ert-deftest yeah-trash-a-file-moves-into-the-trash-and-comes-back ()
  "A file that is thrown away keeps its content and can be restored."
  (yeah-trash-test--with-home
    (let* ((directory (file-name-as-directory (make-temp-file "yeah-trash-work" t)))
           (file (expand-file-name "victim.txt" directory)))
      (unwind-protect
          (progn
            (with-temp-file file (insert "the content"))
            (let ((info (yeah-trash-move file)))
              (should-not (file-exists-p file))
              (should (file-exists-p info))
              (should (string-suffix-p ".trashinfo" info))
              (let ((stored (expand-file-name "victim.txt"
                                              (yeah-trash--files-directory))))
                (should (file-exists-p stored))
                (with-temp-buffer
                  (insert-file-contents stored)
                  (should (equal "the content" (buffer-string)))))
              (should (equal file (yeah-trash-restore info)))
              (should (file-exists-p file))
              (with-temp-buffer
                (insert-file-contents file)
                (should (equal "the content" (buffer-string))))))
        (delete-directory directory t)))))

(ert-deftest yeah-trash-a-directory-moves-with-its-content ()
  "A directory that is thrown away goes into the trash with what is in it."
  (yeah-trash-test--with-home
    (let* ((directory (file-name-as-directory (make-temp-file "yeah-trash-work" t)))
           (tree (expand-file-name "tree" directory)))
      (unwind-protect
          (progn
            (make-directory tree)
            (with-temp-file (expand-file-name "inner.txt" tree) (insert "inner"))
            (yeah-trash-move tree)
            (should-not (file-exists-p tree))
            (should (file-exists-p (expand-file-name "inner.txt"
                                                    (expand-file-name "tree"
                                                                       (yeah-trash--files-directory))))))
        (delete-directory directory t)))))

(ert-deftest yeah-trash-two-files-of-one-name-get-two-entries ()
  "The trash does not lose a path because a path of the same name is already there."
  (yeah-trash-test--with-home
    (let* ((first (file-name-as-directory (make-temp-file "yeah-trash-one" t)))
           (second (file-name-as-directory (make-temp-file "yeah-trash-two" t)))
           (one (expand-file-name "same.txt" first))
           (two (expand-file-name "same.txt" second)))
      (unwind-protect
          (progn
            (with-temp-file one (insert "one"))
            (with-temp-file two (insert "two"))
            (let ((info-one (yeah-trash-move one))
                  (info-two (yeah-trash-move two)))
              (should-not (equal info-one info-two))
              (should (file-exists-p info-one))
              (should (file-exists-p info-two))
              (yeah-trash-restore info-one)
              (yeah-trash-restore info-two)
              (should (equal "one" (with-temp-buffer (insert-file-contents one) (buffer-string))))
              (should (equal "two" (with-temp-buffer (insert-file-contents two) (buffer-string))))))
        (delete-directory first t)
        (delete-directory second t)))))

(ert-deftest yeah-trash-lists-what-it-holds ()
  "The trash names the entries it holds and where they came from."
  (yeah-trash-test--with-home
    (let* ((directory (file-name-as-directory (make-temp-file "yeah-trash-work" t)))
           (file (expand-file-name "listed.txt" directory)))
      (unwind-protect
          (progn
            (with-temp-file file (insert "listed"))
            (yeah-trash-move file)
            (let ((entries (yeah-trash-list)))
              (should (= 1 (length entries)))
              (should (equal file (plist-get (car entries) :path)))
              (should (file-exists-p (plist-get (car entries) :info)))))
        (delete-directory directory t)))))

(ert-deftest yeah-shell-guard-refuses-the-commands-that-destroy-in-place ()
  "The guard refuses the commands that cannot be taken back, by name."
  (dolist (command '("sudo rm -rf /tmp/x"
                      "/bin/rm -rf /tmp/x"
                      "find . -delete"
                      "shred -u secret"
                      "dd if=/dev/zero of=/dev/sda"
                      "mkfs.ext4 /dev/sdb1"
                      "git clean -fdx"
                      ":(){ :|:& };:"))
    (should (yeah-shell-guard--refusal command))
    (should-error (yeah-shell-guard-check command) :type 'user-error)))

(ert-deftest yeah-shell-guard-lets-the-ordinary-commands-through ()
  "The guard refuses nothing that the trash can keep."
  (dolist (command '("rm -rf build"
                      "git status"
                      "cargo build --release"
                      "ls -la"
                      "make test"))
    (should-not (yeah-shell-guard--refusal command))
    (should (equal command (yeah-shell-guard-check command)))))

(provide 'test-yeah-trash)
;;; test-yeah-trash.el ends here
