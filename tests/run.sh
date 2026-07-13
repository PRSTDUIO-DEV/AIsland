#!/bin/bash
# Compile providers.swift with the test main and run the assertions.
set -e
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -o .build/aisland-tests providers.swift tests/main.swift
./.build/aisland-tests
