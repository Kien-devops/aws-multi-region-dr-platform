#!/usr/bin/env bash
# scripts/update-image-tag.sh
# Usage: ./scripts/update-image-tag.sh <component> <new_tag>
# Example: ./scripts/update-image-tag.sh backend-2 abcdef123
# Phase 2 only: application delivery is outside the infrastructure lab scope.

set -euo pipefail

COMPONENT="${1:-}"
NEW_TAG="${2:-}"

if [[ -z "$COMPONENT" || -z "$NEW_TAG" ]]; then
  echo "Usage: $0 <component> <new_tag>"
  echo "Allowed components: frontend, backend-1, backend-2, backend-3"
  exit 1
fi

# Normalize component to logical image name
case "$COMPONENT" in
  frontend|app2-frontend)
    IMAGE_NAME="app2-frontend"
    ;;
  backend-1|app2-backend-1)
    IMAGE_NAME="app2-backend-1"
    ;;
  backend-2|app2-backend-2)
    IMAGE_NAME="app2-backend-2"
    ;;
  backend-3|app2-backend-3)
    IMAGE_NAME="app2-backend-3"
    ;;
  *)
    echo "Error: Unknown component '$COMPONENT'."
    echo "Allowed components: frontend, backend-1, backend-2, backend-3"
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_KUSTOMIZE="$REPO_ROOT/gitops/app2/base/kustomization.yaml"

if [[ ! -f "$BASE_KUSTOMIZE" ]]; then
  echo "Error: Base kustomization file not found at $BASE_KUSTOMIZE"
  exit 1
fi

echo "==> Updating image [$IMAGE_NAME] with tag [$NEW_TAG] in [$BASE_KUSTOMIZE]..."

# Update using python, sed or kustomize
if command -v python3 &>/dev/null; then
  python3 -c "
import sys

base_file = '$BASE_KUSTOMIZE'
target_name = '$IMAGE_NAME'
new_tag = '$NEW_TAG'

with open(base_file, 'r') as f:
    lines = f.readlines()

out = []
in_target_image = False

for line in lines:
    if line.strip().startswith('- name:'):
        name = line.split('- name:')[1].strip()
        in_target_image = (name == target_name)
    elif in_target_image and line.strip().startswith('newTag:'):
        indent = line[:line.find('newTag:')]
        line = f'{indent}newTag: {new_tag}\n'
        in_target_image = False
    out.append(line)

with open(base_file, 'w') as f:
    f.writelines(out)
"
else
  # Portable awk / sed fallback
  awk -v img="$IMAGE_NAME" -v tag="$NEW_TAG" '
    $0 ~ "- name: " img { in_block=1; print; next }
    in_block && $0 ~ "newTag:" { sub(/newTag:.*/, "newTag: " tag); in_block=0; print; next }
    in_block && $0 ~ "- name:" { in_block=0 }
    { print }
  ' "$BASE_KUSTOMIZE" > "$BASE_KUSTOMIZE.tmp" && mv "$BASE_KUSTOMIZE.tmp" "$BASE_KUSTOMIZE"
fi

echo "==> Validating Kustomize build for Singapore overlay..."
if command -v kubectl &>/dev/null; then
  kubectl kustomize "$REPO_ROOT/gitops/app2/overlays/singapore" > /dev/null
  echo "    [PASS] Singapore overlay valid."
  kubectl kustomize "$REPO_ROOT/gitops/app2/overlays/tokyo" > /dev/null
  echo "    [PASS] Tokyo overlay valid."
elif command -v kustomize &>/dev/null; then
  kustomize build "$REPO_ROOT/gitops/app2/overlays/singapore" > /dev/null
  echo "    [PASS] Singapore overlay valid."
  kustomize build "$REPO_ROOT/gitops/app2/overlays/tokyo" > /dev/null
  echo "    [PASS] Tokyo overlay valid."
else
  echo "    [INFO] Neither kubectl nor kustomize found for dry-run verification."
fi

echo "==> Successfully updated $IMAGE_NAME to $NEW_TAG!"
