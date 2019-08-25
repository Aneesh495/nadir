# Astrodynamics Mathematical Foundations and Numerical Formulations

This document provides the mathematical foundations, coordinate reference frames, perturbation equations, and numerical solvers implemented across the NADIR astrodynamics engine.

---

## 1. Coordinate Reference Systems and Geodesy

### 1.1 Earth-Centered Inertial (ECI J2000)
The ECI frame is an unaccelerated Cartesian coordinate system defined at the epoch J2000.0 (January 1, 2000, 12:00:00 TT):
* The origin is located at the center of mass of the Earth.
* The fundamental plane is the mean Earth equatorial plane at J2000.0.
* The positive x-axis points toward the mean vernal equinox ($\Upsilon$) at J2000.0.
* The positive z-axis is normal to the fundamental plane, aligned with Earth's rotation axis.
* The positive y-axis completes the right-handed orthogonal triad: $\hat{\mathbf{y}} = \hat{\mathbf{z}} \times \hat{\mathbf{x}}$.

### 1.2 Earth-Centered Earth-Fixed (ECEF WGS-84)
The ECEF frame rotates with the Earth:
* The origin coincides with the Earth center of mass.
* The fundamental plane is the true equatorial plane.
* The positive x-axis intersects the IERS Reference Meridian (zero longitude).
* The positive z-axis points toward the IERS Reference Pole (CIP).
* The positive y-axis points toward $90^\circ$ East longitude.

### 1.3 Sidereal Rotation Matrix
The coordinate rotation between ECI and ECEF is modeled through Greenwich Mean Sidereal Time (GMST) $\theta_{\text{gmst}}$:

$$\mathbf{r}_{\text{ECEF}} = \mathbf{R}_z(\theta_{\text{gmst}}) \mathbf{r}_{\text{ECI}}$$

$$\mathbf{R}_z(\theta) = \begin{bmatrix} \cos\theta & \sin\theta & 0 \\ -\sin\theta & \cos\theta & 0 \\ 0 & 0 & 1 \end{bmatrix}$$

For velocity transformation, the Coriolis velocity component due to Earth rotation rate $\boldsymbol{\omega}_{\oplus} = [0, 0, \omega_{\oplus}]^T$ ($\omega_{\oplus} = 7.2921150 \times 10^{-5}\text{ rad/s}$) is accounted for:

$$\mathbf{v}_{\text{ECEF}} = \mathbf{R}_z(\theta_{\text{gmst}}) \mathbf{v}_{\text{ECI}} - \boldsymbol{\omega}_{\oplus} \times \mathbf{r}_{\text{ECEF}}$$

The inverse transformation is exact:

$$\mathbf{r}_{\text{ECI}} = \mathbf{R}_z(-\theta_{\text{gmst}}) \mathbf{r}_{\text{ECEF}}$$

$$\mathbf{v}_{\text{ECI}} = \mathbf{R}_z(-\theta_{\text{gmst}}) \left( \mathbf{v}_{\text{ECEF}} + \boldsymbol{\omega}_{\oplus} \times \mathbf{r}_{\text{ECEF}} \right)$$

### 1.4 WGS-84 Reference Ellipsoid
The reference surface is an oblate spheroid of revolution defined by:
* Semi-major axis (equatorial radius): $a = 6378137.0\text{ m}$
* Reciprocal flattening: $1/f = 298.257223563$
* Semi-minor axis (polar radius): $b = a(1 - f) \approx 6356752.314245\text{ m}$
* First eccentricity squared: $e^2 = 2f - f^2 = \frac{a^2 - b^2}{a^2} \approx 6.69437999014 \times 10^{-3}$
* Second eccentricity squared: $e'^2 = \frac{a^2 - b^2}{b^2} = \frac{e^2}{1 - e^2} \approx 6.73949674228 \times 10^{-3}$

### 1.5 Direct Geodetic Transformation (Geodetic to ECEF)
Given geodetic latitude $\phi$, longitude $\lambda$, and ellipsoidal height $h$:

$$N(\phi) = \frac{a}{\sqrt{1 - e^2 \sin^2\phi}}$$

$$\begin{aligned}
x &= (N(\phi) + h) \cos\phi \cos\lambda \\
y &= (N(\phi) + h) \cos\phi \sin\lambda \\
z &= \left(N(\phi)(1 - e^2) + h\right) \sin\phi
\end{aligned}$$

### 1.6 Inverse Geodetic Transformation (Bowring Closed-Form Algorithm)
Given Cartesian coordinates $(x, y, z)$, Bowring's algorithm provides sub-millimeter geodetic coordinates without expensive iterative loops:

$$p = \sqrt{x^2 + y^2}, \quad \lambda = \text{atan2}(y, x)$$

If $p < 10^{-6}\text{ m}$ (polar singularity):
$$\phi = \begin{cases} +\frac{\pi}{2} & \text{if } z \ge 0 \\ -\frac{\pi}{2} & \text{if } z < 0 \end{cases}, \quad h = |z| - b$$

Otherwise, evaluate the parametric auxiliary latitude $\theta$:
$$\theta = \text{atan2}(z \cdot a, \; p \cdot b)$$

The geodetic latitude $\phi$ is calculated directly:
$$\phi = \text{atan2}\left( z + e'^2 b \sin^3\theta, \; p - e^2 a \cos^3\theta \right)$$

The prime vertical radius of curvature and altitude are obtained:
$$N(\phi) = \frac{a}{\sqrt{1 - e^2 \sin^2\phi}}, \quad h = \frac{p}{\cos\phi} - N(\phi)$$

---

## 2. Orbital Mechanics and Keplerian Dynamics

### 2.1 State Vector Representations
A spacecraft orbit is uniquely specified by:
1. Cartesian state: $\mathbf{r} = [x, y, z]^T$, $\mathbf{v} = [v_x, v_y, v_z]^T$
2. Classical Keplerian orbital elements: $(a, e, i, \Omega, \omega, \nu)$
   * $a$: Semi-major axis
   * $e$: Orbital eccentricity ($0 \le e < 1$ for elliptic orbits)
   * $i$: Inclination relative to equatorial plane ($0 \le i \le \pi$)
   * $\Omega$: Right Ascension of the Ascending Node (RAAN) ($0 \le \Omega < 2\pi$)
   * $\omega$: Argument of perigee ($0 \le \omega < 2\pi$)
   * $\nu$: True anomaly ($0 \le \nu < 2\pi$)

### 2.2 Cartesian to Keplerian Conversion
Given $\mathbf{r}$ and $\mathbf{v}$:
1. Specific angular momentum: $\mathbf{h} = \mathbf{r} \times \mathbf{v}$, with magnitude $h = \|\mathbf{h}\|$.
2. Node line vector: $\mathbf{n} = \hat{\mathbf{z}} \times \mathbf{h} = [-h_y, h_x, 0]^T$, with magnitude $n_0 = \|\mathbf{n}\|$.
3. Eccentricity vector:
   $$\mathbf{e} = \frac{1}{\mu} \left[ (v^2 - \frac{\mu}{r}) \mathbf{r} - (\mathbf{r} \cdot \mathbf{v}) \mathbf{v} \right], \quad e = \|\mathbf{e}\|$$
4. Specific mechanical energy:
   $$\mathcal{E} = \frac{v^2}{2} - \frac{\mu}{r} = -\frac{\mu}{2a} \implies a = -\frac{\mu}{2\mathcal{E}}$$
5. Inclination: $i = \arccos(h_z / h)$.
6. RAAN:
   $$\Omega = \begin{cases} \arccos(n_x / n_0) & \text{if } n_y \ge 0 \\ 2\pi - \arccos(n_x / n_0) & \text{if } n_y < 0 \end{cases}$$
7. Argument of perigee:
   $$\omega = \begin{cases} \arccos\left(\frac{\mathbf{n} \cdot \mathbf{e}}{n_0 e}\right) & \text{if } e_z \ge 0 \\ 2\pi - \arccos\left(\frac{\mathbf{n} \cdot \mathbf{e}}{n_0 e}\right) & \text{if } e_z < 0 \end{cases}$$
8. True anomaly:
   $$\nu = \begin{cases} \arccos\left(\frac{\mathbf{e} \cdot \mathbf{r}}{e r}\right) & \text{if } \mathbf{r} \cdot \mathbf{v} \ge 0 \\ 2\pi - \arccos\left(\frac{\mathbf{e} \cdot \mathbf{r}}{e r}\right) & \text{if } \mathbf{r} \cdot \mathbf{v} < 0 \end{cases}$$

---

## 3. Halley Cubic-Order Kepler Solver

To determine position at future time $t$, the mean anomaly $M = M_0 + n(t - t_0)$ must be inverted to find eccentric anomaly $E$ via Kepler's equation:

$$f(E) = E - e \sin E - M = 0$$

While standard Newton-Raphson achieves second-order quadratic convergence:
$$E_{k+1} = E_k - \frac{f(E_k)}{f'(E_k)}$$

NADIR implements Halley's third-order rational method:

$$E_{k+1} = E_k - \frac{2 f(E_k) f'(E_k)}{2 [f'(E_k)]^2 - f(E_k) f''(E_k)}$$

Where the derivatives of $f(E)$ are:
$$f'(E) = 1 - e \cos E$$
$$f''(E) = e \sin E$$

### Cubic Convergence Properties
* **Convergence Order**: $p = 3$. If $\epsilon_k = |E_k - E^*|$, then $\epsilon_{k+1} \approx C \epsilon_k^3$.
* **Initial Guess**:
  $$E_0 = M + \frac{e \sin M}{1 - \sin(M + e) + \sin M}$$
* **Termination Criterion**: $|E_{k+1} - E_k| < 10^{-12}\text{ rad}$. In benchmark tests across high eccentricities ($e \le 0.8$), Halley's method converges to double-precision machine epsilon in 2 to 3 iterations.

Once $E$ is determined, true anomaly $\nu$ is calculated via the half-angle relation:
$$\nu = 2 \arctan\left( \sqrt{\frac{1 + e}{1 - e}} \tan\frac{E}{2} \right)$$

---

## 4. Perturbation Mechanics: J2 Geopotential Zonal Harmonics

Due to the Earth's equatorial bulge, the gravitational potential deviates from a pure point-mass field. Expanding in Legendre polynomials:

$$V(r, \phi) = -\frac{\mu}{r} \left[ 1 - \sum_{k=2}^{\infty} J_k \left(\frac{R_e}{r}\right)^k P_k(\sin\phi) \right]$$

Retaining the dominant second zonal harmonic $J_2 = 1.08262668 \times 10^{-3}$:

$$V_{J_2}(r, \phi) = -\frac{\mu J_2 R_e^2}{2 r^3} (3 \sin^2\phi - 1)$$

### 4.1 Secular Perturbation Rates
Averaging the disturbing potential over one orbital period yields the secular rates of the orbital elements:
* Semi-major axis, eccentricity, and inclination experience zero secular drift:
  $$\langle \dot{a} \rangle = 0, \quad \langle \dot{e} \rangle = 0, \quad \langle \dot{i} \rangle = 0$$
* **Nodal Precession Rate** (regression of the ascending node):
  $$\dot{\Omega}_{J_2} = -\frac{3}{2} n J_2 \left(\frac{R_e}{p}\right)^2 \cos i$$
  Where $p = a(1 - e^2)$ is the semi-latus rectum, and $n = \sqrt{\mu / a^3}$ is the mean motion.
* **Argument of Perigee Advance**:
  $$\dot{\omega}_{J_2} = \frac{3}{4} n J_2 \left(\frac{R_e}{p}\right)^2 (5 \cos^2 i - 1)$$
  At the critical inclinations $i = 63.4349^\circ$ and $i = 116.565^\circ$, $5\cos^2 i - 1 = 0$, causing perigee drift to cease.
* **Perturbed Mean Motion**:
  $$n^* = n \left[ 1 + \frac{3}{4} J_2 \left(\frac{R_e}{p}\right)^2 \sqrt{1 - e^2} (2 - 3 \sin^2 i) \right]$$

### 4.2 Sun-Synchronous Orbit (SSO) Design
Earth orbits the Sun once per tropical year ($365.24219$ days), rotating the Sun vector at:
$$\dot{\Omega}_{\odot} = \frac{2\pi}{365.24219 \times 86400} \approx 1.99106 \times 10^{-7}\text{ rad/s} \approx 0.9856^\circ/\text{day}$$

To ensure a constant solar illumination angle (constant Local Time of Ascending Node, LTAN), the nodal precession must match the mean solar motion:

$$\dot{\Omega}_{J_2} = \dot{\Omega}_{\odot} \implies \cos i_{\text{SSO}} = -\frac{2}{3} \frac{\dot{\Omega}_{\odot}}{n J_2} \left(\frac{p}{R_e}\right)^2$$

Because $\dot{\Omega}_{\odot} > 0$, $\cos i_{\text{SSO}}$ is strictly negative, requiring a retrograde inclination ($i > 90^\circ$). For a 500 km circular orbit ($a = 6878137\text{ m}$), $i_{\text{SSO}} \approx 97.4^\circ$.

---

## 5. Cowell Numerical Integration and Atmosphere Modeling

For high-precision propagation over long horizons, NADIR implements Cowell's method:

$$\ddot{\mathbf{r}} = \mathbf{a}_{\text{grav}} + \mathbf{a}_{J_2} + \mathbf{a}_{\text{drag}}$$

$$\mathbf{a}_{\text{grav}} = -\frac{\mu}{r^3} \mathbf{r}$$

$$\mathbf{a}_{J_2} = -\frac{3 \mu J_2 R_e^2}{2 r^5} \begin{bmatrix}
x \left( 1 - 5 \frac{z^2}{r^2} \right) \\
y \left( 1 - 5 \frac{z^2}{r^2} \right) \\
z \left( 3 - 5 \frac{z^2}{r^2} \right)
\end{bmatrix}$$

Atmospheric drag is parameterized by ballistic coefficient $B = \frac{C_D A}{m}$ and exponential density $\rho(h) = \rho_0 \exp(-h / H)$:

$$\mathbf{a}_{\text{drag}} = -\frac{1}{2} C_D \frac{A}{m} \rho(h) \|\mathbf{v}_{\text{rel}}\| \mathbf{v}_{\text{rel}}$$

Integration is performed using the classical 4th-order Runge-Kutta (RK4) tableau:
$$\mathbf{y}_{k+1} = \mathbf{y}_k + \frac{\Delta t}{6} (k_1 + 2 k_2 + 2 k_3 + k_4)$$
Providing local truncation error $O(\Delta t^5)$ and global truncation error $O(\Delta t^4)$.
