::  %llmproxy-client: send LLM jobs to node ships and print responses
::
/-  llmproxy
/+  default-agent
::
|%
+$  card  card:agent:gall
+$  state-0
  $:  %0
      nonce=@ud
      jobs=(map @ud [target=@p text=@t done=?])
  ==
--
::
=|  state-0
=*  state  -
::
^-  agent:gall
|_  =bowl:gall
+*  this  .
    def   ~(. (default-agent this %|) bowl)
::
++  on-init
  ^-  (quip card _this)
  `this(state [%0 0 ~])
::
++  on-save  !>(state)
::
++  on-load
  |=  =vase
  ^-  (quip card _this)
  `this(state !<(state-0 vase))
::
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark  (on-poke:def mark vase)
      %noun
    =/  cmd  !<([%ask target=@p model=@t prompt=@t] vase)
    =/  n=@ud  +(nonce.state)
    =/  jid=job-id:llmproxy  [our.bowl now.bowl n]
    =/  jr=job-req:llmproxy  [jid model.cmd prompt.cmd]
    =/  pat=path  /job/(scot %ud n)
    :_  %=  this
            jobs   (~(put by jobs.state) n [target.cmd '' |])
            nonce  n
        ==
    :~  [%pass /poke/(scot %ud n) %agent [target.cmd %llmproxy-node] %poke %llmproxy-job !>(jr)]
        [%pass /watch/(scot %ud n) %agent [target.cmd %llmproxy-node] %watch pat]
    ==
  ==
::
++  on-agent
  |=  [=wire =sign:agent:gall]
  ^-  (quip card _this)
  ?+    wire  (on-agent:def wire sign)
      [%poke @ ~]
    ?+  -.sign  (on-agent:def wire sign)
        %poke-ack
      ?~  p.sign  `this
      ~&  >>>  [%llmproxy-poke-failed u.p.sign]
      `this
    ==
  ::
      [%watch @ ~]
    ?+  -.sign  (on-agent:def wire sign)
        %watch-ack
      ?~  p.sign  `this
      ~&  >>>  [%llmproxy-watch-failed u.p.sign]
      `this
    ::
        %fact
      ?+  p.cage.sign  (on-agent:def wire sign)
          %llmproxy-token
        =/  tc  !<(token-chunk:llmproxy q.cage.sign)
        ~&  >  [%llmproxy-token text=text.tc done=done.tc]
        =/  n  (slav %ud i.t.wire)
        =/  upd  (~(get by jobs.state) n)
        ?~  upd  `this
        =.  jobs.state
          (~(put by jobs.state) n [target.u.upd text.tc done.tc])
        `this
      ==
    ==
  ==
::
++  on-arvo   on-arvo:def
++  on-watch  on-watch:def
++  on-leave  on-leave:def
::
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?+  path  (on-peek:def path)
      [%x %jobs ~]
    ``noun+!>(jobs.state)
  ==
::
++  on-fail   on-fail:def
--
