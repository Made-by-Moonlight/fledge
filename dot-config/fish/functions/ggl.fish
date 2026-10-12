# Ported from oh-my-zsh plugins/git (master, 2026-10).
function ggl
    if test (count $argv) -gt 1
        git pull origin "$argv"
    else
        set -l b
        test (count $argv) -eq 0; and set b (git_current_branch)
        git pull origin (test -n "$b"; and echo $b; or echo $argv[1])
    end
end
