#!/usr/bin/env bash
# ==============================================================================
# OpenFOAM macOS Integration & PATH Installer
# Configures system PATH and shell aliases for zero-friction CFD simulation
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"
ZSHRC="${HOME}/.zshrc"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "\n${BOLD}${CYAN}======================================================================${NC}"
echo -e " ${BOLD}OpenFOAM macOS CLI & Integration Setup${NC}"
echo -e "${BOLD}${CYAN}======================================================================${NC}\n"

# 1. Ensure all binaries are executable
chmod +x "${SCRIPT_DIR}/openfoam.sh" "${BIN_DIR}"/* "${SCRIPT_DIR}/tests"/* 2>/dev/null || true
echo -e " ${GREEN}✓${NC} Permissions verified for all binaries."

# 2. Add to ~/.zshrc if not already present
PATH_ENTRY="export PATH=\"${BIN_DIR}:\$PATH\""
ALIAS_ENTRY="alias openfoam=\"${SCRIPT_DIR}/openfoam.sh\""

if [ -f "$ZSHRC" ] && grep -q "${BIN_DIR}" "$ZSHRC"; then
    echo -e " ${GREEN}✓${NC} ${BIN_DIR} is already configured in ~/.zshrc"
else
    echo "" >> "$ZSHRC"
    echo "# OpenFOAM Docker & Native macOS CFD Tools" >> "$ZSHRC"
    echo "$PATH_ENTRY" >> "$ZSHRC"
    echo "$ALIAS_ENTRY" >> "$ZSHRC"
    echo -e " ${GREEN}✓${NC} Added OpenFOAM tools to ${ZSHRC}"
fi

echo -e "\n${BOLD}Available commands (open a new terminal tab or run 'source ~/.zshrc'):${NC}"
echo -e "  • ${CYAN}openfoam${NC}      : Main OpenFOAM solver & shell command (e.g. 'openfoam simpleFoam')"
echo -e "  • ${CYAN}paraFoam${NC}      : Launch native macOS ParaView with Apple Silicon Metal acceleration"
echo -e "  • ${CYAN}foam-live${NC}     : Launch real-time web convergence & aerodynamic monitor"
echo -e "  • ${CYAN}foam-aero${NC}     : Aerodynamics toolkit (set-aoa, polar sweep, forces, renders)"
echo -e "  • ${CYAN}foam-test${NC}     : Run full fluid simulation test suite"
echo -e "  • ${CYAN}pvpython${NC}      : Headless/scripted ParaView Python on macOS"
echo -e "\n${GREEN}${BOLD}Setup complete!${NC}\n"
