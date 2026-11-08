#!/usr/bin/env bash
# ==============================================================================
# OpenFOAM Docker Runner & CLI for macOS (Apple Silicon ARM64 & Intel x86_64)
# OpenCFD OpenFOAM v2512 with Native ParaView & Real-Time Monitoring
# ==============================================================================

set -eo pipefail

IMAGE="opencfd/openfoam-default:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="${SCRIPT_DIR}"
CONTAINER_BASE="/home/openfoam"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ------------------------------------------------------------------------------
# 1. Docker Daemon Verification & macOS Auto-Start
# ------------------------------------------------------------------------------
ensure_docker_running() {
    if docker info >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${YELLOW}Docker is not running. Attempting to start Docker Desktop...${NC}"
    if [ "$(uname)" = "Darwin" ]; then
        open -a Docker >/dev/null 2>&1 || true
    fi

    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if docker info >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Docker Desktop is ready.${NC}"
            return 0
        fi
        printf "."
        sleep 1
        attempt=$((attempt + 1))
    done
    echo ""

    echo -e "${RED}Error: Docker daemon could not be reached after 30 seconds.${NC}" >&2
    echo "Please ensure Docker Desktop is open and responding, then retry." >&2
    exit 1
}

# ------------------------------------------------------------------------------
# 2. Host native ParaView Launcher
# ------------------------------------------------------------------------------
launch_paraview() {
    local target_dir="${1:-$(pwd)}"
    if [ -f "$target_dir" ]; then
        target_dir="$(dirname "$target_dir")"
    fi
    target_dir="$(cd "$target_dir" && pwd)"

    local case_name
    case_name="$(basename "$target_dir")"
    local foam_file="${target_dir}/${case_name}.foam"

    if [ ! -f "$foam_file" ]; then
        touch "$foam_file"
        echo -e "${CYAN}Created case file: ${foam_file}${NC}"
    fi

    local paraview_bin=""
    if [ -x "/opt/homebrew/bin/paraview" ]; then
        paraview_bin="/opt/homebrew/bin/paraview"
    elif [ -x "/Applications/ParaView-6.1.1.app/Contents/MacOS/paraview" ]; then
        paraview_bin="/Applications/ParaView-6.1.1.app/Contents/MacOS/paraview"
    elif [ -d "/Applications/ParaView.app" ]; then
        paraview_bin="/Applications/ParaView.app/Contents/MacOS/paraview"
    elif command -v paraview >/dev/null 2>&1; then
        paraview_bin="$(command -v paraview)"
    fi

    if [ -z "$paraview_bin" ]; then
        echo -e "${RED}Error: ParaView was not found on your Mac.${NC}"
        echo "Install via Homebrew: brew install --cask paraview"
        exit 1
    fi

    echo -e "${GREEN}🚀 Launching native macOS ParaView for: ${BOLD}${case_name}${NC}"
    "$paraview_bin" "$foam_file" >/dev/null 2>&1 &
}

# ------------------------------------------------------------------------------
# 3. Environment Doctor & Diagnostics
# ------------------------------------------------------------------------------
run_doctor() {
    echo -e "${BOLD}${CYAN}=== OpenFOAM Environment Diagnostics ===${NC}"
    echo -e "Host System:        $(uname -s) $(uname -m) ($(sw_vers -productVersion 2>/dev/null || echo 'macOS'))"
    
    if docker info >/dev/null 2>&1; then
        local cpus mem
        cpus=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo "Unknown")
        mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "Unknown")
        echo -e "Docker Engine:      ${GREEN}Running${NC} (${cpus} CPUs, ${mem} bytes RAM)"
    else
        echo -e "Docker Engine:      ${RED}Not running${NC}"
    fi

    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo -e "OpenFOAM Image:     ${GREEN}Present (${IMAGE})${NC}"
    else
        echo -e "OpenFOAM Image:     ${YELLOW}Missing locally (will be pulled on first run)${NC}"
    fi

    if [ -x "/opt/homebrew/bin/paraview" ] || [ -d "/Applications/ParaView-6.1.1.app" ]; then
        echo -e "Native ParaView:    ${GREEN}Installed (/opt/homebrew/bin/paraview)${NC}"
    else
        echo -e "Native ParaView:    ${YELLOW}Not found (brew install --cask paraview)${NC}"
    fi

    if [ -x "/Applications/ParaView-6.1.1.app/Contents/bin/pvpython" ]; then
        echo -e "ParaView pvpython:  ${GREEN}Available for automated batch/headless rendering${NC}"
    else
        echo -e "ParaView pvpython:  ${YELLOW}Not found${NC}"
    fi

    echo -e "${BOLD}${CYAN}=========================================${NC}"
}

# ------------------------------------------------------------------------------
# 4. Command Router
# ------------------------------------------------------------------------------
# Check for subcommands
case "${1:-}" in
    view|parafoam|paraFoam)
        shift
        launch_paraview "${1:-$(pwd)}"
        exit 0
        ;;
    live|monitor|dashboard)
        shift
        exec "${WORKSPACE_ROOT}/bin/foam-live" "$@"
        ;;
    test|tests|check)
        shift
        exec "${WORKSPACE_ROOT}/bin/foam-test" "$@"
        ;;
    aero)
        shift
        exec "${WORKSPACE_ROOT}/bin/foam-aero" "$@"
        ;;
    doctor)
        run_doctor
        exit 0
        ;;
    help|--help|-h)
        cat << 'EOF'
OpenFOAM Runner & CFD Suite for macOS

Usage:
  ./openfoam.sh                     Enter interactive OpenFOAM container shell
  ./openfoam.sh <cmd> [args...]     Run any OpenFOAM solver or utility (e.g. simpleFoam, blockMesh)
  ./openfoam.sh parafoam [case]     Launch native macOS ParaView on current or specified case
  ./openfoam.sh live [case]         Launch real-time web convergence & aerodynamic monitor
  ./openfoam.sh aero <command>      Aerodynamics toolkit (set-aoa, polar, forces, render)
  ./openfoam.sh test                Run fluid simulation verification test suite
  ./openfoam.sh doctor              Display system and environment diagnostics

Examples:
  ./openfoam.sh blockMesh
  ./openfoam.sh simpleFoam -case cases/airFoil2D
  ./openfoam.sh parafoam cases/airFoil2D
  ./openfoam.sh live cases/airFoil2D
  ./openfoam.sh aero set-aoa 4.0
EOF
        exit 0
        ;;
esac

# ------------------------------------------------------------------------------
# 5. Run OpenFOAM inside Container
# ------------------------------------------------------------------------------
ensure_docker_running

CURRENT_DIR="$(pwd)"
CONTAINER_WORK_DIR="${CONTAINER_BASE}"

# Determine mounting path:
# Prevent sharing the user's entire $HOME directory with the container
if [[ "${CURRENT_DIR}" == "${WORKSPACE_ROOT}"* ]]; then
    # Working inside the OpenFOAM workspace
    REL_PATH="${CURRENT_DIR#"${WORKSPACE_ROOT}"}"
    REL_PATH="${REL_PATH#/}"
    MOUNT_HOST="${WORKSPACE_ROOT}"
    if [ -n "${REL_PATH}" ]; then
        CONTAINER_WORK_DIR="${CONTAINER_BASE}/${REL_PATH}"
    else
        CONTAINER_WORK_DIR="${CONTAINER_BASE}"
    fi
    EXTRA_MOUNTS=()
elif [ "$CURRENT_DIR" = "$HOME" ] || [ "$CURRENT_DIR" = "/" ] || [ "$CURRENT_DIR" = "/Users" ]; then
    # Running from home directory or root: mount workspace root, NEVER $HOME
    MOUNT_HOST="${WORKSPACE_ROOT}"
    CONTAINER_WORK_DIR="${CONTAINER_BASE}"
    EXTRA_MOUNTS=()
else
    # Running from a custom case folder outside the workspace (e.g. ~/Desktop/my_case)
    MOUNT_HOST="${WORKSPACE_ROOT}"
    CONTAINER_WORK_DIR="${CONTAINER_BASE}/case"
    EXTRA_MOUNTS=(-v "${CURRENT_DIR}:${CONTAINER_BASE}/case")
fi

# TTY flags
DOCKER_TTY_FLAGS=""
if [ -t 0 ] && [ -t 1 ]; then
    DOCKER_TTY_FLAGS="-it"
fi

# High performance Docker flags:
# - shm-size=4g: prevents OpenMPI / parallel crashes on medium-to-large aerodynamic grids
# - ipc=host: optimized inter-process communication on host
DOCKER_PERF_FLAGS=(
    --shm-size=4g
    --ipc=host
    -e OMPI_MCA_btl_vader_single_copy_mechanism=none
)

if [ "$#" -eq 0 ]; then
    echo -e "${CYAN}------------------------------------------------------------------${NC}"
    echo -e " ${BOLD}OpenFOAM Shell (OpenCFD v2512 - Apple Silicon / ARM64)${NC}"
    echo -e " Workspace: ${BOLD}${MOUNT_HOST}${NC}"
    echo -e " Working directory: ${BOLD}${CONTAINER_WORK_DIR}${NC}"
    echo -e " Ready! Run solvers/utilities: ${GREEN}simpleFoam${NC}, ${GREEN}blockMesh${NC}, ${GREEN}checkMesh${NC}"
    echo -e " Type '${YELLOW}exit${NC}' to return to macOS terminal."
    echo -e "${CYAN}------------------------------------------------------------------${NC}"
    exec docker run --rm ${DOCKER_TTY_FLAGS} \
        "${DOCKER_PERF_FLAGS[@]}" \
        -u "$(id -u):$(id -g)" \
        -v "${MOUNT_HOST}:${CONTAINER_BASE}" \
        "${EXTRA_MOUNTS[@]}" \
        -w "${CONTAINER_WORK_DIR}" \
        "${IMAGE}"
fi

# Check if arguments contain shell control operators or pipelines
CMD_STRING="$*"
if [[ "$1" == "-c" ]]; then
    exec docker run --rm ${DOCKER_TTY_FLAGS} \
        "${DOCKER_PERF_FLAGS[@]}" \
        -u "$(id -u):$(id -g)" \
        -v "${MOUNT_HOST}:${CONTAINER_BASE}" \
        "${EXTRA_MOUNTS[@]}" \
        -w "${CONTAINER_WORK_DIR}" \
        "${IMAGE}" \
        "$@"
elif [[ "$CMD_STRING" == *"&&"* || "$CMD_STRING" == *"||"* || "$CMD_STRING" == *";"* || "$CMD_STRING" == *"|"* || "$CMD_STRING" == *">"* || "$CMD_STRING" == *"<"* ]]; then
    exec docker run --rm ${DOCKER_TTY_FLAGS} \
        "${DOCKER_PERF_FLAGS[@]}" \
        -u "$(id -u):$(id -g)" \
        -v "${MOUNT_HOST}:${CONTAINER_BASE}" \
        "${EXTRA_MOUNTS[@]}" \
        -w "${CONTAINER_WORK_DIR}" \
        "${IMAGE}" \
        -c "$CMD_STRING"
else
    exec docker run --rm ${DOCKER_TTY_FLAGS} \
        "${DOCKER_PERF_FLAGS[@]}" \
        -u "$(id -u):$(id -g)" \
        -v "${MOUNT_HOST}:${CONTAINER_BASE}" \
        "${EXTRA_MOUNTS[@]}" \
        -w "${CONTAINER_WORK_DIR}" \
        "${IMAGE}" \
        "$@"
fi
