;;; tests/fixtures/negative/yeah-gptel-prompt-without-prelude.el ---
;;; negative fixture for `lib/yeah-gptel.el'.
;;;
;;; The negative fixture documents the contract that a prompt
;;; *without* the prelude is a drift: any caller that bypasses
;;; `yeah-gptel-prompt-transform' and hands gptel a raw prompt
;;; has skipped the tools / FSM / manifesto section, and is
;;; therefore missing the constraints Yeah relies on the model
;;; to honour.
;;;
;;; Expected rejected shape:
;;;
;;;     <original-prompt>          ;; no prelude
;;;
;;; Verified indirectly via the symmetric test
;;; `yeah-gptel-prompt-transform-appends-prelude' in
;;; `tests/unit/test-yeah-gptel.el', which asserts the
;;; prelude *is* present. The fixture itself is documentary at
;;; this revision; Tier 3 will exercise the full
;;; `gptel-request' round-trip and assert a raw prompt is
;;; rejected at the boundary.
;;;
;;; Copyright (C) 2026  Petr Kosov
;;;
;;; This file is part of Yeah.

;;; Code:

;; Intentionally empty. See the header commentary for the
;; contract this fixture documents.

;;; yeah-gptel-prompt-without-prelude.el ends here