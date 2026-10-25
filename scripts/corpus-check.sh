#!/bin/sh
# Checks the vendored conformance corpus against its own manifest and its
# recorded source, by the corpus README's rule ("Running the cases", steps
# 1 and 2):
#
#   - conformance/SOURCE.json holds exactly repo, tag, sha and corpus_hash,
#     and names the reference's repository, the tag and the commit this
#     script expects;
#   - manifest.json is corpus version 1, its corpus_hash is SOURCE.json's,
#     and it lists case files by case_count, file and kind, with nothing
#     else;
#   - each case file is case_count lines, each ended by a newline, none of
#     them empty, and each carries a case id that starts with its kind;
#   - the SHA-256 of the case files' bytes, concatenated in the manifest's
#     order, is the manifest's corpus_hash.
#
# A mismatch fails the check. It is never repaired by rewriting a hash or
# a count: the vendored files are the tag's bytes, and a new corpus is
# vendored whole, with this script's expected tag and commit, from a new
# tag.
#
# POSIX sh and the POSIX utilities only, no jq: the manifest is one line
# of JSON with sorted keys and no whitespace (the corpus README, "The
# format"), so sed and tr read it. The SHA-256 comes from sha256sum,
# shasum or openssl, whichever is installed.
#
#   sh scripts/corpus-check.sh
set -eu

expected_repo="riddler/uxid-ex"
expected_tag="v2.10.0"
expected_sha="57235777cb29c70f751552ce7aa20ab5fe71fb74"

root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/conformance"
errors=0

fail() {
  printf 'corpus: %s\n' "$1" >&2
  errors=$((errors + 1))
}

stop() {
  printf 'corpus: %s\n' "$1" >&2
  exit 1
}

# The keys of the JSON object text in $1, in order, one per line: every
# quoted name followed by a colon. Only for the flat objects read here.
keys_of() {
  printf '%s\n' "$1" | tr ',{}' '\n\n\n' | sed -n 's/^ *"\([a-z_]*\)" *:.*/\1/p'
}

# The string value of key $2 in the JSON object text $1.
string_of() {
  printf '%s\n' "$1" | tr -d '\n' | sed -n "s/.*\"$2\" *: *\"\\([^\"]*\\)\".*/\\1/p"
}

# The integer value of key $2 in the JSON object text $1.
integer_of() {
  printf '%s\n' "$1" | tr -d '\n' | sed -n "s/.*\"$2\" *: *\\([0-9][0-9]*\\).*/\\1/p"
}

# Fails the check unless the object text $1 (named $2) has exactly the keys
# $3, space-separated in their order.
want_keys() {
  got="$(keys_of "$1" | tr '\n' ' ' | sed 's/ $//')"
  if [ "$got" != "$3" ]; then
    stop "$2 has the keys \"$got\", expected exactly \"$3\""
  fi
}

sha256_of_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d ' ' -f 1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d ' ' -f 1
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | sed 's/^.*= *//'
  else
    stop "no sha256sum, shasum or openssl to hash with"
  fi
}

[ -f "$dir/SOURCE.json" ] || stop "no conformance/SOURCE.json"
[ -f "$dir/manifest.json" ] || stop "no conformance/manifest.json"

source_json="$(cat "$dir/SOURCE.json")"
want_keys "$source_json" "SOURCE.json" "repo tag sha corpus_hash"
repo="$(string_of "$source_json" repo)"
tag="$(string_of "$source_json" tag)"
sha="$(string_of "$source_json" sha)"
source_hash="$(string_of "$source_json" corpus_hash)"
[ "$repo" = "$expected_repo" ] ||
  fail "SOURCE.json repo is \"$repo\", expected \"$expected_repo\""
[ "$tag" = "$expected_tag" ] ||
  fail "SOURCE.json tag is \"$tag\", expected \"$expected_tag\""
[ "$sha" = "$expected_sha" ] ||
  fail "SOURCE.json sha is \"$sha\", expected \"$expected_sha\""

manifest_lines="$(wc -l < "$dir/manifest.json" | tr -d ' ')"
[ "$manifest_lines" = "1" ] ||
  stop "manifest.json is $manifest_lines lines, expected one line"
manifest="$(cat "$dir/manifest.json")"
top="$(printf '%s\n' "$manifest" | sed 's/"files":\[[^]]*\]/"files":0/')"
want_keys "$top" "manifest.json" "corpus_hash corpus_version files"
version="$(integer_of "$manifest" corpus_version)"
manifest_hash="$(string_of "$top" corpus_hash)"
[ "$version" = "1" ] ||
  fail "manifest.json corpus_version is \"$version\"; this check knows version 1"
case "$manifest_hash" in
  sha256:*) ;;
  *) stop "manifest.json corpus_hash \"$manifest_hash\" is not sha256:<hex>" ;;
esac
[ "$manifest_hash" = "$source_hash" ] ||
  fail "manifest.json corpus_hash $manifest_hash differs from SOURCE.json's $source_hash"

# One manifest entry per line, in the manifest's order.
entries="$(printf '%s\n' "$manifest" |
  sed -n 's/.*"files":\[\([^]]*\)\].*/\1/p' |
  tr '}' '\n' |
  sed -n 's/^,\{0,1\}{\(.*\)$/{\1}/p')"
[ -n "$entries" ] || stop "manifest.json lists no case files"

files=""
file_count=0
cases=0
while IFS= read -r entry; do
  file_count=$((file_count + 1))
  what="manifest.json files[$((file_count - 1))]"
  want_keys "$entry" "$what" "case_count file kind"
  file="$(string_of "$entry" file)"
  kind="$(string_of "$entry" kind)"
  case_count="$(integer_of "$entry" case_count)"
  case "$file" in
    *[!a-z.]* | .* | *..* | '') stop "$what names \"$file\", not a case file name" ;;
    *.json) ;;
    *) stop "$what names \"$file\", not a case file name" ;;
  esac
  [ -f "$dir/$file" ] || stop "$what names $file, which is not in conformance/"
  [ -n "$case_count" ] || stop "$what has no integer case_count"
  lines="$(wc -l < "$dir/$file" | tr -d ' ')"
  [ "$lines" = "$case_count" ] ||
    fail "$file has $lines lines, manifest.json says case_count $case_count"
  if [ -s "$dir/$file" ]; then
    last="$(tail -c 1 "$dir/$file" | od -An -to1 | tr -d ' \n')"
    [ "$last" = "012" ] || fail "$file does not end with a newline"
  fi
  empty="$(grep -c '^$' "$dir/$file" || true)"
  [ "$empty" = "0" ] || fail "$file has $empty empty lines"
  ids="$(grep -c "\"id\":\"$kind/" "$dir/$file" || true)"
  [ "$ids" = "$lines" ] ||
    fail "$file has $ids lines with a case id starting $kind/, of $lines"
  files="$files $file"
  cases=$((cases + case_count))
done <<ENTRIES
$entries
ENTRIES

# The case files' bytes, concatenated in the manifest's order. The names
# are checked above to be lower-case letters and .json, so the unquoted
# list splits on the spaces between them only.
hash="sha256:$(cd "$dir" && cat $files | sha256_of_stdin)"
[ "$hash" = "$manifest_hash" ] ||
  fail "the case files hash to $hash, manifest.json says $manifest_hash"

if [ "$errors" -ne 0 ]; then
  printf 'corpus: %s check(s) failed in conformance/\n' "$errors" >&2
  exit 1
fi
printf 'corpus: %s (%s), %s case files, %s cases, %s\n' \
  "$tag" "$sha" "$file_count" "$cases" "$hash"
