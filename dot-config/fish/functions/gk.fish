# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gk
    command gitk --all --branches $argv &
    disown
end
