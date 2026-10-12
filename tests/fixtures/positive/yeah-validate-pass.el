;; Positive fixture: yeah-validate passes on the current tree.
;; Run: `emacs -Q --batch -L lib -l lib/yeah-validate.el
;;            -l tests/unit/test-yeah-validate.el
;;            -f ert-run-tests-batch-and-exit`
;; Expected: 2/2 tests pass.
(provide 'fixtures-positive-yeah-validate)
