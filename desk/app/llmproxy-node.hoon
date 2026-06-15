::  %llmproxy-node: serve LLM inference over Ames (non-streaming Iris).
::
::  Pokes received: %llmproxy-job
::  Subscriptions: /job/<nonce> — emits one %fact with the full response,
::  then a final fact with done=%.y, then a kick.
::
/-  llmproxy
/+  default-agent, *llmproxy-helpers
::
|%
+$  card  card:agent:gall
+$  pending-job
  $:  src=@p
      model=@t
      jid=job-id:llmproxy
      started=@da
      req-bytes=@ud
  ==
::  Older pending-job, kept for state-0 deserialization in on-load.
+$  pending-job-0  [src=@p model=@t jid=job-id:llmproxy]
+$  state-0
  $:  %0
      backend-url=@t
      backend-key=@t
      policy=access-policy:llmproxy
      advertised=(list @t)
      pending=(map @ud pending-job-0)
  ==
::  Union of every state shape this agent has ever shipped. on-load casts
::  the persisted state to this and migrates forward to the current shape.
::  RULE: once a version ships, freeze its +$; any shape change adds a new
::  +$ state-N (with a fresh %N tag) and a migration arm in on-load. Never
::  reshape a tagged version in place — that breaks the cast on upgrade.
+$  state-1
  $:  %1
      backend-url=@t
      backend-key=@t
      policy=access-policy:llmproxy
      advertised=(list @t)
      pending=(map @ud pending-job)
      telemetry=(list node-telemetry-entry:llmproxy)
  ==
+$  versioned-state  $%(state-0 state-1)
::  Cap on the in-state telemetry ring buffer.
++  telemetry-cap  20
--
::
=|  state-1
=*  state  -
::
=>  |%
    ::  Pure helpers (allowed, build-body, build-headers, derive-models-url,
    ::  parse-models-list, extract-content) live in /lib/llmproxy-helpers.hoon
    ::  and are imported via /+ above.
    ::
    ::  Build an Iris GET request card aimed at the backend's /v1/models endpoint.
    ++  refresh-models-card
      |=  [chat-url=@t api-key=@t]
      ^-  card
      =/  =request:http
        :*  method=%'GET'
            url=(derive-models-url chat-url)
            header-list=(build-headers ~ api-key)
            body=~
        ==
      [%pass /refresh-models %arvo %i %request request *outbound-config:iris]
    --
::
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  =/  default-backend=@t  'http://localhost:11434/v1/chat/completions'
  :_  this(state [%1 default-backend '' [%whitelist ~] ~ ~ ~])
  :~  (refresh-models-card default-backend '')
      [%pass /refresh-tick %arvo %b %wait (add now.bowl ~m30)]
  ==
::
++  on-save  !>(state)
::
++  on-load
  |=  old-state=vase
  ^-  (quip card _this)
  ::  Versioned, non-destructive load (see the rationale on the state defs).
  ::  Hard-cast and migrate forward; no on-init fallback.
  =/  s  !<(versioned-state old-state)
  =.  state
    ?-  -.s
        %1  s
    ::
    ::  state-0 → state-1: drop any in-flight pending jobs (their old
    ::  shape lacks started/req-bytes, and we'd have no clean way to
    ::  reconstruct latency or sizes for them anyway), init telemetry.
        %0
      :*  %1
          backend-url.s
          backend-key.s
          policy.s
          advertised.s
          *(map @ud pending-job)
          *(list node-telemetry-entry:llmproxy)
      ==
    ==
  ::  Re-arm the auto-refresh timer on every reload. Existing in-flight
  ::  timers from prior revisions still fire on this same wire; on-arvo
  ::  handles those harmlessly (refresh + reschedule).
  :_  this
  [%pass /refresh-tick %arvo %b %wait (add now.bowl ~m30)]~
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark  (on-poke:def mark vase)
      %noun
    =/  cmd
      !<  $%  [%set-backend url=@t]
              [%set-backend-key key=@t]
              [%set-backend-and-key url=@t key=@t]
              [%set-policy =access-policy:llmproxy]
              [%refresh-models ~]
          ==
      vase
    ?-    -.cmd
        %set-backend
      ~|  "llmproxy-node: backend url must be http(s) and end in /chat/completions: {(trip url.cmd)}"
      ?>  (valid-backend-url url.cmd)
      :_  this(backend-url url.cmd)
      [(refresh-models-card url.cmd backend-key)]~
    ::
        %set-backend-key
      :_  this(backend-key key.cmd)
      [(refresh-models-card backend-url key.cmd)]~
    ::
    ::  Atomic update — both fields together, single refresh. The client's
    ::  merged "update backend" form uses this so it can defer its HTTP
    ::  response on a single /models fact rather than race two refreshes.
        %set-backend-and-key
      ~|  "llmproxy-node: backend url must be http(s) and end in /chat/completions: {(trip url.cmd)}"
      ?>  (valid-backend-url url.cmd)
      :_  this(backend-url url.cmd, backend-key key.cmd)
      [(refresh-models-card url.cmd key.cmd)]~
    ::
        %set-policy  `this(policy access-policy.cmd)
    ::
        %refresh-models
      :_  this
      [(refresh-models-card backend-url backend-key)]~
    ==
  ::
      %llmproxy-job
    ?.  (allowed src.bowl our.bowl policy)
      ~|  "llmproxy-node: access denied for {<src.bowl>} under policy {<-.policy>}"
      !!
    =/  jr  !<(job-req:llmproxy vase)
    =/  body=@t  (build-body body.jr)
    =/  =request:http
      :*  method=%'POST'
          url=backend-url
          header-list=(build-headers `'application/json' backend-key)
          body=`(as-octs:mimes:html body)
      ==
    =/  n=@ud  nonce.id.jr
    =/  wir=wire  /req/(scot %ud n)
    =/  rec=pending-job  [src.bowl model.jr id.jr now.bowl (met 3 body)]
    :_  this(pending (~(put by pending) n rec))
    [%pass wir %arvo %i %request request *outbound-config:iris]~
  ==
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?+  path  (on-watch:def path)
      [%job @ ~]  `this
  ::
      [%models ~]
    :_  this
    [%give %fact ~ %llmproxy-models !>(advertised)]~
  ==
::
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ?+  wire  (on-arvo:def wire sign-arvo)
      [%refresh-models ~]
    ?+  +<.sign-arvo  (on-arvo:def wire sign-arvo)
        %http-response
      =/  resp=client-response:iris  +>.sign-arvo
      ?.  ?=(%finished -.resp)  `this
      =/  rep  (to-httr:iris [response-header.resp full-file.resp])
      =/  body-text=@t
        ?~  r.rep  ''
        q.u.r.rep
      =/  ms=(list @t)  (parse-models-list body-text)
      :_  this(advertised ms)
      [%give %fact ~[/models] %llmproxy-models !>(ms)]~
    ==
  ::
      [%req @ ~]
    =/  n=@ud  (slav %ud i.t.wire)
    ?+  +<.sign-arvo  (on-arvo:def wire sign-arvo)
        %http-response
      =/  resp=client-response:iris  +>.sign-arvo
      =/  rec=(unit pending-job)  (~(get by pending) n)
      ?~  rec  `this
      ?.  ?=(%finished -.resp)  `this
      =/  rep  (to-httr:iris [response-header.resp full-file.resp])
      =/  body-text=@t
        ?~  r.rep  ''
        q.u.r.rep
      =/  http-code=@ud  p.rep
      =/  ok=?  &((gte http-code 200) (lth http-code 300))
      =/  entry=node-telemetry-entry:llmproxy
        :*  now.bowl
            src.u.rec
            n
            model.u.rec
            ?:(ok %ok %backend-error)
            http-code
            (elapsed-ms now.bowl started.u.rec)
            req-bytes.u.rec
            (met 3 body-text)
        ==
      =/  pat=path  /job/(scot %ud n)
      =/  tc=token-chunk:llmproxy  [jid.u.rec 0 body-text &]
      :_  %=  this
              pending    (~(del by pending) n)
              telemetry  (scag telemetry-cap `(list node-telemetry-entry:llmproxy)`[entry telemetry])
          ==
      :~  [%give %fact ~[pat] %llmproxy-token !>(tc)]
          [%give %kick ~[pat] ~]
      ==
    ==
  ::
      [%refresh-tick ~]
    ?+  +<.sign-arvo  (on-arvo:def wire sign-arvo)
        %wake
      :_  this
      :~  (refresh-models-card backend-url backend-key)
          [%pass /refresh-tick %arvo %b %wait (add now.bowl ~m30)]
      ==
    ==
  ==
::
++  on-leave  on-leave:def
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+  path  (on-peek:def path)
      [%x %advertised ~]    ``noun+!>(advertised)
      [%x %policy ~]        ``noun+!>(policy)
      [%x %backend ~]       ``noun+!>(backend-url)
      [%x %backend-key ~]   ``noun+!>(backend-key)
      [%x %telemetry ~]     ``noun+!>(telemetry)
  ==
++  on-agent  on-agent:def
++  on-fail   on-fail:def
--
