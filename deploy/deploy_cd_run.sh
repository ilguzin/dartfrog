#!/bin/bash

if [ ! -z "$1" ]; then
  export env_name=${1}
fi

# if [ ! -z "$2" ]; then
#   export run_command=${2}
# fi

# if [ ! -z "$3" ]; then
#   export run_arg=${3}
# fi

cdstamp=$(date +%s)

if [ -z ${env_name} ]; then
  # Check if env and command are given via cli
  echo "NOTICE: no env_name parameter found"
  exit 0
fi

if [ "$(
  echo $CI_COMMIT_MESSAGE | grep '^cd:' &>/dev/null
  echo $?
)" == '0' ]; then
  # If cd-commit message has been used to deploy (format is: "cd:ENV_NAME:COMMAND:VERSION", e.g. "cd:update:1.0.1")
  # environment is defined then by env_name which is in its turn defined by current branch tag
  # (see https://documentation.codeship.com/pro/builds-and-configuration/steps/#limiting-steps-to-specific-branches-or-tags)

  # override any run_command and run_arg given
  run_env_name=$(echo ${CI_COMMIT_MESSAGE} | awk -F: '{print $2}')
  run_command=$(echo ${CI_COMMIT_MESSAGE} | awk -F: '{print $3}')
  run_arg=$(echo ${CI_COMMIT_MESSAGE} | awk -F: '{print $4}')

  if [ ${env_name} != ${run_env_name} ]; then
    # Check if env and command are given via cli
    echo "NOTICE: '${run_env_name}' env selected, skipping '${env_name}' env"
    exit 0
  fi
fi


if [ -z ${run_command} ]; then
  # Check if env and command are given via cli
  echo "NOTICE: no proper CD command given, make sure to pass both run_command and run_arg parameters via cd-commit based command to deploy"
  exit 0
fi

if [ "${run_command}" == 'noop' ]; then
  echo "NOTICE: Command 'noop' given."
  exit 0
fi

# if [ -z ${run_arg} ]; then
#   # Check if env and command are given via cli
#   echo "NOTICE: no proper CD command given, make sure to pass both run_command and run_arg parameters via cd-commit based command to deploy"
#   exit 0
# fi

if [ -z "$MANAGER_HOST" ]; then
  echo "NOTICE: MANAGER_HOST has to be set to swarm manager host to deploy to"
  exit 0
fi

echo -e $PRIVATE_SSH_KEY >/root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa
ssh-keyscan -H $MANAGER_HOST >/root/.ssh/known_hosts 2>/dev/null
echo 'SendEnv ENV_* CI_*' >/root/.ssh/config
scp /deploy/deploy.sh root@$MANAGER_HOST:/tmp/deploy.sh.${cdstamp} &>/dev/null

ssh -T root@$MANAGER_HOST /tmp/deploy.sh.${cdstamp} ${env_name} ${run_command} ${run_arg} 2>&1

exit $?
