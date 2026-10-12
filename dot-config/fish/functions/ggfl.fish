# Ported from oh-my-zsh plugins/git (master, 2026-10).
function ggfl
    set -l b
    test (count $argv) -ne 1; and set b (git_current_branch)
    git push --force-with-lease origin (test -n "$b"; and echo $b; or echo $argv[1])
end
