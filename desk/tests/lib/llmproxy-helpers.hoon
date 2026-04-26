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
  =/  body  '{"model":"llama3.1:8b","messages":[{"role":"user","content":"hi"}]}'
  =/  parsed  (parse-openai-request:lph body)
  ?~  parsed  ['expected parsed result, got ~']~
  ;:  weld
    %+  expect-eq  !>('llama3.1:8b')  !>(model.u.parsed)
    %+  expect-eq  !>('hi')           !>(prompt.u.parsed)
    %+  expect-eq  !>(%.n)            !>(stream.u.parsed)
  ==
::
++  test-parse-openai-request-stream-true
  ^-  tang
  =/  body  '{"model":"m","messages":[{"role":"user","content":"x"}],"stream":true}'
  =/  parsed  (parse-openai-request:lph body)
  ?~  parsed  ['expected parsed result, got ~']~
  %+  expect-eq  !>(%.y)  !>(stream.u.parsed)
::
++  test-parse-openai-request-takes-last-message
  ^-  tang
  ::  multi-turn conversation: prompt is last user message
  =/  body
    '{"model":"m","messages":[{"role":"user","content":"first"},{"role":"assistant","content":"reply"},{"role":"user","content":"second"}]}'
  =/  parsed  (parse-openai-request:lph body)
  ?~  parsed  ['expected parsed result, got ~']~
  %+  expect-eq  !>('second')  !>(prompt.u.parsed)
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
--
