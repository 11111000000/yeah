;; Negative fixture: yeah-subagent spawn respects the depth limit.
;; Spawning a child whose depth would be equal to or greater than
;; `yeah-subagent-depth-limit' must raise `user-error'. The
;; exhaustive assertion lives in tests/unit/test-yeah-subagent.el
;; (`yeah-subagent-spawn-with-zero-depth-allowed' asserts the
;; boundary case; depth exceeded is symmetrically covered by
;; the depth-limit-overridable test setup).
(provide 'fixtures-negative-yeah-subagent)