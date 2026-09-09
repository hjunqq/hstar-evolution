! yl_diag_registry -- reader registry constants for the legacy YL solver (M1-02).
!
! GENERATED FILE -- DO NOT EDIT BY HAND.
! Source : docs/m1/reader-inventory.toml
! Command: python3 tools/yl_io_inventory.py gen-fortran
!
! One entry per [[reader]] in inventory order (idx from 1). Source code refers
! to a reader only through its RD_<id> integer constant; `check` verifies that
! every constant referenced from legacy/yl exists here. STAGE is the inventory
! `phase` text; reached_only entries carry stage 'reached_only' and seq 0.
module yl_diag_registry
  implicit none
  public

  integer, parameter :: YL_NREADERS = 157
  integer, parameter :: YL_LEN_READER_ID = 96
  integer, parameter :: YL_LEN_READER_SITE = 32
  integer, parameter :: YL_LEN_READER_FILE = 16
  integer, parameter :: YL_LEN_READER_UNIT = 24
  integer, parameter :: YL_LEN_READER_STAGE = 24
  integer, parameter :: YL_LEN_READER_FIELD = 256

  ! --- per-reader index constants ---------------------------------------------
  integer, parameter :: RD_INP_FEM90_title_1 = 1
  integer, parameter :: RD_INP_FEM90_run_control = 2
  integer, parameter :: RD_INP_FEM90_title_2 = 3
  integer, parameter :: RD_INP_FEM90_problem_name = 4
  integer, parameter :: RD_GLB_global_data_title_1 = 5
  integer, parameter :: RD_GLB_global_data_sizes_and_switches = 6
  integer, parameter :: RD_GLB_global_data_title_2 = 7
  integer, parameter :: RD_GLB_global_data_reached_only_Global_691 = 8
  integer, parameter :: RD_GLB_global_data_title_3 = 9
  integer, parameter :: RD_GLB_global_data_title_4 = 10
  integer, parameter :: RD_GLB_global_data_init_and_blocks = 11
  integer, parameter :: RD_GLB_global_data_title_5 = 12
  integer, parameter :: RD_GLB_global_data_problem_type = 13
  integer, parameter :: RD_GLB_global_data_title_6 = 14
  integer, parameter :: RD_GLB_global_data_reached_only_Global_772 = 15
  integer, parameter :: RD_GLB_global_data_title_7 = 16
  integer, parameter :: RD_GLB_global_data_material_class_counts = 17
  integer, parameter :: RD_GLB_global_data_title_8 = 18
  integer, parameter :: RD_GLB_global_data_title_9 = 19
  integer, parameter :: RD_GLB_global_data_special_counts = 20
  integer, parameter :: RD_FTR_global_data_title_1 = 21
  integer, parameter :: RD_FTR_global_data_force_counts = 22
  integer, parameter :: RD_GLB_global_data_title_10 = 23
  integer, parameter :: RD_GLB_global_data_mdofn = 24
  integer, parameter :: RD_GLB_global_data_lmdofn = 25
  integer, parameter :: RD_GLB_global_data_order_time_mdofn = 26
  integer, parameter :: RD_GLB_global_data_title_11 = 27
  integer, parameter :: RD_GLB_global_data_newmark = 28
  integer, parameter :: RD_GLB_global_data_title_12 = 29
  integer, parameter :: RD_GLB_global_data_equvs_process = 30
  integer, parameter :: RD_GLB_global_data_title_13 = 31
  integer, parameter :: RD_GLB_global_data_appear_level = 32
  integer, parameter :: RD_GLB_global_data_title_14 = 33
  integer, parameter :: RD_GLB_global_data_appear_process = 34
  integer, parameter :: RD_GLB_global_data_title_15 = 35
  integer, parameter :: RD_GLB_global_data_matno_process = 36
  integer, parameter :: RD_GLB_global_data_title_16 = 37
  integer, parameter :: RD_GLB_global_data_force_process = 38
  integer, parameter :: RD_GLB_global_data_title_17 = 39
  integer, parameter :: RD_GLB_global_data_average_appear = 40
  integer, parameter :: RD_GLB_global_data_title_18 = 41
  integer, parameter :: RD_GLB_global_data_gid_flags = 42
  integer, parameter :: RD_GLB_global_data_title_19 = 43
  integer, parameter :: RD_GLB_global_data_res_flags = 44
  integer, parameter :: RD_GLB_global_data_title_20 = 45
  integer, parameter :: RD_GLB_global_data_fsi_params = 46
  integer, parameter :: RD_GLB_global_data_title_21 = 47
  integer, parameter :: RD_GLB_global_data_crack_and_beam = 48
  integer, parameter :: RD_GLB_global_data_title_22 = 49
  integer, parameter :: RD_GLB_global_data_transform_and_mif = 50
  integer, parameter :: RD_GLB_global_data_title_23 = 51
  integer, parameter :: RD_GLB_global_data_hdam = 52
  integer, parameter :: RD_GLB_global_data_title_24 = 53
  integer, parameter :: RD_GLB_global_data_water_level = 54
  integer, parameter :: RD_GLB_global_data_title_25 = 55
  integer, parameter :: RD_GLB_global_data_modf_dis_blocks = 56
  integer, parameter :: RD_GLB_global_data_title_26 = 57
  integer, parameter :: RD_GLB_global_data_uinitial = 58
  integer, parameter :: RD_GLB_global_data_title_27 = 59
  integer, parameter :: RD_GLB_global_data_title_28 = 60
  integer, parameter :: RD_GLB_global_data_title_29 = 61
  integer, parameter :: RD_COR_global_data_node_coordinates = 62
  integer, parameter :: RD_GLB_global_data_title_30 = 63
  integer, parameter :: RD_GLB_global_data_title_31 = 64
  integer, parameter :: RD_GLB_global_data_title_32 = 65
  integer, parameter :: RD_GLB_global_data_title_33 = 66
  integer, parameter :: RD_GLB_global_data_title_34 = 67
  integer, parameter :: RD_GLB_global_data_group_header = 68
  integer, parameter :: RD_GLB_global_data_group_mass_damping = 69
  integer, parameter :: RD_GLB_global_data_group_order_time = 70
  integer, parameter :: RD_GLB_global_data_group_nfdof = 71
  integer, parameter :: RD_GLB_global_data_group_listdof = 72
  integer, parameter :: RD_ELE_read_element_element_connectivity = 73
  integer, parameter :: RD_NRT_global_data_title_1 = 74
  integer, parameter :: RD_NRT_global_data_title_2 = 75
  integer, parameter :: RD_NRT_global_data_transgroup = 76
  integer, parameter :: RD_GLB_global_data_title_35 = 77
  integer, parameter :: RD_GLB_global_data_tension_joint_count = 78
  integer, parameter :: RD_GLB_global_data_title_36 = 79
  integer, parameter :: RD_GLB_global_data_contact_joint_count = 80
  integer, parameter :: RD_INP_FEM90_runblks = 81
  integer, parameter :: RD_MAT_material_set_title_1 = 82
  integer, parameter :: RD_MAT_material_set_curve_count = 83
  integer, parameter :: RD_MAT_material_set_comment_line_count = 84
  integer, parameter :: RD_MAT_material_set_comment_line_1 = 85
  integer, parameter :: RD_MAT_material_set_title_2 = 86
  integer, parameter :: RD_MAT_material_set_nmats = 87
  integer, parameter :: RD_MAT_material_set_title_3 = 88
  integer, parameter :: RD_MAT_material_set_material_header = 89
  integer, parameter :: RD_MAT_material_set_material_nphase = 90
  integer, parameter :: RD_MAT_material_set_material_phase = 91
  integer, parameter :: RD_MAT_material_set_elastic_isotropic = 92
  integer, parameter :: RD_MAT_material_set_elastic_extra = 93
  integer, parameter :: RD_GLB_contact_point_to_point_title_1 = 94
  integer, parameter :: RD_GLB_contact_point_to_point_contact_control = 95
  integer, parameter :: RD_GLB_link_concrete_and_steel_title_1 = 96
  integer, parameter :: RD_GLB_link_concrete_and_steel_rc_steel_count = 97
  integer, parameter :: RD_GLB_link_concrete_and_water_pipe_title_1 = 98
  integer, parameter :: RD_GLB_link_concrete_and_water_pipe_water_pipe_count = 99
  integer, parameter :: RD_IFS_stiff_interface_fluid_solid_title_1 = 100
  integer, parameter :: RD_IFS_stiff_interface_fluid_solid_ifs_group_count = 101
  integer, parameter :: RD_IFS_stiff_absorb_fluid_title_1 = 102
  integer, parameter :: RD_IFS_stiff_absorb_fluid_absorb_fluid_count = 103
  integer, parameter :: RD_IFS_stiff_absorb_solid_title_1 = 104
  integer, parameter :: RD_IFS_stiff_absorb_solid_absorb_solid_count = 105
  integer, parameter :: RD_IFS_stiff_ifs2006_title_1 = 106
  integer, parameter :: RD_IFS_stiff_ifs2006_ifs_edge_count = 107
  integer, parameter :: RD_OPR_output_read_title_1 = 108
  integer, parameter :: RD_OPR_output_read_title_2 = 109
  integer, parameter :: RD_OPR_output_read_output_control = 110
  integer, parameter :: RD_OPR_output_read_title_3 = 111
  integer, parameter :: RD_OPR_output_read_title_4 = 112
  integer, parameter :: RD_OPR_output_read_label1_title = 113
  integer, parameter :: RD_OPR_output_read_label2_title = 114
  integer, parameter :: RD_OPR_output_read_label3_title = 115
  integer, parameter :: RD_LOA_external_load_1_title_1 = 116
  integer, parameter :: RD_LOA_external_load_1_curve_count = 117
  integer, parameter :: RD_LOA_external_load_1_curve_header = 118
  integer, parameter :: RD_LOA_external_load_1_curve_points = 119
  integer, parameter :: RD_LOA_external_load_1_curve_factors = 120
  integer, parameter :: RD_LOA_external_load_1_title_2 = 121
  integer, parameter :: RD_LOA_external_load_1_point_load_count = 122
  integer, parameter :: RD_LOA_external_load_1_title_3 = 123
  integer, parameter :: RD_LOA_external_load_1_edge_count = 124
  integer, parameter :: RD_PRE_prescrib_set_title_1 = 125
  integer, parameter :: RD_PRE_prescrib_set_set_count = 126
  integer, parameter :: RD_PRE_prescrib_set_reached_only_Prescrib_213 = 127
  integer, parameter :: RD_PRE_prescrib_set_set_header = 128
  integer, parameter :: RD_PRE_prescrib_set_set_nodes = 129
  integer, parameter :: RD_PRE_prescrib_set_set_values = 130
  integer, parameter :: RD_LOA_external_load_2_title_1 = 131
  integer, parameter :: RD_LOA_external_load_2_title_2 = 132
  integer, parameter :: RD_LOA_external_load_2_edge_load_groups = 133
  integer, parameter :: RD_LOA_external_load_2_title_3 = 134
  integer, parameter :: RD_LOA_external_load_2_gravity = 135
  integer, parameter :: RD_LOA_external_load_2_gravity_curve_title = 136
  integer, parameter :: RD_LOA_external_load_2_gravity_curves = 137
  integer, parameter :: RD_LOA_external_load_2_title_4 = 138
  integer, parameter :: RD_LOA_external_load_2_beam_load_count = 139
  integer, parameter :: RD_LOA_external_load_2_title_5 = 140
  integer, parameter :: RD_LOA_external_load_2_plate_load_count = 141
  integer, parameter :: RD_TEM_boundt_title_1 = 142
  integer, parameter :: RD_TEM_boundt_temp_surface_count = 143
  integer, parameter :: RD_TEM_boundt_title_2 = 144
  integer, parameter :: RD_TEM_boundt_temp_edge_count = 145
  integer, parameter :: RD_TEM_boundt_label11_title = 146
  integer, parameter :: RD_TEM_boundt_title_3 = 147
  integer, parameter :: RD_TEM_boundt_temp_elgroup_count = 148
  integer, parameter :: RD_TEM_boundt_title_4 = 149
  integer, parameter :: RD_TEM_boundt_title_5 = 150
  integer, parameter :: RD_TEM_boundt_pipe_count = 151
  integer, parameter :: RD_SOL_PROFILE_title_1 = 152
  integer, parameter :: RD_SOL_PROFILE_profile_control = 153
  integer, parameter :: RD_MAN_STATIC_U_title_1 = 154
  integer, parameter :: RD_MAN_STATIC_U_nincs = 155
  integer, parameter :: RD_MAN_STATIC_U_increment_control = 156
  integer, parameter :: RD_MAN_STATIC_U_tolerances = 157

  character(len=96), parameter :: YL_READER_ID(YL_NREADERS) = [character(len=96) :: &
    'INP.FEM90.title#1', &
    'INP.FEM90.run_control', &
    'INP.FEM90.title#2', &
    'INP.FEM90.problem_name', &
    'GLB.global_data.title#1', &
    'GLB.global_data.sizes_and_switches', &
    'GLB.global_data.title#2', &
    'GLB.global_data.reached_only_Global_691', &
    'GLB.global_data.title#3', &
    'GLB.global_data.title#4', &
    'GLB.global_data.init_and_blocks', &
    'GLB.global_data.title#5', &
    'GLB.global_data.problem_type', &
    'GLB.global_data.title#6', &
    'GLB.global_data.reached_only_Global_772', &
    'GLB.global_data.title#7', &
    'GLB.global_data.material_class_counts', &
    'GLB.global_data.title#8', &
    'GLB.global_data.title#9', &
    'GLB.global_data.special_counts', &
    'FTR.global_data.title#1', &
    'FTR.global_data.force_counts', &
    'GLB.global_data.title#10', &
    'GLB.global_data.mdofn', &
    'GLB.global_data.lmdofn', &
    'GLB.global_data.order_time_mdofn', &
    'GLB.global_data.title#11', &
    'GLB.global_data.newmark', &
    'GLB.global_data.title#12', &
    'GLB.global_data.equvs_process', &
    'GLB.global_data.title#13', &
    'GLB.global_data.appear_level', &
    'GLB.global_data.title#14', &
    'GLB.global_data.appear_process', &
    'GLB.global_data.title#15', &
    'GLB.global_data.matno_process', &
    'GLB.global_data.title#16', &
    'GLB.global_data.force_process', &
    'GLB.global_data.title#17', &
    'GLB.global_data.average_appear', &
    'GLB.global_data.title#18', &
    'GLB.global_data.gid_flags', &
    'GLB.global_data.title#19', &
    'GLB.global_data.res_flags', &
    'GLB.global_data.title#20', &
    'GLB.global_data.fsi_params', &
    'GLB.global_data.title#21', &
    'GLB.global_data.crack_and_beam', &
    'GLB.global_data.title#22', &
    'GLB.global_data.transform_and_mif', &
    'GLB.global_data.title#23', &
    'GLB.global_data.hdam', &
    'GLB.global_data.title#24', &
    'GLB.global_data.water_level', &
    'GLB.global_data.title#25', &
    'GLB.global_data.modf_dis_blocks', &
    'GLB.global_data.title#26', &
    'GLB.global_data.uinitial', &
    'GLB.global_data.title#27', &
    'GLB.global_data.title#28', &
    'GLB.global_data.title#29', &
    'COR.global_data.node_coordinates', &
    'GLB.global_data.title#30', &
    'GLB.global_data.title#31', &
    'GLB.global_data.title#32', &
    'GLB.global_data.title#33', &
    'GLB.global_data.title#34', &
    'GLB.global_data.group_header', &
    'GLB.global_data.group_mass_damping', &
    'GLB.global_data.group_order_time', &
    'GLB.global_data.group_nfdof', &
    'GLB.global_data.group_listdof', &
    'ELE.read_element.element_connectivity', &
    'NRT.global_data.title#1', &
    'NRT.global_data.title#2', &
    'NRT.global_data.transgroup', &
    'GLB.global_data.title#35', &
    'GLB.global_data.tension_joint_count', &
    'GLB.global_data.title#36', &
    'GLB.global_data.contact_joint_count', &
    'INP.FEM90.runblks', &
    'MAT.material_set.title#1', &
    'MAT.material_set.curve_count', &
    'MAT.material_set.comment_line_count', &
    'MAT.material_set.comment_line#1', &
    'MAT.material_set.title#2', &
    'MAT.material_set.nmats', &
    'MAT.material_set.title#3', &
    'MAT.material_set.material_header', &
    'MAT.material_set.material_nphase', &
    'MAT.material_set.material_phase', &
    'MAT.material_set.elastic_isotropic', &
    'MAT.material_set.elastic_extra', &
    'GLB.contact_point_to_point.title#1', &
    'GLB.contact_point_to_point.contact_control', &
    'GLB.link_concrete_and_steel.title#1', &
    'GLB.link_concrete_and_steel.rc_steel_count', &
    'GLB.link_concrete_and_water_pipe.title#1', &
    'GLB.link_concrete_and_water_pipe.water_pipe_count', &
    'IFS.stiff_interface_fluid_solid.title#1', &
    'IFS.stiff_interface_fluid_solid.ifs_group_count', &
    'IFS.stiff_absorb_fluid.title#1', &
    'IFS.stiff_absorb_fluid.absorb_fluid_count', &
    'IFS.stiff_absorb_solid.title#1', &
    'IFS.stiff_absorb_solid.absorb_solid_count', &
    'IFS.stiff_ifs2006.title#1', &
    'IFS.stiff_ifs2006.ifs_edge_count', &
    'OPR.output_read.title#1', &
    'OPR.output_read.title#2', &
    'OPR.output_read.output_control', &
    'OPR.output_read.title#3', &
    'OPR.output_read.title#4', &
    'OPR.output_read.label1_title', &
    'OPR.output_read.label2_title', &
    'OPR.output_read.label3_title', &
    'LOA.external_load_1.title#1', &
    'LOA.external_load_1.curve_count', &
    'LOA.external_load_1.curve_header', &
    'LOA.external_load_1.curve_points', &
    'LOA.external_load_1.curve_factors', &
    'LOA.external_load_1.title#2', &
    'LOA.external_load_1.point_load_count', &
    'LOA.external_load_1.title#3', &
    'LOA.external_load_1.edge_count', &
    'PRE.prescrib_set.title#1', &
    'PRE.prescrib_set.set_count', &
    'PRE.prescrib_set.reached_only_Prescrib_213', &
    'PRE.prescrib_set.set_header', &
    'PRE.prescrib_set.set_nodes', &
    'PRE.prescrib_set.set_values', &
    'LOA.external_load_2.title#1', &
    'LOA.external_load_2.title#2', &
    'LOA.external_load_2.edge_load_groups', &
    'LOA.external_load_2.title#3', &
    'LOA.external_load_2.gravity', &
    'LOA.external_load_2.gravity_curve_title', &
    'LOA.external_load_2.gravity_curves', &
    'LOA.external_load_2.title#4', &
    'LOA.external_load_2.beam_load_count', &
    'LOA.external_load_2.title#5', &
    'LOA.external_load_2.plate_load_count', &
    'TEM.boundt.title#1', &
    'TEM.boundt.temp_surface_count', &
    'TEM.boundt.title#2', &
    'TEM.boundt.temp_edge_count', &
    'TEM.boundt.label11_title', &
    'TEM.boundt.title#3', &
    'TEM.boundt.temp_elgroup_count', &
    'TEM.boundt.title#4', &
    'TEM.boundt.title#5', &
    'TEM.boundt.pipe_count', &
    'SOL.PROFILE.title#1', &
    'SOL.PROFILE.profile_control', &
    'MAN.STATIC_U.title#1', &
    'MAN.STATIC_U.nincs', &
    'MAN.STATIC_U.increment_control', &
    'MAN.STATIC_U.tolerances' &
    ]

  character(len=32), parameter :: YL_READER_SITE(YL_NREADERS) = [character(len=32) :: &
    'Fem.f90:97', &
    'Fem.f90:99', &
    'Fem.f90:101', &
    'Fem.f90:103', &
    'Global.f90:691', &
    'Global.f90:694', &
    'Global.f90:720', &
    'Global.f90:722', &
    'Global.f90:725', &
    'Global.f90:759', &
    'Global.f90:762', &
    'Global.f90:786', &
    'Global.f90:789', &
    'Global.f90:807', &
    'Global.f90:810', &
    'Global.f90:812', &
    'Global.f90:815', &
    'Global.f90:818', &
    'Global.f90:830', &
    'Global.f90:833', &
    'Global.f90:878', &
    'Global.f90:880', &
    'Global.f90:948', &
    'Global.f90:950', &
    'Global.f90:955', &
    'Global.f90:957', &
    'Global.f90:959', &
    'Global.f90:961', &
    'Global.f90:973', &
    'Global.f90:976', &
    'Global.f90:980', &
    'Global.f90:983', &
    'Global.f90:985', &
    'Global.f90:989', &
    'Global.f90:994', &
    'Global.f90:998', &
    'Global.f90:1012', &
    'Global.f90:1015', &
    'Global.f90:1021', &
    'Global.f90:1023', &
    'Global.f90:1025', &
    'Global.f90:1027', &
    'Global.f90:1030', &
    'Global.f90:1032', &
    'Global.f90:1056', &
    'Global.f90:1058', &
    'Global.f90:1060', &
    'Global.f90:1062', &
    'Global.f90:1073', &
    'Global.f90:1075', &
    'Global.f90:1077', &
    'Global.f90:1079', &
    'Global.f90:1082', &
    'Global.f90:1084', &
    'Global.f90:1087', &
    'Global.f90:1089', &
    'Global.f90:1091', &
    'Global.f90:1093', &
    'Global.f90:1099', &
    'Global.f90:1140', &
    'Global.f90:1155', &
    'Global.f90:1176', &
    'Global.f90:1192', &
    'Global.f90:1195', &
    'Global.f90:1197', &
    'Global.f90:1199', &
    'Global.f90:1201', &
    'Global.f90:1216', &
    'Global.f90:1242', &
    'Global.f90:1245', &
    'Global.f90:1255', &
    'Global.f90:1263', &
    'Elements.f90:1087', &
    'Global.f90:1492', &
    'Global.f90:1494', &
    'Global.f90:1496', &
    'Global.f90:1809', &
    'Global.f90:1812', &
    'Global.f90:1826', &
    'Global.f90:1829', &
    'Fem.f90:185', &
    'Material.f90:243', &
    'Material.f90:245', &
    'Material.f90:261', &
    'Material.f90:264', &
    'Material.f90:270', &
    'Material.f90:272', &
    'Material.f90:281', &
    'Material.f90:283', &
    'Material.f90:298', &
    'Material.f90:302', &
    'Material.f90:310', &
    'Material.f90:313', &
    'Global.f90:3466', &
    'Global.f90:3469', &
    'Global.f90:4678', &
    'Global.f90:4681', &
    'Global.f90:4542', &
    'Global.f90:4545', &
    'Stiff.f90:10216', &
    'Stiff.f90:10218', &
    'Stiff.f90:10320', &
    'Stiff.f90:10322', &
    'Stiff.f90:10419', &
    'Stiff.f90:10421', &
    'Stiff.f90:9581', &
    'Stiff.f90:9583', &
    'Output.f90:4154', &
    'Output.f90:4156', &
    'Output.f90:4159', &
    'Output.f90:4163', &
    'Output.f90:4165', &
    'Output.f90:4301', &
    'Output.f90:4327', &
    'Output.f90:4353', &
    'Load.f90:143', &
    'Load.f90:145', &
    'Load.f90:156', &
    'Load.f90:220', &
    'Load.f90:231', &
    'Load.f90:240', &
    'Load.f90:242', &
    'Load.f90:364', &
    'Load.f90:366', &
    'Prescrib.f90:211', &
    'Prescrib.f90:213', &
    'Prescrib.f90:218', &
    'Prescrib.f90:220', &
    'Prescrib.f90:235', &
    'Prescrib.f90:242', &
    'Load.f90:750', &
    'Load.f90:752', &
    'Load.f90:755', &
    'Load.f90:911', &
    'Load.f90:913', &
    'Load.f90:920', &
    'Load.f90:922', &
    'Load.f90:932', &
    'Load.f90:934', &
    'Load.f90:1013', &
    'Load.f90:1015', &
    'Temper.f90:124', &
    'Temper.f90:126', &
    'Temper.f90:152', &
    'Temper.f90:154', &
    'Temper.f90:243', &
    'Temper.f90:245', &
    'Temper.f90:247', &
    'Temper.f90:306', &
    'Temper.f90:308', &
    'Temper.f90:311', &
    'Solver.f90:6829', &
    'Solver.f90:6831', &
    'Fem.f90:3593', &
    'Fem.f90:3595', &
    'Fem.f90:3627', &
    'Fem.f90:3633' &
    ]

  character(len=16), parameter :: YL_READER_FILE(YL_NREADERS) = [character(len=16) :: &
    'inp', &
    'inp', &
    'inp', &
    'inp', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.ftr', &
    '.ftr', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.cor', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.ele', &
    '.nrt', &
    '.nrt', &
    '.nrt', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    'inp', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.mat', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.glb', &
    '.ifs', &
    '.ifs', &
    '.ifs', &
    '.ifs', &
    '.ifs', &
    '.ifs', &
    '.ifs', &
    '.ifs', &
    '.opr', &
    '.opr', &
    '.opr', &
    '.opr', &
    '.opr', &
    '.opr', &
    '.opr', &
    '.opr', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.pre', &
    '.pre', &
    '.pre', &
    '.pre', &
    '.pre', &
    '.pre', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.loa', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.tem', &
    '.sol', &
    '.sol', &
    '.man', &
    '.man', &
    '.man', &
    '.man' &
    ]

  character(len=24), parameter :: YL_READER_UNIT(YL_NREADERS) = [character(len=24) :: &
    'inpunit', &
    'inpunit', &
    'inpunit', &
    'inpunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'ftfread', &
    'ftfread', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'cunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'iunit', &
    'nrtunit', &
    'nrtunit', &
    'nrtunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'inpunit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'munit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'gunit', &
    'ifsunit', &
    'ifsunit', &
    'ifsunit', &
    'ifsunit', &
    'ifsunit', &
    'ifsunit', &
    'ifsunit', &
    'ifsunit', &
    'outpread', &
    'outpread', &
    'outpread', &
    'outpread', &
    'outpread', &
    'outpread', &
    'outpread', &
    'outpread', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'punit', &
    'punit', &
    'punit', &
    'punit', &
    'punit', &
    'punit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'loadunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'tunit', &
    'solveunit', &
    'solveunit', &
    'mainunit', &
    'mainunit', &
    'mainunit', &
    'mainunit' &
    ]

  character(len=24), parameter :: YL_READER_STAGE(YL_NREADERS) = [character(len=24) :: &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'reached_only', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'reached_only', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'reached_only', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'startup', &
    'solver_lazy', &
    'solver_lazy', &
    'phase_lazy(1)', &
    'phase_lazy(1)', &
    'increment_lazy(1,1)', &
    'increment_lazy(1,1)' &
    ]

  character(len=256), parameter :: YL_READER_FIELD(YL_NREADERS) = [character(len=256) :: &
    'text:str', &
    'restart:int,relis:int,sysrelis:int,ADINA:int,Uopt_R:int,gamamax:int', &
    'text:str', &
    'probn:str', &
    'text:str', &
    'npoin:int:derived(mesh.nodes),npoinb:int:derived,nelem:int:derived(mesh.elements),ndimn:int:mesh&
    &.dimension,nmats:int:derived(materials),ngroup:int:derived(sections),ntlink:int:unused_switch,ou&
    &tplot:str:output_control,kstab:real:unused_switch,mat_curve:int:', &
    'text:str', &
    '', &
    'text:str', &
    'text:str', &
    'ninit:int:unused_switch,kinit:int:unused_switch,winit:int:unused_switch,nblks:int:derived(steps)&
    &,nlinks:int:unused_switch,nonsym:int:solver.symmetric,outinp:int:output_control,outintr:int:outp&
    &ut_control,outintw:int:output_control,neuman:int:unused_switch,e', &
    'text:str', &
    'type_problem:str:steps[0].procedure,type_solver:str:solver.linear,type_load:str:steps[0].load_mo&
    &de,type_nl:int:steps[0].controls,stabpw:int:unused_switch,nlayer:int:unused_switch,kglb:int:unus&
    &ed_switch,state_change:int:unused_switch,Bparameter:int:unused_s', &
    'text:str', &
    '', &
    'text:str', &
    'nmass:int:unused_switch,nsmat:int:derived,nhmat:int:unused_switch,nqmat:int:unused_switch,nldfl:&
    &int:unused_switch,kgmat:int:unused_switch,nswkw:int:unused_switch,uwcpl:int:unused_switch,NGRAV:&
    &int:steps[0].load(gravity),nflow:int:unused_switch,ECWPIPE:int:u', &
    'text:str', &
    'text:str', &
    'ntsmat:int:unused_switch,nthmat:int:unused_switch,kstat:int:unused_switch,ground_inf:int:unused_&
    &switch,src:int:unused_switch,nextrf:int:unused_switch,submodel:int:unused_switch', &
    'text:str', &
    'nforce:int,ngaps:int,nforce_gaps:int,nsafety_gaps:int', &
    'text:str', &
    'mdofn:int', &
    'lmdofn[1:mdofn]:int', &
    'order_time_mdofn[1:mdofn]:int', &
    'text:str', &
    'beeta1:real,beeta2:real,theta1:real', &
    'text:str', &
    'equvs_process[1:ngroup]:int', &
    'text:str', &
    'appear_level[1:ngroup]:int', &
    'text:str', &
    'appear_process[1:ngroup,iblk]:int', &
    'text:str', &
    'matno_process[1:ngroup,iblk]:int', &
    'text:str', &
    'force_process[1:ngroup]:int', &
    'text:str', &
    'average_appear[1:ngroup]:int', &
    'text:str', &
    'gid_u:int,gid_s:int,gid_ms:int,gid_f:int,gid_rot:int,gid_v:int,gid_a:int,gid_T:int,gid_P:int,gid&
    &_Pv:int,gid_ep:int,gid_Y:int,gid_FC:int,gid_Ns:int,gid_Ss:int,gid_Mxy:int,gid_bem:int,gid_wh:int&
    &,gid_wv:int,gid_bcs:int', &
    'text:str', &
    'res_u:int,res_s:int,res_ms:int,res_f:int,res_rot:int,res_v:int,res_a:int,res_T:int,res_P:int,res&
    &_Pv:int,res_ep:int,res_Y:int,res_FC:int,res_Ns:int,res_Ss:int,res_Tv:int,res_Pa:int', &
    'text:str', &
    'Icaddmass:int,swlifs2006:real,toth:real,ifswater:int,ifsgravity:real,absorb:real,alfa_p4:real,st&
    &iff_p4:real', &
    'text:str', &
    'ftcrack:real,coefMpa:real,ikindks:int,doubsig:int,ktan1:real,ktan2:real,nlocalbeam:int,ndimnrt:i&
    &nt,listglocbeam[1:nlocalbeam]:int,lelenrt[1:ndimnrt]:int', &
    'text:str', &
    'ntrans:int,nlaymif:int,epsMIFb:real,gamaMIF:real,ifixvar0_inpb:int,camif:real,dxmif:real', &
    'text:str', &
    'hdam[1:nblks]:real', &
    'text:str', &
    'water_level[1:nblks]:real', &
    'text:str', &
    'modf_dis_blocks[1:nblks]:int', &
    'text:str', &
    'uinitial[1:nblks]:int', &
    'text:str', &
    'text:str', &
    'text:str', &
    'i0:int:mesh.nodes[].id,coord[1:ndimn]:real:mesh.nodes[].xyz', &
    'text:str', &
    'text:str', &
    'text:str', &
    'text:str', &
    'text:str', &
    'name:str:sections[].element,kname:str:sections[].name,index:int:sections[].element_kind,class:st&
    &r:sections[].class,nrfields:int:derived,fieldid:str:sections[].fields,special:str,sptype:str:sec&
    &tions[].formulation,nelgroup:int:derived(elset size),matno:int:s', &
    'type_mass[1:nrfields]:int,alfa:real,beta:real', &
    'order_time[:,1:nrfields]:int', &
    'nfdof:int', &
    'listdof_f[1:nfdof]:int', &
    'i0:int:mesh.elements[].id,lnods[1:nnode]:int:mesh.elements[].nodes', &
    'text:str', &
    'text:str', &
    'transgroup:int', &
    'text:str', &
    'tsel:int', &
    'text:str', &
    'tsel:int', &
    'runblks:int', &
    'text:str', &
    'nscurve:int', &
    'nline:int', &
    'text:str', &
    'text:str', &
    'mmats:int', &
    'text:str', &
    'property:str:materials[].kind,name:str:materials[].name,imat:int:materials[].id', &
    'nphase:int', &
    'phase:str', &
    'material:str:materials[].model,density:real:materials[].density,ratio:real,thickness:real:sectio&
    &ns[].thickness,e:real:materials[].E,nu:real:materials[].nu,alfa:real:materials[].thermal_expansi&
    &on,icreep:int,kind_wt:int,jliqu:int', &
    'iE:int,iNu:int,density_w:real', &
    'text:str', &
    'ngaps:int,ngapb:int,contactpe:int,miter_bt:int,tor_bt:real,iblks_bt:int,nonsbt:int,xlwsol:int,me&
    &thod_gapi:int,miter_state:int,type_solver_ctt:str,restart_ctt:int,damp_ctt:real,istatec:int', &
    'text:str', &
    'nrcsteel:int', &
    'text:str', &
    'nwcpipe:int', &
    'text:str', &
    'nifsgroup:int', &
    'text:str', &
    'nabsfgroup:int', &
    'text:str', &
    'nabssgroup:int,exx:real,uxx:real,densxx:real', &
    'text:str', &
    'ifsnedge:int', &
    'text:str', &
    'text:str', &
    'irecover:int,wpgroup:int,wegroup:int,wggroup:int,wjgroup:int', &
    'text:str', &
    'text:str', &
    'text:str', &
    'text:str', &
    'text:str', &
    'text:str', &
    'ntcurve:int', &
    'ntime:int:derived,type_curve:str:amplitudes[].type,nstoch_curve:int,nline:int', &
    'ttime_curve[1:ntime]:real:amplitudes[].points', &
    'dfact_curve[1:ntime]:real:amplitudes[].factors', &
    'text:str', &
    'nplgroup:int,kpload:int', &
    'text:str', &
    'nedge:int', &
    'text:str', &
    'nfixsets:int,nline:int', &
    '', &
    'ifixvar:int:steps[0].boundary[].dof,nfixnods:int:derived(nset size),itcurve:int:steps[0].boundar&
    &y[].amplitude,tfixvar:real,outfix:int,jfixvar:int,gamawx:real,nextr:int', &
    'list_fix[1:nfixnods]:int:mesh.sets(nset)', &
    'val_fix[1:nfixnods]:real:steps[0].boundary[].value', &
    'text:str', &
    'text:str', &
    'edge_load_group:int,delgroup:int', &
    'text:str', &
    'gravy:real:steps[0].load(gravity).magnitude,factg[1:ndimn]:real:steps[0].load(gravity).direction&
    &,factf[1:ndimn]:real', &
    'text:str,nline:int', &
    'tcurvegravity[1:ngroup]:int:steps[0].load(gravity).amplitude', &
    'text:str', &
    'nbeamload:int', &
    'text:str', &
    'nplateload:int', &
    'text:str', &
    'ntemp_surface:int', &
    'text:str', &
    'ntedge:int', &
    'text:str', &
    'text:str', &
    'ntelgroup:int', &
    'text:str', &
    'text:str', &
    'npipe:int,algo_pipe:int', &
    'text:str', &
    'iafile:int,icond:int,ipdchk:int,ising:int', &
    'text:str', &
    'nincs:int', &
    'miter:int:steps[0].controls.max_iterations,ditime:real:steps[0].controls.time_increment,noutn:in&
    &t:steps[0].output.frequency,noutf:int:steps[0].output.frequency,nstep:int:steps[0].controls.step&
    &s,inc_step:int:steps[0].controls.step_increment,nresta:int:steps', &
    'toler_force:real:steps[0].controls.tolerance_force,toler_var[1:mdofn]:real:steps[0].controls.tol&
    &erance_dof' &
    ]

  integer, parameter :: YL_READER_SEQ(YL_NREADERS) = [integer :: &
    1, 2, 3, 4, 1, 2, 3, 0, 5, 6, 7, 8, &
    9, 10, 0, 12, 13, 14, 15, 16, 1, 2, 17, 18, &
    19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, &
    31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, &
    43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, &
    55, 1, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, &
    1, 1, 2, 3, 66, 67, 68, 69, 5, 1, 2, 3, &
    4, 5, 6, 7, 8, 9, 10, 11, 12, 70, 71, 72, &
    73, 74, 75, 1, 2, 3, 4, 5, 6, 7, 8, 1, &
    2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, &
    6, 7, 8, 9, 1, 2, 0, 4, 5, 6, 9, 10, &
    11, 12, 13, 14, 15, 16, 17, 18, 19, 1, 2, 3, &
    4, 5, 6, 7, 8, 9, 10, 1, 2, 1, 2, 3, &
    4 &
    ]

end module yl_diag_registry
