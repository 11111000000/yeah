;; Negative fixture: the append-only log forbids delete and rewrite.
;; `yeah-session-delete' and `yeah-session-rewrite' are deliberately
;; not defined; calling either is a compile-time error
;; (`void-function'). The exhaustive assertion lives in
;; tests/unit/test-yeah-session.el (`yeah-session-no-delete-or-rewrite-api').
(provide 'fixtures-negative-yeah-session)