Yeah is an agent harness that runs inside Emacs. The plugin adds it to Paseo
as a provider named Yeah, so an agent of the Yeah kernel can be created and
run like any other agent, in the workspace that is open in Paseo.

The plugin starts the ACP server of the Yeah kernel in an Emacs process and
speaks ACP (JSON-RPC over stdio) with it. The model is reached through gptel,
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
| `host` | host of the model backend |
| `profile` | permission profile: `build` asks the person, `plan` forbids edits |
| `keyFile` | environment file that holds the provider key |
| `dataHome` | data directory of Yeah; empty means the default of the kernel |

The key of the model backend is never stored in the settings of Paseo and never
reaches its configuration. It is read from the environment file named by
`keyFile`, which lives outside the repository of the kernel and is readable by
its owner only, or from `YEAH_ACP_KEY` in the environment of the daemon. The
value is passed to the Emacs process through the environment and is not
printed or written to a log by the plugin.

## What the plugin adds to the wire

The kernel does not publish its models over ACP, so the plugin publishes the
configured model in the catalog of the provider and accepts a request for that
model. A request for another model fails.

The kernel does not name the kind of a tool call either. The plugin reads the
name of the tool and sets the kind the Paseo interface expects: `edit`,
`read`, `search` or `execute`.

Yeah has its own events for the queue of a session. They are not ACP, and the
plugin does not announce them, so the client of Paseo receives plain ACP.

## Known limits

These are limits of the kernel. The plugin neither works around them nor hides
them.

- A cancellation over stdio is read only after the running prompt has settled,
  so stopping an agent waits for the end of the turn.
- `session/set_mode` and a change of the model of a session over the wire do
  not exist: the profile and the model are chosen when the process starts.
- The `mcpServers` of a session are ignored.
- The working directory of a session is not applied to the tools. Relative
  paths of the agent resolve against the working directory of the Emacs
  process.
- The arguments of a tool arrive as a positional list of values, so the
  interface of Paseo shows no diff of an edit.
- The journal of the session stays the source of truth: ACP projects part of
  what a run did, and the rest is in the JSONL file of the session.
