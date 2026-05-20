::  /sur/llmproxy: shared types for %llmproxy desk
::
|%
+$  job-id  [src=@p time=@da nonce=@ud]
::
::  `body` is the full OpenAI-compatible request body the client received,
::  forwarded verbatim to the backend so tools, tool_choice, temperature,
::  response_format, etc. all pass through untouched. The node overlays
::  `stream: false` before calling the backend (Iris buffers fully).
+$  job-req
  $:  id=job-id
      model=@t
      body=@t
  ==
::
::  `text` is the full backend response body, forwarded verbatim by the
::  client. Display-only paths (UI test form, dojo `[%ask ...]`) parse
::  `choices[0].message.content` out of it via extract-content.
+$  token-chunk
  $:  id=job-id
      seq=@ud
      text=@t
      done=?
  ==
::
::  Programmatic ask: a same-ship Gall agent pokes %llmproxy-client with an
::  `ask-agent` (its own request `id`, a model, and the full OpenAI
::  chat-completions `body`) and subscribes to /ask-result/[id]. It gets the
::  backend response back as a %llmproxy-token fact (verbatim, same as the HTTP
::  path), or an `ask-error` fact if the node rejected the job or was
::  unreachable. See docs/programmatic-ask.md.
+$  ask-agent  [id=@ta model=@t body=@t]
+$  ask-error  [id=@ta reason=@t]
::
::  Access policy enforced by %llmproxy-node on incoming job pokes.
::  In both modes, the node's own ship is always allowed.
::    %whitelist — deny everyone except `ships`
::    %blacklist — allow everyone except `ships`
+$  access-policy
  $%  [%whitelist ships=(set @p)]
      [%blacklist ships=(set @p)]
  ==
::
::  Telemetry: ring-buffer entries describing recent activity. Both
::  agents independently keep the last N entries (newest-first) in
::  their state and expose them via scry + UI for debugging.
::
::  Node entry — one per inbound %llmproxy-job that the node accepted
::  (i.e. passed the access policy and reached the backend). Denied
::  jobs do not appear here: the current denial path crashes the poke,
::  which rolls back any telemetry write. Denials are visible from the
::  client side as %node-rejected entries.
+$  node-telemetry-entry
  $:  time=@da
      src=@p
      nonce=@ud
      model=@t
      status=?(%ok %backend-error %no-response)
      http-code=@ud
      latency-ms=@ud
      req-bytes=@ud
      resp-bytes=@ud
  ==
::
::  Client entry — one per inbound HTTP request hitting /llmproxy/v1/*.
::  /ui requests are intentionally excluded (config noise).
::
::  status meanings:
::    %ok               — 200 returned to caller
::    %unauthorized     — 401, bad/missing Bearer token
::    %bad-request      — 400, body failed parse-openai-request
::    %node-rejected    — 403, poke nacked by node (likely policy)
::    %node-unreachable — 502, watch-ack nacked
::
::  authed: %none if no token is configured (open endpoint), %ok if a
::  configured token matched, %fail if the request was rejected.
+$  client-telemetry-entry
  $:  time=@da
      endpoint=?(%chat %models)
      target=@p
      nonce=@ud
      model=@t
      stream=?
      authed=?(%ok %none %fail)
      status=?(%ok %unauthorized %bad-request %node-rejected %node-unreachable)
      latency-ms=@ud
      resp-bytes=@ud
  ==
--
