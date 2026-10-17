# Syntax and pager colours from the made by moonlight palette
# (cachyos/branding/palette.sh, quickshell/fledge/theme/Theme.qml). Our own file
# rather than omarchy/current/theme/colors.fish, which project C retires.
# Plain (global) variables, set every start, so palette edits need no
# `set -U` and nothing lands in fish_variables.
if status is-interactive
    set -l accent f4af03
    set -l fg ffffff
    set -l dim c8ced8
    set -l muted 6c7787
    set -l error e5626a
    set -l ok 8fcf8a

    set -g fish_color_normal $fg
    set -g fish_color_command $ok
    set -g fish_color_keyword $accent
    set -g fish_color_quote $accent
    set -g fish_color_redirection $dim
    set -g fish_color_end $muted
    set -g fish_color_error $error
    set -g fish_color_param $dim
    set -g fish_color_option $dim
    set -g fish_color_comment $muted
    set -g fish_color_operator $accent
    set -g fish_color_escape $accent
    set -g fish_color_autosuggestion $muted
    set -g fish_color_cwd $accent
    set -g fish_color_user $accent
    set -g fish_color_host $dim
    set -g fish_color_valid_path --underline
    set -g fish_color_search_match --background=2f3640
    set -g fish_color_selection --background=2f3640
    set -g fish_color_cancel $muted
    set -g fish_color_history_current --bold

    set -g fish_pager_color_prefix $accent --bold
    set -g fish_pager_color_completion $fg
    set -g fish_pager_color_description $muted
    set -g fish_pager_color_progress $muted
    set -g fish_pager_color_selected_background --background=2f3640
    set -g fish_pager_color_selected_completion $accent
    set -g fish_pager_color_selected_description $dim
end
