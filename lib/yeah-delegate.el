;;; yeah-delegate.el --- delegate a task to a child agent -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; The model hands a task to a child agent, named by an agent preset
;; (D8).  The child runs in a session of its own, with the model, the
;; tools and the instructions of the preset, and with nothing else.
;;
;; The parent is not held while the child works: the `delegate' tool
;; answers with the id of the child at once, and the model asks for what
;; became of the child with the `delegate-result' tool.
;;
;; A delegation is an effect, and the permission system has an opinion
;; about it: the Plan profile denies it, so that a plan cannot reach the
;; world through a child.  The Build profile asks the person.
;;
;; The child of a delegation is unattended.  The rules of the child allow
;; the tools of the preset and nothing else, so the child never asks a
;; question, and it never uses a tool of its own.
;;
;; The tools of this module are registered when the module is loaded, and
;; not through `yeah-builtins-specs': the built-ins are the tools of the
;; kernel, and this module needs the run and the session of Yeah, which
;; the kernel of the tools must not depend on.

;;; Code:

(require 'cl-lib)
(require 'yeah-agent)
(require 'yeah-events)
(require 'yeah-gptel)
(require 'yeah-result)
(require 'yeah-subagent)
(require 'yeah-tools)

(defconst yeah-delegate--tool-names '("delegate" "delegate-result")
  "The names of the tools of delegation.")

(defvar yeah-delegate--dispatch-queue nil
  "The journals of the runs whose allowed delegations are waiting to run.
The observer of this module remembers them; see `yeah-delegate--observe'.
The queue is a queue and not a counter: two runs may delegate at the same
time, and the journal of one of them must not be taken for the other.")

(defvar yeah-delegate--children (make-hash-table :test 'equal)
  "The children this Emacs delegated, by the id of their session.")

(defvar yeah-delegate--depths (make-hash-table :test 'equal)
  "The depth of every delegated child, by the id of its session.")

(defvar yeah-delegate--transport-factory nil
  "The factory of the transport of a child, or nil for the default.
A factory is called with the model, the instructions and the tools of
the child, and returns the transport of the child.  The tests replace
it; the default reaches the model through gptel.")

(defun yeah-delegate--observe (session type fields _id)
  "Note the allowed delegation of SESSION, so that the tool finds its journal.
TYPE is the type of the event, FIELDS the fields it carries."
  (when (and (equal type "permission-decision")
             (equal (plist-get fields :effect) "allow")
             (member (plist-get fields :action) yeah-delegate--tool-names))
    (setq yeah-delegate--dispatch-queue
          (append yeah-delegate--dispatch-queue (list session)))))

(defun yeah-delegate--install-observer ()
  "Install the observer that lets a delegate tool find the journal of its run."
  (unless (memq #'yeah-delegate--observe yeah-events-write-functions)
    (add-to-list 'yeah-events-write-functions #'yeah-delegate--observe)))

(defun yeah-delegate--take-session ()
  "Return the journal of the run whose allowed call is waiting to run.
Return nil when no allowed call is waiting."
  (when yeah-delegate--dispatch-queue
    (let ((session (car yeah-delegate--dispatch-queue)))
      (setq yeah-delegate--dispatch-queue
            (cdr yeah-delegate--dispatch-queue))
      session)))

(defun yeah-delegate--current-session ()
  "Return the journal the delegate tools act on.
The journal of the run whose allowed call is waiting to run is used.
A call with no such journal is refused: there is no journal to write into."
  (or (yeah-delegate--take-session)
      (signal 'user-error
              (list "delegate: this call has no journal: the run did not bind one"))))

(defun yeah-delegate--preset (name)
  "Return the preset NAME with its instructions.
Signal `user-error' when no preset of that name exists; the message names the
presets that do exist, because a model that named a wrong one has to learn
the right name."
  (let ((preset (yeah-agent-load name)))
    (unless preset
      (signal 'user-error
              (list (format "delegate: no agent named %S; the agents are: %s"
                            name
                            (if (yeah-agent-names)
                                (string-join (yeah-agent-names) ", ")
                              "none")))))
    preset))

(defun yeah-delegate--count (value)
  "Return VALUE as a number, or nil when it is not one.
Only a string of digits is a number: `string-to-number' reads \"abc\" as zero,
and a zero that was never written is not a budget."
  (when (and (stringp value) (string-match-p "\\`[0-9]+\\'" value))
    (string-to-number value)))

(defun yeah-delegate--budget (preset)
  "Return the context budget of the child of PRESET, or nil when it names none."
  (let ((number (yeah-delegate--count (plist-get preset :budget))))
    (when (and number (> number 0)) number)))

(defun yeah-delegate--allowed-depth (preset)
  "Return the depth the children of PRESET may reach, or nil when it names none."
  (let ((number (yeah-delegate--count (plist-get preset :depth))))
    (when (and number (>= number 0)) number)))

(defun yeah-delegate--depth-of (session)
  "Return the depth of SESSION in the tree of delegations.
The run that started the tree is at the depth zero."
  (or (gethash (plist-get session :id) yeah-delegate--depths) 0))

(defun yeah-delegate--check-depth (preset depth)
  "Refuse the delegation of PRESET when the child would be deeper than it allows.
DEPTH is the depth the child would have."
  (let ((allowed (yeah-delegate--allowed-depth preset)))
    (when (and allowed (> depth allowed))
      (signal 'user-error
              (list (format "delegate: the agent %S allows the depth %d, and this child is at the depth %d"
                            (or (plist-get preset :name) "child")
                            allowed depth))))))

(defun yeah-delegate--system (preset)
  "Return the system prompt of the child of PRESET.
The prelude of Yeah says how a model of Yeah acts, and the body of the preset
says who the child is."
  (let ((body (string-trim (or (plist-get preset :prompt) ""))))
    (if (string-empty-p body)
        yeah-gptel-prelude
      (concat yeah-gptel-prelude "\n\n" body))))

(defun yeah-delegate--gptel-transport (model system tools)
  "Return the transport of a child that runs on MODEL with SYSTEM.
TOOLS are the names of the tools the child may use."
  (lambda (prompt callback)
    (yeah-gptel-request prompt callback
                        :model model
                        :system system
                        :tools (mapcar #'yeah-gptel-tool-for tools))))

(defun yeah-delegate--transport (model system tools)
  "Return the transport of the child that runs on MODEL with SYSTEM.
TOOLS are the names of the tools the child may use."
  (if yeah-delegate--transport-factory
      (funcall yeah-delegate--transport-factory model system tools)
    (yeah-delegate--gptel-transport model system tools)))

(defun yeah-delegate--id (record)
  "Return the id of the session of the child RECORD."
  (plist-get (plist-get record :child-session) :id))

(defun yeah-delegate--start (session preset task)
  "Start the child of PRESET on TASK in the session of the parent SESSION.
Return the record of the child."
  (let* ((tools (plist-get preset :tools))
         (model (plist-get preset :model))
         (system (yeah-delegate--system preset))
         (depth (1+ (yeah-delegate--depth-of session)))
         (record nil))
    (yeah-delegate--check-depth preset depth)
    (setq record (yeah-subagent-spawn
                  session
                  (or (plist-get preset :name) "child")
                  task
                  :depth (yeah-delegate--depth-of session)
                  :tools tools
                  :budget (yeah-delegate--budget preset)
                  :transport (yeah-delegate--transport model system tools)))
    (puthash (yeah-delegate--id record) record yeah-delegate--children)
    (puthash (yeah-delegate--id record) depth yeah-delegate--depths)
    record))

(defun yeah-delegate--status-of (record)
  "Return the status of the child RECORD, as a string.
The child may have ended while the tool was on its way back; the status that
the model reads is the status of the child now, not the status it had when
the child was started."
  (let ((status (plist-get record :status)))
    (if (eq status 'running)
        "running"
      (format "%s" status))))

(defun yeah-delegate--delegate (agent task)
  "Start the child of the preset AGENT on TASK and return the result of the tool.
The child works while the parent does: the tool answers at once, with the id
of the child."
  (let* ((session (yeah-delegate--current-session))
         (preset (yeah-delegate--preset agent))
         (record (yeah-delegate--start session preset task))
         (id (yeah-delegate--id record)))
    (yeah-result-ok
     (format "the child %s works on the task while you keep working" id)
     (list :id id
           :agent (or (plist-get preset :name) agent)
           :status (yeah-delegate--status-of record)))))

(defun yeah-delegate--result (child)
  "Report what became of the child CHILD."
  (let ((record (gethash child yeah-delegate--children)))
    (unless record
      (signal 'user-error
              (list (format "delegate-result: no child %S" child))))
    (let ((status (plist-get record :status))
          (answer (or (plist-get record :result) "")))
      (cond ((eq status 'running)
             (yeah-result-ok
              (format "the child %s still works" child)
              (list :id child :status "running")))
            ((eq status 'completed)
             (yeah-result-ok
              (format "the child %s is done: %s" child answer)
              (list :id child :status "completed" :summary answer)))
            (t
             (yeah-result-ok
              (format "the child %s ended in %s: %s" child status answer)
              (list :id child :status (format "%s" status) :summary answer)))))))

(defun yeah-delegate-tools ()
  "Return the specifications of the tools of delegation."
  (list (list :name "delegate"
              :description
              "Start a child agent and give it a task. The child is an agent of your own: it runs in a session of its own, with the model and the tools that the agent names, and it works while you keep working. Give the name of the agent and the task; ask for what became of the child with delegate-result."
              :input (list (list :name "agent" :type 'string)
                           (list :name "task" :type 'string))
              :handler #'yeah-delegate--delegate)
        (list :name "delegate-result"
              :description
              "Report what became of a child agent: whether it still works, and the summary it ended with. Give the id that the delegate tool returned."
              :input (list (list :name "child" :type 'string))
              :handler #'yeah-delegate--result)))

(defun yeah-delegate-register ()
  "Register the tools of delegation, once.
The registration is idempotent: a tool that is already registered is kept as
it is, so calling this twice does not raise an error."
  (dolist (spec (yeah-delegate-tools))
    (unless (yeah-tools-get (plist-get spec :name))
      (yeah-tools-register spec)))
  (yeah-delegate--install-observer)
  t)

(defun yeah-delegate-reset-for-test ()
  "Drop every delegated child and reset the counters.
Tests only."
  (clrhash yeah-delegate--children)
  (clrhash yeah-delegate--depths)
  (setq yeah-delegate--dispatch-queue nil)
  t)

(yeah-delegate-register)

(provide 'yeah-delegate)
;;; yeah-delegate.el ends here
