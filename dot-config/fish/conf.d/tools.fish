# Tool integrations, each guarded so a missing tool is silent.

# Package managers' paths come first so the tools below are found.
if test -x /home/linuxbrew/.linuxbrew/bin/brew
    /home/linuxbrew/.linuxbrew/bin/brew shellenv fish | source
else if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
end
# Per-user installs (pipx, the Antigravity CLI, ...). -g: this session only, so nothing
# lands in fish_variables; fish_add_path skips it if it's already there.
fish_add_path -g ~/.local/bin

status is-interactive; or return

# History: fish already dedupes, shares it between sessions and skips
# commands typed with a leading space; nothing to configure.

# Ctrl-P / Ctrl-N walk history entries that start with what is typed.
bind \cp history-prefix-search-backward 2>/dev/null; or bind \cp up-or-search
bind \cn history-prefix-search-forward 2>/dev/null; or bind \cn down-or-search

# fzf: Ctrl-R history, Ctrl-T files, Alt-C cd. Tab completion stays fish's pager.
if type -q fzf
    # made by moonlight palette (see theme.fish)
    set -gx FZF_DEFAULT_OPTS --color=bg+:#2f3640,fg:#c8ced8,fg+:#ffffff,hl:#f4af03,hl+:#f4af03,pointer:#f4af03,marker:#f4af03,prompt:#f4af03,info:#6c7787,border:#6c7787,gutter:-1
    fzf --fish | source
end

# Completions from each tool's own generator, where the tool exists.
# kubectl's is generated into completions/ (fish autoloads it) only when
# missing or older than the binary, so starting a shell never runs kubectl.
if type -q kubectl
    set -l comp ~/.config/fish/completions/kubectl.fish
    if not test -s $comp; or test (command -s kubectl) -nt $comp
        mkdir -p (dirname $comp)
        kubectl completion fish >$comp 2>/dev/null
    end
end
if type -q aws_completer
    complete -c aws -f -a '(begin; set -lx COMP_SHELL fish; set -lx COMP_LINE (commandline); aws_completer | sed "s/ \$//"; end)'
end

if test -x ~/.local/bin/mise
    ~/.local/bin/mise activate fish | source
end

if type -q starship
    starship init fish | source
end
