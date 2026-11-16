#!/bin/sh
# The maintainer publishes only as dev@mainshai.com; other contributors are accepted.
# The maintainer is anyone whose name contains the surname Ferrandiz (any case, with or
# without the accent, precomposed or combining) or whose name or address contains the
# user id dferrandizmont. As committer, GitHub's noreply address is also accepted.
# No Gmail addresses (plain, %40, JSON-escaped or as HTML entities) in public files,
# file or directory names, messages or identities, and no symbolic links or submodules
# in the tree. Commits are read raw: any encoding header other than UTF-8, or an empty
# or malformed author or committer, is refused.
# staged (local, strict) | msg <file> | range <rev-list args> | ci <rev-list args>
#   | push <before> <after> (identities, messages and tags: all history up to <after>;
#     files: only the commits in before..after, or all of them if <before> is unknown)
#   | tag <rev>
set -eu
# Bytes, not characters: in a UTF-8 locale grep and sed skip names with Latin-1 bytes.
LC_ALL=C
export LC_ALL
public_email="dev@mainshai.com"
public_name='Daniel Mont Ferrandiz'
maintainer_user='dferrandizmont'
# The at sign plain, as an HTML entity (named or numeric), URL-encoded or as a JSON escape.
gmail_re='(@|&commat;|%40|\\u0040|&#0*64;|&#x0*40;)(gmail|googlemail)[.]com'
fail=0
strict=0

flag() { printf 'identity check: %s\n' "$*" >&2; fail=1; }

check_text() {
  set +e
  printf '%s\n' "$1" | LC_ALL=C grep -i -E "$gmail_re" >/dev/null
  text_rc=$?
  set -e
  case "$text_rc" in
    0) flag 'Gmail address in public text' ;;
    1) ;;
    *) flag 'could not scan public text' ;;
  esac
}

# grep -i -E status: 0 match, 1 none. Any other status counts as a match (fail closed).
grep_matches() {
  set +e
  printf '%s\n' "$2" | LC_ALL=C grep -i -E "$1" >/dev/null
  grep_rc=$?
  set -e
  [ "$grep_rc" -ne 1 ]
}

is_maintainer() {
  # The name contains the surname (any case or accent), or the name or the address
  # contains the user id. tr cannot fold multibyte UTF-8, so under the C locale any
  # accent is one or two non-ASCII bytes in place of the a (precomposed UTF-8 or
  # Latin-1), or two bytes after it (a combining mark).
  surname_re='ferr(a|[^ -~]{1,2}|a[^ -~]{2})ndiz'
  if grep_matches "$surname_re" "$1"; then return 0; fi
  if grep_matches "$maintainer_user" "$1"; then return 0; fi
  if grep_matches "$maintainer_user" "$2"; then return 0; fi
  return 1
}

check_ident() {
  # role, name, email; GitHub's identity is allowed only as committer.
  if [ -z "$2" ] || [ -z "$3" ]; then flag "$1 has an empty name or address"; return; fi
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

scan_listing() {
  # $listing: git's file listing with modes. Names are not quoted (core.quotePath=false),
  # so no escape hides a match; names with control characters stay quoted, so none can
  # forge the start of a line.
  set +e
  printf '%s\n' "$listing" | LC_ALL=C grep -i -E "$gmail_re" >/dev/null
  names_rc=$?
  printf '%s\n' "$listing" | LC_ALL=C grep -E '^(120000|160000) ' >/dev/null
  links_rc=$?
  set -e
  case "$names_rc" in
    0) flag 'Gmail address in a public file name' ;;
    1) ;;
    *) flag 'could not scan public file names' ;;
  esac
  case "$links_rc" in
    0) flag 'symbolic link or submodule in public files' ;;
    1) ;;
    *) flag 'could not scan public file modes' ;;
  esac
}

check_files() {
  # $1: a commit, or --cached for the index. Contents first, then names and links.
  set +e
  git grep -a -i -l -E -e "$gmail_re" "$1" -- . >/dev/null 2>&1
  files_rc=$?
  set -e
  case "$files_rc" in
    0) flag 'Gmail address in public files' ;;
    1) ;;
    *) flag 'could not search public files' ;;
  esac
  if [ "$1" = --cached ]; then
    if listing=$(git -c core.quotePath=false ls-files -s); then scan_listing; else
      flag 'could not list public files'
    fi
  else
    if listing=$(git -c core.quotePath=false ls-tree -r -t "$1"); then scan_listing; else
      flag 'could not list public files'
    fi
  fi
}

check_commit_ident() {
  # role, header lines of that role from the raw commit: exactly one, well formed.
  case "$2" in
    '') flag "commit has no $1"; return ;;
    *'
'*) flag "commit has more than one $1"; return ;;
  esac
  if printf '%s\n' "$2" | LC_ALL=C grep -E '^[^<>]*<[^<>]*> [0-9]+ [+-][0-9]{4}$' >/dev/null; then :; else
    flag "malformed $1"; return
  fi
  check_ident "$1" "$(printf '%s\n' "$2" | sed 's/ *<.*//')" \
    "$(printf '%s\n' "$2" | sed -n 's/^[^<]*<\([^>]*\)>.*/\1/p')"
}

check_meta() {
  # The raw object: git log recodes by the encoding header and skips extra headers
  # (mergetag, x-contact, ...), so everything is read and searched as stored.
  if raw=$(git cat-file commit "$1"); then :; else
    flag 'could not read commit'; return
  fi
  check_text "$raw"
  headers=$(printf '%s\n' "$raw" | sed '/^$/q')
  encodings=$(printf '%s\n' "$headers" | sed -n 's/^encoding //p')
  if [ -n "$encodings" ] && printf '%s\n' "$encodings" | LC_ALL=C grep -v -i -E '^utf-?8$' >/dev/null; then
    flag 'commit encoding is not UTF-8'
  fi
  check_commit_ident author "$(printf '%s\n' "$headers" | sed -n 's/^author //p')"
  check_commit_ident committer "$(printf '%s\n' "$headers" | sed -n 's/^committer //p')"
}

check_commit() {
  check_meta "$1"
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

check_push() {
  # Identities, messages and tags: all history up to $2. Files: only the commits in $1..$2.
  push_before=$1
  push_after=$2
  case "$push_before$push_after" in
    ''|*[!0-9a-fA-F]*) flag 'invalid push revisions'; return ;;
  esac
  if git cat-file -e "$push_after^{commit}" 2>/dev/null; then :; else
    flag 'pushed object is not a commit'
    return
  fi
  if revisions=$(git rev-list "$push_after"); then :; else
    flag 'could not enumerate revisions'
    return
  fi
  for revision in $revisions; do check_meta "$revision"; done
  check_tags
  file_revisions=$revisions
  case "$push_before" in
    *[!0]*)
      # A before that is missing (new branch, forced push) keeps the full-history check.
      if git cat-file -e "$push_before^{commit}" 2>/dev/null; then
        if file_revisions=$(git rev-list "$push_before..$push_after"); then :; else
          flag 'could not enumerate pushed revisions'
          return
        fi
      fi
      ;;
  esac
  for revision in $file_revisions; do check_files "$revision"; done
}

check_tag_chain() {
  tag_object=$1
  while :; do
    if object_type=$(git cat-file -t "$tag_object"); then :; else
      flag 'could not read tag object'; return
    fi
    if [ "$object_type" != tag ]; then
      # A tag, annotated or not, must end at a commit, never at a blob or a tree.
      [ "$object_type" = commit ] || flag 'tag does not point to a commit'
      return
    fi
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
  push)
    [ "$#" -eq 3 ] || { printf 'usage: %s push <before> <after>\n' "$0" >&2; exit 2; }
    check_push "$2" "$3"
    ;;
  *) printf 'usage: %s staged | msg <file> | range <revs> | ci <revs> | push <before> <after> | tag <rev>\n' "$0" >&2; exit 2 ;;
esac
[ "$fail" -eq 0 ]
