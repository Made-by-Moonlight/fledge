# Ported from oh-my-zsh plugins/git (master, 2026-10).
# Clone, then cd into the clone. The repo URL is the first argument that looks like one.
function gccd
    set -l repo
    for a in $argv
        if string match -qr '^(ssh://|git://|ftp(s)?://|http(s)?://)|@' -- $a
            set repo $a
            break
        end
    end
    test -n "$repo"; or set repo $argv[-1]
    command git clone --recurse-submodules $argv; or return
    if test -d "$argv[-1]"
        cd $argv[-1]
    else
        cd (string replace -r '\.git/*$' '' -- (path basename $repo))
    end
end
