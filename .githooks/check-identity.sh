#!/bin/sh
# The maintainer (name Daniel Mont Ferrandiz, or an address containing the user id
# dferrandizmont) publishes only as dev@mainshai.com; other contributors are accepted.
# No Gmail addresses in public files, messages or identities.
# staged (local, strict) | msg <file> | range <rev-list args> | ci <rev-list args> | tag <rev>
set -eu
public_email="dev@mainshai.com"
public_name='Daniel Mont Ferrandiz'
maintainer_user='dferrandizmont'
gmail_re='@(gmail[.]com|googlemail[.]com)'
fail=0
strict=0

flag() { printf 'identity check: %s\n' "$*" >&2; fail=1; }

check_text() {
  set +e
  printf '%s\n' "$1" | grep -i -E "$gmail_re" >/dev/null
  text_rc=$?
  set -e
  case "$text_rc" in
    0) flag 'Gmail address in public text' ;;
    1) ;;
    *) flag 'could not scan public text' ;;
  esac
}

is_maintainer() {
  # name is the maintainer's, or the address contains the maintainer's user id.
  lower_name=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  lower_email=$(printf '%s' "$2" | tr 'A-Z' 'a-z')
  [ "$lower_name" = "$(printf '%s' "$public_name" | tr 'A-Z' 'a-z')" ] && return 0
  case "$lower_email" in *"$maintainer_user"*) return 0 ;; esac
  return 1
}

check_ident() {
  # role, name, email; GitHub's identity is allowed only as committer.
  check_text "$2 <$3>"
  if [ "$strict" -eq 1 ]; then
    # Local hooks: this machine belongs to the maintainer.
    if [ "$3" = "$public_email" ] && [ "$2" = "$public_name" ]; then return; fi
  else
    # CI and push checks: other contributors are accepted as they are.
    is_maintainer "$2" "$3" || return 0
    if [ "$3" = "$public_email" ]; then return; fi
  fi
  if [ "$1" = committer ] && [ "$3" = noreply@github.com ]; then return; fi
  flag "$1 must use the public identity"
}

check_files() {
  set +e
  git grep -a -i -l -E -e "$gmail_re" "$@" -- . >/dev/null 2>&1
  files_rc=$?
  set -e
  case "$files_rc" in
    0) flag 'Gmail address in public files' ;;
    1) ;;
    *) flag 'could not search public files' ;;
  esac
}

check_commit() {
  check_ident author "$(git log -1 --format=%an "$1")" "$(git log -1 --format=%ae "$1")"
  check_ident committer "$(git log -1 --format=%cn "$1")" "$(git log -1 --format=%ce "$1")"
  check_text "$(git log -1 --format=%B "$1")"
  check_files "$1"
}

check_range() {
  # Capture output and status: a failing substitution in a for loop is lost.
  if revisions=$(git rev-list "$@"); then :; else
    flag 'could not enumerate revisions'
    return
  fi
  for revision in $revisions; do check_commit "$revision"; done
  check_tags
}

check_tag_chain() {
  tag_object=$1
  while :; do
    if object_type=$(git cat-file -t "$tag_object"); then :; else
      flag 'could not read tag object'; return
    fi
    [ "$object_type" = tag ] || return 0
    if tag_data=$(git cat-file -p "$tag_object"); then :; else
      flag 'could not read annotated tag'; return
    fi
    tagger=$(printf '%s\n' "$tag_data" | sed -n '/^$/q; s/^tagger //p')
    tag_name=$(printf '%s\n' "$tagger" | sed 's/ <.*//')
    tag_email=$(printf '%s\n' "$tagger" | sed -n 's/.*<\([^>]*\)>.*/\1/p')
    check_ident tagger "$tag_name" "$tag_email"
    check_text "$tag_data"
    tag_object=$(printf '%s\n' "$tag_data" | sed -n '1s/^object //p')
    [ -n "$tag_object" ] || { flag 'tag has no target'; return; }
  done
}

check_tags() {
  if tags=$(git for-each-ref --format='%(refname)' refs/tags); then :; else
    flag 'could not enumerate tags'; return
  fi
  for tag in $tags; do check_tag_chain "$tag"; done
}

case "${1:-}" in
  staged)
    strict=1
    author=$(git var GIT_AUTHOR_IDENT)
    committer=$(git var GIT_COMMITTER_IDENT)
    check_ident author "$(printf '%s\n' "$author" | sed 's/ <.*//')" "$(printf '%s\n' "$author" | sed -n 's/.*<\([^>]*\)>.*/\1/p')"
    check_ident committer "$(printf '%s\n' "$committer" | sed 's/ <.*//')" "$(printf '%s\n' "$committer" | sed -n 's/.*<\([^>]*\)>.*/\1/p')"
    check_files --cached
    ;;
  msg) check_text "$(cat "$2")" ;;
  tag) check_tag_chain "$2" ;;
  range|ci) shift; check_range "$@" ;;
  *) printf 'usage: %s staged | msg <file> | range <revs> | ci <revs>\n' "$0" >&2; exit 2 ;;
esac
[ "$fail" -eq 0 ]
