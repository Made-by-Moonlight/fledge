# Ported from oh-my-zsh plugins/kubectl (master, 2026-10): kubectl output as yaml through yh.
function ky
    kubectl $argv -o yaml | yh
end
