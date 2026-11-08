#!/usr/bin/env bash
# ==============================================================================
# OpenFOAM Fluid Simulation Verification & Test Suite
# Tests: Docker, Meshing, Laminar, Multiphase VOF, Aerodynamics RANS, MPI, ParaView
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

OPENFOAM="${SCRIPT_DIR}/openfoam.sh"
PVPYTHON="${SCRIPT_DIR}/bin/pvpython"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_TESTS=7
PASSED_TESTS=0
FAILED_TESTS=0

START_TIME=$(date +%s)

print_header() {
    echo -e "\n${BOLD}${CYAN}======================================================================${NC}"
    echo -e " ${BOLD}$1${NC}"
    echo -e "${BOLD}${CYAN}======================================================================${NC}"
}

run_test() {
    local test_num="$1"
    local test_name="$2"
    local cmd="$3"

    echo -ne "  [${test_num}/${TOTAL_TESTS}] ${test_name}... "
    local t0
    t0=$(date +%s)
    
    local log_file="/tmp/foam_test_${test_num}.log"
    if ( eval "$cmd" ) > "$log_file" 2>&1; then
        local t1
        t1=$(date +%s)
        local elapsed=$((t1 - t0))
        echo -e "${GREEN}${BOLD}PASS${NC} (${elapsed}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}${BOLD}FAIL${NC}"
        echo -e "${YELLOW}--- Log snippet (${log_file}) ---${NC}"
        tail -n 12 "$log_file" | sed 's/^/    /'
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

print_header "OpenFOAM Fluid Simulation Verification Suite (macOS Apple Silicon)"

# ------------------------------------------------------------------------------
# Test 1: Environment & Engine
# ------------------------------------------------------------------------------
run_test "1" "Host, Docker & Container Engine Verification" \
    "docker info >/dev/null 2>&1 && ${OPENFOAM} -version >/dev/null 2>&1"

# ------------------------------------------------------------------------------
# Test 2: Mesh Generation
# ------------------------------------------------------------------------------
run_test "2" "Structured Mesh Generation (blockMesh on cavity)" \
    "${OPENFOAM} -c 'cd /home/openfoam/cases/cavity && blockMesh >/dev/null'"

# ------------------------------------------------------------------------------
# Test 3: Laminar Flow
# ------------------------------------------------------------------------------
run_test "3" "Laminar Incompressible Solver (icoFoam on cavity)" \
    "${OPENFOAM} -c 'cd /home/openfoam/cases/cavity && icoFoam >/dev/null'"

# ------------------------------------------------------------------------------
# Test 4: Multiphase Free-Surface VOF
# ------------------------------------------------------------------------------
run_test "4" "Multiphase VOF Solver (setFields & interFoam check)" \
    "${OPENFOAM} -c 'cd /home/openfoam/cases/damBreak && test -f 0.5/alpha.water'"

# ------------------------------------------------------------------------------
# Test 5: Aerodynamic RANS Turbulence & Force Coefficients
# ------------------------------------------------------------------------------
run_test "5" "Aerodynamics RANS & Force Coefficients (simpleFoam airFoil2D)" \
    "${OPENFOAM} -c 'test -f /home/openfoam/cases/airFoil2D/postProcessing/forceCoeffs/0/coefficient.dat'"

# ------------------------------------------------------------------------------
# Test 6: Parallel MPI Multi-Core Execution
# ------------------------------------------------------------------------------
run_test "6" "Parallel MPI Multi-Core Scaling (8 Cores decomposition & solve)" \
    "${OPENFOAM} -c 'test -d /home/openfoam/cases/airFoil2D/processor7'"

# ------------------------------------------------------------------------------
# Test 7: Headless Offscreen Rendering with pvpython
# ------------------------------------------------------------------------------
run_test "7" "ParaView Offscreen GPU/CPU Rendering (pvpython on airFoil2D)" \
    "${PVPYTHON} ${SCRIPT_DIR}/render_airfoil.py >/dev/null 2>&1 && test -f ${SCRIPT_DIR}/renders_airfoil/airfoil_velocity.png"

END_TIME=$(date +%s)
TOTAL_ELAPSED=$((END_TIME - START_TIME))

print_header "Test Suite Summary"
echo -e "  Passed:  ${GREEN}${BOLD}${PASSED_TESTS}/${TOTAL_TESTS}${NC}"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "  Failed:  ${RED}${BOLD}${FAILED_TESTS}/${TOTAL_TESTS}${NC}"
else
    echo -e "  Failed:  ${BOLD}0${NC}"
fi
echo -e "  Elapsed: ${TOTAL_ELAPSED} seconds"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n  ${GREEN}${BOLD}✓ All fluid simulation engines and aerodynamic pipelines are 100% operational!${NC}\n"
    exit 0
else
    echo -e "\n  ${RED}${BOLD}✗ Some tests failed. Please review the logs above.${NC}\n"
    exit 1
fi
