#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/replay-bundle-commit.sh [--dry-run] [--allow-dirty] [--bundle PATH] COMMIT

Replays one commit from pdfium-bundle into this repository layout:
  - pdfium-lib/... changes are applied inside the pdfium-lib submodule.
  - pdfium-render/... changes are applied inside the pdfium-render submodule.
  - all other changes are applied at the superproject root.

The source pdfium-bundle commits are expected to predate the submodule split,
so this script strips the top-level project directory when applying submodule
patches.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_clean() {
  local repo=$1
  local label=$2

  if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
    die "$label has uncommitted changes; commit, stash, or clean it before replaying"
  fi
}

has_diff() {
  local bundle_repo=$1
  local parent=$2
  local commit=$3
  shift 3

  ! git -C "$bundle_repo" diff --quiet --binary "$parent" "$commit" -- "$@"
}

strip_path_components() {
  local path=$1
  local count=$2

  for ((i = 0; i < count; i++)); do
    path=${path#*/}
  done

  printf '%s\n' "$path"
}

seed_missing_modified_paths() {
  local bundle_repo=$1
  local target_repo=$2
  local parent=$3
  local commit=$4
  local strip=$5
  shift 5

  local status source_path target_path target_file target_dir source_strip
  source_strip=$((strip - 1))
  while IFS= read -r -d '' status; do
    IFS= read -r -d '' source_path

    case "$status" in
      M|T)
        target_path=$(strip_path_components "$source_path" "$source_strip")
        target_file=$target_repo/$target_path

        if [[ ! -e "$target_file" ]]; then
          target_dir=$(dirname "$target_file")
          mkdir -p "$target_dir"
          git -C "$bundle_repo" show "$parent:$source_path" > "$target_file"
          git -C "$target_repo" add -- "$target_path"
          echo "  seeded missing base file $target_path"
        fi
        ;;
    esac
  done < <(git -C "$bundle_repo" diff --name-status -z --diff-filter=MT "$parent" "$commit" -- "$@")
}

apply_diff() {
  local bundle_repo=$1
  local target_repo=$2
  local parent=$3
  local commit=$4
  local strip=$5
  local dry_run=$6
  shift 6

  local apply_args=(apply "--binary" "-p$strip")
  if [[ "$dry_run" == "1" ]]; then
    apply_args+=("--check" "--3way")
  else
    apply_args+=("--3way")
    seed_missing_modified_paths "$bundle_repo" "$target_repo" "$parent" "$commit" "$strip" "$@"
  fi

  git -C "$bundle_repo" diff --binary "$parent" "$commit" -- "$@" |
    git -C "$target_repo" "${apply_args[@]}"
}

bundle_repo="../pdfium-bundle"
dry_run=0
allow_dirty=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      [[ $# -ge 2 ]] || die "--bundle requires a path"
      bundle_repo=$2
      shift 2
      ;;
    --dry-run|--check)
      dry_run=1
      shift
      ;;
    --allow-dirty)
      allow_dirty=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -eq 1 ]] || { usage >&2; exit 1; }

commit=$1
repo_root=$(git rev-parse --show-toplevel)
bundle_root=$(git -C "$bundle_repo" rev-parse --show-toplevel)
commit=$(git -C "$bundle_root" rev-parse "$commit^{commit}")

parent_count=$(git -C "$bundle_root" rev-list --parents -n 1 "$commit" | wc -w | tr -d ' ')
[[ "$parent_count" == "2" ]] || die "commit must have exactly one parent"
parent="$commit^"

[[ -d "$repo_root/pdfium-lib/.git" || -f "$repo_root/pdfium-lib/.git" ]] ||
  die "pdfium-lib submodule is not checked out"
[[ -d "$repo_root/pdfium-render/.git" || -f "$repo_root/pdfium-render/.git" ]] ||
  die "pdfium-render submodule is not checked out"

if [[ "$dry_run" != "1" && "$allow_dirty" != "1" ]]; then
  require_clean "$repo_root" "superproject"
  require_clean "$repo_root/pdfium-lib" "pdfium-lib"
  require_clean "$repo_root/pdfium-render" "pdfium-render"
fi

subject=$(git -C "$bundle_root" log -n 1 --format=%s "$commit")
echo "Replaying $commit $subject"
applied_any=0

if has_diff "$bundle_root" "$parent" "$commit" "." ":(exclude)pdfium-lib/**" ":(exclude)pdfium-render/**"; then
  applied_any=1
  echo "  root paths"
  apply_diff "$bundle_root" "$repo_root" "$parent" "$commit" 1 "$dry_run" "." ":(exclude)pdfium-lib/**" ":(exclude)pdfium-render/**"
fi

if has_diff "$bundle_root" "$parent" "$commit" "pdfium-lib"; then
  applied_any=1
  echo "  pdfium-lib submodule paths"
  apply_diff "$bundle_root" "$repo_root/pdfium-lib" "$parent" "$commit" 2 "$dry_run" "pdfium-lib"
fi

if has_diff "$bundle_root" "$parent" "$commit" "pdfium-render"; then
  applied_any=1
  echo "  pdfium-render submodule paths"
  apply_diff "$bundle_root" "$repo_root/pdfium-render" "$parent" "$commit" 2 "$dry_run" "pdfium-render"
fi

if [[ "$applied_any" == "0" ]]; then
  echo "No matching root, pdfium-lib, or pdfium-render paths changed."
fi

if [[ "$dry_run" == "1" ]]; then
  echo "Dry run succeeded."
else
  echo "Replay applied. Review with:"
  echo "  git status --short"
  echo "  git -C pdfium-lib status --short"
  echo "  git -C pdfium-render status --short"
fi
