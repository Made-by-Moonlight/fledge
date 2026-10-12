# Ported from oh-my-zsh plugins/git (master, 2026-10).
function ggu
    set -l b
    test (count $argv) -ne 1; and set b (git_current_branch)
    git pull --rebase origin (test -n "$b"; and echo $b; or echo $argv[1])
end
