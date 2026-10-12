# Ported from oh-my-zsh plugins/aws (master, 2026-10): the functions are in functions/.
# The prompt hook is not ported (starship has its own aws module); aws_prompt_info
# remains available. Completions for the profile/region commands, and the
# optional state file restore when AWS_PROFILE_STATE_ENABLED=true.
if status is-interactive
    complete -c asp -c acp -c aws_change_access_key -f -a '(aws_profiles)'
    complete -c asr -f -a '(aws_regions)'
end

if test "$AWS_PROFILE_STATE_ENABLED" = true
    set -q AWS_STATE_FILE; or set -gx AWS_STATE_FILE /tmp/.aws_current_profile
    if test -s $AWS_STATE_FILE
        set -l state (string split ' ' -- (cat $AWS_STATE_FILE))
        set -gx AWS_DEFAULT_PROFILE $state[1]
        set -gx AWS_PROFILE $state[1]
        set -gx AWS_EB_PROFILE $state[1]
        test -z "$state[2]"; and set -gx AWS_REGION (aws configure get region)
        set -q AWS_REGION; or set -gx AWS_REGION $state[2]
        set -gx AWS_DEFAULT_REGION $AWS_REGION
    end
end
