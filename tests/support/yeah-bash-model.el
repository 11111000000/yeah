;;; yeah-bash-model.el --- the fake model that calls the bash tool -*- lexical-binding: t; no-byte-compile: t -*-

;;; Commentary:
;;
;; The check of the mode without a person needs a model that calls the tool
;; the person was asked about most often: the `bash' tool.  In the `build'
;; mode the client is asked about it, and in the `auto' mode nobody is asked.
;; The model of this file is a FAKE.
;;
;; The model runs one command per turn: the answer asks for the `bash` tool,
;; and the answer that ends the run comes from the callback of that tool.  The
;; command writes a marker by its relative name, so that the marker lands in
;; the directory of the session and not in the directory of the process.
;;
;; The file is loaded, not required: it defines the transport of the model and
;; the check names it.  The server process of the check loads it too, so that
;; the check and the server run the same model.

;;; Code:

(defvar yeah-bash-model--calls 0
  "How many times the fake model of the checks answered.")

(defun yeah-bash-model--finish ()
  "Return the answer that ends the run of the fake model.
The answer is a call of the `finish' tool: a supervised run does not end
with words (wave 53)."
  (list 'tool-call
        (list (list :name "finish")
              (list "the model of the check is done")
              (lambda (_value) nil))))

(defun yeah-bash-model--bash (callback)
  "Return the answer that asks for the `bash' tool.
The command writes a marker by its relative name, so that the marker lands
in the directory of the session.  The tool of the call answers with the
answer that ends the run: the turn of a model ends when the tool it asked
for has answered."
  (list 'tool-call
        (list (list :name "bash")
              (list "printf 'bash-ok\\n' > marker.txt")
              (lambda (_value)
                (funcall callback (yeah-bash-model--finish))))))

(defun yeah-bash-model-transport (prompt callback)
  "Call the `bash' tool and end the run.
PROMPT is what the turn asked; CALLBACK takes the answer in the shape
gptel uses."
  (setq yeah-bash-model--calls (1+ yeah-bash-model--calls))
  (funcall callback (yeah-bash-model--bash callback)))

(provide 'yeah-bash-model)
;;; yeah-bash-model.el ends here
