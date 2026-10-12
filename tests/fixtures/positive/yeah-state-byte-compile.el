;; Positive fixture: byte-compile-clean for lib/yeah-state.el.
;;
;; Run:
;;   emacs -Q --batch -l scripts/dev byte-compile-all
;;
;; Expected: exit 0; "yeah-state.el: clean" on stdout.
;;
;; The actual byte-compile check is wired in Tier 1 of ROADMAP.md
;; (decision `elisp-toolchain-only@0'). This fixture file is a
;; placeholder until that decision lands.
(provide 'fixtures-positive-yeah-state)
