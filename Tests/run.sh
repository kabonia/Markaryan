#!/bin/sh
# Runs the calculation and plan tests (macOS with Xcode, or Linux with a Swift toolchain).
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}"
CORE=Markaryan/Core
PLAN_FILES="$CORE/Calculator.swift $CORE/PlanGeometry.swift $CORE/PlanWalls.swift $CORE/DesignProposal.swift $CORE/RoomKind.swift $CORE/FloorPlan.swift $CORE/LayoutCheck.swift $CORE/DesignBrief.swift $CORE/LayoutEngine.swift $CORE/OfflineDesigner.swift $CORE/PlanFlow.swift $CORE/PlanEditor.swift $CORE/FurnitureEditor.swift $CORE/WallBody.swift $CORE/ElectricPlan.swift $CORE/TileLayout.swift"

swiftc -swift-version 5 -O "$CORE/Calculator.swift" Tests/main.swift -o "$OUT/markaryan-calc-tests"
"$OUT/markaryan-calc-tests"

# shellcheck disable=SC2086
swiftc -swift-version 5 -O $PLAN_FILES Tests/Plan/main.swift -o "$OUT/markaryan-plan-tests"
"$OUT/markaryan-plan-tests"
