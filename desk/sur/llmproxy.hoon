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
--
