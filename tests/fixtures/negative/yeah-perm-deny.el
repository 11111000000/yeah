;; Negative fixture: yeah-perm-deny
;;
;; A permission rule with effect `deny' (or `ask') makes the
;; corresponding `(action resource)' query raise `user-error'
;; from `yeah-perm-evaluate'. The exhaustive assertion lives in
;; tests/unit/test-yeah-perm.el.
;;
;; Example:
;;   (yeah-perm-rule-make "shell" "*" 'deny)
;;   (yeah-perm-evaluate "shell" "/bin/rm")
;;     ;; raises (user-error "deny: shell on /bin/rm")
(provide 'fixtures-negative-yeah-perm)