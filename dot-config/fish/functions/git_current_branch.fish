# Ported from oh-my-zsh lib/git.zsh (master, 2026-10), used by plugins/git.
function git_current_branch
    set -l ref (command git symbolic-ref --quiet HEAD 2>/dev/null)
    set -l ret $status
    if test $ret -ne 0
        test $ret -eq 128; and return
        set ref (command git rev-parse --short HEAD 2>/dev/null); or return
    end
    string replace refs/heads/ '' -- $ref
end
