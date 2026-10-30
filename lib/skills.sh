#!/usr/bin/env bash
# caveman-kit — shared skill helpers, sourced by install.sh and update.sh
# (ADR 0020, ADR 0021). Bash 3.2 compatible (macOS /bin/bash): no associative
# arrays, no ${var,,}. Functions print to stdout/stderr and return status;
# none of them exits the calling script.

SKILL_REPO="JuliusBrussee/caveman"
# Git URL used for the release-tag lookup. Overridable for tests only.
SKILL_REMOTE="${CAVEMAN_KIT_SKILL_REMOTE:-https://github.com/JuliusBrussee/caveman}"
SKILL_RELEASES_URL="https://github.com/JuliusBrussee/caveman/releases"
# First upstream release that ships the ultracave skill (ADR 0021 decision 3).
SKILL_MIN_TAG="v3.1.0"

# valid_tag <tag>: strict vMAJOR.MINOR.PATCH, no prerelease suffix.
valid_tag() {
  # [[ =~ ]] matches the whole string; grep would accept a multi-line value
  # whose first line is a tag.
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# tag_ge <a> <b>: true when version a >= version b (both valid tags).
tag_ge() {
  local first
  first="$(printf '%s\n%s\n' "${1#v}" "${2#v}" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)"
  [ "$first" = "${2#v}" ]
}

# latest_release_tag: print the highest vX.Y.Z tag of the upstream repo.
# Fails (non-zero, nothing printed) on a network/git error or an empty tag set.
latest_release_tag() {
  local out tag
  # GIT_TERMINAL_PROMPT=0: a 401 fails instead of prompting on the tty.
  out="$(GIT_TERMINAL_PROMPT=0 git ls-remote --tags --refs "$SKILL_REMOTE" 2>/dev/null)" || return 1
  tag="$(printf '%s\n' "$out" | sed -n 's|.*refs/tags/||p' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -1)"
  [ -n "$tag" ] || return 1
  printf '%s\n' "$tag"
}

# ultracave_present <claude dir>: SKILL.md readable with a non-empty body after
# frontmatter. A directory without such a file counts as missing (ADR 0020
# decision 1).
ultracave_present() {
  local f="$1/skills/ultracave/SKILL.md"
  [ -r "$f" ] || return 1
  awk '
    NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm == 1 { if (/^---[[:space:]]*$/) fm = 2; next }
    /[^[:space:]]/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$f"
}

# install_skill <tag> <skill>: one npx call for one skill, pinned to the tag.
install_skill() {
  GH_HOST=github.com GH_TOKEN= GITHUB_TOKEN= npx --yes skills add "$SKILL_REPO@$1" --skill "$2" -a claude-code -g -y --copy
}

# manual_skill_cmd <skill> [tag]: the command a user can run by hand. Always
# pinned: with the placeholder and the releases page when no tag is known
# (ADR 0021 decision 7). Never prints an unpinned command.
manual_skill_cmd() {
  local skill="$1" tag="${2:-}"
  if [ -n "$tag" ]; then
    echo "npx skills add $SKILL_REPO@$tag --skill $skill -a claude-code -g --copy"
  else
    echo "npx skills add $SKILL_REPO@<tag> --skill $skill -a claude-code -g --copy   (<tag>: use the newest vX.Y.Z release from $SKILL_RELEASES_URL)"
  fi
}

# check_override <value>: 0 when the value is a vX.Y.Z tag >= SKILL_MIN_TAG.
check_override() {
  valid_tag "$1" && tag_ge "$1" "$SKILL_MIN_TAG"
}
