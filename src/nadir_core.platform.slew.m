:- module nadir_core.platform.slew.
:- interface.

:- import_module float, string.
:- use_module nadir_core.platform.
:- import_module nadir_core.platform.quaternion.

:- type agile_adcs_limits
    --->    agile_adcs_limits(
                al_max_torque       :: float, % Peak reaction wheel torque in N*m (e.g. 0.2 N*m)
                al_moment_inertia   :: float, % Principal spacecraft inertia in kg*m^2 (e.g. 8.0 kg*m^2)
                al_max_rate         :: float, % Peak slew rate in rad/s (e.g. 0.0698 rad/s = 4.0 deg/s)
                al_max_accel        :: float, % Peak angular acceleration in rad/s^2 (e.g. 0.0261 rad/s^2 = 1.5 deg/s^2)
                al_settling_time    :: float  % Sensor stabilization settling time in seconds (e.g. 3.0s)
            ).

:- type slew_profile
    --->    slew_profile(
                sp_delta_angle      :: float, % Total slew angle in radians
                sp_accel_time       :: float, % Acceleration phase duration in seconds
                sp_coast_time       :: float, % Constant rate coast phase duration in seconds
                sp_settling_time    :: float, % Settling time in seconds
                sp_total_duration   :: float, % Total duration in seconds
                sp_energy_joules    :: float  % Reaction wheel mechanical work in Joules
            ).

% Standard Earth observation satellite ADCS configurations
:- func default_agile_adcs = agile_adcs_limits.

% Compute bang-coast-bang slew profile for a given rotation angle
:- func compute_slew_profile(agile_adcs_limits, float) = slew_profile.

% Compute slew profile between two spacecraft attitude quaternions
:- func compute_attitude_slew(agile_adcs_limits, quat, quat) = slew_profile.

% Quick duration estimate between two angles
:- func slew_duration_seconds(agile_adcs_limits, float) = float.

% Formatting
:- func format_slew_profile(slew_profile) = string.

:- implementation.

:- import_module math, list.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.constants.

% Standard 120kg class satellite ADCS:
% Torque: 0.25 N*m, Inertia: 12.0 kg*m^2, MaxRate: 4.5 deg/s (0.0785 rad/s),
% MaxAccel: 0.0208 rad/s^2 (1.19 deg/s^2), Settling: 2.5s
default_agile_adcs =
    agile_adcs_limits(0.25, 12.0, deg_to_rad(4.5), deg_to_rad(1.2), 2.5).

compute_slew_profile(ADCS, DeltaAngle0) = Profile :-
    DeltaAngle = abs(DeltaAngle0),
    AlphaMax = ADCS ^ al_max_accel,
    OmegaMax = ADCS ^ al_max_rate,
    Settling = ADCS ^ al_settling_time,
    Inertia  = ADCS ^ al_moment_inertia,
    % Minimum time to reach maximum rate: t_acc = omega_max / alpha_max
    T_acc_limit = OmegaMax / AlphaMax,
    % Angle traversed during accel and decel to/from omega_max: theta_acc_limit = alpha_max * t_acc^2
    Theta_acc_limit = AlphaMax * (T_acc_limit * T_acc_limit),
    ( if DeltaAngle < Theta_acc_limit then
        % Triangular profile (does not reach omega_max)
        % theta = alpha * t_acc^2 => t_acc = sqrt(theta / alpha)
        T_acc = sqrt(DeltaAngle / AlphaMax),
        T_coast = 0.0,
        PeakRate = AlphaMax * T_acc
      else
        % Trapezoidal profile (bang-coast-bang)
        T_acc = T_acc_limit,
        Theta_coast = DeltaAngle - Theta_acc_limit,
        T_coast = Theta_coast / OmegaMax,
        PeakRate = OmegaMax
    ),
    TotalDuration = (2.0 * T_acc) + T_coast + Settling,
    % Mechanical work: E = 0.5 * I * peak_rate^2 for acceleration, and another for braking
    Energy = Inertia * (PeakRate * PeakRate),
    Profile = slew_profile(DeltaAngle, T_acc, T_coast, Settling, TotalDuration, Energy).

compute_attitude_slew(ADCS, Q1, Q2) =
    compute_slew_profile(ADCS, quat_angle_between(Q1, Q2)).

slew_duration_seconds(ADCS, DeltaAngle) =
    (compute_slew_profile(ADCS, DeltaAngle)) ^ sp_total_duration.

format_slew_profile(P) = Str :-
    string.format("Angle: %0.2f deg | Duration: %0.1fs (acc: %0.1fs, coast: %0.1fs, settle: %0.1fs) | Energy: %0.1f J",
        [f(rad_to_deg(P ^ sp_delta_angle)),
         f(P ^ sp_total_duration),
         f(P ^ sp_accel_time),
         f(P ^ sp_coast_time),
         f(P ^ sp_settling_time),
         f(P ^ sp_energy_joules)], Str).
