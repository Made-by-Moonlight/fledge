# Ported from oh-my-zsh plugins/aws (master, 2026-10).
# AWS profile selection.
function asp
    if test -z "$argv[1]"
        set -e AWS_DEFAULT_PROFILE AWS_PROFILE AWS_EB_PROFILE AWS_PROFILE_REGION
        _aws_clear_state
        echo AWS profile cleared.
        return
    end
    set -l available (aws_profiles)
    if not contains -- $argv[1] $available
        set_color red >&2
        echo "Profile '$argv[1]' not found in '"(test -n "$AWS_CONFIG_FILE"; and echo $AWS_CONFIG_FILE; or echo $HOME/.aws/config)"'" >&2
        echo "Available profiles: "(test (count $available) -gt 0; and string join ', ' $available; or echo "no profiles found") >&2
        set_color normal >&2
        return 1
    end
    set -gx AWS_DEFAULT_PROFILE $argv[1]
    set -gx AWS_PROFILE $argv[1]
    set -gx AWS_EB_PROFILE $argv[1]
    set -gx AWS_PROFILE_REGION (aws configure get region)
    _aws_update_state
    if test "$argv[2]" = login
        if test -n "$argv[3]"
            aws sso login --sso-session $argv[3]
        else
            aws sso login
        end
    else if test "$argv[2]" = logout
        aws sso logout
    end
end
