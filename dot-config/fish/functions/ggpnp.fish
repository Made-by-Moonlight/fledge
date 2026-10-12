# Ported from oh-my-zsh plugins/git (master, 2026-10).
function ggpnp
    if test (count $argv) -eq 0
        ggl; and ggp
    else
        ggl "$argv"; and ggp "$argv"
    end
end
