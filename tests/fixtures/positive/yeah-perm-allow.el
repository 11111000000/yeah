;; Positive fixture: yeah-perm-allow
;;
;; A permission rule with effect `allow' lets the corresponding
;; `(action resource)' query through `yeah-perm-evaluate' with
;; return value `:allow'. The exhaustive assertion lives in
;; tests/unit/test-yeah-perm.el.
;;
;; Example:
;;   (yeah-perm-rule-make "edit" "/tmp/foo.el" 'allow)
;;   (yeah-perm-evaluate "edit" "/tmp/foo.el")
;;     ;; => :allow
(provide 'fixtures-positive-yeah-perm)