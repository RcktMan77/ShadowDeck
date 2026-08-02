#!/usr/bin/env bash
# Optional style lint. No-ops with a clear message when SwiftLint is not installed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "SwiftLint not installed. Optional: brew install swiftlint"
  echo "Config is ready at .swiftlint.yml — CI/local runs will use it once installed."
  exit 0
fi

echo "Running SwiftLint (comprehensive config: .swiftlint.yml)…"
# Defaults + recommended opt-ins. Errors fail the run; warnings are informational.
# Pass --strict to fail on warnings as well.
swiftlint lint --config .swiftlint.yml "$@"
