;; Positive fixture: yeah-compact-cut walks the session log from
;; oldest to newest, accumulates a prin1-length budget per record,
;; and returns the id of the first record whose running total
;; crosses the target. Records before the cut are summarised;
;; records from the cut onwards are preserved verbatim.
;;
;; Run:
;;   emacs -Q --batch -L lib -l tests/unit/test-yeah-compact.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Expected: 7 tests pass.
(provide 'fixtures-positive-yeah-compact)