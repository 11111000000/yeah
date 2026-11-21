;;; check-the-client-reads-the-port-of-a-service-that-is-gone.el --- the client reads the port of a service that is gone -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify it under
;; the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The editor finds a service over TCP on a Windows-like host: the
;; service publishes the number of its port in a file next to its
;; socket, and the client reads that file.  The service removes the
;; file when it stops, so the file can be gone by the time the client
;; reads it.
;;
;; The reader of the file of the port asked for the file and read it
;; afterwards.  The file was there when it was asked for and gone when
;; it was read, and the read then died with `file-missing'.  The death
;; left the reader of the port, and with it the client: the client of
;; the editor fell on the filesystem where it had promised to wait for
;; a service that is not there yet.
;;
;; The reader of the port decides now: it answers nil when the port is
;; unavailable -- no file, a file that vanished between the look and the
;; read, a file that cannot be read, a directory in place of the file --
;; and it catches the error of the file and nothing else.  A reader that
;; hides every failure is a reader that is blind, and a blind reader
;; decides nothing.
;;
;; This check is the proof of that repair, and it must be able to fail:
;;
;;   1. the port of a service that is not there is nil, and no error is
;;      raised;
;;   2. the port of a service that stops while the client reads it is
;;      nil, and no error is raised -- the file vanishes between the
;;      look and the read, and the vanishing is made by the check and
;;      not waited for;
;;   3. a directory in place of the file of the port is nil, and no
;;      error is raised;
;;   4. a file of the port that cannot be read is nil, and no error is
;;      raised;
;;   5. a file of the port that holds text and not a port is nil;
;;   6. a file of the port that holds a port out of range is nil;
;;   7. a file of the port that holds a port is that port: the repair
;;      did not turn the reader into a reader that answers nil for
;;      everything;
;;   8. the reader hides the error of the file and nothing else: an
;;      error that is not an error of the file is raised and not
;;      swallowed;
;;   9. the client waits for a service that is not there and says that
;;      there is no service on it;
;;  10. the client waits for a service whose file of the port vanishes
;;      and says that there is no service on it -- it does not die on
;;      the file where it promised to wait;
;;  11. the stop of a service removes the file of the port, and the
;;      client reads nil afterwards: a service that is gone is an
;;      expected state and not an accident.
;;
;; The second, the third and the tenth are the ones that fail on the
;; code before the repair: that code raised the error of the file out
;; of the reading.  The seventh and the eighth keep the repair honest:
;; a reader that answers nil for every port and a reader that hides
;; every failure pass a check that asks nothing else.
;;
;; The vanishing is made by two advises in the environment of the check
;; itself.  The advise on `file-readable-p' deletes the file of the
;; port and answers t: the reader is told the file is there.  The
;; advise on `insert-file-contents' deletes it again and lets the real
;; read fail: the file is gone when the reader reads it, whatever the
;; reader does between the two.  The second advise alone would do, and
;; it keeps the stand honest for a reader that does not look for the
;; file before it reads it.
;;
;; Exit codes: 0 -- the reader decides; 1 -- it did not.

;;; Code:

(require 'cl-lib)
(require 'yeah-client)
(require 'yeah-service)

(defvar yeah-check--failures nil
  "The failures this check found.")

(defconst yeah-check--port 4242
  "The port the check publishes in the file of the port.")

(defun yeah-check--socket (directory)
  "Return the path of the socket of the service of the check in DIRECTORY."
  (expand-file-name "yeah-service-gone.sock" directory))

(defun yeah-check--write-port (file text)
  "Write TEXT into the file of the port FILE."
  (with-temp-file file
    (insert text))
  (set-file-modes file #o600)
  file)

(defun yeah-check--call (thunk)
  "Call THUNK and return a cons of the outcome and the answer.
The outcome is `ok' when the reader answered and `error' when it raised:
the error is kept, so a reader that dies is named and not hidden."
  (condition-case err
      (cons 'ok (funcall thunk))
    (error (cons 'error err))))

(defun yeah-check--error-text (err)
  "Return the text of the error ERR."
  (mapconcat #'identity (cdr err) " "))

(defun yeah-check--expect-nil (result what)
  "Assert that the reader answered nil for WHAT.
RESULT is the cons that `yeah-check--call' returns."
  (cond
   ((not (eq 'ok (car result)))
    (push (format "%s raised an error: %S" what (cdr result)) yeah-check--failures))
   ((not (null (cdr result)))
    (push (format "%s answered %S and not nil" what (cdr result)) yeah-check--failures))))

(defun yeah-check--vanishing-port (file thunk)
  "Call THUNK with the port file FILE vanishing between the look and the read.
The advise on `file-readable-p' deletes FILE and answers t: the reader
is told the file is there.  The advise on `insert-file-contents' deletes
it again and lets the real read fail: the file is gone when the reader
reads it, whatever the reader does between the two.

The answer is a cons of the outcome of THUNK -- the cons that
`yeah-check--call' returns -- and whether the reader reached the read."
  ;; The bindings are sequential on purpose: the advises are closures, and
  ;; a closure made in the init form of a `let' would close over the
  ;; `read' of the world and not over the one of this function.
  (let* ((read nil)
         (look (lambda (orig path &rest args)
                 (if (equal path file)
                     (progn
                       (ignore-errors (delete-file file))
                       t)
                   (apply orig path args))))
         (insert (lambda (orig path &rest args)
                   (if (equal path file)
                       (progn
                         (setq read t)
                         (ignore-errors (delete-file file))
                         (apply orig path args))
                     (apply orig path args)))))
    (advice-add 'file-readable-p :around look)
    (advice-add 'insert-file-contents :around insert)
    (unwind-protect
        (cons (yeah-check--call thunk) read)
      (advice-remove 'file-readable-p look)
      (advice-remove 'insert-file-contents insert))))

(let* ((directory (make-temp-file "yeah-client-port-check" t))
       (socket (yeah-check--socket directory))
       (port-file (yeah-client-port-file socket)))
  (unwind-protect
      (progn
        ;; 1. a service that is not there at all
        (yeah-check--expect-nil
         (yeah-check--call (lambda () (yeah-client--read-port socket)))
         "the port of a service that is not there")
        ;; 2. the file of the port vanishes between the look and the read
        (yeah-check--write-port port-file (number-to-string yeah-check--port))
        (let* ((outcome (yeah-check--vanishing-port
                         port-file
                         (lambda () (yeah-client--read-port socket))))
               (read (cdr outcome)))
          (unless read
            (push "the reader did not read the file of the port: the stand of the vanished port proves nothing"
                  yeah-check--failures))
          (yeah-check--expect-nil
           (car outcome)
           "the port of a service that stopped while the client read it"))
        (ignore-errors (delete-file port-file))
        ;; 3. a directory in place of the file of the port
        (make-directory port-file t)
        (yeah-check--expect-nil
         (yeah-check--call (lambda () (yeah-client--read-port socket)))
         "the port file that is a directory")
        (ignore-errors (delete-directory port-file t))
        ;; 4. a file of the port that cannot be read
        (yeah-check--write-port port-file (number-to-string yeah-check--port))
        (set-file-modes port-file #o000)
        (if (file-readable-p port-file)
            (message "client-port: the mode of the file does not deny the read on this host: the stand of the unreadable port is skipped")
          (yeah-check--expect-nil
           (yeah-check--call (lambda () (yeah-client--read-port socket)))
           "the port file that cannot be read"))
        (set-file-modes port-file #o600)
        (ignore-errors (delete-file port-file))
        ;; 5. a file of the port that holds text and not a port
        (yeah-check--write-port port-file "not a port")
        (yeah-check--expect-nil
         (yeah-check--call (lambda () (yeah-client--read-port socket)))
         "the port file that holds text and not a port")
        ;; 6. a file of the port that holds a port out of range
        (dolist (text '("0" "65536"))
          (yeah-check--write-port port-file text)
          (yeah-check--expect-nil
           (yeah-check--call (lambda () (yeah-client--read-port socket)))
           (format "the port file that holds the port %s out of range" text)))
        ;; 7. a file of the port that holds a port
        (yeah-check--write-port port-file (number-to-string yeah-check--port))
        (let ((result (yeah-check--call (lambda () (yeah-client--read-port socket)))))
          (cond
           ((not (eq 'ok (car result)))
            (push (format "the port of a service that is there raised an error: %S" (cdr result))
                  yeah-check--failures))
           ((not (equal yeah-check--port (cdr result)))
            (push (format "the port of a service that is there is %S and not %d"
                          (cdr result) yeah-check--port)
                  yeah-check--failures))))
        ;; 8. the reader hides the error of the file and nothing else
        (let ((blind (lambda (orig path &rest args)
                       (if (equal path port-file)
                           (error "the reader does not hide the failure of the read")
                         (apply orig path args)))))
          (advice-add 'insert-file-contents :around blind)
          (unwind-protect
              (let ((result (yeah-check--call (lambda () (yeah-client--read-port socket)))))
                (cond
                 ((not (eq 'error (car result)))
                  (push "the reader hid an error that is not an error of the file"
                        yeah-check--failures))
                 ((memq 'file-error (get (car (cdr result)) 'error-conditions))
                  (push "the reader caught an error that is not an error of the file as if it were one"
                        yeah-check--failures))))
            (advice-remove 'insert-file-contents blind)))
        ;; 9. the client waits for a service that is not there
        (let* ((yeah-client-network-family 'ipv4)
               (start (float-time))
               (result (condition-case err
                           (cons 'ok (yeah-client-connect socket :timeout 1))
                         (error (cons 'error err))))
               (elapsed (- (float-time) start)))
          (cond
           ((not (eq 'error (car result)))
            (push "the client connected to a service that is not there" yeah-check--failures))
           ((not (memq 'user-error (get (car (cdr result)) 'error-conditions)))
            (push (format "the client did not say that there is no service: %S" (cdr result))
                  yeah-check--failures))
           ((not (string-match-p "no service on" (yeah-check--error-text (cdr result))))
            (push (format "the client did not name the service it did not find: %S" (cdr result))
                  yeah-check--failures))
           ((< elapsed 0.5)
            (push (format "the client gave up after %.2fs and did not wait for the service" elapsed)
                  yeah-check--failures))))
        ;; 10. the client waits for a service whose file of the port vanishes
        (yeah-check--write-port port-file (number-to-string yeah-check--port))
        (let* ((yeah-client-network-family 'ipv4)
               (start (float-time))
               (outcome (yeah-check--vanishing-port
                        port-file
                        (lambda () (yeah-client-connect socket :timeout 1))))
               (result (car outcome))
               (elapsed (- (float-time) start)))
          (unless (cdr outcome)
            (push "the client did not read the file of the port: the stand of the vanished port proves nothing"
                  yeah-check--failures))
          (cond
           ((not (eq 'error (car result)))
            (push "the client connected to a service that is not there" yeah-check--failures))
           ((not (memq 'user-error (get (car (cdr result)) 'error-conditions)))
            (push (format "the client died on the file where it promised to wait: %S" (cdr result))
                  yeah-check--failures))
           ((not (string-match-p "no service on" (yeah-check--error-text (cdr result))))
            (push (format "the client did not name the service it did not find: %S" (cdr result))
                  yeah-check--failures))
           ((< elapsed 0.5)
            (push (format "the client gave up after %.2fs and did not wait for the service" elapsed)
                  yeah-check--failures))))
        ;; 11. the stop of a service removes the file of the port
        (let* ((name (format "gone-%d-%d" (emacs-pid) (random 1000000)))
               (service-socket (yeah-service-socket-path name))
               (service-port-file (yeah-client-port-file service-socket)))
          (yeah-check--write-port service-port-file (number-to-string yeah-check--port))
          ;; The service of the check is never started: only the removal
          ;; of the file of the port is exercised here.
          (yeah-service-stop name)
          (if (file-exists-p service-port-file)
              (push "the stop of the service did not remove the file of the port"
                    yeah-check--failures)
            (yeah-check--expect-nil
             (yeah-check--call (lambda () (yeah-client--read-port service-socket)))
             "the port of a service that stopped"))))
    (ignore-errors (delete-directory directory t)))
  (dolist (failure yeah-check--failures)
    (message "client-port: %s" failure))
  (if yeah-check--failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-the-client-reads-the-port-of-a-service-that-is-gone.el ends here
