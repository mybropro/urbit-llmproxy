::  /sur/llmproxy: shared types for %llmproxy desk
::
|%
+$  job-id  [src=@p time=@da nonce=@ud]
::
+$  job-req
  $:  id=job-id
      model=@t
      prompt=@t
  ==
::
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
