! yl_problem_pipeline_selftest -- the acceptance instrument for the M3-02 pipeline.
!
! Scope (.ccg/tasks/m3-02-normalize-validate-finalize/plan.md deliverable 6, test
! matrix rows P-ok / P-neg / P-I04 / P-T01 / P-stage)
!   This program is the falsifiability gate for yl_problem_pipeline. The M3-02
!   acceptance criterion is not "the pipeline accepts the good deck": it is that
!   EVERY implemented rule has a counter-example draft that actually makes that
!   rule fire, and that the finding names the object and the field. This
!   repository has already shipped three gates that could not fail; a rule with no
!   reachable failing draft is a defect, not a pass.
!
! Method
!   good_draft() builds, through yl_problem_builder, one draft that is
!   structurally equivalent to cases/golden/static_2d/cooks_membrane: the same
!   supported combination (2-D, Q4 / kind 5 / class CO / fields U / formulation
!   PE, ELASTIC_ISOTROPIC MECHANICAL, PROFILE symmetric, procedure Q, load mode
!   LOAD, gravity enabled, one section, one material, one step, one increment,
!   one LINEAR amplitude of two points, two prescribed sets) with a four-node
!   single-element mesh instead of the deck's 289 nodes and 256 elements. The
!   mesh size is the only thing scaled down: every field the rule set reads is
!   present with the deck's value. Each negative case then applies ONE mutation
!   to a fresh copy of that draft, so what makes the rule fire is exactly the one
!   changed value and nothing else.
!
!   expect_rule() is deliberately stricter than "the run failed". It asserts the
!   run failed AND that the first finding carrying the expected rule id has the
!   expected code, object path and field. A pipeline that rejected every draft
!   for the wrong reason would fail this program.
!
! Output
!   One `ok` / `BAD` line per check and a final `PASS: n/n` or `FAIL: n/m`,
!   following src/problem/yl_problem_selftest.f90. Exits 1 on any failure so a
!   build script can gate on it. Build and run under BOTH profiles: the plain
!   -warn all -stand f18 flags and the strict profile of tools/build.sh
!   (-O0 -g -traceback -check bounds,pointers -init=snan,arrays -fpe0).
program yl_problem_pipeline_selftest

  use iso_fortran_env, only: int32, int64, real64, output_unit
  use yl_problem_optional, only: opt_int, opt_real, opt_text, opt_logical, &
                                 opt_set, opt_get, opt_is_set, opt_clear, &
                                 opt_value_or, opt_equal
  use yl_problem_types, only: problem_state_t, case_t, node_t, element_t, elset_t, &
                              nset_t, material_t, section_t, amplitude_t, &
                              amplitude_point_t, interactions_t, solver_t, step_t, &
                              controls_t, load_t, output_t, output_field_t, &
                              boundary_t, activation_t
  use yl_problem_errors, only: problem_error_t, problem_errors_t, source_location_t, &
                               PE_MISSING_FIELD, PE_DANGLING_REF, PE_DUPLICATE_REF, &
                               PE_EMPTY_COLLECTION, PE_COUNT_MISMATCH, &
                               PE_INVALID_INPUT, PE_UNSUPPORTED, &
                               PE_STAGE_NORMALIZE, PE_STAGE_VALIDATE, &
                               PE_STAGE_CAPABILITY, PE_STAGE_FINALIZE
  use yl_problem_manifest, only: manifest_t, manifest_entry_t, manifest_count, &
                                 manifest_get, manifest_find, manifest_is_valid, &
                                 MANIFEST_KIND_DERIVED, MANIFEST_KIND_DEFAULT, &
                                 MANIFEST_KIND_CHECK, MANIFEST_VERDICT_MATCH
  use yl_problem_profile, only: PROFILE_ID, PROFILE_VERSION, PROFILE_TAG, &
                                capability_item_t, capability_row
  use yl_problem_builder
  use yl_problem_pipeline

  implicit none

  integer :: n_check = 0
  integer :: n_fail = 0

  ! Which capability ROWS a gate counter-example actually triggered. The table
  ! has fifteen rows but only six rule ids, so a row can hide behind a rule id
  ! another row already makes look covered: that is not a hypothesis, it is what
  ! an audit of this matrix found, six rows with no counter-example and none of
  ! them visible as a gap. Auditing once fixes the six; walking the table at
  ! runtime is what stops the seventh. A row added later under an existing rule
  ! id fails this suite instead of inheriting that id's coverage.
  logical, allocatable :: cap_hit(:)

  write (output_unit, '(a)') 'yl_problem_pipeline_selftest: M3-02 rule falsifiability matrix'

  allocate (cap_hit(capability_row_count()))
  cap_hit = .false.

  call group_positive()
  call group_normalize()
  call group_validate()
  call group_conditions()
  call group_gate()
  call group_i04()
  call group_transaction()
  call group_stage_barrier()
  call group_accumulation()

  call summary()

contains

  ! ==========================================================================
  ! 1. positive: the cooks-equivalent draft runs the whole pipeline
  ! ==========================================================================

  subroutine group_positive()
    type(problem_state_t), allocatable :: d, p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok
    integer :: i

    write (output_unit, '(a)') '-- 1. positive (cooks-equivalent draft)'
    call good_draft(d)
    call run_counts(d, good_counts(), p, man, errs, ok)

    call check('P-ok  prepare_problem succeeds', ok)
    call check('P-ok  no findings accumulated', errs%count() == 0)
    if (.not. ok) then
      do i = 1, errs%count()
        write (output_unit, '(a)') '        finding: '//errs%render(i)
      end do
    end if
    call check('P-ok  a problem state was produced', allocated(p))
    call check('P-ok  the manifest is valid', manifest_is_valid(man))
    call check('P-ok  the manifest is not empty', n_manifest(man) > 0)

    ! The six ProblemState index_map rows finalize owns at M3-02, under the
    ! object and field spellings the pipeline actually writes.
    call check_derived(man, 'mesh.elements', 'elset')      ! mesh.elements.group
    call check_derived(man, 'mesh.elements', 'kind')       ! mesh.elements.kind
    call check_derived(man, 'mesh.elsets[1]', 'elements')  ! mesh.sets.elset
    call check_derived(man, 'mesh.nsets[1]', 'nodes')      ! mesh.sets.nset
    call check_derived(man, 'sections[1]', 'material_header')
    call check_derived(man, 'sections[1]', 'material')
    ! The one M3-02 profile default, with its version stamp: derived.counts.nstre.
    call check_default(man, 'sections[1]', 'stress_components')
    ! The eight checkable declared counts, all agreeing.
    call check_check_count(man, 8)

    ! sections[].material_header has TWO provenances and the row must appear,
    ! exactly once, under either. The good draft leaves the element records
    ! carrying no material, which is what both golden decks do, so the branch
    ! above took the authored header. This variant states the material on the
    ! element instead, so the header is derived from it. The row went missing on
    ! the authored branch once; asserting only the branch that happens to be
    ! wired today is how that recurs.
    call good_draft(d)
    call opt_set(d%mesh%elements(1)%material, 1_int32)
    call opt_clear(d%sections(1)%material_header)
    call run_counts(d, good_counts(), p, man, errs, ok)
    call check('P-ok  a derived material header is accepted', ok)
    if (.not. ok) then
      do i = 1, errs%count()
        write (output_unit, '(a)') '        finding: '//errs%render(i)
      end do
    end if
    call check_derived(man, 'sections[1]', 'material_header')
  end subroutine group_positive

  ! Present, derived, and present EXACTLY ONCE. The last part is what catches a
  ! finalize that emits a row from two branches, or one that emits a row per
  ! element instead of one per collection: a total-count assertion would let both
  ! through as long as the total happened to match.
  subroutine check_derived(man, object, field)
    type(manifest_t), allocatable, intent(in) :: man
    character(len=*), intent(in) :: object, field
    integer :: k
    type(manifest_entry_t) :: e
    logical :: found
    k = manifest_find(man, object, field)
    call check('P-ok  manifest has derived '//object//'.'//field, k > 0)
    if (k <= 0) return
    call manifest_get(man, k, e, found)
    call check('P-ok  '//object//'.'//field//' is a derived entry', &
               found .and. txt(e%kind) == MANIFEST_KIND_DERIVED)
    call check('P-ok  '//object//'.'//field//' appears exactly once', &
               n_entries_for(man, object, field) == 1)
  end subroutine check_derived

  ! How many manifest entries target this exact (object, field) pair.
  integer function n_entries_for(man, object, field) result(n)
    type(manifest_t), allocatable, intent(in) :: man
    character(len=*), intent(in) :: object, field
    type(manifest_entry_t) :: e
    logical :: found
    integer :: k
    n = 0
    if (.not. allocated(man)) return
    do k = 1, manifest_count(man)
      call manifest_get(man, k, e, found)
      if (.not. found) cycle
      if (txt(e%object) == object .and. txt(e%field) == field) n = n + 1
    end do
  end function n_entries_for

  ! An opt_text that is set and carries exactly this value.
  logical function text_is(x, want) result(res)
    type(opt_text), intent(in) :: x
    character(len=*), intent(in) :: want
    res = .false.
    if (.not. opt_is_set(x)) return
    res = (opt_value_or(x, '') == want)
  end function text_is

  subroutine check_default(man, object, field)
    type(manifest_t), allocatable, intent(in) :: man
    character(len=*), intent(in) :: object, field
    integer :: k
    type(manifest_entry_t) :: e
    logical :: found
    k = manifest_find(man, object, field)
    call check('P-ok  manifest has default '//object//'.'//field, k > 0)
    if (k <= 0) return
    call manifest_get(man, k, e, found)
    call check('P-ok  '//field//' is a default entry', &
               found .and. txt(e%kind) == MANIFEST_KIND_DEFAULT)
    call check('P-ok  '//field//' carries the profile id', &
               txt(e%profile) == PROFILE_ID)
    call check('P-ok  '//field//' carries the profile version', &
               txt(e%profile_version) == PROFILE_VERSION)
    call check('P-ok  '//object//'.'//field//' appears exactly once', &
               n_entries_for(man, object, field) == 1)
  end subroutine check_default

  subroutine check_check_count(man, want)
    type(manifest_t), allocatable, intent(in) :: man
    integer, intent(in) :: want
    integer :: k, nchk, nmatch
    type(manifest_entry_t) :: e
    logical :: found
    nchk = 0
    nmatch = 0
    do k = 1, manifest_count(man)
      call manifest_get(man, k, e, found)
      if (.not. found) cycle
      if (txt(e%kind) /= MANIFEST_KIND_CHECK) cycle
      nchk = nchk + 1
      if (txt(e%verdict) == MANIFEST_VERDICT_MATCH) nmatch = nmatch + 1
    end do
    call check('P-ok  manifest has the 8 declared-count checks', nchk == want)
    call check('P-ok  every declared-count check verdict is match', nmatch == nchk)
  end subroutine check_check_count

  ! ==========================================================================
  ! 2a. normalize counter-examples: N4, N5, N6
  ! ==========================================================================

  subroutine group_normalize()
    type(problem_state_t), allocatable :: d, p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok
    type(elset_t), allocatable :: es(:)
    type(section_t), allocatable :: sc(:)

    write (output_unit, '(a)') '-- 2a. normalize counter-examples'

    ! N4 -- two elsets for one section.
    call good_draft(d)
    allocate (es(2))
    es(1) = d%mesh%elsets(1)
    allocate (es(2)%elements(0))
    call move_alloc(es, d%mesh%elsets)
    call expect_rule('N4  elset/section arity', 'N4', PE_INVALID_INPUT, &
                     'mesh.elsets', '', d)

    ! N5 -- a collection the author left unset must stay unset: normalize may
    ! never allocate it to length zero. prepare_problem takes the draft
    ! intent(in), so the caller's copy is safe by construction; what is
    ! observable, and what N5 is really about, is that the unset collection is
    ! still reported AS UNSET further down the pipeline instead of being read as
    ! an explicitly empty one. An unset elsets reaches validate and is V8; an
    ! elsets of length 0 never gets that far, because normalize's own arity rule
    ! sees 0 sets for 1 section. Two states, two verdicts, from two stages.
    call good_draft(d)
    deallocate (d%mesh%elsets)
    call run(d, p, man, errs, ok)
    call check('N5  an unset collection fails the run', .not. ok)
    call check('N5  the caller draft was not allocated by the pipeline', &
               .not. allocated(d%mesh%elsets))
    call check('N5  the unset collection is reported as unset, not as empty', &
               has_rule(errs, 'V8') .and. first_actual(errs, 'V8') == 'unset')
    call check('N5  normalize did not turn unset into explicitly empty', &
               .not. has_rule(errs, 'N4'))
    ! The other half of the prohibition, on the passing side: the good draft has
    ! no empty collection, so a zero-length collection in the PUBLISHED problem
    ! could only have been invented by a stage. This is what would fail if
    ! normalize ever grew an allocate for an unset collection.
    call good_draft(d)
    call run_counts(d, good_counts(), p, man, errs, ok)
    call check('N5  a passing run publishes no invented empty collection', &
               ok .and. zero_length_in(p) == 0)

    ! N6 -- one element claimed by two element sets. element%elset is left unset
    ! so the back-reference fill runs and finds the double membership.
    call good_draft(d)
    call opt_clear(d%mesh%elements(1)%elset)
    allocate (sc(2))
    sc(1) = d%sections(1)
    sc(2) = d%sections(1)
    call opt_set(sc(2)%name, 'g2')
    call move_alloc(sc, d%sections)
    allocate (es(2))
    allocate (es(1)%elements(1))
    es(1)%elements = [1_int32]
    allocate (es(2)%elements(1))
    es(2)%elements = [1_int32]
    call move_alloc(es, d%mesh%elsets)
    call regrow_per_section(d, 2)
    call expect_rule('N6  element in two element sets', 'N6', PE_INVALID_INPUT, &
                     'mesh.elements', 'elset', d)

    ! N1 -- text canonicalisation, asserted DIRECTLY on the finalized state.
    ! Passing the capability gate is only indirect evidence, because the gate
    ! reads six of these fields and would have rejected an uncanonicalised value
    ! on its own. The four fields below the gate never reads are the ones that
    ! catch a future change which stops canonicalising a field nothing else
    ! looks at: the output format, the load mode and the section's special code
    ! are enum-valued and must come back upper case, while a section NAME is an
    ! identifier and must come back trimmed with its authored case intact.
    call good_draft(d)
    call opt_set(d%solver%linear, '  profile  ')
    call opt_set(d%sections(1)%formulation, 'pe ')
    call opt_set(d%sections(1)%element, ' q4')
    call opt_set(d%sections(1)%class, 'co')
    call opt_set(d%sections(1)%fields, 'u')
    call opt_set(d%materials(1)%model, 'elastic_isotropic')
    call opt_set(d%materials(1)%kind, 'mechanical')
    call opt_set(d%steps(1)%procedure, ' q ')
    call opt_set(d%sections(1)%special, ' st ')
    call opt_set(d%sections(1)%name, '  MixedCase_g1  ')
    call opt_set(d%steps(1)%load_mode, ' load ')
    call opt_set(d%steps(1)%output%format, ' gidr ')
    call run_counts(d, good_counts(), p, man, errs, ok)
    call check('N1  a draft of padded lower-case enums is accepted', ok)
    if (allocated(p)) then
      ! read by the gate
      call check('N1  solver.linear canonicalised to PROFILE', &
                 text_is(p%solver%linear, 'PROFILE'))
      call check('N1  sections[1].formulation canonicalised to PE', &
                 text_is(p%sections(1)%formulation, 'PE'))
      call check('N1  sections[1].element canonicalised to Q4', &
                 text_is(p%sections(1)%element, 'Q4'))
      call check('N1  sections[1].class canonicalised to CO', &
                 text_is(p%sections(1)%class, 'CO'))
      call check('N1  sections[1].fields canonicalised to U', &
                 text_is(p%sections(1)%fields, 'U'))
      call check('N1  materials[1].model canonicalised to ELASTIC_ISOTROPIC', &
                 text_is(p%materials(1)%model, 'ELASTIC_ISOTROPIC'))
      call check('N1  materials[1].kind canonicalised to MECHANICAL', &
                 text_is(p%materials(1)%kind, 'MECHANICAL'))
      call check('N1  steps[1].procedure canonicalised to Q', &
                 text_is(p%steps(1)%procedure, 'Q'))
      ! never read by the gate: the fields a regression would hide in
      call check('N1  steps[1].output.format canonicalised to GIDR', &
                 text_is(p%steps(1)%output%format, 'GIDR'))
      call check('N1  steps[1].load_mode canonicalised to LOAD', &
                 text_is(p%steps(1)%load_mode, 'LOAD'))
      call check('N1  sections[1].special canonicalised to ST', &
                 text_is(p%sections(1)%special, 'ST'))
      call check('N1  sections[1].name is trimmed but keeps its case', &
                 text_is(p%sections(1)%name, 'MixedCase_g1'))
    else
      call check('N1  the canonicalised draft published a problem', .false.)
    end if

    ! P0 -- the requested default profile must be the one compiled in, so a
    ! caller cannot silently receive another profile's defaults.
    call good_draft(d)
    call expect_profile_rejected('P0  an unknown profile tag is refused', d)
  end subroutine group_normalize

  ! ==========================================================================
  ! 2b. validate counter-examples: V1..V13, V15..V22
  ! ==========================================================================

  subroutine group_validate()
    type(problem_state_t), allocatable :: d
    type(material_t), allocatable :: mats(:)
    type(elset_t), allocatable :: es(:)
    type(section_t), allocatable :: sc(:)
    type(step_t), allocatable :: sts(:)
    type(amplitude_point_t) :: swap

    write (output_unit, '(a)') '-- 2b. validate counter-examples'

    ! V1 -- a required field left unset.
    call good_draft(d)
    call opt_clear(d%materials(1)%nu)
    call expect_rule('V1  required field unset', 'V1', PE_MISSING_FIELD, &
                     'materials', 'nu', d)

    ! V2 -- section references a material id that does not exist.
    call good_draft(d)
    call opt_set(d%sections(1)%material, 7_int32)
    call expect_rule('V2  dangling material reference', 'V2', PE_DANGLING_REF, &
                     'sections', 'material', d)

    ! V3 -- gravity references an amplitude that does not exist.
    call good_draft(d)
    d%steps(1)%load%gravity%amplitude = [3_int32]
    call expect_rule('V3  dangling gravity amplitude', 'V3', PE_DANGLING_REF, &
                     'steps[1].load.gravity', 'amplitude[1]', d)

    ! V4 -- a node set names a node id that is not in the mesh.
    call good_draft(d)
    d%mesh%nsets(1)%nodes = [1_int32, 999_int32]
    call expect_rule('V4  dangling node-set member', 'V4', PE_DANGLING_REF, &
                     'mesh.nsets', 'nodes[2]', d)

    ! V5 -- element connectivity names a node id that is not in the mesh.
    call good_draft(d)
    d%mesh%elements(1)%nodes = [1_int32, 2_int32, 3_int32, 400_int32]
    call expect_rule('V5  dangling connectivity entry', 'V5', PE_DANGLING_REF, &
                     'mesh.elements', 'nodes[4]', d)

    ! V6 -- two materials share one id.
    call good_draft(d)
    allocate (mats(2))
    mats(1) = d%materials(1)
    mats(2) = d%materials(1)
    call opt_set(mats(2)%name, 'concrete2')
    call move_alloc(mats, d%materials)
    call expect_rule('V6  duplicate material id', 'V6', PE_DUPLICATE_REF, &
                     'materials', 'id', d)

    ! V7 -- one element in two element sets, with element%elset already set so
    ! that the normalize back-reference fill (N6) does not claim the defect
    ! first. If this case reports N6 instead of V7, V7 is unreachable.
    call good_draft(d)
    call opt_set(d%mesh%elements(1)%elset, 1_int32)
    allocate (sc(2))
    sc(1) = d%sections(1)
    sc(2) = d%sections(1)
    call opt_set(sc(2)%name, 'g2')
    call move_alloc(sc, d%sections)
    allocate (es(2))
    allocate (es(1)%elements(1))
    es(1)%elements = [1_int32]
    allocate (es(2)%elements(1))
    es(2)%elements = [1_int32]
    call move_alloc(es, d%mesh%elsets)
    call regrow_per_section(d, 2)
    call expect_rule('V7  duplicate element-set membership', 'V7', PE_DUPLICATE_REF, &
                     'mesh.elsets', 'elements[1]', d)

    ! V8 -- an unset collection is not an explicitly empty one (I04).
    call good_draft(d)
    deallocate (d%mesh%elsets)
    call expect_rule('V8  unset collection is not empty', 'V8', PE_MISSING_FIELD, &
                     'mesh.elsets', '', d)

    ! V9 -- an element set that is explicitly empty has no elements to run on.
    ! element%elset is stated so that the normalize back-reference fill does not
    ! report "element 1 is in no element set" (N6) before validate is reached.
    call good_draft(d)
    call opt_set(d%mesh%elements(1)%elset, 1_int32)
    deallocate (d%mesh%elsets(1)%elements)
    allocate (d%mesh%elsets(1)%elements(0))
    call expect_rule('V9  empty element set', 'V9', PE_EMPTY_COLLECTION, &
                     'mesh.elsets', 'elements', d)

    ! V10 -- a node carries three coordinates in a two-dimensional mesh.
    call good_draft(d)
    deallocate (d%mesh%nodes(3)%xyz)
    allocate (d%mesh%nodes(3)%xyz(3))
    d%mesh%nodes(3)%xyz = [48.0_real64, 60.0_real64, 0.0_real64]
    call expect_rule('V10 node coordinate count', 'V10', PE_COUNT_MISMATCH, &
                     'mesh.nodes', 'xyz', d)

    ! V11 -- one amplitude reference per section, and there is one section.
    call good_draft(d)
    deallocate (d%steps(1)%load%gravity%amplitude)
    allocate (d%steps(1)%load%gravity%amplitude(2))
    d%steps(1)%load%gravity%amplitude = [1_int32, 1_int32]
    call expect_rule('V11 gravity amplitude count', 'V11', PE_COUNT_MISMATCH, &
                     'steps[1].load.gravity', 'amplitude', d)

    ! V12 -- one stress-averaging selector per section.
    call good_draft(d)
    deallocate (d%steps(1)%output%stress_averaging)
    allocate (d%steps(1)%output%stress_averaging(0))
    call expect_rule('V12 stress averaging count', 'V12', PE_COUNT_MISMATCH, &
                     'steps[1].output', 'stress_averaging', d)

    ! V13 -- a Q4 needs four connectivity entries.
    call good_draft(d)
    deallocate (d%mesh%elements(1)%nodes)
    allocate (d%mesh%elements(1)%nodes(3))
    d%mesh%elements(1)%nodes = [1_int32, 2_int32, 3_int32]
    call expect_rule('V13 connectivity count', 'V13', PE_COUNT_MISMATCH, &
                     'mesh.elements', 'nodes', d)

    ! V15 -- an authored zero is a value, not an omission. The counter-example
    ! for this rule is a rule that REJECTS the zero, so the assertion is that the
    ! draft passes. Group 3 then checks that the zero survives into the finalized
    ! state rather than being replaced by a default.
    call good_draft(d)
    call opt_set(d%steps(1)%load%gravity%magnitude, 0.0_real64)
    call expect_pass('V15 an authored zero magnitude is accepted', d)

    ! V16 -- amplitude points must advance in time.
    call good_draft(d)
    swap = d%amplitudes(1)%points(1)
    d%amplitudes(1)%points(1) = d%amplitudes(1)%points(2)
    d%amplitudes(1)%points(2) = swap
    call expect_rule('V16 amplitude time ordering', 'V16', PE_INVALID_INPUT, &
                     'amplitudes[1].points', 'time', d)

    ! V17 -- a prescribed degree of freedom outside 1..dimension.
    call good_draft(d)
    call opt_set(d%steps(1)%boundary(1)%dof, 3_int32)
    call expect_rule('V17 boundary dof range', 'V17', PE_INVALID_INPUT, &
                     'steps[1].boundary', 'dof', d)

    ! V18 -- a prescribed record referencing an amplitude that does not exist.
    call good_draft(d)
    call opt_set(d%steps(1)%boundary(1)%amplitude, 9_int32)
    call expect_rule('V18 boundary amplitude reference', 'V18', PE_DANGLING_REF, &
                     'steps[1].boundary', 'amplitude', d)

    ! V19 -- Poisson's ratio outside the physically admissible range.
    call good_draft(d)
    call opt_set(d%materials(1)%nu, 0.6_real64)
    call expect_rule('V19 material physics range', 'V19', PE_INVALID_INPUT, &
                     'materials', 'nu', d)

    ! V20 -- an analysis with an explicitly empty step list.
    call good_draft(d)
    allocate (sts(0))
    call move_alloc(sts, d%steps)
    call expect_rule('V20 empty step list', 'V20', PE_EMPTY_COLLECTION, &
                     'steps', '', d)

    call group_declared_counts()
  end subroutine group_validate

  ! --------------------------------------------------------------------------
  ! V21 / V22: the deck's redundant declared counts.
  ! --------------------------------------------------------------------------

  subroutine group_declared_counts()
    type(problem_state_t), allocatable :: d, p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    type(declared_counts_t) :: dc
    logical :: ok

    ! V21 -- the deck declares a node count the object list does not support.
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%node_count, 289_int32)
    call expect_rule_counts('V21 declared node count disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'mesh.nodes', 'count', d, dc)

    ! The declared counts are themselves three-state, and the three states give
    ! three different verdicts. No `declared` argument at all means the reader
    ! captured no declarations, so no count is compared and no check entry is
    ! written. A `declared` whose node count is unset compares the other seven
    ! and writes seven entries. A node count declared as ZERO is a statement the
    ! deck made, and it disagrees with the four nodes the objects yield, so V21
    ! fires. A pipeline that treated an unset count as a zero would reject the
    ! middle case, and one that treated a zero as absent would accept the last.
    call good_draft(d)
    call run(d, p, man, errs, ok)
    call check('I04 no declared counts means no comparison', &
               ok .and. n_checks_in(man) == 0)

    call good_draft(d)
    dc = good_counts()
    call opt_clear(dc%node_count)
    call run_counts(d, dc, p, man, errs, ok)
    call check('I04 an unset declared count is skipped, not read as zero', &
               ok .and. n_checks_in(man) == 7)

    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%node_count, 0_int32)
    call expect_rule_counts('I04 a declared zero count is compared', 'V21', &
                            PE_COUNT_MISMATCH, 'mesh.nodes', 'count', d, dc)

    ! V22 -- the deck declares a load kind this path has no object for.
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%beam_load_count, 2_int32)
    call expect_rule_counts('V22 unsupported declared load count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'beam_load_count', d, dc)
  end subroutine group_declared_counts

  ! ==========================================================================
  ! 2e. one counter-example per CONDITION, not per rule id
  ! ==========================================================================

  ! The capability table showed that a rule id is the wrong unit of coverage:
  ! fifteen rows share six ids, and six rows had no counter-example while their
  ! id looked covered. The same shape exists in the validate family. Counting
  ! raise sites in the pipeline: V1 has eleven, V6 four, V19 three, N6 and V11
  ! and V20 two each, and V21 and V22 fan out to eight and ten declared counts
  ! through a shared helper. Every condition below was reachable and untested
  ! until this group existed.
  subroutine group_conditions()
    type(problem_state_t), allocatable :: d
    type(section_t), allocatable :: sc(:)
    type(element_t), allocatable :: els(:)
    type(elset_t), allocatable :: es(:)
    type(declared_counts_t) :: dc

    write (output_unit, '(a)') '-- 2e. per-condition counter-examples'

    ! -- N6, second condition: an element in NO element set. The first condition
    !    (an element in two) is covered in group 2a.
    call good_draft(d)
    deallocate (d%mesh%elsets(1)%elements)
    allocate (d%mesh%elsets(1)%elements(0))
    call expect_rule('N6  element in no element set', 'N6', PE_INVALID_INPUT, &
                     'mesh.elements', 'elset', d)
    ! -- V1, the other ten required fields. materials.nu is covered in 2b.
    call good_draft(d)
    call opt_clear(d%mesh%dimension)
    call expect_rule('V1  required mesh dimension unset', 'V1', PE_MISSING_FIELD, &
                     'mesh', 'dimension', d)
    call good_draft(d)
    call opt_clear(d%solver%linear)
    call expect_rule('V1  required solver linear unset', 'V1', PE_MISSING_FIELD, &
                     'solver', 'linear', d)
    call good_draft(d)
    call opt_clear(d%mesh%nodes(1)%id)
    call expect_rule('V1  required node id unset', 'V1', PE_MISSING_FIELD, &
                     'mesh.nodes', 'id', d)
    call good_draft(d)
    call opt_clear(d%mesh%elements(1)%id)
    call expect_rule('V1  required element id unset', 'V1', PE_MISSING_FIELD, &
                     'mesh.elements', 'id', d)
    call good_draft(d)
    call opt_clear(d%materials(1)%id)
    call expect_rule('V1  required material id unset', 'V1', PE_MISSING_FIELD, &
                     'materials', 'id', d)
    call good_draft(d)
    call opt_clear(d%materials(1)%E)
    call expect_rule('V1  required material E unset', 'V1', PE_MISSING_FIELD, &
                     'materials', 'E', d)
    call good_draft(d)
    call opt_clear(d%sections(1)%element_kind)
    call expect_rule('V1  required section element_kind unset', 'V1', PE_MISSING_FIELD, &
                     'sections', 'element_kind', d)
    call good_draft(d)
    call opt_clear(d%sections(1)%formulation)
    call expect_rule('V1  required section formulation unset', 'V1', PE_MISSING_FIELD, &
                     'sections', 'formulation', d)
    call good_draft(d)
    call opt_clear(d%steps(1)%procedure)
    call expect_rule('V1  required step procedure unset', 'V1', PE_MISSING_FIELD, &
                     'steps', 'procedure', d)
    call good_draft(d)
    call opt_clear(d%steps(1)%controls%increments)
    call expect_rule('V1  required controls increments unset', 'V1', PE_MISSING_FIELD, &
                     'steps[1].controls', 'increments', d)

    ! -- V6, the other three uniqueness domains. Duplicate material ids are
    !    covered in 2b; ids on nodes and elements and names on sections are not.
    call good_draft(d)
    call opt_set(d%mesh%nodes(2)%id, 1_int32)
    call expect_rule('V6  duplicate node id', 'V6', PE_DUPLICATE_REF, &
                     'mesh.nodes', 'id', d)

    call good_draft(d)
    allocate (els(2))
    els(1) = d%mesh%elements(1)
    els(2) = d%mesh%elements(1)
    call opt_set(els(1)%elset, 1_int32)
    call opt_set(els(2)%elset, 1_int32)
    call move_alloc(els, d%mesh%elements)
    call expect_rule('V6  duplicate element id', 'V6', PE_DUPLICATE_REF, &
                     'mesh.elements', 'id', d)

    call good_draft(d)
    call opt_set(d%mesh%elements(1)%elset, 1_int32)
    allocate (sc(2))
    sc(1) = d%sections(1)
    sc(2) = d%sections(1)
    call move_alloc(sc, d%sections)
    allocate (es(2))
    allocate (es(1)%elements(1))
    es(1)%elements = [1_int32]
    allocate (es(2)%elements(0))
    call move_alloc(es, d%mesh%elsets)
    call regrow_per_section(d, 2)
    call expect_rule('V6  duplicate section name', 'V6', PE_DUPLICATE_REF, &
                     'sections', 'name', d)

    ! -- V11, second condition: the gravity DIRECTION against the dimension.
    !    The amplitude-against-sections condition is covered in 2b.
    call good_draft(d)
    deallocate (d%steps(1)%load%gravity%direction)
    allocate (d%steps(1)%load%gravity%direction(3))
    d%steps(1)%load%gravity%direction = [0.0_real64, -1.0_real64, 0.0_real64]
    call expect_rule('V11 gravity direction count', 'V11', PE_COUNT_MISMATCH, &
                     'steps[1].load.gravity', 'direction', d)

    ! -- V19, the other two physical ranges. Poisson's ratio is covered in 2b.
    call good_draft(d)
    call opt_set(d%materials(1)%E, -1.0_real64)
    call expect_rule('V19 non-positive Young modulus', 'V19', PE_INVALID_INPUT, &
                     'materials', 'E', d)

    call good_draft(d)
    call opt_set(d%materials(1)%density, -1.0_real64)
    call expect_rule('V19 negative density', 'V19', PE_INVALID_INPUT, &
                     'materials', 'density', d)

    ! -- V20, second condition: the step collection UNSET rather than empty.
    !    Same rule, different code, and that difference is the ADR-0002 point.
    call good_draft(d)
    deallocate (d%steps)
    call expect_rule('V20 step collection unset', 'V20', PE_MISSING_FIELD, &
                     'steps', '', d)

    ! -- V24, first condition: the boundary set ordinals are KEYS, so they must
    !    run 1..n with no gap. Sizing a collection by the maximum ordinal instead
    !    publishes a manufactured empty set for every ordinal the author skipped,
    !    which asserts "explicitly empty" on the author's behalf. The old
    !    behaviour was that this draft SUCCEEDED, so asserting that it fails is
    !    precisely the test that would have caught it.
    call good_draft(d)
    call opt_set(d%steps(1)%boundary(1)%name, 2_int32)
    call opt_set(d%steps(1)%boundary(2)%name, 3_int32)
    call expect_rule('V24 boundary set ordinals skip a key', 'V24', PE_INVALID_INPUT, &
                     'steps[1].boundary', 'name', d)

    ! -- V24, second condition: ordinal 0 is not a key at all.
    call good_draft(d)
    call opt_set(d%steps(1)%boundary(1)%name, 0_int32)
    call expect_rule('V24 boundary set ordinal below one', 'V24', PE_INVALID_INPUT, &
                     'steps[1].boundary', 'name', d)

    ! -- V25, an element set naming an element that was never declared. V4 and V5
    !    already did this for node ids in node sets and in connectivity; nothing
    !    did it for element ids in element sets.
    call good_draft(d)
    deallocate (d%mesh%elsets(1)%elements)
    allocate (d%mesh%elsets(1)%elements(2))
    d%mesh%elsets(1)%elements = [1_int32, 99_int32]
    call expect_rule('V25 element set names a missing element', 'V25', PE_DANGLING_REF, &
                     'mesh.elsets', 'elements[2]', d)

    ! -- V21 fans out to eight declared counts through one raise site. The node
    !    count is covered in 2b; here are the other seven.
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%element_count, 99_int32)
    call expect_rule_counts('V21 declared element count disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'mesh.elements', 'count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%material_count, 99_int32)
    call expect_rule_counts('V21 declared material count disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'materials', 'count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%section_count, 99_int32)
    call expect_rule_counts('V21 declared section count disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'sections', 'count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%amplitude_count, 99_int32)
    call expect_rule_counts('V21 declared amplitude count disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'amplitudes', 'count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%nset_count, 99_int32)
    call expect_rule_counts('V21 declared node set count disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'mesh.nsets', 'count', d, dc)
    call good_draft(d)
    dc = good_counts()
    dc%elset_size = [99_int32]
    call expect_rule_counts('V21 declared element-set size disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'mesh.elsets[1]', 'count', d, dc)

    call good_draft(d)
    dc = good_counts()
    dc%amplitude_points = [99_int32]
    call expect_rule_counts('V21 declared amplitude point count disagrees', 'V21', &
                            PE_COUNT_MISMATCH, 'amplitudes[1]', 'points', d, dc)

    ! -- V22 covers ten load and thermal kinds this build carries no object for.
    !    Beam loads are covered in 2b; here are the other nine.
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%point_load_group_count, 1_int32)
    call expect_rule_counts('V22 declared point load group count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'point_load_group_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%edge_count, 1_int32)
    call expect_rule_counts('V22 declared loaded edge count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'edge_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%edge_load_group_count, 1_int32)
    call expect_rule_counts('V22 declared edge load group count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'edge_load_group_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%edge_load_element_group_count, 1_int32)
    call expect_rule_counts('V22 declared edge load element group count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'edge_load_element_group_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%plate_load_count, 1_int32)
    call expect_rule_counts('V22 declared plate load count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'plate_load_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%temperature_surface_count, 1_int32)
    call expect_rule_counts('V22 declared temperature surface count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'temperature_surface_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%temperature_edge_count, 1_int32)
    call expect_rule_counts('V22 declared temperature edge count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'temperature_edge_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%temperature_element_group_count, 1_int32)
    call expect_rule_counts('V22 declared temperature element group count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'temperature_element_group_count', d, dc)
    call good_draft(d)
    dc = good_counts()
    call opt_set(dc%pipe_count, 1_int32)
    call expect_rule_counts('V22 declared pipe count', 'V22', &
                            PE_UNSUPPORTED, 'declared_counts', 'pipe_count', d, dc)
  end subroutine group_conditions

  ! ==========================================================================
  ! 2c. capability gate counter-examples: G1..G6
  ! ==========================================================================

  subroutine group_gate()
    type(problem_state_t), allocatable :: d, p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    type(step_t), allocatable :: sts(:)
    logical :: ok

    write (output_unit, '(a)') '-- 2c. capability gate counter-examples'

    ! The capability table has fifteen rows but only six rule ids, so several
    ! rows hide behind a rule id that another row already makes "covered".
    ! Binding a finding by rule id, which is what makes the rest of this matrix
    ! precise, cannot tell two rows of the same rule apart. Each row therefore
    ! gets its own draft, mutating exactly the one field that row reads.

    ! G1 row 1 of 4 -- the element type name.
    call good_draft(d)
    call opt_set(d%sections(1)%element, 'Q8')
    call expect_rule('G1  unsupported element type', 'G1', PE_UNSUPPORTED, &
                     'sections', 'element', d)

    ! G1 row 2 of 4 -- the element kind code.
    call good_draft(d)
    call opt_set(d%sections(1)%element_kind, 9_int32)
    call expect_rule('G1  unsupported element kind code', 'G1', PE_UNSUPPORTED, &
                     'sections', 'element_kind', d)

    ! G1 row 3 of 4 -- the element class. BM is a beam, not a continuum.
    call good_draft(d)
    call opt_set(d%sections(1)%class, 'BM')
    call expect_rule('G1  unsupported element class', 'G1', PE_UNSUPPORTED, &
                     'sections', 'class', d)

    ! G1 row 4 of 4 -- the field set. P adds pore pressure to displacement.
    call good_draft(d)
    call opt_set(d%sections(1)%fields, 'P')
    call expect_rule('G1  unsupported field set', 'G1', PE_UNSUPPORTED, &
                     'sections', 'fields', d)

    ! G2 -- three spatial dimensions. G2 owns TWO capability rows, the
    ! formulation and the dimension, and the rule id alone does not tell them
    ! apart: a matrix that exercised only the formulation would leave the
    ! dimension row with no counter-example while still showing G2 as covered.
    ! The draft has to be consistently three-dimensional or the coordinate and
    ! gravity-direction count rules claim it during validate and the gate is
    ! never reached, so make_three_dimensional widens the node coordinates and
    ! the gravity direction along with the declared dimension. Boundary degrees
    ! of freedom 1 and 2 stay inside 1..3 and the Q4 connectivity is untouched,
    ! so this draft carries exactly one defect.
    call good_draft(d)
    call make_three_dimensional(d)
    call run(d, p, man, errs, ok)
    call record_capability_hits(errs)
    call assert_finding('G2  unsupported spatial dimension', 'G2', PE_UNSUPPORTED, &
                        'mesh', 'dimension', errs, ok)
    ! The point of the case is WHERE it is rejected. A bare dimension flip is
    ! caught by the coordinate and gravity-direction arity rules during validate
    ! and never reaches the gate at all, which would leave the dimension row with
    ! no counter-example while still showing G2 as covered.
    call check('G2  the dimension is rejected at the capability gate', &
               stage_of(errs, 'G2') == PE_STAGE_CAPABILITY)
    call check('G2  no arity rule fired first', &
               (.not. has_rule(errs, 'V10')) .and. (.not. has_rule(errs, 'V11')) &
               .and. (.not. has_rule(errs, 'V13')) .and. (.not. has_rule(errs, 'V17')))
    call check('G2  the draft is rejected for the dimension alone', &
               errs%count() == 1)

    ! G2 -- plane stress instead of plane strain.
    call good_draft(d)
    call opt_set(d%sections(1)%formulation, 'PS')
    call expect_rule('G2  unsupported formulation', 'G2', PE_UNSUPPORTED, &
                     'sections', 'formulation', d)

    ! G2 row 3 of 3 -- the analysis procedure. D is dynamic, not static.
    call good_draft(d)
    call opt_set(d%steps(1)%procedure, 'D')
    call expect_rule('G2  unsupported analysis procedure', 'G2', PE_UNSUPPORTED, &
                     'steps', 'procedure', d)

    ! G3 row 1 of 2 -- the material kind.
    call good_draft(d)
    call opt_set(d%materials(1)%kind, 'THERMAL')
    call expect_rule('G3  unsupported material kind', 'G3', PE_UNSUPPORTED, &
                     'materials', 'kind', d)

    ! G3 -- a constitutive model this build cannot integrate.
    call good_draft(d)
    call opt_set(d%materials(1)%model, 'MOHR_COULOMB')
    call expect_rule('G3  unsupported material model', 'G3', PE_UNSUPPORTED, &
                     'materials', 'model', d)

    ! G4 -- a linear solver this build does not carry.
    call good_draft(d)
    call opt_set(d%solver%linear, 'PARDISO')
    call expect_rule('G4  unsupported linear solver', 'G4', PE_UNSUPPORTED, &
                     'solver', 'linear', d)

    ! G4 row 2 of 2 -- solver symmetry. The legacy flag has inverted sense, so
    ! this is the one gate row whose authored value is a logical.
    call good_draft(d)
    call opt_set(d%solver%symmetric, .false.)
    call expect_rule('G4  unsupported unsymmetric solve', 'G4', PE_UNSUPPORTED, &
                     'solver', 'symmetric', d)

    ! G5 -- gravity switched off: the only load kind on this path.
    call good_draft(d)
    call opt_set(d%steps(1)%load%gravity%enabled, 0_int32)
    call expect_rule('G5  unsupported load configuration', 'G5', PE_UNSUPPORTED, &
                     'steps[1].load.gravity', 'enabled', d)

    ! G6 -- more than one increment.
    call good_draft(d)
    call opt_set(d%steps(1)%controls%increments, 10_int32)
    call expect_rule('G6  unsupported increment count', 'G6', PE_UNSUPPORTED, &
                     'steps[1].controls', 'increments', d)

    ! G6 -- and more than one step, the cardinality half of the same rule.
    call good_draft(d)
    allocate (sts(2))
    sts(1) = d%steps(1)
    sts(2) = d%steps(1)
    call move_alloc(sts, d%steps)
    call expect_rule('G6  unsupported step count', 'G6', PE_UNSUPPORTED, &
                     'steps', 'size', d)

    ! G6 -- no sections at all. This one is the gate's job alone: no validate
    ! rule requires the section collection to exist, so before the gate counted
    ! an absent collection as zero, such a draft passed the gate and failed much
    ! later in finalize with a confusing missing-elset finding.
    call good_draft(d)
    deallocate (d%sections)
    call expect_rule('G6  no sections at all', 'G6', PE_UNSUPPORTED, &
                     'sections', 'size', d)

    ! Mechanical, not a one-time audit: every declared row must have been hit by
    ! one of the drafts above.
    call check_capability_binding_is_unique()
    call check_capability_coverage()

    call group_finalize()
  end subroutine group_gate

  ! ==========================================================================
  ! 2d. finalize counter-examples: F-IM2, F-IM5
  ! ==========================================================================

  ! These two are only reachable on a draft that is otherwise wholly valid, so
  ! they are the deepest cases in the matrix: normalize, validate and the gate
  ! all have to pass before the rule can fire at all.
  subroutine group_finalize()
    type(problem_state_t), allocatable :: d

    write (output_unit, '(a)') '-- 2d. finalize counter-examples'

    ! F-IM2 -- the element names an element set that does not exist. Stating the
    ! reference explicitly is what gets past the normalize back-fill, which only
    ! touches elements whose owning set is unset.
    call good_draft(d)
    call opt_set(d%mesh%elements(1)%elset, 7_int32)
    call expect_rule('F-IM2 element set reference out of range', 'F-IM2', &
                     PE_DANGLING_REF, 'mesh.elements', 'elset', d)

    ! F-IM5 -- neither provenance of the section header material is available:
    ! the element records carry no material and none was authored on the section.
    call good_draft(d)
    call opt_clear(d%sections(1)%material_header)
    call expect_rule('F-IM5 no material header from either source', 'F-IM5', &
                     PE_MISSING_FIELD, 'sections', 'material_header', d)
  end subroutine group_finalize

  ! ==========================================================================
  ! 3. I04: unset / explicitly empty / an authored zero are three verdicts
  ! ==========================================================================

  subroutine group_i04()
    type(problem_state_t), allocatable :: d, p
    type(problem_errors_t) :: e_unset, e_empty, e_zero
    type(manifest_t), allocatable :: m_unset, m_empty, m_zero
    logical :: ok_unset, ok_empty, ok_zero
    character(len=:), allocatable :: r_unset, r_empty
    real(real64) :: mag
    logical :: found, ok
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    type(declared_counts_t) :: dc_empty
    integer :: i

    write (output_unit, '(a)') '-- 3. I04 three-state (unset / empty / zero)'

    ! (a) the collection was never declared.
    call good_draft(d)
    deallocate (d%mesh%elsets)
    call run(d, p, m_unset, e_unset, ok_unset)

    ! (b) the collection was declared, and declared empty.
    call good_draft(d)
    deallocate (d%mesh%elsets)
    allocate (d%mesh%elsets(0))
    call run(d, p, m_empty, e_empty, ok_empty)

    ! (c) an authored zero VALUE. Zero gravity is a statement, not an omission:
    ! it must pass, and it must reach the finalized state as a SET zero.
    call good_draft(d)
    call opt_set(d%steps(1)%load%gravity%magnitude, 0.0_real64)
    call run(d, p, m_zero, e_zero, ok_zero)

    call check('I04 an unset collection is rejected', .not. ok_unset)
    call check('I04 an explicitly empty collection is rejected', .not. ok_empty)
    call check('I04 an authored zero magnitude is accepted', ok_zero)

    r_unset = first_rule(e_unset)
    r_empty = first_rule(e_empty)
    call check('I04 unset and empty give different verdicts', r_unset /= r_empty)
    if (r_unset == r_empty) then
      write (output_unit, '(a)') '        both verdicts were rule "'//r_unset//'"'
    else
      write (output_unit, '(a)') '        unset -> '//r_unset//', empty -> '//r_empty
    end if

    call check('I04 the zero-magnitude run produced a valid manifest', &
               manifest_is_valid(m_zero) .and. manifest_count(m_zero) > 0)
    if (allocated(p)) then
      call check('I04 the authored zero is still SET after the pipeline', &
                 opt_is_set(p%steps(1)%load%gravity%magnitude))
      call opt_get(p%steps(1)%load%gravity%magnitude, mag, found)
      call check('I04 the authored zero kept its value', &
                 found .and. (transfer(mag, 0_int64) == transfer(0.0_real64, 0_int64)))
    else
      call check('I04 the authored zero is still SET after the pipeline', .false.)
      call check('I04 the authored zero kept its value', .false.)
    end if
    ! The passing side of I04, and unlike the net above this one IS falsifiable by
    ! a single draft: it goes red the day the pipeline drops an authored empty
    ! collection to unset, or fills one in. "The author declared no amplitudes"
    ! and "the author said nothing about amplitudes" are different statements and
    ! both must survive the whole pipeline, not merely be told apart at rejection.
    ! Gravity references ordinal 0, the legacy spelling for no curve in that
    ! group, so the reference rule stays quiet and the empty collection is the
    ! only thing under test.
    call good_draft(d)
    deallocate (d%amplitudes)
    allocate (d%amplitudes(0))
    d%steps(1)%load%gravity%amplitude = [0_int32]
    call opt_clear(d%steps(1)%boundary(1)%amplitude)
    call opt_clear(d%steps(1)%boundary(2)%amplitude)
    dc_empty = good_counts()
    call opt_set(dc_empty%amplitude_count, 0_int32)
    deallocate (dc_empty%amplitude_points)
    call run_counts(d, dc_empty, p, man, errs, ok)
    call check('I04 a draft with an explicitly empty collection is accepted', ok)
    if (.not. ok) then
      do i = 1, errs%count()
        write (output_unit, '(a)') '        finding: '//errs%render(i)
      end do
    end if
    if (allocated(p)) then
      call check('I04 an authored empty collection is still ALLOCATED after finalize', &
                 allocated(p%amplitudes))
      if (allocated(p%amplitudes)) then
        call check('I04 an authored empty collection is still EMPTY after finalize', &
                   size(p%amplitudes) == 0)
      else
        call check('I04 an authored empty collection is still EMPTY after finalize', .false.)
      end if
    else
      call check('I04 an authored empty collection is still ALLOCATED after finalize', .false.)
      call check('I04 an authored empty collection is still EMPTY after finalize', .false.)
    end if

  end subroutine group_i04

  ! ==========================================================================
  ! 4. T01: a failing run leaves no residue, and the next good run succeeds
  ! ==========================================================================

  subroutine group_transaction()
    type(problem_state_t), allocatable :: bad_before, bad_after, p
    type(problem_state_t), allocatable :: d
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok

    write (output_unit, '(a)') '-- 4. T01 transaction (no half-commit, retry works)'

    ! Two independently built copies of the same mutated draft. One is submitted
    ! to the pipeline, the other is never touched, so the comparison is against a
    ! draft the pipeline has never seen rather than against a snapshot the
    ! pipeline could in principle have aliased.
    call good_draft(bad_before)
    call opt_set(bad_before%sections(1)%material, 7_int32)
    call good_draft(bad_after)
    call opt_set(bad_after%sections(1)%material, 7_int32)

    call run(bad_after, p, man, errs, ok)
    call check('T01 the injected failure is reported', .not. ok)
    ! prepare_problem declares `draft` intent(in), so this is belt and braces:
    ! the comparison is component by component over every allocation status,
    ! every array element and every opt_* presence flag AND payload, and it would
    ! still catch a stage that reached the input through an alias.
    call check('T01 the draft is unchanged after the failed run', &
               same_draft(bad_before, bad_after))
    call check('T01 no problem state was published', .not. allocated(p))
    call check('T01 no manifest entry was produced', n_manifest(man) == 0)

    ! Immediately afterwards, in the same process, a legal draft must succeed.
    call good_draft(d)
    call run(d, p, man, errs, ok)
    call check('T01 a legal draft succeeds immediately afterwards', ok)
    call check('T01 the retry produced a manifest', n_manifest(man) > 0)
  end subroutine group_transaction

  ! ==========================================================================
  ! 5. stage barrier: a normalize failure stops the later stages
  ! ==========================================================================

  subroutine group_stage_barrier()
    type(problem_state_t), allocatable :: d, p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok

    write (output_unit, '(a)') '-- 5. stage barrier'

    ! The draft carries a normalize defect (N4, two elsets for one section) AND
    ! three defects only a later stage could report: a missing required field
    ! (V1, validate), an unsupported solver (G4, capability) and a declared node
    ! count that finalize would have to check. If the barrier holds, none of
    ! those three appears.
    call good_draft(d)
    call grow_elsets_to_two(d)
    call opt_clear(d%materials(1)%nu)
    call opt_set(d%solver%linear, 'PARDISO')
    call run(d, p, man, errs, ok)

    call check('P-stage the normalize defect fails the run', .not. ok)
    call check('P-stage a normalize finding is present', has_stage(errs, PE_STAGE_NORMALIZE))
    call check('P-stage validate did not run', .not. has_stage(errs, PE_STAGE_VALIDATE))
    call check('P-stage the capability gate did not run', &
               .not. has_stage(errs, PE_STAGE_CAPABILITY))
    call check('P-stage finalize did not run', .not. has_stage(errs, PE_STAGE_FINALIZE))
    call check('P-stage the later-stage defects are not reported', &
               (.not. has_rule(errs, 'V1')) .and. (.not. has_rule(errs, 'G4')))
    call check('P-stage finalize produced no manifest entry', n_manifest(man) == 0)
  end subroutine group_stage_barrier

  ! ==========================================================================
  ! 6. accumulation: one stage reports every independent defect it finds
  ! ==========================================================================

  subroutine group_accumulation()
    type(problem_state_t), allocatable :: d, p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok

    write (output_unit, '(a)') '-- 6. accumulation within a stage'

    ! Three independent validate defects, in three different objects.
    call good_draft(d)
    call opt_clear(d%materials(1)%nu)                    ! V1  materials[1].nu
    call opt_set(d%sections(1)%material, 7_int32)        ! V2  sections[1].material
    d%mesh%nsets(1)%nodes = [1_int32, 999_int32]         ! V4  mesh.nsets[1].nodes
    call run(d, p, man, errs, ok)

    call check('P-acc the run fails', .not. ok)
    call check('P-acc at least three findings accumulated', errs%count() >= 3)
    call check('P-acc V1 is reported', has_rule(errs, 'V1'))
    call check('P-acc V2 is reported', has_rule(errs, 'V2'))
    call check('P-acc V4 is reported', has_rule(errs, 'V4'))
  end subroutine group_accumulation

  ! ==========================================================================
  ! the pipeline-facing surface: one wrapper, so the API appears in one place
  ! ==========================================================================

  ! prepare_problem has no success flag: it APPENDS findings and publishes
  ! `problem` and `manifest` together only when the whole run succeeded. Success
  ! is therefore "this run added no finding and a problem came back", and the
  ! accumulator is cleared first so a previous case's findings cannot be read as
  ! this one's.
  subroutine run(draft, problem, man, errors, ok)
    type(problem_state_t), intent(in) :: draft
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(manifest_t), allocatable, intent(inout) :: man
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok
    if (allocated(problem)) deallocate (problem)
    if (allocated(man)) deallocate (man)
    call errors%clear()
    call prepare_problem(draft, PROFILE_TAG, problem, man, errors)
    ok = (.not. errors%any()) .and. allocated(problem)
    if (ok) call check_no_manufactured_empty(draft, problem)
  end subroutine run

  subroutine run_counts(draft, declared, problem, man, errors, ok)
    type(problem_state_t), intent(in) :: draft
    type(declared_counts_t), intent(in) :: declared
    type(problem_state_t), allocatable, intent(inout) :: problem
    type(manifest_t), allocatable, intent(inout) :: man
    type(problem_errors_t), intent(inout) :: errors
    logical, intent(out) :: ok
    if (allocated(problem)) deallocate (problem)
    if (allocated(man)) deallocate (man)
    call errors%clear()
    call prepare_problem(draft, PROFILE_TAG, problem, man, errors, declared=declared)
    ok = (.not. errors%any()) .and. allocated(problem)
    if (ok) call check_no_manufactured_empty(draft, problem)
  end subroutine run_counts

  ! How many `check` entries a manifest carries. Used to tell "no declaration was
  ! made" from "a declaration was made and compared".
  integer function n_checks_in(man) result(n)
    type(manifest_t), allocatable, intent(in) :: man
    type(manifest_entry_t) :: e
    logical :: found
    integer :: k
    n = 0
    if (.not. allocated(man)) return
    do k = 1, manifest_count(man)
      call manifest_get(man, k, e, found)
      if (found .and. txt(e%kind) == MANIFEST_KIND_CHECK) n = n + 1
    end do
  end function n_checks_in

  ! Applied to EVERY passing run, not to one case: the pipeline may never publish
  ! an allocated zero-length collection the author did not declare.
  !
  ! CLASSIFICATION, so nobody reads this as rule coverage. No draft can make this
  ! fail. Probed by disabling rules in a scratch copy of the pipeline: with the
  ! boundary-ordinal rule disabled the internal net INV-EMPTY-DERIVED fires first
  ! and aborts the run, so nothing is published and this never gets to look; only
  ! with BOTH that rule and that net disabled does it go red. It is reachable
  ! solely under two simultaneous faults, so it is a NET, not a rule, and it is
  ! excluded from every rule count this file reports.
  !
  ! SCOPE, narrower than breadth suggests. Only two collections can be
  ! manufactured by today's pipeline, mesh.elsets and mesh.nsets in the two
  ! derive routines; every other collection in the published problem is a whole
  ! object copy of the draft, which is what makes N5 a prohibition rather than a
  ! claim. So the walk over nodes, elements, materials, sections, amplitudes and
  ! the step lists guards against FUTURE edits, and is not live protection today.
  !
  ! An allocated empty collection is a STATEMENT under ADR-0002, "the author
  ! declared this empty", and only the author may make it. A stage that sizes a
  ! collection by arithmetic -- by a maximum ordinal, say -- asserts that
  ! statement on the author's behalf for every index the arithmetic skipped.
  ! That defect had three independent causes in finalize and only one was
  ! reachable through the draft that reported it; a per-case fix would have left
  ! the other two. A structural check catches the class, including causes nobody
  ! has thought of, which is why it is here rather than in three counter-examples.
  subroutine check_no_manufactured_empty(draft, problem)
    type(problem_state_t), intent(in) :: draft
    type(problem_state_t), allocatable, intent(in) :: problem
    integer :: before, after
    before = zero_length_of(draft)
    after = zero_length_in(problem)
    call check('P-emp the run manufactured no empty collection', after <= before)
  end subroutine check_no_manufactured_empty

  ! How many collections of a published problem are allocated with length zero.
  ! The good draft declares none empty, so on a passing run this must be zero.
  integer function zero_length_in(p) result(n)
    type(problem_state_t), allocatable, intent(in) :: p
    n = 0
    if (allocated(p)) n = zero_length_of(p)
  end function zero_length_in

  integer function zero_length_of(p) result(n)
    type(problem_state_t), intent(in) :: p
    integer :: i
    n = 0
    if (allocated(p%mesh%nodes)) then
      if (size(p%mesh%nodes) == 0) n = n + 1
    end if
    if (allocated(p%mesh%elements)) then
      if (size(p%mesh%elements) == 0) n = n + 1
    end if
    if (allocated(p%mesh%elsets)) then
      if (size(p%mesh%elsets) == 0) n = n + 1
      do i = 1, size(p%mesh%elsets)
        if (allocated(p%mesh%elsets(i)%elements)) then
          if (size(p%mesh%elsets(i)%elements) == 0) n = n + 1
        end if
      end do
    end if
    if (allocated(p%mesh%nsets)) then
      if (size(p%mesh%nsets) == 0) n = n + 1
      do i = 1, size(p%mesh%nsets)
        if (allocated(p%mesh%nsets(i)%nodes)) then
          if (size(p%mesh%nsets(i)%nodes) == 0) n = n + 1
        end if
      end do
    end if
    if (allocated(p%materials)) then
      if (size(p%materials) == 0) n = n + 1
    end if
    if (allocated(p%sections)) then
      if (size(p%sections) == 0) n = n + 1
    end if
    if (allocated(p%amplitudes)) then
      if (size(p%amplitudes) == 0) n = n + 1
      do i = 1, size(p%amplitudes)
        if (allocated(p%amplitudes(i)%points)) then
          if (size(p%amplitudes(i)%points) == 0) n = n + 1
        end if
      end do
    end if
    if (allocated(p%steps)) then
      if (size(p%steps) == 0) n = n + 1
      do i = 1, size(p%steps)
        if (allocated(p%steps(i)%boundary)) then
          if (size(p%steps(i)%boundary) == 0) n = n + 1
        end if
        if (allocated(p%steps(i)%activation)) then
          if (size(p%steps(i)%activation) == 0) n = n + 1
        end if
      end do
    end if
  end function zero_length_of

  ! Entry count of a manifest that may never have been published.
  integer function n_manifest(man) result(n)
    type(manifest_t), allocatable, intent(in) :: man
    n = 0
    if (allocated(man)) n = manifest_count(man)
  end function n_manifest

  ! ==========================================================================
  ! assertions
  ! ==========================================================================

  ! Assert that `draft` is rejected AND that the first finding carrying rule id
  ! `rule` names the expected code, object path and field. Asserting only that
  ! the run failed would pass for a pipeline that rejected every draft for the
  ! wrong reason, which is exactly the failure mode this program exists to catch.
  subroutine expect_rule(label, rule, code, object, field, draft)
    character(len=*), intent(in) :: label, rule, code, object, field
    type(problem_state_t), intent(inout) :: draft
    type(problem_state_t), allocatable :: p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok
    call run(draft, p, man, errs, ok)
    call record_capability_hits(errs)
    call assert_finding(label, rule, code, object, field, errs, ok)
  end subroutine expect_rule

  ! Assert that `draft` runs the whole pipeline. Used by the two inverse rules:
  ! V15, where the counter-example is a pipeline that rejects an authored zero,
  ! and N1, where it is a pipeline that fails to canonicalise.
  subroutine expect_pass(label, draft)
    character(len=*), intent(in) :: label
    type(problem_state_t), intent(in) :: draft
    type(problem_state_t), allocatable :: p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok
    integer :: i
    call run(draft, p, man, errs, ok)
    call check(label, ok)
    if (ok) return
    do i = 1, errs%count()
      write (output_unit, '(a)') '        finding: '//errs%render(i)
    end do
  end subroutine expect_pass

  ! P0 is the only rule whose input is an argument of prepare_problem rather than
  ! a component of the draft, so it needs its own runner.
  subroutine expect_profile_rejected(label, draft)
    character(len=*), intent(in) :: label
    type(problem_state_t), intent(in) :: draft
    type(problem_state_t), allocatable :: p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    call prepare_problem(draft, 'static-q4-si/99', p, man, errs)
    call check(label//' -- the run fails', errs%any() .and. .not. allocated(p))
    call check(label//' -- rule P0 fired', has_rule(errs, 'P0'))
  end subroutine expect_profile_rejected

  subroutine expect_rule_counts(label, rule, code, object, field, draft, declared)
    character(len=*), intent(in) :: label, rule, code, object, field
    type(problem_state_t), intent(inout) :: draft
    type(declared_counts_t), intent(in) :: declared
    type(problem_state_t), allocatable :: p
    type(problem_errors_t) :: errs
    type(manifest_t), allocatable :: man
    logical :: ok
    call run_counts(draft, declared, p, man, errs, ok)
    call record_capability_hits(errs)
    call assert_finding(label, rule, code, object, field, errs, ok)
  end subroutine expect_rule_counts

  subroutine assert_finding(label, rule, code, object, field, errs, ok)
    character(len=*), intent(in) :: label, rule, code, object, field
    type(problem_errors_t), intent(in) :: errs
    logical, intent(in) :: ok
    type(problem_error_t) :: e
    logical :: found
    integer :: i

    call check(label//' -- the run fails', .not. ok)

    found = .false.
    do i = 1, errs%count()
      call errs%get(i, e, found)
      if (.not. found) cycle
      if (opt_value_or(e%rule_id, '') == rule) exit
      found = .false.
    end do

    call check(label//' -- rule '//rule//' fired', found)
    if (.not. found) then
      write (output_unit, '(a)') '        rules that did fire: '//rules_of(errs)
      ! Keep the check count stable whether or not the rule fired.
      call check(label//' -- code is '//code, .false.)
      call check(label//' -- object path is "'//object//'"', .false.)
      call check(label//' -- field is "'//field//'"', .false.)
      return
    end if

    call check(label//' -- code is '//code, opt_value_or(e%code, '') == code)
    call check(label//' -- object path is "'//object//'"', &
               opt_value_or(e%object_path, '') == object)
    call check(label//' -- field is "'//field//'"', &
               opt_value_or(e%field, '') == field)
    if (opt_value_or(e%code, '') /= code .or. &
        opt_value_or(e%object_path, '') /= object .or. &
        opt_value_or(e%field, '') /= field) then
      write (output_unit, '(a)') '        got: code='//opt_value_or(e%code, '<unset>')// &
        ' object="'//opt_value_or(e%object_path, '<unset>')// &
        '" field="'//opt_value_or(e%field, '<unset>')//'"'
    end if
  end subroutine assert_finding

  ! ==========================================================================
  ! mechanical capability-row coverage
  ! ==========================================================================

  ! Mark every capability row that this run's findings triggered.
  !
  ! The finding-to-row binding lives in yl_problem_pipeline, not here. Binding a
  ! finding to a row means knowing how the gate spells that row's object path,
  ! and the gate chooses that spelling in that module; a second copy of the
  ! knowledge here would be free to drift from it. So this walks the rows and
  ! asks the module, once per row per case.
  !
  ! What stays local is the ACCUMULATION. cap_hit is a per-row flag array updated
  ! from each case's OWN findings, so the union is built without any accumulator
  ! outliving a case. The alternative -- one accumulator never cleared, shared by
  ! every case -- would let one case's findings satisfy another case's assertion,
  ! which is the exact class of defect this matrix exists to remove.
  subroutine record_capability_hits(errs)
    type(problem_errors_t), intent(in) :: errs
    integer :: k
    do k = 1, capability_row_count()
      if (capability_row_exercised(errs, k)) cap_hit(k) = .true.
    end do
  end subroutine record_capability_hits

  ! The PRECONDITION of that binding, checked rather than assumed. A finding is
  ! bound by rule id, object path and field with subscripts erased, which
  ! identifies a row only while those triples stay pairwise distinct. If two rows
  ! ever collapsed to one triple, a single counter-example would mark both and
  ! the coverage number would read HIGH -- green, and wrong. That is this task's
  ! own failure mode aimed at the guard itself, so it gets an assertion.
  !
  ! This reads the declared table and binds no finding, so it is not a second
  ! matcher; it states the property the real matcher depends on.
  subroutine check_capability_binding_is_unique()
    type(capability_item_t) :: a, b
    logical :: ga, gb
    integer :: i, j, clashes

    clashes = 0
    do i = 1, capability_row_count()
      call capability_row(i, a, ga)
      if (.not. ga) cycle
      do j = i + 1, capability_row_count()
        call capability_row(j, b, gb)
        if (.not. gb) cycle
        if (trim(a%rule_id) /= trim(b%rule_id)) cycle
        if (desubscript(trim(a%object_path)) /= desubscript(trim(b%object_path))) cycle
        if (trim(a%field) /= trim(b%field)) cycle
        clashes = clashes + 1
        write (output_unit, '(a)') '        AMBIGUOUS: rows '//trim(a%item)//' and '// &
          trim(b%item)//' share ('//trim(a%rule_id)//' '//trim(a%object_path)// &
          '.'//trim(a%field)//')'
      end do
    end do
    call check('P-cov the row binding is unambiguous (rule, path, field pairwise distinct)', &
               clashes == 0)
  end subroutine check_capability_binding_is_unique

  function itoa(v) result(t)
    integer, intent(in) :: v
    character(len=:), allocatable :: t
    character(len=12) :: buf
    write (buf, '(i0)') v
    t = trim(buf)
  end function itoa

  ! Erase '[...]' subscripts. Used ONLY by the precondition check above, to
  ! compare two DECLARED ROWS with each other. No finding passes through it.
  function desubscript(path) result(bare)
    character(len=*), intent(in) :: path
    character(len=:), allocatable :: bare
    integer :: i
    logical :: inside
    bare = ''
    inside = .false.
    do i = 1, len(path)
      if (path(i:i) == '[') then
        inside = .true.
      else if (path(i:i) == ']') then
        inside = .false.
      else if (.not. inside) then
        bare = bare//path(i:i)
      end if
    end do
  end function desubscript

  ! Fail the suite when any declared capability row was never triggered. The
  ! evidence carries covered-against-declared, not a check total: a check total
  ! is satisfied by any fifteen assertions, whereas this says which rows of the
  ! table this build's gate was actually shown to enforce.
  subroutine check_capability_coverage()
    integer :: k, n_cov, n_dec
    character(len=32) :: a, b

    n_dec = capability_row_count()
    n_cov = count(cap_hit)
    write (a, '(i0)') n_cov
    write (b, '(i0)') n_dec
    write (output_unit, '(a)') '  capability rows covered: '//trim(a)//'/'//trim(b)
    ! Name the row, do not merely say coverage is incomplete: a suite that fails
    ! with "element.fields has no counter-example" is actionable. The identity is
    ! capability_row_id, the module's own stable name for the row.
    do k = 1, n_dec
      if (cap_hit(k)) cycle
      write (output_unit, '(a)') '        NEVER TRIGGERED: row '//itoa(k)//' '// &
        capability_row_id(k)
    end do
    call check('P-cov every declared capability row has a counter-example', n_cov == n_dec)
  end subroutine check_capability_coverage

  ! ==========================================================================
  ! finding-list helpers
  ! ==========================================================================

  logical function has_rule(errs, rule) result(res)
    type(problem_errors_t), intent(in) :: errs
    character(len=*), intent(in) :: rule
    type(problem_error_t) :: e
    logical :: found
    integer :: i
    res = .false.
    do i = 1, errs%count()
      call errs%get(i, e, found)
      if (found .and. opt_value_or(e%rule_id, '') == rule) then
        res = .true.
        return
      end if
    end do
  end function has_rule

  logical function has_stage(errs, stage) result(res)
    type(problem_errors_t), intent(in) :: errs
    character(len=*), intent(in) :: stage
    type(problem_error_t) :: e
    logical :: found
    integer :: i
    res = .false.
    do i = 1, errs%count()
      call errs%get(i, e, found)
      if (found .and. opt_value_or(e%stage, '') == stage) then
        res = .true.
        return
      end if
    end do
  end function has_stage

  function first_rule(errs) result(rule)
    type(problem_errors_t), intent(in) :: errs
    character(len=:), allocatable :: rule
    type(problem_error_t) :: e
    logical :: found
    rule = '<none>'
    if (errs%count() < 1) return
    call errs%get(1, e, found)
    if (found) rule = opt_value_or(e%rule_id, '<unset>')//'/'// &
                      opt_value_or(e%code, '<unset>')//'/'// &
                      opt_value_or(e%object_path, '<unset>')
  end function first_rule

  ! The stage of the first finding carrying `rule`. A rule that fires in the
  ! wrong stage has bound to a different defect than the one under test.
  function stage_of(errs, rule) result(text)
    type(problem_errors_t), intent(in) :: errs
    character(len=*), intent(in) :: rule
    character(len=:), allocatable :: text
    type(problem_error_t) :: e
    logical :: found
    integer :: i
    text = '<none>'
    do i = 1, errs%count()
      call errs%get(i, e, found)
      if (.not. found) cycle
      if (opt_value_or(e%rule_id, '') /= rule) cycle
      text = opt_value_or(e%stage, '<unset>')
      return
    end do
  end function stage_of

  ! The `actual` text of the first finding carrying `rule`. N5 uses it to tell
  ! "reported as unset" from "reported as a zero-length collection".
  function first_actual(errs, rule) result(text)
    type(problem_errors_t), intent(in) :: errs
    character(len=*), intent(in) :: rule
    character(len=:), allocatable :: text
    type(problem_error_t) :: e
    logical :: found
    integer :: i
    text = '<none>'
    do i = 1, errs%count()
      call errs%get(i, e, found)
      if (.not. found) cycle
      if (opt_value_or(e%rule_id, '') /= rule) cycle
      text = opt_value_or(e%actual, '<unset>')
      return
    end do
  end function first_actual

  function rules_of(errs) result(text)
    type(problem_errors_t), intent(in) :: errs
    character(len=:), allocatable :: text
    type(problem_error_t) :: e
    logical :: found
    integer :: i
    text = ''
    do i = 1, errs%count()
      call errs%get(i, e, found)
      if (.not. found) cycle
      if (len(text) > 0) text = text//' '
      text = text//opt_value_or(e%rule_id, '?')//'('//opt_value_or(e%code, '?')//' '// &
             opt_value_or(e%object_path, '')//'.'//opt_value_or(e%field, '')//')'
    end do
    if (len(text) == 0) text = '<none>'
  end function rules_of

  function txt(s) result(t)
    character(len=:), allocatable, intent(in) :: s
    character(len=:), allocatable :: t
    if (allocated(s)) then
      t = s
    else
      t = ''
    end if
  end function txt

  ! ==========================================================================
  ! draft identity, for T01
  ! ==========================================================================

  ! Component-by-component identity of two drafts: every allocation status, every
  ! array extent, every array element and every opt_* presence flag AND payload.
  ! opt_equal compares the flag first and the payload as a bit pattern, so an
  ! optional that was silently defaulted, cleared or overwritten is caught.
  logical function same_draft(a, b) result(res)
    type(problem_state_t), intent(in) :: a, b
    integer :: i, j

    res = .false.

    if (.not. opt_equal(a%case%name, b%case%name)) return
    if (.not. opt_equal(a%case%units, b%case%units)) return
    if (.not. opt_equal(a%mesh%dimension, b%mesh%dimension)) return

    if (allocated(a%mesh%nodes) .neqv. allocated(b%mesh%nodes)) return
    if (allocated(a%mesh%nodes)) then
      if (size(a%mesh%nodes) /= size(b%mesh%nodes)) return
      do i = 1, size(a%mesh%nodes)
        if (.not. opt_equal(a%mesh%nodes(i)%id, b%mesh%nodes(i)%id)) return
        if (.not. same_real_list(a%mesh%nodes(i)%xyz, b%mesh%nodes(i)%xyz)) return
      end do
    end if

    if (allocated(a%mesh%elements) .neqv. allocated(b%mesh%elements)) return
    if (allocated(a%mesh%elements)) then
      if (size(a%mesh%elements) /= size(b%mesh%elements)) return
      do i = 1, size(a%mesh%elements)
        if (.not. opt_equal(a%mesh%elements(i)%id, b%mesh%elements(i)%id)) return
        if (.not. opt_equal(a%mesh%elements(i)%kind, b%mesh%elements(i)%kind)) return
        if (.not. opt_equal(a%mesh%elements(i)%material, b%mesh%elements(i)%material)) return
        if (.not. opt_equal(a%mesh%elements(i)%elset, b%mesh%elements(i)%elset)) return
        if (.not. same_int_list(a%mesh%elements(i)%nodes, b%mesh%elements(i)%nodes)) return
      end do
    end if

    if (allocated(a%mesh%elsets) .neqv. allocated(b%mesh%elsets)) return
    if (allocated(a%mesh%elsets)) then
      if (size(a%mesh%elsets) /= size(b%mesh%elsets)) return
      do i = 1, size(a%mesh%elsets)
        if (.not. same_int_list(a%mesh%elsets(i)%elements, b%mesh%elsets(i)%elements)) return
      end do
    end if

    if (allocated(a%mesh%nsets) .neqv. allocated(b%mesh%nsets)) return
    if (allocated(a%mesh%nsets)) then
      if (size(a%mesh%nsets) /= size(b%mesh%nsets)) return
      do i = 1, size(a%mesh%nsets)
        if (.not. same_int_list(a%mesh%nsets(i)%nodes, b%mesh%nsets(i)%nodes)) return
      end do
    end if

    if (allocated(a%materials) .neqv. allocated(b%materials)) return
    if (allocated(a%materials)) then
      if (size(a%materials) /= size(b%materials)) return
      do i = 1, size(a%materials)
        if (.not. opt_equal(a%materials(i)%id, b%materials(i)%id)) return
        if (.not. opt_equal(a%materials(i)%name, b%materials(i)%name)) return
        if (.not. opt_equal(a%materials(i)%kind, b%materials(i)%kind)) return
        if (.not. opt_equal(a%materials(i)%phase, b%materials(i)%phase)) return
        if (.not. opt_equal(a%materials(i)%model, b%materials(i)%model)) return
        if (.not. opt_equal(a%materials(i)%E, b%materials(i)%E)) return
        if (.not. opt_equal(a%materials(i)%nu, b%materials(i)%nu)) return
        if (.not. opt_equal(a%materials(i)%density, b%materials(i)%density)) return
        if (.not. opt_equal(a%materials(i)%thermal_expansion, &
                            b%materials(i)%thermal_expansion)) return
        if (.not. opt_equal(a%materials(i)%solid_ratio, b%materials(i)%solid_ratio)) return
        if (.not. opt_equal(a%materials(i)%creep_model, b%materials(i)%creep_model)) return
        if (.not. opt_equal(a%materials(i)%liquefaction, b%materials(i)%liquefaction)) return
        if (.not. opt_equal(a%materials(i)%wetting_kind, b%materials(i)%wetting_kind)) return
      end do
    end if

    if (allocated(a%sections) .neqv. allocated(b%sections)) return
    if (allocated(a%sections)) then
      if (size(a%sections) /= size(b%sections)) return
      do i = 1, size(a%sections)
        if (.not. opt_equal(a%sections(i)%name, b%sections(i)%name)) return
        if (.not. opt_equal(a%sections(i)%element, b%sections(i)%element)) return
        if (.not. opt_equal(a%sections(i)%element_kind, b%sections(i)%element_kind)) return
        if (.not. opt_equal(a%sections(i)%class, b%sections(i)%class)) return
        if (.not. opt_equal(a%sections(i)%fields, b%sections(i)%fields)) return
        if (.not. opt_equal(a%sections(i)%formulation, b%sections(i)%formulation)) return
        if (.not. opt_equal(a%sections(i)%special, b%sections(i)%special)) return
        if (.not. opt_equal(a%sections(i)%material, b%sections(i)%material)) return
        if (.not. opt_equal(a%sections(i)%material_header, b%sections(i)%material_header)) return
        if (.not. opt_equal(a%sections(i)%algorithm, b%sections(i)%algorithm)) return
        if (.not. opt_equal(a%sections(i)%stiffness_kind, b%sections(i)%stiffness_kind)) return
        if (.not. opt_equal(a%sections(i)%stress_recovery, b%sections(i)%stress_recovery)) return
        if (.not. opt_equal(a%sections(i)%layer, b%sections(i)%layer)) return
        if (.not. opt_equal(a%sections(i)%liquefaction, b%sections(i)%liquefaction)) return
        if (.not. opt_equal(a%sections(i)%uplift, b%sections(i)%uplift)) return
        if (.not. opt_equal(a%sections(i)%local_axes, b%sections(i)%local_axes)) return
        if (.not. opt_equal(a%sections(i)%thickness, b%sections(i)%thickness)) return
      end do
    end if

    if (allocated(a%amplitudes) .neqv. allocated(b%amplitudes)) return
    if (allocated(a%amplitudes)) then
      if (size(a%amplitudes) /= size(b%amplitudes)) return
      do i = 1, size(a%amplitudes)
        if (.not. opt_equal(a%amplitudes(i)%name, b%amplitudes(i)%name)) return
        if (.not. opt_equal(a%amplitudes(i)%type, b%amplitudes(i)%type)) return
        if (allocated(a%amplitudes(i)%points) .neqv. allocated(b%amplitudes(i)%points)) return
        if (allocated(a%amplitudes(i)%points)) then
          if (size(a%amplitudes(i)%points) /= size(b%amplitudes(i)%points)) return
          do j = 1, size(a%amplitudes(i)%points)
            if (.not. opt_equal(a%amplitudes(i)%points(j)%time, &
                                b%amplitudes(i)%points(j)%time)) return
            if (.not. opt_equal(a%amplitudes(i)%points(j)%value, &
                                b%amplitudes(i)%points(j)%value)) return
          end do
        end if
      end do
    end if

    if (.not. opt_equal(a%interactions%absorbing%type, b%interactions%absorbing%type)) return

    if (.not. opt_equal(a%solver%linear, b%solver%linear)) return
    if (.not. opt_equal(a%solver%symmetric, b%solver%symmetric)) return
    if (.not. opt_equal(a%solver%profile%singularity_check, &
                        b%solver%profile%singularity_check)) return
    if (.not. opt_equal(a%solver%profile%condition_check, &
                        b%solver%profile%condition_check)) return
    if (.not. opt_equal(a%solver%profile%positive_definite_check, &
                        b%solver%profile%positive_definite_check)) return
    if (.not. opt_equal(a%solver%profile%pivot_file, b%solver%profile%pivot_file)) return

    if (allocated(a%steps) .neqv. allocated(b%steps)) return
    if (allocated(a%steps)) then
      if (size(a%steps) /= size(b%steps)) return
      do i = 1, size(a%steps)
        if (.not. same_step(a%steps(i), b%steps(i))) return
      end do
    end if

    res = .true.
  end function same_draft

  logical function same_step(a, b) result(res)
    type(step_t), intent(in) :: a, b
    integer :: j
    res = .false.
    if (.not. opt_equal(a%procedure, b%procedure)) return
    if (.not. opt_equal(a%load_mode, b%load_mode)) return

    if (.not. opt_equal(a%controls%nonlinear_type, b%controls%nonlinear_type)) return
    if (.not. opt_equal(a%controls%increments, b%controls%increments)) return
    if (.not. opt_equal(a%controls%max_iterations, b%controls%max_iterations)) return
    if (.not. opt_equal(a%controls%steps, b%controls%steps)) return
    if (.not. opt_equal(a%controls%step_increment, b%controls%step_increment)) return
    if (.not. opt_equal(a%controls%restart_frequency, b%controls%restart_frequency)) return
    if (.not. opt_equal(a%controls%time_increment, b%controls%time_increment)) return
    if (.not. opt_equal(a%controls%tolerance_force, b%controls%tolerance_force)) return
    if (.not. same_real_list(a%controls%tolerance_dof, b%controls%tolerance_dof)) return

    if (allocated(a%boundary) .neqv. allocated(b%boundary)) return
    if (allocated(a%boundary)) then
      if (size(a%boundary) /= size(b%boundary)) return
      do j = 1, size(a%boundary)
        if (.not. opt_equal(a%boundary(j)%name, b%boundary(j)%name)) return
        if (.not. opt_equal(a%boundary(j)%nset, b%boundary(j)%nset)) return
        if (.not. opt_equal(a%boundary(j)%dof, b%boundary(j)%dof)) return
        if (.not. opt_equal(a%boundary(j)%value, b%boundary(j)%value)) return
        if (.not. opt_equal(a%boundary(j)%amplitude, b%boundary(j)%amplitude)) return
        if (.not. opt_equal(a%boundary(j)%record_reaction, b%boundary(j)%record_reaction)) return
      end do
    end if

    if (allocated(a%activation) .neqv. allocated(b%activation)) return
    if (allocated(a%activation)) then
      if (size(a%activation) /= size(b%activation)) return
      do j = 1, size(a%activation)
        if (.not. opt_equal(a%activation(j)%material, b%activation(j)%material)) return
        if (.not. opt_equal(a%activation(j)%active, b%activation(j)%active)) return
      end do
    end if

    if (.not. opt_equal(a%load%gravity%enabled, b%load%gravity%enabled)) return
    if (.not. opt_equal(a%load%gravity%magnitude, b%load%gravity%magnitude)) return
    if (.not. same_real_list(a%load%gravity%direction, b%load%gravity%direction)) return
    if (.not. same_int_list(a%load%gravity%amplitude, b%load%gravity%amplitude)) return

    if (.not. opt_equal(a%output%format, b%output%format)) return
    if (.not. same_field(a%output%field, b%output%field)) return
    if (.not. opt_equal(a%output%frequency%nodes, b%output%frequency%nodes)) return
    if (.not. opt_equal(a%output%frequency%fields, b%output%frequency%fields)) return
    if (.not. same_int_list(a%output%stress_averaging, b%output%stress_averaging)) return

    res = .true.
  end function same_step

  logical function same_field(a, b) result(res)
    type(output_field_t), intent(in) :: a, b
    res = .false.
    if (.not. opt_equal(a%u, b%u)) return
    if (.not. opt_equal(a%v, b%v)) return
    if (.not. opt_equal(a%a, b%a)) return
    if (.not. opt_equal(a%s, b%s)) return
    if (.not. opt_equal(a%ms, b%ms)) return
    if (.not. opt_equal(a%f, b%f)) return
    if (.not. opt_equal(a%rot, b%rot)) return
    if (.not. opt_equal(a%T, b%T)) return
    if (.not. opt_equal(a%P, b%P)) return
    if (.not. opt_equal(a%Pv, b%Pv)) return
    if (.not. opt_equal(a%ep, b%ep)) return
    if (.not. opt_equal(a%Y, b%Y)) return
    if (.not. opt_equal(a%FC, b%FC)) return
    if (.not. opt_equal(a%Ns, b%Ns)) return
    if (.not. opt_equal(a%Ss, b%Ss)) return
    if (.not. opt_equal(a%Mxy, b%Mxy)) return
    if (.not. opt_equal(a%bem, b%bem)) return
    if (.not. opt_equal(a%wh, b%wh)) return
    if (.not. opt_equal(a%wv, b%wv)) return
    if (.not. opt_equal(a%bcs, b%bcs)) return
    res = .true.
  end function same_field

  ! Allocation status, extent and contents. Reals are compared as bit patterns so
  ! that the comparison is total and cannot trap under -fpe0.
  logical function same_real_list(a, b) result(res)
    real(real64), allocatable, intent(in) :: a(:), b(:)
    integer :: i
    res = .false.
    if (allocated(a) .neqv. allocated(b)) return
    if (allocated(a)) then
      if (size(a) /= size(b)) return
      do i = 1, size(a)
        if (transfer(a(i), 0_int64) /= transfer(b(i), 0_int64)) return
      end do
    end if
    res = .true.
  end function same_real_list

  logical function same_int_list(a, b) result(res)
    integer(int32), allocatable, intent(in) :: a(:), b(:)
    res = .false.
    if (allocated(a) .neqv. allocated(b)) return
    if (allocated(a)) then
      if (size(a) /= size(b)) return
      if (size(a) > 0) then
        if (any(a /= b)) return
      end if
    end if
    res = .true.
  end function same_int_list

  ! ==========================================================================
  ! mutation helpers
  ! ==========================================================================

  ! Widen a draft to three spatial dimensions consistently: the declared
  ! dimension, every node's coordinate vector and the gravity direction move
  ! together, because they are the three places the count rules compare against
  ! mesh.dimension. The added component is zero, an authored value, not padding.
  subroutine make_three_dimensional(d)
    type(problem_state_t), intent(inout) :: d
    real(real64) :: xy(2)
    integer :: i

    call opt_set(d%mesh%dimension, 3_int32)
    do i = 1, size(d%mesh%nodes)
      xy = d%mesh%nodes(i)%xyz(1:2)
      deallocate (d%mesh%nodes(i)%xyz)
      allocate (d%mesh%nodes(i)%xyz(3))
      d%mesh%nodes(i)%xyz = [xy(1), xy(2), 0.0_real64]
    end do
    deallocate (d%steps(1)%load%gravity%direction)
    allocate (d%steps(1)%load%gravity%direction(3))
    d%steps(1)%load%gravity%direction = [0.0_real64, -1.0_real64, 0.0_real64]
  end subroutine make_three_dimensional

  ! Two element sets for one section, leaving element 1 in set 1 only, so the
  ! defect is the arity (N4) and not a double membership (N6).
  subroutine grow_elsets_to_two(d)
    type(problem_state_t), intent(inout) :: d
    type(elset_t), allocatable :: es(:)
    allocate (es(2))
    allocate (es(1)%elements(1))
    es(1)%elements = [1_int32]
    allocate (es(2)%elements(0))
    call move_alloc(es, d%mesh%elsets)
  end subroutine grow_elsets_to_two

  ! Resize the two per-section vectors so that a draft grown to `n` sections is
  ! not ALSO defective under V11 and V12. Each counter-example must carry one
  ! defect, not three.
  subroutine regrow_per_section(d, n)
    type(problem_state_t), intent(inout) :: d
    integer, intent(in) :: n
    deallocate (d%steps(1)%load%gravity%amplitude)
    allocate (d%steps(1)%load%gravity%amplitude(n))
    d%steps(1)%load%gravity%amplitude = 1_int32
    deallocate (d%steps(1)%output%stress_averaging)
    allocate (d%steps(1)%output%stress_averaging(n))
    d%steps(1)%output%stress_averaging = 2_int32
  end subroutine regrow_per_section

  ! ==========================================================================
  ! the good draft
  ! ==========================================================================

  ! A draft structurally equivalent to cases/golden/static_2d/cooks_membrane.
  ! Every value that a rule reads carries the deck's value; only the mesh is
  ! scaled down to one Q4 on four nodes. Built through the real builder, so the
  ! three-state contract of every collection is the builder's, not a hand-rolled
  ! allocation in this file.
  subroutine good_draft(draft)
    type(problem_state_t), allocatable, intent(out) :: draft

    type(problem_builder_t) :: b
    type(step_builder_t) :: sb
    type(amplitude_builder_t) :: ab
    type(problem_errors_t) :: errors
    type(source_location_t) :: loc
    type(case_t) :: kase
    type(node_t) :: nd
    type(element_t) :: el
    type(elset_t) :: es
    type(nset_t) :: ns
    type(material_t) :: mt
    type(section_t) :: sc
    type(amplitude_t) :: am
    type(amplitude_point_t) :: pt
    type(interactions_t) :: it
    type(solver_t) :: sv
    type(controls_t) :: ct
    type(load_t) :: ld
    type(output_t) :: ou
    type(boundary_t) :: bd
    type(activation_t) :: ac
    type(step_t) :: st
    integer :: k
    logical :: ok
    real(real64) :: xs(4), ys(4)

    call builder_begin(b)

    call opt_set(kase%name, 'cooks_membrane')
    call builder_set_case(b, kase, loc, errors)
    call builder_set_mesh_dimension(b, 2_int32, loc, errors)

    ! The four corners of the Cook membrane outline, in counter-clockwise order.
    xs = [0.0_real64, 48.0_real64, 48.0_real64, 0.0_real64]
    ys = [0.0_real64, 44.0_real64, 60.0_real64, 44.0_real64]
    do k = 1, 4
      call opt_set(nd%id, int(k, int32))
      if (allocated(nd%xyz)) deallocate (nd%xyz)
      allocate (nd%xyz(2))
      nd%xyz = [xs(k), ys(k)]
      call builder_add_node(b, nd, loc, errors)
    end do

    ! kind, material and elset are left UNSET: they are what finalize derives.
    call opt_set(el%id, 1_int32)
    allocate (el%nodes(4))
    el%nodes = [1_int32, 2_int32, 3_int32, 4_int32]
    call builder_add_element(b, el, loc, errors)

    allocate (es%elements(1))
    es%elements = [1_int32]
    call builder_add_elset(b, es, loc, errors)

    ! Two prescribed sets over the same nodes, as in the deck's .pre.
    do k = 1, 2
      if (allocated(ns%nodes)) deallocate (ns%nodes)
      allocate (ns%nodes(2))
      ns%nodes = [1_int32, 4_int32]
      call builder_add_nset(b, ns, loc, errors)
    end do

    ! .mat: ELASTIC_ISOTROPIC, rho 2400, E 2.5e10, nu 0.2.
    call opt_set(mt%id, 1_int32)
    call opt_set(mt%name, 'concrete')
    call opt_set(mt%kind, 'MECHANICAL')
    call opt_set(mt%phase, 'SOLID')
    call opt_set(mt%model, 'ELASTIC_ISOTROPIC')
    call opt_set(mt%E, 2.5e10_real64)
    call opt_set(mt%nu, 0.2_real64)
    call opt_set(mt%density, 2.4e3_real64)
    call opt_set(mt%thermal_expansion, 1.0e-5_real64)
    call opt_set(mt%solid_ratio, 1.0_real64)
    call opt_set(mt%creep_model, 0_int32)
    call opt_set(mt%liquefaction, 0_int32)
    call opt_set(mt%wetting_kind, 0_int32)
    call builder_add_material(b, mt, loc, errors)

    ! .glb group header: Q4 Default 5 CO 1 U ST PE 256 1 0 1 1 1 0.0 0 0 0.
    call opt_set(sc%name, 'g1')
    call opt_set(sc%element, 'Q4')
    call opt_set(sc%element_kind, 5_int32)
    call opt_set(sc%class, 'CO')
    call opt_set(sc%fields, 'U')
    call opt_set(sc%formulation, 'PE')
    call opt_set(sc%special, 'ST')
    call opt_set(sc%material, 1_int32)
    call opt_set(sc%material_header, 1_int32)
    call opt_set(sc%algorithm, 0_int32)
    call opt_set(sc%stiffness_kind, 1_int32)
    call opt_set(sc%stress_recovery, 1_int32)
    call opt_set(sc%layer, 1_int32)
    call opt_set(sc%liquefaction, 0_int32)
    call opt_set(sc%uplift, 0_int32)
    call opt_set(sc%local_axes, 0.0_real64)
    call builder_add_section(b, sc, loc, errors)

    ! .loa: one LINEAR curve, points (0, 1) and (1, 1).
    call builder_amplitude_begin(ab)
    call builder_amplitude_set_name(b, ab, 'a1', loc, errors)
    call builder_amplitude_set_type(b, ab, 'LINEAR', loc, errors)
    call opt_set(pt%time, 0.0_real64)
    call opt_set(pt%value, 1.0_real64)
    call builder_amplitude_add_point(b, ab, pt, loc, errors)
    call opt_set(pt%time, 1.0_real64)
    call opt_set(pt%value, 1.0_real64)
    call builder_amplitude_add_point(b, ab, pt, loc, errors)
    call builder_amplitude_finish(b, ab, am, loc, errors)
    call builder_add_amplitude(b, am, loc, errors)

    ! .glb: TYPE_SOLVER PROFILE, NONSY 0 (so the model is symmetric).
    call opt_set(sv%linear, 'PROFILE')
    call opt_set(sv%symmetric, .true.)
    call opt_set(sv%profile%singularity_check, 0_int32)
    call opt_set(sv%profile%condition_check, 0_int32)
    call opt_set(sv%profile%positive_definite_check, 0_int32)
    call opt_set(sv%profile%pivot_file, 0_int32)
    call builder_set_solver(b, sv, loc, errors)

    call opt_set(it%absorbing%type, 'FIX')
    call builder_set_interactions(b, it, loc, errors)

    ! .glb TYPE_PROBLEM Q, TYPE_LOAD LOAD; .man nincs 1.
    call builder_step_begin(sb)
    call builder_step_set_procedure(b, sb, 'Q', loc, errors)
    call builder_step_set_load_mode(b, sb, 'LOAD', loc, errors)

    call opt_set(ct%nonlinear_type, 5_int32)
    call opt_set(ct%increments, 1_int32)
    call opt_set(ct%max_iterations, 1_int32)
    call opt_set(ct%steps, 1_int32)
    call opt_set(ct%step_increment, 1_int32)
    call opt_set(ct%restart_frequency, 0_int32)
    call opt_set(ct%time_increment, 1.0_real64)
    call opt_set(ct%tolerance_force, 1.0e-5_real64)
    allocate (ct%tolerance_dof(2))
    ct%tolerance_dof = [1.0e-5_real64, 1.0e-5_real64]
    call builder_step_set_controls(b, sb, ct, loc, errors)

    ! .loa body force: g 9.81, direction (0, -1), curve 1 for the one group.
    call opt_set(ld%gravity%enabled, 1_int32)
    call opt_set(ld%gravity%magnitude, 9.81_real64)
    allocate (ld%gravity%direction(2))
    ld%gravity%direction = [0.0_real64, -1.0_real64]
    allocate (ld%gravity%amplitude(1))
    ld%gravity%amplitude = [1_int32]
    call builder_step_set_load(b, sb, ld, loc, errors)

    ! .glb: outplot GIDR, gid_u = gid_s = 1, average_appear 2.
    call opt_set(ou%format, 'GIDR')
    call opt_set(ou%field%u, 1_int32)
    call opt_set(ou%field%v, 0_int32)
    call opt_set(ou%field%a, 0_int32)
    call opt_set(ou%field%s, 1_int32)
    call opt_set(ou%field%ms, 0_int32)
    call opt_set(ou%field%f, 0_int32)
    call opt_set(ou%field%rot, 0_int32)
    call opt_set(ou%field%T, 0_int32)
    call opt_set(ou%field%P, 0_int32)
    call opt_set(ou%field%Pv, 0_int32)
    call opt_set(ou%field%ep, 0_int32)
    call opt_set(ou%field%Y, 0_int32)
    call opt_set(ou%field%FC, 0_int32)
    call opt_set(ou%field%Ns, 0_int32)
    call opt_set(ou%field%Ss, 0_int32)
    call opt_set(ou%field%Mxy, 0_int32)
    call opt_set(ou%field%bem, 0_int32)
    call opt_set(ou%field%wh, 0_int32)
    call opt_set(ou%field%wv, 0_int32)
    call opt_set(ou%field%bcs, 0_int32)
    call opt_set(ou%frequency%nodes, 1_int32)
    call opt_set(ou%frequency%fields, 1_int32)
    allocate (ou%stress_averaging(1))
    ou%stress_averaging = [2_int32]
    call builder_step_set_output(b, sb, ou, loc, errors)

    ! .pre: set 1 fixes ux, set 2 fixes uy, both on the left edge.
    do k = 1, 2
      call opt_set(bd%name, int(k, int32))
      call opt_set(bd%nset, int(k, int32))
      call opt_set(bd%dof, int(k, int32))
      call opt_set(bd%value, 0.0_real64)
      call opt_set(bd%amplitude, 1_int32)
      call opt_set(bd%record_reaction, 0_int32)
      call builder_step_add_boundary(b, sb, bd, loc, errors)
    end do

    ! .glb APPEAR_PROCESS 1, MATNO_PROCESS 1.
    call opt_set(ac%material, 1_int32)
    call opt_set(ac%active, 1_int32)
    call builder_step_add_activation(b, sb, ac, loc, errors)

    call builder_step_finish(b, sb, st, loc, errors)
    call builder_add_step(b, st, loc, errors)

    call builder_finish(b, draft, errors, ok)
    if (.not. ok) then
      write (output_unit, '(a)') 'FATAL: the good draft did not build'
      stop 1
    end if
  end subroutine good_draft

  ! The deck's redundant count declarations, all agreeing with the good draft.
  ! The eight checkable rows are declared, so the positive run produces the eight
  ! `check` manifest entries. The ten must-be-zero rows are declared as zero, the
  ! value the cooks deck actually carries for every load and thermal kind that is
  ! not gravity, so V22 is exercised on its passing side too.
  function good_counts() result(dc)
    type(declared_counts_t) :: dc
    call opt_set(dc%node_count, 4_int32)
    call opt_set(dc%element_count, 1_int32)
    call opt_set(dc%material_count, 1_int32)
    call opt_set(dc%section_count, 1_int32)
    call opt_set(dc%amplitude_count, 1_int32)
    call opt_set(dc%nset_count, 2_int32)
    allocate (dc%elset_size(1))
    dc%elset_size = [1_int32]
    allocate (dc%amplitude_points(1))
    dc%amplitude_points = [2_int32]
    call opt_set(dc%point_load_group_count, 0_int32)
    call opt_set(dc%edge_count, 0_int32)
    call opt_set(dc%edge_load_group_count, 0_int32)
    call opt_set(dc%edge_load_element_group_count, 0_int32)
    call opt_set(dc%beam_load_count, 0_int32)
    call opt_set(dc%plate_load_count, 0_int32)
    call opt_set(dc%temperature_surface_count, 0_int32)
    call opt_set(dc%temperature_edge_count, 0_int32)
    call opt_set(dc%temperature_element_group_count, 0_int32)
    call opt_set(dc%pipe_count, 0_int32)
  end function good_counts

  ! ==========================================================================
  ! harness
  ! ==========================================================================

  subroutine check(label, condition)
    character(len=*), intent(in) :: label
    logical, intent(in) :: condition
    n_check = n_check + 1
    if (condition) then
      write (output_unit, '(a)') '  ok   '//label
    else
      n_fail = n_fail + 1
      write (output_unit, '(a)') '  BAD  '//label
    end if
  end subroutine check

  subroutine summary()
    character(len=32) :: a, b
    write (a, '(i0)') n_check - n_fail
    write (b, '(i0)') n_check
    if (n_fail == 0) then
      write (output_unit, '(a)') 'PASS: '//trim(a)//'/'//trim(b)
    else
      write (output_unit, '(a)') 'FAIL: '//trim(a)//'/'//trim(b)
      stop 1
    end if
  end subroutine summary

end program yl_problem_pipeline_selftest
