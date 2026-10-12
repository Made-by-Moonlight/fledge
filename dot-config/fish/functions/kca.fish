# Ported from oh-my-zsh plugins/kubectl (master, 2026-10).
# Execute a kubectl command against all namespaces.
function kca
    kubectl $argv --all-namespaces
end
