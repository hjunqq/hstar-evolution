# R27 closure — expectations stated BEFORE the runs (2026-09-09)

Class of change: TOOL change only (breakpoint placement in
tools/yl_io_inventory.py gdb-script). No legacy source change, no rebuild:
all four runs use one and the same binary build/trace-r27/hstar
sha256 361e7b2858b6572cc272ba063358edaad730d705b6f336471d3c27300cb652ec.

Design facts measured before the runs (not predictions):
 D1 1022 sites -> 1259 breakpoint locations; 101 sites have >1 location; 0 fallbacks.
 D2 Load.f90:231 has exactly 2 locations: 0x5a9b16 and 0x5a9e38.
 D3 89 of the 101 multi-location sites are NOT in the recorded 211-site hit set,
    i.e. the search space in which new sites could appear is non-empty.

Predictions:
 E1 POSITIVE CONTROL. New script, both cases: hits.json contains "Load.f90:231"
    with count >= 1, machine-generated (no manual_additions). If it is absent the
    new script has the same defect and every clean result from it is worthless
    -> report immediately, do not work around.
 E2 NEGATIVE CONTROL / MUST STAY SILENT. Old (HEAD) script, same binary, same
    cases: "Load.f90:231" must be ABSENT. This is what attributes E1 to the tool
    change rather than to the binary or the deck.
 E3 MUST STAY SILENT. Global.f90:1250 and Prescrib.f90:173, :174, :176 must be
    ABSENT from BOTH new hit sets. They are structurally unreachable on the
    whitelist; if the new script reports them, its address enumeration is
    over-broad (breaking on code that belongs to a neighbouring statement) and
    any new site it finds is suspect.
 E4 gdb must create exactly the requested number of breakpoints: "LOCATIONS 1259 1259".
 E5 Numerics unperturbed: compare-vs-reference identical for both cases
    (yl_io_trace.sh exits 5 otherwise).
 E6 New hit set is a SUPERSET of the old-script hit set on the same binary.
 E7 Old script on my binary reproduces the recorded 211-site set exactly
    (0 added, 0 removed) -- i.e. the binary rebuild is inert for the hit set.
 E8 Counts of single-location sites are identical between old and new runs;
    only multi-location sites may show larger counts (one execution can cross
    two ranges of the same line).
 Unknown, to be measured: whether any site other than Load.f90:231 appears.

Second round (max-merge rule, stated before the re-run):
 E9 Site sets unchanged (212 on both cases, still 0 added / 0 removed vs the
    recorded evidence).
 E10 All 11 count inflations disappear: count diff vs the recorded hits.json
    is empty on both cases.
 E11 Load.f90:231: hits_by_range shows 0x5a9e38 = 1 and 0x5a9b16 ABSENT
    (must stay silent). That is the direct machine confirmation of the
    hand-made observation in M1-finding-2026-09-08.

Third round — sensitivity control (stated in-session before the control run,
written into this file only afterwards, so it counts as an INFORMAL expectation):
 E12 Breaking on EVERY line-table row of a site's line (5508 locations), rather
     than only on the first address of each contiguous run (1259 locations),
     would find the SAME site set.
     RESULT: REFUTED. all-rows finds 4 sites that run-starts misses
     (Output.f90:4301, :4326, :4351, Temper.f90:243), and inside Load.f90:231's
     first range -- whose start 0x5a9b16 never fires -- five interior rows DO
     fire. Interior rows are reached by jumps without the run start executing,
     so run-start grouping carries the same class of defect as R27 itself.
     The tool is therefore changed to break on every row address.

Fourth round (all-rows tool, stated before the re-run):
 E13 Both cases: 216 distinct sites; new - recorded(211 machine) = exactly
     {Load.f90:231, Output.f90:4301, Output.f90:4326, Output.f90:4351,
      Temper.f90:243} on cooks_membrane; lame_cylinder not yet measured.
 E14 Counts for all sites already in the recorded evidence stay IDENTICAL under
     the max merge rule (must stay silent: no count diff on the 211).
 E15 Silent controls still absent: Global.f90:1250, Prescrib.f90:173/:174/:176.
 E16 Numerics still identical to reference on both cases.
 E17 `yl_io_inventory.py check` now FAILS -- the four new sites are executed but
     unregistered. (It cannot fail on that by itself: check only validates
     registered entries, so it may still PASS; the diff, not check, is the
     detector. Recorded as an open question rather than a prediction.)

Fifth round — instruction-level control (stated before the run):
 E18 Breakpoints on EVERY INSTRUCTION (47965) inside the line-table ranges of
     the 806 sites that the shipped tool reports as NOT executed: zero HIT lines
     on cooks_membrane. A hit would mean the line-table-row tool still
     under-detects, and would have to be reported as an open defect.
 E19 The run still exits 0 and its 1.flavia.res still compares identical to the
     frozen reference (an instrumentation that perturbs the run proves nothing).
