# Ported from oh-my-zsh plugins/git (master, 2026-10).
# Check for develop and similarly named branches.
function git_develop_branch
    command git rev-parse --git-dir &>/dev/null; or return
    for branch in dev devel develop development
        if command git show-ref -q --verify refs/heads/$branch
            echo $branch
            return 0
        end
    end
    echo develop
    return 1
end
