;;; yeah-session-outcome-model.el --- the fake model of the checks of the outcome -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; The check of the outcome of a run needs a model that never finishes: it
;; describes its next step and calls no tool.  The kernel nudges it, and the
;; budget of the nudges runs out, and the run ends without an effect -- which
;; is exactly the run whose outcome the orchestrator must see.
;;
;; The model here is a FAKE (the model is a FAKE).  The file is loaded and not
;; required: the service loads it in its own Emacs, and the check names it.

;;; Code:

(defun yeah-session-outcome-model-transport (prompt callback)
  "Describe the next step of the run and call no tool.
PROMPT is the prompt of the run and CALLBACK takes the answer of the model.
The model talks and never acts, so the kernel spends its nudges on it and the
run ends without an effect."
  (funcall callback "I will write the file now."))

(provide 'yeah-session-outcome-model)
;;; yeah-session-outcome-model.el ends here
