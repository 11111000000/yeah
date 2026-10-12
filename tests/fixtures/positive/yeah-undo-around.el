;; Positive fixture: yeah-undo-around.el
;;
;; The per-tick undo-boundary wrapper records a `(undo-boundary)'
;; marker in the buffer before and after the thunk runs, so that
;; `M-x undo' (or programmatic `undo') reverts the change cleanly.
;; This fixture pins the closest plausible positive case: a buffer
;; modified by a thunk should have a recoverable boundary in its
;; `buffer-undo-list'.
;;
;; The exhaustive assertion lives in
;; `tests/unit/test-yeah-undo.el':
;;
;;   * yeah-undo-around-buffer-places-boundary
;;   * yeah-undo-around-buffer-runs-thunk
;;   * yeah-undo-around-file-opens-buffer
;;   * yeah-undo-around-file-uses-existing-buffer
;;   * yeah-undo-list-size-grows-by-two-after-around-buffer
;;
;; Example:
;;   (yeah-undo-around-buffer (current-buffer)
;;     (lambda () (insert "hello\n")))
;;     ;; the buffer's `buffer-undo-list' now contains
;;     ;; two `(undo-boundary)' markers around the insert.
(provide 'fixtures-positive-yeah-undo)