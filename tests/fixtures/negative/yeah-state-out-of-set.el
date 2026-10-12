;; Negative fixture: yeah-state-p must reject every symbol that
;; is not in the 10-element contract list.
;;
;; Run:
;;   emacs -Q --batch -l tests/unit/test-yeah-state.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Expected: the test `yeah-state-p-rejects-symbols-outside-the-set'
;; passes. The other negative tests
;; (`yeah-state-terminal-p-rejects-non-states',
;; `yeah-state-list-has-exactly-10-states') also pass.
(provide 'fixtures-negative-yeah-state)
