# Ported from oh-my-zsh plugins/git (master, 2026-10).
function gdv
    git diff -w $argv | view -
end
