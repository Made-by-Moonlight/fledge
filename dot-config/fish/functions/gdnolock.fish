# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gdnolock
    git diff $argv ":(exclude)package-lock.json" ":(exclude)*.lock"
end
