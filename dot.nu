#!/usr/bin/env nu

# Disposable Shannon target: a kind cluster running dot-ai-stack (the target app),
# with in-cluster Ollama embeddings so its resource views populate without any LLM key.
#
# Usage (inside `devbox shell`):
#   ./dot.nu setup     # stand the target up
#   ./dot.nu run       # run Shannon against it (needs SHANNON_AI_API_KEY; prompts if unset)
#   ./dot.nu destroy   # tear everything down

const CLUSTER = "shannon-target"

def kubeconfig [] { $"(pwd)/kubeconfig.yaml" }

# Stand up the disposable target.
def "main setup" [] {
    $env.KUBECONFIG = (kubeconfig)

    print "==> Creating kind cluster..."
    kind create cluster --config manifests/kind-config.yaml --kubeconfig (kubeconfig) --wait "120s"

    print "==> Installing ingress-nginx..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout "180s"

    print "==> Deploying dot-ai-stack (the target app)..."
    helm upgrade --install dot-ai-stack oci://ghcr.io/vfarcic/dot-ai-stack/charts/dot-ai-stack --version 0.106.0 --namespace dot-ai --create-namespace --values manifests/values.yaml --timeout "5m"

    print "==> Deploying Ollama (embeddings) + container-reachable route..."
    kubectl apply -f manifests/ollama.yaml
    kubectl apply -f manifests/ingress-hostdocker.yaml
    kubectl wait --for=condition=available deploy/ollama --namespace dot-ai --timeout "180s"
    kubectl exec --namespace dot-ai deploy/ollama -- ollama pull nomic-embed-text

    print "==> Waiting for the stack and kicking off resource indexing..."
    kubectl wait --for=condition=available deploy/dot-ai deploy/dot-ai-ui --namespace dot-ai --timeout "300s"
    kubectl rollout restart deploy/dot-ai-controller-manager --namespace dot-ai

    if not ("dot-ai-ui" | path exists) {
        print "==> Cloning the target's source (for Shannon's code analysis)..."
        git clone https://github.com/vfarcic/dot-ai-ui dot-ai-ui
    }

    # Write KUBECONFIG (and any future env vars) to .env so the user can point
    # their own shell at THIS cluster without touching their real ~/.kube/config.
    $"export KUBECONFIG=(kubeconfig)\n" | save --force .env

    print ""
    print "Target ready."
    print "  UI (browser):  http://dot-ai-ui.127.0.0.1.nip.io:8080   (login: Token tab -> shannon-demo-ui-token)"
    print ""
    print "To use kubectl against the target from your shell:"
    print "  source .env"
}

# Run Shannon against the target.
def "main run" [] {
    mut key = ($env.SHANNON_AI_API_KEY? | default "")
    if ($key | is-empty) {
        $key = (input "OpenRouter API key (SHANNON_AI_API_KEY): ")
    }
    if ($key | is-empty) {
        print "No API key provided; aborting."
        return
    }
    $env.SHANNON_AI_API_KEY = $key
    $env.SHANNON_AI_MODEL = "openrouter:deepseek/deepseek-v4-flash-0731"

    npx @keygraph/shannon@latest start --url http://host.docker.internal:8080 --repo $"(pwd)/dot-ai-ui" --config shannon-config.yaml --keep-container
}

# Tear everything down.
def "main destroy" [] {
    # Scope KUBECONFIG to our local file so `kind delete` updates THAT, and never
    # reaches for (or trips over) the user's real ~/.kube/config.
    $env.KUBECONFIG = (kubeconfig)

    kind delete cluster --name $CLUSTER --kubeconfig (kubeconfig)
    # system rm: handles read-only git objects in the cloned source that
    # nushell's `rm --force` refuses to delete.
    ^rm -rf dot-ai-ui kubeconfig.yaml .env
}

def main [] {
    print "Usage: ./dot.nu [setup | run | destroy]"
}
