# Ported from oh-my-zsh plugins/aws (master, 2026-10).
function aws_change_access_key
    if test -z "$argv[1]"
        echo "usage: aws_change_access_key <profile>"
        return 1
    end
    set -l profile $argv[1]
    set -l original (aws configure get aws_access_key_id --profile $profile)
    asp $profile; or return 1
    echo "Generating a new access key pair for you now."
    if aws --no-cli-pager iam create-access-key
        echo "Insert the newly generated credentials when asked."
        aws --no-cli-pager configure --profile $profile
    else
        echo "Current access keys:"
        aws --no-cli-pager iam list-access-keys
        echo "Profile \"$profile\" is currently using the $original key. You can delete an old access key by running `aws --profile $profile iam delete-access-key --access-key-id AccessKeyId`"
        return 1
    end
    read -n 1 -P "Would you like to disable your previous access key ($original) now? " yn
    switch $yn
        case 'y*' 'Y*'
            echo -n "Disabling access key $original..."
            if aws --no-cli-pager iam update-access-key --access-key-id $original --status Inactive
                echo "done."
            else
                echo "Failed to disable $original key."
            end
        case '*'
            echo ""
    end
    echo "You can now safely delete the old access key by running `aws --profile $profile iam delete-access-key --access-key-id $original`"
    echo "Your current keys are:"
    aws --no-cli-pager iam list-access-keys
end
