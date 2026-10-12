# Ported from oh-my-zsh plugins/kubectl (master, 2026-10): kubectl output as json through jq.
function kj
    kubectl $argv -o json | jq
end
