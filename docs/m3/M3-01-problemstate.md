# M3-01 ProblemState 逐字段表

由 `python3 tools/yl_problem_check.py render` 生成，请勿手工编辑。
字段名由 `docs/m2/state-field-map.toml` 的 `owner` 路径机械推导；`map id` 为该行的溯源，`M5-only` 表示本阶段无 legacy 槽位。

可选性约定：`required` 在 finalize 后必定已设置；`optional` 未写入时为 unset，写入的零是真实的零；`collection` 区分未分配（unset）与零长（empty）。

字段总数 100，其中已导出映射 98 项。

## case (2 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `case%name` | `type(opt_text)` | 1 | optional | `case.name` | draft | reader |
| `case%units` | `type(opt_text)` | - | optional | M5-only: ADR-0003 mandates an explicit SI unit declaration that no legacy record carries | - | M5 |

## mesh (10 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `mesh%dimension` | `type(opt_int)` | 1 | optional | `mesh.dimension` | draft | reader |
| `mesh%elements(i)%elset` | `type(opt_int)` | id | optional | `mesh.elements.group` | finalized | finalize |
| `mesh%elements(i)%id` | `type(opt_int)` | id | optional | `mesh.elements.id` | draft | reader |
| `mesh%elements(i)%kind` | `type(opt_int)` | 1 | optional | `mesh.elements.kind` | finalized | finalize |
| `mesh%elements(i)%material` | `type(opt_int)` | id | optional | `mesh.elements.material` | draft | reader |
| `mesh%elements(i)%nodes(:)` | `integer(int32), allocatable` | id | collection | `mesh.elements.nodes` | draft | reader |
| `mesh%elsets(i)%elements(:)` | `integer(int32), allocatable` | id | collection | `mesh.sets.elset` | finalized | finalize |
| `mesh%nodes(i)%id` | `type(opt_int)` | id | optional | `mesh.nodes.id` | draft | reader |
| `mesh%nodes(i)%xyz(:)` | `real(real64), allocatable` | m | collection | `mesh.nodes.xyz` | draft | reader |
| `mesh%nsets(i)%nodes(:)` | `integer(int32), allocatable` | id | collection | `mesh.sets.nset` | finalized | finalize |

## materials (13 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `materials(i)%creep_model` | `type(opt_int)` | 1 | optional | `materials.icreep` | draft | reader |
| `materials(i)%density` | `type(opt_real)` | kg/m3 | optional | `materials.density` | draft | reader |
| `materials(i)%E` | `type(opt_real)` | Pa | optional | `materials.E` | draft | reader |
| `materials(i)%id` | `type(opt_int)` | id | optional | `materials.id` | draft | reader |
| `materials(i)%kind` | `type(opt_text)` | 1 | optional | `materials.kind` | draft | reader |
| `materials(i)%liquefaction` | `type(opt_int)` | 1 | optional | `materials.jliqu` | draft | reader |
| `materials(i)%model` | `type(opt_text)` | 1 | optional | `materials.model` | draft | reader |
| `materials(i)%name` | `type(opt_text)` | 1 | optional | `materials.name` | draft | reader |
| `materials(i)%nu` | `type(opt_real)` | 1 | optional | `materials.nu` | draft | reader |
| `materials(i)%phase` | `type(opt_text)` | 1 | optional | `materials.phase` | draft | reader |
| `materials(i)%solid_ratio` | `type(opt_real)` | 1 | optional | `materials.ratio` | draft | reader |
| `materials(i)%thermal_expansion` | `type(opt_real)` | 1/K | optional | `materials.thermal_expansion` | draft | reader |
| `materials(i)%wetting_kind` | `type(opt_int)` | 1 | optional | `materials.kind_wt` | draft | reader |

## sections (17 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `sections(i)%algorithm` | `type(opt_int)` | 1 | optional | `sections.type_nalgo` | draft | reader |
| `sections(i)%class` | `type(opt_text)` | 1 | optional | `sections.class` | draft | reader |
| `sections(i)%element` | `type(opt_text)` | 1 | optional | `sections.element` | draft | reader |
| `sections(i)%element_kind` | `type(opt_int)` | 1 | optional | `sections.element_kind` | draft | reader |
| `sections(i)%fields` | `type(opt_text)` | 1 | optional | `sections.fields` | draft | reader |
| `sections(i)%formulation` | `type(opt_text)` | 1 | optional | `sections.formulation` | draft | reader |
| `sections(i)%layer` | `type(opt_int)` | 1 | optional | `sections.ilayer` | draft | reader |
| `sections(i)%liquefaction` | `type(opt_int)` | 1 | optional | `sections.liquj` | draft | reader |
| `sections(i)%local_axes` | `type(opt_real)` | 1 | optional | `sections.elcod_local` | draft | reader |
| `sections(i)%material` | `type(opt_int)` | id | optional | `sections.material` | finalized | finalize |
| `sections(i)%material_header` | `type(opt_int)` | id | optional | `sections.material_header` | finalized | finalize |
| `sections(i)%name` | `type(opt_text)` | 1 | optional | `sections.name` | draft | reader |
| `sections(i)%special` | `type(opt_text)` | 1 | optional | `sections.special` | draft | reader |
| `sections(i)%stiffness_kind` | `type(opt_int)` | 1 | optional | `sections.type_stiff` | draft | reader |
| `sections(i)%stress_recovery` | `type(opt_int)` | 1 | optional | `sections.type_ecoint` | draft | reader |
| `sections(i)%thickness` | `type(opt_real)` | m | optional | `sections.thickness` | draft | reader |
| `sections(i)%uplift` | `type(opt_int)` | 1 | optional | `sections.uplift_ic` | draft | reader |

## amplitudes (4 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `amplitudes(i)%name` | `type(opt_text)` | - | optional | M5-only: seven map rows index by this amplitude key but the key is never exported as a value | - | M5 |
| `amplitudes(i)%points(j)%time` | `type(opt_real)` | s | optional | `amplitudes.points.time` | draft | reader |
| `amplitudes(i)%points(j)%value` | `type(opt_real)` | 1 | optional | `amplitudes.points.value` | draft | reader |
| `amplitudes(i)%type` | `type(opt_text)` | 1 | optional | `amplitudes.type` | draft | reader |

## interactions (1 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `interactions%absorbing%type` | `type(opt_text)` | 1 | optional | `interactions.absorbing.type` | draft | reader |

## steps (47 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `steps(k)%activation(j)%active` | `type(opt_int)` | 1 | optional | `steps0.activation.active` | draft | reader |
| `steps(k)%activation(j)%material` | `type(opt_int)` | id | optional | `steps0.activation.material` | draft | reader |
| `steps(k)%boundary(j)%amplitude` | `type(opt_int)` | id | optional | `steps0.boundary.amplitude` | draft | reader |
| `steps(k)%boundary(j)%dof` | `type(opt_int)` | 1 | optional | `steps0.boundary.dof` | draft | reader |
| `steps(k)%boundary(j)%name` | `type(opt_int)` | id | optional | `steps0.boundary.set` | draft | reader |
| `steps(k)%boundary(j)%nset` | `type(opt_int)` | id | optional | `steps0.boundary.nodes` | draft | reader |
| `steps(k)%boundary(j)%record_reaction` | `type(opt_int)` | 1 | optional | `steps0.boundary.record_reaction` | draft | reader |
| `steps(k)%boundary(j)%value` | `type(opt_real)` | m | optional | `steps0.boundary.value` | draft | reader |
| `steps(k)%controls%increments` | `type(opt_int)` | 1 | optional | `steps0.controls.increments` | draft | reader |
| `steps(k)%controls%max_iterations` | `type(opt_int)` | 1 | optional | `steps0.controls.max_iterations` | draft | reader |
| `steps(k)%controls%nonlinear_type` | `type(opt_int)` | 1 | optional | `steps0.controls.nonlinear_type` | draft | reader |
| `steps(k)%controls%restart_frequency` | `type(opt_int)` | 1 | optional | `steps0.controls.restart_frequency` | draft | reader |
| `steps(k)%controls%step_increment` | `type(opt_int)` | 1 | optional | `steps0.controls.step_increment` | draft | reader |
| `steps(k)%controls%steps` | `type(opt_int)` | 1 | optional | `steps0.controls.steps` | draft | reader |
| `steps(k)%controls%time_increment` | `type(opt_real)` | s | optional | `steps0.controls.time_increment` | draft | reader |
| `steps(k)%controls%tolerance_dof(:)` | `real(real64), allocatable` | m | collection | `steps0.controls.tolerance_dof` | draft | reader |
| `steps(k)%controls%tolerance_force` | `type(opt_real)` | N | optional | `steps0.controls.tolerance_force` | draft | reader |
| `steps(k)%load%gravity%amplitude(:)` | `integer(int32), allocatable` | id | collection | `steps0.load.gravity.amplitude` | draft | reader |
| `steps(k)%load%gravity%direction(:)` | `real(real64), allocatable` | 1 | collection | `steps0.load.gravity.direction` | draft | reader |
| `steps(k)%load%gravity%enabled` | `type(opt_int)` | 1 | optional | `steps0.load.gravity.enabled` | draft | reader |
| `steps(k)%load%gravity%magnitude` | `type(opt_real)` | m/s2 | optional | `steps0.load.gravity.magnitude` | draft | reader |
| `steps(k)%load_mode` | `type(opt_text)` | 1 | optional | `steps0.load_mode` | draft | reader |
| `steps(k)%output%field%a` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_a` | draft | reader |
| `steps(k)%output%field%bcs` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_bcs` | draft | reader |
| `steps(k)%output%field%bem` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_bem` | draft | reader |
| `steps(k)%output%field%ep` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_ep` | draft | reader |
| `steps(k)%output%field%f` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_f` | draft | reader |
| `steps(k)%output%field%FC` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_FC` | draft | reader |
| `steps(k)%output%field%ms` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_ms` | draft | reader |
| `steps(k)%output%field%Mxy` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_Mxy` | draft | reader |
| `steps(k)%output%field%Ns` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_Ns` | draft | reader |
| `steps(k)%output%field%P` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_P` | draft | reader |
| `steps(k)%output%field%Pv` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_Pv` | draft | reader |
| `steps(k)%output%field%rot` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_rot` | draft | reader |
| `steps(k)%output%field%s` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_s` | draft | reader |
| `steps(k)%output%field%Ss` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_Ss` | draft | reader |
| `steps(k)%output%field%T` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_T` | draft | reader |
| `steps(k)%output%field%u` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_u` | draft | reader |
| `steps(k)%output%field%v` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_v` | draft | reader |
| `steps(k)%output%field%wh` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_wh` | draft | reader |
| `steps(k)%output%field%wv` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_wv` | draft | reader |
| `steps(k)%output%field%Y` | `type(opt_int)` | 1 | optional | `steps0.output.field.gid_Y` | draft | reader |
| `steps(k)%output%format` | `type(opt_text)` | 1 | optional | `steps0.output.format` | draft | reader |
| `steps(k)%output%frequency%fields` | `type(opt_int)` | 1 | optional | `steps0.output.frequency_fields` | draft | reader |
| `steps(k)%output%frequency%nodes` | `type(opt_int)` | 1 | optional | `steps0.output.frequency_nodes` | draft | reader |
| `steps(k)%output%stress_averaging(:)` | `integer(int32), allocatable` | 1 | collection | `steps0.output.stress_averaging` | draft | reader |
| `steps(k)%procedure` | `type(opt_text)` | 1 | optional | `steps0.procedure` | draft | reader |

## solver (6 fields)

| field | type | unit | optionality | map id | lifecycle | owner |
|---|---|---|---|---|---|---|
| `solver%linear` | `type(opt_text)` | 1 | optional | `solver.linear` | draft | reader |
| `solver%profile%condition_check` | `type(opt_int)` | 1 | optional | `solver.profile.icond` | draft | reader |
| `solver%profile%pivot_file` | `type(opt_int)` | 1 | optional | `solver.profile.iafile` | draft | reader |
| `solver%profile%positive_definite_check` | `type(opt_int)` | 1 | optional | `solver.profile.ipdchk` | draft | reader |
| `solver%profile%singularity_check` | `type(opt_int)` | 1 | optional | `solver.profile.ising` | draft | reader |
| `solver%symmetric` | `type(opt_logical)` | 1 | optional | `solver.symmetric` | draft | reader |

