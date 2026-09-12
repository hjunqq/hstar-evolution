

    Module global_var


    !Pardiso for IA32  2008-11-05

    !!!DEC$ OBJCOMMENT LIB:"gidpost_MT32.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_intel_s.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_intel_thread.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_core.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_solver.lib"
    !!DEC$ OBJCOMMENT LIB:"libguide.lib"

    !Pardiso for EM64T  2008-11-05

    !!DEC$ OBJCOMMENT LIB:"gidpost_MT64.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_intel_lp64.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_intel_thread.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_core.lib"
    !!DEC$ OBJCOMMENT LIB:"mkl_solver_lp64.lib"
    !!DEC$ OBJCOMMENT LIB:"libguide.lib"
    !include 'mkl_vsl.fi'

    use yl_diag
    use yl_diag_registry
    use variable_types
    use arrayutil
    use elements
    use gidpost

    !       use utility
    !use mkl_vsl_type
    !use mkl_vsl
    !use vsl_external


    implicit none

    integer*8 pt(64)    !pardiso
    Integer*8 pt_ctt(64)

    real(irk), parameter:: gamaw=9810.   !20230402
    character(80)text
    character(8) char_time
    character(1)field1
    character(20)material,type_curve
    integer(ink) igroup,nincs,nchek,lincs,runblks,len1,i0,cgroup,itotv,itcurve,iccontact,nmcon,relis,sysrelis !2018/01/10
    integer(ink) ninter_node,inode,jnode,ipoin,jpoin,jtotv,nintf,idofn,cmesh,ic,tnegid,ADINA,noutn,noutf,nstep,block_stab,  &
        nbackf,nbspring,ebody,nbackdT  !20210820
    integer(ink) tbpointsu,tbpointsT,tbpointsp  !20210321
    integer(ink) Uopt_R,vcor_unit !20210502
    integer(ink) hwdirec  !20220105
    real   (irk) hcoord   !20220105
    integer(ink) Blarge  !20221102, 考虑梁板大变形影响

    real   (irk) toler_force,lttime,f0,dfact,xload,yload,err,fincre
    real   (irk) preact0,preact1,preact4
    integer(ink) blks_new,incs_new,icttstif           !!rrr
    integer(ink) Qstatic          !20221104,该参数指定拟静力法中加速度随坐标变化的点数
    integer(ink) :: inpunit=43    !20190810, 通道号做了规范调整
    integer(ink) matno,index,order_int,ngaus,jndex,nstre,igaus,ielgroup,ielem, &
        jelem,kelem,jkelm,icjr !2003/10/31
    integer(ink),pointer::lnods(:)
    integer(ink),allocatable::icpoi(:),lmcon(:),listbpointsu_t(:),listbpointst_t(:),listbpointsp_t(:)
    integer(ink),allocatable::liste_bem_new(:),ien_bem(:,:),liste_mxy_new(:),ien_mxy(:,:) !20200311
    integer(ink),allocatable::ien_bcs(:,:),listp_bcs_new(:)   !20210328
    integer(ink),allocatable::line_load_block(:),line_temp_block(:),dinterp(:),group_have(:)   !!rrr
    real   (irk),allocatable::toler_var(:),freez(:),coef_water(:,:),rmcon(:,:)  !2013/3/18

    real   (irk),allocatable::dissanru(:,:),dissanzi(:,:)  !hxl2006 MIF
    real   (irk),allocatable::disA_1(:),disB_1(:),disA_2(:),disB_2(:)  !hxl2006 MIF
    real   (irk) k1(3),k2(3),k3(3)       !hxl
    integer(ink),allocatable::earthquake_curve(:),earthquake_curve_d(:),earthquake_curve_v(:),earthquake_curve_MIF(:)
    !20231215YL
    integer(ink) nstepjq,nstepjp,lquunit,disunit,pmtunit,stnunit,nliqu,omgunit !20231008
    integer(ink) out_gid_dismax !20231009
    real   (irk) base_freq
    type shear_liquifaction
        real(irk),pointer::stres(:,:)
    end type shear_liquifaction
    type(shear_liquifaction),allocatable::shear(:)
    integer(ink) gamamax,gamamaxunit !20231008
    real   (irk) Tgamamax,Tgamamax0
    !20231215YL
    integer(ink) ecwpipe  !20200221, equivalent cooling of water pipe
    integer(ink) wpgroup  !20210805

    integer(ink),allocatable::ipp4(:) !p42010
    real   (irk) alfa_p4,stiff_p4 !p42010
    integer(ink),allocatable::freedom_for_back(:,:) !20200812
    real (irk)  ,allocatable::Xvalue(:) !20200812

    real  ,allocatable::mean_value(:),sigma_value(:),para_stoch(:,:)  !20200812


    character(20) title(10),outplot,curtime  !20200220
    character(200) probn !20231215YL
    character(50) type_problem,type_solver,type_load,type_ABC,type_solver_ctt
    integer (ink) gunit,cunit,eunit,punit,loadunit,munit,chkunit,nrtunit,outinpunit,solveunit,  &
        initunit,mainunit,outpread,outpwrite,outdis,outact,outgpvar,restaunit,nresta, &
        lineload,outinp,irecover,tunit,linet,neuman,midstif,outint,outintr,outintw,outind,   &
        outewrite,outgwrite,outjwrite,outbar,outbeam,outcontact,outgoodman,arc_curve, &
        ifsunit,out_gid_dis,out_gid_msh,out_cosm_dis,out_cosm_gpvar,nlayer,neq_layer1,&
        kresl_layer1,kresl_layer2,type_nl_layer1,type_nl_layer2,kglb,state_change,ftfread,stocunit,         &
        ground_inf,group_inf,src,teloaw,equvs,out_msh,faiunit,nliste,resunit,resbunit,mwaqu_unit, & !20220330
        upliftunit,outindunit,pzunit,sub_msh_unit !20230407
    integer (ink) recttunit,restart_ctt,istatec
    integer (ink) back_ctl_unit,observ_unit,observc_unit,Bparameter,balgor,  &  !20210805
        bem_msh_unit,bem_res_unit,mxy_msh_unit,mxy_res_unit, &  !20200311
        bcs_msh_unit,bcs_res_unit, &  !20210328
        winit,initwunit,submodel  !20210207,20210320

    real    (irk) tor_bt,inpcord,camif,dxmif,epsMIFb,gamaMIF !zhao ctt2005 !hxl2006 VIE
    integer (ink) nlaymif,ifixvar0_inpb,doubsig !crack 2006 !steel 2006
    real    (irk) ftcrack,coefmpa,exx,uxx,densxx !crack 2006 !steel 2006
    integer (ink) ljdp,stab_matde !for longjiang, =0 ,nothing happen, =1, pseudononlinear  =2
    integer (ink),allocatable:: nforce_appear(:),nforce_gaps_appear(:) !1-- for saftyfactor 2-- for internal force 3-- for both
    integer (ink),allocatable:: safety_gaps_appear(:,:)  !20200409
    integer(2) mystatus(5) !pi chu li
    character(8)t2,t3
    !for outputGID
    integer(ink) gid_u,gid_s,gid_ms,gid_f,gid_rot,gid_v,gid_a,gid_T,gid_P,  &
        gid_Pv,gid_ep,gid_Y,gid_FC,gid_Ns,gid_Ss,gid_Mxy,gid_bem,gid_wh,gid_wv,gid_bcs
    integer(ink) res_u,res_s,res_ms,res_f,res_rot,res_v,res_a,res_T,res_P,res_Pv,res_ep,  &
        res_Y,res_FC,res_Ns,res_Ss,res_Pa,res_Tv   !,res_Mxy,res_bem
    integer(ink),allocatable::average_appear(:)
    !end for outputGID
    !local_p4
    integer(ink),allocatable::local_p4(:)  !20221124
    !end for outputGID
    !local_p4
    !steel 2006
    integer (ink) nlocalbeam,ikindks,ndimnrt
    real    (irk) ktan1,ktan2
    integer (ink),allocatable::listglocbeam(:),icpspring(:),icpnorm(:),lelenrt(:)
    real   (irk),allocatable::pnorm(:,:),prot(:,:,:),pstrain(:) !steel 2008
    !ifs2006 zhao, 06/03/29
    integer (ink) ifsnedge,ifswater,Icaddmass
    real    (irk) swlifs2006,toth,ifsgravity,absorb
    integer (ink),allocatable::icmp(:)
    real    (irk),allocatable::norp(:,:),addmp(:,:)
    !ifs2006 zhao, 06/03/29

    integer (ink) kinit,miter,solver_iter   !kinit=1, the load related to the initial
    !          stress will be computed;
    !kinit=2, not.
    integer(ink)level_set_problem ! 0--='F' , 1--Levleset , 2--'F'+Levelset.
    integer(ink)nifsgroup,nabssgroup,nabsfgroup  !!ifs2000
    integer(ink)nelc,nelc1,nremesh,nextrf,ntrans  !2004/9/11 !hxl2006 MIF
    integer(ink),allocatable::listnelc(:),listnelc1(:),ndefault(:)
    integer(ink)ndofn_space,ne_space,ngroup0,meshc,rmesh
    integer (ink) npoin,npoinb,nelem,ndimn,mdofn,cdofn,nmats,ngroup,ntotv,ntotv0
    integer (ink) ninit,nblks,nlinks,nonsym,type_nl,stabpw ! ,ngaps
    integer (ink) ninistn !20231215YL
    integer(ink) KRESL,KMASS,KSMAT,KHMAT,KQMAT,KLDFL,KSWKW,UWCPL,NGRAV,nflow,nfreeflownode
    INTEGER(INK) NMASS,NSMAT,NHMAT,NQMAT,NLDFL,NSWKW,KGMAT,KGRAV,KSTAT
    integer(ink) kthmat,ktsmat,nthmat,ntsmat,ntlink,nforce,nforce_gaps,nsafety_gaps ! 20200409
    integer(ink) restart,iblks,lblks,iiter,istep,iincs,mdiv,idiv,trstep,inc_step
    integer(ink) ngaps,ngapb,npbt,ntotvbt,contactpe,nonsbt,xlwsol  !ctt2005
    integer(ink) upliftin !20220409
    integer(ink),allocatable:: nodfnbt(:,:),listp_bt(:),npandbt(:)  !ctt2005
    integer (ink) miter_bt,iblks_bt,  neq_bt,mpairs,miter_state  !ctt2005 !fzx from solver
    integer (ink)   npoin_bem,nelem_bem,npoin_mxy,nelem_mxy
    integer (ink)   npoin_bcs,nelem_bcs  !20210328
    integer(ink) nrcsteel,nwcpipe       !20210328(考虑钢筋混凝土之间粘结滑移+钢筋的组数）
    integer(ink) nvarp_U,nintp_U,vdirect  !20210502,nvarp_U(U型渡槽内圈坐标可变节点数),nintp_U(与内圈坐标变化关联节点数）
    integer(ink),allocatable::varplist_U(:,:),intplist_U(:,:) !20210502上述点号列表
    real   (irk),allocatable::rintf_U(:,:) !20210502 插值系数
    real   (irk) radiusi,centerR(2)
    integer(ink)   Npara,Mvalue,Nblks_pb,mobstimes,Npoints_pb,Npoints_pbx !20210803
    integer(ink) ngdis_bk  !20211121(反演刚体位移的组数）
    integer(ink) ngval_bk  !20211201(反演节点值的组数）

    !! for caculate the interal forces
    integer(ink) npface,ftfunit,mat_curve
    integer(ink),allocatable::np_to_face(:),list_npface(:),ldofs_space(:),listp_space(:),listfreeflownode(:),nndex(:),nndex_bt(:) !ssorpbcg
    integer(ink),allocatable::iffix(:)
    real   (irk),allocatable::fixed(:)
    real   (irk),allocatable::ftfor(:,:),flowrate(:)
    real   (irk),allocatable::fmass(:), floae(:),floai(:),fexta(:) !!nstoks
    !! end for caculate the interal forces

    real    (irk) ditime,ttime,beeta1,beeta2,theta1,kstab,valv1,valv2,damp_ctt
    integer (ink),allocatable::nodfn(:,:),lmdofn(:),lcdofn(:),order_time_mdofn(:)
    integer (ink),allocatable::appear(:),appear_process(:,:),matno_process(:,:),state_change_process(:,:), &
        uinitial(:),freedom_layer(:),appear_p(:),appear_level(:),modf_dis_blocks(:) !levelset
    integer (ink),allocatable::block_appear_process(:,:)  !20200331

    real    (irk),allocatable::coord(:,:),deltafi(:),delitfi(:),     &
        stfor(:),tofor(:),fachv(:),prstat(:), &
        toforl(:),toform(:),  & !,deltafi_ssorpbcg(:) !ssorpbcg
        coord0(:,:)  !20221102

    integer (ink),allocatable::tlink(:,:),tension_joint(:),tension_contact(:)
    real    (irk),allocatable::  torel(:),hdam(:),estif_space(:,:),reaction_space(:,:),  &
        stif_inv_space(:,:),eload_space(:),global_mmatx(:,:),    &
        load_space(:),dis0_space(:),load0_space(:)
    real    (irk),allocatable::result_zero(:), result_first(:), result_second(:),inpru(:),inpzi(:) !hxl2006 MIF
    real    (irk),allocatable::result_zero_g(:),result_zero_e(:) !20210706
    real    (irk),allocatable::tofor_arclength(:),delta_arclength(:)
    real    (irk),allocatable::water_level(:),uplift_node(:),thetaice(:),velo_thetai(:) !20220409
    real    (irk),allocatable::accq(:,:) !20231113

    type(element_lib),allocatable::element(:)

    integer(ink),allocatable::equvs_process(:),force_process(:) !zhao 05/07/30
    complex(irk), allocatable::stforw(:),toforw(:) !freq2006

    type interpolation_group  !!int2000
        integer (ink)  nintf
        integer (ink), pointer::listf(:)
        real    (irk), pointer::rintf(:)
    end type interpolation_group

    type EAWPC     !Equivalent Algorithm of Water Pipe Cooling  for concrete temperature history !20200221
        real    (irk)  tp,btwater,gap_1,gap_2,L_pipe     !
        integer (ink)  icwater,pipecooling
        real    (irk)  time_eq,dtime_eq,time_real,dtime_real
        real     (irk), pointer::  tb1(:),te1(:),tsw1(:),taim1(:),q1(:)
    end type EAWPC  !20200221

    type temperature_prescribed  !20200226
        real    (irk)  time0,temp0,dtemp
        integer (ink)  temp_var_curve
    end type temperature_prescribed !20200226

    type parameter_trust_region  !20220108
        real    (irk)  eta1,eta2,gama1,gama2,eps,delta0
        real    (irk)  eta01,eta02,deltab
        integer (ink)  mtter
    end type parameter_trust_region  !20220108

    type group_of_elements
        character (10) name
        character (20) kname
        integer (ink) index,ngvar,nnode_dd,np_unode,point_direct(2), & !20200210
            uplift_ic,liquj
        character (2) class
        integer (ink) nrfields,ilayer
        integer (ink) kinit_g   !20211214
        character (5) fieldid
        character (10) special
        character (10) sptype
        real    (irk)  btime,educ,ditime_1,elcod_local,alfa,beta   ! for creep
        integer (ink)  nelgroup,matno,nstre,type_nalgo,type_stiff,type_ecoint,ivcoh,ivfri
        integer (ink), pointer::type_mass(:),order_time(:,:)   ! 0--lumped; 1--distributed
        integer (ink), pointer::list(:),belem(:) !belem (1:nelgroup) indicates the refined elements
        !belonged to which coarse element
        type(unode_elements), pointer::unode(:)
        type(EAWPC), pointer::water_pipe  !20200221
        type(temperature_prescribed), pointer::temp_pre  !20200226
        !!!!!  2003/10/30
        integer (ink)  cgroup  !,ninter_node
        integer (ink), pointer::lcgroup(:)
        !cgroup, corresponding group at the same position,
        !        sign(+) for fine mesh, sign(-) for coarse mesh
        !!!!!
        real    (irk), pointer::valun(:,:)
        type(field_dof), pointer::dof(:)
    end  type group_of_elements

    type unode_elements
        integer (ink) ne_unode
        integer (ink),pointer::list(:)
        !! stablize
        integer (ink) np_unode,ipoin
        integer (ink),pointer::patch_nod(:)
        real    (irk),pointer::patch_sta(:,:),patch_load(:)
        !! end stablize
    end type unode_elements

    type field_dof
        integer (ink) nfdof
        integer (ink), pointer::listdof_f(:)
    end type field_dof

    type link_group
        integer (ink) npairs
        integer (ink),pointer:: link_freedom(:)   ! 1-cdofn
        integer (ink), pointer::pairnode(:,:)
    end type link_group

    type interface_internal_force
        integer (ink) npface,lgroup,neface
        integer (ink),pointer:: list(:)  ! list the number of groups
        integer (ink),pointer::list_npface(:),liste(:),liste1(:) !special for caoguangde
        real    (irk),pointer::ftfor(:,:)
        real    (irk),pointer::ftfor_ext(:,:,:)
    end type interface_internal_force

    !ifs2006 zhao, 06/03/29
    type gauss_edge_ifs2006
        real(irk) djacb
        real(irk),pointer::shape(:),cartd(:,:),rotation(:,:),normal(:)
    end type gauss_edge_ifs2006

    type ifsedges_define
        integer(ink) nnode,ngaus,index,selem,felem,ndimn,bkind,order_int
        integer(ink),pointer::lnods(:),ldofs(:),ldofs_s(:),ldofs_f(:)
        real   (irk),pointer::normal(:),matrix(:,:),eload(:),matrix0(:,:)
        type(gauss_edge_ifs2006),pointer::edgegaus(:)
    end  type ifsedges_define

    type dwpressure_aquduct !20220330
        integer(ink) xdir,zdir,nsect,npseczx,npsecxz,aqu_group
        integer(ink),pointer::listp_seczx(:,:),listp_secxz(:,:),jnode(:)
        integer(ink),pointer::ldofszx(:),ldofsxz(:)
        real   (irk),pointer::pzx(:,:),pxz(:,:),eloadzx(:),eloadxz(:)
    end  type dwpressure_aquduct !20220330

    type (dwpressure_aquduct),allocatable::dwpre_aqu  !20220330



    type (ifsedges_define),allocatable::ifsedges(:)

    !!ifs2000  !!for interface between fluid and solid

    type group_of_ifs
        integer(ink) aelemf,aelems
        integer(ink),pointer::lnods(:),ldofs(:)
        real   (irk),pointer::estif(:,:),eload(:)
    end type group_of_ifs

    type group_of_absorb_fluid
        integer(ink) aelemf
        integer(ink),pointer::lnods(:),ldofs(:)
        real   (irk),pointer::estif(:,:),eload(:)
    end type group_of_absorb_fluid

    type group_of_absorb_solid !hxl2006 VIE
        integer(ink) aelems,cdbound
        integer(ink),pointer::lnods(:),ldofs(:)
        real   (irk),pointer::estif(:,:),eload(:),estif0(:,:),cordzfree(:),eload_s(:,:),rr(:,:)
    end type group_of_absorb_solid

    type group_of_dvide_ipoin
        integer(ink) mgroup
        integer(ink),pointer::listg(:),listp(:)
    end type group_of_dvide_ipoin


    type qstatic_parameter !20221104
        integer(ink) iaxe
        integer(ink),pointer::appearg(:)
        real   (irk),pointer::cor_coef(:,:),qfactor(:)
    end type qstatic_parameter  !20221104

    type(qstatic_parameter), allocatable::qstatic_force   !20221104


    type group_of_back_analysis !20230523
        integer(ink) groupb,mdism,wstep
        integer(ink),pointer::listp(:),listdim(:),ic(:) !20230523
        real   (irk),pointer::dism(:,:),wtime(:) !20230523
        type(back_points_information),pointer::relat(:)
    end type group_of_back_analysis !20230523

    type observation_node_information !20190810
        integer(ink) inode,idofn  !inode观测节点号；idofn,观测点自由度序号（在1：mdofn）中的位置；
        !!,jnode jnode 为相对值对应节点号
        integer(ink) iblks,iincs,istep,ivalue_point,iobse,ic
        integer(ink) jvalue   !位移起始观测点
        real(irk) value_measure,value_computation !20220108
        real(irk),pointer::dudx(:),dudx2(:,:)  !20220108
    end type observation_node_information !20190810

    type back_parameter_information !20190810
        integer(ink) imat,mode_transform   !imat:被反演的材料号;mode_transform:参数变换方式,0(不变换),1(倒数)
        character (10) name  !name,被反演的材料名
        real(irk) factor,factor_inc
    end type back_parameter_information !20190810

    type back_nincs_information !20200819
        integer(ink) nstep_pb,dstep_pb,dtime_pb,begin_day_pb,end_day_pb,mvalue_point  !20230719
        integer(ink),pointer::list_point_pb(:),tstep_bp(:,:)
        real   (irk),pointer::time_bp(:)
    end type back_nincs_information !20200819

    type back_points_information !20230503
        integer(ink) nintf,ndofn
        integer(ink),pointer::listf(:),listdofn(:),listp(:)
        real   (irk),pointer::rintf(:)
        real   (irk),pointer::cor(:)  !20211121
        !integer(ink) inode,jnode,idofn,nintf,nintf1
        !integer(ink),pointer::listf(:)
        !real   (irk),pointer::rintf(:)
        !integer(ink),pointer::listf1(:)
        !real   (irk),pointer::rintf1(:),cor(:)  !20211121
    end type back_points_information  !20230503

    type back_blocks_information !20200819
        integer(ink) nincs_pb
        type(back_nincs_information),pointer::para_nincs(:)
    end type back_blocks_information !20200819

    type group_of_constrain_spring !20150925
        integer(ink) listp,listdof,listdim
        real   (irk) spring,eload
    end type group_of_constrain_spring !20150925

    type matrix_rigid_dis_block_group  !20211121
        integer (ink)  npoin_bk,ngroup_bk,ndofn_bk
        integer (ink), pointer::node_bk(:),group_bk(:),fixed_dis(:),nodet_bk(:),dof_bk(:)
        real    (irk), pointer::cmatrix(:,:),center(:),npdisp(:,:,:)
    end type matrix_rigid_dis_block_group !20211121


    type(group_of_ifs), allocatable::tifs(:)              !nifsgroup
    type(group_of_absorb_solid), allocatable::tabss(:)    !nabssgroup
    type(group_of_absorb_fluid), allocatable::tabsf(:)    !nabsfgroup
    type(parameter_trust_region),allocatable::trustp(:)  !20220108
    !!ifs2000

    !! contact    !!ctt2005
    type gap_node  !2010/10
        integer (ink)  njcp
        integer (ink), pointer::jcplist(:)
        real    (irk), pointer::rot(:,:,:),aera(:),ft(:),cohes(:),frict(:),Gf(:)
    end type gap_node

    type gap_collect_node  !2015/11/17
        integer (ink)  npbotom,nptop
        integer (ink), pointer::listbotom(:),listtop(:)
        real    (irk), pointer::listbotom_aera(:),listtop_aera(:)
    end type gap_collect_node



    type gap_group
        integer (ink) npairs,ngroupt,stateix,frict_less,goodman,thin_layer,ivcoh,ivfri
        integer (ink), pointer::listgroupt(:),xlwmd(:)
        integer (ink), pointer::pairnode(:,:),state(:),state0(:),statei(:),paire(:),group(:),pair_process(:)
        real    (irk), pointer::rot(:,:,:),aera(:),gap0(:,:),ctforce(:,:),ft(:),wsc(:),  &
            alfa1(:),alfa2(:),ctforce0(:,:),ctforcei(:,:),ctforcej(:,:),gap(:,:), &
            cohes(:),frict(:),ft0(:),cohes0(:),frict0(:),Gf0(:),kgroup0(:,:),kgroup1(:,:),  &  !2007
            cohesx(:),frictx(:),kxyz0(:,:,:),kxyz(:,:,:),dxyz(:,:),dxyz0(:,:),dxyzi(:,:),sigmad(:),xd(:),Gf(:), &
            ft1(:),wt0(:),wt1(:),wt2(:),ctforce_stres0(:,:), &  !2019/03/19
            damage0(:),damage(:)
        real    (irk), pointer::kgdm(:)
        real    (irk)  gapi,Rf,n,Pa,e,miu,thick,Ke,gamaw    !Ke对应于何金文的beishu，2017/02/14
        type(gap_collect_node),pointer::gaps_collect(:) !2015/11/17
    end type gap_group

    type gap_block_group
        integer (ink)  npgblock,ngroupb,ngroupt,ntotv_bt,nrdof !rpoin-rigid displacement  fzx
        integer (ink)  npblock,eblock   !2017/11/19
        integer (ink), pointer::nodeblock(:),nppt(:)   !new
        !ndimn=2: first dimn freedom of rpoin1 and two freedom of rpoin2
        !ndimn=3: three freedoms of rpoin1 and rpoin2
        integer (ink), pointer::nodegblock(:),listgroupb(:),listgroupt(:),ldofs(:),listrele(:),listrdof(:),rldofs(:)
        integer (ink), pointer::nodegblock_ipairs(:),nodegblock_igaps(:),nodegblock_onetwo(:)
        real    (irk), pointer::cmatrix(:,:),rdisp_zero(:),npdisp(:,:,:),rdisp_inc(:),rdisp_inc0(:),center(:),mass_inertia(:),uireact(:,:) !2015/11/28
        real    (irk), pointer::rstiff(:,:) !20121216
        real    (irk), pointer::rdisp_first(:),rdisp_second(:),rdisp_delitfi(:),rdisp_deltafi(:)  !1128
        integer (ink), pointer::pairspoint12(:)  !20191031   for block_stab==2
        real    (irk), pointer::disp_ct(:,:),force_ct(:,:),ext_force(:)  !20231009
    end type gap_block_group

    !! end contact !ctt2005
    !! （混凝土+钢筋及与混凝土粘结）交互求解 20210328
    type line_steel_stick   !对应每根钢筋及对应的联结单元
        integer (ink)  npairs_sc,nline_s
        integer (ink), pointer::linenode_s(:,:),ianode_s(:,:),pairnode_sc(:)
        real    (irk), pointer::rot_sc(:,:),aera_sc(:),dl_s(:),rot_s(:,:),aera_s(:,:),tao_cs(:),slip_sc(:)
        real    (irk), pointer::cmatrix_c(:,:),kmatrix_s(:,:),ikscr(:,:),kmatrix_cs(:,:)
        real    (irk), pointer::tao0_cs(:),slip0_sc(:),k2(:,:,:),axial_stres(:),shear_stres(:)
    end type line_steel_stick


    type group_stick_and_steel  !对应一种类型的钢筋及对应联结单元组
        integer (ink)  nline_g_sc,listgroup_s,listgroup_c,ikindsc,mxter !对应的concrete单元组号
        real    (irk)  diameter_s,ft,err_ctl
        type(line_steel_stick),pointer::line_g_sc(:)
    end type group_stick_and_steel  !20210328

    !! end（混凝土+钢筋及与混凝土粘结）交互求解 20210308

    !! （混凝土+冷却水管）交互求解 20210411
    type line_water_pipe   !对应每根冷却水管
        integer (ink)  nline_w,npairs_wc
        integer (ink), pointer::linenode_w(:,:),ianode_w(:,:),pairnode_wc(:)
        real    (irk), pointer::cmatrix_c(:,:),kmatrix_w(:,:),idcr(:,:)
        real    (irk), pointer::Qwc(:)
    end type line_water_pipe


    type group_water_pipe  !对应一种类型的冷却水管
        integer (ink)  nline_g_w,listgroup_w,listgroup_c,iwc
        real    (irk)  alfa1,Qw,lamda_w,density_w,Cw,begin_time,end_time,twater_curve,dtime_change
        type(line_water_pipe),pointer::line_g_w(:)
    end type group_water_pipe  !20210411

    !! end（混凝土+冷却水管）交互求解 20210411


    type(group_of_elements),       allocatable::group(:)
    type(group_of_elements),       allocatable::group1(:)
    type(group_of_elements),       allocatable::group2(:)
    type(link_group),              allocatable::links(:)
    type(interface_internal_force),allocatable::surface_force(:)
    type(interpolation_group),     allocatable::trans(:) !!int2000
    type(interpolation_group),     allocatable::trans0(:) !!int2000
    type(interpolation_group),     allocatable::trans_c(:) !!int2000
    type(interpolation_group),     allocatable::trans_bt(:) !!int2000 !ctt2005
    type(group_of_dvide_ipoin),    allocatable::listp_group(:) !!2003/10/31
    type(group_of_back_analysis),  allocatable::backf(:) !!20150925
    type(group_of_constrain_spring),    allocatable::bspring(:) !!20150925
    type(observation_node_information), allocatable::Value_observ(:) !!20190810
    type(back_parameter_information),   allocatable::para_back(:) !!20190810
    type(back_blocks_information),      allocatable::para_block(:) !!20200819
    type(back_points_information),      allocatable::para_points(:) !!20200819
    type(back_points_information),      allocatable::para_pointsx(:) !!20230523

    type(group_stick_and_steel),  allocatable::rc_steel(:) !!20210308,总的钢筋及对应联结单元组
    type(group_water_pipe),  allocatable::wc_pipe(:) !!20210411,总的冷却水管

    type(gap_node), allocatable::gapnode(:)	 !2010/10
    type(gap_group), allocatable::gaps(:)  !ctt2005
    type(gap_block_group), allocatable::gapb(:)  !ctt2005
    type(matrix_rigid_dis_block_group),allocatable::rigid_bk(:)  !20211121
    type(matrix_rigid_dis_block_group),allocatable::nodvar_bk(:)  !20211201

    !   type(gap_group), allocatable::gaps(:)    ! contact

    interface default
    module procedure kinddefine, read_element
    end interface

    contains



    subroutine global_data

    character(80) text,title_intp       ! middle variable  20200112
    character(10) name,fieldid,class,special ! middle variable
    integer (ink) i,j,idofn,ilink,ipoin,jpoin,i0,j0,ielem,igroup,iblk,ie,  &
        ielgroup,nstre,type_mass,np_unode,ip0,jp0,mdism,wstep,                & !!middle variable
        idfn(2),jdfn(2),jtotv,idimn,i1,mgroup,jdimn,jdofn,xdofn   !20230523
    integer (ink) ncouple,icouple,ifield,field1,field2,nevab,nevab1,nevab2,ipoin1,ipoin2
    integer (ink) ne_unode,lnode,inode,nrfields,len1,nfdof,tne,jelem
    integer (ink) nelsum   ! M1-03: running sum of nelgroup over the groups
    integer (ink) index,matno,nelgroup,nnode,npairs,ipair,nnode1,nnode2
    integer (ink) iforce,lgroup,node_face,neface,tsel,itsel,translg,ntlg
    integer (ink) transgroup,itrans,nintf,itotv,inintf,ne_include,ntransnode,itransgroup !!int20200805
    integer (ink), allocatable::listx(:),mdof(:),appear_node(:),  &
        nodx(:),ienface(:,:),listf(:),corsp(:),icxx(:),listdofn(:) !20230523
    real    (irk) tvol,elcod_local,f1,f2,f3,f12(2),f0  !20200112
    real    (irk),allocatable::rotation(:,:),rintf(:)
    integer (ink),pointer::lnods(:)


    ! set units for data file
    gunit=1
    cunit=2
    eunit=3
    punit=4
    munit=5
    chkunit=7
    solveunit=8
    mainunit=9
    outpread=10
    outdis=11
    outact=12
    outgpvar=13
    initunit=14
    initwunit=48   !20210207

    restaunit=15
    outint=16
    outpwrite=17   ! records results at nodes
    outewrite=18   ! records element average stress
    outgwrite=19   ! records average gaps at given elements
    outjwrite=20   ! records normal and tangent stresses for given joint elements
    loadunit=21
    tunit=22
    midstif=23
    outcontact=24
    outgoodman=25
    outbar=26
    outbeam=27
    ftfunit=28
    ftfread=29
    ifsunit=30
    nrtunit=31
    resunit=32
    resbunit=49  !20210321
    upliftunit=53 !20220409
    sub_msh_unit=55 !20230407

    stocunit=33
    back_ctl_unit=44 !20190810
    observ_unit=45  !20190810

    bem_msh_unit=46  !20200311
    bem_res_unit=47  !20200311

    bcs_msh_unit=46  !20210328
    bcs_res_unit=47  !20210328

    Mxy_msh_unit=46  !20200311
    Mxy_res_unit=47  !20200311

    if(Uopt_R==1)vcor_unit=50  !20210502

    observc_unit=51  !20210805
    mwaqu_unit=52  !20220330
    !20231215YL
    lquunit=0     !72  !20231008
    disunit=0     !73  for liqu judge
    pmtunit=0     !74  shear strain for calculaing permanent deformation  nzw 2013-5-8
    stnunit=0     !75  residual strain for calculaing permanent deformation  nzw 2013-5-8
    gamamaxunit=1012  !20231008存储最大动剪应变
    !20231215YL

    title(1)='Ux'
    title(2)='Uy'
    title(3)='Uz'
    title(4)='Thx'
    title(5)='Thy'
    title(6)='Thz'
    title(7)='Hydrostatic_pressure'
    title(8)='Pore_Pressure'
    title(9)='Air_Pressure'
    title(10)='Temperature'
    print *,'Input the problem name?'
    !   read *,probn
    len1=len_trim(probn)
    if (.not. yl_input_enabled) open(gunit,     file=probn(1:len1)//'.glb',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.glb','gunit','Global.f90:631')
    if (.not. yl_input_enabled) open(cunit,     file=probn(1:len1)//'.cor',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.cor','cunit','Global.f90:633')
    if (.not. yl_input_enabled) open(eunit,     file=probn(1:len1)//'.ele',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.ele','eunit','Global.f90:635')
    if (.not. yl_input_enabled) open(punit,     file=probn(1:len1)//'.pre',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.pre','punit','Global.f90:637')
    if (.not. yl_input_enabled) open(munit,     file=probn(1:len1)//'.mat',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.mat','munit','Global.f90:639')
    if (.not. yl_input_enabled) open(loadunit,  file=probn(1:len1)//'.loa',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.loa','loadunit','Global.f90:641')
    open(chkunit,   file=probn(1:len1)//'.chk')
    if (.not. yl_input_enabled) open(solveunit, file=probn(1:len1)//'.sol',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.sol','solveunit','Global.f90:644')
    if (.not. yl_input_enabled) open(mainunit,  file=probn(1:len1)//'.man',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.man','mainunit','Global.f90:646')
    if (.not. yl_input_enabled) open(outpread,  file=probn(1:len1)//'.opr',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.opr','outpread','Global.f90:648')
    open(outpwrite, file=probn(1:len1)//'.opw')
    open(outewrite, file=probn(1:len1)//'.oew')
    open(outgwrite, file=probn(1:len1)//'.ogw')
    open(outjwrite, file=probn(1:len1)//'.ojw')
    open(outdis,    file=probn(1:len1)//'.dis')
    open(outact,    file=probn(1:len1)//'.act')
    open(outgpvar,  file=probn(1:len1)//'.gpv')
    open(initunit,  file=probn(1:len1)//'.ini')
    open(initwunit,  file=probn(1:len1)//'.inw')  !20210207
    if(Uopt_R==1) &
        open(vcor_unit,  file=probn(1:len1)//'.vcor')  !20210502
    if (.not. yl_input_enabled) open(tunit,     file=probn(1:len1)//'.tem',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.tem','tunit','Global.f90:661')
    open(ftfunit,   file=probn(1:len1)//'.ftf')
    if (.not. yl_input_enabled) open(ftfread,   file=probn(1:len1)//'.ftr',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.ftr','ftfread','Global.f90:664')
    if (.not. yl_input_enabled) open(ifsunit,   file=probn(1:len1)//'.ifs',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.ifs','ifsunit','Global.f90:666')
    open(mwaqu_unit,file=probn(1:len1)//'.aqu')  !20220330
    if (.not. yl_input_enabled) open(nrtunit,   file=probn(1:len1)//'.nrt',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,probn(1:len1)//'.nrt','nrtunit','Global.f90:669')
    open(outbar,    file=probn(1:len1)//'.bar')
    open(outbeam,   file=probn(1:len1)//'.bem')
    open(outcontact,file=probn(1:len1)//'.ctr')
    open(outgoodman,file=probn(1:len1)//'.gdm')
    open(stocunit,file=probn(1:len1)//'.sto')

    open(restaunit, file=probn(1:len1)//'.rtt',FORM='UNFORMATTED')
    open(midstif,   file=probn(1:len1)//'.stf',FORM='UNFORMATTED')

    open(resunit,  file=probn(1:len1)//'.res',FORM='binary')
    open(resbunit,  file=probn(1:len1)//'.resb',FORM='binary')


    !open(resunit,  file=probn(1:len1)//'.res') !,FORM='binary')
    !open(resbunit,  file=probn(1:len1)//'.resb') !,FORM='binary')
    faiunit=34
    open(faiunit,  file=probn(1:len1)//'.fai',FORM='UNFORMATTED')
    recttunit=35
    open(recttunit,file=probn(1:len1)//'.ctt',FORM='UNFORMATTED') !ctt2005
    if (yl_input_enabled) goto 8090   ! M5: no .glb to read; see yl_authoring_prelude
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_1,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)npoin,npoinb,nelem,ndimn,nmats,ngroup,ntlink,outplot,kstab,mat_curve,meshc,rmesh,level_set_problem,ljdp,stab_matde
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_sizes_and_switches,0)
    print *, npoin,npoinb,nelem,ndimn,nmats,ngroup,ntlink,outplot,kstab,mat_curve,meshc,rmesh,level_set_problem,ljdp,stab_matde
    ! M1-03 sizes guard: these decide every allocation below, so fail before the first allocate
    call diag_range(RD_GLB_global_data_sizes_and_switches,0,'npoin',int(npoin,i8),1_i8,diag_max_entities())
    call diag_range(RD_GLB_global_data_sizes_and_switches,0,'npoinb',int(npoinb,i8),0_i8,diag_max_entities())
    call diag_range(RD_GLB_global_data_sizes_and_switches,0,'nelem',int(nelem,i8),1_i8,diag_max_entities())
    if(ndimn/=2.and.ndimn/=3)call diag_unsupported(RD_GLB_global_data_sizes_and_switches,0,'ndimn',diag_itoa(int(ndimn,i8)),'2 | 3')
    call diag_range(RD_GLB_global_data_sizes_and_switches,0,'nmats',int(nmats,i8),1_i8,diag_max_entities())
    call diag_range(RD_GLB_global_data_sizes_and_switches,0,'ngroup',int(ngroup,i8),1_i8,diag_max_entities())
    call diag_range(RD_GLB_global_data_sizes_and_switches,0,'ntlink',int(ntlink,i8),0_i8,diag_max_entities())
    call diag_product(RD_GLB_global_data_sizes_and_switches,0,'npoin*ndimn',[int(npoin,i8),int(ndimn,i8)])
    call diag_product(RD_GLB_global_data_sizes_and_switches,0,'npoin*ndimn*ndimn',[int(npoin,i8),int(ndimn,i8),int(ndimn,i8)])
    call diag_flush_stage()
    allocate(pnorm(ndimn,npoin),prot(ndimn,ndimn,npoin),icpnorm(npoin),lelenrt(nelem),icpspring(npoin),stat=yl_st,errmsg=yl_msg) !steel 2006
    if(yl_st/=0)call diag_abort('INIT',EXIT_INIT,'Global.f90:global_data','first allocate failed: '//trim(yl_msg))
    pnorm=0. ; prot=0. ; icpnorm=0 ; lelenrt=0 ; icpspring=0

    allocate(ipp4(npoin)) ; ipp4=0 !p42010   !20221124

    allocate(pstrain(npoin)) ; pstrain=0. !steel 2008

    do idimn=1,ndimn
        prot(idimn,idimn,:)=1.0
    enddo

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text  !2004/7/12
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_2,0)
    if(rmesh/=0)read(gunit,*,iostat=yl_ios,iomsg=yl_msg)valv1,valv2 !2004/7/12
    if(rmesh/=0)call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_reached_only_Global_691,0)

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text  !2004/7/12
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_3,0)
    if (rmesh/=0)then
        allocate(ndefault(abs(rmesh)))
        read(gunit,*)ndefault
    endif              !2004/7/12
8090 continue
    if (outplot(1:3)=='GID')then
        out_gid_msh=39
        open(out_gid_msh,file=probn(1:len1)//'.flavia.msh',buffered='YES',blocksize=1048576)
        out_gid_dis=40
        if(outplot=='GIDR')open(out_gid_dis,file=probn(1:len1)//'.flavia.res',buffered='YES',blocksize=1048576)
        if(outplot=='GIDA')open(out_gid_dis,file=probn(1:len1)//'.flavia.res',ACCESS='append',buffered='YES',blocksize=1048576)
        if(outplot=='GIDL')then
            CALL GID_OPENPOSTRESULTFILE(probn(1:len1)//'.post.bin',GiD_PostBinary)
        endif
    else if(outplot(1:6)=='COSMOS') then
        out_cosm_dis =40
        out_cosm_gpvar=41
        if (outplot=='COSMOSR') then
            open(out_cosm_dis,  file=probn(1:len1)//'.cosm.dis')
            open(out_cosm_gpvar,file=probn(1:len1)//'.cosm.gpv')
        else if(outplot=='COSMOSA') then
            open(out_cosm_dis,  file=probn(1:len1)//'.cosm.dis',ACCESS='append')
            open(out_cosm_gpvar,file=probn(1:len1)//'.cosm.gpv',ACCESS='append')
        endif
    endif

    if (rmesh<0)then
        out_msh=36
        open(out_msh,file=probn(1:len1)//'r.flavia.msh',buffered='YES',blocksize=1048576)
    endif
    if (yl_adapter_mode) call yl_adapter_override(); if (yl_adapter_mode) return   ! M4-02 adapter entry
    allocate(tlink(2,ntlink))
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_4,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)ninit,kinit,winit,nblks,nlinks,nonsym,outinp,outintr,outintw,neuman,equvs,type_ABC,block_stab,nbackf,nbspring,ebody,outind,nbackdT,ninistn  !20231215YL
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_init_and_blocks,0)
    print *,ninit,kinit,winit,nblks,nlinks,nonsym,outinp,outintr,outintw,neuman,equvs,type_ABC,block_stab,nbackf,nbspring,ebody,outind,nbackdT,ninistn !20231215YL
    outinpunit=37  !20220626
    outindunit=54  !20220626
    write(*,*)'outinpunit=',outinpunit,'outindunit=',outindunit
    if(outind/=0)open(outindunit,file=probn(1:len1)//'.oid')
    !if(outinp/=0)open(outinpunit,file=probn(1:len1)//'.oip',FORM='binary')
    if(outinp/=0)open(outinpunit,file=probn(1:len1)//'.oip')


    if(equvs/=0)teloaw=38
    if(equvs/=0)open(teloaw,file=probn(1:len1)//'.tel',FORM='UNFORMATTED') !zhao 05/07/30
    !open(100,file=probn(1:len1)//'.tel0') !zhao 05/07/30
    !open(teloaw,file=probn(1:len1)//'.tel')
    if(ninistn/=0)stnunit=75 !20231215YL
    if(stnunit/=0)open(stnunit,file=probn(1:len1)//'.stn') !20231215YL


    !   if (outintr.gt.0) then
    !      open(outint,file=probn(1:len1)//'.oit',RECL=npoin*4,FORM='BINARY',ACCESS='DIRECT')
    !   else if(outintw.gt.0) then
    !      open(outint,file=probn(1:len1)//'.oit',FORM='BINARY',ACCESS='append')
    !   endif
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_5,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)type_problem,type_solver,type_load,type_nl,stabpw,nlayer,kglb,state_change,Bparameter,balgor,upliftin   !20220409
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_problem_type,0)

    if(Bparameter==-3.or.Bparameter>0.or.nbackf>0.or.nbackdT==2) &  !20231030
        open(back_ctl_unit,file=probn(1:len1)//'.btl')

    if(Bparameter==-3.or.Bparameter>0.or.nbackdT==2) & !20231030
        open(observ_unit,file=probn(1:len1)//'.obs')
    if(nbackf>0) & !20230523
        open(observc_unit,file=probn(1:len1)//'.obsc')


    if (ljdp/=0.and.type_nl/=5)then !ljdp 2010
        write(*,*)'Warning: ljdp/=0.and.type_nl/=5'
        write(*,*)'Press anykey to skip this massage!'
        pause
    endif
    print *,type_problem,type_solver,type_load,type_nl,stabpw,nlayer,kglb
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_6,0)
    print *,text
    if(nlayer==2)read(gunit,*,iostat=yl_ios,iomsg=yl_msg) type_nl_layer1,type_nl_layer2,solver_iter
    if(nlayer==2)call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_reached_only_Global_772,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_7,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)nmass,nsmat,nhmat,nqmat,nldfl,kgmat,nswkw,uwcpl,NGRAV,nflow,ECWPIPE  !20200220
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_material_class_counts,0)
    print *,nmass,nsmat,nhmat,nqmat,nldfl,kgmat,nswkw,uwcpl,ngrav,nflow,ECWPIPE  !20200220
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_8,0)
    print *,text
    if (nflow/=0)then
        read(gunit,*)nfreeflownode
        if(nfreeflownode/=0)then
            allocate(listfreeflownode(nfreeflownode))
            read(gunit,*)listfreeflownode
        endif
    endif

    ! temperature
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_9,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)ntsmat,nthmat,kstat,ground_inf,src,nextrf,submodel  !20210320
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_special_counts,0)

    if(submodel==-1)open(sub_msh_unit,file=probn(1:len1)//'.msh')  !20230407


    if(submodel==1)then  !20210321
        !read(resbunit)text
        !read(resbunit)text
        read(resbunit)tbpointsu,tbpointst,tbpointsp
        write(7,*)'tbpointsu,tbpointst,tbpointsp=',tbpointsu,tbpointst,tbpointsp
        if(tbpointsu/=0)then
            allocate(listbpointsu_t(tbpointsu))
            read(resbunit)listbpointsu_t
            write(7,*)'listbpointsu_t=',listbpointsu_t
        endif
        if(tbpointst/=0)then
            allocate(listbpointst_t(tbpointst))
            read(resbunit)listbpointst_t
        endif
        if(tbpointsp/=0)then
            allocate(listbpointsp_t(tbpointsp))
            read(resbunit)listbpointsp_t
            write(7,*)'listbpointsp_t=',listbpointsp_t
        endif

    endif !20210321

    if(outind==-1)then  !20231113
        read(outindunit,*)tbpointsu
        write(7,*)'tbpointsu=',tbpointsu
        if(tbpointsu/=0)then
            allocate(listbpointsu_t(tbpointsu))
            read(outindunit,*)listbpointsu_t
            write(7,*)'listbpointsu_t=',listbpointsu_t
        endif
    endif !20231113


    !   groundf=ijk
    !   i=1,center,2,distribution
    !   j=1,only vertical,2 three directions
    !   k=1,plate,2 Simo-Rifai
    print *,ntsmat,nthmat,kstat,ground_inf,nextrf  !2004/9/11
    !new
    read(ftfread,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_FTR_global_data_title_1,0)
    read(ftfread,*,iostat=yl_ios,iomsg=yl_msg)nforce,ngaps,nforce_gaps,nsafety_gaps
    call diag_check_read(yl_ios,yl_msg,RD_FTR_global_data_force_counts,0)
    if(nforce/=0)allocate(surface_force(nforce),nforce_appear(nforce))    !nforce_appear !1-- for saftyfactor 2-- for internal force 3-- for both
    if(nforce_gaps/=0)allocate(nforce_gaps_appear(ngaps))    !nforce_gaps_appear !1-- for saftyfactor 2-- for internal force 3-- for both
    if(nforce/=0)then
        read(ftfread,*)text
        read(ftfread,*)nforce_appear
    endif
    if(nforce_gaps/=0)then
        read(ftfread,*)text
        read(ftfread,*)nforce_gaps_appear
        print *,'nforce_gaps_appear=',nforce_gaps_appear
    endif
    if(nsafety_gaps/=0)then  !20200409
        allocate(safety_gaps_appear(ngaps,nsafety_gaps))
        read(ftfread,*)text
        do iforce=1,nsafety_gaps
            write(7,*)'isafety=',iforce,'ngaps=',ngaps
            read(ftfread,*)safety_gaps_appear(:,iforce)
            write(7,*)'safety_gaps_appear=',safety_gaps_appear(:,iforce)
        end do
    endif  !20200409

    if(nforce/=0)then
        read(ftfread,*)text
        do iforce=1,nforce

            read(ftfread,*)text
            read(ftfread,*)lgroup,neface,node_face,nliste
            print *,'lgroup=',lgroup,'neface=',neface,'node_face=',node_face
            surface_force(iforce)%lgroup=lgroup
            surface_force(iforce)%neface=neface
            allocate(surface_force(iforce)%list(lgroup),surface_force(iforce)%liste(neface),  &
                surface_force(iforce)%liste1(neface)) !special for caoguangde
            allocate(ienface(node_face,neface),nodx(npoin))
            read(ftfread,*)text
            read(ftfread,*)surface_force(iforce)%list

            nodx=0
            do ie=1,neface
                !read(ftfread,*)i0,ienface(:,ie),  surface_force(iforce)%liste(ie)
                !if(nliste==1)read(ftfread,*)i0,surface_force(iforce)%liste(ie),ienface(:,ie)
                if(nliste==1)read(ftfread,*)surface_force(iforce)%liste(ie),ienface(:,ie)
                if(nliste==2)read(ftfread,*)i0,surface_force(iforce)%liste(ie),surface_force(iforce)%liste1(ie),ienface(:,ie)
                nodx(ienface(:,ie))=1
            end do    !ie
            npface=sum(nodx)
            surface_force(iforce)%npface=npface
            allocate(surface_force(iforce)%ftfor(ndimn,npface),  &
                surface_force(iforce)%list_npface(npface))

            if(nextrf/=0)allocate(surface_force(iforce)%ftfor_ext(ndimn,npface,nextrf)) !2004/9/11


            npface=0
            do ipoin=1,npoin
                if (nodx(ipoin)==1)then
                    npface=npface+1
                    surface_force(iforce)%list_npface(npface)=ipoin
                endif
            end do    ! ipoin

            deallocate(ienface,nodx)

        end do    !iforce
    endif

    !  end new
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_10,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)mdofn
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_mdofn,0)
    call diag_range(RD_GLB_global_data_mdofn,0,'mdofn',int(mdofn,i8),1_i8,diag_max_entities())   ! M1-03
    call diag_flush_stage()
    allocate(lmdofn(mdofn),lcdofn(mdofn),order_time_mdofn(mdofn))
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)lmdofn(1:mdofn) !0,no the freedom;1,the freedom occur
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_lmdofn,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)order_time_mdofn(1:mdofn) !0,no the freedom;1,sppead;2,acceleration
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_order_time_mdofn,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_11,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)beeta1,beeta2,theta1
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_newmark,0)
    print *,'beeta1,beeta2,theta1=',beeta1,beeta2,theta1
    allocate(appear_process(1:ngroup,0:nblks),appear(ngroup),water_level(nblks), &
        hdam(nblks),uinitial(nblks),matno_process(ngroup,nblks),modf_dis_blocks(nblks))
    if(state_change==1) allocate(state_change_process(1:ngroup,nblks))
    if(state_change==1) state_change_process=0
    appear_process(:,0)=0
    modf_dis_blocks=0

    allocate(equvs_process(ngroup),average_appear(ngroup)) !zhao 05/07/30

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_12,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)equvs_process(1:ngroup)
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_equvs_process,0)
    !levelset
    allocate(appear_level(ngroup))
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_13,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)appear_level(1:ngroup)
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_appear_level,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_14,0)
    print *,text
    do iblk=1,nblks
        read(gunit,*,iostat=yl_ios,iomsg=yl_msg)appear_process(1:ngroup,iblk)
        call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_appear_process,iblk)
        print *,'appear_process=',appear_process(1:ngroup,iblk)
    end do

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_15,0)
    print *,text
    do iblk=1,nblks
        read(gunit,*,iostat=yl_ios,iomsg=yl_msg)matno_process(1:ngroup,iblk)
        call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_matno_process,iblk)
        print *,'iblks=',iblks,'ngroup=',ngroup,'matno=',matno_process(1:ngroup,iblk)
    end do

    if(state_change==1)then !11/23/2014
        read(gunit,*)text
        print *,text
        do iblk=1,nblks
            read(gunit,*)state_change_process(1:ngroup,iblk)
            print *,'iblks=',iblks,'state_change_process=',state_change_process(1:ngroup,iblk)
        end do
    endif

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text               !zhao 05/08/05
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_16,0)
    allocate(force_process(ngroup))
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)force_process(1:ngroup)
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_force_process,0)

    print *,'force_process=',force_process

    average_appear=0 !for stress average
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_17,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)average_appear(1:ngroup) !=0 不参与应力平均，=1应力外推 =2 应力直接平均 =-1按原来方式外推 =-2按原来方式直接平均
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_average_appear,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_18,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)gid_u,gid_s,gid_ms,gid_f,gid_rot,gid_v,gid_a,gid_T,gid_P,  &
        gid_Pv,gid_ep,gid_Y,gid_FC,gid_Ns,gid_Ss,gid_Mxy,gid_bem,gid_wh,gid_wv,gid_bcs  !20210328
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_gid_flags,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_19,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)res_u,res_s,res_ms,res_f,res_rot,res_v,res_a,res_T,res_P,   &
        res_Pv,res_ep,res_Y,res_FC,res_Ns,res_Ss,res_Tv,res_Pa   !20210324
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_res_flags,0)

    if (gid_bem==1)then  !20200311
        open(bem_msh_unit,file=probn(1:len1)//'bem.flavia.msh',buffered='YES',blocksize=1048576)
        open(bem_res_unit,file=probn(1:len1)//'bem.flavia.res',buffered='YES',blocksize=1048576)
    endif !20200311

    if (gid_bcs==1)then  !20200311
        open(bcs_msh_unit,file=probn(1:len1)//'bcs.flavia.msh',buffered='YES',blocksize=1048576)
        open(bcs_res_unit,file=probn(1:len1)//'bcs.flavia.res',buffered='YES',blocksize=1048576)
    endif !20200311

    if (gid_Mxy==1)then  !20200311
        open(mxy_msh_unit,file=probn(1:len1)//'mxy.flavia.msh',buffered='YES',blocksize=1048576)
        open(mxy_res_unit,file=probn(1:len1)//'mxy.flavia.res',buffered='YES',blocksize=1048576)
    endif !20200311


    write(7,*)'irecover=',irecover

    allocate(listglocbeam(ngroup))
    listglocbeam=0
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text       !ifs2006 zhao, 06/03/29
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_20,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)Icaddmass,swlifs2006,toth,ifswater,ifsgravity,absorb,alfa_p4,stiff_p4
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_fsi_params,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text   !steel 2006
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_21,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)ftcrack,coefMpa,ikindks,doubsig,ktan1,ktan2,nlocalbeam,ndimnrt,listglocbeam(1:nlocalbeam),lelenrt(1:ndimnrt)
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_crack_and_beam,0)
    !ftcrack-脆性开裂时用，抗拉强度
    !coefMpa-粘结滑移时的系数，10^6/E的单位，比如:弹模采用Pa,coefMpa=10^6,弹模采用kPa,coefMpa=10^3
    !ikindks-粘结滑移曲线类型
    !doubsig-=1单弹簧，=2双弹簧
    !ktan1、ktan2法向刚度，可取10^8kN/m^3
    !nlocalbeam-几组单元用局部坐标系求解，共用结点的组要么全是整体，要么全是局部
    !ndimnrt=有多少个粘结单元切向固结
    !listglocbeam=局部坐标系求解的组列表
    !lelenrt=切向固结单元列表
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text !hxl2006 MIF
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_22,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)ntrans,nlaymif,epsMIFb,gamaMIF,ifixvar0_inpb,camif,dxmif
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_transform_and_mif,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_23,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)hdam(1:nblks)
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_hdam,0)

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_24,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)water_level(1:nblks)  !20220409
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_water_level,0)

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_25,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)modf_dis_blocks(1:nblks)
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_modf_dis_blocks,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_26,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)uinitial(1:nblks)
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_uinitial,0)


    print *,'uinitial=',uinitial(1:nblks)

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text  !输入与nbackf/=0时的相关内容
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_27,0)



    if(nbspring>0)then  !20150925

        allocate(bspring(nbspring))
        read(gunit,*)text
        print *,text

        do idofn=1,nbspring
            read(gunit,*) bspring(idofn)%listp,bspring(idofn)%listdim,bspring(idofn)%spring
            print *,'bspring(idofn)%listp,bspring(idofn)%listdim,bspring(idofn)%spring',bspring(idofn)%listp,bspring(idofn)%listdim,bspring(idofn)%spring

        enddo

    endif  !20150925


    cdofn=0
    do idofn=1,mdofn
        if (lmdofn(idofn)/=0) then
            cdofn=cdofn+1
            lmdofn(idofn)=cdofn
            lcdofn(cdofn)=idofn
        end if
    end do

    if (mdofn>=8 ) then
        if (lmdofn(8)/=0.and.(type_problem/='Q'.or.(type_problem=='Q'.and.uwcpl==1))) then
            allocate(prstat(npoin))
            prstat=0.0
        endif
    endif

    allocate(coord(ndimn,npoin),element(nelem),nodfn(cdofn,npoin))

    if(Blarge==1)allocate(coord0(ndimn,npoin))  !20221102
    allocate(links(nlinks),group(ngroup)) !,gaps(ngaps)) !contact

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_28,0)
    print *,text
    do ilink=1,nlinks

        read(gunit,*)npairs
        links(ilink)%npairs=npairs
        allocate(links(ilink)%link_freedom(cdofn),links(ilink)%pairnode(2,npairs))
        read(gunit,*)links(ilink)%link_freedom(1:cdofn)
        do ipair=1,npairs
            read(gunit,*)i0,links(ilink)%pairnode(1:2,ipair)
        end do

    end do

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_29,0)
    print *,text
    do ilink=1,ntlink
        read(gunit,*)i0,tlink(1:2,ilink)
    end do

    !!  contact
    !   read(gunit,*)text
    !   print *,text
    !   do ilink=1,ngaps
    !      read(gunit,*)npairs,gaps(ilink)%gap
    !      gaps(ilink)%npairs=npairs
    !      allocate(gaps(ilink)%pairnode(2,npairs))
    !      do ipair=1,npairs
    !      read(gunit,*)i0,gaps(ilink)%pairnode(1:2,ipair)
    !      end do
    !   end do
    !! end contact

    do ipoin=1,npoin   !!!read coordinate
        read(cunit,*,iostat=yl_ios,iomsg=yl_msg)i0,coord(1:ndimn,ipoin)
        call diag_check_read(yl_ios,yl_msg,RD_COR_global_data_node_coordinates,ipoin)
        if(i0/=ipoin)then   ! M1-03 contract: node id equals record order (old code ignored i0)
            if(i0>=1.and.i0<ipoin)then
                call diag_dup(RD_COR_global_data_node_coordinates,ipoin,'i0',int(i0,i8))
            else
                call diag_range(RD_COR_global_data_node_coordinates,ipoin,'i0',int(i0,i8),int(ipoin,i8),int(ipoin,i8))
            endif
        endif
    end do
    call diag_flush_stage()

    if(Blarge==1)coord0=coord   !20221102

    call kinddefine

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_30,0)
    print *,'text1=',text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_31,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_32,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_33,0)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_34,0)
    print *,text



    allocate(listp_group(npoin))  !2003/10/31
    listp_group(1:npoin)%mgroup=0 !2003/10/31

    tne=0
    ielem=0
    nelsum=0
    do igroup=1,ngroup    !!igroup  for elements

        print *,'igroup=',igroup
        read(gunit,*,iostat=yl_ios,iomsg=yl_msg)group(igroup)%name,       group(igroup)%kname,      group(igroup)%index,      &
            group(igroup)%class,      group(igroup)%nrfields,   group(igroup)%fieldid,    &
            group(igroup)%special,    group(igroup)%sptype,     group(igroup)%nelgroup,   &
            group(igroup)%matno,      group(igroup)%type_nalgo, group(igroup)%type_stiff, &
            group(igroup)%type_ecoint,group(igroup)%ilayer,     elcod_local,group_inf,  &
            group(igroup)%uplift_ic,group(igroup)%liquj  !20220409
        call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_group_header,igroup)
        print *,'name=',group(igroup)%name
        ! M1-03 group header guard: index selects the element kind table, nrfields/nelgroup size allocations, matno is consumed per element
        if(group(igroup)%index<1.or.group(igroup)%index>ekind) &
            call diag_unsupported(RD_GLB_global_data_group_header,igroup,'index',diag_itoa(int(group(igroup)%index,i8)),'1..'//trim(diag_itoa(int(ekind,i8))))
        call diag_range(RD_GLB_global_data_group_header,igroup,'nrfields',int(group(igroup)%nrfields,i8),1_i8,diag_max_entities())
        call diag_ref(RD_GLB_global_data_group_header,igroup,'matno',int(group(igroup)%matno,i8),1_i8,int(nmats,i8))
        call diag_range(RD_GLB_global_data_group_header,igroup,'nelgroup',int(group(igroup)%nelgroup,i8),0_i8,int(nelem,i8)-int(nelsum,i8))
        call diag_flush_stage()
        nelsum=nelsum+group(igroup)%nelgroup
        call diag_product(RD_GLB_global_data_group_header,igroup,'nelgroup*nnode',[int(group(igroup)%nelgroup,i8),int(elkn(group(igroup)%index)%nnode,i8)])
        call diag_flush_stage()

        nrfields=group(igroup)%nrfields
        group(igroup)%elcod_local=elcod_local
        group(igroup)%kinit_g=kinit    !20220713

        allocate(group(igroup)%type_mass(nrfields),group(igroup)%order_time(2,nrfields))
        allocate(group(igroup)%list(group(igroup)%nelgroup))
        allocate(group(igroup)%dof(nrfields))
        read(gunit,*,iostat=yl_ios,iomsg=yl_msg)group(igroup)%type_mass(1:nrfields),group(igroup)%alfa,group(igroup)%beta
        call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_group_mass_damping,igroup)
        !write(7,*)'group(igroup)%type_mass(1:nrfields),group(igroup)%alfa,group(igroup)%beta=',group(igroup)%type_mass(1:nrfields),group(igroup)%alfa,group(igroup)%beta
        read(gunit,*,iostat=yl_ios,iomsg=yl_msg)(group(igroup)%order_time(:,ifield),ifield=1,group(igroup)%nrfields)  !907
        call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_group_order_time,igroup)
        !write(7,*)'order-Time=', (group(igroup)%order_time(:,ifield),ifield=1,group(igroup)%nrfields)

        if(group(igroup)%index==20.or.group(igroup)%index==21.or.group(igroup)%index==22.or.group(igroup)%index==26) &
            read(gunit,*) group(igroup)%point_direct   !20230910
        if(group(igroup)%index==20)print *,'group(igroup)%point_direct=',group(igroup)%point_direct

        allocate(mdof(nrfields))
        do ifield=1,nrfields
            read(gunit,*,iostat=yl_ios,iomsg=yl_msg)nfdof
            call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_group_nfdof,igroup)
            call diag_range(RD_GLB_global_data_group_nfdof,igroup,'nfdof',int(nfdof,i8),1_i8,int(mdofn,i8))   ! M1-03
            call diag_flush_stage()
            !print *,'ifield=',ifield,'nfdof=',nfdof
            group(igroup)%dof(ifield)%nfdof=nfdof
            mdof(ifield)=nfdof
            allocate(group(igroup)%dof(ifield)%listdof_f(nfdof))
            read(gunit,*,iostat=yl_ios,iomsg=yl_msg)group(igroup)%dof(ifield)%listdof_f(1:nfdof)
            call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_group_listdof,igroup)
            do i0=1,nfdof   ! M1-03: every listed dof must exist
                call diag_range(RD_GLB_global_data_group_listdof,igroup,'listdof',int(group(igroup)%dof(ifield)%listdof_f(i0),i8),1_i8,int(mdofn,i8))
            end do
            call diag_flush_stage()
        end do

        index=group(igroup)%index
        name=group(igroup)%name !why
        matno=group(igroup)%matno
        nelgroup=group(igroup)%nelgroup
        fieldid=group(igroup)%fieldid
        ncouple=elkn(index)%ncouple
        class=group(igroup)%class

        nstre=3*(ndimn-1)
        name=group(igroup)%sptype !why
        special=group(igroup)%special
        group(igroup)%nnode_dd=0
        if(index==3)group(igroup)%nnode_dd=6
        if(index==5)group(igroup)%nnode_dd=8
        if(index==9)group(igroup)%nnode_dd=20

        if(ndimn==2)nstre=4
        if(class=='BM'.or.index==1)nstre=1 !why
        group(igroup)%nstre=nstre

        tvol=0.
        do ielgroup=1,nelgroup
            ielem=ielem+1
            !if(igroup==6) &
            !print *,'igroup=',igroup,'ifield=',ifield,'ie=',ielem
            call read_element(index, igroup,name,matno,nstre,nelem,          &
                ielem,coord,eunit,element,mdof,ndimn,           &
                special,elcod_local,group_inf,src,group(igroup)%point_direct)
            if(ele_scan_only)cycle   ! M1-03: a bad .ele record was seen; only scan the rest, fail after the groups


            !         write(chkunit,10)ielem,element(ielem)%field(1)%lnods_f,igroup
10          format(10i10)

            !! allocate element stiff matrix
            tne=tne+1
            !         if(index/=20.and.index/=21)tvol=tvol+sum(element(ielem)%egaus(1)%djacb(:))
            if(index/=20.and.index/=21.and.index/=25)tvol=tvol+sum(element(ielem)%egaus(1)%djacb(:)) !steel 2006
            do ifield=1,nrfields
                nnode=elkn(index)%el_field(ifield)%nnode_f
                nevab=nnode*mdof(ifield)
                allocate(element(ielem)%field(ifield)%khandmc(1)%fstif(nevab,nevab))
                element(ielem)%field(ifield)%khandmc(1)%fstif=0.0

                !! stablize
                if (stabpw==1.and.(fieldid(ifield:ifield)=='W'.or.fieldid(ifield:ifield)=='P'))then
                    allocate(element(ielem)%field(ifield)%khandmc(1)%hstar(nevab,nevab))
                    element(ielem)%field(ifield)%khandmc(1)%hstar=0.
                endif
                !! end stablize
                allocate(element(ielem)%field(ifield)%tload(nevab))
                allocate(element(ielem)%field(ifield)%eload(nevab))
                allocate(element(ielem)%field(ifield)%rload(nevab))

                element(ielem)%field(ifield)%tload=0.0
                element(ielem)%field(ifield)%eload=0.0
                element(ielem)%field(ifield)%rload=0.0


                type_mass=group(igroup)%type_mass(ifield)
                if (fieldid(ifield:ifield)/='U'.or.(fieldid(ifield:ifield)=='U'.and.  &
                    (type_problem=='E'.or.type_problem/='Q'.or.stabpw==1))) then
                    if (type_mass==0.and.index.ne.20.and.index.ne.21.and.index/=22.and.index/=26)then
                        allocate(element(ielem)%field(ifield)%khandmc(2)%fstif(nevab,1))
                        element(ielem)%field(ifield)%khandmc(2)%fstif=0.0
                    else
                        allocate(element(ielem)%field(ifield)%khandmc(2)%fstif(nevab,nevab))
                        element(ielem)%field(ifield)%khandmc(2)%fstif=0.0
                    endif
                endif
            end do !! ifield

            if(ncouple/=0)allocate(element(ielem)%cstif(ncouple))

            do icouple=1,ncouple
                field1=elkn(index)%couple(icouple)%field_couple(1)
                field2=elkn(index)%couple(icouple)%field_couple(2)
                nnode1=elkn(index)%el_field(field1)%nnode_f
                nnode2=elkn(index)%el_field(field2)%nnode_f
                nevab1=nnode1*mdof(field1)
                nevab2=nnode2*mdof(field2)
                allocate(element(ielem)%cstif(icouple)%qmatx(nevab1,nevab2))
                element(ielem)%cstif(icouple)%qmatx=0.0
                !! stablize
                if (stabpw==1.and.(fieldid(1:2)=='UW'.or.fieldid(1:2)=='UP')) then
                    allocate(element(ielem)%cstif(icouple)%qstab(nevab1,nevab2))
                    element(ielem)%cstif(icouple)%qstab=0.0
                endif
                !! end stablize
            end do
            group(igroup)%list(ielgroup)=ielem
        end do !!ielgroup
        if(ele_scan_only)then   ! M1-03: nothing below may touch the unread elements
            deallocate(mdof)
            cycle
        endif
        if(index/=20.and.index/=21)write(chkunit,*)'igroup=',igroup,'tvol=',tvol

        !!!!!!!!!2003/10/31
        allocate(appear_node(npoin),corsp(npoin))
        appear_node=0
        corsp=0
        do ielgroup=1,nelgroup
            ielem=group(igroup)%list(ielgroup)
            lnods=>element(ielem)%field(1)%lnods_f
            do inode=1,size(lnods)
                lnode=lnods(inode)
                appear_node(lnode)=appear_node(lnode)+1
            end do
            nullify(lnods)
        end do
        !   write(7,*)'appear_node=',appear_node
        np_unode=0
        do ipoin=1,npoin
            if (appear_node(ipoin)/=0)then
                np_unode=np_unode+1
                corsp(ipoin)=np_unode
                listp_group(ipoin)%mgroup=listp_group(ipoin)%mgroup+1
            endif
        end do

        allocate(group(igroup)%unode(np_unode))
        np_unode=0
        do ipoin=1,npoin
            if (appear_node(ipoin)/=0)then
                np_unode=np_unode+1
                group(igroup)%unode(np_unode)%ipoin=ipoin
                group(igroup)%unode(np_unode)%ne_unode=appear_node(ipoin)
                allocate(group(igroup)%unode(np_unode)%list(appear_node(ipoin)))
            endif
        end do

        allocate(listx(npoin))
        listx=0
        do ielgroup=1,nelgroup
            ielem=group(igroup)%list(ielgroup)
            lnods=>element(ielem)%field(1)%lnods_f
            !         appear_node=0
            do inode=1,size(lnods)
                lnode=lnods(inode)
                !            if (appear_node(lnode)==0)then
                listx(lnode)=listx(lnode)+1
                group(igroup)%unode(corsp(lnode))%list(listx(lnode))=ielem
                !               appear_node(lnode)=1
                !            endif
            end do
            nullify(lnods)
        end do
        deallocate(listx,appear_node,corsp)
        group(igroup)%np_unode=np_unode

        !!!!!!!!!2003/10/31

        !! stablize
        if (stabpw==1.and.(fieldid(2:2)=='P'.or.fieldid(2:2)=='W')) then
            do ipoin=1,np_unode  !!! ipoin
                ne_unode=group(igroup)%unode(ipoin)%ne_unode
                allocate(appear_node(npoin))
                appear_node=0
                nnode=elkn(index)%el_field(2)%nnode_f
                do ie=1,ne_unode
                    jelem=group(igroup)%unode(ipoin)%list(ie)
                    do inode=1,nnode
                        lnode=element(jelem)%field(2)%lnods_f(inode)
                        appear_node(lnode)=1
                    end do
                end do
                np_unode=sum(appear_node)
                group(igroup)%unode(ipoin)%np_unode=np_unode
                allocate(group(igroup)%unode(ipoin)%patch_nod(np_unode),          &
                    group(igroup)%unode(ipoin)%patch_sta(np_unode,np_unode), &
                    group(igroup)%unode(ipoin)%patch_load(np_unode))
                np_unode=0
                do jpoin=1,npoin      ! jpoin
                    if (appear_node(jpoin)/=0) then
                        np_unode=np_unode+1
                        group(igroup)%unode(ipoin)%patch_nod(np_unode)=jpoin
                    endif
                end do          ! jpoin
                deallocate(appear_node)
            end do  !!! for ipoin
        endif
        !! end for stablize

        deallocate(mdof)
        write(chkunit,*)'igroup=',igroup,'tne=',tne
    end do   !!igroup
    ! M1-03: the groups must account for every element; also flushes .ele record diagnostics
    call diag_range(RD_GLB_global_data_group_header,ngroup,'nelgroup',int(nelsum,i8),int(nelem,i8),int(nelem,i8))
    call diag_flush_stage()

    !stop

    do ipoin=1,npoin
        mgroup=listp_group(ipoin)%mgroup
        if(mgroup>0)allocate(listp_group(ipoin)%listg(mgroup),listp_group(ipoin)%listp(mgroup))
        listp_group(ipoin)%mgroup=0
    end do

    do igroup=1,ngroup
        do i0=1,group(igroup)%np_unode
            ipoin=group(igroup)%unode(i0)%ipoin
            listp_group(ipoin)%mgroup=listp_group(ipoin)%mgroup+1
            listp_group(ipoin)%listg(listp_group(ipoin)%mgroup)=igroup
            listp_group(ipoin)%listp(listp_group(ipoin)%mgroup)=i0
        end do
    end do

    print *,'tne=',tne

    if(alfa_p4>0)call form_ipp4 !p42010  !20221124

    call set_elem_dofs
    call set_dofs_layer


    !!int2000
    allocate(trans(ntotv))
    trans(1:ntotv)%nintf=0
    if(meshc/=0) goto 111
    if(rmesh/=0) goto 222
    read(nrtunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_NRT_global_data_title_1,0)
    read(nrtunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_NRT_global_data_title_2,0)
    read(nrtunit,*,iostat=yl_ios,iomsg=yl_msg)transgroup
    call diag_check_read(yl_ios,yl_msg,RD_NRT_global_data_transgroup,0)
    do itransgroup=1,transgroup
        read(nrtunit,*)ntransnode,translg
        print *, 'ntransnode,translg=',ntransnode,translg
        if (translg==0) then
            do itrans=1,ntransnode
                read(nrtunit,*)title_intp,ipoin,nintf  !20200220
                allocate(listf(nintf),rintf(nintf))
                if(title_intp(1:4)=='TRAL')then  !20200220
                    read(nrtunit,*)listf
                    read(nrtunit,*)rintf

                    do idofn=1,mdofn
                        if (lmdofn(idofn)/=0)then
                            itotv=nodfn(lmdofn(idofn),ipoin)
                            IF(itotv>0)then
                                trans(itotv)%nintf=nintf
                                allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                                trans(itotv)%listf=nodfn(lmdofn(idofn),listf)
                                trans(itotv)%rintf=rintf
                            endif
                        endif
                    end do
                end if  !20200220
                deallocate(listf,rintf)
            end do

        elseif(translg==99)then
            do itrans=1,ntransnode
                read(nrtunit,*)ipoin,nintf
                allocate(listf(nintf),rintf(nintf))
                read(nrtunit,*)listf
                read(nrtunit,*)rintf
                do idofn=1,mdofn
                    if (lmdofn(idofn)/=0)then
                        itotv=nodfn(lmdofn(idofn),ipoin)
                        trans(itotv)%nintf=nintf
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        trans(itotv)%listf=nodfn(lmdofn(idofn),listf)
                        trans(itotv)%rintf=rintf
                    endif
                end do
                deallocate(listf,rintf)
            end do
            ! by zhao 2005/12/27 , special for WuDongde
        elseif(translg==88)then
            do itrans=1,ntransnode
                read(nrtunit,*)title_intp,ipoin,nintf
                if(title_intp(1:4)=='TRAL')then
                    allocate(listf(nintf),rintf(nintf))
                    read(nrtunit,*)listf
                    read(nrtunit,*)rintf
                    !write(7,*)'itrans=',itrans,'ipoin=',ipoin,'listf=',listf,'rintf=',rintf
                    do idofn=1,ndimn
                        if (lmdofn(idofn)/=0)then

                            itotv=nodfn(lmdofn(idofn),ipoin)
                            trans(itotv)%nintf=nintf
                            allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                            trans(itotv)%listf=nodfn(lmdofn(idofn),listf)
                            trans(itotv)%rintf=rintf
                            !write(7,*)'idofn=',idofn,'lmdofn=',lmdofn(idofn),'ipoin=',ipoin,'itotv=',itotv,'nintf=',nintf
                            !write(7,*)'listf=',trans(itotv)%listf,'rintf=',trans(itotv)%rintf
                        endif
                    end do
                    deallocate(listf,rintf)
                endif

                if(title_intp(1:4)=='ROTA')then

                    !if(ndimn==2.and.title_intp(1:5)=='ROTAZ')then
                    if(ndimn==2)then   !20221130
                        itotv=nodfn(lmdofn(4),ipoin)
                        trans(itotv)%nintf=nintf
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        do idofn=1,nintf
                            read(nrtunit,*)jpoin,jdimn,f0
                            trans(itotv)%listf(idofn)=nodfn(jdimn,jpoin)
                            trans(itotv)%rintf(idofn)=f0

                            !write(chkunit,*)'itotv=',itotv,'listf=',trans(itotv)%listf(idofn),'rintf=',trans(itotv)%rintf(idofn)
                        enddo
                    endif

                    if(ndimn==3.and.title_intp(1:5)=='ROTAX')then
                        itotv=nodfn(lmdofn(4),ipoin)
                        trans(itotv)%nintf=nintf
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        do idofn=1,nintf
                            read(nrtunit,*)jpoin,jdimn,f0
                            trans(itotv)%listf(idofn)=nodfn(jdimn,jpoin)
                            trans(itotv)%rintf(idofn)=f0
                        end do
                    endif

                    if(ndimn==3.and.title_intp(1:5)=='ROTAY')then
                        itotv=nodfn(lmdofn(5),ipoin)
                        trans(itotv)%nintf=nintf
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        do idofn=1,nintf
                            read(nrtunit,*)jpoin,jdimn,f0
                            trans(itotv)%listf(idofn)=nodfn(jdimn,jpoin)
                            trans(itotv)%rintf(idofn)=f0
                        end do
                    endif

                    if(ndimn==3.and.title_intp(1:5)=='ROTAZ')then
                        itotv=nodfn(lmdofn(6),ipoin)
                        trans(itotv)%nintf=nintf
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        do idofn=1,nintf
                            read(nrtunit,*)jpoin,jdimn,f0
                            trans(itotv)%listf(idofn)=nodfn(jdimn,jpoin)
                            trans(itotv)%rintf(idofn)=f0
                        end do
                    endif


                endif


            end do
            ! by LTC 2020/01/12 , 桩作为梁单元处理，作为从节点处理。
        elseif(translg==-10)then

            do itrans=1,ntransnode
                read(nrtunit,*)ipoin,nintf
                allocate(listf(nintf),rintf(nintf))
                read(nrtunit,*)listf
                read(nrtunit,*)rintf
                do idofn=8,8
                    if (lmdofn(idofn)/=0)then
                        itotv=nodfn(lmdofn(idofn),ipoin)
                        trans(itotv)%nintf=nintf
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        trans(itotv)%listf=nodfn(lmdofn(idofn),listf)
                        trans(itotv)%rintf=rintf
                    endif
                end do
                deallocate(listf,rintf)
            end do
        elseif(translg==10)then
            !*******for plate to body elements
            do itrans=1,ntransnode
                read(nrtunit,*)i0,ipoin,jpoin,idfn(1:2),jdfn(1:2),f12(1:2)
                do i0=1,2
                    itotv=nodfn(lmdofn(idfn(i0)),ipoin)
                    nintf=trans(itotv)%nintf
                    if (nintf==0)then
                        nintf=2
                        trans(itotv)%nintf=2
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        jtotv=nodfn(lmdofn(idfn(i0)),jpoin)
                        trans(itotv)%listf(1)=jtotv;trans(itotv)%rintf(1)=1.
                        jtotv=nodfn(lmdofn(jdfn(i0)),jpoin)
                        trans(itotv)%listf(2)=jtotv;trans(itotv)%rintf(2)=f12(i0)
                    else
                        allocate(listf(nintf),rintf(nintf))
                        listf=trans(itotv)%listf
                        rintf=trans(itotv)%rintf
                        deallocate(trans(itotv)%listf,trans(itotv)%rintf)
                        nintf=nintf+1
                        trans(itotv)%nintf=nintf
                        allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                        trans(itotv)%listf(1:(nintf-1))=listf
                        trans(itotv)%rintf(1:(nintf-1))=rintf
                        deallocate(listf,rintf)
                        jtotv=nodfn(lmdofn(jdfn(i0)),jpoin)
                        trans(itotv)%listf(nintf)=jtotv
                        trans(itotv)%rintf(nintf)=f12(i0)
                    endif
                end do  ! i0

                do idimn=1,ndimn
                    if (idimn/=idfn(1).and.idimn/=idfn(2))then
                        itotv=nodfn(lmdofn(idimn),ipoin)
                        nintf=trans(itotv)%nintf
                        if (nintf==0)then
                            nintf=1
                            trans(itotv)%nintf=nintf
                            allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                            jtotv=nodfn(lmdofn(idimn),jpoin)
                            trans(itotv)%listf(nintf)=jtotv
                            trans(itotv)%rintf(nintf)=1.
                        endif
                    endif
                end do
            end do
        elseif(translg==20)then
            !*******for beam to body element nodes

            do itrans=1,ntransnode
                read(nrtunit,*)i0,ipoin,i1
                do idimn=1,ndimn
                    itotv=nodfn(lmdofn(idimn),ipoin)
                    trans(itotv)%nintf=12
                    nintf=12
                    allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                    ipoin1=element(i1)%field(1)%lnods_f(1)
                    ipoin2=element(i1)%field(1)%lnods_f(2)
                    trans(itotv)%listf(1:6)=nodfn(lmdofn(1:6),ipoin1)
                    trans(itotv)%listf(7:12)=nodfn(lmdofn(1:6),ipoin2)
                    read(nrtunit,*)trans(itotv)%rintf(1:nintf)
                end do
            end do
        elseif(translg==30)then

            !*******for beam to internal beam element  nodes

            do itrans=1,ntransnode
                read(nrtunit,*)i0,ipoin,i1
                do idimn=1,3*(ndimn-1)
                    itotv=nodfn(lmdofn(idimn),ipoin)
                    trans(itotv)%nintf=12
                    nintf=12
                    allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                    ipoin1=element(i1)%field(1)%lnods_f(1)
                    ipoin2=element(i1)%field(1)%lnods_f(2)
                    trans(itotv)%listf(1:6)=nodfn(lmdofn(1:6),ipoin1)
                    trans(itotv)%listf(7:12)=nodfn(lmdofn(1:6),ipoin2)
                    read(nrtunit,*)trans(itotv)%rintf(1:nintf)
                end do
            end do

        elseif(translg==40)then  !20231008
            !*******for shell to body element nodes壳中心点与表面节点位移转换（表面节点为整体位移，壳中心节点为局部坐标位移）
            ! 给定插值系数已经考虑了空间坐标系的转换

            do itrans=1,ntransnode
                read(nrtunit,*)i0,ipoin,jpoin
                do idimn=1,ndimn
                    itotv=nodfn(lmdofn(idimn),ipoin)
                    trans(itotv)%nintf=6
                    nintf=6
                    allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                    trans(itotv)%listf(1:6)=nodfn(lmdofn(1:6),jpoin)
                    read(nrtunit,*)trans(itotv)%rintf(1:nintf)
                end do
            end do


            !***********
        else
            read(nrtunit,*)ntlg !,ielem
            allocate(listx(ntlg),rotation(ndimn,ndimn))
            read(nrtunit,*)rotation(1,:)
            read(nrtunit,*)rotation(2,:)
            read(nrtunit,*)rotation(3,:)
            read(nrtunit,*)listx
            do i0=1,ntlg
                ipoin=listx(i0)
                do idofn=1,ndimn
                    itotv=nodfn(lmdofn(idofn),ipoin)
                    allocate(trans(itotv)%listf(ndimn),trans(itotv)%rintf(ndimn))
                    trans(itotv)%nintf=ndimn
                    trans(itotv)%listf=nodfn(lmdofn(1:ndimn),ipoin)
                    trans(itotv)%rintf=rotation(idofn,:)
                end do
                if (translg==2) then
                    do idofn=4,6
                        itotv=nodfn(lmdofn(idofn),ipoin)
                        allocate(trans(itotv)%listf(ndimn),trans(itotv)%rintf(ndimn))
                        trans(itotv)%nintf=ndimn
                        trans(itotv)%listf=nodfn(lmdofn(4:6),ipoin)
                        trans(itotv)%rintf=rotation(idofn-3,:)
                    end do
                endif
            end do
            deallocate(listx,rotation)
        endif
    end do !itransgroup
    goto 222
    !!int2000
    !!int2000
111 continue
    allocate(trans_c(npoin))
    trans_c(1:npoin)%nintf=0
    read(nrtunit,*)text
    read(nrtunit,*)transgroup
    do itrans=1,transgroup
        read(nrtunit,*)ipoin,nintf
        trans_c(ipoin)%nintf=nintf
        allocate(trans_c(ipoin)%listf(abs(nintf)),trans_c(ipoin)%rintf(abs(nintf)))
        read(nrtunit,*)trans_c(ipoin)%listf
        read(nrtunit,*)trans_c(ipoin)%rintf
    end do
    !!!!!!!!!!!!!!!!2003/10/30 for refine mesh
222 continue

    if (meshc==1.or.meshc==2) then  !if(meshc/=0) then
        allocate(appear_p(ngroup))
        read(nrtunit,*)text
        read(nrtunit,*)text
        read(nrtunit,*)ngroup0
        do igroup=1,ngroup0
            read(nrtunit,*)i0,group(igroup)%cgroup
            if (meshc==2.and.group(igroup)%cgroup/=0)then
                allocate(group(igroup)%lcgroup(group(igroup)%cgroup))
                read(nrtunit,*)group(igroup)%lcgroup
            endif
        end do

        do igroup=ngroup0+1,ngroup
            read(nrtunit,*)i0,group(igroup)%cgroup
            print *,'igroup=',igroup,'i0=',i0
        end do
    endif
    !!!!!!!!!!!!!!!!!!!!!2003/10/30

    !special for hjd
    allocate (tension_joint(nelem))
    tension_joint=0
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_35,0)
    print*,'text_tension_joint=',text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)tsel
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_tension_joint_count,0)
    if (tsel/=0) then
        allocate(icxx(tsel))
        icxx=0
        read(gunit,*)icxx
        tension_joint(icxx)=1
        deallocate(icxx)
    endif
    ! special for hjd

    ! contact  !zhao 05/07/22
    allocate (tension_contact(nelem))
    tension_contact=0
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_title_36,0)
    print*,'text_tension_contact=',text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)tsel
    call diag_check_read(yl_ios,yl_msg,RD_GLB_global_data_contact_joint_count,0)
    if (tsel/=0) then
        allocate(icxx(tsel))
        icxx=0
        read(gunit,*)icxx
        tension_contact(icxx)=1
        deallocate(icxx)
    endif

    !   write(chkunit,*)'nodfn='
    !   do ipoin=1,npoin
    !   write(chkunit,70)ipoin,nodfn(1:cdofn,ipoin)
    !   end do
    !70 format(i5,6(2x,i8))
    print *,'ground_inf=',ground_inf,'/100=',ground_inf/100
    if(ground_inf/100==1)call estif_semi_space_center
    if(ground_inf/100==2)call estif_semi_space

    !if(nbackf/=0)then !20230523
    !do idofn=1,nbackf
    ! do i0=1,backf(idofn)%mdism
    !     ip0=backf(idofn)%listp(i0);jp0=backf(idofn)%listdim(i0)
    !     backf(idofn)%listdof(i0)=nodfn(jp0,ip0)
    ! enddo
    !end do
    !endif !20230523

    if(nbspring>0)then !20150925
        do idofn=1,nbspring
            ip0=bspring(idofn)%listp;jp0=bspring(idofn)%listdim
            bspring(idofn)%listdof=nodfn(jp0,ip0)
        end do
    endif !20150925

    if(nbackf/=0)then  !20230523

        read(observc_unit,*)text
        print *,text,'nbackf=',nbackf
        allocate(backf(nbackf))

        do idofn=1,nbackf
            read(observc_unit,*)i0, backf(idofn)%groupb,backf(idofn)%mdism,backf(idofn)%wstep
            allocate( backf(idofn)%listp(backf(idofn)%mdism),   &
                backf(idofn)%dism(backf(idofn)%mdism,backf(idofn)%wstep),backf(idofn)%listdim(backf(idofn)%mdism),      &
                backf(idofn)%wtime(backf(idofn)%wstep),   &
                backf(idofn)%relat(backf(idofn)%mdism),backf(idofn)%ic(backf(idofn)%mdism)) !+ic，20210726

            do i0=1,backf(idofn)%mdism  !i0,20230523
                read(observc_unit,*)j0,jdofn,nintf  !,backf(idofn)%dism(i0)  !节点号，自由度，插值点数
                !print *,'i0=',i0,'j0,jdofn,nintf=',j0,jdofn,nintf
                allocate(listf(nintf),rintf(nintf))
                read(observc_unit,*)listf
                read(observc_unit,*)rintf
                allocate(backf(idofn)%relat(i0)%listf(nintf),backf(idofn)%relat(i0)%rintf(nintf),backf(idofn)%relat(i0)%listp(nintf))
                backf(idofn)%relat(i0)%nintf=nintf
                backf(idofn)%relat(i0)%rintf=rintf
                backf(idofn)%relat(i0)%listp=listf
                backf(idofn)%listdim(i0)=jdofn
                do i1=1,nintf  !i1
                    backf(idofn)%relat(i0)%listf(i1)=nodfn(lmdofn(jdofn),listf(i1))
                end do  !i1

                deallocate(listf,rintf)

            enddo   !i0,20230523

            read(observc_unit,*)text,wstep
            backf(idofn)%wstep=wstep
            read(observc_unit,*)backf(idofn)%wtime
            print *,'text,backf(idofn)%wstep=',text,backf(idofn)%wstep
            do j0=1, backf(idofn)%mdism!j0
                read(observc_unit,*)backf(idofn)%dism(j0,:)  !总位移（相对点号为零）或相对位
            enddo !j0 20230523

        enddo !idofn !20230523
    endif  !20230523(nbackf/=0.and.Bparameter==0)

    !!!!
    if(Bparameter>0.or.nbackdT==2)then !20230523
        read(back_ctl_unit,*)text  !输入与Bparameter/=0时的相关内容（不为零时，执行参数优化反演）
        read(back_ctl_unit,*)Npoints_pb   !20230523
        print *,'Npoints_pb=',Npoints_pb


        allocate(para_points(Npoints_pb))  !20230523

        read(back_ctl_unit,*)text  !20230523
        allocate(listdofn(4))
        Npoints_pbx=0
        do i=1,Npoints_pb
            read(back_ctl_unit,*)i0,xdofn,listdofn(1:xdofn),nintf
            Npoints_pbx=Npoints_pbx+xdofn
            allocate(para_points(i)%listf(nintf),para_points(i)%rintf(nintf),para_points(i)%listdofn(xdofn))
            allocate(para_points(i)%cor(ndimn))  !20231027
            para_points(i)%ndofn=xdofn
            para_points(i)%nintf=nintf
            para_points(i)%listdofn=listdofn(1:xdofn)
            read(back_ctl_unit,*)para_points(i)%listf
            read(back_ctl_unit,*)para_points(i)%rintf

            do idimn=1,ndimn
                para_points(i)%cor(idimn)=dot_product(coord(idimn,para_points(i)%listf),para_points(i)%rintf)  !20231027
            end do

        end do
        !read(back_ctl_unit,*)text  !20230709
        !read(back_ctl_unit,*)para_points(1:Npoints_pb)%begin_day_obs !20230709

        deallocate(listdofn) !20230523


        allocate(para_pointsx(Npoints_pbx))


        Npoints_pbx=0
        do i=1,Npoints_pb
            xdofn=para_points(i)%ndofn
            nintf=para_points(i)%nintf
            do j=1,xdofn
                Npoints_pbx=Npoints_pbx+1
                !write(7,*)'ipoint_pb=',i,'idofn=',j,'Npoints_pbx=',Npoints_pbx
                allocate(para_pointsx(Npoints_pbx)%listf(nintf),para_pointsx(Npoints_pbx)%rintf(nintf),para_pointsx(Npoints_pbx)%listdofn(1))
                allocate(para_pointsx(Npoints_pbx)%cor(ndimn))
                para_pointsx(Npoints_pbx)%ndofn=1
                para_pointsx(Npoints_pbx)%nintf=para_points(i)%nintf
                para_pointsx(Npoints_pbx)%listdofn(1)=para_points(i)%listdofn(j)
                para_pointsx(Npoints_pbx)%listf=para_points(i)%listf
                para_pointsx(Npoints_pbx)%rintf=para_points(i)%rintf
                para_pointsx(Npoints_pbx)%cor=para_points(i)%cor

                !para_pointsx(Npoints_pbx)%begin_day_obs=  &   !202030709
                !     para_points(i)%begin_day_obs

            end do
        end do

        deallocate(para_points)
        allocate(para_points(Npoints_pbx))

        do i=1,Npoints_pbx
            nintf=para_pointsx(i)%nintf
            allocate(para_points(i)%listf(nintf),para_points(i)%rintf(nintf),para_points(i)%listdofn(1))
            allocate(para_points(i)%cor(ndimn))
            para_points(i)%ndofn=1
            para_points(i)%nintf=nintf
            para_points(i)%listdofn(1)=para_pointsx(i)%listdofn(1)
            para_points(i)%listf=para_pointsx(i)%listf
            para_points(i)%rintf=para_pointsx(i)%rintf
            para_points(i)%cor=para_pointsx(i)%cor
            !para_points(i)%begin_day_obs=para_pointsx(i)%begin_day_obs !202030709

        end do

        deallocate(para_pointsx)



    endif !20230523

    !!!



    end  subroutine global_data


    !!!define the freedom of nodes and elements

    subroutine form_ipp4 !p42010

    integer(ink) igroup,index,ielgroup,ielem,inode,ipoin,jnode
    real   (irk) value

    integer (ink),allocatable::nnormp4(:)
    real(irk),pointer::normal(:)
    real(irk),allocatable::prot0(:,:,:)
    integer(ink),pointer::lnods(:)

    type p4p_type
        integer (ink) igroup
        real(irk),pointer::norm(:,:)
    end type p4p_type

    type(p4p_type),allocatable::p4p(:)

    allocate(p4p(npoin),nnormp4(npoin)) ; nnormp4=0

    do igroup=1,ngroup
        index=group(igroup)%index
        if(index/=22.and.index/=26)cycle
        DO ielgroup = 1,group(igroup)%nelgroup
            ielem = group(igroup)%list(ielgroup)
            lnods=>element(ielem)%field(1)%lnods_f
            normal=>element(ielem)%rotation(ndimn,:)
            do inode=1,size(lnods)
                ipoin=lnods(inode)
                nnormp4(ipoin)=nnormp4(ipoin)+1
            enddo
            nullify(lnods,normal)
        enddo
    enddo

    do ipoin=1,npoin
        if(nnormp4(ipoin)==0)cycle
        allocate(p4p(ipoin)%norm(ndimn,nnormp4(ipoin)))
    enddo
    nnormp4=0
    allocate(prot0(ndimn,ndimn,npoin)) !20221124
    prot0=0.
    do igroup=1,ngroup
        index=group(igroup)%index
        if(index/=22.and.index/=26)cycle
        DO ielgroup = 1,group(igroup)%nelgroup
            ielem = group(igroup)%list(ielgroup)
            lnods=>element(ielem)%field(1)%lnods_f
            normal=>element(ielem)%rotation(ndimn,:)
            do inode=1,size(lnods)
                ipoin=lnods(inode)
                nnormp4(ipoin)=nnormp4(ipoin)+1
                p4p(ipoin)%norm(:,nnormp4(ipoin))=normal
                prot0(:,:,ipoin)=prot0(:,:,ipoin)+element(ielem)%rotation(:,:) !20221124
            enddo
            nullify(lnods,normal)
        enddo
    enddo

    ipp4=1
    do ipoin=1,npoin
        if(nnormp4(ipoin)==0)cycle
        do inode=1,nnormp4(ipoin)
            do jnode=inode+1,nnormp4(ipoin)
                value=dot_product(p4p(ipoin)%norm(:,inode),p4p(ipoin)%norm(:,jnode))
                if(abs(value)<cosd(alfa_p4))then !abs(value),加ABS的原因是面有可能是相反的
                    ipp4(ipoin)=0
                    goto 10101
                endif
            enddo
        enddo
10101   continue
    enddo

    !write(7,*)'ipp4 for p4'
    !do ipoin=1,npoin
    !   if(ipp4(ipoin)==0)cycle
    !   write(7,*)'ipoin=',ipoin !ipp4(ipoin)==1的点，说明绕此点的单元的外法向夹角小于alfa_p4，也就是基本在一个平面内
    !enddo

    do ipoin=1,npoin
        if(nnormp4(ipoin)==0)cycle
        prot(:,:,ipoin)=prot0(:,:,ipoin)/nnormp4(ipoin) !20221124
        nullify(p4p(ipoin)%norm)
    enddo
    deallocate(nnormp4,p4p,prot0)  !20221124


    end subroutine form_ipp4

    subroutine set_elem_dofs

    integer (ink) ipoin,idofn,ielgroup,idofs,kpoin,igroup
    integer (ink) inode,ndofn_f,nnode_f,ifield,nrfields
    integer (ink) nelgroup,index,nnode,ielem
    integer (ink) nevab_f,nevabt1,nevabt2
    integer (ink) igapbf,jpoin,jpoin0,jdimn,i  !20210726
    integer (ink),allocatable::lnods(:),listdof(:)

    nodfn=0
    do igroup=1,ngroup

        nelgroup=group(igroup)%nelgroup
        index   =group(igroup)%index
        nnode   =elkn(index)%nnode
        nrfields=elkn(index)%nrfields

        do ielgroup=1,nelgroup
            ielem=group(igroup)%list(ielgroup)
            do ifield=1,nrfields   !!ifield
                !print *,'ielem=',ielem,'ifield=',ifield
                nnode_f=elkn(index)%el_field(ifield)%nnode_f
                ndofn_f=group(igroup)%dof(ifield)%nfdof
                allocate(listdof(ndofn_f),lnods(nnode_f))
                lnods=element(ielem)%field(ifield)%lnods_f
                listdof=group(igroup)%dof(ifield)%listdof_f
                listdof=lmdofn(listdof)
                nodfn(listdof,lnods(1:nnode_f))=1
                deallocate(listdof,lnods)
            end do                 !!end ifield
        end do
    end do

    !!20230523 !旧版本将监测点与网格节点重合，需要对位移分离反演的节点加入计算自由度，新版本不需要。
    !if(nbackf/=0)then
    !    		       do igapbf=1,nbackf
    !                     do kpoin=1,backf(igapbf)%mdism
    !              		   jpoin=backf(igapbf)%listp(kpoin)
    !                       jpoin0=backf(igapbf)%relatnode(kpoin)
    !                       jdimn=backf(igapbf)%listdim(kpoin)
    !                       if(jpoin/=0)nodfn(lmdofn(jdimn),jpoin)=1
    !                       if(jpoin0/=0)nodfn(lmdofn(jdimn),jpoin0)=1
    !                     end do
    !                    end do
    !endif
    !!20230523

    !20210803
    !if(Bparameter>0)then  !旧版本将监测点与网格节点重合，需要给定自由度，新版本不需要
    !  do i=1,Npoints_pb !20230523
    !  inode=para_points(i)%inode
    !  idofn=para_points(i)%idofn
    !  jnode=para_points(i)%jnode
    !if(inode/=0)nodfn(lmdofn(idofn),inode)=1
    !if(jnode/=0)nodfn(lmdofn(idofn),jnode)=1
    !  end do !20230523
    !endif
    !20210803


    ntotv=0

    do ipoin=1,npoin     !!! block for ntotv _____________!
        do idofn=1,cdofn                                   !
            if (nodfn(idofn,ipoin)==1) then                 !
                ntotv=ntotv+1                                !
                nodfn(idofn,ipoin)=ntotv                     !
            endif                                           !
        end do                                             !
    end do               !!!block for ntotv_______________!


    write(chkunit,*)'****** ntotv= ******',ntotv

    do igroup=1,ngroup

        nelgroup=group(igroup)%nelgroup
        index   =group(igroup)%index
        nnode   =elkn(index)%nnode
        nrfields=elkn(index)%nrfields

        do ielgroup=1,nelgroup
            ielem=group(igroup)%list(ielgroup)
            nevabt1=0
            do ifield=1,nrfields
                nnode_f=elkn(index)%el_field(ifield)%nnode_f
                ndofn_f=group(igroup)%dof(ifield)%nfdof
                nevab_f=nnode_f*ndofn_f
                nevabt1=nevabt1+1
                nevabt2=nevabt1+nevab_f-1

                idofs=0

                allocate(listdof(ndofn_f),lnods(nnode_f))

                lnods=element(ielem)%field(ifield)%lnods_f
                listdof=group(igroup)%dof(ifield)%listdof_f
                listdof=lmdofn(listdof)
                do inode=1,nnode_f
                    kpoin=lnods(inode)
                    do idofn=1,ndofn_f
                        if (nodfn(listdof(idofn),kpoin)/=0) then
                            idofs=idofs+1
                            element(ielem)%field(ifield)%ldofs_f(idofs)=nodfn(listdof(idofn),kpoin)
                        endif
                    end do
                end do
                element(ielem)%ldofs(nevabt1:nevabt2)=element(ielem)%field(ifield)%ldofs_f(1:nevab_f)
                nevabt1=nevabt2
                deallocate(listdof,lnods)
            end do       !!end ifield
        end do
    end do

    end subroutine set_elem_dofs

    subroutine set_dofs_layer

    integer (ink) ielgroup,igroup,ifield,nrfields,ilayer,nelgroup,index,ielem

    integer (ink),allocatable::freedom_layer1(:),freedom_layer2(:)
    integer (ink),pointer::ldofs_f(:)

    if(nlayer/=2)return
    allocate(freedom_layer1(ntotv),freedom_layer2(ntotv),freedom_layer(ntotv))
    freedom_layer =0
    freedom_layer1=0
    freedom_layer2=0

    do igroup=1,ngroup

        ilayer  =group(igroup)%ilayer
        index   =group(igroup)%index
        nelgroup=group(igroup)%nelgroup
        nrfields=elkn(index)%nrfields

        do ielgroup=1,nelgroup
            ielem=group(igroup)%list(ielgroup)
            do ifield=1,nrfields   !!ifield
                ldofs_f=>element(ielem)%field(ifield)%ldofs_f
                if(ilayer==1)freedom_layer1(ldofs_f)=1
                if(ilayer==2)freedom_layer2(ldofs_f)=2
                nullify(ldofs_f)
            end do                 !!end ifield
        end do
    end do

    freedom_layer=freedom_layer1+freedom_layer2
    deallocate(freedom_layer1,freedom_layer2)

    end subroutine set_dofs_layer

    !! for semi infinity space
    subroutine estif_semi_space

    character(80) text		  ! middle variable
    integer(ink) ngaus_p,ie,i0,j0,ipoin,jpoin,igaus,inode,nnode_p,pes,kinv,je,  &
        np_space,idofn,jdofn,idimn,i1,i2,in,jn,ix,ix2,ndofn2_space,ndofn0_space
    integer(ink),allocatable::nodx(:),liste_space(:,:)
    real(irk)    ds,dx,dy,fact1,fact2,e_space,nu_space,fact3,t0,e0,nu0
    real(irk),   allocatable::elcod(:,:),   &
        posgp_p(:,:),weigp_p(:), &
        deriv_p(:,:,:),shape_p(:,:), &
        gpcod_p(:,:,:),djacb_p(:,:), stif1_inv_space(:,:), &
        fij(:),fijg(:),global_stif(:,:),unitm(:,:), &
        mmatx(:,:), rr(:,:),rrt(:,:), &
        fij2(:,:,:),fijg2(:,:,:),diagm(:),estif0_space(:,:),estif1_space(:,:),global_stifg(:)
    ! for semi-infinity space
    if(ground_inf==0) return
    !ix=(ground_inf-ground_inf/100*100)/10
    ix=(ground_inf-ground_inf/100*100)/10
    ix2=ground_inf-ground_inf/100*100-(ground_inf-ground_inf/100*100)/10*10


    read(gunit,*)text
    print *,text
    read(gunit,*)ne_space,e_space,nu_space,ngaus_p,t0,pes
    nnode_p=2
    if(ndimn==3)nnode_p=4
    if(ndimn==2.and.pes==2)then
        e0=e_space;nu0=nu_space
        e_space=e0/(1-nu0**2)
        nu_space=nu0/(1-nu0)
    endif


    allocate(liste_space(nnode_p,ne_space))

    allocate(nodx(npoin))
    nodx=0
    do ie=1,ne_space
        read(gunit,*)i0,liste_space(:,ie)
        !read(gunit,*)i0,liste_space(nnode_p:1:-1,ie)


        nodx(liste_space(:,ie))=1
    end do

    np_space=sum(nodx)
    allocate(listp_space(np_space))

    np_space=0
    do ipoin=1,npoin
        if(nodx(ipoin)==1) then
            np_space=np_space+1
            listp_space(np_space)=ipoin
            nodx(ipoin)=np_space
        endif
    end do

    ndofn_space=np_space
    if(ix==2)ndofn_space=np_space*ndimn
    ndofn2_space=ndofn_space  !!
    if(ix==2.and.ix2==1)ndofn2_space=np_space*(2*ndimn-1) !!
    allocate(ldofs_space(ndofn2_space),estif_space(ndofn2_space,ndofn2_space))
    allocate(eload_space(ndofn2_space),estif0_space(ndofn_space,ndofn_space))
    ndofn0_space=0
    do ipoin=1,npoin
        if(nodx(ipoin)/=0) then
            if(ix==1) then
                ndofn0_space=ndofn0_space+1
                ldofs_space(ndofn0_space)=nodfn(ndimn,ipoin)
            elseif(ix==2.and.ix2==2) then
                do idimn=1,ndimn
                    ndofn0_space=ndofn0_space+1
                    ldofs_space(ndofn0_space)=nodfn(idimn,ipoin)
                end do
            elseif(ix==2.and.ix2==1) then
                do idimn=1,2*ndimn-1
                    ndofn0_space=ndofn0_space+1
                    ldofs_space(ndofn0_space)=nodfn(idimn,ipoin)
                end do
            endif  !ground_inf
        endif  !nodx
    end do !ipoin


    if(ndimn==2)then
        fact1=(1+nu_space)/e_space/3.14159
        fact2=(1-nu_space)*.5/e_space
        fact3=2./(3.14159*e_space)
    else
        fact1=(1-nu_space**2)/e_space/3.14159
        fact2=-(1+nu_space)*(1-2*nu_space)/(2.*3.14159*e_space)
        fact3=(1+nu_space)/(3.14159*e_space)
    endif

    allocate(elcod(ndimn-1,nnode_p),posgp_p(2,ngaus_p),weigp_p(ngaus_p), &
        deriv_p(ndimn-1,nnode_p,ngaus_p),shape_p(nnode_p,ngaus_p), &
        gpcod_p(ndimn-1,ngaus_p,ne_space),djacb_p(ngaus_p,ne_space), &
        global_stif(ndofn_space,ndofn_space))

    global_stif=0.
    if(ix==1) then
        allocate(fij(ngaus_p),fijg(nnode_p))
    else if(ix==2) then
        allocate(fij2(ndimn,ndimn,ngaus_p),fijg2(ndimn,ndimn,nnode_p))
    endif

    call getgauss_space(ngaus_p,posgp_p,weigp_p)
    call shfunc_space(ngaus_p,posgp_p,shape_p,deriv_p)

    do ie=1,ne_space
        elcod=coord(1:ndimn-1,liste_space(:,ie))
        call jacob_space(ie,ngaus_p,elcod,deriv_p,djacb_p,gpcod_p,shape_p,nnode_p)
    end do

    do i0=1,np_space

        ipoin=listp_space(i0)


        do ie=1,ne_space

            do igaus=1,ngaus_p
                if(ndimn==3)then
                    ds=(gpcod_p(1,igaus,ie)-coord(1,ipoin))**2+  &
                        (gpcod_p(2,igaus,ie)-coord(2,ipoin))**2
                    ds=sqrt(ds)
                endif
                if(ix==1) then
                    if(ndimn==3)then
                        fij(igaus)=fact1/ds*djacb_p(igaus,ie)*weigp_p(igaus)
                    elseif(ndimn==2)then
                        dx=coord(1,ipoin)-gpcod_p(1,igaus,ie)
                        fij(igaus)=-(log(abs(dx))*fact3+fact1)*djacb_p(igaus,ie)*weigp_p(igaus)
                    endif
                elseif(ix==2) then
                    dx=coord(1,ipoin)-gpcod_p(1,igaus,ie)
                    if(ndimn==3)then
                        dy=coord(2,ipoin)-gpcod_p(2,igaus,ie)
                        fij2(1,3,igaus)=fact2/ds*dx/ds
                        fij2(2,3,igaus)=fact2/ds*dy/ds
                        fij2(3,3,igaus)=fact1/ds

                        fij2(1,1,igaus)=fact3*(1-nu_space+nu_space*(dx/ds)**2)/ds
                        fij2(2,1,igaus)=fact3*nu_space*dx*dy/(ds**3)
                        fij2(3,1,igaus)=-fact2*dx/(ds**2)

                        fij2(2,2,igaus)=fact3*(1-nu_space+nu_space*(dy/ds)**2)/ds
                        fij2(1,2,igaus)=fact3*nu_space*dx*dy/(ds**3)
                        fij2(3,2,igaus)=-fact2*dy/(ds**2)
                    elseif(ndimn==2)then
                        fij2(1,2,igaus)=-fact2*sign(1.,dx)
                        fij2(2,2,igaus)=-(fact3*log(abs(dx))+fact1)
                        fij2(1,1,igaus)=-(fact3*log(abs(dx))-fact1)
                        fij2(2,1,igaus)=fact2*sign(1.,dx)
                    endif

                    fij2(:,:,igaus)=fij2(:,:,igaus)*djacb_p(igaus,ie)*weigp_p(igaus)
                endif
            end do

            if(ix==1) then
                do inode=1,nnode_p
                    fijg(inode)=dot_product(fij,shape_p(inode,:))
                end do
            elseif(ix==2) then
                do inode=1,nnode_p
                    do i1=1,ndimn
                        do i2=1,ndimn
                            fijg2(i1,i2,inode)=dot_product(fij2(i1,i2,:),shape_p(inode,:))
                        end do
                    end do
                end do
            endif

            if(ix==1) then
                do inode=1,nnode_p
                    j0=nodx(liste_space(inode,ie))
                    global_stif(i0,j0)=global_stif(i0,j0)+fijg(inode)
                end do
            elseif(ix==2) then
                do inode=1,nnode_p
                    j0=nodx(liste_space(inode,ie))
                    global_stif((i0-1)*ndimn+1:i0*ndimn,(j0-1)*ndimn+1:j0*ndimn)=  &
                        global_stif((i0-1)*ndimn+1:i0*ndimn,(j0-1)*ndimn+1:j0*ndimn)+fijg2(:,:,inode)
                end do
            endif
        end do  !ie

    end do  !ipoin



    !!!!!!!!!!!!!!!!!!!!!!!!!! 2008/4/13
    allocate(stif_inv_space(ndofn_space,ndofn_space))
    stif_inv_space=0.
    allocate(unitm(ndofn_space,ndofn_space))
    unitm=0.
    stif_inv_space=0.
    do ipoin=1,ndofn_space
        unitm(ipoin,ipoin)=1.
    end do
    call householder(global_stif,unitm,stif_inv_space) !3
    deallocate(unitm)

    !!!!!!!!!!!!!!!!!!!!!!!!!

    allocate(mmatx(nnode_p,nnode_p),global_mmatx(ndofn_space,ndofn_space))

    global_mmatx=0.
    do ie=1,ne_space

        mmatx=0.
        do igaus=1,ngaus_p

            do in=1,nnode_p
                do jn=1,nnode_p
                    mmatx(in,jn)=mmatx(in,jn)+  &
                        shape_p(in,igaus)*shape_p(jn,igaus)*djacb_p(igaus,ie)*weigp_p(igaus)
                end do
            end do
        end do

        if(ix==1) then
            do i0=1,nnode_p
                do j0=1,nnode_p
                    ipoin=nodx(liste_space(i0,ie))
                    jpoin=nodx(liste_space(j0,ie))
                    global_mmatx(ipoin,jpoin)= &
                        global_mmatx(ipoin,jpoin)+mmatx(i0,j0)
                end do
            end do
        else
            do idimn=1,ndimn
                do i0=1,nnode_p
                    do j0=1,nnode_p
                        ipoin=nodx(liste_space(i0,ie))
                        jpoin=nodx(liste_space(j0,ie))
                        idofn=(ipoin-1)*ndimn+idimn
                        jdofn=(jpoin-1)*ndimn+idimn
                        global_mmatx(idofn,jdofn)= &
                            global_mmatx(idofn,jdofn)+mmatx(i0,j0)
                    end do
                end do
            end do
        endif

    end do

    estif0_space=0.
    do idofn=1,ndofn_space
        do jdofn=1,ndofn_space
            estif0_space(idofn,jdofn)=estif0_space(idofn,jdofn)+global_mmatx(idofn,:).d.stif_inv_space(:,jdofn)
        end do
    end do

    !	   estif0_space=matmul(global_mmatx,stif_inv_space)

    if(ix==2.and.ix2==1) then
        allocate(rr(np_space*ndimn,np_space*(2*ndimn-1)),  &
            estif1_space(np_space*ndimn,np_space*(2*ndimn-1)), &
            rrt(np_space*(2*ndimn-1),np_space*ndimn),          &
            stif1_inv_space(np_space*ndimn,np_space*ndimn))

        stif1_inv_space=stif_inv_space
        deallocate(stif_inv_space)
        allocate(stif_inv_space(np_space*ndimn,np_space*(2*ndimn-1)))
        rr=0.
        estif1_space=0.
        estif_space=0.
        do ipoin=1,np_space
            do idimn=1,ndimn
                rr((ipoin-1)*ndimn+idimn,(ipoin-1)*(2*ndimn-1)+idimn)=1.
            end do
            if(ndimn==2)then
                rr((ipoin-1)*ndimn+1,(ipoin-1)*(2*ndimn-1)+(2*ndimn-1))= .5*t0   !200200208
            elseif(ndimn==3) then
                rr((ipoin-1)*ndimn+1,(ipoin-1)*(2*ndimn-1)+(2*ndimn-1))= -.5*t0  !200200208
                rr((ipoin-1)*ndimn+2,(ipoin-1)*(2*ndimn-1)+(2*ndimn-2))=  .5*t0  !200200208
            endif
        end do

        estif1_space=0.
        do idofn=1,np_space*ndimn
            do jdofn=1,np_space*(2*ndimn-1)
                estif1_space(idofn,jdofn)=estif1_space(idofn,jdofn)+estif0_space(idofn,:).d.rr(:,jdofn)
            end do
        end do
        !	   estif1_space=estif0_space.x.rr
        stif_inv_space=0.
        do idofn=1,np_space*ndimn
            do jdofn=1,np_space*(2*ndimn-1)
                stif_inv_space(idofn,jdofn)=stif_inv_space(idofn,jdofn)+stif1_inv_space(idofn,:).d.rr(:,jdofn)
            end do
        end do

        !	   stif_inv_space=stif1_inv_space.x.rr
        rrt=transpose(rr)
        estif_space=0.
        do idofn=1,np_space*(2*ndimn-1)
            do jdofn=1,np_space*(2*ndimn-1)
                estif_space(idofn,jdofn)=estif_space(idofn,jdofn)+rrt(idofn,:).d.estif1_space(:,jdofn)
            end do
        end do
        !	   estif_space=rrt.x.estif1_space
        deallocate(rr,estif1_space,rrt,stif1_inv_space)
        ndofn_space=ndofn2_space

    else
        estif_space=estif0_space
    endif


    deallocate(nodx,mmatx, &
        elcod,posgp_p,weigp_p,deriv_p,shape_p, &
        gpcod_p,djacb_p,global_stif,liste_space,estif0_space)

    end   subroutine estif_semi_space
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !! for semi infinity space
    subroutine estif_semi_space_center  !consider lateral side load effection 2008/6/21

    character(80) text		  ! middle variable
    character(8) char_time
    integer(ink) ngaus_p,ie,i0,j0,je,ipoin,igaus,inode,ifcg,  &
        np_space,idofn,idimn,n1,n2,ix1,ix2,jdofn,gdofn,nnode_p,pes,nel
    integer(ink),allocatable::nodx(:),liste_space(:,:)
    real(irk)    ds,x0,y0,fact1,e_space,nu_space,aera,con,fact2,dx,dy,fact3,t0,e0,nu0, &
        a1,a2,x01,c,fki,s0,c0,fkj
    real(irk),   allocatable::elcod(:,:),bbar(:,:),shapwxy(:,:),   &
        posgp_p(:,:),weigp_p(:), &
        deriv_p(:,:,:),shape_p(:,:), &
        gpcod_p(:,:,:),djacb_p(:,:), global_stifg(:), &
        global_stif(:,:),unitm(:,:),transg(:,:),dershap(:,:,:),   &
        ploadl(:,:),cordl(:,:)
    ! for semi-infinity space
    if(ground_inf==0) return
    ix1=(ground_inf-ground_inf/100*100)/10
    ix2=ground_inf-ground_inf/100*100-(ground_inf-ground_inf/100*100)/10*10
    read(gunit,*)text
    print *,text
    read(gunit,*)ne_space,e_space,nu_space,ngaus_p,t0,pes,ifcg,nel  !080621 add nel
    print *,'ne_space=',ne_space
    nnode_p=2
    if(ndimn==3)nnode_p=4
    if(ndimn==2.and.pes==2)then
        e0=e_space;nu0=nu_space
        e_space=e0/(1-nu0**2)
        nu_space=nu0/(1-nu0)
    endif


    allocate(liste_space(nnode_p,ne_space))

    allocate(nodx(npoin))
    nodx=0
    do ie=1,ne_space
        if(ix2==2) then
            read(gunit,*)i0,liste_space(nnode_p:1:-1,ie) !the information are obtained from psgid
        elseif(ix2==1)then
            read(gunit,*)i0,liste_space(:,ie)
        endif
        nodx(liste_space(:,ie))=1
    end do

    if(nel/=0)then  !080621
        allocate(cordl(ndimn-1,nel))
        if(ix1==1.and.ix2==2)then
            allocate(ploadl(1,nel))
        else
            allocate(ploadl(ndimn,nel))
        endif
        do ie=1,nel
            read(gunit,*)i0,cordl(:,ie),ploadl(:,ie)
        end do
    endif


    np_space=sum(nodx)
    allocate(listp_space(np_space))

    np_space=0
    do ipoin=1,npoin
        if(nodx(ipoin)==1) then
            np_space=np_space+1
            listp_space(np_space)=ipoin
            nodx(ipoin)=np_space
        endif
    end do

    ndofn_space=np_space*ndimn   !07
    if(ndimn==3.and.ix1==2.and.ix2==1)ndofn_space=np_space*5
    if(ndimn==2.and.ix1==2.and.ix2==1)ndofn_space=np_space*3
    if(ix1==1.and.ix2==2)ndofn_space=np_space
    gdofn=ne_space
    if(ix1==2)gdofn=ne_space*ndimn

    allocate(ldofs_space(ndofn_space),estif_space(ndofn_space,ndofn_space))
    allocate(eload_space(ndofn_space),dis0_space(gdofn),load0_space(gdofn),load_space(ndofn_space))
    dis0_space=0.;load_space=0.;load0_space=0.

    n1=ndimn
    n2=2*ndimn-1
    if(ix1==2.and.ix2==1)then
        n1=1
        n2=2*ndimn-1
    elseif(ix1==1.and.ix2==2)then
        n1=ndimn
        n2=ndimn
    elseif(ix1==2.and.ix2==2)then
        n1=1
        n2=ndimn
    endif

    ndofn_space=0
    do ipoin=1,npoin
        if(nodx(ipoin)/=0) then
            do idimn=n1,n2   !3,5
                ndofn_space=ndofn_space+1
                ldofs_space(ndofn_space)=nodfn(idimn,ipoin)
            end do
        endif  !nodx
    end do !ipoin





    if(ndimn==2)then
        fact1=(1+nu_space)/e_space/3.14159
        fact2=(1-nu_space)*.5/e_space
        fact3=2./(3.14159*e_space)
        allocate(elcod(1,2),posgp_p(1,ngaus_p),weigp_p(ngaus_p), &
            deriv_p(1,2,ngaus_p),shape_p(2,ngaus_p), &
            gpcod_p(1,ngaus_p,ne_space),djacb_p(ngaus_p,ne_space))
    elseif(ndimn==3)then
        fact1=(1-nu_space**2)/e_space/3.14159
        fact2=-(1+nu_space)*(1-2*nu_space)/(2.*3.14159*e_space)
        fact3=(1+nu_space)/(3.14159*e_space)
        allocate(elcod(2,4),posgp_p(2,ngaus_p),weigp_p(ngaus_p), &
            deriv_p(2,4,ngaus_p),shape_p(4,ngaus_p), &
            gpcod_p(2,ngaus_p,ne_space),djacb_p(ngaus_p,ne_space))

    endif

    allocate(global_stif(gdofn,gdofn))
    global_stif=0.

    call getgauss_space(ngaus_p,posgp_p,weigp_p)
    call shfunc_space(ngaus_p,posgp_p,shape_p,deriv_p)

    do ie=1,ne_space
        elcod=coord(1:ndimn-1,liste_space(:,ie))
        call jacob_space(ie,ngaus_p,elcod,deriv_p,djacb_p,gpcod_p,shape_p,nnode_p)
    end do
    if(ix1==1)then
        if(ndimn==3)then
            do ie=1,ne_space
                x0=sum(coord(1,liste_space(1:4,ie)))
                y0=sum(coord(2,liste_space(1:4,ie)))
                !		  write(7,*)'ie=',ie,'x0=',x0,'y0=',y0
                do je=1,ne_space
                    aera=dot_product(djacb_p(:,je),weigp_p(:))
                    !	   write(7,*)'je=',je,'aera=',aera
                    do igaus=1,ngaus_p
                        ds=(gpcod_p(1,igaus,je)-x0*.25)**2+  &
                            (gpcod_p(2,igaus,je)-y0*.25)**2
                        ds=sqrt(ds)
                        global_stif(ie,je)=global_stif(ie,je)+  &
                            fact1*djacb_p(igaus,je)/ds*weigp_p(igaus)/aera
                    end do  !igaus
                end do  !je

                do je=1,nel
                    ds=(cordl(1,je)-x0*.25)**2+  &
                        (cordl(2,je)-y0*.25)**2
                    ds=sqrt(ds)
                    dis0_space(ie)=dis0_space(ie)+fact1/ds*ploadl(1,je)
                end do
            end do  !ie
        elseif(ndimn==2)then
            if(ifcg==1)then
                do ie=1,ne_space
                    x0=sum(coord(1,liste_space(1:2,ie)))
                    x0=x0*.5
                    do je=1,ne_space
                        c0=abs(coord(1,liste_space(1,ie))-coord(1,liste_space(2,ie)))
                        if(ie/=je)then
                            x01=sum(coord(1,liste_space(1:2,je)))
                            x01=x01*.5
                            dx=x0-x01
                            a1=(2.*(dx/c0)+1)/(2.*(dx/c0)-1)
                            a2=4*(dx/c0)**2-1
                            fki=-2.*dx/c0*log(a1)-log(a2)
                        else
                            fki=0.
                        endif
                        global_stif(ie,je)=global_stif(ie,je)+fki/3.14159/e_space
                    end do  !je
                end do  !ie
            elseif(ifcg==2)then


                do ie=1,ne_space
                    x0=sum(coord(1,liste_space(1:2,ie)))
                    do je=1,ne_space
                        aera=dot_product(djacb_p(:,je),weigp_p(:))
                        do igaus=1,ngaus_p
                            dx=x0*.5-gpcod_p(1,igaus,je)
                            global_stif(ie,je)=global_stif(ie,je)-  &
                                (log(abs(dx))*fact3+fact1)*djacb_p(igaus,je)*weigp_p(igaus)/aera
                        end do  !igaus
                    end do  !je

                    do je=1,nel  !080621
                        dx=x0*.5-cordl(1,je)
                        dis0_space(ie)=dis0_space(ie)-(log(abs(dx))*fact3+fact1)*ploadl(1,je)
                    end do  !je


                end do  !ie

            endif
        endif
    else if(ix1==2)then




        if(ndimn==3)then
            do ie=1,ne_space
                x0=sum(coord(1,liste_space(1:4,ie)))
                y0=sum(coord(2,liste_space(1:4,ie)))
                do je=1,ne_space
                    aera=dot_product(djacb_p(:,je),weigp_p(:))
                    do igaus=1,ngaus_p
                        ds=(gpcod_p(1,igaus,je)-x0*.25)**2+  &
                            (gpcod_p(2,igaus,je)-y0*.25)**2
                        ds=sqrt(ds)
                        dx=x0*.25-gpcod_p(1,igaus,je)
                        dy=y0*.25-gpcod_p(2,igaus,je)
                        idofn=(ie-1)*3
                        jdofn=(je-1)*3
                        con=djacb_p(igaus,je)*weigp_p(igaus)/aera

                        global_stif(idofn+1,jdofn+3)=global_stif(idofn+1,jdofn+3)+fact2/ds*dx/ds*con
                        global_stif(idofn+2,jdofn+3)=global_stif(idofn+2,jdofn+3)+fact2/ds*dy/ds*con
                        global_stif(idofn+3,jdofn+3)=global_stif(idofn+3,jdofn+3)+fact1/ds*con
                        global_stif(idofn+1,jdofn+1)=global_stif(idofn+1,jdofn+1)+fact3/ds*(1-nu_space+nu_space*(dx/ds)**2)*con
                        global_stif(idofn+2,jdofn+1)=global_stif(idofn+2,jdofn+1)+fact3*nu_space*dx*dy/(ds**3)*con
                        global_stif(idofn+3,jdofn+1)=global_stif(idofn+3,jdofn+1)-fact2*dx/(ds**2)*con
                        global_stif(idofn+2,jdofn+2)=global_stif(idofn+2,jdofn+2)+fact3/ds*(1-nu_space+nu_space*(dy/ds)**2)*con
                        global_stif(idofn+1,jdofn+2)=global_stif(idofn+1,jdofn+2)+fact3*nu_space*dx*dy/(ds**3)*con
                        global_stif(idofn+3,jdofn+2)=global_stif(idofn+3,jdofn+2)-fact2*dy/(ds**2)*con

                    end do  !igaus
                end do  !je


                do je=1,nel   !080621
                    ds=(cordl(1,je)-x0*.25)**2+(cordl(2,je)-y0*.25)**2
                    ds=sqrt(ds)
                    dx=x0*.25-cordl(1,je)
                    dy=y0*.25-cordl(2,je)
                    idofn=(ie-1)*3
                    dis0_space(idofn+1)=dis0_space(idofn+1)+fact2/ds*dx/ds*ploadl(3,je)
                    dis0_space(idofn+2)=dis0_space(idofn+2)+fact2/ds*dy/ds*ploadl(3,je)
                    dis0_space(idofn+3)=dis0_space(idofn+3)+fact1/ds*ploadl(3,je)
                    dis0_space(idofn+1)=dis0_space(idofn+1)+fact3/ds*(1-nu_space+nu_space*(dx/ds)**2)*ploadl(1,je)
                    dis0_space(idofn+2)=dis0_space(idofn+2)+fact3*nu_space*dx*dy/(ds**3)*ploadl(1,je)
                    dis0_space(idofn+3)=dis0_space(idofn+3)-fact2*dx/(ds**2)*ploadl(1,je)
                    dis0_space(idofn+2)=dis0_space(idofn+2)+fact3/ds*(1-nu_space+nu_space*(dy/ds)**2)*ploadl(2,je)
                    dis0_space(idofn+1)=dis0_space(idofn+1)+fact3*nu_space*dx*dy/(ds**3)*ploadl(2,je)
                    dis0_space(idofn+3)=dis0_space(idofn+3)-fact2*dy/(ds**2)*ploadl(2,je)
                end do  !je  !080621


            end do  !ie
        else if(ndimn==2)then
            if(ifcg==1)then
                do ie=1,ne_space
                    x0=sum(coord(1,liste_space(1:2,ie)))
                    x0=x0*.5
                    do je=1,ne_space
                        idofn=(ie-1)*2
                        jdofn=(je-1)*2
                        c0=abs(coord(1,liste_space(1,ie))-coord(1,liste_space(2,ie)))
                        x01=sum(coord(1,liste_space(1:2,je)))
                        x01=x01*.5
                        dx=x0-x01
                        a1=(2.*(dx/c0)+1)/(2.*(dx/c0)-1)
                        a2=4*(dx/c0)**2-1
                        fki=0.
                        fkj=0.
                        if(ie/=je) then
                            fki=-2.*dx/c0*log(a1)-log(a2)
                            fkj=fact2
                        endif

                        global_stif(idofn+1,jdofn+2)=global_stif(idofn+1,jdofn+2)-fkj*sign(1.,dx)
                        global_stif(idofn+2,jdofn+2)=global_stif(idofn+2,jdofn+2)+fki/3.14159/e_space
                        global_stif(idofn+1,jdofn+1)=global_stif(idofn+1,jdofn+1)+fki/3.14159/e_space
                        global_stif(idofn+2,jdofn+1)=global_stif(idofn+2,jdofn+1)+fkj*sign(1.,dx)


                    end do  !je
                end do  !ie
            elseif(ifcg==2)then

                do ie=1,ne_space
                    x0=sum(coord(1,liste_space(1:2,ie)))
                    do je=1,ne_space
                        aera=dot_product(djacb_p(:,je),weigp_p(:))
                        do igaus=1,ngaus_p
                            dx=x0*.5-gpcod_p(1,igaus,je)
                            idofn=(ie-1)*2
                            jdofn=(je-1)*2
                            con=djacb_p(igaus,je)*weigp_p(igaus)/aera

                            global_stif(idofn+1,jdofn+2)=global_stif(idofn+1,jdofn+2)-fact2*sign(1.,dx)*con
                            global_stif(idofn+2,jdofn+2)=global_stif(idofn+2,jdofn+2)-(fact3*log(abs(dx))+fact1)*con
                            global_stif(idofn+1,jdofn+1)=global_stif(idofn+1,jdofn+1)-(fact3*log(abs(dx))-fact1)*con
                            global_stif(idofn+2,jdofn+1)=global_stif(idofn+2,jdofn+1)+fact2*sign(1.,dx)*con

                        end do  !igaus
                    end do  !je


                    do je=1,nel    !080621
                        dx=x0*.5-cordl(1,je)
                        idofn=(ie-1)*2
                        dis0_space(idofn+1)=dis0_space(idofn+1)-fact2*sign(1.,dx)*ploadl(2,je)
                        dis0_space(idofn+2)=dis0_space(idofn+2)-(fact3*log(abs(dx))+fact1)*ploadl(2,je)
                        dis0_space(idofn+1)=dis0_space(idofn+1)-(fact3*log(abs(dx))-fact1)*ploadl(1,je)
                        dis0_space(idofn+2)=dis0_space(idofn+2)+fact2*sign(1.,dx)*ploadl(1,je)
                    end do  !je   !080621


                end do  !ie
            endif
        endif
    endif

    call TIME(char_time)
    write(chkunit,*)'time_invg0: ', char_time
    allocate(stif_inv_space(gdofn,gdofn))

    allocate(unitm(gdofn,gdofn))
    unitm=0.
    stif_inv_space=0.
    !	   write(7,*)'global_stif='
    do ipoin=1,gdofn
        unitm(ipoin,ipoin)=1.
        !	   write(7,10)global_stif(ipoin,:)
    end do
    call householder(global_stif,unitm,stif_inv_space) !3
    !	   do ipoin=1,gdofn
    !	   write(7,*)'ipoin=',ipoin,'stif_inv_space=',stif_inv_space(ipoin,ipoin)
    !	   end do
    deallocate(unitm)


    if(nel/=0)  &
        load0_space=stif_inv_space.x.dis0_space   !080621
10  format(1x,20e15.3)
    call TIME(char_time)
    write(chkunit,*)'time_invg0: ', char_time
    allocate(global_mmatx(gdofn,ndofn_space))
    global_mmatx=0.

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    do ie=1,ne_space
        elcod=coord(1:2,liste_space(:,ie))
        if(ix1==1.and.ix2==1.and.ndimn==3)then
            allocate(bbar(3,12),shapwxy(3,4),dershap(2,4,3))
            call der_shap_puxiaoming(0._irk,0._irk,elcod,bbar,shapwxy,0,dershap)
            do i0=1,4
                ipoin=liste_space(i0,ie)
                idofn=(nodx(ipoin)-1)*3
                global_mmatx(ie,idofn+1)=global_mmatx(ie,idofn+1)+shapwxy(1,i0)
                global_mmatx(ie,idofn+2)=global_mmatx(ie,idofn+2)+shapwxy(2,i0)
                global_mmatx(ie,idofn+3)=global_mmatx(ie,idofn+3)+shapwxy(3,i0)
            end do
            deallocate(bbar,shapwxy,dershap)
        elseif(ix1==1.and.ix2==2)then
            allocate(bbar(ndimn-1,nnode_p),shapwxy(1,nnode_p))
            if(ndimn==3)then
                call shfunc( ndimn-1,nnode_p,0._irk,0._irk,0._irk,shapwxy(1,:),bbar)
            else
                call shfunc( ndimn-1,nnode_p,0.5_irk,0.5_irk,0.5_irk,shapwxy(1,:),bbar)
            endif
            do i0=1,nnode_p
                ipoin=liste_space(i0,ie)
                idofn=(nodx(ipoin)-1)
                global_mmatx(ie,idofn+1)=global_mmatx(ie,idofn+1)+shapwxy(1,i0)
            end do
            deallocate(bbar,shapwxy)
        elseif(ix1==2.and.ix2==2)then

            allocate(bbar(ndimn-1,nnode_p),shapwxy(1,nnode_p))
            if(ndimn==3)then
                call shfunc( ndimn-1,nnode_p,0._irk,0._irk,0._irk,shapwxy(1,:),bbar)
            else
                call shfunc( ndimn-1,nnode_p,0.5_irk,0.5_irk,0.5_irk,shapwxy(1,:),bbar)
            endif
            do i0=1,nnode_p
                ipoin=liste_space(i0,ie)
                idofn=(nodx(ipoin)-1)*ndimn
                do idimn=1,ndimn
                    global_mmatx((ie-1)*ndimn+idimn,idofn+idimn)=global_mmatx((ie-1)*ndimn+idimn,idofn+idimn)+shapwxy(1,i0)
                end do
            end do
            deallocate(bbar,shapwxy)
        elseif(ix1==2.and.ix2==1)then
            if(ndimn==3)then
                allocate(bbar(3,12),shapwxy(3,4),dershap(2,4,3))
                call der_shap_puxiaoming(0._irk,0._irk,elcod,bbar,shapwxy,1,dershap)
                do i0=1,4
                    ipoin=liste_space(i0,ie)
                    idofn=(nodx(ipoin)-1)*5
                    global_mmatx(ie*3,idofn+3)=global_mmatx(ie*3,idofn+3)+shapwxy(1,i0)
                    global_mmatx(ie*3,idofn+4)=global_mmatx(ie*3,idofn+4)+shapwxy(2,i0)
                    global_mmatx(ie*3,idofn+5)=global_mmatx(ie*3,idofn+5)+shapwxy(3,i0)
                end do
                deallocate(bbar,shapwxy)
                allocate(bbar(2,4),shapwxy(1,4))
                if(ndimn==3)then
                    call shfunc( ndimn-1,nnode_p,0._irk,0._irk,0._irk,shapwxy(1,:),bbar)
                else
                    call shfunc( ndimn-1,nnode_p,0.5_irk,0.5_irk,0.5_irk,shapwxy(1,:),bbar)
                endif
                do i0=1,4
                    ipoin=liste_space(i0,ie)
                    idofn=(nodx(ipoin)-1)*5
                    do idimn=1,2
                        global_mmatx((ie-1)*3+idimn,idofn+idimn)=global_mmatx((ie-1)*3+idimn,idofn+idimn)+shapwxy(1,i0)
                    end do

                    global_mmatx((ie-1)*3+1,idofn+3)=global_mmatx((ie-1)*3+1,idofn+3)-t0*.5*dershap(1,i0,1)
                    global_mmatx((ie-1)*3+1,idofn+4)=global_mmatx((ie-1)*3+1,idofn+4)-t0*.5*dershap(1,i0,2)
                    global_mmatx((ie-1)*3+1,idofn+5)=global_mmatx((ie-1)*3+1,idofn+5)-t0*.5*dershap(1,i0,3)
                    global_mmatx((ie-1)*3+2,idofn+3)=global_mmatx((ie-1)*3+2,idofn+3)-t0*.5*dershap(2,i0,1)
                    global_mmatx((ie-1)*3+2,idofn+4)=global_mmatx((ie-1)*3+2,idofn+4)-t0*.5*dershap(2,i0,2)
                    global_mmatx((ie-1)*3+2,idofn+5)=global_mmatx((ie-1)*3+2,idofn+5)-t0*.5*dershap(2,i0,3)

                end do
                deallocate(bbar,shapwxy,dershap)
            else if(ndimn==2)then
                do i0=1,2
                    ipoin=liste_space(i0,ie)
                    idofn=(nodx(ipoin)-1)*3
                    do idimn=1,2
                        global_mmatx((ie-1)*2+idimn,idofn+idimn)=global_mmatx((ie-1)*2+idimn,idofn+idimn)+0.5
                    end do
                end do
                do i0=1,2
                    ipoin=liste_space(i0,ie)
                    idofn=(nodx(ipoin)-1)*3
                    global_mmatx((ie-1)*2+1,idofn+3)=global_mmatx((ie-1)*2+1,idofn+3)-t0*.5*.5
                end do

            endif

        endif
    end do
    !*******


    allocate(reaction_space(gdofn,ndofn_space),transg(ndofn_space,gdofn))
    reaction_space=0.
    do idofn=1,gdofn
        do jdofn=1,ndofn_space
            reaction_space(idofn,jdofn)=reaction_space(idofn,jdofn)+stif_inv_space(idofn,:).d.global_mmatx(:,jdofn)
        end do
    end do

    !	   reaction_space=stif_inv_space.x.global_mmatx
    transg=transpose(global_mmatx)
    estif_space=0.
    do idofn=1,ndofn_space
        do jdofn=1,ndofn_space
            estif_space(idofn,jdofn)=estif_space(idofn,jdofn)+transg(idofn,:).d.reaction_space(:,jdofn)
        end do
    end do
    !	   estif_space=transg.x.reaction_space
    if(nel/=0)  &
        load_space=transg.x.load0_space    !080621


    !	   write(7,*)'estif_space'
    !	   do i0=1,ndofn_space
    !	   write(7,*)i0
    !	   write(7,*)estif_space(i0,:)
    !	   end do

    deallocate(nodx,stif_inv_space, &
        elcod,posgp_p,weigp_p,deriv_p,shape_p, &
        gpcod_p,djacb_p,global_stif,liste_space,transg)
    if(nel/=0)then
        deallocate(cordl,ploadl)
    endif

    end   subroutine estif_semi_space_center
    !!
    !!
    subroutine getgauss_space(ngaus,posgp,weigp)
    integer(ink) ngaus,igaus,i,j,k
    real(irk)   posgp(:,:),weigp(:)
    real(irk) G,cnst3, w(4),g1,g2,w6(6),li6(6),w10(10),li10(10),w8(8),li8(8),  &
        w12(12),w16(16),w20(20),w24(24),li12(12),li16(16),li20(20),li24(24)
    integer(ink) Lj16(16), LI9(9), LK16(16), LK9(9)
    DATA LK9/-1,-1,-1,0,0,0,1,1,1/, LI9/-1,0,1,-1,0,1,-1,0,1/
    DATA LK16/8*-1,8*1/, Lj16/-1,-1,1,1,-1,-1,1,1,-1,-1,1,1,-1,-1,1,1/

    if  ( ngaus.eq.4 ) then
        cnst3     = 1./3.**0.5
        posgp(1,1)= -cnst3
        posgp(2,1)= -cnst3
        posgp(1,2)=  cnst3
        posgp(2,2)= -cnst3
        posgp(1,3)=  cnst3
        posgp(2,3)=  cnst3
        posgp(1,4)= -cnst3
        posgp(2,4)=  cnst3
        weigp=1.00
    else if(ngaus==9) then
        G=0.7745966692414830
        DO  I=1,9
            POSGP(1,I)=G*LK9(I)
            POSGP(2,I)=G*LI9(I)
        end do
        W(1)=0.555555555555556D0
        W(2)=0.888888888888889D0
        W(3)=W(1)
        K=0
        DO  I=1,3
            DO  J=1,3
                K=K+1
                WEIGP(K)=W(I)*W(J)
            end do
        end do
    else if(ngaus==16) then
        G1=0.8611363115940530
        G2=0.3399810435848560
        DO  I=1,16
            if (I<=4.OR.I>=13) THEN
                POSGP(1,I)=G1*LK16(I)
            ELSE
                POSGP(1,I)=G2*LK16(I)
            ENDIF
            if (I.EQ.1.OR.I.EQ.4.OR.I.EQ.5.OR.I.EQ.8.OR.I.EQ.9.OR.I.EQ.12   &
                .OR.I.EQ.13.OR.I.EQ.16) THEN
                POSGP(2,I)=G1*Lj16(I)
            ELSE
                POSGP(2,I)=G2*Lj16(I)
            ENDIF
        end do
        W(1)=0.3478548451374540
        W(2)=0.6521451548625460
        W(3)=W(2)
        W(4)=W(1)
        K=0
        DO  I=1,4
            DO  J=1,4
                K=K+1
                WEIGP(K)=W(I)*W(J)
            end do
        end do
    else if(ngaus==36) then
        li6(1)=-.932469514203152
        li6(2)=-.661209386466265
        li6(3)=-.238619186083197
        li6(4)=.932469514203152
        li6(5)=.661209386466265
        li6(6)=.238619186083197
        w6(1)=.171324492379170
        w6(2)=.360761573048139
        w6(3)=.467913934572691
        w6(4)=.171324492379170
        w6(5)=.360761573048139
        w6(6)=.467913934572691
        k=0
        do i=1,6
            do j=1,6
                k=k+1
                posgp(1,k)=li6(i)
                posgp(2,k)=li6(j)
                weigp(k)=w6(i)*w6(j)
            end do
        end do
    else if(ngaus==64) then
        li8(1)=-.9602898565
        li8(2)=-.7966664774
        li8(3)=-.5255324099
        li8(4)=-.1834346425
        li8(8)=.9602898565
        li8(7)=.7966664774
        li8(6)=.5255324099
        li8(5)=.1834346425
        w8(1)=.1012285363
        w8(2)=.2223810345
        w8(3)=.3137066459
        w8(4)=.3626837834
        w8(8)=.1012285363
        w8(7)=.2223810345
        w8(6)=.3137066459
        w8(5)=.3626837834
        k=0
        do i=1,8
            do j=1,8
                k=k+1
                posgp(1,k)=li8(i)
                posgp(2,k)=li8(j)
                weigp(k)=w8(i)*w8(j)
            end do
        end do
    else if(ngaus==100) then
        li10(1)=-.1488743390
        li10(2)=-.4338953941
        li10(3)=-.6794095683
        li10(4)=-.8650633667
        li10(5)=-.9739065285
        li10(6)=.1488743390
        li10(7)=.4338953941
        li10(8)=.6794095683
        li10(9)=.8650633667
        li10(10)=.9739065285
        w10(1)=.2955242247
        w10(2)=.2692667193
        w10(3)=.2190863625
        w10(4)=.1494513492
        w10(5)=.0666713443
        w10(6)=.2955242247
        w10(7)=.2692667193
        w10(8)=.2190863625
        w10(9)=.1494513492
        w10(10)=.0666713443
        k=0
        do i=1,10
            do j=1,10
                k=k+1
                posgp(1,k)=li10(i)
                posgp(2,k)=li10(j)
                weigp(k)=w10(i)*w10(j)
            end do
        end do
        !
    else if(ngaus==144) then
        li12(1 )=-.12523340851146891547
        li12(2 )=-.36783149899818019375
        li12(3 )=-.58731795428661744730
        li12(4 )=-.76990267419430468704
        li12(5 )=-.90411725637047485668
        li12(6 )=-.98156063424671925069
        li12(7 )= .12523340851146891547
        li12(8 )= .36783149899818019375
        li12(9 )= .58731795428661744730
        li12(10)= .76990267419430468704
        li12(11)= .90411725637047485668
        li12(12)= .98156063424671925069
        w12(1 )=.24914704581340278500
        w12(2 )=.23349253653835480876
        w12(3 )=.20316742672306592175
        w12(4 )=.16007832854334622633
        w12(5 )=.10693932599531843096
        w12(6 )=.04717533638651182719
        w12(7 )=.24914704581340278500
        w12(8 )=.23349253653835480876
        w12(9 )=.20316742672306592175
        w12(10)=.16007832854334622633
        w12(11)=.10693932599531843096
        w12(12)=.04717533638651182719
        k=0
        do i=1,12
            do j=1,12
                k=k+1
                posgp(1,k)=li12(i)
                posgp(2,k)=li12(j)
                weigp(k)=w12(i)*w12(j)
            end do
        end do
        !****
        !
    else if(ngaus==256) then
        li16(1 )=-.09501250983763744019
        li16(2 )=-.28160355077925891323
        li16(3 )=-.45801677765722738634
        li16(4 )=-.61787624440264374845
        li16(5 )=-.75540440835500303390
        li16(6 )=-.86563120238783174388
        li16(7 )=-.94457502307323257608
        li16(8 )=-.98940093499164993260
        li16(9 )=.09501250983763744019
        li16(10)=.28160355077925891323
        li16(11)=.45801677765722738634
        li16(12)=.61787624440264374845
        li16(13)=.75540440835500303390
        li16(14)=.86563120238783174388
        li16(15)=.94457502307323257608
        li16(16)=.98940093499164993260
        w16(1 )=.18945061045506849629
        w16(2 )=.18260341504492358887
        w16(3 )=.16915651939500253819
        w16(4 )=.14959598881657673208
        w16(5 )=.12462897125553387205
        w16(6 )=.09515851168249278481
        w16(7 )=.06225352393864789286
        w16(8 )=.02715245941175409485
        w16(9 )=.18945061045506849629
        w16(10)=.18260341504492358887
        w16(11)=.16915651939500253819
        w16(12)=.14959598881657673208
        w16(13)=.12462897125553387205
        w16(14)=.09515851168249278481
        w16(15)=.06225352393864789286
        w16(16)=.02715245941175409485
        k=0
        do i=1,16
            do j=1,16
                k=k+1
                posgp(1,k)=li16(i)
                posgp(2,k)=li16(j)
                weigp(k)=w16(i)*w16(j)
            end do
        end do
        !****

    else if(ngaus==400) then
        li20(1 )=-.07652652113349733375
        li20(2 )=-.22778585114164507808
        li20(3 )=-.37370608871541956067
        li20(4 )=-.51086700195082709800
        li20(5 )=-.63605368072651502545
        li20(6 )=-.74633190646015079261
        li20(7 )=-.83911697182221882339
        li20(8 )=-.91223442825132590587
        li20(9 )=-.96397192727791379127
        li20(10)=-.99312859918509492479
        li20(11)=.07652652113349733375
        li20(12)=.22778585114164507808
        li20(13)=.37370608871541956067
        li20(14)=.51086700195082709800
        li20(15)=.63605368072651502545
        li20(16)=.74633190646015079261
        li20(17)=.83911697182221882339
        li20(18)=.91223442825132590587
        li20(19)=.96397192727791379127
        li20(20)=.99312859918509492479
        w20(1 )=.15275338713072585070
        w20(2 )=.14917298647260374679
        w20(3 )=.14209610931838205133
        w20(4 )=.13168863844917662690
        w20(5 )=.11819453196151841731
        w20(6 )=.10193011981724043504
        w20(7 )=.08327674157670474872
        w20(8 )=.06267204833410906357
        w20(9 )=.04060142980038694133
        w20(10)=.01761400713915211831
        w20(11)=.15275338713072585070
        w20(12)=.14917298647260374679
        w20(13)=.14209610931838205133
        w20(14)=.13168863844917662690
        w20(15)=.11819453196151841731
        w20(16)=.10193011981724043504
        w20(17)=.08327674157670474872
        w20(18)=.06267204833410906357
        w20(19)=.04060142980038694133
        w20(20)=.01761400713915211831
        k=0
        do i=1,20
            do j=1,20
                k=k+1
                posgp(1,k)=li20(i)
                posgp(2,k)=li20(j)
                weigp(k)=w20(i)*w20(j)
            end do
        end do
        !****

    else if(ngaus==576) then
        li24(1 )=-.06405689286260562609
        li24(2 )=-.19111886747361630916
        li24(3 )=-.31504267969616337439
        li24(4 )=-.43379350762604513849
        li24(5 )=-.54542147138883953566
        li24(6 )=-.64809365193697556925
        li24(7 )=-.74012419157855436424
        li24(8 )=-.82000198597390292195
        li24(9 )=-.88641552700440103421
        li24(10)=-.93827455200273275852
        li24(11)=-.97472855597130949820
        li24(12)=-.99518721999702136018
        li24(13)=.06405689286260562609
        li24(14)=.19111886747361630916
        li24(15)=.31504267969616337439
        li24(16)=.43379350762604513849
        li24(17)=.54542147138883953566
        li24(18)=.64809365193697556925
        li24(19)=.74012419157855436424
        li24(20)=.82000198597390292195
        li24(21)=.88641552700440103421
        li24(22)=.93827455200273275852
        li24(23)=.97472855597130949820
        li24(24)=.99518721999702136018
        w24(1 )=.12793819534675215697
        w24(2 )=.12583745634682829612
        w24(3 )=.12167047292780339120
        w24(4 )=.11550566805372560135
        w24(5 )=.10744427011596563478
        w24(6 )=.09761865210411388827
        w24(7 )=.08619016153195327592
        w24(8 )=.07334648141108030573
        w24(9 )=.05929858491543678075
        w24(10)=.04427743881741980617
        w24(11)=.02853138862893366318
        w24(12)=.01234122979998719955
        w24(13)=.12793819534675215697
        w24(14)=.12583745634682829612
        w24(15)=.12167047292780339120
        w24(16)=.11550566805372560135
        w24(17)=.10744427011596563478
        w24(18)=.09761865210411388827
        w24(19)=.08619016153195327592
        w24(20)=.07334648141108030573
        w24(21)=.05929858491543678075
        w24(22)=.04427743881741980617
        w24(23)=.02853138862893366318
        w24(24)=.01234122979998719955
        k=0
        do i=1,24
            do j=1,24
                k=k+1
                posgp(1,k)=li24(i)
                posgp(2,k)=li24(j)
                weigp(k)=w24(i)*w24(j)
            end do
        end do
        !****
    endif

    end subroutine getgauss_space


    subroutine shfunc_space(ngaus,posgp,shape,deriv)

    !      ------  Obtain shape functions at sampling point (x,y,z) and
    !              its derivatives

    !-------------------------------------------------------------------
    integer(ink) ngaus,igaus
    real(irk) s,t,st
    real(irk),dimension(:,:):: shape,posgp
    real(irk),dimension(:,:,:):: deriv


    do igaus=1,ngaus
        s=posgp(1,igaus)
        t=posgp(2,igaus)
        st=s*t

        shape(1,igaus) = (1-t-s+st)*0.25
        shape(2,igaus) = (1-t+s-st)*0.25
        shape(3,igaus) = (1+t+s+st)*0.25
        shape(4,igaus) = (1+t-s-st)*0.25
        deriv(1,1,igaus) = (-1+t)*0.25
        deriv(1,2,igaus) = (+1-t)*0.25
        deriv(1,3,igaus) = (+1+t)*0.25
        deriv(1,4,igaus) = (-1-t)*0.25
        deriv(2,1,igaus) = (-1+s)*0.25
        deriv(2,2,igaus) = (-1-s)*0.25
        deriv(2,3,igaus) = (+1+s)*0.25
        deriv(2,4,igaus) = (+1-s)*0.25
    end do


    end subroutine shfunc_space

    subroutine jacob_space (ie,ngaus,elcod,deriv,djacb,gpcod,shape,nnode_p)

    integer(ink)  idimn,jdimn,inode,ie,ngaus,igaus,nnode_p
    real(irk)     djacb(:,:),gpcod(:,:,:),shape(:,:)
    real(irk)     deriv(:,:,:), elcod(:,:),xjacm(2,2)

    do igaus=1,ngaus

        do idimn=1,ndimn-1
            gpcod(idimn,igaus,ie)=dot_product(shape(:,igaus),elcod(idimn,:))
        end do
        DO idimn=1,ndimn-1
            DO jdimn=1,ndimn-1
                xjacm(idimn,jdimn)=0.0
                DO inode=1,nnode_p
                    xjacm(idimn,jdimn)=xjacm(idimn,jdimn)+        &
                        deriv(idimn,inode,igaus)*elcod(jdimn,inode)
                enddo
            enddo
        enddo

        !      ------  Get determinant and inverse
        if(ndimn==2)then
            djacb(igaus,ie)=xjacm(1,1)
        else
            djacb(igaus,ie)=xjacm(1,1)*xjacm(2,2)-xjacm(1,2)*xjacm(2,1)
        endif
    end do


    end subroutine jacob_space


    !! end for semi infinity space

    !! for point to point contacts
    subroutine contact_point_to_point  !ctt2005

    character(80) text       ! middle variable
    integer(ink) igaps,igapb,igroup,jgroup,ielgroup,ielem,index,matno,inode,nnode,ipoin,npairs,nnodei,nnodej, &
        npgblock,ntotv_bt,idimn,ij,ipairs,i0,ipgblock,onetwo,totonetwo,itotv,nrdof,ij1,ij2, &
        npblock,ipblock,jpoin,njcp,method_gapi,ngroupt,i,pairnode1,pairnode2,npbotom,nptop,j0,kdimn,igapbf,iptop,ipbotom
    integer(ink) igapf,kpoin,jpoin0,kkdimn !20211214
    real(irk)    elcod_local,xx,lambda,e,miu,g,rr,e00
    integer(ink),allocatable::ictp(:),jctp(:),icetemp(:),ntotv_btx(:),listbotom(:), &
        listtop(:),ntpoin(:)
    integer(ink),pointer::lnods(:),xlwmd(:)
    real(irk),   allocatable::aera(:),rot(:,:,:),frict(:),cohes(:),ft(:),Gf(:),center1(:),center2(:),disbotom(:),  &
        distop(:),ictp_aera(:),jctp_aera(:)

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_contact_point_to_point_title_1,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)ngaps,ngapb,contactpe,miter_bt,tor_bt,iblks_bt,nonsbt,xlwsol,method_gapi,miter_state,type_solver_ctt,restart_ctt,damp_ctt,istatec  !tcl1124
    call diag_check_read(yl_ios,yl_msg,RD_GLB_contact_point_to_point_contact_control,0)
    print *,'ngaps=',ngaps

    if (ngaps==0) return

    allocate(block_appear_process(ngapb,nblks))   !20200331
    read(gunit,*)text   !20200331
    read(gunit,*)(block_appear_process(:,iblks),iblks=1,nblks)  !20200331

    allocate(gaps(ngaps),gapb(ngapb))
    read(gunit,*)text

    do igaps=1,ngaps
        read(gunit,*)text
        !print *,'igaps=',igaps,text
        allocate(gaps(igaps)%xlwmd(ndimn))
        read(gunit,*)ngroupt,gaps(igaps)%xlwmd,gaps(igaps)%frict_less,gaps(igaps)%goodman,gaps(igaps)%thin_layer
        !if(relis/=0)then
        !read(gunit,*)gaps(igaps)%ivcoh,gaps(igaps)%ivfri
        !endif

        gaps(igaps)%ngroupt=ngroupt

        allocate(gaps(igaps)%listgroupt(ngroupt),gaps(igaps)%ft0(ngroupt),gaps(igaps)%frict0(ngroupt),gaps(igaps)%cohes0(ngroupt))

        if(block_stab==1) then
            allocate( gaps(igaps)%kgroup0(3*(ndimn-1),3*(ndimn-1)),gaps(igaps)%kgroup1(3*(ndimn-1),3*(ndimn-1)))
        else
            allocate( gaps(igaps)%kgroup0(ndimn,ndimn),gaps(igaps)%kgroup1(ndimn,ndimn))
        endif


        gaps(igaps)%kgroup0=0.
        gaps(igaps)%kgroup1=0.
        read(gunit,*)gaps(igaps)%listgroupt
        !print *,'igaps=',igaps,'gaps(igaps)%listgroupt=',gaps(igaps)%listgroupt
        read(gunit,*)gaps(igaps)%gapi,gaps(igaps)%stateix
        read(gunit,*)gaps(igaps)%ft0
        read(gunit,*)gaps(igaps)%frict0
        read(gunit,*)gaps(igaps)%cohes0

        print *,'igaps=',igaps,'cohes0=',gaps(igaps)%cohes0,'kstab=',kstab
        !if(nforce_gaps>0) &   !2017/02/14
        !print *,'nforce_gaps_appear(igaps)=',nforce_gaps_appear(igaps)

        gaps(igaps)%ft0=gaps(igaps)%ft0
        gaps(igaps)%cohes0=gaps(igaps)%cohes0
        if(nforce_gaps>0)then     !2017/02/14
            if(nforce_gaps_appear(igaps)==1.or.nforce_gaps_appear(igaps)==3)then
                gaps(igaps)%frict0=gaps(igaps)%frict0/kstab
                gaps(igaps)%cohes0=gaps(igaps)%cohes0/kstab
            endif
        endif

        if(block_stab==1) then
            read(gunit,*)i0,(gaps(igaps)%kgroup0(i,i),i=1,3*(ndimn-1)),(gaps(igaps)%kgroup1(i,i),i=1,3*(ndimn-1))
            !write(7,*)'igaps=',igaps,'kgroup0=',(gaps(igaps)%kgroup0(i,i),i=1,3*(ndimn-1)),'kgroup0=',(gaps(igaps)%kgroup1(i,i),i=1,3*(ndimn-1))
        else
            read(gunit,*)i0,(gaps(igaps)%kgroup0(i,i),i=1,ndimn),(gaps(igaps)%kgroup1(i,i),i=1,ndimn)
        endif
        print *, 'gaps(igaps)%kgroup0=',gaps(igaps)%kgroup0
        print *, 'gaps(igaps)%kgroup1=',gaps(igaps)%kgroup1

        if (gaps(igaps)%xlwmd(ndimn)>0)then
            allocate(gaps(igaps)%Gf0(gaps(igaps)%ngroupt))  !2017/04/03
            if (gaps(igaps)%xlwmd(ndimn)==5)then      !2017/04/03
                allocate(gaps(igaps)%ft1(gaps(igaps)%ngroupt),gaps(igaps)%wt0(gaps(igaps)%ngroupt),gaps(igaps)%wt1(gaps(igaps)%ngroupt), &
                    gaps(igaps)%wt2(gaps(igaps)%ngroupt))
            endif
            read(gunit,*)gaps(igaps)%Gf0     !2017/04/03
            if (gaps(igaps)%xlwmd(ndimn)==5)then     !2017/04/03
                read(gunit,*)gaps(igaps)%ft1,gaps(igaps)%wt0,gaps(igaps)%wt1,gaps(igaps)%wt2   !2017/04/03
            endif
        endif
        if (gaps(igaps)%goodman>0)then
            allocate(gaps(igaps)%kgdm(ndimn))
            read(gunit,*)gaps(igaps)%kgdm(:),gaps(igaps)%Rf,gaps(igaps)%Pa,gaps(igaps)%gamaw,gaps(igaps)%n
            do idimn=1,ndimn
                gaps(igaps)%kgroup0(idimn,idimn)=1./( gaps(igaps)%kgdm(idimn)*gamaw)      !gaps(igaps)%gamaw)  20230402
                !write(7,*)'igaps=',igaps,'kgroup0=', gaps(igaps)%kgroup0(idimn,idimn)
            end do
            if(block_stab==1)then
                do idimn=ndimn+1,3*(ndimn-1)
                    gaps(igaps)%kgroup0(idimn,idimn)=gaps(igaps)%kgroup0(ndimn,ndimn)
                enddo
            end if
        endif
        !     if (gaps(igaps)%thin_layer==1)then
        !      read(gunit,*)gaps(igaps)%e,gaps(igaps)%miu,gaps(igaps)%thick
        !      e=gaps(igaps)%e
        !      miu=gaps(igaps)%miu
        !        lambda=e*miu/((1+miu)*(1-2*miu))	!拉梅常数
        !     g=e/(2*(1+miu))						!剪切模量
        !      gaps(igaps)%kgroup0(ndimn,ndimn)=1./(lambda+2*g)/gaps(igaps)%thick
        !gaps(igaps)%kgroup0(1,1)=1./g/gaps(igaps)%thick
        !      if(ndimn==3)gaps(igaps)%kgroup0(2,2)=1./g/gaps(igaps)%thick
        !      !write(7,*)'igaps=',igaps,'kgroup0=', gaps(igaps)%kgroup0(1,1), gaps(igaps)%kgroup0(2,2), gaps(igaps)%kgroup0(3,3)
        !       endif

        if(gaps(igaps)%thin_layer>0)  then  ! add by HEJINWEN  !2017/02/14
            read(gunit,*)gaps(igaps)%Ke, gaps(igaps)%e,gaps(igaps)%miu,gaps(igaps)%RF   !2017/02/14
            gaps(igaps)%kgroup0=0.0
            gaps(igaps)%kgroup1=0.
            e00=gaps(igaps)%e*gaps(igaps)%Ke
            if(ndimn.eq.2)  then
                gaps(igaps)%kgroup0(ndimn,ndimn)=1./e00
                gaps(igaps)%kgroup0(1,1)=1./(e00/2.0/(1+gaps(igaps)%miu))
                !write(*,*) igaps,gaps(igaps)%kgroup0(1,1), gaps(igaps)%kgroup0(ndimn,ndimn)
            else if (ndimn.eq.3)  then
                gaps(igaps)%kgroup0(ndimn,ndimn)=1./e00
                gaps(igaps)%kgroup0(1,1)=1./(e00/2.0/(1+gaps(igaps)%miu))
                gaps(igaps)%kgroup0(2,2)=1./(e00/2.0/(1+gaps(igaps)%miu))
                !write(7,*) 'igaps=',igaps,'kxxyz0=',gaps(igaps)%kgroup0(1,1), gaps(igaps)%kgroup0(2,2),gaps(igaps)%kgroup0(ndimn,ndimn)
            end if
        end if         !2017/02/14


        print *,'end igroup'
    end do

    print *,'after input gaps information'
    read(gunit,*)text
    print *,text

    do igapb=1,ngapb
        read(gunit,*)text
        print *,'igapb=',igapb,text
        read(gunit,*)gapb(igapb)%ngroupt,gapb(igapb)%ngroupb,gapb(igapb)%nrdof,gapb(igapb)%eblock !2017/11/19

        nrdof=gapb(igapb)%nrdof
        if(nrdof/=0)then
            allocate(gapb(igapb)%center(ndimn),gapb(igapb)%ext_force(3*(ndimn-1)))  !20231019
            gapb(igapb)%ext_force=0. !20231019
            if(type_problem=='F')allocate(gapb(igapb)%mass_inertia(3*(ndimn-1)))
            allocate(gapb(igapb)%listrdof(gapb(igapb)%nrdof)) !fzx 约束点的三个（二维）、六个（三维）自由度的整体自由度号
            read(gunit,*)gapb(igapb)%listrdof
        endif


        allocate(gapb(igapb)%listgroupt(gapb(igapb)%ngroupt),gapb(igapb)%listgroupb(gapb(igapb)%ngroupb))
        if(block_stab==2)allocate(gapb(igapb)%pairspoint12(gapb(igapb)%ngroupt)) !20191031
        read(gunit,*)gapb(igapb)%listgroupt
        if(block_stab==2)read(gunit,*)gapb(igapb)%pairspoint12 !20191031
        read(gunit,*)gapb(igapb)%listgroupb

        print *,'igapb=',igapb,'listgroupb=',gapb(igapb)%listgroupb


    end do
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !考虑极限平衡

    if(block_stab==1)then
        print *,'block_stab=',block_stab
        allocate(center1(ndimn),center2(ndimn),ictp(npoin),jctp(npoin),ictp_aera(npoin),jctp_aera(npoin))
        !ictp_aera=0.;jctp_aera=0.  !20211201

        ntotv0=ntotv
        do igaps=1,ngaps
            npairs=0
            do igroup=1,gaps(igaps)%ngroupt !11
                jgroup=gaps(igaps)%listgroupt(igroup)
                if (jgroup<=0)cycle
                npairs=npairs+1
            end do  !11
            gaps(igaps)%npairs=npairs
            allocate(gaps(igaps)%pairnode(2,npairs),     gaps(igaps)%aera(npairs),          &
                gaps(igaps)%gap(3*(ndimn-1),npairs),      gaps(igaps)%ctforce(3*(ndimn-1),npairs), &
                gaps(igaps)%state(npairs),          gaps(igaps)%state0(npairs),        &
                gaps(igaps)%rot(ndimn,ndimn,npairs),gaps(igaps)%ft(npairs),            &
                gaps(igaps)%alfa1(npairs),          gaps(igaps)%ctforce0(3*(ndimn-1),npairs),&
                gaps(igaps)%ctforcei(3*(ndimn-1),npairs), gaps(igaps)%gap0(3*(ndimn-1),npairs),        &
                gaps(igaps)%ctforcej(3*(ndimn-1),npairs),                              &
                gaps(igaps)%frict(npairs),          gaps(igaps)%cohes(npairs),         &
                gaps(igaps)%kxyz(3*(ndimn-1),3*(ndimn-1),npairs),gaps(igaps)%kxyz0(3*(ndimn-1),3*(ndimn-1),npairs),     gaps(igaps)%dxyz(3*(ndimn-1),npairs),    &
                gaps(igaps)%dxyz0(3*(ndimn-1),npairs),    gaps(igaps)%dxyzi(3*(ndimn-1),npairs),gaps(igaps)%pair_process(npairs))
            gaps(igaps)%pair_process=1  !20200331
            if(miter_state>1)allocate(gaps(igaps)%statei(npairs)) !20161115

            if(kinit==2)allocate(gaps(igaps)%ctforce_stres0(3*(ndimn-1),npairs))  !2019/03/19
            if(kinit==2)gaps(igaps)%ctforce_stres0=0.  !2019/03/19

            gaps(igaps)%aera=0.;gaps(igaps)%gap=0.; gaps(igaps)%ctforce=0.
            gaps(igaps)%ctforce0=0.;gaps(igaps)%ctforcei=0.;gaps(igaps)%ctforcej=0.

            gaps(igaps)%frict=0.;gaps(igaps)%cohes=0.;gaps(igaps)%dxyz0=0.;gaps(igaps)%dxyzi=0.
            gaps(igaps)%ft=0.;gaps(igaps)%alfa1=0.;gaps(igaps)%alfa2=0.;gaps(igaps)%rot=0.;gaps(igaps)%kxyz=0.;gaps(igaps)%kxyz0=0.;gaps(igaps)%dxyz=0.
            if (ndimn==3)allocate(gaps(igaps)%alfa2(npairs))
            if (ndimn==3)gaps(igaps)%alfa2=0.
            !if(ebody==1)allocate(gaps(igaps)%gaps_collect(npairs))
            allocate(gaps(igaps)%gaps_collect(npairs)) !20161115


            npairs=0
            do igroup=1,gaps(igaps)%ngroupt   !22
                jgroup=gaps(igaps)%listgroupt(igroup)
                if (jgroup<=0)cycle
                npairs=npairs+1
                index = group(jgroup)%index
                nnode = elkn(index)%el_field(1)%nnode_f
                center1=0.;center2=0.
                ictp=0;jctp=0
                ictp_aera=0.;jctp_aera=0.  !20211201
                do ielgroup=1,group(jgroup)%nelgroup
                    ielem = group(jgroup)%list(ielgroup)
                    lnods =>element(ielem)%field(1)%lnods_f
                    write(7,*)'ie=',ielem,'aera_local=',element(ielem)%aera_local
                    do inode=1,nnode/2
                        ictp(lnods(inode))=1
                        jctp(lnods(inode+nnode/2))=1
                        center1=center1+coord(:,lnods(inode))*element(ielem)%aera_local(inode)
                        ictp_aera(lnods(inode))=ictp_aera(lnods(inode))+element(ielem)%aera_local(inode)
                        jctp_aera(lnods(inode+nnode/2))=ictp_aera(lnods(inode+nnode/2))+element(ielem)%aera_local(inode)
                        if(ndimn==2)then
                            if(inode==1) &
                                center2=center2+coord(:,lnods(4))*element(ielem)%aera_local(inode)
                            if(inode==2) &
                                center2=center2+coord(:,lnods(3))*element(ielem)%aera_local(inode)
                        elseif(ndimn==3)then
                            center2=center2+coord(:,lnods(inode+nnode/2))*element(ielem)%aera_local(inode)
                        endif

                        gaps(igaps)%aera(npairs)=gaps(igaps)%aera(npairs)+element(ielem)%aera_local(inode)
                        gaps(igaps)%rot(:,:,npairs)=gaps(igaps)%rot(:,:,npairs)+element(ielem)%rotation(:,:)*element(ielem)%aera_local(inode)
                        gaps(igaps)%ft(npairs)=gaps(igaps)%ft(npairs)+gaps(igaps)%ft0(igroup)*element(ielem)%aera_local(inode)
                        gaps(igaps)%frict(npairs)=gaps(igaps)%frict(npairs)+gaps(igaps)%frict0(igroup)*element(ielem)%aera_local(inode)
                        gaps(igaps)%cohes(npairs)=gaps(igaps)%cohes(npairs)+gaps(igaps)%cohes0(igroup)*element(ielem)%aera_local(inode)
                    end do
                    nullify(lnods)
                end do


                !write(7,*)'igaps_0=',igaps,'center1=',center1,'center2=',center2,'gaps(igaps)%aera(npairs)=',gaps(igaps)%aera(npairs)
                center1=center1/gaps(igaps)%aera(npairs)
                center2=center2/gaps(igaps)%aera(npairs)
                write(7,*)'igaps=',igaps,'jgroup=',jgroup,'center1=',center1,'center2=',center2

                gaps(igaps)%rot(:,:,npairs)=gaps(igaps)%rot(:,:,npairs)/gaps(igaps)%aera(npairs)
                write(7,*)'rot=',gaps(igaps)%rot(:,:,npairs)
                gaps(igaps)%ft(npairs)=gaps(igaps)%ft(npairs)/gaps(igaps)%aera(npairs)
                gaps(igaps)%frict(npairs)=gaps(igaps)%frict(npairs)/gaps(igaps)%aera(npairs)
                gaps(igaps)%cohes(npairs)=gaps(igaps)%cohes(npairs)/gaps(igaps)%aera(npairs)


                gaps(igaps)%ctforce=0.;gaps(igaps)%ctforce0=0.;gaps(igaps)%dxyz=0. ; gaps(igaps)%dxyz0=0.  !2011
                gaps(igaps)%ctforcei=0.;gaps(igaps)%ctforcej=0.;gaps(igaps)%dxyzi=0.

                gaps(igaps)%gap(ndimn,npairs)=gaps(igaps)%gapi
                gaps(igaps)%gap0(ndimn,npairs)=gaps(igaps)%gapi

                gaps(igaps)%state0(npairs)=gaps(igaps)%stateix
                gaps(igaps)%state (npairs)=gaps(igaps)%stateix

                npbotom=sum(ictp)
                nptop=sum(jctp)
                gaps(igaps)%gaps_collect(npairs)%npbotom=npbotom
                gaps(igaps)%gaps_collect(npairs)%nptop=nptop
                allocate(disbotom(npbotom),listbotom(npbotom),distop(nptop),listtop(nptop))

                if(ebody==1) &         !2015/11/17
                    allocate(gaps(igaps)%gaps_collect(npairs)%listbotom(npbotom),gaps(igaps)%gaps_collect(npairs)%listtop(nptop),   &
                    gaps(igaps)%gaps_collect(npairs)%listbotom_aera(npbotom),gaps(igaps)%gaps_collect(npairs)%listtop_aera(nptop) )

                disbotom=0.;distop=0.
                npbotom=0
                do ipoin=1,npoin
                    if(ictp(ipoin)==0)cycle
                    npbotom=npbotom+1
                    listbotom(npbotom)=ipoin
                    if(ebody==1)then         !2015/11/17
                        gaps(igaps)%gaps_collect(npairs)%listbotom(npbotom)=ipoin
                        gaps(igaps)%gaps_collect(npairs)%listbotom_aera(npbotom)=ictp_aera(ipoin)
                    endif

                    disbotom(npbotom)=sum((coord(:,ipoin)-center1)**2)
                end do
                !write(7,*)'npbotom=',npbotom  !,'disbotom=',disbotom
                i0=minloc(disbotom,dim=1)
                pairnode1=listbotom(i0)
                !write(7,*)'i0=',i0,'pairnode1=',pairnode1

                nptop=0
                do ipoin=1,npoin
                    if(jctp(ipoin)==0)cycle
                    nptop=nptop+1
                    listtop(nptop)=ipoin
                    if(ebody==1) then         !2015/11/17
                        gaps(igaps)%gaps_collect(npairs)%listtop(nptop)=ipoin
                        gaps(igaps)%gaps_collect(npairs)%listtop_aera(nptop)=jctp_aera(ipoin)
                    endif
                    distop(nptop)=sum((coord(:,ipoin)-coord(:,pairnode1))**2)
                end do
                !write(7,*)'nptop=',nptop  !,'distop=',distop
                j0=minloc(distop,dim=1)

                pairnode2=listtop(j0)
                !write(7,*)'j0=',j0,'pairnode2=',pairnode2
                !write(7,*)'coord10=',coord(:, pairnode1)
                !write(7,*)'coord20=',coord(:, pairnode2)

                coord(:, pairnode1)=center1
                coord(:, pairnode2)=center2
                !write(7,*)'coord11=',coord(:, pairnode1)
                !write(7,*)'coord21=',coord(:, pairnode2)
                gaps(igaps)%pairnode(1,npairs)=pairnode1
                gaps(igaps)%pairnode(2,npairs)=pairnode2
                deallocate(disbotom,listbotom,distop,listtop)
                !write(7,*)'npairs=',npairs,'pairnode1=',pairnode1,'pairnode2=',pairnode2
                if(ndimn==2)then
                    if(nodfn(3,pairnode1)==0)then
                        ntotv=ntotv+1
                        nodfn(3,pairnode1)=ntotv
                    endif
                    if(nodfn(3,pairnode2)==0)then
                        ntotv=ntotv+1
                        nodfn(3,pairnode2)=ntotv
                    endif
                elseif(ndimn==3)then
                    do idimn=4,6
                        if(nodfn(idimn,pairnode1)==0)then
                            ntotv=ntotv+1
                            nodfn(idimn,pairnode1)=ntotv
                        endif
                    end do
                    do idimn=4,6
                        if(nodfn(idimn,pairnode2)==0)then
                            ntotv=ntotv+1
                            nodfn(idimn,pairnode2)=ntotv
                        endif
                    end do
                end if


            end do !22

        end do !igaps

        rewind(cunit)
        if(ndimn==2)then
            do ipoin=1,npoin
                write(cunit,55)ipoin,coord(:,ipoin),0.
            end do
        elseif(ndimn==3)then
            do ipoin=1,npoin
                write(cunit,55)ipoin,coord(:,ipoin)
            end do
        endif
55      format(i10,3f15.5)

        deallocate(center1,center2,ictp,jctp,ictp_aera,jctp_aera)


        allocate(trans0(ntotv0))
        do itotv=1,ntotv0
            nintf=trans(itotv)%nintf !20210726
            trans0(itotv)%nintf=nintf
            if(nintf/=0)then
                allocate(trans0(itotv)%listf(nintf),trans0(itotv)%rintf(nintf))
                trans0(itotv)%listf=trans(itotv)%listf
                trans0(itotv)%rintf=trans(itotv)%rintf
                deallocate(trans(itotv)%listf,trans(itotv)%rintf)
            endif
        end do
        deallocate(trans)
        allocate(trans(ntotv))
        do itotv=1,ntotv0
            nintf=trans0(itotv)%nintf  !20210726
            trans(itotv)%nintf=nintf
            if(nintf/=0)then
                allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                trans(itotv)%listf=trans0(itotv)%listf
                trans(itotv)%rintf=trans0(itotv)%rintf
                deallocate(trans0(itotv)%listf,trans0(itotv)%rintf)
            endif
        end do
        do itotv=ntotv0+1,ntotv
            trans(itotv)%nintf=0
        end do
        deallocate(trans0)



        if(ebody==1) then   !2015/11/17
            allocate(ntpoin(npoin))

            ntpoin=0
            do igaps=1,ngaps
                do ipairs=1,gaps(igaps)%npairs
                    npbotom=gaps(igaps)%gaps_collect(ipairs)%npbotom
                    nptop  =gaps(igaps)%gaps_collect(ipairs)%nptop
                    do iptop=1,nptop
                        ipoin=gaps(igaps)%gaps_collect(ipairs)%listtop(iptop)
                        ntpoin(ipoin)= ntpoin(ipoin)+1
                        !write(7,*)'ipointop=',ipoin,'ntpon=',ntpoin(ipoin)
                    end do
                    do ipbotom=1,npbotom
                        ipoin=gaps(igaps)%gaps_collect(ipairs)%listbotom(ipbotom)
                        ntpoin(ipoin)= ntpoin(ipoin)+1
                        !write(7,*)'ipoinbotom=',ipoin,'ntpon=',ntpoin(ipoin)
                    end do
                end do
            end do

            write(7,*)'ntpoin=ipoin,ntpoin(ipoin)'
            do ipoin=1,npoin
                if(ntpoin(ipoin)==0)cycle
                write(7,*)ipoin,ntpoin(ipoin)
                do idimn=1,ndimn
                    itotv=nodfn(idimn,ipoin)
                    nintf=ntpoin(ipoin)*3*(ndimn-1)
                    !trans(itotv)%nintf=nintf
                    allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                end do
            end do


            do igaps=1,ngaps
                do ipairs=1,gaps(igaps)%npairs
                    npbotom=gaps(igaps)%gaps_collect(ipairs)%npbotom
                    nptop  =gaps(igaps)%gaps_collect(ipairs)%nptop
                    pairnode1=gaps(igaps)%pairnode(1,ipairs)
                    pairnode2=gaps(igaps)%pairnode(2,ipairs)
                    call beam_section_dis_int(igaps,ipairs,pairnode2,nptop,1,ntpoin)  !2015/11/17
                    call beam_section_dis_int(igaps,ipairs,pairnode1,npbotom,2,ntpoin)  !2015/11/17
                end do
            end do
            deallocate(ntpoin)
        endif
        print *,'end block_state'
        goto 40
    endif


    !!!!!!!!!!!!!!!!!!!!!!!!!! 以节点对作为接触点对
    if(contactpe==2) go to 10

    mpairs=0 !zhao 05/09/06ctr
    do igaps=1,ngaps

        xlwmd=>gaps(igaps)%xlwmd
        allocate(ictp(npoin))
        ictp=0
        do igroup=1,gaps(igaps)%ngroupt
            jgroup=gaps(igaps)%listgroupt(igroup)
            if (jgroup>=0)cycle
            index = group(-jgroup)%index
            nnode = elkn(index)%el_field(1)%nnode_f
            do ielgroup=1,group(-jgroup)%nelgroup
                ielem = group(-jgroup)%list(ielgroup)
                lnods =>element(ielem)%field(1)%lnods_f
                ictp(lnods)=1
                nullify(lnods)
            end do
        end do

        !write(7,*)'igaps=',igaps !'ictp(243,269)=',ictp(243),ictp(269)
        npairs=0

        allocate(gapnode(npoin))  !2010/10
        gapnode(:)%njcp=0


        do igroup=1,gaps(igaps)%ngroupt
            jgroup=gaps(igaps)%listgroupt(igroup)
            if (jgroup<=0)cycle
            index = group(jgroup)%index
            nnode = elkn(index)%el_field(1)%nnode_f
            do ielgroup=1,group(jgroup)%nelgroup
                elcod_local=group(jgroup)%elcod_local
                ielem = group(jgroup)%list(ielgroup)
                lnods =>element(ielem)%field(1)%lnods_f
                do inode=1,nnode/2
                    ipoin=lnods(inode)
                    jpoin=0
                    if (ndimn==3)then
                        jpoin=lnods(inode+nnode/2)
                    else if(ndimn==2)then
                        if (inode==1.and.lnods(1)/=lnods(4))jpoin=lnods(4)
                        if (inode==2.and.lnods(2)/=lnods(3))jpoin=lnods(3)
                    endif
                    if(jpoin==0) cycle
                    if(ictp(ipoin)==1.or.ictp(jpoin)==1)cycle
                    if(ipoin/=jpoin)then
                        njcp=gapnode(ipoin)%njcp
                        do i0=1,njcp
                            if(jpoin==gapnode(ipoin)%jcplist(i0))then

                                gapnode(ipoin)%aera(i0)=gapnode(ipoin)%aera(i0)+element(ielem)%aera_local(inode)
                                gapnode(ipoin)%rot(:,:,i0)=gapnode(ipoin)%rot(:,:,i0)+element(ielem)%rotation(:,:)*element(ielem)%aera_local(inode)
                                gapnode(ipoin)%ft(i0)=gapnode(ipoin)%ft(i0)+gaps(igaps)%ft0(igroup)*element(ielem)%aera_local(inode)
                                gapnode(ipoin)%frict(i0)=gapnode(ipoin)%frict(i0)+gaps(igaps)%frict0(igroup)*element(ielem)%aera_local(inode)
                                gapnode(ipoin)%cohes(i0)=gapnode(ipoin)%cohes(i0)+gaps(igaps)%cohes0(igroup)*element(ielem)%aera_local(inode)
                                if (xlwmd(ndimn)>0)   &
                                    gapnode(ipoin)%Gf(i0)=gapnode(ipoin)%Gf(i0)+gaps(igaps)%Gf0(igroup)*element(ielem)%aera_local(inode) !2007
                                goto 101
                            endif
                        end do

                        njcp=njcp+1
                        gapnode(ipoin)%njcp=njcp
                        call nodegapchange(njcp,ipoin,xlwmd)
                        gapnode(ipoin)%jcplist(njcp)=jpoin

                        !print *,'ipoin=',ipoin,'inode=',inode,'ielem=',ielem,'jpoin=',jpoin
                        gapnode(ipoin)%aera(njcp)=gapnode(ipoin)%aera(njcp)+element(ielem)%aera_local(inode)
                        gapnode(ipoin)%rot(:,:,njcp)=gapnode(ipoin)%rot(:,:,njcp)+element(ielem)%rotation(:,:)*element(ielem)%aera_local(inode)
                        gapnode(ipoin)%ft(njcp)=gapnode(ipoin)%ft(njcp)+gaps(igaps)%ft0(igroup)*element(ielem)%aera_local(inode)
                        gapnode(ipoin)%frict(njcp)=gapnode(ipoin)%frict(njcp)+gaps(igaps)%frict0(igroup)*element(ielem)%aera_local(inode)
                        gapnode(ipoin)%cohes(njcp)=gapnode(ipoin)%cohes(njcp)+gaps(igaps)%cohes0(igroup)*element(ielem)%aera_local(inode)
                        if (xlwmd(ndimn)>0)   &
                            gapnode(ipoin)%Gf(njcp)=gapnode(ipoin)%Gf(njcp)+gaps(igaps)%Gf0(igroup)*element(ielem)%aera_local(inode) !2007
101                     continue
                    endif
                end do
                nullify(lnods)
            end do
        end do


        !	write(7,*)'gapnode(243,269)%njcp=',gapnode(243)%njcp,gapnode(269)%njcp
        do ipoin=1,npoin
            if (gapnode(ipoin)%njcp/=0)npairs=npairs+gapnode(ipoin)%njcp
        end do
        gaps(igaps)%npairs=npairs
        if (npairs>mpairs)mpairs=npairs !zhao 05/09/06
        allocate(gaps(igaps)%pairnode(2,npairs),     gaps(igaps)%aera(npairs),          &
            gaps(igaps)%gap(ndimn,npairs),      gaps(igaps)%ctforce(ndimn,npairs), &
            gaps(igaps)%state(npairs),          gaps(igaps)%state0(npairs),        &
            gaps(igaps)%rot(ndimn,ndimn,npairs),gaps(igaps)%ft(npairs),            &
            gaps(igaps)%alfa1(npairs),          gaps(igaps)%ctforce0(ndimn,npairs),&
            gaps(igaps)%ctforcei(ndimn,npairs), gaps(igaps)%gap0(ndimn,npairs),          &
            gaps(igaps)%ctforcej(ndimn,npairs),                                    &
            gaps(igaps)%frict(npairs),          gaps(igaps)%cohes(npairs),         &
            gaps(igaps)%kxyz(ndimn,ndimn,npairs),gaps(igaps)%kxyz0(ndimn,ndimn,npairs), &
            gaps(igaps)%dxyz(ndimn,npairs),   gaps(igaps)%dxyz0(ndimn,npairs),   &
            gaps(igaps)%dxyzi(ndimn,npairs), gaps(igaps)%wsc(npairs), &
            gaps(igaps)%sigmad(npairs),gaps(igaps)%xd(npairs),gaps(igaps)%pair_process(npairs),   &
            gaps(igaps)%damage0(npairs),gaps(igaps)%damage(npairs))        !20210131
        gaps(igaps)%pair_process=1  !20200331
        if(miter_state>1)allocate(gaps(igaps)%statei(npairs))

        allocate(gaps(igaps)%group(npairs))  !2017/04/03

        if(kinit==2)allocate(gaps(igaps)%ctforce_stres0(ndimn,npairs))  !2019/03/19
        if(kinit==2)gaps(igaps)%ctforce_stres0=0.  !2019/03/19


        if (ndimn==3)allocate(gaps(igaps)%alfa2(npairs))
        if (xlwmd(ndimn)>0)allocate(gaps(igaps)%Gf(npairs))

        gaps(igaps)%ctforce=0.;gaps(igaps)%ctforce0=0.;gaps(igaps)%dxyz=0. ; gaps(igaps)%dxyz0=0.  !2011
        gaps(igaps)%gap=0.;    gaps(igaps)%gap0=0.; gaps(igaps)%wsc=0.;gaps(igaps)%sigmad=0.;gaps(igaps)%xd=0.
        gaps(igaps)%ctforcei=0.;gaps(igaps)%dxyzi=0.;gaps(igaps)%kxyz=0.;gaps(igaps)%kxyz0=0.
        gaps(igaps)%ctforcej=0.;gaps(igaps)%damage0=0.;gaps(igaps)%damage=0.  !20210131

        npairs=0
        do ipoin=1,npoin
            if (gapnode(ipoin)%njcp/=0)then
                do i0=1,gapnode(ipoin)%njcp
                    npairs=npairs+1
                    gaps(igaps)%pairnode(1,npairs)=ipoin
                    gaps(igaps)%pairnode(2,npairs)=gapnode(ipoin)%jcplist(i0)
                    !write(7,*)npairs,gaps(igaps)%pairnode(1:2,npairs)
                    gaps(igaps)%gap(ndimn,npairs)=gaps(igaps)%gapi
                    gaps(igaps)%gap0(ndimn,npairs)=gaps(igaps)%gapi
                    gaps(igaps)%aera(npairs)=gapnode(ipoin)%aera(i0)
                    gaps(igaps)%state0(npairs)=gaps(igaps)%stateix
                    gaps(igaps)%state (npairs)=gaps(igaps)%stateix

                    gaps(igaps)%rot(:,:,npairs)=gapnode(ipoin)%rot(:,:,i0)/gapnode(ipoin)%aera(i0)
                    gaps(igaps)%ft(npairs) =gapnode(ipoin)%ft(i0)/gapnode(ipoin)%aera(i0) !2007      !2007
                    gaps(igaps)%cohes(npairs) =gapnode(ipoin)%cohes(i0)/gapnode(ipoin)%aera(i0) !2007
                    gaps(igaps)%frict(npairs) =gapnode(ipoin)%frict(i0)/gapnode(ipoin)%aera(i0) !2007


                    !			 write(7,*)'igaps=',igaps,'ipairs=',npairs,'ipoin=',ipoin,'rot=',gaps(igaps)%rot(:,:,npairs)
                    if (xlwmd(ndimn)>0)gaps(igaps)%Gf(npairs) =gapnode(ipoin)%Gf(i0)/gapnode(ipoin)%aera(i0)      !2007
                    do idimn=1,ndimn
                        xx=sqrt(sum(gaps(igaps)%rot(idimn,:,npairs)**2))
                        gaps(igaps)%rot(idimn,:,npairs)=gaps(igaps)%rot(idimn,:,npairs)/xx
                    end do
                end do
            endif
        end do



        do ipoin=1,npoin
            if(gapnode(ipoin)%njcp/=0)then
                deallocate(gapnode(ipoin)%jcplist,gapnode(ipoin)%aera,gapnode(ipoin)%rot,gapnode(ipoin)%ft,gapnode(ipoin)%frict,gapnode(ipoin)%cohes)
                if (xlwmd(ndimn)>0)   &
                    deallocate(gapnode(ipoin)%Gf)
            endif
        end do
        deallocate(gapnode,ictp)  !2010/10
        nullify(xlwmd)

    end do !igaps



    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

10  if(contactpe==1) goto 20 !tcl1124

    mpairs=0 !zhao 05/09/06
    do igaps=1,ngaps

        !print *,'igaps=',igaps
        npairs=0

        xlwmd=>gaps(igaps)%xlwmd
        do igroup=1,gaps(igaps)%ngroupt !2007
            jgroup=gaps(igaps)%listgroupt(igroup)
            if (jgroup>0)then
                npairs=npairs+group(jgroup)%nelgroup
                gaps(igaps)%npairs=npairs
                index=group(jgroup)%index  !2017/02/14
                nnode=2
                if(ndimn==3)nnode=4  !2017/02/14
                if(ndimn==3.and.index==23)nnode=3  !2017/02/14
            endif
        end do

        gaps(igaps)%npairs=npairs
        if (npairs>mpairs)mpairs=npairs !zhao 05/09/06

        allocate(gaps(igaps)%pairnode(nnode*2,npairs),     gaps(igaps)%aera(npairs),          &
            gaps(igaps)%gap(ndimn,npairs),                gaps(igaps)%ctforce(ndimn,npairs), &
            gaps(igaps)%state(npairs),                    gaps(igaps)%state0(npairs),        &
            gaps(igaps)%rot(ndimn,ndimn,npairs),          gaps(igaps)%ft(npairs),            &
            gaps(igaps)%alfa1(npairs),                    gaps(igaps)%ctforce0(ndimn,npairs),&
            gaps(igaps)%ctforcei(ndimn,npairs),           gaps(igaps)%gap0(ndimn,npairs),          &
            gaps(igaps)%ctforcej(ndimn,npairs),   &
            gaps(igaps)%frict(npairs),                    gaps(igaps)%cohes(npairs),         &
            gaps(igaps)%kxyz(ndimn,ndimn,npairs),         gaps(igaps)%kxyz0(ndimn,ndimn,npairs), &
            gaps(igaps)%dxyz(ndimn,npairs),               gaps(igaps)%dxyz0(ndimn,npairs), &
            gaps(igaps)%dxyzi(ndimn,npairs),              gaps(igaps)%wsc(npairs), &
            gaps(igaps)%sigmad(npairs),gaps(igaps)%xd(npairs),gaps(igaps)%pair_process(npairs))         !2011

        gaps(igaps)%pair_process=1  !20200331
        if(miter_state>1)allocate(gaps(igaps)%statei(npairs))  !20161115


        allocate(gaps(igaps)%paire(npairs),gaps(igaps)%group(npairs))

        if (ndimn==3)allocate(gaps(igaps)%alfa2(npairs))
        if (xlwmd(ndimn)>0)allocate(gaps(igaps)%Gf(npairs))

        gaps(igaps)%ctforce=0.;gaps(igaps)%ctforce0=0.
        gaps(igaps)%dxyz=0. ; gaps(igaps)%dxyz0=0.  !2011
        gaps(igaps)%gap=0.;    gaps(igaps)%gap0=0.; gaps(igaps)%wsc=0.;gaps(igaps)%sigmad=0.;gaps(igaps)%xd=0.
        gaps(igaps)%ctforcei=0.;gaps(igaps)%dxyzi=0.;gaps(igaps)%kxyz=0.;gaps(igaps)%kxyz0=0.
        gaps(igaps)%ctforcej=0.

        npairs=0

        do igroup=1,gaps(igaps)%ngroupt !2007
            jgroup=gaps(igaps)%listgroupt(igroup)
            if (jgroup<=0)cycle
            index=group(jgroup)%index !2017/02/14
            nnode=2
            if(ndimn==3)nnode=4  !2017/02/14
            if(ndimn==3.and.index==23)nnode=3 !2017/02/14
            do ielgroup=1,group(jgroup)%nelgroup
                !   nnode=2
                !if(ndimn==3)nnode=4
                ielem = group(jgroup)%list(ielgroup)
                lnods =>element(ielem)%field(1)%lnods_f
                npairs=npairs+1
                gaps(igaps)%paire(npairs)=ielem
                gaps(igaps)%group(npairs)=jgroup
                gaps(igaps)%pairnode(1:nnode,npairs)=lnods(1:nnode)
                if(ndimn==3)then
                    gaps(igaps)%pairnode(nnode+1:nnode*2,npairs)=lnods(nnode+1:nnode*2)
                else
                    gaps(igaps)%pairnode(3,npairs)=lnods(4)
                    gaps(igaps)%pairnode(4,npairs)=lnods(3)
                endif
                gaps(igaps)%gap(ndimn,npairs)=gaps(igaps)%gapi
                gaps(igaps)%gap0(ndimn,npairs)=gaps(igaps)%gapi
                gaps(igaps)%aera(npairs)=sum(element(ielem)%aera_local(1:nnode))
                gaps(igaps)%state0(npairs)=gaps(igaps)%stateix
                gaps(igaps)%state (npairs)=gaps(igaps)%stateix

                gaps(igaps)%rot(:,:,npairs)=element(ielem)%rotation(:,:)
                gaps(igaps)%ft(npairs) =gaps(igaps)%ft0(igroup)       !2007
                gaps(igaps)%cohes(npairs) =gaps(igaps)%cohes0(igroup) !2007
                gaps(igaps)%frict(npairs) =gaps(igaps)%frict0(igroup) !2007
                if (xlwmd(ndimn)>0)gaps(igaps)%Gf(npairs) =gaps(igaps)%Gf0(igroup)     !2007
                nullify(lnods)
            end do
        end do

        nullify(xlwmd)
    end do !igaps

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
20  continue   !tcl1124

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs

            if(method_gapi==1)then
                xx=sum((coord(:,gaps(igaps)%pairnode(1,ipairs))-coord(:,gaps(igaps)%pairnode(2,ipairs)))**2)
                gaps(igaps)%gap(ndimn,ipairs)=sqrt(xx)
                gaps(igaps)%gap0(ndimn,ipairs)=sqrt(xx)
                gaps(igaps)%rot(:,:,ipairs)=0.   !special for cyct
                gaps(igaps)%rot(1,1,ipairs)=-1.  !special for cyct
                gaps(igaps)%rot(2,2,ipairs)=-1.  !special for cyct
                if(sqrt(xx)<1.e-3)then
                    gaps(igaps)%state (ipairs)=1
                    gaps(igaps)%state0(ipairs)=0
                endif
            endif
        end do
    end do


    print *,'******pairenode information******'
    if(ndimn==2)then
        write(7,*)'******pairenode information******'
        write(7,*)'igaps(1),ipairs(2),pairnode(3:4),state(5),gap(6)'
        write(7,*)'aera,ft,frict,cohes,rot(1,:),rot(2,:)'
        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            do ipairs=1,npairs
                if(block_stab/=1.and.contactpe==1)then
                    write(7,'(5i10, 1e15.3)')igaps,ipairs,gaps(igaps)%pairnode(:,ipairs),gaps(igaps)%state(ipairs),gaps(igaps)%gap(ndimn,ipairs)
                    write(7,'(8e15.3)')gaps(igaps)%aera(ipairs), &
                        gaps(igaps)%ft(ipairs),gaps(igaps)%frict(ipairs),gaps(igaps)%cohes(ipairs),gaps(igaps)%rot(1,:,ipairs),gaps(igaps)%rot(2,:,ipairs)
                elseif(contactpe==2)then
                    write(7,'(7i10, 1e15.3)')igaps,ipairs,gaps(igaps)%pairnode(:,ipairs),gaps(igaps)%state(ipairs),gaps(igaps)%gap(ndimn,ipairs)
                    write(7,'(8e15.3)')gaps(igaps)%aera(ipairs), &
                        gaps(igaps)%ft(ipairs),gaps(igaps)%frict(ipairs),gaps(igaps)%cohes(ipairs),gaps(igaps)%rot(1,:,ipairs),gaps(igaps)%rot(2,:,ipairs)
                endif
            end do
        end do
    elseif(ndimn==3)then
        write(7,*)'******pairenode information******'
        write(7,*)'igaps(1),ipairs(2),pairnode(3:4),aera,ft,frict,cohes,rot(1,:),rot(2,:),rot(3,:)'
        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            do ipairs=1,npairs
                write(7,'(4i10, 13e15.3)')igaps,ipairs,gaps(igaps)%pairnode(:,ipairs),gaps(igaps)%aera(ipairs), &
                    gaps(igaps)%ft(ipairs),gaps(igaps)%frict(ipairs),gaps(igaps)%cohes(ipairs),gaps(igaps)%rot(1,:,ipairs),gaps(igaps)%rot(2,:,ipairs), &
                    gaps(igaps)%rot(3,:,ipairs)
                !write(7,*)gaps(igaps)%frict(ipairs),gaps(igaps)%cohes(ipairs)
            end do
        end do
    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
40  continue
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(gaps(igaps)%thin_layer==1)then
                gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%aera(ipairs)*gaps(igaps)%kgroup0
            else
                gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0
            endif
            gaps(igaps)%kxyz0(:,:,ipairs)=gaps(igaps)%kxyz(:,:,ipairs)
        end do
    end do


    npbt=0
    do igapb=1,ngapb

        write(7,*)'igapb=',igapb

        nrdof=gapb(igapb)%nrdof

        allocate(jctp(npoin))
        jctp=0

        do igroup=1,gapb(igapb)%ngroupb
            jgroup=gapb(igapb)%listgroupb(igroup)
            if(jgroup<=0)cycle  !20191031
            index = group(jgroup)%index
            nnode = elkn(index)%el_field(1)%nnode_f
            do ielgroup=1,group(jgroup)%nelgroup
                ielem = group(jgroup)%list(ielgroup)
                lnods =>element(ielem)%field(1)%lnods_f
                jctp(lnods)=1
                nullify(lnods)
            enddo
        end do

        !if(nbackf/=0)then  !!20230523   此段专为位移分离反演设置
        !    		       do igapbf=1,nbackf
        !          if(igapb/=backf(igapbf)%groupb) cycle
        !                do kpoin=1,backf(igapbf)%mdism
        !       		   jpoin=backf(igapbf)%listp(kpoin)
        !                jpoin0=backf(igapbf)%relatnode(kpoin)
        !                if(jpoin/=0)jctp(jpoin)=1
        !                if(jpoin0/=0)jctp(jpoin0)=1
        !                end do
        !                end do
        !
        !endif !!20230523   此段专为位移分离反演设置

        if(block_stab==2)then  !!20191031   此段专为（块体+界面元不共网格）的块体极限平衡分析设置

            do igroup=1,gapb(igapb)%ngroupb
                jgroup=gapb(igapb)%listgroupb(igroup)
                if(jgroup>=0)cycle  !20191031

                index = group(abs(jgroup))%index
                nnode = elkn(index)%el_field(1)%nnode_f

                do ielgroup=1,group(abs(jgroup))%nelgroup
                    ielem = group(abs(jgroup))%list(ielgroup)
                    lnods =>element(ielem)%field(1)%lnods_f
                    jctp(lnods)=0
                    nullify(lnods)
                enddo
            end do

            do i0=1,gapb(igapb)%ngroupt
                igaps=gapb(igapb)%listgroupt(i0)
                ij=gapb(igapb)%pairspoint12(igaps)
                if(ij==0) cycle
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs
                    jctp(gaps(igaps)%pairnode(ij,ipairs))=1
                end do
            end do
        endif  !!20191031



        !!!!!!
        npblock=sum(jctp)  !new 09/11/23 tcl
        write(7,*)'igapb=',igapb,'npblock=',npblock

        gapb(igapb)%npblock=npblock
        allocate(gapb(igapb)%nodeblock(npblock))
        npblock=0
        do ipoin=1,npoin
            if (jctp(ipoin)==1)then
                npblock=npblock+1
                gapb(igapb)%nodeblock(npblock)=ipoin
            end if
        end do !new 09/11/23 tcl

        npgblock=0
        if(block_stab==1.or.contactpe==1)then  !!2015/8
            do i0=1,gapb(igapb)%ngroupt
                igaps=gapb(igapb)%listgroupt(i0)
                !write(7,*)'i0=',i0,'igaps=',igaps
                npairs=gaps(igaps)%npairs
                !write(7,*)'npairs=',npairs
                do ipairs=1,npairs
                    do ij=1,2
                        if (jctp(gaps(igaps)%pairnode(ij,ipairs))==1)npgblock=npgblock+1
                    end do
                end do
            end do
        elseif(contactpe==2)then  !!2015/8
            do i0=1,gapb(igapb)%ngroupt
                igaps=gapb(igapb)%listgroupt(i0)
                npgblock=npgblock+gaps(igaps)%npairs
            end do


        endif  !!2015/8


        gapb(igapb)%npgblock=npgblock

        if(nbackf/=0)then  !20211214
            kkdimn=ndimn
            if(block_stab/=0)kkdimn=3*(ndimn-1)
            allocate(gapb(igapb)%disp_ct(kkdimn,npgblock),gapb(igapb)%force_ct(kkdimn,npgblock))
            gapb(igapb)%disp_ct=0.
            gapb(igapb)%force_ct=0.
        endif !20211214

        write(7,*)'igapb=',igapb,'npgblock=',npgblock

        allocate(gapb(igapb)%nodegblock(npgblock),gapb(igapb)%nodegblock_ipairs(npgblock), &
            gapb(igapb)%nodegblock_igaps(npgblock),gapb(igapb)%nodegblock_onetwo(npgblock))


        npgblock=0
        if(block_stab==1.or.contactpe==1)then  !2015/8
            do i0=1,gapb(igapb)%ngroupt
                igaps=gapb(igapb)%listgroupt(i0)
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs
                    do ij=1,2
                        if (jctp(gaps(igaps)%pairnode(ij,ipairs))==1)then
                            npgblock=npgblock+1
                            gapb(igapb)%nodegblock(npgblock)=gaps(igaps)%pairnode(ij,ipairs)
                            gapb(igapb)%nodegblock_ipairs(npgblock)=ipairs
                            gapb(igapb)%nodegblock_igaps(npgblock)=igaps
                            gapb(igapb)%nodegblock_onetwo(npgblock)=ij !check ipair zhao 05/09/12
                            !write(7,*)igapb,npgblock,gapb(igapb)%nodegblock(npgblock)
                        endif
                    end do
                end do
            end do
        elseif(contactpe==2)then !2015/8
            do i0=1,gapb(igapb)%ngroupt


                igaps=gapb(igapb)%listgroupt(i0)

                !write(7,*)'i0=',i0,'igaps=',igaps
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs

                    nnodei=size(gaps(igaps)%pairnode(:,ipairs))  !2017/02/14
                    nnodej=nnodei/2    !2017/02/14

                    do ij=1,2
                        if(ij==1)ij1=1
                        !if(ij==1)ij2=2*(ndimn-1)
                        if(ij==1)ij2=nnodej !2017/02/14
                        !
                        !if(ij==2)ij1=2*(ndimn-1)+1
                        !if(ij==2)ij2=4*(ndimn-1)

                        if(ij==2)ij1=nnodej+1 !2017/02/14
                        if(ij==2)ij2=nnodei !2017/02/14

                        if (all(jctp(gaps(igaps)%pairnode(ij1:ij2,ipairs))==1))then
                            !write(7,*)'igapb=',igapb,'i0=',i0,'igaps=',igaps,'ipairs=',ipairs,'ij=',ij,'jctp=',jctp(gaps(igaps)%pairnode(ij1:ij2,ipairs))
                            npgblock=npgblock+1
                            !gapb(igapb)%nodegblock(npgblock)=gaps(igaps)%pairnode(ij,ipairs)
                            gapb(igapb)%nodegblock_ipairs(npgblock)=ipairs
                            gapb(igapb)%nodegblock_igaps(npgblock)=igaps
                            gapb(igapb)%nodegblock_onetwo(npgblock)=ij
                        endif
                    end do
                end do
            end do  !i0
            write(7,*)'igapb=',igapb,'npgblock=',npgblock
        endif !2015/8

        deallocate(jctp)

        if(block_stab==1)then
            ntotv_bt=npgblock*3*(ndimn-1)+gapb(igapb)%nrdof

            write(7,*)'igapb=',igapb,'nrdof=',gapb(igapb)%nrdof,'npgblock=',npgblock,'ntotv_bt=',ntotv_bt
        else
            ntotv_bt=npgblock*ndimn+gapb(igapb)%nrdof
        endif


        npbt=npbt+npgblock
        gapb(igapb)%ntotv_bt=ntotv_bt
        allocate(gapb(igapb)%nppt(npgblock),gapb(igapb)%cmatrix(ntotv_bt,ntotv_bt),gapb(igapb)%ldofs(ntotv_bt))
        gapb(igapb)%ldofs=0
        if(gapb(igapb)%nrdof/=0) then
            allocate(gapb(igapb)%rstiff(gapb(igapb)%nrdof,gapb(igapb)%nrdof))  !20121216
            gapb(igapb)%rstiff=0.  !20121216

            allocate(gapb(igapb)%rdisp_zero(gapb(igapb)%nrdof),gapb(igapb)%rdisp_inc(gapb(igapb)%nrdof), gapb(igapb)%rdisp_inc0(gapb(igapb)%nrdof),    &
                gapb(igapb)%rdisp_delitfi(gapb(igapb)%nrdof),gapb(igapb)%rdisp_deltafi(gapb(igapb)%nrdof))
            gapb(igapb)%rdisp_zero=0. ; gapb(igapb)%rdisp_inc=0.;gapb(igapb)%rdisp_inc0=0.;gapb(igapb)%rdisp_delitfi=0.;gapb(igapb)%rdisp_deltafi=0. !fzx

            if(type_problem=='F')then  !!1128
                allocate(gapb(igapb)%rdisp_first(gapb(igapb)%nrdof),gapb(igapb)%rdisp_second(gapb(igapb)%nrdof))
                gapb(igapb)%rdisp_first=0. ; gapb(igapb)%rdisp_second=0.
            endif !!1128
            if(block_stab/=1)allocate(gapb(igapb)%npdisp(ndimn,npblock,nrdof))
            if(block_stab==1)allocate(gapb(igapb)%npdisp(3*(ndimn-1),npblock,nrdof))
            gapb(igapb)%npdisp=0.
        endif
        gapb(igapb)%cmatrix=0.

    end do  !igapb
    !    allocate(listp_bt(npbt)) !tcl
    if(block_stab/=1)allocate(nodfnbt(ndimn,npbt),ntotv_btx(ngapb))!tcl
    if(block_stab==1)allocate(nodfnbt(3*(ndimn-1),npbt),ntotv_btx(ngapb))
    if(contactpe==1)allocate(npandbt(npoin))
    if(contactpe==2)allocate(npandbt(2*nelem))

    listp_bt=0 ; npandbt=0 ; nodfnbt=0
    ntotvbt=0
    npbt=0
    npandbt=0
    ntotv_btx=0
    do igapb=1,ngapb
        npgblock=gapb(igapb)%npgblock
        ntotv_bt=0
        do ipoin=1,npgblock
            npbt=npbt+1
            gapb(igapb)%nppt(ipoin)=npbt
            kdimn=ndimn
            if(block_stab==1)kdimn=3*(ndimn-1)
            do idimn=1,kdimn
                ntotvbt=ntotvbt+1
                ntotv_bt=ntotv_bt+1
                nodfnbt(idimn,npbt)=ntotvbt
                gapb(igapb)%ldofs(ntotv_bt)=ntotvbt
            end do
            !write(7,*)'igapb=',igapb,'i0=',ipoin,'nodfn=', nodfnbt(:,npbt)
        end do
        ntotv_btx(igapb)=ntotv_bt
    end do  !tcl


    do igapb=1,ngapb  !tcl
        if(gapb(igapb)%nrdof/=0)then   !tcl
            allocate(gapb(igapb)%rldofs(gapb(igapb)%nrdof))
            gapb(igapb)%rldofs=0
            ntotv_bt=ntotv_btx(igapb)
            do idimn=1,gapb(igapb)%nrdof  !tcl
                ntotvbt=ntotvbt+1
                ntotv_bt=ntotv_bt+1
                gapb(igapb)%ldofs(ntotv_bt)=ntotvbt
                if(gapb(igapb)%listrdof(idimn)==1)then
                    gapb(igapb)%rldofs(idimn)=ntotvbt
                endif
            enddo
        endif
    end do

    if(nbackf/=0)then !20150925
        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            npgblock=gapb(igapb)%npgblock
            kdimn=ndimn
            if(block_stab==1)kdimn=3*(ndimn-1)
            if(backf(igapbf)%mdism>npgblock*kdimn) allocate( gapb(igapb)%uireact(backf(igapbf)%mdism,npgblock*kdimn))
        end do
    endif


    allocate(trans_bt(ntotvbt))
    deallocate(ntotv_btx)

    !check ipair zhao 05/09/12
    write(7,*)'****************************  gapb information ****************************'
    write(7,*)'         igapb      ipgblock    ipoin        ipairs      igaps       onetwo'
    write(*,*)'check gapb information , one or two'
    do igapb=1,ngapb
        npgblock=gapb(igapb)%npgblock
        totonetwo=0
        do ipgblock=1,npgblock
            ipairs=gapb(igapb)%nodegblock_ipairs(ipgblock)
            igaps =gapb(igapb)%nodegblock_igaps (ipgblock)
            onetwo=gapb(igapb)%nodegblock_onetwo(ipgblock)
            !ipoin =gapb(igapb)%nodegblock       (ipgblock)
            write(7,*)igapb,ipgblock,ipairs,igaps,onetwo !igapb,ipgblock,ipoin,ipairs,igaps,onetwo   !2015/8
            totonetwo=totonetwo+onetwo
        enddo
        if (totonetwo==npgblock.or.totonetwo==2*npgblock)then
            write(7,*)'igapb=',igapb,'npgblock=',npgblock,'  ok'
        else
            write(7,*)'error!'
            write(7,*)'igapb=',igapb,'  error'
            write(7,*)'npgblock=',npgblock,'totonetwo=',totonetwo
            !        stop
        endif
    enddo

    end subroutine contact_point_to_point  !ctt2005

    subroutine link_concrete_and_water_pipe  !20210411
    character(80) text       !
    integer(ink) i0,i1,j1,listgroup_w,listgroup_c,nline_g_w,tnest,ie, &
        inode1,inode2,ielem,inode,ipairs,jpairs,npairs_wc, &
        ix0,jx0,ix1,jx1,twater_curve,iwc
    integer(ink),allocatable::nel_pipe(:),icpoin(:),jcpoin(:)
    real(irk)   alfa1,Qw,lamda_w,density_w,Cw,begin_time,end_time,dtime_change,k2(2,2)

    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_link_concrete_and_water_pipe_title_1,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)nwcpipe
    call diag_check_read(yl_ios,yl_msg,RD_GLB_link_concrete_and_water_pipe_water_pipe_count,0)
    print *,'nwcpipe=',nwcpipe


    if (nwcpipe==0) return
    allocate(wc_pipe(nwcpipe))
    read(gunit,*)text
    print *,text
    do i0=1,nwcpipe
        read(gunit,*)iwc,listgroup_c,listgroup_w,nline_g_w
        read(gunit,*)alfa1,Qw,lamda_w,density_w,Cw,begin_time,end_time,twater_curve,dtime_change

        wc_pipe(i0)%iwc=iwc
        wc_pipe(i0)%listgroup_w=listgroup_w
        wc_pipe(i0)%listgroup_c=listgroup_c
        wc_pipe(i0)%nline_g_w=nline_g_w

        wc_pipe(i0)%Qw=Qw
        wc_pipe(i0)%alfa1=alfa1
        wc_pipe(i0)%lamda_w=lamda_w
        wc_pipe(i0)%density_w=density_w
        wc_pipe(i0)%Cw=Cw
        wc_pipe(i0)%begin_time=begin_time
        wc_pipe(i0)%end_time=end_time
        wc_pipe(i0)%twater_curve=twater_curve
        wc_pipe(i0)%dtime_change=dtime_change


        allocate(nel_pipe(nline_g_w))
        read(gunit,*)nel_pipe
        if(sum(nel_pipe)/=group(listgroup_w)%nelgroup)then
            print *,'sum(nel_pipe)/=group(%listgroup_w%nelgroup)'
            call diag_abort('RANGE',EXIT_INPUT,'Global.f90:link_concrete_and_water_pipe','sum(nel_pipe)/=group(listgroup_w)%nelgroup')   ! M1-03 R20
        endif

        allocate(wc_pipe(i0)%line_g_w(nline_g_w))

        tnest=0
        do i1=1,nline_g_w
            wc_pipe(i0)%line_g_w(i1)%nline_w=nel_pipe(i1)
            tnest=0
            if(i1>1)tnest=sum(nel_pipe(1:(i1-1)))
            allocate(wc_pipe(i0)%line_g_w(i1)%linenode_w(2,nel_pipe(i1)))
            allocate(wc_pipe(i0)%line_g_w(i1)%ianode_w(2,nel_pipe(i1)))

            do j1=1,nel_pipe(i1)
                ielem=tnest+j1
                ie = group(listgroup_w)%list(ielem)
                wc_pipe(i0)%line_g_w(i1)%linenode_w(1:2,j1)=element(ie)%field(1)%lnods_f(1:2)
                !print *,'i0=',i0,'i1=',i1,'j1=','linenode_w=',c_pipe(i0)%line_g_w(i1)%linenode_w(1:2,j1)
            end do !j1

            !allocate(icpoin(npoin),jcpoin(npoin))
            !icpoin=0;jcpoin=0
            !do j1=1,nel_pipe(i1)
            !icpoin(wc_pipe(i0)%line_g_w(i1)%linenode_w(1:2,j1))=1
            !end do
            !npairs_wc=sum(icpoin)
            !wc_pipe(i0)%line_g_w(i1)%npairs_wc=npairs_wc

            npairs_wc=nel_pipe(i1)+1
            wc_pipe(i0)%line_g_w(i1)%npairs_wc=npairs_wc

            allocate(wc_pipe(i0)%line_g_w(i1)%pairnode_wc(npairs_wc))

            allocate(wc_pipe(i0)%line_g_w(i1)%cmatrix_c(npairs_wc,npairs_wc))
            allocate(wc_pipe(i0)%line_g_w(i1)%kmatrix_w(npairs_wc,npairs_wc))


            allocate(wc_pipe(i0)%line_g_w(i1)%idcr(npairs_wc,npairs_wc))
            allocate(wc_pipe(i0)%line_g_w(i1)%Qwc(npairs_wc))



            wc_pipe(i0)%line_g_w(i1)%cmatrix_c=0.
            wc_pipe(i0)%line_g_w(i1)%kmatrix_w=0.
            wc_pipe(i0)%line_g_w(i1)%idcr=0.
            wc_pipe(i0)%line_g_w(i1)%Qwc=0.


            do j1=1,nel_pipe(i1)
                wc_pipe(i0)%line_g_w(i1)%pairnode_wc(j1)= &
                    wc_pipe(i0)%line_g_w(i1)%linenode_w(1,j1)
            end do
            wc_pipe(i0)%line_g_w(i1)%pairnode_wc(npairs_wc)= &
                wc_pipe(i0)%line_g_w(i1)%linenode_w(2,nel_pipe(i1))


            write(7,*)'pairnode_wc=',wc_pipe(i0)%line_g_w(i1)%pairnode_wc


            do j1=1,nel_pipe(i1)
                wc_pipe(i0)%line_g_w(i1)%ianode_w(1,j1)=j1
                wc_pipe(i0)%line_g_w(i1)%ianode_w(2,j1)=j1+1
            end do

            do j1=1,nel_pipe(i1)  !水管单元刚度矩阵

                k2(1,1)=-1.;k2(1,2)=1.;k2(2,1)=-1.;k2(2,2)=1.
                k2=k2*alfa1*.5*(Cw*density_w*Qw)/lamda_w

                do ix0=1,2
                    do jx0=1,2
                        ix1=wc_pipe(i0)%line_g_w(i1)%ianode_w(ix0,j1)
                        jx1=wc_pipe(i0)%line_g_w(i1)%ianode_w(jx0,j1)
                        wc_pipe(i0)%line_g_w(i1)%kmatrix_w(ix1,jx1)=  &
                            wc_pipe(i0)%line_g_w(i1)%kmatrix_w(ix1,jx1)+k2(ix0,jx0)
                    end do
                end do
            end do !j1

        end do !i1

        deallocate(nel_pipe)
    end do !i0


10  format(10e15.5)

    end subroutine link_concrete_and_water_pipe !20210411



    subroutine link_concrete_and_steel  !20210328
    character(80) text       !
    integer(ink) i0,i1,j1,listgroup_s,listgroup_c,nline_g_sc,tnest,ie, &
        inode1,inode2,ikindsc,ielem,inode,ipairs,jpairs,npairs_sc, &
        ix0,jx0,ix1,jx1,mxter
    integer(ink),allocatable::nel_steel(:),icpoin(:),jcpoin(:),ncpoin(:)
    real(irk)   dl,diameter_s,aera_s,e,k0(2,2),  &
        k1(2,2),k2(2,2),tt(2,2),ft,err_ctl
    real(irk) ,allocatable::roti(:),rotj(:),rote(:)
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_GLB_link_concrete_and_steel_title_1,0)
    print *,text
    read(gunit,*,iostat=yl_ios,iomsg=yl_msg)nrcsteel
    call diag_check_read(yl_ios,yl_msg,RD_GLB_link_concrete_and_steel_rc_steel_count,0)
    print *,'nrcsteel=',nrcsteel

    if (nrcsteel==0) return
    allocate(rc_steel(nrcsteel),roti(ndimn),rotj(ndimn),rote(ndimn))
    read(gunit,*)text
    print *,text
    do i0=1,nrcsteel
        read(gunit,*)listgroup_c,listgroup_s,nline_g_sc,diameter_s,e,ft,ikindsc,err_ctl,mxter

        rc_steel(i0)%listgroup_s=listgroup_s
        rc_steel(i0)%listgroup_c=listgroup_c
        rc_steel(i0)%nline_g_sc=nline_g_sc
        rc_steel(i0)%diameter_s=diameter_s
        rc_steel(i0)%ft=ft
        rc_steel(i0)%ikindsc=ikindsc
        rc_steel(i0)%err_ctl=err_ctl
        rc_steel(i0)%mxter=mxter

        allocate(nel_steel(nline_g_sc))
        read(gunit,*)nel_steel
        if(sum(nel_steel)/=group(listgroup_s)%nelgroup)then
            print *,'sum(nel_steel)/=group(%listgroup_s%nelgroup)'
            call diag_abort('RANGE',EXIT_INPUT,'Global.f90:link_concrete_and_steel','sum(nel_steel)/=group(listgroup_s)%nelgroup')   ! M1-03 R20
        endif

        allocate(rc_steel(i0)%line_g_sc(nline_g_sc))

        tnest=0
        do i1=1,nline_g_sc
            rc_steel(i0)%line_g_sc(i1)%nline_s=nel_steel(i1)
            tnest=0
            if(i1>1)tnest=sum(nel_steel(1:(i1-1)))
            allocate(rc_steel(i0)%line_g_sc(i1)%linenode_s(2,nel_steel(i1)))
            allocate(rc_steel(i0)%line_g_sc(i1)%ianode_s(2,nel_steel(i1)))
            allocate(rc_steel(i0)%line_g_sc(i1)%dl_s(nel_steel(i1)))
            allocate(rc_steel(i0)%line_g_sc(i1)%rot_s(ndimn,nel_steel(i1)))
            allocate(rc_steel(i0)%line_g_sc(i1)%k2(2,2,nel_steel(i1)))
            allocate(rc_steel(i0)%line_g_sc(i1)%axial_stres(nel_steel(i1)))
            rc_steel(i0)%line_g_sc(i1)%axial_stres=0.


            do j1=1,nel_steel(i1)
                ielem=tnest+j1
                ie = group(listgroup_s)%list(ielem)
                rc_steel(i0)%line_g_sc(i1)%linenode_s(1:2,j1)=element(ie)%field(1)%lnods_f(1:2)
                !print *,'i0=',i0,'i1=',i1,'j1=','linenode_s=',rc_steel(i0)%line_g_sc(i1)%linenode_s(1:2,j1)

            end do !j1

            allocate(icpoin(npoin),jcpoin(npoin),ncpoin(npoin))
            icpoin=0;jcpoin=0;ncpoin=0
            do j1=1,nel_steel(i1)
                icpoin(rc_steel(i0)%line_g_sc(i1)%linenode_s(1:2,j1))=1
            end do
            npairs_sc=sum(icpoin)
            rc_steel(i0)%line_g_sc(i1)%npairs_sc=npairs_sc
            allocate(rc_steel(i0)%line_g_sc(i1)%pairnode_sc(npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%rot_sc(ndimn,npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%aera_sc(npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%cmatrix_c(npairs_sc,npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%kmatrix_s(npairs_sc,npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%kmatrix_cs(npairs_sc,npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%ikscr(npairs_sc,npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%tao_cs(npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%slip_sc(npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%tao0_cs(npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%slip0_sc(npairs_sc))
            allocate(rc_steel(i0)%line_g_sc(i1)%shear_stres(npairs_sc))

            rc_steel(i0)%line_g_sc(i1)%aera_sc=0.
            rc_steel(i0)%line_g_sc(i1)%rot_sc=0.
            rc_steel(i0)%line_g_sc(i1)%cmatrix_c=0.
            rc_steel(i0)%line_g_sc(i1)%kmatrix_s=0.
            rc_steel(i0)%line_g_sc(i1)%kmatrix_cs=0.
            rc_steel(i0)%line_g_sc(i1)%tao_cs=0.
            rc_steel(i0)%line_g_sc(i1)%slip_sc=0.
            rc_steel(i0)%line_g_sc(i1)%tao0_cs=0.
            rc_steel(i0)%line_g_sc(i1)%slip0_sc=0.
            rc_steel(i0)%line_g_sc(i1)%ikscr=0.
            rc_steel(i0)%line_g_sc(i1)%shear_stres=0.

            ipairs=0
            do j1=1,npoin
                if(icpoin(j1)==0)cycle
                ipairs=ipairs+1
                rc_steel(i0)%line_g_sc(i1)%pairnode_sc(ipairs)=j1
                jcpoin(j1)=ipairs
            end do

            do j1=1,nel_steel(i1)
                inode1=rc_steel(i0)%line_g_sc(i1)%linenode_s(1,j1)
                inode2=rc_steel(i0)%line_g_sc(i1)%linenode_s(2,j1)
                rc_steel(i0)%line_g_sc(i1)%ianode_s(1,j1)=jcpoin(inode1)
                rc_steel(i0)%line_g_sc(i1)%ianode_s(2,j1)=jcpoin(inode2)

                ncpoin(inode1)=ncpoin(inode1)+1
                ncpoin(inode2)=ncpoin(inode2)+1
                dl=sum((coord(:,inode2)-coord(:,inode1))**2)
                dl=sqrt(dl)
                rc_steel(i0)%line_g_sc(i1)%dl_s(j1)=dl
                rc_steel(i0)%line_g_sc(i1)%rot_s(:,j1)=(coord(:,inode2)-coord(:,inode1))/dl
                ipairs=jcpoin(inode1)
                jpairs=jcpoin(inode2)
                print *,'ie=',j1,'rot_s=',rc_steel(i0)%line_g_sc(i1)%rot_s(:,j1)

                rc_steel(i0)%line_g_sc(i1)%rot_sc(:,ipairs)=  &
                    rc_steel(i0)%line_g_sc(i1)%rot_sc(:,ipairs)+rc_steel(i0)%line_g_sc(i1)%rot_s(:,j1)
                rc_steel(i0)%line_g_sc(i1)%aera_sc(ipairs)=  &
                    rc_steel(i0)%line_g_sc(i1)%aera_sc(ipairs)+.5*3.14159*diameter_s*dl

                rc_steel(i0)%line_g_sc(i1)%rot_sc(:,jpairs)=  &
                    rc_steel(i0)%line_g_sc(i1)%rot_sc(:,jpairs)+rc_steel(i0)%line_g_sc(i1)%rot_s(:,j1)
                rc_steel(i0)%line_g_sc(i1)%aera_sc(jpairs)=  &
                    rc_steel(i0)%line_g_sc(i1)%aera_sc(jpairs)+.5*3.14159*diameter_s*dl
            end do !j1

            !print *,'pairnode=',rc_steel(i0)%line_g_sc(i1)%pairnode_sc
            !print *,'dl_s=',rc_steel(i0)%line_g_sc(i1)%dl_s

            do ipairs=1,npairs_sc
                inode=rc_steel(i0)%line_g_sc(i1)%pairnode_sc(ipairs)
                rc_steel(i0)%line_g_sc(i1)%rot_sc(:,ipairs)=   &
                    rc_steel(i0)%line_g_sc(i1)%rot_sc(:,ipairs)/ncpoin(inode)
                !print *,'ipairs=',ipairs,'rot_sc=',rc_steel(i0)%line_g_sc(i1)%rot_sc(:,ipairs)
            end do

            do j1=1,nel_steel(i1)  !钢筋单元刚度矩阵

                dl= rc_steel(i0)%line_g_sc(i1)%dl_s(j1)
                aera_s=3.14159*(.5*diameter_s)**2
                k0(1,1)=1.;k0(1,2)=-1.;k0(2,1)=-1.;k0(2,2)=1.
                k0=k0*e* aera_s/dl
                ix1=rc_steel(i0)%line_g_sc(i1)%ianode_s(1,j1)
                jx1=rc_steel(i0)%line_g_sc(i1)%ianode_s(2,j1)
                roti=rc_steel(i0)%line_g_sc(i1)%rot_sc(:,ix1)
                rotj=rc_steel(i0)%line_g_sc(i1)%rot_sc(:,jx1)
                rote=rc_steel(i0)%line_g_sc(i1)%rot_s(:,j1)
                tt=0.
                tt(1,1)=dot_product(rote,roti)
                tt(2,2)=dot_product(rote,rotj)
                k1=k0.x.tt
                k2=transpose(tt).x.k1



                do ix0=1,2
                    do jx0=1,2
                        ix1=rc_steel(i0)%line_g_sc(i1)%ianode_s(ix0,j1)
                        jx1=rc_steel(i0)%line_g_sc(i1)%ianode_s(jx0,j1)
                        rc_steel(i0)%line_g_sc(i1)%kmatrix_s(ix1,jx1)=  &
                            rc_steel(i0)%line_g_sc(i1)%kmatrix_s(ix1,jx1)+k2(ix0,jx0)
                    end do
                end do
                rc_steel(i0)%line_g_sc(i1)%k2(:,:,j1)=k2/aera_s  !20220314

            end do !j1



            !write(7,*)'kmatrix_s='
            !   do ix0=1,npairs_sc
            !   write(7,10)rc_steel(i0)%line_g_sc(i1)%kmatrix_s(ix0,:)
            !   end do

            !print *,'aera_sc=',rc_steel(i0)%line_g_sc(i1)%aera_sc
            deallocate(icpoin,jcpoin,ncpoin)
        end do !i1

        deallocate(nel_steel)
    end do !i0

    deallocate(roti,rotj,rote)

10  format(10e15.5)

    end subroutine link_concrete_and_steel !20210328


    subroutine beam_section_dis_int(igaps,ipairs,pairnode1,nptop,ix,ntpoin)   !!2015/11/17
    integer(ink) pairnode1,iptop,ipoin1,jdimn,idimn,itotv,nintf,igaps,nptop,ix,ipairs,ntpoin(:),iintf,jintf
    real   (irk),allocatable::dist(:),disgi(:,:)

    !write(7,*)'pairnode1=', pairnode1,'nodfn=',nodfn(1:6,pairnode1)

    allocate(dist(ndimn),disgi(ndimn,3*(ndimn-1)))


    do iptop=1,nptop
        if(ix==1) &
            ipoin=gaps(igaps)%gaps_collect(ipairs)%listtop(iptop)
        if(ix==2) &
            ipoin=gaps(igaps)%gaps_collect(ipairs)%listbotom(iptop)

        do jdimn=1,ndimn
            dist(jdimn)=coord(jdimn,ipoin)-coord(jdimn,pairnode1)
        end do

        disgi=0.
        do idimn=1,ndimn
            disgi(idimn,idimn)=1.
        end do

        if(ndimn==2)then
            disgi(1,3)=-dist(2)
            disgi(2,3)= dist(1)
        elseif(ndimn==3)then
            disgi(1,5)= dist(3)
            disgi(1,6)=-dist(2)

            disgi(2,4)=-dist(3)
            disgi(2,6)= dist(1)

            disgi(3,4)= dist(2)
            disgi(3,5)=-dist(1)
        endif

        if(ipoin/=pairnode1)then
            !write(7,*)'ipoin=',ipoin,'pairnode1=',pairnode1
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                nintf=3*(ndimn-1)
                !trans(itotv)%nintf=nintf
                !allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                do iintf=1,nintf
                    trans(itotv)%nintf=trans(itotv)%nintf+1
                    jintf=trans(itotv)%nintf

                    trans(itotv)%listf(jintf)=nodfn(iintf,pairnode1)
                    trans(itotv)%rintf(jintf)=disgi(idimn,iintf)/ntpoin(ipoin)
                end do
                !   if(itotv==33694.or.itotv==33695) &
                !   write(7,*)'itotv=',itotv,'trans(itotv)%nintf=',trans(itotv)%nintf,'listf=', trans(itotv)%listf(1:trans(itotv)%nintf),'rintf=',trans(itotv)%rintf(1:trans(itotv)%nintf)
            end do
        endif



    end do

    deallocate( dist,disgi)
    end  subroutine beam_section_dis_int  !!2015/11/17
    subroutine nodegapchange(njcp,ipoin,xlwmd)
    integer(ink) njcp,ipoin,i0,xlwmd(:)
    integer(ink),allocatable::jcplist(:)
    real   (irk),allocatable::aera(:),rot(:,:,:),ft(:),frict(:),cohes(:),Gf(:)

    allocate(jcplist(njcp),rot(ndimn,ndimn,njcp),aera(njcp),ft(njcp),cohes(njcp),frict(njcp),Gf(njcp))
    do i0=1,njcp-1
        jcplist(i0)=gapnode(ipoin)%jcplist(i0)
        aera(i0)=gapnode(ipoin)%aera(i0)
        rot(:,:,i0)=gapnode(ipoin)%rot(:,:,i0)
        ft(i0)=gapnode(ipoin)%ft(i0)
        frict(i0)=gapnode(ipoin)%frict(i0)
        cohes(i0)=gapnode(ipoin)%cohes(i0)
        if (xlwmd(ndimn)>0)   &
            Gf(i0)=gapnode(ipoin)%Gf(i0)
    end do
    if(njcp>1) then
        deallocate(gapnode(ipoin)%jcplist,gapnode(ipoin)%aera,gapnode(ipoin)%rot,gapnode(ipoin)%ft,gapnode(ipoin)%frict,gapnode(ipoin)%cohes)
        if (xlwmd(ndimn)>0)   &
            deallocate(gapnode(ipoin)%Gf)
    endif

    allocate(gapnode(ipoin)%jcplist(njcp),gapnode(ipoin)%aera(njcp),gapnode(ipoin)%rot(ndimn,ndimn,njcp),gapnode(ipoin)%ft(njcp),  &
        gapnode(ipoin)%frict(njcp),gapnode(ipoin)%cohes(njcp))
    gapnode(ipoin)%aera(njcp)=0.
    gapnode(ipoin)%rot(:,:,njcp)=0.
    gapnode(ipoin)%ft(njcp)=0.
    gapnode(ipoin)%frict(njcp)=0.
    gapnode(ipoin)%cohes(njcp)=0.
    if (xlwmd(ndimn)>0)   &
        allocate(gapnode(ipoin)%Gf(njcp))
    if (xlwmd(ndimn)>0)   &
        gapnode(ipoin)%Gf(njcp)=0.
    do i0=1,njcp-1
        gapnode(ipoin)%jcplist(i0)=jcplist(i0)
        gapnode(ipoin)%aera(i0)=aera(i0)
        gapnode(ipoin)%rot(:,:,i0)=rot(:,:,i0)
        gapnode(ipoin)%ft(i0)=ft(i0)
        gapnode(ipoin)%frict(i0)=frict(i0)
        gapnode(ipoin)%cohes(i0)=cohes(i0)
        if (xlwmd(ndimn)>0)   &
            gapnode(ipoin)%Gf(i0)=Gf(i0)
    end do
    deallocate(jcplist,rot,aera,ft,cohes,frict,Gf)

    end subroutine nodegapchange

    subroutine contact_pair_process0

    integer(ink) igroup,ielem,igaps,ipairs,npairs,ielgroup,ipoin1,ipoin2
    integer(ink),allocatable::ipx(:)
    integer(ink),pointer::lnods(:)

    allocate(ipx(npoin))

    ipx=0
    do igroup=1,ngroup
        if (appear_process(igroup,iblks)==0)cycle
        do ielgroup=1,group(igroup)%nelgroup
            ielem= group(igroup)%list(ielgroup)
            lnods=>element(ielem)%field(1)%lnods_f
            ipx(lnods)=1
        enddo
    enddo

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            ipoin1=gaps(igaps)%pairnode(1,ipairs)
            ipoin2=gaps(igaps)%pairnode(2,ipairs)
            gaps(igaps)%pair_process(ipairs)=1       !2021/06/30

            !gaps(igaps)%pair_process(ipairs)=0
            !if (ipx(ipoin1)==1.and.ipx(ipoin2)==1)gaps(igaps)%pair_process(ipairs)=1
        enddo
    enddo
    deallocate(ipx)

    end subroutine contact_pair_process0

    subroutine contact_pair_process  !20210630
    !20210630修改：对于不参与运算块体单元组，其接触点对不考虑施工过程影响。

    integer(ink) igroup,ielem,igaps,ipairs,npairs,ielgroup,ipoin1,ipoin2,eblock,igapb,jgroup
    integer(ink),allocatable::ipx(:)
    integer(ink),pointer::lnods(:)

    allocate(ipx(npoin))
    ipx=0
    do igapb=1,ngapb
        do igroup=1,gapb(igapb)%ngroupb
            jgroup=gapb(igapb)%listgroupb(igroup)
            eblock=gapb(igapb)%eblock
            if (eblock==1.and.appear_process(jgroup,iblks)==0)cycle
            do ielgroup=1,group(jgroup)%nelgroup
                ielem= group(jgroup)%list(ielgroup)
                lnods=>element(ielem)%field(1)%lnods_f
                ipx(lnods)=1
            enddo
        end do
    end do



    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            ipoin1=gaps(igaps)%pairnode(1,ipairs)
            ipoin2=gaps(igaps)%pairnode(2,ipairs)

            gaps(igaps)%pair_process(ipairs)=0
            if (ipx(ipoin1)==1.and.ipx(ipoin2)==1)gaps(igaps)%pair_process(ipairs)=1
        enddo
    enddo
    deallocate(ipx)
    nullify(lnods)

    end subroutine contact_pair_process




    subroutine dateandtime(datetime) !20200220
    character*20 curtime,curdate,datetime

    call DATE_AND_TIME(curdate,curtime)
    datetime=curdate(1:4)//'-'//curdate(5:6)//'-'//curdate(7:8)
    datetime=trim(datetime)//' '//curtime(1:2)//':'//curtime(3:4)//':'//curtime(5:6)
    end subroutine dateandtime

    end module global_var




