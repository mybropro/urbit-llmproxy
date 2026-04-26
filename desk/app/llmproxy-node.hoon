::  %llmproxy-node: serve LLM inference over Ames (non-streaming Iris).
::
::  Pokes received: %llmproxy-job
::  Subscriptions: /job/<nonce> — emits one %fact with the full response,
::  then a final fact with done=%.y, then a kick.
::
/-  llmproxy
/+  default-agent
::
|%
+$  card  card:agent:gall
+$  pending-job
  $:  src=@p
      model=@t
      jid=job-id:llmproxy
  ==
+$  state-0
  $:  %0
      backend-url=@t
      backend-key=@t
      policy=access-policy:llmproxy
      advertised=(list @t)
      pending=(map @ud pending-job)
  ==
--
::
=|  state-0
=*  state  -
::
=>  |%
    ++  build-body
      |=  [model=@t prompt=@t]
      ^-  @t
      =/  jon=json
        %-  pairs:enjs:format
        :~  ['model'^s+model]
            ['stream'^b+%.n]
            :-  'messages'
            :-  %a
            :~  %-  pairs:enjs:format
                :~  ['role'^s+'user']
                    ['content'^s+prompt]
                ==
            ==
        ==
      (en:json:html jon)
    ::
    ::  Check whether a ship is allowed to submit a job under this policy.
    ::  The node's own ship is always allowed, regardless of mode.
    ++  allowed
      |=  [src=@p our=@p =access-policy:llmproxy]
      ^-  ?
      ?:  =(src our)  &
      ?-    -.access-policy
          %whitelist  (~(has in ships.access-policy) src)
          %blacklist  !(~(has in ships.access-policy) src)
      ==
    ::
    ::  Derive the OpenAI /v1/models URL from the configured /v1/chat/completions URL.
    ::  If the chat URL doesn't end with /chat/completions we append /models as a fallback.
    ++  derive-models-url
      |=  chat-url=@t
      ^-  @t
      =/  suffix  '/chat/completions'
      =/  s-len   (met 3 suffix)
      =/  u-len   (met 3 chat-url)
      ?.  (gte u-len s-len)
        (cat 3 chat-url '/models')
      =/  end-bytes  (rsh [3 (sub u-len s-len)] chat-url)
      ?.  =(suffix end-bytes)
        (cat 3 chat-url '/models')
      (cat 3 (end [3 (sub u-len s-len)] chat-url) '/models')
    ::
    ::  Parse OpenAI-format /v1/models response into a list of model id strings.
    ++  parse-models-list
      |=  body=@t
      ^-  (list @t)
      =/  jon=(unit json)  (de:json:html body)
      ?~  jon  ~
      ?.  ?=([%o *] u.jon)  ~
      =/  data  (~(get by p.u.jon) 'data')
      ?~  data  ~
      ?.  ?=([%a *] u.data)  ~
      %+  murn  p.u.data
      |=  =json
      ^-  (unit @t)
      ?.  ?=([%o *] json)  ~
      =/  id  (~(get by p.json) 'id')
      ?~  id  ~
      ?.  ?=([%s *] u.id)  ~
      `p.u.id
    ::
    ::  Build header-list with optional Authorization Bearer.
    ++  build-headers
      |=  [content-type=(unit @t) api-key=@t]
      ^-  header-list:http
      =/  base=header-list:http
        ?~  content-type  ~
        ~[['content-type'^u.content-type]]
      ?:  =('' api-key)  base
      [['authorization'^(rap 3 ~['Bearer ' api-key])] base]
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
    ::
    ::  Extract choices[0].message.content from a non-streaming OpenAI response.
    ++  extract-content
      |=  body=@t
      ^-  @t
      =/  jon=(unit json)  (de:json:html body)
      ?~  jon  ''
      ?.  ?=([%o *] u.jon)  ''
      =/  c1=(unit json)  (~(get by p.u.jon) 'choices')
      ?~  c1  ''
      ?.  ?=([%a *] u.c1)  ''
      ?~  p.u.c1  ''
      ?.  ?=([%o *] i.p.u.c1)  ''
      =/  msg=(unit json)  (~(get by p.i.p.u.c1) 'message')
      ?~  msg  ''
      ?.  ?=([%o *] u.msg)  ''
      =/  cn=(unit json)  (~(get by p.u.msg) 'content')
      ?~  cn  ''
      ?.  ?=([%s *] u.cn)  ''
      p.u.cn
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
  :_  this(state [%0 default-backend '' [%whitelist ~] ~ ~])
  [(refresh-models-card default-backend '')]~
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  =/  loaded  (mole |.(!<(state-0 vase)))
  ?~  loaded
    ~&  >>  %llmproxy-node-reset-state
    on-init
  `this(state u.loaded)
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark  (on-poke:def mark vase)
      %noun
    =/  cmd
      !<  $%  [%set-backend url=@t]
              [%set-backend-key key=@t]
              [%set-policy =access-policy:llmproxy]
              [%refresh-models ~]
          ==
      vase
    ?-    -.cmd
        %set-backend
      :_  this(backend-url url.cmd)
      [(refresh-models-card url.cmd backend-key)]~
    ::
        %set-backend-key
      :_  this(backend-key key.cmd)
      [(refresh-models-card backend-url key.cmd)]~
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
    =/  body=@t  (build-body model.jr prompt.jr)
    =/  =request:http
      :*  method=%'POST'
          url=backend-url
          header-list=(build-headers `'application/json' backend-key)
          body=`(as-octs:mimes:html body)
      ==
    =/  n=@ud  nonce.id.jr
    =/  wir=wire  /req/(scot %ud n)
    =/  rec=pending-job  [src.bowl model.jr id.jr]
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
      =/  text=@t  (extract-content body-text)
      =/  pat=path  /job/(scot %ud n)
      =/  tc=token-chunk:llmproxy  [jid.u.rec 0 text &]
      :_  this(pending (~(del by pending) n))
      :~  [%give %fact ~[pat] %llmproxy-token !>(tc)]
          [%give %kick ~[pat] ~]
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
  ==
++  on-agent  on-agent:def
++  on-fail   on-fail:def
--
