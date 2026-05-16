#!/bin/bash
# Build the Flutter macOS release app and package the .app bundle as a zip.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

readonly APP_DIR="${REPO_ROOT}/apps/abyssl_flutter"
readonly FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
readonly APP_BUNDLE_NAME="abyssl_flutter.app"
readonly ARCHIVE_NAME="abyssl_flutter-macos-release.zip"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

resolve_dist_dir() {
  local configured_dist_dir="${DIST_DIR:-dist}"

  if [[ "${configured_dist_dir}" == /* ]]; then
    printf '%s\n' "${configured_dist_dir}"
  else
    printf '%s\n' "${REPO_ROOT}/${configured_dist_dir}"
  fi
}

require_macos() {
  local kernel_name
  kernel_name="$(uname -s)"

  if [[ "${kernel_name}" != "Darwin" ]]; then
    die "macOS release builds must run on macOS; current kernel is ${kernel_name}."
  fi
}

require_flutter() {
  command -v "${FLUTTER_BIN}" >/dev/null 2>&1 \
    || die "Flutter executable not found: ${FLUTTER_BIN}"

  command -v ditto >/dev/null 2>&1 \
    || die "Required macOS packaging tool not found: ditto"
}

resolve_dependencies() {
  if ! "${FLUTTER_BIN}" pub get 2>&1 \
    | bash "${REPO_ROOT}/scripts/filter-flutter-pub-get-output.sh"; then
    die "Flutter dependency resolution failed."
  fi
}

build_release() {
  local -a build_args
  build_args=(build macos --release --no-pub)

  if [[ -n "${APP_VERSION:-}" ]]; then
    build_args+=("--build-name=${APP_VERSION}")
  fi

  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    build_args+=("--build-number=${BUILD_NUMBER}")
  fi

  "${FLUTTER_BIN}" "${build_args[@]}"
}

package_release() {
  local dist_dir="$1"
  local release_dir="${APP_DIR}/build/macos/Build/Products/Release"
  local app_bundle="${release_dir}/${APP_BUNDLE_NAME}"
  local archive_path="${dist_dir}/${ARCHIVE_NAME}"

  [[ -d "${app_bundle}" ]] \
    || die "Release app bundle not found after build: ${app_bundle}"

  if [[ "${dist_dir}" == "/" || "${dist_dir}" == "${REPO_ROOT}" ]]; then
    die "Refusing to use unsafe DIST_DIR: ${dist_dir}"
  fi

  rm -rf "${dist_dir}"
  mkdir -p "${dist_dir}"

  ditto -c -k --sequesterRsrc --keepParent "${app_bundle}" "${archive_path}"
  printf 'Built %s\n' "${archive_path}"
}

main() {
  local dist_dir
  dist_dir="$(resolve_dist_dir)"

  require_macos
  require_flutter
  cd "${APP_DIR}" || die "Failed to enter Flutter app directory: ${APP_DIR}"
  resolve_dependencies
  build_release
  package_release "${dist_dir}"
}

main "$@"
