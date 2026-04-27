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
/+  default-agent, server, *llmproxy-helpers
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
      backend-key=@t
      client-api-token=@t
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
    ::  Pure helpers (parse-openai-request, build-completion-json,
    ::  build-sse-body, build-models-response, parse-form-body, trim-spaces,
    ::  csv-to-list, list-to-csv, ships-to-csv, get-header, bearer-ok,
    ::  derive-api-base, policy-mode-text, policy-ships-csv) live in
    ::  /lib/llmproxy-helpers.hoon and are imported via /+ above.
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
              backend-key-set=?
              client-api-token-set=?
              hosting=?
          ==
      ^-  (list card)
      =/  poke-card=card
        [%pass /set-policy %agent [our %llmproxy-node] %poke %noun !>([%set-policy new-pol])]
      =/  http-cards
        %+  give-simple-payload:app:server  eid
        (manx-response (ui-page our publisher api-base node models backend backend-key-set client-api-token-set new-pol hosting 'policy updated' '' ''))
      [poke-card http-cards]
    ::
    ::  Build the config UI page.
    ++  ui-page
      |=  $:  our=@p
              publisher=@p
              api-base=@t
              node=@p
              models=(list @t)
              backend=@t
              backend-key-set=?
              client-api-token-set=?
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
      =/  example-model-cord=@t
        ?~(models 'llama3.1:8b' i.models)
      =/  example-json-cord=@t
        %+  rap  3
        :~  '{"model":"'
            example-model-cord
            '","messages":[{"role":"user","content":"hello"}]}'
        ==
      =/  auth-line-cord=@t
        ?:  client-api-token-set
          ' \\\0a  -H "Authorization: Bearer YOUR_TOKEN"'
        ''
      =/  curl-example=tape
        %-  trip
        %+  rap  3
        :~  'curl -X POST '
            api-base
            '/v1/chat/completions \\\0a  -H "content-type: application/json"'
            auth-line-cord
            ' \\\0a  -d \''
            example-json-cord
            '\''
        ==
      =/  msg-text=tape  (trip msg)
      =/  css=tape
        """
        body \{font-family:-apple-system,system-ui,sans-serif;max-width:680px;margin:2em auto;padding:0 1em;color:#222;line-height:1.5}
        h1 \{color:#444;border-bottom:1px solid #ccc;padding-bottom:.3em;margin-bottom:.4em}
        h2 \{color:#444;font-size:1.25em;margin-top:2.2em;margin-bottom:.3em;border-bottom:1px solid #ececec;padding-bottom:.2em}
        h3 \{color:#666;font-size:1em;margin-top:1.6em;margin-bottom:.2em;text-transform:uppercase;letter-spacing:.06em;font-weight:600}
        details \{margin:1.5em 0}
        summary \{color:#444;font-size:1.25em;font-weight:600;cursor:pointer;padding:.4em 0;border-bottom:1px solid #ececec;list-style-position:outside;user-select:none}
        summary:hover \{color:#3aa37a}
        details[open] > summary \{margin-bottom:.6em}
        .topo \{display:flex;align-items:stretch;gap:.5em;padding:1em;background:#f0f6f3;border:1px solid #d8e8e0;border-radius:6px;margin:1em 0;font-size:.9em;flex-wrap:wrap}
        .topo-box \{flex:1;min-width:8em;background:#fff;padding:.6em;border:1px solid #d8e8e0;border-radius:4px;text-align:center}
        .topo-box.you \{border-color:#3aa37a;background:#f0fdf4}
        .topo-box.backend \{border-color:#b54a4a;background:#fef2f2}
        .topo-box.client \{border-color:#4a7bb5;background:#e8f1fb}
        .topo-box small \{display:block;font-size:.78em;color:#666;margin-top:.2em;font-family:ui-monospace,Menlo,monospace;word-break:break-all}
        .topo-box .role \{display:block;color:#888;font-size:.7em;text-transform:uppercase;letter-spacing:.05em;margin-top:.3em}
        .topo-arrow \{display:flex;flex-direction:column;align-items:center;justify-content:center;color:#3aa37a;font-size:1.5em;font-weight:bold;line-height:1}
        .topo-arrow small \{display:block;text-align:center;font-size:.45em;color:#666;font-weight:normal;letter-spacing:.05em;margin-top:.3em}
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
          ;details(open "")
            ;summary: Use as a client
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
            ;dt: api token
            ;dd:"{?:(client-api-token-set "(set — clients must send Authorization: Bearer <token>)" "(none — endpoint is open to anyone who can reach the URL)")}"
          ==
          ;div(class "topo")
            ;div(class "topo-box client")
              ;b: OpenAI clients
              ;br;
              ;small: Continue.dev
              ;br;
              ;small: OpenCode
              ;br;
              ;small: AtomicChat
              ;br;
              ;small: curl, etc.
            ==
            ;span(class "topo-arrow")
              ;span:"→"
              ;small: HTTP
            ==
            ;div(class "topo-box you")
              ;b: this ship
              ;br;
              ;small:"{our-text}"
              ;span(class "role"):"{?:(=(node our) "shim + node" "shim only")}"
            ==
            ;*  ?:  =(node our)  ~
                :~  ;span(class "topo-arrow")
                      ;span:"→"
                      ;small: Ames
                    ==
                    ;div(class "topo-box")
                      ;b: node
                      ;br;
                      ;small:"{ship-text}"
                      ;span(class "role"): node + backend
                    ==
                ==
            ;span(class "topo-arrow")
              ;span:"→"
              ;small: HTTP
            ==
            ;div(class "topo-box backend")
              ;b: backend
              ;br;
              ;small: OpenAI-compatible
              ;span(class "role"): inference server
            ==
          ==
          ;p
            ;small: Example
          ==
          ;pre(id "curl-ex"):"{curl-example}"
          ;button(type "button", onclick "navigator.clipboard.writeText(document.getElementById('curl-ex').textContent);this.textContent='copied!';"): copy
          ;form(method "post", action "/llmproxy/ui")
            ;input(type "hidden", name "action", value "set-node");
            ;label: route requests to this ship's %llmproxy-node
            ;br;
            ;input(type "text", name "node", value "{ship-text}", placeholder "~sampel-palnet", size "60");
            ;button(type "submit"): update node
          ==
          ;form(method "post", action "/llmproxy/ui")
            ;label: api token (clients send as Authorization: Bearer ...; leave empty to disable auth)
            ;br;
            ;input(type "password", name "token", placeholder "your-shared-secret", size "60");
            ;br;
            ;button(type "submit", name "action", value "set-client-api-token"): update
            ;button(type "submit", name "action", value "generate-api-token"): generate random
          ==
            ;p
              ;small: Models auto-populate from the node when you change it. To change what's offered, ask the node operator.
            ==
          ==
          ;details(open "")
            ;summary: Test
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
          ==
          ;details
            ;summary: Host a node
            ;p
              ;small: Let other ships connect to your LLM inference.
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
                  ;dt: api key
                  ;dd:"{?:(backend-key-set "(set)" "(none)")}"
                ==
                ;form(method "post", action "/llmproxy/ui")
                  ;input(type "hidden", name "action", value "set-backend");
                  ;label: where your local OpenAI-compatible inference server lives
                  ;br;
                  ;input(type "text", name "backend", value "{backend-text}", placeholder "http://localhost:11434/v1/chat/completions", size "60");
                  ;button(type "submit"): update backend
                ==
                ;form(method "post", action "/llmproxy/ui")
                  ;input(type "hidden", name "action", value "set-backend-key");
                  ;label: api key to send to your local OpenAI-compatible server (leave empty to remove)
                  ;br;
                  ;input(type "password", name "key", placeholder "sk-...", size "60");
                  ;button(type "submit"): update api key
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
                  ;li
                    ;span: On their ship:
                    ;br;
                    ;code:"|install {publisher-text} %llmproxy"
                  ==
                  ;li: Have them point their shim's node at your @p via this same form.
                ==
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
            backend-key=''
            client-api-token=''
            policy=`access-policy:llmproxy`[%whitelist ~]
            hosting=%.n
            pending=~
        ==
      ==
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
      (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state fresh-models backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state '' '' ''))
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
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state 'missing node value' '' ''))
        =/  parsed  (slaw %p u.raw)
        ?~  parsed
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state (cat 3 'invalid @p: ' u.raw) '' ''))
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
        (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base u.parsed fresh-models backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state 'node updated' '' ''))
      ?:  ?&  ?=(^ act)  =('generate-api-token' u.act)  ==
        ::  Eyre intercepts Authorization: Bearer 0v... as a session lookup,
        ::  so prefix with 'sk-' (and drop the 0v) to keep it out of that path.
        =/  new-token=@t
          (cat 3 'sk-' (rsh [3 2] (scot %uv (sham eny.bowl))))
        :_  this(client-api-token new-token)
        %+  give-simple-payload:app:server  eyre-id
        (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) %.y policy.state hosting.state (cat 3 'new api token (copy now, you cannot see it again): ' new-token) '' ''))
      ?:  ?&  ?=(^ act)  =('set-client-api-token' u.act)  ==
        =/  raw  (~(get by fields) 'token')
        =/  tok=@t  ?~(raw '' u.raw)
        :_  this(client-api-token tok)
        %+  give-simple-payload:app:server  eyre-id
        (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' tok) policy.state hosting.state ?:(=('' tok) 'api token disabled' 'api token set') '' ''))
      ?:  ?&  ?=(^ act)  =('set-backend-key' u.act)  ==
        =/  raw  (~(get by fields) 'key')
        =/  key=@t  ?~(raw '' u.raw)
        =/  poke-card=card
          [%pass /set-backend-key %agent [our.bowl %llmproxy-node] %poke %noun !>([%set-backend-key key])]
        =/  http-cards
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' key) !=('' client-api-token.state) policy.state hosting.state ?:(=('' key) 'api key removed' 'api key updated') '' ''))
        :_  this(backend-key key)
        [poke-card http-cards]
      ?:  ?&  ?=(^ act)  =('refresh-models' u.act)  ==
        =/  poke-card=card
          [%pass /refresh-models %agent [our.bowl %llmproxy-node] %poke %noun !>([%refresh-models ~])]
        =/  http-cards
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state 'refreshing models from backend...' '' ''))
        :_  this
        [poke-card http-cards]
      ?:  ?&  ?=(^ act)  =('set-backend' u.act)  ==
        =/  raw  (~(get by fields) 'backend')
        ?:  |(?=(~ raw) =('' u.raw))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state 'missing backend url' '' ''))
        =/  poke-card=card
          [%pass /set-backend %agent [our.bowl %llmproxy-node] %poke %noun !>([%set-backend u.raw])]
        =/  http-cards
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state u.raw !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state 'backend updated' '' ''))
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
          !=('' backend-key.state)
          !=('' client-api-token.state)
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
        (policy-cards our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base eyre-id np node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) hosting.state)
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
        (policy-cards our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base eyre-id np node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) hosting.state)
      ?:  ?&  ?=(^ act)  =('test' u.act)  ==
        =/  prompt-raw  (~(get by fields) 'prompt')
        =/  model-raw  (~(get by fields) 'model')
        ?:  |(?=(~ prompt-raw) =('' u.prompt-raw))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state 'enter a prompt to test' '' ''))
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
      (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state 'unknown action' '' ''))
    ::  GET /llmproxy/v1/models
    ?:  ?&  ?=(%'GET' method.request)
            ?=([%llmproxy %v1 %models ~] site.rl)
        ==
      ?.  (bearer-ok client-api-token.state header-list.request)
        :_  this
        (give-simple-payload:app:server eyre-id [[401 ~] `(as-octs:mimes:html '{"error":"unauthorized: invalid or missing Bearer token"}')])
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
      ?.  (bearer-ok client-api-token.state header-list.request)
        :_  this
        (give-simple-payload:app:server eyre-id [[401 ~] `(as-octs:mimes:html '{"error":"unauthorized: invalid or missing Bearer token"}')])
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
              !=('' backend-key.state)
              !=('' client-api-token.state)
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
