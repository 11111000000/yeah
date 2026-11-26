Yeah is an agent harness that runs inside Emacs. The plugin adds it to Paseo
as a provider named Yeah, so an agent of the Yeah kernel can be created and
run like any other agent, in the workspace that is open in Paseo.

The plugin starts the ACP server of the Yeah kernel in an Emacs process — one
per connection, or one shared over a Unix socket — and speaks ACP (JSON-RPC
over stdio or over that socket) with it. The model is reached through gptel,
every tool goes through the registry and the permission system of the kernel,
and the session log stays an append-only JSONL file.

## Setup

The plugin needs an Emacs binary, a checkout of the Yeah kernel and the gptel
package. It requires Paseo 0.15.2 or newer and a Unix-like system.

The plugin lives in the repository of the kernel, in `plugin/yeah-provider`,
and is installed from there:

```sh
paseo plugin install /home/az/Projects/yeah/plugin/yeah-provider
```

Settings live in the host settings of Paseo under Yeah:

| Setting | Meaning |
|---|---|
| `repoPath` | root of the Yeah checkout; its `lib/` directory is loaded into Emacs |
| `gptelPath` | directory of the gptel build; empty means the freshest one under `~/.emacs.d/elpa` |
| `emacsPath` | path to Emacs; empty means the usual places are searched |
| `model` | model the provider uses |
| `models` | models offered to Paseo |
| `host` | host of the model backend |
| `endpoint` | endpoint of the model backend; GLM uses the Responses API of Z.ai |
| `profile` | permission profile of the process: `workspace` asks once for work in the task directory and separately for outside paths and shell, `build` asks each step, `plan` forbids edits, `auto` allows everything; the mode of the session is a different thing (below) |
| `serviceMode` | placement of the kernel: `spawn` raises one Emacs per connection, `service` keeps one Emacs for every agent and the sessions come to it over a socket |
| `serviceName` | name of the service, which is the name of its socket; services with different names do not get in each other's way |
| `keyFile` | environment file that holds the provider key |
| `dataHome` | data directory of Yeah; empty means the default of the kernel |

The key of the model backend is never stored in the settings of Paseo and never
reaches its configuration. It is read from the environment file named by
`keyFile`, which lives outside the repository of the kernel and is readable by
its owner only, or from `YEAH_ACP_KEY` in the environment of the daemon. The
value is passed to the Emacs process through the environment and is not
printed or written to a log by the plugin.
There are two profiles here and they are not the same thing. The setting
`profile` of the plugin chooses the profile of the process at launch
(`YEAH_ACP_PROFILE`) and fills the standing rules of permissions of the
kernel: `plan` forbids the tools that change the world, `build` asks the
person, `auto` allows everything. A standing refusal decides everything, on
the wire too: a tool that the standing rules forbid is not asked about, it is
refused. The mode of the session is the other thing: it travels over ACP, the
kernel publishes three of them in the answer of `session/new` (`plan`,
`build`, `auto`; the third came with wave 76), and the client of the
orchestrator switches them with `session/set_mode`. The mode of the session
decides: `plan` forbids, `auto` allows without a question, `build` asks the
client. A run without questions is therefore the mode `auto`, and it is
switched on the side of the client (`paseo run --provider yeah --mode auto`;
the live run of 19 November 2026 asked zero times). The setting `profile`
alone does not switch the mode of the session: it fills the standing rules of
the process, and a standing permission does not remove the question -- the
mode of the session does. The mode does not make the work of the agent safe:
a deletion goes into the trash of the user and the commands that destroy in
place are refused by name, but there is no boundary of the working directory
and the secrets in the journal are not masked (`docs/AGENT-SAFETY.md`).

## What the plugin adds to the wire

The kernel does not publish its models over ACP, so the plugin publishes the
configured model in the catalog of the provider and accepts a request for that
model. A request for another model fails.

The kernel does not name the kind of a tool call either. The plugin reads the
name of the tool and sets the kind the Paseo interface expects: `edit`,
`read`, `search` or `execute`.

Yeah has its own events for the queue of a session. They are not ACP, and the
plugin does not announce them, so the client of Paseo receives plain ACP.

The outcome of a run is the vocabulary of the kernel as well: the nudge that
pushed the model, the run that ended without an effect and the error that
stopped it. The kernel sends it as its own notification `yeah/outcome` and only
to the clients that asked for it: the plugin adds `yeah.runOutcome` to the
`_meta` of the client capabilities of the `initialize` request, which the
daemon of the orchestrator sends. The plugin translates the outcome into a
notice that the orchestrator shows.

## Service placement

By default the plugin raises an Emacs of its own for every connection: the
agent came, Emacs started, the agent left, Emacs left. That is simple, but it
is expensive, because the backend of the model is configured every time, and
it has a hard limit: over stdio the kernel reads the next request only after
the turn has settled.

In the service placement one Emacs serves every agent of the host: it listens
on a Unix socket and the sessions come to it. The switch is one setting,
`serviceMode`, and `serviceName` names the service, which is the name of its
socket. The path of the socket is the path the kernel names
(`yeah-service-socket-path`), so a service raised from Emacs and a service
raised from the plugin do not take each other's place. The life of the service
is tied to the life socket of the host: the plugin closes the service when it
goes.

A service that dies leaves its socket behind: the file outlives the process.
The plugin does not take the file for proof of life — it asks the socket
itself, and a dead socket raises the service again (wave 74).

The default is still `spawn`, on purpose: which placement is canonical and
what happens to the service after it dies is a decision of the owner
(`docs/PASEO-INTEGRATION-PLAN.md` §5.3).

## Steering

Steering is a message that reaches the agent in the middle of a turn without
replacing that turn. The orchestrator sends it with `delivery: "steer"`, and a
provider has to declare the capability `prompt.steer`.

The ACP adapter of the library of the orchestrator does not know that
capability, and a request with `delivery: "steer"` interrupts the running turn
and starts a new one. So the plugin does the steering itself: it declares
`prompt.steer` — in the connection and in the session it opens, and only when
the orchestrator offered the capability — it translates such a request into
`session/steer` of the kernel, and it answers the orchestrator with the
identifier of the turn that is running. The request never reaches the adapter,
so the running turn is not interrupted.

Over stdio the steering is not timely: the kernel reads the next request only
after the turn has settled, so the clarification is read late and becomes an
ordinary ask. The service placement is what makes a request during a turn read
while the turn runs.

A live run through the real orchestrator was made on 19 November 2026: the
clarification reached the model in the running turn, and the turn was neither
interrupted nor replaced.  The check of the wave proves the same against the
real kernel (`tests/checks/check-the-plugin-steers-the-running-turn.sh`).

## Known limits

These are limits of the kernel. The plugin neither works around them nor hides
them.

- A cancellation over stdio is read only after the running prompt has settled,
  so stopping an agent waits for the end of the turn. The socket placement of
  the plugin removes that limit, and it is not the default: the default is
  still `spawn`, one Emacs per connection.
- `session/set_mode` and a change of the model of a session over the wire do
  exist (waves 43, parts 3 and 4, 18 November 2026): the mode of the session
  and the model of the session are chosen over the wire. The setting `profile`
  of the plugin is a different thing — the standing rules of the process
  (above).
- The `mcpServers` of a session are not ignored: the kernel connects to them
  and their tools become the tools of the runs of that session (wave 66 gave the
  kernel an HTTP transport for MCP). Who starts those servers stays outside the
  kernel.
- The journal of the session stays the source of truth: ACP projects part of
  what a run did, and the rest is in the JSONL file of the session.
Two entries of that list are old and are not gaps any more. The working
directory of a session is applied to the tools: a relative path of the agent
resolves against the directory of the session, not against the working
directory of the Emacs process (wave 43, part 1, 18 November 2026). The
arguments of a tool arrive under the names the tool declared, and the plugin
translates the names of an edit into the ones the client of Paseo reads (`path`
to `filePath`, `old_str` to `oldString`, `new_str` to `newString`; wave 43,
part 2). The diff of an edit in the interface of Paseo has not been observed
since: only a live run can show it.
