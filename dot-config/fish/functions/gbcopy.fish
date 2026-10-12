# Ported from oh-my-zsh plugins/git (master, 2026-10).
# oh-my-zsh uses its clipcopy helper; wl-copy is the Wayland equivalent.
function gbcopy
    command git rev-parse --git-dir &>/dev/null; or return
    set -l branch (git_current_branch); or return
    test -n "$branch"; or return 1
    printf %s $branch | wl-copy
end
