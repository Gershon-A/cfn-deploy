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

#Check AWS credetials are defined in Gitlab Secrets
if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
    # echo "AWS_ACCESS_KEY_ID is not SET!"
    MESSAGE="AWS_ACCESS_KEY_ID is not SET!" ; simple_red_echo
    echo
    exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
    echo "AWS_SECRET_ACCESS_KEY is not SET!"
    exit 2
fi

if [[ -z "$AWS_REGION" ]]; then
    echo "AWS_REGION is not SET!"
    exit 3
fi

aws configure --profile ${AWS_PROFILE} set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
aws configure --profile ${AWS_PROFILE} set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
aws configure --profile ${AWS_PROFILE} set region "${AWS_REGION}"


# function example { args : string stack-name , string template } {
#   echo "My name is ${stack-name} ${template} and I am  years old."
# }
#
# MESSAGE="this is a test" ; simple_red_echo
# example # this calls a function
# echo $?

cfn-deploy() {
    #Paramters
    # region       - the AWS region
    # stack-name   - the stack name
    # template     - the template file
    # parameters   - the paramters file
    # capabilities  - capabilities for IAM

    template=$3
    parameters=$4
    parameters_overrides="$5"
    capabilities="$6"

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

    ARG_STRING=$ARG_CMD

    shopt -s failglob
    set -eu -o pipefail

    echo -e "\nVERIFYING IF CFN STACK EXISTS ...!"

    if ! aws cloudformation describe-stacks --region "$1" --stack-name "$2"; then

        echo -e "\nSTACK DOES NOT EXISTS, RUNNING VALIDATE"
        aws cloudformation validate-template \
        --template-body file://"${template}"

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
        stack_output=$(
            aws cloudformation update-stack \
            --region "$1" \
            --stack-name "$2" \
            $ARG_STRING 2>&1
        )
        exit_status=$?
        set -e

        echo "$stack_output"

        if [ $exit_status -ne 0 ]; then

            if [[ $stack_output == *"ValidationError"* && $stack_output == *"No updates"* ]]; then
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

    stack_output_display=$(
        aws cloudformation \
        --region "$1" \
        describe-stacks --stack-name "$2" \
        --query "Stacks[0].Outputs"
    )

    if [ "$stack_output_display" != "null" ]; then
        echo "Stack output is : "
        echo "$stack_output_display"
    else
        echo "No stack output to display"
    fi

    echo -e "\nSUCCESSFULLY UPDATED - $2"
}
echo "AWS_REGION=$AWS_REGION"
echo "STACK_NAME=$STACK_NAME"
echo "TEMPLATE_FILE=$TEMPLATE_FILE"
echo "PARAMETERS_FILE=${PARAMETERS_FILE:-}"
echo "AWS_REGION=$AWS_REGION"

if [[ -n $parameters ]]; then
    cfn-deploy "$AWS_REGION" "$STACK_NAME" "$TEMPLATE_FILE" "${PARAMETERS_FILE:-}" "$CAPABILITIES"
fi
if [[ -n $parameters_overrides ]]; then
    cfn-deploy "$AWS_REGION" "$STACK_NAME" "$TEMPLATE_FILE" "${PARAMETER_OVERRIDE}" "$CAPABILITIES"
fi
