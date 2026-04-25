::  %llmproxy-shim: OpenAI-compatible HTTP gateway.
::
::  Endpoints:
::    GET  /llmproxy/v1/models           list configured models
::    POST /llmproxy/v1/chat/completions chat (honors `stream` field)
::
::  Streaming caveat: returns properly-formed SSE when stream=true, but
::  Iris buffers the full Ollama response so all chunks arrive at once.
::
/-  llmproxy
/+  default-agent, server
::
|%
+$  card  card:agent:gall
+$  pending-shim
  $:  eyre-id=@ta
      model=@t
      stream=?
  ==
+$  state-0
  $:  %0
      nonce=@ud
      node=@p
      models=(list @t)
      pending=(map @ud pending-shim)
  ==
--
::
=|  state-0
=*  state  -
::
=>  |%
    ::  Parse incoming OpenAI chat-completion request body.
    ++  parse-openai-request
      |=  body=@t
      ^-  (unit [model=@t prompt=@t stream=?])
      =/  jon=(unit json)  (de:json:html body)
      ?~  jon  ~
      ?.  ?=([%o *] u.jon)  ~
      =/  m=(unit json)  (~(get by p.u.jon) 'model')
      ?~  m  ~
      ?.  ?=([%s *] u.m)  ~
      =/  msgs=(unit json)  (~(get by p.u.jon) 'messages')
      ?~  msgs  ~
      ?.  ?=([%a *] u.msgs)  ~
      ?~  p.u.msgs  ~
      =/  last=json  (rear p.u.msgs)
      ?.  ?=([%o *] last)  ~
      =/  c=(unit json)  (~(get by p.last) 'content')
      ?~  c  ~
      ?.  ?=([%s *] u.c)  ~
      =/  stream=?
        =/  s=(unit json)  (~(get by p.u.jon) 'stream')
        ?~  s  %.n
        ?.(?=([%b *] u.s) %.n p.u.s)
      `[p.u.m p.u.c stream]
    ::
    ::  Build the non-streaming chat.completion JSON response.
    ++  build-completion-json
      |=  [model=@t content=@t]
      ^-  json
      %-  pairs:enjs:format
      :~  ['id'^s+'chatcmpl-urbit']
          ['object'^s+'chat.completion']
          ['model'^s+model]
          :-  'choices'
          :-  %a
          :~  %-  pairs:enjs:format
              :~  ['index'^(numb:enjs:format 0)]
                  :-  'message'
                  %-  pairs:enjs:format
                  :~  ['role'^s+'assistant']
                      ['content'^s+content]
                  ==
                  ['finish_reason'^s+'stop']
              ==
          ==
      ==
    ::
    ::  Build the SSE body: one delta chunk with full content + [DONE].
    ++  build-sse-body
      |=  [model=@t content=@t]
      ^-  @t
      =/  delta-jon=json
        %-  pairs:enjs:format
        :~  ['object'^s+'chat.completion.chunk']
            ['model'^s+model]
            :-  'choices'
            :-  %a
            :~  %-  pairs:enjs:format
                :~  ['index'^(numb:enjs:format 0)]
                    :-  'delta'
                    %-  pairs:enjs:format
                    :~  ['content'^s+content]
                    ==
                ==
            ==
        ==
      =/  delta-body=@t  (en:json:html delta-jon)
      (rap 3 ~['data: ' delta-body '\0a\0a' 'data: [DONE]\0a\0a'])
    ::
    ::  Build OpenAI-format /v1/models response.
    ++  build-models-response
      |=  models=(list @t)
      ^-  json
      %-  pairs:enjs:format
      :~  ['object'^s+'list']
          :-  'data'
          :-  %a
          %+  turn  models
          |=  m=@t
          ^-  json
          %-  pairs:enjs:format
          :~  ['id'^s+m]
              ['object'^s+'model']
              ['owned_by'^s+'urbit']
          ==
      ==
    ::
    ++  sse-cards
      |=  [eyre-id=@ta body=@t]
      ^-  (list card)
      =/  pat=(pole @ta)  /http-response/[eyre-id]
      =/  hdr=response-header:http
        :-  200
        :~  ['content-type'^'text/event-stream']
            ['cache-control'^'no-cache']
        ==
      :~  [%give %fact ~[pat] %http-response-header !>(hdr)]
          [%give %fact ~[pat] %http-response-data !>(`(unit octs)``[(met 3 body) body])]
          [%give %fact ~[pat] %http-response-data !>(`(unit octs)`~)]
          [%give %kick ~[pat] ~]
      ==
    --
::
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  :_  this(state [%0 0 our.bowl ~['llama3.1:8b'] ~])
  [%pass /bind %arvo %e %connect [~ /llmproxy] dap.bowl]~
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  loaded  (mole |.(!<(state-0 vase)))
  ?~  loaded
    ~&  >>  %llmproxy-shim-reset-state
    on-init
  `this(state u.loaded)
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+    mark  (on-poke:def mark vase)
      %noun
    =/  cmd  !<(?([%set-node target=@p] [%set-models ms=(list @t)]) vase)
    ?-    -.cmd
        %set-node    `this(node target.cmd)
        %set-models  `this(models ms.cmd)
    ==
  ::
      %handle-http-request
    =+  !<([eyre-id=@ta =inbound-request:eyre] vase)
    =/  =request:http  request.inbound-request
    =/  rl  (parse-request-line:server url.request)
    ::  GET /llmproxy/v1/models
    ?:  ?&  ?=(%'GET' method.request)
            ?=([%llmproxy %v1 %models ~] site.rl)
        ==
      :_  this
      %+  give-simple-payload:app:server  eyre-id
      (json-response:gen:server (build-models-response models.state))
    ::  POST /llmproxy/v1/chat/completions
    ?:  ?&  ?=(%'POST' method.request)
            ?=([%llmproxy %v1 %chat %completions ~] site.rl)
        ==
      =/  body=@t
        ?~  body.request  ''
        q.u.body.request
      =/  parsed  (parse-openai-request body)
      ?~  parsed
        :_  this
        (give-simple-payload:app:server eyre-id [[400 ~] `(as-octs:mimes:html '{"error":"bad request"}')])
      =/  n=@ud  +(nonce.state)
      =/  jid=job-id:llmproxy  [our.bowl now.bowl n]
      =/  jr=job-req:llmproxy  [jid model.u.parsed prompt.u.parsed]
      =/  pat=path  /job/(scot %ud n)
      :_  %=  this
              nonce    n
              pending  (~(put by pending.state) n [eyre-id model.u.parsed stream.u.parsed])
          ==
      :~  [%pass /poke/(scot %ud n) %agent [node.state %llmproxy-node] %poke %llmproxy-job !>(jr)]
          [%pass /watch/(scot %ud n) %agent [node.state %llmproxy-node] %watch pat]
      ==
    ::  Anything else: 404
    :_  this
    (give-simple-payload:app:server eyre-id [[404 ~] `(as-octs:mimes:html '{"error":"not found"}')])
  ==
::
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?:  ?=([%http-response *] path)  `this
  (on-watch:def path)
::
++  on-agent
  |=  [=wire =sign:agent:gall]
  ^-  (quip card _this)
  ?+    wire  (on-agent:def wire sign)
      [%poke @ ~]
    ?+  -.sign  (on-agent:def wire sign)
        %poke-ack
      ?~  p.sign  `this
      ~&  >>>  [%shim-poke-failed u.p.sign]
      `this
    ==
  ::
      [%watch @ ~]
    =/  n=@ud  (slav %ud i.t.wire)
    ?+    -.sign  (on-agent:def wire sign)
        %watch-ack
      ?~  p.sign  `this
      ~&  >>>  [%shim-watch-failed u.p.sign]
      =/  rec  (~(get by pending.state) n)
      ?~  rec  `this
      :_  this(pending (~(del by pending.state) n))
      (give-simple-payload:app:server eyre-id.u.rec [[502 ~] `(as-octs:mimes:html '{"error":"node unreachable"}')])
    ::
        %kick
      `this
    ::
        %fact
      ?+  p.cage.sign  `this
          %llmproxy-token
        =/  tc  !<(token-chunk:llmproxy q.cage.sign)
        =/  rec  (~(get by pending.state) n)
        ?~  rec  `this
        =/  eid=@ta  eyre-id.u.rec
        ::  Final fact only fires once with done=%.y. Build the response.
        ?.  done.tc  `this
        =/  cards=(list card)
          ?:  stream.u.rec
            (sse-cards eid (build-sse-body model.u.rec text.tc))
          (give-simple-payload:app:server eid (json-response:gen:server (build-completion-json model.u.rec text.tc)))
        =/  leave-card=card
          [%pass /watch/(scot %ud n) %agent [node.state %llmproxy-node] %leave ~]
        :_  this(pending (~(del by pending.state) n))
        [leave-card cards]
      ==
    ==
  ==
::
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ?:  ?=([%bind ~] wire)
    ?>  ?=([%eyre %bound *] sign-arvo)
    `this
  (on-arvo:def wire sign-arvo)
::
++  on-leave  on-leave:def
++  on-peek   on-peek:def
++  on-fail   on-fail:def
--
