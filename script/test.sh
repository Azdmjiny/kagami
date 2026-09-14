#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_BINARY="${TMPDIR:-/tmp}/kagami-model-checks"

cd "$ROOT_DIR"
swift build
swiftc \
  Sources/Kagami/Models/KagamiModels.swift \
  Sources/Kagami/Services/OllamaClient.swift \
  Sources/Kagami/Services/APIModelClient.swift \
  Sources/Kagami/Services/APIKeyStore.swift \
  Sources/Kagami/Services/AnkiConnectClient.swift \
  Sources/Kagami/Stores/KagamiStore.swift \
  Tests/run_model_checks.swift \
  -framework Security \
  -o "$CHECK_BINARY"
"$CHECK_BINARY"
