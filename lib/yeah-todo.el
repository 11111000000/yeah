;;; yeah-todo.el --- the task list of a run -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.
;;
;; Yeah is free software: you can redistribute it and/or modify
;; it under the terms of the Apache License, Version 2.0.

;;; Commentary:
;;
;; Work that takes more than one step needs a list: what is left, what is
;; being done now, what is done.  The list is not a variable of the run.
;; It is a projection of the journal, exactly like the context of a run
;; and the cost of a run are: every change of the list is an event of the
;; log, and the list is what the log says when it is read from the
;; beginning.
;;
;; A task is a text and a status.  The status is one of `pending',
;; `in-progress' or `done'.  The journal carries the tasks that were added
;; and the tasks that were changed, each with the operation that changed
;; them; the projection folds the events of the log in the order they were
;; written, so a restart that reads the log again finds the same list.
;; The tasks of an event are a vector: the journal is JSONL, and a JSON
;; array is read back as a vector.
;;
;; The tools of the list are `todo_add', `todo_update' and `todo_list'.
;; They act on the journal of the run that asked for them.  A run binds
;; that journal with `yeah-todo-with-session' around the dispatch of its
;; tools; when a run does not bind it, the module finds the journal of the
;; run whose allowed call is waiting to run, which is the journal the
;; turn wrote the permission decision into.  A call with no journal to act
;; on is refused: a task list that nobody can read back is not a list.

;;; Code:

(require 'cl-lib)
(require 'yeah-events)
(require 'yeah-result)
(require 'yeah-session)

(defgroup yeah-todo nil
  "The task list of a Yeah run."
  :group 'yeah)

(defconst yeah-todo--statuses '("pending" "in-progress" "done")
  "The statuses a task may have.")

(defconst yeah-todo--tool-names '("todo_add" "todo_update" "todo_list")
  "The names of the tools of the task list.")

(defvar yeah-todo--session nil
  "The journal the todo tools act on, or nil when no run bound one.
The binding is request-local: a run binds it around the dispatch of its
tools, so two runs in one Emacs do not share one task list.")

(defvar yeah-todo--dispatch-session nil
  "The journal of the run whose allowed todo call is waiting to run, or nil.
It is the journal the turn wrote the permission decision of the call into.")

(defvar yeah-todo--dispatch-pending 0
  "The number of allowed todo calls that have not run yet.
A call that was refused by the rules never reaches its tool, so it never
counts; a call that runs takes one count back.")

(defun yeah-todo--check-session (session)
  "Return SESSION when it is a session, and signal `user-error' otherwise."
  (unless (and (consp session)
               (stringp (plist-get session :id))
               (plist-get session :path))
    (signal 'user-error
            (list (format "yeah-todo: not a session: %S" session))))
  session)

(defun yeah-todo--check-text (text)
  "Return TEXT when it is a nonempty string, and signal `user-error' otherwise."
  (unless (and (stringp text) (not (string-empty-p (string-trim text))))
    (signal 'user-error
            (list (format "yeah-todo: the task text must be a nonempty string, got %S"
                          text))))
  text)

(defun yeah-todo--check-status (status)
  "Return STATUS when it is a status of a task, and signal `user-error' otherwise."
  (unless (member status yeah-todo--statuses)
    (signal 'user-error
            (list (format "yeah-todo: unknown status %S; the statuses are %S"
                          status yeah-todo--statuses))))
  status)

(defun yeah-todo--id-of (item)
  "Return the identifier of the task ITEM."
  (plist-get item :id))

(defun yeah-todo--next-id (items)
  "Return the identifier of the task that follows the tasks ITEMS."
  (let ((highest 0))
    (dolist (item items)
      (let ((number (string-to-number (plist-get item :id))))
        (when (and (integerp number) (> number highest))
          (setq highest number))))
    (format "%d" (1+ highest))))

(defun yeah-todo--items-in (records)
  "Return the task list that RECORDS describe.
Each `todo' event of RECORDS is folded into the list in the order the
events were written: an `add' appends the tasks it carries, an `update'
replaces the task of the same identifier.

The tasks of an event are a vector, because the journal is JSONL and a
vector is what the reader of a JSON array gives back."
  (let ((items nil))
    (dolist (record records)
      (when (equal (plist-get record :type) "todo")
        (let ((operation (plist-get record :operation))
              (carried (append (plist-get record :items) nil)))
          (dolist (item carried)
            (let ((copy (copy-sequence item)))
              (if (equal operation "add")
                  (setq items (append items (list copy)))
                (setq items
                      (append
                       (cl-remove (yeah-todo--id-of item) items
                                  :key #'yeah-todo--id-of :test #'equal)
                       (list copy)))))))))
    items))

(defun yeah-todo-items (session)
  "Return the tasks of SESSION: the projection of its journal.
Each task is a plist `(:id ID :text TEXT :status STATUS)'.  The tasks are
in the order they were added."
  (yeah-todo--check-session session)
  (yeah-todo--items-in (yeah-session-records session)))

(defun yeah-todo-add (session text)
  "Add the task TEXT to the list of SESSION and return the new task.
The task is written into the journal of SESSION as a `todo' event, and it
starts as `pending'."
  (yeah-todo--check-session session)
  (yeah-todo--check-text text)
  (let* ((items (yeah-todo-items session))
         (item (list :id (yeah-todo--next-id items)
                     :text text
                     :status "pending")))
    (yeah-events-write session "todo" :items (vector item) :operation "add")
    item))

(defun yeah-todo-update (session id &optional status text)
  "Update the task ID of SESSION and return the task as it is now.
STATUS and TEXT are what change; at least one of them must be given.
Signals `user-error' when there is no task ID or when nothing changes."
  (yeah-todo--check-session session)
  (unless (and (stringp id) (not (string-empty-p id)))
    (signal 'user-error
            (list (format "yeah-todo: the task id must be a nonempty string, got %S"
                          id))))
  (when (and (null status) (null text))
    (signal 'user-error
            (list "yeah-todo: nothing to update: give a status or a text")))
  (when status
    (yeah-todo--check-status status))
  (when text
    (yeah-todo--check-text text))
  (let* ((items (yeah-todo-items session))
         (item (cl-find id items :key #'yeah-todo--id-of :test #'equal)))
    (unless item
      (signal 'user-error
              (list (format "yeah-todo: there is no task %s" id))))
    (let ((changed (list :id id
                          :text (or text (plist-get item :text))
                          :status (or status (plist-get item :status)))))
      (yeah-events-write session "todo" :items (vector changed) :operation "update")
      changed)))

(defun yeah-todo--observe (session type fields _id)
  "Note the allowed todo call of SESSION, so that the tool finds its journal.
TYPE is the type of the event, FIELDS the fields it carries."
  (when (and (equal type "permission-decision")
             (equal (plist-get fields :effect) "allow")
             (member (plist-get fields :action) yeah-todo--tool-names))
    (setq yeah-todo--dispatch-session session)
    (cl-incf yeah-todo--dispatch-pending)))

(defun yeah-todo--install-observer ()
  "Install the observer that lets a todo tool find the journal of its run."
  (unless (memq #'yeah-todo--observe yeah-events-write-functions)
    (add-to-list 'yeah-events-write-functions #'yeah-todo--observe)))

(defun yeah-todo--current-session ()
  "Return the journal the todo tools act on.
The binding of the run comes first.  When no run bound one, the journal of
the run whose allowed call is waiting to run is used.  A call with neither
is refused: there is no journal to write into."
  (cond
   (yeah-todo--session
    yeah-todo--session)
   ((and yeah-todo--dispatch-session (> yeah-todo--dispatch-pending 0))
    (cl-decf yeah-todo--dispatch-pending)
    yeah-todo--dispatch-session)
   (t
    (signal 'user-error
            (list "yeah-todo: this call has no journal: the run did not bind one")))))

(defmacro yeah-todo-with-session (session &rest body)
  "Run BODY with SESSION as the journal the todo tools act on.
The binding is request-local: it lasts for the dynamic extent of BODY."
  (declare (indent 1) (debug t))
  `(let ((yeah-todo--session ,session))
     ,@body))

(defun yeah-todo--describe (item)
  "Return one line that describes the task ITEM."
  (format "%s. [%s] %s"
          (plist-get item :id)
          (plist-get item :status)
          (plist-get item :text)))

(defun yeah-todo-add-tool (text)
  "Add the task TEXT to the list of the run and return the result.
The result tells the model what the task is and where it stands."
  (let* ((session (yeah-todo--current-session))
         (item (yeah-todo-add session text)))
    (yeah-result-ok
     (format "Added task %s: %s"
             (plist-get item :id) (plist-get item :text))
     (list :id (plist-get item :id)
           :status (plist-get item :status)
           :count (length (yeah-todo-items session))))))

(defun yeah-todo-update-tool (id &optional status text)
  "Update the task ID of the run and return the result.
STATUS and TEXT are what change; at least one of them must be given."
  (let* ((session (yeah-todo--current-session))
         (item (yeah-todo-update session id status text)))
    (yeah-result-ok
     (format "Task %s is now %s: %s"
             (plist-get item :id)
             (plist-get item :status)
             (plist-get item :text))
     (list :id (plist-get item :id)
           :status (plist-get item :status)
           :count (length (yeah-todo-items session))))))

(defun yeah-todo-list-tool ()
  "Return the task list of the run and the result for the model."
  (let* ((session (yeah-todo--current-session))
         (items (yeah-todo-items session)))
    (yeah-result-ok
     (if items
         (mapconcat #'yeah-todo--describe items "\n")
       "The task list is empty.")
     (list :count (length items)
           :ids (mapcar #'yeah-todo--id-of items)))))

(defun yeah-todo-tools ()
  "Return the tool specifications of the task list."
  (yeah-todo--install-observer)
  (list
   (list :name "todo_add"
         :description
         "Add a task to the task list of this run. Use it when the work takes more than one step: the list is part of the journal of the run, so it is still there after a restart. A new task starts as pending."
         :input (list (list :name "text" :type 'string))
         :handler #'yeah-todo-add-tool)
   (list :name "todo_update"
         :description
         "Change a task of the task list of this run: give its id and either a new status or a new text. The status is one of pending, in-progress or done."
         :input (list (list :name "id" :type 'string)
                      (list :name "status" :type 'string :optional t)
                      (list :name "text" :type 'string :optional t))
         :handler #'yeah-todo-update-tool)
   (list :name "todo_list"
         :description
         "List the tasks of this run with their status."
         :input nil
         :handler #'yeah-todo-list-tool)))

(provide 'yeah-todo)
;;; yeah-todo.el ends here
