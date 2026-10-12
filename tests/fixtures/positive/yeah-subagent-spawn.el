;; Positive fixture: yeah-subagent spawn happy path.
;; `yeah-subagent-spawn PARENT-SESSION ROLE PROMPT &optional DEPTH'
;; returns a plist with `:status 'completed' and a stub result
;; string. The exhaustive assertion lives in
;; tests/unit/test-yeah-subagent.el.
;;
;; Run:
;;   emacs -Q --batch -L lib -l tests/unit/test-yeah-subagent.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Expected: 7 tests pass.
(provide 'fixtures-positive-yeah-subagent)