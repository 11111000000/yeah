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
(require 'yeah-control)
(require 'yeah-events)
(require 'yeah-product)
(require 'yeah-turn)
(require 'yeah-wire)
(require 'yeah-wire-socket)

(defgroup yeah-acp nil
  "Yeah ACP v1 agent."
  :group 'yeah)

(defconst yeah-acp--protocol-version 1
  "ACP v1 protocol version spoken by Yeah.")

(defconst yeah-acp--agent-name "yeah")
(defconst yeah-acp--agent-version "0.1.0")

(defvar yeah-acp--sessions (make-hash-table :test 'equal)
  "Map ACP session ids to their Yeah session state.")

(defvar yeah-acp--active-turns (make-hash-table :test 'equal)
  "Map ACP session ids to their active turns.")

(defvar yeah-acp--pending-permissions (make-hash-table :test 'equal)
  "Map permission request ids to the session they belong to.")

(defvar yeah-acp--connection nil
  "The connection being served, bound dynamically by the socket handler.
A session remembers which connection owns it, so the death of that
connection can cancel the work it started.")

(defun yeah-acp--jsonable-args (args)
  "Return ARGS as a JSON value: an array when every element serializes,
the printed form otherwise."
  (condition-case nil
      (let ((array (apply #'vector args)))
        (ignore (json-serialize array))
        array)
    (error (format "%S" args))))

(defun yeah-acp--client-answerer (session-id output)
  "Return the answerer of SESSION-ID that asks the client over the wire.
The rules decide first; what they do not name is asked of the client as a
`session/request_permission', and the call waits for the answer."
  (lambda (request)
    (let ((effect (yeah-perm-effect (plist-get request :action)
                                    (plist-get request :resource))))
      (pcase effect
        ('allow (list :effect :allow :reply :once))
        ('deny (list :effect :deny :reply :reject
                     :reason (format "the rules deny %s on %s"
                                     (plist-get request :action)
                                     (plist-get request :resource))))
        (_
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
                                          (list :optionId "allow-once" :name "Allow once" :kind "allow_once")
                                          (list :optionId "reject-once" :name "Reject" :kind "reject_once")))))
           (puthash request-id session-id yeah-acp--pending-permissions)
           (funcall output (json-serialize
                            (list :jsonrpc "2.0" :id request-id
                                  :method "session/request_permission"
                                  :params params)))
           (list :defer request-id)))))))

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

(defun yeah-acp-version ()
  "Return the ACP protocol version spoken by Yeah."
  yeah-acp--protocol-version)

(defun yeah-acp--print-line (text)
  "Write TEXT and a newline to standard output."
  (princ text)
  (terpri))

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
  (list :protocolVersion yeah-acp--protocol-version
        :agentInfo (list :name yeah-acp--agent-name
                         :version yeah-acp--agent-version)
        :agentCapabilities
        (list :loadSession t
              :promptCapabilities (list :image :false
                                        :audio :false
                                        :embeddedContext :false)
              :mcpCapabilities (list :http :false :sse :false))))

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
  "Return an ACP content chunk of KIND containing TEXT."
  (list :sessionUpdate kind
        :content (list :type "text" :text (or text ""))))

(defun yeah-acp--tool-call (record-id name status &optional result)
  "Return a tool_call or tool_call_update ACP update for RECORD-ID."
  (if (eq status 'started)
      (list :sessionUpdate "tool_call"
            :toolCallId (format "tool-%s" record-id)
            :title name
            :status "pending")
    (list :sessionUpdate "tool_call_update"
          :toolCallId (format "tool-%s" record-id)
          :status (if result "completed" "failed")
          :content (list (list :type "text" :text (or result ""))))))

(defun yeah-acp--observe-event (state session type fields id)
  "Send ACP updates for journal events belonging to STATE's SESSION."
  (when (eq session (plist-get state :session))
    (let ((session-id (plist-get state :id))
          (output (yeah-acp--output-for state)))
      (pcase type
        ("user-message"
         (yeah-acp--send-update
          session-id (yeah-acp--content-chunk "user_message_chunk"
                                              (plist-get fields :payload))
          output))
        ("assistant-message"
         (yeah-acp--send-update
          session-id (yeah-acp--content-chunk "agent_message_chunk"
                                              (plist-get fields :payload))
          output))
        ("tool-request"
         (yeah-acp--send-update
          session-id (yeah-acp--tool-call id (plist-get fields :tool) 'started)
          output))
        ("tool-end"
         (yeah-acp--send-update
          session-id (yeah-acp--tool-call id (plist-get fields :tool) nil
                                          (plist-get fields :payload))
          output))
        (_ nil)))))

(defun yeah-acp--output-for (state)
  "Return the output function of STATE: its connection's, or the global one."
  (or (plist-get state :output) yeah-acp--output-function
      #'yeah-acp--print-line))

(defun yeah-acp--register-session (session cwd)
  "Register SESSION for ACP and return its state plist.
The state carries the output function of the connection the session was
created on, so its notifications reach that connection; when the session
was created without a connection the current output function is used."
  (let* ((id (plist-get session :id))
         (state (list :id id :session session :cwd cwd :listener nil
                      :output yeah-acp--output
                      :connection yeah-acp--connection
                      :registry (yeah-tools-snapshot)))
         (listener (lambda (observed-session type fields event-id)
                     (yeah-acp--observe-event state observed-session type fields event-id))))
    (plist-put state :listener listener)
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
  "Load an existing session and replay no history, as session/resume semantics."
  (yeah-acp--validate-session-request request t)
  (let* ((cwd (file-truename (plist-get request :cwd)))
         (root (yeah-product-session-root cwd))
         (session-id (plist-get request :sessionId))
         (session (yeah-session-open session-id root)))
    (yeah-acp--register-session session cwd)
    (list :sessionId (plist-get session :id))))

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

(defun yeah-acp-session-prompt (request id)
  "Start a prompt for REQUEST and send its response later under request ID."
  (unless (listp request)
    (signal 'user-error (list "session/prompt params must be an object")))
  (let* ((session-id (plist-get request :sessionId))
         (state (yeah-acp--session-state session-id t))
         (session (plist-get state :session))
         (output (yeah-acp--output-for state))
         (prompt (yeah-acp--prompt-text (plist-get request :prompt)))
         (frozen (list :kind 'ask :prompt prompt
                       :frozen (list :cwd (plist-get state :cwd))))
         (turn
          (yeah-turn-run
           session prompt yeah-acp--transport
           (or yeah-acp--answerer
               (yeah-acp--client-answerer session-id output))
           nil nil
           (lambda (finished)
             (remhash session-id yeah-acp--active-turns)
             (funcall
              output
              (json-serialize
               (list :jsonrpc "2.0" :id id
                     :result (list :stopReason
                                   (yeah-acp--stop-reason finished))))))
           nil frozen nil
           (plist-get state :registry))))
    (unless (yeah-turn-done turn)
      (puthash session-id turn yeah-acp--active-turns))
    nil))

(defun yeah-acp-session-cancel (request)
  "Handle the session/cancel notification REQUEST."
  (unless (and (listp request) (stringp (plist-get request :sessionId)))
    (signal 'user-error (list "session/cancel needs sessionId")))
  (when-let ((turn (gethash (plist-get request :sessionId)
                            yeah-acp--active-turns)))
    (yeah-turn-cancel turn "cancelled by ACP client"))
  nil)

(defun yeah-acp--route-response (message)
  "Route a client RESPONSE (a message with an id and no method) to the
permission it answers.  Return non-nil when it was a response."
  (let ((id (plist-get message :id)))
    (when (and id (null (plist-get message :method)))
      (when-let ((session-id (gethash id yeah-acp--pending-permissions)))
        (remhash id yeah-acp--pending-permissions)
        (when-let ((turn (gethash session-id yeah-acp--active-turns)))
          (let* ((outcome (plist-get (plist-get message :result) :outcome))
                 (cancelled (equal (plist-get outcome :outcome) "cancelled"))
                 (option (plist-get outcome :optionId))
                 (decision (if (or cancelled (equal option "reject-once"))
                               (list :effect :deny
                                     :reason (if cancelled "cancelled" "the person refused"))
                             (list :effect :allow :reply :once))))
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
      (maphash (lambda (id session-id)
                 (when (memq session-id sessions)
                   (push id stale)))
               yeah-acp--pending-permissions)
      (dolist (id stale)
        (remhash id yeah-acp--pending-permissions)))
    (dolist (session-id sessions)
      (when-let ((turn (gethash session-id yeah-acp--active-turns)))
        (yeah-turn-cancel turn "the client disconnected")))))

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
             (lambda () (zerop (hash-table-count yeah-acp--active-turns)))))))))
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
  "Clear ACP sessions, listeners and active turns for tests."
  (maphash
   (lambda (_id state)
     (when-let ((listener (plist-get state :listener)))
       (setq yeah-events-write-functions
             (delete listener yeah-events-write-functions))))
   yeah-acp--sessions)
  (clrhash yeah-acp--sessions)
  (clrhash yeah-acp--active-turns)
  (setq yeah-acp--counter 0))

(provide 'yeah-acp)
;;; yeah-acp.el ends here
