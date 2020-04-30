#!/bin/bash
set -eu
set -o pipefail

sourcecred_data="${GITHUB_WORKSPACE}/sourcecred_data"
export SOURCECRED_DIRECTORY="${sourcecred_data}"

# This script uses the scripts/build-static-site.sh provided in the container
# and customizes the entrypoint based on what the user has provided.
# We derive variables from the environment instead of command line

COMMAND="/bin/bash /build_static_site.sh"

echo METABOTS $GITHUB_WORKSPACE $SC_PROJECT_FILE $SC_WEIGHTS

ls

pwd

# Target is required, project has a default
if [ -z "${SC_TARGET}" ]; then
   SC_TARGET="${GITHUB_WORKSPACE}/docs"        
fi
COMMAND="${COMMAND} --target ${SC_TARGET}"

# Project file and if are both required for generation!
# The action requires, but we have the double check here for a fallback
if [ -z "${SC_PROJECT_FILE}" ]; then
    echo "Project file (project-file) is required"
    exit 1
fi
if [ -z "${SC_PROJECT}" ]; then
    echo "Project identifier (project) is required"
    exit 1
fi
COMMAND="${COMMAND} --project-file ${GITHUB_WORKSPACE}/${SC_PROJECT_FILE}"

# Weights are not required, added if defined
if [ ! -z "${SC_WEIGHTS}" ]; then
    COMMAND="${COMMAND} --weights ${GITHUB_WORKSPACE}/${SC_WEIGHTS}"
fi

# Show the user where we are
echo "Present working directory is:"
echo "${PWD}"
ls

# Clean up any previous runs (deployed in docs folder)
# This command needs to be run relative to sourcecred respository
# that is located at the WORKDIR /code
rm -rf "${SC_TARGET}"
echo "${COMMAND}"
${COMMAND}

echo "Finished initial run, present working directory is ${PWD}"
ls

# This interacts with node sourcecred.js
# Load it twice so we can access the scores -- it's a hack, pending real instance system
# Note from @vsoch: these variable names aren't consistent - the project here referes to the project file.
LOAD_COMMAND="node /code/bin/sourcecred.js load --project ${GITHUB_WORKSPACE}/${SC_PROJECT_FILE}"
if [ ! -z "${SC_WEIGHTS}" ]; then
    LOAD_COMMAND="${LOAD_COMMAND} --weights ${GITHUB_WORKSPACE}/${SC_WEIGHTS}"
fi
echo "$LOAD_COMMAND"
${LOAD_COMMAND}
node /code/bin/sourcecred.js scores "${SC_PROJECT}" | python3 -m json.tool > "${GITHUB_WORKSPACE}/${SC_SCORES_JSON}"

# Now we want to interact with the GitHub repository
# The GitHub workspace has the root of the repository
cd "${GITHUB_WORKSPACE}"
echo "Found files in workspace:"
ls

echo "GitHub Actor: ${GITHUB_ACTOR}"
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git branch
git config --global user.name "github-actions"
git config --global user.email "github-actions@users.noreply.github.com"

# Automated means that we push to a branch, otherwise we open a pull request
if [ "${SC_AUTOMATED}" == "true" ]; then
    echo "Automated PR requested"
    UPDATE_BRANCH="${SC_BRANCH_AGAINST}"
else
    UPDATE_BRANCH="update/sourcecred-cred-$(date '+%Y-%m-%d')"
fi

export UPDATE_BRANCH
echo "Branch to update is ${UPDATE_BRANCH}"
git checkout -b ${UPDATE_BRANCH}
git branch

if [ "${SC_AUTOMATED}" == "true" ]; then
    git pull origin "${UPDATE_BRANCH}" || echo "Branch not yet on remote"
    git add "${SC_TARGET}/*"
    git add "${SC_SCORES_JSON}"
    git commit -m "Automated deployment to update cred in ${SC_TARGET} $(date '+%Y-%m-%d')"
    git push origin "${UPDATE_BRANCH}"
else
    git add "${SC_TARGET}/*"
    git add "${SC_SCORES_JSON}"
    git commit -m "Automated deployment to update ${SC_TARGET} static files $(date '+%Y-%m-%d')"
    git push origin "${UPDATE_BRANCH}"
    /bin/bash -e /pull_request.sh
fi
