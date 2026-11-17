;;; test-yeah-acp.el --- ERT tests for the ACP v1 agent -*- lexical-binding: t; no-byte-compile: t -*-
;;
;; Copyright (C) 2026  Petr Kosov

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'yeah-acp)
(require 'yeah-events)
(require 'yeah-input)

(defun yeah-acp-test--parse (json-string)
  "Parse JSON-STRING as a plist."
  (json-parse-string json-string :object-type 'plist :array-type 'list))

(defun yeah-acp-test--prompt-request (id session-id text)
  "Return one valid ACP prompt request string for ID, SESSION-ID and TEXT."
  (json-serialize
   (list :jsonrpc "2.0"
         :id id
         :method "session/prompt"
         :params (list :sessionId session-id
                       :prompt (vector (list :type "text" :text text))))))

(defun yeah-acp-test--find-response (emitted id)
  "Return the emitted message answering request ID, or nil."
  (cl-find-if
   (lambda (text)
     (equal id (plist-get (yeah-acp-test--parse text) :id)))
   emitted))

(defun yeah-acp-test--stop-reason (text)
  "Return the stopReason carried by the response TEXT."
  (plist-get (plist-get (yeah-acp-test--parse text) :result) :stopReason))

(defun yeah-acp-test--response (method params)
  "Return the parsed JSON-RPC response of the ACP METHOD with PARAMS.
A notification that answers nothing gives nil."
  (let ((raw (yeah-acp-handle-message
              (json-serialize (list :jsonrpc "2.0" :id 99 :method method
                                    :params params)))))
    (and raw (yeah-acp-test--parse raw))))

(defun yeah-acp-test--result (method params)
  "Return the result object of the response of the ACP METHOD with PARAMS."
  (plist-get (yeah-acp-test--response method params) :result))

(defun yeah-acp-test--update-objects (emitted)
  "Return the update objects of the session/update notifications in EMITTED."
  (mapcar (lambda (text)
            (plist-get (plist-get (yeah-acp-test--parse text) :params) :update))
          (seq-filter
           (lambda (text)
             (equal "session/update"
                    (plist-get (yeah-acp-test--parse text) :method)))
           emitted)))

(defun yeah-acp-test--content-text (content)
  "Return the text of CONTENT, one content block or a list of them."
  (let ((blocks (cond ((vectorp content) (append content nil))
                      ((and (listp content) (consp (car content))) content)
                      (t (list content)))))
    (string-join (mapcar (lambda (block) (or (plist-get block :text) ""))
                         blocks)
                 "")))

(defun yeah-acp-test--pending-input (control id)
  "Return the pending input ID of CONTROL, or nil."
  (seq-find (lambda (input) (equal id (plist-get input :id)))
            (yeah-control-pending control)))

(defun yeah-acp-test--schema-path ()
  "Return the path of the ACP schema, or nil when it cannot be found."
  (seq-find
   (lambda (path) (file-readable-p path))
   (list (expand-file-name
          "../schemas/acp-v1.json"
          (file-name-directory (or (locate-library "yeah-acp") "yeah-acp.el")))
         (expand-file-name "schemas/acp-v1.json" default-directory))))

(defun yeah-acp-test--schema-methods ()
  "Return the names of the methods the ACP schema declares."
  (let ((path (yeah-acp-test--schema-path)))
    (when path
      (with-temp-buffer
        (insert-file-contents path)
        (let* ((schema (json-parse-string (buffer-string) :object-type 'alist))
               (methods (cdr (assoc 'methods schema))))
          (mapcar (lambda (method) (symbol-name (car method))) methods))))))

(defmacro yeah-acp-test--with-server (&rest body)
  "Run BODY with isolated ACP state, model transport and output.
The pending queue of a session lives in the temporary directory too: a test
must not write into the queue of the person who runs it."
  (declare (indent 0))
  `(let* ((directory (make-temp-file "yeah-acp-test" t))
          (yeah-data-home directory)
          (yeah-input-directory (expand-file-name "pending/" directory))
          (yeah-acp--transport nil)
          (yeah-acp--answerer nil)
          (yeah-acp--output-function nil))
     (unwind-protect
         (progn
           (yeah-acp--reset-for-test)
           ,@body)
       (yeah-acp--reset-for-test)
       (ignore-errors (delete-directory directory t t)))))

(defun yeah-acp-test--finish (summary)
  "Return the tool call of a model that finished its work with SUMMARY.
A supervised run ends through the `finish' tool: a text answer alone is not
a completion, and the wire says which of the two happened."
  (list 'tool-call
        (list (list :name "finish")
              (list summary)
              (lambda (_value) nil))))

(defun yeah-acp-test--answer-then-finish (summary)
  "Return a transport that answers with SUMMARY and then finishes the run.
A supervised run does not end through talk: the harness nudges the model, and
the model ends the run with the `finish' tool."
  (let ((asked 0))
    (lambda (_prompt callback)
      (setq asked (1+ asked))
      (if (= asked 1)
          (funcall callback summary)
        (funcall callback (yeah-acp-test--finish summary))))))

(defun yeah-acp-test--new-session (&optional transport)
  "Create a session in the isolated ACP test server and return its id.
TRANSPORT is the transport of the service: the controller of a session
freezes it when the session is created."
  (when transport
    (setq yeah-acp--transport transport))
  (plist-get
   (yeah-acp-session-new (list :cwd (file-truename yeah-data-home)
                               :mcpServers nil))
   :sessionId))

(defun yeah-acp-test--announce-queue-events ()
  "Announce that the client understands Yeah's own queue events.
The announcement is what the client of Yeah says at `initialize'; a client
that says nothing is served plain ACP.  The handshake goes through the
wire here, so the test reads the announcement the way the server reads
it: Emacs parses a JSON object into a property list whose keys are
keywords."
  (yeah-acp-initialize
   (yeah-acp-test--parse
    (json-serialize
     (list :protocolVersion yeah-acp-protocol-version
           :clientCapabilities (yeah-acp-queue-events-capabilities))))))

(ert-deftest yeah-acp-initialize-negotiates-protocol-one ()
  (yeah-acp-test--with-server
    (let ((response (yeah-acp-initialize
                     (list :protocolVersion 1 :clientInfo '(:name "zed")))))
      (should (= 1 (plist-get response :protocolVersion)))
      (should (equal "yeah" (plist-get (plist-get response :agentInfo) :name)))
      (should (eq t (plist-get (plist-get response :agentCapabilities)
                               :loadSession))))))

(ert-deftest yeah-acp-initialize-rejects-string-protocol-version ()
  (yeah-acp-test--with-server
    (should-error (yeah-acp-initialize '(:protocolVersion "1"))
                  :type 'user-error)))

(ert-deftest yeah-acp-session-new-load-and-updates ()
  (yeah-acp-test--with-server
    (let* ((updates nil)
           (session-id (yeah-acp-test--new-session))
           (session (plist-get (yeah-acp--session-state session-id) :session)))
      (setq yeah-acp--output-function (lambda (text) (push text updates)))
      (yeah-events-write session "assistant-message" :payload "hello")
      (should (= 1 (length updates)))
      (let* ((update (yeah-acp-test--parse (car updates)))
             (params (plist-get update :params)))
        (should (equal "session/update" (plist-get update :method)))
        (should (equal session-id (plist-get params :sessionId)))
        (should (equal "agent_message_chunk"
                       (plist-get (plist-get params :update) :sessionUpdate))))
      (let ((loaded (yeah-acp-session-load
                     (list :sessionId session-id :cwd yeah-data-home
                           :mcpServers nil))))
        (should (equal session-id (plist-get loaded :sessionId)))
        (should (yeah-acp--session-state session-id))))))

(ert-deftest yeah-acp-prompt-answers-with-end-turn-stop-reason ()
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session
                        (yeah-acp-test--answer-then-finish "the answer"))))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (should-not
       (yeah-acp-handle-message
        (yeah-acp-test--prompt-request 7 session-id "hello")))
      (let ((response (yeah-acp-test--find-response emitted 7)))
        (should response)
        (should (equal "end_turn" (yeah-acp-test--stop-reason response))))
      (should (cl-some (lambda (text)
                         (string-match-p "agent_message_chunk" text))
                       emitted)))))

(ert-deftest yeah-acp-prompt-answers-refusal-when-the-run-does-not-finish ()
  "A model that only describes its next step does not finish the run.
The wire must not call such a run done: the run is supervised, and a run
that spends its budget without an effect is not a completion."
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session
                        (lambda (_prompt callback)
                          (funcall callback "I'll write the file now."))))
           (session (plist-get (yeah-acp--session-state session-id) :session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (should-not
       (yeah-acp-handle-message
        (yeah-acp-test--prompt-request 8 session-id "hello")))
      (let ((response (yeah-acp-test--find-response emitted 8)))
        (should response)
        (should (equal "refusal" (yeah-acp-test--stop-reason response))))
      ;; and the journal of the session says that the run did not finish
      (should (cl-some (lambda (record)
                          (equal "unfinished" (plist-get record :type)))
                        (yeah-session-records session))))))

(ert-deftest yeah-acp-cancel-answers-prompt-with-cancelled ()
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session
                        (lambda (_prompt _callback) nil))))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (should-not
       (yeah-acp-handle-message
        (yeah-acp-test--prompt-request 9 session-id "wait")))
      (yeah-acp-handle-message
       (json-serialize
        (list :jsonrpc "2.0"
              :method "session/cancel"
              :params (list :sessionId session-id))))
      (let ((response (yeah-acp-test--find-response emitted 9)))
        (should response)
        (should (equal "cancelled" (yeah-acp-test--stop-reason response))))
      (should (yeah-control-done-p
               (plist-get (yeah-acp--session-state session-id) :control))))))

(ert-deftest yeah-acp-prompt-rejects-unsupported-content-block ()
  (yeah-acp-test--with-server
    (let* ((session-id (yeah-acp-test--new-session))
           (request
            (format
             (concat "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"session/prompt\","
                     "\"params\":{\"sessionId\":\"%s\",\"prompt\":[{\"type\":\"image\"}]}}")
             session-id))
           (response (yeah-acp-test--parse (yeah-acp-handle-message request))))
      (should (= -32602 (plist-get (plist-get response :error) :code))))))

(ert-deftest yeah-acp-handle-message-rejects-malformed-json ()
  (yeah-acp-test--with-server
    (let* ((response (yeah-acp-test--parse
                      (yeah-acp-handle-message "{not-json"))))
      (should (= -32700 (plist-get (plist-get response :error) :code))))))

(ert-deftest yeah-acp-handle-message-refuses-unknown-method ()
  (yeah-acp-test--with-server
    (let ((response
           (yeah-acp-test--parse
            (yeah-acp-handle-message
             (concat "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"unknown\","
                     "\"params\":{}}")))))
      (should (= -32601 (plist-get (plist-get response :error) :code))))))

(ert-deftest yeah-acp-permission-response-allows-only-an-explicit-allow ()
  "Unknown, failed, cancelled and rejected responses never allow an effect."
  (should (equal (plist-get
                  (yeah-acp--permission-decision
                   (list :result (list :outcome
                                       (list :outcome "selected"
                                             :optionId "allow-once"))))
                 :effect)
                 :allow))
  (dolist (message
           (list (list :error (list :code -32601 :message "unsupported"))
                 (list :result (list :outcome (list :outcome "cancelled")))
                 (list :result (list :outcome (list :outcome "selected"
                                                      :optionId "reject-once")))
                 (list :result (list :outcome (list :outcome "selected"
                                                      :optionId "unknown")))
                 (list)))
    (should (eq (plist-get (yeah-acp--permission-decision message) :effect)
                :deny))))

(ert-deftest yeah-acp-an-always-answer-is-remembered-for-the-session ()
  "The client may answer `allow-always': the decision is remembered for
the session, so the same question is not asked a second time."
  (yeah-acp-test--with-server
    (let* ((session-id (yeah-acp-test--new-session))
           (answerer (yeah-acp--client-answerer
                      session-id (lambda (text) text)))
           (request (list :action "write" :resource "/tmp/x.el" :args nil))
           (deferral (funcall answerer request)))
      (should (plist-get deferral :defer))
      (let ((question (gethash (plist-get deferral :defer)
                               yeah-acp--pending-permissions)))
        (should question)
        (yeah-acp--remember-decision question
                                     (list :effect :allow :reply :always)))
      (should (eq :allow
                  (plist-get (funcall answerer request) :effect))))))

(ert-deftest yeah-acp-steer-queues-an-input-and-answers-with-its-id ()
  "A clarification waits in the queue of the session and is named by its id."
  (yeah-acp-test--with-server
    (let* ((session-id (yeah-acp-test--new-session
                        (lambda (_prompt _callback) nil)))
           (control (plist-get (yeah-acp--session-state session-id) :control)))
      ;; a prompt the model never answers keeps the turn of the session running
      (should-not
       (yeah-acp-handle-message
        (yeah-acp-test--prompt-request 7 session-id "hello")))
      (let* ((result (yeah-acp-test--result
                      "session/steer" (list :sessionId session-id
                                            :prompt "focus on the tests")))
             (input-id (plist-get result :inputId))
             (input (yeah-acp-test--pending-input control input-id)))
        (should (stringp input-id))
        (should input)
        (should (eq 'steering (plist-get input :kind)))
        (should (equal "focus on the tests" (plist-get input :prompt)))))))

(ert-deftest yeah-acp-withdraw-removes-a-pending-input ()
  "A withdrawn input leaves the queue of the session and is not withdrawn twice."
  (yeah-acp-test--with-server
    (let* ((session-id (yeah-acp-test--new-session
                        (lambda (_prompt _callback) nil)))
           (control (plist-get (yeah-acp--session-state session-id) :control)))
      (should-not
       (yeah-acp-handle-message
        (yeah-acp-test--prompt-request 7 session-id "hello")))
      (let* ((input-id (plist-get (yeah-acp-test--result
                                   "session/steer" (list :sessionId session-id
                                                         :prompt "wait"))
                                  :inputId))
             (result (yeah-acp-test--result
                      "session/withdraw" (list :sessionId session-id
                                               :inputId input-id))))
        (should (eq t (plist-get result :withdrawn)))
        (should-not (yeah-acp-test--pending-input control input-id))
        (should (eq :false
                    (plist-get (yeah-acp-test--result
                                "session/withdraw"
                                (list :sessionId session-id
                                      :inputId input-id))
                               :withdrawn)))))))

(ert-deftest yeah-acp-recover-starts-the-oldest-pending-ask ()
  "Recovery is explicit: a pending input waits until the person asks for it."
  (yeah-acp-test--with-server
    (let* ((asked nil)
           (session-id (yeah-acp-test--new-session
                        (lambda (prompt callback)
                          (setq asked prompt)
                          (funcall callback
                                   (yeah-acp-test--finish "the answer")))))
           (session (plist-get (yeah-acp--session-state session-id) :session)))
      ;; the queue a restart left behind
      (yeah-input-enqueue session (list :kind 'ask
                                         :prompt "the pending one"
                                         :frozen (list :cwd yeah-data-home)))
      (let ((result (yeah-acp-test--result
                     "session/recover" (list :sessionId session-id))))
        (should (eq t (plist-get result :started)))
        (should (stringp (plist-get result :inputId)))
        (should (equal "the pending one" asked))))))

(ert-deftest yeah-acp-load-replays-the-journal-into-the-editor-view ()
  "Opening a session again replays its records as session/update messages."
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session))
           (session (plist-get (yeah-acp--session-state session-id) :session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (yeah-events-write session "user-message" :payload "the earlier text")
      (let* ((result (yeah-acp-test--result
                      "session/load" (list :sessionId session-id
                                            :cwd yeah-data-home
                                            :mcpServers nil)))
             (replayed (plist-get result :replayed)))
        (should (equal session-id (plist-get result :sessionId)))
        (should (> replayed 0))
        (let ((updates (yeah-acp-test--update-objects
                        (take replayed emitted))))
          (should (= replayed (length updates)))
          (should (cl-some (lambda (update)
                             (equal "user_message_chunk"
                                    (plist-get update :sessionUpdate)))
                           updates))
          (should (cl-some (lambda (update)
                             (equal "the earlier text"
                                    (yeah-acp-test--content-text
                                     (plist-get update :content))))
                           updates)))))))

(ert-deftest yeah-acp-queue-events-reach-the-client-as-session-updates ()
  "The pending queue of a session is visible in the wire: the events that
move an input in or out of the queue have their own update kinds.
They travel to the client that asked for them: they are not ACP, and a
client that does not know them refuses the whole update."
  (yeah-acp-test--with-server
    (yeah-acp-test--announce-queue-events)
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session))
           (state (yeah-acp--session-state session-id))
           (listener (plist-get state :listener))
           (session (plist-get state :session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (funcall listener session "input-queued"
               (list :input_id "input-1" :input_kind "ask"
                     :prompt "the words") 1)
      (funcall listener session "input-taken"
               (list :input_id "input-1" :input_kind "ask") 2)
      (funcall listener session "input-recovered"
               (list :input_id "input-2" :input_kind "steering") 3)
      (funcall listener session "input-withdrawn"
               (list :input_id "input-2" :kind "steering"
                     :reason "the run it was addressed to ended") 4)
      (let ((updates (reverse (yeah-acp-test--update-objects emitted))))
        (should (= 4 (length updates)))
        (should (equal "input_queued" (plist-get (nth 0 updates) :sessionUpdate)))
        (should (equal "input-1" (plist-get (nth 0 updates) :inputId)))
        (should (equal "ask" (plist-get (nth 0 updates) :inputKind)))
        (should (equal "the words"
                       (yeah-acp-test--content-text
                        (plist-get (nth 0 updates) :content))))
        (should (equal "input_taken" (plist-get (nth 1 updates) :sessionUpdate)))
        (should (equal "input_recovered"
                       (plist-get (nth 2 updates) :sessionUpdate)))
        (should (equal "input_withdrawn"
                       (plist-get (nth 3 updates) :sessionUpdate)))
        (should (equal "steering" (plist-get (nth 3 updates) :inputKind)))
        (should (equal "the run it was addressed to ended"
                       (plist-get (nth 3 updates) :reason)))))))

(ert-deftest yeah-acp-queue-events-stay-away-from-a-client-that-asked-for-nothing ()
  "A client that announced nothing gets plain ACP: the queue events of Yeah
are not part of the protocol, and a client that does not know them refuses
the whole update."
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session))
           (state (yeah-acp--session-state session-id))
           (listener (plist-get state :listener))
           (session (plist-get state :session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (funcall listener session "input-queued"
               (list :input_id "input-1" :input_kind "ask"
                     :prompt "the words") 1)
      (funcall listener session "input-taken"
               (list :input_id "input-1" :input_kind "ask") 2)
      (should (null emitted)))))

(ert-deftest yeah-acp-a-content-chunk-carries-one-content-block ()
  "The content of an ACP chunk is one block, not an array of them: a client
that checks the wire refuses a chunk that carries an array."
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session))
           (state (yeah-acp--session-state session-id))
           (listener (plist-get state :listener))
           (session (plist-get state :session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (funcall listener session "assistant-message" (list :payload "hello") 1)
      (let* ((update (car (yeah-acp-test--update-objects emitted)))
             (content (plist-get update :content)))
        (should (equal "agent_message_chunk" (plist-get update :sessionUpdate)))
        (should (equal "text" (plist-get content :type)))
        (should (equal "hello" (plist-get content :text)))
        (should-not (vectorp content))))))

(ert-deftest yeah-acp-the-answer-of-a-finished-run-reaches-the-client ()
  "The summary of a finished run is the answer of the agent: it travels as
the message of the agent.  A model that answers only through the `finish'
tool says nothing else, and a client that waits for the words of the agent
must see them."
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session))
           (state (yeah-acp--session-state session-id))
           (listener (plist-get state :listener))
           (session (plist-get state :session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (funcall listener session "finish"
               (list :summary "the work is done") 1)
      (let* ((updates (yeah-acp-test--update-objects emitted))
             (update (car updates))
             (content (plist-get update :content)))
        (should (= 1 (length updates)))
        (should (equal "agent_message_chunk" (plist-get update :sessionUpdate)))
        (should (equal "the work is done" (plist-get content :text)))))))

(ert-deftest yeah-acp-a-tool-call-carries-its-input-and-its-output ()
  "The call of a tool travels with what the tool was called with and what it
returned: a call without its input is a name."
  (yeah-acp-test--with-server
    (let* ((emitted nil)
           (session-id (yeah-acp-test--new-session))
           (state (yeah-acp--session-state session-id))
           (listener (plist-get state :listener))
           (session (plist-get state :session)))
      (setq yeah-acp--output-function (lambda (text) (push text emitted)))
      (funcall listener session "tool-request"
               (list :tool "write" :args "(\"answer.txt\" \"42\")"
                     :tool_call_id "call-1") 1)
      (funcall listener session "tool-end"
               (list :tool "write" :ok t :payload "the file is written"
                     :tool_call_id "call-1") 2)
      (let* ((updates (reverse (yeah-acp-test--update-objects emitted)))
             (call (nth 0 updates))
             (end (nth 1 updates)))
        (should (equal "tool_call" (plist-get call :sessionUpdate)))
        ;; the arguments are the values themselves and not their printed form
        (should (equal '("answer.txt" "42") (plist-get call :rawInput)))
        (should (equal "tool_call_update" (plist-get end :sessionUpdate)))
        (should (equal "the file is written" (plist-get end :rawOutput))))))

(ert-deftest yeah-acp-the-input-of-a-tool-call-is-read-as-data ()
  "The arguments of a call come from the model, so the printed form of them is
read back as data: a form that the reader would evaluate is not read at all,
and the printed form travels to the client as it is."
  (should (equal '("answer.txt" "42")
                 (yeah-acp--tool-input "(\"answer.txt\" \"42\")")))
  (should (equal '("a" "b") (yeah-acp--tool-input "(\"a\" \"b\")")))
  (should (equal "#.(+ 1 2)" (yeah-acp--tool-input "#.(+ 1 2)")))
  (should (equal "not a list" (yeah-acp--tool-input "not a list")))))

(ert-deftest yeah-acp-an-unknown-session-is-an-error ()
  "The wire does not answer a request for a session it does not know."
  (yeah-acp-test--with-server
    (dolist (method '("session/steer" "session/withdraw" "session/recover"))
      (let ((response (yeah-acp-test--response method
                                              (list :sessionId "no-such-session"
                                                    :inputId "input-1"
                                                    :prompt "hello"))))
        (should (= -32602 (plist-get (plist-get response :error) :code)))
        (should-not (plist-get response :result))))
    (let ((response (yeah-acp-test--response
                     "session/load" (list :sessionId "no-such-session"
                                           :cwd yeah-data-home))))
      (should (= -32602 (plist-get (plist-get response :error) :code)))
      (should-not (plist-get response :result)))))

(ert-deftest yeah-acp-dispatcher-routes-every-method-the-schema-declares ()
  "The schema and the dispatcher agree: a method the schema names is routed.
A request the dispatcher cannot accept is refused with -32602; a method it
does not know is refused with -32601."
  (yeah-acp-test--with-server
    (let ((methods (yeah-acp-test--schema-methods)))
      (should methods)
      (dolist (method methods)
        (let ((response (yeah-acp-test--response method nil)))
          (should-not
           (= -32601 (plist-get (plist-get response :error) :code))))))))

(provide 'test-yeah-acp)
;;; test-yeah-acp.el ends here
