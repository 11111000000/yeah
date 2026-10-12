;; Negative fixture: when the budget is large enough to hold every
;; record, `yeah-compact-cut-point' returns nil and `yeah-compact-run'
;; is a no-op (no compaction record is appended). This is the closest
;; plausible failure mode to the happy path: a tight but valid
;; cut-point is a pass; an over-budget request is also a pass, but
;; it is a no-op rather than an error.
(provide 'fixtures-negative-yeah-compact)