;;; yeah-files.el --- bounded file discovery and reading tools -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; File tool specifications for Yeah's tool registry.  The handlers are
;; synchronous Elisp operations: they do not start subprocesses or modify the
;; files they inspect.

;;; Code:

(require 'cl-lib)
(require 'yeah-result)

(defconst yeah-files--ignored-directories
  '(".git" ".hg" ".svn"
    "node_modules" "bower_components" "vendor" "deps"
    "dist" "build" "_build" "target" "out"
    ".venv" "venv" "__pycache__" ".tox" ".mypy_cache" ".pytest_cache")
  "Directory names excluded from recursive file discovery.")

(defconst yeah-files--grep-max-file-size (* 1024 1024)
  "Maximum file size in bytes searched by the grep tool.")

(defconst yeah-files--binary-sniff-length 4096
  "Number of initial characters checked for a NUL byte.")

(defun yeah-files--protect (tool thunk)
  "Run THUNK for TOOL, returning structured expected failures."
  (condition-case err
      (funcall thunk)
    (user-error
     (yeah-result-error
      (format "yeah-files %s: %s" tool (error-message-string err))))
    (file-error
     (yeah-result-error
      (format "yeah-files %s: %s" tool (error-message-string err))))))

(defun yeah-files--positive-integer (value default name)
  "Return VALUE or DEFAULT, requiring a positive integer named NAME."
  (let ((actual (or value default)))
    (unless (and (integerp actual) (> actual 0))
      (user-error "%s must be a positive integer, got %S" name value))
    actual))

(defun yeah-files--validate-regexp (pattern)
  "Return PATTERN after validating its type and Emacs regexp syntax."
  (unless (stringp pattern)
    (user-error "pattern must be a string, got %S" (type-of pattern)))
  (condition-case err
      (progn
        (string-match-p pattern "")
        pattern)
    (invalid-regexp
     (user-error "invalid regexp %S: %s"
                 pattern (error-message-string err)))))

(defun yeah-files--canonical-file (path)
  "Return the canonical name of readable regular file PATH."
  (unless (and (stringp path) (> (length path) 0))
    (user-error "path must be a nonempty string, got %S" path))
  (let ((canonical (file-truename path)))
    (unless (file-exists-p canonical)
      (user-error "file does not exist: %s" canonical))
    (unless (file-regular-p canonical)
      (user-error "not a regular file: %s" canonical))
    (unless (file-readable-p canonical)
      (user-error "file is not readable: %s" canonical))
    canonical))

(defun yeah-files--canonical-directory (directory)
  "Return the canonical name of readable DIRECTORY or `default-directory'."
  (let ((actual (or directory default-directory)))
    (unless (and (stringp actual) (> (length actual) 0))
      (user-error "directory must be a nonempty string, got %S" directory))
    (let ((canonical (file-truename actual)))
      (unless (file-directory-p canonical)
        (user-error "not a readable directory: %s" canonical))
      (unless (file-readable-p canonical)
        (user-error "not a readable directory: %s" canonical))
      canonical)))

(defun yeah-files--discover (directory)
  "Return sorted regular files below DIRECTORY, pruning ignored directories."
  (sort
   (directory-files-recursively
    directory "" nil
    (lambda (path)
      (if (file-directory-p path)
          (not (member (file-name-nondirectory (directory-file-name path))
                       yeah-files--ignored-directories))
        (file-regular-p path))))
   #'string-lessp))

(defun yeah-files--read (path &optional offset limit)
  "Read PATH at 1-based line OFFSET, returning at most LIMIT lines."
  (yeah-files--protect
   "read"
   (lambda ()
     (let ((canonical (yeah-files--canonical-file path))
           (actual-offset (yeah-files--positive-integer offset 1 "offset"))
           (actual-limit (yeah-files--positive-integer limit 2000 "limit")))
       (with-temp-buffer
         (let ((coding-system-for-read 'utf-8-unix))
           (insert-file-contents canonical))
         (let ((total-lines (if (= (point-min) (point-max))
                                0
                              (count-lines (point-min) (point-max)))))
           (when (> actual-offset (max 1 total-lines))
             (user-error "offset %d exceeds the file's %d lines"
                         actual-offset total-lines))
           (goto-char (point-min))
           (forward-line (1- actual-offset))
           (let ((start (point)))
             (forward-line actual-limit)
             (let* ((end (point))
                    (truncated (< end (point-max)))
                    (content (buffer-substring-no-properties start end))
                    (tick (with-current-buffer (find-file-noselect canonical)
                            (buffer-chars-modified-tick)))
                    (metadata (list :path canonical
                                    :offset actual-offset
                                    :limit actual-limit
                                    :total-lines total-lines
                                    :tick tick
                                    :truncated truncated)))
               (yeah-result-ok content metadata truncated)))))))))

(defun yeah-files--glob (pattern &optional directory limit)
  "Find relative paths matching regexp PATTERN below DIRECTORY.
Return no more than LIMIT paths."
  (yeah-files--protect
   "glob"
   (lambda ()
     (let ((root (yeah-files--canonical-directory directory))
           (actual-limit (yeah-files--positive-integer limit 1000 "limit")))
       (yeah-files--validate-regexp pattern)
       (let ((files (yeah-files--discover root))
             (paths nil)
             (count 0)
             (truncated nil))
         (catch 'yeah-files--glob-done
           (dolist (file files)
             (let ((relative (file-relative-name file root)))
               (when (string-match-p pattern relative)
                 (if (= count actual-limit)
                     (progn
                       (setq truncated t)
                       (throw 'yeah-files--glob-done nil))
                   (setq count (1+ count))
                   (push relative paths))))))
         (let ((metadata (list :count count :truncated truncated)))
           (yeah-result-ok (mapconcat #'identity (nreverse paths) "\n")
                           metadata truncated)))))))

(defun yeah-files--binary-buffer-p ()
  "Return non-nil when the current buffer looks like a binary file."
  (save-excursion
    (goto-char (point-min))
    (search-forward "\0"
                    (min (point-max)
                         (+ (point-min) yeah-files--binary-sniff-length))
                    t)))

(defun yeah-files--grep-file (file pattern on-match)
  "Search FILE for PATTERN, calling ON-MATCH with line number and text.
Skip large, unreadable, and likely binary files."
  (let ((attributes (file-attributes file)))
    (when (and attributes
               (<= (or (nth 7 attributes) 0) yeah-files--grep-max-file-size)
               (file-readable-p file))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8-unix))
          (insert-file-contents file))
        (unless (yeah-files--binary-buffer-p)
          (goto-char (point-min))
          (let ((previous-position -1)
                (done nil))
            (while (and (not done) (re-search-forward pattern nil t))
              (funcall on-match
                       (line-number-at-pos (match-beginning 0))
                       (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position)))
              (if (/= (point) previous-position)
                  (setq previous-position (point))
                (if (< (point) (point-max))
                    (forward-char 1)
                  (setq done t))))))))))

(defun yeah-files--grep (pattern &optional directory limit)
  "Search text files below DIRECTORY for Emacs regexp PATTERN.
Return at most LIMIT path:line:text matches."
  (yeah-files--protect
   "grep"
   (lambda ()
     (let ((root (yeah-files--canonical-directory directory))
           (actual-limit (yeah-files--positive-integer limit 200 "limit")))
       (yeah-files--validate-regexp pattern)
       (let ((files (yeah-files--discover root))
             (lines nil)
             (count 0)
             (truncated nil))
         (catch 'yeah-files--grep-done
           (dolist (file files)
             (let ((relative (file-relative-name file root)))
               (condition-case nil
                   (yeah-files--grep-file
                    file pattern
                    (lambda (line-number text)
                      (if (= count actual-limit)
                          (progn
                            (setq truncated t)
                            (throw 'yeah-files--grep-done nil))
                        (setq count (1+ count))
                        (push (format "%s:%d:%s\n" relative line-number text)
                              lines))))
                 (file-error nil)))))
         (yeah-result-from-output
          (mapconcat #'identity (nreverse lines) "")
          nil
          (list :count count :truncated truncated)))))))

(defun yeah-files-tools ()
  "Return read, glob, and grep tool specifications for Yeah's registry."
  (list
   (list :name "read"
         :description "Read a UTF-8 file by 1-based line offset and line limit."
         :input (list (list :name "path" :type 'string)
                      (list :name "offset" :type 'integer :optional t)
                      (list :name "limit" :type 'integer :optional t))
         :handler #'yeah-files--read)
   (list :name "glob"
         :description "List relative file paths matching an Emacs regexp."
         :input (list (list :name "pattern" :type 'string)
                      (list :name "directory" :type 'string :optional t)
                      (list :name "limit" :type 'integer :optional t))
         :handler #'yeah-files--glob)
   (list :name "grep"
         :description "Search text files for an Emacs regexp without subprocesses."
         :input (list (list :name "pattern" :type 'string)
                      (list :name "directory" :type 'string :optional t)
                      (list :name "limit" :type 'integer :optional t))
         :handler #'yeah-files--grep)))

(provide 'yeah-files)
;;; yeah-files.el ends here
