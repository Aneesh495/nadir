:- module nadir_core.astro.vec3.
:- interface.

:- import_module float, string.

:- type vec3
    --->    vec3(
                v_x :: float,
                v_y :: float,
                v_z :: float
            ).

:- type mat3
    --->    mat3(
                m_row0 :: vec3,
                m_row1 :: vec3,
                m_row2 :: vec3
            ).

% Constructors and constants
:- func vec3_zero = vec3.
:- func vec3_unit_x = vec3.
:- func vec3_unit_y = vec3.
:- func vec3_unit_z = vec3.
:- func mat3_identity = mat3.

% Vector operations
:- func vec3_add(vec3, vec3) = vec3.
:- func vec3_sub(vec3, vec3) = vec3.
:- func vec3_scale(float, vec3) = vec3.
:- func vec3_dot(vec3, vec3) = float.
:- func vec3_cross(vec3, vec3) = vec3.
:- func vec3_norm_sqr(vec3) = float.
:- func vec3_norm(vec3) = float.
:- func vec3_normalize(vec3) = vec3.
:- func vec3_dist(vec3, vec3) = float.
:- func vec3_angle(vec3, vec3) = float.

% Matrix operations
:- func mat3_transpose(mat3) = mat3.
:- func mat3_mul_vec(mat3, vec3) = vec3.
:- func mat3_mul(mat3, mat3) = mat3.
:- func mat3_rot_x(float) = mat3.
:- func mat3_rot_y(float) = mat3.
:- func mat3_rot_z(float) = mat3.

% Formatting
:- func format_vec3(vec3) = string.

:- implementation.

:- import_module math, list.

vec3_zero = vec3(0.0, 0.0, 0.0).
vec3_unit_x = vec3(1.0, 0.0, 0.0).
vec3_unit_y = vec3(0.0, 1.0, 0.0).
vec3_unit_z = vec3(0.0, 0.0, 1.0).

mat3_identity = mat3(vec3_unit_x, vec3_unit_y, vec3_unit_z).

vec3_add(vec3(X1, Y1, Z1), vec3(X2, Y2, Z2)) = vec3(X1 + X2, Y1 + Y2, Z1 + Z2).

vec3_sub(vec3(X1, Y1, Z1), vec3(X2, Y2, Z2)) = vec3(X1 - X2, Y1 - Y2, Z1 - Z2).

vec3_scale(S, vec3(X, Y, Z)) = vec3(S * X, S * Y, S * Z).

vec3_dot(vec3(X1, Y1, Z1), vec3(X2, Y2, Z2)) = (X1 * X2) + (Y1 * Y2) + (Z1 * Z2).

vec3_cross(vec3(X1, Y1, Z1), vec3(X2, Y2, Z2)) =
    vec3(Y1 * Z2 - Z1 * Y2,
         Z1 * X2 - X1 * Z2,
         X1 * Y2 - Y1 * X2).

vec3_norm_sqr(V) = vec3_dot(V, V).

vec3_norm(V) = sqrt(vec3_norm_sqr(V)).

vec3_normalize(V) = Normed :-
    N = vec3_norm(V),
    ( if N > 1.0e-15 then
        Normed = vec3_scale(1.0 / N, V)
      else
        Normed = vec3_zero
    ).

vec3_dist(V1, V2) = vec3_norm(vec3_sub(V1, V2)).

vec3_angle(V1, V2) = Angle :-
    N1 = vec3_norm(V1),
    N2 = vec3_norm(V2),
    ( if (N1 > 1.0e-15, N2 > 1.0e-15) then
        CosVal0 = vec3_dot(V1, V2) / (N1 * N2),
        ( if CosVal0 > 1.0 then CosVal = 1.0
          else if CosVal0 < -1.0 then CosVal = -1.0
          else CosVal = CosVal0
        ),
        Angle = acos(CosVal)
      else
        Angle = 0.0
    ).

mat3_transpose(mat3(vec3(R00, R01, R02),
                    vec3(R10, R11, R12),
                    vec3(R20, R21, R22))) =
    mat3(vec3(R00, R10, R20),
         vec3(R01, R11, R21),
         vec3(R02, R12, R22)).

mat3_mul_vec(mat3(R0, R1, R2), V) =
    vec3(vec3_dot(R0, V),
         vec3_dot(R1, V),
         vec3_dot(R2, V)).

mat3_mul(M1, M2) = Res :-
    M2T = mat3_transpose(M2),
    M2T = mat3(Col0, Col1, Col2),
    M1 = mat3(Row0, Row1, Row2),
    Res = mat3(
        vec3(vec3_dot(Row0, Col0), vec3_dot(Row0, Col1), vec3_dot(Row0, Col2)),
        vec3(vec3_dot(Row1, Col0), vec3_dot(Row1, Col1), vec3_dot(Row1, Col2)),
        vec3(vec3_dot(Row2, Col0), vec3_dot(Row2, Col1), vec3_dot(Row2, Col2))
    ).

mat3_rot_x(Angle) =
    mat3(vec3(1.0, 0.0, 0.0),
         vec3(0.0, cos(Angle), -sin(Angle)),
         vec3(0.0, sin(Angle), cos(Angle))).

mat3_rot_y(Angle) =
    mat3(vec3(cos(Angle), 0.0, sin(Angle)),
         vec3(0.0, 1.0, 0.0),
         vec3(-sin(Angle), 0.0, cos(Angle))).

mat3_rot_z(Angle) =
    mat3(vec3(cos(Angle), -sin(Angle), 0.0),
         vec3(sin(Angle), cos(Angle), 0.0),
         vec3(0.0, 0.0, 1.0)).

format_vec3(vec3(X, Y, Z)) = Str :-
    string.format("[%0.6f, %0.6f, %0.6f]", [f(X), f(Y), f(Z)], Str).
