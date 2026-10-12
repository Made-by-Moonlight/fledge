# Ported from oh-my-zsh plugins/git (master, 2026-10).
function _git_log_prettily
    test -n "$argv[1]"; and git log --pretty=$argv[1]
end
