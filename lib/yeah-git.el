;;; yeah-git.el --- git tools for reviewing and committing a change -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The tools of the review-commit loop: the agent sees what changed, reads
;; the difference, and — only when the rules allow it — writes a commit.
;;
;; Every command is a subprocess started with `make-process' — never a
;; blocking shell command — in the project directory, decoded as UTF-8 and
;; bounded.  Magit is neither required nor called: these are the plain git
;; command line, so that the tools work in a service Emacs without a
;; display and in a batch Emacs without a terminal.
;;
;; `git_status' and `git_diff' only read.  `git_commit' writes history, so
;; it is the only one that asks the permission rules: a commit needs a rule
;; that allows the action "git_commit" on the project directory.  A rule is
;; standing permission; a one-time answer at the turn is not enough,
;; because a commit cannot be un-written by asking.
;;
;; The tools are asynchronous, like the Bash tool: the handler starts the
;; subprocess and the continuation answers when the command has finished.

;;; Code:

(require 'cl-lib)
(require 'yeah-perm)
(require 'yeah-result)

(defconst yeah-git--output-cap (* 256 1024)
  "Maximum number of characters one git command may collect.
A command that says more is cut: the model gets what fits and the
result says that it was truncated.")

(defconst yeah-git--timeout 30
  "Seconds one git command may run before it is cut.")

(defconst yeah-git--commit-action "git_commit"
  "The action the permission rules match a commit against.")

(defvar yeah-git--rules nil
  "The ruleset `git_commit' consults, or nil for the global ruleset.
A run binds this for the length of its own tool calls, so that the rules
of the run decide and the persistent rules of the person are not the only
truth that a commit is asked of.")

(defun yeah-git--directory (directory)
  "Return DIRECTORY as an absolute name of a directory that exists."
  (unless (and (stringp directory) (> (length directory) 0))
    (user-error "the project directory must be a nonempty string, got %S" directory))
  (let ((expanded (file-name-as-directory (expand-file-name directory))))
    (unless (file-directory-p expanded)
      (user-error "the project directory does not exist: %s" expanded))
    expanded))

(defun yeah-git--excerpt (output limit)
  "Return the last LIMIT characters of OUTPUT, marked when it was cut."
  (if (<= (length output) limit)
      output
    (concat "[...]\n" (substring output (- (length output) limit)))))

(defun yeah-git--fail (tool err)
  "Return the structured failure of TOOL for the error ERR."
  (yeah-result-error (format "yeah-git %s: %s" tool (error-message-string err))))

(defun yeah-git--result (directory args status exit output truncated)
  "Return the structured result of a git command.

DIRECTORY is the project the command ran in, ARGS the arguments it ran
with, STATUS what became of it, EXIT its exit code, OUTPUT what it said
and TRUNCATED whether the output was cut."
  (let* ((command (mapconcat #'identity (cons "git" args) " "))
         (metadata (list :command command
                         :directory directory
                         :status status
                         :exit exit
                         :truncated (and truncated t))))
    (if (and (string= status "exited") (= exit 0))
        (let ((result (yeah-result-from-output output nil metadata)))
          (if truncated
              ;; The plist is the one `yeah-result-from-output' just made, so
              ;; changing it here changes nothing else.
              (plist-put result :truncated t)
            result))
      (yeah-result-error
       (format "git %s failed (%s): %s"
               command status
               (if (string= output "")
                   "no output"
                 (yeah-git--excerpt output 2000)))
       metadata))))

(defun yeah-git--run (directory args done)
  "Run git with ARGS in DIRECTORY and call DONE with the result.

DONE receives one structured result.  The command is a subprocess started
with `make-process'; its working directory is DIRECTORY, its output is
decoded as UTF-8 and bounded by `yeah-git--output-cap'.  A command that
runs longer than `yeah-git--timeout' seconds is cut and reported as a
timeout."
  (let* ((buffer (generate-new-buffer " *yeah-git*"))
         (truncated nil)
         (settled nil)
         (process nil)
         (timer nil)
         (finish
          (lambda (status exit output)
            (unless settled
              (setq settled t)
              (when timer
                (cancel-timer timer))
              (when (and process (process-live-p process))
                (set-process-sentinel process nil)
                (delete-process process))
              (when (buffer-live-p buffer)
                (kill-buffer buffer))
              (funcall done
                       (yeah-git--result directory args status exit output
                                         truncated))))))
    (condition-case err
        (progn
          (setq process
                (let ((default-directory directory))
                  (make-process
                   :name "yeah-git"
                   :buffer buffer
                   :command (cons "git" args)
                   :coding '(utf-8 . utf-8)
                   :connection-type 'pipe
                   :noquery t
                   :filter (lambda (_process chunk)
                             (when (buffer-live-p buffer)
                               (with-current-buffer buffer
                                 (if (> (+ (buffer-size) (length chunk))
                                         yeah-git--output-cap)
                                     (setq truncated t)
                                   (insert chunk)))))
                   :sentinel
                   (lambda (proc _event)
                     (when (memq (process-status proc) '(exit signal))
                       (funcall finish
                                (if (eq (process-status proc) 'exit)
                                    "exited"
                                  "signaled")
                                (process-exit-status proc)
                                (with-current-buffer buffer
                                  (buffer-substring-no-properties
                                   (point-min) (point-max)))))))))
          (setq timer
                (run-at-time yeah-git--timeout nil
                             (lambda ()
                               (funcall finish "timeout" nil ""))))
          nil)
      (error
       (funcall finish "failed" nil (error-message-string err))))))

(defun yeah-git--run-plan (directory commands done)
  "Run COMMANDS in DIRECTORY in order and call DONE with the last result.

COMMANDS is a list of argument lists for git.  A command that fails stops
the plan: DONE receives that failure and the commands after it do not run."
  (if (null commands)
      (funcall done (yeah-result-error "yeah-git: there was nothing to run"))
    (yeah-git--run
     directory (car commands)
     (lambda (result)
       (if (and (cdr commands) (yeah-result-success-p result))
           (yeah-git--run-plan directory (cdr commands) done)
         (funcall done result))))))

(defun yeah-git--status (args done)
  "Show the status of the project and answer DONE.

ARGS is the argument list of the tool: the project directory."
  (condition-case err
      (yeah-git--run (yeah-git--directory (nth 0 args))
                     '("--no-pager" "status" "--porcelain" "--branch")
                     done)
    (user-error (funcall done (yeah-git--fail "git_status" err)))
    (file-error (funcall done (yeah-git--fail "git_status" err)))))

(defun yeah-git--diff (args done)
  "Show the difference in the project and answer DONE.

ARGS is the argument list of the tool: the project directory, the path to
look at (or nil for the whole project) and whether the staged changes are
the ones to show."
  (condition-case err
      (let* ((directory (yeah-git--directory (nth 0 args)))
             (path (nth 1 args))
             (staged (nth 2 args)))
        (when (and path (not (stringp path)))
          (user-error "the path must be a string, got %S" (type-of path)))
        (when (and staged (not (booleanp staged)))
          (user-error "staged must be true or false, got %S" staged))
        (yeah-git--run
         directory
         (append (list "--no-pager" "diff")
                 (when staged '("--cached"))
                 (when path (list "--" path)))
         done))
    (user-error (funcall done (yeah-git--fail "git_diff" err)))
    (file-error (funcall done (yeah-git--fail "git_diff" err)))))

(defun yeah-git--split-files (files)
  "Return the list of paths in FILES.

FILES is a string: the paths are separated by commas or newlines.  A path
that holds a comma is not a path this tool can name."
  (when (and files (not (stringp files)))
    (user-error "the files must be a string, got %S" (type-of files)))
  (let ((parts (split-string (or files "") "[,\n]")))
    (seq-remove (lambda (part) (string= "" part))
                (mapcar #'string-trim parts))))

(defun yeah-git--effect (resources rules)
  "Return the effect RULES give for a commit on RESOURCES.

RESOURCES is the list of names the rules may name the commit by.  A deny
on any of them denies the commit; an allow on any of them allows it; a
question on all of them is a question."
  (let ((effects (mapcar (lambda (resource)
                            (yeah-perm-effect yeah-git--commit-action resource rules))
                          resources)))
    (cond ((memq 'deny effects) 'deny)
          ((memq 'allow effects) 'allow)
          (t 'ask))))

(defun yeah-git--authorize (directory raw)
  "Refuse a commit in DIRECTORY unless the rules allow it.

RAW is the project directory as the caller named it.  The rule may name
either RAW or its absolute form DIRECTORY: both are the same project."
  (let* ((rules (or yeah-git--rules (yeah-perm-rules-list)))
         (resources (delete-dups (list raw directory)))
         (effect (yeah-git--effect resources rules)))
    (unless (eq effect 'allow)
      (user-error "the rules do not allow a commit in %s (%s)"
                  directory
                  (if (eq effect 'deny) "denied" "not allowed")))))

(defun yeah-git--commit-commands (message files)
  "Return the commands of a commit with MESSAGE for FILES.

FILES is the list of paths to commit.  Without paths the staged changes
are committed; with paths those paths are staged and committed, and
nothing else."
  (if (null files)
      (list (list "--no-pager" "commit" "--no-gpg-sign" "-m" message))
    (list (append (list "--no-pager" "add" "--") files)
          (append (list "--no-pager" "commit" "--no-gpg-sign" "-m" message "--")
                  files))))

(defun yeah-git--commit (args done)
  "Write a commit in the project and answer DONE.

ARGS is the argument list of the tool: the project directory, the commit
message and the paths to commit (or nil for the staged changes).  The
rules must allow the commit before anything is written."
  (condition-case err
      (let* ((directory (yeah-git--directory (nth 0 args)))
             (message (nth 1 args))
             (files (yeah-git--split-files (nth 2 args))))
        (unless (and (stringp message) (> (length message) 0))
          (user-error "the commit message must be a nonempty string, got %S" message))
        (yeah-git--authorize directory (nth 0 args))
        (yeah-git--run-plan directory
                            (yeah-git--commit-commands message files)
                            done))
    (user-error (funcall done (yeah-git--fail "git_commit" err)))
    (file-error (funcall done (yeah-git--fail "git_commit" err)))))

(defun yeah-git-tools ()
  "Return the git tool specifications for Yeah's registry."
  (list
   (list :name "git_status"
         :description
         "Show the status of the project: the branch, and the files that are changed, staged or untracked. The directory is the project directory; the command runs there."
         :input (list (list :name "directory" :type 'string))
         :async t
         :handler #'yeah-git--status)
   (list :name "git_diff"
         :description
         "Show the difference in the project: the changes that are not staged yet, for the whole project or for one path. Set staged to true to see what the next commit would contain."
         :input (list (list :name "directory" :type 'string)
                      (list :name "path" :type 'string :optional t)
                      (list :name "staged" :type 'boolean :optional t))
         :async t
         :handler #'yeah-git--diff)
   (list :name "git_commit"
         :description
         "Write a commit in the project. The rules must allow it: a rule that allows git_commit on the project directory is required, and a one-time approval is not enough. The files are the paths to commit, separated by commas or newlines, relative to the project directory; without them the staged changes are committed."
         :input (list (list :name "directory" :type 'string)
                      (list :name "message" :type 'string)
                      (list :name "files" :type 'string :optional t))
         :async t
         :concurrency 'exclusive
         :handler #'yeah-git--commit)))

(provide 'yeah-git)
;;; yeah-git.el ends here
