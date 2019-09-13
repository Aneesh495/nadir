# NADIR

**Autonomous Earth Observation Satellite Constellation Mission Planning, J2 Astrodynamics, Agile Slew Scheduling, and Optical Inter-Satellite Link Routing Engine**

```
                  .---.                           .---.
                 /     \    === Laser ISL ===    /     \
                |  SAT  | <-------------------> |  SAT  |   [ Walker-Delta Mesh ]
                 \     /                         \     /
                  '---'                           '---'
                    \                               /
                     \  Push-Broom       Optical   /
                      \ Sensor Swath    Downlink  /
                       v                         v
                   .----------------------------------.
                  /                                    \
                 |          WGS-84 OBLATE EARTH         |
                 |      Critical Target Infrastructure  |
                 |       Ground Tracking Network (SGS)  |
                  \                                    /
                   '----------------------------------'
```

---

## 1. Executive Summary

NADIR is an autonomous mission planning, astrodynamics propagation, and network routing engine designed for large-scale Earth observation (EO) satellite constellations. Written in pure **Mercury** with native **ANSI C99** hardware acceleration, NADIR models the full closed-loop physics of modern low Earth orbit (LEO) imaging fleets:

* **High-Precision Astrodynamics**: Secular $J_2$ geopotential perturbations, Cowell numerical integration via Runge-Kutta 4th-order (RK4), Bowring WGS-84 ellipsoidal geodesy, and Halley cubic-order iterative Kepler equation solving.
* **Agile ADCS Slew Dynamics**: Reaction wheel torque/momentum constraints ($\alpha_{\max}, \omega_{\max}$) with trapezoidal angular velocity profiles and unit quaternion kinematics.
* **Physical Spacecraft Subsystems**: Closed-loop Electrical Power System (EPS) battery state-of-charge integration and Solid-State Recorder (SSR) buffer dynamics.
* **Optical Inter-Satellite Link (ISL) Mesh**: Parametric Walker-Delta ($T/P/F$) laser crosslink topologies, grazing ray atmospheric occultation filtering ($h_{\text{tangent}} \ge 100\text{ km}$), and dynamic Dijkstra shortest-path routing.
* **Ground Segment Downlink Allocator**: Multi-dish antenna contention resolution with DVB-S2X / CCSDS 131.2-B elevation-dependent Adaptive Coding and Modulation (ACM).
* **Dual-Language Architecture**: Referential transparency, strong static typing, and determinism analysis in Mercury, bridged via C foreign function interfaces (FFI) for SIMD vector arithmetic and nanosecond POSIX timing.

---

## 2. System Architecture

```
       +-------------------------------------------------------------+
       |                     NADIR CLI & Frontends                   |
       |  nadir CLI  /  Curses Ops Dashboard  /  CesiumJS 3D WebGL   |
       +-------------------------------------------------------------+
                                      |
       +-------------------------------------------------------------+
       |               Simulation & Mission Loop Engine              |
       |                   (nadir_core.sim: discrete event)          |
       +-------------------------------------------------------------+
               |                       |                      |
               v                       v                      v
    +--------------------+  +--------------------+  +--------------------+
    | Access & Coverage  |  |  Constellation     |  | Ground Segment &   |
    |  Geometry Engine   |  |   ISL Routing      |  | Downlink Optimizer |
    | (swath, agile FOR, |  | (contact graph,    |  | (AOS/LOS passes,   |
    |  Earth occultation)|  |  dynamic Dijkstra) |  |  ACM link budgets) |
    +--------------------+  +--------------------+  +--------------------+
               |                       |                      |
               +-----------------------+----------------------+
                                       |
       +-------------------------------------------------------------+
       |          Observation Scheduler (Constrained MIP/Greedy)     |
       |           (ADCS slew dynamics, EPS battery, SSR storage)    |
       +-------------------------------------------------------------+
                                       |
       +-------------------------------------------------------------+
       |              High-Precision Astrodynamics Core              |
       |     (J2 secular, Cowell RK4, Halley Kepler, Bowring WGS-84) |
       +-------------------------------------------------------------+
                                       |
       +-------------------------------------------------------------+
       |          ANSI C99 SIMD & Nanosecond FFI Acceleration        |
       |               (c_src/nadir_c_glue.c: FFI layer)             |
       +-------------------------------------------------------------+
```

Detailed technical documentation and derivations are available in `docs/`:
* [System Architecture & Pipelines](file:///Users/aneeshkrishna/.gemini/antigravity/scratch/nadir/docs/ARCHITECTURE.md)
* [Astrodynamics & Numerical Formulations](file:///Users/aneeshkrishna/.gemini/antigravity/scratch/nadir/docs/ASTRODYNAMICS.md)
* [Optical ISL Mesh & Routing](file:///Users/aneeshkrishna/.gemini/antigravity/scratch/nadir/docs/ISL_ROUTING.md)
* [Observation Scheduler & ADCS Agility](file:///Users/aneeshkrishna/.gemini/antigravity/scratch/nadir/docs/SCHEDULER.md)
* [Ground Tracking Segment & Downlink Protocol](file:///Users/aneeshkrishna/.gemini/antigravity/scratch/nadir/docs/GROUND_SEGMENT.md)
* [Verification Matrix & Validation Report](file:///Users/aneeshkrishna/.gemini/antigravity/scratch/nadir/docs/VERIFICATION.md)

---

## 3. Key Technical Innovations

### 3.1 Halley Cubic-Order Kepler Anomaly Solver
Standard astrodynamics packages rely on second-order Newton-Raphson iteration. NADIR implements Halley's third-order rational method:

$$E_{k+1} = E_k - \frac{2 f(E_k) f'(E_k)}{2 [f'(E_k)]^2 - f(E_k) f''(E_k)}$$

This achieves cubic asymptotic convergence ($O(\epsilon^3)$), converging to machine epsilon ($< 10^{-12}\text{ rad}$) in 2 to 3 iterations even across high eccentricities ($e \ge 0.75$).

### 3.2 Atmospheric Grazing Ray Occultation Limit
Inter-satellite optical crosslinks undergo severe wavefront distortion when intersecting Earth's atmosphere. NADIR analytically solves the closest approach along the laser ray segment:

$$t_{\min} = -\frac{\mathbf{r}_1 \cdot (\mathbf{r}_2 - \mathbf{r}_1)}{\|\mathbf{r}_2 - \mathbf{r}_1\|^2}, \quad h_{\text{tangent}} = \|\mathbf{r}(t_{\min})\| - R_{\oplus}$$

From this geometry, NADIR mathematically derives the critical angular spacing for low Earth orbit constellations:

$$\Delta\theta_{\max} = 2 \arccos\left(\frac{R_{\oplus} + h_{\text{atm}}}{R_{\oplus} + h_{\text{sat}}}\right) \approx 39.27^\circ \quad (\text{at } 500\text{ km})$$

This proves why circular LEO constellations require at least 10 satellites per orbital plane ($\Delta\theta \le 36^\circ$) to establish uninterrupted optical crosslink loops.

### 3.3 Strict Functional Determinism
In distributed satellite constellations, non-deterministic mission planners produce conflicting command uplinks and divergent state estimates. NADIR enforces pure determinism:
* Zero global mutable state or unchecked side effects in core planning algorithms.
* State evolution modeled as pure functional transitions: $\text{Step}(S_k, \Delta t) \to S_{k+1}$.
* Chronological sorting invariants eliminating reverse-accumulator order inversion bugs.

---

## 4. Repository Structure

```
nadir/
├── src/                               # Mercury source codebase
│   ├── nadir.m                        # Top-level CLI router and dispatcher
│   ├── nadir_core.m                   # Library root interface
│   ├── nadir_core.astro.*             # Astrodynamics, geodesy, Kepler, Cowell, time
│   ├── nadir_core.access.*            # Swath geometry, target access, Earth occultation
│   ├── nadir_core.platform.*          # Quaternions, ADCS slew, EPS power, SSR storage
│   ├── nadir_core.scheduler.*         # Constraint logic solver and mission planner
│   ├── nadir_core.isl.*               # Walker-Delta mesh, contact graph, Dijkstra routing
│   ├── nadir_core.ground.*            # Ground station network, passes, ACM link budgets
│   ├── nadir_core.io_*.m              # TLE, CSV, Cesium CZML, and GeoJSON exporters
│   ├── nadir_core.sim.m               # Closed-loop discrete-event constellation simulator
│   ├── nadir_core.c_fastpath.m        # Mercury FFI bindings to C99 acceleration
│   ├── nadir_core.regression.m        # Pure Mercury astrodynamics regression suite
│   ├── test_runner.m                  # Comprehensive engine test harness (69 tests)
│   └── bench_runner.m                 # Performance microbenchmark suite
├── c_src/                             # ANSI C99 hardware acceleration
│   ├── nadir_c_glue.h                 # Vector SIMD prototypes and inline math
│   └── nadir_c_glue.c                 # Fastpath Bowring geodetic and POSIX timers
├── data/                              # Datasets and mission catalogs
│   ├── constellations/                # Sentinel-2, Planet Flock, Walker-Delta TLEs
│   ├── ground_stations/               # Global tracking network specifications
│   └── targets/                       # Critical infrastructure and disaster tasks
├── tools/                             # Operational utilities and frontends
│   ├── live_dashboard.py              # Terminal curses live constellation telemetry
│   ├── visualize_czml.py              # Standalone CesiumJS 3D WebGL orbital visualizer
│   ├── constellation_generator.py     # Parametric Walker-Delta TLE synthesizer
│   ├── tle_validator.py               # NORAD TLE checksum and range validator
│   └── tle_fetcher.py                 # Live CelesTrak TLE fetcher and cache
├── tests/                             # Python integration and regression suites
│   ├── test_cli.py                    # Multi-subcommand CLI end-to-end tests
│   ├── test_simulation.py             # Schema, CZML, and GeoJSON validation tests
│   ├── test_regression.py             # Astrodynamics mathematical regression tests
│   ├── test_astrodynamics_properties.py # Property-based randomized invariant tests
│   └── test_structure.py              # Binary build and integrity tests
├── docs/                              # Formal mathematical specifications
│   ├── ARCHITECTURE.md                # System topology and dataflow pipelines
│   ├── ASTRODYNAMICS.md               # Geodesy, Kepler, J2 secular, Cowell RK4
│   ├── ISL_ROUTING.md                 # Link budgets, grazing rays, contact graphs
│   ├── SCHEDULER.md                   # Constraint satisfaction and ADCS agility
│   ├── GROUND_SEGMENT.md              # Pass geometry, ACM profiles, dish contention
│   └── VERIFICATION.md                # Error bounds, test matrix, benchmark tables
├── scripts/                           # Engineering automation
│   └── verify_no_em_dashes.py         # Automated unicode punctuation checker
└── Makefile                           # Build, test, benchmark, and clean targets
```

---

## 5. Prerequisites and Installation

### Dependencies
* **Mercury Compiler**: `mmc` version 22.01 or later (Homebrew: `brew install mercury`)
* **C Compiler**: Apple Clang or GCC (supporting C99 standards)
* **Python**: Version 3.10 or later
* **GNU Make**

### Building from Source

```bash
# Clone the repository
git clone https://github.com/Aneesh495/nadir.git
cd nadir

# Build all binaries (nadir CLI, test runner, benchmark runner)
make all
```

The build produces three executables in `bin/`:
* `bin/nadir`: The main operational CLI router.
* `bin/test_runner`: Pure Mercury engine unit and regression test suite.
* `bin/bench_runner`: Astrodynamics microbenchmark harness.

---

## 6. Verification and Testing

NADIR maintains comprehensive test coverage across mathematical precision, coordinate transformations, and end-to-end CLI workflows:

```bash
# Run the complete automated test suite (lint, regression, properties, engine, CLI)
make test
```

### Verification Output Summary
```
Verifying absence of forbidden dashes...
PASSED: Scanned 74 files. Zero forbidden dashes found.
Running astrodynamics regression suite...
Ran 5 tests in 0.000s (OK)
Running property-based invariant test suite...
Ran 5 tests in 0.001s (OK)
Running Mercury test runner...
=== Running NADIR Astrodynamics Test Suite ===
  [PASS] J2000.0 epoch Julian Date exact match (2451545.0)
  [PASS] Geodetic <-> ECEF round trip (sub-millimeter precision)
  [PASS] ECI <-> ECEF coordinate rotation round trip (sub-nanometer precision)
  [PASS] Halley cubic Kepler solver converges to machine precision (<1e-12)
  [PASS] LEO 500km orbital period is nominal (~94.6 min)
  [PASS] 500km SSO analytical inclination matches theory (~97.4 deg)
  [PASS] J2 nodal precession rate matches Earth solar rate (~0.9856 deg/day)
  [PASS] Adjacent in-plane constellation satellites have clear optical LOS
  [PASS] 30 degree agile slew duration is nominal (~13s)
  [PASS] Constellation constraint solver fulfilled 100% of candidate tasks
  [PASS] Shortest ISL path found with optimal 2-hop routing
  [PASS] Svalbard polar ground pass detected with high elevation and capacity
  [PASS] C FFI vector dot fastpath matches pure Mercury (sub-picometer exact)
  [PASS] C FFI Bowring geodetic fastpath matches pure Mercury within sub-millimeter bound
=== Running NADIR Astrodynamics Mercury Regression Suite ===
  [PASS] Regression: Bowring North Pole singularity resolves to lat=pi/2, alt=0m
  [PASS] Regression: Bowring South Pole singularity resolves to lat=-pi/2, alt=0m
  [PASS] Regression: J2 nodal precession sign reverses across 90 deg inclination
  [PASS] Regression: Geostationary orbit period matches Earth sidereal day (~86164s)
  [PASS] Regression: Antipodal constellation crosslink is occulted by Earth
  [PASS] Regression: Direct radial zenith satellite produces 90 degree elevation
=== All Engine Unit Tests Passed ===
Running full Python test discovery suite...
Ran 21 tests in 0.058s (OK)
```

---

## 7. Command-Line Interface (CLI) Guide

### 7.1 Orbit Propagation (`propagate`)
Propagates a Keplerian state vector under $J_2$ secular perturbations:

```bash
./bin/nadir propagate --semi-major 7000000 --ecc 0.001 --inc 98.2 --duration 3600 --step 600
```

### 7.2 Optical Crosslink Routing (`route`)
Synthesizes a 48-satellite Walker-Delta mesh, evaluates Earth occultations, and calculates the lowest-latency optical path:

```bash
./bin/nadir route --source 0 --target 3 --horizon 3600
```

Sample output:
```
[ISL Route Result]
  Source Node : 0 (Plane 0, Sat 0)
  Target Node : 3 (Plane 0, Sat 3)
  Hop Count   : 2 hops
  Total Path  : 0 -> 1 -> 3
  Total Delay : 18.2 ms
  Link Status : Active Optical Crosslink Established
```

### 7.3 Observation Scheduling (`schedule`)
Ingests target requests and generates a conflict-free, ADCS-feasible observation timeline:

```bash
./bin/nadir schedule --targets data/targets/disaster_response_tasks.csv --horizon 7200
```

### 7.4 Closed-Loop Constellation Simulation (`simulate`)
Runs a multi-satellite mission simulation tracking battery SoC, SSR storage, and downlinks:

```bash
./bin/nadir simulate --demo
```

---

## 8. Operational Tools and Visualizers

### 8.1 Terminal Curses Live Telemetry Dashboard
Monitors real-time constellation sub-satellite coordinates, battery health, and optical link topologies directly in the terminal:

```bash
python3 tools/live_dashboard.py
```

### 8.2 CesiumJS 3D WebGL Geospatial Visualizer
Generates interactive 3D WebGL orbital visualizations with dynamic laser crosslink polylines:

```bash
python3 tools/visualize_czml.py --input data/samples/constellation_mesh.czml --output viewer.html
open viewer.html
```

### 8.3 Parametric Walker-Delta TLE Synthesizer
Generates mathematically valid, checksum-verified NORAD TLE datasets for arbitrary Walker-Delta configurations:

```bash
python3 tools/constellation_generator.py --total 48 --planes 4 --phase 1 --alt 500 --inc 97.4 --output data/constellations/walker_48_4_1.tle
```

### 8.4 NORAD TLE Integrity Validator
Inspects and validates NORAD Two-Line Element sets against orbital element physical boundaries and modulo-10 checksums:

```bash
python3 tools/tle_validator.py data/constellations/sentinel2.tle
```

---

## 9. Performance Benchmarks

Run the hardware-accelerated microbenchmark harness:

```bash
make bench
```

Measured performance on Apple Silicon (M-series, 64-bit ARM, macOS):

| Benchmark Kernel | Pure Mercury | C99 FFI Fastpath | Throughput / Acceleration |
|---|---|---|---|
| **3D Vector Dot Product** | 840 Mops/s | 995 Mops/s | **995,000,000 ops/sec** (1.18x) |
| **3D Vector Cross Product** | 410 Mops/s | 472 Mops/s | **472,000,000 ops/sec** (1.15x) |
| **WGS-84 Bowring Geodesy** | 4.4 Kops/s | 13.5 Kops/s | **13,500 ops/sec** (3.07x) |
| **J2 Kepler Orbit Propagator** | 1.99 Mops/s | - | **1,990,000 states/sec** |
| **24-Sat ISL Mesh Graph** | 16,600 graphs/s | - | **16,600 graphs/sec** |

---

## 10. License

This project is licensed under the Apache 2.0 Open Source License.
