# Ported from oh-my-zsh plugins/kubectl (master, 2026-10).
function kres
    kubectl set env $argv REFRESHED_AT=(date +%Y%m%d%H%M%S)
end
