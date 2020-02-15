#!/bin/bash

# Suggested by Github actions to be strict
# Taken from https://www.github.com/vsoch/pull-request-action
set -e
set -o pipefail

make_curl_config() {
    tmpdir="$(umask 077 && mktemp -d)"
    curl_config="${tmpdir}/curl_config"
    cat >"${curl_config}" <<EOF
--user "${GITHUB_ACTOR}"
-H "Authorization: token ${GITHUB_TOKEN}"
-H "Accept: application/vnd.github.v3+json, application/vnd.github.antiope-preview+json, application/vnd.github.shadow-cat-preview+json"
EOF
}

PULLS_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls"

################################################################################
# Helper Functions
################################################################################

check_credentials() {

    if [[ -z "${GITHUB_TOKEN}" ]]; then
        echo "You must include the GITHUB_TOKEN as an environment variable."
        exit 1
    fi

}

check_events_json() {

    if [[ ! -f "${GITHUB_EVENT_PATH}" ]]; then
        printf 'Cannot find Github events file at %s\n' "${GITHUB_EVENT_PATH}"
        exit 1
    fi
    printf 'Found %s\n' "${GITHUB_EVENT_PATH}"
    
}

create_pull_request() {

    SOURCE="${1}"  # from this branch
    TARGET="${2}"  # pull request TO this target

    # Check if the branch already has a pull request open
    if [[ -z "${TITLE}" ]]; then
        TITLE='Update SourceCred cred'
    fi
    BODY='This pull request updates static files for SourceCred.'
    DATA="{\"base\":\"${TARGET}\", \"head\":\"${SOURCE}\", \"body\":\"${BODY}\"}"
    RESPONSE=$(curl -fsSL -K "${curl_config}" -X GET --data "${DATA}" "${PULLS_URL}")
    PR=$(printf '%s\n' "${RESPONSE}" | python3 -c 'import json, sys
data = json.load(sys.stdin);
print(data[0]["head"]["ref"])')

    # Option 1: The pull request is already open
    if [[ "${PR}" == "${SOURCE}" ]]; then
        printf '%s\n' "Pull request from ${SOURCE} to ${TARGET} is already open!"

    # Option 2: Open a new pull request
    else
        # Post the pull request
        DATA="{\"title\":\"${TITLE}\", \"base\":\"${TARGET}\", \"head\":\"${SOURCE}\", \"body\":\"${BODY}\"}"
        (
            set -x;
            curl -fsSL -K "${curl_config}" -X POST --data "${DATA}" "${PULLS_URL}"
        )
        echo $?
    fi
}


main() {
    make_curl_config

    # path to file that contains the POST response of the event
    # Example: https://github.com/actions/bin/tree/master/debug
    # Value: /github/workflow/event.json
    check_events_json;

    # User specified branch for PR
    if [ -z "${UPDATE_BRANCH}" ]; then
        echo "You must specify a branch to PR from."
        exit 1
    fi
    printf '%s\n' "Branch for pull request is ${UPDATE_BRANCH}"

    if [ -z "${SC_BRANCH_AGAINST}" ]; then
        SC_BRANCH_AGAINST=master
    fi
    printf '%s\n' "Pull request will go against ${SC_BRANCH_AGAINST}"

    # Ensure we have a GitHub token
    check_credentials
    create_pull_request "${UPDATE_BRANCH}" "${SC_BRANCH_AGAINST}"

}

echo "==========================================================================
START: Creating SourceCred Cred Update Pull Request!";
main "$@"
echo "==========================================================================
END: Finished";
