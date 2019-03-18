:- module nadir_core.platform.quaternion.
:- interface.

:- import_module float, string.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.vec3.

:- type quat
    --->    quat(
                q_w :: float, % Scalar component
                q_x :: float, % Vector component X
                q_y :: float, % Vector component Y
                q_z :: float  % Vector component Z
            ).

% Constructors and constants
:- func quat_identity = quat.
:- func quat_from_axis_angle(vec3, float) = quat.

% Quaternion algebra
:- func quat_conjugate(quat) = quat.
:- func quat_norm_sqr(quat) = float.
:- func quat_norm(quat) = float.
:- func quat_normalize(quat) = quat.
:- func quat_mul(quat, quat) = quat.

% Attitude rotations
:- func quat_rot_vec(quat, vec3) = vec3.
:- func quat_to_mat3(quat) = mat3.
:- func quat_angle_between(quat, quat) = float.

% Spherical Linear Interpolation (SLERP) with parameter T in [0, 1]
:- func quat_slerp(quat, quat, float) = quat.

% Formatting
:- func format_quat(quat) = string.

:- implementation.

:- import_module math, list.
:- import_module nadir_core.astro.constants.

quat_identity = quat(1.0, 0.0, 0.0, 0.0).

quat_from_axis_angle(Axis, Angle) = Q :-
    AxisNorm = vec3_normalize(Axis),
    HalfAngle = Angle * 0.5,
    SinHalf = sin(HalfAngle),
    CosHalf = cos(HalfAngle),
    Q = quat(CosHalf,
             AxisNorm ^ v_x * SinHalf,
             AxisNorm ^ v_y * SinHalf,
             AxisNorm ^ v_z * SinHalf).

quat_conjugate(quat(W, X, Y, Z)) = quat(W, -X, -Y, -Z).

quat_norm_sqr(quat(W, X, Y, Z)) = (W * W) + (X * X) + (Y * Y) + (Z * Z).

quat_norm(Q) = sqrt(quat_norm_sqr(Q)).

quat_normalize(Q) = Normed :-
    N = quat_norm(Q),
    ( if N > 1.0e-15 then
        InvN = 1.0 / N,
        Normed = quat(Q ^ q_w * InvN,
                      Q ^ q_x * InvN,
                      Q ^ q_y * InvN,
                      Q ^ q_z * InvN)
      else
        Normed = quat_identity
    ).

% Hamilton product: q1 * q2
quat_mul(quat(W1, X1, Y1, Z1), quat(W2, X2, Y2, Z2)) =
    quat(W1 * W2 - X1 * X2 - Y1 * Y2 - Z1 * Z2,
         W1 * X2 + X1 * W2 + Y1 * Z2 - Z1 * Y2,
         W1 * Y2 - X1 * Z2 + Y1 * W2 + Z1 * X2,
         W1 * Z2 + X1 * Y2 - Y1 * X2 + Z1 * W2).

% Rotate 3D vector by unit quaternion: v' = q * [0, v] * q*
quat_rot_vec(Q, V) = V_rot :-
    Q_norm = quat_normalize(Q),
    Q_vec = quat(0.0, V ^ v_x, V ^ v_y, V ^ v_z),
    Q_res = quat_mul(quat_mul(Q_norm, Q_vec), quat_conjugate(Q_norm)),
    V_rot = vec3(Q_res ^ q_x, Q_res ^ q_y, Q_res ^ q_z).

% Convert unit quaternion to 3x3 direction cosine rotation matrix
quat_to_mat3(Q) = mat3(Row0, Row1, Row2) :-
    Qn = quat_normalize(Q),
    W = Qn ^ q_w,
    X = Qn ^ q_x,
    Y = Qn ^ q_y,
    Z = Qn ^ q_z,
    X2 = X * X,
    Y2 = Y * Y,
    Z2 = Z * Z,
    XY = X * Y,
    XZ = X * Z,
    YZ = Y * Z,
    WX = W * X,
    WY = W * Y,
    WZ = W * Z,
    Row0 = vec3(1.0 - 2.0 * (Y2 + Z2), 2.0 * (XY - WZ), 2.0 * (XZ + WY)),
    Row1 = vec3(2.0 * (XY + WZ), 1.0 - 2.0 * (X2 + Z2), 2.0 * (YZ - WX)),
    Row2 = vec3(2.0 * (XZ - WY), 2.0 * (YZ + WX), 1.0 - 2.0 * (X2 + Y2)).

% Angular distance between two attitudes in radians: theta = 2 * acos(|q1 . q2|)
quat_angle_between(Q1, Q2) = Angle :-
    Dot0 = (Q1 ^ q_w * Q2 ^ q_w) +
           (Q1 ^ q_x * Q2 ^ q_x) +
           (Q1 ^ q_y * Q2 ^ q_y) +
           (Q1 ^ q_z * Q2 ^ q_z),
    Dot = abs(Dot0),
    ( if Dot >= 1.0 then Angle = 0.0
      else Angle = 2.0 * acos(Dot)
    ).

% Spherical Linear Interpolation
quat_slerp(Q1, Q2_in, T) = Q_out :-
    Q1_norm = quat_normalize(Q1),
    Q2_norm = quat_normalize(Q2_in),
    Dot0 = (Q1_norm ^ q_w * Q2_norm ^ q_w) +
           (Q1_norm ^ q_x * Q2_norm ^ q_x) +
           (Q1_norm ^ q_y * Q2_norm ^ q_y) +
           (Q1_norm ^ q_z * Q2_norm ^ q_z),
    % Ensure shortest path on 4D sphere
    ( if Dot0 < 0.0 then
        Q2 = quat(-Q2_norm ^ q_w, -Q2_norm ^ q_x, -Q2_norm ^ q_y, -Q2_norm ^ q_z),
        Dot = -Dot0
      else
        Q2 = Q2_norm,
        Dot = Dot0
    ),
    ( if Dot > 0.9995 then
        % Linear interpolation fallback for nearly identical orientations
        Q_lerp = quat(Q1_norm ^ q_w + T * (Q2 ^ q_w - Q1_norm ^ q_w),
                      Q1_norm ^ q_x + T * (Q2 ^ q_x - Q1_norm ^ q_x),
                      Q1_norm ^ q_y + T * (Q2 ^ q_y - Q1_norm ^ q_y),
                      Q1_norm ^ q_z + T * (Q2 ^ q_z - Q1_norm ^ q_z)),
        Q_out = quat_normalize(Q_lerp)
      else
        Theta_0 = acos(Dot),
        Theta = Theta_0 * T,
        SinTheta_0 = sin(Theta_0),
        SinTheta = sin(Theta),
        S1 = cos(Theta) - Dot * SinTheta / SinTheta_0,
        S2 = SinTheta / SinTheta_0,
        Q_out = quat(S1 * Q1_norm ^ q_w + S2 * Q2 ^ q_w,
                     S1 * Q1_norm ^ q_x + S2 * Q2 ^ q_x,
                     S1 * Q1_norm ^ q_y + S2 * Q2 ^ q_y,
                     S1 * Q1_norm ^ q_z + S2 * Q2 ^ q_z)
    ).

format_quat(quat(W, X, Y, Z)) = Str :-
    string.format("[W: %0.5f, X: %0.5f, Y: %0.5f, Z: %0.5f]", [f(W), f(X), f(Y), f(Z)], Str).
