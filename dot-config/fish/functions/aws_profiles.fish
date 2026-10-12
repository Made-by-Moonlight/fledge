# Ported from oh-my-zsh plugins/aws (master, 2026-10).
function aws_profiles
    aws --no-cli-pager configure list-profiles 2>/dev/null; and return
    set -l cfg $AWS_CONFIG_FILE
    test -n "$cfg"; or set cfg $HOME/.aws/config
    test -r $cfg; or return 1
    command grep -Eo '^[[:space:]]*\[[[:space:]]*(profile[[:space:]]+)?[^][:space:]]+[[:space:]]*\]' $cfg | command sed -E 's/^[[:space:]]*\[[[:space:]]*(profile[[:space:]]+)?([^][:space:]]+)[[:space:]]*\]$/\2/'
end
