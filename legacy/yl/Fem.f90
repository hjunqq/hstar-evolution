    include 'mkl_rci.f90'


    PROGRAM FEM90

    !                 M. PASTOR, TONCHUN LI AND P. MIRA
    !                          May, 1997
    !                      All rights reserved.

    use yl_state_serializer, only: yl_state_dump

    use yl_diag
    use yl_diag_registry
    use variable_types
    use elements
    use global_var
    use materials
    use prescribed
    use applied_load
    use stiffness_matrix
    use internal_force
    use solver
    use output
    use temperature
    use meshfine
    !use portlib ! for what?
    use levelset !levelset
    use MKL_RCI  !20190810
    use MKL_RCI_TYPE !20190810
    use vsl_gauss_module
    !use  EXAMPLEDTRNLSP


    implicit none

    !EXTERNAL  measure_computation  !20190810

    type beta_resultm
        real(irk),pointer:: ga(:)
        real(irk) beta
    end type beta_resultm

    type(beta_resultm),allocatable::betas(:)

    !20190810
    !** N - NUMBER OF FUNCTION VARIABLES
    !integer             Npara,Mvalue,Nblks_pb,mobstimes,Npoints_pb,RCI_REQUEST,res !20210803
    integer             RCI_REQUEST,res !20210803

    integer             nback_point,nstoch,istoch,tbstep     !20200812
    integer             ie,ig,nel_sub,npoin_sub,ngroup_sub   !20230407
    integer,allocatable :: list_nel_sub(:),icpoin_sub(:),listpoin_sub(:),listgroup_sub(:),list_group_sub(:) !20230407
    integer,allocatable :: icgroup(:)
    real(irk),allocatable::coord_sub(:,:)


    !** SOLUTION VECTOR. CONTAINS VALUES X FOR F(X)
    !double precision,allocatable::Xvalue(:)  在global中定义
    !** PRECISIONS FOR STOP-CRITERIA (SEE MANUAL FOR MORE DETAILS)
    double precision    EPS (6),JAC_EPS
    double precision,allocatable:: FVEC (:),FJAC (:, :) ,Fvec1(:),Fvec2(:), &
        value_vc(:,:,:),fjac22(:,:,:)  !20220108
    !** NUMBER OF ITERATIONS
    integer             ITER
    !** NUMBER OF STOP-CRITERION
    integer             ST_CR,INFO(6)
    !** CONTROLS OF RCI CYCLE
    integer             SUCCESSFUL
    !** MAXIMUM NUMBER OF ITERATIONS
    integer             ITER1
    !** MAXIMUM NUMBER OF ITERATIONS OF CALCULATION OF TRIAL-STEP
    integer             ITER2
    !** INITIAL STEP BOUND
    double precision    RS
    !** INITIAL AND FINAL RESIDUALS
    double precision    R1, R2
    !** TR SOLVER HANDLE
    TYPE(HANDLE_TR) :: HANDLE



    !interface default

    !module procedure global_data, prescrib_set, material_set,      &
    !                 external_load, stiff_u, hmatrx, mcmatrx,      &
    !         upwcouple, estif_assemble, couple_assemble,    &
    !         residu_f, eload_field, eload_couple, solve

    !end interface




    call diag_set_mode_from_argv()
    if (yl_input_enabled) call yl_modern_prelude(); if (.not. yl_input_enabled) open(inpunit,file='inp',status='old',iostat=yl_ios,iomsg=yl_msg)
    if (.not. yl_input_enabled) call diag_check_open(yl_ios,yl_msg,'inp','inpunit','Fem.f90:95')
    if (.not. yl_input_enabled) read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) text
    if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_INP_FEM90_title_1,0)
    if (.not. yl_input_enabled) read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) restart,relis,sysrelis,ADINA,Uopt_R,gamamax !20231215YL
    if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_INP_FEM90_run_control,0)
    if (.not. yl_input_enabled) read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) text
    if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_INP_FEM90_title_2,0)
    if (.not. yl_input_enabled) read (inpunit,*,iostat=yl_ios,iomsg=yl_msg) probn
    if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_INP_FEM90_problem_name,0)
    !	adina=0

    !mystatus=0
    !CALL GETARG (1, probn,mystatus(1))
    !CALL GETARG (2, t2,mystatus(2))
    !CALL GETARG (3, t3,mystatus(3))
    !if(mystatus(2)>0)read(t2,*)restart
    !if(mystatus(3)>0)read(t3,*)Runblks
    call TIME(char_time)
    print *, 'time: ', char_time
    write(chkunit,*)'time: ', char_time
    ! analysis process
    call global_data ! set the global data, they will be unchanged in the whole


    if(Uopt_R==1)then  !20210502
        read(vcor_unit,*)text
        read(vcor_unit,*)radiusi,vdirect,centerR(1:2)

        read(vcor_unit,*)text
        read(vcor_unit,*)nvarp_U
        !write(7,*)text,nvarp_U
        allocate(varplist_U(2,nvarp_U))
        do i0=1,nvarp_U
            read(vcor_unit,*)varplist_U(:,i0)
            !write(7,*)i0,varplist_U(:,i0)
        end do
        read(vcor_unit,*)text
        read(vcor_unit,*)nintp_U
        !write(7,*)text,nintp_U
        allocate(intplist_U(3,nvarp_U),rintf_U(2,nvarp_U))
        do i0=1,nintp_U
            read(vcor_unit,*)intplist_U(:,i0)
            !write(7,*)i0,intplist_U(:,i0)
            read(vcor_unit,*)rintf_U(:,i0)
            !write(7,*)rintf_U(:,i0)
        end do
        call modify_coord

    endif   !20210502

    !call vsl_gauss_gen()

    !call MKL_VSL_TEST

    !stop


    len1=len_trim(probn)


    !if (outintr.gt.0) then
    !   open(outint,file=probn(1:len1)//'.oit',RECL=npoin*irk,FORM='BINARY',ACCESS='DIRECT')
    !elseif(outintw.gt.0.and.restart/=0)then
    !   open(outint,file=probn(1:len1)//'.oit',FORM='BINARY',ACCESS='append')
    !elseif(outintw.gt.0.and.restart==0)then
    !   open(outint,file=probn(1:len1)//'.oit',FORM='BINARY')
    !endif

    if(type_problem=='Q')then   !20200220
        if(outintr>0) then
            open(outint,file=probn(1:len1)//'.oit',RECL=npoin*irk,FORM='BINARY',ACCESS='DIRECT')
            !elseif(outintw>0)then   !20230402
            !    open(outint,file=probn(1:len1)//'.oit',RECL=npoin*irk,FORM='BINARY')
        endif
    else
        if(outintw>0.and.restart/=0) then  !20230402
            open(outint,file=probn(1:len1)//'.oit',FORM='BINARY', &
                ACCESS='append')
        elseif(outintw>0.and.restart==0) then
            open(outint,file=probn(1:len1)//'.oit',FORM='BINARY')
        endif
    endif

    if(upliftin/=0) &        !20220409
        open(upliftunit,file=probn(1:len1)//'.upf',FORM='BINARY') !20220625

    print *,'nblks=',nblks
    print *,'Input runblks, =?'
    !read *,runblks
    if (.not. yl_adapter_mode) read (inpunit,*,iostat=yl_ios,iomsg=yl_msg)runblks
    if (.not. yl_adapter_mode) call diag_check_read(yl_ios,yl_msg,RD_INP_FEM90_runblks,0)
    call TIME(char_time)
    print *, 'time: ', char_time
    write(chkunit,*)'time: ', char_time
    ! material set
    if (.not. yl_adapter_mode) call material_set
    ! modify the element libary
    call modf_element_lib  !20221124

    if (.not. yl_adapter_mode) call contact_point_to_point  !!ctt2005

    if (.not. yl_adapter_mode) call link_concrete_and_steel  !20210328
    if (.not. yl_adapter_mode) call link_concrete_and_water_pipe !20210411



    !  write(7,*)'ntotv=',ntotv,'nodfn='
    !do ipoin=1,npoin
    !write(7,1992)ipoin,nodfn(:,ipoin)
    !end do

    !call steel_spring_parameter  !!steel 2006
    ! stiffness for interface of Fluid and solid, absorbing boundary
    if (.not. yl_adapter_mode) call stiff_interface_fluid_solid    !!ifs2000
    if (.not. yl_adapter_mode) call stiff_absorb_fluid             !!ifs2000
    if (.not. yl_adapter_mode) call stiff_absorb_solid             !!ifs2000
    if (.not. yl_adapter_mode) call stiff_ifs2006                  !!ifs2006 zhao, 06/03/29

    allocate(toler_var(mdofn))
    if (.not. yl_adapter_mode) call output_read  !20210803
    iwriten=0
    trstep=0

    if (.not. yl_adapter_mode) allocate(result_zero(ntotv)) ; result_zero=0.
    if(upliftin/=0)allocate(uplift_node(npoin))
    if(outind==-1)  allocate(accq(ndimn,npoin))  !20231113

    if(nbackf/=0)then
        allocate(result_zero_g(ntotv)) ; result_zero_g=0.   !20210706
        allocate(result_zero_e(ntotv)) ; result_zero_e=0.   !20210706
    endif
    if(type_problem/='Q'.and.type_problem/='E')allocate(result_first(ntotv))
    if(type_problem=='F')allocate(result_second(ntotv))
    !result_zero=0.0
    if(allocated(result_first))result_first=0.0
    if(allocated(result_second))result_second=0.0
    if(allocated(torel))               torel=0.0
    if(allocated(toforl))              toforl=0.0
    if(nflow/=0)then
        allocate(flowrate(npoin))
        flowrate=0.
    endif

    if (type_problem/='W')then !freq2006
        if(allocated(tofor))deallocate(tofor,stfor,toforl,toform,delitfi,deltafi) !,deltafi_ssorpbcg)
        if(allocated(torel))deallocate(torel)
        if(allocated(floae))deallocate(fmass,floae,floai,fexta)
        allocate(tofor(ntotv),stfor(ntotv),toforl(ntotv),toform(ntotv))
        tofor=0. ; stfor=0. ; toforl=0. ; toform=0.
        if(ninit/=0.and.kinit==2) allocate(torel(ntotv)) ; torel=0.  !20201121
        allocate(delitfi(ntotv),deltafi(ntotv)) !,deltafi_ssorpbcg(ntotv)) !ssorpbcg
    else
        if(allocated(toforw))deallocate(toforw,stforw)
        allocate(toforw(ntotv),stforw(ntotv))
        if(allocated(tofor))deallocate(delitfi,deltafi)
        !allocate(delitfi(ntotv),deltafi(ntotv))
    endif

    if (any(props(:)%name=='NSTOKS')) then
        allocate(fmass(ntotv),floae(ntotv),floai(ntotv),fexta(ntotv))
    endif


    if (.not. yl_adapter_mode) allocate(ice0(nelem))
    if (.not. yl_adapter_mode) ice0=0

    call gid_output_parameter !only for check


    if (any(props(:)%name=='NSTOKS')) then
        allocate(fmass(ntotv),floae(ntotv),floai(ntotv),fexta(ntotv))
        fmass=0.
        floai=0.
        floae=0.
        fexta=0.
    endif

    if (.not. yl_adapter_mode) allocate(line_load_block(nblks),line_temp_block(nblks))   !!rrr
    line_load_block=0
    line_temp_block=0
    nincs=0
    if (restart==0)then
        lblks=0
        lttime=0.0
        lincs=0
    else
        ninit=0
        call resta_read_write(1)
        !!special for sanxia
        if(outintr>0.and.(lblks==outintr-1))lttime=0.   !20200226
        !!end special for sanxia
        if (restart==2)then
            appear(1:ngroup)=appear_process(1:ngroup,lblks)
            call local_stress
            !if (kstab==0.)then !zhao 2010
            if(nforce/=0.or.ngaps/=0)call force_interface
            if((nforce/=0.or.ngaps/=0).and.nextrf==0)call write_force_interface
            !else
            if(kstab/=0.)call safety_factor
            !end if
            call out_full_write
            if(outplot(1:3)=='GID')   call OUT_GID_WRITE
            if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            call diag_exit(EXIT_OK)   ! M1-03 R20: restart output written, normal end
        endif
        do iblks=1,lblks
            read(mainunit,*)text
            read(mainunit,*)nincs
            do iincs=1,nincs
                read(mainunit,*) i0
                read(mainunit,*) f0
            end do
        end do
    end if !if (restart==0)then

    ttime=lttime
    blks_new=lblks+1
    write(*,*)'lblks=',lblks,' blks_new=',blks_new
    incs_new=1
    write(*,*)'lincs=',lincs,' nincs=',nincs
    if (lincs<nincs) then
        incs_new=lincs+1
        blks_new=lblks
    endif
    lineload=0
    write(*,*)'lblks=',lblks,' blks_new=',blks_new
    if(blks_new/=1)lineload=line_load_block(blks_new-1)
    linet=0
    if(blks_new/=1)linet   =line_temp_block(blks_new-1)

    rewind(mainunit)

    do iblks=1,blks_new-1
        read(mainunit,*)text
        read(mainunit,*)nincs
        do iincs=1,nincs
            read(mainunit,*) i0
            read(mainunit,*) f0
        end do
    end do
    lblks=blks_new-1
    lincs=incs_new-1

    print *,'Bparameter=',Bparameter


    if(Bparameter==-1.or.Bparameter==-2)then  !20231030
        call  parameter_back_analysis_verify_read
        call  parameter_back_analysis_verify

    else if((Bparameter>0.and.Bparameter<=2).and.balgor<=1)then
        call parameter_back_analysis_read
        call observe_back_analysis_read
        call parameter_back_analysis(Npara,Mvalue)

    else if((Bparameter>0.and.Bparameter<=2).and.balgor==2)then
        call trust_region_back_analysis_read
        call observe_back_analysis_read
        call trust_region_back_analysis(Npara,Mvalue)
    else if(Bparameter==3)then

        call matrix_rigid_dis
        call observe_back_analysis_read
        call rigid_dis_back_analysis
        call diag_exit(EXIT_OK)   ! M1-03 R20: back analysis done, normal end
    else if(Bparameter==4)then

        call matrix_nodal_value
        call observe_back_analysis_read

        call nodal_value_back_analysis
        call diag_exit(EXIT_OK)   ! M1-03 R20: back analysis done, normal end
    else
        if(nbackdT==2) &     !20230216
            call observe_back_analysis_read
        call process_analysis
    endif

    if(submodel<0) then  !20230407
        write(chkunit,*)'npoin_L,nelem_L,ngroup_L,nstep'
        write(chkunit,*)'ires_u, ires_rot,ires_v, ires_a, ires_T, ires_Tv, ires_P, ires_Pv, ires_Pa'
        write(chkunit,*)'nelgp'

        write(chkunit,1992) npoin,nelem,ngroup,nstep,miter
        write(chkunit,992) res_u,res_rot,res_v, res_a, res_T, res_Tv, res_P, res_Pv, res_Pa
        write(chkunit,1992)group(1:ngroup)%nelgroup


        if(submodel==-1)then
            print *,'input total groups or elements for submodel analysis: ngroup_sub,nel_sub'
            !输入子模型分析的组数或单元数：ngroup_sub,nel_sub
            read *, ngroup_sub,nel_sub
            if(ngroup_sub==0.and.nel_sub==0) goto 11


            if(ngroup_sub/=0)then
                allocate(list_group_sub(ngroup_sub))
                print *,'input list of groups for submodel analysis list_ngroup_sub='
                read *,list_group_sub

                allocate(listgroup_sub(ngroup))
                listgroup_sub=0
                do ig=1,ngroup_sub
                    igroup=list_group_sub(ig)
                    listgroup_sub(igroup)=ig
                end do

                nel_sub=0
                do ig=1,ngroup_sub
                    igroup=list_group_sub(ig)
                    nel_sub=nel_sub+group(igroup)%nelgroup
                end do
                allocate(list_nel_sub(nel_sub))

                nel_sub=0
                do ig=1,ngroup_sub
                    igroup=list_group_sub(ig)
                    do ie=1,group(igroup)%nelgroup
                        ielem=group(igroup)%list(ie)
                        nel_sub=nel_sub+1
                        list_nel_sub(nel_sub)=ielem
                    end do
                end do

                deallocate(list_group_sub)

            elseif(nel_sub/=0)then

                allocate(list_nel_sub(nel_sub))
                print *,'input list of element numbers for  submodel analysis list_nel_sub='
                read *,list_nel_sub
                allocate(icgroup(ngroup))

                icgroup=0
                do ie=1,nel_sub
                    ielem=list_nel_sub(ie)
                    icgroup(element(ielem)%group)=1
                end do
                ngroup_sub=sum(icgroup)

                allocate(listgroup_sub(ngroup))

                ngroup_sub=0
                do ig=1,ngroup
                    if(icgroup(ig)==0)cycle
                    ngroup_sub=ngroup_sub+1
                    listgroup_sub(ig)=ngroup_sub
                end do

                deallocate(icgroup)
            endif

            write(chkunit,*)'ngroup_sub=',ngroup_sub,'nel_sub=',nel_sub

            allocate(icpoin_sub(npoin),listpoin_sub(npoin))
            icpoin_sub=0
            listpoin_sub=0
            do ie=1,nel_sub
                ielem=list_nel_sub(ie)
                lnods=>element(ielem)%field(1)%lnods_f
                icpoin_sub(lnods)=1
                nullify(lnods)
            end do
            npoin_sub=sum(icpoin_sub)
            allocate(coord_sub(ndimn,npoin_sub))
            npoin_sub=0
            do ipoin=1,npoin
                if(icpoin_sub(ipoin)==0)cycle
                npoin_sub=npoin_sub+1
                coord_sub(:,npoin_sub)=coord(:,ipoin)
                listpoin_sub(ipoin)=npoin_sub
            end do

            write(sub_msh_unit,*)'NODES INFORMATION'
            do ipoin=1,npoin_sub
                write(sub_msh_unit,1991)ipoin,coord_sub(:,ipoin)
            end do
            write(sub_msh_unit,*)'ELEMENTS INFORMATION'
            do ie=1,nel_sub
                ielem=list_nel_sub(ie)
                ig=element(ielem)%group
                igroup=listgroup_sub(ig)
                lnods=>element(ielem)%field(1)%lnods_f
                write(sub_msh_unit,1992)ie,size(lnods),listpoin_sub(lnods),igroup
                nullify(lnods)
            end do

            deallocate(list_nel_sub,coord_sub,icpoin_sub,listpoin_sub,listgroup_sub)

        endif
    endif !20230407

11  call out_record_write   !20230407

    if (rmesh<0)then
        rewind(out_msh)
        write(out_msh,*)'mesh dimension = 3 elemtype quadrilateral nnode = 4'
        write(out_msh,*)'coordinates'
        do ipoin=1,npoin
            write(out_msh,1991)ipoin,coord(:,ipoin)
        end do
        write(out_msh,*)'end coordinates'
        write(out_msh,*)'elements'
        tnegid=0
        do igroup=1,ngroup
            if (appear(igroup)==1)then
                do ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (ice0(ielem)==0)then
                        tnegid=tnegid+1
                        write(out_msh,1992)tnegid,element(ielem)%field(1)%lnods_f,igroup
                    endif
                enddo
            endif
        enddo

        if (nelem1>0)then
            do igroup=1,ngroup
                if (appear(igroup)==1)then
                    DO ielgroup = 1,group1(igroup)%nelgroup
                        ielem = group1(igroup)%list(ielgroup)
                        if (jce1(ielem)==0)then
                            tnegid=tnegid+1
                            write(out_msh,1992)tnegid,element1(ielem)%field(1)%lnods_f,igroup+ngroup
                        endif
                    end do
                endif
            enddo
        endif

        if (nelem2>0)then
            do igroup=1,ngroup
                if (appear(igroup)==1)then
                    DO ielgroup = 1,group2(igroup)%nelgroup
                        ielem = group2(igroup)%list(ielgroup)
                        tnegid=tnegid+1
                        write(out_msh,992)tnegid,element2(ielem)%field(1)%lnods_f,igroup+2*ngroup
                    end do
                endif
            enddo
        endif
        write(out_msh,*)'end elements'
    endif

1991 format(i10,3e15.3)
1992 format(i10,10i10)
992 format(20i5)

    if(outplot=='GIDL')then
        call GID_CLOSEPOSTRESULTFILE
    endif

    call TIME(char_time)
    print *, 'time: ', char_time
    write(chkunit,*)'time: ', char_time

    contains

    subroutine modify_coord  !20210502
    integer i1,i2,i0,ipoin,idk,ipoin1,ipoin2
    real(irk) radius0,xy0(2),xyi(2),f1,f2,alfa0

    if(vdirect/=3)then
        i1=1;i2=2
    else
        i1=2;i2=3
    endif

    do i0=1,nvarp_U
        ipoin=varplist_U(1,i0)
        idk=varplist_U(2,i0)
        if(idk==0)cycle
        if(idk==1)then
            coord(i1,ipoin)=sign(radiusi,coord(i1,ipoin))
        else if(idk==2)then
            xy0(1)=coord(i1,ipoin)-centerR(1)
            xy0(2)=coord(i2,ipoin)-centerR(2)
            radius0=sum(xy0**2)
            radius0=sqrt(radius0)
            alfa0=acos(xy0(1)/radius0)
            xyi(1)=radiusi*cos(alfa0);xyi(2)=-radiusi*sin(alfa0)
            xyi=xyi+centerR
            coord(i1,ipoin)=xyi(1)
            coord(i2,ipoin)=xyi(2)
        endif
    end do

    do i0=1,nintp_U
        ipoin=intplist_U(1,i0)
        ipoin1=intplist_U(2,i0)
        ipoin2=intplist_U(3,i0)
        f1=rintf_U(1,i0)
        f2=rintf_U(2,i0)
        coord(i1,ipoin)=coord(i1,ipoin1)*f1+coord(i1,ipoin2)*f2
        coord(i2,ipoin)=coord(i2,ipoin1)*f1+coord(i2,ipoin2)*f2
        !write(chk_unit,*)'ipoin=',ipoin,'ipoin1,2=',ipoin1,ipoin2,'f1=',f1,'f2=',f2
        !write(chk_unit,*)'coord=',coord(1:2,ipoin)
    end do
    end subroutine modify_coord !20210502


    subroutine update_coord_blarge  !20221102
    integer ipoin,idimn,itotv

    do ipoin=1,npoin
        do idimn=1,ndimn
            itotv=nodfn(idimn,ipoin)
            coord(idimn,ipoin)=coord0(idimn,ipoin)+result_zero(itotv)
        end do
    end do

    end subroutine update_coord_blarge !20221102


    subroutine modify_element_information !20210502

    character(10) nameg
    integer(ink)ielknind,ielem,nnode,ngaus,ikg,ig,id,nr_intrules
    real(irk)   djacb,weigp

    integer(ink),pointer::lnods(:)
    real(irk),pointer::elcod(:,:)

    real(irk),allocatable::shape(:),deriv(:,:),cartd(:,:),posgp(:),xjaci(:,:)

    do ielem=1,nelem
        ielknind=element(ielem)%index
        nr_intrules=elkn(ielknind)%nr_intrules
        igroup=element(ielem)%group

        lnods=>element(ielem)%field(1)%lnods_f
        elcod=>element(ielem)%field(1)%elcod_f


        if  (ielknind/=20.and.ielknind/=21)then  !!new
            do ikg=1,nr_intrules     !!!ikg
                ngaus=elkn(ielknind)%ggaus(ikg)%ngaus
                nnode=elkn(ielknind)%ggaus(ikg)%nnode
                nameg=elkn(ielknind)%ggaus(ikg)%name

                allocate(shape(nnode),deriv(ndimn,nnode),cartd(ndimn,nnode),xjaci(ndimn,ndimn))

                allocate(element(ielem)%egaus(ikg)%gpcod(ndimn,ngaus), &
                    element(ielem)%egaus(ikg)%djacb(ngaus))

                if (nameg(1:4)/='mass')allocate(element(ielem)%egaus(ikg)%cartd(ndimn,nnode,ngaus))
                if (nnode==2)djacb=sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))

                !coordinate for gauss points & derivatives
                do ig=1,ngaus !ig

                    shape=elkn(ielknind)%ggaus(ikg)%shape(:,ig)
                    deriv=elkn(ielknind)%ggaus(ikg)%deriv(:,:,ig)
                    weigp=elkn(ielknind)%ggaus(ikg)%weigp(ig)

                    do id=1,ndimn
                        element(ielem)%egaus(ikg)%gpcod(id,ig)=sum (elcod(id,1:nnode)*shape(1:nnode))
                    end do

                    if  (nnode==2)then
                        cartd=deriv/djacb
                    else
                        call jacob(ielem, ndimn, nnode,elcod,deriv,cartd, djacb,xjaci)
                    endif

                    if (nameg/='mass')element(ielem)%egaus(ikg)%cartd(:,:,ig)=cartd
                    element(ielem)%egaus(ikg)%djacb(ig)=djacb*weigp
                end do !ig

                deallocate (shape,deriv,cartd,xjaci)

            end do        !!!ikg
        endif
        nullify(lnods,elcod)
    end do

    end subroutine modify_element_information !20210502




    subroutine parameter_back_analysis(N,M) !20190810
    !N随机变量数,M测点数
    implicit none

    INTEGER  i,j, N, M,ivalue,inode,idofn,jnode,jtotv,iobstimes,  &
        iblks_bp,iincs_bp,istep_bp,iobse_bp,jvalue,ivalue_point
    !** SOLUTION VECTOR. CONTAINS VALUES X FOR F(X)
    DOUBLE PRECISION    X (N)
    DOUBLE PRECISION,allocatable:: errn(:,:),fjac2(:,:),errx(:,:),fjac1(:,:), &
        errm0(:,:),sigma(:),errn0(:,:),errx0(:,:)


    x=xvalue
    !call parameter_back_analysis_read
    IF (DTRNLSP_INIT (HANDLE,N,M,X,EPS, ITER1, ITER2, RS).NE. TR_SUCCESS) THEN
        !** IF FUNCTION DOES NOT COMPLETE SUCCESSFULLY THEN PRINT ERROR MESSAGE
        PRINT *, '| ERROR IN DTRNLSP_INIT'
        !** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
        !** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
        !** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
        CALL MKL_FREE_BUFFERS
        !** AND STOP
        STOP 1
    END IF

    !   ** CHECKS THE CORRECTNESS OF HANDLE AND ARRAYS CONTAINING JACOBIAN MATRIX,
    !** OBJECTIVE FUNCTION, LOWER AND UPPER BOUNDS, AND STOPPING CRITERIA.
    IF (DTRNLSP_CHECK (HANDLE, N,M, FJAC, FVEC, EPS, INFO) .NE. TR_SUCCESS) THEN
        !** IF FUNCTION DOES NOT COMPLETE SUCCESSFULLY THEN PRINT ERROR MESSAGE
        PRINT *, '| ERROR IN DTRNLSPBC_INIT'
        !** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
        !** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
        !** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
        CALL MKL_FREE_BUFFERS
        !** AND STOP
        STOP 1
    ELSE
        !write(7,*)'size(fjac)=',size(fjac),'size(fvec)=',size(fvec)
        !write(7,*)'info=',info(1:4)
        !** THE HANDLE IS NOT VALID.
        IF( INFO(1) .NE. 0 .OR.    &
            !** THE FJAC ARRAY IS NOT VALID.
            INFO(2) .NE. 0 .OR.   &
            !** THE FVEC ARRAY IS NOT VALID.
            INFO(3) .NE. 0 .OR. &
            !** THE EPS ARRAY IS NOT VALID.
            INFO(4) .NE. 0 ) THEN
            PRINT *, '| INPUT PARAMETERS ARE NOT VALID'
            !** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
            !** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
            !** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
            CALL MKL_FREE_BUFFERS
            !** AND STOP
            STOP 1
        END IF
    END IF

    !** SET INITIAL RCI CYCLE VARIABLES
    RCI_REQUEST = 0
    SUCCESSFUL = 0



    DO WHILE (SUCCESSFUL == 0)
        !** CALL TR SOLVER
        !**   HANDLE        IN/OUT: TR SOLVER HANDLE
        !**   FVEC          IN:     VECTOR
        !**   FJAC          IN:     JACOBI MATRIX
        !**   RCI_REQUEST   IN/OUT: RETURN NUMBER WHICH DENOTE NEXT STEP FOR PERFORMING
        IF (DTRNLSP_SOLVE (HANDLE, FVEC, FJAC, RCI_REQUEST)  &
            .NE. TR_SUCCESS) THEN
            !** IF FUNCTION DOES NOT COMPLETE SUCCESSFULLY THEN PRINT ERROR MESSAGE
            PRINT *, '| ERROR IN DTRNLSP_SOLVE'
            !** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
            !** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
            !** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
            CALL MKL_FREE_BUFFERS
            !** AND STOP
            STOP 1
        END IF
        !** ACCORDING WITH RCI_REQUEST VALUE WE DO NEXT STEP

        res=DTRNLSP_GET (HANDLE, ITER, ST_CR, R1, R2)
        write(7,*)'res=',res
        write(7,*)'r1=',r1,'r2=',r2
        write(7,*)'RCI_REQUEST=',RCI_REQUEST
        write(7,*)'iter=',iter
        write(7,*)'xvalue=',x


        !print *,'res=',res
        !print *,'r1=',r1,'r2=',r2
        !print *,'RCI_REQUEST=',RCI_REQUEST
        print *,'iter=',iter
        print *,'xvalue=',x



        SELECT CASE (RCI_REQUEST)
        CASE (-1, -2, -3, -4, -5, -6)
            !**   STOP RCI CYCLE
            SUCCESSFUL = 1
        CASE (1)
            !**   RECALCULATE FUNCTION VALUE
            !**     M               IN:     DIMENSION OF FUNCTION VALUE
            !**     N               IN:     NUMBER OF FUNCTION VARIABLES
            !**     X               IN:     SOLUTION VECTOR
            !**     FVEC            OUT:    FUNCTION VALUE F(X)
            xvalue=x
            do i=1,n
                if(para_back(i)%mode_transform==0)then
                    xvalue(i)=xvalue(i)*para_back(i)%factor
                elseif(para_back(i)%mode_transform==1)then
                    xvalue(i)=para_back(i)%factor/xvalue(i)
                endif
            end do
            ttime=0.
            trstep=0   !20230430
            Value_observ(:)%value_computation=0.

            call process_analysis  !20190810
            fvec=0.
            !write(7,*)'ivalue,jvalue,value_mesure,value_computation'
            do ivalue=1,m
                if(Value_observ(ivalue)%ic==0)cycle
                Fvec(ivalue)=Value_observ(ivalue)%value_measure-Value_observ(ivalue)%value_computation
                jvalue=Value_observ(ivalue)%jvalue
                if(jvalue/=0) &   !20230709
                    Fvec(ivalue)=Fvec(ivalue)+Value_observ(jvalue)%value_computation
                ivalue_point=Value_observ(ivalue)%ivalue_point

                !if(ivalue_point==169.or.ivalue_point==170)then
                idofn =lmdofn(Value_observ(ivalue)%idofn)
                !write(7,*)'ivalue_point=',ivalue_point,'idofn=',idofn
                ! if(jvalue==0) & !20230717
                !write(7,*)ivalue,jvalue,Value_observ(ivalue)%value_measure,Value_observ(ivalue)%value_computation
                ! if(jvalue/=0) & !20230717
                !write(7,*)ivalue,jvalue,Value_observ(ivalue)%value_measure,  &
                !    (Value_observ(ivalue)%value_computation-Value_observ(jvalue)%value_computation)
                !endif

            end do
            !write(7,*)'fvec=',fvec
        CASE (2)
            !**   COMPUTE JACOBI MATRIX
            !**     EXTENDED_POWELL IN:     EXTERNAL OBJECTIVE FUNCTION
            !**     N               IN:     NUMBER OF FUNCTION VARIABLES
            !**     M               IN:     DIMENSION OF FUNCTION VALUE
            !**     FJAC            OUT:    JACOBI MATRIX
            !**     X               IN:     SOLUTION VECTOR
            !**     JAC_EPS         IN:     JACOBI CALCULATION PRECISION

            if(balgor==0)then
                do  i=1, N
                    xvalue=x
                    Xvalue(i)=X(i)-para_back(i)%factor_inc*X(i)

                    do j=1,n
                        if(para_back(j)%mode_transform==0)then
                            xvalue(j)=xvalue(j)*para_back(j)%factor
                        elseif(para_back(j)%mode_transform==1)then
                            xvalue(j)=para_back(j)%factor/xvalue(j)
                        endif
                    end do
                    ttime=0.
                    trstep=0
                    Value_observ(:)%value_computation=0.
                    call process_analysis  !20190810
                    fvec1=0.
                    do ivalue=1,m
                        if(Value_observ(ivalue)%ic==0)cycle
                        Fvec1(ivalue)=Value_observ(ivalue)%value_computation
                    end do
                    xvalue=x
                    Xvalue(i)=X(i)+para_back(i)%factor_inc*X(i)
                    do j=1,n
                        if(para_back(j)%mode_transform==0)then
                            xvalue(j)=xvalue(j)*para_back(j)%factor
                        elseif(para_back(j)%mode_transform==1)then
                            xvalue(j)=para_back(j)%factor/xvalue(j)
                        endif
                    end do
                    ttime=0.
                    trstep=0
                    Value_observ(:)%value_computation=0.
                    call process_analysis  !20190810
                    fvec2=0.
                    !write(7,*)'ivalue,Value_observ(ivalue)%ic,Fvec1(ivalue),Fvec2(ivalue)='
                    do ivalue=1,m
                        if(Value_observ(ivalue)%ic==0)cycle
                        Fvec2(ivalue)=Value_observ(ivalue)%value_computation
                        !write(7,15)ivalue,Value_observ(ivalue)%ic,Fvec1(ivalue),Fvec2(ivalue)
                    end do
                    FJAC(:,i)=-(Fvec2-Fvec1)/(2.*para_back(i)%factor_inc*x(i))
                    !15 format(2i5,2e15.5)
                    !     write(7,*)'i=',i
                    !write(7,*)'fjac=',fjac(:,i)
                end do
                !stop
            else if(balgor==1)then  !20220108
                do  i=1, N
                    do J=1, mvalue
                        FJAC(j,i)=-Value_observ(j)%dudx(i)
                    enddo
                enddo
            endif

            !                IF (DJACOBI (measure_computation, N, M, FJAC, X, JAC_EPS)   &
            !                     .NE. TR_SUCCESS) THEN
            !!** IF FUNCTION DOES NOT COMPLETE SUCCESSFULLY THEN PRINT ERROR MESSAGE
            !                    PRINT *, '| ERROR IN DJACOBI'
            !!** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
            !!** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
            !!** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
            !                    CALL MKL_FREE_BUFFERS
            !!** AND STOP
            !                    STOP 1
            !                     END IF
        ENDSELECT
    END DO

    allocate(fjac1(npoints_pbx,n),errn(n,mobstimes),fjac2(n,n),errx(n,mobstimes))

    allocate(errm0(npoints_pbx,mobstimes),sigma(n))

    errm0=0.
    !write(7,*)'m=',m
    do ivalue=1,m
        if(Value_observ(ivalue)%ic==0)cycle
        iblks_bp=Value_observ(ivalue)%iblks
        iincs_bp=Value_observ(ivalue)%iincs
        istep_bp=Value_observ(ivalue)%istep
        iobse_bp=Value_observ(ivalue)%iobse
        !print *,'ivalue=',ivalue,'iblks_bp=',iblks_bp,'iincs_bp=',iincs_bp,'istep_bp=',istep_bp


        jtotv=Value_observ(ivalue)%ivalue_point
        !print *,'jtotv=',jtotv,'iobse_bp=',iobse_bp

        iobstimes=para_block(iblks_bp)%para_nincs(iincs_bp)%tstep_bp(istep_bp,iobse_bp)
        errm0(jtotv,iobstimes)=fvec(ivalue)
    end do
    !write(7,*)'errm0='
    !      do i=1,mobstimes
    !     write(7,10)errm0(:,i)
    !     end do

10  format(10e15.5)

    do i=1,mobstimes
        fjac1=0.
        do ivalue=1,m
            if(Value_observ(ivalue)%ic==0)cycle
            jtotv=Value_observ(ivalue)%ivalue_point
            iblks_bp=Value_observ(ivalue)%iblks
            iincs_bp=Value_observ(ivalue)%iincs
            istep_bp=Value_observ(ivalue)%istep
            iobse_bp=Value_observ(ivalue)%iobse
            iobstimes=para_block(iblks_bp)%para_nincs(iincs_bp)%tstep_bp(istep_bp,iobse_bp)
            if(i==iobstimes)then
                !write(7,*),'i=',i,'ivalue=',ivalue
                fjac1(jtotv,:)=fjac(ivalue,:)
            endif
        end do
        !     write(7,*)'iobstimes=',i,'fjac1='
        !     do jtotv=1,npoints_pbx
        !     write(7,10)fjac1(jtotv,:)
        !     end do
        !
        !stop

        do jtotv=1,npoints_pbx
            errn(:,i)=transpose(fjac1).x.errm0(:,i)
        end do
        fjac2=transpose(fjac1).x.fjac1
        allocate(errn0(n,1),errx0(n,1))
        errn0(:,1)=errn(:,i)
        call householderx(fjac2,errn0,errx0)
        errn(:,i)=errn0(:,1)
        errx(:,i)=errx0(:,1)
        deallocate(errn0,errx0)
    end do

    !write(7,*)'errx='
    !    do i=1,mobstimes
    !   write(7,10)errx(:,i)
    !   end do
    !write(7,*)'errn='
    !    do i=1,mobstimes
    !   write(7,10)errn(:,i)
    !   end do
    !

    do j=1,n
        sigma(j)=0.

        do i=1,mobstimes
            sigma(j)=sigma(j)+errx(j,i)**2
        end do
        sigma(j)=sigma(j)/mobstimes
        sigma(j)=sqrt(sigma(j))
        !sigma(j)=sigma(j)/x(j)
    end do


    write(7,*)'sigma=',sigma
    write(7,*)'mobstimes=',mobstimes
    write(7,*)'x=',x

    deallocate(errn,fjac2,fjac1,errx,sigma,errm0)


    !** GET SOLUTION STATUSES
    !**   HANDLE            IN: TR SOLVER HANDLE
    !**   ITER              OUT: NUMBER OF ITERATIONS
    !**   ST_CR             OUT: NUMBER OF STOP CRITERION
    !**   R1                OUT: INITIAL RESIDUALS
    !**   R2                OUT: FINAL RESIDUALS
    IF (DTRNLSP_GET (HANDLE, ITER, ST_CR, R1, R2)  &
        .NE. TR_SUCCESS) THEN
        !** IF FUNCTION DOES NOT COMPLETE SUCCESSFULLY THEN PRINT ERROR MESSAGE
        PRINT *, '| ERROR IN DTRNLSP_GET'
        !** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
        !** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
        !** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
        CALL MKL_FREE_BUFFERS
        !** AND STOP
        STOP 1
    END IF
    !** FREE HANDLE MEMORY
    IF (DTRNLSP_DELETE (HANDLE) .NE. TR_SUCCESS) THEN
        !** IF FUNCTION DOES NOT COMPLETE SUCCESSFULLY THEN PRINT ERROR MESSAGE
        PRINT *, '| ERROR IN DTRNLSP_DELETE'
        !** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
        !** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
        !** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
        CALL MKL_FREE_BUFFERS
        !** AND STOP
        STOP 1
    END IF

    !** RELEASE INTERNAL Intel(R) MKL MEMORY THAT MIGHT BE USED FOR COMPUTATIONS.
    !** NOTE: IT IS IMPORTANT TO CALL THE ROUTINE BELOW TO AVOID MEMORY LEAKS
    !** UNLESS YOU DISABLE Intel(R) MKL MEMORY MANAGER
    CALL MKL_FREE_BUFFERS
    !** IF FINAL RESIDUAL LESS THEN REQUIRED PRECISION THEN PRINT PASS
    !        IF (R2 .LT. 1.D-5) THEN
    !            PRINT *, '|         DTRNLSP POWELL............PASS'
    !            STOP 0
    !!** ELSE PRINT FAILED
    !        ELSE
    !            PRINT *, '|         DTRNLSP POWELL............FAILED'
    !            STOP 1
    !        END IF


    end  subroutine parameter_back_analysis

    !!!
    subroutine trust_region_back_analysis(N,M) !20220108
    implicit none

    integer(ink)  i,j,k, N, M,ivalue,inode,idofn,jnode,jtotv,iobstimes,  &
        iblks_bp,iincs_bp,istep_bp,iobse_bp,iter_tr,mtter,jvalue
    !** SOLUTION VECTOR. CONTAINS VALUES X FOR F(X)
    real(irk)   X(N),x0(N),x1,x2,alfak,deltak, &
        eta1,eta2,gama1,gama2,eps,delta0,eta01,eta02,rk, &
        deltab,dkstar,dkpre
    real(irk),allocatable:: errn(:,:),fjac2(:,:),errx(:,:),fjac1(:,:), &
        errm0(:,:),sigma(:),errn0(:,:),errx0(:,:),gk0(:),bk0(:,:)
    real(irk),allocatable::gk(:),gk1(:,:),Bk(:,:),xnew(:),funx(:),  &
        Qs(:),sk(:),yk(:),funx0(:),bs(:)

    allocate(gk(N),gk1(N,1),Bk(N,N),xnew(N),funx0(n),bs(n))
    eta1=trustp(1)%eta1;   eta2=trustp(1)%eta2
    gama1=trustp(1)%gama1; gama2=trustp(1)%gama2
    eps=trustp(1)%eps;    deltak=trustp(1)%delta0
    eta01=trustp(1)%eta01; eta02=trustp(1)%eta02
    mtter=trustp(1)%mtter; deltab=trustp(1)%deltab
    allocate(funx(mtter),Qs(mtter),gk0(N),sk(N),yk(N),bk0(N,N))

    x0=xvalue
    xnew=xvalue
    Bk=0.
    do i=1,n
        bk(i,i)=1.
    end do

    iter_tr=1

    x=xnew
    do i=1,n
        if(para_back(i)%mode_transform==0)then
            xvalue(i)=x(i)*para_back(i)%factor
        elseif(para_back(i)%mode_transform==1)then
            xvalue(i)=para_back(i)%factor/x(i)
        endif
    end do
    ttime=0.
    Value_observ(:)%value_computation=0.

    call process_analysis
    fvec=0.

    write(7,*)'ivalue,value_mesure,value_computation'
    do ivalue=1,m
        if(Value_observ(ivalue)%ic==0)cycle
        Fvec(ivalue)=Value_observ(ivalue)%value_measure-Value_observ(ivalue)%value_computation
        jvalue=Value_observ(ivalue)%jvalue
        if(jvalue/=0) &   !20230709
            Fvec(ivalue)=Fvec(ivalue)+Value_observ(jvalue)%value_computation
        if(jvalue==0) & !20230709
            write(7,*)ivalue,Value_observ(ivalue)%value_measure,Value_observ(ivalue)%value_computation
        if(jvalue/=0) & !20230709
            write(7,*)ivalue,Value_observ(ivalue)%value_measure,  &
            (Value_observ(ivalue)%value_computation-Value_observ(jvalue)%value_computation)
    end do
    !   write(7,*)'value_observe%dudx='
    ! do i=1,mvalue
    !write(7,*)i,Value_observ(i)%dudx(:)
    !enddo

    do i=1,n
        do j=1,mvalue
            Fjac(j,i)=Value_observ(j)%dudx(i)
        enddo
    end do
    funx(iter_tr)=dot_product(fvec,fvec)
    do i=1,n
        gk(i)=-2.*dot_product(fvec,Fjac(:,i))
    end do
    !write(7,*)'fvec=',fvec
    !write(7,*)'fjac(:,1)=',fjac(:,1)
    !write(7,*)'fjac(:,2)=',fjac(:,2)
    !write(7,*)'gk=',gk,'funx(iter_tr)=',funx(iter_tr)
20  x1=dot_product(gk,gk)
    x1=sqrt(x1)
    !write(7,*)'x1=',x1
    if(sqrt(x1)<eps) goto 30
    call solve_dx(deltak,N,gk,bk,Sk)
    !write(7,*)'sk=',sk
    if(iter_tr>1)then
        funx(iter_tr)=funx(iter_tr-1)
        gk0=gk
    end if

    x=x0+sk
    do i=1,n
        if(para_back(i)%mode_transform==0)then
            xvalue(i)=x(i)*para_back(i)%factor
        elseif(para_back(i)%mode_transform==1)then
            xvalue(i)=para_back(i)%factor/x(i)
        endif
    end do
    ttime=0.
    Value_observ(:)%value_computation=0.
    call process_analysis
    fvec=0.
    do ivalue=1,m
        if(Value_observ(ivalue)%ic==0)cycle
        Fvec(ivalue)=Value_observ(ivalue)%value_measure-Value_observ(ivalue)%value_computation
        jvalue=Value_observ(ivalue)%jvalue
        if(jvalue/=0) &   !20230709
            Fvec(ivalue)=Fvec(ivalue)-+Value_observ(jvalue)%value_computation
    end do
    bs=Bk.x.sk
    dkstar=funx(iter_tr)-dot_product(fvec,fvec)
    dkpre =-dot_product(gk,sk)-.5*dot_product(sk,bs)

    rk=dkstar/dkpre
    xnew=x0
    !funx(iter_tr)=funx0(iter_tr)
    gk=gk0
    !write(7,*)'dkpre=',dkpre,'dkstar=',dkstar,'rk=',rk
    if(rk>=eta1)then
        xnew=x0+Sk
        do i=1,n
            do J=1,Mvalue
                Fjac(j,i)=Value_observ(j)%dudx(i)
            enddo
        end do
        funx(iter_tr)=dot_product(fvec,fvec)
        if(sqrt(funx(iter_tr))<eps) goto 30
        do i=1,n
            gk(i)=-2.*dot_product(fvec,Fjac(:,i))
        end do
    endif
    !write(7,*)'dkstar=',dkstar,'dkpre=',dkpre,'rk=',rk,'eta1=',eta1,'eta2=',eta2

    !!!校正信赖区间
    if(rk<eta1)then
        deltak=.5*(0+gama1*deltak)
    elseif(rk>=eta1.and.rk<=eta2)then
        deltak=.5*(gama1*deltak+deltak)
    elseif(rk>eta2)then
        if(gama2*deltak<deltab)deltak=.5*(gama2*deltak+deltak)
        if(gama2*deltak>=deltab)deltak=.5*(deltab+deltak)
    endif
    !write(7,*)'deltak=',deltak
    if(rk>=eta1)then   !20230423
        bk0=bk
        yk=gk-gk0
        call update_bk(N,yk,sk,bk0,bk)
    endif
    !!!

    !write(7,*)'x0=',x,'xnew=',xnew
    !!!

    if(iter_tr<mtter)then
        iter_tr=iter_tr+1
        if(iter_tr>=2)then
            !write(7,*)'bk='
            !write(7,*)bk(1,:)
            !write(7,*)bk(2,:)
        endif
        x0=xnew
        goto 20
    end if
    deallocate(gk,gk1,Bk,xnew,bs)
    deallocate(funx,Qs,gk0,bk0,Sk,yk,funx0)

30  continue
    write(7,*)'iter_tr=',iter_tr,'mtter=',mtter
    write(7,*)'abs(df/dx)=',x1,'abs(fvec)=',sqrt(funx(iter_tr))
    write(7,*)'xnew=',xnew

    allocate(fjac1(npoints_pbx,n),errn(n,mobstimes),fjac2(n,n),errx(n,mobstimes))

    allocate(errm0(npoints_pbx,mobstimes),sigma(n))

    errm0=0.
    !write(7,*)'m=',m
    do ivalue=1,m
        if(Value_observ(ivalue)%ic==0)cycle
        iblks_bp=Value_observ(ivalue)%iblks
        iincs_bp=Value_observ(ivalue)%iincs
        istep_bp=Value_observ(ivalue)%istep
        iobse_bp=Value_observ(ivalue)%iobse
        jtotv=Value_observ(ivalue)%ivalue_point
        iobstimes=para_block(iblks_bp)%para_nincs(iincs_bp)%tstep_bp(istep_bp,iobse_bp)
        errm0(jtotv,iobstimes)=fvec(ivalue)
    end do
    !write(7,*)'errm0='
    !      do i=1,mobstimes
    !     write(7,10)errm0(:,i)
    !     end do

10  format(10e15.5)

    do i=1,mobstimes
        fjac1=0.
        do ivalue=1,m
            if(Value_observ(ivalue)%ic==0)cycle
            jtotv=Value_observ(ivalue)%ivalue_point
            iblks_bp=Value_observ(ivalue)%iblks
            iincs_bp=Value_observ(ivalue)%iincs
            istep_bp=Value_observ(ivalue)%istep
            iobse_bp=Value_observ(ivalue)%iobse
            iobstimes=para_block(iblks_bp)%para_nincs(iincs_bp)%tstep_bp(istep_bp,iobse_bp)
            if(i==iobstimes)then
                fjac1(jtotv,:)=fjac(ivalue,:)
            endif
        end do
        !write(7,*)'iobstimes=',i,'fjac1='
        !do jtotv=1,npoints_pbx
        !write(7,10)fjac1(jtotv,:)
        !end do

        do jtotv=1,npoints_pbx
            errn(:,i)=transpose(fjac1).x.errm0(:,i)
        end do
        fjac2=transpose(fjac1).x.fjac1
        allocate(errn0(n,1),errx0(n,1))
        errn0(:,1)=errn(:,i)
        call householderx(fjac2,errn0,errx0)
        errn(:,i)=errn0(:,1)
        errx(:,i)=errx0(:,1)
        deallocate(errn0,errx0)
    end do

    !write(7,*)'errx='
    !    do i=1,mobstimes
    !   write(7,10)errx(:,i)
    !   end do
    !write(7,*)'errn='
    !    do i=1,mobstimes
    !   write(7,10)errn(:,i)
    !   end do
    !

    do j=1,n
        sigma(j)=0.

        do i=1,mobstimes
            sigma(j)=sigma(j)+errx(j,i)**2
        end do
        sigma(j)=sigma(j)/mobstimes
        sigma(j)=sqrt(sigma(j))
    end do


    write(7,*)'sigma=',sigma
    write(7,*)'mobstimes=',mobstimes
    write(7,*)'x=',x

    deallocate(errn,fjac2,fjac1,errx,sigma,errm0)

    end  subroutine trust_region_back_analysis !20220108
    !!!
    subroutine solve_dx(deltak,N,gk,bk,S)
    integer(ink) N
    real(irk)   a0,b0,c0,yx,lamda1,lamda2,lamda,x1,x2,alfak,gk(:),bk(:,:),bgk(N),  &
        S1(N),Gk1(N,1),S2(N),S21(N,1),skc,skn,deltak,S(:)
    x1=dot_product(gk,gk)
    Bgk=Bk.x.gk
    x2=dot_product(gk,Bgk)
    alfak=x1/x2
    S1=-alfak*gk

    Gk1(:,1)=-Gk
    call householderx(Bk,Gk1,S21)
    S2=S21(:,1)
    skc=dot_product(S1,S1)
    skn=dot_product(S2,S2)
    skc=sqrt(skc)
    skn=sqrt(skn)

    print *,'sqrt(x1)=',sqrt(x1)
    !if(sqrt(x1)<eps) goto 30
    !
    !if(iter_tr==1)then
    !   delta0=x1/10.
    !   write(7,*)'delta0=',delta0,'deltak=',deltak
    !   if(delta0>deltak)deltak=delta0
    !endif
    write(7,*)'s1=',s1
    write(7,*)'s2=',s2
    write(7,*)'deltak=',deltak,'skc=',skc,'skn=',skn
    !write(7,*)'xnew0=',x-deltak*gk/sqrt(x1)
    if(skc>=deltak)then
        S=-deltak*gk/sqrt(x1)
    elseif(skc<deltak.and.skn<=deltak)then
        S=S2   !-S2  20230423
    elseif(skc<deltak.and.skn>deltak)then
        lamda=0.
        a0=dot_product(S2-S1,S2-S1)
        b0=2*dot_product(S2-S1,S1)
        C0=dot_product(S1,S1)
        C0=C0-deltak
        yx=b0**2-4*a0*c0
        lamda1=(-b0+sqrt(yx))/(2*a0)
        lamda2=(-b0-sqrt(yx))/(2*a0)
        write(7,*)'lamda1=',lamda1,'lamda2=',lamda2
        if(lamda1>0.and.lamda2>0.)then
            lamda=lamda1
            if(lamda2>lamda1)lamda=lamda1
        elseif(lamda1>0.)then
            lamda=lamda1
        elseif(lamda2>0.)then
            lamda=lamda2
        endif
        S=S1+lamda*(S2-S1)
    endif

    end subroutine solve_dx

    subroutine update_bk(N,yk,sk,bk0,bk)  !BFGS公式(来源于最优化方法.ppt)
    integer(ink) i,j,N
    real(irk) yk(:),sk(:),bk0(:,:),bk(:,:),BS(N),BS1(N),x1

    !yk=gk-gk0
    !bk0=bk
    Bk=bk0
    bs=Bk0.x.sk

    x1=dot_product(sk,yk)
    do i=1,n
        do j=1,n
            bk(i,j)=bk(i,j)+yk(i)*yk(j)/x1
        end do
    end do

    do i=1,n
        bs1(i)=dot_product(sk,bk0(:,i))
    end do
    x1=dot_product(sk,bs)
    do i=1,n
        do j=1,n
            bk(i,j)=bk(i,j)-bs(i)*bs1(j)/x1
        end do
    end do
    end subroutine update_bk

    subroutine rigid_dis_back_analysis !20211121
    implicit none
    integer(ink) nincs_pb,nstep_pb,mvalue_point,imt,igdis_bk,i,ipoin,istep,npara,nmbpoint
    real   (irk),allocatable:: observ(:),observt(:,:),interp(:,:),interpt(:,:),rgdis(:,:)
    integer(ink),allocatable::measurep(:),backrdisp(:),changepx(:)
    real   (irk) ug,ue
    allocate(measurep(Npoints_pbx))
    do iblks=1,Nblks_pb
        nincs_pb=para_block(iblks)%nincs_pb
        do iincs=1,nincs_pb
            nstep_pb=para_block(iblks)%para_nincs(iincs)%nstep_pb
            mvalue_point=para_block(iblks)%para_nincs(iincs)%mvalue_point

            measurep=0
            do imt=1,mvalue_point
                ipoin=para_block(iblks)%para_nincs(iincs)%list_point_pb(imt)
                measurep(ipoin)=1
            end do

            allocate(backrdisp(Npoints_pbx),changepx(Npoints_pbx))

            do igdis_bk=1,ngdis_bk
                write(7,*)'iblks=',iblks,'iincs=',iincs,'igdis_bk=',igdis_bk
                write(7,*)'      istep                 刚体位移'

                backrdisp=0
                backrdisp(rigid_bk(igdis_bk)%node_bk)=1

                nmbpoint=0
                changepx=0

                do ipoin=1,Npoints_pbx
                    if(backrdisp(ipoin)==1.and.measurep(ipoin)==1)then
                        nmbpoint=nmbpoint+1
                        changepx(ipoin)=nmbpoint
                    endif
                end do

                npara=3*(ndimn-1)
                allocate(observ(nmbpoint),observt(npara,1),interp(nmbpoint,npara),interpt(npara,npara),rgdis(npara,1))

                do istep=1,nstep_pb !istep
                    nmbpoint=0
                    do i=1,mvalue  !i
                        if(iblks/=Value_observ(i)%iblks)cycle
                        if(iincs/=Value_observ(i)%iincs)cycle
                        if(istep/=Value_observ(i)%istep)cycle
                        ipoin=Value_observ(i)%ivalue_point
                        if(backrdisp(ipoin)/=1.or.measurep(ipoin)/=1)cycle
                        nmbpoint=nmbpoint+1
                        observ(nmbpoint)=Value_observ(i)%value_measure
                        idofn=Value_observ(i)%idofn   !20230523
                        interp(nmbpoint,1:npara)=rigid_bk(igdis_bk)%npdisp(idofn,changepx(ipoin),:)
                    end do !i
                    interpt=transpose(interp).x.interp
                    observt(:,1)=transpose(interp).x.observ
                    do idofn=1,npara
                        if(rigid_bk(igdis_bk)%fixed_dis(idofn)==0) then
                            if(interpt(idofn,idofn)<1.e-1)then
                                interpt(idofn,idofn)=1.e10
                            else
                                interpt(idofn,idofn)=interpt(idofn,idofn)*1.e10
                            endif
                        endif
                    end do
                    call householder(interpt,observt,rgdis)


                    write(7,20)istep,rgdis(:,1)
                    write(7,*)'    观测点号    刚体位移      弹性位移'
                    nmbpoint=0
                    do i=1,mvalue
                        if(iblks/=Value_observ(i)%iblks)cycle
                        if(iincs/=Value_observ(i)%iincs)cycle
                        if(istep/=Value_observ(i)%istep)cycle
                        ipoin=Value_observ(i)%ivalue_point
                        if(backrdisp(ipoin)/=1.or.measurep(ipoin)/=1)cycle
                        nmbpoint=nmbpoint+1
                        ug=dot_product(interp(nmbpoint,:),rgdis(:,1))
                        ue=observ(nmbpoint)-ug
                        write(7,20)i,ug,ue
                    end do


                    !        do jpoin=1,npara
                    !ipoin=nodvar_bk(igdis_bk)%node_bk(jpoin)
                    !itotv=nodfn(lmdofn(kdofn),ipoin)
                    !result_zero(itotv)=nodvar(jpoin,1)
                    !end do
                    if(outplot(1:3)=='GID')   call OUT_GID_WRITE

                end do !istep
                deallocate(observ,observt,interp,interpt,rgdis,changepx)
            end do  !igdis_bk
            deallocate(backrdisp)
        end do !iincs
    end do !iblks
    deallocate(measurep)

20  format(i10,6e15.5)

    end subroutine rigid_dis_back_analysis !20211121

    subroutine nodal_value_back_analysis !20211201
    implicit none
    integer(ink) nincs_pb,nstep_pb,mvalue_point,imt,igdis_bk,i,ipoin,istep,   &
        npara,nmbpoint,jdofn,itotv,kdofn,kdofn1
    real   (irk),allocatable:: observ(:),observt(:,:),interp(:,:),interpt(:,:),nodvar(:,:)
    integer(ink),allocatable::measurep(:),backrdisp(:),listnode(:)

    allocate(measurep(Npoints_pbx))
    do iblks=1,Nblks_pb
        nincs_pb=para_block(iblks)%nincs_pb
        do iincs=1,nincs_pb
            nstep_pb=para_block(iblks)%para_nincs(iincs)%nstep_pb
            mvalue_point=para_block(iblks)%para_nincs(iincs)%mvalue_point

            measurep=0
            do imt=1,mvalue_point
                ipoin=para_block(iblks)%para_nincs(iincs)%list_point_pb(imt)
                measurep(ipoin)=1
            end do

            allocate(backrdisp(Npoints_pbx),listnode(npoin))

            do igdis_bk=1,ngval_bk
                write(7,*)'iblks=',iblks,'iincs=',iincs,'igvar_bk=',igdis_bk
                write(7,*)'      istep','      node_value'

                backrdisp=0
                listnode=0


                listnode(nodvar_bk(igdis_bk)%node_bk(:))=1

                do i=1,Npoints_pbx
                    nintf=para_points(i)%nintf
                    if(nintf==0)cycle
                    if(all(listnode(para_points(i)%listf(:))==1))backrdisp(i)=1
                end do

                nmbpoint=0

                do ipoin=1,Npoints_pbx
                    if(backrdisp(ipoin)==1.and.measurep(ipoin)==1)nmbpoint=nmbpoint+1
                end do

                npara=nodvar_bk(igdis_bk)%npoin_bk
                allocate(observ(nmbpoint),observt(npara,1),interp(nmbpoint,npara),interpt(npara,npara),nodvar(npara,1))
                interp=0.;interpt=0.
                do istep=1,nstep_pb !istep

                    do kdofn1=1,nodvar_bk(igdis_bk)%ndofn_bk
                        kdofn=nodvar_bk(igdis_bk)%dof_bk(kdofn1)

                        nmbpoint=0
                        do i=1,mvalue  !i
                            if(iblks/=Value_observ(i)%iblks)cycle
                            if(iincs/=Value_observ(i)%iincs)cycle
                            if(istep/=Value_observ(i)%istep)cycle
                            if(kdofn/=Value_observ(i)%idofn)cycle
                            ipoin=Value_observ(i)%ivalue_point
                            if(backrdisp(ipoin)/=1.or.measurep(ipoin)/=1)cycle
                            nmbpoint=nmbpoint+1
                            observ(nmbpoint)=Value_observ(i)%value_measure
                            do  idofn=1,para_points(ipoin)%nintf
                                jpoin=para_points(ipoin)%listf(idofn)
                                jdofn=nodvar_bk(igdis_bk)%nodet_bk(jpoin)
                                interp(nmbpoint,jdofn)=para_points(ipoin)%rintf(idofn)
                            end do
                        end do !i


                        interpt=transpose(interp).x.interp
                        observt(:,1)=transpose(interp).x.observ
                        call householder(interpt,observt,nodvar)
                        write(7,20)istep,nodvar(:,1)
                        do jpoin=1,npara
                            ipoin=nodvar_bk(igdis_bk)%node_bk(jpoin)
                            itotv=nodfn(lmdofn(kdofn),ipoin)
                            result_zero(itotv)=nodvar(jpoin,1)
                        end do


                        if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                    end do !kdofn1
                end do !istep
                deallocate(observ,observt,interp,interpt,nodvar)
            end do  !igdis_bk
            deallocate(backrdisp)
        end do !iincs
    end do !iblks
    deallocate(measurep,listnode)

10  format(20e15.3)
20  format(i10,20e15.3)

    end subroutine nodal_value_back_analysis !20211201

    subroutine parameter_back_analysis_verify !20200812
    implicit none

    INTEGER   k0,nincs_pb,i,j,istep,inode,jnode,idofn,mvalue_point, &
        iblks,iincs,nintf,mode_transform,bblks,i0,ibpstep,mback_point, &
        nstep_pb,ix
    real     factor,dtime_pb
    integer,allocatable::list_point_pb(:)

    do istoch=1,nstoch
        xvalue=para_stoch(:,istoch)
        do i=1,npara
            factor=para_back(i)%factor
            mode_transform=para_back(i)%mode_transform
            if(mode_transform==0)then
                xvalue(i)=factor*xvalue(i)
            elseif(mode_transform==1)then
                xvalue(i)=factor/xvalue(i)
            endif
        end do
        tbstep=0
        ttime=0.
        print *,'istoch=',istoch
        call process_analysis
    end do



    !write(observ_unit,*)'information for given points：Npoints_pb'
    !write(observ_unit,10) nback_point
    !write(observ_unit,*)'1:Npoints_pb/i0,ndofn,imdofn,nintf'
    ! k0=0 ; nintf=1
    !              do i=1,nback_point
    !        k0=k0+1
    !        inode=freedom_for_back(1,i)
    !        idofn=freedom_for_back(2,i)
    !           write(observ_unit,10)k0,1,idofn,1
    !           write(observ_unit,10)inode
    !           write(observ_unit,12)1.
    !              end do
    write(observ_unit,*)'Nblks_pb/1:nblks_pb->/text/nincs_pb/1:nincs_pb->dtime_pb,nstep_p,bobserv_pb'
    write(observ_unit,10)runblks
    rewind(mainunit)
    do iblks=1,runblks
        read(mainunit,*)text
        write(observ_unit,*)text
        read(mainunit,*)nincs_pb
        write(observ_unit,10)nincs_pb
        do iincs=1,nincs_pb
            read(mainunit,*)i0,dtime_pb,i0,i0,nstep_pb
            write(observ_unit,13)dtime_pb,nstep_pb,1,nstoch
            read(mainunit,*)text
        end do
    end do

    write(observ_unit,*)'observed values(1:nback_point)|1:nstoch:(1:tbstep)'
    ix=0
    do i=1,nback_point
        do j=1,nstoch
            ix=ix+1
            write(observ_unit,10)ix,i,j,0
            write(observ_unit,12)Value_vc(i,:,j)
        end do
    end do

10  format(20i10)
12  format(20e15.5)
13  format(e15.5,3i10)

    end  subroutine parameter_back_analysis_verify


    subroutine process_analysis   !20190810
    implicit none
    integer            igapb,igaps,ipairs,npairs,igapbf,npgblock,i0,ij,ipoin


    if (diag_check_mode()) call diag_summary_and_exit()
    ttime=lttime
    print *,'lblks=',lblks,'lincs=',lincs,'ttime=',ttime
    if(Bparameter/=0)then
        result_zero=0.
        if(allocated(result_first))result_first=0.0
        if(allocated(result_second))result_second=0.0
        if(allocated(torel))               torel=0.0
        if(allocated(toforl))              toforl=0.0
        if(nflow/=0)then
            allocate(flowrate(npoin))
            flowrate=0.
        endif


        do igapb=1,ngapb   !tcl 2009/10/11
            if(gapb(igapb)%nrdof==0)cycle
            gapb(igapb)%rdisp_inc=0.
            gapb(igapb)%rdisp_zero=0.
        enddo

        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            do ipairs=1,npairs
                if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                gaps(igaps)%dxyz0(:,ipairs)=0.
                gaps(igaps)%dxyz(:,ipairs)=0.
                gaps(igaps)%ctforce0(:,ipairs)=0.
                gaps(igaps)%ctforce(:,ipairs)=0.
            end do
        end do

        call gpvar_initial  !201605
    endif

    if (.not. yl_adapter_mode) call external_load_1
    do iblks=lblks+1,runblks
        write(7,*)'iblks=',iblks,'runblks=',runblks
        if(allocated(torel))               torel=0.0  !20201121

        if(outplot=='GIDL')call OUT_GID_BIN_MESH

        !if(iblks==uwcpl.or.iblks==nblks)
        ! call gpvar_change  !zhao 2007.04.10  !2016/04/25

        mdiv=1
        print *,'iblks=',iblks
        if(type_load=='DISCONTROL'.and.iblks==1)xload=0.
        if(type_load=='DISCONTROL'.and.iblks>1) xload=yload
        write(chkunit,*)'iblks=',iblks


        if(iblks==1)nremesh=0
        call TIME(char_time)
        print *, 'time: ', char_time
        write(chkunit,*)'time: ', char_time

        write(7,*)'ninit=',ninit,'iblks=',iblks,'restart=',restart
        if(ninit/=0.and.iblks==1.and.restart==0)call read_initial

        if (uinitial(iblks)==1) then
            result_zero=0.0
            if(allocated(result_first))result_first=0.0
            if(allocated(result_second))result_second=0.0
        endif
        print *,'a1'

        appear_p=appear
        do igroup=1,ngroup
            appear(igroup)=appear_process(igroup,iblks)
            group(igroup)%matno=matno_process(igroup,iblks)
            if(appear_process(igroup,iblks)==0.and.              &
                appear_process(igroup,iblks-1)==1)                &
                appear(igroup)=-1
        end do

        !20231215YL
        if(restart==0) then !20231008
            if(gamamax/=0) then !yuanli20230926 等效线性化土体动力本构
                open(gamamaxunit,file=probn(1:len1)//'.gamax')
                call readgamamax
            endif
        else
            gamamax=0
        endif

        if(ninistn>0.and.stnunit/=0)call read_permanent_strain !20231010
        !20231215YL

        ! transform the value in the old mesh to the new mesh
        ! meshc---1, coarse mesh to fine mesh, for stress concentration problem
        !         2, fine mesh to coarse mesh, for temperature and creep problem
        !         3, mixed, for fluid dynamic problem with consideration of free surface

        !! the following is to modify the interpolation matrix
        if (meshc==1.or.meshc==2)then  !2003/10/31
            appear=appear_process(:,iblks)
            if (meshc==2)then
                do igroup=ngroup0+1,ngroup
                    cgroup=group(igroup)%cgroup
                    appear(-cgroup)=0
                end do
                goto 100
            endif
            !!!!!! obtain the average result to set to the refined or coarse mesh
            do igroup=1,ngroup0
                cgroup=abs(group(igroup)%cgroup)
                if(cgroup==0) goto 10
                if (appear(igroup)==1)then
                    call judge_fine_mesh(igroup,icjr)
                    if (icjr==1)then
                        appear(igroup)=0
                        appear_process(igroup,iblks:nblks)=0
                        appear(cgroup)=1
                        appear_process(cgroup,iblks:nblks)=1
                    endif   ! for conditions of cgroup
                endif
10              continue
            end do ! for igroup
        endif ! for meshc

100     if (meshc==1.or.meshc==2)then  ! 2003/10/31
            write(7,992)appear(1:ngroup0)
            write(7,992)appear(ngroup0+1:ngroup)
992         format(20i5)
            do itotv=1,ntotv
                if(trans(itotv)%nintf/=0)deallocate(trans(itotv)%rintf,trans(itotv)%listf)
                trans(itotv)%nintf=0
            end do
            allocate(dinterp(npoin))
            dinterp=0
            allocate(icpoi(npoin))
            if (meshc==2) then
                icpoi=0
                do igroup=1,ngroup0
                    cgroup=abs(group(igroup)%cgroup)
                    if (cgroup==0.and.appear_process(igroup,iblks)==1)then
                        DO ielgroup = 1,group(igroup)%nelgroup
                            ielem = group(igroup)%list(ielgroup)
                            lnods =>element(ielem)%field(1)%lnods_f
                            icpoi(lnods)=1
                            nullify(lnods)
                        end do
                    endif
                end do

                do igroup=ngroup0+1,ngroup
                    cgroup=abs(group(igroup)%cgroup)
                    if (appear_process(igroup,iblks)==1.and.appear_process(cgroup,iblks)==1)then
                        DO ielgroup = 1,group(igroup)%nelgroup
                            ielem = group(igroup)%list(ielgroup)
                            lnods =>element(ielem)%field(1)%lnods_f
                            icpoi(lnods)=1
                            nullify(lnods)
                        end do
                    endif
                end do
                do ipoin=1,npoin
                    nintf=trans_c(ipoin)%nintf
                    if (icpoi(ipoin)==1.or.nintf<0)then
                        dinterp(ipoin)=1
                    endif
                end do
            elseif(meshc==1)then
                do igroup=ngroup0+1,ngroup
                    if (appear_process(igroup,iblks)==1)then
                        icpoi=0
                        DO ielgroup = 1,group(igroup)%nelgroup
                            ielem = group(igroup)%list(ielgroup)
                            lnods =>element(ielem)%field(1)%lnods_f
                            icpoi(lnods)=1
                            nullify(lnods)
                        end do
                        dinterp=dinterp+icpoi
                    endif
                end do
            endif

            deallocate(icpoi)

            do ipoin=1,npoin

                nintf=abs(trans_c(ipoin)%nintf)
                if ((meshc==2.and.nintf/=0.and.dinterp(ipoin)==1).or.   &
                    (meshc==1.and.trans_c(ipoin)%nintf>0.and.dinterp(ipoin)==1))then  !x2

                    !write(chkunit,*)'ipoin=',ipoin,'nintf=',nintf
                    !write(chkunit,*)'list=',trans_c(ipoin)%listf(:)
                    do idofn=1,cdofn   !4
                        itotv=nodfn(idofn,ipoin)
                        if (itotv/=0) then  !x3
                            trans(itotv)%nintf=nintf
                            allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
                            if(meshc==1)result_zero(itotv)=0.
                            if (meshc==2.or.meshc==1)then
                                if(allocated(result_first))  result_first(itotv)=0.0
                                if(allocated(result_second))result_second(itotv)=0.0
                                if(allocated(torel))                torel(itotv)=0.0
                                if(allocated(toforl))              toforl(itotv)=0.0
                            endif

                            do jnode=1,nintf  !3
                                jpoin=trans_c(ipoin)%listf(jnode)
                                dfact=trans_c(ipoin)%rintf(jnode)
                                jtotv=nodfn(idofn,jpoin)
                                trans(itotv)%listf(jnode)=jtotv
                                trans(itotv)%rintf(jnode)=dfact
                                if(meshc==1)result_zero(itotv)=result_zero(itotv)+result_zero(jtotv)*dfact
                                if (meshc==1.or.meshc==2)then
                                    if(allocated(result_first))  result_first(itotv)=result_first(itotv)+dfact*result_first(jtotv)
                                    if(allocated(result_second))result_second(itotv)=result_second(itotv)+dfact*result_second(jtotv)
                                    if(allocated(torel)) torel(itotv) =torel(itotv) +dfact*torel(jtotv)
                                    if(allocated(toforl))toforl(itotv)=toforl(itotv)+dfact*toforl(itotv)
                                endif
                            enddo !3
                        endif   !x3
                    end do  !4
                endif     !x2
            end do
            deallocate(dinterp)
        endif

        write(7,*)'ikindks=',ikindks
        if(ikindks/=0)call steel_spring_parameter  !!steel 2006


        if (.not. yl_adapter_mode) call prescrib_set  !20221124

        if(nbackdT==1)then !20210820

            do igapbf=1,nbackf
                igapb=backf(igapbf)%groupb
                npgblock=gapb(igapb)%npgblock
                do i0=1,npgblock
                    igaps=gapb(igapb)%nodegblock_igaps(i0)
                    ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                    ij=gapb(igapb)%nodegblock_onetwo(i0)
                    ipoin=gaps(igaps)%pairnode(ij,ipairs)
                    do idofn=1,mdofn
                        if(lmdofn(idofn)==0)cycle  !20230430
                        itotv=nodfn(lmdofn(idofn),ipoin)
                        if(itotv==0)cycle
                        iffix(itotv)=6  !20210820
                        fixed(itotv)=0. !20210820
                    end do
                end do
            end do
        endif

        if (.not. yl_adapter_mode) call external_load_2
        if(block_stab==0) &   !20200331
            call contact_pair_process !ctt2005  !zhao 2007.04.16
        if (.not. yl_adapter_mode) call boundt !! temperature
        if(ADINA/=0.and.iblks==runblks)call GHM2ADINA
        if(ADINA==1.and.iblks<runblks)cycle
        if(ADINA==1.and.iblks==runblks)stop 'stop for ADINA==1!'
        line_load_block(iblks)=lineload
        line_temp_block(iblks)=linet  !! temperature
        call TIME(char_time)
        print *, 'time: ', char_time
        write(chkunit,*)'time(solve): ', char_time
        if (yl_dump_enabled) call yl_state_dump('model_ready')
        operation='SET'
        call solve
        call TIME(char_time)
        print *, 'time: ', char_time
        write(chkunit,*)'time(solve_set): ', char_time
        if(nlayer==2.and.type_solver=='PROFILE'.and.solver_iter==2)call nonzero_stiff_pcg
        call TIME(char_time)
        print *, 'time: ', char_time
        write(chkunit,*)'time(solve_pcg): ', char_time
        call modf_time_order ! zhao 2007/04/10
        if (type_problem=='Q') then

            if(relis==1.and.block_stab==0)then
                call STATIC_U_reli
            elseif(relis==1.and.block_stab>=1)then
                call static_rigid_reli
            elseif(block_stab>=1.and.ebody==0)then
                call static_rigid_1
            else if(mdofn==7)  then
                if(lmdofn(7)/=0)call static_U_P
            else if(mdofn==8)  then
                print *,' to static_u_pw'
                if(lmdofn(8)/=0)call static_U_Pw
            else if(nbackf/=0)then
                if(nbackdT==0)then
                    call back_analysis  !20150925
                else
                    call back_d_analysis  !20210820
                endif
            else
                call static_U
            endif
        endif
        !if(type_problem=='Q'.and.mdofn>=10.and.lmdofn(10)/=0)call modf_time_order  !zhao 05/07/22
        !call modf_time_order ! zhao 2007/04/10
        if (type_problem/='Q'.and.type_problem/='E'.and.type_problem/='W') then !freq2006
            call modf_time_order
            if(type_solver=='EXPLICIT') then
                call explicit
            else
                call time_dependent
            endif
        elseif(type_problem=='E') then
            call response_spectrum
        endif

        if(type_problem=='W') call frequency_analysis !freq2006

        call gpvar1_initial                                         !! 4/5/98

        restart=0
        lincs=0
        if(meshc/=0) appear_p=appear  !2003/10/31

        if (rmesh/=0)then  !!2004/7/12

            cmesh=1
            if (type_load=='DISCONTROL')then
                do itcurve=1,ntcurve
                    type_curve=tcurves(itcurve)%type_curve
                    if (type_curve=='DISCONTROL')then
                        ic=tcurves(itcurve)%ttime_curve(1)
                        yload=abs(prescrib(ic)%rdofix)
                        err=(yload-xload)/yload
                        if(abs(err)<.02.or.err<-.05) cmesh=0
                    endif
                end do
            end if

            print *,'cmesh=',cmesh
            nremesh=nremesh+1
            print *,'nremesh=',nremesh
            if(nremesh>1)call result_store_of_fine_mesh
            if (cmesh==1)then
                nelc=0;nelc1=0
                call find_remesh_stran
                !call find_remesh_element1
                !if(rmesh==2) &
                !call find_remesh_element2
                !write(7,*)'nelc=',nelc,'nelc1=',nelc1
                !if(nelc/=0) &
                !write(7,*)'listnelc=',listnelc
                call mesh_refine(nremesh)
                if(nelc/=0)deallocate(listnelc)
                if(nelc1/=0)deallocate(listnelc1)
            endif
        endif !!2004/7/12
    end do    !iblks

    !20231215YL
    !&  等效线性动剪应力输出 yuanli20230926 !20231008
    if (restart==0.and.gamamax/=0) then
        call writegamamax
    endif

    if(type_problem=='F')then !20231009
        call out_gid_max
    endif
    !20231215YL


    end subroutine process_analysis  !20190810

    subroutine  parameter_back_analysis_read   !20190810

    implicit none
    integer             I, J,k,nincs_pb,nstep_pb,ivalue_point,i0,inode,idofn,jnode,nintf
    INTEGER             nvalue,mvalue_point,k0,observ_pb,iobse,ndofn,ivalue,i1,j1,j0,ibstep
    INTEGER,allocatable::listdofn(:)
    real(irk)           dtime_pb,ttime_pb
    real(irk),allocatable::obs_value(:)


    read(back_ctl_unit,*)text
    read(back_ctl_unit,*)Npara  !20230523


    allocate(Xvalue(Npara),Para_back(Npara))  !20230523
    read(back_ctl_unit,*)text
    do i=1,Npara
        read(back_ctl_unit,*)j,para_back(i)%imat,para_back(i)%name,para_back(i)%factor,  &
            para_back(i)%factor_inc,para_back(i)%mode_transform
    enddo
    read(back_ctl_unit,*)text
    read(back_ctl_unit,*)eps,iter1,iter2,rs,jac_eps
    read(back_ctl_unit,*)text  !待反演参数初始值
    read(back_ctl_unit,*)Xvalue

    write(7,*)'xvalue=',xvalue
    write(7,*)'eps,iter1,iter2,rs,jac_eps=',eps,iter1,iter2,rs,jac_eps

    end subroutine parameter_back_analysis_read  !20190810

    subroutine  trust_region_back_analysis_read  !20220108

    implicit none
    integer             I, J,k,nincs_pb,nstep_pb,ivalue_point,i0,inode,idofn,jnode,nintf
    INTEGER             nvalue,mvalue_point,k0,observ_pb,iobse,ndofn,ivalue,j0,i1,j1,ibstep
    INTEGER,allocatable::listdofn(:)
    real(irk)           dtime_pb,ttime_pb
    real(irk),allocatable::obs_value(:)


    allocate(trustp(1))
    read(back_ctl_unit,*)text
    read(back_ctl_unit,*)Npara  !20230523


    allocate(Xvalue(Npara),Para_back(Npara))  !20230523
    read(back_ctl_unit,*)text

    do i=1,Npara
        read(back_ctl_unit,*)j,para_back(i)%imat,para_back(i)%name,para_back(i)%factor,  &
            para_back(i)%factor_inc,para_back(i)%mode_transform
    enddo

    read(back_ctl_unit,*)text
    print *,text
    read(back_ctl_unit,*)trustp(1)%eta1,trustp(1)%eta2,   &
        trustp(1)%gama1,trustp(1)%gama2,trustp(1)%eps,  &
        trustp(1)%eta01,trustp(1)%eta02,trustp(1)%delta0, &
        trustp(1)%deltab,trustp(1)%mtter
    read(back_ctl_unit,*)text  !待反演参数初始值
    read(back_ctl_unit,*)Xvalue


    end subroutine trust_region_back_analysis_read  !20220108

    subroutine  parameter_back_analysis_verify_read   !20200813

    implicit none
    integer             I, J,k0,k,tbstep,nincs_pb,nstep_pb,bblks
    !INTEGER             nvalue,mvalue_point,k0
    !DOUBLE PRECISION    value
    real    timebprecord,dtime_pb
    real,allocatable:: ruo(:,:),sigma_t(:)

    open(back_ctl_unit,file=probn(1:len1)//'.btl')
    open(observ_unit,file=probn(1:len1)//'.obsc')

    read(back_ctl_unit,*)text  !输入与Bparamete为负时的相关内容（给定随机变量参数，进行正分析计算，输出相关结果用于反演分析方法验证）

    read(back_ctl_unit,*)Npara,nback_point,nstoch
    print *,'Npara,nback_point,nstoch=',Npara,nback_point,nstoch
    tbstep=0
    nblks_pb=runblks
    allocate(para_block(Nblks_pb))
    rewind(mainunit)
    do i=1,nblks_pb
        read(mainunit,*)text
        read(mainunit,*)nincs_pb
        para_block(i)%nincs_pb=nincs_pb
        allocate(para_block(i)%para_nincs(nincs_pb))
        timebprecord=0.
        do j=1,nincs_pb
            read(mainunit,*)k0,dtime_pb,k0,k0,nstep_pb
            read(mainunit,*)text
            para_block(i)%para_nincs(j)%nstep_pb=nstep_pb
            tbstep=tbstep+nstep_pb
            allocate(para_block(i)%para_nincs(j)%time_bp(nstep_pb))
            do k=1,nstep_pb
                timebprecord=timebprecord+dtime_pb
                para_block(i)%para_nincs(j)%time_bp(k)=timebprecord
            end do
        end do
    end do


    allocate(Para_back(Npara),freedom_for_back(4,nback_point))
    allocate(Xvalue(Npara),mean_value(Npara),sigma_value(Npara),para_stoch(npara,nstoch))

    read(back_ctl_unit,*)text
    print *,text
    do i=1,Npara
        read(back_ctl_unit,*)j,para_back(i)%imat,para_back(i)%name,para_back(i)%factor,para_back(i)%mode_transform
    enddo

    read(back_ctl_unit,*)text
    read(back_ctl_unit,*)mean_value  !随机变量均值
    read(back_ctl_unit,*)sigma_value !随机变量离散系数
    do i=1,Npara
        sigma_value(i)=sigma_value(i)*mean_value(i)
    end do
    if(nstoch==1)then !20210805
        para_stoch(:,1)=mean_value
    else !20210805
        do i=1,Npara
            call vsl_gauss_gen_single(nstoch,mean_value(i),sigma_value(i),para_stoch(i,:))
        end do
    endif !20210805

    write(7,*)'蒙特卡洛分析随机抽样参数生成结果'
    do i=1,nstoch
        write(7,10)i,para_stoch(1:Npara,i)
    end do

    allocate(ruo(npara,npara),sigma_t(npara))
    ruo=0.
    do i=1,npara
        xvalue(i)=sum(para_stoch(i,:))
        xvalue(i)=xvalue(i)/nstoch
    end do

    sigma_t=0.
    do i=1,npara
        do j=1,nstoch
            sigma_t(i)=sigma_t(i)+(para_stoch(i,j)-xvalue(i))**2
        end do
    end do

    !write(7,*)'sigma_t=',sigma_t
    if(nstoch>1)then  !20210805
        do i=1,npara
            do j=1,npara
                do k=1,nstoch
                    ruo(i,j)=ruo(i,j)+(para_stoch(i,k)-xvalue(i))*(para_stoch(j,k)-xvalue(j))
                    !if(i==2.and.j==3)write(7,*)'ruo(i,j)=',ruo(i,j)
                end do
                ruo(i,j)= ruo(i,j)/sqrt(sigma_t(i)*sigma_t(j))
            end do
        end do

        do i=1,npara
            sigma_t(i)=sigma_t(i)/(nstoch-1)
            sigma_t(i)=sqrt(sigma_t(i))
        end do
    endif !20210805


    write(7,*)'模拟数据均值与与给定值比较'
    write(7,11)mean_value  !随机变量均值
    write(7,11)xvalue
    write(7,*)'模拟数据方差与与给定值比较'
    write(7,11)sigma_value  !随机变量均值
    write(7,11)sigma_t
    write(7,*)'相关系数'
    do i=1,npara
        write(7,11)ruo(i,:)
    end do


    deallocate(ruo,sigma_t)


    read(back_ctl_unit,*)text
    do i=1,nback_point
        read(back_ctl_unit,*)k0,inode,idofn,jnode,bblks
        freedom_for_back(1,i)=inode
        freedom_for_back(2,i)=idofn
        freedom_for_back(3,i)=jnode
        freedom_for_back(4,i)=bblks
    end do

    write(7,*)'nback_point=',nback_point,'tbstep,nstoch=',tbstep,nstoch
    allocate(value_vc(nback_point,tbstep,nstoch))
    value_vc=99999.
    !write(7,*)'value_vc(nback_point,tbstep,nstoch)=',value_vc(nback_point,tbstep,nstoch)
10  format(i10,20e15.5)
11  format(20e15.5)

    end subroutine parameter_back_analysis_verify_read   !20200813


    subroutine  observe_back_analysis_read  !20230523

    implicit none
    integer             I, J,k,nincs_pb,nstep_pb,ivalue_point,i0,j0,inode,idofn,jnode,nintf
    INTEGER             nvalue,mvalue_point,k0,observ_pb,iobse,ndofn,ivalue,i1,j1,ibstep,  &
        ix,jvalue,begin_day_obs,dstep_pb,dtime_pb, &
        begin_day_pb,end_day_pb,ttime_pb   !20230709
    INTEGER,allocatable::listdofn(:)
    DOUBLE PRECISION    value

    real(irk),allocatable::obs_value(:)
    ! ttime_pb,dtime_pb的单位为天，所以实际工程反分析时将这两个变量按整数处理。

    !open(observ_unit,file=probn(1:len1)//'.obs')
    !read(back_ctl_unit,*)text  !输入与Bparameter/=0时的相关内容（不为零时，执行参数优化反演）
    tbstep=0
    ttime_pb=0.
    mobstimes=0
    Mvalue=0
    read(observ_unit,*)text
    read(observ_unit,*)Nblks_pb  !20230523
    allocate(para_block(Nblks_pb))  !20230523

    do iblks=1,Nblks_pb
        read(observ_unit,*)text
        read(observ_unit,*) nincs_pb
        para_block(iblks)%nincs_pb=nincs_pb
        allocate(para_block(iblks)%para_nincs(nincs_pb))
        do i=1,nincs_pb
            read(observ_unit,*) dtime_pb,nstep_pb,observ_pb,begin_day_pb,end_day_pb  !20230924
            dstep_pb=1
            tbstep=tbstep+nstep_pb !20230719
            para_block(iblks)%para_nincs(i)%nstep_pb=nstep_pb
            para_block(iblks)%para_nincs(i)%dtime_pb=dtime_pb
            para_block(iblks)%para_nincs(i)%dstep_pb=dstep_pb
            para_block(iblks)%para_nincs(i)%begin_day_pb=begin_day_pb
            para_block(iblks)%para_nincs(i)%end_day_pb=end_day_pb
            para_block(iblks)%para_nincs(i)%mvalue_point=Npoints_pbx
            mvalue_point=Npoints_pbx
            allocate(para_block(iblks)%para_nincs(i)%time_bp(nstep_pb),  &
                para_block(iblks)%para_nincs(i)%tstep_bp(nstep_pb,observ_pb),  &
                para_block(iblks)%para_nincs(i)%list_point_pb(mvalue_point))

            do j=1,Npoints_pbx
                para_block(iblks)%para_nincs(i)%list_point_pb(j)=j
            end do

            do j=1,nstep_pb,dstep_pb !20230719
                ttime_pb=begin_day_pb+dtime_pb*j*dstep_pb !20230924
                para_block(iblks)%para_nincs(i)%time_bp(j)=ttime_pb
                do i0=1,observ_pb
                    mobstimes=mobstimes+1
                    para_block(iblks)%para_nincs(i)%tstep_bp(j,i0)=mobstimes
                end do
            end do  !j
            do j=1,Npoints_pbx
                Mvalue=mvalue+((nstep_pb-1)/dstep_pb+1)*observ_pb   !20230719
            end do
        end do !i
    end do  !iblks

    allocate(Value_observ(Mvalue))

    read(observ_unit,*)text
    print *,'text=',text
    allocate(obs_value(tbstep))
    ivalue=0

    do j=1,Npoints_pbx

        !begin_day_obs=para_points(j)%begin_day_obs

        do j0=1,observ_pb
            read(observ_unit,*)ix,i1,j1,begin_day_obs    !对应测点点号，方向号
            !print *,'j=','j0=',j0,'i1=',i1,'j1=',j1
            read(observ_unit,*)obs_value

            ibstep=0   !20230902
            do iblks=1,Nblks_pb
                nincs_pb=para_block(iblks)%nincs_pb
                do iincs=1,nincs_pb
                    nstep_pb=para_block(iblks)%para_nincs(iincs)%nstep_pb
                    jvalue=0
                    do istep=1,nstep_pb,dstep_pb  !20230719
                        ibstep=ibstep+1  !20230902
                        ivalue=ivalue+1
                        !if(begin_day_obs==para_block(iblks)%para_nincs(iincs)%time_bp(istep))   &
                        if(begin_day_obs==ibstep) &
                            jvalue=ivalue   !20230924
                        Value_observ(ivalue)%iblks=iblks
                        Value_observ(ivalue)%iincs=iincs
                        Value_observ(ivalue)%istep=istep
                        Value_observ(ivalue)%iobse=j0
                        Value_observ(ivalue)%idofn=para_points(j)%listdofn(1)
                        Value_observ(ivalue)%ivalue_point=j
                        if(Value_observ(ivalue)%idofn<=ndimn)  & !20230709
                            Value_observ(ivalue)%jvalue=jvalue  !20230709

                        Value_observ(ivalue)%ic=1
                        if(abs(obs_value(ibstep)-99999.)<.01)Value_observ(ivalue)%ic=0   !20230902

                        if(Value_observ(ivalue)%idofn<=ndimn.and.(ivalue==jvalue))  &
                            Value_observ(ivalue)%ic=0   !20230709

                        Value_observ(ivalue)%value_measure=obs_value(ibstep)  !20230902


                        if(balgor/=0) then !20220108
                            allocate(Value_observ(ivalue)%dudx(npara))
                            Value_observ(ivalue)%dudx=0.
                        endif
                    end do  !istep
                end do  !iincs
            end do !iblks
        end do !j0
    end do !j

    deallocate(obs_value)
    if(Bparameter==1.or.Bparameter==2)then
        allocate(Fvec(Mvalue),Fvec1(Mvalue),Fvec2(Mvalue),FJAC (Mvalue,Npara))
        fvec=0.
        fjac=0.
    endif
    !

    print *,'mvalue=',mvalue


    end subroutine observe_back_analysis_read  !20230523


    SUBROUTINE stab_initialize

    character(10) fieldid,class,name,material
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index,icr

    if(ninit/=0)stop 'stop for ninit/=0!!'

    result_zero=0.

    DO igroup =1,ngroup   ! --1
        if (appear(igroup)>0) then
            ! get information from the group level
            fieldid=group(igroup)%fieldid
            class  =group(igroup)%class
            !         if (fieldid(1:1)=='U'.and.class=='CO')then
            if (fieldid(1:1)=='U')then !--2
                matno = group(igroup)%matno
                index = group(igroup)%index
                name  =props(matno)%name
                material=props(matno)%mechanical%solid%material
                icr=0
                if(material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(ice0(ielem)==1) goto 100
                    element(ielem)%field(1)%gpvar0=0.
                    element(ielem)%field(1)%gpvar=0.
                    !!contact
100                 continue
                end do
            endif
        endif !--2
    end do !--1

    end SUBROUTINE stab_initialize

    SUBROUTINE back_analysis  !20150925

    logical logx
    character(80)text
    integer(ink) itotv,ielem,irst,trstep0,ipoin,idofn,ij,idofix,ldofix,idelgroup,i0,ipairs,k
    real   (irk) xtime,time_begin,detal,ttime0,coef,xij,qi,qerr,qabs
    real   (irk) dispoint0,dispoint1,tQerr,tQabs,dispoint1g,dispoint0g  !20210726
    real   (irk) dis2e,diser,kmodu

    real   (irk),allocatable::rvectorm(:),value(:)
    integer(ink) iintf,nintf,iieq,igapbf,mdism   !!int2000

    integer(ink) i,iincs_i,iblks_i,istep_i,inode,jnode,ivalue,ivalue_point,bblks  !20230523
    integer(ink),pointer::listf(:)  !20200819
    real   (irk),pointer::rintf(:)  !20200819


    integer(ink) igapb,npgblock,jpoin,igaps,ipair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,npairs,cwater,jgaps,jpair,kdimn,jpoin0,itotv0   !!ctt2005
    real   (irk),allocatable::rot(:,:),tofor0(:),uireact(:,:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:) !!ctt2005

    if (meshc==1.or.rmesh/=0)rewind(mainunit)
    if(Bparameter/=0.and.iblks==1)rewind(mainunit)  !20190810

    !read(observ_unit,*)text


    read(mainunit,*)text
    read(mainunit,*)nincs

    print *,' in back_analysis'
    tQerr=0.;tQabs=0.

    if(ngaps/=0.or.nrcsteel/=0)allocate(tofor0(ntotv)) !!ctt2005

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    xtime=0.0
    do iincs=lincs+1,nincs
        print *,'iincs=',iincs

        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            allocate(coef_water(delgroup,nstep))
            do idelgroup=1,delgroup
                read(mainunit,*)i0,coef_water(idelgroup,:)
            end do
        end if


        ttime0=ttime
        trstep0=trstep
        !if(nbackf/=0) & !20210726,20230430
        !read(mainunit,*)text

        do istep=inc_step,nstep,inc_step

            if(iblks>=stab_matde)call stab_initialize

            write(chkunit,*)'Increment step=',istep
            if(nbackf/=0)trstep=trstep0+istep  !20220101
            if(outintr>0.and.iblks>=outintr)trstep=trstep0+istep  !20200226
            xtime=ditime*istep
            ttime=ttime0+ditime*istep !! only for output

            result_zero=0.0  !201605
            do igapb=1,ngapb
                if(gapb(igapb)%nrdof/=0)gapb(igapb)%rdisp_zero=0.
            end do


            do igaps=1,ngaps   !20190810
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs
                    if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                    gaps(igaps)%dxyz0(:,ipairs)=0.
                    gaps(igaps)%dxyz(:,ipairs)=0.
                    gaps(igaps)%ctforce0(:,ipairs)=0.
                    gaps(igaps)%ctforce(:,ipairs)=0.
                end do
            end do   !20190810
            call gpvar_initial  !201605

            if(nbackf/=0)then  !20210804
                do idofn=1,nbackf  !20210804
                    mdism=backf(idofn)%mdism
                    backf(idofn)%ic=1
                    do i0=1,mdism
                        if(abs(backf(idofn)%dism(i0,trstep)-99999.)<.01) &  !20220101
                            backf(idofn)%ic(i0)=0
                    end do
                enddo !20210804
            endif  !20210804


            call dfact_time_curve(ttime)
            call modf_var_prescribed

            call gravity
            if(rmesh>0)call gravity1
            if(rmesh>1)call gravity2
            write(7,*)'cwater=',cwater,'delgroup=',delgroup
            if(cwater/=0.and.delgroup/=0)call step_water_pressure  !2013/3/18

222         call force_external
            !if(iblks/=1)mdiv=1   !5
            if(type_load=='LOAD2')mdiv=2  !!806
            do idiv=1,mdiv
                !! temperature
                if(type_load=='LOAD2'.and.idiv==2) goto 71
                call load_of_creep_and_temperature
                call creep_strain_of_rock_fill    !20130510
71              if(mdiv/=1)toform=toforl+(tofor-toforl)*idiv/mdiv
                if(type_load=='DISCONTROL')preact0=prescrib(1)%rdofix
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv==1)tofor0=tofor !!ctt2005
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv/=1)tofor0=toform !!ctt2005
                deltafi=0.0
                do igapb=1,ngapb !fzx  tcl
                    if(gapb(igapb)%nrdof==0)cycle
                    gapb(igapb)%rdisp_deltafi=0.
                enddo


                do iiter=1,miter
                    iccontact=0 !zhao 05/07/30
                    print *,'iblks=',iblks,'idiv=',idiv,'iiter=',iiter

                    call algort

                    if (iiter==1.or.(kstat==2.and.iiter.le.2))then
                        delitfi=0.0

                        call predict

                        do ielem=1,nelem   !!simo_rifai
                            if(associated(element(ielem)%alfa))element(ielem)%alfa=0.
                        end do  !!simo_rifai
                    endif


                    if(ikindks/=0) call strain_for_steel_bar !steel 2008
                    if (nlayer/=2)then

                        if (kresl/=0.or.kthmat/=0) then
                            if(kresl/=0)call stiff_u
                            if(kresl/=0.and.rmesh>0.and.nelem1>0)call stiff_u1
                            if(kresl/=0.and.rmesh>1.and.nelem2>0)call stiff_u2
                            if(neuman==1.and.((kstat==2.and.iiter==2).or.&
                                (kstat/=2.and.istep==inc_step.and.iiter==1)))call write_stiff_u
                            if(kthmat/=0)call htmatrx

                            if(type_solver=='PROFILE'.and.   &
                                (neuman==1.and.((kstat/=2.and.(istep/=1.or.iiter/=1)).or.(kstat==2.and.iiter.gt.2))))goto 1
                            if(type_solver/='JPCG')global_stiff1=0.0
                            if(nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                            if (type_solver=='JPCG'.and.outintr==0) then
                                do ielem=1,nelem
                                    element(ielem)%estif=0.0
                                end do
                            endif
                            call estif_assemble
                            if(ground_inf/=0) call semi_inf_space_assemble

                            if(nonsym==0)then !20240312 YL
                                do itotv=1,ntotv
                                    if (totveq(itotv)/=0)then
                                        if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                    endif
                                enddo
                            endif !20240312 YL

                        endif

                    else !if (nlayer/=2)then

                        if(kresl_layer1/=0.or.kresl_layer2/=0)call stiff_u
                        print *,'kresl_layer=',kresl_layer1,kresl_layer2
                        if(kresl_layer1/=0)global_stiff1(1:iseq(neq_layer1))=0.
                        if(kresl_layer2/=0)global_stiff1(iseq(neq_layer1)+1:iseq(neq))=0.
                        if(nonsym==1.and.kresl_layer1/=0)global_stiff2(1:iseq(neq_layer1))=0.
                        if(nonsym==2.and.kresl_layer2/=0)global_stiff2(iseq(neq_layer1)+1:iseq(neq))=0.

                        call estif_assemble

                        if(nonsym==0)then !20240312 YL
                            do itotv=1,ntotv
                                if (totveq(itotv)/=0)then
                                    if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                endif
                            enddo
                        endif !20240312 YL

                    endif !if (nlayer/=2)


1                   if(type_load=='LOAD2'.or.(kstat==2.and.iiter.le.2).or.(type_load/='LOAD2'.and.kstat/=2.and.iiter==1).or.  &
                        (ngaps/=0.and.istatec==0)) then	  !! for temperature 20130510
                        if(type_load=='LOAD2'.and.idiv==2)then  !20130510
                            deltafi=0.0
                            delitfi=0.0
                        endif
                        call gpvar2_initial
                        if (ninit/=0.and.(kinit==2.and.iincs==1)) then
                            call eload_initialize
                            call eload_initial_stress
                            if (kinit==2.and.iincs==1)then
                                call force_release
                                where(totveq==0)
                                    torel=0.0
                                endwhere
                            endif
                        endif

                        call eload_initialize

                        call residu_f

                        if(rmesh>0.and.nelem1>0)call residu_f1
                        if(rmesh>1.and.nelem2>0)call residu_f2
                        call eload_field
                        if(ground_inf/=0)call semi_inf_load
                        call force_internal
                    endif !for iiter==1 and istep==inc_step .and.idiv==1  temperature


                    if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv==1)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005
                    if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv/=1)call ctfor_to_tofor(tofor0,toform)  !!ctt2005
                    if(nrcsteel/=0.and.iiter==1.and.mdiv==1)call csfor_to_tofor(tofor0,tofor)  !!20210328
                    if(nrcsteel/=0.and.iiter==1.and.mdiv/=1)call csfor_to_tofor(tofor0,toform)  !!20210328

                    if (mdiv/=1) then
                        if(idiv==1.and.iiter==1.and.allocated(torel))toform=toform+torel  !!20210328
                    else
                        if(iiter==1.and.allocated(torel))tofor=tofor+torel !!20210328
                    endif


                    if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)  goto 2  !ctt2005 , change position!
                    if(type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR
                    if ((type_solver=='PROFILE'.or.type_solver=='PARDISO').and.kresl/=0)then
                        operation='FACTORIZE'
                        call solve
                    end if
2                   continue

                    logx=ngaps/=0.and.(iiter==1.and.istep==inc_step.and.iincs==(lincs+1)).and.iblks==iblks_bt
                    if (logx)then !ctt2005
                        if (restart_ctt==0)then !restart_ctt
                            kdimn=ndimn
                            if(block_stab==1)kdimn=3*(ndimn-1) !2015/11/17
                            allocate(rot(kdimn,kdimn))
                            rot=0.
                            do igapbf=1,nbackf
                                igapb=backf(igapbf)%groupb
                                npgblock=gapb(igapb)%npgblock
                                if(backf(igapbf)%mdism>npgblock*kdimn) allocate(uireact(backf(igapbf)%mdism,npgblock*kdimn))
                                gapb(igapb)%cmatrix=0.
                                do ipoin=1,npgblock
                                    igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                    ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                    ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                                    coef=1.
                                    if(ij==2)coef=-1.
                                    rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)  !2015/11/17
                                    if(kdimn>ndimn)then  !2015/11/17
                                        if(ndimn==2)rot(3,3)=1.
                                        if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                    endif
                                    allocate(unitl(kdimn),unitg(kdimn))
                                    do idimn=1,kdimn
                                        itotvbt=(ipoin-1)*kdimn+idimn
                                        unitl=0.
                                        unitl(idimn)=1.*coef
                                        unitg=transpose(rot).x.unitl  !2015/11/17
                                        rvector=0.
                                        call  unit_force_trans(igapbf,kdimn,ij,unitg,igaps,ipair,rvector)

                                        operation='SOLVE'
                                        call solve

                                        if(backf(igapbf)%mdism==npgblock*kdimn)then
                                            do kpoin=1,backf(igapbf)%mdism
                                                !jdimn=backf(igapbf)%listdim(kpoin)
                                                dispoint1=0.    !20210726
                                                nintf=backf(igapbf)%relat(kpoin)%nintf

                                                do iintf=1,nintf
                                                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                                                    dispoint1=dispoint1+result(jtotv)*backf(igapbf)%relat(kpoin)%rintf(iintf)
                                                end do
                                                jtotvbt=kpoin
                                                gapb(igapb)%cmatrix(jtotvbt,itotvbt)=dispoint1
                                            end do  !kpoin
                                        else if(backf(igapbf)%mdism>npgblock*kdimn)then
                                            do kpoin=1,backf(igapbf)%mdism
                                                !jdimn=backf(igapbf)%listdim(kpoin)
                                                !itotv=nodfn(jdimn,jpoin)
                                                dispoint1=0.    !20210726
                                                nintf=backf(igapbf)%relat(kpoin)%nintf
                                                do iintf=1,nintf
                                                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                                                    dispoint1=dispoint1+result(jtotv)*backf(igapbf)%relat(kpoin)%rintf(iintf)
                                                end do

                                                jtotvbt=kpoin
                                                uireact(jtotvbt,itotvbt)=dispoint1
                                            end do  !kpoin

                                        endif
                                    end do  !idimn
                                    deallocate(unitl,unitg)
                                end do  !ipoin

                                if(backf(igapbf)%mdism>npgblock*kdimn)then
                                    gapb(igapb)%uireact=uireact
                                    gapb(igapb)%cmatrix(1:npgblock*kdimn,1:npgblock*kdimn)=transpose(uireact).x.gapb(igapb)%uireact
                                    deallocate(uireact)
                                endif


                            end do  !igapb
                            call forAdirect_back_analysis !fzx !形成A矩阵


                            do igapb=1,ngapb
                                !write(7,*)'igapb=',igapb,'ntotv_bt=',gapb(igapb)%ntotv_bt,'camatrix='
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    !write(7,*)gapb(igapb)%cmatrix(itotvbt,:)
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo  !igapb

                            deallocate(rot)

                        elseif(restart_ctt==1)then !restart_ctt
                            call forAdirect_back_analysis !fzx !形成A矩阵
                            rewind(recttunit)
                            do igapb=1,ngapb
                                npgblock=gapb(igapb)%npgblock
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo
                        else !restart_ctt
                            write(*,*)'no such restart_ctt!!'
                            stop
                        endif !restart_ctt
                    endif  !!ctt2005


90                  format(10e12.5)
                    rvector=0.0
                    !write(7,*)'iiter=',iiter,'tofor,stfor,rvector='
                    if (type_solver/='JPCG') then
                        do itotv=1,ntotv
                            if (totveq(itotv)/=0)then
                                if (mdiv/=1)then
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        toform(itotv)-stfor(itotv)

                                else
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        tofor(itotv)-stfor(itotv)

                                    !write(7,*)itotv,tofor(itotv),stfor(itotv), rvector(totveq(itotv))
                                endif
                            endif
                        end do

                        !!int2000
                        do itotv=1,ntotv
                            nintf=trans(itotv)%nintf
                            if (nintf/=0) then
                                iieq=totveq(itotv)
                                if(iieq/=0)rvector(iieq)=0.
                                do iintf=1,nintf
                                    iieq=totveq(trans(itotv)%listf(iintf))
                                    if(iieq/=0)rvector(iieq)=rvector(iieq)+  &
                                        (tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                                end do
                            endif
                        end do
                        !!int2000

                    else !if (type_solver/='JPCG') then

                        if(mdiv/=1)rvector=toform-stfor
                        if(mdiv==1)rvector=tofor -stfor
                    endif


                    if (type_nl==8)then
                        if(kstat/=2)call bfgsr(iiter)
                        if(kstat==2)call bfgsr(iiter-1)
                    else
                        operation='SOLVE'
                        call solve
                    endif
                    result_zero_e=result_zero_e+result

                    if(ngaps/=0.and.iblks>=abs(iblks_bt))call solve_ctt_back_analysis  !!ctt2005

                    !write(7,*)'result='
                    !do itotv=1,ntotv
                    !write(7,*)itotv,result(itotv)
                    !end do


                    call TIME(char_time)
                    print *, 'time: ', char_time
                    write(chkunit,*)'time: ', char_time


                    call varupdate
                    call eload_initialize
                    call residu_f
                    if(rmesh>0.and.nelem1>0)call residu_f1
                    if(rmesh>1.and.nelem2>0)call residu_f2
                    if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then   !806
                        call eload_field
                        if(ground_inf/=0)call semi_inf_load

                        call reaction_prescribed


                        call conver_load
                        if(nchek==0) call conver_nodal_value

                        if(nchek==0)exit !tcl
                    endif !ep2010
10                  continue
                    print *,'miter=',miter,'iiter=',iiter
                end do   !! loop for iiter

                if(type_load/='LOAD2') &
                    call gpvarupdate

                if(rmesh>0.and.nelem1>0)call gpvarupdate1
                if(rmesh>1.and.nelem2>0)call gpvarupdate2
            end do    !! for idiv
            if(type_load=='LOAD2') &
                call gpvarupdate
            if(modf_dis_blocks(iblks)==1)call construction_dis_modify


100         toforl=tofor

            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
                call outputres !for output
            endif
            !if (kstab==0.) then
            if(nforce/=0.or.ngaps/=0)call force_interface
            !else
            if(kstab/=0.)call safety_factor
            !endif
            if (istep/noutf*noutf==istep)then
                !if(kstab==0.and.nforce/=0)call write_force_interface
                if(nforce/=0.or.ngaps/=0)call write_force_interface
                call out_full_write
                if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif

            do igapbf=1,nbackf
                write(7,*)'nodal number,direction,ratio,rigid_dis,elastic_dis'
                dis2e=0.;diser=0.
                qi=0.
                do kpoin=1,backf(igapbf)%mdism
                    if(backf(igapbf)%ic(kpoin)==0)cycle  !20230523
                    jdimn=backf(igapbf)%listdim(kpoin)
                    dispoint1=0.;dispoint1g=0.
                    nintf=backf(igapbf)%relat(kpoin)%nintf
                    do iintf=1,nintf
                        jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                        dispoint1=dispoint1+result_zero_e(jtotv)*backf(igapbf)%relat(kpoin)%rintf(iintf)
                        dispoint1g=dispoint1g+(result_zero(jtotv)-result_zero_e(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)

                    end do

                    qi=abs(dispoint1g/dispoint1)
                    !dis2e=dis2e+(dispoint1-dispoint1g)**2
                    !diser=diser+(backf(igapbf)%dism(kpoin,trstep)-dispoint1g)*(dispoint1-dispoint1g)
                    write(7,20)kpoin,jdimn,qi,dispoint1g,dispoint1
                end do
            end do

            !    kmodu=diser/dis2e
            !write(7,*)'kmodu=',kmodu

            do igapbf=1,nbackf
                write(7,*)'relative displacement error/nodal number,direction,relative error,u_observation,u_computation'
                qi=0.; Qerr=0.;Qabs=0.
                do kpoin=1,backf(igapbf)%mdism
                    if(backf(igapbf)%ic(kpoin)==0)cycle  !20210726
                    dispoint1=0.    !20210726
                    nintf=backf(igapbf)%relat(kpoin)%nintf
                    do iintf=1,nintf
                        !jtotv=trans(itotv)%listf(iintf)  !20231026
                        jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)    !20231026
                        dispoint1=dispoint1+result_zero(jtotv)*backf(igapbf)%relat(kpoin)%rintf(iintf)  !20231026
                    end do



                    qi=abs((backf(igapbf)%dism(kpoin,trstep)-dispoint1)/dispoint1)  !20220101
                    qerr=qerr+(backf(igapbf)%dism(kpoin,trstep)-dispoint1)**2 !20220101
                    qabs=qabs+dispoint1**2
                    write(7,20)kpoin,jdimn,qi,backf(igapbf)%dism(kpoin,trstep),dispoint1 !20220101

                end do
                tQerr=tQerr+Qerr;tQabs=tQabs+Qabs
                write(7,*)'step residual displacements (sum of squre),      Qerr=',qerr
                write(7,*)'step          displacements (sum of squre),      Qabs=',qabs
                write(7,*)'step  relative  displacementerror,root of (qerr/Qabs)=',sqrt(qerr/qabs)
            end do


            if(istep/nresta*nresta==istep)call resta_read_write(-1)

            if(Bparameter>0)then !20230523
                !Value_observ(:)%value_computation=0.
                do ivalue=1,mvalue
                    !if(Value_observ(ivalue)%ic==0)cycle
                    iblks_i=Value_observ(ivalue)%iblks
                    iincs_i=Value_observ(ivalue)%iincs
                    istep_i=Value_observ(ivalue)%istep
                    idofn =lmdofn(Value_observ(ivalue)%idofn)
                    ivalue_point=Value_observ(ivalue)%ivalue_point
                    if(iblks_i==iblks.and.iincs_i==iincs.and.istep_i==istep)then
                        nintf=para_points(ivalue_point)%nintf
                        listf=>para_points(ivalue_point)%listf
                        rintf=>para_points(ivalue_point)%rintf
                        if(Bparameter==1)Value_observ(ivalue)%value_computation=dot_product(rintf,result_zero(nodfn(idofn,listf)))
                        if(Bparameter==2)Value_observ(ivalue)%value_computation=dot_product(rintf,deltafi(listf))
                        nullify(listf,rintf)
                    endif
                end do
            endif   !20230523

            if(Bparameter<0)then !20200812
                tbstep=tbstep+1
                do i=1,nback_point

                    bblks=freedom_for_back(4,i)  !20230523
                    if(bblks>iblks)cycle !20230523

                    inode=freedom_for_back(1,i)
                    idofn=freedom_for_back(2,i)
                    jnode=freedom_for_back(3,i)
                    itotv=nodfn(lmdofn(idofn),inode)
                    if(jnode/=0)jtotv=nodfn(lmdofn(idofn),jnode)
                    if(Bparameter==-1)then
                        Value_vc(i,tbstep,istoch)=result_zero(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-result_zero(jtotv)
                    elseif(Bparameter==-2)then
                        Value_vc(i,tbstep,istoch)=deltafi(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-deltafi(jtotv)
                    end if
                end do
            endif  !20200812


        end do     !! loop for istep
        !if(kstab==0.and.(nforce/=0.or.ngaps/=0))call write_force_interface
        if(cwater/=0.and.delgroup>0)deallocate(coef_water)
    end do !!iincs
    write(7,*)'total residual displacements (sum of squre),      tQerr=',tqerr
    write(7,*)'total          displacements (sum of squre),      tQabs=',tqabs
    write(7,*)'total  relative  displacementerror,root of (tqerr/tQabs)=',sqrt(tqerr/tqabs)

20  format(2I10, 3e15.5)
    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI

    !if(ngaps/=0)deallocate(tofor0)  !!ctt2005

    END SUBROUTINE back_analysis  !20150925
    !!!
    SUBROUTINE back_d_analysis  !20210820

    logical logx
    character(80)text
    integer(ink) itotv,ielem,irst,trstep0,ipoin,idofn,ij,idofix,ldofix,idelgroup,i0,ipairs,k
    real   (irk) xtime,time_begin,detal,ttime0,coef,xij,qi,qerr,qabs
    real   (irk) dispoint0,dispoint1,tQerr,tQabs,dispoint1g,dispoint0g  !20210726
    real   (irk) dis2e,diser,kmodu

    real   (irk),allocatable::rvectorm(:),value(:)
    integer(ink) iintf,nintf,iieq,igapbf,mdism,jpoinx   !!int2000

    integer(ink) i,iincs_i,iblks_i,istep_i,inode,jnode,ivalue,ivalue_point,bblks  !20200819
    integer(ink),pointer::listf(:)  !20200819
    real   (irk),pointer::rintf(:)  !20200819


    integer(ink) igapb,npgblock,jpoin,igaps,ipair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,npairs,cwater,jgaps,jpair,kdimn,jpoin0,itotv0   !!ctt2005
    real   (irk),allocatable::rot(:,:),tofor0(:),uireact(:,:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:) !!ctt2005

    if (meshc==1.or.rmesh/=0)rewind(mainunit)
    if(Bparameter/=0.and.iblks==1)rewind(mainunit)  !20190810

    !read(observ_unit,*)text


    read(mainunit,*)text
    read(mainunit,*)nincs

    print *,' in back_d_analysis,trstep=',trstep
    tQerr=0.;tQabs=0.

    if(ngaps/=0.or.nrcsteel/=0)allocate(tofor0(ntotv)) !!ctt2005

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    xtime=0.0
    do iincs=lincs+1,nincs
        print *,'iincs=',iincs

        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            allocate(coef_water(delgroup,nstep))
            do idelgroup=1,delgroup
                read(mainunit,*)i0,coef_water(idelgroup,:)
            end do
        end if


        ttime0=ttime
        trstep0=trstep
        !if(nbackf/=0) & !20210726,20230430
        !read(mainunit,*)text

        do istep=inc_step,nstep,inc_step

            if(iblks>=stab_matde)call stab_initialize

            write(chkunit,*)'Increment step=',istep
            if(nbackf/=0)trstep=trstep0+istep  !20220101
            if(outintr>0.and.iblks>=outintr)trstep=trstep0+istep  !20200226
            xtime=ditime*istep
            ttime=ttime0+ditime*istep !! only for output

            result_zero=0.0  !201605
            do igapb=1,ngapb
                if(gapb(igapb)%nrdof/=0)gapb(igapb)%rdisp_zero=0.
            end do


            do igaps=1,ngaps   !20190810
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs
                    if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                    gaps(igaps)%dxyz0(:,ipairs)=0.
                    gaps(igaps)%dxyz(:,ipairs)=0.
                    gaps(igaps)%ctforce0(:,ipairs)=0.
                    gaps(igaps)%ctforce(:,ipairs)=0.
                end do
            end do   !20190810
            call gpvar_initial  !201605

            if(nbackf/=0)then  !20210804
                do idofn=1,nbackf  !20210804
                    mdism=backf(idofn)%mdism
                    backf(idofn)%ic=1
                    do i0=1,mdism
                        if(abs(backf(idofn)%dism(i0,trstep)-999.)<.01) & !20220101
                            backf(idofn)%ic(i0)=0
                    end do
                enddo !20210804
            endif  !20210804


            call dfact_time_curve(ttime)
            call modf_var_prescribed

            call gravity
            if(rmesh>0)call gravity1
            if(rmesh>1)call gravity2
            write(7,*)'cwater=',cwater,'delgroup=',delgroup
            if(cwater/=0.and.delgroup/=0)call step_water_pressure  !2013/3/18

222         call force_external
            !if(iblks/=1)mdiv=1   !5
            if(type_load=='LOAD2')mdiv=2  !!806
            do idiv=1,mdiv
                !! temperature
                if(type_load=='LOAD2'.and.idiv==2) goto 71
                call load_of_creep_and_temperature
                call creep_strain_of_rock_fill    !20130510
71              if(mdiv/=1)toform=toforl+(tofor-toforl)*idiv/mdiv
                if(type_load=='DISCONTROL')preact0=prescrib(1)%rdofix
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv==1)tofor0=tofor !!ctt2005
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv/=1)tofor0=toform !!ctt2005
                deltafi=0.0
                do igapb=1,ngapb !fzx  tcl
                    if(gapb(igapb)%nrdof==0)cycle
                    gapb(igapb)%rdisp_deltafi=0.
                enddo


                do iiter=1,miter
                    iccontact=0 !zhao 05/07/30
                    print *,'iblks=',iblks,'idiv=',idiv,'iiter=',iiter

                    call algort

                    if (iiter==1.or.(kstat==2.and.iiter.le.2))then
                        delitfi=0.0

                        call predict

                        do ielem=1,nelem   !!simo_rifai
                            if(associated(element(ielem)%alfa))element(ielem)%alfa=0.
                        end do  !!simo_rifai
                    endif


                    if(ikindks/=0) call strain_for_steel_bar !steel 2008
                    if (nlayer/=2)then

                        if (kresl/=0.or.kthmat/=0) then
                            if(kresl/=0)call stiff_u
                            if(kresl/=0.and.rmesh>0.and.nelem1>0)call stiff_u1
                            if(kresl/=0.and.rmesh>1.and.nelem2>0)call stiff_u2
                            if(neuman==1.and.((kstat==2.and.iiter==2).or.&
                                (kstat/=2.and.istep==inc_step.and.iiter==1)))call write_stiff_u
                            if(kthmat/=0)call htmatrx

                            if(type_solver=='PROFILE'.and.   &
                                (neuman==1.and.((kstat/=2.and.(istep/=1.or.iiter/=1)).or.(kstat==2.and.iiter.gt.2))))goto 1
                            if(type_solver/='JPCG')global_stiff1=0.0
                            if(nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                            if (type_solver=='JPCG'.and.outintr==0) then
                                do ielem=1,nelem
                                    element(ielem)%estif=0.0
                                end do
                            endif
                            call estif_assemble
                            if(ground_inf/=0) call semi_inf_space_assemble

                            if(nonsym==0)then !20240312 YL
                                do itotv=1,ntotv
                                    if (totveq(itotv)/=0)then
                                        if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                    endif
                                enddo
                            endif !20240312 YL

                        endif

                    else !if (nlayer/=2)then

                        if(kresl_layer1/=0.or.kresl_layer2/=0)call stiff_u
                        print *,'kresl_layer=',kresl_layer1,kresl_layer2
                        if(kresl_layer1/=0)global_stiff1(1:iseq(neq_layer1))=0.
                        if(kresl_layer2/=0)global_stiff1(iseq(neq_layer1)+1:iseq(neq))=0.
                        if(nonsym==1.and.kresl_layer1/=0)global_stiff2(1:iseq(neq_layer1))=0.
                        if(nonsym==2.and.kresl_layer2/=0)global_stiff2(iseq(neq_layer1)+1:iseq(neq))=0.

                        call estif_assemble

                        if(nonsym==0)then !20240312 YL
                            do itotv=1,ntotv
                                if (totveq(itotv)/=0)then
                                    if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                endif
                            enddo
                        endif !20240312 YL

                    endif !if (nlayer/=2)


1                   if(type_load=='LOAD2'.or.(kstat==2.and.iiter.le.2).or.(type_load/='LOAD2'.and.kstat/=2.and.iiter==1).or.  &
                        (ngaps/=0.and.istatec==0)) then	  !! for temperature 20130510
                        if(type_load=='LOAD2'.and.idiv==2)then  !20130510
                            deltafi=0.0
                            delitfi=0.0
                        endif
                        call gpvar2_initial
                        if (ninit/=0.and.(kinit==2.and.iincs==1)) then
                            call eload_initialize
                            call eload_initial_stress
                            if (kinit==2.and.iincs==1)then
                                call force_release
                                where(totveq==0)
                                    torel=0.0
                                endwhere
                            endif
                        endif

                        call eload_initialize

                        call residu_f

                        if(rmesh>0.and.nelem1>0)call residu_f1
                        if(rmesh>1.and.nelem2>0)call residu_f2
                        call eload_field
                        if(ground_inf/=0)call semi_inf_load
                        call force_internal
                    endif !for iiter==1 and istep==inc_step .and.idiv==1  temperature


                    if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv==1)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005
                    if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv/=1)call ctfor_to_tofor(tofor0,toform)  !!ctt2005
                    if(nrcsteel/=0.and.iiter==1.and.mdiv==1)call csfor_to_tofor(tofor0,tofor)  !!20210328
                    if(nrcsteel/=0.and.iiter==1.and.mdiv/=1)call csfor_to_tofor(tofor0,toform)  !!20210328

                    if (mdiv/=1) then
                        if(idiv==1.and.iiter==1.and.allocated(torel))toform=toform+torel  !!20210328
                    else
                        if(iiter==1.and.allocated(torel))tofor=tofor+torel !!20210328
                    endif


                    if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)  goto 2  !ctt2005 , change position!
                    if(type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR
                    if ((type_solver=='PROFILE'.or.type_solver=='PARDISO').and.kresl/=0)then
                        operation='FACTORIZE'
                        call solve
                    end if
2                   continue

                    logx=ngaps/=0.and.(iiter==1.and.istep==inc_step.and.iincs==(lincs+1)).and.iblks==iblks_bt
                    if (logx)then !ctt2005
                        if (restart_ctt==0)then !restart_ctt
                            kdimn=ndimn
                            if(block_stab==1)kdimn=3*(ndimn-1)
                            allocate(rot(kdimn,kdimn))
                            rot=0.
                            do igapbf=1,nbackf
                                igapb=backf(igapbf)%groupb
                                npgblock=gapb(igapb)%npgblock
                                if(backf(igapbf)%mdism>npgblock*kdimn) allocate(uireact(backf(igapbf)%mdism,npgblock*kdimn))
                                gapb(igapb)%cmatrix=0.
                                do ipoin=1,npgblock
                                    igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                    ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                    ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                                    jpoinx=gaps(igaps)%pairnode(ij,ipair)
                                    coef=1.
                                    !if(ij==2)coef=-1.  !20210820
                                    rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                                    if(kdimn>ndimn)then
                                        if(ndimn==2)rot(3,3)=1.
                                        if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                    endif
                                    allocate(unitl(kdimn),unitg(kdimn))
                                    do idimn=1,kdimn
                                        itotvbt=(ipoin-1)*kdimn+idimn
                                        unitl=0.
                                        unitl(idimn)=1.*coef
                                        unitg=unitl  !20210820
                                        !unitg=transpose(rot).x.unitl
                                        rvector=0.

                                        call  unit_dis_force_trans(igapb,jpoinx,kdimn,unitg,rvector)

                                        operation='SOLVE'
                                        call solve
                                        !write(7,*)'itotvbt=',itotvbt
                                        !write(7,*)'result=',result
                                        if(backf(igapbf)%mdism==npgblock*kdimn)then
                                            do kpoin=1,backf(igapbf)%mdism
                                                !jdimn=backf(igapbf)%listdim(kpoin)
                                                dispoint1=0.    !20230523
                                                nintf=backf(igapbf)%relat(kpoin)%nintf
                                                do iintf=1,nintf
                                                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                                                    dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                                                end do

                                                jtotvbt=kpoin
                                                !if(jpoin0==0)then
                                                gapb(igapb)%cmatrix(jtotvbt,itotvbt)=dispoint1
                                                !else
                                                !gapb(igapb)%cmatrix(jtotvbt,itotvbt)=dispoint1-dispoint0
                                                !endif
                                            end do  !kpoin
                                        else if(backf(igapbf)%mdism>npgblock*kdimn)then
                                            do kpoin=1,backf(igapbf)%mdism
                                                !jdimn=backf(igapbf)%listdim(kpoin)
                                                dispoint1=0.    !20230523
                                                nintf=backf(igapbf)%relat(kpoin)%nintf
                                                do iintf=1,nintf
                                                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                                                    dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                                                    !write(7,*)'kpoin=',kpoin,'jtotv=',jtotv,'result=',result(jtotv),'rintf=',backf(igapbf)%relat(kpoin)%rintf(iintf)
                                                end do

                                                jtotvbt=kpoin
                                                !if(jpoin0==0)then
                                                uireact(jtotvbt,itotvbt)=dispoint1  !20210726

                                                !write(7,*)'jtotvbt,itotvbt=',jtotvbt,itotvbt,'uireact=',uireact(jtotvbt,itotvbt)
                                                !   else
                                                !uireact(jtotvbt,itotvbt)=dispoint1-dispoint0    !20210726
                                                !endif
                                            end do  !kpoin

                                        endif
                                    end do  !idimn
                                    deallocate(unitl,unitg)
                                end do  !ipoin

                                if(backf(igapbf)%mdism>npgblock*kdimn)then
                                    gapb(igapb)%uireact=uireact
                                    gapb(igapb)%cmatrix(1:npgblock*kdimn,1:npgblock*kdimn)=transpose(uireact).x.gapb(igapb)%uireact
                                    deallocate(uireact)
                                endif


                            end do  !igapb
                            !call forAdirect_back_analysis !fzx !形成A矩阵


                            do igapb=1,ngapb
                                !write(7,*)'igapb=',igapb,'ntotv_bt=',gapb(igapb)%ntotv_bt,'camatrix='
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    !write(7,*)gapb(igapb)%cmatrix(itotvbt,:)
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo  !igapb

                            deallocate(rot)

                        elseif(restart_ctt==1)then !restart_ctt
                            call forAdirect_back_analysis !fzx !形成A矩阵
                            rewind(recttunit)
                            do igapb=1,ngapb
                                npgblock=gapb(igapb)%npgblock
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo
                        else !restart_ctt
                            write(*,*)'no such restart_ctt!!'
                            stop
                        endif !restart_ctt
                    endif  !!ctt2005


90                  format(10e12.5)
                    rvector=0.0
                    !write(7,*)'iiter=',iiter,'itotv,ieq,tofor,stfor,rvector='
                    if (type_solver/='JPCG') then
                        do itotv=1,ntotv
                            if (totveq(itotv)/=0)then
                                if (mdiv/=1)then
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        toform(itotv)-stfor(itotv)

                                else
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        tofor(itotv)-stfor(itotv)
                                    !if(abs(rvector(totveq(itotv)))>1.e-3) &
                                    !                   write(7,*)itotv,totveq(itotv),tofor(itotv),stfor(itotv), rvector(totveq(itotv))
                                endif
                            endif
                        end do

                        !!int2000
                        do itotv=1,ntotv
                            nintf=trans(itotv)%nintf
                            if (nintf/=0) then
                                iieq=totveq(itotv)
                                if(iieq/=0)rvector(iieq)=0.
                                do iintf=1,nintf
                                    iieq=totveq(trans(itotv)%listf(iintf))
                                    if(iieq/=0)rvector(iieq)=rvector(iieq)+  &
                                        (tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                                end do
                            endif
                        end do
                        !!int2000

                    else !if (type_solver/='JPCG') then

                        if(mdiv/=1)rvector=toform-stfor
                        if(mdiv==1)rvector=tofor -stfor
                    endif


                    if (type_nl==8)then
                        if(kstat/=2)call bfgsr(iiter)
                        if(kstat==2)call bfgsr(iiter-1)
                    else
                        operation='SOLVE'
                        call solve
                    endif
                    result_zero_e=result_zero_e+result   !20210820


                    if(ngaps/=0.and.iblks>=abs(iblks_bt))call solve_back_d_analysis  !!ctt2005



                    call TIME(char_time)
                    print *, 'time: ', char_time
                    write(chkunit,*)'time: ', char_time


                    call varupdate
                    call eload_initialize
                    call residu_f
                    if(rmesh>0.and.nelem1>0)call residu_f1
                    if(rmesh>1.and.nelem2>0)call residu_f2
                    if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then   !806
                        call eload_field
                        if(ground_inf/=0)call semi_inf_load

                        call reaction_prescribed


                        call conver_load
                        if(nchek==0) call conver_nodal_value

                        if(nchek==0)exit !tcl
                    endif !ep2010
10                  continue
                    print *,'miter=',miter,'iiter=',iiter
                end do   !! loop for iiter

                if(type_load/='LOAD2') &
                    call gpvarupdate

                if(rmesh>0.and.nelem1>0)call gpvarupdate1
                if(rmesh>1.and.nelem2>0)call gpvarupdate2
            end do    !! for idiv
            if(type_load=='LOAD2') &
                call gpvarupdate
            if(modf_dis_blocks(iblks)==1)call construction_dis_modify


100         toforl=tofor

            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
                call outputres !for output
            endif
            !if (kstab==0.) then
            if(nforce/=0.or.ngaps/=0)call force_interface
            !else
            if(kstab/=0.)call safety_factor
            !endif
            if (istep/noutf*noutf==istep)then
                !if(kstab==0.and.nforce/=0)call write_force_interface
                if(nforce/=0.or.ngaps/=0)call write_force_interface
                call out_full_write
                if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif

            do igapbf=1,nbackf
                write(7,*)'nodal number,direction,ratio,foundation_dis,dam_dis'
                dis2e=0.;diser=0.
                qi=0.
                do kpoin=1,backf(igapbf)%mdism
                    if(backf(igapbf)%ic(kpoin)==0)cycle  !20210726
                    jdimn=backf(igapbf)%listdim(kpoin)
                    dispoint1=0.;dispoint1g=0.   !20230523  20231026
                    nintf=backf(igapbf)%relat(kpoin)%nintf
                    do iintf=1,nintf
                        jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                        dispoint1=dispoint1+result_zero_e(jtotv)*backf(igapbf)%relat(kpoin)%rintf(iintf)
                        dispoint1g=dispoint1g+(result_zero(jtotv)-result_zero_e(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                    end do

                    dispoint1g=backf(igapbf)%dism(kpoin,trstep)-dispoint1  !20231026

                    qi=dispoint1g/dispoint1
                    !dis2e=dis2e+dispoint1**2
                    !diser=diser+(backf(igapbf)%dism(kpoin,trstep)-dispoint1g)*dispoint1

                    write(7,20)kpoin,jdimn,qi,dispoint1g,dispoint1
                end do
            end do

            !    kmodu=diser/dis2e
            !write(7,*)'kmodu=',kmodu

            do igapbf=1,nbackf
                write(7,*)'relative displacement error/nodal number,direction,relative error,u_observation,u_computation'
                qi=0.; Qerr=0.;Qabs=0.
                do kpoin=1,backf(igapbf)%mdism
                    if(backf(igapbf)%ic(kpoin)==0)cycle  !20210726
                    jdimn=backf(igapbf)%listdim(kpoin)
                    dispoint1=0.    !20230523
                    nintf=backf(igapbf)%relat(kpoin)%nintf
                    do iintf=1,nintf
                        jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                        dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                    end do


                    qi=abs((backf(igapbf)%dism(kpoin,trstep)-dispoint1)/dispoint1) !20220101
                    qerr=qerr+(backf(igapbf)%dism(kpoin,trstep)-dispoint1)**2  !20220101
                    qabs=qabs+dispoint1**2
                    write(7,20)kpoin,jdimn,qi,backf(igapbf)%dism(kpoin,trstep),dispoint1 !20220101

                end do
                tQerr=tQerr+Qerr;tQabs=tQabs+Qabs
                write(7,*)'step residual displacements (sum of squre),      Qerr=',qerr
                write(7,*)'step          displacements (sum of squre),      Qabs=',qabs
                write(7,*)'step  relative  displacementerror,root of (qerr/Qabs)=',sqrt(qerr/qabs)
            end do


            if(istep/nresta*nresta==istep)call resta_read_write(-1)

            if(Bparameter>0)then !20230523
                !Value_observ(:)%value_computation=0.
                do ivalue=1,mvalue
                    !if(Value_observ(ivalue)%ic==0)cycle
                    iblks_i=Value_observ(ivalue)%iblks
                    iincs_i=Value_observ(ivalue)%iincs
                    istep_i=Value_observ(ivalue)%istep
                    idofn =lmdofn(Value_observ(ivalue)%idofn)
                    ivalue_point=Value_observ(ivalue)%ivalue_point
                    if(iblks_i==iblks.and.iincs_i==iincs.and.istep_i==istep)then
                        nintf=para_points(ivalue_point)%nintf
                        listf=>para_points(ivalue_point)%listf
                        rintf=>para_points(ivalue_point)%rintf
                        if(Bparameter==1)Value_observ(ivalue)%value_computation=dot_product(rintf,result_zero(nodfn(idofn,listf)))
                        if(Bparameter==2)Value_observ(ivalue)%value_computation=dot_product(rintf,deltafi(listf))
                        nullify(listf,rintf)
                    endif
                end do
            endif   !20230523

            if(Bparameter<0)then !20200812
                tbstep=tbstep+1
                do i=1,nback_point

                    bblks=freedom_for_back(4,i)  !20230523
                    if(bblks>iblks)cycle !20230523

                    inode=freedom_for_back(1,i)
                    idofn=freedom_for_back(2,i)
                    jnode=freedom_for_back(3,i)
                    itotv=nodfn(lmdofn(idofn),inode)
                    if(jnode/=0)jtotv=nodfn(lmdofn(idofn),jnode)
                    if(Bparameter==-1)then
                        Value_vc(i,tbstep,istoch)=result_zero(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-result_zero(jtotv)
                    elseif(Bparameter==-2)then
                        Value_vc(i,tbstep,istoch)=deltafi(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-deltafi(jtotv)
                    end if
                end do
            endif  !20200812


        end do     !! loop for istep
        !if(kstab==0.and.(nforce/=0.or.ngaps/=0))call write_force_interface
        if(cwater/=0.and.delgroup>0)deallocate(coef_water)
    end do !!iincs
    write(7,*)'total residual displacements (sum of squre),      tQerr=',tqerr
    write(7,*)'total          displacements (sum of squre),      tQabs=',tqabs
    write(7,*)'total  relative  displacementerror,root of (tqerr/tQabs)=',sqrt(tqerr/tqabs)

20  format(2I10, 3e15.5)
    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI
    !if(ngaps/=0)deallocate(tofor0)  !!ctt2005

    END SUBROUTINE back_d_analysis  !20210820

    !!


    SUBROUTINE STATIC_U

    logical logx
    character(80)text
    integer(ink) i,itotv,ielem,irst,trstep0,ipoin,idofn,ij,ij0,idofix,ldofix,idelgroup,i0,ipairs
    real   (irk) xtime,time_begin,detal,ttime0,coef
    real   (irk),allocatable::rvectorm(:),value(:)
    integer(ink) iintf,nintf,iieq,njntf,bblks   !!int2000
    integer(ink) iincs_i,iblks_i,istep_i,inode,jnode,ivalue,ivalue_point  !20200819
    integer(ink),pointer::listf(:)  !20200819
    real   (irk),pointer::rintf(:)  !20200819

    integer(ink) igapb,npgblock,jpoin,igaps,ipair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,npairs,cwater,jgaps,jpair,kdimn   !!ctt2005
    real   (irk),allocatable::rot(:,:),tofor0(:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:) !!ctt2005

    if (meshc==1.or.rmesh/=0)rewind(mainunit)
    if(Bparameter/=0.and.iblks==1)rewind(mainunit)  !20230902
    if(Bparameter/=0.and.iblks==1)rewind(upliftunit)


    if (.not. yl_input_enabled) read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)text
    if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_MAN_STATIC_U_title_1,0)
    if (.not. yl_input_enabled) read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)nincs; if (yl_input_enabled) call yl_modern_step_controls(nincs,miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic)
    if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_MAN_STATIC_U_nincs,0)
    call diag_range(RD_MAN_STATIC_U_nincs,0,'nincs',int(nincs,i8),1_i8,diag_max_entities())   ! M1-03: increment loop bound
    call diag_flush_stage()

    print *,' in static_U**'

    if (yl_dump_enabled) call yl_state_dump('phase_ready(1)')
    if(ngaps/=0.or.nrcsteel/=0)allocate(tofor0(ntotv)) !!ctt2005

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            do idelgroup=1,delgroup
                read(mainunit,*)text
            end do
        end if
        if(Qstatic/=0) then !20221104
            do i0=1,6
                read(mainunit,*)text
            end do
        endif

    end do

    xtime=0.0
    !write(7,*)'iffix(nodfn(1:3,25))=',iffix(nodfn(1:3,25))

    do iincs=lincs+1,nincs
        print *,'iincs=',iincs,'lincs=',lincs

        if (.not. yl_input_enabled) read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic; if (yl_input_enabled) call yl_modern_step_controls(nincs,miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic)
        if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_MAN_STATIC_U_increment_control,iincs)
        call diag_range(RD_MAN_STATIC_U_increment_control,iincs,'miter',int(miter,i8),1_i8,diag_max_entities())   ! M1-03: loop bounds
        call diag_range(RD_MAN_STATIC_U_increment_control,iincs,'nstep',int(nstep,i8),1_i8,diag_max_entities())
        call diag_range(RD_MAN_STATIC_U_increment_control,iincs,'inc_step',int(inc_step,i8),1_i8,diag_max_entities())
        call diag_flush_stage()
        if (.not. yl_input_enabled) read(mainunit,*,iostat=yl_ios,iomsg=yl_msg)toler_force,toler_var(1:mdofn); if (yl_input_enabled) call yl_modern_tolerances(toler_force)
        if (.not. yl_input_enabled) call diag_check_read(yl_ios,yl_msg,RD_MAN_STATIC_U_tolerances,iincs)
        if(cwater/=0.and.delgroup>0)then
            allocate(coef_water(delgroup,nstep))
            do idelgroup=1,delgroup
                read(mainunit,*)i0,coef_water(idelgroup,:)
            end do
        end if


        if(Qstatic/=0) then !20221104
            read(mainunit,*)text  !20221104
            allocate(qstatic_force)  !20221104
            allocate(qstatic_force%appearg(ngroup),qstatic_force%qfactor(ndimn),qstatic_force%cor_coef(2,Qstatic))
            read(mainunit,*)qstatic_force%iaxe
            read(mainunit,*)qstatic_force%appearg
            read(mainunit,*)qstatic_force%qfactor
            read(mainunit,*)qstatic_force%cor_coef(1,:)
            read(mainunit,*)qstatic_force%cor_coef(2,:)
        endif !20221104

        print *,'cwater,Qstatic=',cwater,Qstatic

        if (yl_dump_enabled) call yl_state_dump('increment_ready(1,1)')
        ttime0=ttime
        trstep0=trstep
        do istep=inc_step,nstep,inc_step

            if(iblks>=stab_matde)call stab_initialize

            write(chkunit,*)'Increment step=',istep
            print *,'istep=',istep
            if(outintr>0.and.iblks>=outintr)trstep=trstep0+istep !20200226
            xtime=ditime*istep
            ttime=ttime0+ditime*istep !! only for output

            call dfact_time_curve(ttime)
            call modf_var_prescribed

            call saturation_judge  !20220409

            print *,'tcurvegravity=',tcurvegravity
            call gravity
            if(rmesh>0)call gravity1
            if(rmesh>1)call gravity2
            write(7,*)'cwater=',cwater,'delgroup=',delgroup
            if(cwater/=0.and.delgroup/=0)call step_water_pressure  !2013/3/18

222         call force_external


            !if(iblks/=1)mdiv=1   !5
            if(type_load=='LOAD2')mdiv=2  !!806
            do idiv=1,mdiv
                !! temperature
                if(type_load=='LOAD2'.and.idiv==2) goto 71
                call load_of_creep_and_temperature
                call creep_strain_of_rock_fill    !20130510
                call wetting_strain_of_rock_fill  !20220409
71              if(mdiv/=1)toform=toforl+(tofor-toforl)*idiv/mdiv
                if(type_load=='DISCONTROL')preact0=prescrib(1)%rdofix
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv==1)tofor0=tofor !!ctt2005
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv/=1)tofor0=toform !!ctt2005
                deltafi=0.0
                do igapb=1,ngapb !fzx  tcl
                    if(gapb(igapb)%nrdof==0)cycle
                    gapb(igapb)%rdisp_deltafi=0.
                enddo

                if(submodel==1.and.idiv==1)call value_submodel_boundary  !20210321


                do iiter=1,miter
                    iccontact=0 !zhao 05/07/30
                    !print *,'iblks=',iblks,'idiv=',idiv,'iiter=',iiter
                    if (istep==inc_step.and.iiter==1)then
                        call local_stress
                        call contact_state(0)
                        !call crack_state !crack 2006
                    endif

                    call algort

                    if (iiter==1.or.(kstat==2.and.iiter.le.2))then
                        !deltafi_ssorpbcg=deltafi !ssorpbcg
                        !deltafi=0.0
                        delitfi=0.0
                        call predict
                        do ielem=1,nelem   !!simo_rifai
                            if(associated(element(ielem)%alfa))element(ielem)%alfa=0.
                        end do  !!simo_rifai
                    endif


                    if(ikindks/=0) call strain_for_steel_bar !steel 2008

                    call stran0_creep4   !20180630  (博格斯模型蠕变初应变增量，因为应力增量在变化，所以每一迭代步求解，只适用于NSOLN=5）
                    if(iiter==1)   call effect_stres_modul_for_steel_beam !20211125
                    if(iiter==1)   call stiffness_for_bolt_spring  !20211125

                    if (nlayer/=2)then

                        if (kresl/=0.or.kthmat/=0) then
                            if(kresl/=0)call stiff_u
                            if(kresl/=0.and.rmesh>0.and.nelem1>0)call stiff_u1
                            if(kresl/=0.and.rmesh>1.and.nelem2>0)call stiff_u2
                            if(neuman==1.and.((kstat==2.and.iiter==2).or.&
                                (kstat/=2.and.istep==inc_step.and.iiter==1)))call write_stiff_u
                            if(kthmat/=0)call htmatrx

                            if(type_solver=='PROFILE'.and.   &
                                (neuman==1.and.((kstat/=2.and.(istep/=1.or.iiter/=1)).or.(kstat==2.and.iiter.gt.2))))goto 1
                            if(type_solver/='JPCG')global_stiff1=0.0
                            if(nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                            if (type_solver=='JPCG'.and.outintr==0) then
                                do ielem=1,nelem
                                    element(ielem)%estif=0.0
                                end do
                            endif
                            call estif_assemble
                            if(nbspring>0) &       !20150925
                                call assemble_back_spring  !20150925
                            if(ground_inf/=0) call semi_inf_space_assemble  !20231010

                            if(nonsym==0)then !20240312 YL
                                do itotv=1,ntotv
                                    if (totveq(itotv)/=0)then
                                        if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                    endif
                                enddo
                            endif !20240312 YL

                        endif

                    else !if (nlayer/=2)then

                        if(kresl_layer1/=0.or.kresl_layer2/=0)call stiff_u
                        print *,'kresl_layer=',kresl_layer1,kresl_layer2
                        if(kresl_layer1/=0)global_stiff1(1:iseq(neq_layer1))=0.
                        if(kresl_layer2/=0)global_stiff1(iseq(neq_layer1)+1:iseq(neq))=0.
                        if(nonsym==1.and.kresl_layer1/=0)global_stiff2(1:iseq(neq_layer1))=0.
                        if(nonsym==2.and.kresl_layer2/=0)global_stiff2(iseq(neq_layer1)+1:iseq(neq))=0.

                        call estif_assemble

                        if(nonsym==0)then !20240312 YL
                            do itotv=1,ntotv
                                if (totveq(itotv)/=0)then
                                    if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                endif
                            enddo
                        endif !20240312 YL

                    endif !if (nlayer/=2)

1                   if(type_load=='LOAD2'.or.(kstat==2.and.iiter.le.2).or.(type_load/='LOAD2'.and.kstat/=2.and.iiter==1).or.  &
                        (ngaps/=0.and.istatec==0)) then	  !! for temperature 20130510
                        !if(type_load=='LOAD2'.and.idiv==2)then  !20130510  !20220607
                        ! deltafi=0.0
                        ! delitfi=0.0
                        ! endif
                        call gpvar2_initial
                        if (ninit/=0.and.(kinit==2.and.iincs==1.and.istep==1)) then  !20201203
                            call eload_initialize
                            call eload_initial_stress
                            call force_release
                            where(totveq==0)
                                torel=0.0
                            endwhere
                        endif !20201203


                        call eload_initialize
                        write(7,*)'residu_f1'
                        call residu_f  !!!!!!

                        if(rmesh>0.and.nelem1>0)call residu_f1
                        if(rmesh>1.and.nelem2>0)call residu_f2
                        call eload_field
                        if(nbspring>0) & !20150925
                            call eload_back_spring  !20150925
                        if(ground_inf/=0)call semi_inf_load
                        call force_internal
                    endif !for iiter==1 and istep==inc_step .and.idiv==1  temperature
                    if (mdiv/=1) then
                        if(idiv==1.and.iiter==1.and.allocated(torel))toform=toform+torel
                    else
                        if(iiter==1.and.allocated(torel))tofor=tofor+torel
                    endif

                    if(ngaps/=0.and.iblks>=iblks_bt.and.mdiv==1)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005
                    if(ngaps/=0.and.iblks>=iblks_bt.and.mdiv/=1)call ctfor_to_tofor(tofor0,toform)  !!ctt2005

                    if(nrcsteel/=0.and.mdiv==1)call csfor_to_tofor(tofor0,tofor)  !!20210328
                    if(nrcsteel/=0.and.mdiv/=1)call csfor_to_tofor(tofor0,toform)  !!20210328


                    if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)  goto 2  !ctt2005 , change position!
                    if(type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR
                    if ((type_solver=='PROFILE'.or.type_solver=='PARDISO').and.kresl/=0)then
                        operation='FACTORIZE'
                        call solve
                    end if
2                   continue

                    logx=ngaps/=0.and.(iiter==1.and.istep==inc_step).and.iincs==(lincs+1) !20200331
                    if (logx)then !ctt2005
                        if (restart_ctt==0)then !restart_ctt
                            kdimn=ndimn
                            if(block_stab==1)kdimn=3*(ndimn-1) !2015/11/17
                            allocate(rot(kdimn,kdimn))
                            rot=0.
                            do igapb=1,ngapb
                                if(block_appear_process(igapb,iblks)==0)cycle    !20200331
                                npgblock=gapb(igapb)%npgblock
                                gapb(igapb)%cmatrix=0.

                                if(gapb(igapb)%eblock==0) cycle  !2017/11/19
                                do ipoin=1,npgblock
                                    igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                    ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                    ij=gapb(igapb)%nodegblock_onetwo(ipoin)


                                    coef=1.
                                    if(ij==2)coef=-1.
                                    rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                                    if(kdimn>ndimn)then
                                        if(ndimn==2)rot(3,3)=1.
                                        if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                    endif

                                    allocate(unitl(kdimn),unitg(kdimn))
                                    do idimn=1,kdimn

                                        itotvbt=(ipoin-1)*kdimn+idimn
                                        unitl=0.
                                        unitl(idimn)=1.*coef


                                        unitg=transpose(rot).x.unitl
                                        rvector=0.
                                        call  unit_force_trans(igapb,kdimn,ij,unitg,igaps,ipair,rvector)

                                        operation='SOLVE'
                                        call solve


                                        do kpoin=1,npgblock
                                            jgaps=gapb(igapb)%nodegblock_igaps(kpoin)
                                            jpair=gapb(igapb)%nodegblock_ipairs(kpoin)
                                            ij0=gapb(igapb)%nodegblock_onetwo(kpoin)         !2017/04/03
                                            call result_node_to_center(kdimn,ij0,jgaps,jpair,result,unitg)

                                            do jdimn=1,kdimn
                                                jtotvbt=(kpoin-1)*kdimn+jdimn
                                                gapb(igapb)%cmatrix(jtotvbt,itotvbt)=unitg(jdimn)
                                            end do
                                        end do  !kpoin
                                    end do  !idimn
                                    deallocate(unitl,unitg)
                                end do  !ipoin

                                do ipoin=1,npgblock
                                    igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                    ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                    ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                                    coef=1.
                                    if(ij==2)coef=-1.
                                    rot=0.
                                    rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)

                                    if(kdimn>ndimn)then
                                        if(ndimn==2)rot(3,3)=1.
                                        !if(ndimn==3)rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                                        if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                        !if(ndimn==3)rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                                    endif

                                    rot=coef*rot

                                    allocate(cmatrixl(kdimn,kdimn))
                                    do jpoin=1,npgblock
                                        jtotv=(jpoin-1)*kdimn
                                        itotv=(ipoin-1)*kdimn
                                        cmatrixl=gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)
                                        gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)=   &
                                            rot.x.cmatrixl
                                    end do
                                    deallocate(cmatrixl)
                                end do
                            end do  !igapb
                            call forAdirect !fzx !形成A矩阵

                            do igapb=1,ngapb
                                !write(7,*)'igapb=',igapb,'ntotv_bt=',gapb(igapb)%ntotv_bt,'camatrix='
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    !write(7,*)gapb(igapb)%cmatrix(itotvbt,:)
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo  !igapb

                            deallocate(rot)

                        elseif(restart_ctt==1)then !restart_ctt
                            call forAdirect !fzx !形成A矩阵
                            rewind(recttunit)
                            do igapb=1,ngapb
                                npgblock=gapb(igapb)%npgblock
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo
                        else !restart_ctt
                            write(*,*)'no such restart_ctt!!'
                            call diag_abort('UNSUPPORTED',EXIT_UNSUPPORTED,'Fem.f90:static_u','no such restart_ctt (see write above)')   ! M1-03 R20
                        endif !restart_ctt
                    endif  !!ctt2005
                    !logx=nrcsteel/=0.and.(iiter==1.and.istep==inc_step).and.iincs==(lincs+1) !20220311
                    !if (logx) call cmatrix_c_formation !20210328

                    if(kresl/=0) & !20220311
                        call cmatrix_c_formation !20220311



90                  format(10e12.5)
                    rvector=0.0
                    !write(chkunit,*)'iiter=',iiter,'itotv ieq  tofor stfor'
                    !write(chkunit,*)'itotv=','ieq=','stif=','rvector='

                    if (type_solver/='JPCG') then
                        do itotv=1,ntotv
                            !if(abs(tofor(itotv)-stfor(itotv))>1.e-5) &

                            if (totveq(itotv)/=0)then
                                if (mdiv/=1)then
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        toform(itotv)-stfor(itotv)

                                else
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        tofor(itotv)-stfor(itotv)
                                    !if(abs(rvector(totveq(itotv)))>1.e-8)write(7,*)itotv,tofor(itotv),stfor(itotv)
                                    !write(7,*)itotv,tofor(itotv),stfor(itotv)
                                endif
                                if(nonsym==0)then !20240312 YL
                                    if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e20
                                endif !20240312 YL
                                !if(abs(rvector(totveq(itotv)))>1.e-8) &
                                !write(chkunit,52)itotv,totveq(itotv),global_stiff1(iseq(totveq(itotv))),rvector(totveq(itotv))


                            endif
                            !write(7,*)itotv,tofor(itotv),stfor(itotv)
                        end do
                        !stop
                        !!int2000

                        do itotv=1,ntotv
                            nintf=trans(itotv)%nintf
                            if (nintf/=0) then
                                do iintf=1,nintf
                                    iieq=totveq(trans(itotv)%listf(iintf))
                                    if(iieq/=0)rvector(iieq)=rvector(iieq)+  &
                                        (tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                                end do
                            endif
                        end do

                        !!int2000

                    else !if (type_solver/='JPCG') then

                        if(mdiv/=1)rvector=toform-stfor
                        if(mdiv==1)rvector=tofor -stfor
                    endif
52                  format(2I10,3e15.5)



                    if (type_load=='ARCLENGTH'.and.kresl/=0) then
                        allocate(rvectorm(neq))
                        rvectorm=rvector
                        rvector=0.0
                        if (type_solver/='JPCG') then
                            do itotv=1,ntotv
                                if(totveq(itotv)/=0) &
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+tofor_arclength(itotv)
                            end do
                        else
                            rvector=tofor_arclength
                        endif
                        operation='SOLVE'
                        call solve
                        delta_arclength=result
                        rvector=rvectorm
                        deallocate(rvectorm)
                    endif

                    !write(7,*)'idiv=',idiv,'iiter=',iiter
                    !write(7,*)'rvector=',rvector

                    if (type_nl==8)then
                        if(kstat/=2)call bfgsr(iiter)
                        if(kstat==2)call bfgsr(iiter-1)
                    else
                        operation='SOLVE'
                        call solve
                    endif

                    !write(7,*)'result=',result

                    if(ngaps/=0.and.iblks>=abs(iblks_bt))call solve_ctt  !!ctt2005
                    if(nrcsteel/=0) call solve_bond_force_of_cs !20210328

                    !
                    !write(7,*)'tofor***'
                    !do itotv=1,ntotv
                    !    if(abs(tofor(itotv))>1.e-3) &
                    !    write(7,*)itotv,tofor(itotv)
                    ! end do

                    if (type_load=='ARCLENGTH')then
                        call find_dfact_of_arclength (irst)
                        if (irst==1) then
                            time_begin=tcurves(arc_curve)%time_begin
                            detal=tcurves(arc_curve)%detal
                            if (abs(ttime-time_begin-ditime).le.1.e-8)detal=tcurves(arc_curve)%fact_inc
                            tcurves(arc_curve)%detal=detal*.5
                            if (abs(ttime-time_begin-ditime).le.1.e-8)tcurves(arc_curve)%fact_inc=detal*.5
                            goto 222
                        endif
                    endif

                    if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)call neuman_expan

                    call TIME(char_time)
                    print *, 'time: ', char_time
                    write(chkunit,*)'time: ', char_time


                    !write(7,*)'varupdate'
                    call varupdate
                    !write(7,*)'af varupdate'
                    call relative_dis_watertight !20231007 止水 !20240305
                    call eload_initialize

                    if(ikindks/=0) call strain_for_steel_bar !steel 2008
                    !write(7,*)'bbxx residu_f'
                    write(7,*)'residu_f2'
                    call residu_f

                    !write(7,*)'aaxx residu_f'
                    if(rmesh>0.and.nelem1>0)call residu_f1
                    if(rmesh>1.and.nelem2>0)call residu_f2
                    if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then   !806
                        call eload_field
                        if(nbspring>0) & !20150925
                            call   eload_back_spring  !20150925
                        if(ground_inf/=0)call semi_inf_load

                        call reaction_prescribed

                        call conver_load
                        if(nchek==0) call conver_nodal_value
                        if(type_load=='ARCLENGTH')tcurves(arc_curve)%piter=iiter

                        !!!!!!!!!!!!!!!!
                        !call local_stress
                        !call contact_state(1)

                        !**************************

                        !if(nchek==0.and.iccontact==1)exit
                        !!!!!!!!!!!!!!!
                        if(nchek==0)exit !tcl
                    endif !806
                    if(type_load=='LOAD2'.and.idiv==1) goto 10
                    print *,'miter=',miter,'iiter=',iiter
                end do   !! loop for iiter
10              continue

                if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then   !20220607
                    call local_stress
                    call contact_state(1)
                    !write(7,*)'gpvar1=',element(1)%field(1)%gpvar(1:6,1)
                    !if(type_load/='LOAD2') then   !20220607
                    if(istatec==0) &
                        call state_and_stiff_2021
                    !write(7,*)'icttstif_static_u=',icttstif
                    do igaps=1,ngaps
                        npairs=gaps(igaps)%npairs
                        do ipairs=1,npairs
                            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                            gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
                            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
                            gaps(igaps)%state0(ipairs)=gaps(igaps)%state(ipairs)
                            gaps(igaps)%damage0(ipairs)=gaps(igaps)%damage(ipairs)
                            gaps(igaps)%kxyz0(:,:,ipairs)=gaps(igaps)%kxyz(:,:,ipairs)
                        end do
                    end do
                    !endif   !20220607

                    !if(type_load/='LOAD2') &   !20220607
                    call gpvarupdate

                    if(rmesh>0.and.nelem1>0)call gpvarupdate1
                    if(rmesh>1.and.nelem2>0)call gpvarupdate2

                endif   !20220607
            end do    !! for idiv

            !if(type_load=='LOAD2') &   !20220607
            !call gpvarupdate   !20220607

            if(Blarge==1) then  !20221102
                call update_coord_blarge
                call modf_element_local_direction
            endif !20221102
            if(modf_dis_blocks(iblks)==1)call construction_dis_modify


            !if(type_load=='LOAD2') then   !20220607
            !if(istatec==0) &
            !              call state_and_stiff_2021
            !do igaps=1,ngaps
            !npairs=gaps(igaps)%npairs
            !do ipairs=1,npairs
            !     if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
            !    gaps(igaps)%state0(ipairs)=gaps(igaps)%state(ipairs)
            !   gaps(igaps)%damage0(ipairs)=gaps(igaps)%damage(ipairs)
            !   gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
            !   gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
            !   gaps(igaps)%kxyz0(:,:,ipairs)=gaps(igaps)%kxyz(:,:,ipairs)
            !end do
            !end do
            !    endif      !20220607


100         toforl=tofor

            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
                call outputres !for output
            endif


            !if (kstab==0.) then
            if(nforce/=0.or.ngaps/=0)call force_interface
            !else
            if(kstab/=0.)call safety_factor
            !endif
            if (istep/noutf*noutf==istep)then
                !if(kstab==0.and.nforce/=0)call write_force_interface
                if(nforce/=0.or.ngaps/=0)call write_force_interface

                call out_full_write
                if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif

            if(istep/nresta*nresta==istep)call resta_read_write(-1)

            if(Bparameter>0)then !20230523
                !Value_observ(:)%value_computation=0.
                do ivalue=1,mvalue
                    !if(Value_observ(ivalue)%ic==0)cycle
                    iblks_i=Value_observ(ivalue)%iblks
                    iincs_i=Value_observ(ivalue)%iincs
                    istep_i=Value_observ(ivalue)%istep
                    idofn =lmdofn(Value_observ(ivalue)%idofn)
                    ivalue_point=Value_observ(ivalue)%ivalue_point
                    if(iblks_i==iblks.and.iincs_i==iincs.and.istep_i==istep)then
                        nintf=para_points(ivalue_point)%nintf
                        listf=>para_points(ivalue_point)%listf
                        rintf=>para_points(ivalue_point)%rintf
                        if(Bparameter==1)Value_observ(ivalue)%value_computation=dot_product(rintf,result_zero(nodfn(idofn,listf)))
                        !if(ivalue_point==169)then  !20230717
                        !    write(7,*)'ivalue_point=',ivalue_point,'ivalue=',ivalue
                        !    write(7,*)'result_zero=',result_zero(nodfn(idofn,listf))
                        !    write(7,*)'rintf=',rintf
                        !    write(7,*)'value_computation=',Value_observ(ivalue)%value_computation
                        ! endif

                        if(Bparameter==2)Value_observ(ivalue)%value_computation=dot_product(rintf,deltafi(listf))
                        nullify(listf,rintf)
                    endif
                end do
            endif   !20230523

            if(Bparameter<0)then !20200812
                tbstep=tbstep+1
                do i=1,nback_point
                    bblks=freedom_for_back(4,i)  !20230523
                    if(bblks>iblks)cycle !20230523

                    inode=freedom_for_back(1,i)
                    idofn=freedom_for_back(2,i)
                    jnode=freedom_for_back(3,i)
                    print *,'inode=',inode,'idofn=',idofn,'jnode=',jnode
                    itotv=nodfn(lmdofn(idofn),inode)
                    if(jnode/=0)jtotv=nodfn(lmdofn(idofn),jnode)
                    if(Bparameter==-1)then
                        Value_vc(i,tbstep,istoch)=result_zero(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-result_zero(jtotv)
                    elseif(Bparameter==-2)then
                        Value_vc(i,tbstep,istoch)=deltafi(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-deltafi(jtotv)
                    end if
                end do
            endif  !20200812
            if((bparameter>=1.and.bparameter<=2).and.balgor>=1) call dudx

        end do     !! loop for istep

        if(Qstatic/=0) then !20221104
            deallocate(qstatic_force%appearg,qstatic_force%qfactor,qstatic_force%cor_coef) !20221104
            deallocate(qstatic_force)  !20221104
        endif !20221104

        !if(kstab==0.and.(nforce/=0.or.ngaps/=0))call write_force_interface
        if(cwater/=0.and.delgroup>0)deallocate(coef_water)
    end do !!iincs
    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI

    !if(ngaps/=0)deallocate(tofor0)  !!ctt2005



    END SUBROUTINE STATIC_U


    subroutine modf_element_local_direction  !20221102

    integer(ink) igroup,index,nnode,ielgroup,ielem,inode,idimn
    integer(ink),pointer::lnods(:)

    real(irk) djacb
    real(irk),pointer::elcod(:,:)
    real(irk),allocatable::a3(:)

    do igroup=1,ngroup
        index = group(igroup)%index
        nnode = elkn(index)%el_field(1)%nnode_f

        if(index/=20.or.index/=21.or.index/=22) cycle
        allocate(a3(ndimn))
        DO ielgroup = 1,group(igroup)%nelgroup
            ielem = group(igroup)%list(ielgroup)

            lnods=>element(ielem)%field(1)%lnods_f
            elcod=>element(ielem)%field(1)%elcod_f

            if(index==22)then
                call normal_local_plate(index,ndimn,elcod,a3)
                call direct_p4(ndimn,a3,element(ielem)%rotation,element(ielem)%point_direct,coord)
            else
                djacb =sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))
                a3(:)=(elcod(:,2)-elcod(:,1))/djacb
                call direct_beam(ndimn,a3,element(ielem)%rotation,element(ielem)%point_direct,coord)
            endif

            do inode=1,nnode
                do idimn=1,ndimn
                    elcod(idimn,inode)=element(ielem)%rotation(idimn,:).d.coord(:,lnods(inode))
                end do
            end do
            element(ielem)%field(1)%elcod_f=elcod
            nullify(elcod,lnods)
        end do
        deallocate(a3)
    end do
    end subroutine modf_element_local_direction !20221102

    subroutine dudx  !20220108
    integer(ink) ivar,igroup,matno,ielgroup,ielem,nevab,itotv,iieq,  &
        ivalue,iintf,nintf,inode,idofn,jnode,   &
        iblks_i,iincs_i,istep_i,ivalue_point,jvar,jtotv,njntf
    real   (irk) e
    real   (irk),allocatable::stfor_bar(:),eload(:),value(:)
    real   (irk),pointer::fstif(:,:),rintf(:)
    integer(ink),pointer::ldofs(:),listf(:)

    !do ivalue=1,mvalue
    !Value_observ(ivalue)%dudx=0.
    !end do
    allocate(stfor_bar(ntotv))
    do ivar=1,npara
        write(7,*)'ivar=',ivar,'para_back(ivar)%name=',para_back(ivar)%name
        stfor_bar=0.
        if(para_back(ivar)%name=='E'.or.para_back(ivar)%name=='PERM')then  !20230430

            DO igroup =1,ngroup  !igroup
                if (appear(igroup)<=0) cycle
                matno = group(igroup)%matno
                if(para_back(ivar)%name=='E')then  !20230430
                    if(props(matno)%mechanical%solid%ie/=ivar)cycle
                    e=xvalue(ivar)
                    if(para_back(ivar)%mode_transform==0)then
                        e=xvalue(ivar)/para_back(ivar)%factor
                    elseif(para_back(ivar)%mode_transform==1)then
                        e=1./xvalue(ivar)/para_back(ivar)%factor
                    endif
                    !write(7,*)'igroup=',igroup,'e=',e
                endif
                if(para_back(ivar)%name=='PERM')then !20230430
                    if(props(matno)%mechanical%fluid%iperm/=ivar)cycle
                    e=xvalue(ivar)
                    if(para_back(ivar)%mode_transform==0)then
                        e=xvalue(ivar)/para_back(ivar)%factor
                    elseif(para_back(ivar)%mode_transform==1)then
                        e=1./xvalue(ivar)/para_back(ivar)%factor
                    endif
                endif

                nevab=size(element(group(igroup)%list(1))%field(1)%ldofs_f)
                allocate(eload(nevab),value(nevab))
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    fstif=>element(ielem)%field(1)%khandmc(1)%fstif
                    ldofs=>element(ielem)%field(1)%ldofs_f
                    if (Bparameter==1) value=result_zero(ldofs)
                    if (Bparameter==2) value=deltafi(ldofs)
                    !fstif=fstif/e
                    eload=MATMUL(fstif/e,value)
                    stfor_bar(ldofs)=stfor_bar(ldofs)-eload
                    nullify(fstif,ldofs)
                end do
                deallocate(eload,value)
            end do  !igroup

            !!
            rvector=0.
            do itotv=1,ntotv
                if (totveq(itotv)==0)cycle
                rvector(totveq(itotv))=rvector(totveq(itotv))+stfor_bar(itotv)
            end do
            do itotv=1,ntotv
                nintf=trans(itotv)%nintf
                if (nintf==0)cycle
                do iintf=1,nintf
                    iieq=totveq(trans(itotv)%listf(iintf))
                    if(iieq/=0)rvector(iieq)=rvector(iieq)+stfor_bar(itotv)*trans(itotv)%rintf(iintf)
                end do
            end do
            !!
            operation='SOLVE'
            call solve
            !! 找出观测点处的du/dx

            do ivalue=1,mvalue
                if(Value_observ(ivalue)%ic==0)cycle
                iblks_i=Value_observ(ivalue)%iblks
                iincs_i=Value_observ(ivalue)%iincs
                istep_i=Value_observ(ivalue)%istep
                idofn =lmdofn(Value_observ(ivalue)%idofn)

                ivalue_point=Value_observ(ivalue)%ivalue_point
                if(iblks_i==iblks.and.iincs_i==iincs.and.istep_i==istep)then
                    nintf=para_points(ivalue_point)%nintf
                    listf=>para_points(ivalue_point)%listf
                    rintf=>para_points(ivalue_point)%rintf
                    Value_observ(ivalue)%dudx(ivar)=dot_product(rintf,result(nodfn(idofn,listf)))
                    nullify(listf,rintf)
                endif  ! if(iblks_i==iblks....)
            end do  !ivalue
            !write(7,*)'istep=',istep,'ivar=',ivar,'value_observe%dudx='
            !write(7,*)Value_observ(:)%dudx(ivar)
        endif  !20230430
        !!!!
    end do  !ivar

    deallocate(stfor_bar)
    end subroutine dudx !20220108

    subroutine cmatrix_c_formation  !20210328
    integer(ink) igapb,igroup,nline_g_sc,npairs_sc,ipoin,jpoin,jdimn,jtotv,nintf,  &
        iintf,il0,kdimn,kpoin,iieq
    real   (irk) dislocal_s
    real   (irk),allocatable::unitg(:)
    real   (irk),pointer::Ks(:,:),Kc(:,:)

    allocate(unitg(ndimn))

    !write(7,*)'cmatrix_c='
    do igapb=1,nrcsteel
        igroup=rc_steel(igapb)%listgroup_c
        if(appear_process(igroup,iblks)==0)cycle
        nline_g_sc=rc_steel(igapb)%nline_g_sc
        do il0=1,nline_g_sc
            !write(7,*)'steel_group=',igapb,'line_order=',il0
            npairs_sc=rc_steel(igapb)%line_g_sc(il0)%npairs_sc

            rc_steel(igapb)%line_g_sc(il0)%cmatrix_c=0.

            do ipoin=1,npairs_sc
                rvector=0.
                jpoin=rc_steel(igapb)%line_g_sc(il0)%pairnode_sc(ipoin)

                do jdimn=1,ndimn
                    jtotv=nodfn(jdimn,jpoin)
                    nintf=trans(jtotv)%nintf
                    if(nintf/=0) then
                        iieq=totveq(jtotv)
                        if(iieq/=0)rvector(iieq)=0.
                        do iintf=1,nintf
                            iieq=totveq(trans(jtotv)%listf(iintf))
                            if(iieq/=0) &
                                rvector(iieq)=rvector(iieq)+rc_steel(igapb)%line_g_sc(il0)%rot_sc(jdimn,ipoin)*trans(jtotv)%rintf(iintf)
                        end do
                    else
                        if(totveq(jtotv)/=0) &
                            rvector(totveq(jtotv))=rvector(totveq(jtotv))+rc_steel(igapb)%line_g_sc(il0)%rot_sc(jdimn,ipoin)

                    endif
                end do !jdimn

                operation='SOLVE'
                call solve

                do kpoin=1,npairs_sc
                    jpoin=rc_steel(igapb)%line_g_sc(il0)%pairnode_sc(kpoin)
                    unitg=0.
                    do jdimn=1,ndimn
                        jtotv=nodfn(jdimn,jpoin)
                        nintf=trans(jtotv)%nintf
                        if(nintf/=0) then
                            do iintf=1,nintf
                                itotv=trans(jtotv)%listf(iintf)
                                unitg(jdimn)=unitg(jdimn)+result(itotv)*trans(jtotv)%rintf(iintf)
                            end do
                        else
                            unitg(jdimn)=result(jtotv)
                        endif
                    end do !jdimn
                    dislocal_s=dot_product(unitg,rc_steel(igapb)%line_g_sc(il0)%rot_sc(:,kpoin))
                    rc_steel(igapb)%line_g_sc(il0)%cmatrix_c(kpoin,ipoin)=dislocal_s

                end do  !kpoin
            end do  !ipoin


            Ks=>rc_steel(igapb)%line_g_sc(il0)%kmatrix_s
            Kc=>rc_steel(igapb)%line_g_sc(il0)%cmatrix_c
            rc_steel(igapb)%line_g_sc(il0)%ikscr=(Ks.x.Kc)
            do ipoin=1,npairs_sc
                rc_steel(igapb)%line_g_sc(il0)%ikscr(ipoin,ipoin)=   &
                    rc_steel(igapb)%line_g_sc(il0)%ikscr(ipoin,ipoin)+1.
            end do

            !write(7,*)'Ks='
            !       do ipoin=1,npairs_sc
            !   write(7,10)Ks(ipoin,:)
            !       end do
            !
            !   write(7,*)'Kc='
            !       do ipoin=1,npairs_sc
            !   write(7,10)Kc(ipoin,:)
            !       end do
            !            write(7,*)'ikscr='
            !    do ipoin=1,npairs_sc
            !write(7,10)rc_steel(igapb)%line_g_sc(il0)%ikscr(ipoin,:)
            !    end do
            nullify(ks,kc)

        end do !il0

    end do  !igapb
    deallocate(unitg)
10  format(15e15.5)

    end subroutine cmatrix_c_formation  !20210328


    subroutine Tcmatrix_c_formation  !20210411
    integer(ink) igapb,igroup,nline_g_w,npairs_wc,ipoin,jpoin,jdimn,jtotv,nintf,  &
        iintf,il0,kdimn,kpoin,iieq
    real   (irk) dislocal_s,coef
    real   (irk),pointer::Ks(:,:),Kc(:,:)


    !write(7,*)'cmatrix_c='
    coef=theta1*ditime
    do igapb=1,nwcpipe
        igroup=wc_pipe(igapb)%listgroup_c
        if(appear_process(igroup,iblks)==0)cycle
        nline_g_w=wc_pipe(igapb)%nline_g_w

        do il0=1,nline_g_w
            !write(7,*)'steel_group=',igapb,'line_order=',il0
            npairs_wc=wc_pipe(igapb)%line_g_w(il0)%npairs_wc

            wc_pipe(igapb)%line_g_w(il0)%cmatrix_c=0.

            do ipoin=1,npairs_wc
                rvector=0.
                jpoin=wc_pipe(igapb)%line_g_w(il0)%pairnode_wc(ipoin)
                jtotv=nodfn(lmdofn(10),jpoin)
                nintf=trans(jtotv)%nintf
                if(nintf/=0) then
                    iieq=totveq(jtotv)
                    if(iieq/=0)rvector(iieq)=0.
                    do iintf=1,nintf
                        iieq=totveq(trans(jtotv)%listf(iintf))
                        if(iieq/=0) &
                            rvector(iieq)=rvector(iieq)+1.*trans(jtotv)%rintf(iintf)
                    end do
                else
                    if(totveq(jtotv)/=0) &
                        rvector(totveq(jtotv))=rvector(totveq(jtotv))+1.

                endif


                operation='SOLVE'
                call solve

                do kpoin=1,npairs_wc
                    jpoin=wc_pipe(igapb)%line_g_w(il0)%pairnode_wc(kpoin)


                    jtotv=nodfn(lmdofn(10),jpoin)
                    nintf=trans(jtotv)%nintf
                    dislocal_s=0.
                    if(nintf/=0) then
                        do iintf=1,nintf
                            itotv=trans(jtotv)%listf(iintf)
                            dislocal_s=dislocal_s+result(itotv)*trans(jtotv)%rintf(iintf)
                        end do
                    else
                        dislocal_s=result(jtotv)
                    endif
                    wc_pipe(igapb)%line_g_w(il0)%cmatrix_c(kpoin,ipoin)=dislocal_s

                end do  !kpoin
            end do  !ipoin


            Ks=>wc_pipe(igapb)%line_g_w(il0)%kmatrix_w
            Kc=>wc_pipe(igapb)%line_g_w(il0)%cmatrix_c
            wc_pipe(igapb)%line_g_w(il0)%idcr=(Kc.x.Ks)
            do ipoin=1,npairs_wc
                wc_pipe(igapb)%line_g_w(il0)%idcr(ipoin,ipoin)=   &
                    coef*wc_pipe(igapb)%line_g_w(il0)%idcr(ipoin,ipoin)+1.
            end do

            !write(7,*)'Ks='
            !       do ipoin=1,npairs_wc
            !   write(7,10)Ks(ipoin,:)
            !       end do
            !
            !   write(7,*)'Kc='
            !       do ipoin=1,npairs_wc
            !   write(7,10)Kc(ipoin,:)
            !       end do
            !               write(7,*)'idcr='
            !       do ipoin=1,npairs_wc
            !   write(7,10)wc_pipe(igapb)%line_g_w(il0)%idcr(ipoin,:)
            !       end do
            nullify(ks,kc)

        end do !il0

    end do  !igapb

10  format(15e15.5)

    end subroutine Tcmatrix_c_formation  !20210411


    subroutine cmatrix_dtv_formation(cmatrix_dtv,inv_cmatrix_dtv2)  !20230216
    character(10)fieldid
    integer(ink) ifixset,idofix,jfixset,idofn,igroup,nrfields,ikh,index,nevab,ifield,ipoin,inode,nintf,mfixset
    real   (irk) coef,cmatrix_dtv(:,:),inv_cmatrix_dtv2(:,:)
    real   (irk),allocatable::value(:),qtemp(:),dtemp(:),interpt(:,:),observt(:,:)
    integer(ink),pointer::ldofs(:),listf(:),mlist(:)
    real   (irk),pointer::fstif(:,:),rintf(:)


    allocate(interpt(nfixsets,nfixsets),observt(nfixsets,nfixsets))
    cmatrix_dtv=0.


    allocate(dtemp(ntotv),qtemp(ntotv))

    !write(7,*)'cmatrix_c='

    do ifixset=1,nfixsets
        dtemp=0.
        qtemp=0.
        do idofix=1,ndofix
            idofn=prescrib(idofix)%ldofix
            mfixset=prescrib(idofix)%mfixset !20231130
            mlist=>prescrib(idofix)%mlist !20231130
            do i0=1,mfixset  !20231130
                jfixset=prescrib(idofix)%mlist(i0) !20231130
                if(jfixset/=ifixset)cycle
                dtemp(idofn)=1.*prescrib(idofix)%rintf(i0) !20231130
            end do  !20231130
            nullify(mlist) !20231130
        end do

        DO igroup =1,ngroup

            if (appear(igroup)>0) then
                ! get information from the group level

                nrfields=group(igroup)%nrfields
                fieldid=group(igroup)%fieldid
                if (nrfields/=1)     cycle
                if (fieldid/='T'.and.fieldid/='W')     cycle

                index  = group(igroup)%index
                nevab    =elkn(index)%el_field(1)%nnode_f
                allocate(value(nevab))

                do ifield=1,nrfields
                    do ikh=1,2

                        coef=1.
                        if (type_problem=='Q'.and.ikh==2) cycle
                        if (type_problem=='S'.and.ikh==1) coef=ditime    !theta1*ditime

                        DO ielgroup = 1,group(igroup)%nelgroup
                            ielem = group(igroup)%list(ielgroup)

                            if (associated(element(ielem)%field(ifield)%khandmc(ikh)%fstif)) then

                                fstif=>element(ielem)%field(ifield)%khandmc(ikh)%fstif
                                ldofs=>element(ielem)%field(ifield)%ldofs_f

                                value=coef*dtemp(ldofs)
                                ic=size(fstif,dim=2)
                                if (ic==1)then
                                    do idofn=1,nevab
                                        qtemp(ldofs(idofn))=qtemp(ldofs(idofn))+fstif(idofn,1)*value(idofn)
                                    end do
                                else
                                    qtemp(ldofs)=qtemp(ldofs)+MATMUL(fstif,value)
                                endif
                                nullify(fstif,ldofs)
                            endif

                        end do       !!ielgroup
                    end do        !!end do ikh
                end do     !! end do ifield
            endif
            deallocate(value)
        end do     !!  for igroup




        rvector=0.
        do itotv=1,ntotv
            if(totveq(itotv)/=0) &
                rvector(totveq(itotv))=rvector(totveq(itotv))-qtemp(itotv)
        end do


        operation='SOLVE'
        call solve
        !!!!!!!
        do ipoin=1, Npoints_pbx
            nintf=para_points(ipoin)%nintf
            listf=>para_points(ipoin)%listf
            rintf=>para_points(ipoin)%rintf
            cmatrix_dtv(ipoin,ifixset)=dot_product(rintf,result(listf))
            nullify(listf,rintf)
        end do



    end do  !ifixset

    interpt=transpose(cmatrix_dtv).x.cmatrix_dtv
    observt=0.
    do ifixset=1,nfixsets
        observt(ifixset,ifixset)=1.
    end do
    call householder(interpt,observt,inv_cmatrix_dtv2)


    deallocate(qtemp,dtemp)
    deallocate(interpt,observt)

    end subroutine cmatrix_dtv_formation  !20230216




    SUBROUTINE STATIC_U_reli

    logical logx
    character(80)text,material,criteria
    integer(ink) itotv,ielem,irst,trstep0,ipoin,idofn,ij,ij0,idofix,ldofix,idelgroup,i0,ipairs
    integer(ink) ncmat,ncpld,nstoch
    real   (irk) xtime,time_begin,detal,ttime0,coef
    real   (irk),allocatable::rvectorm(:),value(:)
    integer(ink) iintf,nintf,iieq,ivcoh,ivfri   !!int2000

    integer(ink) igapb,npgblock,jpoin,igaps,ipair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,npairs,cwater,jgaps,jpair,kdimn   !!ctt2005
    real   (irk),allocatable::rot(:,:),tofor0(:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:) !!ctt2005

    integer(ink) iter,mkiter,i,j0,nbeta,ibeta,ic,Nv
    real(irk)    beta,er,gy
    integer(ink),allocatable::ja(:)
    real(irk),allocatable::xa(:),ya(:),sd(:),ed(:),ep(:),sp(:),ga(:),rc(:),ee(:),ss(:), &
        cov(:,:)

    !
    !open(stocunit,file='stoc.dat')

    read(stocunit,*)text
    read(stocunit,*)nbeta,nv,mkiter !number of radom,maximum iteration number

    allocate(betas(nbeta))

    do ibeta=1,nbeta
        allocate(betas(ibeta)%ga(nv))
        betas(ibeta)%ga=0.
    end do

    !   read(stocunit,*)text
    !read(stocunit,*)group(1:ngroup)%ivcoh
    !   read(stocunit,*)group(1:ngroup)%ivfri


    allocate(xa(nv),ya(nv),ed(nv),sd(nv),ep(nv),sp(nv),ga(nv),rc(nv),ja(nv),ee(nv),ss(nv))
    allocate(cov(nv,nv))

    read(stocunit,*)text
    read(stocunit,*)ja(:)  !distribution type:1,normal,2,log normal,3,extreme
    read(stocunit,*)ee(:)  !average value
    read(stocunit,*)ss(:)  !variance
    do i=1,nv
        read(stocunit,*)cov(i,:)  !correlation matrix
    end do

    read(mainunit,*)text
    read(mainunit,*)nincs

    print *,' in static_U**'

    if(ngaps/=0)allocate(tofor0(ntotv)) !!ctt2005

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            do idelgroup=1,delgroup
                read(mainunit,*)text
            end do
        end if
        if(Qstatic/=0) then !20221104
            do i0=1,6
                read(mainunit,*)text
            end do
        endif

    end do



    xtime=0.0
    do iincs=lincs+1,nincs
        print *,'iincs=',iincs

        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            allocate(coef_water(delgroup,nstep))
            do idelgroup=1,delgroup
                read(mainunit,*)i0,coef_water(idelgroup,:)
            end do
        end if


        if(Qstatic/=0) then !20221104
            read(mainunit,*)text  !20221104
            allocate(qstatic_force)  !20221104
            allocate(qstatic_force%appearg(ngroup),qstatic_force%qfactor(ndimn),qstatic_force%cor_coef(2,Qstatic))
            read(mainunit,*)qstatic_force%iaxe
            read(mainunit,*)qstatic_force%appearg
            read(mainunit,*)qstatic_force%qfactor
            read(mainunit,*)qstatic_force%cor_coef(1,:)
            read(mainunit,*)qstatic_force%cor_coef(2,:)
        endif !20221104


        do ibeta=1,nbeta !!!2018/01/10
            read(stocunit,*)text
            do igaps=1,ngaps
                read(stocunit,*)gaps(igaps)%ivcoh,gaps(igaps)%ivfri
            end do

            iter=0
            SP=ss
            EP=ee
            XA=EP
            YA=0.
            er=1.e-3



333         iter=iter+1
            CALL DANGLI(nv,EE,SS,XA,JA,SD,ED,SP,EP)

            do igaps=1,ngaps
                if(nforce_gaps_appear(igaps)==2.or.nforce_gaps_appear(igaps)==0)cycle
                ivcoh=gaps(igaps)%ivcoh
                ivfri=gaps(igaps)%ivfri
                if(ivcoh==0.and.ivfri==0)cycle
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs
                    if(ivfri>0) &
                        gaps(igaps)%frict(ipairs)=xa(ivfri)
                    if(ivcoh>0) &
                        gaps(igaps)%cohes(ipairs)=xa(ivcoh)
                end do
            end do


            ttime0=ttime
            trstep0=trstep
            do istep=inc_step,nstep,inc_step

                if(iblks>=stab_matde)call stab_initialize

                write(chkunit,*)'Increment step=',istep
                print *,'istep=',istep
                if(outintr>0.and.iblks>=outintr)trstep=trstep0+istep !20200226
                xtime=ditime*istep
                ttime=ttime0+ditime*istep !! only for output

                call dfact_time_curve(ttime)
                call modf_var_prescribed

                call gravity
                if(rmesh>0)call gravity1
                if(rmesh>1)call gravity2
                write(7,*)'cwater=',cwater,'delgroup=',delgroup
                if(cwater/=0.and.delgroup/=0)call step_water_pressure  !2013/3/18

                write(7,*)'force_external_reli**'
222             call force_external
                !if(iblks/=1)mdiv=1   !5
                if(type_load=='LOAD2')mdiv=2  !!806
                do idiv=1,mdiv
                    !! temperature
                    if(type_load=='LOAD2'.and.idiv==2) goto 71
                    call load_of_creep_and_temperature
                    call creep_strain_of_rock_fill    !20130510
71                  if(mdiv/=1)toform=toforl+(tofor-toforl)*idiv/mdiv
                    if(type_load=='DISCONTROL')preact0=prescrib(1)%rdofix
                    if(ngaps/=0.and.mdiv==1)tofor0=tofor !!ctt2005
                    if(ngaps/=0.and.mdiv/=1)tofor0=toform !!ctt2005
                    deltafi=0.0
                    do igapb=1,ngapb !fzx  tcl
                        if(gapb(igapb)%nrdof==0)cycle
                        gapb(igapb)%rdisp_deltafi=0.
                    enddo


                    do iiter=1,miter
                        iccontact=0 !zhao 05/07/30
                        print *,'iblks=',iblks,'idiv=',idiv,'iiter=',iiter

                        call algort

                        if (iiter==1.or.(kstat==2.and.iiter.le.2))then
                            !deltafi_ssorpbcg=deltafi !ssorpbcg
                            !deltafi=0.0
                            delitfi=0.0
                            call predict
                            do ielem=1,nelem   !!simo_rifai
                                if(associated(element(ielem)%alfa))element(ielem)%alfa=0.
                            end do  !!simo_rifai
                        endif


                        if(ikindks/=0) call strain_for_steel_bar !steel 2008
                        if (nlayer/=2)then

                            if (kresl/=0.or.kthmat/=0) then
                                if(kresl/=0)call stiff_u
                                if(kresl/=0.and.rmesh>0.and.nelem1>0)call stiff_u1
                                if(kresl/=0.and.rmesh>1.and.nelem2>0)call stiff_u2
                                if(neuman==1.and.((kstat==2.and.iiter==2).or.&
                                    (kstat/=2.and.istep==inc_step.and.iiter==1)))call write_stiff_u
                                if(kthmat/=0)call htmatrx

                                if(type_solver=='PROFILE'.and.   &
                                    (neuman==1.and.((kstat/=2.and.(istep/=1.or.iiter/=1)).or.(kstat==2.and.iiter.gt.2))))goto 1
                                if(type_solver/='JPCG')global_stiff1=0.0
                                if(nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                                if (type_solver=='JPCG'.and.outintr==0) then
                                    do ielem=1,nelem
                                        element(ielem)%estif=0.0
                                    end do
                                endif
                                call estif_assemble
                                if(nbspring>0) &       !20150925
                                    call assemble_back_spring  !20150925
                                if(ground_inf/=0) call semi_inf_space_assemble

                                if(nonsym==0)then !20240312 YL
                                    do itotv=1,ntotv
                                        if (totveq(itotv)/=0)then
                                            if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                        endif
                                    enddo
                                endif !20240312 YL

                            endif

                        else !if (nlayer/=2)then

                            if(kresl_layer1/=0.or.kresl_layer2/=0)call stiff_u
                            print *,'kresl_layer=',kresl_layer1,kresl_layer2
                            if(kresl_layer1/=0)global_stiff1(1:iseq(neq_layer1))=0.
                            if(kresl_layer2/=0)global_stiff1(iseq(neq_layer1)+1:iseq(neq))=0.
                            if(nonsym==1.and.kresl_layer1/=0)global_stiff2(1:iseq(neq_layer1))=0.
                            if(nonsym==2.and.kresl_layer2/=0)global_stiff2(iseq(neq_layer1)+1:iseq(neq))=0.

                            call estif_assemble

                            if(nonsym==0)then !20240312 YL
                                do itotv=1,ntotv
                                    if (totveq(itotv)/=0)then
                                        if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-5)global_stiff1(iseq(totveq(itotv)))=1.e30
                                    endif
                                enddo
                            endif !20240312 YL

                        endif !if (nlayer/=2)

1                       if(type_load=='LOAD2'.or.(kstat==2.and.iiter.le.2).or.(type_load/='LOAD2'.and.kstat/=2.and.iiter==1).or.  &
                            (ngaps/=0.and.istatec==0)) then	  !! for temperature 20130510
                            if(type_load=='LOAD2'.and.idiv==2)then  !20130510
                                deltafi=0.0
                                delitfi=0.0
                            endif
                            call gpvar2_initial
                            if (ninit/=0.and.(kinit==2.and.iincs==1)) then
                                call eload_initialize
                                call eload_initial_stress
                                if (kinit==2.and.iincs==1)then
                                    call force_release
                                    where(totveq==0)
                                        torel=0.0
                                    endwhere
                                endif
                            endif

                            !write(7,*)'deltafi_before conver_load(100-120)'
                            !        do itotv=100,120
                            !        write(7,*)itotv,deltafi(itotv)
                            !        end do


                            call eload_initialize
                            call residu_f

                            if(rmesh>0.and.nelem1>0)call residu_f1
                            if(rmesh>1.and.nelem2>0)call residu_f2
                            call eload_field
                            if(nbspring>0) & !20150925
                                call eload_back_spring  !20150925
                            if(ground_inf/=0)call semi_inf_load
                            call force_internal
                        endif !for iiter==1 and istep==inc_step .and.idiv==1  temperature
                        if (mdiv/=1) then
                            if(idiv==1.and.iiter==1.and.allocated(torel))toform=toform+torel
                        else
                            if(iiter==1.and.allocated(torel))tofor=tofor+torel
                        endif
                        write(*,*)'   ' !很奇怪，有这一行的话，就不出错，没有的话，SOLVE中allocate(resultm(ntotv))这一行出错！


                        if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv==1)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005
                        if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv/=1)call ctfor_to_tofor(tofor0,toform)  !!ctt2005

                        !if(ngaps/=0)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005

                        if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)  goto 2  !ctt2005 , change position!
                        if(type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR
                        if ((type_solver=='PROFILE'.or.type_solver=='PARDISO').and.kresl/=0)then
                            operation='FACTORIZE'
                            call solve
                        end if
2                       continue

                        logx=ngaps/=0.and.(iiter==1.and.istep==inc_step).and.iblks==iblks_bt
                        if (logx)then !ctt2005
                            if (restart_ctt==0)then !restart_ctt

                                kdimn=ndimn
                                if(block_stab==1)kdimn=3*(ndimn-1) !2015/11/17
                                allocate(rot(kdimn,kdimn))
                                rot=0.
                                do igapb=1,ngapb
                                    npgblock=gapb(igapb)%npgblock
                                    write(7,*)'igapb=',igapb,'npgblock=',npgblock
                                    gapb(igapb)%cmatrix=0.

                                    if(gapb(igapb)%eblock==0) cycle  !2017/11/19
                                    do ipoin=1,npgblock
                                        !jpoin=gapb(igapb)%nodegblock(ipoin)
                                        igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                        ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                        ij=gapb(igapb)%nodegblock_onetwo(ipoin)


                                        coef=1.
                                        if(ij==2)coef=-1.
                                        rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                                        if(kdimn>ndimn)then
                                            if(ndimn==2)rot(3,3)=1.
                                            if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                        endif

                                        allocate(unitl(kdimn),unitg(kdimn))
                                        do idimn=1,kdimn

                                            itotvbt=(ipoin-1)*kdimn+idimn
                                            unitl=0.
                                            unitl(idimn)=1.*coef


                                            unitg=transpose(rot).x.unitl
                                            rvector=0.
                                            call  unit_force_trans(igapb,kdimn,ij,unitg,igaps,ipair,rvector)
                                            !
                                            ! if(igapb==2.and.idimn==2) then
                                            !write(7,*)'igapb**=',igapb,'jpoin=',gapb(igapb)%nodegblock(ipoin),'idimn=',idimn,'rvector='
                                            !      do jdimn=1,neq
                                            !          if(abs(rvector(jdimn))>1.e-6)write(7,*)jdimn,rvector(jdimn)
                                            !      end do
                                            ! endif

                                            operation='SOLVE'
                                            call solve


                                            do kpoin=1,npgblock
                                                jgaps=gapb(igapb)%nodegblock_igaps(kpoin)
                                                jpair=gapb(igapb)%nodegblock_ipairs(kpoin)
                                                ij0=gapb(igapb)%nodegblock_onetwo(kpoin)         !2017/04/03
                                                call result_node_to_center(kdimn,ij0,jgaps,jpair,result,unitg)

                                                do jdimn=1,kdimn
                                                    jtotvbt=(kpoin-1)*kdimn+jdimn
                                                    gapb(igapb)%cmatrix(jtotvbt,itotvbt)=unitg(jdimn)
                                                end do
                                            end do  !kpoin
                                        end do  !idimn
                                        deallocate(unitl,unitg)
                                    end do  !ipoin

                                    do ipoin=1,npgblock
                                        igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                        ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                        ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                                        coef=1.
                                        if(ij==2)coef=-1.
                                        rot=0.
                                        rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)

                                        if(kdimn>ndimn)then
                                            if(ndimn==2)rot(3,3)=1.
                                            !if(ndimn==3)rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                                            if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                            !if(ndimn==3)rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                                        endif

                                        rot=coef*rot

                                        allocate(cmatrixl(kdimn,kdimn))
                                        do jpoin=1,npgblock
                                            jtotv=(jpoin-1)*kdimn
                                            itotv=(ipoin-1)*kdimn
                                            cmatrixl=gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)
                                            gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)=   &
                                                rot.x.cmatrixl
                                        end do
                                        deallocate(cmatrixl)
                                    end do
                                end do  !igapb
                                call forAdirect !fzx !形成A矩阵

                                do igapb=1,ngapb
                                    !write(7,*)'igapb=',igapb,'ntotv_bt=',gapb(igapb)%ntotv_bt,'camatrix='
                                    do itotvbt=1,gapb(igapb)%ntotv_bt
                                        !write(7,*)gapb(igapb)%cmatrix(itotvbt,:)
                                        do jtotvbt=1,gapb(igapb)%ntotv_bt
                                            write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                        enddo
                                    enddo
                                enddo  !igapb

                                deallocate(rot)

                            elseif(restart_ctt==1)then !restart_ctt
                                call forAdirect !fzx !形成A矩阵
                                rewind(recttunit)
                                do igapb=1,ngapb
                                    npgblock=gapb(igapb)%npgblock
                                    do itotvbt=1,gapb(igapb)%ntotv_bt
                                        do jtotvbt=1,gapb(igapb)%ntotv_bt
                                            read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                        enddo
                                    enddo
                                enddo
                            else !restart_ctt
                                write(*,*)'no such restart_ctt!!'
                                stop
                            endif !restart_ctt
                        endif  !!ctt2005


90                      format(10e12.5)
                        rvector=0.0
                        !write(7,*)'iiter=',iiter
                        !write(7,*)'rvector,tofor,stfor'
                        if (type_solver/='JPCG') then
                            do itotv=1,ntotv
                                if (totveq(itotv)/=0)then
                                    if (mdiv/=1)then
                                        rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                            toform(itotv)-stfor(itotv)

                                    else
                                        rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                            tofor(itotv)-stfor(itotv)
                                        !if(abs(rvector(totveq(itotv)))>1.e-8)write(7,*)itotv,tofor(itotv),stfor(itotv)

                                    endif
                                endif
                            end do

                            !!int2000
                            do itotv=1,ntotv
                                nintf=trans(itotv)%nintf
                                if (nintf/=0) then
                                    iieq=totveq(itotv)
                                    if(iieq/=0)rvector(iieq)=0.
                                    do iintf=1,nintf
                                        iieq=totveq(trans(itotv)%listf(iintf))
                                        if(iieq/=0)rvector(iieq)=rvector(iieq)+  &
                                            (tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                                    end do
                                endif
                            end do
                            !!int2000

                        else !if (type_solver/='JPCG') then

                            if(mdiv/=1)rvector=toform-stfor
                            if(mdiv==1)rvector=tofor -stfor
                        endif



                        if (type_load=='ARCLENGTH'.and.kresl/=0) then
                            allocate(rvectorm(neq))
                            rvectorm=rvector
                            rvector=0.0
                            if (type_solver/='JPCG') then
                                do itotv=1,ntotv
                                    if(totveq(itotv)/=0) &
                                        rvector(totveq(itotv))=rvector(totveq(itotv))+tofor_arclength(itotv)
                                end do
                            else
                                rvector=tofor_arclength
                            endif
                            operation='SOLVE'
                            call solve
                            delta_arclength=result
                            rvector=rvectorm
                            deallocate(rvectorm)
                        endif

                        if (type_nl==8)then
                            if(kstat/=2)call bfgsr(iiter)
                            if(kstat==2)call bfgsr(iiter-1)
                        else
                            operation='SOLVE'
                            call solve
                        endif

                        if(ngaps/=0.and.iblks>=abs(iblks_bt))call solve_ctt  !!ctt2005

                        !write(7,*)'tofor***'
                        !do itotv=1,ntotv
                        !    if(abs(tofor(itotv))>1.e-3) &
                        !    write(7,*)itotv,tofor(itotv)
                        ! end do

                        if (type_load=='ARCLENGTH')then
                            call find_dfact_of_arclength (irst)
                            if (irst==1) then
                                time_begin=tcurves(arc_curve)%time_begin
                                detal=tcurves(arc_curve)%detal
                                if (abs(ttime-time_begin-ditime).le.1.e-8)detal=tcurves(arc_curve)%fact_inc
                                tcurves(arc_curve)%detal=detal*.5
                                if (abs(ttime-time_begin-ditime).le.1.e-8)tcurves(arc_curve)%fact_inc=detal*.5
                                goto 222
                            endif
                        endif

                        if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)call neuman_expan

                        call TIME(char_time)
                        print *, 'time: ', char_time
                        write(chkunit,*)'time: ', char_time


                        !write(7,*)'varupdate'
                        call varupdate
                        !write(7,*)'af varupdate'
                        call eload_initialize

                        if(ikindks/=0) call strain_for_steel_bar !steel 2008
                        !write(7,*)'bbxx residu_f'
                        call residu_f
                        !write(7,*)'aaxx residu_f'
                        if(rmesh>0.and.nelem1>0)call residu_f1
                        if(rmesh>1.and.nelem2>0)call residu_f2
                        if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then   !806
                            call eload_field
                            if(nbspring>0) & !20150925
                                call   eload_back_spring  !20150925
                            if(ground_inf/=0)call semi_inf_load


                            call reaction_prescribed

                            call conver_load
                            if(nchek==0) call conver_nodal_value
                            if(type_load=='ARCLENGTH')tcurves(arc_curve)%piter=iiter


                            if(nchek==0)exit !tcl
                        endif !ep2010
10                      continue
                        print *,'miter=',miter,'iiter=',iiter
                    end do   !! loop for iiter

                    if(type_load/='LOAD2') then
                        if(istatec==0) &
                            call state_and_stiff_2021
                        !write(7,*)'icttstif_static_u=',icttstif
                        do igaps=1,ngaps
                            npairs=gaps(igaps)%npairs
                            do ipairs=1,npairs
                                if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                                gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
                                gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
                            end do
                        end do
                    endif

                    if(type_load/='LOAD2') &
                        call gpvarupdate

                    if(rmesh>0.and.nelem1>0)call gpvarupdate1
                    if(rmesh>1.and.nelem2>0)call gpvarupdate2
                end do    !! for idiv
                if(type_load=='LOAD2') &
                    call gpvarupdate
                if(modf_dis_blocks(iblks)==1)call construction_dis_modify


                if(type_load=='LOAD2') then
                    if(istatec==0) &
                        call state_and_stiff_2021
                    do igaps=1,ngaps
                        npairs=gaps(igaps)%npairs
                        do ipairs=1,npairs
                            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                            gaps(igaps)%state0(ipairs)=gaps(igaps)%state(ipairs)
                            gaps(igaps)%damage0(ipairs)=gaps(igaps)%damage(ipairs)
                            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
                            gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
                        end do
                    end do
                endif


100             toforl=tofor

                if (istep/noutn*noutn==istep)then
                    iwriten=iwriten+1
                    call out_record
                    call outputres !for output
                endif
                !if (kstab==0.) then
                if(nforce/=0.or.ngaps/=0)call force_interface
                !else
                if(kstab/=0.)call safety_factor


                if (istep/noutf*noutf==istep)then
                    !if(kstab==0.and.nforce/=0)call write_force_interface
                    if(nforce/=0.or.ngaps/=0)call write_force_interface
                    call out_full_write
                    if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                    if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
                endif

                if(istep/nresta*nresta==istep)call resta_read_write(-1)
            end do     !! loop for istep

            call stab_rcandgy_reli(rc,xa,gy)
            call RI3(nv,GY,GA,RC,XA,YA,SD,ED,SP,EP,cov)  !translation between the distributions

            write(7,*)'iter=',iter,'gy=',gy,'xa=',xa
            if(abs(gy)>er.and.iter<mkiter) goto 333
            call betaindex(nv,rc,ep,sp,xa,cov,beta) ! computation reliability index
            write(7,*)'ibeta=',ibeta,'iter=',iter,'gy=',gy

            betas(ibeta)%beta=beta
            betas(ibeta)%ga(:)=-ga
            write(7,*)'reliability index=',beta
            write(7,*)'experiment points=',xa
            write(7,*)'alfa=',-ga


        end do !ibeta !!!2018/01/10
        !if(kstab==0.and.(nforce/=0.or.ngaps/=0))call write_force_interface
        if(Qstatic/=0) then !20221104
            deallocate(qstatic_force%appearg,qstatic_force%qfactor,qstatic_force%cor_coef) !20221104
            deallocate(qstatic_force)  !20221104
        endif !20221104

        if(cwater/=0.and.delgroup>0)deallocate(coef_water)
    end do !!iincs
    if(sysrelis>0) &
        call system_reliability(nbeta,nv)

    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI
    !if(ngaps/=0)deallocate(tofor0)  !!ctt2005

    END SUBROUTINE STATIC_U_reli

    !!!!!!!!!!!!!!!!
    SUBROUTINE betaindex(nv,rc,ep,sp,xa,cov,beta1)
    integer(ink) i,j,nv
    real(irk) sigmaz,miuz,beta1
    real(irk) rc(:),ep(:),sp(:),xa(:),cov(:,:)

    sigmaz=0.
    miuz=0.
    do i=1,nv
        miuz=miuz+(ep(i)-xa(i))*rc(i)
    end do
    do i=1,nv
        do j=1,nv
            sigmaz=sigmaz+rc(i)*sp(i)*rc(j)*sp(j)*cov(i,j)
        end do
    end do
    sigmaz=sqrt(sigmaz)
    beta1=miuz/sigmaz

    !	  write(2,*)'miuz=',miuz,'sigmaz=',sigmaz
    end SUBROUTINE

    SUBROUTINE RI3(nv,GY,GA,RC,XA,YA,SD,ED,SP,EP,cov)
    integer i,j,nv
    real(8) gg,y1,gy
    real(8) ga(:),rc(:),xa(:),ya(:),ed(:),sd(:),ep(:),sp(:),cov(:,:)
    real(8),allocatable::xc(:)
    allocate(xc(nv))
    xc=rc
    GG=0.0
    DO 160 I=1,NV
        rc(i)=0.
        do j=1,nv
            RC(I)=rc(i)+xc(j)*cov(i,j)*SP(j)
        end do
        GG=GG+RC(I)*RC(I)
160 CONTINUE
    GG=SQRT(GG)
    DO 164 I=1,NV
        IF(SP(I).EQ.0.OR.RC(I).EQ.0.) THEN
            GA(I)=0.
            YA(I)=0.
            GOTO 164
        ENDIF
        GA(I)=-RC(I)/GG
        YA(I)=SD(I)*YA(I)/SP(I)+(ED(I)-EP(I))/SP(I)
164 CONTINUE
    Y1=0.
    DO 165 I=1,NV
        Y1=Y1+YA(I)*GA(I)
165 CONTINUE
    Y1=Y1+GY/GG
    DO 170 I=1,NV
        YA(I)=GA(I)*Y1
170 CONTINUE
    DO 180 I=1,NV
        XA(I)=YA(I)*SP(I)+EP(I)
180 CONTINUE
    rc=xc

    deallocate(xc)
    END SUBROUTINE

    SUBROUTINE DANGLI(nv,EE,SS,XA,JA,SD,ED,SP,EP)
    integer(ink) i,j1,jj,nv
    real(irk) vv,sl,ar,ak,q,af,agf,aa,b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10, &
        bb,yy,u1,uu,ub
    integer(ink) ja(:)
    real(irk) ee(:),ss(:),xa(:),sd(:),ed(:),ep(:),sp(:)
    DO 5 I=1,NV
        SD(I)=SP(I)
        ED(I)=EP(I)
        J1=JA(I)
        JJ=J1-2
        IF(JJ) 5,3,4
3       VV=(SS(I)/EE(I))**2    !
        SL=dLOG(1.+VV)
        IF(XA(I).GE.0.0) GO TO 6
        XA(I)=dABS(XA(I))
6       SP(I)=XA(I)*SQRT(SL)
        EP(I)=XA(I)*(1.+dLOG(EE(I))-dLOG(XA(I)*SQRT(1.+VV)))
        GOTO 5
4       AR=1.28255/SS(I)
        AK=EE(I)-0.5772/AR
        Q=EXP(-AR*(XA(I)-AK))
        AF=EXP(-Q)
        AGF=AR*Q*EXP(-Q)
        AA=1.-AF
        B0=1.570796288
        B1=3.706987906E-2
        B2=-8.364353589E-4
        B3=-2.250947176E-4
        B4=6.841218299E-6
        B5=5.824238515E-6
        B6=-1.04527497E-6
        B7=8.360937017E-8
        B8=-3.231081277E-9
        B9=3.657763036E-11
        B10=6.936233982E-13
        IF(AA-0.5) 230,240,250
230     BB=AA
        GO TO 255
250     BB=1.-AA
255     YY=-dLOG(4.*BB*(1.-BB))
        U1=YY*(B5+YY*(B6+YY*(B7+YY*(B8+YY*(B9+YY*B10)))))
        UU=YY*(B0+YY*(B1+YY*(B2+YY*(B3+YY*(B4+U1)))))
        UB=SQRT(UU)
        IF(AA.LT.0.5) GOTO 260
        UB=-UB
        GO TO 260
240     UB=0.0
260     SP(I)=EXP(-UB*UB/2.)/SQRT(2.*3.1416)/AGF
        EP(I)=XA(I)-SP(I)*UB
5   CONTINUE
    END SUBROUTINE


    subroutine system_reliability(nbeta,nv)
    integer(ink) nbeta,ntmod,itmod,jtmod,ibeta,i,j,nv
    real(irk) betax,pr,af,x0,lowpf,highpf,q1,q2,f0,relat_ave,beta_ave,aft
    integer(ink),allocatable:: rep(:)
    real(irk),allocatable::tga(:,:),tbeta(:),relat(:,:),ymult(:),zmult(:),qij(:,:)

    ntmod=nbeta
    allocate(tbeta(ntmod),tga(nv,ntmod),relat(ntmod,ntmod))
    relat=0.
    do ibeta=1,nbeta
        tga(:,ibeta)=betas(ibeta)%ga(:)
        tbeta(ibeta)=betas(ibeta)%beta
        write(7,*)'ibeta=',ibeta
        write(7,*)'ga=',tga(:,ibeta)
        write(7,*)'beta=',tbeta(ibeta)
    end do

    do itmod=1,ntmod
        do jtmod=1,ntmod
            relat(itmod,jtmod)=tga(:,itmod).d.tga(:,jtmod)
        end do
    end do
    write(7,*)' correlative matric'
    do itmod=1,ntmod
        write(7,10)relat(itmod,:)
    end do

    allocate(ymult(18),zmult(18))
    do i=1,18
        ymult(i)=1.
        do j=1,2*i+1,2
            ymult(i)=ymult(i)*real(j)
        end do
    end do
    zmult(1)=1.
    do i=2,18
        zmult(i)=1.
        do j=2*i-3,2*i-1,2
            zmult(i)=zmult(i)*real(j)
        end do
    end do
    !!!!for 串并联系统
    relat_ave=0.
    do i=1,ntmod
        do j=1,ntmod
            if(i/=j)relat_ave=relat_ave+relat(i,j)
        end do
    end do
    relat_ave=relat_ave/(ntmod*(ntmod-1))
    pr=1.0
    do i=1,ntmod
        !		  call af_normalx(tbeta(i),af,ymult,zmult)
        call af_normal(tbeta(i),af)
        pr=pr*af
    end do
    call af_beta(pr,beta_ave,ymult,zmult)


    call aft_gauss(beta_ave,relat_ave,aft,ntmod,ymult,zmult)
    !call aft_gauss(4.23_irk,0.57_irk,aft,10,ymult,zmult)
    print*,'串联系统失效概率=',aft
    write(7,*)'串联系统失效概率=',aft

    call af_beta(1-aft,betax,ymult,zmult)
    print*,'串联系统可靠指标=',betax
    write(7,*)'串联系统可靠指标=',betax

    betax=beta_ave*sqrt(ntmod/(1+relat_ave*(ntmod-1)))
    !betax=4.23*sqrt(10/(1+0.57*(10-1)))
    print*,'并联系统可靠指标=',betax
    write(7,*)'并联系统可靠指标=',betax
    !stop
    !!!!end for 串并联系统

    allocate(rep(ntmod))
    rep=0
    do i=1,ntmod
        if(rep(i)==0)then
            do j=i+1,ntmod
                if(rep(j)==0)then
                    if(relat(i,j)>0.7)then
                        rep(j)=1
                    endif
                endif
            end do
        endif
    end do
    pr=1.0
    do i=1,ntmod
        if(rep(i)==0)then
            !		  call af_normalx(tbeta(i),af,ymult,zmult)
            call af_normal(tbeta(i),af)
            pr=pr*af
        end if
    end do
    write(7,*)'PNET system reliability=',pr
    call af_beta(pr,betax,ymult,zmult)
    write(7,*)'PNET system reliability index=',betax
    !!!!following is for general narrow field method
    allocate(qij(ntmod,ntmod))
    do i=1, ntmod
        !			call af_normalx(tbeta(i),af,ymult,zmult)
        call af_normal(tbeta(i),af)
        qij(i,i)=1-af
    enddo
    do i=1, ntmod
        do j=i+1,ntmod
            x0=(tbeta(j)-relat(i,j)*tbeta(i))/(1-relat(i,j)**2)
            f0=1.
            if(x0<0.)then
                f0=-1.
                x0=x0*f0
            endif
            !			call af_normalx(x0,af,ymult,zmult)
            call af_normal(x0,af)
            write(7,*)'i=','j=',j,'x01=',x0,'af=',af
            if(f0<0.)af=1-af
            qij(i,j)=qij(i,i)*(1-af)
            x0=(tbeta(i)-relat(i,j)*tbeta(j))/(1-relat(i,j)**2)
            f0=1.
            if(x0<0.)then
                f0=-1.
                x0=x0*f0
            endif
            !			call af_normalx(x0,af,ymult,zmult)
            call af_normal(x0,af)
            write(7,*)'i=','j=',j,'x01=',x0,'af=',af
            if(f0<0.)af=1-af
            qij(j,i)=qij(j,j)*(1-af)
        end do
    end do
    write(7,*)'General narrow field method'
    write(7,*)'Qij****'
    do i=1,ntmod
        write(7,*)qij(i,:)
    end do

    lowpf=qij(1,1)
    do i=2,ntmod
        lowpf=lowpf+qij(i,i)
        do j=1,i-1
            lowpf=lowpf-qij(i,j)-qij(j,i)
        end do
    end do
    highpf=0.
    do i=1,ntmod
        highpf=highpf+qij(i,i)
    end do

    do i=2,ntmod
        q1=maxval(qij(1:(i-1),i))
        q2=maxval(qij(i,1:(i-1)))
        if(q2>q1)q1=q2
        highpf=highpf-q1
    end do
    write(7,*)'low  failure probability=',lowpf
    call af_beta(1-lowpf,betax,ymult,zmult)
    write(7,*)'high probability index=',betax
    write(7,*)'high failure probability=',highpf
    call af_beta(1-highpf,betax,ymult,zmult)
    write(7,*)'low probability index=',betax


    !!!!!!!end for


10  format(20e15.5)

    end subroutine system_reliability

    subroutine aft_gauss(beta_ave,relat_ave,aft,ntmod,ymult,zmult)
    integer(ink) i,ntmod
    real(irk) x0,y0,af ,beta_ave,relat_ave,aft,pi
    real(irk) w24(24),li24(24),ymult(:),zmult(:)
    pi=3.14159
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

    aft=1.
    do i=1,24
        x0=5*li24(i)
        y0=(beta_ave+sqrt(relat_ave)*li24(i)*5)/sqrt(1-relat_ave)
        !	  call af_normalx(y0,af,ymult,zmult)
        call af_normal(y0,af)
        af=5*af**ntmod*exp(-.5*x0**2)/sqrt(2.*pi)
        aft=aft-af*w24(i)
    end do


    end subroutine aft_gauss

    SUBROUTINE af_normalx(xy0,af,ymult,zmult)
    integer(ink) i,j
    real(irk) pi,af,xy0,y0,ymult(:),zmult(:)

    PI=3.141592653589793238
    if(xy0<=2.5)then
        y0=1.
        do j=1,18
            y0=y0+(xy0**(2.*j))/ymult(j)
        end do
        af=.5+xy0*exp(-.5*xy0**2)*y0/sqrt(2*pi)
    else
        y0=1.
        do j=1,18
            y0=y0+(-1)**j*(xy0**(-2.*j))*zmult(j)
        end do
        af=1.0-exp(-.5*xy0**2)*y0/xy0/sqrt(2*pi)
    endif

    END SUBROUTINE


    SUBROUTINE af_normal(xy0,af)
    integer i,j,k
    real(8) pi,af,xy0,y0

    pi=3.141592653589793238
    k=30
    if(xy0<=3.)then
        y0=(2.*k-1.)+k*(-1)**k*xy0**2/(2.*k+1)
        do j=k-1,1,-1
            y0=(2.*j-1.)+j*(-1)**j*xy0**2/y0
        end do
        af=.5+xy0*exp(-.5*xy0**2)/y0/sqrt(2*pi)
    else
        y0=xy0+k/xy0
        do j=k-1,1,-1
            y0=xy0+j/y0
        end do
        af=1-exp(-.5*xy0**2)/y0/sqrt(2*pi)
    endif

    END SUBROUTINE

    SUBROUTINE af_beta(af,beta,ymult,zmult)
    real(irk) pi,af,y,xy0,x1,af1,u0,beta,gx,af0,ymult(:),zmult(:)

    PI=3.141592653589793238

    af0=af
    if(af<0.5)af=1-af0

    y=-dlog(4*af*(1-af))
    x1=sqrt(y*(2.0611786-5.7262204/(y+11.640595)))
    if(x1<=4.5)then
        xy0=x1
    else
        xy0=x1-.000637*x1**2-.010437*x1+.059374
    endif
    !      call af_normalx(xy0,af1,ymult,zmult)
    call af_normal(xy0,af1)
    gx=af1-af
    u0=exp(-.5*xy0**2)/sqrt(2*pi)
    beta=xy0-gx/u0*(1-.5*xy0*gx/u0)
    if(af0<0.5)then
        beta=-beta
        af=af0
    endif

    END SUBROUTINE

    !!!!!!!!!!!!
    !!!!!!!!!!
    SUBROUTINE unit_force_trans(igapb,kdimn,ij,unitg,igaps,ipairs,rvector)
    real(irk) coef1,rvector(:),unitg(:)
    integer(ink) igapb,igaps,ipairs,ij1,ij2,j0,ij,jpoin,jdimn,jtotv,nintf,iieq,iintf,kdimn,nnodei,nnodej

    nnodei=size(gaps(igaps)%pairnode(:,ipairs))  !2017/02/14
    nnodej=nnodei/2    !2017/02/14
    if(ij==1)then
        ij1=1
        ij2=1
        if(contactpe==2)then
            ij1=1
            !ij2=2*(ndimn-1)
            ij2=nnodej    !2017/02/14
        endif
    elseif(ij==2)then
        ij1=2
        ij2=2
        if(contactpe==2)then
            !ij1=2*(ndimn-1)+1
            !ij2=4*(ndimn-1)
            ij1=nnodej+1   !2017/02/14
            ij2=nnodei     !2017/02/14
        endif
    endif

    coef1=1.
    !if(contactpe==2)coef1=.5/(ndimn-1)
    if(contactpe==2)coef1=1./nnodej  !2017/02/14
    do j0=ij1,ij2
        jpoin=gaps(igaps)%pairnode(j0,ipairs)


        do jdimn=1,kdimn
            jtotv=nodfn(jdimn,jpoin)
            nintf=trans(jtotv)%nintf
            if(nintf/=0) then
                iieq=totveq(jtotv)
                if(iieq/=0)rvector(iieq)=0.
                do iintf=1,nintf
                    iieq=totveq(trans(jtotv)%listf(iintf))
                    if(iieq/=0) &
                        rvector(iieq)=rvector(iieq)+coef1*unitg(jdimn)*trans(jtotv)%rintf(iintf)
                end do
            else
                if(totveq(jtotv)/=0) &
                    rvector(totveq(jtotv))=rvector(totveq(jtotv))+coef1*unitg(jdimn)

            endif
        end do !jdimn
    end do
    end SUBROUTINE unit_force_trans
    !!!11
    !!!!!!!!!!
    SUBROUTINE unit_dis_force_trans(igapb,jpoin,kdimn,unitg,rvector) !20210820

    real(irk) rvector(:),unitg(:),dispoint
    real(irk),allocatable::dis_unit(:),load_unit(:),eload(:),value(:)
    integer(ink) kdimn,jpoin,igapb,igroup,jgroup,idofn,itotv,nintf,iieq,iintf,nevab, &
        ielem,ielgroup,jtotv
    integer(ink),pointer::ldofs(:)
    real(irk),   pointer::fstif(:,:)

    allocate(dis_unit(ntotv),load_unit(ntotv))
    dis_unit=0.;load_unit=0.

    do idofn=1,kdimn
        itotv=nodfn(idofn,jpoin)
        dis_unit(itotv)=unitg(idofn)
    end do

    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if (nintf==0) cycle
        dispoint=0.
        do iintf=1,nintf
            jtotv=trans(itotv)%listf(iintf)
            dispoint=dispoint+dis_unit(jtotv)*trans(itotv)%rintf(iintf)
        end do
        dis_unit(itotv)=dispoint
    end do


    do igroup=1,gapb(igapb)%ngroupb
        jgroup=gapb(igapb)%listgroupb(igroup)
        if (appear(jgroup)<=0) cycle
        nevab=size(element(group(jgroup)%list(1))%field(1)%ldofs_f)
        allocate(value(nevab),eload(nevab))
        nevab=0.;eload=0.
        DO ielgroup = 1,group(jgroup)%nelgroup
            ielem = group(jgroup)%list(ielgroup)

            if (associated(element(ielem)%field(1)%khandmc(1)%fstif)) then
                fstif=>element(ielem)%field(1)%khandmc(1)%fstif
                ldofs=>element(ielem)%field(1)%ldofs_f
                value=dis_unit(ldofs)
                eload=fstif.x.value
                load_unit(ldofs)=load_unit(ldofs)-eload
                nullify(fstif,ldofs)
            endif
        end do       !!ielgroup
        deallocate(value,eload)
    end do     !!  for igroup

    do itotv=1,ntotv
        if (totveq(itotv)==0)cycle
        rvector(totveq(itotv))=rvector(totveq(itotv))+load_unit(itotv)
    end do

    !!int2000
    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if (nintf==0) cycle
        do iintf=1,nintf
            iieq=totveq(trans(itotv)%listf(iintf))
            if(iieq/=0)rvector(iieq)=rvector(iieq)+  &
                load_unit(itotv)*trans(itotv)%rintf(iintf)
        end do
    end do
    !!int2000
    deallocate(dis_unit,load_unit)
    end SUBROUTINE unit_dis_force_trans  !20210820

    !!!

    subroutine result_node_to_center(kdimn,ij,igaps,ipairs,dx,dis)
    integer(ink) igaps,ipairs,ij1,ij2,j0,i12,ij,kdimn,nnodei,nnodej
    real(irk) coef1
    real(irk) dx(:),dis(:)

    nnodei=size(gaps(igaps)%pairnode(:,ipairs))  !2017/02/14
    nnodej=nnodei/2    !2017/02/14
    if(ij==1)then
        ij1=1
        ij2=1
        if(contactpe==2)then
            ij1=1
            !ij2=2*(ndimn-1)
            ij2=nnodej    !2017/02/14
        endif
    elseif(ij==2)then
        ij1=2
        ij2=2
        if(contactpe==2)then
            !ij1=2*(ndimn-1)+1
            !ij2=4*(ndimn-1)
            ij1=nnodej+1   !2017/02/14
            ij2=nnodei     !2017/02/14
        endif
    endif

    coef1=1.
    !if(contactpe==2)coef1=.5/(ndimn-1)
    if(contactpe==2)coef1=1./nnodej  !2017/02/14


    dis=0.
    do j0=ij1,ij2
        i12=gaps(igaps)%pairnode(j0,ipairs)
        dis=dis+coef1*dx(nodfn(1:kdimn,i12))
    end do  !j0
    end subroutine  result_node_to_center
    !!!!!!!!!!!!

    !!!!!!!!!!!!!!!!!!!!!!!!
    SUBROUTINE STATIC_rigid_reli  !20211016

    logical logx
    character(80)text
    integer(ink) itotv,ielem,irst,trstep0,ipoin,idofn,ij,idofix,ldofix,idelgroup,i0,ipairs
    integer(ink) ncmat,ncpld,nstoch
    real   (irk) xtime,time_begin,detal,ttime0,coef
    real   (irk),allocatable::rvectorm(:),value(:)
    integer(ink) iintf,nintf,iieq,ivcoh,ivfri   !!int2000

    integer(ink) igapb,npgblock,jpoin,igaps,ipair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,npairs,cwater   !!ctt2005
    real   (irk),allocatable::rot(:,:),tofor0(:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:) !!ctt2005

    integer(ink) iter,mkiter,i,j0,nbeta,ibeta,ic,Nv
    real(irk)    beta,er,gy
    integer(ink),allocatable::ja(:)
    real(irk),allocatable::xa(:),ya(:),sd(:),ed(:),ep(:),sp(:),ga(:),rc(:),ee(:),ss(:), &
        cov(:,:)

    read(stocunit,*)text
    read(stocunit,*)nbeta,nv,mkiter !number of radom,maximum iteration number

    allocate(betas(nbeta))
    do ibeta=1,nbeta
        allocate(betas(ibeta)%ga(nv))
        betas(ibeta)%ga=0.
    end do
    allocate(xa(nv),ya(nv),ed(nv),sd(nv),ep(nv),sp(nv),ga(nv),rc(nv),ja(nv),ee(nv),ss(nv))
    allocate(cov(nv,nv))

    read(stocunit,*)text
    read(stocunit,*)ja(:)  !distribution type:1,normal,2,log normal,3,extreme
    read(stocunit,*)ee(:)  !average value
    read(stocunit,*)ss(:)  !variance
    do i=1,nv
        read(stocunit,*)cov(i,:)  !correlation matrix
    end do

    !if(meshc==1.or.rmesh/=0)rewind(mainunit)

    read(mainunit,*)text
    read(mainunit,*)nincs

    print *,' in static_rigid_1**'

    if(ngaps/=0)allocate(tofor0(ntotv)) !!ctt2005

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    xtime=0.0
    do iincs=lincs+1,nincs
        print *,'iincs=',iincs

        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            allocate(coef_water(delgroup,nstep))
            do idelgroup=1,delgroup
                read(mainunit,*)i0,coef_water(idelgroup,:)
            end do
        end if

        do ibeta=1,nbeta !!!2018/01/10
            read(stocunit,*)text
            do igaps=1,ngaps
                read(stocunit,*)gaps(igaps)%ivcoh,gaps(igaps)%ivfri
            end do

            iter=0
            SP=ss
            EP=ee
            XA=EP
            YA=0.
            er=1.e-3

333         iter=iter+1
            CALL DANGLI(nv,EE,SS,XA,JA,SD,ED,SP,EP)
            do igaps=1,ngaps
                if(nforce_gaps_appear(igaps)==2.or.nforce_gaps_appear(igaps)==0)cycle
                ivcoh=gaps(igaps)%ivcoh
                ivfri=gaps(igaps)%ivfri
                if(ivcoh==0.and.ivfri==0)cycle
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs
                    if(ivfri>0) &
                        gaps(igaps)%frict(ipairs)=xa(ivfri)
                    if(ivcoh>0) &
                        gaps(igaps)%cohes(ipairs)=xa(ivcoh)
                end do
            end do


            ttime0=ttime
            trstep0=trstep
            do istep=inc_step,nstep,inc_step

                if(iblks>=stab_matde)call stab_initialize

                write(chkunit,*)'Increment step=',istep
                print *,'istep=',istep
                if(outintr>0.and.iblks>=outintr)trstep=trstep0+istep !20200226
                xtime=ditime*istep
                ttime=ttime0+ditime*istep !! only for output

                call dfact_time_curve(ttime)
                call modf_var_prescribed

                call gravity
                if(rmesh>0)call gravity1
                if(rmesh>1)call gravity2
                write(7,*)'cwater=',cwater,'delgroup=',delgroup
                if(cwater/=0.and.delgroup/=0)call step_water_pressure  !2013/3/18

222             call force_external
                !if(iblks/=1)mdiv=1   !5
                if(type_load=='LOAD2')mdiv=2  !!806
                do idiv=1,mdiv
                    !! temperature
                    if(type_load=='LOAD2'.and.idiv==2) goto 71
                    call load_of_creep_and_temperature
                    call creep_strain_of_rock_fill    !20130510
71                  if(mdiv/=1)toform=toforl+(tofor-toforl)*idiv/mdiv
                    if(ngaps/=0.and.mdiv==1)tofor0=tofor !!ctt2005
                    if(ngaps/=0.and.mdiv/=1)tofor0=toform !!ctt2005
                    deltafi=0.0
                    do igapb=1,ngapb !fzx  tcl
                        if(gapb(igapb)%nrdof==0)cycle
                        gapb(igapb)%rdisp_deltafi=0.
                    enddo


                    do iiter=1,miter
                        iccontact=0 !zhao 05/07/30
                        print *,'iblks=',iblks,'idiv=',idiv,'iiter=',iiter

                        call algort

                        if (iiter==1.or.(kstat==2.and.iiter.le.2))then
                            delitfi=0.0
                            call predict
                        endif

                        if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv==1)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005
                        if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv/=1)call ctfor_to_tofor(tofor0,toform)  !!ctt2005

                        logx=ngaps/=0.and.(iiter==1.and.istep==inc_step).and.iblks==iblks_bt
                        if (logx)then !ctt2005
                            if (restart_ctt==0)then !restart_ctt
                                do igapb=1,ngapb
                                    gapb(igapb)%cmatrix=0.
                                end do

                                call forAdirect !fzx !形成A矩阵
                                do igapb=1,ngapb
                                    do itotvbt=1,gapb(igapb)%ntotv_bt
                                        do jtotvbt=1,gapb(igapb)%ntotv_bt
                                            write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                        enddo
                                    enddo
                                enddo  !igapb

                            elseif(restart_ctt==1)then !restart_ctt
                                call forAdirect !fzx !形成A矩阵
                                rewind(recttunit)
                                do igapb=1,ngapb
                                    npgblock=gapb(igapb)%npgblock
                                    do itotvbt=1,gapb(igapb)%ntotv_bt
                                        do jtotvbt=1,gapb(igapb)%ntotv_bt
                                            read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                        enddo
                                    enddo
                                enddo
                            else !restart_ctt
                                write(*,*)'no such restart_ctt!!'
                                stop
                            endif !restart_ctt
                        endif  !!ctt2005
90                      format(10e12.5)

                        if(ngaps/=0.and.iblks>=abs(iblks_bt))call solve_ctt_rigid  !!ctt2005


                        call TIME(char_time)
                        print *, 'time: ', char_time
                        write(chkunit,*)'time: ', char_time


                        call varupdate
                        call conver_nodal_value
                        if(nchek==0)exit !tcl
10                      continue
                        print *,'miter=',miter,'iiter=',iiter
                    end do   !! loop for iiter

                    if(istatec==0) &
                        call state_and_stiff_rigid_2021
                    do igaps=1,ngaps
                        npairs=gaps(igaps)%npairs
                        do ipairs=1,npairs
                            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                            gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
                        end do
                    end do

                end do    !! for idiv


100             toforl=tofor

                if (istep/noutn*noutn==istep)then
                    iwriten=iwriten+1
                    call out_record
                    call outputres !for output
                endif


                if(nforce/=0.or.ngaps/=0)call force_interface  !2017/11/19
                if(kstab/=0.)call safety_factor  !2017/11/19

                if (istep/noutf*noutf==istep)then
                    if(nforce/=0.or.ngaps/=0)call write_force_interface
                    call out_full_write
                    if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                    if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
                endif

                if(istep/nresta*nresta==istep)call resta_read_write(-1)

            end do     !! loop for istep

            call stab_rcandgy_reli(rc,xa,gy)
            call RI3(nv,GY,GA,RC,XA,YA,SD,ED,SP,EP,cov)  !translation between the distributions
            write(7,*)'iter=',iter,'gy=',gy,'xa=',xa
            if(abs(gy)>er.and.iter<mkiter) goto 333
            call betaindex(nv,rc,ep,sp,xa,cov,beta) ! computation reliability index
            write(7,*)'ibeta=',ibeta,'iter=',iter,'gy=',gy

            betas(ibeta)%beta=beta
            betas(ibeta)%ga(:)=-ga
            write(7,*)'reliability index=',beta
            write(7,*)'experiment points=',xa
            write(7,*)'alfa=',-ga
        end do !ibeta !!!2018/01/10
        if(cwater/=0.and.delgroup>0)deallocate(coef_water)
    end do !!iincs
    if(sysrelis>0) &
        call system_reliability(nbeta,nv)

    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI
    if(ngaps/=0)deallocate(tofor0)  !!ctt2005

    END SUBROUTINE STATIC_rigid_reli !20211016

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!stoch
    SUBROUTINE STATIC_rigid_1

    logical logx
    character(80)text
    integer(ink) itotv,ielem,irst,trstep0,ipoin,idofn,ij,idofix,ldofix,idelgroup,i0,ipairs
    real   (irk) xtime,time_begin,detal,ttime0,coef
    real   (irk),allocatable::rvectorm(:),value(:)
    integer(ink) iintf,nintf,iieq   !!int2000

    integer(ink) igapb,npgblock,jpoin,igaps,ipair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,npairs,cwater,Qstatic   !!ctt2005
    real   (irk),allocatable::rot(:,:),tofor0(:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:) !!ctt2005

    !if(meshc==1.or.rmesh/=0)rewind(mainunit)

    read(mainunit,*)text
    read(mainunit,*)nincs

    print *,' in static_rigid_1**'

    if(ngaps/=0)allocate(tofor0(ntotv)) !!ctt2005
    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic
        read(mainunit,*)toler_force,toler_var(1:mdofn)

        if(cwater/=0.and.delgroup>0)then
            do idelgroup=1,delgroup
                read(mainunit,*)text
            end do
        end if
        if(Qstatic/=0) then !20221104
            do i0=1,6
                read(mainunit,*)text
            end do
        endif

    end do

    xtime=0.0
    do iincs=lincs+1,nincs
        print *,'iincs=',iincs

        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            allocate(coef_water(delgroup,nstep))
            do idelgroup=1,delgroup
                read(mainunit,*)i0,coef_water(idelgroup,:)
            end do
        end if

        if(Qstatic/=0) then !20221104
            read(mainunit,*)text  !20221104
            allocate(qstatic_force)  !20221104
            allocate(qstatic_force%appearg(ngroup),qstatic_force%qfactor(ndimn),qstatic_force%cor_coef(2,Qstatic))
            read(mainunit,*)qstatic_force%iaxe
            read(mainunit,*)qstatic_force%appearg
            read(mainunit,*)qstatic_force%qfactor
            read(mainunit,*)qstatic_force%cor_coef(1,:)
            read(mainunit,*)qstatic_force%cor_coef(2,:)
        endif !20221104


        ttime0=ttime
        trstep0=trstep
        do istep=inc_step,nstep,inc_step

            if(iblks>=stab_matde)call stab_initialize

            write(chkunit,*)'Increment step=',istep
            print *,'istep=',istep
            if(outintr>0.and.iblks>=outintr)trstep=trstep0+istep !20200226
            xtime=ditime*istep
            ttime=ttime0+ditime*istep !! only for output

            call dfact_time_curve(ttime)
            call modf_var_prescribed

            call gravity
            if(rmesh>0)call gravity1
            if(rmesh>1)call gravity2
            write(7,*)'cwater=',cwater,'delgroup=',delgroup
            if(cwater/=0.and.delgroup/=0)call step_water_pressure  !2013/3/18

222         call force_external
            !if(iblks/=1)mdiv=1   !5
            if(type_load=='LOAD2')mdiv=2  !!806
            do idiv=1,mdiv
                !! temperature
                if(type_load=='LOAD2'.and.idiv==2) goto 71
                call load_of_creep_and_temperature
                call creep_strain_of_rock_fill    !20130510
71              if(mdiv/=1)toform=toforl+(tofor-toforl)*idiv/mdiv
                if(ngaps/=0.and.mdiv==1)tofor0=tofor !!ctt2005
                if(ngaps/=0.and.mdiv/=1)tofor0=toform !!ctt2005
                deltafi=0.0
                do igapb=1,ngapb !fzx  tcl
                    if(gapb(igapb)%nrdof==0)cycle
                    gapb(igapb)%rdisp_deltafi=0.
                enddo


                do iiter=1,miter
                    iccontact=0 !zhao 05/07/30
                    print *,'iblks=',iblks,'idiv=',idiv,'iiter=',iiter

                    call algort

                    if (iiter==1.or.(kstat==2.and.iiter.le.2))then
                        delitfi=0.0
                        call predict
                    endif

                    if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv==1)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005
                    if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1.and.mdiv/=1)call ctfor_to_tofor(tofor0,toform)  !!ctt2005

                    logx=ngaps/=0.and.(iiter==1.and.istep==inc_step).and.iblks==iblks_bt
                    if (logx)then !ctt2005
                        if (restart_ctt==0)then !restart_ctt
                            do igapb=1,ngapb
                                gapb(igapb)%cmatrix=0.
                            end do

                            call forAdirect !fzx !形成A矩阵
                            do igapb=1,ngapb
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo  !igapb

                        elseif(restart_ctt==1)then !restart_ctt
                            call forAdirect !fzx !形成A矩阵
                            rewind(recttunit)
                            do igapb=1,ngapb
                                npgblock=gapb(igapb)%npgblock
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo
                        else !restart_ctt
                            write(*,*)'no such restart_ctt!!'
                            stop
                        endif !restart_ctt
                    endif  !!ctt2005
90                  format(10e12.5)

                    if(ngaps/=0.and.iblks>=abs(iblks_bt))call solve_ctt_rigid  !!ctt2005


                    call TIME(char_time)
                    print *, 'time: ', char_time
                    write(chkunit,*)'time: ', char_time


                    call varupdate
                    call conver_nodal_value
                    if(nchek==0)exit !tcl
10                  continue
                    print *,'miter=',miter,'iiter=',iiter
                end do   !! loop for iiter

                if(istatec==0) &
                    call state_and_stiff_rigid_2021
                do igaps=1,ngaps
                    npairs=gaps(igaps)%npairs
                    do ipairs=1,npairs
                        if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                        gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
                    end do
                end do

            end do    !! for idiv


100         toforl=tofor

            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
                call outputres !for output
            endif


            if(nforce/=0.or.ngaps/=0)call force_interface  !2017/11/19
            if(kstab/=0.)call safety_factor  !2017/11/19

            if (istep/noutf*noutf==istep)then
                if(nforce/=0.or.ngaps/=0)call write_force_interface
                call out_full_write
                if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif

            if(istep/nresta*nresta==istep)call resta_read_write(-1)

        end do     !! loop for istep
        if(cwater/=0.and.delgroup>0)deallocate(coef_water)
    end do !!iincs
    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI
    if(ngaps/=0)deallocate(tofor0)  !!ctt2005

    END SUBROUTINE STATIC_rigid_1


    subroutine forAdirect_back_analysis !20150925

    integer(ink) igapb,npgblock,onetwo,ipoin,jpoin,ipair,idimn,itotvbt,itotv,ielem, &
        kpoin,lpoin,jdimn,jtotv,jtotvbt,nevab,ieqx,ievab,igaps,nnode,ii,matno,index,order_int,ngaus, &
        ielgroup,igaus,igroup,jgroup,igapbf,kdimn,icg,ipoin0
    real   (irk) coef,tvol,density,djacb,rr,fact,xij
    real   (irk),allocatable::eldis(:),eload(:),rot(:,:),disgi(:,:),disli(:,:),dist(:),center(:),mass_inertia(:),gpcod(:),uirigid(:,:),disgi0(:,:)
    real   (irk),allocatable::coordx(:)
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)

    kdimn=ndimn
    if(block_stab==1)kdimn=3*(ndimn-1)
    allocate(center(ndimn),rot(ndimn,ndimn),dist(ndimn),disgi(ndimn,3*(ndimn-1)))
    if(block_stab/=1) allocate(disli(ndimn,3*(ndimn-1)))
    if(block_stab==1) allocate(disli(3*(ndimn-1),3*(ndimn-1)))
    if(type_problem=='F')allocate(mass_inertia(3*(ndimn-1)))

    write(7,*)'foradirect'

    allocate(gpcod(ndimn))
    do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb
        if(gapb(igapb)%nrdof==0) cycle   !tcl
        gapb(igapb)%center=0.;
        if(type_problem=='F')gapb(igapb)%mass_inertia=0.
        tvol=0.
        do igroup=1,gapb(igapb)%ngroupb
            jgroup=gapb(igapb)%listgroupb(igroup)
            matno = group(jgroup)%matno
            index = group(jgroup)%index
            density=props(matno)%mechanical%solid%density
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus
            do ielgroup=1,group(jgroup)%nelgroup
                ielem = group(jgroup)%list(ielgroup)

                do igaus=1,ngaus
                    djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                    gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                    gapb(igapb)%center=gapb(igapb)%center+djacb*gpcod*density
                    tvol=tvol+djacb*density
                end do
            enddo
        end do
        gapb(igapb)%center=gapb(igapb)%center/tvol
        write(7,*)'tvol=',tvol,'igapb=',igapb,'center=', gapb(igapb)%center

        if(type_problem=='F')then
            do igroup=1,gapb(igapb)%ngroupb
                jgroup=gapb(igapb)%listgroupb(igroup)
                matno = group(jgroup)%matno
                index = group(jgroup)%index
                density=props(matno)%mechanical%solid%density
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus = elkn(index)%ggaus(order_int)%ngaus
                do ielgroup=1,group(jgroup)%nelgroup
                    ielem = group(jgroup)%list(ielgroup)

                    do igaus=1,ngaus
                        djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                        gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                        if(ndimn==2)then
                            rr=(gpcod(1)-gapb(igapb)%center(1))**2+(gpcod(2)-gapb(igapb)%center(2))**2
                            gapb(igapb)%mass_inertia(1)=gapb(igapb)%mass_inertia(1)+djacb*density
                            gapb(igapb)%mass_inertia(2)=gapb(igapb)%mass_inertia(2)+djacb*density
                            gapb(igapb)%mass_inertia(3)=gapb(igapb)%mass_inertia(3)+djacb*rr*density
                        elseif(ndimn==3)then
                            gapb(igapb)%mass_inertia(1)=gapb(igapb)%mass_inertia(1)+djacb*density
                            gapb(igapb)%mass_inertia(2)=gapb(igapb)%mass_inertia(2)+djacb*density
                            gapb(igapb)%mass_inertia(3)=gapb(igapb)%mass_inertia(3)+djacb*density
                            rr=(gpcod(2)-gapb(igapb)%center(2))**2+(gpcod(3)-gapb(igapb)%center(3))**2
                            gapb(igapb)%mass_inertia(4)=gapb(igapb)%mass_inertia(4)+djacb*rr*density
                            rr=(gpcod(1)-gapb(igapb)%center(1))**2+(gpcod(3)-gapb(igapb)%center(3))**2
                            gapb(igapb)%mass_inertia(5)=gapb(igapb)%mass_inertia(5)+djacb*rr*density
                            rr=(gpcod(2)-gapb(igapb)%center(2))**2+(gpcod(1)-gapb(igapb)%center(1))**2
                            gapb(igapb)%mass_inertia(6)=gapb(igapb)%mass_inertia(6)+djacb*rr*density
                        endif

                    end do
                enddo
            end do
            write(7,*)'igapb=',igapb,'gapb(igapb)%mass_inertia=', gapb(igapb)%mass_inertia
        endif
    enddo

    deallocate(gpcod)


    do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb

        if(gapb(igapb)%nrdof==0) cycle   !tcl
        npgblock=gapb(igapb)%npgblock
        center=gapb(igapb)%center
        if(type_problem=='F')mass_inertia=gapb(igapb)%mass_inertia

        !write(7,*)'npdisp++++++++++++++'
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            dist=0.
            do jdimn=1,ndimn
                dist(jdimn)=coord(jdimn,ipoin)-center(jdimn)
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

            do idimn=1,gapb(igapb)%nrdof
                do jdimn=1,ndimn
                    gapb(igapb)%npdisp(jdimn,jpoin,idimn)=disgi(jdimn,idimn) !存每个点的位移，为计算A(T)F
                enddo
            end do
            if(block_stab==1)then
                do jdimn=ndimn+1,3*(ndimn-1)
                    gapb(igapb)%npdisp(jdimn,jpoin,jdimn)=1. !存每个点的位移，为计算A(T)F
                enddo
            endif
        enddo



        if(type_problem=='F')then
            do idimn=1,gapb(igapb)%nrdof
                gapb(igapb)%rstiff(idimn,idimn)=-mass_inertia(idimn) !20121216
            enddo !idimn
        endif

        if (restart_ctt/=0) cycle
        icg=0
        if(backf(igapbf)%mdism>npgblock*kdimn)then
            icg=1
            allocate(uirigid(backf(igapbf)%mdism,gapb(igapb)%nrdof))
        endif

        write(7,*)'icg=',icg


        do kpoin=1,backf(igapbf)%mdism
            allocate(coordx(ndimn))
            do idimn=1,ndimn
                coordx(idimn)=0.
                do i0=1,backf(igapbf)%relat(kpoin)%nintf
                    coordx(idimn)=coordx(idimn)+coord(idimn,backf(igapbf)%relat(kpoin)%listp(i0))*backf(igapbf)%relat(kpoin)%rintf(i0)
                end do
            end do
            !write(7,*)'kpoin=',kpoin,'coordx=',coordx
            dist=0.
            do jdimn=1,ndimn
                dist(jdimn)=coordx(jdimn)-center(jdimn)
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

            do idimn=1,gapb(igapb)%nrdof
                itotvbt=npgblock*kdimn+idimn
                jdimn=backf(igapbf)%listdim(kpoin)
                if(icg==0)gapb(igapb)%cmatrix(kpoin,itotvbt)=disgi(jdimn,idimn)
                if(icg==1)uirigid(kpoin,idimn)=disgi(jdimn,idimn)
            enddo !idimn
            deallocate(coordx)

        enddo !kpoin

        if(icg==1)then  !2015/11/28

            gapb(igapb)%cmatrix(1:npgblock*kdimn,npgblock*kdimn+1:npgblock*kdimn+gapb(igapb)%nrdof)=transpose(gapb(igapb)%uireact).x.uirigid

            deallocate(uirigid)
        endif   !2015/11/28


        do kpoin=1,npgblock
            onetwo=gapb(igapb)%nodegblock_onetwo(kpoin) !前四个点还是后四个点，也就是第一点还是第二点
            if(onetwo==1)coef=1.
            if(onetwo==2)coef=-1.
            igaps=gapb(igapb)%nodegblock_igaps(kpoin)
            ipair=gapb(igapb)%nodegblock_ipairs(kpoin)
            rot=gaps(igaps)%rot(:,:,ipair)


            dist=0.
            if(contactpe==1)then
                lpoin=gapb(igapb)%nodegblock(kpoin)
                do jdimn=1,ndimn
                    dist(jdimn)=coord(jdimn,lpoin)-center(jdimn)
                end do
            elseif(contactpe==2)then
                !nnode=2
                !if(ndimn==3)nnode=4
                nnode=size(gaps(igaps)%pairnode(:,ipair))/2  !2017/02/14

                do ii=1,nnode
                    jpoin=gaps(igaps)%pairnode((onetwo-1)*nnode+ii,ipair)
                    do jdimn=1,ndimn
                        dist(jdimn)=dist(jdimn)+(coord(jdimn,jpoin)-center(jdimn))/nnode
                    end do
                end do
            endif

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

            disli=0.
            if(block_stab/=1)then
                disli=rot.x.disgi
                disli=disli*coef
            elseif(block_stab==1)then
                disli(1:ndimn,:)=rot.x.disgi
                if(ndimn==2)disli(3,3)=1.
                if(ndimn==3) &
                    disli(ndimn+1:3*(ndimn-1),ndimn+1:3*(ndimn-1))=rot  !2015/11/17
                disli=disli*coef

                !write(7,*)'igapb=',igapb,'kpoin=',kpoin,'rot=',rot,'coef=',coef,'disli=',disli
            endif




            do idimn=1,gapb(igapb)%nrdof
                itotvbt=npgblock*kdimn+idimn
                do jdimn=1,kdimn
                    jtotvbt=(kpoin-1)*kdimn+jdimn
                    gapb(igapb)%cmatrix(itotvbt,jtotvbt)=disli(jdimn,idimn)   !2010/5/3
                    !write(7,*)'itotvbt=',itotvbt,'jtotvbt=',jtotvbt,'cmatrix=',gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                enddo
            enddo !idimn

        enddo !kpoin




45      format(15e15.3)

        if(type_problem=='F')then
            fact=1+damp_ctt*theta1*ditime
            do idimn=1,gapb(igapb)%nrdof
                itotvbt=npgblock*ndimn+idimn
                gapb(igapb)%cmatrix(itotvbt,itotvbt)=-mass_inertia(idimn)*fact
                gapb(igapb)%rstiff(idimn,idimn)=-mass_inertia(idimn) !20121216
            enddo !idimn
        endif

        !nullify(listrdof)
    enddo !igapb
    deallocate(rot,disgi,disli,dist,center)
    if(type_problem=='F')deallocate(mass_inertia)

    end subroutine forAdirect_back_analysis   !20150925


    subroutine forAdirect !fzx !形成A矩阵  2010/7/13

    integer(ink) igapb,npgblock,onetwo,ipoin,jpoin,ipair,idimn,itotvbt,itotv,ielem, &
        kpoin,lpoin,jdimn,jtotv,jtotvbt,nevab,ieqx,ievab,igaps,nnode,ii,matno,index,order_int,ngaus, &
        ielgroup,igaus,igroup,jgroup
    real   (irk) coef,tvol,density,djacb,rr,fact,thick
    real   (irk),allocatable::eldis(:),eload(:),rot(:,:),disgi(:,:),disli(:,:),dist(:),center(:),mass_inertia(:),gpcod(:)
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)


    allocate(center(ndimn),rot(ndimn,ndimn),dist(ndimn),disgi(ndimn,3*(ndimn-1)))
    if(block_stab/=1) allocate(disli(ndimn,3*(ndimn-1)))
    if(block_stab==1) allocate(disli(3*(ndimn-1),3*(ndimn-1)))
    if(type_problem=='F')allocate(mass_inertia(3*(ndimn-1)))
    !		   write(7,*)'npdisp in formatrixa *************jpoin,ipoin,gapb(igapb)%npdisp(:,jpoin,idimn)'

    write(7,*)'foradirect'

    allocate(gpcod(ndimn))
    do igapb=1,ngapb
        if(gapb(igapb)%nrdof==0) cycle   !tcl
        gapb(igapb)%center=0.;
        if(type_problem=='F')gapb(igapb)%mass_inertia=0.
        tvol=0.
        do igroup=1,gapb(igapb)%ngroupb
            jgroup=gapb(igapb)%listgroupb(igroup)
            if(jgroup<0)cycle  !20191031
            matno = group(jgroup)%matno
            index = group(jgroup)%index

            thick=1.
            if (ndimn==2.or.index==22.or.index==26)thick  =props(matno)%mechanical%solid%thickness     !20230910
            density=thick*props(matno)%mechanical%solid%density
            order_int=elkn(index)%el_field(1)%order_intrules(1)

            ngaus = elkn(index)%ggaus(order_int)%ngaus
            do ielgroup=1,group(jgroup)%nelgroup
                ielem = group(jgroup)%list(ielgroup)

                do igaus=1,ngaus
                    djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                    gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                    gapb(igapb)%center=gapb(igapb)%center+djacb*gpcod*density
                    tvol=tvol+djacb*density
                end do
            enddo
        end do
        gapb(igapb)%center=gapb(igapb)%center/tvol
        write(7,*)'tvol=',tvol,'igapb=',igapb,'center=', gapb(igapb)%center

        if(type_problem=='F')then
            do igroup=1,gapb(igapb)%ngroupb
                jgroup=gapb(igapb)%listgroupb(igroup)
                if(jgroup<0)cycle  !20191031
                matno = group(jgroup)%matno
                index = group(jgroup)%index
                thick=1.
                if (ndimn==2.or.index==22.or.index==26)thick  =props(matno)%mechanical%solid%thickness
                density=thick*props(matno)%mechanical%solid%density
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus = elkn(index)%ggaus(order_int)%ngaus
                do ielgroup=1,group(jgroup)%nelgroup
                    ielem = group(jgroup)%list(ielgroup)

                    do igaus=1,ngaus
                        djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                        gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                        if(ndimn==2)then
                            rr=(gpcod(1)-gapb(igapb)%center(1))**2+(gpcod(2)-gapb(igapb)%center(2))**2
                            gapb(igapb)%mass_inertia(1)=gapb(igapb)%mass_inertia(1)+djacb*density
                            gapb(igapb)%mass_inertia(2)=gapb(igapb)%mass_inertia(2)+djacb*density
                            gapb(igapb)%mass_inertia(3)=gapb(igapb)%mass_inertia(3)+djacb*rr*density
                        elseif(ndimn==3)then
                            gapb(igapb)%mass_inertia(1)=gapb(igapb)%mass_inertia(1)+djacb*density
                            gapb(igapb)%mass_inertia(2)=gapb(igapb)%mass_inertia(2)+djacb*density
                            gapb(igapb)%mass_inertia(3)=gapb(igapb)%mass_inertia(3)+djacb*density
                            rr=(gpcod(2)-gapb(igapb)%center(2))**2+(gpcod(3)-gapb(igapb)%center(3))**2
                            gapb(igapb)%mass_inertia(4)=gapb(igapb)%mass_inertia(4)+djacb*rr*density
                            rr=(gpcod(1)-gapb(igapb)%center(1))**2+(gpcod(3)-gapb(igapb)%center(3))**2
                            gapb(igapb)%mass_inertia(5)=gapb(igapb)%mass_inertia(5)+djacb*rr*density
                            rr=(gpcod(2)-gapb(igapb)%center(2))**2+(gpcod(1)-gapb(igapb)%center(1))**2
                            gapb(igapb)%mass_inertia(6)=gapb(igapb)%mass_inertia(6)+djacb*rr*density
                        endif

                    end do
                enddo
            end do
            write(7,*)'igapb=',igapb,'gapb(igapb)%mass_inertia=', gapb(igapb)%mass_inertia
        endif
    enddo

    deallocate(gpcod)


    do igapb=1,ngapb

        if(gapb(igapb)%nrdof==0) cycle   !tcl
        npgblock=gapb(igapb)%npgblock
        center=gapb(igapb)%center
        if(type_problem=='F')mass_inertia=gapb(igapb)%mass_inertia

        !write(7,*)'npdisp++++++++++++++'
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            dist=0.
            do jdimn=1,ndimn
                dist(jdimn)=coord(jdimn,ipoin)-center(jdimn)
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

            do idimn=1,gapb(igapb)%nrdof
                do jdimn=1,ndimn
                    gapb(igapb)%npdisp(jdimn,jpoin,idimn)=disgi(jdimn,idimn) !存每个点的位移，为计算A(T)F
                enddo
            end do
            if(block_stab==1)then
                do jdimn=ndimn+1,3*(ndimn-1)
                    gapb(igapb)%npdisp(jdimn,jpoin,jdimn)=1. !存每个点的位移，为计算A(T)F
                enddo
            endif
            !		  write(7,*)jpoin,ipoin,gapb(igapb)%npdisp(:,jpoin,:)
        enddo


        !do idimn=1,gapb(igapb)%nrdof
        !         gapb(igapb)%rstiff(idimn,idimn)=1.e-5 !20121216
        !enddo !idimn


        ! if(type_problem=='F')then
        ! do idimn=1,gapb(igapb)%nrdof
        !             gapb(igapb)%rstiff(idimn,idimn)=-mass_inertia(idimn) !20121216
        !    enddo !idimn
        !endif

        if (restart_ctt/=0) cycle

        do kpoin=1,npgblock
            onetwo=gapb(igapb)%nodegblock_onetwo(kpoin) !前四个点还是后四个点，也就是第一点还是第二点
            if(onetwo==1)coef=1.
            if(onetwo==2)coef=-1.
            igaps=gapb(igapb)%nodegblock_igaps(kpoin)
            ipair=gapb(igapb)%nodegblock_ipairs(kpoin)
            rot=gaps(igaps)%rot(:,:,ipair)


            dist=0.
            if(contactpe==1)then
                lpoin=gapb(igapb)%nodegblock(kpoin)
                do jdimn=1,ndimn
                    dist(jdimn)=coord(jdimn,lpoin)-center(jdimn)
                end do
            elseif(contactpe==2)then
                nnode=2
                if(ndimn==3)nnode=4
                do ii=1,nnode
                    jpoin=gaps(igaps)%pairnode((onetwo-1)*nnode+ii,ipair)
                    do jdimn=1,ndimn
                        dist(jdimn)=dist(jdimn)+(coord(jdimn,jpoin)-center(jdimn))/nnode
                    end do
                end do
            endif

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

            disli=0.
            if(block_stab/=1)then
                disli=rot.x.disgi
                disli=disli*coef
            elseif(block_stab==1)then
                disli(1:ndimn,:)=rot.x.disgi
                if(ndimn==2)disli(3,3)=1.
                if(ndimn==3) &
                    disli(ndimn+1:3*(ndimn-1),ndimn+1:3*(ndimn-1))=rot
                disli=disli*coef

                !write(7,*)'igapb=',igapb,'kpoin=',kpoin,'rot=',rot,'coef=',coef,'disli=',disli
            endif



            if(block_stab/=1)then
                do idimn=1,gapb(igapb)%nrdof
                    itotvbt=npgblock*ndimn+idimn
                    do jdimn=1,ndimn
                        jtotvbt=(kpoin-1)*ndimn+jdimn
                        gapb(igapb)%cmatrix(jtotvbt,itotvbt)=disli(jdimn,idimn)
                        gapb(igapb)%cmatrix(itotvbt,jtotvbt)=disli(jdimn,idimn)   !2010/5/3
                    enddo
                enddo !idimn
            elseif(block_stab==1)then
                do idimn=1,gapb(igapb)%nrdof
                    itotvbt=npgblock*3*(ndimn-1)+idimn
                    do jdimn=1,3*(ndimn-1)
                        jtotvbt=(kpoin-1)*3*(ndimn-1) +jdimn
                        gapb(igapb)%cmatrix(jtotvbt,itotvbt)=disli(jdimn,idimn)
                        gapb(igapb)%cmatrix(itotvbt,jtotvbt)=disli(jdimn,idimn)   !2010/5/3
                    enddo
                enddo !idimn
            endif

        enddo !kpoin

        !write(7,*)'igapb=',igapb
        !   write(7,*)'cmatrix='
        !   do itotvbt=1,gapb(igapb)%ntotv_bt
        !       write(7,45)gapb(igapb)%cmatrix(itotvbt,:)
        !   end do
45      format(15e15.3)

        if(type_problem=='F'.and.gapb(igapb)%eblock==0)then
            fact=1+damp_ctt*theta1*ditime
            do idimn=1,gapb(igapb)%nrdof
                itotvbt=npgblock*ndimn+idimn
                gapb(igapb)%cmatrix(itotvbt,itotvbt)=-mass_inertia(idimn)*fact
                gapb(igapb)%rstiff(idimn,idimn)=-mass_inertia(idimn) !20121216
            enddo !idimn
        endif


        !nullify(listrdof)
    enddo !igapb
    deallocate(rot,disgi,disli,dist,center)
    if(type_problem=='F')deallocate(mass_inertia)

    end subroutine forAdirect   !tcl

    subroutine matrix_rigid_dis   !20211121
    character(20) text
    integer(ink) igapb,npgblock,ipoin,jpoin,idimn,itotvbt,itotv,ielem, &
        kpoin,lpoin,jdimn,jtotv,jtotvbt,nevab,ieqx,ievab,igaps,nnode,ii,matno,index,order_int,ngaus, &
        ielgroup,igaus,igroup,jgroup,igdis_bk,ngroup_bk,npoin_bk
    integer(ink),allocatable:: appear_gdis_bk(:)
    integer(ink),pointer:: lnods(:)
    real   (irk) tvol,density,djacb,fact,thick
    real   (irk),allocatable::disgi(:,:),dist(:),center(:),gpcod(:),cor(:)

    read(back_ctl_unit,*)text
    print *,'text=',text
    read(back_ctl_unit,*)ngdis_bk
    print *,'ngdis_bk=',ngdis_bk
    allocate(rigid_bk(ngdis_bk),appear_gdis_bk(ngroup))

    read(back_ctl_unit,*)text
    do igdis_bk=1,ngdis_bk
        allocate(rigid_bk(igdis_bk)%fixed_dis(3*(ndimn-1)))
        read(back_ctl_unit,*)rigid_bk(igdis_bk)%fixed_dis
        print *,'fixed_dis=',rigid_bk(igdis_bk)%fixed_dis
        read(back_ctl_unit,*)appear_gdis_bk(:)
        print *,'appear_gdis_bk=',appear_gdis_bk
        read(back_ctl_unit,*)npoin_bk
        rigid_bk(igdis_bk)%npoin_bk=npoin_bk
        allocate(rigid_bk(igdis_bk)%node_bk(npoin_bk))
        read(back_ctl_unit,*)rigid_bk(igdis_bk)%node_bk  !对应的是para_points(1:npoints_pb)的序号
        ngroup_bk=sum(appear_gdis_bk)
        print *,'ngroup_bk=',ngroup_bk
        rigid_bk(igdis_bk)%ngroup_bk=ngroup_bk
        allocate(rigid_bk(igdis_bk)%group_bk(ngroup_bk))
        ngroup_bk=0
        do igroup=1,ngroup
            if(appear_gdis_bk(igroup)==0)cycle
            ngroup_bk=ngroup_bk+1
            rigid_bk(igdis_bk)%group_bk(ngroup_bk)=igroup
        end do
        print *,'ngroup_bk=',ngroup_bk
        print *,'rigid_bk(igdis_bk)%group_bk=',rigid_bk(igdis_bk)%group_bk

    end do

    allocate(gpcod(ndimn),cor(ndimn),center(ndimn),dist(ndimn),disgi(ndimn,3*(ndimn-1)))

    do igdis_bk=1,ngdis_bk

        allocate(rigid_bk(igdis_bk)%center(ndimn))
        rigid_bk(igdis_bk)%center=0.
        tvol=0.
        do jgroup=1,rigid_bk(igdis_bk)%ngroup_bk
            igroup=rigid_bk(igdis_bk)%group_bk(jgroup)
            !print *,'jgroup=',igroup
            matno = group(igroup)%matno
            index = group(igroup)%index

            thick=1.
            if (ndimn==2.or.index==22.or.index==26)thick  =props(matno)%mechanical%solid%thickness
            density=thick*props(matno)%mechanical%solid%density
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus
            do ielgroup=1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                lnods=>element(ielem)%field(1)%lnods_f

                nullify(lnods)
                do igaus=1,ngaus
                    djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                    gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                    rigid_bk(igdis_bk)%center=rigid_bk(igdis_bk)%center+djacb*gpcod*density
                    tvol=tvol+djacb*density
                end do
            enddo  !ielgroup
        end do  !jgroup
        rigid_bk(igdis_bk)%center=rigid_bk(igdis_bk)%center/tvol
    enddo  !igdis_bk
    deallocate(gpcod)


    do igdis_bk=1,ngdis_bk
        npoin_bk=rigid_bk(igdis_bk)%npoin_bk
        allocate(rigid_bk(igdis_bk)%npdisp(ndimn,npoin_bk,3*(ndimn-1)))
        rigid_bk(igdis_bk)%npdisp=0.

        center=rigid_bk(igdis_bk)%center
        write(7,*)'igdis_bk=',igdis_bk,'center=',center

        !write(7,*)'npdisp++++++++++++++'
        do jpoin=1,npoin_bk
            ipoin=rigid_bk(igdis_bk)%node_bk(jpoin)
            cor=para_points(jpoin)%cor
            !write(7,*)'jpoin=',jpoin,'cor=',cor
            dist=0.
            do jdimn=1,ndimn
                dist(jdimn)=cor(jdimn)-center(jdimn)
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

            do idimn=1,3*(ndimn-1)
                do jdimn=1,ndimn
                    rigid_bk(igdis_bk)%npdisp(jdimn,jpoin,idimn)=disgi(jdimn,idimn) !存每个点的位移，为计算A(T)F
                enddo
            end do
            !		  write(7,*)jpoin,ipoin,gapb(igapb)%npdisp(:,jpoin,:)
        enddo

    enddo !igapb
    deallocate(disgi,dist,cor,center,appear_gdis_bk)
45  format(15e15.3)


    end subroutine matrix_rigid_dis   !20211121

    subroutine matrix_nodal_value   !20211201
    character(20) text
    integer(ink) ipoin,igroup,jgroup,ielem,ielgroup,igdis_bk,ngroup_bk, &
        npoin_bk,ndofn_bk
    integer(ink),allocatable:: appear_nodvar_bk(:),listnode(:)
    integer(ink),pointer:: lnods(:)

    read(back_ctl_unit,*)text
    read(back_ctl_unit,*)ngval_bk
    allocate(nodvar_bk(ngval_bk),appear_nodvar_bk(ngroup))

    read(back_ctl_unit,*)text
    do igdis_bk=1,ngval_bk
        read(back_ctl_unit,*)ndofn_bk
        nodvar_bk(igdis_bk)%ndofn_bk=ndofn_bk
        allocate(nodvar_bk(igdis_bk)%dof_bk(ndofn_bk))
        read(back_ctl_unit,*)nodvar_bk(igdis_bk)%dof_bk

        read(back_ctl_unit,*)appear_nodvar_bk(:)
        ngroup_bk=sum(appear_nodvar_bk)
        nodvar_bk(igdis_bk)%ngroup_bk=ngroup_bk
        allocate(nodvar_bk(igdis_bk)%group_bk(ngroup_bk))
        ngroup_bk=0
        do igroup=1,ngroup
            if(appear_nodvar_bk(igroup)==0)cycle
            ngroup_bk=ngroup_bk+1
            nodvar_bk(igdis_bk)%group_bk(ngroup_bk)=igroup
        end do
        print *,'ngroup_bk=',ngroup_bk
        print *,'nodvar_bk(igdis_bk)%group_bk=',nodvar_bk(igdis_bk)%group_bk

    end do

    allocate (listnode(npoin))
    do igdis_bk=1,ngval_bk
        listnode=0

        do jgroup=1,nodvar_bk(igdis_bk)%ngroup_bk
            igroup=nodvar_bk(igdis_bk)%group_bk(jgroup)
            do ielgroup=1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                lnods=>element(ielem)%field(1)%lnods_f
                listnode(lnods)=1
                nullify(lnods)
            enddo  !ielgroup
        end do  !jgroup
        npoin_bk=sum(listnode)
        nodvar_bk(igdis_bk)%npoin_bk=npoin_bk
        allocate(nodvar_bk(igdis_bk)%node_bk(npoin_bk),nodvar_bk(igdis_bk)%nodet_bk(npoin))

        npoin_bk=0
        nodvar_bk(igdis_bk)%nodet_bk=0
        do ipoin=1,npoin
            if(listnode(ipoin)==0)cycle
            npoin_bk=npoin_bk+1
            nodvar_bk(igdis_bk)%node_bk(npoin_bk)=ipoin
            nodvar_bk(igdis_bk)%nodet_bk(ipoin)=npoin_bk
        end do
    enddo  !igdis_bk

    deallocate(appear_nodvar_bk,listnode)


    end subroutine matrix_nodal_value   !20211201

    !!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine write_stiff_u

    integer(ink) igroup,ielgroup,ielem,matno,icreep
    character(10)field1,name
    character(20)material

    rewind(midstif)
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid
        if (field1(1:1)=='U'.and.appear(igroup)>0)  then
            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            icreep =props(matno)%mechanical%solid%icreep
            if (name=='CONTACT'.or.material/='ELASTIC_ISOTROPIC'.or.   &
                (material=='ELASTIC_ISOTROPIC'.and.icreep/=0))then
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    write(midstif) element(ielem)%field(1)%khandmc(1)%fstif
                end do
            endif
        endif
    end do

    end subroutine write_stiff_u

    SUBROUTINE neuman_expan

    !! need the zero, firt, second deritives of the result, store in the ntotv order
    !!          result_zero, result_first, result_second

    character(10)fieldid,name
    character(20)material
    integer(ink) igroup,index,nevab,ielgroup,ielem,itotv,iter_neuman,ichk,eigen,matno,icreep
    integer(ink), pointer::ldofs(:)
    real   (irk), allocatable::value(:),fstif0(:,:),refu(:),result0(:),resultn(:),deliu(:), &
        eload(:),result_org(:)
    real   (irk), pointer::fstif(:,:)
    real   (irk) err,fmfold,rld
    allocate(refu(ntotv),result0(ntotv),resultn(ntotv),deliu(ntotv))
    allocate(result_org(ntotv))
    eigen=0
    result_org=result
10  iter_neuman=0
    fmfold=1.
    result0=result/fmfold
    resultn=result/fmfold
1   iter_neuman=iter_neuman+1
    where(iffix==0)
        deliu=result0
    elsewhere
        deliu=0.
    endwhere
    refu=0.0
    rewind(midstif)
    DO igroup =1,ngroup
        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='U') then
            matno=group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            icreep =props(matno)%mechanical%solid%icreep
            if (name=='CONTACT'.or.material/='ELASTIC_ISOTROPIC'.or.   &
                (material=='ELASTIC_ISOTROPIC'.and.icreep/=0))then
                ! get information from the group level
                index=group(igroup)%index
                nevab=elkn(index)%el_field(1)%nnode_f*group(igroup)%dof(1)%nfdof
                allocate(value(nevab),fstif0(nevab,nevab),eload(nevab))
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    read(midstif)fstif0
                    fstif=>element(ielem)%field(1)%khandmc(1)%fstif
                    ldofs=>element(ielem)%field(1)%ldofs_f
                    fstif0=fstif/fmfold-fstif0
                    value=deliu(ldofs)
                    eload=MATMUL(fstif0,value)
                    refu(ldofs)=refu(ldofs)+eload
                    nullify(fstif,ldofs)
                end do       !!ielgroup
                deallocate(value,fstif0,eload)
            endif
        endif
    enddo !for igroup

    rvector=0.
    do itotv=1,ntotv
        if(totveq(itotv)/=0)     &
            rvector(totveq(itotv))=rvector(totveq(itotv))+refu(itotv)
    end do

    operation='SOLVE'
    call solve
    resultn=resultn+(-1)**iter_neuman*result
    err=MAXVAL(abs(result))/MAXVAL(abs(resultn))
    ichk=0
    write(chkunit,*)'iter_neuman==',iter_neuman,'err=',err
    if(err.le.1.e-1.or.iter_neuman.eq.30)ichk=1
    if (ichk==0)then
        !      if((iter_neuman==20.or.err.ge.1.0).and.eigen==0) then
        if (err.ge.1.0.and.eigen==0) then
            print *,'neuman expansion failed!'
            stop
            eigen=1
            call eigv(rld)
            fmfold=(rld+1.)/2.+.2
            result=result_org
            goto 10
        else
            result0=result
            goto 1
        endif
    endif
    print *,'iter_neuman=',iter_neuman,'err=',err
    result=resultn
    deallocate(refu,result0,resultn,deliu,result_org)

    END SUBROUTINE neuman_expan

    !!!!!!!
    SUBROUTINE kdelt(ic,ics,result0,refu)

    character(10)fieldid
    integer(ink) igroup,index,ic,ics,nevab, ielgroup, ielem, itotv
    integer(ink),pointer::ldofs(:)
    real   (irk),allocatable::value(:),fstif0(:,:), eload(:),deliu(:)
    real   (irk),pointer::fstif(:,:)
    real   (irk) result0(:),refu(:)

    allocate(deliu(ntotv))
    where(iffix==0)
        deliu=result0
    elsewhere
        deliu=0.
    endwhere
    refu=0.0
    if(ic==2)rewind(midstif)
    DO igroup =1,ngroup
        fieldid = group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='U') then
            ! get information from the group level
            index=group(igroup)%index
            nevab=elkn(index)%el_field(1)%nnode_f*group(igroup)%dof(1)%nfdof
            allocate(value(nevab),fstif0(nevab,nevab),eload(nevab))
            DO ielgroup=1,group(igroup)%nelgroup
                ielem=group(igroup)%list(ielgroup)
                if(ic==2)read(midstif)fstif0
                fstif=>element(ielem)%field(1)%khandmc(1)%fstif
                ldofs=>element(ielem)%field(1)%ldofs_f
                if (ic==1)then
                    fstif0=fstif
                else
                    fstif0=fstif-fstif0
                endif
                value=deliu(ldofs)
                eload=MATMUL(fstif0,value)
                refu(ldofs)=refu(ldofs)+eload
                nullify(fstif,ldofs)
            enddo !!ielgroup
            deallocate(value,fstif0,eload)
        endif
    enddo     !!  for igroup
    deallocate(deliu)
    if(ics==0)return
    rvector=0.
    do itotv=1,ntotv
        if(totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))+refu(itotv)
    end do
    operation='SOLVE'
    call solve

    END SUBROUTINE kdelt
    ! ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    !for the first eigenvalue with rld*K*delta=dK*delta

    SUBROUTINE EIGV (rld)

    integer(ink) num
    real   (irk) rec,aa,bb,rld,re,r3,r4
    real   (irk), allocatable::refu(:)
    print *,'******','EIGENNALUE CALCULATION','*******'
    allocate(refu(ntotv))
    NUM=0
    BB=0.0
    REC=1.0E-7
    result=1.
12  call kdelt(2,1,result,refu)
    RLD=maxval(abs(result))
    IF(rld.LT.0.00001) print *, 'AAA1'
    result=result/rld
    RE=0.0
    R3=0.0
    R4=0.0
    call kdelt(1,0,result,refu)
    r3=result.d.refu
    call kdelt(2,0,result,refu)
    r4=result.d.refu
    RLD=abs(R4/R3)
    AA=RLD
    RE=ABS(AA-BB)/AA
    IF (RE.GT.REC) BB=AA
    NUM=NUM+1
    IF (NUM.GT.150) GOTO 165
    print *, 'num=',num,'rld=',rld
    IF (RE.LE.REC) GOTO 165
    GO TO 12
165 CONTINUE
    !   WO=1.0/SQRT(AA)
    !   TO=6.2832/WO
    !   FO=1./TO
    deallocate(refu)
    WRITE(chkunit,*) 'num=',num,'rld=',rld

    RETURN

    END subroutine eigv

    !::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    SUBROUTINE STATIC_U_P

    character(80)text
    integer(ink) itotv,ielem,trstep0
    real   (irk) time,ttime0
    integer(ink) iintf,nintf,iieq   !!int2000

    print *,'in static_u_p'
    read(mainunit,*)text
    read(mainunit,*)nincs

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    time=0.0
    do iincs=lincs+1,nincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        ttime0=ttime
        trstep0=trstep
        do istep=inc_step,nstep,inc_step
            if (outintr>0.and.iblks>=outintr)trstep=trstep0+istep !20200226
            time=ditime*istep
            ttime=ttime0+ditime*istep        !! only for output
            call dfact_time_curve(ttime)
            call modf_var_prescribed
            call gravity
            call force_external
            do ielem=1,nelem   !!simo_rifai
                if (associated(element(ielem)%alfa))element(ielem)%alfa=0.
            end do  !!simo_rifai

            do iiter=1,miter

                if  (iiter==1) then
                    deltafi=0.0
                    delitfi=0.
                endif

                call algort

                if (iiter==1)call predict   ! new

                if (kresl/=0)call stiff_u
                if (ksmat/=0)call mcmatrx('P')
                if (kqmat/=0)call upwcouple

                if  (kresl/=0.or.ksmat/=0.or.kqmat/=0) then
                    if (type_solver/='JPCG')global_stiff1=0.0
                    if (nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                    if  (type_solver=='JPCG')then
                        do ielem=1,nelem
                            element(ielem)%estif=0.0
                        end do
                    endif
                    call estif_assemble
                    call couple_assemble
                endif

                !            if (iiter==1.and.istep==inc_step) then   !! iiter==1 and istep==inc_step
                if (iiter==1) then   !! iiter==1 and istep==inc_step
1                   call eload_initialize
                    if ((ninit/=0.and.((iblks==1.and.kinit==1)).or.(kinit==2.and.iincs==1))) then

                        call eload_initial_stress
                        call gpvar2_initial
                        if (kinit==2.and.iincs==1)then
                            call force_release
                            where(totveq==0)
                                torel=0.0
                            endwhere
                        endif

                    endif
                    call residu_f
                    !           if(iblks/=1.or.(iblks==1.and.iincs/=1))call residu_f
                    call eload_field
                    call eload_couple

                    call force_internal

                endif    !! end for iiter==1 and istep==inc_step

                if (iiter==1.and.allocated(torel))tofor=tofor+torel


                rvector=0.0
                if (type_solver/='JPCG') then
                    do itotv=1,ntotv
                        if (totveq(itotv)/=0)     &
                            rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                            tofor(itotv)-stfor(itotv)
                    end do



                    !!int2000
                    do itotv=1,ntotv
                        nintf=trans(itotv)%nintf
                        if (nintf/=0) then
                            iieq=totveq(itotv)
                            if (iieq/=0)rvector(iieq)=0.
                            do iintf=1,nintf
                                iieq=totveq(trans(itotv)%listf(iintf))
                                if (iieq/=0) &
                                    rvector(iieq)=rvector(iieq)+  &
                                    (tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                            end do
                        endif
                    end do
                    !!int2000
                else
                    rvector=tofor-stfor
                endif


                if (type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR

                if (type_solver=='PROFILE'.and.               &
                    (kresl/=0.or.ksmat/=0.or.khmat/=0.or.kqmat/=0)) then
                    operation='FACTORIZE'
                    call solve
                end if

2               if(type_nl==8) then
                    if (kstat/=2)call bfgsr(iiter)
                    if (kstat==2)call bfgsr(iiter-1)
                else
                    operation='SOLVE'
                    call solve
                endif

                where(iffix==0)
                    delitfi=result
                    deltafi=deltafi+delitfi
                endwhere
                where(iffix==0)
                    result_zero=result_zero+delitfi
                endwhere
                call eload_initialize
                call residu_f
                call eload_field
                call eload_couple
                call reaction_prescribed
                call conver_load

                if (nchek==0)call conver_nodal_value
                if (nchek==0)exit

            end do   !! loop for iiter

            call gpvarupdate

            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
            endif

            if (istep/noutf*noutf==istep)then
                call out_full_write
                if (outplot(1:3)=='GID')   call OUT_GID_WRITE
                if (outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif
            if (istep/nresta*nresta==istep)call resta_read_write(-1)

        end do     !! loop for istep

    end do     !! loop for iincs

    END SUBROUTINE STATIC_U_P


    SUBROUTINE STATIC_U_PW


    logical logx
    character(80)text
    integer(ink) i,ii,itotv,ielem,irst,trstep0,ipoin,idofn,ij,ij0,idofix,ldofix,idelgroup,i0,ipairs
    real   (irk) xtime,time_begin,detal,ttime0,coef,pvalue,Tpredict !20230216
    real   (irk),allocatable::rvectorm(:),value(:)
    integer(ink) iintf,nintf,iieq,njntf,icdofn,ifixset   !!20230216  !!20220626
    integer(ink) iincs_i,iblks_i,istep_i,inode,jnode,ivalue,ivalue_point,bblks,mfixset,j  !20231130
    integer(ink),pointer::listf(:)  !20200819
    real   (irk),pointer::rintf(:)  !20200819

    integer(ink) igapb,npgblock,jpoin,igaps,ipair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,npairs,cwater,jgaps,jpair,kdimn   !!ctt2005
    real   (irk),allocatable::rot(:,:),tofor0(:),midt(:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:) !!ctt2005
    real   (irk),allocatable::observstar(:),dtv(:),dtvi(:) !20230216
    real   (irk),allocatable::cmatrix_dtv(:,:),inv_cmatrix_dtv2(:,:)  !20230216



    print *,'static_U_Pw'
    if (meshc==1.or.rmesh/=0)rewind(mainunit)
    if(Bparameter/=0.and.iblks==1)rewind(mainunit)  !20230902
    if(Bparameter/=0.and.iblks==1)rewind(upliftunit)

    read(mainunit,*)text
    read(mainunit,*)nincs

    if(ngaps/=0.or.nrcsteel/=0)allocate(tofor0(ntotv)) !!ctt2005



    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(cwater/=0.and.delgroup>0)then
            do idelgroup=1,delgroup
                read(mainunit,*)text
            end do
        end if
        if(Qstatic/=0) then !20221104
            do i0=1,6
                read(mainunit,*)text
            end do
        endif

    end do

    xtime=0.0
    do iincs=lincs+1,nincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,cwater,Qstatic
        read(mainunit,*)toler_force,toler_var(1:mdofn)

        if(cwater/=0.and.delgroup>0)then
            allocate(coef_water(delgroup,nstep))
            do idelgroup=1,delgroup
                read(mainunit,*)i0,coef_water(idelgroup,:)
            end do
        end if


        if(Qstatic/=0) then !20221104
            read(mainunit,*)text  !20221104
            allocate(qstatic_force)  !20221104
            allocate(qstatic_force%appearg(ngroup),qstatic_force%qfactor(ndimn),qstatic_force%cor_coef(2,Qstatic))
            read(mainunit,*)qstatic_force%iaxe
            read(mainunit,*)qstatic_force%appearg
            read(mainunit,*)qstatic_force%qfactor
            read(mainunit,*)qstatic_force%cor_coef(1,:)
            read(mainunit,*)qstatic_force%cor_coef(2,:)
        endif !20221104


        ttime0=ttime
        trstep0=trstep

        do istep=inc_step,nstep,inc_step
            if(iblks>=stab_matde)call stab_initialize
            if (outintr>0.and.iblks>=outintr)trstep=trstep0+istep !20200226

            xtime=ditime*istep
            ttime=ttime0+ditime*istep        !! only for output

            call dfact_time_curve(ttime)
            call modf_var_prescribed

            call saturation_judge

            call gravity
            call loadfl

            !write(7,*)'cwater=',cwater,'delgroup=',delgroup
            if(cwater/=0.and.delgroup/=0)call step_water_pressure

222         call force_external

            if(type_load=='LOAD2')mdiv=2

            do idiv=1,mdiv

                if(type_load=='LOAD2'.and.idiv==2) goto 71
                call load_of_creep_and_temperature
                call creep_strain_of_rock_fill    !20130510
                call wetting_strain_of_rock_fill  !20220409
71              if(mdiv/=1)toform=toforl+(tofor-toforl)*idiv/mdiv
                if(type_load=='DISCONTROL')preact0=prescrib(1)%rdofix
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv==1)tofor0=tofor !!ctt2005
                if((ngaps/=0.or.nrcsteel/=0).and.mdiv/=1)tofor0=toform !!ctt2005
                deltafi=0.0
                do igapb=1,ngapb !fzx  tcl
                    if(gapb(igapb)%nrdof==0)cycle
                    gapb(igapb)%rdisp_deltafi=0.
                enddo

                if(submodel==1.and.idiv==1)call value_submodel_boundary  !20210321
                do ielem=1,nelem   !!simo_rifai
                    if (associated(element(ielem)%alfa))element(ielem)%alfa=0.
                end do  !!simo_rifai

                do iiter=1,miter

                    iccontact=0
                    print *,'iblks=',iblks,'iincs=',iincs,'istep=',istep,'idiv=',idiv,'iiter=',iiter
                    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
                    if (istep==inc_step.and.iiter==1)then
                        call local_stress
                        call contact_state(0)
                        !call crack_state !crack 2006
                    endif
                    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1

                    call algort
                    if (iiter==1.or.(kstat==2.and.iiter.le.2))then
                        delitfi=0.0
                        call predict
                        do ielem=1,nelem   !!simo_rifai
                            if(associated(element(ielem)%alfa))element(ielem)%alfa=0.
                        end do  !!simo_rifai
                    endif

                    if(ikindks/=0) call strain_for_steel_bar !steel 2008

                    call stran0_creep4   !20180630  (博格斯模型蠕变初应变增量，因为应力增量在变化，所以每一迭代步求解，只适用于NSOLN=5）
                    if(iiter==1)   call effect_stres_modul_for_steel_beam !20211125
                    if(iiter==1)   call stiffness_for_bolt_spring  !20211125

                    call porepr_w
                    if (kswkw/=0) call propty_w
                    if (kresl/=0             )call stiff_u
                    if (ksmat/=0.and.uwcpl==1)call mcmatrx('W')
                    if (kmass/=0)             call mcmatrx('U')
                    if (khmat/=0.and.uwcpl/=1)call hmatrx('W')
                    if (kqmat/=0.and.uwcpl/=0)call upwcouple
                    if (stabpw==1.and.khmat/=0)call stabpatch    !!stablize


                    if (kresl/=0.or.ksmat/=0.or.khmat/=0.or.kqmat/=0) then
                        if (type_solver/='JPCG')global_stiff1=0.0
                        if (nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                        if (type_solver=='JPCG')then
                            do ielem=1,nelem
                                element(ielem)%estif=0.0
                            end do
                        endif
                        call estif_assemble
                        if (uwcpl==1)  call couple_assemble
                        if (stabpw==1) call stabpw_assemble           !! stablize
                    endif

                    if(nbspring>0) &       !20150925
                        call assemble_back_spring  !20150925
                    if(ground_inf/=0) call semi_inf_space_assemble

                    if(nonsym==0)then !20240312 YL
                        do itotv=1,ntotv   !20220618
                            if (totveq(itotv)/=0)then
                                if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-15)  &
                                    global_stiff1(iseq(totveq(itotv)))=1.e30
                            endif
                        enddo      !20220618
                    endif !20240312 YL


                    if(type_load=='LOAD2'.or.(kstat==2.and.iiter.le.2).or.(type_load/='LOAD2'.and.kstat/=2.and.iiter==1).or.  &
                        (ngaps/=0.and.istatec==0)) then	  !! for temperature 20130510
                        call gpvar2_initial
                        if (ninit/=0.and.(kinit==2.and.iincs==1.and.istep==1)) then  !20201203
                            call eload_initialize
                            call eload_initial_stress
                            call force_release
                            where(totveq==0)
                                torel=0.0
                            endwhere
                        endif

                        call eload_initialize
                        call residu_f
                        call eload_field
                        if (uwcpl/=0) call eload_couple
                        if(nbspring>0) &
                            call eload_back_spring
                        if(ground_inf/=0)call semi_inf_load

                        if (stabpw==1)call stabload
                        call force_internal

                    endif    !! end for if(type_load=='LOAD2'...
                    if (mdiv/=1) then
                        if (idiv==1.and.iiter==1.and.allocated(torel))toform=toform+torel
                    else
                        if (iiter==1.and.allocated(torel))tofor=tofor+torel
                    endif

                    if(ngaps/=0.and.iblks>=iblks_bt.and.mdiv==1)call ctfor_to_tofor(tofor0,tofor)
                    if(ngaps/=0.and.iblks>=iblks_bt.and.mdiv/=1)call ctfor_to_tofor(tofor0,toform)

                    if(nrcsteel/=0.and.mdiv==1)call csfor_to_tofor(tofor0,tofor)
                    if(nrcsteel/=0.and.mdiv/=1)call csfor_to_tofor(tofor0,toform)

                    if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)  goto 2  !ctt2005 , change position!
                    if(type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR
                    if ((type_solver=='PROFILE'.or.type_solver=='PARDISO').and.kresl/=0)then
                        operation='FACTORIZE'
                        call solve

                        !20230216 形成反演边界温度需要的C矩阵
                        if(nbackdT==2.and.istep==1.and.iiter==1) then
                            if(allocated(cmatrix_dtv))deallocate(cmatrix_dtv)
                            if(allocated(inv_cmatrix_dtv2))deallocate(inv_cmatrix_dtv2)
                            allocate(cmatrix_dtv(Npoints_pbx,nfixsets),inv_cmatrix_dtv2(nfixsets,nfixsets))
                            call cmatrix_dtv_formation(cmatrix_dtv,inv_cmatrix_dtv2)
                        endif
                        !20230216



                    end if
2                   continue

                    logx=ngaps/=0.and.(iiter==1.and.istep==inc_step).and.iincs==(lincs+1) !20200331
                    if (logx)then !ctt2005
                        if (restart_ctt==0)then !restart_ctt
                            kdimn=ndimn
                            if(block_stab==1)kdimn=3*(ndimn-1) !2015/11/17
                            allocate(rot(kdimn,kdimn))
                            rot=0.
                            do igapb=1,ngapb
                                if(block_appear_process(igapb,iblks)==0)cycle    !20200331
                                npgblock=gapb(igapb)%npgblock
                                gapb(igapb)%cmatrix=0.

                                if(gapb(igapb)%eblock==0) cycle  !2017/11/19
                                do ipoin=1,npgblock
                                    igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                    ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                    ij=gapb(igapb)%nodegblock_onetwo(ipoin)


                                    coef=1.
                                    if(ij==2)coef=-1.
                                    rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                                    if(kdimn>ndimn)then
                                        if(ndimn==2)rot(3,3)=1.
                                        if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                    endif

                                    allocate(unitl(kdimn),unitg(kdimn))
                                    do idimn=1,kdimn

                                        itotvbt=(ipoin-1)*kdimn+idimn
                                        unitl=0.
                                        unitl(idimn)=1.*coef


                                        unitg=transpose(rot).x.unitl
                                        rvector=0.
                                        call  unit_force_trans(igapb,kdimn,ij,unitg,igaps,ipair,rvector)

                                        operation='SOLVE'
                                        call solve


                                        do kpoin=1,npgblock
                                            jgaps=gapb(igapb)%nodegblock_igaps(kpoin)
                                            jpair=gapb(igapb)%nodegblock_ipairs(kpoin)
                                            ij0=gapb(igapb)%nodegblock_onetwo(kpoin)         !2017/04/03
                                            call result_node_to_center(kdimn,ij0,jgaps,jpair,result,unitg)

                                            do jdimn=1,kdimn
                                                jtotvbt=(kpoin-1)*kdimn+jdimn
                                                gapb(igapb)%cmatrix(jtotvbt,itotvbt)=unitg(jdimn)
                                            end do
                                        end do  !kpoin
                                    end do  !idimn
                                    deallocate(unitl,unitg)
                                end do  !ipoin

                                do ipoin=1,npgblock
                                    igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                    ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                    ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                                    coef=1.
                                    if(ij==2)coef=-1.
                                    rot=0.
                                    rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)

                                    if(kdimn>ndimn)then
                                        if(ndimn==2)rot(3,3)=1.
                                        !if(ndimn==3)rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                                        if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                        !if(ndimn==3)rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                                    endif

                                    rot=coef*rot

                                    allocate(cmatrixl(kdimn,kdimn))
                                    do jpoin=1,npgblock
                                        jtotv=(jpoin-1)*kdimn
                                        itotv=(ipoin-1)*kdimn
                                        cmatrixl=gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)
                                        gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)=   &
                                            rot.x.cmatrixl
                                    end do
                                    deallocate(cmatrixl)
                                end do
                            end do  !igapb
                            call forAdirect !fzx !形成A矩阵

                            do igapb=1,ngapb
                                !write(7,*)'igapb=',igapb,'ntotv_bt=',gapb(igapb)%ntotv_bt,'camatrix='
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    !write(7,*)gapb(igapb)%cmatrix(itotvbt,:)
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo  !igapb

                            deallocate(rot)

                        elseif(restart_ctt==1)then !restart_ctt
                            call forAdirect !fzx !形成A矩阵
                            rewind(recttunit)
                            do igapb=1,ngapb
                                npgblock=gapb(igapb)%npgblock
                                do itotvbt=1,gapb(igapb)%ntotv_bt
                                    do jtotvbt=1,gapb(igapb)%ntotv_bt
                                        read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                    enddo
                                enddo
                            enddo
                        else !restart_ctt
                            write(*,*)'no such restart_ctt!!'
                            stop
                        endif !restart_ctt
                    endif  !!ctt2005

                    if(kresl/=0) & !20220311
                        call cmatrix_c_formation !20220311


                    rvector=0.0
                    if (type_solver/='JPCG') then
                        do itotv=1,ntotv
                            if (totveq(itotv)/=0)then
                                if (mdiv/=1) then
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        toform(itotv)-stfor(itotv)
                                else
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        tofor(itotv)-stfor(itotv)
                                endif
                                if(nonsym==0)then !20240312 YL
                                    if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-15) &  !20220618
                                        global_stiff1(iseq(totveq(itotv)))=1.e20
                                endif !20240312 YL
                            endif
                        end do
                        if (nflow/=0)then
                            call flow_charge
                            do ii=1,nfreeflownode
                                ipoin=listfreeflownode(ii)
                                itotv=nodfn(lmdofn(8),ipoin)
                                if (totveq(itotv)/=0.and.(result_zero(itotv)>.1  &
                                    .or.(result_zero(itotv)>0..and.flowrate(ipoin)>0.))) then
                                    global_stiff1(iseq(totveq(itotv)))=1.e20
                                    rvector(totveq(itotv))=0.
                                    result_zero(itotv)=0.
                                endif
                            end do
                        endif
                        !!int2000
                        do itotv=1,ntotv
                            nintf=trans(itotv)%nintf
                            if (nintf/=0) then
                                iieq=totveq(itotv)
                                if (iieq/=0)rvector(iieq)=0.
                                do iintf=1,nintf
                                    iieq=totveq(trans(itotv)%listf(iintf))
                                    if (iieq/=0) &
                                        rvector(iieq)=rvector(iieq)+  &
                                        (tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                                end do
                            endif
                        end do
                        !!int2000
                    else
                        if (mdiv/=1)rvector=toform-stfor
                        if (mdiv==1)rvector=tofor -stfor
                    endif

                    if (type_load=='ARCLENGTH'.and.kresl/=0) then
                        allocate(rvectorm(neq))
                        rvectorm=rvector
                        rvector=0.0
                        if (type_solver/='JPCG') then
                            do itotv=1,ntotv
                                if(totveq(itotv)/=0) &
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+tofor_arclength(itotv)
                            end do
                        else
                            rvector=tofor_arclength
                        endif
                        operation='SOLVE'
                        call solve
                        delta_arclength=result
                        rvector=rvectorm
                        deallocate(rvectorm)
                    endif

                    !write(7,*)'idiv=',idiv,'iiter=',iiter
                    !write(7,*)'rvector=',rvector

                    if (type_nl==8)then
                        if(kstat/=2)call bfgsr(iiter)
                        if(kstat==2)call bfgsr(iiter-1)
                    else
                        operation='SOLVE'
                        call solve
                    endif

                    !write(7,*)'result=',result

                    if(ngaps/=0.and.iblks>=abs(iblks_bt))call solve_ctt  !!ctt2005
                    if(nrcsteel/=0) call solve_bond_force_of_cs !20210328


                    if (type_load=='ARCLENGTH')then
                        call find_dfact_of_arclength (irst)
                        if (irst==1) then
                            time_begin=tcurves(arc_curve)%time_begin
                            detal=tcurves(arc_curve)%detal
                            if (abs(ttime-time_begin-ditime).le.1.e-8)detal=tcurves(arc_curve)%fact_inc
                            tcurves(arc_curve)%detal=detal*.5
                            if (abs(ttime-time_begin-ditime).le.1.e-8)tcurves(arc_curve)%fact_inc=detal*.5
                            goto 222
                        endif
                    endif

                    if(neuman==1.and.(istep/=1.or.iiter/=1).and.kresl/=0)call neuman_expan

                    call TIME(char_time)
                    print *, 'time: ', char_time
                    write(chkunit,*)'time: ', char_time



                    call varupdate

                    !20230216 反演边界温度
                    if(nbackdT==2.and.iiter==1) then
                        allocate(observstar(Npoints_pbx),dtv(nfixsets),dtvi(nfixsets))
                        observstar=0.

                        do i=1,mvalue
                            print *,i,'Value_observ(i)%istep=',Value_observ(i)%istep
                            if(Value_observ(i)%iblks/=iblks)cycle
                            if(Value_observ(i)%iincs/=iincs)cycle
                            if(Value_observ(i)%istep/=istep)cycle
                            ivalue_point=Value_observ(i)%ivalue_point
                            observstar(ivalue_point)=Value_observ(i)%value_measure
                            nintf=para_points(ivalue_point)%nintf
                            listf=>para_points(ivalue_point)%listf
                            rintf=>para_points(ivalue_point)%rintf
                            Tpredict=dot_product(result_zero(listf),rintf)
                            observstar(ivalue_point)=observstar(ivalue_point)-Tpredict
                            nullify(listf,rintf)
                        end do
                        print *,'observstar=',observstar,'Tpre=',Tpredict
                        dTv=transpose(cmatrix_dtv).x.observstar
                        dtvi=inv_cmatrix_dtv2.x.dtv


                        do i=1,ndofix    !20231130
                            mfixset=prescrib(i)%mfixset
                            do j=1,mfixset !20231130
                                ifixset=prescrib(i)%mlist(j)
                                idofn=prescrib(i)%ldofix
                                result_zero(idofn)= result_zero(idofn)+dtvi(ifixset)*prescrib(i)%rintf(j)
                            end do !20231130
                        end do !20231130

                        !   do i=1,ndofix
                        !ifixset=prescrib(i)%ifixset
                        !idofn=prescrib(i)%ldofix
                        !result_zero(idofn)= result_zero(idofn)+dtvi(ifixset)
                        !  end do

                        deallocate(observstar,dtv,dtvi)

                    endif
                    !20230216



                    call relative_dis_watertight !20231007 止水 !20240305
                    call eload_initialize
                    if(ikindks/=0) call strain_for_steel_bar !steel 2008
                    call residu_f

                    if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then
                        call eload_field
                        if (uwcpl/=0) call eload_couple
                        if (stabpw==1)call stabload

                        call reaction_prescribed
                        call conver_load

                        if (nchek==0)call conver_nodal_value

                        if (nchek==0)exit
                    endif   !if(type_load/='LOAD2'...
                    if(type_load=='LOAD2'.and.idiv==1)goto 10
                end do   !! loop for iiter
10              continue

                if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then   !20220607
                    call local_stress
                    call contact_state(1)
                    call crack_state !crack 2006
                    if(istatec==0) &
                        call state_and_stiff_2021
                    do igaps=1,ngaps
                        npairs=gaps(igaps)%npairs
                        do ipairs=1,npairs
                            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                            gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
                            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
                            gaps(igaps)%state0(ipairs)=gaps(igaps)%state(ipairs)
                            gaps(igaps)%damage0(ipairs)=gaps(igaps)%damage(ipairs)
                            gaps(igaps)%kxyz0(:,:,ipairs)=gaps(igaps)%kxyz(:,:,ipairs)
                        end do
                    end do
                    if (nflow/=0)call flow_charge
                    call gpvarupdate
                endif   !20220607

            end do    !! for idiv

            if(modf_dis_blocks(iblks)==1)call construction_dis_modify

100         toforl=tofor
            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
                call outputres !for output
            endif

            if(outinp<0)then  !稳定渗流场分析时向oip文件输出结点压力 20220623
                !write(outinpunit,'(a)')'ipoin    pore_pressure'
                !idofn=lmdofn(8)
                !do ipoin=1,npoin
                !    itotv=nodfn(idofn,ipoin)
                !    if(itotv==0)then
                !        write(outinpunit,'(i8,e16.6)')ipoin,0.0
                !    else
                !        pvalue=result_zero(itotv)
                !        if(pvalue<0)pvalue=0.0
                !        write(outinpunit,'(i8,e16.6)')ipoin,pvalue
                !    endif
                !end do
                !!!!
                allocate(midt(npoin))  !20220626
                icdofn=lmdofn(8)
                midt=0.
                do ipoin=1,npoin
                    itotv=nodfn(icdofn,ipoin)
                    if (itotv/=0) then
                        midt(ipoin)=result_zero(itotv)
                    endif
                end do
                write(outinpunit)midt
                deallocate(midt)
            endif


            if(nforce/=0.or.ngaps/=0)call force_interface
            if(kstab/=0.)call safety_factor


            if (istep/noutf*noutf==istep)then
                if(nforce/=0.or.ngaps/=0)call write_force_interface
                call out_full_write
                if (outplot(1:3)=='GID')   call OUT_GID_WRITE
                if (outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif

            if (istep/nresta*nresta==istep)call resta_read_write(-1)


            if(Bparameter>0)then !20230523
                !Value_observ(:)%value_computation=0.
                do ivalue=1,mvalue
                    !if(Value_observ(ivalue)%ic==0)cycle
                    iblks_i=Value_observ(ivalue)%iblks
                    iincs_i=Value_observ(ivalue)%iincs
                    istep_i=Value_observ(ivalue)%istep
                    idofn =lmdofn(Value_observ(ivalue)%idofn)
                    ivalue_point=Value_observ(ivalue)%ivalue_point
                    if(iblks_i==iblks.and.iincs_i==iincs.and.istep_i==istep)then
                        nintf=para_points(ivalue_point)%nintf
                        listf=>para_points(ivalue_point)%listf
                        rintf=>para_points(ivalue_point)%rintf
                        if(Bparameter==1)Value_observ(ivalue)%value_computation=dot_product(rintf,result_zero(nodfn(idofn,listf)))
                        if(Bparameter==2)Value_observ(ivalue)%value_computation=dot_product(rintf,deltafi(listf))
                        nullify(listf,rintf)
                    endif
                end do
            endif   !20230523

            if(Bparameter<0)then !20200812
                tbstep=tbstep+1
                do i=1,nback_point

                    bblks=freedom_for_back(4,i)  !20230523
                    if(bblks>iblks)cycle !20230523
                    inode=freedom_for_back(1,i)
                    idofn=freedom_for_back(2,i)
                    jnode=freedom_for_back(3,i)
                    print *,'inode=',inode,'idofn=',idofn,'jnode=',jnode
                    itotv=nodfn(lmdofn(idofn),inode)
                    if(jnode/=0)jtotv=nodfn(lmdofn(idofn),jnode)
                    if(Bparameter==-1)then
                        Value_vc(i,tbstep,istoch)=result_zero(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-result_zero(jtotv)
                    elseif(Bparameter==-2)then
                        Value_vc(i,tbstep,istoch)=deltafi(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-deltafi(jtotv)
                    end if
                end do
            endif  !20200812
            if((bparameter>=1.and.bparameter<=2).and.balgor>=1) call dudx

            if(upliftin<0)then  !考虑渗流场影响分析时向upf文件输出结点压力 20220623
                allocate(midt(npoin))  !20220626
                icdofn=lmdofn(8)
                midt=0.
                do ipoin=1,npoin
                    itotv=nodfn(icdofn,ipoin)
                    if (itotv/=0) then
                        midt(ipoin)=result_zero(itotv)
                    endif
                end do
                write(upliftunit)midt
                deallocate(midt)

            endif   !20230708


        end do     !! loop for istep

        if(Qstatic/=0) then !20221104
            deallocate(qstatic_force%appearg,qstatic_force%qfactor,qstatic_force%cor_coef) !20221104
            deallocate(qstatic_force)  !20221104
        endif !20221104
        if(cwater/=0.and.delgroup>0)deallocate(coef_water)
    end do     !! loop for iincs


    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI

    END SUBROUTINE STATIC_U_PW

    SUBROUTINE STATIC_U_PWm

    character(80)text
    integer(ink) itotv,ielem
    real   (irk) time
    integer(ink) iintf,nintf,iieq,idofn,ipoin   !!int2000

    print *,'static_U_Pwm'
    read(mainunit,*)text
    read(mainunit,*)nincs

    mdiv=2
    time=0.0
    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do


    do iincs=lincs+1,nincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)

        do istep=1,nstep
            if (outintr>0.and.iblks>=outintr)trstep=trstep+1  !20200226
            time=time+ditime
            ttime=ttime+ditime        !! only for output

            call dfact_time_curve(ttime)

            call modf_var_prescribed
            call gravity
            call loadfl
            call force_external

            do idiv=1,mdiv

                deltafi=0.0
                delitfi=0.0

                if (mdiv/=1) &
                    toform=toforl+(tofor-toforl)*idiv/mdiv

                do iiter=1,miter

                    print *,'iincs=',iincs,'istep=',istep,'iiter=',iiter


                    call algort
                    if (iiter==1)then
                        deltafi=0.0
                        delitfi=0.0
                        call predict
                        do ielem=1,nelem   !!simo_rifai
                            if (associated(element(ielem)%alfa))element(ielem)%alfa=0.
                        end do  !!simo_rifai
                    endif
                    if (kresl/=0.and.uwcpl/=0)call stiff_u
                    if (ksmat/=0.and.uwcpl==1)call mcmatrx('W')
                    if (kmass/=0)             call mcmatrx('U')
                    if (khmat/=0.and.uwcpl/=1)call hmatrx('W')
                    if (kqmat/=0.and.uwcpl/=0)call upwcouple
                    if (stabpw==1.and.khmat/=0)call stabpatch    !!stablize



                    if (kresl/=0.or.ksmat/=0.or.khmat/=0.or.kqmat/=0) then
                        if (type_solver/='JPCG')global_stiff1=0.0
                        if (nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                        if (type_solver=='JPCG')then
                            do ielem=1,nelem
                                element(ielem)%estif=0.0
                            end do
                        endif
                        call estif_assemble
                        if (uwcpl==1)  call couple_assemble
                        if (stabpw==1) call stabpw_assemble           !! stablize
                    endif


                    if (idiv==1.and.iiter==1.and.istep==inc_step) then    !! iiter==1 and istep==inc_step
                        call eload_initialize
                        if ((ninit/=0.and.((iblks==1.and.kinit==1)).or.(kinit==2.and.iincs==1))) then

                            call eload_initial_stress
                            call gpvar2_initial
                            if (kinit==2.and.iincs==1)then
                                call force_release
                                where(totveq==0)
                                    torel=0.0
                                endwhere
                            endif

                        endif

                        if (uwcpl/=0.and.(iblks/=1.or.(iblks==1.and.iincs/=1)))call residu_f
                        call eload_field
                        if (uwcpl/=0) call eload_couple
                        if (stabpw==1)call stabload
                        call force_internal

                    endif    !! end for iiter==1 and istep==inc_step
                    if (mdiv/=1) then
                        if (idiv==1.and.iiter==1.and.allocated(torel))toform=toform+torel
                    else
                        if (iiter==1.and.allocated(torel))tofor=tofor+torel
                    endif

                    rvector=0.0
                    if (type_solver/='JPCG') then
                        do itotv=1,ntotv
                            if (totveq(itotv)/=0)then
                                if (mdiv/=1) then
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        toform(itotv)-stfor(itotv)
                                else
                                    rvector(totveq(itotv))=rvector(totveq(itotv))+ &
                                        tofor(itotv)-stfor(itotv)
                                endif
                            endif
                        end do

                        !!int2000
                        do itotv=1,ntotv
                            nintf=trans(itotv)%nintf
                            if (nintf/=0) then
                                iieq=totveq(itotv)
                                if (iieq/=0)rvector(iieq)=0.
                                do iintf=1,nintf
                                    iieq=totveq(trans(itotv)%listf(iintf))
                                    if (iieq/=0) &
                                        rvector(iieq)=rvector(iieq)+  &
                                        (tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                                end do
                            endif
                        end do
                        !!int2000
                    else
                        if (mdiv/=1)rvector=toform-stfor
                        if (mdiv==1)rvector=tofor -stfor
                    endif

                    if (type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR
                    if (type_solver=='PROFILE'.and.               &
                        (kresl/=0.or.ksmat/=0.or.khmat/=0.or.kqmat/=0)) then
                        operation='FACTORIZE'
                        call solve
                    end if
2                   if(type_nl==8) then
                        if (kstat/=2)call bfgsr(iiter)
                        if (kstat==2)call bfgsr(iiter-1)
                    else
                        operation='SOLVE'
                        call solve
                    endif

                    if (idiv==1) then
                        do idofn=1,cdofn
                            do ipoin=1,npoin
                                itotv=nodfn(idofn,ipoin)
                                if (itotv/=0.and.iffix(itotv)==0)  then
                                    delitfi(itotv)=result(itotv)
                                    deltafi(itotv)=deltafi(itotv)+delitfi(itotv)
                                endif
                            enddo     !! for ipoin
                        end do     !! for idofn
                        call residu_f
                        goto 10
                    endif

                    call varupdate
                    call eload_initialize
                    if (uwcpl/=0)call residu_f
                    call eload_field
                    if (uwcpl/=0)call eload_couple
                    if (stabpw==1)call stabload

                    call reaction_prescribed
                    call conver_load

                    if (nchek==0)call conver_nodal_value
                    if (nchek==0)exit
                    call gpvarupdate
                end do   !! loop for iiter
10              continue
            end do    !! for idiv
100         toforl=tofor
            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
            endif

            if (istep/noutf*noutf==istep)then
                call out_full_write
                if (outplot(1:3)=='GID')   call OUT_GID_WRITE
                if (outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif

            if (istep/nresta*nresta==istep)call resta_read_write(-1)
        end do     !! loop for istep

    end do     !! loop for iincs


    !if(winit==-1) call out_next_write
    if(winit==-1*iblks) call out_next_write !20231215YULI

    END SUBROUTINE STATIC_U_PWm


    SUBROUTINE time_dependent

    character(80)text,type_curve
    integer(ink) itotv,ielem,itcurve,idofix,iextrf,nbounods,nnode,ibounod,ij,npairs,ipairs,ldofix,imcon,i0,ij0
    integer(ink) ilink,node1,node2,ipoin,idofn,kdimn,ivalue_point,bblks,nbasef,do_base_freq  !20230216
    real   (irk),allocatable::resultm(:),result0(:),tofor0(:)
    real   (irk),allocatable::disA(:),disB(:) !hxl2006 MIF
    real   (irk) time,coef,pvalue,Tpredict !20230216
    integer(ink) iintf,nintf,iieq,icdofn,ifixset   !!20230216
    integer(ink) igapb,npgblock,jpoin,igaps,ipair,jgaps,jpair,idimn,itotvbt,jdimn, &  !!ctt2005
        jtotv,kpoin,lpoin,jtotvbt,mfixset,j   !!20231130
    real   (irk),allocatable::rot(:,:)  !!ctt2005
    real   (irk),allocatable::unitl(:),unitg(:),cmatrixl(:,:),bounfreez(:),gaptofor(:),force_rigid(:)!!ctt2005
    integer(irk),allocatable::list_bound(:)
    real   (irk) s
    integer(ink) ilaymif
    integer(ink) i,iincs_i,iblks_i,istep_i,inode,jnode,ivalue  !20200819
    integer(ink),pointer::listf(:)  !20200819
    real   (irk),pointer::rintf(:)  !20200819
    real   (irk),allocatable::observstar(:),dtv(:),dtvi(:) !20230216

    integer(ink) cdtest,ntram,icrev,ICEND,Iseg,itram,icstop,nc1,nc2,nstre  !cdtest,2013/12/11
    real   (irk) p,q,eta,cvv,xl0,distf,dist,dist1,dist2,dist0,damage
    real   (irk),allocatable::xl1(:),xl2(:),midt(:) !20220626
    integer(ink),allocatable::ncyc(:),ic(:)

    real   (irk),allocatable::cmatrix_dtv(:,:),inv_cmatrix_dtv2(:,:)  !20230216

    integer(ink),pointer::ldofixb(:)  !hxl2006 MIF
    integer(ink),pointer::lnods(:)

    !if(outintw/=0)allocate(resultm(npoin),result0(ntotv))
    allocate(resultm(npoin),result0(ntotv))  !20200821
    if(allocated(earthquake_curve))deallocate(earthquake_curve)
    if(allocated(earthquake_curve_d))deallocate(earthquake_curve_d)
    if(allocated(earthquake_curve_v))deallocate(earthquake_curve_v)
    if(allocated(earthquake_curve_MIF))deallocate(earthquake_curve_MIF)
    if(allocated(fachv))deallocate(fachv)

    if (meshc==1.or.rmesh/=0)rewind(mainunit)
    if(Bparameter/=0.and.iblks==1)rewind(mainunit)  !20230902
    if(Bparameter/=0.and.iblks==1)rewind(upliftunit) !20230902


10  format(10i8)
    if(iblks==1)call cvoid(0)
    if(iblks==1.and.restart==0) then  !20220721
        if(any(group(:)%fieldid=='UW'))call cvoid(0)
        call inivdval
    endif

    allocate(earthquake_curve(ndimn),fachv(ndimn),earthquake_curve_d(ndimn),earthquake_curve_v(ndimn))!hxl2006 , VIE
    allocate(earthquake_curve_MIF(ndimn))
    earthquake_curve=0 ; earthquake_curve_MIF=0 ; earthquake_curve_d=0 ; earthquake_curve_v=0
    read(mainunit,*)text
    read(mainunit,*)nincs,cdtest,earthquake_curve(1:ndimn)
    read(mainunit,*)nstepjq,nstepjp !20231215YL

    if(type_ABC=='VIE')read(mainunit,*)hwdirec,hcoord  !20220105
    if(type_ABC=='VIE')read(mainunit,*)inpcord,earthquake_curve_d(1:ndimn),earthquake_curve_v(1:ndimn)
    if(type_ABC=='MIF')read(mainunit,*)inpcord,earthquake_curve_MIF(1:ndimn)

    mdiv=1
    if(cdtest>=1)then  !2013/12/11
        read(mainunit,*)text
        read(mainunit,*)ntram
        allocate(xl1(ntram),xl2(ntram),ncyc(ntram),ic(ntram))
        ic=0
        do itram=1,ntram
            read(mainunit,*)xl1(itram),xl2(itram)  !,ncyc(itram)
        end do
    endif

    !hxl2006 VIE
    allocate(freez(npoin))
    freez=0.0 ; nbounods=0
    if(type_ABC=='VIE')read(punit,*)nbounods
    write(7,*)'nbounods=',nbounods
    if (nbounods/=0) then
        allocate(list_bound(nbounods),bounfreez(nbounods))
        read(punit,*)list_bound(1:nbounods)
        read(punit,*)bounfreez(1:nbounods)

        do ibounod=1,nbounods
            ipoin=list_bound(ibounod)
            freez(ipoin)=bounfreez(ibounod)
        end do

        do ielem=1,nabssgroup
            lnods=>tabss(ielem)%lnods
            nnode=size(lnods)
            allocate(tabss(ielem)%cordzfree(nnode))
            do inode=1,nnode
                ipoin=lnods(inode)
                tabss(ielem)%cordzfree(inode)=freez(ipoin)
            end do
        end do
    end if
    deallocate(freez)
    !hxl2006 VIE


    !20231215YL
    if(nstepjq/=0)then  !20231008  file to sore the element average shear stress for judgement of liquifaction
        lquunit=72
        open(lquunit,file=probn(1:len1)//'.lqu',FORM='UNFORMATTED')
        nliqu=0
        disunit=73
        open(disunit,file=probn(1:len1)//'d.dis')
    endif  !
    if(nstepjp/=0)then
        pmtunit=74
        open(pmtunit,file=probn(1:len1)//'.pmt')
    endif
    omgunit=178 !20231008
    open(omgunit,file=probn(1:len1)//'.omg')
    !20231215YL

    if(cdtest>=1)then  !2013/12/11
        ICEND=0
        ICREV=0
        ISEG=0
        ITRAM=1
        ICSTOP=0
        fincre=1.
    endif



    if(ngaps/=0.or.nrcsteel/=0.or.nwcpipe/=0)allocate(tofor0(ntotv)) !!ctt2005

    time=0.0

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,nmcon,nbasef  !20231215YL
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    do iincs=lincs+1,nincs
        print *,'  time depend     iincs=',  iincs,'nincs=',nincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,nmcon,nbasef !20231215YL
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        if(nmcon/=0)allocate(lmcon(nmcon),rmcon(ndimn,nmcon))
        if (nmcon/=0) then
            read(mainunit,*)coef
            do imcon=1,nmcon
                read(mainunit,*)i0,lmcon(imcon),rmcon(:,imcon)
            end do
            rmcon=abs(rmcon)*coef
        endif


        !hxl2006 MIF

        !allocate(dissanru(nstep,ntotv),dissanzi(nstep,ntotv))   !sanshe  hxl
        allocate(disA(ntotv),disB(ntotv),disA_1(ntotv),disB_1(ntotv),disA_2(ntotv),disB_2(ntotv)) !hxl2006 MIF
        disA=0. ; disB=0. ; disA_1=0. ; disB_1=0. ; disA_2=0. ; disB_2=0.

        !dissanru=0.0
        !dissanzi=0.0                      !sanshe     hxl
        if (ntrans>0)then
            s=camif*ditime/dxmif
            k1(1)=(s-3)*s/2+1
            k1(2)=(2-s)*s
            k1(3)=(s-1)*s/2
            k2(1)=(2*s-3)*s+1
            k2(2)=4*(1-s)*s
            k2(3)=(2*s-1)*s
            k3(1)=4.5*(s-3.0)*s+1.
            k3(2)=3.0*(2.0-3.0*s)*s
            k3(3)=1.5*(3.0*s-1.0)*s
        endif
        !end hxl2006 MIF



        do istep=1,nstep

            print *, 'time: ', char_time
            !write(7,*)'gaps(1)%ctforce(:,1)=',gaps(1)%ctforce(:,1)
            disA_2=disA_1  !zhao
            disB_2=disB_1
            disA_1=disA
            disB_1=disB
            print *, 'iblks=',iblks,'iincs=',iincs,'istep=',istep
            if(outintr>0.and.iblks>=outintr)trstep=trstep+1  !20200226
            time=time+ditime
            ttime=ttime+ditime        !! only for output

            call dfact_time_curve(ttime)

            !!20231215YL
            do_base_freq=0  !20231008
            if(nbasef>0)then  !903
                if(istep==1.or.(istep/nbasef*nbasef==istep))then
                    if(gamamax==0)then !yuanli20230926
                        do_base_freq=1 !903
                        call base_frequency_analysis  !903
                    elseif(gamamax/=0.and.istep==1)then
                        do_base_freq=1 !903
                        call base_frequency_analysis  !903
                    endif
                endif
            elseif(nbasef<0)then  !903
                if(istep==1.or.(istep/abs(nbasef)*abs(nbasef)==istep))then
                    do_base_freq=1 !903
                    read(omgunit,*)text,base_freq
                    write(chkunit,*)'base_freq=',base_freq
                endif
            endif  !903
            !!20231215YL

            where(earthquake_curve==0)
                fachv=0.0
            elsewhere
                fachv=tcurves(earthquake_curve)%dfact
            endwhere
            write(7,*)'fachv=',fachv
            !levelset
            !***********************************************************************
            if (level_set_problem==2)then
                call levelsetmain
                ditime=delt
            endif
            !***********************************************************************
            if(outintr==0)then !20200220
                if(iincs==1.and.istep==inc_step)then
                    call placement_temperature(result0)  !20200220
                else
                    result0=result_zero
                endif
            endif
            allocate(inpru(ntotv),inpzi(ntotv))     !sanshe  hxl !hxl2006 MIF
            inpru=0.0 ; inpzi=0.0
            if(type_abc=='MIF')call modf_inpwav     !hxl2006 MIF
            !modf_inpwav：得到入射波场inpru及自由场inpzi

            deltafi=0.0
            call modf_var_prescribed
            if(submodel==1)call value_submodel_boundary  !20210321
            !modf_var_prescribed：在这个子程序里实现插值，由前几步人工边界区点的位移值得到当前步人工边界点的值，
            !以作为约束值，存在fixed中，或者说更新fixed
            !write(7,*)'result_zero(1:10)1=',result_zero(1:10)

            call heat_internal1

            do ielem=1,nelem   !!simo_rifai
                if(associated(element(ielem)%alfa))element(ielem)%alfa=0.
            end do  !!simo_rifai
            iccontact=0 !zhao 05/07/22

            do iiter=1,miter
                print *,'iiter=',iiter

                call algort
                if (istep==1.and.iiter==1)then
                    call local_stress
                    call contact_state(0)
                endif

                call porepr
                if(iiter==1)   call effect_stres_modul_for_steel_beam !20211125
                if(iiter==1)   call stiffness_for_bolt_spring  !20211125
                write(7,*) 'kswkw=',kswkw,'kresl=',kresl,'kmass=',kmass
                if(kswkw/=0) call propty
                if(kresl/=0) call stiff_u

                call dateandtime(curtime)   !20200220
                write(chkunit,2000)'Begin forming various matrix       at ',curtime  !20200220
                write(*,2000)      'Begin forming various matrix       at ',curtime   !20200220



                if(kmass/=0) call mcmatrx('U')
                if(ksmat/=0) call mcmatrx('W')
                if(allocated(fmass))call fmass_assemble

                if(khmat/=0) call hmatrx('W')
                if(kthmat/=0)call htmatrx

                print *,'ktsmat=',ktsmat
                if(ktsmat/=0)call stmatrx

                if(kthmat/=0)call assemble_boundt_estif
                if(kthmat/=0.and.algo_pipe==3)call assemble_pipe_estif
                if(kqmat/=0) call upwcouple
                if(stabpw==1.and.khmat/=0) call stabpatch   !!stablize

                if(kgrav/=0)call gravity
                if(kldfl/=0)call loadfl
                if (kresl/=0.or.ksmat/=0.or.khmat/=0.or.kqmat/=0.or.kmass/=0  &
                    .or.kthmat/=0.or.ktsmat/=0)then

                    call dateandtime(curtime)  !20200220
                    write(chkunit,2000)'Begin assemble golbal matrix       at ',curtime !20200220
                    write(*,2000)      'Begin assemble golbal matrix       at ',curtime !20200220


                    if(type_solver/='JPCG')global_stiff1=0.0
                    if(nonsym/=0.and.type_solver=='PROFILE')global_stiff2=0.0
                    if (type_solver=='JPCG')then
                        do ielem=1,nelem
                            element(ielem)%estif=0.0
                        end do
                    endif
                    call estif_assemble
                    call COUPLE_ASSEMBLE
                    if(nmcon/=0) call concentrated_mass_matrix !2013/4/11
                    if(stabpw==1) call stabpw_assemble           !! stablize
                    if(nifsgroup/=0 .and.(type_solver=='PROFILE'.or.type_solver=='PARDISO') )call assemble_interface_fluid_solid          !!ifs2000
                    if(nifsgroup/=0 .and.type_solver=='SSORPBCG')call assemble_interface_fluid_solid_SSORPBCG !!ifs2000
                    if(nabsfgroup/=0.and.(type_solver=='PROFILE'.or.type_solver=='PARDISO'))call assemble_absorb_fluid                   !!ifs2000
                    if(nabssgroup/=0.and.(type_solver=='PROFILE'.or.type_solver=='PARDISO'))call assemble_absorb_solid                   !!ifs2000
                    if(nabssgroup/=0.and.type_solver=='SSORPBCG')call assemble_absorb_solid_SSORPBCG          !!ifs2000
                    if((Icaddmass>=2.or.ifsnedge/=0).and.(type_solver=='PROFILE'.or.type_solver=='PARDISO') )call assemble_stiff_ifs2006   !!20220330 Li
                    if(ifsnedge/=0  .and.type_solver=='SSORPBCG')call assemble_stiff_ifs2006_SSORPBCG         !!ifs2006 zhao, 06/03/29

                    !do itotv=1,ntotv   !20221014
                    !   if (totveq(itotv)/=0)then
                    ! if(abs(global_stiff1(iseq(totveq(itotv)))).le.1.e-10.and.ifsnedge==0.and.nifsgroup==0.AND.TYPE_PROBLEM/='S')global_stiff1(iseq(totveq(itotv)))=1.e30
                    !   endif
                    !enddo  !20221014

                endif

                ! write(7,*)'global_stiff1***'
                !  do itotv=1,ntotv
                !if(totveq(itotv)/=0)   &
                ! write(7,*)itotv,totveq(itotv),global_stiff1(iseq(totveq(itotv)))
                !  end do


                if(iiter==1.or.kgrav/=0.or.kldfl/=0) call force_external
                !   write(chkunit,*)'itotv,tofor'
                !do itotv=1,ntotv
                !	if(abs(totveq(itotv)).ne.0) then
                !		write(chkunit,*)itotv,tofor(itotv)
                !	endif
                !end do


                if (iiter==1) then     ! iiter==1

                    call heat_flow_charge(0)          !!!20200316 pipe
                    call eload_initialize
                    call predict
                    call residu_f

                    !write(7,*)'eload1=',element(1)%field(1)%eload
                    !write(7,*)'eload2=',element(2)%field(1)%eload

                    call eload_couple
                    call eload_field  !20210417
                    if(algo_pipe>3) call pipe_cool_eload
                    call eload_interface_fluid_solid  !!ifs2000
                    call eload_absorb_fluid           !!ifs2000
                    call eload_absorb_solid           !!ifs2000
                    call eload_ifs2006                !!ifs2006 zhao, 06/03/29
                    if(stabpw==1)call stabload
                    call force_internal
                endif ! iiter=1    !should change for nssoil

                if(ngaps/=0.and.iblks>=iblks_bt.and.iiter==1)call ctfor_to_tofor(tofor0,tofor)  !!ctt2005

                if(type_nl==8.and.(iiter>1.or.(kstat==2.and.iiter>2))) goto 2  !MNR
                if ((type_solver=='PROFILE'.or.type_solver=='PARDISO').and.                     &
                    (kresl/=0.or.ksmat/=0.or.khmat/=0.or.kqmat/=0.or.kmass/=0  &
                    .or.kthmat/=0.or.ktsmat/=0)) then
                    call dateandtime(curtime)  !20200220
                    write(chkunit,2000)'Begin factorize global matrix      at ',curtime !20200220
                    write(*,2000)      'Begin factorize global matrix      at ',curtime	!20200220

                    operation='FACTORIZE'
                    call solve
                    !20230216 形成反演边界温度需要的C矩阵
                    if(nbackdT==2.and.istep==1) then
                        if(allocated(cmatrix_dtv))deallocate(cmatrix_dtv)
                        if(allocated(inv_cmatrix_dtv2))deallocate(inv_cmatrix_dtv2)
                        allocate(cmatrix_dtv(Npoints_pbx,nfixsets),inv_cmatrix_dtv2(nfixsets,nfixsets))
                        call cmatrix_dtv_formation(cmatrix_dtv,inv_cmatrix_dtv2)
                        !print *,'nfixsets=',nfixsets
                        !print *,'cmatrix_dtv=',cmatrix_dtv(:,1)
                        !print *,'inv_cmatrix_dtv2=',inv_cmatrix_dtv2

                    endif
                    !20230216
                end if
2               continue
                if (ngaps/=0.and.(iiter==1.and.istep==inc_step).and.iblks==iblks_bt)then   !!ctt2005
                    if (restart_ctt==0)then !restart_ctt
                        call forAdirect !fzx !形成A矩阵
                        kdimn=ndimn
                        if(block_stab==1)kdimn=3*(ndimn-1) !2015/11/17
                        allocate(rot(kdimn,kdimn))


                        do igapb=1,ngapb

                            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
                            if(gapb(igapb)%eblock==0) cycle  !2017/11/19
                            npgblock=gapb(igapb)%npgblock

                            allocate(unitl(kdimn),unitg(kdimn))
                            do ipoin=1,npgblock
                                igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                                coef=1.
                                if(ij==2)coef=-1.
                                rot=0.
                                rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                                if(kdimn>ndimn)then
                                    if(ndimn==2)rot(3,3)=1.
                                    if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                endif
                                do idimn=1,kdimn
                                    itotvbt=(ipoin-1)*kdimn+idimn
                                    unitl=0.
                                    unitl(idimn)=1.*coef
                                    unitg=transpose(rot).x.unitl
                                    rvector=0.

                                    call  unit_force_trans(igapb,kdimn,ij,unitg,igaps,ipair,rvector)
                                    !
                                    operation='SOLVE'
                                    call solve

                                    do kpoin=1,npgblock
                                        jgaps=gapb(igapb)%nodegblock_igaps(kpoin)   !因为上面有idimn循环，这里不能用igaps变量
                                        jpair=gapb(igapb)%nodegblock_ipairs(kpoin)
                                        ij0=gapb(igapb)%nodegblock_onetwo(kpoin)    !因为上面有idimn循环，这里不能用ij变量      !！2017/04/03
                                        call result_node_to_center(kdimn,ij0,jgaps,jpair,result,unitg)

                                        do jdimn=1,kdimn
                                            jtotvbt=(kpoin-1)*kdimn+jdimn
                                            gapb(igapb)%cmatrix(jtotvbt,itotvbt)=unitg(jdimn)
                                        end do
                                    end do  !kpoin


                                    if(gapb(igapb)%nrdof>0)call dfat_rigid_ctfor(igapb,itotvbt,result)   !dfat due to ctfor

                                end do    ! idimn
                            end do    ! ipoin

                            do ipoin=1,npgblock
                                igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                                coef=1.
                                if(ij==2)coef=-1.
                                rot=0.
                                rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                                if(kdimn>ndimn)then
                                    if(ndimn==2)rot(3,3)=1.
                                    if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                endif
                                rot=coef*rot
                                allocate(cmatrixl(kdimn,kdimn))
                                do jpoin=1,npgblock
                                    jtotv=(jpoin-1)*kdimn
                                    itotv=(ipoin-1)*kdimn
                                    cmatrixl=gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)
                                    gapb(igapb)%cmatrix(itotv+1:itotv+kdimn,jtotv+1:jtotv+kdimn)=  &
                                        (rot.x.cmatrixl)
                                end do
                                deallocate(cmatrixl)
                            end do
                            !!!!!!!!!!!!!!!!!!!!!!!
                            !if(nonsbt/=0)then
                            do idimn=1,gapb(igapb)%nrdof
                                itotvbt=npgblock*kdimn+idimn
                                if(gapb(igapb)%listrdof(idimn)==0)cycle
                                allocate(force_rigid(ntotv))
                                call force_unit_rigid_accs(igapb,idimn,force_rigid)

                                operation='SOLVE'
                                call solve

                                do ipoin=1,npgblock
                                    !kpoin=gapb(igapb)%nodegblock(ipoin)
                                    igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                                    ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                                    ij0=gapb(igapb)%nodegblock_onetwo(ipoin)   !2017/04/03
                                    coef=1.
                                    if(ij==2)coef=-1.
                                    rot=0.
                                    rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                                    if(kdimn>ndimn)then
                                        if(ndimn==2)rot(3,3)=1.
                                        if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                                    endif
                                    rot=coef*rot

                                    call result_node_to_center(kdimn,ij0,igaps,ipair,result,unitg)

                                    unitl=rot.x.unitg
                                    jtotv=(ipoin-1)*kdimn
                                    gapb(igapb)%cmatrix(jtotv+1:jtotv+kdimn,itotvbt)=   &
                                        gapb(igapb)%cmatrix(jtotv+1:jtotv+kdimn,itotvbt)+unitl
                                end do

                                call dfat_rigid(igapb,idimn,result,force_rigid)   !dfat due to stfor_inc
                                deallocate(force_rigid)
                            end do
                            !endif
                            deallocate(unitl,unitg)   !20121216
                            !!!!!!!!!!!!!!!!!!!!!!!!!!!
                        end do  !igapb
                        do igapb=1,ngapb
                            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
                            do itotvbt=1,gapb(igapb)%ntotv_bt
                                do jtotvbt=1,gapb(igapb)%ntotv_bt
                                    write(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                enddo
                            enddo
                        enddo  !igapb

                        deallocate(rot)
                    elseif(restart_ctt==1)then !restart_ctt
                        write(7,*)'read_cmatrix'
                        call forAdirect !fzx !形成A矩阵
                        rewind(recttunit)
                        do igapb=1,ngapb
                            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
                            do itotvbt=1,gapb(igapb)%ntotv_bt
                                do jtotvbt=1,gapb(igapb)%ntotv_bt
                                    read(recttunit)gapb(igapb)%cmatrix(itotvbt,jtotvbt)
                                enddo
                            enddo
                        enddo
                    else !restart_ctt
                        write(*,*)'no such restart_ctt!!'
                        stop
                    endif !restart_ctt
                endif  !!ctt2005

                if (nwcpipe/=0.and.(iiter==1.and.istep==inc_step))  &   !!20210411
                    call Tcmatrix_c_formation



90              format(10e12.5)

                !write(7,*)' itotv,tofor,stfor'
                !do itotv=1,ntotv
                !    write(7,*)itotv,tofor(itotv),stfor(itotv)
                !end do


                rvector=0.0
                !write(7,*)' itotv,totveq(itotv),rvector(totveq(itotv)),global_stiff1(iseq(totveq(itotv)))'

                if (type_solver/='JPCG') then
                    do itotv=1,ntotv
                        if (totveq(itotv)/=0)then
                            if (allocated(fexta))then  !!nstoks
                                rvector(totveq(itotv))=rvector(totveq(itotv))+tofor(itotv)+fexta(itotv)-stfor(itotv)
                            else
                                rvector(totveq(itotv))=rvector(totveq(itotv))+tofor(itotv)-stfor(itotv)

                                !if(abs(rvector(totveq(itotv)))>1.e-3) &
                                !write(7,*)itotv,totveq(itotv),rvector(totveq(itotv)),global_stiff1(iseq(totveq(itotv)))
                            endif
                        endif
                    end do
                    !!int2000
                    do itotv=1,ntotv
                        nintf=trans(itotv)%nintf
                        if (nintf/=0) then
                            iieq=totveq(itotv)
                            if(iieq/=0)rvector(iieq)=0.
                            do iintf=1,nintf
                                iieq=totveq(trans(itotv)%listf(iintf))
                                if(iieq/=0)rvector(iieq)=rvector(iieq)+(tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                            enddo
                        endif
                        !      if(totveq(itotv)/=0)then
                        !!if(abs(rvector(totveq(itotv)))>1.e-3) then
                        !!if(abs(totveq(itotv)).ne.0) then
                        !	!write(chkunit,'(2i8,20e16.6)')itotv,totveq(itotv),rvector(totveq(itotv)),global_stiff1(iseq(totveq(itotv)))
                        !      !endif
                        !      endif


                    enddo
                    !!int2000
                else !!if (type_solver/='JPCG') then

                    if (allocated(fexta))then   !!nstoks
                        rvector=tofor+fexta-stfor
                    else
                        rvector=tofor-stfor
                    endif
                endif


                if (type_nl==8) then
                    if(kstat/=2)call bfgsr(iiter)
                    if(kstat==2)call bfgsr(iiter-1)
                else
                    call dateandtime(curtime) !20200220
                    write(chkunit,2000)'Begin solution global equation     at ',curtime !20200220
                    write(*,2000)      'Begin solution global equation     at ',curtime !20200220
                    operation='SOLVE'
                    call solve
                endif
                !write(chkunit,'(a)')'result='
                !do itotv=1,ntotv
                !write(chkunit,*)itotv,result(itotv)
                !end do




                if(ngaps/=0.and.iblks>=iblks_bt)call solve_ctt  !!ctt2005
                if(nwcpipe/=0)call solve_heat_quantity_of_wc  !!20210411

                call varupdate !20230216

                !20230216 反演边界温度增量速率
                if(nbackdT==2.and.iiter==1) then
                    allocate(observstar(Npoints_pbx),dtv(nfixsets),dtvi(nfixsets))
                    observstar=0.

                    do i=1,mvalue
                        !print *,i,'Value_observ(i)%istep=',Value_observ(i)%istep
                        if(Value_observ(i)%iblks/=iblks)cycle
                        if(Value_observ(i)%iincs/=iincs)cycle
                        if(Value_observ(i)%istep/=istep)cycle
                        ivalue_point=Value_observ(i)%ivalue_point
                        observstar(ivalue_point)=Value_observ(i)%value_measure
                        nintf=para_points(ivalue_point)%nintf
                        listf=>para_points(ivalue_point)%listf
                        rintf=>para_points(ivalue_point)%rintf
                        Tpredict=dot_product(result_zero(listf),rintf)
                        !print *,'Tpredict=',Tpredict,'observstar(ivalue_point)=',observstar(ivalue_point)
                        observstar(ivalue_point)=observstar(ivalue_point)-Tpredict
                        nullify(listf,rintf)
                    end do
                    !print *,'observstar=',observstar
                    dTv=transpose(cmatrix_dtv).x.observstar
                    dtvi=inv_cmatrix_dtv2.x.dtv
                    !print *,'dtvi=',dtvi
                    dtvi=dtvi/(theta1*ditime)
                    !print *,'dtvi0=',dtvi


                    do i=1,ndofix    !20231130
                        mfixset=prescrib(i)%mfixset
                        do j=1,mfixset !20231130
                            ifixset=prescrib(i)%mlist(j)
                            idofn=prescrib(i)%ldofix
                            result_first(idofn)= result_first(idofn)+dtvi(ifixset)*prescrib(i)%rintf(j)
                            result_zero(idofn)= result_zero(idofn)+dtvi(ifixset)*prescrib(i)%rintf(j)*ditime !(theta1*ditime)
                        end do !20231130
                    end do !20231130


                    !   do i=1,ndofix
                    !ifixset=prescrib(i)%ifixset
                    !idofn=prescrib(i)%ldofix
                    !result_first(idofn)= result_first(idofn)+dtvi(ifixset)
                    !result_zero(idofn)= result_zero(idofn)+dtvi(ifixset)*ditime !(theta1*ditime)
                    !  end do

                    deallocate(observstar,dtv,dtvi)

                endif
                !20230216

                !call varupdate !20230216
                !call relative_dis_watertight !20231007 止水 !20240305
                call eload_initialize
                call residu_f
                call eload_couple
                call eload_field  !20210417
                if(algo_pipe>3) call pipe_cool_eload
                call eload_interface_fluid_solid  !!ifs2000
                call eload_absorb_fluid           !!ifs2000
                call eload_absorb_solid           !!ifs2000
                call eload_ifs2006                !!ifs2006 zhao, 06/03/29
                call heat_flow_charge(1)          !!! 20200316 pipe
                if(stabpw==1)call stabload


                call reaction_prescribed

                call conver_load
                if(nchek==0)call conver_nodal_value

                if(nchek==0)exit

            end do   !! loop for iiter
            ! call acc_rigid
            if(istatec==0) &
                call state_and_stiff_2021

            call local_stress    !20210207
            call contact_state(1) !20210207

            do igaps=1,ngaps
                npairs=gaps(igaps)%npairs
                do ipairs=1,npairs
                    if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                    gaps(igaps)%state0(ipairs)=gaps(igaps)%state(ipairs)
                    gaps(igaps)%damage0(ipairs)=gaps(igaps)%damage(ipairs)
                    gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
                    gaps(igaps)%dxyz0(:,ipairs)=gaps(igaps)%dxyz(:,ipairs)
                end do
            end do



            if(mdofn>7)then
                if (ifsnedge==0.and.type_problem=='F'.and.order_time_mdofn(8)==1)then
                    do ipoin=1,npoin
                        itotv=nodfn(lmdofn(8),ipoin)
                        IF(ITOTV/=0)result_second(itotv)=0.
                    enddo
                endif
            endif
            if(allocated(fexta))call find_fexta !!nstoks

            call cvoid(1)

            ! special for temperature (only) field
            if (outintw/=0)then
                resultm=0.
                do ipoin=1,npoin
                    idofn=nodfn(1,ipoin)
                    if(idofn/=0)resultm(ipoin)=result_zero(idofn)-result0(idofn)
                end do
                do ilink=1,ntlink
                    node1=tlink(1,ilink)
                    node2=tlink(2,ilink)
                    resultm(node1)=resultm(node2)
                end do
            endif
            ! end of special

            call gpvarupdate
            !write(7,*)'af gpvarupdate','stres0=',element(1)%field(1)%gpvar(1:3,1) !,'stres=',element(1)%field(1)%gpvar(1:3,1)

            if(gamamax/=0)call gamamaxupdate !20231125YL 更新地震过程中最大动剪应变
            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
                call outputres !for output
                call out_full_write
            endif

            if (istep/noutf*noutf==istep)then

                if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif

            if (outintw/=0) then
                !write(7,*)'resultm(931)=',resultm(931),'result_zero(931)=',result_zero(931)
                write(outint)resultm
            endif

            if(istep/nresta*nresta==istep)call resta_read_write(-1)

            if(nstepjq>0)then !20231215YL
                if(istep/nstepjq*nstepjq==istep)call liquifaction_judge
                if(istep/nstepJP*nstepJP==istep)call permdeform_judge
            endif !20231215YL

            if(nforce/=0.or.ngaps/=0)call force_interface
            !         if(nforce/=0.or.ngaps/=0)call write_force_interface
            if((nforce/=0.or.ngaps/=0).and.nextrf==0)call write_force_interface
            if(kstab/=0.)call safety_factor  !2019/03/20

            if (nextrf/=0)then  !2004/9/11
                do idofix=1,ndofix
                    itcurve =prescrib(idofix)%itcurve
                    type_curve='NONE'   ! M1-03 R18: itcurve=0 has no curve
                    if(itcurve/=0)type_curve=tcurves(itcurve)%type_curve
                    if (type_curve=='EXTRAPOLATION')then
                        if (istep>nextrf)then
                            do iextrf=1,nextrf-1
                                prescrib(idofix)%value_ext(:,iextrf+1)=prescrib(idofix)%value_ext(:,iextrf)
                            end do
                            prescrib(idofix)%value_ext(:,1)=result_zero(prescrib(idofix)%listep)
                        else
                            if(istep==1)prescrib(idofix)%value_ext(:,1)=0.
                            do iextrf=1,istep-1
                                prescrib(idofix)%value_ext(:,iextrf+1)=  &
                                    prescrib(idofix)%value_ext(:,iextrf)
                            end do
                            prescrib(idofix)%value_ext(:,1)=result_zero(prescrib(idofix)%listep)
                        endif
                    endif
                end do
            endif !2004/9/11
            !hxl2006 MIF
            if(type_ABC=='MIF')then
                do idofix=1,ndofix   !sanshe  hxl
                    ldofixb=>prescrib(idofix)%ldofixb
                    do ilaymif=1,nlaymif
                        !dissanru(istep,ldofixb(i))=result_zero(ldofixb(i))-inpru(ldofixb(i))
                        !dissanzi(istep,ldofixb(i))=result_zero(ldofixb(i))-inpzi(ldofixb(i))
                        disA(ldofixb(ilaymif))=result_zero(ldofixb(ilaymif))-inpru(ldofixb(ilaymif))
                        !对底边界，将总波场分解为入射波场与散射波场，disA即为散射波
                        disB(ldofixb(ilaymif))=result_zero(ldofixb(ilaymif))-inpzi(ldofixb(ilaymif))
                        !对侧边界，将总波场分解为自由波场与散射波场，disB即为散射波

                        !原因在于透射边界仅对散射波场，保证散射波场能够穿过人工边界而透向无限远处，但同时与要允许入射波场能够向上传播
                        !故进行波场分离。
                    end do
                    nullify(ldofixb)
                end do
            endif
            deallocate(inpru,inpzi)
            ! end hxl2006 MIF

            if(cdtest>=1)then
                nstre =group(1)%nstre
                call gpq (element(1)%field(1)%gpvar(1:nstre,1),p,q,eta)
                CVV=Q
                xl0=0.
                DIST0=ABS(CVV-XL0)
                DIST1=ABS(CVV-XL1(ITRAM))
                DIST2=ABS(CVV-XL2(ITRAM))
                DIST =ABS(XL1(ITRAM)-XL2(ITRAM))
                DISTF=ABS(XL2(ITRAM)-XL0)
                ICREV=0
                ICEND=0
                IF((DIST1.GE.DIST).OR.(DIST2.GE.DIST)) ICREV=1
                !C------------------------------------------------------
                !C       CHECK END OF TRAM
                !C-----------------------------------------------------
                NC1=2*NCYC(ITRAM)-1
                NC2=2*NCYC(ITRAM)
                !	    print *,'iseg=',iseg,'icrev=',icrev,'fincre=',fincre
                IF((cdtest==1).AND.(ISEG.EQ.NC1).AND.(ICREV.EQ.1)) ICEND=1
                IF((cdtest==2).AND.(ISEG.EQ.NC2).AND.(DIST2.GE.DISTF)) ICEND=1
                IF(ICEND.EQ.1) ITRAM=ITRAM+1
                IF((ICREV.NE.1).AND.(ICEND.NE.1)) GO TO 32
                ISEG=ISEG+1
                IF(ICEND.EQ.1)  ISEG=0
                fincre=-fincre
32              CONTINUE
                !       print *,'icend=',icend,'itram=',itram
                IF((ICEND.EQ.1).AND.(ITRAM.GT.NTRAM)) stop
            endif

            if(Bparameter>0)then !20230523
                !Value_observ(:)%value_computation=0.
                do ivalue=1,mvalue
                    !if(Value_observ(ivalue)%ic==0)cycle
                    iblks_i=Value_observ(ivalue)%iblks
                    iincs_i=Value_observ(ivalue)%iincs
                    istep_i=Value_observ(ivalue)%istep
                    idofn =lmdofn(Value_observ(ivalue)%idofn)
                    ivalue_point=Value_observ(ivalue)%ivalue_point
                    if(iblks_i==iblks.and.iincs_i==iincs.and.istep_i==istep)then
                        nintf=para_points(ivalue_point)%nintf
                        listf=>para_points(ivalue_point)%listf
                        rintf=>para_points(ivalue_point)%rintf
                        if(Bparameter==1)Value_observ(ivalue)%value_computation=dot_product(rintf,result_zero(nodfn(idofn,listf)))
                        if(Bparameter==2)Value_observ(ivalue)%value_computation=dot_product(rintf,deltafi(listf))
                        !write(7,*)'ivalue=',ivalue,'idofn=',idofn,'nodfn(idofn,listf)=',nodfn(idofn,listf)
                        !write(7,*)'ivalue_point=',ivalue_point,'listf=',listf,'Value_observ(ivalue)%value_computation=',Value_observ(ivalue)%value_computation


                        nullify(listf,rintf)
                    endif
                end do

            endif   !20230523



            if(Bparameter<0)then !20200812
                tbstep=tbstep+1
                do i=1,nback_point

                    bblks=freedom_for_back(4,i)  !20230523
                    if(bblks>iblks)cycle !20230523

                    inode=freedom_for_back(1,i)
                    idofn=freedom_for_back(2,i)
                    jnode=freedom_for_back(3,i)
                    itotv=nodfn(lmdofn(idofn),inode)
                    if(jnode/=0)jtotv=nodfn(lmdofn(idofn),jnode)
                    if(Bparameter==-1)then
                        Value_vc(i,tbstep,istoch)=result_zero(itotv)

                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-result_zero(jtotv)
                    elseif(Bparameter==-2)then
                        Value_vc(i,tbstep,istoch)=deltafi(itotv)
                        if(jnode/=0)Value_vc(i,tbstep,istoch)=Value_vc(i,tbstep,istoch)-deltafi(jtotv)
                    end if
                end do
            endif  !20200812

            if(outinp<0)then  !非稳定渗流场分析时向oip文件输出结点压力 20220623
                allocate(midt(npoin))  !20220626
                icdofn=lmdofn(8)
                midt=0.
                do ipoin=1,npoin
                    itotv=nodfn(icdofn,ipoin)
                    if (itotv/=0) then
                        midt(ipoin)=result_zero(itotv)
                    endif
                end do
                write(outinpunit)midt
                deallocate(midt)

            endif

            if(upliftin<0)then  !非稳定渗流场分析时向upf文件输出结点压力 20220623
                allocate(midt(npoin))  !20220626
                icdofn=lmdofn(8)
                midt=0.
                do ipoin=1,npoin
                    itotv=nodfn(icdofn,ipoin)
                    if (itotv/=0) then
                        midt(ipoin)=result_zero(itotv)
                    endif
                end do
                write(upliftunit)midt
                deallocate(midt)

            endif
            !if((bparameter>=1.and.bparameter<=2).and.balgor>=1) call dudx !20230430

        end do       !! for istep

        deallocate(disA,disB,disA_1,disB_1,disA_2,disB_2) !hxl2006 MIF
    end do     !! loop for iincs

    if(cdtest>=1)deallocate(xl1,xl2,ncyc,ic)
    if(outintw/=0)deallocate(resultm,result0)
    if(ngaps/=0) deallocate(tofor0)
2000 format(a,a)
    end subroutine time_dependent

    subroutine value_submodel_boundary  !20210324

    integer(ink) iu,it,itotv,idimn,kkdimn
    real   (irk), allocatable::value(:,:)

    if(res_u==1)then

        kkdimn=ndimn
        if(res_rot/=0) kkdimn=3*(ndimn-1)  !20221202

        allocate(value(kkdimn,tbpointsu))
        read(resbunit)value


        do iu=1,tbpointsu
            ipoin=listbpointsu_t(iu)
            do idimn=1,kkdimn
                itotv=nodfn(idimn,ipoin)
                if(istep==1) then
                    result_zero(itotv)=value(idimn,iu)
                    deltafi(itotv)=value(idimn,iu)
                else
                    deltafi(itotv)=value(idimn,iu)-result_zero(itotv)
                    result_zero(itotv)=value(idimn,iu)
                endif
                !write(chkunit,*)'iu=',iu,'ipoin=',ipoin,'idimn=',idimn,'value=',deltafi(itotv)

            end do
        end do


        if(res_v==1)then
            read(resbunit)value
            do iu=1,tbpointsu
                ipoin=listbpointsu_t(iu)
                do idimn=1,kkdimn
                    itotv=nodfn(idimn,ipoin)
                    result_first(itotv)=value(idimn,iu)
                end do
            end do
        endif

        if(res_a==1)then
            read(resbunit)value
            do iu=1,tbpointsu
                ipoin=listbpointsu_t(iu)
                do idimn=1,kkdimn
                    itotv=nodfn(idimn,ipoin)
                    result_second(itotv)=value(idimn,iu)
                end do
            end do
        endif
        deallocate(value)
    endif


    if(res_T==1)then
        allocate(value(1,tbpointst))
        read(resbunit)value

        do it=1,tbpointsT
            ipoin=listbpointst_t(it)
            itotv=nodfn(lmdofn(10),ipoin)
            result_zero(itotv)=value(1,it)
        end do
        if(res_Tv==1)then
            read(resbunit)value

            do it=1,tbpointsT
                ipoin=listbpointst_t(it)
                itotv=nodfn(lmdofn(10),ipoin)
                result_first(itotv)=value(1,it)
            end do
        endif
        deallocate(value)
    endif

    !write(7,*)'pressure='
    if(res_P==1)then
        allocate(value(1,tbpointsp))
        read(resbunit)value
        do it=1,tbpointsP
            ipoin=listbpointsp_t(it)
            itotv=nodfn(lmdofn(8),ipoin)
            result_zero(itotv)=value(1,it)
            !write(7,*)ipoin,result_zero(itotv)
        end do
        !write(7,*)'pressure_v='

        if(res_Pv==1)then
            read(resbunit)value
            do it=1,tbpointsP
                ipoin=listbpointsp_t(it)
                itotv=nodfn(lmdofn(8),ipoin)
                result_first(itotv)=value(1,it)
                !write(7,*)ipoin,result_first(itotv)

            end do
        endif
        !write(7,*)'pressure_a='

        if(res_Pa==1)then
            read(resbunit)value
            do it=1,tbpointsP
                ipoin=listbpointsp_t(it)
                itotv=nodfn(lmdofn(8),ipoin)
                result_second(itotv)=value(1,it)
                !write(7,*)ipoin,result_second(itotv)

            end do
        endif
        deallocate(value)
    endif

    end subroutine value_submodel_boundary !20210324

    !!!!!!!!!!!!!!!!!!!!!!!!!!
    SUBROUTINE force_unit_rigid_accs(igapb,jdimn,force_rigid)
    character(10)fieldid
    integer(ink) igroup,index,nnode_f, nevab_f, ic,ielgroup, ielem,ievab,itotv,igapb,jdimn,ipoin,jpoin,jgapb,kdimn,kkdimn
    real   (irk)  coef,alfa,beta,force_rigid(:)
    real   (irk), allocatable::fstif(:,:),eload(:),value(:),result_second_rigid(:)
    real   (irk), pointer::fstif0(:,:)
    integer(ink), pointer::ldofs(:)

    kkdimn=ndimn
    if(block_stab==1)kkdimn=3*(ndimn-1) !2015/11/17
    allocate(result_second_rigid(ntotv))

    rvector=0.;force_rigid=0.;result_second_rigid=0.
    do jpoin=1,gapb(igapb)%npblock
        ipoin=gapb(igapb)%nodeblock(jpoin)
        do kdimn=1,kkdimn  !idimn
            itotv=nodfn(kdimn,ipoin)
            if(itotv/=0) &
                result_second_rigid(itotv)=1.*gapb(igapb)%npdisp(kdimn,jpoin,jdimn)
        end do   !kdimn
    end do   !jpoin

    !	write(7,*)'result_second_rigid=',result_second_rigid

    do jgapb=1,gapb(igapb)%ngroupb
        igroup=gapb(igapb)%listgroupb(jgapb)
        fieldid=group(igroup)%fieldid
        if(appear(igroup)>0)  then
            ! get information from the group level
            index    = group(igroup)%index
            alfa=group(igroup)%alfa
            beta=group(igroup)%beta
            nnode_f = elkn(index)%el_field(1)%nnode_f
            nevab_f = nnode_f*group(igroup)%dof(1)%nfdof
            allocate(fstif(nevab_f,nevab_f),eload(nevab_f),value(nevab_f))
            ! loop for k(h) and m(c)
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                if(fieldid(1:1)=='U') then
                    if(associated(element(ielem)%field(1)%khandmc(2)%fstif)) then
                        coef=1.0+alfa*beeta1*ditime                         !-------------------------------!
                        ldofs=>element(ielem)%field(1)%ldofs_f
                        value=result_second_rigid(ldofs)
                        fstif0=>element(ielem)%field(1)%khandmc(2)%fstif
                        ic=size(fstif0,dim=2)
                        if(ic==1)then
                            fstif=0.0
                            do ievab=1,nevab_f
                                fstif(ievab,ievab)=fstif0(ievab,1)
                            end do
                        else
                            fstif=fstif0
                        end if
                        fstif=coef*fstif
                        eload=fstif.x.value
                        force_rigid(ldofs)=force_rigid(ldofs)+eload
                        nullify(fstif0,ldofs)
                    endif
                endif
            end do       !!ielgroup
            deallocate(fstif,eload,value)
        end if    !! for do while
    end do     !!  for igroup

    do itotv=1,ntotv
        if (totveq(itotv)>0)rvector(totveq(itotv))=rvector(totveq(itotv))-force_rigid(itotv)
    end do


    deallocate(result_second_rigid)

    END SUBROUTINE force_unit_rigid_accs


    SUBROUTINE dfat_rigid(igapb,idimn,resi,force_rigid)
    character(10)fieldid
    character(30)material
    integer(ink) igroup, nrfields, ifield,  index, order_time,     &
        nnode_f, nevab_f,   ic,   idimn,igapb, jgapb, npblock,npgblock,kdimn,       &
        ielgroup, ielem,   ievab,  ikh, anevab,  matno, nstre,jdimn,jtotvbt,itotvbt

    real   (irk)  coef,alfa,beta,lamda,resi(:),force_rigid(:)
    real   (irk), allocatable::fstif(:,:),eload(:),value(:),stfor_inc(:),df(:),dfat(:),mtrxA(:,:)
    real   (irk), pointer::fstif0(:,:)
    integer(ink), pointer::ldofs(:)

    allocate(stfor_inc(ntotv))
    stfor_inc=0.
    do jgapb=1,gapb(igapb)%ngroupb
        igroup=gapb(igapb)%listgroupb(jgapb)
        if(appear(igroup)>0)  then

            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            matno = group(igroup)%matno
            nstre=  group(igroup)%nstre
            if(fieldid(1:1)=='U') &
                material=props(matno)%mechanical%solid%material
            index    = group(igroup)%index
            alfa=group(igroup)%alfa
            beta=group(igroup)%beta
            do ifield=1,nrfields
                nnode_f = elkn(index)%el_field(ifield)%nnode_f
                nevab_f = nnode_f*group(igroup)%dof(ifield)%nfdof
                allocate(fstif(nevab_f,nevab_f),eload(nevab_f),value(nevab_f))
                ! loop for k(h) and m(c)
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(fieldid(ifield:ifield)=='U') then
                        do ikh=1,2
                            if(associated(element(ielem)%field(ifield)%khandmc(ikh)%fstif)) then
                                if(ikh==1)coef=beeta2*ditime**2+beta*beeta1*ditime          !
                                if(ikh==2)coef=1.0+alfa*beeta1*ditime                         !-------------------------------!

                                ldofs=>element(ielem)%field(ifield)%ldofs_f
                                value=resi(ldofs)
                                fstif0=>element(ielem)%field(ifield)%khandmc(ikh)%fstif
                                ic=size(fstif0,dim=2)
                                if(ikh==2.and.ic==1)then
                                    fstif=0.0
                                    do ievab=1,nevab_f
                                        fstif(ievab,ievab)=fstif0(ievab,1)
                                    end do
                                else
                                    fstif=fstif0
                                end if
                                fstif=coef*fstif
                                eload=fstif.x.value
                                stfor_inc(ldofs)=stfor_inc(ldofs)+eload
                                nullify(fstif0,ldofs)
                            endif
                        end do        !!end do ikh
                    endif
                end do       !!ielgroup
                deallocate(fstif,eload,value)
            end do     !! end do ifield
        end if    !! for do while
    end do     !!  for igroup

    kdimn=ndimn
    if(block_stab==1)kdimn=3*(ndimn-1) !2015/11/17
    allocate(df(kdimn),dfat((ndimn-1)*3),mtrxA(kdimn,(ndimn-1)*3))
    df=0. ;  dfat=0. ;mtrxA=0.

    dfat=0.
    npblock=gapb(igapb)%npblock
    npgblock=gapb(igapb)%npgblock
    do jpoin=1,gapb(igapb)%npblock
        ipoin=gapb(igapb)%nodeblock(jpoin)
        df=0.
        do jdimn=1,kdimn !严格的说，应该用cdofn,ndof
            itotv=nodfn(jdimn,ipoin)
            if(itotv/=0) &
                df(jdimn)=-stfor_inc(itotv)-force_rigid(itotv)
        enddo

        mtrxa=0.
        do jdimn=1,gapb(igapb)%nrdof
            mtrxa(:,jdimn)=gapb(igapb)%npdisp(:,jpoin,jdimn)
        end do

        dfat=dfat+matmul(transpose(mtrxA),df)

    enddo !jpoin
    jtotvbt=npgblock*kdimn+idimn
    do jdimn=1,gapb(igapb)%nrdof
        itotvbt=npgblock*kdimn+jdimn
        gapb(igapb)%cmatrix(itotvbt,jtotvbt)=gapb(igapb)%cmatrix(itotvbt,jtotvbt)+dfat(jdimn)

    enddo !jdimn

    deallocate(stfor_inc,df,dfat,mtrxA)

    END SUBROUTINE dfat_rigid

    SUBROUTINE dfat_rigid_ctfor(igapb,itotvbt,resi)
    character(10)fieldid
    character(30)material
    integer(ink) kpoin,ipoin,igroup, nrfields, ifield,  index, order_time,     &
        nnode_f, nevab_f,   ic,  igapb, jgapb, npblock,npgblock,kdimn,       &
        ielgroup, ielem,   ievab,  ikh, anevab,  matno, nstre,jdimn,jtotvbt,itotvbt

    real   (irk)  coef,alfa,beta,lamda,resi(:)
    real   (irk), allocatable::fstif(:,:),eload(:),value(:),stfor_inc(:),df(:),dfat(:),mtrxA(:,:)
    real   (irk), pointer::fstif0(:,:)
    integer(ink), pointer::ldofs(:)

    allocate(stfor_inc(ntotv))
    stfor_inc=0.

    do jgapb=1,gapb(igapb)%ngroupb
        igroup=gapb(igapb)%listgroupb(jgapb)
        if(appear(igroup)>0)  then

            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            matno = group(igroup)%matno
            nstre=  group(igroup)%nstre
            if(fieldid(1:1)=='U') &
                material=props(matno)%mechanical%solid%material
            index    = group(igroup)%index
            alfa=group(igroup)%alfa
            beta=group(igroup)%beta
            do ifield=1,nrfields
                nnode_f = elkn(index)%el_field(ifield)%nnode_f
                nevab_f = nnode_f*group(igroup)%dof(ifield)%nfdof
                allocate(fstif(nevab_f,nevab_f),eload(nevab_f),value(nevab_f))
                ! loop for k(h) and m(c)
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(fieldid(ifield:ifield)=='U') then
                        do ikh=1,2
                            if(associated(element(ielem)%field(ifield)%khandmc(ikh)%fstif)) then
                                if(ikh==1)coef=beeta2*ditime**2+beta*beeta1*ditime          !
                                if(ikh==2)coef=1.0+alfa*beeta1*ditime                         !-------------------------------!

                                ldofs=>element(ielem)%field(ifield)%ldofs_f
                                value=resi(ldofs)
                                fstif0=>element(ielem)%field(ifield)%khandmc(ikh)%fstif
                                ic=size(fstif0,dim=2)
                                if(ikh==2.and.ic==1)then
                                    fstif=0.0
                                    do ievab=1,nevab_f
                                        fstif(ievab,ievab)=fstif0(ievab,1)
                                    end do
                                else
                                    fstif=fstif0
                                end if
                                fstif=coef*fstif
                                eload=fstif.x.value
                                stfor_inc(ldofs)=stfor_inc(ldofs)-eload
                                nullify(fstif0,ldofs)
                            endif
                        end do        !!end do ikh
                    endif
                end do       !!ielgroup
                deallocate(fstif,eload,value)
            end do     !! end do ifield
        end if    !! for do while
    end do     !!  for igroup

    kdimn=ndimn
    if(block_stab==1)kdimn=(ndimn-1)*3

    allocate(df(kdimn),dfat((ndimn-1)*3),mtrxA(kdimn,(ndimn-1)*3))
    df=0. ; dfat=0. ; mtrxA=0.

    dfat=0.
    npblock=gapb(igapb)%npblock
    npgblock=gapb(igapb)%npgblock
    do jpoin=1,gapb(igapb)%npblock
        ipoin=gapb(igapb)%nodeblock(jpoin)
        df=0.
        do jdimn=1,kdimn !严格的说，应该用cdofn,ndof
            itotv=nodfn(jdimn,ipoin)
            if(itotv/=0) &
                df(jdimn)=stfor_inc(itotv)
        enddo

        mtrxa=0.
        do jdimn=1,gapb(igapb)%nrdof
            mtrxa(:,jdimn)=gapb(igapb)%npdisp(:,jpoin,jdimn)
        end do

        dfat=dfat+matmul(transpose(mtrxA),df)
    enddo !jpoin

    do jdimn=1,gapb(igapb)%nrdof
        jtotvbt=npgblock*kdimn+jdimn
        gapb(igapb)%cmatrix(jtotvbt,itotvbt)=gapb(igapb)%cmatrix(jtotvbt,itotvbt)+dfat(jdimn)
    enddo !jdimn

    deallocate(stfor_inc,df,dfat,mtrxA)

    END SUBROUTINE dfat_rigid_ctfor
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine frequency_analysis !freq2006

    character(80)text,type_curve
    integer(ink) itotv,ielem
    integer(ink) ilink,node1,node2,ipoin,idofn
    real   (irk), allocatable::resultm(:)
    real   (irk) time
    integer(ink) iintf,nintf,iieq   !!int2000


    if(allocated(fachv))deallocate(fachv)
    allocate(fachv(ndimn))
    read(mainunit,*)text
    read(mainunit,*)nincs,fachv

    time=0.0

    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    do iincs=lincs+1,nincs
        print *,'  time depend     iincs=',  iincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)

        do istep=1,nstep
            print *, 'iblks=',iblks,'iincs=',iincs,'istep=',istep
            time=time+ditime
            ttime=ttime+ditime        !! only for output
            print *,'ttime=',ttime

            !deltafi=0.0
            stforw=0.
            call modf_var_prescribed_w
            do iiter=1,miter
                print *,'iiter=',iiter
                if (istep==1.and.iiter==1)then
                    call stiff_u
                    call mcmatrx('U')
                    call mcmatrx('W')
                    if(allocated(fmass))call fmass_assemble
                    call hmatrx('W')
                    call upwcouple
                    !               if(stabpw==1) call stabpatch    !!stablize
                endif

                if (iiter==1)then
                    global_stiff1w=0.0
                    if(nonsym/=0)global_stiff2w=0.0
                    call estif_assemble_w
                    call couple_assemble_w
                    if(stabpw==1)     call stabpw_assemble_w           !! stablize
                    if(nifsgroup/=0)  call assemble_interface_fs_w !!ifs2000
                    if(nabsfgroup/=0) call assemble_absorb_fluid_w !!ifs2000
                    if(nabssgroup/=0) call assemble_absorb_solid_w !!ifs2000
                    if(ifsnedge/=0)   call assemble_stiff_ifs2006_w !ifs2006
                endif

                if (iiter==1) call force_external_w
                if (iiter==1)then
                    operation='FACTORIZE'
                    call solve
                end if

                rvectorw=(0.0,0.)
                do itotv=1,ntotv
                    if(totveq(itotv)/=0)rvectorw(totveq(itotv))=rvectorw(totveq(itotv))+ &
                        (toforw(itotv)-stforw(itotv))
                end do

                !!int2000
                do itotv=1,ntotv
                    nintf=trans(itotv)%nintf
                    if (nintf/=0) then
                        iieq=totveq(itotv)
                        if(iieq/=0)rvectorw(iieq)=(0.,0.)
                        do iintf=1,nintf
                            iieq=totveq(trans(itotv)%listf(iintf))
                            if(iieq/=0)rvectorw(iieq)=rvectorw(iieq)+(toforw(itotv)-stforw(itotv))*trans(itotv)%rintf(iintf)
                        end do
                    endif
                end do
                !!int2000
                !            write(7,*)'global_stif,rvector'
                !            do itotv=1,ntotv
                !               if (abs(totveq(itotv)).ne.0) then
                !                  write(chkunit,*)itotv,totveq(itotv),global_stiff1w(iseq(totveq(itotv))),rvectorw(totveq(itotv))
                !               endif
                !            end do



                operation='SOLVE'
                call solve

                stforw=(0.,0.)
                call varupdate_w
                call eload_couple_w
                call eload_field_w
                call eload_interface_fs_w      !!ifs2000
                call eload_absorb_fluid_w      !!ifs2000
                call eload_absorb_solid_w      !!ifs2000
                call eload_ifs2006_w           !ifs2006
                call conver_load_w
                if(nchek==0)exit

            end do   !! loop for iiter


            !         call gpvarupdate

            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
            endif

            !         if(istep/noutf*noutf==istep)then
            !         call out_full_write
            if(outplot(1:3)=='GID')   call out_gid_write_w
            !         if(outplot(1:6)=='COSMOS')call out_cosmos_write
            !         endif

            if(istep/nresta*nresta==istep)call resta_read_write(-1)

            if(nforce/=0.or.ngaps/=0)call force_interface
            !         if(nforce/=0.or.ngaps/=0)call write_force_interface

        end do       !! for istep
    end do     !! loop for iincs

    end subroutine frequency_analysis

    !explicit
    subroutine explicit

    character(80)text
    integer(ink) itotv,ielem,iintf,iieq
    integer(ink),allocatable::earthquake_curve(:)
    real   (irk), allocatable::rmid(:)
    real   (irk) time
    real   (irk),pointer::ymass(:,:)
    integer(ink),pointer::ldofs(:)
    if(allocated(rmid))deallocate(rmid)
    if(allocated(result))deallocate(result)
    if(allocated(rvector))deallocate(rvector)
    allocate(rmid(ntotv),result(ntotv),rvector(ntotv))

    print *,     'in explicit'
    if(iblks==1)call cvoid(0)
    allocate(earthquake_curve(ndimn),fachv(ndimn))
    read(mainunit,*)text
    read(mainunit,*)nincs,earthquake_curve(1:ndimn)
    time=0.0
    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    do iincs=lincs+1,nincs
        print *,'  time depend     iincs=',  iincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        do istep=1,nstep
            print *, '     istep=',istep
            if(outintr>0.and.iblks>=outintr)trstep=trstep+1  !20200226
            time=time+ditime
            ttime=ttime+ditime        !! only for output

            call dfact_time_curve(ttime)

            where(earthquake_curve==0)
                fachv=0.0
            elsewhere
                fachv=tcurves(earthquake_curve)%dfact
            endwhere

            call modf_var_prescribed
            call heat_internal        ! temperature
            deltafi=0.0

            do iiter=1,miter

                call algort
                call porepr
                if(kswkw/=0)call propty
                if(kresl/=0)call stiff_u
                if(kmass/=0)call mcmatrx('U')
                if(ksmat/=0)call mcmatrx('W')
                if(ktsmat/=0)call stmatrx
                if(khmat/=0)call hmatrx('W')
                if(kthmat/=0)call htmatrx
                call assemble_boundt_estif
                if(kqmat/=0)call upwcouple
                if(stabpw==1.and.khmat/=0) call stabpatch   !!stablize
                !!explicit
                print *,'kmass=',kmass
                if (ktsmat/=0.or.kmass/=0) then
                    rmid=0.
                    do ielem=1,nelem
                        ymass=>element(ielem)%field(1)%khandmc(2)%fstif
                        ldofs=>element(ielem)%field(1)%ldofs_f
                        rmid(ldofs)=rmid(ldofs)+ymass(:,1)
                    end do
                end if

                !!int2000
                do itotv=1,ntotv
                    nintf=trans(itotv)%nintf
                    if (nintf/=0) then
                        do iintf=1,nintf
                            iieq=trans(itotv)%listf(iintf)
                            if(iieq/=0) &
                                rmid(iieq)=rmid(iieq)+rmid(itotv)*trans(itotv)%rintf(iintf)
                        end do
                    endif
                end do
                !!int2000

                !! end explicit

                if(kgrav/=0)call gravity
                if(kldfl/=0)call loadfl

                if(iiter==1) call force_external

                if (iiter==1) then     ! iiter==1

                    call eload_initialize
                    call predict
                    call residu_f
                    call eload_couple
                    call eload_field
                    if(stabpw==1)call stabload
                    call force_internal

                endif          ! iiter=1

                rvector=tofor-stfor

                !!int2000
                do itotv=1,ntotv
                    nintf=trans(itotv)%nintf
                    if (nintf/=0) then
                        do iintf=1,nintf
                            iieq=trans(itotv)%listf(iintf)
                            if(iieq/=0) &
                                rvector(iieq)=rvector(iieq)+(tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                        end do
                    endif
                end do
                do itotv=1,ntotv
                    nintf=trans(itotv)%nintf
                    if(nintf==0) &
                        result(itotv)=rvector(itotv)/rmid(itotv)  !!!
                end do

                !!int2000
                do itotv=1,ntotv
                    nintf=trans(itotv)%nintf
                    if (nintf/=0) then
                        result(itotv)=0.
                        do iintf=1,nintf
                            iieq=trans(itotv)%listf(iintf)
                            result(itotv)=result(itotv)+result(iieq)*trans(itotv)%rintf(iintf)
                        enddo
                    endif
                end do
                !!int2000
                !!int2000
                !            do itotv=1,ntotv
                !               result(itotv)=rvector(itotv)/rmid(itotv)  !!!
                !            end do

                call varupdate

                call eload_initialize
                call residu_f
                call eload_couple
                call eload_field
                if(stabpw==1)call stabload
                call reaction_prescribed
                call conver_load
                if(nchek==0)call conver_nodal_value
                if(nchek==0)exit

            end do   !! loop for iiter

            call cvoid(1)
            call gpvarupdate

            if (istep/noutn*noutn==istep)then
                iwriten=iwriten+1
                call out_record
            endif

            if (istep/noutf*noutf==istep)then
                call out_full_write
                if(outplot(1:3)=='GID')   call OUT_GID_WRITE
                if(outplot(1:6)=='COSMOS')call OUT_COSMOS_WRITE
            endif
            if(istep/nresta*nresta==istep)call resta_read_write(-1)
        end do       !! for istep
    end do     !! loop for iincs

    end subroutine explicit

    !explicit

    !response_spectrum

    subroutine response_spectrum ! only available for u field + w field

    character(80)text
    integer(ink) itotv,iieq,nintf,iintf,jtotv,idimn,imcon,  &
        jstep,max_dofn,max_poin,max_dim,jiter,ipoin,idofn,maloc(1)
    integer(ink),pointer::listf(:)
    real   (irk), allocatable::rmid(:),alfa(:),beta(:),lamda(:),deltafp(:),   &
        dis_shape(:,:),mdelta(:),disone(:),loadone(:), &
        disthree(:),loadthree(:),kdelta(:),   &
        distwo(:),loadtwo(:) !zhao
    real   (irk),pointer::rintf(:)
    real   (irk) time,lamda_iter,omega,alfa_mid,beta_mid,coefx,coefy,coefz,kstar,coef !zhao


    print *,'response_spectrum'
    if(allocated(rmid))deallocate(rmid)
    if(allocated(rvector))deallocate(rvector)
    allocate(rmid(ntotv),rvector(ntotv),mdelta(ntotv),disone(ntotv),loadone(ntotv),kdelta(ntotv))
    if(nifsgroup/=0)allocate(deltafp(ntotv))
    allocate(disthree(ntotv),loadthree(ntotv),distwo(ntotv),loadtwo(ntotv))

    read(mainunit,*)text
    read(mainunit,*)nincs
    time=0.0
    do iincs=1,lincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,nmcon !20210118
        read(mainunit,*)toler_force,toler_var(1:mdofn)
    end do

    do iincs=lincs+1,nincs
        print *,'  time depend     iincs=',  iincs
        read(mainunit,*)miter,ditime,noutn,noutf,nstep,inc_step,nresta,nmcon  !20210118
        read(mainunit,*)toler_force,toler_var(1:mdofn)
        read(mainunit,*)max_poin,max_dim
        if(nmcon/=0)allocate(lmcon(nmcon),rmcon(ndimn,nmcon))
        if (nmcon/=0) then
            read(mainunit,*)coef
            do imcon=1,nmcon
                read(mainunit,*)i0,lmcon(imcon),rmcon(:,imcon)
            end do
            rmcon=abs(rmcon)*coef
        endif
        max_dofn=nodfn(max_dim,max_poin)

        allocate(beta(nstep),alfa(nstep),dis_shape(ntotv,nstep),lamda(nstep))

        do istep=1,nstep

            print *, 'istep=',istep
            if(outintr>0.and.iblks>=outintr)trstep=trstep+1  !20200226
            time=time+ditime
            ttime=ttime+ditime        !! only for output
            call dfact_time_curve(ttime)
            call modf_var_prescribed

            if (istep==1) then
                iiter=1
                call stiff_u
                call mcmatrx('U')
                call hmatrx('W')
                global_stiff1=0.
                call estif_assem_response
                !write(7,*)'global_stiff1**'
                !do itotv=1,neq
                !    write(7,*)itotv,global_stiff1(iseq(itotv))
                !   if(abs(global_stiff1(iseq(itotv))).le.1.e-5)global_stiff1(iseq(itotv))=1.e30
                !end do
                !            call skfacs_layer(global_stiff1,iseq,0)
                if (type_solver=='PROFILE') then !zhao 20070829
                    call skfacs_layer(global_stiff1,iseq,1)
                    call skfacs_layer(global_stiff1,iseq,2)
                    write(7,*)'neq_layer1=',neq_layer1,'neq=',neq
                ELSEIF(type_solver=='PARDISO')THEN
                    operation='FACTORIZE'
                    call solve
                endif
            endif

            if (istep==1) then
                deltafi=0.
                disone=0.
                distwo=0. !zhao
                disthree=0.

                do ipoin=1,npoin
                    DO idimn=1,ndimn
                        itotv=nodfn(idimn,ipoin)
                        if (itotv/=0) then
                            if(iffix(itotv)==0)deltafi(itotv)=1.
                        endif
                    enddo
                end do

                do ipoin=1,npoin
                    itotv=nodfn(1,ipoin)
                    if (itotv/=0) then
                        if(iffix(itotv)==0)disone(itotv)=1.
                    endif
                end do

                if (cdofn>1)then
                    do ipoin=1,npoin
                        itotv=nodfn(2,ipoin)
                        if (itotv/=0) then
                            if(iffix(itotv)==0)distwo(itotv)=1.
                        endif
                    end do
                endif

                if (cdofn>2)then
                    do ipoin=1,npoin
                        itotv=nodfn(3,ipoin)
                        if (itotv/=0) then
                            if(iffix(itotv)==0)disthree(itotv)=1.
                        endif
                    end do
                endif

            endif !if (istep==1) then

            do jiter=1,miter

                rmid=0.
                if(nifsgroup/=0)call load_of_addtional_mass(rmid,deltafi,deltafp)
                call load_of_mass(rmid,deltafi)

                do jstep=1,istep-1
                    beta_mid=dis_shape(:,jstep).d.rmid
                    beta(jstep)=alfa(jstep)*beta_mid
                end do

                rvector=0.0
                do itotv=1,ntotv
                    if(totveq(itotv)/=0.and.totveq(itotv).le.neq_layer1) &
                        rvector(totveq(itotv))=rvector(totveq(itotv))+rmid(itotv)
                end do
                !!int2000
                do itotv=1,ntotv
                    nintf=trans(itotv)%nintf
                    if (nintf/=0) then
                        iieq=totveq(itotv)
                        if(iieq/=0)rvector(iieq)=0.
                        do iintf=1,nintf
                            iieq=totveq(trans(itotv)%listf(iintf))
                            if(iieq/=0) &
                                rvector(iieq)=rvector(iieq)+rmid(itotv)*trans(itotv)%rintf(iintf)
                        end do
                    endif
                end do
                !!int2000


                if (type_solver=='PROFILE') then !zhao 20070829
                    call sksols_layer(global_stiff1,rvector,iseq,1)
                    !             call sksols_layer(global_stiff1,rvector,iseq,0)
                    !!int2000
                    deltafi=0.
                    do itotv=1,ntotv
                        nintf=trans(itotv)%nintf
                        if (iffix(itotv)==0.and.nintf==0) then
                            deltafi(itotv)=rvector(totveq(itotv))
                        elseif(nintf/=0) then
                            listf=>trans(itotv)%listf
                            rintf=>trans(itotv)%rintf
                            do jtotv=1,nintf
                                if(totveq(listf(jtotv))>0)deltafi(itotv)=deltafi(itotv)+rvector(totveq(listf(jtotv)))*rintf(jtotv)
                            enddo
                        endif
                    end do
                    !!int2000
                elseif(type_solver=='SSORPBCG')then !zhao 20070829

                    operation='SOLVE'
                    call solve
                    deltafi=result
                elseif(type_solver=='PARDISO')then
                    operation='SOLVE'
                    call solve
                    deltafi=result
                else
                    stop 'type_solver, in response_spectrum '

                endif
                do jstep=1,istep-1
                    deltafi=deltafi-beta(jstep)*dis_shape(:,jstep)
                end do

                !lamda(istep)=abs(deltafi(max_dofn))
                lamda(istep)=maxval(abs(deltafi))
                !lamda(istep)=0.
                do ipoin=1,0 !npoin
                    do idimn=1,ndimn
                        if(idimn>mdofn)cycle
                        if(lmdofn(idimn)==0)cycle
                        itotv=nodfn(lmdofn(idimn),ipoin)
                        if(itotv==0)cycle
                        if(abs(lamda(istep))<abs(deltafi(itotv)))lamda(istep)=deltafi(itotv)
                    enddo
                enddo
                !maloc=maxloc(abs(deltafi))
                !lamda(istep)=deltafi(maloc(1))

                deltafi=deltafi/lamda(istep)
                print *,'max_dofn=',max_dofn
                print *,'lamda(istep)=',lamda(istep),'lamda_iter=',lamda_iter
                if(abs(lamda(istep)-lamda_iter)/abs(lamda(istep)).le.1.e-12) goto 10
                lamda_iter=lamda(istep)
                print *,'iiter=',jiter,'lamda_iter=',lamda_iter

            end do !for iiter
10          continue
            dis_shape(:,istep)=deltafi

            if (istep==1) then
                loadone=0.
                loadtwo=0.
                loadthree=0.
                if(nifsgroup/=0)call load_of_addtional_mass(loadone,disone,deltafp)
                call load_of_mass(loadone,disone)
                if(nifsgroup/=0)call load_of_addtional_mass(loadtwo,distwo,deltafp)
                call load_of_mass(loadtwo,distwo)
                if(nifsgroup/=0)call load_of_addtional_mass(loadthree,disthree,deltafp)
                call load_of_mass(loadthree,disthree)
            endif

            mdelta=0.
            kdelta=0.
            if(nifsgroup/=0)call load_of_addtional_mass(mdelta,deltafi,deltafp)
            call load_of_mass(mdelta,deltafi)

            alfa_mid=deltafi.d.mdelta
            alfa(istep)=lamda(istep)/alfa_mid

            coefx=deltafi.d.loadone
            coefx=coefx/alfa_mid

            coefy=deltafi.d.loadtwo
            coefy=coefy/alfa_mid

            coefz=deltafi.d.loadthree
            coefz=coefz/alfa_mid

            result_zero=deltafi
            if (nifsgroup/=0)then
                do ipoin=1,npoin
                    idofn=lmdofn(8)
                    itotv=nodfn(idofn,ipoin)
                    if(itotv/=0)result_zero(itotv)=deltafp(itotv)
                end do
            endif
            !only for Mode Superposition Method
            !zhao 2005/06/23
            call load_of_stiff(kdelta,deltafi)

            do itotv=1,ntotv
                write(faiunit)result_zero(itotv)
            enddo

            kstar=deltafi.d.kdelta
            omega=1./sqrt(lamda(istep))
            write(chkunit,100)istep,omega,omega/(2.*3.14159),2.*3.14159/omega,coefx,coefy,coefz,alfa_mid,kstar
100         format('  order=',i5,'  omega=',e12.5,'  freq=',e12.5,'  period=',e12.5,' coefx=',e12.5,' coefy=',e12.5, &
                ' coefz=',e12.5,' mstar=',e12.5,' kstar=',e12.5)

            call residu_f
            if (istep/noutf*noutf==istep)then
                call out_full_write
                if(outplot(1:3)=='GID')   call OUT_GID_WRITE
            endif
            if(istep/nresta*nresta==istep)call resta_read_write(-1)
            if(nforce/=0.or.ngaps/=0)call force_interface
            if((nforce/=0.or.ngaps/=0).and.nextrf==0)call write_force_interface
        end do       !! for istep
    end do     !! loop for iincs

    end subroutine response_spectrum

    !===========================================================================
    SUBROUTINE base_frequency_analysis !20231008

    character(80)text
    integer(ink) itotv,iieq,nintf,iintf,jtotv,  &
        jiter,ipoin,idofn
    integer(ink),pointer::listf(:)
    real   (irk), allocatable::rmid(:),deltafp(:)
    real   (irk),pointer::rintf(:)
    real   (irk) time,lamda_iter,omega,lamda


    call dateandtime(curtime)
    write(chkunit,'(a,a)')'Begin calculating base frequency   at ',curtime
    write(*,'(a,a)')      'Begin calculating base frequency   at ',curtime

    if(allocated(rmid))deallocate(rmid)
    if(allocated(rvector))deallocate(rvector)
    allocate(rmid(ntotv),rvector(ntotv))
    if(nifsgroup/=0)allocate(deltafp(ntotv))

    !    call dfact_time_curve(ttime)
    call modf_var_prescribed

    iiter=1
    call stiff_u
    call mcmatrx('U')
    call hmatrx('W')
    global_stiff1=0.
    call estif_assem_response

    operation='FACTORIZE'
    call solve

    deltafi=0.
    do itotv=1,ntotv
        if(iffix(itotv)==0)then
            deltafi(itotv)=1.
        endif
    enddo

    do jiter=1,100
        rmid=0.
        if(nifsgroup/=0)call load_of_addtional_mass(rmid,deltafi,deltafp)     !nzw 2013-5-6 cancle comment
        call load_of_mass_base(rmid,deltafi)
        rvector=0.0
        do itotv=1,ntotv
            if(totveq(itotv)/=0) then
                rvector(totveq(itotv))=rvector(totveq(itotv))+rmid(itotv)
            endif
        end do

        do itotv=1,ntotv
            nintf=trans(itotv)%nintf
            if(nintf/=0) then
                iieq=totveq(itotv)
                if(iieq/=0)rvector(iieq)=0.
                do iintf=1,nintf
                    iieq=totveq(trans(itotv)%listf(iintf))
                    if(iieq/=0) &
                        rvector(iieq)=rvector(iieq)+rmid(itotv)*trans(itotv)%rintf(iintf)
                end do
            endif
        end do
        operation='SOLVE'
        call solve
        deltafi=result
        lamda=maxval(abs(deltafi))
        deltafi=deltafi/lamda
        if(abs(lamda-lamda_iter)/abs(lamda).le.1.e-8) goto 10
        lamda_iter=lamda

    end do !for iiter
10  continue

    omega=1./sqrt(lamda)
    base_freq=omega
    write(chkunit,100)omega,2.*3.14159/omega
    write(omgunit,100)omega,2.*3.14159/omega     !psy.2018.11.01
100 format('  omega=',e12.5,'  period=',e12.5)

    END SUBROUTINE base_frequency_analysis  !903

    !20231215YL
    subroutine load_of_mass_base(rmid1,dis) !20231008
    character(1)field1
    integer(ink) ielem,nevab,ic,ielgroup,ii,ipoin,inode,idimn,itotv
    integer(ink),pointer::ldofs(:)
    real   (irk),allocatable::eldis(:),eload(:)
    real   (irk),pointer::fstif(:,:)
    real   (irk) dis(:)
    real(irk) rmid1(:)

    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if(appear(igroup)>0.and.field1=='U') then
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                if(associated(element(ielem)%field(1)%khandmc(2)%fstif)) then
                    fstif=>element(ielem)%field(1)%khandmc(2)%fstif
                    ldofs=>element(ielem)%field(1)%ldofs_f
                    nevab=size(ldofs)
                    allocate(eldis(nevab),eload(nevab))
                    ic=size(fstif,dim=2)
                    eldis = dis(ldofs)
                    if(ic==1) then
                        do ii=1,nevab
                            eload(ii)=fstif(ii,1)*eldis(ii)
                        end do
                    else
                        eload=fstif.x.eldis
                    endif
                    rmid1(ldofs)=rmid1(ldofs)+eload
                end if
                deallocate(eldis,eload)
            end do
        endif
    end do
    !write(7,*)'icaddmass=',icaddmass
    if(icaddmass/=0)then
        do ipoin=1,npoin
            if(icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                rmid1(itotv)=rmid1(itotv)+addmp(idimn,ipoin)*dis(itotv)
            enddo
        enddo
    endif
    end subroutine load_of_mass_base
    !20231215YL


    subroutine load_of_mass(rmid1,dis)

    character(1)field1
    integer(ink) ielem,nevab,ic,ielgroup,ii,ipoin,inode,idimn,itotv
    integer(ink),pointer::ldofs(:)
    real   (irk),allocatable::eldis(:),eload(:)
    real   (irk),pointer::fstif(:,:)
    real   (irk) dis(:)
    real(irk) rmid1(:)
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U') then
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                if (associated(element(ielem)%field(1)%khandmc(2)%fstif)) then
                    fstif=>element(ielem)%field(1)%khandmc(2)%fstif
                    ldofs=>element(ielem)%field(1)%ldofs_f
                    nevab=size(ldofs)
                    allocate(eldis(nevab),eload(nevab))
                    ic=size(fstif,dim=2)
                    eldis = dis(ldofs)
                    if (ic==1) then
                        do ii=1,nevab
                            eload(ii)=fstif(ii,1)*eldis(ii)
                        end do
                    else
                        eload=fstif.x.eldis
                    endif
                    rmid1(ldofs)=rmid1(ldofs)+eload
                end if
                deallocate(eldis,eload)
            end do
        endif
    end do

    do ipoin=1,nmcon
        inode=lmcon(ipoin)
        do idimn=1,ndimn
            itotv=nodfn(idimn,inode)
            if (itotv/=0)then
                rmid1(itotv)=rmid1(itotv)+rmcon(idimn,ipoin)*dis(itotv)
                !             write(chkunit,*)ipoin,inode,itotv,rmcon(ipoin),dis(itotv)
            endif
        end do
    end do
    if (icaddmass/=0)then
        do ipoin=1,npoin
            if(icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                rmid1(itotv)=rmid1(itotv)+addmp(idimn,ipoin)*dis(itotv)
            enddo
        enddo
    endif
    end subroutine load_of_mass

    subroutine load_of_stiff(rmid1,dis) !only for Mode Superposition Method

    character(1)field1                  !zhao 2005/06/23
    integer(ink) ielem,nevab,ielgroup,ii,ipoin,inode,idimn,itotv
    integer(ink),pointer::ldofs(:)
    real   (irk),allocatable::eldis(:),eload(:)
    real   (irk),pointer::fstif(:,:)
    real   (irk) dis(:)
    real(irk) rmid1(:)
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U') then
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                if (associated(element(ielem)%field(1)%khandmc(1)%fstif)) then
                    fstif=>element(ielem)%field(1)%khandmc(1)%fstif
                    ldofs=>element(ielem)%field(1)%ldofs_f
                    nevab=size(ldofs)
                    allocate(eldis(nevab),eload(nevab))
                    eldis = dis(ldofs)
                    eload=fstif.x.eldis
                    rmid1(ldofs)=rmid1(ldofs)+eload
                end if
                deallocate(eldis,eload)
            end do
        endif
    end do

    end subroutine load_of_stiff

    subroutine load_of_addtional_mass(loadmid,dis,deltafp)
    integer(ink) ielem,aelemf,aelems,igroup,jgroup,  &
        idofn,ipea1,ipea2,nnode,itotv
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    real   (irk),allocatable::value(:),rvectorp(:),eload(:),rvector_mid(:)
    real   (irk) loadmid(:),dis(:),deltafp(:)

    allocate(rvectorp(neq),rvector_mid(neq))
    rvectorp=0. ; rvector_mid=0.

    do ielem=1,nifsgroup
        aelemf=tifs(ielem)%aelemf
        aelems=tifs(ielem)%aelems
        ipea1=0
        igroup=element(aelemf)%group
        if(appear(igroup)>0)ipea1=1
        ipea2=1
        if (aelems/=0) then
            jgroup=element(aelems)%group
            if(appear(jgroup)<=0)ipea2=0
        endif
        if (ipea1==1.and.ipea2==1) then
            ldofs=>tifs(ielem)%ldofs
            estif=>tifs(ielem)%estif
            nnode=size(tifs(ielem)%lnods)
            allocate(value(nnode*ndimn),eload(nnode))
            do idofn=1,nnode*ndimn
                value(idofn)=dis(ldofs(idofn))
            end do
            eload=estif(nnode*ndimn+1:nnode*(ndimn+1),1:nnode*ndimn).x.value
            loadmid(ldofs(nnode*ndimn+1:nnode*(ndimn+1)))=   &
                loadmid(ldofs(nnode*ndimn+1:nnode*(ndimn+1)))+eload
            deallocate(value,eload)
            nullify(ldofs,estif)
        endif
    end do

    rvectorp=0.0
    do itotv=1,ntotv
        if(totveq(itotv)/=0.and.totveq(itotv).gt.neq_layer1) &
            rvectorp(totveq(itotv))=rvectorp(totveq(itotv))+loadmid(itotv)
    end do

    if (type_solver=='PROFILE')THEN
        call sksols_layer(global_stiff1,rvectorp,iseq,2)
    ELSEIF(type_solver=='PARDISO')THEN
        rvector_mid=rvector
        rvector=rvectorp
        operation='SOLVE'
        call solve
        rvectorp=rvector
        rvector=rvector_mid
        !STOP 'type_solver=PROFILE'
    ENDIF
    deltafp=0.
    do itotv=1,ntotv
        if(iffix(itotv)==0.and.totveq(itotv)/=0) &
            deltafp(itotv)=rvectorp(totveq(itotv))
    end do

    loadmid=0.
    do ielem=1,nifsgroup

        aelemf=tifs(ielem)%aelemf
        aelems=tifs(ielem)%aelems
        ipea1=0
        igroup=element(aelemf)%group
        if(appear(igroup)>0)ipea1=1
        ipea2=1
        if (aelems/=0) then
            jgroup=element(aelems)%group
            if(appear(jgroup)<=0)ipea2=0
        endif
        if (ipea1==1.and.ipea2==1) then
            ldofs=>tifs(ielem)%ldofs
            estif=>tifs(ielem)%estif
            nnode=size(tifs(ielem)%lnods)
            allocate(value(nnode),eload(nnode*ndimn))
            do idofn=1,nnode
                value(idofn)=deltafp(ldofs(nnode*ndimn+idofn))
            end do
            eload=estif(1:nnode*ndimn,nnode*ndimn+1:nnode*(ndimn+1)).x.value
            loadmid(ldofs(1:nnode*ndimn))=loadmid(ldofs(1:nnode*ndimn))+eload
            deallocate(value,eload)
            nullify(ldofs,estif)
        endif
    end do

    deallocate(rvectorp,rvector_mid)
10  format(10e15.3)

    end subroutine load_of_addtional_mass

    !response_spectrum

    SUBROUTINE PREDICT

    integer(ink) ordert,idofn,ipoin,itotv,idimn,jdofn
    real   (irk) accmid
    integer(ink) igroup,ielem,ielgroup,index,igapb,jdimn !simo_rifai
    character(1 )field1  !simo_rifai
    character(10)special !simo_rifa
    real(irk),allocatable::disl(:)

    !! the following is for the predicted value

    write(7,*) 'in predict'
    do idofn=1,cdofn

        jdofn=lcdofn(idofn)               !20200226
        if(jdofn==10.and.outintr/=0)cycle !20200226

        ordert=order_time_mdofn(lcdofn(idofn))


        do ipoin=1,npoin
            itotv=nodfn(idofn,ipoin)
            ! if(ipoin==168) &
            !print *,'ipoin=',ipoin,'idofn=',idofn,'itov=',itotv,'iffix=',iffix(itotv)
            if(itotv==0)cycle
            !  if(itotv/=0.and.iffix(itotv)==0)then  !!  y1
            if (itotv/=0.and.(iffix(itotv)==0.or.iffix(itotv)==4.or.iffix(itotv)==5.or.trans(itotv)%nintf/=0))then  !!  y1
                if(ordert==1)then
                    result_zero(itotv)=result_zero(itotv)+   &
                        ditime*result_first(itotv)
                    deltafi(itotv)=ditime*result_first(itotv)
                elseif(ordert==2) then
                    deltafi(itotv)=ditime*result_first(itotv)              &
                        +.5*ditime**2*result_second(itotv)
                    result_zero(itotv)=result_zero(itotv)+   &
                        ditime*result_first(itotv)+       &
                        .5*ditime**2*result_second(itotv)
                    result_first(itotv)=result_first(itotv)+ditime*result_second(itotv)
                    !if(iffix(itotv)==4)then
                    !write(7,*)'itotv=',itotv,'delta=',deltafi(itotv),'dis=',result_zero(itotv),'vec=',result_first(itotv),'acc=',result_second(itotv)
                    !endif


                endif

            else if(itotv/=0.and.(iffix(itotv)/=0.and.trans(itotv)%nintf==0))then !!! 07/04/16



                if(nbackdT==2.and.iffix(itotv)==1.and.ordert==1)then !20230216
                    result_zero(itotv)=result_zero(itotv)+result_first(itotv)*ditime
                    !write(7,*)'itotv=',itotv,'result_zero(itotv)=',result_zero(itotv),'result_first(itotv)=',result_first(itotv)

                endif


                if(nbackdT/=2.and.submodel<=0)then !20230216
                    if(iffix(itotv)==1) then ! displacement fixed

                        deltafi(itotv)=fixed(itotv)-result_zero(itotv)
                        !write(7,*)'itotv=',itotv,'fixed(itotv)=',fixed(itotv),'result_zero(itotv)=',result_zero(itotv)
                        if(ordert==1) then	 !x1
                            result_first(itotv)=(fixed(itotv)-result_zero(itotv))/ditime
                        else if(ordert==2) then
                            accmid=fixed(itotv)-(result_zero(itotv)+              &
                                ditime*result_first(itotv)+       &
                                .5*ditime**2*result_second(itotv))
                            accmid=accmid/(beeta2*ditime**2)
                            result_first(itotv)=result_first(itotv)+ditime*result_second(itotv) &
                                +beeta1*ditime*accmid
                            result_second(itotv)=result_second(itotv)+accmid
                        endif	 ! end x1
                        result_zero(itotv)=fixed(itotv)

                        !write(7,*)'itotv=',itotv,'result_zero(itotv)=',result_zero(itotv),'result_first(itotv)=',result_first(itotv)


                    else if(iffix(itotv)==2) then ! velocity fixed
                        if(ordert==1) then
                            deltafi(itotv)=ditime*(result_first(itotv)*(1-theta1)+theta1*fixed(itotv))
                        else if(ordert==2) then
                            accmid=fixed(itotv)-result_first(itotv)-ditime*result_second(itotv)
                            accmid=accmid/(beeta1*ditime)
                            deltafi(itotv)=ditime*result_first(itotv)+       &
                                ditime**2*(.5*result_second(itotv)+beeta2*accmid)
                            result_second(itotv)=result_second(itotv)+accmid
                        endif
                        result_zero(itotv)=result_zero(itotv)+deltafi(itotv)
                        result_first(itotv)=fixed(itotv)
                    else	if(iffix(itotv)==3) then					  !acceleration fixed
                        accmid=fixed(itotv)-result_second(itotv)
                        deltafi(itotv)=ditime*result_first(itotv)+       &
                            ditime**2*(.5*result_second(itotv)+beeta2*accmid)
                        result_zero(itotv)=result_zero(itotv)+deltafi(itotv)
                        result_first(itotv)=result_first(itotv)+ditime*result_second(itotv) &
                            +beeta1*ditime*accmid
                        result_second(itotv)=fixed(itotv)
                    endif
                endif  !20210324
            endif		 !end y1
        end do

    enddo

    delitfi=deltafi

    if(type_problem=='F'.and.ngapb/=0)then !!20121001
        do igapb=1,ngapb
            if(gapb(igapb)%nrdof==0)cycle
            gapb(igapb)%rdisp_zero=gapb(igapb)%rdisp_zero+ditime*gapb(igapb)%rdisp_first+       &
                .5*ditime**2*gapb(igapb)%rdisp_second
            gapb(igapb)%rdisp_delitfi=ditime*gapb(igapb)%rdisp_first+       &
                .5*ditime**2*gapb(igapb)%rdisp_second
            gapb(igapb)%rdisp_deltafi=gapb(igapb)%rdisp_delitfi
            gapb(igapb)%rdisp_first=gapb(igapb)%rdisp_first+.5*ditime*gapb(igapb)%rdisp_second
            !
            !
            !allocate(disl(gapb(igapb)%nrdof)) !20171130
            !disl=ditime*gapb(igapb)%rdisp_first+.5*ditime**2*gapb(igapb)%rdisp_second !此处为刚体转动加速度增量
            !   call dis_modify(igapb,disl)
            !disl=.5*ditime*gapb(igapb)%rdisp_second
            !   call vel_modify(igapb,disl)
            !   deallocate(disl) !20171130
            !

        end do   !igapb
    endif  !!20121001




    !! Simo rifai
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        special= group(igroup)%special
        index = group(igroup)%index
        if (appear(igroup)>0.and.field1=='U')then
            if ((index==5.or.index==9.or.index==16.or.index==18).and.special(1:1)=='B')then
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (order_time_mdofn(1)==1)  then
                        element(ielem)%alfa=ditime*element(ielem)%alfa_first
                    elseif(order_time_mdofn(1)==2)  then
                        element(ielem)%alfa=ditime*element(ielem)%alfa_first
                        element(ielem)%alfa=ditime*element(ielem)%alfa_first+    &
                            .5*ditime*ditime*element(ielem)%alfa_second
                    endif
                end do
            endif
        endif
    end do
    !!simo rifai
    END  SUBROUTINE PREDICT

    SUBROUTINE varupdate
    integer(ink) idofn,ordert,ipoin,itotv,igapb,idimn,jdimn,i1,i2,ipoin1,ipoin2,igaps,ipairs,npairs
    integer(ink) igroup,ielem,ielgroup,index,ic,jdofn  !simo_rifai
    real(irk) xxac
    real(irk),allocatable::disl(:)
    character(5 )fieldid  !simo_rifai
    character(10)special  !simo_rifai

    ic=0
    if(type_load=='LOAD2'.and.idiv==2)ic=1
    if(type_load/='LOAD2')ic=1
    !write(7,*)'ipoin,idofn,itotv,result_zero(itotv)'
    !write(7,*)'iffix(nodfn(1:3,25))=',iffix(nodfn(1:3,25))
    !write(7,*)'result_zero(iffix(nodfn(1:3,25)))1=',result_zero(iffix(nodfn(1:3,25)))
    delitfi=0.
    if(block_stab>=1.and.ebody/=1) goto 10
    !allocate(disl(ndimn))
    do idofn=1,cdofn
        jdofn=lcdofn(idofn)               !20200226
        if(jdofn==10.and.outintr/=0)cycle !20200226
        ordert=order_time_mdofn(lcdofn(idofn))
        do ipoin=1,npoin
            itotv=nodfn(idofn,ipoin)
            if(itotv==0)cycle
            if (itotv/=0.and.(iffix(itotv)==0.or.trans(itotv)%nintf/=0))then
                !if (itotv/=0.and.iffix(itotv)==0)then
                if (ordert==0) then      !! for ordert


                    if(ic==1)&
                        result_zero(itotv)=result_zero(itotv)+result(itotv)
                    delitfi(itotv)    =result(itotv)
                    !write(7,*)'ipoin=',ipoin,'idofn=',idofn,'result=',result(itotv)
                elseif(ordert==1) then
                    if(ic==1)then
                        result_zero(itotv)=result_zero(itotv)+theta1*ditime*result(itotv)
                        result_first(itotv)=result_first(itotv)+result(itotv)
                        if(type_problem=='F'.and.lcdofn(idofn)==8)then   !20220721
                            result_second(itotv)=result_second(itotv)+result(itotv)/ditime
                        endif
                    endif
                    delitfi(itotv)    =theta1*ditime*result(itotv)
                    !write(7,20)ipoin,idofn,itotv,result_zero(itotv)

                elseif(ordert==2)then
                    if(ic==1)then
                        result_zero(itotv)=result_zero(itotv)+beeta2*ditime**2*result(itotv)
                        result_first(itotv)=result_first(itotv)+beeta1*ditime*result(itotv)
                        result_second(itotv)=result_second(itotv)+result(itotv)
                    endif
                    delitfi(itotv)=beeta2*ditime**2*result(itotv)
                    !write(7,20)ipoin,idofn,itotv,result_zero(itotv)


                endif !! for ordert

                ! if(idofn<=ndimn.or.idofn==7)deltafi(itotv)=deltafi(itotv)+delitfi(itotv)
                if(idofn<=7)&   !20220607
                    deltafi(itotv)=deltafi(itotv)+delitfi(itotv)
                !write(7,*)'itotv=',itotv,'deltafi0=',deltafi(itotv),'delitfi(itotv)=',delitfi(itotv)

            endif
        enddo     !! for ipoin
    end do     !! for idofn
20  format(3I10,e15.6)

    !deallocate(disl)
10  continue
    !write(7,*)'ngapb=',ngapb
    !write(7,*)'result_zero(iffix(nodfn(1:3,25)))2=',result_zero(iffix(nodfn(1:3,25)))

    if(ngapb/=0)then
        do igapb=1,ngapb
            if(gapb(igapb)%nrdof==0)cycle   !20231026
            allocate(disl(gapb(igapb)%nrdof))

            disl=gapb(igapb)%rdisp_inc !此处为刚体转动加速度增量
            write(7,*)'igapb=',igapb,'disl=',disl
            if(type_problem=='Q')then !!20121001
                gapb(igapb)%rdisp_delitfi=disl
                if(ic==1) &
                    gapb(igapb)%rdisp_zero=gapb(igapb)%rdisp_zero+disl
                gapb(igapb)%rdisp_deltafi=gapb(igapb)%rdisp_deltafi+disl
                !write(7,*)'before_dis_modify*****'
                call dis_modify(igapb,disl)
                write(7,*)'disl=',disl,'rdisp_zero=',gapb(igapb)%rdisp_zero
                write(7,*)'ext_force=',gapb(igapb)%ext_force
                write(7,*)'constrained stiffness='
                do idimn=1,3*(ndimn-1)
                    if(abs(gapb(igapb)%rdisp_zero(idimn))>1.e-20) &
                        write(7,30)idimn,gapb(igapb)%ext_force(idimn)/gapb(igapb)%rdisp_zero(idimn)
                end do
30              format(i10,e15.6)

            elseif(type_problem=='F')then !!20121001

                !write(7,*)'igapb=',igapb,'ic=',ic
                if(ic==1) &
                    gapb(igapb)%rdisp_zero=gapb(igapb)%rdisp_zero+beeta2*ditime**2*disl
                gapb(igapb)%rdisp_delitfi=beeta2*ditime**2*disl
                gapb(igapb)%rdisp_deltafi=gapb(igapb)%rdisp_deltafi+beeta2*ditime**2*disl
                call dis_modify(igapb,beeta2*ditime**2*disl)
                if(ic==1)then
                    gapb(igapb)%rdisp_first=gapb(igapb)%rdisp_first+beeta1*ditime*disl
                    call vel_modify(igapb,beeta1*ditime*disl)
                    gapb(igapb)%rdisp_second=gapb(igapb)%rdisp_second+disl
                    call acc_modify(igapb,disl)
                endif
                !call acc_check(igapb, gapb(igapb)%rdisp_second,acccheck)
            endif  !!20121001
            deallocate(disl)
        end do   !igapb
    end if

    !write(7,*)'result_zero(iffix(nodfn(1:3,25)))3=',result_zero(iffix(nodfn(1:3,25)))

    !deallocate(acccheck)

    !! Simo rifai
    if(ic==1)then
        DO igroup =1,ngroup
            fieldid= group(igroup)%fieldid
            special= group(igroup)%special
            index = group(igroup)%index
            if (appear(igroup)>0.and.fieldid(1:1)=='U')then
                if ((index==5.or.index==9.or.index==16.or.index==18).and.special(1:1)=='B')then
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        call updalfa(ielem,fieldid)
                        if (order_time_mdofn(1)==0)  then
                            element(ielem)%alfa=element(ielem)%alfa+element(ielem)%alfa_it
                        elseif(order_time_mdofn(1)==1)  then
                            element(ielem)%alfa=element(ielem)%alfa+theta1*ditime*element(ielem)%alfa_it
                            element(ielem)%alfa_first=element(ielem)%alfa_first+element(ielem)%alfa_it
                        elseif(order_time_mdofn(1)==2)  then
                            element(ielem)%alfa=element(ielem)%alfa+beeta2*ditime*ditime*element(ielem)%alfa_it
                            element(ielem)%alfa_first=element(ielem)%alfa_first+beeta1*ditime*element(ielem)%alfa_it
                            element(ielem)%alfa_second=element(ielem)%alfa_second+element(ielem)%alfa_it
                        endif
                    end do
                endif
            endif
        end do
    endif

    END SUBROUTINE varupdate

    !20231215YL
    SUBROUTINE relative_dis_watertight   !20231007 止水
    character (10) model,field1,material
    integer(ink) ielem,nnode,nevab,ngaus,nnode_half,inode,idofn,ielgroup,igroup,idimn,index
    integer(ink),allocatable:: lnods(:),ldofs(:)
    real   (irk),allocatable:: eldis(:),rot(:,:),shapecg(:,:),relat_dis_nod(:,:),nordis(:,:),relat_dis_gaus(:,:)

    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if(appear(igroup)>0.and.field1=='U')then
            matno = group(igroup)%matno
            material=props(matno)%mechanical%solid%material

            index    =group(igroup)%index
            nnode    =elkn(index)%el_field(1)%nnode_f

            if(material/='GOODMAN') cycle
            model=props(matno)%mechanical%solid%Goodman%model
            if(model/='WATERTIGHT') cycle
            jndex=1
            if(ndimn==3)jndex=5
            order_int=elkn(jndex)%el_field(1)%order_intrules(1)
            ngaus=elkn(jndex)%ggaus(order_int)%ngaus
            nevab=nnode*ndimn

            allocate(lnods(nnode),ldofs(nevab),eldis(nevab),nordis(ndimn,nnode),rot(ndimn,ndimn))
            nnode_half=nnode/2
            allocate(shapecg(nnode_half,ngaus),relat_dis_gaus(ndimn,ngaus),relat_dis_nod(ndimn,nnode))

            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                lnods = element(ielem)%field(1)%lnods_f
                ldofs = element(ielem)%field(1)%ldofs_f
                eldis = deltafi(ldofs)

                rot=element(ielem)%rotation

                do inode=1,nnode
                    idofn=(inode-1)*ndimn
                    nordis(:,inode)=rot.x.eldis(idofn+1:idofn+ndimn)
                end do

                if(ndimn==3) then
                    do inode=1,nnode_half
                        relat_dis_nod(:,inode)=nordis(:,inode+nnode_half)-nordis(:,inode)
                        relat_dis_nod(:,inode+nnode_half)=relat_dis_nod(:,inode)
                    end do
                else  ! 2D
                    relat_dis_nod(:,1)=nordis(:,4)-nordis(:,1)
                    relat_dis_nod(:,4)=relat_dis_nod(:,1)
                    relat_dis_nod(:,2)=nordis(:,3)-nordis(:,2)
                    relat_dis_nod(:,3)=relat_dis_nod(:,2)
                endif
                element(ielem)%field(1)%relat_dis_nod=element(ielem)%field(1)%relat_dis_nod0  &
                    +relat_dis_nod

                shapecg = elkn(jndex)%ggaus(order_int)%shape(:,:)
                do idimn=1,ndimn
                    relat_dis_gaus(idimn,:)=transpose(shapecg).x.relat_dis_nod(idimn,:)
                end do

                element(ielem)%field(1)%relat_dis_gaus=element(ielem)%field(1)%relat_dis_gaus0  &
                    +relat_dis_gaus

            end do !ielgroup

            deallocate(lnods,ldofs,eldis,nordis,rot,shapecg,relat_dis_nod,relat_dis_gaus)
        endif
    end do !igroup

    END SUBROUTINE relative_dis_watertight

    !20231215YL

    SUBROUTINE construction_dis_modify
    character(1)field1
    integer(ink) igroup,ielgroup,ielem,idofn
    integer(ink),pointer::lnods(:)
    integer(ink),allocatable::icd(:)
    real   (irk) zz,hh,coef

    allocate(icd(npoin))
    icd=0

    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if(field1/='U')cycle
        if (appear_process(igroup,iblks-1)==0.and.appear_process(igroup,iblks)/=0)then
            do ielgroup =1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                lnods=>element(ielem)%field(1)%lnods_f
                icd(lnods)=1
                nullify(lnods)
            end do
        end if
    end do


    do igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if(field1/='U')cycle
        if (appear_process(igroup,iblks-1)/=0.and.appear_process(igroup,iblks)/=0)then
            DO ielgroup =1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                lnods=>element(ielem)%field(1)%lnods_f
                icd(lnods)=0
                nullify(lnods)
            end do
        end if
    end do

    if(iblks>1) then
        hh= hdam(iblks)-hdam(iblks-1)
    else
        hh= hdam(iblks)
    endif

    !if(iblks==12)write(7,*)'hh=',hh
    do ipoin=1,npoin
        if(icd(ipoin)==0)cycle
        zz=hdam(iblks)-coord(ndimn,ipoin)
        if(zz<0.)zz=0.
        coef=2.*zz/(hh+zz)
        !if(iblks==12)then
        !   write(7,*)'ipoin=',ipoin,'coef=',coef
        !endif
        do idofn=1,cdofn
            itotv=nodfn(idofn,ipoin)
            if(itotv==0)cycle
            result_zero(itotv)=result_zero(itotv)*coef
        enddo
    end do

    deallocate(icd)
    end SUBROUTINE construction_dis_modify





    SUBROUTINE acc_modify(igapb,disl1)
    integer(ink) igapb,ipoin,jpoin,idimn,jdimn,itotv,kdimn
    real   (irk) xxac,disl1(:)
    if(gapb(igapb)%nrdof==0)return
    kdimn=ndimn
    if(block_stab==1)kdimn=3*(ndimn-1)
    do jpoin=1,gapb(igapb)%npblock
        ipoin=gapb(igapb)%nodeblock(jpoin)
        do idimn=1,kdimn  !idimn
            itotv=nodfn(idimn,ipoin)
            if(itotv==0)cycle
            xxac=0.
            do jdimn=1,gapb(igapb)%nrdof
                xxac=xxac+disl1(jdimn)*gapb(igapb)%npdisp(idimn,jpoin,jdimn)
            end do
            result_second(itotv)=result_second(itotv)+xxac
        end do   !idimn
    end do   !jpoin
    end SUBROUTINE acc_modify

    SUBROUTINE acc_check(igapb,disl1,acccheck)
    integer(ink) igapb,ipoin,jpoin,idimn,jdimn,itotv
    real   (irk) xxac,disl1(:),acccheck(:)

    if(gapb(igapb)%nrdof==0)return
    do jpoin=1,gapb(igapb)%npblock
        ipoin=gapb(igapb)%nodeblock(jpoin)
        do idimn=1,ndimn  !idimn
            itotv=nodfn(idimn,ipoin)
            if(itotv==0)cycle
            xxac=0.
            do jdimn=1,gapb(igapb)%nrdof
                xxac=xxac+disl1(jdimn)*gapb(igapb)%npdisp(idimn,jpoin,jdimn)
            end do
            acccheck(itotv)=acccheck(itotv)+xxac
        end do   !idimn
    end do   !jpoin
    end SUBROUTINE acc_check


    SUBROUTINE acc_rigid
    integer(ink) igapb,ipoin,jpoin,idimn,jdimn,itotv,kdimn
    real   (irk) xxac
    real   (irk), allocatable::disl(:)
    !write(7,*)'igapb=',igapb
    kdimn=ndimn
    if(block_stab==1)kdimn=3*(ndimn-1)
    do igapb=1,ngapb
        if(gapb(igapb)%nrdof==0)cycle

        allocate(disl(gapb(igapb)%nrdof))
        disl=gapb(igapb)%rdisp_second
        !   disl=100.
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            do idimn=1,kdimn  !idimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxac=0.
                do jdimn=1,gapb(igapb)%nrdof
                    xxac=xxac+disl(jdimn)*gapb(igapb)%npdisp(idimn,jpoin,jdimn)
                end do
                !   write(7,*)'itotv=',itotv,'acc=',xxac
                result_second(itotv)=xxac
            end do   !idimn
        end do   !jpoin
        deallocate(disl)
    end do
    end SUBROUTINE acc_rigid


    SUBROUTINE vel_modify(igapb,disl1)
    integer(ink) igapb,ipoin,jpoin,idimn,jdimn,itotv,kdimn
    real   (irk) xxac,disl1(:)

    kdimn=ndimn
    if(block_stab==1)kdimn=3*(ndimn-1)
    if(gapb(igapb)%nrdof==0)return
    do jpoin=1,gapb(igapb)%npblock
        ipoin=gapb(igapb)%nodeblock(jpoin)
        do idimn=1,kdimn  !idimn
            itotv=nodfn(idimn,ipoin)
            if(itotv==0)cycle
            xxac=0.
            do jdimn=1,gapb(igapb)%nrdof
                xxac=xxac+disl1(jdimn)*gapb(igapb)%npdisp(idimn,jpoin,jdimn)
            end do
            result_first(itotv)=result_first(itotv)+xxac
        end do   !idimn
    end do   !jpoin
    end SUBROUTINE vel_modify


    SUBROUTINE dis_modify(igapb,disl1)
    integer(ink) igapb,ipoin,jpoin,idimn,jdimn,itotv,kdimn
    real   (irk) xxac,disl1(:)

    kdimn=ndimn
    if(block_stab==1)kdimn=3*(ndimn-1)
    if(gapb(igapb)%nrdof==0)return
    !write(7,*)'igapb=',igapb,'disl1=',disl1,'gapb(igapb)%npblock=',gapb(igapb)%npblock
    do jpoin=1,gapb(igapb)%npblock
        ipoin=gapb(igapb)%nodeblock(jpoin)
        do idimn=1,kdimn  !idimn
            itotv=nodfn(idimn,ipoin)
            if(itotv==0)cycle
            xxac=0.
            do jdimn=1,gapb(igapb)%nrdof
                xxac=xxac+disl1(jdimn)*gapb(igapb)%npdisp(idimn,jpoin,jdimn)
            end do
            !if (iffix(itotv)==0.or.iffix(itotv)==4)then
            delitfi(itotv)=delitfi(itotv)+xxac
            deltafi(itotv)=deltafi(itotv)+xxac
            result_zero(itotv)=result_zero(itotv)+xxac
            if(nbackf/=0)result_zero_g(itotv)=result_zero_g(itotv)+xxac
            !if(itotv>=100.and.itotv<=120) &
            !write(7,*)'itotv=',itotv,'delitfi=',delitfi(itotv),'deltafi=',deltafi(itotv),'result_zero=',result_zero(itotv)
            !else
            !write(7,*)'ipoin=',ipoin,'idimn=',idimn,'itotv=',itotv,'iffix=',iffix(itotv),'xxac=',xxac,'result_zero(itotv)=',result_zero(itotv)
            !endif

        end do   !idimn
    end do   !jpoin
    end SUBROUTINE dis_modify

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    SUBROUTINE varupdate_w !freq2006

    integer(ink) idofn,ordert,ipoin,itotv

    !delitfi=0.
    do idofn=1,cdofn
        do ipoin=1,npoin
            itotv=nodfn(idofn,ipoin)
            if (itotv/=0.and.iffix(itotv)==0)then
                result_zero(itotv)=abs(resultw(itotv))*ttime**2
            elseif(itotv/=0.and.iffix(itotv)/=0)then
                result_zero(itotv)=fixed(itotv)*ttime**2
                resultw(itotv)=fixed(itotv)
            endif
            !        if (itotv/=0)then
            !           delitfi(itotv)=result_zero(itotv)
            !           if(idofn<=7)deltafi(itotv)=deltafi(itotv)+delitfi(itotv)
            !        endif
        enddo     !! for ipoin
    end do     !! for idofn

    END SUBROUTINE varupdate_w

    !!simo_rifai
    subroutine updalfa(ielem,fieldid)
    !
    character(5) fieldid
    integer(ink) ielem,nevab,aevab,np
    integer(ink), pointer::ldofsp(:),ldofs(:)
    real   (irk), pointer::rh(:),estift(:,:),estifhi(:,:), qmatxa(:,:)
    real   (irk), allocatable::eldis(:),rh0(:,:),alfa0(:,:),rh1(:),elpw(:)

    ldofs => element(ielem)%field(1)%ldofs_f
    nevab=size(ldofs)
    aevab=size(element(ielem)%rh)
    if (fieldid(1:2)=='UW') then
        ldofsp => element(ielem)%field(2)%ldofs_f
        np = size(ldofsp)
        allocate(elpw(np))
        elpw  = delitfi(ldofsp)
    endif
    allocate(eldis(nevab))
    rh     =>element(ielem)%rh
    eldis = delitfi(ldofs )

    estift =>element(ielem)%estift
    estifhi=>element(ielem)%estifh
    allocate(rh0(aevab,1),alfa0(aevab,1),rh1(aevab))
    rh1=estift.x.eldis

    if(fieldid(1:2)=='UW') then
        qmatxa => element(ielem)%qmatxa
        rh1 = rh1 - ( qmatxa.x.elpw )
    endif

    rh0(:,1)=-rh-rh1

    call householder(estifhi,rh0,alfa0) !3
    !
    element(ielem)%alfa_it=alfa0(:,1)

    nullify(rh,ldofs,estift,estifhi)
    deallocate(alfa0,rh0,rh1,eldis)

    if (fieldid(1:2)=='UW') then
        nullify(ldofsp)
        deallocate(elpw)
    endif

    end  subroutine updalfa
    !!simo_rifai

    SUBROUTINE gpvarupdate

    character(10) fieldid,class,name,material,model
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index,icr,icreep  !20180630
    DO igroup =1,ngroup   ! --1
        if (appear(igroup)>0) then
            ! get information from the group level
            fieldid=group(igroup)%fieldid
            class  =group(igroup)%class
            !         if (fieldid(1:1)=='U'.and.class=='CO')then
            if (fieldid(1:1)=='U')then !--2
                matno = group(igroup)%matno
                index = group(igroup)%index
                name  =props(matno)%name
                material=props(matno)%mechanical%solid%material
                if(material=='GOODMAN') &
                    model=props(matno)%mechanical%solid%Goodman%model


                icreep =props(matno)%mechanical%solid%icreep  !20180630
                icr=0
                if(material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(ice0(ielem)==1) goto 100
                    element(ielem)%field(1)%gpvar0=element(ielem)%field(1)%gpvar
                    if(index/=20.and.index/=21)  &   !20211125
                        element(ielem)%field(1)%sigz=element(ielem)%field(1)%gpvar(ndimn,:) !ep2010
                    if(icr==2.or.icr==3.or.icr==5.or.icr==6)  & !zhao09
                        element(ielem)%field(1)%strain0=element(ielem)%field(1)%strain

                    if(material=='GOODMAN'.and.model=='FCM')  & !20210126
                        element(ielem)%field(1)%strain0=element(ielem)%field(1)%strain

                    if(icreep==4)  & !20180630
                        element(ielem)%field(1)%vkstrain0=element(ielem)%field(1)%vkstrain

                    !! contact
                    if (name=='CONTACT') then
                        element(ielem)%field(1)%gapg0=element(ielem)%field(1)%gapg
                        element(ielem)%field(1)%gapn0=element(ielem)%field(1)%gapn
                        element(ielem)%field(1)%state0=element(ielem)%field(1)%state
                    elseif(name=='CRACK')then !crack 2006
                        element(ielem)%field(1)%state0=element(ielem)%field(1)%state
                    endif
                    !20231215_YL
                    !!20231007 止水
                    if(material=='GOODMAN') then
                        model=props(matno)%mechanical%solid%Goodman%model
                        if(model=='WATERTIGHT')then
                            element(ielem)%field(1)%relat_dis_nod0 =element(ielem)%field(1)%relat_dis_nod
                            element(ielem)%field(1)%relat_dis_gaus0=element(ielem)%field(1)%relat_dis_gaus
                        endif
                    endif
                    !20231215_YL


                    !!contact
100                 continue
                end do
            endif




            if (fieldid(1:2)=='UW') then !--3

                if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if (ice0(ielem)/=1)then
                            element(ielem)%egaus(order_int)%iload0=element(ielem)%egaus(order_int)%iload
                            element(ielem)%egaus(order_int)%vdval0=element(ielem)%egaus(order_int)%vdval
                        endif
                    end do
                end if
            endif !--3
        endif !--2
    end do !--1

    END  SUBROUTINE gpvarupdate

    !!!!!
    SUBROUTINE gpvarupdate1
    character(10) fieldid,class,name,material
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index,icr
    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            ! get information from the group level
            fieldid=group(igroup)%fieldid
            class  =group(igroup)%class
            !      if(fieldid(1:1)=='U'.and.class=='CO')then
            if (fieldid(1:1)=='U')then
                matno = group(igroup)%matno
                index = group(igroup)%index
                name    =props(matno)%name
                material=props(matno)%mechanical%solid%material
                icr=0
                if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
                DO ielgroup = 1,group1(igroup)%nelgroup
                    ielem = group1(igroup)%list(ielgroup)
                    if (jce1(ielem)/=1)then
                        element1(ielem)%field(1)%gpvar0=element1(ielem)%field(1)%gpvar
                        if (icr==2.or.icr==3.or.icr==5)  & !zhao09
                            element1(ielem)%field(1)%strain0=element1(ielem)%field(1)%strain

                        !! contact
                        if (name=='CONTACT') then
                            element1(ielem)%field(1)%gapg0=element1(ielem)%field(1)%gapg
                            element1(ielem)%field(1)%gapn0=element1(ielem)%field(1)%gapn
                            element1(ielem)%field(1)%state0=element1(ielem)%field(1)%state
                        endif
                        !!contact
                    endif
                end do
            endif


            if (fieldid(1:2)=='UW') then
                if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    DO ielgroup = 1,group1(igroup)%nelgroup
                        ielem = group1(igroup)%list(ielgroup)
                        if (jce1(ielem)==1)then
                            element1(ielem)%egaus(order_int)%iload0=      &
                                element1(ielem)%egaus(order_int)%iload
                            element1(ielem)%egaus(order_int)%vdval0=      &
                                element1(ielem)%egaus(order_int)%vdval
                        endif
                    end do
                endif
            endif

        endif
    end do
    END  SUBROUTINE gpvarupdate1
    !!!!!
    SUBROUTINE gpvarupdate2
    character(10) fieldid,class,name,material
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index,icr
    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            ! get information from the group level
            fieldid=group(igroup)%fieldid
            class  =group(igroup)%class
            !      if(fieldid(1:1)=='U'.and.class=='CO')then
            if (fieldid(1:1)=='U')then
                matno = group(igroup)%matno
                index = group(igroup)%index
                name    =props(matno)%name
                material=props(matno)%mechanical%solid%material
                icr=0
                if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
                DO ielgroup = 1,group2(igroup)%nelgroup
                    ielem = group2(igroup)%list(ielgroup)
                    element2(ielem)%field(1)%gpvar0=element2(ielem)%field(1)%gpvar
                    if (icr==2.or.icr==3.or.icr==5)  & !zhao09
                        element2(ielem)%field(1)%strain0=element2(ielem)%field(1)%strain

                    !! contact
                    if (name=='CONTACT') then
                        element2(ielem)%field(1)%gapg0=element2(ielem)%field(1)%gapg
                        element2(ielem)%field(1)%gapn0=element2(ielem)%field(1)%gapn
                        element2(ielem)%field(1)%state0=element2(ielem)%field(1)%state
                    endif
                    !!contact
                end do
            endif


            if (fieldid(1:2)=='UW') then
                if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    DO ielgroup = 1,group2(igroup)%nelgroup
                        ielem = group2(igroup)%list(ielgroup)
                        element2(ielem)%egaus(order_int)%iload0=      &
                            element2(ielem)%egaus(order_int)%iload
                        element2(ielem)%egaus(order_int)%vdval0=      &
                            element2(ielem)%egaus(order_int)%vdval
                    end do
                endif
            endif

        endif
    end do
    END  SUBROUTINE gpvarupdate2
    !!!!!
    SUBROUTINE gpvar_initial
    character(10) fieldid,class,name,material
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index
    DO igroup =1,ngroup
        !if (appear(igroup)==-1) then
        ! get information from the group level
        fieldid=group(igroup)%fieldid
        class  =group(igroup)%class
        !      if(fieldid(1:1)=='U'.and.class=='CO')then
        if (fieldid(1:1)=='U')then
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                element(ielem)%field(1)%gpvar0=0.0
                element(ielem)%field(1)%gpvar =0.0
                element(ielem)%stres0=0.
                if (associated(element(ielem)%field(1)%strain0)) &
                    element(ielem)%field(1)%strain0=0.
                if (associated(element(ielem)%field(1)%strain )) &
                    element(ielem)%field(1)%strain =0.
            end do
        endif
        if (fieldid(1:2)=='UW') then
            matno = group(igroup)%matno
            index = group(igroup)%index
            material=props(matno)%mechanical%solid%material
            if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    element(ielem)%egaus(order_int)%iload0=0.
                    element(ielem)%egaus(order_int)%vdval0=0.
                    element(ielem)%egaus(order_int)%iload =0.
                    element(ielem)%egaus(order_int)%vdval =0.
                end do
            endif
        endif

        !endif
    end do
    END  SUBROUTINE gpvar_initial


    SUBROUTINE gpvar1_initial
    character(10) fieldid,class,name,material
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index
    DO igroup =1,ngroup
        if (appear(igroup)==-1) then
            ! get information from the group level
            fieldid=group(igroup)%fieldid
            class  =group(igroup)%class
            !      if(fieldid(1:1)=='U'.and.class=='CO')then
            if (fieldid(1:1)=='U')then
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    element(ielem)%field(1)%gpvar0=0.0
                    element(ielem)%field(1)%gpvar =0.0
                    element(ielem)%stres0=0.
                    if (associated(element(ielem)%field(1)%strain0)) &
                        element(ielem)%field(1)%strain0=0.
                    if (associated(element(ielem)%field(1)%strain )) &
                        element(ielem)%field(1)%strain =0.
                end do
            endif
            if (fieldid(1:2)=='UW') then
                matno = group(igroup)%matno
                index = group(igroup)%index
                material=props(matno)%mechanical%solid%material
                if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        element(ielem)%egaus(order_int)%iload0=0.
                        element(ielem)%egaus(order_int)%vdval0=0.
                        element(ielem)%egaus(order_int)%iload =0.
                        element(ielem)%egaus(order_int)%vdval =0.
                    end do
                endif
            endif

        endif
    end do
    END  SUBROUTINE gpvar1_initial

    SUBROUTINE gpvar2_initial
    character(10) fieldid,class,name
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index
    DO igroup =1,ngroup
        if (appear(igroup)==2) then
            ! get information from the group level
            fieldid=group(igroup)%fieldid
            class  =group(igroup)%class
            !      if(fieldid(1:1)=='U'.and.class=='CO')then
            if (fieldid(1:1)=='U')then
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    element(ielem)%field(1)%gpvar0=0.0
                    element(ielem)%field(1)%gpvar =0.0
                    element(ielem)%stres0=0.
                    if (associated(element(ielem)%field(1)%strain0)) &
                        element(ielem)%field(1)%strain0=0.
                    if (associated(element(ielem)%field(1)%strain )) &
                        element(ielem)%field(1)%strain =0.
                end do
            endif
            if (fieldid(1:2)=='UW') then
                matno = group(igroup)%matno
                index = group(igroup)%index
                material=props(matno)%mechanical%solid%material
                if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        element(ielem)%egaus(order_int)%iload0=0.
                        element(ielem)%egaus(order_int)%vdval0=0.
                        element(ielem)%egaus(order_int)%iload =0.
                        element(ielem)%egaus(order_int)%vdval =0.
                    end do
                endif
            endif

        endif
    end do
    END  SUBROUTINE gpvar2_initial




    subroutine modf_element_lib

    character(20)material,field1,special,criteria,name,model
    integer(ink) jgroup,matno,nstre,ngvar,ielgroup,ielem,index,ngaus,ngaus1, &
        order_int, order_int1, order_int2,nevab,aevab,nnode,point2x,point1x, &
        inode,edimn,jndex,ig,idimn,icreep,nr,nrfields,jfield,ifield,icr,point1,point2,ii, &
        kinit_g,uplift_ic,kind_wt,nlinkg  !20221124
    integer(ink),pointer::lnods(:)
    integer(ink),allocatable::ngpoin(:,:)
    real(irk), allocatable::shape(:),cartd(:,:),deriv(:,:),elcod0(:,:),a3(:),a1(:), &
        rxp(:,:),xjaci(:,:),rot(:,:)
    real(irk) djacb,weigp,dis,thickness
    ! define gpvar
    write(7,*)'in modf_element_lib'
    if(type_problem=='WT')then !20220409 用于冰雪冻融
        DO jgroup =1,ngroup
            index = group(jgroup)%index
            ngaus =elkn(index)%ggaus(1)%ngaus
            ngvar=2
            DO ielgroup = 1,group(jgroup)%nelgroup
                ielem = group(jgroup)%list(ielgroup)
                allocate(element(ielem)%field(1)%gpvar(ngvar,ngaus))
            end do
        end do
        return
    endif !20220409

    if(alfa_p4>0)then
        allocate(local_p4(npoin),ngpoin(ngroup,npoin))  !20221124
        local_p4=0 !20221124
        ngpoin=0 !20221124
    endif

    DO jgroup =1,ngroup
        !write(7,*)'jgroup=',jgroup
        field1= group(jgroup)%fieldid
        nrfields= group(jgroup)%nrfields
        special= group(jgroup)%special
        jfield=0
        do ifield=1,nrfields
            if (field1(ifield:ifield)=='T') then
                jfield=ifield
                exit
            endif
        end do

        ! get information from the group level
        index = group(jgroup)%index
        matno = group(jgroup)%matno
        kinit_g=group(jgroup)%kinit_g  !20211214
        write(7,*)'jgroup=',jgroup,'kinit_g=',kinit_g
        name=props(matno)%name
        !uplift_ic=group(jgroup)%uplift_ic  !20220409


        if (field1(1:1)=='U')  then
            thickness  =props(matno)%mechanical%solid%thickness   !2017/04/03
            material=props(matno)%mechanical%solid%material

            !if (index.ne.20.and.index.ne.21) then ! not for beam
            if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006

                icreep =props(matno)%mechanical%solid%icreep

                !print *,'matno=',matno,'icreep=',icreep
                if(icreep.ne.0)nr=props(matno)%mechanical%solid%creep%nr
                if(material=='GOODMAN')then
                    group(jgroup)%nstre=ndimn
                    model=props(matno)%mechanical%solid%Goodman%model
                endif
                nstre=group(jgroup)%nstre
                ngvar=nstre+3 ! 20210125
                if (index==22)then
                    nstre=8 !! for plate element
                    ngvar=nstre
                endif

                if (index==26)then  !20230910
                    nstre=3 !! for thin_film element
                    ngvar=nstre
                endif

                ngaus=elkn(index)%ggaus(1)%ngaus

                !write(7,*)'jgroup=',jgroup,'matno=',matno,'material=',material
                if (material=='PLANE_LOWFT')then
                    allocate(a1(ndimn),a3(ndimn),rxp(ndimn,ndimn))
                    point1=props(matno)%mechanical%solid%Plane_lowft%point(1)
                    point2=props(matno)%mechanical%solid%Plane_lowft%point(2)
                    dis=sum((coord(:,point2)-coord(:,point1))**2)
                    dis=sqrt(dis)
                    a1=(coord(:,point2)-coord(:,point1))/dis
                    lnods=>props(matno)%mechanical%solid%Plane_lowft%point
                    call normal_local(lnods,a3)
                    !write(7,*)'a3=',a3
                    call direct_goodman(a3,rxp,ndimn,a1)
                    !write(7,*)'matno=',matno,'rxp(1,:)=',rxp(1,:),'rxp(2,:)=',rxp(2,:)
                    deallocate(a1,a3)
                    nullify(lnods)
                endif



                if (material=='GOODMAN') then
                    if(ndimn==2)ngaus =elkn(1)%ggaus(1)%ngaus
                    if(ndimn==3)ngaus =elkn(5)%ggaus(1)%ngaus
                    allocate(a1(ndimn))
                    a1=0.
                    if(ndimn==3)then
                        point1=props(matno)%mechanical%solid%Goodman%point1
                        point2=props(matno)%mechanical%solid%Goodman%point2
                        if(point1/=0.and.point2/=0)then  !20211031
                            dis=sum((coord(:,point2)-coord(:,point1))**2)
                            dis=sqrt(dis)
                            a1=(coord(:,point2)-coord(:,point1))/dis
                        endif !20211031
                        !write(7,*)'a1=',a1
                    endif

                endif

                nnode =elkn(index)%nnode
                nevab =nnode*ndimn !20231215YL

                if(material=='CLASSICALEP'.or.material=='CONCRETE')ngvar=nstre+3  !nstre+epstn+dlan+yvalue
                if(material=='DUNCANCHANG')ngvar=nstre+5  !nstre+q+s+et+vt+p3 !for judgement of downloading
                if(material=='DUNCANCHANG'.and.icreep==3)ngvar=nstre+7  !nstre+q+s+et+vt+p3+tevf+tetf !for creep
                if(material=='SandPZ'.or.   &  !20220409
                    material=='ClayPZ'.or.material=='SoilPZ') ngvar=2*nstre+1
                !if(material=='SoilPZ') ngvar=2*nstre+1  !20220629
            else if(index.eq.20.or.index.eq.21) then   ! for beam

                ngvar=6*(ndimn-1)
                ngaus=1
                nstre=ngvar

            elseif(index==25)then !steel 2006

                ngvar=2*ndimn
                ngaus=1
                nstre=ngvar
                ngvar=ngvar+5 !ngvar+1--for gaptao, ngvar+2--for gapnorm ,ngvar+3--for Ks, ngvar+4--for steel strain
                !ngvar+5--for state 0-close 1-open , integer it first! for lhg ngvar+6 ic_yty

            endif ! for beam

            group(jgroup)%ngvar=ngvar
            group(jgroup)%nstre=nstre


            ! loop for 1:nelgroup
            DO ielgroup=1,group(jgroup)%nelgroup
                ielem=group(jgroup)%list(ielgroup)
                element(ielem)%field(1)%ngvar_f=ngvar

                !if(index.eq.20.or.index.eq.21)then   !20200116
                ! if(props(matno)%geometry%ipd==1) &
                !element(ielem)%rotation=props(matno)%geometry%rotlg
                ! endif
                if(Blarge/=0.and.(index==20.or.index==21.or.index==22.or.index==26)) then  !20221102
                    allocate(element(ielem)%point_direct(2))
                    element(ielem)%point_direct=0
                endif !20221102

                if(alfa_p4>0.and.(index==22.or.index==26)) then  !20230910
                    lnods=>element(ielem)%field(1)%lnods_f
                    ngpoin(jgroup,lnods)=1
                    nullify(lnods)
                endif !20221124

                allocate(element(ielem)%field(1)%gpvar0(ngvar,ngaus))  !20210125
                allocate(element(ielem)%field(1)%gpvar(ngvar,ngaus),element(ielem)%field(1)%sigz(ngaus))
                allocate(element(ielem)%field(1)%bmatx(nstre,nevab,ngaus)) !20231215YL 存储单元B矩阵

                !if(material=='DUNCANCHANG'.and.uplift_ic/=0)then !20220409
                !if(material=='DUNCANCHANG')then !20220607
                !allocate(element(ielem)%field(1)%gpvar_s(ngvar,ngaus))
                kind_wt=props(matno)%mechanical%solid%kind_wt
                if(kind_wt/=0)then
                    allocate(element(ielem)%field(1)%stran0_s(nstre,ngaus))
                    element(ielem)%field(1)%stran0_s=0.

                    allocate(element(ielem)%field(1)%isatu(ngaus))
                    element(ielem)%field(1)%isatu=0
                endif

                !endif    !20220409


                if(material=='STEEL_SP') allocate(element(ielem)%field(1)%kdiag(3*(ndimn-1))) !20211125


                element(ielem)%field(1)%gpvar0=0.0
                element(ielem)%field(1)%gpvar=0.0
                element(ielem)%field(1)%sigz=0.
                element(ielem)%field(1)%bmatx=0.0 !20231215YL
                if(material=='STEEL_EP')  element(ielem)%field(1)%ep=0. !20211125
                if(material=='STEEL_SP')  element(ielem)%field(1)%kdiag=0. !20211125

                if(material=='DUNCANCHANG'.and.type_problem=='F'.and.gamamax/=0)then !20231215YL
                    allocate(element(ielem)%field(1)%gamamax(ngaus))
                    allocate(element(ielem)%field(1)%gamamax0(ngaus))
                    allocate(element(ielem)%field(1)%gamamax_ini(ngaus))
                    allocate(element(ielem)%field(1)%gamamax_error(ngaus))
                    element(ielem)%field(1)%gamamax=0
                    element(ielem)%field(1)%gamamax0=0
                    element(ielem)%field(1)%gamamax_ini=0
                    element(ielem)%field(1)%gamamax_error=0
                endif !20231215YL


                if (material=='CONCRETE')then
                    icr=props(matno)%mechanical%solid%Concrete%icr
                    if (icr==1)then
                        allocate(element(ielem)%field(1)%rr(ndimn,ndimn,ngaus))
                        element(ielem)%field(1)%rr=0.
                    endif
                    if (icr==2.or.icr==3.or.icr==5.or.icr==6) then !zhao09
                        allocate(element(ielem)%field(1)%strain0(nstre+2,ngaus),element(ielem)%field(1)%strain(nstre+2,ngaus))
                        element(ielem)%field(1)%strain0=0.;element(ielem)%field(1)%strain=0.
                        if(icr==6)element(ielem)%field(1)%gpvar0(nstre+1,:)=1
                        if(icr==6)element(ielem)%field(1)%gpvar (nstre+1,:)=1
                    endif
                endif

                if ((jfield/=0.and.field1/='WT').or.icreep.ne.0) then   !!20220409

                    allocate(element(ielem)%field(1)%stran0(nstre,ngaus))
                    element(ielem)%field(1)%stran0=0.

                    if(icreep==4)then   !20180630
                        allocate(element(ielem)%field(1)%vkstrain0(nstre,ngaus),element(ielem)%field(1)%vkstrain(nstre,ngaus))
                        element(ielem)%field(1)%vkstrain0=0.;element(ielem)%field(1)%vkstrain=0.
                    endif

                end if

                if (jfield/=0.and.field1/='WT') then   !! !20220409
                    allocate(element(ielem)%field(1)%dsig(nstre,ngaus))
                    element(ielem)%field(1)%dsig =0.0
                endif


                if ((jfield/=0.and.field1/='WT').and.icreep.ne.0) then   !!20220409
                    allocate(element(ielem)%field(1)%omega(nstre,ngaus,nr))
                    element(ielem)%field(1)%omega=0.
                endif


                if (kinit_g==2) then
                    allocate(element(ielem)%stres0(nstre,ngaus))
                    element(ielem)%stres0=0.0
                end if



                if (material=='CLASSICALEP') then
                    criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
                    if (criteria=='MCJOINT')then
                        allocate(element(ielem)%rotation(1,ndimn),  &
                            element(ielem)%field(1)%ntstress(2,ngaus))
                        element(ielem)%field(1)%ntstress=0.
                        lnods=>element(ielem)%field(1)%lnods_f
                        call normal_local(lnods,element(ielem)%rotation(1,:))
                        nullify(lnods)
                    endif
                endif
                if (name=='NORMK'.or.name=='NOLINORMK')then
                    allocate(element(ielem)%rotation(1,ndimn))
                    lnods=>element(ielem)%field(1)%lnods_f
                    call normal_local(lnods,element(ielem)%rotation(1,:))
                    nullify(lnods)
                endif

                if (material=='PLANE_LOWFT')then
                    allocate(element(ielem)%rotation(ndimn,ndimn),element(ielem)%field(1)%dmatxd(nstre,nstre,ngaus))   !20130510
                    element(ielem)%field(1)%dmatxd=0.
                    element(ielem)%rotation=rxp
                endif


                if (material/='CLASSICALEP'.and.material/='GOODMAN'.and.name=='CONTACT')then
                    allocate(element(ielem)%rotation(1,ndimn),  &
                        element(ielem)%field(1)%ntstress(2,ngaus))
                    lnods=>element(ielem)%field(1)%lnods_f
                    call normal_local(lnods,element(ielem)%rotation(1,:))
                    nullify(lnods)
                endif
                ! for PZ model 20220409
                if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                    !if(material=='SoilPZ'.or.material=='SandPZ')then
                    order_int1=elkn(index)%el_field(1)%order_intrules(1)
                    ngaus =elkn(index)%ggaus(order_int1)%ngaus
                    allocate(element(ielem)%egaus(order_int1)%iload(ngaus))
                    allocate(element(ielem)%egaus(order_int1)%iload0(ngaus))
                    allocate(element(ielem)%egaus(order_int1)%vdval(6,ngaus))
                    allocate(element(ielem)%egaus(order_int1)%vdval0(6,ngaus))
                    element(ielem)%egaus(order_int1)%iload=0.0
                    element(ielem)%egaus(order_int1)%iload0=0.0
                    element(ielem)%egaus(order_int1)%vdval=0.0
                    element(ielem)%egaus(order_int1)%vdval0=0.0
                endif
                !end for PZ model	!20220409

                !crack 2006
                if(name=='CRACK')allocate(element(ielem)%field(1)%ntstress(1,ngaus))
                !! contact
                if(index==1.and.material=='ELASTIC_SPRING')               &
                    allocate(element(ielem)%field(1)%state(ngaus))

                if(name=='CONTACT')    &
                    allocate(element(ielem)%field(1)%gapg0(ngaus),         &
                    element(ielem)%field(1)%gapg (ngaus),          &
                    element(ielem)%field(1)%gapn0(nnode),          &
                    element(ielem)%field(1)%gapn (nnode),          &
                    element(ielem)%field(1)%state0(ngaus),         &
                    element(ielem)%field(1)%state(ngaus),          &
                    element(ielem)%field(1)%state1(ngaus),         &  !zhao 05/07/22
                    element(ielem)%field(1)%icftcontact(ngaus),    &
                    element(ielem)%field(1)%natural_thickness(ngaus))
                if(name=='CONTACT')element(ielem)%field(1)%icftcontact=0
                !! end contact

                if (name=='CRACK')then !crack 2006
                    allocate(element(ielem)%field(1)%state(ngaus),element(ielem)%field(1)%state0(ngaus))
                    element(ielem)%field(1)%state='close'
                    element(ielem)%field(1)%state0='close'
                endif
                !! Goodman
                if (material=='GOODMAN') then
                    allocate(element(ielem)%rotation(ndimn,ndimn), &
                        element(ielem)%aera_local(ngaus),a3(ndimn),element(ielem)%evk(ndimn,ngaus))
                    !20231215_YL
                    if(model=='WATERTIGHT')then !20231007 止水
                        jndex=1
                        if(ndimn==3)jndex=5
                        order_int=elkn(jndex)%el_field(1)%order_intrules(1)
                        ngaus=elkn(jndex)%ggaus(order_int)%ngaus

                        allocate(element(ielem)%field(1)%relat_dis_gaus0(ndimn,ngaus),	    	&
                            element(ielem)%field(1)%relat_dis_gaus(ndimn,ngaus),		    &
                            element(ielem)%field(1)%relat_dis_nod0(ndimn,nnode/2),		    &
                            element(ielem)%field(1)%relat_dis_nod(ndimn,nnode/2))
                        element(ielem)%field(1)%relat_dis_gaus0=0.;element(ielem)%field(1)%relat_dis_gaus=0.
                        element(ielem)%field(1)%relat_dis_nod0=0.;element(ielem)%field(1)%relat_dis_nod=0.
                    endif

                    !20231215_YL

                    if(model=='FCM')then
                        element(ielem)%field(1)%gpvar0(nstre+1,:)=1.
                        element(ielem)%field(1)%gpvar(nstre+1,:)=1.
                        do igaus=1,ngaus
                            element(ielem)%evk(:,igaus)=   &
                                props(matno)%mechanical%solid%Goodman%fcmp%kns0
                        end do
                    endif

                    lnods=>element(ielem)%field(1)%lnods_f

                    if(model(1:3)=='FCM') then   !20210125
                        allocate(element(ielem)%field(1)%strain0(ndimn,ngaus),    &
                            element(ielem)%field(1)%strain (ndimn,ngaus))  !20210125
                        element(ielem)%field(1)%strain0=0.
                        element(ielem)%field(1)%strain =0.
                    endif
                    call normal_local(lnods,a3)
                    !call direct(a3,element(ielem)%rotation,ndimn)
                    if(ndimn==3.and.(point1==0.or.point2==0))then  !20211031
                        point2x=lnods(2);point1x=lnods(1)
                        dis=sum((coord(:,point2x)-coord(:,point1x))**2)
                        dis=sqrt(dis)
                        a1=(coord(:,point2x)-coord(:,point1x))/dis
                    endif                !20211031
                    call direct_goodman(a3,element(ielem)%rotation,ndimn,a1)

                    !write(7,*)'jgroup=',jgroup,'ie=',ielem, 'rotation='
                    !do idimn=1,ndimn
                    !write(7,*)element(ielem)%rotation(idimn,:)
                    !end do
                    edimn=ndimn-1
                    !jndex=1  !2017/02/14
                    !if(ndimn==3)jndex=5  !2017/02/14

                    jndex=1
                    if (ndimn==3.and.index==9)jndex=5  !2017/02/14
                    if (ndimn==3.and.index==23)jndex=3  !2017/02/14
                    ngaus1=elkn(jndex)%ggaus(1)%ngaus   !2017/02/14
                    allocate(shape(nnode/2),deriv(edimn,nnode/2),cartd(edimn,nnode/2))
                    allocate(elcod0(edimn,nnode/2),xjaci(edimn,edimn))

                    do inode=1,nnode/2
                        do idimn=1,edimn
                            elcod0(idimn,inode)=element(ielem)%rotation(idimn,:).d.coord(:,lnods(inode))
                        end do
                    end do
                    nullify(lnods)

                    !print *,'ielem=',ielem,'index=',index,'jndex=',jndex,'nnode=',nnode,'ngaus=',ngaus

                    do ig=1,ngaus1
                        !print *,'size(shape)=',size(shape),'size(elkn)=',size(elkn(jndex)%ggaus(1)%shape(:,ig))
                        shape=elkn(jndex)%ggaus(1)%shape(:,ig)
                        deriv=elkn(jndex)%ggaus(1)%deriv(:,:,ig)
                        weigp=elkn(jndex)%ggaus(1)%weigp(ig)
                        call jacob(ielem, edimn, nnode/2,elcod0,deriv,cartd, djacb,xjaci)
                        element(ielem)%aera_local(ig)=djacb*weigp*thickness  !2017/04/03
                    end do
                    !!X,Y,Z ---global axis, x,y,z--local axis
                    !!z is the normal direction of the surface
                    !!    if z/=Y, x=Y*z, y=z*x
                    !!    if z=y,  x=X*z, y=z*x
                    deallocate(deriv,cartd,shape,elcod0,a3,xjaci)
                endif
                !! end of Goodman

                !! for Simo & Rifai element
                if ((index==3.or.index==5.or.index==9.or.index==16.or.index==18).and.special(1:1)=='B')then

                    if (ndimn==2) then
                        nevab=8
                        if(special(2:2)=='A') aevab=2
                        if(special(2:2)=='B') aevab=4
                        if(special(2:2)=='C') aevab=7
                        if(special(2:2)=='D') aevab=11
                        if(index==3)nevab=6
                        if(special(2:2)=='B'.and.index==3) aevab=6
                        if(special(2:2)=='C'.and.index==3) aevab=9
                    else if(ndimn==3) then
                        nevab=24
                        if(special(2:2)=='A') aevab=3
                        if(special(2:2)=='B') aevab=9
                        if(special(2:2)=='C') aevab=24
                        if(special(2:2)=='D') aevab=30
                    endif
                    allocate(element(ielem)%rh(aevab))
                    allocate(element(ielem)%alfa(aevab),element(ielem)%alfa_it(aevab))
                    element(ielem)%alfa=0.
                    element(ielem)%alfa_it=0.
                    if (order_time_mdofn(1)>=1)  then
                        allocate(element(ielem)%alfa_first(aevab))
                        element(ielem)%alfa_first=0.
                    endif
                    if (order_time_mdofn(1)==2)  then
                        allocate(element(ielem)%alfa_second(aevab))
                        element(ielem)%alfa_second=0.
                    endif
                    allocate(element(ielem)%estift(aevab,nevab))
                    allocate(element(ielem)%estifh(aevab,aevab))
                    if(field1(1:2)=='UW')allocate(element(ielem)%qmatxa(aevab,nnode))
                endif
            end do  !ielem
            if(material=='GOODMAN') deallocate(a1)
            if(material=='PLANE_LOWFT')deallocate(rxp)
        endif !for field(1:1)='U'

        !! end for Simo & Rifai element
        !! 11/6/04   ! 单纯渗流场考虑非饱和
        if (field1(1:1)=='W'.and.name(1:6)=='NSSoil') then

            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus=elkn(index)%ggaus(order_int)%ngaus
            DO ielgroup=1,group(jgroup)%nelgroup
                ielem=group(jgroup)%list(ielgroup)
                allocate(element(ielem)%egaus(order_int)%permr(ngaus),  &
                    element(ielem)%egaus(order_int)%csmos(ngaus))
                element(ielem)%egaus(order_int)%permr=1.0
                element(ielem)%egaus(order_int)%csmos=0.
                allocate(element(ielem)%egaus(order_int)%pwatr(ngaus))
                element(ielem)%egaus(order_int)%pwatr=0.
            end do
        endif
        !!
        !!23/2/98
        if (field1(1:2)=='UW'.and.name(1:6)=='NSSoil') then
            order_int=elkn(index)%el_field(2)%order_intrules(1)
            ngaus=elkn(index)%ggaus(order_int)%ngaus
            DO ielgroup=1,group(jgroup)%nelgroup
                ielem=group(jgroup)%list(ielgroup)
                allocate(element(ielem)%egaus(order_int)%permr(ngaus))
                element(ielem)%egaus(order_int)%permr=1.0
                allocate(element(ielem)%egaus(order_int)%pwatr(ngaus),   &
                    element(ielem)%egaus(order_int)%csmos(ngaus),   &
                    element(ielem)%egaus(order_int)%poros(ngaus),   &
                    element(ielem)%egaus(order_int)%satur(ngaus),   &
                    element(ielem)%egaus(order_int)%voide(ngaus))


                order_int1=elkn(index)%el_field(2)%order_intrules(2)  !20220707

                if (order_int1/=order_int)then
                    ngaus =elkn(index)%ggaus(order_int1)%ngaus
                    allocate(element(ielem)%egaus(order_int1)%poros(ngaus),   &
                        element(ielem)%egaus(order_int1)%voide(ngaus),   &
                        element(ielem)%egaus(order_int1)%permr(ngaus),    &
                        element(ielem)%egaus(order_int1)%pwatr(ngaus),   &
                        element(ielem)%egaus(order_int1)%csmos(ngaus),   &
                        element(ielem)%egaus(order_int1)%satur(ngaus))
                endif

                order_int1=elkn(index)%el_field(1)%order_intrules(1)  !20220707
                if (order_int1/=order_int)then
                    ngaus =elkn(index)%ggaus(order_int1)%ngaus
                    allocate(element(ielem)%egaus(order_int1)%poros(ngaus),   &
                        element(ielem)%egaus(order_int1)%satur(ngaus))
                endif


                order_int1=elkn(index)%el_field(1)%order_intrules(2)  !20220707
                if (order_int1/=order_int)then
                    ngaus =elkn(index)%ggaus(order_int1)%ngaus
                    allocate(element(ielem)%egaus(order_int1)%poros(ngaus),   &
                        element(ielem)%egaus(order_int1)%satur(ngaus))
                endif

                order_int1=elkn(index)%couple(1)%intrule_couple(1)
                if (order_int1/=order_int)then
                    ngaus =elkn(index)%ggaus(order_int1)%ngaus
                    allocate(element(ielem)%egaus(order_int1)%satur(ngaus))
                endif

                order_int2=elkn(index)%el_field(1)%order_intrules(1)
                ngaus =elkn(index)%ggaus(order_int2)%ngaus
                if(order_int2/=order_int)then
                    allocate(element(ielem)%egaus(order_int2)%pwatr(ngaus), &
                        element(ielem)%egaus(order_int2)%satur(ngaus))
                endif

                if(material=='SandPZ'.or.material=='ClayPZ'.or.material=='SoilPZ')then
                    allocate(element(ielem)%egaus(order_int2)%iload(ngaus))
                    allocate(element(ielem)%egaus(order_int2)%iload0(ngaus))
                    allocate(element(ielem)%egaus(order_int2)%vdval(6,ngaus))
                    allocate(element(ielem)%egaus(order_int2)%vdval0(6,ngaus))
                endif
            end do !ielem
        endif  !!23/2/98
    end do !jgroup

    !20221124
    if(alfa_p4>0)then
        do ipoin=1,npoin
            if(sum(ngpoin(:,ipoin))/=1)cycle   !20231006 ?
            if(ipp4(ipoin)/=1)cycle
            local_p4(ipoin)=1
            itotv=nodfn(1,ipoin)
            nintf=trans(itotv)%nintf
            if(nintf/=0)local_p4(ipoin)=0
        enddo
        deallocate(ngpoin)
    endif
    !20221124


    end  subroutine modf_element_lib

    subroutine normal_local(lnods,rotation)

    integer(ink) lnods(:)
    integer(ink) index,nnode,edimn,order_int,ngaus,ig,inode,nnode1
    integer(ink),allocatable::lnode(:)
    real   (irk) rotation(:),weigp,aa
    real   (irk),allocatable::elcod(:,:),deriv(:,:),s(:,:),a3(:)
    real   (irk),allocatable::shape(:)
    nnode1=size(lnods)
    index=1
    if(ndimn==3.and.nnode1==8)index=5   !2017/02/14
    if(ndimn==3.and.nnode1==6)index=3   !2017/02/14
    nnode=2
    if(ndimn==3.and.nnode1==8)nnode=4   !2017/02/14
    if(ndimn==3.and.nnode1==6)nnode=3   !2017/02/14
    edimn=ndimn-1
    order_int=elkn(index)%el_field(1)%order_intrules(1)
    ngaus=elkn(index)%ggaus(order_int)%ngaus
    allocate(lnode(nnode),elcod(nnode,ndimn))
    lnode=lnods(1:nnode)
    do inode=1,nnode
        elcod(inode,:)=coord(:,lnode(inode))
    end do
    allocate(shape(nnode),deriv(edimn,nnode))
    allocate(s(ndimn,ndimn),a3(ndimn))
    rotation=0.
    do ig=1,ngaus
        shape=elkn(index)%ggaus(order_int)%shape(:,ig)
        deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
        weigp=elkn(index)%ggaus(order_int)%weigp(ig)
        s(1:edimn,:)=MATMUL(deriv,elcod)
        if((edimn+1).eq.3) then
            s(3,1)=s(1,2)*s(2,3)-s(2,2)*s(1,3)
            s(3,2)=s(1,3)*s(2,1)-s(1,1)*s(2,3)
            s(3,3)=s(1,1)*s(2,2)-s(1,2)*s(2,1)
        else
            s(2,1)=-s(1,2)
            s(2,2)=s(1,1)
        endif
        a3=s(edimn+1,:)**2
        aa=sqrt(sum(a3))
        s(edimn+1,:)=s(edimn+1,:)/aa
        a3=s(edimn+1,:)
        rotation=rotation+a3
    end do
    rotation=rotation/ngaus
    rotation=rotation/sqrt(sum(rotation**2)) !p42010
    deallocate(lnode,elcod,shape,deriv,s,a3)

    end subroutine normal_local

    SUBROUTINE modf_var_prescribed

    character(80) text,type_curve,field1
    integer(ink) idofix,itcurve,ldofix,ipoin,i0,itotv,icdofn,mistep,ifixvar, &
        ic,ifield,nrfields,temp_var_curve,ielgroup,ielem,inode,i1
    integer(ink)  vertical_direction  !20230402

    integer(ink),pointer::ldofs_t(:)
    real   (irk) dfact,f0,time0,temp0,time1,temp1,temp2,dfact1,dfact2,dtemp
    real   (irk), allocatable::midt(:),dmidt(:),value(:)

    integer(ink), pointer::ldofixb(:)    !hxl2006 MIF
    integer(ink) ifixvar0,jfixvar    !20230402
    real   (irk) fixed1,fixed2,bb,val_fix,wpres,xc,corz  !20230402,gamaw

    do idofix=1,ndofix
        itcurve =prescrib(idofix)%itcurve
        if(itcurve==0)then   ! M1-03 R18: no curve -> unit factor; never index tcurves(0)
            dfact=1.0_irk
            type_curve='NONE'
        else
            dfact   =tcurves(itcurve)%dfact
            type_curve=tcurves(itcurve)%type_curve
        endif
        ldofix  =prescrib(idofix)%ldofix
        ifixvar =prescrib(idofix)%ifixvar  !20230402
        jfixvar=prescrib(idofix)%jfixvar  !20220304



        if(type_curve=='EQUINCRE')then !2007/9/28
            fixed(ldofix)=fixed(ldofix)+fincre*prescrib(idofix)%vdofix
            ! write(7,*)'istep=',istep,'fincre=',fincre,'ldofix=',ldofix,'fixed=',fixed(ldofix)
        else if(ifixvar==8.and.jfixvar/=0)then   !20230402
            inode=prescrib(idofix)%nodfix
            if  (jfixvar>0) then
                wpres=(dfact-coord(jfixvar,inode))*gamaw
            else
                wpres=(coord(-jfixvar,inode)-dfact)*gamaw
            end if
            !if(val_fix(ifixnods)<0.)val_fix(ifixnods)=0.
            fixed(ldofix)=wpres
        else if(ifixvar==8.and.jfixvar==0)then  !20230402

            fixed(ldofix)=dfact*gamaw

        else if(ifixvar==10.and.jfixvar/=0)then  !20230402

            !将坝体上下游分为不同区，jfixvar=0时，与通常方法相同，由*.loa中的曲线，根据时间来确定温度值；
            !jfixvar/=0时，jfixvar为指定区域沿不同深度随时间变化曲线，可以分为上游和下游。
            inode=prescrib(idofix)%nodfix
            vertical_direction=temp_surface(jfixvar)%vertical_direction
            corz=coord(vertical_direction,inode)
            call surface_point_temp_find(jfixvar,corz, fixed(ldofix))

        else     !20230402


            fixed(ldofix)=dfact*prescrib(idofix)%vdofix
            !print *,'idofix=',idofix,'fixed=',fixed(ldofix)

        endif




        if (type_problem=='F'.and.ntrans>0)then
            ldofixb=>prescrib(idofix)%ldofixb    !ziyouduzhu  hxl
            bb=1.0/(gamaMIF+1.0)
            if (istep==1)then
                if(ifixvar0_inpb==ifixvar0)then
                    fixed(ldofix)=inpru(ldofix)
                else
                    fixed(ldofix)=inpzi(ldofix)
                end if
            end if
            if (istep==2)then
                if (ifixvar0_inpb==ifixvar0)then
                    fixed(ldofix)=2*bb*(k1.d.disA_1(ldofixb))+inpru(ldofix)
                else
                    fixed(ldofix)=2*bb*(k1.d.disB_1(ldofixb))+inpzi(ldofix)
                end if
            end if
            if (istep>=3)then
                if (ifixvar0_inpb==ifixvar0)then
                    fixed1=k1.d.disA_1(ldofixb)
                    fixed2=k2.d.disA_2(ldofixb)
                    fixed(ldofix)=2*bb*fixed1-(bb**2)*fixed2+inpru(ldofix)
                else
                    fixed1=k1.d.disB_1(ldofixb)
                    fixed2=k2.d.disB_2(ldofixb)
                    fixed(ldofix)=2*bb*fixed1-(bb**2)*fixed2+inpzi(ldofix)
                end if
            end if
        end if
        nullify(ldofixb)
        !      result_zero(ldofix)=fixed(ldofix)

    end do

    print *,'outinp=',outinp
    !if (outinp>0.and.iblks>=outinp) then !20220626
    !   allocate(midt(npoin))
    !  icdofn=lmdofn(8)
    !  !read(outinpunit,*)text
    !  read(outinpunit)midt
    !  do ipoin=1,npoin
    !     itotv=nodfn(icdofn,ipoin)
    !     if (itotv/=0) then
    !        result_zero(itotv)=midt(ipoin)
    !        fixed(itotv)=midt(ipoin)
    !     endif
    !  end do
    !
    !  deallocate(midt)
    !endif

    if(outinp>0.and.iblks>=outinp) then
        allocate(midt(npoin))

        icdofn=lmdofn(8)
        read(outinpunit,*)text
        do i0=1,npoin
            read(outinpunit,*)ipoin,midt(ipoin)
        enddo
        do ipoin=1,npoin
            itotv=nodfn(icdofn,ipoin)
            if(itotv/=0) then
                result_zero(itotv)=midt(ipoin)
                fixed(itotv)=midt(ipoin)
            endif
        end do

        deallocate(midt)
    endif


    if(outintr<0)then  !20200226
        DO igroup =1,ngroup
            if(appear(igroup)>0) then
                field1=group(igroup)%fieldid
                nrfields=group(igroup)%nrfields
                ic=0
                do ifield=1,nrfields
                    if(field1(ifield:ifield)=='T')then
                        ic=1
                        exit
                    end if
                end do
                if(ic==0) goto 1
                time0=group(igroup)%temp_pre%time0
                temp0=group(igroup)%temp_pre%temp0
                temp_var_curve=group(igroup)%temp_pre%temp_var_curve
                group(igroup)%temp_pre%dtemp=0.
                temp1=temp0
                if(ttime>=time0.and.temp_var_curve/=0)then
                    time1=ttime-ditime*inc_step
                    if(time1>=time0)then
                        call dfact_temp_pre(temp_var_curve,time1-time0,dfact1)
                        temp1=temp0+dfact1
                    endif
                    temp2=temp0
                    if(ttime>time0)then
                        call dfact_temp_pre(temp_var_curve,ttime-time0,dfact2)
                        temp2=temp0+dfact2
                    endif
                    group(igroup)%temp_pre%dtemp=temp2-temp1
                    do ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        ldofs_t=>element(ielem)%field(ifield)%ldofs_f
                        deltafi(ldofs_t)=temp2-temp1    !20200226
                        result_zero(ldofs_t)=temp2 !20200226
                        fixed(ldofs_t)=temp2  !20200226
                        nullify(ldofs_t)
                    enddo
                endif
1               continue
            endif  !if(appear(igroup)>0) then
        end do !igroup
    endif !if(outintr<0)then  !20200226

    if(outintr>0.and.iblks>=outintr) then !20200220
        if(.not.allocated(midt))allocate(midt(npoin))
        midt=0.
        icdofn=lmdofn(10)
        if(inc_step==1) then
            read(outint,rec=trstep)midt
        else
            allocate(dmidt(npoin))
            do mistep=trstep-inc_step+1,trstep  !cj042 add step interpolation for thermal stress 20191120
                print *, 'mistep=',mistep,'trstep=',trstep
                read(outint,rec=mistep)dmidt
                midt=midt+dmidt
            end do
            deallocate(dmidt)
        end if
        write(chkunit,*)'temperature**'
        do ipoin=1,npoin
            if (nodfn(icdofn,ipoin).gt.0) then

                deltafi(nodfn(icdofn,ipoin))=midt(ipoin)    !20200226
                result_zero(nodfn(icdofn,ipoin))=result_zero(nodfn(icdofn,ipoin))+midt(ipoin) !20200226
                fixed(nodfn(icdofn,ipoin))=result_zero(nodfn(icdofn,ipoin))  !20200226

                !result_zero(nodfn(icdofn,ipoin))=midt(ipoin)
                !fixed(nodfn(icdofn,ipoin))=midt(ipoin)

            endif
        end do
    endif

    if(upliftin>0.and.iblks>=upliftin)then  !20221119
        if(water_level(iblks)>=0.)then !20230331
            do ipoin=1,npoin
                xc=water_level(iblks)-coord(ndimn,ipoin)
                if(xc<0.)cycle

                uplift_node(ipoin)=xc*gamaw   !20230402
            enddo
        else   !20230331
            !write(7,*)'uplift_node='
            read(upliftunit)uplift_node
            do ipoin=1,npoin
                if(uplift_node(ipoin)<=0.)uplift_node(ipoin)=0.
                !if(uplift_node(ipoin)>0.) &
                !write(7,*)ipoin,uplift_node(ipoin)
            end do
        endif
    endif !20221119

    if(outind==-1) then  !20231113
        accq=0.
        allocate(value(ndimn))
        do i0=1,tbpointsu
            read(outindunit,*)i1,value
            ipoin=listbpointsu_t(i0)
            accq(:,ipoin)=value
        enddo
        deallocate(value)
    endif !20231113


    END SUBROUTINE modf_var_prescribed

    subroutine dfact_temp_pre(itcurve,time,dfact) !20200226

    character(20)type_curve
    real(irk) time,time1,time2,fact1,fact2,dfact,a0sin,asin,wsin,w0sin
    real(irk)theta0,expon,halftime,totime   	! cj042 20191104 equivalent age
    integer(ink) itcurve,itime,ntime

    ntime=tcurves(itcurve)%ntime
    type_curve=tcurves(itcurve)%type_curve

    if(type_curve=='LINEAR'.or.type_curve=='LNLINEAR') then
        if(time<tcurves(itcurve)%ttime_curve(1)) then
            dfact=0.0
        else if(time>=tcurves(itcurve)%ttime_curve(ntime)) then
            dfact=tcurves(itcurve)%dfact_curve(ntime)
        else
            do itime=1,ntime-1
                time1=tcurves(itcurve)%ttime_curve(itime)
                time2=tcurves(itcurve)%ttime_curve(itime+1)
                dfact=0.0
                if(time>=time1.and.time<time2) then
                    fact1=tcurves(itcurve)%dfact_curve(itime)
                    fact2=tcurves(itcurve)%dfact_curve(itime+1)
                    dfact=fact1+(time-time1)/(time2-time1)*(fact2-fact1)
                    exit
                endif
            end do
        end if
        if(type_curve=='LNLINEAR')dfact=exp(dfact)

    elseif(type_curve=='HARMONIC')  then
        a0sin=tcurves(itcurve)%a0sin
        asin =tcurves(itcurve)%asin
        wsin =tcurves(itcurve)%wsin
        w0sin=tcurves(itcurve)%w0sin
        dfact=a0sin+asin*sin(wsin*time+w0sin)

    elseif(type_curve=='DEXPONENTIAL')  then	!d(f)=a*b*exp(b*t)
        time1=tcurves(itcurve)%ttime_curve(1)    !! b
        fact1=tcurves(itcurve)%dfact_curve(1)    !! a
        dfact=fact1*time1*exp(fact1*time)
    elseif(type_curve=='DABT')  then	!d(f)=a*b/(b+t)**2
        time1=tcurves(itcurve)%ttime_curve(1)    !! a
        fact1=tcurves(itcurve)%dfact_curve(1)    !! b
        dfact=fact1*time1/(fact1+time)**2

    else
        print *, 'no type_curve'
        stop
    end if
    end subroutine dfact_temp_pre !20200226


    SUBROUTINE modf_var_prescribed_w !freq2006

    integer(ink) idofix,ldofix
    do idofix=1,ndofix
        ldofix  =prescrib(idofix)%ldofix
        fixed(ldofix)=(prescrib(idofix)%vdofix)/(ttime**2)
    end do

    END SUBROUTINE modf_var_prescribed_w

    subroutine dfact_time_curve(time)

    character(20)type_curve
    real   (irk) time,time1,time2,fact1,fact2,dfact,dtrec,dtend,ample,a0sin,asin,wsin,w0sin
    integer(ink) itcurve,itime,ntime,mgash,ngash,nf,ii,NFs,i
    real   (irk) dtbegin,pai   !hxl
    real (irk) avTem,dTem,detTime,stTime  !20200220
    real   (irk),allocatable::ai(:),omega(:)

    do itcurve=1,ntcurve
        ntime=tcurves(itcurve)%ntime
        type_curve=tcurves(itcurve)%type_curve
        !print *,'itcurve=',itcurve, 'no type_curve=',type_curve
        if (type_curve=='LINEAR'.or.type_curve=='LNLINEAR'.or.type_curve=='WATERLEVEL') then
            if (time<tcurves(itcurve)%ttime_curve(1)) then
                dfact=0.0
            else if(time>=tcurves(itcurve)%ttime_curve(ntime)) then
                dfact=tcurves(itcurve)%dfact_curve(ntime)
            else
                do itime=1,ntime-1
                    time1=tcurves(itcurve)%ttime_curve(itime)
                    time2=tcurves(itcurve)%ttime_curve(itime+1)
                    dfact=0.0
                    if (time>=time1.and.time<time2) then
                        fact1=tcurves(itcurve)%dfact_curve(itime)
                        fact2=tcurves(itcurve)%dfact_curve(itime+1)
                        dfact=fact1+(time-time1)/(time2-time1)*(fact2-fact1)
                        exit
                    endif
                end do
            end if
            if(type_curve=='LNLINEAR')dfact=exp(dfact)

        elseif(type_curve=='TEMPERATURE')  then
            time1=tcurves(itcurve)%ttime_curve(1)
            time2=tcurves(itcurve)%ttime_curve(2)
            fact1=tcurves(itcurve)%dfact_curve(1)
            fact2=tcurves(itcurve)%dfact_curve(2)
            dfact=time1+fact1*sin(2*3.14159*(time2+time)/fact2)
        elseif(type_curve=='COS')  then !17.5+10.8*COS(2*3.14/12*({TIME}/30-6.8)) 20200220
            avTem=tcurves(itcurve)%dfact_curve(1)   !!cj042@126.com  2013.4.18
            dTem=tcurves(itcurve)%dfact_curve(2)
            detTime=tcurves(itcurve)%dfact_curve(3)
            stTime=tcurves(itcurve)%dfact_curve(4)
            dfact=avTem+dTem*cos(2*3.14159/12*((time+stTime)/30.-detTime))

        elseif(type_curve=='PEAK')  then
            dfact=0.0
            do itime=1,ntime
                time1=tcurves(itcurve)%ttime_curve(itime)
                if (time>=time1) then
                    dfact=tcurves(itcurve)%dfact_curve(itime)
                endif
            end do
        elseif(type_curve=='HARMONIC')  then
            a0sin=tcurves(itcurve)%a0sin
            asin =tcurves(itcurve)%asin
            wsin =tcurves(itcurve)%wsin
            w0sin=tcurves(itcurve)%w0sin
            dtbegin=tcurves(itcurve)%dtbegin
            dtend=tcurves(itcurve)%dtend
            if (time<dtbegin)then
                dfact=1.e-30
            else if(time>(dtbegin+dtend)) then
                dfact=1.e-30
            else
                dfact=a0sin+asin*sin(wsin*time+w0sin)
            endif
        elseif(type_curve=='FOURIERSERIES')  then
            Nfs=tcurves(itcurve)%NFS
            !write(7,*)'nfs=',nfs
            dtbegin=tcurves(itcurve)%dtbegin
            dtend=tcurves(itcurve)%dtend
            allocate(ai(nfs),omega(nfs))
            !write(7,*)'ai=',tcurves(itcurve)%ai,'omega=',tcurves(itcurve)%omega
            ai=tcurves(itcurve)%ai
            omega=tcurves(itcurve)%omega

            if (time<dtbegin)then
                dfact=1.e-30
            else if(time>(dtbegin+dtend)) then
                dfact=1.e-30
            else
                pai=3.14159
                dfact=0.
                do i=1,nfs
                    dfact=dfact+ai(i)*sin(omega(i)*pai*time)
                end do
            endif

            write(7,*)'time=',time,'dfact=',dfact
            deallocate(ai,omega)

        elseif (type_curve=='SEISMIC')  then
            dtrec=tcurves(itcurve)%dtrec   !hxl
            dtbegin=tcurves(itcurve)%dtbegin
            dtend=tcurves(itcurve)%dtend
            ample=tcurves(itcurve)%ample
            dfact=0.0
            if (time<dtbegin)then
                dfact=1.e-30
            else if(time>(dtbegin+dtend)) then
                dfact=1.e-30
            else
                time1=(TIME-dtbegin)/DTREC+1
                MGASH=time1
                NGASH=MGASH+1
                time1=time1-FLOAT(MGASH)
                fact1=tcurves(itcurve)%dfact_curve(mgash)
                fact2=tcurves(itcurve)%dfact_curve(ngash)
                dfact=fact1*(1.0-time1)+time1*fact2
                dfact=dfact*ample
            end if                                 !hxl

        elseif(type_curve=='DEXPONENTIAL')  then   !d(f)=a*b*exp(b*t)
            time1=tcurves(itcurve)%ttime_curve(1)    !! b
            fact1=tcurves(itcurve)%dfact_curve(1)    !! a
            dfact=fact1*time1*exp(time1*time)
        elseif(type_curve=='DABT')  then  !d(f)=a*b/(b+t)**2
            time1=tcurves(itcurve)%ttime_curve(1)    !! a
            fact1=tcurves(itcurve)%dfact_curve(1)    !! b
            dfact=fact1*time1/(fact1+time)**2
        else if(type_curve=='ARCLENGTH') then
            goto 1
        else if(type_curve=='DISCONTROL') then
            goto 1
        else if(type_curve=='EXTRAPOLATION') then
            goto 1
        else
            print *,'itcurve=',itcurve, 'no type_curve=',type_curve
            call diag_abort('UNSUPPORTED',EXIT_UNSUPPORTED,'Fem.f90:dfact_time_curve','itcurve='//trim(diag_itoa(int(itcurve,i8)))//': no such type_curve '//trim(type_curve))   ! M1-03 R20
        end if
        tcurves(itcurve)%dfact=dfact
1       continue
    end do

    end subroutine dfact_time_curve

    subroutine contact_state(ic)
    character(20) field1,name,material
    integer (ink) igroup,matno,index,nnode,nnode_half,  &
        order_int,ngaus,ielgroup,ielem,inode, &
        igaus,nevab,idofn,igap0,jndex,ic,iiii,jjjj,icftg,icft
    integer (ink) gap_kind,ngapx,ix  !20231006
    real    (irk) eps,gap0,smean,ftcontact,ft0,radius,alfax,dxi  !20231006
    integer (ink),pointer::ldofs(:)
    real    (irk),allocatable::rot(:),eldis(:),nordis(:),shape(:,:),gapnod(:),gapgaus(:)
    real    (irk),allocatable::centerx(:),gapx(:),gapalfax(:)  !20231006
    real    (irk):: current_gap, gap_change, natural_gap
    character(20):: previous_state, current_state
    real    (irk):: old_gap


    eps = 1.e-5  ! 增大eps提高数值稳定性


    write(7,*)'contact_state********************'
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            igap0=0
            if (name=='CONTACT')then
                gap0     =props(matno)%mechanical%solid%gap0
                igap0    =props(matno)%mechanical%solid%igap0

                if(igap0==2) then    !20231006
                    ngapx=props(matno)%mechanical%solid%gap_define%ngapx
                    gap_kind=props(matno)%mechanical%solid%gap_define%gap_kind
                    if(gap_kind==1) then
                        allocate(centerx(ndimn),gapx(ngapx),gapalfax(ngapx))
                        radius=props(matno)%mechanical%solid%gap_define%radius
                        centerx=props(matno)%mechanical%solid%gap_define%centerx
                        gapalfax=props(matno)%mechanical%solid%gap_define%gapalfax
                        gapx=props(matno)%mechanical%solid%gap_define%gapx
                    endif
                endif !20231006

                ftcontact=props(matno)%mechanical%solid%ftcontact !zhao 05/08/02
                icft     =props(matno)%mechanical%solid%icft
                index    =group(igroup)%index
                nnode    =elkn(index)%el_field(1)%nnode_f
                nnode_half=nnode/2
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus    =elkn(index)%ggaus(order_int)%ngaus
                if(material=='GOODMAN') then   !! for goodman element

                    jndex=1
                    if (ndimn==3.and.index==9)jndex=5  !2017/02/14
                    if (ndimn==3.and.index==23)jndex=3  !2017/02/14
                    order_int=elkn(jndex)%el_field(1)%order_intrules(1)
                    ngaus=elkn(jndex)%ggaus(order_int)%ngaus
                endif !! for goodman element
                nevab=nnode*ndimn
                allocate(eldis(nevab),nordis(nnode),gapnod(nnode),gapgaus(ngaus),rot(ndimn))
                if (material=='GOODMAN') then   !! for goodman element
                    allocate(shape(nnode_half,ngaus))
                else
                    allocate(shape(nnode,ngaus))
                endif

                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (tension_contact(ielem)/=1)then !zhao 05/07/22  tcl,original==1
                        if (material=='GOODMAN') then
                            rot=element(ielem)%rotation(ndimn,:)
                        else
                            rot=element(ielem)%rotation(1,:)
                        endif
                        ldofs => element(ielem)%field(1)%ldofs_f
                        !eldis=delitfi(ldofs)
                        eldis = deltafi(ldofs)
                        !                  eldis = result_zero(ldofs)

                        if(appear_process(igroup,iblks)==1.and.     &
                            appear_process(igroup,iblks-1)==0.and.   &
                            iincs==1.and.istep==inc_step.and.iiter==1.and.ic==0) then

                            if (igap0==1) then
                                element(ielem)%field(1)%gapg =gap0
                                element(ielem)%field(1)%gapg0=gap0
                                element(ielem)%field(1)%gapn =gap0
                                element(ielem)%field(1)%gapn0=gap0
                            elseif(igap0==2.and.gap_kind==1)then !20231006
                                gapnod=0.
                                do inode=1,nnode
                                    idofn=element(ielem)%field(1)%lnods_f(inode)
                                    dxi=coord(1,idofn)-centerx(1)
                                    alfax=dxi/radius
                                    alfax=acosd(alfax)
                                    if(alfax<gapalfax(1).or.alfax>gapalfax(ngapx))cycle
                                    do ix=1,ngapx-1
                                        if(alfax>=gapalfax(ix).and.alfax<=gapalfax(ix+1))then
                                            gapnod(inode)=gapx(ix)+(gapx(ix+1)-gapx(ix))*(alfax-gapalfax(ix))/(gapalfax(ix+1)-gapalfax(ix))
                                        endif
                                    end do
                                end do

                                if (material=='GOODMAN') then
                                    shape = elkn(jndex)%ggaus(order_int)%shape(:,:)
                                    gapgaus=transpose(shape).x.gapnod(1:nnode_half)
                                else
                                    shape = elkn(index)%ggaus(order_int)%shape(:,:)
                                    gapgaus=transpose(shape).x.gapnod
                                endif
                                !write(7,*)'ie=',ielem,'gapgaus=',gapgaus
                                element(ielem)%field(1)%gapg0=gapgaus
                                element(ielem)%field(1)%gapg=element(ielem)%field(1)%gapg0
                                element(ielem)%field(1)%gapn=element(ielem)%field(1)%gapn0
                            elseif(igap0==99)then !zhao 05/07/19
                                do inode=1,nnode
                                    idofn=element(ielem)%field(1)%lnods_f(inode)
                                    nordis(inode)=rot.d.coord(:,idofn)
                                end do
                                if (ndimn==3) then
                                    do inode=1,nnode_half
                                        gapnod(inode)=nordis(inode+nnode_half)-nordis(inode)
                                        gapnod(inode+nnode_half)=gapnod(inode)
                                    end do
                                else  ! 2D
                                    gapnod(1)=nordis(4)-nordis(1)
                                    gapnod(4)=gapnod(1)
                                    gapnod(2)=nordis(3)-nordis(2)
                                    gapnod(3)=gapnod(2)
                                endif
                                element(ielem)%field(1)%gapn0=gapnod

                                if (material=='GOODMAN') then
                                    shape = elkn(jndex)%ggaus(order_int)%shape(:,:)
                                    gapgaus=transpose(shape).x.gapnod(1:nnode_half)
                                else
                                    shape = elkn(index)%ggaus(order_int)%shape(:,:)
                                    gapgaus=transpose(shape).x.gapnod
                                endif
                                !write(7,*)'ie=',ielem,'gapgaus=',gapgaus
                                element(ielem)%field(1)%gapg0=gapgaus
                                element(ielem)%field(1)%gapg=element(ielem)%field(1)%gapg0
                                element(ielem)%field(1)%gapn=element(ielem)%field(1)%gapn0
                                if(istep.eq.1.and.iincs==1) then
                                    element(ielem)%field(1)%natural_thickness = element(ielem)%field(1)%gapg
                                endif
                            endif  !igap0=1
                        else  !for ic==1
                            do inode=1,nnode
                                idofn=(inode-1)*ndimn
                                nordis(inode)=rot.d.eldis(idofn+1:idofn+ndimn)
                            end do
                            if (ndimn==3) then
                                do inode=1,nnode_half
                                    gapnod(inode)=nordis(inode+nnode_half)-nordis(inode)
                                    gapnod(inode+nnode_half)=gapnod(inode)
                                end do
                            else  ! 2D
                                gapnod(1)=nordis(4)-nordis(1)
                                gapnod(4)=gapnod(1)
                                gapnod(2)=nordis(3)-nordis(2)
                                gapnod(3)=gapnod(2)
                            endif

                            element(ielem)%field(1)%gapn=element(ielem)%field(1)%gapn0+gapnod

                            if (material=='GOODMAN') then
                                shape = elkn(jndex)%ggaus(order_int)%shape(:,:)
                                gapgaus=transpose(shape).x.gapnod(1:nnode_half)
                            else
                                shape = elkn(index)%ggaus(order_int)%shape(:,:)
                                gapgaus=transpose(shape).x.gapnod
                            endif
                            element(ielem)%field(1)%gapg=gapgaus+element(ielem)%field(1)%gapg0
                        endif
                        !write(7,"(A15,I10,5(A10,3E15.7))")'当前间隙为：ie=',ielem,'gapg=   ',element(ielem)%field(1)%gapg
                        !write(7,"(A15,I10,5(A10,3E15.7))")'当前间隙为：ie=',ielem,'gapg0=  ',element(ielem)%field(1)%gapg0
                        !write(7,"(A15,I10,5(A10,3E15.7))")'当前间隙为：ie=',ielem,'gapgaus=',gapgaus
                        do igaus=1,ngaus
                            icftg=element(ielem)%field(1)%icftcontact(igaus)
                            if (material=='GOODMAN') then
                                smean=element(ielem)%field(1)%gpvar(ndimn,igaus)
                            else
                                smean=element(ielem)%field(1)%ntstress(1,igaus)
                            endif
                            element(ielem)%field(1)%state1(igaus)=element(ielem)%field(1)%state(igaus) !zhao 05/07/22
                            element(ielem)%field(1)%state(igaus)='contact'
                            if (icftg==0.and.icft/=0)then
                                ft0=ftcontact
                            else
                                ft0=0.01
                            endif


                            ! 获取间隙变化量（相对于初始状态的变化）
                            current_gap = element(ielem)%field(1)%gapg(igaus)  ! 总间隙（用于显示）
                            gap_change = current_gap-element(ielem)%field(1)%gapg0(igaus)  ! 间隙变化量
                            natural_gap = element(ielem)%field(1)%natural_thickness(igaus)  ! 初始间隙


                            previous_state = element(ielem)%field(1)%state1(igaus)

                            !if (element(ielem)%field(1)%gapg(igaus)>eps.and.smean>ft0) then !ooo
                            !    element(ielem)%field(1)%icftcontact(igaus)=1
                            !    element(ielem)%field(1)%state(igaus)='open'
                            !    !                        write(7,*)'ielem=',ielem,'igaus=',igaus,'gapg=',element(ielem)%field(1)%gapg(igaus),'smean=',smean
                            !endif
                            !cycle


                            if (previous_state == 'contact') then
                                ! contact → open 判断：基于位移增量和真实应力

                                ! 修正的判断条件：
                                ! 1. 位移增量明显为正（张开方向）
                                ! 2. 应力超过拉伸极限（这里smean还是真实应力）
                                if (smean > ft0) then
                                    element(ielem)%field(1)%state(igaus) = 'open'
                                    element(ielem)%evk(:,igaus) = 0.02
                                else
                                    element(ielem)%field(1)%state(igaus) = 'contact'
                                endif

                            elseif (previous_state == 'open') then
                                ! open → contact 判断：基于间隙闭合几何条件

                                ! 正确的判断条件：
                                ! open → contact 的核心：间隙足够小，接近真正接触
                                ! 判断依据：当前间隙接近接触阈值

                                if (gap_change < eps .and. current_gap<natural_gap) then
                                    element(ielem)%field(1)%state(igaus) = 'contact'
                                else
                                    element(ielem)%field(1)%state(igaus) = 'open'
                                endif
                            endif


                            ! --- 根据最终的 'state' 字符串更新整数标志位 icftcontact ---
                            if (element(ielem)%field(1)%state(igaus) == 'open') then
                                element(ielem)%field(1)%icftcontact(igaus) = 1 ! 1 代表张开
                            else
                                element(ielem)%field(1)%icftcontact(igaus) = 0 ! 0 代表接触
                            endif

                        end do  !!igaus
                        element(ielem)%field(1)%icok=0
                        if(all(element(ielem)%field(1)%state1==element(ielem)%field(1)%state))element(ielem)%field(1)%icok=1
                        nullify(ldofs)
                    else !zhao 05/07/22
                        do igaus=1,ngaus
                            element(ielem)%field(1)%state (igaus)='open'
                            element(ielem)%field(1)%state0(igaus)='open'
                            element(ielem)%field(1)%state1(igaus)='open'
                        enddo
                    endif !zhao 05/07/22
                end do   !! ielgroup
                deallocate(rot,nordis,shape,eldis,gapnod,gapgaus)
            endif

            if (name=='CONTACT'.and.igap0==2.and.gap_kind==1)  &
                deallocate(centerx,gapx,gapalfax)   !20231006

        endif
    end do  !! igroup


    iiii=0 ; jjjj=0
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            if (name=='CONTACT')then
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    !if(tension_contact(ielem)/=1)cycle  !20230922
                    if(tension_contact(ielem)==1)cycle  !20230922
                    jjjj=jjjj+1
                    if(element(ielem)%field(1)%icok==1)iiii=iiii+1
                enddo
            endif
        endif
    enddo
    if(iiii==jjjj)iccontact=1

    end subroutine contact_state

    !crack 2006
    subroutine crack_state

    character(20) field1,material,criteria,name
    integer(ink) iielem,iigaus,igroup,matno,index,order_int,ngaus,igaus,ielem
    real   (irk) smin,ft,sx,sy,sxy,s1,delta,strem(3),rr(3,3)
    real   (irk),allocatable::stemp(:)
    allocate(stemp(3*(ndimn-1)))
    smin=1.0e-10
    iielem=0
    iigaus=0
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            matno = group(igroup)%matno
            name=props(matno)%name
            index = group(igroup)%index
            if (name/='CRACK'.or.index==20.or.index==21.or.index==25)cycle
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus

            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                !do igaus=1,ngaus/2 !special for xld
                do igaus=1,ngaus
                    stemp=element(ielem)%field(1)%gpvar(1:3*(ndimn-1),igaus)

                    if (ndimn==3)then
                        call stresmr ( stemp, strem, rr)
                        s1=strem(1)
                    else
                        sx=stemp(1)
                        sy=stemp(2)
                        sxy=stemp(3)
                        delta=sqrt((sx-sy)**2/4+sxy**2)
                        s1=0.
                        if(delta>1.e-5)s1=(sx+sy)/2.+delta
                    endif
                    element(ielem)%field(1)%ntstress(1,igaus)=s1
                    if (smin<s1.and.s1>=ftcrack)then
                        smin=s1
                        iielem=ielem
                        iigaus=igaus
                    endif
                enddo
            enddo
        endif
    enddo
    deallocate(stemp)
    if(iielem*iigaus/=0)then
        write(7,*)'*******************************crack***************************'
        write(7,*)'istep=',istep,'  iiter=',iiter
        write(7,*)'ielem=',iielem,' igaus=',iigaus
        element(iielem)%field(1)%state(iigaus)='open'

        !if(ndimn==3)then
        !  element(iielem)%field(1)%state(iigaus+4)='open'
        !else
        !  element(iielem)%field(1)%state(iigaus+2)='open'
        !endif

        !one element failure in each step
        !element(iielem)%field(1)%state='open'

    endif

    end subroutine crack_state
    !end crack 2006

    subroutine local_stress
    character(20) field1,material,criteria,name
    integer (ink) igroup,matno,index,igaus,idimn,       &
        order_int,ngaus,ielgroup,ielem,ic
    real    (irk) smean,steff
    real    (irk),allocatable::rot(:),devia(:),stemp(:),tensor(:,:)

    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then

            matno = group(igroup)%matno
            material=props(matno)%mechanical%solid%material
            name  = props(matno)%name
            ic=0
            if(name=='CONTACT'.and.material/='GOODMAN')ic=1
            if (material=='CLASSICALEP') then
                criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
                if(criteria=='MCJOINT')ic=1
            endif
            if (ic==1) then
                allocate(rot(ndimn),devia(ndimn),stemp(3*(ndimn-1)),tensor(ndimn,ndimn))
                index = group(igroup)%index
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus = elkn(index)%ggaus(order_int)%ngaus
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    rot=element(ielem)%rotation(1,:)
                    do igaus=1,ngaus
                        stemp=element(ielem)%field(1)%gpvar(1:3*(ndimn-1),igaus)
                        do idimn=1,ndimn
                            tensor(idimn,idimn)=stemp(idimn)
                        end do
                        if (ndimn==2) then
                            tensor(1,2)=stemp(3)
                            tensor(2,1)=stemp(3)
                        elseif(ndimn==3) then
                            tensor(1,2)=stemp(4)
                            tensor(1,3)=stemp(6)
                            tensor(2,3)=stemp(5)
                            tensor(2,1)=stemp(4)
                            tensor(3,1)=stemp(6)
                            tensor(3,2)=stemp(5)
                        endif
                        devia(1:ndimn)=tensor.x.rot(1:ndimn)
                        smean=rot(1:ndimn).d.devia(1:ndimn)
                        steff=sum(devia(1:ndimn)**2)-smean**2
                        if (steff.le.1.e-5) then
                            steff=1.e-5
                        else
                            steff=sqrt(steff)
                        endif
                        !                  write(chkunit,*)'smean=',smean,'steff=',steff
                        element(ielem)%field(1)%ntstress(1,igaus)=smean
                        element(ielem)%field(1)%ntstress(2,igaus)=steff
                    end do  ! igaus
                end do  ! ielgroup
                deallocate(rot,tensor,stemp,devia)
            endif    ! for ic=1
        endif  ! for group appearing
    end do  !! igroup

    end subroutine locaL_stress

    subroutine FORCE_EXTERNAL

    character(10) fieldid,class,name,SPtype
    character(20) type_curve
    integer(ink) iplgroup,nudofn,npload,iedge,itcurve,aelem,nrfields,        &
        ifield,ielem,ipload,ielgroup,ipoin,idofn,jdofn,itotv,ndofn, &
        index,nevab,nnode,type_mass,inode,ic,aelems,ipea1,cdbound,imcon, &
        igaps,igapb,ngroupb,igroupb,ic_inertia,ipairs,npairs   !2017/06
    real   (irk) dfact,preact2,xxxx
    integer(ink),pointer::list(:),ldofe(:),ldofs_f(:),lnods(:)
    real   (irk),pointer::rload(:),tload(:),edload(:),fstif(:,:)
    real   (irk),allocatable::value(:),tt(:),cc(:),loadlocal(:,:,:),forceint(:,:),forcel(:,:)
    real   (irk) dx,ca,ss,t1,t2,t3,timer,coordzi,timer1,timer2
    integer(ink) nextr,i0,i1,iextr,iforce,ipface,idimn,itdis,itveloc,matno
    real   (irk),pointer::cordzfree(:)
    real   (irk),pointer::estif0(:,:),estif(:,:)
    real   (irk),allocatable::dfact1(:),dfact2(:),dfact3(:),dfact4(:) !hxl2006 VIE
    real   (irk),allocatable::value_d(:),value_v(:),eload(:),value_s(:)
    real   (irk),allocatable::sxyz(:),xyz1(:),xyz2(:),dsxyz(:,:),speed(:)
    real   (irk) density,e,nu,alfa,beta,g
    real   (irk)  timer0 !20220105
    integer(ink),pointer::ldofs(:)
    integer(ink),allocatable::ic_inertia_group(:)  !2017/06

    write(7,*)'force_external***,edge_load_group=',edge_load_group
    if(allocated(floae))floae=0. !!nstoks
    tofor=0.0
    if(type_load=='ARCLENGTH')tofor_arclength=0.
    !! add point load increment
    do iplgroup=1,nplgroup
        itcurve=pload(iplgroup)%order_time_curve
        type_curve=tcurves(itcurve)%type_curve


        if (type_curve=='EXTRAPOLATION')then !2004/9/11
            nextr=tcurves(itcurve)%nextr
            allocate(cc(nextr))

            dx=tcurves(itcurve)%dx
            ca=tcurves(itcurve)%ca
            ss=ca*ditime/dx
            t1=(2.-ss)*(1.-ss)*.5
            t2=ss*(2.-ss)
            t3=ss*(ss-1.)*.5
            if (nextr==1)then
                cc(1)=1.
            elseif(nextr==2)then
                cc(1)=2;cc(2)=-1.
            elseif(nextr==5)then
                cc(1)=3.;cc(2)=-3.;cc(3)=1.
            endif
            npload=pload(iplgroup)%npload
            allocate(loadlocal(npload,ndimn,nextr),forceint(ndimn,npoin),forcel(ndimn,2*nextr+1))

            do iextr=1,nextr  !iextr
                allocate(tt(2*iextr+1))
                if (iextr==1)then
                    tt(1)=t1;tt(2)=t2;tt(3)=t3
                elseif(iextr==2)then
                    tt(1)=t1**2;tt(2)=2*t1*t2;tt(3)=2*t1*t3+t2**2
                    tt(4)=2*t2*t3;tt(5)=t3**2
                elseif(iextr==5)then
                    tt(1)=t1**3;tt(2)=3*t2*t1**2;tt(3)=3*t1*t2**2+3*t3*t1**2
                    tt(4)=6*t1*t2*t3+t2**3;tt(5)=3*t1*t3**2+3*t3*t2**2
                    tt(6)=3*t2*t3**2;tt(7)=t3**3
                endif

                forceint=0.
                do iforce=1,nforce
                    npface=surface_force(iforce)%npface
                    do ipface=1,npface
                        ipoin=surface_force(iforce)%list_npface(ipface)
                        forceint(:,ipoin)=surface_force(iforce)%ftfor_ext(:,ipface,iextr)
                    end do
                end do
                do i0=1,npload
                    forcel=0.
                    do i1=1,2*iextr+1
                        forcel(:,i1)=forceint(:,pload(iplgroup)%listep(i0,i1))
                    end do

                    do i1=1,ndimn
                        loadlocal(i0,i1,iextr)=forcel(i1,1:2*iextr+1).d.tt
                    end do
                end do
                deallocate(tt)
            end do   !iextr
            list=>pload(iplgroup)%list
            do i0=1,npload
                ipoin=list(i0)
                do i1=1,ndimn
                    jdofn=lmdofn(i1)
                    if (jdofn/=0) then
                        itotv=nodfn(jdofn,ipoin)
                        tofor(itotv)=tofor(itotv)+(cc.d.loadlocal(i0,i1,:))
                    endif
                end do
            end do
            nullify(list)
            deallocate(loadlocal,forceint,forcel,cc)
        elseif(type_curve=='DISCONTROL')then
            ic=tcurves(itcurve)%ttime_curve(1)
            if(iiter==2)preact1=prescrib(ic)%rdofix
            if (iiter>=3)then
                preact2=prescrib(ic)%rdofix
                if(iiter==3)dfact=(preact1-preact0)**2/(2*(preact1-preact0)-(preact2-preact0))
                if(iiter>3)dfact=(preact1-preact0)*preact4/((preact1-preact0)+preact4-(preact2-preact0))
                preact4=dfact
                dfact=preact0+dfact
                dfact=dfact*tcurves(itcurve)%dfact_curve(1)
            else
                dfact=tcurves(itcurve)%dfact_curve(1)
                dfact=dfact*prescrib(ic)%rdofix
            endif
        else
            dfact=tcurves(itcurve)%dfact
            !write(7,*)'istep=',istep,'dfact=',dfact
        endif

        if (type_curve/='EXTRAPOLATION')then !2004/9/11
            nudofn=pload(iplgroup)%nudofn
            npload=pload(iplgroup)%npload
            list=>pload(iplgroup)%list
            do ipload=1,npload
                ipoin=list(ipload)
                do idofn=1,nudofn
                    jdofn=lmdofn(idofn)
                    if (jdofn/=0) then
                        itotv=nodfn(jdofn,ipoin)
                        tofor(itotv)=tofor(itotv)+(pload(iplgroup)%pxyz(idofn))*dfact
                        if(type_curve=='ARCLENGTH')tofor_arclength(itotv)=tofor_arclength(itotv)+pload(iplgroup)%pxyz(idofn)
                    end if
                end do
            end do
            nullify(list)
        endif    !2004/9/11
    end do
    !! initialize tload
    do ielem=1,nelem
        igroup=element(ielem)%group
        nrfields=group(igroup)%nrfields
        !if (appear(igroup)>0) then  !2017/11/19
        do ifield=1,nrfields
            element(ielem)%field(ifield)%tload=0.0
        end do
        !end if   !2017/11/19
    end do

    if (rmesh>0)then
        do ielem=1,nelem1
            igroup=element1(ielem)%group
            nrfields=group(igroup)%nrfields
            !if (appear(igroup)>0.and.jce1(ielem)/=1) then   !2017/11/19
            do ifield=1,nrfields
                element1(ielem)%field(ifield)%tload=0.0    !2017/11/19
            end do
            !end if
        end do
    endif

    if (rmesh>1)then
        do ielem=1,nelem2
            igroup=element2(ielem)%group
            nrfields=group(igroup)%nrfields
            !if (appear(igroup)>0) then   !2017/11/19
            do ifield=1,nrfields
                element2(ielem)%field(ifield)%tload=0.0
            end do
            !end if     !2017/11/19
        end do
    endif
    !! add beam load
    do ielgroup=1,nbeamload
        edload=>beamload(ielgroup)%edload
        aelem=beamload(ielgroup)%aelem
        itcurve=beamload(ielgroup)%itcurve
        dfact=tcurves(itcurve)%dfact
        element(aelem)%field(1)%tload=element(aelem)%field(1)%tload+edload*dfact
        nullify(edload)
    end do
    !! add plate_water pressure
    !write(7,*)'plateload***='
    do ielgroup=1,nplateload
        edload=>plateload(ielgroup)%edload
        aelem=plateload(ielgroup)%aelem
        itcurve=plateload(ielgroup)%itcurve
        dfact=tcurves(itcurve)%dfact
        element(aelem)%field(1)%tload=element(aelem)%field(1)%tload+edload*dfact
        !write(7,*)aelem,element(aelem)%field(1)%tload

        nullify(edload)
    end do
    !! add edge load increment to tload
    do ielgroup=1,edge_load_group
        iedge=edgeload(ielgroup)%iedge
        itcurve=edgeload(ielgroup)%itcurve

        type_curve=tcurves(itcurve)%type_curve
        !print *,'ielgroup=',ielgroup,'iedge=',iedge,'itvurve=',itcurve,'type_curve=',type_curve
        edload=>edgeload(ielgroup)%edload
        dfact=tcurves(itcurve)%dfact

        if (rmesh==0)then  !!!!!!for rmesh==0
            aelem=edges(iedge)%aelem
            !write(7,*)'iedge=',iedge,'aelem=',aelem,'dfact=',dfact,'edload=',edload

            if(type_curve=='ARCLENGTH')ldofs_f => element(aelem)%field(1)%ldofs_f
            ldofe=>edges(iedge)%ldofe
            ndofn=size(ldofe)

            ! print *,'iedge=',iedge,'aelem=',aelem,'ndofn=',ndofn,'size(tload)=',size(element(aelem)%field(1)%tload)
            !print *,'ldofe=',ldofe
            do idofn=1,ndofn
                jdofn=ldofe(idofn)
                element(aelem)%field(1)%tload(jdofn)=        &
                    element(aelem)%field(1)%tload(jdofn)+edload(idofn)*dfact
                if (type_curve=='ARCLENGTH') then
                    itotv=ldofs_f(jdofn)
                    tofor_arclength(itotv)=tofor_arclength(itotv)+edload(idofn)
                endif
            end do
            if(type_curve=='ARCLENGTH')nullify(ldofs_f)
            nullify(ldofe)
            if (allocated(floae))then  !!nstoks
                igroup=element(aelem)%group
                matno = group(igroup)%matno
                name=props(matno)%name
                if (name=='NSTOKS')then
                    ldofs_f => element(aelem)%field(1)%ldofs_f
                    do idofn=1,ndofn
                        jdofn=ldofe(idofn)
                        itotv=ldofs_f(jdofn)
                        floae(itotv)=floae(itotv)+edload(idofn)*dfact
                    end do
                    nullify(ldofs_f)
                endif
            endif
        else    !for rmesh/=0
            lnods=>edges(iedge)%lnode
            do inode=1,size(lnods)
                do idofn=1,ndimn
                    itotv=nodfn(idofn,lnods(inode))
                    if(itotv>0)tofor(itotv)=tofor(itotv)+edload((inode-1)*ndimn+idofn)*dfact
                end do
            end do
            nullify(lnods)
        endif
        nullify(edload)
    end do
    !! add body force to tload

    write(7,*)'body force'
    do ielem=1,nelem
        igroup=element(ielem)%group
        fieldid=group(igroup)%fieldid
        !if (appear(igroup)>0.and.ice0(ielem)/=1) then   !2017/11/19
        nrfields=element(ielem)%nrfields
        do ifield=1,nrfields
            if (associated(element(ielem)%field(ifield)%rload)) then
                rload=> element(ielem)%field(ifield)%rload
                if (fieldid(ifield:ifield)=='U'.or.fieldid(ifield:ifield)=='W')then
                    itcurve=tcurvegravity(igroup)
                    !print *,'ie=',ielem,'igroup=',igroup,'itcurve=',itcurve
                    if (itcurve/=0) then
                        type_curve=tcurves(itcurve)%type_curve
                        ldofs_f => element(ielem)%field(ifield)%ldofs_f
                        dfact=tcurves(itcurve)%dfact
                        element(ielem)%field(ifield)%tload=                  &
                            element(ielem)%field(ifield)%tload+ rload*dfact
                        !write(7,*)'ie=',ielem,'rload=',rload,'dfact=',dfact
                        if (ifield==1.and.allocated(floae))then  !!nstoks
                            matno = group(igroup)%matno
                            name=props(matno)%name
                            if(name=='NSTOKS') &
                                floae(ldofs_f)=floae(ldofs_f)+rload*dfact
                        endif
                        if(type_curve=='ARCLENGTH')tofor_arclength(ldofs_f)=tofor_arclength(ldofs_f)+rload
                        nullify(ldofs_f)
                    endif
                elseif(fieldid(ifield:ifield)=='T') then
                    element(ielem)%field(ifield)%tload=                  &
                        element(ielem)%field(ifield)%tload+ rload
                endif
                nullify(rload)
            endif
        end do
        !endif   !2017/11/19
    end do
    !!!!!!!!!!!!!!!!!!!!!!!!
    if (rmesh>0)then
        do ielem=1,nelem1
            igroup=element1(ielem)%group
            fieldid=group(igroup)%fieldid
            !if (appear(igroup)>0.and.jce1(ielem)/=1) then  !2017/11/19
            nrfields=element1(ielem)%nrfields
            do ifield=1,nrfields
                if (associated(element1(ielem)%field(ifield)%rload)) then
                    rload=> element1(ielem)%field(ifield)%rload
                    if (fieldid(ifield:ifield)=='U'.or.fieldid(ifield:ifield)=='W')then
                        itcurve=tcurvegravity(igroup)
                        if (itcurve/=0) then
                            type_curve=tcurves(itcurve)%type_curve
                            ldofs_f => element1(ielem)%field(ifield)%ldofs_f
                            dfact=tcurves(itcurve)%dfact
                            element1(ielem)%field(ifield)%tload=                  &
                                element1(ielem)%field(ifield)%tload+ rload*dfact
                            nullify(ldofs_f)
                        endif
                    elseif(fieldid(ifield:ifield)=='T') then
                        element1(ielem)%field(ifield)%tload=                  &
                            element1(ielem)%field(ifield)%tload+ rload
                    endif
                    nullify(rload)
                endif
            end do
            !endif   !2017/11/19
        end do
    endif
    !!!!!!!!!!!!!!!!!!!!!
    if (rmesh>1)then
        do ielem=1,nelem2
            igroup=element2(ielem)%group
            fieldid=group(igroup)%fieldid
            !if (appear(igroup)>0) then  !2017/11/19
            nrfields=element2(ielem)%nrfields
            do ifield=1,nrfields
                if (associated(element2(ielem)%field(ifield)%rload)) then
                    rload=> element2(ielem)%field(ifield)%rload
                    if (fieldid(ifield:ifield)=='U'.or.fieldid(ifield:ifield)=='W')then
                        itcurve=tcurvegravity(igroup)
                        if (itcurve/=0) then
                            type_curve=tcurves(itcurve)%type_curve
                            ldofs_f => element2(ielem)%field(ifield)%ldofs_f
                            dfact=tcurves(itcurve)%dfact
                            element2(ielem)%field(ifield)%tload=                  &
                                element2(ielem)%field(ifield)%tload+ rload*dfact
                            nullify(ldofs_f)
                        endif
                    elseif(fieldid(ifield:ifield)=='T') then
                        element2(ielem)%field(ifield)%tload=element2(ielem)%field(ifield)%tload+ rload
                    endif
                    nullify(rload)
                endif
            end do
            !endif  !2017/11/19
        end do
    endif

    !! internal heat source for unsteady temperature problem

    call assemble_boundt_eload


    !! add inertia force

    write(7,*)'interia force***'
    if (type_problem=='F')then


        ic_inertia=0    !ic_inertia,ic_inertia_group 主要用来识别当接触块体完全张开后，不在施加地震惯性力
        allocate(ic_inertia_group(ngroup))
        ic_inertia_group=1

        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            do ipairs=1,npairs
                if(gaps(igaps)%state(ipairs)/=0) ic_inertia=1
            end do
        end do
        if(ic_inertia==0)then
            do igapb=1,ngapb !2017/06
                if(gapb(igapb)%nrdof==0)cycle
                ngroupb=gapb(igapb)%ngroupb
                do igroupb=1,ngroupb
                    ic_inertia_group(gapb(igapb)%listgroupb(igroupb))=0
                end do
            end do
        endif   !2017/06

        DO igroup =1,ngroup
            if(force_process(igroup)==0)cycle !zhao 05/08/05

            write(7,*)'igroup=',igroup,'ic_=',ic_inertia_group(:)
            if(ic_inertia_group(igroup)==0) cycle !2017/06
            !if (appear(igroup)>0) then  !2017/11/19
            ! get information from the group level
            fieldid=group(igroup)%fieldid
            class  =group(igroup)%class
            if (fieldid(1:1)=='U'.and.class=='CO')then
                index    =group(igroup)%index
                ndofn    =group(igroup)%dof(1)%nfdof
                nnode    =elkn(index)%el_field(1)%nnode_f
                nevab    =nnode*ndofn
                allocate(value(nevab))
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (associated(element(ielem)%field(1)%khandmc(2)%fstif)) then
                        ! if(istep==nstep) &
                        !write(7,*)'ielem=',ielem,'element(ielem)%field(1)%tload0=',element(ielem)%field(1)%tload


                        fstif=>element(ielem)%field(1)%khandmc(2)%fstif
                        ic=size(fstif,dim=2)
                        value=0.0
                        do inode=1,nnode
                            idofn=(inode-1)*ndofn
                            value(idofn+1:idofn+ndimn)=-fachv
                        end do
                        !write(7,*)'ielem=',ielem,'value=',value,'fstif=',fstif,'value=',value
                        if (ic/=1) then
                            element(ielem)%field(1)%tload=element(ielem)%field(1)%tload+matmul(fstif,value)
                        else
                            do idofn=1,nevab
                                element(ielem)%field(1)%tload(idofn)=                  &
                                    element(ielem)%field(1)%tload(idofn)+fstif(idofn,1)*value(idofn)
                            end do
                        endif
                        !if(istep==nstep) &
                        !write(7,*)'ielem=',ielem,'element(ielem)%field(1)%tload=',element(ielem)%field(1)%tload
                        nullify(fstif)
                    endif        !! for associated
                end do          !! for ielgroup
                deallocate(value)
            end if   !! for 'U' and 'CO'
            !endif       !! for aappear  !2017/11/19
        end do         !! for igroup
        deallocate(ic_inertia_group)   !2017/06

        !hxl2006 VIE
        do ielem=1,nabssgroup
            aelems=tabss(ielem)%aelems
            ipea1=0
            igroup=element(aelems)%group
            if(appear(igroup)>0)ipea1=1
            if (ipea1==1) then
                cdbound=tabss(ielem)%cdbound  !!hxl_l  1,for lateral, 2 for bottom
                lnods=>tabss(ielem)%lnods
                cordzfree=>tabss(ielem)%cordzfree

                !write(7,*)'ie=',ielem,'lnods=',lnods,'cordzfree=',cordzfree
                nnode=size(lnods)
                allocate(dfact1(ndimn),dfact2(ndimn),dfact3(ndimn),dfact4(ndimn))
                allocate(value_d(nnode*ndimn),value_v(nnode*ndimn),value_s(nnode*ndimn))
                allocate(sxyz(ndimn),speed(ndimn),dsxyz(ndimn,ndimn),xyz1(ndimn),xyz2(ndimn))
                value_d=0.;value_v=0.;value_s=0.
                matno=element(tabss(ielem)%aelems)%matno
                SPtype=group(element(tabss(ielem)%aelems)%group)%SPtype
                density=props(matno)%mechanical%solid%density !densxx !

                if(Bparameter/=0.and.props(matno)%mechanical%solid%ie/=0)then !20190810
                    e=xvalue(props(matno)%mechanical%solid%ie)
                else
                    e=props(matno)%mechanical%solid%e !exx !
                endif
                if(Bparameter/=0.and.props(matno)%mechanical%solid%iNu/=0)then
                    Nu=xvalue(props(matno)%mechanical%solid%iNu)
                else
                    Nu=props(matno)%mechanical%solid%Nu !uxx !
                endif

                alfa = e*(1-nu)/((1.+nu)*(1.-2.*nu))
                beta = e*nu/((1.+nu)*(1.-2.*nu))
                if(SPtype=='PS')alfa=e/(1.0-nu**2)
                if(SPtype=='PS')beta=alfa*nu
                G= e/(2.*(1.+nu))
                speed(ndimn)=sqrt(alfa/density) !P波波速
                speed(1:(ndimn-1))=sqrt(g/density) !S波波速
                if (cdbound==2)then           !底边界
                    if(hwdirec==0) then !20220105

                        call dfact_time_curve(ttime)
                        dfact1=0.;dfact2=0.;  sxyz=0.
                        do idimn=1,ndimn
                            itdis=earthquake_curve_d(idimn)     !!hxl_l
                            itveloc=earthquake_curve_v(idimn)   !!hxl_l
                            if(itdis>0) &
                                dfact1(idimn)=tcurves(itdis)%dfact     !入射位移波
                            if(itveloc>0)dfact2(idimn)=2.*tcurves(itveloc)%dfact    !入射速度波 *2？
                        end do
                        do inode=1,nnode
                            do idimn=1,ndimn
                                value_d((inode-1)*ndimn+idimn)=dfact1(idimn)
                                value_v((inode-1)*ndimn+idimn)=dfact2(idimn)
                            end do
                        end do


                    else !20220105
                        !****!20220105
                        do inode=1,nnode
                            timer0=0.  !20220105
                            if(hwdirec>0)then !20220105
                                timer0=(coord(hwdirec,lnods(inode))-hcoord)/speed(hwdirec) !20220105
                            else if(hwdirec<0)then !20220105
                                timer0=(hcoord-coord(hwdirec,lnods(inode)))/speed(-hwdirec) !20220105
                            endif  !20220105
                            timer0=ttime-timer0 !计算时间与输入波传播至当前点的时间之差，即已传播至当前点的时间
                            dfact1=0.;dfact2=0.;  sxyz=0.
                            if (timer0>0.)then
                                call dfact_time_curve(timer0)
                                do idimn=1,ndimn
                                    itdis=earthquake_curve_d(idimn)     !!hxl_l
                                    itveloc=earthquake_curve_v(idimn)   !!hxl_l
                                    if(itdis>0)  dfact1(idimn)=tcurves(itdis)%dfact
                                    if(itveloc>0)dfact2(idimn)=tcurves(itveloc)%dfact
                                end do
                            endif
                            do idimn=1,ndimn
                                value_d((inode-1)*ndimn+idimn)=dfact1(idimn)
                                value_v((inode-1)*ndimn+idimn)=dfact2(idimn)
                            end do
                        end do
                        !****!20220105


                    endif !20220105


                elseif(cdbound==1)then       !侧边界
                    dfact1=0.;dfact2=0.;  sxyz=0.
                    do inode=1,nnode
                        timer0=0.  !20220105
                        if(hwdirec>0)then !20220105
                            timer0=(coord(hwdirec,lnods(inode))-hcoord)/speed(hwdirec) !20220105
                        else if(hwdirec<0)then !20220105
                            timer0=(hcoord-coord(hwdirec,lnods(inode)))/speed(-hwdirec) !20220105
                        endif  !20220105
                        coordzi=coord(ndimn,lnods(inode))
                        do idimn=1,ndimn
                            itdis=earthquake_curve_d(idimn)     !!hxl_l
                            itveloc=earthquake_curve_v(idimn)   !!hxl_l
                            timer1=(coordzi-inpcord)/speed(idimn) !输入波传播至当前点的时间
                            timer1=timer1+timer0 !20220105
                            timer1=ttime-timer1 !计算时间与输入波传播至当前点的时间之差，即已传播至当前点的时间
                            if (timer1>0.)then
                                call dfact_time_curve(timer1)
                                if(itdis>0)  dfact1(idimn)=tcurves(itdis)%dfact
                                if(itveloc>0)dfact2(idimn)=tcurves(itveloc)%dfact
                                if(itveloc>0)sxyz(idimn)=-speed(idimn)*density*tcurves(itveloc)%dfact
                                ! sxyz 入射速度波产生的应力г=-ρ*Cs*V
                            endif
                        end do

                        if (ndimn==2)then ! 由1:nidmn-1个切应力及ndimn法向应力推求入射速度波产生应力张量dsxyz
                            dsxyz(1,1)=beta/alfa*sxyz(2)
                            dsxyz(2,2)=sxyz(2)
                            dsxyz(1,2)=sxyz(1)
                            dsxyz(2,1)=sxyz(1)
                        elseif(ndimn==3)then ! 由1:nidmn-1个切应力及ndimn法向应力推求入射速度波产生应力张量dsxyz
                            dsxyz(1,1)=beta/alfa*sxyz(3)
                            dsxyz(2,2)=dsxyz(1,1)
                            dsxyz(3,3)=sxyz(3)
                            dsxyz(1,2)=0.
                            dsxyz(1,3)=sxyz(1)
                            dsxyz(2,1)=0.
                            dsxyz(2,3)=sxyz(2)
                            dsxyz(3,1)=sxyz(1)
                            dsxyz(3,2)=sxyz(2)
                        endif
                        xyz1=dsxyz.x.tabss(ielem)%rr(ndimn,:) !转换至整体坐标系
                        ! xyz1:整体坐标系下上行波产生的应力

                        dfact3=0.
                        dfact4=0.
                        sxyz=0.
                        do idimn=1,ndimn
                            itdis=earthquake_curve_d(idimn)     !!hxl_l
                            itveloc=earthquake_curve_v(idimn)   !!hxl_l
                            timer2=(cordzfree(inode)-inpcord)/speed(idimn)+(cordzfree(inode)-coordzi)/speed(idimn)
                            timer2=timer2+timer0 !20220105
                            !timer2:入射波传播至顶面的时间+从顶面再传播至当前点的时间
                            timer2=ttime-timer2 !计算时间与入射波从顶面反射至当前点的时间之差
                            if (timer2>0.) then
                                call dfact_time_curve(timer2)
                                if(itdis>0)dfact3(idimn)=tcurves(itdis)%dfact
                                if(itveloc>0)dfact4(idimn)=tcurves(itveloc)%dfact
                                if(itveloc>0)sxyz(idimn)=speed(idimn)*density*tcurves(itveloc)%dfact
                                ! sxyz 入射速度波产生的应力г=ρ*Cs*V
                            endif
                        end do



                        if (ndimn==2)then
                            dsxyz(1,1)=beta/alfa*sxyz(2)
                            dsxyz(2,2)=sxyz(2)
                            dsxyz(1,2)=sxyz(1)
                            dsxyz(2,1)=sxyz(1)
                        elseif(ndimn==3)then
                            dsxyz(1,1)=beta/alfa*sxyz(3)
                            dsxyz(2,2)=dsxyz(1,1)
                            dsxyz(3,3)=sxyz(3)
                            dsxyz(1,2)=0.
                            dsxyz(1,3)=sxyz(1)
                            dsxyz(2,1)=0.
                            dsxyz(2,3)=sxyz(2)
                            dsxyz(3,1)=sxyz(1)
                            dsxyz(3,2)=sxyz(2)
                        endif
                        xyz2=dsxyz.x.tabss(ielem)%rr(ndimn,:)
                        ! xyz1:整体坐标系下下行波产生的应力
                        do idimn=1,ndimn
                            value_d((inode-1)*ndimn+idimn)=(dfact1(idimn)+dfact3(idimn)) !自由场位移波
                            value_v((inode-1)*ndimn+idimn)=(dfact2(idimn)+dfact4(idimn)) !自由场速度波
                            value_s((inode-1)*ndimn+idimn)=xyz1(idimn)+xyz2(idimn)       !自由场应力波
                            !实际上将自由场分为两部分：上行波（即输入波）与下行波（即反射波）
                        end do
                    end do
                endif

                !estif  =Int. (RT NT ρ*Cs N R)
                !estif0 =Int. (RT NT k/(2*rb) N R)
                !eload_s=Int. (NT N)

                !将自由场应力转换为结点荷载累加至总体荷载列阵tofor
                ldofs=>tabss(ielem)%ldofs
                allocate(eload(size(ldofs)))
                estif=>tabss(ielem)%estif
                eload=estif.x.value_v

                tofor(ldofs)=tofor(ldofs)+eload
                estif0=>tabss(ielem)%estif0
                eload=estif0.x.value_d
                tofor(ldofs)=tofor(ldofs)+eload
                nullify(estif)
                estif=>tabss(ielem)%eload_s
                eload=estif.x.value_s
                tofor(ldofs)=tofor(ldofs)+eload
                nullify(ldofs,estif,estif0)
                deallocate(eload)
                deallocate(dfact1,dfact2,dfact3,dfact4,value_d,value_v,value_s)
                deallocate(sxyz,speed,dsxyz,xyz1,xyz2)
            endif
        end do
        !end hxl2006 VIE

    end if   !! for fast problems !if (type_problem=='F')then

    !************************************************************************
    !levelset
    !add dynamic pressure of levelset , for fsi problem

    If (type_problem=='F'.and.level_set_problem==2)then

        do iedge=1,nedgel !iedge
            ic=edgesl(iedge)%ic

            if(ic/=1)cycle !ic=1--FSI boundary, ic/=1--others

            edload=>edgesl(iedge)%edload
            aelem=edgesl(iedge)%selem

            !if(type_curve=='ARCLENGTH')  &
            !ldofs_f => element(aelem)%field(1)%ldofs_f

            !dfact=tcurves(itcurve)%dfact
            dfact=1.0
            ldofe=>edgesl(iedge)%ldofe
            ndofn=size(ldofe)

            do idofn=1,ndofn
                jdofn=ldofe(idofn)
                element(aelem)%field(1)%tload(jdofn)=        &
                    element(aelem)%field(1)%tload(jdofn)+edload(idofn)*dfact
            enddo
        enddo
    Endif

    !************************************************************************

    !! add tload to tofor
    do ielem=1,nelem
        igroup=element(ielem)%group
        !if (appear(igroup)>0.and.ice0(ielem)/=1) then    !!2017/11/19

        nrfields=element(ielem)%nrfields
        do ifield=1,nrfields
            if (associated(element(ielem)%field(ifield)%tload)) then
                tload=> element(ielem)%field(ifield)%tload
                ldofe=>element(ielem)%field(ifield)%ldofs_f
                ndofn=size(ldofe)
                do idofn=1,ndofn
                    tofor(ldofe(idofn))=tofor(ldofe(idofn))+tload(idofn)
                    !write(7,*)'ie=',ielem,'itotv=',ldofe(idofn),'tofor=', tofor(ldofe(idofn)),'tload=',tload(idofn)
                end do
                nullify(tload,ldofe)
            end if
        end do
        !endif               !!2017/11/19
    end do

    !if(istep==nstep)then
    !write(7,*)'tofor11='
    !do itotv=1,ntotv
    !write(7,*)itotv,tofor(itotv)
    !end do
    !endif

    !ifs2006 zhao, 06/03/29, icaddmass
    if (icaddmass/=0)then
        do ipoin=1,npoin
            if(icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxxx=fachv(idimn)
                tofor(itotv)=tofor(itotv)-addmp(idimn,ipoin)*xxxx
            enddo
        enddo
    endif
    !2013/4/12
    if (nmcon/=0)then
        do imcon=1,nmcon
            ipoin=lmcon(imcon)
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxxx=fachv(idimn)
                tofor(itotv)=tofor(itotv)-rmcon(idimn,imcon)*xxxx
            enddo
        enddo
    endif

    if(alfa_p4>0)then  !20221124 对应于局部坐标作未知量的节点，将外载进行转换
        allocate(value(ndimn))
        do ipoin=1,npoin
            if (local_p4(ipoin)==0)cycle
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)value(idofn)=tofor(itotv)
            end do

            value=prot(:,:,ipoin).x.value
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)tofor(itotv)=value(idofn)
            end do

            value=0.
            do idofn=4,2*ndimn
                itotv=nodfn(lmdofn(idofn),ipoin)
                if (itotv/=0)value(idofn-3)=tofor(itotv)
            end do
            value=prot(:,:,ipoin).x.value
            do idofn=1,ndimn   !4,2*ndimn
                itotv=nodfn(ndimn+idofn,ipoin)
                if (itotv/=0)tofor(itotv)=value(idofn)
            end do
        end do
        deallocate(value)
    end if !20221124



    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    if (rmesh>0.and.nelem1>0)then
        do ielem=1,nelem1
            igroup=element1(ielem)%group
            !if (appear(igroup)>0.and.jce1(ielem)/=1) then    !    !2017/11/19
            nrfields=element1(ielem)%nrfields
            do ifield=1,nrfields
                if (associated(element1(ielem)%field(ifield)%tload)) then
                    tload=> element1(ielem)%field(ifield)%tload
                    ldofe=>element1(ielem)%field(ifield)%ldofs_f
                    ndofn=size(ldofe)
                    do idofn=1,ndofn
                        tofor(ldofe(idofn))=tofor(ldofe(idofn))+tload(idofn)
                    end do
                    nullify(tload,ldofe)
                end if
            end do
            !endif               !!2017/11/19
        end do
    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    if (rmesh>1.and.nelem2>0)then
        do ielem=1,nelem2
            igroup=element2(ielem)%group
            !if (appear(igroup)>0) then    !    !2017/11/19
            nrfields=element2(ielem)%nrfields
            do ifield=1,nrfields
                if (associated(element2(ielem)%field(ifield)%tload)) then
                    tload=>element2(ielem)%field(ifield)%tload
                    ldofe=>element2(ielem)%field(ifield)%ldofs_f
                    ndofn=size(ldofe)
                    do idofn=1,ndofn
                        tofor(ldofe(idofn))=tofor(ldofe(idofn))+tload(idofn)
                    end do
                    nullify(tload,ldofe)
                end if
            end do
            !endif               !!2017/11/19
        end do
    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    if(ground_inf/=0.and.allocated(load_space)) then
        tofor(ldofs_space)=tofor(ldofs_space)+load_space
    endif

1111 format(a10,i10,2(a10,f15.5),a10,2f15.5)
1112 format(a10,i10,a10,f15.5,a10,2f15.5)

    end subroutine FORCE_EXTERNAL




    subroutine FORCE_EXTERNAL_w !freq2006

    integer(ink) nnode,inode,cdbound,idimn
    integer(ink),pointer::list(:),ldofe(:),lnods(:)
    complex   (irk),allocatable::dfact1(:),dfact2(:),estif0(:,:),estif(:,:)
    complex   (irk),allocatable::value_d(:),value_v(:),eload(:)
    real   (irk) density,e,nu,alfa,beta,g
    integer(ink),pointer::ldofs(:)


    toforw=0.0
    do ielem=1,nabssgroup
        cdbound=tabss(ielem)%cdbound  ! 1,for lateral, 2 for bottom
        lnods=>tabss(ielem)%lnods
        nnode=size(lnods)
        allocate(dfact1(ndimn),dfact2(ndimn))
        allocate(value_d(nnode*ndimn),value_v(nnode*ndimn))
        value_d=0.;value_v=0.
        if (cdbound==2)then           !bottom
            dfact1=0.;dfact2=0.
            do idimn=1,ndimn
                if (fachv(idimn)/=0)then
                    dfact1(idimn)=cmplx(1.,0.)    !rusheweiyi
                    dfact2(idimn)=2.*cmplx(0.,-ttime)    !rushesudu
                endif
            end do
            do inode=1,nnode
                do idimn=1,ndimn
                    value_d((inode-1)*ndimn+idimn)=dfact1(idimn)
                    value_v((inode-1)*ndimn+idimn)=dfact2(idimn)
                end do
            end do
            ldofs=>tabss(ielem)%ldofs
            allocate(eload(size(ldofs)),estif(size(ldofs),size(ldofs)),estif0(size(ldofs),size(ldofs)))
            estif=cmplx(1.,0.)*tabss(ielem)%estif
            eload=matmul(estif,value_v)    !add
            toforw(ldofs)=toforw(ldofs)+eload

            estif0=cmplx(1.,0.)*tabss(ielem)%estif0
            eload=matmul(estif0,value_d)
            toforw(ldofs)=toforw(ldofs)+eload
            nullify(ldofs)
            deallocate(eload,estif,estif0)
            deallocate(dfact1,dfact2,value_d,value_v)
        endif
    end do

    end subroutine FORCE_EXTERNAL_w

    !! temperature

    subroutine assemble_boundt_estif

    character(10)fieldid
    integer(ink) ielgroup,iedge,aelem,ndofn,igroup,nrfields,idofn,jdofn,kdofn,ldofn,ifield
    integer(ink),pointer::ldofe(:)
    real(irk),pointer::edstif(:,:)
    do ielgroup=1,ntelgroup
        iedge=tedgeload(ielgroup)%iedge
        edstif=>tedgeload(ielgroup)%edstif
        aelem=tedges(iedge)%aelem
        ldofe=>tedges(iedge)%ldofe
        ndofn=size(ldofe)
        igroup=element(aelem)%group
        nrfields=group(igroup)%nrfields
        fieldid=group(igroup)%fieldid
        do ifield=1,nrfields
            if(fieldid(ifield:ifield)=='T')goto 1
        end do
1       do idofn=1,ndofn
            do jdofn=1,ndofn
                kdofn=ldofe(idofn)
                ldofn=ldofe(jdofn)
                element(aelem)%field(ifield)%khandmc(1)%fstif(kdofn,ldofn)=     &
                    element(aelem)%field(ifield)%khandmc(1)%fstif(kdofn,ldofn)+     &
                    edstif(idofn,jdofn)
            end do
        end do
        nullify(ldofe,edstif)
    end do

    end subroutine assemble_boundt_estif

    subroutine assemble_boundt_eload

    character(10)fieldid
    integer(ink) ielgroup,iedge,aelem,ndofn,igroup,nrfields,  &
        idofn,jdofn,ifield,itcurve
    integer(ink),pointer::ldofe(:)
    real(irk),pointer::edload(:)
    real(irk) dfact

    print *,'ntelgroup=',ntelgroup
    do ielgroup=1,ntelgroup
        iedge=tedgeload(ielgroup)%iedge
        edload=>tedgeload(ielgroup)%edload
        !      write(chkunit,*)'ielgroup=',ielgroup,'edload=',edload
        aelem=tedges(iedge)%aelem
        ldofe=>tedges(iedge)%ldofe
        ndofn=size(ldofe)
        igroup=element(aelem)%group
        nrfields=group(igroup)%nrfields
        fieldid=group(igroup)%fieldid
        itcurve=tedgeload(ielgroup)%itcurve
        dfact=tcurves(itcurve)%dfact
        do ifield=1,nrfields
            if(fieldid(ifield:ifield)=='T')exit
        end do
        do idofn=1,ndofn
            jdofn=ldofe(idofn)
            element(aelem)%field(ifield)%tload(jdofn)=     &
                element(aelem)%field(ifield)%tload(jdofn)+     &
                edload(idofn)*dfact
        end do
        nullify(ldofe,edload)
    end do

    end subroutine assemble_boundt_eload

    !! temperature

    !ifs2006 zhao, 06/03/29

    subroutine eload_ifs2006

    integer(ink) iedge,bkind,felem,igroup,nevab,nevabs,nevabf,nnode,inode,idimn,selem,jgroup,idofn,ndofn
    integer(ink) i0,i1,xdir,zdir,jpoin,npseczx,npsecxz,nsect  !20220330
    integer(ink),pointer::ldofs(:),ldofs_s(:),ldofs_f(:)
    real   (irk),pointer::matrix(:,:)
    real   (irk),allocatable::value(:),values(:),valuef(:)
    real   (irk) coef,accx,accz

    if(Icaddmass==3)then  !计算渡槽槽底中心线上水平加速度引起的竖向压力，以及槽底中心线上竖向加速度引起的侧向压力
        !20220330
        igroup=dwpre_aqu%aqu_group
        if(appear(igroup)==0) goto 10
        xdir=dwpre_aqu%xdir;zdir=dwpre_aqu%zdir;nsect=dwpre_aqu%nsect
        npseczx=dwpre_aqu%npseczx;npsecxz=dwpre_aqu%npsecxz
        dwpre_aqu%eloadzx=0.;dwpre_aqu%eloadxz=0.
        do i0=1,nsect
            jpoin=dwpre_aqu%jnode(i0)
            idofn=nodfn(xdir,jpoin)
            accx=result_second(idofn)+fachv(xdir)
            idofn=nodfn(zdir,jpoin)
            accz=result_second(idofn)+fachv(zdir)
            do i1=1,npseczx
                idofn=(i0-1)*npseczx+i1
                dwpre_aqu%eloadzx(idofn)=accx*dwpre_aqu%pzx(i1,i0)
            end do
            do i1=1,npsecxz
                idofn=(i0-1)*npsecxz+i1
                dwpre_aqu%eloadxz(idofn)=accz*dwpre_aqu%pxz(i1,i0)
            end do
        end do

10      continue
    endif  !20220330

    coef=-beeta2*ditime**2

    IF(IFSNEDGE==0)RETURN
    do iedge=1,ifsnedge
        ifsedges(iedge)%eload=0.
    enddo

    do iedge=1,ifsnedge !iedge
        bkind=ifsedges(iedge)%bkind
        if(bkind==2)cycle
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        if(appear(igroup)==0)cycle
        ldofs =>ifsedges(iedge)%ldofs
        matrix=>ifsedges(iedge)%matrix
        nevab=size(ldofs)
        allocate(value(nevab))
        if(bkind==1)value=result_second(ldofs)
        if(bkind==3.or.bkind==4)value=result_first(ldofs)
        ifsedges(iedge)%eload=matrix.x.value
        deallocate(value)
        nullify(matrix,ldofs)
    enddo

    do iedge=1,ifsnedge !iedge
        bkind=ifsedges(iedge)%bkind
        nnode=ifsedges(iedge)%nnode
        if(bkind/=2)cycle
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        selem=ifsedges(iedge)%selem
        jgroup=element(selem)%group
        if(appear(igroup)==0.or.appear(jgroup)==0)cycle
        ldofs =>ifsedges(iedge)%ldofs
        ldofs_s=>ifsedges(iedge)%ldofs_s
        ldofs_f=>ifsedges(iedge)%ldofs_f
        matrix=>ifsedges(iedge)%matrix
        nevab=size(ldofs)
        nevabs=size(ldofs_s)
        nevabf=size(ldofs_f)
        allocate(values(nevabs),valuef(nevabf))
        values=result_second(ldofs_s)
        !      do inode=1,nnode
        !         do idimn=1,ndimn
        !            idofn=(inode-1)*ndimn+idimn
        !            values(idofn)=values(idofn)+fachv(idimn)
        !         enddo
        !      enddo
        ndofn=group(jgroup)%dof(1)%nfdof
        do inode=1,nnode
            idofn=(inode-1)*ndofn
            values(idofn+1:idofn+ndimn)=values(idofn+1:idofn+ndimn)+fachv
        end do
        valuef=result_zero(ldofs_f)
        ifsedges(iedge)%eload(1:nevabs)=-transpose(matrix).x.valuef/coef
        ifsedges(iedge)%eload(nevabs+1:nevab)=matrix.x.values
        deallocate(values,valuef)
        nullify(matrix,ldofs,ldofs_s,ldofs_f)
    enddo

    end subroutine eload_ifs2006

    subroutine eload_ifs2006_w !ifs2006

    integer(ink) iedge,bkind,felem,igroup,nevab,nevabs,nevabf,nnode,inode,idimn,selem,jgroup,idofn,ndofn
    integer(ink),pointer::ldofs(:),ldofs_s(:),ldofs_f(:)
    complex(irk),allocatable::value(:),values(:),valuef(:),matrix(:,:)
    complex(irk) coef

    do iedge=1,ifsnedge
        ifsedges(iedge)%eload=0.
    enddo

    do iedge=1,ifsnedge !iedge
        bkind=ifsedges(iedge)%bkind
        if(bkind==2)cycle
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        if(appear(igroup)==0)cycle
        if(bkind==1)coef=cmplx(-1.0,0.)
        if(bkind==2)cycle
        if(bkind==3.or.bkind==4)coef=cmplx(0.,-1.0/ttime)
        ldofs =>ifsedges(iedge)%ldofs
        nevab=size(ldofs)
        allocate(value(nevab),matrix(nevab,nevab))
        matrix=coef*ifsedges(iedge)%matrix
        value=resultw(ldofs)
        stforw(ldofs)=stforw(ldofs)+matmul(matrix,value)
        deallocate(value,matrix)
        nullify(ldofs)
    enddo

    do iedge=1,ifsnedge !iedge
        bkind=ifsedges(iedge)%bkind
        nnode=ifsedges(iedge)%nnode
        if(bkind/=2)cycle
        coef=cmplx(-1.0,0.)
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        selem=ifsedges(iedge)%selem
        jgroup=element(selem)%group
        if(appear(igroup)==0.or.appear(jgroup)==0)cycle
        ldofs =>ifsedges(iedge)%ldofs
        ldofs_s=>ifsedges(iedge)%ldofs_s
        ldofs_f=>ifsedges(iedge)%ldofs_f
        nevab=size(ldofs)
        nevabs=size(ldofs_s)
        nevabf=size(ldofs_f)
        allocate(values(nevabs),valuef(nevabf),matrix(nevabf,nevabs))
        matrix=coef*ifsedges(iedge)%matrix
        values=resultw(ldofs_s)
        valuef=resultw(ldofs_f)
        stforw(ldofs_s)=stforw(ldofs_s)+matmul(transpose(matrix),valuef)
        stforw(ldofs_f)=stforw(ldofs_f)+matmul(matrix,values)
        deallocate(values,valuef,matrix)
        nullify(ldofs,ldofs_s,ldofs_f)
    enddo

    end subroutine eload_ifs2006_w

    !!ifs2000
    !****


    subroutine eload_interface_fluid_solid
    integer(ink) ielem,aelemf,aelems,igroup,jgroup,nevab,  &
        idofn,ipea1,ipea2,nnode,idimn
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    real   (irk),allocatable::value(:)
    real   (irk) coef

    coef=theta1*ditime

    do ielem=1,nifsgroup
        tifs(ielem)%eload=0.
        aelemf=tifs(ielem)%aelemf
        aelems=tifs(ielem)%aelems
        ipea1=0
        igroup=element(aelemf)%group
        if(appear(igroup)>0)ipea1=1
        ipea2=1
        if (aelems/=0) then
            jgroup=element(aelems)%group
            if(appear(igroup)<=0)ipea2=0
        endif
        if (ipea1==1.and.ipea2==1) then
            ldofs=>tifs(ielem)%ldofs
            estif=>tifs(ielem)%estif
            nevab=size(ldofs)
            allocate(value(nevab))
            nnode=size(tifs(ielem)%lnods)
            !do idofn=1,nnode*ndimn
            !value(idofn)=coef*result_second(ldofs(idofn))
            !end do
            !zhao
            do inode=1,nnode
                do idimn=1,ndimn
                    idofn=(inode-1)*ndimn+idimn
                    value(idofn)=coef*(result_second(ldofs(idofn))+fachv(idimn))
                enddo
            enddo

            do idofn=nnode*ndimn+1,nevab
                value(idofn)=result_zero(ldofs(idofn))
            end do
            tifs(ielem)%eload=estif.x.value
            deallocate(value)
            nullify(ldofs,estif)
        endif
    end do

    end subroutine eload_interface_fluid_solid

    subroutine eload_interface_fs_w !freq2006
    integer(ink) ielem,aelemf,aelems,igroup,jgroup,nevab,idofn,ipea1,ipea2,nnode
    integer(ink),pointer::ldofs(:)
    complex(irk),allocatable::value(:),estif(:,:)
    complex(irk) coef

    coef=cmplx(1.,0.)

    do ielem=1,nifsgroup
        aelemf=tifs(ielem)%aelemf
        aelems=tifs(ielem)%aelems
        ipea1=0
        igroup=element(aelemf)%group
        if(appear(igroup)>0)ipea1=1
        ipea2=1
        if (aelems/=0) then
            jgroup=element(aelems)%group
            if(appear(igroup)<=0)ipea2=0
        endif
        if(ipea1==1.and.ipea2==1) then
            ldofs=>tifs(ielem)%ldofs
            nevab=size(ldofs)
            allocate(value(nevab),estif(nevab,nevab))
            estif=coef*tifs(ielem)%estif
            do idofn=1,nevab
                value(idofn)=resultw(ldofs(idofn))
            end do
            stforw(ldofs)=stforw(ldofs)+matmul(estif,value)
            deallocate(value,estif)
            nullify(ldofs)
        endif
    end do

    end subroutine eload_interface_fs_w

    subroutine eload_absorb_fluid
    integer(ink) ielem,aelemf,igroup,nevab,ipea1
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    real   (irk),allocatable::value(:)
    real   (irk) coef

    coef=-theta1*ditime

    do ielem=1,nabsfgroup
        tabsf(ielem)%eload=0.
        aelemf=tabsf(ielem)%aelemf
        ipea1=0
        igroup=element(aelemf)%group
        if(appear(igroup)>0)ipea1=1
        if (ipea1==1) then
            ldofs=>tabsf(ielem)%ldofs
            estif=>tabsf(ielem)%estif
            nevab=size(ldofs)
            allocate(value(nevab))
            value=coef*result_first(ldofs)
            tabsf(ielem)%eload=estif.x.value
            deallocate(value)
            nullify(ldofs,estif)
        endif
    end do

    end subroutine eload_absorb_fluid

    subroutine eload_absorb_fluid_w !freq2006

    integer(ink) ielem,aelemf,igroup,nevab,ipea1
    integer(ink),pointer::ldofs(:)
    complex(irk),allocatable::value(:),estif(:,:)
    complex(irk) coef

    coef=-cmplx(0.,ttime)/(ttime**2)

    do ielem=1,nabsfgroup
        aelemf=tabsf(ielem)%aelemf
        ipea1=0
        igroup=element(aelemf)%group
        if(appear(igroup)>0)ipea1=1
        if (ipea1==1) then
            ldofs=>tabsf(ielem)%ldofs
            nevab=size(ldofs)
            allocate(value(nevab),estif(nevab,nevab))
            estif=coef*tabsf(ielem)%estif
            value=resultw(ldofs)
            stforw(ldofs)=stforw(ldofs)+matmul(estif,value)
            deallocate(value,estif)
            nullify(ldofs)
        endif
    end do

    end subroutine eload_absorb_fluid_w

    subroutine eload_absorb_solid

    integer(ink) ielem,aelems,igroup,ipea1
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:),estif0(:,:)
    real   (irk),allocatable::value(:),eload(:)

    do ielem=1,nabssgroup
        tabss(ielem)%eload=0.
        aelems=tabss(ielem)%aelems
        ipea1=0
        igroup=element(aelems)%group
        if(appear(igroup)>0)ipea1=1

        if (ipea1==1) then

            ldofs=>tabss(ielem)%ldofs
            allocate(value(size(ldofs)),eload(size(ldofs)))
            estif=>tabss(ielem)%estif
            value=result_first(ldofs)
            tabss(ielem)%eload=estif.x.value
            estif0=>tabss(ielem)%estif0
            value=result_zero(ldofs)
            eload=estif0.x.value
            tabss(ielem)%eload=tabss(ielem)%eload+eload
            nullify(ldofs,estif,estif0)
            deallocate(value,eload)
        endif
    end do
    end subroutine eload_absorb_solid


    subroutine eload_back_spring  !20150925

    integer(ink) ielem,itotv

    real   (irk) stif_spring

    do ielem=1,nbspring
        itotv=bspring(ielem)%listdof
        stif_spring=bspring(ielem)%spring
        bspring(ielem)%eload=stif_spring*result_zero(itotv)

    end do
    end subroutine eload_back_spring !20150925

    subroutine eload_absorb_solid_w !freq2006

    integer(ink) ielem,aelems,igroup,ipea1
    integer(ink),pointer::ldofs(:)
    complex(irk),allocatable::value(:),estif(:,:),estif0(:,:)
    complex(irk) coef,coef0

    coef=cmplx(0.,-ttime)
    coef0=cmplx(1.,0.)          !

    do ielem=1,nabssgroup
        aelems=tabss(ielem)%aelems
        ipea1=0
        igroup=element(aelems)%group
        if(appear(igroup)>0)ipea1=1

        if (ipea1==1) then

            ldofs=>tabss(ielem)%ldofs
            allocate(value(size(ldofs)),estif(size(ldofs),size(ldofs)),estif0(size(ldofs),size(ldofs)))
            estif=coef*tabss(ielem)%estif
            value=resultw(ldofs)
            stforw(ldofs)=stforw(ldofs)+matmul(estif,value)
            estif0=coef0*tabss(ielem)%estif0
            value=resultw(ldofs)
            stforw(ldofs)=stforw(ldofs)+matmul(estif0,value)

            nullify(ldofs)
            deallocate(value,estif,estif0)

        endif
    end do

    end subroutine eload_absorb_solid_w
    !****

    !!ifs2000
    subroutine FORCE_INTERNAL

    integer(ink) ifield,ielem,nrfields,itotv,ndofn,iedge, &
        inode,ipoin,np_unode,matno,idimn,felem,imcon,   &       !! stablize
        i0,i1,ipairs,npairs_wc,nline_g_w

    real   (irk) xxxx,coef1
    character(10)fieldid,name                    !! stablize
    integer(ink),pointer::ldofe(:),lnods(:),pairnode_wc(:)  !20210417
    real   (irk),pointer::eload(:),ks(:,:)  !20210417
    real   (irk),allocatable::value(:),heat_wc(:)  !20210417

    stfor=0.0
    if(allocated(floai))floai=0.
    !! add tload to tofor
    do ielem=1,nelem
        igroup=element(ielem)%group
        if (appear(igroup)>0.and.ice0(ielem)/=1) then    !
            fieldid= group(igroup)%fieldid
            nrfields=element(ielem)%nrfields
            do ifield=1,nrfields
                if (associated(element(ielem)%field(ifield)%eload)) then
                    eload=> element(ielem)%field(ifield)%eload
                    ldofe=>element(ielem)%field(ifield)%ldofs_f
                    if (fieldid=='UW'.and.allocated(floai).and.ifield==1)then  !!nstoks
                        matno = group(igroup)%matno
                        name=props(matno)%name
                        if(name=='NSTOKS')floai(ldofe)=floai(ldofe)+eload
                    endif
                    ndofn=size(ldofe)
                    do itotv=1,ndofn
                        stfor(ldofe(itotv))=stfor(ldofe(itotv))+eload(itotv)
                        ! if(ldofe(itotv)==5218) &
                        !write(7,*)'ielem=',ielem,'ifield=',ifield,'idofn=',itotv,'stfor=',stfor(ldofe(itotv)),'eload=',eload(itotv)
                    end do
                    nullify(eload,ldofe)
                end if
            end do
        endif               !
    end do
    !ifs2006 zhao, 06/03/29 , icaddmass
    if (icaddmass/=0)then
        do ipoin=1,npoin
            if(icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxxx=result_second(itotv)
                stfor(itotv)=stfor(itotv)+addmp(idimn,ipoin)*xxxx
            enddo
        enddo
        if(icaddmass==3)then   !20220330

            igroup=dwpre_aqu%aqu_group
            if(appear(igroup)/=0)then
                ldofe=>dwpre_aqu%ldofszx
                eload=>dwpre_aqu%eloadzx
                stfor(ldofe)=stfor(ldofe)+eload
                nullify(ldofe,eload)

                ldofe=>dwpre_aqu%ldofsxz
                eload=>dwpre_aqu%eloadxz
                stfor(ldofe)=stfor(ldofe)+eload
                nullify(ldofe,eload)

            endif
        endif !20220330

    endif
    !2013/4/12

    if (nbspring>0)then  !20150925
        do imcon=1,nbspring
            itotv=bspring(imcon)%listdof
            if(itotv==0)cycle
            stfor(itotv)=stfor(itotv)+bspring(imcon)%eload
        enddo
    endif      !20150925

    if (nmcon/=0)then
        do imcon=1,nmcon
            ipoin=lmcon(imcon)
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxxx=result_second(itotv)
                stfor(itotv)=stfor(itotv)+rmcon(idimn,imcon)*xxxx
            enddo
        enddo
    endif


    !!!!1
    if (rmesh>0)then
        do ielem=1,nelem1
            igroup=element1(ielem)%group
            if (appear(igroup)>0.and.jce1(ielem)/=1) then    !

                fieldid= group(igroup)%fieldid
                nrfields=element1(ielem)%nrfields
                do ifield=1,nrfields
                    if (associated(element1(ielem)%field(ifield)%eload)) then
                        eload=>element1(ielem)%field(ifield)%eload
                        ldofe=>element1(ielem)%field(ifield)%ldofs_f
                        !write(7,*)'ie=',ielem,'eload=',eload
                        ndofn=size(ldofe)
                        do itotv=1,ndofn
                            stfor(ldofe(itotv))=stfor(ldofe(itotv))+eload(itotv)
                        end do
                        nullify(eload,ldofe)
                    end if
                end do

            endif               !
        end do
    endif

    !!!!2
    if (rmesh>1)then
        do ielem=1,nelem2
            igroup=element2(ielem)%group
            if (appear(igroup)>0) then    !

                fieldid= group(igroup)%fieldid
                nrfields=element2(ielem)%nrfields
                do ifield=1,nrfields
                    if (associated(element2(ielem)%field(ifield)%eload)) then
                        eload=>element2(ielem)%field(ifield)%eload
                        ldofe=>element2(ielem)%field(ifield)%ldofs_f
                        ndofn=size(ldofe)
                        do itotv=1,ndofn
                            stfor(ldofe(itotv))=stfor(ldofe(itotv))+eload(itotv)
                        end do
                        nullify(eload,ldofe)
                    end if
                end do

            endif               !
        end do
    endif

    !!ifs2000
    do ielem=1,nifsgroup
        ldofe=> tifs(ielem)%ldofs
        eload=> tifs(ielem)%eload
        stfor(ldofe)=stfor(ldofe)+eload
        nullify(ldofe,eload)
    end do
    do ielem=1,nabsfgroup
        ldofe=> tabsf(ielem)%ldofs
        eload=> tabsf(ielem)%eload
        stfor(ldofe)=stfor(ldofe)+eload

        nullify(ldofe,eload)
    end do
    do ielem=1,nabssgroup
        ldofe=> tabss(ielem)%ldofs
        eload=> tabss(ielem)%eload
        stfor(ldofe)=stfor(ldofe)+eload
        !write(7,*)'ielem=',ielem,'eload=',eload,'stfor=',stfor(ldofe)

        nullify(ldofe,eload)
    end do

    !!ifs2000

    !ifs2006 zhao, 06/03/29
    if(icaddmass==0)then    !20231215YL 对附加质量法不需要以下集成
        do iedge=1,ifsnedge
            felem=ifsedges(iedge)%felem
            igroup=element(felem)%group
            if(appear(igroup)==0)cycle
            ldofe=>ifsedges(iedge)%ldofs
            eload=>ifsedges(iedge)%eload
            stfor(ldofe)=stfor(ldofe)+eload
            nullify(ldofe,eload)
        enddo
    endif
    !! stablize
    if (stabpw==1) then
        do igroup=1,ngroup
            fieldid=group(igroup)%fieldid
            if (appear(igroup)>0.and.(fieldid(1:2)=='UP'.or.fieldid(1:2)=='UW')) then

                do ipoin=1,group(igroup)%np_unode
                    np_unode=group(igroup)%unode(ipoin)%np_unode
                    if (np_unode/=0) then
                        eload=>group(igroup)%unode(ipoin)%patch_load
                        lnods=>group(igroup)%unode(ipoin)%patch_nod
                        do inode=1,np_unode
                            itotv=nodfn(ndimn+1,lnods(inode))
                            stfor(itotv)=stfor(itotv)+eload(inode)
                        end do
                        nullify(eload,lnods)
                    endif
                end do
            endif
        end do
    endif
    !! end of stablize

    if (ground_inf/=0) then
        stfor(ldofs_space)=stfor(ldofs_space)+eload_space
    endif

    if(nwcpipe/=0)then !20210417
        do i0=1,nwcpipe
            nline_g_w=wc_pipe(i0)%nline_g_w
            coef1= wc_pipe(i0)%iwc

            do i1=1,nline_g_w
                npairs_wc=wc_pipe(i0)%line_g_w(i1)%npairs_wc
                allocate(value(npairs_wc),heat_wc(npairs_wc))
                pairnode_wc=>wc_pipe(i0)%line_g_w(i1)%pairnode_wc
                value=0.;heat_wc=0.
                do ipairs=1,npairs_wc
                    itotv=nodfn(lmdofn(10),pairnode_wc(ipairs))
                    if(itotv/=0) &
                        value(ipairs)=result_zero(itotv)
                end do
                !write(7,*)'value=',value
                Ks=>wc_pipe(i0)%line_g_w(i1)%kmatrix_w
                heat_wc=Ks.x.value
                heat_wc=coef1*heat_wc

                do ipairs=1,npairs_wc
                    itotv=nodfn(lmdofn(10),pairnode_wc(ipairs))
                    if(itotv/=0) &
                        stfor(itotv)=stfor(itotv)+heat_wc(ipairs)
                end do
                deallocate(value,heat_wc)
                nullify(Ks,pairnode_wc)
            end do
        end do

    endif  !20210417


    end subroutine FORCE_INTERNAL



    subroutine force_release

    integer(ink) ifield,ielem,nrfields,itotv,ndofn
    integer(ink),pointer::ldofe(:)
    real   (irk),pointer::eload(:)
    integer(ink),allocatable::id(:)


    !! add tload to torel
    do ielem=1,nelem
        igroup=element(ielem)%group
        if (appear(igroup)==-1.or.appear(igroup)==2) then    !

            !write(chkunit,*)'igroup=',igroup,'ielem=',ielem
            nrfields=element(ielem)%nrfields
            do ifield=1,nrfields
                if (associated(element(ielem)%field(ifield)%eload)) then
                    eload=> element(ielem)%field(ifield)%eload
                    ldofe=>element(ielem)%field(ifield)%ldofs_f
                    ndofn=size(ldofe)
                    do itotv=1,ndofn
                        torel(ldofe(itotv))=torel(ldofe(itotv))+eload(itotv)
                    end do
                    !write(chkunit,*)'eload=',eload
                    nullify(eload,ldofe)
                end if
            end do

        endif               !
    end do

    allocate(id(ntotv))
    id=0

    do ielem=1,nelem
        igroup=element(ielem)%group
        if (appear(igroup)==1) then    !

            nrfields=element(ielem)%nrfields
            do ifield=1,nrfields
                ldofe=>element(ielem)%field(ifield)%ldofs_f
                id(ldofe)=1
                nullify(ldofe)
            end do

        endif               !
    end do

    do itotv=1,ntotv
        if(id(itotv)==0)torel(itotv)=0.
    end do
    deallocate(id)

    end  subroutine FORCE_release

    subroutine ELOAD_INITIALIZE

    integer(ink) ifield,ielem,nrfields,igroup
    character(10) fieldi,fieldid

    do ielem=1,nelem
        igroup=element(ielem)%group
        if (appear(igroup)>0.and.ice0(ielem)/=1) then    !
            if(associated(element(ielem)%rh))element(ielem)%rh=0.

            nrfields=element(ielem)%nrfields
            fieldid=group(igroup)%fieldid
            do ifield=1,nrfields
                fieldi=fieldid(ifield:ifield)
                element(ielem)%field(ifield)%eload=0.0_irk
            end do

        endif               !
    end do

    if (rmesh>0)then
        do ielem=1,nelem1
            igroup=element1(ielem)%group
            if (appear(igroup)>0.and.jce1(ielem)/=1) then    !
                !if(associated(element1(ielem)%rh))element1(ielem)%rh=0.

                nrfields=element1(ielem)%nrfields
                do ifield=1,nrfields
                    element1(ielem)%field(ifield)%eload=0.0_irk
                end do

            endif               !
        end do
    endif

    if (rmesh>1)then
        do ielem=1,nelem2
            igroup=element2(ielem)%group
            if (appear(igroup)>0) then    !
                !if(associated(element2(ielem)%rh))element2(ielem)%rh=0.

                nrfields=element2(ielem)%nrfields
                do ifield=1,nrfields
                    element2(ielem)%field(ifield)%eload=0.0_irk
                end do

            endif               !
        end do
    endif

    end   subroutine ELOAD_INITIALIZE

    !20231215YL
    subroutine read_permanent_strain !20231010
    real(irk), allocatable::sigma0(:),dmatx(:,:),strain0(:)
    character(30)text,SPtype*10
    integer(ink) ingroup,ilgroup,ielem,igaus,ie,ig,index,order_int,ngaus,nstre,nelgroup
    real(irk) mu,Emoduls
    SPtype='PE'

    read(stnunit,*)text
    if(iblks==1)element(:)%icper=0
    read(stnunit,*)ingroup

    do ilgroup=1,ingroup
        read(stnunit,*)igroup
        index=group(igroup)%index
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        ngaus=elkn(index)%ggaus(order_int)%ngaus
        nstre=group(igroup)%nstre
        allocate(sigma0(nstre),dmatx(nstre,nstre),strain0(nstre))
        strain0=0.0;sigma0=0.0;dmatx=0.0
        do ie=1,group(igroup)%nelgroup
            ielem=group(igroup)%list(ie)
            if(iblks==1)then
                allocate(element(ielem)%strainx0(nstre,ngaus))
                element(ielem)%strainx0=0.0
            endif

            element(ielem)%icper=1
            do igaus=1,ngaus
                read(stnunit,*)i0,ig,strain0
                strain0=-1*strain0
                element(ielem)%strainx0(:,igaus)=strain0
            enddo	 !end do igaus
        enddo   !end do ie
        deallocate(sigma0,dmatx,strain0)
    enddo  !end do ilgroup

    end subroutine read_permanent_strain
    !20231215YL

    subroutine read_initial

    character(30)text,name,material,field1,model
    integer(ink) iinit,ingroup,igroup,ielem,igaus,i0,ie,ipoin,i1,i2,jdimn
    integer(ink) index,order_int,ngaus,nstre,nelgroup,ilgroup,matno,ngvar
    integer(ink) igaps,ipairs,npairs,unitread,kinit_g !20211214
    real(irk)    coef1,coef2,aera
    real(irk),   allocatable::sigma0(:),stres_poin(:,:),rr0(:,:),rr(:,:),  &
        tt(:,:),sgtot(:),sgloc(:),tti(:,:),sigma1(:),trot(:,:)  !20200330

    integer(ink) indofix,idofix,jdofix,totvi,ordert,vdimn,jndex,order_jnt
    real   (irk) rdofix
    real(irk),pointer::rotation(:,:)

    integer(ink) icdofn,inpoin,idofn,jpoin,idimn
    integer(ink),allocatable::ilmdofn(:),ilcdofn(:),order(:)
    real   (irk),allocatable::vinit(:)

    unitread=initunit  !20210207
    if(winit==1)unitread=initwunit !20210207
    rewind(unitread)  !20230708


    do iinit=1,ninit

        read(unitread,*)text
        write(7,*)'iinit=',iinit,'text=',text

        select case(text)

        case('STRESS')      !! for initial stresses

            read(unitread,*)ingroup,kinit_g !20211214
            do ilgroup=1,ingroup
                !if (kinit==1) then
                !   read(unitread,*)igroup,vdimn,coef1,coef2
                !else if(kinit==2) then
                read(unitread,*)igroup,vdimn,coef1,coef2
                !end if
                index=group(igroup)%index
                group(igroup)%kinit_g=kinit_g  !20211214

                write(7,*)'read_initial igroup=',igroup,'kinit_g=',kinit_g
                order_int=elkn(index)%el_field(1)%order_intrules(1)

                if(index==20.or.index==21)then
                    ngaus=1
                    ngvar=3
                    if(ndimn==3)then
                        ngvar=6
                    endif
                    nstre=ngvar
                else
                    ngaus=elkn(index)%ggaus(order_int)%ngaus

                    field1= group(igroup)%fieldid(1:1)
                    if(field1=='U')then
                        matno = group(igroup)%matno
                        material=props(matno)%mechanical%solid%material

                        if (material=='GOODMAN') then   !! 20210207
                            jndex=1
                            if (ndimn==3.and.index==9)jndex=5
                            if (ndimn==3.and.index==23)jndex=3
                            order_jnt=elkn(jndex)%el_field(1)%order_intrules(1)
                            ngaus=elkn(jndex)%ggaus(order_jnt)%ngaus
                            model=props(matno)%mechanical%solid%Goodman%model
                        endif               !! 20210207
                    endif

                    nstre=group(igroup)%nstre
                    ngvar=group(igroup)%ngvar
                endif
                matno = group(igroup)%matno
                name=props(matno)%name
                allocate(sigma0(ngvar))
                if(index==20.or.index==21)allocate(sigma1(ngvar),trot(ngvar,ngvar))
                nelgroup=group(igroup)%nelgroup
                do ielem=1,nelgroup
                    ie = group(igroup)%list(ielem)
                    do igaus=1,ngaus
                        sigma0=0.
                        !if (name=='CONTACT')then  !20210207
                        !   sigma0(1:ndimn)=.02
                        !else
                        !read(unitread,*)i0,sigma0  !20220712
                        !read(unitread,*)i0,i1,sigma0(1:nstre)  !20231215YL
                        read(unitread,*)i0,i1,sigma0(1:ngvar)  !20231215YL
                        !endif  !20210207

                        if (vdimn/=0) then !!!!!!!!!!

                            if (ndimn==2) then
                                if(vdimn==2)then
                                    sigma0(1)=coef1*sigma0(2)
                                    sigma0(4)=coef2*sigma0(2)
                                elseif(vdimn==1)then
                                    sigma0(2)=coef1*sigma0(1)
                                    sigma0(4)=coef2*sigma0(1)
                                endif
                                sigma0(3)=0.0
                            else if(ndimn==3) then
                                if(vdimn==3)then
                                    sigma0(1)=coef1*sigma0(3)
                                    sigma0(2)=coef2*sigma0(3)
                                elseif(vdimn==2)then
                                    sigma0(1)=coef1*sigma0(2)
                                    sigma0(3)=coef2*sigma0(2)
                                elseif(vdimn==1)then
                                    sigma0(2)=coef1*sigma0(1)
                                    sigma0(3)=coef2*sigma0(1)
                                endif

                                sigma0(4:6)=0.0
                            endif

                        endif
                        !write(7,*) 'ig=',igroup,'ie=',ie,'size1=',size(element(ie)%stres0(:,igaus)),'nstre=',nstre
                        !write(7,*)'sigma0=',sigma0
                        if(kinit_g==2.and.index/=20.and.index/=21)element(ie)%stres0(:,igaus)=sigma0(1:nstre)

                        if(index==20.or.index==21)then
                            rotation=>element(ie)%rotation
                            trot=0.
                            if (ndimn==2)then
                                trot(1:ndimn,1:ndimn)=transpose(rotation)
                                trot(3,3)=1.
                            else if(ndimn==3) then
                                trot(1:3,1:3)=transpose(rotation); trot(4:6,4:6)=transpose(rotation)
                            end if
                            sigma1=trot.x.sigma0
                            element(ie)%field(1)%gpvar(1:ngvar,igaus)=-sigma1
                            element(ie)%field(1)%gpvar(ngvar+1:ngvar*2,igaus)=sigma1
                            element(ie)%field(1)%gpvar0=element(ie)%field(1)%gpvar
                            if(kinit_g==2) &
                                element(ie)%stres0=element(ie)%field(1)%gpvar  !20201203
                            nullify(rotation)
                        else

                            element(ie)%field(1)%gpvar(1:ngvar,igaus)=sigma0
                            element(ie)%field(1)%gpvar0(1:ngvar,igaus)=sigma0
                        endif
                    end do
                end do
                if (model(1:3)=='FCM')then
                    do ielem=1,nelgroup
                        ie = group(igroup)%list(ielem)
                        read(unitread,*)i0,element(ie)%field(1)%strain
                        element(ie)%field(1)%strain0=element(ie)%field(1)%strain
                    enddo
                endif
                deallocate(sigma0)
                if(index==20.or.index==21)deallocate(sigma1,trot)
            end do          !!   for do ingroup

        case('INTERNAL_FORCE_BEAM') !20210207

            read(unitread,*)ingroup,kinit_g !20211214
            print *, 'ingroup=',ingroup
            DO ilgroup =1,ingroup
                read(unitread,*)igroup
                index=group(igroup)%index
                print*,'igroup=',igroup,'index=',index
                if(index/=20.and.index/=21) then
                    print *,'stop in read_initial_INTERNAL_FORCE_BEAM'
                    stop
                endif
                ngaus=1
                nstre=6
                if(ndimn==3)nstre=12
                print *,'nstre=',nstre
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    read(unitread,*)i0,element(ielem)%field(1)%gpvar(1:nstre,1)
                    element(ielem)%field(1)%gpvar0=element(ielem)%field(1)%gpvar
                    if(kinit_g==2) &
                        element(ielem)%stres0=element(ielem)%field(1)%gpvar  !20201203
                end do
            end do
        case('STRESS_BOND_SLIP') !20210207

            read(unitread,*)ingroup,kinit_g !20211214
            DO ilgroup =1,ingroup
                read(unitread,*)igroup
                index=group(igroup)%index
                if(index/=25) then
                    print *,'stop in read_initial-STRESS_BOND_SLIP'
                    stop
                endif
                ngvar=2*ndimn
                ngaus=1
                nstre=ngvar
                ngvar=ngvar+5 !ngvar+1--for gaptao, ngvar+2--for gapnorm ,ngvar+3--for Ks, ngvar+4--for steel strain
                !ngvar+5--for state 0-close 1-open , integer it first! for lhg ngvar+6 ic_yty

                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    read(unitread,*)i0,element(ielem)%field(1)%gpvar(1:ngvar,1)
                    element(ielem)%field(1)%gpvar0=element(ielem)%field(1)%gpvar
                    if(kinit_g==2) &
                        element(ielem)%stres0(1:nstre,1)=element(ielem)%field(1)%gpvar(1:nstre,1)  !20210207
                end do

            end do

        case('CONTACT_STATE') !zhao 05/07/19 !contact
            read(unitread,*)ingroup
            DO ilgroup =1,ingroup
                read(unitread,*)igroup
                field1= group(igroup)%fieldid
                index = group(igroup)%index
                if (appear_process(igroup,iblks)>0.and.field1=='U')  then
                    matno = group(igroup)%matno
                    name  = props(matno)%name
                    if (name/='CONTACT')then
                        print *,'stop in read_initial-CONTACT'
                        stop
                    endif

                    material=props(matno)%mechanical%solid%material
                    if(material=='GOODMAN')then
                        model=props(matno)%mechanical%solid%Goodman%model
                    endif

                    !! contact
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        read(unitread,*)i0,element(ielem)%field(1)%gapn
                        read(unitread,*)i0,element(ielem)%field(1)%gapg
                        read(unitread,*)i0,element(ielem)%field(1)%state

                        if (model(1:3)=='FCM')then
                            read(unitread,*)i0,element(ielem)%field(1)%strain
                            element(ielem)%field(1)%strain0=element(ielem)%field(1)%strain
                        endif

                        element(ielem)%field(1)%gapn0=element(ielem)%field(1)%gapn
                        element(ielem)%field(1)%gapg0=element(ielem)%field(1)%gapg
                        element(ielem)%field(1)%state0=element(ielem)%field(1)%state
                        element(ielem)%field(1)%state1=element(ielem)%field(1)%state


                        !write(chkunit,'(i10,30e14.5)')ielem,element(ielem)%field(1)%gapn
                        !write(chkunit,'(i10,30e14.5)')ielem,element(ielem)%field(1)%gapg
                        !write(chkunit,'(i10,5x,30a10)')ielem,element(ielem)%field(1)%state
                    end do
                endif
            enddo

        case('CONTACTCTT') !ctt2005 zhao 05/09/07

            if(block_stab==2)then   !20200330
                allocate(stres_poin(3*(ndimn-1),npoin))
                read(unitread,*)text
                read(unitread,*)coef1
                do ipoin=1,npoin
                    read(unitread,*)i0,stres_poin(:,ipoin)
                end do
                stres_poin=stres_poin*coef1

                allocate(rr0(ndimn,ndimn),rr(ndimn+1,ndimn+1),tt(3*(ndimn-1),3*(ndimn-1)),  &
                    sgtot(3*(ndimn-1)),sgloc(3*(ndimn-1)),tti(3*(ndimn-1),3*(ndimn-1)))

                do igaps=1,ngaps
                    npairs=gaps(igaps)%npairs
                    do ipairs=1,npairs
                        i1=gaps(igaps)%pairnode(1,ipairs)
                        i2=gaps(igaps)%pairnode(2,ipairs)
                        sgtot=.5*(stres_poin(:,i1)+stres_poin(:,i2))
                        aera=gaps(igaps)%aera(ipairs)
                        rr0=gaps(igaps)%rot(:,:,ipairs)

                        rr(1:ndimn,1:ndimn)=rr0
                        rr(1:ndimn,ndimn+1)=rr(1:ndimn,1)
                        rr(ndimn+1,1:ndimn)=rr(1,1:ndimn)
                        rr(ndimn+1,ndimn+1)=rr(1,1)

                        tt=0.0
                        tt(1:ndimn,1:ndimn)=rr**2

                        tti=0.
                        tti(1:ndimn,1:ndimn)=(transpose(rr))**2
                        if (ndimn==2) then
                            tt(1,3)=2*rr(1,1)*rr(1,2)
                            tt(2,3)=2*rr(2,1)*rr(2,2)
                            tt(3,1)=rr(1,1)*rr(2,1)
                            tt(3,2)=rr(1,2)*rr(2,2)
                            tt(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)


                            tti(3,1)=rr(1,1)*rr(1,2)
                            tti(3,2)=rr(2,1)*rr(2,2)
                            tti(1,3)=2*rr(1,1)*rr(2,1)
                            tti(2,3)=2*rr(1,2)*rr(2,2)
                            tti(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)
                        else if(ndimn==3) then

                            do idimn=1,ndimn
                                do jdimn=1,ndimn
                                    tt(idimn,3+jdimn)=2*rr(idimn,jdimn)*rr(idimn,jdimn+1)
                                    tt(3+idimn,jdimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn)
                                    tt(3+idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                                        rr(idimn+1,jdimn)*rr(idimn,jdimn+1)

                                    tti(3+jdimn,idimn)=rr(idimn,jdimn)*rr(idimn,jdimn+1)
                                    tti(jdimn,3+idimn)=2*rr(idimn,jdimn)*rr(idimn+1,jdimn)
                                    tti(3+jdimn,3+idimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                                        rr(idimn+1,jdimn)*rr(idimn,jdimn+1)
                                end do
                            end do
                        endif

                        sgloc=tt.x.sgtot
                        gaps(igaps)%ctforce0(ndimn,ipairs)=sgloc(ndimn)*aera
                        if(ndimn==2)then
                            gaps(igaps)%ctforce0(1,ipairs)=sgloc(ndimn+1)*aera
                        elseif(ndimn==3)then
                            gaps(igaps)%ctforce0(1,ipairs)=sgloc(6)*aera
                            gaps(igaps)%ctforce0(2,ipairs)=sgloc(5)*aera
                        endif

                        gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                        gaps(igaps)%state(ipairs)=1
                        gaps(igaps)%state0(ipairs)=1
                        !write(7,*)'ipairs=',ipairs,'ctforce=',gaps(igaps)%ctforce(:,ipairs)


                    end do
                end do
                deallocate(rr0,rr,tt,sgtot,sgloc,tti)


            else !20200330
                do igaps=1,ngaps
                    npairs=gaps(igaps)%npairs
                    do ipairs=1,npairs
                        if(kstab/=0.)then
                            read(unitread,*)i0,i0,gaps(igaps)%ctforce0(:,ipairs),gaps(igaps)%gap0(ndimn,ipairs), &
                                gaps(igaps)%state0(ipairs) !,gaps(igaps)%ft(ipairs),(gaps(igaps)%kxyz(idimn,idimn,ipairs),idimn=1,3*(ndimn-1))
                            gaps(igaps)%state0(ipairs)=1
                        else
                            read(unitread,*)i0,i0,gaps(igaps)%ctforce0(:,ipairs),gaps(igaps)%gap0(ndimn,ipairs), &
                                gaps(igaps)%state0(ipairs),gaps(igaps)%ft(ipairs),(gaps(igaps)%kxyz(idimn,idimn,ipairs),idimn=1,ndimn)
                        endif
                        gaps(igaps)%gap(ndimn,ipairs)            =gaps(igaps)%gap0(ndimn,ipairs)
                        gaps(igaps)%state(ipairs)          =gaps(igaps)%state0(ipairs)
                        gaps(igaps)%ctforce(1:ndimn,ipairs)=gaps(igaps)%ctforce0(1:ndimn,ipairs)
                        !write(7,*)'ipairs=',ipairs,'ctforce=', gaps(igaps)%ctforce(1:ndimn,ipairs),'state=',gaps(igaps)%state(ipairs)
                        if(kinit==2)gaps(igaps)%ctforce_stres0(1:ndimn,ipairs)=gaps(igaps)%ctforce0(1:ndimn,ipairs) !2019/03/19
                        !if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                        ! gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup1(1,1)  !柔度系数取大值模拟自由滑动
                        !if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup1(2,2)  !柔度系数取大值模拟自由滑动
                        !end if
                    enddo
                enddo
            endif !20200330
        case('REACTION')      !! for initial reactions

            read(unitread,*)indofix
            do jdofix=1,indofix
                read(unitread,*)idofix,rdofix
                prescrib(idofix)%rdofix=rdofix
            end do

            case default    !! for initial(Ux,Uy,Uz,Thxy,....)
            !! it could be velocity or acceleration
            allocate(ilmdofn(mdofn),ilcdofn(mdofn),order(1:mdofn))
            read(unitread,*)i0,inpoin
            read(unitread,*)ilmdofn(1:mdofn)
            read(unitread,*)order(1:mdofn)
            icdofn=0
            do idofn=1,mdofn
                if (ilmdofn(idofn)/=0) then
                    icdofn=icdofn+1
                    ilcdofn(icdofn)=idofn
                endif
            end do
            allocate(vinit(icdofn))

            !write(7,*)'ipoin,idofn,totvi,result_zero(totvi)='
            do jpoin=1,inpoin
                read(unitread,*)ipoin,vinit

                do idofn=1,icdofn
                    totvi=nodfn(lmdofn(ilcdofn(idofn)),ipoin)

                    if(ilcdofn(idofn)==8) then  !20230331
                        if(vinit(idofn)<=0)vinit(idofn)=0.
                    endif !20230331
                    ordert=order(ilcdofn(idofn))
                    if (ordert==0.and.totvi/=0)then
                        result_zero(totvi)=vinit(idofn)
                        !write(7,*)ipoin,idofn,totvi,result_zero(totvi)

                    elseif(ordert==1)then
                        result_first(totvi)=vinit(idofn)
                    elseif(ordert==2)then
                        result_second(totvi)=vinit(idofn)
                    endif

                    !            if(ilcdofn(idofn)/=8.and.ordert==0.and.totvi/=0) result_zero(totvi)=0. !special zhao

                    !! initial pore pressure
                    !if(type_problem=='F'.and.(ilcdofn(idofn)==8.and.ordert==0)) prstat(ipoin)=vinit(idofn) !20221013
                    if(ilcdofn(idofn)==8.and.ordert==0) prstat(ipoin)=vinit(idofn) !20221013
                end do
            end do
1           continue
            deallocate(vinit,order)

        end select

    end do     !!!iinit

    end subroutine read_initial

    !====================================================================
    subroutine placement_temperature(result0)
    character(10) fieldid
    integer(ink) igroup,ic,ifield,matno,place_curve,ielgroup,ipoin,jpoin,nline_g_w,npairs_wc,  &
        ielem, nrfields,index,nnode,itotv,jtotv,iintf,nintf,i0,i1,iwc,twater_curve
    integer(ink), pointer::ldofs(:),pairnode_wc(:)
    real(irk),allocatable::result1(:)
    real(irk) ::result0(ntotv),dfact

    real   (irk) temperature,tp,tpave,tpele


    allocate(result1(ntotv))
    result0=result_zero;
    result1=result_zero;
    print*,'maxval(result_zero)=',maxval(result_zero)
    DO igroup =1,ngroup
        if(appear(igroup)<=0)cycle
        if(appear_process(igroup,iblks-1)==0.and.   &
            appear_process(igroup,iblks)==1) then

            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid

            ic=0

            do ifield=1,nrfields
                if(fieldid(ifield:ifield)=='T')then
                    ic=1
                    exit
                end if
            end do

            if(ic==1) then
                matno = group(igroup)%matno
                place_curve=props(matno)%heat%place_curve
                if(place_curve/=0) then
                    temperature=tcurves(place_curve)%dfact
                    group(igroup)%water_pipe%tp=temperature
                    write(chkunit,*)'temp=',temperature
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        ldofs => element(ielem)%field(ifield)%ldofs_f
                        result_zero(ldofs)=temperature

                        !do idofn=1,size(ldofs)     !修改浇筑层界面温度
                        !	if(abs(result_zero(ldofs(idofn)))<.0001) then
                        !		result_zero(ldofs(idofn))=temperature
                        !	else
                        !		result_zero(ldofs(idofn))=(result0(ldofs(idofn))+temperature)*.5
                        !	endif
                        !            enddo

                        do idofn=1,size(ldofs)     !cj042@126.com  20191120修改浇筑层界面温度
                            if(abs(result0(ldofs(idofn)))<.0001) then
                                result_zero(ldofs(idofn))=temperature
                                result1(ldofs(idofn))=temperature  !20191127修改浇筑层除接触面意外的节点的基准温度
                            else
                                result_zero(ldofs(idofn))=(result0(ldofs(idofn))+temperature)*.5  !基准值result0不变【以下层为准】
                            endif
                        enddo

                        nullify(ldofs)
                    end do

                    index=group(igroup)%index
                    nnode=elkn(index)%el_field(ifield)%nnode_f
                    tpave=0.
                    DO ielgroup = 1,group(igroup)%nelgroup      !ielgroup
                        ielem = group(igroup)%list(ielgroup)
                        ldofs =>element(ielem)%field(1)%ldofs_f
                        tpele=sum(result_zero(ldofs))/nnode
                        tpave=tpave+tpele
                        nullify(ldofs)
                    end do
                    tp=tpave/group(igroup)%nelgroup
                    group(igroup)%water_pipe%tp=tp
                    group(igroup)%water_pipe%time_eq=0  ! cj042 20191104 equivalent age
                    group(igroup)%water_pipe%time_real=0  ! cj042 20191104 equivalent age

                endif ! endif for place_curve/=0
            endif ! endif for any fileld=='T'(ic=1)
        endif ! endif for the group just appears in the block
    end do ! igroup
    result0=result1
    deallocate(result1)

    !! 对从节点数值进行修改，以保证水管单元初始温度与依赖的混凝土节点温度相同(20210417)
    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if (nintf==0) cycle
        result_zero(itotv)=0.
        do iintf=1,nintf
            jtotv=trans(itotv)%listf(iintf)
            result_zero(itotv)=result_zero(itotv)+result_zero(jtotv)*trans(itotv)%rintf(iintf)
        end do
    end do

    do i0=1,nwcpipe
        iwc=wc_pipe(i0)%iwc
        twater_curve=wc_pipe(i0)%twater_curve
        dfact   =tcurves(twater_curve)%dfact
        nline_g_w=wc_pipe(i0)%nline_g_w
        do i1=1,nline_g_w
            npairs_wc=wc_pipe(i0)%line_g_w(i1)%npairs_wc
            pairnode_wc=>wc_pipe(i0)%line_g_w(i1)%pairnode_wc
            if(iwc==1)then
                ipoin=pairnode_wc(1)
                jtotv=nodfn(lmdofn(10),ipoin)
                result_zero(jtotv)=dfact
            elseif(iwc==-1)then
                ipoin=pairnode_wc(npairs_wc)
                jtotv=nodfn(lmdofn(10),ipoin)
                result_zero(jtotv)=dfact
            endif
            nullify(pairnode_wc)
        end do
    end do
    !!end 对从节点数值修改，以保证水管单元初始温度与依赖的混凝土节点温度相同(20210417)



    end   subroutine placement_temperature

    subroutine placement_temperature0

    character(10) fieldid
    integer(ink) igroup,ic,ifield,matno,place_curve,ielgroup,ielem, nrfields
    integer(ink), pointer::ldofs(:)
    real   (irk) temperature
    DO igroup =1,ngroup
        if(appear(igroup)<=0)cycle
        if (appear_process(igroup,iblks-1)==0.and.   &
            appear_process(igroup,iblks)==1) then
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            ic=0
            do ifield=1,nrfields
                if (fieldid(ifield:ifield)=='T')then
                    ic=1
                    exit
                end if
            end do
            if (ic==1) then
                matno = group(igroup)%matno
                place_curve=props(matno)%heat%place_curve
                if (place_curve/=0) then
                    temperature=tcurves(place_curve)%dfact
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        ldofs => element(ielem)%field(ifield)%ldofs_f
                        result_zero(ldofs)=temperature
                        nullify(ldofs)
                    end do
                endif ! endif for place_curve/=0
            endif ! endif for any fileld=='T'(ic=1)
        endif ! endif for the group just appears in the block
    end do ! igroup

    end   subroutine placement_temperature0



    SUBROUTINE ALGORT
    !
    integer(ink) KOUNT

    KRESL=0
    IF(type_nl.EQ.1.and.istep==inc_step.AND.IITER.EQ.1)   KRESL=1
    IF(type_nl.EQ.2.AND.IITER.le.2)                       KRESL=1
    IF(type_nl.EQ.4)                                      KRESL=1    ! Full newton
    IF(type_nl.EQ.5.AND.IITER.EQ.1)                       KRESL=1
    IF(type_nl.EQ.6.AND.IITER.EQ.2)                       KRESL=1
    IF(type_nl.EQ.7.AND.IITER.ge.2)                       KRESL=1
    if(type_nl.eq.8.and.iiter==1)                         kresl=1
    IF(type_nl==9.AND.iblks==(lblks+1).and. &
        iincs==1.and.istep==inc_step.and.IITER.EQ.1)          kresl=1
    if(type_nl.eq.10)                                     kresl=0
    !   if(kstat==2.and.iiter<=2)                             kresl=1
    if(gamamax/=0)then !20231215YL
        if(istep/=1)kresl=0
    endif !20231215YL



    if (nlayer==2) then
        kresl_layer1=0
        IF(type_nl_layer1.EQ.1.AND.istep==inc_step.AND.IITER.EQ.1)       kresl_layer1=1
        IF(type_nl_layer1.EQ.2.AND.IITER.le.2)                           kresl_layer1=1
        IF(type_nl_layer1.EQ.4)                                          kresl_layer1=1  ! Full newton
        IF(type_nl_layer1.EQ.5.AND.IITER.EQ.1)                           kresl_layer1=1
        IF(type_nl_layer1==9.AND.  &
            iblks==(lblks+1).and.iincs==1.and.istep==inc_step.and.IITER.EQ.1)kresl_layer1=1
        kresl_layer2=0
        IF(type_nl_layer2.EQ.1.AND.istep==inc_step.AND.IITER.EQ.1)       kresl_layer2=1
        IF(type_nl_layer2.EQ.2.AND.IITER.le.2)                           kresl_layer2=1
        IF(type_nl_layer2.EQ.4)                                          kresl_layer2=1  ! Full newton
        IF(type_nl_layer2.EQ.5.AND.IITER.EQ.1)                           kresl_layer2=1
        IF(type_nl_layer2==9.AND.  &
            iblks==(lblks+1).and.iincs==1.and.istep==inc_step.and.IITER.EQ.1)kresl_layer2=1
        kresl=0
        if(kresl_layer1/=0.or.kresl_layer2/=0)                           kresl=1
    endif
    !
    KMASS=0
    if (type_problem/='Q'.or.stabpw==1) then
        IF (NMASS.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
            KMASS=1
        ELSE
            IF (IITER.EQ.1) THEN
                KOUNT=(istep/NMASS)*NMASS
                IF(KOUNT.EQ.istep)                                          KMASS=1
            END IF
        END IF
    endif
    !
    KSMAT=0
    IF (NSMAT.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
        KSMAT=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(istep/NSMAT)*NSMAT
            IF(KOUNT.EQ.istep)                                             KSMAT=1
        END IF
    END IF
    if(type_problem=='Q'.or.outinp>0)                                                        ksmat=0  !20220623
    !
    KHMAT=0
    IF (NHMAT.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
        KHMAT=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(istep/NHMAT)*NHMAT
            IF(KOUNT.EQ.istep)                                             KHMAT=1
        END IF
    END IF
    if(outinp>0)                                                        khmat=0  !20220623

    !   temperature

    KTSMAT=0
    IF (NTSMAT.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
        KTSMAT=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(istep/NTSMAT)*NTSMAT
            IF(KOUNT.EQ.istep)                                             KTSMAT=1
        END IF
    END IF
    !if(outintr.ne.0.or.outinp/=0)                                       ktsmat=0  !20220623
    if(outintr.ne.0)                                       ktsmat=0   !20220623
    !
    KTHMAT=0
    IF (NTHMAT.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
        KTHMAT=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(istep/NTHMAT)*NTHMAT
            IF(KOUNT.EQ.istep)                                             KTHMAT=1
        END IF
    END IF
    !if(outintr.ne.0.or.outinp/=0)                                       kthmat=0 !20220623
    if(outintr.ne.0)                                       kthmat=0 !20220623


    !   temperature
    !
    KQMAT=0
    IF (NQMAT.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
        KQMAT=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(istep/NQMAT)*NQMAT
            IF(KOUNT.EQ.istep)                                             KQMAT=1
        END IF
    END IF
    !
    KSWKW=0
    IF (NSWKW.EQ.0.or.(istep.eq.inc_step.and.iiter.eq.1)) THEN
        KSWKW=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(ISTEP/NSWKW)*NSWKW
            IF(KOUNT.EQ.ISTEP)                                             KSWKW=1
        END IF
    END IF

    !
    kldfl=0
    IF (NLDFL.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
        KLDFL=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(istep/NLDFL)*NLDFL
            IF(KOUNT.EQ.istep)                                             KLDFL=1
        END IF
    END IF
    !
    kgrav=0
    IF (NGRAV.EQ.0.OR.(istep==inc_step.AND.IITER.EQ.1)) THEN
        KGRAV=1
    ELSE
        IF (IITER.EQ.1) THEN
            KOUNT=(istep/NGRAV)*NGRAV
            IF(KOUNT.EQ.istep)                                             KGRAV=1
        END IF
    END IF


    END SUBROUTINE ALGORT
    !-------------------------------------------------------------------------

    subroutine conver_load

    real   (irk),allocatable:: refor(:),toforx(:),refory(:),tofory(:)
    integer(ink) igroup,nrfields,nelgroup,ielgroup,ielem,imcon,                &
        ifield,first_node, second_node,npairs,ipair,            &
        itotv,jtotv,order_freedom,ilink,ndofn,                  &
        inode,ipoin,np_unode,ii,iedge,idimn,felem,i0, &
        i1,ipairs,npairs_wc,nline_g_w,twater_curve,iwc,  &
        igapbf,igapb,npgblock,ij,igaps,kkdimn

    integer(ink) iintf,nintf
    character(10)fieldid
    integer(ink),pointer::ldofs(:),link_freedom(:),pairnode(:,:),lnods(:),pairnode_wc(:)
    real   (irk),pointer::eload(:),value(:),ks(:,:)
    real   (irk) tfi,resid,retot,max_refor,max_tofor,ratio1,ratio2,xxxx,coef1,dfact
    real   (irk),allocatable::heat_wc(:)  !20210417


    !   Checks convergence for load part
    print *,'                    istep=',istep,'iiter=',iiter
    print *,'                    conver_load check'
    write(chkunit,*)
    write(chkunit,*)'        Convergence check for Residual force,ttime=,',ttime
    allocate(refor(ntotv),toforx(ntotv),refory(ntotv),tofory(ntotv))
    nchek=0
    resid=0.0
    retot=0.0
    stfor=0.0
    toforx=0.0
    refor=0.0
    tofory=0.0
    refory=0.0


    do igroup=1,ngroup
        if (appear(igroup)>0) then   !20191006
            ! get information from the group level
            nrfields =group(igroup)%nrfields
            nelgroup =group(igroup)%nelgroup
            do ielgroup=1,nelgroup
                ielem=group(igroup)%list(ielgroup)
                if (ice0(ielem)/=1)then
                    do ifield=1,nrfields
                        if (associated(element(ielem)%field(ifield)%eload)) then
                            ldofs=> element(ielem)%field(ifield)%ldofs_f
                            eload=> element(ielem)%field(ifield)%eload

                            ndofn=size(ldofs)
                            do itotv=1,ndofn

                                stfor(ldofs(itotv))=stfor(ldofs(itotv))+eload(itotv)
                                ! if(ldofs(itotv)==5218) &
                                !write(7,*)'ielem=',ielem,'ifield=',ifield,'idofn=',itotv,'stfor=',stfor(ldofs(itotv)),'eload=',eload(itotv)
                            end do
                            nullify(ldofs,eload)
                        endif
                    end do   !! for ifield
                endif
            end do  !! for ielgroup
        end if   !! for appear
    end do !! for igroup
    !!!!!
    write(7,*)'total force on spring nodes of dam_foundation interface'

    !ifs2006 zhao, 06/03/29 , icaddmass

    if (icaddmass/=0)then
        do ipoin=1,npoin
            if(icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxxx=result_second(itotv)
                stfor(itotv)=stfor(itotv)+addmp(idimn,ipoin)*xxxx
            enddo
        enddo
    endif
    !2013/4/12

    if (nmcon/=0)then
        do imcon=1,nmcon
            ipoin=lmcon(imcon)
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxxx=result_second(itotv)
                stfor(itotv)=stfor(itotv)+rmcon(idimn,imcon)*xxxx
            enddo
        enddo
    endif

    if (nbspring>0)then  !20150925
        do imcon=1,nbspring
            itotv=bspring(imcon)%listdof
            if(itotv==0)cycle
            stfor(itotv)=stfor(itotv)+bspring(imcon)%eload
        enddo
    endif      !20150925

    !!!!1
    if (rmesh>0.and.nelem1>0)then
        do igroup=1,ngroup
            if (appear(igroup)>0) then
                ! get information from the group level
                nrfields =group(igroup)%nrfields
                nelgroup =group1(igroup)%nelgroup
                do ielgroup=1,nelgroup
                    ielem=group1(igroup)%list(ielgroup)
                    if (jce1(ielem)/=1)then
                        do ifield=1,nrfields
                            if (associated(element1(ielem)%field(ifield)%eload)) then
                                ldofs=> element1(ielem)%field(ifield)%ldofs_f
                                eload=> element1(ielem)%field(ifield)%eload

                                ndofn=size(ldofs)
                                do itotv=1,ndofn
                                    stfor(ldofs(itotv))=stfor(ldofs(itotv))+eload(itotv)

                                end do
                                nullify(ldofs,eload)
                            endif
                        end do   !! for ifield
                    endif
                end do  !! for ielgroup
            end if   !! for appear
        end do !! for igroup
    endif

    !!!!2
    if (rmesh>1.and.nelem2>0)then
        do igroup=1,ngroup
            if (appear(igroup)>0) then
                ! get information from the group level
                nrfields =group(igroup)%nrfields
                nelgroup =group2(igroup)%nelgroup
                do ielgroup=1,nelgroup
                    ielem=group2(igroup)%list(ielgroup)
                    do ifield=1,nrfields
                        if (associated(element2(ielem)%field(ifield)%eload)) then
                            ldofs=> element2(ielem)%field(ifield)%ldofs_f
                            eload=> element2(ielem)%field(ifield)%eload

                            ndofn=size(ldofs)
                            do itotv=1,ndofn
                                stfor(ldofs(itotv))=stfor(ldofs(itotv))+eload(itotv)
                            end do
                            nullify(ldofs,eload)
                        endif
                    end do   !! for ifield
                end do  !! for ielgroup
            end if   !! for appear
        end do !! for igroup
    endif

    !!ifs2000
    do ielem=1,nifsgroup
        ldofs=> tifs(ielem)%ldofs
        eload=> tifs(ielem)%eload
        stfor(ldofs)=stfor(ldofs)+eload
        nullify(ldofs,eload)
    end do

    do ielem=1,nabssgroup
        ldofs=> tabss(ielem)%ldofs
        eload=> tabss(ielem)%eload
        stfor(ldofs)=stfor(ldofs)+eload
        nullify(ldofs,eload)
    end do
    !!ifs2000

    !ifs2006 zhao, 06/03/29
    if(icaddmass==0)then    !20231215YL 对附加质量法不需要以下集成
        do iedge=1,ifsnedge
            felem=ifsedges(iedge)%felem
            igroup=element(felem)%group
            if(appear(igroup)==0)cycle
            ldofs=>ifsedges(iedge)%ldofs
            eload=>ifsedges(iedge)%eload
            stfor(ldofs)=stfor(ldofs)+eload
            nullify(ldofs,eload)
        enddo
    endif

    !! stablize
    if (stabpw==1) then
        do igroup=1,ngroup
            fieldid=group(igroup)%fieldid
            if (appear(igroup)>0.and.(fieldid(1:2)=='UP'.or.fieldid(1:2)=='UW')) then
                do ipoin=1,group(igroup)%np_unode
                    np_unode=group(igroup)%unode(ipoin)%np_unode
                    if (np_unode/=0) then
                        eload=>group(igroup)%unode(ipoin)%patch_load
                        lnods=>group(igroup)%unode(ipoin)%patch_nod
                        do inode=1,np_unode
                            itotv=nodfn(ndimn+1,lnods(inode))
                            stfor(itotv)=stfor(itotv)+eload(inode)
                        end do
                        nullify(eload,lnods)
                    endif
                end do
            endif
        end do
    endif
    !! end of stablize

    if (ground_inf/=0) then
        !  write(7,*)'itotv,ldofs_space,eload_space,stfor='
        !do itotv=1,size(ldofs_space)
        !    write(7,*)itotv,ldofs_space(itotv),eload_space(itotv),stfor(ldofs_space(itotv))
        !end do
        stfor(ldofs_space)=stfor(ldofs_space)+eload_space

    endif

    if(nwcpipe/=0)then !20210417
        !write(7,*)'nwcpipe:itotv,stfor,tofor='
        do i0=1,nwcpipe
            nline_g_w=wc_pipe(i0)%nline_g_w
            coef1= wc_pipe(i0)%iwc
            iwc=wc_pipe(i0)%iwc
            twater_curve=wc_pipe(i0)%twater_curve
            dfact   =tcurves(twater_curve)%dfact

            do i1=1,nline_g_w
                npairs_wc=wc_pipe(i0)%line_g_w(i1)%npairs_wc
                allocate(value(npairs_wc),heat_wc(npairs_wc))
                pairnode_wc=>wc_pipe(i0)%line_g_w(i1)%pairnode_wc
                value=0.;heat_wc=0.

                if(iwc==1)then
                    ipoin=pairnode_wc(1)
                    jtotv=nodfn(lmdofn(10),ipoin)
                    result_zero(jtotv)=dfact
                    result_first(jtotv)=0.
                elseif(iwc==-1)then
                    ipoin=pairnode_wc(npairs_wc)
                    jtotv=nodfn(lmdofn(10),ipoin)
                    result_zero(jtotv)=dfact
                    result_first(jtotv)=0.
                endif
                do ipairs=1,npairs_wc
                    itotv=nodfn(lmdofn(10),pairnode_wc(ipairs))
                    if(itotv/=0) &
                        value(ipairs)=result_zero(itotv)
                end do

                Ks=>wc_pipe(i0)%line_g_w(i1)%kmatrix_w
                heat_wc=Ks.x.value
                heat_wc=coef1*heat_wc
                !write(7,*)'heat_wc='
                !write(7,30)heat_wc

                do ipairs=1,npairs_wc
                    jtotv=nodfn(lmdofn(10),pairnode_wc(ipairs))
                    tofor(jtotv)=-heat_wc(ipairs)
                end do
                deallocate(value,heat_wc)
                nullify(Ks,pairnode_wc)
            end do
        end do

    endif  !20210417



    if (mdiv==1)then
        refor=refor+(tofor-stfor)
    else
        refor=refor+(toform-stfor)
    endif

    if (mdiv==1)then
        toforx=tofor
    else
        toforx=toform
    endif

    !!int2000
    ! write(7,*)'refor(5218)=',refor(5218)
    !write(7,*)'tofor(17570)=',tofor(17570),'stfor(17570)=',stfor(17570)
    !write(7,*)'refor(17570)=',refor(17570)
    !


    tofory=toforx
    refory=refor
    do itotv=1,ntotv
        nintf=trans(itotv)%nintf

        if (nintf/=0) then
            !write(7,*)'itotv=',itotv,'nintf=',nintf

            toforx(itotv)=0.
            refor(itotv)=0.
            do iintf=1,nintf
                !if (iffix(trans(itotv)%listf(iintf))==0)then  !20211214
                toforx(trans(itotv)%listf(iintf))=  &
                    toforx(trans(itotv)%listf(iintf))+  &
                    tofory(itotv)*trans(itotv)%rintf(iintf)
                refor(trans(itotv)%listf(iintf))=  &
                    refor(trans(itotv)%listf(iintf))+  &
                    refory(itotv)*trans(itotv)%rintf(iintf)
                !if(trans(itotv)%listf(iintf)==5218)write(7,*)trans(itotv)%listf(iintf),itotv,refor(trans(itotv)%listf(iintf))
                !endif  !20211214
            end do
        endif
    end do
    !!int2000
    ! write(7,*)'total force on spring nodes of dam_foundation interface'
    !  do idimn=1,mdofn
    !tfi=0.
    !if(lmdofn(idimn)==0)cycle  !20220302
    !do ipoin=1,npoin
    !    itotv=nodfn(lmdofn(idimn),ipoin) !20220302
    !    if (itotv==0) cycle
    !     if (iffix(itotv)==6) &
    !    tfi=tfi-refor(itotv)
    !end do
    !write(7,*)'idimn=',idimn,'tfi=',tfi
    !  end do

    if(nbackf/=0)then
        ! record the displacements of spring points
        kkdimn=ndimn  !2015/11/17
        if(block_stab==1)kkdimn=3*(ndimn-1) !2015/11/17
        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ipair=gapb(igapb)%nodegblock_ipairs(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                ipoin=gaps(igaps)%pairnode(ij,ipair)
                gapb(igapb)%force_ct(1:kkdimn,i0)=-refor(nodfn(1:kkdimn,ipoin))  !坝和地基交界点处位移
            end do
        end do
    endif

    do itotv=1,ntotv  !20191006
        if (iffix(itotv)>0) refor(itotv)=0.
    end do




    if (nflow/=0)then
        do ii=1,nfreeflownode
            ipoin=listfreeflownode(ii)
            itotv=nodfn(lmdofn(8),ipoin)
            if (totveq(itotv)/=0.and.(result_zero(itotv)>.1  &
                .or.(result_zero(itotv)>0..and.flowrate(ipoin)>0.))) then
                refor(itotv)=0.
            endif
        end do
    endif

    do ilink=1,nlinks
        npairs=links(ilink)%npairs
        pairnode=>links(ilink)%pairnode
        link_freedom=>links(ilink)%link_freedom
        do order_freedom=1,cdofn
            if (link_freedom(order_freedom)==1) then
                do ipair=1,npairs
                    first_node   =pairnode(1,ipair)
                    second_node  =pairnode(2,ipair)
                    itotv        =nodfn(order_freedom,first_node)
                    jtotv        =nodfn(order_freedom,second_node)
                    toforx(itotv)  =toforx(itotv)+toforx(jtotv)
                    toforx(jtotv)  =0.0
                    refor (itotv)  =refor (itotv)+refor (jtotv)
                    refor (jtotv)  =0.0
                end do
            endif
        end do
        nullify(pairnode)
    end do

    !write(outact,*)'istep=',istep,'iiter=',iiter,'tofor_ncomn='
    !    allocate(value(1:ndimn))
    !    i0=0
    !       do ipoin=1,npoin
    !          value=0.
    !          do idofn=1,ndimn
    !             itotv=nodfn(idofn,ipoin)
    !             if (itotv/=0)value(idofn)=tofor(itotv)
    !          end do
    !          if(any(abs(value)>.01)) then
    !              i0=i0+1
    !          write(outact,11)i0,ipoin,value
    !          endif
    !       end do
    !       deallocate(value)
11  format(2i10, 6e15.5)
    !12 format(3i10, 3e20.5)

    !write(7,*)'istep=',istep,'iiter=',iiter
    !write(7,*)'ipoin,idofn,itotv,iffix(itotv),toforx(itotv),stfor(itotv),refor(itotv)='
    !
    !       do ipoin=1,npoin
    !          do idofn=1,mdofn  !ndimn
    !           if(lmdofn(idofn)==0)cycle
    !             itotv=nodfn(lmdofn(idofn),ipoin)     !20200220
    !             if(itotv==0)cycle
    !                !if(abs(refor(itotv))>1.e-3) &
    !          write(7,1234)ipoin,idofn,itotv,iffix(itotv),toforx(itotv),stfor(itotv),refor(itotv)
    !           end do
    !       end do
    !
    !1234 format(4I10,3e15.5)
    !
    resid=dot_product(refor,refor)
    retot=dot_product(toforx,toforx)

    max_refor=maxval(abs(refor))
    max_tofor=maxval(abs(toforx))
    print *, 'resid=',resid,'retot=',retot
    resid=sqrt(resid)
    retot=sqrt(retot)
    !   print *, 'resid=',resid,'retot=',retot
    !   print *, 'max_refor=',max_refor,'max_tofor=',max_tofor
    ratio1=resid/retot
    ratio2=max_refor/max_tofor

    write(chkunit,*)'iblks=',iblks,'iincs=',iincs,'istep=',istep,'iiter=',iiter
    write(chkunit,*)'resid=',resid,'retot=',retot
    write(chkunit,10) ratio1
    write(chkunit,*)'max_refor=',max_refor,'max_tofor=',max_tofor
    write(chkunit,20) ratio2
    print *,'ratio1=',ratio1,'ratio2=',ratio2
    !   if(ratio1.ge.1..or.ratio2.ge.1.) stop 'error conver_load'

    deallocate(refor,toforx,refory,tofory)

    print *,'nchek0=',nchek,'toler_force=',toler_force
    if(ratio1>toler_force.or.ratio2>toler_force) nchek=1
    print *,'nchek=',nchek

10  format('ratio for residu norm=',e11.4)
20  format('ratio for residu maxm=',e11.4)
30  format(10e15.5)

    end subroutine conver_load

    subroutine conver_load_w !freq2006

    complex(irk),allocatable:: refor(:)
    real   (irk) resid,retot,max_refor,max_tofor,ratio1,ratio2

    !      ------  Checks convergence for load part

    if (iiter==2)then
        write(7,*)'ndofn='
        do ipoin=1,npoin
            write(7,*)ipoin,nodfn(lmdofn(1:ndimn),ipoin)
        end do
    endif
    print *,'                    istep=',istep,'iiter=',iiter
    print *,'                    conver_load check'
    write(chkunit,*)
    write(chkunit,*)'        Convergence check for Residual force,ttime=,',ttime
    allocate(refor(ntotv))
    nchek=0
    retot=0.0
    refor=(0.0,0.)
    refor=(toforw-stforw)

    do itotv=1,ntotv
        if(iffix(itotv)/=0)then
            refor(itotv)=(0.,0.)
            toforw(itotv)=stforw(itotv)
        endif
    end do

    resid=dot_product(refor,refor)
    retot=dot_product(toforw,toforw)

    max_refor=maxval(abs(refor))
    max_tofor=maxval(abs(toforw))
    print *, 'resid=',resid,'retot=',retot
    resid=sqrt(resid)
    retot=sqrt(retot)
    !   print *, 'resid=',resid,'retot=',retot
    !   print *, 'max_refor=',max_refor,'max_tofor=',max_tofor
    ratio1=resid/retot
    ratio2=max_refor/max_tofor
    !write(chkunit,*)'iiter=',iiter,'stfor,tofor,refor='
    !do itotv=1,ntotv
    !write(chkunit,30)itotv,stforw(itotv),toforw(itotv),refor(itotv)
    !end do


    write(chkunit,*)'iblks=',iblks,'iincs=',iincs,'istep=',istep,'iiter=',iiter
    write(chkunit,*)'resid=',resid,'retot=',retot
    write(chkunit,10) ratio1
    write(chkunit,*)'max_refor=',max_refor,'max_tofor=',max_tofor
    write(chkunit,20) ratio2
    print *,'ratio1=',ratio1,'ratio2=',ratio2
    !   if(ratio1.ge.1..or.ratio2.ge.1.) stop 'error conver_load'

    deallocate(refor)

    if(ratio1>toler_force.or.ratio2>toler_force) nchek=1

10  format('ratio for residu norm=',e11.4)
20  format('ratio for residu maxm=',e11.4)
30  format(i10,10e15.4)

    end subroutine conver_load_w

    subroutine conver_nodal_value

    integer(ink) checki,mdofn1,mdofn2,idimn,itotv,ipoin
    real   (irk),allocatable::tavalue(:),itvalue(:)

    real   (irk) tavnorm,itvnorm,max_tav,max_itv,ratio1,ratio2

    !      ------  Checks convergence for load part

    print *, '                   conver_nodal_value check'
    write(chkunit,*)
    nchek=0

    !!  check convergence for displacement term

    checki=1
    mdofn1=1
    mdofn2=ndimn

    allocate(tavalue(ntotv),itvalue(ntotv))


100 if (any(lmdofn(mdofn1:mdofn2)/=0)) then


        if(checki==1)write(chkunit,*)'              Convergence check for displacement'
        if(checki==2)write(chkunit,*)'              Convergence check for rotations'
        if(checki==3)write(chkunit,*)'              Convergence check for pressure(P)'
        if(checki==4)write(chkunit,*)'              Convergence check for pressure(Pw)'
        if(checki==5)write(chkunit,*)'              Convergence check for pressure(Pa)'
        if(checki==6)write(chkunit,*)'              Convergence check for temperature'
        if(checki==1)print *,'              Convergence check for displacement'
        if(checki==2)print *,'              Convergence check for rotations'
        if(checki==3)print *,'              Convergence check for pressure(P)'
        if(checki==4)print *,'              Convergence check for pressure(Pw)'
        if(checki==5)print *,'              Convergence check for pressure(Pa)'
        if(checki==6)print *,'              Convergence check for temperature'
        tavalue=0.0
        itvalue=0.0
        do idimn=mdofn1,mdofn2
            if (lmdofn(idimn)/=0) then
                do ipoin=1,npoin
                    itotv=nodfn(lmdofn(idimn),ipoin)
                    if (itotv>0)then
                        tavalue(itotv)=result_zero(itotv)
                        itvalue(itotv)=delitfi(itotv)
                        !if(iiter>1.and.abs(itvalue(itotv)/tavalue(itotv))>1.e-3)then
                        !write(7,*)'itotv=',itotv,'itvalue=',itvalue(itotv),'tavalue=',tavalue(itotv)
                        !endif
                    endif
                end do
            endif
        end do

        !write(7,*)'tavalue,itvalue'
        !do itotv=1,ntotv
        !    write(7,*)itotv,tavalue(itotv),itvalue(itotv)
        !end do

        tavnorm=dot_product(tavalue,tavalue)
        itvnorm=dot_product(itvalue,itvalue)
        max_tav=maxval(abs(tavalue))
        max_itv=maxval(abs(itvalue))

        tavnorm=sqrt(tavnorm)
        itvnorm=sqrt(itvnorm)
        if (max_tav.le.1.e-10.or.tavnorm.le.1.e-10)then
            nchek=0
            goto 101
        endif
        !      print *,'tatfn=',tavnorm,'itifn=',itvnorm
        write(7,*)'max_tatf=',max_tav,'max_itif=',max_itv
        ratio1=itvnorm/tavnorm
        ratio2=max_itv/max_tav

        write(chkunit,*)'iiter=',iiter,'tatfn=',tavnorm,'itifn=',itvnorm
        write(chkunit,10) ratio1
        write(chkunit,*)'max_tatf=',max_tav,'max_itif=',max_itv
        write(chkunit,20) ratio2
        print *,'ratio1=',ratio1,'ratio2=',ratio2

        if(ratio1>toler_var(mdofn1).or.ratio2>toler_var(mdofn1)) nchek=1

    end if   !! for convergence checki


    if (nchek==1) then
        print *,'                           not converged for checki=',checki
        write(chkunit,*)'                   not converged for checki=',checki
        deallocate(tavalue,itvalue)
        return
    endif

101 continue


    if (checki==6) then
        deallocate(tavalue,itvalue)
        return

    else

        checki=checki+1
        if(checki==2)             mdofn1=4
        if(checki==2.and.ndimn==2)mdofn2=4
        if(checki==2.and.ndimn==3)mdofn2=6

        if(checki==3)mdofn1=7
        if(checki==3)mdofn2=7

        if(checki==4)mdofn1=8
        if(checki==4)mdofn2=8

        if(checki==5)mdofn1=9
        if(checki==5)mdofn2=9

        if(checki==6)mdofn1=10
        if(checki==6)mdofn2=10

        if (mdofn<mdofn1.or.(checki==5.and.(outintr.ne.0.or.outinp/=0)).or.(checki==3.and.outinp==8))then
            print *, 'nchek=',nchek
            deallocate(tavalue,itvalue)
            return
        endif
        goto 100
    endif


10  format('ratio for norm=',e11.4)
20  format('ratio for maxm=',e11.4)

    end subroutine conver_nodal_value

    !   SUBROUTINE modf_time_order
    !
    !   character(10)fieldid
    !   integer(ink) index,matno
    !
    !   do igroup=1,ngroup
    !      fieldid=group(igroup)%fieldid
    !      index=group(igroup)%index
    !      matno = group(igroup)%matno
    !      group(igroup)%order_time(:,:)=0
    !
    !      if (fieldid=='U') then
    !
    !         elkn(index)%el_field(1)%order_time(1)=0
    !         elkn(index)%el_field(1)%order_time(2)=2
    !         group(igroup)%order_time(1,1)=0 !order_time
    !         group(igroup)%order_time(2,1)=2 !order_time
    !         if (type_problem=='S')then
    !            elkn(index)%el_field(1)%order_time(2)=1
    !            group(igroup)%order_time(2,1)=1
    !         endif
    !
    !      elseif(fieldid=='W') then !20060602
    !
    !         elkn(index)%el_field(1)%order_time(1)=0
    !         elkn(index)%el_field(1)%order_time(2)=2
    !         group(igroup)%order_time(1,1)=0 !order_time
    !         group(igroup)%order_time(2,1)=2 !order_time
    !         material=props(matno)%name
    !         if (material(1:6)=='NSSoil')then
    !            elkn(index)%el_field(1)%order_time(2)=1
    !            group(igroup)%order_time(2,1)=1 !order_time
    !         endif
    !      endif
    !
    !      if (fieldid=='T'.and.type_problem=='S') then
    !
    !         elkn(index)%el_field(1)%order_time(1)=0
    !         elkn(index)%el_field(1)%order_time(2)=1
    !         group(igroup)%order_time(1,1)=0
    !         group(igroup)%order_time(2,1)=1
    !
    !      elseif(fieldid=='T'.and.type_problem=='Q') then !zhao 05/07/22
    !
    !         elkn(index)%el_field(1)%order_time(1)=0
    !         group(igroup)%order_time(1,1)=0
    !
    !      endif
    !
    !      if (fieldid=='UW') then
    !
    !         elkn(index)%el_field(2)%order_time(1)=0
    !         elkn(index)%el_field(2)%order_time(2)=1
    !         group(igroup)%order_time(1,2)=0
    !         group(igroup)%order_time(2,2)=1
    !
    !if(type_problem/='Q'.or.(type_problem=='Q'.and.uwcpl/=0)) then		!nzw 2006-05-15 for calculating eload_couple
    !
    !            elkn(index)%couple(1)%order_couple(1)=1
    !            elkn(index)%couple(1)%order_couple(2)=0
    !            !group(igroup)%order_time(1,1)=1          ! problem?
    !            !group(igroup)%order_time(2,1)=0
    !
    !         endif
    !
    !         if (type_problem=='S') then
    !
    !            elkn(index)%el_field(1)%order_time(1)=0
    !            elkn(index)%el_field(1)%order_time(2)=1
    !            group(igroup)%order_time(1,1)=0
    !            group(igroup)%order_time(2,1)=1
    !
    !         elseif(type_problem=='F') then
    !
    !            elkn(index)%el_field(1)%order_time(1)=0
    !            elkn(index)%el_field(1)%order_time(2)=2
    !            group(igroup)%order_time(1,1)=0
    !            group(igroup)%order_time(2,1)=2
    !         endif
    !      endif
    !   end do
    !
    !   END  SUBROUTINE modf_time_order

    SUBROUTINE modf_time_order
    character(10)fieldid,name
    integer(ink) index,matno

    do igroup=1,ngroup
        fieldid=group(igroup)%fieldid
        index=group(igroup)%index
        matno = group(igroup)%matno

        !print *,'igroup=',igroup   !20231215YL

        if(fieldid=='U') then
            elkn(index)%el_field(1)%order_time(1)=0
            elkn(index)%el_field(1)%order_time(2)=2
            if(type_problem=='S')elkn(index)%el_field(1)%order_time(2)=1
        elseif(fieldid=='W') then
            elkn(index)%el_field(1)%order_time(1)=0
            elkn(index)%el_field(1)%order_time(2)=2
            name=props(matno)%name
            if(name(1:6)=='NSSoil')elkn(index)%el_field(1)%order_time(2)=1

        endif

        if(fieldid=='T'.and.type_problem=='S') then
            elkn(index)%el_field(1)%order_time(1)=0
            elkn(index)%el_field(1)%order_time(2)=1
        endif

        if(fieldid=='UW') then
            elkn(index)%el_field(2)%order_time(1)=0
            elkn(index)%el_field(2)%order_time(2)=1


            elkn(index)%couple(1)%order_couple(1)=0
            elkn(index)%couple(1)%order_couple(2)=0

            if(type_problem/='Q') then
                elkn(index)%couple(1)%order_couple(1)=1
                elkn(index)%couple(1)%order_couple(2)=0
            endif

            if(type_problem=='S') then
                elkn(index)%el_field(1)%order_time(1)=0
                elkn(index)%el_field(1)%order_time(2)=1

            elseif(type_problem=='F') then
                elkn(index)%el_field(1)%order_time(1)=0
                elkn(index)%el_field(1)%order_time(2)=2
            endif

        endif

    end do

    END  SUBROUTINE modf_time_order

    SUBROUTINE RESTA_READ_WRITE(ic)

    character(10) field1,name
    integer(ink) igroup,index,order_int,ielem,matno,ic,ielgroup,icreep,igapb,nrdof,igaps
    integer(ink) kinit_g !20211214
    rewind(restaunit)
    if (ic==-1) then
        write(restaunit)iblks,iincs,ttime,line_load_block(1:iblks),line_temp_block(1:iblks),trstep
        write(restaunit)group(1:ngroup)%btime,group(1:ngroup)%ditime_1
        if(allocated(result_zero))  write(restaunit)result_zero
        if(allocated(result_first)) write(restaunit)result_first
        if(allocated(result_second))write(restaunit)result_second
        if(allocated(prstat))       write(restaunit)prstat
        if(allocated(torel))        write(restaunit)torel
        if(allocated(toforl))       write(restaunit)toforl
        if(allocated(fexta))        write(restaunit)fexta  !!nstoks

        DO igroup =1,ngroup
            field1= group(igroup)%fieldid
            if (field1(1:1)=='U')  then
                kinit_g=group(igroup)%kinit_g
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    write(restaunit)element(ielem)%field(1)%gpvar
                    write(restaunit)element(ielem)%field(1)%tload
                    write(restaunit)element(ielem)%field(1)%eload
                    if(kinit_g==2)write(restaunit)element(ielem)%stres0
                end do
            endif
        end do
        DO igroup =1,ngroup
            field1= group(igroup)%fieldid
            index = group(igroup)%index
            if (field1(1:1)=='U')  then
                matno = group(igroup)%matno
                name  = props(matno)%name
                icreep=props(matno)%mechanical%solid%icreep
                !! contact
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (name=='CONTACT') then
                        write(restaunit)element(ielem)%field(1)%gapg
                        write(restaunit)element(ielem)%field(1)%gapn
                        write(restaunit)element(ielem)%field(1)%state
                    endif
                    if (icreep==2) then
                        write(restaunit)element(ielem)%field(1)%omega
                        write(restaunit)element(ielem)%field(1)%dsig
                    end if
                end do
            endif
            !!contact
            if (field1(1:2)=='UW') then
                if (name=='NSSoilPZ') then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        write(restaunit)element(ielem)%egaus(order_int)%iload
                        write(restaunit)element(ielem)%egaus(order_int)%vdval
                    end do
                endif
            endif
        end do

        do igaps=1,ngaps
            write(restaunit)gaps(igaps)%state
            write(restaunit)gaps(igaps)%ctforce
            if(kinit==2)write(restaunit)gaps(igaps)%ctforce_stres0  !20220623
            write(restaunit)gaps(igaps)%gap
            write(restaunit)gaps(igaps)%dxyz
        end do

        do igapb=1,ngapb
            nrdof=gapb(igapb)%nrdof
            if(nrdof==0)cycle
            write(restaunit)gapb(igapb)%rdisp_zero
            if(type_problem=='F')then
                write(restaunit)gapb(igapb)%rdisp_first
                write(restaunit)gapb(igapb)%rdisp_second
            endif
        end do


        print *,'***********RESTART FILE IS UPDATED!*******'
    else if(ic==1) then
        Print *,'restart reading file'
        read(restaunit)lblks,lincs,lttime,line_load_block(1:lblks),line_temp_block(1:lblks),trstep
        print *,'lblks=',lblks,'lincs=',lincs
        read(restaunit)group(1:ngroup)%btime,group(1:ngroup)%ditime_1
        if(allocated(result_zero))  read(restaunit)result_zero
        if(allocated(result_first)) read(restaunit)result_first
        if(allocated(result_second))read(restaunit)result_second
        if(allocated(prstat))       read(restaunit)prstat
        if(allocated(torel))        read(restaunit)torel
        if(allocated(toforl))       read(restaunit)toforl
        if(allocated(fexta))        read(restaunit)fexta  !!nstoks
        DO igroup =1,ngroup
            field1= group(igroup)%fieldid
            if (field1(1:1)=='U')  then
                kinit_g=group(igroup)%kinit_g  !20211214
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    read(restaunit)element(ielem)%field(1)%gpvar0
                    read(restaunit)element(ielem)%field(1)%tload
                    read(restaunit)element(ielem)%field(1)%eload
                    element(ielem)%field(1)%gpvar=element(ielem)%field(1)%gpvar0
                    if(kinit_g==2)read(restaunit)element(ielem)%stres0
                end do
            endif
        end do
        DO igroup =1,ngroup

            field1= group(igroup)%fieldid
            index = group(igroup)%index
            !! contact
            if (field1(1:1)=='U')  then
                matno = group(igroup)%matno
                name=props(matno)%name
                icreep=props(matno)%mechanical%solid%icreep
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (name=='CONTACT') then
                        read(restaunit)element(ielem)%field(1)%gapg0
                        read(restaunit)element(ielem)%field(1)%gapn0
                        read(restaunit)element(ielem)%field(1)%state0
                        element(ielem)%field(1)%gapg=element(ielem)%field(1)%gapg0
                        element(ielem)%field(1)%gapn=element(ielem)%field(1)%gapn0
                    endif
                    if (icreep==2) then
                        read(restaunit)element(ielem)%field(1)%omega
                        read(restaunit)element(ielem)%field(1)%dsig
                    end if
                end do
            endif
            !!contact
            if (field1(1:2)=='UW') then
                if (name=='NSSoilPZ') then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        read(restaunit)element(ielem)%egaus(order_int)%iload0
                        read(restaunit)element(ielem)%egaus(order_int)%vdval0
                    end do
                endif
            endif
        end do


        do igaps=1,ngaps
            read(restaunit)gaps(igaps)%state
            read(restaunit)gaps(igaps)%ctforce
            if(kinit==2)read(restaunit)gaps(igaps)%ctforce_stres0  !20220623
            read(restaunit)gaps(igaps)%gap
            read(restaunit)gaps(igaps)%dxyz

            gaps(igaps)%state0=gaps(igaps)%state
            gaps(igaps)%ctforce0=gaps(igaps)%ctforce
            gaps(igaps)%gap0=gaps(igaps)%gap
            gaps(igaps)%dxyz0=gaps(igaps)%dxyz
        end do

        do igapb=1,ngapb
            nrdof=gapb(igapb)%nrdof
            if(nrdof==0)cycle
            read(restaunit)gapb(igapb)%rdisp_zero
            if(type_problem=='F')then
                read(restaunit)gapb(igapb)%rdisp_first
                read(restaunit)gapb(igapb)%rdisp_second
            endif
        end do

        print *,'***********RESTART FILE IS READ!*******'
    endif


    END SUBROUTINE RESTA_READ_WRITE


    subroutine safety_factor
    character(20)material,criteria,name
    integer(ink) ielem,igroup,iforce,jgroup,matno,ielgroup
    integer(ink) index,ngaus,igaus,order_int,nstre,npairs,igaps,ipairs,isafety,istate
    integer(ink),allocatable::iii(:)
    real   (irk),allocatable::ftang(:),fresi(:),ftang_gaps(:),fresi_gaps(:),sfactor(:),ps(:)  !20200411
    real   (irk) ft,fn,uniax,frict,k_safety,elcod_local,yld,aera, dilan,sigma0,ftangt,fresit,t1,t2,tt,areat,damage

    if(nforce==0.and.ngaps==0) return
    if(nforce==0) goto 10
    allocate(ftang(nforce),fresi(nforce),iii(ngroup))
    allocate(ps(ndimn))
    iii=0
    ftang=0.
    fresi=0.
    areat = 0.

    do iforce=1,nforce
        if(nforce_appear(iforce)/=1.and.nforce_appear(iforce)/=3)cycle !zhao 2010
        do jgroup=1,surface_force(iforce)%lgroup
            igroup=surface_force(iforce)%list(jgroup)
            iii(igroup)=1
            index = group(igroup)%index
            nstre =group(igroup)%nstre
            matno =group(igroup)%matno
            name=props(matno)%name
            select case(trim(props(matno)%mechanical%solid%material))
            case('CLASSICALEP')
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus = elkn(index)%ggaus(order_int)%ngaus
                elcod_local=group(igroup)%elcod_local
                uniax   =props(matno)%mechanical%solid%classicalEP%sigma0
                frict   =props(matno)%mechanical%solid%classicalEP%frict_angle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    do igaus=1,ngaus
                        yld=element(ielem)%field(1)%gpvar(nstre+2,igaus)
                        if (yld/=2.) then
                            aera=1./elcod_local*element(ielem)%egaus(1)%djacb(igaus)
                            areat = areat + aera
                            fn=element(ielem)%field(1)%ntstress(1,igaus)
                            ft=element(ielem)%field(1)%ntstress(2,igaus)
                            fresi(iforce)=fresi(iforce)-fn*aera*tand(frict)+uniax*aera
                            ftang(iforce)=ftang(iforce)+ft*aera
                        endif
                    end do
                end do

            case('GOODMAN')

                order_int=elkn(1)%el_field(1)%order_intrules(1)
                ngaus=elkn(1)%ggaus(order_int)%ngaus
                elcod_local=group(igroup)%elcod_local
                frict = props(matno)%mechanical%solid%Goodman%frict_angle
                uniax = props(matno)%mechanical%solid%Goodman%uniax_cohes
                if (name=="CONTACT")then
                    do ielgroup = 1, group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        do igaus = 1, ngaus
                            ps = element(ielem)%field(1)%gpvar(1:ndimn,igaus)
                            ps = element(ielem)%field(1)%gpvar(1:ndimn,igaus)
                            fn = ps(2)
                            ft = ps(1)
                            if (element(ielem)%field(1)%state(igaus)=='contact') then
                                aera=element(ielem)%aera_local(igaus)
                                areat = areat + aera
                                fresi(iforce)=fresi(iforce)-fn*aera*tand(frict)+uniax*aera
                            else
                                fn = ps(2)
                                fresi(iforce)=fresi(iforce)-fn*aera*tand(frict)
                            endif
                            ftang(iforce)=ftang(iforce)+ft*aera
                        enddo
                    enddo
                else
                    do ielgroup = 1, group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        do igaus =1, ngaus
                            ps = element(ielem)%field(1)%gpvar(1:ndimn,igaus)
                            fn = ps(2)
                            ft = ps(1)
                            if (ps(2)<1e-10) then
                                aera=element(ielem)%aera_local(igaus)
                                areat = areat + aera
                                fresi(iforce)=fresi(iforce)-fn*aera*tand(frict)+uniax*aera
                            else
                                fn = ps(2)
                                fresi(iforce)=fresi(iforce)-fn*aera*tand(frict)
                            endif
                            ftang(iforce)=ftang(iforce)+ft*aera
                        enddo
                    enddo
                endif

            end select

        end do
        write(chkunit,*)'iforce=',iforce
        write(chkunit,*)'fresi=',fresi(iforce),'ftang=',ftang(iforce)
    end do !iforce

    fresit=0.;ftangt=0.
    fresit=sum(fresi)
    ftangt=sum(ftang)
    K_safety=kstab*fresit/ftangt
    !  kstab=K_safety
    write(chkunit,*)'k_safety=',k_safety, 'area_sum=',areat

10  continue
    if(ngaps/=0)then
        allocate(fresi_gaps(ngaps),ftang_gaps(ngaps))
        if(nsafety_gaps>=0)allocate(sfactor(nsafety_gaps))
        do isafety=1,nsafety_gaps  !isafety  20200409
            fresi_gaps=0.;ftang_gaps=0.
            do igaps=1,ngaps
                if(safety_gaps_appear(igaps,isafety)==0)cycle
                npairs=gaps(igaps)%npairs
                !write(7,*)'igaps=',igaps,'fxyz=',sum(gaps(igaps)%ctforce(1,:)),sum(gaps(igaps)%ctforce(2,:))
                do ipairs=1,npairs
                    if(gaps(igaps)%state(ipairs)==0)cycle  !20211005

                    !write(7,*)'ipairs=',ipairs,'gaps(igaps)%cohes(ipairs)=',gaps(igaps)%cohes(ipairs),'gaps(igaps)%frict(ipairs) =',gaps(igaps)%frict(ipairs)
                    fresi_gaps(igaps)=fresi_gaps(igaps)+gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)
                    t1=gaps(igaps)%ctforce(1,ipairs)
                    if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                    tt=abs(t1)
                    if (ndimn==3)tt=sqrt(t1**2+t2**2)
                    ftang_gaps(igaps)=ftang_gaps(igaps)+tt
                    !write(7,*)'sfl=',(gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs))/tt
                end do
            enddo
            fresit=0.;ftangt=0
            fresit=fresit+sum(fresi_gaps)
            ftangt=ftangt+sum(ftang_gaps)
            write(chkunit,*)'isafety=',isafety
            write(chkunit,*)'fresit=',fresit,'ftangt=',ftangt
            ! write(chkunit,*)'fresi_gaps=',fresi_gaps
            !write(chkunit,*)'ftang_gaps=',ftang_gaps

            K_safety=kstab*fresit/ftangt
            sfactor(isafety)=K_safety
            write(chkunit,*)'k_safety=',k_safety
        end do  !isafety  20200409
        write(7,*)'minimum safety=',minval(sfactor)
        deallocate(sfactor)
    end if



    if(nforce/=0) &
        deallocate(ftang,fresi)
    if(ngaps/=0) &
        deallocate(ftang_gaps,fresi_gaps)

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! zhao 2006/03/09
    if(nforce/=0) then
        do igroup=1,ngroup
            if(iii(igroup)/=1)cycle
            matno =group(igroup)%matno
            material=props(matno)%mechanical%solid%material
            if(material/='CLASSICALEP')cycle
            criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
            if (kstab/=0.and.criteria(1:2)=='MC') then
                frict=props(matno)%mechanical%solid%ClassicalEP%frict_angle_ini
                dilan=props(matno)%mechanical%solid%ClassicalEP%dilan_angle_ini
                frict=tand(frict)/kstab
                dilan=tand(dilan)/kstab
                frict=atand(frict)
                dilan=atand(dilan)
                sigma0=props(matno)%mechanical%solid%ClassicalEP%sigma0_ini
                sigma0=sigma0/kstab
                props(matno)%mechanical%solid%ClassicalEP%frict_angle=frict
                props(matno)%mechanical%solid%ClassicalEP%dilan_angle=dilan
                props(matno)%mechanical%solid%ClassicalEP%sigma0=sigma0
            endif
        enddo
        deallocate(iii)
    endif

    end subroutine safety_factor

    subroutine stab_rcandgy_reli(rc,xa,gy) !2018/01/10
    character(20)material,criteria
    integer(ink) ielem,igroup,iforce,jgroup,matno,ielgroup
    integer(ink) index,ngaus,igaus,order_int,nstre,npairs,igaps,ipairs,ivfri,ivcoh
    real   (irk),allocatable::ftang(:),fresi(:),ftang_gaps(:),fresi_gaps(:)
    real   (irk) ft,fn,uniax,frict,k_safety,elcod_local,yld,aera, dilan,sigma0,ftangt,fresit,t1,t2,tt,rc(:),xa(:),Gy

    rc=0.
    if(nforce==0.and.ngaps==0) return
    if(nforce==0) goto 10
    allocate(ftang(nforce),fresi(nforce))
    ftang=0.
    fresi=0.

    do iforce=1,nforce
        if(nforce_appear(iforce)/=1.and.nforce_appear(iforce)/=3)cycle !zhao 2010
        do jgroup=1,surface_force(iforce)%lgroup
            igroup=surface_force(iforce)%list(jgroup)
            index = group(igroup)%index
            nstre =group(igroup)%nstre
            matno =group(igroup)%matno
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus
            elcod_local=group(igroup)%elcod_local
            uniax   =props(matno)%mechanical%solid%classicalEP%sigma0
            frict   =props(matno)%mechanical%solid%classicalEP%frict_angle
            ivcoh=group(igroup)%ivcoh
            ivfri=group(igroup)%ivfri
            if(ivcoh==0.or.ivfri==0)cycle
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                do igaus=1,ngaus
                    yld=element(ielem)%field(1)%gpvar(nstre+2,igaus)
                    if (yld/=2.) then
                        aera=1./elcod_local*element(ielem)%egaus(1)%djacb(igaus)
                        fn=element(ielem)%field(1)%ntstress(1,igaus)
                        ft=element(ielem)%field(1)%ntstress(2,igaus)
                        fresi(iforce)=fresi(iforce)-fn*aera*xa(ivfri)+xa(ivcoh)*aera
                        ftang(iforce)=ftang(iforce)+ft*aera
                        rc(ivcoh)=rc(ivcoh)+aera
                        rc(ivfri)=rc(ivfri)-fn*aera

                    endif
                end do
            end do
        end do
        write(chkunit,*)'iforce=',iforce
        write(chkunit,*)'fresi=',fresi(iforce),'ftang=',ftang(iforce)
    end do !iforce

10  continue
    if(ngaps/=0)then
        allocate(fresi_gaps(ngaps),ftang_gaps(ngaps))
        fresi_gaps=0.;ftang_gaps=0.
        do igaps=1,ngaps
            if(nforce_gaps_appear(igaps)==2.or.nforce_gaps_appear(igaps)==0)cycle
            ivcoh=gaps(igaps)%ivcoh
            ivfri=gaps(igaps)%ivfri
            if(ivcoh==0.or.ivfri==0)cycle
            npairs=gaps(igaps)%npairs
            do ipairs=1,npairs

                fresi_gaps(igaps)=fresi_gaps(igaps)+gaps(igaps)%aera(ipairs)*xa(ivcoh)-gaps(igaps)%ctforce(ndimn,ipairs)*xa(ivfri)
                rc(ivcoh)=rc(ivcoh)+gaps(igaps)%aera(ipairs)
                rc(ivfri)=rc(ivfri)-gaps(igaps)%ctforce(ndimn,ipairs)
                t1=gaps(igaps)%ctforce(1,ipairs)
                if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                tt=abs(t1)
                if (ndimn==3)tt=sqrt(t1**2+t2**2)
                ftang_gaps(igaps)=ftang_gaps(igaps)+tt
            end do
        enddo
    end if

    fresit=0.;ftangt=0.
    if(nforce/=0)fresit=sum(fresi)
    if(ngaps/=0) fresit=fresit+sum(fresi_gaps)
    if(nforce/=0)ftangt=sum(ftang)
    if(ngaps/=0) ftangt=ftangt+sum(ftang_gaps)
    if(ngaps/=0)then
        write(chkunit,*)'fresit=',fresit,'ftangt=',ftangt
        write(chkunit,*)'fresi_gaps=',fresi_gaps
        write(chkunit,*)'ftang_gaps=',ftang_gaps
    endif

    Gy=fresit-ftangt

    write(7,*)'Gy=',Gy,'Rc=',Rc

    if(nforce/=0) &
        deallocate(ftang,fresi)
    if(ngaps/=0) &
        deallocate(ftang_gaps,fresi_gaps)

    end subroutine stab_rcandgy_reli  !2018/01/10
    subroutine FORCE_interface
    character(20)material,criteria
    integer(ink) ielem,idofn,inode,idimn,igroup,iforce,iextrf, &
        jelem,jgroup,ipoin,ne_unode,ipface,matno,ig,mgroup,index,nevab
    integer(ink),allocatable::ice(:),icp(:)
    integer(ink),pointer::lnods(:),liste(:)
    real   (irk),pointer::eload(:),tload(:),elcod(:,:)

    allocate(ice(nelem)) !,icp(npoin))
    do iforce=1,nforce
        ice=0
        liste=>surface_force(iforce)%liste
        ice(liste)=1
        if (nliste==2)then
            nullify(liste)
            liste=>surface_force(iforce)%liste1
            ice(liste)=1
        endif
        nullify(liste)
        surface_force(iforce)%ftfor=0.0

        !npface=surface_force(iforce)%npface
        !icp=0
        !do ipface=1,npface
        !   ipoin=surface_force(iforce)%list_npface(ipface)
        !	icp(ipoin)=ipface
        !enddo

        !       do ielem=1,nelem
        !	      if(ice(ielem)==0)cycle
        !            lnods=>element(ielem)%field(1)%lnods_f
        !            eload=>element(ielem)%field(1)%eload
        !            tload=>element(ielem)%field(1)%tload
        !			do inode=1,size(lnods)
        !			   ipoin=lnods(inode)
        !			   if(icp(ipoin)==0)cycle
        !               do idimn=1,ndimn
        !                  idofn=(inode-1)*ndimn+idimn
        !                  surface_force(iforce)%ftfor(idimn,icp(ipoin))=   &
        !                  surface_force(iforce)%ftfor(idimn,icp(ipoin))+eload(idofn)-tload(idofn)
        !                end do
        !			enddo
        !			nullify(eload,tload)
        !	   enddo



        do jgroup=1,surface_force(iforce)%lgroup
            igroup=surface_force(iforce)%list(jgroup)
            index=group(igroup)%index
            if (appear(igroup).gt.0) then
                matno = group(igroup)%matno
                material=props(matno)%mechanical%solid%material
                npface=surface_force(iforce)%npface
                do ipface=1,npface
                    ipoin=surface_force(iforce)%list_npface(ipface)
                    mgroup=listp_group(ipoin)%mgroup
                    do ig=1,mgroup
                        if(listp_group(ipoin)%listg(ig)==igroup) goto 1
                    end do
                    goto 2
1                   ne_unode=group(igroup)%unode(listp_group(ipoin)%listp(ig))%ne_unode

                    do jelem=1,ne_unode
                        ielem=group(igroup)%unode(listp_group(ipoin)%listp(ig))%list(jelem)
                        if (ice(ielem)==1) then

                            elcod=>element(ielem)%field(1)%elcod_f

                            lnods=>element(ielem)%field(1)%lnods_f
                            eload=>element(ielem)%field(1)%eload
                            tload=>element(ielem)%field(1)%tload
                            nevab=size(eload)
                            do inode=1,size(lnods)
                                if (lnods(inode)==ipoin) then
                                    do idimn=1,ndimn
                                        idofn=(inode-1)*ndimn+idimn
                                        if(index==20)idofn=(inode-1)*nevab/2+idimn !steel 2008
                                        surface_force(iforce)%ftfor(idimn,ipface)=   &
                                            surface_force(iforce)%ftfor(idimn,ipface)+eload(idofn)-tload(idofn)
                                    end do
                                end if
                            end do
                            nullify(tload,eload,lnods)
                            nullify(elcod)
                        end if
                    end do !jelem
2                   continue
                end do ! ipface
            endif  !for appear(igroup).gt.0
        end do !jgroup

        !nullify(liste)

        if (nextrf/=0)then  !2004/9/11
            if (istep>nextrf)then
                do iextrf=1,nextrf-1
                    surface_force(iforce)%ftfor_ext(:,:,iextrf+1)=  &
                        surface_force(iforce)%ftfor_ext(:,:,iextrf)
                end do
                surface_force(iforce)%ftfor_ext(:,:,1)=surface_force(iforce)%ftfor
            else
                if(istep==1)surface_force(iforce)%ftfor_ext(:,:,:)=0.
                do iextrf=1,istep-1
                    surface_force(iforce)%ftfor_ext(:,:,iextrf+1)=  &
                        surface_force(iforce)%ftfor_ext(:,:,iextrf)
                end do
                surface_force(iforce)%ftfor_ext(:,:,1)=surface_force(iforce)%ftfor
            endif
        endif   !2004/9/11
    end do !iforce
    deallocate(ice) !,icp)

    end subroutine FORCE_interface



    subroutine write_force_interface
    integer(ink) ipoin,npface,iforce,jpoin
    real   (irk),allocatable::force0(:)
    allocate(force0(ndimn))
    write(ftfunit,*)'ttime=',ttime

    do iforce=1,nforce
        if(nforce_appear(iforce)/=2.and.nforce_appear(iforce)/=3)cycle !zhao 2010
        write(ftfunit,*)'iforce=',iforce
        npface=surface_force(iforce)%npface
        do ipoin=1,npface
            jpoin=surface_force(iforce)%list_npface(ipoin) !steel 2008
            force0=surface_force(iforce)%ftfor(:,ipoin)

            if(icpnorm(jpoin)/=0)surface_force(iforce)%ftfor(:,ipoin)=transpose(prot(:,:,jpoin)).x.force0

            write(ftfunit,1)ipoin,surface_force(iforce)%list_npface(ipoin),surface_force(iforce)%ftfor(:,ipoin)

        end do
        write(ftfunit,*)'total force on x =',sum(surface_force(iforce)%ftfor(1,1:npface))
        write(ftfunit,*)'total force on y =',sum(surface_force(iforce)%ftfor(2,1:npface))
        if(ndimn==3)write(ftfunit,*)'total force on z =',sum(surface_force(iforce)%ftfor(3,1:npface))
    end do
1   format(1x,2i10,3e20.4)

    deallocate(force0)

    end subroutine write_force_interface

    subroutine judge_fine_mesh(igroup,icjr)

    integer(ink) igroup,icjr,nstre,ngaus,igaus,index,ielem,ielgroup
    real   (irk) sx,sy,sxy,delta
    real   (irk),allocatable::smain(:),rr(:,:),stres(:)

    index = group(igroup)%index
    ngaus = elkn(index)%ggaus(1)%ngaus
    nstre=4
    if(ndimn==3)nstre=6
    allocate(stres(nstre),rr(ndimn,ndimn),smain(ndimn))

    icjr=0
    DO ielgroup = 1,group(igroup)%nelgroup
        ielem    = group(igroup)%list(ielgroup)
        do igaus=1,ngaus
            stres=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            if (ndimn==2) then
                sx=stres(1)
                sy=stres(2)
                sxy=stres(3)
                delta=sqrt((sx-sy)**2/4+sxy**2)
                smain=0.
                if(delta.lt.1.e-5) goto 12
                smain(1)=(sx+sy)/2.+delta
                smain(2)=(sx+sy)/2.-delta
12              continue
            else
                call stresmr ( stres, smain, rr)
            endif
            if(smain(1)>500.)icjr=1
        end do
    end do
    deallocate(stres,rr,smain)

    end subroutine judge_fine_mesh

    subroutine find_remesh_element1

    integer(ink) ielem,nstre
    integer(ink),allocatable::rele(:)
    allocate(rele(nelem))
    rele=0
    !if(iblks>1)return
    do ielem=1,nelem
        if(ice0(ielem)==1) goto 10
        nstre=4
        if(ndimn==3)nstre=6
        if(any(element(ielem)%field(1)%gpvar(nstre+3,:)>valv1))rele(ielem)=1
10      continue
    end do
    nelc=sum(rele)
    if (nelc>0)then
        allocate(listnelc(nelc))
        nelc=0
        do ielem=1,nelem
            if (rele(ielem)==1)then
                nelc=nelc+1
                listnelc(nelc)=ielem
            endif
        end do
    endif
    deallocate(rele)

    end subroutine find_remesh_element1

    subroutine find_remesh_element2

    integer(ink) ielem,nstre
    integer(ink),allocatable::rele(:)
    allocate(rele(nelem1))
    rele=0
    !return
    do ielem=1,nelem1
        if(jce1(ielem)==1) goto 10
        nstre=4
        if(ndimn==3)nstre=6
        if(any(element1(ielem)%field(1)%gpvar(nstre+3,:)>valv2))rele(ielem)=1
10      continue
    end do
    nelc1=sum(rele)
    if (nelc1>0)then
        allocate(listnelc1(nelc1))
        nelc1=0
        do ielem=1,nelem1
            if (rele(ielem)==1)then
                nelc1=nelc1+1
                listnelc1(nelc1)=ielem
            endif
        end do
    endif
    deallocate(rele)

    end subroutine find_remesh_element2


    SUBROUTINE  find_remesh_stran

    !*********************************************************************
    !
    !*** by aera weighting average (only for Q4 and B8) elements
    !
    !********************************************************************
    character(10)fieldid,class,material,name
    integer(ink) igroup,index,order_int,ngaus,nevab,idimn,  &
        ipoin,ielem,matno,nnode,ielgroup,nstre
    integer(ink), pointer::lnods(:),ldofs(:)
    integer(ink),allocatable::rele(:)
    real   (irk) elcod_local,stranmax,stranmax1,tstran
    real   (irk),allocatable::stran(:),cartd(:,:),eldis(:),valun(:),valun1(:)

    allocate(valun(nelem))
    if(nelem1>0)allocate(valun1(nelem1))
    valun=0.
    if(nelem1>0)valun1=0.
    do igroup=1,ngroup

        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='U')then
            class=group(igroup)%class

            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            index=group(igroup)%index
            nnode=elkn(index)%nnode
            elcod_local=group(igroup)%elcod_local
            if (elcod_local==0..and.fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT'.and.nnode/=2)then
                order_int=elkn(index)%el_field(1)%order_intrules(1)

                ngaus=elkn(index)%ggaus(order_int)%ngaus
                nstre=group(igroup)%nstre
                nevab=nnode*ndimn
                allocate (stran(ndimn),cartd(ndimn,nnode),eldis(nevab))
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (ice0(ielem)==0)then
                        lnods=>element(ielem)%field(1)%lnods_f
                        ldofs=>element(ielem)%field(1)%ldofs_f
                        eldis = result_zero(ldofs)
                        valun(ielem)=0.
                        !                  do igaus=1,ngaus
                        !                     cartd=element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                        !                     do idimn=1,ndimn
                        !                        stran(idimn)=0.
                        !                        do inode=1,nnode
                        !                           stran(idimn)=stran(idimn)+cartd(idimn,inode)*eldis(ndimn*(inode-1)+idimn)
                        !                        end do
                        !                     end do
                        !                     tstran=sqrt(sum(stran(1:ndimn)**2))
                        !                     valun(ielem)=valun(ielem)+tstran
                        !                  end do
                        valun(ielem)=sum(element(ielem)%field(1)%gpvar(nstre+1,:))
                        valun(ielem)=valun(ielem)/ngaus
                        nullify(lnods,ldofs)
                    endif
                end do

                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                if (nelem1>0)then
                    DO ielgroup = 1,group1(igroup)%nelgroup
                        ielem = group1(igroup)%list(ielgroup)
                        if (jce1(ielem)==0)then
                            lnods=>element1(ielem)%field(1)%lnods_f
                            ldofs=>element1(ielem)%field(1)%ldofs_f
                            eldis = result_zero(ldofs)
                            valun1(ielem)=0.
                            do igaus=1,ngaus
                                cartd=element1(ielem)%egaus(order_int)%cartd(:,:,igaus)
                                do idimn=1,ndimn
                                    stran(idimn)=0.
                                    do inode=1,nnode
                                        stran(idimn)=stran(idimn)+cartd(idimn,inode)*eldis(ndimn*(inode-1)+idimn)
                                    end do
                                end do
                                tstran=sqrt(sum(stran(1:ndimn)**2))
                                valun1(ielem)=valun1(ielem)+tstran
                            end do
                            valun1(ielem)=valun1(ielem)/ngaus
                            nullify(lnods,ldofs)
                        endif
                    end do
                endif
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                deallocate (stran,cartd,eldis)
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            endif           !! for(U,CO)
        endif                            !!for appear>0
    end do !! for igroup
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    stranmax=maxval(valun)
    stranmax1=0.
    if(nelem1>0)stranmax1=maxval(valun1)
    print *,'stranmax=',stranmax,'stranmax1=',stranmax1
    !if(stranmax1>stranmax)stranmax=stranmax1

    allocate(rele(nelem))
    rele=0
    do ielem=1,nelem
        if (ice0(ielem)==0) then
            !         if(valun(ielem)>.98*stranmax)rele(ielem)=1   !for rmesh=1
            if(valun(ielem)>.05*stranmax)rele(ielem)=1  !for rmesh=-1
        endif
    end do
    nelc=sum(rele)
    if (nelc>0)then
        allocate(listnelc(nelc))
        nelc=0
        do ielem=1,nelem
            if (rele(ielem)==1)then
                nelc=nelc+1
                listnelc(nelc)=ielem
            endif
        end do
    endif
    deallocate(rele)

    if(rmesh==1)return

    allocate(rele(nelem1))
    rele=0
    !   return
    do ielem=1,nelem1
        if (jce1(ielem)==0)  then
            if(valun1(ielem)>.5*stranmax)rele(ielem)=1
        endif
    end do
    nelc1=sum(rele)
    if (nelc1>0)then
        allocate(listnelc1(nelc1))
        nelc1=0
        do ielem=1,nelem1
            if (rele(ielem)==1)then
                nelc1=nelc1+1
                listnelc1(nelc1)=ielem
            endif
        end do
    endif
    deallocate(rele)

    END SUBROUTINE find_remesh_stran
    !**************************************

    subroutine modf_inpwav         !hxl2006 MIF

    character(80)text
    integer(ink) idofn,idofix,iwavcurve,ifixvar,ifixvar0,ilaymif,inpvar
    real   (irk) dfact1,dfact2,frecoord,bfrecoord
    integer(ink),pointer::lnofixb(:),ldofixb(:)

    do idofix=1,ndofix
        ifixvar=prescrib(idofix)%ifixvar
        ifixvar0=prescrib(idofix)%ifixvar0
        bfrecoord=prescrib(idofix)%bfrecoord
        iwavcurve=earthquake_curve_MIF(ifixvar)
        if(iwavcurve==0)cycle
        lnofixb=>prescrib(idofix)%lnofixb
        ldofixb=>prescrib(idofix)%ldofixb
        inpvar=abs(ifixvar0_inpb)
        if (ifixvar0_inpb==ifixvar0)then !底边界
            do ilaymif=1,nlaymif
                tcurves(iwavcurve)%dtbegin=abs(coord(inpvar,lnofixb(ilaymif))-inpcord)/camif !入射位移波传播至当前层的时间
                call dfact_time_curve(ttime)
                inpru(ldofixb(ilaymif))=tcurves(iwavcurve)%dfact !当前层的入射位移波
                tcurves(iwavcurve)%dtbegin=0.0
            enddo
        else
            do ilaymif=1,nlaymif
                tcurves(iwavcurve)%dtbegin=abs(coord(inpvar,lnofixb(ilaymif))-inpcord)/camif
                call dfact_time_curve(ttime)
                dfact1=tcurves(iwavcurve)%dfact !入射波
                tcurves(iwavcurve)%dtbegin=abs((bfrecoord-inpcord)/camif)+abs(coord(inpvar,lnofixb(ilaymif))-bfrecoord)/camif
                call dfact_time_curve(ttime)
                dfact2=tcurves(iwavcurve)%dfact !入射波传播至自由表面后下行反射波
                inpzi(ldofixb(ilaymif))=dfact1+dfact2 !二者的迭加就是自由场
                tcurves(iwavcurve)%dtbegin=0.0
            enddo
        endif
        nullify(lnofixb,ldofixb)
    enddo

    end subroutine modf_inpwav
    !!!!20231215YL
    !----------------------------------------------------------------
    subroutine liquifaction_judge  !20231008

    character(1)field1
    integer(ink)igroup,liquj,ij,index,matno,order_int,ngaus,nalfa,ncycl,  &
        ielgroup,ielem,npeak,id
    real(irk) ceqcy(14),bi,bj,bm,bijm,stmax,ratio,dts,dts_1,neqcy,sigma0,  &
        tshear,tyz,tzx,taij,tbij,alfa1,alfa2,alfac,cycl1,cycl2,tstrength
    real(irk),allocatable::qtime(:),tai(:),tbi(:),speak(:),kliqu(:)
    real(irk),pointer::ta(:,:),tb(:,:),alfai(:),cycli(:)
    DATA ceqcy/3.,2.7,2.4,2.05,1.7,1.4,1.2,1.0,.76,.4,.2,.1,.04,.02/


    rewind(lquunit)

    print *,'in liqu_judge,nliqu=',nliqu
    allocate(shear(ngroup),qtime(nliqu))

    DO igroup =1,ngroup
        liquj=  group(igroup)%liquj
        field1= group(igroup)%fieldid(1:1)
        if(appear(igroup)>0.and.field1=='U'.and.liquj==1) then
            allocate(shear(igroup)%stres(nliqu,group(igroup)%nelgroup))
        endif
    end do

    do i0=1,nliqu
        read(lquunit)qtime(i0)
        !  write(7,*)'qtime=',qtime(i0)
        DO igroup =1,ngroup
            liquj=  group(igroup)%liquj
            field1= group(igroup)%fieldid(1:1)
            if(appear(igroup)>0.and.field1=='U'.and.liquj==1) then
                read(lquunit)shear(igroup)%stres(i0,:)
            endif
        end do
    end do
    !!!!!!分组计算周数

    DO igroup =1,ngroup
        liquj=  group(igroup)%liquj
        field1= group(igroup)%fieldid(1:1)
        if(appear(igroup)>0.and.field1=='U'.and.liquj==1) then
            index=group(igroup)%index
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus=elkn(index)%ggaus(order_int)%ngaus
            matno=group(igroup)%matno
            if(props(matno)%mechanical%solid%jliqu==0)then
                print *,'stop err in material number,  &
                    should include the parameters for liqufaction'
                stop
            endif

            nalfa=props(matno)%mechanical%solid%scycl%nalfa
            ncycl=props(matno)%mechanical%solid%scycl%ncycl
            ta=>props(matno)%mechanical%solid%scycl%ta
            tb=>props(matno)%mechanical%solid%scycl%tb
            alfai=>props(matno)%mechanical%solid%scycl%alfai
            cycli=>props(matno)%mechanical%solid%scycl%cycli
            allocate(tai(ncycl),tbi(ncycl))
            allocate(speak(nliqu),kliqu(group(igroup)%nelgroup))
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)

                npeak=0
                !!计算峰值点个数
                do i0=2,nliqu-1
                    bi=shear(igroup)%stres(i0-1,ielgroup)
                    bj=shear(igroup)%stres(i0,ielgroup)
                    bm=shear(igroup)%stres(i0+1,ielgroup)
                    bijm=(bj-bi)*(bj-bm)
                    !			write(7,*)'ig=',igroup,'ie=',ielgroup,'bi,bj,bm=',bi,bj,bm,'bijm=',bijm
                    if(bijm>0)then
                        if((bj>0..and.(bj-bi)>0.).or.(bj<0..and.(bj-bi)<0.))then
                            npeak=npeak+1
                            !				  write(7,*)'npeak=',npeak
                            speak(npeak)=bj
                        endif
                    endif
                end do
                !        write(7,*)'ig=',igroup,'ie=',ielgroup,'npeak=',npeak,'speak=',speak(1:npeak)
                !!end计算峰值点个数
                !!计算等效周数
                neqcy=0
                if(npeak>0)then
                    !write(7,*)'*******************************npeak=*********************',npeak
                    stmax=maxval(abs(shear(igroup)%stres(:,ielgroup)))
                    speak=abs(speak)/stmax

                    do ij=1,npeak
                        do id=1,14
                            dts=1.-(id-1)*.05
                            dts_1=dts-.05
                            if(id==14)dts_1=0.
                            if(speak(ij)<=dts.and.speak(ij)>dts_1)neqcy=neqcy+.5*ceqcy(id)
                        end do
                    end do
                end if
                !	print *,'neqcy=',neqcy
                element(ielem)%neqcy=neqcy
                !!end计算等效周数
                !! take out the initial vertical normal stress and the horizontal shear stress
                !sigma0=sum(element(ielem)%field(1)%STRES0(ndimn,:))/ngaus
                sigma0=sum(element(ielem)%STRES0(ndimn,:))/ngaus
                if(ndimn==2)then
                    !tshear=sum(element(ielem)%field(1)%STRES0(3,:))/ngaus
                    tshear=sum(element(ielem)%STRES0(3,:))/ngaus
                elseif(ndimn==3)then
                    !tyz=sum(element(ielem)%field(1)%STRES0(5,:))/ngaus
                    !tzx=sum(element(ielem)%field(1)%STRES0(6,:))/ngaus
                    tyz=sum(element(ielem)%STRES0(5,:))/ngaus
                    tzx=sum(element(ielem)%STRES0(6,:))/ngaus

                    tshear=sqrt(tyz**2+tzx**2)
                endif
                ratio=abs(tshear/sigma0)
                !	print *,'tshear=',tshear,'ratio=',ratio

                tai=0;tbi=0.
                if(ratio>=alfai(nalfa)) then
                    tai=ta(nalfa,:)
                    tbi=ta(nalfa,:)
                else
                    do i0=1,nalfa-1
                        alfa1=alfai(i0)
                        alfa2=alfai(i0+1)
                        if(ratio>=alfa1.and.ratio<alfa2) then
                            alfac=(ratio-alfa1)/(alfa2-alfa1)
                            tai(:)=ta(i0,:)+alfac*(ta(i0+1,:)-ta(i0,:))
                            tbi(:)=tb(i0,:)+alfac*(tb(i0+1,:)-tb(i0,:))
                            goto 10
                        endif
                    end do
                endif

10              taij=0.;tbij=0.

                if(neqcy<=cycli(1)) then
                    taij=tai(ncycl)
                    tbij=tbi(ncycl)
                elseif(neqcy>=cycli(ncycl)) then
                    taij=tai(ncycl)
                    tbij=tbi(ncycl)
                else
                    do i0=1,ncycl-1
                        cycl1=cycli(i0)
                        cycl2=cycli(i0+1)
                        if(neqcy>=cycl1.and.neqcy<=cycl2) then
                            alfac=(neqcy-cycl1)/(cycl2-cycl1)
                            taij=tai(i0)+alfac*(tai(i0+1)-tai(i0))
                            tbij=tbi(i0)+alfac*(tbi(i0+1)-tbi(i0))
                            goto 20
                        endif
                    end do
                endif

20              continue

                tstrength=tbij+taij*abs(sigma0)
                kliqu(ielgroup)=tstrength/(.65*stmax)
                !  write(7,*)'ielem=',ielem,'stmax=',stmax,'tstrength=',tstrength,'kliqu=',kliqu(ielgroup)
            end do
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                write(disunit,30)igroup,ielem,kliqu(ielgroup)
            end do
            deallocate(tai,tbi)
            deallocate(speak,kliqu)
            nullify(ta,tb)
        endif
    end do
    !!!!!!!
    DO igroup =1,ngroup
        liquj=  group(igroup)%liquj
        if(appear(igroup)>0.and.field1=='U'.and.liquj==1) then
            deallocate(shear(igroup)%stres)
        endif
    end do
    deallocate(shear,qtime)

30  format(2i10,e20.5)

    end subroutine liquifaction_judge
    !==============================================================================
    subroutine permdeform_judge !20231008

    character(100) name,material,SPtype,field1
    integer(ink) igroup,index,matno,nstre,nnode,ielgroup,ielem,igaus,ngaus,order_int,nevab,liquj
    real   (irk) pei,totneq,neqcy,theta,steff,smean,varj3,varj2,toct,p0,p,p3,s,q,qf,ROOT3,strain_s,devr,drr, &
        c1,c2,c3,c4,c5,vj3,phi,COHES,vj2,sint3
    real   (irk),allocatable::unitx(:),SGTOT(:),devia(:),rot(:),ps(:),eldis(:),bmatx(:,:),stran(:),stemp(:), &
        stmin(:),sigx(:),strand(:)
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::cartd(:,:),shape(:),gpcod(:)


    pei= 3.14159 ;       ROOT3=1.73205080757


    allocate(unitx(3*(ndimn-1)),ps(ndimn))
    ps=0. ; totneq=0.

    unitx=1.
    unitx(ndimn+1:3*(ndimn-1))=0.
    write(pmtunit,*)'ttime=',ttime,' istep=',istep
    DO igroup =1,ngroup
        liquj=  group(igroup)%liquj
        index   =group(igroup)%index
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        ngaus=elkn(index)%ggaus(order_int)%ngaus
        matno   =group(igroup)%matno
        name    =props(matno)%name
        field1= group(igroup)%fieldid(1:1)    ! nzw 2016-02-02   field1(1:1) for UW
        material=props(matno)%mechanical%solid%material
        if(appear(igroup)/=1.or.field1/='U'.or.material/='DUNCANCHANG'.or.liquj/=1)cycle !CR?    !psy.2018.09.20
        nstre   =group(igroup)%nstre
        SPtype  =group(igroup)%SPtype
        nnode   =elkn(index)%el_field(1)%nnode_f
        phi  =props(matno)%mechanical%solid%DuncanChang%phi
        COHES=props(matno)%mechanical%solid%DuncanChang%COHES
        p0   =props(matno)%mechanical%solid%DuncanChang%p0
        DO ielgroup=1,group(igroup)%nelgroup
            ielem=group(igroup)%list(ielgroup)
            neqcy=element(ielem)%neqcy
            !		  totneq=totneq+neqcy
            write(pmtunit,*)'igroup,   ielem,     neqcy'
            write(pmtunit,*) igroup,ielem,neqcy
            ldofs=>element(ielem)%field(1)%ldofs_f
            nevab=size(ldofs)      !   nevab=size(element(ielem)%ldofs)    nzw 2016-02-02   for UW
            allocate(eldis(nevab))
            eldis =result_zero(ldofs)
            do igaus=1,ngaus
                allocate(SGTOT(nstre),devia(nstre),rot(ndimn))
                devia=0. ; rot=0.

                !           SGTOT=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                SGTOT=element(ielem)%stres0(1:nstre,igaus)

                CALL INVART(matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
                if (ndimn==3)then
                    varj2=((SGTOT(1)-SGTOT(2))**2+(SGTOT(2)-SGTOT(3))**2+(SGTOT(1)-SGTOT(3))**2)/6.  &
                        +SGTOT(4)**2+SGTOT(5)**2+SGTOT(6)**2
                elseif(ndimn==2)then
                    if(nstre==3)then
                        varj2=((SGTOT(1)-SGTOT(2))**2+SGTOT(2)**2+SGTOT(1)**2)/6.+SGTOT(3)**2
                    elseif(nstre==4)then
                        varj2=((SGTOT(1)-SGTOT(2))**2+(SGTOT(2)-SGTOT(4))**2+(SGTOT(1)-SGTOT(4))**2)/6.  &
                            +SGTOT(3)**2
                    endif
                    !                 if (nstre==4)then
                    !                    varj2=((SGTOT(1)-SGTOT(2))**2+SGTOT(2)**2+SGTOT(1)**2)/6.+SGTOT(3)**2
                else
                    stop 'nstre ! permdeform_judge'
                endif
                !            endif
                toct=sqrt(2*varj2/3)
                ps(3)=-(2.*steff/root3*sin(theta+2*pei/3.)+smean)
                ps(2)=-(2.*steff/root3*sin(theta         )+smean)
                ps(1)=-(2.*steff/root3*sin(theta+4*pei/3.)+smean)
                p=ps(3)
                if(p<p0)p=p0
                p3=p
                Q=ps(1)-ps(3)
                Qf=(2.*p3*sinD(phi)+2.*COHES*COSD(phi))/(1-sind(phi))
                S=Q/QF
                if(s>1.)s=1.

                cartd=>element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                shape=>elkn(index)%ggaus(order_int)%shape(:,igaus)
                gpcod=>element(ielem)%egaus(order_int)%gpcod(:,igaus)
                allocate(bmatx(nstre,nevab),stran(nstre),stemp(nstre),stmin(ndimn))
                bmatx=0. ; stran=0. ; stmin=0.
                call gbmat(SPtype,nnode,bmatx,cartd,gpcod,shape)
                stran=matmul(bmatx,eldis)
                stemp=stran
                stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
                call main_stran_r( stemp, stmin)
                ! if(ndimn==2)strain_s=abs((stmin(1)-stmin(2)))*0.5  !最大剪应变(2D) !zhao
                ! if(ndimn==3)strain_s=abs((stmin(1)-stmin(3)))*0.5  !最大剪应变(3D)
                if(ndimn==2)strain_s=(stmin(1)-stmin(2))!*0.5  !最大剪应变(2D) !zhao
                !if(ndimn==3)strain_s=(stmin(1)-stmin(3))!*0.5  !最大剪应变(3D)
                if(ndimn==3)strain_s=sqrt(((stmin(1)-stmin(2))**2+(stmin(2)-stmin(3))**2+(stmin(3)-stmin(1))**2)*2)/3 !最大动剪应变 yuanli
                !			 if (strain_s<=0) stop
                !			 print *,'srain_s0'
                allocate(sigx(nstre))
                sigx=0.
                sigx=SGTOT
                !sigx(1:ndimn)=sigx(1:ndimn)-p
                p=-smean
                !if(p<.01)p=.01
                !if(p<p0)p=p0 !yuanli20230802
                sigx(1:ndimn)=-1*sigx(1:ndimn)-p
                sigx(ndimn+1:3*(ndimn-1))=-1*sigx(ndimn+1:3*(ndimn-1))*2.
                if(istep==nstepJP)write(pmtunit,'(2i8,6e18.6)')ielem,igaus,sigx
                write(pmtunit,'(2i8,6e18.6)')ielem,igaus,s,strain_s,toct
                deallocate(SGTOT,devia,rot,bmatx,stran,stemp,stmin,sigx)
                nullify(cartd,shape,gpcod)
            enddo !igaus
            nullify(ldofs)
            deallocate(eldis)
        enddo !ielem
    enddo !igroup

    end subroutine permdeform_judge
    !==============================================================================
    subroutine gamamaxupdate !20231008
    integer(ink) igroup,matno,index,ngaus,nstre,nnode,nevab,ielgroup,ielem,igaus
    integer(ink),pointer::ldofs(:)
    real(irk) gamad,gamad0
    real(irk),allocatable::eldis(:),bmatx(:,:),stran(:),stemp(:),stmin(:)
    character(100) name,material,fieldid

    DO igroup =1,ngroup
        if(appear(igroup)>0) then
            fieldid=group(igroup)%fieldid
            if(fieldid(1:1)=='U')then
                matno = group(igroup)%matno
                index = group(igroup)%index
                ngaus = elkn(index)%ggaus(1)%ngaus
                name  = props(matno)%name
                material=props(matno)%mechanical%solid%material
                if(material/='DUNCANCHANG')cycle
                nstre=  group(igroup)%nstre
                nnode = elkn(index)%el_field(1)%nnode_f
                nevab = nnode*group(igroup)%dof(1)%nfdof
                allocate(eldis(nevab),bmatx(nstre,nevab),stran(nstre),stemp(nstre),stmin(ndimn))
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    ldofs => element(ielem)%field(1)%ldofs_f
                    eldis = result_zero(ldofs)
                    do igaus = 1,ngaus
                        bmatx = element(ielem)%field(1)%bmatx(:,:,igaus)
                        stran = matmul(bmatx,eldis)
                        !未处理平面应力情况
                        stemp=stran
                        stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
                        call main_stran_r( stemp, stmin)
                        if(ndimn==2)gamad=abs((stmin(1)-stmin(2)))   !*0.5  !最大剪应变(2D) !zhao
                        !if(ndimn==3)strain_s=abs((stmin(1)-stmin(3)))   !*0.5  !最大剪应变(3D)
                        if(ndimn==3)gamad=sqrt(((stmin(1)-stmin(2))**2+(stmin(2)-stmin(3))**2+(stmin(3)-stmin(1))**2)*2)/3 !最大动剪应变 yuanli
                        gamad0 = element(ielem)%field(1)%gamamax0(igaus)
                        if(gamad>=gamad0)then
                            element(ielem)%field(1)%gamamax(igaus) = gamad
                            element(ielem)%field(1)%gamamax0(igaus) = gamad
                        else
                            element(ielem)%field(1)%gamamax(igaus) = gamad0
                            element(ielem)%field(1)%gamamax0(igaus) = gamad0
                        endif
                    enddo
                    nullify(ldofs)
                enddo
                deallocate(eldis,bmatx,stran,stemp,stmin)
            endif
        endif
    enddo

    end subroutine gamamaxupdate

    subroutine readgamamax !20231008
    integer(ink) igroup,matno,index,ngaus,ielgroup,ielem,igaus,i0
    character(100) material,fieldid,text
    Tgamamax0=0
    if(gamamax==1)then
        return
    elseif(gamamax==2)then
        DO igroup =1,ngroup
            if(appear(igroup)>0) then
                fieldid=group(igroup)%fieldid
                if(fieldid(1:1)=='U')then
                    matno = group(igroup)%matno
                    index = group(igroup)%index
                    ngaus = elkn(index)%ggaus(1)%ngaus
                    material=props(matno)%mechanical%solid%material
                    if(material/='DUNCANCHANG')cycle
                    read(gamamaxunit,*)i0
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        do igaus = 1,ngaus
                            read(gamamaxunit,*)i0,i0,element(ielem)%field(1)%gamamax_ini(igaus),element(ielem)%field(1)%gamamax_error(igaus)
                        enddo
                    enddo
                endif
            endif
        enddo
        read(gamamaxunit,*) text,i0,text,Tgamamax0,text,i0
    endif


    end subroutine readgamamax

    subroutine writegamamax !20231008
    integer(ink) igroup,matno,index,ngaus,ielgroup,ielem,igaus
    real(irk) gamamax_error_max,gamamax_ratio
    character(100) material,fieldid
    rewind(gamamaxunit)
    Tgamamax=0
    DO igroup =1,ngroup
        if(appear(igroup)>0) then
            fieldid=group(igroup)%fieldid
            if(fieldid(1:1)=='U')then
                matno = group(igroup)%matno
                index = group(igroup)%index
                ngaus = elkn(index)%ggaus(1)%ngaus
                material=props(matno)%mechanical%solid%material
                if(material/='DUNCANCHANG')cycle
                write(gamamaxunit,*)igroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    do igaus = 1,ngaus
                        element(ielem)%field(1)%gamamax_error(igaus) = abs((element(ielem)%field(1)%gamamax(igaus)-element(ielem)%field(1)%gamamax_ini(igaus))/element(ielem)%field(1)%gamamax(igaus))
                        element(ielem)%field(1)%gamamax_ini(igaus) = element(ielem)%field(1)%gamamax(igaus)
                        Tgamamax=Tgamamax+element(ielem)%field(1)%gamamax(igaus)
                        write(gamamaxunit,*)ielem,igaus,element(ielem)%field(1)%gamamax_ini(igaus),element(ielem)%field(1)%gamamax_error(igaus)
                        if(gamamax_error_max<element(ielem)%field(1)%gamamax_error(igaus))gamamax_error_max = element(ielem)%field(1)%gamamax_error(igaus)
                    enddo
                enddo
            endif
        endif
    enddo
    gamamax_ratio=abs(Tgamamax-Tgamamax0)/Tgamamax
    write(gamamaxunit,*) '结点最大相对误差',gamamax_error_max,'总误差',Tgamamax,'总相对误差',gamamax_ratio
    close(gamamaxunit)
    end subroutine writegamamax

    !!!!20231215YL

    !===================================================
    SUBROUTINE inivdval !20220721
    character(10) fieldid
    integer(ink) igroup,ielgroup,ielem,matno,order_int,index,igaus,ngaus

    DO igroup =1,ngroup

        if(appear(igroup)>0) then

            fieldid=group(igroup)%fieldid

            if(fieldid(1:2)=='UW'.or.fieldid(1:1)=='U') then		!nzw 2006-06-19 for PZ to U field
                matno = group(igroup)%matno
                index = group(igroup)%index

                if(props(matno)%mechanical%solid%material=='SandPZ'.or. &
                    props(matno)%mechanical%solid%material=='ClayPZ')then

                    order_int=elkn(index)%el_field(1)%order_intrules(1)

                    ngaus = elkn(index)%ggaus(order_int)%ngaus

                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        element(ielem)%egaus(order_int)%iload0=0
                        element(ielem)%egaus(order_int)%vdval0=0.
                        element(ielem)%egaus(order_int)%iload =0
                        element(ielem)%egaus(order_int)%vdval =0.


                        if(ndimn==2)then

                            do igaus=1,ngaus

                                element(ielem)%egaus(order_int)%vdval0(5,igaus)=           &
                                    -(element(ielem)%field(1)%gpvar0(1,igaus)+         &
                                    element(ielem)%field(1)%gpvar0(2,igaus)+           &
                                    element(ielem)%field(1)%gpvar0(4,igaus))/3.

                                element(ielem)%egaus(order_int)%vdval(5,igaus)=            &
                                    -(element(ielem)%field(1)%gpvar0(1,igaus)+         &
                                    element(ielem)%field(1)%gpvar0(2,igaus)+           &
                                    element(ielem)%field(1)%gpvar0(4,igaus))/3.
                            enddo

                        elseif(ndimn==3)then
                            do igaus=1,ngaus

                                element(ielem)%egaus(order_int)%vdval0(5,igaus)=           &
                                    -(element(ielem)%field(1)%gpvar0(1,igaus)+         &
                                    element(ielem)%field(1)%gpvar0(2,igaus)+           &
                                    element(ielem)%field(1)%gpvar0(3,igaus))/3.

                                element(ielem)%egaus(order_int)%vdval(5,igaus)=            &
                                    -(element(ielem)%field(1)%gpvar0(1,igaus)+         &
                                    element(ielem)%field(1)%gpvar0(2,igaus)+           &
                                    element(ielem)%field(1)%gpvar0(3,igaus))/3.
                            enddo
                        else
                            write(*,*) 'in sub inivaval, ndimn should be 2 or 3'
                            stop
                        endif

                        if(props(matno)%mechanical%solid%material=='ClayPZ')then
                            element(ielem)%egaus(order_int)%vdval0(3,:)=props(matno)%mechanical%solid%ClayPZ%d(10)
                            element(ielem)%egaus(order_int)%vdval(3,:) =props(matno)%mechanical%solid%ClayPZ%d(10)
                            element(ielem)%egaus(order_int)%vdval0(4,:)=props(matno)%mechanical%solid%ClayPZ%d(10)
                            element(ielem)%egaus(order_int)%vdval(4,:) =props(matno)%mechanical%solid%ClayPZ%d(10)
                        elseif(props(matno)%mechanical%solid%material=='SandPZ')then
                            element(ielem)%egaus(order_int)%vdval0(2,:)=props(matno)%mechanical%solid%SandPZ%d(12)   !Hu0
                            element(ielem)%egaus(order_int)%vdval (2,:)=props(matno)%mechanical%solid%SandPZ%d(12)
                        endif
                    end do
                endif
            endif

        endif
    end do

    END  SUBROUTINE inivdval  !20220721
    !===================================================

    subroutine strain_for_steel_bar
    integer(ink) ielem,index,nnode,igroup,nevab,ipoin
    real   (irk) dl
    integer(ink),pointer::lnods(:),ldofs(:)
    real   (irk),pointer::rotation(:,:)
    real   (irk),allocatable::eldis(:)

    pstrain=0.

    do ielem=1,nelem
        index =element(ielem)%index
        if (index/=20.and.index/=1)cycle  !20200628
        nnode =elkn(index)%nnode
        igroup=element(ielem)%group
        if(appear(igroup)==0)cycle
        lnods=>element(ielem)%field(1)%lnods_f
        ldofs=> element(ielem)%field(1)%ldofs_f
        rotation=>element(ielem)%rotation
        nevab=size(ldofs) ; allocate(eldis(nevab)) ; eldis=0.
        dl=sqrt(sum((coord(:,lnods(2))-coord(:,lnods(1)))**2))
        eldis=result_zero(ldofs)
        if(nlocalbeam==0)then  !20230906
            !pstrain(lnods)=pstrain(lnods)+((eldis(nevab/2+1:nevab/2+ndimn)-eldis(1:ndimn)).d.rotation(1,:))/dl
            pstrain(lnods)=pstrain(lnods)+((eldis(ndimn+1:ndimn)-eldis(1:ndimn)).d.rotation(1,:))/dl !20230906
        else
            pstrain(lnods)=pstrain(lnods)+(eldis(nevab/2+1)-eldis(1))/dl
        endif
        nullify(lnods,ldofs,rotation)
        deallocate(eldis)
    enddo
    do ipoin=1,npoin
        if(icpspring(ipoin)<1)cycle
        pstrain(ipoin)=pstrain(ipoin)/real(icpspring(ipoin))
    enddo

    end subroutine strain_for_steel_bar

    !==============================================================================
    !--------------------------------------------------------
    subroutine change_list(listnode,index,nnode)
    integer(ink) index,nnode,listnode(nnode),nodeface(4),listnode0(nnode)
    integer(ink),allocatable::ipi(:)
    allocate(ipi(npoin))
    ipi=0
    ipi(listnode)=1
    select case(index)
    case(5,22)
        if(sum(ipi)==3)call change4(listnode)   !对退化的四边形处理
    case(9)
        if(sum(ipi)==6)then  !对退化的六面体处理
            ipi=0
            ipi(listnode(1:4))=1

            if(sum(ipi)==3)then
                nodeface=listnode(1:4)
                call change4(nodeface)
                listnode(1:4)=nodeface
                nodeface=listnode(5:8)
                call change4(nodeface)
                listnode(5:8)=nodeface
                deallocate(ipi)
                return
            endif

            ipi=0
            ipi(listnode(1))=1;ipi(listnode(5))=1;ipi(listnode(6))=1;ipi(listnode(2))=1
            if(sum(ipi)==3)then
                listnode0=listnode
                listnode(1)=listnode0(1)
                listnode(2)=listnode0(5)
                listnode(3)=listnode0(6)
                listnode(4)=listnode0(2)
                listnode(5)=listnode0(4)
                listnode(6)=listnode0(8)
                listnode(7)=listnode0(7)
                listnode(8)=listnode0(3)

                nodeface=listnode(1:4)
                call change4(nodeface)
                listnode(1:4)=nodeface
                nodeface=listnode(5:8)
                call change4(nodeface)
                listnode(5:8)=nodeface
                deallocate(ipi)
                return
            endif

            ipi=0
            ipi(listnode(2))=1;ipi(listnode(6))=1;ipi(listnode(7))=1;ipi(listnode(3))=1
            if(sum(ipi)==3)then
                listnode0=listnode
                listnode(1)=listnode0(2)
                listnode(2)=listnode0(6)
                listnode(3)=listnode0(7)
                listnode(4)=listnode0(3)
                listnode(5)=listnode0(1)
                listnode(6)=listnode0(5)
                listnode(7)=listnode0(8)
                listnode(8)=listnode0(4)

                nodeface=listnode(1:4)
                call change4(nodeface)
                listnode(1:4)=nodeface
                nodeface=listnode(5:8)
                call change4(nodeface)
                listnode(5:8)=nodeface
                deallocate(ipi)
                return
            endif
        endif
    end select
    if(allocated(ipi))deallocate(ipi)
    end subroutine change_list
    !--------------------------------------------------------
    subroutine change4(listnode)
    integer(ink) listnode(4),ipoin

    if(listnode(1)==listnode(2))then
        ipoin=listnode(1)
        listnode(1:2)=listnode(3:4)
        listnode(3:4)=ipoin
    elseif(listnode(2)==listnode(3))then
        ipoin=listnode(1)
        listnode(1)=listnode(4)
        listnode(2)=ipoin
        listnode(4)=listnode(3)
    elseif(listnode(1)==listnode(4))then
        ipoin=listnode(1)
        listnode(1:2)=listnode(2:3)
        listnode(3)=listnode(4)
    endif

    end subroutine change4

    !==============================================================================
    subroutine GHM2ADINA
    integer(ink),allocatable::ipiface(:),list_fix(:),val_fix(:),fix_xyz(:)
    integer(ink),pointer::lnods(:),nlist(:)
    real(irk),pointer::pxyz(:),fxyz(:,:)
    character*20 gname,name,material,criteria,text,sptype,type_curve
    integer(ink) adnunit,imat,nnode,nset,iplgroup,iedge,inode,edimn,ndofn,iset,   &
        ifixsets,nfixsets,ifixnods,nfixnods,pset,ntime,itime,nload_mass,iload_mass,idimn
    real(irk) density,e,nu,alpha,frict_angle,sigma0,pvalue,rot(3),dp_alfa,dp_k,r0,r1,deltatime

    adnunit=101
    open(adnunit,  file=trim(probn)//'.in')

    write(adnunit,1000)'DATABASE NEW SAVE=NO PROMPT=NO'
    write(adnunit,1000)'FEPROGRAM ADINA'
    write(adnunit,1000)'CONTROL FILEVERSION=V85'

    if(type_problem=='Q')write(adnunit,'(a)')'MASTER ANALYSIS=STATIC MODEX=EXECUTE TSTART=0.00000000000000,'
    if(type_problem=='F')write(adnunit,'(a)')'MASTER ANALYSIS=DYNAMIC-DIRECT-INTEGRATION MODEX=EXECUTE TSTART=0.00000000000000,'

    if(ndimn==2.and.MDOFN==2)then
        write(adnunit,'(a)')'     IDOF=100111 OVALIZAT=NONE FLUIDPOT=AUTOMATIC CYCLICPA=1,'
    elseif(ndimn==3.and.MDOFN==3)then
        write(adnunit,'(a)')'     IDOF=111 OVALIZAT=NONE FLUIDPOT=AUTOMATIC CYCLICPA=1,'
    endif
    write(adnunit,'(a)')'     IPOSIT=STOP REACTION=YES INITIALS=NO FSINTERA=NO IRINT=DEFAULT,'
    write(adnunit,'(a)')'     CMASS=NO SHELLNDO=AUTOMATIC AUTOMATI=OFF SOLVER=SPARSE,'
    write(adnunit,'(a)')'     CONTACT-=CONSTRAINT-FUNCTION TRELEASE=0.00000000000000,'
    write(adnunit,'(a)')'     RESTART-=NO FRACTURE=NO LOAD-CAS=NO LOAD-PEN=NO MAXSOLME=0,'
    write(adnunit,'(a)')'     MTOTM=2 RECL=3000 SINGULAR=YES STIFFNES=0.000100000000000000,'
    write(adnunit,'(a)')"     MAP-OUTP=NONE MAP-FORM=NO NODAL-DE='' POROUS-C=NO ADAPTIVE=0,"
    write(adnunit,'(a)')'     ZOOM-LAB=1 AXIS-CYC=0 PERIODIC=NO VECTOR-S=GEOMETRY EPSI-FIR=NO,'
    write(adnunit,'(a)')'     STABILIZ=NO STABFACT=1.00000000000000E-12 RESULTS=PORTHOLE,'
    write(adnunit,'(a)')'     FEFCORR=NO BOLTSTEP=1 EXTEND-S=YES CONVERT-=NO DEGEN=YES'

    !write material information
    write(adnunit,1000)'* define material proterties'
    do imat=1,nmats
        if(associated(props(imat)%mechanical%solid))then
            material=props(imat)%mechanical%solid%material
            density=props(imat)%mechanical%solid%density
            if(Bparameter/=0.and.props(imat)%mechanical%solid%ie/=0)then !20190810
                e=xvalue(props(imat)%mechanical%solid%ie)
            else
                e=props(imat)%mechanical%solid%e !exx !
            endif
            if(Bparameter/=0.and.props(imat)%mechanical%solid%iNu/=0)then
                Nu=xvalue(props(imat)%mechanical%solid%iNu)
            else
                Nu=props(imat)%mechanical%solid%Nu !uxx !
            endif
            alpha=props(imat)%mechanical%solid%alfa
            select    case(material)
            case('ELASTIC_ISOTROPIC')
                write(adnunit,'(a,i3,a,e16.6,a,f5.3,a)')'MATERIAL ELASTIC NAME=',imat,' E=',e,' NU=',nu,','
                write(adnunit,'(2(a,e16.6),a)')"     DENSITY=",density," ALPHA=",alpha," MDESCRIP='NONE'"
            case('CLASSICALEP')
                criteria=props(imat)%mechanical%solid%ClassicalEP%criteria
                if(criteria(1:2)=='MC')then
                    frict_angle=props(imat)%mechanical%solid%ClassicalEP%frict_angle
                    sigma0=props(imat)%mechanical%solid%ClassicalEP%sigma0
                    write(adnunit,'(a,i3,a,e16.6,a)')'MATERIAL MOHR-COULOMB NAME=',imat,' E=',e,','
                    write(adnunit,'(a,f5.3,a,f8.3,a)')'     NU=',nu,' PHI=',frict_angle,' PSI=0.00000000000000,'
                    write(adnunit,'(a,e16.6,a)')'     COH=',sigma0,' TCUT=0.00000000,'
                    write(adnunit,'(a,e16.6,a)')"     DENSITY=",density," DILATION=NO MDESCRIP='NONE'"
                elseif(criteria(1:2)=='DP')then
                    frict_angle=props(imat)%mechanical%solid%ClassicalEP%frict_angle
                    sigma0=props(imat)%mechanical%solid%ClassicalEP%sigma0
                    !if(criteria=='DP1')then !外顶点
                    !    dp_alfa=2.0*sind(frict_angle)/(sqrt(3.0)*(3.0-sind(frict_angle)))
                    !    dp_k=   6.0*sigma0*cosd(frict_angle)/(sqrt(3.0)*(3.0-sind(frict_angle)))
                    !elseif(criteria=='DP2')then !内顶点  DP3内切
                    dp_alfa=2.0*sind(frict_angle)/(sqrt(3.0)*(3.0+sind(frict_angle)))
                    dp_k=   6.0*sigma0*cosd(frict_angle)/(sqrt(3.0)*(3.0+sind(frict_angle)))
                    !else
                    !    write(*,*)'**********ERROR************'
                    !    write(*,*)'GHM2ADINA. Criteria should be DP1 or DP2 for matno=',imat
                    !    write(*,*)'**********ERROR************'
                    !    stop
                    !endif
                    write(adnunit,'(a,i3,a,e16.6,a)')'MATERIAL DRUCKER-PRAGER NAME=',imat,' E=',e,','
                    write(adnunit,'(a,f5.3,a,e16.6,a)')'     NU=',nu,' ALPHA=',dp_alfa,','
                    write(adnunit,'(a,e16.6,a)')'     KYIELD=',dp_k,' WCAP=-0.100000000000000,'
                    write(adnunit,'(a)')'     DCAP=-0.100000000000000 TCUT=100000.000000000,'
                    write(adnunit,'(a)')'     ICPOS=0.00000000000000 RCAP=0.00000000000000,'
                    write(adnunit,'(a,e16.6,a)')'     DENSITY=',density,' BETA=0.00000000000000 POTENTIA=NO,'
                    write(adnunit,'(a)')"     MDESCRIP='NONE'"
                endif
                case default
                write(adnunit,1000)'*This material is not included in adina. matno=',imat
                write(*,1000)'*This material is not included in adina. matno=',imat
                stop
            end select

        elseif(associated(props(imat)%mechanical%fluid))then
        else
        endif

        write(adnunit,1000)
    end do
    !write coordinate information
    write(adnunit,1000)'COORDINATES NODE SYSTEM=0'
    write(adnunit,1000)'@CLEAR'
    do ipoin=1,npoin
        if(ndimn==2)write(adnunit,1001)ipoin,0.0,coord(1:ndimn,ipoin)    !convert to YZ plane
        if(ndimn==3)write(adnunit,1001)ipoin,coord(1:ndimn,ipoin)
    end do
    write(adnunit,'(a)')'@'
    write(adnunit,'(a)')'*'

    !write element information
    write(adnunit,1000)'* define element information'

    do igroup=1,ngroup
        name=group(igroup)%kname
        index=group(igroup)%index
        nnode=elkn(index)%nnode
        sptype=group(igroup)%sptype
        if(sptype=='PS')sptype='STRESS'
        if(sptype=='PE')sptype='STRAIN'
        matno=matno_process(igroup,iblks)
        nnode=elkn(index)%nnode
        if(index==1.or.index==2)then
            write(adnunit,1002)
        elseif(index==19.or.index==20.or.index==21)then
            write(adnunit,1002)
        elseif(index==3.or.index==4)then
            write(adnunit,1002)
        elseif(index==5.or.index==6.or.index==12.or.index==16)then
            write(text,'(i4)')igroup
            write(adnunit,'(8a)')'EGROUP TWODSOLID NAME=',trim(ADJUSTL(text)),' SUBTYPE=',trim(sptype),' DISPLACE=DEFAULT,'
            write(adnunit,'(a,i3,a)')'     STRAINS=DEFAULT MATERIAL=',matno,' INT=DEFAULT RESULTS=STRESSES,'
            write(adnunit,'(a)')'     DEGEN=YES FORMULAT=0 STRESSRE=GLOBAL INITIALS=NONE FRACTUR=NO,'
            write(adnunit,'(a)')'     CMASS=DEFAULT STRAIN-F=0 UL-FORMU=DEFAULT PNTGPS=0 NODGPS=0,'
            write(adnunit,'(a)')'     LVUS1=0 LVUS2=0 SED=NO RUPTURE=ADINA INCOMPAT=DEFAULT,'
            write(adnunit,'(a)')'     TIME-OFF=0.00000000000000 POROUS=NO WTMC=1.00000000000000,'
            write(adnunit,'(a)')"     OPTION=NONE DESCRIPT='NONE' THICKNES=1.00000000000000,"
            write(adnunit,'(a)')'     PRINT=DEFAULT SAVE=DEFAULT TBIRTH=0.00000000000000,'
            write(adnunit,'(a)')'     TDEATH=0.00000000000000'
        elseif(index==22.or.index==26)then  !20230910
            write(adnunit,1002)
        elseif(index==7.or.index==8.or.index==13.or.index==17)then
            write(adnunit,1002)
        elseif(index==9.or.index==10.or.index==14.or.index==18)then
            write(text,'(i4)')igroup
            write(adnunit,'(3a,i3,a)')'EGROUP THREEDSOLID NAME=',trim(ADJUSTL(text)),' DISPLACE=DEFAULT STRAINS=DEFAULT MATERIAL=',matno,','
            write(adnunit,'(a)')'     RSINT=DEFAULT TINT=DEFAULT RESULTS=STRESSES DEGEN=YES FORMULAT=0,'
            write(adnunit,'(a)')'     STRESSRE=GLOBAL INITIALS=NONE FRACTUR=NO CMASS=DEFAULT,'
            write(adnunit,'(a)')'     STRAIN-F=0 UL-FORMU=DEFAULT LVUS1=0 LVUS2=0 SED=NO RUPTURE=ADINA,'
            write(adnunit,'(a)')'     INCOMPAT=DEFAULT TIME-OFF=0.00000000000000 POROUS=NO,'
            write(adnunit,'(a)')"     WTMC=1.00000000000000 OPTION=NONE DESCRIPT='NONE' PRINT=DEFAULT,"
            write(adnunit,'(a)')'     SAVE=DEFAULT TBIRTH=0.00000000000000 TDEATH=0.00000000000000'
        endif

        write(adnunit,'(3a)')'ENODES SUBSTRUC=0 GROUP=',trim(ADJUSTL(text)),' NNODES=32'
        write(adnunit,'(a)')'@CLEAR'

        DO ielgroup = 1,group(igroup)%nelgroup
            ielem = group(igroup)%list(ielgroup)
            lnods=>element(ielem)%field(1)%lnods_f
            call change_list(lnods,index,nnode)
            if(index==1)then
            elseif(index==5)then
                write(adnunit,'(5i8,a)')ielem,lnods,' 0 0 0 0 0'
            elseif(index==9)then
                write(adnunit,'(9i8,a)')ielem,lnods,' 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0'
            endif
            nullify(lnods)
        end do
    end do

    !write time curve
    do itcurve=1,ntcurve
        type_curve=tcurves(itcurve)%type_curve
        ntime=tcurves(itcurve)%ntime
        if(type_curve=='LINEAR'.or.type_curve=='SEISMIC')then
            write(adnunit,'(a,i2,a)')'TIMEFUNCTION NAME=',itcurve,' IFLIB=1 FPAR1=0.0,FPAR2=0.0 FPAR3=0.0,FPAR4=0.0 FPAR5=0.0,FPAR6=0.0'
            write(adnunit,'(a)')'@CLEAR'
            do itime=1,ntime
                if(type_curve=='SEISMIC')write(adnunit,'(2e16.6)')itime*tcurves(itcurve)%dtrec,tcurves(itcurve)%dfact_curve(itime)*tcurves(itcurve)%ample
                if(type_curve=='LINEAR')write(adnunit,'(2e16.6)')tcurves(itcurve)%ttime_curve(itime),tcurves(itcurve)%dfact_curve(itime)
            end do
            write(adnunit,'(a)')'@'
        endif
    end do

    !write node load
    nset=0
    do iplgroup=1,nplgroup

        pxyz=>pload(iplgroup)%pxyz
        rot=0.
        pvalue=sqrt(dot_product(pxyz,pxyz))
        if(pvalue>=1e-6)then
            nset=nset+1
            !define nole set
            nlist=>pload(iplgroup)%list
            write(adnunit,'(a,i3,a)')"NODESET NAME=",nset," ALL-EXT=NO DESCRIPT='NONE' OPTION=NODE GROUP=0 ZONE='',ELSET=0 TARGET=0"
            write(adnunit,'(a)')'@CLEAR'
            do inode=1,size(nlist,1)
                write(adnunit,'(i8,2i3)')nlist(inode),0,1
            end do
            write(adnunit,'(a)')'@'
            nullify(nlist)

            !define node load value and vector
            rot(1:ndimn)=pxyz/pvalue
            if(ndimn==2)then
                rot(3)=rot(2)
                rot(2)=rot(1)
                rot(1)=0.
            endif
            write(adnunit,'(a,i3,a,e16.6,a,f8.5,a)')'LOAD FORCE NAME=',iplgroup,' MAGNITUD=',pvalue,' FX=',rot(1),','
            write(adnunit,'(2(a,f8.5))')'     FY=',rot(2),' FZ=',rot(3)
        endif
        nullify(pxyz)
    end do

    !wirte face load
    allocate(ipiface(npoin),fxyz(ndimn,npoin))
    ipiface=0;fxyz=0.
    do iedge=1,nedge
        nnode=edges(iedge)%nnode
        index=edges(iedge)%index
        edimn=elkn(index)%ndimn
        nlist=>edges(iedge)%lnode
        ipiface(nlist)=1
        ndofn=ndimn
        do inode=1,nnode
            idofn=(inode-1)*ndofn
            fxyz(1:ndimn,nlist(inode))=fxyz(1:ndimn,nlist(inode))+edgeload(iedge)%edload(idofn+1:idofn+edimn+1)
        end do
        nullify(nlist)
    end do

    do ipoin=1,npoin
        if(ipiface(ipoin)==0)cycle
        rot=0.
        pvalue=sqrt(dot_product(fxyz(1:ndimn,ipoin),fxyz(1:ndimn,ipoin)))
        if(pvalue>=1e-6)then
            !define nole set
            nset=nset+1
            write(adnunit,'(a,i3,a)')"NODESET NAME=",nset," ALL-EXT=NO DESCRIPT='NONE' OPTION=NODE GROUP=0 ZONE='',"
            write(adnunit,'(a)')'ELSET=0 TARGET=0'
            write(adnunit,'(a)')'@CLEAR'
            write(adnunit,'(i8,2i3)')ipoin,0,1
            write(adnunit,'(a)')'@'

            rot(1:ndimn)=fxyz(1:ndimn,ipoin)/pvalue
            if(ndimn==2)then
                rot(3)=rot(2)
                rot(2)=rot(1)
                rot(1)=0.
            endif

            !define node load value and vector
            write(adnunit,'(a,i3,a,e16.6,a,f8.5,a)')'LOAD FORCE NAME=',nset,' MAGNITUD=',pvalue,' FX=',rot(1),','
            write(adnunit,'(2(a,f8.5))')'     FY=',rot(2),' FZ=',rot(3)
        endif
    end do

    if(.not.allocated(earthquake_curve))then
        allocate(earthquake_curve(ndimn))
        earthquake_curve=0
    endif
    read(mainunit,*)text
    !read(mainunit,*)nincs,r0,r1,earthquake_curve
    read(mainunit,*)nincs,earthquake_curve
    !define body load
    nload_mass=0
    if(any(tcurvegravity/=0)) then
        nload_mass=nload_mass+1
        write(adnunit,'(a,i2,a)')'LOAD MASS-PROPORTIONAL NAME=',nload_mass,' MAGNITUD=9.81,AX=0.0 AY=0.0 AZ=-1.0,INTERPRE=BODY-FORCE'
    endif
    if(earthquake_curve(1)/=0)then
        nload_mass=nload_mass+1
        write(adnunit,'(a,i2,a)')'LOAD MASS-PROPORTIONAL NAME=',nload_mass,' MAGNITUD=1.0,AX=1.0 AY=0.0 AZ=0.0,INTERPRE=GROUND-ACCELERATION'
    endif
    if(earthquake_curve(2)/=0)then
        nload_mass=nload_mass+1
        write(adnunit,'(a,i2,a)')'LOAD MASS-PROPORTIONAL NAME=',nload_mass,' MAGNITUD=1.0,AX=0.0 AY=1.0 AZ=0.0,INTERPRE=GROUND-ACCELERATION'
    endif
    if(ndimn==3)then
        if(earthquake_curve(3)/=0)then
            nload_mass=nload_mass+1
            write(adnunit,'(a,i2,a)')'LOAD MASS-PROPORTIONAL NAME=',nload_mass,' MAGNITUD=1.0,AX=0.0 AY=0.0 AZ=1.0,INTERPRE=GROUND-ACCELERATION'
        endif
    endif

    !apply node load to node set
    write(adnunit,'(a)')'APPLY-LOAD BODY=0'
    write(adnunit,'(a)')'@CLEAR'
    do iset=1,nset
        write(adnunit,'(i3,a,i3,a,i3,a)')iset,"  'FORCE' ",iset,"  'NODE' ",iset," 0 1 0.0 0 -1 0 0 0  'NO',0.0 0.0 1 0"
    end do
    nload_mass=0
    if(any(tcurvegravity/=0)) then
        nload_mass=nload_mass+1
        write(adnunit,'(i3,a,i3,a,i3,a)')iset,"  'MASS-PROPORTIONAL' ",nload_mass,"  'MODEL' 0 0 1 0.0 0 -1 0 0 0,'NO' 0.0 0.0 1 0"
    endif
    do idimn=1,ndimn
        if(earthquake_curve(idimn)==0)cycle
        nload_mass=nload_mass+1
        iset=iset+1
        write(adnunit,'(i3,a,i3,a,i3,a)')iset,"  'MASS-PROPORTIONAL' ",nload_mass,"  'MODEL' 0 0 ",earthquake_curve(idimn)," 0.0 0 -1 0 0 0,'NO' 0.0 0.0 1 0"
    end do
    write(adnunit,'(a)')'@'
    deallocate(ipiface,fxyz,earthquake_curve)

    !wirte constrains
    rewind(punit)
    pset=nset
    read(punit,*)text
    read(punit,*)nfixsets
    allocate(fix_xyz(nfixsets))
    fix_xyz=0
    do ifixsets=1,nfixsets
        read(punit,*)fix_xyz(ifixsets),nfixnods
        if(nfixnods<=0)cycle
        allocate(list_fix(nfixnods),val_fix(nfixnods))
        list_fix=0.;val_fix=0.
        read(punit,*)list_fix(1:nfixnods)
        read(punit,*)val_fix(1:nfixnods)
        pset=pset+1
        !define node set
        write(adnunit,'(a,i3,a)')"NODESET NAME=",pset," ALL-EXT=NO DESCRIPT='NONE' OPTION=NODE GROUP=0 ZONE='',ELSET=0 TARGET=0"
        write(adnunit,'(a)')'@CLEAR'
        do ifixnods=1,nfixnods
            write(adnunit,'(i8,2i3)')list_fix(ifixnods),0,1
        end do
        write(adnunit,'(a)')'@'
        deallocate(list_fix,val_fix)
    end do

    if(ndimn==3)then
        write(adnunit,'(a)')'FIXITY NAME=XD'
        write(adnunit,'(a)')'@CLEAR'
        write(adnunit,'(a)')" 'X-TRANSLATION' 'OVALIZATION'"
        write(adnunit,'(a)')'@'
    endif
    write(adnunit,'(a)')'FIXITY NAME=YD'
    write(adnunit,'(a)')'@CLEAR'
    write(adnunit,'(a)')" 'Y-TRANSLATION' 'OVALIZATION'"
    write(adnunit,'(a)')'@'
    write(adnunit,'(a)')'FIXITY NAME=ZD'
    write(adnunit,'(a)')'@CLEAR'
    write(adnunit,'(a)')" 'Z-TRANSLATION' 'OVALIZATION'"
    write(adnunit,'(a)')'@'


    write(adnunit,'(a)')'*'
    write(adnunit,'(a)')'FIXBOUNDARY NODE-SET FIXITY=ALL'
    write(adnunit,'(a)')'@CLEAR'
    do iset=nset+1,pset
        if(ndimn==2)then
            if(fix_xyz(iset-nset)==1)write(adnunit,'(i8,a)')iset,"  'YD'"
            if(fix_xyz(iset-nset)==2)write(adnunit,'(i8,a)')iset,"  'ZD'"
        else
            if(fix_xyz(iset-nset)==1)write(adnunit,'(i8,a)')iset,"  'XD'"
            if(fix_xyz(iset-nset)==2)write(adnunit,'(i8,a)')iset,"  'YD'"
            if(fix_xyz(iset-nset)==3)write(adnunit,'(i8,a)')iset,"  'ZD'"
        endif
    end do
    write(adnunit,'(a)')'@'

    !write load step
    do iincs=1,nincs
        read(mainunit,*)iset,deltatime,iset,iset,nstep
        read(mainunit,*) !text
        if(type_problem=='F')read(mainunit,*) !text
        write(adnunit,'(a)')'*'
        write(adnunit,'(a)')'TIMESTEP NAME=DEFAULT'
        write(adnunit,'(a)')'@CLEAR'
        write(adnunit,'(i5,e16.6)')nstep,deltatime
        write(adnunit,'(a)')'@'
    end do
1000 format(a,i5,e15.6)
1001 format(i8,3e15.6)
1002 format(a,i5,a)
1003 format(a,10(',',i8))
    close(adnunit)
    end subroutine GHM2ADINA

    END PROGRAM FEM90
    !subroutine measure_computation (M, N, X, F)  !20190810
    !   IMPLICIT NONE
    !   INTEGER M, N
    !   DOUBLE PRECISION X (*), F (*)
    !
    !end subroutine measure_computation !20190810