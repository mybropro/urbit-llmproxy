# %llmproxy — Urbit LLM Proxy

## What it is

`%llmproxy` is an Urbit desk that turns any Urbit ship into an OpenAI-compatible LLM proxy. A ship running a **node** agent exposes its local inference backend (Ollama, llama.cpp, vLLM, etc.) to other ships over Ames. A ship running the **client + shim** agents gets a local HTTP endpoint that any OpenAI-compatible tool can point at — Continue.dev, Open WebUI, shell scripts using `curl`, anything.

The key properties:

- **No coordinator.** There is no central server. Each node is sovereign — it sets its own access policy, manages its own queue, and decides who can submit jobs.
- **No open ports on the node.** The node's Ollama backend is never exposed to the internet. All communication goes through Urbit's Ames protocol, which handles NAT traversal, encryption, and authentication natively.
- **Identity is free.** Urbit `@p` ships are the auth layer. No API keys, no accounts, no HMAC tokens.
- **One desk, multiple roles.** Both ships install the same `%llmproxy` desk. Each operator starts only the agents they need.

---

## Roles

### Node operator

Someone with a GPU (or any machine running a local LLM backend) who wants to serve inference to other ships.

Runs: `%llmproxy-node`

Configures: which models to advertise, access policy (open / galaxy-only / whitelist), Ollama backend URL.

### Client user

Someone who wants to use LLMs via Urbit and has an existing tool (Continue.dev, Open WebUI, etc.) that speaks the OpenAI API.

Runs: `%llmproxy-client` + `%llmproxy-shim`

Configures: which node ship(s) to connect to.

### Both

A single ship can run all three agents simultaneously — useful for someone who wants to serve inference and use it locally.

---

## Installation

```
|install ~node %llmproxy
```

Then start the agents you need:

```
:: node operator
|start %llmproxy-node

:: client user
|start %llmproxy-client
|start %llmproxy-shim
```

---

## Agent overview

### `%llmproxy-node`

The inference-serving agent. Runs on any ship with a local LLM backend.

**Responsibilities:**
- Accepts job submissions from client ships over Ames
- Enforces access policy (open, galaxy-only, or explicit whitelist)
- Maintains a local priority queue
- Dispatches jobs to a local Ollama/vLLM/llama.cpp backend via HTTP thread
- Streams token chunks back to the requesting ship as Gall subscription facts

**Configuration pokes:**
```
::  set which models this node advertises
:llmproxy-node %set-models ~[%llama3-8b %mistral-7b]

::  set access policy
:llmproxy-node %set-policy [%open ~]
:llmproxy-node %set-policy [%whitelist (sy ~[~zod ~nec])]
:llmproxy-node %set-policy [%galaxy-only ~]

::  set local backend URL
:llmproxy-node %set-backend 'http://localhost:11434'
```

**State:**
```hoon
+$  node-state
  $:  models=(list model-id)       ::  advertised models
      policy=access-policy         ::  who can submit
      queue=(list job-req)         ::  pending jobs
      active=(unit job-id)         ::  currently running job
      rate-limits=(map @p @ud)     ::  requests/hour per ship
      backend-url=@t               ::  local inference backend
  ==
```

---

### `%llmproxy-client`

The Urbit-side client agent. Manages node connections and routes jobs.

**Responsibilities:**
- Maintains a registry of known node ships (manually added by the user)
- On job submission from the shim, selects the appropriate node by model name
- Pokes the node ship with the job over Ames
- Subscribes to the node's `/job/[id]` path to receive streaming token chunks
- Forwards token chunks to the shim for SSE delivery

**Configuration pokes:**
```
::  add a node ship (fetches its capabilities automatically)
:llmproxy-client %add-node ~sampel-palnet

::  remove a node
:llmproxy-client %remove-node ~sampel-palnet

::  refresh a node's advertised capabilities
:llmproxy-client %refresh-node ~sampel-palnet
```

**State:**
```hoon
+$  client-state
  $:  nodes=(map @p node-ad)       ::  known node ships + their capabilities
      jobs=(map job-id job-state)  ::  active and recent jobs
  ==
```

When `%add-node` is called, the client pokes the target ship with `%ping` to fetch its current `node-ad` (model list, queue depth, policy). If the node's policy rejects the requesting ship, an error is returned immediately.

---

### `%llmproxy-shim`

An Eyre HTTP handler. Translates between the OpenAI API and Gall pokes.

**Responsibilities:**
- Binds the `/llmproxy` path on the ship's HTTP server
- Handles `POST /llmproxy/v1/chat/completions` — parses OpenAI request JSON, pokes `%llmproxy-client`, holds the connection open, streams SSE `data:` chunks as token gifts arrive, closes with `data: [DONE]`
- Handles `GET /llmproxy/v1/models` — returns all models across all known nodes in OpenAI format

**Auth:** Eyre's existing session authentication gates all requests to the ship owner. The `Authorization` header sent by OpenAI clients is accepted but not validated — any non-empty value works.

---

## Protocol types (`sur/llmproxy.hoon`)

```hoon
+$  model-id  @tas
::  e.g. %llama3-8b, %mistral-7b-instruct

+$  job-id    [src=@p time=@da nonce=@ud]
::  globally unique without a coordinator

+$  message
  $:  role=?(%system %user %assistant)
      content=@t
  ==

+$  job-req
  $:  id=job-id
      model=model-id
      messages=(list message)
      params=job-params
  ==

+$  job-params
  $:  temperature=@rs
      max-tokens=@ud
      stream=?
  ==

+$  token-chunk
  $:  id=job-id
      seq=@ud        ::  ordering guarantee across Ames messages
      text=@t        ::  may contain 1..10 tokens (see batching rule)
      done=?
  ==

+$  node-ad
  $:  ship=@p
      models=(list model-id)
      queue-depth=@ud
      policy=access-policy
      updated=@da
  ==

+$  access-policy
  $%  [%open ~]
      [%galaxy-only ~]
      [%whitelist ships=(set @p)]
      [%moons-of ship=@p]      ::  any moon under this planet (^sein:title)
  ==
```

---

## Job lifecycle

1. **User tool** sends `POST /llmproxy/v1/chat/completions` to `http://localhost:8080/llmproxy`
2. **Shim** parses the request, extracts model name and messages, pokes `%llmproxy-client` with `%submit`
3. **Client** looks up the requested model in its `nodes` map, selects the node serving it, generates a `job-id`, pokes the node ship with `%submit-job` over Ames, subscribes to `/job/[job-id]` on that ship
4. **Node** receives the poke, checks policy and rate limits, appends to queue, dispatches to a Hoon thread if idle
5. **Thread** POSTs to the configured **OpenAI-compatible** `/v1/chat/completions` endpoint with `stream: true`, reads SSE response, batches tokens (see *Chunk batching*), emits `token-chunk` gifts back to the node agent
6. **Node** forwards each `token-chunk` as a subscription fact on `/job/[job-id]`
7. **Client** receives facts, forwards as gifts to the shim
8. **Shim** serializes each chunk as an SSE `data:` event, flushes to the open HTTP connection
9. **User tool** receives streamed tokens in real time, same as any OpenAI-compat server

---

## Client configuration (Continue.dev example)

After installing and starting agents, the user adds a provider in their tool's config:

```json
{
  "models": [
    {
      "title": "Llama 3 via Urbit",
      "provider": "openai",
      "model": "llama3-8b",
      "apiBase": "http://localhost:8080/llmproxy",
      "apiKey": "urbit"
    }
  ]
}
```

`apiBase` is always `http://[ship-host]:8080/llmproxy`. For a locally-running ship that's `localhost:8080`. For a ship running on a VPS it would be the server's domain or IP.

`model` must match the `model-id` atom the node was configured with (e.g. `llama3-8b`).

`apiKey` can be any non-empty string — it is not validated.

---

## Access policy on nodes

Node operators control who can submit jobs:

| Policy | Effect |
|--------|--------|
| `[%open ~]` | Any ship can submit |
| `[%galaxy-only ~]` | Only ships sponsored by galaxies (filters out comets) |
| `[%whitelist ships=(set @p)]` | Explicit list of permitted ships |
| `[%moons-of ship=@p]` | Any moon whose parent (`^sein:title`) is this planet |

Rejected submissions receive an immediate `%error` gift with a reason. The client surfaces this as an HTTP error to the shim.

---

## Desk structure

```
llmproxy/
  app.hoon                  ::  desk config
  sur/
    llmproxy.hoon           ::  shared molds
  app/
    node.hoon               ::  %llmproxy-node
    client.hoon             ::  %llmproxy-client
    shim.hoon               ::  %llmproxy-shim
  mar/
    llmproxy/
      job.hoon              ::  job-req mark
      token.hoon            ::  token-chunk mark
      ad.hoon               ::  node-ad mark
  lib/
    llmproxy.hoon           ::  shared helpers
  thread/
    run-job.hoon            ::  async Ollama HTTP + streaming
```

---

## Chunk batching

To avoid one Ames message per token (200-message round trips for a typical response), the run-job thread batches tokens before emitting a `token-chunk` gift. Flush rule:

- **10 tokens accumulated**, OR
- **3 seconds elapsed since the last flush**, OR
- **`done=%.y`** (final chunk, always flushed regardless of size)

whichever comes first. `seq` is monotonic per `job-id` and increments once per emitted chunk, not once per token. The shim re-emits each chunk as a single SSE `data:` event with the joined text — OpenAI's streaming spec permits multi-token deltas, so clients render identically.

This trades ~10x fewer Ames messages for up to 3 s of additional perceived latency at the tail of generation when models slow down. The 3 s ceiling is a safety net; in practice the 10-token trigger fires first for any model running >3.3 tokens/sec.

---

## Open questions / v2 considerations

**Backend format** — v1 supports **OpenAI-compatible HTTP endpoints only** (`POST /v1/chat/completions` with `stream: true`). This covers Ollama (via its `/v1/*` compat layer), vLLM, llama.cpp's server, LM Studio, TGI, and most other inference servers. Native non-compat formats (Ollama's `/api/chat`, raw llama.cpp completions API, etc.) are out of scope.

**Discovery / directory** — for v1, node ships are added manually with `%add-node`. With the moon-per-model deployment pattern this means an operator running 5 models has 5 moons that each client must add by `@p`. A v2 directory agent (`%llmproxy-dir`) is the natural fix: nodes advertise capabilities to a well-known ship, clients query by model. Out of scope for v1.

**Multi-node routing** — the client currently picks the first node serving the requested model. A smarter strategy (lowest queue depth, lowest latency, preferred ship list) is a natural v2 improvement once the basic protocol is working.

---

## Deployment pattern: moons per model

The intended deployment for a node operator is **one moon per model**, all spawned under a single planet. A moon is a free, sponsored sub-identity — `|moon` from a planet's dojo issues new keys; the moon ship name is deterministic from the parent. An operator with 4 models spawns 4 moons:

```
~sampel-palnet                   ::  parent planet (no node agent needed)
~doznec-pinwod-sampel-palnet     ::  moon serving llama3-8b
~ridlur-figbud-sampel-palnet     ::  moon serving mistral-7b
~litzod-norsep-sampel-palnet     ::  moon serving qwen-32b
~dapwep-fadted-sampel-palnet     ::  moon serving deepseek-coder-33b
```

Each moon runs `%llmproxy-node` with its own backend URL (likely a different port or host) and advertises its single model. Benefits:

- **Resource isolation** — each moon is its own urbit process, with its own pier, queue, and event log. A crash in the qwen-32b moon doesn't take down the others.
- **Per-model access policy** — the operator may want `%open` on a small model and `%moons-of` (org-only) on a large one.
- **Cheap horizontal scale** — adding a model = `|moon` + boot + start agent. No re-deploy, no agent state migration.
- **Trust inheritance** — the `%moons-of ship=@p` policy lets every moon of a planet trust every other moon for free.

The protocol still permits a single node to advertise multiple models (`models=(list model-id)`) — useful for an operator running two small models on one box without bothering with separate moons. The multi-moon pattern is a *convention*, not a constraint.
