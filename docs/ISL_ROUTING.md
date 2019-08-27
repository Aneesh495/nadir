# Optical Inter-Satellite Link (ISL) Mesh Architecture and Routing Protocols

This document details the physical link budgets, geometric occultation limits, Walker-Delta constellation mesh topologies, and dynamic shortest-path routing algorithms implemented in NADIR.

---

## 1. Free-Space Optical (FSO) Laser Communications

Inter-satellite crosslinks in modern Earth observation constellations utilize coherent infrared laser communication terminals (LCT) operating at $\lambda = 1550\text{ nm}$. Compared to traditional RF crosslinks (Ka-band), optical ISLs provide:
* Multi-gigabit per second data rates ($10\text{ Gbps}$ to $100\text{ Gbps}$).
* Narrow beam divergence angles ($\sim 10\text{ to } 30\ \mu\text{rad}$), yielding negligible probability of intercept and zero inter-satellite radio interference.
* Compact terminal mass, volume, and power requirements.

### 1.1 Optical Link Budget Formulation
The optical power received at a distance $d$ is governed by the Friis transmission equation adapted for Gaussian laser beams:

$$P_{\text{rx}} = P_{\text{tx}} \cdot G_{\text{tx}} \cdot L_{\text{fspl}} \cdot L_{\text{point}} \cdot \eta_{\text{tx}} \cdot \eta_{\text{rx}} \cdot G_{\text{rx}}$$

Where:
* $P_{\text{tx}}$ is the laser transmit optical power (e.g., $5\text{ W} \approx 37\text{ dBm}$).
* $G_{\text{tx}}$ is the transmitter optical telescope gain:
  $$G_{\text{tx}} = \left( \frac{\pi D_{\text{tx}}}{\lambda} \right)^2$$
  For aperture diameter $D_{\text{tx}} = 10\text{ cm}$ at $\lambda = 1550\text{ nm}$, $G_{\text{tx}} \approx 106.1\text{ dBi}$.
* $L_{\text{fspl}}$ is the Free Space Path Loss:
  $$L_{\text{fspl}} = \left( \frac{\lambda}{4\pi d} \right)^2$$
* $L_{\text{point}}$ is the pointing jitter loss resulting from satellite micro-vibrations:
  $$L_{\text{point}} = \exp\left( -G_{\text{tx}} \frac{\sigma_{\theta}^2}{2} \right)$$
  Where $\sigma_{\theta}$ is the root-mean-square angular tracking jitter.
* $G_{\text{rx}}$ is the receiver optical telescope gain:
  $$G_{\text{rx}} = \left( \frac{\pi D_{\text{rx}}}{\lambda} \right)^2$$
* $\eta_{\text{tx}}, \eta_{\text{rx}}$ are the optical efficiency factors of the optics and fine steering mirrors (typically $0.70$ to $0.85$).

---

## 2. Atmospheric Grazing and Geometric Occultation Limits

An optical laser beam passing through Earth's upper atmosphere undergoes severe wavefront distortion, Rayleigh and Mie scattering, and thermal refractive bending. To guarantee link integrity, an optical crosslink is occulted if the line-of-sight ray penetrates the Earth's atmosphere below a safety altitude $h_{\text{atm}} = 100\text{ km}$.

```
                 Satellite A (r1)
                      *
                       \
                        \   Ray: r(t) = r1 + t*(r2 - r1)
                         \
                          \        Closest approach: r_min
                           \       +---------+
                            \      |   *     | (Tangent altitude: h_tangent)
                             \     +---------+
                              \         |
                               \        v
                                \   Earth Surface (R_earth)
                                 \
                                  *
                             Satellite B (r2)
```

### 2.1 Derivation of Grazing Ray Tangent Altitude
Let $\mathbf{r}_1$ and $\mathbf{r}_2$ be the position vectors of two satellites in ECI or ECEF frame. The parametric line segment connecting them is:

$$\mathbf{r}(t) = \mathbf{r}_1 + t (\mathbf{r}_2 - \mathbf{r}_1) = \mathbf{r}_1 + t \mathbf{d}, \quad t \in [0, 1]$$

Where $\mathbf{d} = \mathbf{r}_2 - \mathbf{r}_1$. The squared distance from the Earth center of mass to the ray is:

$$f(t) = \|\mathbf{r}(t)\|^2 = \|\mathbf{r}_1\|^2 + 2 t (\mathbf{r}_1 \cdot \mathbf{d}) + t^2 \|\mathbf{d}\|^2$$

Differentiating with respect to $t$ and equating to zero:

$$\frac{df}{dt} = 2 (\mathbf{r}_1 \cdot \mathbf{d}) + 2 t \|\mathbf{d}\|^2 = 0 \implies t_{\min} = -\frac{\mathbf{r}_1 \cdot \mathbf{d}}{\|\mathbf{d}\|^2}$$

The point of closest approach along the ray segment is:

$$\mathbf{r}_{\text{closest}} = \begin{cases}
\mathbf{r}_1 & \text{if } t_{\min} \le 0 \\
\mathbf{r}_2 & \text{if } t_{\min} \ge 1 \\
\mathbf{r}_1 + t_{\min} \mathbf{d} & \text{if } 0 < t_{\min} < 1
\end{cases}$$

The tangent altitude above the reference spherical Earth radius $R_{\oplus} = 6378.137\text{ km}$ is:

$$h_{\text{tangent}} = \|\mathbf{r}_{\text{closest}}\| - R_{\oplus}$$

The optical crosslink is viable if and only if:
$$h_{\text{tangent}} \ge h_{\text{atm}} = 100\text{ km}$$

### 2.2 Critical Angular Spacing Limit for Circular Constellations
For two satellites in the same circular orbit of radius $r_{\text{orb}} = R_{\oplus} + h_{\text{sat}}$, the maximum angular separation $\Delta\theta_{\max}$ before Earth occultation occurs is derived from the right triangle formed by the Earth center, tangent point, and satellite:

$$\cos\left( \frac{\Delta\theta_{\max}}{2} \right) = \frac{R_{\oplus} + h_{\text{atm}}}{R_{\oplus} + h_{\text{sat}}}$$

$$\Delta\theta_{\max} = 2 \arccos\left( \frac{R_{\oplus} + h_{\text{atm}}}{R_{\oplus} + h_{\text{sat}}} \right)$$

Evaluating for a low Earth orbit at altitude $h_{\text{sat}} = 500\text{ km}$ ($r_{\text{orb}} = 6878.137\text{ km}$) with $h_{\text{atm}} = 100\text{ km}$ ($r_{\text{tangent}} = 6478.137\text{ km}$):

$$\frac{\Delta\theta_{\max}}{2} = \arccos\left( \frac{6478.137}{6878.137} \right) = \arccos(0.941845) \approx 19.636^\circ$$

$$\Delta\theta_{\max} \approx 39.27^\circ$$

#### Constellation Density Implication
For adjacent satellites within an orbital plane to maintain continuous, uninterrupted line-of-sight laser crosslinks, the angular separation must satisfy:

$$\Delta\theta = \frac{360^\circ}{S_{\text{plane}}} \le \Delta\theta_{\max} \approx 39.27^\circ \implies S_{\text{plane}} \ge \left\lceil \frac{360^\circ}{39.27^\circ} \right\rceil = 10\text{ satellites/plane}$$

This mathematical limit demonstrates why sparse constellations (such as 6 satellites per plane, $\Delta\theta = 60^\circ$) cannot maintain intra-plane ISLs, while a Walker-Delta 48/4/1 configuration (12 satellites per plane, $\Delta\theta = 30^\circ$) maintains robust, continuous intra-plane crosslinks.

---

## 3. Walker-Delta Constellation Mesh Topology

Walker-Delta constellations are parameterized by the notation $T / P / F$:
* $T$: Total number of satellites in the constellation.
* $P$: Number of equally spaced orbital planes.
* $F$: Phasing parameter ($0 \le F \le P - 1$), defining the relative true anomaly shift between adjacent planes:
  $$\Delta M = \frac{2\pi F}{T}$$
* Satellites per plane: $S = T / P$.
* RAAN spacing: $\Delta\Omega = 2\pi / P$.

```
Plane 0       Plane 1       Plane 2       Plane 3
   |             |             |             |
 [Sat 0] <=====> [Sat 12] <==> [Sat 24] <==> [Sat 36]  (Inter-plane crosslinks)
   ^             ^             ^             ^
   | (Intra)     | (Intra)     | (Intra)     | (Intra)
   v             v             v             v
 [Sat 1] <=====> [Sat 13] <==> [Sat 25] <==> [Sat 37]
   ^             ^             ^             ^
   |             |             |             |
   v             v             v             v
 [Sat 2] <=====> [Sat 14] <==> [Sat 26] <==> [Sat 38]
```

Each satellite node in the mesh hosts up to 4 optical communication terminals:
1. **Intra-Plane Fore (+v)**: Fixed pointing along velocity vector to satellite $(k + 1) \bmod S$ in the same plane.
2. **Intra-Plane Aft (-v)**: Fixed pointing anti-parallel to velocity vector to satellite $(k - 1 + S) \bmod S$ in the same plane.
3. **Inter-Plane Left (+w)**: Steerable gimbaled terminal tracking adjacent plane $(p + 1) \bmod P$.
4. **Inter-Plane Right (-w)**: Steerable gimbaled terminal tracking adjacent plane $(p - 1 + P) \bmod P$.

### 3.1 Seam Discontinuity Handling
In inclined Walker-Delta constellations, adjacent planes 0 and $P - 1$ at the boundary (the constellation "seam") have counter-rotating relative velocity vectors ($\sim 15\text{ km/s}$ at equatorial crossings). Optical terminals cannot maintain tracking across the seam without gimbal slip rings and extreme slew rates. NADIR explicitly isolates cross-seam links, routing traffic through the continuous intra-plane loops and polar convergence zones.

---

## 4. Contact Graph Routing Algorithms

The constellation communication topology is modeled as a time-varying contact graph:

$$G_t = (V, E_t, W_t)$$

Where:
* $V = \{s_0, s_1, \dots, s_{T-1}\}$ is the static set of satellite nodes.
* $E_t \subseteq V \times V$ is the dynamic set of active links at time $t$ satisfying range and occultation conditions.
* $W_t(u, v)$ is the link latency weight:
  $$W_t(u, v) = \tau_{\text{prop}}(u, v) + \tau_{\text{proc}} + \tau_{\text{tx}}$$
  Where propagation delay is $\tau_{\text{prop}} = \frac{\|\mathbf{r}_u(t) - \mathbf{r}_v(t)\|}{c}$ ($c \approx 299792458\text{ m/s}$), and $\tau_{\text{proc}}$ is store-and-forward packet processing latency.

### 4.1 Shortest Path Dijkstra Routing
To route high-priority Earth observation image metadata or emergency tasking requests from any source satellite $s_{\text{src}}$ to a destination satellite $s_{\text{dst}}$ with an active ground station downlink pass, NADIR implements an exact priority-queue Dijkstra algorithm:

1. Initialize tentative distance array: $D[v] \leftarrow \infty$ for all $v \in V$, $D[s_{\text{src}}] \leftarrow 0$.
2. Initialize predecessor map: $\Pi[v] \leftarrow \text{None}$.
3. Insert $(0, s_{\text{src}})$ into priority min-heap $Q$.
4. While $Q$ is non-empty:
   * Pop $(d_u, u)$ with minimum distance.
   * If $u = s_{\text{dst}}$, terminate search.
   * If $d_u > D[u]$, skip (stale heap entry).
   * For each neighbor $v$ such that $(u, v) \in E_t$:
     * New cost: $d_{\text{alt}} = D[u] + W_t(u, v)$.
     * If $d_{\text{alt}} < D[v]$:
       $$D[v] \leftarrow d_{\text{alt}}, \quad \Pi[v] \leftarrow u$$
       Insert $(d_{\text{alt}}, v)$ into $Q$.
5. Reconstruct optimal path by following predecessors from $s_{\text{dst}}$ backward to $s_{\text{src}}$.

Through this contact graph formulation, NADIR guarantees minimum-latency multi-hop data delivery across dynamic orbital topologies.
