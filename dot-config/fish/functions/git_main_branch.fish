# Ported from oh-my-zsh plugins/git (master, 2026-10).
# Default branch name from common names, falling back to the remote HEAD.
function git_main_branch
    command git rev-parse --git-dir &>/dev/null; or return
    for base in refs/heads refs/remotes/origin refs/remotes/upstream
        for name in main trunk mainline default stable master
            if command git show-ref -q --verify $base/$name
                echo $name
                return 0
            end
        end
    end
    for remote in origin upstream
        set -l ref (command git rev-parse --abbrev-ref $remote/HEAD 2>/dev/null)
        if string match -q "$remote/*" -- $ref
            string replace "$remote/" '' -- $ref
            return 0
        end
    end
    echo master
    return 1
end
