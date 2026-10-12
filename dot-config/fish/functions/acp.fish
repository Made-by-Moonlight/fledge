# Ported from oh-my-zsh plugins/aws (master, 2026-10).
# AWS profile switch, with MFA / role assumption.
function acp
    if test -z "$argv[1]"
        set -e AWS_DEFAULT_PROFILE AWS_PROFILE AWS_EB_PROFILE
        set -e AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
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

    set -l profile $argv[1]
    set -l mfa_token $argv[2]

    # Fallback credentials for if the aws command fails or no command is run.
    set -l key_id (aws configure get aws_access_key_id --profile $profile)
    set -l secret (aws configure get aws_secret_access_key --profile $profile)
    set -l token (aws configure get aws_session_token --profile $profile)

    # If the profile has MFA configured, get the token and session duration.
    set -l mfa_serial (aws configure get mfa_serial --profile $profile)
    set -l sess_duration (aws configure get duration_seconds --profile $profile)
    set -l mfa_opt
    if test -n "$mfa_serial"
        if test -z "$mfa_token"
            read -P "Please enter your MFA token for $mfa_serial: " mfa_token
        end
        if test -z "$sess_duration"
            read -P "Please enter the session duration in seconds (900-43200; default: 3600, which is the default maximum for a role): " sess_duration
        end
        test -n "$sess_duration"; or set sess_duration 3600
        set mfa_opt --serial-number $mfa_serial --token-code $mfa_token --duration-seconds $sess_duration
    end

    # Either MFA for the current role, or assume a different one.
    set -l role_arn (aws configure get role_arn --profile $profile)
    set -l sess_name (aws configure get role_session_name --profile $profile)
    set -l aws_command
    if test -n "$role_arn"
        set aws_command aws sts assume-role --role-arn $role_arn $mfa_opt
        set -l external_id (aws configure get external_id --profile $profile)
        test -n "$external_id"; and set -a aws_command --external-id $external_id
        set -l source_profile (aws configure get source_profile --profile $profile)
        test -n "$source_profile"; or set source_profile profile
        test -n "$sess_name"; or set sess_name $source_profile
        set -a aws_command --profile=$source_profile --role-session-name $sess_name
        echo "Assuming role $role_arn using profile $source_profile"
    else
        set aws_command aws sts get-session-token --profile=$profile $mfa_opt
        echo "Obtaining session token for profile $profile"
    end
    set -a aws_command --query '[Credentials.AccessKeyId,Credentials.SecretAccessKey,Credentials.SessionToken]' --output text

    set -l credentials (string split \t -- ($aws_command | string collect))
    if test (count $credentials) -gt 0
        set key_id $credentials[1]
        set secret $credentials[2]
        set token $credentials[3]
    end

    if test -n "$key_id" -a -n "$secret"
        set -gx AWS_DEFAULT_PROFILE $profile
        set -gx AWS_PROFILE $profile
        set -gx AWS_EB_PROFILE $profile
        set -gx AWS_ACCESS_KEY_ID $key_id
        set -gx AWS_SECRET_ACCESS_KEY $secret
        if test -n "$token"
            set -gx AWS_SESSION_TOKEN $token
        else
            set -e AWS_SESSION_TOKEN
        end
        echo "Switched to AWS Profile: $profile"
    end
end
