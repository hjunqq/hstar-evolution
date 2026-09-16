! yl_authoring_keys -- the declared key table, and the contract validation that walks it.
!
! WHAT IT IS
!   One parameter array describing every key `docs/m5/authoring-contract.md` admits: its
!   path pattern, its type, whether the author MUST write it, and its allowed values when
!   the contract whitelists a set. Validation is then a walk over that table plus a walk
!   over the parsed store -- not a hand-written sequence of ifs, which is how a contract
!   and its checker drift apart.
!
! THE RULE THE `required` COLUMN ENCODES
!   The contract's operational test: a field may be optional only if it is NOT a physical
!   choice -- would changing its default change the result or its physical meaning? So
!   `material[].E` is required and `output.format` is required (it selects what the user
!   gets), while everything in the contract's default table never appears here at all,
!   because the author cannot write it.
!
!   Where it is ARGUABLE, the contract says prefer explicit. `section[].formulation` could
!   have defaulted to plane_strain -- there is exactly one on the whitelist -- and it is
!   required anyway, because plane strain vs plane stress is a modelling decision and
!   guessing it for the author is precisely what this input system exists to stop.
!
! WHAT A FAILURE LOOKS LIKE
!   A `problem_errors_t` finding, the same type the legacy adapter and the pipeline raise,
!   carrying `source = (file=case.toml, line=N)`, the key path, the value read and the
!   allowed set. Reusing that type rather than inventing an authoring-specific one is
!   deliberate: two error types would be two chances to disagree about what a verdict means.
!
! VERDICTS
!   INVALID_INPUT (exit 2): syntax already handled by the reader, plus unknown key, wrong
!     type, missing required key, dangling reference, duplicate name, wrong units/version.
!   UNSUPPORTED_CAPABILITY (exit 3): every key is well formed and every reference resolves,
!     but a value is outside the whitelist -- `element = "Q8"`.
!   The split matters to an operator: the first says "your file is wrong", the second says
!   "your file is fine and this build cannot do it".
module yl_authoring_keys

  use iso_fortran_env, only: int32, real64

  use yl_problem_errors, only: problem_errors_t, make_problem_error, make_source_location,   &
                               PE_INVALID_INPUT, PE_UNSUPPORTED, PE_MISSING_FIELD,           &
                               PE_DANGLING_REF, PE_DUPLICATE_REF,                            &
                               PE_EXIT_INPUT, PE_EXIT_UNSUPPORTED
  use yl_authoring_toml, only: toml_doc_t, TV_INT, TV_REAL, TV_STR, TV_BOOL, TOML_LEN_PATH

  implicit none
  private

  integer, parameter :: LEN_PAT = 48
  integer, parameter :: LEN_ALLOW = 120

  type :: key_t
    character(len=LEN_PAT) :: pattern = ''
    integer(int32) :: kind = 0_int32
    logical :: required = .false.
    !> `|`-separated whitelist, empty when the contract does not restrict the value.
    character(len=LEN_ALLOW) :: allowed = ''
  end type key_t

  ! The table. `[]` stands for any index. Order is the contract's order, so the two can be
  ! read side by side.
  type(key_t), parameter :: KEYS(*) = [                                                      &
    key_t('version',                       TV_INT,  .true.,  '1'),                           &
    key_t('case.name',                     TV_STR,  .true.,  ''),                            &
    key_t('case.units',                    TV_STR,  .true.,  'SI'),                          &
    key_t('case.description',              TV_STR,  .false., ''),                            &
    key_t('mesh.file',                     TV_STR,  .true.,  ''),                            &
    key_t('mesh.format',                   TV_STR,  .true.,  'hstar-legacy-cor-ele'),        &
    key_t('mesh.dimension',                TV_INT,  .true.,  '2'),                           &
    key_t('elset[].name',                  TV_STR,  .true.,  ''),                            &
    key_t('elset[].element_count',         TV_INT,  .true.,  ''),                            &
    key_t('nset[].name',                   TV_STR,  .true.,  ''),                            &
    key_t('nset[].nodes[]',                TV_INT,  .false., ''),                            &
    key_t('nset[].nodes.count',            TV_INT,  .true.,  ''),                            &
    key_t('material[].name',               TV_STR,  .true.,  ''),                            &
    key_t('material[].model',              TV_STR,  .true.,  'elastic_isotropic|classicalep'), &
    key_t('material[].density',            TV_REAL, .true.,  ''),                            &
    key_t('material[].E',                  TV_REAL, .true.,  ''),                            &
    key_t('material[].nu',                 TV_REAL, .true.,  ''),                            &
    ! A material property that differs between real decks (1.0e-5 on the static pair,
    ! 5.0e-6 on slope_srm). Unconsumed without a thermal step, but changing it changes what
    ! the material IS, so by the admission rule it cannot carry a default.
    key_t('material[].thermal_expansion',  TV_REAL, .true.,  ''),                            &
    ! The plasticity block: OPTIONAL as keys, because an elastic material has none of it,
    ! and REQUIRED-TOGETHER by model_requires below. Declaring them required here would
    ! demand a friction angle of every linear-elastic deck.
    key_t('material[].criterion',          TV_STR,  .false., 'mohr_coulomb'),                &
    key_t('material[].cohesion',           TV_REAL, .false., ''),                            &
    key_t('material[].hardening',          TV_REAL, .false., ''),                            &
    key_t('material[].friction_angle',     TV_REAL, .false., ''),                            &
    key_t('material[].dilation_angle',     TV_REAL, .false., ''),                            &
    key_t('section[].name',                TV_STR,  .true.,  ''),                            &
    key_t('section[].elset',               TV_STR,  .true.,  ''),                            &
    key_t('section[].element',             TV_STR,  .true.,  'Q4'),                          &
    key_t('section[].formulation',         TV_STR,  .true.,  'plane_strain'),                &
    key_t('section[].material',            TV_STR,  .true.,  ''),                            &
    key_t('amplitude[].name',              TV_STR,  .true.,  ''),                            &
    key_t('amplitude[].type',              TV_STR,  .true.,  'linear'),                      &
    key_t('amplitude[].points[][]',        TV_REAL, .false., ''),                            &
    key_t('amplitude[].points[].count',    TV_INT,  .false., ''),                            &
    key_t('amplitude[].points.count',      TV_INT,  .true.,  ''),                            &
    key_t('step[].name',                   TV_STR,  .true.,  ''),                            &
    key_t('step[].procedure',              TV_STR,  .true.,  'static'),                      &
    key_t('step[].controls.increments',    TV_INT,  .true.,  '1'),                           &
    ! How many load steps the analysis walks, and how far each advances the curve
    ! abscissa. Both were pinned in the default table while one step was the only shape
    ! this build admitted; a strength-reduction sweep is 100 steps of 0.01 and the values
    ! decide where on the reduction curve the analysis ends.
    key_t('step[].controls.substeps',      TV_INT,  .true.,  ''),                            &
    key_t('step[].controls.time_increment', TV_REAL, .true., ''),                            &
    key_t('step[].controls.max_iterations', TV_INT, .true.,  ''),                            &
    key_t('step[].controls.tolerance_force', TV_REAL, .true., ''),                           &
    key_t('step[].controls.tolerance_dof', TV_REAL, .true.,  ''),                            &
    ! WHEN the tangent is rebuilt. It was in the default table (pinned to legacy's
    ! type_nl=5) with the reason "the value does not reach the result" -- true for one
    ! linear-elastic iteration, FALSE the moment a material is non-linear. By the contract's
    ! own admission rule it therefore cannot be a default, so the author writes it.
    key_t('step[].controls.stiffness_update', TV_STR, .true., 'first_iteration|every_iteration'), &
    key_t('step[].boundary[].nset',        TV_STR,  .true.,  ''),                            &
    key_t('step[].boundary[].dof[]',       TV_INT,  .false., '1|2'),                         &
    key_t('step[].boundary[].dof.count',   TV_INT,  .true.,  ''),                            &
    key_t('step[].boundary[].value',       TV_REAL, .true.,  ''),                            &
    ! legacy `type_load`. 'strength_reduction' is MAT_DE: the named amplitude's current
    ! factor scales the cohesion and tand(friction)/tand(dilation) every step
    ! (Stiff.f90:5779), which is what walks the model to failure. It is a property of the
    ! STEP, not of any one load, which is why it left `[step.load]` when that became an
    ! array (2026-09-15, contract section 8.3).
    key_t('step[].load_mode',              TV_STR,  .true.,  'load|strength_reduction'),     &
    ! WHICH element sets are part of the model in this step. legacy calls it
    ! APPEAR_PROCESS and stores it as a (group, block) matrix read once from `.glb`; the
    ! author states it per step, by name, and the mapping layer builds the matrix.
    ! Required rather than defaulted to "everything": on a staged analysis "which parts
    ! exist yet" is the whole point of having more than one step, and on a single-step
    ! deck writing it costs one line and removes a default that would have to be
    ! un-defaulted the moment a second step appears.
    ! legacy `uinitial(iblks)`: this step starts from ZERO displacement rather than
    ! continuing from the previous step's. Fem.f90:1704-1708 zeroes result_zero and the
    ! two result buffers when it is set. It left the default table the moment a second
    ! step existed -- "does this step inherit what the last one did" is the central
    ! question of a staged analysis, and it cannot be guessed.
    key_t('step[].reset_state',            TV_BOOL, .true.,  ''),                            &
    key_t('step[].active_elsets[]',        TV_STR,  .false., ''),                            &
    key_t('step[].active_elsets.count',    TV_INT,  .true.,  ''),                            &
    key_t('step[].strength_reduction.amplitude', TV_STR, .false., ''),                       &
    ! Loads are an ARRAY of objects, because one step can carry several of the same kind:
    ! two element groups on different gravity histories, two faces at different water
    ! levels. legacy flattens all of that into parallel arrays indexed by group or by edge
    ! range; the author writes objects and the adapter does the flattening.
    key_t('step[].load[].type',            TV_STR,  .true.,  'gravity|pressure'),            &
    key_t('step[].load[].amplitude',       TV_STR,  .true.,  ''),                            &
    ! --- type = "gravity"
    key_t('step[].load[].magnitude',       TV_REAL, .false., ''),                            &
    key_t('step[].load[].direction[]',     TV_REAL, .false., ''),                            &
    key_t('step[].load[].direction.count', TV_INT,  .false., '2'),                           &
    key_t('step[].load[].apply_to',        TV_STR,  .false., ''),                            &
    ! --- type = "pressure"
    key_t('step[].load[].surface',         TV_STR,  .false., ''),                            &
    key_t('step[].load[].distribution.type', TV_STR, .false., 'linear_in_coordinate'),       &
    key_t('step[].load[].distribution.axis', TV_STR, .false., 'y'),                          &
    key_t('step[].load[].distribution.at[]', TV_REAL, .false., ''),                          &
    key_t('step[].load[].distribution.at.count', TV_INT, .false., ''),                       &
    key_t('step[].load[].distribution.value[]', TV_REAL, .false., ''),                       &
    key_t('step[].load[].distribution.value.count', TV_INT, .false., ''),                    &
    key_t('step[].load[].distribution.scale', TV_REAL, .false., ''),                         &
    ! A named face is an EXPLICIT edge table: every row is [n1, n2, element]. The element
    ! is written down because legacy writes it down too (Load.f90:383); looking it up from
    ! the node pair would be topology derivation in the adapter, and this build has twice
    ! paid for mirroring legacy's own derivations (R31, the jacob 1-ULP divergence).
    key_t('surface[].name',                TV_STR,  .true.,  ''),                            &
    key_t('surface[].kind',                TV_STR,  .true.,  'edge2'),                       &
    key_t('surface[].edges[][]',           TV_INT,  .false., ''),                            &
    key_t('surface[].edges[].count',       TV_INT,  .false., ''),                            &
    key_t('surface[].edges.count',         TV_INT,  .true.,  ''),                            &
    key_t('solver.linear',                 TV_STR,  .true.,  'profile'),                     &
    key_t('output.format',                 TV_STR,  .true.,  'gid'),                         &
    key_t('output.field[]',                TV_STR,  .false., 'u|s|ep|ms|f|y'),               &
    key_t('output.field.count',            TV_INT,  .true.,  ''),                            &
    key_t('output.stress_averaging',       TV_STR,  .true.,                                  &
          'none|smoothed|direct|smoothed_legacy|direct_legacy')]

  public :: authoring_validate, authoring_key_count, authoring_key_pattern

contains

  pure integer function authoring_key_count() result(n)
    n = size(KEYS)
  end function authoring_key_count

  pure function authoring_key_pattern(i) result(p)
    integer, intent(in) :: i
    character(len=LEN_PAT) :: p
    p = KEYS(i)%pattern
  end function authoring_key_pattern

  !> Validate `doc` against the contract. Every finding carries the line it came from.
  subroutine authoring_validate(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors

    integer(int32) :: i
    integer :: k
    character(len=TOML_LEN_PATH) :: np

    ! --- every key present was declared, and has the declared type -----------------
    do i = 1_int32, doc%n
      np = normalise(doc%entry(i)%path)
      k = slot(np)
      if (k == 0) then
        call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(i)%line,        &
                   trim(doc%entry(i)%path), 'unknown key; the authoring contract admits '//  &
                   'no such field', '', '')
        cycle
      end if
      if (doc%entry(i)%kind /= KEYS(k)%kind) then
        call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(i)%line,        &
                   trim(doc%entry(i)%path), 'wrong type', kind_name(doc%entry(i)%kind),      &
                   kind_name(KEYS(k)%kind))
        cycle
      end if
      if (len_trim(KEYS(k)%allowed) > 0) then
        call check_allowed(doc, i, KEYS(k), file, errors)
      end if
    end do

    ! --- every required key is present, per collection element ---------------------
    do k = 1, size(KEYS)
      if (.not. KEYS(k)%required) cycle
      call require_all(doc, KEYS(k)%pattern, file, errors)
    end do

    ! --- names unique, references resolve -----------------------------------------
    call unique_names(doc, 'elset', file, errors)
    call unique_names(doc, 'nset', file, errors)
    call unique_names(doc, 'material', file, errors)
    call unique_names(doc, 'section', file, errors)
    call unique_names(doc, 'amplitude', file, errors)
    call unique_names(doc, 'step', file, errors)
    call unique_names(doc, 'surface', file, errors)

    call resolve(doc, 'section', 'elset', 'elset', file, errors)
    call resolve(doc, 'section', 'material', 'material', file, errors)
    call resolve_nested(doc, 'step', 'boundary', 'nset', 'nset', file, errors)
    call resolve_nested(doc, 'step', 'load', 'surface', 'surface', file, errors)
    call resolve_active_elsets(doc, file, errors)
    call resolve_step_amplitude(doc, file, errors)
    call model_requires(doc, file, errors)
    call load_mode_requires(doc, file, errors)
    call load_type_requires(doc, file, errors)
    call check_loads(doc, file, errors)
    call check_surfaces(doc, file, errors)
    call check_amplitudes(doc, file, errors)

    ! --- at least one step --------------------------------------------------------
    ! "EXACTLY one" used to be here. It moved to the mapping layer on 2026-09-15: the
    ! contract can describe a sequence of steps (section 2.1 freezes legacy nblks =
    ! count(step)), and what this build can EXECUTE is a separate, narrower statement.
    ! Putting the execution limit where the mesh and the legacy globals are is the same
    ! rule that already sends the element-count refusal there.
    if (doc%count_of('step') < 1_int32) then
      call raise(errors, PE_MISSING_FIELD, PE_EXIT_INPUT, file, 0_int32, 'step',             &
                 'an analysis needs at least one [[step]]', '0', 'one or more')
    end if
  end subroutine authoring_validate

  !> Per-model fields are required TOGETHER with their model and forbidden without it.
  !>
  !> This is the first conditional requirement in the contract, and the material domain is
  !> where it had to appear: legacy reads a common solid record and then branches per
  !> constitutive model, so "required" stops being a property of the key and becomes a
  !> property of the (key, model) pair. Both directions are checked -- a missing one is a
  !> MISSING_FIELD, and a friction angle on an elastic material is an unknown-in-context
  !> key rather than something silently ignored.
  subroutine model_requires(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), parameter :: FIELDS(4) = [character(len=15) ::                          &
      'cohesion', 'hardening', 'friction_angle', 'dilation_angle']
    integer(int32) :: i, k, kc
    character(len=TOML_LEN_PATH) :: base
    logical :: plastic
    integer :: f

    do i = 1_int32, doc%count_of('material')
      base = 'material['//itoa(i)//']'
      k = doc%find(trim(base)//'.model')
      if (k == 0_int32) cycle                  ! a missing model is require_all's finding
      plastic = trim(doc%entry(k)%svalue) == 'classicalep'
      kc = doc%find(trim(base)//'.criterion')
      if (plastic .and. kc == 0_int32) then
        call raise(errors, PE_MISSING_FIELD, PE_EXIT_INPUT, file, doc%entry(k)%line,          &
                   trim(base)//'.criterion',                                                  &
                   'model "classicalep" needs a yield criterion', '', 'mohr_coulomb')
      end if
      if (.not. plastic .and. kc /= 0_int32) then
        call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(kc)%line,         &
                   trim(base)//'.criterion',                                                  &
                   'only a plasticity model takes a yield criterion',                         &
                   trim(doc%entry(k)%svalue), 'classicalep')
      end if
      do f = 1, size(FIELDS)
        k = doc%find(trim(base)//'.'//trim(FIELDS(f)))
        if (plastic .and. k == 0_int32) then
          call raise(errors, PE_MISSING_FIELD, PE_EXIT_INPUT, file, 0_int32,                  &
                     trim(base)//'.'//trim(FIELDS(f)),                                        &
                     'the mohr_coulomb criterion needs this parameter', '', 'a real number')
        else if (.not. plastic .and. k /= 0_int32) then
          call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(k)%line,        &
                     trim(base)//'.'//trim(FIELDS(f)),                                        &
                     'only a plasticity model takes this parameter', '', '')
        end if
      end do
    end do
  end subroutine model_requires

  !> The strength-reduction curve is required with its mode and forbidden without it.
  !> Same shape as `model_requires`, and the same reason: "required" is a property of the
  !> (key, mode) pair. A curve named on a plain gravity run would be silently ignored --
  !> legacy only reads mat_curve under MAT_DE -- and an author would never learn that the
  !> schedule they wrote did nothing.
  subroutine load_mode_requires(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: km, kc, a

    do a = 1_int32, doc%count_of('step')
      call one_step_load_mode(doc, file, a, errors)
    end do
  end subroutine load_mode_requires

  subroutine one_step_load_mode(doc, file, a, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    integer(int32), intent(in) :: a
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: km, kc
    logical :: reducing
    character(len=TOML_LEN_PATH) :: base

    base = 'step['//trim(itoa(a))//']'
    km = doc%find(trim(base)//'.load_mode')
    if (km == 0_int32) return                  ! a missing mode is require_all's finding
    reducing = trim(doc%entry(km)%svalue) == 'strength_reduction'
    kc = doc%find(trim(base)//'.strength_reduction.amplitude')
    if (reducing .and. kc == 0_int32) then
      call raise(errors, PE_MISSING_FIELD, PE_EXIT_INPUT, file, doc%entry(km)%line,           &
                 trim(base)//'.strength_reduction.amplitude',                                &
                 'strength reduction needs the amplitude that schedules it', '',              &
                 'an amplitude name')
    end if
    if (.not. reducing .and. kc /= 0_int32) then
      ! Located on the MODE line, not on the curve. Two lines contradict each other and
      ! this is the one the author most likely meant to change -- they wrote a reduction
      ! schedule, so the mode is what is out of step with the intent. The message names
      ! the other line so neither has to be guessed at.
      call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(km)%line,           &
                 trim(base)//'.strength_reduction.amplitude',                                &
                 'a strength-reduction curve is named but load.mode is not '//                &
                 '"strength_reduction", so legacy would never read it',                       &
                 trim(doc%entry(km)%svalue), 'strength_reduction')
    end if
  end subroutine one_step_load_mode

  ! ------------------------------------------------------------------ checks ----

  subroutine check_allowed(doc, i, key, file, errors)
    type(toml_doc_t), intent(in) :: doc
    integer(int32), intent(in) :: i
    type(key_t), intent(in) :: key
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    character(len=LEN_ALLOW) :: got
    select case (doc%entry(i)%kind)
    case (TV_STR);  got = doc%entry(i)%svalue
    case (TV_INT);  got = itoa(doc%entry(i)%ivalue)
    case default;   return   ! the contract whitelists only strings and small integers
    end select
    if (in_list(trim(got), trim(key%allowed))) return
    ! A well-formed value outside the whitelist is a CAPABILITY verdict, not a malformed
    ! file: the operator's file is fine and this build cannot do what it asks.
    call raise(errors, PE_UNSUPPORTED, PE_EXIT_UNSUPPORTED, file, doc%entry(i)%line,         &
               trim(doc%entry(i)%path), 'value is outside this build''s whitelist',          &
               trim(got), trim(key%allowed))
  end subroutine check_allowed

  !> Require `pattern` for every concrete index combination the document actually has.
  subroutine require_all(doc, pattern, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: pattern
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n1, n2, a, b
    character(len=TOML_LEN_PATH) :: p1, p2
    character(len=LEN_PAT) :: head

    if (index(pattern, '[]') == 0) then
      if (doc%find(pattern) == 0_int32) then
        call missing(errors, file, pattern)
      end if
      return
    end if

    head = pattern(1:index(pattern, '[]') - 1)
    n1 = doc%count_of(trim(head))
    if (n1 == 0_int32) then
      ! An absent collection is only a defect when the contract requires the collection
      ! itself; `step` is checked by its own arity rule, the rest may legitimately be
      ! empty and the mapping layer will say so if it needs one.
      return
    end if
    do a = 1_int32, n1
      p1 = subst_first(pattern, a)
      if (index(p1, '[]') == 0) then
        if (doc%find(trim(p1)) == 0_int32) call missing(errors, file, trim(p1))
        cycle
      end if
      head = p1(1:index(p1, '[]') - 1)
      n2 = doc%count_of(trim(head))
      do b = 1_int32, n2
        p2 = subst_first(trim(p1), b)
        if (index(p2, '[]') /= 0) cycle   ! three index levels: not in this contract
        if (doc%find(trim(p2)) == 0_int32) call missing(errors, file, trim(p2))
      end do
    end do
  end subroutine require_all

  subroutine unique_names(doc, collection, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: collection, file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n, a, b, ka, kb
    n = doc%count_of(collection)
    do a = 1_int32, n
      ka = doc%find(trim(collection)//'['//trim(itoa(a))//'].name')
      if (ka == 0_int32) cycle
      do b = a + 1_int32, n
        kb = doc%find(trim(collection)//'['//trim(itoa(b))//'].name')
        if (kb == 0_int32) cycle
        if (trim(doc%entry(ka)%svalue) == trim(doc%entry(kb)%svalue)) then
          call raise(errors, PE_DUPLICATE_REF, PE_EXIT_INPUT, file, doc%entry(kb)%line,      &
                     trim(collection)//'['//trim(itoa(b))//'].name',                         &
                     'duplicate name in this collection; references are by name, so two '//  &
                     'entries with one name have no meaning',                                &
                     trim(doc%entry(kb)%svalue), 'a name not already used')
        end if
      end do
    end do
  end subroutine unique_names

  subroutine resolve(doc, from, field, to, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: from, field, to, file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n, a, k
    n = doc%count_of(from)
    do a = 1_int32, n
      k = doc%find(trim(from)//'['//trim(itoa(a))//'].'//trim(field))
      if (k == 0_int32) cycle
      if (.not. name_exists(doc, to, trim(doc%entry(k)%svalue))) then
        call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line,         &
                   trim(from)//'['//trim(itoa(a))//'].'//trim(field),                        &
                   'refers to a '//trim(to)//' that this file does not define',              &
                   trim(doc%entry(k)%svalue), 'a declared [['//trim(to)//']] name')
      end if
    end do
  end subroutine resolve

  subroutine resolve_nested(doc, outer, inner, field, to, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: outer, inner, field, to, file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: no, ni, a, b, k
    character(len=TOML_LEN_PATH) :: base
    no = doc%count_of(outer)
    do a = 1_int32, no
      base = trim(outer)//'['//trim(itoa(a))//'].'//trim(inner)
      ni = doc%count_of(trim(base))
      do b = 1_int32, ni
        k = doc%find(trim(base)//'['//trim(itoa(b))//'].'//trim(field))
        if (k == 0_int32) cycle
        if (.not. name_exists(doc, to, trim(doc%entry(k)%svalue))) then
          call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line,       &
                     trim(base)//'['//trim(itoa(b))//'].'//trim(field),                      &
                     'refers to a '//trim(to)//' that this file does not define',            &
                     trim(doc%entry(k)%svalue), 'a declared [['//trim(to)//']] name')
        end if
      end do
    end do
  end subroutine resolve_nested

  subroutine resolve_step_amplitude(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: n, a, nl, b
    n = doc%count_of('step')
    do a = 1_int32, n
      call one_amplitude_ref(doc, file,                                                       &
           'step['//trim(itoa(a))//'].strength_reduction.amplitude', errors)
      nl = doc%count_of('step['//trim(itoa(a))//'].load')
      do b = 1_int32, nl
        call one_amplitude_ref(doc, file,                                                     &
             'step['//trim(itoa(a))//'].load['//trim(itoa(b))//'].amplitude', errors)
      end do
    end do
  end subroutine resolve_step_amplitude

  !> Every name in a step's `active_elsets` must be a declared elset. A typo here is
  !> silent in the worst way: the element set simply never appears in the model, and the
  !> analysis runs to completion on a structure with a piece missing.
  subroutine resolve_active_elsets(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: a, i, kn, k
    character(len=TOML_LEN_PATH) :: base

    do a = 1_int32, doc%count_of('step')
      base = 'step['//trim(itoa(a))//'].active_elsets'
      kn = doc%find(trim(base)//'.count')
      if (kn == 0_int32) cycle
      do i = 1_int32, doc%entry(kn)%ivalue
        k = doc%find(trim(base)//'['//trim(itoa(i))//']')
        if (k == 0_int32) cycle
        if (name_exists(doc, 'elset', trim(doc%entry(k)%svalue))) cycle
        call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line,           &
                   trim(base)//'['//trim(itoa(i))//']',                                       &
                   'refers to an elset that this file does not define',                       &
                   trim(doc%entry(k)%svalue), 'a declared [[elset]] name')
      end do
    end do
  end subroutine resolve_active_elsets

  !> One amplitude reference, if present, must name a declared amplitude. Two call sites
  !> now (gravity's curve and the strength-reduction schedule) and the same rule for both.
  subroutine one_amplitude_ref(doc, file, path, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file, path
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: k
    k = doc%find(path)
    if (k == 0_int32) return
    if (name_exists(doc, 'amplitude', trim(doc%entry(k)%svalue))) return
    call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line, path,        &
               'refers to an amplitude that this file does not define',                      &
               trim(doc%entry(k)%svalue), 'a declared [[amplitude]] name')
  end subroutine one_amplitude_ref

  !> A load object's fields are required BY ITS TYPE, and forbidden outside it.
  !>
  !> Third instance of the same shape as `model_requires` and `load_mode_requires`, and
  !> the reason it keeps recurring is structural: legacy reads a common record and then
  !> branches, so "required" is a property of the (key, discriminator) pair rather than of
  !> the key. Both directions are checked -- a water-pressure distribution written on a
  !> gravity object would otherwise be read by nobody and reported by nobody.
  subroutine load_type_requires(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), parameter :: GRAV(3) = [character(len=24) ::                            &
      'magnitude', 'direction.count', 'apply_to']
    character(len=*), parameter :: PRES(6) = [character(len=24) ::                            &
      'surface', 'distribution.type', 'distribution.axis', 'distribution.at.count',           &
      'distribution.value.count', 'distribution.scale']
    integer(int32) :: a, b, kt, k
    character(len=TOML_LEN_PATH) :: base
    logical :: is_grav
    integer :: f

    do a = 1_int32, doc%count_of('step')
      do b = 1_int32, doc%count_of('step['//trim(itoa(a))//'].load')
        base = 'step['//trim(itoa(a))//'].load['//trim(itoa(b))//']'
        kt = doc%find(trim(base)//'.type')
        if (kt == 0_int32) cycle               ! a missing type is require_all's finding
        is_grav = trim(doc%entry(kt)%svalue) == 'gravity'
        do f = 1, size(GRAV)
          call needs(doc, file, errors, trim(base), trim(GRAV(f)), is_grav, kt, 'gravity')
        end do
        do f = 1, size(PRES)
          call needs(doc, file, errors, trim(base), trim(PRES(f)), .not. is_grav, kt,         &
                     'pressure')
        end do
        ! `apply_to` names an element set or the whole model. It is required rather than
        ! defaulted to "all" because on a two-material deck "which elements are heavy" is
        ! a physical statement, and this contract does not guess physical statements.
        k = doc%find(trim(base)//'.apply_to')
        if (is_grav .and. k /= 0_int32) then
          if (trim(doc%entry(k)%svalue) /= 'all') then
            if (.not. name_exists(doc, 'elset', trim(doc%entry(k)%svalue))) then
              call raise(errors, PE_DANGLING_REF, PE_EXIT_INPUT, file, doc%entry(k)%line,     &
                         trim(base)//'.apply_to',                                             &
                         'refers to an elset that this file does not define',                 &
                         trim(doc%entry(k)%svalue), '"all" or a declared [[elset]] name')
            end if
          end if
        end if
      end do
    end do
  end subroutine load_type_requires

  !> One (field, belongs-to-this-type) pair, both directions.
  subroutine needs(doc, file, errors, base, field, wanted, kt, tname)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file, base, field, tname
    logical, intent(in) :: wanted
    integer(int32), intent(in) :: kt
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: k
    k = doc%find(trim(base)//'.'//trim(field))
    if (wanted .and. k == 0_int32) then
      call raise(errors, PE_MISSING_FIELD, PE_EXIT_INPUT, file, doc%entry(kt)%line,           &
                 trim(base)//'.'//trim(field),                                                &
                 'a load of type "'//trim(tname)//'" needs this field', '', 'a value')
    else if ((.not. wanted) .and. k /= 0_int32) then
      call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(k)%line,            &
                 trim(base)//'.'//trim(field),                                                &
                 'only a load of type "'//trim(tname)//'" takes this field; here it '//       &
                 'would be read by nothing', trim(doc%entry(kt)%svalue), tname)
    end if
  end subroutine needs

  !> The two numeric degeneracies a load object can carry.
  !>
  !> Both are things legacy does not survive: a zero gravity direction leaves the load
  !> vector undefined, and `at[1] == at[2]` divides by zero in `Load.f90:819`
  !> (`dcor/(cor0-cor1)`). Neither is a whitelist question -- the value is well formed and
  !> the combination is arithmetic nonsense -- so both are INVALID_INPUT.
  subroutine check_loads(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: a, b, k1, k2, kn, kv
    character(len=TOML_LEN_PATH) :: base
    real(real64) :: d1, d2

    do a = 1_int32, doc%count_of('step')
      do b = 1_int32, doc%count_of('step['//trim(itoa(a))//'].load')
        base = 'step['//trim(itoa(a))//'].load['//trim(itoa(b))//']'

        k1 = doc%find(trim(base)//'.direction[1]')
        k2 = doc%find(trim(base)//'.direction[2]')
        if (k1 /= 0_int32 .and. k2 /= 0_int32) then
          d1 = doc%entry(k1)%rvalue
          d2 = doc%entry(k2)%rvalue
          if (d1*d1 + d2*d2 == 0.0_real64) then
            call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(k1)%line,     &
                       trim(base)//'.direction',                                              &
                       'the direction has zero length, so it names no direction at all',      &
                       '[0, 0]', 'a vector with non-zero length')
          end if
        end if

        k1 = doc%find(trim(base)//'.distribution.at[1]')
        k2 = doc%find(trim(base)//'.distribution.at[2]')
        if (k1 /= 0_int32 .and. k2 /= 0_int32) then
          if (doc%entry(k1)%rvalue == doc%entry(k2)%rvalue) then
            call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(k2)%line,     &
                       trim(base)//'.distribution.at',                                        &
                       'the two coordinates are equal, and legacy divides by their '//        &
                       'difference (Load.f90:819)', trim(rtoa(doc%entry(k1)%rvalue)),         &
                       'two different coordinates')
          end if
        end if

        kn = doc%find(trim(base)//'.distribution.at.count')
        kv = doc%find(trim(base)//'.distribution.value.count')
        if (kn /= 0_int32 .and. kv /= 0_int32) then
          if (doc%entry(kn)%ivalue /= doc%entry(kv)%ivalue) then
            call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(kv)%line,     &
                       trim(base)//'.distribution.value',                                     &
                       'the distribution pairs one pressure with each coordinate, so the '//  &
                       'two arrays must be the same length',                                  &
                       trim(itoa(doc%entry(kv)%ivalue)), trim(itoa(doc%entry(kn)%ivalue)))
          else if (doc%entry(kn)%ivalue /= 2_int32) then
            ! Two points are what a 2-D linear distribution is; more of them is a
            ! piecewise profile, which legacy's single (cor0, cor1, p0, p1) record
            ! cannot express at all. A capability refusal, not a malformed file.
            call raise(errors, PE_UNSUPPORTED, PE_EXIT_UNSUPPORTED, file,                     &
                       doc%entry(kn)%line, trim(base)//'.distribution.at',                    &
                       'a 2-D linear distribution is fixed by exactly two points',            &
                       trim(itoa(doc%entry(kn)%ivalue)), '2')
          end if
        end if
      end do
    end do
  end subroutine check_loads

  !> A surface is an explicit edge table, and every row must have the arity its `kind`
  !> declares. Node and element NUMBERS are not checked here: this layer never opens the
  !> mesh, so "node 9999 does not exist" is the mapping layer's finding, where the .cor
  !> file is in hand. What is checkable here is shape and sign, and a zero or negative
  !> number is never a legacy node id.
  subroutine check_surfaces(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: a, e, k, kc, c, j, want
    character(len=TOML_LEN_PATH) :: base, row

    do a = 1_int32, doc%count_of('surface')
      base = 'surface['//trim(itoa(a))//']'
      k = doc%find(trim(base)//'.kind')
      want = 3_int32                            ! 'edge2': [n1, n2, element]
      if (k == 0_int32) cycle
      kc = doc%find(trim(base)//'.edges.count')
      if (kc == 0_int32) cycle
      if (doc%entry(kc)%ivalue == 0_int32) then
        call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(k)%line,          &
                   trim(base)//'.edges', 'a surface with no edges carries no load', '0',      &
                   'at least one [n1, n2, element] row')
        cycle
      end if
      do e = 1_int32, doc%entry(kc)%ivalue
        row = trim(base)//'.edges['//trim(itoa(e))//']'
        c = doc%find(trim(row)//'.count')
        if (c == 0_int32) cycle
        if (doc%entry(c)%ivalue /= want) then
          call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(c)%line,        &
                     trim(row), 'kind "'//trim(doc%entry(k)%svalue)//'" makes every row '//   &
                     '[n1, n2, element]', trim(itoa(doc%entry(c)%ivalue)), trim(itoa(want)))
          cycle
        end if
        do j = 1_int32, want
          c = doc%find(trim(row)//'['//trim(itoa(j))//']')
          if (c == 0_int32) cycle
          if (doc%entry(c)%ivalue < 1_int32) then
            call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(c)%line,      &
                       trim(row), 'node and element numbers start at 1',                      &
                       trim(itoa(doc%entry(c)%ivalue)), 'a positive number')
          end if
        end do
      end do
    end do
  end subroutine check_surfaces

  !> An amplitude's abscissa must strictly increase.
  !>
  !> legacy evaluates a curve by walking the time array until it passes the current time
  !> and interpolating between the two straddling points; a repeated or decreasing time
  !> makes the segment it lands on depend on the walk, not on the author's intent, and a
  !> repeat divides by a zero interval. It is not a whitelist question, so INVALID_INPUT.
  subroutine check_amplitudes(doc, file, errors)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: file
    type(problem_errors_t), intent(inout) :: errors
    integer(int32) :: a, i, kn, kp, kq
    character(len=TOML_LEN_PATH) :: base

    do a = 1_int32, doc%count_of('amplitude')
      base = 'amplitude['//trim(itoa(a))//'].points'
      kn = doc%find(trim(base)//'.count')
      if (kn == 0_int32) cycle
      do i = 2_int32, doc%entry(kn)%ivalue
        kp = doc%find(trim(base)//'['//trim(itoa(i - 1_int32))//'][1]')
        kq = doc%find(trim(base)//'['//trim(itoa(i))//'][1]')
        if (kp == 0_int32 .or. kq == 0_int32) cycle
        if (doc%entry(kq)%rvalue > doc%entry(kp)%rvalue) cycle
        call raise(errors, PE_INVALID_INPUT, PE_EXIT_INPUT, file, doc%entry(kq)%line,         &
                   trim(base)//'['//trim(itoa(i))//']',                                       &
                   'the time points of an amplitude must strictly increase',                  &
                   trim(rtoa(doc%entry(kq)%rvalue)),                                          &
                   'a time later than '//trim(rtoa(doc%entry(kp)%rvalue)))
      end do
    end do
  end subroutine check_amplitudes

  !> A real, rendered short enough to read inside an error message.
  function rtoa(x) result(t)
    real(real64), intent(in) :: x
    character(len=24) :: t
    write (t, '(g0.6)') x
  end function rtoa

  ! ------------------------------------------------------------------ helpers ----

  pure logical function name_exists(doc, collection, want) result(found)
    type(toml_doc_t), intent(in) :: doc
    character(len=*), intent(in) :: collection, want
    integer(int32) :: n, a, k
    found = .false.
    n = doc%count_of(collection)
    do a = 1_int32, n
      k = doc%find(trim(collection)//'['//trim(itoa(a))//'].name')
      if (k == 0_int32) cycle
      if (trim(doc%entry(k)%svalue) == trim(want)) then
        found = .true.
        return
      end if
    end do
  end function name_exists

  subroutine missing(errors, file, path)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: file, path
    call raise(errors, PE_MISSING_FIELD, PE_EXIT_INPUT, file, 0_int32, path,                 &
               'required by the authoring contract and not present. It is required '//       &
               'because it is a physical choice: this build will not guess it', '', '')
  end subroutine missing

  subroutine raise(errors, code, exit_class, file, line, path, msg, actual, expected)
    type(problem_errors_t), intent(inout) :: errors
    character(len=*), intent(in) :: code, file, path, msg, actual, expected
    integer(int32), intent(in) :: exit_class, line
    if (line > 0_int32) then
      call errors%add(make_problem_error(code=code, stage='authoring',                       &
           object_path=path, message=msg, actual=actual, expected=expected,                  &
           exit_class=exit_class,                                                            &
           source=make_source_location(file=file, reader='case.toml', line=line)))
    else
      call errors%add(make_problem_error(code=code, stage='authoring',                       &
           object_path=path, message=msg, actual=actual, expected=expected,                  &
           exit_class=exit_class, source=make_source_location(file=file, reader='case.toml')))
    end if
  end subroutine raise

  !> `material[2].E` -> `material[].E`; indices are positions, not identity.
  pure function normalise(path) result(out)
    character(len=*), intent(in) :: path
    character(len=TOML_LEN_PATH) :: out
    integer :: i
    logical :: skipping
    out = ''
    skipping = .false.
    do i = 1, len_trim(path)
      if (path(i:i) == '[') then
        skipping = .true.
        out = trim(out)//'[]'
        cycle
      end if
      if (path(i:i) == ']') then
        skipping = .false.
        cycle
      end if
      if (.not. skipping) out = trim(out)//path(i:i)
    end do
  end function normalise

  pure integer function slot(np) result(k)
    character(len=*), intent(in) :: np
    integer :: i
    k = 0
    do i = 1, size(KEYS)
      if (trim(KEYS(i)%pattern) == trim(np)) then
        k = i
        return
      end if
    end do
  end function slot

  pure function subst_first(pattern, idx) result(out)
    character(len=*), intent(in) :: pattern
    integer(int32), intent(in) :: idx
    character(len=TOML_LEN_PATH) :: out
    integer :: p
    p = index(pattern, '[]')
    out = pattern(1:p - 1)//'['//trim(itoa(idx))//']'//trim(pattern(p + 2:))
  end function subst_first

  pure logical function in_list(want, list) result(found)
    character(len=*), intent(in) :: want, list
    integer :: p, q
    found = .false.
    p = 1
    do
      q = index(list(p:), '|')
      if (q == 0) then
        found = (trim(list(p:)) == trim(want))
        return
      end if
      if (trim(list(p:p + q - 2)) == trim(want)) then
        found = .true.
        return
      end if
      p = p + q
    end do
  end function in_list

  pure function kind_name(k) result(s)
    integer(int32), intent(in) :: k
    character(len=:), allocatable :: s
    select case (k)
    case (TV_INT);  s = 'integer'
    case (TV_REAL); s = 'real'
    case (TV_STR);  s = 'string'
    case (TV_BOOL); s = 'boolean'
    case default;   s = 'unknown'
    end select
  end function kind_name

  pure function itoa(v) result(out)
    integer(int32), intent(in) :: v
    character(len=12) :: buf
    character(len=:), allocatable :: out
    write (buf, '(i0)') v
    out = trim(buf)
  end function itoa

end module yl_authoring_keys
