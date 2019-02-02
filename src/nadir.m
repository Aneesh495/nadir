:- module nadir.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- use_module nadir_core.
:- use_module nadir_core.astro.
:- import_module nadir_core.astro.constants.
:- import_module nadir_core.astro.temporal.
:- import_module float, string, list.

main(!IO) :-
    DT = datetime(2026, 11, 19, 12, 0, 0.0),
    JD = datetime_to_jd(DT),
    GMST = datetime_to_gmst(DT),
    io.format("nadir constellation engine initialized\n", [], !IO),
    io.format("Epoch: %s (JD: %f, GMST: %f rad)\n",
        [s(format_iso8601(DT)), f(JD), f(GMST)], !IO).
