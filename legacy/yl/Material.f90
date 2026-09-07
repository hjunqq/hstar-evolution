    module materials

    use yl_diag
    use yl_diag_registry
    use variable_types
    use global_var

    implicit none

    type stress_strain_curve
        integer(ink) npoints
        character(10)type_curve
        real   (irk) confining   ! confining pressure
        real   (irk),pointer:: strain_curve(:),a(:)
        real   (irk),pointer:: stress_curve(:)
    end type stress_strain_curve

    type material_1
        character(20)criteria
        real   (irk) sigma0, hardening, frict_angle, dilan_angle,ft,sigmat,sigma0_ini,frict_angle_ini,dilan_angle_ini
        integer(ink) csigma0, cfrict, cdilan,cft,csigmat
    end type material_1

    type material_2
        real(irk)  Pc, lamda, Mg, Mf, D0, D1, gamma
    end type material_2

    type material_3
        integer(ink) ntest
        real(irk)  d(24)
    end type material_3

    type material_4
        real(irk)  A,B,C,D,Fc,Gf,h,Ct ! A,B,C,D for parameters,
        ! Fc compressive strength, h mesh size
        ! Ct=Ft/Fc
        integer(ink) icr   !icr=1, general brittle elastic rupture

        real(irk) at,bt,alfat,t1,t2,t3,t4,ft0,eft
        real(irk) ac,bc,alfac,c1,c2,c3,c4,fc0,efc
        real(irk) bb,dt,et0
    end type material_4

    type material_fcm  !20210125
        real(irk)  w0,w1,w2,ft,ft1,Gf
        real(irk),pointer::kns0(:)
        integer(ink)xlwmodel
    end type material_fcm !20210125

    type material_5
        character(len=2) model            !DuncanChang
        real(irk)  Cohes,phi,K,n,Rf,G,F,Vtf,Nur,Kur,Pa,P0  !G,F,Vtf for model EV
        real(irk)  Kb,m,dphi      !for model EB
        real(irk)  phi_s,K_s
        real(irk)  k1,k2,nd,lamdaMax !20231215YL
    end type material_5

    type material_6
        character(10) model            !goodman
        real(irk)  phi,K1,n,Rf,kzz,kzx,kzy,gamaw,Pa,cohes,Ft  !janbu
        real(irk)  frict_angle, uniax_cohes
        integer(ink) point1,point2
        !20231215YL
        integer(ink) IWJ,fill !20231007 止水 IWJ指定为1，2，或3，分别表示止水铜片、止水塑料或两者组合
        real(irk),pointer::A(:) !20231007 止水1-13参数，14、15，分别为变形参数
        !20231215YL
        type(material_fcm),pointer::fcmp  !20210125
    end type material_6

    type material_7
        integer(ink) nr,cvstrain     !nzw 2006-05-21 for vstrain              !concrete creep
        real   (irk) a,b,alfas,bs,cs,ds,m1,m2,m3 !适用于堆石体模型
        real   (irk) Ek,etak,etam   !适用于burgers模型  ！20180630
        real(irk),pointer::c(:),d(:),f(:),k(:)
    end type material_7

    type soil_wetting
        !integer(ink) kind_wt                  !湿化变形模型类型:(1:沈珠江Cw-Dw模型,..)
        real   (irk) Cw,Dw,nw
        real   (irk) a,b,c
    end type soil_wetting

    type material_8
        real   (irk) a,b,c,d,l0
    end type material_8

    type material_9 !ep2010
        integer(ink) np
        real(irk),pointer::p(:),es(:)
    end type material_9

    type material_10 !ep2010
        integer(ink),pointer::point(:)
        real(irk),pointer::ft(:)
    end type material_10

    type material_11 !钢螺栓   ！20211125
        integer(ink) np,csigma  !np：定义非线性模量的节点数，csigma：梁屈服应力计算方式（1，轴拉；2，轴拉+剪；(暂时只考虑1和2）
        !      3：轴拉与弯曲应力的最大值作为正应力，剪与扭剪组合最大值作为剪应力,VonMises公式计算屈服应力)
        real(irk),pointer::sig(:),es(:)
    end type material_11  !20211125

    type material_12 !   盾构界面弹簧 20211125
        real(irk),pointer::kxyz(:)
        real(irk) ktheta1,ktheta2
    end type material_12 !20211125

    type material_13			!for SandPZ !20220713
        integer(ink) ntest,humidification,pztype
        integer(ink),allocatable:: bline(:),eline(:)
        real(irk),allocatable::sigmad(:)
        real(irk)  d(24)
    end type material_13

    type material_14			!for ClayPZ !20220713
        integer(ink) ntest
        real(irk)  d(11)
    end type material_14

    type material_15            !20220713
        integer(ink) nalfa,ncycl		!抗液化剪应力与垂直应力和剪应力比之关系
        real(irk),pointer::ta(:,:),tb(:,:)
        real(irk),pointer::alfai(:),cycli(:)
    end type material_15

    type gap_describe  !20231006
        integer(ink) gap_kind,ngapx
        real(irk) radius
        real(irk),allocatable::centerx(:),gapx(:),gapalfax(:)
    end type gap_describe !20231006

    type solid_skeleton
        real(irk) density,ratio,thickness,E,nu,alfa,gap0,ftcontact,icft !zhao 05/08/02
        integer(ink)igap0,icreep,np,kind_wt,jliqu
        integer(ink)iE,iNu  !20190810
        real(irk) density_w !20220409
        real(irk),pointer::normalstress(:),normale(:)
        character(len=30) material

        type(gap_describe),pointer::gap_define  !20231006

        type(material_1),pointer::ClassicalEP
        type(material_2),pointer::CamClay
        type(material_3),pointer::SoilPZ
        type(material_4),pointer::Concrete
        type(material_5),pointer::DuncanChang
        type(material_6),pointer::Goodman
        type(material_7),pointer::creep
        type(material_8),pointer::Elastic_Spring
        type(material_9),pointer::Elastic_ep !ep2010
        type(material_10),pointer::Plane_lowft !ep2010
        type(material_11),pointer::steel_ep !20211125
        type(material_12),pointer::steel_sp !20211125 螺栓处弹簧
        type(soil_wetting),pointer::wetting_def !20220409

        type(material_13),pointer::SandPZ !20220713
        type(material_14),pointer::ClayPZ !20220713
        type(material_15),pointer::scycl  !20220713


    end type solid_skeleton

    type fluid_phase
        real(irk) density,ratio,bulkw,c !ifs2006 zhao, 06/03/29
        real(irk) ,pointer::permeability(:)
        integer(ink) ksmsa, nswpw, npmpm, iperm
        real(irk)    dpwats,dpwatp
        real(irk),pointer::swpwc(:),pmpwc(:),pwats(:),pwatp(:)
        real(irk)  bulks,bulkd
    end type fluid_phase

    type geometry_property    ! only for bem or bar element
        real(irk) Aera,J,Iy,Iz
        real(irk),pointer:: rotlg(:,:)  !20200116
        integer(ink) ipd  !20200116
        integer(ink),pointer::point_direct(:)
    end type geometry_property

    type mechanical_property
        type(solid_skeleton),pointer::solid
        type(fluid_phase) , pointer::fluid
    end type mechanical_property

    !type heat_property
    !   real(irk),pointer:: alfa(:)  !导温系数
    !   integer(ink) source_curve  !热源导数曲线(d(theta)/dtime)
    !   integer(ink) place_curve  !placement temperature curve
    !end type heat_property

    type heat_property  !20200221
        real(irk),pointer:: alfa(:)  !导温系数
        real(irk) tem_water,time_cooling,b,s,bcooltime
        integer(ink) ialfa         !作为随机变量处理时的序号
        integer(ink) source_curve  !热源导数曲线(d(theta)/dtime)
        integer(ink) place_curve  !placement temperature curve
        integer(ink) pipe_cooling !consider the equivalent pipe cooling effect
        integer(ink) water_curve  !cooling water temperature curve
    end type heat_property  !20200221

    type material_property
        character(20)name
        type(mechanical_property),pointer::mechanical
        type(heat_property),pointer::heat
        type(geometry_property),pointer::geometry
    end type material_property

    type(stress_strain_curve), allocatable::scurves(:)        !nscurve
    type(material_property),   allocatable::props(:)

    contains

    subroutine material_set

    integer(ink) imat, nline,iline,iphase,nphase,icels,ksmsa,nswpw,npmpm,ntest
    integer(ink) iscurve,nscurve,npoints,jmat,icreep,nr,icr,cvstrain,np !ep2010
    integer(ink) iE,iNu,mmats,xlwmodel,kind_wt  !20220409
    integer(ink)  jliqu,nalfa,ncycl,humidification,pztype  !20220713
    integer(ink),allocatable::point_direct(:)


    real(irk)    density,ratio,bulkw,thickness,e,nu,a,b,alfa,alfas,bs,cs,ds,m1,m2,m3,dis,xx   !20200116
    real(irk),   allocatable::d(:),ax(:),rotlg(:,:)
    real(irk),   allocatable::gapalfax(:),centerx(:),gapx(:)  !20231006
    integer(ink)  ngapx,igap0   !20231006

    real(irk) xmgc,xmfc,alfaf,alfag,frict,dilan,sigma0,radius !20231006
    real(irk) hev0,hes0,beta0,beta1,expf
    real(irk) h0,hu0,gamhu,gamdm,pcut,phig,phif
    real(irk) dpwats,dpwatp,bulks,bulkd,density_w !20220409
    real(irk) ft0,eft,at,bt,alfat,fc0,efc,ac,bc,alfac,c1,c2,c3,c4,x0,y0,fc,ft,ci,ct,gf,h,cx
    real(irk) s,gap_cooling,eata  !20200221 modified from chengjing
    real(irk) w0,w1,ft1
    real(irk) mg,mf,kevo,keso,gama,gamau,extcr,PZUNIT   !SandPZ 20220713


    character (30) name,phase,material,criteria,property,type_curve
    character (10 ) model
    character (80) text
    logical,allocatable::yl_seen(:)   ! M1-03: imat already defined

    allocate(props(nmats))

    read(munit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_title_1,0)
    read(munit,*,iostat=yl_ios,iomsg=yl_msg)nscurve
    call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_curve_count,0)
    if (nscurve.ne.0)allocate(scurves(nscurve))
    do iscurve=1,nscurve

        read(munit,*)npoints,type_curve   !20200220

        scurves(iscurve)%npoints=npoints
        scurves(iscurve)%type_curve=type_curve
        allocate(scurves(iscurve)%strain_curve(npoints))
        allocate(scurves(iscurve)%stress_curve(npoints))
        read(munit,*)scurves(iscurve)%strain_curve(1:npoints)
        read(munit,*)scurves(iscurve)%stress_curve(1:npoints) !!one record

    end do

    read(munit,*,iostat=yl_ios,iomsg=yl_msg)nline
    call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_comment_line_count,0)
    do iline=1,nline
        read(munit,*,iostat=yl_ios,iomsg=yl_msg) text
        call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_comment_line_1,iline)
        print *, text
    end do


    read(munit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_title_2,0)
    read(munit,*,iostat=yl_ios,iomsg=yl_msg)mmats  ! !20200617
    call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_nmats,0)
    call diag_range(RD_MAT_material_set_nmats,0,'nmats',int(mmats,i8),int(nmats,i8),int(nmats,i8))   ! M1-03: must equal .glb nmats (props is sized by it)
    call diag_flush_stage()
    allocate(yl_seen(nmats)) ; yl_seen=.false.

    do jmat=1,mmats

        print *,'jmat=',jmat
        read(munit,*,iostat=yl_ios,iomsg=yl_msg)text
        call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_title_3,0)
        read(munit,*,iostat=yl_ios,iomsg=yl_msg)property,name,imat
        call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_material_header,0)
        call diag_range(RD_MAT_material_set_material_header,jmat,'imat',int(imat,i8),1_i8,int(nmats,i8))   ! M1-03: props(imat) is written next
        call diag_flush_stage()
        if(yl_seen(imat))call diag_dup(RD_MAT_material_set_material_header,jmat,'imat',int(imat,i8))
        call diag_flush_stage()
        yl_seen(imat)=.true.

        print *,property,name,imat

        props(imat)%name=trim(name)
        property_select: select case(trim(property))                                       ! select 1

        case('MECHANICAL')
            allocate(props(imat)%mechanical)
            read(munit,*,iostat=yl_ios,iomsg=yl_msg)nphase
            call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_material_nphase,0)
            do iphase=1,nphase      !! loop for nphase

                read(munit,*,iostat=yl_ios,iomsg=yl_msg)phase
                call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_material_phase,0)

                phase_select: select case(trim(phase))
                    ! select 2

                case('SOLID')
                    allocate(props(imat)%mechanical%solid)
                    read(munit,*,iostat=yl_ios,iomsg=yl_msg)material,density,ratio,thickness,e,nu,alfa,icreep,kind_wt,jliqu  !20220713
                    call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_elastic_isotropic,0)
                    print *,material,density,ratio,thickness,e,nu,alfa,icreep,kind_wt,jliqu
                    read(munit,*,iostat=yl_ios,iomsg=yl_msg)iE,iNu,density_w   !20190810
                    call diag_check_read(yl_ios,yl_msg,RD_MAT_material_set_elastic_extra,0)
                    props(imat)%mechanical%solid%material =trim(material)
                    props(imat)%mechanical%solid%density  =density
                    props(imat)%mechanical%solid%density_w  =density_w
                    props(imat)%mechanical%solid%ratio    =ratio
                    props(imat)%mechanical%solid%thickness=thickness
                    props(imat)%mechanical%solid%e        =e
                    props(imat)%mechanical%solid%nu       =nu
                    props(imat)%mechanical%solid%alfa     =alfa
                    props(imat)%mechanical%solid%icreep   =icreep   !2019/09/30
                    props(imat)%mechanical%solid%iE   =iE
                    props(imat)%mechanical%solid%iNu   =iNu
                    props(imat)%mechanical%solid%kind_wt   =kind_wt
                    props(imat)%mechanical%solid%jliqu   =jliqu

                    !! for parameters of anti-liquifaction
                    if(jliqu.ne.0) then  !20220713
                        allocate(props(imat)%mechanical%solid%scycl)
                        read(munit,*)nalfa,ncycl
                        props(imat)%mechanical%solid%scycl%nalfa=nalfa
                        props(imat)%mechanical%solid%scycl%ncycl=ncycl
                        allocate(props(imat)%mechanical%solid%scycl%ta(nalfa,ncycl),  &
                            props(imat)%mechanical%solid%scycl%tb(nalfa,ncycl),  &
                            props(imat)%mechanical%solid%scycl%alfai(nalfa),     &
                            props(imat)%mechanical%solid%scycl%cycli(ncycl))
                        read(munit,*)props(imat)%mechanical%solid%scycl%alfai, &
                            props(imat)%mechanical%solid%scycl%cycli
                        do i0=1,nalfa
                            read(munit,*)props(imat)%mechanical%solid%scycl%ta(i0,:), &
                                props(imat)%mechanical%solid%scycl%tb(i0,:)
                        end do
                    endif

                    ! icreep=0:不考虑徐变、不考虑模量变化、不考虑体积收缩变化
                    ! icreep=1,a/=0,cstrain=0:不考虑徐变、考虑模量变化、不考虑体积收缩变化
                    ! icreep=1,a=0,cstrain/=0:不考虑徐变、不考虑模量变化、考虑体积收缩变化
                    ! icreep=1,a/=0,cstrain/=0:不考虑徐变、考虑模量变化、考虑体积收缩变化
                    ! icreep=2:考虑混凝土徐变
                    ! icreep=3:堆石体徐变（方维凤、混凝土面板堆石坝流变研究，河海大学博士学位论文，2003）
                    ! icreep=4:岩体蠕变（博格斯（Burgers）模型）
                    ! cvstrain为体积变化曲线号，曲线在MAT文件中定义
                    !! for creep
                    !print *,'icreep=',icreep
                    if (icreep>0.and.icreep<=2) then  !20220422
                        allocate(props(imat)%mechanical%solid%creep)
                        read(munit,*)nr,a,b,cvstrain     !nzw 2006-05-21 for vstrain
                        props(imat)%mechanical%solid%creep%nr=nr
                        props(imat)%mechanical%solid%creep%a =a
                        props(imat)%mechanical%solid%creep%b =b
                        props(imat)%mechanical%solid%creep%cvstrain=cvstrain
                        !! for creep

                        if (icreep==2) then
                            allocate(props(imat)%mechanical%solid%creep%c(nr),  &
                                props(imat)%mechanical%solid%creep%d(nr),  &
                                props(imat)%mechanical%solid%creep%f(nr),  &
                                props(imat)%mechanical%solid%creep%k(nr))
                            read(munit,*)props(imat)%mechanical%solid%creep%c,  &
                                props(imat)%mechanical%solid%creep%d,  &
                                props(imat)%mechanical%solid%creep%f,  &
                                props(imat)%mechanical%solid%creep%k
                        endif
                    else if (icreep==3) then  !2013510
                        !print *,'icreepxx=',icreep
                        allocate(props(imat)%mechanical%solid%creep)
                        read(munit,*)nr,alfas,bs,ds
                        !print *,'nr,alfas,bs,ds=',nr,alfas,bs,ds
                        props(imat)%mechanical%solid%creep%nr=nr
                        props(imat)%mechanical%solid%creep%alfas =alfas
                        props(imat)%mechanical%solid%creep%bs =bs
                        props(imat)%mechanical%solid%creep%ds =ds
                        if(nr==7)then
                            read(munit,*)cs,m1,m2,m3
                            !print *,'cs,m1,m2,m3=',cs,m1,m2,m3
                            props(imat)%mechanical%solid%creep%cs =cs
                            props(imat)%mechanical%solid%creep%m1 =m1
                            props(imat)%mechanical%solid%creep%m2 =m2
                            props(imat)%mechanical%solid%creep%m3 =m3
                        endif
                    else if (icreep==4) then  !20180630
                        !print *,'icreepxx=',icreep
                        allocate(props(imat)%mechanical%solid%creep)
                        read(munit,*)props(imat)%mechanical%solid%creep%Ek,props(imat)%mechanical%solid%creep%etak,props(imat)%mechanical%solid%creep%etam

                    endif
                    !! end for creep

                    !! for wetting deformation
                    if (kind_wt>0) then  !20220409
                        allocate(props(imat)%mechanical%solid%wetting_def)
                        !1.沈珠江Cw-Dw模型(沈珠江,王剑平:土质心墙坝填筑及蓄水的数值模拟，水利水运科学研究，1988（4）：47-63）
                        !        strain_vs=Cw;Gama_s=Dw*SL/（1-SL)
                        !2.改进Cw-Dw模型(李全明等:黄河公伯峡面板堆石坝三维湿化变形分析,水力发电学报,Vol.24(3),2005：24-29）
                        !        strain_vs=sigma3/(a+b*sigma3);Gama_s=Dw*SL/（1-SL)
                        !3.改进Cw-Dw模型(王富强等:积石峡面板堆石坝三维湿化变形分析,水力发电学报,Vol.28(2),2009：56-60）
                        !        strain_vs=sigma3/(a+b*sigma3)-c*Gama_s;Gama_s=Dw*SL/（1-SL)
                        !4.改进Cw-Dw模型(李国英、刘玉年:砂石料浸水变形三维有限元分析,1998）
                        !        strain_vs=Cw*(sigma3/Pa)**nw;Gama_s=Dw*SL/（1-SL)
                        read(munit,*)props(imat)%mechanical%solid%wetting_def%Cw, &
                            props(imat)%mechanical%solid%wetting_def%Dw, &
                            props(imat)%mechanical%solid%wetting_def%nw, &
                            props(imat)%mechanical%solid%wetting_def%a, &
                            props(imat)%mechanical%solid%wetting_def%b, &
                            props(imat)%mechanical%solid%wetting_def%c
                    endif  !20220409
                    if (name=='CONTACT') &
                        read(munit,*)props(imat)%mechanical%solid%igap0, &
                        props(imat)%mechanical%solid%gap0,  &
                        props(imat)%mechanical%solid%ftcontact, &
                        props(imat)%mechanical%solid%icft
                    igap0=props(imat)%mechanical%solid%igap0
                    if(igap0==2)then !20231006
                        allocate(props(imat)%mechanical%solid%gap_define)  !20231006
                        read(munit,*)props(imat)%mechanical%solid%gap_define%gap_kind,  &
                            ngapx
                        if(props(imat)%mechanical%solid%gap_define%gap_kind==1)then
                            if(ndimn/=2)then
                                print *, 'stop for igap0=2 and gap_kind=1,but ndimn/=2'
                                call diag_abort('UNSUPPORTED',EXIT_UNSUPPORTED,'Material.f90:material_set','igap0=2 with gap_kind=1 is only implemented for ndimn=2')   ! M1-03 R20
                            endif   !ndimn==2
                            allocate(centerx(ndimn),gapx(ngapx),gapalfax(ngapx))
                            allocate(props(imat)%mechanical%solid%gap_define%centerx(ndimn),  &
                                props(imat)%mechanical%solid%gap_define%gapx(ngapx),  &
                                props(imat)%mechanical%solid%gap_define%gapalfax(ngapx))
                            read(munit,*) radius,centerx
                            read(munit,*) gapalfax
                            read(munit,*) gapx
                            props(imat)%mechanical%solid%gap_define%radius=radius
                            props(imat)%mechanical%solid%gap_define%ngapx=ngapx
                            props(imat)%mechanical%solid%gap_define%centerx=centerx
                            props(imat)%mechanical%solid%gap_define%gapalfax=gapalfax
                            props(imat)%mechanical%solid%gap_define%gapx=gapx
                            deallocate(centerx,gapx,gapalfax) !20231006
                        endif  !gap_kind==1
                    end if !igap0==2 !20231006

                    if (name=='NOLINORMK')then
                        read(munit,*)np
                        props(imat)%mechanical%solid%np=np
                        allocate(props(imat)%mechanical%solid%normalstress(np),props(imat)%mechanical%solid%normale(np))
                        read(munit,*)props(imat)%mechanical%solid%normalstress
                        read(munit,*)props(imat)%mechanical%solid%normale
                    endif
                    material_select: select case(material)                       ! select 3
                    case('PLANE_LOWFT')

                        allocate(props(imat)%mechanical%solid%Plane_lowft)
                        allocate(props(imat)%mechanical%solid%Plane_lowft%point(2*(ndimn-1)),props(imat)%mechanical%solid%Plane_lowft%ft(ndimn-1) )
                        read(munit,*)props(imat)%mechanical%solid%Plane_lowft%point(:), &    !定义方向余弦的3个（2d）或4个（3d）点号
                            props(imat)%mechanical%solid%Plane_lowft%ft(:)       !定义平面内1个（2d）或2个方向（3d）抗拉强度

                    case('ELASTIC_ISOTROPIC')
                    case('ELASTIC_FRICTIONLESS')
                    case('ELASTIC_SPRING')
                        allocate(props(imat)%mechanical%solid%Elastic_Spring)
                        read(munit,*)props(imat)%mechanical%solid%Elastic_Spring%a,      &
                            props(imat)%mechanical%solid%Elastic_Spring%b,      &
                            props(imat)%mechanical%solid%Elastic_Spring%c,      &
                            props(imat)%mechanical%solid%Elastic_Spring%d,      &
                            props(imat)%mechanical%solid%Elastic_Spring%l0

                    case('ELASTIC_EP') !ep2010

                        allocate(props(imat)%mechanical%solid%ELASTIC_EP)
                        read(munit,*)np
                        props(imat)%mechanical%solid%ELASTIC_EP%np=np
                        allocate(props(imat)%mechanical%solid%ELASTIC_EP%p(np),props(imat)%mechanical%solid%ELASTIC_EP%Es(np))
                        props(imat)%mechanical%solid%ELASTIC_EP%p=0.
                        props(imat)%mechanical%solid%ELASTIC_EP%Es=0.
                        read(munit,*)props(imat)%mechanical%solid%ELASTIC_EP%p
                        read(munit,*)props(imat)%mechanical%solid%ELASTIC_EP%Es
                    case('STEEL_EP') !20211125

                        allocate(props(imat)%mechanical%solid%STEEL_EP)
                        read(munit,*)np,props(imat)%mechanical%solid%STEEL_EP%csigma
                        props(imat)%mechanical%solid%STEEL_EP%np=np
                        allocate(props(imat)%mechanical%solid%STEEL_EP%sig(np),props(imat)%mechanical%solid%STEEL_EP%Es(np))
                        props(imat)%mechanical%solid%STEEL_EP%sig=0.
                        props(imat)%mechanical%solid%STEEL_EP%Es=0.
                        read(munit,*)props(imat)%mechanical%solid%STEEL_EP%sig
                        read(munit,*)props(imat)%mechanical%solid%STEEL_EP%Es
                    case('STEEL_SP') !20211125

                        allocate(props(imat)%mechanical%solid%STEEL_SP)
                        allocate(props(imat)%mechanical%solid%STEEL_SP%kxyz(ndimn))
                        read(munit,*)props(imat)%mechanical%solid%STEEL_SP%kxyz,props(imat)%mechanical%solid%STEEL_SP%ktheta1,props(imat)%mechanical%solid%STEEL_SP%ktheta2

                    case('DUNCANCHANG')

                        allocate(props(imat)%mechanical%solid%DuncanChang)
                        read(munit,*)props(imat)%mechanical%solid%DuncanChang%model, &
                            props(imat)%mechanical%solid%DuncanChang%cohes, &
                            props(imat)%mechanical%solid%DuncanChang%phi,   &
                            props(imat)%mechanical%solid%DuncanChang%k,     &
                            props(imat)%mechanical%solid%DuncanChang%n,     &
                            props(imat)%mechanical%solid%DuncanChang%Rf,    &
                            props(imat)%mechanical%solid%DuncanChang%Nur,   &
                            props(imat)%mechanical%solid%DuncanChang%Kur,   &
                            props(imat)%mechanical%solid%DuncanChang%P0 ,   &
                            props(imat)%mechanical%solid%DuncanChang%Pa

                        if(type_problem=='F')then !2023215YL    !南科院沈珠江模型
                            read(munit,*)props(imat)%mechanical%solid%DuncanChang%k1,    &
                                props(imat)%mechanical%solid%DuncanChang%k2,    &
                                props(imat)%mechanical%solid%DuncanChang%nd, &
                                props(imat)%mechanical%solid%DuncanChang%lamdaMax
                        endif       !2023215YL

                        model=props(imat)%mechanical%solid%DuncanChang%model
                        if (model=='EV'.or.model=='CR') then
                            read(munit,*)props(imat)%mechanical%solid%DuncanChang%G,     &
                                props(imat)%mechanical%solid%DuncanChang%F,                  &
                                props(imat)%mechanical%solid%DuncanChang%Vtf
                        else if(model(1:2)=='EB') then
                            read(munit,*)props(imat)%mechanical%solid%DuncanChang%Kb,    &
                                props(imat)%mechanical%solid%DuncanChang%m,                  &
                                props(imat)%mechanical%solid%DuncanChang%dphi
                        endif

                        props(imat)%mechanical%solid%DuncanChang%phi_s  &
                            =props(imat)%mechanical%solid%DuncanChang%phi  !20220607

                        props(imat)%mechanical%solid%DuncanChang%k_s  &
                            =props(imat)%mechanical%solid%DuncanChang%k !20220607

                        if(kind_wt>0)then  !20220607
                            read(munit,*)props(imat)%mechanical%solid%DuncanChang%phi_s,   &
                                props(imat)%mechanical%solid%DuncanChang%k_s
                        endif
                        !  goodman
                    case('GOODMAN')

                        allocate(props(imat)%mechanical%solid%Goodman)
                        read(munit,*)model,props(imat)%mechanical%solid%Goodman%point1,  & !2007
                            props(imat)%mechanical%solid%Goodman%point2,                 &     !2007
                            props(imat)%mechanical%solid%Goodman%uniax_cohes,                  &     !2007
                            props(imat)%mechanical%solid%Goodman%frict_angle
                        props(imat)%mechanical%solid%Goodman%model=model
                        print *,'model=',model
                        if (model=='JANBU') then
                            read(munit,*)props(imat)%mechanical%solid%Goodman%K1,       &
                                props(imat)%mechanical%solid%Goodman%n,        &
                                props(imat)%mechanical%solid%Goodman%Kzz,      &
                                props(imat)%mechanical%solid%Goodman%Rf,       &
                                props(imat)%mechanical%solid%Goodman%phi,      &
                                props(imat)%mechanical%solid%Goodman%Kzx,      &
                                props(imat)%mechanical%solid%Goodman%pa,       &
                                props(imat)%mechanical%solid%Goodman%gamaw,    &
                                props(imat)%mechanical%solid%Goodman%cohes,    &
                                props(imat)%mechanical%solid%Goodman%Ft

                            if (ndimn==3)read(munit,*)props(imat)%mechanical%solid%Goodman%Kzy

                            !20231215_YL
                        elseif(model=='WATERTIGHT') then !20231007   !来源（抚宁报告，顾淦臣等《土石坝工程经验与创新》（p247））
                            allocate(props(imat)%mechanical%solid%Goodman%A(17))
                            read(munit,*)props(imat)%mechanical%solid%Goodman%IWJ,props(imat)%mechanical%solid%Goodman%fill
                            read(munit,*)props(imat)%mechanical%solid%Goodman%A
                            !20231215_YL
                        elseif (model=='EQUBOLT') then
                            read(munit,*)props(imat)%mechanical%solid%Goodman%K1,       &
                                props(imat)%mechanical%solid%Goodman%Kzz
                            !print *,'k1,kzz=',props(imat)%mechanical%solid%Goodman%K1,       &
                            !             props(imat)%mechanical%solid%Goodman%Kzz

                        elseif (model=='FCM') then !20210125
                            allocate(props(imat)%mechanical%solid%Goodman%fcmp)
                            allocate(props(imat)%mechanical%solid%Goodman%fcmp%kns0(ndimn))
                            read(munit,*)xlwmodel,Gf,ft


                            props(imat)%mechanical%solid%Goodman%fcmp%xlwmodel=xlwmodel
                            props(imat)%mechanical%solid%Goodman%fcmp%Gf=Gf
                            props(imat)%mechanical%solid%Goodman%fcmp%ft=ft

                            if(xlwmodel==1)then
                                w0=2.*Gf/ft
                                props(imat)%mechanical%solid%Goodman%fcmp%w0=w0
                            elseif(xlwmodel==2)then
                                ft1=ft/3.
                                w0=3.6*Gf/ft
                                w1=2.*w0/9.
                                props(imat)%mechanical%solid%Goodman%fcmp%w0=w0
                                props(imat)%mechanical%solid%Goodman%fcmp%w1=w1
                                props(imat)%mechanical%solid%Goodman%fcmp%ft1=ft1
                            elseif(xlwmodel==3)then
                                w0=209*1.e-6
                                props(imat)%mechanical%solid%Goodman%fcmp%w0=w0
                            elseif(xlwmodel==4)then
                                w0=5.618*Gf/ft
                                props(imat)%mechanical%solid%Goodman%fcmp%w0=w0
                            elseif(xlwmodel==5)then
                                read(munit,*)props(imat)%mechanical%solid%Goodman%fcmp%w0, &
                                    props(imat)%mechanical%solid%Goodman%fcmp%w1,      &
                                    props(imat)%mechanical%solid%Goodman%fcmp%w2,       &
                                    props(imat)%mechanical%solid%Goodman%fcmp%ft,      &
                                    props(imat)%mechanical%solid%Goodman%fcmp%ft1
                            endif
                            !read(munit,*)props(imat)%mechanical%solid%Goodman%fcmp%kns0
                            props(imat)%mechanical%solid%Goodman%fcmp%kns0(ndimn)=e*1.e3
                            props(imat)%mechanical%solid%Goodman%fcmp%kns0(1:ndimn-1)=e*1.e3/(2.*(1+nu))

                            !write(7,*)'imat=',imat,'kns0=',props(imat)%mechanical%solid%Goodman%fcmp%kns0
                        endif
                    case('CLASSICALEP')
                        allocate(props(imat)%mechanical%solid%ClassicalEP)
                        read(munit,*)props(imat)%mechanical%solid%ClassicalEP%criteria, &
                            props(imat)%mechanical%solid%ClassicalEP%sigma0,   &
                            props(imat)%mechanical%solid%ClassicalEP%hardening
                        criteria=props(imat)%mechanical%solid%ClassicalEP%criteria
                        if (criteria(1:2)=='MC'.or.criteria(1:2)=='DP')                      &
                            read(munit,*)props(imat)%mechanical%solid%ClassicalEP%frict_angle,   &
                            props(imat)%mechanical%solid%ClassicalEP%dilan_angle
                        if (kstab/=0.and.criteria=='MCJOINT') then

                            props(imat)%mechanical%solid%ClassicalEP%frict_angle_ini=props(imat)%mechanical%solid%ClassicalEP%frict_angle
                            props(imat)%mechanical%solid%ClassicalEP%dilan_angle_ini=props(imat)%mechanical%solid%ClassicalEP%dilan_angle
                            props(imat)%mechanical%solid%ClassicalEP%sigma0_ini=props(imat)%mechanical%solid%ClassicalEP%sigma0

                            frict=props(imat)%mechanical%solid%ClassicalEP%frict_angle
                            dilan=props(imat)%mechanical%solid%ClassicalEP%dilan_angle
                            frict=tand(frict)/kstab
                            dilan=tand(dilan)/kstab
                            frict=atand(frict)
                            dilan=atand(dilan)
                            sigma0=props(imat)%mechanical%solid%ClassicalEP%sigma0
                            sigma0=sigma0/kstab
                            props(imat)%mechanical%solid%ClassicalEP%frict_angle=frict
                            props(imat)%mechanical%solid%ClassicalEP%dilan_angle=dilan
                            props(imat)%mechanical%solid%ClassicalEP%sigma0=sigma0
                        endif
                        read(munit,*)props(imat)%mechanical%solid%ClassicalEP%csigma0
                        if (criteria(1:2)=='MC'.or.criteria(1:2)=='DP')                  &
                            read(munit,*)props(imat)%mechanical%solid%ClassicalEP%cfrict,    &
                            props(imat)%mechanical%solid%ClassicalEP%cdilan

                        if (criteria=='MCC'.or.criteria=='DPC'.or.criteria=='MCJOINT')   &
                            read(munit,*)props(imat)%mechanical%solid%ClassicalEP%ft,        &
                            props(imat)%mechanical%solid%ClassicalEP%cft,       &
                            props(imat)%mechanical%solid%ClassicalEP%sigmat,    &
                            props(imat)%mechanical%solid%ClassicalEP%csigmat
                    case('CAMCLAY')
                        allocate(props(imat)%mechanical%solid%CamClay)
                        read(munit,*)props(imat)%mechanical%solid%CamClay%Pc,           &
                            props(imat)%mechanical%solid%CamClay%lamda,        &
                            props(imat)%mechanical%solid%CamClay%Mg,           &
                            props(imat)%mechanical%solid%CamClay%Mf,           &
                            props(imat)%mechanical%solid%CamClay%D0,           &
                            props(imat)%mechanical%solid%CamClay%D1,           &
                            props(imat)%mechanical%solid%CamClay%gamma
                    case('CONCRETE')
                        allocate(props(imat)%mechanical%solid%Concrete)
                        read(munit,*)props(imat)%mechanical%solid%Concrete%A,           &
                            props(imat)%mechanical%solid%Concrete%B,           &
                            props(imat)%mechanical%solid%Concrete%C,           &
                            props(imat)%mechanical%solid%Concrete%D,           &
                            props(imat)%mechanical%solid%Concrete%Fc,          &
                            props(imat)%mechanical%solid%Concrete%Ct,          &
                            props(imat)%mechanical%solid%Concrete%Gf,          &
                            props(imat)%mechanical%solid%Concrete%h,           &
                            props(imat)%mechanical%solid%Concrete%icr         !new
                        icr= props(imat)%mechanical%solid%Concrete%icr
                        !if (icr==6)then !ltc 2013/11/24
                        !       read(munit,*)props(imat)%mechanical%solid%Concrete%et0,  &
                        !                    props(imat)%mechanical%solid%Concrete%at,  &
                        !                    props(imat)%mechanical%solid%Concrete%bt,  &
                        !                    props(imat)%mechanical%solid%Concrete%dt
                        !endif

                        if (icr==3.or.icr==5.or.icr==6)then !zhao09
                            fc=props(imat)%mechanical%solid%Concrete%Fc
                            ct=props(imat)%mechanical%solid%Concrete%Ct
                            ft=fc*Ct
                            x0=ft/e
                            gf=props(imat)%mechanical%solid%Concrete%Gf
                            h =props(imat)%mechanical%solid%Concrete%h
                            props(imat)%mechanical%solid%Concrete%bb=  &
                                3./(x0*(2.*gf*e/(h*ft**2)-1))
                            if(props(imat)%mechanical%solid%Concrete%bb<0.) & !zhao09 !!!!
                                props(imat)%mechanical%solid%Concrete%bb=0.
                            props(imat)%mechanical%solid%Concrete%et0=x0
                        endif

                        if (icr==2)then
                            read(munit,*)ft0,eft,at,bt,alfat
                            fc=props(imat)%mechanical%solid%Concrete%Fc
                            ct=props(imat)%mechanical%solid%Concrete%Ct
                            ft=fc*Ct
                            x0=ft0/(e*eft)
                            y0=ft0/ft
                            ci=e*eft/ft
                            c4=(1.-y0+.5*ci*(x0-1))/(2*x0**6-3*x0**5+3*x0-2)
                            c3=(.5*ci-3.*c4*(x0**5-1))/(x0-1)
                            c2=-2*c3-6*c4
                            c1=c3+5.*c4+1
                            props(imat)%mechanical%solid%Concrete%at=at
                            props(imat)%mechanical%solid%Concrete%bt=bt
                            props(imat)%mechanical%solid%Concrete%alfat=alfat
                            props(imat)%mechanical%solid%Concrete%t1=c1
                            props(imat)%mechanical%solid%Concrete%t2=c2
                            props(imat)%mechanical%solid%Concrete%t3=c3
                            props(imat)%mechanical%solid%Concrete%t4=c4
                            props(imat)%mechanical%solid%Concrete%ft0=ft0
                            props(imat)%mechanical%solid%Concrete%eft=eft

                            read(munit,*)fc0,efc,ac,bc,alfac
                            fc=props(imat)%mechanical%solid%Concrete%Fc
                            x0=fc0/(e*efc)
                            y0=fc0/fc
                            ci=e*efc/fc
                            c4=(2.-2.*y0+ci*(x0-1))/(x0**3-3*x0**2+3*x0-1)
                            c3=(.5*ci-1.5*c4*(x0**2-1))/(x0-1)
                            c2=-2*c3-3*c4
                            c1=c3+2.*c4+1
                            props(imat)%mechanical%solid%Concrete%ac=ac
                            props(imat)%mechanical%solid%Concrete%bc=bc
                            props(imat)%mechanical%solid%Concrete%alfac=alfac
                            props(imat)%mechanical%solid%Concrete%c1=c1
                            props(imat)%mechanical%solid%Concrete%c2=c2
                            props(imat)%mechanical%solid%Concrete%c3=c3
                            props(imat)%mechanical%solid%Concrete%c4=c4
                            props(imat)%mechanical%solid%Concrete%fc0=fc0
                            props(imat)%mechanical%solid%Concrete%efc=efc
                        endif
                    case('ClayPZ')
                        allocate(props(imat)%mechanical%solid%ClayPZ)
                        read(munit,*)text
                        read(munit,*)props(imat)%mechanical%solid%ClayPZ%ntest     !ntest
                        read(munit,*)text
                        read(munit,*)mg,alfag
                        read(munit,*)text
                        read(munit,*)Kevo,Keso,icels
                        read(munit,*)text
                        read(munit,*)beta0,beta1,expf
                        read(munit,*)text
                        read(munit,*)h0,extcr,pcut

                        props(imat)%mechanical%solid%ClayPZ%d(1)=kevo		!Kevo
                        props(imat)%mechanical%solid%ClayPZ%d(2)=keso		!Keso
                        props(imat)%mechanical%solid%ClayPZ%d(3)=mg			!Mg
                        props(imat)%mechanical%solid%ClayPZ%d(4)=alfag		!alfag
                        props(imat)%mechanical%solid%ClayPZ%d(5)=h0			!H0
                        props(imat)%mechanical%solid%ClayPZ%d(6)=expf		!expf
                        props(imat)%mechanical%solid%ClayPZ%d(7)=beta0		!beta0
                        props(imat)%mechanical%solid%ClayPZ%d(8)=beta1		!beta1
                        props(imat)%mechanical%solid%ClayPZ%d(9)=extcr		!nu
                        props(imat)%mechanical%solid%ClayPZ%d(10)=pcut		!pc0
                        props(imat)%mechanical%solid%ClayPZ%d(11)=icels     !icels (=o o cts, =1 o var.)


                        pzunit=64

                    case('SandPZ')
                        allocate(props(imat)%mechanical%solid%SandPZ)
                        props(imat)%mechanical%solid%SandPZ%d=0.0d0
                        props(imat)%mechanical%solid%SandPZ%humidification=0

                        read(munit,*)text
                        read(munit,*)props(imat)%mechanical%solid%SandPZ%ntest,pztype,humidification

                        read(munit,*)text
                        read(munit,*)mg,mf,alfag,alfaf

                        if(pztype==11)then   !PZ模型中的K、G用DC的参数来求
                            read(munit,*)text
                            allocate(props(imat)%mechanical%solid%DuncanChang)
                            read(munit,*)props(imat)%mechanical%solid%DuncanChang%model, &
                                props(imat)%mechanical%solid%DuncanChang%cohes, &
                                props(imat)%mechanical%solid%DuncanChang%phi,   &
                                props(imat)%mechanical%solid%DuncanChang%dphi,  &       !902
                                props(imat)%mechanical%solid%DuncanChang%k,     &
                                props(imat)%mechanical%solid%DuncanChang%n,     &
                                props(imat)%mechanical%solid%DuncanChang%Rf,    &
                                props(imat)%mechanical%solid%DuncanChang%Nur,   &
                                props(imat)%mechanical%solid%DuncanChang%Kur,   &
                                props(imat)%mechanical%solid%DuncanChang%P0 ,   &
                                props(imat)%mechanical%solid%DuncanChang%Pa

                            model=props(imat)%mechanical%solid%DuncanChang%model
                            if(model=='EV'.or.model=='CR') then
                                read(munit,*)props(imat)%mechanical%solid%DuncanChang%G,     &
                                    props(imat)%mechanical%solid%DuncanChang%F,     &
                                    props(imat)%mechanical%solid%DuncanChang%Vtf

                            else if(model=='EB') then
                                read(munit,*)props(imat)%mechanical%solid%DuncanChang%Kb,    &
                                    props(imat)%mechanical%solid%DuncanChang%m      !,     &  !902
                                !                                props(imat)%mechanical%solid%DuncanChang%dphi            !902
                            endif
                        else
                            read(munit,*)text
                            read(munit,*)Kevo,Keso,icels
                        endif
                        read(munit,*)text
                        read(munit,*)beta0,beta1,expf
                        read(munit,*)text
                        read(munit,*)h0,gama,hu0,gamau,pcut,extcr

                        if(abs(humidification)==2)then
                            !humidification=2 or -2 考虑静力时湿化
                            allocate(props(imat)%mechanical%solid%SandPZ%bline(abs(humidification)))
                            allocate(props(imat)%mechanical%solid%SandPZ%eline(abs(humidification)))
                            props(imat)%mechanical%solid%SandPZ%bline=0
                            props(imat)%mechanical%solid%SandPZ%eline=0
                            read(munit,*)text
                            read(munit,*)props(imat)%mechanical%solid%SandPZ%bline,    &
                                props(imat)%mechanical%solid%SandPZ%eline  !通过指定湿化曲线号考虑湿化
                            if(humidification==-2)read(munit,*)props(imat)%mechanical%solid%SandPZ%d(17),    &
                                props(imat)%mechanical%solid%SandPZ%d(18),    &
                                props(imat)%mechanical%solid%SandPZ%d(19),    &
                                props(imat)%mechanical%solid%SandPZ%d(20)    !cohes,phi,p0,pa
                        elseif(humidification==3)then
                            !humidification=3 动力时通过输入lamda和剪应力关系曲线求阻尼比
                            allocate(props(imat)%mechanical%solid%SandPZ%bline(abs(humidification)))
                            allocate(props(imat)%mechanical%solid%SandPZ%sigmad(abs(humidification)))
                            props(imat)%mechanical%solid%SandPZ%bline=0
                            props(imat)%mechanical%solid%SandPZ%sigmad=0.0d0
                            read(munit,*)text
                            read(munit,*)props(imat)%mechanical%solid%SandPZ%bline
                            read(munit,*)props(imat)%mechanical%solid%SandPZ%sigmad
                        endif

                        props(imat)%mechanical%solid%SandPZ%pztype=pztype
                        props(imat)%mechanical%solid%SandPZ%humidification=humidification
                        props(imat)%mechanical%solid%SandPZ%d(1)=kevo			!Kevo
                        props(imat)%mechanical%solid%SandPZ%d(2)=keso			!Keso
                        props(imat)%mechanical%solid%SandPZ%d(3)=mg				!Mg
                        props(imat)%mechanical%solid%SandPZ%d(4)=alfag			!alfag
                        props(imat)%mechanical%solid%SandPZ%d(5)=mf				!Mf
                        props(imat)%mechanical%solid%SandPZ%d(6)=alfaf			!alfaf
                        props(imat)%mechanical%solid%SandPZ%d(7)=h0				!H0
                        props(imat)%mechanical%solid%SandPZ%d(8)=pcut			!pcut
                        props(imat)%mechanical%solid%SandPZ%d(9)=beta0			!beta0
                        props(imat)%mechanical%solid%SandPZ%d(10)=beta1			!beta1
                        props(imat)%mechanical%solid%SandPZ%d(11)=gama			!gama
                        props(imat)%mechanical%solid%SandPZ%d(12)=hu0			!Hu0
                        props(imat)%mechanical%solid%SandPZ%d(13)=gamau			!gamau
                        props(imat)%mechanical%solid%SandPZ%d(14)=expf			!expf
                        props(imat)%mechanical%solid%SandPZ%d(15)=icels			!icels
                        props(imat)%mechanical%solid%SandPZ%d(16)=extcr			!extcr

                        pzunit=64


                    case('SoilPZ')
                        allocate(props(imat)%mechanical%solid%SoilPZ)
                        allocate(d(24))
                        !
                        !**** READ THE MODEL PARAMETERS
                        !
                        WRITE(chkunit,*)'ENTERING DEPMDL: MARK-III MODEL IN 3-D (ISOTROPIC)'
                        WRITE(chkunit,*)'M. PASTOR AND O.C. ZIENKIEWICZ'
                        WRITE(chkunit,*)'CONDENSED VERSION FOR STRAIN CONTROL ONLY'
                        WRITE(chkunit,*)'MODIFIED FOR FINITE ELEMENT PROGRAM USAGE '
                        !
                        !**** ETA=MG DEFINES THE ZERO-DILATANCY LINE WHERE FAILURE SHOULD
                        !     OCCUR. MG CAN BE DEFINED IN A MOHR-COULOMB FASHION USING
                        !     THE EXPRESSION MG=6SIN(PHIG)/(3-SIN(PHIG)*SIN(3*THETA))
                        !     MF IS USED TO DEFINE THE LOADING VECTOR AND ETAF WHERE
                        !     ETA SHOULD NEVER EXCEED
                        !     ALPHAF AND ALPHAG ARE USED TO DEFINE THE SHAPE OF THE ALPHA
                        !     SURFACES
                        !
                        WRITE(chkunit,*)'ntest'
                        READ(munit,*) text
                        READ(munit,*) ntest

                        write(chkunit,*)'ntest=',ntest
                        WRITE(chkunit,*)'XMGC,XMFC,ALFAF,ALFAG'
                        WRITE(chkunit,*)'XMGC=6*SIN(PHIG)/(3-SIN(PHIG))'
                        WRITE(chkunit,*)'XMFC WILL BEAR A FIXED RATIO WITH XMGC'
                        READ(munit,*) text
                        READ (munit,*)XMGC,XMFC,ALFAF,ALFAG
                        write(chkunit,*)XMGC,XMFC,ALFAF,ALFAG
                        PHIG=ASIN(3.0*XMGC/(6.0+XMGC))
                        PHIF=ASIN(3.0*XMFC/(6.0+XMFC))
                        !
                        write(chkunit,*)'MODIFIED ON 3/8/1986'
                        write(chkunit,*)'K=HEV0*P,G=HES0*P/3, ICELS: 0 BOTH VARIABLE'
                        write(chkunit,*)'                        1 HEV CONST, HES VAR'
                        write(chkunit,*)'                        2 HEV VAR, HES CONST'
                        write(chkunit,*)'                        3 BOTH CONSTANT'
                        READ(munit,*) text
                        READ (munit,*)HEV0,HES0,ICELS
                        write(chkunit,*)HEV0,HES0,ICELS
                        READ(munit,*) text
                        write(chkunit,*)'BETA0,BETA1,EXPF'
                        READ (munit,*)BETA0,BETA1,EXPF
                        write(chkunit,*)BETA0,BETA1,EXPF
                        !
                        write(chkunit,*)'NEW PARAMETER INCLUDED (PCUT) ON 7/2/87'
                        write(chkunit,*)'PCUT IS THE VALUE OF P0 WHEN LINEAR OPTION IS USED'
                        write(chkunit,*)'OR IN CALCULATION OF ELASTIC INITIAL MATRIX'
                        write(chkunit,*)'IF P0 IS LESS THAN PCUT'
                        write(chkunit,*)'H0,HU0,GAMHU,GAMDM,PCUT'
                        READ(munit,*) text
                        READ (munit,*)H0,HU0,GAMHU,GAMDM,PCUT
                        write(chkunit,*)H0,HU0,GAMHU,GAMDM,PCUT
                        !
                        D(1)=PHIG
                        D(2)=PHIF
                        D(3)=SIN(PHIG)
                        D(4)=SIN(PHIF)
                        D(5)=XMFC/XMGC
                        D(6)=ALFAF
                        D(7)=ALFAG
                        D(8)=PCUT
                        D(9)=HEV0
                        D(10)=HES0
                        D(12)=ICELS
                        D(13)=BETA0
                        D(14)=BETA1
                        D(15)=H0
                        D(16)=GAMDM
                        D(20)=HU0
                        D(21)=GAMHU
                        D(22)=XMGC
                        D(23)=XMFC
                        D(24)=EXPF
                        props(imat)%mechanical%solid%SoilPZ%d=d
                        props(imat)%mechanical%solid%SoilPZ%ntest=ntest
                        deallocate(d)
                        case default

                        print *, 'no such material'
                        call diag_unsupported(RD_MAT_material_set_material_header,jmat,'material',trim(material),'a material model name known to material_set')   ! M1-03 R20
                        call diag_flush_stage()

                    end select material_select

                case('FLUID')
                    allocate(props(imat)%mechanical%fluid)
                    read(munit,*)density,ratio,bulkw  !,cx
                    print *,'density,ratio,bulkw,c=',density,ratio,bulkw ,cx
                    props(imat)%mechanical%fluid%density  =density
                    props(imat)%mechanical%fluid%ratio    =ratio
                    props(imat)%mechanical%fluid%bulkw    =bulkw !ifs2006 zhao, 06/03/29
                    !props(imat)%mechanical%fluid%c        =cx
                    props(imat)%mechanical%fluid%c        =sqrt(bulkw/density)
                    !props(imat)%mechanical%fluid%bulkw    =density*cx**2
                    allocate(props(imat)%mechanical%fluid%permeability(ndimn))
                    read(munit,*)props(imat)%mechanical%fluid%iperm,props(imat)%mechanical%fluid%permeability(1:ndimn)


                    print *,'per=',props(imat)%mechanical%fluid%permeability(1:ndimn)

                    name=props(imat)%name

                    if (name(1:6)=='NSSoil') then
                        read(munit,*)ksmsa,bulks,bulkd

                        props(imat)%mechanical%fluid%ksmsa=ksmsa
                        props(imat)%mechanical%fluid%bulks=bulks
                        props(imat)%mechanical%fluid%bulkd=bulkd
                        if (ksmsa==1) then
                            read(munit,*)text
                            read(munit,*)nswpw,dpwats,npmpm,dpwatp
                            allocate(props(imat)%mechanical%fluid%swpwc(1:nswpw),        &
                                props(imat)%mechanical%fluid%pmpwc(1:npmpm),        &
                                props(imat)%mechanical%fluid%pwats(1:nswpw),        &
                                props(imat)%mechanical%fluid%pwatp(1:npmpm))
                            props(imat)%mechanical%fluid%nswpw=nswpw
                            props(imat)%mechanical%fluid%npmpm=npmpm
                            props(imat)%mechanical%fluid%dpwats=dpwats
                            props(imat)%mechanical%fluid%dpwatp=dpwatp
                            read(munit,*)props(imat)%mechanical%fluid%pwats(1:nswpw)
                            read(munit,*)props(imat)%mechanical%fluid%swpwc(1:nswpw)
                            read(munit,*)props(imat)%mechanical%fluid%pwatp(1:npmpm)
                            read(munit,*)props(imat)%mechanical%fluid%pmpwc(1:npmpm)
                        endif
                    endif

                    case default
                    print *, 'no such phase',phase
                    call diag_unsupported(RD_MAT_material_set_material_header,jmat,'phase',trim(phase),'SOLID | FLUID')   ! M1-03 R20
                    call diag_flush_stage()
                end select phase_select

            end do     !! for nphase
        case ('HEAT')   !20200221 modified from chengjing

            allocate(props(imat)%heat)
            allocate(props(imat)%heat%alfa(ndimn))
            read(munit,*)props(imat)%heat%alfa,  &
                props(imat)%heat%source_curve, &
                props(imat)%heat%place_curve,  &
                props(imat)%heat%pipe_cooling
            read(munit,*)props(imat)%heat%ialfa
            if(props(imat)%heat%pipe_cooling/=0)then   !pipe_cool
                read(munit,*)props(imat)%heat%water_curve,  &
                    props(imat)%heat%time_cooling,gap_cooling,eata,props(imat)%heat%bcooltime
                !b=(2.09-1.35*eata+.32*eata**2)*props(imat)%heat%alfa(1)/(gap_cooling**2)
                s=.971+.1485*eata-.0445*eata**2   !朱伯芳大体积混凝土P661上面的两个公式
                b=(2.08-1.174*eata+.256*eata**2)*(props(imat)%heat%alfa(1)/(gap_cooling**2))**s
                props(imat)%heat%b=b
                props(imat)%heat%s=s
            endif


        case ('GEOMETRY')
            allocate(props(imat)%geometry)

            read(munit,*)props(imat)%geometry%aera,  &
                props(imat)%geometry%J,     &
                props(imat)%geometry%Iy,    &
                props(imat)%geometry%Iz   !20200116


            case default
            print *, 'no such property',name
            call diag_unsupported(RD_MAT_material_set_material_header,jmat,'property',trim(property),'MECHANICAL | HEAT | GEOMETRY')   ! M1-03 R20
            call diag_flush_stage()
        end select property_select

    end do

    end subroutine material_set


    subroutine parameter_find(iscurve,strain,stress,hards)

    character(10)type_curve
    real   (irk) strain,strain1,strain2,stress,stress1,stress2,hards
    integer(ink) ipoint,npoints,iscurve

    npoints=scurves(iscurve)%npoints
    type_curve=scurves(iscurve)%type_curve


    if (type_curve=='LINEAR') then

        if (strain<scurves(iscurve)%strain_curve(1)) then
            stress=0.0
            hards=0.0
        else if(strain>=scurves(iscurve)%strain_curve(npoints)) then
            stress=scurves(iscurve)%stress_curve(npoints)
            hards=0.0
        else
            do ipoint=1,npoints-1
                strain1=scurves(iscurve)%strain_curve(ipoint)
                strain2=scurves(iscurve)%strain_curve(ipoint+1)
                stress=0.0
                if (strain>=strain1.and.strain<strain2) then
                    stress1=scurves(iscurve)%stress_curve(ipoint)
                    stress2=scurves(iscurve)%stress_curve(ipoint+1)
                    stress=stress1+(strain-strain1)/(strain2-strain1)*(stress2-stress1)
                    hards=(stress2-stress1)/(strain2-strain1)
                endif
            end do
        end if


    else
        print *, 'no type_curve'
        stop

    end if

    end subroutine parameter_find

    subroutine steel_spring_parameter !steel 2006

    character(100)text
    integer(ink) ielem,index,nnode,igroup,imats,inode,ipoin,jnode,nintf,idimn,itotv,xdimn,jdimn,jtotv,inift,mintf,kintf
    real   (irk) aera,dl
    real (irk),allocatable::dlpoint(:),a3(:)
    integer(ink),pointer::lnods(:)
    real   (irk),pointer::rotation(:,:)

    ! problem 1  - global , double (discret model)
    ! problem 2  - local  , double (discret model)
    ! problem 3  - local  , single (discret model)
    ! problem 4  - global , nrt    (embedded )
    ! problem 5  - local  , nrt
    !
    !
    !
    pnorm=0. ; prot=0. ; icpnorm=0 ; icpspring=0 !; lelenrt=0

    do idimn=1,ndimn
        prot(idimn,idimn,:)=1.0
    enddo

    !if(nlocalbeam==0)return


    allocate(dlpoint(npoin))
    dlpoint=0.

    do ielem=1,nelem
        index =element(ielem)%index
        if (index/=20.and.index/=1)cycle !增加钢筋为杆单元 2010.7.27 !barsteel
        nnode =elkn(index)%nnode
        igroup=element(ielem)%group
        if(appear(igroup)==0)cycle

        imats =matno_process(igroup,1)
        aera  =props(imats)%geometry%aera
        lnods=>element(ielem)%field(1)%lnods_f
        icpspring(lnods)=icpspring(lnods)+1


        allocate(a3(ndimn))
        dl=sqrt(sum((coord(:,lnods(2))-coord(:,lnods(1)))**2))
        a3(:)=(coord(:,lnods(2))-coord(:,lnods(1)))/dl
        do inode=1,nnode
            pnorm(:,lnods(inode))=pnorm(:,lnods(inode))+a3 !此处要求法向方向要保持一致才行。
        enddo
        dlpoint(lnods)=dlpoint(lnods)+sqrt(4.*aera*3.14159265)*dl/2.
        if (any(listglocbeam==igroup))icpnorm(lnods)=icpnorm(lnods)+1
        deallocate(a3)
        nullify(lnods)
    enddo

    do ipoin=1,npoin
        !write(7,*)'ipoin=',ipoin,'icpnorm=',icpnorm(ipoin)
        if (icpspring(ipoin)==0)cycle
        pnorm(:,ipoin)=pnorm(:,ipoin)/real(icpspring(ipoin))
        if(sqrt(sum(pnorm(:,ipoin)**2))<0.01)then
            write(*,*)'钢筋单元在此点附近法线方向不一致!，ipoin=',ipoin
            stop
        endif
        pnorm(:,ipoin)=pnorm(:,ipoin)/sqrt(sum(pnorm(:,ipoin)**2))
        call direct(pnorm(:,ipoin),prot(:,:,ipoin))
    enddo

    do ielem=1,nelem
        index =element(ielem)%index
        igroup=element(ielem)%group
        if(appear(igroup)==0)cycle
        if (index/=25)cycle
        nnode =elkn(index)%nnode
        lnods=>element(ielem)%field(1)%lnods_f
        do inode=1,nnode
            ipoin=lnods(inode)
            if (icpspring(ipoin)/=0)exit
        enddo
        element(ielem)%rotation=prot(:,:,ipoin)
        element(ielem)%area    =dlpoint(ipoin)
        nullify(lnods)
    enddo
    deallocate(dlpoint)

    !int2000 !for steel 20006

    if(doubsig==2)return

    do ielem=1,nelem
        index =element(ielem)%index
        igroup=element(ielem)%group
        if(appear(igroup)==0)cycle
        if (index/=25)cycle
        nnode =elkn(index)%nnode
        lnods   =>element(ielem)%field(1)%lnods_f
        rotation=>element(ielem)%rotation
        do inode=1,nnode
            ipoin=lnods(inode)
            if (icpnorm(ipoin)/=0)exit
            !if (icpspring (ipoin)/=0)exit
        enddo
        if (inode==1)jnode=2
        if (inode==2)jnode=1
        if (inode/=1.and.inode/=2)cycle
        nintf=ndimn
        xdimn=2
        !if(all(lelenrt/=ielem).and.ktan1>0.01)cycle
        if (any(lelenrt==ielem))xdimn=1
        do idimn=xdimn,ndimn
            if (lmdofn(idimn)==0)cycle
            itotv=nodfn(lmdofn(idimn),lnods(inode))
            if (associated(trans(itotv)%listf))then
                nullify(trans(itotv)%listf,trans(itotv)%rintf)
            endif
            !allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
            !trans(itotv)%listf=nodfn(lmdofn(1:ndimn),lnods(jnode))
            !trans(itotv)%rintf=rotation(idimn,:)
            !trans(itotv)%nintf=nintf

            !new
            kintf=0
            do jdimn=1,ndimn
                jtotv=nodfn(lmdofn(jdimn),lnods(jnode))
                mintf=trans(jtotv)%nintf
                do inift=1,mintf
                    nintf=nintf+1
                enddo
                if(mintf>0)kintf=kintf+1
            enddo
            allocate(trans(itotv)%listf(nintf-kintf),trans(itotv)%rintf(nintf-kintf))
            nintf=0
            do jdimn=1,ndimn
                jtotv=nodfn(lmdofn(jdimn),lnods(jnode))
                mintf=trans(jtotv)%nintf
                if (mintf==0)then
                    nintf=nintf+1
                    trans(itotv)%listf(nintf:nintf)=nodfn(lmdofn(jdimn),lnods(jnode))
                    trans(itotv)%rintf(nintf:nintf)=rotation(idimn,jdimn)
                elseif(mintf>0)then
                    do inift=1,mintf
                        nintf=nintf+1
                        trans(itotv)%listf(nintf:nintf)=trans(jtotv)%listf(inift)
                        trans(itotv)%rintf(nintf:nintf)=trans(jtotv)%rintf(inift)*rotation(idimn,jdimn)
                    enddo
                endif
                trans(itotv)%nintf=nintf
                !trans(jtotv)%nintf=0
            enddo
            !endnew
        enddo
        nullify(lnods,rotation)
    enddo

    contains

    subroutine direct(a3,r)
    real   (irk) xx,r(:,:),a3(:)
    real   (irk),allocatable::a30(:)

    r(1,:)=a3
    if (ndimn.eq.2) then
        r(2,1)=-r(1,2)
        r(2,2)=r(1,1)

        return
    endif
    allocate(a30(ndimn))
    a30=a3

    xx=a3(1)**2+a3(3)**2
    !!X,Y,Z ---global axis, x,y,z--local axis
    !!x is the axial direction of the bar
    !!    if x/=Y, z=x*Y, y=z*x
    !!    if x=Y,  z=x*Z, y=z*x
    if (xx.gt..001) then
        r(3,1)=-a3(3)
        r(3,2)=0.
        r(3,3)=a3(1)
    else
        r(3,1)=a3(2)
        r(3,2)=-a3(1)
        r(3,3)=0.
    endif
    a3=r(3,:)**2
    xx=sqrt(sum(a3))
    r(3,:)=r(3,:)/xx
    r(2,1)=r(3,2)*r(1,3)-r(3,3)*r(1,2)
    r(2,2)=r(3,3)*r(1,1)-r(3,1)*r(1,3)
    r(2,3)=r(3,1)*r(1,2)-r(3,2)*r(1,1)
    a3=r(2,:)**2
    xx=sqrt(sum(a3))
    r(2,:)=r(2,:)/xx
    a3=a30
    end subroutine direct

    end subroutine steel_spring_parameter

    !steel 2010

    subroutine steel_bond_slip_relation(icx,sx,ks,tao,ft,fc,d,stra,coef)
    integer(ink) icx
    real   (irk) sx,ks,tao,ft,fc,d,stra,coef,taou

    sx=1000*sx
    if (icx<0)then
        ks=1.0*10**(-1.*icx)
        tao=ks*sx
    elseif(icx>99)then
        ks=real(icx)
        tao=ks*sx
    elseif(icx==1)then
        !Nilson
        Tao=9.78e2*sx-5.72e4*sx*sx+0.836e6*sx*sx*sx
        ks=9.78e2-5.72e4*2.*sx+0.836e6*3.*sx*sx

    elseif(icx==2)then
        !Houde and Mirza
        Tao=5.3e2*sx-2.52e4*sx*sx+5.87e5*sx*sx*sx-5.47e6*sx*sx*sx*sx
        ks=5.3e2-2.52e4*2*sx+5.87e5*3*sx*sx-5.47e6*4*sx*sx*sx
        if(abs(fc)>0.01)then
            Tao=tao*sqrt(fc/coef/40.7)
            ks=ks*sqrt(fc/coef/40.7)
        endif
    elseif(icx==3)then
        !狄林生
        Tao=6.59e2*sx-2.13e4*sx*sx+0.22e6*sx*sx*sx
        ks=6.59e2-2.13e4*2*sx+0.22e6*3*sx*sx
    elseif(icx==4)then
        !Shima
        if(abs(fc)<0.01)fc=21.6
        if(abs(d)<0.01)D=19.
        Tao=0.73*FC*(log(1+5000*sx/D))**3/(1.0+1.0e5*abs(stra))
        ks=0.73*FC*3.*(log(1+5000*sx/D))**2*(1./(Sx+D/5000))/(1.0+1.0e5*abs(stra))
    elseif(icx==5)then
        !汪基伟对Houde的改进，下降段采用双直线
        fc=17.e6
        if(sx<=0.03)then
            Tao=5.3e2*sx-2.52e4*sx*sx+5.87e5*sx*sx*sx-5.47e6*sx*sx*sx*sx
            ks=5.3e2-2.52e4*2*sx+5.87e5*3*sx*sx-5.47e6*4*sx*sx*sx
            if(abs(fc)>0.01)then
                Tao=tao*sqrt(fc/coef/40.7)
                ks=ks*sqrt(fc/coef/40.7)
            endif
        elseif(sx>0.03.and.sx<=0.05)then
            Taou=4.6383
            if(abs(fc)>0.01)Taou=Taou*sqrt(fc/coef/40.7)
            tao=taou+(sx-0.03)/(0.05-0.03)*(0.2*taou-taou)
            ks=-40.*taou
        elseif(sx>0.05)then
            Taou=4.6383
            if(abs(fc)>0.01)Taou=Taou*sqrt(fc/coef/40.7)
            tao=0.2*taou
            ks=0.
        endif
    else
        !
        write(*,*)'ikinds=',icx
        stop 'stop for ikind for steel!'

    endif

    ks=ks*coef*1000.
    tao=tao*coef


    end subroutine steel_bond_slip_relation

    subroutine get_humidification(bline,eline,curconfining,curSLevel,dfact)
    integer(ink) iline,iscurve1,iscurve2,bline,eline !begin and end curve number of humidification
    real   (irk) curconfining,confining1,confining2,coef1,coef2,dfact,dfact1,dfact2,curSLevel,hards

    dfact1=0.0d0;dfact2=0.0d0;iscurve1=0;iscurve2=0
    confining1=scurves(bline)%confining
    confining2=scurves(eline)%confining

    if(curconfining<=confining1)then
        iscurve1=bline;iscurve2=0
        coef1=1.0d0;coef2=0.0d0
    elseif(curconfining>=confining2)then
        iscurve1=0;iscurve2=eline
        coef1=0.0d0;coef2=1.0d0
    else
        do iline=bline,eline-1
            confining1=scurves(iline)%confining
            confining2=scurves(iline+1)%confining
            if(curconfining>confining1.and.curconfining<=confining2)then
                coef1=(confining2-curconfining)/(confining2-confining1)
                coef2=1.d0-coef1
                iscurve1=iline
                iscurve2=iline+1
                exit
            endif
        end do
    endif

    if(iscurve1/=0)call parameter_find(iscurve1,curSLevel,dfact1,hards)
    if(iscurve2/=0)call parameter_find(iscurve2,curSLevel,dfact2,hards)
    dfact=coef1*dfact1+coef2*dfact2

    end subroutine get_humidification


    end module materials
