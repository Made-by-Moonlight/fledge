# Ported from oh-my-zsh plugins/kubectl (master, 2026-10): kubectl output as json through fx.
function kjx
    kubectl $argv -o json | fx
end
