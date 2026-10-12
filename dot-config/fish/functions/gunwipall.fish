# Ported from oh-my-zsh plugins/git (master, 2026-10).
# Like gunwip, but unwips all recent --wip-- commits, not just the last one.
function gunwipall
    set -l _commit (git log --grep='--wip--' --invert-grep --max-count=1 --format=format:%H)
    if test "$_commit" != (git rev-parse HEAD)
        git reset $_commit; or return 1
    end
end
