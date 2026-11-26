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
(require 'yeah-context)
(require 'yeah-events)
(require 'yeah-life)
(require 'yeah-model)
(require 'yeah-perm)
(require 'yeah-product)
(require 'yeah-result)
(require 'yeah-session-mcp)
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
client remembered for this session come last: the last match wins.
The standing permissions are the rules of the carriers that keep their
rules in a file and the rules of the process."
  (let ((state (yeah-acp--session-state session-id)))
    (append (yeah-perm-file-rules)
            (yeah-perm-rules-list)
            (plist-get state :rules))))

(defconst yeah-acp--default-mode "build"
  "The mode a session is in when the client has not chosen another one.
The mode asks once for work in the session's workspace and then keeps
that grant.  Work outside the workspace and work of the shell ask their
own grants.")

(defconst yeah-acp--mode-names
  '(("plan" "Plan" "the agent may look at the world, but not change it")
    ("build" "Build" "the agent may change the world, and the person decides each step")
    ("auto" "Auto" "the agent may change the world, and nobody is there to answer"))
  "The name and the description of every mode of a session.
The modes themselves are the permission profiles of the kernel
(`yeah-perm-profiles'); this table only names them for the client, which
shows the names and the descriptions to the person.")

(defun yeah-acp--available-modes ()
  "Return the modes a session may be in.
Every mode is a permission profile of the kernel, and every profile has a
name and a description for the client.  The modes travel as a vector: a
list of objects does not serialize, and the wire of ACP carries an array."
  (apply #'vector
         (mapcar
          (lambda (id)
            (let ((entry (assoc id yeah-acp--mode-names)))
              (list :id id
                    :name (if entry (nth 1 entry) id)
                    :description (if entry (nth 2 entry)))))
          '("plan" "build" "auto"))))

(defun yeah-acp--mode-state (mode-id)
  "Return the state of the modes of a session in MODE-ID.
The state names the mode the session is in and every mode it may be in."
  (list :currentModeId mode-id
        :availableModes (yeah-acp--available-modes)))

(defun yeah-acp--mode-effect (mode request)
  "Return the effect the mode MODE gives for REQUEST.
The mode is a permission profile: `plan' denies the tools that change the
world, and every other profile leaves the question to the person.  A mode
that the kernel does not know decides nothing."
  (let ((rules (yeah-perm-profile (or mode yeah-acp--default-mode))))
    (if rules
        (yeah-perm-effect (plist-get request :action)
                          (plist-get request :resource)
                          rules)
      'ask)))

(defun yeah-acp--mode-denies-p (mode request)
  "Return non-nil when the mode MODE forbids REQUEST.
The mode of a session is the decision of the person and not a question to
the person: a mode that forbids an action refuses it without asking."
  (eq (yeah-acp--mode-effect mode request) 'deny))

(defun yeah-acp--session-mode (session-id)
  "Return the mode of SESSION-ID."
  (let ((state (yeah-acp--session-state session-id)))
    (or (plist-get state :mode) yeah-acp--default-mode)))

(defconst yeah-acp--model-option-id "model"
  "The id of the configuration option of the model.
ACP names the option by its id, and the client of Paseo looks for the
  option whose category is `model'.")

(defconst yeah-acp--workspace-option-id "workspaceTrust"
  "The id of the workspace-trust configuration option.
ACP spells the option as a boolean: on means Build asks once for work in
the session directory; off restores the old per-call questions.")

(defun yeah-acp--session-model (state)
  "Return the name of the model the session of STATE runs on.
The model the client chose for the session comes first, and the model of
the service comes next: a session that nobody gave a model runs on the
model the transport would use."
  (or (plist-get state :model) (yeah-model-default)))

(defun yeah-acp--model-option (model)
  "Return the configuration option of the model, with MODEL in it.
The option is a choice: it names every model a session may run on, and the
one the session runs on now.  The options travel as a vector, because a list
of objects does not serialize and the wire of ACP carries an array."
  (list :id yeah-acp--model-option-id
        :name "Model"
        :category "model"
        :type "select"
        :currentValue model
        :options (apply #'vector
                        (mapcar (lambda (name) (list :value name :name name))
                                (yeah-model-names)))))

(defun yeah-acp--workspace-trust-option (state)
  "Return the workspace-trust option of session STATE."
  (list :id yeah-acp--workspace-option-id
        :name "Workspace trust"
        :category "permissions"
        :type "boolean"
        :currentValue (yeah-acp--workspace-trust-p state)))

(defun yeah-acp--workspace-trust-p (state)
  "Return non-nil when Build trusts one grant for the workspace of STATE.
The legacy sessions that were opened in the short-lived Workspace mode
keep that meaning: their journal says workspace, and Build plus trust is
the behaviour they had."
  (or (equal (plist-get state :mode) "workspace")
      (not (eq (plist-get state :workspace-trust) :false))))

(defun yeah-acp--config-options (model &optional state)
  "Return the configuration options of a session that runs on MODEL.
The options travel as a vector: a list of objects does not serialize, and
the wire of ACP carries an array."
  (if state
      (vector (yeah-acp--model-option model)
              (yeah-acp--workspace-trust-option state))
    (vector (yeah-acp--model-option model))))

(defun yeah-acp--option-kind (answer)
  "Return the kind of the ACP option that offers ANSWER.
The kind stays inside the vocabulary of ACP: `allow_once', `allow_always'
and `reject_once'.  The scope of the answer travels in the option id and
not in the kind: the kind says what the answer does, and the option id
says how long it lives."
  (pcase (yeah-approval-reply-canonical answer)
    (:once "allow_once")
    (:reject "reject_once")
    (_ "allow_always")))

(defun yeah-acp--permission-options ()
  "Return the options of the question of a permission.
The question offers the four scopes of an answer and the refusal.  The
options are derived from the dictionary of the answers: the option id is
the wire name of the answer, and the name is the words the surfaces of
the kernel use for it."
  (vconcat
   (mapcar (lambda (answer)
             (list :optionId (yeah-approval-reply-on-wire
                              (yeah-approval-effect-of answer) answer)
                   :name (yeah-approval-label answer)
                   :kind (yeah-acp--option-kind answer)))
           (yeah-approval-reply-kinds))))

(defun yeah-acp--ask-client (session-id output request)
  "Ask the client about REQUEST and return the deferral of the question.
The question carries the four scopes of an answer -- once, session,
project and global -- and the refusal.  The scope travels in the option
id: the kind of the option stays inside the vocabulary of ACP.  The
question itself is kept, so that the answer reaches the turn that asked
and may be remembered."
	  (let* ((state (yeah-acp--session-state session-id))
	         (class (and state (yeah-acp--workspace-class state request)))
	         (trusted (and state (yeah-acp--workspace-trust-p state)
	                       (member (or (plist-get state :mode) yeah-acp--default-mode)
	                               '("workspace" "build"))))
	         (workspace (and trusted (eq class :inside)))
	         (workspace-shell (and trusted (eq class :shell)
	                               (equal (plist-get request :action) "bash")))
         (request-id (yeah-acp--fresh-id "perm"))
         (params (list :sessionId session-id
                       :toolCall (list :toolCallId request-id
                                       :title (format "%s on %s"
                                                      (plist-get request :action)
                                                      (plist-get request :resource))
                                       :rawInput
                                       (yeah-acp--jsonable-args
                                        (plist-get request :args)))
                       :options (yeah-acp--permission-options))))
	    (puthash request-id
	             (list :session-id session-id
	                   :action (plist-get request :action)
		                   :resource (plist-get request :resource)
		                   :workspace workspace
		                   :workspace-shell workspace-shell)
	             yeah-acp--pending-permissions)
    (funcall output (json-serialize
                     (list :jsonrpc "2.0" :id request-id
                           :method "session/request_permission"
                           :params params)))
    (list :defer request-id)))

(defconst yeah-acp--carrier 'session
  "The carrier of the rules an ACP session writes: the rules of this
session.  The scope of that carrier is the scope of an answer of the
session.")

(defun yeah-acp--client-answerer (session-id output)
  "Return the answerer of SESSION-ID that asks the client over the wire.
The rules decide first; what they do not name is asked of the client as a
`session/request_permission', and the call waits for the answer.  A safe
read needs no question: it is allowed, and it says why.  The question
offers the four scopes of an answer and the refusal, and the answer that
comes back carries the scope it named."
  (lambda (request)
    (yeah-approval-scope-decision
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
                (yeah-acp--ask-client session-id output request)))))
     yeah-acp--carrier)))

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

(defun yeah-acp--mode-allows (state request)
  "Return the decision that the mode of STATE allows REQUEST without a question.
A standing refusal of the person still wins: the mode of the session is
the decision about the session, and the refusal of the person about a
tool is the decision about that tool."
  (let ((action (plist-get request :action))
        (resource (plist-get request :resource)))
    (if (eq (yeah-perm-effect action resource (yeah-perm-effective-rules)) 'deny)
        (list :effect :deny :reply :reject
              :reason (format "the standing permissions deny %s on %s"
                              action resource))
      (list :effect :allow :reply :once
            :reason (format "the %s mode allows %s without a question"
                            (or (plist-get state :mode) yeah-acp--default-mode)
                            action)))))

(defun yeah-acp--session-answerer (state)
  "Return the answerer of STATE: the client of the session over the wire.
The mode of the session decides first: a mode that forbids an action
refuses it without a question, and a mode that allows it allows it
without a question -- a mode is the decision of the person and not a
question to the person.  The rules of the session decide next; what
they do not name is asked of the client as a
`session/request_permission', and the call waits for the answer.  The
question is asked of the connection the session belongs to."
	  (lambda (request)
	    (let ((mode (plist-get state :mode)))
	      (cond
	       ((yeah-acp--mode-denies-p mode request)
        (list :effect :deny :reply :reject
              :reason (format "the %s mode does not allow %s"
                              (or mode yeah-acp--default-mode)
                              (plist-get request :action))))
	       ((eq (yeah-acp--mode-effect mode request) 'allow)
	        (yeah-acp--mode-allows state request))
	       ((and (yeah-acp--workspace-trust-p state)
	             (member (or mode yeah-acp--default-mode) '("workspace" "build")))
	        (yeah-acp--workspace-answerer state request))
	       (t
        (funcall (or yeah-acp--answerer
                     (yeah-acp--client-answerer (plist-get state :id)
                                                 (yeah-acp--output-for state)))
	                  request))))))

(defun yeah-acp--workspace-root (state)
  "Return the project root of the workspace session STATE."
  (file-truename (or (plist-get state :cwd) default-directory)))

(defun yeah-acp--workspace-shell-resource (state)
  "Return the resource name of one shell grant for the root of STATE.
The resource names the place where commands start, not a command string:
one answer for Bash in this workspace must allow the next Bash command
there as well."
  (concat "workspace:" (yeah-acp--workspace-root state)))

(defun yeah-acp--workspace-inside-p (state path)
  "Return non-nil when PATH names a file below the root of STATE.
A nil or empty PATH names no place outside the workspace: the tool
falls back to the session directory, and that directory is inside."
  (or (not (stringp path))
      (string-empty-p path)
      (file-in-directory-p (expand-file-name path (yeah-acp--workspace-root state))
                           (yeah-acp--workspace-root state))))

(defun yeah-acp--workspace-class (state request)
  "Return where REQUEST acts in the workspace mode of STATE.
`:shell' is the escape hatch to the whole machine: it always has its own
grant, even after the workspace itself was granted.  `:outside' is a
path below another root.  `:inside' is work below the root of the
session.  Everything else is treated as inside work unless a rule or a
person says otherwise."
  (let* ((action (plist-get request :action))
         (args (plist-get request :args))
         (named (yeah-tools-named-args action args))
         (directory (plist-get named :directory))
         (path (or (plist-get named :path) directory)))
    (cond
     ((member action '("bash" "job-cancel"))
      (if (and (stringp directory)
               (not (string-empty-p directory))
               (not (yeah-acp--workspace-inside-p state directory)))
          :outside
        :shell))
     ((equal action "delegate") :outside)
     ((and (stringp path) (not (string-empty-p path)))
      (if (yeah-acp--workspace-inside-p state path) :inside :outside))
     (t :inside))))

(defun yeah-acp--workspace-granted-p
    (session-id request &optional wildcard-only exact-only)
  "Return non-nil when the session rules allow REQUEST.
WILDCARD-ONLY asks only for the workspace-wide grant; otherwise an
exact rule of this request is enough as well."
  (let* ((rules (yeah-acp--session-rules session-id))
         (wildcard (eq (yeah-perm-effect "*" "*" rules) 'allow))
         (exact (seq-some
                 (lambda (rule)
                   (and (eq (plist-get rule :effect) 'allow)
                        (equal (plist-get rule :action)
                               (plist-get request :action))
                        (equal (plist-get rule :resource)
                               (plist-get request :resource))))
                 rules)))
    (cond
     (exact-only exact)
     (wildcard-only wildcard)
     (t (or wildcard exact)))))

(defun yeah-acp--workspace-shell-granted-p (state)
  "Return non-nil when session rules grant Bash in the root of STATE.
The grant is the workspace shell resource, not one exact command: one
answer for Bash there has to cover the next command there too."
  (let ((resource (yeah-acp--workspace-shell-resource state)))
    (seq-some
     (lambda (rule)
       (and (eq (plist-get rule :effect) 'allow)
            (equal (plist-get rule :action) "bash")
            (equal (plist-get rule :resource) resource)))
     (yeah-acp--session-rules (plist-get state :id)))))

(defun yeah-acp--workspace-answerer (state request)
  "Answer REQUEST in the workspace mode of STATE.
Inside work is allowed by one workspace-wide grant for the session,
project or user.  Work below another root and shell work are never
covered by that grant: the first asks separately, and the person may
answer once for this call, for the session, for the project or for the
user.  A safe read inside the workspace needs no question."
  (let* ((session-id (plist-get state :id))
         (class (yeah-acp--workspace-class state request))
         (ask (yeah-acp--client-answerer session-id (yeah-acp--output-for state))))
    (cond
	     ((eq class :shell)
	      (if (yeah-acp--workspace-shell-granted-p state)
	          (list :effect :allow :reply :once
	                :reason "the shell grant allows this command")
        (funcall ask request)))
     ((eq class :outside)
      (if (yeah-acp--workspace-granted-p session-id request nil t)
          (list :effect :allow :reply :once
                :reason "the outside grant allows this path")
        (funcall ask request)))
     ((yeah-acp--workspace-granted-p session-id request t)
      (list :effect :allow :reply :once
            :reason "the workspace grant allows this action"))
     (t
      (or (yeah-approval-safe-read-decision request)
          (funcall ask request))))))

(defun yeah-acp--session-transport (state)
  "Return the transport of the session of STATE.
The transport of the service is the transport of every session, and the
model of the session is bound around the call of that transport: the model
in force is a property of the call, and two sessions that work at the same
time do not see each other's model.  The transport keeps its shape -- it
takes a prompt and a callback."
  (let ((base (or yeah-acp--transport yeah-acp-default-transport
                    (and (fboundp 'yeah-gptel-request) #'yeah-gptel-request))))
	  (if base
	        (lambda (prompt callback)
	          (let ((yeah-model--current (yeah-acp--session-model state)))
	            (if (eq base #'yeah-gptel-request)
	                (funcall base prompt callback
	                         :system (yeah-acp--session-system-prompt state))
	              (funcall base prompt callback))))
	  base)))

(defun yeah-acp--session-system-prompt (state)
  "Return the model system prompt for the session STATE.
The model is told where the session lives, because a model that does not
know its directory guesses -- and a guess may walk through every project
under the parent directory."
  (concat yeah-gptel-prelude
          (format "\nYou are working in the directory %s.\nStay inside this directory unless the person explicitly asks for another place.\n"
                  (yeah-acp--workspace-root state))))

(defun yeah-acp--make-control (state)
  "Return the controller of STATE.
The controller owns the turn of the session and its persistent pending
queue: the wire and the attached path share one queue, one set of journal
events and one set of semantics.  The transport and the answerer are the
service's, and the working directory travels with every input.

The tools of the session travel with it too: the tools of the MCP servers
the client named belong to the runs of this session and to no other run.
The frozen configuration names the servers, and only their names: the
command of a server and its environment may hold secrets, and a secret is
never written into the log."
  (yeah-control-new (plist-get state :session)
                    (yeah-acp--session-transport state)
                    (yeah-acp--session-answerer state)
                    nil nil
                    (list :cwd (plist-get state :cwd)
                          :mcp-servers (plist-get state :mcp-servers))
                    (plist-get state :mcp-tools)))

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
              :mcpCapabilities (list :http t :sse :false)
              ;; `session/close' is a part of ACP: the client asks the agent
              ;; to close the session, and the agent says it did.
              :sessionCapabilities (list :close (list)))))

(defun yeah-acp--remember-capabilities (handshake)
  "Remember the client capabilities of HANDSHAKE for the current connection.
What the client announced is what it understands of the wire: Yeah's own
events travel to the clients that asked for them and to nobody else."
  (puthash yeah-acp--connection
           (plist-get handshake :clientCapabilities)
           yeah-acp--client-capabilities))

(defun yeah-acp--meta-capability-p (state capability)
  "Return non-nil when the client of STATE announced CAPABILITY in its `_meta'.
What the client announced is what it understands of the wire: Yeah's own
events travel to the clients that asked for them and to nobody else."
  (let* ((capabilities (gethash (plist-get state :connection)
                                yeah-acp--client-capabilities))
         (meta (and (listp capabilities) (plist-get capabilities :_meta))))
    (and (listp meta)
         (eq t (plist-get meta capability)))))

(defun yeah-acp--queue-events-p (state)
  "Return non-nil when the client of STATE asked for Yeah's queue events.
The queue events are Yeah's own vocabulary, not the vocabulary of ACP: a
client that does not know them refuses the whole update.  A client asks
for them in the `_meta' of the capabilities it announced."
  (yeah-acp--meta-capability-p state yeah-acp-queue-events-capability))

(defun yeah-acp--outcome-events-p (state)
  "Return non-nil when the client of STATE asked for the outcome of a run.
The outcome of a run is Yeah's own vocabulary, not the vocabulary of ACP: a
client that does not know it refuses the whole update.  A client asks for it
in the `_meta' of the capabilities it announced."
  (yeah-acp--meta-capability-p state yeah-acp-outcome-capability))

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

(defun yeah-acp--tool-arguments (fields)
  "Return the arguments of the call in FIELDS as a value for the wire.
FIELDS are the fields of the record of the request of a tool.  The record
carries the arguments under the names the tool declared, and the wire
carries them under those names: a client that looks for `path' or
`old_str' finds them.

A record written before the kernel named the arguments holds the printed
form of them only, and the wire falls back to the values in the order they
came."
  (let ((named (plist-get fields :named_args)))
    (if named
        named
      (yeah-acp--tool-input (plist-get fields :args)))))

(defun yeah-acp--tool-call (tool-call-id name kind status &optional input result)
  "Return a tool_call or tool_call_update ACP update for TOOL-CALL-ID.
NAME is the name of the tool and KIND is its kind: a client renders the
call of a tool by its kind, and the kind of a call is a fact of the tool
and not a guess of its name.  INPUT is what the tool was called with and
RESULT is what it returned.  The protocol has a field for each of them, and
a client that shows the call of a tool shows them: a call without its input
is a name."
  (if (eq status 'started)
      (let ((update (list :sessionUpdate "tool_call"
                           :toolCallId tool-call-id
                           :title name
                           :status "pending")))
        (when (stringp kind)
          (plist-put update :kind kind))
        (when input
          (plist-put update :rawInput input))
        update)
    (let ((update (list :sessionUpdate "tool_call_update"
                         :toolCallId tool-call-id
                         :status (if (eq status 'failed) "failed" "completed")
                         :content (vector (list :type "text"
                                                :text (or result ""))))))
      (when (stringp kind)
        (plist-put update :kind kind))
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
    ("reasoning"
     ;; The road to the answer is visible too: ACP has a thought chunk, and
     ;; Paseo renders it as Thinking. The journal keeps the same bounded text.
     (yeah-acp--content-chunk "agent_thought_chunk"
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
      (plist-get fields :tool)
      (plist-get fields :kind)
      'started
      (yeah-acp--tool-arguments fields)))
    ("tool-end"
     (yeah-acp--tool-call
      (or (plist-get fields :tool_call_id) id)
      (plist-get fields :tool)
      (plist-get fields :kind)
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
    ("session-mode"
     ;; The mode of a session is its state, and the journal is where the
     ;; state of a session lives: a client that opens a session again learns
     ;; the mode from the replay of the journal.
     (list :sessionUpdate "current_mode_update"
           :currentModeId (plist-get fields :mode)))
    ("session-model"
     ;; The model of a session is its state in the same way: the journal
     ;; names it, and the client learns it from the replay of the journal.
     (list :sessionUpdate "config_option_update"
	   :configOptions (yeah-acp--config-options
	                           (plist-get fields :model))))
    (_ nil)))

(defconst yeah-acp--outcome-types '("nudge" "unfinished" "error")
  "The events of the journal that tell how a run ended.
The tokens a run spent are not here: they travel as `usage_update', which is
a part of ACP, and the client of the orchestrator counts them itself.")

(defun yeah-acp--send-outcome (state type fields)
  "Send the outcome event TYPE with FIELDS to the client of STATE.
The outcome of a run is Yeah's own vocabulary: it travels to the clients that
asked for it and to nobody else.  The method of the notification is not a
method of ACP, and the orchestrator learns the outcome through the plugin
that translates it."
  (when (and (member type yeah-acp--outcome-types)
             (yeah-acp--outcome-events-p state))
    (funcall (yeah-acp--output-for state)
             (json-serialize
              (list :jsonrpc "2.0"
                    :method yeah-acp-outcome-method
                    :params (append (list :sessionId (plist-get state :id)
                                          :outcome type)
                                    fields))))))

(defun yeah-acp--send-usage (state session)
  "Send the context usage of SESSION to the client of STATE.
`usage_update' is a part of ACP, and the client of the orchestrator counts the
tokens of the context itself.  The size of the context is the budget of the
kernel and not the window of the provider: the kernel does not know the window
of the provider and does not guess it.

The update travels only to the clients that asked for the outcome of a run:
the kind of the update is marked as unstable in ACP, and a client built on an
older schema refuses the whole update it does not know."
  (when (yeah-acp--outcome-events-p state)
    (let* ((usage (yeah-context-usage (yeah-session-records session)))
           (used (or (plist-get usage :total) 0)))
      (yeah-acp--send-update
       (plist-get state :id)
       (list :sessionUpdate "usage_update"
             :used used
             :size yeah-context-default-budget)
       (yeah-acp--output-for state)))))

(defun yeah-acp--usage-events-p (state)
  "Return non-nil when the client of STATE asked for the tokens of a turn.
The tokens of a turn are Yeah's own vocabulary, not the vocabulary of ACP: a
client that does not know them refuses the whole update.  A client asks for
them in the `_meta' of the capabilities it announced."
  (yeah-acp--meta-capability-p state yeah-acp-usage-capability))

(defun yeah-acp--send-usage-of-turn (state fields)
  "Send the tokens of the turn to the client of STATE.
FIELDS are the fields of the journal record of the usage: the provider of the
model reported the tokens it spent, and the kernel does not count them itself.

The notification travels only to the clients that asked for the tokens of a
turn: the method of the notification is not a method of ACP, and a client that
does not know it refuses the whole message.  The client of the orchestrator
translates it into the number of tokens the orchestrator shows."
  (when (yeah-acp--usage-events-p state)
    (let ((input (plist-get fields :input))
          (output (plist-get fields :output)))
      (when (or (numberp input) (numberp output))
        (funcall (yeah-acp--output-for state)
                 (json-serialize
                  (list :jsonrpc "2.0"
                        :method yeah-acp-usage-method
                        :params (list :sessionId (plist-get state :id)
                                      :inputTokens (if (numberp input) input 0)
                                      :outputTokens (if (numberp output) output 0)))))))))

(defun yeah-acp--observe-event (state session type fields id)
  "Send ACP updates for journal events belonging to STATE's SESSION."
  (when (eq session (plist-get state :session))
    (let ((update (yeah-acp--update-for type fields id
                                         (yeah-acp--queue-events-p state))))
      (when update
        (yeah-acp--send-update (plist-get state :id) update
                               (yeah-acp--output-for state))))
    ;; The outcome of the run: the orchestrator must see how the run ended
    ;; and not only that it ended.
    (when (equal "usage" type)
      (yeah-acp--send-usage state session)
      ;; The tokens of the turn: the orchestrator counts them, and the update
      ;; of the context above carries the size of the window and not them.
      (yeah-acp--send-usage-of-turn state fields))
    (yeah-acp--send-outcome state type fields)))

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

(defun yeah-acp--register-session (session cwd &optional tools servers)
  "Register SESSION for ACP and return its state plist.
The state carries the output function of the connection the session was
created on, so its notifications reach that connection; when the session
was created without a connection the current output function is used.
The state also carries the rules the client remembered for this session:
a decision of the client is remembered here and in no other session.
The state carries the model the client chose for this session, the tools
of the MCP servers the client named, and the controller of the session:
its turn and its queue."
  (let* ((id (plist-get session :id))
         (previous (gethash id yeah-acp--sessions))
         (state (list :id id :session session :cwd cwd :listener nil
                      :output yeah-acp--output
                      :connection yeah-acp--connection
                     :model nil
                      :workspace-trust t
                      :rules nil
                      :mcp-tools tools
                      :mcp-servers servers))
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
  "Create a real Yeah session for ACP REQUEST and return its answer.
The answer names the session, the modes it may be in and the
configuration options of the session: the modes are the permission
profiles of the kernel, the session is in the mode `build' until the
client chooses another one, and the options are the models the session may
run on.

The MCP servers the client names are connected before the session is
opened: their tools are the tools of the session, and a session whose
servers did not answer is not opened at all."
  (yeah-acp--validate-session-request request)
  (let* ((cwd (file-truename (plist-get request :cwd)))
         (root (yeah-product-session-root cwd))
         (clients (yeah-session-mcp-connect (plist-get request :mcpServers)))
         (session (yeah-session-open (yeah-acp--fresh-id "session") root cwd))
         (state (yeah-acp--register-session
                 session cwd
                 (yeah-session-mcp-tools clients)
                 (yeah-session-mcp-names (plist-get request :mcpServers)))))
    (plist-put state :mcp-clients clients)
    (list :sessionId (plist-get session :id)
          :modes (yeah-acp--mode-state yeah-acp--default-mode)
          :configOptions (yeah-acp--config-options
                          (yeah-acp--session-model state) state))))

(defun yeah-acp--journal-mode (session)
  "Return the mode the journal of SESSION names, or nil.
The mode of a session is part of its state, and the journal is where the
state of a session lives: a session that is opened again keeps the mode
it was left in."
  (let ((mode nil))
    (dolist (record (yeah-session-records session))
      (when (equal "session-mode" (plist-get record :type))
        (setq mode (plist-get record :mode))))
    mode))

(defun yeah-acp--journal-model (session)
  "Return the model the journal of SESSION names, or nil.
The model of a session is part of its state, and the journal is where the
state of a session lives: a session that is opened again keeps the model
it was left in."
  (let ((model nil))
    (dolist (record (yeah-session-records session))
      (when (equal "session-model" (plist-get record :type))
        (setq model (plist-get record :model))))
    model))

(defun yeah-acp-session-load (request)
  "Load an existing session and replay its journal into the editor's view.
The records of the session become session/update notifications, so that the
editor can rebuild the transcript of a session it opens again.  The answer
names the session, the number of records that were replayed, the modes of
the session and its configuration options: the mode the journal names is
the mode it is in, and the model it names is the model it runs on."
  (yeah-acp--validate-session-request request t)
  (let* ((cwd (file-truename (plist-get request :cwd)))
         (root (yeah-product-session-root cwd))
         (session-id (plist-get request :sessionId)))
    ;; A session whose journal has no file yet is a session of this process:
    ;; the journal of a session appears with its first record (wave 67), so a
    ;; session that was created and never wrote has no file and is still
    ;; known here.  Only a session that the process knows nothing about is
    ;; refused.
    (unless (or (file-exists-p (yeah-session--path-for session-id root))
                (gethash session-id yeah-acp--sessions))
      (signal 'user-error
              (list (format "unknown ACP session: %s" session-id))))
    (let* ((clients (yeah-session-mcp-connect (plist-get request :mcpServers)))
           (session (yeah-session-open session-id root cwd))
           (state (yeah-acp--register-session
                   session cwd
                   (yeah-session-mcp-tools clients)
                   (yeah-session-mcp-names (plist-get request :mcpServers))))
           (mode (or (yeah-acp--journal-mode session) yeah-acp--default-mode)))
      (plist-put state :mcp-clients clients)
      (plist-put state :mode mode)
      (plist-put state :model (yeah-acp--journal-model session))
      (list :sessionId (plist-get session :id)
            :replayed (yeah-acp--replay state session)
            :modes (yeah-acp--mode-state mode)
            :configOptions (yeah-acp--config-options
                            (yeah-acp--session-model state) state)))))

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

(defun yeah-acp--usage-of-turn (session turn)
  "Return the ACP usage of the run of TURN in SESSION, or nil.
The tokens of a run are what the provider reported and nothing else: the
kernel does not guess the tokens of a provider that said nothing.  A run that
reported no usage has no usage in its answer either.

The run of a prompt is one run of the session, and its `usage' records share
the run id of that run, so the sum of them is the cost of this prompt and not
the cost of the whole session."
  (when turn
    (let ((run-id (yeah-turn-id turn))
          (input 0)
          (output 0)
          (reported nil))
      (dolist (record (yeah-session-records session))
        (when (and (equal (plist-get record :type) "usage")
                   (equal (plist-get record :run_id) run-id))
          (setq reported t)
          (setq input (+ input (or (plist-get record :input) 0)))
          (setq output (+ output (or (plist-get record :output) 0)))))
      (when reported
        (list :totalTokens (+ input output)
              :inputTokens input
              :outputTokens output)))))

(defun yeah-acp-session-prompt (request id)
  "Queue a prompt for REQUEST and send its response later under request ID.
The prompt is an ordinary ask of the session's controller: it runs when the
session is idle and waits in the queue of the session when a run is active.
The response leaves when the run reaches a terminal state, and it carries the
same stop reasons as before.

The response carries the tokens of the run in the `usage' field of ACP: a
client that counts the tokens of a turn reads them there, and a client that
does not know the field ignores it."
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
               :result
               (append
                (list :stopReason
                      (yeah-acp--completion-stop-reason completion))
                (let ((usage (yeah-acp--usage-of-turn
                              (plist-get state :session)
                              (plist-get completion :turn))))
                  (when usage (list :usage usage))))))))))
  nil)

(defvar yeah-acp--last-session-closed nil
  "Non-nil when the client closed the last session of this server.
A server that serves one client over a pipe ends with that session: the
process must not outlive the agent.  A service on a socket outlives its
sessions by design and does not read this flag.")

(defun yeah-acp-session-set-mode (request)
  "Set the mode of the session named by REQUEST and answer that it is set.
REQUEST carries the `sessionId' and the `modeId'.  A mode is the permission
profile of the session: in the `plan' mode the tools that change the world
are refused without a question, and in the `build' mode the person decides
each one of them.  The answer is empty, as ACP says, and the client learns
the new mode from the journal of the session, which names it."
  (let* ((session-id (plist-get request :sessionId))
         (mode-id (plist-get request :modeId)))
	    (unless (stringp session-id)
	      (signal 'user-error (list "session/set_mode needs sessionId")))
	  (unless (and (stringp mode-id)
	               (member mode-id '("plan" "build" "auto")))
	      (signal 'user-error
              (list (format "session/set_mode: unknown mode %S" mode-id))))
    (let* ((state (yeah-acp--session-state session-id t))
           (session (plist-get state :session)))
      (plist-put state :mode mode-id)
      (yeah-events-write session "session-mode" :mode mode-id)
      (list))))

(defun yeah-acp-session-set-config-option (request)
  "Set the configuration option named by REQUEST and answer with the options.
REQUEST carries the `sessionId', the `configId' and the `value'.  The
model option names the model the session runs on; the model of the
session is bound around the call of the transport, so the next run of the
session goes to that model.  The workspace-trust option is the separate
Build toggle: on means one answer covers later work in this directory;
off means Build asks per call.  A model that no session may run on is
refused: the catalog of the kernel names the models that can really run.

The answer carries every option of the session with its new value, as ACP
says, and the journal of the session names the model it was left in."
  (let* ((session-id (plist-get request :sessionId))
         (config-id (plist-get request :configId))
         (value (plist-get request :value)))
    (unless (stringp session-id)
      (signal 'user-error (list "session/set_config_option needs sessionId")))
    (unless (member config-id
                    (list yeah-acp--model-option-id
                          yeah-acp--workspace-option-id))
      (signal 'user-error
              (list (format "session/set_config_option: unknown option %S"
                            config-id))))
    (let* ((state (yeah-acp--session-state session-id t))
           (session (plist-get state :session)))
      (if (equal config-id yeah-acp--workspace-option-id)
          (progn
            (unless (memq value '(:true :false))
              (signal 'user-error
                      (list (format "session/set_config_option: %S is not a boolean"
                                    value))))
            (plist-put state :workspace-trust (eq value :true))
            (yeah-events-write session "session-workspace-trust"
                               :enabled (eq value :true)))
        (unless (yeah-model-known-p value)
          (signal 'user-error
                  (list (format "session/set_config_option: unknown model %S" value))))
        (plist-put state :model value)
        (yeah-events-write session "session-model" :model value))
      (list :configOptions (yeah-acp--config-options
                            (yeah-acp--session-model state) state)))))

(defun yeah-acp-session-close (request)
  "Close the session named by REQUEST and answer that it is closed.
The turn that runs in the session is cancelled, the session leaves the
registry of the server, and the server that serves one client over a pipe
ends with it -- the process must not outlive the agent, and the client
that keeps the pipe open does not decide when the process goes.

ACP says `session/close' is a request, so the answer leaves before the
server stops."
  (yeah-acp--require-session-id request "session/close")
  (let* ((session-id (plist-get request :sessionId))
         (state (yeah-acp--session-state session-id t)))
    (when state
      (let ((control (plist-get state :control)))
        (when control
          (yeah-control-cancel control "closed by the ACP client")))
      (when-let ((listener (plist-get state :listener)))
        (setq yeah-events-write-functions
              (delete listener yeah-events-write-functions)))
      (when-let ((clients (plist-get state :mcp-clients)))
        (yeah-session-mcp-close clients))
      (remhash session-id yeah-acp--sessions)
      (when (= 0 (hash-table-count yeah-acp--sessions))
        (setq yeah-acp--last-session-closed t))))
  (list :closed t))

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
cancelled request, a protocol error, or an unknown option refuses it.
The decision is what the client answered; the scope of the session is
named by the route that remembers it."
  (let* ((error (plist-get message :error))
         (result (plist-get message :result))
         (outcome (plist-get result :outcome))
         (state (plist-get outcome :outcome))
         (option (plist-get outcome :optionId))
         (kind (yeah-approval-reply-from-wire option)))
    (cond
     (error
      (list :effect :deny
            :reason "the client could not answer the permission request"))
     ((equal state "cancelled")
      (list :effect :deny :reason "cancelled"))
     ((eq kind :reject)
      (list :effect :deny :reason "the person refused"))
     (kind
      (list :effect :allow :reply kind))
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
  "Remember a DECISION that is to be remembered for QUESTION.
The decision is remembered for this session only: the standing permissions
of the service are not touched.  The rule carries the scope of the answer,
and it is written into the carrier of its scope: the session itself for
the scope of the session, the file of the project for the scope of the
project, the file of the user for the scope of the user.  An answer that
names another scope is refused by name instead of being written into the
rules of the session."
  (let* ((scoped (yeah-approval-scope-decision decision yeah-acp--carrier))
         (session-id (plist-get question :session-id))
         (state (yeah-acp--session-state session-id))
         (request (cond
                   ((plist-get question :workspace-shell)
                    (list :action "bash"
                          :resource (yeah-acp--workspace-shell-resource state)))
                   ((plist-get question :workspace)
                    (list :action "*" :resource "*"))
                   (t
                    (list :action (plist-get question :action)
                          :resource (plist-get question :resource))))))
    (when-let ((rule (yeah-approval-remember-rule
                      request
                      scoped)))
      (let ((state (yeah-acp--session-state session-id)))
        (yeah-perm-rule-store
         rule yeah-acp--carrier
         (lambda (stored)
           (plist-put state :rules
                      (yeah-perm-rules-append (plist-get state :rules) stored))
           stored))))
    scoped))

(defun yeah-acp--route-response (message)
  "Route a client RESPONSE (a message with an id and no method) to the
permission it answers.  Return non-nil when it was a response."
  (let ((id (plist-get message :id)))
    (when (and id (null (plist-get message :method)))
      (when-let ((question (gethash id yeah-acp--pending-permissions)))
        (remhash id yeah-acp--pending-permissions)
        (let* ((decision (yeah-acp--permission-decision message))
               (scoped (yeah-approval-scope-decision
                        decision yeah-acp--carrier)))
          (when (yeah-approval-remembers-p scoped)
            (yeah-acp--remember-decision question scoped))
          (when-let ((turn (yeah-acp--turn-waiting-for
                            (plist-get question :session-id) id)))
            (yeah-turn-resume-permission turn id scoped)))
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
    ("session/set_mode"
     (yeah-acp--response id (yeah-acp-session-set-mode params)))
    ("session/set_config_option"
     (yeah-acp--response id (yeah-acp-session-set-config-option params)))
    ("session/prompt"
     (yeah-acp-session-prompt params id))
    ("session/cancel"
     (yeah-acp-session-cancel params))
    ("session/close"
     (yeah-acp--response id (yeah-acp-session-close params)))
    ("session/steer"
     (yeah-acp--response id (yeah-acp-session-steer params)))
    ("session/withdraw"
     (yeah-acp--response id (yeah-acp-session-withdraw params)))
    ("session/recover"
     (yeah-acp--response id (yeah-acp-session-recover params)))
    ("session/request_permission"
     ;; The question of a permission travels from the agent to the
     ;; client: the agent asks, the client answers.  A client that sends
     ;; the question to the agent is refused by name: the method is
     ;; known -- the agent sends it -- and the agent does not accept it
     ;; as a request.
     (yeah-acp--error id -32602
                      "the agent asks the client for permission: the question of a permission travels from the agent to the client"))
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
limit.

The server ends with its last session: a client that closes the session
with `session/close' and keeps the pipe of the server open does not keep
the process alive."
  (setq yeah-acp--transport transport
        yeah-acp--answerer answerer
        yeah-acp--output-function (or output-function #'yeah-acp--print-line))
  (let ((yeah-acp--output yeah-acp--output-function))
    (catch 'eof
      (while t
        ;; The client closed the last session: the server ends with it, even
        ;; when the client keeps the pipe of the server open.
        (when yeah-acp--last-session-closed
          (throw 'eof nil))
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
(defun yeah-acp-serve-socket (service &optional transport answerer family life)
  "Serve ACP on the local socket SERVICE until the server stops.
TRANSPORT and ANSWERER configure the agent for this service process.
FAMILY is `local' for a Unix socket and `ipv4' for a loopback TCP port.
The connection is a process, so the event loop keeps running while the
server waits: a `session/cancel' that arrives during a running prompt is
handled while that prompt is still running, and two connections are
served at the same time.

LIFE is the path of the life socket of the owner of this server.  The
server watches it and ends when it ends: a server whose owner is gone
has nobody to serve, and a server left behind by a finished session is
gone with it.  Without LIFE the server takes the socket that its owner
named in YEAH_LIFE_SOCKET, and without that it ends the way it always
ended -- when its last session is closed."
  (setq yeah-acp--transport transport
        yeah-acp--answerer answerer)
  (let* ((life (or life (yeah-life-inherited-path)))
         (watch (and life (yeah-life-socket-connect life))))
    (when (and life (null watch))
      ;; The owner is gone before the server even started: there is
      ;; nothing to serve, and a server that serves nobody is a leftover.
      (yeah-life-socket-close life)
      (error "yeah-acp-serve-socket: the owner of the server is gone"))
    (unwind-protect
        (yeah-wire-socket-serve
         service
         (lambda (line respond &optional connection)
           (let ((yeah-acp--output respond)
                 (yeah-acp--connection connection))
             (let ((response (yeah-acp-handle-message line)))
               (when response
                 (funcall respond response)))))
         family
         #'yeah-acp--connection-closed
         (and watch (lambda () (not (yeah-life-alive-p watch)))))
      (when (and life (not (yeah-life-alive-p watch)))
        ;; The owner is gone: the file of its life is a leftover.
        (yeah-life-socket-close life)))))

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
  (setq yeah-acp--counter 0
        yeah-acp--last-session-closed nil))

(provide 'yeah-acp)
;;; yeah-acp.el ends here
