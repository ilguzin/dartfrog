#!/bin/bash

if [ -z "$1" ]; then
  echo "ERROR: Envirment name not set"
  exit 1
else
  export ENV_NAME=${1}
fi

if [ -z "$2" ]; then
  echo "ERROR: Command not provided"
  exit 1
else
  export COMMAND=${2}
fi

if [ ! -z "$3" ]; then
  export RUN_ARG=${3}
fi

if [ -z "${ENV_GITHUB_REPO_NAME}" ]; then
  export ENV_GITHUB_REPO_NAME=dartfrog
fi

if [ -z "${ENV_PATH}" ]; then
  export ENV_PATH=/mnt/deployments
fi

export ENV_BASEDIR="${ENV_PATH}/${ENV_NAME}"

IFS=$'\n'

check_env_vars() {
  declare -a ENV_VARS=(
    'ENV_GITHUB_REPO_NAME' 'ENV_NAME' 'ENV_PATH' 'ENV_GITHUB_PRIVATE_SSH_KEY'
  )

  for ENV_VAR in "${ENV_VARS[@]}"; do
    #echo "$ENV_VAR : ${!ENV_VAR}"
    # echo "Checking var ${ENV_VAR}"
    if [ -z ${!ENV_VAR} ]; then
      echo "ERROR: Environment variable ${ENV_VAR} not found."
      exit 1
    fi
  done

  if [[ -z ${CI_BRANCH} && -z ${RUN_ARG} && -z ${CI_TAG} ]]; then
    echo "ERROR: One of CI_TAG, CI_BRANCH, or RUN_ARG env variables is required to be set."
    exit 1
  fi

  # if [[ -z ${RUN_ARG} ]]; then
  #   echo "ERROR: RUN_ARG variable is required to be set."
  #   exit 1
  # fi

}

create_config() {
  filename=${1}
  path=${2}

  if [ $(
    docker config ls | grep ${ENV_NAME} | grep "${filename}\." | grep -v '\.tmp' &>/dev/null
    echo $?
  ) == '0' ]; then
    # config version already exists

    # find old version stamp
    oldstamp=$(docker config ls | grep ${ENV_NAME} | grep "${filename}\." | grep -v '\.tmp' | awk '{print $2}' | awk -F. '{print $NF}' | sort -n | tail -n 1)

    # delete any existing .tmp
    docker config rm ${ENV_NAME}.${filename}.tmp &>/dev/null
    # create new .tmp
    cat ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/${path}/${filename} | docker config create ${ENV_NAME}.${filename}.tmp -

    # get data value from latest and .tmp
    currentvalue=$(docker config inspect ${ENV_NAME}.${filename}.${oldstamp} | jq '.[].Spec.Data' | awk -F\" '{print $2}')
    tmpvalue=$(docker config inspect ${ENV_NAME}.${filename}.tmp | jq '.[].Spec.Data' | awk -F\" '{print $2}')

    # compare
    if [ "${currentvalue}" == "$tmpvalue" ]; then
      # if the same, set the api_hub_config_stamp to the latest value
      eval export "CONFIG_$(echo $filename | sed -e 's/\./_/g' | sed -e 's/-/_/g')_STAMP"=${oldstamp}
    else
      cat ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/${path}/${filename} | docker config create ${ENV_NAME}.${filename}.${STAMP} -
      eval export "CONFIG_$(echo $filename | sed -e 's/\./_/g' | sed -e 's/-/_/g')_STAMP"=${STAMP}
    fi

    docker config rm ${ENV_NAME}.${filename}.tmp &>/dev/null

    for configversion in $(docker config ls | grep ${ENV_NAME} | grep "${filename}\." | grep -v '\.tmp' | grep -v "${STAMP}\|${oldstamp}" | awk '{print $1}'); do
      docker config rm ${ENV_NAME}.${filename}.${configversion} &>/dev/null
    done
  else
    # no config version exists

    # create config with current stamp
    cat ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/${path}/${filename} | docker config create ${ENV_NAME}.${filename}.${STAMP} -
    # set api_hub_config_stamp to current stamp
    eval export "CONFIG_$(echo $filename | sed -e 's/\./_/g' | sed -e 's/-/_/g')_STAMP"=${STAMP}
  fi

}

create_secret() {
  secretname=${1}

  if [ $(
    docker secret ls | grep ${ENV_NAME} | grep "${secretname}\." | grep -v '\.tmp' &>/dev/null
    echo $?
  ) == '0' ]; then
    # config version already exists

    # find old version stamp
    oldstamp=$(docker secret ls | grep ${ENV_NAME} | grep "${secretname}\." | grep -v '\.tmp' | awk '{print $2}' | awk -F. '{print $NF}' | sort -n | tail -n 1)

    newhash=$(printf -- ${SECRETVALUE} | sha512sum | awk '{print $1}')

    oldhash=$(docker secret inspect ${ENV_NAME}.${secretname}.${oldstamp} | jq '.[].Spec.Labels.hash' | awk -F\" '{print $2}')

    # compare
    if [ "${newhash}" == "${oldhash}" ]; then
      eval export "SECRET_$(echo $secretname | sed -e 's/\./_/g' | sed -e 's/-/_/g')_STAMP"=${oldstamp}
    else
      printf -- "${SECRETVALUE}" | docker secret create --label hash=${newhash} ${ENV_NAME}.${secretname}.${STAMP} -
      eval export "SECRET_$(echo $secretname | sed -e 's/\./_/g' | sed -e 's/-/_/g')_STAMP"=${STAMP}
    fi

    for secretversion in $(docker config ls | grep ${ENV_NAME} | grep "${secretname}\." | grep -v '\.tmp' | grep -v "${STAMP}\|${oldstamp}" | awk '{print $1}'); do
      docker secret rm ${ENV_NAME}.${secretname}.${secretversion} &>/dev/null
    done
  else
    # no config version exists

    # create config with current stamp
    printf -- "${SECRETVALUE}" | docker secret create --label hash=${newhash} ${ENV_NAME}.${secretname}.${STAMP} -
    # set api_hub_config_stamp to current stamp
    eval export "SECRET_$(echo $secretname | sed -e 's/\./_/g' | sed -e 's/-/_/g')_STAMP"=${STAMP}
  fi

  unset SECRETVALUE

}

image_version_matching() {
  for image in $(cat ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/.images.sh | grep '^export'); do
    if [ "$(
      echo $image | grep '>=' >/dev/null
      echo $?
    )" == '0' ]; then
      imagevar=$(echo $image | awk '{print $2}' | awk -F= '{print $1}')
      imageversion=$(echo $image | awk '{print $NF}' | awk -F\' '{print $1}')
      imagename=$(grep ${imagevar} ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/${ENV_COMPOSE_FILE} | head -n 1 | awk '{print $NF}' | awk -F: '{print $1}')
      export IMGNAME=${imagename}
      if [ "$(
        echo ${imageversion} | grep '^[0-9]' &>/dev/null
        echo $?
      )" == '0' ]; then
        versions=$(image_tag_list ${imagename} | grep '^[0-9]' | sort -V)
      else
        versions=$(image_tag_list ${imagename} | grep '^v' | sort -V)
      fi
      eval export ${imagevar}="$(echo $versions | awk -F${imageversion} -v imageversion="${imageversion}" '{print imageversion" "$NF}' | awk '{print $NF}')"
      realversion=$(echo $versions | awk -F${imageversion} -v imageversion="${imageversion}" '{print imageversion" "$NF}' | awk '{print $NF}')
      [ -z "${realversion}" ] && echo "ERROR: No matching version found for ${imagename} (variable name ${imagevar})." && exit 1
      eval export ${imagevar}="${realversion}"
    elif [ "$(
      echo $image | grep '<=' >/dev/null
      echo $?
    )" == '0' ]; then
      imagevar=$(echo $image | awk '{print $2}' | awk -F= '{print $1}')
      imageversion=$(echo $image | awk '{print $NF}' | awk -F\' '{print $1}')
      imagename=$(grep ${imagevar} ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/${ENV_COMPOSE_FILE} | head -n 1 | awk '{print $NF}' | awk -F: '{print $1}')
      export IMGNAME=${imagename}
      if [ "$(
        echo ${imageversion} | grep '^[0-9]' &>/dev/null
        echo $?
      )" == '0' ]; then
        versions=$(image_tag_list ${imagename} | grep '^[0-9]' | sort -V)
      else
        versions=$(image_tag_list ${imagename} | grep '^v' | sort -V)
      fi
      realversion=$(echo $versions | awk -F${imageversion} -v imageversion="${imageversion}" '{print $1" "imageversion}' | awk '{print $1}')
      [ -z "${realversion}" ] && echo "ERROR: No matching version found for ${imagename} (variable name ${imagevar})." && exit 1
      eval export ${imagevar}="${realversion}"
    elif [ "$(
      echo $image | grep '>' >/dev/null
      echo $?
    )" == '0' ]; then
      imagevar=$(echo $image | awk '{print $2}' | awk -F= '{print $1}')
      imageversion=$(echo $image | awk '{print $NF}' | awk -F\' '{print $1}')
      imagename=$(grep ${imagevar} ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/${ENV_COMPOSE_FILE} | head -n 1 | awk '{print $NF}' | awk -F: '{print $1}')
      export IMGNAME=${imagename}
      if [ "$(
        echo ${imageversion} | grep '^[0-9]' &>/dev/null
        echo $?
      )" == '0' ]; then
        versions=$(image_tag_list ${imagename} | grep '^[0-9]' | sort -V)
      else
        versions=$(image_tag_list ${imagename} | grep '^v' | sort -V)
      fi
      realversion=$(echo $versions | awk -F${imageversion} '{print $NF}' | awk '{print $NF}')
      [ -z "${realversion}" ] && echo "ERROR: No matching version found for ${imagename} (variable name ${imagevar})." && exit 1
      eval export ${imagevar}="${realversion}"
    elif [ "$(
      echo $image | grep '<' >/dev/null
      echo $?
    )" == '0' ]; then
      imagevar=$(echo $image | awk '{print $2}' | awk -F= '{print $1}')
      imageversion=$(echo $image | awk '{print $NF}' | awk -F\' '{print $1}')
      imagename=$(grep ${imagevar} ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/${ENV_COMPOSE_FILE} | head -n 1 | awk '{print $NF}' | awk -F: '{print $1}')
      export IMGNAME=${imagename}
      if [ "$(
        echo ${imageversion} | grep '^[0-9]' &>/dev/null
        echo $?
      )" == '0' ]; then
        versions=$(image_tag_list | grep '^[0-9]' | sort -V)
      else
        versions=$(image_tag_list | grep '^v' | sort -V)
      fi
      realversion=$(echo $versions | awk -F${imageversion} '{print $1}' | awk '{print $1}')
      [ -z "${realversion}" ] && echo "ERROR: No matching version found for ${imagename} (variable name ${imagevar})." && exit 1
      eval export ${imagevar}="${realversion}"
    elif [ "$(
      echo $image | grep '=' >/dev/null
      echo $?
    )" == '0' ]; then
      imagevar=$(echo $image | awk '{print $2}' | awk -F= '{print $1}')
      imageversion=$(echo $image | awk '{print $NF}' | awk -F\' '{print $1}')
      eval export ${imagevar}="${imageversion}"

    fi
  done

}

check_env_clean() {
  # verify that env is not created
  [ -d "${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}" ] && echo "ERROR: Environment directory already exists." && exit 1

}

set_stamp() {
  export STAMP=$(date +%s)
}

git_checkout() {
  # cd to ${ENV_GITHUB_REPO_NAME} directory
  cd ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/

  # checkout the correct branch. it will either use the same branch name as the ${ENV_GITHUB_REPO_NAME} project or the name from the override var
  if [ ! -z "${RUN_ARG}" ]; then
    GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_github_${ENV_GITHUB_REPO_NAME}" git checkout $RUN_ARG
  elif [ ! -z "${CI_TAG}" ]; then
    GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_github_${ENV_GITHUB_REPO_NAME}" git checkout $CI_TAG
  elif [ ! -z "${CI_BRANCH}" ]; then
    GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_github_${ENV_GITHUB_REPO_NAME}" git checkout $CI_BRANCH
  else
    echo "ERROR: No git tag or branch found to checkout."
    exit 1
  fi
}

create_env() {
  # Configure access to github
  echo -e $ENV_GITHUB_PRIVATE_SSH_KEY > /root/.ssh/id_rsa_github_${ENV_GITHUB_REPO_NAME}
  chmod 600 /root/.ssh/id_rsa_github_${ENV_GITHUB_REPO_NAME}
  ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
  # create env base directory and data directories
  mkdir -p ${ENV_BASEDIR}
  mkdir -p ${ENV_BASEDIR}/data/zk_data
  mkdir -p ${ENV_BASEDIR}/data/zk_log_data
  mkdir -p ${ENV_BASEDIR}/data/zk_logs
  mkdir -p ${ENV_BASEDIR}/data/kafka_data
  mkdir -p ${ENV_BASEDIR}/data/mongo_data
  mkdir -p ${ENV_BASEDIR}/data/redis_data
  mkdir -p ${ENV_BASEDIR}/data/redis_conf
  # cd there
  cd ${ENV_BASEDIR}
  # clone the ${ENV_GITHUB_REPO_NAME} project into base directory
  GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_github_${ENV_GITHUB_REPO_NAME}" git clone git@github.com:serverfarm/${ENV_GITHUB_REPO_NAME}.git

  git_checkout
}

get_env_vars() {
  # Source the provider env, which will source the any others needed to deploy the stack.
  source ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/.${ENV_NAME}.env.sh
}

create_compose() {
  # Update env base directory and URL in the compose
  envsubst <"${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/${ENV_COMPOSE_FILE}" > "${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/docker-compose.yml"
}

create_env_network() {
  # Create serivces network
  docker network create --driver overlay --scope swarm --attachable ${ENV_NAME} &>/dev/null
  # Create services expose network
  docker network create --driver bridge --scope swarm frontend-${ENV_NAME} &>/dev/null
}

set_compose_file() {
  if [ -f "${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/docker-compose.yml.template.${ENV_NAME}" ]; then
    export ENV_COMPOSE_FILE="docker-compose.yml.template.${ENV_NAME}"
  else
    export ENV_COMPOSE_FILE="docker-compose.yml.template"
  fi
}

env_update() {
  get_env_vars
  image_version_matching
  create_env_network
  set_compose_file
  create_compose
}

run_create() {

  check_env_clean

  create_env

  env_update
}

run_env_verify() {

  get_env_vars
  check_env_vars

  set_compose_file

  [ ! -d "${ENV_BASEDIR}" ] && echo "ERROR: Environment base directory does not exist." && exit 1

  [ ! -f "${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/${ENV_COMPOSE_FILE}" ] && echo "ERROR: Environment docker-compose.yml template(${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/${ENV_COMPOSE_FILE}) does not exist." && exit 1
  [ ! -f "${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/.${ENV_NAME}.env.sh" ] && echo "ERROR: Provider environment file does not exist." && exit 1

  [ "$(
    docker network inspect ${ENV_NAME} &>/dev/null
    echo $?
  )" != '0' ] && echo "ERROR: Environment Docker '${ENV_NAME}' network does not exist." && exit 1

  [ "$(
    docker network inspect frontend-${ENV_NAME} &>/dev/null
    echo $?
  )" != '0' ] && echo "ERROR: Environment Docker 'frontend-${ENV_NAME}' network does not exist." && exit 1

  echo "VERIFY: Enviroment exists."
}

pull_env() {
  cd ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/
  GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_github_${ENV_GITHUB_REPO_NAME}" git pull
  git_checkout
}

run_deploy() {
  # Run the 'docker stack deploy' command
  docker stack deploy --with-registry-auth --prune --compose-file ${ENV_PATH}/${ENV_NAME}/${ENV_GITHUB_REPO_NAME}/deploy/docker-compose.yml ${ENV_NAME}
}

run_stop() {
  # Run the 'docker stack deploy' command
  docker stack rm ${ENV_NAME}
}

set_dh_token() {
  export DH_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST -d '{"username": "'${ENV_DH_USER}'", "password": "'${ENV_DH_PASS}'"}' https://hub.docker.com/v2/users/login/ | jq -r .token)
}

image_list() {

  # Docker Hub

  [ -z $DH_TOKEN ] && set_dh_token

  if [ -z ${CLI} ]; then
    OUTPUT="\n"
  else
    OUTPUT=""
  fi

  for IMGNAME in $(curl -s -H "Authorization: JWT ${DH_TOKEN}" https://hub.docker.com/v2/repositories/serverfarm/?page_size=10000 | jq -r '.results|.[]|.name' | sort); do
    OUTPUT="${OUTPUT}serverfarm/${IMGNAME}\n"
  done
  printf "$OUTPUT"
  # InnoScale Harbor

}

image_tag_list() {
  [ -z $DH_TOKEN ] && set_dh_token

  if [ -z ${CLI} ]; then
    OUTPUT="\n"
  else
    OUTPUT=""
  fi

  for TAG in $(curl -s -H "Authorization: JWT ${DH_TOKEN}" https://hub.docker.com/v2/repositories/${IMGNAME}/tags/?page_size=10000 | jq -r '.results|.[]|.name' | sort); do
    OUTPUT="${OUTPUT}${TAG}\n"
  done
  printf "$OUTPUT"
}

set_stamp

case $COMMAND in
'create')
  check_env_clean
  create_env
  get_env_vars
  check_env_vars
  env_update
  exit 0
  ;;
'deploy' | 'start' | 'up')
  run_env_verify
  run_deploy
  exit 0
  ;;
'update' | 'scale' | 'image' | 'images')
  pull_env
  run_env_verify
  env_update
  run_deploy
  exit 0
  ;;
'updatenodep')
  pull_env
  run_env_verify
  env_update
  exit 0
  ;;
'envverify')
  run_env_verify
  exit 0
  ;;
'stackverify')
  run_env_verify
  run_stack_verify
  exit 0
  ;;
'stop' | 'down')
  run_env_verify
  run_stop
  exit 0
  ;;
'teardown')
  run_env_verify
  run_teardown
  exit 0
  ;;
'imagelist' | 'imagels' | 'imgls')
  image_list
  exit 0
  ;;
'imageversions' | 'imgver' | 'imgvers' | 'imagetags' | 'imagetag' | 'imgtag' | 'imgtags')
  IMGNAME=${RUN_ARG}
  image_tag_list
  exit 0
  ;;
*)
  echo "ERROR: No command provided."
  exit 1
  ;;
esac
