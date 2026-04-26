::  %llmproxy-shim: OpenAI-compatible HTTP gateway.
::
::  Endpoints:
::    GET  /llmproxy/v1/models           list configured models
::    POST /llmproxy/v1/chat/completions chat (honors `stream` field)
::
::  Streaming caveat: returns properly-formed SSE when stream=true, but
::  Iris buffers the full Ollama response so all chunks arrive at once.
::
/-  llmproxy, hood
/+  default-agent, server
::
|%
+$  card  card:agent:gall
+$  pending-shim
  $:  eyre-id=@ta
      model=@t
      stream=?
      kind=?(%openai %test)
      prompt=@t
      api-base=@t
  ==
+$  state-0
  $:  %0
      nonce=@ud
      node=@p
      models=(list @t)
      backend=@t
      policy=access-policy:llmproxy
      hosting=?
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
    ::
    ::  Parse a url-encoded form body via Eyre's query parser.
    ++  parse-form-body
      |=  body=@t
      ^-  (map @t @t)
      =/  prefixed=@t  (cat 3 '?' body)
      =/  parsed  (rush prefixed yque:de-purl:html)
      ?~  parsed  ~
      (malt u.parsed)
    ::
    ::  Trim leading/trailing spaces from a cord.
    ++  trim-spaces
      |=  t=@t
      ^-  @t
      =/  bytes=(list @)  (rip 3 t)
      =/  front
        |-  ^-  (list @)
        ?~  bytes  ~
        ?:  =(' ' i.bytes)  $(bytes t.bytes)
        bytes
      =/  back
        =/  rev  (flop front)
        |-  ^-  (list @)
        ?~  rev  ~
        ?:  =(' ' i.rev)  $(rev t.rev)
        rev
      (rap 3 (flop back))
    ::
    ::  Split CSV → trimmed list, dropping empties.
    ++  csv-to-list
      |=  csv=@t
      ^-  (list @t)
      =/  bytes=(list @)  (rip 3 csv)
      =|  out=(list @t)
      =|  cur=(list @)
      |-  ^-  (list @t)
      ?~  bytes
        =/  trimmed  (trim-spaces (rap 3 (flop cur)))
        ?:  =('' trimmed)  (flop out)
        (flop [trimmed out])
      ?:  =(',' i.bytes)
        =/  trimmed  (trim-spaces (rap 3 (flop cur)))
        %=  $
            bytes  t.bytes
            cur  ~
            out  ?:(=('' trimmed) out [trimmed out])
        ==
      $(bytes t.bytes, cur [i.bytes cur])
    ::
    ::  Render list of models as comma-separated cord.
    ++  list-to-csv
      |=  ms=(list @t)
      ^-  @t
      ?~  ms  ''
      ?~  t.ms  i.ms
      (rap 3 ~[i.ms ', ' $(ms t.ms)])
    ::
    ::  Derive the public-facing base URL ("http(s)://host/llmproxy") from
    ::  the inbound request, by inspecting the Host header and secure flag.
    ++  derive-api-base
      |=  =inbound-request:eyre
      ^-  @t
      =/  hosts
        %+  skim  header-list.request.inbound-request
        |=  [k=@t v=@t]
        =((cass (trip k)) "host")
      =/  host=@t
        ?~(hosts 'localhost' value.i.hosts)
      =/  scheme=@t
        ?:(secure.inbound-request 'https://' 'http://')
      (rap 3 ~[scheme host '/llmproxy'])
    ::
    ::  Look up which ship we synced the %llmproxy desk from, via kiln/pikes.
    ::  Falls back to our own @p if no sync record is found (e.g. desk was
    ::  authored locally rather than installed from another ship).
    ++  pub-of-llmproxy
      |=  [our=@p now=@da]
      ^-  @p
      =/  scried=(unit pikes:hood)
        %-  mole
        |.
        .^(pikes:hood %gx /(scot %p our)/hood/(scot %da now)/kiln/pikes/noun)
      ?~  scried  our
      =/  pike  (~(get by u.scried) %llmproxy)
      ?~  pike  our
      ?~  sync.u.pike  our
      ship.u.sync.u.pike
    ::
    ::  Build the cards to apply a new policy: poke node, render UI.
    ++  policy-cards
      |=  $:  our=@p
              publisher=@p
              api-base=@t
              eid=@ta
              new-pol=access-policy:llmproxy
              node=@p
              models=(list @t)
              backend=@t
              hosting=?
          ==
      ^-  (list card)
      =/  poke-card=card
        [%pass /set-policy %agent [our %llmproxy-node] %poke %noun !>([%set-policy new-pol])]
      =/  http-cards
        %+  give-simple-payload:app:server  eid
        (manx-response (ui-page our publisher api-base node models backend new-pol hosting 'policy updated' '' ''))
      [poke-card http-cards]
    ::
    ::  Mode label: "whitelist" or "blacklist".
    ++  policy-mode-text
      |=  =access-policy:llmproxy
      ^-  @t
      ?-  -.access-policy
          %whitelist  'whitelist (only listed ships allowed)'
          %blacklist  'blacklist (everyone except listed)'
      ==
    ::
    ::  Comma-separated list of ships in the policy.
    ++  policy-ships-csv
      |=  =access-policy:llmproxy
      ^-  @t
      (ships-to-csv ~(tap in ships.access-policy))
    ::
    ++  ships-to-csv
      |=  ships=(list @p)
      ^-  @t
      ?~  ships  ''
      ?~  t.ships  (scot %p i.ships)
      (rap 3 ~[(scot %p i.ships) ', ' $(ships t.ships)])
    ::
    ::  Build the config UI page.
    ++  ui-page
      |=  $:  our=@p
              publisher=@p
              api-base=@t
              node=@p
              models=(list @t)
              backend=@t
              =access-policy:llmproxy
              hosting=?
              msg=@t
              test-prompt=@t
              test-response=@t
          ==
      ^-  manx
      =/  ship-text=tape  (scow %p node)
      =/  our-text=tape  (scow %p our)
      =/  publisher-text=tape  (scow %p publisher)
      =/  api-base-text=tape  (trip api-base)
      =/  models-text=tape  (trip (list-to-csv models))
      =/  backend-text=tape  (trip backend)
      =/  policy-mode=tape  (trip (policy-mode-text access-policy))
      =/  policy-ships=tape  (trip (policy-ships-csv access-policy))
      =/  toggle-target=@t
        ?-  -.access-policy
            %whitelist  'blacklist'
            %blacklist  'whitelist'
        ==
      =/  toggle-label=tape  (trip (cat 3 'switch to ' toggle-target))
      =/  test-prompt-tape=tape  (trip test-prompt)
      =/  test-response-tape=tape  (trip test-response)
      =/  msg-text=tape  (trip msg)
      =/  css=tape
        """
        body \{font-family:-apple-system,system-ui,sans-serif;max-width:680px;margin:2em auto;padding:0 1em;color:#222;line-height:1.5}
        h1 \{color:#444;border-bottom:1px solid #ccc;padding-bottom:.3em;margin-bottom:.4em}
        h2 \{color:#444;font-size:1.25em;margin-top:2.2em;margin-bottom:.3em;border-bottom:1px solid #ececec;padding-bottom:.2em}
        h3 \{color:#666;font-size:1em;margin-top:1.6em;margin-bottom:.2em;text-transform:uppercase;letter-spacing:.06em;font-weight:600}
        form \{background:#f7f7f5;padding:1em;border-radius:6px;margin:1em 0;border:1px solid #ececec}
        label \{display:block;margin:.5em 0 .2em;font-weight:600;font-size:.9em;color:#555}
        input[type=text],select,textarea \{width:100%;padding:.5em;border:1px solid #ccc;border-radius:4px;box-sizing:border-box;font-family:ui-monospace,Menlo,monospace;font-size:.95em}
        textarea \{resize:vertical;min-height:3em}
        button \{padding:.5em 1.2em;background:#3aa37a;color:#fff;border:0;border-radius:4px;cursor:pointer;font-weight:600;margin-top:.5em;font-size:.95em}
        button:hover \{background:#2e8862}
        button:disabled \{background:#aaa;cursor:wait}
        .msg \{background:#fff7d8;padding:.7em 1em;border-radius:4px;border-left:3px solid #c9a000;margin:1em 0}
        dl \{background:#f7f7f5;padding:1em;border-radius:6px;border:1px solid #ececec;margin:1em 0}
        dt \{font-weight:600;color:#666;font-size:.85em;text-transform:uppercase;letter-spacing:.04em;margin-top:.7em}
        dt:first-child \{margin-top:0}
        dd \{margin:.2em 0 0 0;font-family:ui-monospace,Menlo,monospace;word-break:break-all}
        pre \{background:#f7f7f5;border:1px solid #ececec;border-radius:6px;padding:1em;font-family:ui-monospace,Menlo,monospace;font-size:.92em;white-space:pre-wrap;word-wrap:break-word;max-height:400px;overflow:auto;margin:1em 0}
        small \{color:#888}
        ol li \{margin:.3em 0}
        code \{background:#eee;padding:.05em .35em;border-radius:3px;font-size:.9em;font-family:ui-monospace,Menlo,monospace}
        """
      ;html
        ;head
          ;title: llmproxy config
          ;meta(charset "utf-8");
          ;style:"{css}"
        ==
        ;body
          ;h1: llmproxy
          ;+  ?:  =('' msg)  ;span;
              ;p(class "msg"):"{msg-text}"
          ;h2: Use as a client
          ;p
            ;small: Use the URL below in OpenCode, AtomicChat, or any app that wants an OpenAI-compatible endpoint. Requests are routed through this ship to a node operator's hardware.
          ==
          ;dl
            ;dt: api endpoint
            ;dd:"POST {api-base-text}/v1/chat/completions"
            ;dt: node
            ;dd:"{ship-text}"
            ;dt: models
            ;dd:"{models-text}"
          ==
          ;form(method "post", action "/llmproxy/ui")
            ;input(type "hidden", name "action", value "set-node");
            ;label: route requests to this ship's %llmproxy-node
            ;br;
            ;input(type "text", name "node", value "{ship-text}", placeholder "~sampel-palnet", size "60");
            ;button(type "submit"): update node
          ==
          ;p
            ;small: Models auto-populate from the node when you change it. To change what's offered, ask the node operator.
          ==
          ;h2: Test
          ;p
            ;small: Send a prompt through to confirm the connection works.
          ==
          ;form(method "post", action "/llmproxy/ui", onsubmit "var b=this.querySelector('button');b.disabled=true;b.textContent='waiting for response...';")
            ;input(type "hidden", name "action", value "test");
            ;label: model
            ;br;
            ;select(name "model")
              ;*  %+  turn  models
                  |=  m=@t
                  =/  mt=tape  (trip m)
                  ;option(value "{mt}"):"{mt}"
            ==
            ;label: prompt
            ;br;
            ;textarea(name "prompt", rows "3", cols "60"):"{test-prompt-tape}"
            ;br;
            ;button(type "submit"): send
          ==
          ;+  ?:  =('' test-response)  ;span;
              ;pre:"{test-response-tape}"
          ;h2: Host a node
          ;p
            ;small: Let other ships run inference on your hardware.
          ==
          ;form(method "post", action "/llmproxy/ui")
            ;input(type "hidden", name "action", value "toggle-hosting");
            ;button(type "submit"):"{?:(hosting "turn off hosting" "turn on hosting")}"
          ==
          ;+  ?.  hosting  ;span;
              ;div
                ;dl
                  ;dt: your @p
                  ;dd:"{our-text}"
                  ;dt: ollama backend
                  ;dd:"{backend-text}"
                ==
                ;form(method "post", action "/llmproxy/ui")
                  ;input(type "hidden", name "action", value "set-backend");
                  ;label: where your local OpenAI-compatible inference server lives
                  ;br;
                  ;input(type "text", name "backend", value "{backend-text}", placeholder "http://localhost:11434/v1/chat/completions", size "60");
                  ;button(type "submit"): update backend
                ==
                ;form(method "post", action "/llmproxy/ui")
                  ;input(type "hidden", name "action", value "refresh-models");
                  ;p
                    ;small: Models are auto-discovered from your backend's /v1/models endpoint when you change the backend URL. Click below if your backend's model list has changed.
                  ==
                  ;button(type "submit"): refresh models from backend
                ==
                ;h3: Access permissions
                ;p
                  ;small: Decide which ships are allowed to submit jobs to your node. Your own ship is always allowed.
                ==
                ;dl
                  ;dt: mode
                  ;dd:"{policy-mode}"
                  ;dt: ships
                  ;dd:"{policy-ships}"
                ==
                ;form(method "post", action "/llmproxy/ui")
                  ;input(type "hidden", name "action", value "toggle-policy-mode");
                  ;button(type "submit"):"{toggle-label}"
                ==
                ;form(method "post", action "/llmproxy/ui")
                  ;input(type "hidden", name "action", value "set-policy-ships");
                  ;label: ships (comma-separated @ps; replaces the whole list)
                  ;br;
                  ;input(type "text", name "ships", value "{policy-ships}", placeholder "~zod, ~nec", size "60");
                  ;button(type "submit"): update ships
                ==
                ;p: To invite a friend:
                ;ol
                  ;li: Send them your @p above.
                  ;li:"On their ship: |install {publisher-text} %llmproxy"
                  ;li: Have them point their shim's node at your @p via this same form.
                ==
              ==
          ;p
            ;small: %llmproxy-shim
          ==
        ==
      ==
    ::
    ::  Convert a manx to an HTTP 200 text/html simple-payload.
    ++  manx-response
      |=  m=manx
      ^-  simple-payload:http
      =/  body=@t  (crip (en-xml:html m))
      :_  `[(met 3 body) body]
      [200 ~[['content-type'^'text/html; charset=utf-8']]]
    --
::
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  :_  %=  this
          state
        :*  %0
            nonce=0
            node=our.bowl
            models=~
            backend='http://localhost:11434/v1/chat/completions'
            policy=`access-policy:llmproxy`[%whitelist ~]
            hosting=%.n
            pending=~
        ==
      ==
  :~  [%pass /bind %arvo %e %connect [~ /llmproxy] dap.bowl]
      [%pass /models %agent [our.bowl %llmproxy-node] %watch /models]
  ==
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
  ::  Re-emit /models watch so we get the current list. (Cheap: leaving
  ::  a non-existent sub is a no-op; this handles the install-time race
  ::  where shim started watching before the node was up.)
  :_  this(state u.loaded)
  :~  [%pass /models %agent [node.u.loaded %llmproxy-node] %leave ~]
      [%pass /models %agent [node.u.loaded %llmproxy-node] %watch /models]
  ==
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
    =/  api-base=@t  (derive-api-base inbound-request)
    ::  GET /llmproxy/ui — config page
    ?:  ?&  ?=(%'GET' method.request)
            ?=([%llmproxy %ui ~] site.rl)
        ==
      =/  fresh-models=(list @t)
        ?.  =(node.state our.bowl)  models.state
        =/  scried=(unit (list @t))
          %-  mole
          |.
          .^  (list @t)  %gx
              /(scot %p our.bowl)/llmproxy-node/(scot %da now.bowl)/advertised/noun
          ==
        ?~(scried models.state u.scried)
      :_  this(models fresh-models)
      %+  give-simple-payload:app:server  eyre-id
      (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state fresh-models backend.state policy.state hosting.state '' '' ''))
    ::
    ::  POST /llmproxy/ui — handle config form submissions
    ?:  ?&  ?=(%'POST' method.request)
            ?=([%llmproxy %ui ~] site.rl)
        ==
      =/  body=@t
        ?~  body.request  ''
        q.u.body.request
      =/  fields  (parse-form-body body)
      =/  act  (~(get by fields) 'action')
      ?:  ?&  ?=(^ act)  =('set-node' u.act)  ==
        =/  raw  (~(get by fields) 'node')
        ?:  |(?=(~ raw) =('' u.raw))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state policy.state hosting.state 'missing node value' '' ''))
        =/  parsed  (slaw %p u.raw)
        ?~  parsed
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state policy.state hosting.state (cat 3 'invalid @p: ' u.raw) '' ''))
        =/  resub-cards=(list card)
          :~  [%pass /models %agent [node.state %llmproxy-node] %leave ~]
              [%pass /models %agent [u.parsed %llmproxy-node] %watch /models]
          ==
        ::  For local node, scry the node's current advertised list synchronously
        ::  so the response page renders with fresh models. For remote nodes the
        ::  cache holds whatever was last known until the new subscription fires.
        =/  fresh-models=(list @t)
          ?.  =(u.parsed our.bowl)  models.state
          =/  scried=(unit (list @t))
            %-  mole
            |.
            .^  (list @t)  %gx
                /(scot %p our.bowl)/llmproxy-node/(scot %da now.bowl)/advertised/noun
            ==
          ?~(scried models.state u.scried)
        :_  this(node u.parsed, models fresh-models)
        %+  weld  resub-cards
        %+  give-simple-payload:app:server  eyre-id
        (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base u.parsed fresh-models backend.state policy.state hosting.state 'node updated' '' ''))
      ?:  ?&  ?=(^ act)  =('refresh-models' u.act)  ==
        =/  poke-card=card
          [%pass /refresh-models %agent [our.bowl %llmproxy-node] %poke %noun !>([%refresh-models ~])]
        =/  http-cards
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state policy.state hosting.state 'refreshing models from backend...' '' ''))
        :_  this
        [poke-card http-cards]
      ?:  ?&  ?=(^ act)  =('set-backend' u.act)  ==
        =/  raw  (~(get by fields) 'backend')
        ?:  |(?=(~ raw) =('' u.raw))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state policy.state hosting.state 'missing backend url' '' ''))
        =/  poke-card=card
          [%pass /set-backend %agent [our.bowl %llmproxy-node] %poke %noun !>([%set-backend u.raw])]
        =/  http-cards
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state u.raw policy.state hosting.state 'backend updated' '' ''))
        :_  this(backend u.raw)
        [poke-card http-cards]
      ?:  ?&  ?=(^ act)  =('toggle-hosting' u.act)  ==
        =/  new-hosting=?  !hosting.state
        :_  this(hosting new-hosting)
        %+  give-simple-payload:app:server  eyre-id
        %-  manx-response
        %:  ui-page
          our.bowl
          (pub-of-llmproxy our.bowl now.bowl)
          api-base
          node.state
          models.state
          backend.state
          policy.state
          new-hosting
          ?:(new-hosting 'hosting on' 'hosting off')
          ''
          ''
        ==
      ?:  ?&  ?=(^ act)  =('toggle-policy-mode' u.act)  ==
        =/  np=access-policy:llmproxy
          ?-  -.policy.state
              %whitelist  [%blacklist ships.policy.state]
              %blacklist  [%whitelist ships.policy.state]
          ==
        :_  this(policy np)
        (policy-cards our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base eyre-id np node.state models.state backend.state hosting.state)
      ?:  ?&  ?=(^ act)  =('set-policy-ships' u.act)  ==
        =/  raw  (~(get by fields) 'ships')
        =/  ship-strs=(list @t)
          ?~  raw  ~
          (csv-to-list u.raw)
        =/  ships=(set @p)
          %-  silt
          (murn ship-strs |=(s=@t (slaw %p s)))
        =/  np=access-policy:llmproxy
          ?-  -.policy.state
              %whitelist  [%whitelist ships]
              %blacklist  [%blacklist ships]
          ==
        :_  this(policy np)
        (policy-cards our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base eyre-id np node.state models.state backend.state hosting.state)
      ?:  ?&  ?=(^ act)  =('test' u.act)  ==
        =/  prompt-raw  (~(get by fields) 'prompt')
        =/  model-raw  (~(get by fields) 'model')
        ?:  |(?=(~ prompt-raw) =('' u.prompt-raw))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state policy.state hosting.state 'enter a prompt to test' '' ''))
        =/  model=@t
          ?~  model-raw
            ?~  models.state  'llama3.1:8b'
            i.models.state
          u.model-raw
        =/  n=@ud  +(nonce.state)
        =/  jid=job-id:llmproxy  [our.bowl now.bowl n]
        =/  jr=job-req:llmproxy  [jid model u.prompt-raw]
        =/  pat=path  /job/(scot %ud n)
        :_  %=  this
                nonce    n
                pending  (~(put by pending.state) n [eyre-id model %.n %test u.prompt-raw api-base])
            ==
        :~  [%pass /poke/(scot %ud n) %agent [node.state %llmproxy-node] %poke %llmproxy-job !>(jr)]
            [%pass /watch/(scot %ud n) %agent [node.state %llmproxy-node] %watch pat]
        ==
      :_  this
      %+  give-simple-payload:app:server  eyre-id
      (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state policy.state hosting.state 'unknown action' '' ''))
    ::  GET /llmproxy/v1/models
    ?:  ?&  ?=(%'GET' method.request)
            ?=([%llmproxy %v1 %models ~] site.rl)
        ==
      =/  fresh-models=(list @t)
        ?.  =(node.state our.bowl)  models.state
        =/  scried=(unit (list @t))
          %-  mole
          |.
          .^  (list @t)  %gx
              /(scot %p our.bowl)/llmproxy-node/(scot %da now.bowl)/advertised/noun
          ==
        ?~(scried models.state u.scried)
      :_  this(models fresh-models)
      %+  give-simple-payload:app:server  eyre-id
      (json-response:gen:server (build-models-response fresh-models))
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
              pending  (~(put by pending.state) n [eyre-id model.u.parsed stream.u.parsed %openai prompt.u.parsed api-base])
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
      [%models ~]
    ?+    -.sign  (on-agent:def wire sign)
        %watch-ack
      ?~  p.sign  `this
      ~&  >>>  [%shim-models-watch-failed u.p.sign]
      `this
    ::
        %kick
      ::  Resubscribe.
      :_  this
      [%pass /models %agent [node.state %llmproxy-node] %watch /models]~
    ::
        %fact
      ?+  p.cage.sign  `this
          %llmproxy-models
        =/  ms  !<((list @t) q.cage.sign)
        `this(models ms)
      ==
    ==
  ::
      [%poke @ ~]
    ?+  -.sign  (on-agent:def wire sign)
        %poke-ack
      ?~  p.sign  `this
      =/  n=@ud  (slav %ud i.t.wire)
      =/  rec  (~(get by pending.state) n)
      ?~  rec  `this
      :_  this(pending (~(del by pending.state) n))
      %+  weld
        ~[[%pass /watch/(scot %ud n) %agent [node.state %llmproxy-node] %leave ~]]
      (give-simple-payload:app:server eyre-id.u.rec [[403 ~] `(as-octs:mimes:html '{"error":"poke rejected by node (likely access policy)"}')])
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
          ?-    kind.u.rec
              %openai
            ?:  stream.u.rec
              (sse-cards eid (build-sse-body model.u.rec text.tc))
            (give-simple-payload:app:server eid (json-response:gen:server (build-completion-json model.u.rec text.tc)))
          ::
              %test
            %+  give-simple-payload:app:server  eid
            %-  manx-response
            %:  ui-page
              our.bowl
              (pub-of-llmproxy our.bowl now.bowl)
              api-base.u.rec
              node.state
              models.state
              backend.state
              policy.state
              hosting.state
              'test response below'
              prompt.u.rec
              text.tc
            ==
          ==
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
