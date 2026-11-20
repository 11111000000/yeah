;;; yeah-shell-guard.el --- the guard of the shell of the agent -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The agent runs commands in a shell.  Two things stand between the
;; agent and a command that cannot be taken back.
;;
;; The first is the `rm' of the shell: it is not the `rm' of the system
;; but a script that moves what it is given into the trash
;; (`lib/yeah-trash.el').  The script is put in front of the PATH of
;; the processes of the agent, so that every `rm' the agent runs --
;; `rm -rf', `rm -fr', `find ... -exec rm', `xargs rm', a script the
;; agent wrote -- moves into the trash and removes nothing.  The flags
;; of `rm' are dropped: the trash does not need to know about them.
;;
;; The second is this guard: the commands that destroy in place are
;; refused by name, because no trash can bring back what was never
;; moved into it.  The guard is a list of forms and not a sandbox: a
;; command that hides its intent (`r''m -rf', a variable, a script from
;; the network) is not caught by it.  The honest name of the guard is a
;; guard, and the honest boundary of the agent is the account it runs
;; as and the trash that keeps what it throws away.
;;
;; The refusals name their reason: an agent that is refused a command
;; can tell the person what it wanted to do and why it may not.

;;; Code:

(require 'cl-lib)

(defconst yeah-shell-guard--refusals
  '(("\\bsudo\\b"
     . "the agent does not become another user")
    ("\\(/usr/\\)?bin/\\(rm\\|busybox\\)[[:space:]]"
     . "the rm of the system removes in place; the trash is the rm the shell finds")
    ("\\bfind[[:space:]].*\\bdelete\\b"
     . "find -delete removes in place")
    ("\\b\\(shred\\|srm\\|unlink\\|truncate\\)\\b"
     . "the command removes in place, and nothing comes back from that")
    ("\\bdd[[:space:]].*of=/dev/"
     . "dd on a device destroys it")
    ("\\b\\(mkfs\\(\\.[a-z0-9]+\\)?\\|fdisk\\|parted\\)\\b"
     . "the command writes a filesystem and destroys what was on the device")
    ("\\bgit[[:space:]].*\\bclean\\b"
     . "git clean removes in place")
    (")[[:space:]]*{[[:space:]]*:"
     . "the command forks itself for ever"))
  "The commands the shell of the agent refuses, and the reason of each refusal.
Every entry is a cons of a regular expression and the reason of the
refusal.  The expressions are matched against the whole command: the
guard reads the text of the command and not the shell it is written for.")

(defun yeah-shell-guard--refusal (command)
  "Return the reason why COMMAND is refused, or nil.
The reason names what the command does, so that the agent can tell the
person what it wanted to do."
  (when (stringp command)
    (let ((reason nil))
      (dolist (entry yeah-shell-guard--refusals)
        (when (and (null reason)
                   (string-match (car entry) command))
          (setq reason (cdr entry))))
      reason)))

(defun yeah-shell-guard-check (command)
  "Refuse COMMAND when it is a command the agent may not run.
Signals `user-error' with the reason of the refusal; returns the command
when there is nothing to refuse."
  (let ((reason (yeah-shell-guard--refusal command)))
    (when reason
      (signal 'user-error
              (list (format "the shell of the agent refuses this command: %s"
                            reason))))
    command))

(defconst yeah-shell-guard--rm-script
  "#!/bin/sh
# The rm of the agent: it moves what it is given into the trash and
# removes nothing.  The flags of rm are dropped: the trash does not need
# to know about them, and a path that begins with a dash is rare enough
# to be named with a path prefix.
if ! command -v gio >/dev/null 2>&1; then
  echo \"rm: the trash is not available on this host; nothing was removed\" >&2
  exit 1
fi
status=0
for arg in \"$@\"; do
  case \"$arg\" in
    -*) continue ;;
  esac
  if ! gio trash -- \"$arg\"; then
    echo \"rm: cannot move $arg into the trash\" >&2
    status=1
  fi
done
exit $status
"
  "The script that stands in for `rm' in the shell of the agent.
It moves every path it is given into the trash of the user and removes
nothing.  It needs `gio', the program of the desktop of the person; when
`gio' is not there, the script refuses the removal instead of letting it
through.")

(defun yeah-shell-guard--shim-directory ()
  "Return the directory of the shims of the shell of the agent.
The directory lives under the data home of the harness when that home is
known, and under the data of the user when it is not: the guard stands
below the product in the layers of the kernel and does not require it."
  (expand-file-name
   "shims/"
   (if (boundp 'yeah-data-home)
       yeah-data-home
     (expand-file-name "yeah/" (or (getenv "XDG_DATA_HOME")
                                   (expand-file-name ".local/share/" (getenv "HOME")))))))

(defun yeah-shell-guard--write-shims ()
  "Write the shims of the shell of the agent and return their directory.
The directory is private and the scripts of it are executable: the
agent runs the `rm' of the trash and nobody else does."
  (let ((directory (yeah-shell-guard--shim-directory)))
    (unless (file-directory-p directory)
      (make-directory directory t))
    (set-file-modes directory #o700)
    (let ((rm (expand-file-name "rm" directory)))
      (unless (file-executable-p rm)
        (with-temp-file rm
          (set-buffer-file-coding-system 'utf-8-unix)
          (insert yeah-shell-guard--rm-script))
        (set-file-modes rm #o755)))
    directory))

(defun yeah-shell-guard-path ()
  "Return the PATH the processes of the agent get.
The shims of the shell come first, so that the `rm' of the agent is the
`rm' that moves into the trash.  The rest of the PATH is the PATH of the
process of Emacs: the shims are added, nothing is taken away."
  (format "%s%s" (yeah-shell-guard--write-shims) path-separator))

(defun yeah-shell-guard--wrap (command)
  "Return COMMAND with the shims of the shell in front of its PATH.
The PATH is exported inside the shell and not outside it: `make-process'
knows no environment of its own, and the assignment of the PATH in the
command reaches every child of that command."
  (format "export PATH=%s$PATH; %s" (shell-quote-argument (yeah-shell-guard-path))
          command))

(provide 'yeah-shell-guard)
;;; yeah-shell-guard.el ends here
