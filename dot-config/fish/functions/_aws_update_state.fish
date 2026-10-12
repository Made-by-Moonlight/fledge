# Ported from oh-my-zsh plugins/aws (master, 2026-10).
function _aws_update_state
    if test "$AWS_PROFILE_STATE_ENABLED" = true
        test -d (dirname "$AWS_STATE_FILE"); or return 1
        echo "$AWS_PROFILE $AWS_REGION" >"$AWS_STATE_FILE"
    end
end
