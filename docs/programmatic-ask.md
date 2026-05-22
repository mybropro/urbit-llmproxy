# Programmatic ask — letting other agents use the proxy

> **Status:** implemented on branch `programmatic-ask`. Adds a capability on
> `%llmproxy-client` so other Gall agents on the *same ship* can use the proxy
> via poke + subscribe, getting the completion back as a typed fact. The poke
> uses the dedicated mark `%llmproxy-ask` (sample type `ask-agent`); the result
> is a `%llmproxy-token` fact or, on failure, a `%llmproxy-ask-error` fact, both
> on `/ask-result/[id]`.

## Why

Today `%llmproxy-client` has two real consumers: the HTTP entrypoint
(`POST /llmproxy/v1/chat/completions`) and the dojo `%ask` test poke (which
prints to dojo, no result returned to a caller). There's no way for *another
Gall agent* to use the proxy and get the answer back.

The motivating consumer is `%papertrail`, which runs a classify → extract →
judge LLM pipeline and wants to call the LLM without knowing or caring which
node llmproxy routes to. It should just poke its local llmproxy-client and get
a completion. But this is a generally useful feature: any on-ship agent can
treat llmproxy as a local LLM service.

## Concept

```
caller agent (e.g. %papertrail)                 %llmproxy-client
─────────────────────────────────               ──────────────────────────
1. pick request id
2. %watch /ask-result/[id]  ───────────────────► on-watch: accept (local only)
3. %poke %llmproxy-ask [id model body] ────────► on-poke: poke node, watch /job/n
                                                 (exact existing %ask machinery)
4. on-agent: %llmproxy-token fact ◄──── %give ◄─ on node's final token fact,
   read content, advance, %leave                give result on /ask-result/[id]
```

The caller builds the **full OpenAI chat-completions body** itself (system+user
messages, `response_format`, temperature, …). The client forwards it verbatim
to the node, exactly as the HTTP path does — so the client needs zero knowledge
of message structure.

## Changes, file by file

### 1. `sur/llmproxy.hoon` — new poke + error types

```hoon
+$  ask-agent  [id=@ta model=@t body=@t]   :: body = full OpenAI chat-completions JSON
+$  ask-error  [id=@ta reason=@t]
```

`token-chunk` is reused unchanged as the success fact.

### 2. `app/llmproxy-client.hoon` — `pending-client` (currently ~:20–28)

Add `%agent` to the `kind` enum and store the caller's request id, so we know
which `/ask-result/[id]` path to answer on:

```hoon
+$  pending-client
  $:  eyre-id=@ta
      target=@p
      model=@t
      stream=?
      kind=?(%openai %test %dojo %agent)   :: + %agent
      prompt=@t
      api-base=@t
      ask-id=@ta                            :: NEW: caller's id, set for %agent kind
  ==
```

The three existing construction sites (`%openai` HTTP path, `%test` UI form,
`%dojo` `%ask`) just set `ask-id=''`.

### 3. `app/llmproxy-client.hoon` — `on-poke`, new `%ask-agent` handler

Mirror the existing `%ask` handler (~:484–497). Differences: take `body`
instead of building one from a `prompt`; target the **configured `node.state`**
(callers don't pick nodes); set `kind=%agent`; stash `ask-id`.

```hoon
%ask-agent
?>  =(src.bowl our.bowl)            :: SECURITY: same-ship agents only (see note)
=/  n=@ud  +(nonce.state)
=/  jid=job-id:llmproxy  [our.bowl now.bowl n]
=/  jr=job-req:llmproxy  [jid model.cmd body.cmd]      :: caller's body, verbatim
=/  pat=path  /job/(scot %ud n)
=/  rec=pending-client
  ['' node.state model.cmd %.n %agent '' '' id.cmd]    :: kind=%agent, ask-id=id
:_  this(nonce n, pending (~(put by pending.state) n rec))
:~  [%pass /poke/(scot %ud n) %agent [node.state %llmproxy-node] %poke %llmproxy-job !>(jr)]
    [%pass /watch/(scot %ud n) %agent [node.state %llmproxy-node] %watch pat]
==
```

Use a dedicated `%llmproxy-ask` mark (cleanest public API → needs
`mar/llmproxy/ask.hoon`), or fold `[%ask-agent ...]` into the existing `%noun`
command union for zero new mark files. Prefer the dedicated mark — this is a
real cross-agent API.

### 4. `app/llmproxy-client.hoon` — `on-watch` (currently ~:739–743)

Today it only accepts `[%http-response *]` and defers the rest to
`default-agent` (which rejects). Accept the result paths, gated to our own ship:

```hoon
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?:  ?=([%http-response *] path)  `this
  ?:  ?=([%ask-result @ ~] path)
    ?>  =(src.bowl our.bowl)        :: only local agents subscribe to results
    `this
  (on-watch:def path)
```

### 5. `app/llmproxy-client.hoon` — `on-agent` success (the `kind` switch ~:826–859)

Add an `%agent` arm to the `?- kind.u.rec` switch that fires on the final token
fact. Forward the token-chunk verbatim on the result path:

```hoon
%agent
[%give %fact ~[/ask-result/[ask-id.u.rec]] %llmproxy-token !>(tc)]~
```

Verbatim (rather than `(extract-content text.tc)`) keeps this a general feature
— the caller gets exactly what the HTTP path gets, including `usage`/
`tool_calls`. The caller runs its own `choices[0].message.content` extraction.
If a clean-text variant is wanted later, swap in `(extract-content text.tc)`.

### 6. `app/llmproxy-client.hoon` — `on-agent` failure paths

So callers' state machines never hang, add `%agent` arms to the two failure
handlers:

- **poke-ack rejection** (node access policy denied us, ~:782–798): give an
  `ask-error` fact on `/ask-result/[id]`, then leave.
- **watch-ack failure** (node unreachable, ~:800–811): same.

```hoon
%agent
:_  this(pending (~(del by pending.state) n))
:~  leave-card
    [%give %fact ~[/ask-result/[ask-id.u.rec]] %llmproxy-ask-error !>([ask-id.u.rec 'node rejected or unreachable'])]
==
```

Callers treat an `ask-error` (or a `%kick` before any result) as a failed stage
→ retry with backoff, the same way `llm.py` retries on 4xx/5xx.

### 7. Mark files

- `mar/llmproxy/ask.hoon` — for the `%llmproxy-ask` poke (skip if folded into `%noun`).
- `mar/llmproxy/ask/error.hoon` — for the `%llmproxy-ask-error` fact. Note the
  nesting: Clay maps *every* hyphen in a mark name to a path separator, so
  `%llmproxy-ask-error` resolves to `mar/llmproxy/ask/error.hoon`, not
  `mar/llmproxy/ask-error.hoon` (a hyphenated filename is unreachable as a mark).
- `mar/llmproxy/token.hoon` — already exists, reused for the success fact.

### 8. Tests

The ask path is mostly effectful, so cover it with an `e2e.sh` scenario: a
throwaway test agent pokes `%ask-agent` and asserts it receives a
`%llmproxy-token` fact on `/ask-result/[id]` — confirms the loop end to end.
Add pure unit tests only if logic is factored into `lib/llmproxy-helpers.hoon`.

## Security note

The HTTP entrypoint is gated by the client-api-token; a Gall poke is not. So
`%ask-agent` must be restricted (the `?> =(src.bowl our.bowl)` above) to agents
on **your own ship** — otherwise a remote ship could poke your client and use
your proxy without the token gate. The node's access policy still independently
gates the actual job, but defense in depth: the programmatic ask is a *local*
convenience, not a network entrypoint. Consumers like papertrail always run on
the same ship as the llmproxy-client they use, so this costs nothing.

## Footprint

~4 small edits to `llmproxy-client.hoon` (one enum field, one poke arm, one
on-watch line, three on-agent arms), 2 type additions, 1–2 new mark files. It's
additive — no existing behavior changes.
