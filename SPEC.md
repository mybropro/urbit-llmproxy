# %llmproxy — design spec

This spec describes the current implementation. The README covers install
and use; this doc covers the wire shapes, agent responsibilities, and the
edges where things get interesting.

## What it is

`%llmproxy` is an Urbit desk that turns any ship into an OpenAI-compatible
LLM proxy. A ship running the **node** agent forwards inference requests
from peers to a local OpenAI-compatible HTTP backend (Ollama, vLLM,
llama.cpp's server, OpenAI direct, etc.). A ship running the **client**
agent exposes `/llmproxy/v1/chat/completions` and `/llmproxy/v1/models` over
Eyre, plus a `/llmproxy/ui` config page, and pokes a configured node ship
over Ames to do the actual work.

Both agents are in the same desk. Most installs run both on one ship; the
node-only or client-only deployments are also valid.

Properties:

- **No coordinator.** Each node is sovereign — it sets its own access
  policy, picks its own backend, and decides who can submit jobs.
- **No open ports on the node.** The backend is reachable only from
  localhost; cross-ship calls go through Ames, which handles NAT
  traversal, encryption, and authentication natively.
- **Identity-based auth.** The node's access policy is `@p`-based. A
  separate Bearer-token gate on the client's HTTP layer is optional.
- **One desk, two agents.** Both shipped together. Whether you serve, use,
  or both is a runtime config decision via `/llmproxy/ui`.

---

## Agents

### `%llmproxy-node`

Run this where the inference backend lives. Accepts `%llmproxy-job` pokes
from peers (gated by access policy), POSTs to the backend's
`/v1/chat/completions`, and emits the result as a single
`%llmproxy-token` fact on `/job/<nonce>`.

**Responsibilities**

- Enforce the access policy on incoming `%llmproxy-job` pokes
- Build the upstream HTTP request (`build-body`, `build-headers`)
- Track the request via Iris (`%i` `%request`) on a `/req/<nonce>` wire
- On `%http-response %finished`, parse the JSON, extract the assistant
  text via `extract-content`, and emit a final `token-chunk` fact +
  `%kick` on `/job/<nonce>`
- Periodically refresh advertised models by GETting `/v1/models` from the
  backend and parsing with `parse-models-list`
- Publish the model list as `%llmproxy-models` facts on `/models` (the
  client subscribes to this)

**Configuration pokes (mark `%noun`)**

```
[%set-backend url=@t]         :: where the backend's /v1/chat/completions lives
[%set-backend-key key=@t]     :: optional Bearer key sent upstream
[%set-policy =access-policy]  :: who can submit jobs
[%refresh-models ~]           :: re-GET /v1/models from the backend
```

**State (`state-0`)**

```hoon
+$  state-0
  $:  %0
      backend-url=@t                       :: e.g. http://localhost:11434/v1/chat/completions
      backend-key=@t                       :: empty = no Authorization sent upstream
      policy=access-policy:llmproxy
      advertised=(list @t)                 :: cached models list
      pending=(map @ud pending-job)        :: in-flight Iris requests
  ==
```

**Scry endpoints**

```
.^((list @t)         %gx /=llmproxy-node=/advertised/noun)
.^(access-policy:llmproxy %gx /=llmproxy-node=/policy/noun)
.^(@t                 %gx /=llmproxy-node=/backend/noun)
.^(@t                 %gx /=llmproxy-node=/backend-key/noun)
```

The client uses `/advertised/noun` to render the UI and `/v1/models`
synchronously when the configured node is local — this avoids a fact
round-trip on cold loads.

---

### `%llmproxy-client`

Run this where you want to use the API. Binds `/llmproxy` on Eyre, serves
the config UI (Sail), and routes OpenAI HTTP traffic to a configured node
over Ames.

**Responsibilities**

- Bind `/llmproxy` via `[%pass /bind %arvo %e %connect [~ /llmproxy] dap.bowl]`
- Serve `GET /llmproxy/ui` (Sail-rendered config page) and handle `POST
  /llmproxy/ui` form actions
- Serve `GET /llmproxy/v1/models` (passthrough of node's `advertised`
  list) and `POST /llmproxy/v1/chat/completions` (OpenAI-format request →
  `%llmproxy-job` poke → SSE or single-JSON HTTP response)
- Maintain a single `node=@p` config — the ship that handles inference
- Subscribe to that node's `/models` to keep the advertised list fresh
- Optionally gate HTTP requests with a Bearer token (`bearer-ok`)
- Accept `[%ask target=@p model=@t prompt=@t]` from dojo (mark `%noun`)
  for ad-hoc testing — same poke / watch path, prints with `~&`

**Configuration: via `/llmproxy/ui` HTML forms.** The form actions are:

```
set-node              :: change which @p handles inference
set-backend           :: pokes node with %set-backend
set-backend-key       :: pokes node with %set-backend-key
refresh-models        :: pokes node with %refresh-models
toggle-policy-mode    :: flip whitelist <-> blacklist
set-policy-ships      :: replace the policy's ships set
set-client-api-token  :: HTTP-layer Bearer token (empty = open)
generate-api-token    :: emit a random sk-prefixed token
toggle-hosting        :: cosmetic flag controlling whether the
                         "Host a node" section is expanded
test                  :: send a one-off prompt via the same poke path
```

**State (`state-0`)**

```hoon
+$  state-0
  $:  %0
      nonce=@ud                            :: monotonic per-request key
      node=@p                              :: which ship handles inference
      models=(list @t)                     :: cached from /models subscription
      backend=@t                           :: mirrors the node's backend (for UI display)
      backend-key=@t                       :: same — local copy of node's key
      client-api-token=@t                  :: HTTP Bearer gate; empty = no auth
      policy=access-policy:llmproxy        :: mirror of node's policy (for UI)
      hosting=?                            :: UI-only — expand the node-config section
      pending=(map @ud pending-client)     :: in-flight requests awaiting a fact
  ==

+$  pending-client
  $:  eyre-id=@ta                          :: empty for %dojo
      target=@p                            :: which node we poked
      model=@t
      stream=?
      kind=?(%openai %test %dojo)
      prompt=@t
      api-base=@t                          :: for the %test re-render
  ==
```

**HTTP endpoints**

| Method | Path | Behavior |
|---|---|---|
| GET | `/llmproxy/ui` | Sail-rendered HTML config page |
| POST | `/llmproxy/ui` | Form-encoded action dispatch (see actions above) |
| GET | `/llmproxy/v1/models` | OpenAI-format model list |
| POST | `/llmproxy/v1/chat/completions` | OpenAI chat. Honors `stream`. Returns SSE if true, single JSON otherwise. |

---

## Protocol types (`sur/llmproxy.hoon`)

```hoon
+$  job-id  [src=@p time=@da nonce=@ud]    :: globally unique without a coordinator

+$  job-req
  $:  id=job-id
      model=@t
      prompt=@t
  ==

+$  token-chunk
  $:  id=job-id
      seq=@ud
      text=@t
      done=?
  ==

+$  access-policy
  $%  [%whitelist ships=(set @p)]          :: deny by default; ships are allowed
      [%blacklist ships=(set @p)]          :: allow by default; ships are denied
  ==
```

The node's own ship is always allowed regardless of policy mode.

The `seq` field on `token-chunk` is reserved for future progressive
streaming. Today every job emits exactly one chunk with `done=%.y`, so
`seq` is always `0`.

## Marks

```
mar/llmproxy/job.hoon      :: %llmproxy-job   = job-req
mar/llmproxy/token.hoon    :: %llmproxy-token = token-chunk
mar/llmproxy/models.hoon   :: %llmproxy-models = (list @t)
```

---

## Job lifecycle

A typical OpenAI HTTP call from a tool like Continue.dev:

1. **Tool** sends `POST /llmproxy/v1/chat/completions` to the local ship.
2. **Eyre** routes to `%llmproxy-client` via `%handle-http-request`.
3. **Client** checks `bearer-ok`, parses the OpenAI body
   (`parse-openai-request`), assigns a nonce, builds a `job-req`, and emits:
   - a `%poke %llmproxy-job` to `[node %llmproxy-node]` on wire `/poke/<n>`
   - a `%watch /job/<n>` to the same agent on wire `/watch/<n>`
   It records a `pending-client` keyed by `<n>` with the eyre-id.
4. **Node** receives the poke, runs `allowed src.bowl our.bowl policy`. On
   denial it crashes the poke (`!!`) — Gall ack-nacks the client. On
   allow it builds an Iris request, passes `[%i %request ...]` on wire
   `/req/<n>`, and stores a `pending-job`.
5. **Iris** delivers `[%http-response %finished ...]` on `/req/<n>`.
   Node converts the response, extracts the assistant text, builds a
   `token-chunk` with `done=%.y`, and emits a `%fact` + `%kick` on
   `/job/<n>`.
6. **Client** receives the fact on `/watch/<n>`, looks up the pending
   record, and:
   - For `%openai`: emits SSE chunks (`sse-cards`) or a single JSON body
     (`give-simple-payload` + `build-completion-json`) depending on
     `stream`.
   - For `%test`: re-renders the UI with the response in a `<pre>` block.
   - For `%dojo`: prints with `~&` and emits no HTTP cards.
   It then leaves the subscription and deletes the pending record.

If step 4 nacks (poke ack with non-null `p.sign`), the client emits HTTP
403 ("poke rejected by node (likely access policy)") to the eyre-id and
leaves the watch.

If the watch ack itself fails (node unreachable / agent not running), the
client emits HTTP 502 ("node unreachable").

---

## Auth

Two independent gates:

**Node-side: access policy.** Enforced inside `%llmproxy-job` poke
handling. `whitelist` denies by default and only allows listed ships;
`blacklist` allows by default and denies listed ships. The node's own
ship is always allowed. The check is the pure `allowed` arm in
`lib/llmproxy-helpers.hoon`. Denied requests crash the poke, which the
client surfaces as HTTP 403.

**Client-side: optional Bearer token.** The client compares the incoming
`Authorization: Bearer ...` header against `client-api-token`. Empty
token disables the check. Non-empty requires an exact match. Mismatch
returns HTTP 401.

**Token format reservation.** Eyre intercepts
`Authorization: Bearer 0v...` as a session-token lookup, so tokens
generated via the UI's "generate random" button are prefixed with `sk-`
to keep them out of that path. Manually-set tokens can be any non-empty
cord.

---

## Streaming caveat

The OpenAI request honors `stream: true` and the response is a properly
formed SSE event stream — but Iris (Urbit's HTTP client) buffers the
upstream backend's response fully before delivering it to the agent. The
node has nothing to forward until the whole inference completes. From
the curl client's perspective: silence, then all chunks at once.

True progressive streaming would require either runtime changes to Iris
(stream chunk events into Arvo as they arrive) or replacing the Iris
hop with a `%lick`-based unix bridge that pipes the backend's SSE
output. Out of scope here.

---

## State migration

Both agents' `on-load` use a `mole`-wrapped `!<` to deserialize the saved
vase. On failure, they log and call `on-init`. This avoids the standard
Gall `%load-failed` hard-stop when the state shape changes between desk
revisions, at the cost of silently dropping the old state.

```hoon
=/  loaded  (mole |.(!<(state-0 vase)))
?~  loaded
  ~&  >>  %llmproxy-client-reset-state
  on-init
`this(state u.loaded)
```

This is the right tradeoff for a hobbyist desk where the operator can
reconfigure via UI in two minutes. A production desk would build proper
versioned state migrations.

---

## Desk layout

```
desk/
  desk.bill                  :: %llmproxy-node, %llmproxy-client
  desk.docket-0              :: app metadata
  sur/llmproxy.hoon          :: shared types
  app/
    llmproxy-node.hoon
    llmproxy-client.hoon
  lib/
    llmproxy-helpers.hoon    :: pure helpers (allowed, parsers, builders)
  mar/llmproxy/
    job.hoon                 :: %llmproxy-job   = job-req
    token.hoon               :: %llmproxy-token = token-chunk
    models.hoon              :: %llmproxy-models = (list @t)
  tests/
    lib/llmproxy-helpers.hoon  :: hoon unit tests for pure helpers
tests/
  e2e.sh                     :: bash HTTP-level tests
docs/
  multi-friend.dot/.svg/.png :: deployment topology diagram
```

`lib/llmproxy-helpers.hoon` exists so that auth checks, JSON/form/CSV
parsers, builders, and tape utilities are unit-testable in isolation
without spinning up Gall agents.

---

## Out of scope (today)

These are deliberate exclusions, not bugs:

- **Multi-node routing.** The client has a single `node=@p`. No
  fallback, no load-balancing, no model-aware dispatch.
- **A directory.** Nodes are added by typing a `@p` into the UI form.
  No discovery service.
- **Per-ship rate limits or queueing.** The node has a `pending` map
  keyed by nonce, but nothing throttles concurrent jobs from the same
  ship beyond what the backend itself enforces.
- **Galaxy/star/moon-based policies.** Only flat whitelist/blacklist.
- **True progressive streaming.** See the streaming caveat above.
- **Multi-model node config.** A node has one backend URL. The
  `models` list is whatever the backend's `/v1/models` advertises.
