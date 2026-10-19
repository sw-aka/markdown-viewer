#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -swift-version 6 MarkdownViewer/Sources/UpdateRelease.swift MarkdownViewer/Sources/SessionSnapshot.swift MarkdownViewer/Sources/UpdateWriteProtection.swift \
  tests/UpdateModelTests.swift -o build/tests/update-model-tests
build/tests/update-model-tests
