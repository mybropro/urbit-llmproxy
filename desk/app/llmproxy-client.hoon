::  %llmproxy-client: OpenAI-compatible HTTP gateway + Ames client.
::
::  Endpoints:
::    GET  /llmproxy/v1/models           list configured models
::    POST /llmproxy/v1/chat/completions chat (honors `stream` field)
::    GET  /llmproxy/ui                  config page
::
::  Streaming caveat: returns properly-formed SSE when stream=true, but
::  Iris buffers the full backend response so all chunks arrive at once.
::
::  Dojo:
::    :llmproxy-client &noun [%ask ~target-ship 'model' 'prompt']
::  Pokes the named node, watches /job/<nonce>, prints the response.
::
/-  llmproxy, hood
/+  default-agent, server, *llmproxy-helpers
::
|%
+$  card  card:agent:gall
+$  pending-client
  $:  eyre-id=@ta
      target=@p
      model=@t
      stream=?
      kind=?(%openai %test %dojo %agent)
      prompt=@t
      api-base=@t
      ::  caller's request id, set only for kind=%agent (the /ask-result/[id]
      ::  path we answer on); '' for the http/test/dojo paths.
      ask-id=@ta
      ::  wall-clock submit time, for telemetry latency. (added in state-1)
      started=@da
  ==
::  Older pending-client shape (pre-telemetry), kept for state-0
::  deserialization — matches main's shipped state-0 pending-client exactly.
+$  pending-client-0
  $:  eyre-id=@ta
      target=@p
      model=@t
      stream=?
      kind=?(%openai %test %dojo %agent)
      prompt=@t
      api-base=@t
      ask-id=@ta
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
      pending=(map @ud pending-client-0)
      pending-config=(map @ud [eyre-id=@ta api-base=@t])
  ==
+$  state-1
  $:  %1
      nonce=@ud
      node=@p
      models=(list @t)
      backend=@t
      backend-key=@t
      client-api-token=@t
      policy=access-policy:llmproxy
      hosting=?
      pending=(map @ud pending-client)
      ::  HTTP form-submit eyre-ids parked here waiting for a /models fact
      ::  after a backend/key change. Drained in on-agent when the fact
      ::  arrives; drained in on-arvo /config-timeout when behn fires first.
      ::  api-base captured at submit time so the deferred response can
      ::  render the same external URL the user originally hit.
      pending-config=(map @ud [eyre-id=@ta api-base=@t])
      ::  Last N HTTP requests received on /llmproxy/v1/*, newest-first.
      ::  Surfaced in the UI and via scry for debugging.
      telemetry=(list client-telemetry-entry:llmproxy)
  ==
::  Union of every state shape this agent has ever shipped. on-load casts
::  the persisted state to this and migrates forward to the current shape.
::  RULE: once a version ships, freeze its +$; any shape change adds a new
::  +$ state-N (with a fresh %N tag) and a migration arm in on-load. Never
::  reshape a tagged version in place — that breaks the cast on upgrade.
+$  versioned-state  $%(state-0 state-1)
++  telemetry-cap  20
--
::
=|  state-1
=*  state  -
::
=>  |%
    ::  Pure helpers (parse-openai-request, build-test-body,
    ::  build-sse-body, build-models-response, extract-content,
    ::  parse-form-body, trim-spaces, csv-to-list, list-to-csv,
    ::  ships-to-csv, get-header, bearer-ok, derive-api-base,
    ::  policy-mode-text, policy-ships-csv) live in
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
    ::  Scry the local llmproxy-node for its telemetry buffer. Returns
    ::  empty when hosting is off (the node may not be useful state) or
    ::  on scry failure (cold start, agent not yet booted).
    ++  scry-node-telemetry
      |=  [our=@p now=@da hosting=?]
      ^-  (list node-telemetry-entry:llmproxy)
      ?.  hosting  ~
      =/  scried=(unit (list node-telemetry-entry:llmproxy))
        %-  mole
        |.
        .^  (list node-telemetry-entry:llmproxy)  %gx
            /(scot %p our)/llmproxy-node/(scot %da now)/telemetry/noun
        ==
      ?~(scried ~ u.scried)
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
              now=@da
              client-telemetry=(list client-telemetry-entry:llmproxy)
          ==
      ^-  (list card)
      =/  poke-card=card
        [%pass /set-policy %agent [our %llmproxy-node] %poke %noun !>([%set-policy new-pol])]
      =/  node-tel  (scry-node-telemetry our now hosting)
      =/  http-cards
        %+  give-simple-payload:app:server  eid
        (manx-response (ui-page our publisher api-base node models backend backend-key-set client-api-token-set new-pol hosting now client-telemetry node-tel 'policy updated' '' ''))
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
              now=@da
              client-telemetry=(list client-telemetry-entry:llmproxy)
              node-telemetry=(list node-telemetry-entry:llmproxy)
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
        .topo-box \{flex:1 1 6em;min-width:6em;background:#fff;padding:.6em;border:1px solid #d8e8e0;border-radius:4px;text-align:center}
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
        .tel-table \{width:100%;border-collapse:collapse;font-size:.82em;font-family:ui-monospace,Menlo,monospace;margin:.4em 0 1.2em 0;display:block;overflow-x:auto}
        .tel-table th, .tel-table td \{padding:.3em .55em;border-bottom:1px solid #ececec;text-align:left;white-space:nowrap}
        .tel-table th \{color:#666;font-weight:600;text-transform:uppercase;font-size:.78em;letter-spacing:.05em;background:#f7f7f5}
        .tel-table tbody tr:hover \{background:#fafaf8}
        .tel-ok \{color:#3aa37a}
        .tel-err \{color:#b54a4a}
        .tel-empty \{color:#888;font-style:italic;margin:.4em 0}
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
            ;dd(class "api-base"):"POST {api-base-text}/v1/chat/completions"
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
              ;span(class "role"):"{?:(=(node our) "client + node" "client only")}"
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
          ;*  ?~  models
                :~  ;p(class "msg")
                      ;small: No models advertised yet. The node may not be reachable, or hosting is off.
                    ==
                ==
              :~  ;p
                    ;small: Example
                  ==
                  ;pre(id "curl-ex", class "api-base"):"{curl-example}"
                  ;button(type "button", onclick "navigator.clipboard.writeText(document.getElementById('curl-ex').textContent);this.textContent='copied!';"): copy
              ==
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
                  ;input(type "hidden", name "action", value "set-backend-and-key");
                  ;label: where your local OpenAI-compatible inference server lives
                  ;br;
                  ;input(type "text", name "backend", value "{backend-text}", placeholder "http://localhost:11434/v1/chat/completions", size "60");
                  ;br;
                  ;label: api key to send to your local OpenAI-compatible server (leave empty to keep current)
                  ;br;
                  ;input(type "password", name "key", placeholder "sk-...", size "60");
                  ;br;
                  ;label
                    ;input(type "checkbox", name "clear-key", value "1");
                    ;span: remove existing api key
                  ==
                  ;br;
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
                  ;li
                    ;span: On their ship:
                    ;br;
                    ;code:"|install {publisher-text} %llmproxy"
                  ==
                  ;li: Have them point their %llmproxy-client's node at your @p via this same form.
                ==
              ==
          ==
          ;details
            ;summary: Telemetry
            ;p
              ;small: Last 20 requests on each side, newest first. Reload to refresh. Bodies, prompts, and tokens are never recorded.
            ==
            ;h3: Client (HTTP requests this ship received)
            ;+  ?:  =(~ client-telemetry)
                  ;p(class "tel-empty"): no requests recorded yet
                ;table(class "tel-table")
                  ;thead
                    ;tr
                      ;th: age
                      ;th: endpoint
                      ;th: target
                      ;th: model
                      ;th: stream
                      ;th: auth
                      ;th: status
                      ;th: ms
                      ;th: resp
                    ==
                  ==
                  ;tbody
                    ;*  %+  turn  client-telemetry
                        |=  e=client-telemetry-entry:llmproxy
                        =/  st=tape  ?:(?=(%ok status.e) "tel-ok" "tel-err")
                        ;tr
                          ;td:"{(trip (format-age now time.e))}"
                          ;td:"{(trip `@t`endpoint.e)}"
                          ;td:"{(scow %p target.e)}"
                          ;td:"{(trip model.e)}"
                          ;td:"{?:(stream.e "yes" "no")}"
                          ;td:"{(trip (authed-text authed.e))}"
                          ;td(class "{st}"):"{(trip (client-status-text status.e))}"
                          ;td:"{(trip (format-ms latency-ms.e))}"
                          ;td:"{(trip (format-bytes resp-bytes.e))}"
                        ==
                  ==
                ==
            ;+  ?.  hosting  ;span;
                ;div
                  ;h3: Node (jobs this ship's node served)
                  ;p
                    ;small: Denied requests are not recorded — the denial path nacks the poke before state is written. They appear as "node rejected" entries in the client table on the requesting ship.
                  ==
                  ;+  ?:  =(~ node-telemetry)
                        ;p(class "tel-empty"): no jobs recorded yet
                      ;table(class "tel-table")
                        ;thead
                          ;tr
                            ;th: age
                            ;th: src
                            ;th: model
                            ;th: status
                            ;th: code
                            ;th: ms
                            ;th: req
                            ;th: resp
                          ==
                        ==
                        ;tbody
                          ;*  %+  turn  node-telemetry
                              |=  e=node-telemetry-entry:llmproxy
                              =/  st=tape  ?:(?=(%ok status.e) "tel-ok" "tel-err")
                              ;tr
                                ;td:"{(trip (format-age now time.e))}"
                                ;td:"{(scow %p src.e)}"
                                ;td:"{(trip model.e)}"
                                ;td(class "{st}"):"{(trip (node-status-text status.e))}"
                                ;td:"{(scow %ud http-code.e)}"
                                ;td:"{(trip (format-ms latency-ms.e))}"
                                ;td:"{(trip (format-bytes req-bytes.e))}"
                                ;td:"{(trip (format-bytes resp-bytes.e))}"
                              ==
                        ==
                      ==
                ==
          ==
          ;p
            ;small: %llmproxy-client
          ==
          ;script:"(function()\{var loc=window.location.origin;var re=/https?:\\/\\/[^\\/'\"]+/g;document.querySelectorAll('.api-base').forEach(function(el)\{el.textContent=el.textContent.replace(re,loc);});})();"
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
  =/  default-node=@p  (pub-of-llmproxy our.bowl now.bowl)
  =/  bind-card=card
    [%pass /bind %arvo %e %connect [~ /llmproxy] dap.bowl]
  ::  Subscribe to default-node's /models. When default-node is our own
  ::  ship (the common single-ship setup), this also gives the host UI's
  ::  deferred-refresh response a signal to fire on. In a cross-ship setup
  ::  where the inference target is someone else's ship, the host UI's
  ::  deferred refresh has no local subscription to ride on and will fall
  ::  back to its timeout — a known caveat.
  =/  watch-cards=(list card)
    :~  [%pass /models %agent [default-node %llmproxy-node] %watch /models]
    ==
  :_  %=  this
          state
        :*  %1
            nonce=0
            node=default-node
            models=~
            backend='http://localhost:11434/v1/chat/completions'
            backend-key=''
            client-api-token=''
            policy=`access-policy:llmproxy`[%whitelist ~]
            hosting=%.n
            pending=~
            pending-config=~
            telemetry=~
        ==
      ==
  [bind-card watch-cards]
::
++  on-save  !>(state)
::
++  on-load
  |=  old-state=vase
  ^-  (quip card _this)
  ::  Versioned, non-destructive load — see llmproxy-node on-load for the
  ::  full rationale. We never fall back to on-init: that silently resets
  ::  the node target, client api token, advertised models, and the hosting
  ::  flag back to defaults. Add a +$ state-N and an arm below per change;
  ::  never reshape a shipped version in place.
  =/  s  !<(versioned-state old-state)
  =.  state
    ?-  -.s
        %1  s
    ::
    ::  state-0 → state-1: drop any in-flight pending entries (their
    ::  old shape lacks `started` and we can't reconstruct latency),
    ::  init telemetry empty.
        %0
      :*  %1
          nonce.s
          node.s
          models.s
          backend.s
          backend-key.s
          client-api-token.s
          policy.s
          hosting.s
          *(map @ud pending-client)
          pending-config.s
          *(list client-telemetry-entry:llmproxy)
      ==
    ==
  `this
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+    mark  (on-poke:def mark vase)
      %noun
    =/  cmd
      !<  $%  [%set-node target=@p]
              [%set-models ms=(list @t)]
              [%ask target=@p model=@t prompt=@t]
          ==
      vase
    ?-    -.cmd
    ::  re-point at a node AND (re)subscribe to its /models, so the advertised
    ::  list stays populated (mirrors the HTML set-node path).
        %set-node
      :_  this(node target.cmd)
      ^-  (list card:agent:gall)
      :~  [%pass /models %agent [node.state %llmproxy-node] %leave ~]
          [%pass /models %agent [target.cmd %llmproxy-node] %watch /models]
      ==
        %set-models  `this(models ms.cmd)
    ::
        %ask
      =/  n=@ud  +(nonce.state)
      =/  jid=job-id:llmproxy  [our.bowl now.bowl n]
      =/  jr=job-req:llmproxy  [jid model.cmd (build-test-body model.cmd prompt.cmd)]
      =/  pat=path  /job/(scot %ud n)
      =/  rec=pending-client
        [eyre-id='' target.cmd model.cmd stream=%.n %dojo prompt.cmd api-base='' ask-id='' started=now.bowl]
      :_  %=  this
              nonce    n
              pending  (~(put by pending.state) n rec)
          ==
      :~  [%pass /poke/(scot %ud n) %agent [target.cmd %llmproxy-node] %poke %llmproxy-job !>(jr)]
          [%pass /watch/(scot %ud n) %agent [target.cmd %llmproxy-node] %watch pat]
      ==
    ==
  ::
  ::  Programmatic ask: a same-ship agent (e.g. %papertrail) pokes us with the
  ::  full OpenAI body and subscribes to /ask-result/[id]. We run the exact
  ::  existing job machinery against the configured node and answer on that
  ::  path. See docs/programmatic-ask.md.
      %llmproxy-ask
    =+  !<(cmd=ask-agent:llmproxy vase)
    ::  SECURITY: a Gall poke isn't gated by the client-api-token the way the
    ::  HTTP entrypoint is, so restrict this to agents on our own ship —
    ::  otherwise a remote ship could use our proxy without the token gate.
    ?>  =(src.bowl our.bowl)
    =/  n=@ud  +(nonce.state)
    =/  jid=job-id:llmproxy  [our.bowl now.bowl n]
    ::  caller's body forwarded verbatim; callers don't pick nodes, so we
    ::  always target the configured node.state.
    =/  jr=job-req:llmproxy  [jid model.cmd body.cmd]
    =/  pat=path  /job/(scot %ud n)
    =/  rec=pending-client
      ['' node.state model.cmd %.n %agent '' '' id.cmd now.bowl]
    :_  this(nonce n, pending (~(put by pending.state) n rec))
    :~  [%pass /poke/(scot %ud n) %agent [node.state %llmproxy-node] %poke %llmproxy-job !>(jr)]
        [%pass /watch/(scot %ud n) %agent [node.state %llmproxy-node] %watch pat]
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
      =/  node-tel  (scry-node-telemetry our.bowl now.bowl hosting.state)
      :_  this(models fresh-models)
      %+  give-simple-payload:app:server  eyre-id
      (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state fresh-models backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel '' '' ''))
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
      ::  Scry once per request for node telemetry; reused across branches
      ::  that don't toggle hosting.
      =/  node-tel  (scry-node-telemetry our.bowl now.bowl hosting.state)
      ?:  ?&  ?=(^ act)  =('set-node' u.act)  ==
        =/  raw  (~(get by fields) 'node')
        ?:  |(?=(~ raw) =('' u.raw))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'missing node value' '' ''))
        =/  parsed  (slaw %p u.raw)
        ?~  parsed
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel (cat 3 'invalid @p: ' u.raw) '' ''))
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
        (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base u.parsed fresh-models backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'node updated' '' ''))
      ?:  ?&  ?=(^ act)  =('generate-api-token' u.act)  ==
        ::  Eyre intercepts Authorization: Bearer 0v... as a session lookup,
        ::  so prefix with 'sk-' (and drop the 0v) to keep it out of that path.
        =/  new-token=@t
          (cat 3 'sk-' (rsh [3 2] (scot %uv (sham eny.bowl))))
        :_  this(client-api-token new-token)
        %+  give-simple-payload:app:server  eyre-id
        (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) %.y policy.state hosting.state now.bowl telemetry.state node-tel (cat 3 'new api token (copy now, you cannot see it again): ' new-token) '' ''))
      ?:  ?&  ?=(^ act)  =('set-client-api-token' u.act)  ==
        =/  raw  (~(get by fields) 'token')
        =/  tok=@t  ?~(raw '' u.raw)
        :_  this(client-api-token tok)
        %+  give-simple-payload:app:server  eyre-id
        (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' tok) policy.state hosting.state now.bowl telemetry.state node-tel ?:(=('' tok) 'api token disabled' 'api token set') '' ''))
      ?:  ?&  ?=(^ act)  =('refresh-models' u.act)  ==
        =/  poke-card=card
          [%pass /refresh-models %agent [our.bowl %llmproxy-node] %poke %noun !>([%refresh-models ~])]
        =/  http-cards
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'refreshing models from backend...' '' ''))
        :_  this
        [poke-card http-cards]
      ::  Merged backend + api key form. Backend URL is required and always
      ::  updated. The api key field is tri-state: leaving it blank keeps
      ::  the current value; typing a new value replaces it; ticking
      ::  `clear-key` removes the existing key (and beats out any value
      ::  typed in the field, so an accidental keystroke doesn't override
      ::  the explicit "remove" intent).
      ::
      ::  Response is deferred: we poke the node (single atomic
      ::  set-backend-and-key, triggers one /v1/models fetch) and stash the
      ::  eyre-id in pending-config. on-agent fires the response when the
      ::  /models fact arrives; on-arvo /config-timeout fires it if behn
      ::  beats the fetch (10s grace, suggests the user reload).
      ?:  ?&  ?=(^ act)  =('set-backend-and-key' u.act)  ==
        =/  raw-backend  (~(get by fields) 'backend')
        ?:  |(?=(~ raw-backend) =('' u.raw-backend))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'missing backend url' '' ''))
        =/  new-backend=@t  u.raw-backend
        =/  raw-key  (~(get by fields) 'key')
        =/  typed-key=@t  ?~(raw-key '' u.raw-key)
        =/  clear-key=?  ?=(^ (~(get by fields) 'clear-key'))
        =/  change-key=?  |(clear-key !=('' typed-key))
        =/  new-key=@t  ?:(clear-key '' typed-key)
        =/  effective-key=@t  ?:(change-key new-key backend-key.state)
        =/  n=@ud  +(nonce.state)
        =/  poke-card=card
          [%pass /set-backend-and-key %agent [our.bowl %llmproxy-node] %poke %noun !>([%set-backend-and-key new-backend effective-key])]
        =/  timeout-card=card
          [%pass /config-timeout/(scot %ud n) %arvo %b %wait (add now.bowl ~s10)]
        :_  %=  this
                nonce           n
                backend         new-backend
                backend-key     effective-key
                pending-config  (~(put by pending-config.state) n [eyre-id api-base])
            ==
        ~[poke-card timeout-card]
      ?:  ?&  ?=(^ act)  =('toggle-hosting' u.act)  ==
        =/  new-hosting=?  !hosting.state
        =/  new-node-tel  (scry-node-telemetry our.bowl now.bowl new-hosting)
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
          now.bowl
          telemetry.state
          new-node-tel
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
        (policy-cards our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base eyre-id np node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) hosting.state now.bowl telemetry.state)
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
        (policy-cards our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base eyre-id np node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) hosting.state now.bowl telemetry.state)
      ?:  ?&  ?=(^ act)  =('test' u.act)  ==
        =/  prompt-raw  (~(get by fields) 'prompt')
        =/  model-raw  (~(get by fields) 'model')
        ?:  |(?=(~ prompt-raw) =('' u.prompt-raw))
          :_  this
          %+  give-simple-payload:app:server  eyre-id
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'enter a prompt to test' '' ''))
        =/  model=@t
          ?~  model-raw
            ?~  models.state  'llama3.1:8b'
            i.models.state
          u.model-raw
        =/  n=@ud  +(nonce.state)
        =/  jid=job-id:llmproxy  [our.bowl now.bowl n]
        =/  jr=job-req:llmproxy  [jid model (build-test-body model u.prompt-raw)]
        =/  pat=path  /job/(scot %ud n)
        :_  %=  this
                nonce    n
                pending  (~(put by pending.state) n [eyre-id node.state model %.n %test u.prompt-raw api-base '' now.bowl])
            ==
        :~  [%pass /poke/(scot %ud n) %agent [node.state %llmproxy-node] %poke %llmproxy-job !>(jr)]
            [%pass /watch/(scot %ud n) %agent [node.state %llmproxy-node] %watch pat]
        ==
      :_  this
      %+  give-simple-payload:app:server  eyre-id
      (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'unknown action' '' ''))
    ::  GET /llmproxy/v1/models
    ?:  ?&  ?=(%'GET' method.request)
            ?=([%llmproxy %v1 %models ~] site.rl)
        ==
      =/  authed-state=?(%ok %none)
        ?:(=('' client-api-token.state) %none %ok)
      ?.  (bearer-ok client-api-token.state header-list.request)
        =/  err-body=@t  '{"error":"unauthorized: invalid or missing Bearer token"}'
        =/  entry=client-telemetry-entry:llmproxy
          [now.bowl %models node.state 0 '' %.n %fail %unauthorized 0 (met 3 err-body)]
        :_  this(telemetry (scag telemetry-cap `(list client-telemetry-entry:llmproxy)`[entry telemetry.state]))
        (give-simple-payload:app:server eyre-id [[401 ~] `(as-octs:mimes:html err-body)])
      =/  fresh-models=(list @t)
        ?.  =(node.state our.bowl)  models.state
        =/  scried=(unit (list @t))
          %-  mole
          |.
          .^  (list @t)  %gx
              /(scot %p our.bowl)/llmproxy-node/(scot %da now.bowl)/advertised/noun
          ==
        ?~(scried models.state u.scried)
      =/  resp-json=json  (build-models-response fresh-models)
      =/  resp-body=@t  (en:json:html resp-json)
      =/  entry=client-telemetry-entry:llmproxy
        [now.bowl %models node.state 0 '' %.n authed-state %ok 0 (met 3 resp-body)]
      :_  this(models fresh-models, telemetry (scag telemetry-cap `(list client-telemetry-entry:llmproxy)`[entry telemetry.state]))
      %+  give-simple-payload:app:server  eyre-id
      (json-response:gen:server resp-json)
    ::  POST /llmproxy/v1/chat/completions
    ?:  ?&  ?=(%'POST' method.request)
            ?=([%llmproxy %v1 %chat %completions ~] site.rl)
        ==
      =/  authed-state=?(%ok %none)
        ?:(=('' client-api-token.state) %none %ok)
      ?.  (bearer-ok client-api-token.state header-list.request)
        =/  err-body=@t  '{"error":"unauthorized: invalid or missing Bearer token"}'
        =/  entry=client-telemetry-entry:llmproxy
          [now.bowl %chat node.state 0 '' %.n %fail %unauthorized 0 (met 3 err-body)]
        :_  this(telemetry (scag telemetry-cap `(list client-telemetry-entry:llmproxy)`[entry telemetry.state]))
        (give-simple-payload:app:server eyre-id [[401 ~] `(as-octs:mimes:html err-body)])
      =/  body=@t
        ?~  body.request  ''
        q.u.body.request
      =/  parsed  (parse-openai-request body)
      ?~  parsed
        =/  err-body=@t  '{"error":"bad request"}'
        =/  entry=client-telemetry-entry:llmproxy
          [now.bowl %chat node.state 0 '' %.n authed-state %bad-request 0 (met 3 err-body)]
        :_  this(telemetry (scag telemetry-cap `(list client-telemetry-entry:llmproxy)`[entry telemetry.state]))
        (give-simple-payload:app:server eyre-id [[400 ~] `(as-octs:mimes:html err-body)])
      =/  n=@ud  +(nonce.state)
      =/  jid=job-id:llmproxy  [our.bowl now.bowl n]
      =/  jr=job-req:llmproxy  [jid model.u.parsed body.u.parsed]
      =/  pat=path  /job/(scot %ud n)
      :_  %=  this
              nonce    n
              pending  (~(put by pending.state) n [eyre-id node.state model.u.parsed stream.u.parsed %openai '' api-base '' now.bowl])
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
  ::  Programmatic-ask result subscriptions, local agents only (see on-poke).
  ?:  ?=([%ask-result @ ~] path)
    ?>  =(src.bowl our.bowl)
    `this
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
      ~&  >>>  [%client-models-watch-failed u.p.sign]
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
        ?:  =(~ pending-config.state)
          `this(models ms)
        ::  Deferred-form responses parked in pending-config get rendered
        ::  now with this fresh list. We don't try to filter by "fact in
        ::  response to my refresh vs. unrelated" — any fresh /models fact
        ::  reflects the latest node state, which is what the user wanted.
        =/  node-tel  (scry-node-telemetry our.bowl now.bowl hosting.state)
        =/  http-cards=(list card)
          %-  zing
          %+  turn  ~(tap by pending-config.state)
          |=  [n=@ud entry=[eyre-id=@ta api-base=@t]]
          %+  give-simple-payload:app:server  eyre-id.entry
          (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base.entry node.state ms backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'backend updated and models refreshed' '' ''))
        :_  this(models ms, pending-config ~)
        http-cards
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
      =/  leave-card=card
        [%pass /watch/(scot %ud n) %agent [target.u.rec %llmproxy-node] %leave ~]
      ?:  ?=(%dojo kind.u.rec)
        ~&  >>>  [%llmproxy-poke-rejected target=target.u.rec reason=u.p.sign]
        :_  this(pending (~(del by pending.state) n))
        [leave-card]~
      ::  Programmatic ask: tell the caller on its result path so its state
      ::  machine doesn't hang, then leave the (already-opened) watch.
      ?:  ?=(%agent kind.u.rec)
        :_  this(pending (~(del by pending.state) n))
        :~  leave-card
            [%give %fact ~[[%ask-result ask-id.u.rec ~]] %llmproxy-ask-error !>([ask-id.u.rec 'node rejected or unreachable'])]
        ==
      =/  err-body=@t  '{"error":"poke rejected by node (likely access policy)"}'
      =/  new-telemetry=(list client-telemetry-entry:llmproxy)
        ?.  ?=(%openai kind.u.rec)  telemetry.state
        =/  authed-state=?(%ok %none)
          ?:(=('' client-api-token.state) %none %ok)
        =/  entry=client-telemetry-entry:llmproxy
          :*  now.bowl
              %chat
              target.u.rec
              n
              model.u.rec
              stream.u.rec
              authed-state
              %node-rejected
              (elapsed-ms now.bowl started.u.rec)
              (met 3 err-body)
          ==
        (scag telemetry-cap `(list client-telemetry-entry:llmproxy)`[entry telemetry.state])
      :_  this(pending (~(del by pending.state) n), telemetry new-telemetry)
      :-  leave-card
      (give-simple-payload:app:server eyre-id.u.rec [[403 ~] `(as-octs:mimes:html err-body)])
    ==
  ::
      [%watch @ ~]
    =/  n=@ud  (slav %ud i.t.wire)
    ?+    -.sign  (on-agent:def wire sign)
        %watch-ack
      ?~  p.sign  `this
      ~&  >>>  [%client-watch-failed u.p.sign]
      =/  rec  (~(get by pending.state) n)
      ?~  rec  `this
      ?:  ?=(%dojo kind.u.rec)
        `this(pending (~(del by pending.state) n))
      ::  Programmatic ask: the watch never opened, so no leave is needed —
      ::  just report the failure to the caller's result path.
      ?:  ?=(%agent kind.u.rec)
        :_  this(pending (~(del by pending.state) n))
        [%give %fact ~[[%ask-result ask-id.u.rec ~]] %llmproxy-ask-error !>([ask-id.u.rec 'node unreachable'])]~
      =/  err-body=@t  '{"error":"node unreachable"}'
      =/  new-telemetry=(list client-telemetry-entry:llmproxy)
        ?.  ?=(%openai kind.u.rec)  telemetry.state
        =/  authed-state=?(%ok %none)
          ?:(=('' client-api-token.state) %none %ok)
        =/  entry=client-telemetry-entry:llmproxy
          :*  now.bowl
              %chat
              target.u.rec
              n
              model.u.rec
              stream.u.rec
              authed-state
              %node-unreachable
              (elapsed-ms now.bowl started.u.rec)
              (met 3 err-body)
          ==
        (scag telemetry-cap `(list client-telemetry-entry:llmproxy)`[entry telemetry.state])
      :_  this(pending (~(del by pending.state) n), telemetry new-telemetry)
      (give-simple-payload:app:server eyre-id.u.rec [[502 ~] `(as-octs:mimes:html err-body)])
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
        ::  Final fact only fires once with done=%.y. Build the response.
        ?.  done.tc  `this
        =/  leave-card=card
          [%pass /watch/(scot %ud n) %agent [target.u.rec %llmproxy-node] %leave ~]
        =/  cards=(list card)
          ?-    kind.u.rec
              %openai
            ?:  stream.u.rec
              (sse-cards eyre-id.u.rec (build-sse-body model.u.rec text.tc))
            ::  Forward the backend's chat-completion response verbatim
            ::  so tool_calls, usage, finish_reason, etc. ride along.
            %+  give-simple-payload:app:server  eyre-id.u.rec
            :-  [200 ['content-type'^'application/json']~]
            `(as-octs:mimes:html text.tc)
          ::
              %test
            =/  node-tel  (scry-node-telemetry our.bowl now.bowl hosting.state)
            %+  give-simple-payload:app:server  eyre-id.u.rec
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
              now.bowl
              telemetry.state
              node-tel
              'test response below'
              prompt.u.rec
              (extract-content text.tc)
            ==
          ::
              %dojo
            ~&  >  [%llmproxy-response target=target.u.rec model=model.u.rec text=(extract-content text.tc)]
            *(list card)
          ::
              %agent
            ::  Forward the token-chunk verbatim on the caller's result path:
            ::  it gets exactly what the HTTP path gets (usage, tool_calls, …)
            ::  and runs its own choices[0].message.content extraction.
            [%give %fact ~[[%ask-result ask-id.u.rec ~]] %llmproxy-token !>(tc)]~
          ==
        =/  new-telemetry=(list client-telemetry-entry:llmproxy)
          ?.  ?=(%openai kind.u.rec)  telemetry.state
          =/  authed-state=?(%ok %none)
            ?:(=('' client-api-token.state) %none %ok)
          =/  entry=client-telemetry-entry:llmproxy
            :*  now.bowl
                %chat
                target.u.rec
                n
                model.u.rec
                stream.u.rec
                authed-state
                %ok
                (elapsed-ms now.bowl started.u.rec)
                (met 3 text.tc)
            ==
          (scag telemetry-cap `(list client-telemetry-entry:llmproxy)`[entry telemetry.state])
        :_  this(pending (~(del by pending.state) n), telemetry new-telemetry)
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
  ::  Deferred set-backend-and-key responses get parked in pending-config
  ::  with a 10s behn fallback. If the fact races us, the entry is already
  ::  gone and this is a no-op; otherwise honestly tell the user the
  ::  refresh hasn't landed yet and let them reload to check.
  ?:  ?=([%config-timeout @ ~] wire)
    ?>  ?=([%behn %wake *] sign-arvo)
    =/  n=@ud  (slav %ud i.t.wire)
    =/  entry  (~(get by pending-config.state) n)
    ?~  entry  `this
    =/  node-tel  (scry-node-telemetry our.bowl now.bowl hosting.state)
    :_  this(pending-config (~(del by pending-config.state) n))
    %+  give-simple-payload:app:server  eyre-id.u.entry
    (manx-response (ui-page our.bowl (pub-of-llmproxy our.bowl now.bowl) api-base.u.entry node.state models.state backend.state !=('' backend-key.state) !=('' client-api-token.state) policy.state hosting.state now.bowl telemetry.state node-tel 'backend updated; model refresh still pending, reload to check' '' ''))
  (on-arvo:def wire sign-arvo)
::
++  on-leave  on-leave:def
::
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+  path  (on-peek:def path)
      [%x %jobs ~]       ``noun+!>(pending.state)
      [%x %node ~]       ``noun+!>(node.state)
      [%x %telemetry ~]  ``noun+!>(telemetry.state)
      [%x %models ~]     ``noun+!>(models.state)
  ==
++  on-fail   on-fail:def
--
