<!-- datasheet:banner -->
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/banner-dark.svg">
    <img src=".github/assets/banner-light.svg" alt="OpenFOAM Mac Suite: A turnkey OpenFOAM v2512 CFD environment for Apple Silicon and Intel Macs, with live dashboards and aero tooling." width="100%">
  </picture>
</p>
<!-- /datasheet:banner -->

# OpenFOAM Mac Suite

**A turnkey OpenFOAM v2512 CFD environment for Apple Silicon and Intel Macs, pairing a Docker solver runtime with native macOS ParaView, live convergence monitoring, and an aerodynamics toolkit.**

<!-- datasheet:figure -->
## At a glance

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/diagram-dark.svg">
    <img src=".github/assets/diagram-light.svg" alt="Block diagram: case to solver to live view" width="100%">
  </picture>
</p>

| Characteristic | Detail |
| --- | --- |
| **Engine** | OpenCFD OpenFOAM v2512 (`opencfd/openfoam-default:latest`) on macOS (`arm64` and `x86_64`) via Docker (`--shm-size=4g --ipc=host`) |
| **CLI tools** | `openfoam` (`./openfoam.sh`), `foam-aero`, `foam-live` (`http://localhost:8080`), `foam-test`, `paraFoam`, `pvpython`, `pvbatch` |
| **Visualization** | Native macOS `ParaView*.app` (Metal GPU accelerated) plus a live browser dashboard for residuals and aerodynamic forces |
| **Included cases** | `cases/airFoil2D` (`simpleFoam`), `cases/damBreak` (`interFoam`), `cases/pitzDaily` (`pimpleFoam`), `cases/cavity` (`icoFoam`) |
| **Verification** | `./bin/foam-test` runs a 7-stage check covering Docker, `blockMesh`, laminar, VOF, RANS airfoil, 8-core MPI scaling and headless `pvpython` |
<!-- /datasheet:figure -->

## Quick start

All tools live in [`bin/`](bin) and can be added to `PATH` with [`install_mac.sh`](install_mac.sh):

| Command | Purpose |
| :--- | :--- |
| `openfoam` (or `./openfoam.sh`) | Open an interactive OpenFOAM shell or run any solver/utility in the container |
| `paraFoam [case]` | Create the `.foam` stub and open the case in native macOS ParaView |
| `foam-live [case]` | Launch the real-time web convergence dashboard (`http://localhost:8080`) |
| `foam-aero <cmd>` | Aerodynamics toolkit (`set-aoa`, `forces`, `polar`, `render`) |
| `foam-test` | Run the automated 7-step fluid simulation test suite |
| `pvpython <script.py>` | Run macOS ParaView Python scripts for headless rendering and animations |

## Aerodynamic workflows

### 1. Angle of Attack (AoA) adjustment
Set the angle of attack $\alpha$ for the 2D NACA airfoil without manually recalculating velocity components or lift/drag unit vectors:

```bash
# Set Angle of Attack to 4.0 degrees with default 26.0 m/s freestream velocity
foam-aero set-aoa 4.0

# Set Angle of Attack to 12.0 degrees with 50.0 m/s freestream
foam-aero set-aoa 12.0 --speed 50.0
```

`foam-aero set-aoa` updates:
- Velocity field $U = (U_\infty \cos\alpha, U_\infty \sin\alpha, 0)$ in `0.orig/U` and `0/U`.
- Lift direction $(-\sin\alpha, \cos\alpha, 0)$ and drag direction $(\cos\alpha, \sin\alpha, 0)$ in `system/controlDict`.

### 2. Extract converged lift and drag coefficients
Inspect converged aerodynamic forces, lift coefficient $C_l$, drag coefficient $C_d$ (pressure vs friction), pitching moment $C_m$, and lift-to-drag ratio $L/D$:

```bash
foam-aero forces
```

Output:
```text
============================================================
  Aerodynamic Coefficients Summary: airFoil2D
============================================================
  Converged Iteration / Time:   308
  Lift Coefficient (Cl):        +0.9709
  Drag Coefficient (Cd):        +0.0294
    - Pressure Drag (Cd_p):     +0.0140
    - Friction Drag (Cd_f):     +0.0154
  Pitching Moment (Cm_c/4):     +0.2329
  Lift-to-Drag Ratio (L/D):     +33.07
============================================================
```

### 3. Automated aerodynamic polar sweep
Run a polar sweep across multiple angles of attack:

```bash
foam-aero polar --angles 0,2,4,6,8,10,12
```

Each point is cleaned and solved in turn, writing $C_l, C_d, C_m$ to `cases/airFoil2D/aerodynamic_polar.csv`.

### 4. High-resolution flow field rendering
Render velocity magnitude and pressure field snapshots through headless `pvpython`:

```bash
foam-aero render
```
Images are written to `renders_airfoil/`.

## Real-time simulation viewing

### Live web convergence dashboard (`foam-live`)
```bash
foam-live
```
Open **`http://localhost:8080`** in your browser:
- **Live residuals graph:** logarithmic convergence plot for $p, U_x, U_y, \tilde{\nu}, k, \omega$.
- **Live aerodynamic forces:** real-time lift ($C_l$) and drag ($C_d$) history.
- **Live flow visualizer:** rendered flow field slices.
- **One-click ParaView:** launch native macOS ParaView from the dashboard.

### Hardware-accelerated macOS ParaView (`paraFoam`)
```bash
paraFoam cases/airFoil2D
```
In ParaView, enable **Auto Apply** (`Edit -> Settings -> General -> Auto Apply`), open the `.foam` stub, and click **Reload Files** while the solver runs in Docker to step through newly written time directories.

## Fluid simulation test suite

```bash
./bin/foam-test
```

Checks performed:
1. **Environment:** Docker daemon, CPU/RAM, and ARM64/x86_64 image check.
2. **Mesh generation:** `blockMesh` on a structured 3D grid.
3. **Laminar flow:** `icoFoam` on the lid-driven cavity benchmark.
4. **Multiphase VOF:** `interFoam` on the dam-break collapsing liquid column.
5. **Aerodynamics RANS:** `simpleFoam` on the NACA 0012 airfoil with force convergence.
6. **Parallel MPI scaling:** 8-core `decomposePar` and `mpirun` check.
7. **ParaView offscreen rendering:** `pvpython` headless render pipeline.

## Included simulation cases

| Case | Solver | Physics & Application |
| :--- | :--- | :--- |
| [`cases/airFoil2D`](cases/airFoil2D) | `simpleFoam` | External aerodynamics: NACA 0012 airfoil ($C_l, C_d, C_m, y^+$, residuals) |
| [`cases/damBreak`](cases/damBreak) | `interFoam` | Multiphase Volume-of-Fluid (VOF) collapsing liquid column and obstacle splash |
| [`cases/pitzDaily`](cases/pitzDaily) | `pimpleFoam` | Transient turbulent vortex shedding over a backward-facing step |
| [`cases/cavity`](cases/cavity) | `icoFoam` | Classic 2D lid-driven cavity laminar benchmark |

Run any case with:
```bash
cd cases/<case_name>
openfoam ./Allrun
```

## Absolute maximum ratings

| Parameter | Limit |
| --- | --- |
| Container shared memory (`--shm-size`) | `4 GB` default (increase in `openfoam.sh` for larger unstructured MPI meshes) |
| Host mount safety | Never mounts `$HOME` or `/`; external cases mount solely at `/home/openfoam/case` |
| Live dashboard bind | `http://localhost:8080` (`foam-live`) |
| Parallel MPI ranks in `foam-test` | Up to 8 ranks (`decomposePar` + OpenMPI `vader` shared-memory transport) |

## Errata

- **Docker Desktop required:** OpenFOAM solvers run inside the Linux container (`opencfd/openfoam-default:latest`); `openfoam.sh` attempts to auto-start Docker Desktop on macOS and waits up to 30 seconds.
- **ParaView discovery:** `paraFoam`, `pvpython`, and `pvbatch` search `PARAVIEW_APP`, `/opt/homebrew/bin/paraview`, `/Applications/ParaView.app`, and `/Applications/ParaView*.app` (highest installed version first). Headless rendering (`foam-aero render` and test step 7) requires ParaView to be installed under `/Applications`.

## License

MIT. See [LICENSE](LICENSE).

<!-- datasheet:footer -->
---

<p align="center">
  <a href="https://github.com/S-k404/mc-server-manager">&larr; U19 mc-server-manager</a> &middot;
  <a href="https://github.com/S-k404/S-k404">SK-404 index</a> &middot;
  <a href="https://github.com/S-k404/card-wallet">U23 card-wallet &rarr;</a>
</p>
<!-- /datasheet:footer -->
