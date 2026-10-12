# Ported from oh-my-zsh plugins/aws (master, 2026-10).
# oh-my-zsh's ZSH_THEME_AWS_* prefix/suffix variables are honoured when set.
function aws_prompt_info
    set -l region $AWS_REGION
    test -n "$region"; or set region $AWS_DEFAULT_REGION
    test -n "$region"; or set region $AWS_PROFILE_REGION
    set -l show
    if test -n "$AWS_PROFILE"
        set -a show (string join '' (set -q ZSH_THEME_AWS_PROFILE_PREFIX; and echo $ZSH_THEME_AWS_PROFILE_PREFIX; or echo "<aws:") $AWS_PROFILE (set -q ZSH_THEME_AWS_PROFILE_SUFFIX; and echo $ZSH_THEME_AWS_PROFILE_SUFFIX; or echo ">"))
    end
    if test -n "$region"
        set -a show (string join '' (set -q ZSH_THEME_AWS_REGION_PREFIX; and echo $ZSH_THEME_AWS_REGION_PREFIX; or echo "<region:") $region (set -q ZSH_THEME_AWS_REGION_SUFFIX; and echo $ZSH_THEME_AWS_REGION_SUFFIX; or echo ">"))
    end
    string join (set -q ZSH_THEME_AWS_DIVIDER; and echo $ZSH_THEME_AWS_DIVIDER; or echo " ") $show
end
