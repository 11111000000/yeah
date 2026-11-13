;;; test-yeah-markdown.el --- ERT tests for yeah-markdown -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-markdown)

(defmacro yeah-markdown-test--without-package (&rest body)
  "Run BODY while markdown-mode is absent from feature and load lookups."
  (declare (indent 0))
  `(let ((real-featurep (symbol-function 'featurep))
         (real-require (symbol-function 'require)))
     (cl-letf (((symbol-function 'featurep)
                (lambda (feature &optional subfeature)
                  (if (eq feature 'markdown-mode)
                      nil
                    (funcall real-featurep feature subfeature))))
               ((symbol-function 'require)
                (lambda (feature &optional filename noerror)
                  (if (eq feature 'markdown-mode)
                      nil
                    (funcall real-require feature filename noerror)))))
       ,@body)))

(ert-deftest yeah-markdown-absent-package-is-a-plain-text-noop ()
  "Without markdown-mode, Markdown syntax and buffer state stay untouched."
  (yeah-markdown-test--without-package
    (should-not (yeah-markdown-available-p))
    (with-temp-buffer
      (insert "# Заголовок\n\nТекст **важный** и `код`.")
      (set-buffer-modified-p nil)
      (let ((text (buffer-string))
            (tick (buffer-chars-modified-tick))
            (mode major-mode))
        (should-not (yeah-markdown-fontify-region (point-min) (point-max)))
        (should (equal (buffer-string) text))
        (should (= tick (buffer-chars-modified-tick)))
        (should (eq mode major-mode))
        (should-not (buffer-modified-p))
        (should-not (get-text-property (point-min) 'face))
        (should (string-search "**важный**" (buffer-string)))))))

(ert-deftest yeah-markdown-available-p-uses-the-optional-feature ()
  "A present markdown-mode feature with its entry point is detected."
  (let ((real-featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature &optional subfeature)
                 (if (eq feature 'markdown-mode)
                     t
                   (funcall real-featurep feature subfeature))))
              ((symbol-function 'markdown-mode) (lambda () nil)))
      (should (yeah-markdown-available-p)))))

(ert-deftest yeah-markdown-present-copies-only-face-properties ()
  "The present adapter fontifies a temporary copy, not the journal mode."
  (with-temp-buffer
    (insert "outside\n")
    (let ((beginning (point)))
      (insert "# Заголовок\nТекст")
      (let ((limit (point)))
        (insert "\noutside")
        (narrow-to-region beginning limit)
        (add-text-properties beginning limit
                             '(help-echo "keep" yeah-test-property "also-keep"))
        (fundamental-mode)
        (setq buffer-read-only t)
        (set-buffer-modified-p nil)
        (goto-char (+ beginning 2))
        (let ((mode major-mode)
              (point-before (point))
              (tick (buffer-chars-modified-tick))
              (text (buffer-string)))
          (cl-letf (((symbol-function 'yeah-markdown-available-p) (lambda () t))
                    ((symbol-function 'markdown-mode)
                     (lambda ()
                       (should (equal (buffer-string) "# Заголовок\nТекст"))
                       (should-not markdown-mode-hook)
                       (should-not text-mode-hook)
                       (should-not markdown-hide-markup)
                       (should-not markdown-fontify-code-blocks-natively)))
                    ((symbol-function 'font-lock-ensure)
                     (lambda (start end)
                       (should (= start (point-min)))
                       (should (= end (point-max)))
                       (add-text-properties
                        start (1+ start)
                        '(face markdown-header-face
                          font-lock-face markdown-header-face
                          invisible markdown-markup
                          display "hidden")))))
            (should (yeah-markdown-fontify-region beginning limit)))
          (should (equal (buffer-string) text))
          (should (eq major-mode mode))
          (should (= (point) point-before))
          (should (= (point-min) beginning))
          (should (= (point-max) limit))
          (should (= (buffer-chars-modified-tick) tick))
          (should buffer-read-only)
          (should-not (buffer-modified-p))
          (should (eq (get-text-property beginning 'face)
                      'markdown-header-face))
          (should (eq (get-text-property beginning 'font-lock-face)
                      'markdown-header-face))
          (should-not (get-text-property beginning 'invisible))
          (should-not (get-text-property beginning 'display))
          (should (equal (get-text-property beginning 'help-echo) "keep"))
          (should (equal (get-text-property beginning 'yeah-test-property)
                         "also-keep")))
        (widen)
        (should-not (get-text-property (point-min) 'face))))))

(ert-deftest yeah-markdown-present-provider-error-retains-plain-text ()
  "A failing optional provider cannot damage or hide the source text."
  (with-temp-buffer
    (insert "# Заголовок\n\nОбычный **текст**")
    (add-text-properties (point-min) (point-max) '(help-echo "unchanged"))
    (let ((mode major-mode)
          (text (buffer-string)))
      (cl-letf (((symbol-function 'yeah-markdown-available-p) (lambda () t))
                ((symbol-function 'markdown-mode)
                 (lambda () (error "mock fontification failure"))))
        (should-not (yeah-markdown-fontify-region (point-min) (point-max))))
      (should (equal (buffer-string) text))
      (should (eq major-mode mode))
      (should-not (get-text-property (point-min) 'face))
      (should (equal (get-text-property (point-min) 'help-echo)
                     "unchanged")))))

(ert-deftest yeah-markdown-empty-region-does-not-load-provider ()
  "An empty region is a no-op even when no Markdown package is installed."
  (with-temp-buffer
    (cl-letf (((symbol-function 'yeah-markdown-available-p)
               (lambda () (error "provider must not be probed"))))
      (should-not (yeah-markdown-fontify-region (point-min) (point-max))))))

(ert-deftest yeah-markdown-reversed-region-is-supported ()
  "Region bounds may be supplied in either order."
  (with-temp-buffer
    (insert "**текст**")
    (cl-letf (((symbol-function 'yeah-markdown-available-p) (lambda () t))
              ((symbol-function 'markdown-mode) (lambda () nil))
              ((symbol-function 'font-lock-ensure)
               (lambda (start _end)
                 (put-text-property start (1+ start) 'face 'bold))))
      (should (yeah-markdown-fontify-region (point-max) (point-min)))
      (should (eq (get-text-property (point-min) 'face) 'bold)))))

(ert-deftest yeah-markdown-rejects-region-outside-narrowing ()
  "The adapter never widens the user's buffer behind their back."
  (with-temp-buffer
    (insert "one\ntwo")
    (narrow-to-region (point-min) 4)
    (should-error (yeah-markdown-fontify-region (point-min) 5)
                  :type 'user-error)
    (should (= (point-max) 4))))

(provide 'test-yeah-markdown)
;;; test-yeah-markdown.el ends here
