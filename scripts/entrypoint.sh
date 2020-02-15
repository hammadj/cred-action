#!/bin/bash
set -eu
set -o pipefail

# This script uses the scripts/build-static-site.sh provided in the container
# and customizes the entrypoint based on what the user has provided.
# We derive variables from the environment instead of command line

if [ -z "${SC_TARGET}" ]; then
   SC_TARGET="${GITHUB_WORKSPACE}/docs"        
fi

# Show the user where we are
echo "Present working directory is:"
pwd
ls

# Clean up any previous runs (deployed in docs folder)
# This command needs to be run relative to sourcecred respository
# that is located at the WORKDIR /code
rm -rf "${SC_TARGET}"
(
    set -x;
    /bin/bash /build_static_site.sh \
        --target "${SC_TARGET}" \
        --project "${SC_PROJECT}" \
        ${SC_PROJECT_FILE:+--project-file "${GITHUB_WORKSPACE}/${SC_PROJECT_FILE}"} \
        ${SC_WEIGHTS:+--weights "${GITHUB_WORKSPACE}/${SC_WEIGHTS}"} \
        ;
)

printf 'Finished initial run, present working directory is %s\n' "${PWD}"
ls

# This interacts with node sourcecred.js
# Load it twice so we can access the scores -- it's a hack, pending real instance system
# Note from @vsoch: these variable names aren't consistent - the project here referes to the project file.
(
    set -x;
    node /code/bin/sourcecred.js load \
        --project "${GITHUB_WORKSPACE}/${SC_PROJECT_FILE}" \
        ${SC_WEIGHTS:+--weights "${GITHUB_WORKSPACE}/${SC_WEIGHTS}"} \
        ;
)
node /code/bin/sourcecred.js scores "${SC_PROJECT}" | python3 -m json.tool > "${GITHUB_WORKSPACE}/${SC_SCORES_JSON}"

# Now we want to interact with the GitHub repository
# The GitHub workspace has the root of the repository
cd "${GITHUB_WORKSPACE}"
echo "Found files in workspace:"
ls

printf 'GitHub Actor: %s\n' "${GITHUB_ACTOR}"
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
printf 'Branch to update is %s\n' "${UPDATE_BRANCH}"
git checkout -b "${UPDATE_BRANCH}"
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
