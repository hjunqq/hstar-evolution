    module internal_force

    use variable_types
    use stiffness_matrix
    use applied_load
    use arrayutil
    use global_var
    use meshfine


    implicit none
    contains

    SUBROUTINE RESIDU_F

    character(1)field1
    character(10)SPtype,class,fieldid,special,state,state0
    character(30)material,name
    integer(ink) igroup,nrfields,ifield,ntpel,index,ic,       &
        matno,nstre,nevab,nnode,order_int,nnode_half,&
        ngaus,ielgroup,ielem,igaus,type_ecoint,      &
        nnode_p,nevab_p,pfield,inode,lnidmn,aevab,   &
        jnode,jndex,idimn,icreep,jfield,idofn,       &
        nnode_dd,nevab_dd,icr,ipoin,igroup_iblks,   &  !20201128
        uplift_ic,kind_wt !20220409
    integer(ink),pointer:: lnods(:), ldofs(:), ldofp(:)
    !********************* !ljdp 2010 ******************************
    integer(ink) type_stiff,kinit_g  !20211214
    real   (irk),allocatable::sgtot(:), devia(:), avect(:),avecq(:), dvect(:), dvecq(:)
    real   (irk)   yld, theta, steff, vj3,abeta,eps
    !********************* !ljdp 2010 ******************************

    real   (irk) e, nu, djacb, bulkt,thick,smean,dgapn,strenth,forcx,fai,sigmac,fn,ex
    real   (irk) upliftg !20220409
    real   (irk),allocatable::eldis(:), cartd(:,:),           &
        ematx(:,:),bmatx(:,:),gpcod(:), &
        shape(:),eload(:),ecmatx(:,:),  &
        phydro(:), elp(:), shapep(:),   &
        dmatx(:,:),dcmatx(:,:),eload_dd(:),eloadx(:),eload1(:),eload2(:)
    real   (irk),allocatable::stran(:), stres(:), strsg(:),    &
        veca2(:),veca3(:),eldis_dd(:),ks(:,:),ksx(:,:),ddisp(:),rotstar(:,:),unitx(:,:)
    real   (irk),pointer::rotation(:,:), gmatx(:,:),elcod(:,:),eload0(:),estifb(:,:)

    real   (irk),allocatable::trot(:,:),estifm(:,:),estif(:,:),tincr(:)
    real   (irk),allocatable::gapnod(:),nordis(:),gapgaus(:),shapecg(:,:),rot(:),sig(:),ft(:),dmatxd(:,:)
    real   (irk) aera,g,iy,iiy,iz,iiz,twist,itj,iea,dl,tincr_g,alfa
    real   (irk) factgi,ggg,a,b,c,d,l0,dgap0,dgap1,dgap,pps,strabar,tao,ftx,fcx,dx,ep !ep2010
    real   (irk) penetration_ratio,current_gap,raw_factgi,ideal_factgi  ! 新增穿透检查变量
    real   (irk) penetration_depth,initial_gap  ! 穿透深度分析变量
    real   (irk),allocatable:: stran_before(:)  ! 用于调试应变修正
    integer(ink),pointer::ldofs_t(:)

    !write(7,*)'iblks=',iblks,'iincs=',iincs,'idiv=',idiv,'istep=',istep,'iiter=',iiter
    strabar=0.
    ! determine the time dependent coefficient for assembling.
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        class = group(igroup)%class
        special= group(igroup)%special
        kinit_g= group(igroup)%kinit_g  !20211214
        type_stiff=group(igroup)%type_stiff !ljdp 2010

        !judge whether the CO-displacement field is included.
        !if(appear(igroup)>0.and.field1=='U'.and.class=='CO') then
        igroup_iblks=0   !20201128
        if(iincs==1.and.istep==1.and.(iblks==1.or.   &
            (appear_process(igroup,iblks)==1.and.appear_process(igroup,iblks-1)==0))) &
            igroup_iblks=1 !20201128

        if (appear(igroup)>0.and.field1=='U') then
            !write(chkunit,*)'igroup=',igroup
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            !find whether the u-p formulation is used, ntpel=1--yes!
            ntpel=0
            jfield=0
            do ifield=1,nrfields
                if (fieldid(ifield:ifield)=='T')then
                    jfield=ifield
                endif
                if (fieldid(ifield:ifield)=='P')then
                    ntpel=1
                    pfield=ifield
                endif
            end do
            ! get information from the group level
            index = group(igroup)%index
            matno = group(igroup)%matno
            nstre=  group(igroup)%nstre
            SPtype=    group(igroup)%SPtype
            type_ecoint=    group(igroup)%type_ecoint
            nnode = elkn(index)%el_field(1)%nnode_f
            nevab = nnode*group(igroup)%dof(1)%nfdof
            uplift_ic=group(igroup)%uplift_ic !20220409
            if (special(1:1)=='D')nnode_dd=group(igroup)%nnode_dd
            if (special(1:1)=='D')nevab_dd=nnode_dd*ndimn
            material=props(matno)%mechanical%solid%material
            kind_wt=props(matno)%mechanical%solid%kind_wt
            if(material=='GOODMAN')nstre=ndimn

            icr=0
            if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
            name=props(matno)%name
            icreep= props(matno)%mechanical%solid%icreep
            if (material/='DUNCANCHANG'.and.material/='GOODMAN')then
                if(Bparameter/=0.and.props(matno)%mechanical%solid%ie/=0)then !20190810
                    e=xvalue(props(matno)%mechanical%solid%ie)
                else
                    e=props(matno)%mechanical%solid%e !exx !
                endif
                if(Bparameter/=0.and.props(matno)%mechanical%solid%iNu/=0)then
                    Nu=xvalue(props(matno)%mechanical%solid%iNu)
                else
                    Nu=props(matno)%mechanical%solid%Nu !uxx !
                endif  !20190810
                if (icreep.ne.0.and.icreep<=3)e=group(igroup)%educ  !20180630  20190810(看情况待修改！）
                alfa =props(matno)%mechanical%solid%alfa
                if (ntpel==1)bulkt   =e/(3.0*(1.0-2.0*nu))
            endif

            !write(chkunit,*)'igroup=',igroup,'  e=',e,'     residu_u'


            allocate (lnods(nnode),ldofs(nevab),eldis(nevab),eload(nevab))
            thick=1.
            if (ndimn==2.or.index==22.or.index==26)thick  =props(matno)%mechanical%solid%thickness
            !if(nnode==2)thick  =props(matno)%geometry%aera
            if (nnode==2.and.index/=25)thick  =props(matno)%geometry%aera !steel 2006

            !if(index.ne.20.and.index.ne.21) then ! not for beam
            if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                if (material=='GOODMAN') allocate(shape(nnode/2))
                if (material/='GOODMAN') allocate(shape(nnode))
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus = elkn(index)%ggaus(order_int)%ngaus

                if (material=='GOODMAN') then   !! for goodman element
                    jndex=1
                    if (ndimn==3.and.index==9)jndex=5  !2017/02/14
                    if (ndimn==3.and.index==23)jndex=3  !2017/02/14
                    order_int=elkn(jndex)%el_field(1)%order_intrules(1)
                    ngaus=elkn(jndex)%ggaus(order_int)%ngaus
                endif               !! for goodman element

                lnidmn=elkn(index)%ndimn
                ! allocate the arrays which will be used
                allocate (stran(nstre),stres(nstre))
                if (special(1:1)/='D')then
                    allocate (cartd(lnidmn,nnode),bmatx(nstre,nevab))
                else
                    allocate (cartd(lnidmn,nnode_dd),bmatx(nstre,nevab_dd))
                endif
                allocate (ematx(nstre,nstre),gpcod(ndimn))
                allocate (strsg(nstre))
                allocate (ecmatx(nstre,nstre),veca2(nstre),veca3(nstre))
                allocate (dmatx(nstre,nstre),dcmatx(nstre,nstre))

                allocate(devia(nstre),sgtot(nstre), avect(nstre),avecq(nstre), dvect(nstre), dvecq(nstre)) !ljdp 2010
                devia=0. ; sgtot=0. ; avect=0. ; avecq=0. ; dvect=0. ; dvecq=0.

                if (name=='CONTACT')allocate(gapgaus(ngaus))
                ! for simo & Rifai element
                if (special(1:1)=='B'.and.index/=22.and.index/=26) then
                    if (ndimn==2) then
                        if (special(2:2)=='A') aevab=2
                        if (special(2:2)=='B') aevab=4
                        if (special(2:2)=='C') aevab=7
                        if (special(2:2)=='D') aevab=11
                        if (special(2:2)=='B'.and.index==3) aevab=6
                        if (special(2:2)=='C'.and.index==3) aevab=9
                    else if(ndimn==3) then
                        if (special(2:2)=='A') aevab=3
                        if (special(2:2)=='B') aevab=9
                        if (special(2:2)=='C') aevab=24
                        if (special(2:2)=='D') aevab=30
                    endif
                    allocate (gmatx(nstre,aevab))
                endif
                ! compute the elastic matrix, De or Ds
                ematx=0.;ecmatx=0.
                if (material/='DUNCANCHANG'.and.material/='GOODMAN')then

                    if (nnode/=2) then
                        if (name=='NSTOKS') then    !!nstoks
                            do idimn=1,ndimn
                                ematx(idimn,idimn)=e*4./3.
                                ematx(idimn,idimn+1:ndimn)=-e*2/3.
                                ematx(1:(idimn-1),idimn)=-e*2/3.
                            end do

                            do idimn=ndimn+1,3*(ndimn-1)
                                ematx(idimn,idimn)=e
                            end do

                            if (ndimn==2.and.nstre==4) then
                                ematx(4,4)=e*4./3.
                                ematx(1,4)=-e*2/3.
                                ematx(2,4)=-e*2/3.
                                ematx(4,1)=-e*2/3.
                                ematx(4,2)=-e*2/3.
                            endif
                        else
                            !if (index/=22)call ecmat(SPtype,ematx,e,nu) !zhao
                            !SOLIDF  --displacement-displacement formulation for fluid-structure-interaction,
                            !        --fluid domain is also descirbed by the displacement field as done in solid domain.
                            !        --e=k=lamda(lami constant)
                            !        --there still some problem in prescibe information.
                            if (index/=22.and.index/=26.and.name/='SOLIDF')call ecmat(SPtype,ematx,e,nu) !zhao 0710
                            if (index/=22.and.index/=26.and.name=='SOLIDF')call ecmat_solidf(SPtype,ematx,e,nu) !zhao 0710
                            if (index==22)call ecmat_p4(thick,ematx,e,nu)
                            if (index==26)call ecmat_thin_film(thick,ematx,e,nu)  !20230910
                        endif
                    endif


                    if (nnode==2)ematx=e
                    ecmatx=ematx
                    if (ntpel.ne.0.and.nstre/=1) then
                        ecmatx(1:ndimn,1:ndimn)=ecmatx(1:ndimn,1:ndimn)-bulkt
                        if (ndimn==2.and.SPtype=='PE')ecmatx(4,4)=ecmatx(4,4)-bulkt
                    endif
                endif
            else if(index.eq.20.or.index.eq.21) then
                allocate(trot(nevab,nevab),estifm(nevab,nevab), &
                    estif(nevab,nevab),eload0(nevab))
                g=e/(2*(1+nu))
                Iy   =props(matno)%geometry%iy
                Iz   =props(matno)%geometry%iz
                twist=props(matno)%geometry%j
                aera =props(matno)%geometry%aera
                if (jfield/=0) allocate(tincr(nnode))
            else if (index==25)then !steel 2006
                allocate(trot(nevab,nevab),estifm(nevab,nevab), &
                    estif(nevab,nevab),eload0(nevab))
                trot=0. ; estifm=0. ; estif=0. ; eload0=0.
                icreep=props(matno)%mechanical%solid%icreep
                if(icreep/=0)then
                    strenth=props(matno)%geometry%aera !for lhg
                    fai   =props(matno)%geometry%J
                    sigmac=props(matno)%geometry%iy
                endif
            endif
            ! loop for 1:nelgroup
            DO ielgroup = 1,group(igroup)%nelgroup

                ielem = group(igroup)%list(ielgroup)

                !write(7,*)'iiter=',iiter,'ie=',ielem

                if (ice0(ielem)==1) goto 100
                if (tension_joint(ielem)==1) goto 100   !! special for hjd

                if (nnode==2.or.index==22.or.index==26)rotation=>element(ielem)%rotation
                !if(ielem==1046)then
                !    write(7,*)'ie=',ielem,'rot='
                !    write(7,*)rotation(1,:)
                !    write(7,*)rotation(2,:)
                !    write(7,*)rotation(3,:)
                ! endif


                if (ntpel==1) then
                    nnode_p = elkn(index)%el_field(pfield)%nnode_f
                    nevab_p = nnode_p*group(igroup)%dof(pfield)%nfdof
                    allocate (elp(nevab_p),shapep(nnode_p),phydro(ngaus))
                    ldofp => element(ielem)%field(pfield)%ldofs_f
                    elp    = deltafi(ldofp)
                    do igaus=1,ngaus
                        shapep = elkn(index)%shapep(:,igaus)
                        phydro(igaus)=shapep.d.elp

                    end do
                    deallocate(elp,shapep)
                    nullify(ldofp)
                end if

                lnods = element(ielem)%field(1)%lnods_f
                ldofs = element(ielem)%field(1)%ldofs_f
                !if (material=='GOODMAN'.or.material=='DUNCANCHANG'.or.material=='ELASTIC_EP')then !ep2010
                if(type_load/='LOAD2'.and.(type_nl==4.or.type_nl==8))then
                    eldis = delitfi(ldofs)

                else
                    if (meshc==1)then
                        if (appear_p(igroup)==0.and.appear(igroup)==1)then
                            eldis = result_zero(ldofs)
                        else
                            eldis = deltafi(ldofs)
                        endif
                    elseif(name=='NSTOKS')then
                        eldis = result_zero(ldofs)
                    else
                        eldis = deltafi(ldofs)
                    endif
                endif

                !write(7,*)'ie=',ielem,'eldis=',eldis

                if (name=='CONTACT') then
                    allocate(nordis(nnode),gapnod(nnode),rot(ndimn))
                    nnode_half=nnode/2
                    if (material=='GOODMAN') then
                        allocate(shapecg(nnode_half,ngaus))
                        rot=element(ielem)%rotation(ndimn,:)
                    else
                        allocate(shapecg(nnode,ngaus))
                        rot=element(ielem)%rotation(1,:)
                    endif
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
                    if (material=='GOODMAN') then
                        shapecg = elkn(jndex)%ggaus(order_int)%shape(:,:)
                    else
                        shapecg = elkn(index)%ggaus(order_int)%shape(:,:)
                    endif
                    if (material=='GOODMAN') then
                        gapgaus=transpose(shapecg).x.gapnod(1:nnode_half)
                    else
                        gapgaus=transpose(shapecg).x.gapnod
                    endif
                    deallocate(nordis,gapnod,shapecg,rot)
                endif
                if (special(1:1)=='D')then
                    allocate(eldis_dd(nevab_dd),eload_dd(nevab_dd))
                    call eldisr(ielem,nevab,nevab_dd,eldis,eldis_dd)
                    eload_dd=0.
                    !        write(7,*)'eldis_dd=',eldis_dd
                endif
                eload =0.0

                !if(special(1:1)=='B'.and.index/=22)  &
                !call updalfa(ielem,ldofs,fieldid) !! Simo & Rifai

                !if(index.ne.20.and.index.ne.21) then ! not for beam
                if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                    if (index==22.and.special=='ST')then
                        elcod=>element(ielem)%field(1)%elcod_f
                        call smat_p4 (e,nu,thick,elcod,eldis,rotation,element(ielem)%field(1)%gpvar(1:nstre,:))
                        estifb=>element(ielem)%field(1)%khandmc(1)%fstif
                        eload=estifb.x.eldis
                        nullify(elcod,estifb)
                        goto 1
                    endif

                    do igaus=1,ngaus

                        if(material=='ELASTIC_EP')then !ep2010
                            call epcurveEP(element(ielem)%field(1)%sigz(igaus),matno,ep)
                            if (index/=22.and.index/=26.and.name/='SOLIDF')call ecmat(SPtype,ematx,ep,nu) !zhao 0710
                            if (index/=22.and.index/=26.and.name=='SOLIDF')call ecmat_solidf(SPtype,ematx,ep,nu) !zhao 0710
                            ecmatx=ematx
                        endif

                        if(material=='PLANE_LOWFT')then
                            allocate(dmatxd(nstre,nstre))
                            dmatxd=element(ielem)%field(1)%dmatxd(:,:,igaus)     !20130510
                            call ecmat_change_local(dmatxd,ematx,element(ielem)%rotation)
                            deallocate(dmatxd)
                        endif


                        factgi=1.
                        dmatx=ematx;dcmatx=ecmatx
                        if (name=='CONTACT') then
                            state=element(ielem)%field(1)%state(igaus)
                            if (state=='open') then
                                element(ielem)%field(1)%gpvar(:,igaus)=0
                                element(ielem)%field(1)%gpvar(1:ndimn,igaus)=0.02
                                goto 10
                            else
                                state0=element(ielem)%field(1)%state0(igaus)
                                if (state0=='open') then
                                    ggg=gapgaus(igaus)+element(ielem)%field(1)%gapg0(igaus)
                                    !if(ggg.ge.0.) then !zhao
                                    !element(ielem)%field(1)%gpvar(:,igaus)=0.02
                                    !goto 10
                                    !else

                                    if (element(ielem)%field(1)%gapg0(igaus).ge.0.and.ggg.lt.0.) &
                                        factgi=ggg/gapgaus(igaus)
                                    if (factgi.le.0.) factgi=0.
                                    if (factgi.ge.1.) factgi=1.
                                    !endif
                                endif
                                if (material=='ELASTIC_FRICTIONLESS')then
                                    rotation=>element(ielem)%rotation
                                    call dmatxf_change(e,dcmatx,rotation)
                                    nullify(rotation)
                                endif
                            endif
                        endif
                        !crack 2006
                        if (name=='CRACK') then
                            state=element(ielem)%field(1)%state(igaus)
                            if (state=='open') then
                                element(ielem)%field(1)%gpvar(:,igaus)=0
                                goto 10
                            endif
                        endif
                        !end crack 2006
                        if (name=='NORMK'.or.name=='NOLINORMK')then
                            rotation=>element(ielem)%rotation !垫层材料需要求这一下法向
                            ex=e
                            if (name=='NOLINORMK')then
                                call find_e_NOLINORMK(matno,rotation,element(ielem)%field(1)%gpvar0(1:nstre,igaus),ex) !用上一步应力求弹模
                            endif
                            call dmatxf_change(ex,dcmatx,rotation)
                            nullify(rotation)
                        endif

                        if (material/='GOODMAN') then
                            shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                            ! get djacb and cartd in the element level
                            djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                            !          if(special(1:1)/='D')djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                            !          if(special(1:1)=='D')djacb=element(ielem)%djacb_dd(igaus)
                            gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                        else
                            shape = elkn(jndex)%ggaus(order_int)%shape(:,igaus)
                            djacb=element(ielem)%aera_local(igaus)
                        endif

                        if(upliftin>0.and.iblks>=upliftin.and.uplift_ic/=0)  &
                            upliftg=uplift_node(lnods).d.shape       !20220409
                        if(upliftin==0.and.uplift_ic/=0.and.kind_wt>0)then
                            if(nrfields==1.and.element(ielem)%field(1)%isatu(igaus)>=1)then  !20220607
                                gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                                upliftg=(water_level(iblks)-gpcod(ndimn))*gravy*  &
                                    props(matno)%mechanical%solid%density_w       !20220502
                                !write(7,*)'ielem=',ielem,'igaus=',igaus,'upliftg=',upliftg
                            endif
                        endif

                        bmatx=0.0
                        if (material/='GOODMAN')then
                            if (special(1:1)/='D')cartd=element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                            if (special(1:1)=='D')cartd=element(ielem)%gmatx(:,:,igaus)
                            if (nnode/=2) then
                                ic=0
                                if (special(1:1)=='B')ic=1
                                if (special(1:1)=='C')ic=2
                                if (index==22)call gbmat_p4(ic,igaus,ielem,bmatx, cartd, shape,rotation)
                                if (index==26)call gbmat_thin_film(ic,igaus,ielem,bmatx, cartd, shape,rotation)

                                if (index/=22.and.index/=26.and.special(1:1)/='D')  &
                                    call gbmat   (SPtype, nnode, bmatx, cartd, gpcod, shape)
                                if (index/=22.and.index/=26.and.special(1:1)=='D')  &
                                    call gbmat   (SPtype, nnode_dd, bmatx, cartd, gpcod, shape)
                            else
                                do inode=1,nnode
                                    bmatx(1,(inode-1)*ndimn+1:inode*ndimn)=cartd(1,inode)*rotation(1,:)
                                end do
                                if(index==1.and.(any(listglocbeam==igroup)))then !barsteel
                                    allocate(trot(nevab,nevab))
                                    trot=0.
                                    trot(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
                                    trot(ndimn+1:ndimn*2,ndimn+1:ndimn*2)=prot(:,:,lnods(2))
                                    bmatx=matmul(bmatx,transpose(trot))
                                    deallocate(trot)
                                endif
                            endif

                        else       !! for goodman element
                            rotation=>element(ielem)%rotation
                            do inode=1,nnode/2
                                do idimn=1,ndimn
                                    bmatx(idimn,(inode-1)*ndimn+1:inode*ndimn)=-shape(inode)* &
                                        rotation(idimn,:)
                                end do
                                if (ndimn==3)then
                                    jnode=inode+nnode/2
                                else
                                    if (inode==1)jnode=4
                                    if (inode==2)jnode=3
                                endif
                                do idimn=1,ndimn
                                    bmatx(idimn,(jnode-1)*ndimn+1:jnode*ndimn)=shape(inode)* &
                                        rotation(idimn,:)
                                end do
                            end do
                            nullify(rotation)
                        endif

                        element(ielem)%field(1)%bmatx(:,:,igaus)=bmatx !20231215YL存储B矩阵
                        ! compute strain and elastic stres increment


                        if (special(1:1)/='D')stran=matmul(bmatx,eldis)
                        if (special(1:1)=='D')stran=matmul(bmatx,eldis_dd)


                        stran=stran*factgi
                        if(element(ielem)%icper==1)stran=stran-element(ielem)%strainx0(1:nstre,igaus) !20231215YL
                        ! for creep and temperature---> stran=stran-stran(creep)-stran(temp)
                        if (jfield/=0.or.icreep>=3)   &
                            stran=stran-element(ielem)%field(1)%stran0(:,igaus)   !20200227
                        if (kind_wt>0)   &
                            stran=stran-element(ielem)%field(1)%stran0_s(:,igaus)   !20220607


                        ! for simo & Rifai element
                        if (special(1:1)=='B'.and.index/=22.and.index/=26) then
                            gmatx=element(ielem)%gmatx(:,:,igaus)
                            stran=stran+(gmatx.x.element(ielem)%alfa)
                        endif
                        if (icr==2.or.icr==3.or.icr==5) & !zhao09
                            stran=stran+element(ielem)%field(1)%strain0(:,igaus)

                        !      if(ielem==560) &
                        !write(7,*)'ie=',ielem,'igaus=',igaus,'stran=',stran


                        if (ljdp/=0.and.material=='CLASSICALEP')then !ljdp 2010
                            dmatx=dcmatx
                            call deps
                            dcmatx=dmatx
                        endif

                        if (material/='DUNCANCHANG'.and.material/='GOODMAN')stres=matmul(dcmatx,stran)
                        if (nstre/=1.and.material/='GOODMAN')then
                            if (ndimn==2.and.SPtype(1:2)=='PS')  &
                                stran(4)=-(stran(1)+stran(2))*nu/(1.-nu)
                            if (ndimn==2.and.SPtype(1:2)=='PE'.and.material/='DUNCANCHANG')  &
                                STRES(4)=nu*(STRES(1)+STRES(2))+e*STRAN(4)

                            if (ntpel/=0.and.material/='DUNCANCHANG') then
                                stres(1:ndimn)=stres(1:ndimn)-phydro(igaus)
                                if (ndimn==2)stres(4)=stres(4)-phydro(igaus)
                            endif
                        endif
                        !if(ielem==560)then
                        !     write(7,*)'ie=',ielem,'igaus=',igaus,'stres=',stres,'stran=',stran,'dmatx=',dmatx
                        ! endif

                        ! compute total stres
                        if (name=='NSTOKS')then
                            element(ielem)%field(1)%gpvar(1:nstre,igaus)= stres
                            strsg=stres
                        else
                            call updstress
                            ! if(ielem==560)&
                            !write(7,*)'ie=',ielem,'igaus=',igaus,'strsg=',strsg

                        endif
                        if(upliftin>0.and.iblks>=upliftin.and.uplift_ic/=0)  &
                            strsg(1:ndimn)=strsg(1:ndimn)-upliftg  !20220409(渗透压力）
                        !if(upliftin>0.and.iblks>=upliftin.and.uplift_ic/=0.and.ielgroup==1) then
                        !      write(7,*)'ie=',ielem,'igaus=',igaus,'upliftg=',upliftg
                        !           endif

                        if(upliftin==0.and.uplift_ic/=0.and.kind_wt>0) then
                            if(element(ielem)%field(1)%isatu(igaus)>=1) &
                                strsg(1:ndimn)=strsg(1:ndimn)-upliftg  !20220502(渗透压力）
                        endif
                        !if(ielem==1.and.igaus==1) &
                        !write(7,*)'ie_residu=',ielem,'igaus=',igaus,'strsg=',strsg


                        if (index==1.and.material=='ELASTIC_SPRING')then
                            strsg=0.
                            if (element(ielem)%field(1)%state(igaus)=='CLOSE')then
                                l0=props(matno)%mechanical%solid%Elastic_Spring%l0
                                dgap0=(coord(:,lnods(2))-coord(:,lnods(1))).d.rotation(1,:)
                                dgap0=l0-dgap0
                                eldis=result_zero(ldofs)
                                dgap1=(eldis(ndimn+1:2*ndimn)-eldis(1:ndimn)).d.rotation(1,:)
                                dgap=dgap0+dgap1
                                dgap=-dgap
                                if (dgap<0.)then
                                    strsg=0.
                                else
                                    a=props(matno)%mechanical%solid%Elastic_Spring%a
                                    b=props(matno)%mechanical%solid%Elastic_Spring%b
                                    c=props(matno)%mechanical%solid%Elastic_Spring%c
                                    d=props(matno)%mechanical%solid%Elastic_Spring%d
                                    strsg=-(a+b*dgap+c*dgap**2+d*dgap**3)/thick
                                endif
                            end if
                            element(ielem)%field(1)%gpvar(1,igaus)=strsg(1)
                        endif


                        ! if kinit=2, the initial load related to initial stress is not computed
                        if (kinit_g==2)strsg=strsg-element(ielem)%stres0(:,igaus)
                        !if( ielem==1)then
                        !    write(7,*)'ie=',ielem,'igaus=',igaus
                        !    write(7,*)'strsg=',strsg
                        !    write(7,*)'stres0=',element(ielem)%stres0(:,igaus)
                        ! endif

                        ! compute the internal force
                        stres=strsg
                        if (ntpel.eq.1) then
                            pps=sum(stres(1:ndimn))
                            if (ndimn.eq.2)pps=pps+stres(4)
                            pps=pps/3.d0
                            stres(1:ndimn)=stres(1:ndimn)-pps
                            if (ndimn==2)stres(4)=stres(4)-pps
                        endif

                        if (special(1:1)/='D') &
                            eload=eload+thick*djacb*MATMUL(transpose(bmatx),stres)


                        if (special(1:1)=='D') &
                            eload_dd=eload_dd+thick*djacb*MATMUL(transpose(bmatx),stres)


                        if (name=='NSTOKS')  &   !!nstoks
                            call eload_nstoks(matno,ielem,nnode,djacb,thick,shape,cartd,eload)
                        ! for simo & Rifai element
                        if (special(1:1)=='B'.and.index/=22.and.index/=26) then
                            call residu_sr(fieldid,gmatx,igaus,ngaus,ielem,djacb,strsg)
                        endif
                        if (icreep==2)   &
                            element(ielem)%field(1)%dsig(:,igaus)=  &
                            element(ielem)%field(1)%gpvar(1:nstre,igaus)-  &
                            element(ielem)%field(1)%gpvar0(1:nstre,igaus)
10                      continue
                    end do     !!igaus
1                   continue
                else if(index.eq.20.or.index.eq.21) then
                    if(material=='STEEL_EP')e=element(ielem)%field(1)%ep  !20211125

                    trot=0.; estifm=0.0
                    if(material/='STEEL_SP')then  !20211125
                        elcod=>element(ielem)%field(1)%elcod_f
                        dl=sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))
                        iiy=e*iy/dl; iiz=e*iz/dl; itj=g*twist/dl; iea=e*aera/dl
                    endif !20211125
                    if (ndimn==2) then
                        trot(1:ndimn,1:ndimn)=rotation
                        trot(3,3)=1.
                        trot(4:5,4:5)=rotation
                        trot(6,6)=1.

                        if(material/='STEEL_SP')then  !20211125
                            estifm(1,1)=iea; estifm(1,4)=-iea; estifm(4,1)=-iea; estifm(4,4)=iea
                            estifm(2,2)=12*iiy/dl**2;  estifm(2,3)=-6*iiy/dl
                            estifm(2,5)=-12*iiy/dl**2; estifm(2,6)=-6*iiy/dl
                            estifm(3,2)=-6*iiy/dl;     estifm(3,3)=4*iiy
                            estifm(3,5)= 6*iiy/dl;     estifm(3,6)=2*iiy

                            estifm(5,2)=-12*iiy/dl**2; estifm(5,3)=6*iiy/dl
                            estifm(5,5)= 12*iiy/dl**2; estifm(5,6)=6*iiy/dl
                            estifm(6,2)=-6*iiy/dl;     estifm(6,3)=2*iiy
                            estifm(6,5)= 6*iiy/dl;     estifm(6,6)=4*iiy
                        else !20211125
                            do idimn=1,3*(ndimn-1)
                                estifm(idimn,idimn)=element(ielem)%field(1)%kdiag(idimn)
                                estifm(idimn,idimn+3)=-element(ielem)%field(1)%kdiag(idimn)
                                estifm(idimn+3,idimn+3)=element(ielem)%field(1)%kdiag(idimn)
                                estifm(idimn+3,idimn)=-element(ielem)%field(1)%kdiag(idimn)
                            enddo
                        endif !20211125

                    else if(ndimn==3) then
                        trot(1:3,1:3)=rotation; trot(4:6,4:6)=rotation
                        trot(7:9,7:9)=rotation; trot(10:12,10:12)=rotation

                        if(material/='STEEL_SP')then  !20211125
                            estifm(1,1)=iea; estifm(1,7)=-iea; estifm(7,1)=-iea; estifm(7,7)=iea
                            estifm(4,4)=itj; estifm(4,10)=-itj; estifm(10,4)=-itj; estifm(10,10)=itj

                            estifm(2,2)= 12*iiz/dl**2;  estifm(2, 6)= 6*iiz/dl
                            estifm(2,8)=-12*iiz/dl**2;  estifm(2,12)= 6*iiz/dl
                            estifm(3,3)= 12*iiy/dl**2;  estifm(3, 5)=-6*iiy/dl
                            estifm(3,9)=-12*iiy/dl**2;  estifm(3,11)=-6*iiy/dl

                            estifm(5,3)=-6*iiy/dl; estifm(5,5)=4*iiy
                            estifm(5,9)= 6*iiy/dl; estifm(5,11)=2*iiy
                            estifm(6,2)= 6*iiz/dl; estifm(6,6)=4*iiz
                            estifm(6,8)=-6*iiz/dl; estifm(6,12)=2*iiz


                            estifm(8,2)=-12*iiz/dl**2;  estifm(8, 6)=-6*iiz/dl
                            estifm(8,8)= 12*iiz/dl**2;  estifm(8,12)=-6*iiz/dl
                            estifm(9,3)=-12*iiy/dl**2;  estifm(9, 5)= 6*iiy/dl
                            estifm(9,9)= 12*iiy/dl**2;  estifm(9,11)= 6*iiy/dl

                            estifm(11,3)=-6*iiy/dl; estifm(11, 5)=2*iiy
                            estifm(11,9)= 6*iiy/dl; estifm(11,11)=4*iiy
                            estifm(12,2)= 6*iiz/dl; estifm(12, 6)=2*iiz
                            estifm(12,8)=-6*iiz/dl; estifm(12,12)=4*iiz
                        else !20211125
                            do idimn=1,3*(ndimn-1)
                                estifm(idimn,idimn)=element(ielem)%field(1)%kdiag(idimn)
                                estifm(idimn,idimn+6)=-element(ielem)%field(1)%kdiag(idimn)
                                estifm(idimn+6,idimn+6)=element(ielem)%field(1)%kdiag(idimn)
                                estifm(idimn+6,idimn)=-element(ielem)%field(1)%kdiag(idimn)
                            enddo
                        endif !20211125
                    endif
                    estif=estifm.x.trot
                    estifm=estif
                    estif=transpose(trot).x.estifm

                    !steel 2006
                    if (any(listglocbeam==igroup))then
                        if (ndimn==2)then
                            trot=0.
                            trot(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
                            trot(3,3)=1.
                            trot(4:5,4:5)=prot(:,:,lnods(2))
                            trot(6,6)=1.
                        elseif(ndimn==3)then
                            trot=0.
                            trot(1:3,1:3)=prot(:,:,lnods(1)); trot(4:6,4:6)=prot(:,:,lnods(1))
                            trot(7:9,7:9)=prot(:,:,lnods(2)); trot(10:12,10:12)=prot(:,:,lnods(2))
                        endif

                        estifm=matmul(estif,transpose(trot))
                        estif=estifm
                        estifm=trot.x.estif
                        estif=estifm

                    endif
                    !steel 2006
                    eload0=element(ielem)%field(1)%gpvar0(:,1)

                    eload0=eload0+(estif.x.eldis)
                    if (jfield/=0) then
                        tincr=0.
                        eload=0.
                        ldofs_t=>element(ielem)%field(jfield)%ldofs_f
                        !tincr=result_zero(ldofs_t)

                        if(outintr>=0)then
                            tincr=deltafi(ldofs_t)  !20200226
                        elseif(outintr<0)then
                            tincr=group(igroup)%temp_pre%dtemp  !20200226
                        end if

                        tincr=tincr/mdiv
                        tincr_g=sum(tincr)/2.
                        eload(1)=e*alfa*tincr_g*aera   !20200220
                        eload(3*ndimn-2)=-e*alfa*tincr_g*aera
                        eload0=eload0+(transpose(trot).x.eload)
                        nullify(ldofs_t)
                    endif

                    element(ielem)%field(1)%gpvar(:,1)=eload0

                    eload=eload0 !内力及转换后的荷载均为整体坐标下的结果  !20200220
                    !if(kinit_g==2.and.igroup_iblks/=1)then  !20201203
                    if((TYPE_PROBLEM=='Q'.and.(kinit_g==2.and.igroup_iblks/=1)).or. &
                        (TYPE_PROBLEM/='Q'.and.kinit_g==2))then  !20211214
                        eload=eload0-element(ielem)%stres0(:,1)
                    endif  !20201203

                    !write(7,*)'ie=',ielem,'eload=',eload

                elseif(index==25)then !steel 2006

                    allocate(ks(ndimn,ndimn),ksx(ndimn,ndimn*2),ddisp(ndimn),rotstar(ndimn,ndimn),unitx(ndimn,ndimn)) !KSX--B Matrix
                    ks=0. ; ksx=0. ; ddisp=0. ; rotstar=0. ; unitx=0.
                    thick=1.0
                    rotation=>element(ielem)%rotation
                    if (icpspring(lnods(1))==0)then
                        ipoin=lnods(2)
                    elseif(icpspring(lnods(2))==0)then
                        ipoin=lnods(1)
                    else
                        stop 'stop here!'
                    endif
                    ! if(ielem==1109)then
                    !     write(7,*)'ie=',ielem,'nstre=',nstre
                    !endif

                    rotstar=prot(:,:,ipoin)
                    unitx=matmul(rotation,transpose(rotstar))
                    aera    = element(ielem)%area

                    eldis=result_zero(ldofs)!deltafi(ldofs)
                    if (nlocalbeam==0)then
                        ddisp=rotation.x.(eldis(ndimn+1:ndimn*2)-eldis(1:ndimn))
                    else
                        if (icpnorm(lnods(1))==0)ddisp=eldis(ndimn+1:ndimn*2)-(rotation.x.eldis(1:ndimn))
                        if (icpnorm(lnods(2))==0)ddisp=(rotation.x.eldis(ndimn+1:ndimn*2))-eldis(1:ndimn)
                        if ((icpnorm(lnods(1))==0.and.icpnorm(lnods(2))==0).or.(icpnorm(lnods(1))/=0.and.icpnorm(lnods(2))/=0))then
                            write(*,*)'stop for (icpnorm(lnods(1))==0.and.icpnorm(lnods(2))==0).or.(icpnorm(lnods(1))/=0.and.icpnorm(lnods(2))/=0)'
                            write(*,*)'ielem=',ielem,lnods
                            stop
                        endif
                    endif
                    dgap1=ddisp(1)
                    dgapn=ddisp(2)
                    if(ndimn==3)dgapn=sqrt(ddisp(2)**2+ddisp(3)**2)
                    if(ikindks/=0)then
                        do inode=1,nnode
                            ipoin=lnods(inode)
                            if (icpspring(ipoin)/=0)exit
                        enddo
                        strabar=pstrain(lnods(inode))
                    endif

                    eldis=deltafi(ldofs)

                    ks=0.

                    ftx=0. ; fcx=0. ; dx=0.
                    call steel_bond_slip_relation(ikindks,abs(dgap1),ks(1,1),tao,ftx,fcx,dx,strabar,coefMpa)

                    ! if(ielem==1109)then
                    !     write(7,*)'ie=',ielem,'nstre=',nstre,'ks=',ks(1,1),'tao=',tao,'dx=',dx
                    !endif

                    ks(1,1)=ks(1,1)*aera
                    !if (dgap1<0)ks(1,1)=-ks(1,1) !?????????????
                    !if(abs(element(ielem)%field(1)%gpvar(nstre+5,1)-1.)<0.001)ks(1,1)=0. !for lhg
                    if (doubsig==2)then
                        if (ndimn>=2)ks(2,2)=ktan1
                        if (ndimn==3)ks(3,3)=ktan2
                    endif
                    !ksx=transpose(rotation).x.ks

                    if (icpspring(lnods(1))==0)then
                        ksx=0.
                        ksx(1:ndimn,1:ndimn)=-rotation
                        if(nlocalbeam==0)then
                            ksx(1:ndimn,ndimn+1:ndimn*2)=rotation
                        else
                            !do idimn=1,ndimn
                            !ksx(idimn,ndimn+idimn)=1
                            !enddo
                            ksx(1:ndimn,ndimn+1:ndimn*2)=unitx
                        endif

                    elseif(icpspring(lnods(2))==0)then
                        ksx=0.
                        ksx(1:ndimn,ndimn+1:ndimn*2)=rotation
                        if(nlocalbeam==0)then
                            ksx(1:ndimn,1:ndimn)=-rotation
                        else
                            !do idimn=1,ndimn
                            !ksx(idimn,idimn)=-1
                            !enddo
                            ksx(1:ndimn,1:ndimn)=-unitx
                        endif
                    else
                        write(*,*)'stop for Sub. Residu, line 601'
                        stop
                    endif
                    estif=matmul(matmul(transpose(ksx),ks),ksx) !K=BDB
                    eload=0.
                    eload0=element(ielem)%field(1)%gpvar0(1:nstre,1)
                    eload0=eload0+(estif.x.eldis)
                    allocate(eload1(ndimn),eload2(ndimn))
                    eload1=0. ; eload2=0.
                    forcx=aera*tao
                    if (icreep/=0)goto 1010
                    !element(ielem)%field(1)%gpvar(nstre+6,1)=eload0(1) ????
                    if (nlocalbeam==0)then
                        eload1=eload0(1:ndimn)
                        eload2=eload0(ndimn+1:ndimn*2)
                        eload1=rotation.x.eload1
                        eload2=rotation.x.eload2
                        if (dgap1>0.)then
                            eload1(1)=-forcx
                        elseif(dgap1<0.)then
                            eload1(1)=forcx
                        else
                            eload1(1)=0.
                        end if
                        eload2(1)=-eload1(1)
                        eload1=transpose(rotation).x.eload1
                        eload2=transpose(rotation).x.eload2
                        eload0(1:ndimn)=eload1
                        eload0(ndimn+1:ndimn*2)=eload2
                    else  ! nlocalbeam==0
                        if (icpnorm(lnods(1))==0)then
                            eload1=eload0(1:ndimn)
                            eload2=eload0(ndimn+1:ndimn*2)
                            if (dgap1>0.)then
                                eload2(1)=forcx
                            elseif(dgap1<0.)then
                                eload2(1)=-forcx
                            else
                                eload2(1)=0.
                            end if
                            eload1=rotation.x.eload1
                            eload1(1)=-eload2(1)
                            eload1=transpose(rotation).x.eload1
                            eload0(1:ndimn)=eload1
                            eload0(ndimn+1:ndimn*2)=eload2
                        else
                            eload1=eload0(1:ndimn)
                            eload2=eload0(ndimn+1:ndimn*2)
                            if (dgap1>0.)then
                                eload1(1)=-forcx
                            elseif(dgap1<0.)then
                                eload1(1)=forcx
                            else
                                eload1(1)=0.
                            end if
                            eload2=rotation.x.eload2
                            eload2(1)=-eload1(1)
                            eload2=transpose(rotation).x.eload2
                            eload0(1:ndimn)=eload1
                            eload0(ndimn+1:ndimn*2)=eload2
                        endif
                    endif ! nlocalbeam==0
1010                continue
                    deallocate(eload1,eload2)

                    element(ielem)%field(1)%gpvar(1:nstre,1)=eload0
                    eload=eload0
                    element(ielem)%field(1)%gpvar(nstre+1,1)=dgap1
                    element(ielem)%field(1)%gpvar(nstre+2,1)=dgapn
                    element(ielem)%field(1)%gpvar(nstre+3,1)=ks(1,1)
                    element(ielem)%field(1)%gpvar(nstre+4,1)=strabar

                    if (icreep/=0)then !for lhg

                        allocate(eload1(ndimn),eload2(ndimn))
                        eload1=0. ; eload2=0.
                        if (nlocalbeam==0)then
                            eload1=eload0(1:ndimn)
                            eload2=eload0(ndimn+1:ndimn*2)
                            eload1=rotation.x.eload1
                            eload2=rotation.x.eload2
                            if (icreep==1)then
                                forcx=aera*strenth
                            elseif (icreep==2)then
                                if(ndimn==2)fn=abs(eload2(2)) !abs?
                                if(ndimn==3)fn=sqrt(eload2(2)**2+eload2(3)**2)
                                forcx=fn*tand(fai)+sigmac*aera
                            else
                                stop 'stop for icreep>2!'
                            endif
                            if (abs(eload1(1))>forcx)then
                                eload1(1)=eload1(1)/abs(eload1(1))*forcx
                                eload2(1)=-eload1(1)
                                eload1=transpose(rotation).x.eload1
                                eload2=transpose(rotation).x.eload2
                                eload0(1:ndimn)=eload1
                                eload0(ndimn+1:ndimn*2)=eload2
                                element(ielem)%field(1)%gpvar(1:nstre,1)=eload0
                                eload=eload0
                                element(ielem)%field(1)%gpvar(nstre+5,1)=1.
                            endif
                        else
                            if (icpnorm(lnods(1))==0)then
                                eload1=eload0(1:ndimn)
                                eload2=eload0(ndimn+1:ndimn*2)
                                if (icreep==1)then
                                    forcx=aera*strenth
                                elseif (icreep==2)then
                                    stop 'stop for icreep==2!' !fn should be obtained in element level, tload-eload
                                    !if(ndimn==2)fn=abs(eload2(2)) !abs?
                                    !if(ndimn==3)fn=sqrt(eload2(2)**2+eload2(3)**2)
                                    !forcx=fn*tand(fai)+sigmac*aera
                                else
                                    stop 'stop for icreep>2!'
                                endif
                                if (abs(eload2(1))>forcx)then
                                    eload2(1)=eload2(1)/abs(eload2(1))*forcx
                                    eload1=rotation.x.eload1
                                    eload1(1)=-eload2(1)
                                    eload1=transpose(rotation).x.eload1
                                    eload0(1:ndimn)=eload1
                                    eload0(ndimn+1:ndimn*2)=eload2
                                    element(ielem)%field(1)%gpvar(1:nstre,1)=eload0
                                    eload=eload0
                                    element(ielem)%field(1)%gpvar(nstre+5,1)=1.
                                endif
                            else
                                eload1=eload0(1:ndimn)
                                eload2=eload0(ndimn+1:ndimn*2)
                                if (icreep==1)then
                                    forcx=aera*strenth
                                elseif (icreep==2)then
                                    stop 'stop for icreep==2!'
                                    !if(ndimn==2)fn=abs(eload1(2))
                                    !if(ndimn==3)fn=sqrt(eload1(2)**2+eload1(3)**2)
                                    !forcx=fn*tand(fai)+sigmac*aera
                                else
                                    stop 'stop for icreep>2!'
                                endif
                                if (abs(eload1(1))>forcx)then
                                    eload1(1)=eload1(1)/abs(eload1(1))*forcx
                                    eload2=rotation.x.eload2
                                    eload2(1)=-eload1(1)
                                    eload2=transpose(rotation).x.eload2
                                    eload0(1:ndimn)=eload1
                                    eload0(ndimn+1:ndimn*2)=eload2
                                    element(ielem)%field(1)%gpvar(1:nstre,1)=eload0
                                    eload=eload0
                                    element(ielem)%field(1)%gpvar(nstre+5,1)=1.
                                endif
                            endif
                        endif
                        deallocate(eload1,eload2)
                    endif
                    nullify(rotation)
                    deallocate(ks,ksx,ddisp,rotstar,unitx)
                endif

                !if(alfa_p4>0.and.index==22)then
                !if(any(local_p4(lnods)==1)) call change_eload_p4 !p42010  !20221124
                !endif

                !if(ielem==560) &
                !write(7,*)'ie=',ielem,'eload=',eload

                if (special(1:1)/='D') &
                    element(ielem)%field(1)%eload=element(ielem)%field(1)%eload+eload

                !!if(ielem==1.or.ielem==2) &
                !write(7,*)'ie residu=',ielem,'eload=',eload


                if (special(1:1)=='D') &
                    element(ielem)%field(1)%eload=element(ielem)%field(1)%eload+eload_dd(1:nevab)

                if (ntpel==1)deallocate(phydro)
100             continue
                if (nnode==2.or.index==22.or.index==26)nullify(rotation)
                if (special(1:1)=='D')deallocate(eldis_dd,eload_dd)

            end do       !!ielgroup

            !if(index.ne.20.and.index.ne.21) then ! not for beam
            if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                deallocate(cartd,ematx,gpcod,shape,ecmatx,dmatx,dcmatx)
                deallocate(stran,stres,strsg,bmatx,veca2,veca3)
                deallocate(devia,sgtot,avect,avecq,dvect,dvecq) !ljdp 2010
                if (name=='CONTACT')deallocate(gapgaus)
            else if(index.eq.20.or.index.eq.21) then
                deallocate(estif)
                deallocate(estifm)
                deallocate(trot)
                deallocate(eload0)
                if(material/='STEEL_SP')nullify(elcod)  !20211125
                if (jfield/=0) deallocate(tincr)
            elseif(index==25)then !steel 2006
                deallocate(estif,estifm,trot,eload0)
            endif

            deallocate(lnods,eldis,eload,ldofs)
            if (special(1:1)=='B'.and.index/=22.and.index/=26)deallocate (gmatx)
        endif        !! for co-displacement group
    end do         !!  for group

    contains

    subroutine change_eload_p4 !p42010

    integer (ink) ipoin
    real(irk),allocatable::trot(:,:),eloadx(:),eloady(:)

    allocate(trot(24,24),eloadx(24),eloady(24))
    trot=0. ; eloadx=0. ; eloady=0.

    eloady=eload

    do inode=1,8
        trot((inode-1)*ndimn+1:(inode-1)*ndimn+ndimn,(inode-1)*ndimn+1:(inode-1)*ndimn+ndimn)=rotation
    enddo
    eloadx=matmul(trot,eload)
    do inode=1,nnode
        ipoin=lnods(inode)
        if(local_p4(ipoin)==0)cycle  !20221124
        eloadx(inode*ndimn*2)=0.
    enddo
    eload=matmul(transpose(trot),eloadx)

    deallocate(trot,eloadx,eloady)

    end subroutine change_eload_p4


    subroutine DEPs

    character(20)criteria,model
    integer(ink) order_int,kload,ntest,istr1,ndiv,idm,first,icr
    real(irk) pwatr,satur,bulks,bulkd,bioal,bioac,epC,rot(3)
    real(irk),allocatable::stran(:),dd(:),sigma(:),vdval(:),strsg(:)
    real(irk) smax,qmax,phi,density,snorm
    real(irk),allocatable::evk(:)
    
    real(irk) normal_gap 
    
    material_select: select case(material)
    case('DUNCANCHANG')
        select case(type_stiff)
        case (1) ! Standard Dep
            !  if(appear_process(igroup,iblks-1)==0.and.iincs==1 &
            !     .and.istep==inc_step.and.iiter==1)then
            if ((appear_process(igroup,iblks-1)==0.or.  &
                (appear_process(igroup,iblks-1)==1.and.    &
                appear_process(igroup,iblks)==2))       &
                .and.iincs==1.and.istep==inc_step.and.idiv==1.and.iiter==1) then
                sgtot=0.
                density=props(matno)%mechanical%solid%density
                if (ndimn==2) then
                    sgtot(ndimn)=hdam(iblks)-gpcod(ndimn)
                    if (sgtot(ndimn)<=0.8)sgtot(ndimn)=0.8
                elseif(ndimn==3) then
                    sgtot(2)=hdam(iblks)-gpcod(2)
                    if (sgtot(2)<=10.)sgtot(2)=10.
                endif
                phi  =props(matno)%mechanical%solid%DuncanChang%phi
                phi=phi*3.14159/180.
                if (ndimn==2) then
                    sgtot(ndimn)=-sgtot(ndimn)*density
                    sgtot(1:ndimn-1)=sgtot(ndimn)*(1-SIN(phi))
                    if (ndimn==2.and.SPtype(1:2)=='PE')sgtot(4)=sgtot(1)
                else if(ndimn==3) then
                    sgtot(2)=-sgtot(2)*density
                    sgtot(1)=sgtot(2)*(1-SIN(phi))
                    sgtot(3)=sgtot(2)*(1-SIN(phi))
                endif
                qmax=0.;smax=0.
            else
                sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                qmax=element(ielem)%field(1)%gpvar(nstre+1,igaus)
                smax=element(ielem)%field(1)%gpvar(nstre+2,igaus)
            endif

            call tangceDCs(matno,smax,qmax,rot)
            case default
            print *, 'SORRY!'
            print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
        end select ! type_stiff
    case('GOODMAN')
        model=props(matno)%mechanical%solid%Goodman%model
        if(model=='JANBU')then
            select case(type_stiff)
            case (1) ! Standard Dep
                sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                allocate(evk(ndimn))
                !  if(appear_process(igroup,iblks-1)==0.and.iincs==1 &
                !     .and.istep==inc_step.and.iiter==1)first=1
                first=0
                if(type_problem/='Q') goto 10
                if ((appear_process(igroup,iblks-1)==0.or.  &
                    (appear_process(igroup,iblks-1)==1.and.    &
                    appear_process(igroup,iblks)==2))       &
                    .and.iincs==1.and.istep==inc_step.and.iiter==1.and.idiv==1) first=1
                !write(chkunit,*)'ie stif=',ielem,'first=',first
10              call PKPN(matno,evk,sgtot,first)
                
                normal_gap = element(ielem)%field(1)%gapg(igaus)-element(ielem)%field(1)%natural_thickness(igaus)

                ! 增加罚函数
                evk(ndimn) = evk(ndimn)/element(ielem)%field(1)%natural_thickness(igaus) + &
                    evk(ndimn)*normal_gap**2*1e3
                
                !write(chkunit,*)'evk=',evk
                dmatx=0.
                do idm=1,ndimn
                    dmatx(idm,idm)=evk(idm)
                end do
                deallocate(evk)
                case default
                print *, 'SORRY!'
                print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
            end select ! type_stiff

        elseif(model=='EQUBOLT') then  !20210913
            sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            allocate(evk(ndimn))
            call KBOLT(matno,evk,sgtot)
            element(ielem)%evk(:,igaus)=evk
            !write(7,*)'ie=',ielem,'ig=',igaus,'evk=',evk
            dmatx=0.
            do idm=1,ndimn
                dmatx(idm,idm)=evk(idm)
            end do
            deallocate(evk)

        endif  !20210913

    case('CLASSICALEP')
        criteria=props(matno)%mechanical%solid%classicalEP%criteria
        if (criteria=='MCJOINT')then
            rot(1:ndimn)=element(ielem)%rotation(1,:)
            snorm=element(ielem)%field(1)%ntstress(1,igaus)

            !    if(snorm==0.02)then
            !    dmatx=0.
            !    return
            !    endif

        endif
        select case(type_stiff)
        case (1) ! Standard Dep
            if ((kstat==2.and.iiter.le.2)) then
                sgtot=element(ielem)%field(1)%gpvar0(1:nstre,igaus)
                epC=element(ielem)%field(1)%gpvar0(nstre+1,igaus)
                yld=element(ielem)%field(1)%gpvar0(nstre+2,igaus)
            else
                sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                epC=element(ielem)%field(1)%gpvar(nstre+1,igaus)
                yld=element(ielem)%field(1)%gpvar(nstre+2,igaus)
            endif
            if (ljdp/=0)then !ljdp 2010
                sgtot=element(ielem)%field(1)%gpvar0(1:nstre,igaus)
                epC=element(ielem)%field(1)%gpvar0(nstre+1,igaus)
                yld=element(ielem)%field(1)%gpvar0(nstre+2,igaus)
                if (ljdp==2.and.yld/=0.)then
                    dmatx=dmatx*1.0e-5
                    return
                endif
            endif

            !     if(criteria=='MCJOINT'.and.yld==2.)then
            !     dmatx=0.
            !   call change1_dmatx(dmatx,yld,rot)
            !      return
            !      endif


            call tangcepstd(epC,matno,rot,snorm)
        case (2) ! General consistent Dep
            if (kstat==2.and.iiter.le.2) then
                sgtot=element(ielem)%field(1)%gpvar0(1:nstre,igaus)
                epC=element(ielem)%field(1)%gpvar0(nstre+1,igaus)
                yld=element(ielem)%field(1)%gpvar0(nstre+2,igaus)
            else
                sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                epC=element(ielem)%field(1)%gpvar(nstre+1,igaus)
                yld=element(ielem)%field(1)%gpvar(nstre+2,igaus)
            endif
            call tangcepconsg(sgtot,dmatx,nstre,epC,matno,rot,snorm)
            case default
            print *, 'SORRY!'
            print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
        end select ! type_stiff
    case('CONCRETE')
        select case(type_stiff)
        case (1) ! Standard Dep
            sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            yld=element(ielem)%field(1)%gpvar(nstre+2,igaus)
            epC=element(ielem)%field(1)%gpvar(nstre+1,igaus)
            icr=0
            if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
            if (icr==1)then
                call dep_concrete_1(element(ielem)%field(1)%rr(:,:,igaus),matno,yld,dmatx)
                return
            elseif(icr==2.or.icr==3.or.icr==5.or.icr==6)then !zhao09
                if (yld>.9)yld=.9
                dmatx=dmatx*(1-yld)**2
                return
            endif
            call tangcepstd(epC,matno,rot,snorm)
        case (2) ! General consistent Dep
            sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            yld=element(ielem)%field(1)%gpvar(nstre+2,igaus)
            epC=element(ielem)%field(1)%gpvar(nstre+1,igaus)
            !           write(chkunit,*)'ielem=',ielem,'igaus=',igaus
            call tangcepconsg(sgtot,dmatx,nstre,epC,matno,rot,snorm)
            case default
            print *, 'SORRY!'
            print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
        end select ! type_stiff
    case('SoilPZ')
        allocate(dd(24),vdval(5),sigma(nstre),stran(nstre),strsg(nstre))
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        strsg=element(ielem)%field(1)%gpvar0(1:nstre,igaus)
        kload=element(ielem)%egaus(order_int)%iload0(igaus)
        vdval=element(ielem)%egaus(order_int)%vdval0(1:5,igaus)
        pwatr=element(ielem)%egaus(order_int)%pwatr(igaus)
        satur=element(ielem)%egaus(order_int)%satur(igaus)
        dd=props(matno)%mechanical%solid%SoilPZ%d
        bulks=props(matno)%mechanical%fluid%bulks
        bulkd=props(matno)%mechanical%fluid%bulkd
        ntest=props(matno)%mechanical%solid%SoilPZ%ntest
        bioal=1.
        if (bulks.ne.0.)bioal=1.-bulkd/bulks
        if (bulkd.le.0.) bioal=1.
        if (bioal.lt.1.e-6)bioal=0.
        BIOAC=0.0
        if (BIOAL.NE.0.0) BIOAC=(BIOAL-1.)/BIOAL
        DO 152 ISTR1=1,2*ndimn
            if ((ndimn.eq.3.and.istr1.le.3).or.(ndimn.eq.2.and.ISTR1.NE.3)) THEN
                !**** compute sigma0'
                SIGMA(ISTR1)=strsg(ISTR1)+BIOAC*(bioal*satur*pwatr)
            ELSE
                SIGMA(ISTR1)=strsg(ISTR1)
            END IF
152     CONTINUE
        if (ndimn==2) then
            CALL CHANGE (STRAN)
            CALL CHANGE (SIGMA)
            CALL CHANGE (strsg)
        endif
        stran=0.0
        CALL TESMDL (nstre,strsg,SIGMA,STRAN,DMATX,VDVal,KLOAD,1,ndiv,ntest,dd)

        deallocate(dd,sigma,vdval,stran,strsg)
        case default
        print *, 'SORRY! residu.f90 dep'
        print *, 'THIS MATERIAL HAVE NOT BEEN IMPLEMENTED'

    end select  material_select

    end subroutine DEPs
    !  GOODMAN


    !
    subroutine tangceDCs(matno,smax,qmax,rot)

    character(2) model
    integer(ink) matno,i,isat
    real   (irk) smax,qmax,s,et,vt,vj2,sint3,p3,rot(:)
    model=props(matno)%mechanical%solid%DuncanChang%model

    isat=0

    CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)

    if (model=='EV'.or.model=='CR') then
        call DUNE(matno,smean,steff,theta,smax,Qmax,s,et,p3) !20130510
        call DUNV(matno,smean,s,VT)

    else if(model=='EB')then
        call EBMOD(isat,matno,smean,steff,theta,smax,Qmax,s,et,vt,p3) !20130510
    else if(model=='EBG')then
        call EBMODg(isat,matno,smean,steff,theta,smax,Qmax,s,et,vt,p3) !20130510
    endif
    call ecmat ( SPtype,dmatx,et,vt)
    if (ntpel.ne.0) bulkt=et/(3.0*(1.0-2.0*vt))


    end subroutine tangceDCs
    !
    subroutine tangcepstd(epC,matno,rot,snorm)

    integer (ink) matno,i
    real(irk) cons2,cons3,eqstr,preys,epC,rot(:)
    real(irk) harden,harden0,snorm,qfect,Ct,vj2,sint3

    if  (yld>eps) then

        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPC,PREYS,matno,snorm)
        if (nstre==1)eqstr=eqstr/sqrt(3.)   !! for line element, only sigma-Fc=0
        !! use VM model!
        CALL FLOWFQ (smean,AVECT,DEVIA,THETA,STEFF,AVECQ,  &
            NSTRE,matno,vj3,cons2,cons3,veca2,veca3,preys,epC,rot,snorm)

        call hardsmodu(matno,epC,harden0,steff,theta,smean,preys)
        Ct=0.
        call effective_strain(nstre,avecq,qfect,0,Ct)
        harden=harden0*qfect

        CALL FLOWPL (SPtype,ABETA,AVECT,DVECT,AVECQ, &
            DVECQ,NSTRE,matno,harden)

        do i=1,nstre
            DMATX(i,:)=DMATX(i,:)-ABETA*DVECQ(i)*DVECT(:)
        end do

    end if  !! if iyld

    end subroutine tangcepstd

    subroutine  tangcepconsg(sig,ad,nstre,epC,matno,rot,snorm)

    !  subroutine to compute the general consistent
    !  elasto-plastic   tangent modulus
    !
    !     input parameters :
    !       d    : array of material constants
    !       sig  : stresses at t-n+1 c       alph : back stress at t-n+1
    !       ep   : effective plastic strain at t-n
    !       epn  : effective plastic strain at t-n+1
    !       sig0 : stresses at t-n
    !       eps  : strains at t-n+1
    !
    !     output parameters :
    !       ad   : ' consistent tangent matrix'

    integer (ink) nstre,matno
    real (irk) sig(:),ad(:,:),cons2,cons3,epC,rot(:),snorm,Ct
    real (irk) p,dlan,dt,varj2,sint3,varj3,theta,steff,eqstr,preys,qfect
    real (irk),allocatable ::adel(:,:),dsig(:),da(:,:),      &
        Q(:,:),a(:),v1(:),Qf(:,:),n(:),v2(:)
    real (irk)  harden0,harden

    allocate (adel(nstre,nstre),dsig(nstre),da(nstre,nstre), &
        Q(nstre,nstre),a(nstre),v1(nstre),             &
        Qf(nstre,nstre),n(nstre),v2(nstre))

    adel = ad

    if  (epC>0. ) then

        !
        !     compute deviatoric components of tensors
        !
        !      call calcdevol(sig,dsig,p)

        CALL INVART (matno,nstre,Dsig,Sig,THETA,STEFF,p,varj2,varj3,sint3,rot)
        call YIELDS (THETA,p,STEFF,EQSTR,EPC,PREYS,matno,snorm)
        if (nstre==1)eqstr=eqstr/sqrt(3.)  !! VM model---->sigma-Fc=0

        CALL FLOWFQ (p,a,Dsig,THETA,STEFF,n,  &
            NSTRE,matno,varj3,cons2,cons3,veca2,veca3,preys,epC,rot,snorm)

        call hardsmodu(matno,epC,harden0,steff,theta,p,preys)

        Ct=0.
        call effective_strain(nstre,n,qfect,0,Ct)
        harden=harden0*qfect

        dlan = yld
        if (iiter==1) dlan=0.

        !
        !     compute derivative of normal vector
        !
        call dadsig(p,dsig,THETA,STEFF,NSTRE,                        &
            matno,varj3,veca2,veca3,preys, cons2,          &
            cons3,da,epC,rot)
        !
        !     compute Q matrix and its LU decomposition
        !
        call calcQ(Q,da,adel,dlan,nstre)    !!Q=I+d(lamda)*C*da

        !Qf=dcmp(Q,indx)                   !!Qf=Q--->LU
        !adel=bksb(Qf,adel,indx)      !! adel=inverse(Q)*C
        call householder(q,adel,qf)

        !
        !     compute vector normal to yield surface
        !

        !v1=adel.x.n                        !!v1=inverse(Q)*C*a
        !v2=adel.x.a
        v1=qf.x.n                        !!v1=inverse(Q)*C*a
        v2=qf.x.a

        dt = a.d.v1                        !!dt=tanspose(a)*v1

        !ad = adel - (v1.o.v2)/(dt+harden)
        ad = Qf - (v1.o.v2)/(dt+harden)

    endif

    deallocate (adel,dsig,da,Q,Qf,a,v1,v2,n)

    end  subroutine  tangcepconsg

    subroutine updstress

    select case(type_ecoint)
    case (1) ! Forward Euler
        call  fwds_euler(ielem,matno,igaus,nstre,stres,strsg, &
            SPtype,index,stran,dmatx,veca2,veca3, &
            igroup,gpcod)
    case (2) ! Backward Euler
        call  bkwd_euler(ielem,matno,igaus,nstre,stres,strsg, &
            dmatx,veca2,veca3)
        case default
        print *, 'SORRY!'
        print *, 'THIS TYPE_ECOINT HAS NOT BEEN IMPLEMENTED'
    end select ! type_ecoint

    end subroutine updstress

    END SUBROUTINE RESIDU_F

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    SUBROUTINE RESIDU_F1
    character(1)field1
    character(10)SPtype,class,fieldid,special
    character(30)material,name
    integer(ink) igroup, nrfields, ifield, ntpel, index,ic,      &
        matno,  nstre,    nevab,  nnode, order_int,     &
        ngaus,  ielgroup, ielem,  igaus, type_ecoint,   &
        inode, lnidmn,    aevab, &
        jnode,   jndex,  idimn, icreep, jfield,idofn,    &
        icr,kinit_g  !20211214
    integer(ink),pointer:: lnods(:), ldofs(:)
    real   (irk)  e, nu, djacb, thick
    real   (irk),allocatable::eldis(:), cartd(:,:),           &
        ematx(:,:),bmatx(:,:),gpcod(:), &
        shape(:),  eload(:),dmatx(:,:)
    real   (irk),allocatable::stran(:), stres(:), strsg(:),    &
        veca2(:),veca3(:)
    real   (irk),pointer::elcod(:,:)


    ! determine the time dependent coefficient for assembling.
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        class = group(igroup)%class
        special= group(igroup)%special
        kinit_g=group(igroup)%kinit_g
        ! judge whether the CO-displacement field is included.
        !if(appear(igroup)>0.and.field1=='U'.and.class=='CO') then
        if (appear(igroup)>0.and.field1=='U') then
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            ! find whether the u-p formulation is used, ntpel=1--yes!
            jfield=0
            do ifield=1,nrfields
                if (fieldid(ifield:ifield)=='T')then
                    jfield=ifield
                endif
            end do
            ! get information from the group level
            index = group(igroup)%index
            matno = group(igroup)%matno
            nstre=  group(igroup)%nstre
            SPtype=    group(igroup)%SPtype
            type_ecoint=    group(igroup)%type_ecoint
            nnode = elkn(index)%el_field(1)%nnode_f
            nevab = nnode*group(igroup)%dof(1)%nfdof
            material=props(matno)%mechanical%solid%material
            icr=0
            if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
            name=props(matno)%name
            icreep= props(matno)%mechanical%solid%icreep
            if(Bparameter/=0.and.props(matno)%mechanical%solid%ie/=0)then !20190810
                e=xvalue(props(matno)%mechanical%solid%ie)
            else
                e=props(matno)%mechanical%solid%e !exx !
            endif
            if(Bparameter/=0.and.props(matno)%mechanical%solid%iNu/=0)then
                Nu=xvalue(props(matno)%mechanical%solid%iNu)
            else
                Nu=props(matno)%mechanical%solid%Nu !uxx !
            endif  !20190810
            if (icreep.ne.0)e=group(igroup)%educ  !20190810(待修改！）
            allocate (lnods(nnode),ldofs(nevab),    &
                eldis(nevab),eload(nevab))
            thick=1.
            if (ndimn==2)thick  =props(matno)%mechanical%solid%thickness

            allocate(shape(nnode))
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus
            lnidmn=elkn(index)%ndimn
            ! allocate the arrays which will be used
            allocate (stran(nstre),stres(nstre))
            allocate (cartd(lnidmn,nnode),bmatx(nstre,nevab))
            allocate (ematx(nstre,nstre),gpcod(ndimn),dmatx(nstre,nstre))
            allocate (strsg(nstre))
            allocate (veca2(nstre),veca3(nstre))

            ! compute the elastic matrix, De or Ds
            ematx=0.
            call ecmat(SPtype,ematx,e,nu)
            ! loop for 1:nelgroup
            DO ielgroup = 1,group1(igroup)%nelgroup
                ielem = group1(igroup)%list(ielgroup)
                if (jce1(ielem)==1) goto 100
                lnods = element1(ielem)%field(1)%lnods_f
                ldofs = element1(ielem)%field(1)%ldofs_f
                if (iblks==(element1(ielem)%jblks+1))then
                    eldis = result_zero(ldofs)
                else
                    eldis = deltafi(ldofs)
                endif
                eload =0.0
                !          write(7,*)'ie=',ielem,'eldis=',eldis
                do igaus=1,ngaus
                    shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                    ! get djacb and cartd in the element1 level
                    djacb=element1(ielem)%egaus(order_int)%djacb(igaus)
                    gpcod=element1(ielem)%egaus(order_int)%gpcod(:,igaus)
                    bmatx=0.0
                    cartd=element1(ielem)%egaus(order_int)%cartd(:,:,igaus)
                    call gbmat   (SPtype, nnode, bmatx, cartd, gpcod, shape)
                    ! compute strain and elastic stres increment
                    stran=matmul(bmatx,eldis)
                    ! for creep and temperature---> stran=stran-stran(creep)-stran(temp)
                    if (jfield/=0.or.icreep>=3)   &
                        stran=stran-element1(ielem)%field(1)%stran0(:,igaus)   !20200227
                    if (icr==2.or.icr==3.or.icr==5.or.icr==6) & !zhao09
                        stran=stran+element1(ielem)%field(1)%strain0(:,igaus)
                    stres=matmul(ematx,stran)
                    if (ndimn==2.and.SPtype(1:2)=='PS')  &
                        stran(4)=-(stran(1)+stran(2))*nu/(1.-nu)
                    if (ndimn==2.and.SPtype(1:2)=='PE')  &
                        STRES(4)=nu*(STRES(1)+STRES(2))+e*STRAN(4)

                    ! compute total stres
                    dmatx=ematx
                    call FWDS_EULER1(ielem,matno,igaus,nstre,stres,strsg, &
                        SPtype,index,dmatx,veca2,veca3, &
                        igroup,gpcod)

                    ! if kinit_g=2, the initial load related to initial stress is not computed
                    if (kinit_g==2)strsg=strsg-element1(ielem)%stres0(:,igaus)
                    ! compute the internal force
                    eload=eload+thick*djacb*MATMUL(transpose(bmatx),strsg)

                    ! for simo & Rifai element
                    if (icreep==2)   &
                        element1(ielem)%field(1)%dsig(:,igaus)=  &
                        element1(ielem)%field(1)%gpvar(1:nstre,igaus)-  &
                        element1(ielem)%field(1)%gpvar0(1:nstre,igaus)
10                  continue
                end do     !!igaus
1               continue


                element1(ielem)%field(1)%eload=element1(ielem)%field(1)%eload+eload

100             continue

            end do       !!ielgroup

            deallocate(cartd,ematx,gpcod,shape,dmatx)
            deallocate(stran,stres,strsg,bmatx,veca2,veca3)
            deallocate(lnods,eldis,eload,ldofs)
        endif        !! for co-displacement group
    end do         !!  for group

    contains

    SUBROUTINE FWDS_EULER1(ielem,matno,igaus,nstre,stres,strsg, &
        SPtype,index,dmatx,veca2,veca3, &
        igroup,gpcod)

    character(10) SPtype
    character(20) material,criteria
    character(10) model,name
    integer(ink) matno,igaus,mstep,nstre,ielem,jstep,first,ic,icc,icr
    integer(ink) order_int,kload,ntest,istr1,ndiv,index,igroup
    real   (irk) epstn, effst, theta, steff, smean, vj3,       &
        eqstr, preys, escur, rfact, astep,     &
        reduc, agash, bring, uniax, dlamd,     &
        abeta,curys,eps, cons2,cons3,qfect,Ct,vj2,sint3
    real   (irk) pwatr,satur,bulks,bulkd,bioal,bioac,dmatx(:,:)
    real   (irk) stres(:), strsg(:), sgtot(nstre),veca2(:),veca3(:)
    real   (irk) devia(nstre), avect(nstre), avecq(nstre),     &
        dvect(nstre), dvecq(nstre)
    real   (irk),allocatable::d(:),sigma(:),vdval(:)
    real   (irk) harden0,hards,rot(3),gpcod(:)
    real   (irk) s,smax,qmax,et,vt,evk(3),phi,density,snorm,ft,yld,damage0
    real   (irk),pointer::rr(:,:)

    eps=-1.e-1
    material=props(matno)%mechanical%solid%material

    if (material(1:7)=='ELASTIC')   then
        element1(ielem)%field(1)%gpvar(1:nstre,igaus)=                        &
            element1(ielem)%field(1)%gpvar0(1:nstre,igaus)+stres
        strsg=element1(ielem)%field(1)%gpvar(1:nstre,igaus)
        return
    elseif(material=='CLASSICALEP'.or.material=='CONCRETE') then
        if (material=='CLASSICALEP') then
            uniax=props(matno)%mechanical%solid%classicalEP%sigma0
            hards=props(matno)%mechanical%solid%classicalEP%hardening
            criteria=props(matno)%mechanical%solid%classicalEP%criteria
        endif
        epstn=element1(ielem)%field(1)%gpvar0(nstre+1,igaus)
        effst=element1(ielem)%field(1)%gpvar0(nstre+3,igaus)
        strsg=element1(ielem)%field(1)%gpvar0(1:nstre,igaus)
        yld=element1(ielem)%field(1)%gpvar0(nstre+2,igaus)
        sgtot=strsg+stres
        icr=0
        if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr

        if (icr/=0)then
            icc=2
            if (icr==1)then
                rr=>element1(ielem)%field(1)%rr(:,:,igaus)
                call concrete_1(matno,SPtype,yld,nstre,stran,strsg,sgtot,devia,rot,rr,icc)
            else if(icr==2) then
                damage0  =element1(ielem)%field(1)%gpvar0(nstre+2,igaus)
                call concrete_2(matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            else if(icr==3) then
                damage0  =element1(ielem)%field(1)%gpvar0(nstre+2,igaus)
                call concrete_3(ielem,matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            else if(icr==5) then !zhao09
                damage0  =element1(ielem)%field(1)%gpvar0(nstre+2,igaus)
                call concrete_5(matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            endif
            element1(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
            if (rmesh==1) &
                element1(ielem)%field(1)%gpvar(nstre+2,igaus)=yld
            if (rmesh==2) &
                element1(ielem)%field(1)%gpvar(nstre+3,igaus)=yld
            if (icr>=2)element1(ielem)%field(1)%strain(1:nstre,igaus)=stran
            return
        endif

        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,PREYS,matno,snorm)
        if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
        ESCUR=EQSTR-PREYS
        if (rmesh==2)then
            yld=eqstr/preys
            strsg=sgtot
            goto 160
        endif

        if (epstn.ne.0.) GOTO 50
        ESCUR=EQSTR-PREYS
        if (ESCUR<=eps*preys.or.abs(eqstr-effst).le.abs(eps)) GOTO 60
        RFACT=ESCUR/(EQSTR-EFFST)
        GO TO 70
50      ESCUR=EQSTR-EFFST
        if (ESCUR/abs(effst)<=eps) GOTO 60
        RFACT=1.0
70      MSTEP=ESCUR*8.0/preys+1.0

        if (MSTEP.GT.10) MSTEP=10
        ASTEP=MSTEP
        if (epstn.ne.0.) then
            sgtot=strsg
            stres=stres/astep
        else
            rfact=escur/eqstr
            REDUC=1.0-RFACT
            stres=rfact*sgtot/astep
            sgtot=reduc*sgtot
        endif
        DO 90 JSTEP=1,MSTEP
            CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
            call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,PREYS,matno,snorm)
            if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
            CALL FLOWFQ (smean,AVECT,DEVIA,THETA,STEFF,AVECQ,NSTRE,matno,     &
                vj3,cons2,cons3,veca2,veca3, PREYS,epstn,rot,snorm)
            call hardsmodu(matno,epstn,harden0,steff,theta,smean,preys)
            icc=0
            if (material=='CONCRETE')then
                icc=1
                Ct =props(matno)%mechanical%solid%Concrete%Ct
            endif
            call effective_strain(nstre,avecq,qfect,icc,Ct)
            agash=sum(avect*stres)
            hards=harden0*qfect
            CALL FLOWPL (SPtype,ABETA,AVECT,DVECT,AVECQ,DVECQ,NSTRE,matno,hards)
            DLAMD=AGASH*ABETA
            if (abs(DLAMD)<1.e-15) DLAMD=0.0
            sgtot=sgtot+stres-dlamd*dvecq
            if (SPtype=='PS') sgtot(nstre)=0.
            EPSTN=EPSTN+DLAMD*qfect
90      CONTINUE
        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,CURYS,matno,snorm)
        if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
        BRING=1.0
        if (EQSTR.GT.CURYS) BRING=CURYS/EQSTR
        strsg=bring*sgtot
        EFFST=BRING*EQSTR
        yld=1.
        element1(ielem)%field(1)%gpvar(nstre+1,igaus)=epstn
        element1(ielem)%field(1)%gpvar(nstre+3,igaus)=effst
        element1(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
        element1(ielem)%field(1)%gpvar(nstre+2,igaus)=yld

        return
        !**** FOR ELASTIC AND UNLODING
60      CONTINUE
        if (epstn/=0.)then
            epstn=0.
            yld=0.
        else
            strsg=sgtot
            effst=eqstr
        endif
160     continue  !!new
        if (rmesh==1)then
            element1(ielem)%field(1)%gpvar(nstre+3,igaus)=effst
            element1(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
            element1(ielem)%field(1)%gpvar(nstre+1,igaus)=epstn
            element1(ielem)%field(1)%gpvar(nstre+2,igaus)=yld
        else if(rmesh==2)then
            element1(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
            element1(ielem)%field(1)%gpvar(nstre+3,igaus)=yld
        endif
        return
    end if   !!!!
    END SUBROUTINE FWDS_EULER1

    END SUBROUTINE RESIDU_F1

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    SUBROUTINE RESIDU_F2

    character(1)field1
    character(10)SPtype,class,fieldid,special
    character(30)material,name
    integer(ink) igroup, nrfields, ifield, ntpel, index,ic,      &
        matno,  nstre,    nevab,  nnode, order_int,     &
        ngaus,  ielgroup, ielem,  igaus, type_ecoint,   &
        inode, lnidmn,    aevab, &
        jnode,   jndex,  idimn, icreep, jfield,idofn,    &
        icr,kinit_g  !20211214
    integer(ink),pointer:: lnods(:), ldofs(:)
    real   (irk)  e, nu, djacb, thick
    real   (irk),allocatable::eldis(:), cartd(:,:),           &
        ematx(:,:),bmatx(:,:),gpcod(:), &
        shape(:),  eload(:),dmatx(:,:)
    real   (irk),allocatable::stran(:), stres(:), strsg(:),    &
        veca2(:),veca3(:)
    real   (irk),pointer::elcod(:,:)


    ! determine the time dependent coefficient for assembling.
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        class = group(igroup)%class
        special= group(igroup)%special
        ! judge whether the CO-displacement field is included.
        !           if(appear(igroup)>0.and.field1=='U'.and.class=='CO') then
        if (appear(igroup)>0.and.field1=='U') then
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            ! find whether the u-p formulation is used, ntpel=1--yes!
            jfield=0
            do ifield=1,nrfields
                if (fieldid(ifield:ifield)=='T')then
                    jfield=ifield
                endif
            end do
            ! get information from the group level
            index = group(igroup)%index
            matno = group(igroup)%matno
            nstre=  group(igroup)%nstre
            SPtype=    group(igroup)%SPtype
            type_ecoint=    group(igroup)%type_ecoint
            nnode = elkn(index)%el_field(1)%nnode_f
            nevab = nnode*group(igroup)%dof(1)%nfdof
            material=props(matno)%mechanical%solid%material
            icr=0
            if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
            name=props(matno)%name
            icreep= props(matno)%mechanical%solid%icreep
            if(Bparameter/=0.and.props(matno)%mechanical%solid%ie/=0)then !20190810
                e=xvalue(props(matno)%mechanical%solid%ie)
            else
                e=props(matno)%mechanical%solid%e !exx !
            endif
            if(Bparameter/=0.and.props(matno)%mechanical%solid%iNu/=0)then
                Nu=xvalue(props(matno)%mechanical%solid%iNu)
            else
                Nu=props(matno)%mechanical%solid%Nu !uxx !
            endif  !20190810
            if (icreep.ne.0)e=group(igroup)%educ  !考虑徐变参数变化时，待修改

            allocate (lnods(nnode),ldofs(nevab),    &
                eldis(nevab),eload(nevab))
            thick=1.
            if (ndimn==2)thick  =props(matno)%mechanical%solid%thickness

            allocate(shape(nnode))
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus
            lnidmn=elkn(index)%ndimn
            ! allocate the arrays which will be used
            allocate (stran(nstre),stres(nstre))
            allocate (cartd(lnidmn,nnode),bmatx(nstre,nevab))
            allocate (ematx(nstre,nstre),gpcod(ndimn),dmatx(nstre,nstre))
            allocate (strsg(nstre))
            allocate (veca2(nstre),veca3(nstre))

            ! compute the elastic matrix, De or Ds
            ematx=0.
            call ecmat(SPtype,ematx,e,nu)
            ! loop for 1:nelgroup
            DO ielgroup = 1,group2(igroup)%nelgroup

                ielem = group2(igroup)%list(ielgroup)
                lnods = element2(ielem)%field(1)%lnods_f
                ldofs = element2(ielem)%field(1)%ldofs_f
                if (iblks==(element2(ielem)%jblks+1))then
                    eldis = result_zero(ldofs)
                else
                    eldis = deltafi(ldofs)
                endif
                eload =0.0
                do igaus=1,ngaus
                    shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                    ! get djacb and cartd in the element1 level
                    djacb=element2(ielem)%egaus(order_int)%djacb(igaus)
                    gpcod=element2(ielem)%egaus(order_int)%gpcod(:,igaus)
                    bmatx=0.0
                    cartd=element2(ielem)%egaus(order_int)%cartd(:,:,igaus)
                    call gbmat   (SPtype, nnode, bmatx, cartd, gpcod, shape)
                    ! compute strain and elastic stres increment
                    stran=matmul(bmatx,eldis)
                    ! for creep and temperature---> stran=stran-stran(creep)-stran(temp)
                    if (jfield/=0.or.icreep>=3)   &
                        stran=stran-element2(ielem)%field(1)%stran0(:,igaus)  !20200227
                    if (icr==2.or.icr==3.or.icr==5.or.icr==6) & !zhao09
                        stran=stran+element2(ielem)%field(1)%strain0(:,igaus)
                    stres=matmul(ematx,stran)
                    if (ndimn==2.and.SPtype(1:2)=='PS')  &
                        stran(4)=-(stran(1)+stran(2))*nu/(1.-nu)
                    if (ndimn==2.and.SPtype(1:2)=='PE')  &
                        STRES(4)=nu*(STRES(1)+STRES(2))+e*STRAN(4)

                    ! compute total stres
                    dmatx=ematx
                    call FWDS_EULER2(ielem,matno,igaus,nstre,stres,strsg, &
                        SPtype,index,dmatx,veca2,veca3, &
                        igroup,gpcod)
                    ! if kinit_g=2, the initial load related to initial stress is not computed
                    if (kinit_g==2)strsg=strsg-element2(ielem)%stres0(:,igaus)
                    ! compute the internal force
                    eload=eload+thick*djacb*MATMUL(transpose(bmatx),strsg)

                    ! for simo & Rifai element
                    if (icreep==2)   &
                        element2(ielem)%field(1)%dsig(:,igaus)=  &
                        element2(ielem)%field(1)%gpvar(1:nstre,igaus)-  &
                        element2(ielem)%field(1)%gpvar0(1:nstre,igaus)
10                  continue
                end do     !!igaus
1               continue


                element2(ielem)%field(1)%eload=element2(ielem)%field(1)%eload+eload

100             continue

            end do       !!ielgroup

            deallocate(cartd,ematx,gpcod,shape,dmatx)
            deallocate(stran,stres,strsg,bmatx,veca2,veca3)
            deallocate(lnods,eldis,eload,ldofs)
        endif        !! for co-displacement group
    end do         !!  for group

    contains

    SUBROUTINE FWDS_EULER2(ielem,matno,igaus,nstre,stres,strsg, &
        SPtype,index,dmatx,veca2,veca3, &
        igroup,gpcod)

    character(10) SPtype
    character(20) material,criteria
    character(10)  model,name
    integer(ink) matno,igaus,mstep,nstre,ielem,jstep,first,ic,icc,icr
    integer(ink) order_int,kload,ntest,istr1,ndiv,index,igroup
    real   (irk) epstn, effst, theta, steff, smean, vj3,       &
        eqstr, preys, escur, rfact, astep,     &
        reduc, agash, bring, uniax, dlamd,     &
        abeta,curys,eps, cons2,cons3,qfect,Ct,vj2,sint3
    real   (irk) pwatr,satur,bulks,bulkd,bioal,bioac,dmatx(:,:)
    real   (irk) stres(:), strsg(:), sgtot(nstre),veca2(:),veca3(:)
    real   (irk) devia(nstre), avect(nstre), avecq(nstre),     &
        dvect(nstre), dvecq(nstre)
    real   (irk),allocatable::d(:),sigma(:),vdval(:)
    real   (irk) harden0,hards,rot(3),gpcod(:)
    real   (irk) s,smax,qmax,et,vt,evk(3),phi,density,snorm,ft,yld,damage0
    real   (irk),pointer::rr(:,:)

    eps=-1.e-2
    material=props(matno)%mechanical%solid%material

    if (material(1:7)=='ELASTIC')   then
        element2(ielem)%field(1)%gpvar(1:nstre,igaus)=                        &
            element2(ielem)%field(1)%gpvar0(1:nstre,igaus)+stres
        strsg=element2(ielem)%field(1)%gpvar(1:nstre,igaus)
        return
    elseif(material=='CLASSICALEP'.or.material=='CONCRETE') then
        if (material=='CLASSICALEP') then
            uniax=props(matno)%mechanical%solid%classicalEP%sigma0
            hards=props(matno)%mechanical%solid%classicalEP%hardening
            criteria=props(matno)%mechanical%solid%classicalEP%criteria
        endif
        epstn=element2(ielem)%field(1)%gpvar0(nstre+1,igaus)
        effst=element2(ielem)%field(1)%gpvar0(nstre+3,igaus)
        strsg=element2(ielem)%field(1)%gpvar0(1:nstre,igaus)
        yld=element2(ielem)%field(1)%gpvar0(nstre+2,igaus)
        sgtot=strsg+stres
        icr=0
        if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr

        if (icr/=0)then
            icc=3
            if (icr==1)then
                rr=>element2(ielem)%field(1)%rr(:,:,igaus)
                call concrete_1(matno,SPtype,yld,nstre,stran,strsg,sgtot,devia,rot,rr,icc)
            else if(icr==2) then
                damage0  =element2(ielem)%field(1)%gpvar0(nstre+2,igaus)
                call concrete_2(matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            else if(icr==3) then
                damage0  =element2(ielem)%field(1)%gpvar0(nstre+2,igaus)
                call concrete_3(ielem,matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            else if(icr==5)then !zhao09
                damage0  =element2(ielem)%field(1)%gpvar0(nstre+2,igaus)
                call concrete_5(matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            endif
            element2(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
            element2(ielem)%field(1)%gpvar(nstre+2,igaus)=yld
            if (icr>=2)element2(ielem)%field(1)%strain(1:nstre,igaus)=stran
            return
        endif

        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,PREYS,matno,snorm)
        if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
        ESCUR=EQSTR-PREYS

        if (epstn.ne.0.) GOTO 50
        ESCUR=EQSTR-PREYS
        if (ESCUR<=eps*preys.or.abs(eqstr-effst).le.abs(eps)) GOTO 60
        RFACT=ESCUR/(EQSTR-EFFST)
        GO TO 70
50      ESCUR=EQSTR-EFFST
        if (ESCUR/abs(effst)<=eps) GOTO 60
        RFACT=1.0
70      MSTEP=ESCUR*8.0/preys+1.0

        if (MSTEP.GT.10) MSTEP=10
        ASTEP=MSTEP
        if (epstn.ne.0.) then
            sgtot=strsg
            stres=stres/astep
        else
            rfact=escur/eqstr
            REDUC=1.0-RFACT
            stres=rfact*sgtot/astep
            sgtot=reduc*sgtot
        endif
        DO 90 JSTEP=1,MSTEP
            CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
            call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,PREYS,matno,snorm)
            if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
            CALL FLOWFQ (smean,AVECT,DEVIA,THETA,STEFF,AVECQ,NSTRE,matno,     &
                vj3,cons2,cons3,veca2,veca3, PREYS,epstn,rot,snorm)
            call hardsmodu(matno,epstn,harden0,steff,theta,smean,preys)
            icc=0
            if (material=='CONCRETE')then
                icc=1
                Ct =props(matno)%mechanical%solid%Concrete%Ct
            endif
            call effective_strain(nstre,avecq,qfect,icc,Ct)
            agash=sum(avect*stres)
            hards=harden0*qfect
            CALL FLOWPL (SPtype,ABETA,AVECT,DVECT,AVECQ,DVECQ,NSTRE,matno,hards)
            DLAMD=AGASH*ABETA
            if (abs(DLAMD)<1.e-15) DLAMD=0.0
            sgtot=sgtot+stres-dlamd*dvecq
            if (SPtype=='PS') sgtot(nstre)=0.
            EPSTN=EPSTN+DLAMD*qfect
90      CONTINUE
        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,CURYS,matno,snorm)
        if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
        BRING=1.0
        if (EQSTR.GT.CURYS) BRING=CURYS/EQSTR
        strsg=bring*sgtot
        EFFST=BRING*EQSTR
        yld=1.
        element2(ielem)%field(1)%gpvar(nstre+1,igaus)=epstn
        element2(ielem)%field(1)%gpvar(nstre+3,igaus)=effst
        element2(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
        element2(ielem)%field(1)%gpvar(nstre+2,igaus)=yld

        return
        !**** FOR ELASTIC AND UNLODING
60      CONTINUE
        if (epstn/=0.)then
            epstn=0.
            yld=0.
        else
            strsg=sgtot
            effst=eqstr
        endif
160     continue  !!new
        element2(ielem)%field(1)%gpvar(nstre+3,igaus)=effst
        element2(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
        element2(ielem)%field(1)%gpvar(nstre+1,igaus)=epstn
        element2(ielem)%field(1)%gpvar(nstre+2,igaus)=yld

        return
    end if   !!!!
    END SUBROUTINE FWDS_EULER2


    END SUBROUTINE RESIDU_F2
    !************************************************************************
    !  !nstoks
    subroutine eload_nstoks(matno,ielem,nnode,djacb,thick,shape,cartd,eload)

    integer(ink) ielem,nnode,matno,  &
        idimn,jdimn,inode,ievab
    real   (irk) djacb,shape(:),cartd(:,:),eload(:)
    real   (irk) density,vstrn,thick
    real   (irk),allocatable::vgaus(:),veloc(:),dgaus(:,:),xxx(:)
    integer(ink),pointer::ldofs(:)

    allocate(vgaus(ndimn),veloc(ndimn*nnode),dgaus(ndimn,ndimn),xxx(ndimn))

    vgaus=0.
    veloc=0.
    dgaus=0.
    xxx=0.
    density=props(matno)%mechanical%solid%density
    ldofs => element(ielem)%field(1)%ldofs_f
    veloc =  result_first(ldofs)

    do idimn=1,ndimn
        do inode=1,nnode
            ievab=(inode-1)*ndimn+idimn
            vgaus(idimn)=vgaus(idimn)+shape(inode)*veloc(ievab)
            vstrn=vstrn+veloc(ievab)*cartd(idimn,inode)
            do jdimn=1,ndimn
                dgaus(idimn,jdimn)=dgaus(idimn,jdimn)+cartd(jdimn,inode)*veloc(ievab)
            end do
        end do
    end do


    do jdimn=1,ndimn
        xxx(jdimn)=vstrn*vgaus(jdimn)+vgaus.d.dgaus(jdimn,:)
    end do
    do idimn=1,ndimn
        do inode=1,nnode
            ievab=(inode-1)*ndimn+idimn
            eload(ievab)=eload(ievab)+xxx(jdimn)*shape(inode)*djacb*thick*density
        end do
    end do

    deallocate(vgaus,veloc,xxx,dgaus)

    end subroutine eload_nstoks

    !!
    !  !nstoks
    subroutine find_fexta

    character(1)field1
    character(10)name
    integer(ink) ielem,nnode,matno,index,itotv,igroup,ngaus,igaus,  &
        idimn,jdimn,inode,ievab,order_int,ielgroup
    real   (irk) djacb,density,thick
    real   (irk),allocatable::vgaus(:),veloc(:),dgaus(:,:),xxx(:),vgaus0(:),   &
        yyy(:),shape(:),cartd(:,:),veloc0(:)
    integer(ink),pointer::ldofs(:)

    allocate(yyy(ntotv))
    do itotv=1,ntotv
        if (fmass(itotv)/=0.)  &
            yyy(itotv)=2.*(floae(itotv)-floai(itotv))/fmass(itotv)
    end do

    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        matno = group(igroup)%matno
        name=props(matno)%name
        if (appear(igroup)>0.and.field1=='U'.and.name=='NSTOKS')then
            index = group(igroup)%index
            nnode = elkn(index)%el_field(1)%nnode_f
            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus
            allocate(vgaus(ndimn),veloc(ndimn*nnode),dgaus(ndimn,ndimn),xxx(ndimn))
            allocate(shape(nnode),cartd(ndimn,nnode),veloc0(ndimn*nnode),vgaus0(ndimn))
            thick=1.
            if (ndimn==2)thick  =props(matno)%mechanical%solid%thickness

            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)

                do igaus=1,ngaus

                    shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                    djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                    cartd=element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                    vgaus=0.
                    vgaus0=0.
                    veloc=0.
                    dgaus=0.
                    veloc0=0.
                    xxx=0.
                    density=props(matno)%mechanical%solid%density
                    ldofs => element(ielem)%field(1)%ldofs_f
                    veloc0 =  yyy(ldofs)
                    veloc  =  result_first(ldofs)

                    do idimn=1,ndimn
                        do inode=1,nnode
                            ievab=(inode-1)*ndimn+idimn
                            vgaus0(idimn)=vgaus(idimn)+shape(inode)*veloc0(ievab)
                            vgaus(idimn)=vgaus(idimn)+shape(inode)*veloc(ievab)
                            do jdimn=1,ndimn
                                dgaus(idimn,jdimn)=dgaus(idimn,jdimn)+cartd(jdimn,inode)*veloc0(ievab)
                            end do
                        end do
                    end do


                    do jdimn=1,ndimn
                        xxx(jdimn)=vgaus0(jdimn)-ditime*(vgaus.d.dgaus(jdimn,:))
                    end do
                    do idimn=1,ndimn
                        do inode=1,nnode
                            ievab=(inode-1)*ndimn+idimn
                            fexta(ldofs(ievab))=fexta(ldofs(ievab))+   &
                                xxx(jdimn)*shape(inode)*djacb*thick*density
                        end do
                    end do
                end do  !!igaus
            end do  !!ielgroup
            deallocate(vgaus,veloc,xxx,dgaus,shape,cartd,vgaus0,veloc0)
        endif   !! appearing group
    end do  !!igroup
    deallocate(yyy)

    end subroutine find_fexta

    ! The following two subs are for Simo Rifai Elements

    subroutine residu_sr(fieldid,gmatx,igaus,ngaus,ielem,djacb,stres)

    character(10) fieldid
    integer(ink) ielem,igaus,ngaus,aevab,nevab,np
    integer(ink),pointer::ldofsp(:),lnodsp(:)
    real   (irk) djacb,stres(:),gmatx(:,:)
    real   (irk), pointer::estift(:,:),   &
        estifhi(:,:),qmatxa(:,:)
    real   (irk), allocatable::rh0(:,:),hinvk(:,:),eload(:),elpw(:)

    element(ielem)%rh=element(ielem)%rh+        &
        djacb*(transpose(gmatx).x.stres)

    if (igaus<ngaus) return
    if  (fieldid(1:2)=='UW') then
        ldofsp => element(ielem)%field(2)%ldofs_f
        np = size(ldofsp)
        allocate(elpw(np))
        elpw  = result_zero(ldofsp)
        if (allocated(prstat))then
            lnodsp => element(ielem)%field(2)%lnods_f
            elpw=elpw-prstat(lnodsp)
        endif
        qmatxa => element(ielem)%qmatxa
        element(ielem)%rh = element(ielem)%rh - ( qmatxa.x.elpw )
        deallocate(elpw)
        nullify(ldofsp,qmatxa)
    endif
    !
    estift =>element(ielem)%estift
    estifhi=>element(ielem)%estifh

    aevab=size(estift,dim=1)
    nevab=size(estift,dim=2)
    allocate(rh0(aevab,1),hinvk(aevab,1),eload(nevab))
    rh0(:,1)=-element(ielem)%rh
    call householder(estifhi,rh0,hinvk) !3
    eload=transpose(estift).x.hinvk(:,1)

    element(ielem)%field(1)%eload=element(ielem)%field(1)%eload &
        +eload
    deallocate(rh0,hinvk,eload)
    nullify(estift,estifhi)

    end subroutine residu_sr

    !**************
    subroutine  eldisr(ielem,nevab,nevab_dd,eldis,eldis_dd)

    integer(ink) ielem,nevab,nevab_dd,nevabsr
    real   (irk) eldis(:),eldis_dd(:)
    real   (irk),allocatable::estif21(:,:),estif22(:,:),eldis0(:,:),eldis1(:)

    nevabsr=nevab_dd-nevab
    allocate(estif21(nevabsr,nevab),estif22(nevab,nevab),  &
        eldis0(nevabsr,1),eldis1(nevabsr))
    estif22=element(ielem)%estifh(nevab+1:nevab_dd,nevab+1:nevab_dd)
    estif21=element(ielem)%estifh(nevab+1:nevab_dd,1:nevab)
    eldis_dd(1:nevab)=eldis
    eldis0(:,1)=estif21.x.eldis
    eldis0=-eldis0
    call householder(estif22,eldis0,eldis1)
    eldis_dd(nevab+1:nevab_dd)=eldis1
    deallocate(estif21,estif22,eldis0,eldis1)
    end subroutine  eldisr

    !
    subroutine bkwd_euler(ielem,matno,igaus,nstre,stres,sigC, &
        dmatx,veca2,veca3)

    !
    !---- program to update the stress through the method Backward Euler
    !
    !---- Input parameters :
    !
    !       d       : array of material constants
    !       stres   : incremental stress
    !       sigC    : stresses at t-n
    !       epC     : plastic multiplier at t-n
    !                 ( different from effective plastic strain for
    !                   Mohr-Coulomb and Drucker-Prager;
    !                   equal to effective plastic strain for
    !                   Tresca and Von Mises )
    !       tol     : tolerance factor for newton iterations
    !       nmax    : number max of iter for newtion algorithm
    !       yld     : yield control variable for gauss point
    !       nstre   : number of stress components
    !
    !---- Output parameters :
    !
    !       sigC    : stresses at t-n+1
    !       epC     : plastic multiplier at t-n+1
    !       yld     : yield control variable for gauss point
    !       effstC  : Effective stress

    integer (ink) nstre,iiters,ict, nmax, ielem, matno, igaus, ic1, ic2,icc
    real (irk)  stres(:),sigC(:),dmatx(:,:),pB,fB,epC,effstC,snorm,bring,     &
        harden,dlan,fc,pC,tol,err1,err2,dlan0,harden0,qfect,Ct,vj2,sint3
    real (irk), allocatable :: epsB(:),sigB(:),dsigB(:),aB(:),&
        dsigC(:),aC(:),daC(:,:),sigCn(:),r(:),nb(:),nc(:)
    real (irk)  veca2(:),veca3(:),theta,steff,eqstr,cons2,cons3,varj3,rot(3)
    character(20) material,criteria


    material=props(matno)%mechanical%solid%material

    sigC=element(ielem)%field(1)%gpvar0(1:nstre,igaus)

    if (material(1:7)=='ELASTIC')    then
        element(ielem)%field(1)%gpvar(1:nstre,igaus)= sigC+stres
        sigC=element(ielem)%field(1)%gpvar(1:nstre,igaus)
        return
    endif

    epC=element(ielem)%field(1)%gpvar0(nstre+1,igaus)


    if (material=='CLASSICALEP') then
        criteria=props(matno)%mechanical%solid%classicalEP%criteria
        if (criteria=='MCJOINT')then
            rot(1:ndimn)=element(ielem)%rotation(1,:)
            snorm=element(ielem)%field(1)%ntstress(1,igaus)
        endif
    endif

    tol=1.e-5 ! Should be input parameter = Newton-R tolerance
    nmax=20  ! Should be input parameter = Newton-R miter

    allocate (epsB(nstre),sigB(nstre),dsigB(nstre),aB(nstre), &
        dsigC(nstre),aC(nstre),daC(nstre,nstre),sigCn(nstre),  &
        r(nstre),nb(nstre),nc(nstre))

    sigB = sigC + stres

    !
    !---- compute the yield state at B
    !
    CALL INVART (matno,nstre,dsigB,SigB,THETA,STEFF,pB,vj2,varj3,sint3,rot)
    call YIELDS (THETA,Pb,STEFF,EQSTR,epC,effstC,matno,snorm)
    if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
    fB=eqstr-effstC
    dlan=0.0                      !! Li
    !     write(chkunit,*)'istep=',istep,'iiter=',iiter,'igaus=',igaus
    !     write(chkunit,*)'eqstr=',eqstr,'effstc=',effstc,'fb/effstc=',fb/effstc

    !
    !---- compute plasticity solution state
    !
    if  (fB/effstc >-1.e-5) then

        !
        !---- compute plasticity solution state
        !
        !         yld = 1.00
        iiters = 0
        !
        !----    compute vector normal to yield surface
        !
        CALL FLOWFQ (pb,aB,dsigB,THETA,STEFF,nb,NSTRE,matno,     &
            varj3,cons2,cons3,veca2,veca3, effstC,epC,rot,snorm)
        call hardsmodu(matno,epC,harden0,steff,theta,pB,effstc)
        icc=0
        if (material=='CONCRETE')then
            icc=1
            Ct =props(matno)%mechanical%solid%Concrete%Ct
        endif

        call effective_strain(nstre,nb,qfect,icc,Ct)
        harden=harden0*qfect

        !
        !---- Copy aB to aC and dsigB to dsigC
        !
        nc = nB
        aC = aB
        pc=pb
        dsigC = dsigB
        !
        !----    compute plastic strain increment ( update type 1 )
        !
        call calcdlan1(dlan,fB,dmatx,aB,nB,harden,nstre)     !PM

        call effective_strain(nstre,nb,qfect,icc,Ct)
        epC=epC+dlan*qfect
        !
        !----    Plastic update of stress vector (Return to yield surface)
        !----    sigmaC = sigmaB - D . a . Dland
        !
        sigC = sigB - dlan*(dmatx.x.nb)


        ict=0

        do while (ict.eq.0)

            iiters = iiters + 1

            if  (iiters.ne.1) then

                if  (iiters >  nmax) then
                    Print *,'Maximum number of stress update iterations exceded'
                    write(chkunit,*)'Max. number of stress update iterations exceded'
                    stop
                endif
                !
                !----      compute derivative of normal vector
                !
                call dadsig (pc,dsigC,THETA,STEFF,NSTRE,                           &
                    matno,   varj3,veca2,veca3,effstC, cons2,          &
                    cons3,   daC, epC,rot)
                !
                !----      compute plastic strain increment ( update type 2 )
                !          along with the corresponding plastic updade of the stress vector


                dlan0=dlan
                call calcdlan2(dlan,sigC,fC,aC,nC,daC,r,dmatx,harden,nstre)
                epC=epC+(dlan-dlan0)*qfect
            endif
            !
            !---- compute deviatoric and volumetric components of sigmaC
            !

            CALL INVART (matno,nstre,dsigC,SigC,THETA,STEFF,pC,vj2,varj3,sint3,rot)
            call YIELDS (THETA,pC,STEFF,EQSTR,epC,effstC,matno,snorm)
            if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
            fC=eqstr-effstC
            !
            !----     compute vector normal to yield surface at C
            !
            CALL FLOWFQ (pc,aC,dsigC,THETA,STEFF,nC,NSTRE,matno,      &
                varj3,cons2,cons3,veca2,veca3, effstC, epC, rot,snorm)
            !                                                                 !PM
            !----     compute residual
            !
            call hardsmodu(matno,epC,harden0,steff,theta,pC,effstc)

            call effective_strain(nstre,nC,qfect,icc,Ct)
            harden=harden0*qfect



            SigCn=dmatx.x.nC
            sigCn = sigB -dlan*sigCn
            r = sigC - sigCn
            !
            !----  Check convergence
            !
            call checkconv(r,sigC,tol,err1,ic1,fC,effstC,tol,err2,ic2,ict)

            if (iiters>=nmax)ict=1    !! Li
            !      write(chkunit,*)'iiters=',iiters,'fc=',fc,'eqstr=',eqstr,'effstc=',effstc

        enddo

        BRING=1.0
        if (EQSTR.GT.effstc) BRING=effstc/EQSTR
        sigC=bring*sigC
        EFFSTC=BRING*EQSTR
    else

        sigC = sigB
        !       yld  = 0.0_irk
        epc  = 0.0_irk
        !       effstc  = 0.0_irk

    endif
    element(ielem)%field(1)%gpvar(1:nstre,igaus)=sigC
    element(ielem)%field(1)%gpvar(nstre+1,igaus)=epC
    element(ielem)%field(1)%gpvar(nstre+2,igaus)=dlan   !!yld--->dlan
    element(ielem)%field(1)%gpvar(nstre+3,igaus)=effstC

    deallocate (epsB,sigB,dsigB,aB,dsigC,aC,daC,sigCn,r,nB,nC)

    end subroutine bkwd_euler
    !
    !***************************************
    subroutine bkwd_euler_check

    integer (ink) nstre,iiters,ict, nmax,  ic1, ic2
    real (irk)  stres(2),sigC(2),dmatx(2,2),fB,epC,   &
        d(8),dlan,yld,fc,tol,err1,err2
    real (irk) sigB(2),aB(2),nc(2),nb(2),        &
        aC(2),daC(2,2),sigCn(2),r(2)
    real (irk)  steff,effst
    !      character(20) material

    tol=0.001 ! Should be input parameter = Newton-R tolerance
    nmax=20  ! Should be input parameter = Newton-R miter
    nstre=2


    sigC(1)=120;sigC(2)=-80.;stres(1)=280.;stres(2)=280.;
    dmatx=0.0;dmatx(1,1)=2.e5;dmatx(2,2)=2.e5;
    d=0.0    ;epc=0.0
    sigB = sigC + stres
    !      call calcdevol(sigB,dsigB,pB)             !PM

    !
    !---- compute the yield state at B
    !
    !      call calcf(fB,dsigB,pB,epC,effstC,d)     !PM
    fB=sqrt(sigB(1)**2+sigb(2)**2-sigB(1)*sigB(2))-200.
    !
    !---- compute plasticity solution state
    !
    if  (fB >0.0) then
        !
        !---- compute plasticity solution state
        !
        yld = 1.00
        iiters = 0
        !
        !----    compute vector normal to yield surface
        !
        !         call calca(aB,dsigB,d)                 !PM
        aB(1)=.5*(2*sigB(1)-sigB(2))/sqrt(sigB(1)**2+sigb(2)**2-sigB(1)*sigB(2))
        aB(2)=.5*(2*sigB(2)-sigB(1))/sqrt(sigB(1)**2+sigb(2)**2-sigB(1)*sigB(2))
        !
        !---- Copy aB to aC and dsigB to dsigC
        !
        aC = aB
        nC = nB
        !
        !----    compute plastic strain increment ( update type 1 )
        !
        call calcdlan1(dlan,fB,dmatx,aB,nB,d(6),nstre)     !PM
        !
        sigC = sigB - dlan*(dmatx.x.nC)

        ict=0

        do while (ict.eq.0)

            iiters = iiters + 1

            if  (iiters.ne.1) then
                !
                !----      compute derivative of normal vector
                !
                !           call calcda(dsigC,daC,nstre)                              !PM
                steff=sqrt(sigC(1)**2+sigC(2)**2-sigC(1)*sigC(2))
                daC(1,1)=1./steff-.25*(2*sigc(1)-sigc(2))**2/steff**3
                dac(1,2)=-.5/steff-.25*(2.*sigc(1)-sigc(2))*(2*sigc(2)-sigC(1))/steff**3
                daC(2,2)=1./steff-.25*(2*sigc(2)-sigc(1))**2/steff**3
                daC(2,1)=daC(1,2)

                !         print *,'dadsig***'
                !
                !----      compute plastic strain increment ( update type 2 )
                !          along with the corresponding plastic updade of the stress vector

                call calcdlan2(dlan,sigC,fC,aC,nC,daC,r,dmatx,d(6),nstre)
                !         print *,'calcdlan2**'

            endif
            !
            !---- compute deviatoric and volumetric components of sigmaC
            !
            !          call calcdevol(sigC,dsigC,pC)                             !PM
            !
            !----     compute vector normal to yield surface at C
            !
            !          call calca(aC,dsigC,d)                                !PM
            !                                                                 !PM
            aC(1)=.5*(2*sigC(1)-sigC(2))/sqrt(sigC(1)**2+sigC(2)**2-sigC(1)*sigC(2))
            aC(2)=.5*(2*sigC(2)-sigC(1))/sqrt(sigC(1)**2+sigC(2)**2-sigC(1)*sigC(2))
            !----     compute residual
            !
            SigCn=dmatx.x.aC
            sigCn = sigB -dlan*sigCn
            r = sigC - sigCn
            write(chkunit,*)'sigc=',sigc
            write(chkunit,*)'sigcn=',sigcn

            !          if(iiters==5)stop
            !          print *,'r=',r,'eqstr=',eqstr,'effstc=',effstc,'fc=',fc
            !
            !----     compute the yield state at C
            !
            !         call calcf(fC,dsigC,pC,epC,effstC,d)                    !PM
            !
            fC=sqrt(sigC(1)**2+sigC(2)**2-sigC(1)*sigC(2))-200.

            !----  Check convergence
            !
            write(chkunit,*)'r=',r,'fc=',fc,'dlan=',dlan
            write(chkunit,*)'ac2=',ac

            effst=200.
            call checkconv(r,sigC,tol,err1,ic1,fC,effst,tol,err2,ic2,ict)
            !         write(chkunit,*)'err1=',err1,'err2=',err2
            if (iiters>=nmax)ict=1    !! Li

        enddo
    endif
    stop

    end subroutine bkwd_euler_check

    subroutine checkconv(r,sig,tol1,err1,ic1,f,effst,tol2,err2,ic2,ict)
    implicit none
    integer (ink) ict,ic1,ic2,iz
    real (irk) r(:),sig(:),tol1,err1,f,effst,tol2,err2,rn,sn

    iz=size(r)
    if (iz==1) then
        rn =abs(r(1))
        sn =abs(sig(1))
    else
        rn =   tnorm(r)
        sn =   tnorm(sig)
    endif
    err1 =  rn/sn

    err2 = f / effst

    ic1=0_ink
    ic2=0_ink
    ict=0_ink

    if  (abs(err1).le.tol1) ic1=1_ink
    if  (abs(err2).le.tol2) ic2=1_ink
    !      write(chkunit,*)'err1=',err1,'err2=',err2
    !      if (ic1 == 1_ink.and.ic2 == 1_ink) ict=1_ink
    if  (ic2 == 1_ink) ict=1_ink
    end subroutine checkconv



    SUBROUTINE FWDS_EULER(ielem,matno,igaus,nstre,stres,strsg, &
        SPtype,index,stran,dmatx,veca2,veca3, &
        igroup,gpcod)

    character(10) SPtype
    character(20) material,criteria
    character(10)  model,name
    integer(ink) matno,igaus,mstep,nstre,ielem,jstep,first,ic,icc,icr,isat,kind_wt,uplift_ic
    integer(ink) order_int,kload,ntest,istr1,ndiv,index,igroup,humidification,bline,eline
    real   (irk) epstn, effst, theta, steff, smean, vj3,vj2,sint3,       &
        eqstr, preys, escur, rfact, astep,curconfining,sv,sa,     &
        reduc, agash, bring, uniax, dlamd,curSlevel,     &
        abeta,curys,eps, cons2,cons3,qfect,Ct,damage0
    real   (irk) pwatr,satur,bulks,bulkd,bioal,bioac,dmatx(:,:),stran(:),ppp
    real   (irk) stres(:), strsg(:), sgtot(nstre),veca2(:),veca3(:)
    real   (irk) devia(nstre), avect(nstre), avecq(nstre),     &
        dvect(nstre), dvecq(nstre)
    real   (irk),allocatable::d(:),sigma(:),vdval(:),strsg0(:),evk(:)
    real   (irk) harden0,hards,rot(3),gpcod(:)
    real   (irk) s,smax,qmax,et,vt,phi,density,snorm,ft,yld,p0,px,ratio
    real   (irk),pointer::rr(:,:)


    eps=-1.e-3
    material=props(matno)%mechanical%solid%material
    name=props(matno)%name



    !      material_select: select case(material)
    if(material=='PLANE_LOWFT')then
        strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)
        allocate(strsg0(size(strsg)))  !806
        !		if(type_load=='LOAD2') &   !806
        strsg0=element(ielem)%field(1)%gpvar0(1:nstre,igaus) !806
        if(type_load/='LOAD2'.and.type_nl==4)strsg0=strsg !806
        stres=matmul(dmatx,stran)
        strsg=strsg0+stres
        element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg  !储存局部坐标下应力
        call  stres_local_to_global(strsg,element(ielem)%rotation)
        deallocate(strsg0)

    elseif (material(1:7)=='ELASTIC'.and.material/='ELASTIC_EP')   then !ep2010
        if (name/='NSTOKS') then  !nstoks

            if(type_load/='LOAD2'.and.type_nl==4)then   !20210913
                element(ielem)%field(1)%gpvar(1:nstre,igaus)=                        &
                    element(ielem)%field(1)%gpvar(1:nstre,igaus)+stres
            else !20210913
                element(ielem)%field(1)%gpvar(1:nstre,igaus)=                        &
                    element(ielem)%field(1)%gpvar0(1:nstre,igaus)+stres

            endif

        else
            element(ielem)%field(1)%gpvar(1:nstre,igaus)=stres
        endif
        strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)

        return
    elseIF(material=='ELASTIC_EP')THEN !ep2010

        if(iiter==1)then
            element(ielem)%field(1)%sigz(igaus)=element(ielem)%field(1)%gpvar(ndimn,igaus)+stres(ndimn)
            stres=0
        endif
        element(ielem)%field(1)%gpvar(1:nstre,igaus)=element(ielem)%field(1)%gpvar(1:nstre,igaus)+stres
        strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)
        return
    else if(material=='GOODMAN') then

        model=props(matno)%mechanical%solid%goodman%model
        if(model=='FCM')then
            call FCM_KS(matno,ielem,igaus,stran)
            strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            !20231215_YL
        elseif(model=='JANBU'.or.model=='EQUBOLT'.or.model=='WATERTIGHT')then  !20210913
            !20231215_YL
            !20231215_YL
            Ft    =props(matno)%mechanical%solid%Goodman%Ft
            strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            allocate(strsg0(size(strsg)))  !806
            strsg0=element(ielem)%field(1)%gpvar0(1:nstre,igaus) !806
            if(type_load/='LOAD2'.and.type_nl==4)strsg0=strsg !806
            sgtot=strsg
            allocate(evk(ndimn))
            evk=element(ielem)%evk(:,igaus)
            sgtot=strsg0+evk*stran   !202501
            !write(7,*)'idiv=',idiv,'ie=',ielem,'ig=',igaus,'evk=',evk,'stran=',stran,'sgtot=',sgtot

            strsg=sgtot
            element(ielem)%field(1)%gpvar(1:nstre,igaus)=sgtot
            deallocate(strsg0,evk)
        endif
        return
    else if(material=='DUNCANCHANG')     then
        strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)
        allocate(strsg0(size(strsg)))  !806
        strsg0=element(ielem)%field(1)%gpvar0(1:nstre,igaus) !806
        if(type_load/='LOAD2'.and.type_nl==4)strsg0=strsg !806

        et=element(ielem)%field(1)%gpvar(3+nstre,igaus)
        vt=element(ielem)%field(1)%gpvar(4+nstre,igaus)

        if(ninistn==1)then !20231215YL
            et=element(ielem)%stres0(nstre+3,Igaus)
            vt=element(ielem)%stres0(nstre+4,Igaus)
        endif  !20231215YL

        call ecmat ( SPtype,dmatx,et,vt)
        stres=matmul(dmatx,stran)
        strsg=strsg0+stres
        deallocate(strsg0)
        element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg

        return
    elseif(material=='CLASSICALEP'.or.material=='CONCRETE') then
        if (material=='CLASSICALEP') then
            uniax=props(matno)%mechanical%solid%classicalEP%sigma0
            hards=props(matno)%mechanical%solid%classicalEP%hardening
            criteria=props(matno)%mechanical%solid%classicalEP%criteria
        endif
        epstn=element(ielem)%field(1)%gpvar0(nstre+1,igaus)
        effst=element(ielem)%field(1)%gpvar0(nstre+3,igaus)
        strsg=element(ielem)%field(1)%gpvar0(1:nstre,igaus)
        yld=element(ielem)%field(1)%gpvar0(nstre+2,igaus)
        sgtot=strsg+stres


        if (ljdp/=0)then !ljdp 2010
            if(ljdp==2.and.yld/=0.)sgtot=strsg
            strsg=sgtot
            element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
        endif
        if (material=='CLASSICALEP'.and.criteria=='MCJOINT'.and.name=='CONTACT') then   !!tcl
            rot(1:ndimn)=element(ielem)%rotation(1,:) !tcl
            snorm=element(ielem)%field(1)%ntstress(1,igaus) !tcl
            call stress_change_contact(ielem,igaus,matno,sgtot,rot,epstn,effst,yld) !tcl
            strsg=sgtot !tcl
            goto 160 !tcl
        elseif(material=='CLASSICALEP'.and.criteria=='MCJOINT') then   !!new
            rot(1:ndimn)=element(ielem)%rotation(1,:)
            snorm=element(ielem)%field(1)%ntstress(1,igaus)
            !if(yld/=0.) sgtot=strsg !zhao09
            !call stress_change(ielem,igaus,matno,sgtot,rot,epstn,effst,yld)
            !strsg=sgtot
            !goto 160

        endif

        icr=0
        if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr


        if (icr/=0)then
            icc=1
            if (icr==1)then
                rr=>element(ielem)%field(1)%rr(:,:,igaus)
                call concrete_1(matno,SPtype,yld,nstre,stran,strsg,sgtot,devia,rot,rr,icc)
            else if(icr==2) then
                damage0  =element(ielem)%field(1)%gpvar0(nstre+2,igaus)
                call concrete_2(matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            else if(icr==3) then
                damage0  =element(ielem)%field(1)%gpvar0(nstre+2,igaus)

                !if(ielem==560) then
                !     write(7,*)'icr=',icr,'damage0=',damage0
                !     write(7,*)'stran=',stran
                !     write(7,*)'stres=',stres
                !     write(7,*)'strsg=',strsg
                !     write(7,*)'sgtot=',sgtot
                !endif

                call concrete_3(ielem,matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            else if(icr==5)then
                damage0  =element(ielem)%field(1)%gpvar0(nstre+2,igaus)
                !          print *, 'ielem=',ielem,'ig=',igaus
                call concrete_5(matno,nstre,damage0,yld,stran,stres,strsg,sgtot,devia,rot,icc)
            else if(icr==6)then
                !write(7,*)'ie=',ielem,'ig=',igaus,'stran=',stran,'stres=',stres
                call concrete_6(matno,nstre,ielem,igaus,stran,stres,strsg)
                !write(7,*)'ie=',ielem,'ig=',igaus,'stran=',stran,'stres=',stres,'strsg=',strsg
            endif

            !if(ielem==560) then
            !      write(7,*)'strsg=',strsg
            ! endif


            if(icr/=6)then
                element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
                if (rmesh<=0) &
                    element(ielem)%field(1)%gpvar(nstre+2,igaus)=yld
                if (rmesh>0) &
                    element(ielem)%field(1)%gpvar(nstre+3,igaus)=yld
            endif
            if (icr>=2)element(ielem)%field(1)%strain(1:nstre,igaus)=stran
            return
        endif
        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,PREYS,matno,snorm)
        if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
        ESCUR=EQSTR-PREYS

        if (rmesh>0)then
            yld=eqstr/preys
            strsg=sgtot
            goto 160
        endif

        if (epstn.ne.0.) GOTO 50
        ESCUR=EQSTR-PREYS
        if (ESCUR<=eps*preys.or.abs(eqstr-effst).le.abs(eps)) GOTO 60
        RFACT=ESCUR/(EQSTR-EFFST)
        GO TO 70
50      ESCUR=EQSTR-EFFST
        if (ESCUR/abs(effst)<=eps) GOTO 60
        RFACT=1.0
70      MSTEP=ESCUR*8.0/preys+1.0

        if (MSTEP.GT.10) MSTEP=10
        ASTEP=MSTEP
        if (epstn.ne.0.) then
            sgtot=strsg
            stres=stres/astep
        else
            rfact=escur/eqstr
            REDUC=1.0-RFACT
            stres=rfact*sgtot/astep
            sgtot=reduc*sgtot
        endif
        DO 90 JSTEP=1,MSTEP
            CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
            call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,PREYS,matno,snorm)
            if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
            CALL FLOWFQ (smean,AVECT,DEVIA,THETA,STEFF,AVECQ,NSTRE,matno,     &
                vj3,cons2,cons3,veca2,veca3, PREYS,epstn,rot,snorm)
            call hardsmodu(matno,epstn,harden0,steff,theta,smean,preys)
            icc=0
            if (material=='CONCRETE')then
                icc=1
                Ct =props(matno)%mechanical%solid%Concrete%Ct
            endif
            call effective_strain(nstre,avecq,qfect,icc,Ct)
            agash=sum(avect*stres)
            hards=harden0*qfect
            CALL FLOWPL (SPtype,ABETA,AVECT,DVECT,AVECQ,DVECQ,NSTRE,matno,hards)
            DLAMD=AGASH*ABETA
            if (abs(DLAMD)<1.e-15) DLAMD=0.0
            sgtot=sgtot+stres-dlamd*dvecq
            if (SPtype=='PS'.and.nstre==4) sgtot(nstre)=0.  !20211108
            EPSTN=EPSTN+DLAMD*qfect
90      CONTINUE
        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        call YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,CURYS,matno,snorm)
        if (nstre==1) eqstr=eqstr/sqrt(3.)  !! for VM model---->sigma-Fc=0.
        BRING=1.0
        if (EQSTR.GT.CURYS) BRING=CURYS/EQSTR
        strsg=bring*sgtot
        EFFST=BRING*EQSTR
        yld=1.
        element(ielem)%field(1)%gpvar(nstre+1,igaus)=epstn
        element(ielem)%field(1)%gpvar(nstre+3,igaus)=effst
        if(ljdp==0)element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg !ljdp 2010
        element(ielem)%field(1)%gpvar(nstre+2,igaus)=yld

        if(ljdp/=0)strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)
        return
        !**** FOR ELASTIC AND UNLODING
60      CONTINUE
        if (epstn/=0.)then
            epstn=0.
            yld=0.
        else
            strsg=sgtot
            effst=eqstr
        endif
160     continue  !!new
        if (rmesh<=0)then
            element(ielem)%field(1)%gpvar(nstre+3,igaus)=effst
            if(ljdp==0)element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
            element(ielem)%field(1)%gpvar(nstre+1,igaus)=epstn
            element(ielem)%field(1)%gpvar(nstre+2,igaus)=yld
        else if(rmesh>0)then
            element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
            element(ielem)%field(1)%gpvar(nstre+3,igaus)=yld
        endif
        if(ljdp/=0)strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus)
        return

    else if(material=='SoilPZ')    then
        allocate(d(24),vdval(6),sigma(nstre))
        order_int=elkn(index)%el_field(1)%order_intrules(1)


        if(type_nl==5)then
            strsg=element(ielem)%field(1)%gpvar0(1:nstre,igaus) !
            kload=element(ielem)%egaus(order_int)%iload0(igaus)
            vdval=element(ielem)%egaus(order_int)%vdval0(1:6,igaus)
        elseif(type_nl==4.or.type_nl==8)then
            strsg=element(ielem)%field(1)%gpvar(1:nstre,igaus) !
            kload=element(ielem)%egaus(order_int)%iload(igaus)
            vdval=element(ielem)%egaus(order_int)%vdval(1:6,igaus)
        endif

        if(type_problem=='Q')then   !20220629
            if((appear_process(igroup,iblks-1)==0.or.	 &
                (appear_process(igroup,iblks-1)==1.and.appear_process(igroup,iblks)==2))		 &
                .and.(type_nl==5.or.(type_nl==4.and.iiter==1).or.(type_nl==8.and.iiter==1))   &
                .and.iincs==1.and.istep==inc_step)then       !20220629

                sgtot=0.
                ratio=props(matno)%mechanical%solid%ratio
                density=gravy*ratio*props(matno)%mechanical%solid%density
                if(group(igroup)%fieldid=='UW')then
                    ratio=props(matno)%mechanical%fluid%ratio
                    density=density+gravy*ratio*props(matno)%mechanical%fluid%density
                endif

                p0=d(8)  !20220629
                px=(hdam(iblks)-gpcod(ndimn))*density*gravy*ratio !20220629
                if(px<p0)px=p0 !20220629
                phi  =d(1)
                sgtot(ndimn)=-px
                sgtot(1:ndimn-1)=sgtot(ndimn)*(1-SIN(phi))
                if (ndimn==2.and.SPtype(1:2)=='PE')sgtot(4)=sgtot(1)

                if(ndimn==2) then
                    element(ielem)%egaus(order_int)%vdval0(5,igaus)=-(sgtot(1)+sgtot(2)+sgtot(4))/3.
                    element(ielem)%egaus(order_int)%vdval(5,igaus) =-(sgtot(1)+sgtot(2)+sgtot(4))/3.
                else if(ndimn==3) then
                    element(ielem)%egaus(order_int)%vdval0(5,igaus)=-(sgtot(1)+sgtot(2)+sgtot(3))/3.
                    element(ielem)%egaus(order_int)%vdval(5,igaus) =-(sgtot(1)+sgtot(2)+sgtot(3))/3.
                endif   ! end if(ndimn==2) then

            else
                sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            endif  !end if((appear_process

            vdval=element(ielem)%egaus(order_int)%vdval0(1:6,igaus)

        endif   !end if(type_problem=='Q')


        d=props(matno)%mechanical%solid%SoilPZ%d
        ntest=props(matno)%mechanical%solid%SoilPZ%ntest

        ppp=element(ielem)%egaus(order_int)%vdval(5,igaus)
        if(name(1:6)=='NSSoil')then
            bulkd=ppp*props(matno)%mechanical%solid%SoilPZ%d(9)
            pwatr=element(ielem)%egaus(order_int)%pwatr(igaus)
            satur=element(ielem)%egaus(order_int)%satur(igaus)
            bulks=props(matno)%mechanical%fluid%bulks
            bioal=1.
            if(bulks.ne.0.)bioal=1.-bulkd/bulks
            if(bulkd.le.0.) bioal=1.
            if(bioal.lt.1.e-6)bioal=0.
            BIOAC=0.0
            IF(BIOAL.NE.0.0) BIOAC=(BIOAL-1.)/BIOAL
            !  write(7,*)'ig=',igaus,'pwatr=',pwatr,'satur=',satur,'bioac=',bioac,'bioal=',bioal
            DO 152 ISTR1=1,2*ndimn
                IF((ndimn.eq.3.and.istr1.le.3).or.(ndimn.eq.2.and.ISTR1.NE.3)) THEN
                    !**** compute sigma0'
                    SIGMA(ISTR1)=strsg(ISTR1)+BIOAC*(bioal*satur*pwatr)
                ELSE
                    SIGMA(ISTR1)=strsg(ISTR1)
                END IF
152         CONTINUE
        else
            sigma=strsg
        end if


        if(type_nl==5)then
            element(ielem)%field(1)%gpvar(nstre+1:2*nstre,igaus)=  &
                element(ielem)%field(1)%gpvar0(nstre+1:2*nstre,igaus)+ stran
        elseif(type_nl==4.or.type_nl==8)then
            element(ielem)%field(1)%gpvar(nstre+1:2*nstre,igaus)=  &
                element(ielem)%field(1)%gpvar(nstre+1:2*nstre,igaus)+ stran
        endif
        if(ndimn==2) then
            CALL CHANGE (STRAN)
            CALL CHANGE (SIGMA)
            CALL CHANGE (strsg)
        endif
        ! if(ielem>=245.and.ielem<=248)then
        !    write(7,*)'ig in residu=',igaus,'ie=',ielem
        !   write(7,*)'strsg=',strsg
        !write(7,*)'sigma=',sigma
        !write(7,*)'stran=',stran
        !write(7,*)'kload=',kload,'vdval0=',vdval
        !endif

        CALL TESMDL(nstre,strsg,SIGMA,STRAN,DMATX,VDVal,KLOAD,2,ndiv,ntest,d)
        element(ielem)%egaus(order_int)%vdval(1:6,igaus)=vdval
        element(ielem)%egaus(order_int)%vdval(5,igaus)=-sum(strsg(1:3))/3.
        if(ndimn==2)CALL CHANGE (strsg)
        element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
        element(ielem)%egaus(order_int)%iload(igaus)=kload
        element(ielem)%field(1)%gpvar(2*nstre+1,igaus)=vdval(1)

        deallocate(d,vdval,sigma)
        return
    else if(material=='SandPZ')    then

        allocate(d(24),vdval(6),sigma(nstre))
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        if(type_nl==5)then
            sgtot=element(ielem)%field(1)%gpvar0(1:nstre,igaus) !
            kload=element(ielem)%egaus(order_int)%iload0(igaus)
            vdval=element(ielem)%egaus(order_int)%vdval0(1:6,igaus)
        elseif(type_nl==4.or.type_nl==8)then
            sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus) !
            kload=element(ielem)%egaus(order_int)%iload(igaus)
            vdval=element(ielem)%egaus(order_int)%vdval(1:6,igaus)
        endif
        sigma=sgtot   !1017
        d=    props(matno)%mechanical%solid%SandPZ%d
        ntest=props(matno)%mechanical%solid%SandPZ%ntest

        !!!!!
        isat=0
        if(type_problem=='Q')then   !!903
            kind_wt=props(matno)%mechanical%solid%kind_wt

            if(kind_wt/=0) &
                isat=element(ielem)%field(1)%isatu(igaus)


            if((appear_process(igroup,iblks-1)==0.or.	 &
                (appear_process(igroup,iblks-1)==1.and.appear_process(igroup,iblks)==2))		 &
                .and.(type_nl==5.or.(type_nl==4.and.iiter==1))   &
                .and.iincs==1.and.istep==inc_step)then       !906

                sgtot=0.
                sigma=0.
                ratio=props(matno)%mechanical%solid%ratio
                density=gravy*ratio*props(matno)%mechanical%solid%density
                if(group(igroup)%fieldid=='UW')then
                    ratio=props(matno)%mechanical%fluid%ratio
                    density=density+gravy*ratio*props(matno)%mechanical%fluid%density
                endif

                p0=d(8)  !20220629
                px=(hdam(iblks)-gpcod(ndimn))*density*gravy*ratio !20220629
                if(px<p0)px=p0 !20220629
                phi  =d(1)
                sigma(ndimn)=-px
                sigma(1:ndimn-1)=sigma(ndimn)*(1-SIN(phi))
                if (ndimn==2.and.SPtype(1:2)=='PE')sigma(4)=sigma(1)

                if(ndimn==2) then
                    element(ielem)%egaus(order_int)%vdval0(5,igaus)=-(sigma(1)+sigma(2)+sigma(4))/3.
                    element(ielem)%egaus(order_int)%vdval(5,igaus) =-(sigma(1)+sigma(2)+sigma(4))/3.
                else if(ndimn==3) then
                    element(ielem)%egaus(order_int)%vdval0(5,igaus)=-(sigma(1)+sigma(2)+sigma(3))/3.
                    element(ielem)%egaus(order_int)%vdval(5,igaus) =-(sigma(1)+sigma(2)+sigma(3))/3.
                endif   ! end if(ndimn==2) then
                vdval=element(ielem)%egaus(order_int)%vdval0(1:6,igaus)
            endif  !end if((appear_process
        endif   !end if(type_problem=='Q')

        strsg=sgtot

        if(name(1:6)=='NSSoil')then
            pwatr=element(ielem)%egaus(order_int)%pwatr(igaus)
            satur=element(ielem)%egaus(order_int)%satur(igaus)
            bulks=props(matno)%mechanical%fluid%bulks
            bulkd=props(matno)%mechanical%fluid%bulkd

            bioal=1.
            if(bulks.ne.0.)bioal=1.-bulkd/bulks
            if(bulkd.le.0.) bioal=1.
            if(bioal.lt.1.e-6)bioal=0.
            BIOAC=0.0
            IF(BIOAL.NE.0.0) BIOAC=(BIOAL-1.)/BIOAL
            !**** compute sigma0'
            DO  ISTR1=1,2*ndimn
                IF((ndimn.eq.3.and.istr1.le.3).or.(ndimn.eq.2.and.ISTR1.NE.3)) THEN
                    SIGMA(ISTR1)=strsg(ISTR1)+BIOAC*(bioal*satur*pwatr)
                ELSE
                    SIGMA(ISTR1)=strsg(ISTR1)
                END IF
            enddo
            !	else
            !		sigma=strsg
        end if

        !	if(ndimn==2) then
        !		CALL CHANGE (STRAN)
        !		CALL CHANGE (SIGMA)
        !		CALL CHANGE (strsg)
        !	endif

        humidification=props(matno)%mechanical%solid%SandPZ%humidification
        !	if(abs(humidification)==2.and.iblks==uplift_ic.and.istep==1.and.iiter==1)then   !  在浸水时一次扣除应变
        if(abs(humidification)==2.and.iblks==uplift_ic)then   !  在浸水时一次扣除应变
            if(element(ielem)%field(1)%isatu(igaus)==1)then
                curconfining=sum(strsg(1:ndimn))/real(ndimn)
                if(ndimn==2.and.nstre==4)curconfining=(sum(strsg(1:ndimn))+strsg(4))/real(ndimn+1)
                call get_stress_level(matno,nstre,humidification,d,strsg,curSlevel)

                bline=props(matno)%mechanical%solid%SandPZ%bline(1)
                eline=props(matno)%mechanical%solid%SandPZ%eline(1)
                call get_humidification(bline,eline,curconfining,curSlevel,sa)        !插值轴应变

                bline=props(matno)%mechanical%solid%SandPZ%bline(2)
                eline=props(matno)%mechanical%solid%SandPZ%eline(2)
                call get_humidification(bline,eline,curconfining,curSlevel,sv)        !插值体应变

                if(ielem==group(igroup)%list(1).and.istep==1.and.iiter==1)then
                    write(7,'(a,3i6,10e16.8)')'igroup,ielem,igaus,sa,sv,curconfining,curSlevel,stran=',igroup,ielem,igaus,sa,sv,curconfining,curSlevel,stran
                endif

                sa=(3*sa-sv)/3.0    !由轴应变和体应变求得偏应变
                call dispatch_sa_sv(igroup,ielem,igaus,matno,nstre,strsg,sa,sv,stran)

                element(ielem)%field(1)%isatu(igaus)=2  ! 单元高斯点的湿化只考虑一次

            endif
        endif

        !   if(iblks==1.and.ielem==1)then
        !write(7,*)'ielem=',ielem,'ig=',igaus
        !write(7,*)'stran0=',stran
        !write(7,*)'strsg0=',strsg
        !write(7,*)'sigma=',sigma
        !   write(7,*)'vdval=',vdval
        !   write(7,*)'d=',d
        !endif

        CALL mainsandpz (ielem,matno,nstre,strsg,SIGMA,STRAN,DMATX,VDVal,KLOAD,2,d,ntest)

        !   if(iblks==1.and.ielem==1)then
        !write(7,*)'stran1=',stran
        !write(7,*)'strsg1=',strsg
        !endif

        !	if(ndimn==2) then
        !		CALL CHANGE (strsg)
        !		CALL CHANGE (STRAN)
        !	endif

        element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
        element(ielem)%field(1)%gpvar(2*nstre+1,igaus)=   vdval(1)
        if(type_nl==5)then
            element(ielem)%field(1)%gpvar(nstre+1:2*nstre,igaus)=  &
                element(ielem)%field(1)%gpvar0(nstre+1:2*nstre,igaus)+ stran
        elseif(type_nl==4.or.type_nl==8)then
            element(ielem)%field(1)%gpvar(nstre+1:2*nstre,igaus)=  &
                element(ielem)%field(1)%gpvar(nstre+1:2*nstre,igaus)+ stran
        endif
        element(ielem)%egaus(order_int)%iload(igaus)=kload
        element(ielem)%egaus(order_int)%vdval(1:6,igaus)=vdval

        deallocate(d,vdval,sigma)
        return




    end if   !!!!
    !            case default
    !            print *, 'SORRY!'
    !            print *, 'THIS MATERIAL HAVE NOT BEEN IMPLEMENTED'
    !        end select  material_select
    END SUBROUTINE FWDS_EULER


    subroutine concrete_1(matno,SPtype,yld,nstre,stran,strsg,sgtot,devia,rot,rr,icc)
    character(10) SPtype
    integer(ink) nstre,matno,icc
    real   (irk) theta,steff,smean,vj3,vj2,sint3
    real   (irk) yld,stran(:),strsg(:),sgtot(:),devia(:),rot(:),rr(:,:)
    real   (irk) a,b,c,d,Fc,sigma1,eqstr,escur,e,nu,alfa,beta,coef
    real   (irk),allocatable::sgtio(:),sgloc(:),dmatx(:,:),  &
        dmatxd(:,:),cmatx(:,:),stres(:)

    if ((rmesh>0.and.icc==1).or.(rmesh==2.and.icc==2))then
        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        A=props(matno)%mechanical%solid%Concrete%A
        B=props(matno)%mechanical%solid%Concrete%B
        C=props(matno)%mechanical%solid%Concrete%C
        D=props(matno)%mechanical%solid%Concrete%D
        Fc=props(matno)%mechanical%solid%Concrete%Fc
        sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
        eqstr=a*steff**2/Fc+b*steff+c*sigma1+3.*d*smean
        yld=eqstr/Fc
        strsg=sgtot
        return
    endif

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
    if (yld==0.)then
        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        A=props(matno)%mechanical%solid%Concrete%A
        B=props(matno)%mechanical%solid%Concrete%B
        C=props(matno)%mechanical%solid%Concrete%C
        D=props(matno)%mechanical%solid%Concrete%D
        Fc=props(matno)%mechanical%solid%Concrete%Fc
        sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
        eqstr=a*steff**2/Fc+b*steff+c*sigma1+3.*d*smean
        ESCUR=EQSTR-Fc
        if (escur>=-0.001*Fc)then
            alfa=-smean/(2.*steff/sqrt(3.)*sin(theta+2.*3.14159/3.))
            beta=(1+nu)/(1-2*nu)
            if (alfa>=beta)then
                strsg=0.01
                yld=2.
            else
                allocate(sgtio(3*(ndimn-1)),sgloc(3*(ndimn-1)))
                sgtio(1:3*(ndimn-1))=sgtot(1:3*(ndimn-1))
                call main_s_r( sgtio, sgloc(1:ndimn), rr)
                sgloc(1)=0.01
                if (alfa<=1.)then
                    yld=1.
                else
                    yld=alfa
                    sgloc=(1.-alfa/beta)*sgloc
                endif
                call stress_modify(sgloc,strsg(1:3*(ndimn-1)),rr)
                !        element(ielem)%field(1)%rr(:,:,igaus)=rr !why?
                deallocate(sgtio,sgloc)
            endif
        else
            strsg=sgtot
            yld=0.
        endif
    else if(yld<2.)then
        allocate(dmatx(nstre,nstre),dmatxd(3*(ndimn-1),3*(ndimn-1)),  &
            cmatx(3*(ndimn-1),3*(ndimn-1)),stres(3*(ndimn-1)))
        call ecmat ( SPtype,dmatx,e,nu)
        dmatxd(1:3*(ndimn-1),1:3*(ndimn-1))=dmatx(1:3*(ndimn-1),1:3*(ndimn-1))
        dmatxd(1,:)=0.01
        dmatxd(:,1)=0.01
        beta=(1+nu)/(1-2*nu)
        coef=1.
        if (yld>1.)coef=1.-yld/beta
        dmatxd=coef*dmatxd
        !        rr=element(ielem)%field(1)%rr(:,:,igaus) !why?
        call ecmat_change(dmatxd,cmatx,rr)
        stres(1:3*(ndimn-1))=matmul(cmatx,stran(1:3*(ndimn-1)))
        strsg(1:3*(ndimn-1))=strsg(1:3*(ndimn-1))+stres(1:3*(ndimn-1))
        deallocate(dmatx,dmatxd,cmatx,stres)
    end if
    if (ndimn==2.and.SPtype=='PE')strsg(nstre)=nu*(strsg(1)+strsg(2))
    end subroutine concrete_1


    subroutine concrete_2(matno,nstre,damage0,damage,stran,stres,strsg,sgtot,devia,rot,icc)
    character(10) SPtype
    integer(ink) nstre,matno,idimn,icc
    real   (irk) theta,steff,smean,vj3,vj2,sint3
    real   (irk) yld,stran(:),strsg(:),sgtot(:),devia(:),rot(:),stres(:)
    real   (irk) Fc,e,nu,alfa,beta,coef,Ct,damage0
    real   (irk) damage1,damage3,damage,ft,eft,efc,e0
    real   (irk) at,bt,alfat,c1,c2,c3,c4,ft0,stran1,xx,yy,sigma1,ep1
    real   (irk) ac,bc,alfac,fc0,stran3,sigma3,ep3
    real   (irk),allocatable::stemp(:),strem(:)

    allocate(stemp(size(stran)),strem(ndimn))

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
    Fc=props(matno)%mechanical%solid%Concrete%Fc
    Ct=props(matno)%mechanical%solid%Concrete%Ct
    !            damage0  =element(ielem)%field(1)%gpvar0(nstre+2,igaus)
    sgtot   =(1-damage0)**2*stres

    CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
    alfa=-smean/(2.*steff/sqrt(3.)*sin(theta+2.*3.14159/3.))
    beta=(1+nu)/(1-2*nu)
    stemp=stran
    stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
    call main_stran_r( stemp, strem)
    write(chkunit,*)'alfa=',alfa,'beta=',beta
    damage1=0.
    damage3=0.
    if (alfa>beta) goto 10
    at=props(matno)%mechanical%solid%Concrete%at
    bt=props(matno)%mechanical%solid%Concrete%bt
    alfat=props(matno)%mechanical%solid%Concrete%alfat
    c1=props(matno)%mechanical%solid%Concrete%t1
    c2=props(matno)%mechanical%solid%Concrete%t2
    c3=props(matno)%mechanical%solid%Concrete%t3
    c4=props(matno)%mechanical%solid%Concrete%t4
    ft0=props(matno)%mechanical%solid%Concrete%ft0
    e0=ft0/e
    ft=Fc*Ct
    eft=props(matno)%mechanical%solid%Concrete%eft
    stran1=0.
    do idimn=1,ndimn
        if (strem(idimn)>0.)then
            stran1=stran1+strem(idimn)**2
        else
            stran1=stran1+(ct*strem(idimn))**2
        endif
    end do
    stran1=sqrt(stran1)

    if ((rmesh>0.and.icc==1).or.(rmesh==2.and.icc==2))then
        damage=stran1/e0
        strsg=sgtot
        deallocate(stemp,strem)
        return
    endif

    if (stran1<e0) goto 10
    xx=stran1/eft
    if (xx<=1.)then
        yy=c1+c2*xx+c3*xx**2+c4*xx**6
    else
        yy=xx/(alfat*(xx-1)**1.7+xx)
    endif
    sigma1=yy*ft
    damage1=1.-sigma1/(e*stran1)
    !         ep1=At*((stran1-e0)/eft)**Bt
    !         damage1=1-sigma1/(e*(stran1-ep1))
    if (damage1<0.)damage1=0.
    if (damage1>=1.)damage1=1.
    write(chkunit,*)'damage1=',damage1,'xx=',xx,'sigma1=',sigma1
    if (alfa<1.) goto 20
10  continue
    ac=props(matno)%mechanical%solid%Concrete%ac
    bc=props(matno)%mechanical%solid%Concrete%bc
    alfac=props(matno)%mechanical%solid%Concrete%alfac
    c1=props(matno)%mechanical%solid%Concrete%c1
    c2=props(matno)%mechanical%solid%Concrete%c2
    c3=props(matno)%mechanical%solid%Concrete%c3
    c4=props(matno)%mechanical%solid%Concrete%c4
    fc0=props(matno)%mechanical%solid%Concrete%fc0
    e0=fc0/e
    efc=props(matno)%mechanical%solid%Concrete%efc
    stran3=0.
    do idimn=1,ndimn
        if (strem(idimn)<0.)then
            stran3=stran3+strem(idimn)**2
        endif
    end do
    stran3=sqrt(stran3)

    if ((rmesh>0.and.icc==1).or.(rmesh==2.and.icc==2))then
        damage=stran3/e0
        strsg=sgtot
        deallocate(stemp,strem)
        return
    endif

    if (stran3<e0) goto 20
    xx=stran3/efc
    if (xx<=1.)then
        yy=c1+c2*xx+c3*xx**2+c4*xx**3
    else
        yy=xx/(alfac*(xx-1)**2+xx)
    endif
    sigma3=yy*fc
    damage3=1-sigma3/(e*stran3)
    if (damage3<0.)damage3=0.
    if (damage3>=1.)damage3=1.
    write(chkunit,*)'damage3=',damage3
    !            ep3=Ac*((stran3-e0)/efc)**Bc
    !           ep3=ep3*efc
    !            damage3=1-sigma3/(e*(stran3-ep3))
20  continue


    if (alfa<1.)then
        damage=damage1
    else if(alfa>beta)then
        damage=damage3
    else
        coef=(beta-alfa)/(beta-1)
        damage=coef*damage1+(1.-coef)*damage3
    endif
    if (damage<damage0)then
        damage=damage0
    else
        damage=.5*(damage+damage0)
    endif
    strsg=(1-damage)**2*stres
    !           element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
    !           element(ielem)%field(1)%gpvar(nstre+2,igaus)=damage
    !           element(ielem)%field(1)%strain(1:nstre,igaus)=stran
    deallocate(stemp,strem)
    end subroutine concrete_2


    subroutine concrete_3(ielem,matno,nstre,damage0,damage,stran,stres,strsg,sgtot,devia,rot,icc)
    character(10) SPtype
    integer(ink) nstre,matno,idimn,icc,ielem
    real   (irk) theta,steff,smean,vj3,vj2,sint3,bb,cc,et0,a,b,c,d
    real   (irk) stran(:),strsg(:),sgtot(:),devia(:),rot(:),stres(:)
    real   (irk) Fc,e,nu,Ct,damage0,damage,stran1,estar
    real   (irk),allocatable::stemp(:)

    allocate(stemp(size(stran)))

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
    Fc=props(matno)%mechanical%solid%Concrete%Fc
    Ct=props(matno)%mechanical%solid%Concrete%Ct
    !            damage0  =element(ielem)%field(1)%gpvar0(nstre+2,igaus)

    stemp=stran
    stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
    CALL INVART (matno,nstre,DEVIA,stemp,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
    A=props(matno)%mechanical%solid%Concrete%A
    B=props(matno)%mechanical%solid%Concrete%B
    C=props(matno)%mechanical%solid%Concrete%C
    D=props(matno)%mechanical%solid%Concrete%D
    et0=ct*fc/e
    stran1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
    estar=a*steff**2/et0+b*steff+c*stran1+3.*d*smean

    if ((rmesh>0.and.icc==1).or.(rmesh==2.and.icc==2))then
        damage=estar/et0
        strsg=stres
        deallocate(stemp)
        return
    endif

    !if(ielem==560) then
    !write(7,*)'et0=',et0,'ester=',estar
    !write(7,*)'a,b,c,d=',a,b,c,d
    !write(7,*)'steff=',steff,'stran1=',stran1,'smean=',smean
    !
    !endif

    if (estar<et0)then
        damage=0.
    else
        bb=props(matno)%mechanical%solid%Concrete%bb
        cc=2.*exp(-bb*(estar-et0))-exp(-2*bb*(estar-et0))
        cc=cc*ct*fc/e/estar
        damage=1-sqrt(cc)
    endif

    if (damage<damage0)then
        damage=damage0
    else
        damage=.5*(damage+damage0)
    endif
    strsg=(1-damage)**2*stres
    deallocate(stemp)
    end subroutine concrete_3

    subroutine concrete_5(matno,nstre,damage0,damage,stran,stres,strsg,sgtot,devia,rot,icc)
    character(10) SPtype
    integer(ink) nstre,matno,igaus,ielem,idimn,icc
    real   (irk) theta,steff,smean,vj2,sint3,vj3,bb,cc,et0,a,b,c,d,a1,b1,pei
    real   (irk) stran(:),strsg(:),sgtot(:),devia(:),rot(:),stres(:)
    real   (irk) Fc,ft,e,nu,Ct,damage0,damage,stran1,estar,stran2,stran3,root3
    real   (irk),allocatable::stemp(:),strem(:)

    allocate(stemp(size(stran)),strem(ndimn))

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
    Fc=props(matno)%mechanical%solid%Concrete%Fc
    Ct=props(matno)%mechanical%solid%Concrete%Ct

    stemp=stran
    stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
    CALL INVART (matno,nstre,DEVIA,stemp,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
    !此时求出的STEFF为第二应变不变量的开方,Smean为应变张量第一不变量
    A=props(matno)%mechanical%solid%Concrete%A
    B=props(matno)%mechanical%solid%Concrete%B
    C=props(matno)%mechanical%solid%Concrete%C
    D=props(matno)%mechanical%solid%Concrete%D
    et0=ct*fc/e
    stran1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean  !最大主应变

    a1=a*steff**2
    b1=b*steff+c*stran1+3.*d*smean
    estar=0.5*(b1+sqrt(b1**2+4.*a1))  !求解二次方程得到
    !print*,et0
    if(estar<et0)then
        damage=0.
    else
        bb=props(matno)%mechanical%solid%Concrete%bb
        !print *,'estar=',estar,'et0=',et0,'bb=',bb
        cc=2.*exp(-bb*(estar-et0))-exp(-2*bb*(estar-et0))
        cc=cc*ct*fc/e/estar

        if(cc<0.)cc=0
        damage=1-sqrt(cc)
        !write(chkunit,*)'damage=',damage
    endif


    if(damage<damage0)then
        damage=damage0
    else
        damage=.5*(damage+damage0)
    endif
    !write(chkunit,*)'damage=',damage
    strsg=(1-damage)**2*stres

    deallocate(stemp)

    end subroutine concrete_5

    subroutine concrete_6(matno,nstre,ielem,igaus,stran,stres,strsg)
    character(10) SPtype
    integer(ink) nstre,matno,igaus,ielem,iload,iload0
    real   (irk) theta,steff,smean,vj3,a,b,c,d,a1,b1,ae,be,ce,de,estar0,estar,estarm,x0,y0,bb,cc,ct
    real   (irk) stran(:),strsg(:),stres(:),vj2,sint3
    real   (irk) Fc,ft0,e,damage0,damage,stran1,x1,ep,ftv,ftv0,eqstr,k0,et0,at,bt,dt,sigma1
    real   (irk),allocatable::stemp(:),strem(:),rot(:),sgtot(:),devia(:)

    allocate(stemp(nstre),strem(ndimn),devia(nstre),rot(ndimn),sgtot(nstre))
    stran=stran+element(ielem)%field(1)%strain0(1:nstre,igaus)

    !write(7,*)'ie=',ielem,'ig=',igaus,'nstre=',nstre
    ! write(7,*)'stran=',stran,'strain0=',element(ielem)%field(1)%strain0(1:nstre,igaus)
    ! write(7,*)'stres=',stres,'stres0=',element(ielem)%field(1)%gpvar0(1:nstre,igaus)

    stemp=stran
    stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
    CALL INVART (matno,nstre,DEVIA,stemp,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
    !此时求出的STEFF为第二应变不变量的开方,Smean为应变张量第一不变量
    if(Bparameter/=0.and.props(matno)%mechanical%solid%ie/=0)then !20190810
        e=xvalue(props(matno)%mechanical%solid%ie)
    else
        e=props(matno)%mechanical%solid%e !exx !
    endif

    et0=props(matno)%mechanical%solid%Concrete%et0
    fc=props(matno)%mechanical%solid%Concrete%fc
    ct=props(matno)%mechanical%solid%Concrete%ct
    ft0=fc*ct
    !at=props(matno)%mechanical%solid%Concrete%at
    !bt=props(matno)%mechanical%solid%Concrete%bt
    !dt=props(matno)%mechanical%solid%Concrete%dt


    estar0=element(ielem)%field(1)%strain0(nstre+1,igaus)
    estarm=element(ielem)%field(1)%strain0(nstre+2,igaus)

    x0=estar0/et0

    ae=2.4312243e-2
    be=6.2636003e-2
    ce=0.7661423
    de=0.2712015
    !ae=0.01*x0**6-0.003*x0**5-0.015*x0**4+0.08*x0**3-0.138*x0**2+0.1*x0-0.029
    !be=-0.433*x0**6+2.856*x0**5-6.16*x0**4+3.42*x0**3+3.388*x0**2-2.824*x0+1.017
    !ce=0.445*x0**6-2.855*x0**5+5.736*x0**4-1.93*x0**3-5.264*x0**2+3.558*x0-0.182
    !de=-.256*x0**6+1.6*x0**5-2.986*x0**4+0.322*x0**3+3.85*x0**2-2.3*x0+0.738

    stran1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean  !最大主应变

    !if(istep>=10) &
    !write(7,*)'x0=',x0,'ae,be,ce,de=',ae,be,ce,de,'stran1=',stran1
    a1=ae*steff**2
    b1=be*steff+ce*stran1+3.*de*smean
    estar=0.5*(b1+sqrt(b1**2+4.*a1))  !求解二次方程得到
    !write(7,*)'estar=',estar

    element(ielem)%field(1)%strain(1:nstre,igaus)=stran
    element(ielem)%field(1)%strain(nstre+1,igaus)=estar

    iload0=element(ielem)%field(1)%gpvar0(nstre+1,igaus)
    damage0=element(ielem)%field(1)%gpvar0(nstre+2,igaus)
    ftv0=element(ielem)%field(1)%gpvar0(nstre+3,igaus)
    !print*,et0

    write(7,*)'iload0=',iload0,'et0=',et0,'estar=',estar,'estar0=',estar0,'estarm=',estarm
    if(estar<=estar0.or.(iload0==0.and.estar<estarm))then
        ftv=ftv0-(estar0-estar)*(1-damage0)**2*e
        y0=ftv/ft0
        iload=0
    else
        !y0=(1+at)*x1-at*x1**2--->
        iload=1
        if(estar<et0)then
            damage=0.
            ftv=ft0*estar/et0
            !write(7,*)'ft0=',ft0,'ftv=',ftv
        else
            bb=props(matno)%mechanical%solid%Concrete%bb
            !print *,'estar=',estar,'et0=',et0,'bb=',bb
            cc=2.*exp(-bb*(estar-et0))-exp(-2*bb*(estar-et0))
            ftv=cc*ct*fc
            cc=cc*ct*fc/e/estar

            if(cc<0.)cc=0.
            damage=1-sqrt(cc)
            !write(chkunit,*)'damage=',damage
        endif

        y0=ftv/ft0
        write(7,*)'ftv=',ftv,'ft0=',ft0,'y0=',y0,'damage=',damage

        !     x0=estar/et0
        !if(x0<=1.)then
        !     y0=x0/(0.8*(1-x0)**1.8+x0)
        !         else
        !     y0=x0/(1.2*(1-x0)**2+x0)
        !         endif
        !     ftv=y0*ft0
        !     x1=((1+at)+sqrt((1+at)**2-4.*at*y0))/(2*at)
        !     x1=log(x1)
        !     ep=-x1/bt
        !     damage=1-exp(-dt*ep)
    endif

    element(ielem)%field(1)%gpvar(nstre+1,igaus)=iload
    element(ielem)%field(1)%gpvar(nstre+2,igaus)=damage
    element(ielem)%field(1)%gpvar(nstre+3,igaus)=ftv
    if(iload0==1.and.iload==0)element(ielem)%field(1)%strain(nstre+2,igaus)=estarm

    sgtot=stres+element(ielem)%field(1)%gpvar0(1:nstre,igaus)

    k0=1.
    if(iload==1.and.estar>et0)then
        CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
        Fc=props(matno)%mechanical%solid%Concrete%Fc
        A=props(matno)%mechanical%solid%Concrete%A
        B=props(matno)%mechanical%solid%Concrete%B
        C=props(matno)%mechanical%solid%Concrete%C
        D=props(matno)%mechanical%solid%Concrete%D
        Fc=y0*props(matno)%mechanical%solid%Concrete%Fc
        sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
        eqstr=a*steff**2/Fc+b*steff+c*sigma1+3.*d*smean
        k0=Fc/eqstr
    endif
    strsg=k0*sgtot
    element(ielem)%field(1)%gpvar(1:nstre,igaus)=strsg
    !write(7,*)'k0=',k0,'sgtot=',sgtot
    deallocate(stemp,strem,devia,rot,sgtot)

    end subroutine concrete_6

    subroutine concrete_6x(matno,nstre,ielem,igaus,stran,stres,strsg)
    character(10) SPtype
    integer(ink) nstre,matno,igaus,ielem,iload,iload0
    real   (irk) theta,steff,smean,vj3,a,b,c,d,a1,b1,ae,be,ce,de,estar0,estar,estarm,x0,y0
    real   (irk) stran(:),strsg(:),stres(:),vj2,sint3
    real   (irk) Fc,ft0,e,damage0,damage,stran1,x1,ep,ftv,ftv0,eqstr,k0,et0,at,bt,dt,sigma1
    real   (irk),allocatable::stemp(:),strem(:),rot(:),sgtot(:),devia(:)

    allocate(stemp(nstre),strem(ndimn),devia(nstre),rot(ndimn),sgtot(nstre))
    stran=stran+element(ielem)%field(1)%strain0(1:nstre,igaus)

    stemp=stran
    stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
    CALL INVART (matno,nstre,DEVIA,stemp,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
    !此时求出的STEFF为第二应变不变量的开方,Smean为应变张量第一不变量
    if(Bparameter/=0.and.props(matno)%mechanical%solid%ie/=0)then !20190810
        e=xvalue(props(matno)%mechanical%solid%ie)
    else
        e=props(matno)%mechanical%solid%e !exx !
    endif

    et0=props(matno)%mechanical%solid%Concrete%et0
    ft0=props(matno)%mechanical%solid%Concrete%fc*props(matno)%mechanical%solid%Concrete%ct
    at=props(matno)%mechanical%solid%Concrete%at
    bt=props(matno)%mechanical%solid%Concrete%bt
    dt=props(matno)%mechanical%solid%Concrete%dt


    estar0=element(ielem)%field(1)%strain0(nstre+1,igaus)
    estarm=element(ielem)%field(1)%strain0(nstre+2,igaus)

    x0=estar0/et0
    ae=0.01*x0**6-0.003*x0**5-0.015*x0**4+0.08*x0**3-0.138*x0**2+0.1*x0-0.029
    be=-0.433*x0**6+2.856*x0**5-6.16*x0**4+3.42*x0**3+3.388*x0**2-2.824*x0+1.017
    ce=0.445*x0**6-2.855*x0**5+5.736*x0**4-1.93*x0**3-5.264*x0**2+3.558*x0-0.182
    de=-.256*x0**6+1.6*x0**5-2.986*x0**4+0.322*x0**3+3.85*x0**2-2.3*x0+0.738

    stran1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean  !最大主应变

    a1=ae*steff**2
    b1=be*steff+ce*stran1+3.*de*smean
    estar=0.5*(b1+sqrt(b1**2+4.*a1))  !求解二次方程得到

    element(ielem)%field(1)%strain(1:nstre,igaus)=stran
    element(ielem)%field(1)%strain(nstre+1,igaus)=estar

    iload0=element(ielem)%field(1)%gpvar0(nstre+1,igaus)
    damage0=element(ielem)%field(1)%gpvar0(nstre+2,igaus)
    ftv0=element(ielem)%field(1)%gpvar0(nstre+3,igaus)
    !print*,et0

    if(estar<=estar0.or.(iload0==0.and.estar<estarm))then
        ftv=ftv0-(estar0-estar)*(1-damage0)*e
        y0=ftv/ft0
        iload=0
    else
        !y0=(1+at)*x1-at*x1**2--->
        iload=1
        x0=estar/et0
        if(x0<=1.)then
            y0=x0/(0.8*(1-x0)**1.8+x0)
        else
            y0=x0/(1.2*(1-x0)**2+x0)
        endif
        ftv=y0*ft0
        x1=((1+at)+sqrt((1+at)**2-4.*at*y0))/(2*at)
        x1=log(x1)
        ep=-x1/bt
        damage=1-exp(-dt*ep)
    endif

    element(ielem)%field(1)%gpvar(nstre+1,igaus)=iload
    element(ielem)%field(1)%gpvar(nstre+2,igaus)=damage
    element(ielem)%field(1)%gpvar(nstre+3,igaus)=ftv
    if(iload0==1.and.iload==0)element(ielem)%field(1)%strain(nstre+2,igaus)=estarm

    sgtot=stres+element(ielem)%field(1)%gpvar0(1:nstre,igaus)
    CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
    Fc=props(matno)%mechanical%solid%Concrete%Fc
    A=props(matno)%mechanical%solid%Concrete%A
    B=props(matno)%mechanical%solid%Concrete%B
    C=props(matno)%mechanical%solid%Concrete%C
    D=props(matno)%mechanical%solid%Concrete%D
    Fc=y0*props(matno)%mechanical%solid%Concrete%Fc
    sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
    eqstr=a*steff**2/Fc+b*steff+c*sigma1+3.*d*smean
    k0=Fc/eqstr
    strsg=k0*sgtot
    deallocate(stemp,strem,devia,rot,sgtot)

    end subroutine concrete_6x

    subroutine main_s_r( stemp, strem, rr)
    !
    !      obtain the main strain or stress and corresponding directions
    !
    integer(ink) im,i1,i2,i,ijc(3)
    real   (irk) devia(6), stemp(:), strem(:), rr(:,:)
    real   (irk) root3,pei,smean,varj2,varj3,steff,sint3,theta,alfa
    real   (irk) a1,a2,a,fj,abs,delta

    if (ndimn==2) then
        delta=sqrt((stemp(1)-stemp(2))**2/4+stemp(3)**2)
        strem=0.
        if (delta.lt.1.e-5) return
        strem(1)=(stemp(1)+stemp(2))/2.+delta
        strem(2)=(stemp(1)+stemp(2))/2.-delta
        alfa=atan((strem(1)-stemp(1))/stemp(3))
        rr(1,1)=cos(alfa)
        rr(1,2)=sin(alfa)
        rr(2,1)=-sin(alfa)
        rr(2,2)=cos(alfa)
        return
    endif

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
    !     write(chkunit,*)'main stress(1-3)=',strem
    !   write(chkunit,*)'stemp=',stemp(1:3)

    ijc=0
    do 10 im=1,3
        do    i=1,3
            rr(im,i)=0.
        end do
        do i=1,3
            if (abs(strem(im)-stemp(i)).lt.1.e-3.and.ijc(i)==0) then
                rr(im,i)=1.
                ijc(i)=1
                goto 10
            end if
        end do
        do 20 i=1,3
            i1=i+1
            i2=i+2
            if (i1.gt.3)i1=i1-3
            if (i2.gt.3)i2=i2-3
            fj=stemp(3+i2)*(stemp(i1)-strem(im))-stemp(3+i1)*stemp(3+i)
            if (abs(fj).ge.1.e-5) then
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
    end subroutine main_s_r

    !
    subroutine stress_change(ielem,igaus,matno,sgtot,rot,epstn,effst,yld)
    real    (irk) epstn,effst,yld,sgtot(:),rot(:)
    real    (irk),allocatable:: rr(:,:),rr0(:,:),tt(:,:),sgloc(:),tt0(:,:),tti(:,:)
    real    (irk) sigman,sigmat,sigmatn,uniax,frict,eqstr,ft
    integer (ink)   igaus,idimn,jdimn,ielem,matno,csigma0

    allocate(rr0(ndimn,ndimn),rr(ndimn+1,ndimn+1),tt(3*(ndimn-1),3*(ndimn-1)),  &
        sgloc(3*(ndimn-1)),tti(3*(ndimn-1),3*(ndimn-1)))

    call direct(rot,rr0,ndimn)

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
    !  write(chkunit,*)'ielem=',ielem,'igaus=',igaus
    !    write(chkunit,*)'sgloc=',sgloc
    sigman=sgloc(ndimn)
    if (ndimn==2) then
        sigmat=abs(sgloc(3))
    elseif(ndimn==3) then
        sigmat=sqrt(sgloc(5)**2+sgloc(6)**2)
    endif

    sigmatn=sigmat
    if (yld/=0.) goto 10
    epstn=0.
    yld=0.

    csigma0   =props(matno)%mechanical%solid%classicalEP%csigma0
    if (csigma0==999) goto 10
    uniax   =props(matno)%mechanical%solid%classicalEP%sigma0
    ft=props(matno)%mechanical%solid%classicalEP%ft
    frict=props(matno)%mechanical%solid%classicalEP%frict_angle
    EQSTR=sigmat+tand(frict)*sigman-uniax

    if (sigman>=ft) then
        sgtot=0.
        epstn=1.
        yld=2.
        sigman=0.
        sigmatn=0.
    elseif(eqstr>0.)then
        sigmatn=-tand(frict)*sigman+uniax
        if (sigmatn<0.)sigmatn=0.
        if (ndimn==2)then
            sgloc(3)=sign(sigmatn,sgloc(3))
        elseif(ndimn==3) then
            sgloc(5:6)=sigmatn*sgloc(5:6)/sigmat
        endif
        sgtot=tti.x.sgloc
        epstn=1.
        yld=1.
    endif
    sgloc=tt.x.sgtot

10  continue
    effst=sigmatn
    element(ielem)%field(1)%ntstress(1,igaus)=sigman
    element(ielem)%field(1)%ntstress(2,igaus)=sigmatn
    deallocate(rr,rr0,tt,sgloc,tti)
    end subroutine stress_change
    !!!!!!!!!!!!!

    !
    subroutine stress_change_contact(ielem,igaus,matno,sgtot,rot,epstn,effst,yld) !tcl
    real    (irk) epstn,effst,yld,sgtot(:),rot(:)
    real    (irk),allocatable:: rr(:,:),rr0(:,:),tt(:,:),sgloc(:),tt0(:,:),tti(:,:)
    real    (irk) sigman,sigmat,sigmatn,uniax,frict,eqstr,ft
    integer (ink)   igaus,idimn,jdimn,ielem,matno,csigma0

    allocate(rr0(ndimn,ndimn),rr(ndimn+1,ndimn+1),tt(3*(ndimn-1),3*(ndimn-1)),  &
        sgloc(3*(ndimn-1)),tti(3*(ndimn-1),3*(ndimn-1)))

    call direct(rot,rr0,ndimn)

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
    sigman=sgloc(ndimn)
    if (ndimn==2) then
        sigmat=abs(sgloc(3))
    elseif(ndimn==3) then
        sigmat=sqrt(sgloc(5)**2+sgloc(6)**2)
    endif

    !  write(7,*)'ie=',ielem,'ig=',igaus,'sgloc=',sgloc

    sigmatn=sigmat

    csigma0   =props(matno)%mechanical%solid%classicalEP%csigma0
    if (csigma0==999) goto 10
    uniax   =props(matno)%mechanical%solid%classicalEP%sigma0
    ft=props(matno)%mechanical%solid%classicalEP%ft
    frict=props(matno)%mechanical%solid%classicalEP%frict_angle
    EQSTR=sigmat+tand(frict)*sigman-uniax

    epstn=0.
    yld=0.
    if (eqstr>0.)then
        sigmatn=-tand(frict)*sigman+uniax
        if (sigmatn<0.)sigmatn=0.
        if (ndimn==2)then
            sgloc(3)=sign(sigmatn,sgloc(3))
        elseif(ndimn==3) then
            sgloc(5:6)=sigmatn*sgloc(5:6)/sigmat
        endif
        sgtot=tti.x.sgloc
        !    write(7,*)'sigmatn=',sigmatn,'sgloc=',sgloc
        !    write(7,*)'sgtot=',sgtot
        epstn=1.
        yld=1.
    endif
    !     sgloc=tt.x.sgtot

10  continue
    effst=sigmatn
    element(ielem)%field(1)%ntstress(1,igaus)=sigman
    element(ielem)%field(1)%ntstress(2,igaus)=sigmatn
    deallocate(rr,rr0,tt,sgloc,tti)
    end subroutine stress_change_contact  !tcl


    !***
    subroutine stress_modify(sgloc,sgtot,rr0)
    real    (irk) sgtot(:),sgloc(:),rr0(:,:)
    real    (irk),allocatable::tti(:,:),rr(:,:)
    integer (ink) idimn,jdimn

    allocate(rr(ndimn+1,ndimn+1))
    rr(1:ndimn,1:ndimn)=rr0
    rr(1:ndimn,ndimn+1)=rr(1:ndimn,1)
    rr(ndimn+1,1:ndimn)=rr(1,1:ndimn)
    rr(ndimn+1,ndimn+1)=rr(1,1)


    allocate(tti(3*(ndimn-1),3*(ndimn-1)))
    tti=0.
    tti(1:ndimn,1:ndimn)=(transpose(rr0))**2
    if (ndimn==2) then
        tti(3,1)=rr(1,1)*rr(1,2)
        tti(3,2)=rr(2,1)*rr(2,2)
        tti(1,3)=2*rr(1,1)*rr(2,1)
        tti(2,3)=2*rr(1,2)*rr(2,2)
        tti(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)
    else if(ndimn==3) then
        do idimn=1,ndimn
            do jdimn=1,ndimn
                tti(3+jdimn,idimn)=rr(idimn,jdimn)*rr(idimn,jdimn+1)
                tti(jdimn,3+idimn)=2*rr(idimn,jdimn)*rr(idimn+1,jdimn)
                tti(3+jdimn,3+idimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                    rr(idimn+1,jdimn)*rr(idimn,jdimn+1)
            end do
        end do
    endif

    sgtot=tti.x.sgloc

    deallocate(tti,rr)
    end subroutine stress_modify
    !***

    subroutine calcdlan1(dlan,f,dmatx,a,n,harden,nstre)

    integer (ink) nstre
    real (irk) dlan,dmatx(:,:),a(:),n(:),harden,ada,tt,f
    real (irk),allocatable:: v1(:)
    !
    !    compute plastic strain increment ( update type 1 )
    !
    tt = .816496580927726_irk
    allocate (v1(nstre))

    v1=dmatx.x.n
    ada=a.d.v1
    dlan  = f/(ada+harden)
    !     ep    = ep    +  dlan
    !    Strain Hardening
    !     effst = effst + d(6)/tt*dlan          ! LI
    !    Work Hardening
    !    effst = effst + d(6)/tt*dlan

    deallocate (v1)

    end  subroutine calcdlan1

    subroutine calcdlan2(dlan,sig,f,a,n,da,r,dmatx,harden,nstre)

    integer (ink) nstre
    real (irk) dlan,sig(:),a(:),da(:,:),n(:),                    &
        r(:),dmatx(:,:),harden,dl,f,tt,a1,a2
    real (irk), allocatable :: Q(:,:),v1(:,:),v2(:,:),v3(:,:)

    allocate (Q(nstre,nstre),v1(nstre,1),v2(nstre,1),v3(nstre,1))
    tt = .816496580927726_irk
    !
    !    compute plastic strain increment ( update type 2 )
    !    and the corresponding plastic stress update
    !

    !
    !    compute Q matrix and its LU decomposition
    !
    call calcQ(Q,da,dmatx,dlan,nstre)

    v3(:,1)=r

    call householder(q,v3,v1)
    v3(:,1)=dmatx.x.n
    call householder(q,v3,v2)
    a1=a.d.v1(:,1)
    a2=a.d.v2(:,1)
    dl=(f-a1)/(a2+harden)
    dlan = dlan + dl

    sig = sig - v1(:,1) - dl*v2(:,1)

    deallocate (Q,v1,v2,v3)

    end subroutine calcdlan2

    SUBROUTINE ELOAD_FIELD

    !! need the zero, firt, second deritives of the result, store in the ntotv order
    !!          result_zero, result_first, result_second
    character(10)fieldid,fieldi,special,name,material
    integer(ink) igroup, nrfields, ifield, index, ordert,idofn, matno,   &
        nevab_f, ielgroup, ielem, ikh, type_mass,ic

    integer(ink), pointer::ldofs(:),lnods(:)
    real   (irk), allocatable::value(:)
    real   (irk), pointer::fstif(:,:)
    integer(ink)  nstre !20231215YL
    real   (irk)  alfa,beta,lamda !20231215YL

    DO igroup =1,ngroup

        if (appear(igroup)>0) then
            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            special=group(igroup)%special
            index    = group(igroup)%index
            matno = group(igroup)%matno
            material=props(matno)%name
            name=props(matno)%name
            nstre=  group(igroup)%nstre !20231215YL
            alfa=group(igroup)%alfa !20231215YL
            beta=group(igroup)%beta !20231215YL

            do ifield=1,nrfields
                fieldi=fieldid(ifield:ifield)
                nevab_f = elkn(index)%el_field(ifield)%nnode_f*group(igroup)%dof(ifield)%nfdof
                allocate(value(nevab_f))
                ! loop for k(h) and m(c)

                do ikh=1,2
                    if (fieldid=='UP'.and.fieldi=='U')                                             goto 10
                    if (fieldid=='W'.and.ikh==2.and.type_problem=='Q')                             goto 10
                    if (fieldid=='W'.and.ikh==2.and.ifsnedge==0.and.type_problem=='F')             goto 10 !ifs2006 zhao, 06/03/29
                    !if (fieldi=='U'.and.ikh==1.and.group(igroup)%beta==0.)                         goto 10
                    if(fieldi=='U')then
                        if(ikh==1.and.group(igroup)%beta==0..and.props(matno)%mechanical%solid%material/='DUNCANCHANG') goto 10 !20231215YL !20240305
                    endif
                    !if(fieldi=='U'.and.ikh==2.and.name=='NSTOKS')                                 goto 10 !!nstoks
                    if (fieldi=='P'.and.ikh==1)                                                    goto 10
                    if (fieldi=='U'.and.type_problem=='Q')                                         goto 10
                    if (fieldi=='U'.and.type_problem=='S')                                         goto 10
                    if (fieldi=='W'.and.uwcpl==2.and.ikh==2.and.material/='NSSoil')                goto 10
                    !if (nrfields==1.and.fieldid=='W'.and.type_problem=='S'.and.material/='NSSoil') goto 10  !20200823
                    if (fieldi=='T'.and.type_problem=='Q'.and.ikh==2)                              goto 10


                    if (ikh==2)type_mass=group(igroup)%type_mass(ifield)

                    !ordert=elkn(index)%el_field(ifield)%order_time(ikh)
                    ordert=group(igroup)%order_time(ikh,ifield)

                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)

                        if (associated(element(ielem)%field(ifield)%khandmc(ikh)%fstif)) then
                            !20231215YL  !20240305
                            if(fieldi=='U')then
                                if(props(matno)%mechanical%solid%material=='DUNCANCHANG'.and.type_problem=='F')then !20231008
                                    lamda=sum(element(ielem)%field(1)%gpvar(nstre+1,:))/size(element(ielem)%field(1)%gpvar,dim=2)
                                    beta=lamda/base_freq
                                    alfa=lamda*base_freq
                                endif
                            endif
                            !20231215YL
                            fstif=>element(ielem)%field(ifield)%khandmc(ikh)%fstif
                            ldofs=>element(ielem)%field(ifield)%ldofs_f

                            if (fieldi=='P') value=deltafi(ldofs)

                            if (fieldi/='P') then

                                if (ordert==0) then
                                    if (fieldi=='U') then
                                        !value=result_first(ldofs)*group(igroup)%beta
                                        value=result_first(ldofs)*beta !20231215YL
                                    else
                                        value=result_zero(ldofs)
                                    endif

                                    if (kinit==2.and.allocated(prstat).and.fieldi=='W'.and.ikh==1) then    !20221014
                                        lnods=>element(ielem)%field(ifield)%lnods_f
                                        value=value-prstat(lnods)
                                        nullify(lnods)
                                    endif
                                endif

                                !if(ielem==1.or.ielem==2)write(7,*)'1ielem=',ielem,'ikh=',ikh,'ordert=',ordert

                                if (ordert==1)value=result_first(ldofs)
                                if (ordert==2)then
                                    if (fieldi=='U')then
                                        !value=result_second(ldofs)+result_first(ldofs)*group(igroup)%alfa
                                        value=result_second(ldofs)+result_first(ldofs)*alfa !20231215YL
                                        !if(ielem==1.or.ielem==2)write(7,*)'1ielem=',ielem,'result_second=',result_second(ldofs),'result_first=',result_first(ldofs),'alfa=',group(igroup)%alfa
                                    else
                                        value=result_second(ldofs)
                                    endif
                                endif

                            endif


                            ic=size(fstif,dim=2)
                            if (ic==1)then
                                do idofn=1,nevab_f
                                    element(ielem)%field(ifield)%eload(idofn)=element(ielem)%field(ifield)%eload(idofn)+  &
                                        fstif(idofn,1)*value(idofn)
                                    !write(7,*)'1ielem=',ielem,'idofn=',idofn,'eload_field=',fstif(idofn,1)*value(idofn),'value=',value(idofn)
                                end do
                            else
                                element(ielem)%field(ifield)%eload=element(ielem)%field(ifield)%eload+  &
                                    MATMUL(fstif,value)
                                !write(7,*)'2ielem=',ielem,'eload_field=',MATMUL(fstif,value),'value=',value
                            endif


                            nullify(fstif,ldofs)
                        endif

                    end do       !!ielgroup
10                  continue
                end do        !!end do ikh
                deallocate(value)
            end do     !! end do ifield
        endif
    end do     !!  for igroup


    END SUBROUTINE ELOAD_FIELD

    SUBROUTINE ELOAD_FIELD_w !freq2006

    !! need the zero, firt, second deritives of the result, store in the ntotv order
    !!          result_zero, result_first, result_second
    character(10)fieldid
    integer(ink) igroup, nrfields, ifield, index, idofn,    &
        nevab_f, ielgroup, ielem, ikh, type_mass,ic

    integer(ink), pointer::ldofs(:),lnods(:)
    complex(irk), allocatable::value(:),cstif(:,:),eload(:)
    real   (irk), pointer::fstif(:,:)
    complex(irk) coef

    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            ! get information from the group level
            index    = group(igroup)%index
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            do ifield=1,nrfields
                nevab_f = elkn(index)%el_field(ifield)%nnode_f*group(igroup)%dof(ifield)%nfdof
                allocate(value(nevab_f))
                ! loop for k(h) and m(c)
                do ikh=1,2

                    if (fieldid(ifield:ifield)=='U')then
                        if (ikh==1)coef=cmplx(1.,-ttime*group(igroup)%beta)
                        if (ikh==2)coef=-ttime*cmplx(ttime,group(igroup)%alfa)
                    elseif(fieldid(ifield:ifield)=='W') then
                        if (nrfields==2)then
                            if (ikh==1)coef=-1./cmplx(0.,ttime)  !对称性系数与自身乘积
                            if (ikh==2)coef=cmplx(1.,0.)  !对称性系数与自身乘积
                        elseif(nrfields==1)then
                            if (ikh==1)coef=-1./cmplx(ttime**2,0.)/theta1/ditime   !对称性系数与自身乘积
                            if (ikh==2)coef=cmplx(1.,0.)/theta1/ditime   !对称性系数与自身乘积
                            if (ifsnedge/=0)then !ifs2006
                                if (ikh==1)coef=cmplx(-1./ttime**2,0.)/beeta2/ditime**2
                                if (ikh==2)coef=cmplx(1.,0.)/beeta2/ditime**2
                            endif
                        endif
                    endif
                    if (ikh==2)type_mass=group(igroup)%type_mass(ifield)
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if (associated(element(ielem)%field(ifield)%khandmc(ikh)%fstif)) then

                            fstif=>element(ielem)%field(ifield)%khandmc(ikh)%fstif
                            ldofs=>element(ielem)%field(ifield)%ldofs_f
                            allocate(cstif(size(fstif,dim=1),size(fstif,dim=2)),eload(nevab_f))
                            value=resultw(ldofs)
                            cstif=fstif*coef
                            ic=size(fstif,dim=2)
                            if (ic==1)then
                                do idofn=1,nevab_f
                                    stforw(ldofs(idofn))=stforw(ldofs(idofn))+cstif(idofn,1)*value(idofn)
                                end do
                            else
                                eload=MATMUL(cstif,value)
                                stforw(ldofs)=stforw(ldofs)
                                do idofn=1,nevab_f
                                    stforw(ldofs(idofn))=stforw(ldofs(idofn))+eload(idofn)
                                end do
                            endif

                            nullify(fstif,ldofs)
                            deallocate(cstif,eload)
                        endif
                    end do       !!ielgroup
10                  continue
                end do        !!end do ikh
                deallocate(value)
            end do     !! end do ifield
        endif
    end do     !!  for igroup

    END SUBROUTINE ELOAD_FIELD_w
    !! stablize

    SUBROUTINE stabload

    character(10)fieldid
    integer(ink) igroup,ipoin,np_unode
    integer(ink), pointer::lnods(:)
    real   (irk), allocatable::value(:)
    real   (irk), pointer::fstif(:,:)
    DO igroup =1,ngroup
        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.   &
            (fieldid(1:2)=='UP'.or.fieldid(1:2)=='UW')) then
            ! get information from the group level
            do ipoin=1,group(igroup)%np_unode
                np_unode=group(igroup)%unode(ipoin)%np_unode
                if (np_unode/=0) then
                    allocate(value(np_unode))

                    fstif=>group(igroup)%unode(ipoin)%patch_sta
                    lnods=>group(igroup)%unode(ipoin)%patch_nod
                    if (type_problem=='Q') then
                        value=result_zero(nodfn(ndimn+1,lnods))
                        if (kinit==2.and.allocated(prstat))value=value-prstat(lnods)  !20221014
                    else
                        value=result_first(nodfn(ndimn+1,lnods))
                    endif


                    group(igroup)%unode(ipoin)%patch_load=fstif.x.value
                    deallocate(value)
                    nullify(fstif,lnods)
                endif
            end do       !!ipoin
        end if        !!end if appear
    end do     !!  for igroup


    END SUBROUTINE stabload
    !! end of stablize

    !! semi_infinity-space
    SUBROUTINE semi_inf_load
    integer(ink) idofn,ndofn_act
    real   (irk), allocatable::value(:),press_space(:)
    if (ground_inf/100==1)then
        ndofn_act=size(reaction_space,1)
    elseif(ground_inf/100==2)then
        ndofn_act=size(stif_inv_space,1)
    endif

    !   if(ground_inf/100==2)ndofn_act=ndofn_space
    allocate(value(ndofn_space),press_space(ndofn_act))
    value(:)=result_zero(ldofs_space(:))
    eload_space=estif_space.x.value
    if (ground_inf/100==1)then
        press_space=reaction_space.x.value
        if(allocated(load0_space))press_space=press_space-load0_space  !080621
    elseif(ground_inf/100==2)then
        press_space=stif_inv_space.x.value
    endif

    write(chkunit,*)'ground reaction pressure'
    write(chkunit,*)'ndofn_act=',ndofn_act
    if ((ground_inf-ground_inf/100*100)/10==1)then
        do idofn=1,ndofn_act
            write(chkunit,10)idofn,press_space(idofn)
        end do
    elseif((ground_inf-ground_inf/100*100)/10==2)then
        do idofn=1,ndofn_act/3
            write(chkunit,10)idofn,press_space((idofn-1)*3+1:(idofn-1)*3+3)
        end do
    endif


10  format(1x,i10,3f15.3)
    deallocate(value,press_space)

    END SUBROUTINE semi_inf_load
    !! end of semi_infinity_space
    SUBROUTINE ELOAD_COUPLE
    character(10)fieldid, fieldid1, fieldid2, name, special
    integer(ink) igroup, nrfields,  index, field1,  field2,     &
        nevab1, nevab2,  ncouple, icouple, matno,      &
        ielgroup, ielem, order_time1, order_time2,kinit_g !20211214
    real   (irk) coef
    integer(ink), allocatable::ldofs1(:),ldofs2(:),lnods2(:)
    real   (irk), allocatable::qmatx(:,:), value1(:), value2(:)

    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            index    = group(igroup)%index
            kinit_g=group(igroup)%kinit_g !20211214
            ncouple  = elkn(index)%ncouple
            matno = group(igroup)%matno
            name=props(matno)%name
            special=group(igroup)%special
            coef=1.0    !!nstoks
            if (name/='NSTOKS'.and.type_problem/='Q') then    ! coef is only for p or Pw term
                coef=theta1*ditime
                if (type_problem=='F')coef=theta1/beeta1
            endif


            do icouple=1,ncouple

                field1 =elkn(index)%couple(icouple)%field_couple(1)
                field2 =elkn(index)%couple(icouple)%field_couple(2)
                order_time1=elkn(index)%couple(icouple)%order_couple(1)
                order_time2=elkn(index)%couple(icouple)%order_couple(2)
                fieldid1=fieldid(field1:field1)
                fieldid2=fieldid(field2:field2)

                if (fieldid1/='U'.and.(fieldid2/='P'.or.fieldid2/='W')) then
                    print *, 'only u-p or u-w coupling is implemented!'
                    stop
                endif
                nevab1 = elkn(index)%el_field(field1)%nnode_f*group(igroup)%dof(field1)%nfdof
                nevab2 = elkn(index)%el_field(field2)%nnode_f*group(igroup)%dof(field2)%nfdof
                allocate(qmatx(nevab1,nevab2),ldofs1(nevab1),ldofs2(nevab2),lnods2(nevab2))
                allocate(value1(nevab1), value2(nevab2))

                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (associated(element(ielem)%cstif(icouple)%qmatx)) then

                        ldofs1=element(ielem)%field(field1)%ldofs_f
                        ldofs2=element(ielem)%field(field2)%ldofs_f
                        qmatx=element(ielem)%cstif(icouple)%qmatx

                        if (fieldid2/='P') then
                            if (uwcpl==1) then
                                if (order_time1==0)value1=result_zero(ldofs1)
                                if (order_time1==1)value1=result_first(ldofs1)
                                if (order_time1==2)value1=result_second(ldofs1)
                            endif
                            if (order_time2==0)then
                                value2=result_zero(ldofs2)
                                if (kinit_g==2.and.allocated(prstat)) then
                                    !   if(allocated(prstat)) then     !2003/10
                                    lnods2=element(ielem)%field(field2)%lnods_f
                                    value2=value2-prstat(lnods2)
                                endif
                            endif
                            if (order_time2==1)value2=result_first(ldofs2)
                            if (order_time2==2)value2=result_second(ldofs2)
                        else
                            value1=result_zero(ldofs1)
                            value2=result_zero(ldofs2)
                        endif
                        element(ielem)%field(field1)%eload=element(ielem)%field(field1)%eload+  &
                            MATMUL(qmatx,value2)
                        !write(7,*)'eload_couple1=',element(ielem)%field(field1)%eload
                        if (uwcpl==1)   &
                            element(ielem)%field(field2)%eload=element(ielem)%field(field2)%eload+  &
                            coef*MATMUL(transpose(qmatx),value1)
                        ! if (uwcpl==1)   &
                        !write(7,*)'eload_couple2=',element(ielem)%field(field2)%eload

                        !      if(special(1:1)=='B') then
                        !     call eload_couple_sr(ielem,coef)
                        !     endif
                    endif
                end do       !!ielgroup
                deallocate(qmatx, ldofs1, ldofs2, lnods2, value1, value2)
            end do        !!end do icouple
        end if    !! for do while
    end do     !!  for igroup


    END SUBROUTINE ELOAD_COUPLE

    SUBROUTINE ELOAD_COUPLE_w !freq2006
    character(10)fieldid, fieldid1, fieldid2, name, special
    integer(ink) igroup, nrfields,  index, field1,  field2,     &
        nevab1, nevab2,  ncouple, icouple, matno,      &
        ielgroup, ielem, order_time1, order_time2
    complex(irk) coef
    integer(ink), allocatable::ldofs1(:),ldofs2(:),lnods2(:)
    complex(irk), allocatable::qmatx(:,:), value1(:), value2(:)

    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            index    = group(igroup)%index
            ncouple  = elkn(index)%ncouple
            matno = group(igroup)%matno
            name=props(matno)%name
            special=group(igroup)%special

            do icouple=1,ncouple

                field1 =elkn(index)%couple(icouple)%field_couple(1)
                field2 =elkn(index)%couple(icouple)%field_couple(2)
                order_time1=elkn(index)%couple(icouple)%order_couple(1)
                order_time2=elkn(index)%couple(icouple)%order_couple(2)
                fieldid1=fieldid(field1:field1)
                fieldid2=fieldid(field2:field2)

                if (fieldid1/='U'.and.(fieldid2/='P'.or.fieldid2/='W')) then
                    print *, 'only u-p or u-w coupling is implemented!'
                    stop
                endif
                nevab1 = elkn(index)%el_field(field1)%nnode_f*group(igroup)%dof(field1)%nfdof
                nevab2 = elkn(index)%el_field(field2)%nnode_f*group(igroup)%dof(field2)%nfdof
                allocate(qmatx(nevab1,nevab2),ldofs1(nevab1),ldofs2(nevab2),lnods2(nevab2))
                allocate(value1(nevab1), value2(nevab2))

                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (associated(element(ielem)%cstif(icouple)%qmatx)) then
                        coef=cmplx(1.0,0.)

                        ldofs1=element(ielem)%field(field1)%ldofs_f
                        ldofs2=element(ielem)%field(field2)%ldofs_f

                        qmatx=coef*element(ielem)%cstif(icouple)%qmatx

                        value1=resultw(ldofs1)
                        value2=resultw(ldofs2)
                        stforw(ldofs1)=stforw(ldofs1)+MATMUL(qmatx,value2)
                        stforw(ldofs2)=stforw(ldofs2)+MATMUL(transpose(qmatx),value1)

                    endif
                end do       !!ielgroup
                deallocate(qmatx, ldofs1, ldofs2, lnods2, value1, value2)
            end do        !!end do icouple
        end if    !! for do while
    end do     !!  for igroup


    END SUBROUTINE ELOAD_COUPLE_w
    SUBROUTINE ELOAD_COUPLE_SR(ielem,coef)

    integer (ink)  ielem, aevab, np
    real (irk) coef,coef0
    real (irk) ,pointer    :: qmatxa(:,:),estifhi(:,:),alfa_first(:)
    real (irk) ,allocatable:: rho(:,:),hinvk(:,:),eload(:)

    qmatxa  => element(ielem)%qmatxa
    estifhi => element(ielem)%estifh

    aevab = size(estifhi, dim=1)
    np    = size(qmatxa , dim=2)

    coef0=1.0
    if (type_problem/='Q') then    ! coef is only for p or Pw term
        coef0=theta1/beeta1
        if (type_problem=='F')coef0=theta1/(beeta2*ditime)
    endif

    allocate(rho(aevab,1),hinvk(aevab,1),eload(np))

    rho(:,1) =-element(ielem)%rh
    call householder(estifhi,rho,hinvk)
    alfa_first=>element(ielem)%alfa_first    ! new
    eload =-coef*(transpose(qmatxa).x.alfa_first) !new
    eload =eload-(coef0* (transpose(qmatxa).x.hinvk(:,1)))


    element(ielem)%field(2)%eload=element(ielem)%field(2)%eload  &
        +eload

    deallocate(rho,hinvk,eload)
    nullify(estifhi,qmatxa,alfa_first)

    END SUBROUTINE ELOAD_COUPLE_SR

    SUBROUTINE eload_initial_stress

    character(1)field1
    character(10)SPtype,class,special,material
    integer(ink) igroup, index, nstre, nevab,  nnode,ic,      &
        order_int, ngaus,  ielgroup, ielem,  igaus, matno,jndex,kinit_g  !20211214
    real   (irk) thick
    real   (irk),allocatable:: bmatx(:,:),eload(:)
    real   (irk),pointer:: djacb,shape(:),gpcod(:),cartd(:,:),strsg(:),rotation(:,:)


    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        class = group(igroup)%class
        special= group(igroup)%special
        kinit_g=group(igroup)%kinit_g
        ! judge whether the CO-displacement field is included.
        !      if(field1(1:1)=='U'.and.class=='CO')then  !20201203
        if (field1(1:1)=='U')then !20201203
            print *,'igroup=',igroup
            index = group(igroup)%index
            order_int=elkn(index)%el_field(1)%order_intrules(1)

            if(index==20.or.index==21)then  !20210207
                ngaus=1
                nstre=3
                if(ndimn==3)nstre=6
            else
                nstre=  group(igroup)%nstre
                ngaus = elkn(index)%ggaus(order_int)%ngaus
            endif

            matno = group(igroup)%matno   !! for goodman element 20201121
            material=props(matno)%mechanical%solid%material
            if(material=='GOODMAN') then
                jndex=1
                if (ndimn==3.and.index==9)jndex=5
                if (ndimn==3.and.index==23)jndex=3
                order_int=elkn(jndex)%el_field(1)%order_intrules(1)
                ngaus=elkn(jndex)%ggaus(order_int)%ngaus
            endif                      !! for goodman element 20201121

            if(kinit_g==2.and.appear(igroup)>0) then  !20201121
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    do igaus=1,ngaus
                        element(ielem)%stres0(1:nstre,igaus)=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                    end do
                end do
            endif  !20201121


            if ((kinit_g==1.and.appear(igroup)>0).or.    &  !20211214
                (kinit_g==2.and.(appear(igroup)==-1.or.appear(igroup)==2))) then  !20201121
                !if(iblks==3)write(chkunit,*)'igroup=',igroup

                ! get information from the group level
                SPtype=    group(igroup)%SPtype
                nnode = elkn(index)%el_field(1)%nnode_f
                nevab = group(igroup)%dof(1)%nfdof*nnode
                matno = group(igroup)%matno
                thick=1.
                if (ndimn==2.or.index==22.or.index==26) &
                    thick=props(matno)%mechanical%solid%thickness
                ! allocate the arrays which will be used
                allocate (bmatx(nstre,nevab),eload(nevab))
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (index==22.or.index==26)rotation=>element(ielem)%rotation
                    eload =0.0
                    do igaus=1,ngaus
                        shape => elkn(index)%ggaus(order_int)%shape(:,igaus)
                        ! get djacb and cartd in the element level
                        djacb=>element(ielem)%egaus(order_int)%djacb(igaus)
                        gpcod=>element(ielem)%egaus(order_int)%gpcod(:,igaus)
                        cartd=>element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                        !if (kinit_g==1.or.(kinit_g==2.and.iblks>1)) then

                        if (kinit_g==1) then
                            strsg=>element(ielem)%field(1)%gpvar(1:nstre,igaus)
                        else if(kinit_g==2) then
                            strsg=>element(ielem)%stres0(1:nstre,igaus)
                        endif
                        ! get bmatrx according to ndimn and SPtype (for ndimn=2)
                        bmatx=0.0
                        ic=0
                        if (special(1:1)=='B')ic=1
                        if (special(1:1)=='C')ic=2
                        if (index==22)call gbmat_p4(ic,igaus,ielem,bmatx, cartd, shape,rotation)
                        if (index==26)call gbmat_thin_film(ic,igaus,ielem,bmatx, cartd, shape,rotation)
                        if (index/=22.and.index/=26)call gbmat   (SPtype, nnode, bmatx, cartd, gpcod, shape)
                        ! compute the internal force
                        eload=eload+djacb*MATMUL(transpose(bmatx),strsg)
                    end do     !!igaus
                    element(ielem)%field(1)%eload=element(ielem)%field(1)%eload+eload*thick
                    !if(iblks>=2)write(chkunit,10)ielem,element(ielem)%field(1)%eload

                    if (index==22.or.index==26)nullify(rotation)
                end do       !!ielgroup

                deallocate(bmatx,eload)
                nullify(djacb,shape,gpcod,cartd,strsg)
            endif    !! for kinit
        endif        !! for co-displacement group
    end do         !!  for group
10  format(i10,30e15.3)
    END SUBROUTINE eload_initial_stress


    SUBROUTINE REACTION_PRESCRIBED

    ! the prescribed value only for the zero order to time is available
    integer(ink) ifield, ielem, idofn,igroup,ii,ipoin,itotv
    integer(ink) idofix, ldofix, lnefix, ilnefix
    integer(ink),     pointer::leldofix(:),levdofix(:),lefdofix(:)
    real   (irk),     pointer::eload(:),tload(:)


    do idofix=1,ndofix


        lnefix =prescrib(idofix)%lnefix
        ldofix =prescrib(idofix)%ldofix
        leldofix=>prescrib(idofix)%leldofix
        levdofix=>prescrib(idofix)%levdofix
        lefdofix=>prescrib(idofix)%lefdofix

        ! if(istep==nstep)then
        !    write(7,*)'idofix=',idofix,'ldofix=',ldofix,'iffix=',iffix(ldofix)
        !end if

        if(iffix(ldofix)==4.or.iffix(ldofix)==5)cycle

        prescrib(idofix)%rdofix=0.0
        if (mdiv==1)then
            tofor(ldofix)=0.0
        else
            toform(ldofix)=0.0
        endif
        do ilnefix=1,lnefix

            ielem=leldofix(ilnefix)
            if (ice0(ielem)==0)then
                ifield=lefdofix(ilnefix)
                idofn=levdofix(ilnefix)
                igroup=element(ielem)%group

                !print *,'ilnefix=',ilnefix,'ie=',ielem,'ifield=',ifield,'idofn=',idofn
                if (appear(igroup)>0) then
                    eload=>element(ielem)%field(ifield)%eload
                    tload=>element(ielem)%field(ifield)%tload

                    !element(ielem)%field(ifield)%tload(idofn)=-element(ielem)%field(ifield)%eload(idofn)  !20200122

                    prescrib(idofix)%rdofix=prescrib(idofix)%rdofix+      &
                        eload(idofn)-tload(idofn)
                    if (mdiv==1) then
                        tofor(ldofix)=tofor(ldofix)+eload(idofn)      !! reaction=internal force
                        !write(7,*)'ldofix=',ldofix,'tofor=',tofor(ldofix)
                    else
                        toform(ldofix)=toform(ldofix)+eload(idofn)      !! reaction=internal force
                    endif
                    nullify(eload,tload)
                endif
            endif
        end do       ! ilnefix

        nullify(leldofix,levdofix,lefdofix)
    end do           ! idofix



    END SUBROUTINE REACTION_PRESCRIBED

    SUBROUTINE flow_charge

    ! caculate the flowcharge at every points
    character(10) fieldid
    integer(ink) ifield, ielem, matno,igroup,ipoin,inode
    real   (irk) density
    real   (irk),pointer::eload(:),tload(:)
    integer(ink),pointer::lnods(:)

    flowrate=0.
    do ielem=1,nelem
        igroup =element(ielem)%group
        fieldid=group(igroup)%fieldid
        matno  =group(igroup)%matno
        density = gravy*props(matno)%mechanical%fluid%density
        if (appear(igroup)>0.and.fieldid=='W'.or.fieldid=='UW') then
            ifield=1
            if (fieldid=='UW')ifield=2
            eload=>element(ielem)%field(ifield)%eload
            tload=>element(ielem)%field(ifield)%tload
            lnods=>element(ielem)%field(ifield)%lnods_f

            do inode=1,size(lnods)
                ipoin=lnods(inode)
                flowrate(ipoin)=flowrate(ipoin)+(eload(inode)-tload(inode))/density
            end do
            nullify(eload,tload,lnods)
        endif
    end do       ! ielem


    END SUBROUTINE flow_charge

    SUBROUTINE stran0_creep4  !20180630
    character(1)field1
    character(10)SPtype,fieldid
    integer(ink) igroup,  matno,  nstre,     nnode, order_int,  &
        ngaus,  ielgroup, ielem,  igaus, idimn, icreep
    real   (irk)  e, nu, Ek,Etam,Etak
    real   (irk),allocatable::stran(:),  einv(:,:), shape(:), omega(:),  dsig(:)


    ! determine the time dependent coefficient for assembling.
    DO igroup =1,ngroup

        fieldid=group(igroup)%fieldid
        if(fieldid/='U') cycle !20220607

        matno = group(igroup)%matno
        icreep= props(matno)%mechanical%solid%icreep
        if (icreep.ne.4) cycle
        ! get information from the group level
        index = group(igroup)%index
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
        Ek      =props(matno)%mechanical%solid%creep%Ek
        Etak    =props(matno)%mechanical%solid%creep%etak
        Etam    =props(matno)%mechanical%solid%creep%etam

        write(7,*)'Ek=',Ek,'etak=',etak,'etam=',etam,'ditime=',ditime
        write(7,*)'coef=',(1.-exp(-Ek/Etak*ditime))
        nstre=  group(igroup)%nstre
        SPtype=    group(igroup)%SPtype
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        ngaus = elkn(index)%ggaus(order_int)%ngaus

        allocate(einv(nstre,nstre),dsig(nstre),omega(nstre),stran(nstre))
        call ematrx_inverse

        ! loop for 1:nelgroup
        DO ielgroup = 1,group(igroup)%nelgroup

            ielem = group(igroup)%list(ielgroup)

            do igaus=1,ngaus
                ! compute initial strain  for creep
                stran=0.

                dsig =.5*(element(ielem)%field(1)%gpvar(:,igaus)+element(ielem)%field(1)%gpvar0(:,igaus))

                omega=einv.x.dsig
                omega=omega/Ek
                omega=omega-element(ielem)%field(1)%vkstrain0(:,igaus)

                stran=stran+(1.-exp(-Ek/Etak*ditime))*omega
                !if(igaus==1) &
                !write(7,*)'coef=',(1.-exp(-Ek/Etak*ditime)),'stran1=', (1.-exp(-Ek/Etak*ditime))*omega,'stran2=',ditime/Etam*dsig
                element(ielem)%field(1)%vkstrain(:,igaus)=element(ielem)%field(1)%vkstrain0(:,igaus)+stran
                stran=stran+ditime/Etam*dsig
                element(ielem)%field(1)%stran0(:,igaus)=stran
                !
                !if(igaus==1) &
                !write(7,*)'igaus=',igaus,'stran=',stran,'vkstrain0=',element(ielem)%field(1)%vkstrain0(:,igaus),'vkstrain=',element(ielem)%field(1)%vkstrain(:,igaus)

            end do     !!igaus


        end do       !!ielgroup

        deallocate(omega,dsig,einv,stran)
    end do         !!  for group

    contains
    subroutine ematrx_inverse
    einv=0.0
    if (ndimn==2) then
        if (SPtype=='PS') then
            einv(1,1)=1.
            einv(2,2)=1.
            einv(1,2)=-nu
            einv(2,1)=-nu
            einv(3,3)=2*(1+nu)
        else if(SPtype=='PE') then
            einv(1,1)=1-nu
            einv(2,2)=1-nu
            einv(1,2)=-nu
            einv(2,1)=-nu
            einv(3,3)=2.
            einv=einv*(1+nu)
        endif
    else
        einv(1:ndimn,1:ndimn)=-nu
        do idimn=1,ndimn
            einv(idimn,idimn)=1.
            einv(idimn+ndimn,idimn+ndimn)=2.*(1+nu)
        end do
    endif

    end subroutine ematrx_inverse

    end SUBROUTINE stran0_creep4  !20180630

    SUBROUTINE load_of_creep_and_temperature
    character(1)field1
    character(10)SPtype,fieldid
    integer(ink) igroup, nrfields, ifield, index,             &
        matno,  nstre,    nevab,  nnode, order_int,  &
        ngaus,  ielgroup, ielem,  igaus,               &
        jfield, icreep, nr,ir, idimn,cvstrain
    real   (irk)  e, nu,  ptime, ptime_1, ditime_1,kk,vstrain,vstrain0,vstrain1, &  !20200220
        alfa, a, b, btime, cir, fir, educ, tincr_g,qn  !20200220
    real   (irk),allocatable::stran(:),  tincr(:),              &
        einv(:,:), shape(:), omega(:),    &
        dsig(:)
    real   (irk),pointer::c(:),d(:),k(:),f(:)
    integer(ink),pointer::ldofs(:)

    ! determine the time dependent coefficient for assembling.
    DO igroup =1,ngroup
        nrfields=group(igroup)%nrfields
        fieldid=group(igroup)%fieldid
        field1= fieldid(1:1)
        if (appear(igroup)>0.and.field1=='U') then
            jfield=0;vstrain=0.
            do ifield=1,nrfields
                if (fieldid(ifield:ifield)=='T') then
                    jfield=ifield
                    goto 2
                endif
            end do
2           matno = group(igroup)%matno
            icreep= props(matno)%mechanical%solid%icreep
            if (jfield/=0.or.icreep.ne.0) then
                ! get information from the group level
                index = group(igroup)%index
                nnode = elkn(index)%el_field(1)%nnode_f
                nevab = nnode*group(igroup)%dof(1)%nfdof
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
                alfa =props(matno)%mechanical%solid%alfa
                !write(7,*)'igroup=',igroup,'dtemp=',group(igroup)%temp_pre%dtemp
                if (jfield/=0)allocate (tincr(nnode))
                !if(index.ne.20.and.index.ne.21) then ! not for beam
                if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006

                    nstre=  group(igroup)%nstre
                    SPtype=    group(igroup)%SPtype
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    ngaus = elkn(index)%ggaus(order_int)%ngaus

                    if (icreep.ne.0) then     !! for icreep/=0
                        if (appear_process(igroup,iblks)==1  .and.              &
                            appear_process(igroup,iblks-1)==0.and.             &
                            iincs==1.and.istep==inc_step)then
                            btime=0.
                            ptime=ditime*inc_step/2.
                            ditime_1=0.
                            ptime_1=0.
                        else
                            btime=group(igroup)%btime
                            ptime=ttime-btime-ditime*inc_step/2.
                            ditime_1=group(igroup)%ditime_1
                            ptime_1=ptime-(ditime*inc_step+ditime_1)/2.
                        endif
                        cvstrain=props(matno)%mechanical%solid%creep%cvstrain !nzw 2006-05-21 for vstrain,20200220
                        if(cvstrain/=0)then
                            call parameter_find(cvstrain,ptime_1,vstrain0,kk)
                            call parameter_find(cvstrain,ptime,vstrain1,kk)
                            vstrain=vstrain1-vstrain0
                        endif


                        a=props(matno)%mechanical%solid%creep%a
                        b=props(matno)%mechanical%solid%creep%b
                        e=e*(1.-exp(-a*ptime**b))
                        ! write(chkunit,*)'ptime=',ptime,'a=',a,'b=',b,'e=',e
                        educ=e
                        if (icreep==2) then     !! for icreep==2
                            nr=props(matno)%mechanical%solid%creep%nr
                            c=>props(matno)%mechanical%solid%creep%c
                            d=>props(matno)%mechanical%solid%creep%d
                            f=>props(matno)%mechanical%solid%creep%f
                            k=>props(matno)%mechanical%solid%creep%k

                            qn=0. !20200220
                            do ir=1,nr
                                cir=c(ir)+d(ir)*ptime**(-f(ir))
                                qn=qn+cir*(1.-exp(-k(ir)*ditime*inc_step*.5))
                            end do
                            educ=1.+qn*e !20200220

                            !write(chkunit,*)'igroup=',igroup,'  e=',e,'     educ=',educ

                            !educ=1.   !20200220
                            !do ir=1,nr
                            !   cir=c(ir)+d(ir)/ptime
                            !   fir=(exp(-k(ir)*ditime*inc_step)-1.)/(k(ir)*ditime*inc_step)
                            !   educ=educ+e*cir*(1-fir*exp(-k(ir)*ditime*inc_step))
                            !end do
                            !  write(chkunit,*)'educ=',educ
                            educ=e/educ
                            e=educ
                            !  write(chkunit,*)'e final=', e
                            allocate(einv(nstre,nstre),omega(nstre),dsig(nstre))
                            call ematrx_inverse
                        endif       !! end for icreep=2

                        group(igroup)%educ=educ ! estar/(1+estar*...)
                    endif    !! end for icreep/=0


                    ! allocate the arrays which will be used
                    if (jfield/=0)allocate (stran(nstre),shape(nnode))
                endif
                if (jfield==0) goto 3
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup

                    ielem = group(igroup)%list(ielgroup)


                    tincr=0.
                    if (jfield/=0) then
                        ldofs=>element(ielem)%field(jfield)%ldofs_f
                        !tincr=result_zero(ldofs)

                        if(outintr>=0)then
                            tincr=deltafi(ldofs)  !20200226
                        elseif(outintr<0)then
                            tincr=group(igroup)%temp_pre%dtemp  !20200226
                        end if

                        tincr=tincr/mdiv
                    endif


                    !if(index.ne.20.and.index.ne.21) then ! not for beam
                    if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                        do igaus=1,ngaus
                            ! compute initial strain and the omega for creep
                            stran=0.

                            if (jfield/=0) then
                                shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                                tincr_g=shape.d.tincr
                                if(nnode.eq.2) then
                                    stran(1)=alfa*tincr_g
                                elseif(ndimn==2.and.SPtype=='PE') then
                                    stran(1:ndimn)=(1+nu)*alfa*tincr_g
                                elseif(ndimn==2.and.SPtype=='PS') then
                                    stran(1:ndimn)=alfa*tincr_g
                                    stran(4)=alfa*tincr_g
                                else
                                    stran(1:ndimn)=alfa*tincr_g
                                endif
                            endif
                            !if(igroup==3.and.ielgroup==1)then
                            !    write(7,*)'ielem=',ielem,'igaus=',igaus,'tincr_g=',tincr_g,'stran1=',stran
                            !    write(7,*)'tincr=',tincr
                            !endif

                            !if(ielgroup==1)write(chkunit,'(a,3i8,10e16.6)')'igroup0,ielem,igaus,stran',igroup,ielem,igaus,stran


                            if(nnode.eq.2) then		!nzw 2006-05-21 for vstrain 20200220
                                stran(1)=stran(1)+vstrain
                            else
                                stran(1:ndimn)=stran(1:ndimn)+vstrain
                                if(ndimn==2.and.SPtype=='PS')stran(4)=stran(4)+vstrain
                            endif
                            !      if(igroup==3.and.ielgroup==1)then
                            !    write(7,*)'ielem=',ielem,'igaus=',igaus,'stran2=',stran,'dsig=',dsig
                            !endif


                            !if(ielgroup==1)write(chkunit,'(a,3i8,10e16.6)')'igroup1,ielem,igaus,stran',igroup,ielem,igaus,stran


                            if (icreep==2) then
                                do ir=1,nr
                                    omega=element(ielem)%field(1)%omega(:,igaus,ir)
                                    dsig =element(ielem)%field(1)%dsig(:,igaus)
                                    if (appear_process(igroup,iblks)==1  .and.              &
                                        appear_process(igroup,iblks-1)==0.and.             &
                                        iincs==1.and.istep==inc_step)then
                                        cir=c(ir)
                                        dsig=dsig*cir
                                        omega=einv.x.dsig
                                    else
                                        !cir=c(ir)+d(ir)/ptime_1
                                        !fir=(exp(-k(ir)*ditime_1)-1.)/(k(ir)*ditime_1)
                                        !dsig=dsig*cir*fir
                                        !omega=omega+(einv.x.dsig)
                                        !omega=omega*exp(-k(ir)*ditime_1)

                                        cir=c(ir)+d(ir)*ptime_1**(-f(ir))   !20200220
                                        fir=exp(-k(ir)*ditime_1*.5)         !20200220
                                        dsig=dsig*cir*fir                   !20200220
                                        omega=omega*exp(-k(ir)*ditime_1)    !20200220
                                        omega=omega+(einv.x.dsig)          !20200220

                                    endif
                                    element(ielem)%field(1)%omega(:,igaus,ir)=omega
                                    stran=stran+omega*(1.-exp(-k(ir)*ditime*inc_step))
                                end do
                            endif
                            element(ielem)%field(1)%stran0(:,igaus)=stran


                            !if(igroup==3.and.ielgroup==1)write(chkunit,'(a,3i8,10e16.6)')'igroup2,ielem,igaus,stran',igroup,ielem,igaus,stran
                        end do     !!igaus
                    endif

                    nullify(ldofs)
                end do       !!ielgroup
                deallocate(tincr)
                !if(index.ne.20.and.index.ne.21) then ! not for beam
                if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                    deallocate(shape,stran)
                endif
3               continue
                if (icreep==2) then
                    nullify(c,d,f,k)
                    deallocate(omega,dsig,einv)
                endif
                if (appear_process(igroup,iblks)==1  .and.           &
                    appear_process(igroup,iblks-1)==0.and.             &
                    iincs==1.and.istep==inc_step)group(igroup)%btime=ttime-ditime*inc_step
                group(igroup)%ditime_1=ditime*inc_step
            end if      !! for creep
        endif        !! for co-displacement group
    end do         !!  for group

    contains
    subroutine ematrx_inverse
    einv=0.0
    if (ndimn==2) then
        if (SPtype=='PS') then
            einv(1,1)=1.
            einv(2,2)=1.
            einv(1,2)=-nu
            einv(2,1)=-nu
            einv(3,3)=2*(1+nu)
        else if(SPtype=='PE') then
            einv(1,1)=1-nu
            einv(2,2)=1-nu
            einv(1,2)=-nu
            einv(2,1)=-nu
            einv(3,3)=2.
            einv=einv*(1+nu)
        endif
    else
        einv(1:ndimn,1:ndimn)=-nu
        do idimn=1,ndimn
            einv(idimn,idimn)=1.
            einv(idimn+ndimn,idimn+ndimn)=2.*(1+nu)
        end do
    endif

    end subroutine ematrx_inverse

    end SUBROUTINE load_of_creep_and_temperature

    SUBROUTINE creep_strain_of_rock_fill   !2013510

    character(1) field1 !20220624
    character(20)SPtype,material
    integer(ink) igroup, index, matno,  nstre,   order_int, ngaus,  ielgroup, ielem,  igaus,  &
        icreep, nr
    real   (irk) root3, Pa, alfas, bs,cs,ds,m1,m2,m3,steff,sl,p3,p,q,evf,etf,devf,detf,tevf,tetf
    real   (irk),allocatable::unitx(:), sgtot(:),sigx(:),stran(:)



    ! determine the time dependent coefficient for assembling.
    root3 = sqrt(3.00)
    allocate(unitx(3*(ndimn-1)))
    unitx=0.
    unitx(1:ndimn)=1.
    DO igroup =1,ngroup

        field1= group(igroup)%fieldid(1:1)
        if(appear(igroup)<=0)cycle
        if(field1/='U')cycle !20220624

        matno = group(igroup)%matno
        material=props(matno)%mechanical%solid%material
        icreep =props(matno)%mechanical%solid%icreep
        if(material/='DUNCANCHANG') cycle
        if(icreep/=3) cycle
        Pa   =props(matno)%mechanical%solid%DuncanChang%Pa

        ! get information from the group level
        index = group(igroup)%index
        nstre=  group(igroup)%nstre
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        ngaus = elkn(index)%ggaus(order_int)%ngaus
        nr=props(matno)%mechanical%solid%creep%nr
        alfas=props(matno)%mechanical%solid%creep%alfas
        bs=props(matno)%mechanical%solid%creep%bs
        ds=props(matno)%mechanical%solid%creep%ds

        if(nr==7)then
            cs=props(matno)%mechanical%solid%creep%cs
            m1=props(matno)%mechanical%solid%creep%m1
            m2=props(matno)%mechanical%solid%creep%m2
            m3=props(matno)%mechanical%solid%creep%m3
        endif
        !write(7,*)'pa=',pa,'alfas=',alfas,'bs=',bs,'cs=',cs,'ds=',ds,'m1=',m1,'m2=',m2,'m3=',m3
        !write(7,*)'pa=',pa,'alfas=',alfas,'bs=',bs,'cs=',cs,'ds=',ds


        ! loop for 1:nelgroup
        DO ielgroup = 1,group(igroup)%nelgroup

            ielem = group(igroup)%list(ielgroup)

            do igaus=1,ngaus
                ! compute initial strain and the omega for creep

                steff=element(ielem)%field(1)%gpvar0(1+nstre,igaus)
                sl=element(ielem)%field(1)%gpvar0(2+nstre,igaus)
                !element(ielem)%field(1)%gpvar(3+nstre,igaus)=et
                !element(ielem)%field(1)%gpvar(4+nstre,igaus)=vt
                p3=element(ielem)%field(1)%gpvar0(5+nstre,igaus)
                tevf=element(ielem)%field(1)%gpvar0(6+nstre,igaus)
                tetf=element(ielem)%field(1)%gpvar0(7+nstre,igaus)
                q=root3*steff
                if(abs(p3)<1.e-2*pa.or.abs(q)<1.e-2*pa) cycle  !20220607
                !if(abs(p3)<pa.or.abs(q)<pa) cycle  !20220607
                if(sl<=0.) sl=0.
                if(sl>=0.999)sl=0.995
                if(nr==3)then
                    evf=bs*p3/pa
                    etf=ds*sl/(1-sl)
                elseif(nr==7) then
                    evf=bs*(p3/pa)**m1+cs*(q/pa)**m2
                    etf=ds*sl/(1-sl)**m3
                endif
                devf=alfas*evf*(1-tevf/evf)*ditime
                detf=alfas*etf*(1-tetf/etf)*ditime

                !       if(ielgroup==1.or.ielgroup==group(igroup)%nelgroup)then
                !write(7,*)'ie=',ielem,'igaus=',igaus,'p3=',p3,'q=',q,'sl=',sl,'tevf=',tevf,'tetf=',tetf
                !
                !write(7,*) 'evf=',evf,'etf=',etf,'devf=',devf,'detf=',detf
                !     endif

                tevf=tevf+devf
                tetf=tetf+detf
                element(ielem)%field(1)%gpvar(6+nstre,igaus)= tevf
                element(ielem)%field(1)%gpvar(7+nstre,igaus)= tetf

                allocate(SGTOT(nstre),sigx(nstre),stran(nstre))

                SGTOT=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                p=sum(sgtot(1:ndimn))
                p=p/3.
                sigx(1:ndimn)=sgtot(1:ndimn)-p
                if(ndimn.eq.2.and.nstre==4)sigx(4)=sgtot(4)-p
                sigx(ndimn+1:3*(ndimn-1))=sgtot(ndimn+1:3*(ndimn-1))*2.
                stran=devf*unitx/3.+.5*detf*sigx/q
                !if(ielgroup==1.or.ielgroup==group(igroup)%nelgroup)then
                !    write(7,*)'ie=',ielem,'igaus=',igaus,'stran=',stran
                !endif
                element(ielem)%field(1)%stran0(:,igaus)=stran
                deallocate(sgtot,sigx,stran)
            end do     !!igaus

            !
        end do       !!end DO ielgroup

    end do         !!  for group
    deallocate(unitx)

    end SUBROUTINE creep_strain_of_rock_fill   !2013510

    SUBROUTINE saturation_judge !20220409
    integer(ink) igroup,uplift_ic,index,order_int,igaus,ngaus,matno, &
        ielem,ielgroup,nnode,nrfields,kind_wt
    real   (irk) dheight,ppp
    real   (irk),allocatable::shape(:)
    integer(ink),pointer::lnods(:),ldofs(:)
    character(30)material,fieldid
    character(1)field1

    DO igroup =1,ngroup
        uplift_ic=group(igroup)%uplift_ic
        nrfields=group(igroup)%nrfields
        fieldid=group(igroup)%fieldid
        if(fieldid=='W') cycle !20220607
        !write(7,*)'igroup=',igroup,'uplift_ic=',uplift_ic,'upliftin=',upliftin
        !write(7,*)'nrfields=', nrfields
        matno = group(igroup)%matno
        kind_wt =props(matno)%mechanical%solid%kind_wt
        if(kind_wt==0)cycle !20220607

        !if(uplift_ic==0)cycle


        field1= group(igroup)%fieldid(1:1)
        matno = group(igroup)%matno
        if(appear(igroup)>0.and.field1=='U') then
            material=props(matno)%mechanical%solid%material
            index = group(igroup)%index
            if(nrfields==1)then
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus = elkn(index)%ggaus(order_int)%ngaus
                nnode    =elkn(index)%el_field(1)%nnode_f
            elseif(group(igroup)%fieldid(1:2)=='UW')then
                order_int=elkn(index)%el_field(1)%order_intrules(1)  !20220707
                ngaus = elkn(index)%ggaus(order_int)%ngaus !20220707
                nnode =elkn(index)%el_field(1)%nnode_f
            endif
            allocate (shape(nnode))
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                do igaus=1,ngaus
                    if(element(ielem)%field(1)%isatu(igaus)==0)then

                        if(upliftin==0.and.nrfields==1)then
                            dheight=water_level(iblks)-element(ielem)%egaus(order_int)%gpcod(ndimn,igaus)
                            !write(7,*)'ielem=',ielem,'igaus=',igaus,'dheight=',dheight

                            if(dheight>0.)element(ielem)%field(1)%isatu(igaus)=1
                            !write(7,*)'isatu=', element(ielem)%field(1)%isatu(igaus)

                        elseif(upliftin>0.and.nrfields==1)then
                            shape=elkn(index)%ggaus(order_int)%shape(:,igaus)
                            lnods=>element(ielem)%field(1)%lnods_f
                            ppp=uplift_node(lnods).d.shape
                            if(ppp>1.e-2)element(ielem)%field(1)%isatu(igaus)=1
                            nullify(lnods)
                        elseif(nrfields==2.and.group(igroup)%fieldid(2:2)=='W')then
                            ldofs=>element(ielem)%field(2)%ldofs_f
                            ppp=result_zero(ldofs).d.shape
                            if(ppp>1.e-2)element(ielem)%field(1)%isatu(igaus)=1
                            nullify(ldofs)
                        endif
                    elseif(element(ielem)%field(1)%isatu(igaus)==1)then
                        element(ielem)%field(1)%isatu(igaus)=2
                    endif
                end do
            end do
            deallocate(shape)
        endif
    end do
    end SUBROUTINE saturation_judge   !20220409

    SUBROUTINE wetting_strain_of_rock_fill   !20220409

    character(1) field1 !20220624
    character(20)SPtype,material
    integer(ink) igroup, index, matno,  nstre,   order_int, ngaus,  ielgroup, ielem,  igaus,  &
        uplift_ic,kind_wt
    real   (irk) root3, Pa, Cw,Dw,nw,a,b,c,steff,sl,p3,p,q,devf,detf
    real   (irk),allocatable::unitx(:), sgtot(:),sigx(:),stran(:)



    ! determine the time dependent coefficient for assembling.
    root3 = sqrt(3.00)
    allocate(unitx(3*(ndimn-1)))
    unitx=0.
    unitx(1:ndimn)=1.
    DO igroup =1,ngroup

        field1= group(igroup)%fieldid(1:1)
        if(appear(igroup)<=0)cycle
        if(field1/='U')cycle !20220624

        if(appear(igroup)<=0)cycle

        matno = group(igroup)%matno
        kind_wt =props(matno)%mechanical%solid%kind_wt
        !uplift_ic=group(igroup)%uplift_ic  !20220409
        !write(7,*)'igroup=',igroup,'kind_wt=',kind_wt,'uplift_ic=',uplift_ic


        if(kind_wt==0) cycle !20220422
        !if(uplift_ic/=2) cycle
        Pa   =props(matno)%mechanical%solid%DuncanChang%Pa

        ! get information from the group level
        index = group(igroup)%index
        nstre=  group(igroup)%nstre
        order_int=elkn(index)%el_field(1)%order_intrules(1)
        ngaus = elkn(index)%ggaus(order_int)%ngaus

        Cw=props(matno)%mechanical%solid%wetting_def%Cw
        Dw=props(matno)%mechanical%solid%wetting_def%Dw
        nw=props(matno)%mechanical%solid%wetting_def%nw
        a=props(matno)%mechanical%solid%wetting_def%a
        b=props(matno)%mechanical%solid%wetting_def%b
        c=props(matno)%mechanical%solid%wetting_def%c

        ! loop for 1:nelgroup
        DO ielgroup = 1,group(igroup)%nelgroup

            ielem = group(igroup)%list(ielgroup)

            do igaus=1,ngaus
                ! compute initial strain and the omega for creep
                element(ielem)%field(1)%stran0_s(:,igaus)=0. !湿化变形只在初始湿化计算一次
                !write(7,*)'ie=',ielem,'ig=',igaus,'isatu=',element(ielem)%field(1)%isatu(igaus)
                if(element(ielem)%field(1)%isatu(igaus)/=1)cycle
                steff=element(ielem)%field(1)%gpvar0(1+nstre,igaus)
                sl=element(ielem)%field(1)%gpvar0(2+nstre,igaus)
                p3=element(ielem)%field(1)%gpvar0(5+nstre,igaus)
                q=root3*steff
                !if(abs(p3)<pa.or.abs(q)<pa) cycle
                if(sl<=0.) sl=0.
                if(sl>=0.999)sl=0.995
                if(kind_wt==1)then
                    devf=Cw;detf=Dw*sl/(1-sl)
                elseif(kind_wt==2)then
                    devf=p3*1.e-6/(a+b*p3*1.e-6);detf=Dw*sl/(1-sl)
                elseif(kind_wt==3)then
                    detf=Dw*sl/(1-sl);devf=p3/(a+b*p3)-c*detf
                elseif(kind_wt==4)then
                    detf=Dw*sl/(1-sl);devf=Dw*(p3/pa)**nw
                endif
                if(ielgroup==1.or.ielgroup==group(igroup)%nelgroup)then
                    !write(7,*)'ie=',ielem,'igaus=',igaus,'p3=',p3,'q=',q,'sl=',sl
                    !write(7,*) 'devf=',devf,'detf=',detf
                endif

                allocate(SGTOT(nstre),sigx(nstre),stran(nstre))

                SGTOT=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                p=sum(sgtot(1:ndimn))
                p=p/3.
                sigx(1:ndimn)=sgtot(1:ndimn)-p
                if(ndimn.eq.2.and.nstre==4)sigx(4)=sgtot(4)-p
                sigx(ndimn+1:3*(ndimn-1))=sgtot(ndimn+1:3*(ndimn-1))*2.
                stran=devf*unitx/3.
                if(q>1.e-8) &  !20231110
                    stran=stran+.5*detf*sigx/q
                !if(ielgroup==1.or.ielgroup==group(igroup)%nelgroup)then
                !    write(7,*)'ie=',ielem,'igaus=',igaus,'stran=',stran
                !endif
                element(ielem)%field(1)%stran0_s(:,igaus)=stran*1.e-2  !20220502
                deallocate(sgtot,sigx,stran)
            end do     !!igaus

            !
        end do       !!end DO ielgroup

    end do         !!  for group
    deallocate(unitx)

    end SUBROUTINE wetting_strain_of_rock_fill   !20220409

    !======================================================
    subroutine get_stress_level(matno,nstre,humidification,d,sig,curSlevel)
    integer(ink) matno,nstre,humidification
    real   (irk) sig(:),curSlevel,theta,q,p,rj2,rj3,sint3,d(:),eta,etaf,    &
        sinfg,sinff,xmgc,xmfc,ri1,pei,cohes,phi,p0,pa,ps(3),niu,thetal,root3,steff,smean,qf,DPHI
    real(irk), allocatable:: DEVIA(:)

    allocate(devia(nstre))
    devia=0.0

    call invart(matno,nstre,devia,sig,theta,q,p,rj2,rj3,sint3)

    if(humidification==2)then   ! 用eta/etaf求应力水平

        sinfg=3*d(3)/(6.+d(3))
        sinff=3*d(5)/(6.+d(5))

        XMGC=6.0*sinfg/(3.0-sinfg*SINT3)
        XMFC=6.0*sinff/(3.0-sinff*SINT3)

        RI1=-P
        ETA=ABS(Q/P)
        ETAF=(1.0+1.0/D(6))*XMFC  ! nzw PHD Thesis, (3.8.28a)
        curSlevel=eta/etaf

    elseif(humidification==-2)then   !用DC模型中的方法求应力水平
        ROOT3=1.73205080757
        pei  = 3.1415926535
        cohes=d(17)
        phi =d(18)
        P0  =d(19)
        Pa  =d(20)

        smean=-p    !修改p和q是因为invart中PZ材料求得的p和q和DC的有点不同
        steff=q/sqrt(3.d0)

        ps(3)=-(2.*steff/root3*sin(theta+2*pei/3.)+smean)
        ps(2)=-(2.*steff/root3*sin(theta         )+smean)
        ps(1)=-(2.*steff/root3*sin(theta+4*pei/3.)+smean)
        p=(ps(3)+ps(2)+ps(1))/3      !2008_lhe

        IF(P.LT.0.01)p=0.01

        IF(P<P0)p=p0

        PHI=PHI-DPHI*LOG10(p/pa)

        niu=1-2*(ps(2)-ps(3))/(ps(1)-ps(3))
        thetal=atan(-niu/root3)
        Q    =sqrt((ps(1)-ps(2))**2+(ps(2)-ps(3))**2+(ps(3)-ps(1))**2)/1.414213562  !       2008_lhe
        Qf   =(3.*COHES*COSD(phi)+3*p*sinD(phi))/(ROOT3*cos(thetal)+sin(thetal)*sind(phi))

        curSlevel=Q/QF

    endif

    IF(curSlevel>1.0) curSlevel=1.0
    IF(curSlevel<0.0) curSlevel=0.001

    deallocate(devia)
    end subroutine get_stress_level
    !======================================================
    subroutine dispatch_sa_sv(igroup,ielem,igaus,matno,nstre,strsg,sa,sv,stran)
    integer(ink) matno,nstre,igroup,ielem,igaus,istre
    real   (irk) sa,sv,stran(:),strsg(:),theta,p,q,rj2,rj3,sint3,ri1,alfa1,temp
    real(irk),allocatable::a1(:),a2(:),a3(:),devia(:)

    allocate(a1(nstre),a2(nstre),a3(nstre),devia(nstre))
    a1=0.0;a2=0.0;a3=0.0;devia=0.0

    call invart(matno,nstre,devia,strsg,theta,q,p,rj2,rj3,sint3)
    CALL FAVMDL(nstre,A1,A2,A3,DEVIA,RJ2,RJ3,THETA,RI1)

    if(ndimn==2)then
    elseif(ndimn==3)then
        temp=a2(1)**2+a2(2)**2+a2(3)**2+2.d0*(a2(4)**2+a2(5)**2+a2(6)**2)
        alfa1=(3.d0/2.d0)*(sa/100.)**2/temp
        alfa1=sqrt(abs(alfa1))
    endif

    do istre=1,nstre
        stran(istre)=stran(istre)-sv/100.0*a1(istre)   !除100是因为由曲线插值得到的体应变单位是%
        stran(istre)=stran(istre)-alfa1*a2(istre)
    end do

    if(ielem==group(igroup)%list(1))then
        write(7,'(a,3i6,10e16.8)')'igroup,ielem,igaus,sa,sv,alfa1,stran=',igroup,ielem,igaus,sa,sv,alfa1,stran
        write(7,'(a,10e16.8)')'a1=',a1
        write(7,'(a,10e16.8)')'a2=',a2
    endif

    deallocate(a1,a2,a3,devia)

    end subroutine dispatch_sa_sv


    END MODULE INTERNAL_FORCE
