#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit # same as -e
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch if the pipe fucntion fails
set -o pipefail
set -x

# Helper functions
echoerr() {
    tput bold;
    tput setaf 1;
    echo "$@";
    tput sgr0; 1>&2; }

# Prints success/info $MESSAGE in green foreground color
#
# For e.g. You can use the convention of using GREEN color for [S]uccess messages
green_echo() {
    echo -e "\x1b[1;32m[S] $SELF_NAME: $MESSAGE\e[0m"
}

simple_green_echo() {
    echo -e "\x1b[1;32m$MESSAGE\e[0m"
}
blue_echo() {
    echo -e "\x1b[1;34m[I] $SELF_NAME: $MESSAGE\e[0m"
}

simple_blue_echo() {
    echo -e "\x1b[1;34m$MESSAGE\e[0m"
}

simple_red_echo() {
    echo -e "\x1b[1;31m$MESSAGE\e[0m"
}


AWS_PROFILE="default"
readonly DEFAULT_SLACK_WEBHOOK_URL=""
readonly DEFAULT_GITHUB_JOB_LINK="https://github.com/Tricentis-Cloud-Infrastructure/ttm4j-infrastructure"
DEPLOYMENT_STATUS="IN_PROGRESS"
#Check AWS credetials are defined in Gitlab Secrets
if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
    MESSAGE="AWS_ACCESS_KEY_ID is not SET!" ; simple_red_echo
    echo
    exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    MESSAGE="AWS_SECRET_ACCESS_KEY is not SET!" ; simple_red_echo
    echo
    exit 2
fi

if [[ -z "$AWS_REGION" ]]; then
    MESSAGE="AWS_REGION is not SET!" ; simple_red_echo
    echo
    exit 3
fi

aws configure --profile ${AWS_PROFILE} set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
aws configure --profile ${AWS_PROFILE} set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
aws configure --profile ${AWS_PROFILE} set region "${AWS_REGION}"

function post-exit {
  if [ $DEPLOYMENT_STATUS == "SUCCESS" ]; then
    send-deployment-success-slack-notification "$1" "$2" "$3"
  else
    send-deployment-failure-slack-notification "$1" "$2" "$3"
  fi
}

function send-deployment-failure-slack-notification {
    # Parameters
    # stack-name  - the stack name
    # slack-webhook-url - the webhook for slack

    post-slack-message "<${3}|${1}> : DEPLOYMENT FAILURE" "${2}"
}

function send-deployment-success-slack-notification {
    # Parameters
    # stack-name  - the stack name
    # slack-webhook-url - the webhook for slack

    post-slack-message "<${3}|${1}> : DEPLOYMENT SUCCESS" "${2}"
}

function post-slack-message {

    # Parameters
    # slack-message - the slack message to be sent
    # slack-webhook-url - the webhook for slack

    if [[ -n $2 ]] ; then
        curl -X POST -H 'Content-type: application/json' \
        --data '{"text":"'"$1"'"}' $2
    fi
}

cfn-deploy() {
    #Paramters
    # region                - the AWS region
    # stack-name            - the stack name
    # template              - the template file
    # parameters            - the paramters file
    # parameters_overrides  - Key=value parameters
    # capabilities          - capabilities for IAM
    # output                - the output format (yaml or json)
    # slack-webhook-url     - the webhook for slack
    # github-job-link       - the github job link
    # notificationArn       - notification ARN for stack updates

    template=$3
    parameters=$4
    parameters_overrides="$5"
    capabilities="$6"
    output="$7"
    # notificationArn="${10}"

    trap 'post-exit "$2" "$6"' EXIT

    ARG_CMD=" "
    if [[ -n $template ]]; then
        ARG_CMD="${ARG_CMD}--template-body file://${template} "
    fi
    if [[ -n $parameters ]]; then
        ARG_CMD="${ARG_CMD}--parameters file://${parameters} "
    fi
    if [[ -n $parameters_overrides ]]; then
        ARG_CMD="${ARG_CMD}--parameters ${parameters_overrides} "
    fi
    if [[ -n $capabilities ]]; then
        ARG_CMD="${ARG_CMD}--capabilities ${capabilities} "
    fi
    if [[ -n $output ]]; then
        ARG_CMD="${ARG_CMD}--output ${output} "
    fi
    if [[ -n $notificationArn ]];then
        ARG_CMD="${ARG_CMD}--notification-arns ${notificationArn[@]} "
    fi

    ARG_STRING=$ARG_CMD

    shopt -s failglob
    set -eu -o pipefail

    echo -e "\nVERIFYING IF CFN STACK EXISTS ...!"

    if ! aws cloudformation describe-stacks --region "$1" --stack-name "$2" --output "$7" ; then

    echo -e "\nSTACK DOES NOT EXISTS, RUNNING VALIDATE"
    aws cloudformation validate-template \
        --template-body file://${template}

    echo -e "\nSTACK DOES NOT EXISTS, RUNNING CREATE"
    # shellcheck disable=SC2086
    aws cloudformation create-stack \
        --region "$1" \
        --stack-name "$2" \
        --on-failure "DELETE" \
        $ARG_STRING

    echo "\nSLEEP STILL STACK CREATES zzz ..."
    aws cloudformation wait stack-create-complete \
        --region "$1" \
        --stack-name "$2" \

    else

    echo -e "\n STACK IS AVAILABLE, TRYING TO UPDATE !!"

    set +e
    # shellcheck disable=SC2086
    stack_output=$( aws cloudformation update-stack \
        --region "$1" \
        --stack-name "$2" \
        $ARG_STRING  2>&1)
    exit_status=$?
    set -e

    echo "$stack_output"

    if [ $exit_status -ne 0 ] ; then

        if [[ $stack_output == *"ValidationError"* && $stack_output == *"No updates"* ]] ; then
          DEPLOYMENT_STATUS="SUCCESS"
            echo -e "\nNO OPERATIONS PERFORMED" && exit 0
        else
            exit $exit_status
        fi
    fi

    echo "STACK UPDATE CHECK ..."

    aws cloudformation wait stack-update-complete \
        --region "$1" \
        --stack-name "$2" \

    fi

    stack_output_display=$(aws cloudformation \
      --region "$1" \
      describe-stacks --stack-name "$2" \
      --query "Stacks[0].Outputs")

    if [ "$stack_output_display" != "null" ]; then
      echo "Stack output is : ";
      echo "$stack_output_display";
    else
      echo "No stack output to display";
    fi


    echo -e "\nSUCCESSFULLY UPDATED - $2"
    DEPLOYMENT_STATUS="SUCCESS"
}
echo "AWS_REGION=$AWS_REGION"
echo "STACK_NAME=$STACK_NAME"
echo "TEMPLATE_FILE=$TEMPLATE_FILE"
echo "PARAMETERS_FILE=${PARAMETERS_FILE:-}"
echo "PARAMETER_OVERRIDE=${PARAMETER_OVERRIDE:-}"
echo "CAPABILITIES=$CAPABILITIES"


    cfn-deploy "$AWS_REGION" "$STACK_NAME" "$TEMPLATE_FILE" "${PARAMETERS_FILE:-}" "${PARAMETER_OVERRIDE}" "$CAPABILITIES" "$OUTPUT" "${SLACK_WEBHOOK_URL:-${DEFAULT_SLACK_WEBHOOK_URL}}" "${GITHUB_JOB_LINK:-${DEFAULT_GITHUB_JOB_LINK}}" "$NOTIFICATION_ARNS"
