! yl_problem_profile -- the versioned default profile and the capability table.
!
! Scope (see .ccg/tasks/m3-02-normalize-validate-finalize/plan.md delivery 2,
! analysis.md "capability table" ruling, analysis-codex.md S5, analysis-claude.md S3)
!   Two read-only tables and their accessors. No I/O, no parsing, no state.
!     * DEFAULTS      -- values the pipeline may supply when the author did not,
!                        each stamped with the profile version that supplied it.
!     * CAPABILITIES  -- everything this build declares it CANNOT express, one row
!                        per checked item, each carrying the rule that owns it.
!                        Two partitions, `stage`; see the next section.
!
! THE TWO PARTITIONS OF THE CAPABILITY TABLE (M4-01 L2-b)
!   M3-02 shipped this table with one partition: the capability GATE's rows, read
!   after a draft exists. M4-01's legacy adapter needs the same declaration for a
!   second population -- the legacy dialects it refuses WHILE PARSING, before any
!   draft exists. The M4-01 plan (Layer 2) is explicit that this is an EXTENSION of
!   this table and not a second one, and the reason is the one M3-02 already paid
!   for: a rejection that lives only as a raise site in executable code cannot be
!   enumerated, so nothing can fail when it loses its counter-example.
!
!     CAP_STAGE_GATE   rows the capability gate reads out of a finished draft
!                      (yl_problem_pipeline). Payload: the whitelisted value.
!     CAP_STAGE_ADAPT  legacy dialects the adapter refuses at parse time
!                      (yl_adapter_*). Payload: none -- the observed value is a
!                      run-time fact the parser reports as `actual`, and the
!                      whitelisted value is either fixed in the message or, for the
!                      two mesh rows, read from a CAP_STAGE_GATE row of this same
!                      table. A dialect row therefore never restates a gate row.
!
!   The partitions are CONTIGUOUS and gate-first: rows 1..capability_count() are
!   gate rows, the rest are dialect rows. capability_* accessors see only the first
!   partition and dialect_* accessors only the second, so the M3-02 gate, its
!   coverage walk and its export are byte-for-byte unaffected by rows added here.
!   yl_adapter_dialect_test.f90 asserts the contiguity rather than trusting it.
!
! WHY A DIALECT ROW CARRIES A `condition` AND THE KEY IS COMPOSED
!   Carried from yl_runtime_rules (M3-03), which recorded why the M3-02 binding
!   triple was not enough: a rule id with several conditions behind it lets the
!   second and later conditions inherit the first one's apparent coverage. Two
!   dialect rows prove the point here -- A-MAT/contact-material and
!   A-MAT/nonlinear-normal-stiffness bind to the SAME (rule_id, object_path, field)
!   and are separated only by their condition. So `condition` is a column, the
!   stable id is dialect_key() = rule_id//'/'//condition computed from it, and a
!   raise site passes the two halves, never a pre-joined string: passing a bare
!   rule id where a composed key is expected is a real bug this project has already
!   shipped once, and the raiser (yl_adapter_parts) makes it impossible by
!   composing the key itself from the row it just looked up.
!
! Why Fortran constants and not a TOML file
!   Layer 3 of the target architecture has no I/O and no parser, so a table read at
!   run time would have to open a file from inside the pipeline. The tables are
!   therefore compiled in, and the ONE copy is exported for cross-checking rather
!   than transcribed: capability_row_text() renders a row in a stable, parseable
!   form, the self-test prints those rows, and the Python side compares them
!   against the map. There is deliberately no second table in Python to drift.
!
! Versioning
!   A default is only meaningful together with the profile that produced it, so
!   PROFILE_ID / PROFILE_VERSION are public and profile_lookup_* hands back the row
!   index that supplied the value. finalize records `key`, `map_id`, `rule_id` and
!   the profile tag in the manifest for every default it applies, which is what
!   makes a defaulted value auditable rather than indistinguishable from an
!   authored one.
!
! Vocabulary
!   Keys are CAE vocabulary, never Fortran slot names: the stress-component count
!   is `plane_strain.stress_components`, and the legacy map row it corresponds to
!   travels alongside in `map_id` as provenance only. This mirrors the rule that
!   keeps yl_problem_types.f90 free of legacy spellings.
!
! Scale
!   M3-02 has exactly ONE default row. The table, the typed payload discriminator
!   and the lookup are built for the sixteen further legacy_default rows that
!   M3-03 adds, so that growth is a table edit rather than a redesign.
!
! Deliberately absent from the capability table
!   `restart` and `steps[].load_mode`. The team lead ruled both out for M3-02:
!   neither has a constructible counter-example on the two golden decks at this
!   stage (the draft cannot express restart at all, and no M3-02 consumer reads
!   load_mode), and a gate item that cannot fail is exactly the defect this
!   milestone exists to stop shipping. Both return when a fixture can falsify them.
module yl_problem_profile

  use iso_fortran_env, only: int32

  implicit none
  private

  public :: profile_default_t, capability_item_t
  public :: profile_default_count, profile_default_row, profile_lookup_int, profile_lookup_text
  public :: capability_count, capability_row, capability_find, capability_row_text
  public :: capability_expect_int, capability_expect_text, capability_expect_logical
  public :: dialect_count, dialect_row, dialect_find, dialect_key, dialect_row_text
  public :: capability_table_row

  ! Fixed lengths, so that both tables can be PARAMETER arrays: a derived type with
  ! a deferred-length or allocatable component cannot be a named constant, and a
  ! named constant is what makes these tables provably read-only.
  integer, parameter :: LEN_KEY = 48
  integer, parameter :: LEN_MAP_ID = 48
  integer, parameter :: LEN_RULE = 24
  integer, parameter :: LEN_PATH = 40
  integer, parameter :: LEN_FIELD = 24
  integer, parameter :: LEN_VALUE = 32
  integer, parameter :: LEN_DTYPE = 8
  ! Dialect-row columns. LEN_COND is sized by the longest condition in the table
  ! ('stochastic-curve-modifier-unsupported', 37); LEN_MESSAGE by the longest
  ! message (188). Both are asserted against the table by the dialect self-test,
  ! so a row that would silently truncate fails the suite instead of shipping.
  integer, parameter :: LEN_COND = 40
  integer, parameter :: LEN_MESSAGE = 200

  ! --- profile identity -------------------------------------------------------

  character(len=*), parameter, public :: PROFILE_ID = 'static-q4-si'
  character(len=*), parameter, public :: PROFILE_VERSION = '1'
  character(len=*), parameter, public :: PROFILE_TAG = PROFILE_ID//'/'//PROFILE_VERSION

  ! --- capability identity ----------------------------------------------------

  character(len=*), parameter, public :: CAPABILITY_ID = 'static-q4'
  character(len=*), parameter, public :: CAPABILITY_VERSION = '1'
  character(len=*), parameter, public :: CAPABILITY_TAG = CAPABILITY_ID//'/'//CAPABILITY_VERSION

  ! --- payload discriminator --------------------------------------------------
  ! Which of the three payload members of a row carries the value. A row always
  ! sets exactly one; the other two keep their default initialisers and must not
  ! be read. This is a discriminator, not a sentinel: it says WHICH member is
  ! meaningful, it never encodes absence as a magic value.

  integer(int32), parameter, public :: PROFILE_KIND_INT = 1_int32
  integer(int32), parameter, public :: PROFILE_KIND_TEXT = 2_int32
  integer(int32), parameter, public :: PROFILE_KIND_LOGICAL = 3_int32
  ! A row with NO payload. Only CAP_STAGE_ADAPT rows use it: the value that made a
  ! dialect row fire is read from the deck at parse time and travels as the
  ! finding's `actual`, so there is nothing for the table to hold. This is a fourth
  ! member of the discriminator, not an absence sentinel -- capability_expect_*
  ! answers not-found for it exactly as it does for a kind mismatch.
  integer(int32), parameter, public :: PROFILE_KIND_NONE = 0_int32

  ! --- capability-table partitions --------------------------------------------
  ! Which enforcement stage owns a row. See the module header.

  integer(int32), parameter, public :: CAP_STAGE_GATE = 1_int32
  integer(int32), parameter, public :: CAP_STAGE_ADAPT = 2_int32

  ! The ONE outward name for "this deck is valid legacy that this build does not
  ! cover" (docs/02-migration-plan.md M4; docs/m4/adapter-contract.md SS4 assigns
  ! the unification to L2-b). It is deliberately NOT a new PE_* code: the contract
  ! pins the code of a dialect finding to PE_UNSUPPORTED, whose exit class is 3,
  ! and a second code spelling the same verdict would be a second thing to keep in
  ! step with exit_class_for_code. It is the adapter's verdict vocabulary --
  ! yl_adapter_parts's dialect_verdict_of() answers it, and nothing else spells it.
  character(len=*), parameter, public :: DIALECT_VERDICT = 'UNSUPPORTED_LEGACY_DIALECT'

  ! --- default profile row ----------------------------------------------------

  type :: profile_default_t
    character(len=LEN_KEY) :: key = ''          ! CAE vocabulary key, the lookup name
    character(len=LEN_MAP_ID) :: map_id = ''    ! M2 map row, provenance only
    character(len=LEN_RULE) :: rule_id = ''     ! the map `source` that justifies the default
    character(len=LEN_DTYPE) :: dtype = ''      ! map dtype of the defaulted value
    integer(int32) :: value_kind = PROFILE_KIND_INT
    integer(int32) :: int_value = 0_int32
    character(len=LEN_VALUE) :: text_value = ''
    logical :: logical_value = .false.
  end type profile_default_t

  ! The whole M3-02 default profile.
  !
  ! plane_strain.stress_components = 4: a plane-strain continuum point carries
  ! sxx, syy, szz and sxy. szz is not zero under plane strain, which is why the
  ! count is 4 and not 3, and it is a property of the formulation rather than of
  ! any authored input -- so it is a profile default, not a required field.
  type(profile_default_t), parameter :: DEFAULTS(1) = [                        &
    profile_default_t(key='plane_strain.stress_components',                    &
                      map_id='derived.counts.nstre',                           &
                      rule_id='derived:legacy_default',                        &
                      dtype='i32',                                             &
                      value_kind=PROFILE_KIND_INT,                             &
                      int_value=4_int32,                                       &
                      text_value='',                                           &
                      logical_value=.false.)]

  ! --- capability row ---------------------------------------------------------
  ! `item` is the CAE name of the checked property; `object_path` and `field` say
  ! which component of the ProblemState the gate reads, so the gate's rejection
  ! message can name the offending object without a second lookup table. A field
  ! of `size` means the check is on the cardinality of the collection named by
  ! object_path, not on a component of it.

  ! The three components added by M4-01 L2-b are APPENDED, not interleaved. The
  ! fifteen gate rows below are positional structure constructors written in M3-02;
  ! inserting a component would have silently re-bound every one of their arguments
  ! to the wrong component. Appending, with a default initialiser on each new
  ! component, leaves them valid and unchanged -- and CAP_STAGE_GATE as the default
  ! `stage` is what makes an M3-02 row a gate row without editing it.
  type :: capability_item_t
    character(len=LEN_RULE) :: rule_id = ''     ! G1..G6 (gate) or A-GLB/F1/A1.. (dialect)
    character(len=LEN_KEY) :: item = ''         ! gate: CAE name of the property
                                                ! dialect: the legacy deck symbol, e.g. glb.rmesh
    character(len=LEN_PATH) :: object_path = '' ! ProblemState object the value is read from
    character(len=LEN_FIELD) :: field = ''      ! component, or `size` for a cardinality
    integer(int32) :: value_kind = PROFILE_KIND_TEXT
    integer(int32) :: int_value = 0_int32
    character(len=LEN_VALUE) :: text_value = ''
    logical :: logical_value = .false.
    ! --- appended by M4-01 L2-b ---
    character(len=LEN_COND) :: condition = ''   ! dialect only: the second half of the key
    integer(int32) :: stage = CAP_STAGE_GATE    ! which partition this row belongs to
    character(len=LEN_MESSAGE) :: message = ''  ! dialect only: the wording of the rejection
  end type capability_item_t

  ! The one supported combination, static-q4/1. Grouped by owning gate rule:
  !   G1 element    -- what the element is
  !   G2 formulation-- what physics is being solved
  !   G3 material   -- what constitutive model
  !   G4 solver     -- which linear solver and which symmetry
  !   G5 load       -- which load kinds may appear
  !   G6 extent     -- how many sections, steps and increments
  ! Text values are the canonical upper-case spellings produced by normalize rule
  ! N1, so the gate compares canonical against canonical and never case-folds here.
  type(capability_item_t), parameter :: GATE_ROWS(*)      = [                                        &
    capability_item_t('G1', 'element.type', 'sections[]', 'element',                                &
                      PROFILE_KIND_TEXT, 0_int32, 'Q4', .false.),                                   &
    capability_item_t('G1', 'element.kind_code', 'sections[]', 'element_kind',                      &
                      PROFILE_KIND_INT, 5_int32, '', .false.),                                      &
    capability_item_t('G1', 'element.class', 'sections[]', 'class',                                 &
                      PROFILE_KIND_TEXT, 0_int32, 'CO', .false.),                                   &
    capability_item_t('G1', 'element.fields', 'sections[]', 'fields',                               &
                      PROFILE_KIND_TEXT, 0_int32, 'U', .false.),                                    &
    capability_item_t('G2', 'analysis.dimension', 'mesh', 'dimension',                              &
                      PROFILE_KIND_INT, 2_int32, '', .false.),                                      &
    capability_item_t('G2', 'element.formulation', 'sections[]', 'formulation',                     &
                      PROFILE_KIND_TEXT, 0_int32, 'PE', .false.),                                   &
    capability_item_t('G2', 'analysis.procedure', 'steps[]', 'procedure',                           &
                      PROFILE_KIND_TEXT, 0_int32, 'Q', .false.),                                    &
    capability_item_t('G3', 'material.kind', 'materials[]', 'kind',                                 &
                      PROFILE_KIND_TEXT, 0_int32, 'MECHANICAL', .false.),                           &
    capability_item_t('G3', 'material.model', 'materials[]', 'model',                               &
                      PROFILE_KIND_TEXT, 0_int32, 'ELASTIC_ISOTROPIC', .false.),                    &
    capability_item_t('G4', 'solver.linear', 'solver', 'linear',                                    &
                      PROFILE_KIND_TEXT, 0_int32, 'PROFILE', .false.),                              &
    capability_item_t('G4', 'solver.symmetric', 'solver', 'symmetric',                              &
                      PROFILE_KIND_LOGICAL, 0_int32, '', .true.),                                   &
    capability_item_t('G5', 'load.gravity_enabled', 'steps[].load.gravity', 'enabled',              &
                      PROFILE_KIND_INT, 1_int32, '', .false.),                                      &
    ! READ THIS BEFORE RAISING THE SECTION COUNT.
    ! This row is load-bearing beyond the gate. finalize derives one element set
    ! per section, and a draft with two sections whose elements ALL belong to the
    ! first would make the second set an allocated zero-length set -- an explicit
    ! empty where nothing was authored, which ADR-0002 forbids. No validation rule
    ! guards that case, on purpose: while this row reads 1 the case is
    ! unreachable, and a rule that nothing can fail is the defect this milestone
    ! exists to remove. The net today is the pipeline's INV-EMPTY-DERIVED
    ! assertion, which reports the situation as an INTERNAL fault -- the wrong
    ! class for what is really an input defect, and acceptable only because it
    ! cannot fire. So raising this above 1 REQUIRES adding that validation rule
    ! first, with a counter-example draft; otherwise the first two-section model a
    ! user writes is answered with an internal fault.
    capability_item_t('G6', 'model.section_count', 'sections', 'size',                              &
                      PROFILE_KIND_INT, 1_int32, '', .false.),                                      &
    capability_item_t('G6', 'analysis.step_count', 'steps', 'size',                                 &
                      PROFILE_KIND_INT, 1_int32, '', .false.),                                      &
    capability_item_t('G6', 'analysis.increments', 'steps[].controls', 'increments',                &
                      PROFILE_KIND_INT, 1_int32, '', .false.)]

  ! ==============================================================================================
  ! CAP_STAGE_ADAPT -- the legacy dialects the M4-01 adapter refuses at parse time.
  !
  ! One row per construct the parsers meet and will not read. `item` names the LEGACY deck symbol
  ! that carries it (deck side); `object_path`/`field` name what the value would have become
  ! (model side); `message` is the whole of the wording, so a parser passes only the run-time
  ! facts -- the observed value, the source location, the record index.
  !
  ! WHY THESE ARRIVE IN FIVE NAMED BLOCKS AND NOT AS MORE ROWS OF ONE CONSTRUCTOR
  ! A Fortran statement may carry at most 255 continuation lines (F2018 6.3.2.4), and these rows
  ! need about 290. This is a source-form limit, not a second table: the blocks are concatenated
  ! into the ONE named constant CAPABILITIES immediately below, every accessor reads only that,
  ! and the dialect self-test walks it. The split is along the parser that raises each group,
  ! which is the boundary a reader wants anyway.
  ! ==============================================================================================

  ! .inp and .man -- yl_adapter_fem90. The 9 legacy sites behind these have no callable
  ! counterpart (they are internal procedures of PROGRAM FEM90), so these rows guard the
  ! one hand-written parser with no oracle behind it (M4-01 plan, R-fem90-9).
  type(capability_item_t), parameter :: DIALECT_INP_MAN(*) = [                                                         &
    capability_item_t(rule_id='F1', condition='restart',                                                            &
                      item='inp.restart', object_path='control.run.restart',                                        &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='restart/=0 resumes a prior run (Fem.f90:277-309); this build only reads a fresh '//   &
                              'deck'),                                                                              &
    capability_item_t(rule_id='F1', condition='relis',                                                              &
                      item='inp.relis', object_path='control.run.relis',                                            &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='relis/=0 enables the reliability-analysis branch (STATIC_U_reli, Fem.f90:1921), '//   &
                              'not read by this module'),                                                           &
    capability_item_t(rule_id='F1', condition='sysrelis',                                                           &
                      item='inp.sysrelis', object_path='control.run.sysrelis',                                      &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='sysrelis/=0 enables the system-reliability branch (Fem.f90:5380,6230), not read '//   &
                              'by this module'),                                                                    &
    capability_item_t(rule_id='F1', condition='adina',                                                              &
                      item='inp.adina', object_path='control.run.adina',                                            &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='ADINA/=0 diverts to the ADINA export path and stops the run (Fem.f90:1900-1902)'),   &
    capability_item_t(rule_id='F1', condition='uopt_r',                                                             &
                      item='inp.Uopt_R', object_path='control.run.uopt_r',                                          &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='Uopt_R==1 reads an entire extra optimisation-coordinate deck (Fem.f90:120-142) '//   &
                              'that has no reader-inventory entry'),                                                &
    capability_item_t(rule_id='F1', condition='gamamax',                                                            &
                      item='inp.gamamax', object_path='control.run.gamamax',                                        &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='gamamax/=0 opens an equivalent-linearisation soil-constitutive file '//   &
                              '(Fem.f90:1724-1730)'),                                                               &
    capability_item_t(rule_id='F1', condition='runblks',                                                            &
                      item='inp.runblks', object_path='derived.counts.runblks',                                     &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='runblks must be 1 under static-q4/1 (single-stage static); this build cannot '//   &
                              'represent a multi-block analysis'),                                                  &
    capability_item_t(rule_id='F2', condition='multi-increment',                                                    &
                      item='man.nincs', object_path='steps0.controls.increments',                                   &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nincs must be 1: ProblemState.steps[0].controls has no per-increment array, so '//   &
                              'more than one increment cannot be represented without silently dropping data'),      &
    capability_item_t(rule_id='F2', condition='cwater',                                                             &
                      item='man.cwater', object_path='not_migrated.cwater',                                         &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='cwater/=0 enables the water-coupling coefficient branch (Fem.f90:3636-3641), not '//   &
                              'read by this module'),                                                               &
    capability_item_t(rule_id='F2', condition='qstatic',                                                            &
                      item='man.Qstatic', object_path='not_migrated.qstatic',                                       &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='Qstatic/=0 enables the quasi-static-force reads further down STATIC_U, not read '//   &
                              'by this module')]

  ! .glb -- yl_adapter_model. Fourteen of these are the flat `pinned guard` switches
  ! docs/m2/state-field-map.toml pins at 0; the rest are branches whose record shape
  ! changes with the value.
  type(capability_item_t), parameter :: DIALECT_GLB(*) = [                                                             &
    capability_item_t(rule_id='A-GLB', condition='rmesh-nonzero',                                                   &
                      item='glb.rmesh', object_path='mesh',                                                         &
                      field='rmesh', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='remeshing (rmesh/=0) is outside static-q4/1 and this parser does not know the '//   &
                              'format of the valv1/valv2 record it would gate (Global.f90:722)'),                   &
    capability_item_t(rule_id='A-GLB', condition='ntlink-nonzero',                                                  &
                      item='glb.ntlink', object_path='control.glb.ntlink',                                          &
                      field='ntlink', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                          &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.ntlink)'),                                &
    capability_item_t(rule_id='A-GLB', condition='mat_curve-nonzero',                                               &
                      item='glb.mat_curve', object_path='control.glb.mat_curve',                                    &
                      field='mat_curve', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                       &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.mat_curve)'),                             &
    capability_item_t(rule_id='A-GLB', condition='meshc-nonzero',                                                   &
                      item='glb.meshc', object_path='control.glb.meshc',                                            &
                      field='meshc', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.meshc)'),                                 &
    capability_item_t(rule_id='A-GLB', condition='level_set_problem-nonzero',                                       &
                      item='glb.level_set_problem', object_path='control.glb.level_set_problem',                    &
                      field='level_set_problem', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,               &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.level_set_problem)'),                     &
    capability_item_t(rule_id='A-GLB', condition='ljdp-nonzero',                                                    &
                      item='glb.ljdp', object_path='control.glb.ljdp',                                              &
                      field='ljdp', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                            &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.ljdp)'),                                  &
    capability_item_t(rule_id='A-GLB', condition='kstab-nonzero',                                                   &
                      item='glb.kstab', object_path='control.glb.kstab',                                            &
                      field='kstab', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='kstab is a pinned-zero unused switch on static-q4/1'),                               &
    capability_item_t(rule_id='A-GLB', condition='outplot-not-gidr',                                                &
                      item='glb.outplot', object_path='steps[0].output',                                            &
                      field='format', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                          &
                      message='only the GIDR text flavia writer is reproduced; GIDA (append) and any other '//   &
                              'value select a different .glb.flavia.res open discipline (Global.f90:736-737) '//   &
                              'this build does not implement'),                                                     &
    capability_item_t(rule_id='A-GLB', condition='multiple-blocks',                                                 &
                      item='glb.nblks', object_path='steps',                                                        &
                      field='nblks', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='this parser assembles exactly one steps[0] (adapter-contract.md SS2.1); a '//   &
                              'multi-block deck needs a step_parts_t per block, which does not exist yet'),         &
    capability_item_t(rule_id='A-GLB', condition='stab-matde-enabled',                                              &
                      item='glb.stab_matde', object_path='control.glb',                                             &
                      field='stab_matde', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                      &
                      message='stab_matde<=nblks would run stab_initialize (Fem.f90:2441), which this build '//   &
                              'does not reproduce; a disable sentinel (e.g. 99999) is required'),                   &
    capability_item_t(rule_id='A-GLB', condition='nlinks-nonzero',                                                  &
                      item='glb.nlinks', object_path='control.glb.nlinks',                                          &
                      field='nlinks', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                          &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.nlinks)'),                                &
    capability_item_t(rule_id='A-GLB', condition='block_stab-nonzero',                                              &
                      item='glb.block_stab', object_path='control.glb.block_stab',                                  &
                      field='block_stab', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                      &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.block_stab)'),                            &
    capability_item_t(rule_id='A-GLB', condition='nbackf-nonzero',                                                  &
                      item='glb.nbackf', object_path='control.glb.nbackf',                                          &
                      field='nbackf', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                          &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.nbackf)'),                                &
    capability_item_t(rule_id='A-GLB', condition='ebody-nonzero',                                                   &
                      item='glb.ebody', object_path='control.glb.ebody',                                            &
                      field='ebody', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.ebody)'),                                 &
    capability_item_t(rule_id='A-GLB', condition='ninit-nonzero',                                                   &
                      item='glb.ninit', object_path='control.glb.ninit',                                            &
                      field='ninit', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.ninit)'),                                 &
    capability_item_t(rule_id='A-GLB', condition='absorbing-not-fix',                                               &
                      item='glb.type_ABC', object_path='interactions.absorbing',                                    &
                      field='type', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                            &
                      message='MIF changes the .pre set_header shape, which this build does not parse'),            &
    capability_item_t(rule_id='A-GLB', condition='nlayer-nonzero',                                                  &
                      item='glb.nlayer', object_path='control.glb.nlayer',                                          &
                      field='nlayer', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                          &
                      message='nlayer==2 would also read three more scalars at Global.f90:810, a branch this '//   &
                              'parser does not implement; static-q4/1 has no layered element'),                     &
    capability_item_t(rule_id='A-GLB', condition='state_change-nonzero',                                            &
                      item='glb.state_change', object_path='control.glb.state_change',                              &
                      field='state_change', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                    &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.state_change)'),                          &
    capability_item_t(rule_id='A-GLB', condition='Bparameter-nonzero',                                              &
                      item='glb.Bparameter', object_path='control.glb.bparameter',                                  &
                      field='Bparameter', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                      &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.bparameter)'),                            &
    capability_item_t(rule_id='A-GLB', condition='nonlinear-type-not-5',                                            &
                      item='glb.type_nl', object_path='steps[0].controls',                                          &
                      field='nonlinear_type', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                  &
                      message='only the ALGORT fixed-iteration static path (type_nl=5) is reproduced'),             &
    capability_item_t(rule_id='A-GLB', condition='mdofn-mismatch',                                                  &
                      item='glb.mdofn', object_path='derived.counts',                                               &
                      field='mdofn', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='static-q4/1 is a single displacement field: total dofs must equal mesh.dimension'),  &
    capability_item_t(rule_id='A-GLB', condition='crack-beam-nonzero',                                              &
                      item='glb.nlocalbeam', object_path='control.glb',                                             &
                      field='nlocalbeam/ndimnrt', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,              &
                      message='concrete crack / beam local-axes elements are outside static-q4/1 isotropic '//   &
                              'linear-elastic'),                                                                    &
    capability_item_t(rule_id='A-GLB', condition='ntrans-nonzero',                                                  &
                      item='glb.ntrans', object_path='control.glb.ntrans',                                          &
                      field='ntrans', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                          &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.ntrans)'),                                &
    capability_item_t(rule_id='A-GLB', condition='uinitial-nonzero',                                                &
                      item='glb.uinitial', object_path='control.glb.uinitial',                                      &
                      field='uinitial', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                        &
                      message='pinned guard: value 0 keeps control flow on static_2d path '//   &
                              '(docs/m2/state-field-map.toml, control.glb.uinitial)')]

  ! .cor and .ele -- yl_adapter_mesh. The only two dialect rows whose whitelisted value
  ! is not fixed here but read from a CAP_STAGE_GATE row above (analysis.dimension,
  ! element.kind_code), so the parser and the gate cannot disagree about it.
  type(capability_item_t), parameter :: DIALECT_COR_ELE(*) = [                                                         &
    capability_item_t(rule_id='A-COR', condition='dimension',                                                       &
                      item='glb.ndimn', object_path='mesh',                                                         &
                      field='dimension', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                       &
                      message='only the capability table''s analysis.dimension is whitelisted; a different ndimn '//   &
                              'would build a draft the capability gate rejects later anyway, so this parser '//   &
                              'stops before spending the read'),                                                    &
    capability_item_t(rule_id='A-ELE', condition='element-kind',                                                    &
                      item='glb.group_index', object_path='sections[]',                                             &
                      field='element_kind', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                    &
                      message='only the capability table''s element.kind_code (Q4) is whitelisted; this parser '//   &
                              'only knows how to shape a Q4 connectivity record')]

  ! .mat and .sol -- yl_adapter_material. A-MAT/contact-material and
  ! A-MAT/nonlinear-normal-stiffness share (rule_id, object_path, field) and differ only
  ! in `condition`: the pair the module header names as the reason the key is composed.
  type(capability_item_t), parameter :: DIALECT_MAT_SOL(*) = [                                                         &
    capability_item_t(rule_id='A-MAT', condition='curve-count',                                                     &
                      item='mat.nscurve', object_path='materials',                                                  &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='property curves (nscurve/=0) read npoints/type_curve/strain_curve/stress_curve '//   &
                              'records this parser cannot shape (Material.f90:250-257)'),                           &
    capability_item_t(rule_id='A-MAT', condition='property',                                                        &
                      item='mat.property', object_path='materials',                                                 &
                      field='kind', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                            &
                      message='property_select (Material.f90:294) has a branch per property; only MECHANICAL is '//   &
                              'whitelisted'),                                                                       &
    capability_item_t(rule_id='A-MAT', condition='phase-count',                                                     &
                      item='mat.nphase', object_path='materials',                                                   &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='the phase loop (Material.f90:300) reads one phase record per nphase; only a '//   &
                              'single SOLID phase is whitelisted'),                                                 &
    capability_item_t(rule_id='A-MAT', condition='phase',                                                           &
                      item='mat.phase', object_path='materials',                                                    &
                      field='phase', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='phase_select (Material.f90:305) also has a FLUID branch reading different '//   &
                              'fields; only SOLID is whitelisted'),                                                 &
    capability_item_t(rule_id='A-MAT', condition='creep',                                                           &
                      item='mat.icreep', object_path='materials',                                                   &
                      field='creep_model', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                     &
                      message='icreep>0 reads a creep-model record shaped by icreep itself '//   &
                              '(Material.f90:357-398); not whitelisted'),                                           &
    capability_item_t(rule_id='A-MAT', condition='wetting',                                                         &
                      item='mat.kind_wt', object_path='materials',                                                  &
                      field='wetting_kind', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                    &
                      message='kind_wt>0 reads a wetting-deformation record (Material.f90:402-418); not '//   &
                              'whitelisted'),                                                                       &
    capability_item_t(rule_id='A-MAT', condition='liquefaction',                                                    &
                      item='mat.jliqu', object_path='materials',                                                    &
                      field='liquefaction', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                    &
                      message='jliqu/=0 reads anti-liquefaction cyclic records (Material.f90:330-345); not '//   &
                              'whitelisted'),                                                                       &
    capability_item_t(rule_id='A-MAT', condition='contact-material',                                                &
                      item='mat.name', object_path='materials',                                                     &
                      field='name', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                            &
                      message='name==CONTACT reads a gap/friction record (Material.f90:419-423); not '//   &
                              'whitelisted'),                                                                       &
    capability_item_t(rule_id='A-MAT', condition='nonlinear-normal-stiffness',                                      &
                      item='mat.name', object_path='materials',                                                     &
                      field='name', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                            &
                      message='name==NOLINORMK reads a piecewise-normal-stiffness record '//   &
                              '(Material.f90:450-456); not whitelisted'),                                           &
    capability_item_t(rule_id='A-MAT', condition='model',                                                           &
                      item='mat.material', object_path='materials',                                                 &
                      field='model', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                           &
                      message='material_select (Material.f90:457) has a branch per constitutive model, each '//   &
                              'with its own extra records; only ELASTIC_ISOTROPIC is whitelisted (capability '//   &
                              'row G3 material.model)'),                                                            &
    capability_item_t(rule_id='A-SOL', condition='pivot-file',                                                      &
                      item='sol.iafile', object_path='solver',                                                      &
                      field='profile.pivot_file', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,              &
                      message='iafile/=0 opens a separate unformatted pivot file (Solver.f90:6833, the '//   &
                              'PARDISO/pivot-capture variant); not whitelisted')]

  ! .loa and .pre -- yl_adapter_load. Every load kind except gravity, and every prescribed
  ! displacement record shape except the 8-field FIX header.
  type(capability_item_t), parameter :: DIALECT_LOA_PRE(*) = [                                                         &
    capability_item_t(rule_id='A1', condition='stochastic-curve-modifier-unsupported',                              &
                      item='loa.nstoch_curve', object_path='amplitudes',                                            &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nstoch_curve /= 0: the stochastic curve parameter record (Load.f90:171) is not '//   &
                              'reproduced'),                                                                        &
    capability_item_t(rule_id='A2', condition='curve-type-unsupported',                                             &
                      item='loa.type_curve', object_path='amplitudes',                                              &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='only ''LINEAR'' (Load.f90:218-222) is in the static-q4/1 whitelist; every other '//   &
                              'named case (Load.f90:175-217) reads a different record shape that is not '//   &
                              'reproduced'),                                                                        &
    capability_item_t(rule_id='A3', condition='point-load-unsupported',                                             &
                      item='loa.nplgroup', object_path='steps[0].load',                                             &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nplgroup /= 0: point loads (Load.f90:246-333) are outside the static-q4/1 '//   &
                              'whitelist'),                                                                         &
    capability_item_t(rule_id='A4', condition='edge-definition-unsupported',                                        &
                      item='loa.nedge', object_path='steps[0].load',                                                &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nedge /= 0: edge definitions (Load.f90:369-465) feed only pressure loads, which '//   &
                              'are outside the static-q4/1 whitelist'),                                             &
    capability_item_t(rule_id='A5', condition='pressure-load-unsupported',                                          &
                      item='loa.edge_load_group', object_path='steps[0].load',                                      &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='edge_load_group /= 0: edge / water-pressure loads (Load.f90:757-908) are outside '//   &
                              'the static-q4/1 whitelist'),                                                         &
    capability_item_t(rule_id='A6', condition='beam-load-unsupported',                                              &
                      item='loa.nbeamload', object_path='steps[0].load',                                            &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nbeamload /= 0: beam loads (Load.f90:936-1004) are outside the static-q4/1 '//   &
                              'whitelist'),                                                                         &
    capability_item_t(rule_id='A7', condition='plate-load-unsupported',                                             &
                      item='loa.nplateload', object_path='steps[0].load',                                           &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nplateload /= 0: plate/water-pressure loads (Load.f90:1017-1080) are outside the '//   &
                              'static-q4/1 whitelist'),                                                             &
    capability_item_t(rule_id='A8', condition='restart-linked-boundary-unsupported',                                &
                      item='pre.nbackdT', object_path='steps[0].boundary',                                          &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nbackdT == 2: the Prescrib.f90:184-201 record shape is a restart-linked dialect '//   &
                              'outside the static-q4/1 whitelist and is not reproduced'),                           &
    capability_item_t(rule_id='A9', condition='mif-boundary-unsupported',                                           &
                      item='pre.type_abc', object_path='steps[0].boundary',                                         &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='type_abc == ''MIF'': only fixed/prescribed displacement is in the static-q4/1 '//   &
                              'whitelist; the 9-field MIF/VIE record shape (Prescrib.f90:218) is not reproduced'),  &
    capability_item_t(rule_id='A10', condition='extrapolation-record-unsupported',                                  &
                      item='pre.nextr', object_path='steps[0].boundary',                                            &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='nextr /= 0: the per-node extrapolation list (Prescrib.f90:261-266) is not '//   &
                              'reproduced'),                                                                        &
    capability_item_t(rule_id='A11', condition='mif-coordinate-record-unsupported',                                 &
                      item='pre.ifixvar', object_path='steps[0].boundary',                                          &
                      field='', stage=CAP_STAGE_ADAPT, value_kind=PROFILE_KIND_NONE,                                &
                      message='ntrans > 0 and ifixvar <= ndimn: the MIF free-face coordinate record '//   &
                              '(Prescrib.f90:248-249) is not reproduced')]

  ! THE table. One named constant, assembled from the blocks above in partition order: every
  ! CAP_STAGE_GATE row, then every CAP_STAGE_ADAPT row. N_GATE/N_ADAPT below are counted from
  ! the `stage` column of THIS array, so the order here and the counts cannot drift apart -- but
  ! the CONTIGUITY the accessors rely on is a property of this line, and only the self-test's
  ! walk over capability_table_row proves it.
  type(capability_item_t), parameter :: CAPABILITIES(*) = [GATE_ROWS, DIALECT_INP_MAN,           &
                                                           DIALECT_GLB, DIALECT_COR_ELE,          &
                                                           DIALECT_MAT_SOL, DIALECT_LOA_PRE]


  ! --- partition bounds, DERIVED from the table -------------------------------
  ! Counted from the `stage` column rather than written down, for the reason
  ! yl_runtime_rules gives for not writing down its own row count: a number spelled
  ! twice is a number that can disagree with itself. These are the ONLY place the
  ! two partitions are separated, and the gate-first contiguity they assume is
  ! asserted by yl_adapter_dialect_test rather than assumed silently here.

  integer, parameter :: N_GATE = count(CAPABILITIES%stage == CAP_STAGE_GATE)
  integer, parameter :: N_ADAPT = count(CAPABILITIES%stage == CAP_STAGE_ADAPT)

  ! The whole table, both partitions. Public so the self-test can walk every row
  ! and prove the partition really is contiguous -- no accessor below can show it
  ! that, because each one already assumes the answer.
  integer, parameter, public :: CAPABILITY_ROW_TOTAL = size(CAPABILITIES)

contains

  ! --- default profile accessors ----------------------------------------------

  pure integer function profile_default_count() result(n)
    n = size(DEFAULTS)
  end function profile_default_count

  ! Copy out default row `i`. `found` is mandatory, as in opt_get and
  ! problem_errors_t%get: an out-of-range index is answered, never assumed away.
  pure subroutine profile_default_row(i, row, found)
    integer, intent(in) :: i
    type(profile_default_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > size(DEFAULTS)) return
    row = DEFAULTS(i)
    found = .true.
  end subroutine profile_default_row

  ! Look up an integer-valued default by CAE key. `row_index` is returned so that
  ! finalize can record WHICH profile row supplied the value, together with its
  ! map_id and rule_id, in the manifest. A key that exists but holds a different
  ! payload kind is reported as not found rather than coerced: a type confusion in
  ! the table must surface as a missing default, not as a plausible wrong number.
  pure subroutine profile_lookup_int(key, value, found, row_index)
    character(len=*), intent(in) :: key
    integer(int32), intent(out) :: value
    logical, intent(out) :: found
    integer, intent(out) :: row_index
    integer :: i
    value = 0_int32
    found = .false.
    row_index = 0
    do i = 1, size(DEFAULTS)
      if (trim(DEFAULTS(i)%key) == key) then
        if (DEFAULTS(i)%value_kind == PROFILE_KIND_INT) then
          value = DEFAULTS(i)%int_value
          found = .true.
          row_index = i
        end if
        return
      end if
    end do
  end subroutine profile_lookup_int

  ! Text counterpart of profile_lookup_int. No M3-02 row uses it; it exists so the
  ! M3-03 rows that default a text value need no new mechanism.
  pure subroutine profile_lookup_text(key, value, found, row_index)
    character(len=*), intent(in) :: key
    character(len=:), allocatable, intent(out) :: value
    logical, intent(out) :: found
    integer, intent(out) :: row_index
    integer :: i
    value = ''
    found = .false.
    row_index = 0
    do i = 1, size(DEFAULTS)
      if (trim(DEFAULTS(i)%key) == key) then
        if (DEFAULTS(i)%value_kind == PROFILE_KIND_TEXT) then
          value = trim(DEFAULTS(i)%text_value)
          found = .true.
          row_index = i
        end if
        return
      end if
    end do
  end subroutine profile_lookup_text

  ! --- capability accessors ---------------------------------------------------

  ! The GATE partition only. This deliberately answers N_GATE and not the table's
  ! size: yl_problem_pipeline's capability gate, its coverage walk and its
  ! uniqueness check all iterate 1..capability_count(), and a dialect row is not
  ! theirs to evaluate -- it fires in the adapter, long before a draft exists, so a
  ! coverage walk over it would report every dialect row as an un-falsifiable gate
  ! row. Dialect rows are reached through dialect_count/dialect_row instead.
  pure integer function capability_count() result(n)
    n = N_GATE
  end function capability_count

  pure subroutine capability_row(i, row, found)
    integer, intent(in) :: i
    type(capability_item_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > N_GATE) return
    row = CAPABILITIES(i)
    found = .true.
  end subroutine capability_row

  ! Any row of the WHOLE table, both partitions, 1 .. CAPABILITY_ROW_TOTAL.
  !
  ! The only accessor that crosses the partition boundary, and it exists for one
  ! caller: the self-test that proves the boundary is where every other accessor
  ! assumes it is. Nothing in the gate or in a parser may use it -- both know which
  ! partition they belong to, and reading the other one is the mistake this
  ! separation exists to prevent.
  pure subroutine capability_table_row(i, row, found)
    integer, intent(in) :: i
    type(capability_item_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (i < 1) return
    if (i > size(CAPABILITIES)) return
    row = CAPABILITIES(i)
    found = .true.
  end subroutine capability_table_row

  ! Index of the capability row for a CAE item name, 0 when there is none. The
  ! gate uses this to fetch the rule id and the expected value for the item it is
  ! about to check, so the expected value is never spelled twice.
  pure integer function capability_find(item) result(row_index)
    character(len=*), intent(in) :: item
    integer :: i
    row_index = 0
    do i = 1, N_GATE
      if (trim(CAPABILITIES(i)%item) == item) then
        row_index = i
        return
      end if
    end do
  end function capability_find

  ! Expected integer for a capability item. As with profile_lookup_int, a payload
  ! kind mismatch reports not-found rather than returning a coerced value.
  pure subroutine capability_expect_int(item, value, found)
    character(len=*), intent(in) :: item
    integer(int32), intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = 0_int32
    found = .false.
    i = capability_find(item)
    if (i == 0) return
    if (CAPABILITIES(i)%value_kind /= PROFILE_KIND_INT) return
    value = CAPABILITIES(i)%int_value
    found = .true.
  end subroutine capability_expect_int

  pure subroutine capability_expect_text(item, value, found)
    character(len=*), intent(in) :: item
    character(len=:), allocatable, intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = ''
    found = .false.
    i = capability_find(item)
    if (i == 0) return
    if (CAPABILITIES(i)%value_kind /= PROFILE_KIND_TEXT) return
    value = trim(CAPABILITIES(i)%text_value)
    found = .true.
  end subroutine capability_expect_text

  pure subroutine capability_expect_logical(item, value, found)
    character(len=*), intent(in) :: item
    logical, intent(out) :: value
    logical, intent(out) :: found
    integer :: i
    value = .false.
    found = .false.
    i = capability_find(item)
    if (i == 0) return
    if (CAPABILITIES(i)%value_kind /= PROFILE_KIND_LOGICAL) return
    value = CAPABILITIES(i)%logical_value
    found = .true.
  end subroutine capability_expect_logical

  ! One capability row as a single stable line:
  !
  !   <tag>|<rule_id>|<item>|<object_path>|<field>|<kind>|<value>
  !
  ! kind is one of i32/text/bool and value is the decimal integer, the canonical
  ! text, or true/false. This is the export path: the self-test prints every row
  ! through this function and the Python cross-check parses those lines, so the
  ! capability table exists exactly once in the repository. An out-of-range index
  ! renders as the empty string; export is a reporting path and must not abort.
  !
  ! GATE partition only, and the line shape is unchanged from M3-02 on purpose: an
  ! existing cross-check must not start seeing new rows or a new field count
  ! because M4-01 extended a partition it does not read. Dialect rows have their
  ! own renderer, dialect_row_text, with its own shape.
  pure function capability_row_text(i) result(text)
    integer, intent(in) :: i
    character(len=:), allocatable :: text
    character(len=12) :: buffer

    if (i < 1 .or. i > N_GATE) then
      text = ''
      return
    end if

    text = CAPABILITY_TAG//'|'//trim(CAPABILITIES(i)%rule_id)//'|'//trim(CAPABILITIES(i)%item)//   &
           '|'//trim(CAPABILITIES(i)%object_path)//'|'//trim(CAPABILITIES(i)%field)//'|'

    select case (CAPABILITIES(i)%value_kind)
    case (PROFILE_KIND_INT)
      write (buffer, '(i0)') CAPABILITIES(i)%int_value
      text = text//'i32|'//trim(buffer)
    case (PROFILE_KIND_TEXT)
      text = text//'text|'//trim(CAPABILITIES(i)%text_value)
    case (PROFILE_KIND_LOGICAL)
      if (CAPABILITIES(i)%logical_value) then
        text = text//'bool|true'
      else
        text = text//'bool|false'
      end if
    case default
      text = text//'unknown|'
    end select
  end function capability_row_text

  ! --- dialect accessors ------------------------------------------------------
  ! The CAP_STAGE_ADAPT partition. Index `j` runs 1 .. dialect_count() and is
  ! translated to the table index once, here, so no caller ever holds a raw
  ! CAPABILITIES index into the second partition.

  pure integer function dialect_count() result(n)
    n = N_ADAPT
  end function dialect_count

  pure subroutine dialect_row(j, row, found)
    integer, intent(in) :: j
    type(capability_item_t), intent(out) :: row
    logical, intent(out) :: found
    found = .false.
    if (j < 1) return
    if (j > N_ADAPT) return
    row = CAPABILITIES(N_GATE + j)
    found = .true.
  end subroutine dialect_row

  ! Index of the dialect row with this (rule_id, condition), 0 when the table has
  ! none. Two halves in, never a pre-joined key: a caller that already had the
  ! joined string would have had to build it, and building it at the raise site is
  ! precisely the duplication dialect_key exists to remove.
  pure integer function dialect_find(rule_id, condition) result(j)
    character(len=*), intent(in) :: rule_id, condition
    integer :: k
    j = 0
    do k = 1, N_ADAPT
      if (trim(CAPABILITIES(N_GATE + k)%rule_id) /= rule_id) cycle
      if (trim(CAPABILITIES(N_GATE + k)%condition) /= condition) cycle
      j = k
      return
    end do
  end function dialect_find

  ! The stable id of dialect row `j`: `<rule_id>/<condition>`, e.g.
  ! 'A-GLB/rmesh-nonzero'. This is the single string a finding carries as its
  ! rule_id and a coverage walk matches on. Empty for an out-of-range index.
  pure function dialect_key(j) result(key)
    integer, intent(in) :: j
    character(len=:), allocatable :: key
    key = ''
    if (j < 1 .or. j > N_ADAPT) return
    key = trim(CAPABILITIES(N_GATE + j)%rule_id)//'/'//trim(CAPABILITIES(N_GATE + j)%condition)
  end function dialect_key

  ! One dialect row as a single stable line:
  !
  !   <verdict>|<tag>|<key>|<item>|<object_path>|<field>|<message>
  !
  ! The counterpart of capability_row_text, and separate from it because the two
  ! partitions do not carry the same columns: a dialect row has no payload and a
  ! gate row has no message, so one renderer for both would have to emit empty
  ! fields that mean two different things. An out-of-range index renders empty.
  pure function dialect_row_text(j) result(text)
    integer, intent(in) :: j
    character(len=:), allocatable :: text
    text = ''
    if (j < 1 .or. j > N_ADAPT) return
    text = DIALECT_VERDICT//'|'//CAPABILITY_TAG//'|'//dialect_key(j)//                             &
           '|'//trim(CAPABILITIES(N_GATE + j)%item)//                                              &
           '|'//trim(CAPABILITIES(N_GATE + j)%object_path)//                                       &
           '|'//trim(CAPABILITIES(N_GATE + j)%field)//                                             &
           '|'//trim(CAPABILITIES(N_GATE + j)%message)
  end function dialect_row_text

end module yl_problem_profile
