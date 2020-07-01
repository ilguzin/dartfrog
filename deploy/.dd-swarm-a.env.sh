#!/bin/bash

#
# Stack configuration
#

#
# Docker Swarm configuration
#


#
# DataDog configuration
#
# export DOCKER_DD_API_KEY=""

#
# Application configuration local overrides
#

# source local deployment overrides
if [ -f "${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/.${ENV_NAME}.local.env.sh" ] ; then
        source ${ENV_BASEDIR}/${ENV_GITHUB_REPO_NAME}/deploy/.${ENV_NAME}.local.env.sh
fi