# Ported from oh-my-zsh plugins/git (master, 2026-10).
function work_in_progress
    command git -c log.showSignature=false log -n 1 2>/dev/null | grep -q -- "--wip--"; and echo "WIP!!"
end
