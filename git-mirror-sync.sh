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

REMOTE_BRANCH_LIST=($(git branch -r | grep -v '\->' | grep "${REMOTE}/"))
TAG_LIST=($(git tag -l | grep -v '^last-sync/'))

function tag_last_sync()
{
    local cmd
    local branch
    for branch in "${REMOTE_BRANCH_LIST[@]}"
    do
        cmd="git tag -f last-sync/${branch} ${branch}"
        if [ "$DRY_RUN" = "1" ]; then
            echo "$cmd"
        else
            eval "$cmd"
	    fi
    done

    # save tags as msg
    local tagmsg="$(printf "%s\n" "${TAG_LIST[@]}")"
    cmd="git tag -f -a -m \"\$tagmsg\" last-sync/tag-list ${REMOTE}/HEAD"
    if [ "$DRY_RUN" = "1" ]; then
        echo "$tagmsg"
        echo "$cmd"
    else
        eval "$cmd"
    fi
}

function create_full_bundle()
{
    local bundle_file="$1"
    shift
    [ -z "$bundle_file" ] && help
    local branch_list=("${REMOTE_BRANCH_LIST[@]}")
    local rev_list=("${branch_list[@]}")
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
    local now_branch_list=("${REMOTE_BRANCH_LIST[@]}")
    local last_branch_list=($(git tag -l | grep "^last-sync/${REMOTE}/" | sed 's,^last-sync/,,'))
    local new_branch_list=($(diff --new-line-format="%L" --old-line-format="" --unchanged-line-format="" <(printf "%s\n" "${last_branch_list[@]}" | sort) <(printf "%s\n" "${now_branch_list[@]}" | sort)  | grep -v '^$'))
    local last_tag_list=($(git describe --tags last-sync/tag-list >/dev/null 2>&1 && git tag -l --format='%(contents)' last-sync/tag-list))
    local new_tag_list=($(diff --new-line-format="%L" --old-line-format="" --unchanged-line-format="" <(printf "%s\n" "${last_tag_list[@]}" | sort) <(printf "%s\n" "${TAG_LIST[@]}" | sort)  | grep -v '^$'))

    local rev_list=()
    rev_list+=($(for i in "${last_branch_list[@]}"; do echo "last-sync/${i}..${i}"; done))
    rev_list+=("${new_branch_list[@]}")
    rev_list+=($(for i in "${new_tag_list[@]}"; do echo "tags/${i}"; done))
    rev_list+=("$@")
    local cmd="git bundle create ${bundle_file} ${rev_list[@]}"
    if [ "$DRY_RUN" = "1" ]; then
        echo "$cmd"
        return
    fi
    eval "$cmd" && git bundle list-heads ${bundle_file}
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
    echo "       list-tags          show tags"
    echo "       full BUNDLE_FILE   make full bundle save to BUNDLE_FILE"
    echo "       inc  BUNDLE_FILE   make inc bundle save to BUNDLE_FILE, range is (last, current]"
    echo "       tag                mark current position as last"
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
    list-branch) printf "%s\n" "${REMOTE_BRANCH_LIST[@]}" ;;
    list-tags)   printf "%s\n" "${TAG_LIST[@]}" ;;
    *)    help ;;
    esac
}

main "$@"

