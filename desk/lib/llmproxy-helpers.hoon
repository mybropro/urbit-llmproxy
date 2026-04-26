::  /lib/llmproxy-helpers: pure helpers used by %llmproxy-{node,shim}.
::
::  Anything that's a pure function with no scry, no card-building, no
::  mark-typing lives here. Agents import via /+ llmproxy-helpers and
::  reference the arms.
::
/-  llmproxy
::
|%
::                                                  ::
::::                  policy                        ::
::                                                  ::
::  Whether `src` is allowed to submit a job under `policy`. The node's
::  own `our` is always allowed regardless of mode.
++  allowed
  |=  [src=@p our=@p =access-policy:llmproxy]
  ^-  ?
  ?:  =(src our)  &
  ?-    -.access-policy
      %whitelist  (~(has in ships.access-policy) src)
      %blacklist  !(~(has in ships.access-policy) src)
  ==
::                                                  ::
::::                  http auth                     ::
::                                                  ::
::  Case-insensitive header lookup. Returns the value of the first
::  matching header, or ~ if none.
++  get-header
  |=  [name=@t headers=header-list:http]
  ^-  (unit @t)
  =/  matched
    %+  skim  headers
    |=  [k=@t v=@t]
    =((cass (trip k)) (cass (trip name)))
  ?~(matched ~ `value.i.matched)
::
::  Returns true iff the request has a matching `Authorization: Bearer
::  <token>` header, OR if `token` is empty (no auth required).
++  bearer-ok
  |=  [token=@t headers=header-list:http]
  ^-  ?
  ?:  =('' token)  &
  =/  auth  (get-header 'authorization' headers)
  ?~  auth  %.n
  =((cat 3 'Bearer ' token) u.auth)
::                                                  ::
::::                  string utilities              ::
::                                                  ::
::  Trim leading/trailing ASCII spaces from a cord.
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
::  Split a comma-separated cord into a trimmed list, dropping empties.
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
::  Render a list of @t as comma-separated cord ('a, b, c').
++  list-to-csv
  |=  ms=(list @t)
  ^-  @t
  ?~  ms  ''
  ?~  t.ms  i.ms
  (rap 3 ~[i.ms ', ' $(ms t.ms)])
::
::  Render a list of @p as comma-separated cord ('~zod, ~nec').
++  ships-to-csv
  |=  ships=(list @p)
  ^-  @t
  ?~  ships  ''
  ?~  t.ships  (scot %p i.ships)
  (rap 3 ~[(scot %p i.ships) ', ' $(ships t.ships)])
::                                                  ::
::::                  policy display                ::
::                                                  ::
::  "whitelist (only listed ships allowed)" / "blacklist (...)"
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
::                                                  ::
::::                  api base / inbound request    ::
::                                                  ::
::  Derive the public-facing base URL ("http(s)://host/llmproxy") from
::  the inbound request's Host header and `secure` flag.
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
::                                                  ::
::::                  url-encoded forms             ::
::                                                  ::
::  Parse a url-encoded form body to a (map @t @t) by reusing Eyre's
::  query-string parser. Empty body returns empty map.
++  parse-form-body
  |=  body=@t
  ^-  (map @t @t)
  ?:  =('' body)  ~
  =/  prefixed=@t  (cat 3 '?' body)
  =/  parsed  (rush prefixed yque:de-purl:html)
  ?~  parsed  ~
  (malt u.parsed)
::                                                  ::
::::                  openai requests               ::
::                                                  ::
::  Parse incoming OpenAI chat-completion request body. Returns ~ if
::  the body is malformed or missing required fields.
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
::                                                  ::
::::                  backend / models discovery    ::
::                                                  ::
::  Derive the OpenAI /v1/models URL from the configured chat URL.
::  Replaces /chat/completions suffix; appends /models otherwise.
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
::  Parse OpenAI-format /v1/models response body into a list of model
::  ids. Empty list on parse failure or missing data.
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
::  Extract `choices[0].message.content` from a non-streaming OpenAI
::  chat-completion response. Returns '' on parse failure.
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
::                                                  ::
::::                  http body builders            ::
::                                                  ::
::  Build the JSON body for a (non-streaming) chat-completions request
::  to the backend.
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
--
