# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gke
    command gitk --all (git log --walk-reflogs --pretty=%h) $argv &
    disown
end
