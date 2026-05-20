::  /sur/llmproxy: shared types for %llmproxy desk
::
|%
+$  job-id  [src=@p time=@da nonce=@ud]
::
::  `body` is the full OpenAI-compatible request body the client received,
::  forwarded verbatim to the backend so tools, tool_choice, temperature,
::  response_format, etc. all pass through untouched. The node overlays
::  `stream: false` before calling the backend (Iris buffers fully).
+$  job-req
  $:  id=job-id
      model=@t
      body=@t
  ==
::
::  `text` is the full backend response body, forwarded verbatim by the
::  client. Display-only paths (UI test form, dojo `[%ask ...]`) parse
::  `choices[0].message.content` out of it via extract-content.
+$  token-chunk
  $:  id=job-id
      seq=@ud
      text=@t
      done=?
  ==
::
::  Access policy enforced by %llmproxy-node on incoming job pokes.
::  In both modes, the node's own ship is always allowed.
::    %whitelist — deny everyone except `ships`
::    %blacklist — allow everyone except `ships`
+$  access-policy
  $%  [%whitelist ships=(set @p)]
      [%blacklist ships=(set @p)]
  ==
--
