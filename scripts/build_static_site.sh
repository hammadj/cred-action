#!/bin/bash

# This is a modified version of
# https://github.com/sourcecred/sourcecred/blob/master/scripts/build_static_site.sh
# that is intended to be used inside of a container, and not intended to
# generate files like CNAME. The defaults are set up to be consistent
# with file locations in the container. See the Dockerfile for details.

set -eu
set -o pipefail

usage() {
    printf 'usage: build_static_site.sh --target TARGET\n'
    printf '                            [--project PROJECT [...]]\n'
    printf '                            [--project-file PROJECT_FILE [...]]\n'
    printf '                            [--weights WEIGHTS_FILE]\n'
    printf '                            [-h|--help]\n'
    printf '\n'
    printf 'Build the static SourceCred website, including example data.\n'
    printf 'This script should be run from the root of your code repository.\n'
    printf '\n'
    printf '%s\n' '--target TARGET'
    printf '\t%s\n' 'an empty directory into which to build the site'
    printf '%s\n' '--project PROJECT'
    printf '\t%s\n' 'a project spec; see help for cli/load.js for details'
    printf '%s\n' '--project-file PROJECT_FILE'
    printf '\t%s\n' 'the path to a file containing a project config'
    printf '%s\n' '--weights WEIGHTS_FILE'
    printf '\t%s\n' 'path to a json file which contains a weights configuration.'
    printf '\t%s\n' 'This will be used instead of the default weights and persisted.'
    printf '%s\n' '-h|--help'
    printf '\t%s\n' 'show this message'
}

main() {
    parse_args "$@"
    sourcecred_data=
    build
}

parse_args() {
    target=
    weights=
    repos=( )
    project_files=( )
    while [ $# -gt 0 ]; do
        case "$1" in
            --target)
                if [ -n "${target}" ]; then
                    die '--target specified multiple times'
                fi
                shift
                if [ $# -eq 0 ]; then die 'missing value for --target'; fi
                target="$1"
                ;;
            --weights)
                if [ -n "${weights}" ]; then
                    die '--weights specified multiple times'
                fi
                shift
                if [ $# -eq 0 ]; then die 'missing value for --weights'; fi
                weights="$1"
                ;;
            --project-file)
                shift
                if [ $# -eq 0 ]; then die 'missing value for --project-file'; fi
                project_files+=( "$1" )
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                printf >&2 'fatal: unknown argument: %s\n' "$1"
                exit 1
                ;;
        esac
        shift
    done
    if [ -z "${target}" ]; then
        die 'target directory not specified'
    fi
    if ! [ -e "${target}" ]; then
        mkdir -p -- "${target}"
    fi
    if ! [ -d "${target}" ]; then
        die "target is not a directory: ${target}"
    fi
    if [ "$(command ls -A "${target}" | wc -l)" != 0 ]; then
        die "target directory is nonempty: ${target}"
    fi
    target="$(readlink -e "${target}")"
    : "${SOURCECRED_BIN:=/code/bin}"
}

build() {
    if [ -z "${SOURCECRED_DIRECTORY}" ]; then
        die "SOURCECRED_DIRECTORY is empty"
    fi
    echo "Data in: ${SOURCECRED_DIRECTORY}"

    # Load project files (required)
    if [ "${#project_files[@]}" -eq 0 ]; then
        die 'project-file is required.'
    fi

    local weightsStr=""
    if [ -n "${weights}" ]; then
        weightsStr="--weights ${weights}"
    fi
    for project_file in "${project_files[@]}"; do
        NODE_PATH="/code/node_modules${NODE_PATH:+:${NODE_PATH}}" \
            node /code/bin/sourcecred.js load --project "${project_file}" $weightsStr
    done

    # Do we need to be in sourcecred directory here?
    cd /code
    yarn -s build --output-path "${target}"
    echo "Output in target ${target}:"
    ls

    # Copy the SourceCred data into the appropriate API route. Using
    # `mkdir` here will fail in the case where an `api/` folder exists,
    # which is the correct behavior. (In this case, our site's
    # architecture conflicts with the required static structure, and we
    # must fail.)
    mkdir "${target}/api/"
    mkdir "${target}/api/v1/"
    cp -r "${SOURCECRED_DIRECTORY}" "${target}/api/v1/data"
    rm -rf "${target}/api/v1/data/cache"
}

die() {
    printf >&2 'fatal: %s\n' "$@"
    exit 1
}

main "$@"
