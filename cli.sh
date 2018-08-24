#!/bin/sh
#
# Command line helper for https://github.com/rycus86/githooks
#
# See the documentation in the project README for more information.
#
# Version: 1808.241831-61bf5e

print_help() {
    print_help_header

    echo "
Available commands:
    disable         Disables a hook in the current repository
    enable          Enables a previously disabled hook in the current repository
    list            Lists the active hooks in the current repository
    update-shared   Updates the shared repositories
    upgrade         Performs an update check
    help            Prints this help message

You can also execute _githooks <cmd> help_ for more information on the individual commands.
"
}

print_help_header() {
    echo
    echo "Githooks - https://github.com/rycus86/githooks"
    echo "----------------------------------------------"
}

is_running_in_git_repo_root() {
    if ! git status >/dev/null 2>&1; then
        return 1
    fi

    [ -d .git ] || return 1
}

disable_hooks() {
    echo "TODO - disable: $*"
}

enable_hooks() {
    echo "TODO - enable: $*"
}

list_hooks() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
githooks list [type]

    Lists the active hooks in the current repository along with their state.
    If _type_ is given, then it only lists the hooks for that trigger event.
    This command needs to be run at the root of a repository.
"
        return
    fi

    if ! is_running_in_git_repo_root; then
        echo "The current directory ($(pwd)) does not seem to be the root of a Git repository!"
        exit 1
    fi

    if [ -n "$*" ]; then
        LIST_TYPES="$*"
        WARN_NOT_FOUND="1"
    else
        LIST_TYPES="
        applypatch-msg pre-applypatch post-applypatch
        pre-commit prepare-commit-msg commit-msg post-commit
        pre-rebase post-checkout post-merge pre-push
        pre-receive update post-receive post-update
        push-to-checkout pre-auto-gc post-rewrite sendemail-validate"
    fi

    for LIST_TYPE in $LIST_TYPES; do
        if [ -d ".githooks/$LIST_TYPE" ]; then
            echo "> $LIST_TYPE"
            for LIST_ITEM in .githooks/"$LIST_TYPE"/*; do
                ITEM_NAME=$(basename "$LIST_ITEM")
                ITEM_STATE=$(get_hook_state "$(pwd)/.githooks/$LIST_TYPE/$ITEM_NAME")

                echo "  - $ITEM_NAME (${ITEM_STATE})"
            done

        elif [ -f ".githooks/$LIST_TYPE" ]; then
            ITEM_STATE=$(get_hook_state "$(pwd)/.githooks/$LIST_TYPE")

            echo "> $LIST_TYPE"
            echo "  File found (${ITEM_STATE})"

        elif [ -n "$WARN_NOT_FOUND" ]; then
            echo "> $LIST_TYPE"
            echo "  No active hooks found"

        fi
    done
}

get_hook_state() {
    if is_file_ignored "$1"; then
        echo "ignored"
    elif is_trusted_repo; then
        echo "active / trusted"
    else 
        get_hook_enabled_or_disabled_state "$1"
    fi
}

#####################################################
# Checks if the hook file at ${HOOK_PATH}
#   is ignored and should not be executed.
#
# Returns:
#   0 if ignored, 1 otherwise
#####################################################
is_file_ignored() {
    HOOK_NAME=$(basename "$1")
    IS_IGNORED=""

    # If there are .ignore files, read the list of patterns to exclude.
    ALL_IGNORE_FILE=$(mktemp)
    if [ -f ".githooks/.ignore" ]; then
        cat ".githooks/.ignore" >"$ALL_IGNORE_FILE"
        echo >>"$ALL_IGNORE_FILE"
    fi
    if [ -f ".githooks/${HOOK_NAME}/.ignore" ]; then
        cat ".githooks/${HOOK_NAME}/.ignore" >>"$ALL_IGNORE_FILE"
        echo >>"$ALL_IGNORE_FILE"
    fi

    # Check if the filename matches any of the ignored patterns
    while IFS= read -r IGNORED; do
        if [ -z "$IGNORED" ] || [ "$IGNORED" != "${IGNORED#\#}" ]; then
            continue
        fi

        if [ -z "${HOOK_NAME##$IGNORED}" ]; then
            IS_IGNORED="y"
            break
        fi
    done <"$ALL_IGNORE_FILE"

    # Remove the temporary file
    rm -f "$ALL_IGNORE_FILE"

    if [ -n "$IS_IGNORED" ]; then
        return 0
    else
        return 1
    fi
}

is_trusted_repo() {
    if [ -f ".githooks/trust-all" ]; then
        TRUST_ALL_CONFIG=$(git config --local --get githooks.trust.all)
        TRUST_ALL_RESULT=$?

        # shellcheck disable=SC2181
        if [ $TRUST_ALL_RESULT -ne 0 ]; then
            return 1
        elif [ $TRUST_ALL_RESULT -eq 0 ] && [ "$TRUST_ALL_CONFIG" = "Y" ]; then
            return 0
        fi
    fi

    return 1
}

get_hook_enabled_or_disabled_state() {
    HOOK_PATH="$1"

    # get hash of the hook contents
    if ! MD5_HASH=$(md5 -r "$HOOK_PATH" 2>/dev/null); then
        MD5_HASH=$(md5sum "$HOOK_PATH" 2>/dev/null)
    fi
    MD5_HASH=$(echo "$MD5_HASH" | awk "{ print \$1 }")
    CURRENT_HASHES=$(grep "$HOOK_PATH" .git/.githooks.checksum 2>/dev/null)

    # check against the previous hash
    if ! echo "$CURRENT_HASHES" | grep -q "$MD5_HASH $HOOK_PATH" >/dev/null 2>&1; then
        echo "diff: $MD5_HASH $HOOK_PATH"
        echo "chk : $CURRENT_HASHES"
        if [ -z "$CURRENT_HASHES" ]; then
            echo "pending / new"
        elif echo "$CURRENT_HASHES" | grep -q "disabled> $HOOK_PATH" >/dev/null 2>&1; then
            echo "disabled"
        else
            echo "pending / changed"
        fi
    else
        echo "active"
    fi
}

update_shared_hook_repos() {
    echo "TODO - update shared repos: $*"
}

run_update_check() {
    record_update_time
    
    if ! fetch_latest_update_script; then
        echo "Failed to fetch the update script"
        exit 1
    fi

    read_updated_version_number

    if ! is_update_available; then
        echo "  Githooks is already on the latest version"
        return
    fi

    echo "  There is a new Githooks update available: Version $LATEST_VERSION"
    echo

    read_single_repo_information

    if ! execute_update; then
        print_update_disable_info
    fi
}

#####################################################
# Saves the last update time into the
#   githooks.autoupdate.lastrun global Git config.
#
# Returns:
#   None
#####################################################
record_update_time() {
    git config --global githooks.autoupdate.lastrun "$(date +%s)"
}

#####################################################
# Loads the contents of the latest install
#   script into a variable.
#
# Sets the ${INSTALL_SCRIPT} variable
#
# Returns:
#   1 if failed the load the script, 0 otherwise
#####################################################
fetch_latest_update_script() {
    DOWNLOAD_URL="https://raw.githubusercontent.com/rycus86/githooks/master/install.sh"

    echo "Checking for updates ..."

    if curl --version >/dev/null 2>&1; then
        INSTALL_SCRIPT=$(curl -fsSL "$DOWNLOAD_URL" 2>/dev/null)

    elif wget --version >/dev/null 2>&1; then
        INSTALL_SCRIPT=$(wget -O- "$DOWNLOAD_URL" 2>/dev/null)

    else
        echo "! Cannot check for updates - needs either curl or wget"
        return 1
    fi

    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        echo "! Failed to check for updates"
        return 1
    fi
}

#####################################################
# Reads the version number of the latest
#   install script into a variable.
#
# Sets the ${LATEST_VERSION} variable
#
# Returns:
#   None
#####################################################
read_updated_version_number() {
    LATEST_VERSION=$(echo "$INSTALL_SCRIPT" | grep "^# Version: .*" | sed "s/^# Version: //")
}

#####################################################
# Checks if the latest install script is
#   newer than what we have installed already.
#
# Returns:
#   0 if the script is newer, 1 otherwise
#####################################################
is_update_available() {
    CURRENT_VERSION=$(grep "^# Version: .*" "$0" | sed "s/^# Version: //")
    UPDATE_AVAILABLE=$(echo "$CURRENT_VERSION $LATEST_VERSION" | awk "{ print (\$1 >= \$2) }")
    [ "$UPDATE_AVAILABLE" = "0" ] || return 1
}

#####################################################
# Reads whether the hooks in the current
#   local repository were installed in
#   single repository install mode.
#
# Sets the ${IS_SINGLE_REPO} variable
#
# Returns:
#   None
#####################################################
read_single_repo_information() {
    IS_SINGLE_REPO=$(git config --get --local githooks.single.install)
}

#####################################################
# Checks if the hooks in the current
#   local repository were installed in
#   single repository install mode.
#
# Returns:
#   1 if they were, 0 otherwise
#####################################################
is_single_repo() {
    [ "$IS_SINGLE_REPO" = "yes" ] || return 1
}

#####################################################
# Performs the installation of the latest update.
#
# Returns:
#   0 if the update was successful, 1 otherwise
#####################################################
execute_update() {
    if is_single_repo; then
        if sh -c "$INSTALL_SCRIPT" -- --single; then
            return 0
        fi
    else
        if sh -c "$INSTALL_SCRIPT"; then
            return 0
        fi
    fi

    return 1
}

choose_command() {
    CMD="$1"
    shift

    case "$CMD" in
    "disable")
        disable_hooks "$@"
        ;;
    "enable")
        enable_hooks "$@"
        ;;
    "list")
        list_hooks "$@"
        ;;
    "update-shared")
        update_shared_hook_repos "$@"
        ;;
    "upgrade")
        run_update_check "$@"
        ;;
    "help")
        print_help
        exit 0
        ;;
    *)
        [ -n "$CMD" ] && echo "Unknown command: $CMD"
        print_help
        exit 1
        ;;
    esac
}

choose_command "$@"
