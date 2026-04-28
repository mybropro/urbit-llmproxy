# %llmproxy

**Share a local LLM with friends over Urbit, without exposing your machine to the public internet.**

If you've got Ollama or vLLM running on a GPU box at home and want to let a friend hit it from their laptop, the usual options are:

- **Tailscale + raw port** — works, but now your friend is on your private network and you're trusting whatever software runs on their device.
- **Cloudflare Tunnel + Bearer auth** — works, but you're maintaining a tunnel, a public hostname, an auth proxy, and rotating tokens.
- **Reverse proxy + nginx + Let's Encrypt** — works, but you're running a small webhost.

%llmproxy gets you the same outcome with less infrastructure. Both you and your friend each run an Urbit ship. Your friend installs the desk, points their `%llmproxy-client` at your `@p`, and curls `http://localhost:<port>/llmproxy/v1/chat/completions` from their laptop. Routing, NAT traversal, identity-based auth, and access control all come from Ames. No tunnels, no DNS, no certs, no public ports.

It's an OpenAI-compatible HTTP proxy on the front, an Urbit ship in the middle, your inference server on the back end.

![Network topology](docs/multi-friend.svg)

## You'll need

- An Urbit ship. A free comet works fine — see [hawk.computer/install](https://hawk.computer/~~/install/).
- The `urbit` binary running. Check `<pier>/.http.ports` for the port Eyre bound (typically `:80`).
- *(Hosting only)* a local OpenAI-compatible inference server. Ollama at `localhost:11434` is the default; vLLM, llama.cpp's server, OpenRouter, OpenAI direct, etc. all work as long as they expose `/v1/chat/completions`.

## Install from this repo

You're going to publish the desk from your own ship so friends can install it from you. From your ship's dojo:

```
|merge %llmproxy our %base
|mount %llmproxy
```

That mounts a forked-from-base desk at `<pier>/llmproxy/`. Now copy this repo's desk source onto it:

```bash
# from this repo's root, on the same machine as your pier
cp -R desk/* <pier>/llmproxy/
```

Back in the dojo:

```
|commit %llmproxy
|public %llmproxy
|install our %llmproxy
```

`|public` makes the desk pullable by anyone you give your `@p` to. `|install our %llmproxy` boots the agents on your ship. You should see:

```
gall: booted %llmproxy-node
gall: booted %llmproxy-client
```

`%llmproxy-client` binds at `http://<your-ship-host>/llmproxy`. Open `/llmproxy/ui` in a browser to configure node target, models, and access policy via HTML forms.

### Inviting a friend

Send them your `@p`. On their ship:

```
|install ~your-ship %llmproxy
```

When they see the two `gall: booted` lines, the desk is installed. They open `/llmproxy/ui` on their ship and:

1. Set **node** to your `@p`
2. (If you set an api token) paste it as the apiKey in their tool of choice

Their ship now exposes `http://localhost:<port>/llmproxy/v1/chat/completions` — fully proxied to your hardware over Ames.

## Usage

Any OpenAI-compatible tool works against `http://<ship-host>:<port>/llmproxy`. Pass the api token (if you set one) as `apiKey`.

### curl

```bash
curl -N -X POST http://localhost:80/llmproxy/v1/chat/completions \
  -H 'content-type: application/json' \
  -H 'Authorization: Bearer sk-your-token-or-anything' \
  -d '{
    "model":"llama3.1:8b",
    "messages":[{"role":"user","content":"hello"}],
    "stream":true
  }'
```

### OpenCode

In `~/.config/opencode/opencode.json` (or `opencode.json` at your project root):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "llmproxy": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "llmproxy via Urbit",
      "options": {
        "baseURL": "http://localhost:80/llmproxy/v1",
        "apiKey": "sk-your-token"
      },
      "models": {
        "llama3.1:8b": {}
      }
    }
  }
}
```

Then `opencode` and pick the `llmproxy/llama3.1:8b` model.

### Endpoints

- `POST /llmproxy/v1/chat/completions` — chat. Honors `stream` field. Returns SSE if `true`, single JSON otherwise.
- `GET /llmproxy/v1/models` — list advertised models.
- `GET /llmproxy/ui` — config page. View and update node target / api token / access policy / etc. with HTML forms. Server-rendered with [Sail](https://docs.urbit.org/hoon/sail), no JS framework, no glob.

## Architecture

Two Gall agents in one desk:

| Agent | Role |
|---|---|
| `%llmproxy-node` | Accepts job pokes, calls the local OpenAI HTTP backend, emits the result as a fact. *Run this where your inference server lives.* |
| `%llmproxy-client` | Eyre HTTP handler. Bridges OpenAI HTTP ↔ Gall pokes. Serves `/llmproxy/ui`. Also accepts `:llmproxy-client &noun [%ask ~target-ship 'model' 'prompt']` from dojo for ad-hoc tests. *Run this where you want to use the API.* |

A normal install runs both on the same ship. The client's `node` config picks which friend's ship handles inference. Each ship can run multiple OpenAI-compatible apps against its own client, all sharing the same upstream node — see the topology diagram above.

Pure functions (auth checks, parsers, JSON builders, header lookup, ...) live in `lib/llmproxy-helpers.hoon` and are unit-tested in isolation.

Source `.dot` files for the diagram live in [`docs/`](./docs) — edit and re-render with `dot -Tsvg <file>.dot -o <file>.svg`.

## Access policy

The node enforces who can submit jobs. Two modes:

- **whitelist** (default) — deny by default; only ships in the list are allowed. Empty list = nobody but your own ship.
- **blacklist** — allow by default; ships in the list are denied. Empty list = everyone.

Your own ship is always allowed regardless of mode. Manage via `/llmproxy/ui`. Denied requests return `HTTP 403` instead of timing out.

The client also gates the HTTP layer with an optional Bearer token. Generate one in the UI; paste it into your friend's `apiKey` field. Empty = no auth required.

## Known limitations

- **Streaming is a UX illusion.** Iris (Urbit's HTTP client) buffers the inference server's response fully before delivering it to the agent. From the curl client's perspective: silence, then all chunks at once. Real progressive streaming would require either runtime changes or bypassing Iris with a `%lick`-based unix bridge.
- **One node per client.** No load balancing, no fallback. The client's `node` config is a single `@p`.
- **`Authorization: Bearer 0v...` is reserved by Eyre.** Tokens generated by the client use a `sk-` prefix to avoid colliding with Urbit's session-token format.

## Updating

After install, your ship subscribes to the publisher's desk. When the publisher commits a new revision, your ship pulls it automatically and `gall: bumped` the two agents. No reinstall needed.

## Testing

Two layers:

**Hoon unit tests** (pure helpers — auth, parsers, builders):

```
-test /=llmproxy=/tests/lib/llmproxy-helpers ~
```

26 tests covering `allowed`, `bearer-ok`, `get-header`, the JSON / form / CSV parsers, model URL derivation, etc.

**Bash end-to-end tests** (HTTP behavior — needs both ships running, hosting on, and Ollama):

```
bash tests/e2e.sh
```

17 scenarios: whitelist/blacklist enforcement (local + cross-ship), API-token gate (set/wrong/right/none), generate-token randomness, models discovery, UI invariants. Override the URLs via `T1=` / `T2=` env vars.
