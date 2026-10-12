# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gbda
    git branch --no-color --merged | command grep -vE "^([+*]|\s*("(git_main_branch)"|"(git_develop_branch)")\s*\$)" | command xargs git branch --delete 2>/dev/null
end
