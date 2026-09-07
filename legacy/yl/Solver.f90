    MODULE SOLVER


    use yl_diag
    use yl_diag_registry
    use variable_types
    USE GLOBAL_VAR
    USE PRESCRIBED
    use applied_load

    IMPLICIT none
    integer(ink) neq,snonzero,mitcg,itolcg,miter_ssorpbcg,iafile,icond,ipdchk,ising !ssorpbcg
    real   (irk) torler_ssorpbcg,omig_ssorpbcg !ssorpbcg
    integer(ink), allocatable::iseq(:),totveq(:),pcg_iseq(:)
    real(irk),  allocatable::global_stiff1(:),global_stiff2(:),rvector(:),result(:), &
        pcg_stiff1(:)
    complex(irk),allocatable::global_stiff1w(:),global_stiff2w(:),rvectorw(:),resultw(:) !freq2006
    real(irk)  tolcg
    logical pardiso_symbolic_done
    integer(ink) pardiso_analyzed_neq
    integer(ink) iparm(64),maxfct, mnum, mtype, phase_pardiso,msglvl,error,idum   !PARDISO  2008-11-05
    integer(ink) iparm_ctt(64),maxfct_ctt,mnum_ctt,mtype_ctt,phase_pardiso_ctt,msglvl_ctt,error_ctt,idum_ctt
    real   (irk) ddum
    integer(ink), allocatable::iseq_bt(:),totveq_bt(:),iffix_bt(:) !ctt2005
    real(irk),  allocatable::global_stiff_bt(:),global_stiff2_bt(:),rvector_bt(:),result_bt(:) !ctt2005

    character (32) operation
    type nonzero_stiff_store_pcg
        integer(ink)nciseq
        integer(ink),pointer::list(:)
        real   (irk),pointer::nonzero(:)
    end type nonzero_stiff_store_pcg

    type band_of_ssorbcg
        integer(ink) nband,icaloctd
        integer(ink),pointer::mband(:)
    end type band_of_ssorbcg

    type (nonzero_stiff_store_pcg),allocatable::pcg_stiff(:)
    type (band_of_ssorbcg),allocatable::bandinf(:)
    type (band_of_ssorbcg),allocatable::bandinf_bt(:)


    CONTAINS

    SUBROUTINE SOLVE


    Select Case (Type_solver)
    Case ('JPCG')
        Call JPCG
    Case ('PROFILE')
        Call PROFILE
    Case ('PROFILEW')
        Call PROFILEW
    Case ('PARDISO')   !2008-11-05
        Call MAIN_PARDISO
    Case ('PBCG')
        Call PBCG
    Case ('SSORPBCG') !ssorpbcg
        Call SSORPBCG

    Case('EXPLICIT')

        Case Default
        Write(chkunit,*) ' Stopped at routine Solve '
        Write(chkunit,*) ' This type of solver is not implemented'
    End Select

    END SUBROUTINE


    subroutine nonzero_stiff_pcg
    integer(ink) index,nevab,ielem,ieq,jeq,ievab,jevab,ielgroup
    integer(ink) ic,nciseq,snonzero

    integer(ink) igroup
    integer(ink),allocatable::ldofs(:)
    integer(ink),pointer::listx(:),listy(:)



    if(allocated(pcg_stiff))deallocate(pcg_stiff)
    allocate(pcg_stiff(ntotv))
    pcg_stiff(:)%nciseq=0

    DO igroup = 1,ngroup                              !6

        if(appear(igroup)>0)    then                    !5

            index = group(igroup)%index
            ielem = group(igroup)%list(1)
            index=element(ielem)%index
            nevab = size(element(ielem)%field(1)%ldofs_f)
            allocate(ldofs(nevab))
            DO ielgroup = 1, group(igroup)%nelgroup    !4
                ielem = group(igroup)%list(ielgroup)
                ldofs=element(ielem)%field(1)%ldofs_f
                do ievab=1,nevab                          !3
                    ieq=ldofs(ievab)
                    nciseq=pcg_stiff(ieq)%nciseq
                    do jevab=1,nevab            ! 1
                        jeq=ldofs(jevab)

                        if(jeq/=ieq) then

                            ic=0
                            if(nciseq/=0) then
                                allocate(listy(nciseq))
                                listy=pcg_stiff(ieq)%list
                                if(any(listy==jeq))ic=1
                                deallocate(listy)
                            endif
                            !!!update the structure store_seq(ieq)
                            if(ic==0) then                              !!!!!!!!!!!!!!!!!!!!!!!!
                                nciseq=nciseq+1                                                     !
                                allocate(listx(nciseq))                                             !
                                if(nciseq.gt.1)listx(1:nciseq-1)=pcg_stiff(ieq)%list(1:nciseq-1)     !
                                listx(nciseq)=jeq                                                 !
                                if(nciseq.gt.1)deallocate(pcg_stiff(ieq)%list)                     !
                                allocate(pcg_stiff(ieq)%list(nciseq))                     !
                                pcg_stiff(ieq)%list=listx
                                pcg_stiff(ieq)%nciseq=nciseq                                 !
                                deallocate(listx)                                         !
                            endif                                      !!!!!!!!!!!!!!!!!!!!!!!!
                        endif
                    end do                         !1
                end do                                 !3
            end DO        !!ielgroup               !4
            deallocate(ldofs)
        end if            !!do while                      !5
    end do           !!igroup                      !6

    do ieq=1,ntotv
        nciseq=pcg_stiff(ieq)%nciseq
        allocate(pcg_stiff(ieq)%nonzero(nciseq+1))
    end do
    !       write(chkunit,*)'nciseq=',store_seq(1:neq)%nciseq
    !       do ieq=1,neq
    !       write(chkunit,*)'nciseq=',store_seq(ieq)%nciseq
    !       write(chkunit,*)'list  =',store_seq(ieq)%list
    !       end do


    snonzero=sum(pcg_stiff(1:neq)%nciseq)
    snonzero=snonzero+neq

    write(chkunit,*)'snonzero (JPCG) =',snonzero

    end subroutine nonzero_stiff_pcg


    SUBROUTINE JPCG   ! -----------------------------------

    !      ------  Declaration of variables
    character (32) text
    integer iitcg
    !      real(irk) rcg(:)   !rcg: RHS increment computed in the calling program
    !     it will no change. It is transfered into fcg
    !     in the iterative process
    !           --> rvector
    !      real(irk) asdis(:) !asdis: displacement+pressure increment, it is the result.
    !           --> result
    real(irk), allocatable   :: q1cg(:), apcg(:), pcg(:), fcg(:), scg(:)
    real(irk)                :: prod1, alfa, beta, rnorm0, rnorm1, ratio
    integer(ink)             :: index, nevab, ievab, ielgroup, ielem, igroup
    integer(ink)             :: ilink, order_freedom, first_node, second_node, &
        itotv, jtotv, npairs, ipair, jblks
    integer(ink),pointer     :: link_freedom(:),pairnode(:,:)
    integer(ink),allocatable :: ldofs(:)
    real   (irk),allocatable :: estif(:,:), vtemp1(:), vtemp2(:)
    save                     :: rnorm0


    !      -----  Select the operation :

    Select Case ( Operation)
    Case ('SET')
        if(restart==1)   then
            do jblks=1,iblks-1
                read(solveunit,*)text
                read(solveunit,*)text
            end do
        end if
        Read (solveunit,*) text
        Read (solveunit,*) mitcg, tolcg
        if(iblks==1.or.restart==1) then
            Allocate ( rvector(ntotv),result(ntotv) )
        else
            deAllocate ( rvector,result )
            Allocate ( rvector(ntotv),result(ntotv) )
        endif
        if(outintr/=0)then
            do ielem=1,nelem
                index=element(ielem)%index
                nevab=size(element(ielem)%ldofs)
                if(iblks==1.or.restart==1) then
                    allocate(element(ielem)%estif(nevab,nevab))
                else
                    deallocate(element(ielem)%estif)
                    allocate(element(ielem)%estif(nevab,nevab))
                endif
                element(ielem)%estif=0.0
            end do
        endif
        Return

    Case ('SOLVE')

        Allocate ( q1cg(ntotv), apcg(ntotv), fcg(ntotv),   &
            pcg(ntotv), scg (ntotv))
        !      ------  Initializes array

        result = 0.0_irk

        q1cg  = 0.0_irk
        apcg  = 0.0_irk
        pcg   = 0.0_irk
        fcg   = 0.0_irk

        !      ------  Obtains Q = diag (K)-1  and rvector


        DO igroup =1,ngroup
            if(appear(igroup)>0)then
                index = group(igroup)%index
                ielem = group(igroup)%list(1)
                if(outintr/=0)then
                    nevab = size(element(ielem)%field(1)%ldofs_f)
                else
                    nevab = size(element(ielem)%ldofs)
                endif
                allocate ( estif(nevab,nevab), ldofs(nevab) )
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(outintr/=0)then
                        ldofs=element(ielem)%field(1)%ldofs_f
                        estif=element(ielem)%field(1)%khandmc(1)%fstif
                    else
                        ldofs = element(ielem)%ldofs
                        estif = element(ielem)%estif
                    endif
                    DO ievab = 1,nevab
                        q1cg(ldofs(ievab))=q1cg(ldofs(ievab))+estif(ievab,ievab)
                    ENDDO
                ENDDO
                deallocate ( estif, ldofs )
            endif
        ENDDO

        fcg=rvector
        do ilink=1,nlinks
            npairs=links(ilink)%npairs
            pairnode=>links(ilink)%pairnode
            link_freedom=>links(ilink)%link_freedom
            do order_freedom=1,cdofn
                if(link_freedom(order_freedom)==1) then
                    do ipair=1,npairs
                        first_node   =pairnode(1,ipair)
                        second_node  =pairnode(2,ipair)
                        itotv        =nodfn(order_freedom,first_node)
                        jtotv        =nodfn(order_freedom,second_node)
                        q1cg(itotv)  =q1cg(itotv)+q1cg(jtotv)
                        fcg(itotv)   =fcg(itotv)+fcg(jtotv)
                        q1cg(jtotv)  =q1cg(itotv)
                        fcg(jtotv)   =fcg(itotv)
                    end do
                endif
            end do
            nullify(pairnode)
        end do

        do itotv=1,ntotv
            if(abs(q1cg(itotv)).le.1.e-1)q1cg(itotv)=1.e15
        end do


        where(iffix==0)
            q1cg = 1.0/q1cg
        elsewhere
            q1cg=0.0
            fcg= 0.0
        end where


        !      ------  Set rnorm0 to its value at 1st iteration

        IF (iiter==1) THEN
            rnorm0 = maxval( abs(fcg) )
        ENDIF

        DO IITCG = 1,MITCG

            if(iitcg==1) then
                scg=q1cg*fcg
                pcg=scg
            endif

            !      ------  Obtains K.p
            apcg=0.0
            DO igroup = 1,ngroup
                if(appear(igroup)>0)  then

                    index = group(igroup)%index
                    ielem = group(igroup)%list(1)
                    if(outintr/=0)then
                        nevab = size(element(ielem)%field(1)%ldofs_f)
                    else
                        nevab = size(element(ielem)%ldofs)
                    endif
                    allocate ( estif(nevab,nevab), ldofs(nevab) )
                    allocate ( vtemp1(nevab), vtemp2(nevab) )

                    DO ielgroup = 1, group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if(outintr/=0)then
                            ldofs=element(ielem)%field(1)%ldofs_f
                            estif=element(ielem)%field(1)%khandmc(1)%fstif
                        else
                            ldofs = element(ielem)%ldofs
                            estif = element(ielem)%estif
                        endif
                        vtemp1= pcg(ldofs)
                        vtemp2= estif.x.vtemp1
                        apcg (ldofs) = apcg(ldofs) + vtemp2
                    ENDDO
                    deallocate ( estif, ldofs, vtemp1, vtemp2)
                endif
            end do  !!for igroup
            do ilink=1,nlinks
                npairs=links(ilink)%npairs
                pairnode=>links(ilink)%pairnode
                link_freedom=>links(ilink)%link_freedom
                do order_freedom=1,cdofn
                    if(link_freedom(order_freedom)==1) then
                        do ipair=1,npairs
                            first_node   =pairnode(1,ipair)
                            second_node  =pairnode(2,ipair)
                            itotv        =nodfn(order_freedom,first_node)
                            jtotv        =nodfn(order_freedom,second_node)
                            apcg(itotv)  =apcg(itotv)+apcg(jtotv)
                            apcg(jtotv)  =apcg(itotv)
                        end do
                    endif
                end do
                nullify(pairnode)
            end do
            prod1 = dot_product (fcg,scg)
            alfa  = prod1/dot_product(pcg,apcg)
            do itotv=1,ntotv
                if( iffix(itotv) == 0 ) then
                    result(itotv) = result(itotv) + alfa*pcg(itotv)
                    fcg(itotv)   = fcg(itotv) - alfa*apcg(itotv)
                endif
            END do
            scg   = q1cg * fcg
            beta  = dot_product ( fcg,scg ) / prod1
            do itotv=1,ntotv
                if(iffix(itotv) == 0 ) &
                    pcg(itotv)   = scg(itotv) + beta*pcg(itotv)
            END do
            rnorm1= maxval (abs(fcg))
            ratio = rnorm1/rnorm0
            print *,'iitcg=',iitcg,'ratio=',ratio
            write(chkunit,*)'iitcg=',iitcg,'ratio=',ratio
            if (ratio <= tolcg ) goto 1
        ENDDO
1       continue
        deAllocate ( q1cg, apcg, fcg, pcg, scg)
    end select

    END SUBROUTINE JPCG


    subroutine solve_heat_quantity_of_wc  !20210411
    character(80) text       !
    integer(ink) i0,i1,nline_g_w,npairs_wc,inode,ipoin,itotv,ixter,mxter,  &
        jtotv,iintf,nintf,j1,iwc,twater_curve,igroup,matno,place_curve
    integer(ink),pointer::pairnode_wc(:)
    real(irk)   error_s,err_ctl,deltas,tslips,coef,coef_big,coef1,dfact,dtime_change, &
        begin_time,Qwci,temperature
    real(irk) ,pointer::ks(:,:),kc(:,:)
    real(irk),allocatable::tbar(:),idcr(:,:),residu(:),kts_inv(:,:),twp(:), &
        ctfor(:),unitm(:,:),kcs(:,:),dtw(:),Qheat(:)

    coef=theta1*ditime
    coef_big=1.e8

    do i0=1,nwcpipe


        begin_time=wc_pipe(i0)%begin_time
        dtime_change=wc_pipe(i0)%dtime_change
        twater_curve=wc_pipe(i0)%twater_curve
        iwc=(ttime-begin_time)/dtime_change
        if(iwc/2*2/=iwc)iwc=-1
        if(iwc==0)iwc=wc_pipe(i0)%iwc
        wc_pipe(i0)%iwc=iwc
        !write(7,*)'iwc=',iwc
        coef1=iwc

        dfact   =tcurves(twater_curve)%dfact

        nline_g_w=wc_pipe(i0)%nline_g_w

        do i1=1,nline_g_w
            npairs_wc=wc_pipe(i0)%line_g_w(i1)%npairs_wc
            pairnode_wc=>wc_pipe(i0)%line_g_w(i1)%pairnode_wc

            allocate(tbar(npairs_wc),idcr(npairs_wc,npairs_wc),kcs(npairs_wc,npairs_wc),  &
                dtw(npairs_wc))
            tbar=0.
            do inode=1,npairs_wc
                ipoin=pairnode_wc(inode)

                jtotv=nodfn(lmdofn(10),ipoin)
                nintf=trans(jtotv)%nintf
                if(nintf/=0) then
                    do iintf=1,nintf
                        itotv=trans(jtotv)%listf(iintf)
                        tbar(inode)=tbar(inode)+result(itotv)*trans(jtotv)%rintf(iintf)
                    end do
                else
                    tbar(inode)=result(jtotv)
                endif
            end do

            !!!!!!组装矩阵 idcr 并求其逆矩阵kts_inv
            Ks=>wc_pipe(i0)%line_g_w(i1)%kmatrix_w
            Kc=>wc_pipe(i0)%line_g_w(i1)%cmatrix_c
            Kcs=coef1*(Kc.x.Ks)
            idcr=kcs*coef
            do ipoin=1,npairs_wc
                idcr(ipoin,ipoin)=idcr(ipoin,ipoin)+1.
            end do

            allocate(unitm(npairs_wc,npairs_wc),residu(npairs_wc),kts_inv(npairs_wc,npairs_wc))
            allocate(Qheat(npairs_wc))
            if(iwc==1)then
                idcr(1,1)=coef_big
            elseif(iwc==-1)then
                idcr(npairs_wc,npairs_wc)=coef_big
            endif

            unitm=0.
            kts_inv=0.
            do ipoin=1,npairs_wc
                unitm(ipoin,ipoin)=1.
            end do
            call householder(idcr,unitm,kts_inv) !3


            residu=tbar

            if(iwc==1)residu(1)=0.
            if(iwc==-1)residu(npairs_wc)=0.

            dtw=(kts_inv.x.residu)

            Twp=coef*dtw
            Qheat=-coef1*(ks.x.Twp)
            wc_pipe(i0)%line_g_w(i1)%Qwc=Qheat
            deallocate(unitm,tbar,idcr,residu,kcs,kts_inv,twp,dtw,Qheat)
            nullify(pairnode_wc,ks,kc)
        enddo !i1
    end do !i0

10  format(10e15.5)
20  format(10i10)
    !!!
    allocate(ctfor(ntotv))
    ctfor=0.

    do i0=1,nwcpipe
        nline_g_w=wc_pipe(i0)%nline_g_w

        do i1=1,nline_g_w
            npairs_wc=wc_pipe(i0)%line_g_w(i1)%npairs_wc
            pairnode_wc=>wc_pipe(i0)%line_g_w(i1)%pairnode_wc

            do inode=1,npairs_wc
                ipoin=pairnode_wc(inode)
                Qwci=wc_pipe(i0)%line_g_w(i1)%Qwc(inode)
                jtotv=nodfn(lmdofn(10),ipoin)
                nintf=trans(jtotv)%nintf
                if(nintf/=0) then
                    do iintf=1,nintf
                        itotv=trans(jtotv)%listf(iintf)
                        ctfor(itotv)=ctfor(itotv)+Qwci*trans(jtotv)%rintf(iintf)
                    end do
                else
                    ctfor(jtotv)=ctfor(jtotv)+Qwci
                endif
            end do  !inode
            nullify(pairnode_wc)
        end do !i1
    end do !i0


    do itotv=1,ntotv
        if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)
    end do

    operation='SOLVE'
    call solve


    deallocate(ctfor)
    end subroutine solve_heat_quantity_of_wc !20210411

    subroutine solve_bond_force_of_cs  !20210328
    character(80) text       !
    integer(ink) i0,i1,nline_g_sc,ikindsc,npairs_sc,inode,ipoin,idimn,itotv,ixter,mxter,  &
        jdimn,jtotv,iintf,nintf,j1
    integer(ink),pointer::pairnode_sc(:)
    real(irk)   error_s,err_ctl,deltas,tslips,diameter_s,ft,ks,tao,dtao_sc,ds(2),dn(2),k2(2,2)
    real(irk) ,pointer::rot_sc(:,:),aera_sc(:),kmatrix_s(:,:),unitm(:,:),  &
        ikscr(:,:),tao_cs(:),slip_sc(:),kmatrix_cs(:,:),cmatrix_c(:,:), &
        tao0_cs(:),slip0_sc(:)
    real(irk),allocatable::ubar(:),kts(:,:),residu(:),kts_inv(:,:),dslip_sc(:),value(:), &
        uconcrete(:),ctfor(:),usteel(:)
    integer(ink),allocatable::icstate(:)

    do i0=1,nrcsteel

        nline_g_sc=rc_steel(i0)%nline_g_sc
        ikindsc=rc_steel(i0)%ikindsc

        do i1=1,nline_g_sc
            npairs_sc=rc_steel(i0)%line_g_sc(i1)%npairs_sc
            allocate(icstate(npairs_sc))
            diameter_s=rc_steel(i0)%diameter_s
            err_ctl=rc_steel(i0)%err_ctl
            mxter=rc_steel(i0)%mxter
            ft=rc_steel(i0)%ft
            pairnode_sc=>rc_steel(i0)%line_g_sc(i1)%pairnode_sc
            rot_sc=>rc_steel(i0)%line_g_sc(i1)%rot_sc
            aera_sc=>rc_steel(i0)%line_g_sc(i1)%aera_sc

            allocate(value(ndimn),ubar(npairs_sc))
            do inode=1,npairs_sc
                ipoin=pairnode_sc(inode)
                value=0.
                do jdimn=1,ndimn
                    jtotv=nodfn(jdimn,ipoin)
                    nintf=trans(jtotv)%nintf
                    if(nintf/=0) then
                        do iintf=1,nintf
                            itotv=trans(jtotv)%listf(iintf)
                            value(jdimn)=value(jdimn)+result(itotv)*trans(jtotv)%rintf(iintf)
                        end do
                    else
                        value(jdimn)=result(jtotv)
                    endif
                end do !jdimn
                ubar(inode)=dot_product(rot_sc(:,inode),value)
            end do
            deallocate(value)

            !write(7,*)'ubar='
            !write(7,10)ubar

            kmatrix_s=>rc_steel(i0)%line_g_sc(i1)%kmatrix_s
            cmatrix_c=>rc_steel(i0)%line_g_sc(i1)%cmatrix_c
            ikscr=>rc_steel(i0)%line_g_sc(i1)%ikscr

            !tao_cs=>rc_steel(i0)%line_g_sc(i1)%tao_cs
            slip_sc=>rc_steel(i0)%line_g_sc(i1)%slip_sc
            do ipoin=1,npairs_sc
                call cs_relation(slip_sc(ipoin),ks,tao,ft,diameter_s,icstate(ipoin))
                rc_steel(i0)%line_g_sc(i1)%kmatrix_cs(ipoin,ipoin)=ks*aera_sc(ipoin)
                rc_steel(i0)%line_g_sc(i1)%tao_cs(ipoin)=sign(tao*aera_sc(ipoin),slip_sc(ipoin))
            end do

            !write(7,*)'kmatrix_cs='
            !do ipoin=1,npairs_sc
            !write(7,10)rc_steel(i0)%line_g_sc(i1)%kmatrix_cs(ipoin,:)
            !end do

            nullify(slip_sc)

            allocate(unitm(npairs_sc,npairs_sc),kts(npairs_sc,npairs_sc),residu(npairs_sc),  &
                kts_inv(npairs_sc,npairs_sc),dslip_sc(npairs_sc))

            tao0_cs=>rc_steel(i0)%line_g_sc(i1)%tao0_cs
            slip0_sc=>rc_steel(i0)%line_g_sc(i1)%slip0_sc
            do ixter=1,mxter
                write(7,*)'ixter=',ixter
                kmatrix_cs=>rc_steel(i0)%line_g_sc(i1)%kmatrix_cs
                kts=(kmatrix_s-(ikscr.x.kmatrix_cs))
                !      write(7,*)'kts='
                !do ipoin=1,npairs_sc
                !write(7,10)kts(ipoin,:)
                !end do

                tao_cs=>rc_steel(i0)%line_g_sc(i1)%tao_cs
                slip_sc=>rc_steel(i0)%line_g_sc(i1)%slip_sc

                !       write(7,*)'ikscr='
                ! do ipoin=1,npairs_sc
                ! write(7,10)ikscr(ipoin,:)
                ! end do
                !  write(7,*)'tao_cs='
                !write(7,10)rc_steel(i0)%line_g_sc(i1)%tao_cs

                residu=ikscr.x.(tao_cs-tao0_cs)
                !      write(7,*)'residu1='
                !write(7,10)residu
                residu=residu-(kmatrix_s.x.ubar)
                !      write(7,*)'residu2='
                !write(7,10)residu
                residu=residu-(kmatrix_s.x.(slip_sc-slip0_sc))
                !write(7,*)'residu3='
                !write(7,10)residu

                unitm=0.
                kts_inv=0.
                do ipoin=1,npairs_sc
                    unitm(ipoin,ipoin)=1.
                end do
                call householder(kts,unitm,kts_inv) !3
                !write(7,*)'kts_inv='
                !do ipoin=1,npairs_sc
                !write(7,10)kts_inv(ipoin,:)
                !end do

                dslip_sc=kts_inv.x.residu
                !   write(7,*)'dslip_sc='
                !write(7,10)dslip_sc
                !
                !write(7,*)'residu1a='
                !residu=(kmatrix_s.x.dslip_sc)
                !write(7,10)residu
                !write(7,*)'tau_cs='
                !write(7,10)(kmatrix_cs.x.dslip_sc)
                !
                !write(7,*)'residu1b='
                !residu=-((ikscr.x.kmatrix_cs).x.dslip_sc)
                !write(7,10)residu
                !write(7,*)'residu1c='
                !residu=(kts.x.dslip_sc)
                !write(7,10)residu

                !write(7,*)'slipb_sc='
                !write(7,10)rc_steel(i0)%line_g_sc(i1)%slip_sc
                rc_steel(i0)%line_g_sc(i1)%slip_sc=rc_steel(i0)%line_g_sc(i1)%slip_sc+dslip_sc

                slip_sc=>rc_steel(i0)%line_g_sc(i1)%slip_sc
                !write(7,*)'slipa_sc='
                !write(7,10)slip_sc
                do ipoin=1,npairs_sc
                    call cs_relation(slip_sc(ipoin),ks,tao,ft,diameter_s,icstate(ipoin))
                    rc_steel(i0)%line_g_sc(i1)%kmatrix_cs(ipoin,ipoin)=ks*aera_sc(ipoin)
                    rc_steel(i0)%line_g_sc(i1)%tao_cs(ipoin)=sign(tao*aera_sc(ipoin),slip_sc(ipoin))
                    rc_steel(i0)%line_g_sc(i1)%shear_stres(ipoin)=sign(tao,slip_sc(ipoin))

                    !if(abs(slip_sc(ipoin))>1.e-10) &
                    !rc_steel(i0)%line_g_sc(i1)%tao_cs(ipoin)=tao*aera_sc(ipoin)*slip_sc(ipoin)/abs(slip_sc(ipoin))
                end do
                !write(7,*)'kmatrix_cs='
                !write(7,10)(rc_steel(i0)%line_g_sc(i1)%kmatrix_cs(ipoin,ipoin),ipoin=1,npairs_sc)
                !write(7,*)'tao_cs='
                !write(7,10)rc_steel(i0)%line_g_sc(i1)%tao_cs


                deltas=sum(dslip_sc**2)
                tslips=sum(slip_sc**2)
                !tslips=sum((slip_sc-slip0_sc)**2)
                error_s=sqrt(deltas/tslips)
                write(7,*)'deltas=',deltas,'tslips=',tslips,'error_s=',error_s,'err_ctl=',err_ctl
                write(7,*)'icstate='
                write(7,20)icstate
                !nullify(tao_cs,tao0_cs)
                if(error_s<err_ctl) goto 11
            end do
11          continue
            tao_cs=>rc_steel(i0)%line_g_sc(i1)%tao_cs
            allocate(uconcrete(npairs_sc),usteel(npairs_sc))
            uconcrete=ubar-(cmatrix_c.x.(tao_cs-tao0_cs))
            usteel=uconcrete+(slip_sc-slip0_sc)
            !  write(7,*)'ubar='
            ! write(7,10)ubar
            !write(7,*)'uconcrete='
            ! write(7,10)uconcrete
            !  write(7,*)'usteel='
            ! write(7,10)usteel

            do j1=1,rc_steel(i0)%line_g_sc(i1)%nline_s  !钢筋单元刚度矩阵
                k2=rc_steel(i0)%line_g_sc(i1)%k2(:,:,j1)
                ds=usteel(rc_steel(i0)%line_g_sc(i1)%ianode_s(:,j1))
                dn=k2.x.ds
                rc_steel(i0)%line_g_sc(i1)%axial_stres(j1)=  &
                    rc_steel(i0)%line_g_sc(i1)%axial_stres(j1)+dn(2)
            end do


            deallocate(unitm,ubar,kts,residu,kts_inv,dslip_sc,uconcrete,usteel,icstate)
            nullify(tao0_cs,slip0_sc)
            nullify(pairnode_sc,rot_sc,aera_sc,kmatrix_s,cmatrix_c,kmatrix_cs,ikscr,tao_cs,slip_sc)
        enddo !i1
    end do !i0

10  format(10e15.5)
20  format(10i10)
    !!!
    allocate(ctfor(ntotv))
    ctfor=0.
    do i0=1,nrcsteel

        nline_g_sc=rc_steel(i0)%nline_g_sc
        ikindsc=rc_steel(i0)%ikindsc

        do i1=1,nline_g_sc
            npairs_sc=rc_steel(i0)%line_g_sc(i1)%npairs_sc
            tao_cs=>rc_steel(i0)%line_g_sc(i1)%tao_cs
            tao0_cs=>rc_steel(i0)%line_g_sc(i1)%tao0_cs
            rot_sc=>rc_steel(i0)%line_g_sc(i1)%rot_sc
            pairnode_sc=>rc_steel(i0)%line_g_sc(i1)%pairnode_sc

            do inode=1,npairs_sc
                ipoin=pairnode_sc(inode)
                dtao_sc=-(tao_cs(inode)-tao0_cs(inode))
                do jdimn=1,ndimn
                    jtotv=nodfn(jdimn,ipoin)
                    nintf=trans(jtotv)%nintf
                    if(nintf/=0) then
                        do iintf=1,nintf
                            itotv=trans(jtotv)%listf(iintf)
                            ctfor(itotv)=ctfor(itotv)+dtao_sc*rot_sc(jdimn,inode)*trans(jtotv)%rintf(iintf)
                        end do
                    else
                        ctfor(jtotv)=ctfor(jtotv)+dtao_sc*rot_sc(jdimn,inode)
                    endif
                end do !jdimn
            end do  !inode
            rc_steel(i0)%line_g_sc(i1)%tao0_cs=rc_steel(i0)%line_g_sc(i1)%tao_cs
            rc_steel(i0)%line_g_sc(i1)%slip0_sc=rc_steel(i0)%line_g_sc(i1)%slip_sc
            nullify(tao_cs,tao0_cs,rot_sc,pairnode_sc)
        end do !i1
    end do !i0


    !rvector=rvector_mid

    do itotv=1,ntotv
        if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)
    end do


    tofor=tofor+ctfor
    operation='SOLVE'
    call solve
    !!1

    deallocate(ctfor)
    end subroutine solve_bond_force_of_cs !20210328


    subroutine cs_relation(sx,ks,tao,ft,d,ic) !20210328
    !适用于有限元片状裂缝模型的钢筋与混凝土粘结滑移关系,水利水电技术，2016，vol.47，No.4
    !肖 遥，汪基伟，冷飞
    integer(ink) ic
    real   (irk) sx,ks,tao,ft,d,a0(3),b0(3),sxabs

    !	sxabs=abs(sx*1000.)
    !Tao=6.59e2*sxabs-2.13e4*sxabs*sxabs+0.22e6*sxabs*sxabs*sxabs
    !   ks=6.59e2-2.13e4*2*sxabs+0.22e6*3*sxabs*sxabs
    !   ks=ks*1000.
    !   ic=1
    !   return
    !
    !

    a0(1)=0.0012;a0(2)=0.0023;a0(3)=0.0061
    b0(1)=2.;b0(2)=3.;b0(3)=1.
    a0=a0*d
    b0=b0*ft

    sxabs=abs(sx)
    ic=0
    if(sxabs<=a0(1))then
        tao=sxabs*b0(1)/a0(1)
        ks=b0(1)/a0(1)
        ic=1
    elseif(sxabs<=a0(2))then
        tao=b0(1)+(sxabs-a0(1))*(b0(2)-b0(1))/(a0(2)-a0(1))
        ks=tao/sxabs  !割线模量
        ic=2
    elseif(sxabs<=a0(3))then
        tao=b0(2)-(sxabs-a0(2))*(b0(2)-b0(3))/(a0(3)-a0(2))
        ks=tao/sxabs  !割线模量
        ic=3
    else
        tao=b0(3)
        ks=tao/sxabs  !割线模量
        ic=4
    endif

    end subroutine cs_relation  !20210328



    !ctt2005


    subroutine getatf(vectx,rhs,ctfor,resi,stfor_rigid)  !tcl
    character(10)fieldid,fieldi
    integer(ink) igapb,igroup,jgroup,index,nnode,rpoin,ielgroup,ielem,inode,ic,idofn,  &
        jpoin,idimn,ipoin,itotv,ieq,onetwo,npblock,nrfields,ifield,nevab_f,type_mass,ordert, &
        npgblock,itotvbt,jtotvbt,jdimn,kdimn
    real   (irk) alfa,vectx(:),rhs(:),ctfor(:),resi(:),stfor_rigid(:)
    real   (irk),allocatable::df(:),dfat(:),mtrxA(:,:),rvect(:),disl(:,:),drdisp(:),stfor_inc(:),ext_force(:),dff(:)

    kdimn=ndimn
    if(block_stab==1)kdimn=(ndimn-1)*3
    allocate(df(kdimn),dfat((ndimn-1)*3),mtrxA(kdimn,(ndimn-1)*3),drdisp((ndimn-1)*3))
    allocate(dff(kdimn),ext_force((ndimn-1)*3))  !20231019

    rvect=0. ; df=0. ; dfat=0. ; mtrxA=0.;ext_force=0.;dff=0.

    if(type_problem=='F')then
        allocate(stfor_inc(ntotv))
        stfor_inc=0.
        call stfor_inc_ctfor(resi,stfor_inc)
        !   else if(type_problem=='Q')then
        !allocate(stfor_inc(ntotv))
        !	stfor_inc=0.
        !call stfor_inc_ctfor_Q(resi,stfor_inc)
    endif
    !write(7,*)'itotv,df,tofor(itotv),stfor(itotv),ctfor(itotv),stfor_inc(itotv),stfor_rigid(itotv)'
    !write(7,*)'itotv,df,tofor(itotv),stfor(itotv),ctfor(itotv)'

    do igapb=1,ngapb
        if(gapb(igapb)%nrdof==0) cycle   !tcl

        allocate(disl(gapb(igapb)%nrdof,gapb(igapb)%nrdof))

        dfat=0.
        if(iiter==1)ext_force=0.
        npblock=gapb(igapb)%npblock
        npgblock=gapb(igapb)%npgblock
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            df=0.
            do idimn=1,kdimn !严格的说，应该用cdofn,ndof
                itotv=nodfn(idimn,ipoin)
                if(itotv/=0)then
                    df(idimn)=tofor(itotv)-stfor(itotv)+ctfor(itotv)
                    if(iiter==1)dff(idimn)=tofor(itotv)  !20231019
                    if(type_problem=='F')df(idimn)=df(idimn)-stfor_rigid(itotv)-stfor_inc(itotv)  !2017/03/29
                    !write(7,*)itotv,df(idimn),tofor(itotv),stfor(itotv),ctfor(itotv)
                endif
            enddo

            mtrxa=0.

            do idimn=1,gapb(igapb)%nrdof
                mtrxa(:,idimn)=gapb(igapb)%npdisp(:,jpoin,idimn)
            end do

            dfat=dfat+matmul(transpose(mtrxA),df)
            if(iiter==1)ext_force=ext_force+matmul(transpose(mtrxA),dff)  !20231019

        enddo !ipoin

        write(7,*)'igapb=',igapb,'dfat=',dfat,'ext_force=',ext_force
        !1011 format(3i10,10e15.5)

        if(iiter==1)gapb(igapb)%ext_force=ext_force  !20231019

        if(type_problem=='F'.and.gapb(igapb)%eblock==0)then	       !20161101
            disl=(1+damp_ctt*theta1*ditime)*gapb(igapb)%rstiff  !20161101
            drdisp=gapb(igapb)%rdisp_second+gapb(igapb)%rdisp_inc !20161101
            dfat=dfat+(disl.x.drdisp)  !!1!20161101
        endif


        write(7,*)'igapb=',igapb,'dfat1=',dfat

        do idimn=1,gapb(igapb)%nrdof !fzx
            itotv=gapb(igapb)%rldofs(idimn)
            if(itotv==0)cycle
            vectx(itotv)=-dfat(idimn)
            !write(7,*)'igapb=',igapb,'itotv=',itotv,'vectx(itotv)=',vectx(itotv)
        enddo


        deallocate(disl)
    enddo !igapb


    deallocate(df,dfat,mtrxA,drdisp,dff,ext_force)
    if(type_problem=='F')deallocate(stfor_inc)

10  format(i10, 6e20.5)
    end subroutine getatf

    !!!!
    subroutine getatf_back_analysis(vectx,rhs,ctfor,resi)   !20150925
    character(10)fieldid,fieldi
    integer(ink) igapb,igroup,jgroup,index,nnode,rpoin,ielgroup,ielem,inode,ic,idofn,  &
        jpoin,idimn,ipoin,itotv,ieq,onetwo,npblock,nrfields,ifield,nevab_f,type_mass,ordert, &
        npgblock,itotvbt,jtotvbt,jdimn,igapbf,kdimn
    real   (irk) alfa,vectx(:),rhs(:),ctfor(:),resi(:)
    real   (irk),allocatable::df(:),dfat(:),mtrxA(:,:),disl(:,:),drdisp(:)
    real   (irk),allocatable::dff(:),ext_force(:)  !20231019


    kdimn=ndimn
    if(block_stab==1)kdimn=(ndimn-1)*3
    allocate(df(kdimn),dfat((ndimn-1)*3),mtrxA(kdimn,(ndimn-1)*3),drdisp((ndimn-1)*3))
    allocate(dff(kdimn),ext_force((ndimn-1)*3))

    df=0. ; dfat=0. ; mtrxA=0.;dff=0.
    !write(7,*)'ipoin,idimn,df,tofor(itotv),stfor_inc(itotv),ctfor(itotv)'

    do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb
        if(gapb(igapb)%nrdof==0) cycle   !tcl

        allocate(disl(gapb(igapb)%nrdof,gapb(igapb)%nrdof))

        !write(7,*)'itotv,tofor(itotv),stfor(itotv),ctfor(itotv),stfor_inc(itotv),stfor_rigid(itotv)'
        dfat=0.
        ext_force=0.

        npblock=gapb(igapb)%npblock
        npgblock=gapb(igapb)%npgblock
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            df=0.
            dff=0.
            do idimn=1,kdimn !严格的说，应该用cdofn,ndof
                itotv=nodfn(idimn,ipoin)
                if(itotv/=0)then
                    df(idimn)=tofor(itotv)-stfor(itotv)+ctfor(itotv)
                    if(iiter==1)dff(idimn)=tofor(itotv)
                endif
            enddo

            mtrxa=0.
            do idimn=1,gapb(igapb)%nrdof
                mtrxa(:,idimn)=gapb(igapb)%npdisp(:,jpoin,idimn)
            end do

            dfat=dfat+matmul(transpose(mtrxA),df)
            if(iiter==1)ext_force=ext_force+matmul(transpose(mtrxA),dff)
        enddo !ipoin

        if(iiter==1)gapb(igapb)%ext_force=ext_force
        disl=(1+damp_ctt*theta1*ditime)*gapb(igapb)%rstiff  !20121216

        drdisp=gapb(igapb)%rdisp_inc
        dfat=dfat+(disl.x.drdisp)  !!1128

        write(7,*)'igapb=',igapb,'dfat=',dfat
        write(7,*)'igapb=',igapb,'ext_force=',ext_force

        do idimn=1,gapb(igapb)%nrdof !fzx
            itotv=gapb(igapb)%rldofs(idimn)
            if(itotv==0)cycle
            vectx(itotv)=-dfat(idimn)
        enddo

        deallocate(disl)
    enddo !igapb

    deallocate(df,dfat,mtrxA,drdisp)

10  format(i10, 6e20.5)
    end subroutine getatf_back_analysis !20150925
    !!!!!

    subroutine getatf_rigid(vectx,ctfor)  !tcl
    character(10)fieldid,fieldi
    integer(ink) igapb,igroup,jgroup,index,nnode,rpoin,ielgroup,ielem,inode,ic,idofn,  &
        jpoin,idimn,ipoin,itotv,ieq,onetwo,npblock,nrfields,ifield,nevab_f,type_mass,ordert, &
        npgblock,itotvbt,jtotvbt,jdimn,kdimn
    real   (irk) alfa,vectx(:),ctfor(:)
    real   (irk),allocatable::df(:),dfat(:),mtrxA(:,:),rvect(:),disl(:,:),drdisp(:),stfor_inc(:)
    real   (irk),allocatable::dff(:),ext_force(:)  !20231019

    kdimn=ndimn
    if(block_stab==1)kdimn=(ndimn-1)*3
    allocate(df(kdimn),dfat((ndimn-1)*3),mtrxA(kdimn,(ndimn-1)*3),drdisp((ndimn-1)*3))
    allocate(dff(kdimn),ext_force((ndimn-1)*3))

    df=0. ; dfat=0. ; mtrxA=0.;dff=0.

    do igapb=1,ngapb
        if(gapb(igapb)%nrdof==0) cycle   !tcl

        allocate(disl(gapb(igapb)%nrdof,gapb(igapb)%nrdof))


        !write(7,*)'itotv,tofor(itotv),stfor(itotv),ctfor(itotv),stfor_inc(itotv),stfor_rigid(itotv)'
        dfat=0.
        ext_force=0.
        npblock=gapb(igapb)%npblock
        npgblock=gapb(igapb)%npgblock
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            df=0.
            dff=0.
            do idimn=1,kdimn !严格的说，应该用cdofn,ndof
                itotv=nodfn(idimn,ipoin)
                if(itotv/=0)then
                    df(idimn)=tofor(itotv)+ctfor(itotv)
                    if(iiter==1)dff(idimn)=tofor(itotv)
                    !write(7,*)'idimn=',idimn,'itotv=',itotv,'tofor=',tofor(itotv),'ctfor=',ctfor(itotv)
                endif
            enddo

            mtrxa=0.
            do idimn=1,gapb(igapb)%nrdof
                mtrxa(:,idimn)=gapb(igapb)%npdisp(:,jpoin,idimn)
            end do

            !write(7,*)'jpoin=',jpoin,'matrix,df='
            !do idimn=1,3*(ndimn-1)
            !write(7,*)mtrxa(idimn,:),df(idimn)
            !end do

            dfat=dfat+matmul(transpose(mtrxA),df)
            if(iiter==1)ext_force=ext_force+matmul(transpose(mtrxA),dff)
        enddo !ipoin

        write(7,*)'igapb=',igapb,'dfat=',dfat
        write(7,*)'igapb=',igapb,'ext_force=',ext_force

        if(iiter==1)gapb(igapb)%ext_force=ext_force
        !write(7,*)'dfat=',dfat

        disl=(1+damp_ctt*theta1*ditime)*gapb(igapb)%rstiff  !20121216

        if(type_problem=='F')then
            drdisp=gapb(igapb)%rdisp_second+gapb(igapb)%rdisp_inc
        else
            drdisp=gapb(igapb)%rdisp_inc
        endif
        dfat=dfat+(disl.x.drdisp)  !!1128

        do idimn=1,gapb(igapb)%nrdof !fzx
            itotv=gapb(igapb)%rldofs(idimn)
            if(itotv==0)cycle
            vectx(itotv)=-dfat(idimn)
        enddo

        deallocate(disl)
    enddo !igapb

    deallocate(df,dfat,mtrxA,drdisp)

10  format(i10, 6e20.5)
    end subroutine getatf_rigid

    !!!!!!
    subroutine getardisp(glbrdisp)  !2015/8

    integer(ink) igapb,idimn,ipoin,jpoin,itotv,npgblock,ipairs,ij,igaps,nnode,inode,kpoin,i1,ii,npairs,i0,ij1,ij2,kdimn,nnodei,nnodej
    real   (irk),allocatable::local_poin(:)
    real   (irk) coef,coef1,glbrdisp(:)
    real   (irk),allocatable::adisp(:),drdisp(:),mtrxA(:,:),dislocal(:),rot(:,:),disb(:,:,:)

    kdimn=ndimn
    if(block_stab==1)kdimn=(ndimn-1)*3
    allocate(adisp(kdimn),drdisp((ndimn-1)*3),mtrxA(kdimn,(ndimn-1)*3))

    !
    !allocate(adisp(ndimn),drdisp((ndimn-1)*3),mtrxA(ndimn,(ndimn-1)*3))
    adisp=0. ; drdisp=0. ; mtrxA=0.

    do igapb=1,ngapb

        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        if(gapb(igapb)%nrdof==0) cycle
        allocate(disb(kdimn,npoin,gapb(igapb)%nrdof))
        disb=0.
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            do ij=1,gapb(igapb)%nrdof
                disb(:,ipoin,ij)=gapb(igapb)%npdisp(:,jpoin,ij)
            end do
        end do

        npgblock=gapb(igapb)%npgblock
        allocate(rot(kdimn,kdimn),dislocal(kdimn))

        drdisp=gapb(igapb)%rdisp_inc

        do jpoin=1,gapb(igapb)%npgblock
            ij=gapb(igapb)%nodegblock_onetwo(jpoin)
            coef=1.
            if(ij==1)coef=-1.
            i1=gapb(igapb)%nppt(jpoin)
            ipairs=gapb(igapb)%nodegblock_ipairs(jpoin)
            igaps=gapb(igapb)%nodegblock_igaps(jpoin)

            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3)then
                    !rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                    !rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                endif
            endif

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



            do i0=ij1,ij2

                !ipoin=gapb(igapb)%nodegblock(jpoin)
                ipoin=gaps(igaps)%pairnode(i0,ipairs)
                mtrxa=0.
                do idimn=1,gapb(igapb)%nrdof
                    mtrxa(:,idimn)=disb(:,ipoin,idimn)
                end do
                adisp=matmul(mtrxA,drdisp)
                dislocal=rot.x.adisp !
                do idimn=1,kdimn
                    itotv=nodfnbt(idimn,i1)
                    glbrdisp(itotv)=glbrdisp(itotv)+coef*coef1*dislocal(idimn)
                    !write(7,*)'itotv=',itotv,'glbrdisp=',glbrdisp(itotv)
                enddo

            end do !i0
        enddo !jpoin

        deallocate(rot,dislocal)
        deallocate(disb)
    enddo !igapb



    deallocate(adisp,drdisp,mtrxA)

    end subroutine getardisp
    !!!!!!
    subroutine getardisp_back_analysis(glbrdisp)  !20150925

    integer(ink) igapb,idimn,ipoin,jpoin,itotv,npgblock,ipairs,ij,igaps,nnode,inode,kpoin,i1,ii,npairs,i0,igapbf,jdimn,kdimn,jpoin0
    real   (irk) adisp,glbrdisp(:)
    real   (irk),allocatable::drdisp(:),mtrxA(:),disb(:,:,:),glbreact(:)

    kdimn=ndimn
    if(block_stab==1)kdimn=(ndimn-1)*3
    allocate(drdisp((ndimn-1)*3),mtrxA((ndimn-1)*3))
    adisp=0. ; drdisp=0. ; mtrxA=0.

    do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb
        npgblock=gapb(igapb)%npgblock

        if(gapb(igapb)%nrdof==0) cycle
        allocate(disb(kdimn,npoin,gapb(igapb)%nrdof))
        disb=0.
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            do ij=1,gapb(igapb)%nrdof
                disb(:,ipoin,ij)=gapb(igapb)%npdisp(:,jpoin,ij)
            end do
        end do

        drdisp=gapb(igapb)%rdisp_inc

        if(backf(igapbf)%mdism==npgblock*kdimn)then
            do kpoin=1,backf(igapbf)%mdism
                jdimn=backf(igapbf)%listdim(kpoin)
                mtrxa=0.
                do idimn=1,gapb(igapb)%nrdof
                    do i0=1,backf(igapbf)%relat(kpoin)%nintf
                        jpoin=backf(igapbf)%relat(kpoin)%listp(i0)
                        mtrxa(idimn)=mtrxa(idimn)+disb(jdimn,jpoin,idimn)*backf(igapbf)%relat(kpoin)%rintf(i0)
                    end do
                end do
                adisp=dot_product(mtrxA,drdisp)
                glbrdisp(kpoin)=glbrdisp(kpoin)-adisp

            end do !i0
        elseif(backf(igapbf)%mdism>npgblock*kdimn)then
            allocate(glbreact(backf(igapbf)%mdism))
            glbreact=0.
            do kpoin=1,backf(igapbf)%mdism
                jdimn=backf(igapbf)%listdim(kpoin)
                mtrxa=0.
                do idimn=1,gapb(igapb)%nrdof
                    do i0=1,backf(igapbf)%relat(kpoin)%nintf
                        jpoin=backf(igapbf)%relat(kpoin)%listp(i0)
                        mtrxa(idimn)=mtrxa(idimn)+disb(jdimn,jpoin,idimn)*backf(igapbf)%relat(kpoin)%rintf(i0)
                    end do
                end do
                adisp=dot_product(mtrxA,drdisp)
                glbreact(kpoin)=glbreact(kpoin)-adisp
            end do !kpoin

            glbrdisp(1:npgblock*kdimn)=glbrdisp(1:npgblock*kdimn)+(transpose(gapb(igapb)%uireact).x.glbreact)
            deallocate(glbreact)
        endif



        deallocate(disb)
    enddo !igapb

    deallocate(drdisp,mtrxA)

    end subroutine getardisp_back_analysis !20150925

    !!!!!

    subroutine getardisp_rigid(glbrdisp)

    integer(ink) igapb,idimn,ipoin,jpoin,itotv,npgblock,ipairs,ij,igaps,nnode,inode,kpoin,i1,ii,npairs,i0,ij1,ij2,kdimn,nnodei,nnodej
    real   (irk),allocatable::local_poin(:)
    real   (irk) coef,coef1,glbrdisp(:)
    real   (irk),allocatable::adisp(:),drdisp(:),mtrxA(:,:),dislocal(:),rot(:,:),disb(:,:,:)

    kdimn=ndimn
    if(block_stab==1)kdimn=(ndimn-1)*3
    allocate(adisp(kdimn),drdisp((ndimn-1)*3),mtrxA(kdimn,(ndimn-1)*3))

    adisp=0. ; drdisp=0. ; mtrxA=0.

    do igapb=1,ngapb

        if(gapb(igapb)%nrdof==0) cycle
        allocate(disb(kdimn,npoin,gapb(igapb)%nrdof))
        disb=0.
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            do ij=1,gapb(igapb)%nrdof
                disb(:,ipoin,ij)=gapb(igapb)%npdisp(:,jpoin,ij)
            end do
        end do

        npgblock=gapb(igapb)%npgblock
        allocate(rot(kdimn,kdimn),dislocal(kdimn))

        drdisp=gapb(igapb)%rdisp_inc
        !write(7,*)'igapb=',igapb,'drdisp=',drdisp
        !
        do jpoin=1,gapb(igapb)%npgblock
            ij=gapb(igapb)%nodegblock_onetwo(jpoin)
            coef=1.
            if(ij==1)coef=-1.
            i1=gapb(igapb)%nppt(jpoin)
            ipairs=gapb(igapb)%nodegblock_ipairs(jpoin)
            igaps=gapb(igapb)%nodegblock_igaps(jpoin)
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3)then
                    !rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                    !rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                endif
            endif

            !       ipoin=gapb(igapb)%nodegblock(jpoin)
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

            do i0=ij1,ij2
                ipoin=gaps(igaps)%pairnode(i0,ipairs)

                mtrxa=0.
                do idimn=1,gapb(igapb)%nrdof
                    mtrxa(:,idimn)=disb(:,ipoin,idimn)
                end do
                adisp=matmul(mtrxA,drdisp)
                !write(7,*)'adisp=',adisp
                dislocal=rot.x.adisp !
                do idimn=1,kdimn
                    itotv=nodfnbt(idimn,i1)
                    glbrdisp(itotv)=glbrdisp(itotv)+coef*coef1*dislocal(idimn)
                    !write(7,*)'itotv=',itotv,'glbrdisp=',glbrdisp(itotv),'coef=',coef,'dislocal=',dislocal
                enddo
            end do !i0
        enddo !jpoin

        deallocate(rot,dislocal)
        deallocate(disb)
    enddo !igapb
    deallocate(adisp,drdisp,mtrxA)

    end subroutine getardisp_rigid

    !!!!!!20150925
    SUBROUTINE solve_ctt_back_analysis !20150925

    integer(ink) nevab,ieq,jeq,dijeq,ievab,jevab,igapb,igaps,inode,ipoin1,ipoin2,jpoin1, &
        jpoin2,iieq,ij,npgblock,kpoin,max_band,stiff_length,i1,i2,ntotv_bt,     &
        iter_bt,idimn,jconv,itotv,jtotv,ipoin,jpoin,ipairs,npairs,iconv,jter_bt,&
        nintf,njntf,iintf,jintf,colum,rpoin,onetwo,jdimn,nnode,ii,i0,i12,       &
        jgapb,j0,jpairs,jgaps,ij1,ij2,iix,k1,iter_state,kdimn,igapbf,kkdimn,itotv0,jpoin0
    real   (irk) ylost,dista,sigman,ft,t1,t2,tt,alfa1,alfa2,sheart,dnorm,tnorm,facti,xi0,&
        sigmanc,gf,et,sig1,wx,w1,w0,coef,fact,coef1,xij,dispoint0,dispoint1
    real   (irk),allocatable ::resultm(:),eldis(:),recover_bt(:),rvector_mid(:),rot(:,:), &
        ctfor(:),ctfori1(:),ctfori2(:),ctforl1(:),ctforl2(:),      &
        resultx(:),rdisp(:),disl(:),dispre(:),stfor_rigid(:),result0(:),resback(:)
    integer(ink),pointer::listf(:),ldofs(:),lnods(:) !fzx
    real   (irk),pointer::rintf(:),dislocal(:),cmatrix(:,:)

    print *,'in ctt'
    write(7,*)'nonsbt=',nonsbt,'xlwsol=',xlwsol

    kkdimn=ndimn  !2015/11/17
    if(block_stab==1)kkdimn=3*(ndimn-1) !2015/11/17
    allocate(dispre(ntotv))
    dispre=0.
    allocate(stfor_rigid(ntotv))
    stfor_rigid=0.
    allocate(rdisp((ndimn-1)*3))
    allocate(rvector_mid(neq),resultx(ntotvbt),ctfor(ntotv))

    iter_state=1
    if(miter_state>1)then
        allocate(result0(ntotv))
        result0=result
    endif
    rvector_mid=rvector



10  do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb
        if(gapb(igapb)%nrdof==0)cycle
        gapb(igapb)%rdisp_inc=0.
    enddo

    ctfor=0.
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    resultx=0.

    do igapbf=1,nbackf

        igapb=backf(igapbf)%groupb
        npgblock=gapb(igapb)%npgblock

        if(backf(igapbf)%mdism==npgblock*kkdimn)then
            do kpoin=1,backf(igapbf)%mdism
                if(backf(igapbf)%ic(kpoin)==0) cycle !20230523
                jdimn=backf(igapbf)%listdim(kpoin)
                dispoint1=0.    !20230523
                nintf=backf(igapbf)%relat(kpoin)%nintf
                do iintf=1,nintf
                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                    dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                end do


                resultx(kpoin)=backf(igapbf)%dism(kpoin,trstep)-dispoint1 !20220101
                !resultx(kpoin)=backf(igapbf)%dism(kpoin)-result_zero(itotv)-result(itotv)
                !if(jpoin0/=0)resultx(kpoin)=resultx(kpoin)+result_zero(itotv0)+result(itotv0)
            end do
        else if(backf(igapbf)%mdism>npgblock*kkdimn)then
            allocate(resback(backf(igapbf)%mdism))
            resback=0.  !20210726
            do kpoin=1,backf(igapbf)%mdism
                if(backf(igapbf)%ic(kpoin)==0) cycle !20210726
                jdimn=backf(igapbf)%listdim(kpoin)
                dispoint1=0.    !20230523
                nintf=backf(igapbf)%relat(kpoin)%nintf
                do iintf=1,nintf
                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                    dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                end do

                resback(kpoin)=backf(igapbf)%dism(kpoin,trstep)-dispoint1 !20220101

                !            if(jpoin0/=0) itotv0=nodfn(jdimn,jpoin0)
                !resback(kpoin)=backf(igapbf)%dism(kpoin)-result_zero(itotv)-result(itotv)
                !        if(jpoin0/=0)resback(kpoin)=resback(kpoin)+result_zero(itotv0)+result(itotv0)
            end do

            !do ii=1,npgblock*kkdimn
            !   xij=0.
            !   do kpoin=1,backf(igapbf)%mdism
            !   xij=xij+resback(kpoin)*gapb(igapb)%uireact(kpoin,ii)
            !   end do
            !   resultx(ii)=xij
            !  end do

            resultx(1:npgblock*kkdimn)=(transpose(gapb(igapb)%uireact).x.resback)
            deallocate(resback)

        endif
    end do

1   format(2i5,3f15.5)
2   format(4i5,3f15.5)
50  format(i5,3f15.8)
51  format(3i5,3f15.8)

    call getardisp_back_analysis(resultx) !迭代过程中，将刚体位移增量引起的接触面位移增量累加到resultx中
    call getatf_back_analysis(resultx,rvector,ctfor,result) !接触力变化引起刚体运动平衡方程右端项变化

    if(istep==inc_step.and.iiter==1)then
        operation='SET'
        call profile_ctt_back_analysis
        if(neq_bt==0) goto 20

        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            ntotv_bt=gapb(igapb)%ntotv_bt


            call global_stif_profile_ctt(ntotv_bt,gapb(igapb)%ldofs,gapb(igapb)%cmatrix)
        end do
        !
        !    write(7,*)'istep=',istep,'iiter=',iiter,'global_stiff_bt01='
        !do itotv=1, neq_bt
        !    if(itotv==1)then
        !    write(7,*)itotv,global_stiff_bt(iseq_bt(itotv))
        !    write(7,*)itotv,global_stiff2_bt(iseq_bt(itotv))
        !    else
        !        write(7,*)itotv,global_stiff_bt(iseq_bt(itotv-1)+1:iseq_bt(itotv))
        !         write(7,*)itotv,global_stiff2_bt(iseq_bt(itotv-1)+1:iseq_bt(itotv))
        !    endif
        !end do


100     format(i5,48e15.5)
        !
        !write(7,*)'factoriza=','type_solver_ctt=',type_solver_ctt
        operation='FACTORIZE'
        call profile_ctt_back_analysis
    endif

    iter_bt=0
20  allocate(result_bt(ntotvbt),rot(kkdimn,kkdimn))
    allocate(eldis(kkdimn))

    if(neq_bt/=0)then
        allocate(rvector_bt(neq_bt))
        rvector_bt=0.
    endif


    result_bt=resultx

    do itotv=1,ntotvbt
        if (totveq_bt(itotv)/=0)then
            rvector_bt(totveq_bt(itotv))=rvector_bt(totveq_bt(itotv))+result_bt(itotv)
            !write(7,*)'itotv=',itotv,'ieq=',totveq_bt(itotv),'rvector=',rvector_bt(totveq_bt(itotv))
        endif
    end do

    operation='SOLVE'
    call profile_ctt_back_analysis

    !write(7,*)'iter_bt=',iter_bt,'resultm=',resultm
    !
    !stop



    do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb
        rdisp=0.
        if(gapb(igapb)%nrdof==0)cycle
        do idimn=1,gapb(igapb)%nrdof
            itotv=gapb(igapb)%rldofs(idimn)
            if(itotv==0) cycle
            rdisp(idimn)=resultm(itotv)
        enddo
        !write(7,*)'iter_bt=',iter_bt,'rdisp=',rdisp

        gapb(igapb)%rdisp_inc=gapb(igapb)%rdisp_inc+rdisp !fzx !约束点位移增量  !rdisp0+rdisp

        !write(7,*)'igapb=',igapb,'rdisp_inc=',gapb(igapb)%rdisp_inc
    enddo

    !end fzx


    allocate(ctfori1(kkdimn),ctfori2(kkdimn),ctforl1(kkdimn),ctforl2(kkdimn))

    ctfor=0.


    do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb
        npgblock=gapb(igapb)%npgblock

        do i0=1,npgblock
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            ipoin=gapb(igapb)%nppt(i0)
            jtotv= nodfnbt(ndimn,ipoin)
            !if(ij==2)cycle
            gaps(igaps)%ctforcei(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)  !2012818
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3)then
                    !rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                    !rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                endif
            endif

            ctfori1=0. ; ctfori2=0. ; ctforl1=0. ; ctforl2=0.
            kdimn=1
            if(gaps(igaps)%frict_less==1)kdimn=ndimn
            do idimn=1,kkdimn
                itotv= nodfnbt(idimn,ipoin)
                gaps(igaps)%ctforce(idimn,ipairs)=gaps(igaps)%ctforce(idimn,ipairs)+resultm(itotv)
                ctforl1(idimn)=gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs)
                ctforl2(idimn)=-ctforl1(idimn)
            end do


            ctfori1=transpose(rot).x.ctforl1
            ctfori2=transpose(rot).x.ctforl2

            call ctfor_center_to_node(igaps,ipairs,ctfori1,ctfori2,ctfor)
        end do
    end do
    !!!!!!!!!!!!!
    dnorm=0
    tnorm=0.
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        kdimn=1
        if(gaps(igaps)%frict_less==1)kdimn=ndimn
        do ipairs=1,npairs
            do idimn=kdimn,kkdimn
                dnorm=dnorm+(gaps(igaps)%ctforcei(idimn,ipairs)-gaps(igaps)%ctforce(idimn,ipairs))**2
                tnorm=tnorm+gaps(igaps)%ctforce(idimn,ipairs)**2
            end do
        end do
    end do
    dnorm=sqrt(dnorm)
    tnorm=sqrt(tnorm)
    jconv=0
    if  (dnorm<tor_bt.and.tnorm<tor_bt)jconv=1

    if  (dnorm>tor_bt.or.tnorm>tor_bt)then
        if  (tnorm<tor_bt)then !>?? fzx
            jconv=1
        else
            if (dnorm/tnorm<tor_bt)jconv=1

        endif
    endif

    write(7,'(a,i4,3(a,e15.6),a,i4)')'iter_bt=',iter_bt,' dnorm=',dnorm,' tnorm=',tnorm,' jconv=',jconv

    deallocate(resultm,result_bt,rot,eldis,ctfori1,ctfori2,ctforl1,ctforl2)
    if(neq_bt/=0)deallocate(rvector_bt)

    if  (iter_bt==0.or.(jconv==0.and.iter_bt<=miter_bt)) then
        iter_bt=iter_bt+1


        !!!!!!!!!!!!!!!!!!!!
        !下面这一部分计算由于接触力引起的变化，并求解相应的位移增量
        rvector=rvector_mid


        do itotv=1,ntotv
            if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)
        end do

        do itotv=1,ntotv
            nintf=trans(itotv)%nintf
            if  (nintf/=0) then
                iieq=totveq(itotv)
                if (iieq/=0)rvector(iieq)=0.
                do iintf=1,nintf
                    iieq=totveq(trans(itotv)%listf(iintf))
                    if (iieq/=0)rvector(iieq)=rvector(iieq)+ctfor(itotv)*trans(itotv)%rintf(iintf)
                end do
            endif
        end do

        operation='SOLVE'
        call solve

        !!!!!
        !下面这一部分为力的变化导致位移增量
        resultx=0.

        !  do igapbf=1,nbackf
        !  do kpoin=1,backf(igapbf)%mdism
        !           		   jpoin=backf(igapbf)%listp(kpoin)
        !                    jdimn=backf(igapbf)%listdim(kpoin)
        !                    itotv=nodfn(jdimn,jpoin)
        !   resultx(kpoin)=backf(igapbf)%dism(kpoin)-result_zero(itotv)-result(itotv)
        !end do
        !  end do

        do igapbf=1,nbackf

            igapb=backf(igapbf)%groupb
            npgblock=gapb(igapb)%npgblock

            if(backf(igapbf)%mdism==npgblock*kkdimn)then
                do kpoin=1,backf(igapbf)%mdism
                    if(backf(igapbf)%ic(kpoin)==0) cycle !20210726
                    jdimn=backf(igapbf)%listdim(kpoin)
                    dispoint1=0.    !20230523
                    nintf=backf(igapbf)%relat(kpoin)%nintf
                    do iintf=1,nintf
                        jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                        dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                    end do


                    resultx(kpoin)=backf(igapbf)%dism(kpoin,trstep)-dispoint1 !20220101
                    !resultx(kpoin)=backf(igapbf)%dism(kpoin)-result_zero(itotv)-result(itotv)
                    !if(jpoin0/=0)resultx(kpoin)=resultx(kpoin)+result_zero(itotv0)+result(itotv0)
                end do
            else if(backf(igapbf)%mdism>npgblock*kkdimn)then
                allocate(resback(backf(igapbf)%mdism))
                resback=0.
                do kpoin=1,backf(igapbf)%mdism
                    if(backf(igapbf)%ic(kpoin)==0) cycle !20210726
                    jdimn=backf(igapbf)%listdim(kpoin)
                    dispoint1=0.    !20230523
                    nintf=backf(igapbf)%relat(kpoin)%nintf
                    do iintf=1,nintf
                        jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                        dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                    end do


                    resback(kpoin)=backf(igapbf)%dism(kpoin,trstep)-dispoint1 !20220101
                end do

                resultx(1:npgblock*kkdimn)=(transpose(gapb(igapb)%uireact).x.resback)
                deallocate(resback)

            endif
        end do     !2015/11/28

        !write(7,*)'resultx1=',resultx

        call getardisp_back_analysis(resultx) !迭代过程中，将刚体位移增量引起的接触面位移增量累加到resultx中
        call getatf_back_analysis(resultx,rvector,ctfor,result) ! 接触力变化引起刚体运动平衡方程右端项变化
        !write(7,*)'resultx2=',resultx
        goto 20
    endif

    !!!!!!!!!!!!!!!!!!!!

    ctfor=0.
    allocate(ctfori1(kkdimn),ctfori2(kkdimn),ctforl1(kkdimn),ctforl2(kkdimn),rot(kkdimn,kkdimn))

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        ctfori1=0. ; ctfori2=0. ; ctforl1=0. ; ctforl2=0.
        do ipairs=1,npairs
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3)then
                    !rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                    !rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                endif
            endif

            do idimn=1,kkdimn
                ctforl1(idimn)=gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs)
            end do
            ctfori1=transpose(rot).x.ctforl1
            do idimn=kdimn,kkdimn
                ctforl2(idimn)=-(gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs))
            end do
            ctfori2=transpose(rot).x.ctforl2

            call  ctfor_center_to_node(igaps,ipairs,ctfori1,ctfori2,ctfor)

        end do  !ipairs
    end do  !igaps
    deallocate(ctfori1,ctfori2,ctforl1,ctforl2,rot)

29  format(i10,3e15.5)
    rvector=rvector_mid

    !write(7,*)'istep=',istep,'iiter=',iiter,'ctfor='
    do itotv=1,ntotv
        if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)

    end do

    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if  (nintf/=0) then
            iieq=totveq(itotv)
            if (iieq/=0)rvector(iieq)=0.
            do iintf=1,nintf
                iieq=totveq(trans(itotv)%listf(iintf))
                if (iieq/=0)rvector(iieq)=rvector(iieq)+ctfor(itotv)*trans(itotv)%rintf(iintf)
            end do
        endif
    end do
    tofor=tofor+ctfor

    operation='SOLVE'
    call solve


    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
        end do
    end do

    !!!!!!!!!!!!!!!!!!!!!!
    deallocate(resultx,rvector_mid)
    deallocate(dispre)
    if(miter_state>1)deallocate(result0)
    write(7,*)'iter_bt=',iter_bt
    write(7,'(5(a,i5))')'iblks=',iblks,' iincs=',iincs,' istep=',istep,' iiter=',iiter,' iter_bt=',iter_bt
    deallocate(ctfor)
    deallocate(rdisp) !fzx

    contains

    subroutine profile_ctt_back_analysis !20150925

    Select Case ( Operation)

    Case ('SET')

        !!!!!!!!!!!!!!!!!!!!
        if (allocated(trans_bt))deallocate(trans_bt)
        allocate(trans_bt(ntotvbt))
        trans_bt(:)%nintf=0


        if (allocated(iffix_bt))deallocate(iffix_bt)
        allocate(iffix_bt(ntotvbt))
        iffix_bt=1

        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                jpoin=gapb(igapb)%nppt(i0)
                iffix_bt(nodfnbt(1:kkdimn,jpoin))=0
            end do
        end do

        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            if(gapb(igapb)%nrdof==0) cycle
            do idimn=1,gapb(igapb)%nrdof  !tcl
                if(gapb(igapb)%rldofs(idimn)==0) cycle
                iffix_bt(gapb(igapb)%rldofs(idimn))=0
            end do
        end do

        !end fzx
        if (allocated(totveq_bt))deallocate(totveq_bt)
        allocate(totveq_bt(ntotvbt))
        totveq_bt=0
        do itotv=1,ntotvbt
            if  (iffix_bt(itotv)==0) then
                if  (trans_bt(itotv)%nintf==0)then
                    totveq_bt(itotv)=1
                else
                    if (any(trans_bt(itotv)%listf==itotv))totveq_bt(itotv)=1

                endif
            endif
        end do


        neq_bt=0
        do itotv=1,ntotvbt
            if(totveq_bt(itotv)==1)then
                neq_bt=neq_bt+1
                totveq_bt(itotv)=neq_bt
            endif
        end do
        print *,'neq_bt=',neq_bt


        if (allocated(iseq_bt))deallocate(iseq_bt)
        if(neq_bt/=0)then
            allocate(iseq_bt(neq_bt))
            iseq_bt=0
        endif
        !!int2000
        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            nevab=gapb(igapb)%ntotv_bt
            do ievab=1,nevab
                nintf=trans_bt(gapb(igapb)%ldofs(ievab))%nintf
                do jevab=1,nevab
                    njntf=trans_bt(gapb(igapb)%ldofs(jevab))%nintf

                    if  (nintf==0.and.njntf==0) then !!1
                        ieq=totveq_bt(gapb(igapb)%ldofs(ievab))
                        jeq=totveq_bt(gapb(igapb)%ldofs(jevab))
                        if  (ieq/=0.and.jeq/=0) then
                            dijeq=ieq-jeq
                            if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                        endif
                    else if(nintf/=0.and.njntf==0)then  !!2
                        do iintf=1,nintf
                            ieq=totveq_bt(trans_bt(gapb(igapb)%ldofs(ievab))%listf(iintf))
                            jeq=totveq_bt(gapb(igapb)%ldofs(jevab))
                            if  (ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                            endif
                        end do
                    else if(nintf==0.and.njntf/=0)then  !!3
                        ieq=totveq_bt(gapb(igapb)%ldofs(ievab))
                        do jintf=1,njntf
                            jeq=totveq_bt(trans_bt(gapb(igapb)%ldofs(jevab))%listf(jintf))
                            if  (ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                            endif
                        end do
                    else if(nintf/=0.and.njntf/=0)then !!4
                        do iintf=1,nintf
                            ieq=totveq_bt(trans_bt(gapb(igapb)%ldofs(ievab))%listf(iintf))
                            do jintf=1,njntf
                                jeq=totveq_bt(trans_bt(gapb(igapb)%ldofs(jevab))%listf(jintf))
                                if  (ieq/=0.and.jeq/=0) then
                                    dijeq=ieq-jeq
                                    if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                                endif
                            end do
                        end do
                    endif
                end do
            end do
        end do
        !!int2000

        print *,'neq_bt=',neq_bt
        if (neq_bt==0) return
        Max_band=0
        Iseq_bt(1)=1
        DO Ieq=2,Neq_bt
            if  (Max_band<Iseq_bt(Ieq))then
                Max_band=Iseq_bt(Ieq)
            endif
            Iseq_bt(Ieq)=Iseq_bt(Ieq)+Iseq_bt(Ieq-1)+1
        end do
        Max_band=Max_band+1
        Stiff_length=Iseq_bt(neq_bt)
        write(chkunit,*)'No. of equations        =',neq_bt
        write(chkunit,*)'Max half band width     =',Max_band
        write(chkunit,*)'length half stiff matrix=',Stiff_length
        if (allocated(global_stiff_bt))deallocate(global_stiff_bt)
        if (allocated(rvector_bt))    deallocate(rvector_bt)
        allocate(global_stiff_bt(Stiff_length))
        global_stiff_bt=0.0
        if(nonsbt==1)then
            if (allocated(global_stiff2_bt))deallocate(global_stiff2_bt)
            allocate(global_stiff2_bt(Stiff_length))
            global_stiff2_bt=0.0
        endif


    case ('FACTORIZE')
        call skfaca_bt(global_stiff_bt,global_stiff2_bt,iseq_bt,0)

    case ('SOLVE')


        if(neq_bt/=0)then
            if (nonsbt==0)call sksols_bt(global_stiff_bt,rvector_bt,iseq_bt)
            if (nonsbt==1)call sksola_bt(global_stiff_bt,rvector_bt,global_stiff2_bt,iseq_bt)
        endif

        allocate(resultm(ntotvbt))
        resultm=0.
        do itotv=1,ntotvbt !npbt*ndimn
            nintf=trans_bt(itotv)%nintf
            if  (iffix_bt(itotv)==0.and.nintf==0) then
                resultm(itotv)=rvector_bt(totveq_bt(itotv))
            elseif(nintf/=0) then
                listf=>trans_bt(itotv)%listf
                rintf=>trans_bt(itotv)%rintf
                do jtotv=1,nintf
                    njntf=trans_bt(listf(jtotv))%nintf
                    if(njntf==0)then
                        if (totveq_bt(listf(jtotv))>0)resultm(itotv)=resultm(itotv)+rvector_bt(totveq_bt(listf(jtotv)))*rintf(jtotv)
                    else
                        do k1=1,njntf
                            if (totveq_bt(trans_bt(listf(jtotv))%listf(k1))>0)resultm(itotv)=resultm(itotv)+   &
                                rvector_bt(totveq_bt(trans_bt(listf(jtotv))%listf(k1)))*trans_bt(listf(jtotv))%rintf(k1)
                        end do
                    endif
                enddo
                nullify(listf,rintf)
            endif
        end do


    end select
    end  subroutine profile_ctt_back_analysis !20150925

    !!!!!!!!!!!!!!!!!!!!!!!!!!
    end subroutine solve_ctt_back_analysis  !20150925
    !!!!!!20150925
    !!! 20210820
    SUBROUTINE solve_back_d_analysis !20210820
    integer(ink) igapbf,igapb,kpoin,npgblock,jpoin,jpoin0,jdimn,itotv,jtotv, &
        nintf,iintf,kkdimn,itotv0,i0,j0,igaps,ipair,ntotv_bt,ngpblock,ij,idimn
    real   (irk) dispoint0,dispoint1,dispoint,tfi
    real   (irk),allocatable ::resultx(:,:),resultdf(:,:),resback(:),dfmatrix(:,:),  &
        dis_bound(:),dis_bound0(:)


    write(7,*)'in solve_back_d_analysis'

    kkdimn=ndimn  !2015/11/17
    if(block_stab==1)kkdimn=3*(ndimn-1) !2015/11/17



    do igapbf=1,nbackf

        igapb=backf(igapbf)%groupb
        npgblock=gapb(igapb)%npgblock
        write(7,*)'igapb=',igapb,'npgblock=',npgblock

        allocate(resultx(npgblock*kkdimn,1),dfmatrix(npgblock*kkdimn,npgblock*kkdimn),  &
            resultdf(npgblock*kkdimn,1),dis_bound(ntotv),dis_bound0(ntotv))
        resultx=0.
        dfmatrix=0.
        resultdf=0.


        if(backf(igapbf)%mdism==npgblock*kkdimn)then
            do kpoin=1,backf(igapbf)%mdism
                if(backf(igapbf)%ic(kpoin)==0) cycle
                jdimn=backf(igapbf)%listdim(kpoin)
                dispoint1=0.    !20230523
                nintf=backf(igapbf)%relat(kpoin)%nintf
                do iintf=1,nintf
                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                    dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                end do


                resultx(kpoin,1)=backf(igapbf)%dism(kpoin,trstep)-dispoint1 !20220101
            end do
        else if(backf(igapbf)%mdism>npgblock*kkdimn)then
            allocate(resback(backf(igapbf)%mdism))
            resback=0.  !20210726
            do kpoin=1,backf(igapbf)%mdism
                if(backf(igapbf)%ic(kpoin)==0) cycle !20210726
                jdimn=backf(igapbf)%listdim(kpoin)
                dispoint1=0.    !20230523
                nintf=backf(igapbf)%relat(kpoin)%nintf
                do iintf=1,nintf
                    jtotv=backf(igapbf)%relat(kpoin)%listf(iintf)
                    dispoint1=dispoint1+(result_zero(jtotv)+result(jtotv))*backf(igapbf)%relat(kpoin)%rintf(iintf)
                end do


                resback(kpoin)=backf(igapbf)%dism(kpoin,trstep)-dispoint1 !20220101
            end do


            resultx(1:npgblock*kkdimn,1)=(transpose(gapb(igapb)%uireact).x.resback)
            deallocate(resback)

        endif



        dfmatrix=gapb(igapb)%cmatrix
        write(7,*)'size(dfmatrix)=',size(dfmatrix,1),size(dfmatrix,2)

        call householder(dfmatrix,resultx,resultdf) !3

        dis_bound=0.
        jtotv=0
        write(7,*)'igapb=',igapb,'npgblock=',npgblock
        write(7,*)'result spring=:i0,ipoin,kkdimn'
        do i0=1,npgblock
            !write(7,*)'i0=',i0
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ipair=gapb(igapb)%nodegblock_ipairs(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            ipoin=gaps(igaps)%pairnode(ij,ipair)
            !write(7,*)'i0=',i0,'ipoin=',ipoin,'kkdimn=',kkdimn
            do idimn=1,kkdimn
                jtotv=jtotv+1
                itotv=nodfn(idimn,ipoin)
                dis_bound(itotv)=resultdf(jtotv,1)
            end do
            write(7,2)ipoin,dis_bound(nodfn(:,ipoin))
        end do

        deallocate(resultx,dfmatrix,resultdf)
    end do
    dis_bound0=dis_bound

    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if (nintf==0) cycle
        dispoint=0.
        do iintf=1,nintf
            jtotv=trans(itotv)%listf(iintf)
            dispoint=dispoint+dis_bound0(jtotv)*trans(itotv)%rintf(iintf)
        end do
        dis_bound(itotv)=dispoint
        !write(7,*)itotv,dis_bound(itotv)
    end do


    call rvector_load_react(igapb,dis_bound)

    operation='SOLVE'
    call solve
    !result=result+dis_bound  !20211212
    result_zero=result_zero+dis_bound  !20211212

    ! record the displacements of spring points
    do igapbf=1,nbackf
        igapb=backf(igapbf)%groupb
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ipair=gapb(igapb)%nodegblock_ipairs(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            ipoin=gaps(igaps)%pairnode(ij,ipair)
            gapb(igapb)%disp_ct(1:kkdimn,i0)=result_zero(nodfn(1:kkdimn,ipoin))  !坝和地基交界点处位移
        end do
    end do

    !  write(7,*)'sum(tofor(1:mdofn))1'
    !  do idimn=1,mdofn
    !tfi=0.
    !do ipoin=1,npoin
    !    itotv=nodfn(idimn,ipoin)
    !    if(itotv/=0)then
    !        !if(totveq(itotv)/=0) &
    !    tfi=tfi+tofor(itotv)
    !    endif
    !end do
    !write(7,*)'idimn=',idimn,'tfi=',tfi
    !  end do



    deallocate(dis_bound,dis_bound0)

1   format(2i5,3f15.5)
2   format(i5,6e15.5)
    end SUBROUTINE solve_back_d_analysis !20210820

    SUBROUTINE rvector_load_react(igapb,dis_bound) !20210820

    real(irk) dis_bound(:)
    real(irk),allocatable::load_react(:),eload(:),value(:)
    integer(ink) kdimn,jpoin,igapb,igroup,jgroup,idofn,itotv,nintf,iieq,iintf,nevab, &
        ielem,ielgroup,jtotv
    integer(ink),pointer::ldofs(:)
    real(irk),   pointer::fstif(:,:)

    allocate(load_react(ntotv))
    load_react=0.

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
                value=dis_bound(ldofs)
                eload=fstif.x.value
                load_react(ldofs)=load_react(ldofs)-eload
                nullify(fstif,ldofs)
            endif
        end do       !!ielgroup
        deallocate(value,eload)
    end do     !!  for igroup

    do itotv=1,ntotv
        if (totveq(itotv)==0)cycle
        rvector(totveq(itotv))=rvector(totveq(itotv))+load_react(itotv)
    end do

    !!int2000
    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if (nintf==0) cycle
        do iintf=1,nintf
            iieq=totveq(trans(itotv)%listf(iintf))
            if(iieq/=0)rvector(iieq)=rvector(iieq)+  &
                load_react(itotv)*trans(itotv)%rintf(iintf)
        end do
    end do
    !!int2000
    tofor=tofor+load_react  !20211212
    deallocate(load_react)
    end SUBROUTINE rvector_load_react  !20210820


    !!! 20210820



    SUBROUTINE solve_ctt

    integer(ink) nevab,ieq,jeq,dijeq,ievab,jevab,igapb,igaps,inode,ipoin1,ipoin2,jpoin1, &
        jpoin2,iieq,ij,npgblock,kpoin,max_band,stiff_length,i1,i2,ntotv_bt,     &
        iter_bt,idimn,jconv,itotv,jtotv,ipoin,jpoin,ipairs,npairs,iconv,jter_bt,&
        nintf,njntf,iintf,jintf,colum,rpoin,onetwo,jdimn,nnode,ii,i0,i12,       &
        jgapb,j0,jpairs,jgaps,ij1,ij2,iix,k1,iter_state,kdimn,kkdimn,nx1,nx2,istate
    real   (irk) ylost,dista,sigman,ft,t1,t2,tt,alfa1,alfa2,sheart,dnorm,tnorm,facti,xi0,&
        sigmanc,gf,et,sig1,wx,w1,w0,coef,fact,coef1,x0
    real   (irk),allocatable ::resultm(:),eldis(:),recover_bt(:),rvector_mid(:),rot(:,:), &
        ctfor(:),ctfori1(:),ctfori2(:),ctforl1(:),ctforl2(:),      &
        resultx(:),rdisp(:),disl(:),dispre(:),stfor_rigid(:),result0(:)
    integer(ink),pointer::listf(:),ldofs(:),lnods(:) !fzx
    real   (irk),pointer::rintf(:),dislocal(:),cmatrix(:,:)

    print *,'in ctt'
    write(7,*)'nonsbt=',nonsbt,'xlwsol=',xlwsol


    kkdimn=ndimn
    if(block_stab/=0)kkdimn=3*(ndimn-1)
    allocate(dispre(ntotv))
    dispre=0.
    allocate(stfor_rigid(ntotv))
    stfor_rigid=0.
    allocate(rdisp((ndimn-1)*3))
    allocate(resultx(ntotvbt),ctfor(ntotv))
    if(neq>0) &
        allocate(rvector_mid(neq)) !2017/11/19


    iter_state=1
    if(miter_state>1)then
        allocate(result0(ntotv))
        result0=result
        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            do ipairs=1,npairs
                gaps(igaps)%statei(ipairs)=gaps(igaps)%state(ipairs)
                gaps(igaps)%ctforcei(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)  !20161111
            end do
        end do
    endif

    if(neq>0) &    !2017/11/19
        rvector_mid=rvector

10  continue
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(miter_state>1) &
                gaps(igaps)%statei(ipairs)=gaps(igaps)%state(ipairs)
            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)  !20210221
        end do
    end do

    do igapb=1,ngapb   !tcl 2009/10/11
        if(gapb(igapb)%nrdof==0)cycle
        gapb(igapb)%rdisp_inc=0.
    enddo

    allocate(eldis(kkdimn),dislocal(kkdimn),rot(kkdimn,kkdimn))
    ctfor=0.
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    resultx=0.

    fact=1.
    if(type_problem=='F')fact=1./(beeta2*ditime**2)

    !write(7,*)'ipoin,result_zero,result'
    do igapb=1,ngapb
        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            coef=1.
            if(ij==1)coef=-1.
            ipoin=gapb(igapb)%nppt(i0)
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3)then
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                endif
            endif


            call dislocal_node_to_center(kkdimn,ij,igaps,ipairs,coef,fact,result_zero,result,dislocal,eldis,rot)
            do idimn=1,kkdimn
                itotv= nodfnbt(idimn,ipoin)
                resultx(itotv)=resultx(itotv)+dislocal(idimn)
            end do

        end do
    end do

    do igapb=1,ngapb
        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            if(ij==2)cycle
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ipoin=gapb(igapb)%nppt(i0)
            do idimn=ndimn,ndimn   !!!2012704  这里只对法向进行
                itotv= nodfnbt(idimn,ipoin)
                resultx(itotv)=resultx(itotv)+gaps(igaps)%gap0(idimn,ipairs)*fact
            end do
        end do
    end do



    deallocate(dislocal,eldis,rot)
1   format(2i5,3f15.5)
2   format(4i5,3f15.5)
50  format(i5,3f15.8)
51  format(3i5,3f15.8)

    call getardisp(resultx) !迭代过程中，将刚体位移增量引起的接触面位移增量累加到resultx中
    call getatf(resultx,rvector,ctfor,result,stfor_rigid) !接触力变化引起刚体运动平衡方程右端项变化

    write(7,*)'iter_state=',iter_state,'icttstiff=',icttstif
    if((istep==inc_step.and.iiter==1).or.icttstif==1)then  !20210225
        !if((istatec==0.and.iiter==1).or.istatec==1)then  !20210225
        operation='SET'
        if(type_solver_ctt=='PROFILE') &
            call profile_ctt
        if(type_solver_ctt=='PARDISO') &
            call pardiso_ctt
        if(neq_bt==0) goto 20

        do igapb=1,ngapb  !assemble the local stiff_matrix for the local region
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            ntotv_bt=gapb(igapb)%ntotv_bt
            if(type_solver_ctt=='PROFILE') &
                call global_stif_profile_ctt(ntotv_bt,gapb(igapb)%ldofs,gapb(igapb)%cmatrix)


            if(type_solver_ctt=='PARDISO') &
                call global_stif_pardiso_ctt(gapb(igapb)%ldofs,gapb(igapb)%cmatrix)
        end do


        do igapb=1,ngapb  !加入接触点对相对位移柔度系数
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                istate=gaps(igaps)%state(ipairs)
                if(istatec==0)istate=gaps(igaps)%state0(ipairs)
                if  (istate==0) cycle
                if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904
                    jpoin=gapb(igapb)%nppt(i0)
                    do idimn=1,kkdimn
                        itotv=nodfnbt(idimn,jpoin)
                        if(itotv==0)cycle !fzx
                        ieq=totveq_bt(itotv) !通过ieq是否为零，保证只将kxyz计入一次
                        do jdimn=1,kkdimn
                            jtotv=nodfnbt(jdimn,jpoin)
                            if(jtotv==0)cycle !fzx
                            jeq=totveq_bt(jtotv) !通过ieq是否为零，保证只将kxyz计入一次
                            if(jeq/=0.and.ieq/=0.and.ieq<=jeq) then
                                colum=iseq_bt(jeq)-jeq+ieq
                                if(istatec==0)then
                                    global_stiff_bt(colum)=global_stiff_bt(colum)+gaps(igaps)%kxyz0(idimn,jdimn,ipairs)*fact
                                    if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+gaps(igaps)%kxyz(jdimn,idimn,ipairs)*fact
                                else
                                    global_stiff_bt(colum)=global_stiff_bt(colum)+gaps(igaps)%kxyz(idimn,jdimn,ipairs)*fact
                                    if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+gaps(igaps)%kxyz(jdimn,idimn,ipairs)*fact
                                endif
                            endif
                        end do
                    end do
                endif
            end do
        end do


        !write(7,*)'istep=',istep,'iiter=',iiter,'global_stiff_bt01='
        ! do itotv=1, neq_bt
        !!     if(itotv==1)then
        !     write(7,*)itotv,global_stiff_bt(iseq_bt(itotv))
        !!     else
        !!         write(7,*)itotv,global_stiff_bt(iseq_bt(itotv-1)+1:iseq_bt(itotv))
        !!     endif
        ! end do
        !write(7,*)'global_stiff_bt='
        !do ieq=1,neq_bt
        !    write(7,*)ieq,global_stiff_bt(iseq_bt(ieq))
        !end do

100     format(i5,48e15.5)

        !write(7,*)'factoriza=','type_solver_ctt=',type_solver_ctt
        operation='FACTORIZE'
        if(type_solver_ctt=='PROFILE') &
            call profile_ctt
        if(type_solver_ctt=='PARDISO') &
            call pardiso_ctt

    endif

    iter_bt=0
20  allocate(result_bt(ntotvbt),rot(kkdimn,kkdimn))
    allocate(eldis(kkdimn))

    if(neq_bt/=0)then
        if(allocated(rvector_bt))deallocate(rvector_bt)
        allocate(rvector_bt(neq_bt))
        rvector_bt=0.
    endif

    result_bt=resultx

    !write(7,*)'iter_bt=',iter_bt,'itotv,ieq,result_bt00,rvector_bt'
    do itotv=1,ntotvbt
        if (totveq_bt(itotv)/=0)then
            rvector_bt(totveq_bt(itotv))=rvector_bt(totveq_bt(itotv))+result_bt(itotv)
            !write(7,*)itotv,totveq_bt(itotv),result_bt(itotv),rvector_bt(totveq_bt(itotv))
        endif
    end do

    do itotv=1,ntotvbt
        nintf=trans_bt(itotv)%nintf
        if(nintf/=0) then
            do iintf=1,nintf
                iieq=totveq_bt(trans_bt(itotv)%listf(iintf))
                if(iieq/=0) then
                    rvector_bt(iieq)=rvector_bt(iieq)+result_bt(itotv)*trans_bt(itotv)%rintf(iintf)
                endif
            end do
        endif
    end do

    !if(istep>=25)then
    !write(7,*)'istep=',istep,'iiter=',iiter,'rvector_bt,global_stiff_bt='
    !do itotv=1,neq_bt
    !    write(7,*)itotv,rvector_bt(itotv),global_stiff_bt(iseq_bt(itotv))
    !end do
    !endif


    do igapb=1,ngapb   !!!!减去接触弹簧位移增量
        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)

            istate=gaps(igaps)%state(ipairs)
            if(istatec==0)istate=gaps(igaps)%state0(ipairs)
            if  (istate==0) cycle
            if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904
                jpoin=gapb(igapb)%nppt(i0)
                do idimn=1,kkdimn
                    itotv=nodfnbt(idimn,jpoin)

                    if(itotv==0)cycle !fzx
                    ieq=totveq_bt(itotv)
                    if(ieq==0) cycle
                    rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%dxyz(idimn,ipairs)  !20210217(!!)
                    do jdimn=1,kkdimn

                        if(istatec==0)then
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz0(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        else
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        endif
                    end do

                end do

            elseif(istate==2.and.xlwsol==0) then   !20161112
                jpoin=gapb(igapb)%nppt(i0)
                do idimn=ndimn,ndimn
                    itotv=nodfnbt(idimn,jpoin)

                    if(itotv==0)cycle !fzx
                    ieq=totveq_bt(itotv)
                    if(ieq==0) cycle
                    rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%dxyz(idimn,ipairs)  !20210217(!!)
                    do jdimn=ndimn,ndimn
                        if(type_nl==5.or.type_nl==1)then
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz0(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        else
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        endif
                    end do
                end do
            endif
        end do
    end do

    !write(7,*)'rvecor_bt1='
    !do itotv=1,neq_bt
    !write(7,*)itotv,rvector_bt(itotv)
    !end do

    operation='SOLVE'
    if(type_solver_ctt=='PROFILE') &
        call profile_ctt
    if(type_solver_ctt=='PARDISO') &
        call pardiso_ctt

    !write(7,*)'rvecor_bt2='
    !do itotv=1,neq_bt
    !write(7,*)itotv,rvector_bt(itotv)
    !end do


    do igapb=1,ngapb   !tcl 2009/10/11
        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        rdisp=0.
        if(gapb(igapb)%nrdof==0)cycle
        do idimn=1,gapb(igapb)%nrdof
            itotv=gapb(igapb)%rldofs(idimn)
            if(itotv==0) cycle
            rdisp(idimn)=resultm(itotv)
        enddo
        write(7,*)'iter_bt=',iter_bt,'rdisp=',rdisp

        gapb(igapb)%rdisp_inc=gapb(igapb)%rdisp_inc+rdisp !fzx !约束点位移增量  !rdisp0+rdisp

        write(7,*)'igapb=',igapb,'rdisp_inc=',gapb(igapb)%rdisp_inc
    enddo



    allocate(ctfori1(kkdimn),ctfori2(kkdimn),ctforl1(kkdimn),ctforl2(kkdimn))

    ctfor=0.


    do igapb=1,ngapb
        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        npgblock=gapb(igapb)%npgblock
        !write(7,*)'igapb=',igapb,'npgblock=',npgblock
        do i0=1,npgblock
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            ipoin=gapb(igapb)%nppt(i0)

            if(ij==2)cycle  !20120907
            gaps(igaps)%ctforcei(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)  !20161111

            rot=0.  !2015/11/17
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3) rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
            endif


            ctfori1=0. ; ctfori2=0. ; ctforl1=0. ; ctforl2=0.
            kdimn=1
            if(gaps(igaps)%frict_less==1)kdimn=ndimn
            do idimn=kkdimn,kdimn,-1
                itotv= nodfnbt(idimn,ipoin)
                istate=gaps(igaps)%state(ipairs)
                if(istatec==0)istate=gaps(igaps)%state0(ipairs)
                if  (istate==0) cycle
                if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !20120904
                    gaps(igaps)%ctforce(idimn,ipairs)=gaps(igaps)%ctforce(idimn,ipairs)+resultm(itotv)
                elseif(istate==2.and.xlwsol==0)then
                    if (idimn==ndimn)then
                        gaps(igaps)%ctforce(idimn,ipairs)=gaps(igaps)%ctforce(idimn,ipairs)+resultm(itotv)
                    else
                        if(idimn==1)gaps(igaps)%ctforce(idimn,ipairs)=abs(-gaps(igaps)%ctforce(ndimn,ipairs)*   &
                            gaps(igaps)%frict(ipairs)+gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))*gaps(igaps)%alfa1(ipairs)

                        if (ndimn==3) then
                            if(idimn==2)gaps(igaps)%ctforce(idimn,ipairs)=abs(-gaps(igaps)%ctforce(ndimn,ipairs)*   &
                                gaps(igaps)%frict(ipairs)+gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))*gaps(igaps)%alfa2(ipairs)
                        endif
                    endif
                endif

                ctforl1(idimn)=gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs)
                ctforl2(idimn)=-ctforl1(idimn)
            end do

            ctfori1=transpose(rot).x.ctforl1
            ctfori2=transpose(rot).x.ctforl2

            call ctfor_center_to_node(igaps,ipairs,ctfori1,ctfori2,ctfor)

        end do
    end do
    !!!!!!!!!!!!!
    dnorm=0
    tnorm=0.
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        kdimn=1
        if(gaps(igaps)%frict_less==1)kdimn=ndimn
        do ipairs=1,npairs
            do idimn=kdimn,kkdimn
                dnorm=dnorm+(gaps(igaps)%ctforcei(idimn,ipairs)-gaps(igaps)%ctforce(idimn,ipairs))**2
                tnorm=tnorm+gaps(igaps)%ctforce(idimn,ipairs)**2
            end do
        end do
    end do
    dnorm=sqrt(dnorm)
    tnorm=sqrt(tnorm)
    jconv=0
    if  (dnorm<tor_bt.and.tnorm<tor_bt)jconv=1

    if  (dnorm>tor_bt.or.tnorm>tor_bt)then
        if  (tnorm<tor_bt)then !>?? fzx
            jconv=1
        else
            if (dnorm/tnorm<tor_bt)jconv=1

        endif
    endif

    write(7,'(a,i4,3(a,e15.6),a,i4)')'iter_bt=',iter_bt,' dnorm=',dnorm,' tnorm=',tnorm,' jconv=',jconv

    deallocate(resultm,result_bt,rot,eldis,ctfori1,ctfori2,ctforl1,ctforl2)
    if(neq_bt/=0)deallocate(rvector_bt)

    if  (jconv==0.and.iter_bt<miter_bt) then
        iter_bt=iter_bt+1


        !!!!!!!!!!!!!!!!!!!!
        !下面这一部分计算由于接触力引起的变化，并求解相应的位移增量
        rvector=0.
        do itotv=1,ntotv
            if (totveq(itotv)/=0)then
                rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)+tofor(itotv)-stfor(itotv)
            endif
        end do


        if(type_problem=='F'.and.ngapb/=0)then
            stfor_rigid=0.
            call stfor_rigid_accs(stfor_rigid)
            do itotv=1,ntotv
                if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))-stfor_rigid(itotv)
            end do
        endif


        do itotv=1,ntotv
            nintf=trans(itotv)%nintf
            if  (nintf/=0) then
                iieq=totveq(itotv)
                if (iieq/=0)rvector(iieq)=0.
                do iintf=1,nintf
                    iieq=totveq(trans(itotv)%listf(iintf))
                    if (iieq/=0)rvector(iieq)=rvector(iieq)+(ctfor(itotv)+tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                end do
            endif
        end do


        operation='SOLVE'
        call solve

        !!!!!
        !下面这一部分为力的变化导致位移增量引起的接触面位移增量
        allocate(eldis(kkdimn),dislocal(kkdimn),rot(kkdimn,kkdimn))
        resultx=0.
        do igapb=1,ngapb
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                !          i12=gapb(igapb)%nodegblock(i0)
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                coef=1.
                if(ij==1)coef=-1.
                ipoin=gapb(igapb)%nppt(i0)

                rot=0.
                rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

                if(block_stab==1)then
                    if(ndimn==2)rot(3,3)=1.
                    if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                endif

                call dislocal_node_to_center(kkdimn,ij,igaps,ipairs,coef,fact,result_zero,result,dislocal,eldis,rot)

                do idimn=1,kkdimn
                    itotv= nodfnbt(idimn,ipoin)
                    resultx(itotv)=resultx(itotv)+dislocal(idimn)  ! 总位移量
                end do
            end do
        end do

        !write(7,*)'istep=',istep,'iiter=',iiter,'iter_bt=',iter_bt,'iter_state=',iter_state
        !write(7,*)'resultx(1:10)'
        !do itotv=1,10
        !write(7,*)itotv,resultx(itotv)
        !end do

        do igapb=1,ngapb
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                if(ij==2)cycle
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ipoin=gapb(igapb)%nppt(i0)
                do idimn=ndimn,ndimn   !!!2012704  这里只对法向进行
                    itotv= nodfnbt(idimn,ipoin)
                    resultx(itotv)=resultx(itotv)+gaps(igaps)%gap0(idimn,ipairs)*fact
                    !初始间隙不变，在节点对中的第一节点中的总位移上加上初始间隙
                end do
            end do
        end do

        deallocate(dislocal,eldis,rot)
        !!!!!!
        call getardisp(resultx) !迭代过程中，将刚体位移增量引起的接触面位移增量累加到resultx中
        call getatf(resultx,rvector,ctfor,result,stfor_rigid) ! 接触力变化引起刚体运动平衡方程右端项变化
        goto 20
    endif

    !!!!!!!!!!!!!!!!!!!!
    !!!&&&&&&&&&
    !!下一部分是修改接触单元的间隙
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
            gaps(igaps)%dxyz(:,ipairs)=0.
            gaps(igaps)%gap(:,ipairs)=0.
        end do
    end do

    do igapb=1,ngapb
        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            !       i12=gapb(igapb)%nodegblock(i0)    !2015/8
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            ipoin=gapb(igapb)%nppt(i0)
            istate=gaps(igaps)%state(ipairs)
            if(istatec==0)istate=gaps(igaps)%state0(ipairs)
            !     if  (gaps(igaps)%state(ipairs)==0.or.gaps(igaps)%state(ipairs)>=3) then

            do idimn=kdimn,kkdimn
                dista=resultx(nodfnbt(idimn,ipoin))  !ltc
                if(type_problem=='F')dista=dista*beeta2*ditime**2
                if(istatec==0)then
                    gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                else
                    if(istate==0)then
                        gaps(igaps)%gap (idimn,ipairs)=gaps(igaps)%gap (idimn,ipairs)+dista   !得到的是总间隙量
                    elseif(istate==1.or.(istate==2.and.xlwsol==1))then  !20120821
                        gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                    elseif(idimn==ndimn.and.istate==2.and.xlwsol==0)then  !20161112
                        gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                    elseif(istate>=3)then
                        gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                    endif
                endif
            enddo

            !   endif
        end do
    end do

    if(istatec==1) &
        call state_and_stiff_2021

    ctfor=0.
    allocate(ctfori1(kkdimn),ctfori2(kkdimn),ctforl1(kkdimn),ctforl2(kkdimn),rot(kkdimn,kkdimn))

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        kdimn=1
        if(gaps(igaps)%frict_less==1)kdimn=ndimn
        ctfori1=0. ; ctfori2=0. ; ctforl1=0. ; ctforl2=0.
        do ipairs=1,npairs
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
            endif

            do idimn=kdimn,kkdimn
                ctforl1(idimn)=gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs)
            end do
            ctfori1=transpose(rot).x.ctforl1
            do idimn=kdimn,kkdimn
                ctforl2(idimn)=-(gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs))
            end do
            ctfori2=transpose(rot).x.ctforl2

            call  ctfor_center_to_node(igaps,ipairs,ctfori1,ctfori2,ctfor)


        end do  !ipairs
    end do  !igaps
    deallocate(ctfori1,ctfori2,ctforl1,ctforl2,rot)

29  format(i10,3e15.5)
    !rvector=rvector_mid
    rvector=0.


    if(type_problem=='F'.and.ngapb/=0)then
        stfor_rigid=0.
        call stfor_rigid_accs(stfor_rigid)
        do itotv=1,ntotv

            if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))-stfor_rigid(itotv)
        end do
    endif

    do itotv=1,ntotv
        if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)+tofor(itotv)-stfor(itotv)
    end do

    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if  (nintf/=0) then
            iieq=totveq(itotv)
            if (iieq/=0)rvector(iieq)=0.
            do iintf=1,nintf
                iieq=totveq(trans(itotv)%listf(iintf))
                if (iieq/=0)rvector(iieq)=rvector(iieq)+(ctfor(itotv)+tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
            end do
        endif
    end do

    !
    !write(7,*)'itotv,rvector,tofor,stfor,ctfor='
    ! do itotv=1,ntotv
    !     if(totveq(itotv)/=0)then
    !     write(7,*)itotv,rvector(totveq(itotv)),tofor(itotv),stfor(itotv),ctfor(itotv)
    !     endif
    ! end do
    !


    operation='SOLVE'
    call solve

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
            gaps(igaps)%state0(ipairs)=gaps(igaps)%state(ipairs)  !20210217
            gaps(igaps)%damage0(ipairs)=gaps(igaps)%damage(ipairs) !20210217
            gaps(igaps)%ctforcej(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
        end do
    end do


    if(istatec==1.and.miter_state>1.and.iter_state<miter_state)then
        jconv=0

        !!!!
        !下面这一部分为接触力的变化导致位移增量引起的接触面位移增量
        allocate(eldis(kkdimn),dislocal(kkdimn),rot(kkdimn,kkdimn))
        resultx=0.
        !write(7,*)'fact=',fact
        do igapb=1,ngapb
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                !          i12=gapb(igapb)%nodegblock(i0)
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                coef=1.
                if(ij==1)coef=-1.
                ipoin=gapb(igapb)%nppt(i0)

                rot=0.
                rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

                if(block_stab==1)then
                    if(ndimn==2)rot(3,3)=1.
                    if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                endif

                call dislocal_node_to_center(kkdimn,ij,igaps,ipairs,coef,fact,result_zero,result,dislocal,eldis,rot)
                !位移叠加存在问题，result只计及了接触力增量，但ctforce0在变化。
                do idimn=1,kkdimn
                    itotv= nodfnbt(idimn,ipoin)
                    resultx(itotv)=resultx(itotv)+dislocal(idimn)  ! 总位移量
                end do
            end do
        end do

        do igapb=1,ngapb
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                if(ij==2)cycle
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ipoin=gapb(igapb)%nppt(i0)
                do idimn=ndimn,ndimn   !!!2012704  这里只对法向进行
                    itotv= nodfnbt(idimn,ipoin)
                    resultx(itotv)=resultx(itotv)+gaps(igaps)%gap0(idimn,ipairs)*fact
                    !初始间隙不变，在节点对中的第一节点中的总位移上加上初始间隙
                end do
            end do
        end do



        deallocate(dislocal,eldis,rot)
        !!!!!!

        tofor=tofor+ctfor  !20210217 这里表示将ctfor转换到tofor里去了
        ctfor=0.
        !
        dnorm=0
        tnorm=0.
        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            kdimn=1
            if(gaps(igaps)%frict_less==1)kdimn=ndimn
            do ipairs=1,npairs
                do idimn=kdimn,kkdimn
                    dnorm=dnorm+(gaps(igaps)%ctforcej(idimn,ipairs)-gaps(igaps)%ctforce(idimn,ipairs))**2
                    tnorm=tnorm+gaps(igaps)%ctforce(idimn,ipairs)**2
                end do
            end do
        end do
        dnorm=sqrt(dnorm)
        tnorm=sqrt(tnorm)
        print *,'iter_state=',iter_state,'dnorm=',dnorm,'tnorm=',tnorm,'dnorm/tnorm=',dnorm/tnorm
        jconv=0
        if  (dnorm<tor_bt.and.tnorm<tor_bt)jconv=1

        if  (dnorm>tor_bt.or.tnorm>tor_bt)then
            if  (tnorm<tor_bt) jconv=1
            if (dnorm/tnorm<tor_bt)jconv=1
        endif
        if(jconv==0)then
            iter_bt=0
            iter_state=iter_state+1
            goto 10
        endif

    endif

    !  if(type_nl==4.and.miter_state>1.and.iter_state<miter_state)then
    !            jconv=0
    !    do igaps=1,ngaps
    !     npairs=gaps(igaps)%npairs
    !     do ipairs=1,npairs
    ! if(gaps(igaps)%state(ipairs)/=gaps(igaps)%statei(ipairs))jconv=jconv+1
    !     end do
    !   end do
    !
    !if(jconv>0)then
    !iter_state=iter_state+1
    !goto 10
    !endif
    !  endif  !20161111

    !!!!!!!!!!!!!!!!!!!!!!
    if(neq>0) & !2017/11/19
        deallocate(rvector_mid)
    deallocate(resultx)
    deallocate(dispre)
    if(type_problem=='F'.and.ngapb/=0)deallocate(stfor_rigid)
    if(miter_state>1)deallocate(result0)
    write(7,*)'iter_bt=',iter_bt,'gaps(1)%cohes(1)=',gaps(1)%cohes(1)
    write(7,'(5(a,i5))')'iblks=',iblks,' iincs=',iincs,' istep=',istep,' iiter=',iiter,' iter_bt=',iter_bt
    deallocate(ctfor)
    deallocate(rdisp) !fzx

    contains

    subroutine profile_ctt

    Select Case ( Operation)

    Case ('SET')

        !!!!!!!!!!!!!!!!!!!!
        if (allocated(trans_bt))deallocate(trans_bt)
        allocate(trans_bt(ntotvbt))
        trans_bt(:)%nintf=0


        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

        iix=0
        do igapb=1,ngapb
            do jgapb=igapb,ngapb
                do i0=1,gapb(igapb)%npgblock
                    k1=1
                    if(igapb==jgapb)k1=i0+1
                    do j0=k1,gapb(jgapb)%npgblock

                        if(block_stab==1.or.contactpe==1)then  !2015/8
                            i1=gapb(igapb)%nodegblock(i0)
                            i2=gapb(jgapb)%nodegblock(j0)
                            if(i1==i2)cycle
                        endif !2015/8

                        ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                        igaps=gapb(igapb)%nodegblock_igaps(i0)
                        istate=gaps(igaps)%state(ipairs)
                        if(type_nl==5.or.type_nl==1)istate=gaps(igaps)%state0(ipairs)

                        jpairs=gapb(jgapb)%nodegblock_ipairs(j0)
                        jgaps=gapb(jgapb)%nodegblock_igaps(j0)

                        if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
                        if(gaps(jgaps)%pair_process(jpairs)==0)cycle  !20200331


                        if((ipairs/=jpairs).or.(igaps/=jgaps))cycle
                        iix=iix+1
                        if  (istate/=0) then  !tcl

                            if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904

                                jpoin1=gapb(igapb)%nppt(i0)
                                jpoin2=gapb(jgapb)%nppt(j0)
                                kdimn=1
                                if(gaps(igaps)%frict_less==1)kdimn=ndimn

                                do idimn=kdimn,kkdimn !(ndimn-1)*3*2 !ndimn !fzx 没有必要
                                    itotv=nodfnbt(idimn,jpoin1)
                                    jtotv=nodfnbt(idimn,jpoin2)
                                    if(itotv*jtotv==0)cycle !fzx
                                    nintf=trans_bt(jtotv)%nintf
                                    if(nintf/=0)cycle
                                    nintf=trans_bt(itotv)%nintf
                                    if(nintf==0)then
                                        trans_bt(jtotv)%nintf=1
                                        allocate(trans_bt(jtotv)%listf(1),trans_bt(jtotv)%rintf(1))
                                        trans_bt(jtotv)%listf(1)=itotv
                                        trans_bt(jtotv)%rintf(1)=1.
                                    else   !!20120907
                                        trans_bt(jtotv)%nintf=nintf
                                        allocate(trans_bt(jtotv)%listf(nintf),trans_bt(jtotv)%rintf(nintf))
                                        trans_bt(jtotv)%listf=trans_bt(itotv)%listf
                                        trans_bt(jtotv)%rintf=trans_bt(itotv)%rintf
                                    endif  !!20120907
                                end do


                            else if(istate.and.xlwsol==0) then   !20161112

                                jpoin1=gapb(igapb)%nppt(i0)
                                jpoin2=gapb(jgapb)%nppt(j0)
                                do idimn=ndimn,ndimn !(ndimn-1)*3*2 !ndimn !fzx 没有必要
                                    itotv=nodfnbt(idimn,jpoin1)
                                    jtotv=nodfnbt(idimn,jpoin2)
                                    if(itotv*jtotv==0)cycle !fzx
                                    nintf=trans_bt(jtotv)%nintf
                                    if(nintf/=0)cycle
                                    nintf=trans_bt(itotv)%nintf
                                    if(nintf==0)then
                                        trans_bt(jtotv)%nintf=1
                                        allocate(trans_bt(jtotv)%listf(1),trans_bt(jtotv)%rintf(1))
                                        trans_bt(jtotv)%listf(1)=itotv
                                        trans_bt(jtotv)%rintf(1)=1.
                                    else   !!!20161112
                                        trans_bt(jtotv)%nintf=nintf
                                        allocate(trans_bt(jtotv)%listf(nintf),trans_bt(jtotv)%rintf(nintf))
                                        trans_bt(jtotv)%listf=trans_bt(itotv)%listf
                                        trans_bt(jtotv)%rintf=trans_bt(itotv)%rintf
                                    endif  !!!20161112
                                end do
                            endif  !!20161112
                        endif   !tcl
                    end do
                end do
            end do
        end do


        !write(7,*)'nintf'
        !do itotv=1,ntotvbt
        !write(7,*)'itotv=',itotv,'nintf=',trans_bt(itotv)%nintf
        !if(trans_bt(itotv)%nintf/=0)write(7,*)'listf=',trans_bt(itotv)%listf
        !end do


        if (allocated(iffix_bt))deallocate(iffix_bt)
        allocate(iffix_bt(ntotvbt))
        iffix_bt=1

        do igapb=1,ngapb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                jpoin=gapb(igapb)%nppt(i0)
                istate=gaps(igaps)%state(ipairs)
                if(type_nl==5.or.type_nl==1)istate=gaps(igaps)%state0(ipairs)

                !write(7,*)'igapb=',igapb,'i0=',i0,'jpoin=',jpoin,'ipairs=',ipairs,'state=',gaps(igaps)%state(ipairs)

                if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904
                    !state=0 ,open;=1, close,2,slide,3,softening  !20120821
                    iffix_bt(nodfnbt(1:kkdimn,jpoin))=0
                elseif (gaps(igaps)%frict_less==1.or.(istate==2.and.xlwsol==0))then  !tcl
                    iffix_bt(nodfnbt(ndimn,jpoin))=0
                    iffix_bt(nodfnbt(1:ndimn-1,jpoin))=1
                endif     !tcl
                !write(7,*)'iffix_bt=',iffix_bt(nodfnbt(1:ndimn,jpoin)),'nodfnbt(1:ndimn,jpoin)=',nodfnbt(1:ndimn,jpoin)
                if(gaps(igaps)%pair_process(ipairs)==0)iffix_bt(nodfnbt(1:ndimn,jpoin))=1  !20200331
            end do
        end do

        !  write(7,*)'iffix_bt'
        !do itotv=1,ntotvbt
        !write(7,*)itotv,iffix_bt(itotv)
        !end do



        do igapb=1,ngapb
            if(gapb(igapb)%nrdof==0) cycle
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            do idimn=1,gapb(igapb)%nrdof  !tcl
                if(gapb(igapb)%rldofs(idimn)==0) cycle
                iffix_bt(gapb(igapb)%rldofs(idimn))=0
            end do
        end do

        !end fzx
        if (allocated(totveq_bt))deallocate(totveq_bt)
        allocate(totveq_bt(ntotvbt))
        totveq_bt=0
        do itotv=1,ntotvbt
            if  (iffix_bt(itotv)==0) then
                if  (trans_bt(itotv)%nintf==0)then
                    totveq_bt(itotv)=1
                else
                    if (any(trans_bt(itotv)%listf==itotv))totveq_bt(itotv)=1

                endif
            endif
        end do


        ! write(7,*)'totveq'
        !do itotv=1,ntotvbt
        !write(7,*)'itotv=',itotv,'totveq=',totveq_bt(itotv)
        !end do


        neq_bt=0
        do itotv=1,ntotvbt
            if(totveq_bt(itotv)==1)then
                neq_bt=neq_bt+1
                totveq_bt(itotv)=neq_bt
                !   if(neq_bt==1) &
                !write(7,*)'itotv=',itotv,'neq_bt=',neq_bt
            endif
        end do
        print *,'neq_bt=',neq_bt


        if (allocated(iseq_bt))deallocate(iseq_bt)
        if(neq_bt/=0)then
            allocate(iseq_bt(neq_bt))
            iseq_bt=0
        endif
        !!int2000
        do igapb=1,ngapb
            nevab=gapb(igapb)%ntotv_bt
            do ievab=1,nevab
                nintf=trans_bt(gapb(igapb)%ldofs(ievab))%nintf
                do jevab=1,nevab
                    njntf=trans_bt(gapb(igapb)%ldofs(jevab))%nintf

                    if  (nintf==0.and.njntf==0) then !!1
                        ieq=totveq_bt(gapb(igapb)%ldofs(ievab))
                        jeq=totveq_bt(gapb(igapb)%ldofs(jevab))
                        if  (ieq/=0.and.jeq/=0) then
                            dijeq=ieq-jeq
                            if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                        endif
                    else if(nintf/=0.and.njntf==0)then  !!2
                        do iintf=1,nintf
                            ieq=totveq_bt(trans_bt(gapb(igapb)%ldofs(ievab))%listf(iintf))
                            jeq=totveq_bt(gapb(igapb)%ldofs(jevab))
                            if  (ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                            endif
                        end do
                    else if(nintf==0.and.njntf/=0)then  !!3
                        ieq=totveq_bt(gapb(igapb)%ldofs(ievab))
                        do jintf=1,njntf
                            jeq=totveq_bt(trans_bt(gapb(igapb)%ldofs(jevab))%listf(jintf))
                            if  (ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                            endif
                        end do
                    else if(nintf/=0.and.njntf/=0)then !!4
                        do iintf=1,nintf
                            ieq=totveq_bt(trans_bt(gapb(igapb)%ldofs(ievab))%listf(iintf))
                            do jintf=1,njntf
                                jeq=totveq_bt(trans_bt(gapb(igapb)%ldofs(jevab))%listf(jintf))
                                if  (ieq/=0.and.jeq/=0) then
                                    dijeq=ieq-jeq
                                    if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                                endif
                            end do
                        end do
                    endif
                end do
            end do
        end do
        !!int2000

        print *,'neq_bt=',neq_bt
        if (neq_bt==0) return
        Max_band=0
        Iseq_bt(1)=1
        DO Ieq=2,Neq_bt
            if  (Max_band<Iseq_bt(Ieq))then
                Max_band=Iseq_bt(Ieq)
            endif
            Iseq_bt(Ieq)=Iseq_bt(Ieq)+Iseq_bt(Ieq-1)+1
        end do
        Max_band=Max_band+1
        Stiff_length=Iseq_bt(neq_bt)
        write(chkunit,*)'No. of equations        =',neq_bt
        write(chkunit,*)'Max half band width     =',Max_band
        write(chkunit,*)'length half stiff matrix=',Stiff_length
        if (allocated(global_stiff_bt))deallocate(global_stiff_bt)
        if (allocated(rvector_bt))    deallocate(rvector_bt)
        allocate(global_stiff_bt(Stiff_length))
        global_stiff_bt=0.0
        if(nonsbt==1)then
            if (allocated(global_stiff2_bt))deallocate(global_stiff2_bt)
            allocate(global_stiff2_bt(Stiff_length))
            global_stiff2_bt=0.0
        endif


    case ('FACTORIZE')
        if(nonsbt==0) &
            call skfacs_bt(global_stiff_bt,iseq_bt,ylost,0)
        if(nonsbt==1) &
            call skfaca_bt(global_stiff_bt,global_stiff2_bt,iseq_bt,0)

    case ('SOLVE')


        if(neq_bt/=0)then
            if (nonsbt==0)call sksols_bt(global_stiff_bt,rvector_bt,iseq_bt)
            if (nonsbt==1)call sksola_bt(global_stiff_bt,rvector_bt,global_stiff2_bt,iseq_bt)
        endif

        allocate(resultm(ntotvbt))
        resultm=0.
        do itotv=1,ntotvbt !npbt*ndimn
            nintf=trans_bt(itotv)%nintf
            if  (iffix_bt(itotv)==0.and.nintf==0) then
                resultm(itotv)=rvector_bt(totveq_bt(itotv))
            elseif(nintf/=0) then
                listf=>trans_bt(itotv)%listf
                rintf=>trans_bt(itotv)%rintf
                do jtotv=1,nintf
                    njntf=trans_bt(listf(jtotv))%nintf
                    if(njntf==0)then
                        if (totveq_bt(listf(jtotv))>0)resultm(itotv)=resultm(itotv)+rvector_bt(totveq_bt(listf(jtotv)))*rintf(jtotv)
                    else
                        do k1=1,njntf
                            if (totveq_bt(trans_bt(listf(jtotv))%listf(k1))>0)resultm(itotv)=resultm(itotv)+   &
                                rvector_bt(totveq_bt(trans_bt(listf(jtotv))%listf(k1)))*trans_bt(listf(jtotv))%rintf(k1)
                        end do
                    endif
                enddo
                nullify(listf,rintf)
            endif
        end do


    end select
    end  subroutine profile_ctt

    !!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine pardiso_ctt
    integer(ink) migcg,jblks,igroup,ielgroup,ielem,nnode,inode,ipoin,jnode,jpoin,ic,iband,nthis,ithis, &
        ipm,lband,jband,icdofn,itotv,ieq,jeq,jcdofn,jtotv,sstore_bt,itwksp,aelemf,aelems,ipea1,ipea2,jgroup, &
        nintf,njntf,iintf,jintf,nevab,ievab,nevabt,nbandi,nbandx,nbandy,ii,icaloctd,  &
        isdefault,ncpu,reducing_order,PreCGS,permutation,maxiter,out_of_core,eps_pivot,iparm11,iparm13
    integer(ink) ntotve    !2017/03/19
    integer(ink),allocatable::nbande(:),ldofe(:),ltotve(:)    !2017/03/19
    integer(ink),allocatable::mbandi(:),mbandx(:)
    !real   (irk),allocatable::resultm(:)
    integer(ink),pointer::ldofs(:),iseq0_bt(:)
    integer(ink),pointer::listf(:)
    real   (irk),pointer::rintf(:)


    Select Case ( Operation)

    Case ('SET')
        ncpu=4
        iparm_ctt = 0
        iparm_ctt(1) = 1 ! no solver default
        iparm_ctt(2) = 2 ! fill-in reordering from METIS
        iparm_ctt(3) = ncpu ! not used in MKL PARDISO
        iparm_ctt(4) = 0 ! no iterative-direct algorithm
        iparm_ctt(5) = 0 ! no user fill-in reducing permutation
        iparm_ctt(6) = 0 ! =0 solution on the first n components of x
        iparm_ctt(7) = 0 ! not in use
        iparm_ctt(8) = 0 ! numbers of iterative refinement steps
        iparm_ctt(9) = 0 ! not in use
        iparm_ctt(10) = 13 ! perturb the pivot elements with 1E-13
        iparm_ctt(11) = 1 ! use nonsymmetric permutation and scaling MPS
        iparm_ctt(12) = 0 ! not in use
        iparm_ctt(13) = 0 ! maximum weighted matching algorithm is switched-off
        iparm_ctt(14) = 0 ! Output: number of perturbed pivots
        iparm_ctt(15) = 0 ! not in use
        iparm_ctt(16) = 0 ! not in use
        iparm_ctt(17) = 0 ! not in use
        iparm_ctt(18) = -1 ! Output: number of nonzeros in the factor LU
        iparm_ctt(19) = -1 ! Output: Mflops for LU factorization
        iparm_ctt(20) = 0 ! Output: Numbers of CG Iterations
        error_ctt = 0 ! initialize error flag
        msglvl_ctt = 0 ! no statistical information
        mtype_ctt = -2 ! symmetric, indefinite
        mnum_ctt = 1
        maxfct_ctt = 1

        !!!!!!!!!!!!!!!!!!!!
        if (allocated(trans_bt))deallocate(trans_bt)
        allocate(trans_bt(ntotvbt))
        trans_bt(:)%nintf=0


        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        print *,'a11'
        iix=0
        do igapb=1,ngapb
            do jgapb=igapb,ngapb
                do i0=1,gapb(igapb)%npgblock
                    k1=1
                    if(igapb==jgapb)k1=i0+1
                    do j0=k1,gapb(jgapb)%npgblock

                        if(block_stab==1.or.contactpe==1)then  !2015/8
                            i1=gapb(igapb)%nodegblock(i0)
                            i2=gapb(jgapb)%nodegblock(j0)
                            if(i1==i2)cycle
                        endif  !2015/8

                        ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                        igaps=gapb(igapb)%nodegblock_igaps(i0)
                        istate=gaps(igaps)%state(ipairs)
                        if(type_nl==5.or.type_nl==1)istate=gaps(igaps)%state0(ipairs)

                        jpairs=gapb(jgapb)%nodegblock_ipairs(j0)
                        jgaps=gapb(jgapb)%nodegblock_igaps(j0)

                        if(gaps(igaps)%pair_process(ipairs)==0)cycle !20200331
                        if(gaps(jgaps)%pair_process(jpairs)==0)cycle !20200331
                        if((ipairs/=jpairs).or.(igaps/=jgaps))cycle
                        iix=iix+1
                        if  (istate/=0) then  !tcl

                            if(istate==1.or.istate>=4.or.    &
                                ((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904

                                jpoin1=gapb(igapb)%nppt(i0)
                                jpoin2=gapb(jgapb)%nppt(j0)
                                kdimn=1
                                if(gaps(igaps)%frict_less==1)kdimn=ndimn

                                do idimn=1,ndimn !(ndimn-1)*3*2 !ndimn !fzx 没有必要
                                    itotv=nodfnbt(idimn,jpoin1)
                                    jtotv=nodfnbt(idimn,jpoin2)
                                    if(itotv*jtotv==0)cycle !fzx
                                    nintf=trans_bt(jtotv)%nintf
                                    if(nintf/=0)cycle
                                    nintf=trans_bt(itotv)%nintf
                                    if(nintf==0)then
                                        trans_bt(jtotv)%nintf=1
                                        allocate(trans_bt(jtotv)%listf(1),trans_bt(jtotv)%rintf(1))
                                        trans_bt(jtotv)%listf(1)=itotv
                                        trans_bt(jtotv)%rintf(1)=1.
                                    else   !!20120907
                                        trans_bt(jtotv)%nintf=nintf
                                        allocate(trans_bt(jtotv)%listf(nintf),trans_bt(jtotv)%rintf(nintf))
                                        trans_bt(jtotv)%listf=trans_bt(itotv)%listf
                                        trans_bt(jtotv)%rintf=trans_bt(itotv)%rintf
                                    endif  !!20120907
                                end do
                            endif  !tcl 20120821
                        endif   !tcl
                    end do
                end do
            end do
        end do


        if (allocated(iffix_bt))deallocate(iffix_bt)
        allocate(iffix_bt(ntotvbt))
        iffix_bt=1

        do igapb=1,ngapb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                istate=gaps(igaps)%state(ipairs)
                if(type_nl==5.or.type_nl==1)istate=gaps(igaps)%state0(ipairs)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                jpoin=gapb(igapb)%nppt(i0)

                if(istate==1.or.istate>=4.or.    &
                    ((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904
                    !state=0 ,open;=1, close,2,slide,3,softening  !20120821
                    iffix_bt(nodfnbt(1:ndimn,jpoin))=0
                    if (gaps(igaps)%frict_less==1.or.(istate==2.and.xlwsol==0))then  !tcl
                        iffix_bt(nodfnbt(1:ndimn-1,jpoin))=1
                    endif
                endif     !tcl
                if(gaps(igaps)%pair_process(ipairs)==0)iffix_bt(nodfnbt(1:ndimn,jpoin))=1 !20200331
            end do
        end do

        do igapb=1,ngapb
            if(gapb(igapb)%nrdof==0) cycle
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            do idimn=1,gapb(igapb)%nrdof  !tcl
                if(gapb(igapb)%rldofs(idimn)==0) cycle
                iffix_bt(gapb(igapb)%rldofs(idimn))=0
            end do
        end do

        !end fzx
        if (allocated(totveq_bt))deallocate(totveq_bt)
        allocate(totveq_bt(ntotvbt))
        totveq_bt=0
        do itotv=1,ntotvbt
            if  (iffix_bt(itotv)==0) then
                if  (trans_bt(itotv)%nintf==0)then
                    totveq_bt(itotv)=1
                else
                    if (any(trans_bt(itotv)%listf==itotv))totveq_bt(itotv)=1

                endif
            endif
        end do

        neq_bt=0
        do itotv=1,ntotvbt
            if(totveq_bt(itotv)==1)then
                neq_bt=neq_bt+1
                totveq_bt(itotv)=neq_bt
                !	write(7,*)'itotv=',itotv,'neq_bt=',neq_bt
            endif
        end do

        if (allocated(ltotve))deallocate(ltotve)         !2017/03/19
        allocate(ltotve(neq_bt))  !2017/03/19

        print *,'neq_bt=',neq_bt


        if (allocated(iseq_bt))deallocate(iseq_bt)
        if(neq_bt/=0)then
            allocate(iseq_bt(neq_bt+1))  !!profile--neq_bt,pardiso--neq_bt+1
            iseq_bt=0

            allocate(bandinf_bt(neq_bt))
            bandinf_bt(:)%nband=0
            bandinf_bt(:)%icaloctd=0
        endif
        !!!!!
        do igapb=1,ngapb
            nevab=gapb(igapb)%ntotv_bt
            ldofs=>gapb(igapb)%ldofs
            ntotve=0
            do ievab=1,nevab
                itotv=ldofs(ievab)
                nintf=trans_bt(itotv)%nintf

                if(nintf==0)then
                    ieq=totveq_bt(itotv)
                    if(ieq==0)cycle
                    ntotve=ntotve+1
                    ltotve(ntotve)=ieq
                elseif(nintf/=0)then
                    do iintf=1,nintf
                        jtotv=trans_bt(itotv)%listf(iintf)
                        jeq=totveq_bt(jtotv)
                        if(jeq==0)cycle
                        ntotve=ntotve+1
                        ltotve(ntotve)=jeq
                    end do
                endif
            end do
            do itotv=1,ntotve
                ieq=ltotve(itotv)
                do jtotv=itotv+1,ntotve
                    jeq=ltotve(jtotv)
                    if(ieq==jeq)ltotve(jtotv)=0
                enddo
            enddo
            nevabt=0
            do itotv=1,ntotve
                if(ltotve(itotv)/=0)nevabt=nevabt+1
            enddo
            allocate(ldofe(nevabt))
            nevabt=0
            do itotv=1,ntotve
                if(ltotve(itotv)/=0)then
                    nevabt=nevabt+1
                    ldofe(nevabt)=ltotve(itotv)
                endif
            enddo
            do inode=1,nevabt
                itotv=ldofe(inode)

                nbandi=0
                allocate(mbandi(nevabt))

                nbandx=bandinf_bt(itotv)%nband
                if(nbandx/=0) then
                    allocate(mbandx(nbandx))
                    mbandx=bandinf_bt(itotv)%mband
                endif

                do jnode=1,nevabt
                    jtotv=ldofe(jnode)
                    if(itotv>jtotv)cycle   !up triangle
                    do ii=1,nbandx
                        if(mbandx(ii)==jtotv) goto 10
                    end do
                    nbandi=nbandi+1
                    mbandi(nbandi)=jtotv
10                  continue
                enddo !jnode

                if(nbandi/=0)then
                    nbandy=nbandx+nbandi
                    bandinf_bt(itotv)%nband=nbandy
                    if(nbandx/=0)deallocate(bandinf_bt(itotv)%mband)
                    allocate(bandinf_bt(itotv)%mband(nbandy))
                    bandinf_bt(itotv)%icaloctd=1

                    if(nbandx/=0)then
                        bandinf_bt(itotv)%mband(1:nbandx)=mbandx
                    endif

                    bandinf_bt(itotv)%mband(nbandx+1:nbandy)=mbandi(1:nbandi)
                endif
                if(nbandx/=0)deallocate(mbandx)


                deallocate(mbandi)
            enddo !inode

            nullify(ldofs)
            deallocate(ldofe)

        end do !igap

        !!!!!!!!!!!!!!
        sstore_bt=0
        do ieq=1,neq_bt
            do iband=1,bandinf_bt(ieq)%nband
                jeq=bandinf_bt(ieq)%mband(iband)
                if(ieq<=jeq)then
                    sstore_bt=sstore_bt+1  !!up trigonal(for symetric)
                    iseq_bt(ieq)=iseq_bt(ieq)+1
                endif
            enddo !iband
        enddo

        write(chkunit,*)'单个方程中最大非零元素个数',maxval(Iseq_bt)
        allocate(iseq0_bt(neq_bt))
        iseq0_bt(1:neq_bt)=iseq_bt(1:neq_bt)
        Iseq_bt(1)=1
        DO  Ieq=2,Neq_bt
            Iseq_bt(Ieq)=Iseq_bt(Ieq-1)+iseq0_bt(ieq-1)
        end do
        Iseq_bt(1)=1
        Iseq_bt(neq_bt+1)=Iseq_bt(neq_bt)+1
        deallocate(iseq0_bt)

        write(chkunit,*)'Neq_bt=',neq_bt,'      Iseq_bt(neq_bt)=',Iseq_bt(neq_bt)
        write(chkunit,*)'storage of PARDISO, sstore_bt=',sstore_bt
        write(chkunit,*)'                                            '
        if(allocated(global_stiff_bt))deallocate(global_stiff_bt)
        if(allocated(nndex_bt))        deallocate(nndex_bt)
        if(allocated(rvector_bt))      deallocate(rvector_bt)
        allocate(global_stiff_bt(sstore_bt),nndex_bt(sstore_bt),rvector_bt(neq_bt))
        global_stiff_bt=0.0 ; nndex_bt=0 ; rvector_bt=0.

        if(nonsbt==1)then
            if (allocated(global_stiff2_bt))deallocate(global_stiff2_bt)
            allocate(global_stiff2_bt(Stiff_length))
            global_stiff2_bt=0.0
        endif

        sstore_bt=0
        do ieq=1,neq_bt
            do iband=1,bandinf_bt(ieq)%nband
                jeq=bandinf_bt(ieq)%mband(iband)
                if(ieq<=jeq)then
                    sstore_bt=sstore_bt+1  !!low trigonal(for symetric)
                    nndex_bt(sstore_bt)=jeq
                endif
            enddo !iband
        enddo

        do ieq=1,neq_bt
            icaloctd=bandinf_bt(ieq)%icaloctd
            if(icaloctd==1)deallocate(bandinf_bt(ieq)%mband)
        end do
        deallocate(bandinf_bt)

        print *,'a12'

    case ('FACTORIZE')
        print *,'a13'
        phase_pardiso_ctt = -1 ! release internal memory
        CALL pardiso (pt_ctt, maxfct_ctt, mnum_ctt, mtype_ctt, phase_pardiso_ctt, neq_bt, ddum, idum, idum,    &
            idum, 1, iparm_ctt, msglvl_ctt, ddum, ddum, error_ctt)

        pt_ctt=0
        phase_pardiso_ctt = 11 ! only reordering and symbolic factorization
        CALL pardiso (pt_ctt, maxfct_ctt, mnum_ctt, mtype_ctt, phase_pardiso_ctt, neq_bt, global_stiff_bt, iseq_bt, nndex_bt,   &
            idum, 1, iparm_ctt, msglvl_ctt, ddum, ddum, error_ctt)
        WRITE(*,*) 'Reordering completed ... '
        IF (error_ctt .NE. 0) THEN
            write(chkunit,*)'系数矩阵重新排序时出错，错误代码:', error_ctt
            write(*,*)'系数矩阵重新排序时出错，错误代码:', error_ctt
            call pardiso_error(error_ctt)
            STOP
        END IF
        WRITE(chkunit,'(a40,i12)') ' Number of nonzeros in factors:',iparm_ctt(18)
        WRITE(chkunit,'(a40,i12)') ' Number of factorization MFLOPS:',iparm_ctt(19)

        ! write(7,*)'global_stiff_bt='
        !      write(7,*)'1',global_stiff_bt(iseq_bt(1))
        !do itotv=2,neq_bt+1
        !    write(7,*)itotv,global_stiff_bt(iseq_bt(itotv-1)+1:iseq_bt(itotv))
        !end do


        phase_pardiso_ctt = 22 ! only factorization

        CALL pardiso (pt_ctt, maxfct_ctt, mnum_ctt, mtype_ctt, phase_pardiso_ctt, neq_bt, global_stiff_bt, iseq_bt, nndex_bt,   &
            idum, 1, iparm_ctt, msglvl_ctt, ddum, ddum, error_ctt)
        WRITE(*,*) 'Factorization completed ... '
        IF (error_ctt .NE. 0) THEN
            WRITE(chkunit,*) '矩阵分解时出错，错误代码: ', error_ctt
            WRITE(*,*) '矩阵分解时出错，错误代码: ', error_ctt
            call pardiso_error(error_ctt)
            STOP
        ENDIF

    case ('SOLVE')

        print *,'a14'

        if(allocated(result_bt))deallocate(result_bt)
        allocate(result_bt(neq_bt))
        result_bt=0.

        phase_pardiso_ctt = 33
        CALL pardiso (pt_ctt, maxfct_ctt, mnum_ctt, mtype_ctt, phase_pardiso_ctt, neq_bt, global_stiff_bt, iseq_bt, nndex_bt,   &
            idum, 1, iparm_ctt, msglvl_ctt, rvector_bt, result_bt, error_ctt)

        IF (error_ctt .NE. 0) THEN
            WRITE(chkunit,*) '前代回代时出错，错误代码: ', error_ctt
            WRITE(*,*) '前代回代时出错，错误代码: ', error_ctt
            call pardiso_error(error_ctt)
            STOP
        ENDIF

        allocate(resultm(ntotvbt))
        resultm=0.
        do itotv=1,ntotvbt !npbt*ndimn
            nintf=trans_bt(itotv)%nintf
            if  (iffix_bt(itotv)==0.and.nintf==0) then
                resultm(itotv)=result_bt(totveq_bt(itotv))
            elseif(nintf/=0) then
                listf=>trans_bt(itotv)%listf
                rintf=>trans_bt(itotv)%rintf
                do jtotv=1,nintf
                    njntf=trans_bt(listf(jtotv))%nintf
                    if(njntf==0)then
                        if (totveq_bt(listf(jtotv))>0)resultm(itotv)=resultm(itotv)+result_bt(totveq_bt(listf(jtotv)))*rintf(jtotv)
                    else
                        do k1=1,njntf
                            if (totveq_bt(trans_bt(listf(jtotv))%listf(k1))>0)resultm(itotv)=resultm(itotv)+   &
                                result_bt(totveq_bt(trans_bt(listf(jtotv))%listf(k1)))*trans_bt(listf(jtotv))%rintf(k1)
                        end do
                    endif
                enddo
                nullify(listf,rintf)
            endif
        end do


    end select
    end  subroutine pardiso_ctt

    SUBROUTINE global_stif_pardiso_ctt(ldofs,estif) !pardiso
    integer(ink) ldofs(:)
    integer(ink) i,j, k,idofn,jdofn, ieq,jeq,nintf,njntf,iintf,jintf
    real   (irk) facti,factj,estif(:,:)

    do i= 1,size(ldofs)
        idofn=ldofs(i)
        nintf=trans_bt(idofn)%nintf
        do j=1,size(ldofs)
            jdofn=ldofs(j)
            njntf=trans_bt(jdofn)%nintf
            !		 print *,'nintf=',nintf,'njntf=',njntf
            if(njntf==0.and.nintf==0) then !!1
                jeq  =totveq_bt(jdofn)
                ieq  =totveq_bt(idofn)
                if(ieq==0.or.jeq==0)cycle
                if(ieq>jeq)cycle

                do k=iseq_bt(ieq),iseq_bt(ieq+1)-1
                    if(jeq==nndex_bt(k))then
                        global_stiff_bt(k)=global_stiff_bt(k)+estif(i,j)
                        exit
                    endif
                enddo
            elseif(njntf/=0.and.nintf==0) then !!2
                ieq  =totveq_bt(idofn)
                if(ieq==0) cycle
                do jintf=1,njntf
                    jeq =totveq_bt(trans_bt(jdofn)%listf(jintf))
                    factj=trans_bt(jdofn)%rintf(jintf)
                    if(jeq==0.or.ieq>jeq) cycle

                    do k=iseq_bt(ieq),iseq_bt(ieq+1)-1
                        if(jeq==nndex_bt(k))then
                            global_stiff_bt(k)=global_stiff_bt(k)+estif(i,j)*factj
                            goto 10
                        endif
                    enddo
10                  continue
                end do
            elseif(njntf==0.and.nintf/=0) then !!3
                jeq  =totveq_bt(jdofn)
                if(jeq==0) cycle
                do iintf=1,nintf
                    ieq =totveq_bt(trans_bt(idofn)%listf(iintf))
                    if(ieq==0.or.ieq>jeq) cycle
                    facti=trans_bt(idofn)%rintf(iintf)

                    do k=iseq_bt(ieq),iseq_bt(ieq+1)-1
                        if(jeq==nndex_bt(k))then
                            global_stiff_bt(k)=global_stiff_bt(k)+estif(i,j)*facti
                            goto 20
                        endif
                    enddo
20                  continue
                end do
            elseif(njntf/=0.and.nintf/=0) then !!4
                do iintf=1,nintf
                    ieq =totveq_bt(trans_bt(idofn)%listf(iintf))
                    if(ieq==0) cycle
                    facti=trans_bt(idofn)%rintf(iintf)
                    do jintf=1,njntf
                        jeq =totveq_bt(trans_bt(jdofn)%listf(jintf))
                        if(jeq==0) cycle
                        factj=trans_bt(jdofn)%rintf(jintf)
                        if(ieq>jeq) cycle

                        do k=iseq_bt(ieq),iseq_bt(ieq+1)-1
                            if(jeq==nndex_bt(k))then
                                global_stiff_bt(k)=global_stiff_bt(k)+estif(i,j)*facti*factj
                                goto 30
                            endif
                        enddo
30                      continue
                    end do
                end do
            endif	!endif elseif(njntf/=0.and.nintf/=0)

        enddo
    enddo
    END SUBROUTINE global_stif_pardiso_ctt

    !!!!!!!!!!!!!!!!!!!!!!!!!!
    end subroutine solve_ctt
    !!!!!!!!!!!!!!!!!!!!


    SUBROUTINE solve_ctt_rigid

    integer(ink) nevab,ieq,jeq,dijeq,ievab,jevab,igapb,igaps,inode,ipoin1,ipoin2,jpoin1, &
        jpoin2,iieq,ij,npgblock,kpoin,max_band,stiff_length,i1,i2,ntotv_bt,     &
        iter_bt,idimn,jconv,itotv,jtotv,ipoin,jpoin,ipairs,npairs,iconv,jter_bt,&
        nintf,njntf,iintf,jintf,colum,rpoin,onetwo,jdimn,nnode,ii,i0,i12,       &
        jgapb,j0,jpairs,jgaps,ij1,ij2,iix,k1,iter_state,kdimn,kkdimn,istate
    real   (irk) ylost,dista,sigman,ft,t1,t2,tt,alfa1,alfa2,sheart,dnorm,tnorm,facti,xi0,&
        sigmanc,gf,et,sig1,wx,w1,w0,coef,fact
    real   (irk),allocatable ::resultm(:),eldis(:),recover_bt(:),rot(:,:), &
        ctfor(:),ctfori1(:),ctfori2(:),ctforl1(:),ctforl2(:),      &
        resultx(:),rdisp(:),disl(:)
    integer(ink),pointer::listf(:),ldofs(:),lnods(:) !fzx
    real   (irk),pointer::rintf(:),dislocal(:),cmatrix(:,:)

    print *,'in ctt_rigid','nonsbt=',nonsbt
    kkdimn=ndimn
    if(block_stab==1)kkdimn=3*(ndimn-1)
    allocate(rdisp((ndimn-1)*3))
    allocate(resultx(ntotvbt),ctfor(ntotv),result(ntotv))
    result=0.

    iter_state=1

    if(miter_state>1)then
        write(7,*)'iter_state=',iter_state
        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            do ipairs=1,npairs
                gaps(igaps)%statei(ipairs)=gaps(igaps)%state(ipairs)
                gaps(igaps)%ctforcei(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
            end do
        end do
    endif


10  continue
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(miter_state>1) &
                gaps(igaps)%statei(ipairs)=gaps(igaps)%state(ipairs)
            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)  !20210221
        end do
    end do

    do igapb=1,ngapb   !tcl 2009/10/11
        if(gapb(igapb)%nrdof==0)cycle
        gapb(igapb)%rdisp_inc=0.
    enddo

    allocate(eldis(kkdimn),dislocal(kkdimn),rot(kkdimn,kkdimn))

    ctfor=0.
    !do igaps=1,ngaps
    !   npairs=gaps(igaps)%npairs
    !   do ipairs=1,npairs
    !      if (gaps(igaps)%state(ipairs)==2.and.iiter==1)gaps(igaps)%state(ipairs)=1	  !!!
    !   end do
    !end do
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    resultx=0.

    fact=1.
    if(type_problem=='F')fact=1./(beeta2*ditime**2)
    do igapb=1,ngapb
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            !i12=gapb(igapb)%nodegblock(i0)
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            coef=1.
            if(ij==1)coef=-1.
            ipoin=gapb(igapb)%nppt(i0)
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)rot(3,3)=1.
                if(ndimn==3)then
                    !rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                    !rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                endif
            endif

            !eldis=coef*result_zero(nodfn(1:3*(ndimn-1),i12))*fact
            !
            !      dislocal=rot.x.eldis   !!1128


            call dislocal_node_to_center(kkdimn,ij,igaps,ipairs,coef,fact,result_zero,result,dislocal,eldis,rot)
            do idimn=1,kkdimn !!1128
                itotv= nodfnbt(idimn,ipoin) !!1128
                resultx(itotv)=resultx(itotv)+dislocal(idimn) !!1128
            end do  !!1128
        end do
    end do



    deallocate(dislocal,eldis,rot)
1   format(2i5,3f15.5)
2   format(4i5,3f15.5)
50  format(i5,3f15.8)
51  format(3i5,3f15.8)

    do igapb=1,ngapb   !tcl 2009/10/11
        if(gapb(igapb)%nrdof==0)cycle
        write(7,*)'igapb=',igapb,'rdisp_inc=',gapb(igapb)%rdisp_inc
    enddo
    !write(7,*)'resultx00=',resultx
    call getardisp_rigid(resultx) !迭代过程中，将刚体位移增量引起的接触面位移增量累加到resultx中
    !write(7,*)'resultx0=',resultx
    call getatf_rigid(resultx,ctfor) !接触力变化引起刚体运动平衡方程右端项变化

    !write(7,*)'resultx=',resultx

    if((istep==inc_step.and.iiter==1).or.icttstif==1)then
        operation='SET'
        if(type_solver_ctt=='PROFILE') &
            call profile_ctt_rigid
        if(neq_bt==0) goto 20

        do igapb=1,ngapb  !assemble the local stiff_matrix for the local region
            ntotv_bt=gapb(igapb)%ntotv_bt
            !write(7,*)'igapb=',igapb,'ntotv_bt=',ntotv_bt,'ldofs=',gapb(igapb)%ldofs
            if(type_solver_ctt=='PROFILE') &
                call global_stif_profile_ctt(ntotv_bt,gapb(igapb)%ldofs,gapb(igapb)%cmatrix)

            !write(7,*)'global_stiff_bt ii='
            !do ieq=1,neq_bt
            !    write(7,*)ieq,global_stiff_bt(iseq_bt(ieq))
            !end do
        end do
55      format(i5,10f12.3)

        !write(7,*)'global_stiff_bt='
        !   do ieq=1,neq_bt
        !       write(7,*)ieq,global_stiff_bt(iseq_bt(ieq))
        !   end do


        do igapb=1,ngapb  !加入块体之间接触点对相对位移柔度系数（用梁单元的柔度矩阵形式）
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                istate=gaps(igaps)%state(ipairs)
                if(istatec==0)istate=gaps(igaps)%state0(ipairs)
                if  (istate==0) cycle
                if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904
                    jpoin=gapb(igapb)%nppt(i0)
                    do idimn=1,kkdimn
                        itotv=nodfnbt(idimn,jpoin)
                        if(itotv==0)cycle !fzx
                        ieq=totveq_bt(itotv) !通过ieq是否为零，保证只将kxyz计入一次
                        do jdimn=1,kkdimn
                            jtotv=nodfnbt(jdimn,jpoin)
                            if(jtotv==0)cycle !fzx
                            jeq=totveq_bt(jtotv) !通过ieq是否为零，保证只将kxyz计入一次
                            if(jeq/=0.and.ieq/=0.and.ieq<=jeq) then
                                colum=iseq_bt(jeq)-jeq+ieq
                                if(istatec==0)then
                                    global_stiff_bt(colum)=global_stiff_bt(colum)+gaps(igaps)%kxyz0(idimn,jdimn,ipairs)*fact
                                    if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+gaps(igaps)%kxyz(jdimn,idimn,ipairs)*fact
                                else
                                    global_stiff_bt(colum)=global_stiff_bt(colum)+gaps(igaps)%kxyz(idimn,jdimn,ipairs)*fact
                                    if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+gaps(igaps)%kxyz(jdimn,idimn,ipairs)*fact
                                endif
                            endif
                        end do
                    end do
                endif
            end do
        end do


        ! write(7,*)'global_stiff_bt='
        !do ieq=1,neq_bt
        !    write(7,*)ieq,global_stiff_bt(iseq_bt(ieq))
        !end do

100     format(i5,48e15.5)

        operation='FACTORIZE'
        if(type_solver_ctt=='PROFILE') &
            call profile_ctt_rigid


    endif

    iter_bt=0
20  allocate(result_bt(ntotvbt))

    allocate(rot(kkdimn,kkdimn))

    if(neq_bt/=0)then
        allocate(rvector_bt(neq_bt))
        rvector_bt=0.
    endif
    result_bt=resultx
    do itotv=1,ntotvbt
        if (totveq_bt(itotv)/=0)then
            rvector_bt(totveq_bt(itotv))=rvector_bt(totveq_bt(itotv))+result_bt(itotv)
        endif
    end do

    !!!!!xx
    do itotv=1,ntotvbt
        nintf=trans_bt(itotv)%nintf
        if(nintf/=0) then
            do iintf=1,nintf
                iieq=totveq_bt(trans_bt(itotv)%listf(iintf))
                if(iieq/=0) then
                    rvector_bt(iieq)=rvector_bt(iieq)+result_bt(itotv)*trans_bt(itotv)%rintf(iintf)
                endif
            end do
        endif
    end do
    !!!!!xx

    !write(7,*)'iter_bt=',iter_bt,'result_bt0=',rvector_bt
    !

    do igapb=1,ngapb   !!!!减去接触弹簧位移增量
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            istate=gaps(igaps)%state(ipairs)
            if(istatec==0)istate=gaps(igaps)%state0(ipairs)
            if  (istate==0) cycle
            if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !201200904
                jpoin=gapb(igapb)%nppt(i0)
                do idimn=1,kkdimn
                    itotv=nodfnbt(idimn,jpoin)

                    if(itotv==0)cycle !fzx
                    ieq=totveq_bt(itotv)
                    if(ieq==0) cycle
                    rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%dxyz(idimn,ipairs)

                    do jdimn=1,kkdimn
                        if(istatec==0)then
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz0(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        else
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        endif
                    end do
                end do
            elseif(istate==2.and.xlwsol==0) then   !20161112
                jpoin=gapb(igapb)%nppt(i0)
                do idimn=ndimn,ndimn
                    itotv=nodfnbt(idimn,jpoin)

                    if(itotv==0)cycle !fzx
                    ieq=totveq_bt(itotv)
                    if(ieq==0) cycle
                    rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%dxyz(idimn,ipairs)  !20210217(!!)
                    do jdimn=ndimn,ndimn
                        if(type_nl==5.or.type_nl==1)then
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz0(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        else
                            rvector_bt(ieq)=rvector_bt(ieq)-fact*gaps(igaps)%kxyz(idimn,jdimn,ipairs)*  &
                                (gaps(igaps)%ctforce(jdimn,ipairs)-gaps(igaps)%ctforce0(jdimn,ipairs))
                        endif
                    end do
                end do
            endif
        end do
    end do

    !write(7,*)'rvecor_bt1='
    !do itotv=1,neq_bt
    !write(7,*)itotv,rvector_bt(itotv)
    !end do

    operation='SOLVE'
    if(type_solver_ctt=='PROFILE') &
        call profile_ctt_rigid
    !write(7,*)'rvector_bt2=',rvector_bt

    !write(7,*)'resultm=',resultm

    do igapb=1,ngapb   !tcl 2009/10/11

        rdisp=0.
        if(gapb(igapb)%nrdof==0)cycle
        do idimn=1,gapb(igapb)%nrdof
            itotv=gapb(igapb)%rldofs(idimn)
            if(itotv==0) cycle
            rdisp(idimn)=resultm(itotv)
        enddo
        write(7,*)'iter_bt=',iter_bt,'rdisp=',rdisp

        gapb(igapb)%rdisp_inc=gapb(igapb)%rdisp_inc+rdisp !fzx !约束点位移增量  !rdisp0+rdisp

        write(7,*)'igapb=',igapb,'rdisp_inc=',gapb(igapb)%rdisp_inc
    enddo

    !end fzx

    allocate(ctfori1(kkdimn),ctfori2(kkdimn),ctforl1(kkdimn),ctforl2(kkdimn))


    ctfor=0.

    !  do igaps=1,ngaps
    !   npairs=gaps(igaps)%npairs
    !   do ipairs=1,npairs
    !       write(7,*)'igaps=',igaps,'ipairs=',ipairs,'ctforce0=',gaps(igaps)%ctforce(:,ipairs)
    !   end do
    !end do


    do igapb=1,ngapb
        npgblock=gapb(igapb)%npgblock
        !write(7,*)'igapb=',igapb,'npgblock=',npgblock
        do i0=1,npgblock
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            ipoin=gapb(igapb)%nppt(i0)
            if(ij==2)cycle
            gaps(igaps)%ctforcei(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)  !2012818
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)then
                    rot(3,3)=1.
                elseif(ndimn==3)then
                    !rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                    !rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                endif
            endif

            ctfori1=0. ; ctfori2=0. ; ctforl1=0. ; ctforl2=0.
            kdimn=1
            do idimn=kkdimn,kdimn,-1
                itotv= nodfnbt(idimn,ipoin)
                !write(7,*)'igapb=',igapb,'i0=',i0,'ip0in=',ipoin,'idimn=',idimn,'itotv=',itotv,'resultm=',resultm(itotv)
                istate=gaps(igaps)%state(ipairs)
                if(istatec==0)istate=gaps(igaps)%state0(ipairs)
                if  (istate==0) cycle
                if(istate==1.or.istate>=4.or.((istate>=2.and.istate<=3).and.xlwsol==1)) then   !20120904
                    gaps(igaps)%ctforce(idimn,ipairs)=gaps(igaps)%ctforce(idimn,ipairs)+resultm(itotv)
                elseif(istate==2.and.xlwsol==0)then
                    if (idimn==ndimn)then
                        gaps(igaps)%ctforce(idimn,ipairs)=gaps(igaps)%ctforce(idimn,ipairs)+resultm(itotv)
                    else
                        if(idimn==1)gaps(igaps)%ctforce(idimn,ipairs)=abs(-gaps(igaps)%ctforce(ndimn,ipairs)*   &
                            gaps(igaps)%frict(ipairs)+gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))*gaps(igaps)%alfa1(ipairs)

                        if (ndimn==3) then
                            if(idimn==2)gaps(igaps)%ctforce(idimn,ipairs)=abs(-gaps(igaps)%ctforce(ndimn,ipairs)*   &
                                gaps(igaps)%frict(ipairs)+gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))*gaps(igaps)%alfa2(ipairs)
                        endif
                    endif
                endif
                ctforl1(idimn)=gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs)
                ctforl2(idimn)=-ctforl1(idimn)
            end do

            ctfori1=transpose(rot).x.ctforl1
            ctfori2=transpose(rot).x.ctforl2
            !       i1=gaps(igaps)%pairnode(1,ipairs)
            !      i2=gaps(igaps)%pairnode(2,ipairs)
            !
            !ctfor(nodfn(1:3*(ndimn-1),i1))=ctfor(nodfn(1:3*(ndimn-1),i1))+ctfori1
            !ctfor(nodfn(1:3*(ndimn-1),i2))=ctfor(nodfn(1:3*(ndimn-1),i2))+ctfori2
            call ctfor_center_to_node(igaps,ipairs,ctfori1,ctfori2,ctfor)

        end do
    end do

    !write(7,*)'ctfor=',ctfor
    !!!!!!!!!!!!!
    dnorm=0
    tnorm=0.
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'ctfor=',gaps(igaps)%ctforce(:,ipairs)
            do idimn=1,kkdimn
                dnorm=dnorm+(gaps(igaps)%ctforcei(idimn,ipairs)-gaps(igaps)%ctforce(idimn,ipairs))**2
                tnorm=tnorm+gaps(igaps)%ctforce(idimn,ipairs)**2
            end do
        end do
    end do
    dnorm=sqrt(dnorm)
    tnorm=sqrt(tnorm)
    jconv=0
    if  (dnorm<tor_bt.and.tnorm<tor_bt)jconv=1

    if  (dnorm>tor_bt.or.tnorm>tor_bt)then
        if  (tnorm<tor_bt)then !>?? fzx
            jconv=1
        else
            if (dnorm/tnorm<tor_bt)jconv=1

        endif
    endif

    !write(7,'(a,i4,3(a,e15.6),a,i4)')'iter_bt=',iter_bt,' dnorm=',dnorm,' tnorm=',tnorm,' jconv=',jconv
    write(7,*)'iter_bt=',iter_bt,' dnorm=',dnorm,' tnorm=',tnorm,' jconv=',jconv

    deallocate(resultm,result_bt,rot,ctfori1,ctfori2,ctforl1,ctforl2)
    if(neq_bt/=0)deallocate(rvector_bt)

    if  (jconv==0.and.iter_bt<miter_bt) then
        iter_bt=iter_bt+1

        rvector=0.
        do itotv=1,ntotv
            if (totveq(itotv)/=0)then
                rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)+tofor(itotv)-stfor(itotv)
            endif
        end do

        do itotv=1,ntotv
            nintf=trans(itotv)%nintf
            if  (nintf/=0) then
                iieq=totveq(itotv)
                if (iieq/=0)rvector(iieq)=0.
                do iintf=1,nintf
                    iieq=totveq(trans(itotv)%listf(iintf))
                    if (iieq/=0)rvector(iieq)=rvector(iieq)+(ctfor(itotv)+tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
                end do
            endif
        end do

        operation='SOLVE'
        call solve

        !!!!!
        !下面这一部分为力的变化导致位移增量引起的接触面位移增量
        allocate(eldis(kkdimn),dislocal(kkdimn),rot(kkdimn,kkdimn))
        resultx=0.
        do igapb=1,ngapb
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                !i12=gapb(igapb)%nodegblock(i0)
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                coef=1.
                if(ij==1)coef=-1.
                ipoin=gapb(igapb)%nppt(i0)
                rot=0.
                rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)
                if(block_stab==1)then
                    if(ndimn==2)rot(3,3)=1.
                    if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                endif
                !eldis=coef*result_zero(nodfn(1:3*(ndimn-1),i12))*fact
                !         dislocal=rot.x.eldis !fzx  tcl

                call dislocal_node_to_center(kkdimn,ij,igaps,ipairs,coef,fact,result_zero,result,dislocal,eldis,rot)

                do idimn=1,kkdimn
                    itotv= nodfnbt(idimn,ipoin)
                    resultx(itotv)=resultx(itotv)+dislocal(idimn)  ! 总位移量
                end do
            end do
        end do
        !write(7,*)'resultx10=',resultx

        deallocate(dislocal,eldis,rot)
        !!!!!!
        call getardisp_rigid(resultx) !迭代过程中，将刚体位移增量引起的接触面位移增量累加到resultx中
        !write(7,*)'resultx11=',resultx
        call getatf_rigid(resultx,ctfor) ! 接触力变化引起刚体运动平衡方程右端项变化
        !write(7,*)'resultx12=',resultx
        goto 20
    endif

    !!!!!!!!!!!!!!!!!!!!
    !!!&&&&&&&&&
    !!下一部分是修改接触单元的相对变形
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            gaps(igaps)%dxyz(:,ipairs)=0.
        end do
    end do

    do igapb=1,ngapb
        if(block_appear_process(igapb,iblks)==0)cycle  !20200331
        npgblock=gapb(igapb)%npgblock
        do i0=1,npgblock
            !      i12=gapb(igapb)%nodegblock(i0)   !2015/8
            ipairs=gapb(igapb)%nodegblock_ipairs(i0)
            igaps=gapb(igapb)%nodegblock_igaps(i0)
            ij=gapb(igapb)%nodegblock_onetwo(i0)
            ipoin=gapb(igapb)%nppt(i0)
            istate=gaps(igaps)%state(ipairs)
            if(istatec==0)istate=gaps(igaps)%state0(ipairs)

            do idimn=1,kkdimn
                dista=resultx(nodfnbt(idimn,ipoin))  !ltc
                if(type_problem=='F')dista=dista*beeta2*ditime**2
                if(istatec==0)then
                    gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                else
                    if(istate==0)then
                        gaps(igaps)%gap (idimn,ipairs)=gaps(igaps)%gap (idimn,ipairs)+dista   !得到的是总间隙量
                    elseif(istate==1.or.(istate==2.and.xlwsol==1))then  !20120821
                        gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                    elseif(idimn==ndimn.and.istate==2.and.xlwsol==0)then  !20161112
                        gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                    elseif(istate>=3)then
                        gaps(igaps)%dxyz(idimn,ipairs)=gaps(igaps)%dxyz(idimn,ipairs)+dista   !得到的是总相对位移量
                    endif
                endif
            enddo

            !   endif
        end do
    end do

    !!!&&&&&&&&&&&&
    if(istatec==1) &
        call state_and_stiff_rigid_2021


    ctfor=0.
    allocate(ctfori1(kkdimn),ctfori2(kkdimn),ctforl1(kkdimn),ctforl2(kkdimn),rot(kkdimn,kkdimn))

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        kdimn=1
        ctfori1=0. ; ctfori2=0. ; ctforl1=0. ; ctforl2=0.
        do ipairs=1,npairs
            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)

            if(block_stab==1)then
                if(ndimn==2)then
                    rot(3,3)=1.
                elseif(ndimn==3)then
                    !rot(1:3,4:6)= rot(1:ndimn,1:ndimn)
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                    !rot(4:6,1:3)= rot(1:ndimn,1:ndimn)
                endif
            endif


            do idimn=kdimn,kkdimn
                ctforl1(idimn)=gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs)
                ctforl2(idimn)=-ctforl1(idimn)

            end do
            ctfori1=transpose(rot).x.ctforl1
            ctfori2=transpose(rot).x.ctforl2

            !
            !i2=gaps(igaps)%pairnode(2,ipairs)
            !i1=gaps(igaps)%pairnode(1,ipairs)
            !      ctfor(nodfn(1:3*(ndimn-1),i1))=ctfor(nodfn(1:3*(ndimn-1),i1))+ctfori1
            !ctfor(nodfn(1:3*(ndimn-1),i2))=ctfor(nodfn(1:3*(ndimn-1),i2))+ctfori2

            call ctfor_center_to_node(igaps,ipairs,ctfori1,ctfori2,ctfor)

            !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'rot=',rot
            !write(7,*)'ctfor1=',ctfor(nodfn(1:3*(ndimn-1),i1))
            !write(7,*)'ctfor2=',ctfor(nodfn(1:3*(ndimn-1),i2))
        end do
    end do
    deallocate(ctfori1,ctfori2,ctforl1,ctforl2,rot)


29  format(i10,3e15.5)

    rvector=0.
    do itotv=1,ntotv
        if (totveq(itotv)/=0)rvector(totveq(itotv))=rvector(totveq(itotv))+ctfor(itotv)+tofor(itotv)-stfor(itotv)
    end do
    do itotv=1,ntotv
        nintf=trans(itotv)%nintf
        if  (nintf/=0) then
            iieq=totveq(itotv)
            if (iieq/=0)rvector(iieq)=0.
            do iintf=1,nintf
                iieq=totveq(trans(itotv)%listf(iintf))
                if (iieq/=0)rvector(iieq)=rvector(iieq)+(ctfor(itotv)+tofor(itotv)-stfor(itotv))*trans(itotv)%rintf(iintf)
            end do
        endif
    end do

    operation='SOLVE'
    call solve

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
            gaps(igaps)%state0(ipairs)=gaps(igaps)%state(ipairs)  !20210217
            gaps(igaps)%damage0(ipairs)=gaps(igaps)%damage(ipairs) !20210217
            gaps(igaps)%ctforcej(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
            gaps(igaps)%ctforce0(:,ipairs)=gaps(igaps)%ctforce(:,ipairs)
        end do
    end do


    if(istatec==1.and.miter_state>1.and.iter_state<miter_state)then
        jconv=0

        !!!!
        !下面这一部分为接触力的变化导致位移增量引起的接触面位移增量
        allocate(eldis(kkdimn),dislocal(kkdimn),rot(kkdimn,kkdimn))
        resultx=0.
        do igapb=1,ngapb
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                !          i12=gapb(igapb)%nodegblock(i0)
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                coef=1.
                if(ij==1)coef=-1.
                ipoin=gapb(igapb)%nppt(i0)

                rot=0.
                rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)
                if(block_stab==1)then
                    if(ndimn==2)rot(3,3)=1.
                    if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                endif

                call dislocal_node_to_center(kkdimn,ij,igaps,ipairs,coef,fact,result_zero,result,dislocal,eldis,rot)
                !位移叠加存在问题，result只计及了接触力增量，但ctforce0在变化。
                do idimn=1,kkdimn
                    itotv= nodfnbt(idimn,ipoin)
                    resultx(itotv)=resultx(itotv)+dislocal(idimn)  ! 总位移量
                end do
            end do
        end do
        do igapb=1,ngapb
            if(block_appear_process(igapb,iblks)==0)cycle  !20200331
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                if(ij==2)cycle
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ipoin=gapb(igapb)%nppt(i0)
                do idimn=ndimn,ndimn   !!!2012704  这里只对法向进行
                    itotv= nodfnbt(idimn,ipoin)
                    resultx(itotv)=resultx(itotv)+gaps(igaps)%gap0(idimn,ipairs)*fact
                    !初始间隙不变，在节点对中的第一节点中的总位移上加上初始间隙
                end do
            end do
        end do
        deallocate(dislocal,eldis,rot)
        tofor=tofor+ctfor  !20210217 这里表示将ctfor转换到tofor里去了
        ctfor=0.
        !
        dnorm=0
        tnorm=0.
        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs
            kdimn=1
            if(gaps(igaps)%frict_less==1)kdimn=ndimn
            do ipairs=1,npairs
                do idimn=kdimn,kkdimn
                    dnorm=dnorm+(gaps(igaps)%ctforcej(idimn,ipairs)-gaps(igaps)%ctforce(idimn,ipairs))**2
                    tnorm=tnorm+gaps(igaps)%ctforce(idimn,ipairs)**2
                end do
            end do
        end do
        dnorm=sqrt(dnorm)
        tnorm=sqrt(tnorm)
        print *,'iter_state=',iter_state,'dnorm=',dnorm,'tnorm=',tnorm,'dnorm/tnorm=',dnorm/tnorm
        jconv=0
        if  (dnorm<tor_bt.and.tnorm<tor_bt)jconv=1

        if  (dnorm>tor_bt.or.tnorm>tor_bt)then
            if  (tnorm<tor_bt) jconv=1
            if (dnorm/tnorm<tor_bt)jconv=1
        endif
        if(jconv==0)then
            iter_bt=0
            iter_state=iter_state+1
            goto 10
        endif

    endif
    !!!!!!!!!!!!!!!!!!!!!!
    deallocate(resultx,result)
    write(7,*)'iter_bt=',iter_bt,'gaps(1)%cohes(1)=',gaps(1)%cohes(1)
    write(7,'(5(a,i5))')'iblks=',iblks,' iincs=',iincs,' istep=',istep,' iiter=',iiter,' iter_bt=',iter_bt
    deallocate(ctfor,rdisp) !

    contains

    subroutine profile_ctt_rigid

    Select Case ( Operation)

    Case ('SET')

        !!!!!!!!!!!!!!!!!!!!
        if (allocated(trans_bt))deallocate(trans_bt)
        allocate(trans_bt(ntotvbt))
        trans_bt(:)%nintf=0

        !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

        iix=0
        do igapb=1,ngapb
            do jgapb=igapb,ngapb
                do i0=1,gapb(igapb)%npgblock
                    k1=1
                    if(igapb==jgapb)k1=i0+1
                    do j0=k1,gapb(jgapb)%npgblock
                        if(block_stab==1.or.contactpe==1)then  ! 2015/8
                            i1=gapb(igapb)%nodegblock(i0)
                            i2=gapb(jgapb)%nodegblock(j0)
                            if(i1==i2)cycle
                        endif   ! 2015/8
                        ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                        igaps=gapb(igapb)%nodegblock_igaps(i0)

                        jpairs=gapb(jgapb)%nodegblock_ipairs(j0)
                        jgaps=gapb(jgapb)%nodegblock_igaps(j0)

                        if((ipairs/=jpairs).or.(igaps/=jgaps))cycle
                        iix=iix+1
                        if  (gaps(igaps)%state(ipairs)/=0) then  !tcl

                            if(gaps(igaps)%state(ipairs)==1.or.(gaps(igaps)%state(ipairs)>=2.and.xlwsol==1)) then   !201200904

                                jpoin1=gapb(igapb)%nppt(i0)
                                jpoin2=gapb(jgapb)%nppt(j0)
                                kdimn=1
                                if(gaps(igaps)%frict_less==1)kdimn=ndimn

                                do idimn=kdimn,kkdimn
                                    itotv=nodfnbt(idimn,jpoin1)
                                    jtotv=nodfnbt(idimn,jpoin2)
                                    if(itotv*jtotv==0)cycle !fzx
                                    nintf=trans_bt(jtotv)%nintf
                                    if(nintf/=0)cycle
                                    nintf=trans_bt(itotv)%nintf
                                    if(nintf==0)then
                                        trans_bt(jtotv)%nintf=1
                                        allocate(trans_bt(jtotv)%listf(1),trans_bt(jtotv)%rintf(1))
                                        trans_bt(jtotv)%listf(1)=itotv
                                        trans_bt(jtotv)%rintf(1)=1.
                                    else   !!20120907
                                        trans_bt(jtotv)%nintf=nintf
                                        allocate(trans_bt(jtotv)%listf(nintf),trans_bt(jtotv)%rintf(nintf))
                                        trans_bt(jtotv)%listf=trans_bt(itotv)%listf
                                        trans_bt(jtotv)%rintf=trans_bt(itotv)%rintf
                                    endif  !!20120907
                                end do
                            endif  !tcl 20120821
                        endif   !tcl
                    end do
                end do
            end do
        end do


        if (allocated(iffix_bt))deallocate(iffix_bt)
        allocate(iffix_bt(ntotvbt))
        iffix_bt=1

        do igapb=1,ngapb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                ipairs=gapb(igapb)%nodegblock_ipairs(i0)
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                jpoin=gapb(igapb)%nppt(i0)

                if(gaps(igaps)%state(ipairs)==1.or.(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)) then !state=1, close,2,slide  !20120821
                    iffix_bt(nodfnbt(1:kkdimn,jpoin))=0
                elseif (gaps(igaps)%state(ipairs)==2.and.xlwsol==0)then
                    iffix_bt(nodfnbt(ndimn,jpoin))=0
                    iffix_bt(nodfnbt(1:ndimn-1,jpoin))=1
                endif     !tcl

            end do
        end do

        do igapb=1,ngapb
            if(gapb(igapb)%nrdof==0) cycle
            do idimn=1,gapb(igapb)%nrdof  !tcl
                if(gapb(igapb)%rldofs(idimn)==0) cycle
                iffix_bt(gapb(igapb)%rldofs(idimn))=0
            end do
        end do


        if (allocated(totveq_bt))deallocate(totveq_bt)
        allocate(totveq_bt(ntotvbt))
        totveq_bt=0
        do itotv=1,ntotvbt
            if  (iffix_bt(itotv)==0) then
                if  (trans_bt(itotv)%nintf==0)then
                    totveq_bt(itotv)=1
                else
                    if (any(trans_bt(itotv)%listf==itotv))totveq_bt(itotv)=1

                endif
            endif
        end do


        neq_bt=0
        do itotv=1,ntotvbt
            if(totveq_bt(itotv)==1)then
                neq_bt=neq_bt+1
                totveq_bt(itotv)=neq_bt
            endif
        end do
        print *,'neq_bt=',neq_bt

        if (allocated(iseq_bt))deallocate(iseq_bt)
        if(neq_bt/=0)then
            allocate(iseq_bt(neq_bt))
            iseq_bt=0
        endif
        !!int2000
        do igapb=1,ngapb
            nevab=gapb(igapb)%ntotv_bt
            do ievab=1,nevab
                nintf=trans_bt(gapb(igapb)%ldofs(ievab))%nintf
                do jevab=1,nevab
                    njntf=trans_bt(gapb(igapb)%ldofs(jevab))%nintf

                    if  (nintf==0.and.njntf==0) then !!1
                        ieq=totveq_bt(gapb(igapb)%ldofs(ievab))
                        jeq=totveq_bt(gapb(igapb)%ldofs(jevab))
                        if  (ieq/=0.and.jeq/=0) then
                            dijeq=ieq-jeq
                            if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                        endif
                    else if(nintf/=0.and.njntf==0)then  !!2
                        do iintf=1,nintf
                            ieq=totveq_bt(trans_bt(gapb(igapb)%ldofs(ievab))%listf(iintf))
                            jeq=totveq_bt(gapb(igapb)%ldofs(jevab))
                            if  (ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                            endif
                        end do
                    else if(nintf==0.and.njntf/=0)then  !!3
                        ieq=totveq_bt(gapb(igapb)%ldofs(ievab))
                        do jintf=1,njntf
                            jeq=totveq_bt(trans_bt(gapb(igapb)%ldofs(jevab))%listf(jintf))
                            if  (ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                            endif
                        end do
                    else if(nintf/=0.and.njntf/=0)then !!4
                        do iintf=1,nintf
                            ieq=totveq_bt(trans_bt(gapb(igapb)%ldofs(ievab))%listf(iintf))
                            do jintf=1,njntf
                                jeq=totveq_bt(trans_bt(gapb(igapb)%ldofs(jevab))%listf(jintf))
                                if  (ieq/=0.and.jeq/=0) then
                                    dijeq=ieq-jeq
                                    if (dijeq.gt.iseq_bt(ieq))iseq_bt(ieq)=dijeq  !!low trigonal(for symetric)
                                endif
                            end do
                        end do
                    endif
                end do
            end do
        end do
        !!int2000

        print *,'neq_bt=',neq_bt
        if (neq_bt==0) return
        Max_band=0
        Iseq_bt(1)=1
        DO Ieq=2,Neq_bt
            if  (Max_band<Iseq_bt(Ieq))then
                Max_band=Iseq_bt(Ieq)
            endif
            Iseq_bt(Ieq)=Iseq_bt(Ieq)+Iseq_bt(Ieq-1)+1
        end do
        Max_band=Max_band+1
        Stiff_length=Iseq_bt(neq_bt)
        write(chkunit,*)'No. of equations        =',neq_bt
        write(chkunit,*)'Max half band width     =',Max_band
        write(chkunit,*)'length half stiff matrix=',Stiff_length
        if (allocated(global_stiff_bt))deallocate(global_stiff_bt)
        if (allocated(rvector_bt))    deallocate(rvector_bt)
        allocate(global_stiff_bt(Stiff_length))
        global_stiff_bt=0.0
        if(nonsbt==1)then
            if (allocated(global_stiff2_bt))deallocate(global_stiff2_bt)
            allocate(global_stiff2_bt(Stiff_length))
            global_stiff2_bt=0.0
        endif


    case ('FACTORIZE')
        if(nonsbt==0) &
            call skfacs_bt(global_stiff_bt,iseq_bt,ylost,0)
        if(nonsbt==1) &
            call skfaca_bt(global_stiff_bt,global_stiff2_bt,iseq_bt,0)

    case ('SOLVE')


        if(neq_bt/=0)then
            if (nonsbt==0)call sksols_bt(global_stiff_bt,rvector_bt,iseq_bt)
            if (nonsbt==1)call sksola_bt(global_stiff_bt,rvector_bt,global_stiff2_bt,iseq_bt)
        endif

        allocate(resultm(ntotvbt))
        resultm=0.
        do itotv=1,ntotvbt !npbt*ndimn
            nintf=trans_bt(itotv)%nintf
            if  (iffix_bt(itotv)==0.and.nintf==0) then
                resultm(itotv)=rvector_bt(totveq_bt(itotv))
            elseif(nintf/=0) then
                listf=>trans_bt(itotv)%listf
                rintf=>trans_bt(itotv)%rintf
                do jtotv=1,nintf
                    njntf=trans_bt(listf(jtotv))%nintf
                    if(njntf==0)then
                        if (totveq_bt(listf(jtotv))>0)resultm(itotv)=resultm(itotv)+rvector_bt(totveq_bt(listf(jtotv)))*rintf(jtotv)
                    else
                        do k1=1,njntf
                            if (totveq_bt(trans_bt(listf(jtotv))%listf(k1))>0)resultm(itotv)=resultm(itotv)+   &
                                rvector_bt(totveq_bt(trans_bt(listf(jtotv))%listf(k1)))*trans_bt(listf(jtotv))%rintf(k1)
                        end do
                    endif
                enddo
                nullify(listf,rintf)
            endif
        end do

    end select
    end  subroutine profile_ctt_rigid

    end subroutine solve_ctt_rigid
    !!!!!!!!!!!

    subroutine ctfor_center_to_node(igaps,ipairs,ctfori1,ctfori2,ctfor)
    integer(ink) igaps,ipairs,ij1,ij2,idimn,j0,i1,i2,ijk,nnodei,nnodej
    real(irk) coef1
    real(irk) ctfori1(:),ctfori2(:),ctfor(:)

    nnodei=size(gaps(igaps)%pairnode(:,ipairs))  !2017/02/14
    nnodej=nnodei/2    !2017/02/14
    ! coef1=1.  ! 2015/8
    !if(contactpe==2)coef1=.5/(ndimn-1)
    coef1=1.
    !if(contactpe==2)coef1=.5/(ndimn-1)
    if(contactpe==2)coef1=1./nnodej  !2017/02/14

    ijk=ndimn
    if(block_stab==1)ijk=3*(ndimn-1)


    ij1=1
    ij2=1
    if(contactpe==2)then
        ij1=1
        !ij2=2*(ndimn-1)
        ij2=nnodej !2017/02/14
    endif
    do j0=ij1,ij2
        i1=gaps(igaps)%pairnode(j0,ipairs)
        ctfor(nodfn(1:ijk,i1))=ctfor(nodfn(1:ijk,i1))+ctfori1*coef1
    end do

    ij1=2
    ij2=2
    if(contactpe==2)then
        !ij1=2*(ndimn-1)+1
        !ij2=4*(ndimn-1)
        ij1=nnodej+1 !2017/02/14
        ij2=nnodei   !2017/02/14
    endif
    do j0=ij1,ij2
        i2=gaps(igaps)%pairnode(j0,ipairs)
        ctfor(nodfn(1:ijk,i2))=ctfor(nodfn(1:ijk,i2))+ctfori2*coef1
    end do !j0   2015/8

    end  subroutine ctfor_center_to_node



    subroutine dislocal_node_to_center(kdimn,ij,igaps,ipairs,coef,fact,x1,dx,dislocal,eldis,rot)
    integer(ink) igaps,ipairs,ij1,ij2,j0,i12,ij,kdimn,nnodei,nnodej
    real(irk) coef,coef1,fact
    real(irk) x1(:),dx(:),dislocal(:),eldis(:),rot(:,:)
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

    eldis=0.
    do j0=ij1,ij2
        i12=gaps(igaps)%pairnode(j0,ipairs)

        eldis=eldis+coef1*coef*x1(nodfn(1:kdimn,i12))*fact   !20161206
        !write(7,10)i12,x1(nodfn(1:kdimn,i12)),coef1*coef*x1(nodfn(1:kdimn,i12))*fact
        !write(7,10)i12,dx(nodfn(1:kdimn,i12)),coef1*coef*dx(nodfn(1:kdimn,i12))
        if(block_stab/=1.or.ebody==1) &
            eldis=eldis+coef1*coef*dx(nodfn(1:kdimn,i12))
        dislocal=rot.x.eldis
        !write(7,*)'dislocal=',dislocal
    end do  !j0
10  format(i10,10e15.5)
    end subroutine dislocal_node_to_center

    !!!!!!
    subroutine ctfor_to_tofor(tofor0,toforx)  !ctt2005
    integer(ink) igaps,npairs,ipairs,i1,i2,idimn,ijk,j0,ij1,ij2,nnodei,nnodej
    real(irk) coef1,tofor0(:),toforx(:)
    real(irk),allocatable::ctfori1(:),ctfori2(:),ctforl1(:),ctforl2(:),rot(:,:)

    ijk=ndimn
    if(block_stab==1)ijk=3*(ndimn-1)

    allocate(ctfori1(ijk),ctfori2(ijk),ctforl1(ijk), &
        rot(ijk,ijk),ctforl2(ijk))
    toforx=tofor0

    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(gaps(igaps)%pair_process(ipairs)==0)cycle !zhao 2007.04.16
            nnodei=size(gaps(igaps)%pairnode(:,ipairs))  !2017/02/14
            nnodej=nnodei/2    !2017/02/14

            coef1=1.  ! 2015/8
            if(contactpe==2)coef1=1./nnodej  !2017/02/14

            rot=0.
            rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipairs)
            if(block_stab==1)then
                if(ndimn==2)then
                    rot(3,3)=1.
                elseif(ndimn==3)then
                    rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                endif
            endif
            !
            do idimn=1,ijk
                ctforl1(idimn)=gaps(igaps)%ctforce(idimn,ipairs)
                if(kinit==2)ctforl1(idimn)=ctforl1(idimn)-gaps(igaps)%ctforce_stres0(idimn,ipairs)  !2019/03/19
                ctforl2(idimn)=-ctforl1(idimn)
            end do
            ctfori1=transpose(rot).x.ctforl1
            ctfori2=transpose(rot).x.ctforl2

            if(igaps==3.and.ipairs==11) &
                write(7,*)'igaps=',igaps,'ctfori1=',ctfori1,'ctfori2=',ctfori2



            ij1=1
            ij2=1
            if(contactpe==2)then
                ij1=1
                !ij2=2*(ndimn-1)
                ij2=nnodej   !2017/02/14
            endif
            do j0=ij1,ij2
                i1=gaps(igaps)%pairnode(j0,ipairs)
                toforx(nodfn(1:ijk,i1))=toforx(nodfn(1:ijk,i1))+ctfori1*coef1
            end do

            ij1=2
            ij2=2
            if(contactpe==2)then
                ij1=nnodej+1  !2017/02/14
                ij2=nnodei    !2017/02/14
            endif
            do j0=ij1,ij2
                i2=gaps(igaps)%pairnode(j0,ipairs)
                toforx(nodfn(1:ijk,i2))=toforx(nodfn(1:ijk,i2))+ctfori2*coef1
            end do !j0   2015/8

        end do
    end do
    deallocate(ctfori1,ctfori2,ctforl1,rot,ctforl2)
    end subroutine ctfor_to_tofor  !ctt2005


    subroutine csfor_to_tofor(tofor0,toforx)  !20210328
    integer(ink) i0,i1,nline_g_sc,npairs_sc,inode,ipoin,jdimn,jtotv,nintf,iintf,itotv
    integer(ink),pointer::pairnode_sc(:)
    real(irk) tofor0(:),toforx(:),dtao_sc
    real(irk),pointer::tao_cs(:),rot_sc(:,:)
    real(irk),allocatable::ctfor(:)

    toforx=tofor0
    allocate(ctfor(ntotv))
    ctfor=0.
    do i0=1,nrcsteel
        nline_g_sc=rc_steel(i0)%nline_g_sc


        do i1=1,nline_g_sc
            npairs_sc=rc_steel(i0)%line_g_sc(i1)%npairs_sc
            tao_cs=>rc_steel(i0)%line_g_sc(i1)%tao_cs
            rot_sc=>rc_steel(i0)%line_g_sc(i1)%rot_sc
            pairnode_sc=>rc_steel(i0)%line_g_sc(i1)%pairnode_sc

            do inode=1,npairs_sc
                ipoin=pairnode_sc(inode)
                dtao_sc=-tao_cs(inode)
                do jdimn=1,ndimn
                    jtotv=nodfn(jdimn,ipoin)
                    nintf=trans(jtotv)%nintf
                    if(nintf/=0) then
                        do iintf=1,nintf
                            itotv=trans(jtotv)%listf(iintf)
                            ctfor(itotv)=ctfor(itotv)+dtao_sc*rot_sc(jdimn,inode)*trans(jtotv)%rintf(iintf)
                        end do
                    else
                        ctfor(jtotv)=ctfor(jtotv)+dtao_sc*rot_sc(jdimn,inode)
                    endif
                end do !jdimn
            end do  !inode
            nullify(tao_cs,rot_sc,pairnode_sc)
        end do !i1
    end do !i0

    toforx=toforx+ctfor

    deallocate(ctfor)

    end subroutine csfor_to_tofor  !20210328


    SUBROUTINE stfor_inc_ctfor(resi,stfor_inc)
    character(10)fieldid
    character(30)material
    integer(ink) igroup, nrfields, ifield,  index, order_time,     &
        nnode_f, nevab_f,   ic,            &
        ielgroup, ielem,   ievab,  ikh, anevab,  matno, nstre

    real   (irk)  coef,alfa,beta,lamda,stfor_inc(:),resi(:)
    real   (irk), allocatable::fstif(:,:),eload(:),value(:)
    real   (irk), pointer::fstif0(:,:)
    integer(ink), pointer::ldofs(:)

    stfor_inc=0.
    DO igroup =1,ngroup
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
                                !write(7,*)'ie=',ielem,'value=',value,'coef=',coef,'eload=',eload
                                nullify(fstif0,ldofs)
                            endif
                        end do        !!end do ikh
                    endif
                end do       !!ielgroup
                deallocate(fstif,eload,value)
            end do     !! end do ifield
        end if    !! for do while
    end do     !!  for igroup

    END SUBROUTINE stfor_inc_ctfor


    SUBROUTINE stfor_rigid_accs(stfor_rigid)
    character(10)fieldid
    integer(ink) igroup,index,nnode_f, nevab_f, ic,ielgroup, ielem,ievab,itotv,igapb,idimn,jdimn,ipoin,jpoin,jgapb,kdimn,ikh
    real   (irk)  coef,alfa,beta,xxac,stfor_rigid(:)
    real   (irk), allocatable::fstif(:,:),eload(:),value(:),result_second_rigid(:)
    real   (irk), pointer::fstif0(:,:)
    integer(ink), pointer::ldofs(:)


    kdimn=ndimn
    if(block_stab==1)kdimn=3*(ndimn-1) !2015/11/17
    stfor_rigid=0.
    allocate(result_second_rigid(ntotv))
    result_second_rigid=0.
    do igapb=1,ngapb
        if(gapb(igapb)%nrdof==0)cycle


        !write(7,*)'igapb=',igapb,'rdisp_inc=',gapb(igapb)%rdisp_inc
        do jpoin=1,gapb(igapb)%npblock
            ipoin=gapb(igapb)%nodeblock(jpoin)
            do idimn=1,kdimn  !idimn
                itotv=nodfn(idimn,ipoin)
                if(itotv==0)cycle
                xxac=0.
                do jdimn=1,gapb(igapb)%nrdof
                    xxac=xxac+gapb(igapb)%rdisp_inc(jdimn)*gapb(igapb)%npdisp(idimn,jpoin,jdimn)
                end do
                result_second_rigid(itotv)=xxac
            end do   !idimn
        end do   !jpoin
    end do   !igapb

    !	write(7,*)'result_second_rigid=',result_second_rigid

    do jgapb=1,ngapb
        do igapb=1,gapb(jgapb)%ngroupb
            igroup=gapb(jgapb)%listgroupb(igapb)
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


                        do ikh=1,2
                            if(associated(element(ielem)%field(1)%khandmc(ikh)%fstif)) then

                                if(ikh==1)coef=beeta2*ditime**2+beta*beeta1*ditime          !
                                if(ikh==2)coef=1.0+alfa*beeta1*ditime
                                !coef=1.0+alfa*beeta1*ditime                         !-------------------------------!
                                ldofs=>element(ielem)%field(1)%ldofs_f
                                value=result_second_rigid(ldofs)
                                fstif0=>element(ielem)%field(1)%khandmc(ikh)%fstif
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
                                stfor_rigid(ldofs)=stfor_rigid(ldofs)+eload
                                nullify(fstif0,ldofs)
                            endif
                        end do        !!end do ikh
                    endif
                end do       !!ielgroup
                deallocate(fstif,eload,value)
            end if    !! for do while
        end do     !!  for igroup
    end do
    !	write(7,*)'stfor_rigid=',stfor_rigid

    deallocate(result_second_rigid)

    END SUBROUTINE stfor_rigid_accs
    !!!!!!!!!!
    subroutine state_and_stiff_rigid

    integer(ink) igaps,npairs,ipairs,idimn

    real(irk),pointer::kgdm(:)
    real(irk),allocatable::r(:),sigma(:),kxyz(:,:)
    real(irk)    sigman,ft,Gf,xi0,sigmanc,sig1,w0,w1,wx,wxi,t1,t2,tt,sheart,alfa1,alfa2,k0,wx0,c1,c2, &
        pa,n,Rf,e,miu,f,c,k,i1,alfa  !,gamaw 20230402

    icttstif=0
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if (gaps(igaps)%state(ipairs)==1.or.gaps(igaps)%state(ipairs)==2) then  !

                t1=gaps(igaps)%ctforce(1,ipairs)
                if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                tt=abs(t1)
                if (ndimn==3)tt=sqrt(t1**2+t2**2)
                if(gaps(igaps)%thin_layer/=1)then
                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)
                    !if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)  !new
                    if  (tt>0.95*sheart)then
                        if (gaps(igaps)%state(ipairs)==1)gaps(igaps)%state(ipairs)=2
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)

                    elseif(gaps(igaps)%state(ipairs)==2)then

                        gaps(igaps)%state(ipairs)=1

                        if(gaps(igaps)%state0(ipairs)==1)then
                            gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                            do idimn=1,ndimn
                                if(abs(gaps(igaps)%ctforce(idimn,ipairs))<1.e-5)gaps(igaps)%ctforce(idimn,ipairs)=1.e-5
                            enddo
                            !gaps(igaps)%ft(ipairs)=gaps(igaps)%ft0(ipairs)
                            gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                        endif

                    endif
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(gaps(igaps)%state(ipairs)==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                        if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                    else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup1(1,1)  !柔度系数取大值模拟自由滑动
                        if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup1(2,2)  !柔度系数取大值模拟自由滑动
                    endif
                else  !!!!!thin_layer==1
                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)  !2017/02/14 by Hejinwen
                    !if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)
                    if  (tt>sheart)then
                        gaps(igaps)%state(ipairs)=2
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)
                    elseif(gaps(igaps)%state(ipairs)==2)then
                        gaps(igaps)%state(ipairs)=1
                    endif
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(gaps(igaps)%state(ipairs)==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                        if(ndimn.eq.3) gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                    else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)/(1-gaps(IGAPS)%RF)**2
                        if(ndimn.eq.3)   gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)/(1-gaps(IGAPS)%RF)**2
                    endif

                    icttstif=1   !2017/02/14 by Hejinwen

                    !     allocate(sigma(ndimn))
                    !     e=gaps(igaps)%e
                    !     miu=gaps(igaps)%miu
                    !     f=gaps(igaps)%frict(ipairs)
                    !     c=gaps(igaps)%cohes(ipairs)
                    !     sigma=gaps(igaps)%ctforce(:,ipairs)/gaps(igaps)%aera(ipairs)
                    !     alfa=f/sqrt(9+12*f*f)					!dp准则系数alfa
                    !  k=3*c/sqrt(9+12*f*f)					!dp准则系数k
                    !  i1=(1.+2.*miu/(1.-miu))*sigma(ndimn)						!应力张量第一不变量
                    !     sheart=(k-3*alfa*sigma(ndimn))/sqrt(1-12*alfa**2)
                    !     if(sheart<c)sheart=c  !new
                    !     sheart=sheart*gaps(igaps)%aera(ipairs)
                    !     if(sheart<1.e-5)sheart=1.e-5
                    !        if  (tt>0.95*sheart)then
                    !              if (gaps(igaps)%state(ipairs)==1)gaps(igaps)%state(ipairs)=2
                    !              alfa1=t1/tt
                    !              if (ndimn==3)alfa2=t2/tt
                    !              gaps(igaps)%alfa1(ipairs)=alfa1
                    !              if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                    !
                    !      gaps(igaps)%ctforce(1,ipairs)=sign(sheart,gaps(igaps)%ctforce(1,ipairs))*gaps(igaps)%alfa1(ipairs)
                    !if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sign(sheart,gaps(igaps)%ctforce(2,ipairs))*gaps(igaps)%alfa2(ipairs)
                    !           elseif(gaps(igaps)%state(ipairs)==2)then
                    !               gaps(igaps)%state(ipairs)=1
                    !           endif
                    !      allocate(kxyz(ndimn,ndimn))
                    !      call dep_thin_layer(gaps(igaps)%state(ipairs),e,miu,f,c,sigma,kxyz)
                    !      gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%aera(ipairs)*kxyz/gaps(igaps)%thick
                    !      deallocate(sigma,kxyz)
                endif

                if(gaps(igaps)%goodman==1.and.gaps(igaps)%frict_less==0)then

                    allocate(R(ndimn))
                    kgdm=>gaps(igaps)%kgdm
                    !gamaw=gaps(igaps)%gamaw   !20230402
                    pa   =gaps(igaps)%pa
                    n  =gaps(igaps)%n
                    Rf=gaps(igaps)%Rf
                    r(ndimn)=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                    do idimn=1,ndimn-1
                        R(idimn)=1.0-Rf*abs(gaps(igaps)%ctforce(idimn,ipairs))/sheart
                        if(r(idimn)<1.e-5)r(idimn)=1.e-5
                        gaps(igaps)%kxyz(idimn,idimn,ipairs)=kgdm(idimn)*gamaw*(abs(r(ndimn))/pa)**n*R(idimn)**2
                    end do
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgdm(ndimn)*gamaw
                    do idimn=1,ndimn
                        gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
                    end do
                    icttstif=1
                    nullify(kgdm)
                    deallocate(R)
                endif

            endif
            if(gaps(igaps)%state(ipairs)==0.AND.gaps(igaps)%thin_layer==1)then  !2017/02/14 by Hejinwen
                gaps(igaps)%kxyz(NDIMN,NDIMN,ipairs)=gaps(igaps)%kgroup0(NDIMN,NDIMN)/(1-gaps(IGAPS)%RF)**2
                gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                if(ndimn.eq.3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
            END IF            !2017/02/14 by Hejinwen

            if  (gaps(igaps)%state(ipairs)/=gaps(igaps)%state0(ipairs))icttstif=1

        end do
    end do
    end subroutine state_and_stiff_rigid

    subroutine state_and_stiff_rigid_2021  !20211004

    integer(ink) igaps,npairs,ipairs,idimn,igroupt,istate0,istate  !igroupt,2017/04/03
    real(irk),pointer::kgdm(:)
    real(irk),allocatable::r(:),sigma(:),kxyz(:,:),ps0(:),ps(:),evk(:),stran0(:),stran(:),dstran(:)
    real(irk)    sigman,ft,Gf,xi0,sigmanc,sig1,w0,w1,wx,wxi,t1,t2,tt,sheart,alfa1,alfa2,k0,wx0,c1,c2, &
        pa,n,Rf,e,miu,f,c,k,i1,alfa   !,gamaw 20230402
    icttstif=0

    allocate(ps0(ndimn),ps(ndimn),evk(ndimn))
    !write(7,*)'state_and_stiff_2021'
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if  (gaps(igaps)%state(ipairs)==0) then  !state=0 ,open;=1, close,2,sliding,3,softening
                write(7,*)'igaps=',igaps,'ipairs=',ipairs,'gap=',gaps(igaps)%gap(ndimn,ipairs),'state0-1=',gaps(igaps)%state0(ipairs)
                if  (gaps(igaps)%gap(ndimn,ipairs)<=-1.e-10)then
                    gaps(igaps)%gap(ndimn,ipairs)=0.
                    gaps(igaps)%dxyz(ndimn,ipairs)=0.
                    gaps(igaps)%ctforce(:,ipairs)=1.e-5*gaps(igaps)%aera(ipairs)
                    gaps(igaps)%ft(ipairs)=1.e-5
                    gaps(igaps)%kxyz(:,:,ipairs)=0.
                    gaps(igaps)%state(ipairs)=1
                    if(gaps(igaps)%state0(ipairs)==1)then
                        gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                        do idimn=1,ndimn
                            if(abs(gaps(igaps)%ctforce(idimn,ipairs))<1.e-5)gaps(igaps)%ctforce(idimn,ipairs)=1.e-5
                        enddo
                        !gaps(igaps)%ft(ipairs)=gaps(igaps)%ft0(ipairs)
                        gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                    endif
                endif
            elseif(gaps(igaps)%state(ipairs)>=1) then
                sigman=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                ft=gaps(igaps)%ft(ipairs)
                if  (sigman>ft)then

                    gaps(igaps)%ft(ipairs)=1.e-5   !2017/06
                    gaps(igaps)%state(ipairs)=0
                    gaps(igaps)%ctforce(:,ipairs)=1.e-5*gaps(igaps)%aera(ipairs)       !2017/06
                    gaps(igaps)%kxyz(:,:,ipairs)=0.
                endif
            endif

            if (gaps(igaps)%state(ipairs)==1.or.gaps(igaps)%state(ipairs)==2) then  !

                !write(7,*)'ipairs=',ipairs,'ctforce1=',gaps(igaps)%ctforce(:,ipairs)
                t1=gaps(igaps)%ctforce(1,ipairs)
                if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                tt=abs(t1)
                if (ndimn==3)tt=sqrt(t1**2+t2**2)
                if(gaps(igaps)%thin_layer/=1)then
                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)
                    !if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)  !new
                    if  (tt>0.95*sheart)then
                        if (gaps(igaps)%state(ipairs)==1)gaps(igaps)%state(ipairs)=2
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)

                    elseif(gaps(igaps)%state(ipairs)==2)then
                        if(gaps(igaps)%goodman==0)then     !20161206
                            gaps(igaps)%state(ipairs)=1
                            if(gaps(igaps)%state0(ipairs)==1)then
                                gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                                do idimn=1,ndimn
                                    if(abs(gaps(igaps)%ctforce(idimn,ipairs))<1.e-5)gaps(igaps)%ctforce(idimn,ipairs)=1.e-5
                                enddo
                                gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                            endif
                        endif

                    endif
                    !write(7,*)'ipairs=',ipairs,'ctforce2=',gaps(igaps)%ctforce(:,ipairs)

                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(gaps(igaps)%goodman==0.and.gaps(igaps)%frict_less==0)then
                        if(gaps(igaps)%state(ipairs)==1)then
                            gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                            if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                        else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                            gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup1(1,1)  !柔度系数取大值模拟自由滑动
                            if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup1(2,2)  !柔度系数取大值模拟自由滑动
                        endif
                    endif
                else  !!!!!thin_layer==1

                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)  !2017/02/14 by Hejinwen
                    !if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)
                    if  (tt>0.95*sheart)then
                        gaps(igaps)%state(ipairs)=2
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)
                    elseif(gaps(igaps)%state(ipairs)==2)then
                        gaps(igaps)%state(ipairs)=1
                    endif
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(gaps(igaps)%state(ipairs)==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                        if(ndimn.eq.3) gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                    else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)/(1-gaps(IGAPS)%RF)**2
                        if(ndimn.eq.3)   gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)/(1-gaps(IGAPS)%RF)**2
                    endif
                    !icttstif=1   !2017/02/14 by Hejinwen

                endif

                if(gaps(igaps)%goodman==1.and.gaps(igaps)%frict_less==0)then

                    allocate(R(ndimn))
                    kgdm=>gaps(igaps)%kgdm
                    !gamaw=gaps(igaps)%gamaw    !20230402
                    pa   =gaps(igaps)%pa
                    n  =gaps(igaps)%n
                    Rf=gaps(igaps)%Rf
                    r(ndimn)=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                    t1=gaps(igaps)%ctforce(1,ipairs)
                    if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                    tt=abs(t1)
                    if (ndimn==3)tt=sqrt(t1**2+t2**2)

                    do idimn=1,ndimn-1
                        R(idimn)=1.0-Rf*tt/sheart
                        !write(7,*)'r=',r(idimn)
                        gaps(igaps)%kxyz(idimn,idimn,ipairs)=kgdm(idimn)*gamaw*(abs(r(ndimn))/pa)**n*R(idimn)**2
                    end do
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgdm(ndimn)*gamaw
                    if(block_stab==1)then
                        do idimn=ndimn+1,3*(ndimn-1)
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                        enddo
                    end if
                    if(block_stab==0)then
                        do idimn=1,ndimn
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
                        end do
                    else
                        do idimn=1,3*(ndimn-1)
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
                        end do
                    endif
                    !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=', gaps(igaps)%kxyz(1,1,ipairs),gaps(igaps)%kxyz(2,2,ipairs),gaps(igaps)%kxyz(3,3,ipairs)
                    !gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                    icttstif=1
                    nullify(kgdm)
                    deallocate(R)
                endif

            endif

            if(gaps(igaps)%state(ipairs)==0.AND.gaps(igaps)%thin_layer==1)then  !2017/02/14 by Hejinwen
                gaps(igaps)%kxyz(NDIMN,NDIMN,ipairs)=gaps(igaps)%kgroup0(NDIMN,NDIMN)/(1-gaps(IGAPS)%RF)**2
                gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                if(ndimn.eq.3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
            END IF            !2017/02/14 by Hejinwen
            !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=', gaps(igaps)%kxyz(1,1,ipairs),gaps(igaps)%kxyz(2,2,ipairs),gaps(igaps)%kxyz(3,3,ipairs)
            if  (gaps(igaps)%state(ipairs)/=gaps(igaps)%state0(ipairs))icttstif=1

        end do
    end do
    deallocate(ps0,ps,evk)
    end subroutine state_and_stiff_rigid_2021  !20211004


    subroutine state_and_stiff_2021  !20210704

    integer(ink) igaps,npairs,ipairs,idimn,igroupt,istate0,istate  !igroupt,2017/04/03
    integer(ink),pointer::xlwmd(:)
    real(irk),pointer::kgdm(:)
    real(irk),allocatable::r(:),sigma(:),kxyz(:,:),ps0(:),ps(:),evk(:),stran0(:),stran(:),dstran(:)
    real(irk)    sigman,ft,Gf,xi0,sigmanc,sig1,w0,w1,wx,wxi,t1,t2,tt,sheart,alfa1,alfa2,k0,wx0,c1,c2, &
        pa,n,Rf,e,miu,f,c,k,i1,alfa,ft1,w2, &  !ft1,w2,  2017/04/03  ,gamaw  20230402
        wxd,damage0,damage
    icttstif=0

    allocate(ps0(ndimn),ps(ndimn),evk(ndimn),stran0(ndimn),dstran(ndimn),stran(ndimn))
    !write(7,*)'state_and_stiff_2021'
    do igaps=1,ngaps
        xlwmd=>gaps(igaps)%xlwmd
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(xlwmd(ndimn)==0)then
                if  (gaps(igaps)%state(ipairs)==0) then  !state=0 ,open;=1, close,2,sliding,3,softening
                    write(7,*)'igaps=',igaps,'ipairs=',ipairs,'gap=',gaps(igaps)%gap(ndimn,ipairs),'state0-1=',gaps(igaps)%state0(ipairs)
                    if  (gaps(igaps)%gap(ndimn,ipairs)<=-1.e-10)then
                        gaps(igaps)%gap(ndimn,ipairs)=0.
                        gaps(igaps)%dxyz(ndimn,ipairs)=0.
                        gaps(igaps)%ctforce(:,ipairs)=1.e-5*gaps(igaps)%aera(ipairs)
                        gaps(igaps)%ft(ipairs)=1.e-5
                        gaps(igaps)%kxyz(:,:,ipairs)=0.
                        gaps(igaps)%state(ipairs)=1
                        if(gaps(igaps)%state0(ipairs)==1)then
                            gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                            do idimn=1,ndimn
                                if(abs(gaps(igaps)%ctforce(idimn,ipairs))<1.e-5)gaps(igaps)%ctforce(idimn,ipairs)=1.e-5
                            enddo
                            !gaps(igaps)%ft(ipairs)=gaps(igaps)%ft0(ipairs)
                            gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                        endif
                    endif
                elseif(gaps(igaps)%state(ipairs)>=1) then
                    sigman=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                    ft=gaps(igaps)%ft(ipairs)
                    if  (sigman>ft)then

                        gaps(igaps)%ft(ipairs)=1.e-5   !2017/06
                        gaps(igaps)%state(ipairs)=0
                        gaps(igaps)%ctforce(:,ipairs)=1.e-5*gaps(igaps)%aera(ipairs)       !2017/06
                        gaps(igaps)%kxyz(:,:,ipairs)=0.
                    endif
                endif

            else
                istate0=gaps(igaps)%state0(ipairs)
                damage0=gaps(igaps)%damage0(ipairs)
                damage=gaps(igaps)%damage(ipairs)
                ft=gaps(igaps)%ft(ipairs)
                w0=ft*gaps(igaps)%aera(ipairs)*gaps(igaps)%kgroup0(ndimn,ndimn)
                wxd   =gaps(igaps)%wsc(ipairs)
                ps0   =gaps(igaps)%ctforce0(:,ipairs)/gaps(igaps)%aera(ipairs)
                ps   =gaps(igaps)%ctforce(:,ipairs)/gaps(igaps)%aera(ipairs)

                stran0 =gaps(igaps)%dxyz0(:,ipairs)
                stran  =gaps(igaps)%dxyz (:,ipairs)
                dstran =stran-stran0
                do idimn=1,ndimn
                    evk(idimn)=1./gaps(igaps)%kxyz(idimn,idimn,ipairs)
                end do
                !ps=evk*stran


                istate=istate0  !state=0,open(采用虚拟裂缝模型时体现在3中）;=1, close；
                ! 2,sliding；3,softening；4,unloading
                if(istate0<=2.and.stran(ndimn)>w0)istate=3
                if(istate0==3.and.stran(ndimn)<stran0(ndimn))istate=4
                if(istate0==4.and.stran(ndimn)>wxd)istate=3
                !if(istate==3) then
                !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'istate=',istate,'istate0=',istate0
                ! write(7,*)'ps0=',ps0,'ps=',ps
                !  write(7,*)'damage0=',damage0
                !   write(7,*)'w0=',w0,'stran=',stran(ndimn)
                !   write(7,*)'ctfor=',gaps(igaps)%ctforce(:,ipairs)
                !  endif
                if(istate==3)then
                    sigmanc=ps(ndimn)
                    !w0=ft*gaps(igaps)%kgroup0(ndimn,ndimn)
                    wx=stran(ndimn)-w0
                    call FCM_gap_and_force(igaps,ipairs,xlwmd(ndimn),wx,sigmanc,damage,damage0,stran(ndimn))
                    if(damage<=damage0)damage=damage0
                    damage=(damage+damage0)*.5
                    if(damage<0.)damage=0.
                    write(7,*)'damage=',damage,'sigmanc=',sigmanc,'xlwmd(ndimn)=',xlwmd(ndimn)
                    if(damage>0.9949)then
                        damage=0.995
                        evk(:)=1.e-5/gaps(igaps)%kgroup0(ndimn,ndimn)
                        ps=1.e2*gaps(igaps)%aera(ipairs)
                        sigmanc=1.e2
                    else
                        evk(:)=(1-damage)**2/gaps(igaps)%kgroup0(ndimn,ndimn)
                        ps=evk*stran
                    endif
                    ps=ps/gaps(igaps)%aera(ipairs)
                    ps=ps*sigmanc/ps(ndimn)
                elseif(istate==4)then
                    wxd=damage0
                    ps=ps0+evk*dstran
                    ps=ps/gaps(igaps)%aera(ipairs)
                    damage=damage0
                endif
                if(istate==3) &
                    write(7,*)'damage=',damage,'ps=',ps,'evk=',evk

                do idimn=1,ndimn
                    gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./evk(idimn)
                end do
                gaps(igaps)%state(ipairs)=istate
                gaps(igaps)%damage(ipairs)=damage
                gaps(igaps)%wsc(ipairs)=wxd
                gaps(igaps)%ctforce(:,ipairs)=ps*gaps(igaps)%aera(ipairs)
            endif

            if (xlwmd(ndimn)<=0.and.(gaps(igaps)%state(ipairs)==1.or.gaps(igaps)%state(ipairs)==2)) then  !

                !write(7,*)'ipairs=',ipairs,'ctforce1=',gaps(igaps)%ctforce(:,ipairs)
                t1=gaps(igaps)%ctforce(1,ipairs)
                if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                tt=abs(t1)
                if (ndimn==3)tt=sqrt(t1**2+t2**2)
                if(gaps(igaps)%thin_layer/=1)then
                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)
                    !if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)  !new
                    if  (tt>0.95*sheart)then
                        if (gaps(igaps)%state(ipairs)==1)gaps(igaps)%state(ipairs)=2
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)

                    elseif(gaps(igaps)%state(ipairs)==2)then
                        if(gaps(igaps)%goodman==0)then     !20161206
                            gaps(igaps)%state(ipairs)=1
                            if(gaps(igaps)%state0(ipairs)==1)then
                                gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                                do idimn=1,ndimn
                                    if(abs(gaps(igaps)%ctforce(idimn,ipairs))<1.e-5)gaps(igaps)%ctforce(idimn,ipairs)=1.e-5
                                enddo
                                gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                            endif
                        endif

                    endif
                    !write(7,*)'ipairs=',ipairs,'ctforce2=',gaps(igaps)%ctforce(:,ipairs)

                    if(xlwmd(ndimn)==0)gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(xlwmd(1)==0.and.gaps(igaps)%goodman==0.and.gaps(igaps)%frict_less==0)then
                        if(gaps(igaps)%state(ipairs)==1)then
                            gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                            if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                        else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                            gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup1(1,1)  !柔度系数取大值模拟自由滑动
                            if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup1(2,2)  !柔度系数取大值模拟自由滑动
                        endif
                    endif
                else  !!!!!thin_layer==1

                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)  !2017/02/14 by Hejinwen
                    !if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)
                    if  (tt>0.95*sheart)then
                        gaps(igaps)%state(ipairs)=2
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)
                    elseif(gaps(igaps)%state(ipairs)==2)then
                        gaps(igaps)%state(ipairs)=1
                    endif
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(gaps(igaps)%state(ipairs)==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                        if(ndimn.eq.3) gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                    else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)/(1-gaps(IGAPS)%RF)**2
                        if(ndimn.eq.3)   gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)/(1-gaps(IGAPS)%RF)**2
                    endif
                    !icttstif=1   !2017/02/14 by Hejinwen

                endif

                if(gaps(igaps)%goodman==1.and.gaps(igaps)%frict_less==0)then

                    allocate(R(ndimn))
                    kgdm=>gaps(igaps)%kgdm
                    !gamaw=gaps(igaps)%gamaw  !20230402
                    pa   =gaps(igaps)%pa
                    n  =gaps(igaps)%n
                    Rf=gaps(igaps)%Rf
                    r(ndimn)=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                    t1=gaps(igaps)%ctforce(1,ipairs)
                    if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                    tt=abs(t1)
                    if (ndimn==3)tt=sqrt(t1**2+t2**2)

                    do idimn=1,ndimn-1
                        R(idimn)=1.0-Rf*tt/sheart
                        !write(7,*)'r=',r(idimn)
                        gaps(igaps)%kxyz(idimn,idimn,ipairs)=kgdm(idimn)*gamaw*(abs(r(ndimn))/pa)**n*R(idimn)**2
                    end do
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgdm(ndimn)*gamaw
                    if(block_stab==1)then
                        do idimn=ndimn+1,3*(ndimn-1)
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                        enddo
                    end if
                    if(block_stab==0)then
                        do idimn=1,ndimn
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
                        end do
                    else
                        do idimn=1,3*(ndimn-1)
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
                        end do
                    endif
                    !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=', gaps(igaps)%kxyz(1,1,ipairs),gaps(igaps)%kxyz(2,2,ipairs),gaps(igaps)%kxyz(3,3,ipairs)
                    !gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                    icttstif=1
                    nullify(kgdm)
                    deallocate(R)
                endif

            endif

            if(gaps(igaps)%state(ipairs)==0.AND.gaps(igaps)%thin_layer==1)then  !2017/02/14 by Hejinwen
                gaps(igaps)%kxyz(NDIMN,NDIMN,ipairs)=gaps(igaps)%kgroup0(NDIMN,NDIMN)/(1-gaps(IGAPS)%RF)**2
                gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                if(ndimn.eq.3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
            END IF            !2017/02/14 by Hejinwen
            !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=', gaps(igaps)%kxyz(1,1,ipairs),gaps(igaps)%kxyz(2,2,ipairs),gaps(igaps)%kxyz(3,3,ipairs)
            if  (gaps(igaps)%state(ipairs)/=gaps(igaps)%state0(ipairs))icttstif=1

        end do
        nullify(xlwmd)
    end do
    deallocate(ps0,ps,evk,stran0,dstran,stran)
    end subroutine state_and_stiff_2021


    subroutine FCM_gap_and_force(igaps,ipairs,xlwmodel,wx,sigmanc,damage,damage0,gap)  !20210125


    integer(ink)  xlwmodel,igaps,ipairs,igroupt
    real(irk)     wx,w0,w1,w2,ft1,ft,sigmanc,c1,c2,damage,damage0,gap,gf,sig1


    c1=1.0;c2=5.64
    Gf=gaps(igaps)%Gf(ipairs)
    ft=gaps(igaps)%ft(ipairs)
    if(xlwmodel==1)then
        w0=2.*Gf/ft
    elseif(xlwmodel==2)then
        sig1=ft/3.
        w0=3.6*Gf/ft
        w1=2.*w0/9.
    elseif(xlwmodel==3)then
        w0=209*1.e-6
    elseif(xlwmodel==4)then
        w0=5.618*Gf/ft
    elseif(xlwmodel==5)then
        igroupt=1  !2017/04/03
        w0=gaps(igaps)%wt0(igroupt)
        w1=gaps(igaps)%wt1(igroupt)
        w2=gaps(igaps)%wt2(igroupt)
        ft1=gaps(igaps)%ft1(igroupt)
    endif

    if(xlwmodel==1)then

        write(7,*)'xlwmodel=',xlwmodel,'w0=',w0,'wx=',wx,'ft=',ft
        if(wx>w0)then
            sigmanc=1.e2
        else
            sigmanc=(1-wx/w0)*ft
        endif
        write(7,*)'sigmanc=',sigmanc
    elseif(xlwmodel==2)then !Bilinear sofening , from Petersson
        if(w1<wx.and.wx<=w0)then
            sigmanc=((w0-wx)/(w0-w1))*ft1
        else !if(w1>0..and.wx<=w1)then
            sigmanc=(1.-wx/w1)*(ft-ft1)+ft1
        endif
    elseif(xlwmodel==3)then !Bilinear sofening , from Petersson
        sigmanc=(((1.+(wx/w0)**3)*exp(-5.64*wx/w0))-(wx/w0)*7.105773e-3)*ft
    elseif(xlwmodel==4)then !cornelissen 颜天佑论文（固体力学学报）
        sigmanc=((1+(c1*wx/w0)**3)*exp(-c2*wx/w0)-wx/w0*(1+c1**3)*exp(-c2))*ft
    elseif(xlwmodel==5)then ! Jiaji Du,Albert S. Kobayashi and Neil M. Hawkins, FEM DYNAMIC FRACTURE ANALYSIS OF CONCRETE BEAMS
        ! Journal of Engineering Mechanics, Vol. 115, No. 10, October, 1989
        !write(7,*)'wx=',wx,'w0,w1,w2=',w0,w1,w2,'ft=',ft,'ft1=',ft1

        if(wx<=w1)then
            sigmanc=ft
        elseif(wx<=w2)then
            sigmanc=ft+(ft1-ft)*(wx-w1)/(w2-w1)
        elseif(wx<w0)then
            sigmanc=ft1+(0-ft1)*(wx-w2)/(w0-w2)
        elseif(wx>=w0)then
            sigmanc=1.e2
        endif
    endif
    damage=1-sigmanc*gaps(igaps)%aera(ipairs)*gaps(igaps)%kgroup0(ndimn,ndimn)/gap
    !write(7,*)'ielem=',ielem,'igaus=',igaus,'wx=',wx,'sigmanc=',sigmanc,'damage=',damage


    end subroutine FCM_gap_and_force  !20210125


    !!!!!!!!!!!!!!!!!!
    subroutine state_and_stiff

    integer(ink) igaps,npairs,ipairs,idimn,igroupt  !igroupt,2017/04/03
    integer(ink),pointer::xlwmd(:)
    real(irk),pointer::kgdm(:)
    real(irk),allocatable::r(:),sigma(:),kxyz(:,:)
    real(irk)    sigman,ft,Gf,xi0,sigmanc,sig1,w0,w1,wx,wxi,t1,t2,tt,sheart,alfa1,alfa2,k0,wx0,c1,c2, &
        pa,n,Rf,e,miu,f,c,k,i1,alfa,ft1,w2  !ft1,w2,  2017/04/03  gamaw, 20230402

    icttstif=0

    !write(7,*)'state_and_stiff'
    do igaps=1,ngaps
        xlwmd=>gaps(igaps)%xlwmd
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if  (gaps(igaps)%state(ipairs)==0) then  !state=0 ,open;=1, close,2,sliding,3,softening

                write(7,*)'igaps=',igaps,'ipairs=',ipairs,'gap=',gaps(igaps)%gap(ndimn,ipairs),'state0-1=',gaps(igaps)%state0(ipairs)
                if  (gaps(igaps)%gap(ndimn,ipairs)<=-1.e-10)then

                    gaps(igaps)%gap(ndimn,ipairs)=0.
                    gaps(igaps)%dxyz(ndimn,ipairs)=0.
                    gaps(igaps)%ctforce(:,ipairs)=1.e-5*gaps(igaps)%aera(ipairs)
                    gaps(igaps)%ft(ipairs)=1.e-5
                    gaps(igaps)%kxyz(:,:,ipairs)=0.
                    gaps(igaps)%state(ipairs)=1
                    if(gaps(igaps)%state0(ipairs)==1)then
                        gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                        do idimn=1,ndimn
                            if(abs(gaps(igaps)%ctforce(idimn,ipairs))<1.e-5)gaps(igaps)%ctforce(idimn,ipairs)=1.e-5
                        enddo
                        !gaps(igaps)%ft(ipairs)=gaps(igaps)%ft0(ipairs)
                        gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kxyz0(:,:,ipairs)
                    endif
                endif
            elseif(gaps(igaps)%state(ipairs)>=1) then
                sigman=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                ft=gaps(igaps)%ft(ipairs)

                !write(7,*)'ipairs=',ipairs,'sigman=',sigman,'ft=',ft

                if (xlwmd(ndimn)<=0)then
                    if  (sigman>ft)then

                        gaps(igaps)%ft(ipairs)=1.e-5   !2017/06
                        gaps(igaps)%state(ipairs)=0
                        gaps(igaps)%ctforce(:,ipairs)=1.e-5*gaps(igaps)%aera(ipairs)       !2017/06
                        gaps(igaps)%kxyz(:,:,ipairs)=0.
                    endif
                else
                    Gf=gaps(igaps)%Gf(ipairs)
                    wx=gaps(igaps)%dxyz(ndimn,ipairs)
                    wx0=gaps(igaps)%dxyz0(ndimn,ipairs)
                    wxi=gaps(igaps)%dxyzi(ndimn,ipairs)


                    if(gaps(igaps)%state(ipairs)==3.and.wx<=-1.e-10)then    !!!new !20120821
                        gaps(igaps)%gap(ndimn,ipairs)=0.
                        gaps(igaps)%dxyz(ndimn,ipairs)=0.
                        gaps(igaps)%state(ipairs)=1
                        gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=0.
                        gaps(igaps)%ctforce(ndimn,ipairs)=gaps(igaps)%ctforce0(ndimn,ipairs)
                    endif   !!!new


                    if(xlwmd(ndimn)==1)then
                        w0=2.*Gf/ft
                    elseif(xlwmd(ndimn)==2)then
                        sig1=ft/3.
                        w0=3.6*Gf/ft
                        w1=2.*w0/9.
                    elseif(xlwmd(ndimn)==3)then
                        w0=209*1.e-6
                    elseif(xlwmd(ndimn)==4)then
                        w0=5.618*Gf/ft
                    elseif(xlwmd(ndimn)==5)then
                        igroupt=1  !2017/04/03
                        w0=gaps(igaps)%wt0(igroupt)
                        w1=gaps(igaps)%wt1(igroupt)
                        w2=gaps(igaps)%wt2(igroupt)
                        ft1=gaps(igaps)%ft1(igroupt)
                        !write(7,*)'w0,w1,w2,ft1=',w0,w1,w2,ft1
                    endif

                    !if(ipairs==13)then
                    !              write(7,*)'igaps=',igaps,'ipairs=',ipairs,'wx0=',wx0,'wx=',wx,'w0=',w0
                    !			  write(7,*)'kxy0=',gaps(igaps)%kxyz(ndimn,ipairs),'state0=',gaps(igaps)%state(ipairs)
                    !			  write(7,*)'ctforce=',gaps(igaps)%ctforce(ndimn,ipairs),'ctforce0=',gaps(igaps)%ctforce0(ndimn,ipairs)
                    !			  write(7,*)'dxyz0=',gaps(igaps)%dxyz0(ndimn,ipairs)
                    !			  write(7,*)'dxyz=',gaps(igaps)%dxyz(ndimn,ipairs)
                    !			  write(7,*)'gap0=',gaps(igaps)%gap0(ndimn,ipairs)
                    !			  write(7,*)'gap=',gaps(igaps)%gap(ndimn,ipairs)
                    !endif
                    if  (gaps(igaps)%state(ipairs)<=2)then
                        if  (sigman>ft)then
                            gaps(igaps)%state(ipairs)=3
                            gaps(igaps)%ctforce(ndimn,ipairs)=ft*gaps(igaps)%aera(ipairs)
                            if(xlwmd(ndimn)==1)then
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=-w0/(ft*gaps(igaps)%aera(ipairs))
                            elseif(xlwmd(ndimn)==2)then
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=-w1/((ft-sig1)*gaps(igaps)%aera(ipairs))
                            elseif(xlwmd(ndimn)==3)then
                                k0=((1.+(wx/w0)**3)*(-5.64/w0)+3.*wx**2/(w0**3))*exp(-5.64*wx/w0)-7.105773e-3/w0
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*ft*gaps(igaps)%aera(ipairs))
                            elseif(xlwmd(ndimn)==4)then
                                c1=1.0;c2=5.64
                                k0=((1.+(c1*wx/w0)**3)*(-c2/w0)+3.*c1**3*wx**2/(w0**3))*exp(-c2*wx/w0)-(1+c1**3)*exp(-c2)/w0
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*ft*gaps(igaps)%aera(ipairs))
                            elseif(xlwmd(ndimn)==5)then  !2017/04/03
                                !k0=w1/((ft1-ft)*gaps(igaps)%aera(ipairs))
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=-w1/(.02*ft*gaps(igaps)%aera(ipairs))
                                write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=',gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                            endif
                        endif
                    elseif(gaps(igaps)%state(ipairs)==3)then  !!state==3

                        write(7,*)'igaps=',igaps,'ipairs=',ipairs,'wx=',wx,'w0=',w0

                        if(abs(wx)<1.e-10.or.abs(wx-wx0)<1.e-10)cycle  !20120821
                        if(wx>w0)then
                            gaps(igaps)%state(ipairs)=0
                            gaps(igaps)%ctforce(:,ipairs)=0.
                            gaps(igaps)%gap(ndimn,ipairs)=wx
                            gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=0.
                            write(7,*)'igaps=',igaps,'ipairs=',ipairs
                        elseif(wx<wx0)then   !!进入软化卸载
                            write(7,*)'ipairs3-4=',ipairs,'wx=',wx,'wx0=',wx0
                            gaps(igaps)%state(ipairs)=4
                            gaps(igaps)%wsc(ipairs)=wx0
                            call character_softening_unloading(xlwmd(ndimn),wx0,w0,w1,sigmanc,k0,ft,gaps(igaps)%wsc(ipairs),sig1,w2,ft1)
                            k0=sigmanc/wx0
                            gaps(igaps)%ctforce(ndimn,ipairs)=(sigmanc+k0*(wx-wx0))*gaps(igaps)%aera(ipairs)
                            gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                            gaps(igaps)%wsc(ipairs)=wx0

                        else !!!!!!!!软化段加载 state==3

                            write(7,*)'igaps=',igaps,'ipairs=',ipairs
                            call character_softening_loading(xlwmd(ndimn),wx,w0,w1,sigmanc,k0,ft,sig1,w2,ft1)
                            gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc*gaps(igaps)%aera(ipairs)
                            gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                            write(7,*)'kxyz=',gaps(igaps)%kxyz(ndimn,ndimn,ipairs)

                        endif  !!!!!!!!软化段加载

                    elseif(gaps(igaps)%state(ipairs)==4)then  !!state==4  软化段卸载


                        if(wx<-1.e-10)then   !进入闭合受压状态
                            gaps(igaps)%state(ipairs)=5
                            gaps(igaps)%sigmad(ipairs)=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                            gaps(igaps)%xd   (ipairs)=0.
                            gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=0.
                            gaps(igaps)%dxyz(ndimn,ipairs)=0.
                        elseif(wx0<wx)then
                            write(7,*)'ipairs4-6=',ipairs,'wx=',wx,'wx0=',wx0
                            gaps(igaps)%state(ipairs)=6  !进入软化卸载再加载状态
                            if(xlwmd(ndimn)<=3.or.xlwmd(ndimn)==5)then
                                if(abs(gaps(igaps)%kxyz(ndimn,ndimn,ipairs))>1.e-10)then
                                    k0=gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                                    k0=1./k0
                                    gaps(igaps)%ctforce(ndimn,ipairs)=k0*wx*gaps(igaps)%aera(ipairs)
                                endif
                            elseif(xlwmd(ndimn)==4)then
                                gaps(igaps)%sigmad(ipairs)=gaps(igaps)%ctforce0(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                                gaps(igaps)%xd    (ipairs)=wx0
                                call character_unloading_loading(xlwmd(ndimn),wx,w0,w1,sigmanc,k0,ft,gaps(igaps)%wsc(ipairs),gaps(igaps)%sigmad(ipairs),gaps(igaps)%xd(ipairs))
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                                gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc*gaps(igaps)%aera(ipairs)

                            endif

                        else  !!state==4
                            if(xlwmd(ndimn)<=3.or.xlwmd(ndimn)==5)then
                                if(abs(gaps(igaps)%kxyz(ndimn,ndimn,ipairs))>1.e-10)then
                                    k0=gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                                    k0=1./k0
                                    sigmanc=gaps(igaps)%ctforce0(ndimn,ipairs)
                                    gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc+k0*(wx-wxi)*gaps(igaps)%aera(ipairs)
                                endif
                            elseif(xlwmd(ndimn)==4)then
                                call character_softening_unloading(xlwmd(ndimn),wx,w0,w1,sigmanc,k0,ft,gaps(igaps)%wsc(ipairs),sig1,w2,ft1)
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                                gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc*gaps(igaps)%aera(ipairs)
                            endif
                        endif
                    elseif(gaps(igaps)%state(ipairs)==5)then  !!state==5  闭合受压状态
                        if((gaps(igaps)%ctforce(ndimn,ipairs)-gaps(igaps)%sigmad(ipairs)*gaps(igaps)%aera(ipairs))  &
                            /abs(gaps(igaps)%ctforce(ndimn,ipairs))>0.01)then
                            gaps(igaps)%state(ipairs)=6  !进入软化卸载再加载状态
                            if(xlwmd(ndimn)<=3.or.xlwmd(ndimn)==5)then
                                if(abs(gaps(igaps)%kxyz(ndimn,ndimn,ipairs))>1.e-10)then
                                    k0=gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                                    k0=1./k0
                                    gaps(igaps)%ctforce(ndimn,ipairs)=k0*wx*gaps(igaps)%aera(ipairs)
                                endif
                                !write(7,*)'ipairs=',ipairs,'igaps=',igaps,'k0=',k0,'wx=',wx
                            elseif(xlwmd(ndimn)==4)then
                                gaps(igaps)%sigmad(ipairs)=gaps(igaps)%ctforce0(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                                gaps(igaps)%xd    (ipairs)=wxi
                                call character_unloading_loading(xlwmd(ndimn),wx,w0,w1,sigmanc,k0,ft,gaps(igaps)%wsc(ipairs),gaps(igaps)%sigmad(ipairs),gaps(igaps)%xd(ipairs))
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                                gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc*gaps(igaps)%aera(ipairs)
                            endif
                        endif
                    elseif(gaps(igaps)%state(ipairs)==6)then  !!state==6  再加载状态
                        if((wx-gaps(igaps)%wsc(ipairs))>1.e-5)then
                            gaps(igaps)%state(ipairs)=3
                            call character_softening_loading(xlwmd(ndimn),wx,w0,w1,sigmanc,k0,ft,sig1,w2,ft1)
                            gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc*gaps(igaps)%aera(ipairs)
                            gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                        elseif((wx0-wx)>1.e-5)then
                            gaps(igaps)%state(ipairs)=4
                            if(xlwmd(ndimn)<=3.or.xlwmd(ndimn)==5)then
                                if(abs(gaps(igaps)%kxyz(ndimn,ndimn,ipairs))>1.e-10)then
                                    k0=1./gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                                    sigmanc=gaps(igaps)%ctforce0(ndimn,ipairs)
                                    gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc+k0*(wx-wxi)*gaps(igaps)%aera(ipairs)
                                endif
                            elseif(xlwmd(ndimn)==4)then
                                call character_softening_unloading(xlwmd(ndimn),wx,w0,w1,sigmanc,k0,ft,gaps(igaps)%wsc(ipairs),sig1,w2,ft1)
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                                gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc*gaps(igaps)%aera(ipairs)
                            endif
                        else   !state==6
                            if(xlwmd(ndimn)<=3.or.xlwmd(ndimn)==5)then
                                if(abs(gaps(igaps)%kxyz(ndimn,ndimn,ipairs))>1.e-10)then
                                    k0=1./gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                                    sigmanc=gaps(igaps)%ctforce0(ndimn,ipairs)
                                    gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc+k0*(wx-wxi)*gaps(igaps)%aera(ipairs)
                                endif
                            elseif(xlwmd(ndimn)==4)then
                                call character_unloading_loading(xlwmd(ndimn),wx,w0,w1,sigmanc,k0,ft,gaps(igaps)%wsc(ipairs),gaps(igaps)%sigmad(ipairs),gaps(igaps)%xd(ipairs))
                                gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=1./(k0*gaps(igaps)%aera(ipairs))
                                gaps(igaps)%ctforce(ndimn,ipairs)=sigmanc*gaps(igaps)%aera(ipairs)
                            endif
                        endif

                    endif !state


                endif !xlwmd/=0
            endif ! sate>=1

            if (xlwmd(ndimn)>=0.and.(gaps(igaps)%state(ipairs)==1.or.gaps(igaps)%state(ipairs)==2)) then  !

                !write(7,*)'ipairs=',ipairs,'ctforce1=',gaps(igaps)%ctforce(:,ipairs)
                t1=gaps(igaps)%ctforce(1,ipairs)
                if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                tt=abs(t1)
                if (ndimn==3)tt=sqrt(t1**2+t2**2)
                if(gaps(igaps)%thin_layer/=1)then
                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)
                    !if(ipairs==1) then
                    ! write(7,*)'ipairs=',ipairs,'fn=',gaps(igaps)%ctforce(ndimn,ipairs),'sheart=',sheart
                    ! write(7,*)'aera=',gaps(igaps)%aera(ipairs),'cohes=',gaps(igaps)%cohes(ipairs),'frict=',gaps(igaps)%frict(ipairs)
                    ! endif

                    if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)  !new

                    ! if(ipairs==1) &
                    !write(7,*)'igaps=',igaps,'ipairsxx=',ipairs,'tt=',tt,'sheartxxxx=',sheart,'ratioxx=',tt/sheart
                    if  (tt>0.95*sheart)then
                        !if(gaps(igaps)%goodman==0) then    !20161206         !2017/02/14
                        if (gaps(igaps)%state(ipairs)==1)gaps(igaps)%state(ipairs)=2
                        !endif
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)


                        !gaps(igaps)%ctforce(1,ipairs)=abs(-gaps(igaps)%ctforce(ndimn,ipairs)*   &
                        !gaps(igaps)%frict(ipairs)+gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))*gaps(igaps)%alfa1(ipairs)
                        !if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=abs(-gaps(igaps)%ctforce(ndimn,ipairs)*   &
                        !gaps(igaps)%frict(ipairs)+gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))*gaps(igaps)%alfa2(ipairs)
                    elseif(gaps(igaps)%state(ipairs)==2)then
                        if(gaps(igaps)%goodman==0)then     !20161206
                            gaps(igaps)%state(ipairs)=1
                            if(gaps(igaps)%state0(ipairs)==1)then
                                gaps(igaps)%ctforce(:,ipairs)=gaps(igaps)%ctforce0(:,ipairs)
                                do idimn=1,ndimn
                                    if(abs(gaps(igaps)%ctforce(idimn,ipairs))<1.e-5)gaps(igaps)%ctforce(idimn,ipairs)=1.e-5
                                enddo
                                !gaps(igaps)%ft(ipairs)=gaps(igaps)%ft0(ipairs)  !20161108
                                gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kgroup0(:,:)
                            endif
                        endif

                    endif
                    !write(7,*)'ipairs=',ipairs,'ctforce2=',gaps(igaps)%ctforce(:,ipairs)

                    if(xlwmd(ndimn)==0)gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(xlwmd(1)==0.and.gaps(igaps)%goodman==0.and.gaps(igaps)%frict_less==0)then
                        if(gaps(igaps)%state(ipairs)==1)then
                            gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                            if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                        else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                            gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup1(1,1)  !柔度系数取大值模拟自由滑动
                            if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup1(2,2)  !柔度系数取大值模拟自由滑动
                        endif
                    endif
                else  !!!!!thin_layer==1

                    sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)  !2017/02/14 by Hejinwen
                    if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)
                    if  (tt>0.95*sheart)then
                        gaps(igaps)%state(ipairs)=2
                        alfa1=t1/tt
                        if (ndimn==3)alfa2=t2/tt
                        gaps(igaps)%alfa1(ipairs)=alfa1
                        if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                        gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)
                    elseif(gaps(igaps)%state(ipairs)==2)then
                        gaps(igaps)%state(ipairs)=1
                    endif
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgroup0(ndimn,ndimn)
                    if(gaps(igaps)%state(ipairs)==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                        if(ndimn.eq.3) gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
                    else if(gaps(igaps)%state(ipairs)==2.and.xlwsol==1)then
                        gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)/(1-gaps(IGAPS)%RF)**2
                        if(ndimn.eq.3)   gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)/(1-gaps(IGAPS)%RF)**2
                    endif
                    !icttstif=1   !2017/02/14 by Hejinwen

                    !     allocate(sigma(ndimn))
                    !     e=gaps(igaps)%e
                    !     miu=gaps(igaps)%miu
                    !     f=gaps(igaps)%frict(ipairs)
                    !     c=gaps(igaps)%cohes(ipairs)
                    !     sigma=gaps(igaps)%ctforce(:,ipairs)/gaps(igaps)%aera(ipairs)
                    !
                    !
                    !     alfa=f/sqrt(9+12*f*f)					!dp准则系数alfa
                    !  k=3*c/sqrt(9+12*f*f)					!dp准则系数k
                    !  i1=(1.+2.*miu/(1.-miu))*sigma(ndimn)						!应力张量第一不变量
                    !     sheart=(k-3*alfa*sigma(ndimn))/sqrt(1-12*alfa**2)
                    !     if(sheart<c)sheart=c  !new
                    !     sheart=sheart*gaps(igaps)%aera(ipairs)
                    !      ! if(igaps==5.and.ipairs==1) &
                    !      !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'sigma=',sigma,'sheart=',sheart
                    !     if(sheart<1.e-5)sheart=1.e-5
                    !
                    !     !if(igaps==5.and.ipairs==1) &
                    !     ! write(7,*)'igaps=',igaps,'ipairs=',ipairs,'tt=',tt,'sheart=',sheart
                    !        if  (tt>0.95*sheart)then
                    !              if (gaps(igaps)%state(ipairs)==1)gaps(igaps)%state(ipairs)=2
                    !              alfa1=t1/tt
                    !              if (ndimn==3)alfa2=t2/tt
                    !              gaps(igaps)%alfa1(ipairs)=alfa1
                    !              if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                    !
                    !      gaps(igaps)%ctforce(1,ipairs)=sign(sheart,gaps(igaps)%ctforce(1,ipairs))*gaps(igaps)%alfa1(ipairs)
                    !if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sign(sheart,gaps(igaps)%ctforce(2,ipairs))*gaps(igaps)%alfa2(ipairs)
                    !           elseif(gaps(igaps)%state(ipairs)==2)then
                    !               gaps(igaps)%state(ipairs)=1
                    !           endif
                    !      allocate(kxyz(ndimn,ndimn))
                    !      call dep_thin_layer(gaps(igaps)%state(ipairs),e,miu,f,c,sigma,kxyz)
                    !       !if(igaps==5.and.ipairs==1) &
                    !       !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=',kxyz(1,:),kxyz(2,:)
                    !      gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%aera(ipairs)*kxyz/gaps(igaps)%thick
                    !      deallocate(sigma,kxyz)
                endif

                if(gaps(igaps)%goodman==1.and.gaps(igaps)%frict_less==0)then

                    allocate(R(ndimn))
                    kgdm=>gaps(igaps)%kgdm
                    !gamaw=gaps(igaps)%gamaw  20230402
                    pa   =gaps(igaps)%pa
                    n  =gaps(igaps)%n
                    Rf=gaps(igaps)%Rf
                    r(ndimn)=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
                    t1=gaps(igaps)%ctforce(1,ipairs)
                    if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
                    tt=abs(t1)
                    if (ndimn==3)tt=sqrt(t1**2+t2**2)

                    do idimn=1,ndimn-1
                        R(idimn)=1.0-Rf*tt/sheart
                        !write(7,*)'r=',r(idimn)
                        gaps(igaps)%kxyz(idimn,idimn,ipairs)=kgdm(idimn)*gamaw*(abs(r(ndimn))/pa)**n*R(idimn)**2
                    end do
                    gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgdm(ndimn)*gamaw
                    if(block_stab==1)then
                        do idimn=ndimn+1,3*(ndimn-1)
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=gaps(igaps)%kxyz(ndimn,ndimn,ipairs)
                        enddo
                    end if
                    if(block_stab==0)then
                        do idimn=1,ndimn
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
                        end do
                    else
                        do idimn=1,3*(ndimn-1)
                            gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
                        end do
                    endif
                    !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=', gaps(igaps)%kxyz(1,1,ipairs),gaps(igaps)%kxyz(2,2,ipairs),gaps(igaps)%kxyz(3,3,ipairs)
                    !gaps(igaps)%kxyz(:,:,ipairs)=gaps(igaps)%kxyz0(:,:)
                    icttstif=1
                    nullify(kgdm)
                    deallocate(R)
                endif

            endif

            if(gaps(igaps)%state(ipairs)==0.AND.gaps(igaps)%thin_layer==1)then  !2017/02/14 by Hejinwen
                gaps(igaps)%kxyz(NDIMN,NDIMN,ipairs)=gaps(igaps)%kgroup0(NDIMN,NDIMN)/(1-gaps(IGAPS)%RF)**2
                gaps(igaps)%kxyz(1,1,ipairs)=gaps(igaps)%kgroup0(1,1)
                if(ndimn.eq.3)gaps(igaps)%kxyz(2,2,ipairs)=gaps(igaps)%kgroup0(2,2)
            END IF            !2017/02/14 by Hejinwen
            !write(7,*)'igaps=',igaps,'ipairs=',ipairs,'kxyz=', gaps(igaps)%kxyz(1,1,ipairs),gaps(igaps)%kxyz(2,2,ipairs),gaps(igaps)%kxyz(3,3,ipairs)
            if  (gaps(igaps)%state(ipairs)/=gaps(igaps)%state0(ipairs))icttstif=1

        end do
        nullify(xlwmd)
    end do
    end subroutine state_and_stiff



    subroutine state_and_stiff_general

    integer(ink) igaps,npairs,ipairs,idimn,igroupt  !igroupt,2017/04/16
    real(irk),pointer::kgdm(:)
    real(irk),allocatable::r(:),sigma(:),kxyz(:,:)
    real(irk)    st,ss,sigman,ft,rt,t1,t2,tt,sheart,alfa1,alfa2,pa,n,Rf    ! 2017/04/16,gamaw 20230402

    !write(7,*)'state_and_stiff_general'
    icttstif=1
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            !         do idimn=1,ndimn
            !gaps(igaps)%ctforce(idimn,ipairs)=gaps(igaps)%ctforce(idimn,ipairs)-damp_ctt*(gaps(igaps)%ctforce(idimn,ipairs)-gaps(igaps)%ctforce0(idimn,ipairs))/ditime
            !         end do

            sigman=gaps(igaps)%ctforce(ndimn,ipairs)/gaps(igaps)%aera(ipairs)
            ft=gaps(igaps)%ft(ipairs)
            write(7,*)'ipairs=',ipairs,'sigman=',sigman,'ft=',ft


            kgdm=>gaps(igaps)%kgdm
            !gamaw=gaps(igaps)%gamaw  20230402
            pa   =gaps(igaps)%pa
            n  =gaps(igaps)%n
            Rf=gaps(igaps)%Rf
            if  (sigman>=ft)then
                sigman=ft
                gaps(igaps)%ctforce(ndimn,ipairs)=gaps(igaps)%ft(ipairs)*gaps(igaps)%aera(ipairs)
                !else if(sigman<=0..and.sigman>=-1.*Pa)then
                !    sigman=-pa
            endif

            st=0.
            if(sigman>0.)st=sigman/ft
            if(sigman>=0.)then
                sigman=-(1-.5*sigman/ft)*Pa
            else
                sigman=sigman-pa
            endif


            t1=gaps(igaps)%ctforce(1,ipairs)
            if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
            tt=abs(t1)
            if (ndimn==3)tt=sqrt(t1**2+t2**2)
            sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)

            ss=tt/sheart
            write(7,*)'ipairs=',ipairs, 'ss=',ss,'tt=',tt,'sheart=',sheart
            if  (abs(ss)>1.0)then
                ss=1.0
                alfa1=t1/tt
                if (ndimn==3)alfa2=t2/tt
                gaps(igaps)%alfa1(ipairs)=alfa1
                if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
                gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
                if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)
            endif

            gaps(igaps)%kxyz(ndimn,ndimn,ipairs)=gaps(igaps)%kgdm(ndimn)*gamaw*(abs(sigman)/pa)**n*(1-.5*st)**2
            gaps(igaps)%kxyz(1,1,ipairs)=kgdm(1)*gamaw*(abs(sigman)/pa)**n*(1-.5*st)**2*(1-Rf*ss)**2
            if(ndimn==3)gaps(igaps)%kxyz(2,2,ipairs)=kgdm(2)*gamaw*(abs(sigman)/pa)**n*(1-.5*st)**2*(1-Rf*ss)**2

            !endif
            nullify(kgdm)
            write(7,*)'ipairs=',ipairs, 'ss=',ss,'sigman=',sigman,'abs(sigman)/pa=',abs(sigman)/pa,'kxyz=',gaps(igaps)%kxyz(1,1,ipairs), gaps(igaps)%kxyz(2,2,ipairs)

            do idimn=1,ndimn
                gaps(igaps)%kxyz(idimn,idimn,ipairs)=1./ gaps(igaps)%kxyz(idimn,idimn,ipairs)
            end do
        end do
    end do
    end subroutine state_and_stiff_general

    !
    !subroutine dep_joint_xwg  !(En,Et,phai0,frictd,Fc,sigma,Dep)
    !	character(50)		::	text
    !    integer len1,Ncyc,nn,ic,state,loading,i,j,k,state0,loading0
    !	real				::	eps,sigman,sigmaC,Kt,Kn,cohes,phair,phaib,phai,alfa,Up,Ur,U0,  &
    !                            dut,tut,alfa0,coef,dsigmate,yield,tut0,tutp,Wp,tun,Cx,a,b,AA,lamda, &
    !                            sigmatm,sigmatc,sigmanc,dun,dsigmat,alfab,Ucyc,dut0,dsigman,Tp,T0,Tr,k1,sigmat,tutm,dutx,ratio
    !	real,allocatable				::  sigma(:),Dep(:,:),De(:,:),Dp(:,:)
    !
    !
    !
    !             t1=gaps(igaps)%ctforce(1,ipairs)
    !             if (ndimn==3)t2=gaps(igaps)%ctforce(2,ipairs)
    !             tt=abs(t1)
    !             if (ndimn==3)tt=sqrt(t1**2+t2**2)
    !             sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)-gaps(igaps)%ctforce(ndimn,ipairs)*gaps(igaps)%frict(ipairs)
    !             if(sheart<gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs))sheart=gaps(igaps)%aera(ipairs)*gaps(igaps)%cohes(ipairs)  !new
    !             !write(7,*)'igaps=',igaps,'ipairsxx=',ipairs,'tt=',tt,'sheartxxxx=',sheart,'ratioxx=',tt/sheart
    !               if  (tt>0.995*sheart)then
    !                if (gaps(igaps)%state(ipairs)==1)gaps(igaps)%state(ipairs)=2
    !                alfa1=t1/tt
    !                if (ndimn==3)alfa2=t2/tt
    !                gaps(igaps)%alfa1(ipairs)=alfa1
    !                if (ndimn==3)gaps(igaps)%alfa2(ipairs)=alfa2
    !     	       gaps(igaps)%ctforce(1,ipairs)=sheart*gaps(igaps)%alfa1(ipairs)
    !		        if(ndimn==3)gaps(igaps)%ctforce(2,ipairs)=sheart*gaps(igaps)%alfa2(ipairs)
    !               endif
    !!    allocate(sigma(ndimn),Dep(ndimn,ndimn),De(ndimn,ndimn),Dp(ndimn,ndimn))

    !    De(1,1)=Kt
    !    De(2,2)=Kn
    !    state=1
    !    sigmat=0.
    !    alfa=alfa0
    !    loading=1
    !    loading0=1
    !    state0=1
    !    Wp=0.
    !    do i=1,Ncyc
    !        do j=1,4
    !        coef=1.
    !        if(j==2.or.j==3)coef=-1.
    !        dut=dut0*coef
    !           do k=1,nn
    !               !write(5,*)'j=',j,'k=',k
    !            tutm=tut+dut
    !            dsigmate=De(1,1)*dut
    !
    !     if(state==1)then
    !            sigmatm=sigmat+dsigmate
    !            yield=abs(sigmatm)-T0
    !            write(5,*)'tutm=',tutm,'sigmatm=',sigmatm,'yield=',yield
    !        if(yield>=eps) then
    !             state=2
    !             loading=1
    !         endif
    !     elseif(state==2.and.loading==1)then
    !
    !         loading=1
    !         if(abs(tutm)<abs(tut0))loading=-1
    !         if(loading==-1)then
    !              tutp=abs(tut0)
    !         endif
    !      elseif(state==2.and.loading==-1)then
    !
    !         loading=-1
    !         if(abs(tutm)>tutp)loading=1
    !         if(loading==-1)then
    !              sigmatm=sigmat+dsigmate
    !              yield=abs(sigmatm)-tand(phaib+alfab)*sigman
    !            write(5,*)'sigmatm=',sigmatm,'phaib=',phaib,'alfa=',alfa,'tand(phaib+alfa)*sigman=',tand(phaib+alfa)*sigman
    !              if(yield>=eps)loading=2
    !         endif
    !
    !      elseif(state==2.and.loading==2)then
    !
    !         loading=2
    !         if(tutm*tut0>0..and.(abs(tutm)>abs(tut0)))loading=-1
    !         if(loading==-1)then
    !              tutp=abs(tut0)
    !         elseif(loading==2)then
    !             !write(5,*)'sigmat=',sigmat,'tutm=',tutm,'sigmat*tutm=',sigmat*tutm
    !             if(sigmat*tutm>0.)loading=1
    !         endif
    !      endif
    !
    !            if(state==1.or.loading==-1)then
    !            tut=tutm
    !            sigmat=sigmat+dsigmate
    !            elseif(state==2)then
    !
    !                if(state0==1)then
    !                   ratio=(T0-abs(sigmat))/abs(dsigmate)
    !                   sigmat=sigmat+dsigmate*ratio
    !                   tut=tut+ratio*dut
    !                endif
    !
    !
    !                 dutx=dut
    !                 if(state0==1)then
    !                     dutx=(1-ratio)*dut
    !                 endif
    !
    !
    !                phai=phair
    !                !alfa=alfa0
    !             if(loading==2)phai=phaib
    !             !if(loading==2)alfa=alfab
    !
    !             if(state==2.and.(loading==2.and.loading0==-1))then
    !                 !sigmatm=sigmat+dsigmate
    !                 !yield=abs(sigmatm)-tand(phai+alfa)*sigman
    !                 ratio=(tand(phai+alfa)*sigman-abs(sigmat))/abs(dsigmate)
    !                   sigmat=sigmat+dsigmate*ratio
    !                   tut=tut+ratio*dut
    !                   dutx=(1-ratio)*dut
    !                   !write(5,*)'ratio=',ratio,'sigmat=',sigmat,'dutx=',dutx
    !             endif
    !
    !
    !                if(state==2.and.(loading==1.and.loading0==2))then
    !                 !sigmatm=sigmat+dsigmate
    !                 ratio=(tand(phai+alfa)*sigman-abs(sigmat))/abs(dsigmate)
    !                   sigmat=sigmat+dsigmate*ratio
    !                   tut=tut+ratio*dut
    !                   dutx=(1-ratio)*dut
    !                 endif
    !
    !             !
    !
    !             cx=0.
    !             if(i==1.and.j==1)then
    !             a=k1*(Tp-T0)/((k1-1)*(Up-U0))
    !             b=1/((k1-1)*(Up-U0)**k1)
    !             cx=a*(1-((tut-u0)/(up-u0))**k1)*(1-sigman/sigmac)/((1+b*(tut-u0)**k1)**2)
    !             endif
    !             AA=tand(phair)*Kn*tand(alfa)+Kt+(Tr-T0)/(Ur-U0)
    !
    !             !write(5,*)'aa=',aa,'cx=',cx
    !
    !             Dep(1,1)=Kt-Kt*Kt/AA+cx
    !             Dep(1,2)=-tand(phair)*Kn*Kt/AA
    !             Dep(2,1)=-Kn*Kt*tand(alfa)/AA
    !             Dep(2,2)=Kn-tand(phair)*Kn*Kn*tand(alfa)/AA
    !
    !
    !
    !             !write(5,*)'Dep1=',dep(1,1),dep(1,2)
    !             !write(5,*)'Dep2=',dep(2,1),dep(2,2)
    !             dun=-Dep(2,1)*dutx/Dep(2,2)    !dun=(a4*Kt/(a1*kt+xm*Q))*dut
    !             !write(5,*)'dut=',dut,'dun=',dun
    !             dsigmat=Dep(1,1)*dutx+Dep(1,2)*dun
    !             dsigman=Dep(2,1)*dutx+Dep(2,2)*dun
    !             !write(5,*)'dsigmat=',dsigmat,'t1=',Dep(1,1)*dut,'t2=',Dep(1,2)*dun,'dsigman=',dsigman
    !             sigmat=sigmat+dsigmat
    !             Wp=Wp+sigmat*dutx
    !             alfa=alfa*exp(-lamda*Wp)
    !             !write(5,*)'lamda*Wp=',lamda*Wp,'alfa=',alfa
    !              tut=tut+dutx
    !              tun=tun+dun
    !
    !
    !            endif
    !      tut0=tut
    !        !write(chk_unit,*)'tut*1000,tun*1000,sigmat,sigman,alfa,state,loading'
    !        write(chk_unit,10)tut,tun,sigmat,sigman,alfa,state,loading
    !         state0=state
    !         loading0=loading
    !
    !           end do
    !        end do
    !    end do
    !
    !10 format(5e15.3,2i10)
    !
    !
    !  end subroutine dep_joint_xwg
    !!!!!!!!!!!!!!!!

    subroutine character_softening_loading(xlwmodel,wx,w0,w1,sigmanc,k0,ft,sig1,w2,ft1)  !软化加载

    integer(ink)  xlwmodel
    real(irk) wx,w0,sigmanc,k0,xi0,ft,c1,c2,w1,sig1,w2,ft1   !w2,ft1  2017/04/03

    c1=1.0;c2=5.64
    if(xlwmodel==1)then
        xi0=wx/w0
        sigmanc=(1-xi0)*ft
        k0=-ft/w0
    elseif(xlwmodel==2)then !Bilinear sofening , from Petersson
        if(w1<wx.and.wx<=w0)then
            sigmanc=((w0-wx)/(w0-w1))*sig1
            k0=-sig1/(w0-w1)
        else !if(w1>0..and.wx<=w1)then
            sigmanc=(1.-wx/w1)*(ft-sig1)+sig1
            k0=-(ft-sig1)/w1
        endif
    elseif(xlwmodel==3)then !Bilinear sofening , from Petersson
        sigmanc=(((1.+(wx/w0)**3)*exp(-5.64*wx/w0))-(wx/w0)*7.105773e-3)*ft
        k0=((1.+(wx/w0)**3)*(-5.64/w0)+3.*wx**2/(w0**3))*exp(-5.64*wx/w0)-7.105773e-3/w0
        k0=k0*ft
    elseif(xlwmodel==4)then !cornelissen 颜天佑论文（固体力学学报）
        sigmanc=((1+(c1*wx/w0)**3)*exp(-c2*wx/w0)-wx/w0*(1+c1**3)*exp(-c2))*ft
        k0=((1.+(c1*wx/w0)**3)*(-c2/w0)+3.*c1**3*wx**2/(w0**3))*exp(-c2*wx/w0)-(1+c1**3)*exp(-c2)/w0
        k0=k0*ft
    elseif(xlwmodel==5)then ! Jiaji Du,Albert S. Kobayashi and Neil M. Hawkins, FEM DYNAMIC FRACTURE ANALYSIS OF CONCRETE BEAMS
        ! Journal of Engineering Mechanics, Vol. 115, No. 10, October, 1989
        write(7,*)'wx=',wx,'w0,w1,w2=',w0,w1,w2,'ft=',ft,'ft1=',ft1

        if(wx<=w1)then
            sigmanc=ft
            k0=-.1*ft/w1
        elseif(wx<=w2)then
            sigmanc=ft+(ft1-ft)*(wx-w1)/(w2-w1)
            k0=(ft1-ft)/(w2-w1)
        elseif(wx<w0)then
            sigmanc=ft1+(0-ft1)*(wx-w2)/(w0-w2)
            k0=-ft1/(w0-w2)
        elseif(wx>=w0)then
            sigmanc=0.01
            k0=-.02*ft/w1
        endif
    endif
    write(7,*)'wx=',wx,'sigmanc=',sigmanc


    end subroutine character_softening_loading


    subroutine character_softening_unloading(xlwmodel,wx,w0,w1,sigmanc,k0,ft,wxu,sig1,w2,ft1)  !软化加载

    integer(ink)  xlwmodel
    real(irk) wx,w0,sigmanc,k0,xi0,ft,wxu,sigmac,w1,sig1,c1,c2,alfac,w2,ft1

    c1=1.0;c2=5.64;alfac=0.35

    if(xlwmodel<=3)then
        if(xlwmodel==1)then
            xi0=wx/w0
            sigmanc=(1-xi0)*ft
        elseif(xlwmodel==2)then
            if(w1<wx.and.wx<=w0)then
                sigmanc=((w0-wx)/(w0-w1))*sig1
            else !if(w1>0..and.wx0<=w1)then
                sigmanc=(1.-wx/w1)*(ft-sig1)+sig1
            endif
        elseif(xlwmodel==5)then
            if(w1>wx)then
                sigmanc=ft
            elseif(w1<=wx.and.wx<w2)then
                sigmanc=ft+(ft1-ft)*(wx-w1)/(w2-w1)
            elseif(wx<=w0)then !if(w1>0..and.wx0<=w1)then
                sigmanc=ft1+(0-ft1)*(wx-w2)/(w0-w2)
            endif
        elseif(xlwmodel==3)then !Bilinear sofening , from Petersson
            sigmanc=(((1.+(wx/w0)**3)*exp(-5.64*wx/w0))-(wx/w0)*7.105773e-3)*ft
        endif
        k0=sigmanc/wx
    endif

    if(xlwmodel==4)then
        sigmac=((1+(c1*wxu/w0)**3)*exp(-c2*wxu/w0)-wxu/w0*(1+c1**3)*exp(-c2))*ft
        sigmanc=wx/wxu*(sigmac-alfac*(sigmac-ft))+alfac*(sigmac-ft)
        k0=1/wxu*(sigmac-alfac*(sigmac-ft))
    endif

    end subroutine character_softening_unloading


    subroutine character_unloading_loading(xlwmodel,wx,w0,w1,sigmanc,k0,ft,wxu,sigmad,wd)  !软化加载

    integer(ink)  xlwmodel
    real(irk) wx,w0,sigmanc,k0,xi0,ft,wxu,sigmac,sigmae,wxe,sigmad,wd,w1,c1,c2,alfac,betac,gamac

    c1=1.0;c2=5.64;alfac=0.35;betac=0.05

    if(xlwmodel==4)then
        sigmac=((1+(c1*wxu/w0)**3)*exp(-c2*wxu/w0)-wxu/w0*(1+c1**3)*exp(-c2))*ft
        k0=((1.+(c1*wxu/w0)**3)*(-c2/w0)+3.*c1**3*wxu**2/(w0**3))*exp(-c2*wxu/w0)-(1+c1**3)*exp(-c2)/w0
        k0=k0*ft
        sigmae=(1-betac)*sigmac
        write(7,*)'sigmae=',sigmae
        wxe=(sigmae-sigmac)/k0+wxu
        gamac=1./(1+1.2*wxe/wxu)
        if((wx-wd)/(wxe-wd)<1.e-10)then
            sigmanc=sigmad
        else
            sigmanc=((wx-wd)/(wxe-wd))**gamac*(sigmae-sigmad)+sigmad
        endif
        if((wx-wd)<1.e10)then
            k0=(sigmae-sigmad)/((wxe-wd)**gamac)
        else
            k0=gamac*(wx-wd)**(gamac-1)*(sigmae-sigmad)/((wxe-wd)**gamac)
        endif
    endif

    end subroutine character_unloading_loading

    subroutine dep_thin_layer(ic,e,miu,f,c,sigma,tt2)
    character(50)		::	text
    integer(ink)				::	ic,n,m
    real(irk)				::	sigmazz,sigmayz,sigmazx,alfa,f,c,i1,j2,ff,lambda,g,e,miu, &
        az,ayz,azx,cc,k,a,ft
    real(irk)				::  tt2(:,:),sigma(:)
    real(irk),allocatable	::	tt1(:,:),matrix(:,:),matrix_1(:,:)

    !read(1,*)text
    !read(1,*)e,miu,f,c					!弹模，泊松比，摩擦系数，凝聚力
    !read(1,*)text
    !read(1,*)sigmazz,sigmayz,sigmazx	!局部坐标系下法向应力、切向应力

    sigmazz=sigma(ndimn)
    sigmazx=sigma(1)
    if(ndimn==3)sigmayz=sigma(2)

    n=ndimn	;	m=0
    allocate(matrix(n,n),matrix_1(n,n),tt1(n,n))	!弹塑性系数矩阵，逆矩阵

    tt1=0.0		;	tt2=0.0
    matrix=0.0	;	matrix_1=0.0

    alfa=f/sqrt(9+12*f*f)					!dp准则系数alfa
    k=3*c/sqrt(9+12*f*f)					!dp准则系数k
    i1=(1.+2.*miu/(1.-miu))*sigmazz							!应力张量第一不变量
    j2=(2.*((1-2.*miu)*sigmazz/(1.-miu))**2 + 6.*sigmayz**2 + 6.*sigmazx**2)/6 !应力偏张量的第二不变量

    ff=alfa*i1+sqrt(j2)-k				!屈服判断

    lambda=e*miu/((1+miu)*(1-2*miu))	!拉梅常数
    g=e/(2*(1+miu))						!剪切模量

    if(ic==1)then		!线弹性阶段，胡克定律m=1
        matrix(ndimn,ndimn)=lambda+2*g
        matrix(1,1)=g
        if(ndimn==3) &
            matrix(2,2)=g
        m=1
    endif

    if(ic==2)then	!塑性屈服阶段m=2
        az=3*alfa*(lambda+2*g)
        ayz=g*sigmayz/(sqrt(j2))
        azx=g*sigmazx/(sqrt(j2))
        cc=az*az/(lambda+2*g)+(ayz*ayz+azx*azx)/g
        matrix(ndimn,ndimn)=lambda+2*g-az*az/cc
        matrix(1,1)=g-azx*azx/cc
        if(ndimn==3) &
            matrix(2,2)=g-ayz*ayz/cc

        matrix(ndimn,1)=-azx*az/cc	;	matrix(1,ndimn)=-azx*az/cc
        if(ndimn==3)then
            matrix(ndimn,2)=-ayz*az/cc	;	matrix(2,ndimn)=-ayz*az/cc
            matrix(2,1)=-azx*ayz/cc	;	matrix(1,2)=-azx*ayz/cc
        endif
        m=2
    endif



    !求逆~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    !求行列式a
    if(ndimn==3)then
        a= matrix(1,1)*matrix(2,2)*matrix(3,3)+matrix(2,1)*matrix(3,2)*matrix(1,3)+matrix(3,1)*matrix(1,2)*matrix(2,3)  &
            -matrix(3,1)*matrix(2,2)*matrix(1,3)-matrix(2,1)*matrix(1,2)*matrix(3,3)-matrix(1,1)*matrix(3,2)*matrix(2,3)
    elseif(ndimn==2)then
        a= matrix(1,1)*matrix(2,2)-matrix(2,1)*matrix(1,2)
    endif

    !检验矩阵是否可逆
    !if( abs(a) <=0.00001 .and. m/=3)then
    if( abs(a) <=0.01 .and. m/=3)then
        print *, '行列式=0'
        a=1.e-2
        !stop  ！2017/02/14
    endif

    !求矩阵的逆
    if(m==1 .or. m==2)then
        if(ndimn==3)then
            matrix_1(1,1)=( matrix(2,2)*matrix(3,3)-matrix(3,2)*matrix(2,3) )/a
            matrix_1(1,2)=( matrix(3,2)*matrix(1,3)-matrix(1,2)*matrix(3,3) )/a
            matrix_1(1,3)=( matrix(1,2)*matrix(2,3)-matrix(1,3)*matrix(2,2) )/a

            matrix_1(2,1)=( matrix(3,1)*matrix(2,3)-matrix(2,1)*matrix(3,3) )/a
            matrix_1(2,2)=( matrix(1,1)*matrix(3,3)-matrix(3,1)*matrix(1,3) )/a
            matrix_1(2,3)=( matrix(2,1)*matrix(1,3)-matrix(1,1)*matrix(2,3) )/a

            matrix_1(3,1)=( matrix(2,1)*matrix(3,2)-matrix(2,2)*matrix(3,1) )/a
            matrix_1(3,2)=( matrix(3,1)*matrix(1,2)-matrix(1,1)*matrix(3,2) )/a
            matrix_1(3,3)=( matrix(1,1)*matrix(2,2)-matrix(2,1)*matrix(1,2) )/a
        elseif(ndimn==2) then
            matrix_1(1,1)=matrix(2,2)/a
            matrix_1(2,2)=matrix(1,1)/a
            matrix_1(1,2)=-matrix(2,1)/a
            matrix_1(2,1)=-matrix(1,2)/a
        endif
    endif

    !if(m==3)then	!材料处于拉裂状态时，法向刚度为零，只记切向刚度，其弹塑性系数矩阵不可逆，此处假定其逆矩阵为0，不知是否合理
    !	matrix_1=0.0
    !endif

    tt1=matrix
    tt2=matrix_1

    deallocate(tt1,matrix,matrix_1)

    end subroutine dep_thin_layer


    subroutine dep_joints(En,Et,phai0,frictd,Fc,sigma,Dep)
    character(50)		::	text
    real(irk)				::	sigman,sigmat,xx,Cs,phai0,phai,Wp,qq,ff,frictd,frict,Fc,phai_sec,straintp,En,Et
    real(irk)				::  sigma(:),Dep(:,:)
    real(irk),allocatable	::	avecq(:),avecf(:),ee(:,:),mvect(:),epm(:,:)

    !read(1,*)text
    !read(1,*)e,miu,f,c					!弹模，泊松比，摩擦系数，凝聚力
    !read(1,*)text
    !read(1,*)sigmazz,sigmayz,sigmazx	!局部坐标系下法向应力、切向应力

    sigmat=abs(1)
    if(ndimn==3)sigmat=sqrt(sigma(1)**2+sigma(2)**2)
    sigman=(ndimn)

    Cs=0.0003*phai0*exp(37.87*sigman/Fc)
    phai_sec=.64*phai0*exp(-21.12*sigman/Fc)
    Wp=sigmat*straintp
    phai=phai_sec*exp(-Cs*Wp)
    frict=tand(frictd)



    allocate(avecq(ndimn),avecf(ndimn),ee(ndimn,ndimn),mvect(ndimn),epm(ndimn,ndimn))	!弹塑性系数矩阵，逆矩阵
    avecq=0.;avecf=0.;ee=0.;mvect=0.;epm=0.;dep=0.

    qq=sigmat-sigman*tand(phai)				!屈服判断
    ff=(sigmat-sigman*tand(phai0))-frict*(sigmat+sigman*tand(phai))


    avecq(ndimn)=-tand(phai)
    avecq(1)    =1.*sigma(1)/sigmat
    if(ndimn==3)avecq(2)=1.*sigma(2)/sigmat

    avecf(ndimn)=-tand(phai0)-frict
    avecf(1)=(1-frict*tand(phai))*sigma(1)/sigmat
    if(ndimn==3)avecf(2)=(1-frict*tand(phai))*sigma(1)/sigmat

    ee(ndimn,ndimn)=En
    ee(1,1)=Et
    if(ndimn==3)ee(2,2)=Et

    mvect=ee.x.avecq
    xx=avecf.d.mvect

    epm=avecq.o.avecf
    epm=epm.x.ee
    dep=ee.x.epm
    dep=dep/xx
    dep=ee-dep


    deallocate(avecq,avecf,ee,mvect,epm)

    end subroutine dep_joints


    !!!!!!!!!!!!!!!!!!!

    SUBROUTINE global_stif_profile_ctt(nevab,ldofs,estif)
    integer(ink) nevab,ldofs(:)
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum
    integer(ink) iintf,nintf,jintf,njntf	!!int2000
    real   (irk) facti,factj  !!int2000
    real   (irk) estif(:,:)


    do j= 1,nevab
        jdofn=ldofs(j)
        njntf=trans_bt(jdofn)%nintf
        do i=1,nevab
            idofn=ldofs(i)
            nintf=trans_bt(idofn)%nintf

            if(njntf==0.and.nintf==0) then !!1
                jeq  =totveq_bt(jdofn)
                ieq  =totveq_bt(idofn)
                if(jeq/=0.and.ieq/=0.and.ieq<=jeq) then
                    colum=iseq_bt(jeq)-jeq+ieq
                    global_stiff_bt(colum)=global_stiff_bt(colum)+    &
                        estif(i,j)
                    if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+    &
                        estif(j,i)
                endif
            elseif(njntf/=0.and.nintf==0) then !!2
                ieq  =totveq_bt(idofn)
                if(ieq/=0) then
                    do jintf=1,njntf
                        jeq =totveq_bt(trans_bt(jdofn)%listf(jintf))
                        factj=trans_bt(jdofn)%rintf(jintf)
                        if(jeq/=0.and.ieq<=jeq) then
                            colum=iseq_bt(jeq)-jeq+ieq
                            global_stiff_bt(colum)=global_stiff_bt(colum)+    &
                                estif(i,j)*factj
                            if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+    &
                                estif(j,i)*factj
                        endif
                    end do
                endif
            elseif(njntf==0.and.nintf/=0) then !!3
                jeq  =totveq_bt(jdofn)
                if(jeq/=0) then
                    do iintf=1,nintf
                        ieq =totveq_bt(trans_bt(idofn)%listf(iintf))
                        facti=trans_bt(idofn)%rintf(iintf)
                        if(ieq/=0.and.ieq<=jeq) then
                            colum=iseq_bt(jeq)-jeq+ieq
                            global_stiff_bt(colum)=global_stiff_bt(colum)+    &
                                estif(i,j)*facti
                            if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+    &
                                estif(j,i)*facti
                        endif
                    end do
                endif
            elseif(njntf/=0.and.nintf/=0) then !!4
                do iintf=1,nintf
                    ieq =totveq_bt(trans_bt(idofn)%listf(iintf))
                    facti=trans_bt(idofn)%rintf(iintf)
                    do jintf=1,njntf
                        jeq =totveq_bt(trans_bt(jdofn)%listf(jintf))
                        factj=trans_bt(jdofn)%rintf(jintf)
                        if(ieq/=0.and.jeq/=0.and.ieq<=jeq) then
                            colum=iseq_bt(jeq)-jeq+ieq
                            global_stiff_bt(colum)=global_stiff_bt(colum)+    &
                                estif(i,j)*facti*factj
                            if(nonsbt==1)global_stiff2_bt(colum)=global_stiff2_bt(colum)+    &
                                estif(j,i)*facti*factj
                        endif
                    end do
                end do
            endif  !!4
        end do
    end do
    END SUBROUTINE global_stif_profile_ctt

    !!!!!!!!!!!!!!!!!!!!!!!!ctt2005

    SUBROUTINE PROFILE

    character (32) text
    integer(ink) index,nevab,ielem,ieq,jeq,dijeq,ievab,jevab,ielgroup,jblks
    integer(ink) max_band,stiff_length,igroup,ilayer,iedge,bkind
    real   (irk) ylost
    integer(ink) aelemf,aelems,ipea1,ipea2,jgroup !!ifs2000
    integer(ink) nintf,njntf,iintf,jintf !!int2000
    integer(ink),pointer::listf(:) !!int2000
    real   (irk),pointer::rintf(:) !!int2000
    integer(ink),allocatable::ldofs(:)
    real   (irk),allocatable ::resultm(:)
    integer(ink) itotv,jtotv,ipoin,np_unode   !! stablize

    !!for LDU direct method with symmetric matrix
    Select Case ( Operation)

    Case ('SET')
        if(restart==1)   then
            do jblks=1,iblks-1
                read(solveunit,*)text
                read(solveunit,*)text
            end do
        end if
        if(meshc==1.or.rmesh/=0)rewind(solveunit)
        if(Bparameter/=0)rewind(solveunit)  !20190810
        Read (solveunit,*,iostat=yl_ios,iomsg=yl_msg) text
        call diag_check_read(yl_ios,yl_msg,RD_SOL_PROFILE_title_1,0)
        Read (solveunit,*,iostat=yl_ios,iomsg=yl_msg) iafile,icond,ipdchk,ising
        call diag_check_read(yl_ios,yl_msg,RD_SOL_PROFILE_profile_control,0)
        if(iafile/=0)open(iafile,file='forpivots',form='unformatted')
        call totv_to_eq
        if(neq==0) return   !2017/11/19

        if(allocated(iseq))deallocate(iseq)
        allocate(iseq(neq))

        iseq=0
        DO igroup = 1,ngroup

            if(appear(igroup)>0) then
                ielem = group(igroup)%list(1)
                nevab = size(element(ielem)%ldofs)
                index = group(igroup)%index
                if(nlayer==2)ilayer= group(igroup)%ilayer
                allocate(ldofs(nevab))
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                DO ielgroup = 1, group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(ice0(ielem)==1) goto 1
                    nevab = size(element(ielem)%ldofs)
                    ldofs=element(ielem)%ldofs

                    if(nlayer/=2) then
                        !!int2000
                        do ievab=1,nevab
                            nintf=trans(ldofs(ievab))%nintf
                            !write(7,*)'ielem=',ielem,'ievab=',ievab,'nintf=',nintf
                            !write(7,*)'listif=',trans(ldofs(ievab))%listf(:)
                            do jevab=1,nevab
                                njntf=trans(ldofs(jevab))%nintf
                                !write(7,*)'ielem=',ielem,'jevab=',jevab,'njntf=',njntf
                                ! write(7,*)'listjf=',trans(ldofs(jevab))%listf(:)
                                if(nintf==0.and.njntf==0) then !!1
                                    ieq=totveq(ldofs(ievab))
                                    jeq=totveq(ldofs(jevab))
                                    if(ieq/=0.and.jeq/=0) then
                                        dijeq=ieq-jeq
                                        if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                    endif
                                else if(nintf/=0.and.njntf==0)then  !!2
                                    do iintf=1,nintf
                                        ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                        jeq=totveq(ldofs(jevab))
                                        if(ieq/=0.and.jeq/=0) then
                                            dijeq=ieq-jeq
                                            if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                        endif
                                    end do
                                else if(nintf==0.and.njntf/=0)then  !!3
                                    ieq=totveq(ldofs(ievab))
                                    do jintf=1,njntf
                                        jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                        if(ieq/=0.and.jeq/=0) then
                                            dijeq=ieq-jeq
                                            if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                        endif
                                    end do
                                else if(nintf/=0.and.njntf/=0)then !!4
                                    do iintf=1,nintf
                                        ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                        do jintf=1,njntf
                                            jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                            if(ieq/=0.and.jeq/=0) then
                                                dijeq=ieq-jeq
                                                if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    end do
                                endif
                            end do
                        end do
                        !!int2000

                    else

                        if(ilayer==1) then
                            do ievab=1,nevab
                                ieq=totveq(ldofs(ievab))
                                if(ieq/=0.and.ieq.le.neq_layer1) then
                                    do jevab=1,nevab
                                        jeq=totveq(ldofs(jevab))
                                        dijeq=ieq-jeq
                                        if(jeq/=0.and.jeq.le.neq_layer1.and.dijeq.gt.iseq(ieq))then
                                            iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                        endif
                                    end do
                                endif
                            end do
                        else if(ilayer==2) then
                            do ievab=1,nevab
                                ieq=totveq(ldofs(ievab))
                                if(ieq/=0.and.ieq.gt.neq_layer1) then
                                    do jevab=1,nevab
                                        jeq=totveq(ldofs(jevab))
                                        dijeq=ieq-jeq
                                        if(jeq/=0.and.jeq.gt.neq_layer1.and.dijeq.gt.iseq(ieq))then
                                            iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                        endif
                                    end do
                                endif
                            end do
                        endif ! for ilayer
                    endif  ! for nlayer
1                   continue
                end do   ! ielgroup
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                if(rmesh>0.and.nelem1>0)then
                    DO ielgroup = 1, group1(igroup)%nelgroup
                        ielem = group1(igroup)%list(ielgroup)
                        if(jce1(ielem)==1) goto 2
                        nevab = size(element1(ielem)%ldofs)
                        ldofs=element1(ielem)%ldofs

                        if(nlayer/=2) then
                            !!int2000
                            do ievab=1,nevab
                                nintf=trans(ldofs(ievab))%nintf
                                do jevab=1,nevab
                                    njntf=trans(ldofs(jevab))%nintf
                                    if(nintf==0.and.njntf==0) then !!1
                                        ieq=totveq(ldofs(ievab))
                                        jeq=totveq(ldofs(jevab))
                                        if(ieq/=0.and.jeq/=0) then
                                            dijeq=ieq-jeq
                                            if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                        endif
                                    else if(nintf/=0.and.njntf==0)then  !!2
                                        do iintf=1,nintf
                                            ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                            jeq=totveq(ldofs(jevab))
                                            if(ieq/=0.and.jeq/=0) then
                                                dijeq=ieq-jeq
                                                if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    else if(nintf==0.and.njntf/=0)then  !!3
                                        ieq=totveq(ldofs(ievab))
                                        do jintf=1,njntf
                                            jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                            if(ieq/=0.and.jeq/=0) then
                                                dijeq=ieq-jeq
                                                if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    else if(nintf/=0.and.njntf/=0)then !!4
                                        do iintf=1,nintf
                                            ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                            do jintf=1,njntf
                                                jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                                if(ieq/=0.and.jeq/=0) then
                                                    dijeq=ieq-jeq
                                                    if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                                endif
                                            end do
                                        end do
                                    endif
                                end do
                            end do
                            !!int2000

                        else

                            if(ilayer==1) then
                                do ievab=1,nevab
                                    ieq=totveq(ldofs(ievab))
                                    if(ieq/=0.and.ieq.le.neq_layer1) then
                                        do jevab=1,nevab
                                            jeq=totveq(ldofs(jevab))
                                            dijeq=ieq-jeq
                                            if(jeq/=0.and.jeq.le.neq_layer1.and.dijeq.gt.iseq(ieq))then
                                                iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    endif
                                end do
                            else if(ilayer==2) then
                                do ievab=1,nevab
                                    ieq=totveq(ldofs(ievab))
                                    if(ieq/=0.and.ieq.gt.neq_layer1) then
                                        do jevab=1,nevab
                                            jeq=totveq(ldofs(jevab))
                                            dijeq=ieq-jeq
                                            if(jeq/=0.and.jeq.gt.neq_layer1.and.dijeq.gt.iseq(ieq))then
                                                iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    endif
                                end do
                            endif ! for ilayer
                        endif  ! for nlayer
2                       continue
                    end do   ! ielgroup
                endif
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
                if(rmesh>0.and.nelem2>0)then
                    DO ielgroup = 1, group2(igroup)%nelgroup
                        ielem = group2(igroup)%list(ielgroup)
                        nevab = size(element2(ielem)%ldofs)
                        ldofs=element2(ielem)%ldofs

                        if(nlayer/=2) then
                            !!int2000
                            do ievab=1,nevab
                                nintf=trans(ldofs(ievab))%nintf
                                do jevab=1,nevab
                                    njntf=trans(ldofs(jevab))%nintf
                                    if(nintf==0.and.njntf==0) then !!1
                                        ieq=totveq(ldofs(ievab))
                                        jeq=totveq(ldofs(jevab))
                                        if(ieq/=0.and.jeq/=0) then
                                            dijeq=ieq-jeq
                                            if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                        endif
                                    else if(nintf/=0.and.njntf==0)then  !!2
                                        do iintf=1,nintf
                                            ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                            jeq=totveq(ldofs(jevab))
                                            if(ieq/=0.and.jeq/=0) then
                                                dijeq=ieq-jeq
                                                if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    else if(nintf==0.and.njntf/=0)then  !!3
                                        ieq=totveq(ldofs(ievab))
                                        do jintf=1,njntf
                                            jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                            if(ieq/=0.and.jeq/=0) then
                                                dijeq=ieq-jeq
                                                if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    else if(nintf/=0.and.njntf/=0)then !!4
                                        do iintf=1,nintf
                                            ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                            do jintf=1,njntf
                                                jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                                if(ieq/=0.and.jeq/=0) then
                                                    dijeq=ieq-jeq
                                                    if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                                endif
                                            end do
                                        end do
                                    endif
                                end do
                            end do
                            !!int2000

                        else

                            if(ilayer==1) then
                                do ievab=1,nevab
                                    ieq=totveq(ldofs(ievab))
                                    if(ieq/=0.and.ieq.le.neq_layer1) then
                                        do jevab=1,nevab
                                            jeq=totveq(ldofs(jevab))
                                            dijeq=ieq-jeq
                                            if(jeq/=0.and.jeq.le.neq_layer1.and.dijeq.gt.iseq(ieq))then
                                                iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    endif
                                end do
                            else if(ilayer==2) then
                                do ievab=1,nevab
                                    ieq=totveq(ldofs(ievab))
                                    if(ieq/=0.and.ieq.gt.neq_layer1) then
                                        do jevab=1,nevab
                                            jeq=totveq(ldofs(jevab))
                                            dijeq=ieq-jeq
                                            if(jeq/=0.and.jeq.gt.neq_layer1.and.dijeq.gt.iseq(ieq))then
                                                iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                            endif
                                        end do
                                    endif
                                end do
                            endif ! for ilayer
                        endif  ! for nlayer
                    end do   ! ielgroup
                endif
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                deallocate(ldofs)
                !! stablize
                if(stabpw==1) then
                    do ipoin=1,group(igroup)%np_unode
                        np_unode=group(igroup)%unode(ipoin)%np_unode
                        do ievab=1,np_unode
                            itotv=nodfn(ndimn+1,group(igroup)%unode(ipoin)%patch_nod(ievab))
                            ieq=totveq(itotv)
                            if(ieq/=0) then
                                do jevab=1,np_unode
                                    jtotv=nodfn(ndimn+1,group(igroup)%unode(ipoin)%patch_nod(jevab))
                                    jeq=totveq(jtotv)
                                    dijeq=ieq-jeq
                                    if(jeq/=0.and.dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                end do
                            endif
                        end do
                    end do
                endif
                !! end of stablize

            end if !do while

        end do    !! end do ngroup

        !! semi_infinity
        if(ground_inf/=0) then

            do ievab=1,ndofn_space
                itotv=ldofs_space(ievab)
                ieq=totveq(itotv)
                if(ieq/=0) then
                    do jevab=1,ndofn_space
                        jtotv=ldofs_space(jevab)
                        jeq=totveq(jtotv)
                        dijeq=ieq-jeq
                        if(jeq/=0.and.dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                    end do
                endif
            end do
        endif
        !! end of semi_infinity

        !!ifs2000
        if(type_problem/='Q'.and.type_problem/='E') then
            do ielem=1,nifsgroup
                aelemf=tifs(ielem)%aelemf
                aelems=tifs(ielem)%aelems
                ipea1=0
                igroup=element(aelemf)%group
                if(appear(igroup)>0)ipea1=1
                ipea2=1
                if(aelems/=0) then
                    jgroup=element(aelems)%group
                    if(appear(jgroup)<=0)ipea2=0
                endif
                if(ipea1==1.and.ipea2==1) then
                    nevab=size(tifs(ielem)%ldofs)
                    do ievab=1,nevab
                        do jevab=1,nevab
                            ieq=totveq(tifs(ielem)%ldofs(ievab))
                            jeq=totveq(tifs(ielem)%ldofs(jevab))
                            if(ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq
                            endif
                        end do
                    end do
                endif
            end do
        endif
        !!ifs2000

        !!ifs2006 zhao, 06/03/29
        if (type_problem/='Q'.and.type_problem/='E') then
            do iedge=1,ifsnedge
                bkind=ifsedges(iedge)%bkind
                if(bkind/=2)cycle
                aelemf=ifsedges(iedge)%felem
                aelems=ifsedges(iedge)%selem
                ipea1=0
                igroup=element(aelemf)%group
                if(appear(igroup)>0)ipea1=1
                ipea2=1
                if (aelems/=0) then
                    jgroup=element(aelems)%group
                    if(appear(jgroup)<=0)ipea2=0
                endif
                if(ipea1==1.and.ipea2==1) then
                    nevab=size(ifsedges(iedge)%ldofs)
                    do ievab=1,nevab
                        do jevab=1,nevab
                            ieq=totveq(ifsedges(iedge)%ldofs(ievab))
                            jeq=totveq(ifsedges(iedge)%ldofs(jevab))
                            if(ieq/=0.and.jeq/=0) then
                                dijeq=ieq-jeq
                                if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq
                            endif
                        end do
                    end do
                endif
            end do
        endif

        !!ifs2006 zhao, 06/03/29

        Max_band=0
        Iseq(1)=1
        DO  Ieq=2,Neq
            IF(Max_band<Iseq(Ieq))then
                Max_band=Iseq(Ieq)
            endif
            Iseq(Ieq)=Iseq(Ieq)+Iseq(Ieq-1)+1
        end do
        Max_band=Max_band+1
        Stiff_length=Iseq(neq)
        write(chkunit,*)'No. of equations        =',neq
        write(chkunit,*)'Max half band width     =',Max_band
        write(chkunit,*)'length half stiff matrix=',Stiff_length
        if(allocated(global_stiff1))deallocate(global_stiff1)
        if(allocated(rvector))    deallocate(rvector)
        allocate(global_stiff1(Stiff_length))
        global_stiff1=0.0
        allocate(rvector(neq))

        if(nlayer/=2)  then
            if(nonsym.eq.1)then
                allocate(global_stiff2(Stiff_length))
                global_stiff2=0.0
            endif
        else if(nonsym/=0) then
            if(nonsym.eq.1)allocate(global_stiff2(iseq(neq_layer1)))
            if(nonsym.eq.2)allocate(global_stiff2(iseq(neq)))
            global_stiff2=0.0
        endif
    case ('FACTORIZE')
        if(nlayer/=2) then
            if(nonsym.eq.0)call skfacs(global_stiff1,iseq,ylost,iafile)
            if(nonsym.eq.1)call skfaca(global_stiff1,global_stiff2,iseq,iafile)
            if(iafile.ne.0)call pivots(global_stiff1,global_stiff2,iseq,nonsym,  &
                ylost,icond,ipdchk,ising,iafile)
        else
            if(nonsym==0) then
                if(kresl_layer1==1) &
                    call    skfacs_layer(global_stiff1,iseq,1)
                if(kresl_layer2==1) &
                    call    skfacs_layer(global_stiff1,iseq,2)
            else
                if(kresl_layer1==1) &
                    call    skfaca_layer(global_stiff1,global_stiff2,iseq,iafile,1)
                if(kresl_layer2==1.and.nonsym==1) &
                    call    skfacs_layer(global_stiff1,iseq,2)
                if(kresl_layer2==1.and.nonsym==2) &
                    call    skfaca_layer(global_stiff1,global_stiff2,iseq,iafile,2)
            endif
        endif
    case ('SOLVE')
        if(neq==0)then  !2017/11/27
            if(allocated(result))    deallocate(result)  !2017/11/27
            allocate(result(ntotv))  !2017/11/27
            result=0.  !2017/11/27
            goto 100  !2017/11/27
        endif   !2017/11/27
        if(nlayer/=2) then
            if(allocated(result))    deallocate(result)
            allocate(result(neq))
            result=rvector
            if(nonsym.eq.0) then
                call  sksols(global_stiff1,result,iseq)
            else
                call  sksola(global_stiff1,result,global_stiff2,iseq)
            end if

            !rvector=result !zhao 05/09/03 ctt2005
            ! or if(ngaps==0)rvector=result

            allocate(resultm(ntotv))
            !        where(iffix==0)
            !        resultm=result(totveq)
            !        elsewhere
            !        resultm=0.0
            !        endwhere
            !!int2000

            !	write(7,*)'displacement increment'
            !	do itotv=1,neq
            !	write(7,*)itotv,result(itotv)
            !	end do
            resultm=0.
            do itotv=1,ntotv
                nintf=trans(itotv)%nintf
                if(iffix(itotv)==0.and.nintf==0) then
                    resultm(itotv)=result(totveq(itotv))
                elseif(nintf/=0) then
                    listf=>trans(itotv)%listf
                    rintf=>trans(itotv)%rintf
                    do jtotv=1,nintf
                        if(totveq(listf(jtotv))>0)then
                            resultm(itotv)=resultm(itotv)+result(totveq(listf(jtotv)))*rintf(jtotv)
                            !write(7,*)'itotv=',itotv,'jtotv=',listf(jtotv),'result=',result(totveq(listf(jtotv)))
                        endif

                    enddo

                    !write(7,*)'itotv=',itotv,'resultm=',resultm(itotv)
                    nullify(listf,rintf)
                endif
            end do
            !!int2000

            deallocate(result)
            allocate(result(ntotv))
            result=resultm
            deallocate(resultm)

        else
            call layer_iteration
        endif
100     continue
    end select
    contains

    subroutine layer_iteration
    integer(ink) iitcg,mitcg,itotv,ieq,iciseq,nciseq,keq,   &
        index,ielem,nevab,igroup,idofn,jtotv
    integer(ink),allocatable::ldofs(:)
    real   (irk) alfa,beta,prod1,rnorm0,rnorm1,ratio,tolcg
    real   (irk),allocatable::result1(:),apcg(:),pcg(:),fcg(:), &
        estif(:,:),vtemp1(:),vtemp2(:),scg(:), &
        resultm(:)
    save rnorm0
    mitcg=500
    tolcg=1.e-4
    if(kstat==2.and.iiter==1)tolcg=1.e-3
    if(allocated(result))    deallocate(result)
    allocate(result(neq),result1(ntotv),apcg(neq),pcg(neq),scg(neq),fcg(neq))
    result=0.

    apcg  = 0.0_irk
    pcg   = 0.0_irk
    fcg   = 0.0_irk


    !		write(chkunit,*)'iblks=',iblks,'iiter=',iiter,'rvector='
    !		do ieq=1,neq
    !		write(chkunit,*)ieq,rvector(ieq)
    !		end do
    fcg=rvector


    !      ------  Set rnorm0 to its value at 1st iteration
    if(iiter==1) &
        rnorm0 = maxval( abs(fcg) )
    !!!xxxx
    if((kresl_layer1/=0.or.kresl_layer2/=0).and.solver_iter==2) then !7
        do itotv=1,ntotv
            pcg_stiff(itotv)%nonzero(:)=0.
        end do

        DO igroup = 1,ngroup                              !6
            if(appear(igroup)>0)    then                    !5
                index = group(igroup)%index
                ielem = group(igroup)%list(1)
                nevab = size(element(ielem)%field(1)%ldofs_f)
                allocate ( estif(nevab,nevab), ldofs(nevab) )
                DO ielgroup = 1, group(igroup)%nelgroup    !4
                    ielem = group(igroup)%list(ielgroup)
                    ldofs = element(ielem)%field(1)%ldofs_f
                    estif = element(ielem)%field(1)%khandmc(1)%fstif
                    do ievab=1,nevab
                        ieq=ldofs(ievab)
                        nciseq=pcg_stiff(ieq)%nciseq
                        do jevab=1,nevab            ! 1
                            jeq=ldofs(jevab)
                            if(ieq==jeq) then
                                pcg_stiff(ieq)%nonzero(nciseq+1)=  &
                                    pcg_stiff(ieq)%nonzero(nciseq+1)+estif(ievab,jevab)
                            else
                                do iciseq=1,nciseq
                                    keq=pcg_stiff(ieq)%list(iciseq)
                                    if(jeq==keq) then
                                        pcg_stiff(ieq)%nonzero(iciseq)=  &
                                            pcg_stiff(ieq)%nonzero(iciseq)+estif(ievab,jevab)
                                        goto 10
                                    endif
                                end do
10                              continue
                            endif
                        end do ! 1
                    end do !3
                end do !4
                deallocate(estif,ldofs)
            endif !5
        end do !6

    endif !7
    print *,'af assem pcg'
    !!xxxx

    DO IITCG = 1,MITCG

        if(iitcg==1) then
            scg(1:neq_layer1)=fcg(1:neq_layer1)
            if(nonsym==0) then
                call sksols_layer(global_stiff1,scg,iseq,1)
            else
                call sksola_layer(global_stiff1,scg,global_stiff2,iseq,1)
            endif
            scg(neq_layer1+1:neq)=fcg(neq_layer1+1:neq)
            if(nonsym.le.1) then
                call sksols_layer(global_stiff1,scg,iseq,2)
            else
                call sksola_layer(global_stiff1,scg,global_stiff2,iseq,2)
            endif
            pcg=scg
        endif


        !      ------  Obtains K.p
        apcg=0.0

        result1=0.
        do itotv=1,ntotv


            ieq=totveq(itotv)
            if(ieq/=0)result1(itotv)=pcg(ieq)
        end do


        if(solver_iter==2) then
            do itotv=1,ntotv
                ieq=totveq(itotv)
                if(ieq/=0) then
                    nciseq=pcg_stiff(itotv)%nciseq
                    apcg(ieq)=apcg(ieq)+pcg_stiff(itotv)%nonzero(nciseq+1)*result1(itotv)
                    do iciseq=1,nciseq
                        jtotv=pcg_stiff(itotv)%list(iciseq)
                        apcg(ieq)=apcg(ieq)+pcg_stiff(itotv)%nonzero(iciseq)*result1(jtotv)
                    end do
                endif
            end do
        else
            DO igroup = 1,ngroup

                if(appear(igroup)>0)  then

                    index = group(igroup)%index
                    ielem = group(igroup)%list(1)
                    nevab = size(element(ielem)%field(1)%ldofs_f)
                    allocate ( estif(nevab,nevab), ldofs(nevab) )
                    allocate ( vtemp1(nevab), vtemp2(nevab) )
                    DO ielgroup = 1, group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        ldofs = element(ielem)%field(1)%ldofs_f
                        estif = element(ielem)%field(1)%khandmc(1)%fstif
                        vtemp1= result1(ldofs)
                        vtemp2= MATMUL (estif,vtemp1)
                        do idofn=1,nevab
                            ieq=totveq(ldofs(idofn))
                            if(ieq/=0)apcg (ieq) = apcg(ieq) + vtemp2(idofn)
                        end do
                    ENDDO
                    deallocate ( estif, ldofs, vtemp1, vtemp2)
                endif
            end do  !!for igroup
        endif

        prod1 = dot_product (fcg,scg)
        alfa  = prod1/dot_product(pcg,apcg)
        result = result + alfa*pcg
        fcg   = fcg - alfa*apcg
        scg(1:neq_layer1)=fcg(1:neq_layer1)
        if(nonsym==0) then
            call sksols_layer(global_stiff1,scg,iseq,1)
        else
            call sksola_layer(global_stiff1,scg,global_stiff2,iseq,1)
        endif
        scg(neq_layer1+1:neq)=fcg(neq_layer1+1:neq)
        if(nonsym.le.1) then
            call sksols_layer(global_stiff1,scg,iseq,2)
        else
            call sksola_layer(global_stiff1,scg,global_stiff2,iseq,2)
        endif
        beta  = dot_product ( fcg,scg ) / prod1
        pcg   = scg + beta*pcg
        rnorm1= maxval (abs(fcg))
        ratio = rnorm1/rnorm0
        print *,'iitcg=',iitcg,'ratio=',ratio
        if (ratio <= tolcg ) goto 1
    ENDDO
1   continue
    write(chkunit,*)'iitcg=',iitcg,'ratio=',ratio
    deallocate(apcg,result1,pcg,scg,fcg)
    rvector=result
    allocate(resultm(ntotv))
    where(iffix==0)
        resultm=result(totveq)
    elsewhere
        resultm=0.0
    endwhere
    deallocate(result)
    allocate(result(ntotv))
    result=resultm
    deallocate(resultm)
    end subroutine layer_iteration
    !*******+

    end subroutine PROFILE

    SUBROUTINE PROFILEW !freq2006

    character (32) text
    integer(ink) index,nevab,ielem,ieq,jeq,dijeq,ievab,jevab,ielgroup,jblks
    integer(ink) max_band,stiff_length,igroup,ilayer
    real   (irk) ylost
    integer(ink) aelemf,aelems,ipea1,ipea2,jgroup !!ifs2000
    integer(ink) nintf,njntf,iintf,jintf !!int2000
    integer(ink),pointer::listf(:) !!int2000
    real   (irk),pointer::rintf(:) !!int2000
    integer(ink),allocatable::ldofs(:)
    complex   (irk),allocatable ::resultm(:)
    integer(ink) itotv,jtotv,ipoin,np_unode   !! stablize

    !!for LDU direct method with symmetric matrix


    Select Case ( Operation)

    Case ('SET')
        if(restart==1)   then
            do jblks=1,iblks-1
                read(solveunit,*)text
                read(solveunit,*)text
            end do
        end if

        call totv_to_eq
        if(neq==0) return   !2017/11/19

        if(allocated(iseq))deallocate(iseq)
        allocate(iseq(neq))

        iseq=0
        DO igroup = 1,ngroup

            if(appear(igroup)>0) then
                ielem = group(igroup)%list(1)
                nevab = size(element(ielem)%ldofs)
                index = group(igroup)%index
                allocate(ldofs(nevab))
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                DO ielgroup = 1, group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(ice0(ielem)==1) goto 1
                    nevab = size(element(ielem)%ldofs)
                    ldofs=element(ielem)%ldofs

                    !!int2000
                    do ievab=1,nevab
                        nintf=trans(ldofs(ievab))%nintf
                        do jevab=1,nevab
                            njntf=trans(ldofs(jevab))%nintf
                            if(nintf==0.and.njntf==0) then !!1
                                ieq=totveq(ldofs(ievab))
                                jeq=totveq(ldofs(jevab))
                                if(ieq/=0.and.jeq/=0) then
                                    dijeq=ieq-jeq
                                    if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                endif
                            else if(nintf/=0.and.njntf==0)then  !!2
                                do iintf=1,nintf
                                    ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                    jeq=totveq(ldofs(jevab))
                                    if(ieq/=0.and.jeq/=0) then
                                        dijeq=ieq-jeq
                                        if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                    endif
                                end do
                            else if(nintf==0.and.njntf/=0)then  !!3
                                ieq=totveq(ldofs(ievab))
                                do jintf=1,njntf
                                    jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                    if(ieq/=0.and.jeq/=0) then
                                        dijeq=ieq-jeq
                                        if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                    endif
                                end do
                            else if(nintf/=0.and.njntf/=0)then !!4
                                do iintf=1,nintf
                                    ieq=totveq(trans(ldofs(ievab))%listf(iintf))
                                    do jintf=1,njntf
                                        jeq=totveq(trans(ldofs(jevab))%listf(jintf))
                                        if(ieq/=0.and.jeq/=0) then
                                            dijeq=ieq-jeq
                                            if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                        endif
                                    end do
                                end do
                            endif
                        end do
                    end do
                    !!int2000
1                   continue
                end do   ! ielgroup
                deallocate(ldofs)
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                !! stablize
                if(stabpw==1) then
                    do ipoin=1,group(igroup)%np_unode
                        np_unode=group(igroup)%unode(ipoin)%np_unode
                        do ievab=1,np_unode
                            itotv=nodfn(ndimn+1,group(igroup)%unode(ipoin)%patch_nod(ievab))
                            ieq=totveq(itotv)
                            if(ieq/=0) then
                                do jevab=1,np_unode
                                    jtotv=nodfn(ndimn+1,group(igroup)%unode(ipoin)%patch_nod(jevab))
                                    jeq=totveq(jtotv)
                                    dijeq=ieq-jeq
                                    if(jeq/=0.and.dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                                end do
                            endif
                        end do
                    end do
                endif
                !! end of stablize

            end if !do while

        end do    !! end do ngroup

        !! semi_infinity
        if(ground_inf/=0) then

            do ievab=1,ndofn_space
                itotv=ldofs_space(ievab)
                ieq=totveq(itotv)
                if(ieq/=0) then
                    do jevab=1,ndofn_space
                        jtotv=ldofs_space(jevab)
                        jeq=totveq(jtotv)
                        dijeq=ieq-jeq
                        if(jeq/=0.and.dijeq.gt.iseq(ieq))iseq(ieq)=dijeq  !!low trigonal(for symetric)
                    end do
                endif
            end do
        endif
        !! end of semi_infinity

        !!ifs2000
        do ielem=1,nifsgroup
            aelemf=tifs(ielem)%aelemf
            aelems=tifs(ielem)%aelems
            ipea1=0
            igroup=element(aelemf)%group
            if(appear(igroup)>0)ipea1=1
            ipea2=1
            if(aelems/=0) then
                jgroup=element(aelems)%group
                if(appear(jgroup)<=0)ipea2=0
            endif
            if(ipea1==1.and.ipea2==1) then
                nevab=size(tifs(ielem)%ldofs)
                do ievab=1,nevab
                    do jevab=1,nevab
                        ieq=totveq(tifs(ielem)%ldofs(ievab))
                        jeq=totveq(tifs(ielem)%ldofs(jevab))
                        if(ieq/=0.and.jeq/=0) then
                            dijeq=ieq-jeq
                            if(dijeq.gt.iseq(ieq))iseq(ieq)=dijeq
                        endif
                    end do
                end do
            endif
        end do
        !!ifs2000
        Max_band=0
        Iseq(1)=1
        DO  Ieq=2,Neq
            IF(Max_band<Iseq(Ieq))then
                Max_band=Iseq(Ieq)
            endif
            Iseq(Ieq)=Iseq(Ieq)+Iseq(Ieq-1)+1
        end do
        Max_band=Max_band+1
        Stiff_length=Iseq(neq)
        write(chkunit,*)'No. of equations        =',neq
        write(chkunit,*)'Max half band width     =',Max_band
        write(chkunit,*)'length half stiff matrix=',Stiff_length
        if(allocated(global_stiff1w))deallocate(global_stiff1w)
        if(allocated(rvectorw))    deallocate(rvectorw)
        allocate(global_stiff1w(Stiff_length))
        global_stiff1w=0.0
        allocate(rvectorw(neq))

        if(nonsym.eq.1)then
            allocate(global_stiff2w(Stiff_length))
            global_stiff2w=0.0
        endif
    case ('FACTORIZE')
        if(nonsym.eq.0)call skfacsw(global_stiff1w,iseq)
        if(nonsym.eq.1)call skfacaw(global_stiff1w,global_stiff2w,iseq)
    case ('SOLVE')
        if(allocated(resultw))    deallocate(resultw)
        allocate(resultw(neq))
        resultw=rvectorw
        if(nonsym.eq.0) then
            call  sksolsw(global_stiff1w,resultw,iseq)
        else
            call  sksolaw(global_stiff1w,resultw,global_stiff2w,iseq)
        end if
        allocate(resultm(ntotv))

        resultm=0.
        do itotv=1,ntotv
            nintf=trans(itotv)%nintf
            if(iffix(itotv)==0.and.nintf==0) then
                resultm(itotv)=resultw(totveq(itotv))
            elseif(nintf/=0) then
                listf=>trans(itotv)%listf
                rintf=>trans(itotv)%rintf
                do jtotv=1,nintf
                    if(totveq(listf(jtotv))>0) &
                        resultm(itotv)=resultm(itotv)+resultw(totveq(listf(jtotv)))*rintf(jtotv)
                enddo
                !	 write(7,*)'itotv=',itotv,'resultm=',resultm(itotv)
                nullify(listf,rintf)
            endif
        end do
        !!int2000

        deallocate(resultw)
        allocate(resultw(ntotv))
        resultw=resultm
        deallocate(resultm)

    end select


    end subroutine PROFILEW
    subroutine MAIN_PARDISO
    character(32) text
    integer(ink) migcg,jblks,igroup,ielgroup,ielem,nnode,inode,ipoin,jnode,jpoin,ic,iband,nthis,ithis, &
        ipm,lband,jband,icdofn,itotv,ieq,jeq,jcdofn,jtotv,sstore,itwksp,aelemf,aelems,ipea1,ipea2,jgroup, &
        nintf,njntf,iintf,jintf,nevab,ievab,nevabt,nbandi,nbandx,nbandy,ii,icaloctd,  &
        isdefault,ncpu,reducing_order,PreCGS,permutation,maxiter,out_of_core,eps_pivot,iparm11,iparm13
    integer(ink) ltotve(300),ntotve,bkind
    integer(ink),allocatable::nbande(:),ldofe(:)
    integer(ink),allocatable::mbandi(:),mbandx(:)
    real   (irk),allocatable::resultm(:)
    integer(ink),pointer::ldofs(:),iseq0(:)
    integer(ink),pointer::listf(:)
    real   (irk),pointer::rintf(:)



    Select Case ( Operation)
    Case ('SET')
        if(Bparameter/=0)rewind(solveunit)  !20190810
        if(restart==1)   then
            do jblks=1,iblks-1
                read(solveunit,*)text
                read(solveunit,*)text
                if(type_solver=='PARDISO')then
                    read(solveunit,*)text
                    read(solveunit,*)isdefault
                    if(isdefault/=0)read(solveunit,*)text
                    if(isdefault/=0)read(solveunit,*)text
                endif
            end do
        end if

        !fowlling setting for MKL_PARDISO 2008-11-05
        iparm=0;mtype=2;ncpu=1;msglvl=0;isdefault=1
        read(solveunit,*)text
        print *,text
        read(solveunit,*)mtype,ncpu,msglvl
        print *,mtype,ncpu,msglvl
        read(solveunit,*)text
        print *,text
        read(solveunit,*)isdefault   !0=use default;1=not use default
        print *,isdefault

        if(isdefault/=0)then   ! define value for iparm
            read(solveunit,*)text
            read(solveunit,*)reducing_order,PreCGS,permutation,maxiter,out_of_core,eps_pivot,iparm11,iparm13
            iparm(1) = 1 ! no solver default
            iparm(2) = reducing_order ! fill-in reordering from METIS
            iparm(3) = ncpu ! numbers of processors
            iparm(4) = PreCGS ! no iterative-direct algorithm
            iparm(5) = permutation ! no user fill-in reducing permutation
            iparm(6) = 0 ! =0 solution on the first n compoments of x
            iparm(8) = maxiter ! numbers of iterative refinement steps
            iparm(10) = eps_pivot ! perturbe the pivot elements with 1E-13
            iparm(11) = iparm11 ! use nonsymmetric permutation and scaling MPS
            iparm(13) = iparm13
            iparm(14) = 0 ! Output: number of perturbed pivots
            iparm(18) = -1 ! Output: number of nonzeros in the factor LU
            iparm(19) = -1 ! Output: Mflops for LU factorization
            iparm(20) = 0 ! Output: Numbers of CG Iterations
            iparm(60) = out_of_core  ! use out of core memeroy
        else        !use default value for iparm
            iparm(3) = ncpu ! numbers of processors
            !     iparm(10) = 1.e-15
        endif
        if(nonsym/=0)then !20240312 YL
            iparm(1)  = 1 ! no solver default
            iparm(2)  = 2 ! fill-in reordering from METIS
            !iparm(4)  = 61
            iparm(6)  = 0 ! =0 solution on the first n compoments of x
            iparm(8)  = 5 ! numbers of iterative refinement steps
            iparm(10) = 13 ! perturbe the pivot elements with 1E-13
            iparm(11) = 1 ! use nonsymmetric permutation and scaling MPS
            iparm(13) = 1 ! maximum weighted matching algorithm is switched-off
            iparm(18) = -1
            iparm(19) = -1
            iparm(27) = 1
            !iparm(40) = 0 ! Input: matrix/rhs/solution stored on rank 0 MPI process
        endif !20240312 YL
        error = 0 ! initialize error flag
        maxfct=1
        mnum=1

        pardiso_symbolic_done=.false.
        pardiso_analyzed_neq=-1
        call totv_to_eq

        if(neq==0) return   !2017/11/19

        if(allocated(iseq))deallocate(iseq)
        allocate(iseq(neq+1))
        allocate(bandinf(neq))
        bandinf(:)%nband=0
        bandinf(:)%icaloctd=0

        iseq=0

        do igroup = 1,ngroup
            if(appear(igroup)<=0)cycle
            do ielgroup=1,group(igroup)%nelgroup
                ielem=group(igroup)%list(ielgroup)
                ldofs=>element(ielem)%ldofs
                nevab=size(ldofs)
                ntotve=0
                do ievab=1,nevab
                    itotv=ldofs(ievab)
                    nintf=trans(itotv)%nintf
                    if(nintf==0)then
                        ieq=totveq(itotv)
                        if(ieq==0)cycle
                        ntotve=ntotve+1
                        ltotve(ntotve)=ieq
                    elseif(nintf/=0)then
                        !print *,'ie=',ielem,'nevab=',nevab,'ievab=',ievab,'ntotve=',ntotve,'nintf=',nintf
                        do iintf=1,nintf
                            jtotv=trans(itotv)%listf(iintf)
                            jeq=totveq(jtotv)
                            if(jeq==0)cycle
                            ntotve=ntotve+1
                            ltotve(ntotve)=jeq
                        end do
                    endif
                end do
                do itotv=1,ntotve
                    ieq=ltotve(itotv)
                    do jtotv=itotv+1,ntotve
                        jeq=ltotve(jtotv)
                        if(ieq==jeq)ltotve(jtotv)=0
                    enddo
                enddo
                nevabt=0
                do itotv=1,ntotve
                    if(ltotve(itotv)/=0)nevabt=nevabt+1
                enddo
                allocate(ldofe(nevabt))
                nevabt=0
                do itotv=1,ntotve
                    if(ltotve(itotv)/=0)then
                        nevabt=nevabt+1
                        ldofe(nevabt)=ltotve(itotv)
                    endif
                enddo

                !print *,'ie=',ielem,'nevabt=',nevabt
                do inode=1,nevabt
                    itotv=ldofe(inode)

                    nbandi=0
                    allocate(mbandi(nevabt))

                    nbandx=bandinf(itotv)%nband
                    if(nbandx/=0) then
                        allocate(mbandx(nbandx))
                        mbandx=bandinf(itotv)%mband
                    endif

                    do jnode=1,nevabt
                        jtotv=ldofe(jnode)
                        !if(itotv>jtotv)cycle   !up triangle
                        if(nonsym==0.and.itotv>jtotv)cycle !20240312 YL
                        do ii=1,nbandx
                            if(mbandx(ii)==jtotv) goto 10
                        end do
                        nbandi=nbandi+1
                        mbandi(nbandi)=jtotv
10                      continue
                    enddo !jnode

                    if(nbandi/=0)then
                        nbandy=nbandx+nbandi
                        bandinf(itotv)%nband=nbandy
                        if(nbandx/=0)deallocate(bandinf(itotv)%mband)
                        allocate(bandinf(itotv)%mband(nbandy))
                        bandinf(itotv)%icaloctd=1

                        if(nbandx/=0)then
                            bandinf(itotv)%mband(1:nbandx)=mbandx
                        endif

                        bandinf(itotv)%mband(nbandx+1:nbandy)=mbandi(1:nbandi)
                    endif
                    if(nbandx/=0)deallocate(mbandx)


                    deallocate(mbandi)
                enddo !inode

                nullify(ldofs)
                deallocate(ldofe)

            end do !ielem
        end do !igroup

        !!ifs2000
        if(type_problem/='Q'.and.type_problem/='E') then
            do ielem=1,nifsgroup
                aelemf=tifs(ielem)%aelemf
                aelems=tifs(ielem)%aelems

                ipea1=0
                igroup=element(aelemf)%group
                if(appear(igroup)>0)ipea1=1
                ipea2=1

                if(aelems/=0) then
                    jgroup=element(aelems)%group
                    if(appear(jgroup)<=0)ipea2=0
                endif

                if (ipea1==1.and.ipea2==1) then

                    ldofs=>tifs(ielem)%ldofs
                    nevab=size(ldofs)
                    ntotve=0
                    do ievab=1,nevab
                        itotv=ldofs(ievab)
                        nintf=trans(itotv)%nintf
                        if (nintf==0)then
                            ieq=totveq(itotv)
                            if(ieq==0)cycle
                            ntotve=ntotve+1
                            ltotve(ntotve)=ieq
                        elseif(nintf/=0)then
                            do iintf=1,nintf
                                jtotv=trans(itotv)%listf(iintf)
                                jeq=totveq(jtotv)
                                if(jeq==0)cycle
                                ntotve=ntotve+1
                                ltotve(ntotve)=jeq
                            end do
                        endif
                    end do

                    do itotv=1,ntotve
                        ieq=ltotve(itotv)
                        do jtotv=itotv+1,ntotve
                            jeq=ltotve(jtotv)
                            if(ieq==jeq)ltotve(jtotv)=0
                        enddo
                    enddo
                    nevabt=0
                    do itotv=1,ntotve
                        if(ltotve(itotv)/=0)nevabt=nevabt+1
                    enddo
                    allocate(ldofe(nevabt))
                    nevabt=0
                    do itotv=1,ntotve
                        if(ltotve(itotv)/=0)then
                            nevabt=nevabt+1
                            ldofe(nevabt)=ltotve(itotv)
                        endif
                    enddo
                    !print *,'ie=',ielem,'nevabt=',nevabt
                    do inode=1,nevabt
                        itotv=ldofe(inode)

                        nbandi=0
                        allocate(mbandi(nevabt))

                        nbandx=bandinf(itotv)%nband
                        if(nbandx/=0) then
                            allocate(mbandx(nbandx))
                            mbandx=bandinf(itotv)%mband
                        endif

                        do jnode=1,nevabt
                            jtotv=ldofe(jnode)
                            !if(itotv>jtotv)cycle   !up triangle
                            if(nonsym==0.and.itotv>jtotv)cycle !20240312 YL
                            do ii=1,nbandx
                                if(mbandx(ii)==jtotv) goto 20
                            end do
                            nbandi=nbandi+1
                            mbandi(nbandi)=jtotv
20                          continue
                        enddo !jnode

                        if(nbandi/=0)then
                            nbandy=nbandx+nbandi
                            bandinf(itotv)%nband=nbandy
                            if(nbandx/=0)deallocate(bandinf(itotv)%mband)
                            allocate(bandinf(itotv)%mband(nbandy))
                            bandinf(itotv)%icaloctd=1

                            if(nbandx/=0)then
                                bandinf(itotv)%mband(1:nbandx)=mbandx
                            endif

                            bandinf(itotv)%mband(nbandx+1:nbandy)=mbandi(1:nbandi)
                        endif
                        if(nbandx/=0)deallocate(mbandx)


                        deallocate(mbandi)
                    enddo !inode

                    nullify(ldofs)
                    deallocate(ldofe)

                endif
            end do
        endif
        !!ifs2000
        !!!


        if(type_problem/='Q'.and.type_problem/='E') then
            do ielem=1,ifsnedge
                bkind=ifsedges(ielem)%bkind
                if(bkind/=2)cycle
                aelemf=ifsedges(ielem)%felem
                aelems=ifsedges(ielem)%selem

                ipea1=0
                igroup=element(aelemf)%group
                if(appear(igroup)>0)ipea1=1
                ipea2=1

                if(aelems/=0) then
                    jgroup=element(aelems)%group
                    if(appear(jgroup)<=0)ipea2=0
                endif

                if (ipea1==1.and.ipea2==1) then

                    ldofs=>ifsedges(ielem)%ldofs
                    nevab=size(ldofs)
                    ntotve=0
                    do ievab=1,nevab
                        itotv=ldofs(ievab)
                        nintf=trans(itotv)%nintf
                        if (nintf==0)then
                            ieq=totveq(itotv)
                            if(ieq==0)cycle
                            ntotve=ntotve+1
                            ltotve(ntotve)=ieq
                        elseif(nintf/=0)then
                            do iintf=1,nintf
                                jtotv=trans(itotv)%listf(iintf)
                                jeq=totveq(jtotv)
                                if(jeq==0)cycle
                                ntotve=ntotve+1
                                ltotve(ntotve)=jeq
                            end do
                        endif
                    end do

                    do itotv=1,ntotve
                        ieq=ltotve(itotv)
                        do jtotv=itotv+1,ntotve
                            jeq=ltotve(jtotv)
                            if(ieq==jeq)ltotve(jtotv)=0
                        enddo
                    enddo
                    nevabt=0
                    do itotv=1,ntotve
                        if(ltotve(itotv)/=0)nevabt=nevabt+1
                    enddo
                    allocate(ldofe(nevabt))
                    nevabt=0
                    do itotv=1,ntotve
                        if(ltotve(itotv)/=0)then
                            nevabt=nevabt+1
                            ldofe(nevabt)=ltotve(itotv)
                        endif
                    enddo
                    !print *,'ie=',ielem,'nevabt=',nevabt
                    do inode=1,nevabt
                        itotv=ldofe(inode)

                        nbandi=0
                        allocate(mbandi(nevabt))

                        nbandx=bandinf(itotv)%nband
                        if(nbandx/=0) then
                            allocate(mbandx(nbandx))
                            mbandx=bandinf(itotv)%mband
                        endif

                        do jnode=1,nevabt
                            jtotv=ldofe(jnode)
                            !if(itotv>jtotv)cycle   !up triangle
                            if(nonsym==0.and.itotv>jtotv)cycle !20240312 YL
                            do ii=1,nbandx
                                if(mbandx(ii)==jtotv) goto 21
                            end do
                            nbandi=nbandi+1
                            mbandi(nbandi)=jtotv
21                          continue
                        enddo !jnode

                        if(nbandi/=0)then
                            nbandy=nbandx+nbandi
                            bandinf(itotv)%nband=nbandy
                            if(nbandx/=0)deallocate(bandinf(itotv)%mband)
                            allocate(bandinf(itotv)%mband(nbandy))
                            bandinf(itotv)%icaloctd=1

                            if(nbandx/=0)then
                                bandinf(itotv)%mband(1:nbandx)=mbandx
                            endif

                            bandinf(itotv)%mband(nbandx+1:nbandy)=mbandi(1:nbandi)
                        endif
                        if(nbandx/=0)deallocate(mbandx)


                        deallocate(mbandi)
                    enddo !inode

                    nullify(ldofs)
                    deallocate(ldofe)

                endif
            end do
        endif

        !!!

        do itotv=1,neq
            nthis=bandinf(itotv)%nband
            do iband=1,nthis
                ipm=bandinf(itotv)%mband(iband)
                lband=iband
                do jband=iband+1,nthis
                    if (bandinf(itotv)%mband(jband)<ipm)then
                        lband=jband
                        ipm=bandinf(itotv)%mband(lband)
                    endif
                enddo
                bandinf(itotv)%mband(lband)=bandinf(itotv)%mband(iband)
                bandinf(itotv)%mband(iband)=ipm
            enddo
        enddo

        sstore=0
        do ieq=1,neq
            do iband=1,bandinf(ieq)%nband
                jeq=bandinf(ieq)%mband(iband)
                !if(ieq<=jeq)then
                if(nonsym==0.and.ieq>jeq)cycle !20240312 YL
                sstore=sstore+1  !!up trigonal(for symetric)
                iseq(ieq)=iseq(ieq)+1
                !endif !20240312 YL
            enddo !iband
            !		write(7,*)'ieq=',ieq,'iseq=',iseq(ieq),'nband=',bandinf(ieq)%nband
        enddo

        write(chkunit,*)'单个方程中最大非零元素个数',maxval(Iseq)
        allocate(iseq0(neq+1))
        iseq0(1:neq)=iseq(1:neq)
        Iseq(1)=1
        !DO  Ieq=2,Neq
        DO  Ieq=2,Neq+1 !20240312 YL
            Iseq(Ieq)=Iseq(Ieq-1)+iseq0(ieq-1)
        end do
        !Iseq(1)=1	!20240312 YL
        !Iseq(neq+1)=Iseq(neq)+1
        deallocate(iseq0)


        write(chkunit,*)'Neq=',neq,'      Iseq(neq)=',Iseq(neq)
        write(chkunit,*)'storage of PARDISO, sstore=',sstore
        write(chkunit,*)'                                            '
        if(allocated(global_stiff1))deallocate(global_stiff1)
        if(allocated(nndex))        deallocate(nndex)
        if(allocated(rvector))      deallocate(rvector)
        allocate(global_stiff1(sstore),nndex(sstore),rvector(neq))
        global_stiff1=0.0 ; nndex=0 ; rvector=0.

        sstore=0
        do ieq=1,neq
            do iband=1,bandinf(ieq)%nband
                jeq=bandinf(ieq)%mband(iband)
                !if(ieq<=jeq)then
                if(nonsym==0.and.ieq>jeq)cycle !20240312 YL
                sstore=sstore+1  !!low trigonal(for symetric)
                nndex(sstore)=jeq
                !endif !20240312 YL
            enddo !iband
        enddo

        do ieq=1,neq
            icaloctd=bandinf(ieq)%icaloctd
            if(icaloctd==1)deallocate(bandinf(ieq)%mband)
        end do
        deallocate(bandinf)

    case ('FACTORIZE')

        if(neq==0) return   !2017/11/19
        if(.not.pardiso_symbolic_done .or. pardiso_analyzed_neq /= neq) then
            phase_pardiso = -1 ! release internal memory
            CALL pardiso (pt, maxfct, mnum, mtype, phase_pardiso, neq, ddum, idum, idum,    &
                idum, 1, iparm, msglvl, ddum, ddum, error)

            pt=0
            phase_pardiso = 11 ! only reordering and symbolic factorization
            CALL pardiso (pt, maxfct, mnum, mtype, phase_pardiso, neq, global_stiff1, iseq, nndex,   &
                idum, 1, iparm, msglvl, ddum, ddum, error)
            WRITE(*,*) 'Reordering completed ... ' 
            IF (error .NE. 0) THEN
                write(chkunit,*)'????????????????:', error
                write(*,*)'????????????????:', error
                call pardiso_error(error)
                STOP
            END IF
            pardiso_symbolic_done=.true.
            pardiso_analyzed_neq=neq
        endif
        !    WRITE(chkunit,'(a40,i12)') ' Number of nonzeros in factors:',iparm(18)
        !    WRITE(chkunit,'(a40,i12)') ' Number of factorization MFLOPS:',iparm(19)

        phase_pardiso = 22 ! only factorization
        CALL pardiso (pt, maxfct, mnum, mtype, phase_pardiso, neq, global_stiff1, iseq, nndex,   &
            idum, 1, iparm, msglvl, ddum, ddum, error)
        WRITE(*,*) 'Factorization completed ... ' 
        IF (error .NE. 0) THEN
            WRITE(chkunit,*) '????????????: ', error
            WRITE(*,*) '????????????: ', error
            call pardiso_error(error)
            STOP
        ENDIF
case ('SOLVE')
        !write(7,*)'solve  in main_pardiso='
        if(neq==0) goto 11  !2017/11/19
        if(allocated(result))deallocate(result)


        allocate(result(neq))
        result=0.

        phase_pardiso = 33
        CALL pardiso (pt, maxfct, mnum, mtype, phase_pardiso, neq, global_stiff1, iseq, nndex,   &
            idum, 1, iparm, msglvl, rvector, result, error)

        IF (error .NE. 0) THEN
            WRITE(chkunit,*) '前代回代时出错，错误代码: ', error
            WRITE(*,*) '前代回代时出错，错误代码: ', error
            call pardiso_error(error)
            STOP
        ENDIF

        !if(ngaps==0)rvector=result		!nzw 2006-09-15 !20220321

        !if(kresl/=0.or.ksmat/=0.or.khmat/=0.or.kqmat/=0.or.kmass/=0.or.kthmat/=0.or.ktsmat/=0)then  ! 刚度矩阵重新形成的话就要释放内存
        !    phase_pardiso = -1 ! release internal memory
        !    CALL pardiso (pt, maxfct, mnum, mtype, phase_pardiso, neq, ddum, idum, idum,    &
        !                 idum, 1, iparm, msglvl, ddum, ddum, error)
        !endif

        if(allocated(resultm))deallocate(resultm)
        allocate(resultm(ntotv))
        resultm=0.
        !!$OMP PARALLEL DO PRIVATE(nintf,listf,rintf) IF(OpenMP==1)

        do itotv=1,ntotv
            nintf=trans(itotv)%nintf

            if(iffix(itotv)==0.and.nintf==0) then
                resultm(itotv)=result(totveq(itotv))
            elseif(nintf/=0) then
                listf=>trans(itotv)%listf
                rintf=>trans(itotv)%rintf

                do jtotv=1,nintf
                    if(totveq(listf(jtotv))>0) &
                        resultm(itotv)=resultm(itotv)+result(totveq(listf(jtotv)))*rintf(jtotv)
                enddo

                nullify(listf,rintf)
            endif
        end do


        !!$OMP END PARALLEL DO

11      if(allocated(result)) deallocate(result) !2017/11/19
        allocate(result(ntotv));result=0.0
        if(neq==0) return !2017/11/19
        result=resultm
        deallocate(resultm)



    end select
    end subroutine MAIN_PARDISO
    !====================================================
    subroutine pardiso_error(error)
    integer(ink) error

    Select Case (error)
    Case (-2)
        write(chkunit,*)'没有足够的内存，建议用64位系统编译并用服务器计算'
    Case (-3)
        write(chkunit,*)'方程重新排序时出错'
    Case (-4)
        write(chkunit,*)'主对角线元素接近0，请检查单元形状及材料'
    Case (-8)
        write(chkunit,*)'32位整型溢出，建议用64位系统编译'
    end select
    end subroutine pardiso_error
    !!PBCG
    SUBROUTINE PBCG

    character (32)text
    integer(ink) index,nevab,ielem,ieq,jeq,ievab,jevab,ielgroup,jblks
    integer(ink) ic,nciseq,snonzero,isnonzero,istore,kstore,icolumn

    integer(ink) igroup
    integer(ink),allocatable::ldofs(:)
    integer(ink),pointer::listx(:),listy(:)
    real   (irk),allocatable ::resultm(:)

    type nonzero_stiff_store
        integer(ink)nciseq
        integer(ink),pointer::list(:)
    end type nonzero_stiff_store

    type (nonzero_stiff_store),allocatable::store_seq(:)


    !!for LDU direct method with symmetric matrix
    Select Case ( Operation)
    Case ('SET')
        if(restart==1)   then
            do jblks=1,iblks-1
                read(solveunit,*)text
                read(solveunit,*)text
            end do
        end if
        Read (solveunit,*) text
        Read (solveunit,*)  mitcg, tolcg, itolcg

        !       Case ('SET')

        call totv_to_eq
        if(neq==0) return   !2017/11/19

        if(allocated(store_seq))deallocate(store_seq)
        allocate(store_seq(neq))
        store_seq(:)%nciseq=0

        DO igroup = 1,ngroup                              !6

            if(appear(igroup)>0)    then                    !5

                index = group(igroup)%index
                ielem = group(igroup)%list(1)
                index=element(ielem)%index
                nevab=size(element(ielem)%ldofs)
                allocate(ldofs(nevab))
                DO ielgroup = 1, group(igroup)%nelgroup    !4
                    ielem = group(igroup)%list(ielgroup)
                    ldofs=element(ielem)%ldofs
                    do ievab=1,nevab                          !3
                        ieq=totveq(ldofs(ievab))
                        nciseq=store_seq(ieq)%nciseq
                        if(ieq/=0) then                    !2
                            do jevab=1,nevab            ! 1
                                jeq=totveq(ldofs(jevab))

                                if(jeq/=0.and.jeq/=ieq) then

                                    ic=0
                                    if(nciseq/=0) then
                                        allocate(listy(nciseq))
                                        listy=store_seq(ieq)%list
                                        if(any(listy==jeq))ic=1
                                        deallocate(listy)
                                    endif
                                    !!!update the structure store_seq(ieq)
                                    if(ic==0) then                              !!!!!!!!!!!!!!!!!!!!!!!!
                                        nciseq=nciseq+1                                                     !
                                        allocate(listx(nciseq))                                             !
                                        if(nciseq.gt.1)listx(1:nciseq-1)=store_seq(ieq)%list(1:nciseq-1)     !
                                        listx(nciseq)=jeq                                                 !
                                        if(nciseq.gt.1)deallocate(store_seq(ieq)%list)                     !
                                        allocate(store_seq(ieq)%list(nciseq))                     !
                                        store_seq(ieq)%list=listx
                                        store_seq(ieq)%nciseq=nciseq                                 !
                                        deallocate(listx)                                         !
                                    endif                                      !!!!!!!!!!!!!!!!!!!!!!!!
                                endif
                            end do                         !1
                        endif                                !2
                    end do                                 !3
                end DO        !!ielgroup               !4
                deallocate(ldofs)
            end if            !!do while                      !5
        end do           !!igroup                      !6
        !       write(chkunit,*)'nciseq=',store_seq(1:neq)%nciseq
        !       do ieq=1,neq
        !       write(chkunit,*)'nciseq=',store_seq(ieq)%nciseq
        !       write(chkunit,*)'list  =',store_seq(ieq)%list
        !       end do


        snonzero=sum(store_seq(1:neq)%nciseq)
        snonzero=snonzero+neq+1
        kstore=neq+1

        write(chkunit,*)'snonzero (PBCG) =',snonzero
        if(allocated(iseq))deallocate(iseq)
        allocate(iseq(snonzero))

        isnonzero=neq+2
        iseq(1)=isnonzero
        do ieq=1,neq
            if(store_seq(ieq)%nciseq/=0) then
                isnonzero=store_seq(ieq)%nciseq+isnonzero
                do icolumn=1,store_seq(ieq)%nciseq
                    istore=kstore+icolumn
                    iseq(istore)=store_seq(ieq)%list(icolumn)
                end do
            endif
            iseq(ieq+1)=isnonzero
            kstore=kstore+store_seq(ieq)%nciseq
        end do

        !when assembling the element stiff matrix  st(ievab,jevab)    to
        !            global_stiff1(kstore)
        !  sij_row   =totv_eq(ldofs(ievab))
        !  sij_column=totv_eq(ldofs(jevab))
        !  if(sij_row==sij_column)
        !        kstore=sij_column
        !  else
        !      do kstore=iseq(sij_row),iseq(sij_row+1)-1
        !        if(iseq(kstore).eq.sij_column)exit
        !  endfif
        !         write(chkunit,*)'iseq****'
        !         do ieq=1,snonzero
        !         write(chkunit,*)ieq,iseq(ieq)
        !         end do
        deallocate(store_seq)
        if(allocated(global_stiff1))deallocate(global_stiff1)
        allocate(global_stiff1(snonzero))
        global_stiff1=0.0
        if(allocated(rvector))    deallocate(rvector)
        allocate(rvector(neq))

    case('SOLVE')
        if(allocated(result))deallocate(result)
        allocate(result(neq))
        result=0.0
        call linbcg(neq,rvector,result,itolcg,tolcg,mitcg)

        allocate(resultm(ntotv))
        where(iffix==0)
            resultm=result(totveq)
        elsewhere
            resultm=0.0
        endwhere
        deallocate(result)
        allocate(result(ntotv))
        result=resultm
        deallocate(resultm)
    end select
    end subroutine PBCG
    !====================================================

    SUBROUTINE SSORPBCG !ssorpbcg

    character (32)text
    integer(ink) migcg,jblks,igroup,ielgroup,ielem,nnode,inode,ipoin,jnode,jpoin,ic,iband,nthis,ithis, &
        ipm,lband,jband,icdofn,itotv,ieq,jeq,jcdofn,jtotv,sstore, &
        nintf,njntf,iintf,jintf,nevab,ievab,nevabt,nbandi,nbandx,nbandy,ii,icaloctd,aelemf,aelems,ipea1,ipea2,jgroup
    integer(ink) ltotve(300),ntotve
    integer(ink),allocatable::ldofe(:)
    integer(ink),allocatable::mbandi(:),mbandx(:)
    real   (irk),allocatable::resultm(:)
    integer(ink),pointer::ldofs(:)
    integer(ink),pointer::listf(:)
    real   (irk),pointer::rintf(:)

    Select Case ( Operation)
    Case ('SET')

        if (restart==1)   then
            do jblks=1,iblks-1
                read(solveunit,*)text
                read(solveunit,*)text
            end do
        end if
        read (solveunit,*)text
        read (solveunit,*)miter_ssorpbcg,torler_ssorpbcg,omig_ssorpbcg

        call totv_to_eq

        if(neq==0) return   !2017/11/19

        if(allocated(iseq))deallocate(iseq)
        allocate(iseq(neq))
        allocate(bandinf(neq))
        bandinf(:)%nband=0
        bandinf(:)%icaloctd=0

        iseq=0

        do igroup = 1,ngroup
            if(appear(igroup)<=0)cycle
            dO ielgroup=1,group(igroup)%nelgroup
                ielem=group(igroup)%list(ielgroup)
                !ldofs=>element(ielem)%field(1)%ldofs_f
                ldofs=>element(ielem)%ldofs
                IF(group(Igroup)%nrfields/=1)then
                    write(*,*)'似乎此时应改成ldofs=>element(ielem)%ldofs，PARDISO已改过来了'
                    !STOP
                endif
                nevab=size(ldofs)


                ntotve=0
                do ievab=1,nevab
                    itotv=ldofs(ievab)
                    nintf=trans(itotv)%nintf
                    if(nintf==0)then
                        ieq=totveq(itotv)
                        if(ieq==0)cycle
                        ntotve=ntotve+1
                        ltotve(ntotve)=ieq
                    elseif(nintf/=0)then
                        do iintf=1,nintf
                            jtotv=trans(itotv)%listf(iintf)
                            jeq=totveq(jtotv)
                            if(jeq==0)cycle
                            ntotve=ntotve+1
                            ltotve(ntotve)=jeq
                        end do
                    endif
                end do
                do itotv=1,ntotve
                    ieq=ltotve(itotv)
                    do jtotv=itotv+1,ntotve
                        jeq=ltotve(jtotv)
                        if(ieq==jeq)ltotve(jtotv)=0
                    enddo
                enddo
                nevabt=0
                do itotv=1,ntotve
                    if(ltotve(itotv)/=0)nevabt=nevabt+1
                enddo
                allocate(ldofe(nevabt))
                nevabt=0
                do itotv=1,ntotve
                    if(ltotve(itotv)/=0)then
                        nevabt=nevabt+1
                        ldofe(nevabt)=ltotve(itotv)
                    endif
                enddo

                !print *,'ie=',ielem,'nevabt=',nevabt
                do inode=1,nevabt
                    itotv=ldofe(inode)

                    nbandi=0
                    allocate(mbandi(nevabt))

                    nbandx=bandinf(itotv)%nband
                    if(nbandx/=0) then
                        allocate(mbandx(nbandx))
                        mbandx=bandinf(itotv)%mband
                    endif

                    do jnode=1,nevabt
                        jtotv=ldofe(jnode)
                        if(jtotv>itotv)cycle
                        do ii=1,nbandx
                            if(mbandx(ii)==jtotv) goto 10
                        end do
                        nbandi=nbandi+1
                        mbandi(nbandi)=jtotv
10                      continue
                    enddo !jnode

                    if(nbandi/=0)then
                        nbandy=nbandx+nbandi
                        bandinf(itotv)%nband=nbandy
                        if(nbandx/=0)deallocate(bandinf(itotv)%mband)
                        allocate(bandinf(itotv)%mband(nbandy))
                        bandinf(itotv)%icaloctd=1
                        if(nbandx/=0)then
                            bandinf(itotv)%mband(1:nbandx)=mbandx
                        endif
                        bandinf(itotv)%mband(nbandx+1:nbandy)=mbandi(1:nbandi)
                    endif
                    if(nbandx/=0)deallocate(mbandx)


                    deallocate(mbandi)
                enddo !inode


                nullify(ldofs)
                deallocate(ldofe)

            end do !ielem
        end do !igroup

        !!ifs2000
        if(type_problem/='Q'.and.type_problem/='E') then
            do ielem=1,nifsgroup
                aelemf=tifs(ielem)%aelemf
                aelems=tifs(ielem)%aelems

                ipea1=0
                igroup=element(aelemf)%group
                if(appear(igroup)>0)ipea1=1
                ipea2=1

                if(aelems/=0) then
                    jgroup=element(aelems)%group
                    if(appear(jgroup)<=0)ipea2=0
                endif

                if (ipea1==1.and.ipea2==1) then

                    ldofs=>tifs(ielem)%ldofs
                    nevab=size(ldofs)
                    ntotve=0
                    do ievab=1,nevab
                        itotv=ldofs(ievab)
                        nintf=trans(itotv)%nintf
                        if (nintf==0)then
                            ieq=totveq(itotv)
                            if(ieq==0)cycle
                            ntotve=ntotve+1
                            ltotve(ntotve)=ieq
                        elseif(nintf/=0)then
                            do iintf=1,nintf
                                jtotv=trans(itotv)%listf(iintf)
                                jeq=totveq(jtotv)
                                if(jeq==0)cycle
                                ntotve=ntotve+1
                                ltotve(ntotve)=jeq
                            end do
                        endif
                    end do

                    do itotv=1,ntotve
                        ieq=ltotve(itotv)
                        do jtotv=itotv+1,ntotve
                            jeq=ltotve(jtotv)
                            if(ieq==jeq)ltotve(jtotv)=0
                        enddo
                    enddo
                    nevabt=0
                    do itotv=1,ntotve
                        if(ltotve(itotv)/=0)nevabt=nevabt+1
                    enddo
                    allocate(ldofe(nevabt))
                    nevabt=0
                    do itotv=1,ntotve
                        if(ltotve(itotv)/=0)then
                            nevabt=nevabt+1
                            ldofe(nevabt)=ltotve(itotv)
                        endif
                    enddo
                    !print *,'ie=',ielem,'nevabt=',nevabt
                    do inode=1,nevabt
                        itotv=ldofe(inode)

                        nbandi=0
                        allocate(mbandi(nevabt))

                        nbandx=bandinf(itotv)%nband
                        if(nbandx/=0) then
                            allocate(mbandx(nbandx))
                            mbandx=bandinf(itotv)%mband
                        endif

                        do jnode=1,nevabt
                            jtotv=ldofe(jnode)
                            if(itotv>jtotv)cycle   !up triangle
                            do ii=1,nbandx
                                if(mbandx(ii)==jtotv) goto 20
                            end do
                            nbandi=nbandi+1
                            mbandi(nbandi)=jtotv
20                          continue
                        enddo !jnode

                        if(nbandi/=0)then
                            nbandy=nbandx+nbandi
                            bandinf(itotv)%nband=nbandy
                            if(nbandx/=0)deallocate(bandinf(itotv)%mband)
                            allocate(bandinf(itotv)%mband(nbandy))
                            bandinf(itotv)%icaloctd=1

                            if(nbandx/=0)then
                                bandinf(itotv)%mband(1:nbandx)=mbandx
                            endif

                            bandinf(itotv)%mband(nbandx+1:nbandy)=mbandi(1:nbandi)
                        endif
                        if(nbandx/=0)deallocate(mbandx)


                        deallocate(mbandi)
                    enddo !inode

                    nullify(ldofs)
                    deallocate(ldofe)

                endif
            end do
        endif
        !!ifs2000

        do itotv=1,neq
            nthis=bandinf(itotv)%nband
            do iband=1,nthis
                ipm=bandinf(itotv)%mband(iband)
                lband=iband
                do jband=iband+1,nthis
                    if (bandinf(itotv)%mband(jband)<ipm)then
                        lband=jband
                        ipm=bandinf(itotv)%mband(lband)
                    endif
                enddo
                bandinf(itotv)%mband(lband)=bandinf(itotv)%mband(iband)
                bandinf(itotv)%mband(iband)=ipm
            enddo
        enddo

        !   write(chkunit,*)'Mband information'
        !	do ieq=1,neq
        !	write(7,*)ieq,bandinf(ieq)%nband
        !	write(7,*)bandinf(ieq)%mband
        !	end do
        !	stop
        !do ipoin=1,npoin
        !   write(chkunit,'(50i10)')ipoin,nband(ipoin),mband(1:nband(ipoin),ipoin)
        !enddo
        sstore=0
        do ieq=1,neq
            do iband=1,bandinf(ieq)%nband
                jeq=bandinf(ieq)%mband(iband)
                if(jeq<=ieq)then
                    sstore=sstore+1  !!low trigonal(for symetric)
                    iseq(ieq)=iseq(ieq)+1
                endif
            enddo !iband

        enddo

        !if(allocated(pcg_stiff))deallocate(pcg_stiff)
        !allocate(pcg_stiff(neq))
        !pcg_stiff(:)%nciseq=0

        Iseq(1)=1
        DO  Ieq=2,Neq
            Iseq(Ieq)=Iseq(Ieq)+Iseq(Ieq-1)
        end do

        write(chkunit,*)'                                            '
        write(chkunit,*)'Neq=                        ',neq
        write(chkunit,*)'storage of SSORPBCG, sstore=',sstore
        write(chkunit,*)'                                            '
        if(allocated(global_stiff1))deallocate(global_stiff1)
        if(allocated(nndex))        deallocate(nndex)
        if(allocated(rvector))      deallocate(rvector)
        allocate(global_stiff1(sstore),nndex(sstore),rvector(neq))
        global_stiff1=0.0 ; nndex=0 ; rvector=0.

        sstore=0
        do ieq=1,neq
            do iband=1,bandinf(ieq)%nband
                jeq=bandinf(ieq)%mband(iband)
                if(jeq<=ieq)then
                    sstore=sstore+1  !!low trigonal(for symetric)
                    nndex(sstore)=jeq
                endif
            enddo !iband
        enddo


        !   write(7,*)'nndex=',size(nndex)
        !	write(7,*)'nndex=',nndex
        do ieq=1,neq
            icaloctd=bandinf(ieq)%icaloctd
            if(icaloctd==1)deallocate(bandinf(ieq)%mband)
        end do
        deallocate(bandinf)

    case('SOLVE')
        if(allocated(result))deallocate(result)
        allocate(result(neq))
        result=0.0
        !if(iiter==1)then
        !do itotv=1,ntotv
        !   if(iffix(itotv)==0.and.totveq(itotv)/=0)result(totveq(itotv))=deltafi_ssorpbcg(itotv)
        !enddo
        !endif
        call solver_ssorpbcg_new(global_stiff1,result,rvector,neq,iseq,nndex,miter_ssorpbcg,torler_ssorpbcg,omig_ssorpbcg)
        allocate(resultm(ntotv))

        resultm=0.
        do itotv=1,ntotv
            nintf=trans(itotv)%nintf
            if(iffix(itotv)==0.and.nintf==0) then
                resultm(itotv)=result(totveq(itotv))
            elseif(nintf/=0) then
                listf=>trans(itotv)%listf
                rintf=>trans(itotv)%rintf
                do jtotv=1,nintf
                    if(totveq(listf(jtotv))>0) &
                        resultm(itotv)=resultm(itotv)+result(totveq(listf(jtotv)))*rintf(jtotv)
                enddo
                !	 write(7,*)'itotv=',itotv,'resultm=',resultm(itotv)
                nullify(listf,rintf)
            endif
        end do

        deallocate(result)
        allocate(result(ntotv))
        result=resultm
        deallocate(resultm)
    end select

    end subroutine SSORPBCG

    !-----------------------------------------------------------------
    subroutine solver_ssorpbcg_new(a,x,b,n,ma,ia,kmax,tor,w)
    !-----------------------------------------------------------------


    !global_stiff1    --a
    !result           --x
    !rvector          --b
    !neq              --n
    !iseq             --ma
    !nndex            --ia
    !miter_ssorpbcg   --kmax
    !torler_ssorpbcg  --tor
    !omig_ssorpbcg    --w

    integer(ink) n,ma(:),ia(:),kmax,k,i,ncheck
    real   (irk) a(:),x(:),b(:),tor,w,residu,tao,bk,residu0,ratio
    real   (irk),allocatable::g(:),y(:),z(:),d(:),vy(:),vd(:),wzvd(:)

    allocate(g(n),y(n),z(n),d(n),vy(n),vd(n),wzvd(n))
    g=0. ; y=0. ; z=0. ; d=0. ; vy=0. ; vd=0. ; wzvd=0.

    !set initial value
    x=0.
    k=0

    call ax(g,a,x,n,ma,ia) !g=ax  x=0 so g=0

    g=g-b
    y=g
    call wyg(y,a,n,ma,ia,w,1) !y=w(-1)*g, ie, wy=g .   ic: 1--for w, 2--for w(T)
    z=y
    call vyvd(z,a,ma,n,w)
    z=-z
    d=z
    call wyg(d,a,n,ma,ia,w,2) !y=w(-1)*g, ie, wy=g .   ic: 1--for w, 2--for w(T)
    vy=y
    vd=d
    call vyvd(vy,a,ma,n,w)
    call vyvd(vd,a,ma,n,w)
    residu0=dot_product(y,vy)

    do !  *********loop for iteration*********

        k=k+1
        ncheck=1
        residu=dot_product(y,vy)
        ratio =residu/residu0

        if(abs(residu)<tor)ncheck=0
        IF(K/100*100==k.OR.NCHECK==0)write(*,      '(a,i6,a,e15.6,a,i4,a,e15.6)')'ssorpbcg iiter=',k,' residu=',residu,' ncheck=',ncheck,' ratio=',ratio
        !write(chkunit,'(a,i6,a,e15.6,a,i4,a,e15.6)')'ssorpbcg iiter=',k,' residu=',residu,' ncheck=',ncheck,' ratio=',ratio
        if(ncheck==0.or.k>=kmax)exit

        tao=residu/dot_product(d,2*z-vd)
        x=x+tao*d
        wzvd=z-vd
        call wyg(wzvd,a,n,ma,ia,w,1)!y=w(-1)*g, ie, wy=g .   ic: 1--for w, 2--for w(T)
        bk=dot_product(y,vy)
        y=y+tao*(d+wzvd)
        vy=y
        call vyvd(vy,a,ma,n,w)
        bk=dot_product(y,vy)/bk
        z=bk*z-vy
        d=z
        call wyg(d,a,n,ma,ia,w,2) !y=w(-1)*g, ie, wy=g .   ic: 1--for w, 2--for w(T)
        vd=d
        call vyvd(vd,a,ma,n,w)

    enddo ! *********end loop for iteration*********

    deallocate(g,y,z,d,vy,vd,wzvd)

    end subroutine solver_ssorpbcg_new

    subroutine vyvd(vyd,a,ma,n,w)
    integer(ink) n,ma(:),i
    real   (irk) a(:),vyd(:),w
    do i=1,n
        vyd(i)=vyd(i)*a(ma(i))
    enddo
    vyd=vyd*(2.0-w)/w

    end subroutine vyvd

    !-----------------------------------------------------------------
    subroutine wyg(x,a,n,ma,ia,w,ic)
    !-----------------------------------------------------------------

    integer(ink) n,ma(:),ia(:),ic,i,j,k,low,lup
    real   (irk) a(:),x(:),w,t

    if(ic==1)then !ic: 1--for w, 2--for w(T)

        x(1)=x(1)/a(1)*w
        do i=2,n
            low=ma(i-1)+1
            lup=ma(i)-1
            do j=low,lup
                k=ia(j)
                x(i)=x(i)-a(j)*x(k)
            enddo
            x(i)=x(i)/a(ma(i))*w !a(ma(i))/=====0!!!
        enddo

    elseif(ic==2)then !ic: 1--for w, 2--for w(T)

        do i=n,2,-1
            x(i)=x(i)/a(ma(i))*w !a(ma(i))/=====0!!!
            low=ma(i-1)+1
            lup=ma(i)-1
            do j=low,lup
                k=ia(j)
                x(k)=x(k)-a(j)*x(i)
            enddo
        enddo
        x(1)=x(1)/a(1)*w

    endif

    end subroutine wyg

    !-----------------------------------------------------------------
    subroutine ax(g,a,x,n,ma,ia)
    !-----------------------------------------------------------------

    integer(ink) n,ma(:),ia(:),i,j,k,low,lup
    real   (irk) a(:),x(:),g(:),t

    !perform g=ax

    do i=1,n !main diagonal
        g(i)=a(ma(i))*x(i)
    enddo

    do i=2,n !low trigonal
        low=ma(i-1)+1
        lup=ma(i)-1
        t=x(i)
        do j=low,lup
            k=ia(j)
            g(i)=g(i)+a(j)*x(k)
            g(k)=g(k)+a(j)*t
        enddo
    enddo

    end subroutine ax


    ! end solver_ssorpbcg_new

    SUBROUTINE totv_to_eq

    integer(ink) order_freedom,first_node,second_node,itotv,jtotv,ilink, &
        npairs,ipair,im,in,ipoin
    integer(ink),pointer::link_freedom(:),pairnode(:,:)

    if(allocated(totveq))deallocate(totveq)
    allocate(totveq(ntotv))


    !!int2000
    totveq=0
    !write(7,*)'itotv,iffix,nintf='
    do itotv=1,ntotv
        !write(7,*)itotv,iffix(itotv),trans(itotv)%nintf
        if(iffix(itotv)==0) then
            if(trans(itotv)%nintf==0)then
                totveq(itotv)=1
            else
                if(any(trans(itotv)%listf==itotv))totveq(itotv)=1
            endif
        endif
    end do
    !stop

    !!int2000

    do ilink=1,nlinks
        npairs=links(ilink)%npairs
        pairnode=>links(ilink)%pairnode
        link_freedom=>links(ilink)%link_freedom
        do order_freedom=1,cdofn
            if(link_freedom(order_freedom)==1) then
                do ipair=1,npairs
                    first_node   =pairnode(1,ipair)
                    second_node  =pairnode(2,ipair)
                    itotv        =nodfn(order_freedom,first_node)
                    jtotv        =nodfn(order_freedom,second_node)
                    totveq(jtotv) =-itotv
                end do
            endif
        end do
        nullify(pairnode)
    end do


    neq=0

    if(nlayer/=2) then  !! for nlayer/=2

        !do itotv=1,ntotv
        !if(totveq(itotv)==1) then
        !neq=neq+1
        !totveq(itotv)=neq
        !endif
        !end do


        do ipoin=1,npoin !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!11
            do im=1,mdofn   !! for all variables except Pw
                in=lmdofn(im)
                if(im/=8.and.in/=0) then
                    itotv=nodfn(in,ipoin)


                    if(itotv/=0) then
                        if(totveq(itotv)==1) then
                            neq=neq+1
                            totveq(itotv)=neq
                        endif
                    endif

                end if
            end do
        end do
        neq_layer1=neq !zhao 05/07/22
        if(mdofn>=8)then !for pardiso
            if(mdofn>=8.and.lmdofn(8)/=0) then    !! for varibale Pw
                in=lmdofn(8)
                do ipoin=1,npoin !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!11
                    itotv=nodfn(in,ipoin)
                    if(itotv/=0) then
                        if(totveq(itotv)==1) then
                            neq=neq+1
                            totveq(itotv)=neq
                        endif
                    endif
                end do
            end if
        endif !for pardiso
        !neq_layer1=neq !zhao 05/07/22
    else   !! for nlayer==2
        do itotv=1,ntotv
            if(totveq(itotv)==1.and.freedom_layer(itotv)==1) then
                neq=neq+1
                totveq(itotv)=neq
            endif
        end do
        neq_layer1=neq
        do itotv=1,ntotv
            if(totveq(itotv)==1.and.freedom_layer(itotv)/=1) then
                neq=neq+1
                totveq(itotv)=neq
            endif
        end do
        print *,'neq_layer1=',neq_layer1,'neq=',neq
        write(chkunit,*)'neq_layer1=',neq_layer1,'neq=',neq
    endif



    do itotv=1,ntotv
        if(totveq(itotv)<0) then
            jtotv=-totveq(itotv)
            totveq(itotv)=totveq(jtotv)
        endif
    end do

    END SUBROUTINE totv_to_eq

    !!following is the solver LDU method  for symmetric problems

    SUBROUTINE skfacs(a,idiag,ylost,iafile)

    integer(ink) iafile,idiag(:)
    integer(ink) jr,j,jd,jh,is,ie,k,id,i,ir,ih
    real   (irk) zero,d,dg, a(:), ylost, tol
    real(irk),allocatable::ia(:),la(:)
    !
    !
    data zero,tol/0.0_irk,1.e-7/
    !
    !---- i n i t i a l i s a t i o n
    !
    !
    !---  save original matrix
    !
    if(iafile .ne. 0) then
        rewind iafile
        write(iafile) a
    endif
    !
    !---- f a c t o r i s a t i o n   s e c t i o n
    !
    ylost=zero
    jr = 0
    do 6000 j = 1,neq
        jd = idiag(j)
        jh = jd - jr
        is = j - jh + 2
        dg = a(jd)
        if(jh-2)  6000,3000,1000
        !
1000    ie = j - 1
        k = jr + 2
        id = idiag(is-1)
        !
        !---- reduce all equations except diagonal
        !
        do 2000 i = is,ie
            ir = id
            id = idiag(i)
            ih = min(id-ir-1 , i-is+1)
            if(ih > 0)                                  &
                a(k) = a(k) - dot_product(a(k-ih:k-1),a(id-ih:id-1))       !nzw 2006-08-08 for ivf
            !			  a(k) = a(k) - dots(a(k-ih),a(id-ih),ih)
2000    k = k + 1
        !
        !---- reduce diagonal term
        !
3000    ir = jr + 1
        ie = jd - 1
        k  = j  - jd
        do 4000 i = ir,ie
            id = idiag(k+i)
            if(abs(a(id)) > zero) then
                !            if(abs(a(id)) > tol) then

                d    = a(i)
                a(i) = a(i)/a(id)
                a(jd)= a(jd) - d*a(i)
            endif
4000    continue
        !
        !         if(abs(a(jd)) .lt. tol*abs(dg))          ylost = log10(tol)
        !

6000 jr = jd
    !
    !---- save factorisation if iafile ne. 0
    !
    if(iafile .ne. 0) then
        write(iafile) a
    endif
    !
    !----
    !

    END  SUBROUTINE skfacs

    SUBROUTINE skfacsw(a,idiag)

    integer(ink) iafile,idiag(:)
    integer(ink) jr,j,jd,jh,is,ie,k,id,i,ir,ih
    complex(irk) d,dg, a(:)
    real(irk)  zero
    data zero/0.0_irk/
    complex(irk),allocatable::ia(:),la(:)
    !
    !
    !---- f a c t o r i s a t i o n   s e c t i o n
    !
    jr = 0
    do 6000 j = 1,neq
        jd = idiag(j)
        jh = jd - jr
        is = j - jh + 2
        dg = a(jd)
        if(jh-2)  6000,3000,1000
        !
1000    ie = j - 1
        k = jr + 2
        id = idiag(is-1)
        !
        !---- reduce all equations except diagonal
        !
        do 2000 i = is,ie
            ir = id
            id = idiag(i)
            ih = min(id-ir-1 , i-is+1)
            if(ih > 0)                                  &
                a(k) = a(k) - dot_product(CONJG(a(k-ih:k-1)),a(id-ih:id-1))       !nzw 2006-08-08 for ivf
            !			  a(k) = a(k) - dotsw(a(k-ih),a(id-ih),ih)
2000    k = k + 1
        !
        !---- reduce diagonal term
        !
3000    ir = jr + 1
        ie = jd - 1
        k  = j  - jd
        do 4000 i = ir,ie
            id = idiag(k+i)
            if(abs(a(id)) > zero) then
                d    = a(i)
                a(i) = a(i)/a(id)
                a(jd)= a(jd) - d*a(i)
            endif
4000    continue
        !

6000 jr = jd
    !
    END  SUBROUTINE skfacsw
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    SUBROUTINE skfacs_bt(a,idiag,ylost,iafile)  !ctt2005

    integer(ink) iafile,idiag(:)
    integer(ink) jr,j,jd,jh,is,ie,k,id,i,ir,ih
    real   (irk) zero,d,dg, a(:), ylost, tol
    real(irk),allocatable::ia(:),la(:)
    !
    !
    data zero,tol/0.0_irk,1.e-7/
    !
    !---- i n i t i a l i s a t i o n
    !
    !
    !---  save original matrix
    !
    if(iafile .ne. 0) then
        rewind iafile
        write(iafile) a
    endif
    !
    !---- f a c t o r i s a t i o n   s e c t i o n
    !
    ylost=zero
    jr = 0
    do 6000 j = 1,neq_bt
        jd = idiag(j)
        jh = jd - jr
        is = j - jh + 2
        dg = a(jd)
        if(jh-2)  6000,3000,1000
        !
1000    ie = j - 1
        k = jr + 2
        id = idiag(is-1)
        !
        !---- reduce all equations except diagonal
        !
        do 2000 i = is,ie
            ir = id
            id = idiag(i)
            ih = min(id-ir-1 , i-is+1)
            if(ih > 0)                                  &
                a(k) = a(k) - dot_product(a(k-ih:k-1),a(id-ih:id-1))       !nzw 2006-08-08 for ivf
            !			  a(k) = a(k) - dots(a(k-ih),a(id-ih),ih)
2000    k = k + 1
        !
        !---- reduce diagonal term
        !
3000    ir = jr + 1
        ie = jd - 1
        k  = j  - jd
        do 4000 i = ir,ie
            id = idiag(k+i)
            if(abs(a(id)) > zero) then
                !            if(abs(a(id)) > tol) then

                d    = a(i)
                a(i) = a(i)/a(id)
                a(jd)= a(jd) - d*a(i)
            endif
4000    continue
        !
        !         if(abs(a(jd)) .lt. tol*abs(dg))          ylost = log10(tol)
        !

6000 jr = jd
    !
    !---- save factorisation if iafile ne. 0
    !
    if(iafile .ne. 0) then
        write(iafile) a
    endif
    !
    !----
    !

    END  SUBROUTINE skfacs_bt !ctt2005
    !!nlayer==2
    SUBROUTINE skfacs_layer(a,idiag,ilayer)

    integer(ink) ilayer,eq1,eq2,idiag(:)
    integer(ink) jr,j,jd,jh,is,ie,k,id,i,ir,ih
    real   (irk) d,dg, a(:)
    real(irk),allocatable::ia(:),la(:)
    !
    !
    if(ilayer==1) then
        eq1=1
        eq2=neq_layer1
    elseif(ilayer==2) then
        eq1=neq_layer1+1
        eq2=neq
    endif

    !
    !---- f a c t o r i s a t i o n   s e c t i o n
    !
    jr = 0
    if(ilayer==2)jr=idiag(neq_layer1)
    do 6000 j = eq1,eq2
        jd = idiag(j)
        jh = jd - jr
        is = j - jh + 2
        dg = a(jd)
        if(jh-2)  6000,3000,1000
        !
1000    ie = j - 1
        k = jr + 2
        id = idiag(is-1)
        !
        !---- reduce all equations except diagonal
        !
        do 2000 i = is,ie
            ir = id
            id = idiag(i)
            ih = min(id-ir-1 , i-is+1)
            if(ih > 0)                                  &
                a(k) = a(k) - dot_product(a(k-ih:k-1),a(id-ih:id-1))       !nzw 2006-08-08 for ivf
            !			  a(k) = a(k) - dots(a(k-ih),a(id-ih),ih)
2000    k = k + 1
        !
        !---- reduce diagonal term
        !
3000    ir = jr + 1
        ie = jd - 1
        k  = j  - jd
        do 4000 i = ir,ie
            id = idiag(k+i)
            if(abs(a(id)) > 0.) then
                d    = a(i)
                a(i) = a(i)/a(id)
                a(jd)= a(jd) - d*a(i)
            endif
4000    continue
        !

6000 jr = jd

    END  SUBROUTINE skfacs_layer

    SUBROUTINE sksols_layer(a,x,idiag,ilayer)
    integer(ink) ilayer,eq1,eq2,idiag(:)
    integer(ink) jr,j,jd,jh,is,i,id,k
    real   (irk) d,a(  :), x( :)
    real(irk),allocatable::ia(:),la(:)
    !
    !---- f o r w a r d    s u b s t i t u t i o n   p a s s
    !
    !
    if(ilayer==1) then
        eq1=1
        eq2=neq_layer1
    elseif(ilayer==2) then
        eq1=neq_layer1+1
        eq2=neq
    endif


950 jr = 0
    if(ilayer==2)jr=idiag(neq_layer1)
    do 2000 j = eq1,eq2
        jd   = idiag(j)
        jh   = jd - jr
        is   = j  - jh + 2
        if(jh - 2) 2000,1000,1000
        !
1000    x(j) = x(j) - dot_product(a(jr+1:jr+jh-1),x(is-1:is+jh-3))       !nzw 2006-08-08 for ivf
        !1000         x(j) = x(j) - dots(a(jr+1),x(is-1),jh-1)
2000 jr = jd
    !
    !
    !---- s c a l i n g     p a s s
    !
2500 continue
    do 3000 i = eq1,eq2
        id = idiag(i)
        if(abs(a(id)) > 0.)   x(i) = x(i) / a(id)
3000 continue
    !
    !---- b a c k s u b s t i t u t i o n    p a s s
    !
    j  = eq2
    jd = idiag(j)
4000 d  = x(j)
    j  = j - 1
    if(j .le. (eq1-1))                          go to 7600
    jr  = idiag(j)
    if(jd-jr .le. 1)                     go to 6000
    is = j - jd + jr + 2
    k = jr - is + 1
    do 5000 i = is,j
        x(i) = x(i) - a(i+k)*d
5000 continue
6000 jd = jr
    go to 4000
    !
    !---- e n d   s e c t i o n
    !
7600 continue
    !
    END SUBROUTINE sksols_layer

    !! end of nlayer==2

    SUBROUTINE sksols(a,x,idiag)
    integer(ink) idiag(:)
    integer(ink) jr,j,jd,jh,is,i,id,k
    real   (irk) d,zero,tol,a(  :), x( :)
    data zero,tol/0.0_irk,1.e-7/
    real(irk),allocatable::ia(:),la(:)
    !
    !---- f o r w a r d    s u b s t i t u t i o n   p a s s
    !
    !
    if(neq==0) return  !2017/11/27
950 jr = 0
    do 2000 j = 1,neq
        jd   = idiag(j)
        jh   = jd - jr
        is   = j  - jh + 2
        if(jh - 2) 2000,1000,1000
        !
        !1000         x(j) = x(j) - dots(a(jr+1),x(is-1),jh-1)
1000    x(j) = x(j) - dot_product(a(jr+1:jr+jh-1),x(is-1:is+jh-3))       !nzw 2006-08-08 for ivf
2000 jr = jd
    !
    !
    !---- s c a l i n g     p a s s
    !
2500 continue
    do 3000 i = 1,neq
        id = idiag(i)
        if(abs(a(id)) > zero)   x(i) = x(i) / a(id)
        !         if(abs(a(id)) > tol)   x(i) = x(i) / a(id)
3000 continue
    !
    !---- b a c k s u b s t i t u t i o n    p a s s
    !
    j  = neq
    jd = idiag(j)
4000 d  = x(j)
    j  = j - 1
    if(j .le. 0)                          go to 7600
    jr  = idiag(j)
    if(jd-jr .le. 1)                     go to 6000
    is = j - jd + jr + 2
    k = jr - is + 1
    do 5000 i = is,j
        x(i) = x(i) - a(i+k)*d
5000 continue
6000 jd = jr
    go to 4000
    !
    !---- e n d   s e c t i o n
    !
7600 continue
    !
    END SUBROUTINE sksols

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!w

    SUBROUTINE sksolsw(a,x,idiag)
    integer(ink) idiag(:)
    integer(ink) jr,j,jd,jh,is,i,id,k
    complex  (irk) d,a(  :), x( :)
    real  (irk) zero,tol
    data zero,tol/0.0_irk,1.e-7/
    complex(irk),allocatable::ia(:),la(:)
    !
    !---- f o r w a r d    s u b s t i t u t i o n   p a s s
    !
    !
950 jr = 0
    do 2000 j = 1,neq
        jd   = idiag(j)
        jh   = jd - jr
        is   = j  - jh + 2
        if(jh - 2) 2000,1000,1000
        !
1000    x(j) = x(j) - dot_product(conjg(a(jr+1:jr+jh-1)),x(is-1:is+jh-3))       !nzw 2006-08-08 for ivf
        !1000         x(j) = x(j) - dotsw(a(jr+1),x(is-1),jh-1)
2000 jr = jd
    !
    !
    !---- s c a l i n g     p a s s
    !
2500 continue
    do 3000 i = 1,neq
        id = idiag(i)
        if(abs(a(id)) > zero)   x(i) = x(i) / a(id)
        !         if(abs(a(id)) > tol)   x(i) = x(i) / a(id)
3000 continue
    !
    !---- b a c k s u b s t i t u t i o n    p a s s
    !
    j  = neq
    jd = idiag(j)
4000 d  = x(j)
    j  = j - 1
    if(j .le. 0)                          go to 7600
    jr  = idiag(j)
    if(jd-jr .le. 1)                     go to 6000
    is = j - jd + jr + 2
    k = jr - is + 1
    do 5000 i = is,j
        x(i) = x(i) - a(i+k)*d
5000 continue
6000 jd = jr
    go to 4000
    !
    !---- e n d   s e c t i o n
    !
7600 continue
    !
    END SUBROUTINE sksolsw
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!w

    SUBROUTINE sksols_bt(a,x,idiag)   !ctt2005
    integer(ink) idiag(:)
    integer(ink) jr,j,jd,jh,is,i,id,k
    real   (irk) d,zero,tol,a(  :), x( :)
    data zero,tol/0.0_irk,1.e-7/
    real(irk),allocatable::ia(:),la(:)
    !
    !---- f o r w a r d    s u b s t i t u t i o n   p a s s
    !
    !
950 jr = 0
    do 2000 j = 1,neq_bt
        jd   = idiag(j)
        jh   = jd - jr
        is   = j  - jh + 2
        if(jh - 2) 2000,1000,1000
        !
        !1000         x(j) = x(j) - dots(a(jr+1),x(is-1),jh-1)
1000    x(j) = x(j) - dot_product(a(jr+1:jr+jh-1),x(is-1:is+jh-3))       !nzw 2006-08-08 for ivf
2000 jr = jd
    !
    !
    !---- s c a l i n g     p a s s
    !
2500 continue
    do 3000 i = 1,neq_bt
        id = idiag(i)
        if(abs(a(id)) > zero)   x(i) = x(i) / a(id)
        !         if(abs(a(id)) > tol)   x(i) = x(i) / a(id)
3000 continue
    !
    !---- b a c k s u b s t i t u t i o n    p a s s
    !
    j  = neq_bt
    jd = idiag(j)
4000 d  = x(j)
    j  = j - 1
    if(j .le. 0)                          go to 7600
    jr  = idiag(j)
    if(jd-jr .le. 1)                     go to 6000
    is = j - jd + jr + 2
    k = jr - is + 1
    do 5000 i = is,j
        x(i) = x(i) - a(i+k)*d
5000 continue
6000 jd = jr
    go to 4000
    !
    !---- e n d   s e c t i o n
    !
7600 continue
    !
    END SUBROUTINE sksols_bt  !ctt2005
    !! end the direct solver LDU for symmetric problems


    !
    ! the following is the LDU for non-symmetric problems from P.Mira
    SUBROUTINE skfaca(a,c,idiag,iafile)
    !
    !---- program to perform an in-core factorisation of a sparse
    !         unsymmetric matrix stored skyline fashion
    !
    !     notice :
    !     -------
    !             . the upper triangular part of the input unsymmetric
    !               matrix a is stored column-wise skyline fashion,including
    !               diagonal entries.
    !             . the lower triangular part is stored row-wise,the same
    !               way in matrix c which has then the same size as a.
    !               diagonal entries are stored again in c.
    !             . the skyline profile is supposed symmetric
    !
    !
    !                   .  a11  a12   0    0    0    0   .
    !                   .                                .
    !                   .  a21  a22  a23   0   a25   0   .
    !                   .                                .
    !                   .   0   a32  a33  a34  a35   0   .
    !            a =    .                                .
    !                   .   0    0   a43  a44   0   a46  .
    !                   .                                .
    !                   .   0   a52   0   a54  a55  a56  .
    !                   .                                .
    !                   .   0    0    0   a64  a65  a66  .
    !
    !               . a is represented in 14-word string :
    !
    !           a11 a12 a22 a23 a33 a34 a44 a25 a35 a45 a55 a46 a56 a66
    !
    !               . and c is represented in a 14-word string
    !
    !           a11 a21 a22 a32 a33 a43 a44 a52 a53 a54 a55 a64 a65 a66
    !
    !               . the position of the diagonal element is marked by a
    !                 n+1-word integer array idiag :
    !
    !               idiag :  1 3 5 7 11 14
    !
    !               . factorisation is peformed into a upper triangular
    !
    !                 matrix u , a lower triangular matrix l and a diagonal
    !                 matrix d :
    !
    !                             k =   l  d  u
    !
    !                 matrix u and l have same profile than k and since u
    !                 and l have unit diagonal entries, the diagonal one of
    !                 d are placed in u.
    !
    !     arrays id. :
    !     ----------
    !                  . a    (na)  : coefficients of the upper part
    !                  . c    (na)  : coefficients of the lower part
    !                  . idiag(ieq) : addresses of diagonal terms
    !                  . na=idiag(neq)
    !                  . iafile     : file number for saving origin. matrix
    !                                 .eq. 0  . matrix not saved
    !
    !     external subroutines :
    !     ---------------------
    !                               . dot
    !
    integer(ink) iafile,idiag(:)
    integer(ink) jr,j,jd,jh,ns,ne,k,id,nt,i,ir
    real   (irk) a(:),c(:)
    real,parameter::zero=0.0_irk
    real(irk),allocatable::ia(:),la(:)
    !
    !----                i n i t i a l i z a t i o n
    !
    !
    !---- save original matrix if needed
    !
    if(iafile .ne. 0)    then
        rewind iafile
        write(iafile) a,c
    endif
    !
    !----              f a c t o r i z a t i o n   p h a s e
    !
    jr = 0
    do 6000 j = 1,neq
        jd = idiag(j)
        jh = jd - jr
        if(jh .le.  1)                           goto 6000
        ns = j+1 - jh
        ne = j - 1
        k  = jr + 1
        id = 0
        !
        !----       reduce all coefficients except diagonal terms
        !
        do 3000 i = ns,ne
            ir = id
            id = idiag(i)
            nt = min(id-ir-1,i-ns)
            if(nt .eq. 0)                       goto 2000
            !                  a(k) = a(k) - DOTs(a(k-nt),c(id-nt),nt)
            !                  c(k) = c(k) - dots(c(k-nt),a(id-nt),nt)
            a(k) = a(k) - dot_product(a(k-nt:k-1),c(id-nt:id-1))       !nzw 2006-08-08 for ivf
            c(k) = c(k) - dot_product(c(k-nt:k-1),a(id-nt:id-1))
2000        if(abs(a(id)) .gt. zero)   c(k) = c(k) / a(id)
3000    k = k + 1
        !
        !----          reduce diagonal term
        !
        a(jd) = a(jd) - dot_product(a(jr+1:jr+jh-1),c(jr+1:jr+jh-1))       !nzw 2006-08-08 for ivf
        !			   a(jd) = a(jd) - dots(a(jr+1),c(jr+1),jh-1)
6000 jr = jd
    !
    !---- save factorization if iafile .ne. 0
    !
    if(iafile .ne. 0) then
        write(iafile) a, c
    endif

    !
    !----
    !
    END SUBROUTINE skfaca
    !!!!!!!!!!!!!!!!!!
    SUBROUTINE skfaca_bt(a,c,idiag,iafile)
    integer(ink) iafile,idiag(:)
    integer(ink) jr,j,jd,jh,ns,ne,k,id,nt,i,ir
    real   (irk) a(:),c(:)
    real,parameter::zero=0.0_irk
    !
    !----                i n i t i a l i z a t i o n
    !
    !
    !---- save original matrix if needed
    !
    if(iafile .ne. 0)    then
        rewind iafile
        write(iafile) a,c
    endif
    !
    !----              f a c t o r i z a t i o n   p h a s e
    !
    jr = 0
    do 6000 j = 1,neq_bt
        jd = idiag(j)
        jh = jd - jr
        if(jh .le.  1)                           goto 6000
        ns = j+1 - jh
        ne = j - 1
        k  = jr + 1
        id = 0
        !
        !----       reduce all coefficients except diagonal terms
        !
        do 3000 i = ns,ne
            ir = id
            id = idiag(i)
            nt = min(id-ir-1,i-ns)
            if(nt .eq. 0)                       goto 2000
            !                a(k) = a(k) - DOTs(a(k-nt),c(id-nt),nt)
            !                c(k) = c(k) - dots(c(k-nt),a(id-nt),nt)
            a(k) = a(k) - dot_product(a(k-nt:k-1),c(id-nt:id-1))       !nzw 2006-08-08 for ivf
            c(k) = c(k) - dot_product(c(k-nt:k-1),a(id-nt:id-1))
2000        if(abs(a(id)) .gt. zero)   c(k) = c(k) / a(id)
3000    k = k + 1
        !
        !----          reduce diagonal term
        !
        a(jd) = a(jd) - dot_product(a(jr+1:jr+jh-1),c(jr+1:jr+jh-1))       !nzw 2006-08-08 for ivf
        !               a(jd) = a(jd) - dots(a(jr+1),c(jr+1),jh-1)
        !
6000 jr = jd
    !
    !---- save factorization if iafile .ne. 0
    !
    if(iafile .ne. 0) then
        write(iafile) a, c
    endif

    !
    !----
    !
    END SUBROUTINE skfaca_bt
    !!!!!!!!!!!!!!!!!!!!!!!!!!!w
    SUBROUTINE skfacaw(a,c,idiag)
    integer(ink) iafile,idiag(:)
    integer(ink) jr,j,jd,jh,ns,ne,k,id,nt,i,ir
    complex   (irk) a(:),c(:)
    real,parameter::zero=0.0_irk
    complex(irk),allocatable::ia(:),la(:)
    !
    !
    !----              f a c t o r i z a t i o n   p h a s e
    !
    jr = 0
    do 6000 j = 1,neq
        jd = idiag(j)
        jh = jd - jr
        if(jh .le.  1)                           goto 6000
        ns = j+1 - jh
        ne = j - 1
        k  = jr + 1
        id = 0
        !
        !----       reduce all coefficients except diagonal terms
        !
        do 3000 i = ns,ne
            ir = id
            id = idiag(i)
            nt = min(id-ir-1,i-ns)
            if(nt .eq. 0)                       goto 2000
            !                  a(k) = a(k) - DOTsw(a(k-nt),c(id-nt),nt)
            !                  c(k) = c(k) - dotsw(c(k-nt),a(id-nt),nt)
            a(k) = a(k) - dot_product(conjg(a(k-nt:k-1)),c(id-nt:id-1))
            c(k) = c(k) - dot_product(conjg(c(k-nt:k-1)),a(id-nt:id-1))       !nzw 2006-08-08 for ivf
2000        if(abs(a(id)) .gt. zero)   c(k) = c(k) / a(id)
3000    k = k + 1
        !
        !----          reduce diagonal term
        !
        !               a(jd) = a(jd) - dotsw(a(jr+1),c(jr+1),jh-1)
        a(jd) = a(jd) - dot_product(conjg(a(jr+1:jr+jh-1)),c(jr+1:jr+jh-1))       !nzw 2006-08-08 for ivf
6000 jr = jd
    !
    !
    END SUBROUTINE skfacaw
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!w

    SUBROUTINE sksola(a,x,c,idiag)
    !
    !---- program to solve an unsymmetrical system of equations where the
    !     skyline-stored matrix has already been factorized by skfaca
    !
    !     external subroutines :
    !     --------------------
    !                            . dot
    !
    real,parameter:: zero=0.0_irk

    integer(ink) idiag(:)
    integer(ink) i,jr,j,jd,jh,ns,ne,m,k
    real   (irk) d,a(:), c(:), x(:)
    real(irk),allocatable::ia(:),la(:)
    !
    !
    !----             f o r w a r d   s u b s t i t u t i o n
    !
    jr = 0
    do 2000 j = 1,neq
        jd = idiag(j)
        jh = jd - jr
        if(jh .le. 1)                              goto 2000
        ns = j+1 - jh
        ne = j - 1
        !           x(j) = x(j) - dots(c(jr+1),x(ns),jh-1)
        x(j) = x(j) - dot_product(c(jr+1:jr+jh-1),x(ns:ns+jh-2))      !nzw 2006-08-08 for ivf
2000 jr = jd
    !
    !----              s c a l i n g   p a s s
    !
    j  = neq
    jd = idiag(j)
    if(abs(a(jd)) .gt. zero)  x(j) = x(j) / a(jd)
    if(neq .eq. 1)                                       return
    !
    !----    b a c k -  s u b s t i t u t i o n    p a s s
    !
3000 d = x(j)
    j = j - 1
    jr = idiag(j)
    if(jd-jr .le. 1)                             goto 5000
    m = j-jd + jr + 2
    k = jr - m + 1
    do 4000 i = m,j
        x(i) = x(i) - a(i+k)*d
4000 continue
5000 jd = jr
    if(abs(a(jd)) .gt. zero)   x(j) = x(j) / a(jd)
    if(j .gt. 1)               goto 3000
    END SUBROUTINE sksola

    !********************************************************

    SUBROUTINE sksola_bt(a,x,c,idiag)
    !
    !---- program to solve an unsymmetrical system of equations where the
    !     skyline-stored matrix has already been factorized by skfaca
    !
    !     external subroutines :
    !     --------------------
    !                            . dot
    !
    real,parameter:: zero=0.0_irk

    integer(ink) idiag(:)
    integer(ink) i,jr,j,jd,jh,ns,ne,m,k
    real   (irk) d,a(:), c(:), x(:)
    !
    !
    !----             f o r w a r d   s u b s t i t u t i o n
    !
    jr = 0
    do 2000 j = 1,neq_bt
        jd = idiag(j)
        jh = jd - jr
        if(jh .le. 1)                              goto 2000
        ns = j+1 - jh
        ne = j - 1
        !            x(j) = x(j) - dots(c(jr+1),x(ns),jh-1)
        x(j) = x(j) - dot_product(c(jr+1:jr+jh-1),x(ns:ns+jh-2))      !nzw 2006-08-08 for ivf
2000 jr = jd
    !
    !----              s c a l i n g   p a s s
    !
    j  = neq_bt
    jd = idiag(j)
    if(abs(a(jd)) .gt. zero)  x(j) = x(j) / a(jd)
    if(neq_bt .eq. 1)                                       return
    !
    !----    b a c k -  s u b s t i t u t i o n    p a s s
    !
3000 d = x(j)
    j = j - 1
    jr = idiag(j)
    if(jd-jr .le. 1)                             goto 5000
    m = j-jd + jr + 2
    k = jr - m + 1
    do 4000 i = m,j
        x(i) = x(i) - a(i+k)*d
4000 continue
5000 jd = jr
    if(abs(a(jd)) .gt. zero)   x(j) = x(j) / a(jd)
    if(j .gt. 1)               goto 3000
    END SUBROUTINE sksola_bt
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!W
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!W

    SUBROUTINE sksolaw(a,x,c,idiag)
    !
    !---- program to solve an unsymmetrical system of equations where the
    !     skyline-stored matrix has already been factorized by skfaca
    !
    !     external subroutines :
    !     --------------------
    !                            . dot
    !
    real,parameter:: zero=0.0_irk

    integer(ink) idiag(:)
    integer(ink) i,jr,j,jd,jh,ns,ne,m,k
    complex   (irk) d,a(:), c(:), x(:)
    complex(irk),allocatable::ia(:),la(:)
    !
    !
    !----             f o r w a r d   s u b s t i t u t i o n
    !
    jr = 0
    do 2000 j = 1,neq
        jd = idiag(j)
        jh = jd - jr
        if(jh .le. 1)                              goto 2000
        ns = j+1 - jh
        ne = j - 1
        !            x(j) = x(j) - dotsw(c(jr+1),x(ns),jh-1)
        x(j) = x(j) - dot_product(conjg(c(jr+1:jr+jh-1)),x(ns:ns+jh-2))       !nzw 2006-08-08 for ivf
2000 jr = jd
    !
    !----              s c a l i n g   p a s s
    !
    j  = neq
    jd = idiag(j)
    if(abs(a(jd)) .gt. zero)  x(j) = x(j) / a(jd)
    if(neq .eq. 1)                                       return
    !
    !----    b a c k -  s u b s t i t u t i o n    p a s s
    !
3000 d = x(j)
    j = j - 1
    jr = idiag(j)
    if(jd-jr .le. 1)                             goto 5000
    m = j-jd + jr + 2
    k = jr - m + 1
    do 4000 i = m,j
        x(i) = x(i) - a(i+k)*d
4000 continue
5000 jd = jr
    if(abs(a(jd)) .gt. zero)   x(j) = x(j) / a(jd)
    if(j .gt. 1)               goto 3000
    END SUBROUTINE sksolaw
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!W

    ! the following is the LDU for non-symmetric problems from P.Mira
    SUBROUTINE skfaca_layer(a,c,idiag,iafile,ilayer)
    !

    !
    integer(ink) iafile,idiag(:)
    integer(ink) jr,j,jd,jh,ns,ne,k,id,nt,i,ir,ilayer,eq1,eq2
    real   (irk) a(:),c(:)
    real,parameter::zero=0.0_irk
    real(irk),allocatable::ia(:),la(:)
    !
    !----                i n i t i a l i z a t i o n
    !
    !
    !---- save original matrix if needed
    !
    if(iafile .ne. 0)    then
        rewind iafile
        write(iafile) a,c
    endif
    !
    !----              f a c t o r i z a t i o n   p h a s e
    !
    if(ilayer==1) then
        eq1=1
        eq2=neq_layer1
    elseif(ilayer==2) then
        eq1=neq_layer1+1
        eq2=neq
    endif

    jr = 0
    if(ilayer==2)jr=idiag(neq_layer1)
    do 6000 j = eq1,eq2
        jd = idiag(j)
        jh = jd - jr
        if(jh .le.  1)                           goto 6000
        ns = j+1 - jh
        ne = j - 1
        k  = jr + 1
        id = 0
        !
        !----       reduce all coefficients except diagonal terms
        !
        do 3000 i = ns,ne
            ir = id
            id = idiag(i)
            nt = min(id-ir-1,i-ns)
            if(nt .eq. 0)                       goto 2000
            !                  a(k) = a(k) - DOTs(a(k-nt),c(id-nt),nt)
            !                  c(k) = c(k) - dots(c(k-nt),a(id-nt),nt)
            a(k) = a(k) - dot_product(a(k-nt:k-1),c(id-nt:id-1))       !nzw 2006-08-08 for ivf
            c(k) = c(k) - dot_product(c(k-nt:k-1),a(id-nt:id-1))

2000        if(abs(a(id)) .gt. zero)   c(k) = c(k) / a(id)
3000    k = k + 1
        !
        !----          reduce diagonal term
        !
        !               a(jd) = a(jd) - dots(a(jr+1),c(jr+1),jh-1)
        a(jd) = a(jd) - dot_product(a(jr+1:jr+jh-1),c(jr+1:jr+jh-1))       !nzw 2006-08-08 for ivf

        !
6000 jr = jd
    !
    !---- save factorization if iafile .ne. 0
    !
    if(iafile .ne. 0) then
        write(iafile) a, c
    endif

    !
    !----
    !
    END SUBROUTINE skfaca_layer

    SUBROUTINE sksola_layer(a,x,c,idiag,ilayer)
    !
    !---- program to solve an unsymmetrical system of equations where the
    !     skyline-stored matrix has already been factorized by skfaca
    !
    !     external subroutines :
    !     --------------------
    !                            . dot
    !
    real,parameter:: zero=0.0_irk

    integer(ink) idiag(:)
    integer(ink) i,jr,j,jd,jh,ns,ne,m,k,ilayer,eq1,eq2
    real   (irk) d,a(:), c(:), x(:)
    real(irk),allocatable::ia(:),la(:)
    !
    !
    !----             f o r w a r d   s u b s t i t u t i o n
    !

    if(ilayer==1) then
        eq1=1
        eq2=neq_layer1
    elseif(ilayer==2) then
        eq1=neq_layer1+1
        eq2=neq
    endif

    jr = 0
    if(ilayer==2)jr=idiag(neq_layer1)
    do 2000 j = eq1,eq2
        jd = idiag(j)
        jh = jd - jr
        if(jh .le. 1)                              goto 2000
        ns = j+1 - jh
        ne = j - 1
        !            x(j) = x(j) - dots(c(jr+1),x(ns),jh-1)
        x(j) = x(j) - dot_product(c(jr+1:jr+jh-1),x(ns:ns+jh-1))       !nzw 2006-08-08 for ivf

2000 jr = jd
    !
    !----              s c a l i n g   p a s s
    !
    j  = eq2
    jd = idiag(j)
    if(abs(a(jd)) .gt. zero)  x(j) = x(j) / a(jd)
    if((eq2-eq1+1) .eq. 1)                                       return
    !
    !----    b a c k -  s u b s t i t u t i o n    p a s s
    !
3000 d = x(j)
    j = j - 1
    jr = idiag(j)
    if(jd-jr .le. 1)                             goto 5000
    m = j-jd + jr + 2
    k = jr - m + 1
    do 4000 i = m,j
        x(i) = x(i) - a(i+k)*d
4000 continue
5000 jd = jr
    if(abs(a(jd)) .gt. zero)   x(j) = x(j) / a(jd)
    if(j .gt. eq1)               goto 3000
    END SUBROUTINE sksola_layer

    !********************************************************

    subroutine pivots(a,c,idiag,isymm,ylost,icond,           &
        ipdchk,ising,iafile)
    !
    !---- programme to determine the condition number of the matrix  .a.
    !      skyline-stored and the number of zero and negative pivots
    !      in the array d of the factorisation .a. = .l. .d. .u.
    !
    !     notice :
    !     ------   .a    (na) = aupper part of matrix a compact column
    !                           stored
    !
    !              .c    (na) = alower part of matrix a if nonsymmetric
    !                           case,compact row stored
    !
    !              .idiag(neq)= diagonal address
    !
    !              .v1(neq)   = work array must be composed of
    !                             .neq words
    !
    !              .x(neq)    = solution array must be composed
    !                           of .neq words
    !
    !              .epsmac    = flooting point machine accurancy
    !                          .cdc 6000/7000    7.11e-15 (single precis.)
    !                          .ibm 360/370      9.54e-07 (real*4 precis.)
    !                          .ibm 360/370      2.22e-16 (real*8 precis.)
    !                          .univac 1108/1110 1.49e-08 (single precis.)
    !                          .ibm 7094         1.49e-08 (single precis.)
    !
    !              .icond     = conditioning test
    !                           .eq. 0 no conditioning test
    !                           .eq. 1 conditioning test performed
    !
    !              .ipdchk    = positive definitness index
    !                           .eq. 1  then stop if non positive defin.
    !                           .eq. 0 continue but warning
    !
    !              .ising    = singularity test index
    !                           .eq. 1 then assign default value to pivot
    !                           .eq. 0 continue but ???????
    !
    !     external subroutines :
    !     --------------------
    !                          . sqrow
    !
    !     input/output devices :
    !     --------------------
    !                            .iout   = line printer output
    !                            .iafile = temporary file for matrix
    !                                      .a.
    !
    !
    !---- remove above card for single precision operation
    !
    !----
    !
    integer(ink) iafile, icond, isymm, ipdchk, ising, idiag(:)
    integer(ink) negeig,nezpiv,i,n
    real   (irk) ylost, eight, zero, epsmac, tolrow
    real   (irk) a(  :), c(   :)
    real   (irk), allocatable:: v1(:)
    !
    data eight,zero/8.0,0.0/
    !
    data epsmac/2.22E-16/
    !
    !---- remove above card for single precision operation
    !
    !
    !---- i n i t i a l i s a t i o n
    !
    allocate(v1(neq))
    negeig = 0
    nezpiv = 0
    !
    !----
    !
    if(icond /= 0 .and. abs(ylost) > zero) then
        write(chkunit,100) ylost
    endif
    !
    if(iafile /= 0 .and. ising == 1) then
        v1=0.0
        rewind(iafile)
        if(isymm == 0) then
            read(iafile) a
        else
            read(iafile) a,c
        endif
        !
        call sqrow(v1,a,c,idiag,neq,isymm)
        !
        if(isymm == 0) then
            read(iafile) a
        else
            read(iafile) a,c
        endif
        !
    endif
    !
    do 5000 n=1,neq
        i = idiag(n)
        if(ising == 1) then
            !
            !----       s i n g u l a r i t y   t e s t
            !
            tolrow = eight*epsmac*sqrt(v1(n))
            if(abs(a(i)) <= tolrow) then
                a(i) = tolrow
                nezpiv = nezpiv + 1
            endif
            !
        endif
        !
        !----    p o s i t i v  d e f i n i t n e s s   c h e c k
        !
        if(a(i) <= zero) then
            negeig = negeig + 1
            if(ipdchk == 1) then
                write(chkunit,300)
                !               stop
            endif
        endif
5000 continue
    !
    !---- output the results
    !
    if(negeig > 0 .or. nezpiv > 0) then
        write(chkunit,200) negeig,nezpiv,tolrow
    endif
    if(nezpiv > 0) then
        write(chkunit,200) negeig,nezpiv,tolrow
        !         stop
    endif
    deallocate (v1)
    !
    !
    !---- formats
    !
100 format(/                                                  &
        'w a r n i n g : number of sigificant digit lost .',/      &
        '                . ylost(b. taylor)   --- = ',e20.8)
200 format(1h0,                                              &
        40h zero and/or negative pivots encountered,//,          &
        5x,35h number of negatives or zero      =,i5,//,          &
        5x,35h number of singular case          =,i5,//,          &
        5x,35h test value machine dependant     =,e20.8//)
300 format(/' s i n g u l a r   m a t r i x ')
    !
    !----
    !
    end subroutine pivots

    subroutine sqrow (v,a,c,idiag,neq,isymm)
    !
    !---- program to compute the euclidean norm of the rows of a matrix
    !      stored skyline-wise for symmetric and unsymmetric case
    !
    !     notice :
    !     ------
    !              .v(neq)       = work array store the norm of each row
    !
    !              .a(na)        = upper part of matrix a stored compact
    !                              column-wise
    !
    !             .c(na)        = lower part of matrix a stored compact
    !                              row-wise
    !
    !              .idiag(neq)   = diagonal adresses in a and c as well
    !
    !              .isymm        = symmetric flag :
    !                               .eq. 0   symmetric case
    !                               .eq. 1   unsymmetric case
    !
    !
    !---- remove above card for single precision operation
    !
    integer(ink) j,jj,je,jb,js,jd, neq,isymm,idiag(:)
    real(irk) ab, a(:), c(:), v(:)
    !
    js = 1
    do 2000 j = 1,neq
        jd = idiag(j)
        if(js > jd)                             go to 2000
        ab = a(jd) * a(jd)
        if(js == jd)                          go to 1500
        jb = j - jd
        je = jd -1
        do 1000 jj = js,je
            if(isymm == 0) ab = ab + a(jj)*a(jj)
            if(isymm == 1) ab = ab + c(jj)*c(jj)
1000    v(jj+jb) = v(jj+jb) + a(jj)*a(jj)
1500    v(j) = v(j) + ab
2000 js = jd + 1
    !
    end subroutine sqrow


    function dots(a,b,n)
    integer(ink)i, n
    real(irk) dots, a(n),b(n)
    dots=0.0
    do 10 i=1,n
10  dots=dots+a(i)*b(i)
    end function dots

    function dotsw(a,b,n)
    integer(ink)i, n
    complex(irk) dotsw, a(n),b(n)
    dotsw=0.0
    do 10 i=1,n
10  dotsw=dotsw+a(i)*b(i)
    end function dotsw

    !! finishing solver for unsymmetric LDU     from P. Mira

    !!PBCG solver from NUMERICAL RECIPES
    SUBROUTINE linbcg(n,b,x,itol,tol,itmax)
    INTEGER(ink) iter,itmax,itol,n
    REAL   (irk) err,tol,b(:),x(:)
    REAL        ,PARAMETER:: EPS=1.0_irk
    !U    USES atimes,asolve,snrm
    INTEGER(ink) j
    REAL   (irk) ak,akden,bk,bkden,bknum,bnrm,dxnrm,xnrm,zm1nrm,   &
        znrm
    REAL   (irk),ALLOCATABLE::p(:),pp(:),r(:),rr(:),z(:),zz(:)

    allocate(p(n),pp(n),r(n),rr(n),z(n),zz(n))
    iter=0
    call atimes(n,x,r,0)
    do 11 j=1,n
        r(j)=b(j)-r(j)
        rr(j)=r(j)
11  continue
    !     call atimes(n,r,rr,0)
    if(itol.eq.1) then
        bnrm=snrm(n,b,itol)
        call asolve(n,r,z)

    else if (itol.eq.2) then
        call asolve(n,b,z)
        bnrm=snrm(n,z,itol)
        call asolve(n,r,z)
    else if (itol.eq.3.or.itol.eq.4) then
        call asolve(n,b,z)
        bnrm=snrm(n,z,itol)
        call asolve(n,r,z)
        znrm=snrm(n,z,itol)
    else
        pause 'illegal itol in pbcg'
    endif
100 if (iter.le.itmax) then
        iter=iter+1
        call asolve(n,rr,zz)
        bknum=0.0
        do 12 j=1,n
            bknum=bknum+z(j)*rr(j)
12      continue
        if(iter.eq.1) then
            do 13 j=1,n
                p(j)=z(j)

                pp(j)=zz(j)
13          continue
        else
            bk=bknum/bkden
            do 14 j=1,n
                p(j)=bk*p(j)+z(j)
                pp(j)=bk*pp(j)+zz(j)
14          continue
        endif
        bkden=bknum
        call atimes(n,p,z,0)
        akden=0.0
        do 15 j=1,n
            akden=akden+z(j)*pp(j)
15      continue
        ak=bknum/akden
        call atimes(n,pp,zz,1)
        do 16 j=1,n
            x(j)=x(j)+ak*p(j)
            r(j)=r(j)-ak*z(j)
            rr(j)=rr(j)-ak*zz(j)
16      continue
        call asolve(n,r,z)
        if(itol.eq.1)then

            err=snrm(n,r,itol)/bnrm
        else if(itol.eq.2)then
            err=snrm(n,z,itol)/bnrm
        else if(itol.eq.3.or.itol.eq.4)then
            zm1nrm=znrm
            znrm=snrm(n,z,itol)
            if(abs(zm1nrm-znrm).gt.EPS*znrm) then
                dxnrm=abs(ak)*snrm(n,p,itol)
                err=znrm/abs(zm1nrm-znrm)*dxnrm
            else
                err=znrm/bnrm
                goto 100
            endif
            xnrm=snrm(n,x,itol)
            if(err.le.0.5_irk*xnrm) then
                err=err/xnrm

            else
                err=znrm/bnrm
                goto 100
            endif
        endif
        write (*,*) ' iter=',iter,' err=',err
        if(err.gt.tol) goto 100
    endif
    deallocate(p,pp,r,rr,z,zz)

    contains

    ! 1. asolve
    SUBROUTINE asolve(n,b,x)
    INTEGER(ink) n,i
    REAL   (irk) x(:),b(:)
    do 11 i=1,n
        x(i)=b(i)/global_stiff1(i)
11  continue
    END SUBROUTINE asolve

    !2. atimes

    SUBROUTINE atimes(n,x,r,itrnsp)
    INTEGER(ink) n,itrnsp
    REAL   (irk) x(:),r(:)
    !U    USES dsprsax,dsprstx
    if (itrnsp.eq.0) then
        call dsprsax(x,r,n)
    else
        call dsprstx(x,r,n)
    endif
    END SUBROUTINE atimes
    !2.1 dsprsax
    SUBROUTINE dsprsax(x,b,n)
    INTEGER(ink) n,i,k
    REAL   (irk) b(:),x(:)
    if (iseq(1).ne.n+2) pause 'mismatched vector and matrix in dsprsax'
    do 12 i=1,n
        b(i)=global_stiff1(i)*x(i)
        do 11 k=iseq(i),iseq(i+1)-1
            b(i)=b(i)+global_stiff1(k)*x(iseq(k))
11      continue
12  continue
    END SUBROUTINE dsprsax
    !2.2 dsprstx
    SUBROUTINE dsprstx(x,b,n)
    INTEGER(ink) n,i,j,k
    REAL   (irk) b(:),x(:)
    if (iseq(1).ne.n+2) pause 'mismatched vector and matrix in sprstx'
    do 11 i=1,n
        b(i)=global_stiff1(i)*x(i)
11  continue
    do 13 i=1,n
        do 12 k=iseq(i),iseq(i+1)-1
            j=iseq(k)
            b(j)=b(j)+global_stiff1(k)*x(i)
12      continue
13  continue
    END SUBROUTINE dsprstx

    END    SUBROUTINE linbcg

    !3. snrm
    FUNCTION snrm(n,sx,itol)
    INTEGER(ink) n,itol,i,isamax
    REAL   (irk) sx(:),snrm
    if (itol.le.3)then
        snrm=0.
        do 11 i=1,n
            snrm=snrm+sx(i)**2
11      continue
        snrm=sqrt(snrm)
    else
        isamax=1
        do 12 i=1,n
            if(abs(sx(i)).gt.abs(sx(isamax))) isamax=i
12      continue
        snrm=abs(sx(isamax))
    endif
    END  FUNCTION snrm

    SUBROUTINE BFGSR(JITER )
    !*******************************************************************
    !
    ! *** BFGS METHOD ( RANK-TWO INVERSE UPDATING )
    ! *** H. MATTHIES ET AL, INTER. J. NUM. METHODS ENG.,14,1613-26,1979
    !
    !*******************************************************************
    integer(ink) jiter,nvect,ivect,jvect,nintf,itotv,jtotv
    real(irk) betav,alfav
    real(irk),allocatable::betai(:),dvect(:,:),gvect(:,:),fsave(:)
    real(irk),allocatable::tdvec(:),tgvec(:),vecta(:),vectb(:),   &
        tvect(:,:),rvector0(:),resultm(:)
    integer(ink),pointer::listf(:)  !20220729
    real   (irk),pointer::rintf(:)  !20220729

    SAVE BETAI,DVECT,GVECT,FSAVE

    IF(jiter.EQ.1) THEN
        if(allocated(betai))deallocate(betai)
        if(allocated(dvect))deallocate(dvect)
        if(allocated(gvect))deallocate(gvect)
        if(allocated(fsave))deallocate(fsave)
        allocate(betai(miter),dvect(miter,neq),gvect(miter,neq),fsave(neq))
        fsave=rvector		  ! 1:NEQ
        operation='SOLVE'
        call solve
        dvect(jiter,:)=rvector(:) ! 1:neq
    ELSE
        NVECT=jITER-1
        allocate(tdvec(neq),tgvec(neq),vecta(neq),vectb(neq),tvect(nvect,neq))
        allocate(rvector0(neq))
        gvect(nvect,:)=-(rvector-fsave)
        fsave=rvector
        rvector=0.
        BETAV=0.00

        betav=betav+dvect(nvect,:).d.gvect(nvect,:)
        BETAI(NVECT)=1.00/BETAV

        tdvec=dvect(nvect,:)
        tgvec=gvect(nvect,:)
        ALFAV=TDVEC.d.FSAVE

        rvector=rvector+betai(nvect)*tdvec*alfav
        TVECT(NVECT,:)=FSAVE(:)-BETAI(NVECT)*TGVEC(:)*ALFAV

        IF(NVECT.GT.1) THEN
            DO 900 IVECT=NVECT-1,1,-1
                TDVEC=DVECT(IVECT,:)
                TGVEC=GVECT(IVECT,:)
                VECTA=TVECT(IVECT+1,:)
                ALFAV=TDVEC.d.VECTA
                TVECT(IVECT,:)=VECTA(:)-BETAI(IVECT)*TGVEC(:)*ALFAV
900         CONTINUE
        END IF

        rvector0=rvector

        VECTB=TVECT(1,:)
        rvector=vectb
        operation='SOLVE'
        call solve
        vectb=rvector

        DO 1400 IVECT=1,NVECT
            TDVEC=DVECT(IVECT,:)
            TGVEC=GVECT(IVECT,:)
            ALFAV=TGVEC.d.VECTB
            VECTB=VECTB-BETAI(IVECT)*TDVEC*ALFAV
1400    CONTINUE
        rvector0=rvector0+VECTB

        DO 3000 IVECT=1,NVECT-1
            VECTA=TVECT(IVECT+1,:)
            TDVEC=DVECT(IVECT,:)
            ALFAV=TDVEC.d.VECTA
            VECTB=BETAI(IVECT)*TDVEC*ALFAV
            DO 2000 JVECT=IVECT+1,NVECT
                TDVEC=DVECT(JVECT,:)
                TGVEC=GVECT(JVECT,:)
                ALFAV=TGVEC.d.VECTB
                VECTB=VECTB-BETAI(JVECT)*TDVEC*ALFAV
2000        CONTINUE
            rvector0=rvector0+VECTB
3000    CONTINUE
        DVECT(jITER,:)=rvector0



        allocate(resultm(ntotv))
        resultm=0.
        do itotv=1,ntotv
            nintf=trans(itotv)%nintf
            if(iffix(itotv)==0.and.nintf==0) then
                resultm(itotv)=result(totveq(itotv))
            elseif(nintf/=0) then
                listf=>trans(itotv)%listf
                rintf=>trans(itotv)%rintf
                do jtotv=1,nintf
                    if(totveq(listf(jtotv))>0)then
                        resultm(itotv)=resultm(itotv)+rvector0(totveq(listf(jtotv)))*rintf(jtotv)
                    endif
                enddo
                nullify(listf,rintf)
            endif
        end do
        !!int2000

        deallocate(result)
        allocate(result(ntotv))
        result=resultm
        deallocate(resultm)


        !where(iffix==0)
        !result=rvector0(totveq)	   ! 1:neq --->1:ntotv
        !elsewhere
        !result=0.0
        !endwhere

        deallocate(tdvec,tgvec,vecta,vectb,tvect,rvector0)
    END IF
    END SUBROUTINE BFGSR
    !
    subroutine find_dfact_of_arclength (irst)
    !***********************************************************************
    !
    !*** esta subrutina impone la restriccion delta p * delta p = deltal**2
    !*** asociada al metodo arc-length cilindrico de Crisfield
    !
    !******************************************************************
    !
    real(irk) time_begin,signo,fact_inc,detal,ncdis,a1,a2,a3,a4,a5,  &
        r1,r2,cost1,cost2
    integer(ink) nalgo,piter,giter,ifail,irst

    irst=0
    time_begin=tcurves(arc_curve)%time_begin

    if(ttime.le.time_begin)return

    nalgo=tcurves(arc_curve)%nalgo

    if (iiter.eq.1) then
        signo=delta_arclength.d.tofor_arclength
        if (signo.eq.0.00) signo=1.00
        signo=signo/abs(signo)
        if (abs(ttime-time_begin-ditime).le.1.e-8) then
            fact_inc=tcurves(arc_curve)%fact_inc

            if(nalgo.eq.2) then
                ncdis=tcurves(arc_curve)%ncdis
                detal=abs(fact_inc*delta_arclength(ncdis))
            else if(nalgo==1)then
                detal=fact_inc*sqrt(delta_arclength.d.delta_arclength)
            endif
            fact_inc=signo*fact_inc

        else

            detal=tcurves(arc_curve)%detal
            piter=tcurves(arc_curve)%piter
            giter=tcurves(arc_curve)%giter
            detal=detal*giter/piter

            if(nalgo.eq.2) then
                ncdis=tcurves(arc_curve)%ncdis
                fact_inc=signo*abs((detal-result(ncdis))/delta_arclength(ncdis))
            else if(nalgo==1)then
                fact_inc=signo*detal/sqrt(delta_arclength.d.delta_arclength)
            endif
        endif
        tcurves(arc_curve)%detal=detal
        !! above is for iiter==1
    else
        detal=tcurves(arc_curve)%detal

        if (nalgo.eq.2) then
            ncdis=tcurves(arc_curve)%ncdis
            fact_inc=(detal-deltafi(ncdis)-result(ncdis))/delta_arclength(ncdis)
        elseif(nalgo==1)then

            a1=delta_arclength.d.delta_arclength
            a2=2.*(delta_arclength.d.(deltafi+result))
            a3=(deltafi+result).d.(deltafi+result)
            a3=a3-detal**2
            a4=(deltafi+result).d.deltafi
            a5=delta_arclength.d.deltafi

            call qsolv(a1,a2,a3,r1,r2,ifail)

            if (ifail.eq.2) then
                !*** No real solutions
                write(*,*) "Raices complejas en arc-length"
                irst=1
                return
            elseif (ifail.eq.1) then
                !*** Only linear solution possible
                fact_inc=r1
            elseif(ifail.eq.0) then
                !*** Two real solutions
                cost1=a4+a5*r1
                cost2=a4+a5*r2
                fact_inc=r1
                if (cost2.gt.cost1) fact_inc=r2
            endif
        endif
    endif

    !	write(chkunit,*)'result***delta_arc_length'
    !	do ifail=1,ntotv
    !	write(chkunit,*)ifail,result(ifail),delta_arclength(ifail)
    !	end do
    result=result+fact_inc*delta_arclength
    tofor =tofor +fact_inc*tofor_arclength
    tcurves(arc_curve)%dfact=tcurves(arc_curve)%dfact+fact_inc

    end subroutine find_dfact_of_arclength

    subroutine qsolv(a,b,c,r1,r2,ifail)
    !***********************************************************************
    !
    !*** esta subrutina resuelve la ecuacion de segundo grado
    !*** asociada al metodo arc-length cilindrico de Crisfield
    !*** para obtener delta-landa
    !
    !***********************************************************************
    real   (irk) a,b,c,r1,r2,rlin
    real   (irk) small,discr
    integer(ink) ifail
    small=1.E-10
    ifail=0
    if(b.ne.0.0) rlin=-c/b
    discr=b*b-4*a*c
    if(discr.lt.0.0) then
        !***     No hay raices reales
        ifail=2
        return
    else
        !***     Hay raices reales
        discr=sqrt(discr)
        if(a.eq.0.0) then
            if(b.ne.0) then
                r1=rlin
                ifail=1
            else
                !***         No hay raices reales ni complejas porque no hay ecuacion (a=b=0.0)
                print *,'a=',a,'b=',b,'c=',c
                stop 'a=b=0 en ecuacion arclength'
            endif
        else
            !***       Hay raices reales
            r1=-0.5*( b+discr)/a
            r2= 0.5*(-b+discr)/a
        endif
    endif
    end subroutine qsolv





    end module solver




