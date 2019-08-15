# NADIR System Architecture and Technical Design

NADIR is an autonomous Earth observation satellite constellation mission planning, orbit propagation, optical inter-satellite link (ISL) routing, and closed-loop telemetry simulation engine.

The core computational engine is written in pure Mercury, leveraging strong static typing, determinism analysis, and mathematical purity to eliminate runtime exceptions and state corruption. Time-critical vector arithmetic, WGS-84 ellipsoidal geodesy, and high-resolution POSIX timing are accelerated via an ANSI C99 foreign function interface (FFI). Operational telemetry dashboards, parametric constellation synthesizers, and WebGL 3D geospatial viewers are implemented in Python and modern web standards.

```
       +-------------------------------------------------------------+
       |                     NADIR CLI & Frontends                   |
       |     nadir CLI (Mercury)  /  Live Dashboard  /  Cesium CZML  |
       +-------------------------------------------------------------+
                                      |
       +-------------------------------------------------------------+
       |               Simulation & Mission Loop Engine              |
       |                (nadir_core.sim: discrete event)             |
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

---

## 1. Architectural Principles and Invariants

### 1.1 Pure Functional Determinism
In distributed satellite constellation operations, non-deterministic mission planning leads to telemetry divergence and conflicting command uplinks. NADIR enforces pure determinism across all algorithms:
* All Kepler solvers, coordinate rotations, and contact graph updates are referentially transparent functions.
* The mission simulation advances state through explicit functional fold transitions:
  `Step(State_k, Delta_t) -> State_{k+1}`.
* Floating-point calculations use strict IEEE-754 double precision without undefined compiler re-associations.

### 1.2 Separation of Astrodynamics and Mission Policy
Astrodynamic state vectors (position, velocity, GMST, solar elevation) represent physical ground truth and remain strictly decoupled from spacecraft platform state (battery state of charge, solid-state recorder buffer volume, camera thermal states). The mission policy layer reads orbital ephemeris as read-only telemetry streams and maps candidate opportunities into feasible schedules.

### 1.3 High-Performance Hybrid Model
* **Logical Rigor in Mercury**: Constraint satisfaction, contact graph search, TLE parsing, and schedule validation execute in Mercury. The compiler verifies that every predicate has deterministic behavior and that all union types are handled exhaustively.
* **Vector SIMD Fastpaths in C99**: Core 3-vector dot products, 3D cross products, and transcendental-heavy Bowring geodetic inversions execute in native C99 via Mercury pragma foreign_proc directives, delivering near-billion operation per second throughput.

---

## 2. Subsystem Decomposition

### 2.1 Astrodynamics Core (`nadir_core.astro.*`)
The astrodynamics core provides coordinate transformations, orbital propagation, and celestial body positioning:
* **`constants`**: IAU/WGS-84 physical constants: equatorial radius $a = 6378137.0\text{ m}$, flattening $f = 1/298.257223563$, Earth gravitational parameter $\mu = 3.986004418 \times 10^{14}\text{ m}^3/\text{s}^2$, and second zonal harmonic $J_2 = 1.08262668 \times 10^{-3}$.
* **`vec3`**: Vector and matrix algebra including dot product, cross product, Euclidean norm, orthonormal basis construction, and $3 \times 3$ Euler rotation matrices ($R_x, R_y, R_z$).
* **`temporal`**: High-precision timekeeping supporting Julian Date (JD), Modified Julian Date (MJD), J2000.0 epoch offsets, Greenwich Mean Sidereal Time (GMST), and ISO-8601 UTC timestamp parsing and serialization.
* **`coords`**: Bidirectional coordinate transforms:
  * Earth-Centered Inertial (ECI J2000) $\leftrightarrow$ Earth-Centered Earth-Fixed (ECEF WGS-84) accounting for continuous diurnal rotation and polar motion.
  * ECEF Cartesian $\leftrightarrow$ Geodetic (latitude, longitude, ellipsoidal altitude) via Bowring closed-form algorithm.
  * ECEF $\rightarrow$ Topocentric Horizon Frame (azimuth, elevation, slant range) relative to any ground station.
* **`kepler`**: Two-body Keplerian mechanics, state vector transformations ($r, v \leftrightarrow a, e, i, \Omega, \omega, \nu$), and Halley cubic-order iterative equation solver for eccentric anomaly $E$.
* **`propagator`**: Analytic first-order secular $J_2$ orbit propagator modeling nodal regression ($\dot{\Omega}$) and argument of perigee advance ($\dot{\omega}$), plus Sun-synchronous orbit (SSO) design calculations.
* **`cowell`**: High-fidelity Cowell numerical orbit propagator combining 4th-order Runge-Kutta (RK4) integration with $J_2$ geopotential acceleration and atmospheric density models.
* **`sun`**: Low-precision analytical solar ephemeris vector, cylindrical Earth shadow conical eclipse modeling (umbra, penumbra, sunlight), and local solar time evaluation.

### 2.2 Access and Occultation (`nadir_core.access.*`)
Evaluates geometric visibility between orbiting satellites and surface targets:
* **`footprint`**: Optical payload push-broom cross-track swath width and agile roll/pitch pointing access angles.
* **`target`**: Ground target access window detection based on line-of-sight elevation and sensor off-nadir angle constraints.
* **`occultation`**: Spherical Earth occultation checking for inter-satellite line-of-sight (LOS) links, calculating grazing ray tangent altitude above the WGS-84 ellipsoid.

### 2.3 Spacecraft Platform Dynamics (`nadir_core.platform.*`)
Simulates physical spacecraft subsystem limitations:
* **`quaternion`**: Unit quaternion kinematics, Hamilton product, vector attitude rotation, and spherical linear interpolation (SLERP).
* **`slew`**: Attitude Determination and Control System (ADCS) reaction wheel agile slew duration profiles modeling maximum angular velocity $\omega_{\max}$ and angular acceleration $\alpha_{\max}$.
* **`power`**: Electrical Power System (EPS) battery state-of-charge (SoC) integration accounting for solar array generation in sunlight and payload/bus power draw in eclipse.
* **`storage`**: Payload Solid-State Recorder (SSR) buffer dynamics modeling raw instrument data ingestion, compression, and high-rate RF/optical downlink drainage.

### 2.4 Constraint-Satisfaction Scheduler (`nadir_core.scheduler.*`)
Schedules high-value Earth observation imaging opportunities across the constellation:
* Priority-weighted value maximization.
* ADCS slew maneuver feasibility: ensuring sufficient time $\Delta t \ge t_{\text{slew}}(\theta) + t_{\text{settle}}$ between consecutive observations.
* Electrical power safety: preserving battery SoC above 60% minimum depth-of-discharge reserve.
* Solid-State Recorder storage limits: preventing buffer overflow prior to ground station downlink passes.

### 2.5 Optical Inter-Satellite Link Mesh (`nadir_core.isl.*`)
Maintains dynamic multi-hop laser crosslink routing across the constellation:
* **`topology`**: Walker-Delta parametric constellation mesh initialization with intra-plane (fore/aft) and inter-plane (cross-seam) laser communication terminals (LCT).
* **`contact_graph`**: Dynamic contact graph generation filtering links based on range limits and atmospheric occultation thresholds (minimum tangent altitude $> 100\text{ km}$).
* **`routing`**: Delay-tolerant Dijkstra shortest-path routing over the time-varying contact graph, minimizing end-to-end propagation and transmission latency.

### 2.6 Ground Segment Network (`nadir_core.ground.*`)
Manages satellite-to-ground tracking, telemetry, and downlink operations:
* **`stations`**: Global ground station catalog (e.g., Svalbard, Troll, Fairbanks, Punta Arenas, Inuvik) with horizon masks and multi-band antenna profiles (X-band, Ka-band, optical direct-to-Earth).
* **`passes`**: Acquisition of Signal (AOS) and Loss of Signal (LOS) pass detection with elevation-dependent Adaptive Coding and Modulation (ACM) throughput calculations.
* **`downlink`**: Multi-dish antenna contention allocation resolving overlapping passes across constellation satellites via greedy capacity scheduling.

### 2.7 Discrete-Event Mission Simulator (`nadir_core.sim.*`)
Executes closed-loop constellation operations across configurable simulation horizons:
* Step-by-step state propagation: orbit, attitude, power, storage, contact topology, and observation execution.
* Comprehensive telemetry collection: data downlinked, targets imaged, link outages, and power profiles.

---

## 3. Data Pipelines and Interchange Formats

```
[ NORAD Two-Line Elements (TLE) ] ----> [ nadir_core.io_tle ]
                                               |
[ Observation Requests (CSV)    ] ----> [ nadir_core.io_target ]
                                               |
                                               v
                                    +--------------------+
                                    |    NADIR Engine    |
                                    +--------------------+
                                      /        |        \
                                     /         |         \
                                    v          v          v
                          [ Cesium CZML ]  [ GeoJSON ]  [ Terminal ]
                          (3D Ephemeris &  (2D Ground   (Realtime Ops
                            Laser Mesh)      Tracks)      Dashboard)
```

1. **NORAD Two-Line Elements (TLE)**: Ingests raw orbital element sets, validates line format and modulo-10 checksums, and extracts mean motion, eccentricity, inclination, RAAN, argument of perigee, and epoch.
2. **Observation Requests CSV**: Ingests task catalog files specifying latitude, longitude, elevation, priority, duration, payload sensor mode, and ISO-8601 deadlines.
3. **Cesium CZML Documents**: Emits WGS-84 cartographic degrees and Cartesian positions sampled along orbit tracks, accompanied by dynamic polyline geometry representing active optical inter-satellite links.
4. **GeoJSON GIS Files**: Exports satellite sub-satellite ground track LineStrings, ground station coordinates with visibility circles, and observation targets.

---

## 4. Hardware Acceleration and Foreign Function Interface (FFI)

The FFI architecture isolates memory layouts between Mercury and C99:
* Scalar arguments (`float`, `int`) are passed directly by value across the ABI boundary.
* Pointers to raw arrays (`double*`) are encapsulated in C translation units, preventing heap pointer aliasing.
* All fastpath C functions are declared `static inline` in `c_src/nadir_c_glue.h` with compiler optimization flags (`-O3 -march=native -ffast-math`).

```
Mercury Caller (nadir_core.c_fastpath.m)
    |
    | pragma foreign_proc("C", ...)
    v
C99 Bridge (c_src/nadir_c_glue.c)
    |
    | Vector SIMD & Transcendental Optimizations
    v
Hardware Floating Point Units (FPU / NEON / AVX2)
```

Through this layered architecture, NADIR combines mathematical verification with real-time astrodynamic calculation throughput.
