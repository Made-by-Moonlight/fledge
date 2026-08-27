set -l color00 '#0a0a0c'
set -l color01 '#f7768e'
set -l color02 '#9ece6a'
set -l color03 '#e0af68'
set -l color04 '#7aa2f7'
set -l color05 '#bb9af7'
set -l color06 '#4abaaf'
set -l color07 '#b2b5b3'
set -l color08 '#363638'
set -l color09 '#f7768e'
set -l color0A '#9ece6a'
set -l color0B '#e0af68'
set -l color0C '#7aa2f7'
set -l color0D '#bb9af7'
set -l color0E '#4abaaf'
set -l color0F '#e7e7e7'

set -l FZF_NON_COLOR_OPTS

for arg in (echo $FZF_DEFAULT_OPTS | tr " " "\n")
    if not string match -q -- "--color*" $arg
        set -a FZF_NON_COLOR_OPTS $arg
    end
end

set -Ux FZF_DEFAULT_OPTS "$FZF_NON_COLOR_OPTS"" --color=bg+:$color00,bg:$color00,spinner:$color0E,hl:$color0D"" --color=fg:$color07,header:$color0D,info:$color0A,pointer:$color0E"" --color=marker:$color0E,fg+:$color06,prompt:$color0A,hl+:$color0D"
