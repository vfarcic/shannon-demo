# shannon-demo

A disposable, local target for trying out [Shannon](https://github.com/KeygraphHQ/shannon), the AI pentester — a kind cluster running a real web app (the [dot-ai](https://github.com/vfarcic/dot-ai) UI) that you can point Shannon at and then throw away.

This exists so the setup is a non-event: the interesting part is Shannon, not standing up a target.

## Prerequisites

- **Docker** (running)
- **[Devbox](https://www.jetify.com/devbox)** — brings everything else (`kind`, `kubectl`, `helm`, `nushell`, `node`)

## Use

```bash
devbox shell          # brings in all the tools
./dot.nu setup        # stand up the target (~a few minutes; pulls images)
./dot.nu run          # run Shannon against it
./dot.nu destroy      # tear it all down
```

Everything is scoped to a local `kubeconfig.yaml` in this directory — the scripts never touch your real `~/.kube/config`. `setup` also writes a `.env` pointing `KUBECONFIG` at that file; `source .env` if you want to poke at the target cluster with your own `kubectl`.

Open the UI at http://dot-ai-ui.127.0.0.1.nip.io:8080 and log in via the **Token** tab with `shannon-demo-ui-token`.

## The API key

`./dot.nu run` needs an [OpenRouter](https://openrouter.ai) key (Shannon's model provider) in `SHANNON_AI_API_KEY`. If it isn't set, the script prompts for it.

The repo owner keeps the key in Google Secret Manager and resolves it automatically:

```bash
USE_VALS=1 devbox shell     # resolves SHANNON_AI_API_KEY from .env.vals.yaml via vals
./dot.nu run
```

`.env.vals.yaml` holds only a *reference* (`ref+gcpsecrets://...`), never the secret, so it is safe to commit. If you are not the owner, just let `./dot.nu run` prompt you for your own key.

## What's inside

- `manifests/` — the kind cluster, the `dot-ai-stack` Helm values (dummy LLM key, Ollama embeddings), and the ingress that makes the UI reachable from Shannon's container at `host.docker.internal:8080`.
- `shannon-config.yaml` — Shannon's config: exploit mode, the bearer-token login flow, and a focus on the app's API surface.

## Notes

- The tokens here are fixed demo values — the target is local and disposable, so there is no real secret to protect.
- A run takes a while and costs a little (LLM tokens). Keep your machine awake: a Docker restart evicts the kind cluster mid-run.
- Never point Shannon at anything you do not own.
