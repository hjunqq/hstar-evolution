    module output

    use variable_types
    use global_var
    use prescribed
    use materials
    implicit none

    integer(ink) toutnode,iwriten,toutelement,toutgap,toutmcjoint

    real(irk),allocatable::maxdisp(:,:),maxv(:,:),maxacce(:,:),maxacce_a(:,:) !20231215YL

    type outpoint
        integer(ink) inode,jnode,idofn,nintf,nintf1 !20210803
        real   (irk),pointer::value(:)  !20210803
        real   (irk),pointer::wtime(:)
        integer(ink),pointer::listn(:),listn1(:)  !20210803
        real   (irk),pointer::rintn(:),rintn1(:)  !20210803
    end type outpoint

    type outelement
        integer(ink) ielem,istre
        real   (irk),pointer::value(:)
        real   (irk),pointer::wtime(:)
    end type outelement

    type outgap
        integer(ink) ielem
        real   (irk),pointer::value(:)
        real   (irk),pointer::wtime(:)
    end type outgap

    type outmcjoint
        integer(ink) ielem
        real   (irk),pointer::value(:,:)
        real   (irk),pointer::wtime(:)
    end type outmcjoint

    type outpoints
        integer(ink) toutnode,groupb
        type(outpoint),  allocatable::out_point_group(:)
    end type outpoints

    type(outpoints),  allocatable::out_point_groups(:)
    !type(outpoint),  allocatable::out_point_group(:)
    type(outelement),allocatable::out_element_group(:)
    type(outgap),    allocatable::out_gap_group(:)
    type(outmcjoint),allocatable::out_mcjoint_group(:)

    CONTAINS

    SUBROUTINE OUT_record_WRITE

    integer(ink) ioutnode,jwriten,idofn,ioutelement,icdofn,i0

    if (toutnode==0)goto 1

    if(Bparameter==-3)then
        rewind(observ_unit)
        write(observ_unit,*)'Nblks_pb/1:nblks_pb->/text/nincs_pb/1:nincs_pb->dtime_pb,nstep_p,bobserv_pb'
        write(observ_unit,20)1
        write(observ_unit,*)'NINCS'
        write(observ_unit,20)1
        write(observ_unit,30)ditime,nstep,1,1,1
        write(observ_unit,*)' observed values(1:nback_point)|1:nstoch:(1:tbstep)'
    endif

    do i0=1,wpgroup
        toutnode=out_point_groups(i0)%toutnode
        !write(outpwrite,*)'nodal value ouput**','toutnode=',toutnode,'tnstep=',iwriten
        write(outpwrite,*)'tnstep=',iwriten
        !do jwriten=1,iwriten  !20210803
        !    write(outpwrite,10)out_point_groups(i0)%out_point_group(1)%wtime(jwriten)
        !    write(outpwrite,10)(out_point_groups(i0)%out_point_group(ioutnode)%value(jwriten),ioutnode=1,toutnode)
        !end do
        !
        write(outpwrite,10)out_point_groups(i0)%out_point_group(1)%wtime(:)
        do ioutnode=1,toutnode  !20210803
            write(outpwrite,10)out_point_groups(i0)%out_point_group(ioutnode)%value(:)
            if(Bparameter==-3)then  !20231030
                write(observ_unit,20)ioutnode,ioutnode,out_point_groups(i0)%out_point_group(ioutnode)%idofn,0    !对应测点点号，方向号
                write(observ_unit,10)out_point_groups(i0)%out_point_group(ioutnode)%value(:)
            endif  !20231030
        end do
    end do
1   if(toutelement==0)goto 2
    do jwriten=1,iwriten
        write(outewrite,10)out_element_group(1)%wtime(jwriten),   &
            (out_element_group(ioutelement)%value(jwriten),     &
            ioutelement=1,toutelement)
    end do
2   if(toutgap==0)goto 3
    do jwriten=1,iwriten
        write(outgwrite,10)out_gap_group(1)%wtime(jwriten),   &
            (out_gap_group(ioutelement)%value(jwriten),     &
            ioutelement=1,toutgap)
    end do
3   if(toutmcjoint==0)return
    do icdofn=1,2
        do jwriten=1,iwriten
            write(outjwrite,10)out_mcjoint_group(1)%wtime(jwriten),   &
                (out_mcjoint_group(ioutelement)%value(icdofn,jwriten),     &
                ioutelement=1,toutmcjoint)
        end do
    end do

10  format(10(2x,e15.5))
20  format(10i10)
30  format(e11.4,10i10)

    END SUBROUTINE OUT_record_WRITE


    SUBROUTINE OUT_FULL_WRITE

    character(10) field1,class,name,criteria,model
    character(20) material
    integer(ink) igroup,matno,ielgroup,ielem,istate
    integer(ink) ipoin,len,index,order_int,igaus,npgblock, &
        nstre,ngaus,jndex,nnode,inode,jnode,idimn,noutfix,idofix,node1,igapb,igaps,npairs,ipairs,i1,i2,ij,ipair,igapbf,i12,kdimn
    real   (irk) smean,thick,coef
    integer(ink),allocatable::ipiact(:),ctnode(:)  !zhao 05/08/18
    real   (irk),allocatable::value(:),stres(:),pointact(:,:),rot(:,:),disg(:),disl(:),spring(:)
    integer(ink), pointer::ldofs(:),lnods(:)
    real   (irk), pointer::rotation(:,:)
    real   (irk),allocatable::rdis(:),x1(:),x2(:),eldis(:),trot(:,:), &
        force_e(:),force_i(:),trotx(:,:) !steel 2006
    !20231215YL
    integer(ink) liquj,istre !20231008
    real   (irk) sx,sy,sxy,delta
    real   (irk),allocatable::smax(:),smain(:)
    real   (irk), pointer::rr(:,:)
    !20231215YL

    write(7,*)'irecover=',irecover
    if (irecover==0) then
        write(outgpvar,*)'                             Element Stresses in Gauss Points'
    else if(irecover==-1) then
        write(outgpvar,*)nelem,',1,',2*ndimn
        if (ndimn==2)write(outgpvar,*)'Sig_x Sig_y Txy SigZ'
        if (ndimn==3)write(outgpvar,*)'Sig_x Sig_y SigZ Txy Tyz Tzx'
    else if(irecover==1) then
        write(outgpvar,*)'******gpvar-----> node var***'
    endif

    !write(outgpvar,*)'total time=',ttime

    if (irecover<=0) then
        DO igroup =1,ngroup
            field1= group(igroup)%fieldid(1:1)
            class = group(igroup)%class
            matno = group(igroup)%matno
            if (appear(igroup)>0.and.field1=='U') then
                index=group(igroup)%index
                if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    ngaus=elkn(index)%ggaus(order_int)%ngaus
                    material=props(matno)%mechanical%solid%material
                    thick=0.
                    if (index==22.or.index==26)thick=props(matno)%mechanical%solid%thickness
                    if (material=='GOODMAN') then   !! for goodman element
                        !jndex=1
                        !if (ndimn==3)jndex=5
                        jndex=1
                        if (ndimn==3.and.index==9)jndex=5  !2017/02/14
                        if (ndimn==3.and.index==23)jndex=3  !2017/02/14
                        ngaus=elkn(jndex)%ggaus(1)%ngaus
                    endif               !! for goodman element
                    nstre=group(igroup)%ngvar
                    if (irecover==-1)allocate(stres(nstre))
                    ! loop for 1:nelgroup
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if (ice0(ielem)==0)then
                            if (irecover==-1) then
                                stres=0.0
                                do igaus=1,nstre
                                    stres(igaus)=sum(element(ielem)%field(1)%gpvar(igaus,1:ngaus))/ngaus
                                end do
                                write(outgpvar,10)ielem,stres(1:nstre)
                            elseif(irecover==0)then
                                if(index==22)write(outgpvar,'(i10,9e18.8)')ielem,element(ielem)%rotation
                                do igaus=1,ngaus
                                    if(index==22) then
                                        if(KSTAB==0.and.MAT_curve==0)write(outgpvar,11)ielem,igaus,element(ielem)%egaus(1)%djacb(igaus),   &
                                            element(ielem)%field(1)%gpvar(1:3,igaus),                             &
                                            thick*element(ielem)%field(1)%gpvar(4:nstre,igaus)
                                    elseif(index==26) then
                                        if(KSTAB==0.and.MAT_curve==0)write(outgpvar,11)ielem,igaus,element(ielem)%egaus(1)%djacb(igaus),   &
                                            element(ielem)%field(1)%gpvar(1:3,igaus)
                                    else
                                        if(KSTAB==0.and.MAT_curve==0)write(outgpvar,11)ielem,igaus,element(ielem)%field(1)%gpvar(1:nstre,igaus)
                                    endif
                                end do
                            endif
                        endif
                    end do
                    !!!!!!!!!!!!!!!!!!!!!!!!!!!!
                    if (nelem1>0)write(outgpvar,*)'first refined mesh results'
                    if (nelem1>0)then
                        DO ielgroup = 1,group1(igroup)%nelgroup
                            ielem = group1(igroup)%list(ielgroup)
                            if (jce1(ielem)==0)then
                                do igaus=1,ngaus
                                    write(outgpvar,11)ielem,igaus,element1(ielem)%field(1)%gpvar(1:nstre,igaus)
                                end do
                            endif
                        end do
                    endif
                    if (nelem2>0)write(outgpvar,*)'second refined mesh results'
                    if (nelem2>0)then
                        DO ielgroup = 1,group2(igroup)%nelgroup
                            ielem = group2(igroup)%list(ielgroup)
                            do igaus=1,ngaus
                                write(outgpvar,11)ielem,igaus,element2(ielem)%field(1)%gpvar(1:nstre,igaus)
                            end do
                        end do
                    endif
                    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                    if (irecover==-1)deallocate(stres)
                endif
            endif
        end do

    elseif(irecover==1) then
        call recover
        do igroup=1,ngroup
            write(outgpvar,*)'igroup=',igroup
            if (appear(igroup)>0) then
                do ipoin=1,npoin
                    if (any(group(igroup)%valun(ipoin,:)/=0.0_irk))then
                        len=size(group(igroup)%valun(ipoin,:))
                        write(outgpvar,10)ipoin,group(igroup)%valun(ipoin,1:len)
                    endif
                end do !! for ipoin
            endif
        end do  !! for igroup
    elseif(irecover==2) then  !20231215YL output the stress time history for judgement of liquifaction
        write(lquunit)ttime
        nliqu=nliqu+1
        allocate(smain(ndimn),stres(3*(ndimn-1)),rr(ndimn,ndimn))
        DO igroup =1,ngroup
            liquj=  group(igroup)%liquj
            field1= group(igroup)%fieldid(1:1)
            if(appear(igroup)>0.and.field1=='U'.and.liquj==1) then
                index=group(igroup)%index
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                !            nstre=group(igroup)%ngvar
                allocate(smax(group(igroup)%nelgroup))
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if(ice0(ielem)==0)then
                        do istre=1,3*(ndimn-1)
                            stres(istre)=sum(element(ielem)%field(1)%gpvar(istre,:))/ngaus
                            if(group(igroup)%kinit_g==2)stres(istre)=stres(istre)-   &
                                sum(element(ielem)%stres0(istre,:))/ngaus
                        end do

                        if(ndimn==2) then
                            sx=stres(1)
                            sy=stres(2)
                            sxy=stres(3)
                            delta=sqrt((sx-sy)**2/4+sxy**2)
                            smain=0.
                            smain(1)=(sx+sy)/2.+delta
                            smain(2)=(sx+sy)/2.-delta
                            smax(ielgroup)=.5*(smain(1)-smain(2))
                        else
                            call stresmr ( stres, smain, rr)
                            smax(ielgroup)=.5*(smain(1)-smain(3))
                        endif
                    endif  !ice0==1
                end do
                write(lquunit)smax
                deallocate(smax)
            endif  !liquj==1
        end do

    endif !20231215YL

    !! output reaction
    !! write reaction in point , zhao 05/08/18
    allocate(ipiact(npoin),pointact(mdofn,npoin))
    ipiact=0 ; pointact=0.
    noutfix=0
    do idofix=1,ndofix
        if (prescrib(idofix)%outfix==1)then
            noutfix=noutfix+1
            ipiact(prescrib(idofix)%nodfix)=1
        endif
    end do
    if (noutfix/=0) then
        allocate(value(noutfix))
        noutfix=0
        do idofix=1,ndofix
            if (prescrib(idofix)%outfix==1)then
                noutfix=noutfix+1
                value(noutfix)=prescrib(idofix)%rdofix
                pointact(prescrib(idofix)%ifixvar,prescrib(idofix)%nodfix)=prescrib(idofix)%rdofix
            endif
        end do
        write(outact,12)ttime,value
        write(outact,*)'*************** write reaction in point *****************'
        write(outact,*)'ttime=',ttime
        write(outact,*)sum(ipiact)

        do ipoin=1,npoin
            if (ipiact(ipoin)/=1)cycle
            write(outact,'(10i5)')1,3,1,1 !special for wudongde
            write(outact,'(10e16.4)')pointact(1:mdofn,ipoin)
            write(outact,*)ipoin
            !write(outact,'(i6,10e16.4)')ipoin,pointact(1:mdofn,ipoin)
        enddo
        write(outact,*)'*************** write reaction in point *****************'
        !    write(outact,*)'total=',sum(value)
        deallocate(value)
    endif
    deallocate(ipiact,pointact)
    !! end output of reaction

    if(nbackf/=0.and.nbackdT==1)then
        ! record the displacements of spring points
        write(outact,*)'ttime=',ttime
        write(outact,*)'坝和地基位移分离解法：地基对坝体约束位移'

        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ipair=gapb(igapb)%nodegblock_ipairs(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                ipoin=gaps(igaps)%pairnode(ij,ipair)
                write(outact,11)igapb,i0,gapb(igapb)%disp_ct(:,i0)
            end do
        end do
        write(outact,*)'坝和地基位移分离解法：地基对坝体约束反力'
        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ipair=gapb(igapb)%nodegblock_ipairs(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                ipoin=gaps(igaps)%pairnode(ij,ipair)
                write(outact,11)igapb,i0,gapb(igapb)%force_ct(:,i0)
            end do
        end do
        write(outact,*)'坝和地基位移分离解法：地基对坝体约束刚度'
        do igapbf=1,nbackf
            igapb=backf(igapbf)%groupb
            npgblock=gapb(igapb)%npgblock
            do i0=1,npgblock
                igaps=gapb(igapb)%nodegblock_igaps(i0)
                ipair=gapb(igapb)%nodegblock_ipairs(i0)
                ij=gapb(igapb)%nodegblock_onetwo(i0)
                ipoin=gaps(igaps)%pairnode(ij,ipair)
                write(outact,11)igapb,i0,gapb(igapb)%force_ct(:,i0)/gapb(igapb)%disp_ct(:,i0)
            end do
        end do
    endif


    !! contact
    write(outcontact,*)'*****CONTACT GAPS******'
    write(outcontact,*)'total time=',ttime
    write(outcontact,'(4(a,i5))')'iblks=',iblks,' iincs=',iincs,' istep=',istep,' iiter=',iiter
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            if (name=='CONTACT')then
                index = group(igroup)%index
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                nnode = elkn(index)%el_field(1)%nnode_f
                node1=nnode/2
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    !write(outcontact,10)ielem,element(ielem)%field(1)%gapg(1:ngaus/2)
                    write(outcontact,'(i10,5x,10a)')ielem,element(ielem)%field(1)%state(1:ngaus/2)
                    if (material=='GOODMAN') then
                        write(outcontact,10)ielem,element(ielem)%field(1)%gapg(1:ngaus/2), &
                            element(ielem)%field(1)%gpvar(1:ndimn,1:ngaus/2)
                    else
                        write(outcontact,10)ielem,element(ielem)%field(1)%gapg(1:ngaus/2), &
                            element(ielem)%field(1)%ntstress(1:2,1:ngaus/2)
                    endif
                end do
            endif
        endif
    end do
    !write(outcontact,*)'*****STATE OF CRACK******'
    !write(outcontact,'(4(a,i5))')'iblks=',iblks,' iincs=',iincs,' istep=',istep
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            matno = group(igroup)%matno
            name=props(matno)%name
            if (name=='CRACK')then
                index = group(igroup)%index
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                nnode = elkn(index)%el_field(1)%nnode_f
                node1=nnode/2
                DO ielgroup = 1,group(igroup)%nelgroup

                    ielem = group(igroup)%list(ielgroup)
                    write(outcontact,'(i10,5x,10a)')ielem,element(ielem)%field(1)%state(1:ngaus)
                end do
            endif
        endif
    end do
    !! contact
    write(outcontact,*)'total time=',ttime
    write(outcontact,*)'BLOCK RIGID MOVEMENT'
    do igapb=1,ngapb
        if(gapb(igapb)%nrdof/=0) &
            write(outcontact,43)igapb,gapb(igapb)%rdisp_zero
    end do
    if(type_problem=='F')then
        write(outcontact,*)'BLOCK RIGID acceleration'
        do igapb=1,ngapb
            if(gapb(igapb)%nrdof/=0) &
                write(outcontact,43)igapb,gapb(igapb)%rdisp_second
        end do
    end if
    write(outcontact,*)'igaps,ipairs,pairnod(1:2),state,,ctforce(1:ndimn),gap,dxyz(1:ndimn),kxyz(1:ndimn)'
    do igaps=1,ngaps
        npairs=gaps(igaps)%npairs
        do ipairs=1,npairs
            if(gaps(igaps)%pair_process(ipairs)==0)cycle  !20200331
            if(block_stab/=1.and.contactpe==1)then
                write(outcontact,90)igaps,ipairs,gaps(igaps)%pairnode(1:2,ipairs),gaps(igaps)%state(ipairs),  &   !coord(2,gaps(igaps)%pairnode(1,ipairs)),
                    gaps(igaps)%ctforce(:,ipairs)/gaps(igaps)%aera(ipairs),     &
                    gaps(igaps)%gap(ndimn,ipairs),gaps(igaps)%dxyz(1:ndimn,ipairs),(gaps(igaps)%kxyz(i1,i1,ipairs),i1=1,ndimn)
            elseif(contactpe==2)then
                write(outcontact,92)igaps,ipairs,gaps(igaps)%paire(ipairs),gaps(igaps)%state(ipairs),gaps(igaps)%ctforce(:,ipairs)/gaps(igaps)%aera(ipairs),                 &
                    gaps(igaps)%gap(ndimn,ipairs),gaps(igaps)%rot(:,:,ipairs)
            else
                write(outcontact,93)igaps,ipairs,gaps(igaps)%state(ipairs),gaps(igaps)%ctforce(:,ipairs),(gaps(igaps)%kxyz(i1,i1,ipairs),i1=1,ndimn)   !,gaps(igaps)%gap(ndimn,ipairs),gaps(igaps)%rot(:,:,ipairs)
            endif  ! &
            !,gaps(igaps)%rot(1,:,npairs),gaps(igaps)%rot(2,:,npairs)
            !          write(outcontact,90)igaps,ipairs,gaps(igaps)%pairnode(1:2,ipairs),gaps(igaps)%state(ipairs),  &
            !		                      gaps(igaps)%aera(ipairs),gaps(igaps)%ctforce(:,ipairs),                 &
            !							  gaps(igaps)%gap(ndimn,ipairs),gaps(igaps)%ft(ipairs),                         &
            !                              gaps(igaps)%frict(ipairs),gaps(igaps)%cohes(ipairs)
            if (equvs==1)then
                i2=gaps(igaps)%pairnode(2,ipairs)
                i1=gaps(igaps)%pairnode(1,ipairs)
                write(teloaw,42)i1,tofor(nodfn(1:ndimn,i1))
                write(teloaw,42)i2,tofor(nodfn(1:ndimn,i2))
            endif
        end do
    end do
90  format(5i8,16e15.5)
91  format(4i8,10e15.5)
92  format(4i8,16e15.5)
93  format(3i8,16e15.5)
42  format(i8,3e15.5)
43  format(i8,6e15.5)


    if(nbackf/=0.and.nbackdT==0)then  !20150925
        write(outact,*)'total time=',ttime
        write(outact,*)'ipoin,idimn,kxyz(idimn),FMxyz(idimn),dr(idimn) for unified contact point'
        kdimn=ndimn
        if(block_stab==1)kdimn=3*(ndimn-1)
        allocate(rot(kdimn,kdimn),disg(kdimn),disl(kdimn),spring(kdimn))
        !do igapbf=1,nbackf
        !   igapb=backf(igapbf)%groupb
        do igapb=1,ngapb
            npgblock=gapb(igapb)%npgblock
            do ipoin=1,npgblock
                igaps=gapb(igapb)%nodegblock_igaps(ipoin)
                ipair=gapb(igapb)%nodegblock_ipairs(ipoin)
                rot=0.
                rot(1:ndimn,1:ndimn)=gaps(igaps)%rot(:,:,ipair)
                if(kdimn>ndimn)then
                    if(ndimn==2)rot(3,3)=1.
                    if(ndimn==3)rot(4:6,4:6)= rot(1:ndimn,1:ndimn)
                endif
                ij=gapb(igapb)%nodegblock_onetwo(ipoin)
                i12=gaps(igaps)%pairnode(ij,ipair)
                disg=result_zero(nodfn(1:kdimn,i12))
                !write(7,*)'il2=',i12,'nodfn=',nodfn(1:kdimn,i12)
                !write(7,*)'result_zero=',disg
                disl=(transpose(rot).x.gaps(igaps)%ctforce(:,ipair))
                !
                !write(7,*)'disl=',disl,'disg=',disg

                spring=-disl/disg
                write(outact,*)'igaps=',igaps,'ipair=',ipair,'ij=',ij
                do idimn=1,kdimn
                    write(outact,'(2i8,3e14.5)')i12,idimn,spring(idimn),disl(idimn),disg(idimn)
                end do
            end do
        enddo
        deallocate(rot,disg,disl,spring)

        allocate(ctnode(npoin))
        ctnode=0

        !if(block_stab==1.and.nbackf>0.and.nbackdT==0)then
        if(block_stab==1.and.nbackf>0.and.nbackdT<=1)then
            write(outact,*)'spring and contact_force(under global_coordinate_system) for each point'
            do igaps=1,ngaps
                do ipairs=1,gaps(igaps)%npairs
                    ctnode(gaps(igaps)%gaps_collect(ipairs)%listtop)=1
                    ctnode(gaps(igaps)%gaps_collect(ipairs)%listbotom)=1
                end do
            end do

            allocate(disl(ndimn),disg(ndimn),spring(ndimn))
            do ipoin=1,npoin
                if(ctnode(ipoin)==0)cycle
                disl=-stfor(nodfn(1:ndimn,ipoin))
                disg=result_zero(nodfn(1: ndimn,ipoin))
                spring=-disl/disg
                do idimn=1,ndimn
                    write(outact,'(2i8,3e14.5)')ipoin,idimn,spring(idimn),disl(idimn)
                end do
                !write(outcontact,'(i4,12e14.5)')ipoin,spring,disl
            end do
            write(outact,*)'contact_displacements(under global_coordinate_system) for each point and spring'
            do ipoin=1,npoin
                if(ctnode(ipoin)==0)cycle
                disg=result_zero(nodfn(1: ndimn,ipoin))
                write(outact,'(i8,12e14.5)')ipoin,disg
            end do


            deallocate(ctnode,disl,disg,spring)
        endif



    endif !20150925



    !! goodman
    !write(outgoodman,*)'*****CONTACT GAPS for Goodman elements******'
    !write(outgoodman,*)'IELEM    RELATIVE displacement( slide, gaps), &
    !                  tangent  and normal stress for igaus=1,2'
    !write(chkunit,*)'element with tension'  !special for hjd
    write(outgoodman,*)'total time=',ttime
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            matno = group(igroup)%matno
            name  = props(matno)%name
            index = group(igroup)%index
            nstre = group(igroup)%nstre
            nnode = elkn(index)%el_field(1)%nnode_f
            material=props(matno)%mechanical%solid%material



            if (material=='GOODMAN') then

                jndex=1
                if (ndimn==3.and.index==9)jndex=5  !2017/02/14
                if (ndimn==3.and.index==23)jndex=3  !2017/02/14
                order_int=elkn(jndex)%el_field(1)%order_intrules(1)
                name  =props(matno)%name
                ngaus=elkn(jndex)%ggaus(order_int)%ngaus

                model=props(matno)%mechanical%solid%Goodman%model
                if(model=='FCM') then
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        do igaus=1,ngaus
                            istate=element(ielem)%field(1)%gpvar(ndimn+1,igaus)
                            write(outgoodman,142)ielem,istate,element(ielem)%field(1)%gpvar(ndimn+2,igaus),  &
                                element(ielem)%field(1)%gpvar(1:ndimn,igaus),element(ielem)%field(1)%strain(ndimn,igaus)
                        end do
                    end do

                else if  (name=='CONTACT') then
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        write(outgoodman,10)ielem,element(ielem)%field(1)%gapg(1:ngaus),  &
                            element(ielem)%field(1)%gpvar(ndimn,1:ngaus)
                    end do
                elseif(model=='WATERTIGHT')then !20240305
                    allocate(eldis(nnode*ndimn),x1(ndimn),x2(ndimn),rdis(ndimn))
                    DO ielgroup = 1,group(igroup)%nelgroup

                        ielem = group(igroup)%list(ielgroup)
                        rotation=>element(ielem)%rotation
                        ldofs   => element(ielem)%field(1)%ldofs_f
                        eldis = result_zero(ldofs)
                        x1=0.;x2=0.
                        do inode=1,nnode/2
                            x1=x1+eldis((inode-1)*ndimn+1:inode*ndimn)
                            jnode=inode+nnode/2
                            if (ndimn==2.and.inode==1)jnode=4
                            if (ndimn==2.and.inode==2)jnode=3
                            x2=x2+eldis((jnode-1)*ndimn+1:jnode*ndimn)
                        end do
                        x2=x2-x1
                        rdis=rotation.x.x2
                        write(outgoodman,40)ielem,rdis(1:ndimn),        &
                            (sum(element(ielem)%field(1)%gpvar(idimn,1:ngaus))/ngaus,idimn=1,ndimn)
                    end do !end do ielgroup
                    deallocate(eldis,x1,x2,rdis)
                else
                    allocate(eldis(nnode*ndimn),x1(ndimn),x2(ndimn),rdis(ndimn))
                    DO ielgroup = 1,group(igroup)%nelgroup

                        ielem = group(igroup)%list(ielgroup)
                        !rotation=>element(ielem)%rotation
                        !ldofs   => element(ielem)%field(1)%ldofs_f
                        !eldis = result_zero(ldofs)
                        !x1=0.;x2=0.
                        !do inode=1,nnode/2
                        !   x1=x1+eldis((inode-1)*ndimn+1:inode*ndimn)
                        !   jnode=inode+nnode/2
                        !   if (ndimn==2.and.inode==1)jnode=4
                        !   if (ndimn==2.and.inode==2)jnode=3
                        !   x2=x2+eldis((jnode-1)*ndimn+1:jnode*ndimn)
                        !end do
                        !x2=x2-x1
                        !rdis=rotation.x.x2
                        !write(outgoodman,40)ielem,rdis(1:ndimn),        &
                        !(sum(element(ielem)%field(1)%gpvar(idimn,1:ngaus))/ngaus,idimn=1,ndimn)
                        do igaus=1,ngaus
                            write(outgoodman,41)ielem,element(ielem)%field(1)%gpvar(1:ndimn,igaus),element(ielem)%evk(1:ndimn,igaus)
                        end do
                    end do
                    deallocate(eldis,x1,x2,rdis)
                endif
            else if(material=='CLASSICALEP') then
                criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
                if (criteria=='MCJOINT') then
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    ngaus=elkn(index)%ggaus(order_int)%ngaus
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        !       if(tension_joint(ielem)==1) goto 100   !! special for hjd
                        write(outgoodman,10)ielem,element(ielem)%field(1)%ntstress(1:2,1:ngaus/2)
                        write(outgoodman,10)ielem,element(ielem)%field(1)%gpvar(nstre+2,1:ngaus/2)
                        if  (name=='CONTACT') &
                            write(outgoodman,10)ielem,element(ielem)%field(1)%gapn
                        !! special for hjd
                        !  smean=sum(element(ielem)%field(1)%ntstress(1,1:ngaus/2))
                        !  smean=smean*2/ngaus
                        !  if((matno==7.or.matno>=9).and.smean>0.) then
                        ! write(chkunit,*)ielem
                        !  endif
                        !100     continue
                        !! special for hjd
                    end do
                endif
            endif
        endif
    end do
    !! end of goodman
    !! write stress of bar element
    write(outbar,*)'Stress of bar element in local Coordinates, total time=',ttime
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            index = group(igroup)%index
            if (index==1.or.index==2.or.index==19) then
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                DO ielgroup = 1,group(igroup)%nelgroup

                    ielem = group(igroup)%list(ielgroup)
                    write(outbar,30)ielem,element(ielem)%field(1)%gpvar(1,1:ngaus)
                end do
            endif
        endif
    end do


    !! write force and moment (force*lenth) of  beam element
    write(outbeam,*)'internal forces of beam element under local Coordinates, total time=',ttime  !20200205
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            index = group(igroup)%index
            matno = group(igroup)%matno   !20211125
            material=props(matno)%mechanical%solid%material  !20211125

            if (index==20.or.index==21) then
                nstre=6*(ndimn-1)
                allocate(trot(nstre,nstre),force_e(nstre),force_i(nstre),trotx(nstre,nstre))
                trot=0. ; trotx=0.
                DO ielgroup = 1,group(igroup)%nelgroup

                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f !steel 2006
                    rotation=>element(ielem)%rotation

                    trot=0.
                    if (ndimn==2)then
                        trot(1:ndimn,1:ndimn)=rotation
                        trot(3,3)=1.
                        trot(4:5,4:5)=rotation
                        trot(6,6)=1.
                    else if(ndimn==3) then
                        trot(1:3,1:3)=rotation; trot(4:6,4:6)=rotation
                        trot(7:9,7:9)=rotation; trot(10:12,10:12)=rotation
                    end if
                    !steel 2006
                    if (any(listglocbeam==igroup))then
                        !if (ndimn==2)then
                        !   trotx=0.
                        !   trotx(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
                        !   trotx(3,3)=1.
                        !   trotx(4:5,4:5)=prot(:,:,lnods(2))
                        !   trotx(6,6)=1.
                        !elseif(ndimn==3)then
                        !   trotx=0.
                        !   trotx(1:3,1:3)=prot(:,:,lnods(1)); trotx(4:6,4:6)=prot(:,:,lnods(1))
                        !   trotx(7:9,7:9)=prot(:,:,lnods(2)); trotx(10:12,10:12)=prot(:,:,lnods(2))
                        !endif
                        force_e=element(ielem)%field(1)%tload
                        force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1) !20200116,(ndimn-2)->(ndimn-1)
                        force_i=force_i-force_e
                        !force_e=transpose(trotx).x.force_i
                        !force_i=force_e

                    else !20200205 (BM,index==20)

                        force_e=element(ielem)%field(1)%tload
                        force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1)  !20200116
                        force_i=force_i-force_e !不需要用trot.x.force_e，%tload和%gpvar都是整体坐标系内的
                        force_e=force_i
                        force_i=trot.x.force_e  !转成局部坐标系下的内力
                        !write(7,*)'ie=',ielem,'force_e=',force_e,'force_i=',force_i
                        !write(7,*)'gpvar=',element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1)
                    endif

                    nullify(lnods)
                    if (ndimn==2) then
                        if(material/='STEEL_EP')&  !20211125
                            write(outbeam,30)ielem,force_i  !20211125
                        if(material=='STEEL_EP')&  !20211125
                            write(outbeam,'(i6,7(2x,e12.5))')ielem,element(ielem)%field(1)%ep,force_i  !20211125
                    elseif(ndimn==3) then
                        if(material/='STEEL_EP')&  !20211125
                            write(outbeam,'(i6,6(2x,e12.5),8x,6(2x,e12.5))')ielem,force_i(1:6),force_i(7:12)  !20211125
                        if(material=='STEEL_EP')&  !20211125
                            write(outbeam,'(i6,8(2x,e12.5))')ielem,element(ielem)%field(1)%ep,element(ielem)%field(1)%sigz(1),force_i(1:6)    !20211125

                    endif
                    nullify(rotation)
                end do
                deallocate(trot,force_e,force_i,trotx)
            endif
        endif
    end do



    !! write force (force*lenth) of  bond-slip joint element
    write(outbeam,*)'total time=',ttime,' for  bond-slip joint element'
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            index = group(igroup)%index
            if (index==25) then
                DO ielgroup = 1,group(igroup)%nelgroup

                    ielem = group(igroup)%list(ielgroup)

                    write(outbeam,'(i6,20(2x,e12.5))')ielem,element(ielem)%field(1)%gpvar(:,1)

                end do
            endif
        endif
    end do



    if (equvs==1)then
        do ielem=1,nelem
            !if(group(element(ielem)%group)%elcod_local/=0.) &
            if (equvs_process(element(ielem)%group)/=0) &       !zhao 05/07/30
                write(teloaw)element(ielem)%field(1)%eload-element(ielem)%field(1)%tload
            !if(equvs_process(element(ielem)%group)/=0) &
            !write(100,'(24e15.4)')element(ielem)%field(1)%eload-element(ielem)%field(1)%tload
            !write(teloaw,41)ielem,element(ielem)%field(1)%eload-element(ielem)%field(1)%tload
        end do
    endif

10  format(i10,12(2x,e12.5))
11  format(2i6,12(2x,e12.5))
12  format(10(2x,e12.5))
20  format(2x,3i5,2e12.5)
30  format(i6,8(2x,e12.5))
40  format(i6,2(2x,e12.5),4(2x,e12.5))
41  format(i6,24(2x,e12.5))
142 format(i10,i5,e10.3,4e15.2)

    END SUBROUTINE OUT_FULL_WRITE

    SUBROUTINE OUT_COSMOS_WRITE

    integer(ink) ipoin,idofn,len,ilink,node1,node2,jdofn,i
    real   (irk),allocatable::value(:),stres(:),valun(:,:),rr(:,:),smain(:)
    real   (irk) sigma1,sigma2,sx,sy,sxy,delta,alfa
    real   (irk),allocatable::resultm(:)

    if (outintw/=0) then
        allocate(resultm(npoin))
        resultm=0.
        do ipoin=1,npoin
            idofn=nodfn(1,ipoin)
            if (idofn/=0)resultm(ipoin)=result_zero(idofn)
        end do
        do ilink=1,ntlink
            node1=tlink(1,ilink)
            node2=tlink(2,ilink)
            resultm(node1)=resultm(node2)
        end do
    endif

    write(out_cosm_dis,*)npoin,',0,',cdofn

    write(out_cosm_dis,*)title(lcdofn(1:cdofn))

    allocate(value(cdofn))

    do ipoin=1,npoin

        value=0.0
        do idofn=1,cdofn
            jdofn=lcdofn(idofn)
            itotv=nodfn(idofn,ipoin)
            if ((jdofn/=8.and.jdofn/=10).or.(jdofn==10.and.outintw==0)) then
                if (itotv/=0)value(idofn)=result_zero(itotv)
            else if(jdofn==10.and.outintw/=0) then
                value(idofn)=resultm(ipoin)
            else
                if (type_problem=='F')then
                    if (.not.allocated(prstat).and.itotv/=0)value(idofn)=result_zero(itotv)
                    if (allocated(prstat).and.itotv/=0)value(idofn)=result_zero(itotv)-prstat(ipoin)
                else
                    value(idofn)=result_zero(itotv)
                endif
            endif
        end do
        write(out_cosm_dis,10)ipoin,value
    end do

    deallocate(value)
    if (allocated(resultm))deallocate(resultm)


    len=maxval(group(:)%ngvar)
    allocate(valun(len,npoin))
    call recovery(valun)

    if (ndimn==2) then

        if (len<=4) then
            write(out_cosm_gpvar,*)npoin,',0,5'
            write(out_cosm_gpvar,*)'sig_x sig_y txy sigma1 sigma2'
        else
            write(out_cosm_gpvar,*)npoin,',0,6'
            write(out_cosm_gpvar,*)'sig_x sig_y txy Smax sigma1 sigma2'
        endif

        do ipoin=1,npoin
            sx=valun(1,ipoin)
            sy=valun(2,ipoin)
            sxy=valun(3,ipoin)
            delta=sqrt((sx-sy)**2/4+sxy**2)
            sigma1=0.;sigma2=0.;alfa=0.
            if (delta.lt.1.e-5) goto 12
            sigma1=(sx+sy)/2.+delta
            sigma2=(sx+sy)/2.-delta
            alfa=.5*atan2d(2*sxy,sx-sy)
12          continue
            if (len>=5) then
                write(out_cosm_gpvar,10)ipoin,valun(1:3,ipoin),valun(6,ipoin),sigma1,sigma2,alfa
            else
                write(out_cosm_gpvar,10)ipoin,valun(1:3,ipoin),sigma1,sigma2,alfa
            endif
        enddo
    else


        if (len>2*ndimn) then
            write(out_cosm_gpvar,*)npoin,',0,',2*ndimn+1
            write(out_cosm_gpvar,*)'sig_x sig_y sigz txy tyz tzx eps'
            do ipoin=1,npoin
                write(out_cosm_gpvar,10)ipoin,valun(1:2*ndimn+1,ipoin)
            end do
        else
            write(out_cosm_gpvar,*)npoin,',0,', 2*ndimn
            write(out_cosm_gpvar,*)'sig_x sig_y sigz txy tyz tzx'
            do ipoin=1,npoin
                write(out_cosm_gpvar,10)ipoin,valun(1:2*ndimn,ipoin)
            end do
        endif

        allocate(stres(6),smain(3),rr(3,3))

        write(out_cosm_gpvar,*)npoin,',0,3'
        write(out_cosm_gpvar,*)'sigma1 sigma2 sigma3'
        do ipoin=1,npoin
            stres=valun(:,ipoin)
            call stresmr ( stres, smain, rr)
            write(outgpvar,10)ipoin,smain(1:3),(rr(1:2,i),i=1,2)
            ! here output l,m. n can be got by n=sqrt(1-l**2-m**2)
            ! the unit of l,m is grad.
        end do

        deallocate(stres,smain,rr)


    endif

    deallocate(valun)

10  format(i10,10(2x,e15.4))

    END SUBROUTINE OUT_COSMOS_WRITE

    SUBROUTINE OUT_GID_WRITE

    character(10)fieldid,class,material,name
    integer(ink) igroup,index,nnode,tnegid,matno,ngaus,igaus
    integer(ink) ipoin,idofn,len,nstre,ilink,node1,node2,kdimn
    integer(ink) npoin_igroup,jelem,nline_g_sc ,nline_s,i1,j1,npairs_sc  !20210328
    real   (irk),allocatable::value(:),stres(:),valun(:,:),rr(:,:),smain(:)
    real   (irk) delta,sx,sy,sxy,zz,hh,factor,total_step,thick,z0
    real   (irk),allocatable::resultm(:),vvv(:),trot(:,:),force_e(:),force_i(:),trotx(:,:)
    real   (irk),pointer::rotation(:,:),perme(:)
    integer(ink),pointer::lnods(:)
    integer(ink),allocatable::npbeam(:),listp_bem(:),listp_bem_new(:), & !20200311
        listp_mxy(:),listp_mxy_new(:),listp_bcs(:),npbcs(:)  !20210328
    real   (irk),allocatable::coord_bem(:,:),coord_mxy(:,:),  & !20200311
        cartd(:,:),veloc(:,:),veloc_H(:,:),aera(:),coord_bcs(:,:) !20210328

    integer(ink) ielem,ielgroup,ie

    if(outplot(1:3)/='GID') return
    if(outplot=='GIDL') then
        call OUT_GID_WRITE_BIN
        return
    endif

    !20231215YL
    if(type_problem=='F'.and.(.not.allocated(maxdisp)))then !20231009
        allocate(maxdisp(ndimn,npoin));maxdisp=0.0
    endif
    if(type_problem=='F'.and.(.not.allocated(maxacce)))then
        allocate(maxacce(ndimn,npoin),maxacce_a(ndimn,npoin));maxacce=0;maxacce_a=0
    endif
    if(type_problem=='F'.and.(.not.allocated(maxv)))then
        allocate(maxv(ndimn,npoin));maxv=0
    endif
    !20231215YL

    if (meshc==1.or.rmesh/=0.or.Uopt_R==1) then  !20210502

        rewind(out_gid_msh)
        !ielem=0
        ie=0
        do igroup=1,ngroup
            index=group(igroup)%index
            call geteletype(ndimn,out_gid_msh,index)
            write(out_gid_msh,*)'coordinates'
            if (igroup==1) then
                z0=0.
                if(ndimn==3) then
                    do ipoin=1,npoin
                        write(out_gid_msh,991)ipoin,coord(1:ndimn,ipoin)
                    end do
                else if(ndimn==2) then
                    do ipoin=1,npoin
                        write(out_gid_msh,991)ipoin,coord(1:ndimn,ipoin),z0
                    end do
                else
                    print *,'ndimn must be 2 or 3,now ndimn=',ndimn
                    stop
                end if
            end if
            write(out_gid_msh,*)'end coordinates'
            write(out_gid_msh,*)'elements'

            !tnegid=0
            if (meshc==1.or.Uopt_R==1)then !20210502
                !do igroup=1,ngroup
                if (appear(igroup)==1)then
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        !tnegid=tnegid+1
                        ie=ie+1
                        write(out_gid_msh,992)ie,element(ielem)%field(1)%lnods_f,igroup
                    end do
                endif
                !end do
            else if(rmesh/=0)then
                !do igroup=1,ngroup
                if (appear(igroup)==1)then
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if (ice0(ielem)==0)then
                            !tnegid=tnegid+1
                            ie=ie+1
                            write(out_gid_msh,992)ie,element(ielem)%field(1)%lnods_f,igroup
                        endif
                    end do
                endif
                !end do
                !!!!
                if (nelem1>0)then
                    !do igroup=1,ngroup
                    if (appear(igroup)==1)then
                        DO ielgroup = 1,group1(igroup)%nelgroup
                            ielem = group1(igroup)%list(ielgroup)
                            if (jce1(ielem)==0)then
                                !tnegid=tnegid+1
                                ie=ie+1
                                write(out_gid_msh,992)ie,element1(ielem)%field(1)%lnods_f,igroup+ngroup
                            endif
                        end do
                    endif
                    !end do
                endif
                !!!!!!!!!!!!!!
                if (nelem2>0)then
                    !do igroup=1,ngroup
                    if (appear(igroup)==1)then
                        DO ielgroup = 1,group2(igroup)%nelgroup
                            ielem = group2(igroup)%list(ielgroup)
                            ie=ie+1
                            write(out_gid_msh,992)ie,element2(ielem)%field(1)%lnods_f,igroup+2*ngroup
                        end do
                    endif
                    !end do
                endif
                !!!!!!!!!!!!!!!!
            endif
            write(out_gid_msh,*)'end elements'
        end do
    endif

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!gid_Mxy
    if (gid_mxy==1.and.iblks==lblks+1.and.iincs==1.and.istep/noutf==1) then  !20200311

        npoin_mxy=0
        nelem_mxy=0
        allocate(listp_mxy(npoin))
        DO igroup =1,ngroup
            listp_mxy=0
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if(index/=22.and.index/=26)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_mxy(lnods)=1
                    nullify(lnods)
                end do
                npoin_igroup=sum(listp_mxy)
                nelem_mxy=nelem_mxy+group(igroup)%nelgroup
                npoin_mxy=npoin_mxy+npoin_igroup
            endif
        end do

        allocate(coord_mxy(3,npoin_mxy),ien_mxy(5,nelem_mxy),listp_mxy_new(npoin),  &
            liste_mxy_new(nelem))
        coord_mxy=0.;ien_mxy=0;listp_mxy_new=0;liste_mxy_new=0

        npoin_mxy=0;  nelem_mxy=0
        DO igroup =1,ngroup
            listp_mxy=0
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if(index/=22.and.index/=26)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_mxy(lnods)=1
                    nullify(lnods)
                end do

                do ipoin=1,npoin
                    if(listp_mxy(ipoin)==0) cycle
                    npoin_mxy=npoin_mxy+1
                    listp_mxy_new(ipoin)=npoin_mxy
                    coord_mxy(1:ndimn,npoin_mxy)=coord(1:ndimn,ipoin)
                end do


                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    nelem_mxy=nelem_mxy+1
                    ien_mxy(1:4,nelem_mxy)=listp_mxy_new(lnods(1:4))
                    ien_mxy(5,nelem_mxy)=igroup
                    liste_mxy_new(ielem)=nelem_mxy
                    nullify(lnods)
                end do

            endif
        end do


        rewind(mxy_msh_unit)
        write(mxy_msh_unit,*)'mesh dimension = 3 elemtype quadrilateral nnode = 4'
        write(mxy_msh_unit,*)'coordinates'
        do ipoin=1,npoin_Mxy
            write(mxy_msh_unit,991)ipoin,coord_mxy(:,ipoin)
        end do
        write(mxy_msh_unit,*)'end coordinates'
        write(mxy_msh_unit,*)'elements'

        do ielem=1,nelem_Mxy
            write(mxy_msh_unit,992)ielem,ien_mxy(:,ielem)
        end do
        write(mxy_msh_unit,*)'end elements'

        deallocate(coord_mxy,listp_mxy_new)
    endif

    !!!!!!gid_bem/=0

    if (gid_bem==1.and.iblks==lblks+1.and.iincs==1.and.istep/noutf==1) then  !20200311
        npoin_bem=0
        nelem_bem=0
        allocate(listp_bem(npoin))
        DO igroup =1,ngroup
            listp_bem=0
            field1= group(igroup)%fieldid(1:1)
            !if (appear(igroup)>0.and.field1=='U')then  !20200724
            if (field1=='U')then
                index = group(igroup)%index
                if (index/=20.and.index/=21)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_bem(lnods)=1
                    nullify(lnods)
                end do
                npoin_igroup=sum(listp_bem)
                nelem_bem=nelem_bem+group(igroup)%nelgroup
                npoin_bem=npoin_bem+npoin_igroup
            endif
        end do

        allocate(coord_bem(3,npoin_bem),ien_bem(3,nelem_bem),listp_bem_new(npoin),  &
            liste_bem_new(nelem))
        coord_bem=0.;ien_bem=0;listp_bem_new=0;liste_bem_new=0

        npoin_bem=0;  nelem_bem=0
        DO igroup =1,ngroup
            listp_bem=0
            field1= group(igroup)%fieldid(1:1)
            !if (appear(igroup)>0.and.field1=='U')then
            if (field1=='U')then  !20200724
                index = group(igroup)%index
                if (index/=20.and.index/=21)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_bem(lnods)=1
                    nullify(lnods)
                end do

                do ipoin=1,npoin
                    if(listp_bem(ipoin)==0) cycle
                    npoin_bem=npoin_bem+1
                    listp_bem_new(ipoin)=npoin_bem
                    coord_bem(1:ndimn,npoin_bem)=coord(1:ndimn,ipoin)
                end do


                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    nelem_bem=nelem_bem+1
                    ien_bem(1:2,nelem_bem)=listp_bem_new(lnods(1:2))
                    ien_bem(3,nelem_bem)=igroup
                    liste_bem_new(ielem)=nelem_bem
                    nullify(lnods)
                end do

            endif
        end do


        rewind(bem_msh_unit)
        write(bem_msh_unit,*)'mesh dimension  3   elemtype Linear  nnode  2'
        write(bem_msh_unit,*)'coordinates'
        do ipoin=1,npoin_bem
            write(bem_msh_unit,991)ipoin,coord_bem(:,ipoin)
        end do
        write(bem_msh_unit,*)'end coordinates'
        write(bem_msh_unit,*)'elements'

        do ielem=1,nelem_bem
            write(bem_msh_unit,992)ielem,ien_bem(:,ielem)
        end do
        write(bem_msh_unit,*)'end elements'

        deallocate(coord_bem,listp_bem_new)
    endif


    !!!!!!!gid_bcs/=0

    if (gid_bcs==1.and.iblks==lblks+1.and.iincs==1.and.istep/noutf==1) then  !20220330
        npoin_bcs=0
        nelem_bcs=0
        allocate(listp_bcs(npoin))
        listp_bcs=0
        if(nrcsteel/=0)then  !20220330
            do i0=1,nrcsteel
                do i1=1,rc_steel(i0)%nline_g_sc
                    nline_s=rc_steel(i0)%line_g_sc(i1)%nline_s
                    nelem_bcs=nelem_bcs+nline_s
                    do j1=1,nline_s
                        lnods=>rc_steel(i0)%line_g_sc(i1)%linenode_s(:,j1)
                        listp_bcs(lnods)=1
                        nullify(lnods)
                    end do
                end do
            end do

            npoin_bcs=sum(listp_bcs)
            allocate(coord_bcs(ndimn,npoin_bcs),ien_bcs(3,nelem_bcs),listp_bcs_new(npoin))
            coord_bcs=0.;ien_bcs=0;listp_bcs_new=0
            npoin_bcs=0;  nelem_bcs=0
            do ipoin=1,npoin
                if(listp_bcs(ipoin)==0) cycle
                npoin_bcs=npoin_bcs+1
                listp_bcs_new(ipoin)=npoin_bcs
                coord_bcs(1:ndimn,npoin_bcs)=coord(1:ndimn,ipoin)
            end do

            do i0=1,nrcsteel
                do i1=1,rc_steel(i0)%nline_g_sc
                    nline_s=rc_steel(i0)%line_g_sc(i1)%nline_s

                    do j1=1,nline_s
                        nelem_bcs=nelem_bcs+1
                        lnods=>rc_steel(i0)%line_g_sc(i1)%linenode_s(:,j1)
                        ien_bcs(1:2,nelem_bcs)=listp_bcs_new(lnods(1:2))
                        ien_bcs(3,nelem_bcs)=i0
                        nullify(lnods)
                    end do
                end do
            end do
        else !20220330

            do igroup=1,ngroup
                index = group(igroup)%index
                if(index/=1)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    nelem_bcs=nelem_bcs+1
                    lnods => element(ielem)%field(1)%lnods_f
                    listp_bcs(lnods)=1
                    nullify(lnods)
                end do
            end do
            npoin_bcs=sum(listp_bcs)
            !      print *,'gid_bcs=',gid_bcs,'npoin_bcs=',npoin_bcs
            !pause


            allocate(coord_bcs(ndimn,npoin_bcs),ien_bcs(3,nelem_bcs),listp_bcs_new(npoin))
            coord_bcs=0.;ien_bcs=0;listp_bcs_new=0
            npoin_bcs=0;  nelem_bcs=0
            do ipoin=1,npoin
                if(listp_bcs(ipoin)==0) cycle
                npoin_bcs=npoin_bcs+1
                listp_bcs_new(ipoin)=npoin_bcs
                coord_bcs(1:ndimn,npoin_bcs)=coord(1:ndimn,ipoin)
            end do

            do igroup=1,ngroup
                index = group(igroup)%index
                if(index/=1)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    nelem_bcs=nelem_bcs+1
                    lnods => element(ielem)%field(1)%lnods_f
                    ien_bcs(1:2,nelem_bcs)=listp_bcs_new(lnods(1:2))
                    ien_bcs(3,nelem_bcs)=igroup
                    nullify(lnods)
                end do
            end do
        endif !20220330

        rewind(bcs_msh_unit)
        write(bcs_msh_unit,*)'mesh dimension  3   elemtype Linear  nnode  2'
        write(bcs_msh_unit,*)'coordinates'
        do ipoin=1,npoin_bcs
            write(bcs_msh_unit,991)ipoin,coord_bcs(:,ipoin)
        end do
        write(bcs_msh_unit,*)'end coordinates'
        write(bcs_msh_unit,*)'elements'

        do ielem=1,nelem_bcs
            write(bcs_msh_unit,992)ielem,ien_bcs(:,ielem)
        end do
        write(bcs_msh_unit,*)'end elements'

        deallocate(coord_bcs,ien_bcs)
    endif



991 format(i10,3e15.6)
992 format(i10,10i10)


    total_step=ttime
    if (outintw/=0) then
        allocate(resultm(npoin))
        resultm=0.
        do ipoin=1,npoin
            idofn=nodfn(1,ipoin)
            if (idofn/=0)resultm(ipoin)=result_zero(idofn)
        end do
        do ilink=1,ntlink
            node1=tlink(1,ilink)
            node2=tlink(2,ilink)
            resultm(node1)=resultm(node2)
        end do
    endif

    ! write displacement vector for gid plot

    if (gid_u==1) then
        write(out_gid_dis,101)'DISPLACEMENT',1,total_step,2,1,0

        do ipoin=1,npoin

            kdimn=0
            do idofn=1,ndimn   !cdofn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)kdimn=kdimn+1
            end do
            allocate(value(kdimn))
            value=0.
            do idofn=1,kdimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)value(idofn)=result_zero(itotv)
                if(allocated(maxdisp))maxdisp(idofn,ipoin)=max(maxdisp(idofn,ipoin),abs(value(idofn))) !20231215YL
            end do


            !steel 2006
            if(alfa_p4>0)then  !20221202
                if (local_p4(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            endif
            if (icpnorm(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value

            if(kdimn/=0) &
                write(out_gid_dis,10)ipoin,value
            deallocate(value)
        end do


        if(nbackf/=0)then
            write(out_gid_dis,101)'foundation_DISPLACEMENT',1,total_step,2,1,0

            do ipoin=1,npoin

                kdimn=0
                do idofn=1,ndimn   !cdofn
                    itotv=nodfn(idofn,ipoin)
                    if(itotv/=0)kdimn=kdimn+1
                end do
                allocate(value(kdimn))
                value=0.
                do idofn=1,kdimn
                    itotv=nodfn(idofn,ipoin)
                    !if (itotv/=0)value(idofn)=result_zero_g(itotv)
                    if (itotv/=0)value(idofn)=result_zero(itotv)-result_zero_e(itotv)
                    !if (itotv/=0)value(idofn)=result_zero(itotv)-(result_zero_g(itotv)+result_zero_e(itotv))
                end do

                if(kdimn/=0) &
                    write(out_gid_dis,10)ipoin,value
                deallocate(value)
            end do

            write(out_gid_dis,101)'dam_DISPLACEMENT',1,total_step,2,1,0

            do ipoin=1,npoin

                kdimn=0
                do idofn=1,ndimn   !cdofn
                    itotv=nodfn(idofn,ipoin)
                    if(itotv/=0)kdimn=kdimn+1
                end do
                allocate(value(kdimn))
                value=0.
                do idofn=1,kdimn
                    itotv=nodfn(idofn,ipoin)
                    !if (itotv/=0)value(idofn)=result_zero(itotv)-result_zero_g(itotv)
                    if (itotv/=0)value(idofn)=result_zero_e(itotv)
                    !if (itotv/=0)value(idofn)=result_zero_e(itotv)+result_zero_g(itotv)

                end do

                if(kdimn/=0) &
                    write(out_gid_dis,10)ipoin,value
                deallocate(value)
            end do

        endif

    endif !gid_u

    if(gid_v==1)then

        write(out_gid_dis,101)'velocity',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)value(idofn)=result_first(itotv)
                if(allocated(maxv))maxv(idofn,ipoin)=max(maxv(idofn,ipoin),abs(value(idofn))) !20231215YL
            end do

            if(alfa_p4>0)then   !20221124
                if (local_p4(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            endif !20221124
            if (icpnorm(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value

            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)

    endif !gid_v

    if(gid_a==1)then

        write(out_gid_dis,101)'acceleration',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)value(idofn)=result_second(itotv)
                if(allocated(maxacce))maxacce(idofn,ipoin)=max(maxacce(idofn,ipoin),abs(value(idofn))) !20231215YL
            end do
            if(alfa_p4>0)then   !20221124
                if (local_p4(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            endif !20221124
            if (icpnorm(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)

        write(out_gid_dis,101)'acceleration_absolute',1,total_step,2,1,0 !20231215YL
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)value(idofn)=result_second(itotv)+fachv(idofn)
                if(allocated(maxacce_a))maxacce_a(idofn,ipoin)=max(maxacce_a(idofn,ipoin),abs(value(idofn))) !20231215YL
            end do
            if(alfa_p4>0)then   !20221124
                if (local_p4(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            endif !20221124
            if (icpnorm(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)  !20231215YL

    endif !gid_a

    if (gid_rot==1)then

        write(out_gid_dis,101)'ROTATION',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=4,2*ndimn
                itotv=nodfn(lmdofn(idofn),ipoin)
                if (itotv/=0)value(idofn-3)=result_zero(itotv)
            end do
            if(alfa_p4>0)then   !20221124
                if (local_p4(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            endif !20221124
            if (icpnorm(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value

            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)

    endif !gid_rot


    if(gid_p/=0)then  !20221014
        if(gid_p==1) &
            write(out_gid_dis,101)'PORE-PRESSURE',1,total_step,1,1,0
        if(gid_p==2) &
            write(out_gid_dis,101)'Excess_PORE-PRESSURE',1,total_step,1,1,0
        allocate(value(1))
        do ipoin=1,npoin
            value=0.
            if (lmdofn(8)/=0)idofn=lmdofn(8)
            if (lmdofn(7)/=0)idofn=lmdofn(7)
            itotv=nodfn(idofn,ipoin)
            if(itotv==0)cycle  !20221014
            value(1)=result_zero(itotv) !20221014
            if (allocated(prstat).and.gid_p==2)value(1)=value(1)-prstat(ipoin) !20221014

            !if (type_problem=='F')then  !20221014
            !   if (.not.allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)
            !   if (allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)-prstat(ipoin)
            !else
            !   if (itotv/=0)value(1)=result_zero(itotv) !+coord(2,ipoin)
            !endif
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    endif

    if(gid_wh==1)then !20210324
        write(out_gid_dis,101)'WATER-HEAD',1,total_step,1,1,0
        allocate(value(1))
        do ipoin=1,npoin
            value=0.
            if (lmdofn(8)/=0)idofn=lmdofn(8)
            if (lmdofn(7)/=0)idofn=lmdofn(7)
            itotv=nodfn(idofn,ipoin)
            if (type_problem=='F')then
                if (.not.allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)
                if (allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)-prstat(ipoin)
            else
                if (itotv/=0)value(1)=result_zero(itotv)/9810.+coord(ndimn,ipoin)
            endif
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    end if   !20210324


    if(gid_wv==1)then !20210324
        allocate(veloc_H(ndimn,npoin),aera(npoin))
        veloc_H=0.
        aera=0.
        DO igroup =1,ngroup
            if (appear(igroup)>0) then
                fieldid=group(igroup)%fieldid
                if (fieldid(1:1)/='W')cycle
                ! get information from the group level
1               index = group(igroup)%index
                matno = group(igroup)%matno
                nnode = elkn(index)%el_field(1)%nnode_f
                ngaus = elkn(index)%ggaus(1)%ngaus
                if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
                    allocate(perme(ndimn))
                    perme=xvalue(props(matno)%mechanical%fluid%iperm)
                else
                    perme=> props(matno)%mechanical%fluid%permeability
                endif
                allocate (value(nnode),cartd(ndimn,nnode),veloc(ndimn,ngaus))

                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods =>element(ielem)%field(1)%lnods_f
                    do inode=1,nnode
                        ipoin=lnods(inode)
                        value(inode)=0.
                        if (lmdofn(8)/=0)idofn=lmdofn(8)
                        itotv=nodfn(idofn,ipoin)
                        if(itotv/=0)value(inode)=result_zero(itotv)/9810.+coord(ndimn,ipoin)  !20220304
                    end do
                    do igaus=1,ngaus
                        ! get djacb and cartd in the element level
                        !djacb=element(ielem)%egaus(order_intx)%djacb(igaus)
                        cartd=element(ielem)%egaus(1)%cartd(:,:,igaus)
                        veloc(:,igaus)=cartd.x.value
                        veloc(:,igaus)=veloc(:,igaus)   !*perme  20230824(输出的是渗透坡降）
                    end do

                    do inode=1,nnode
                        ipoin=lnods(inode)
                        aera(ipoin)=aera(ipoin)+1.
                        veloc_H(:,ipoin)=veloc_H(:,ipoin)+veloc(:,inode)
                    end do
                    nullify(lnods)
                end do
                deallocate(value,cartd,veloc)


                if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
                    deallocate(perme)
                else
                    nullify(perme)
                endif

            endif
        end do
        do ipoin=1,npoin

            idofn=lmdofn(8)
            itotv=nodfn(idofn,ipoin)
            if(itotv/=0)then  !自由面以上点渗透坡降为0，20230824
                if(result_zero(itotv)<0.)veloc_H(:,ipoin)=0.
            else     ! 20230824
                if(abs(aera(ipoin)>.001))veloc_H(:,ipoin)=-veloc_H(:,ipoin)/aera(ipoin)
            endif
        end do   !  20230824

        write(out_gid_dis,101)'flow_velocity',1,total_step,2,1,0
        do ipoin=1,npoin
            write(out_gid_dis,10)ipoin,veloc_H(:,ipoin)
        end do


        deallocate(veloc_H,aera)


    endif !20210324


    if (gid_f==1) then
        write(out_gid_dis,101)'tofor',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)value(idofn)=tofor(itotv)
            end do

            if(alfa_p4>0)then  !20221202
                if (local_p4(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            endif
            if (icpnorm(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value


            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    endif
    if(gid_pv==1)then !zhao09

        write(out_gid_dis,101)'PRESSURE_V',1,total_step,1,1,0
        allocate(value(1))
        do ipoin=1,npoin
            value=0.
            if (lmdofn(8)/=0)idofn=lmdofn(8)
            if (lmdofn(7)/=0)idofn=lmdofn(7)
            itotv=nodfn(idofn,ipoin)
            if (itotv/=0)value(1)=result_first(itotv)  !20221014
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    endif !zhao09


    if(gid_p/=0.and.nflow/=0)then  !20221014
        write(out_gid_dis,101)'flow_charge',1,total_step,1,1,0
        allocate(value(1))
        do ipoin=1,npoin
            value=flowrate(ipoin)
            idofn=lmdofn(8)
            itotv=nodfn(idofn,ipoin)
            if(itotv/=0)then  !自由面以上点流量为0，20230824
                if(result_zero(itotv)<0.)value=0.
            endif !20230824
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    endif

    ! end write pore_pressure scalar for gid plot

    ! write temperature scalar for gid plot
    if(gid_T==1)then
        write(out_gid_dis,101)'TEMPERATURE',1,total_step,1,1,0
        allocate(value(1))
        do ipoin=1,npoin
            value=0.
            idofn=lmdofn(10)
            itotv=nodfn(idofn,ipoin)
            !if (itotv/=0.and.outintw==0)value(1)=result_zero(itotv)
            if (itotv/=0)value(1)=result_zero(itotv)  !20200220
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    endif
    ! end write temperature scalar for gid plot

    if(upliftin>0.and.iblks>=upliftin) then !20220409
        write(out_gid_dis,101)'uplift-PRESSURE',1,total_step,1,1,0
        do ipoin=1,npoin
            write(out_gid_dis,10)ipoin,uplift_node(ipoin)
        end do
    endif

    if (allocated(resultm))deallocate(resultm)

    !! end of output of nodal values from solver



    nstre=4
    if (ndimn==3) nstre=6

    if (gid_s==1) then

        write(out_gid_dis,101)'STRESS',1,total_step,3,1,1

        if (ndimn==2) then
            write(out_gid_dis,*)'SIGXX'
            write(out_gid_dis,*)'SIGYY'
            write(out_gid_dis,*)'SIGXY'
            if (nstre==4)write(out_gid_dis,*)'SIGZZ'
        else if(ndimn==3) then
            write(out_gid_dis,*)'SIGXX'
            write(out_gid_dis,*)'SIGYY'
            write(out_gid_dis,*)'SIGZZ'
            write(out_gid_dis,*)'SIGXY'
            write(out_gid_dis,*)'SIGYZ'
            write(out_gid_dis,*)'SIGZX'
        endif

    endif

    !!!!!!!!!!!!!!!!!!!!output for plate
    !if (gid_Mxy==1) then
    !
    !  write(out_gid_dis,101)'STRESS_Moment',1,total_step,3,1,1
    !  write(out_gid_dis,*)'SIGXX'
    !  write(out_gid_dis,*)'SIGYY'
    !  write(out_gid_dis,*)'SIGXY'
    !  write(out_gid_dis,*)'Mx'
    !  write(out_gid_dis,*)'My'
    !  write(out_gid_dis,*)'Mxy'
    !
    !endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    len=0
    do igroup=1,ngroup
        fieldid=group(igroup)%fieldid
        class=group(igroup)%class
        matno = group(igroup)%matno
        name=props(matno)%name
        index=group(igroup)%index
        nnode=elkn(index)%nnode
        if (fieldid(1:1)=='U')then ! zhao 05/12/26
            material=props(matno)%mechanical%solid%material
            if (fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT'.and.nnode/=2.and.index/=22.and.index/=26)then  !20200205
                !.and.name/='CONTACT'.and.nnode/=2)then   !20200205
                if (group(igroup)%ngvar>len)len=group(igroup)%ngvar
            endif
        endif
    end do

    !if (len/=0.and.(gid_s==1.or.gid_ms==1.or.gid_ep==1.or.gid_Y==1.or.gid_Fc==1.or.gid_Mxy==1)) then  !20200205
    if (len/=0.and.(gid_s==1.or.gid_ms==1.or.gid_ep==1.or.gid_Y==1.or.gid_Fc==1)) then  !20200205
        allocate(valun(len,npoin)) ; valun=0.
        !call recovery(valun)
        call average_aera(valun)
        !if(gid_s==1.or.gid_Mxy==1)then  !20200205
        if(gid_s==1)then  !20200205

            do ipoin=1,npoin
                write(out_gid_dis,10)ipoin,valun(1:nstre,ipoin)
            enddo
        endif

        if (gid_ms==1)then

            write(out_gid_dis,101)'PRINCIPALSTRESS',1,total_step,2,1,1
            write(out_gid_dis,*)'SIGMA-1'
            write(out_gid_dis,*)'SIGMA-2'
            if (ndimn==3)write(out_gid_dis,*)'SIGMA-3'

            allocate(smain(ndimn))
            if (ndimn==3)allocate(stres(6),rr(3,3))
            do ipoin=1,npoin
                if (ndimn==2) then
                    sx=valun(1,ipoin)
                    sy=valun(2,ipoin)
                    sxy=valun(3,ipoin)
                    delta=sqrt((sx-sy)**2/4+sxy**2)
                    smain=0.
                    if (delta.lt.1.e-5) goto 12
                    smain(1)=(sx+sy)/2.+delta
                    smain(2)=(sx+sy)/2.-delta
12                  continue
                else
                    stres=valun(:,ipoin)
                    call stresmr ( stres, smain, rr)
                endif
                write(out_gid_dis,10)ipoin,smain
            end do
            deallocate(smain)
            if (ndimn==3)deallocate(stres,rr)

        endif !gid_ms

        if (gid_ep==1)then
            write(out_gid_dis,101)'PLASTICSTRAIN',1,total_step,1,1,0
            do ipoin=1,npoin
                write(out_gid_dis,10)ipoin,valun(nstre+1,ipoin)
            end do
        endif
        if (gid_Y==1)then
            write(out_gid_dis,101)'Yield',1,total_step,1,1,0
            do ipoin=1,npoin
                write(out_gid_dis,10)ipoin,valun(nstre+2,ipoin)
            end do
        endif
        if (gid_FC==1)then
            write(out_gid_dis,101)'FACTOR',1,total_step,1,1,0
            do ipoin=1,npoin
                write(out_gid_dis,10)ipoin,valun(nstre+3,ipoin)
            end do
        endif

        deallocate(valun)

    endif
    if (rmesh/=0)then
        allocate(valun(1,npoin))
        call average_strain(valun)
        write(out_gid_dis,101)'total strain',1,total_step,1,1,0
        do ipoin=1,npoin
            write(out_gid_dis,10)ipoin,valun(1,ipoin)
        end do
        deallocate(valun)
    endif


    !return   !! following is for mcjoint elements
    if (gid_Ns==1) then

        allocate(valun(2,npoin))
        call average_mcjoint(valun)
        write(out_gid_dis,101)'Normal_stress',1,total_step,1,1,0
        do ipoin=1,npoin
            write(out_gid_dis,10)ipoin,valun(1,ipoin)
        end do

        if(gid_ss==1)then

            write(out_gid_dis,101)'Shear_stress',1,total_step,1,1,0
            do ipoin=1,npoin
                write(out_gid_dis,10)ipoin,valun(2,ipoin)
            end do

        endif

        deallocate(valun)

    endif

    !!!!!!!!!!!!!!!!!!!!output for Beam
    if (gid_bem==1) then

        write(bem_res_unit,101)'internal_force_beam(Local)',1,total_step,ndimn,1,1
        if(ndimn==2)then
            write(bem_res_unit,*)'N'
            write(bem_res_unit,*)'Q'
            write(bem_res_unit,*)'M'
        elseif(ndimn==3)then
            write(bem_res_unit,*)'N'
            write(bem_res_unit,*)'Qy'
            write(bem_res_unit,*)'Qz'
            write(bem_res_unit,*)'Mx'
            write(bem_res_unit,*)'My'
            write(bem_res_unit,*)'Mz'
        endif
        allocate(valun(3*(ndimn-1),npoin_bem),npbeam(npoin_bem))
        valun=0.   !20200310
        npbeam=0

        DO igroup =1,ngroup
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if (index==20.or.index==21) then
                    nstre=6*(ndimn-1)
                    allocate(trot(nstre,nstre),force_e(nstre),force_i(nstre),trotx(nstre,nstre))
                    trot=0. ; trotx=0.
                    DO ielgroup = 1,group(igroup)%nelgroup

                        ielem = group(igroup)%list(ielgroup)
                        jelem=liste_bem_new(ielem)

                        rotation=>element(ielem)%rotation

                        trot=0.
                        if (ndimn==2)then
                            trot(1:ndimn,1:ndimn)=rotation
                            trot(3,3)=1.
                            trot(4:5,4:5)=rotation
                            trot(6,6)=1.
                        else if(ndimn==3) then
                            trot(1:3,1:3)=rotation; trot(4:6,4:6)=rotation
                            trot(7:9,7:9)=rotation; trot(10:12,10:12)=rotation
                        end if


                        force_e=element(ielem)%field(1)%tload
                        force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1)  !20200116
                        force_i=force_i-force_e !不需要用trot.x.force_e，%tload和%gpvar都是整体坐标系内的
                        force_e=force_i
                        force_i=trot.x.force_e  !转成局部坐标系下的内力

                        do inode=1,2
                            npbeam(ien_bem(inode,jelem))=npbeam(ien_bem(inode,jelem))+1
                            if(inode==1)then
                                valun(:,ien_bem(inode,jelem))=valun(:,ien_bem(inode,jelem))-force_i(1:3*(ndimn-1))
                            else
                                valun(:,ien_bem(inode,jelem))=valun(:,ien_bem(inode,jelem))+force_i(3*(ndimn-1)+1:6*(ndimn-1))
                            endif
                        end do

                        nullify(rotation)
                    end do
                    deallocate(trot,force_e,force_i,trotx)
                endif
            endif
        end do


        do ipoin=1,npoin_bem
            if(npbeam(ipoin)/=0)valun(:,ipoin)=valun(:,ipoin)/npbeam(ipoin)
            write(bem_res_unit,10)ipoin,valun(:,ipoin)
        end do

        deallocate(valun,npbeam)

    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!output for Bond_cocrete_steel
    if (gid_bcs==1) then

        write(bcs_res_unit,101)'axial-and_shear_stress(Local)',1,total_step,3,1,1
        write(bcs_res_unit,*)'axial_stress'
        write(bcs_res_unit,*)'shear_stress'
        write(bcs_res_unit,*)'relative_slip(*1000)'

        allocate(valun(3,npoin_bcs),npbcs(npoin_bcs))
        valun=0.   !20200310
        npbcs=0
        if(nrcsteel/=0)then
            do i0=1,nrcsteel
                do i1=1,rc_steel(i0)%nline_g_sc
                    nline_s=rc_steel(i0)%line_g_sc(i1)%nline_s
                    do j1=1,nline_s
                        lnods=>rc_steel(i0)%line_g_sc(i1)%linenode_s(:,j1)
                        valun(1,listp_bcs_new(lnods))=valun(1,listp_bcs_new(lnods))+  &
                            rc_steel(i0)%line_g_sc(i1)%axial_stres(j1)
                        npbcs(listp_bcs_new(lnods))=npbcs(listp_bcs_new(lnods))+1
                        nullify(lnods)
                    end do
                end do
            end do

            do ipoin=1,npoin_bcs
                if(npbcs(ipoin)/=0)valun(1,ipoin)=valun(1,ipoin)/npbcs(ipoin)
            end do


            do i0=1,nrcsteel
                do i1=1,rc_steel(i0)%nline_g_sc
                    npairs_sc=rc_steel(i0)%line_g_sc(i1)%npairs_sc
                    do j1=1,npairs_sc
                        ipoin=rc_steel(i0)%line_g_sc(i1)%pairnode_sc(j1)
                        valun(2,listp_bcs_new(ipoin))=rc_steel(i0)%line_g_sc(i1)%shear_stres(j1)
                        valun(3,listp_bcs_new(ipoin))=1000.*rc_steel(i0)%line_g_sc(i1)%slip_sc(j1)
                    end do
                end do
            end do
        else
            do igroup=1,ngroup
                index = group(igroup)%index
                if(index/=1)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods => element(ielem)%field(1)%lnods_f
                    npbcs(listp_bcs_new(lnods))=npbcs(listp_bcs_new(lnods))+1
                    valun(1,listp_bcs_new(lnods))=valun(1,listp_bcs_new(lnods))+ &
                        element(ielem)%field(1)%gpvar(1,1:2)
                    nullify(lnods)
                end do
            end do

            do ipoin=1,npoin_bcs
                if(npbcs(ipoin)/=0)valun(1,ipoin)=valun(1,ipoin)/npbcs(ipoin)
            end do

            do igroup=1,ngroup
                index = group(igroup)%index
                nstre=  group(igroup)%nstre
                if(index/=25)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods => element(ielem)%field(1)%lnods_f
                    do inode=1,nnode
                        ipoin=lnods(inode)
                        if (icpspring(ipoin)/=0)exit
                    enddo

                    valun(2,listp_bcs_new(ipoin))=valun(2,listp_bcs_new(ipoin))+ &
                        element(ielem)%field(1)%gpvar(1,1)
                    valun(3,listp_bcs_new(ipoin))=valun(3,listp_bcs_new(ipoin))+ &
                        element(ielem)%field(1)%gpvar(nstre+4,1)
                    nullify(lnods)
                end do
            end do

        endif


        do ipoin=1,npoin_bcs
            write(bcs_res_unit,10)ipoin,valun(:,ipoin)
        end do

        deallocate(valun,npbcs)

    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


    !!!!!!!!!!!!!!!!!!!!output for Plate  20200311
    if (gid_Mxy==1) then

        write(Mxy_res_unit,101)'STRESS_Moment',1,total_step,3,1,1
        write(Mxy_res_unit,*)'SIGXX'
        write(Mxy_res_unit,*)'SIGYY'
        write(Mxy_res_unit,*)'SIGXY'
        write(Mxy_res_unit,*)'Mx'
        write(Mxy_res_unit,*)'My'
        write(Mxy_res_unit,*)'Mxy'

        allocate(valun(6,npoin_Mxy),npbeam(npoin_Mxy))
        valun=0.   !20200311
        npbeam=0

        DO igroup =1,ngroup
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if(index/=22.and.index/=26)cycle
                matno = group(igroup)%matno
                thick=props(matno)%mechanical%solid%thickness  !202000311

                DO ielgroup = 1,group(igroup)%nelgroup

                    ielem = group(igroup)%list(ielgroup)
                    jelem=liste_mxy_new(ielem)


                    do inode=1,4
                        npbeam(ien_mxy(inode,jelem))=npbeam(ien_mxy(inode,jelem))+1
                    enddo
                    if(index==22) then
                        valun(1:3,ien_mxy(1,jelem))=valun(1:3,ien_mxy(1,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,1)
                        valun(1:3,ien_mxy(2,jelem))=valun(1:3,ien_mxy(2,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,13)
                        valun(1:3,ien_mxy(3,jelem))=valun(1:3,ien_mxy(3,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,16)
                        valun(1:3,ien_mxy(4,jelem))=valun(1:3,ien_mxy(4,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,4)

                        valun(4:6,ien_mxy(1,jelem))=valun(4:6,ien_mxy(1,jelem))+   &
                            thick*element(ielem)%field(1)%gpvar(4:6,1)
                        valun(4:6,ien_mxy(2,jelem))=valun(4:6,ien_mxy(2,jelem))+   &
                            thick*element(ielem)%field(1)%gpvar(4:6,13)
                        valun(4:6,ien_mxy(3,jelem))=valun(4:6,ien_mxy(3,jelem))+   &
                            thick*element(ielem)%field(1)%gpvar(4:6,16)
                        valun(4:6,ien_mxy(4,jelem))=valun(4:6,ien_mxy(4,jelem))+   &
                            thick*element(ielem)%field(1)%gpvar(4:6,4)
                    else if(index==26) then
                        valun(1:3,ien_mxy(1,jelem))=valun(1:3,ien_mxy(1,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,1)
                        valun(1:3,ien_mxy(2,jelem))=valun(1:3,ien_mxy(2,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,2)
                        valun(1:3,ien_mxy(3,jelem))=valun(1:3,ien_mxy(3,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,3)
                        valun(1:3,ien_mxy(4,jelem))=valun(1:3,ien_mxy(4,jelem))+   &
                            element(ielem)%field(1)%gpvar(1:3,4)
                    endif
                end do
            endif
        end do


        do ipoin=1,npoin_mxy
            if(npbeam(ipoin)/=0)valun(:,ipoin)=valun(:,ipoin)/npbeam(ipoin)
            write(mxy_res_unit,10)ipoin,valun(:,ipoin)
        end do

        deallocate(valun,npbeam)

    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

10  format(i10,10(2x,e20.8))
101 format(a15,i8,f12.5,5i8)


    END SUBROUTINE OUT_GID_WRITE

    SUBROUTINE OUT_GID_WRITE_BIN

    character(10)fieldid,class,material,name
    integer(ink) igroup,index,nnode,tnegid,matno,ngaus,igaus
    integer(ink) ipoin,idofn,len,nstre,ilink,node1,node2,kdimn
    integer(ink) npoin_igroup,jelem  !20200311
    real   (irk),allocatable::value(:),stres(:),valun(:,:),rr(:,:),smain(:)
    real   (irk) delta,sx,sy,sxy,zz,hh,factor,thick
    real   (irk),allocatable::resultm(:),vvv(:),trot(:,:),force_e(:),force_i(:),trotx(:,:)
    real   (irk),pointer::rotation(:,:),perme(:)
    integer(ink),pointer::lnods(:)
    integer(ink),allocatable::npbeam(:),listp_bem(:),listp_bem_new(:), & !20200311
        listp_mxy(:),listp_mxy_new(:)
    real   (irk),allocatable::coord_bem(:,:),coord_mxy(:,:),  & !20200311
        cartd(:,:),veloc(:,:),veloc_H(:,:),aera(:)

    real*8 total_step,x,y,z
    real*8,allocatable::GIDB_value(:),GIDB_stres(:),GIDB_valun(:,:)
    CHARACTER*4 NULL


    integer(ink) ielem,ielgroup


    NULL = CHAR(0)//CHAR(0)//CHAR(0)//CHAR(0)

    if (meshc==1.or.rmesh/=0) then
        rewind(out_gid_msh)
        write(out_gid_msh,*)'mesh dimension = 3 elemtype quadrilateral nnode = 4'
        write(out_gid_msh,*)'coordinates'
        do ipoin=1,npoin
            write(out_gid_msh,991)ipoin,coord(:,ipoin)
        end do
        write(out_gid_msh,*)'end coordinates'
        write(out_gid_msh,*)'elements'
        tnegid=0
        if (meshc==1)then
            do igroup=1,ngroup
                if (appear(igroup)==1)then
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        tnegid=tnegid+1
                        write(out_gid_msh,992)tnegid,element(ielem)%field(1)%lnods_f,igroup
                    end do
                endif
            end do
        else if(rmesh/=0)then
            do igroup=1,ngroup
                if (appear(igroup)==1)then
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if (ice0(ielem)==0)then
                            tnegid=tnegid+1
                            write(out_gid_msh,992)tnegid,element(ielem)%field(1)%lnods_f,igroup
                        endif
                    end do
                endif
            end do
            !!!!
            if (nelem1>0)then
                do igroup=1,ngroup
                    if (appear(igroup)==1)then
                        DO ielgroup = 1,group1(igroup)%nelgroup
                            ielem = group1(igroup)%list(ielgroup)
                            if (jce1(ielem)==0)then
                                tnegid=tnegid+1
                                write(out_gid_msh,992)tnegid,element1(ielem)%field(1)%lnods_f,igroup+ngroup
                            endif
                        end do
                    endif
                end do
            endif
            !!!!!!!!!!!!!!
            if (nelem2>0)then
                do igroup=1,ngroup
                    if (appear(igroup)==1)then
                        DO ielgroup = 1,group2(igroup)%nelgroup
                            ielem = group2(igroup)%list(ielgroup)
                            tnegid=tnegid+1
                            write(out_gid_msh,992)tnegid,element2(ielem)%field(1)%lnods_f,igroup+2*ngroup
                        end do
                    endif
                end do
            endif
            !!!!!!!!!!!!!!!!
        endif
        write(out_gid_msh,*)'end elements'
    endif

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!gid_Mxy
    if (gid_mxy==1.and.iblks==lblks+1.and.iincs==1.and.istep/noutf==1) then  !20200311

        npoin_mxy=0
        nelem_mxy=0
        allocate(listp_mxy(npoin))
        DO igroup =1,ngroup
            listp_mxy=0
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if (index/=22)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_mxy(lnods)=1
                    nullify(lnods)
                end do
                npoin_igroup=sum(listp_mxy)
                nelem_mxy=nelem_mxy+group(igroup)%nelgroup
                npoin_mxy=npoin_mxy+npoin_igroup
            endif
        end do

        allocate(coord_mxy(3,npoin_mxy),ien_mxy(5,nelem_mxy),listp_mxy_new(npoin),  &
            liste_mxy_new(nelem))
        coord_mxy=0.;ien_mxy=0;listp_mxy_new=0;liste_mxy_new=0

        npoin_mxy=0;  nelem_mxy=0
        DO igroup =1,ngroup
            listp_mxy=0
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if (index/=22)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_mxy(lnods)=1
                    nullify(lnods)
                end do

                do ipoin=1,npoin
                    if(listp_mxy(ipoin)==0) cycle
                    npoin_mxy=npoin_mxy+1
                    listp_mxy_new(ipoin)=npoin_mxy
                    coord_mxy(1:ndimn,npoin_mxy)=coord(1:ndimn,ipoin)
                end do


                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    nelem_mxy=nelem_mxy+1
                    ien_mxy(1:4,nelem_mxy)=listp_mxy_new(lnods(1:4))
                    ien_mxy(5,nelem_mxy)=igroup
                    liste_mxy_new(ielem)=nelem_mxy
                    nullify(lnods)
                end do

            endif
        end do


        rewind(mxy_msh_unit)
        write(mxy_msh_unit,*)'mesh dimension = 3 elemtype quadrilateral nnode = 4'
        write(mxy_msh_unit,*)'coordinates'
        do ipoin=1,npoin_Mxy
            write(mxy_msh_unit,991)ipoin,coord_mxy(:,ipoin)
        end do
        write(mxy_msh_unit,*)'end coordinates'
        write(mxy_msh_unit,*)'elements'

        do ielem=1,nelem_Mxy
            write(mxy_msh_unit,992)ielem,ien_mxy(:,ielem)
        end do
        write(mxy_msh_unit,*)'end elements'

        deallocate(coord_mxy,listp_mxy_new)
    endif

    !!!!!!gid_bem/=0

    if (gid_bem==1.and.iblks==lblks+1.and.iincs==1.and.istep/noutf==1) then  !20200311
        npoin_bem=0
        nelem_bem=0
        allocate(listp_bem(npoin))
        DO igroup =1,ngroup
            listp_bem=0
            field1= group(igroup)%fieldid(1:1)
            !if (appear(igroup)>0.and.field1=='U')then  !20200724
            if (field1=='U')then
                index = group(igroup)%index
                if (index/=20.and.index/=21)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_bem(lnods)=1
                    nullify(lnods)
                end do
                npoin_igroup=sum(listp_bem)
                nelem_bem=nelem_bem+group(igroup)%nelgroup
                npoin_bem=npoin_bem+npoin_igroup
            endif
        end do

        allocate(coord_bem(3,npoin_bem),ien_bem(3,nelem_bem),listp_bem_new(npoin),  &
            liste_bem_new(nelem))
        coord_bem=0.;ien_bem=0;listp_bem_new=0;liste_bem_new=0

        npoin_bem=0;  nelem_bem=0
        DO igroup =1,ngroup
            listp_bem=0
            field1= group(igroup)%fieldid(1:1)
            !if (appear(igroup)>0.and.field1=='U')then
            if (field1=='U')then  !20200724
                index = group(igroup)%index
                if (index/=20.and.index/=21)cycle
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    listp_bem(lnods)=1
                    nullify(lnods)
                end do

                do ipoin=1,npoin
                    if(listp_bem(ipoin)==0) cycle
                    npoin_bem=npoin_bem+1
                    listp_bem_new(ipoin)=npoin_bem
                    coord_bem(1:ndimn,npoin_bem)=coord(1:ndimn,ipoin)
                end do


                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    nelem_bem=nelem_bem+1
                    ien_bem(1:2,nelem_bem)=listp_bem_new(lnods(1:2))
                    ien_bem(3,nelem_bem)=igroup
                    liste_bem_new(ielem)=nelem_bem
                    nullify(lnods)
                end do

            endif
        end do


        rewind(bem_msh_unit)
        write(bem_msh_unit,*)'mesh dimension  3   elemtype Linear  nnode  2'
        write(bem_msh_unit,*)'coordinates'
        do ipoin=1,npoin_bem
            write(bem_msh_unit,991)ipoin,coord_bem(:,ipoin)
        end do
        write(bem_msh_unit,*)'end coordinates'
        write(bem_msh_unit,*)'elements'

        do ielem=1,nelem_bem
            write(bem_msh_unit,992)ielem,ien_bem(:,ielem)
        end do
        write(bem_msh_unit,*)'end elements'

        deallocate(coord_bem,listp_bem_new)
    endif


991 format(i10,3e18.8)
992 format(i10,10i10)


    total_step=ttime
    if (outintw/=0) then
        allocate(resultm(npoin))
        resultm=0.
        do ipoin=1,npoin
            idofn=nodfn(1,ipoin)
            if (idofn/=0)resultm(ipoin)=result_zero(idofn)
        end do
        do ilink=1,ntlink
            node1=tlink(1,ilink)
            node2=tlink(2,ilink)
            resultm(node1)=resultm(node2)
        end do
    endif

    ! write displacement vector for gid plot

    if (gid_u==1) then

        CALL GID_BeginVectorResult('DISPLACEMENT','TimeStep',total_step,GiD_onNodes,NULL,NULL,'DispX','DispY','DispZ',NULL)

        !write(out_gid_dis,101)'DISPLACEMENT',1,total_step,2,1,0

        do ipoin=1,npoin

            kdimn=0
            do idofn=1,ndimn   !cdofn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)kdimn=kdimn+1
            end do
            allocate(value(kdimn))
            value=0.
            do idofn=1,kdimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)value(idofn)=result_zero(itotv)
            end do


            !steel 2006
            if (icpnorm(ipoin)/=0)value=transpose(prot(:,:,ipoin)).x.value
            !if(kdimn/=0) &
            !    write(out_gid_dis,10)ipoin,value
            if(kdimn/=0)then
                x=value(1)
                y=value(2)
                z=0.0
                if(ndimn==3)z=value(3)
                CALL GID_WriteVector(ipoin,x,y,z)
            endif
            deallocate(value)
        end do

        CALL GID_ENDRESULT

    endif !gid_u

    if(gid_v==1)then
        CALL GID_BeginVectorResult('Velocity','TimeStep',total_step,GiD_onNodes,NULL,NULL,'VelX','VelY','VelZ',NULL)
        !write(out_gid_dis,101)'velocity',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)value(idofn)=result_first(itotv)
            end do
            x=value(1)
            y=value(2)
            z=0.0
            if(ndimn==3)z=value(3)
            CALL GID_WriteVector(ipoin,x,y,z)
        end do
        deallocate(value)
        CALL GID_ENDRESULT
    endif !gid_v

    if(gid_a==1)then
        CALL GID_BeginVectorResult('Acceleration','TimeStep',total_step,GiD_onNodes,NULL,NULL,'AccX','AccY','AccZ',NULL)
        !write(out_gid_dis,101)'acceleration',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)value(idofn)=result_second(itotv)
            end do
            x=value(1)
            y=value(2)
            z=0.0
            if(ndimn==3)z=value(3)
            CALL GID_WriteVector(ipoin,x,y,z)
        end do
        deallocate(value)
        CALL GID_ENDRESULT
    endif !gid_a

    if (gid_rot==1)then
        CALL GID_BeginVectorResult('Rotation','TimeStep',total_step,GiD_onNodes,NULL,NULL,'RotX','RotY','RotZ',NULL)
        !write(out_gid_dis,101)'ROTATION',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=4,2*ndimn
                itotv=nodfn(lmdofn(idofn),ipoin)
                if (itotv/=0)value(idofn-3)=result_zero(itotv)
            end do
            x=value(1)
            y=value(2)
            z=0.0
            if(ndimn==3)z=value(3)
            CALL GID_WriteVector(ipoin,x,y,z)
        end do
        deallocate(value)
        CALL GID_ENDRESULT
    endif !gid_rot


    if(gid_p==1)then
        CALL GID_BeginScalarResult('PORE_PRESSURE','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)
        allocate(value(1),GIDB_value(1))
        do ipoin=1,npoin
            value=0.
            if (lmdofn(8)/=0)idofn=lmdofn(8)
            if (lmdofn(7)/=0)idofn=lmdofn(7)
            itotv=nodfn(idofn,ipoin)
            if (type_problem=='F')then
                if (.not.allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)
                if (allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)-prstat(ipoin)
            else
                if (itotv/=0)value(1)=result_zero(itotv) !+coord(2,ipoin)
            endif
            GIDB_value(1)=value(1)
            call GiD_WriteScalar(ipoin,GIDB_value(1))
        end do
        deallocate(value,GIDB_value)
        CALL GID_ENDRESULT
    endif

    if(gid_wh==1)then !20210324
        CALL GID_BeginScalarResult('WATER-HEAD','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)

        allocate(value(1),GIDB_value(1))
        do ipoin=1,npoin
            value=0.
            if (lmdofn(8)/=0)idofn=lmdofn(8)
            if (lmdofn(7)/=0)idofn=lmdofn(7)
            itotv=nodfn(idofn,ipoin)
            if (type_problem=='F')then
                if (.not.allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)
                if (allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)-prstat(ipoin)
            else
                if (itotv/=0)value(1)=result_zero(itotv)/9810.+coord(ndimn,ipoin)
            endif
            GIDB_value(1)=value(1)
            call GiD_WriteScalar(ipoin,GIDB_value(1))
        end do
        deallocate(value,GIDB_value)
        CALL GID_ENDRESULT
    end if   !20210324


    if(gid_wv==1)then !20210324
        allocate(veloc_H(ndimn,npoin),aera(npoin))
        veloc_H=0.
        aera=0.
        DO igroup =1,ngroup
            if (appear(igroup)>0) then
                fieldid=group(igroup)%fieldid
                if (fieldid(1:1)/='W')cycle
                ! get information from the group level
1               index = group(igroup)%index
                matno = group(igroup)%matno
                nnode = elkn(index)%el_field(1)%nnode_f
                ngaus = elkn(index)%ggaus(1)%ngaus
                if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
                    allocate(perme(ndimn))
                    perme=xvalue(props(matno)%mechanical%fluid%iperm)
                else
                    perme=> props(matno)%mechanical%fluid%permeability
                endif
                allocate (value(nnode),cartd(ndimn,nnode),veloc(ndimn,ngaus))

                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods =>element(ielem)%field(1)%lnods_f
                    do inode=1,nnode
                        ipoin=lnods(inode)
                        value(inode)=0.
                        if (lmdofn(8)/=0)idofn=lmdofn(8)
                        itotv=nodfn(idofn,ipoin)
                        if(itotv/=0)value(inode)=result_zero(itotv)+coord(ndimn,ipoin)
                    end do
                    do igaus=1,ngaus
                        ! get djacb and cartd in the element level
                        !djacb=element(ielem)%egaus(order_intx)%djacb(igaus)
                        cartd=element(ielem)%egaus(1)%cartd(:,:,igaus)
                        veloc(:,igaus)=cartd.x.value
                        veloc(:,igaus)=veloc(:,igaus)*perme
                    end do

                    do inode=1,nnode
                        ipoin=lnods(inode)
                        aera(ipoin)=aera(ipoin)+1.
                        veloc_H(:,ipoin)=veloc_H(:,ipoin)+veloc(:,inode)
                    end do
                    nullify(lnods)
                end do
                deallocate(value,cartd,veloc)


                if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
                    deallocate(perme)
                else
                    nullify(perme)
                endif

            endif
        end do
        do ipoin=1,npoin
            if(abs(aera(ipoin)>.001))veloc_H(:,ipoin)=-veloc_H(:,ipoin)/aera(ipoin)
        end do

        CALL GID_BeginVectorResult('flow_velocity','TimeStep',total_step,GiD_onNodes,NULL,NULL,'flow_vX','flow_vY','flow_vZ',NULL)

        do ipoin=1,npoin
            x=veloc_H(1,ipoin)
            y=veloc_H(2,ipoin)
            z=0.0
            if(ndimn==3)z=veloc_H(3,ipoin)
            CALL GID_WriteVector(ipoin,x,y,z)
            !write(out_gid_dis,10)ipoin,veloc_H(:,ipoin)
        end do
        CALL GID_ENDRESULT

        deallocate(veloc_H,aera)


    endif !20210324


    if (gid_f==1) then
        CALL GID_BeginVectorResult('tofor','TimeStep',total_step,GiD_onNodes,NULL,NULL,'toforX','toforY','toforZ',NULL)
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)value(idofn)=tofor(itotv)
            end do
            x=value(1)
            y=value(2)
            z=0.0
            if(ndimn==3)z=value(3)
            CALL GID_WriteVector(ipoin,x,y,z)
        end do
        deallocate(value)
        CALL GID_ENDRESULT
    endif
    if(gid_pv==1)then !zhao09
        CALL GID_BeginScalarResult('PRESSURE_V','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)
        allocate(value(1),GIDB_value(1))
        do ipoin=1,npoin
            value=0.
            if (lmdofn(8)/=0)idofn=lmdofn(8)
            if (lmdofn(7)/=0)idofn=lmdofn(7)
            itotv=nodfn(idofn,ipoin)
            if (.not.allocated(prstat).and.itotv/=0)value(1)=result_first(itotv)
            if (allocated(prstat).and.itotv/=0)value(1)=result_first(itotv) !-prstat(ipoin)
            GIDB_value(1)=value(1)
            call GiD_WriteScalar(ipoin,GIDB_value(1))
        end do
        deallocate(value,GIDB_value)
        CALL GID_ENDRESULT
    endif !zhao09


    if(gid_p==1.and.nflow/=0)then
        allocate(GIDB_value(1))
        CALL GID_BeginScalarResult('flow_charge','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)
        !write(out_gid_dis,101)'flow_charge',1,total_step,1,1,0
        do ipoin=1,npoin
            !write(out_gid_dis,10)ipoin,flowrate(ipoin)
            GIDB_value(1)=flowrate(ipoin)
            call GiD_WriteScalar(ipoin,GIDB_value(1))
        end do
        CALL GID_ENDRESULT
        deallocate(GIDB_value)
    endif

    ! end write pore_pressure scalar for gid plot

    ! write temperature scalar for gid plot
    if(gid_T==1)then
        CALL GID_BeginScalarResult('TEMPERATURE','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)
        !write(out_gid_dis,101)'TEMPERATURE',1,total_step,1,1,0
        allocate(value(1),GIDB_value(1))
        do ipoin=1,npoin
            value=0.
            idofn=lmdofn(10)
            itotv=nodfn(idofn,ipoin)
            !if (itotv/=0.and.outintw==0)value(1)=result_zero(itotv)
            if (itotv/=0)value(1)=result_zero(itotv)  !20200220
            !write(out_gid_dis,10)ipoin,value
            GIDB_value(1)=value(1)
            call GiD_WriteScalar(ipoin,GIDB_value(1))
        end do
        deallocate(value,GIDB_value)
    endif
    ! end write temperature scalar for gid plot

    if (allocated(resultm))deallocate(resultm)

    !! end of output of nodal values from solver



    nstre=4
    if (ndimn==3) nstre=6

    if (gid_s==1) then
        if(ndimn==2)then
            if(nstre==4)then
                call GiD_BeginPDMMatResult('STRESS','TimeStep',total_step,GiD_onNodes,NULL,NULL,'SXX','SYY','SXY','SZZ')
            else
                call GiD_Begin2DMatResult('STRESS','TimeStep',total_step,GiD_onNodes,NULL,NULL,'SXX','SYY','SXY')
            endif
        else
            call GiD_Begin3DMatResult('STRESS','TimeStep',total_step,GiD_onNodes,NULL,NULL,'SXX','SYY','SZZ','SXY','SYZ','SZX')
        endif
        !write(out_gid_dis,101)'STRESS',1,total_step,3,1,1
        !
        !if (ndimn==2) then
        !    write(out_gid_dis,*)'SIGXX'
        !    write(out_gid_dis,*)'SIGYY'
        !    write(out_gid_dis,*)'SIGXY'
        !    if (nstre==4)write(out_gid_dis,*)'SIGZZ'
        !else if(ndimn==3) then
        !    write(out_gid_dis,*)'SIGXX'
        !    write(out_gid_dis,*)'SIGYY'
        !    write(out_gid_dis,*)'SIGZZ'
        !    write(out_gid_dis,*)'SIGXY'
        !    write(out_gid_dis,*)'SIGYZ'
        !    write(out_gid_dis,*)'SIGZX'
        !endif

    endif

    !!!!!!!!!!!!!!!!!!!!output for plate
    !if (gid_Mxy==1) then
    !
    !  write(out_gid_dis,101)'STRESS_Moment',1,total_step,3,1,1
    !  write(out_gid_dis,*)'SIGXX'
    !  write(out_gid_dis,*)'SIGYY'
    !  write(out_gid_dis,*)'SIGXY'
    !  write(out_gid_dis,*)'Mx'
    !  write(out_gid_dis,*)'My'
    !  write(out_gid_dis,*)'Mxy'
    !
    !endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    len=0
    do igroup=1,ngroup
        fieldid=group(igroup)%fieldid
        class=group(igroup)%class
        matno = group(igroup)%matno
        name=props(matno)%name
        index=group(igroup)%index
        nnode=elkn(index)%nnode
        if (fieldid(1:1)=='U')then ! zhao 05/12/26
            material=props(matno)%mechanical%solid%material
            if (fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT'.and.nnode/=2.and.index/=22)then  !20200205
                !.and.name/='CONTACT'.and.nnode/=2)then   !20200205
                if (group(igroup)%ngvar>len)len=group(igroup)%ngvar
            endif
        endif
    end do

    !if (len/=0.and.(gid_s==1.or.gid_ms==1.or.gid_ep==1.or.gid_Y==1.or.gid_Fc==1.or.gid_Mxy==1)) then  !20200205
    if (len/=0.and.(gid_s==1.or.gid_ms==1.or.gid_ep==1.or.gid_Y==1.or.gid_Fc==1)) then  !20200205
        allocate(valun(len,npoin),GIDB_valun(len,npoin)) ; valun=0.
        !call recovery(valun)
        call average_aera(valun)
        !if(gid_s==1.or.gid_Mxy==1)then  !20200205
        if(gid_s==1)then  !20200205
            GIDB_valun=valun
            do ipoin=1,npoin
                !write(out_gid_dis,10)ipoin,valun(1:nstre,ipoin)
                if(ndimn==2)then
                    if(nstre==4)then
                        call GiD_WritePlainDefMatrix(ipoin,GIDB_valun(1,ipoin),GIDB_valun(2,ipoin),   &
                            GIDB_valun(3,ipoin),GIDB_valun(4,ipoin))
                    else
                        call GiD_Write2DMatrix(ipoin,GIDB_valun(1,ipoin),GIDB_valun(2,ipoin),   &
                            GIDB_valun(3,ipoin))
                    endif
                else
                    call GiD_Write3DMatrix(ipoin,GIDB_valun(1,ipoin),GIDB_valun(2,ipoin),GIDB_valun(3,ipoin),  &
                        GIDB_valun(4,ipoin),GIDB_valun(5,ipoin),GIDB_valun(6,ipoin))
                endif
            enddo
            CALL GID_ENDRESULT
        endif

        if (gid_ms==1)then
            CALL GID_BeginVectorResult('PRINCIPALSTRESS','TimeStep',total_step,GiD_onNodes,NULL,NULL,'SIGMA-1','SIGMA-2','SIGMA-3',NULL)
            !write(out_gid_dis,101)'PRINCIPALSTRESS',1,total_step,2,1,1
            !write(out_gid_dis,*)'SIGMA-1'
            !write(out_gid_dis,*)'SIGMA-2'
            !if (ndimn==3)write(out_gid_dis,*)'SIGMA-3'

            allocate(smain(ndimn))
            if (ndimn==3)allocate(stres(6),rr(3,3))
            do ipoin=1,npoin
                if (ndimn==2) then
                    sx=valun(1,ipoin)
                    sy=valun(2,ipoin)
                    sxy=valun(3,ipoin)
                    delta=sqrt((sx-sy)**2/4+sxy**2)
                    smain=0.
                    if (delta.lt.1.e-5) goto 12
                    smain(1)=(sx+sy)/2.+delta
                    smain(2)=(sx+sy)/2.-delta
12                  continue
                else
                    stres=valun(:,ipoin)
                    call stresmr ( stres, smain, rr)
                endif
                !write(out_gid_dis,10)ipoin,smain
                x=smain(1)
                y=smain(2)
                z=0.0
                if(ndimn==3)z=smain(3)
                CALL GID_WriteVector(ipoin,x,y,z)
            end do
            deallocate(smain)
            if (ndimn==3)deallocate(stres,rr)
            CALL GID_ENDRESULT
        endif !gid_ms

        if (gid_ep==1)then
            CALL GID_BeginScalarResult('PLASTICSTRAIN','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)
            !write(out_gid_dis,101)'PLASTICSTRAIN',1,total_step,1,1,0
            allocate(GIDB_value(1))
            do ipoin=1,npoin
                !write(out_gid_dis,10)ipoin,valun(nstre+1,ipoin)
                GIDB_value(1)=valun(nstre+1,ipoin)
                call GiD_WriteScalar(ipoin,GIDB_value(1))
            end do
            CALL GID_ENDRESULT
            deallocate(GIDB_value)
        endif
        if (gid_Y==1)then
            allocate(GIDB_value(1))
            CALL GID_BeginScalarResult('Yield','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)
            !write(out_gid_dis,101)'Yield',1,total_step,1,1,0
            do ipoin=1,npoin
                !write(out_gid_dis,10)ipoin,valun(nstre+2,ipoin)
                GIDB_value(1)=valun(nstre+2,ipoin)
                call GiD_WriteScalar(ipoin,GIDB_value(1))
            end do
            CALL GID_ENDRESULT
            deallocate(GIDB_value)
        endif
        if (gid_FC==1)then
            allocate(GIDB_value(1))
            CALL GID_BeginScalarResult('FACTOR','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)
            !write(out_gid_dis,101)'FACTOR',1,total_step,1,1,0
            do ipoin=1,npoin
                !write(out_gid_dis,10)ipoin,valun(nstre+3,ipoin)
                GIDB_value(1)=valun(nstre+3,ipoin)
                call GiD_WriteScalar(ipoin,GIDB_value(1))
            end do
            CALL GID_ENDRESULT
            deallocate(GIDB_value)
        endif

        deallocate(valun,GIDB_valun)

    endif
    if (rmesh/=0)then
        allocate(valun(1,npoin))
        call average_strain(valun)
        allocate(GIDB_value(1))
        CALL GID_BeginScalarResult('total_strain','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)

        !write(out_gid_dis,101)'total strain',1,total_step,1,1,0
        do ipoin=1,npoin
            !write(out_gid_dis,10)ipoin,valun(1,ipoin)
            GIDB_value(1)=valun(1,ipoin)
            call GiD_WriteScalar(ipoin,GIDB_value(1))
        end do
        deallocate(valun)
        deallocate(GIDB_value)
        CALL GID_ENDRESULT
    endif


    !return   !! following is for mcjoint elements
    if (gid_Ns==1) then

        allocate(valun(2,npoin))
        call average_mcjoint(valun)
        allocate(GIDB_value(1))
        CALL GID_BeginScalarResult('total_strain','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)

        !write(out_gid_dis,101)'Normal_stress',1,total_step,1,1,0
        do ipoin=1,npoin
            write(out_gid_dis,10)ipoin,valun(1,ipoin)
            GIDB_value(1)=valun(1,ipoin)
            call GiD_WriteScalar(ipoin,GIDB_value(1))
        end do
        CALL GID_ENDRESULT
        if(gid_ss==1)then
            CALL GID_BeginScalarResult('Shear_stress','TimeStep',total_step,GiD_onNodes,NULL,NULL,NULL)

            !write(out_gid_dis,101)'Shear_stress',1,total_step,1,1,0
            do ipoin=1,npoin
                write(out_gid_dis,10)ipoin,valun(2,ipoin)
                GIDB_value(1)=valun(2,ipoin)
                call GiD_WriteScalar(ipoin,GIDB_value(1))
            end do
            CALL GID_ENDRESULT
        endif
        deallocate(GIDB_value)
        deallocate(valun)

    endif

    !!!!!!!!!!!!!!!!!!!!output for Beam
    if (gid_bem==1) then

        write(bem_res_unit,101)'internal_force_beam(Local)',1,total_step,ndimn,1,1
        if(ndimn==2)then
            write(bem_res_unit,*)'N'
            write(bem_res_unit,*)'Q'
            write(bem_res_unit,*)'M'
        elseif(ndimn==3)then
            write(bem_res_unit,*)'N'
            write(bem_res_unit,*)'Qy'
            write(bem_res_unit,*)'Qz'
            write(bem_res_unit,*)'Mx'
            write(bem_res_unit,*)'My'
            write(bem_res_unit,*)'Mz'
        endif
        allocate(valun(3*(ndimn-1),npoin_bem),npbeam(npoin_bem))
        valun=0.   !20200310
        npbeam=0

        DO igroup =1,ngroup
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if (index==20.or.index==21) then
                    nstre=6*(ndimn-1)
                    allocate(trot(nstre,nstre),force_e(nstre),force_i(nstre),trotx(nstre,nstre))
                    trot=0. ; trotx=0.
                    DO ielgroup = 1,group(igroup)%nelgroup

                        ielem = group(igroup)%list(ielgroup)
                        jelem=liste_bem_new(ielem)

                        rotation=>element(ielem)%rotation

                        trot=0.
                        if (ndimn==2)then
                            trot(1:ndimn,1:ndimn)=rotation
                            trot(3,3)=1.
                            trot(4:5,4:5)=rotation
                            trot(6,6)=1.
                        else if(ndimn==3) then
                            trot(1:3,1:3)=rotation; trot(4:6,4:6)=rotation
                            trot(7:9,7:9)=rotation; trot(10:12,10:12)=rotation
                        end if


                        force_e=element(ielem)%field(1)%tload
                        force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1)  !20200116
                        force_i=force_i-force_e !不需要用trot.x.force_e，%tload和%gpvar都是整体坐标系内的
                        force_e=force_i
                        force_i=trot.x.force_e  !转成局部坐标系下的内力

                        do inode=1,2
                            npbeam(ien_bem(inode,jelem))=npbeam(ien_bem(inode,jelem))+1
                            if(inode==1)then
                                valun(:,ien_bem(inode,jelem))=valun(:,ien_bem(inode,jelem))-force_i(1:3*(ndimn-1))
                            else
                                valun(:,ien_bem(inode,jelem))=valun(:,ien_bem(inode,jelem))+force_i(3*(ndimn-1)+1:6*(ndimn-1))
                            endif
                        end do

                        nullify(rotation)
                    end do
                    deallocate(trot,force_e,force_i,trotx)
                endif
            endif
        end do


        do ipoin=1,npoin_bem
            if(npbeam(ipoin)/=0)valun(:,ipoin)=valun(:,ipoin)/npbeam(ipoin)
            write(bem_res_unit,10)ipoin,valun(:,ipoin)
        end do

        deallocate(valun,npbeam)

    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    !!!!!!!!!!!!!!!!!!!!output for Plate  20200311
    if (gid_Mxy==1) then

        write(Mxy_res_unit,101)'STRESS_Moment',1,total_step,3,1,1
        write(Mxy_res_unit,*)'SIGXX'
        write(Mxy_res_unit,*)'SIGYY'
        write(Mxy_res_unit,*)'SIGXY'
        write(Mxy_res_unit,*)'Mx'
        write(Mxy_res_unit,*)'My'
        write(Mxy_res_unit,*)'Mxy'

        allocate(valun(6,npoin_Mxy),npbeam(npoin_Mxy))
        valun=0.   !20200311
        npbeam=0

        DO igroup =1,ngroup
            field1= group(igroup)%fieldid(1:1)
            if (appear(igroup)>0.and.field1=='U')then
                index = group(igroup)%index
                if (index/=22) cycle
                matno = group(igroup)%matno
                thick=props(matno)%mechanical%solid%thickness  !202000311

                DO ielgroup = 1,group(igroup)%nelgroup

                    ielem = group(igroup)%list(ielgroup)
                    jelem=liste_mxy_new(ielem)


                    do inode=1,4
                        npbeam(ien_mxy(inode,jelem))=npbeam(ien_mxy(inode,jelem))+1
                    enddo
                    valun(1:6,ien_mxy(1,jelem))=valun(1:6,ien_mxy(1,jelem))+   &
                        thick*element(ielem)%field(1)%gpvar(1:6,1)
                    valun(1:6,ien_mxy(2,jelem))=valun(1:6,ien_mxy(2,jelem))+   &
                        thick*element(ielem)%field(1)%gpvar(1:6,13)
                    valun(1:6,ien_mxy(3,jelem))=valun(1:6,ien_mxy(3,jelem))+   &
                        thick*element(ielem)%field(1)%gpvar(1:6,16)
                    valun(1:6,ien_mxy(4,jelem))=valun(1:6,ien_mxy(4,jelem))+   &
                        thick*element(ielem)%field(1)%gpvar(1:6,4)
                end do
            endif
        end do


        do ipoin=1,npoin_mxy
            if(npbeam(ipoin)/=0)valun(:,ipoin)=valun(:,ipoin)/npbeam(ipoin)
            write(mxy_res_unit,10)ipoin,valun(:,ipoin)
        end do

        deallocate(valun,npbeam)

    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

10  format(i10,10(2x,e20.8))
101 format(a15,i8,f12.6,5i8)


    END SUBROUTINE OUT_GID_WRITE_BIN
    subroutine OUT_GID_BIN_MESH
    integer(ink),allocatable::lnods(:)
    integer(ink) index0,index,nnode,ipoin,igroup,ielgroup,ielem,np,matno
    character*20 name,text
    real*8 xyz(3)

    !if(iblks/=runblks)return
    write(text,'(i5)')iblks
    text='Block'//trim(adjustl(text))
    CALL GID_BEGINMESHGROUP(trim(text))


    index0=0;xyz=0.
    do igroup=1,ngroup
        if(igroup/=1.and.appear_process(igroup,iblks)==0)cycle

        name=group(igroup)%kname
        index=group(igroup)%index
        nnode=elkn(index)%nnode
        if(allocated(lnods))deallocate(lnods)
        allocate(lnods(nnode+1));lnods=0

        if(index==1.or.index==2.or.index==19.or.index==20.or.index==21)then
            CALL GID_BeginMesh(trim(adjustl(name)),GiD_Dimension(ndimn),GID_ElementType(2),nnode)
        elseif(index==3.or.index==4.or.index==11.or.index==15)then
            CALL GID_BeginMesh(trim(adjustl(name)),GiD_Dimension(ndimn),GID_ElementType(3),nnode)
        elseif(index==5.or.index==6.or.index==22.or.index==12.or.index==16)then
            CALL GID_BeginMesh(trim(adjustl(name)),GiD_Dimension(ndimn),GID_ElementType(4),nnode)
        elseif(index==7.or.index==8.or.index==13.or.index==17)then
            CALL GID_BeginMesh(trim(adjustl(name)),GiD_Dimension(ndimn),GID_ElementType(5),nnode)
        elseif(index==9.or.index==10.or.index==14.or.index==18)then
            CALL GID_BeginMesh(trim(adjustl(name)),GiD_Dimension(ndimn),GID_ElementType(6),nnode)
        endif

        CALL GID_BEGINCOORDINATES
        if(igroup==1)then
            do ipoin=1,npoin
                xyz(1:ndimn)=coord(1:ndimn,ipoin)
                if(ndimn==3)then
                    CALL GID_WRITECOORDINATES(ipoin,xyz(1),xyz(2),xyz(3))
                else
                    CALL GID_WRITECOORDINATES2D(ipoin,xyz(1),xyz(2))
                endif
            end do
        end if
        CALL GID_ENDCOORDINATES

        CALL GID_BEGINELEMENTS

        if(appear_process(igroup,iblks)>0)then
            matno=matno_process(igroup,iblks)

            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                lnods(1:nnode)=element(ielem)%field(1)%lnods_f
                lnods(nnode+1)=matno
                CALL GiD_WriteElementMat(ielem,lnods)
            end do !end do ielgroup
        endif

        CALL GID_ENDELEMENTS
        CALL GID_ENDMESH
        deallocate(lnods)
    end do !end do igroup

    CALL GID_ENDMESHGROUP
1001 format(10i8)
    end subroutine OUT_GID_BIN_MESH


    !20231215YL
    SUBROUTINE OUT_GID_MAX !20231009
    integer(ink)  kdimn,ipoin,idofn,itotv

    out_gid_dismax=1011
    open(out_gid_dismax,file=probn(1:len1)//'max.flavia.res')

    if (gid_u==1) then
        write(out_gid_dismax,101)'DISPLACEMENT',1,1,2,1,0
        do ipoin=1,npoin
            kdimn=0
            do idofn=1,ndimn   !cdofn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)kdimn=kdimn+1
            end do
            if(kdimn/=0)then
                write(out_gid_dismax,10)ipoin,maxdisp(:,ipoin)
            endif
        end do
    endif

    if(gid_v==1)then
        write(out_gid_dismax,101)'velocity',1,1,2,1,0
        do ipoin=1,npoin
            kdimn=0
            do idofn=1,ndimn   !cdofn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)kdimn=kdimn+1
            end do
            if(kdimn/=0)then
                write(out_gid_dismax,10)ipoin,maxv(:,ipoin)
            endif
        end do
    endif !gid_v

    if(gid_a==1)then
        write(out_gid_dismax,101)'acceleration',1,1,2,1,0
        do ipoin=1,npoin
            kdimn=0
            do idofn=1,ndimn   !cdofn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)kdimn=kdimn+1
            end do
            if(kdimn/=0)then
                write(out_gid_dismax,10)ipoin,maxacce(:,ipoin)
            endif
        end do

        write(out_gid_dismax,101)'acceleration_absolue',1,1,2,1,0
        do ipoin=1,npoin
            kdimn=0
            do idofn=1,ndimn   !cdofn
                itotv=nodfn(idofn,ipoin)
                if(itotv/=0)kdimn=kdimn+1
            end do
            if(kdimn/=0)then
                write(out_gid_dismax,10)ipoin,maxacce_a(:,ipoin)
            endif
        end do
    endif !gid_a

10  format(i10,10(2x,e20.8))
101 format(a15,i8,f12.5,5i8)

    END SUBROUTINE OUT_GID_MAX
    !20231215YL

    subroutine geteletype(myndimn,unit,eshape)
    integer(ink) myndimn,unit,eshape

    select case(eshape)
    case(1)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Linear  nnode 2'
    case(2)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Linear  nnode 3'
    case(3)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Triangle nnode 3'
    case(4)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Triangle nnode 6'
    case(5)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Quadrilateral nnode 4'
    case(6)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Quadrilateral nnode 8'
    case(7)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Tetrahedra nnode 4'
    case(8)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Tetrahedra nnode 10'
    case(9)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Hexahedra nnode 8'
    case(10)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Hexahedra nnode 20'
    case(11)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Triangle nnode 6'
    case(12)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Quadrilateral nnode 8'
    case(13)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Tetrahedra nnode 10'
    case(14)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Hexahedra nnode 20'
    case(15)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Triangle nnode 3'
    case(16)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Quadrilateral nnode 4'
    case(17)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Tetrahedra nnode 4'
    case(18)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Hexahedra nnode 8'
    case(19)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Linear  nnode 2'
    case(20)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Linear  nnode 2'
    case(21)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Linear  nnode 2'
    case(22)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Quadrilateral nnode 4'
    case(23)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Prism nnode 6'
    case(24)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Prism nnode 6'
    case(25)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Linear  nnode 2'
    case(26)
        write(unit,*)'mesh dimension ',myndimn,' elemtype Hexahedra nnode 27'
        case default
        print *,'***ERROR***there is not this element type!!!***ERROR***'
        stop
    end select
    end subroutine geteletype


    SUBROUTINE OUTputres

    character(10)fieldid,class,material,name
    integer(ink) igroup,index,nnode,tnegid,kkdimn  !20221202
    integer(ink) ipoin,idofn,len,nstre,ilink,node1,node2
    real   (irk),allocatable::value(:,:),stres(:),valun(:,:),rr(:,:),smain(:,:)
    real   (irk) delta,sx,sy,sxy,zz,hh,factor,total_step
    real   (irk),allocatable::resultm(:),vvv(:)
    integer(ink),pointer::lnods(:)
    integer(ink) ielem,ielgroup

    if (res_u==1) then
        kkdimn=ndimn
        if(res_rot/=0) kkdimn=3*(ndimn-1)  !20221202
        allocate(value(kkdimn,npoin))
        value=0.
        do ipoin=1,npoin
            do idofn=1,kkdimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)value(idofn,ipoin)=result_zero(itotv)
            end do

            if(alfa_p4>0.)then  !20221202
                if (local_p4(ipoin)/=0)value(1:ndimn,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(1:ndimn,ipoin)
            endif
            if (icpnorm(ipoin)/=0)value(1:ndimn,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(1:ndimn,ipoin)
            if(ndimn==3.and.res_rot/=0)then !20221202
                if(alfa_p4>0.)then  !20221202
                    if (local_p4(ipoin)/=0)value(4:6,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(4:6,ipoin)
                endif
                if (icpnorm(ipoin)/=0)value(4:6,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(4:6,ipoin)
            endif
        end do

        write(resunit)value !disp

        !               write(7,*)'disp0='
        ! do ipoin=1,10
        !  write(7,10)ipoin,value(:,ipoin)
        !end do
        deallocate(value)

        if(res_v==1)then
            kkdimn=ndimn
            if(res_rot/=0) kkdimn=3*(ndimn-1)  !20221202
            allocate(value(kkdimn,npoin))
            value=0.
            do ipoin=1,npoin
                do idofn=1,kkdimn
                    itotv=nodfn(idofn,ipoin)
                    if (itotv/=0)value(idofn,ipoin)=result_first(itotv)
                end do

                if(alfa_p4>0.)then  !20221202
                    if (local_p4(ipoin)/=0)value(1:ndimn,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(1:ndimn,ipoin)
                endif
                if (icpnorm(ipoin)/=0)value(1:ndimn,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(1:ndimn,ipoin)

                if(ndimn==3.and.res_rot/=0)then !20221202
                    if(alfa_p4>0.)then  !20221202
                        if (local_p4(ipoin)/=0)value(4:6,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(4:6,ipoin)
                    endif
                    if (icpnorm(ipoin)/=0)value(4:6,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(4:6,ipoin)
                endif
            end do
            write(resunit)value !velocity
            !               write(7,*)'velocity0='
            ! do ipoin=1,10
            !  write(7,10)ipoin,value(:,ipoin)
            !end do

            deallocate(value)
        endif

        if(res_a==1)then
            kkdimn=ndimn
            if(res_rot/=0) kkdimn=3*(ndimn-1)  !20221202
            allocate(value(kkdimn,npoin))
            value=0.
            do ipoin=1,npoin
                do idofn=1,kkdimn
                    itotv=nodfn(idofn,ipoin)
                    if (itotv/=0)value(idofn,ipoin)=result_second(itotv)
                end do

                if(alfa_p4>0.)then  !20221202
                    if (local_p4(ipoin)/=0)value(1:ndimn,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(1:ndimn,ipoin)
                endif
                if (icpnorm(ipoin)/=0)value(1:ndimn,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(1:ndimn,ipoin)

                if(ndimn==3.and.res_rot/=0)then !20221202
                    if(alfa_p4>0.)then  !20221202
                        if (local_p4(ipoin)/=0)value(4:6,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(4:6,ipoin)
                    endif
                    if (icpnorm(ipoin)/=0)value(4:6,ipoin)=transpose(prot(1:ndimn,1:ndimn,ipoin)).x.value(4:6,ipoin)
                endif


            end do
            write(resunit)value !acceleration
            !               write(7,*)'acc0='
            ! do ipoin=1,10
            !  write(7,10)ipoin,value(:,ipoin)
            !end do

            deallocate(value)
        endif
    endif


    if (res_T==1) then  !20210320
        allocate(value(1,npoin))
        value=0.
        do ipoin=1,npoin
            itotv=nodfn(lmdofn(10),ipoin)
            if (itotv/=0)value(1,ipoin)=result_zero(itotv)
        end do
        write(resunit)value !温度
        deallocate(value)
        if(res_Tv==1)then
            allocate(value(1,npoin))
            value=0.
            do ipoin=1,npoin
                itotv=nodfn(lmdofn(10),ipoin)
                if (itotv/=0)value(1,ipoin)=result_first(itotv)
            end do
            write(resunit)value !温变速率
            deallocate(value)
        endif

    endif

    if (res_P==1) then  !20210320
        allocate(value(1,npoin))
        value=0.
        do ipoin=1,npoin
            itotv=nodfn(lmdofn(8),ipoin)
            if (itotv/=0)value(1,ipoin)=result_zero(itotv)
        end do
        write(resunit)value !水压
        deallocate(value)
        if(res_Pv==1)then
            allocate(value(1,npoin))
            value=0.
            do ipoin=1,npoin
                itotv=nodfn(lmdofn(8),ipoin)
                if (itotv/=0)value(1,ipoin)=result_first(itotv)
            end do
            write(resunit)value !水压变化速率
            deallocate(value)
        endif

        if(res_Pa==1)then
            allocate(value(1,npoin))
            value=0.
            do ipoin=1,npoin
                itotv=nodfn(lmdofn(8),ipoin)
                if (itotv/=0)value(1,ipoin)=result_second(itotv)
            end do
            write(resunit)value !水压变化加速速率
            deallocate(value)
        endif

    endif

    if(submodel<0)return  !20210320

    if (allocated(resultm))deallocate(resultm)

    !! end of output of nodal values from solver

    !if (res_s==1.or.res_ms==1.or.res_ep==1.or.res_Y==1.or.res_Fc==1.or.res_Mxy==1) then !20200205
    if (res_s==1.or.res_ms==1.or.res_ep==1.or.res_Y==1.or.res_Fc==1) then !20200205
        nstre=4
        if (ndimn==3) nstre=6

        len=0
        do igroup=1,ngroup

            fieldid=group(igroup)%fieldid
            class=group(igroup)%class
            matno = group(igroup)%matno
            name=props(matno)%name
            index=group(igroup)%index
            nnode=elkn(index)%nnode
            if (fieldid(1:1)=='U')then ! zhao 05/12/26
                material=props(matno)%mechanical%solid%material
                if (fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                    .and.name/='CONTACT'.and.nnode/=2.and.index/=22.and.index/=26)then
                    !.and.name/='CONTACT'.and.nnode/=2)then    !20200205
                    if (group(igroup)%ngvar>len)len=group(igroup)%ngvar
                endif
            endif
        end do

        print *,'ngvar in output=',len,'nstre=',nstre
        if(len>0)then
            allocate(valun(len,npoin)) ; valun=0.
            !call recovery(valun)
            call average_aera(valun)
            !if(res_s==1.or.res_Mxy==1)write(resunit)valun   !stress  20200205
            if(res_s==1)write(resunit)valun   !stress  20200205
            if(res_ms==1)then ! 20200205
                allocate(smain(ndimn,npoin))
                smain=0.
                if (ndimn==3)allocate(stres(6),rr(3,3))
                do ipoin=1,npoin
                    if (ndimn==2) then
                        sx=valun(1,ipoin)
                        sy=valun(2,ipoin)
                        sxy=valun(3,ipoin)
                        delta=sqrt((sx-sy)**2/4+sxy**2)
                        if (delta.lt.1.e-5) goto 12
                        smain(1,ipoin)=(sx+sy)/2.+delta
                        smain(2,ipoin)=(sx+sy)/2.-delta
12                      continue
                    else
                        stres=valun(1:6,ipoin)
                        call stresmr ( stres, smain(:,ipoin), rr)
                    endif
                end do
                write(resunit)smain !principal stress
                deallocate(smain)
                if (ndimn==3)deallocate(stres,rr)
            endif   !20200205
            if(res_ep==1)write(resunit)valun(nstre+1,:) ! Plasticstrain
            if(res_Y==1) write(resunit)valun(nstre+2,:) ! Yield
            if(res_Fc==1)write(resunit)valun(nstre+3,:) ! Factor
        endif

        deallocate(valun)

    endif


    if (gid_Ns==1.or.gid_ss==1) then

        allocate(valun(2,npoin))
        call average_mcjoint(valun)
        if (gid_Ns==1)write(resunit)valun(1,:) !Normal_stress
        if (gid_ss==1)write(resunit)valun(2,:) !Shear_stress
        deallocate(valun)
10      format(i10,3e15.5)

    endif


    END SUBROUTINE OUTputres

    SUBROUTINE OUT_GID_WRITE_w !freq2006

    integer(ink) ipoin,idofn,len,nstre,ilink,node1,node2
    real   (irk),allocatable::value(:),resultm(:)
    real   (irk) total_step

    total_step=ttime
    if (outintw/=0) then
        allocate(resultm(npoin))
        resultm=0.
        do ipoin=1,npoin
            idofn=nodfn(1,ipoin)
            if (idofn/=0)resultm(ipoin)=result_zero(idofn)
        end do
        do ilink=1,ntlink
            node1=tlink(1,ilink)
            node2=tlink(2,ilink)
            resultm(node1)=resultm(node2)
        end do
    endif

    ! write displacement vector for gid plot

    if (lmdofn(1)/=0) then
        write(out_gid_dis,101)'DISPLACEMENT',1,total_step,2,1,0
        allocate(value(1:ndimn))
        do ipoin=1,npoin
            value=0.
            do idofn=1,ndimn
                itotv=nodfn(idofn,ipoin)
                if (itotv/=0)value(idofn)=result_zero(itotv)
            end do
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    endif
    !    deallocate(vvv)
    ! end write displacement vector for gid plot
    ! write rotation vector for gid plot
    if (mdofn>=4)then
        if (lmdofn(4)/=0) then
            write(out_gid_dis,101)'ROTATION',1,total_step,2,1,0
            allocate(value(1:ndimn))
            do ipoin=1,npoin
                value=0.
                do idofn=4,2*ndimn
                    itotv=nodfn(lmdofn(idofn),ipoin)
                    if (itotv/=0)value(idofn-3)=result_zero(itotv)
                end do
                write(out_gid_dis,10)ipoin,value
            end do
            deallocate(value)
        endif
    endif
    ! end write rotation vector for gid plot

    ! write pore_pressure scalar for gid plot

    if (mdofn.ge.7.and.(lmdofn(7)/=0.or.lmdofn(8)/=0)) then
        write(out_gid_dis,101)'PORE-PRESSURE',1,total_step,1,1,0
        allocate(value(1))
        do ipoin=1,npoin
            value=0.
            if (lmdofn(8)/=0)idofn=lmdofn(8)
            if (lmdofn(7)/=0)idofn=lmdofn(7)
            itotv=nodfn(idofn,ipoin)
            if (.not.allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)
            if (allocated(prstat).and.itotv/=0)value(1)=result_zero(itotv)-prstat(ipoin)
            write(out_gid_dis,10)ipoin,value
        end do
        deallocate(value)
    endif

10  format(i10,10(2x,e15.4))
101 format(a15,i8,f20.3,5i8)  !20220302

    END SUBROUTINE OUT_GID_WRITE_w

    SUBROUTINE OUT_NEXT_WRITE

    character(10) field1,class,name,material,model
    integer(ink) ipoin,igroup,idofn,index,order_int,igaus,nstre,ngaus,jdofn,ngvar,idimn
    integer(ink) wngroup,vdimn,order_jnt,jndex,kinit_g
    integer(ink) igaps,ipairs,npairs !ctt2005 zhao 05/09/07
    real   (irk) coef1,coef2,coef
    real   (irk),allocatable::value(:)


    rewind(initwunit)
    write(initwunit,*)'                             STRESS'  !20210207

    !coef1=1.
    !coef2=1.
    kinit_g=1
    if(kinit/=0)kinit_g=kinit  !20220623
    wngroup=0
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        index=group(igroup)%index
        if(index==20.or.index==21)cycle
        if (appear(igroup)>0.and.field1=='U')wngroup=wngroup+1
    end do
    write(initwunit,*)wngroup,kinit_g
    if(wngroup/=0) then  !20220304
        print *,'give me the vdimn,coef1 and coef2?'
        read *,vdimn,coef1,coef2

        DO igroup =1,ngroup
            field1= group(igroup)%fieldid(1:1)
            index=group(igroup)%index
            if(index==20.or.index==21)cycle
            class = group(igroup)%class
            ! judge whether the CO-displacement field is included.
            if (appear(igroup)>0.and.field1=='U') then
                write(initwunit,*)igroup,vdimn,coef1,coef2

                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus=elkn(index)%ggaus(order_int)%ngaus

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




                nstre=group(igroup)%nstre
                ngvar=group(igroup)%ngvar
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    do igaus=1,ngaus
                        write(initwunit,10)ielem,igaus,element(ielem)%field(1)%gpvar(1:ngvar,igaus)
                    end do
                end do
                do ielgroup = 1, group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (model(1:3)=='FCM')then
                        write(initwunit,'(i10,5(2x,e12.5))')ielem,element(ielem)%field(1)%strain
                    endif
                enddo
            endif
        end do
    endif

    write(initwunit,*)'                             INTERNAL_FORCE_BEAM' !20210207
    wngroup=0
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            index=group(igroup)%index
            if(index/=20.and.index/=21)cycle
            wngroup=wngroup+1
        endif
    end do

    write(initwunit,*)wngroup,kinit_g !20220623
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then

            index = group(igroup)%index
            if (index==20.or.index==21) then
                write(initwunit,*)igroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    write(initwunit,10)ielem,element(ielem)%field(1)%gpvar(:,1)
                end do
            endif
        endif
    end do

    write(initwunit,*)'                             STRESS_BOND_SLIP' !20210207
    wngroup=0
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            index=group(igroup)%index
            if(index/=25)cycle
            wngroup=wngroup+1
        endif
    end do

    write(initwunit,*)wngroup,kinit_g !20220623

    !! write force (force*lenth) of  bond-slip joint element
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U')then
            index = group(igroup)%index
            if (index==25) then
                write(initwunit,*)igroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    write(initwunit,'(i6,20(2x,e12.5))')ielem,element(ielem)%field(1)%gpvar(:,1)
                end do
            endif
        endif
    end do




10  format(2i5,15e20.11)
    !write gapn,gapg,state ! contact
    !zhao 05/07/19

    write(initwunit,*)'                             CONTACT_STATE' !20210207
    wngroup=0
    DO igroup =1,ngroup
        matno = group(igroup)%matno
        name  = props(matno)%name
        if  (name/='CONTACT')cycle
        wngroup=wngroup+1
    end do

    write(initwunit,*)wngroup

    DO igroup =1,ngroup
        field1= group(igroup)%fieldid
        index = group(igroup)%index
        if  (field1(1:1)=='U')  then
            matno = group(igroup)%matno
            name  = props(matno)%name
            if  (name/='CONTACT') cycle
            material=props(matno)%mechanical%solid%material
            if(material=='GOODMAN')then
                model=props(matno)%mechanical%solid%Goodman%model
            endif
            write(initwunit,*)igroup
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                write(initwunit,'(i10,30e14.5)')ielem,element(ielem)%field(1)%gapn
                write(initwunit,'(i10,30e14.5)')ielem,element(ielem)%field(1)%gapg
                write(initwunit,'(i10,5x,30a10)')ielem,element(ielem)%field(1)%state
                if (model(1:3)=='FCM')then
                    write(initwunit,'(i10,5x,30a10)')ielem,element(ielem)%field(1)%strain
                endif
            end do
        endif
    enddo


    if(ngaps/=0)then  !20210207
        write(initwunit,*)'CONTACTCTT',' iblks=',iblks,' istep=',istep

        do igaps=1,ngaps
            npairs=gaps(igaps)%npairs

            do ipairs=1,npairs
                if(block_stab==1)then
                    if(ndimn==2) &
                        write(initwunit,'(2i4,4e14.5,i6,4e14.5)')igaps,ipairs,gaps(igaps)%ctforce(:,ipairs),gaps(igaps)%gap(ndimn,ipairs), &
                        gaps(igaps)%state(ipairs),gaps(igaps)%ft(ipairs),(gaps(igaps)%kxyz(idimn,idimn,ipairs),idimn=1,3)
                    if(ndimn==3) &
                        write(initwunit,'(2i4,7e14.5,i6,7e14.5)')igaps,ipairs,gaps(igaps)%ctforce(:,ipairs),gaps(igaps)%gap(ndimn,ipairs), &
                        gaps(igaps)%state(ipairs),gaps(igaps)%ft(ipairs),(gaps(igaps)%kxyz(idimn,idimn,ipairs),idimn=1,6)
                else
                    if(ndimn==2) &
                        write(initwunit,'(2i4,3e14.5,i6,3e14.5)')igaps,ipairs,gaps(igaps)%ctforce(:,ipairs),gaps(igaps)%gap(ndimn,ipairs), &
                        gaps(igaps)%state(ipairs),gaps(igaps)%ft(ipairs),(gaps(igaps)%kxyz(idimn,idimn,ipairs),idimn=1,2)
                    if(ndimn==3) &
                        write(initwunit,'(2i4,4e14.5,i6,4e14.5)')igaps,ipairs,gaps(igaps)%ctforce(:,ipairs),gaps(igaps)%gap(ndimn,ipairs), &
                        gaps(igaps)%state(ipairs),gaps(igaps)%ft(ipairs),(gaps(igaps)%kxyz(idimn,idimn,ipairs),idimn=1,3)
                endif
            enddo
        enddo
    endif

    if (lcdofn(cdofn)==8) then  !20240110
        !allocate(value(cdofn))

        write(initwunit,*)'PORE-PRESSURE'
        write(initwunit,*)'0,',npoin
        write(initwunit,20)0,0,0,0,0,0,0,1
        write(initwunit,20)0,0,0,0,0,0,0,0   !order_time_mdofn

        do ipoin=1,npoin

            !value=0.0
            !do idofn=1,cdofn
            !   jdofn=lcdofn(idofn)
            !   itotv=nodfn(idofn,ipoin)
            !   if (itotv/=0)value(idofn)=result_zero(itotv)
            !end do
            !write(initwunit,10)ipoin,value
            itotv=nodfn(cdofn,ipoin)

            if(itotv/=0)then
                write(initwunit,30)ipoin,result_zero(itotv)
            else
                write(initwunit,30)ipoin,0.
            endif

        end do

        !deallocate(value)
    endif

    if (lcdofn(ndimn)==ndimn) then  !20240110
        !allocate(value(cdofn))

        write(initwunit,*)'DISPLACEMENT'
        write(initwunit,*)'0,',npoin
        write(initwunit,20)1,1,1,0,0,0,0,0
        write(initwunit,20)0,0,0,0,0,0,0,0   !order_time_mdofn

        do ipoin=1,npoin

            !!value=0.0
            !!do idofn=1,ndimn
            !!   itotv=nodfn(idofn,ipoin)

            !if(itotv/=0)then
            write(initwunit,30)ipoin,result_zero(nodfn(1:ndimn,ipoin))
            !else
            !    write(initwunit,30)ipoin,0.
            !endif
            !end do
        end do

        !deallocate(value)
    endif

20  format(10i10)
30  format(i5,15e15.6)

    END SUBROUTINE OUT_NEXT_WRITE

    SUBROUTINE OUT_RECORD

    integer(ink) i0,ioutnode,node,idofn,itotv,   &
        ioutelement,ioutgap,ioutmcjoint,ielem, &
        index,order_int,ngaus,jdofn,ilink,node1,node2,istre,nintf,nintf1
    real   (irk),allocatable::value(:),wtime(:),resultm(:),valuex(:,:)
    integer(ink),pointer::listn(:)  !20210803
    real   (irk),pointer::rintn(:)  !20210803


    if (outintw/=0) then
        allocate(resultm(npoin))
        resultm=0.
        do ipoin=1,npoin
            idofn=nodfn(1,ipoin)
            if (idofn/=0)resultm(ipoin)=result_zero(idofn)
        end do
        do ilink=1,ntlink
            node1=tlink(1,ilink)
            node2=tlink(2,ilink)
            resultm(node1)=resultm(node2)
        end do
    endif

    do i0=1,wpgroup
        toutnode= out_point_groups(i0)%toutnode
        allocate(value(iwriten),wtime(iwriten))

        do ioutnode=1,toutnode  !20210803

            inode=out_point_groups(i0)%out_point_group(ioutnode)%inode
            jnode=out_point_groups(i0)%out_point_group(ioutnode)%jnode
            jdofn=out_point_groups(i0)%out_point_group(ioutnode)%idofn
            nintf=out_point_groups(i0)%out_point_group(ioutnode)%nintf
            nintf1=out_point_groups(i0)%out_point_group(ioutnode)%nintf1

            value=0.;wtime=0.
            if (iwriten>1)then
                value(1:iwriten-1)=out_point_groups(i0)%out_point_group(ioutnode)%value
                wtime(1:iwriten-1)  =out_point_groups(i0)%out_point_group(ioutnode)%wtime
            end if

            idofn=lmdofn(jdofn)
            if(nintf==0)then !20210803
                itotv=nodfn(idofn,inode)
                if ((jdofn/=8.and.jdofn/=10).or.(jdofn==10.and.outintw==0)) then
                    if (itotv/=0)value(iwriten)=result_zero(itotv)
                else if(jdofn==10.and.outintw/=0) then
                    value(iwriten)=resultm(inode)
                else
                    if (.not.allocated(prstat).and.itotv/=0)value(iwriten)=result_zero(itotv)
                    if (allocated(prstat).and.itotv/=0)value(iwriten)=result_zero(itotv)-prstat(inode)
                endif  !20210803
            else
                listn=>out_point_groups(i0)%out_point_group(ioutnode)%listn
                rintn=>out_point_groups(i0)%out_point_group(ioutnode)%rintn
                idofn=lcdofn(jdofn)
                value(iwriten)=dot_product(rintn,result_zero(nodfn(idofn,listn)))
                nullify(listn,rintn)
            endif  !20210803

            if(jnode/=0)then
                if(nintf1==0)then!20210803
                    itotv=nodfn(idofn,jnode)
                    if (itotv/=0)value(iwriten)=value(iwriten)-result_zero(itotv)
                else
                    listn=>out_point_groups(i0)%out_point_group(ioutnode)%listn1
                    rintn=>out_point_groups(i0)%out_point_group(ioutnode)%rintn1
                    value(iwriten)=value(iwriten)-dot_product(rintn,result_zero(nodfn(idofn,listn)))
                    nullify(listn,rintn)
                endif    !20210803
            endif


            wtime(iwriten)=ttime  !20210803

            if (iwriten>1)then
                deallocate(out_point_groups(i0)%out_point_group(ioutnode)%value,      &
                    out_point_groups(i0)%out_point_group(ioutnode)%wtime)
            end if
            allocate(out_point_groups(i0)%out_point_group(ioutnode)%value(iwriten),   &
                out_point_groups(i0)%out_point_group(ioutnode)%wtime(iwriten))
            out_point_groups(i0)%out_point_group(ioutnode)%value=value
            out_point_groups(i0)%out_point_group(ioutnode)%wtime=wtime
        end do  !ioutnode

        deallocate(value,wtime)

    end do  !i0

    if (outintw/=0)deallocate(resultm)
    !! records element average stress
    do ioutelement=1,toutelement

        ielem=out_element_group(ioutelement)%ielem
        index=element(ielem)%index
        !if(index.ne.20.and.index.ne.21) then ! not for beam
        if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus
        endif
        allocate(value(iwriten),wtime(iwriten))
        if (iwriten>1)then
            value(1:iwriten-1)=out_element_group(ioutelement)%value
            wtime(1:iwriten-1)  =out_element_group(ioutelement)%wtime
        end if

        istre=out_element_group(ioutelement)%istre
        !if(index.ne.20.and.index.ne.21) then ! not for beam
        if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
            value(iwriten)=sum(element(ielem)%field(1)%gpvar(istre,1:ngaus))
            value(iwriten)=value(iwriten)/ngaus
        else
            value(iwriten)=element(ielem)%field(1)%gpvar(istre,1)
        endif
        wtime(iwriten)=ttime

        if (iwriten>1)then
            deallocate(out_element_group(ioutelement)%value,      &
                out_element_group(ioutelement)%wtime)
        end if
        allocate(out_element_group(ioutelement)%value(iwriten),   &
            out_element_group(ioutelement)%wtime(iwriten))
        out_element_group(ioutelement)%value=value(:)
        out_element_group(ioutelement)%wtime=wtime

        deallocate(value,wtime)

    end do
    !! records average gaps for contact interface element
    do ioutgap=1,toutgap

        ielem=out_gap_group(ioutgap)%ielem
        index=element(ielem)%index
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        ngaus = elkn(index)%ggaus(order_int)%ngaus
        allocate(value(iwriten),wtime(iwriten))
        if (iwriten>1)then
            value(1:iwriten-1)=out_gap_group(ioutgap)%value
            wtime(1:iwriten-1)  =out_gap_group(ioutgap)%wtime
        end if

        value(iwriten)=sum(element(ielem)%field(1)%gapg(1:ngaus))
        value(iwriten)=value(iwriten)/ngaus
        wtime(iwriten)=ttime

        if (iwriten>1)then
            deallocate(out_gap_group(ioutgap)%value,      &
                out_gap_group(ioutgap)%wtime)
        end if
        allocate(out_gap_group(ioutgap)%value(iwriten),   &
            out_gap_group(ioutgap)%wtime(iwriten))
        out_gap_group(ioutgap)%value=value(:)
        out_gap_group(ioutgap)%wtime=wtime

        deallocate(value,wtime)

    end do
    !! records average normal and tangent stresses for mcjonit elements
    do ioutmcjoint=1,toutmcjoint

        ielem=out_mcjoint_group(ioutmcjoint)%ielem
        index=element(ielem)%index
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        ngaus = elkn(index)%ggaus(order_int)%ngaus
        allocate(valuex(2,iwriten),wtime(iwriten))
        if (iwriten>1)then
            valuex(:,1:iwriten-1)=out_mcjoint_group(ioutmcjoint)%value
            wtime(1:iwriten-1)  =out_mcjoint_group(ioutmcjoint)%wtime
        end if

        valuex(1,iwriten)=sum(element(ielem)%field(1)%ntstress(1,1:ngaus))
        valuex(2,iwriten)=sum(element(ielem)%field(1)%ntstress(2,1:ngaus))
        valuex(:,iwriten)=valuex(:,iwriten)/ngaus
        wtime(iwriten)=ttime

        if (iwriten>1)then
            deallocate(out_mcjoint_group(ioutmcjoint)%value,      &
                out_mcjoint_group(ioutmcjoint)%wtime)
        end if
        allocate(out_mcjoint_group(ioutmcjoint)%value(2,iwriten),   &
            out_mcjoint_group(ioutmcjoint)%wtime(iwriten))
        out_mcjoint_group(ioutmcjoint)%value=valuex
        out_mcjoint_group(ioutmcjoint)%wtime=wtime

        deallocate(valuex,wtime)

    end do
    END SUBROUTINE OUT_RECORD

    subroutine gid_output_parameter
    character(20) fieldid,material,criteria
    integer(ink) igroup,matno,index,nrfields,ifield,ierror,gidres_u,gidres_v,gidres_a,gidres_rot,gidres_s,gidres_ms, &
        gidres_f,gidres_T,gidres_P,gidres_Pv,gidres_ep,gidres_Y,gidres_FC,gidres_Ns,gidres_Ss,  &
        gidres_Pa,gidres_Tv  !gidres_Mxy     !20200205 gidres_Mxy




    gidres_u=0
    gidres_v=0
    gidres_a=0
    gidres_rot=0
    gidres_s=0
    gidres_ms=0
    gidres_f=0
    gidres_T=0
    gidres_Tv=0
    gidres_P=0
    gidres_Pv=0
    gidres_ep=0
    gidres_Y=0
    gidres_FC=0
    gidres_Ns=0
    gidres_Ss=0
    !gidres_Mxy =0  !20200205 gidres_Mxy

    do igroup=1,ngroup
        matno=group(igroup)%matno
        fieldid=group(igroup)%fieldid
        index=group(igroup)%index
        nrfields=elkn(index)%nrfields
        do ifield=1,nrfields
            if(fieldid(ifield:ifield)=='U')then
                gidres_u=1
                gidres_s=1
                gidres_ms=1
                gidres_f=1
                if((type_problem=='S'.or.type_problem=='F').and.allocated(result_first))gidres_v=1
                if(type_problem=='F'.and.allocated(result_second))gidres_a=1
                if(index==22.or.index==20)gidres_rot=1
                !if(index==22)gidres_Mxy=1 !20200205 gidres_Mxy

                material=props(matno)%mechanical%solid%material
                if (material(1:6)/='ELASTIC')then
                    gidres_ep=1
                    gidres_Y=1
                    gidres_FC=1
                    if (material=='CLASSICALEP')criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
                    if (material=='CLASSICALEP'.and.criteria=='MCJOINT')then
                        gidres_Ns=1
                        gidres_Ss=1
                    endif
                endif
            endif
            if(fieldid(ifield:ifield)=='W')then
                gidres_p=gid_p  !20221014
                if(type_problem/='Q')gidres_Pv=1
                if(type_problem=='F')gidres_Pa=1
            endif
            if(fieldid(ifield:ifield)=='T')then
                gidres_T=1
                if(type_problem/='Q')gidres_Tv=1
            endif
        enddo
    enddo

    ierror=0

    if((gid_u  -gidres_u  )==1)ierror=1
    if((gid_s  -gidres_s  )==1)ierror=2
    if((gid_ms -gidres_ms )==1)ierror=3
    if((gid_f  -gidres_f  )==1)ierror=4
    if((gid_rot-gidres_rot)==1)ierror=5
    if((gid_v  -gidres_v  )==1)ierror=6
    if((gid_a  -gidres_a  )==1)ierror=7
    if((gid_T  -gidres_T  )==1)ierror=8
    if((gid_P  -gidres_P  )==1)ierror=9
    if((gid_Pv -gidres_Pv )==1)ierror=10
    if((gid_ep -gidres_ep )==1)ierror=11
    if((gid_Y  -gidres_Y  )==1)ierror=12
    if((gid_FC -gidres_FC )==1)ierror=13
    if((gid_Ns -gidres_Ns )==1)ierror=14
    if((gid_Ss -gidres_Ss )==1)ierror=15
    !if((gid_Mxy -gidres_Mxy )==1)ierror=16 !20200205 gidres_Mxy



    if((res_u  -gidres_u  )==1)ierror=-1
    if((res_s  -gidres_s  )==1)ierror=-2
    if((res_ms -gidres_ms )==1)ierror=-3
    if((res_f  -gidres_f  )==1)ierror=-4
    if((res_rot-gidres_rot)==1)ierror=-5
    if((res_v  -gidres_v  )==1)ierror=-6
    if((res_a  -gidres_a  )==1)ierror=-7
    if((res_T  -gidres_T  )==1)ierror=-8
    if((res_P  -gidres_P  )==1)ierror=-9
    if((res_Pv -gidres_Pv )==1)ierror=-10
    if((res_ep -gidres_ep )==1)ierror=-11
    if((res_Y  -gidres_Y  )==1)ierror=-12
    if((res_FC -gidres_FC )==1)ierror=-13
    if((res_Ns -gidres_Ns )==1)ierror=-14
    if((res_Ss -gidres_Ss )==1)ierror=-15
    if((res_Pa -gidres_Pa )==1)ierror=-16  !20210320
    if((res_Tv -gidres_Tv )==1)ierror=-17  !20210320

    if(ierror/=0)then
        write(*,*)'stop for ierror/=0 ! ,ierror=',ierror
        stop
    endif



    end subroutine gid_output_parameter

    SUBROUTINE output_read

    character(50)text
    integer(ink) igroup,nintf,inode,wegroup,wggroup,wjgroup,begin_element,     &
        end_element,istre,wpgroup1,wpgroup2,nintf1,groupbi,wstep,  &
        ielgroup,ielem,ipoin,idimn
    integer(ink),allocatable::temp(:,:),icpx(:)


    read(outpread,*)text
    read(outpread,*)text
    !print *,text
    read(outpread,*)irecover,wpgroup,wegroup,wggroup,wjgroup
    !print *,'irecover,wpgroup,wegroup,wggroup,wjgroup=',irecover,wpgroup,wegroup,wggroup,wjgroup
    !stop
    read(outpread,*)text
    read(outpread,*)text
    if (wpgroup==0)goto 1  !20210803
    if(Bparameter==-3)then
        rewind(back_ctl_unit)
        write(back_ctl_unit,*)'information for given points：Npoints_pb'
    endif
    allocate(out_point_groups(wpgroup)) !20210805
    do i0=1,wpgroup
        read(outpread,*)groupbi,wpgroup1,wpgroup2,wstep

        out_point_groups(i0)%groupb=abs(groupbi)
        if(groupbi<0)then  !20231030
            allocate(icpx(npoin))
            icpx=0
            DO ielgroup = 1,group(abs(groupbi))%nelgroup
                ielem = group(abs(groupbi))%list(ielgroup)
                icpx(element(ielem)%field(1)%lnods_f)=1
            end do
            toutnode=ndimn*sum(icpx)
            if(Bparameter==-3)then
                write(back_ctl_unit,*)toutnode
                write(back_ctl_unit,*)'1:Npoints_pb/i0,ndofn,imdofn,nintf/listf/rintf'
            endif

            out_point_groups(i0)%toutnode=toutnode
            allocate(out_point_groups(i0)%out_point_group(toutnode))


            write(outpwrite,10)i0,abs(groupbi),toutnode,wstep

            toutnode=0
            do ipoin=1,npoin
                if(icpx(ipoin)==0)cycle
                do idimn=1,ndimn
                    toutnode=toutnode+1
                    out_point_groups(i0)%out_point_group(toutnode)%inode =ipoin
                    out_point_groups(i0)%out_point_group(toutnode)%jnode =0
                    out_point_groups(i0)%out_point_group(toutnode)%idofn =idimn
                    out_point_groups(i0)%out_point_group(toutnode)%nintf =0
                    if(Bparameter==-3)then
                        write(back_ctl_unit,10)toutnode,1,idimn,1
                        write(back_ctl_unit,10)ipoin
                        write(back_ctl_unit,20)1.
                    endif
                end do
            end do

            deallocate(icpx)

        else !20231030
            toutnode=wpgroup1+wpgroup2
            write(outpwrite,*)'iwpgroup,groupb,mdism,wstep'
            write(outpwrite,10)i0,groupbi,toutnode,wstep

            if(Bparameter==-3)then
                write(back_ctl_unit,*)toutnode
                write(back_ctl_unit,*)'1:Npoints_pb/i0,ndofn,imdofn,nintf/listf/rintf'
            endif


            out_point_groups(i0)%toutnode=toutnode
            allocate(out_point_groups(i0)%out_point_group(toutnode))
            toutnode=0
            do igroup=1,wpgroup1
                toutnode=toutnode+1
                read(outpread,*)inode,jnode,idofn
                out_point_groups(i0)%out_point_group(toutnode)%inode =inode
                out_point_groups(i0)%out_point_group(toutnode)%jnode =jnode
                out_point_groups(i0)%out_point_group(toutnode)%idofn =idofn
                out_point_groups(i0)%out_point_group(toutnode)%nintf =0
                write(outpwrite,10)toutnode,inode,jnode,idofn  !,0

                if(Bparameter==-3)then
                    write(back_ctl_unit,10)toutnode,1,idofn,1
                    write(back_ctl_unit,10)inode
                    write(back_ctl_unit,20)1.
                endif

            end do

            do igroup=1,wpgroup2
                read(outpread,*)inode,jnode,idofn,nintf,nintf1
                toutnode=toutnode+1
                write(outpwrite,10)toutnode,inode,jnode,idofn  !,nintf,nintf1
                if(nintf/=0)then
                    allocate(out_point_groups(i0)%out_point_group(toutnode)%listn(nintf),   &
                        out_point_groups(i0)%out_point_group(toutnode)%rintn(nintf))
                    read(outpread,*) out_point_groups(i0)%out_point_group(toutnode)%listn
                    read(outpread,*) out_point_groups(i0)%out_point_group(toutnode)%rintn
                    !write(outpwrite,10)out_point_groups(i0)%out_point_group(toutnode)%listn
                    !write(outpwrite,20)out_point_groups(i0)%out_point_group(toutnode)%rintn
                endif
                if(nintf1/=0)then
                    allocate(out_point_groups(i0)%out_point_group(toutnode)%listn1(nintf1),  &
                        out_point_groups(i0)%out_point_group(toutnode)%rintn1(nintf1))
                    read(outpread,*) out_point_groups(i0)%out_point_group(toutnode)%listn1
                    read(outpread,*) out_point_groups(i0)%out_point_group(toutnode)%rintn1
                    !write(outpwrite,10)out_point_groups(i0)%out_point_group(toutnode)%listn1
                    !write(outpwrite,20)out_point_groups(i0)%out_point_group(toutnode)%rintn1
                endif

                out_point_groups(i0)%out_point_group(toutnode)%inode =inode
                out_point_groups(i0)%out_point_group(toutnode)%jnode =jnode
                out_point_groups(i0)%out_point_group(toutnode)%idofn =idofn
                out_point_groups(i0)%out_point_group(toutnode)%nintf =nintf
                out_point_groups(i0)%out_point_group(toutnode)%nintf1 =nintf1
            end do
        endif  !20231030
    end do  !I0, 20210805

    if(Bparameter==-3)then
        write(back_ctl_unit,*)'ngdis_bk'
        write(back_ctl_unit,10) 1
        write(back_ctl_unit,*)'（1:ngdis_bk):fixed_dis/appear_gdis_bk(1:ngroup)/npoin_bk/node_bk(1:npoin_bk))'
        allocate(icpx(3*(ndimn-1)))
        icpx=1
        write(back_ctl_unit,10)icpx
        deallocate(icpx)
        allocate(icpx(ngroup))
        icpx=0
        icpx(abs(groupbi))=1
        write(back_ctl_unit,10)icpx
        deallocate(icpx)
        write(back_ctl_unit,10)toutnode

        allocate(icpx(toutnode))
        do inode=1,toutnode
            icpx(inode)=inode
        end do
        write(back_ctl_unit,10)icpx
        deallocate(icpx)
    endif

    !20210803

1   read(outpread,*)text
    if (wegroup==0) goto 2
    toutelement=0
    allocate(temp(3,wegroup))
    do igroup=1,wegroup
        read(outpread,*)begin_element,end_element,istre
        toutelement=toutelement+(end_element-begin_element)+1
        temp(1,igroup)=begin_element
        temp(2,igroup)=end_element
        temp(3,igroup)=istre
    end do

    allocate(out_element_group(toutelement))
    toutelement=0

    do igroup=1,wegroup

        do ielem=temp(1,igroup),temp(2,igroup)
            toutelement=toutelement+1
            out_element_group(toutelement)%ielem =ielem
            out_element_group(toutelement)%istre =temp(3,igroup)
        end do
    end do

    deallocate(temp)
2   read(outpread,*)text

    if (wggroup==0) goto 3
    toutgap=0
    allocate(temp(2,wggroup))
    do igroup=1,wggroup
        read(outpread,*)begin_element,end_element
        toutgap=toutgap+(end_element-begin_element)+1
        temp(1,igroup)=begin_element
        temp(2,igroup)=end_element
    end do

    allocate(out_gap_group(toutgap))
    toutgap=0

    do igroup=1,wggroup

        do ielem=temp(1,igroup),temp(2,igroup)
            toutgap=toutgap+1
            out_gap_group(toutgap)%ielem =ielem
        end do
    end do

    deallocate(temp)

3   read(outpread,*)text

    if (wjgroup==0) return
    toutmcjoint=0
    allocate(temp(2,wjgroup))
    do igroup=1,wjgroup
        read(outpread,*)begin_element,end_element
        toutmcjoint=toutmcjoint+(end_element-begin_element)+1
        temp(1,igroup)=begin_element
        temp(2,igroup)=end_element
    end do

    allocate(out_mcjoint_group(toutmcjoint))
    toutmcjoint=0

    do igroup=1,wjgroup

        do ielem=temp(1,igroup),temp(2,igroup)
            toutmcjoint=toutmcjoint+1
            out_mcjoint_group(toutmcjoint)%ielem =ielem
        end do
    end do

    deallocate(temp)

10  format(20i10)
20  format(20e11.3)

    END SUBROUTINE output_read

    SUBROUTINE RECOVER
    !*********************************************************************
    !
    !*** SUPERCONVENGENT RECOVERY METHOD (ZIENKIEWICZ AND ZHU )
    !
    !********************************************************************
    character(10)fieldid,class,name,material
    integer(ink) igroup,index,order_int,nnode,nnods,ngaus,  &
        ipoin,jelem,ielem,inods,nnodt,kwji,kterm,  &
        kpoin,igaus,isamp,igvar,matno,jpoin,ngvar
    integer(ink),allocatable::iount(:),icpoi(:)
    real   (irk) x,y,z,fvalu,eps
    real   (irk),allocatable::valun(:),cmatx(:,:),cload(:), &
        a(:,:),b(:,:),shg(:)

    eps=0.1e-6
    allocate(iount(npoin),icpoi(npoin),valun(npoin))
    do igroup=1,ngroup

        if (appear(igroup)>0)then
            fieldid=group(igroup)%fieldid
            class=group(igroup)%class
            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            index=group(igroup)%index
            nnode=elkn(index)%nnode
            if (fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT'.and.nnode/=2.and.index/=22.and.index/=26)then
                order_int=elkn(index)%el_field(1)%order_intrules(1)

                nnods=nnode
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                ngvar=group(igroup)%ngvar
                if (associated(group(igroup)%valun))deallocate(group(igroup)%valun)
                allocate(group(igroup)%valun(npoin,ngvar))

                icpoi=1
                do jpoin=1,group(igroup)%np_unode
                    ipoin=group(igroup)%unode(jpoin)%ipoin
                    if ((group(igroup)%unode(jpoin)%ne_unode)*ngaus<nnods)    then
                        icpoi(ipoin)=0
                    endif
                end do

                !
                do igvar=1,ngvar
                    iount=0
                    valun=0.0


                    !**** LOOP OVER ALL THE VERTEX NODES (INCLUDING BOUNDARY ONES)
                    !
                    DO 10 jPOIN=1,group(igroup)%np_unode
                        ipoin=group(igroup)%unode(jpoin)%ipoin
                        if (icpoi(ipoin).eq.0) goto 10
                        !
5001                    CONTINUE
                        !
                        allocate(cmatx(nnods,nnods),cload(nnods),shg(nnods))
                        cmatx=0.0
                        cload=0.0
                        !
                        !**** LOOP OVER NODE RELATED ELEMENTS
                        !
                        !----------------------------------------------------------------------
                        DO 20 JELEM=1,group(igroup)%unode(jpoin)%ne_unode
                            IELEM=group(igroup)%unode(jpoin)%list(jelem)
                            DO 40 IGAUS=1,ngaus
                                x=element(ielem)%egaus(order_int)%gpcod(1,igaus)
                                y=element(ielem)%egaus(order_int)%gpcod(2,igaus)

                                if (ndimn.eq.3)z=element(ielem)%egaus(order_int)%gpcod(3,igaus)
                                !
                                !**** SMOOTHING FUNCTION AT GAUSS POINTS
                                !
                                if (ndimn.eq.2)CALL SFUN2(NNODS,SHG,X,Y)
                                if (ndimn.eq.3)CALL SFUN3(NNODS,SHG,X,Y,Z)
                                !
                                !**** COMPUTE THE SMOOTHING EQUATION
                                !
                                DO  INODS=1,NNODS
                                    CMATX(INODS,:)=CMATX(INODS,:)+SHG(INODS)*SHG(:)
                                END DO
                                !
                                FVALU=element(ielem)%field(1)%gpvar(igvar,igaus)

                                CLOAD=CLOAD+SHG*FVALU
                                !
40                          CONTINUE
20                      CONTINUE
                        !--------------------------------------------------------------------
                        !
                        NNODT=NNODS
                        allocate(a(nnodt,nnodt),b(nnodt,1))
                        a=cmatx
                        b(:,1)=cload
                        !
                        !**** SOLVE THE EQUATION
                        !
                        KWJI=0
                        CALL GSCLO(NNODT,1,A,B,eps,KWJI,KTERM)
                        if (KWJI.EQ.1) GO TO 4001
                        cload=b(:,1)
                        !
4001                    CONTINUE
                        deallocate(a,b)
                        if (KWJI.EQ.1) THEN
                            !    write(36,*)' TROUBLE FOR NODE', IPOIN
                            NNODS=KTERM-1
                            if (ndimn.eq.2) then
                                if (nnods.eq.2) nnods=1
                                if (nnods.eq.5) nnods=4
                                if (nnods.eq.7) nnods=6
                            else
                                if (nnods.eq.3) nnods=1
                                if (nnods.eq.7) nnods=4
                                if (nnods.eq.9) nnods=8
                                if (nnods.eq.19) nnods=10
                            endif
                            deallocate(cmatx,cload,shg)
                            GO TO 5001
                        END IF
                        !
                        !**** CALCULATE THE SMOOTHED STRESS AT CORNER NODE
                        !
                        IOUNT(IPOIN)=IOUNT(IPOIN)+1
                        X=COORD(1,IPOIN)
                        Y=COORD(2,IPOIN)
                        if (ndimn.eq.2) then
                            CALL SFUN2(NNODS,SHG,X,Y)
                        else
                            z=COORD(3,IPOIN)
                            CALL SFUN3(NNODS,SHG,X,Y,z)
                        endif

                        valun(ipoin)=valun(ipoin)+dot_product(shg,cload)
                        !------------------------------------------------------------
                        !
                        !**** CALCULATE THE SMOOTHED STRESS AT SURROUNDING NODES
                        !
                        DO 2010 JELEM=1,group(igroup)%unode(jpoin)%ne_unode
                            IELEM=group(igroup)%unode(jpoin)%list(jelem)
                            DO 2050 isamp=1,nnode
                                kpoin=element(ielem)%field(1)%lnods_f(isamp)
                                if (icpoi(kpoin)/=0) goto 2050
                                IOUNT(KPOIN)=IOUNT(KPOIN)+1
                                X=COORD(1,KPOIN)
                                Y=COORD(2,KPOIN)
                                if (ndimn.eq.2) then
                                    CALL SFUN2(NNODS,SHG,X,Y)
                                else
                                    z=COORD(3,KPOIN)
                                    CALL SFUN3(NNODS,SHG,X,Y,z)
                                endif
                                valun(kpoin)=valun(kpoin)+dot_product(shg,cload)
2050                        CONTINUE
                            !
2010                    CONTINUE
                        deallocate(cmatx,cload,shg)
10                  CONTINUE
                    !
                    !**** ADVERAGING
                    where(iount/=0)
                        valun=valun/iount
                    elsewhere
                        valun=0.0
                    endwhere

                    group(igroup)%valun(:,igvar)=valun

                end do   !! for igvar

            endif           !! for(U,CO)
        endif                            !!for appear>0
    end do !! for igroup

    deallocate(valun,iount,icpoi)

    END SUBROUTINE RECOVER
    !
    SUBROUTINE  recovery(valun)
    !*********************************************************************
    !
    !*** SUPERCONVENGENT RECOVERY METHOD (ZIENKIEWICZ AND ZHU )
    !
    !********************************************************************
    character(10)fieldid,class,material,name
    integer(ink) igroup,index,order_int,nnode,nnods,ngaus,  &
        ipoin,jelem,ielem,inods,nnodt,kwji,kterm,  &
        kpoin,igaus,isamp,igvar,len,matno,jpoin,ngvar
    integer(ink),allocatable::iount(:,:),icpoi(:)
    real   (irk) x,y,z,x0,y0,z0,fvalu,eps,valun(:,:)
    real   (irk),allocatable::cmatx(:,:),cload(:), &
        a(:,:),b(:,:),shg(:)

    eps=1.e-15
    len=size(valun,DIM=1)
    allocate(iount(len,npoin),icpoi(npoin))
    valun=0.
    iount=0
    do igroup=1,ngroup

        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='U')then
            class=group(igroup)%class

            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            index=group(igroup)%index
            nnode=elkn(index)%nnode
            if (fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT'.and.nnode/=2.and.index/=22.and.index/=26)then
                order_int=elkn(index)%el_field(1)%order_intrules(1)

                nnods=nnode
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                ngvar=group(igroup)%ngvar

                icpoi=1
                do jpoin=1,group(igroup)%np_unode
                    ipoin=group(igroup)%unode(jpoin)%ipoin
                    if ((group(igroup)%unode(jpoin)%ne_unode)*ngaus<nnods)    then
                        icpoi(ipoin)=0
                    endif
                end do

                !
                do igvar=1,ngvar



                    !**** LOOP OVER ALL THE VERTEX NODES (INCLUDING BOUNDARY ONES)
                    !
                    DO 10 jPOIN=1,group(igroup)%np_unode
                        ipoin=group(igroup)%unode(jpoin)%ipoin
                        if (icpoi(ipoin).eq.0) goto 10
                        x0=coord(1,ipoin)
                        y0=coord(2,ipoin)
                        if (ndimn==3)z0=coord(3,ipoin)
                        !
5001                    CONTINUE
                        !
                        allocate(cmatx(nnods,nnods),cload(nnods),shg(nnods))
                        cmatx=0.0
                        cload=0.0
                        !
                        !**** LOOP OVER NODE RELATED ELEMENTS
                        !
                        !----------------------------------------------------------------------
                        DO 20 JELEM=1,group(igroup)%unode(jpoin)%ne_unode
                            IELEM=group(igroup)%unode(jpoin)%list(jelem)
                            DO 40 IGAUS=1,ngaus
                                x=element(ielem)%egaus(order_int)%gpcod(1,igaus)-x0
                                y=element(ielem)%egaus(order_int)%gpcod(2,igaus)-y0

                                if (ndimn.eq.3)z=element(ielem)%egaus(order_int)%gpcod(3,igaus)-z0
                                !
                                !**** SMOOTHING FUNCTION AT GAUSS POINTS
                                !
                                if (ndimn.eq.2)CALL SFUN2(NNODS,SHG,X,Y)
                                if (ndimn.eq.3)CALL SFUN3(NNODS,SHG,X,Y,Z)
                                !
                                !**** COMPUTE THE SMOOTHING EQUATION
                                !
                                DO  INODS=1,NNODS
                                    CMATX(INODS,:)=CMATX(INODS,:)+SHG(INODS)*SHG(:)
                                END DO
                                !
                                FVALU=element(ielem)%field(1)%gpvar(igvar,igaus)

                                CLOAD=CLOAD+SHG*FVALU
                                !
40                          CONTINUE
20                      CONTINUE
                        !--------------------------------------------------------------------
                        !
                        NNODT=NNODS
                        allocate(a(nnodt,nnodt),b(nnodt,1))
                        a=cmatx
                        b(:,1)=cload
                        !
                        !**** SOLVE THE EQUATION
                        !
                        KWJI=0
                        CALL GSCLO(NNODT,1,A,B,eps,KWJI,KTERM)
                        if (kwji==1) then
                            icpoi(ipoin)=0
                            deallocate(a,b)
                            goto 2011
                        endif
                        !      IF(KWJI.EQ.1) GO TO 4001
                        cload=b(:,1)
                        !
4001                    CONTINUE
                        deallocate(a,b)
                        if (KWJI.EQ.1) THEN
                            print *,' TROUBLE FOR NODE', IPOIN,'kterm=',kterm
                            NNODS=KTERM-1
                            if (ndimn.eq.2) then
                                if (nnods.eq.2) nnods=1
                                if (nnods.eq.5) nnods=4
                                if (nnods.eq.7) nnods=6
                            else
                                if (nnods.eq.3) nnods=1
                                if (nnods.eq.7) nnods=4
                                if (nnods.eq.9) nnods=8
                                if (nnods.eq.19) nnods=10
                            endif
                            deallocate(cmatx,cload,shg)
                            GO TO 5001
                        END IF
                        !
                        !**** CALCULATE THE SMOOTHED STRESS AT CORNER NODE
                        !
                        IOUNT(igvar,IPOIN)=IOUNT(igvar,IPOIN)+1

                        valun(igvar,ipoin)=valun(igvar,ipoin)+cload(1)
                        !------------------------------------------------------------
                        !
                        !**** CALCULATE THE SMOOTHED STRESS AT SURROUNDING NODES
                        !
                        DO 2010 JELEM=1,group(igroup)%unode(jpoin)%ne_unode
                            IELEM=group(igroup)%unode(jpoin)%list(jelem)
                            DO 2050 isamp=1,nnode
                                kpoin=element(ielem)%field(1)%lnods_f(isamp)
                                if (icpoi(kpoin)/=0) goto 2050
                                IOUNT(igvar,KPOIN)=IOUNT(igvar,KPOIN)+1
                                X=COORD(1,KPOIN)-x0
                                Y=COORD(2,KPOIN)-y0
                                if (ndimn.eq.2) then
                                    CALL SFUN2(NNODS,SHG,X,Y)
                                else
                                    z=COORD(3,KPOIN)-z0
                                    CALL SFUN3(NNODS,SHG,X,Y,z)
                                endif
                                valun(igvar,kpoin)=valun(igvar,kpoin)+dot_product(shg,cload)
2050                        CONTINUE
                            !
2010                    CONTINUE
2011                    continue
                        if (allocated(cmatx))deallocate(cmatx)
                        if (allocated(cload))deallocate(cload)
                        if (allocated(shg)   )deallocate(shg)
10                  continue
                    !
                    !**** ADVERAGING


                end do   !! for igvar

            endif           !! for(U,CO)
        endif                            !!for appear>0
    end do !! for igroup

    do igvar=1,len
        do ipoin=1,npoin
            if (iount(igvar,ipoin)/=0)valun(igvar,ipoin)=valun(igvar,ipoin)/iount(igvar,ipoin)
        enddo
    end do
    deallocate(iount,icpoi)

    END SUBROUTINE RECOVERy
    !
    SUBROUTINE RECOVERX (igroup,name,valun)
    !*********************************************************************
    !
    !*** SUPERCONVENGENT RECOVERY METHOD (ZIENKIEWICZ AND ZHU )
    !
    !********************************************************************
    character(5)fieldid,class,name
    integer(ink) igroup,index,order_int,nnode,nnods,ngaus,  &
        ipoin,jelem,ielem,inods,nnodt,kwji,kterm,  &
        kpoin,igaus,isamp,jpoin
    integer(ink),allocatable::iount(:),icpoi(:)
    real   (irk) x,y,z,fvalu,eps,valun(:)
    real   (irk),allocatable::cmatx(:,:),cload(:), &
        a(:,:),b(:,:),shg(:)

    eps=0.1e-6
    allocate(iount(npoin),icpoi(npoin))
    fieldid=group(igroup)%fieldid
    class=group(igroup)%class
    index=group(igroup)%index
    order_int=elkn(index)%el_field(1)%order_intrules(1)
    nnode=elkn(index)%nnode

    nnods=nnode
    ngaus=elkn(index)%ggaus(order_int)%ngaus

    icpoi=1
    do jpoin=1,group(igroup)%np_unode
        ipoin=group(igroup)%unode(jpoin)%ipoin
        if ((group(igroup)%unode(jpoin)%ne_unode)*ngaus<nnods)    then
            icpoi(ipoin)=0
        endif
    end do

    !
    !      do igvar=1,ngvar
    iount=0
    valun=0.0


    !**** LOOP OVER ALL THE VERTEX NODES (INCLUDING BOUNDARY ONES)
    !
    DO 10 jPOIN=1,group(igroup)%np_unode
        ipoin=group(igroup)%unode(jpoin)%ipoin
        if (icpoi(ipoin).eq.0) goto 10
        !
5001    CONTINUE
        !
        allocate(cmatx(nnods,nnods),cload(nnods),shg(nnods))
        cmatx=0.0
        cload=0.0
        !
        !**** LOOP OVER NODE RELATED ELEMENTS
        !
        !----------------------------------------------------------------------
        DO 20 JELEM=1,group(igroup)%unode(jpoin)%ne_unode
            IELEM=group(igroup)%unode(jpoin)%list(jelem)
            DO 40 IGAUS=1,ngaus
                x=element(ielem)%egaus(order_int)%gpcod(1,igaus)
                y=element(ielem)%egaus(order_int)%gpcod(2,igaus)

                if (ndimn.eq.3)z=element(ielem)%egaus(order_int)%gpcod(3,igaus)
                !
                !**** SMOOTHING FUNCTION AT GAUSS POINTS
                !
                if (ndimn.eq.2)CALL SFUN2(NNODS,SHG,X,Y)
                if (ndimn.eq.3)CALL SFUN3(NNODS,SHG,X,Y,Z)
                !
                !**** COMPUTE THE SMOOTHING EQUATION
                !
                DO  INODS=1,NNODS
                    CMATX(INODS,:)=CMATX(INODS,:)+SHG(INODS)*SHG(:)
                END DO
                !
                if (name=='EPRES') then
                    FVALU=element(ielem)%egaus(order_int)%vdval(5,igaus)
                else if(name=='SATUR') then
                    FVALU=element(ielem)%egaus(order_int)%SATUR(igaus)
                endif

                CLOAD=CLOAD+SHG*FVALU
                !
40          CONTINUE
20      CONTINUE
        !--------------------------------------------------------------------
        !
        NNODT=NNODS
        allocate(a(nnodt,nnodt),b(nnodt,1))
        a=cmatx
        b(:,1)=cload
        !
        !**** SOLVE THE EQUATION
        !
        KWJI=0
        CALL GSCLO(NNODT,1,A,B,eps,KWJI,KTERM)
        if (KWJI.EQ.1) GO TO 4001
        cload=b(:,1)
        !
4001    CONTINUE
        deallocate(a,b)
        if (KWJI.EQ.1) THEN
            !    write(36,*)' TROUBLE FOR NODE', IPOIN
            NNODS=KTERM-1
            if (ndimn.eq.2) then
                if (nnods.eq.2) nnods=1
                if (nnods.eq.5) nnods=4
                if (nnods.eq.7) nnods=6
            else
                if (nnods.eq.3) nnods=1
                if (nnods.eq.7) nnods=4
                if (nnods.eq.9) nnods=8
                if (nnods.eq.19) nnods=10
            endif
            deallocate(cmatx,cload,shg)
            GO TO 5001
        END IF
        !
        !**** CALCULATE THE SMOOTHED STRESS AT CORNER NODE
        !
        IOUNT(IPOIN)=IOUNT(IPOIN)+1
        X=COORD(1,IPOIN)
        Y=COORD(2,IPOIN)
        if (ndimn.eq.2) then
            CALL SFUN2(NNODS,SHG,X,Y)
        else
            z=COORD(3,IPOIN)
            CALL SFUN3(NNODS,SHG,X,Y,z)
        endif

        valun(ipoin)=valun(ipoin)+dot_product(shg,cload)
        !------------------------------------------------------------
        !
        !**** CALCULATE THE SMOOTHED STRESS AT SURROUNDING NODES
        !
        DO 2010 JELEM=1,group(igroup)%unode(jpoin)%ne_unode
            IELEM=group(igroup)%unode(jpoin)%list(jelem)
            DO 2050 isamp=1,nnode
                kpoin=element(ielem)%field(1)%lnods_f(isamp)
                if (icpoi(kpoin)/=0) goto 2050
                IOUNT(KPOIN)=IOUNT(KPOIN)+1
                X=COORD(1,KPOIN)
                Y=COORD(2,KPOIN)
                if (ndimn.eq.2) then
                    CALL SFUN2(NNODS,SHG,X,Y)
                else
                    z=COORD(3,KPOIN)
                    CALL SFUN3(NNODS,SHG,X,Y,z)
                endif
                valun(kpoin)=valun(kpoin)+dot_product(shg,cload)
2050        CONTINUE
            !
2010    CONTINUE
        deallocate(cmatx,cload,shg)
10  CONTINUE
    !
    !**** ADVERAGING
    where(iount/=0)
        valun=valun/iount
    elsewhere
        valun=0.0
    endwhere


    deallocate(iount,icpoi)

    END SUBROUTINE RECOVERx
    !
    SUBROUTINE  average(valun)
    !*********************************************************************
    !
    !*** SUPERCONVENGENT RECOVERY METHOD (ZIENKIEWICZ AND ZHU )
    !
    !********************************************************************
    character(10)fieldid,class,material,name
    integer(ink) igroup,index,order_int,ngaus,  &
        ipoin,jelem,ielem,igvar,len,matno,nnode,ngvar
    integer(ink),allocatable::iount(:,:)
    real   (irk)fvalu,valun(:,:)

    len=size(valun,DIM=1)
    allocate(iount(len,npoin))
    valun=0.
    iount=0
    do igroup=1,ngroup

        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='U')then
            class=group(igroup)%class

            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            index=group(igroup)%index
            nnode=elkn(index)%nnode
            if (fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT'.and.nnode/=2.and.index/=22.and.index/=26)then
                order_int=elkn(index)%el_field(1)%order_intrules(1)

                ngaus=elkn(index)%ggaus(order_int)%ngaus
                ngvar=group(igroup)%ngvar
                !
                do igvar=1,ngvar



                    !**** LOOP OVER ALL THE VERTEX NODES (INCLUDING BOUNDARY ONES)
                    !
                    DO 10 jPOIN=1,group(igroup)%np_unode
                        ipoin=group(igroup)%unode(jpoin)%ipoin

                        !
                        !**** LOOP OVER NODE RELATED ELEMENTS
                        !
                        !----------------------------------------------------------------------
                        DO 20 JELEM=1,group(igroup)%unode(jpoin)%ne_unode
                            IELEM=group(igroup)%unode(jpoin)%list(jelem)
                            FVALU=sum(element(ielem)%field(1)%gpvar(igvar,1:ngaus))/ngaus

                            IOUNT(igvar,IPOIN)=IOUNT(igvar,IPOIN)+1

                            valun(igvar,ipoin)=valun(igvar,ipoin)+fvalu
20                      CONTINUE

10                  continue
                    !
                    !**** ADVERAGING


                end do   !! for igvar

            endif           !! for(U,CO)
        endif                            !!for appear>0
    end do !! for igroup

    do igvar=1,len
        do ipoin=1,npoin
            if (iount(igvar,ipoin)/=0)valun(igvar,ipoin)=valun(igvar,ipoin)/iount(igvar,ipoin)
        enddo
    end do
    deallocate(iount)

    END SUBROUTINE average

    SUBROUTINE  average_aera0(valun)
    !*********************************************************************
    !
    !*** by aera weighting average (only for Q4 and B8) elements
    !
    !********************************************************************
    character(10)fieldid,class,material,name
    integer(ink) igroup,index,order_int,ngaus,  &
        ipoin,ielem,matno,nnode,ielgroup,ngvar
    integer(ink), pointer::lnods(:)
    real   (irk),allocatable::aera(:)
    real   (irk) djacb,valun(:,:)

    allocate(aera(npoin))
    valun=0.
    aera=0.
    do igroup=1,ngroup

        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='U')then
            class=group(igroup)%class

            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            index=group(igroup)%index
            nnode=elkn(index)%nnode
            if (fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT'.and.nnode/=2.and.(index==5.or.index==9))then
                order_int=elkn(index)%el_field(1)%order_intrules(1)

                ngaus=elkn(index)%ggaus(order_int)%ngaus
                ngvar=group(igroup)%ngvar
                !
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    do inode=1,nnode
                        ipoin=lnods(inode)
                        djacb=element(ielem)%egaus(order_int)%djacb(inode)
                        valun(1:ngvar,ipoin)=valun(1:ngvar,ipoin)+   &
                            djacb*element(ielem)%field(1)%gpvar(1:ngvar,inode)
                        aera(ipoin)=aera(ipoin)+djacb
                    end do
                    nullify(lnods)
                end do
            endif           !! for(U,CO)
        endif                            !!for appear>0
    end do !! for igroup

    do ipoin=1,npoin
        if (abs(aera(ipoin))>1.e-8)  &
            valun(:,ipoin)=valun(:,ipoin)/aera(ipoin)
    enddo

    deallocate(aera)

    END SUBROUTINE average_aera0

    SUBROUTINE  average_aera(valun)
    !*********************************************************************
    !
    !*** by aera weighting average (only for Q4 and B8) elements
    !
    !********************************************************************
    character(10)fieldid,class,material,name
    integer(ink) igroup,index,order_int,ngaus,ipoin,ielem,matno,nnode,ielgroup,nstre,iaver,iaver_appear,ngvar,igvar
    integer(ink), pointer::lnods(:)
    real   (irk),allocatable::aera(:)
    real   (irk) fvalu,a,b,c,d,djacb,valun(:,:),elcod_local,thick
    real   (irk),allocatable::trs(:,:),stres(:)

    if (ndimn==2)allocate(trs(4,4))
    if (ndimn==3)allocate(trs(8,8))
    a=(5.+3.*sqrt(3.))/4.
    b=-(sqrt(3.)+1.)/4.
    c=(sqrt(3.)-1.)/4.
    d=(5.-3.*sqrt(3.))/4.
    if (ndimn==3)then
        trs(1,1)=a;trs(1,2)=b;trs(1,3)=c;trs(1,4)=b;trs(1,5)=b;trs(1,6)=c;trs(1,7)=d;trs(1,8)=c
        trs(2,1)=b;trs(2,2)=a;trs(2,3)=b;trs(2,4)=c;trs(2,5)=c;trs(2,6)=b;trs(2,7)=c;trs(2,8)=d
        trs(3,1)=c;trs(3,2)=b;trs(3,3)=a;trs(3,4)=b;trs(3,5)=d;trs(3,6)=c;trs(3,7)=b;trs(3,8)=c
        trs(4,1)=b;trs(4,2)=c;trs(4,3)=b;trs(4,4)=a;trs(4,5)=c;trs(4,6)=d;trs(4,7)=c;trs(4,8)=b
        trs(5,1)=b;trs(5,2)=c;trs(5,3)=d;trs(5,4)=c;trs(5,5)=a;trs(5,6)=b;trs(5,7)=c;trs(5,8)=b
        trs(6,1)=c;trs(6,2)=b;trs(6,3)=c;trs(6,4)=d;trs(6,5)=b;trs(6,6)=a;trs(6,7)=b;trs(6,8)=c
        trs(7,1)=d;trs(7,2)=c;trs(7,3)=b;trs(7,4)=c;trs(7,5)=c;trs(7,6)=b;trs(7,7)=a;trs(7,8)=b
        trs(8,1)=c;trs(8,2)=d;trs(8,3)=c;trs(8,4)=b;trs(8,5)=b;trs(8,6)=c;trs(8,7)=b;trs(8,8)=a
    endif
    !     call householder(trs,unit,trsi) !3
    !    write(7,*)

    allocate(aera(npoin))
    valun=0.
    aera=0.
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

            thick=0.   !20200205
            if (index==22.or.index==26)thick=props(matno)%mechanical%solid%thickness  !20200205

            iaver_appear=average_appear(igroup)
            iaver=0
            if(iaver_appear<0.and.((elcod_local==0..or.elcod_local>=0.03).and.fieldid(1:1)=='U'.and.class=='CO'.and.material/='GOODMAN'  &
                .and.name/='CONTACT00'.and.nnode/=2.and.index/=22.and.index/=26))iaver=abs(iaver_appear) !20200205
            !.and.name/='CONTACT00'.and.nnode/=2))iaver=abs(iaver_appear)   !20200205
            if(iaver_appear>0)iaver=iaver_appear

            if(iaver/=0)then
                if(class/='CO'.or.material=='GOODMAN'.or.nnode==2.or.index==22.or.index==26.or.name=='CONTACT')STOP 'stop for iaver!!'  !20200205
                !if(class/='CO'.or.material=='GOODMAN'.or.nnode==2.or.name=='CONTACT')STOP 'stop for iaver!!'  !20200205

                order_int=elkn(index)%el_field(1)%order_intrules(1)

                ngaus=elkn(index)%ggaus(order_int)%ngaus
                ngvar=group(igroup)%ngvar
                nstre=group(igroup)%nstre
                !
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (ice0(ielem)==0)then
                        lnods=>element(ielem)%field(1)%lnods_f
                        if (nnode==8.and.ndimn==3)then
                            allocate(stres(nnode))
                            do igvar=1,ngvar
                                stres=0.
                                if (igvar<=nstre)then !zhao09
                                    if(iaver==1)stres=trs.x.element(ielem)%field(1)%gpvar(igvar,:)
                                    if(iaver==2)stres=element(ielem)%field(1)%gpvar(igvar,:)
                                else
                                    stres=element(ielem)%field(1)%gpvar(igvar,:)
                                endif
                                do inode=1,nnode
                                    ipoin=lnods(inode)
                                    valun(igvar,ipoin)=valun(igvar,ipoin)+stres(inode)
                                    if (igvar==1)aera(ipoin)=aera(ipoin)+1.
                                end do
                            end do
                            deallocate(stres)
                        else
                            do inode=1,nnode
                                ipoin=lnods(inode)
                                aera(ipoin)=aera(ipoin)+1.
                                do igvar=1,ngvar
                                    fvalu=sum(element(ielem)%field(1)%gpvar(igvar,:))
                                    !if(index==22.and.(igvar>3.and.igvar<=6))fvalu=fvalu*thick  !20200205
                                    fvalu=fvalu/ngaus
                                    valun(igvar,ipoin)=valun(igvar,ipoin)+fvalu
                                end do
                            end do
                        endif
                        nullify(lnods)
                    endif
                end do

                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                if (nelem1>0)then
                    DO ielgroup = 1,group1(igroup)%nelgroup
                        ielem = group1(igroup)%list(ielgroup)
                        if (jce1(ielem)==0)then
                            lnods=>element1(ielem)%field(1)%lnods_f
                            if (nnode==8.and.ndimn==3)then
                                allocate(stres(nnode))
                                do igvar=1,ngvar
                                    stres=0.
                                    stres=trs.x.element1(ielem)%field(1)%gpvar(igvar,:)

                                    do inode=1,nnode
                                        ipoin=lnods(inode)
                                        valun(igvar,ipoin)=valun(igvar,ipoin)+stres(inode)
                                        if (igvar==1)aera(ipoin)=aera(ipoin)+1.
                                    end do
                                end do
                                deallocate(stres)
                            else
                                do inode=1,nnode
                                    ipoin=lnods(inode)
                                    aera(ipoin)=aera(ipoin)+1.
                                    do igvar=1,ngvar
                                        fvalu=sum(element1(ielem)%field(1)%gpvar(igvar,:))
                                        fvalu=fvalu/ngaus
                                        valun(igvar,ipoin)=valun(igvar,ipoin)+fvalu
                                    end do
                                end do
                            endif
                            nullify(lnods)
                        endif
                    end do
                endif
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                if (nelem2>0)then
                    DO ielgroup = 1,group2(igroup)%nelgroup
                        ielem = group2(igroup)%list(ielgroup)
                        lnods=>element2(ielem)%field(1)%lnods_f
                        if (nnode==8.and.ndimn==3)then
                            allocate(stres(nnode))
                            do igvar=1,ngvar
                                stres=0.
                                stres=trs.x.element2(ielem)%field(1)%gpvar(igvar,:)

                                do inode=1,nnode
                                    ipoin=lnods(inode)
                                    valun(igvar,ipoin)=valun(igvar,ipoin)+stres(inode)
                                    if (igvar==1)aera(ipoin)=aera(ipoin)+1.
                                end do
                            end do
                            deallocate(stres)
                        else
                            do inode=1,nnode
                                ipoin=lnods(inode)
                                aera(ipoin)=aera(ipoin)+1.
                                do igvar=1,ngvar
                                    fvalu=sum(element2(ielem)%field(1)%gpvar(igvar,:))
                                    fvalu=fvalu/ngaus
                                    valun(igvar,ipoin)=valun(igvar,ipoin)+fvalu
                                end do
                            end do
                        endif
                        nullify(lnods)
                    end do
                endif
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            endif           !! for(U,CO)
        endif                            !!for appear>0
    end do !! for igroup

    do ipoin=1,npoin
        if (abs(aera(ipoin))>1.e-8)  &
            valun(:,ipoin)=valun(:,ipoin)/aera(ipoin)
    enddo

    deallocate(aera)
    if (ndimn==3)deallocate(trs)

    END SUBROUTINE average_aera
    !**************************************
    SUBROUTINE  average_strain(valun)
    !*********************************************************************
    !
    !*** by aera weighting average (only for Q4 and B8) elements
    !
    !********************************************************************
    character(10)fieldid,class,material,name
    integer(ink) igroup,index,order_int,ngaus,  &
        ipoin,ielem,matno,nnode,ielgroup,nstre,idimn,nevab
    integer(ink), pointer::lnods(:),ldofs(:)
    real   (irk),allocatable::aera(:)
    real   (irk) valun(:,:),elcod_local,tstran
    real   (irk),allocatable::stran(:),cartd(:,:),eldis(:)

    allocate(aera(npoin))
    valun=0.
    aera=0.
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

                        do igaus=1,ngaus
                            cartd=element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                            do idimn=1,ndimn
                                stran(idimn)=0.
                                do inode=1,nnode
                                    stran(idimn)=stran(idimn)+cartd(idimn,inode)*eldis(ndimn*(inode-1)+idimn)
                                end do
                            end do
                            tstran=sqrt(sum(stran(1:ndimn)**2))

                            ipoin=lnods(igaus)
                            valun(1,ipoin)=valun(1,ipoin)+tstran
                            aera(ipoin)=aera(ipoin)+1.
                        end do
                        nullify(lnods,ldofs)
                    endif
                end do

                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                if (nelem1>0)then
                    DO ielgroup = 1,group1(igroup)%nelgroup
                        ielem = group1(igroup)%list(ielgroup)
                        if (jce1(ielem)==0)then
                            lnods=>element1(ielem)%field(1)%lnods_f
                            ldofs=>element1(ielem)%field(1)%ldofs_f
                            eldis = result_zero(ldofs)

                            do igaus=1,ngaus
                                cartd=element1(ielem)%egaus(order_int)%cartd(:,:,igaus)
                                do idimn=1,ndimn
                                    stran(idimn)=0.
                                    do inode=1,nnode
                                        stran(idimn)=stran(idimn)+cartd(idimn,inode)*eldis(ndimn*(inode-1)+idimn)
                                    end do
                                end do
                                tstran=sqrt(sum(stran(1:ndimn)**2))

                                ipoin=lnods(igaus)
                                valun(1,ipoin)=valun(1,ipoin)+tstran
                                aera(ipoin)=aera(ipoin)+1.
                            end do
                            nullify(lnods,ldofs)
                        endif
                    end do
                endif
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                if (nelem2>0)then
                    DO ielgroup = 1,group2(igroup)%nelgroup
                        ielem = group2(igroup)%list(ielgroup)
                        lnods=>element2(ielem)%field(1)%lnods_f
                        ldofs=>element2(ielem)%field(1)%ldofs_f
                        eldis = result_zero(ldofs)

                        do igaus=1,ngaus
                            cartd=element2(ielem)%egaus(order_int)%cartd(:,:,igaus)
                            do idimn=1,ndimn
                                stran(idimn)=0.
                                do inode=1,nnode
                                    stran(idimn)=stran(idimn)+cartd(idimn,inode)*eldis(ndimn*(inode-1)+idimn)
                                end do
                            end do
                            tstran=sqrt(sum(stran(1:ndimn)**2))

                            ipoin=lnods(igaus)
                            valun(1,ipoin)=valun(1,ipoin)+tstran
                            aera(ipoin)=aera(ipoin)+1.
                        end do
                        nullify(lnods,ldofs)
                    end do
                endif

                deallocate (stran,cartd,eldis)
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            endif           !! for(U,CO)
        endif                            !!for appear>0
    end do !! for igroup

    do ipoin=1,npoin
        if (abs(aera(ipoin))>1.e-8)  &
            valun(1,ipoin)=valun(1,ipoin)/aera(ipoin)
    enddo

    deallocate(aera)

    END SUBROUTINE average_strain
    !**************************************

    SUBROUTINE  average_mcjoint(valun)
    !*********************************************************************
    !
    !*** SUPERCONVENGENT RECOVERY METHOD (ZIENKIEWICZ AND ZHU )
    !
    !********************************************************************
    character(10)fieldid
    character(20)material,criteria
    integer(ink) igroup,index,order_int,ngaus,ielgroup,  &
        ielem,igvar,matno,nnode
    integer(ink),allocatable::iount(:),icmatno(:)
    integer(ink),pointer::lnods(:)
    real   (irk) fvalu,valun(:,:)

    ALLOCATE(IOUNT(NPOIN),icmatno(ngroup*2))
    IOUNT=0
    icmatno=0
    valun=0
    do igroup=1,ngroup
        matno = group(igroup)%matno
        fieldid=group(igroup)%fieldid
        if(fieldid(1:1)/='U')cycle
        material=props(matno)%mechanical%solid%material
        if (material=='CLASSICALEP') then
            criteria=props(matno)%mechanical%solid%classicalEP%criteria
            if (criteria=='MCJOINT') then   !!new
                icmatno(matno)=1
            endif
        endif
    end do
    do igroup=1,ngroup

        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='U')then
            matno = group(igroup)%matno

            if (icmatno(matno)==1) then
                index=group(igroup)%index
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                !

                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=>element(ielem)%field(1)%lnods_f
                    IOUNT(lnods)=IOUNT(lnods)+1
                    do igvar=1,2
                        FVALU=sum(element(ielem)%field(1)%ntstress(igvar,1:ngaus))/ngaus
                        valun(igvar,lnods)=valun(igvar,lnods)+fvalu
                    end do   !! for igvar
                    nullify(lnods)
                end do
                !
                !**** ADVERAGING



            endif  !for matno
        endif                            !!for appear>0
    end do !! for igroup

    do igvar=1,2
        do ipoin=1,npoin
            if (iount(ipoin)/=0)valun(igvar,ipoin)=valun(igvar,ipoin)/iount(ipoin)
        enddo
    end do
    deallocate(iount,icmatno)

    END SUBROUTINE average_mcjoint
    !


    SUBROUTINE SFUN2(NNODS,SHG,X,Y)
    !********************************************************************
    !
    !***  SMOOTHING FUNCTION FOR LOCAL L2 PROJECTION
    !
    !********************************************************************
    integer(ink) nnods
    real   (irk) x,y,shg(:)

    !
    !**** LINEAR (3)
    !
    SHG(1)=1.0D0
    SHG(2)=X
    SHG(3)=Y
    if (NNODS.LE.3) return
    !
    !**** BILINEAR (4)
    !
    SHG(4)=X*Y
    if (NNODS.LE.4) return
    !
    !**** QUADRATIC (6)
    !
    SHG(5)=X*X
    SHG(6)=Y*Y
    if (NNODS.LE.6) return
    !
    !**** QUADRATIC (8)
    !
    SHG(7)=SHG(5)*Y
    SHG(8)=SHG(6)*X
    if (NNODS.LE.8) return
    !
    !**** BIQUADRATIC (9)
    !
    SHG(9)=SHG(5)*SHG(6)
    END SUBROUTINE SFUN2
    !
    SUBROUTINE SFUN3(NNODS,SHG,X,Y,Z)
    !********************************************************************
    !
    !***  SMOOTHING FUNCTION FOR LOCAL L2 PROJECTION
    !
    !********************************************************************
    integer(ink) nnods
    real   (irk) x,y,z,shg(:)

    !
    !**** LINEAR (4)
    !
    SHG(1)=1.0D0
    SHG(2)=X
    SHG(3)=Y
    SHG(4)=Z
    if (NNODS.LE.4) return
    !
    !**** BILINEAR (8)
    !
    SHG(5)=X*Y
    SHG(6)=X*Z
    SHG(7)=Y*Z
    SHG(8)=X*Y*Z
    if (NNODS.LE.8) return
    !
    !**** QUADRATIC (10)
    !
    SHG(8)=X*X
    SHG(9)=Y*Y
    SHG(10)=Z*Z
    if (NNODS.LE.10) return
    !
    !**** QUADRATIC (20)
    !
    SHG(11)=X*Y*Z
    SHG(12)=X*X*Y
    SHG(13)=X*X*Z
    SHG(14)=X*Y*Y
    SHG(15)=X*Z*Z
    SHG(16)=Z*Z*Y
    SHG(17)=Y*Y*Z
    SHG(18)=X*X*Y*Z
    SHG(19)=X*Y*Y*Z
    SHG(20)=X*Y*Z*Z
    END SUBROUTINE SFUN3
    !
    SUBROUTINE GSCLO(N,M,A,B,EP,KWJI,KTERM)
    !*******************************************************************
    !
    !***  GAUSS ELIMINATION SOLVING EQUATION
    !
    !*******************************************************************
    INTEGER(INK) N,M,KWJI,KTERM
    REAL   (IRK) EP,A(:,:),B(:,:)
    integer(ink) k,i,io,j,im,in,i1
    real   (irk) p,t
    !
    DO 10 K=1,N
        P=0.00
        DO 20 I=K,N
            if (ABS(A(I,K)).LE.ABS(P)) GO TO 20
            P=A(I,K)
            IO=I
20      CONTINUE
        if (ABS(P)-EP) 200,200,100
200     KWJI=1
        !    PRINT *,' DIANGONAL TERM EQUAL ZERO. TROUBLE IN GSCLO'
        !    PRINT *,' K=', K
        KTERM=K
        RETURN
100     IF(IO.EQ.K) GO TO 300
        DO 30 J=K,N
            T=A(K,J)
            A(K,J)=A(IO,J)
30      A(IO,J)=T
        DO 50 IM=1,M
            T=B(K,IM)
            B(K,IM)=B(IO,IM)
50      B(IO,IM)=T
300     P=1.00/P
        IN=N-1
        IM=M-1
        if (K.EQ.N) GO TO 600
        DO 40 J=K,IN
            A(K,J+1)=A(K,J+1)*P
            DO 40 I=K,IN
40      A(I+1,J+1)=A(I+1,J+1)-A(I+1,K)*A(K,J+1)
600     DO 70 I=1,M
70      B(K,I)=B(K,I)*P
        if (K.EQ.N) GO TO 400
        DO 10 J=K,IN
            DO 10 I=1,M
10  B(J+1,I)=B(J+1,I)-B(K,1)*A(J+1,K)
400 DO 60 I1=2,N
        I=N-I1+1
        DO 60 J=I,IN
            DO 60 K=1,M
60  B(I,K)=B(I,K)-A(I,J+1)*B(J+1,K)
    KWJI=0
    END SUBROUTINE GSCLO

    subroutine stresmr ( stemp, strem, rr)
    !
    !      obtain the main strain or stress and corresponding directions
    !
    integer(ink) im,i1,i2,i
    real   (irk) devia(6), stemp(:), strem(:), rr(:,:),fj
    real   (irk) root3,pei,smean,varj2,varj3,steff,sint3,theta
    real   (irk) a1,a2,a

    root3 = sqrt(3.00)
    pei   = 3.14159

    smean=(stemp(1)+stemp(2)+stemp(3))/3.0

    devia(1)=stemp(1)-smean
    devia(2)=stemp(2)-smean
    devia(3)=stemp(3)-smean
    devia(4)=stemp(4)
    devia(5)=stemp(5)
    devia(6)=stemp(6)

    varj2 = devia(4)*devia(4) + devia(5)*devia(5) +           &
        devia(6)*devia(6)+                          &
        0.5 * ( devia(1)*devia(1) + devia(2)*devia(2) +   &
        devia(3)*devia(3) )
    varj3 =    devia(1)*devia(2)*devia(3) +                &
        2.*devia(4)*devia(5)*devia(6) -               &
        devia(1)*devia(5)*devia(5) -               &
        devia(2)*devia(6)*devia(6) -               &
        devia(3)*devia(4)*devia(4)
    steff=sqrt(varj2)
    if  (steff.ne.0.0)  then
        sint3=-3.0*root3*varj3/(2.0*varj2*steff)
        if (sint3.gt.1.0) sint3=1.0
    ELSE
        sint3=0.0
    endif
    if (sint3.lt.-1.0) sint3=-1.0
    if (sint3.gt. 1.0) sint3= 1.0
    theta=asin(sint3)/3.0

    strem(1)=2.*steff/root3*sin(theta+2*pei/3.)+smean
    strem(2)=2.*steff/root3*sin(theta         )+smean
    strem(3)=2.*steff/root3*sin(theta+4*pei/3.)+smean
    !      write(*,*)'main stress(1-3)=',(strem(j),j=1,3)

    do 10 im=1,3
        do    i=1,3
            rr(im,i)=0.
        end do
        do i=1,3
            if (abs(strem(im)-stemp(i)).lt.1.e-10) then
                rr(im,i)=1.
                goto 10
            end if
        end do
        do 20 i=1,3
            i1=i+1
            i2=i+2
            if (i1.gt.3)i1=i1-3
            if (i2.gt.3)i2=i2-3
            fj=stemp(3+i2)*(stemp(i1)-strem(im))-stemp(3+i1)*stemp(3+i)
            if (abs(fj).ge.1.e-10) then
                a1=(stemp(i)-strem(im))*stemp(3+i1)-stemp(3+i)*stemp(3+i2)
                a2=stemp(3+i)**2-(stemp(i1)-strem(im))*(stemp(i)-strem(im))
                a1=a1/fj
                a2=a2/fj
                a=1.+a1*a1+a2*a2
                a=1./sqrt(a)
                a1=a1*a
                a2=a2*a
                rr(im,i)= a
                rr(im,i1)=a1
                rr(im,i2)=a2
                go to 30
            end if
20      continue
30      continue
10  continue
    return
    end subroutine stresmr

    subroutine gbmatx (SPtype, nnode, bmatx, cartd, gpcod, shape)

    !      ------  Obtain B matrix
    character(10) SPtype
    integer(ink) nnode,inode,lgash,mgash,ngash
    real(irk) bmatx(:,:), cartd(:,:), gpcod(:),shape(:)

    !      ------ 1D,  Plane stress, plane strain and axial symmetry

    if  (ndimn==1)  then              !   -----  1 D elements
        bmatx(1,1)=cartd(1,1)
        bmatx(1,2)=cartd(1,2)
        return

    else if (ndimn==2) then

        ngash=0
        DO inode=1,nnode
            mgash=ngash+1
            ngash=mgash+1
            bmatx(1,mgash)=cartd(1,inode)
            bmatx(1,ngash)=0.0
            bmatx(2,mgash)=0.0
            bmatx(2,ngash)=cartd(2,inode)
            bmatx(3,mgash)=cartd(2,inode)
            bmatx(3,ngash)=cartd(1,inode)
            bmatx(4,mgash)=0.0
            bmatx(4,ngash)=0.0
            if  (SPtype=='AX') then
                bmatx(4,mgash)=shape(inode)/gpcod(1)
                bmatx(4,ngash)=0.0
            endif

        enddo
        return
    endif

    !      ------  3D solid elements

    if  (ndimn==3) then

        ngash=0
        DO inode=1,nnode
            lgash=ngash+1
            mgash=lgash+1
            ngash=mgash+1
            bmatx(1,lgash) = cartd(1,inode)
            bmatx(1,mgash) = 0.0
            bmatx(1,ngash) = 0.0
            bmatx(2,lgash) = 0.0
            bmatx(2,mgash) = cartd(2,inode)
            bmatx(2,ngash) = 0.0
            bmatx(3,lgash) = 0.0
            bmatx(3,mgash) = 0.0
            bmatx(3,ngash) = cartd(3,inode)
            bmatx(4,lgash) = cartd(2,inode)
            bmatx(4,mgash) = cartd(1,inode)
            bmatx(4,ngash) = 0.0
            bmatx(5,lgash) = 0.0
            bmatx(5,mgash) = cartd(3,inode)
            bmatx(5,ngash) = cartd(2,inode)
            bmatx(6,lgash) = cartd(3,inode)
            bmatx(6,mgash) = 0.0
            bmatx(6,ngash) = cartd(1,inode)
        enddo
        return

    endif

    end  subroutine gbmatx

    SUBROUTINE gpq (STEMP,smean,steff,eta)

    integer(ink) i,nstre
    real   (irk) stemp(:),steff,smean,varj2,eta
    real   (irk) varj3,rj23,sint3
    real   (irk),allocatable::devia(:)

    nstre=size(stemp)
    allocate(devia(nstre))

    smean=sum(stemp(1:ndimn))
    if(ndimn.eq.2.and.nstre==4)smean=smean+stemp(4)

    SMEAN=smean/3.0_irk

    varj2=0.0_irk

    do i=1,ndimn
        DEVIA(i)=STEMP(i)-SMEAN
        varj2=varj2+.5*devia(i)**2
    end do

    do i=ndimn+1,3*(ndimn-1)
        DEVIA(i)=STEMP(i)
        varj2=varj2+devia(i)**2
    end do

    if(ndimn.eq.2.and.nstre==4)DEVIA(4)=STEMP(4)-SMEAN
    if(ndimn.eq.2.and.nstre==4)varj2=varj2+.5*devia(4)**2

    STEFF=SQRT(3*VARJ2)

    varj3=0.
    varj3=devia(4)*(devia(4)*devia(4)-varj2)

    rj23=sqrt(varj2)**3

    if(rj23.ge.1.e-20) then
        sint3=-3.*sqrt(3.)*varj3/(2.*rj23)
    else
        sint3=0.
    endif
    !if(istep.gt.118.and.istep.le.122)then
    !write(7,*)'rj23=',rj23,'sint3=',sint3
    !write(7,*)'stemp=',stemp
    !endif

    if(sint3.lt.-1.e-3) steff=-steff  !2007

    !smean=abs(smean)
    eta=0.

    if(steff.ne.0.0) eta=abs(steff/smean)

    deallocate(devia)
    END SUBROUTINE gpq

    !
    END  MODULE OUTPUT
