# Ported from oh-my-zsh plugins/aws (master, 2026-10).
# AWS region selection.
function asr
    if test -z "$argv[1]"
        set -e AWS_DEFAULT_REGION AWS_REGION
        _aws_update_state
        echo AWS region cleared.
        return
    end
    if not contains -- $argv[1] (aws_regions)
        set_color red >&2
        echo "Available regions: " >&2
        aws_regions >&2
        set_color normal >&2
        return 1
    end
    set -gx AWS_REGION $argv[1]
    set -gx AWS_DEFAULT_REGION $argv[1]
    _aws_update_state
end
