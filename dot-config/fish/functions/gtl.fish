# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gtl
    git tag --sort=-v:refname -n --list "$argv[1]*"
end
