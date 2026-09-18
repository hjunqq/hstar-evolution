! yl_problem_types -- the M3 ProblemState derived types.
!
! Scope (see .ccg/tasks/m3-01-problemstate-types/plan.md and requirements.md)
!   Types ONLY. No parse, no normalize, no validate, no finalize, no commit and no
!   RuntimeState: those are M3-02 and M3-03. Nothing here reads a legacy file format
!   or touches a solver work array (src/problem/README.md).
!
! Where the field names come from
!   Every component below is derived MECHANICALLY from the `owner` column of
!   docs/m2/state-field-map.toml, never from the `id` column, which still carries the
!   Fortran spellings (`gid_u`, `icreep`, `type_nalgo`, `nonsym`). The 98 exported rows
!   -- `compare.rule != "ignore"` and `owner` starting with `ProblemState.` -- are in
!   one-to-one correspondence with the 98 mapped leaf components declared here, and
!   `python3 tools/yl_problem_check.py check` enforces that correspondence in both
!   directions, fail-closed. Two components carry no map row and therefore carry an
!   `@m5-only` marker with a reason; every other component must trace to exactly one
!   map field id.
!
!   Because the names are mechanical, this module deliberately contains NO Fortran slot
!   name: no npoin, nelem, ndofix, mdofn, matno, nonsym, noutf. The check tool builds a
!   deny list out of the map's own `legacy_symbol` leaf names and fails on any leak.
!
! Absence discipline (ADR-0002)
!   `unset`, an explicit zero and an empty collection are three distinct states and no
!   value is ever overloaded as a second-meaning sentinel:
!     * authoring scalars are the opt_int / opt_real / opt_text wrappers of
!       yl_problem_optional -- default-initialised to unset, payload private, read only
!       through opt_get / opt_value_or;
!     * collections and per-entity vectors are `allocatable`, where NOT allocated means
!       unset and allocated with size 0 means explicitly empty;
!     * no component carries an initializer, a `pointer`, or a declared extent. Extents
!       are derived at finalize, so a count is never stored as a field.
!
! Shape convention
!   A row whose map `shape` carries one more dimension than the owner path has `[]`
!   collection levels becomes a deferred-shape rank-1 array on the entity that owns it
!   (mesh.nodes[].xyz over the spatial dimensions, mesh.elements[].nodes over the element
!   connectivity, controls.tolerance_dof over the degrees of freedom). Everything else is
!   a scalar of the owning entity. Ragged legacy arrays become one allocatable per
!   collection entry, not one flat array with a stored offset table.
module yl_problem_types

  use iso_fortran_env, only: int32, real64
  use yl_problem_optional, only: opt_int, opt_real, opt_text, opt_logical

  implicit none
  private

  ! Default private; every exported entity carries an explicit `public` attribute on its
  ! own `type, public ::` header, so this module has exactly one place per name.

  ! --- case -------------------------------------------------------------------
  ! ProblemState.case (2 components: 1 mapped + 1 M5-only)

  type, public :: case_t
    type(opt_text) :: name
    type(opt_text) :: units   !@m5-only: ADR-0003 mandates an explicit SI unit declaration that no legacy record carries
  end type case_t

  ! --- mesh -------------------------------------------------------------------
  ! ProblemState.mesh (10 mapped components across 5 types)

  type, public :: node_t
    type(opt_int) :: id
    real(real64), allocatable :: xyz(:)
  end type node_t

  type, public :: element_t
    type(opt_int) :: id
    type(opt_int) :: kind
    type(opt_int) :: material
    type(opt_int) :: elset
    integer(int32), allocatable :: nodes(:)
  end type element_t

  ! One ordered element list per element set; the set key is the section name.
  type, public :: elset_t
    integer(int32), allocatable :: elements(:)
  end type elset_t

  ! One ordered node list per node set; the set key is the boundary name.
  type, public :: nset_t
    integer(int32), allocatable :: nodes(:)
  end type nset_t

  !> One NODE-INTERPOLATION constraint: this node's motion is a weighted average of other
  !> nodes' (legacy `trans`, filled from `.nrt` at Global.f90:1502-1531).
  !>
  !> It lives under `mesh` and not under `steps[].boundary` for the reason the data itself
  !> gives: it is mesh-generator output keyed by node id, read ONCE for the whole analysis
  !> rather than per block, and it constrains a node to other nodes rather than to a value.
  !> A boundary record is (variable, value); this is (variable, variables, weights).
  !>
  !> Not a pass-through, though it looked like one for most of 2026-09-18: legacy reads
  !> `.nrt` inside `global_data`, and `global_data` does not run on the adapter path, so
  !> the table has to cross the seam like every other input. The equation count is what
  !> settled it -- 122 dofs' worth of constraints silently absent. See docs/m9.
  type, public :: interpolation_t
    type(opt_int) :: node              !@off-face: mesh.interpolation.node
    integer(int32), allocatable :: sources(:)   !@off-face: mesh.interpolation.source_nodes
    real(real64), allocatable :: weights(:)     !@off-face: mesh.interpolation.weights
  end type interpolation_t

  type, public :: mesh_t
    type(opt_int) :: dimension
    type(node_t), allocatable :: nodes(:)
    type(element_t), allocatable :: elements(:)
    type(elset_t), allocatable :: elsets(:)
    type(nset_t), allocatable :: nsets(:)
    !> Empty on every deck without a `.nrt` interpolation group, which is eight of the nine.
    type(interpolation_t), allocatable :: interpolation(:)
  end type mesh_t

  ! --- materials --------------------------------------------------------------
  ! ProblemState.materials[] (13 mapped components + 8 in plasticity_t)
  !
  ! `plasticity` is the FIRST per-model parameter block. The shape matters more than the
  ! eight fields: legacy's `.mat` reads a COMMON solid record for every material and then
  ! branches per constitutive model (Material.f90:457), each branch with its own extra
  ! records. ProblemState mirrors that -- the common fields sit on material_t, the
  ! model-specific ones in a block that is only meaningful for its model. The next model
  ! adds a sibling block, not eight more optional components on material_t.
  !
  ! Every component is `opt_*`, so "CLASSICALEP was not the model" and "the criterion did
  ! not call for a friction angle" are both representable as absence rather than as 0.0,
  ! which is a real friction angle.

  ! The component names are the MODERN spellings, not legacy's abbreviations -- ADR-0003,
  ! and rule 10 of yl_problem_check forbids harvesting a legacy slot name into the types.
  ! Legacy's own names are in the map rows' `legacy_symbol`, which is where they belong.
  !
  !   criterion              the yield criterion; 'MC' is the whitelist, legacy also has
  !                          TC / VM / DP / MCC / DPC / MCJOINT (legacy `criteria`)
  !   yield_stress           Pa; for MC this is the cohesion c (legacy `sigma0`)
  !   hardening_modulus      Pa (legacy `hardening`)
  !   friction_angle  deg }  read only when criteria(1:2) is 'MC' or 'DP'
  !   dilation_angle  deg }  (Material.f90:624), hence opt_ rather than a 0.0 default
  !   *_curve                CURVE INDICES, not values: legacy declares them integer(ink)
  !                          and 0 means "no curve". The golden deck writes them as `0.0`,
  !                          which ifx list-directed read accepts into an integer as 0 --
  !                          measured 2026-09-13, not assumed.
  type, public :: plasticity_t
    type(opt_text) :: criterion              !@off-face: materials.plasticity.criteria
    type(opt_real) :: yield_stress           !@off-face: materials.plasticity.sigma0
    type(opt_real) :: hardening_modulus      !@off-face: materials.plasticity.hardening
    type(opt_real) :: friction_angle         !@off-face: materials.plasticity.frict_angle
    type(opt_real) :: dilation_angle         !@off-face: materials.plasticity.dilan_angle
    type(opt_int) :: yield_stress_curve      !@off-face: materials.plasticity.csigma0
    type(opt_int) :: friction_angle_curve    !@off-face: materials.plasticity.cfrict
    type(opt_int) :: dilation_angle_curve    !@off-face: materials.plasticity.cdilan
  end type plasticity_t

  ! The SECOND per-model block, and the one that proves the shape above was right: it is a
  ! sibling of plasticity_t, not thirteen more optional components on material_t.
  !
  ! DUNCANCHANG is a nonlinear-ELASTIC law, not a plasticity model: EBMOD (Stiff.f90:6665)
  ! recomputes a tangent Young's modulus and Poisson ratio from the current stress state
  ! every time it is called; nothing yields and no plastic strain accumulates.
  !
  ! Legacy reads a model selector and nine numbers (Material.f90:504-513), then a further
  ! record whose SHAPE depends on that selector (521-531). Only the `EB` branch is carried
  ! here -- it is the one the real deck uses -- so `bulk_modulus_number`, `bulk_modulus_exponent`
  ! and `friction_angle_reduction` are the EB record, and legacy's `EV`/`CR` trio
  ! (G / F / Vtf) has no component at all. That is the refusal: a capability with no field
  ! to put it in cannot be silently half-read.
  !
  ! Two further records legacy can read here are likewise absent by construction:
  !   k1/k2/nd/lamdaMax  read only when type_problem == 'F' (Material.f90:515-520); this
  !                      build whitelists 'Q'.
  !   phi_s/k_s          read only when kind_wt > 0 (Material.f90:539-542); this build
  !                      refuses a non-zero wetting kind in the material gate already.
  !
  !   bulk_modulus_law        legacy `model`; 'EB' is the whitelist
  !   cohesion            Pa  legacy `cohes`
  !   friction_angle      deg legacy `phi`; EBMOD takes SINd()/COSd() of it, so degrees
  !   modulus_number      1   legacy `K`   } E_t = K * Pa * (p3/Pa)**n * (1 - Rf*S)**2
  !   modulus_exponent    1   legacy `n`   }
  !   failure_ratio       1   legacy `Rf`
  !   unload_modulus_number   1   legacy `Kur` } E_ur = Kur * Pa * (p3/Pa)**Nur
  !   unload_modulus_exponent 1   legacy `Nur` } an EXPONENT, not a Poisson ratio
  !   reference_pressure  Pa  legacy `Pa`; atmospheric pressure, the normalising constant
  !   min_confining_pressure  Pa  legacy `P0`; p3 is clamped up to it before every power
  !   bulk_modulus_number     1   legacy `Kb` } B_t = Kb * Pa * (p3/Pa)**m, EB record
  !   bulk_modulus_exponent   1   legacy `m`  }
  !   friction_angle_reduction deg legacy `dphi`; phi = phi - dphi*log10(p3/Pa), EB record
  type, public :: duncan_chang_t
    type(opt_text) :: bulk_modulus_law        !@off-face: materials.duncan_chang.model
    type(opt_real) :: cohesion                !@off-face: materials.duncan_chang.cohes
    type(opt_real) :: friction_angle          !@off-face: materials.duncan_chang.phi
    type(opt_real) :: modulus_number          !@off-face: materials.duncan_chang.k
    type(opt_real) :: modulus_exponent        !@off-face: materials.duncan_chang.n
    type(opt_real) :: failure_ratio           !@off-face: materials.duncan_chang.rf
    type(opt_real) :: unload_modulus_number   !@off-face: materials.duncan_chang.kur
    type(opt_real) :: unload_modulus_exponent !@off-face: materials.duncan_chang.nur
    type(opt_real) :: reference_pressure      !@off-face: materials.duncan_chang.pa
    type(opt_real) :: min_confining_pressure  !@off-face: materials.duncan_chang.p0
    type(opt_real) :: bulk_modulus_number     !@off-face: materials.duncan_chang.kb
    type(opt_real) :: bulk_modulus_exponent   !@off-face: materials.duncan_chang.m
    type(opt_real) :: friction_angle_reduction !@off-face: materials.duncan_chang.dphi
  end type duncan_chang_t

  ! The THIRD per-model block. CONCRETE is a damage model: a four-coefficient failure
  ! surface decides when damage starts, and a softening law carries it afterwards.
  !
  ! The coefficient names come from what each one MULTIPLIES in legacy's own expression
  ! (Residu.f90:3265), not from its legacy letter -- rule 10 forbids harvesting A/B/C/D,
  ! and the letters say nothing anyway:
  !
  !     eqstr = A*steff**2/Fc + B*steff + C*sigma1 + 3*D*smean
  !             ^dev quadratic  ^dev linear ^principal  ^mean
  !
  ! with `steff` the equivalent deviatoric stress, `sigma1` the major principal stress and
  ! `smean` the mean stress. Damage begins where `eqstr` reaches `compressive_strength`.
  !
  ! ONLY the parameters this build's deck uses are here. legacy's material_4 also carries
  ! at/bt/alfat/t1..t4/ft0/eft and the compressive twins ac/bc/..., which belong to the
  ! `crack_model == 2` branch (Material.f90:700) -- a branch that reads a FURTHER record
  ! and that the adapter refuses by name. Two more, `bb` and `et0`, are DERIVED by legacy's
  ! reader rather than read (Material.f90:684-692), so they are reproduced by the bridge
  ! and are not authored fields either.
  !
  !   dev_stress_quadratic  1   legacy `A`
  !   dev_stress_linear     1   legacy `B`
  !   principal_stress      1   legacy `C`
  !   mean_stress           1   legacy `D`
  !   compressive_strength  Pa  legacy `Fc`
  !   tensile_ratio         1   legacy `Ct`, which legacy's own comment defines as Ft/Fc
  !   fracture_energy       N/m legacy `Gf`
  !   characteristic_length m   legacy `h`, the regularisation length the softening law
  !                             divides by, so the answer depends on it
  !   crack_model           id  legacy `icr`; it SELECTS a branch, including one that reads
  !                             another record, so it is whitelisted rather than carried freely
  type, public :: concrete_t
    type(opt_real) :: dev_stress_quadratic   !@off-face: materials.concrete.a
    type(opt_real) :: dev_stress_linear      !@off-face: materials.concrete.b
    type(opt_real) :: principal_stress       !@off-face: materials.concrete.c
    type(opt_real) :: mean_stress            !@off-face: materials.concrete.d
    type(opt_real) :: compressive_strength   !@off-face: materials.concrete.fc
    type(opt_real) :: tensile_ratio          !@off-face: materials.concrete.ct
    type(opt_real) :: fracture_energy        !@off-face: materials.concrete.gf
    type(opt_real) :: characteristic_length  !@off-face: materials.concrete.h
    type(opt_int)  :: crack_model            !@off-face: materials.concrete.icr
  end type concrete_t

  type, public :: material_t
    type(opt_int) :: id
    type(opt_text) :: name
    type(opt_text) :: kind
    type(opt_text) :: phase
    type(opt_text) :: model
    type(opt_real) :: E                    ! Pa
    type(opt_real) :: nu                   ! 1
    type(opt_real) :: density              ! kg/m3
    type(opt_real) :: thermal_expansion    ! 1/K
    type(opt_real) :: solid_ratio          ! 1
    type(opt_int) :: creep_model
    type(opt_int) :: liquefaction
    type(opt_int) :: wetting_kind
    !> Set only when `model` is a plasticity model; absent for ELASTIC_ISOTROPIC.
    type(plasticity_t) :: plasticity
    !> Set only when `model` is DUNCANCHANG; absent for every other model.
    type(duncan_chang_t) :: duncan_chang
    !> Set only when `model` is CONCRETE; absent for every other model.
    type(concrete_t) :: concrete
  end type material_t

  ! --- sections ---------------------------------------------------------------
  ! ProblemState.sections[] (17 mapped components). A section holds the FORMULATION and
  ! the material reference only; the element membership lives in mesh.elsets[] and the
  ! constitutive parameters live in materials[]. `material` is the effective material
  ! after the step activation override; `material_header` is the value as read from the
  ! group header and exists only so the bridge can re-emit that record.

  type, public :: section_t
    type(opt_text) :: name
    type(opt_text) :: element
    type(opt_int) :: element_kind
    type(opt_text) :: class
    type(opt_text) :: fields
    type(opt_text) :: formulation
    type(opt_text) :: special
    type(opt_int) :: material
    type(opt_int) :: material_header
    type(opt_int) :: algorithm
    type(opt_int) :: stiffness_kind
    type(opt_int) :: stress_recovery
    type(opt_int) :: layer
    type(opt_int) :: liquefaction
    type(opt_int) :: uplift
    type(opt_real) :: local_axes           ! 1
    type(opt_real) :: thickness            ! m
    !> Cross-sectional area of a line element. m2.
    !>
    !> The exact counterpart of `thickness`, and deliberately a sibling of it rather than a
    !> reuse: for a 2-D continuum element legacy's `thick` is a thickness in metres, and for
    !> a 2-node element it is an area in square metres (Stiff.f90:118 swaps the source), so
    !> they are different physical quantities that happen to occupy the same slot in the
    !> element routine. Giving them one component would make the unit depend on the element
    !> kind, which is exactly the kind of implicit coupling ADR-0003 exists to prevent.
    !>
    !> Stored by legacy on the MATERIAL (`props(imat)%geometry%aera`, Material.f90:1016)
    !> and owned here by the SECTION, the same indirection `thickness` already has and
    !> resolved by the same bridge pass.
    !> NOT called `area`: that is a legacy slot name (`global_var.element%area`, the steel
    !> element's own computed area) and rule 10 forbids harvesting one into the types. The
    !> two really are different quantities, so the deny list was right to stop it.
    type(opt_real) :: cross_section_area   !@off-face: sections.cross_section_area
  end type section_t

  ! --- amplitudes -------------------------------------------------------------
  ! ProblemState.amplitudes[] (3 mapped components + 1 M5-only)

  type, public :: amplitude_point_t
    type(opt_real) :: time                 ! s
    type(opt_real) :: value                ! 1
  end type amplitude_point_t

  type, public :: amplitude_t
    type(opt_text) :: name   !@m5-only: seven map rows index by this amplitude key but the key is never exported as a value
    type(opt_text) :: type
    type(amplitude_point_t), allocatable :: points(:)
  end type amplitude_t

  ! --- interactions -----------------------------------------------------------
  ! ProblemState.interactions (1 mapped component). Placeholder: on the static_2d path
  ! the absorbing boundary is a guard string only, with no interaction semantics behind
  ! it. The object exists so ADR-0003's top-level shape is complete.

  type, public :: absorbing_t
    type(opt_text) :: type
  end type absorbing_t

  type, public :: interactions_t
    type(absorbing_t) :: absorbing
  end type interactions_t

  ! --- solver -----------------------------------------------------------------
  ! ProblemState.solver (6 mapped components)

  type, public :: profile_t
    type(opt_int) :: singularity_check
    type(opt_int) :: condition_check
    type(opt_int) :: positive_definite_check
    type(opt_int) :: pivot_file
  end type profile_t

  !> The direct sparse solver's own settings, when `linear` selects it.
  !>
  !> A sibling block on solver_t for the same reason plasticity_t and duncan_chang_t are
  !> siblings on material_t: legacy's `.sol` has one record shape per solver
  !> (Solver.f90:6829 for PROFILE, :7788-7794 for PARDISO) and the settings of one are
  !> meaningless to the other. Set only when `linear` is PARDISO.
  !>
  !> These are NUMERICS, not physics: they choose how the same equations get solved, and
  !> nothing here enters the model. That is also why `threads` is carried rather than
  !> defaulted or tuned -- legacy puts it straight into `iparm(3)` (Solver.f90:7816), so it
  !> reaches the factorisation and is part of reproducing the deck. Choosing a good value
  !> is a performance question and belongs to a different thread of work than this one.
  !>
  !>   matrix_type    legacy `mtype`; -2 is real symmetric indefinite
  !>   threads        legacy `ncpu` -> iparm(3)
  !>   message_level  legacy `msglvl`; 0 is silent
  !>
  !> legacy's `isdefault` has no component here on purpose. It is not a value but a
  !> CAPABILITY SWITCH: non-zero makes legacy read a further record of eight iparm tuning
  !> numbers, and this build has nowhere to put them, so the adapter refuses it by name.
  type, public :: pardiso_t
    type(opt_int) :: matrix_type           !@off-face: solver.pardiso.mtype
    type(opt_int) :: threads               !@off-face: solver.pardiso.ncpu
    type(opt_int) :: message_level         !@off-face: solver.pardiso.msglvl
  end type pardiso_t

  type, public :: solver_t
    type(opt_text) :: linear
    ! Reads the legacy `nonsym` slot (a 0/1 flag, Solver.f90:7240) whose sense is
    ! inverted; the inversion is the bridge's job. The map keeps dtype i32 because
    ! that is the legacy WIRE type driving the state dump and the frozen baselines.
    type(opt_logical) :: symmetric  !@repr: bool from i32; legacy nonsym is a 0/1 flag with inverted sense, the bridge converts
    type(profile_t) :: profile
    !> Set only when `linear` is PARDISO; absent for PROFILE.
    type(pardiso_t) :: pardiso
  end type solver_t

  ! --- steps ------------------------------------------------------------------
  ! ProblemState.steps[0] (47 mapped components across 8 types). Authoring `steps[0]` is
  ! Fortran `steps(1)`; the collection is allocatable so "no steps declared" and "an
  ! empty step list" stay distinguishable.

  type, public :: activation_t
    type(opt_int) :: material
    type(opt_int) :: active
  end type activation_t

  ! One prescribed record: set, node set, degree of freedom, value and amplitude
  ! reference. Values vary per record, so a single scalar per set would lose them.
  type, public :: boundary_t
    type(opt_int) :: name
    type(opt_int) :: nset
    type(opt_int) :: dof
    type(opt_real) :: value                ! m
    type(opt_int) :: amplitude
    type(opt_int) :: record_reaction
  end type boundary_t

  type, public :: controls_t
    type(opt_int) :: nonlinear_type
    type(opt_int) :: increments
    type(opt_int) :: max_iterations
    type(opt_int) :: substeps
    type(opt_int) :: step_increment
    type(opt_int) :: restart_frequency
    type(opt_real) :: time_increment       ! s
    type(opt_real) :: tolerance_force      ! N
    real(real64), allocatable :: tolerance_dof(:)   ! m, one per degree of freedom
  end type controls_t

  type, public :: gravity_t
    !> legacy `NGRAV`: how often the gravity load is RECOMPUTED, not whether it is on.
    !> ALGORT (Fem.f90:15582) sets KGRAV=1 when NGRAV == 0, or on the first iteration of
    !> the first step, or every NGRAV-th step. It was modelled as `enabled` because the
    !> static slice has ONE step, where "recompute every step" and "on" are the same
    !> value -- the same shape as materials[].name in M5. Renamed 2026-09-14.
    type(opt_int) :: recompute_every
    type(opt_real) :: magnitude            ! m/s2
    real(real64), allocatable :: direction(:)       ! 1, one per spatial dimension
    integer(int32), allocatable :: amplitude(:)     ! id, one amplitude reference per section
  end type gravity_t

  !> One loaded stretch of a named face: legacy's edge-load group.
  !>
  !> legacy addresses the loaded edges as a CONTIGUOUS RANGE into the global `edges`
  !> table (`begin_edge .. end_edge`, Load.f90:767), and that is what is stored here. The
  !> range is not something an author writes -- the contract's section 3 keeps integer ids
  !> out of the input entirely -- it is what the mapping layer assigns when it lays the
  !> named `[[surface]]` collections out in declaration order. This is the same division
  !> as everywhere else in ProblemState: names in the input, ids in the state.
  type, public :: pressure_t
    type(opt_int) :: first_edge            !@off-face: steps0.load.pressure.begin_edge
    type(opt_int) :: last_edge             !@off-face: steps0.load.pressure.end_edge
    type(opt_int) :: amplitude             !@off-face: steps0.load.pressure.itcurve
    !> legacy `water`: |value| selects the coordinate the distribution reads and the sign
    !> says which way the head deepens (Load.f90:811-822). A physical choice, so it is
    !> carried rather than assumed, even though this build whitelists one value.
    type(opt_int) :: distribution_axis     !@off-face: steps0.load.pressure.water
    !> legacy `code_load` -- a SECOND distribution for the far side of the face -- is
    !> deliberately NOT a field here. legacy reads it into a routine local and keeps
    !> nothing: there is no global for a map row to name, so carrying it would mean
    !> inventing state legacy does not have. The contract admits no key for it, which is
    !> where that capability is refused.
    real(real64), allocatable :: at(:)     !@off-face: steps0.load.pressure.cor
    real(real64), allocatable :: value(:)  !@off-face: steps0.load.pressure.p
    type(opt_real) :: scale                !@off-face: steps0.load.pressure.fact
  end type pressure_t

  !> A concentrated force: one force vector applied at every node of a named set.
  !>
  !> legacy's `pload` group (Load.f90:250-264) is exactly this shape -- one curve, one
  !> `pxyz` vector, one node list -- so the record is carried across as it stands. Unlike
  !> the surface loads, legacy reads this ONCE, before the block loop (Fem.f90:1682), so
  !> it belongs to the analysis rather than to a block; the contract still writes it under
  !> a step, and a deck whose steps disagree about it is refused by name.
  type, public :: concentrated_t
    type(opt_int) :: amplitude                !@off-face: steps0.load.point.itcurve
    !> The force, one component per degree of freedom. legacy's `nudofn` is its size.
    real(real64), allocatable :: value(:)     !@off-face: steps0.load.point.pxyz
    !> The nodes it acts on. legacy's `npload` is its size.
    integer(int32), allocatable :: nodes(:)   !@off-face: steps0.load.point.list
  end type concentrated_t

  type, public :: load_t
    type(gravity_t) :: gravity
    !> The concentrated forces this step carries, in declaration order -- which is the
    !> order legacy reads its point-load groups.
    type(concentrated_t), allocatable :: concentrated(:)
    !> The pressure loads this step carries, in the order the author declared them --
    !> which is the order legacy reads its edge-load groups. NOT allocated means the step
    !> was never given a load record; allocated with size 0 means it carries no pressure,
    !> and those are different states (ADR-0002).
    type(pressure_t), allocatable :: pressure(:)
    !> legacy `mat_curve`: WHICH amplitude drives strength reduction. Only meaningful when
    !> `load_mode` is 'MAT_DE', where Stiff.f90:5779 takes that curve's current factor and
    !> scales the cohesion and tan(friction) / tan(dilation) by it -- so the curve IS the
    !> reduction schedule. An amplitude id, 1-based, like every other amplitude reference;
    !> unset means no strength reduction, which is what `mat_curve = 0` says.
    type(opt_int) :: strength_reduction   !@off-face: steps0.load.strength_reduction
  end type load_t

  ! Output request selectors, not results: each is an integer request level, so a
  ! logical would lose the levels the legacy writer supports.
  type, public :: output_field_t
    type(opt_int) :: u
    type(opt_int) :: v
    type(opt_int) :: a
    type(opt_int) :: s
    type(opt_int) :: ms
    type(opt_int) :: f
    type(opt_int) :: rot
    type(opt_int) :: T
    type(opt_int) :: P
    type(opt_int) :: Pv
    type(opt_int) :: ep
    type(opt_int) :: Y
    type(opt_int) :: FC
    type(opt_int) :: Ns
    type(opt_int) :: Ss
    type(opt_int) :: Mxy
    type(opt_int) :: bem
    type(opt_int) :: wh
    type(opt_int) :: wv
    type(opt_int) :: bcs
  end type output_field_t

  ! Two independent cadences read from one record; they never shared a field.
  type, public :: frequency_t
    type(opt_int) :: nodes
    type(opt_int) :: fields
  end type frequency_t

  type, public :: output_t
    type(opt_text) :: format
    type(output_field_t) :: field
    type(frequency_t) :: frequency
    integer(int32), allocatable :: stress_averaging(:)   ! 1, one per section
  end type output_t

  !> The datum a step's initial confining stress is measured down from.
  !>
  !> legacy `hdam(iblks)`. It is an ELEVATION in mesh coordinates, not a thickness: every
  !> consumer uses the DEPTH below it, `hdam(iblks) - gpcod(ndimn)` (Stiff.f90:801,
  !> Residu.f90:2975, Fem.f90:11156). On the DUNCANCHANG path that depth becomes the
  !> Gauss point's initial vertical stress the first time the point is visited,
  !> `px = (hdam - y) * density * g * ratio`, clamped up to `min_confining_pressure`.
  !>
  !> PER STEP, not per analysis: legacy reads the whole array in one record but indexes it
  !> by block (`hdam(1:nblks)`, Global.f90:1079), and a staged fill is exactly the case
  !> where the surface rises from one block to the next. So the contract writes it under
  !> the step and the step-scope gate classifies it `per_block` -- no cross-step refusal.
  type, public :: initial_stress_t
    !> m, in mesh coordinates.
    type(opt_real) :: fill_elevation       !@off-face: steps0.initial_stress.hdam
  end type initial_stress_t

  type, public :: step_t
    type(opt_text) :: procedure
    type(opt_text) :: load_mode
    type(controls_t) :: controls
    type(boundary_t), allocatable :: boundary(:)
    type(activation_t), allocatable :: activation(:)
    type(load_t) :: load
    type(output_t) :: output
    !> Meaningful only for a model that derives an initial stress from depth; on this
    !> build that is DUNCANCHANG alone, and the profile requires it exactly there.
    type(initial_stress_t) :: initial_stress
  end type step_t

  ! --- root -------------------------------------------------------------------
  ! ADR-0003 top-level shape: case / mesh / materials / sections / amplitudes /
  ! interactions / steps[] / solver. All counts are derived, never stored.

  !> One edge of one face, exactly as legacy writes it down (Load.f90:375-383).
  !>
  !> `element` is stored because legacy stores it: finding the element from the node pair
  !> is topology derivation, and deriving what legacy already states is the mistake this
  !> build has paid for twice (R31, the jacob 1-ULP divergence). `element_class` and
  !> `projection_axis` are legacy's `index` and `vdimn`, per edge, because legacy keeps
  !> them per edge even though its file writes them once per chunk.
  type, public :: surface_edge_t
    integer(int32), allocatable :: nodes(:)  !@off-face: surfaces.edges.lnode
    type(opt_int) :: element                 !@off-face: surfaces.edges.aelem
    type(opt_int) :: element_class           !@off-face: surfaces.edges.index
    type(opt_int) :: projection_axis         !@off-face: surfaces.edges.vdimn
  end type surface_edge_t

  type, public :: problem_state_t
    type(case_t) :: case
    type(mesh_t) :: mesh
    !> Every face's edges, flattened into one table in declaration order, which is what
    !> makes a named face exactly one contiguous range (see pressure_t). One collection
    !> for the whole problem, not one per step: legacy reads the edge table once, "for
    !> whole analysis", and only the LOADS on it are per block.
    type(surface_edge_t), allocatable :: surface_edges(:)
    type(material_t), allocatable :: materials(:)
    type(section_t), allocatable :: sections(:)
    type(amplitude_t), allocatable :: amplitudes(:)
    type(interactions_t) :: interactions
    type(step_t), allocatable :: steps(:)
    type(solver_t) :: solver
  end type problem_state_t

end module yl_problem_types
