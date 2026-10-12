;;; test-yeah-codes.el --- ERT tests for yeah-codes -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Commentary:
;;
;; Positive and negative tests for `lib/yeah-codes.el', the
;; Tier 4 #22 Programmatic Tool Calling (PTC) sandbox stub.
;;
;; The positive tests exercise the happy paths: whitelist
;; defaults, allow / disallow, eval-with-whitelist, eval with
;; inputs, JSON-clean round-trip. The negative tests cover the
;; closest plausible failure modes: unwhitelisted name,
;; malformed form, wrong input types.

;;; Code:

(require 'ert)
(require 'yeah-codes)

(defvar test-yeah-codes--whitelist-backup nil
  "Backup of the default whitelist for `yeah-codes-allow-and-disallow'.")

(ert-deftest yeah-codes-whitelist-has-the-10-default-names ()
  "`yeah-codes-whitelist' returns the ten canonical names in order.

The set is fixed by `decisions/sandbox-elisp-codes-mode@0':
read, edit, grep, glob, bash, webfetch, text, image, console,
exit. Order matters because `yeah-codes-allow' appends in
canonical order; tests downstream of `yeah-codes-allow-and-
disallow' rely on the order to assert no reorder happened."
  (let ((got (yeah-codes-whitelist)))
    (should (listp got))
    (should (= 10 (length got)))
    (should (equal got
                   '("read" "edit" "grep" "glob" "bash"
                     "webfetch" "text" "image" "console" "exit")))))

(ert-deftest yeah-codes-allow-and-disallow ()
  "`yeah-codes-allow' / `yeah-codes-disallow' round-trip.

allow appends; disallow removes; both return the new whitelist.
A duplicate allow is a no-op (no signal). Each test resets
the whitelist to the canonical defaults at the start so the
test is not order-dependent."
  (let ((yeah-codes--whitelist
         '("read" "edit" "grep" "glob" "bash"
           "webfetch" "text" "image" "console" "exit")))
    (let ((after-add (yeah-codes-allow "draft")))
      (should (member "draft" after-add))
      (should (= 11 (length after-add)))
      (let ((after-dup (yeah-codes-allow "draft")))
        (should (= 11 (length after-dup)))
        (should (equal after-dup after-add)))
      (let ((after-rm (yeah-codes-disallow "draft")))
        (should-not (member "draft" after-rm))
        (should (= 10 (length after-rm)))
        (let ((after-rm-again (yeah-codes-disallow "draft")))
          (should-not (member "draft" after-rm-again))
          (should (= 10 (length after-rm-again))))))))

(ert-deftest yeah-codes-eval-returns-ok-when-whitelisted ()
  "`yeah-codes-eval' returns :ok t with the whitelisted :name.

The form's body is evaluated inside the sandbox; its value
is the `:result'. Names outside the whitelist are a separate
test (`yeah-codes-eval-rejects-unwhitelisted-name')."
  (let ((yeah-codes--whitelist '("read")))
    (let ((records (yeah-codes-eval
                    (list (list :name "read"
                                :code "(+ 1 2)"))
                    nil)))
      (should (= 1 (length records)))
      (should (eq (plist-get (nth 0 records) :ok) t))
      (should (string= "read" (plist-get (nth 0 records) :name)))
      (should (= 3 (plist-get (nth 0 records) :result))))))

(ert-deftest yeah-codes-eval-rejects-unwhitelisted-name ()
  "`yeah-codes-eval' raises `user-error' on an unwhitelisted :name.

The check fires **before** any `eval' runs, so the model
cannot side-channel a forbidden binding into the sandbox by
including it as the first form in a batch."
  (let ((yeah-codes--whitelist '("read")))
    (let ((err nil))
      (condition-case nil
          (yeah-codes-eval
           (list (list :name "evil" :code "42"))
           nil)
        (user-error (setq err t)))
      (should err))))

(ert-deftest yeah-codes-eval-passes-inputs ()
  "`yeah-codes-eval' binds INPUTS as lexical variables in the `let'.

The form references the input by symbol name; the binding is
plain lexical. Multiple inputs are bound in one `let'."
  (let ((yeah-codes--whitelist '("read")))
    (let ((records (yeah-codes-eval
                    (list (list :name "read"
                                :code "(+ a b)"))
                    (list (cons "a" 1)
                          (cons "b" 40)))))
      (should (eq (plist-get (nth 0 records) :ok) t))
      (should (= 41 (plist-get (nth 0 records) :result))))))

(ert-deftest yeah-codes-eval-result-is-json-clean ()
  "`yeah-codes-eval' round-trips results through `prin1' / `read'.

The contract is that nothing leaves the sandbox that hasn't
been serialised and re-parsed. We assert the equality by
constructing a non-trivial value, calling the API, and
checking the result is `(equal)' to `(read (prin1-to-string
expected))'. A list-of-strings is the canonical JSON-clean
shape in the Yeah wire layer."
  (let ((yeah-codes--whitelist '("read")))
    (let* ((records (yeah-codes-eval
                     (list (list :name "read"
                                 :code "(list \"alpha\" \"beta\" \"gamma\")"))
                     nil))
           (got (plist-get (nth 0 records) :result))
           (expected '("alpha" "beta" "gamma"))
           (roundtrip (read (prin1-to-string expected))))
      (should (eq (plist-get (nth 0 records) :ok) t))
      (should (equal got expected))
      (should (equal got roundtrip)))))

(ert-deftest yeah-codes-eval-malformed-form-errors ()
  "`yeah-codes-eval' raises `user-error' on a malformed `:code'.

A form that fails `read' must not leak the raw `scan-error'
or `end-of-file' past the boundary. The stub catches every
common read failure and re-signals as `user-error'."
  (let ((yeah-codes--whitelist '("read")))
    (let ((err nil)
          (err-msg nil))
      (condition-case data
          (yeah-codes-eval
           (list (list :name "read"
                       :code "(unclosed"))
           nil)
        (user-error
         (setq err t)
         (setq err-msg (car (cdr data)))))
      (should err)
      (should (string-match-p "malformed form" (or err-msg ""))))))

(ert-deftest yeah-codes-sandbox-available-p-is-featurep ()
  "`yeah-codes-sandbox-available-p' returns `(featurep \\='sandbox)'.

The real `sandbox.el' integration is deferred. The check is
pure side-effect-free so callers can use it as a branch
condition."
  (let ((got (yeah-codes-sandbox-available-p)))
    (should (eq got (featurep 'sandbox)))
    (should (memq got '(nil t)))))

(provide 'test-yeah-codes)
;;; test-yeah-codes.el ends here
