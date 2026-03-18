#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022 Abhishek Malik
# SPDX-License-Identifier: BSD-2-Clause

set -exo pipefail

DOCKER_SCRIPT="docker.run"
COV_SCRIPT="coverity.run"

#export PROJECT="tpm2-totp"
export PROJECT=$PROJECT_NAME
export DOCKER_BUILD_DIR="/workspace/$PROJECT"

# if no DOCKER_IMAGE is set, warn and default to fedora-30
if [ -z "$DOCKER_IMAGE" ]; then
  echo "WARN: DOCKER_IMAGE is not set, defaulting to fedora-32"
  export DOCKER_IMAGE="fedora-32"
fi

#
# Docker starts you in a cloned repo of your project with the PR checkout out.
# We want those changes IN the docker image, so use the -v option to mount the
# project repo in the docker image.
#
# Also, pass in any env variables required for the build via .ci/docker.env
# file. For easy reproducibility, this is done explicitly via `--env VAR1=value1
# --env VAR2=value2`. For local development, you can alternatively pass
# `--env-file .ci/docker.env`.
#
# Execute the build and test procedure by running .ci/docker.run
#

ci_env=""
if [ "$ENABLE_COVERAGE" == "true" ]; then
  ci_env=$(bash <(curl -s https://codecov.io/env))
fi


if [ "$ENABLE_COVERITY" == "true" ]; then
  echo "Running coverity build"
  script="$COV_SCRIPT"
else
  echo "Running non-coverity build"
  script="$DOCKER_SCRIPT"
fi

# Converts a Docker environment file into a string of --env arguments for docker run.
#
# Example:
#   Given a file with:
#     # Comment
#     VAR1=value1
#     VAR2
#
#   Output:
#     --env VAR1=value1 --env VAR2=<current_env_value>
env_args_from_docker_env_file() {
    envfile=$1
    out=""

    # read last line even if no trailing newline:
    while IFS= read -r line || [ -n "$line" ]; do
        # trim leading whitesspace
        line=${line#"${line%%[!	 ]*}"}
        # trim trailing whitespace
        line=${line%"${line##*[!	 ]}"}

        # skip empty or comment
        [ -z "$line" ] && continue
        case "$line" in
            \#*) continue ;;
        esac

        case "$line" in
            *=*)
                key=${line%%=*}
                val=${line#*=}
                [ -z "$val" ] && continue
                ;;
            *)
                key=$line
                # get value from environment (indirect expansion via eval)
                val=$(eval "printf '%s' \"\${$key-}\"")
                [ -z "$val" ] && continue
                ;;
        esac

        out="$out --env $key=$val"
    done < "$envfile"

    # print without leading space
    printf '%s\n' "${out# }"
}

docker run --cap-add=SYS_PTRACE $ci_env $(env_args_from_docker_env_file .ci/docker.env) \
  -v "$(pwd):$DOCKER_BUILD_DIR" "ghcr.io/tpm2-software/$DOCKER_IMAGE" \
  /bin/bash -c "$DOCKER_BUILD_DIR/.ci/$script"

exit 0