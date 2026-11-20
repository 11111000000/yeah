;;; check-a-tool-kind-is-in-the-vocabulary.el --- the kind of a tool is in the vocabulary -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The wire of ACP renders the call of a tool by its kind: a read, an
;; edit, a shell.  The kind is a fact of the tool and not a guess of its
;; name, so the kinds the tools declare are a vocabulary, and a tool that
;; declares a kind outside that vocabulary says something the protocol
;; cannot carry.
;;
;; The defect this check hunts: a tool declares a kind the protocol does
;; not know, and the registry takes it silently.  The mistake is invisible
;; from the outside, because the kind of a tool that declares none is
;; `other' and the kind of a tool that declares an unknown one is also
;; `other' -- the substitution hides what went wrong.
;;
;; So the check reads the RAW specification of every registered tool and
;; not the kind of the wire: `yeah-tools-kind' answers `other' for a kind
;; it does not know, and that answer would hide the very defect the check
;; looks for.  Four things are proved:
;;
;;   1. every kind that a registered tool declares is a kind of the
;;      vocabulary (a tool that declares no kind is legal, and its kind
;;      for the wire is `other');
;;   2. a tool that declares a kind outside the vocabulary is refused, and
;;      the refusal names the tool and the kind;
;;   3. a tool that declares no kind is accepted, and the wire gives it
;;      the kind `other';
;;   4. the docstring of `yeah-tools-register' names every kind of the
;;      vocabulary, so the reader of the source is not left guessing.
;;
;; The load of the registry is guarded: the built-in tools are registered
;; when `lib/yeah-tools.el' is loaded, so a built-in tool with a kind
;; outside the vocabulary stops the load -- and the check says so in its
;; own words instead of dying with the trace of the load.
;;
;; Exit codes: 0 -- the kinds of the tools are in the vocabulary;
;; 1 -- they are not.

;;; Code:

(require 'cl-lib)

(let ((failures nil)
      (load-failure nil))

  ;; The load of the registry is guarded: a refusal inside it must be
  ;; this check's own failure, and not a trace of a half-loaded library.
  (condition-case e
      (require 'yeah-tools)
    (error (setq load-failure e)))

  (if load-failure
      (push (format "the registry of the tools did not load: %s"
                    (error-message-string load-failure))
            failures)
    (let ((kinds yeah-tools--kinds)
          (probe-outside "probe-kind-outside")
          (probe-without "probe-kind-without"))

      ;; --- 1. every declared kind is in the vocabulary --------------------
      ;; The RAW `:kind' of the specification, never the kind of the
      ;; wire: `yeah-tools-kind' answers `other' for a kind it does not
      ;; know, and that answer would hide the defect.
      (dolist (name (yeah-tools-names))
        (let* ((spec (yeah-tools-get name))
               (kind (and spec (plist-get spec :kind))))
          (when kind
            (unless (and (stringp kind)
                         (cl-member kind kinds :test #'equal))
              (push (format "the tool %S declares the kind %S, which is not in the vocabulary of the protocol"
                            name kind)
                    failures)))))

      ;; --- 2. an unknown kind does not pass silently ----------------------
      (let ((refusal nil)
            (refusal-kind nil))
        (condition-case e
            (yeah-tools-register
             (list :name probe-outside
                   :description "A throwaway tool that declares a kind outside the vocabulary."
                   :input nil
                   :handler (lambda (&rest _args) nil)
                   :kind "source"))
          (user-error (setq refusal e) (setq refusal-kind 'user-error))
          (error (setq refusal e) (setq refusal-kind 'other)))
        (cond
         ((null refusal)
          (push (format "the tool %S declared the kind %S and was accepted: an unknown kind passed silently"
                        probe-outside "source")
                failures))
         ((eq refusal-kind 'other)
          (push (format "the tool %S declared the kind %S and the registration raised %S, which is not the user-error that names the kind"
                        probe-outside "source" refusal)
                failures))
         (t
          (let ((text (error-message-string refusal)))
            (unless (string-match-p (regexp-quote probe-outside) text)
              (push (format "the refusal of the unknown kind did not name the tool %S: %s"
                            probe-outside text)
                    failures))
            (unless (string-match-p (regexp-quote "source") text)
              (push (format "the refusal of the unknown kind did not name the kind %S: %s"
                            "source" text)
                    failures))))))

      ;; --- 3. a tool that declares no kind is accepted --------------------
      (let ((refusal nil))
        (condition-case e
            (yeah-tools-register
             (list :name probe-without
                   :description "A throwaway tool that declares no kind."
                   :input nil
                   :handler (lambda (&rest _args) nil)))
          (user-error (setq refusal e))
          (error (setq refusal e)))
        (when refusal
          (push (format "the tool %S declared no kind and was refused: %s"
                        probe-without (error-message-string refusal))
                failures))
        (unless (yeah-tools-get probe-without)
          (push (format "the tool %S declared no kind and is not in the registry"
                        probe-without)
                failures))
        (unless (equal "other" (yeah-tools-kind probe-without))
          (push (format "the tool %S declared no kind and the wire gave it the kind %S"
                        probe-without (yeah-tools-kind probe-without))
                failures)))

      ;; The registry keeps no trace of the two probes.
      (yeah-tools-unregister probe-outside)
      (yeah-tools-unregister probe-without)

      ;; --- 4. the docstring names the whole vocabulary --------------------
      (let ((doc (documentation 'yeah-tools-register)))
        (unless (stringp doc)
          (push "the docstring of yeah-tools-register is not a string" failures))
        (when (stringp doc)
          (dolist (kind kinds)
            (unless (string-match-p (concat "\\_<" (regexp-quote kind) "\\_>") doc)
              (push (format "the docstring of yeah-tools-register does not name the kind %S"
                            kind)
                    failures)))))))

  (dolist (failure failures)
    (message "tool-kind: %s" failure))
  (if failures
      (kill-emacs 1)
    (kill-emacs 0)))

;;; check-a-tool-kind-is-in-the-vocabulary.el ends here
