#!/bin/sh
#
# Command line helper for https://github.com/rycus86/githooks
#
# This tool provides a convenience utility to manage
#   Githooks configuration, hook files and other
#   related functionality.
# This script should be an alias for `git hooks`, done by
#   git config --global alias.hooks "!${SCRIPT_DIR}/githooks"
#
# See the documentation in the project README for more information,
#   or run the `git hooks help` command for available options.
#
# Version: 1809.041830-7295cd

#####################################################
# Prints the command line help for usage and
#   available commands.
#####################################################
print_help() {
    print_help_header

    echo "
Available commands:

    disable     Disables a hook in the current repository
    enable      Enables a previously disabled hook in the current repository
    accept      Accepts the pending changes of a new or modified hook
    trust       Manages settings related to trusted repositories
    list        Lists the active hooks in the current repository
    shared      Manages the shared hook repositories
    pull        Updates the shared repositories
    update      Performs an update check
    readme      Manages the Githooks README in the current repository
    version     Prints the version number of this script
    help        Prints this help message

You can also execute \`git hooks <cmd> help\` for more information on the individual commands.
"
}

#####################################################
# Prints a general header to be included
#   as the first few lines of every help message.
#####################################################
print_help_header() {
    echo
    echo "Githooks - https://github.com/rycus86/githooks"
    echo "----------------------------------------------"
}

#####################################################
# Checks if the current directory is
#   a Git repository or not.
#
# Returns:
#   0 if it is likely a Git repository,
#   1 otherwise
#####################################################
is_running_in_git_repo_root() {
    if ! git status >/dev/null 2>&1; then
        return 1
    fi

    [ -d .git ] || return 1
}

#####################################################
# Finds a hook file path based on trigger name,
#   file name, relative or absolute path, or
#   some combination of these.
#
# Sets the ${HOOK_PATH} environment variable.
#
# Returns:
#   None
#####################################################
find_hook_path_to_enable_or_disable() {
    if [ -z "$1" ]; then
        HOOK_PATH=$(cd .githooks && pwd)

    elif [ -n "$1" ] && [ -n "$2" ]; then
        HOOK_TARGET="$(pwd)/.githooks/$1/$2"
        if [ -e "$HOOK_TARGET" ]; then
            HOOK_PATH="$HOOK_TARGET"
        fi

    elif [ -n "$1" ]; then
        if [ -e "$1" ]; then
            HOOK_DIR=$(dirname "$1")
            HOOK_NAME=$(basename "$1")

            if [ "$HOOK_NAME" = "." ]; then
                HOOK_PATH=$(cd "$HOOK_DIR" && pwd)
            else
                HOOK_PATH=$(cd "$HOOK_DIR" && pwd)/"$HOOK_NAME"
            fi

        elif [ -f ".githooks/$1" ]; then
            HOOK_PATH=$(cd .githooks && pwd)/"$1"

        else
            for HOOK_DIR in .githooks/*; do
                HOOK_ITEM=$(basename "$HOOK_DIR")
                if [ "$HOOK_ITEM" = "$1" ]; then
                    HOOK_PATH=$(cd "$HOOK_DIR" && pwd)
                fi

                if [ ! -d "$HOOK_DIR" ]; then
                    continue
                fi

                HOOK_DIR=$(cd "$HOOK_DIR" && pwd)

                for HOOK_FILE in "$HOOK_DIR"/*; do
                    HOOK_ITEM=$(basename "$HOOK_FILE")
                    if [ "$HOOK_ITEM" = "$1" ]; then
                        HOOK_PATH="$HOOK_FILE"
                    fi
                done
            done
        fi
    fi

    if [ -z "$HOOK_PATH" ]; then
        echo "Sorry, cannot find any hooks that would match that"
        exit 1
    elif echo "$HOOK_PATH" | grep -qv "/.githooks"; then
        if [ -d "$HOOK_PATH/.githooks" ]; then
            HOOK_PATH="$HOOK_PATH/.githooks"
        else
            echo "Sorry, cannot find any hooks that would match that"
            exit 1
        fi
    fi
}

#####################################################
# Creates the Githooks checksum file
#   for the repository if it does not exist yet.
#####################################################
ensure_checksum_file_exists() {
    touch .git/.githooks.checksum
}

#####################################################
# Disables one or more hook files
#   in the current repository.
#
# Returns:
#   1 if the current directory is not a Git repo,
#   0 otherwise
#####################################################
disable_hook() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks disable [trigger] [hook-script]
git hooks disable [hook-script]
git hooks disable [trigger]
git hooks disable [-a|--all]
git hooks disable [-r|--reset]

    Disables a hook in the current repository.
    The \`trigger\` parameter should be the name of the Git event if given.
    The \`hook-script\` can be the name of the file to disable, or its
    relative path, or an absolute path, we will try to find it.
    The \`--all\` parameter on its own will disable running any Githooks
    in the current repository, both existing ones and any future hooks.
    The \`--reset\` parameter is used to undo this, and let hooks run again.
"
        return
    fi

    if ! is_running_in_git_repo_root; then
        echo "The current directory ($(pwd)) does not seem to be the root of a Git repository!"
        exit 1
    fi

    if [ "$1" = "-a" ] || [ "$1" = "--all" ]; then
        git config githooks.disable Y &&
            echo "All existing and future hooks are disabled in the current repository" &&
            return

        echo "! Failed to disable hooks in the current repository"
        exit 1

    elif [ "$1" = "-r" ] || [ "$1" = "--reset" ]; then
        git config --unset githooks.disable

        if ! git config --get githooks.single.install; then
            echo "Githooks hook files are not disabled anymore by default" && return
        else
            echo "! Failed to re-enable Githooks hook files"
            exit 1
        fi
    fi

    find_hook_path_to_enable_or_disable "$@"
    ensure_checksum_file_exists

    for HOOK_FILE in $(find "$HOOK_PATH" -type f | grep "/.githooks/"); do
        if grep -q "disabled> $HOOK_FILE" .git/.githooks.checksum 2>/dev/null; then
            echo "Hook file is already disabled at $HOOK_FILE"
            continue
        fi

        echo "disabled> $HOOK_FILE" >>.git/.githooks.checksum
        echo "Hook file disabled at $HOOK_FILE"
    done
}

#####################################################
# Enables one or more hook files
#   in the current repository.
#
# Returns:
#   1 if the current directory is not a Git repo,
#   0 otherwise
#####################################################
enable_hook() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks enable [trigger] [hook-script]
git hooks enable [hook-script]
git hooks enable [trigger]

    Enables a hook or hooks in the current repository.
    The \`trigger\` parameter should be the name of the Git event if given.
    The \`hook-script\` can be the name of the file to enable, or its
    relative path, or an absolute path, we will try to find it.
"
        return
    fi

    if ! is_running_in_git_repo_root; then
        echo "The current directory ($(pwd)) does not seem to be the root of a Git repository!"
        exit 1
    fi

    find_hook_path_to_enable_or_disable "$@"
    ensure_checksum_file_exists

    sed "\\|disabled> $HOOK_PATH|d" .git/.githooks.checksum >.git/.githooks.checksum.tmp &&
        mv .git/.githooks.checksum.tmp .git/.githooks.checksum &&
        echo "Hook file(s) enabled at $HOOK_PATH"
}

#####################################################
# Accept changes to a new or existing but changed
#   hook file by recording its checksum as accepted.
#
# Returns:
#   1 if the current directory is not a Git repo,
#   0 otherwise
#####################################################
accept_changes() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks accept [trigger] [hook-script]
git hooks accept [hook-script]
git hooks accept [trigger]

    Accepts a new hook or changes to an existing hook.
    The \`trigger\` parameter should be the name of the Git event if given.
    The \`hook-script\` can be the name of the file to enable, or its
    relative path, or an absolute path, we will try to find it.
"
        return
    fi

    if ! is_running_in_git_repo_root; then
        echo "The current directory ($(pwd)) does not seem to be the root of a Git repository!"
        exit 1
    fi

    find_hook_path_to_enable_or_disable "$@"
    ensure_checksum_file_exists

    for HOOK_FILE in $(find "$HOOK_PATH" -type f | grep "/.githooks/"); do
        if grep -q "disabled> $HOOK_FILE" .git/.githooks.checksum; then
            echo "Hook file is currently disabled at $HOOK_FILE"
            continue
        fi

        CHECKSUM=$(get_hook_checksum "$HOOK_FILE")

        echo "$CHECKSUM $HOOK_FILE" >>.git/.githooks.checksum &&
            echo "Changes accepted for $HOOK_FILE"
    done
}

#####################################################
# Returns the MD5 checksum of the hook file
#   passed in as the first argument.
#####################################################
get_hook_checksum() {
    # get hash of the hook contents
    if ! MD5_HASH=$(md5 -r "$1" 2>/dev/null); then
        MD5_HASH=$(md5sum "$1" 2>/dev/null)
    fi

    echo "$MD5_HASH" | awk "{ print \$1 }"
}

#####################################################
# Manage settings related to trusted repositories.
#   It allows setting up and clearing marker
#   files and Git configuration.
#
# Returns:
#   1 on failure, 0 otherwise
#####################################################
manage_trusted_repo() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks trust
git hooks trust [revoke]
git hooks trust [delete]
git hooks trust [forget]

    Sets up, or reverts the trusted setting for the local repository.
    When called without arguments, it marks the local repository as trusted.
    The \`revoke\` argument resets the already accepted trust setting,
    and the \`delete\` argument also deletes the trusted marker.
    The \`forget\` option unsets the trust setting, asking for accepting
    it again next time, if the repository is marked as trusted.
"
        return
    fi

    if ! is_running_in_git_repo_root; then
        echo "The current directory ($(pwd)) does not seem to be the root of a Git repository!"
        exit 1
    fi

    if [ -z "$1" ]; then
        mkdir -p .githooks &&
            touch .githooks/trust-all &&
            git config githooks.trust.all Y &&
            echo "The current repository is now trusted." &&
            echo "  Do not forget to commit and push the trust marker!" &&
            return

        echo "! Failed to mark the current repository as trusted"
        exit 1
    fi

    if [ "$1" = "forget" ]; then
        if [ -z "$(git config --local --get githooks.trust.all)" ]; then
            echo "The current repository does not have trust settings."
            return
        elif git config --unset githooks.trust.all; then
            echo "The current repository is no longer trusted."
            return
        else
            echo "! Failed to revoke the trusted setting"
            exit 1
        fi

    elif [ "$1" = "revoke" ] || [ "$1" = "delete" ]; then
        if git config githooks.trust.all N; then
            echo "The current repository is no longer trusted."
        else
            echo "! Failed to revoke the trusted setting"
            exit 1
        fi

        if [ "$1" = "revoke" ]; then
            return
        fi
    fi

    if [ "$1" = "delete" ] || [ -f .githooks/trust-all ]; then
        rm -rf .githooks/trust-all &&
            echo "The trust marker is removed from the repository." &&
            echo "  Do not forget to commit and push the change!" &&
            return

        echo "! Failed to delete the trust marker"
        exit 1
    fi

    echo "! Unknown subcommand: $1"
    echo "  Run \`git hooks trust help\` to see the available options."
    exit 1
}

#####################################################
# Lists the hook files in the current
#   repository along with their current state.
#
# Returns:
#   1 if the current directory is not a Git repo,
#   0 otherwise
#####################################################
list_hooks() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks list [type]

    Lists the active hooks in the current repository along with their state.
    If \`type\` is given, then it only lists the hooks for that trigger event.
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
        LIST_OUTPUT=""

        # non-Githooks hook file
        if [ -x ".git/hooks/${LIST_TYPE}.replaced.githook" ]; then
            ITEM_STATE=$(get_hook_state "$(pwd)/.git/hooks/${LIST_TYPE}.replaced.githook")
            LIST_OUTPUT="$LIST_OUTPUT
  - $LIST_TYPE (previous / file / ${ITEM_STATE})"
        fi

        # global shared hooks
        SHARED_REPOS_LIST=$(git config --global --get githooks.shared)
        for SHARED_ITEM in $(list_hooks_in_shared_repos "$LIST_TYPE"); do
            if [ -d "$SHARED_ITEM" ]; then
                for LIST_ITEM in "$SHARED_ITEM"/*; do
                    ITEM_NAME=$(basename "$LIST_ITEM")
                    ITEM_STATE=$(get_hook_state "$LIST_ITEM")
                    LIST_OUTPUT="$LIST_OUTPUT
  - $ITEM_NAME (${ITEM_STATE} / shared:global)"
                done

            elif [ -f "$SHARED_ITEM" ]; then
                ITEM_STATE=$(get_hook_state "$SHARED_ITEM")
                LIST_OUTPUT="$LIST_OUTPUT
  - $LIST_TYPE (file / ${ITEM_STATE} / shared:global)"
            fi
        done

        # local shared hooks
        if [ -f "$(pwd)/.githooks/.shared" ]; then
            SHARED_REPOS_LIST=$(grep -E "^[^#].+$" <"$(pwd)/.githooks/.shared")
            for SHARED_ITEM in $(list_hooks_in_shared_repos "$LIST_TYPE"); do
                if [ -d "$SHARED_ITEM" ]; then
                    for LIST_ITEM in "$SHARED_ITEM"/*; do
                        ITEM_NAME=$(basename "$LIST_ITEM")
                        ITEM_STATE=$(get_hook_state "$LIST_ITEM")
                        LIST_OUTPUT="$LIST_OUTPUT
  - $ITEM_NAME (${ITEM_STATE} / shared:local)"
                    done

                elif [ -f "$SHARED_ITEM" ]; then
                    ITEM_STATE=$(get_hook_state "$SHARED_ITEM")
                    LIST_OUTPUT="$LIST_OUTPUT
  - $LIST_TYPE (file / ${ITEM_STATE} / shared:local)"
                fi
            done
        fi

        # in the current repository
        if [ -d ".githooks/$LIST_TYPE" ]; then
            for LIST_ITEM in .githooks/"$LIST_TYPE"/*; do
                ITEM_NAME=$(basename "$LIST_ITEM")
                ITEM_STATE=$(get_hook_state "$(pwd)/.githooks/$LIST_TYPE/$ITEM_NAME")
                LIST_OUTPUT="$LIST_OUTPUT
  - $ITEM_NAME (${ITEM_STATE})"
            done

        elif [ -f ".githooks/$LIST_TYPE" ]; then
            ITEM_STATE=$(get_hook_state "$(pwd)/.githooks/$LIST_TYPE")
            LIST_OUTPUT="$LIST_OUTPUT
  - $LIST_TYPE (file / ${ITEM_STATE})"

        fi

        if [ -n "$LIST_OUTPUT" ]; then
            echo "> ${LIST_TYPE}${LIST_OUTPUT}"

        elif [ -n "$WARN_NOT_FOUND" ]; then
            echo "> $LIST_TYPE"
            echo "  No active hooks found"

        fi
    done
}

#####################################################
# Returns the state of hook file
#   in a human-readable format
#   on the standard output.
#####################################################
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
    if [ -f ".githooks/${LIST_TYPE}/.ignore" ]; then
        cat ".githooks/${LIST_TYPE}/.ignore" >>"$ALL_IGNORE_FILE"
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

#####################################################
# Checks whether the current repository
#   is trusted, and that this is accepted.
#
# Returns:
#   0 if the repo is trusted, 1 otherwise
#####################################################
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

#####################################################
# Returns the enabled or disabled state
#   in human-readable format for a hook file
#   passed in as the first argument.
#####################################################
get_hook_enabled_or_disabled_state() {
    HOOK_PATH="$1"

    # get hash of the hook contents
    if ! MD5_HASH=$(md5 -r "$HOOK_PATH" 2>/dev/null); then
        MD5_HASH=$(md5sum "$HOOK_PATH" 2>/dev/null)
    fi
    MD5_HASH=$(echo "$MD5_HASH" | awk "{ print \$1 }")
    CURRENT_HASHES=$(grep "$HOOK_PATH" .git/.githooks.checksum 2>/dev/null)

    # check against the previous hash
    if echo "$CURRENT_HASHES" | grep -q "disabled> $HOOK_PATH" >/dev/null 2>&1; then
        echo "disabled"
    elif ! echo "$CURRENT_HASHES" | grep -q "$MD5_HASH $HOOK_PATH" >/dev/null 2>&1; then
        if [ -z "$CURRENT_HASHES" ]; then
            echo "pending / new"
        else
            echo "pending / changed"
        fi
    else
        echo "active"
    fi
}

#####################################################
# List the shared hooks from the
#   ~/.githooks/shared directory.
#
# Returns the list of paths to the hook files
#   in the shared hook repositories found locally.
#####################################################
list_hooks_in_shared_repos() {
    if [ ! -d ~/.githooks/shared ]; then
        return
    fi

    SHARED_LIST_TYPE="$1"

    for SHARED_ROOT in ~/.githooks/shared/*; do
        REMOTE_URL=$(cd "$SHARED_ROOT" && git config --get remote.origin.url)
        ACTIVE_REPO=$(echo "$SHARED_REPOS_LIST" | grep -o "$REMOTE_URL")
        if [ "$ACTIVE_REPO" != "$REMOTE_URL" ]; then
            continue
        fi

        if [ -e "${SHARED_ROOT}/.githooks/${SHARED_LIST_TYPE}" ]; then
            echo "${SHARED_ROOT}/.githooks/${SHARED_LIST_TYPE}"
        elif [ -e "${SHARED_ROOT}/${LIST_TYPE}" ]; then
            echo "${SHARED_ROOT}/${LIST_TYPE}"
        fi
    done
}

manage_shared_hook_repos() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks shared [add|remove] [--global|--local] <git-url>
git hooks shared clear [--global|--local|--all]
git hooks shared list [--global|--local] [--with-url]
git hooks shared [update|pull]

    Manages the shared hook repositories set either globally, or locally within the repository.
    The \`add\` or \`remove\` subcommands adds or removes an item, given as \`git-url\` from the list.
    If \`--global\` is given, then the \`githooks.shared\` global Git configuration is modified, or if the
    \`--local\` option (default) is set, the \`.githooks/.shared\` file is modified in the local repository.
    The \`clear\` subcommand deletes every item on either the global or the local list,
    or both when the \`--all\` option is given.
    The \`update\` or \`pull\` subcommands update all the shared repositories, both global and local, either by
    running \`git pull\` on existing ones or \`git clone\` on new ones.
"

        return
    fi

    if [ "$1" = "update" ] || [ "$1" = "pull" ]; then
        update_shared_hook_repos
        return
    fi

    if [ "$1" = "clear" ]; then
        shift
        clear_shared_hook_repos "$@"
        return
    fi

    if [ "$1" = "list" ]; then
        shift
        list_shared_hook_repos "$@"
        return
    fi

    if [ "$1" = "add" ]; then
        shift
        add_shared_hook_repo "$@"
        return
    fi

    if [ "$1" = "remove" ]; then
        shift
        remove_shared_hook_repo "$@"
        return
    fi

    echo "! Unknown subcommand: \`$1\`"
    exit 1
}

add_shared_hook_repo() {
    SET_SHARED_GLOBAL=
    SHARED_REPO_URL=

    case "$1" in
    "--global")
        SET_SHARED_GLOBAL=1
        SHARED_REPO_URL="$2"
        ;;
    "--local")
        SET_SHARED_GLOBAL=
        SHARED_REPO_URL="$2"
        ;;
    *)
        SHARED_REPO_URL="$1"
        ;;
    esac

    if [ -z "$SHARED_REPO_URL" ]; then
        echo "! Usage: \`git hooks shared add [--global|--local] <git-url>\`"
        exit 1
    fi

    if [ -n "$SET_SHARED_GLOBAL" ]; then
        CURRENT_LIST=$(git config --global --get githooks.shared)

        if [ -n "$CURRENT_LIST" ]; then
            NEW_LIST="${CURRENT_LIST},${SHARED_REPO_URL}"
        else
            NEW_LIST="$SHARED_REPO_URL"
        fi

        git config --global githooks.shared "$NEW_LIST" &&
            echo "The new shared hook repository is successfully added" &&
            return

        echo "! Failed to add the new shared hook repository"
        exit 1

    else
        [ -f "$(pwd)/.githooks/.shared" ] &&
            echo "" >>"$(pwd)/.githooks/.shared"

        echo "# Added on $(date)" >>"$(pwd)/.githooks/.shared" &&
            echo "$SHARED_REPO_URL" >>"$(pwd)/.githooks/.shared" &&
            echo "The new shared hook repository is successfully added" &&
            echo "  Do not forget to commit in the change!" &&
            return

        echo "! Failed to add the new shared hook repository"
        exit 1

    fi
}

remove_shared_hook_repo() {
    SET_SHARED_GLOBAL=
    SHARED_REPO_URL=

    case "$1" in
    "--global")
        SET_SHARED_GLOBAL=1
        SHARED_REPO_URL="$2"
        ;;
    "--local")
        SET_SHARED_GLOBAL=
        SHARED_REPO_URL="$2"
        ;;
    *)
        SHARED_REPO_URL="$1"
        ;;
    esac

    if [ -z "$SHARED_REPO_URL" ]; then
        echo "! Usage: \`git hooks shared remove [--global|--local] <git-url>\`"
        exit 1
    fi

    if [ -n "$SET_SHARED_GLOBAL" ]; then
        CURRENT_LIST=$(git config --global --get githooks.shared)
        NEW_LIST=""

        IFS=",
        "

        for SHARED_REPO_ITEM in $CURRENT_LIST; do
            if [ "$SHARED_REPO_ITEM" = "$SHARED_REPO_URL" ]; then
                continue
            fi

            if [ -z "$NEW_LIST" ]; then
                NEW_LIST="$SHARED_REPO_ITEM"
            else
                NEW_LIST="${NEW_LIST},${SHARED_REPO_ITEM}"
            fi
        done

        unset IFS

        if [ -z "$NEW_LIST" ]; then
            clear_shared_hook_repos "--global" && return || exit 1
        fi

        git config --global githooks.shared "$NEW_LIST" &&
            echo "The list of shared hook repositories is successfully changed" &&
            return

        echo "! Failed to remove a shared hook repository"
        exit 1

    else
        IFS=",
        "

        echo "TODO"
        
        [ -f "$(pwd)/.githooks/.shared" ] &&
            echo "" >>"$(pwd)/.githooks/.shared"

        echo "# Added on $(date)" >>"$(pwd)/.githooks/.shared" &&
            echo "$SHARED_REPO_URL" >>"$(pwd)/.githooks/.shared" &&
            echo "The new shared hook repository is successfully added" &&
            echo "  Do not forget to commit in the change!" &&
            return

        echo "! Failed to add the new shared hook repository"
        exit 1
        
    fi
}

clear_shared_hook_repos() {
    CLEAR_GLOBAL_REPOS=
    CLEAR_LOCAL_REPOS=

    case "$1" in
    "--global")
        CLEAR_GLOBAL_REPOS=1
        ;;
    "--local")
        CLEAR_LOCAL_REPOS=1
        ;;
    "--all")
        CLEAR_GLOBAL_REPOS=1
        CLEAR_LOCAL_REPOS=1
        ;;
    *)
        echo "! One of the following must be used:"
        echo "  git hooks shared clear --global"
        echo "  git hooks shared clear --local"
        echo "  git hooks shared clear --all"
        exit 1
        ;;
    esac

    if [ -n "$CLEAR_GLOBAL_REPOS" ] && [ -n "$(git config --global --get githooks.shared)" ]; then
        git config --global --unset githooks.shared &&
            echo "Global shared hook repository list cleared" ||
            CLEAR_REPOS_FAILED=1
    fi

    if [ -n "$CLEAR_LOCAL_REPOS" ] && [ -f "$(pwd)/.githooks/.shared" ]; then
        rm -f "$(pwd)/.githooks/.shared" &&
            echo "Local shared hook repository list cleared" ||
            CLEAR_REPOS_FAILED=1
    fi

    if [ -n "$CLEAR_REPOS_FAILED" ]; then
        echo "! There were some problems clearing the shared hook repository list"
        exit 1
    fi
}

list_shared_hook_repos() {
    # git hooks shared list [--global|--local] [--with-url]
    echo "TODO"
}

#####################################################
# Updates the configured shared hook repositories.
#
# Returns:
#   None
#####################################################
update_shared_hook_repos() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks pull

    Updates the shared repositories found either
    in the global Git configuration, or in the
    \`.githooks/.shared\` file in the local repository.
"
        return
    fi

    SHARED_HOOKS=$(git config --global --get githooks.shared)
    if [ -n "$SHARED_HOOKS" ]; then
        update_shared_hooks_in "$SHARED_HOOKS"
    fi

    if [ -f "$(pwd)/.githooks/.shared" ]; then
        SHARED_HOOKS=$(grep -E "^[^#].+$" <"$(pwd)/.githooks/.shared")
        update_shared_hooks_in "$SHARED_HOOKS"
    fi

    echo "Finished"
}

#####################################################
# Updates the shared hooks repositories
#   on the list passed in on the first argument.
#####################################################
update_shared_hooks_in() {
    SHARED_REPOS_LIST="$1"

    # split on comma and newline
    IFS=",
    "

    for SHARED_REPO in $SHARED_REPOS_LIST; do
        mkdir -p ~/.githooks/shared

        NORMALIZED_NAME=$(echo "$SHARED_REPO" |
            sed -E "s#.*[:/](.+/.+)\\.git#\\1#" |
            sed -E "s/[^a-zA-Z0-9]/_/g")

        if [ -d ~/.githooks/shared/"$NORMALIZED_NAME"/.git ]; then
            echo "* Updating shared hooks from: $SHARED_REPO"
            PULL_OUTPUT=$(cd ~/.githooks/shared/"$NORMALIZED_NAME" && git pull 2>&1)
            # shellcheck disable=SC2181
            if [ $? -ne 0 ]; then
                echo "! Update failed, git pull output:"
                echo "$PULL_OUTPUT"
            fi
        else
            echo "* Retrieving shared hooks from: $SHARED_REPO"
            CLONE_OUTPUT=$(cd ~/.githooks/shared && git clone "$SHARED_REPO" "$NORMALIZED_NAME" 2>&1)
            # shellcheck disable=SC2181
            if [ $? -ne 0 ]; then
                echo "! Clone failed, git clone output:"
                echo "$CLONE_OUTPUT"
            fi
        fi
    done

    unset IFS
}

#####################################################
# Executes an update check, and potentially
#   the installation of the latest version.
#
# Returns:
#   1 if the latest version cannot be retrieved,
#   0 otherwise
#####################################################
run_update_check() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks update [force]
git hooks update [enable|disable]

    Executes an update check for a newer Githooks version.
    If it finds one, or if \`force\` was given, the downloaded
    install script is executed for the latest version.
    The \`enable\` and \`disable\` options enable or disable
    the automatic checks that would normally run daily
    after a successful commit event.
"
        return
    fi

    if [ "$1" = "enable" ]; then
        git config --global githooks.autoupdate.enabled Y &&
            echo "Automatic update checks have been enabled" &&
            return

        echo "! Failed to enable automatic updates" && exit 1

    elif [ "$1" = "disable" ]; then
        git config --global githooks.autoupdate.enabled N &&
            echo "Automatic update checks have been disabled" &&
            return

        echo "! Failed to disable automatic updates" && exit 1
    fi

    record_update_time

    if ! fetch_latest_update_script; then
        echo "Failed to fetch the update script"
        exit 1
    fi

    read_updated_version_number

    if [ "$1" != "force" ]; then
        if ! is_update_available; then
            echo "  Githooks is already on the latest version"
            return
        fi
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
    LATEST_VERSION=$(echo "$INSTALL_SCRIPT" | grep "^# Version: .*" | head -1 | sed "s/^# Version: //")
}

#####################################################
# Checks if the latest install script is
#   newer than what we have installed already.
#
# Returns:
#   0 if the script is newer, 1 otherwise
#####################################################
is_update_available() {
    CURRENT_VERSION=$(grep "^# Version: .*" "$0" | head -1 | sed "s/^# Version: //")
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

#####################################################
# Prints the version number of this script,
#   that would match the latest installed version
#   of Githooks in most cases.
#####################################################
print_current_version_number() {
    if [ "$1" = "help" ]; then
        print_help_header
        echo "
git hooks version

    Prints the version number of the \`git hooks\` helper and exits.
"

        return
    fi

    CURRENT_VERSION=$(grep "^# Version: .*" "$0" | head -1 | sed "s/^# Version: //")

    print_help_header

    echo
    echo "Version: $CURRENT_VERSION"
    echo
}

#####################################################
# Adds or updates the Githooks README in
#   the current local repository.
#
# Returns:
#   1 on failure, 0 otherwise
#####################################################
manage_readme_file() {
    case "$1" in
    "add")
        FORCE_README=""
        ;;
    "update")
        FORCE_README="y"
        ;;
    *)
        print_help_header
        echo "
git hooks readme [add|update]

    Adds or updates the Githooks README in the \`.githooks\` folder.
    If \`add\` is used, it checks first if there is a README file already.
    With \`update\`, the file is always updated, creating it if necessary.
    This command needs to be run at the root of a repository.
"
        if [ "$1" = "help" ]; then
            exit 0
        else
            exit 1
        fi
        ;;
    esac

    if ! is_running_in_git_repo_root; then
        echo "The current directory ($(pwd)) does not seem to be the root of a Git repository!"
        exit 1
    fi

    if [ -f .githooks/README.md ] && [ "$FORCE_README" != "y" ]; then
        echo "! This repository already seems to have a Githooks README."
        echo "  If you would like to replace it with the latest one, please run \`git hooks readme update\`"
        exit 1
    fi

    if ! fetch_latest_readme; then
        exit 1
    fi

    mkdir -p "$(pwd)/.githooks" &&
        printf "%s" "$README_CONTENTS" >"$(pwd)/.githooks/README.md" &&
        echo "The README file is updated, do not forget to commit and push it!" ||
        echo "! Failed to update the README file in the current repository"
}

#####################################################
# Loads the contents of the latest Githooks README
#   into a variable.
#
# Sets the ${README_CONTENTS} variable
#
# Returns:
#   1 if failed the load the contents, 0 otherwise
#####################################################
fetch_latest_readme() {
    DOWNLOAD_URL="https://raw.githubusercontent.com/rycus86/githooks/master/.githooks/README.md"

    if curl --version >/dev/null 2>&1; then
        README_CONTENTS=$(curl -fsSL "$DOWNLOAD_URL" 2>/dev/null)

    elif wget --version >/dev/null 2>&1; then
        README_CONTENTS=$(wget -O- "$DOWNLOAD_URL" 2>/dev/null)

    else
        echo "! Failed to fetch the latest README - needs either curl or wget"
        return 1
    fi

    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        echo "! Failed to fetch the latest README"
        return 1
    fi
}

#####################################################
# Dispatches the command to the
#   appropriate helper function to process it.
#
# Returns:
#   1 if an unknown command was given,
#   the exit code of the command otherwise
#####################################################
choose_command() {
    CMD="$1"
    [ -n "$CMD" ] && shift

    case "$CMD" in
    "disable")
        disable_hook "$@"
        ;;
    "enable")
        enable_hook "$@"
        ;;
    "accept")
        accept_changes "$@"
        ;;
    "trust")
        manage_trusted_repo "$@"
        ;;
    "list")
        list_hooks "$@"
        ;;
    "shared")
        manage_shared_hook_repos "$@"
        ;;
    "pull")
        update_shared_hook_repos "$@"
        ;;
    "update")
        run_update_check "$@"
        ;;
    "readme")
        manage_readme_file "$@"
        ;;
    "version")
        print_current_version_number "$@"
        ;;
    "help")
        print_help
        ;;
    *)
        [ -n "$CMD" ] && echo "Unknown command: $CMD"
        print_help
        exit 1
        ;;
    esac
}

# Choose and execute the command
choose_command "$@"
