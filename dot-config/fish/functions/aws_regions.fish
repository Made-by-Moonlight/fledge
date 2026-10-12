# Ported from oh-my-zsh plugins/aws (master, 2026-10).
function aws_regions
    set -l region us-west-1
    if test -n "$AWS_DEFAULT_REGION"
        set region $AWS_DEFAULT_REGION
    else if test -n "$AWS_REGION"
        set region $AWS_REGION
    end
    if test -n "$AWS_DEFAULT_PROFILE$AWS_PROFILE"
        aws ec2 describe-regions --region $region | grep RegionName | awk -F ':' '{gsub(/"/, "", $2);gsub(/,/, "", $2);gsub(/ /, "", $2);  print $2}'
    else
        echo "You must specify a AWS profile."
    end
end
