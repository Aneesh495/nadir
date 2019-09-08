# Ground Segment Network Architecture and Downlink Allocation Protocol

This document details the ground station tracking geometry, elevation-dependent Adaptive Coding and Modulation (ACM) link budgets, and multi-satellite antenna contention allocation algorithms implemented in NADIR.

---

## 1. Ground Tracking Station Network Topology

In Earth observation missions, high-rate payload data downlink is constrained by satellite-to-ground station line-of-sight visibility. Polar ground stations provide substantial pass frequency for polar and Sun-synchronous (SSO) constellations:
* A satellite in a $98^\circ$ Sun-synchronous orbit completes roughly 14.5 orbits per day.
* A high-latitude ground station (e.g., Svalbard at $78.23^\circ\text{N}$ or Troll at $72.01^\circ\text{S}$) achieves line-of-sight contact on 10 to 14 of those daily orbits.
* Equatorial and mid-latitude stations (e.g., Punta Arenas, Fairbanks, Hartebeesthoek, Singapore) complement polar networks for inclined Walker-Delta constellations.

```
Station Name       Latitude      Longitude     Altitude    Dishes   Bands
-------------------------------------------------------------------------
Svalbard (SGS)     78.2306 deg   15.3894 deg    450 m        4      X, Ka
Troll (TLS)       -72.0114 deg    2.5350 deg   1275 m        3      X, Ka
Fairbanks (FCD)    64.9739 deg -147.5144 deg    300 m        2      X, Ka
Punta Arenas (PUQ)-53.1367 deg  -70.8803 deg     50 m        2      X, Ka
Inuvik (INV)       68.3560 deg -133.5358 deg    100 m        2      X, Ka
```

Each ground tracking station is parameterized by:
* Geodetic coordinates: $(\phi_s, \lambda_s, h_s)$
* Minimum elevation horizon mask: $\eta_{\text{mask}}$ (typically $5^\circ$)
* Number of independent steerable parabolic dishes: $N_{\text{dishes}}$
* Azimuth and elevation antenna slew rate limits ($\dot{A}_{\max} \approx 15^\circ/\text{s}, \dot{E}_{\max} \approx 10^\circ/\text{s}$)

---

## 2. Satellite-to-Ground Pass Geometry

### 2.1 Topocentric Horizon Coordinate Frame
Let $\mathbf{r}_{\text{site}}$ be the ECEF Cartesian position of the ground station, and $\mathbf{r}_{\text{sat}}$ be the satellite position in ECEF. The relative range vector is:

$$\boldsymbol{\rho}_{\text{ecef}} = \mathbf{r}_{\text{sat}} - \mathbf{r}_{\text{site}}$$

The topocentric East-North-Up (ENU) orthogonal basis at the ground site is defined by geodetic latitude $\phi$ and longitude $\lambda$:

$$\hat{\mathbf{e}} = \begin{bmatrix} -\sin\lambda \\ \cos\lambda \\ 0 \end{bmatrix}, \quad
\hat{\mathbf{n}} = \begin{bmatrix} -\sin\phi \cos\lambda \\ -\sin\phi \sin\lambda \\ \cos\phi \end{bmatrix}, \quad
\hat{\mathbf{u}} = \begin{bmatrix} \cos\phi \cos\lambda \\ \cos\phi \sin\lambda \\ \sin\phi \end{bmatrix}$$

Transforming $\boldsymbol{\rho}_{\text{ecef}}$ into ENU coordinates:

$$\begin{bmatrix} \rho_{\text{east}} \\ \rho_{\text{north}} \\ \rho_{\text{up}} \end{bmatrix} =
\begin{bmatrix} \hat{\mathbf{e}}^T \\ \hat{\mathbf{n}}^T \\ \hat{\mathbf{u}}^T \end{bmatrix} \boldsymbol{\rho}_{\text{ecef}}$$

The topocentric observables are:
* **Slant Range**: $\rho = \|\boldsymbol{\rho}\| = \sqrt{\rho_{\text{east}}^2 + \rho_{\text{north}}^2 + \rho_{\text{up}}^2}$
* **Azimuth Angle**: $A = \text{atan2}(\rho_{\text{east}}, \rho_{\text{north}}) \bmod 2\pi$
* **Elevation Angle**: $E = \arcsin\left( \frac{\rho_{\text{up}}}{\rho} \right)$

### 2.2 Ground Pass Lifecycle Events
1. **Acquisition of Signal (AOS)**: Timestamp $t_{\text{aos}}$ where $E(t)$ rises above $\eta_{\text{mask}}$.
2. **Time of Closest Approach (TCA)**: Timestamp $t_{\text{tca}}$ where slant range $\rho(t)$ is minimized and elevation $E(t)$ reaches its maximum $E_{\max}$.
3. **Loss of Signal (LOS)**: Timestamp $t_{\text{los}}$ where $E(t)$ drops below $\eta_{\text{mask}}$.

### 2.3 RAAN Analytical Phasing Formulation
Under coordinate rotations $\mathbf{R}_z(-\theta_{\text{gmst}})$ and $\mathbf{R}_z(-\Omega)$, the satellite ECEF longitude is governed by:

$$\lambda_{\text{sat}} = \Omega + \theta_{\text{gmst}}$$

For an orbit to produce an overhead meridian transit over a ground site with geodetic longitude $\lambda_{\text{site}}$ at epoch $t_0$, the required Right Ascension of the Ascending Node (RAAN) is analytically phased:

$$\Omega = \pi - \lambda_{\text{site}} - \theta_{\text{gmst}}(t_0)$$

And true anomaly $\nu_0$ is phased relative to geodetic latitude:
$$\nu_0 = \pi + \phi_{\text{site}} - \delta\nu_{\text{approach}}$$
Where $\delta\nu_{\text{approach}} \approx 6^\circ$ positions the satellite immediately prior to the ascending horizon crossing.

---

## 3. Elevation-Dependent Adaptive Coding and Modulation (ACM)

In high-rate satellite downlinks (CCSDS 131.2-B / DVB-S2X standards), atmospheric attenuation and free-space path loss vary drastically throughout a pass:
* Slant range at $5^\circ$ horizon elevation is roughly $2200\text{ km}$.
* Slant range at $90^\circ$ zenith is roughly $500\text{ km}$ (a factor of $4.4\times$ reduction, yielding nearly $13\text{ dB}$ higher signal-to-noise ratio).
* Atmospheric path length (air mass) scales approximately as $1 / \sin E$.

NADIR implements dynamic ACM link adaptation across three discrete elevation regimes:

```
Elevation Regime        Modulation & Coding       Throughput Rate
-----------------------------------------------------------------
Low   ( 5 deg <= E < 20 deg)   QPSK   1/2               200 Mbps
Mid   (20 deg <= E < 45 deg)   16-APSK 3/4              600 Mbps
High  (          E >= 45 deg)  64-APSK 5/6             1200 Mbps
```

The total downloadable data volume for pass $p$ is the discrete Riemann integral over pass duration:

$$C_{\text{pass}} = \int_{t_{\text{aos}}}^{t_{\text{los}}} R(E(t)) \, dt \approx \sum_{k=0}^{K-1} R(E(t_k)) \Delta t$$

A standard 10-minute polar pass over Svalbard with $E_{\max} \approx 82^\circ$ delivers approximately $300\text{ to } 400\text{ Gbits}$ of payload data.

---

## 4. Multi-Dish Ground Antenna Contention Resolution

When a constellation operates dozens of satellites in adjacent orbital planes, multiple satellites frequently enter the visibility horizon of a polar tracking station simultaneously.

```
       Time ----->
Dish 1:  [ Sat-01 Pass (High Cap: 340 Gb) ]  [ Sat-03 Pass (180 Gb) ]
Dish 2:  [ Sat-02 Pass (Medium: 220 Gb)   ]  [ Sat-04 Pass (290 Gb) ]
Contention: Sat-05 pass overlaps but no free dishes -> Reroute via ISL!
```

### 4.1 Contention Allocation Formulation
Let $\mathcal{P} = \{P_1, P_2, \dots, P_k\}$ be the candidate ground passes detected for ground station $G$ over time horizon $[0, T]$.
Station $G$ has $N_{\text{dish}}$ independent parabolic antennas.

No dish can track more than one satellite at a time:
$$\forall d \in \{1, \dots, N_{\text{dish}}\}, \quad [t_i^{\text{aos}}, t_i^{\text{los}}] \cap [t_j^{\text{aos}}, t_j^{\text{los}}] = \emptyset \quad (\forall i \ne j \text{ assigned to dish } d)$$

### 4.2 Greedy Capacity-Maximizing Scheduler
NADIR solves antenna contention using a priority-capacity greedy scheduling algorithm:
1. Calculate total downlink capacity $C_{\text{pass}}$ for every candidate pass using the ACM profile.
2. Sort all candidate passes in descending order of capacity:
   $$C_{P_1} \ge C_{P_2} \ge \dots \ge C_{P_k}$$
3. Maintain an availability timeline for each antenna dish:
   $$T_{\text{avail}}[d] \leftarrow 0 \quad (\forall d \in \{1, \dots, N_{\text{dish}}\})$$
4. For each pass $P_i$ in sorted order:
   * Search for an available dish $d$ where $T_{\text{avail}}[d] \le t_{P_i}^{\text{aos}}$.
   * If found:
     * Assign pass $P_i$ to dish $d$.
     * Update dish availability: $T_{\text{avail}}[d] \leftarrow t_{P_i}^{\text{los}} + t_{\text{repoint}}$.
   * If all dishes are busy:
     * Mark pass $P_i$ as conflicted/unallocated.
     * Flag satellite $S_{P_i}$ to retain data in onboard SSR or offload telemetry across the optical ISL mesh.

This algorithm achieves polynomial runtime complexity $\mathcal{O}(K \log K + K \cdot N_{\text{dish}})$ while guaranteeing maximal data extraction per ground station pass window.
