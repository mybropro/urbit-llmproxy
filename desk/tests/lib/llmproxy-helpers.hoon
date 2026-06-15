::  /tests/lib/llmproxy-helpers: unit tests for the pure helpers.
::
::  Run via: -test %/tests/lib/llmproxy-helpers ~
::
/-  llmproxy
/+  *test, lph=llmproxy-helpers
::
|%
::                                                  ::
::::                  policy: whitelist             ::
::                                                  ::
++  test-allowed-whitelist-empty
  ^-  tang
  =/  pol  `access-policy:llmproxy`[%whitelist ~]
  ;:  weld
    ::  empty whitelist: nobody but our.bowl is allowed
    %+  expect-eq  !>(%.n)  !>((allowed:lph ~zod ~bud pol))
    %+  expect-eq  !>(%.n)  !>((allowed:lph ~nec ~bud pol))
    ::  our.bowl is always allowed
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~bud ~bud pol))
  ==
::
++  test-allowed-whitelist-with-ships
  ^-  tang
  =/  pol  `access-policy:llmproxy`[%whitelist (silt ~[~zod ~nec])]
  ;:  weld
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~zod ~bud pol))
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~nec ~bud pol))
    %+  expect-eq  !>(%.n)  !>((allowed:lph ~marbud ~bud pol))
    ::  our.bowl always allowed even when not on the list
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~bud ~bud pol))
  ==
::                                                  ::
::::                  policy: blacklist             ::
::                                                  ::
++  test-allowed-blacklist-empty
  ^-  tang
  =/  pol  `access-policy:llmproxy`[%blacklist ~]
  ;:  weld
    ::  empty blacklist: everyone allowed
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~zod ~bud pol))
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~nec ~bud pol))
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~bud ~bud pol))
  ==
::
++  test-allowed-blacklist-with-ships
  ^-  tang
  =/  pol  `access-policy:llmproxy`[%blacklist (silt ~[~zod])]
  ;:  weld
    %+  expect-eq  !>(%.n)  !>((allowed:lph ~zod ~bud pol))
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~nec ~bud pol))
    ::  even if our.bowl is on the blacklist, our is always allowed
    =/  pol-2  `access-policy:llmproxy`[%blacklist (silt ~[~bud])]
    %+  expect-eq  !>(%.y)  !>((allowed:lph ~bud ~bud pol-2))
  ==
::                                                  ::
::::                  http auth                     ::
::                                                  ::
++  test-bearer-ok-empty-token
  ^-  tang
  ;:  weld
    ::  empty token = always ok regardless of header
    %+  expect-eq  !>(%.y)  !>((bearer-ok:lph '' ~))
    %+  expect-eq  !>(%.y)
      !>((bearer-ok:lph '' ~[['authorization'^'Bearer anything']]))
  ==
::
++  test-bearer-ok-token-set-no-header
  ^-  tang
  ::  token set but request has no Authorization header
  %+  expect-eq  !>(%.n)  !>((bearer-ok:lph 'sk-secret' ~))
::
++  test-bearer-ok-token-set-correct
  ^-  tang
  =/  hdrs=header-list:http  ~[['authorization'^'Bearer sk-secret']]
  %+  expect-eq  !>(%.y)  !>((bearer-ok:lph 'sk-secret' hdrs))
::
++  test-bearer-ok-token-set-wrong
  ^-  tang
  =/  hdrs=header-list:http  ~[['authorization'^'Bearer wrong']]
  %+  expect-eq  !>(%.n)  !>((bearer-ok:lph 'sk-secret' hdrs))
::
++  test-bearer-ok-token-without-bearer-prefix
  ^-  tang
  ::  Authorization without 'Bearer ' prefix should be rejected
  =/  hdrs=header-list:http  ~[['authorization'^'sk-secret']]
  %+  expect-eq  !>(%.n)  !>((bearer-ok:lph 'sk-secret' hdrs))
::
++  test-get-header-case-insensitive
  ^-  tang
  =/  hdrs=header-list:http
    ~[['Authorization'^'Bearer abc'] ['Content-Type'^'application/json']]
  ;:  weld
    %+  expect-eq
      !>(`(unit @t)`[~ 'Bearer abc'])
      !>((get-header:lph 'authorization' hdrs))
    %+  expect-eq
      !>(`(unit @t)`[~ 'Bearer abc'])
      !>((get-header:lph 'AUTHORIZATION' hdrs))
    %+  expect-eq
      !>(`(unit @t)`[~ 'application/json'])
      !>((get-header:lph 'content-type' hdrs))
    %+  expect-eq
      !>(`(unit @t)`~)
      !>((get-header:lph 'missing' hdrs))
  ==
::                                                  ::
::::                  string utilities              ::
::                                                  ::
++  test-trim-spaces
  ^-  tang
  ;:  weld
    %+  expect-eq  !>('foo')   !>((trim-spaces:lph 'foo'))
    %+  expect-eq  !>('foo')   !>((trim-spaces:lph '  foo'))
    %+  expect-eq  !>('foo')   !>((trim-spaces:lph 'foo  '))
    %+  expect-eq  !>('foo')   !>((trim-spaces:lph '   foo  '))
    %+  expect-eq  !>('')      !>((trim-spaces:lph ''))
    %+  expect-eq  !>('')      !>((trim-spaces:lph '   '))
    %+  expect-eq  !>('a b c')  !>((trim-spaces:lph '  a b c  '))
  ==
::
++  test-csv-to-list
  ^-  tang
  ;:  weld
    ::  empty
    %+  expect-eq  !>(`(list @t)`~)  !>((csv-to-list:lph ''))
    ::  single value
    %+  expect-eq  !>(~['foo'])  !>((csv-to-list:lph 'foo'))
    ::  multiple values, no spaces
    %+  expect-eq  !>(~['a' 'b' 'c'])  !>((csv-to-list:lph 'a,b,c'))
    ::  with spaces - should trim
    %+  expect-eq  !>(~['a' 'b' 'c'])  !>((csv-to-list:lph 'a, b, c'))
    %+  expect-eq  !>(~['a' 'b'])      !>((csv-to-list:lph '  a , b  '))
    ::  drops empties from trailing/leading commas
    %+  expect-eq  !>(~['a' 'b'])  !>((csv-to-list:lph ',a,b,'))
    %+  expect-eq  !>(~['a'])      !>((csv-to-list:lph 'a,,'))
  ==
::
++  test-list-to-csv
  ^-  tang
  ;:  weld
    %+  expect-eq  !>('')           !>((list-to-csv:lph ~))
    %+  expect-eq  !>('foo')        !>((list-to-csv:lph ~['foo']))
    %+  expect-eq  !>('a, b, c')    !>((list-to-csv:lph ~['a' 'b' 'c']))
  ==
::
++  test-csv-roundtrip
  ^-  tang
  =/  ms=(list @t)  ~['llama3.1:8b' 'mistral:7b']
  =/  csv  (list-to-csv:lph ms)
  %+  expect-eq  !>(ms)  !>((csv-to-list:lph csv))
::                                                  ::
::::                  policy display                ::
::                                                  ::
++  test-policy-mode-text
  ^-  tang
  ;:  weld
    %+  expect-eq
      !>('whitelist (only listed ships allowed)')
      !>((policy-mode-text:lph [%whitelist ~]))
    %+  expect-eq
      !>('blacklist (everyone except listed)')
      !>((policy-mode-text:lph [%blacklist ~]))
  ==
::                                                  ::
::::                  url-encoded forms             ::
::                                                  ::
++  test-parse-form-body-empty
  ^-  tang
  %+  expect-eq  !>(`(map @t @t)`~)  !>((parse-form-body:lph ''))
::
++  test-parse-form-body-single
  ^-  tang
  =/  m  (parse-form-body:lph 'action=set-node')
  %+  expect-eq  !>(`'set-node')  !>((~(get by m) 'action'))
::
++  test-parse-form-body-multiple
  ^-  tang
  =/  m  (parse-form-body:lph 'action=set-node&node=~zod&extra=hi')
  ;:  weld
    %+  expect-eq  !>(`'set-node')  !>((~(get by m) 'action'))
    %+  expect-eq  !>(`'~zod')      !>((~(get by m) 'node'))
    %+  expect-eq  !>(`'hi')        !>((~(get by m) 'extra'))
  ==
::                                                  ::
::::                  openai request parsing        ::
::                                                  ::
++  test-parse-openai-request-basic
  ^-  tang
  =/  in-body  '{"model":"llama3.1:8b","messages":[{"role":"user","content":"hi"}]}'
  =/  parsed  (parse-openai-request:lph in-body)
  ?~  parsed  ['expected parsed result, got ~']~
  ;:  weld
    %+  expect-eq  !>('llama3.1:8b')  !>(model.u.parsed)
    %+  expect-eq  !>(%.n)            !>(stream.u.parsed)
    ::  body is forwarded verbatim.
    %+  expect-eq  !>(in-body)        !>(body.u.parsed)
  ==
::
++  test-parse-openai-request-stream-true
  ^-  tang
  =/  body  '{"model":"m","messages":[{"role":"user","content":"x"}],"stream":true}'
  =/  parsed  (parse-openai-request:lph body)
  ?~  parsed  ['expected parsed result, got ~']~
  %+  expect-eq  !>(%.y)  !>(stream.u.parsed)
::
::  Multi-turn conversations and any other OpenAI fields (tools, temperature,
::  response_format, etc.) must survive parse. The whole client body is
::  forwarded verbatim — parse-openai-request never rewrites it.
::  Regression for the proxy-strips-fields bug.
++  test-parse-openai-request-forwards-body-verbatim
  ^-  tang
  =/  in-body  '{"model":"m","messages":[{"role":"user","content":"What is the weather?"}],"tools":[{"type":"function","function":{"name":"get_weather"}}],"temperature":0.7}'
  =/  parsed  (parse-openai-request:lph in-body)
  ?~  parsed  ['expected parsed result, got ~']~
  %+  expect-eq  !>(in-body)  !>(body.u.parsed)
::
++  test-parse-openai-request-malformed
  ^-  tang
  ;:  weld
    ::  invalid JSON
    %+  expect-eq  !>(`(unit [@t @t ?])`~)
      !>((parse-openai-request:lph 'not json'))
    ::  missing model
    %+  expect-eq  !>(`(unit [@t @t ?])`~)
      !>((parse-openai-request:lph '{"messages":[{"role":"user","content":"x"}]}'))
    ::  missing messages
    %+  expect-eq  !>(`(unit [@t @t ?])`~)
      !>((parse-openai-request:lph '{"model":"m"}'))
    ::  empty messages
    %+  expect-eq  !>(`(unit [@t @t ?])`~)
      !>((parse-openai-request:lph '{"model":"m","messages":[]}'))
  ==
::
::  build-body must overlay stream:false but leave every other field
::  alone — including arbitrary fields the proxy doesn't know about.
++  test-build-body-overlays-stream-false
  ^-  tang
  =/  in-body  '{"model":"m","messages":[{"role":"user","content":"hi"}],"tools":[{"name":"f"}],"temperature":0.5,"stream":true}'
  =/  out=(unit json)  (de:json:html (build-body:lph in-body))
  ?~  out  ['expected re-parseable JSON in output']~
  ?.  ?=([%o *] u.out)  ['expected JSON object']~
  ;:  weld
    ::  stream coerced to false
    %+  expect-eq
      !>(`(unit json)`(some b+%.n))
      !>((~(get by p.u.out) 'stream'))
    ::  every other field preserved
    %+  expect-eq
      !>(`(unit json)`(some s+'m'))
      !>((~(get by p.u.out) 'model'))
    %+  expect-eq
      !>(`(unit json)`(some n+'0.5'))
      !>((~(get by p.u.out) 'temperature'))
    %+  expect-eq
      !>(`(unit json)`(some a+~[(pairs:enjs:format ~[['name'^s+'f']])]))
      !>((~(get by p.u.out) 'tools'))
  ==
::                                                  ::
::::                  models discovery              ::
::                                                  ::
++  test-derive-models-url
  ^-  tang
  ;:  weld
    %+  expect-eq
      !>('http://localhost:11434/v1/models')
      !>((derive-models-url:lph 'http://localhost:11434/v1/chat/completions'))
    ::  fallback when chat URL doesn't end as expected
    %+  expect-eq
      !>('http://example.com/api/foo/models')
      !>((derive-models-url:lph 'http://example.com/api/foo'))
    ::  empty URL
    %+  expect-eq  !>('/models')  !>((derive-models-url:lph ''))
  ==
::
++  test-valid-backend-url
  ^-  tang
  ;:  weld
    ::  valid: full chat-completions endpoint, http and https
    %+  expect-eq  !>(%.y)
      !>((valid-backend-url:lph 'http://localhost:11434/v1/chat/completions'))
    %+  expect-eq  !>(%.y)
      !>((valid-backend-url:lph 'https://192.168.0.14:3001/v1/chat/completions'))
    ::  invalid: bare base missing /chat/completions (the footgun — models
    ::  discovery would still work, but chat POSTs would break)
    %+  expect-eq  !>(%.n)
      !>((valid-backend-url:lph 'http://192.168.0.14:3001/v1'))
    ::  invalid: wrong suffix
    %+  expect-eq  !>(%.n)
      !>((valid-backend-url:lph 'http://host/v1/completions'))
    ::  invalid: no scheme
    %+  expect-eq  !>(%.n)
      !>((valid-backend-url:lph 'localhost/v1/chat/completions'))
    ::  invalid: empty
    %+  expect-eq  !>(%.n)  !>((valid-backend-url:lph ''))
  ==
::
++  test-parse-models-list
  ^-  tang
  =/  body
    '{"object":"list","data":[{"id":"llama3.1:8b","object":"model"},{"id":"mistral:7b","object":"model"}]}'
  ;:  weld
    %+  expect-eq
      !>(~['llama3.1:8b' 'mistral:7b'])
      !>((parse-models-list:lph body))
    ::  empty data
    %+  expect-eq  !>(`(list @t)`~)
      !>((parse-models-list:lph '{"object":"list","data":[]}'))
    ::  malformed
    %+  expect-eq  !>(`(list @t)`~)
      !>((parse-models-list:lph 'not json'))
    %+  expect-eq  !>(`(list @t)`~)
      !>((parse-models-list:lph '{}'))
  ==
::                                                  ::
::::                  content extraction            ::
::                                                  ::
++  test-extract-content
  ^-  tang
  =/  body
    '{"choices":[{"message":{"role":"assistant","content":"Hello!"}}]}'
  ;:  weld
    %+  expect-eq  !>('Hello!')  !>((extract-content:lph body))
    ::  malformed
    %+  expect-eq  !>('')  !>((extract-content:lph 'not json'))
    %+  expect-eq  !>('')  !>((extract-content:lph '{}'))
    %+  expect-eq  !>('')  !>((extract-content:lph '{"choices":[]}'))
  ==
::                                                  ::
::::                  http body builders            ::
::                                                  ::
++  test-build-headers-no-key
  ^-  tang
  ;:  weld
    ::  no api key, no content-type
    %+  expect-eq  !>(`header-list:http`~)
      !>((build-headers:lph ~ ''))
    ::  no api key, with content-type
    %+  expect-eq
      !>(`header-list:http`~[['content-type'^'application/json']])
      !>((build-headers:lph `'application/json' ''))
  ==
::
++  test-build-headers-with-key
  ^-  tang
  =/  hdrs  (build-headers:lph `'application/json' 'sk-test')
  ?>  ?=(^ hdrs)
  ::  should have 2 headers: Authorization first, then content-type
  ;:  weld
    %+  expect-eq  !>(2)  !>((lent hdrs))
    %+  expect-eq  !>('Bearer sk-test')  !>(value.i.hdrs)
    %+  expect-eq  !>('authorization')   !>(key.i.hdrs)
  ==
::                                                  ::
::::                  telemetry formatters          ::
::                                                  ::
++  test-format-bytes
  ^-  tang
  ;:  weld
    %+  expect-eq  !>('0B')      !>((format-bytes:lph 0))
    %+  expect-eq  !>('1B')      !>((format-bytes:lph 1))
    %+  expect-eq  !>('1.023B')  !>((format-bytes:lph 1.023))
    %+  expect-eq  !>('1.0K')    !>((format-bytes:lph 1.024))
    %+  expect-eq  !>('1.5K')    !>((format-bytes:lph 1.536))
    %+  expect-eq  !>('1.0M')    !>((format-bytes:lph 1.048.576))
    %+  expect-eq  !>('2.0M')    !>((format-bytes:lph 2.097.152))
    %+  expect-eq  !>('5.0M')    !>((format-bytes:lph 5.242.880))
  ==
::
++  test-format-ms
  ^-  tang
  ;:  weld
    %+  expect-eq  !>('0ms')     !>((format-ms:lph 0))
    %+  expect-eq  !>('143ms')   !>((format-ms:lph 143))
    %+  expect-eq  !>('999ms')   !>((format-ms:lph 999))
    %+  expect-eq  !>('1.0s')    !>((format-ms:lph 1.000))
    %+  expect-eq  !>('1.4s')    !>((format-ms:lph 1.420))
    %+  expect-eq  !>('60.1s')   !>((format-ms:lph 60.123))
  ==
::
++  test-format-age
  ^-  tang
  =/  now  ~2026.5.20
  ;:  weld
    ::  identical times → 'now'
    %+  expect-eq  !>('now')  !>((format-age:lph now now))
    ::  future then → 'now' (clock skew safety)
    %+  expect-eq  !>('now')  !>((format-age:lph now (add now ~s5)))
    ::  seconds
    %+  expect-eq  !>('5s')   !>((format-age:lph now (sub now ~s5)))
    ::  minutes
    %+  expect-eq  !>('3m')   !>((format-age:lph now (sub now ~m3)))
    ::  hours
    %+  expect-eq  !>('2h')   !>((format-age:lph now (sub now ~h2)))
    ::  days
    %+  expect-eq  !>('4d')   !>((format-age:lph now (sub now ~d4)))
  ==
::
++  test-elapsed-ms
  ^-  tang
  =/  start  ~2026.5.20
  =/  one-ms  (div ~s1 1.000)
  ;:  weld
    %+  expect-eq  !>(0)      !>((elapsed-ms:lph start start))
    ::  future-started → 0
    %+  expect-eq  !>(0)      !>((elapsed-ms:lph start (add start ~s1)))
    %+  expect-eq  !>(143)    !>((elapsed-ms:lph (add start (mul one-ms 143)) start))
    %+  expect-eq  !>(1.000)  !>((elapsed-ms:lph (add start ~s1) start))
  ==
::
++  test-status-text
  ^-  tang
  ;:  weld
    %+  expect-eq  !>('ok')             !>((node-status-text:lph %ok))
    %+  expect-eq  !>('backend error')  !>((node-status-text:lph %backend-error))
    %+  expect-eq  !>('no response')    !>((node-status-text:lph %no-response))
    %+  expect-eq  !>('ok')             !>((client-status-text:lph %ok))
    %+  expect-eq  !>('unauthorized')   !>((client-status-text:lph %unauthorized))
    %+  expect-eq  !>('node rejected')  !>((client-status-text:lph %node-rejected))
    %+  expect-eq  !>('token ok')       !>((authed-text:lph %ok))
    %+  expect-eq  !>('no auth')        !>((authed-text:lph %none))
    %+  expect-eq  !>('token fail')     !>((authed-text:lph %fail))
  ==
--
