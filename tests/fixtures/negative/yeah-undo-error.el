;; Negative fixture: yeah-undo-error.el
;;
;; The closest plausible failure mode is a thunk that signals an
;; error mid-edit. The A3 invariant requires the boundary still
;; to be recorded so a single `undo' can revert whatever change
;; the partial thunk did. The exhaustive assertion lives in
;; `tests/unit/test-yeah-undo.el':
;;
;;   * yeah-undo-around-buffer-thunk-error-still-records-boundary
;;
;; A naive implementation that places `(undo-boundary)' only on
;; the happy path would leave the buffer partially mutated with
;; no clean undo target, which is the A3 violation this fixture
;; is designed to detect.
(provide 'fixtures-negative-yeah-undo)