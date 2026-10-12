;; Negative fixture: yeah-codes-eval-forbidden
;;
;; A PTC sandbox evaluation that the whitelist gate must
;; reject. An unwhitelisted `:name' raises `user-error'
;; before any `eval' runs. The exhaustive assertion lives in
;; `tests/unit/test-yeah-codes.el' under
;; `yeah-codes-eval-rejects-unwhitelisted-name' and
;; `yeah-codes-eval-malformed-form-errors'.
;;
;; Example (raises `user-error' before any `eval'):
;;   (let ((yeah-codes--whitelist '("read")))
;;     (yeah-codes-eval
;;      (list (list :name "evil" :code "42"))
;;      nil))
;;     ;; => user-error: yeah-codes-eval: form #1: "evil" is not in the whitelist
(provide 'fixtures-negative-yeah-codes)
