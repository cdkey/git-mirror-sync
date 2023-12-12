:<<!
 * Copyright (c) 2022 Ding Hui
 * git-mirror-sync is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *          http://license.coscl.org.cn/MulanPSL2
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 * See the Mulan PSL v2 for more details.
 * Author: dinghui
 * Create: 2022-06-24 
 * Description: tools for git repo offline sync
!
#!/bin/bash

REMOTE="${GMS_REMOTE:-origin}"
DRY_RUN="0"
SNAP_ID="${GMS_ID:-0}"
SNAP_TAG="last-sync/snapshot"
SNAP_MAX=10

function die()
{
    echo "Error: $1"
    [ "$#" -gt 1 ] && exit "$2"
}

function get_remote_branch_name()
{
    git branch -r | grep -v '\->' | grep "^ *${REMOTE}/" | sed 's,^ *,,' | grep -v '^$'
    [ "${PIPESTATUS[0]}" -ne 0 ] && die "${FUNCNAME}" 1
}

# Output Format:
# commit-id:branch-name
# ...
function get_remote_branch_commit()
{
    git branch -r --format="%(objectname):%(refname:short)" --sort="-committerdate" | grep ":${REMOTE}/" | grep -v ":${REMOTE}/HEAD\$"
    [ "${PIPESTATUS[0]}" -ne 0 ] && die "${FUNCNAME}" 1
}

# Output Format:
# commit-id:branch-name
# ...
function get_synced_branch_commit()
{
    if git show-ref --verify --quiet refs/tags/"${SNAP_TAG}-${SNAP_ID}" >/dev/null 2>&1 ; then
        git tag -l --format='%(contents)' "${SNAP_TAG}-${SNAP_ID}" | grep '^b:' | sed 's/^b://'
    fi
}

function get_synced_branch_name()
{
    get_synced_branch_commit | sed 's/^[^:]*://'
}

G_REMOTE_TAG_COMMIT_CACHE=""
# Output Format:
# commit-id:tag-name
# ...
function get_remote_tag_commit()
{
    [ -n "$G_REMOTE_TAG_COMMIT_CACHE" ] && { echo "$G_REMOTE_TAG_COMMIT_CACHE"; return; }
    #realtime remote tags
    local remote_tags_name
    remote_tags_name=($(git ls-remote --refs --tags "${REMOTE}" | grep -v '\trefs/tags/last-sync/' | sed 's,.*\trefs/tags/,,' | grep -v '^$'; exit ${PIPESTATUS[0]}))
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1
    local local_remote_tags
    local_remote_tags=($(git show-ref --tags | grep -v ' refs/tags/last-sync/' | sed 's, refs/tags/,:,g' | grep -v '^$'; exit ${PIPESTATUS[0]}))
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1
    local filter_rule="$(printf ":%s\$|" "${remote_tags_name[@]}")"
    G_REMOTE_TAG_COMMIT_CACHE="$(printf "%s\n" "${local_remote_tags[@]}" | grep -E "${filter_rule%|}")"
    echo "$G_REMOTE_TAG_COMMIT_CACHE" | grep -v '^$'
}

function get_remote_tag_name()
{
    get_remote_tag_commit | sed 's/^[^:]*://'
    [ "${PIPESTATUS[0]}" -ne 0 ] && die "${FUNCNAME}" 1
}

# Output Format:
# commit-id:tag-name
# ...
function get_synced_tag_commit()
{
    if git show-ref --verify --quiet refs/tags/"${SNAP_TAG}-${SNAP_ID}" >/dev/null 2>&1 ; then
        git tag -l --format='%(contents)' "${SNAP_TAG}-${SNAP_ID}" | grep '^t:' | sed 's/^t://'
    fi
}

function get_synced_tag_name()
{
    get_synced_tag_commit | sed 's/^[^:]*://'
}

function check_commit_valid()
{
    git rev-parse -q --verify "$1^{commit}" >/dev/null
}

function diff_inc()
{
    local file1="${1:-/dev/stdin}"
    local file2="${2:-/dev/stdin}"

    diff --new-line-format="%L" --old-line-format="" --unchanged-line-format="" <(cat "$file1" | sort) <(cat "$file2" | sort) | grep -v '^$'
}

function roll_snapshot()
{
    local i
    local cmd
    for ((i=SNAP_MAX-2; i>=SNAP_ID; i--)) ; do
        git show-ref --verify --quiet refs/tags/"${SNAP_TAG}-${i}" >/dev/null 2>&1 || continue
        cmd="git tag -f ${SNAP_TAG}-$((i+1)) ${SNAP_TAG}-${i}"
        [ "$DRY_RUN" = "1" ] && echo "$cmd" || eval "$cmd"
    done
}

# Save Format:
# last-commit-date
# ---
# b:commit-id:branch-name
# ...
# ---
# t:commit-id:tag-name
# ...
function tag_last_sync()
{
    local with_old="${1:-0}"
    local cmd filter_rule
    local remote_commit_branch synced_commit_branch last_commit_date
    local remote_commit_tag synced_commit_tag
    local old_name_list old_commit_branch old_commit_tag

    remote_commit_branch="$(get_remote_branch_commit | sed 's/^/b:/')"
    synced_commit_branch="$(get_synced_branch_commit | sed 's/^/b:/')"
    last_commit_date="$(git show -s --format="%ci" $(head -n1 <<<"${remote_commit_branch}" | awk -F: '{print $2}'))"

    remote_commit_tag="$(get_remote_tag_commit | sed 's/^/t:/')"
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1
    synced_commit_tag="$(get_synced_tag_commit | sed 's/^/t:/')"
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1

    if [ "$with_old" -ne 0 ]; then
        old_name_list=($(diff_inc <(get_remote_branch_name) <(get_synced_branch_name)))
        filter_rule="$(printf "^b:[^:]*:%s\$|" "${old_name_list[@]}")"
        old_commit_branch="$(echo "$synced_commit_branch" | grep -E "${filter_rule%|}")"
        old_name_list=($(diff_inc <(get_remote_tag_name) <(get_synced_tag_name)))
        filter_rule="$(printf "^t:[^:]*:%s\$|" "${old_name_list[@]}")"
        old_commit_tag="$(echo "$synced_commit_tag" | grep -E "${filter_rule%|}")"
    fi

    # save snapshot as tag msg
    local newtagmsg="$(printf "%s\n---\n%s\n---\n%s\n---\n%s\n---\n%s\n"  "$last_commit_date" "$remote_commit_branch" "$old_commit_branch" "$remote_commit_tag" "$old_commit_tag")"
    local curtagmsg=""
    if git show-ref --verify --quiet refs/tags/"${SNAP_TAG}-${SNAP_ID}" >/dev/null 2>&1 ; then
        curtagmsg="$(git tag -l --format='%(contents)' ${SNAP_TAG}-${SNAP_ID})"
    fi
    cmd="git tag -f -a -F - ${SNAP_TAG}-${SNAP_ID} ${REMOTE}/HEAD"
    if [ "$DRY_RUN" = "1" ]; then
        roll_snapshot
        echo "$newtagmsg"
        echo "$cmd"
    else
        if [ "$newtagmsg" != "$curtagmsg" ]; then
            roll_snapshot
            echo "$newtagmsg" | eval "$cmd"
        fi
    fi
}

function create_full_bundle()
{
    local bundle_file="$1"
    shift
    [ -z "$bundle_file" ] && help
    local rev_list
    rev_list=($(get_remote_branch_name))
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1
    local tag_name_list
    tag_name_list=($(get_remote_tag_name))
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1
    if [ "${#tag_name_list[@]}" -gt 0 ]; then
        rev_list+=($(printf "tags/%s\n" "${tag_name_list[@]}"))
    fi
    rev_list+=("$@")
    local cmd="git bundle create ${bundle_file} ${rev_list[@]}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "$cmd"
        return
    fi
    eval "$cmd" && git bundle list-heads ${bundle_file}
}

function create_inc_bundle()
{
    local bundle_file="$1"
    shift
    [ -z "$bundle_file" ] && help
    local remote_branch_list=($(get_remote_branch_commit))
    local synced_branch_list=($(get_synced_branch_commit))
    local new_branch_list=($(diff_inc <(printf "%s\n" "${synced_branch_list[@]}") <(printf "%s\n" "${remote_branch_list[@]}")))
    local synced_tags remote_tags
    synced_tags="$(get_synced_tag_commit)"
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1
    remote_tags="$(get_remote_tag_commit)"
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1
    local new_tag_list=($(diff_inc <(echo "$synced_tags") <(echo "$remote_tags")))

    local rev_list=()
    rev_list+=($(for i in "${synced_branch_list[@]}"; do check_commit_valid "${i%:*}" && echo "^${i%:*}"; done))
    rev_list+=($(for i in "${new_branch_list[@]}"; do check_commit_valid "${i%:*}" && echo "${i#*:}"; done))
    rev_list+=($(for i in "${new_tag_list[@]}"; do echo "tags/${i#*:}"; done))
    rev_list+=("$@")
    local cmd="git bundle create ${bundle_file} ${rev_list[@]}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "$cmd"
        return
    fi
    eval "$cmd" && git bundle list-heads ${bundle_file}
}

function export_position()
{
    local pos_file="${1:-/dev/stdout}"
    shift
    [ -z "$pos_file" ] && help
    local remote_commit_branch last_commit_date remote_commit_tag

    remote_commit_branch="$(get_remote_branch_commit | sed 's/^/b:/')"
    last_commit_date="$(git show -s --format="%ci" $(head -n1 <<<"${remote_commit_branch}" | awk -F: '{print $2}'))"

    remote_commit_tag="$(get_remote_tag_commit | sed 's/^/t:/'; exit ${PIPESTATUS[0]})"
    [ $? -ne 0 ] && die "${FUNCNAME}" 1

    printf "%s\n---\n%s\n---\n%s\n"  "$last_commit_date" "$remote_commit_branch" "$remote_commit_tag"
}

function import_position()
{
    local pos_file="${1:-/dev/stdin}"
    shift
    [ -z "$pos_file" ] && help
    local content="$(cat $pos_file)"

    # save snapshot as tag msg
    local cmd="git tag -f -a -F - ${SNAP_TAG}-${SNAP_ID} ${REMOTE}/HEAD"
    if [ "$DRY_RUN" = "1" ]; then
        roll_snapshot
        echo "$content"
        echo "$cmd"
    else
        roll_snapshot
        echo "$content" | eval "$cmd"
    fi
}

function do_list_branch()
{
    echo "Remote ${REMOTE} branch:"
    get_remote_branch_name

    echo ""

    echo "Deleted synced branch:"
    diff_inc <(get_remote_branch_name) <(get_synced_branch_name)
}

function do_list_tags()
{
    echo "Remote ${REMOTE} tags:"
    get_remote_tag_commit
    [ "$?" -ne 0 ] && die "${FUNCNAME}" 1

    echo ""

    echo "Deleted synced tags:"
    diff_inc <(get_remote_tag_name) <(get_synced_tag_name)
}

function help()
{
    echo "Usage: $0 [-n] ACTION [arg...]"
    echo ""
    echo "OPTION:"
    echo "       -n                 dry run"
    echo ""
    echo "ACTION:"
    echo "       list-branch        show remote branch"
    echo "       list-tags          show remote tags"
    echo "       full BUNDLE_FILE   make full bundle save to BUNDLE_FILE"
    echo "       inc  BUNDLE_FILE   make inc bundle save to BUNDLE_FILE, range is (last, current]"
    echo "       tag                save current position to tag ${SNAP_TAG}-${SNAP_ID} (with deleted)"
    echo "       tag-c              save current position to tag ${SNAP_TAG}-${SNAP_ID} (cleanup)"
    echo "       export [FILE]      export current position to FILE (default to stdout)"
    echo "       import [FILE]      import current position from FILE (default from stdin)"
    exit 0
}

function main()
{
    local action="$1"
    shift
    if [ "$action" = "-n" ]; then
        DRY_RUN="1"
        action="$1"
        shift
    fi
    case "$action" in
    tag)    tag_last_sync "1" ;;
    tag-c)  tag_last_sync "0" ;;
    full) create_full_bundle "$@" ;;
    inc)  create_inc_bundle "$@" ;;
    list-branch) do_list_branch "$@" ;;
    list-tags)   do_list_tags "$@" ;;
    export) export_position "$@" ;;
    import) import_position "$@" ;;
    *)    help ;;
    esac
}

main "$@"

