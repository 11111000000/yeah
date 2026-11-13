;;; test-yeah-faces.el --- ERT tests for yeah-faces -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-faces)

(defconst yeah-faces-test--semantic-faces
  '(yeah-faces-user-heading
    yeah-faces-assistant-heading
    yeah-faces-metadata
    yeah-faces-dimmed
    yeah-faces-tool-name
    yeah-faces-pending
    yeah-faces-running
    yeah-faces-success
    yeah-faces-warning
    yeah-faces-error
    yeah-faces-code
    yeah-faces-output
    yeah-faces-key-hint
    yeah-faces-button))

(defmacro yeah-faces-test--with-mock-icons (glyph &rest body)
  "Run BODY with a displayable mock icon provider returning GLYPH."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'display-multi-font-p) (lambda () t))
             ((symbol-function 'char-displayable-p) (lambda (_glyph) t))
             ((symbol-function 'yeah-faces--icon-provider)
              (lambda ()
                (lambda (_name &rest args)
                  (propertize ,glyph
                              'face (plist-get args :face)
                              'display '(raise 0))))))
     ,@body))

(ert-deftest yeah-faces-icons-defaults-to-auto ()
  "Icons are opportunistic by default and have a Customize type."
  (should (eq (default-value 'yeah-icons) 'auto))
  (should (get 'yeah-icons 'custom-type)))

(ert-deftest yeah-faces-all-semantic-faces-inherit-without-colors ()
  "Every semantic face inherits standard styling on light and dark frames."
  (dolist (background '(light dark))
    (let ((frame-background-mode background))
      (dolist (face yeah-faces-test--semantic-faces)
        (should (facep face))
        (let* ((definition (get face 'face-defface-spec))
               (selected (face-spec-choose definition)))
          (should definition)
          (should (plist-get selected :inherit))
          (should-not (plist-get selected :foreground))
          (should-not (plist-get selected :background))
          (should-not (plist-get selected :color)))))))

(ert-deftest yeah-faces-icon-provider-tries-the-optional-feature ()
  "The icon adapter asks for nerd-icons and tolerates its absence."
  (let ((real-featurep (symbol-function 'featurep))
        (real-require (symbol-function 'require))
        requested)
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature &optional subfeature)
                 (if (eq feature 'nerd-icons)
                     nil
                   (funcall real-featurep feature subfeature))))
              ((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (if (eq feature 'nerd-icons)
                     (progn
                       (setq requested feature)
                       nil)
                   (funcall real-require feature filename noerror)))))
      (should-not (yeah-faces--icon-provider))
      (should (eq requested 'nerd-icons)))))

(ert-deftest yeah-faces-label-has-text-without-icon-package ()
  "A missing icon package leaves a complete propertized text label."
  (let ((yeah-icons 'auto))
    (cl-letf (((symbol-function 'display-multi-font-p) (lambda () t))
              ((symbol-function 'yeah-faces--icon-provider) (lambda () nil)))
      (let ((rendered (yeah-faces-label 'user "Пользователь")))
        (should (equal (substring-no-properties rendered) "Пользователь"))
        (should (eq (get-text-property 0 'face rendered)
                    'yeah-faces-user-heading))
        (should (equal (get-text-property 0 'help-echo rendered)
                       "Пользователь"))))))

(ert-deftest yeah-faces-label-uses-a-mock-icon-provider ()
  "A displayable provider icon decorates rather than replaces the label."
  (let ((yeah-icons 'auto))
    (yeah-faces-test--with-mock-icons "●"
      (let ((rendered (yeah-faces-label 'assistant "Ассистент")))
        (should (equal (substring-no-properties rendered) "● Ассистент"))
        (should (equal (get-text-property 0 'display rendered) '(raise 0)))
        (should (eq (get-text-property (1- (length rendered)) 'face rendered)
                    'yeah-faces-assistant-heading))
        (should (equal (get-text-property 0 'help-echo rendered)
                       "Ассистент"))))))

(ert-deftest yeah-faces-never-does-not-probe-icon-provider ()
  "The never setting avoids optional package and display probing."
  (let ((yeah-icons 'never))
    (cl-letf (((symbol-function 'display-multi-font-p)
               (lambda () (error "display must not be probed")))
              ((symbol-function 'yeah-faces--icon-provider)
               (lambda () (error "provider must not be loaded"))))
      (should (equal (substring-no-properties
                      (yeah-faces-label 'tool "Чтение"))
                     "Чтение")))))

(ert-deftest yeah-faces-terminal-display-falls-back-to-text ()
  "A display without multiple fonts never loads the icon provider."
  (let ((yeah-icons 'auto))
    (cl-letf (((symbol-function 'display-multi-font-p) (lambda () nil))
              ((symbol-function 'yeah-faces--icon-provider)
               (lambda () (error "provider must not be loaded"))))
      (should (equal (substring-no-properties
                      (yeah-faces-label 'user "Пользователь"))
                     "Пользователь")))))

(ert-deftest yeah-faces-nondisplayable-glyph-falls-back-to-text ()
  "A glyph rejected by char-displayable-p is not inserted."
  (let ((yeah-icons 'auto))
    (cl-letf (((symbol-function 'display-multi-font-p) (lambda () t))
              ((symbol-function 'char-displayable-p) (lambda (_glyph) nil))
              ((symbol-function 'yeah-faces--icon-provider)
               (lambda ()
                 (lambda (_name &rest _args) "\xeb99"))))
      (should (equal (substring-no-properties
                      (yeah-faces-status 'running "Выполняется"))
                     "Выполняется")))))

(ert-deftest yeah-faces-label-empty-values-have-readable-fallbacks ()
  "Nil, empty and whitespace labels never become icon-only strings."
  (let ((yeah-icons 'never))
    (dolist (label '(nil "" " \t\n"))
      (should (equal (substring-no-properties
                      (yeah-faces-label 'user label))
                     "User")))
    (let ((unknown (yeah-faces-label 'future-kind nil)))
      (should (equal (substring-no-properties unknown) "Future Kind"))
      (should (eq (get-text-property 0 'face unknown) 'default)))
    (should (equal (substring-no-properties
                    (yeah-faces-label 'assistant nil 'never))
                   "Assistant"))))

(ert-deftest yeah-faces-literal-icon-can-be-suppressed-per-call ()
  "The per-call never override retains the label without decoration."
  (let ((yeah-icons 'auto))
    (cl-letf (((symbol-function 'display-multi-font-p) (lambda () t))
              ((symbol-function 'char-displayable-p) (lambda (_glyph) t)))
      (should (equal (substring-no-properties
                      (yeah-faces-label 'code "Код" 'never))
                     "Код")))))

(ert-deftest yeah-faces-status-covers-run-and-tool-states ()
  "Known states retain explicit text and map to their semantic faces."
  (let ((yeah-icons 'never))
    (dolist (case '((pending "Pending" yeah-faces-pending)
                    (awaiting-tool "Awaiting Tool" yeah-faces-running)
                    (completed "Completed" yeah-faces-success)
                    (cancelled "Cancelled" yeah-faces-warning)
                    (failed "Failed" yeah-faces-error)
                    (future-state "Future State" yeah-faces-metadata)
                    (nil "Unknown" yeah-faces-metadata)))
      (let ((rendered (yeah-faces-status (nth 0 case))))
        (should (equal (substring-no-properties rendered) (nth 1 case)))
        (should (eq (get-text-property 0 'face rendered) (nth 2 case)))
        (should (equal (get-text-property 0 'help-echo rendered)
                       (format "State: %s" (nth 1 case))))))))

(ert-deftest yeah-faces-status-empty-label-keeps-state-text ()
  "An empty override cannot erase the status."
  (let ((yeah-icons 'never))
    (should (equal (substring-no-properties (yeah-faces-status 'done ""))
                   "Done"))
    (should (equal (substring-no-properties (yeah-faces-status nil " \t"))
                   "Unknown"))))

(ert-deftest yeah-faces-status-with-mock-icon-still-has-state-text ()
  "Color and an icon are never the only status indicators."
  (let ((yeah-icons 'auto))
    (yeah-faces-test--with-mock-icons "✓"
      (let ((rendered (yeah-faces-status 'success "Готово")))
        (should (equal (substring-no-properties rendered) "✓ Готово"))
        (should (eq (get-text-property (1- (length rendered)) 'face rendered)
                    'yeah-faces-success))
        (should (equal (get-text-property 0 'help-echo rendered)
                       "State: Готово"))))))

(ert-deftest yeah-faces-metadata-is-narrow-and-cyrillic-safe ()
  "Metadata truncates by display width and keeps the full text in help."
  (let ((rendered (yeah-faces-metadata
                   "  session-42\nМодель: русский текст  " 12)))
    (should (<= (string-width rendered) 12))
    (should (string-suffix-p "…" (substring-no-properties rendered)))
    (should (equal (get-text-property 0 'help-echo rendered)
                   "session-42 Модель: русский текст"))
    (should (eq (get-text-property 0 'face rendered) 'yeah-faces-metadata))
    (should-not (string-match-p "[\n\r]" rendered))))

(ert-deftest yeah-faces-metadata-empty-and-unbounded-cases ()
  "Unbounded metadata keeps Cyrillic text and empty metadata has a label."
  (should (equal (substring-no-properties
                  (yeah-faces-metadata "Модель: тест"))
                 "Модель: тест"))
  (should (equal (substring-no-properties (yeah-faces-metadata " \n"))
                 "Details"))
  (should-error (yeah-faces-metadata "x" 0) :type 'user-error))

(ert-deftest yeah-faces-button-is-local-functional-and-accessible ()
  "A returned text button works without changing the global keymap."
  (let ((calls 0)
        (global-map (current-global-map)))
    (let ((rendered (yeah-faces-button
                     "Разрешить"
                     (lambda () (setq calls (1+ calls))))))
      (should (equal (substring-no-properties rendered) "Разрешить"))
      (should (eq (get-text-property 0 'face rendered) 'yeah-faces-button))
      (should (get-text-property 0 'keymap rendered))
      (should (string-match-p "Разрешить"
                              (get-text-property 0 'help-echo rendered)))
      (with-temp-buffer
        (insert rendered)
        (goto-char (point-min))
        (push-button))
      (should (= calls 1))
      (should (eq global-map (current-global-map))))))

(ert-deftest yeah-faces-button-empty-label-and-invalid-action ()
  "Buttons retain a nonempty label and reject a non-function action."
  (should (equal (substring-no-properties
                  (yeah-faces-button nil (lambda () nil)))
                 "Action"))
  (should-error (yeah-faces-button "Bad" nil) :type 'user-error))

(provide 'test-yeah-faces)
;;; test-yeah-faces.el ends here
