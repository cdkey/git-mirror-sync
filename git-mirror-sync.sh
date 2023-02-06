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

REMOTE="origin"
DRY_RUN="0"

function get_remote_branch_list()
{
    git branch -r | grep -v '\->' | grep "^ *${REMOTE}/" | sed 's,^ *,,' | grep -v '^$'
}

function get_synced_branch_list()
{
    git tag -l | grep "^last-sync/${REMOTE}/" | sed 's,^last-sync/,,' | grep -v '^$'
}

function get_remote_tag_list()
{
    #realtime remote tags
    local remote_tags_name=($(git ls-remote --refs --tags "${REMOTE}" | grep -v '\trefs/tags/last-sync/' | sed 's,.*\trefs/tags/,,' | grep -v '^$'))
    local local_remote_tags=($(git show-ref --tags | grep -v ' refs/tags/last-sync/' | sed 's, refs/tags/,:,g' | grep -v '^$'))
    local filter_rule="$(printf ":%s\$|" "${remote_tags_name[@]}")"
    printf "%s\n" "${local_remote_tags[@]}" | grep -E "${filter_rule%|}"
}

function get_synced_tag_list()
{
    if git show-ref --verify --quiet refs/tags/last-sync/tag-list >/dev/null 2>&1 ; then
        git tag -l --format='%(contents)' last-sync/tag-list
    fi
}

function diff_inc()
{
    local file1="${1:-/dev/stdin}"
    local file2="${2:-/dev/stdin}"

    diff --new-line-format="%L" --old-line-format="" --unchanged-line-format="" <(cat "$file1" | sort) <(cat "$file2" | sort) | grep -v '^$'
}

function tag_last_sync()
{
    local cmd
    local branch
    local remote_branch_list=($(get_remote_branch_list))
    for branch in "${remote_branch_list[@]}"
    do
        cmd="git tag -f last-sync/${branch} ${branch}"
        if [ "$DRY_RUN" = "1" ]; then
            echo "$cmd"
        else
            eval "$cmd"
        fi
    done

    # save tags as msg
    local newtagmsg="$(get_remote_tag_list)"
    local curtagmsg="$(get_synced_tag_list)"
    cmd="git tag -f -a -F - last-sync/tag-list ${REMOTE}/HEAD"
    if [ "$DRY_RUN" = "1" ]; then
        echo "$newtagmsg"
        echo "$cmd"
    else
        if [ "$newtagmsg" != "$curtagmsg" ]; then
            echo "$newtagmsg" | eval "$cmd"
        fi
    fi
}

function create_full_bundle()
{
    local bundle_file="$1"
    shift
    [ -z "$bundle_file" ] && help
    local rev_list=($(get_remote_branch_list))
    rev_list+=("$@")
    local cmd="git bundle create ${bundle_file} --exclude=refs/tags/last-sync/* --tags=* ${rev_list[@]}"
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
    local remote_branch_list=($(get_remote_branch_list))
    local synced_branch_list=($(get_synced_branch_list))
    local new_branch_list=($(diff_inc <(printf "%s\n" "${synced_branch_list[@]}") <(printf "%s\n" "${remote_branch_list[@]}")))
    local new_tag_list=($(diff_inc <(get_synced_tag_list) <(get_remote_tag_list)))

    local rev_list=()
    rev_list+=($(for i in "${synced_branch_list[@]}"; do git show-ref --verify --quiet refs/remotes/${i} >/dev/null 2>&1 && echo "last-sync/${i}..${i}"; done))
    rev_list+=("${new_branch_list[@]}")
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
    echo "[branch]" > "$pos_file"
    local i
    local remote_branch_list=($(get_remote_branch_list))
    for i in "${remote_branch_list[@]}"; do
        git show-ref refs/remotes/${i} | sed 's, refs/remotes/,:,g'
    done >> "$pos_file"
    echo "[tag]" >> "$pos_file"
    git show-ref --tags | grep -v ' refs/tags/last-sync/' | sed 's, refs/tags/,:,g' | grep -v '^$' >> "$pos_file"
}

function import_position()
{
    local pos_file="${1:-/dev/stdin}"
    shift
    [ -z "$pos_file" ] && help
    local content="$(cat $pos_file)"
    local line cmd
    while read line; do
        local hash="${line%:*}"
        local branch="${line#*:}"

        cmd="git tag -f last-sync/${branch} ${hash}"
        if [ "$DRY_RUN" = "1" ]; then
            echo "$cmd"
        else
            eval "$cmd"
        fi
    done <<< $(echo "${content}" | sed -n '/\[branch\]/,/\[tag\]/p' | grep -vE '\[|\]')

    # save tags as msg
    local tagmsg="$(echo "${content}" | sed -n '/\[tag\]/,$p' | grep -vE '\[|\]')"
    cmd="git tag -f -a -F - last-sync/tag-list ${REMOTE}/HEAD"
    if [ "$DRY_RUN" = "1" ]; then
        echo "$tagmsg"
        echo "$cmd"
    else
        echo "$tagmsg" | eval "$cmd"
    fi
}

function do_list_branch()
{
    echo "Remote ${REMOTE} branch:"
    get_remote_branch_list

    echo ""

    echo "Deleted synced branch:"
    diff_inc <(get_remote_branch_list) <(get_synced_branch_list)
}

function do_list_tags()
{
    echo "Remote ${REMOTE} tags:"
    get_remote_tag_list
}

function do_prune_tags()
{
    local deleted_branch_list=($(diff_inc <(get_remote_branch_list) <(get_synced_branch_list)))
    local branch
    for branch in "${deleted_branch_list[@]}" ; do
        local cmd="git tag -d last-sync/${branch}"
        if [ "$DRY_RUN" = "1" ]; then
            echo "$cmd"
        else
            eval "$cmd"
        fi
    done
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
    echo "       tag                mark current position as last"
    echo "       prune-tags         prune deleted synced tags"
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
    tag)  tag_last_sync ;;
    full) create_full_bundle "$@" ;;
    inc)  create_inc_bundle "$@" ;;
    list-branch) do_list_branch "$@" ;;
    list-tags)   do_list_tags "$@" ;;
    prune-tags)  do_prune_tags "$@" ;;
    export) export_position "$@" ;;
    import) import_position "$@" ;;
    *)    help ;;
    esac
}

main "$@"

