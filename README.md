# nadir

An autonomous Earth observation satellite constellation mission planning, J2-perturbed orbit propagation, target access geometry, agile slew scheduling, and optical inter-satellite link (ISL) contact routing engine written in Mercury.

```
       .---.                .-.
      /     \    __        /   \
     |  (o)  |  (  )      | (o) |     [ Satellite Constellation Mesh ]
      \     /    )(        \   /
       '---'    (__)        '-'
         \       ||          /
          \  Optical ISL    /
           \   Crosslink   /
            \             /
             v           v
          .-----------------.
         /                   \
        |    WGS-84 Earth     |
        |   Target Clusters   |
         \                   /
          '-----------------'
```

## Architectural Overview

`nadir` is an end-to-end mission planning and constellation coordination system designed for high-revisit Earth observation constellations. The core logic is built in Mercury, taking advantage of pure declarative logic programming, strong static typing, determinism analysis, and definite clause grammars.

Key subsystems:

1. Astrodynamics Core (`astro`):
   - J2 secular perturbation and Keplerian state vector propagation.
   - High-precision time scales: UTC, TAI, Terrestrial Time (TT), Julian Date, and GMST sidereal rotations.
   - WGS-84 ellipsoidal transformations between ECI (J2000), ECEF (ITRF), and Topocentric horizon frames (SEZ/AER).
   - Analytical solar and lunar ephemeris with cylindrical and dual-cone Earth shadow / eclipse geometry.

2. Access Geometry Engine (`access`):
   - Field-of-view (FOV) and field-of-regard (FOR) projection on the WGS-84 oblate spheroid.
   - Ground target visibility intervals (access windows) with minimum elevation masks and solar lighting constraints.
   - Off-nadir look angle, slant range, and line-of-sight Earth limb occultation checking for inter-satellite crosslinks.

3. Spacecraft Platform Dynamics (`platform`):
   - Unit quaternion kinematics, Euler attitude representations, and spherical linear interpolation.
   - Agile slew trajectory synthesis under reaction wheel torque and angular acceleration limits.
   - Electrical power system (EPS) battery state-of-charge tracking across sunlit and eclipse passes.
   - Onboard solid-state recorder (SSR) mass memory partition modeling.

4. Constraint Satisfaction Scheduler (`scheduler`):
   - Pure declarative constraint logic formulation of observation requests.
   - Branch-and-bound optimization with conflict-directed clause ordering.
   - Squeaky Wheel Optimization (SWO) heuristic for multi-orbit constellation tasking.
   - Elimination of slew overlaps, power depletion, and camera duty cycle thermal violations.

5. Optical Inter-Satellite Link Mesh (`isl`):
   - Dynamic contact graph generation for Walker-Delta and Walker-Star constellation topologies.
   - Contact Graph Routing (CGR) and time-expanded shortest path search for low-latency image telemetry.
   - Delay-tolerant bundle queueing for store-and-forward operations during link occultations.

6. Ground Segment Allocation (`ground`):
   - Multi-station polar and equatorial ground network modeling.
   - High-rate X/Ka-band downlink pass geometry and elevation-dependent link budgets.
   - Downlink contact scheduling resolving antenna dish contention.

7. Telemetry & Mission Simulation (`sim`):
   - Closed-loop discrete-event simulation stepping through constellation orbits.
   - Real-time tracking of imaging yields, battery depth of discharge, memory usage, and downlink latencies.

## Prerequisites

- Mercury compiler (`mmc`, version 22.01 or later)
- C compiler (Apple Clang or GCC)
- Python 3.10+ (for operational CLI tools, data generation, and telemetry visualizers)
- GNU Make

## Quick Start

```bash
# Build the Mercury engine and binaries
make all

# Run the complete test suite
make test

# Execute a constellation simulation
./bin/nadir simulate --constellation data/constellations/walker_delta_sample.json \
                    --targets data/targets/global_disaster_hotspots.json \
                    --duration 7200 \
                    --output results/mission_run.json

# Run benchmark suites
make bench
```

## Repository Structure

```
nadir/
├── src/            # Mercury modules and subsystems
│   ├── nadir.m     # Entrypoint and CLI dispatcher
│   ├── astro/      # Astrodynamics and orbit propagation
│   ├── access/     # Target visibility and sensor geometry
│   ├── platform/   # Quaternion kinematics and platform resources
│   ├── scheduler/  # Constraint logic solver and mission planner
│   ├── isl/        # Inter-satellite link mesh and routing
│   ├── ground/     # Ground station network and downlink allocator
│   ├── io/         # TLE parsers, DCGs, and format exporters
│   └── sim/        # Discrete-event constellation simulator
├── c_src/          # Native C fastpaths for linear algebra and timers
├── tools/          # Python operational utilities and visualization
├── data/           # Constellation definitions, ground stations, targets
├── tests/          # Mercury and Python verification suites
├── benchmarks/     # Performance and scaling microbenchmarks
├── docs/           # Technical derivations and subsystem specifications
└── scripts/        # Verification and build automation
```
