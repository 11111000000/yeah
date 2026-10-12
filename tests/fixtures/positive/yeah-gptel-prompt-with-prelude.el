;;; tests/fixtures/positive/yeah-gptel-prompt-with-prelude.el ---
;;; positive fixture for `lib/yeah-gptel.el'.
;;;
;;; The positive fixture documents the contract that the
;;; transformed prompt produced by
;;; `yeah-gptel-prompt-transform' is *the prelude concatenated
;;; with the user's prompt*. A reviewer reading this file
;;; should see exactly what shape a well-formed transformed
;;; prompt is expected to take.
;;;
;;; Expected transformed shape:
;;;
;;;     <yeah-gptel-prelude><original-prompt>
;;;
;;; where `<yeah-gptel-prelude>' is the value of the defcustom
;;; `yeah-gptel-prelude' (tools, FSM states, manifesto) and
;;; `<original-prompt>' is whatever the user/gptel passed.
;;;
;;; Verified indirectly via the assertion
;;; `yeah-gptel-prompt-transform-appends-prelude' in
;;; `tests/unit/test-yeah-gptel.el'. The fixture itself is
;;; documentary at this revision; Tier 3 will exercise the
;;; full `gptel-request' round-trip.
;;;
;;; Copyright (C) 2026  Petr Kosov
;;;
;;; This file is part of Yeah.

;;; Code:

;; Intentionally empty. See the header commentary for the
;; contract this fixture documents.

;;; yeah-gptel-prompt-with-prelude.el ends here