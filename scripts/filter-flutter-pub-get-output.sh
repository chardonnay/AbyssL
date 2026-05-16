#!/bin/bash
# Filter only Flutter pub-get version summary noise shared by CI and release builds.

set -euo pipefail

# Current Flutter pub get help exposes no --quiet flag. These patterns
# target package rows ending in "(... available)", the incompatible-version
# summary line, and Flutter's `pub outdated` hint while preserving other output.
sed -E \
  -e '/^[[:space:]]+[^[:space:]].*\([0-9][^)]* available\)$/d' \
  -e '/^[0-9]+ packages? (has|have) newer versions incompatible with dependency constraints\.$/d' \
  -e '/^Try .* pub outdated.* for more information\.$/d'
