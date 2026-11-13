;;; test-yeah-input.el --- ERT tests for yeah-input -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Queue behavior, persistence, limits and corrupt-file handling.

;;; Code:

(require 'ert)
(require 'yeah-input)

(defmacro yeah-input-test--with-temp-directory (directory &rest body)
  "Run BODY with `yeah-input-directory' bound to a temporary DIRECTORY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,directory (file-name-as-directory
                      (make-temp-file "yeah-input-test-" t))))
     (unwind-protect
         (let ((yeah-input-directory ,directory))
           ,@body)
       (ignore-errors (delete-directory ,directory t)))))

(defun yeah-input-test--input (prompt &optional kind id)
  "Return a valid input with PROMPT, KIND and optional ID."
  (append (list :kind (or kind 'ask) :prompt prompt
                :frozen '(:model "test" :instructions ("frozen")))
          (when id
            (list :id id :created-at "2026-11-11T00:00:00+0000"))))

(defun yeah-input-test--file-contents (path)
  "Return PATH's contents as a string."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(ert-deftest yeah-input-fifo-persists-across-calls-and-session-objects ()
  (yeah-input-test--with-temp-directory directory
    (let* ((session '(:id "fifo/../λ"))
           (first (yeah-input-enqueue
                   session (yeah-input-test--input "first")))
           (second (yeah-input-enqueue
                    session (yeah-input-test--input "second")))
           (fresh-session (list :id (plist-get session :id)))
           (path (yeah-input--path (plist-get session :id))))
      (should (string-match-p "\\`input-[0-9a-f]\\{64\\}\\'"
                              (plist-get first :id)))
      (should (stringp (plist-get first :created-at)))
      (should (= 2 (yeah-input-count fresh-session)))
      (should (equal (mapcar (lambda (input) (plist-get input :prompt))
                             (yeah-input-pending fresh-session))
                     '("first" "second")))
      (should (file-exists-p path))
      (should (string=
               (file-name-nondirectory path)
               (concat (secure-hash
                        'sha256
                        (encode-coding-string (plist-get session :id) 'utf-8))
                       ".eld")))
      (should (= #o700 (file-modes directory)))
      (should (= #o600 (file-modes path)))
      (should (equal first (yeah-input-pop fresh-session)))
      (should (equal second (yeah-input-pop fresh-session)))
      (should-not (yeah-input-pop fresh-session))
      (should (= 0 (yeah-input-count fresh-session)))
      (should-not (yeah-input-pending fresh-session))
      (should (file-exists-p path))
      (should (equal "nil\n" (yeah-input-test--file-contents path))))))

(ert-deftest yeah-input-steering-preserves-frozen-configuration ()
  (yeah-input-test--with-temp-directory _directory
    (let* ((session '(:id "steering"))
           (frozen '(:backend "local" :model "λ"
                     :instructions ("first" "second")
                     :editor (:buffer "demo.el" :tick 7)
                     :options [1 2 3]))
           (input (list :kind 'steering :prompt "Use the other approach"
                        :frozen frozen :id "steering-1"
                        :created-at "2026-11-11T01:02:03+0000"))
           (normalized (yeah-input-enqueue session input)))
      (should (equal normalized input))
      (should (eq 'steering (plist-get normalized :kind)))
      (should (equal frozen (plist-get normalized :frozen)))
      (should (equal (list input) (yeah-input-pending session))))))

(ert-deftest yeah-input-withdraw-removes-only-the-requested-id ()
  (yeah-input-test--with-temp-directory _directory
    (let ((session '(:id "withdraw")))
      (yeah-input-enqueue session (yeah-input-test--input "one" nil "one"))
      (yeah-input-enqueue session (yeah-input-test--input "two" nil "two"))
      (yeah-input-enqueue session (yeah-input-test--input "three" nil "three"))
      (let ((withdrawn (yeah-input-withdraw session "two")))
        (should withdrawn)
        (should (equal "two" (plist-get withdrawn :id)))
        (should (equal "two" (plist-get withdrawn :prompt))))
      (should (equal '("one" "three")
                     (mapcar (lambda (input) (plist-get input :id))
                             (yeah-input-pending (list :id "withdraw")))))
      (should-not (yeah-input-withdraw session "absent"))
      (should (= 2 (yeah-input-count session)))
      (should (equal "one" (plist-get (yeah-input-withdraw session "one")
                                      :id)))
      (should (equal "three" (plist-get (yeah-input-pop session) :id)))
      (should-not (yeah-input-pending session)))))

(ert-deftest yeah-input-entry-overflow-rejects-without-eviction ()
  (yeah-input-test--with-temp-directory _directory
    (let ((session '(:id "entry-limit")))
      (dotimes (index 8)
        (yeah-input-enqueue
         session (yeah-input-test--input (format "input-%d" index))))
      (let* ((path (yeah-input--path "entry-limit"))
             (before (yeah-input-test--file-contents path)))
        (should-error
         (yeah-input-enqueue session (yeah-input-test--input "ninth"))
         :type 'user-error)
        (should (= 8 (yeah-input-count session)))
        (should (equal before (yeah-input-test--file-contents path)))
        (should (equal (mapcar (lambda (input) (plist-get input :prompt))
                               (yeah-input-pending session))
                       '("input-0" "input-1" "input-2" "input-3"
                         "input-4" "input-5" "input-6" "input-7")))))))

(ert-deftest yeah-input-byte-overflow-rejects-without-eviction ()
  (yeah-input-test--with-temp-directory _directory
    (let ((session '(:id "byte-limit"))
          (prompt (make-string 70000 ?λ)))
      (yeah-input-enqueue session (yeah-input-test--input prompt))
      (let* ((path (yeah-input--path "byte-limit"))
             (before (yeah-input-test--file-contents path)))
        (should-error
         (yeah-input-enqueue session (yeah-input-test--input prompt))
         :type 'user-error)
        (should (= 1 (yeah-input-count session)))
        (should (equal before (yeah-input-test--file-contents path)))
        (should (equal prompt
                       (plist-get (car (yeah-input-pending session))
                                  :prompt)))))))

(ert-deftest yeah-input-corrupt-shape-signals-without-erasing-file ()
  (yeah-input-test--with-temp-directory directory
    (let* ((session '(:id "corrupt"))
           (path (yeah-input--path "corrupt"))
           (contents "(:not-a-queue)\n"))
      (make-directory directory t)
      (with-temp-file path
        (insert contents))
      (should-error (yeah-input-pending session) :type 'user-error)
      (should-error (yeah-input-pop session) :type 'user-error)
      (should-error
       (yeah-input-enqueue session (yeah-input-test--input "new"))
       :type 'user-error)
      (should (equal contents (yeah-input-test--file-contents path))))))

(ert-deftest yeah-input-reading-never-evaluates-lisp ()
  (yeah-input-test--with-temp-directory directory
    (let* ((session '(:id "read-eval"))
           (path (yeah-input--path "read-eval"))
           (marker (expand-file-name "executed" directory))
           (contents (format
                      "#.(with-temp-file %S (insert \"executed\"))"
                      marker)))
      (make-directory directory t)
      (with-temp-file path
        (insert contents))
      (should-error (yeah-input-pending session) :type 'user-error)
      (should-not (file-exists-p marker))
      (should (equal contents (yeah-input-test--file-contents path))))))

(ert-deftest yeah-input-rejects-invalid-inputs ()
  (yeah-input-test--with-temp-directory _directory
    (let ((session '(:id "validation")))
      (dolist (input
               (list (list :kind 'other :prompt "bad" :frozen nil)
                     (list :kind 'ask :prompt 42 :frozen nil)
                     (list :kind 'ask :prompt "missing frozen")
                     (list :kind 'ask :prompt "bad frozen" :frozen '(:model))
                     (list :kind 'ask :prompt "unserializable"
                           :frozen (list :buffer (current-buffer)))))
        (should-error (yeah-input-enqueue session input) :type 'user-error))
      (should (= 0 (yeah-input-count session))))))

(provide 'test-yeah-input)
;;; test-yeah-input.el ends here
