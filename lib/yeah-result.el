;;; yeah-result.el --- structured tool results and output artifacts -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; New tools return `yeah-result-ok' or `yeah-result-error'.  Legacy strings
;; and scheduler `(:yeah-error ...)' values remain accepted at the boundary.
;; Oversized output is stored privately; the model receives a bounded excerpt
;; and an artifact reference rather than unbounded text.

;;; Code:

(require 'cl-lib)
(require 'yeah-text)

(defgroup yeah-result nil
  "Structured Yeah tool results."
  :group 'yeah)

(defcustom yeah-result-output-limit 32768
  "Default maximum number of characters returned inline by one tool result."
  :type 'integer
  :group 'yeah-result)

(defcustom yeah-result-artifact-directory
  (expand-file-name "yeah/tool-output/" user-emacs-directory)
  "Directory for full tool output that does not fit inline."
  :type 'directory
  :group 'yeah-result)

(defun yeah-result-ok (content &optional metadata truncated artifacts)
  "Return a successful result containing CONTENT.
METADATA is optional tool-specific data.  TRUNCATED and ARTIFACTS describe
output held outside the model context."
  (list :ok t
        :content (if (stringp content) content (format "%S" content))
        :error nil
        :truncated (and truncated t)
        :artifacts artifacts
        :metadata metadata))

(defun yeah-result-error (message &optional metadata artifacts)
  "Return a failed result with printable MESSAGE and optional METADATA."
  (list :ok nil
        :content nil
        :error (if (stringp message) message (format "%S" message))
        :truncated nil
        :artifacts artifacts
        :metadata metadata))

(defun yeah-result-p (value)
  "Return non-nil when VALUE is a structured Yeah tool result."
  (and (listp value)
       (booleanp (plist-get value :ok))
       (or (plist-member value :content)
           (plist-member value :error))))

(defun yeah-result-success-p (value)
  "Return non-nil when VALUE represents a successful tool result."
  (if (yeah-result-p value)
      (eq t (plist-get value :ok))
    (not (or (null value)
             (and (consp value) (plist-get value :yeah-error))))))

(defun yeah-result-artifact-write (tool-name content)
  "Write CONTENT privately as TOOL-NAME's full output and return its path."
  (unless (stringp content)
    (signal 'user-error (list "yeah-result: artifact content must be a string")))
  (let ((directory (file-name-as-directory
                    (expand-file-name yeah-result-artifact-directory))))
    (make-directory directory t)
    (set-file-modes directory #o700)
    (let ((file (make-temp-file (expand-file-name
                                 (format "%s-" tool-name) directory)
                                nil ".txt")))
      (let ((coding-system-for-write 'utf-8))
        (with-temp-buffer
          (insert content)
          (write-region (point-min) (point-max) file nil 'silent)))
      (set-file-modes file #o600)
      file)))

(defun yeah-result-from-output (content &optional limit metadata)
  "Return a bounded result for tool output CONTENT.
When CONTENT exceeds LIMIT (default `yeah-result-output-limit'), write the
full text to a private artifact and return its tail inline."
  (unless (stringp content)
    (setq content (format "%S" content)))
  ;; A tool may hand back bytes that are not text: `tail -c' cuts a character
  ;; of a UTF-8 file in half.  The text of the harness is always valid UTF-8,
  ;; and a byte that is not text becomes the replacement character.
  (setq content (yeah-text-valid content))
  (let ((limit (or limit yeah-result-output-limit)))
    (unless (and (integerp limit) (> limit 0))
      (signal 'user-error (list "yeah-result: output limit must be positive")))
    (if (<= (length content) limit)
        (yeah-result-ok content metadata)
      (let* ((artifact (yeah-result-artifact-write "tool" content))
             (tail (substring content (- (length content) limit))))
        (yeah-result-ok tail metadata t (list artifact))))))

(defun yeah-result-bound (value limit)
  "Return VALUE with the output the model reads bounded by LIMIT characters.
LIMIT is the number of characters of the output of the tool that reach the
model.  The whole text of an output that does not fit goes into a private
artifact and the model reads the tail of it, exactly as
`yeah-result-from-output' does.

The value is returned as it is when it carries no output, when the output
fits into LIMIT, and when LIMIT is not a positive integer: a tool that
declares no limit works by the global limit, and the caller decides which
limit applies."
  (if (not (and (integerp limit) (> limit 0)))
      value
    (cond
     ((stringp value)
      (if (<= (length value) limit)
          value
        (yeah-result-from-output value limit)))
     ((yeah-result-p value)
      (let ((content (plist-get value :content)))
        (if (or (not (stringp content))
                (<= (length content) limit))
            value
          (let* ((full (yeah-text-valid content))
                 (artifact (yeah-result-artifact-write "tool" full))
                 (bounded (copy-tree value)))
            ;; `plist-put' changes the plist it is given, so the value is
            ;; copied before it is changed: the tick and the version of the
            ;; result stay where they were.
            (plist-put bounded :content (substring full (- (length full) limit)))
            (plist-put bounded :truncated t)
            (plist-put bounded :artifacts
                       (append (plist-get value :artifacts) (list artifact)))
            bounded))))
     (t value))))

(defun yeah-result-model-text (value)
  "Return one provider-safe string for tool result VALUE.
Structured results include artifact references and truncation metadata;
legacy strings and scheduler error plists are accepted for compatibility."
  (cond
   ((yeah-result-p value)
    (let* ((base (if (plist-get value :ok)
                     (or (plist-get value :content) "")
                   (or (plist-get value :error) "Error: tool failed")))
           (artifacts (plist-get value :artifacts))
           (truncated (plist-get value :truncated))
           (metadata (plist-get value :metadata))
           (tick (or (plist-get value :tick)
                     (and (listp metadata)
                          (plist-get metadata :tick))))
           (version (or (plist-get value :version)
                        (and (listp metadata)
                             (plist-get metadata :version)))))
      (concat (yeah-text-valid base)
              (when (and tick (integerp tick))
                (format "\n[tick: %d]" tick))
              (when (and version (stringp version))
                (format "\n[version: %s]" version))
              (when truncated "\n[Output truncated.]")
              (when artifacts
                (concat "\n[Full output: "
                        (mapconcat (lambda (path) (format "%s" path))
                                   artifacts ", ")
                        "]")))))
   ((and (consp value) (plist-get value :yeah-error))
    (yeah-text-valid (plist-get value :yeah-error)))
   ((null value) "Error: tool produced no result")
   ((stringp value) (yeah-text-valid value))
   (t (format "%S" value))))

(defun yeah-result-json-safe (value)
  "Return a JSON-safe representation of result metadata VALUE.
JSON objects stay plists with keyword keys; general lists become vectors so
`json-serialize' emits arrays rather than interpreting strings as object keys."
  (cond
   ((or (stringp value) (integerp value) (eq value t) (eq value :false)
        (null value))
    value)
   ((floatp value)
    (if (or (isnan value) (= value 1.0e+INF) (= value -1.0e+INF))
        (format "%S" value)
      value))
   ((vectorp value)
    (apply #'vector (mapcar #'yeah-result-json-safe value)))
   ((and (proper-list-p value)
         (zerop (% (length value) 2))
         (cl-loop for key in value by #'cddr always (keywordp key)))
    (let ((rest value)
          (result nil))
      (while rest
        (setq result
              (append result
                      (list (car rest) (yeah-result-json-safe (cadr rest)))))
        (setq rest (cddr rest)))
      result))
   ((proper-list-p value)
    (apply #'vector (mapcar #'yeah-result-json-safe value)))
   ((symbolp value)
    (symbol-name value))
   (t
    (format "%S" value))))

(defun yeah-result-details (value)
  "Return JSON-safe UI details for a structured result VALUE.
The shape is `(:truncated BOOL :artifacts VECTOR :metadata DATA)', with the
last two keys omitted when absent.  Nil is returned for legacy values and
for structured results with no truncation, artifacts or metadata.  This
projection does not change `yeah-result-model-text'."
  (when (yeah-result-p value)
    (let ((truncated (plist-get value :truncated))
          (artifacts (plist-get value :artifacts))
          (metadata (plist-get value :metadata)))
      (when (or truncated artifacts metadata)
        (append
         (list :truncated (if truncated t :false))
         (when artifacts
           (list :artifacts (yeah-result-json-safe artifacts)))
         (when metadata
           (list :metadata (yeah-result-json-safe metadata))))))))

(provide 'yeah-result)
;;; yeah-result.el ends here
