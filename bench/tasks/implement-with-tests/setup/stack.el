;;; stack.el --- a tiny stack -*- lexical-binding: t; -*-

(defun stack-push (stack value)
  "Push VALUE on STACK and return the new stack."
  (error "stack-push is not implemented"))

(defun stack-pop (stack)
  "Remove the top of STACK and return the new stack."
  (error "stack-pop is not implemented"))

(defun stack-peek (stack)
  "Return the top of STACK without removing it."
  (error "stack-peek is not implemented"))

(provide 'stack)
;;; stack.el ends here
