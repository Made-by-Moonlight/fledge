# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gunwip
    git rev-list --max-count=1 --format="%s" HEAD | grep -q "\--wip--"; and git reset HEAD~1
end
