;; Positive fixture: yeah-codes-eval
;;
;; A PTC sandbox evaluation that passes the whitelist gate
;; and round-trips through the JSON-clean boundary. The
;; exhaustive assertion lives in
;; `tests/unit/test-yeah-codes.el' under
;; `yeah-codes-eval-returns-ok-when-whitelisted',
;; `yeah-codes-eval-passes-inputs', and
;; `yeah-codes-eval-result-is-json-clean'.
;;
;; Example (an `eval' against the API):
;;   (let ((yeah-codes--whitelist '("read")))
;;     (yeah-codes-eval
;;      (list (list :name "read" :code "(+ a 1)"))
;;      (list (cons "a" 41))))
;;     ;; => ((:name "read" :result 42 :ok t))
(provide 'fixtures-positive-yeah-codes)
