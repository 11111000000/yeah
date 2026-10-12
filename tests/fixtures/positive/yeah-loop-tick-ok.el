;; Positive fixture: yeah-loop-tick accepts the 18 contract labels
;; from their respective source states. The exhaustive assertion
;; lives in tests/unit/test-yeah-loop.el.
;;
;; Run:
;;   emacs -Q --batch -L lib -l tests/unit/test-yeah-loop.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Expected: 13 tests pass (9 positive + 4 negative).
(provide 'fixtures-positive-yeah-loop)
