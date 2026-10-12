# Ported from oh-my-zsh plugins/git (master, 2026-10).
# Delete branches whose changes were squash-merged (from jmaroeder/plugin-git).
function gbds
    set -l default_branch (git_main_branch); or set default_branch (git_develop_branch)
    git for-each-ref refs/heads/ "--format=%(refname:short)" | while read -l branch
        set -l merge_base (git merge-base $default_branch $branch)
        if string match -q -- '-*' (git cherry $default_branch (git commit-tree (git rev-parse $branch\^{tree}) -p $merge_base -m _))
            git branch -D $branch
        end
    end
end
