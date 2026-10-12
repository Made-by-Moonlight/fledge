# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gwip
    git add -A
    git rm (git ls-files --deleted) 2>/dev/null
    git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"
end
