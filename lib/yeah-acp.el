;;; yeah-acp.el --- ACP v1 agent over newline JSON-RPC -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026  Petr Kosov
;;
;; This file is part of Yeah.

;;; Commentary:
;;
;; Agent-side ACP v1 over newline-delimited JSON-RPC 2.0.  Sessions are real
;; Yeah sessions; prompt responses are sent when the run reaches a terminal
;; state; session/cancel is a notification; journal events become
;; session/update notifications through `yeah-events-write-functions'.
;;
;; A session is driven by a controller: the same one the attached path uses.
;; The controller owns the session's turn and its persistent pending queue,
;; so the wire can ask, steer, cancel, withdraw a pending input and recover
;; one.  There is no second queue in this module: the pending inputs of a
;; session are the ones the control keeps, and the queue the editor sees is
;; a projection of the journal -- the events that move an input in or out of
;; the queue reach the client as session/update notifications.
;;
;; `session/load' opens a session again and replays its journal: the records
;; of the session become session/update notifications, so that an editor can
;; rebuild the transcript of a session it opens a second time.
;;
;; An answer to a permission that arrives after the run that asked has ended
;; is not applied: the journal shows the question as deferred and the run as
;; ended, and the late answer changes nothing.
;;
;; The protocol is spoken over two transports.  On stdio the server reads
;; standard input with a blocking read, so a notification that arrives
;; while a prompt is running is read only after the prompt settled.  On a
;; socket the connection is a process, the data arrives in a filter and the
;; event loop keeps running, so a cancellation is handled while the prompt
;; is still running.  `yeah-acp-serve-socket' is the transport of the
;; primary deployment.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'yeah-acp-vocabulary)
(require 'yeah-control)
(require 'yeah-events)
(require 'yeah-product)
(require 'yeah-result)
(require 'yeah-turn)
(require 'yeah-wire)
(require 'yeah-wire-socket)

(defgroup yeah-acp nil
  "Yeah ACP v1 agent."
  :group 'yeah)

(defconst yeah-acp--agent-name "yeah")
(defconst yeah-acp--agent-version "0.1.0")

(defvar yeah-acp--sessions (make-hash-table :test 'equal)
  "Map ACP session ids to their Yeah session state.")

(defvar yeah-acp--pending-permissions (make-hash-table :test 'equal)
  "Map permission request ids to the question they ask.
The value names the session, the action and the resource, so that the
answer reaches the turn that asked and may be remembered for the
session.")

(defvar yeah-acp--connection nil
  "The connection being served, bound dynamically by the socket handler.
A session remembers which connection owns it, so the death of that
connection can cancel the work it started.")

(defvar yeah-acp--client-capabilities (make-hash-table :test 'eq)
  "Map every connection to the capabilities its client announced.
The key is the connection; the standard output connection is the key
nil.  What a client announced at `initialize' says what it
understands of the wire.")

(defun yeah-acp--jsonable-args (args)
  "Return ARGS as a JSON value: an array when every element serializes,
the printed form otherwise."
  (condition-case nil
      (let ((array (apply #'vector args)))
        (ignore (json-serialize array))
        array)
    (error (format "%S" args))))

(defun yeah-acp--session-rules (session-id)
  "Return the permission rules that decide for SESSION-ID.
The standing permissions of the service come first and the decisions the
client remembered for this session come last: the last match wins."
  (let ((state (yeah-acp--session-state session-id)))
    (append (yeah-perm-rules-list) (plist-get state :rules))))

(defun yeah-acp--ask-client (session-id output request)
  "Ask the client about REQUEST and return the deferral of the question.
The question carries three answers: allow once, allow always (the decision
is remembered for the session) and reject.  The question itself is kept,
so that the answer reaches the turn that asked and may be remembered."
  (let* ((request-id (yeah-acp--fresh-id "perm"))
         (params (list :sessionId session-id
                       :toolCall (list :toolCallId request-id
                                       :title (format "%s on %s"
                                                      (plist-get request :action)
                                                      (plist-get request :resource))
                                       :rawInput
                                       (yeah-acp--jsonable-args
                                        (plist-get request :args)))
                       :options (vector
                                 (list :optionId "allow-once"
                                       :name "Allow once" :kind "allow_once")
                                 (list :optionId "allow-always"
                                       :name "Allow always" :kind "allow_always")
                                 (list :optionId "reject-once"
                                       :name "Reject" :kind "reject_once")))))
    (puthash request-id
             (list :session-id session-id
                   :action (plist-get request :action)
                   :resource (plist-get request :resource))
             yeah-acp--pending-permissions)
    (funcall output (json-serialize
                     (list :jsonrpc "2.0" :id request-id
                           :method "session/request_permission"
                           :params params)))
    (list :defer request-id)))

(defun yeah-acp--client-answerer (session-id output)
  "Return the answerer of SESSION-ID that asks the client over the wire.
The rules decide first; what they do not name is asked of the client as a
`session/request_permission', and the call waits for the answer.  A safe
read needs no question: it is allowed, and it says why."
  (lambda (request)
    (let* ((action (plist-get request :action))
           (resource (plist-get request :resource))
           (effect (yeah-perm-effect action resource
                                     (yeah-acp--session-rules session-id))))
      (pcase effect
        ('allow (list :effect :allow :reply :once))
        ('deny (list :effect :deny :reply :reject
                     :reason (format "the rules deny %s on %s"
                                     action resource)))
        (_ (or (yeah-approval-safe-read-decision request)
               (yeah-acp--ask-client session-id output request)))))))

(defvar yeah-acp--counter 0
  "Monotonic counter for generated identifiers.")

(defvar yeah-acp--transport nil
  "Optional model transport used by the ACP server.")

(defvar yeah-acp-default-transport nil
  "Model transport of the service when none is passed at start.
A service init file (`yeah-service-init-file') sets this; nil falls back
to the gptel transport of the service's own configuration.")

(defvar yeah-acp--answerer nil
  "Optional permission answerer used by the ACP server.")

(defvar yeah-acp--output-function #'yeah-acp--print-line
  "Function receiving one serialized JSON message per call.")

(defvar yeah-acp--output nil
  "Output function of the connection being served, or nil for standard output.
This variable is bound dynamically while a connection is served, so the
messages of one connection do not reach another one.")

(defun yeah-acp--session-answerer (state)
  "Return the answerer of STATE: the client of the session over the wire.
The rules of the session decide first; what they do not name is asked of
the client as a `session/request_permission', and the call waits for the
answer.  The question is asked of the connection the session belongs to."
  (lambda (request)
    (funcall (or yeah-acp--answerer
                 (yeah-acp--client-answerer (plist-get state :id)
                                             (yeah-acp--output-for state)))
             request)))

(defun yeah-acp--make-control (state)
  "Return the controller of STATE.
The controller owns the turn of the session and its persistent pending
queue: the wire and the attached path share one queue, one set of journal
events and one set of semantics.  The transport and the answerer are the
service's, and the working directory travels with every input."
  (yeah-control-new (plist-get state :session)
                    (or yeah-acp--transport yeah-acp-default-transport)
                    (yeah-acp--session-answerer state)
                    nil nil
                    (list :cwd (plist-get state :cwd))))

(defun yeah-acp-version ()
  "Return the ACP protocol version spoken by Yeah."
  yeah-acp-protocol-version)

(defun yeah-acp--print-line (text)
  "Write TEXT and a newline to standard output.
The bytes of a serialized message are UTF-8, and they are written as
they are: `yeah-wire-print-line' knows how."
  (yeah-wire-print-line text))

(defun yeah-acp--emit (object)
  "Serialize OBJECT and pass it to the output function of this connection."
  (funcall (or yeah-acp--output yeah-acp--output-function
               #'yeah-acp--print-line)
           (json-serialize object)))

(defun yeah-acp--response (id result)
  "Return a JSON-RPC response string for ID and RESULT."
  (json-serialize (list :jsonrpc "2.0" :id id :result result)))

(defun yeah-acp--error (id code message)
  "Return a JSON-RPC error response string for ID, CODE and MESSAGE."
  (json-serialize
   (list :jsonrpc "2.0" :id id
         :error (list :code code :message message))))

(defun yeah-acp--fresh-id (prefix)
  "Return a fresh id beginning with PREFIX."
  (setq yeah-acp--counter (1+ yeah-acp--counter))
  (format "%s-%d-%x" prefix yeah-acp--counter (random #x1000000)))

(defun yeah-acp--session-state (session-id &optional required)
  "Return the ACP state for SESSION-ID, optionally requiring it to exist."
  (let ((state (gethash session-id yeah-acp--sessions)))
    (when (and required (null state))
      (signal 'user-error
              (list (format "unknown ACP session: %s" session-id))))
    state))

(defun yeah-acp-initialize (handshake)
  "Negotiate an ACP HANDSHAKE and return agent capabilities."
  (unless (and (listp handshake)
               (integerp (plist-get handshake :protocolVersion)))
    (signal 'user-error
            (list "initialize: protocolVersion must be an integer")))
  (yeah-acp--remember-capabilities handshake)
  (list :protocolVersion yeah-acp-protocol-version
        :agentInfo (list :name yeah-acp--agent-name
                         :version yeah-acp--agent-version)
        :agentCapabilities
        (list :loadSession t
              :promptCapabilities (list :image :false
                                        :audio :false
                                        :embeddedContext :false)
              :mcpCapabilities (list :http :false :sse :false))))

(defun yeah-acp--remember-capabilities (handshake)
  "Remember the client capabilities of HANDSHAKE for the current connection.
What the client announced is what it understands of the wire: Yeah's own
events travel to the clients that asked for them and to nobody else."
  (puthash yeah-acp--connection
           (plist-get handshake :clientCapabilities)
           yeah-acp--client-capabilities))

(defun yeah-acp--queue-events-p (state)
  "Return non-nil when the client of STATE asked for Yeah's queue events.
The queue events are Yeah's own vocabulary, not the vocabulary of ACP: a
client that does not know them refuses the whole update.  A client asks
for them in the `_meta' of the capabilities it announced."
  (let* ((capabilities (gethash (plist-get state :connection)
                                yeah-acp--client-capabilities))
         (meta (and (listp capabilities) (plist-get capabilities :_meta))))
    (and (listp meta)
         (eq t (plist-get meta yeah-acp-queue-events-capability)))))

(defun yeah-acp--validate-session-request (request &optional load)
  "Validate a session/new or session/load REQUEST.  LOAD selects its shape."
  (unless (listp request)
    (signal 'user-error (list "session request must be an object")))
  (when load
    (unless (stringp (plist-get request :sessionId))
      (signal 'user-error (list "session/load needs sessionId"))))
  (unless (and (stringp (plist-get request :cwd))
               (file-name-absolute-p (plist-get request :cwd)))
    (signal 'user-error (list "session request needs an absolute cwd")))
  (unless (or (null (plist-get request :mcpServers))
              (eq (plist-get request :mcpServers) :null)
              (listp (plist-get request :mcpServers)))
    (signal 'user-error (list "mcpServers must be an array or null"))))

(defun yeah-acp--send-update (session-id update &optional output)
  "Send a session/update notification for SESSION-ID and UPDATE.
OUTPUT receives the serialized message and defaults to standard output."
  (funcall (or output yeah-acp--output-function #'yeah-acp--print-line)
           (json-serialize
            (list :jsonrpc "2.0"
                  :method "session/update"
                  :params (list :sessionId session-id :update update)))))

(defun yeah-acp--content-chunk (kind text)
  "Return an ACP content chunk of KIND containing TEXT.
The content of an ACP chunk is one content block, not an array of them:
the protocol says so, and a client that checks the wire refuses a chunk
that carries an array."
  (list :sessionUpdate kind
        :content (list :type "text" :text (or text ""))))

(defun yeah-acp--tool-input (args)
  "Return ARGS as a JSON value for the wire.
The journal holds the arguments of a call in their printed form, because the
journal is a log of what happened and not a place for structured data.  A
client that shows the call wants the values themselves, so the printed form
is read back into them.

The arguments come from the model, so the printed form is read as data and
not as code: a form that the reader would evaluate is not read at all, and
the printed form travels to the client as it is."
  (if (stringp args)
      (condition-case nil
          (if (string-match-p "#\\." args)
              args
            (let ((value (car (read-from-string args))))
              (cond
               ((and (listp value) (proper-list-p value))
                (apply #'vector (mapcar #'yeah-result-json-safe value)))
               ((vectorp value) value)
               (t (format "%S" value)))))
        (error args))
    args))

(defun yeah-acp--tool-call (tool-call-id name status &optional input result)
  "Return a tool_call or tool_call_update ACP update for TOOL-CALL-ID.
INPUT is what the tool was called with and RESULT is what it returned.
The protocol has a field for each of them, and a client that shows the call
of a tool shows them: a call without its input is a name."
  (if (eq status 'started)
      (let ((update (list :sessionUpdate "tool_call"
                           :toolCallId tool-call-id
                           :title name
                           :status "pending")))
        (when input
          (plist-put update :rawInput input))
        update)
    (let ((update (list :sessionUpdate "tool_call_update"
                         :toolCallId tool-call-id
                         :status (if (eq status 'failed) "failed" "completed")
                         :content (vector (list :type "text"
                                                :text (or result ""))))))
      (when result
        (plist-put update :rawOutput result))
      update)))

(defun yeah-acp--input-update (kind fields)
  "Return an ACP update of KIND for a queue event with FIELDS.
The update names the input, its kind, the words the person wrote and, for a
withdrawal, the reason the input left the queue.  A field the event does not
carry is left out of the update."
  (let ((update (list :sessionUpdate kind)))
    (when-let ((input-id (plist-get fields :input_id)))
      (plist-put update :inputId input-id))
    (when-let ((input-kind (or (plist-get fields :input_kind)
                                (plist-get fields :kind))))
      (plist-put update :inputKind input-kind))
    (when-let ((prompt (plist-get fields :prompt)))
      (plist-put update :content (vector (list :type "text" :text prompt))))
    (when-let ((reason (plist-get fields :reason)))
      (plist-put update :reason reason))
    update))

(defun yeah-acp--update-for (type fields id &optional queue-events)
  "Return the ACP update for the journal event TYPE with FIELDS, or nil.
ID names the record.  QUEUE-EVENTS says that the client understands
Yeah's own queue events; a client that does not know them refuses the
whole update, so they travel only where they were asked for.  The
pending queue of a session is visible in the log: the events that move
an input in or out of the queue have their own kinds, so that the
editor learns the queue from the journal and keeps no state of its own."
  (pcase type
    ("user-message"
     (yeah-acp--content-chunk "user_message_chunk"
                              (plist-get fields :payload)))
    ("assistant-message"
     (yeah-acp--content-chunk "agent_message_chunk"
                              (plist-get fields :payload)))
    ("finish"
     ;; The summary of a finished run is the answer of the agent: the model
     ;; writes it for the human, and the editor shows it as the answer of the
     ;; run.  A client that speaks ACP expects the words of the agent as the
     ;; message of the agent, and a model that answers only through the
     ;; `finish' tool says nothing else.
     (yeah-acp--content-chunk "agent_message_chunk"
                              (plist-get fields :summary)))
    ("tool-request"
     (yeah-acp--tool-call
      (or (plist-get fields :tool_call_id) id)
      (plist-get fields :tool) 'started
      (yeah-acp--tool-input (plist-get fields :args))))
    ("tool-end"
     (yeah-acp--tool-call
      (or (plist-get fields :tool_call_id) id)
      (plist-get fields :tool)
      (if (yeah-events-boolean-p (plist-get fields :ok))
          'completed
        'failed)
      nil
      (plist-get fields :payload)))
    ((and (guard queue-events) "input-queued")
     (yeah-acp--input-update "input_queued" fields))
    ((and (guard queue-events) "input-taken")
     (yeah-acp--input-update "input_taken" fields))
    ((and (guard queue-events) "input-recovered")
     (yeah-acp--input-update "input_recovered" fields))
    ((and (guard queue-events) "input-withdrawn")
     (yeah-acp--input-update "input_withdrawn" fields))
    (_ nil)))

(defun yeah-acp--observe-event (state session type fields id)
  "Send ACP updates for journal events belonging to STATE's SESSION."
  (when (eq session (plist-get state :session))
    (let ((update (yeah-acp--update-for type fields id
                                         (yeah-acp--queue-events-p state))))
      (when update
        (yeah-acp--send-update (plist-get state :id) update
                               (yeah-acp--output-for state))))))

(defun yeah-acp--replay (state session)
  "Send the journal of SESSION to the client as session/update notifications.
Return the number of records that were replayed.  The editor rebuilds its
transcript from them: the messages, the tool calls and the queue events of
the session, in the order the journal holds them."
  (let ((output (yeah-acp--output-for state))
        (queue-events (yeah-acp--queue-events-p state))
        (count 0))
    (dolist (record (yeah-session-records session))
      (let ((update (yeah-acp--update-for
                     (plist-get record :type)
                     (yeah-session-record-fields record)
                     (plist-get record :id)
                     queue-events)))
        (when update
          (yeah-acp--send-update (plist-get state :id) update output)
          (setq count (1+ count)))))
    count))

(defun yeah-acp--output-for (state)
  "Return the output function of STATE: its connection's, or the global one."
  (or (plist-get state :output) yeah-acp--output-function
      #'yeah-acp--print-line))

(defun yeah-acp--register-session (session cwd)
  "Register SESSION for ACP and return its state plist.
The state carries the output function of the connection the session was
created on, so its notifications reach that connection; when the session
was created without a connection the current output function is used.
The state also carries the rules the client remembered for this session:
a decision of the client is remembered here and in no other session.
The state carries the controller of the session: its turn and its queue."
  (let* ((id (plist-get session :id))
         (previous (gethash id yeah-acp--sessions))
         (state (list :id id :session session :cwd cwd :listener nil
                      :output yeah-acp--output
                      :connection yeah-acp--connection
                      :rules nil))
         (listener (lambda (observed-session type fields event-id)
                     (yeah-acp--observe-event state observed-session type fields event-id))))
    (when previous
      (when-let ((old (plist-get previous :listener)))
        (setq yeah-events-write-functions
              (delete old yeah-events-write-functions))))
    (plist-put state :listener listener)
    (plist-put state :control (yeah-acp--make-control state))
    (add-to-list 'yeah-events-write-functions listener)
    (puthash id state yeah-acp--sessions)
    state))

(defun yeah-acp-session-new (request)
  "Create a real Yeah session for ACP REQUEST and return `(:sessionId ID)'."
  (yeah-acp--validate-session-request request)
  (let* ((cwd (file-truename (plist-get request :cwd)))
         (root (yeah-product-session-root cwd))
         (session (yeah-session-open (yeah-acp--fresh-id "session") root)))
    (yeah-acp--register-session session cwd)
    (list :sessionId (plist-get session :id))))

(defun yeah-acp-session-load (request)
  "Load an existing session and replay its journal into the editor's view.
The records of the session become session/update notifications, so that the
editor can rebuild the transcript of a session it opens again.  The answer
names the session and the number of records that were replayed."
  (yeah-acp--validate-session-request request t)
  (let* ((cwd (file-truename (plist-get request :cwd)))
         (root (yeah-product-session-root cwd))
         (session-id (plist-get request :sessionId)))
    (unless (file-exists-p (yeah-session--path-for session-id root))
      (signal 'user-error
              (list (format "unknown ACP session: %s" session-id))))
    (let* ((session (yeah-session-open session-id root))
           (state (yeah-acp--register-session session cwd)))
      (list :sessionId (plist-get session :id)
            :replayed (yeah-acp--replay state session)))))

(defun yeah-acp--prompt-text (blocks)
  "Return prompt text from ACP content BLOCKS.
Text and resource_link blocks are supported; every other block is refused."
  (unless (listp blocks)
    (signal 'user-error (list "session/prompt needs a prompt array")))
  (mapconcat
   (lambda (block)
     (pcase (plist-get block :type)
       ("text" (or (plist-get block :text) ""))
       ("resource_link"
        (format "[%s](%s)"
                (or (plist-get block :name) "resource")
                (or (plist-get block :uri) "")))
       (_ (signal 'user-error
                  (list (format "unsupported prompt block: %S"
                                (plist-get block :type)))))))
   blocks "\n"))

(defun yeah-acp--stop-reason (turn)
  "Return the ACP stopReason for terminal TURN."
  (pcase (yeah-turn-state turn)
    ('completed "end_turn")
    ('interrupted "cancelled")
    (_ "refusal")))

(defun yeah-acp--completion-stop-reason (completion)
  "Return the ACP stopReason of the control COMPLETION.
A withdrawn input has no turn: it was cancelled before it ever ran."
  (let ((turn (plist-get completion :turn)))
    (if turn
        (yeah-acp--stop-reason turn)
      (pcase (plist-get completion :state)
        ('completed "end_turn")
        ('interrupted "cancelled")
        ('cancelled "cancelled")
        (_ "refusal")))))

(defun yeah-acp-session-prompt (request id)
  "Queue a prompt for REQUEST and send its response later under request ID.
The prompt is an ordinary ask of the session's controller: it runs when the
session is idle and waits in the queue of the session when a run is active.
The response leaves when the run reaches a terminal state, and it carries the
same stop reasons as before."
  (unless (listp request)
    (signal 'user-error (list "session/prompt params must be an object")))
  (let* ((session-id (plist-get request :sessionId))
         (state (yeah-acp--session-state session-id t))
         (output (yeah-acp--output-for state))
         (control (plist-get state :control))
         (prompt (yeah-acp--prompt-text (plist-get request :prompt))))
    (yeah-control-submit
     control prompt nil
     (lambda (completion)
       (funcall
        output
        (json-serialize
         (list :jsonrpc "2.0" :id id
               :result (list :stopReason
                             (yeah-acp--completion-stop-reason completion))))))))
  nil)

(defun yeah-acp-session-cancel (request)
  "Handle the session/cancel notification REQUEST.
The cancel reaches the run of the session's controller: it stops the turn
that runs now and leaves the pending inputs of the session for a later run."
  (unless (and (listp request) (stringp (plist-get request :sessionId)))
    (signal 'user-error (list "session/cancel needs sessionId")))
  (let ((state (yeah-acp--session-state (plist-get request :sessionId))))
    (when state
      (yeah-control-cancel (plist-get state :control) "cancelled by ACP client")))
  nil)

(defun yeah-acp--require-session-id (request method)
  "Signal `user-error' unless REQUEST names a session for METHOD."
  (unless (and (listp request) (stringp (plist-get request :sessionId)))
    (signal 'user-error (list (format "%s needs sessionId" method)))))

(defun yeah-acp--input-ids (control)
  "Return the ids of the pending inputs of CONTROL."
  (mapcar (lambda (input) (plist-get input :id))
          (yeah-control-pending control)))

(defun yeah-acp--queued-id (session)
  "Return the id of the last input that entered the queue of SESSION.
The journal names every input that enters the queue, so the id of a queued
input is known even when the run it started has already ended."
  (let ((record (seq-find
                 (lambda (candidate)
                   (equal "input-queued" (plist-get candidate :type)))
                 (reverse (yeah-session-records session)))))
    (and record (plist-get record :input_id))))

(defun yeah-acp--steer-input-id (control session prompt)
  "Queue PROMPT as steering in CONTROL and return the id of the new input.
A steering that waits in the queue is named by the queue itself; a steering
that the control turned into an ask (the session was idle) is named by the
run it started."
  (let* ((before (yeah-acp--input-ids control))
         (turn (yeah-control-steer control prompt))
         (fresh (seq-difference (yeah-acp--input-ids control) before #'equal)))
    (or (car fresh)
        (and turn (yeah-turn-id turn))
        (yeah-acp--queued-id session))))

(defun yeah-acp-session-steer (request)
  "Queue a clarification for the running turn of REQUEST.
The answer names the input the clarification waits as.  A clarification that
the session cannot deliver to a running turn becomes an ordinary ask."
  (yeah-acp--require-session-id request "session/steer")
  (unless (stringp (plist-get request :prompt))
    (signal 'user-error (list "session/steer needs a prompt")))
  (let* ((state (yeah-acp--session-state (plist-get request :sessionId) t))
         (control (plist-get state :control))
         (session (plist-get state :session))
         (input-id (yeah-acp--steer-input-id
                    control session (plist-get request :prompt))))
    (unless input-id
      (signal 'user-error (list "session/steer: the clarification was not queued")))
    (list :inputId input-id)))

(defun yeah-acp-session-withdraw (request)
  "Withdraw the pending input named by REQUEST and answer with the outcome.
The answer names the input and says whether it was pending: an input that
is not in the queue is not withdrawn twice."
  (yeah-acp--require-session-id request "session/withdraw")
  (unless (stringp (plist-get request :inputId))
    (signal 'user-error (list "session/withdraw needs an inputId")))
  (let* ((state (yeah-acp--session-state (plist-get request :sessionId) t))
         (control (plist-get state :control))
         (input-id (plist-get request :inputId))
         (input (yeah-control-withdraw control input-id)))
    (list :inputId input-id
          :withdrawn (if input t :false))))

(defun yeah-acp-session-recover (request)
  "Start the oldest pending input of REQUEST and answer with the outcome.
Recovery is explicit: a pending input waits until the person asks for it,
and the journal says that it was recovered.

A run that is already active is not an error of the protocol: nothing is
recovered then, and the answer says so.  The answer names the INPUT that
was recovered, not the turn that carries it."
  (yeah-acp--require-session-id request "session/recover")
  (let* ((state (yeah-acp--session-state (plist-get request :sessionId) t))
         (control (plist-get state :control))
         (active (yeah-control-active-turn control))
         (input (seq-find (lambda (candidate)
                            (eq 'ask (plist-get candidate :kind)))
                          (yeah-control-pending control))))
    (if (and active (not (yeah-turn-done active)))
        (list :started :false)
      (let ((turn (yeah-control-recover-next control)))
        (if turn
            (list :started t :inputId (and input (plist-get input :id)))
          (list :started :false))))))

(defun yeah-acp--permission-decision (message)
  "Return the permission decision carried by client RESPONSE MESSAGE.
Only an explicit `allow-once' permits the effect.  A rejection, a
cancelled request, a protocol error, or an unknown option refuses it."
  (let* ((error (plist-get message :error))
         (result (plist-get message :result))
         (outcome (plist-get result :outcome))
         (state (plist-get outcome :outcome))
         (option (plist-get outcome :optionId)))
    (cond
     (error
      (list :effect :deny
            :reason "the client could not answer the permission request"))
     ((equal state "cancelled")
      (list :effect :deny :reason "cancelled"))
     ((equal option "allow-once")
      (list :effect :allow :reply :once))
     ((equal option "allow-always")
      ;; the person says that this action on this resource is allowed from
      ;; now on; the kernel remembers the decision
      (list :effect :allow :reply :always))
     ((equal option "reject-once")
      (list :effect :deny :reason "the person refused"))
     (t
      (list :effect :deny
            :reason "the client returned an unknown permission response")))))

(defun yeah-acp--turn-waiting-for (session-id request-id)
  "Return the turn of SESSION-ID that waits for the answer of REQUEST-ID.
The turn of a session is the one its controller runs: the answer of a
permission question reaches the turn that asked it."
  (let* ((state (yeah-acp--session-state session-id))
         (control (and state (plist-get state :control)))
         (turn (and control (yeah-control-active-turn control))))
    (when (and turn
               (not (yeah-turn-done turn))
               (gethash request-id (yeah-turn-pending-permissions turn)))
      turn)))

(defun yeah-acp--remember-decision (question decision)
  "Remember an `always' DECISION for QUESTION in the rules of its session.
The decision is remembered for this session only: the standing permissions
of the service are not touched."
  (let ((session-id (plist-get question :session-id)))
    (when-let ((rule (yeah-approval-remember-rule
                      (list :action (plist-get question :action)
                            :resource (plist-get question :resource))
                      decision)))
      (let ((state (yeah-acp--session-state session-id)))
        (plist-put state :rules
                   (yeah-perm-rules-append (plist-get state :rules) rule))))))

(defun yeah-acp--route-response (message)
  "Route a client RESPONSE (a message with an id and no method) to the
permission it answers.  Return non-nil when it was a response."
  (let ((id (plist-get message :id)))
    (when (and id (null (plist-get message :method)))
      (when-let ((question (gethash id yeah-acp--pending-permissions)))
        (remhash id yeah-acp--pending-permissions)
        (let ((decision (yeah-acp--permission-decision message)))
          (when (yeah-approval-always-p decision)
            (yeah-acp--remember-decision question decision))
          (when-let ((turn (yeah-acp--turn-waiting-for
                            (plist-get question :session-id) id)))
            (yeah-turn-resume-permission turn id decision)))
        t))))

(defun yeah-acp--connection-closed (connection)
  "Cancel the work CONNECTION started and forget its pending questions.
A permission request whose asker is gone must never hang the run: the
turn is cancelled with the reason in the journal, and the request ids
of the dead connection are dropped."
  (let ((sessions nil))
    (maphash
     (lambda (id state)
       (when (eq connection (plist-get state :connection))
         (push id sessions)))
     yeah-acp--sessions)
    (let ((stale nil))
      (maphash (lambda (id question)
                 (when (memq (plist-get question :session-id) sessions)
                   (push id stale)))
               yeah-acp--pending-permissions)
      (dolist (id stale)
        (remhash id yeah-acp--pending-permissions)))
    (dolist (session-id sessions)
      (let* ((state (yeah-acp--session-state session-id))
             (control (and state (plist-get state :control))))
        (when control
          (yeah-control-cancel control "the client disconnected"))))))

(defun yeah-acp--dispatch (method params id)
  "Dispatch ACP METHOD with PARAMS and request ID.
Return a response string for immediate requests, or nil for notifications
and asynchronously answered prompts."
  (pcase method
    ("initialize"
     (yeah-acp--response id (yeah-acp-initialize params)))
    ("session/new"
     (yeah-acp--response id (yeah-acp-session-new params)))
    ("session/load"
     (yeah-acp--response id (yeah-acp-session-load params)))
    ("session/prompt"
     (yeah-acp-session-prompt params id))
    ("session/cancel"
     (yeah-acp-session-cancel params))
    ("session/steer"
     (yeah-acp--response id (yeah-acp-session-steer params)))
    ("session/withdraw"
     (yeah-acp--response id (yeah-acp-session-withdraw params)))
    ("session/recover"
     (yeah-acp--response id (yeah-acp-session-recover params)))
    (_
     (yeah-acp--error id -32601 (format "Method not found: %s" method)))))

(defun yeah-acp-handle-message (json-string)
  "Handle one JSON-RPC message string and return a response string or nil."
  (condition-case nil
      (let* ((parsed (json-parse-string json-string :object-type 'plist
                                        :array-type 'list))
             (method (plist-get parsed :method))
             (id (plist-get parsed :id))
             (params (or (plist-get parsed :params) '())))
        (if (null method)
            (when (yeah-acp--route-response parsed)
              nil)
          (condition-case err
              (yeah-acp--dispatch method params id)
            (user-error
             (yeah-acp--error id -32602 (error-message-string err))))))
    (error
     (yeah-acp--error nil -32700 "Parse error"))))

(defun yeah-acp--read-line ()
  "Read one line from standard input, or nil at end of file."
  (yeah-wire-read-line))

(defun yeah-acp--live-turns ()
  "Return the turns that run now, one per session at most.
The turn of a session is the one its controller runs: the wire drives the
sessions through their controllers, so the controllers know what runs."
  (let (turns)
    (maphash
     (lambda (_id state)
       (let ((control (plist-get state :control)))
         (when-let ((turn (and control (yeah-control-active-turn control))))
           (unless (yeah-turn-done turn)
             (push turn turns)))))
     yeah-acp--sessions)
    turns))

;;;###autoload
(defun yeah-acp-serve (&optional transport answerer output-function)
  "Serve ACP over standard input/output until EOF.
TRANSPORT and ANSWERER configure the agent for this service process.
OUTPUT-FUNCTION receives serialized JSON messages and defaults to stdout.
After each request the server lets the work it started settle, so an
asynchronous prompt answer leaves before the next request is read.
A cancellation that arrives while a prompt runs is therefore read only
after that prompt settled; `yeah-acp-serve-socket' does not have this
limit."
  (setq yeah-acp--transport transport
        yeah-acp--answerer answerer
        yeah-acp--output-function (or output-function #'yeah-acp--print-line))
  (let ((yeah-acp--output yeah-acp--output-function))
    (catch 'eof
      (while t
        (let ((line (yeah-acp--read-line)))
          (unless line
            (throw 'eof nil))
          (unless (string-blank-p line)
            (let ((response (yeah-acp-handle-message line)))
              (when response
                (funcall yeah-acp--output-function response)))
            (yeah-wire-pump-until
             (lambda () (null (yeah-acp--live-turns)))))))))
  nil)

;;;###autoload
(defun yeah-acp-serve-socket (service &optional transport answerer family)
  "Serve ACP on the local socket SERVICE until the server stops.
TRANSPORT and ANSWERER configure the agent for this service process.
FAMILY is `local' for a Unix socket and `ipv4' for a loopback TCP port.
The connection is a process, so the event loop keeps running while the
server waits: a `session/cancel' that arrives during a running prompt is
handled while that prompt is still running, and two connections are
served at the same time."
  (setq yeah-acp--transport transport
        yeah-acp--answerer answerer)
  (yeah-wire-socket-serve
   service
   (lambda (line respond &optional connection)
     (let ((yeah-acp--output respond)
           (yeah-acp--connection connection))
       (let ((response (yeah-acp-handle-message line)))
         (when response
           (funcall respond response)))))
   family
   #'yeah-acp--connection-closed))

(defun yeah-acp--reset-for-test ()
  "Clear ACP sessions, listeners and pending questions for tests."
  (maphash
   (lambda (_id state)
     (when-let ((listener (plist-get state :listener)))
       (setq yeah-events-write-functions
             (delete listener yeah-events-write-functions))))
   yeah-acp--sessions)
  (clrhash yeah-acp--sessions)
  (clrhash yeah-acp--pending-permissions)
  (clrhash yeah-acp--client-capabilities)
  (setq yeah-acp--counter 0))

(provide 'yeah-acp)
;;; yeah-acp.el ends here
