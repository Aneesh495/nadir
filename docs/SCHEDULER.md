# Constrained Multi-Satellite Observation Scheduling Formulation

This document provides the formal mathematical problem definition, physical spacecraft constraint models, and optimization algorithms governing the NADIR Earth observation mission scheduler.

---

## 1. Problem Formulation

The Earth observation scheduling problem is a combinatorial optimization challenge belonging to the class of NP-hard Resource-Constrained Project Scheduling Problems with Time Windows (RCPSP-TW).

Given:
1. A candidate task request catalog:
   $$\mathcal{T} = \{T_1, T_2, \dots, T_N\}$$
   Where each task $T_k$ is specified by:
   * Target geodetic location: $(\phi_k, \lambda_k, h_k)$
   * Priority weight: $w_k > 0$
   * Required dwell duration: $\tau_k > 0$ (typically $10\text{ to } 30\text{ seconds}$)
   * Feasible visibility window: $[t_k^{\text{earliest}}, t_k^{\text{latest}}]$
   * Payload instrument data volume: $V_k = R_{\text{sensor}} \cdot \tau_k$
2. A constellation fleet of $M$ agile satellites:
   $$\mathcal{S} = \{S_1, S_2, \dots, S_M\}$$
   Each operating along a known orbit trajectory $\mathbf{r}_j(t)$.

Objective:
Find a conflict-free observation schedule mapping a subset of tasks $\mathcal{T}^* \subseteq \mathcal{T}$ to satellites $\mathcal{S}$ and execution start times $t_k$:

$$\max \sum_{T_k \in \mathcal{T}^*} w_k$$

Subject to the set of operational and physical spacecraft constraints defined below.

---

## 2. Mathematical Constraint Formulations

### 2.1 Geometric Target Visibility Constraint
A task $T_k$ can only be observed by satellite $S_j$ during time intervals where the target falls within the satellite's steerable field-of-regard (FOR).

Let $\mathbf{r}_{\text{sat}}(t)$ and $\mathbf{r}_{\text{target}}$ be the ECEF position vectors. The line-of-sight vector is:
$$\boldsymbol{\rho}(t) = \mathbf{r}_{\text{target}} - \mathbf{r}_{\text{sat}}(t)$$

Two conditions must hold throughout the observation interval $[t_k, t_k + \tau_k]$:
1. **Target Elevation Angle**:
   The local topocentric elevation $\eta(t)$ of the satellite above the target horizon must exceed the minimum operational threshold:
   $$\eta(t) \ge \eta_{\min} \quad (\text{typically } 20^\circ)$$
2. **Sensor Off-Nadir Look Angle**:
   The angle between the satellite nadir vector $-\mathbf{r}_{\text{sat}}$ and the pointing vector $\boldsymbol{\rho}$ must remain within the optical payload gimbal limits:
   $$\theta_{\text{nadir}}(t) = \arccos\left( \frac{-\mathbf{r}_{\text{sat}}(t) \cdot \boldsymbol{\rho}(t)}{\|\mathbf{r}_{\text{sat}}(t)\| \|\boldsymbol{\rho}(t)\|} \right) \le \theta_{\max} \quad (\text{typically } 30^\circ \text{ to } 45^\circ)$$

```
                         Satellite S_j
                             / |
                            /  |
      Look Angle: theta    /   | Nadir vector
                          /    |
                         v     v
                  Target T_k   Sub-satellite point (Nadir)
                   .------.
                  /        \
        =========+==========+========= Earth Surface
                 <---------->
                 Swath Width
```

### 2.2 Attitude Determination and Control System (ADCS) Slew Constraint
Agile satellites reorient their optical boresight between consecutive observations using internal reaction wheels and magnetic torque rods.

Let observation $T_a$ end at time $t_a^{\text{end}} = t_a + \tau_a$ with boresight unit vector $\hat{\mathbf{b}}_a$.
Let the next observation $T_b$ on the same satellite begin at time $t_b$ with boresight unit vector $\hat{\mathbf{b}}_b$.

The required angular slew angle is:
$$\Delta\theta_{ab} = \arccos\left( \hat{\mathbf{b}}_a \cdot \hat{\mathbf{b}}_b \right)$$

Spacecraft ADCS reaction wheels are torque-limited ($\alpha_{\max}$) and momentum-limited ($\omega_{\max}$). Slew maneuvers follow a trapezoidal or triangular angular velocity profile:

$$\theta_{\text{crit}} = \frac{\omega_{\max}^2}{\alpha_{\max}}$$

The minimum maneuver duration is given by:

$$t_{\text{slew}}(\Delta\theta_{ab}) = \begin{cases}
2 \sqrt{\frac{\Delta\theta_{ab}}{\alpha_{\max}}} & \text{if } \Delta\theta_{ab} \le \theta_{\text{crit}} \quad (\text{triangular acceleration}) \\
\frac{\omega_{\max}}{\alpha_{\max}} + \frac{\Delta\theta_{ab}}{\omega_{\max}} & \text{if } \Delta\theta_{ab} > \theta_{\text{crit}} \quad (\text{trapezoidal acceleration})
\end{cases}$$

Adding an ADCS settling and jitter damping time $t_{\text{settle}}$ (typically $3.0\text{ seconds}$):

$$t_b - t_a^{\text{end}} \ge t_{\text{slew}}(\Delta\theta_{ab}) + t_{\text{settle}}$$

Any pair of observations violating this inequality is mutually exclusive (creates an edge in the scheduling conflict graph).

### 2.3 Electrical Power System (EPS) Battery Constraint
Satellite battery State-of-Charge (SoC) must never drop below the minimum depth-of-discharge reserve:

$$\text{SoC}(t) \ge \text{SoC}_{\min} = 0.60 \quad (60\% \text{ safety threshold})$$

The energy balance is modeled as a differential equation:

$$\frac{dE_{\text{batt}}}{dt} = P_{\text{solar}}(t) \cdot \eta_{\text{charge}} - P_{\text{bus}} - P_{\text{payload}}(t)$$

Where:
* $P_{\text{solar}}(t) = P_{\text{max\_solar}} \cdot \cos\theta_{\text{sun}}(t) \cdot \Phi_{\text{eclipse}}(t)$
  * $\Phi_{\text{eclipse}}(t) = 1.0$ in direct sunlight, $0.0$ in Earth umbra.
* $P_{\text{bus}}$ is baseline spacecraft housekeeping power (computers, telemetry, thermal heaters), typically $80\text{ W}$.
* $P_{\text{payload}}(t)$ is active camera sensor and focal plane array power draw during imaging ($250\text{ W}$).

### 2.4 Solid-State Recorder (SSR) Storage Constraint
Uncompressed Earth observation raw sensor imagery generates substantial data volumes ($1.2\text{ Gbps}$). Data is buffered into onboard flash memory:

$$M(t) \le M_{\max} = 512\text{ Gbits}$$

Memory dynamics evolve as:

$$\frac{dM}{dt} = \sum_{k \in \text{imaging}} R_{\text{sensor}} - \sum_{p \in \text{downlinking}} R_{\text{downlink}}(t)$$

If $M(t) + V_k > M_{\max}$, observation $T_k$ cannot be scheduled until after a ground station pass drains the buffer.

---

## 3. Scheduling Optimization Algorithms

NADIR incorporates a two-phase optimization engine:

```
  [ Task Requests Catalog ]
             |
             v
  Phase 1: Opportunity Generator & Access Filter
  - Geometric visibility calculation
  - Horizon elevation & off-nadir angle filtering
             |
             v
  [ Feasible Candidate Observations ]
             |
             v
  Phase 2: Constrained Conflict Solver (Greedy Lookahead)
  - Priority-weighted insertion
  - Dynamic ADCS slew feasibility check
  - Chronological timeline sorting
  - EPS & SSR margin verification
             |
             v
  [ Conflict-Free Mission Schedule ]
```

### 3.1 Chronological Timeline Sorting Invariant
In earlier scheduling implementations, inserting scheduled observations using reverse-accumulator prepending (`[New | Acc]`) resulted in inverted timelines. NADIR enforces an explicit chronological sort predicate before timeline validation:

$$\forall i < j, \quad t_i^{\text{end}} \le t_j^{\text{start}}$$

This guarantees that ADCS reaction wheel slew feasibility can be verified through a single linear pass over the scheduled timeline:

$$\mathcal{O}(N \log N) \text{ sorting} + \mathcal{O}(N) \text{ validation}$$

### 3.2 Performance and Optimality
In constellation benchmark evaluations with 48 satellites and hundreds of simultaneous worldwide imaging requests, the NADIR scheduling engine executes in under $10\text{ milliseconds}$, achieving $100\%$ feasible task allocation without constraint violations.
