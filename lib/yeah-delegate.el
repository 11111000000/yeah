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
;; A delegation belongs to the run that asked for it.  The run binds the
;; session it writes into while it dispatches the call, and the child of
;; that call is written into the journal of that run -- never into the
;; journal of another run.  The id of the child is short, because the model
;; has to copy it back into `delegate-result'; a long token is copied with
;; an error, and the id of the session of the child is long.
;;
;; The child of a delegation is a run of the service placement: it writes
;; its own journal, and the parent is told what became of it, but nobody
;; waits for it and nobody cancels it.  The child has a time of its own:
;; when the time is up the child is cancelled and the parent is told why.
;;
;; The tree of the children is in the journal and not only in the memory of
;; the running Emacs.  The journal of the run holds the short id, the session
;; and the depth of every child; the journal of the child holds where that
;; child stands in the tree.  A harness that starts again reads the tree from
;; there: the child of a run is found by the id the model was given, what
;; became of it is told, and a child the journal holds no end of is not
;; reported as a child that still works.
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
(require 'yeah-session)
(require 'yeah-subagent)
(require 'yeah-tools)

(defgroup yeah-delegate nil
  "Yeah delegation to a child agent."
  :group 'yeah)

(defconst yeah-delegate--tool-names '("delegate" "delegate-result")
  "The names of the tools of delegation.")

(defcustom yeah-delegate-child-timeout 900
  "The time a child of a delegation may take, in seconds.
A child that did not end in that time is cancelled, and the parent is told
that the child ran out of time.  A preset that names a `timeout' header has
a time of its own."
  :type 'integer
  :group 'yeah-delegate)

(defvar yeah-delegate--children (make-hash-table :test 'equal)
  "The children this Emacs delegated, by the id of their session.")

(defvar yeah-delegate--depths (make-hash-table :test 'equal)
  "The depth of every delegated child, by the id of its session.")

(defvar yeah-delegate--ordinals (make-hash-table :test 'equal)
  "The number of the children of every session that delegated, by its id.
The number is what the model sees: the id of a child is short, and the id
of the session of the child is long.")

(defvar yeah-delegate--transport-factory nil
  "The factory of the transport of a child, or nil for the default.
A factory is called with the model, the instructions and the tools of
the child, and returns the transport of the child.  The tests replace
it; the default reaches the model through gptel.")

(defun yeah-delegate--current-session ()
  "Return the journal the delegate tools act on.
The journal of the run whose call is running is used: the run binds the
session it writes into while it dispatches the call, and the binding is
over when the call is over.  A call with no such journal is refused: there
is no journal to write into, and another run's journal is not this run's."
  (or (yeah-session-current)
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

(defun yeah-delegate--timeout (preset)
  "Return the time the child of PRESET may take, in seconds.
The preset may name a `timeout' header; the default of the harness is used
when it names none.  A child that has no time may work for ever, and the
parent never learns that the child is still there."
  (let ((number (yeah-delegate--count (plist-get preset :timeout))))
    (if (and number (> number 0))
        number
      yeah-delegate-child-timeout)))

(defun yeah-delegate--allowed-depth (preset)
  "Return the depth the children of PRESET may reach, or nil when it names none."
  (let ((number (yeah-delegate--count (plist-get preset :depth))))
    (when (and number (>= number 0)) number)))

(defun yeah-delegate--journal-depth (session)
  "Return the depth of SESSION, read from its own journal, or nil.
The journal of a child says where it stands in the tree of delegations, and
the journal outlives the Emacs that wrote it: a restart of the harness must
not make a child of depth three look like a root."
  (let ((depth nil))
    (dolist (record (yeah-session-records session))
      (when (equal (plist-get record :type) "child-start")
        (setq depth (plist-get record :depth))))
    depth))

(defun yeah-delegate--depth-of (session)
  "Return the depth of SESSION in the tree of delegations.
The run that started the tree is at the depth zero.  The depth of a child
that this Emacs delegated is in the memory of the Emacs; the depth of a child
that a restart of the harness forgot is in its own journal."
  (or (gethash (plist-get session :id) yeah-delegate--depths)
      (yeah-delegate--journal-depth session)
      0))

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

(defun yeah-delegate--next-ordinal (session)
  "Return the number the next child of SESSION carries.
The number counts the children of that session, and not the children of the
whole Emacs: the number is short, and the model has to copy it back."
  (let* ((parent (plist-get session :id))
         (last (gethash parent yeah-delegate--ordinals 0)))
    (puthash parent (1+ last) yeah-delegate--ordinals)
    (1+ last)))

(defun yeah-delegate--short-id (ordinal)
  "Return the short id of the child ORDINAL.
The id of the session of the child is long, and a model that copies a long
token loses a character of it.  The short id is what the model sees."
  (format "sub-%d" ordinal))

(defun yeah-delegate--start (session preset task)
  "Start the child of PRESET on TASK in the session of the parent SESSION.
Return the record of the child."
  (let* ((tools (plist-get preset :tools))
         (model (plist-get preset :model))
         (system (yeah-delegate--system preset))
         (depth (1+ (yeah-delegate--depth-of session)))
         (ordinal (yeah-delegate--next-ordinal session))
         (record nil))
    (yeah-delegate--check-depth preset depth)
    (setq record (yeah-subagent-spawn
                  session
                  (or (plist-get preset :name) "child")
                  task
                  :depth (yeah-delegate--depth-of session)
                  :tools tools
                  :budget (yeah-delegate--budget preset)
                  :timeout (yeah-delegate--timeout preset)
                  :short-id (yeah-delegate--short-id ordinal)
                  :transport (yeah-delegate--transport model system tools)))
    (setq record (plist-put record :short-id (yeah-delegate--short-id ordinal)))
    (setq record (plist-put record :ordinal ordinal))
    (setq record (plist-put record :parent-session session))
    (setq record (plist-put record :child-session-id (yeah-delegate--id record)))
    (puthash (yeah-delegate--id record) record yeah-delegate--children)
    (puthash (yeah-delegate--id record) depth yeah-delegate--depths)
    record))

(defun yeah-delegate--session-id-of (record)
  "Return the id of the session of the child RECORD.
The record of a child that this Emacs delegated holds the session itself; the
record that the journal holds holds the id of the session."
  (or (plist-get record :child-session-id)
      (yeah-delegate--id record)))

(defun yeah-delegate--ordinal-of (short-id)
  "Return the number the short id SHORT-ID carries, or nil when it carries none.
The short id of a child is `sub-<n>', and the n is the place of the child
among the children of its run."
  (when (and (stringp short-id)
             (string-match "\\`sub-\\([0-9]+\\)\\'" short-id))
    (string-to-number (match-string 1 short-id))))

(defun yeah-delegate--journal-children (session)
  "Return the records of the children of the run of SESSION, read from its journal.
The journal is what survives a restart of the harness: the memory of the
running Emacs is gone, and the journal still holds the spawn of every child
and the end of every child that ended.  A child that the journal holds no end
of has the status `unknown': the harness does not know what became of it, and
it does not say that it still works."
  (let ((children nil))
    (dolist (record (yeah-session-records session))
      (let ((type (plist-get record :type)))
        (cond ((equal type "spawn")
               (push (list :short-id (plist-get record :short-id)
                           :child-session-id (plist-get record :child)
                           :role (plist-get record :role)
                           :depth (plist-get record :depth)
                           :ordinal (yeah-delegate--ordinal-of
                                     (plist-get record :short-id))
                           :status 'unknown
                           :result nil
                           :from-journal t)
                     children))
              ((equal type "child-end")
               (let ((child (cl-find-if
                             (lambda (candidate)
                               (equal (plist-get candidate :child-session-id)
                                      (plist-get record :child)))
                             children)))
                 (when child
                   (setf (plist-get child :status)
                         (if (yeah-events-boolean-p (plist-get record :ok))
                             'completed
                           'failed)
                         (plist-get child :result)
                         (or (plist-get record :summary) ""))))))))
    (nreverse children)))

(defun yeah-delegate--children-of (session)
  "Return the records of the children that the run of SESSION delegated.
The children come in the order they were delegated.  A child that this Emacs
delegated is in the memory of the Emacs; a child that the run delegated before
a restart of the harness is in the journal of that run."
  (let ((children nil))
    (maphash
     (lambda (_id record)
       (when (equal (plist-get (plist-get record :parent-session) :id)
                    (plist-get session :id))
         (push record children)))
     yeah-delegate--children)
    (dolist (record (yeah-delegate--journal-children session))
      (unless (cl-find-if
               (lambda (live)
                 (equal (yeah-delegate--session-id-of live)
                        (yeah-delegate--session-id-of record)))
               children)
        (push record children)))
    (sort children (lambda (left right)
                     (< (or (plist-get left :ordinal) 0)
                        (or (plist-get right :ordinal) 0))))))

(defun yeah-delegate--status-of (record)
  "Return the status of the child RECORD, as a string.
The child may have ended while the tool was on its way back; the status that
the model reads is the status of the child now, not the status it had when
the child was started."
  (let ((status (plist-get record :status)))
    (if (eq status 'running)
        "running"
      (format "%s" status))))

(defun yeah-delegate--describe-children (session)
  "Return a description of the children of the run of SESSION.
SESSION may be nil: a call outside of a run has no children of its own."
  (let ((children (if session (yeah-delegate--children-of session) nil)))
    (if children
        (string-join
         (mapcar (lambda (record)
                   (format "%s (%s)" (plist-get record :short-id)
                           (yeah-delegate--status-of record)))
                 children)
         ", ")
      "none")))

(defun yeah-delegate--child-by-short-id (id session)
  "Return the child of the run of SESSION whose short id is ID, or nil.
The short id counts the children of that run, so the id of a child of
another run is not the id of a child of this one."
  (cl-find-if (lambda (record)
                (equal (plist-get record :short-id) id))
              (yeah-delegate--children-of session)))

(defun yeah-delegate--child-by-session-id (id session)
  "Return the child of the run of SESSION whose session has the id ID, or nil."
  (cl-find-if (lambda (record)
                (equal (yeah-delegate--session-id-of record) id))
              (yeah-delegate--children-of session)))

(defun yeah-delegate--resolve (id)
  "Return the record of the child ID, or nil when no child has that id.
ID is the id of the session of a child, or the short id of a child of the run
that is running now.  A child of a run that delegated before a restart of the
harness is found in the journal of that run."
  (or (gethash id yeah-delegate--children)
      (let ((session (yeah-session-current)))
        (when session
          (or (yeah-delegate--child-by-short-id id session)
              (yeah-delegate--child-by-session-id id session))))))

(defun yeah-delegate--delegate (agent task)
  "Start the child of the preset AGENT on TASK and return the result of the tool.
The child works while the parent does: the tool answers at once, with the id
of the child."
  (let* ((session (yeah-delegate--current-session))
         (preset (yeah-delegate--preset agent))
         (record (yeah-delegate--start session preset task))
         (id (plist-get record :short-id)))
    (yeah-result-ok
     (format "the child %s works on the task while you keep working; ask for it with delegate-result %s"
             id id)
     (list :id id
           :session (yeah-delegate--id record)
           :agent (or (plist-get preset :name) agent)
           :status (yeah-delegate--status-of record)))))

(defun yeah-delegate--result (child)
  "Report what became of the child CHILD."
  (let ((record (yeah-delegate--resolve child)))
    (unless record
      (signal 'user-error
              (list (format "delegate-result: no child %S; the children of this run are: %s"
                            child (yeah-delegate--describe-children (yeah-session-current))))))
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
            ((eq status 'unknown)
             ;; the child was delegated and the journal of the run holds no end
             ;; of it: the harness does not know what became of it, and it does
             ;; not say that it still works
             (yeah-result-ok
              (format "the child %s did not end: the journal of this run holds no end of it" child)
              (list :id child :status "unknown")))
            (t
             (yeah-result-ok
              (format "the child %s ended in %s: %s" child status answer)
              (list :id child :status (format "%s" status) :summary answer)))))))

(defun yeah-delegate-tools ()
  "Return the specifications of the tools of delegation."
  (list (list :name "delegate"
              :description
              "Start a child agent and give it a task. The child is an agent of your own: it runs in a session of its own, with the model and the tools that the agent names, and it works while you keep working. Give the name of the agent and the task; the tool answers with the short id of the child, and you ask for what became of it with delegate-result and that id."
              :input (list (list :name "agent" :type 'string)
                           (list :name "task" :type 'string))
              :risk "write"
              :resource "delegation"
              :handler #'yeah-delegate--delegate)
        (list :name "delegate-result"
              :description
              "Report what became of a child agent: whether it still works, and the summary it ended with. Give the short id that the delegate tool returned, such as sub-1."
              :input (list (list :name "child" :type 'string))
              :risk "read"
              :handler #'yeah-delegate--result)))

(defun yeah-delegate-register ()
  "Register the tools of delegation, once.
The registration is idempotent: a tool that is already registered is kept as
it is, so calling this twice does not raise an error."
  (dolist (spec (yeah-delegate-tools))
    (unless (yeah-tools-get (plist-get spec :name))
      (yeah-tools-register spec)))
  t)

(defun yeah-delegate-reset-for-test ()
  "Drop every delegated child and reset the counters.
Tests only."
  (clrhash yeah-delegate--children)
  (clrhash yeah-delegate--depths)
  (clrhash yeah-delegate--ordinals)
  t)

(yeah-delegate-register)

(provide 'yeah-delegate)
;;; yeah-delegate.el ends here
