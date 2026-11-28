#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 -m unittest discover -s development/tests -p 'test_*.py' -v
xcrun clang -fobjc-arc -Wno-unused-function -framework AppKit development/tests/test_cursorctl.m -o development/.build/test-cursorctl
development/.build/test-cursorctl
codesign --verify --deep --strict AniOnMac.app

xcrun clang -fobjc-arc -c development/native/CursorRefresh.m -o development/.build/test-refresh.o
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path development/.build/swift-cache development/app/Studio.swift development/native/CursorOutline.swift development/tests/test_apply_state.swift development/.build/test-refresh.o -o development/.build/test-apply-state
development/.build/test-apply-state --data-dir development/.build/apply-state-tests
