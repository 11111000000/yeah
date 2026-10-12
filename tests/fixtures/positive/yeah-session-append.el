;; Positive fixture: yeah-session append-only log exercises the
;; happy path (open, append, project, record-compaction). The
;; exhaustive assertion lives in tests/unit/test-yeah-session.el.
;;
;; Run:
;;   emacs -Q --batch -L lib -l tests/unit/test-yeah-session.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Expected: 7 tests pass.
(provide 'fixtures-positive-yeah-session)