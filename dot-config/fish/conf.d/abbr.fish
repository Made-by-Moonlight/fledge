# Abbreviations replace the zsh OMZ git/kubectl aliases: they expand in place,
# so the full command is visible in history and on the line before it runs.
# git: the most-used subset of Oh My Zsh's git plugin.
if status is-interactive
    abbr -a g git
    abbr -a ga 'git add'
    abbr -a gaa 'git add --all'
    abbr -a gb 'git branch'
    abbr -a gba 'git branch --all'
    abbr -a gc 'git commit --verbose'
    abbr -a 'gc!' 'git commit --verbose --amend'
    abbr -a gcm 'git commit -m'
    abbr -a gco 'git checkout'
    abbr -a gcb 'git checkout -b'
    abbr -a gd 'git diff'
    abbr -a gds 'git diff --staged'
    abbr -a gf 'git fetch'
    abbr -a gl 'git pull'
    abbr -a glog 'git log --oneline --decorate --graph'
    abbr -a gm 'git merge'
    abbr -a gp 'git push'
    abbr -a 'gp!' 'git push --force-with-lease'
    abbr -a grb 'git rebase'
    abbr -a grbi 'git rebase --interactive'
    abbr -a grbc 'git rebase --continue'
    abbr -a grs 'git restore'
    abbr -a gst 'git status'
    abbr -a gsw 'git switch'
    abbr -a gsta 'git stash push'
    abbr -a gstp 'git stash pop'

    # kubectl, kubectx
    abbr -a k kubectl
    if type -q kubectx
        abbr -a kctx kubectx
    end
    if type -q kubens
        abbr -a kns kubens
    end
end
