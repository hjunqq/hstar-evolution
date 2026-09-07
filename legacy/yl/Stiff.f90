    module stiffness_matrix

    use yl_diag
    use yl_diag_registry
    use variable_types
    use arrayutil
    use global_var
    use materials
    use solver
    use output
    !use msimsl
    use meshfine

    implicit none

    real   (irk) Min_ini_stress,XYCoef


    contains

    SUBROUTINE STIFF_U

    character(1)field1
    character(1),allocatable::field(:)
    character(10)SPtype,class,fieldid,special,name,state
    character(30)material
    integer(ink) igroup, nrfields, ifield, ntpel, index,      &
        matno,  nstre,    nevab,  nnode, order_int,  &
        ngaus,  ielgroup, ielem,  igaus, i, inode,   &
        lnidmn, aevab,    jnode,  jndex, idimn, ilayer,ic, &
        nnode_dd,nevab_dd,ipoin,i0
    !! creep
    integer(ink) icreep
    integer(ink),pointer::lnods(:),ldofs(:)
    !! end creep
    integer(ink) type_stiff
    real   (irk)  e, nu, djacb, yld, theta, steff,    &
        smean, vj2,vj3,sint3,   abeta,eps, bulkt,thick,ex
    real   (irk),allocatable::estif(:,:), cartd(:,:),           &
        ematx(:,:), dmatx(:,:),         &
        sgtot(:), devia(:), avect(:),   &
        avecq(:), dvect(:), dvecq(:),   &
        dbmat(:,:),bmatx(:,:),gpcod(:), &
        shape(:),veca2(:),veca3(:),dasig(:,:)
    real   (irk),allocatable::estift(:,:), gmatx(:,:), estifh(:,:),ks(:,:),ksx(:,:),ddisp(:),rotstar(:,:),unitx(:,:)
    real   (irk),pointer::rotation(:,:),elcod(:,:),stran(:)  !20220713
    real   (irk),allocatable::trot(:,:),estifm(:,:),estif_dd(:,:),eldis(:)
    real   (irk) aera,g,iy,iiy,iz,iiz,twist,itj,iea,dl,ep !ep2010

    real   (irk) l0,a,b,c,d,dgap0,dgap1,dgap,strabar,tao,ftx,fcx,dx
    strabar=0.
    eps=1.e-10
    !write(chkunit,*)'dmatx in stiff'
    DO igroup =1,ngroup
        !write(7,*)'ig=',igroup
        field1= group(igroup)%fieldid(1:1)
        class = group(igroup)%class
        special= group(igroup)%special
        ! judge whether the CO-displacement field is included.
        !           if(appear(igroup)>0.and.field1=='U'.and.class=='CO')then
        if (appear(igroup)>0.and.field1=='U')then
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            allocate(field(nrfields))
            do ifield=1,nrfields
                field(ifield)=fieldid(ifield:ifield)
            end do
            ! find whether the u-p formulation is used, ntpel=1--yes!
            ntpel=0
            if (any(field=='P'))ntpel=1
            deallocate(field)
            ! get information from the group level
            index = group(igroup)%index
            ilayer = group(igroup)%ilayer
            matno = group(igroup)%matno
            name=props(matno)%name
            material=props(matno)%mechanical%solid%material
            icreep =props(matno)%mechanical%solid%icreep
            !steel 2006
            if (name/='CRACK'.and.index/=25.and.name/='CONTACT'.and.name/='NOLINORMK'.and.(material=='ELASTIC_ISOTROPIC'.and.icreep==0).and.  &
                (iincs/=1.or.istep/=inc_step.or.iiter/=1).and.restart/=1) goto 111  ! for elastic
            if (nlayer==2.and.ilayer==1.and.kresl_layer1==0) goto 111
            if (nlayer==2.and.ilayer==2.and.kresl_layer2==0) goto 111

            nstre=  group(igroup)%nstre
            !print *,'igroup=',igroup,'nstre=',nstre  !20231215YL
            if(material=='GOODMAN')nstre=ndimn
            SPtype=    group(igroup)%SPtype
            type_stiff=    group(igroup)%type_stiff
            nnode = elkn(index)%el_field(1)%nnode_f
            nevab = nnode*group(igroup)%dof(1)%nfdof
            if (special(1:1)=='D')nnode_dd=group(igroup)%nnode_dd
            nevab_dd=nnode_dd*ndimn
            allocate (estif(nevab,nevab))
            if (special(1:1)=='D')allocate (estif_dd(nevab_dd,nevab_dd))


            if (material/='DUNCANCHANG'.and.material/='GOODMAN') then
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
                if ((icreep.ne.0.and.icreep<=3).and.kglb==0)e=group(igroup)%educ  !20180630
            endif

            !if((material=='DUNCANCHANG'.or.material=='SandPZ').and.type_problem=='F') allocate(stran(nstre)) !20220728
            if(material=='DUNCANCHANG'.or.material=='SandPZ'.or.material=='SoilPZ') allocate(stran(nstre)) !20220728

            thick=1.
            if (ndimn==2.or.index==22.or.index==26)thick=props(matno)%mechanical%solid%thickness
            !if(nnode==2)thick  =props(matno)%geometry%aera
            if (nnode==2.and.index/=25)thick  =props(matno)%geometry%aera !steel 2006

            !if(index.ne.20.and.index.ne.21) then ! not for beam
            if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                order_int=elkn(index)%el_field(1)%order_intrules(1)
                ngaus = elkn(index)%ggaus(order_int)%ngaus

                if (material=='GOODMAN') then
                    jndex=1
                    if (ndimn==3.and.index==9)jndex=5  !2017/02/14
                    if (ndimn==3.and.index==23)jndex=3  !2017/02/14
                    order_int=elkn(jndex)%el_field(1)%order_intrules(1)
                    ngaus=elkn(jndex)%ggaus(order_int)%ngaus
                endif
                if (material=='GOODMAN')allocate(shape(nnode/2))
                if (material/='GOODMAN')allocate(shape(nnode))
                lnidmn =elkn(index)%ndimn

                ! allocate the arrays which will be used
                if (special(1:1)=='D')then
                    allocate (cartd(lnidmn,nnode_dd),bmatx(nstre,nevab_dd), dbmat(nstre,nevab_dd))
                else
                    allocate (cartd(lnidmn,nnode),bmatx(nstre,nevab), dbmat(nstre,nevab))
                endif
                allocate (ematx(nstre,nstre),gpcod(ndimn))
                allocate (dmatx(nstre,nstre),sgtot(nstre))
                allocate (devia(nstre), avect(nstre), avecq(nstre),    &
                    dvect(nstre), dvecq(nstre))
                allocate (veca2(nstre),veca3(nstre))
                veca2=0.;veca3=0.;avect=0.;avecq=0.;dvect=0.;dvecq=0. ;dbmat=0.
                if (type_stiff==2)allocate(dasig(nstre,nstre))
                ! for Simo & Rifai element
                if (special(1:1)=='B') then
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
                    allocate(gmatx(nstre,aevab),estift(aevab,nevab),   &
                        estifh(aevab,aevab))
                endif
                ! end for Simo & Rifai element
                ! compute the elastic matrix, De or Ds
                ematx=0.
                if (material/='DUNCANCHANG'.and.material/='GOODMAN') then

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

                    if (ntpel.ne.0.and.nnode/=2) bulkt=e/(3.0*(1.0-2.0*nu))
                endif
                if (nnode==2)ematx=e
                !else          !! for elements except beam
            elseif(index/=25)then
                allocate(trot(nevab,nevab),estifm(nevab,nevab))
                trot=0. ; estifm=0.
                g=e/(2*(1+nu))
                Iy   =props(matno)%geometry%iy
                Iz   =props(matno)%geometry%iz
                twist=props(matno)%geometry%j
                aera =props(matno)%geometry%aera
            elseif(index==25)then !steel 2006
                allocate(trot(nevab,nevab),estifm(nevab,nevab))
                trot=0. ; estifm=0.
            endif



            ! loop for 1:nelgroup
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                if (tension_joint(ielem)==1) goto 100   !! special for hjd
                !print *,'ie=',ielem
                estif=0.0_irk
                if (special(1:1)=='D')estif_dd=0.
                ! for Simo & Rifai element
                if (special(1:1)=='B') then
                    estift=0.0
                    estifh=0.0
                endif
                ! end for Simo & Rifai element

                !!20220728
                !if((material=='DUNCANCHANG'.or.material=='SandPZ').and.type_problem=='F') then
                !	ldofs => element(ielem)%field(1)%ldofs_f
                !	allocate(eldis(size(ldofs)))
                !	if(material=='DUNCANCHANG')eldis =result_zero(ldofs)
                !	if(material=='SandPZ')eldis =delitfi(ldofs)
                !
                !endif

                if(material=='DUNCANCHANG'.or.material=='SandPZ'.or.material=='SoilPZ') then
                    ldofs => element(ielem)%field(1)%ldofs_f
                    allocate(eldis(size(ldofs)))
                    if(material=='DUNCANCHANG')eldis =result_zero(ldofs)
                    if(material=='SandPZ')eldis =delitfi(ldofs)
                    if(material=='SoilPZ')eldis =delitfi(ldofs)
                endif


                !!20220728




                if (nnode==2.or.index==22.or.index==26)then
                    rotation=>element(ielem)%rotation
                    !write(chkunit,*)'ielem=',ielem,'rotation='
                    !write(chkunit,119)rotation(1,:)
                    !write(chkunit,119)rotation(2,:)
                endif

                !if(index.ne.20.and.index.ne.21) then ! not for beam
                if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006


                    if (index==22.and.special(1:1)=='S')then
                        elcod=>element(ielem)%field(1)%elcod_f
                        call stif_p4_st(ielem,elcod,rotation,e,nu,thick,estif)
                        goto 1
                    endif


                    do igaus=1,ngaus
                        if(material=='ELASTIC_EP')then !ep2010
                            call epcurveEP(element(ielem)%field(1)%sigz(igaus),matno,ep)
                            if (index/=22.and.index/=26.and.name/='SOLIDF')call ecmat(SPtype,ematx,ep,nu) !zhao 0710
                            if (index/=22.and.index/=26.and.name=='SOLIDF')call ecmat_solidf(SPtype,ematx,ep,nu) !zhao 0710
                        endif
                        if (material/='GOODMAN') then
                            shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                            dmatx=ematx
                            !if(ielem==1)then
                            !    write(7,*)'ielem=',ielem,'igaus=',igaus,'dmaxt=',dmatx
                            !endif
                            ! get djacb and cartd in the element level
                            djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                            !          if(special(1:1)/='D')djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                            !          if(special(1:1)=='D')djacb=element(ielem)%djacb_dd(igaus)
                            gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                        else
                            shape = elkn(jndex)%ggaus(order_int)%shape(:,igaus)
                            djacb=element(ielem)%aera_local(igaus)
                        endif
                        bmatx=0.0
                        if (material/='GOODMAN') then
                            if (special(1:1)/='D')cartd=element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                            if (special(1:1)=='D')cartd=element(ielem)%gmatx(:,:,igaus)
                            ! get bmatrx according to ndimn and SPtype (for ndimn=2)
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
                            else  ! for nnode==2

                                do inode=1,nnode
                                    bmatx(1,(inode-1)*ndimn+1:inode*ndimn)=cartd(1,inode)*rotation(1,:)
                                end do

                                if(index==1.and.(any(listglocbeam==igroup)))then !barsteel  20231007
                                    lnods=>element(ielem)%field(1)%lnods_f
                                    allocate(trot(nevab,nevab))
                                    trot=0.
                                    trot(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
                                    trot(ndimn+1:ndimn*2,ndimn+1:ndimn*2)=prot(:,:,lnods(2))
                                    bmatx=matmul(bmatx,transpose(trot))
                                    deallocate(trot)
                                    nullify(lnods)
                                endif

                                if (index==1.and.material=='ELASTIC_SPRING')then
                                    allocate(eldis(ndimn*2))
                                    eldis=0.
                                    lnods=>element(ielem)%field(1)%lnods_f
                                    l0=props(matno)%mechanical%solid%Elastic_Spring%l0
                                    dgap0=(coord(:,lnods(2))-coord(:,lnods(1))).d.rotation(1,:)
                                    dgap0=l0-dgap0
                                    ldofs=>element(ielem)%field(1)%ldofs_f
                                    eldis=result_zero(ldofs)
                                    dgap1=(eldis(ndimn+1:2*ndimn)-eldis(1:ndimn)).d.rotation(1,:)
                                    dgap=dgap0+dgap1
                                    if (dgap>1.e-8) then
                                        element(ielem)%field(1)%state(igaus)='OPEN'
                                        dmatx=0.
                                    else
                                        element(ielem)%field(1)%state(igaus)='CLOSE'
                                        a=props(matno)%mechanical%solid%Elastic_Spring%a
                                        b=props(matno)%mechanical%solid%Elastic_Spring%b
                                        c=props(matno)%mechanical%solid%Elastic_Spring%c
                                        d=props(matno)%mechanical%solid%Elastic_Spring%d
                                        dmatx=(b+2*c*abs(dgap)+3*d*dgap**2)*l0/thick
                                    end if
                                    nullify(ldofs,lnods)
                                    deallocate(eldis)
                                endif
                            endif !nnode== or /=2
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
                        ! compute Dep for nonlinear material
                        !! contact
                        if (name=='CONTACT'.and.kglb==0) then
                            state=element(ielem)%field(1)%state(igaus)
                            if (state=='open') then
                                dmatx=dmatx*0.e-30     !! 0.e-4 can be changed!
                                goto 10
                            elseif(material=='ELASTIC_FRICTIONLESS')then
                                rotation=>element(ielem)%rotation
                                call dmatxf_change(e,dmatx,rotation)
                                nullify(rotation)
                                goto 10
                            endif
                        endif
                        !! end contact
                        !crack 2006
                        if (name=='CRACK') then
                            state=element(ielem)%field(1)%state(igaus)
                            if (state=='open') then
                                dmatx=dmatx*0.0     !! 0.e-4 can be changed!
                                goto 10
                            endif
                        endif
                        !! end crack 2006

                        !if((material=='DUNCANCHANG'.or.material=='SandPZ').and.type_problem=='F') stran=matmul(bmatx,eldis)  !20220728
                        if(material=='DUNCANCHANG'.or.material=='SandPZ'.or.material=='SoilPZ') stran=matmul(bmatx,eldis)  !20220728

                        if (rmesh<=0.and.kglb==0.and.material(1:7)/='ELASTIC')call dep

10                      if (ntpel.ne.0.and.nnode/=2) then
                            dmatx(1:ndimn,1:ndimn)=dmatx(1:ndimn,1:ndimn)-bulkt
                            if (ndimn==2.and.SPtype=='PE')dmatx(4,4)=dmatx(4,4)-bulkt
                        endif

                        if (name=='NORMK'.or.name=='NOLINORMK')then
                            rotation=>element(ielem)%rotation
                            ex=e
                            if (name=='NOLINORMK')then
                                call find_e_NOLINORMK(matno,rotation,element(ielem)%field(1)%gpvar0(1:nstre,igaus),ex) !用上一步应力求弹模
                            endif
                            call dmatxf_change(ex,dmatx,rotation)
                            nullify(rotation)
                        endif

                        dbmat=matmul(dmatx,bmatx)
                        if (special(1:1)/='D')estif=estif+djacb*matmul(transpose(bmatx),dbmat)
                        !if(index==1)then
                        !    write(7,*)'ie=',ielem,'index=',index,'igaus=',igaus
                        !    write(7,*)'estif=',estif
                        ! end if

                        if (special(1:1)=='D')estif_dd=estif_dd+djacb*matmul(transpose(bmatx),dbmat)
                        if (name=='NSTOKS')  &  !nstoks
                            call estif_nstoks(matno,ielem,nnode,djacb,shape,cartd,estif)
                        ! for Simo & Rifai element
                        if (special(1:1)=='B'.and.index/=22.and.index/=26) then
                            gmatx=element(ielem)%gmatx(:,:,igaus)
                            call estif_sr(estif,dmatx,gmatx,dbmat,djacb,    &
                                estift,estifh,igaus,ngaus)
                        endif

20                      format(5e15.3)
                        ! end for Simo & Rifai element

                    end do     !!igaus


                    if (special(1:1)=='D')then
                        lnods=>element(ielem)%field(1)%lnods_f
                        call estif_dr(index,nnode,lnods,estif,estif_dd,nevab,nevab_dd)
                        nullify(lnods)
                    endif

211                 format(8e20.5)
1                   continue
                else if(index.eq.20.or.index.eq.21) then
                    thick=1.

                    if(material=='STEEL_EP')e=element(ielem)%field(1)%ep  !20211125
                    trot=0.; estifm=0.0
                    if(material/='STEEL_SP')then  !20211125
                        elcod=>element(ielem)%field(1)%elcod_f
                        dl=sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))
                        iiy=e*iy/dl; iiz=e*iz/dl; itj=g*twist/dl; iea=e*aera/dl
                    endif !20211125

                    !write(7,*)'ie=',ielem,'e=',e,'iy=',iy,'dl=',dl
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

                    !             write(chkunit,*)'ielem=',ielem,'estifm='
                    !             do idimn=1,12
                    !             write(chkunit,119)estifm(idimn,:)
                    !             end do
                    !
                    !              write(chkunit,*)'ielem=',ielem,'trot='
                    !             do idimn=1,12
                    !             write(chkunit,119)trot(idimn,:)
                    !             end do
                    !119 format(12e15.5)

                    estif=estifm.x.trot
                    estifm=estif
                    estif=transpose(trot).x.estifm
                    !write(chkunit,*)'ielem=',ielem,'estif='
                    ! do idimn=1,12
                    ! write(chkunit,119)estif(idimn,:)
                    ! end do

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

                    nullify(lnods)

                elseif(index==25)then ! steel 2006
                    lnods=>element(ielem)%field(1)%lnods_f
                    !lnods=>element(ielem)%field(1)%lnods_f
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
                    rotstar=prot(:,:,ipoin)
                    unitx=matmul(rotation,transpose(rotstar))

                    aera    = element(ielem)%area

                    allocate(eldis(nevab))
                    eldis=0.
                    ldofs=>element(ielem)%field(1)%ldofs_f

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
                    if(ikindks/=0)then
                        do inode=1,nnode
                            ipoin=lnods(inode)
                            if (icpspring(ipoin)/=0)exit
                        enddo
                        strabar=pstrain(lnods(inode))
                    endif
                    deallocate(eldis)
                    ks=0.

                    ftx=0. ; fcx=0. ; dx=0.
                    call steel_bond_slip_relation(ikindks,abs(dgap1),ks(1,1),tao,ftx,fcx,dx,strabar,coefMpa)

                    ks(1,1)=ks(1,1)*aera
                    if(abs(element(ielem)%field(1)%gpvar(nstre+5,1)-1.)<0.001)ks(1,1)=0. !for lhg
                    !if (dgap1<0)ks(1,1)=-ks(1,1) !?????????????
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
                    !if(abs(element(ielem)%field(1)%gpvar(nstre+5,1)-1.)<0.001)estif=0. !for lhg
                    nullify(rotation,ldofs,lnods)
                    deallocate(ks,ksx,ddisp,rotstar,unitx)
                endif
                ! assembling to element stiff matrix

                if (alfa_p4>0.and.index==22)then !20231007  对于转动刚度按局部坐标求解时自动赋予指定大值(事实上该自由度已被约束）
                    lnods=>element(ielem)%field(1)%lnods_f
                    if(any(local_p4(lnods)==1))call change_estif_p4
                    nullify(lnods)
                endif  !20231007

                !if(index==1.and.(any(listglocbeam==igroup)))call change_estif_barsteel !可以通过只改变B矩阵实现

                element(ielem)%field(1)%khandmc(1)%fstif=estif*thick
                !if(ielem==763)then
                !    print *,'1'
                !endif
                ! if(ielem==1)then
                !     write(7,*)'ielem=',ielem,'thick=',thick
                !     write(7,*)'estif=',estif
                !endif

                if (special(1:1)=='D')element(ielem)%estifh=estif_dd*thick

                if (special(1:1)=='B') then
                    element(ielem)%estift=estift*thick
                    element(ielem)%estifh=estifh*thick
                endif
100             continue
                if (nnode==2.or.index==22.or.index==26)nullify(rotation)
                !if((material=='DUNCANCHANG'.or.material=='SandPZ').and.type_problem=='F')then !20220728
                !deallocate(eldis)
                !nullify(ldofs)
                !  endif !20220728

                if(material=='DUNCANCHANG'.or.material=='SandPZ'.or.material=='SoilPZ')then !20220728
                    deallocate(eldis)
                    nullify(ldofs)
                endif !20220728



            end do       !!ielgroup
            !if(index.ne.20.and.index.ne.21) then ! not for beam
            if (index.ne.20.and.index.ne.21.and.index/=25) then ! not for beam !steel 2006
                deallocate(sgtot,devia,avect,avecq,dvect,dvecq,bmatx,dbmat)
                deallocate(cartd,ematx,dmatx,gpcod,shape,veca2,veca3)

                !if((material=='DUNCANCHANG'.or.material=='SandPZ').and.type_problem=='F') deallocate(stran) !20220728
                if(material=='DUNCANCHANG'.or.material=='SandPZ'.or.material=='SoilPZ') deallocate(stran) !20220728

                if (type_stiff==2) deallocate(dasig)
                ! for Simo & Rifai element
                if (special(1:1)=='B')deallocate(gmatx,estift,estifh)
                if (special(1:1)=='D')deallocate(estif_dd)
            else if(index.eq.20.or.index.eq.21) then
                deallocate(estifm,trot)
                if(material/='STEEL_SP')nullify(elcod)  !20211125
            elseif(index==25)then
                deallocate(estifm,trot)
            endif !
            ! end for Simo & Rifai element
            deallocate(estif)
        end if        !! for co-displacement group
111     continue  !! for elastic
    end do         !!  for group
    contains

    subroutine change_estif_barsteel !barsteel

    real(irk),allocatable::trot(:,:),estifx(:,:)

    allocate(trot(nevab,nevab),estifx(nevab,nevab))
    trot=0. ; estifx=0.
    trot(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
    trot(ndimn+1:ndimn*2,ndimn+1:ndimn*2)=prot(:,:,lnods(2))

    estifx=matmul(estif,transpose(trot))
    estif=estifx
    estifx=trot.x.estif
    estif=estifx

    deallocate(trot,estifx)

    end subroutine change_estif_barsteel !barsteel

    subroutine change_estif_p4 !20231007

    integer ipoin


    do inode=1,nnode
        ipoin=lnods(inode)
        if(local_p4(ipoin)==0)cycle
        estif(inode*ndimn*2,inode*ndimn*2)=stiff_p4
    enddo


    end subroutine change_estif_p4   !20231007

    subroutine DEP  !20220707

    character(20)criteria,model
    integer(ink) order_int,kload,ntest,istr1,ndiv,idm,first,icr,isat,kind_wt,humidification
    real(irk) pwatr,satur,bulks,bulkd,bioal,bioac,epC,s,et,vt,p3,rot(3)  !20130510
    real(irk),allocatable::dd(:),sigma(:),vdval(:),strsg(:),sig(:),ft(:),dmatxd(:,:)
    real(irk) smax,qmax,phi,density,snorm,ratio,px,p0,lamda
    real(irk),allocatable::evk(:),stran0(:)
    real(irk) Emoduls,mu !20231215YL
    real(irk) normal_gap,scaling_factor


    !initial all varibales !20220713
    pwatr=0.0;satur=0.0;bulks=0.0;bulkd=0.0;bioac=0.0;epc=0.0;rot=0.0
    smax=0.0;qmax=0.0;phi=0.0;density=0.0;snorm=0.0;et=0.0;vt=0.0;lamda=0.0

    !if(ielem==1) &
    !print *,'in dep,ielem=',ielem !20220707

    material_select: select case(material)
    case('PLANE_LOWFT')
        allocate(sig(ndimn-1),ft(ndimn-1),dmatxd(nstre,nstre))
        sig=element(ielem)%field(1)%gpvar(1:ndimn-1,igaus)
        ft=props(matno)%mechanical%solid%Plane_lowft%ft
        call ecmat_lowft(SPtype,sig,ft,dmatxd,e,nu)
        element(ielem)%field(1)%dmatxd(:,:,igaus)=dmatxd     !20130510
        call ecmat_change(dmatxd,dmatx,element(ielem)%rotation)
        deallocate(sig,ft,dmatxd)
    case('DUNCANCHANG')
        select case(type_stiff)
        case (1) ! Standard Dep

            if(type_problem=='Q')then !20231215YL
                if ((appear_process(igroup,iblks-1)==0.or.  &
                    (appear_process(igroup,iblks-1)==1.and.    &
                    appear_process(igroup,iblks)==2))       &
                    .and.iincs==1.and.istep==inc_step.and.idiv==1.and.iiter==1) then
                    sgtot=0.
                    density=props(matno)%mechanical%solid%density
                    ratio=props(matno)%mechanical%solid%ratio
                    kind_wt=props(matno)%mechanical%solid%kind_wt
                    p0=props(matno)%mechanical%solid%DuncanChang%P0  !20220502
                    px=(hdam(iblks)-gpcod(ndimn))*density*gravy*ratio !20220502
                    if(px<p0)px=p0 !20220502


                    phi  =props(matno)%mechanical%solid%DuncanChang%phi
                    phi=phi*3.14159/180.
                    !if (ndimn==2) then  !20220501
                    sgtot(ndimn)=-px
                    sgtot(1:ndimn-1)=sgtot(ndimn)*(1-SIN(phi))
                    if (ndimn==2.and.SPtype(1:2)=='PE')sgtot(4)=sgtot(1)

                    qmax=0.;smax=0.
                else
                    sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                    qmax=element(ielem)%field(1)%gpvar(nstre+1,igaus)
                    smax=element(ielem)%field(1)%gpvar(nstre+2,igaus)
                endif
                isat=0
                if(kind_wt/=0) &
                    isat=element(ielem)%field(1)%isatu(igaus)
                if(ninistn==1)then   !20231215YL
                    Emoduls=element(ielem)%stres0(nstre+3,Igaus)
                    mu=element(ielem)%stres0(nstre+4,Igaus)
                    call ecmat (SPtype,dmatx,Emoduls,mu)
                else !20231215YL
                    call tangceDC(isat,matno,smax,qmax,rot,s,et,vt,p3) !20130510
                endif !20231215YL
                !write(7,*)'igaus=',igaus,'et=',et,'vt=',vt,'p3=',p3,'smax=',smax,'qmax=',qmax
                element(ielem)%field(1)%gpvar(1+nstre,igaus)=Qmax  !20220409
                element(ielem)%field(1)%gpvar(2+nstre,igaus)=Smax  !20220409
                element(ielem)%field(1)%gpvar(3+nstre,igaus)=et
                element(ielem)%field(1)%gpvar(4+nstre,igaus)=vt
                element(ielem)%field(1)%gpvar(5+nstre,igaus)=p3    !20220409

            elseif(type_problem=='F')then  !20231215YL
                if(group(igroup)%kinit_g==2)sgtot=element(ielem)%stres0(:,igaus) !zhao
                CALL INVART(matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
                vt=element(ielem)%field(1)%gpvar0(nstre+4,igaus) !gpvar-->gpvar0 zhao  !nzw 2009-01-15 before nstre+2
                if(vt<0.2)vt=0.2         ! ltc 2013-5-22  for FuChuan
                if(vt>0.4)vt=0.4
                call DUNEd(matno,smean,steff,theta,et,vt,lamda,stran,ielem,igaus) !yuanli20230926
                element(ielem)%field(1)%gpvar0(nstre+1,igaus)=lamda !gpvar-->gpvar0 zhao
                element(ielem)%field(1)%gpvar0(nstre+3,igaus)=et !gpvar-->gpvar0 zhao
                element(ielem)%field(1)%gpvar0(nstre+4,igaus)=vt !gpvar-->gpvar0 zhao
                element(ielem)%field(1)%gpvar(nstre+1,igaus)=lamda
                element(ielem)%field(1)%gpvar(nstre+3,igaus)=et
                element(ielem)%field(1)%gpvar(nstre+4,igaus)=vt !2013.5.18
                call ecmat ( SPtype,dmatx,et,vt)
                if(ntpel.ne.0) bulkt=et/(3.0*(1.0-2.0*vt))
            endif
            case default
            print *, 'SORRY!'
            print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
        end select ! type_stiff
    case('GOODMAN')

        model=props(matno)%mechanical%solid%Goodman%model
        if(model=='FCM')then
            dmatx=0.
            do idm=1,ndimn
                dmatx(idm,idm)=element(ielem)%evk(idm,igaus)
            end do
            !write(7,*)'ie=',ielem,'ig=',igaus,'dmatx=',(dmatx(idm,idm),idm=1,ndimn)
        elseif(model=='JANBU')then

            select case(type_stiff)
            case (1) ! Standard Dep
                sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
                allocate(evk(ndimn))
                first=0
                if(type_problem/='Q') goto 10
                if ((appear_process(igroup,iblks-1)==0.or.  &
                    (appear_process(igroup,iblks-1)==1.and.    &
                    appear_process(igroup,iblks)==2))       &
                    .and.iincs==1.and.istep==inc_step.and.iiter==1.and.idiv==1) first=1
10              continue
                call PKPN(matno,evk,sgtot,first)

                normal_gap = element(ielem)%field(1)%gapg(igaus)-element(ielem)%field(1)%natural_thickness(igaus)

                ! 增加罚函数
                if(normal_gap<0)then
                    !scaling_factor = 1.0d0 + abs(normal_gap/element(ielem)%field(1)%natural_thickness(igaus)) * 10.0d0
                    !evk(ndimn) = (evk(ndimn)/element(ielem)%field(1)%natural_thickness(igaus))*scaling_factor
                    evk(ndimn)=evk(ndimn)*100.0d0
                endif
                where(evk>1.0d9)evk=1.0d9
                
                element(ielem)%evk(:,igaus)=evk
                write(7,*)'ie=',ielem,'igaus=',igaus,'evk=',evk,element(ielem)%field(1)%gapg(igaus),normal_gap
                !write(7,*)'first=',first,'sgtot=',sgtot

                dmatx=0.
                do idm=1,ndimn
                    dmatx(idm,idm)=evk(idm)
                end do
                deallocate(evk)
                case default
                print *, 'SORRY!'
                print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
            end select ! type_stiff

            !20231215YL
        elseif(model=='WATERTIGHT')then !20231007 止水
            allocate(evk(ndimn))
            call PKPN_watertight(matno,element(ielem)%field(1)%relat_dis_gaus(:,igaus),EVK)
            element(ielem)%evk(:,igaus)=evk
            dmatx=0.
            do idm=1,ndimn
                dmatx(idm,idm)=evk(idm)
            end do
            deallocate(evk)

            !20231215YL

        elseif(model=='EQUBOLT') then  !20210913
            sgtot=element(ielem)%field(1)%gpvar(1:nstre,igaus)
            allocate(evk(ndimn))
            call KBOLT(matno,evk,sgtot)
            element(ielem)%evk(:,igaus)=evk
            !write(7,*)'ie=',ielem,'ig=',igaus,'sgtot=',sgtot,'evk=',evk
            dmatx=0.
            do idm=1,ndimn
                dmatx(idm,idm)=evk(idm)
            end do
            deallocate(evk)

        endif

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
                !write(7,*)'ie=',ielem,'ig=',igaus,'yld=',yld
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

        if(ielem==1) &
            print *,'igaus=',igaus !20220707
        allocate(dd(24),vdval(6),sigma(nstre),stran(nstre),strsg(nstre))
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

        if(ielem==1) &
            print *,'vdval=',vdval
        dd=props(matno)%mechanical%solid%SoilPZ%d
        ntest=props(matno)%mechanical%solid%SoilPZ%ntest

        if(type_problem=='Q')then   !20220629
            if((appear_process(igroup,iblks-1)==0.or.	 &
                (appear_process(igroup,iblks-1)==1.and.appear_process(igroup,iblks)==2))		 &
                .and.(type_nl==5.or.(type_nl==4.and.iiter==1))   &
                .and.iincs==1.and.istep==inc_step)then       !20220629

                sgtot=0.
                ratio=props(matno)%mechanical%solid%ratio
                density=gravy*ratio*props(matno)%mechanical%solid%density
                if(group(igroup)%fieldid=='UW')then
                    ratio=props(matno)%mechanical%fluid%ratio
                    density=density+gravy*ratio*props(matno)%mechanical%fluid%density
                endif

                p0=dd(8)  !20220629
                px=(hdam(iblks)-gpcod(ndimn))*density*gravy*ratio !20220629
                if(px<p0)px=p0 !20220629
                phi  =dd(1)
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
                vdval=element(ielem)%egaus(order_int)%vdval0(1:6,igaus)

            endif  !end if((appear_process
        endif   !end if(type_problem=='Q')
        strsg=sgtot
        sigma=strsg

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
        else
            sigma=strsg
        end if
        if (ndimn==2) then
            CALL CHANGE (STRAN)
            CALL CHANGE (SIGMA)
            CALL CHANGE (strsg)
        endif
        stran=0.0
        CALL TESMDL (nstre,strsg,SIGMA,STRAN,DMATX,VDVal,KLOAD,1,ndiv,ntest,dd)
        if(ielem==1)then
            write(7,*)'ielem=',ielem,'igaus=',igaus,'DMATX='
            write(7,105)dmatx(1,:)
            write(7,105)dmatx(2,:)
            write(7,105)dmatx(3,:)
        endif
105     format(10e15.3)

        deallocate(dd,sigma,vdval,strsg)
        !20220713
    case('SandPZ')

        allocate(dd(16),vdval(6),sigma(nstre),strsg(nstre))
        !   if(type_problem=='F')allocate(stran0(nstre))  !20220728
        !if(type_problem=='F')stran0=stran  !20220728

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
        sigma=sgtot  !1017

        dd=props(matno)%mechanical%solid%SandPZ%d
        ntest=props(matno)%mechanical%solid%SandPZ%ntest
        !if(ielem==1)then
        !    write(7,*)'ie=',ielem,'ig=',igaus,'sigma=',sigma
        !endif

        isat=0
        if(type_problem=='Q')then   !!903
            kind_wt=props(matno)%mechanical%solid%kind_wt

            if(kind_wt/=0) &
                isat=element(ielem)%field(1)%isatu(igaus)


            if((appear_process(igroup,iblks-1)==0.or.	 &
                (appear_process(igroup,iblks-1)==1.and.appear_process(igroup,iblks)==2))		 &
                .and.(type_nl==5.or.(type_nl==4.and.iiter==1).or.(type_nl==8.and.iiter==1))   &
                .and.iincs==1.and.istep==inc_step)then       !906

                sgtot=0.
                sigma=0.
                ratio=props(matno)%mechanical%solid%ratio
                density=gravy*ratio*props(matno)%mechanical%solid%density
                if(group(igroup)%fieldid=='UW')then
                    ratio=props(matno)%mechanical%fluid%ratio
                    density=density+gravy*ratio*props(matno)%mechanical%fluid%density
                endif

                p0=dd(8)  !20220629
                px=(hdam(iblks)-gpcod(ndimn))*density*gravy*ratio !20220629
                if(px<p0)px=p0 !20220629
                phi  =dd(1)
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
        !		sigma=strsg  !1017

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

        end if


        humidification=props(matno)%mechanical%solid%SandPZ%humidification
        if(type_problem=='F'.and.humidification==3)then    !得到lamda为了求阻尼比
            if(type_nl==5)then
                stran=element(ielem)%field(1)%gpvar0(nstre+1:2*nstre,igaus)
            elseif(type_nl==4.or.type_nl==8)then
                stran=element(ielem)%field(1)%gpvar(nstre+1:2*nstre,igaus)
            endif

            CALL INVART(matno,nstre,DEVIA,strsg,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)
            !		write(7,*)'ie=',ielem,'igaus=',igaus,'stran=',stran
            steff=steff/sqrt(3.d0);smean=-smean   !因PZ材料在invart子程序里求p、q时与常规不太一样

            call Get_SandPZ_lamda(matno,steff,theta,smean,stran,lamda)
            element(ielem)%egaus(order_int)%vdval(6,igaus)=lamda
            element(ielem)%egaus(order_int)%vdval0(6,igaus)=lamda  !vd(6) 存动力时的lamda
        endif

        !stran=stran0   !20220728
        !stran=0.   !20220728


        CALL mainsandpz(ielem,matno,nstre,strsg,SIGMA,STRAN,DMATX,VDVal,KLOAD,1,dd,ntest)

        !if(ielem==1)then
        !    write(7,*)'ie=',ielem,'ig=',igaus
        !    write(7,*)'dmatx(1,:)=',dmatx(1,:)
        !    write(7,*)'dmatx(2,:)=',dmatx(2,:)
        !    write(7,*)'dmatx(3,:)=',dmatx(3,:)
        !    write(7,*)'dmatx(4,:)=',dmatx(4,:)
        !endif


        deallocate(dd,sigma,vdval,strsg)
        !if(type_problem=='F')deallocate(stran0)   !20220728

        !20220713
        case default
        print *, 'SORRY!'
        print *, 'THIS MATERIAL HAVE NOT BEEN IMPLEMENTED'

    end select  material_select

    end subroutine DEP
    !  GOODMAN    !
    subroutine tangceDC(isat,matno,smax,qmax,rot,s,et,vt,p3)  !20130510

    character(2) model
    integer(ink) matno,isat
    real   (irk) smax,qmax,s,et,vt,p3,rot(:)  !20130510
    model=props(matno)%mechanical%solid%DuncanChang%model

    CALL INVART (matno,nstre,DEVIA,SGTOT,THETA,STEFF,SMEAN,vj2,vj3,sint3,rot)

    if (model=='EV'.or.model=='CR') then
        call DUNE(matno,smean,steff,theta,smax,Qmax,s,et,p3)   !20130510
        call DUNV(matno,smean,s,VT)

    else if(model=='EB')then
        call EBMOD(isat,matno,smean,steff,theta,smax,Qmax,s,et,vt,p3)  !20130510
    else if(model=='EBG')then
        call EBMODg(isat,matno,smean,steff,theta,smax,Qmax,s,et,vt,p3)  !20220409
    endif
    call ecmat ( SPtype,dmatx,et,vt)
    if (ntpel.ne.0) bulkt=et/(3.0*(1.0-2.0*vt))

    end subroutine tangceDC
    !
    subroutine tangcepstd(epC,matno,rot,snorm)

    integer (ink) matno
    real(irk) cons2,cons3,eqstr,preys,epC,rot(:)
    real(irk) harden,harden0,snorm,qfect,Ct

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
    real (irk) p,dlan,dt,varj2,varj3,sint3,theta,steff,eqstr,preys,qfect
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
    !!
    !
    END SUBROUTINE STIFF_U
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    SUBROUTINE STIFF_U1
    character(1)field1
    character(10)SPtype,class,special
    character(30)material
    integer(ink) igroup, nrfields, ifield,  index,      &
        matno,  nstre,    nevab,  nnode, order_int,  &
        ngaus,  ielgroup, ielem,  igaus, i, inode,   &
        lnidmn, aevab,    jnode,  jndex, idimn
    integer(ink) type_stiff
    real   (irk)  e, nu, djacb, yld, theta, steff,    &
        smean, vj3,   abeta,eps, thick
    real   (irk),allocatable::estif(:,:), cartd(:,:),           &
        ematx(:,:), dmatx(:,:),         &
        sgtot(:), devia(:), avect(:),   &
        avecq(:), dvect(:), dvecq(:),   &
        dbmat(:,:),bmatx(:,:),gpcod(:), &
        shape(:),veca2(:),veca3(:)

    eps=1.e-10
    !write(chkunit,*)'dmatx in stiff'
    DO igroup =1,ngroup
        !      print *,'ig=',igroup
        field1= group(igroup)%fieldid(1:1)
        class = group(igroup)%class
        special= group(igroup)%special
        if (appear(igroup)>0.and.field1=='U')then
            ! get information from the group level
            index = group(igroup)%index
            matno = group(igroup)%matno
            material=props(matno)%mechanical%solid%material

            nstre=  group(igroup)%nstre
            SPtype=    group(igroup)%SPtype
            type_stiff=    group(igroup)%type_stiff
            nnode = elkn(index)%el_field(1)%nnode_f
            nevab = nnode*group(igroup)%dof(1)%nfdof
            allocate (estif(nevab,nevab))


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
            thick=1.
            if (ndimn==2)thick=props(matno)%mechanical%solid%thickness

            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus

            allocate(shape(nnode))
            lnidmn =elkn(index)%ndimn

            ! allocate the arrays which will be used
            allocate (cartd(lnidmn,nnode),bmatx(nstre,nevab), dbmat(nstre,nevab))
            allocate (ematx(nstre,nstre),gpcod(ndimn))
            allocate (dmatx(nstre,nstre),sgtot(nstre))
            allocate (devia(nstre), avect(nstre), avecq(nstre),    &
                dvect(nstre), dvecq(nstre))
            allocate (veca2(nstre),veca3(nstre))
            veca2=0.;veca3=0.;avect=0.;avecq=0.;dvect=0.;dvecq=0. ;dbmat=0.
            ! compute the elastic matrix, De or Ds
            ematx=0.
            call ecmat(SPtype,ematx,e,nu)

            ! loop for 1:nelgroup
            DO ielgroup = 1,group1(igroup)%nelgroup
                ielem = group1(igroup)%list(ielgroup)
                if (jce1(ielem)==1) goto 100
                estif=0.0_irk
                do igaus=1,ngaus
                    shape=elkn(index)%ggaus(order_int)%shape(:,igaus)
                    dmatx=ematx
                    ! get djacb and cartd in the element level
                    djacb=element1(ielem)%egaus(order_int)%djacb(igaus)
                    gpcod=element1(ielem)%egaus(order_int)%gpcod(:,igaus)
                    bmatx=0.0
                    cartd=element1(ielem)%egaus(order_int)%cartd(:,:,igaus)
                    ! get bmatrx according to ndimn and SPtype (for ndimn=2)
                    call gbmat   (SPtype, nnode, bmatx, cartd, gpcod, shape)
                    ! compute Dep for nonlinear material

                    if (rmesh<=1.and.kglb==0.and.material(1:7)/='ELASTIC')call dep1

                    dbmat=matmul(dmatx,bmatx)
                    estif=estif+djacb*matmul(transpose(bmatx),dbmat)
                end do     !!igaus
                ! assembling to element stiff matrix

                element1(ielem)%field(1)%khandmc(1)%fstif=estif*thick

100             continue
            end do       !!ielgroup
            deallocate(sgtot,devia,avect,avecq,dvect,dvecq,bmatx,dbmat)
            deallocate(cartd,ematx,dmatx,gpcod,shape,veca2,veca3)
            deallocate(estif)
        end if        !! for co-displacement group
    end do         !!  for group
    contains

    subroutine DEP1

    character(20)criteria
    integer(ink) order_int,icr
    real(irk),allocatable::stran(:),sigma(:),strsg(:)
    real(irk) density,epC,rot(3),snorm
    material_select: select case(material)

    case('CLASSICALEP')
        sgtot=element1(ielem)%field(1)%gpvar(1:nstre,igaus)
        epC=element1(ielem)%field(1)%gpvar(nstre+1,igaus)
        yld=element1(ielem)%field(1)%gpvar(nstre+2,igaus)
        call tangcepstd1(epC,matno,rot,snorm)
    case('CONCRETE')
        select case(type_stiff)
        case (1) ! Standard Dep
            sgtot=element1(ielem)%field(1)%gpvar(1:nstre,igaus)
            yld=element1(ielem)%field(1)%gpvar(nstre+2,igaus)
            epC=element1(ielem)%field(1)%gpvar(nstre+1,igaus)
            icr=0
            if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
            if (icr==1)then
                call dep_concrete_1(element1(ielem)%field(1)%rr(:,:,igaus),matno,yld,dmatx)
                return
            elseif(icr==2.or.icr==3.or.icr==5)then !zhao09
                if (yld>.9)yld=.9
                dmatx=dmatx*(1-yld)**2
                return
            endif
            call tangcepstd1(epC,matno,rot,snorm)
            case default
            print *, 'SORRY!'
            print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
        end select ! type_stiff

        case default
        print *, 'SORRY!'
        print *, 'THIS MATERIAL HAVE NOT BEEN IMPLEMENTED'

    end select  material_select

    end subroutine DEP1

    subroutine tangcepstd1(epC,matno,rot,snorm)

    integer (ink) matno
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

    end subroutine tangcepstd1


    END SUBROUTINE STIFF_U1
    !!

    SUBROUTINE STIFF_U2
    character(1)field1
    character(10)SPtype,class,special
    character(30)material
    integer(ink) igroup, nrfields, ifield,  index,      &
        matno,  nstre,    nevab,  nnode, order_int,  &
        ngaus,  ielgroup, ielem,  igaus, i, inode,   &
        lnidmn, aevab,    jnode,  jndex, idimn
    integer(ink) type_stiff
    real   (irk)  e, nu, djacb, yld, theta, steff,    &
        smean, vj3,   abeta,eps, thick
    real   (irk),allocatable::estif(:,:), cartd(:,:),           &
        ematx(:,:), dmatx(:,:),         &
        sgtot(:), devia(:), avect(:),   &
        avecq(:), dvect(:), dvecq(:),   &
        dbmat(:,:),bmatx(:,:),gpcod(:), &
        shape(:),veca2(:),veca3(:)

    eps=1.e-10
    !write(chkunit,*)'dmatx in stiff'
    DO igroup =1,ngroup
        !      print *,'ig=',igroup
        field1= group(igroup)%fieldid(1:1)
        class = group(igroup)%class
        special= group(igroup)%special
        if (appear(igroup)>0.and.field1=='U')then
            ! get information from the group level
            index = group(igroup)%index
            matno = group(igroup)%matno
            material=props(matno)%mechanical%solid%material

            nstre=  group(igroup)%nstre
            SPtype=    group(igroup)%SPtype
            type_stiff=    group(igroup)%type_stiff
            nnode = elkn(index)%el_field(1)%nnode_f
            nevab = nnode*group(igroup)%dof(1)%nfdof
            allocate (estif(nevab,nevab))


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
            thick=1.
            if (ndimn==2)thick=props(matno)%mechanical%solid%thickness

            order_int=elkn(index)%el_field(1)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_int)%ngaus

            allocate(shape(nnode))
            lnidmn =elkn(index)%ndimn

            ! allocate the arrays which will be used
            allocate (cartd(lnidmn,nnode),bmatx(nstre,nevab), dbmat(nstre,nevab))
            allocate (ematx(nstre,nstre),gpcod(ndimn))
            allocate (dmatx(nstre,nstre),sgtot(nstre))
            allocate (devia(nstre), avect(nstre), avecq(nstre),    &
                dvect(nstre), dvecq(nstre))
            allocate (veca2(nstre),veca3(nstre))
            veca2=0.;veca3=0.;avect=0.;avecq=0.;dvect=0.;dvecq=0. ;dbmat=0.
            ! compute the elastic matrix, De or Ds
            ematx=0.
            call ecmat(SPtype,ematx,e,nu)

            ! loop for 1:nelgroup
            DO ielgroup = 1,group2(igroup)%nelgroup
                ielem = group2(igroup)%list(ielgroup)
                estif=0.0_irk
                do igaus=1,ngaus
                    shape=elkn(index)%ggaus(order_int)%shape(:,igaus)
                    dmatx=ematx
                    ! get djacb and cartd in the element level
                    djacb=element2(ielem)%egaus(order_int)%djacb(igaus)
                    gpcod=element2(ielem)%egaus(order_int)%gpcod(:,igaus)
                    bmatx=0.0
                    cartd=element2(ielem)%egaus(order_int)%cartd(:,:,igaus)
                    ! get bmatrx according to ndimn and SPtype (for ndimn=2)
                    call gbmat   (SPtype, nnode, bmatx, cartd, gpcod, shape)
                    ! compute Dep for nonlinear material
                    if (kglb==0.and.material(1:7)/='ELASTIC')call dep2

                    dbmat=matmul(dmatx,bmatx)
                    estif=estif+djacb*matmul(transpose(bmatx),dbmat)
                end do     !!igaus
                ! assembling to element stiff matrix

                element2(ielem)%field(1)%khandmc(1)%fstif=estif*thick

100             continue
            end do       !!ielgroup
            deallocate(sgtot,devia,avect,avecq,dvect,dvecq,bmatx,dbmat)
            deallocate(cartd,ematx,dmatx,gpcod,shape,veca2,veca3)
            deallocate(estif)
        end if        !! for co-displacement group
    end do         !!  for group
    contains

    subroutine DEP2

    character(20)criteria
    integer(ink) order_int,icr
    real(irk),allocatable::stran(:),sigma(:),strsg(:)
    real(irk) density,epC,rot(3),snorm
    material_select: select case(material)

    case('CLASSICALEP')
        sgtot=element2(ielem)%field(1)%gpvar(1:nstre,igaus)
        epC=element2(ielem)%field(1)%gpvar(nstre+1,igaus)
        yld=element2(ielem)%field(1)%gpvar(nstre+2,igaus)
        call tangcepstd2(epC,matno,rot,snorm)
    case('CONCRETE')
        select case(type_stiff)
        case (1) ! Standard Dep
            sgtot=element2(ielem)%field(1)%gpvar(1:nstre,igaus)
            yld=element2(ielem)%field(1)%gpvar(nstre+2,igaus)
            epC=element2(ielem)%field(1)%gpvar(nstre+1,igaus)
            icr=0
            if (material=='CONCRETE')icr=props(matno)%mechanical%solid%Concrete%icr
            if (icr==1)then
                call dep_concrete_1(element2(ielem)%field(1)%rr(:,:,igaus),matno,yld,dmatx)
                return
            elseif(icr==2.or.icr==3.or.icr==5)then !zhao09
                if (yld>.9)yld=.9
                dmatx=dmatx*(1-yld)**2
                return
            endif
            call tangcepstd2(epC,matno,rot,snorm)
            case default
            print *, 'SORRY!'
            print *, 'THIS TYPE_STIFF HAS NOT BEEN IMPLEMENTED'
        end select ! type_stiff

        case default
        print *, 'SORRY!'
        print *, 'THIS MATERIAL HAVE NOT BEEN IMPLEMENTED'

    end select  material_select

    end subroutine DEP2

    subroutine tangcepstd2(epC,matno,rot,snorm)

    integer (ink) matno
    real(irk) cons2,cons3,eqstr,preys,epC,rot(:)
    real(irk) harden,harden0,qfect,Ct,snorm,vj2,sint3

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

    end subroutine tangcepstd2


    END SUBROUTINE STIFF_U2
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!
    subroutine effective_strain(nstre,epi,eps,icc,Ct)
    real   (irk) epi(:),eps,sx,sy,sxy,delta,main_epi(3),Ct
    integer(ink) nstre,icc,i
    if (icc==0)then
        if (ndimn==1.or.nstre==1)then  !2021108
            eps=epi(1)
            return
        else if(ndimn==2)then
            eps=epi(1)**2+epi(2)**2+2.*epi(3)**2
            if (nstre==4)eps=eps+epi(4)**2
        else if(ndimn==3) then
            eps=epi(1)**2+epi(2)**2+epi(3)**2  &
                +2.*(epi(4)**2+epi(5)**2+epi(6)**2)
        endif
        eps=sqrt(2./3.*eps)
    else
        eps=0.
        if (ndimn==1)then
            if (epi(1)>0.)eps=epi(1)
            return
        else if(ndimn==2)then
            sx=epi(1)
            sy=epi(2)
            sxy=epi(3)
            delta=sqrt((sx-sy)**2/4+sxy**2)
            main_epi(1)=(sx+sy)/2.+delta
            main_epi(2)=(sx+sy)/2.-delta

            do i=1,2
                if (main_epi(i)>0.)then
                    eps=eps+main_epi(i)**2
                else
                    eps=eps+Ct*main_epi(i)**2
                endif
            end do
            if (nstre==4)then
                if (epi(4)>0.)then
                    eps=eps+epi(4)**2
                else
                    eps=eps+Ct*epi(4)**2
                endif
            endif
        else if(ndimn==3) then
            call main_strain(epi,main_epi)
            do i=1,3
                if (main_epi(i)>0.)then
                    eps=eps+main_epi(i)**2
                else
                    eps=eps+Ct*main_epi(i)**2
                endif
            end do
        endif
        eps=sqrt(eps)
    endif
    end subroutine effective_strain

    subroutine main_strain ( stemp, strem)
    !
    !      obtain the main strain or stress and corresponding directions
    !
    real   (irk) devia(6), stemp(:), strem(:)
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
    return
    end subroutine main_strain
    !!
    subroutine stif_p4_st(ielem,elcod,rotation,e,nu,t,estif)
    integer(ink) ielem,i,j,inode,jnode,idofn,jdofn,i0,j0
    real (irk) e,nu,t,a,b,a2,b2,x1,x2,elcod(:,:),rotation(:,:),estif(:,:)
    real (irk),allocatable::stifb(:,:),stifp(:,:),stif1(:,:),stif2(:,:),rott(:,:),stif(:,:)

    allocate(stifb(12,12),stifp(8,8),stif1(24,24),stif2(24,24),rott(24,24),stif(24,24))
    stif=0.;stifb=0.;stifp=0.;stif1=0.;stif2=0.;rott=0.

    a=sum((elcod(:,2)-elcod(:,1))**2)
    a=.5*sqrt(a)
    b=sum((elcod(:,4)-elcod(:,1))**2)
    b=.5*sqrt(b)
    a2=a**2;b2=b**2
    x1=(b/a)**2;x2=(a/b)**2
    stifb(1,1)=21-6*nu+30*x1+30*x2;stifb(4,4)=stifb(1,1);stifb(7,7)=stifb(1,1);stifb(10,10)=stifb(1,1)
    stifb(2,2)=8*(1-nu)*b2+40*a2;stifb(5,5)=stifb(2,2);stifb(8,8)=stifb(2,2);stifb(11,11)=stifb(2,2)
    stifb(3,3)=8*(1-nu)*a2+40*b2;stifb(6,6)=stifb(3,3);stifb(9,9)=stifb(3,3);stifb(12,12)=stifb(3,3)
    stifb(2,1)=3*b+12*nu*b+30*a2/b;stifb(5,4)=stifb(2,1)

    stifb(3,1)=-3*a-12*nu*a-30*b2/a;stifb(3,2)=-30*nu*a*b

    stifb(4,1)=-21+6*nu-30*x1+15*x2;stifb(4,2)=-3*b-12*nu*b+15*a2/b;stifb(4,3)=3*a*(1-nu)+30*b2/a

    stifb(5,1)=-3*b-12*nu*b+15*a2/b;stifb(5,2)=8*(nu-1)*b2+20*a2

    stifb(6,1)=3*a*(nu-1)-30*b2/a;stifb(6,3)=2*a2*(nu-1)+20*b2;stifb(6,4)=3*a*(1+4*nu)+30*b2/a;stifb(6,5)=30*nu*a*b

    stifb(7,1)=21-6*nu-15*x1-15*x2;stifb(7,2)=3*b*(1-nu)-15*a2/b;stifb(7,3)=3*a*(nu-1)+15*b2/a
    stifb(7,4)=-21+6*nu+15*x1-30*x2;stifb(7,5)=3*b*(nu-1)-30*a2/b
    stifb(7,6)=-3*a*(1+4*nu)+15*b2/a

    stifb(8,1)=3*b*(nu-1)+15*a2/b;stifb(8,2)=2*b2*(1-nu)+10*a2;stifb(8,4)=3*b*(1-nu)+30*a2/b
    stifb(8,5)=2*b2*(nu-1)+20*a2;stifb(8,7)=-3*b*(1+4*nu)-30*a2/b

    stifb(9,1)=3*a*(1-nu)-15*b2/a;stifb(9,3)=2*a2*(1-nu)+10*b2;stifb(9,4)=-3*a*(1+4*nu)+15*b2/a
    stifb(9,6)=8*a2*(nu-1)+20*b2;stifb(9,7)=3*a*(1+4*nu)+30*b2/a;stifb(9,8)=-30*nu*a*b

    stifb(10,1)=-21+6*nu+15*x1-30*x2;stifb(10,2)=3*b*(nu-1)-30*a2/b;stifb(10,3)=3*a*(1+4*nu)-15*b2/a
    stifb(10,4)=21-6*nu-15*x1-15*x2;stifb(10,5)=3*b*(1-nu)-15*a2/b;stifb(10,6)=3*a*(1-nu)-15*b2/a
    stifb(10,7)=-21+6*nu-30*x1+15*x2;stifb(10,8)=3*b*(1+4*nu)-15*a2/b;stifb(10,9)=3*a*(nu-1)-30*b2/a

    stifb(11,1)=3*b*(1-nu)+30*a2/b;stifb(11,2)=2*b2*(nu-1)+20*a2;stifb(11,4)=3*b*(nu-1)+15*a2/b;
    stifb(11,5)=2*b2*(1-nu)+10*a2;stifb(11,7)=3*b*(1+4*nu)-15*a2/b;stifb(11,8)=8*b2*(nu-1)+20*a2;
    stifb(11,10)=-3*b*(1+4*nu)-30*a2/b

    stifb(12,1)=3*a*(1+4*nu)-15*b2/a;stifb(12,3)=8*a2*(nu-1)+20*b2;stifb(12,4)=3*a*(nu-1)+15*b2/a
    stifb(12,6)=2*a2*(1-nu)+10*b2;stifb(12,7)=3*a*(1-nu)+30*b2/a;stifb(12,9)=2*a2*(nu-1)+20*b2
    stifb(12,10)=-3*a*(1+4*nu)-30*b2/a;stifb(12,11)=30*nu*a*b
    do i=1,12
        do j=i+1,12
            stifb(i,j)=stifb(j,i)
        end do
    end do
    stifb=stifb*e*t**2/(1-nu**2)/360/(a*b)


    x1=b/a;x2=a/b
    stifp(1,1)=x1/3+(1-nu)/6*x2
    stifp(2,1)=(1+nu)/8;stifp(2,2)=x2/3+(1-nu)/6*x1
    stifp(3,1)=-X1/3+(1-nu)/12*X2;stifp(3,2)=(1-3*nu)/8;stifp(3,3)=stifp(1,1)
    stifp(4,1)=-(1-3*nu)/8;stifp(4,2)=x2/6-(1-nu)/6*x1;stifp(4,3)=-(1+nu)/8;stifp(4,4)=stifp(2,2)
    stifp(5,1)=-x1/6-(1-nu)/12*x2;stifp(5,2)=-(1+nu)/8;stifp(5,3)=x1/6-(1-nu)/6*x2;stifp(5,4)=(1-3*nu)/8
    stifp(5,5)=stifp(1,1)

    stifp(6,1)=-(1+nu)/8;stifp(6,2)=-x2/6-(1-nu)/12*x1;stifp(6,3)=-(1-3*nu)/8
    stifp(6,4)=-x2/3+(1-nu)*x1/12;stifp(6,5)=(1+nu)/8;stifp(6,6)=stifp(2,2)

    stifp(7,1)=x1/6-(1-nu)*x2/6;stifp(7,2)=-(1-3*nu)/8;stifp(7,3)=-x1/6-(1-nu)*x2/12
    stifp(7,4)=(1+nu)/8;stifp(7,5)=-x1/3+(1-nu)*x2/12;stifp(7,6)=(1-3*nu)/8;stifp(7,7)=stifp(1,1)

    stifp(8,1)=(1-3*nu)/8;stifp(8,2)=-x2/3+(1-nu)*x1/12;stifp(8,3)=(1+nu)/8
    stifp(8,4)=-x2/6-(1-nu)*x1/12;stifp(8,5)=-(1-3*nu)/8;stifp(8,6)=x2/6-(1-nu)*x1/6
    stifp(8,7)=-(1+nu)/8;stifp(8,8)=stifp(2,2)

    do i=1,8
        do j=i+1,8
            stifp(i,j)=stifp(j,i)
        end do
    end do
    stifp=stifp*e/(1-nu**2)


    do inode=1,4
        do i=1,2
            do jnode=1,4
                do j=1,2
                    idofn=(inode-1)*6+i
                    jdofn=(jnode-1)*6+j
                    i0=(inode-1)*2+i
                    j0=(jnode-1)*2+j
                    stif(idofn,jdofn)=stifp(i0,j0)
                end do
            end do
        end do
    end do

    do inode=1,4
        do i=1,3
            do jnode=1,4
                do j=1,3
                    idofn=(inode-1)*6+i+2
                    jdofn=(jnode-1)*6+j+2
                    i0=(inode-1)*3+i
                    j0=(jnode-1)*3+j
                    stif(idofn,jdofn)=stifb(i0,j0)
                end do
            end do
        end do
    end do


    do inode=1,4
        i0=(inode-1)*6+1
        j0=(inode-1)*6+3
        rott(i0:j0,i0:j0)=rotation; rott((i0+3):(j0+3),(i0+3):(j0+3))=rotation
    end do

    stif1=stif.x.rott
    stif2=transpose(rott).x.stif1

    estif=stif2

    deallocate(stif,stif1,stif2,rott,stifb,stifp)

    end subroutine stif_p4_st
    !!

    subroutine hardsmodu(matno,epstn,harden0,steff,theta,smean,effstc)
    integer (ink) matno,csigma0,cfrict,im,cft
    real (irk) uniax,frict,hards,hardf,steff,theta,smean,effstc
    real (irk)  a,ff,Gf,h,Ct,harden0,epstn,sigma1,hardt,sigma3,ft
    character(20) material,criteria
    hards=0.0;hardt=0.0;hardf=0.0
    material=props(matno)%mechanical%solid%material
    if (material=='CLASSICALEP') then
        harden0=props(matno)%mechanical%solid%classicalEP%hardening
        criteria=props(matno)%mechanical%solid%classicalEP%criteria

        csigma0=props(matno)%mechanical%solid%classicalEP%csigma0
        if (csigma0/=0)call parameter_find(csigma0,epstn,uniax,hards)

        if (criteria(1:2)=='MC'.or.criteria(1:2)=='DP') then
            frict=props(matno)%mechanical%solid%classicalEP%frict_angle

            cfrict=props(matno)%mechanical%solid%classicalEP%cfrict
            if (cfrict/=0)call parameter_find(cfrict,epstn,frict,hardf)

            if (criteria=='MCC'.or.criteria=='DPC') then
                im=1
                sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
                if (sigma1<0.)im=0
                if (im==1) then
                    cft=props(matno)%mechanical%solid%classicalEP%cft
                    ft=props(matno)%mechanical%solid%classicalEP%ft
                    if (cft/=0)call parameter_find(cft,epstn,ft,hardt)
                endif
            endif
        endif

        if (csigma0/=0) harden0=hards
        if (criteria=='MC'.or.(criteria=='MCC'.and.im==0))harden0=harden0*cos(frict)
        if (criteria=='DP'.or.(criteria=='DPC'.and.im==0))   &
            harden0=harden0*6*cos(frict)/sqrt(3.)/(3.-sin(frict))

        if (criteria=='MCC'.and.im==1)harden0=harden0*cos(frict)*(1-sigma1/ft)
        if (criteria=='DPC'.and.im==1)   &
            harden0=harden0*6*cos(frict)/sqrt(3.)/(3.-sin(frict))*(1-sigma1/ft)

        if (cfrict/=0) then
            if (criteria=='MC'.or.(criteria=='MCC'.and.im==0))    &
                harden0=harden0-(smean*cos(frict)-steff/sqrt(3.)*sin(theta)*   &
                cos(frict)+uniax*sin(frict))*hardf

            if (criteria=='DP'.or.(criteria=='DPC'.and.im==0))    &
                harden0=harden0-6.*hardf*(3*smean*cos(frict)-                  &
                uniax*(1-3*sin(frict)))/sqrt(3.)/(3-sin(frict))**2

            if (criteria=='MCC'.and.im==1) then
                sigma3=2*steff/sqrt(3.)*sin(theta-2.*3.14159/3.)+smean
                harden0=harden0-(uniax*sin(frict)*(1-sigma1/ft)+cos(frict)*.5*sigma3)*hardf
            elseif(criteria=='DPC'.and.im==1) then
                harden0=harden0-6.*hardf*((3*smean-sigma1)*cos(frict)-                  &
                    uniax*(1-sigma1/ft)*(1-3*sin(frict)))/sqrt(3.)/(3-sin(frict))**2
            endif

            if (smean<0..and.criteria=='MCJOINT') then
                harden0=harden0-1/cos(frict)**2*smean*hardf
            else if(smean>=0..and.criteria=='MCJOINT') then
                cft=props(matno)%mechanical%solid%classicalEP%cft
                ft=props(matno)%mechanical%solid%classicalEP%ft
                hardt=0.0
                if (cft/=0)call parameter_find(cft,epstn,ft,hardt)
                harden0=harden0-uniax/ft**2*smean*hardt
            endif


        endif

        if (cft/=0.and.im==1.and.criteria(3:3)=='C') then
            if (criteria(1:2)=='MC')harden0=harden0+uniax*cos(frict)*sigma1/ft**2*hardt
            if (criteria(1:2)=='DP')harden0=harden0+6*uniax*cos(frict)/sqrt(3.)/(3.-sin(frict))  &
                *sigma1/ft**2*hardt
        endif


    else if(material=='CONCRETE') then

        A=props(matno)%mechanical%solid%Concrete%A
        Ff=props(matno)%mechanical%solid%Concrete%Fc
        Gf=props(matno)%mechanical%solid%Concrete%Gf
        H =props(matno)%mechanical%solid%Concrete%h
        Ct =props(matno)%mechanical%solid%Concrete%Ct
        harden0=-(a*steff**2/effstC**2+1)*h*ff**2*Ct/Gf*exp(-h*ff*epstn*Ct/Gf*Ct)
    endif
    end subroutine hardsmodu


    !************************************************************************
    !  for Simo & Rifai element
    subroutine estif_sr(estif,dmatx,gmatx,dbmat,djacb,    &
        estift,estifh,igaus,ngaus)
    integer(ink) evabgd,evabsr,igaus,ngaus,irank,ii
    real   (irk) djacb,estif(:,:),dmatx(:,:),gmatx(:,:),  &
        dbmat(:,:), estift(:,:),estifh(:,:),tol
    real   (irk),allocatable::estifhi(:,:),estifhit(:,:),  &
        estiftht(:,:),dgmat(:,:)

    evabgd=size(dmatx,dim=1)
    evabsr=size(gmatx,dim=2)

    allocate(dgmat(evabgd,evabsr))
    dgmat=dmatx.x.gmatx


    estift=estift+matmul(transpose(gmatx),dbmat)*djacb
    estifh=estifh+matmul(transpose(gmatx),dgmat)*djacb
    deallocate(dgmat)

    if (igaus.lt.ngaus) return

    evabgd=size(estif,dim=1)  !2
    evabsr=size(gmatx,dim=2)         !2

    allocate(estifhi(evabsr,evabsr),estifhit(evabsr,evabgd), &
        estiftht(evabgd,evabgd))
    !*** from  imsl**

    call householder(estifh,estift,estifhit)  !3
    estiftht=transpose(estift).x.estifhit
    estif=estif-estiftht
    deallocate(estifhi,estifhit,estiftht)

    end subroutine estif_sr

    !************************************************************************
    !  for second order incompatible elements
    subroutine estif_dr(index,nnode,lnods,estif,estif_dd,nevab,nevab_dd)
    integer(ink) nevab,nevab_dd,evabsr,lnods(:),nev,  &
        nnode,nnod1,nnod2,itotv1,itotv2,idimn,inode,index
    real   (irk) estif(:,:),estif_dd(:,:)
    real   (irk),allocatable::estif1(:,:),estif2(:,:),  &
        estif21(:,:),estif2i21(:,:),estif11(:,:)
    goto 10
    do inode=1,nnode
        nnod1=lnods(inode)
        if (inode<nnode) nnod2=lnods(inode+1)
        if (inode==nnode)nnod2=lnods(1)
        do idimn=1,ndimn
            itotv1=nodfn(idimn,nnod1)
            itotv2=nodfn(idimn,nnod2)
            nev=(nnode+inode-1)*ndimn+idimn
            if (iffix(itotv1)==1.and.iffix(itotv2)==1)then
                estif_dd(1:nev-1,nev)=0.
                estif_dd(nev+1:nevab_dd,nev)=0.
                estif_dd(nev,1:nev-1)=0.
                estif_dd(nev,nev+1:nevab_dd)=0.
            endif
        end do
    end do
    if (index==10)then
        do inode=1,4
            nnod1=lnods(inode)
            nnod2=lnods(inode+4)
            do idimn=1,ndimn
                itotv1=nodfn(idimn,nnod1)
                itotv2=nodfn(idimn,nnod2)
                nev=(16+inode-1)*ndimn+idimn
                if (iffix(itotv1)==1.and.iffix(itotv2)==1)estif_dd(nev,nev)=1.e20
            end do
        end do
    endif

10  evabsr=nevab_dd-nevab

    allocate(estif1(nevab,nevab),estif21(evabsr,nevab), &
        estif2(evabsr,evabsr),estif2i21(evabsr,nevab),estif11(nevab,nevab))
    estif1=estif_dd(1:nevab,1:nevab)
    estif2=estif_dd(nevab+1:nevab_dd,nevab+1:nevab_dd)
    estif21=estif_dd(nevab+1:nevab_dd,1:nevab)

    estif2i21=0.
    call householder(estif2,estif21,estif2i21)  !3
    estif11=0.
    estif11=transpose(estif21).x.estif2i21
    estif=estif1-estif11
    deallocate(estif1,estif2,estif11,estif21,estif2i21)

    end subroutine estif_dr



    !************************************************************************
    !  !nstoks
    subroutine estif_nstoks(matno,ielem,nnode,djacb,shape,cartd,estif)

    integer(ink) ielem,nnode,matno,  &
        idimn,jdimn,inode,jnode,ievab,jevab
    real   (irk) djacb,estif(:,:),shape(:),cartd(:,:)
    real   (irk) density,xxx,vstrn
    real   (irk),allocatable::vgaus(:),veloc(:)
    integer(ink),pointer::ldofs(:)

    allocate(vgaus(ndimn),veloc(ndimn*nnode))
    density=props(matno)%mechanical%solid%density
    ldofs => element(ielem)%field(1)%ldofs_f
    veloc =  result_first(ldofs)

    vstrn=0.
    do idimn=1,ndimn
        vgaus(idimn)=0.
        do inode=1,nnode
            ievab=(inode-1)*ndimn+idimn
            vgaus(idimn)=vgaus(idimn)+shape(inode)*veloc(ievab)
            vstrn=vstrn+veloc(ievab)*cartd(idimn,inode)
        end do
    end do


    do idimn=1,ndimn
        do inode=1,nnode
            ievab=(inode-1)*ndimn+idimn
            do jdimn=1,ndimn
                do jnode=1,nnode
                    jevab=(jnode-1)*ndimn+jdimn
                    xxx=vgaus.d.cartd(:,jnode)
                    estif(ievab,jevab)=estif(ievab,jevab)+   &
                        (shape(inode)*vstrn*shape(jnode)+shape(inode)*xxx)*density*djacb
                end do
            end do
        end do
    end do

    deallocate(vgaus,veloc)

    end subroutine estif_nstoks



    SUBROUTINE HMATRX(WT)
    character(1)WT
    character(10)fieldid,name
    character(30)material
    integer(ink) igroup, nrfields, ifield,  index,            &
        matno,   nnode, order_intx,  in,  jn,         &
        ngaus,  ielgroup, ielem, igaus, order_int, idimn
    real   (irk)  djacb,  coef, permr, elknmk
    real   (irk),allocatable::hmatx(:,:), cartd(:,:)
    real   (irk),pointer:: perme(:)
    !! stablize
    integer(ink) ifieldd
    character(10)field1
    real   (irk) factw,facts,ratio,poros,satur,density
    real   (irk),allocatable::hstar(:,:),permx(:)
    !! end of stablize

    DO igroup =1,ngroup
        !print *,'igroup=',igroup
        if (appear(igroup)>0) then
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            do ifield=1,nrfields
                if (fieldid(ifield:ifield)==WT)goto 1
            end do
            goto 10
            ! get information from the group level
1           index = group(igroup)%index
            matno = group(igroup)%matno
            name=props(matno)%name
            if (name=='NSTOKS') goto 10  !!nstoks
            !print *,'igroup_r=',igroup
            nnode = elkn(index)%el_field(ifield)%nnode_f
            order_intx=elkn(index)%el_field(ifield)%order_intrules(1)
            ngaus = elkn(index)%ggaus(order_intx)%ngaus
            if (WT=='W')then
                if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
                    allocate(perme(ndimn))
                    perme=xvalue(props(matno)%mechanical%fluid%iperm)
                else
                    perme=> props(matno)%mechanical%fluid%permeability
                endif
            endif
            ! allocate the arrays which will be used
            allocate (hmatx(nnode,nnode),cartd(ndimn,nnode),permx(ndimn))

            !! stablize
            if (stabpw==1) then
                allocate(hstar(nnode,nnode))
                do ifieldd=1,nrfields           !!! do for density
                    field1=fieldid(ifieldd:ifieldd)
                    if (field1=='U') then
                        density=props(matno)%mechanical%solid%density
                        ratio  =props(matno)%mechanical%solid%ratio
                        facts=density*ratio
                    else if(field1=='W') then
                        density=props(matno)%mechanical%fluid%density
                        ratio  =props(matno)%mechanical%fluid%ratio
                        factw=density*ratio
                    endif
                end do                      !!! end do for density
            endif
            !! end of stablize

            coef=-1.0  ! coef is for symmetric coupling requirement
            if (type_problem=='E')coef=1.
            if (type_problem/='Q'.and.type_problem/='E') then
                coef=-theta1*ditime
                if (type_problem=='F'.and.nrfields==2)coef=-theta1/beeta1
                if (WT=='W'.and.type_problem=='F'.and.ifsnedge/=0)coef=-beeta2*ditime**2 !ifs2006 zhao, 06/03/29
            endif

            ! loop for 1:nelgroup
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                hmatx=0.0_irk
                if (stabpw==1)hstar=0.0  !! stablize
                do igaus=1,ngaus
                    ! get djacb and cartd in the element level
                    djacb=element(ielem)%egaus(order_intx)%djacb(igaus)
                    cartd=element(ielem)%egaus(order_intx)%cartd(:,:,igaus)

                    if (WT=='W')permx=perme
                    if (fieldid(1:1)=='W') then  !new
                        material=props(matno)%name
                        if (material(1:6)=='NSSoil') then

                            order_int=elkn(index)%el_field(1)%order_intrules(1)
                            permr=element(ielem)%egaus(order_int)%permr(igaus)
                            permx=perme*permr
                        endif
                    end if


                    if (fieldid(1:2)=='UW') then
                        material=props(matno)%name
                        if (material(1:6)=='NSSoil') then

                            order_int=elkn(index)%el_field(2)%order_intrules(1)
                            permr=element(ielem)%egaus(order_int)%permr(igaus)
                            permx=perme*permr

                            !! stablize
                            if (stabpw==1) then
                                density=props(matno)%mechanical%fluid%density
                                poros=element(ielem)%egaus(order_int)%poros(igaus)
                                satur=element(ielem)%egaus(order_int)%satur(igaus)
                                factw=density*poros*satur
                            endif
                            !! end of stablize
                        endif

                    endif


                    do in=1,nnode
                        do jn=1,nnode
                            elknmk=0.0
                            do idimn=1,ndimn
                                elknmk=elknmk+permx(idimn)*cartd(idimn,in)*cartd(idimn,jn)
                            end do
                            hmatx(in,jn)=hmatx(in,jn)+djacb*elknmk
                            !! stablize
                            if (stabpw==1) then
                                elknmk=0.0;density=factw+facts
                                do idimn=1,ndimn
                                    elknmk=elknmk+cartd(idimn,in)*cartd(idimn,jn)
                                end do
                                hstar(in,jn)=hstar(in,jn)+djacb*elknmk/density
                            endif
                            !! end of stablize
                        end do
                    end do
                end do     !!igaus
                ! assembling to element stiff matrix
                element(ielem)%field(ifield)%khandmc(1)%fstif=hmatx*coef
                !! stablize
                if (stabpw==1)  &
                    element(ielem)%field(ifield)%khandmc(1)%hstar=hstar
                !! end of stablize
            end do       !!ielgroup
            deallocate(hmatx,cartd,permx)
            if (stabpw==1)deallocate(hstar)  !! stablize
            if (WT=='W')then
                if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
                    deallocate(perme)
                else
                    nullify(perme)
                endif
            endif

10          continue
        end if        !! for appear group
    end do         !!  for group


    END SUBROUTINE HMATRX

    SUBROUTINE MCMATRX(UPW) !! for mass and compressibility matrix
    character(10)fieldid,material,special
    character(1)field1,UPW
    integer(ink) igroup, nrfields, ifield, ifieldd,  index,    &
        matno,   nnode, order_int,order_int0,  in, type_mass,    &
        ngaus,  ielgroup, ielem,  igaus, nevab,    &
        ndofn, idofn, jn, jdofn,order_intx, aevab,nstre,idimn
    integer(ink),pointer::lnods(:)
    real   (irk)  djacb, bulkt, bulkw, fact, e, nu, ratio, density, &
        dvolu, tdiagm, coef,facts,factw,thick
    real   (irk) ppp,xkd,xks,poros,satur,csmos,bioal,pwatr
    real   (irk),allocatable::cmatx(:,:), shape(:), diagm(:), value(:)
    real   (irk),allocatable::gmatx(:,:),estifh(:,:),qmatxa(:,:)
    DO igroup =1,ngroup
        !if (appear(igroup)>0) then
        nrfields=group(igroup)%nrfields
        fieldid=group(igroup)%fieldid
        do ifield=1,nrfields
            if (fieldid(ifield:ifield)==UPW)goto 1
        end do
        goto 10
        ! get information from the group level
1       special= group(igroup)%special
        index    = group(igroup)%index
        matno = group(igroup)%matno
        material=props(matno)%name
        type_mass= group(igroup)%type_mass(ifield)
        order_int=elkn(index)%el_field(ifield)%order_intrules(2) !2006NS

        thick=1.
        if (fieldid(1:1)=='U'.and.ndimn==2.or.index==22.or.index==26)thick  =props(matno)%mechanical%solid%thickness

        if (fieldid(1:2)=='UW'.and.UPW=='W') then
            if (material(1:6)=='NSSoil') then
                xks=props(matno)%mechanical%fluid%bulks
                xkd=props(matno)%mechanical%fluid%bulkd
                order_int=elkn(index)%el_field(2)%order_intrules(2)
                order_intx=elkn(index)%el_field(1)%order_intrules(1)
                if (order_int/=order_intx.and.material=='NSSoilPZ') then
                    allocate(value(npoin))
                    call recoverx(igroup,'EPRES',value)
                endif
            endif
        endif
        coef=-1.0  ! coef is for symmetric coupling requirement
        if (material/='NSTOKS'.and.UPW/='U')then  !!nstoks
            if (UPW=='W'.and.type_problem/='Q') then
                coef=-theta1*ditime
                if (type_problem=='F'.and.nrfields==2)coef=-theta1/beeta1
                if (type_problem=='F'.and.ifsnedge/=0)coef=-beeta2*ditime**2 !ifs2006 zhao, 06/03/29
            endif
        endif

        if (UPW=='U') then   !! for mass matrix
            coef=1.0
            fact=0.0_irk
            if (material=='NSTOKS')then  !!nstoks
                coef=2.0
                facts=props(matno)%mechanical%solid%density
                factw=0.
            else
                do ifieldd=1,nrfields           !!! do for density
                    field1=fieldid(ifieldd:ifieldd)
                    if (field1=='U') then
                        density=props(matno)%mechanical%solid%density
                        ratio  =props(matno)%mechanical%solid%ratio
                        facts=density*ratio
                        write(7,*)'igroup=',igroup,'matno=',matno,'density=',density,'facts=',facts
                    else if(field1=='W') then
                        density=props(matno)%mechanical%fluid%density
                        ratio  =props(matno)%mechanical%fluid%ratio
                        factw=density*ratio
                    endif
                end do                      !!! end do for density
            endif
        else if(UPW=='P') then   !! for U-P compressibility matrix

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
            bulkt   =e/3./(1.-2.*nu)
            fact   =1./bulkt

        else if(UPW=='W') then  !! for U-W compressibility matrix

            if (material=='NSTOKS') then  !!nstoks
                bulkw   =props(matno)%mechanical%fluid%bulkw
                fact    =1./bulkw
            else
                bulkw   =props(matno)%mechanical%fluid%bulkw
                ratio   =props(matno)%mechanical%fluid%ratio
                fact   =ratio/bulkw
            endif

        endif

        if (index/=20.and.index/=21.and.index/=22.and.index/=26)then  !! 2000  20230910(薄膜单元不考虑质量矩阵)
            nnode = elkn(index)%el_field(ifield)%nnode_f
            ndofn=  group(igroup)%dof(ifield)%nfdof
            nevab=    nnode*ndofn
            order_intx=elkn(index)%el_field(ifield)%order_intrules(2)
            ngaus = elkn(index)%ggaus(order_intx)%ngaus

            write(7,*)'igroup=',igroup,'order_intx=',order_intx,'ngaus=',ngaus
            ! allocate the arrays which will be used
            allocate (shape(nnode))
            if (type_mass==0)allocate (diagm(nnode),cmatx(nevab,1))
            if (type_mass==1)allocate (cmatx(nevab,nevab))


            !     Simo & Rifai element

            if  (fieldid(1:2)=='UW'.and.UPW=='W'.AND.special(1:1)=='B' ) then
                nstre=  group(igroup)%nstre
                if (ndimn==2) then
                    if (special(2:2)=='A') aevab=2
                    if (special(2:2)=='B') aevab=4
                    if (special(2:2)=='C') aevab=7
                    if (special(2:2)=='D') aevab=11
                else if(ndimn==3) then
                    if (special(2:2)=='A') aevab=3
                    if (special(2:2)=='B') aevab=9
                    if (special(2:2)=='C') aevab=24
                    if (special(2:2)=='D') aevab=30
                endif

                allocate(gmatx(nstre,aevab),estifh(aevab,aevab),qmatxa(aevab,nevab))

            endif
            ! end for Simo & Rifai element

            ! loop for 1:nelgroup
            DO ielgroup = 1,group(igroup)%nelgroup
                ielem = group(igroup)%list(ielgroup)
                lnods => element(ielem)%field(ifield)%lnods_f
                cmatx=0.0
                if (type_mass==0)then
                    diagm=0.0
                    dvolu=0.0
                endif
                do igaus=1,ngaus

                    shape = elkn(index)%ggaus(order_intx)%shape(:,igaus)

                    if (fieldid(1:2)=='UW'.and.UPW=='W') then
                        if (material(1:6)=='NSSoil') then !此处material-->name
                            pwatr=element(ielem)%egaus(order_int)%pwatr(igaus)
                            csmos=element(ielem)%egaus(order_int)%csmos(igaus)
                            poros=element(ielem)%egaus(order_int)%poros(igaus)
                            satur=element(ielem)%egaus(order_int)%satur(igaus)

                            if (material=='NSSoilPZ') then  !此处material-->name
                                if (.not.allocated(value)) then
                                    ppp=element(ielem)%egaus(order_int)%vdval(5,igaus)
                                else
                                    ppp=shape.d.value(lnods)
                                endif
                                xkd=ppp*props(matno)%mechanical%solid%SoilPZ%d(9)
                            endif

                            bioal=1.
                            if (xks.ne.0.)bioal=1.-xkd/xks
                            if (xkd.le.0.) bioal=1.
                            if (bioal.lt.1.e-6)bioal=0.
                            fact=csmos+poros*satur/bulkw+satur*(bioal-poros)/xks*          &
                                (satur+csmos*pwatr/poros)
                        endif
                    else if(fieldid(1:2)=='UW'.and.UPW=='U'.and.material(1:6)=='NSSoil') then
                        density=props(matno)%mechanical%fluid%density
                        !    order_int=elkn(index)%el_field(2)%order_intrules(2)
                        !write(7,*)'ie=',ielem,'ig=',igaus,'order_int=',order_int
                        poros=element(ielem)%egaus(order_int)%poros(igaus)
                        satur=element(ielem)%egaus(order_int)%satur(igaus)
                        factw=density*poros*satur
                    elseif(nrfields==1.and.UPW=='W'.and.material(1:6)=='NSSoil') then !2006NS
                        csmos=element(ielem)%egaus(order_int)%csmos(igaus)
                        fact=csmos
                    endif
                    if (UPW=='U')fact=facts+factw
                    ! get djacb and cartd in the element level
                    djacb=element(ielem)%egaus(order_intx)%djacb(igaus)
                    if (type_mass==0) then
                        do in=1,nnode
                            diagm(in)=diagm(in)+djacb*shape(in)*shape(in)
                        end do
                        dvolu=dvolu+djacb
                    else
                        !                      do in=1,nnode
                        !                         idofn=(in-1)*ndofn
                        !                         do jn=1,nnode
                        !                            jdofn=(jn-1)*ndofn
                        !                            cmatx(idofn+1:idofn+ndofn,jdofn+1:jdofn+ndofn)=                   &
                        !                            cmatx(idofn+1:idofn+ndofn,jdofn+1:jdofn+ndofn)                    &
                        !                            +djacb*fact*shape(in)*shape(jn)
                        !                         end do
                        !                      end do
                        do idimn=1,ndofn
                            do in=1,nnode
                                idofn=(in-1)*ndofn+idimn
                                do jn=1,nnode
                                    jdofn=(jn-1)*ndofn+idimn
                                    cmatx(idofn,jdofn)=cmatx(idofn,jdofn)+djacb*fact*shape(in)*shape(jn)
                                enddo
                            enddo
                        enddo
                    endif

                    if  (fieldid(1:2)=='UW'.and.UPW=='W'.AND.special(1:1)=='B' ) then
                        gmatx = element(ielem)%gmatx(:,:,igaus)
                        estifh = element(ielem)%estifh(:,:)
                        call mcmatrx_sr(cmatx,gmatx,shape,qmatxa,estifh,djacb,igaus,ngaus)
                    endif


                end do     !!igaus
                if  (fieldid(1:2)=='UW'.and.UPW=='W'.AND.special(1:1)=='B' ) then
                    element(ielem)%qmatxa = qmatxa
                endif


                if (type_mass==0)then
                    tdiagm=sum(diagm)
                    tdiagm=fact*dvolu/tdiagm
                    do in=1,nnode
                        idofn=(in-1)*ndofn
                        cmatx(idofn+1:idofn+ndofn,1)=tdiagm*diagm(in)
                    end do
                endif
                ! assembling to element stiff matrix
                element(ielem)%field(ifield)%khandmc(2)%fstif=cmatx*coef*thick

                !if(ielem==1) then
                !write(chkunit,*)'UPW=',UPW,'ielem=',ielem,'fact=',fact,'fstif='
                !write(chkunit,*)element(ielem)%field(ifield)%khandmc(2)%fstif
                !endif
                !stop
                nullify(lnods)
            end do       !!ielgroup
            deallocate(shape)
            if (allocated(cmatx))deallocate(cmatx)
            if (allocated(diagm))deallocate(diagm)
            if (allocated(value))deallocate(value)

            if  (fieldid(1:2)=='UW'.and.UPW=='W'.AND.special(1:1)=='B' ) &
                deallocate(gmatx,estifh,qmatxa)

        else !!2000
            if (index==20.or.index==21)call beam_mass(igroup,matno,facts,type_mass)
            if (index==22)call plate_mass(igroup,matno,facts,type_mass)
        endif !! 2000

10      continue
        !end if        !! for co-displacement group
    end do         !!  for group

199 format(10e20.8)
    END SUBROUTINE MCMATRX

    !!2000
    subroutine beam_mass(igroup,matno,density,type_mass)

    real   (irk) Iy,Iz,twist,aera,dun
    integer(ink) ielem,nevab,ielgroup,ii,matno,type_mass,igroup
    real   (irk),pointer::elcod(:,:),rotation(:,:)
    real   (irk),allocatable::estifm(:,:),estif(:,:),trot(:,:)
    real   (irk) density,dl,tmass
    ! get the parameters
    Iy   =props(matno)%geometry%iy
    Iz   =props(matno)%geometry%iz
    twist=props(matno)%geometry%j
    aera =props(matno)%geometry%aera
    dun=aera*density

    nevab=6*(ndimn-1)
    allocate(estifm(nevab,nevab),trot(nevab,nevab),estif(nevab,nevab))
    ! obtain the mass matrix for each element
    tmass=0.
    DO ielgroup = 1,group(igroup)%nelgroup
        ielem = group(igroup)%list(ielgroup)
        elcod=>element(ielem)%field(1)%elcod_f
        rotation=>element(ielem)%rotation
        dl=sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))
        tmass=tmass+dun*dl
        trot=0.; estifm=0.0
        if (ndimn==2) then
            trot(1:ndimn,1:ndimn)=rotation
            trot(3,3)=1.
            trot(4:5,4:5)=rotation
            trot(6,6)=1.
        else if(ndimn==3) then
            trot(1:3,1:3)=rotation; trot(4:6,4:6)=rotation
            trot(7:9,7:9)=rotation; trot(10:12,10:12)=rotation
        endif
        if (type_mass==0) then
            if (ndimn==2) then
                estifm(1,1)=.5*dun*dl
                estifm(2,1)=.5*dun*dl
                estifm(4,1)=.5*dun*dl
                estifm(5,1)=.5*dun*dl
            else if(ndimn==3)then
                estifm(1,1)=.5*dun*dl
                estifm(2,1)=.5*dun*dl
                estifm(3,1)=.5*dun*dl
                estifm(7,1)=.5*dun*dl
                estifm(8,1)=.5*dun*dl
                estifm(9,1)=.5*dun*dl
            endif
        elseif(type_mass==1) then
            if (ndimn==2) then
                estifm(1,1)= dun*dl/3.
                estifm(2,2)= dun*dl*156./420.
                estifm(3,2)=-dun*dl*dl*22./420.
                estifm(3,3)= dun*dl*dl*dl*4./420.
                estifm(4,1)= dun*dl/6.
                estifm(4,4)= dun*dl/3.
                estifm(5,2)= dun*dl*54./420.
                estifm(5,3)=-dun*dl*dl*13./420.
                estifm(5,5)= dun*dl*156./420.
                estifm(6,2)= dun*dl*dl*13./420.
                estifm(6,3)=-dun*dl*dl*dl*3./420.
                estifm(6,5)= dun*dl*dl*22./420.
                estifm(6,6)= dun*dl*dl*dl*4./420.
            else if(ndimn==3) then
                estifm(1,1)= 1./3.
                estifm(2,2)= 13./35.+6*Iz/(5.*aera*dl**2)
                estifm(3,3)= 13./35.+6*Iy/(5.*aera*dl**2)
                estifm(4,4)= twist/(3.*aera)
                estifm(5,3)=-11.*dl/210.-Iy/(10.*aera*dl)
                estifm(5,5)= dl**2/105.+2.*Iy/(15.*aera)
                estifm(6,2)= 11.*dl/210.+Iz/(10.*aera*dl)
                estifm(6,6)= dl**2/105+2.*Iz/(15.*aera)

                estifm(7,1)= 1./6.
                estifm(7,7)= 1./3.

                estifm(8,2)= 9./70.-6*Iz/(5.*aera*dl**2)
                estifm(8,6)= 13.*dl/420.-Iz/(10.*aera*dl)
                estifm(8,8)= 13./35.+6*Iz/(5.*aera*dl**2)

                estifm(9,3)= 9./70.-6*Iy/(5.*aera*dl**2)
                estifm(9,5)=-13.*dl/420.+Iy/(10.*aera*dl)
                estifm(9,9)= 13./35.+6*Iy/(5.*aera*dl**2)

                estifm(10, 4)= twist/(6.*aera)
                estifm(10,10)= twist/(3.*aera)

                estifm(11,3)= 13.*dl/420.-Iy/(10.*aera*dl)
                estifm(11,5)= -dl**2/140.-Iy/(30.*aera)
                estifm(11,9)= 11.*dl/210.+Iy/(10.*aera*dl)
                estifm(11,11)= dl**2/105.+2.*Iy/(15.*aera)

                estifm(12,2)=-13.*dl/420.+Iz/(10.*aera*dl)
                estifm(12,6)= -dl**2/140.-Iz/(30.*aera)
                estifm(12,8)=-11.*dl/210.-Iz/(10.*aera*dl)
                estifm(12,12)= dl**2/105.+2.*Iz/(15.*aera)
                estifm=estifm*dun*dl
            endif

            do ii=1,6*(ndimn-1)
                estifm(ii,ii+1:6*(ndimn-1))=estifm(ii+1:6*(ndimn-1),ii)
            end do
        endif

        if (type_mass==0) then
            do ii=1,6*(ndimn-1)
                estif(ii,:)=estifm(ii,1)*trot(ii,:)
            end do
        else
            estif=estifm.x.trot
        endif
        estifm=estif
        estif=transpose(trot).x.estifm
        element(ielem)%field(1)%khandmc(2)%fstif=estif
        nullify(elcod,rotation)
    end do
    write(chkunit,*)'igroup=',igroup,'tmass=',tmass

10  format(6e15.3)
    deallocate(estifm,trot,estif)
    end subroutine beam_mass
    !****
    !!2000
    subroutine plate_mass(igroup,matno,density,type_mass)

    real   (irk) thick,density,dun,dvolu,djacb,tdiagm
    integer(ink) ielem,nevab,ii,matno,type_mass,igroup,igaus,  &
        in,inode,nnode,ndofn,idofn,jdofn,index,order_intx,ngaus, &
        ielgroup,jn,id,jd,idofn0,jdofn0,icomp
    real   (irk),pointer::rotation(:,:)
    real   (irk),allocatable::estifm(:,:),estif(:,:),trot(:,:),cmatx(:,:), &
        diagm(:),shape(:),shapw(:),mmi(:,:)
    ! get the parameters
    thick=props(matno)%mechanical%solid%thickness
    dun=thick*density

    nevab=12
    allocate(estifm(nevab,nevab),trot(nevab,nevab),estif(nevab,nevab))
    index    = group(igroup)%index
    nnode = elkn(index)%el_field(1)%nnode_f
    ndofn=  group(igroup)%dof(1)%nfdof
    nevab=    nnode*ndofn
    order_intx=elkn(index)%el_field(1)%order_intrules(2)
    ngaus = elkn(index)%ggaus(order_intx)%ngaus
    ! allocate the arrays which will be used
    allocate (shape(nnode))
    if (type_mass==0)allocate (diagm(nevab),cmatx(nevab,1))
    if (type_mass==1)allocate (cmatx(nevab,nevab))
    ! obtain the mass matrix for each element
    DO ielgroup = 1,group(igroup)%nelgroup
        ielem = group(igroup)%list(ielgroup)
        rotation=>element(ielem)%rotation
        trot=0.; estifm=0.0;cmatx=0.0


        do inode=1,nnode
            idofn=(inode-1)*ndofn
            trot(idofn+1:idofn+3,idofn+1:idofn+3)=rotation
            !trot(idofn+4:idofn+6,idofn+4:idofn+6)=rotation
        end do
        if (type_mass==0)then
            diagm=0.0
            dvolu=0.0
        endif
        do igaus=1,ngaus

            if (type_mass==1)then
                allocate(shapw(12))
                shapw=0.
            endif

            djacb=element(ielem)%egaus(order_intx)%djacb(igaus)
            !icomp=5
            !if (type_mass==0)icomp=3
            icomp=3
            do ii=1,icomp
                !if (ii<=2)then
                shape = elkn(index)%ggaus(order_intx)%shape(:,igaus)
                !else
                !shape = element(ielem)%egaus(order_intx)%shapwxy(ii-2,:,igaus)
                !endif
                ! get djacb and cartd in the element level
                if (type_mass==0) then
                    do in=1,nnode
                        idofn=(in-1)*ndofn
                        diagm(idofn+ii)=diagm(idofn+ii)+djacb*shape(in)*shape(in)
                    end do
                    if (ii==1)dvolu=dvolu+djacb
                else
                    if (ii.le.2) then
                        do in=1,nnode
                            idofn=(in-1)*ndofn
                            do jn=1,nnode
                                jdofn=(jn-1)*ndofn
                                cmatx(idofn+ii,jdofn+ii)=                   &
                                    cmatx(idofn+ii,jdofn+ii)+djacb*dun*shape(in)*shape(jn)
                            end do
                        end do
                    else
                        do in=1,nnode
                            idofn=(in-1)*3
                            shapw(idofn+ii-2)=shape(in)
                        end do
                    endif
                endif
            end do !ii

            if (type_mass==1) then
                allocate(mmi(12,12))
                mmi=shapw.o.shapw
                do in=1,nnode
                    do id=1,3
                        idofn0=(in-1)*3+id
                        idofn=(in-1)*ndofn+id+2
                        do jn=1,nnode
                            do jd=1,3
                                jdofn0=(jn-1)*3+jd
                                jdofn=(jn-1)*ndofn+jd+2
                                cmatx(idofn,jdofn)=                   &
                                    cmatx(idofn,jdofn)+djacb*dun*mmi(idofn0,jdofn0)
                            end do
                        end do
                    end do
                end do
                deallocate(shapw,mmi)
            endif

        end do     !!igaus


        if (type_mass==0)then
            do ii=1,3
                tdiagm=0.
                do inode=1,nnode
                    idofn=(inode-1)*ndofn+ii
                    tdiagm=tdiagm+diagm(idofn)
                end do
                tdiagm=dun*dvolu/tdiagm
                do in=1,nnode
                    idofn=(in-1)*ndofn+ii
                    cmatx(idofn,1)=tdiagm*diagm(idofn)
                end do
            end do
        endif
        ! assembling to element stiff matrix
        if (type_mass==0) then
            do ii=1,nevab
                estif(ii,:)=cmatx(ii,1)*trot(ii,:)
            end do
        else
            estif=cmatx.x.trot
        endif
        estifm=estif
        estif=transpose(trot).x.estifm
        !   write(7,*)'ielem=',ielem,'massx-z'
        !   do ii=3,24,6
        !   write(7,10)estif(ii,3:24:6)
        !   end do
        element(ielem)%field(1)%khandmc(2)%fstif=estif
    end do       !!ielgroup
    deallocate(shape)
    if (allocated(cmatx))deallocate(cmatx)
    if (allocated(diagm))deallocate(diagm)

    deallocate(estifm,trot,estif)
10  format(2x,6e15.3)
    end subroutine plate_mass
    !****


    !!!!!!!!!!

    SUBROUTINE MCMATRX_SR(cmatx,gmatx,shape,qmatxa,estifhi,djacb,igaus,ngaus)

    integer (ink) nstre,np,igaus,ngaus,evabsr
    real (irk) coef
    real (irk) djacb,cmatx(:,:),gmatx(:,:),shape(:),qmatxa(:,:),estifhi(:,:)
    real (irk), allocatable :: mnp(:,:),estifhiq(:,:),m(:)

    nstre= size(gmatx,dim=1)
    evabsr=size(gmatx,dim=1)
    np   = size(cmatx,dim=2)

    allocate(mnp(nstre,np),m(nstre))

    if  (ndimn==2) then
        m=(/1.0,1.0,0.0,1.0/)
    else
        m=(/1.0,1.0,1.0,0.0,0.0,0.0/)
    endif

    mnp  = m.o.shape

    if  (igaus==1) qmatxa=0.0

    qmatxa = qmatxa + MATMUL(transpose(gmatx),mnp)*djacb

    deallocate(mnp,m)

    if  (igaus < ngaus) return

    coef=1.
    if (type_problem/='Q') then
        coef=theta1/beeta1
        if (type_problem=='F')coef=theta1*beeta1/beeta2
    endif
    evabsr = size(gmatx,dim=2)
    allocate(estifhiq(evabsr,np))
    call householder(estifhi,qmatxa,estifhiq)
    cmatx = cmatx +coef* (MATMUL(transpose(qmatxa),estifhiq))

    deallocate(estifhiq)

    END SUBROUTINE MCMATRX_SR

    !!Nstoks
    SUBROUTINE fmass_assemble !! for mass and compressibility matrix
    character(10)name
    integer(ink) igroup,  matno, ielgroup, ielem
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::ymass(:,:)

    fmass=0.
    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            matno = group(igroup)%matno
            name=props(matno)%name
            if (name=='NSTOKS')then
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    ymass=>element(ielem)%field(1)%khandmc(2)%fstif
                    ldofs=>element(ielem)%field(1)%ldofs_f
                    fmass(ldofs)=fmass(ldofs)+ymass(:,1)
                end do
                nullify(ldofs,ymass)
            endif       !! for nstoks group
        end if        !! for appearing group
    end do         !!  for group

    END SUBROUTINE fmass_assemble
    !!

    SUBROUTINE upwcouple
    character(10)fieldid,class,material,SPtype,special,name
    integer(ink) igroup, nrfields, ifield1, ifield2,  index,   &
        nnode1, nnode2,   nevab1,  ncouple,  icouple, &
        intrule1, intrule2,  in,  jn,      ievab,     &
        ngaus,  ielgroup, ielem,  igaus, ifield ,kn,  &
        matno, order_int, order_intx,nnode,aevab,nstre
    real   (irk)  djacb,ppp,fact,satur,bioal,xkd,xks,gpcodx
    real   (irk),allocatable::qmatx(:,:), cartd(:,:), shape(:), value(:), &
        shapeu(:),qstab(:,:)
    character(1),allocatable::field(:)
    integer(ink),pointer::lnods(:)
    real   (irk),allocatable:: estifh(:,:), qmatxa(:,:),estift(:,:)

    DO igroup =1,ngroup

        class = group(igroup)%class
        matno = group(igroup)%matno
        if (appear(igroup)>0.and.class=='CO')then
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            index = group(igroup)%index
            SPtype= group(igroup)%SPtype
            special= group(igroup)%special
            ncouple=elkn(index)%ncouple
            nnode = elkn(index)%el_field(1)%nnode_f
            nstre=  group(igroup)%nstre
            allocate(field(nrfields))
            do ifield=1,nrfields
                field(ifield)=fieldid(ifield:ifield)
            end do



            do icouple=1,ncouple      !!new

                if (fieldid(1:2)=='UW') then
                    name=props(matno)%name
                    material=props(matno)%mechanical%solid%material

                    if (name=='NSSoil') then
                        order_int=elkn(index)%couple(icouple)%intrule_couple(1)
                        order_intx=elkn(index)%el_field(1)%order_intrules(1)
                        if (order_int/=order_intx) then
                            allocate(value(npoin))
                            call recoverx(igroup,'EPRES',value)
                        endif
                    endif
                endif
                ifield1=elkn(index)%couple(icouple)%field_couple(1)
                ifield2=elkn(index)%couple(icouple)%field_couple(2)
                if (field(ifield1)/='U'.or.                               &
                    (field(ifield2)/='P'.and.field(ifield2)/='W')) exit
                ! get information from the group level
                nnode1 = elkn(index)%el_field(ifield1)%nnode_f
                nnode2 = elkn(index)%el_field(ifield2)%nnode_f
                nevab1 = nnode1*group(igroup)%dof(ifield1)%nfdof
                intrule1=elkn(index)%couple(icouple)%intrule_couple(1)
                intrule2=elkn(index)%couple(icouple)%intrule_couple(2)
                ngaus = elkn(index)%ggaus(intrule1)%ngaus
                ! allocate the arrays which will be used
                allocate (qmatx(nevab1,nnode2),cartd(ndimn,nnode1), shape(nnode2))
                if (stabpw==1)allocate (qstab(nevab1,nnode2))

                if (sptype=='AX') allocate(shapeu(nnode1))

                !     Simo & Rifai element

                if (special(1:1)=='B'.and.fieldid(1:2)=='UW') then

                    if (ndimn==2) then
                        if (special(2:2)=='A') aevab=2
                        if (special(2:2)=='B') aevab=4
                        if (special(2:2)=='C') aevab=7
                        if (special(2:2)=='D') aevab=11
                    else if(ndimn==3) then
                        if (special(2:2)=='A') aevab=3
                        if (special(2:2)=='B') aevab=9
                        if (special(2:2)=='C') aevab=24
                        if (special(2:2)=='D') aevab=30
                    endif

                    allocate(estifh(aevab,aevab),qmatxa(aevab,nnode2),estift(aevab,nevab1))

                endif
                ! end for Simo & Rifai element


                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods=> element(ielem)%field(ifield2)%lnods_f
                    qmatx=0.0_irk
                    if (stabpw==1)qstab=0.

                    do igaus=1,ngaus

                        shape = elkn(index)%ggaus(intrule2)%shape(:,igaus)
                        ! get djacb and cartd in the element level
                        djacb=element(ielem)%egaus(intrule1)%djacb(igaus)
                        cartd=element(ielem)%egaus(intrule1)%cartd(:,:,igaus)
                        if  (sptype=='AX') then
                            shapeu= elkn(index)%ggaus(intrule1)%shape(:,igaus)
                            gpcodx=element(ielem)%egaus(intrule1)%gpcod(1,igaus)
                        endif
                        fact=1.0
                        if (fieldid(1:2)=='UW') then
                            if (name=='NSSoil') then
                                order_int=elkn(index)%el_field(1)%order_intrules(1)
                                satur=element(ielem)%egaus(order_int)%satur(igaus)
                                xks=props(matno)%mechanical%fluid%bulks
                                xkd=props(matno)%mechanical%fluid%bulkd

                                if (material=='SoilPZ') then
                                    if (.not.allocated(value)) then
                                        ppp=element(ielem)%egaus(order_int)%vdval(5,igaus)
                                    else
                                        ppp=shape.d.value(lnods)
                                    endif
                                    xkd=ppp*props(matno)%mechanical%solid%SoilPZ%d(9)
                                endif

                                bioal=1.
                                if (xks.ne.0.)bioal=1.-xkd/xks
                                if (xkd.le.0.) bioal=1.
                                if (bioal.lt.1.e-6)bioal=0.
                                fact=bioal*satur
                            endif
                        endif

                        do in=1,nnode1
                            do jn=1,ndimn
                                ievab=(in-1)*ndimn+jn
                                do kn=1,nnode2
                                    qmatx(ievab,kn)=qmatx(ievab,kn)+djacb*cartd(jn,in)*shape(kn)*fact
                                    if (stabpw==1) &
                                        qstab(ievab,kn)=qstab(ievab,kn)-djacb*cartd(jn,kn)*shape(in)*fact

                                    if (sptype=='AX'.and.jn==1)           &
                                        qmatx(ievab,kn)=qmatx(ievab,kn)+djacb*shapeu(in)/gpcodx*shape(kn)*fact
                                    if (sptype=='AX'.and.jn==1)           &
                                        qstab(ievab,kn)=qstab(ievab,kn)-djacb*shapeu(kn)/gpcodx*shape(in)*fact
                                    !! stablize
                                end do
                            end do
                        end do

                    end do     !!igaus

                    if (special(1:1)=='B'.and.fieldid(1:2)=='UW') then
                        qmatxa = element(ielem)%qmatxa
                        estifh = element(ielem)%estifh
                        estift = element(ielem)%estift
                        call upwcouple_sr(qmatx,qmatxa,estifh,estift)
                    endif

                    ! assembling to element stiff matrix
                    element(ielem)%cstif(icouple)%qmatx=-qmatx
                    if (stabpw==1)element(ielem)%cstif(icouple)%qstab=qstab


                    nullify(lnods)
                end do       !!ielgroup
                deallocate(qmatx,cartd,shape)
                if (stabpw==1)deallocate(qstab)
                if (sptype=='AX')    deallocate(shapeu)
                if (allocated(value))deallocate(value)
            end do   !! for icouple
            deallocate(field)
            if (special(1:1)=='B'.and.fieldid(1:2)=='UW')  &
                deallocate(estifh,estift,qmatxa)
        end if        !! for co-displacement group
    end do         !!  for group

199 format(10e20.8)

    END SUBROUTINE upwcouple

    SUBROUTINE upwcouple_sr(qmatx,qmatxa,estifhi,estift)

    integer (ink) na,nb
    real (irk)  qmatx(:,:),qmatxa(:,:),estifhi(:,:),estift(:,:)
    real (irk), allocatable :: estifhiq(:,:)

    na=size(estifhi,dim=1)
    nb=size(qmatxa ,dim=2)

    allocate(estifhiq(na,nb))

    call householder(estifhi,qmatxa,estifhiq)
    !   estifhiq = estifhi.x.qmatxa

    qmatx = qmatx - MATMUL(transpose(estift),estifhiq)

    deallocate(estifhiq)

    END SUBROUTINE upwcouple_sr

    !! stablize
    subroutine stabpatch
    character(10)fieldid
    integer(ink) igroup,  index, nnode, nodp, nep, ie, ielem,  &
        i, j, k, inode, ipdofn, jnode, jdofn, jpdofn, &
        ipa,ii
    integer(ink),allocatable::ijpn(:)
    integer(ink),pointer::lnods(:),patch_nod(:),patch_ne(:)
    real   (irk) fact,coef
    real   (irk),allocatable::stabx(:,:),qmid(:,:),ymid(:),hmid(:,:)
    real   (irk),pointer::yemas(:,:),hstar(:,:),qmatr(:,:)

    if (type_problem=='S') fact=theta1*ditime**2
    if (type_problem=='Q') fact=ditime**2
    if (type_problem=='F') fact=beeta1*theta1*ditime**2
    coef=1.0
    if (type_problem/='Q') then
        coef=-theta1*ditime     !(sign - --->+)
        if (type_problem=='F')coef=-theta1/beeta1     !(sign - --->+)
    endif
    DO igroup =1,ngroup

        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.   &
            (fieldid(1:2)=='UP'.or.fieldid(1:2)=='UW')) then
            index = group(igroup)%index
            nnode = elkn(index)%el_field(2)%nnode_f

            allocate(ijpn(npoin))
            do ipa=1,group(igroup)%np_unode
                nodp=group(igroup)%unode(ipa)%np_unode
                if (nodp==0) goto 1
                nep =group(igroup)%unode(ipa)%ne_unode
                patch_nod=>group(igroup)%unode(ipa)%patch_nod
                patch_ne =>group(igroup)%unode(ipa)%list

                ijpn=0
                do i=1,nodp
                    ijpn(patch_nod(i))=i
                end do
                allocate(hmid(nodp,nodp),qmid(nodp,nodp*ndimn),ymid(nodp*ndimn))
                qmid=0.0
                hmid=0.0
                ymid=0.0

                allocate(stabx(nodp,nodp))
                stabx=0.0

                do ie=1,nep
                    ielem=patch_ne(ie)
                    lnods=>element(ielem)%field(2)%lnods_f
                    yemas=>element(ielem)%field(1)%khandmc(2)%fstif
                    hstar=>element(ielem)%field(2)%khandmc(1)%hstar
                    qmatr=>element(ielem)%cstif(1)%qstab


                    do i=1,nnode
                        inode=lnods(i)
                        do ii=1,ndimn
                            ipdofn=(ijpn(inode)-1)*ndimn+ii
                            ymid(ipdofn)=ymid(ipdofn)+yemas((i-1)*ndimn+ii,1)
                        end do

                        do j=1,nnode
                            jnode=lnods(j)
                            hmid(ijpn(inode),ijpn(jnode))=hmid(ijpn(inode),ijpn(jnode))+ &
                                hstar(i,j)
                            do k=1,ndimn
                                jdofn=(j-1)*ndimn+k
                                jpdofn=(ijpn(jnode)-1)*ndimn+k
                                qmid(ijpn(inode),jpdofn)=qmid(ijpn(inode),jpdofn)+        &
                                    qmatr(jdofn,i)
                            end do  !k
                        end do    !j

                    end do    !i
                    nullify(lnods,yemas,hstar,qmatr)
                end do     !ie

                do i=1,nodp                !!!!
                    do j=1,nodp
                        do k=1,nodp*ndimn
                            stabx(i,j)=stabx(i,j)+qmid(i,k)*qmid(j,k)/ymid(k)
                        end do
                    end do
                end do                     !!!!

                stabx=hmid-stabx
                group(igroup)%unode(ipa)%patch_sta=stabx*fact*coef

                deallocate(hmid,qmid,ymid,stabx)
                nullify(patch_nod,patch_ne)
1               continue
            end do      !!!finish npatch --->loop ipa

            deallocate(ijpn)
        endif
    end do   !! igroup

    end subroutine stabpatch

    !! end of stablize

    subroutine concentrated_mass_matrix
    integer(ink)ipoin,idimn,itotv,ieq,colum,imcon

    do imcon=1,nmcon
        ipoin=lmcon(imcon)
        do idimn=1,ndimn
            itotv=nodfn(idimn,ipoin)
            ieq  =totveq(itotv)
            if(ieq/=0) then
                colum=iseq(ieq)
                global_stiff1(colum)=global_stiff1(colum)+ rmcon(idimn,imcon)
                if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+rmcon(idimn,imcon)
            endif
        end do
    end do
    end subroutine concentrated_mass_matrix


    SUBROUTINE ESTIF_ASSEMBLE
    character(10)fieldid,special,name
    integer(ink) igroup, nrfields, ifield,  index, order_time,     &
        nnode_f, nevab_f,  bnevab,  ic,            &
        ielgroup, ielem,   ievab,  ikh, anevab, ilayer, matno,ie0

    real   (irk)  coef
    real   (irk), allocatable::fstif(:,:)
    real   (irk), pointer::fstif0(:,:)
    integer(ink), pointer::ldofs(:)
    logical :: is_pardiso, use_duncanchang
    integer, parameter :: mesh_main=0, mesh_first=1, mesh_second=2

    integer(ink)  nstre !20231215YL
    real   (irk)  alfa,beta,lamda !20231215YL

    if (outintr/=0.and.type_solver=='JPCG')return
    is_pardiso = (type_solver=='PARDISO')
    DO igroup =1,ngroup
        if  (appear(igroup)>0)  then
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            special=group(igroup)%special
            matno  =group(igroup)%matno
            name   =props(matno)%name
            index  =group(igroup)%index
            alfa=group(igroup)%alfa !20231215YL
            beta=group(igroup)%beta !20231215YL
            nstre=  group(igroup)%nstre !20231215YL

            ilayer =group(igroup)%ilayer
            if (nlayer==2.and.ilayer==1.and.kresl_layer1==0) goto 1
            if (nlayer==2.and.ilayer==2.and.kresl_layer2==0) goto 1
            bnevab=0
            do ifield=1,nrfields
                nnode_f = elkn(index)%el_field(ifield)%nnode_f
                nevab_f = nnode_f*group(igroup)%dof(ifield)%nfdof
                if (.not. is_pardiso) allocate(fstif(nevab_f,nevab_f))
                anevab  =bnevab+nevab_f
                ! loop for k(h) and m(c)
                ikh_loop: do ikh=1,2
                    if (type_problem/='F'.and.fieldid(ifield:ifield)=='U'.and.ikh==2)    goto 10  !20221013
                    if (name=='NSTOKS'.and.fieldid(ifield:ifield)=='W'.and.ikh==1)       goto 10  !!nstoks
                    if (type_problem=='Q'.and.fieldid(ifield:ifield)=='P'.and.ikh==1)    goto 10
                    !order_time=elkn(index)%el_field(ifield)%order_time(ikh)
                    order_time=group(igroup)%order_time(ikh,ifield)
                    coef=1.
                    if (type_problem=='F'.and.fieldid(ifield:ifield)=='U')coef=1.0+group(igroup)%alfa*beeta1*ditime                         !-------------------------------!
                    if  (type_problem/='Q') then
                        if  (fieldid(ifield:ifield)=='U') then
                            if  (name/='NSTOKS')then
                                if (order_time==0.and.type_problem/='F')coef=theta1*ditime
                                if (order_time==0.and.type_problem=='F')coef=beeta2*ditime**2+group(igroup)%beta*beeta1*ditime
                                if (order_time==1.and.type_problem=='F')coef=beeta1*ditime
                            else
                                if (order_time==0)coef=ditime  !!nstoks
                            endif
                        elseif(fieldid(ifield:ifield)=='W') then
                            if (order_time==0)coef=theta1*ditime
                            if (order_time==2)coef=1./ditime                            !
                            if (order_time==0.and.ifsnedge/=0)coef=beeta2*ditime**2 !ifs2006 zhao, 06/03/29
                            if (order_time==2.and.ifsnedge/=0)coef=1.0 !ifs2006 zhao, 06/03/29
                        elseif(fieldid(ifield:ifield)=='T') then
                            if (order_time==0)coef=theta1*ditime
                        endif
                    endif
                    use_duncanchang = (fieldid(ifield:ifield)=='U'.and.props(matno)%mechanical%solid%material=='DUNCANCHANG'.and.type_problem=='F')

                    if (is_pardiso) then
                        call assemble_pardiso_mesh(group(igroup)%nelgroup,group(igroup)%list,mesh_main, &
                            bnevab,anevab,nevab_f,coef,use_duncanchang,ifield,ikh,nstre)
                        if (rmesh>0.and.nelem1>0) then
                            call assemble_pardiso_mesh(group1(igroup)%nelgroup,group1(igroup)%list,mesh_first, &
                                bnevab,anevab,nevab_f,coef,use_duncanchang,ifield,ikh,nstre)
                        endif
                        if (rmesh>1.and.nelem2>0) then
                            call assemble_pardiso_mesh(group2(igroup)%nelgroup,group2(igroup)%list,mesh_second, &
                                bnevab,anevab,nevab_f,coef,use_duncanchang,ifield,ikh,nstre)
                        endif
                        cycle ikh_loop
                    endif
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if (ice0(ielem)==1) goto 100
                        !20231215YL !20240305
                        if(fieldid(ifield:ifield)=='U')then
                            if(props(matno)%mechanical%solid%material=='DUNCANCHANG'.and.type_problem=='F')then  !20231008
                                lamda=sum(element(ielem)%field(1)%gpvar(nstre+1,:))/size(element(ielem)%field(1)%gpvar,dim=2)
                                if(ikh==1)then
                                    beta=lamda/base_freq   !907
                                    coef=beeta2*ditime**2+beta*beeta1*ditime          !
                                elseif(ikh==2)then
                                    alfa=lamda*base_freq
                                    coef=1.0+alfa*beeta1*ditime
                                endif
                            endif
                        endif  !20231215YL

                        if  (associated(element(ielem)%field(ifield)%khandmc(ikh)%fstif)) then
                            if (type_solver/='JPCG')ldofs=>element(ielem)%ldofs
                            fstif0=>element(ielem)%field(ifield)%khandmc(ikh)%fstif
                            ic=size(fstif0,dim=2)
                            if  (ikh==2.and.ic==1)then
                                fstif=0.0
                                do ievab=1,nevab_f
                                    fstif(ievab,ievab)=fstif0(ievab,1)
                                end do
                            else
                                fstif=fstif0
                            end if

                            if(iblks==1.and.ielgroup==1.and.istep==inc_step.and.iiter==1)then
                                write(chkunit,5000)'igroup=',igroup,' ifield=',ifield,' ikh=',ikh,' ielem=',ielem,' order_time=',order_time,'  coef=',coef
5000                            format(a,i5,2(a,i1),a,i6,a,i1,a,f8.5)
                                do ie0=1,size(fstif,dim=1)
                                    write(chkunit,'(30e16.5)')fstif(ie0,:)
                                end do
                            end if

                            fstif=coef*fstif


                            if  (type_solver=='JPCG') then
                                element(ielem)%estif(bnevab+1:anevab,bnevab+1:anevab)=             &
                                    element(ielem)%estif(bnevab+1:anevab,bnevab+1:anevab)+    fstif
                            else if(type_solver=='PROFILE') then
                                call global_stif_profile(bnevab,anevab,bnevab,anevab,ldofs,fstif,ilayer)
                            else if(type_solver=='PBCG') then
                                call global_stif_pbcg(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                            else if(type_solver=='SSORPBCG') then !ssorpbcg
                                call global_stif_ssorpbcg(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                            else if(type_solver=='PARDISO') then !PARDISO 2008-11-05
                                call global_stif_pardiso(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                            endif
                            nullify(fstif0)
                            if (type_solver/='JPCG')nullify(ldofs)
                        endif
100                     continue
                    end do       !!ielgroup
                    !!!!!!!!!!!!!!!!!!!!!!!!!!
                    if (rmesh>0.and.nelem1>0)then
                        DO ielgroup = 1,group1(igroup)%nelgroup
                            ielem = group1(igroup)%list(ielgroup)
                            if (jce1(ielem)==1) goto 200
                            if (associated(element1(ielem)%field(ifield)%khandmc(ikh)%fstif)) then
                                if (type_solver/='JPCG')ldofs=>element1(ielem)%ldofs
                                fstif0=>element1(ielem)%field(ifield)%khandmc(ikh)%fstif
                                ic=size(fstif0,dim=2)
                                if (ikh==2.and.ic==1)then
                                    fstif=0.0
                                    do ievab=1,nevab_f
                                        fstif(ievab,ievab)=fstif0(ievab,1)
                                    end do
                                else
                                    fstif=fstif0
                                end if
                                fstif=coef*fstif

                                if (type_solver=='JPCG') then
                                    element1(ielem)%estif(bnevab+1:anevab,bnevab+1:anevab)=             &
                                        element1(ielem)%estif(bnevab+1:anevab,bnevab+1:anevab)+    fstif
                                else if(type_solver=='PROFILE') then
                                    call global_stif_profile(bnevab,anevab,bnevab,anevab,ldofs,fstif,ilayer)
                                else if(type_solver=='PBCG') then
                                    call global_stif_pbcg(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                                else if(type_solver=='SSORPBCG') then !ssorpbcg
                                    call global_stif_ssorpbcg(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                                else if(type_solver=='PARDISO') then !PARDISO 2008-11-05
                                    call global_stif_pardiso(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                                endif
                                nullify(fstif0)
                                if (type_solver/='JPCG')nullify(ldofs)
                            endif
200                         continue
                        end do       !!ielgroup
                    endif
                    !!!!!!!!!!!!!!!!!!!!!!!!!!!
                    if (rmesh>1.and.nelem2>0)then
                        DO ielgroup = 1,group2(igroup)%nelgroup
                            ielem = group2(igroup)%list(ielgroup)
                            if (associated(element2(ielem)%field(ifield)%khandmc(ikh)%fstif)) then
                                if (type_solver/='JPCG')ldofs=>element2(ielem)%ldofs
                                fstif0=>element2(ielem)%field(ifield)%khandmc(ikh)%fstif
                                ic=size(fstif0,dim=2)
                                if (ikh==2.and.ic==1)then
                                    fstif=0.0
                                    do ievab=1,nevab_f
                                        fstif(ievab,ievab)=fstif0(ievab,1)
                                    end do
                                else
                                    fstif=fstif0
                                end if
                                fstif=coef*fstif


                                if (type_solver=='JPCG') then
                                    element2(ielem)%estif(bnevab+1:anevab,bnevab+1:anevab)=             &
                                        element2(ielem)%estif(bnevab+1:anevab,bnevab+1:anevab)+    fstif
                                else if(type_solver=='PROFILE') then
                                    call global_stif_profile(bnevab,anevab,bnevab,anevab,ldofs,fstif,ilayer)
                                else if(type_solver=='PBCG') then
                                    call global_stif_pbcg(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                                else if(type_solver=='SSORPBCG') then !ssorpbcg
                                    call global_stif_ssorpbcg(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                                else if(type_solver=='PARDISO') then !PARDISO 2008-11-05
                                    call global_stif_pardiso(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                                endif
                                nullify(fstif0)
                                if (type_solver/='JPCG')nullify(ldofs)
                            endif
                        end do       !!ielgroup
                    endif
                    !!!!!!!!!!!!!!!!!!!!!!!!!!!
10                  continue
                end do ikh_loop       !!end do ikh
                if (allocated(fstif)) deallocate(fstif)
                bnevab=anevab
            end do     !! end do ifield
1           continue
        end if    !! for do while
    end do     !!  for igroup

    contains

        SUBROUTINE assemble_pardiso_mesh(nelgroup,list_array,mesh_kind,bnevab_l,anevab_l,nevab_field, &
            coef_base,use_duncanchang_local,ifield_idx,ikh_idx,nstre_local)
        use omp_lib
        integer(ink), intent(in) :: nelgroup,bnevab_l,anevab_l,nevab_field,ifield_idx,ikh_idx,nstre_local
        integer(ink), intent(in) :: mesh_kind
        integer(ink), intent(in) :: list_array(:)
        real   (irk), intent(in) :: coef_base
        logical, intent(in) :: use_duncanchang_local

        integer(ink) :: ielgroup, ielem, ic, ievab, ie0_local
        real   (irk) :: coef_local, lamda_local
        real   (irk), pointer :: fstif0_local(:,:)
        integer(ink), pointer :: ldofs_local(:)
        real   (irk), allocatable :: work_fstif(:,:)
        real   (irk), allocatable, target :: local_stiff_all(:,:)
        real   (irk), pointer :: local_stiff(:)
        integer(ink), allocatable, target :: local_mark_all(:,:), touched_all(:,:)
        integer(ink), allocatable :: touch_count(:)
        integer(ink), pointer :: local_mark(:), touched_row(:)
        integer(ink) :: local_touch_count
        integer(ink) :: nthreads, tid, nnz, k, tag

        if (nelgroup<=0) return
        if (nevab_field<=0) return

        nnz=size(global_stiff1)
        nthreads=omp_get_max_threads()
        allocate(local_stiff_all(nthreads,nnz))
        allocate(local_mark_all(nthreads,nnz))
        allocate(touched_all(nthreads,nnz))
        allocate(touch_count(nthreads))
        local_stiff_all=0.0_irk
        local_mark_all=0
        touch_count=0
        tag=1

!$omp parallel default(shared) private(ielgroup,ielem,fstif0_local,ldofs_local,ic,ievab,work_fstif,coef_local,lamda_local,ie0_local,tid,local_stiff,local_mark,touched_row,local_touch_count)
        tid=omp_get_thread_num()+1
        local_stiff=>local_stiff_all(tid,:)
        local_stiff=0.0_irk
        local_mark=>local_mark_all(tid,:)
        touched_row=>touched_all(tid,:)
        local_touch_count=0

        allocate(work_fstif(nevab_field,nevab_field))
!$omp do schedule(static)
        do ielgroup=1,nelgroup
            ielem=list_array(ielgroup)
            select case(mesh_kind)
            case(mesh_main)
                if (ice0(ielem)==1) cycle
                if (.not.associated(element(ielem)%field(ifield_idx)%khandmc(ikh_idx)%fstif)) cycle
                ldofs_local=>element(ielem)%ldofs
                fstif0_local=>element(ielem)%field(ifield_idx)%khandmc(ikh_idx)%fstif
            case(mesh_first)
                if (jce1(ielem)==1) cycle
                if (.not.associated(element1(ielem)%field(ifield_idx)%khandmc(ikh_idx)%fstif)) cycle
                ldofs_local=>element1(ielem)%ldofs
                fstif0_local=>element1(ielem)%field(ifield_idx)%khandmc(ikh_idx)%fstif
            case(mesh_second)
                if (.not.associated(element2(ielem)%field(ifield_idx)%khandmc(ikh_idx)%fstif)) cycle
                ldofs_local=>element2(ielem)%ldofs
                fstif0_local=>element2(ielem)%field(ifield_idx)%khandmc(ikh_idx)%fstif
            case default
                cycle
            end select

            ic=size(fstif0_local,dim=2)
            if (ikh_idx==2.and.ic==1) then
                work_fstif=0.0
                do ievab=1,nevab_field
                    work_fstif(ievab,ievab)=fstif0_local(ievab,1)
                end do
            else
                work_fstif=fstif0_local
            endif

            coef_local=coef_base
            if (use_duncanchang_local) then
                select case(mesh_kind)
                case(mesh_main)
                    lamda_local=sum(element(ielem)%field(1)%gpvar(nstre_local+1,:))/size(element(ielem)%field(1)%gpvar,dim=2)
                case(mesh_first)
                    lamda_local=sum(element1(ielem)%field(1)%gpvar(nstre_local+1,:))/size(element1(ielem)%field(1)%gpvar,dim=2)
                case(mesh_second)
                    lamda_local=sum(element2(ielem)%field(1)%gpvar(nstre_local+1,:))/size(element2(ielem)%field(1)%gpvar,dim=2)
                case default
                    lamda_local=0.0
                end select
                if (ikh_idx==1) then
                    coef_local=beeta2*ditime**2+(lamda_local/base_freq)*beeta1*ditime
                else
                    coef_local=1.0+lamda_local*base_freq*beeta1*ditime
                endif
            endif

            if (iblks==1.and.ielgroup==1.and.istep==inc_step.and.iiter==1) then
!$omp critical(estif_chk)
                write(chkunit,'(a,i5,2(a,i1),a,i6,a,i1,a,f8.5)') &
                    'igroup=',igroup,' ifield=',ifield_idx,' ikh=',ikh_idx,' ielem=',ielem, &
                    ' order_time=',order_time,'  coef=',coef_local
                do ie0_local=1,size(work_fstif,dim=1)
                    write(chkunit,'(30e16.5)')work_fstif(ie0_local,:)
                end do
!$omp end critical(estif_chk)
            endif

            work_fstif=coef_local*work_fstif
            call global_stif_pardiso(bnevab_l,anevab_l,bnevab_l,anevab_l,ldofs_local,work_fstif, &
                local_stiff,local_mark,touched_row,local_touch_count,tag)

            nullify(fstif0_local)
            nullify(ldofs_local)
        end do
!$omp end do
        deallocate(work_fstif)
        touch_count(tid)=local_touch_count
!$omp end parallel

        do tid=1,nthreads
            do k=1,touch_count(tid)
                global_stiff1(touched_all(tid,k))=global_stiff1(touched_all(tid,k))+ &
                    local_stiff_all(tid,touched_all(tid,k))
            end do
        end do
        deallocate(local_stiff_all)
        deallocate(local_mark_all)
        deallocate(touched_all)
        deallocate(touch_count)
        END SUBROUTINE assemble_pardiso_mesh

    END SUBROUTINE ESTIF_ASSEMBLE

    SUBROUTINE ESTIF_ASSEMBLE_w !freq2006
    character(10)fieldid,special,name
    integer(ink) igroup, nrfields, ifield,  index, order_time,     &
        nnode_f, nevab_f,  bnevab,  ic,            &
        ielgroup, ielem,   ievab,  ikh, anevab, ilayer, matno,  &
        index1,nnode_f1,nevab_f1,anevab1,bnevab1

    real   (irk)  omega
    real   (irk), allocatable::fstif(:,:),fstif1(:,:)
    real   (irk), pointer::fstif0(:,:)
    integer(ink), pointer::ldofs(:)
    complex(irk)  coef

    omega=ttime
    DO igroup =1,ngroup
        if (appear(igroup)>0)  then

            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            special=group(igroup)%special
            matno = group(igroup)%matno
            name=props(matno)%name
            index    = group(igroup)%index
            index1=index
            if (index==3)index1=5  !new2005
            if (index==23)index1=9 !new2005
            ilayer   = group(igroup)%ilayer
            bnevab=0
            bnevab1=0
            do ifield=1,nrfields
                nnode_f = elkn(index)%el_field(ifield)%nnode_f
                nnode_f1 = elkn(index1)%el_field(ifield)%nnode_f

                nevab_f = nnode_f*group(igroup)%dof(ifield)%nfdof
                nevab_f1 = nnode_f1*group(igroup)%dof(ifield)%nfdof
                allocate(fstif(nevab_f,nevab_f))
                anevab  =bnevab+nevab_f
                anevab1 =bnevab1+nevab_f1
                ! loop for k(h) and m(c)
                do ikh=1,2
                    !order_time=elkn(index)%el_field(ifield)%order_time(ikh)
                    order_time=group(igroup)%order_time(ikh,ifield)
                    if (fieldid(ifield:ifield)=='U')then
                        if (ikh==1)coef=cmplx(1.,-omega*group(igroup)%beta)
                        if (ikh==2)coef=-omega*cmplx(omega,group(igroup)%alfa)
                    elseif(fieldid(ifield:ifield)=='W') then
                        if (nrfields==2)then
                            if (ikh==1)coef=-1./cmplx(0.,omega)  !对称性系数与自身乘积
                            if (ikh==2)coef=cmplx(1.,0.)  !对称性系数与自身乘积
                        elseif(nrfields==1)then
                            if (ikh==1)coef=-1./cmplx(omega**2,0.)/theta1/ditime   !对称性系数与自身乘积   ! /theta1/ditime zhao 060530
                            if (ikh==2)coef=cmplx(1.,0.)/theta1/ditime   !对称性系数与自身乘积
                            if (ifsnedge/=0)then !ifs2006
                                if (ikh==1)coef=cmplx(-1./omega**2,0.)/beeta2/ditime**2
                                if (ikh==2)coef=cmplx(1.,0.)/beeta2/ditime**2
                            endif
                        endif
                    endif
                    DO ielgroup = 1,group(igroup)%nelgroup
                        ielem = group(igroup)%list(ielgroup)
                        if (associated(element(ielem)%field(ifield)%khandmc(ikh)%fstif)) then
                            ldofs=>element(ielem)%ldofs
                            fstif0=>element(ielem)%field(ifield)%khandmc(ikh)%fstif
                            ic=size(fstif0,dim=2)
                            if (ikh==2.and.ic==1)then
                                fstif=0.0
                                do ievab=1,nevab_f
                                    fstif(ievab,ievab)=fstif0(ievab,1)
                                end do
                            else
                                fstif=fstif0
                            end if

                            !     write(7,*)'ie=',ielem
                            !     write(7,*)'fstif=',fstif
                            !     write(7,*)'coef=',coef

                            call global_stif_profile_w(bnevab,anevab,bnevab,anevab,ldofs,fstif,coef)
                            nullify(fstif0,ldofs)
                        endif
100                     continue
                    end do       !!ielgroup
10                  continue
                end do        !!end do ikh
                deallocate(fstif)
                bnevab=anevab
                bnevab1=anevab1
            end do     !! end do ifield
1           continue
        end if    !! for do while
    end do     !!  for igroup

    END SUBROUTINE ESTIF_ASSEMBLE_w

    SUBROUTINE estif_assem_response
    character(10)fieldid
    integer(ink) igroup, nrfields,  nnode_f, nevab_f,  bnevab,  &
        ielgroup, ielem,  anevab, ilayer,index

    real   (irk), pointer::fstif(:,:)
    integer(ink), pointer::ldofs(:)

    ilayer=1
    DO igroup =1,ngroup
        if (appear(igroup)>0)  then
            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            bnevab=0
            if (nrfields==1.and.fieldid=='U'.or.fieldid=='W') then
                index    = group(igroup)%index
                nnode_f = elkn(index)%el_field(1)%nnode_f
                nevab_f = nnode_f*group(igroup)%dof(1)%nfdof
                allocate(fstif(nevab_f,nevab_f))
                anevab  =bnevab+nevab_f

                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (associated(element(ielem)%field(1)%khandmc(1)%fstif)) then
                        ldofs=>element(ielem)%ldofs
                        fstif=>element(ielem)%field(1)%khandmc(1)%fstif


                        if (type_solver=='JPCG') then  !zhao 20070829
                            stop ' type_solver==JPCG '
                        else if(type_solver=='PROFILE') then
                            call global_stif_profile(bnevab,anevab,bnevab,anevab,ldofs,fstif,ilayer)
                        else if(type_solver=='PBCG') then
                            stop ' type_solver==PBCG '
                        else if(type_solver=='SSORPBCG') then !ssorpbcg
                            call global_stif_ssorpbcg(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                        else if(type_solver=='PARDISO') then !PARDISO 2008-11-05
                            call global_stif_pardiso(bnevab,anevab,bnevab,anevab,ldofs,fstif)
                        endif

                        !call global_stif_profile(bnevab,anevab,bnevab,anevab,ldofs,fstif,ilayer)
                        nullify(ldofs,fstif)
                    endif
                end do       !!ielgroup
            end if !for nrfields==1.and.fieldid=='U'.or.fieldid=='W'
        end if    !! for do while
    end do     !!  for igroup

    END SUBROUTINE estif_assem_response

    !

    SUBROUTINE COUPLE_ASSEMBLE
    character(10)fieldid,special
    integer(ink) igroup, nrfields,  index, field1, field2,     &
        nevab1, nevab2, bnevab1, anevab1,             &
        bnevab2, anevab2, ncouple, icouple,         &
        ielgroup, ielem, nevab, ifield,ilayer
    integer(ink), allocatable::ldofs(:)
    real   (irk)  coef1
    real   (irk), allocatable::qmatx(:,:)

    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            special=group(igroup)%special
            index    = group(igroup)%index
            ilayer   = group(igroup)%ilayer
            ncouple  = elkn(index)%ncouple
            ielem = group(igroup)%list(1)
            if (type_solver/='JPCG') then
                nevab    = size(element(ielem)%ldofs)
                allocate(ldofs(nevab))
            end if
            do icouple=1,ncouple
                field1 =elkn(index)%couple(icouple)%field_couple(1)
                field2 =elkn(index)%couple(icouple)%field_couple(2)

                if (fieldid(field1:field1)/='U'.and.(fieldid(field2:field2)/='P'    &
                    .or.fieldid(field2:field2)/='W')) then
                    print *, 'only u-p or u-w coupling is implemented!'
                    stop
                endif
                nevab1 = elkn(index)%el_field(field1)%nnode_f*group(igroup)%dof(field1)%nfdof
                nevab2 = elkn(index)%el_field(field2)%nnode_f*group(igroup)%dof(field2)%nfdof
                bnevab1=0;bnevab2=0
                do ifield=1,field1-1
                    bnevab1=bnevab1+size(element(ielem)%field(ifield)%ldofs_f)
                end do
                do ifield=1,field2-1
                    bnevab2=bnevab2+size(element(ielem)%field(ifield)%ldofs_f)
                end do
                anevab1=bnevab1+nevab1
                anevab2=bnevab2+nevab2
                allocate(qmatx(nevab1,nevab2))
                coef1=1.0
                if (type_problem/='Q')coef1=theta1*ditime

                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (associated(element(ielem)%cstif(icouple)%qmatx)) then

                        if (type_solver/='JPCG')ldofs=element(ielem)%ldofs

                        qmatx=coef1*element(ielem)%cstif(icouple)%qmatx


                        if (type_solver=='JPCG') then
                            element(ielem)%estif(bnevab1+1:anevab1,bnevab2+1:anevab2)=             &
                                element(ielem)%estif(bnevab1+1:anevab1,bnevab2+1:anevab2)+qmatx
                            element(ielem)%estif(bnevab2+1:anevab2,bnevab1+1:anevab1)=             &
                                element(ielem)%estif(bnevab2+1:anevab2,bnevab1+1:anevab1)+             &
                                transpose(qmatx)
                        else if(type_solver=='PROFILE') then
                            call qglobal_stif_profile(bnevab1,anevab1,bnevab2,anevab2,ldofs,transpose(qmatx),ilayer)
                            call qglobal_stif_profile(bnevab2,anevab2,bnevab1,anevab1,                 &
                                ldofs,qmatx,ilayer)
                        else if(type_solver=='PBCG') then
                            call global_stif_pbcg(bnevab1,anevab1,bnevab2,anevab2,ldofs,transpose(qmatx))
                            call global_stif_pbcg(bnevab2,anevab2,bnevab1,anevab1,                 &
                                ldofs,qmatx)
                        else if(type_solver=='PARDISO') then !PARDISO
                            call global_stif_pardiso(bnevab1,anevab1,bnevab2,anevab2,ldofs,qmatx)
                            call global_stif_pardiso(bnevab2,anevab2,bnevab1,anevab1,ldofs,transpose(qmatx))
                        endif

                    endif
                end do       !!ielgroup
                deallocate(qmatx)
            end do        !!end do icouple

            if (allocated(ldofs))deallocate(ldofs)
        end if    !! for do while
    end do     !!  for igroup


    END SUBROUTINE COUPLE_ASSEMBLE

    SUBROUTINE COUPLE_ASSEMBLE_w !freq2006
    character(10)fieldid,special
    integer(ink) igroup, nrfields,  index, field1, field2,     &
        nevab1, nevab2, bnevab1, anevab1,             &
        bnevab2, anevab2, ncouple, icouple,         &
        ielgroup, ielem, nevab, ifield,ilayer
    integer(ink), allocatable::ldofs(:)
    complex (irk)  coef
    real   (irk), allocatable::qmatx(:,:)

    DO igroup =1,ngroup
        if (appear(igroup)>0) then
            ! get information from the group level
            nrfields=group(igroup)%nrfields
            fieldid=group(igroup)%fieldid
            special=group(igroup)%special
            index    = group(igroup)%index
            ilayer   = group(igroup)%ilayer
            ncouple  = elkn(index)%ncouple
            ielem = group(igroup)%list(1)
            nevab    = size(element(ielem)%ldofs)
            allocate(ldofs(nevab))
            do icouple=1,ncouple
                field1 =elkn(index)%couple(icouple)%field_couple(1)
                field2 =elkn(index)%couple(icouple)%field_couple(2)

                if (fieldid(field1:field1)/='U'.and.(fieldid(field2:field2)/='P'    &
                    .or.fieldid(field2:field2)/='W')) then
                    print *, 'only u-p or u-w coupling is implemented!'
                    stop
                endif
                nevab1 = elkn(index)%el_field(field1)%nnode_f*group(igroup)%dof(field1)%nfdof
                nevab2 = elkn(index)%el_field(field2)%nnode_f*group(igroup)%dof(field2)%nfdof
                bnevab1=0;bnevab2=0
                do ifield=1,field1-1
                    bnevab1=bnevab1+size(element(ielem)%field(ifield)%ldofs_f)
                end do
                do ifield=1,field2-1
                    bnevab2=bnevab2+size(element(ielem)%field(ifield)%ldofs_f)
                end do
                anevab1=bnevab1+nevab1
                anevab2=bnevab2+nevab2
                allocate(qmatx(nevab1,nevab2))
                coef=cmplx(1.0,0.)
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (associated(element(ielem)%cstif(icouple)%qmatx)) then

                        ldofs=element(ielem)%ldofs
                        qmatx=element(ielem)%cstif(icouple)%qmatx


                        call qglobal_stif_profile_w(bnevab1,anevab1,bnevab2,anevab2,ldofs,transpose(qmatx),coef)
                        call qglobal_stif_profile_w(bnevab2,anevab2,bnevab1,anevab1,                 &
                            ldofs,qmatx,coef)

                    endif
                end do       !!ielgroup
                deallocate(qmatx)
            end do        !!end do icouple
            deallocate(ldofs)
        end if    !! for do while
    end do     !!  for igroup


    END SUBROUTINE COUPLE_ASSEMBLE_w

    SUBROUTINE global_stif_profile(bnevab1,anevab1,bnevab2,anevab2,ldofs,estif,ilayer)
    integer(ink) bnevab1,anevab1,bnevab2,anevab2,ldofs(:)
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum,ilayer
    integer(ink) iintf,nintf,jintf,njntf   !!int2000
    real   (irk) facti,factj  !!int2000
    real   (irk) estif(:,:)

    if (nlayer/=2) then
        !   do j= bnevab1+1,anevab1
        !   jdofn=ldofs(j)
        !   jeq  =totveq(jdofn)
        !      if(jeq/=0) then
        !      colum0=iseq(jeq)-jeq
        !         do i=bnevab2+1,anevab2
        !            idofn=ldofs(i)
        !            ieq  =totveq(idofn)
        !            if(ieq/=0.and.ieq<=jeq) then
        !            colum=colum0+ieq
        !global_stiff1(colum)=global_stiff1(colum)+estif(i-bnevab2,j-bnevab1)
        !if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
        !estif(j-bnevab1,i-bnevab2)
        !            endif
        !          end do
        !       endif
        !    end do

        !!int2000
        do j= bnevab1+1,anevab1
            jdofn=ldofs(j)
            njntf=trans(jdofn)%nintf
            do i=bnevab2+1,anevab2
                idofn=ldofs(i)
                nintf=trans(idofn)%nintf
                if (njntf==0.and.nintf==0) then !!1
                    jeq  =totveq(jdofn)
                    ieq  =totveq(idofn)
                    if (jeq/=0.and.ieq/=0.and.ieq<=jeq) then
                        colum=iseq(jeq)-jeq+ieq
                        global_stiff1(colum)=global_stiff1(colum)+    &
                            estif(i-bnevab2,j-bnevab1)
                        if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                            estif(j-bnevab1,i-bnevab2)
                    endif
                elseif(njntf/=0.and.nintf==0) then !!2
                    ieq  =totveq(idofn)
                    if (ieq/=0) then
                        do jintf=1,njntf
                            jeq =totveq(trans(jdofn)%listf(jintf))
                            factj=trans(jdofn)%rintf(jintf)
                            if (jeq/=0.and.ieq<=jeq) then
                                colum=iseq(jeq)-jeq+ieq
                                global_stiff1(colum)=global_stiff1(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*factj
                                if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                                    estif(j-bnevab1,i-bnevab2)*factj
                            endif
                        end do
                    endif
                elseif(njntf==0.and.nintf/=0) then !!3
                    jeq  =totveq(jdofn)
                    if (jeq/=0) then
                        do iintf=1,nintf
                            ieq =totveq(trans(idofn)%listf(iintf))
                            facti=trans(idofn)%rintf(iintf)
                            if (ieq/=0.and.ieq<=jeq) then
                                colum=iseq(jeq)-jeq+ieq
                                global_stiff1(colum)=global_stiff1(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*facti
                                if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                                    estif(j-bnevab1,i-bnevab2)*facti
                            endif
                        end do
                    endif
                elseif(njntf/=0.and.nintf/=0) then !!4
                    do iintf=1,nintf
                        ieq =totveq(trans(idofn)%listf(iintf))
                        facti=trans(idofn)%rintf(iintf)
                        do jintf=1,njntf
                            jeq =totveq(trans(jdofn)%listf(jintf))
                            factj=trans(jdofn)%rintf(jintf)
                            if (ieq/=0.and.jeq/=0.and.ieq<=jeq) then
                                colum=iseq(jeq)-jeq+ieq
                                global_stiff1(colum)=global_stiff1(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*facti*factj
                                if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                                    estif(j-bnevab1,i-bnevab2)*facti*factj
                            endif
                        end do
                    end do
                endif  !!4
            end do
        end do
        !!int2000

        !
    else

        do j= bnevab1+1,anevab1
            jdofn=ldofs(j)
            jeq  =totveq(jdofn)
            if (jeq==0) goto 1
            colum0=iseq(jeq)-jeq
            do i=bnevab2+1,anevab2
                idofn=ldofs(i)
                ieq  =totveq(idofn)
                if (ieq==0.or.ieq.gt.jeq) goto 2
                !      if(ilayer==1.and.(jeq.gt.neq_layer1.or.ieq.gt.neq_layer1)) goto 2
                if (ilayer==1.and.jeq.le.neq_layer1.and.ieq.gt.neq_layer1) goto 2
                if (ilayer==1.and.jeq.gt.neq_layer1.and.ieq.le.neq_layer1) goto 2
                if (kresl_layer1==0.and.ieq.le.neq_layer1) goto 2
                if (kresl_layer2==0.and.ieq.gt.neq_layer1) goto 2
                colum=colum0+ieq
                global_stiff1(colum)=global_stiff1(colum)+estif(i-bnevab2,j-bnevab1)
                if (ilayer==1.and.nonsym==1.and.ieq.gt.neq_layer1) goto 2
                if (nonsym/=0.and.ilayer==1)global_stiff2(colum)=global_stiff2(colum)+ &
                    estif(j-bnevab1,i-bnevab2)
                if (nonsym==2.and.ilayer==2)global_stiff2(colum)=global_stiff2(colum)+ &
                    estif(j-bnevab1,i-bnevab2)
2               continue
            end do
1           continue
        end do
    endif


    END SUBROUTINE global_stif_profile

    SUBROUTINE global_stif_profile_w(bnevab1,anevab1,bnevab2,anevab2,ldofs,estif,coef) !freq2006
    integer(ink) bnevab1,anevab1,bnevab2,anevab2,ldofs(:)
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum,ilayer
    integer(ink) iintf,nintf,jintf,njntf   !!int2000
    real   (irk) facti,factj  !!int2000
    real   (irk) estif(:,:)
    complex(irk) coef

    !!int2000
    do j= bnevab1+1,anevab1
        jdofn=ldofs(j)
        njntf=trans(jdofn)%nintf
        do i=bnevab2+1,anevab2
            idofn=ldofs(i)
            nintf=trans(idofn)%nintf
            if (njntf==0.and.nintf==0) then !!1
                jeq  =totveq(jdofn)
                ieq  =totveq(idofn)
                if (jeq/=0.and.ieq/=0.and.ieq<=jeq) then
                    colum=iseq(jeq)-jeq+ieq
                    global_stiff1w(colum)=global_stiff1w(colum)+    &
                        estif(i-bnevab2,j-bnevab1)*coef
                    if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                        estif(j-bnevab1,i-bnevab2)*coef
                endif
            elseif(njntf/=0.and.nintf==0) then !!2
                ieq  =totveq(idofn)
                if (ieq/=0) then
                    do jintf=1,njntf
                        jeq =totveq(trans(jdofn)%listf(jintf))
                        factj=trans(jdofn)%rintf(jintf)
                        if (jeq/=0.and.ieq<=jeq) then
                            colum=iseq(jeq)-jeq+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*factj*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                                estif(j-bnevab1,i-bnevab2)*factj*coef
                        endif
                    end do
                endif
            elseif(njntf==0.and.nintf/=0) then !!3
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    do iintf=1,nintf
                        ieq =totveq(trans(idofn)%listf(iintf))
                        facti=trans(idofn)%rintf(iintf)
                        if (ieq/=0.and.ieq<=jeq) then
                            colum=iseq(jeq)-jeq+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*facti*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                                estif(j-bnevab1,i-bnevab2)*facti*coef
                        endif
                    end do
                endif
            elseif(njntf/=0.and.nintf/=0) then !!4
                do iintf=1,nintf
                    ieq =totveq(trans(idofn)%listf(iintf))
                    facti=trans(idofn)%rintf(iintf)
                    do jintf=1,njntf
                        jeq =totveq(trans(jdofn)%listf(jintf))
                        factj=trans(jdofn)%rintf(jintf)
                        if (ieq/=0.and.jeq/=0.and.ieq<=jeq) then
                            colum=iseq(jeq)-jeq+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*facti*factj*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                                estif(j-bnevab1,i-bnevab2)*facti*factj*coef
                        endif
                    end do
                end do
            endif  !!4
        end do
    end do
    !!int2000

    END SUBROUTINE global_stif_profile_w

    SUBROUTINE qglobal_stif_profile(bnevab1,anevab1,bnevab2,anevab2,ldofs,estif,ilayer)
    integer(ink) bnevab1,anevab1,bnevab2,anevab2,ldofs(:)
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum,ilayer
    real   (irk) estif(:,:)
    integer(ink) iintf,nintf,jintf,njntf   !!int2000
    real   (irk) facti,factj  !!int2000

    if (nlayer/=2) then
        !   do j= bnevab1+1,anevab1
        !   jdofn=ldofs(j)
        !   jeq  =totveq(jdofn)
        !      if(jeq/=0) then
        !      colum0=iseq(jeq)-jeq
        !         do i=bnevab2+1,anevab2
        !            idofn=ldofs(i)
        !            ieq  =totveq(idofn)
        !            if(ieq/=0.and.ieq<=jeq) then
        !            colum=colum0+ieq
        !global_stiff1(colum)=global_stiff1(colum)+estif(i-bnevab2,j-bnevab1)
        !if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
        !estif(i-bnevab2,j-bnevab1)
        !            endif
        !          end do
        !       endif
        !    end do

        !!int2000
        do j= bnevab1+1,anevab1
            jdofn=ldofs(j)
            njntf=trans(jdofn)%nintf
            do i=bnevab2+1,anevab2
                idofn=ldofs(i)
                nintf=trans(idofn)%nintf
                if (njntf==0.and.nintf==0) then !!1
                    jeq  =totveq(jdofn)
                    ieq  =totveq(idofn)
                    if (jeq/=0.and.ieq/=0.and.ieq<=jeq) then
                        colum=iseq(jeq)-jeq+ieq
                        global_stiff1(colum)=global_stiff1(colum)+    &
                            estif(i-bnevab2,j-bnevab1)
                        if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                            estif(i-bnevab2,j-bnevab1)
                    endif
                elseif(njntf/=0.and.nintf==0) then !!2
                    ieq  =totveq(idofn)
                    if (ieq/=0) then
                        do jintf=1,njntf
                            jeq =totveq(trans(jdofn)%listf(jintf))
                            factj=trans(jdofn)%rintf(jintf)
                            if (jeq/=0.and.ieq<=jeq) then
                                colum=iseq(jeq)-jeq+ieq
                                global_stiff1(colum)=global_stiff1(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*factj
                                if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*factj
                            endif
                        end do
                    endif
                elseif(njntf==0.and.nintf/=0) then !!3
                    jeq  =totveq(jdofn)
                    if (jeq/=0) then
                        do iintf=1,nintf
                            ieq =totveq(trans(idofn)%listf(iintf))
                            facti=trans(idofn)%rintf(iintf)
                            if (ieq/=0.and.ieq<=jeq) then
                                colum=iseq(jeq)-jeq+ieq
                                global_stiff1(colum)=global_stiff1(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*facti
                                if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*facti
                            endif
                        end do
                    endif
                elseif(njntf/=0.and.nintf/=0) then !!4
                    do iintf=1,nintf
                        ieq =totveq(trans(idofn)%listf(iintf))
                        facti=trans(idofn)%rintf(iintf)
                        do jintf=1,njntf
                            jeq =totveq(trans(jdofn)%listf(jintf))
                            factj=trans(jdofn)%rintf(jintf)
                            if (ieq/=0.and.jeq/=0.and.ieq<=jeq) then
                                colum=iseq(jeq)-jeq+ieq
                                global_stiff1(colum)=global_stiff1(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*facti*factj
                                if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+    &
                                    estif(i-bnevab2,j-bnevab1)*facti*factj
                            endif
                        end do
                    end do
                endif  !!4
            end do
        end do
        !!int2000

    else

        do j= bnevab1+1,anevab1
            jdofn=ldofs(j)
            jeq  =totveq(jdofn)
            if (jeq==0) goto 1
            colum0=iseq(jeq)-jeq
            do i=bnevab2+1,anevab2
                idofn=ldofs(i)
                ieq  =totveq(idofn)
                if (ieq==0.or.ieq.gt.jeq) goto 2
                !      if(ilayer==1.and.(jeq.gt.neq_layer1.or.ieq.gt.neq_layer1)) goto 2
                if (ilayer==1.and.jeq.le.neq_layer1.and.ieq.gt.neq_layer1) goto 2
                if (ilayer==1.and.jeq.gt.neq_layer1.and.ieq.le.neq_layer1) goto 2
                if (kresl_layer1==0.and.ieq.le.neq_layer1) goto 2
                if (kresl_layer2==0.and.ieq.gt.neq_layer1) goto 2
                colum=colum0+ieq
                global_stiff1(colum)=global_stiff1(colum)+estif(i-bnevab2,j-bnevab1)
                if (ilayer==1.and.nonsym==1.and.ieq.gt.neq_layer1) goto 2
                if (nonsym/=0.and.ilayer==1)global_stiff2(colum)=global_stiff2(colum)+ &
                    estif(i-bnevab2,j-bnevab1)
                if (nonsym==2.and.ilayer==2)global_stiff2(colum)=global_stiff2(colum)+ &
                    estif(i-bnevab2,j-bnevab1)
2               continue
            end do
1           continue
        end do
    endif


    END SUBROUTINE qglobal_stif_profile

    SUBROUTINE qglobal_stif_profile_w(bnevab1,anevab1,bnevab2,anevab2,ldofs,estif,coef) !freq2006
    integer(ink) bnevab1,anevab1,bnevab2,anevab2,ldofs(:)
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum
    real   (irk) estif(:,:)
    integer(ink) iintf,nintf,jintf,njntf   !!int2000
    real   (irk) facti,factj  !!int2000
    complex(irk) coef

    !!int2000
    do j= bnevab1+1,anevab1
        jdofn=ldofs(j)
        njntf=trans(jdofn)%nintf
        do i=bnevab2+1,anevab2
            idofn=ldofs(i)
            nintf=trans(idofn)%nintf
            if (njntf==0.and.nintf==0) then !!1
                jeq  =totveq(jdofn)
                ieq  =totveq(idofn)
                if (jeq/=0.and.ieq/=0.and.ieq<=jeq) then
                    colum=iseq(jeq)-jeq+ieq
                    global_stiff1w(colum)=global_stiff1w(colum)+    &
                        estif(i-bnevab2,j-bnevab1)*coef
                    if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                        estif(i-bnevab2,j-bnevab1)*coef
                endif
            elseif(njntf/=0.and.nintf==0) then !!2
                ieq  =totveq(idofn)
                if (ieq/=0) then
                    do jintf=1,njntf
                        jeq =totveq(trans(jdofn)%listf(jintf))
                        factj=trans(jdofn)%rintf(jintf)
                        if (jeq/=0.and.ieq<=jeq) then
                            colum=iseq(jeq)-jeq+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*factj*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*factj*coef
                        endif
                    end do
                endif
            elseif(njntf==0.and.nintf/=0) then !!3
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    do iintf=1,nintf
                        ieq =totveq(trans(idofn)%listf(iintf))
                        facti=trans(idofn)%rintf(iintf)
                        if (ieq/=0.and.ieq<=jeq) then
                            colum=iseq(jeq)-jeq+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*facti*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*facti*coef
                        endif
                    end do
                endif
            elseif(njntf/=0.and.nintf/=0) then !!4
                do iintf=1,nintf
                    ieq =totveq(trans(idofn)%listf(iintf))
                    facti=trans(idofn)%rintf(iintf)
                    do jintf=1,njntf
                        jeq =totveq(trans(jdofn)%listf(jintf))
                        factj=trans(jdofn)%rintf(jintf)
                        if (ieq/=0.and.jeq/=0.and.ieq<=jeq) then
                            colum=iseq(jeq)-jeq+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*facti*factj*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+    &
                                estif(i-bnevab2,j-bnevab1)*facti*factj*coef
                        endif
                    end do
                end do
            endif  !!4
        end do
    end do
    !!int2000
    END SUBROUTINE qglobal_stif_profile_w
    !! stablize

    SUBROUTINE stabpw_assemble
    integer(ink) ipoin,igroup,np_unode
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum
    integer(ink),pointer::patch_nod(:)
    real   (irk),pointer::patch_sta(:,:)
    do igroup=1,ngroup
        if (appear(igroup)>0) then
            do ipoin=1,group(igroup)%np_unode                      !!ipoin
                np_unode=group(igroup)%unode(ipoin)%np_unode
                if (np_unode>0) then
                    patch_nod=>group(igroup)%unode(ipoin)%patch_nod
                    patch_sta=>group(igroup)%unode(ipoin)%patch_sta
                    do j= 1,np_unode                 !!j
                        jdofn=nodfn(ndimn+1,patch_nod(j))
                        jeq  =totveq(jdofn)
                        if (jeq/=0) then
                            colum0=iseq(jeq)-jeq
                            do i=1,np_unode      !!i
                                idofn=nodfn(ndimn+1,patch_nod(i))
                                ieq  =totveq(idofn)
                                if (ieq/=0.and.ieq<=jeq) then
                                    colum=colum0+ieq
                                    global_stiff1(colum)=global_stiff1(colum)+patch_sta(i,j)
                                    if (nonsym==1)   &
                                        global_stiff2(colum)=global_stiff2(colum)+patch_sta(j,i)
                                endif
                            end do           !!i
                        endif
                    end do                       !!j

                    nullify(patch_nod,patch_sta)
                endif
            end do                          !!ipoin
        endif
    end do

    END SUBROUTINE stabpw_assemble


    !! end of stablize

    SUBROUTINE stabpw_assemble_w !freq2006
    integer(ink) ipoin,igroup,np_unode
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum
    integer(ink),pointer::patch_nod(:)
    real   (irk),pointer::patch_sta(:,:)
    do igroup=1,ngroup
        if (appear(igroup)>0) then
            do ipoin=1,group(igroup)%np_unode                      !!ipoin
                np_unode=group(igroup)%unode(ipoin)%np_unode
                if (np_unode>0) then
                    patch_nod=>group(igroup)%unode(ipoin)%patch_nod
                    patch_sta=>group(igroup)%unode(ipoin)%patch_sta
                    do j= 1,np_unode                 !!j
                        jdofn=nodfn(ndimn+1,patch_nod(j))
                        jeq  =totveq(jdofn)
                        if (jeq/=0) then
                            colum0=iseq(jeq)-jeq
                            do i=1,np_unode      !!i
                                idofn=nodfn(ndimn+1,patch_nod(i))
                                ieq  =totveq(idofn)
                                if (ieq/=0.and.ieq<=jeq) then
                                    colum=colum0+ieq
                                    global_stiff1w(colum)=global_stiff1w(colum)+patch_sta(i,j)
                                    if (nonsym==1)   &
                                        global_stiff2w(colum)=global_stiff2w(colum)+patch_sta(j,i)
                                endif
                            end do           !!i
                        endif
                    end do                       !!j

                    nullify(patch_nod,patch_sta)
                endif
            end do                          !!ipoin
        endif
    end do

    END SUBROUTINE stabpw_assemble_w

    !! semi_infinity space

    SUBROUTINE semi_inf_space_assemble
    integer(ink) i,j, idofn,jdofn, ieq,jeq, colum0,colum

    do j= 1,ndofn_space              !!j
        jdofn=ldofs_space(j)
        !write(7,*)'j=',j,'jdofn=',jdofn
        jeq  =totveq(jdofn)
        if (jeq/=0) then
            colum0=iseq(jeq)-jeq
            do i=1,ndofn_space      !!i
                idofn=ldofs_space(i)
                ieq  =totveq(idofn)
                if (ieq/=0.and.ieq<=jeq) then
                    colum=colum0+ieq
                    global_stiff1(colum)=global_stiff1(colum)+estif_space(i,j)
                    !write(7,*) 'i1=',i,'estif_space(i,j)=',estif_space(i,j)
                    if (nonsym==1)   &
                        global_stiff2(colum)=global_stiff2(colum)+estif_space(j,i)
                    !write(7,*) 'i2=',i,'estif_space(i,j)=',estif_space(j,i)
                endif
            end do           !!i
        endif
    end do                       !!j
    END SUBROUTINE semi_inf_space_assemble


    !! end of semi_infinity

    SUBROUTINE global_stif_pbcg(bnevab1,anevab1,bnevab2,anevab2,ldofs,estif)
    integer(ink) bnevab1,anevab1,bnevab2,anevab2,ldofs(:)
    integer(ink) i,j, idofn,jdofn, ieq,jeq, kstore
    real   (irk) estif(:,:)

    do i= bnevab1+1,anevab1
        idofn=ldofs(i)
        ieq  =totveq(idofn)
        if (ieq/=0) then
            do j=bnevab2+1,anevab2
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    if (ieq==jeq) then
                        kstore=ieq
                    else
                        do kstore=iseq(ieq),iseq(ieq+1)-1
                            if (iseq(kstore)==jeq)exit
                        end do
                    endif
                    global_stiff1(kstore)=global_stiff1(kstore)+estif(i-bnevab1,j-bnevab2)
                endif
            end do
        endif
    end do

    END SUBROUTINE global_stif_pbcg

    SUBROUTINE global_stif_ssorpbcg(bnevab1,anevab1,bnevab2,anevab2,ldofs,estif) !ssorpbcg
    integer(ink) bnevab1,anevab1,bnevab2,anevab2,ldofs(:)
    integer(ink) i,j, k,idofn,jdofn, ieq,jeq,nintf,njntf,iintf,jintf
    real   (irk) facti,factj,estif(:,:)


    do i= bnevab1+1,anevab1
        idofn=ldofs(i)
        nintf=trans(idofn)%nintf
        do j=bnevab2+1,anevab2
            jdofn=ldofs(j)
            njntf=trans(jdofn)%nintf
            !      print *,'nintf=',nintf,'njntf=',njntf
            if (njntf==0.and.nintf==0) then !!1
                jeq  =totveq(jdofn)
                ieq  =totveq(idofn)
                if (ieq==0.or.jeq==0)cycle
                if (ieq<jeq)cycle
                if  (ieq==1)then
                    global_stiff1(1)=global_stiff1(1)+estif(i-bnevab1,j-bnevab2)
                    cycle
                endif
                do k=iseq(ieq-1)+1,iseq(ieq)
                    if (jeq==nndex(k))then
                        global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)
                    endif
                enddo
            elseif(njntf/=0.and.nintf==0) then !!2
                ieq  =totveq(idofn)
                if (ieq==0) cycle
                do jintf=1,njntf
                    jeq =totveq(trans(jdofn)%listf(jintf))
                    factj=trans(jdofn)%rintf(jintf)
                    if (jeq==0.or.ieq<jeq) cycle
                    if  (ieq==1)then
                        global_stiff1(1)=global_stiff1(1)+estif(i-bnevab1,j-bnevab2)*factj
                        cycle
                    endif
                    do k=iseq(ieq-1)+1,iseq(ieq)
                        if (jeq==nndex(k))then
                            global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)*factj
                            goto 10
                        endif
                    enddo
10                  continue
                end do
            elseif(njntf==0.and.nintf/=0) then !!3
                jeq  =totveq(jdofn)
                if (jeq==0) cycle
                do iintf=1,nintf
                    ieq =totveq(trans(idofn)%listf(iintf))
                    if (ieq==0.or.ieq<jeq) cycle
                    facti=trans(idofn)%rintf(iintf)
                    if  (ieq==1)then
                        global_stiff1(1)=global_stiff1(1)+estif(i-bnevab1,j-bnevab2)*facti
                        cycle
                    endif
                    do k=iseq(ieq-1)+1,iseq(ieq)
                        if (jeq==nndex(k))then
                            global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)*facti
                            goto 20
                        endif
                    enddo
20                  continue
                end do
            elseif(njntf/=0.and.nintf/=0) then !!4
                do iintf=1,nintf
                    ieq =totveq(trans(idofn)%listf(iintf))
                    if (ieq==0) cycle
                    facti=trans(idofn)%rintf(iintf)
                    do jintf=1,njntf
                        jeq =totveq(trans(jdofn)%listf(jintf))
                        if (jeq==0) cycle
                        factj=trans(jdofn)%rintf(jintf)
                        if (ieq<jeq) cycle
                        if  (ieq==1)then
                            global_stiff1(1)=global_stiff1(1)+estif(i-bnevab1,j-bnevab2)*facti*factj
                            cycle
                        endif
                        do k=iseq(ieq-1)+1,iseq(ieq)
                            if (jeq==nndex(k))then
                                global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)*facti*factj
                                goto 30
                            endif
                        enddo
30                      continue
                    end do
                end do
            endif

        enddo
    enddo

    END SUBROUTINE global_stif_ssorpbcg
    SUBROUTINE global_stif_pardiso(bnevab1,anevab1,bnevab2,anevab2,ldofs,estif,local_stiff,local_mark,touched,local_count,tag_in) !pardiso
    integer(ink) bnevab1,anevab1,bnevab2,anevab2,ldofs(:)
    integer(ink) i,j, k,idofn,jdofn, ieq,jeq,nintf,njntf,iintf,jintf
    real   (irk) facti,factj,estif(:,:)
    real   (irk), intent(inout), optional, target :: local_stiff(:)
    integer(ink), intent(inout), optional, target :: local_mark(:), touched(:)
    integer(ink), intent(inout), optional :: local_count
    integer(ink), intent(in), optional :: tag_in
    real   (irk), pointer :: target_stiff(:)
    integer(ink), pointer :: target_mark(:), target_touched(:)
    integer(ink) :: lc, tag
    logical :: use_local

    use_local=present(local_stiff)
    if (use_local) then
        target_stiff=>local_stiff
        target_mark=>local_mark
        target_touched=>touched
        lc=local_count
        tag=tag_in
    endif

    do i= bnevab1+1,anevab1
        idofn=ldofs(i)
        nintf=trans(idofn)%nintf
        do j=bnevab2+1,anevab2
            jdofn=ldofs(j)
            njntf=trans(jdofn)%nintf
            !		 print *,'nintf=',nintf,'njntf=',njntf
                if(njntf==0.and.nintf==0) then !!1
                    jeq  =totveq(jdofn)
                    ieq  =totveq(idofn)
                    if(ieq==0.or.jeq==0)cycle
                    !if(ieq>jeq)cycle
                    if(nonsym==0.and.ieq>jeq)cycle !20240312 YL
                    do k=iseq(ieq),iseq(ieq+1)-1
                        if(jeq==nndex(k))then
                        if (use_local) then
                            if (target_mark(k)/=tag) then
                                target_mark(k)=tag
                                lc=lc+1
                                target_touched(lc)=k
                            endif
                            target_stiff(k)=target_stiff(k)+estif(i-bnevab1,j-bnevab2)
                        else
!$omp atomic update
                            global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)
                        endif
                        !if(ieq==jeq.and.(global_stiff1(k).le.1.e-5))then
                        !    print *,'1'
                        !endif
                        exit
                    endif
                enddo
                elseif(njntf/=0.and.nintf==0) then !!2
                ieq  =totveq(idofn)
                if(ieq==0) cycle
                do jintf=1,njntf
                    jeq =totveq(trans(jdofn)%listf(jintf))
                    factj=trans(jdofn)%rintf(jintf)
                    !if(jeq==0.or.ieq>jeq) cycle
                    if(jeq==0.or.(nonsym==0.and.ieq>jeq))cycle !20240312 YL
                    do k=iseq(ieq),iseq(ieq+1)-1
                        if(jeq==nndex(k))then
                            if (use_local) then
                                if (target_mark(k)/=tag) then
                                    target_mark(k)=tag
                                    lc=lc+1
                                    target_touched(lc)=k
                                endif
                                target_stiff(k)=target_stiff(k)+estif(i-bnevab1,j-bnevab2)*factj
                            else
!$omp atomic update
                                global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)*factj
                            endif
                            goto 10
                        endif
                    enddo
10                  continue
                end do
            elseif(njntf==0.and.nintf/=0) then !!3
                jeq  =totveq(jdofn)
                if(jeq==0) cycle
                do iintf=1,nintf
                    ieq =totveq(trans(idofn)%listf(iintf))
                    !if(ieq==0.or.ieq>jeq) cycle
                    if(ieq==0.or.(nonsym==0.and.ieq>jeq))cycle !20240312 YL
                    facti=trans(idofn)%rintf(iintf)

                    do k=iseq(ieq),iseq(ieq+1)-1
                        if(jeq==nndex(k))then
                            if (use_local) then
                                if (target_mark(k)/=tag) then
                                    target_mark(k)=tag
                                    lc=lc+1
                                    target_touched(lc)=k
                                endif
                                target_stiff(k)=target_stiff(k)+estif(i-bnevab1,j-bnevab2)*facti
                            else
!$omp atomic update
                                global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)*facti
                            endif
                            goto 20
                        endif
                    enddo
20                  continue
                end do
            elseif(njntf/=0.and.nintf/=0) then !!4
                do iintf=1,nintf
                    ieq =totveq(trans(idofn)%listf(iintf))
                    if(ieq==0) cycle
                    facti=trans(idofn)%rintf(iintf)
                    do jintf=1,njntf
                        jeq =totveq(trans(jdofn)%listf(jintf))
                        if(jeq==0) cycle
                        factj=trans(jdofn)%rintf(jintf)
                        !if(ieq>jeq) cycle
                        if(nonsym==0.and.ieq>jeq)cycle !20240312 YL
                        do k=iseq(ieq),iseq(ieq+1)-1
                            if(jeq==nndex(k))then
                                if (use_local) then
                                    if (target_mark(k)/=tag) then
                                        target_mark(k)=tag
                                        lc=lc+1
                                        target_touched(lc)=k
                                    endif
                                    target_stiff(k)=target_stiff(k)+estif(i-bnevab1,j-bnevab2)*facti*factj
                                else
!$omp atomic update
                                    global_stiff1(k)=global_stiff1(k)+estif(i-bnevab1,j-bnevab2)*facti*factj
                                endif
                                goto 30
                            endif
                        enddo
30                      continue
                    end do
                end do
            endif	!endif elseif(njntf/=0.and.nintf/=0)

        enddo
    enddo
    if (use_local) local_count=lc
    END SUBROUTINE global_stif_pardiso

    subroutine change1_dmatx(dmatx,yld,rot)
    integer(ink) idimn,jdimn
    real   (irk) dmatx(:,:),rot(:),yld
    real   (irk),allocatable:: rr(:,:),rr0(:,:),tt(:,:),dmatxl(:,:)

    allocate(rr0(ndimn,ndimn),rr(ndimn+1,ndimn+1),tt(3*(ndimn-1),3*(ndimn-1)))
    allocate(dmatxl(3*(ndimn-1),3*(ndimn-1)))
    dmatxl=dmatx
    if (yld>=1.) then
        !if(yld==2.) then
        !dmatxl=0.
        !else
        if (ndimn==2)dmatxl(3,3)=0.
        if (ndimn==3) then
            dmatxl(5,5)=0.
            dmatxl(6,6)=0.
            !endif
        endif
    endif

    call direct(rot,rr0,ndimn)

    rr(1:ndimn,1:ndimn)=rr0
    rr(1:ndimn,ndimn+1)=rr(1:ndimn,1)
    rr(ndimn+1,1:ndimn)=rr(1,1:ndimn)
    rr(ndimn+1,ndimn+1)=rr(1,1)

    tt=0.0
    tt(1:ndimn,1:ndimn)=rr0**2

    if (ndimn==2) then
        tt(1,3)=rr(1,1)*rr(1,2)
        tt(2,3)=rr(2,1)*rr(2,2)
        tt(3,1)=2*rr(1,1)*rr(2,1)
        tt(3,2)=2*rr(1,2)*rr(2,2)
        tt(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)

    else if(ndimn==3) then



        do idimn=1,ndimn
            do jdimn=1,ndimn
                tt(idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn,jdimn+1)
                tt(3+idimn,jdimn)=2*rr(idimn,jdimn)*rr(idimn+1,jdimn)
                tt(3+idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                    rr(idimn+1,jdimn)*rr(idimn,jdimn+1)
            end do
        end do
    endif
    dmatx=dmatxl.x.tt
    dmatxl=dmatx
    dmatx=transpose(tt).x.dmatxl

    deallocate(dmatxl,rr,rr0,tt)
    end subroutine change1_dmatx

    subroutine dmatxf_change(e,dmatx,rotation) !这是原来的程序，似乎有点问题，主要是少了tti，并且2.0系数也不对
    integer(ink) idimn,jdimn
    real   (irk) e,dmatx(:,:),rotation(:,:)
    real   (irk),allocatable:: rr(:,:),rr0(:,:),tt(:,:),dmatxl(:,:),rot(:)

    allocate(rr0(ndimn,ndimn),rr(ndimn+1,ndimn+1),tt(3*(ndimn-1),3*(ndimn-1)))
    allocate(dmatxl(3*(ndimn-1),3*(ndimn-1)),rot(ndimn))

    rot=rotation(1,:)
    dmatxl=0.
    dmatxl(ndimn,ndimn)=e

    call direct(rot,rr0,ndimn)

    rr(1:ndimn,1:ndimn)=rr0
    rr(1:ndimn,ndimn+1)=rr(1:ndimn,1)
    rr(ndimn+1,1:ndimn)=rr(1,1:ndimn)
    rr(ndimn+1,ndimn+1)=rr(1,1)

    tt=0.0
    tt(1:ndimn,1:ndimn)=rr0**2

    if (ndimn==2) then
        tt(1,3)=rr(1,1)*rr(1,2)
        tt(2,3)=rr(2,1)*rr(2,2)
        tt(3,1)=2*rr(1,1)*rr(2,1)
        tt(3,2)=2*rr(1,2)*rr(2,2)
        tt(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)

    else if(ndimn==3) then
        do idimn=1,ndimn
            do jdimn=1,ndimn
                tt(idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn,jdimn+1)
                tt(3+idimn,jdimn)=2*rr(idimn,jdimn)*rr(idimn+1,jdimn)
                tt(3+idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                    rr(idimn+1,jdimn)*rr(idimn,jdimn+1)
            end do
        end do
    endif
    dmatx=dmatxl.x.tt
    dmatxl=dmatx
    dmatx=transpose(tt).x.dmatxl

    deallocate(dmatxl,rr,rr0,tt,rot)
    end subroutine dmatxf_change


    subroutine ecmat ( SPtype,dmatx,young,poiss)

    !      ------  Obtain the constitutive elastic matrix (Isotropic)

    !-----------------------------------------------------------------------
    character(10) SPtype
    real(irk)  young,poiss,const,conss,consr

    real(irk)  G,alfa,beta,dmatx(:,:)


    dmatx=0.0_irk
    !      ------  1D solid elements

    if  (ndimn==1) then
        dmatx(1,1) = Young
        return
    endif

    if (ndimn==2) then

        !      ------  Plane stress

        if  (SPtype=='PS') then
            const=young/(1.0-poiss*poiss)
            dmatx(1,1) = const
            dmatx(2,2) = const
            dmatx(1,2) = const*poiss
            dmatx(2,1) = const*poiss
            dmatx(3,3) = (1.0-poiss)*const/2.0
            return

            !      ------  Plane strain

        else if (SPtype=='PE') then
            const  = young*(1.0-poiss)/((1.0+poiss)*(1.0-2.0*poiss))
            CONSS=CONST*POISS/(1.0-POISS)
            CONSR=CONST*(1.0-2.0*POISS)/(2.0*(1.0-POISS))
            DMATX(1,1)=CONST
            DMATX(2,2)=CONST
            DMATX(3,3)=CONSR
            DMATX(1,2)=CONSS
            DMATX(2,1)=CONSS
            dmatx(4,4)=const
            dmatx(1,4)=conss
            dmatx(2,4)=conss
            dmatx(4,1)=conss
            dmatx(4,2)=conss
            return

            !      ------  Axisymmetric

        else if (SPtype=='AX') then
            const = young*(1.0-poiss)/((1.0+poiss)*(1.0-2.0*poiss))
            conss      = const*poiss/(1.0-poiss)
            dmatx(1,1) = const
            dmatx(2,2) = const
            dmatx(3,3) = const*(1.0-2.0*poiss)/(2.0*(1.0-poiss))
            dmatx(1,2) = conss
            dmatx(1,4) = conss
            dmatx(2,1) = conss
            dmatx(2,4) = conss
            dmatx(4,1) = conss
            dmatx(4,2) = conss
            dmatx(4,4) = const
            return

        endif       !!!            end for SPtype operations
    end if      !!!    end for ndimn=2

    !     ------  3D solid

    if  ( ndimn==3) then
        alfa = young*(1-poiss)/((1.+poiss)*(1.-2.*poiss))
        beta = young*poiss/((1.+poiss)*(1.-2.*poiss))
        G    = young/(2.*(1.+poiss))
        dmatx(1,1) = alfa
        dmatx(2,2) = alfa
        dmatx(3,3) = alfa
        dmatx(1,2) = beta
        dmatx(1,3) = beta
        dmatx(2,1) = beta
        dmatx(2,3) = beta
        dmatx(3,1) = beta
        dmatx(3,2) = beta
        dmatx(4,4) = G
        dmatx(5,5) = G
        dmatx(6,6) = G
        return
    endif

    end subroutine ecmat


    subroutine ecmat_lowft (SPtype,sig,ft,dmatx,young,poiss)

    character(10) SPtype
    real(irk)  young,poiss,const,conss,consr
    real(irk)  G,alfa,beta,dmatx(:,:),sig(:),ft(:)


    dmatx=0.0

    if (ndimn==2) then

        if(sig(1)>=ft(1))then
            dmatx(2,2)=young
            dmatx(1,1)=1.e-5*young
            dmatx(3,3)=1.e-5*young
        else
            if  (SPtype=='PS') then
                const=young/(1.0-poiss*poiss)
                dmatx(1,1) = const
                dmatx(2,2) = const
                dmatx(1,2) = const*poiss
                dmatx(2,1) = const*poiss
                dmatx(3,3) = (1.0-poiss)*const/2.0
                return

                !      ------  Plane strain

            else if (SPtype=='PE') then
                const  = young*(1.0-poiss)/((1.0+poiss)*(1.0-2.0*poiss))
                CONSS=CONST*POISS/(1.0-POISS)
                CONSR=CONST*(1.0-2.0*POISS)/(2.0*(1.0-POISS))
                DMATX(1,1)=CONST
                DMATX(2,2)=CONST
                DMATX(3,3)=CONSR
                DMATX(1,2)=CONSS
                DMATX(2,1)=CONSS
                dmatx(4,4)=const
                dmatx(1,4)=conss
                dmatx(2,4)=conss
                dmatx(4,1)=conss
                dmatx(4,2)=conss
                return
            endif

        endif
    end if      !!!    end for ndimn=2

    !     ------  3D solid

    if  ( ndimn==3) then

        if(sig(1)>=ft(1).and.sig(2)>=ft(2))then
            dmatx(3,3)=young
            dmatx(1,1)=1.e-5*young
            dmatx(2,2)=1.e-5*young
            dmatx(4,4)=1.e-5*young
            dmatx(5,5)=1.e-5*young
            dmatx(6,6)=1.e-5*young
        elseif(sig(1)>=ft(1).and.sig(2)<ft(2))then
            const=young/(1.0-poiss*poiss)
            dmatx(6,6)=1.e-5*young
            dmatx(1,1)=1.e-5*young
            dmatx(4,4)=1.e-5*young
            dmatx(2,2) = const
            dmatx(3,3) = const
            dmatx(2,3) = const*poiss
            dmatx(3,2) = const*poiss
            dmatx(5,5) = (1.0-poiss)*const/2.0
        elseif(sig(1)<ft(1).and.sig(2)>=ft(2))then
            const=young/(1.0-poiss*poiss)
            dmatx(1,1) = const
            dmatx(3,3) = const
            dmatx(1,3) = const*poiss
            dmatx(3,1) = const*poiss
            dmatx(6,6) = (1.0-poiss)*const/2.0
            dmatx(5,5)=1.e-5*young
            dmatx(2,2)=1.e-5*young
            dmatx(4,4)=1.e-5*young
        else
            alfa = young*(1-poiss)/((1.+poiss)*(1.-2.*poiss))
            beta = young*poiss/((1.+poiss)*(1.-2.*poiss))
            G    = young/(2.*(1.+poiss))
            dmatx(1,1) = alfa
            dmatx(2,2) = alfa
            dmatx(3,3) = alfa
            dmatx(1,2) = beta
            dmatx(1,3) = beta
            dmatx(2,1) = beta
            dmatx(2,3) = beta
            dmatx(3,1) = beta
            dmatx(3,2) = beta
            dmatx(4,4) = G
            dmatx(5,5) = G
            dmatx(6,6) = G
        endif
    endif

    end subroutine ecmat_lowft

    subroutine dep_concrete_1(rr,matno,yld,dmatx)

    integer(ink) matno,ielem,igaus
    real(irk) nu,beta,coef,yld,dmatx(:,:),rr(:,:)
    real(irk),allocatable::dmatxd(:,:),cmatx(:,:)
    if (yld==0.)return
    if (yld==2.)then
        dmatx=0.01
        return
    endif
    nu      =props(matno)%mechanical%solid%nu
    allocate(dmatxd(3*(ndimn-1),3*(ndimn-1)),  &
        cmatx(3*(ndimn-1),3*(ndimn-1)))
    dmatxd(1:3*(ndimn-1),1:3*(ndimn-1))=dmatx(1:3*(ndimn-1),1:3*(ndimn-1))
    dmatxd(1,:)=0.01
    dmatxd(:,1)=0.01
    beta=(1+nu)/(1-2*nu)
    coef=1.
    if (yld>1.)coef=1.-yld/beta
    dmatxd=coef*dmatxd
    call ecmat_change(dmatxd,cmatx,rr)
    dmatx(1:3*(ndimn-1),1:3*(ndimn-1))=cmatx
    deallocate(dmatxd,cmatx)

    end subroutine dep_concrete_1

    subroutine ecmat_change(dmatxd,cmatx,rr0)
    integer(ink) idimn,jdimn
    real(irk) dmatxd(:,:),cmatx(:,:),rr0(:,:)
    real(irk),allocatable::tt(:,:),tti(:,:),dmatx1(:,:),rr(:,:),dmatx2(:,:),dmatx3(:,:)
    allocate(tt(3*(ndimn-1),3*(ndimn-1)),tti(3*(ndimn-1),3*(ndimn-1)),dmatx2(3*(ndimn-1),3*(ndimn-1)),   &
        dmatx1(3*(ndimn-1),3*(ndimn-1)), dmatx3(3*(ndimn-1),3*(ndimn-1)))


    allocate(rr(ndimn+1,ndimn+1))
    rr(1:ndimn,1:ndimn)=rr0
    rr(1:ndimn,ndimn+1)=rr(1:ndimn,1)
    rr(ndimn+1,1:ndimn)=rr(1,1:ndimn)
    rr(ndimn+1,ndimn+1)=rr(1,1)

    tt=0.0
    tt(1:ndimn,1:ndimn)=rr0**2
    if (ndimn==2) then
        tt(1,3)=rr(1,1)*rr(1,2)
        tt(2,3)=rr(2,1)*rr(2,2)
        tt(3,1)=2*rr(1,1)*rr(2,1)
        tt(3,2)=2*rr(1,2)*rr(2,2)
        tt(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)
    else if(ndimn==3) then
        do idimn=1,ndimn
            do jdimn=1,ndimn
                tt(idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn,jdimn+1)
                tt(3+idimn,jdimn)=2*rr(idimn,jdimn)*rr(idimn+1,jdimn)
                tt(3+idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                    rr(idimn+1,jdimn)*rr(idimn,jdimn+1)

            end do
        end do
    endif
    tti=transpose(tt)
    dmatx2=dmatxd(1:3*(ndimn-1),1:3*(ndimn-1))
    dmatx1=dmatx2.x.tt
    dmatx3 =tti.x.dmatx1
    if(ndimn==2.and.size(cmatx,dim=1)==size(dmatx3,dim=1)+1)then
        cmatx(1:3*(ndimn-1),1:3*(ndimn-1))=dmatx3
        cmatx(4,:)=dmatxd(4,:);cmatx(:,4)=dmatxd(:,4)
    else
        cmatx=dmatx3
    endif

    deallocate(dmatx1,dmatx2,dmatx3,tt,tti,rr)
    end subroutine ecmat_change


    subroutine ecmat_change_local(dmatxd,cmatx,rr0)
    integer(ink) idimn,jdimn
    real(irk) dmatxd(:,:),cmatx(:,:),rr0(:,:)
    real(irk),allocatable::tt(:,:),rr(:,:),dmatx1(:,:),dmatx2(:,:)
    allocate(tt(3*(ndimn-1),3*(ndimn-1)),dmatx1(3*(ndimn-1),3*(ndimn-1)),dmatx2(3*(ndimn-1),3*(ndimn-1)))

    allocate(rr(ndimn+1,ndimn+1))

    rr(1:ndimn,1:ndimn)=rr0
    rr(1:ndimn,ndimn+1)=rr(1:ndimn,1)
    rr(ndimn+1,1:ndimn)=rr(1,1:ndimn)
    rr(ndimn+1,ndimn+1)=rr(1,1)

    tt=0.0
    tt(1:ndimn,1:ndimn)=rr0**2

    if (ndimn==2) then

        tt(1,3)=rr(1,1)*rr(1,2)
        tt(2,3)=rr(2,1)*rr(2,2)
        tt(3,1)=2*rr(1,1)*rr(2,1)
        tt(3,2)=2*rr(1,2)*rr(2,2)
        tt(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)

    else if(ndimn==3) then
        do idimn=1,ndimn
            do jdimn=1,ndimn
                tt(idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn,jdimn+1)
                tt(3+idimn,jdimn)=2*rr(idimn,jdimn)*rr(idimn+1,jdimn)
                tt(3+idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                    rr(idimn+1,jdimn)*rr(idimn,jdimn+1)
            end do
        end do
    endif

    dmatx1=dmatxd(1:3*(ndimn-1),1:3*(ndimn-1))
    dmatx2=dmatx1.x.tt

    if(ndimn==2.and.size(cmatx,dim=1)==size(dmatx2,dim=1)+1)then
        cmatx(1:3*(ndimn-1),1:3*(ndimn-1))=dmatx2
        cmatx(4,:)=dmatxd(4,:);cmatx(:,4)=dmatxd(:,4)
    else
        cmatx=dmatx2
    endif

    deallocate(tt,rr,dmatx1,dmatx2)
    end subroutine ecmat_change_local


    subroutine stres_local_to_global(stres,rr0)
    integer(ink) idimn,jdimn
    real(irk) rr0(:,:),stres(:)
    real(irk),allocatable::tt(:,:),rr(:,:),stres1(:),stres2(:)
    allocate(tt(3*(ndimn-1),3*(ndimn-1)),stres1(3*(ndimn-1)),stres2(3*(ndimn-1)))

    stres1=stres(1:3*(ndimn-1))
    allocate(rr(ndimn+1,ndimn+1))

    rr(1:ndimn,1:ndimn)=rr0
    rr(1:ndimn,ndimn+1)=rr(1:ndimn,1)
    rr(ndimn+1,1:ndimn)=rr(1,1:ndimn)
    rr(ndimn+1,ndimn+1)=rr(1,1)

    tt=0.0
    tt(1:ndimn,1:ndimn)=rr0**2

    if (ndimn==2) then

        tt(1,3)=rr(1,1)*rr(1,2)
        tt(2,3)=rr(2,1)*rr(2,2)
        tt(3,1)=2.*rr(1,1)*rr(2,1)
        tt(3,2)=2.*rr(1,2)*rr(2,2)
        tt(3,3)=rr(1,1)*rr(2,2)+ rr(2,1)*rr(1,2)

    else if(ndimn==3) then
        do idimn=1,ndimn
            do jdimn=1,ndimn
                tt(idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn,jdimn+1)
                tt(3+idimn,jdimn)=2.*rr(idimn,jdimn)*rr(idimn+1,jdimn)
                tt(3+idimn,3+jdimn)=rr(idimn,jdimn)*rr(idimn+1,jdimn+1)+  &
                    rr(idimn+1,jdimn)*rr(idimn,jdimn+1)
            end do
        end do
    endif

    stres2=transpose(tt).x.stres1
    stres(1:3*(ndimn-1))=stres2


    deallocate(tt,rr,stres1,stres2)
    end subroutine stres_local_to_global



    subroutine ecmat_p4 ( t,dmatx,young,poiss)

    !      ------  Obtain the constitutive elastic matrix (Isotropic)

    !-----------------------------------------------------------------------
    real(irk)  young,poiss,const,t,k0

    real(irk)  dmatx(:,:)

    k0=1.2
    dmatx=0.0_irk
    const=young/(1.0-poiss*poiss)
    dmatx(1,1) = const
    dmatx(2,2) = const
    dmatx(1,2) = const*poiss
    dmatx(2,1) = const*poiss
    dmatx(3,3) = (1.0-poiss)*const/2.0
    const=t**2*young/(1.0-poiss*poiss)/12.
    dmatx(4,4) = const
    dmatx(5,5) = const
    dmatx(4,5) = const*poiss
    dmatx(5,4) = const*poiss
    dmatx(6,6) = (1.0-poiss)*const/2.0
    const=young*k0/2./(1.+poiss) !1.2=k is the non-uniform factor
    dmatx(7,7) = const
    dmatx(8,8) = const

    end subroutine ecmat_p4



    subroutine ecmat_thin_film ( t,dmatx,young,poiss)

    !      ------  Obtain the constitutive elastic matrix (Isotropic)

    !-----------------------------------------------------------------------
    real(irk)  young,poiss,const,t

    real(irk)  dmatx(:,:)

    dmatx=0.0_irk
    const=young/(1.0-poiss*poiss)
    dmatx(1,1) = const
    dmatx(2,2) = const
    dmatx(1,2) = const*poiss
    dmatx(2,1) = const*poiss
    dmatx(3,3) = (1.0-poiss)*const/2.0
    end subroutine ecmat_thin_film

    subroutine ecmat_solidf ( SPtype,dmatx,young,poiss)

    !      ------  Obtain the constitutive elastic matrix (Isotropic)

    !-----------------------------------------------------------------------
    character(10) SPtype
    real(irk)  young,poiss,const,conss,consr

    real(irk)  G,alfa,beta,dmatx(:,:)


    dmatx=0.0_irk
    !      ------  1D solid elements

    if  (ndimn==1) then
        dmatx(1,1) = Young
        return
    endif

    if (ndimn==2) then

        !      ------  Plane stress

        if  (SPtype=='PS') then

            stop ' solidf  PS not implemented!!'

            !      ------  Plane strain

        else if (SPtype=='PE') then
            const  = young
            DMATX(1,1)=const
            DMATX(2,2)=const
            DMATX(1,2)=const
            DMATX(2,1)=const
            return

            !      ------  Axisymmetric

        else if (SPtype=='AX') then

            stop ' solidf  AX not implemented!!'


        endif       !!!            end for SPtype operations
    end if      !!!    end for ndimn=2

    !     ------  3D solid

    if  ( ndimn==3) then
        alfa = young
        dmatx(1,1) = alfa
        dmatx(2,2) = alfa
        dmatx(3,3) = alfa
        dmatx(1,2) = alfa
        dmatx(1,3) = alfa
        dmatx(2,1) = alfa
        dmatx(2,3) = alfa
        dmatx(3,1) = alfa
        dmatx(3,2) = alfa
        return
    endif

    end subroutine ecmat_solidf

    subroutine gbmat (SPtype, nnode, bmatx, cartd, gpcod, shape)

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

    end  subroutine gbmat


    subroutine gbmat_p4 (ic,ig,ielem,bmatx, cartd,shape,rotation) !20231007

    !      ------  Obtain B matrix
    integer(ink) inode,lgash,mgash,ngash,ic,ig,ielem,ipoin,i0
    real(irk) bmatx(:,:), cartd(:,:), shape(:),rotation(:,:)
    real(irk),allocatable::rott(:,:),bmatxm(:,:),rotstar(:,:),unitx(:,:)


    allocate(rott(6,6),bmatxm(8,6))
    bmatx=0.
    DO inode=1,4

        rott(1:3,1:3)=rotation; rott(4:6,4:6)=rotation
        if(alfa_p4>0.)then
            ipoin=element(ielem)%field(1)%lnods_f(inode) !20221124
            if(local_p4(ipoin)==1)then  !节点的局部坐标方向与单元的局部坐标方向可能不完全一致，局部坐标求解时，用的是节点的局部坐标
                allocate(rotstar(ndimn,ndimn),unitx(ndimn,ndimn))
                rotstar=prot(:,:,ipoin)
                unitx=matmul(rotation,transpose(rotstar))
                rott(1:3,1:3)=unitx; rott(4:6,4:6)=unitx
                deallocate(rotstar,unitx)
            endif
        endif

        bmatxm=0.
        bmatxm(1,1)=cartd(1,inode)
        bmatxm(2,2)=cartd(2,inode)
        bmatxm(3,1)=cartd(2,inode)
        bmatxm(3,2)=cartd(1,inode)

        bmatxm(4,5)= cartd(1,inode)
        bmatxm(5,4)=-cartd(2,inode)
        bmatxm(6,4)=-cartd(1,inode)
        bmatxm(6,5)= cartd(2,inode)

        if (ic==0.or.ic==1) then
            bmatxm(7,3)= cartd(2,inode)
            bmatxm(7,4)=-shape(inode)
            bmatxm(8,3)= cartd(1,inode)
            bmatxm(8,5)= shape(inode)
        endif

        if (ic==1)then
            bmatxm(7,3)=bmatxm(7,3)-element(ielem)%egaus(1)%bbar(1,(inode-1)*3+1,ig)
            bmatxm(7,4)=bmatxm(7,4)-element(ielem)%egaus(1)%bbar(1,(inode-1)*3+2,ig)
            bmatxm(7,5)=bmatxm(7,5)-element(ielem)%egaus(1)%bbar(1,(inode-1)*3+3,ig)
            bmatxm(8,3)=bmatxm(8,3)-element(ielem)%egaus(1)%bbar(2,(inode-1)*3+1,ig)
            bmatxm(8,4)=bmatxm(8,4)-element(ielem)%egaus(1)%bbar(2,(inode-1)*3+2,ig)
            bmatxm(8,5)=bmatxm(8,5)-element(ielem)%egaus(1)%bbar(2,(inode-1)*3+3,ig)
        endif

        if (ic==2) then
            bmatxm(4:6,3:5)=element(ielem)%egaus(1)%bbar(1:3,(inode-1)*3+1:inode*3,ig)
        endif

        bmatx(1:8,(inode-1)*6+1:(inode-1)*6+6)=bmatxm.x.rott
    enddo

    deallocate(rott,bmatxm)
    end  subroutine gbmat_p4  !20231007


    subroutine gbmat_thin_film (ic,ig,ielem,bmatx, cartd,shape,rotation)  !20231007p4

    !      ------  Obtain B matrix
    integer(ink) inode,lgash,mgash,ngash,ic,ig,ielem,ipoin,i0
    real(irk) bmatx(:,:), cartd(:,:), shape(:),rotation(:,:)
    real(irk),allocatable::rott(:,:),bmatxm(:,:),rotstar(:,:),unitx(:,:)

    allocate(rott(3,3),bmatxm(3,3))

    bmatx=0.
    DO inode=1,4

        rott(1:3,1:3)=rotation
        if(alfa_p4>0)then
            ipoin=element(ielem)%field(1)%lnods_f(inode)
            if(local_p4(ipoin)==1)then
                allocate(rotstar(ndimn,ndimn),unitx(ndimn,ndimn))
                rotstar=prot(:,:,ipoin)
                unitx=matmul(rotation,transpose(rotstar))
                rott(1:3,1:3)=unitx
                deallocate(rotstar,unitx)
            endif
        endif

        bmatxm=0.
        bmatxm(1,1)=cartd(1,inode)
        bmatxm(2,2)=cartd(2,inode)
        bmatxm(3,1)=cartd(2,inode)
        bmatxm(3,2)=cartd(1,inode)


        bmatx(1:3,(inode-1)*3+1:(inode-1)*3+3)=bmatxm.x.rott
    enddo

    deallocate(rott,bmatxm)
    end  subroutine gbmat_thin_film  !20231007

    !!!!!!
    subroutine smat_p4 (e,nu,t,elcod,eldis,rotation,stres)

    !      ------  Obtain B matrix
    integer(ink) inode,i0,j0,jnode,i,j,idofn
    real(irk) a,b,x1,y1,x2,y2,x,y,e,nu,t
    real(irk) rotation(:,:),elcod(:,:),eldis(:),stres(:,:)
    real(irk),allocatable::rott(:,:),ss(:,:,:),sp(:,:,:),sb(:,:,:),eldisc(:),dmat(:,:),pmatx(:,:), &
        bi(:,:)

    !      ------ 1D,  Plane stress, plane strain and axial symmetry

    a=sum((elcod(:,2)-elcod(:,1))**2)
    a=.5*sqrt(a)
    b=sum((elcod(:,4)-elcod(:,1))**2)
    b=.5*sqrt(b)

    allocate(rott(24,24),ss(6,24,4),sp(3,8,4),sb(3,12,4),eldisc(24),dmat(3,3),pmatx(3,8),bi(3,12))
    rott=0.;ss=0.;sp=0.;sb=0.;eldisc=0.
    do inode=1,4
        i0=(inode-1)*6+1
        j0=(inode-1)*6+3
        rott(i0:j0,i0:j0)=rotation; rott((i0+3):(j0+3),(i0+3):(j0+3))=rotation
    end do

    eldisc=rott.x.eldis

    dmat=0.
    dmat(1,1)=1.;dmat(1,2)=nu;dmat(2,1)=nu;dmat(2,2)=1.;dmat(3,3)=.5*(1-nu)
    dmat=dmat*e*t/(1-nu**2)
    x=-a;y=-b
    call get_p_p_st(a,b,x,y,pmatx)
    sp(:,:,1)=dmat.x.pmatx
    x=a;y=-b
    call get_p_p_st(a,b,x,y,pmatx)
    sp(:,:,2)=dmat.x.pmatx
    x=a;y=b
    call get_p_p_st(a,b,x,y,pmatx)
    sp(:,:,3)=dmat.x.pmatx
    x=-a;y=b
    call get_p_p_st(a,b,x,y,pmatx)
    sp(:,:,4)=dmat.x.pmatx

    dmat=0.
    dmat(1,1)=1.;dmat(1,2)=nu;dmat(2,1)=nu;dmat(2,2)=1.;dmat(3,3)=.5*(1-nu)
    dmat=-dmat*e*t**3/12/(1-nu**2)
    x1=2.;x2=0.;y1=2;y2=0.
    call GET_P_B_st(x1,y1,x2,y2,a,b,bi)
    sb(:,:,1)=dmat.x.bi
    x1=0.;x2=2.;y1=2;y2=0.
    call GET_P_B_st(x1,y1,x2,y2,a,b,bi)
    sb(:,:,2)=dmat.x.bi
    x1=0.;x2=2.;y1=0;y2=2.
    call GET_P_B_st(x1,y1,x2,y2,a,b,bi)
    sb(:,:,3)=dmat.x.bi
    x1=2.;x2=0.;y1=0;y2=2.
    call GET_P_B_st(x1,y1,x2,y2,a,b,bi)
    sb(:,:,4)=dmat.x.bi

    ss=0.
    do jnode=1,4
        do i=1,3
            do inode=1,4
                do j=1,2
                    idofn=(inode-1)*6+j
                    ss(i,idofn,jnode)=sp(i,(inode-1)*2+j,jnode)
                end do
            end do
        end do
    end do

    do jnode=1,4
        do i=4,6
            do inode=1,4
                do j=1,3
                    idofn=(inode-1)*6+j+2
                    ss(i,idofn,jnode)=sb(i-3,(inode-1)*3+j,jnode)
                end do
            end do
        end do
    end do

    do inode=1,4
        stres(:,inode)=ss(:,:,inode).x.eldisc(:)
    end do

    deallocate(rott,ss,sp,sb,eldisc,dmat,pmatx,bi)
    end  subroutine smat_p4

    SUBROUTINE GET_P_B_st(x1,y1,x2,y2,a,b,Bmatx)
    real(irk) x1,y1,x2,y2,a,b,bmatx(:,:)

    Bmatx=0.
    Bmatx(1,1)=y1*(-8*x1+4*x2+2*y1+2*y2)/(16*a**2)
    Bmatx(1,3)=y1*(8*x1-4*x2)/(16*a)
    Bmatx(1,4)=y1*(4*x1-8*x2+2*y1+2*y2)/(16*a**2)
    Bmatx(1,6)=y1*(4*x1-8*x2)/(16*a)
    Bmatx(1,7)=y2*(4*x1-8*x2+2*y1+2*y2)/(16*a**2)
    Bmatx(1,9)=y2*(4*x1-8*x2)/(16*a)
    Bmatx(1,10)=y2*(-8*x1+4*x2+2*y1+2*y2)/(16*a**2)
    Bmatx(1,12)=y2*(8*x1-4*x2)/(16*b)
    Bmatx(2,1)=x1*(2*x1+2*x2-8*y1+4*y2)/(16*b**2)
    Bmatx(2,2)=x1*(-8*y1+4*y2)/(16*b)
    Bmatx(2,4)=x2*(2*x1+2*x2-8*y1+4*y2)/(16*b**2)
    Bmatx(2,5)=x2*(-8*y1+4*y2)/(16*b)
    Bmatx(2,7)=x2*(2*x1+2*x2+4*y1-8*y2)/(16*b**2)
    Bmatx(2,8)=x2*(-4*y1+8*y2)/(16*b)
    Bmatx(2,10)=x1*(2*x1+2*x2+4*y1-8*y2)/(16*b**2)
    Bmatx(2,11)=x1*(-4*y1+8*y2)/(16*b)
    Bmatx(3,1)=(3*x1*y1+4*x1*x2+4*y1*y2+x1*y2+x2*y1-x2*y2-2*x1**2-2*y1**2)/(16*a*b)
    Bmatx(3,2)=y1*(-2*y1+4*y2)/(16*a)
    Bmatx(3,3)=x1*(2*x1-4*x2)/(16*b)
    Bmatx(3,4)=(-3*x2*y1-4*x1*x2-4*y1*y2+x1*y2-x1*y1-x2*y2+2*x2**2+2*y1**2)/(16*a*b)
    Bmatx(3,5)=y1*(2*y1-4*y2)/(16*a)
    Bmatx(3,6)=x2*(-4*x1+2*x2)/(16*b)
    Bmatx(3,7)=(3*x2*y2+4*x1*x2+4*y1*y2-x1*y1+x2*y1+x1*y2-2*x2**2-2*y2**2)/(16*a*b)
    Bmatx(3,8)=y2*(-4*y1+2*y2)/(16*a)
    Bmatx(3,9)=x2*(4*x1-2*x2)/(16*b)
    Bmatx(3,10)=(-3*x1*y2-4*x1*x2-4*y1*y2-x1*y1+x2*y1-x2*y2+2*x1**2+2*y2**2)/(16*a*b)
    Bmatx(3,11)=y2*(4*y1-2*y2)/(16*a)
    Bmatx(3,12)=x1*(-2*x1+4*x2)/(16*b)

    END SUBROUTINE GET_P_B_st

    subroutine get_p_p_st(a,b,x,y,pmatx)
    real(irk) a,b,x,y,pmatx(:,:)
    pmatx=0.
    pmatx(1,1)=y-b; pmatx(1,3)=b-y;   pmatx(1,5)=b+y; pmatx(1,7)=-(b+y)
    pmatx(2,2)=x-a; pmatx(2,4)=-(a+x);pmatx(2,6)=a+x; pmatx(2,8)=a-x
    pmatx(3,1)=x-a; pmatx(3,2)=y-b;pmatx(3,3)=-(a+x);pmatx(3,4)=b-y
    pmatx(3,5)=a+x;pmatx(3,6)=b+y;pmatx(3,7)=a-x;pmatx(3,8)=-(b+y)
    pmatx=pmatx/(4*a*b)
    end subroutine get_p_p_st



    !!!!!

    SUBROUTINE INVART (matno,nstre,DEVIA,STEMP,THETA,STEFF,SMEAN,varj2,VARJ3,sint3,rot) !20130510
    !*****************************************************************
    !
    !**** TO CALCULATE THE INVARIES OF STRESS
    !
    !*****************************************************************
    character(20) criteria,material
    integer(ink) i,nstre,matno,idimn
    real   (irk) devia(:),stemp(:),theta,steff,smean,varj3,root3, &
        varj2, sint3,rot(:),rj23
    real   (irk),allocatable:: tensor(:,:)
    optional rot

    material=props(matno)%mechanical%solid%material
    if(material=='CLASSICALEP') then
        criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
        if(criteria=='MCJOINT') then
            allocate(tensor(ndimn,ndimn))
            do idimn=1,ndimn
                tensor(idimn,idimn)=stemp(idimn)
            end do
            if(ndimn==2) then
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
            if(steff.le.1.e-25) then
                steff=1.e-15
            else
                steff=sqrt(steff)
            endif
            deallocate(tensor)
            return
        endif
    endif


    ROOT3=1.73205080757

    if(nstre==1) then                ! for line element
        steff=abs(stemp(1))  !20211108
        return
    endif

    smean=sum(stemp(1:ndimn))
    if(ndimn.eq.2.and.nstre==4)smean=smean+stemp(4)
    SMEAN=smean/3.0_irk
    devia=stemp
    do i=1,ndimn
        DEVIA(i)=STEMP(i)-SMEAN
    end do
    if(ndimn.eq.2.and.nstre==4)DEVIA(4)=DEVIA(4)-smean


    varj2=0.0_irk
    if(ndimn==3)then
        varj2=((stemp(1)-stemp(2))**2+(stemp(2)-stemp(3))**2+(stemp(1)-stemp(3))**2)/6.  &
            +stemp(4)**2+stemp(5)**2+stemp(6)**2
    elseif(ndimn==2)then
        if(nstre==3)then
            varj2=((stemp(1)-stemp(2))**2+stemp(2)**2+stemp(1)**2)/6.+stemp(3)**2
        elseif(nstre==4)then
            varj2=((stemp(1)-stemp(2))**2+(stemp(2)-stemp(4))**2+(stemp(1)-stemp(4))**2)/6.  &
                +stemp(3)**2
        endif
    endif

    if(varj2<1.e-25)varj2=1.e-25   !20230907 特别注意，对应变空间的混凝土损伤模型，varj2设置不太大
    !if(varj2<.001)varj2=.001    !20220721

    varj3=0.0
    if(ndimn.eq.2) then  !!new2005
        !	varj3=(devia(1)**3+devia(2)**3+devia(4)**3)/3.d0+devia(3)**3*(devia(1)+devia(2))
        varj3=devia(1)*devia(2)*devia(4)-devia(4)*devia(3)**2
    else
        varj3=devia(1)*devia(2)*devia(3)+                     &
            2.*devia(4)*devia(5)*devia(6)-                 &
            devia(1)*devia(5)**2         -                 &
            devia(2)*devia(6)**2-devia(3)*devia(4)**2
    end if
    !	  if(varj2.gt.1.e15) stop 'in varj2'

    STEFF=SQRT(VARJ2)
    if(material=='SandPZ'.or.material=='ClayPZ')then
        steff=sqrt(3.*varj2)
        smean=-smean
    endif

    !RJ23=(SQRT(varj2))**3
    !IF(RJ23.GE.1.0D-20) THEN
    !	SINT3=-3.0*SQRT(3.0d0)*varj3/(2.0d0*RJ23)
    !ELSE
    !	SINT3=0.0D0
    !END IF

    IF (VARJ2.EQ.0.0_irk.OR.STEFF.EQ.0.0_irk)then
        SINT3=0.0_irk
    else
        SINT3=-2.5980762113*VARJ3/(VARJ2*STEFF)
    endif

    IF(SINT3.LT.-1.0_irk) SINT3=-1.0_irk
    IF(SINT3.GT. 1.0_irk) SINT3= 1.0_irk
    THETA=ASIN(SINT3)/3.0_irk
    !if((material=='SandPZ'.or.material=='ClayPZ').and.sint3<0.)steff=-steff
    END SUBROUTINE INVART


    SUBROUTINE FLOWFQ(smean,AVECT,DEVIA,THETA,STEFF,AVECQ,NSTRE,     &
        matno,varj3,cons2,cons3,veca2,veca3, Fc, epstn,rot,snorm)
    !*****************************************************************
    !
    ! ***  SELECTS EQSTR FUNCTION AND CALCULATES VECTOR 'AVECT'
    !
    !*****************************************************************
    character(20) criteria,material
    integer(ink) i,i1,i2,matno,nstre, istr1,cfrict,cdilan,cft,csigma0,idimn
    real(irk) smean,theta,steff,veca2(:),veca3(:),rot(:)
    real(irk) varj2,tanth,sinth,costh,cost3,root3,c0,                   &
        cons1,cons10,cons2,cons20,cons3,cons30,                   &
        plumi,tant3,snphi,snphi0,frict,dilan,abthe,cmult,         &
        theta1,cos3th,a0,b0,d0,a,b,c,d,Fc,varj3
    real(irk) ath,ath0,dath,dath0,hards,epstn,ft,snorm,dfact
    real(irk) a1,b1,a2,b2,sigma1,sigma0,a10,coef,sigmat
    real(irk) AVECT(:),DEVIA(:),AVECQ(:)
    real(irk), allocatable::veca1(:)

    if (nstre==1) then
        avect(1)=1.
        avecq(1)=1.
        return
    endif
    material=props(matno)%mechanical%solid%material
    if (material=='CLASSICALEP') then

        criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
        sigma0=props(matno)%mechanical%solid%classicalEP%sigma0

        if (type_load=='MAT_DE')then
            dfact   =tcurves(mat_curve)%dfact
            sigma0  =sigma0*dfact
        endif

        csigma0=props(matno)%mechanical%solid%classicalEP%csigma0
        hards   =props(matno)%mechanical%solid%classicalEP%hardening
        sigma0=sigma0+hards*epstn
        if (csigma0/=0)call parameter_find(csigma0,epstn,sigma0,hards)
        if (sigma0.le.0.)sigma0=1.e-3*props(matno)%mechanical%solid%classicalEP%sigma0

        if (criteria(1:2)=='MC'.or.criteria(1:2)=='DP') then

            frict=props(matno)%mechanical%solid%ClassicalEP%frict_angle
            dilan=props(matno)%mechanical%solid%ClassicalEP%dilan_angle

            if (type_load=='MAT_DE')then
                frict=tand(frict)*dfact
                dilan=tand(dilan)*dfact
                frict=atand(frict)
                dilan=atand(dilan)
            endif


            cfrict=props(matno)%mechanical%solid%classicalEP%cfrict
            if (cfrict/=0)call parameter_find(cfrict,epstn,frict,hards)

            cdilan=props(matno)%mechanical%solid%classicalEP%cdilan
            if (cdilan/=0)call parameter_find(cdilan,epstn,dilan,hards)
            frict=frict*3.14159/180.
            dilan=dilan*3.14159/180.

            if (criteria=='MCC'.or.criteria=='DPC'.or.criteria=='MCJOINT') then
                ft=props(matno)%mechanical%solid%classicalEP%ft
                cft=props(matno)%mechanical%solid%classicalEP%cft
                if (cft/=0)call parameter_find(cft,epstn,ft,hards)
            endif
        endif

        if (criteria=='MCJOINT') then
            sigmat=props(matno)%mechanical%solid%classicalEP%sigmat
            veca2=0.0
            avect=0.
            avecq=0.
            coef=tan(frict)
            !   if(snorm>1.e-5*sigma0)coef=sigmat/ft   !!ooo
            do idimn=1,ndimn
                avect(idimn)=(rot(idimn)*devia(idimn)-smean*rot(idimn)**2)/steff  &
                    +rot(idimn)**2*coef
                !      avect(idimn)=rot(idimn)*devia(idimn)/steff
                veca2(idimn)=(rot(idimn)*devia(idimn)-smean*rot(idimn)**2)/steff
            end do
            if (ndimn==2) then
                avect(3)=(rot(2)*devia(1)+devia(2)*rot(1)-2*smean*rot(1)*rot(2))/steff  &
                    +2*rot(1)*rot(2)*coef
                !      avect(3)=(rot(2)*devia(1)+devia(2)*rot(1))/steff
                veca2(3)=(rot(2)*devia(1)+devia(2)*rot(1)-2*smean*rot(1)*rot(2))/steff
            elseif(ndimn==3) then
                avect(4)=(rot(2)*devia(1)+devia(2)*rot(1)-2*smean*rot(1)*rot(2))/steff  &
                    +2*rot(1)*rot(2)*coef
                avect(5)=(rot(2)*devia(3)+devia(2)*rot(3)-2*smean*rot(2)*rot(3))/steff  &
                    +2*rot(2)*rot(3)*coef
                avect(6)=(rot(3)*devia(1)+devia(3)*rot(1)-2*smean*rot(1)*rot(3))/steff  &
                    +2*rot(1)*rot(3)*coef
                !      avect(4)=(rot(2)*devia(1)+devia(2)*rot(1))/steff
                !      avect(5)=(rot(2)*devia(3)+devia(2)*rot(3))/steff
                !      avect(6)=(rot(3)*devia(1)+devia(3)*rot(1))/steff
                veca2(4)=(rot(2)*devia(1)+devia(2)*rot(1)-2*smean*rot(1)*rot(2))/steff
                veca2(5)=(rot(2)*devia(3)+devia(2)*rot(3)-2*smean*rot(2)*rot(3))/steff
                veca2(6)=(rot(3)*devia(1)+devia(3)*rot(1)-2*smean*rot(1)*rot(3))/steff
            endif

            if (smean>0.or.abs(frict-dilan)<1.e-3) then
                avecq=avect
            else
                coef=tan(dilan)
                do idimn=1,ndimn
                    avecq(idimn)=(rot(idimn)*devia(idimn)-smean*rot(idimn)**2)/steff  &
                        +rot(idimn)**2*coef
                end do
                if (ndimn==2) then
                    avecq(3)=(rot(2)*devia(1)+devia(2)*rot(1)-2*smean*rot(1)*rot(2))/steff  &
                        +2*rot(1)*rot(2)*coef
                elseif(ndimn==3) then
                    avecq(4)=(rot(2)*devia(1)+devia(2)*rot(1)-2*smean*rot(1)*rot(2))/steff  &
                        +2*rot(1)*rot(2)*coef
                    avecq(5)=(rot(2)*devia(3)+devia(2)*rot(3)-2*smean*rot(2)*rot(3))/steff  &
                        +2*rot(2)*rot(3)*coef
                    avecq(6)=(rot(3)*devia(1)+devia(3)*rot(1)-2*smean*rot(1)*rot(3))/steff  &
                        +2*rot(1)*rot(3)*coef
                endif
            endif
            return
        endif
    endif

    allocate(veca1(nstre))
    if (STEFF.EQ.0.0) RETURN
    varj2=steff*steff
    TANTH=TAN(THETA)
    SINTH=SIN(THETA)
    COSTH=COS(THETA)
    COST3=COS(3.0*THETA)
    ROOT3=1.732050807570
    !*** CALCULATE VECTOR A1
    do i=1,nstre
        veca1(i)=0.d0
        if (i.le.ndimn)veca1(i)=1.
    end do
    if (ndimn.eq.2.and.nstre==4)VECA1(4)=1.0
    !*** CALCULATE VECTOR A2
    DO 10 ISTR1=1,nstre
        c0=1.d0
        if (istr1.gt.ndimn) c0=2.d0
        if (ndimn.eq.2.and.istr1.eq.4) c0=1.d0
10  VECA2(ISTR1)=DEVIA(ISTR1)*c0
    !*** CALCULATE VECTOR A3
    if (ndimn.eq.3) then
        do i=1,ndimn
            i1=i+1
            if (i1.gt.ndimn)i1=i1-ndimn
            i2=i+2
            if (i2.gt.ndimn)i2=i2-ndimn
            veca3(i)=devia(i1)*devia(i2)-devia(i1)**2+varj2/3.
            veca3(i+ndimn)=2.*(devia(i2)*devia(i)-devia(i)*devia(i1))
        end do
    else
        VECA3(1)=DEVIA(2)*DEVIA(4)+VARJ2/3.0
        VECA3(2)=DEVIA(1)*DEVIA(4)+VARJ2/3.0
        VECA3(3)=-2.0*DEVIA(3)*DEVIA(4)
        if (nstre==4)VECA3(4)=DEVIA(1)*DEVIA(2)-DEVIA(3)*DEVIA(3)+VARJ2/3.0
    end if

    if (material=='CLASSICALEP') then

        criteria_select : select case(criteria)
        case('TC')
            CONS1=0.0_irk
            ABTHE=ABS(THETA*57.29577951308d0)
            if (ABTHE.LT.29.0_irk) GO TO 20
            CONS2=ROOT3/steff/2
            CONS3=0.0
            GO TO 40
20          CONS2=(COSTH+SINTH*TAN(3.0*THETA))/steff/2
            CONS3=ROOT3*SINTH/(VARJ2*COST3)
            GO TO 40
        case('VM')
            CONS1=0.0_irk
            CONS2=ROOT3/(2*steff)
            CONS3=0.0_irk
            GO TO 40
        case('MC')
            CONS1=SIN(FRICT)/3.0_irk
            CONS10=SIN(DILAN)/3.0_irk
            ABTHE=ABS(THETA*57.29577951308)
            if (ABTHE.LT.29.0_irk) GO TO 30
            CONS3=0.0_irk
            CONS30=0.0_irk
            PLUMI=1.0_irk
            if (THETA.GT.0.0_irk) PLUMI=-1.0_irk
            CONS2=0.5*(ROOT3+PLUMI*CONS1*ROOT3)/(2*steff)
            CONS20=0.5*(ROOT3+PLUMI*CONS10*ROOT3)/(2*steff)
            GO TO 40
30          TANT3=TAN(3.0*THETA)
            ath=costh-sinth*cons1*root3
            dath=-sinth-costh*cons1*root3
            ath0=costh-sinth*cons10*root3
            dath0=-sinth-costh*cons10*root3
            CONS2=(ath-tant3*dath)/(2*steff)
            CONS20=(ath0-tant3*dath0)/(2*steff)
            CONS3=-root3*dath/(2.0*VARJ2*COST3)
            CONS30=-root3*dath0/(2.0*VARJ2*COST3)

            GO TO 40
        case('MCC')
            a0=sigma0*cos(frict)/ft-.5-.5*sin(frict)
            a10=sigma0*cos(dilan)/ft-.5-.5*sin(dilan)
            sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
            if (sigma1<0.) then
                a0=0.
                a10=0.
            endif
            CONS1=(SIN(FRICT)+a0)/3.0_irk
            CONS10=(SIN(DILAN)+a10)/3.0_irk
            ABTHE=ABS(THETA*57.29577951308)
            if (ABTHE.LT.29.0_irk) GO TO 31
            CONS3=0.0_irk
            CONS30=0.0_irk
            PLUMI=1.0_irk
            if (THETA.GT.0.0_irk) PLUMI=-1.0_irk
            CONS2=0.5*(ROOT3+PLUMI*sin(frict)*ROOT3+         &
                2*a0*sin(theta+.6667*3.14159)/root3)/(2*steff)
            CONS20=0.5*(ROOT3+PLUMI*sin(dilan)*ROOT3+         &
                2*a10*sin(theta+.6667*3.14159)/root3)/(2*steff)
            GO TO 40
31          TANT3=TAN(3.0*THETA)
            ath=costh-sinth*cons1*root3+2*a0/root3*sin(theta+.6667*3.14159)
            dath=-sinth-costh*cons1*root3+2*a0/root3*cos(theta+.6667*3.14159)
            ath0=costh-sinth*cons10*root3+2*a10/root3*sin(theta+.6667*3.14159)
            dath0=-sinth-costh*cons10*root3+2*a10/root3*cos(theta+.6667*3.14159)
            CONS2=(ath-tant3*dath)/(2*steff)
            CONS20=(ath0-tant3*dath0)/(2*steff)
            CONS3=-root3*dath/(2.0*VARJ2*COST3)
            CONS30=-root3*dath0/(2.0*VARJ2*COST3)

            GO TO 40
        case('DP')
            SNPHI=SIN(FRICT)
            SNPHI0=SIN(DILAN)
            CONS1=2.0*SNPHI/(ROOT3*(3.0-SNPHI))
            CONS10=2.0*SNPHI0/(ROOT3*(3.0-SNPHI0))
            CONS2=1.0_irk/(2*steff)
            CONS20=1.0_irk/(2*steff)
            CONS3=0.0_irk
            CONS30=0.0_irk
        case('DPC')
            a1=2.0*sin(frict)/(ROOT3*(3.0-sin(frict)))
            b1=6.0*sigma0*COS(FRICT)/(ROOT3*(3.0-sin(frict)))
            a0=b1/ft-a1-1/sqrt(3.)
            a2=2.0*sin(dilan)/(ROOT3*(3.0-sin(dilan)))
            b2=6.0*sigma0*COS(dilan)/(ROOT3*(3.0-sin(dilan)))
            a10=b2/ft-a2-1/sqrt(3.)
            sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
            if (sigma1<0.0) then
                a0=0.
                a10=0.
            endif
            CONS1=a1+a0/3
            CONS10=a2+a0/3
            ABTHE=ABS(THETA*57.29577951308)
            if (ABTHE.LT.29.0_irk) GO TO 41
            CONS3=0.0_irk
            CONS30=0.0_irk
            PLUMI=1.0_irk
            if (THETA.GT.0.0_irk) PLUMI=-1.0_irk
            CONS2=(1+a0*2/root3*sin(theta+.6667*3.14159))/(2*steff)
            CONS20=(1+a10*2/root3*sin(theta+.6667*3.14159))/(2*steff)
            GO TO 40
41          TANT3=TAN(3.0*THETA)
            ath=1+2*a0/root3*sin(theta+.6667*3.14159)
            dath=2*a0/root3*cos(theta+.6667*3.14159)
            ath0=1+2*a10/root3*sin(theta+.6667*3.14159)
            dath0=2*a10/root3*cos(theta+.6667*3.14159)
            CONS2=(ath-tant3*dath)/(2*steff)
            CONS20=(ath0-tant3*dath0)/(2*steff)
            CONS3=-root3*dath/(2.0*VARJ2*COST3)
            CONS30=-root3*dath0/(2.0*VARJ2*COST3)

            GO TO 40

            case default
            print *, 'NO SUCH CRITERIA'
            stop
        end select criteria_select

    else if(material=='CONCRETE') then

        A0=props(matno)%mechanical%solid%Concrete%A
        B0=props(matno)%mechanical%solid%Concrete%B
        C0=props(matno)%mechanical%solid%Concrete%C
        D0=props(matno)%mechanical%solid%Concrete%D
        a=A0/Fc;b=B0;c=2/sqrt(3.)*C0;d=C0/3+D0;   ! Fc will change with the plastic strain

        CONS1=d
        ABTHE=ABS(THETA*57.29577951308)
        if (ABTHE.LT.29.0_irk) GO TO 51
        CONS3=0.0_irk
        if (THETA.GT.0.0_irk) CONS2=a+.5*(b+.5*c)/steff
        if (THETA.lt.0.0_irk) CONS2=a+.5*(b+   c)/steff
        GO TO 40
51      theta1=theta+2*3.14159/3.
        cos3th=sqrt(1.-6.75*varj3**2/varj2**3)
        CONS2=a+.5*b/sqrt(varj2)+.75*sqrt(3.)*C*varj3*cos(theta1)/varj2**2/cos3th    &
            +c*sin(theta1)/2/sqrt(varj2)
        CONS3=-.5*sqrt(3.)*c*cos(theta1)/varj2/cos3th
    endif
40  CMULT=1.0_irk
    DO 50 ISTR1=1,nstre
        AVECT(ISTR1)=CMULT*(CONS1*VECA1(ISTR1)+CONS2*                &
            VECA2(ISTR1)+CONS3*VECA3(ISTR1))
        if (material=='CONCRETE'.or.criteria=='TC'.or.criteria=='VM') &
            AVECQ(ISTR1)=AVECT(ISTR1)
        if (material/='CONCRETE'.and.criteria(1:2)=='MC'.or.criteria(1:2)=='DP')                  &
            AVECQ(ISTR1)=                                  &
            CMULT*(CONS10*VECA1(ISTR1)+CONS20*          &
            VECA2(ISTR1)+CONS30*VECA3(ISTR1))
50  CONTINUE

    deallocate(veca1)

    END SUBROUTINE FLOWFQ
    !  goodman
    !C:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    SUBROUTINE PKPN(matno,EVK,ps,first)
    integer(ink) matno,first
    real   (irk) evk(:),ps(:)
    real   (irk) phi,kzz,kzy,kzx,k1,n,rf,pa,t,tf,stif, &   !,gamaw  20230402
        r(3),cohes,ft, max_tan_stiff
    !write(7,*) 'ps=',ps
    Kzz  =props(matno)%mechanical%solid%Goodman%Kzz
    Kzx  =props(matno)%mechanical%solid%Goodman%Kzx
    if (ndimn==3) &
        Kzy  =props(matno)%mechanical%solid%Goodman%Kzy
    !gamaw=props(matno)%mechanical%solid%Goodman%gamaw  20230402
    pa   =props(matno)%mechanical%solid%Goodman%pa
    K1   =props(matno)%mechanical%solid%Goodman%K1
    Ft    =props(matno)%mechanical%solid%Goodman%Ft

    if (first==1)then
        evk(ndimn)=kzz
        evk(1)=K1*gamaw
        if (ndimn==3)evk(2)=K1*gamaw
        return
    endif
    if (PS(ndimn)>=ft.or.abs(ps(ndimn))<.01)then
        EVK(ndimn)=pa
        EVK(1:ndimn-1)=pa
        GOTO 1
    endif
    n    =props(matno)%mechanical%solid%Goodman%n
    Rf   =props(matno)%mechanical%solid%Goodman%Rf
    phi  =props(matno)%mechanical%solid%Goodman%phi
    cohes=props(matno)%mechanical%solid%Goodman%cohes
    EVK(ndimn)=Kzz

    TF=-ps(ndimn)*tand(phi)+cohes
    R(1:ndimn-1)=1.0-Rf*abs(PS(1:ndimn-1))/TF
    where(r<0.0)r=0.0
    where(r>1.0)r=1.0
    
    max_tan_stiff = evk(1)
    
    EVK(1)=max(Kzx*gamaw*(abs(PS(ndimn))/pa)**n*R(1)**2,max_tan_stiff)
    if(ndimn==3)EVK(2)=max(Kzy*gamaw*(abs(PS(ndimn))/pa)**n*R(2)**2,max_tan_stiff)
1   CONTINUE
    END SUBROUTINE PKPN


    !20231125YL
    SUBROUTINE PKPN_watertight(matno,relat_dis_gaus,EVK) !20231007 止水
    integer(ink) matno,iwj,fill
    real   (irk) evk(:),relat_dis_gaus(:),gdelta
    real   (irk) para_a(17)

    evk=0.
    para_a=props(matno)%mechanical%solid%Goodman%A
    gdelta=relat_dis_gaus(ndimn)
    iwj=props(matno)%mechanical%solid%Goodman%IWJ
    fill=props(matno)%mechanical%solid%Goodman%fill
    if(fill==1.and.gdelta<=0.)then
        evk(ndimn)=para_a(17)
        goto 10
    endif
    if(iwj==1)then
        if(gdelta>=0.)evk(ndimn)=para_a(1)/(1-para_a(2)*gdelta)**2
        if(gdelta<0.) evk(ndimn)=para_a(3)/(1-para_a(4)*abs(gdelta))**2
    elseif(iwj==2)then
        if(gdelta>=0.)then
            if(gdelta<=para_a(14))evk(ndimn)=para_a(5)
            if(gdelta> para_a(14))evk(ndimn)=para_a(6)
        elseif(gdelta<0.)then
            if(abs(gdelta)<=para_a(14))evk(ndimn)=para_a(7)
            if(abs(gdelta)> para_a(14))evk(ndimn)=para_a(8)
        endif
    elseif(iwj==3)then
        if(gdelta>=0.)then
            if(gdelta<=para_a(14))evk(ndimn)=para_a(1)/(1-para_a(2)*gdelta)**2+para_a(5)
            if(gdelta> para_a(14))evk(ndimn)=para_a(1)/(1-para_a(2)*gdelta)**2+para_a(6)
        elseif(gdelta<0.)then
            if(abs(gdelta)<=para_a(14))evk(ndimn)=para_a(3)/(1-para_a(4)*abs(gdelta))**2+para_a(7)
            if(abs(gdelta)> para_a(14))evk(ndimn)=para_a(3)/(1-para_a(4)*abs(gdelta))**2+para_a(8)
        endif
    endif

10  continue
    if(ndimn==3) then
        gdelta=abs(relat_dis_gaus(1))
        if(iwj==1.or.iwj==3)evk(1)=para_a(9)/(1-para_a(10)*gdelta)**2

        gdelta=relat_dis_gaus(2)

        if(iwj==1)then
            if(gdelta>=para_a(15))evk(2)=para_a(11)
            if(gdelta<para_a(15) )evk(2)=para_a(12)
        elseif(iwj==2)then
            evk(2)=para_a(13)
        elseif(iwj==3)then
            if(gdelta>=para_a(15))evk(2)=para_a(11)+para_a(13)
            if(gdelta<para_a(15) )evk(2)=para_a(12)+para_a(13)
        endif
    endif

    if(ndimn==2) then

        gdelta=relat_dis_gaus(1)

        if(iwj==1)then
            if(gdelta>=para_a(15))evk(1)=para_a(11)
            if(gdelta<para_a(15) )evk(1)=para_a(12)
        elseif(iwj==2)then
            evk(1)=para_a(13)
        elseif(iwj==3)then
            if(gdelta>=para_a(15))evk(1)=para_a(11)+para_a(13)
            if(gdelta<para_a(15) )evk(1)=para_a(12)+para_a(13)
        endif
    endif

    evk=evk*para_a(16)

    END SUBROUTINE PKPN_watertight
    !20231125YL

    !!!
    SUBROUTINE KBOLT(matno,EVK,ps)  !20210913
    integer(ink) matno
    real   (irk) evk(:),ps(:)
    real   (irk) kzz,k1
    !write(7,*) 'ps=',ps
    Kzz  =props(matno)%mechanical%solid%Goodman%Kzz
    K1   =props(matno)%mechanical%solid%Goodman%K1
    EVK(ndimn)=Kzz
    if (PS(ndimn)>1.e-2)EVK(ndimn)=K1
    EVK(1:ndimn-1)=K1*1.e-2

    END SUBROUTINE KBOLT !20210913


    !!!!!
    subroutine FCM_KS(matno,ielem,igaus,dstran)
    character(3)  model
    integer(ink) istate0,istate,matno,ielem,igaus,idimn
    real(irk),allocatable:: stran0(:),stran(:),ps(:),ps0(:),evk(:)
    real(irk)  dmage0,dmage,wxd,sigmanc,wx,damage,damage0,ft,dstran(:),kn,ks,w0


    model=props(matno)%mechanical%solid%Goodman%model
    if(model/='FCM') then
        print *, 'MODEL of GOODMAN element is not FCM'
        stop
    end if

    allocate(ps0(ndimn),ps(ndimn),stran0(ndimn),stran(ndimn),evk(ndimn))
    ft=props(matno)%mechanical%solid%Goodman%fcmp%ft

    istate0=element(ielem)%field(1)%gpvar0(ndimn+1,igaus)
    damage0=element(ielem)%field(1)%gpvar0(ndimn+2,igaus)
    damage=element(ielem)%field(1)%gpvar(ndimn+2,igaus)
    wxd    =element(ielem)%field(1)%gpvar0(ndimn+3,igaus)
    ps0    =element(ielem)%field(1)%gpvar0(1:ndimn,igaus)
    if(type_nl==4.or.type_nl==8) &
        ps0    =element(ielem)%field(1)%gpvar(1:ndimn,igaus)
    stran0 =element(ielem)%field(1)%strain0(1:ndimn,igaus)
    if(type_nl==4.or.type_nl==8) &
        stran0 =element(ielem)%field(1)%strain(1:ndimn,igaus)

    evk=    element(ielem)%evk(:,igaus)
    stran=dstran+stran0

    istate=1
    if(stran0(ndimn)>0..and.stran(ndimn)<stran0(ndimn))istate=2  !20211028
    !if(ielem==238) then
    !write(7,*)'ielem=',ielem,'igaus=',igaus,'state0,1=',istate0,istate,'stran=',stran,'evk=',evk
    !write(7,*)'stran0=',stran0,'dstran=',dstran,'stran=',stran
    !write(7,*)'ev=',evk
    !endif
    if(istate==1)then
        if(istate0==1)then
            do idimn=1,ndimn
                ps(idimn)=evk(idimn)*stran(idimn)
            end do
            !if(ielem>=238.and.ielem<=240) &
            !write(7,*)'ps=',ps,'ps0=',ps0
            sigmanc=ps(ndimn)
            !wx=stran(ndimn)-ft/evk(ndimn)
            w0=ft/props(matno)%mechanical%solid%Goodman%fcmp%kns0(ndimn)
            wx=stran(ndimn)-w0
            !if(ielem>=238.and.ielem<=240) &
            ! write(7,*)'ielem=',ielem,'damage=',damage,'sigmanc=',sigmanc,'wx=',wx
            call FCM_damage_and_stres(ielem,igaus,istate0,matno,wx,sigmanc,  &
                damage,damage0,stran(ndimn))
            ps(ndimn)=sigmanc
            !if(ielem>=238.and.ielem<=240) &
            !   write(7,*)'ps=',ps,'damage=',damage


        elseif(istate0==2)then
            wx=stran(ndimn)-ft/evk(ndimn)
            if(wx<wxd)then
                ps=ps0+evk*dstran
                damage=damage0
            else
                call FCM_damage_and_stres(ielem,igaus,istate0,matno,wx,  &
                    sigmanc,damage,damage0,stran(ndimn))
            endif
        endif
    elseif(istate==2)then
        if(istate0==1.and.damage0>1.e-5)wxd=damage0
        ps=ps0+evk*dstran
        damage=damage0
    endif
    damage=(damage+damage0)*.5
    if(damage<0.)damage=0.
    if(damage>0.995)damage=0.995

    ! if(damage>1.e-5)then
    !    kn=sigmanc/wx
    !    if(kn>element(ielem)%evk(  ndimn,igaus)) &
    !    kn=element(ielem)%evk(  ndimn,igaus)
    !    ks=kn*element(ielem)%evk(  1,igaus)   &
    !         /element(ielem)%evk(  ndimn,igaus)
    !    element(ielem)%evk(1:ndimn,igaus)=ks
    !    element(ielem)%evk(  ndimn,igaus)=kn
    !endif
    element(ielem)%evk(:,igaus)=(1-damage)**2*   &
        props(matno)%mechanical%solid%Goodman%fcmp%kns0
    !if(ielem==238)then
    !    write(7,*)'ielem,igaus,istate0,istate,damage,wxd'
    !    write(7,*)ielem,igaus,istate0,istate,damage,wxd
    !endif

    do idimn=1,ndimn  !20211028
        ps(idimn)=element(ielem)%evk(idimn,igaus)*stran(idimn)
    end do !20211028
    !element(ielem)%evk(:,igaus)=(1-damage)*   &
    !              props(matno)%mechanical%solid%Goodman%fcmp%kns0
    element(ielem)%field(1)%gpvar(ndimn+1,igaus)=istate
    element(ielem)%field(1)%gpvar(ndimn+2,igaus)=damage
    element(ielem)%field(1)%gpvar(ndimn+3,igaus)=wxd
    element(ielem)%field(1)%gpvar(1:ndimn,igaus)=ps
    element(ielem)%field(1)%strain(1:ndimn,igaus)=stran

    deallocate(ps0,ps,stran0,stran,evk)

    end subroutine FCM_KS

    subroutine FCM_damage_and_stres(ielem,igaus,istate0,matno,wx,sigmanc,damage,damage0,gap)  !20210125


    integer(ink)  xlwmodel,matno,istate0,ielem,igaus
    real(irk)     wx,w0,w1,w2,ft1,ft,sigmanc,c1,c2,damage,damage0,gap


    if(istate0==1.and.damage<1.e-5.and.(sigmanc<ft.or.wx<0.)) then
        damage=0.
        return
    endif
    c1=1.0;c2=5.64
    xlwmodel=props(matno)%mechanical%solid%Goodman%fcmp%xlwmodel

    w0=props(matno)%mechanical%solid%Goodman%fcmp%w0
    w1=props(matno)%mechanical%solid%Goodman%fcmp%w1
    w2=props(matno)%mechanical%solid%Goodman%fcmp%w2

    ft=props(matno)%mechanical%solid%Goodman%fcmp%ft
    ft1=props(matno)%mechanical%solid%Goodman%fcmp%ft1
    if(xlwmodel==1)then
        if(wx>w0)then
            sigmanc=1.e2
        else
            sigmanc=(1-wx/w0)*ft
        endif
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
            sigmanc=0.01
        endif
    endif
    damage=1-sigmanc/   &
        (gap*props(matno)%mechanical%solid%Goodman%fcmp%kns0(ndimn))

    !write(7,*)'ielem=',ielem,'igaus=',igaus,'wx=',wx,'sigmanc=',sigmanc,'damage=',damage


    end subroutine FCM_damage_and_stres  !20210125


    !!!!!!!!!!!!!!
    SUBROUTINE PKPNs(matno,EVK,ps,first,stran,ps0)
    integer(ink) matno,first,ic
    real   (irk) evk(:),ps(:),stran(:),ps0(:)
    real   (irk) phi,kzz,kzy,kzx,k1,n,rf,pa,t,tf,stif, &   !,gamaw 20230402
        r(3),cohes,ft
    Kzz  =props(matno)%mechanical%solid%Goodman%Kzz
    Kzx  =props(matno)%mechanical%solid%Goodman%Kzx
    if (ndimn==3) &
        Kzy  =props(matno)%mechanical%solid%Goodman%Kzy
    !gamaw=props(matno)%mechanical%solid%Goodman%gamaw  20230402
    pa   =props(matno)%mechanical%solid%Goodman%pa
    K1   =props(matno)%mechanical%solid%Goodman%K1
    n    =props(matno)%mechanical%solid%Goodman%n
    Rf   =props(matno)%mechanical%solid%Goodman%Rf
    phi  =props(matno)%mechanical%solid%Goodman%phi
    cohes=props(matno)%mechanical%solid%Goodman%cohes
    Ft    =props(matno)%mechanical%solid%Goodman%Ft


    if (first==1)then
        evk(ndimn)=kzz
        evk(1)=k1*gamaw
        if (ndimn==3)evk(2)=k1*gamaw
        goto 300
    endif

    if (ps(ndimn)>=ft) then
        EVK(ndimn)=100.
        EVK(1:ndimn-1)=10.
        GOTO 300
    endif

    EVK(ndimn)=Kzz
    if (sum(PS(1:ndimn-1)**2)>.01)then
        T=SQRT((sum(PS(1:ndimn-1)**2)))
    else
        t=0.
    endif
    TF=-ps(ndimn)*tand(phi)+cohes

    R(1:ndimn-1)=1.0-Rf*abs(PS(1:ndimn-1))/TF
    STIF=K1*gamaw
    EVK(1:ndimn-1)=K1*gamaw*(abs(PS(ndimn))/pa)**n*R(1:ndimn-1)**2
300 if(first==1) then
        ps=evk*stran
    else
        ps=ps0+evk*stran
    endif
    !if (ps(ndimn)>=ft) then
    !   ps=ft*.1
    !   ps(ndimn)=ft
    !elseif(t>tf)then
    !   ps(1:ndimn-1)=tf*ps(1:ndimn-1)/t
    !endif

1   CONTINUE
    END SUBROUTINE PKPNs

    SUBROUTINE PKPNs0(matno,EVK,ps,first,stran,ps0)
    integer(ink) matno,first,ic
    real   (irk) evk(:),ps(:),stran(:),ps0(:)
    real   (irk) phi,kzz,kzy,kzx,k1,n,rf,pa,t,tf,stif, &   !,gamaw  20230402
        r(3),cohes,ft
    Kzz  =props(matno)%mechanical%solid%Goodman%Kzz
    Kzx  =props(matno)%mechanical%solid%Goodman%Kzx
    if (ndimn==3) &
        Kzy  =props(matno)%mechanical%solid%Goodman%Kzy
    !gamaw=props(matno)%mechanical%solid%Goodman%gamaw  20230402
    pa   =props(matno)%mechanical%solid%Goodman%pa
    K1   =props(matno)%mechanical%solid%Goodman%K1
    n    =props(matno)%mechanical%solid%Goodman%n
    Rf   =props(matno)%mechanical%solid%Goodman%Rf
    phi  =props(matno)%mechanical%solid%Goodman%phi
    cohes=props(matno)%mechanical%solid%Goodman%cohes
    Ft    =props(matno)%mechanical%solid%Goodman%Ft


    if (first==1)then
        evk(ndimn)=kzz
        evk(1)=k1*gamaw
        if (ndimn==3)evk(2)=k1*gamaw
        goto 300
    endif

    EVK(ndimn)=Kzz
    if (sum(PS(1:ndimn-1)**2)>.01)then
        T=SQRT((sum(PS(1:ndimn-1)**2)))
    else
        t=0.
    endif
    TF=-ps(ndimn)*tand(phi)+cohes
    if (ps(ndimn)>=ft) then
        EVK(ndimn)=100.
        EVK(1:ndimn-1)=10.
        GOTO 300
    endif
200 R(1:ndimn-1)=1.0-Rf*abs(PS(1:ndimn-1))/TF
    STIF=K1*gamaw
    EVK(1:ndimn-1)=K1*gamaw*(abs(PS(ndimn))/pa)**n*R(1:ndimn-1)**2
300 if(first==1) then
        ps=evk*stran
    else
        ps=ps0+evk*stran
    endif
    if (ps(ndimn)>=ft) then
        ps=ft*.1
        ps(ndimn)=ft
    elseif(t>tf)then
        ps(1:ndimn-1)=tf*ps(1:ndimn-1)/t
    endif

1   CONTINUE
    END SUBROUTINE PKPNs0


    SUBROUTINE DUNE0(matno,smean,steff,theta,smax,Qmax,s,e,p3)
    character(2) model
    integer(ink) matno
    real   (irk) smean,steff,theta,smax,Qmax,p, s,e
    real   (irk) root3,cohes,phi,K,n,Rf,Nur,Kur,   &
        snphi,q,qf,Pa,p3,p0
    ROOT3=1.73205080757
    cohes=props(matno)%mechanical%solid%DuncanChang%cohes
    phi  =props(matno)%mechanical%solid%DuncanChang%phi
    K    =props(matno)%mechanical%solid%DuncanChang%K
    n    =props(matno)%mechanical%solid%DuncanChang%n
    Rf   =props(matno)%mechanical%solid%DuncanChang%Rf
    Nur  =props(matno)%mechanical%solid%DuncanChang%Nur
    Kur  =props(matno)%mechanical%solid%DuncanChang%Kur
    Pa   =props(matno)%mechanical%solid%DuncanChang%Pa
    P0   =props(matno)%mechanical%solid%DuncanChang%P0
    model=props(matno)%mechanical%solid%DuncanChang%model

    if (model=='CR') RETURN
    p=-smean
    if (p<.01)p=.01
    p3=p
    if (p.LT.P0) p3=p0
    SNPHI=SIND(phi)
    Q    =steff*(COS(THETA)-SIN(THETA)*SNPHI/ROOT3)
    Qf   =P*SNPHI+COHES*COSD(phi)
    S=Q/QF
    if (S.GT.1.0) S=1.0
    if (S.LE.0.95*Smax.AND.Steff.LE.0.95*Qmax) then
        E=Kur*Pa*(P3/Pa)**Nur
    else
        E=K*Pa*(P3/Pa)**N*(1.0-RF*S)**2
    endif
    END SUBROUTINE
    !

    !!!!
    SUBROUTINE DUNE(matno,smean,steff,theta,smax,Qmax,s,e,p3) !20130510
    character(2) model
    integer(ink) matno
    real   (irk) smean,steff,theta,smax,Qmax, s,e
    real   (irk) root3,cohes,phi,K,n,Rf,Nur,Kur,   &
        snphi,q,qf,Pa,p3,p0,pei,ps(3)
    ROOT3=1.73205080757
    cohes=props(matno)%mechanical%solid%DuncanChang%cohes
    phi  =props(matno)%mechanical%solid%DuncanChang%phi
    K    =props(matno)%mechanical%solid%DuncanChang%K
    n    =props(matno)%mechanical%solid%DuncanChang%n
    Rf   =props(matno)%mechanical%solid%DuncanChang%Rf
    Nur  =props(matno)%mechanical%solid%DuncanChang%Nur
    Kur  =props(matno)%mechanical%solid%DuncanChang%Kur
    Pa   =props(matno)%mechanical%solid%DuncanChang%Pa
    P0   =props(matno)%mechanical%solid%DuncanChang%P0

    model=props(matno)%mechanical%solid%DuncanChang%model

    if (model=='CR') RETURN
    pei   = 3.14159
    ps(3)=-(2.*steff/root3*sin(theta+2*pei/3.)+smean)
    ps(2)=-(2.*steff/root3*sin(theta         )+smean)
    ps(1)=-(2.*steff/root3*sin(theta+4*pei/3.)+smean)

    p3=ps(3)    !20130510
    if (p3.LT.P0) p3=p0  !20130510
    Q    =ps(1)-ps(3)
    Qf   =(2.*p3*sinD(phi)+2.*COHES*COSD(phi))/(1-sind(phi))
    S=Q/QF
    if (S.GT.1.0) S=1.0
    if (S.LE.0.95*Smax.AND.Q.LE.0.95*Qmax) then
        E=Kur*Pa*(P3/Pa)**Nur
    else
        if(Smax<S)Smax=S  !20220409
        if(Qmax<Q)Qmax=Q  !20220409
        E=K*Pa*(P3/Pa)**N*(1.0-RF*S)**2
    endif
    !  write(chkunit,*)'q=',q,'qf=',qf,'s=',s,'ps=',ps
    !     IF(E.LT.100.*pa) E=100.*pa
    END SUBROUTINE
    !
    !CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC-
    !
    SUBROUTINE DUNV(matno,smean,s,VT)
    character(2) model
    integer(ink) matno
    real   (irk) smean,s,vt,Et
    real   (irk) F,G,Vtf,Pa,Vi,p,nu,A
    p=-smean
    F  =props(matno)%mechanical%solid%DuncanChang%F
    G  =props(matno)%mechanical%solid%DuncanChang%G
    Vtf=props(matno)%mechanical%solid%DuncanChang%Vtf
    pa =props(matno)%mechanical%solid%DuncanChang%pa
    nu =props(matno)%mechanical%solid%nu
    model=props(matno)%mechanical%solid%DuncanChang%model
    if (model=='CR') then
        vt=nu
        return
    endif
    if (P.LT.0.01) GOTO 410
    Vi=G-F*LOG10(P/pa)
    VT=Vi+(Vtf-Vi)*S
    if (VT.LT.0.0) VT=0.0
    if (VT.GT.0.45) VT=0.45
    GOTO 411
410 VT=0.3
411 CONTINUE
    END SUBROUTINE DUNV
    !
    !SSSSSCSSSSSCSSSSSCSSSSSCSSSSSCSSSSSCSSSSSCSSSSSCSSSSSCSSSSS
    SUBROUTINE EBMODg(isat,matno,smean,steff,theta,smax,Qmax,s,et,vt,p3)    !20220409
    integer(ink) matno,isat
    real   (irk) smean,steff,theta,smax,Qmax,p,s,et,vt,ps(3)
    real   (irk) root3,cohes,phi,K,n,Rf,Nur,Kur,snphi,q,qf,Pa,Kb,m,dphi,BT,pei,p3,p0

    ROOT3=1.73205080757
    cohes=props(matno)%mechanical%solid%DuncanChang%cohes
    pei   = 3.14159
    ps(3)=-(2.*steff/root3*sin(theta+2*pei/3.)+smean)
    ps(2)=-(2.*steff/root3*sin(theta         )+smean)
    ps(1)=-(2.*steff/root3*sin(theta+4*pei/3.)+smean)

    q=.5*((ps(1)-ps(2))**2+(ps(2)-ps(3))**2+(ps(1)-ps(3))**2)
    Q=sqrt(q)
    theta=(ps(1)-2*ps(2)+ps(3))/(ps(1)-ps(3))
    theta=-theta/sqrt(3.)
    theta=atan(theta)
    if(theta<-pei/3.)theta=-pei/3.
    if(theta> pei/3.)theta= pei/3.
    K    =props(matno)%mechanical%solid%DuncanChang%K
    n    =props(matno)%mechanical%solid%DuncanChang%n
    m    =props(matno)%mechanical%solid%DuncanChang%m
    Rf   =props(matno)%mechanical%solid%DuncanChang%Rf
    Nur  =props(matno)%mechanical%solid%DuncanChang%Nur
    Kur  =props(matno)%mechanical%solid%DuncanChang%Kur
    Pa   =props(matno)%mechanical%solid%DuncanChang%Pa
    P0   =props(matno)%mechanical%solid%DuncanChang%P0
    Kb   =props(matno)%mechanical%solid%DuncanChang%Kb
    phi =props(matno)%mechanical%solid%DuncanChang%phi

    if(isat>0) &
        K    =props(matno)%mechanical%solid%DuncanChang%K_s
    if(isat>0) &
        phi =props(matno)%mechanical%solid%DuncanChang%phi_s

    phi =phi*3.14159/180.
    dphi=props(matno)%mechanical%solid%DuncanChang%dphi
    dphi=dphi*3.14159/180.
    p=-smean
    if (P.LT.0.01) GOTO 410
    PHI=PHI-DPHI*LOG10(Ps(3)/pa)
    SNPHI=SIN(phi)

    Qf=3*p*SNPHI+3*cohes*cos(phi)
    Qf=Qf/(ROOT3*cos(theta)+SNPHI*sin(theta))

    S=Q/QF
    if (S.LE.0.95*Smax.AND.Q.LE.0.95*Qmax) GO TO 181
    if(Smax<S)Smax=S !20220409
    if(Qmax<Q)Qmax=Q !20220409
    ET=K*Pa*(P/Pa)**N*(1.0-RF*S)**2
    GO TO 21
181 ET=Kur*Pa*(P/Pa)**Nur
21  BT=Kb*Pa*(P/Pa)**m
    VT=0.5*BT-ET/6.0  !20220409
    if (VT.LT.0.0) VT=0.0
    if (VT.GT.0.49) VT=0.49
    if (ET.LT.pa) ET=pa
    GOTO  411
410 ET=pa
    VT=0.3
411 CONTINUE

    p3=ps(3)
    if (p3.LT.P0) p3=p0

    END SUBROUTINE EBMODg  !20220409

    SUBROUTINE EBMOD(isat,matno,smean,steff,theta,smax,Qmax,s,et,vt,p3)    !20220409
    integer(ink) matno,isat
    real   (irk) smean,steff,theta,smax,Qmax,p,s,et,vt,ps(3)
    real   (irk) root3,cohes,phi,K,n,Rf,Nur,Kur,snphi,q,qf,Pa,Kb,m,dphi,BT,pei,p3,p0

    ROOT3=1.73205080757
    cohes=props(matno)%mechanical%solid%DuncanChang%cohes
    pei   = 3.14159
    ps(3)=-(2.*steff/root3*sin(theta+2*pei/3.)+smean)
    ps(2)=-(2.*steff/root3*sin(theta         )+smean)
    ps(1)=-(2.*steff/root3*sin(theta+4*pei/3.)+smean)

    !write(7,*)'ps=',ps

    K    =props(matno)%mechanical%solid%DuncanChang%K
    n    =props(matno)%mechanical%solid%DuncanChang%n
    m    =props(matno)%mechanical%solid%DuncanChang%m
    Rf   =props(matno)%mechanical%solid%DuncanChang%Rf
    Nur  =props(matno)%mechanical%solid%DuncanChang%Nur
    Kur  =props(matno)%mechanical%solid%DuncanChang%Kur
    Pa   =props(matno)%mechanical%solid%DuncanChang%Pa
    P0   =props(matno)%mechanical%solid%DuncanChang%P0   !20130510
    Kb   =props(matno)%mechanical%solid%DuncanChang%Kb
    phi =props(matno)%mechanical%solid%DuncanChang%phi
    if(isat>0) &
        K    =props(matno)%mechanical%solid%DuncanChang%K_s
    if(isat>0) &
        phi =props(matno)%mechanical%solid%DuncanChang%phi_s

    !phi =phi*3.14159/180.
    dphi=props(matno)%mechanical%solid%DuncanChang%dphi
    !dphi=dphi*3.14159/180.
    p=-smean
    !write(7,*)'p=',p
    !20231215YL
    p3=ps(3) !20231008
    IF(P3.LT.P0)then
        p3=p0
    endif
    !20231215YL
    !if (P.LT.0.01) GOTO 410
    !PHI=PHI-DPHI*LOG10(Ps(3)/pa)
    PHI=PHI-DPHI*LOG10(p3/pa) !20231215YL
    SNPHI=SINd(phi)
    Q=(ps(1)-ps(3))
    !Qf=2*COHES*COSd(phi)+2*ps(3)*SNPHI
    Qf=2*COHES*COSd(phi)+2*p3*SNPHI !20231215YL
    Qf=Qf/(1-SNPHI)
    S=Q/QF

    IF(S.GT.1.0) S=1.0 !20231215YL
    if (S.LE.0.95*Smax.AND.Q.LE.0.95*Qmax) GO TO 181

    if(type_load/='LOAD2'.or.(type_load=='LOAD2'.and.idiv==2))then !20220607
        if(Smax<S)Smax=S !20220607
        if(Qmax<Q)Qmax=Q !20220607
    end if !20220607
    !ET=K*Pa*(Ps(3)/Pa)**N*(1.0-RF*S)**2
    ET=K*Pa*(p3/Pa)**N*(1.0-RF*S)**2!20231215YL
    GO TO 21
    !    181   ET=Kur*Pa*(Ps(3)/Pa)**Nur
    !21        BT=Kb*Pa*(Ps(3)/Pa)**m
181 ET=Kur*Pa*(p3/Pa)**Nur !20231215YL
21  BT=Kb*Pa*(p3/Pa)**m !20231215YL

    VT=0.5-ET/(6.0*BT)  !20220409
    IF(VT.LT.0.0)  VT=0.0  !20220607
    if (VT.GT.0.49) VT=0.49
411 CONTINUE

    END SUBROUTINE EBMOD !

    !20231215YL
    SUBROUTINE DUNEd(matno,smean,steff,theta,e,v,lamda,stran,ielem,igaus)  !20231008
    character(2) model
    integer(ink) matno,curvG,curvL,curvG2,curvL2,curvG3,curvL3,ielem,igaus
    real   (irk) smean,p,e,v,Kd,nd,Gmoud0,gmoud,h0,Pa, &
        lamda,strain_s,stran(:),ps(3),root3,  &
        cohes,phi,rf,pei,q,qf,s,k,n,steff,theta,p0,p3,  &       !902
        Gmoud2,Gmoud3,lamda2,lamda3,sigmad1,sigmad2,sigmad3,k1,k2,lamdaMax,gamba
    real   (irk),allocatable::stemp(:),stmin(:)
    Pa   =props(matno)%mechanical%solid%DuncanChang%Pa
    e    =props(matno)%mechanical%solid%e   !902
    model=props(matno)%mechanical%solid%DuncanChang%model

    ROOT3=1.73205080757
    cohes=props(matno)%mechanical%solid%DuncanChang%cohes
    phi  =props(matno)%mechanical%solid%DuncanChang%phi
    K    =props(matno)%mechanical%solid%DuncanChang%K
    n    =props(matno)%mechanical%solid%DuncanChang%n
    Rf   =props(matno)%mechanical%solid%DuncanChang%Rf
    P0   =props(matno)%mechanical%solid%DuncanChang%P0

    k1   =props(matno)%mechanical%solid%DuncanChang%k1
    k2   =props(matno)%mechanical%solid%DuncanChang%k2
    nd   =props(matno)%mechanical%solid%DuncanChang%nd
    lamdaMax   =props(matno)%mechanical%solid%DuncanChang%lamdaMax
    pei   = 3.14159
    ps(3)=-(2.*steff/root3*sin(theta+2*pei/3.)+smean)
    ps(2)=-(2.*steff/root3*sin(theta         )+smean)
    ps(1)=-(2.*steff/root3*sin(theta+4*pei/3.)+smean)
    p=ps(3)
    if(p<p0)p=p0
    p3=p

    Q    =ps(1)-ps(3)
    Qf   =(2.*p3*sinD(phi)+2.*COHES*COSD(phi))/(1-sind(phi))
    S=Q/QF
    IF(S.GT.1.0) S=1.0

    allocate(stemp(size(stran)),stmin(ndimn))
    stemp=stran
    stemp(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
    call main_stran_r( stemp, stmin)
    if(ndimn==2)strain_s=abs((stmin(1)-stmin(2)))   !*0.5  !最大剪应变(2D) !zhao
    !if(ndimn==3)strain_s=abs((stmin(1)-stmin(3)))   !*0.5  !最大剪应变(3D)
    if(ndimn==3)strain_s=sqrt(((stmin(1)-stmin(2))**2+(stmin(2)-stmin(3))**2+(stmin(3)-stmin(1))**2)*2)/3 !最大动剪应变 yuanli
    if(gamamax/=0)strain_s=element(ielem)%field(1)%gamamax_ini(igaus)
    strain_s=strain_s*100 !yuanli
    gamba=0.65*strain_s*(p/pa)**(nd-1)
    lamda=k1*gamba*lamdaMax/(1+k1*gamba)     !等效粘弹性模型 20190225
    p=-smean
    if(p<p0)p=p0     !psy  2019.04.26
    Gmoud=k2/(1+k1*gamba)*Pa*(P/Pa)**Nd     !等效粘弹性模型 应该用归一化剪应变gamaba 已修正
    e=Gmoud*2*(1.+v)
    END SUBROUTINE
    !20231215YL
    SUBROUTINE dadsig(smean,DI,THETA,STEFF,NSTRE, matno, varj3,           &
        veca2,veca3,Fc, cons2,cons3, dasig,          &
        epstn,rot)
    !*****************************************************************
    !
    ! ***  SELECTS EQSTR FUNCTION AND CALCULATES VECTOR 'AVECT'
    !
    !*****************************************************************
    character(20) criteria,material
    integer(ink) matno,nstre, istr1,cfrict,cft,csigma0
    real(irk) theta,steff,a0,b0,c0,d0,fc,varj3,epstn,hards,smean
    real(irk) varj2,cost3,root3,a,b,c,d,cons1,cons4,                     &
        cons2,cons3,cons22,cons33,cons23,cons32,                   &
        plumi,tant3,frict,abthe,ath,dath,ddath,theta1,cos3th
    real(irk) a1,b1,sigma0,sigma1,ft,rot(:)
    real(irk) DI(:),veca2(:),veca3(:),dasig(:,:)
    real(irk), allocatable::da2(:,:),da3(:,:),da22(:,:),da23(:,:),da32(:,:),da33(:,:)
    real(irk),allocatable::dxn(:),dyn(:),dzn(:),dnn(:),dxn2(:,:),dyn2(:,:),dzn2(:,:),dnn2(:,:)

    if (nstre==1) then
        dasig=0.0
        return
    endif
    material=props(matno)%mechanical%solid%material
    if (material=='CLASSICALEP') then

        criteria=props(matno)%mechanical%solid%ClassicalEP%criteria
        sigma0=props(matno)%mechanical%solid%classicalEP%sigma0
        csigma0=props(matno)%mechanical%solid%classicalEP%csigma0
        hards   =props(matno)%mechanical%solid%classicalEP%hardening
        sigma0=sigma0+hards*epstn
        if (csigma0/=0)call parameter_find(csigma0,epstn,sigma0,hards)
        if (sigma0.le.0.)sigma0=1.e-3*props(matno)%mechanical%solid%classicalEP%sigma0
        if (criteria(1:2)=='MC'.or.criteria(1:2)=='DP') then
            frict=props(matno)%mechanical%solid%classicalEP%frict_angle
            cfrict=props(matno)%mechanical%solid%classicalEP%cfrict
            !      frict=props(matno)%mechanical%solid%classicalEP%dilan_angle
            !    cfrict=props(matno)%mechanical%solid%classicalEP%cdilan
            if (cfrict/=0)call parameter_find(cfrict,epstn,frict,hards)
            frict=3.14159/180.*frict
            if (criteria=='MCC'.or.criteria=='DPC'.or.criteria=='MCJOINT') then
                ft=props(matno)%mechanical%solid%classicalEP%ft
                cft=props(matno)%mechanical%solid%classicalEP%cft
                if (cft/=0)call parameter_find(cft,epstn,ft,hards)
            endif

            if (criteria=='MCJOINT')then

                allocate(dxn(nstre),dyn(nstre),dnn(nstre),dzn(nstre),dxn2(nstre,nstre),   &
                    dyn2(nstre,nstre),dnn2(nstre,nstre),da2(nstre,nstre),dzn2(nstre,nstre))
                dxn=0.;dyn=0.;dzn=0.;dnn=0.;dxn2=0.;dyn2=0.;dnn2=0.;da2=0.;dzn2=0.
                if (ndimn==2) then
                    dxn(1)=rot(1) ;dxn(3)=rot(2)
                    dyn(3)=rot(1);dyn(2)=rot(2)
                    dnn(1:ndimn)=rot(1:ndimn)**2  ;dnn(3)=2*rot(1)*rot(2)
                else if(ndimn==3) then
                    dxn(1)=rot(1);dxn(4)=rot(2);dxn(6)=rot(3)
                    dyn(4)=rot(1);dyn(2)=rot(2);dyn(5)=rot(3)
                    dyn(5)=rot(2);dyn(6)=rot(1);dyn(3)=rot(3)
                    dnn(1:ndimn)=rot(1:ndimn)**2  ;dnn(4)=2*rot(1)*rot(2); dnn(5)=2*rot(2)*rot(3);dnn(6)=2*rot(1)*rot(3)
                endif
                dasig=0.0
                dxn2=dxn.o.dxn
                dyn2=dyn.o.dyn
                if (ndimn==3)dzn2=dzn.o.dzn
                dnn2=dnn.o.dnn
                da2 =veca2.o.veca2
                dasig=dxn2+dyn2-dnn2
                if (ndimn==3)dasig=dasig+dzn2
                dasig=dasig-da2
                dasig=dasig/steff
                deallocate(dxn,dyn,dzn,dnn,dxn2,dyn2,dzn2,dnn2,da2)
                return
            endif

        endif
    endif
    allocate(da2(nstre,nstre), da3(nstre,nstre), da22(nstre,nstre), da23(nstre,nstre), &
        da32(nstre,nstre),da33(nstre,nstre))
    if (STEFF.EQ.0.0) RETURN
    ROOT3=1.732050807570
    varj2=steff*steff
    !*** CALCULATE matrix d(A2)
    da2=0.0
    da2(1:ndimn,1:ndimn)=-1.
    DO 10 ISTR1=1,ndimn
10  dA2(ISTR1,istr1)=2.
    DO 11 ISTR1=ndimn+1,3*(ndimn-1)
11  dA2(ISTR1,istr1)=6.
    if (ndimn==2.and.nstre==4) then
        da2(4,4)=2.
        da2(1:2,4)=-1.
        da2(4,1:2)=-1.
    endif
    da2=da2/3.
    !*** CALCULATE matrix d(A3)

    if (ndimn.eq.3) then
        !!!
        da3(1,1)=di(1);
        da3(2,1)=di(3); da3(2,2)=di(2);
        da3(3,1)=di(2); da3(3,2)=di(1); da3(3,3)=di(3);

        da3(4,4)=-3.*di(3);
        da3(5,4)= 3.*di(6); da3(5,5)=-3.*di(1);
        da3(6,4)= 3.*di(5); da3(6,5)= 3.*di(4); da3(6,6)=-3.*di(2);

        da3(4,1)=    di(4); da3(4,2)=    di(4); da3(4,3)=-2.*di(4);
        da3(5,1)=-2.*di(5); da3(5,2)=    di(5); da3(5,3)=di(5);
        da3(6,1)=    di(6); da3(6,2)=-2.*di(6); da3(6,3)=di(6);
        !!!
        do istr1=1,6
            da3(istr1,istr1+1:6)=da3(istr1+1:6,istr1)
        end do
        da3=da3*2./3.

    else
        !!!
        da3(1,1)=di(1);
        da3(2,1)=di(4); da3(2,2)=di(2);
        da3(4,1)=di(2); da3(4,2)=di(1); da3(4,4)=di(4);da3(4,3)=-2.*di(3);
        da3(3,1)=di(3); da3(3,2)=di(3); da3(3,3)=-3.*di(4);
        !!!
        do istr1=1,4
            da3(istr1,istr1+1:4)=da3(istr1+1:4,istr1)
        end do
        da3=da3*2./3.
    end if

    if (material=='CLASSICALEP') then

        criteria_select : select case(criteria)
        case('VM')
            cons23=0.;cons33=0.0;cons32=0.0;
            CONS22=-.25*ROOT3/(steff*varj2)
            GO TO 40
        case('MC')
            CONS1=SIN(FRICT)/3.0_irk
            ABTHE=ABS(THETA*57.29577951308)
            if (ABTHE.LT.29.0_irk) GO TO 30
            cons23=0.;cons33=0.0;cons32=0.0;
            PLUMI=1.0_irk
            if (THETA.GT.0.0_irk) PLUMI=-1.0_irk
            CONS22=-0.25*(ROOT3+PLUMI*CONS1*ROOT3)/(2*steff*varj2)
            GO TO 40
30          TANT3=TAN(3.0*THETA)
            COST3=COS(3.0*THETA)
            Ath  =cos(theta)-sin(theta)*cons1*root3
            dath =-sin(theta)-cos(theta)*cons1*root3
            ddath=-cos(theta)+sin(theta)*cons1*root3
            cons4=ddath+3*tant3*dath

            cons23=(.5*tant3*cons4+dath)*root3/(2*varj2**2*cost3)
            cons32=cons23
            cons22=-(ath-tant3**2*cons4-3*tant3*dath)/(4*varj2**1.5)
            cons33=3*cons4/(4*varj2**2.5*cost3**2)
            GO TO 40
        case('MCC')
            a0=sigma0*cos(frict)/ft-.5-.5*sin(frict)
            sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
            if (sigma1<0.) a0=0.
            CONS1=SIN(FRICT)/3.0_irk
            ABTHE=ABS(THETA*57.29577951308)
            if (ABTHE.LT.29.0_irk) GO TO 41
            cons23=0.;cons33=0.0;cons32=0.0;
            PLUMI=1.0_irk
            if (THETA.GT.0.0_irk) PLUMI=-1.0_irk
            CONS22=-0.25*((1+PLUMI*CONS1)*root3+2*a0*sin(theta+.6667*3.14159)/root3)  &
                /(2*steff*varj2)
            GO TO 40
41          TANT3=TAN(3.0*THETA)
            COST3=COS(3.0*THETA)
            Ath  =cos(theta)-sin(theta)*cons1*root3+2*a0*sin(theta+.6667*3.14159)
            dath =-sin(theta)-cos(theta)*cons1*root3+2*a0*cos(theta+.6667*3.14159)
            ddath=-cos(theta)+sin(theta)*cons1*root3-2*a0*sin(theta+.6667*3.14159)
            cons4=ddath+3*tant3*dath

            cons23=(.5*tant3*cons4+dath)*root3/(2*varj2**2*cost3)
            cons32=cons23
            cons22=-(ath-tant3**2*cons4-3*tant3*dath)/(4*varj2**1.5)
            cons33=3*cons4/(4*varj2**2.5*cost3**2)
            GO TO 40

        case('DP')
            cons23=0.;cons33=0.0;cons32=0.0;
            CONS22=-.25/(steff*varj2)
        case('DPC')
            a1=2.0*sin(frict)/(ROOT3*(3.0-sin(frict)))
            b1=6.0*sigma0*COS(FRICT)/(ROOT3*(3.0-sin(frict)))
            a0=b1/ft-a1-1/sqrt(3.)
            sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
            if (sigma1<0.) a0=0.
            CONS1=SIN(FRICT)/3.0_irk
            ABTHE=ABS(THETA*57.29577951308)
            if (ABTHE.LT.29.0_irk) GO TO 51
            cons23=0.;cons33=0.0;cons32=0.0;
            PLUMI=1.0_irk
            if (THETA.GT.0.0_irk) PLUMI=-1.0_irk
            CONS22=-0.25*(1+2*a0/root3*sin(theta+.6667*3.14159))/(2*steff*varj2)
            GO TO 40
51          TANT3=TAN(3.0*THETA)
            COST3=COS(3.0*THETA)
            ath=1+2*a0/root3*sin(theta+.6667*3.14159)
            dath=2*a0/root3*cos(theta+.6667*3.14159)
            ddath=-2*a0*sin(theta+.6667*3.14159)
            cons4=ddath+3*tant3*dath

            cons23=(.5*tant3*cons4+dath)*root3/(2*varj2**2*cost3)
            cons32=cons23
            cons22=-(ath-tant3**2*cons4-3*tant3*dath)/(4*varj2**1.5)
            cons33=3*cons4/(4*varj2**2.5*cost3**2)
            GO TO 40
            case default
            print *, 'NO SUCH CRITERIA'
            stop
        end select criteria_select

    else if(material=='CONCRETE') then

        A0=props(matno)%mechanical%solid%Concrete%A
        B0=props(matno)%mechanical%solid%Concrete%B
        C0=props(matno)%mechanical%solid%Concrete%C
        D0=props(matno)%mechanical%solid%Concrete%D
        a=A0/Fc;b=B0;c=2/sqrt(3.)*C0;d=C0/3+D0;   ! Fc will change with the plastic strain

        ABTHE=ABS(THETA*57.29577951308)
        if (ABTHE.LT.29.0_irk) GO TO 31
        cons23=0.;cons33=0.0;cons32=0.0;
        if (THETA.GT.0.0_irk) CONS22=-.25*(b+.5*c)/(varj2*steff)
        if (THETA.lt.0.0_irk) CONS22=-.25*(b+   c)/(varj2*steff)
        GO TO 40
31      theta1=theta+2*3.14159/3.
        cos3th=sqrt(1.-6.75*varj3**2/varj2**3)

        CONS22=-b/(4*varj2**1.5)-7.59375*root3*c*varj3**3*cos(theta1)/              &
            (varj2**6*cos3th**3)                                  &
            -1.125*root3*c*varj3*cos(theta1)/(varj2**3*cos3th)                   &
            -c*sin(theta1)/(4*varj2**1.5)-                                       &
            1.6875*c*varj3**2*sin(theta1)/(varj2**4.5*cos3th**2)

        CONS23=5.0625*root3*c*varj3**2*cos(theta1)/(varj2**5*cos3th**3)             &
            +.5*root3*c*cos(theta1)/(varj2**2*cos3th)                            &
            +1.125*c*varj3*sin(theta1)/(varj2**3.5*cos3th**2)
        cons32=cons23

        CONS33=-3.375*root3*c*varj3*cos(theta1)/(varj2**4*cos3th**3)                &
            -.75*c*sin(theta1)/(varj2**2.5*cos3th**2)
    endif
40  continue
    da22=veca2.o.veca2
    da23=veca2.o.veca3
    da32=veca3.o.veca2
    da33=veca3.o.veca3
    dasig=cons2*da2+cons3*da3+cons22*da22+cons23*da23+cons32*da32+cons33*da33
    deallocate(da2,da3,da22,da33,da23,da32)

    END SUBROUTINE dadsig


    SUBROUTINE FLOWPL (SPtype, ABETA ,AVECT ,DVECT ,AVECQ ,    &
        DVECQ, NSTRE ,matno, hards)
    !********************************************************************
    !
    ! *** CALCULATES VECTOR (DVECT),(DVECQ) AND (ABETA)
    !
    !********************************************************************
    character(10) SPtype
    integer(ink) istr1,matno,i,nstre
    real(irk) young,poiss,hards
    real(irk) fmul1,g,g2,fmul3,fmul2,alfa,beta,ameant,ameanq,denom,abeta
    real(irk) AVECT(:) ,DVECT(:) ,AVECQ(:) ,DVECQ(:)

    if(Bparameter/=0.and.props(matno)%mechanical%solid%ie/=0)then !20190810
        young=xvalue(props(matno)%mechanical%solid%ie)
    else
        young=props(matno)%mechanical%solid%e !exx !
    endif
    if(Bparameter/=0.and.props(matno)%mechanical%solid%iNu/=0)then
        poiss=xvalue(props(matno)%mechanical%solid%iNu)
    else
        poiss=props(matno)%mechanical%solid%Nu !uxx !
    endif
    !young=props(matno)%mechanical%solid%e
    !poiss=props(matno)%mechanical%solid%nu

    if (nstre==1) then
        dvect(1)=young
        dvecq(1)=young
        goto 100
    endif

    fmul1 = young/(1.0+poiss)
    G     = fmul1/2.
    G2    = fmul1

    if (ndimn==2) then
        !      ------  Plane stress problems
        if  (SPtype=='PS') then
            fmul3   = young*poiss*(avect(1)+avect(2))/(1.0-poiss*poiss)
            dvect(1)= fmul1*avect(1)+fmul3
            dvect(2)= fmul1*avect(2) + fmul3
            dvect(3)= 0.5*avect(3)*young/(1.0+poiss)
            if (nstre==4)dvect(4)= fmul1*avect(4)+fmul3
            fmul3   = young*poiss*(avecq(1)+avecq(2))/(1.0-poiss*poiss)
            dvecq(1)= fmul1*avecq(1)+fmul3
            dvecq(2)= fmul1*avecq(2) + fmul3
            dvecq(3)= 0.5*avecq(3)*young/(1.0+poiss)
            if (nstre==4)dvecq(4)= fmul1*avecq(4)+fmul3
        else if (SPtype=='PE') then
            !      ------  Plane strain problems

            fmul2 = young*poiss*(avect(1)+avect(2)+avect(4))/                &
                ( (1.0+poiss) * (1.0-2.0*poiss) )
            dvect(1) = fmul1*avect(1) + fmul2
            dvect(2) = fmul1*avect(2) + fmul2
            dvect(3) = 0.5*avect(3)*young/(1.0+poiss)
            if (nstre==4)dvect(4) = fmul1*avect(4) + fmul2
            fmul2 = young*poiss*(avecq(1)+avecq(2)+avecq(4))/                &
                ( (1.0+poiss) * (1.0-2.0*poiss) )
            dvecq(1) = fmul1*avecq(1) + fmul2
            dvecq(2) = fmul1*avecq(2) + fmul2
            dvecq(3) = 0.5*avecq(3)*young/(1.0+poiss)
            if (nstre==4)dvecq(4) = fmul1*avecq(4) + fmul2
        end if

        !      ------  3D problems

    ELSE IF (ndimn.eq.3) then
        alfa = young*(1.-poiss)/((1.+poiss)*(1.-2.*poiss))
        beta = young*poiss/((1.+poiss)*(1.-2.*poiss))
        G    = young/(2.+2.*poiss)
        ameant= ( avect(1) + avect(2) + avect(3) )*beta
        ameanq= ( avecq(1) + avecq(2) + avecq(3) )*beta
        do i=1,3
            dvect(i)= ameant + (alfa-beta)*avect(i)
            dvect(i+3)= G*avect(i+3)
            dvecq(i)= ameanq + (alfa-beta)*avecq(i)
            dvecq(i+3)= G*avecq(i+3)
        end do
    ENDIF

100 denom=hards
    DO istr1=1,nstre
        denom=denom+avect(istr1)*dvecq(istr1)
    enddo
    abeta=1.0/denom
    end SUBROUTINE FLOWPL
    !
    SUBROUTINE YIELDS (THETA,SMEAN,STEFF,EQSTR,EPSTN,YVALU,matno,snorm)
    !*****************************************************************
    !
    !**** CALCULATES THE VALUE OF EQSTR AND YVALU
    !
    !*****************************************************************
    character(20) criteria,material
    integer(ink) matno,csigma0,cfrict,cdilan,cft
    real   (irk) theta, smean, steff, eqstr, epstn, yvalu,dfact
    real   (irk) root3, uniax, hards, frict, dilan, snphi, cohes
    real   (irk) a,b,c,d,Gf,Ct,h,sigma1,Ft,Fc,a0,sigmat,snorm
    !
    ROOT3=1.73205080757
    material=props(matno)%mechanical%solid%material

    if (material=='CLASSICALEP') then
        criteria=props(matno)%mechanical%solid%classicalEP%criteria
        uniax   =props(matno)%mechanical%solid%classicalEP%sigma0
        hards   =props(matno)%mechanical%solid%classicalEP%hardening

        if (type_load=='MAT_DE')then
            dfact   =tcurves(mat_curve)%dfact
            uniax   =uniax*dfact
        endif

        csigma0=props(matno)%mechanical%solid%classicalEP%csigma0
        if (csigma0/=0)call parameter_find(csigma0,epstn,uniax,hards)

        if (criteria(1:2)=='MC'.or.criteria(1:2)=='DP') then
            frict=props(matno)%mechanical%solid%classicalEP%frict_angle
            dilan=props(matno)%mechanical%solid%classicalEP%dilan_angle

            if (type_load=='MAT_DE')then
                frict=tand(frict)*dfact
                dilan=tand(dilan)*dfact
                frict=atand(frict)
                dilan=atand(dilan)
            endif



            cfrict=props(matno)%mechanical%solid%classicalEP%cfrict
            if (cfrict/=0)call parameter_find(cfrict,epstn,frict,hards)

            cdilan=props(matno)%mechanical%solid%classicalEP%cdilan
            if (cdilan/=0)call parameter_find(cdilan,epstn,dilan,hards)

            frict=frict*3.14159/180.
            dilan=dilan*3.14159/180.

            if (criteria=='MCC'.or.criteria=='DPC'.or.criteria=='MCJOINT') then
                ft=props(matno)%mechanical%solid%classicalEP%ft
                cft=props(matno)%mechanical%solid%classicalEP%cft
                if (cft/=0)call parameter_find(cft,epstn,ft,hards)
                if (criteria=='MCJOINT')sigmat=props(matno)%mechanical%solid%classicalEP%sigmat
            endif
        endif

        criteria_select : select case(criteria)
        case('TC')
            EQSTR=2.0*COS(THETA)*STEFF
            yvalu=uniax
            if (csigma0==0)YVALU=UNIAX+EPSTN*HARDS
            if (yvalu.le.0.)yvalu=uniax*1.e-3
        case('VM')
            EQSTR=ROOT3*STEFF
            yvalu=uniax
            if (csigma0==0)YVALU=UNIAX+EPSTN*HARDS
            if (yvalu.le.0.)yvalu=uniax*1.e-3
        case('MC')
            SNPHI=SIN(FRICT)
            EQSTR=SMEAN*SNPHI+STEFF*(COS(THETA)-SIN(THETA)*SNPHI/ROOT3)
            cohes=uniax
            if (csigma0==0)COHES=UNIAX+EPSTN*HARDS
            if (cohes.le.0.)cohes=1.e-3*uniax
            YVALU=COHES*COS(FRICT)
        case('MCC')
            SNPHI=SIN(FRICT)
            cohes=uniax
            if (csigma0==0)COHES=UNIAX+EPSTN*HARDS
            if (cohes.le.0.)cohes=1.e-3*uniax
            a0=cohes*cos(frict)/ft-.5-.5*snphi
            sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
            if (sigma1<0.)a0=0.
            EQSTR=SMEAN*SNPHI+STEFF*(COS(THETA)-SIN(THETA)*SNPHI/ROOT3)+a0*sigma1
            YVALU=COHES*COS(FRICT)
        case('MCJOINT')
            cohes=uniax
            if (csigma0==0)COHES=UNIAX+EPSTN*HARDS
            if (cohes.le.0.)cohes=1.e-3*uniax
            !    if(snorm<=1.e-5*cohes)then  !!ooo
            EQSTR=STEFF+tan(frict)*smean
            !    else                     !!ooo
            !    cohes=sigmat             !!ooo
            !    eqstr=steff+sigmat/ft*smean !!ooo
            !    endif                    !!ooo
            YVALU=COHES
        case('DP')
            SNPHI=SIN(FRICT)
            EQSTR=6.0*SMEAN*SNPHI/(ROOT3*(3.0-SNPHI))+STEFF
            cohes=uniax
            if (csigma0==0)COHES=UNIAX+EPSTN*HARDS
            if (cohes.le.0.)cohes=1.e-3*uniax
            YVALU=6.0*COHES*COS(FRICT)/(ROOT3*(3.0-SNPHI))
        case('DPC')
            SNPHI=SIN(FRICT)
            cohes=uniax
            if (csigma0==0)COHES=UNIAX+EPSTN*HARDS
            if (cohes.le.0.)cohes=1.e-3*uniax
            a=2.0*SNPHI/(ROOT3*(3.0-SNPHI))
            YVALU=6.0*COHES*COS(FRICT)/(ROOT3*(3.0-SNPHI))
            sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
            a0=yvalu/ft-a-1/sqrt(3.)
            if (sigma1<0.) a0=0.
            eqstr=a*3*smean+STEFF+a0*sigma1
        end select     criteria_select

    else if(material=='CONCRETE') then

        A=props(matno)%mechanical%solid%Concrete%A
        B=props(matno)%mechanical%solid%Concrete%B
        C=props(matno)%mechanical%solid%Concrete%C
        D=props(matno)%mechanical%solid%Concrete%D
        Fc=props(matno)%mechanical%solid%Concrete%Fc
        Gf=props(matno)%mechanical%solid%Concrete%Gf
        H =props(matno)%mechanical%solid%Concrete%h
        Ct =props(matno)%mechanical%solid%Concrete%Ct
        Ft=Ct*Fc
        Ft=Ft*exp(-Ft*h*epstn/Gf)
        yvalu=Ft/Ct
        sigma1=2*steff/sqrt(3.)*sin(theta+2.*3.14159/3.)+smean
        eqstr=a*steff**2/yvalu+b*steff+c*sigma1+3.*d*smean
    endif
    END SUBROUTINE YIELDS
    !

    subroutine calcf(f,dsig,p,ep,effst,d)

    real (irk) eps,f, dsig(:), p, ep, effst, d(:),sn,tt

    eps=1.e-10
    tt = .816496580927726_irk      !sqrt(2/3)
    sn = tnorm(dsig)
    !
    !      compute the yield state
    !
    if  (ep<eps) then
        f  = sn/tt - (d(4) - d(8)*p)
        if  (f<=0.0) then
            !                    effst = sn + tt*d(8)*p
            effst = sn/tt + d(8)*p
        else
            !                    effst = tt*d(4)
            effst =    d(4)
        endif
    else
        effst = d(4) + d(6)*ep/tt
        !               f  = sn -  effst   + tt*d(8)*p
        f  = sn/tt -  (effst   - d(8)*p)
    endif

    end subroutine calcf

    subroutine calca(a,dsig,d)

    real (irk) a(:),dsig(:),d(:),sn,tt

    tt = .816496580927726_irk
    sn = tnorm(dsig)
    !
    !     compute vector normal to yield surface
    !
    a = dsig/sn/tt + d(8)/3.0_irk

    a(3) = 2.0_irk*dsig(3)/sn/tt

    end subroutine calca

    subroutine calcda(dsig,da,nstre)

    integer (ink) nstre,jstre,istre
    real (irk) dsig(:),da(:,:),sn,one,two,three
    real(irk),allocatable ::v1(:)

    allocate (v1(nstre))
    !
    !    compute derivative of normal vector
    !
    one=   1.00_irk
    two=   2.00_irk
    three= 3.00_irk
    sn = tnorm(dsig)

    da=0.0
    do istre=1,nstre
        da(istre,istre) = two/3.0_irk
    enddo

    da(3,3) =  two
    da(2,1) = -one/three
    da(4,1) = -one/three
    da(4,2) = -one/three

    v1=dsig/sn
    v1(3)=2*dsig(3)/sn

    do  istre=1,nstre
        do  jstre=1,istre
            da(istre,jstre)=(da(istre,jstre)-v1(istre)*v1(jstre))/sn
        enddo
    enddo

    do istre=1,nstre
        do jstre=istre+1,nstre
            da(istre,jstre) = da(jstre,istre)
        enddo
    enddo

    deallocate(v1)

    end subroutine calcda


    subroutine calcQ(Q,da,dmatx,dlan,nstre)

    integer (ink) nstre
    real (irk) Q(:,:),da(:,:),dmatx(:,:), midc(nstre,nstre)
    real (irk) dlan

    midc=dmatx.x.da
    q=dlan*midc
    Q = Id(nstre)+ Q

    end subroutine calcQ

    function tnorm(t)

    real (irk) t(:),tnorm

    tnorm=sum(t*t)
    tnorm=tnorm+sum(t(ndimn+1:3*(ndimn-1))**2)
    ! tnorm = t(1)*t(1)+t(2)*t(2)+2*t(3)*t(3)+t(4)*t(4)

    tnorm = sqrt(tnorm)

    end function

    subroutine calcdevol(tens,dtens,p)

    real (irk) tens(:),dtens(:),p

    if (ndimn==2) then
        p = (tens(1)+tens(2)+tens(4))/3

        dtens(1) = tens(1) - p
        dtens(2) = tens(2) - p
        dtens(3) = tens(3)
        dtens(4) = tens(4) - p
    else if(ndimn==3) then

        p=sum(tens(1:ndimn))
        p=p/3.
        dtens(1:ndimn)=tens(1:ndimn)-p
        dtens(ndimn+1:2*ndimn)=tens(ndimn+1:2*ndimn)

    endif

    end subroutine calcdevol

    SUBROUTINE INIMDL (D ,SIG ,VD )
    !*********************************************************************
    !
    !***** TO INITIALIZE THE STATE VARIABLES
    !
    !*********************************************************************
    real(irk) p,p0,D(:),SIG(:),VD(:)
    !
    !**** INITIALIZATION
    !
    P=-(SIG(1)+SIG(2)+SIG(4))/3.0
    !**** EQP
    VD(1)=0.0d0
    !**** HU
    VD(2)=D(20)
    !**** ETAMAX
    VD(3)=0.0d0
    !**** not used
    VD(4)=0.0d0
    !**** P0
    P0=P
    VD(5)=P0
    END SUBROUTINE INIMDL
    !
    !
    SUBROUTINE FAVMDL(nstre,A1,A2,A3,DEVIA,RJ2,RJ3,THETA,RI1)
    !******************************************************************
    !
    !**** SUBROUTINE FAVMDL FOR P-Z MODEL
    !
    !******************************************************************
    integer(ink) nstre,i,idimn
    real(irk) rj2,rj3,theta,ri1
    real(irk) radian,steff,rj2r,rj3r,root3,tol,tant3,coefa
    real(irk) A1(:),A2(:),A3(:),DEVIA(:)
    RADIAN=ATAN(1.0D0)*29.0d0/45.0d0
    STEFF=SQRT(RJ2)
    RJ2R=ABS(STEFF/RI1)
    RJ3R=ABS(ABS(RJ3)**(1.0D0/3.0D0)/RI1)
    ROOT3=SQRT(3.0D0)
    TOL=1.0D-10
    !
    !***  the partial derivative of I1 with respect to the stresses
    !
    do idimn=1,ndimn
        A1(idimn)=1.0D0/3.0D0
        A1(idimn+ndimn)=0.d0
    end do
    if(ndimn==2.and.nstre==4)a1(4)=1.0D0/3.0D0
    !
    !***  the partial derivative of SQRT(3*J2) with respect to the stresses
    !
    do idimn=1,ndimn
        if(rj2>=1e-10)then
            a2(idimn)=devia(idimn)*root3/(2.*sqrt(rj2))
            a2(idimn+ndimn)=devia(idimn+ndimn)*root3/(sqrt(rj2))
            if(ndimn==2.and.nstre==4)a2(4)=devia(4)*root3/(2.*sqrt(rj2))
        else
            a2(idimn)=1.0d0
            a2(idimn+ndimn)=0.0d0
            if(ndimn==2.and.nstre==4)a2(4)=1.0d0
        endif
    end do

    !
    !***  the partial derivative of J3 with respect to the stresses
    !
    if(ndimn==2.and.nstre==4)then
        a3(1)=devia(2)*devia(4)+rj2/3.0
        a3(2)=devia(1)*devia(4)+rj2/3.0
        a3(3)=-2.d0*devia(3)*devia(4)
        a3(4)=devia(1)*devia(2)-devia(3)*devia(3)+rj2/3.0
    elseif(ndimn==3)then
        a3(1)=devia(2)*devia(3)-devia(5)*devia(5)+rj2/3.0
        a3(2)=devia(1)*devia(3)-devia(6)*devia(6)+rj2/3.0
        a3(3)=devia(1)*devia(2)-devia(4)*devia(4)+rj2/3.0
        a3(4)=2.d0*devia(6)*devia(4)-2.d0*devia(1)*devia(5)
        a3(5)=2.d0*devia(4)*devia(5)-2.d0*devia(2)*devia(6)
        a3(6)=2.d0*devia(5)*devia(6)-2.d0*devia(3)*devia(4)
    else
        print *,'***************error in get derivative of J3 with respect to the stress********'
        stop
    end if
    !
    !***  the partial derivative of THETA with respect to the stresses
    !
    DO  I=1,nstre
        IF (ABS(THETA).LT.RADIAN.AND.RJ2R.GT.TOL.AND.               &
            RJ3R.GT.TOL) THEN
            TANT3=TAN(3.0D0*THETA)
            A3(I)=(TANT3/3.0D0)*(A3(I)/RJ3-A2(I)*3./STEFF)
        ELSE
            A3(I)=0.0D0
        END IF
    end do

    END SUBROUTINE FAVMDL

    SUBROUTINE FNVMDL(nstre,ALFA,RI1,XM,RJ2,THETA,SINPH,A1,A2,A3,  &
        VN,ISW)
    !******************************************************************
    !
    !**** SUBROUTINE FNVMDL FOR P-Z MODEL
    !
    !******************************************************************
    integer(ink) nstre,isw,idimn
    real(irk) alfa,ri1,xm,rj2,theta,sinph
    real(irk) radian,c1,c2,c3,cost3,sum
    real(irk) A1(:),A2(:),A3(:),VN(:)
    RADIAN=29.0D0*ATAN(1.0D0)/45.0D0
    IF (ABS(THETA).GE.RADIAN) THEN
        XM=6.0D0*SINPH/(3.0D0-SINPH)
    END IF
    !
    !**** n_I1
    !
    C1=-(1.+ALFA)*(SQRT(3.0*RJ2)/RI1+XM)
    !**** OPTION 2 IS WRITTEN FOR UNLOADING CASE OF NG
    !**** ABSOLUTE SIGN IS TAKEN SO THAT DENSIFICATION WILL ALWAYS OCCUR
    IF (ISW.EQ.2) C1=ABS(C1)
    !
    !**** n_SQRT(3*J2)
    !
    C2=1.0D0
    !
    !**** n_theta
    !
    C3=0.0D0
    IF (ABS(THETA).LT.RADIAN) THEN
        COST3=COS(3.0D0*THETA)
        C3=-SQRT(3.0D0*RJ2)*0.5D0*XM*COST3
    END IF
    !
    !**** THE PLASTIIC MODULUS H IS CALCULATED WHEN ONLY C1,C2 ARE NORMALIZED
    !
    SUM=SQRT(C1*C1+C2*C2)
    SUM=1.0D0/SUM
    C1=C1*SUM
    C2=C2*SUM
    C3=C3*SUM
    do idimn=1,nstre
        VN(idimn)=C1* A1(idimn)         +C2* A2(idimn)         +C3* A3(idimn)
        !	  VN(idimn+ndimn)=C1*(A1(idimn+ndimn)+A1(idimn+ndimn))+C2*(A2(idimn+ndimn)+A2(idimn+ndimn))+C3*(A3(idimn+ndimn)+A3(idimn+ndimn))
    end do
    if(ndimn==2.and.nstre==4)VN(4)=C1* A1(4)         +C2* A2(4)         +C3* A3(4)
    !      VN(1)=C1* A1(1)         +C2* A2(1)         +C3* A3(1)
    !      VN(2)=C1* A1(2)         +C2* A2(2)         +C3* A3(2)
    !      VN(3)=C1* A1(3)         +C2* A2(3)         +C3* A3(3)
    !      VN(4)=C1*(A1(4)+A1(4))+C2*(A2(4)+A2(4))+C3*(A3(4)+A3(4))
    END SUBROUTINE FNVMDL
    !

    !
    SUBROUTINE RINMDL(DEPSP,DEVP,DEQP,A1,A2)
    !******************************************************************
    !
    !**** SUBROUTINE RINMDL FOR P-Z MODEL
    !
    !******************************************************************
    integer(ink) i
    real(irk) devp,deqp
    real(irk) DEPSP(:),A1(:),A2(:)
    DEVP=0.0d0
    DEQP=0.0d0
    DO 10 I=1,3
        DEVP=DEVP+DEPSP(I)*A1(I)
        DEQP=DEQP+DEPSP(I)*A2(I)
10  CONTINUE
    DEVP=-DEVP*3.0d0
    DEQP=DEQP+DEPSP(4)*A2(4)
    DEQP=DEQP*2.0d0/3.0d0
    END SUBROUTINE RINMDL
    !====================================================================
    !

    SUBROUTINE DEPMDL(SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,     &
        DEPSP,VD,LOADIN,ISW,nstre)
    !******************************************************************
    !
    !**** SUBROUTINE DEPMDL FOR P-Z MODEL
    !
    !******************************************************************
    !-------------------------------------------------------------------
    !     D(24) IS THE ARRAY FOR THE GENERAL MATERIAL PARAMETERS OF
    !            THE SOIL TYPE
    !     SIG(4) THIS IS THE EFFECTIVE STRESS WHICH THE DEP MATRIX
    !            DEPENDS UPON
    !     DSIG(4) THE INCREMENTAL STRESS CALCULATED BY THE SUBROUTINE
    !             DUE TO THE PRESENT STRESS STATE AND DEPS(4)
    !     DEP(4,4) THE ELASTOPLASTIC D MATRIX AND DSIG=DEP*DEPS
    !     DEPS(4) THE INCREMENTAL STRAIN
    !     DE THE ELASTIC D MATRIX
    !     DSIGE(4) THE TRIAL STRESS INCREMENT DSIGE=DE*DEPS
    !     DEPSE(4) THE ELASTIC PART OF THE INCREMENTAL STRAIN
    !               DEPSE=DSIG/DE
    !     DEPSP(4) THE PLASTIC PART OF THE INCREMENTAL STRAIN
    !     DEVIA(4) THE DEVIATORIC STRESS CALCULATED FROM DSIG
    !     A1(4) THE A-VECTOR FOR THE I1
    !     A2(4) THE A-VECTOR FOR THE SQRT(3J2) = Q
    !           A-VECTOR IS D(SQRT(3J2))/DSIG
    !     A3(4) THE A-VECTOR FOR THE LODE ANGLE
    !     VN(4) THE N-VECTOR FOR THE LOADING DIRECTION DETERMINATION
    !     VNG(4) THE NG-VECTOR USED IN BOTH LOADING/UNLOADING CASE
    !     SIGU(4) THE MODIFIED EFFECTIVE STRESS, IT IS NOT REFERENCED IN
    !             THIS SUBROUTINE EXCEPT FOR UPDATING PURPOSE
    !     TEMP1(4) TEMP1=DEM*VNG
    !     TEMP2(4) TEMP2=DEM*VN
    !     VD(5) THE LOCAL VARIABLES FOR THE GAUSS POINT
    !-----------------------------------------------------------------------
    integer(ink) isw,icheck,icels,kload0,loadin,i,j,nstre
    real   (irk) p,q,rj2,rj3,theta,sint3,xmgc,xmfc,etaf,eta,pcut,    &
        plimit,pf,pinc,ri1,p0,prefv,prefs,pmax,bulk,shearm, &
        xnu,e,econs1,econs2,econs3,direct,direc1,etarl, &
        etamax,const11,eqp,fact1,fact2,expf,factv,facts,    &
        factdm,h,hcut,hmid,dirtol,pcut1,const1,const2,const3, &
        deqp,devp
    real(irk) D(24),SIG(:),DEPS(:),DSIG(:),DEPSE(:),DEP(:,:),     &
        DEPSP(:),SIGU(:),    VD(:)
    real(irk), allocatable:: DEVIA(:),A1(:),A2(:),A3(:),VN(:),  &
        VNG(:),DSIGE(:),TEMP1(:),TEMP2(:)
    !-----------------------------------------------------------------------
    !  1. DIRTOL: THE TOLERCANCE USED TO DETERMINE THE ANGLE OF
    !             THE NEUTRAL LOADING ZONE, IF THIS IS NOT USED
    !             A ROUND-OFF ERROR WILL DETERMINE THE LOADING
    !             UNLOADING DIRECTION WHICH MAY NOT BE CORRECT
    !             IN THIS SUBROUTINE, ONCE THE LOADING/UNLOADING
    !             DIRECTION IS DETERMINED FOR ONE TIME STEP
    !             IT WILL NOT BE ALTERED.
    !  2. PLIMIT THIS IS THE LOWEST CONFINING PRESSURE THAT SHOULD
    !     BE ATTAIN BY A GAUSS POINT
    !-----------------------------------------------------------------------
    parameter( DIRTOL=4.0D-5)
    !-----------------------------------------------------------------------
    !  1. LOADIN:    +1 FOR LOADING, ONCE LOADING ALWAYS LOADING-DEP
    !                 0 NOT YET DECIDED (FIRST ITERATION OR PREVIOUS
    !                                    ITERATIONS ARE ELASTIC
    !                 -1 FOR UNLOADING, ONCE UNLOADING ALWAYS UNLOADING-DEP
    !
    !  2. SIGU(4) STANDS FOR THE STRESS STATE TO BE UPDATED
    !     SIG (4) IS THE STRESSES FOR THE DEP EVALUATION
    !     (IN SATURATED SOIL, THIS IS THE EFFECTIVE STRESS STATE)
    !------------------------------------------------------------------------
    !
    !**** FORM ETAF AND ETA (FIRST TIME)
    !
    allocate(devia(nstre),a1(nstre),a2(nstre),a3(nstre),vn(nstre),  &
        vng(nstre),dsige(nstre),temp1(nstre),temp2(nstre))
    CALL IVRMDL(SIG,P,Q,RJ2,RJ3,THETA,DEVIA,SINT3)
    XMGC=6.0*D(3)/(3.0-D(3)*SINT3)
    XMFC=6.0*D(4)/(3.0-D(4)*SINT3) ! hms
    !      XMFC=D(5)*XMGC
    ETAF=(1.0+1.0/D(6))*XMFC
    ETA=ABS(Q/P)
    !
    !**** CHECK 1: AVOID TENSION STATE
    !
    ICHECK=1
    if (ICHECK.EQ.0) go to 666
    PCUT=D(8)
    PLIMIT=1.0D-8*PCUT
    if  (P.LE.0.0) THEN
        SIG(1)=-PLIMIT
        SIG(2)=-PLIMIT
        SIG(3)=-PLIMIT
        p=plimit
        if (SIG(4).LE.0) SIG(4)=ETAF*(-PLIMIT)/SQRT(3.0)
        if (SIG(4).GT.0) SIG(4)=ETAF*PLIMIT/SQRT(3.0)
        q=p*etaf
        eta=etaf
        xmgc=6.0*d(3)/3.0
        xmfc=6.0*d(4)/3.0
        !      xmfc=d(5)*xmgc
        etaf=(1.0+1.0/d(6))*xmfc
    END IF
    !
    !**** CHECK 2: KEEP ETA < ETAF
    !
    if  (ETA.GT.ETAF) THEN
        PF=ABS(Q/ETAF)
        PINC=PF-P
        SIG(1)=SIG(1)-PINC
        SIG(2)=SIG(2)-PINC
        SIG(3)=SIG(3)-PINC
    END IF
    !
    !**** FORM INVARIANTS AND ETA (SECOND TIME) , ETAF IS NOT CHANGED !
    !
    CALL IVRMDL(SIG,P,Q,RJ2,RJ3,THETA,DEVIA,SINT3)
666 continue
    RI1=-P
    ETA=ABS(Q/P)
    !
    !**** SINCE THE MODEL HAS A SINGULARITY AT PURE COMRESSION
    !     THE ETA IS SLIGHTLY MODIFIED

    if  (ETA.LT.0.000100) ETA=0.000100
    !
    !**** FIND THE ELASTIC CONSTANTS (CHECK IF THEY ARE VARIABLE WITH P
    !
    P0=VD(5)
    PREFV=P0
    PREFS=P0
    ICELS=D(12)+0.5
    PCUT=D(8)
    PMAX=1.0D+7
    if  (ICELS.EQ.0.OR.ICELS.EQ.2) PREFV=MIN(P,PMAX)
    if  (ICELS.EQ.0.OR.ICELS.EQ.1) PREFS=MIN(P,PMAX)
    if  (ICELS.EQ.0.OR.ICELS.EQ.2) PREFV=MAX(P,PCUT)
    if  (ICELS.EQ.0.OR.ICELS.EQ.1) PREFS=MAX(P,PCUT)
    BULK=D(9)*PREFV
    SHEARM=D(10)*PREFS/3.0D0
    XNU=(3.0*BULK-2.0*SHEARM)/(6.0*BULK+2.0*SHEARM)
    E=3.0*BULK*(1.0-2.0*XNU)
    !
    !**** FORM THE ELASTIC ELASTICITY MATRIX DE
    !
    ECONS1=E*(1.0-XNU)/((1.0+XNU)*(1.0-2.0*XNU))
    ECONS2=ECONS1*XNU/(1.-XNU)
    ECONS3=ECONS1*(1.-2.*XNU)*0.5/(1.-XNU)
    !      IF(ISW.EQ.1) THEN
    !      DO 4001 I=1,4
    !      DO 4001 J=1,4
    ! 4001 DEP(I,J)=0.0
    !      DEP(1,1)=ECONS1
    !      DEP(2,2)=ECONS1
    !      DEP(1,2)=ECONS2
    !      DEP(2,1)=ECONS2
    !      DEP(3,3)=ECONS3
    !      RETURN
    !      END IF
    !
    !**** FORM THE A-VECTORS IN ORDER TO CALCULATE THE N AND NG VECTORS
    !
    CALL FAVMDL(nstre,A1,A2,A3,DEVIA,RJ2,RJ3,THETA,RI1)
    !
    !**** FORM THE N-VECTOR
    !
    CALL FNVMDL(nstre,D(6),RI1,XMFC,RJ2,THETA,D(4),A1,A2,A3,VN,1)
    !
    !**** FORM THE ELASTIC STRESS INCREMENT DEFINED AS DSIGE=DE*DEPS
    !
    DSIGE(1)=ECONS1*DEPS(1)+ECONS2*(DEPS(2)+DEPS(3))
    DSIGE(2)=ECONS1*DEPS(2)+ECONS2*(DEPS(3)+DEPS(1))
    DSIGE(3)=ECONS1*DEPS(3)+ECONS2*(DEPS(1)+DEPS(2))
    DSIGE(4)=ECONS3*DEPS(4)
    !
    !**** CHECK LOADING OR UNLOADING
    !
    KLOAD0=LOADIN
    !
    !**** FORMING NT.DE.DEPS FOR DIRECTION DETERMINATION
    !**** FIND THE COSINE BETWEEN THE TWO VECTORS (ACTUALLY BOTH ARE TENSORS)
    !
    DIRECT=VN.d.DSIGE
    DIREC1=SQRT(dot_product(DSIGE,DSIGE)*dot_product(VN,VN))
    if  (DIREC1.NE.0.0) THEN
        DIRECT=DIRECT/DIREC1
    ELSE
        if  (DIRECT.NE.0.0) THEN
            !      PRINT *,'DIRECT<>0 WITH DIREC1=0 IN DEPMDL'
            STOP 'STOP IN DEPMDL'
        END IF
    END IF
    LOADIN=0
    if  (DIRECT.GT.DIRTOL) LOADIN=1
    if  (DIRECT.LT.-DIRTOL) LOADIN=-1
    !
    !**** UPDATE Hu WHEN REVERSAL
    !------------------------------------------------------------------
    if (KLOAD0.GT.0.AND.LOADIN.LT.0) THEN
        ETARL=ETA/XMGC
        if (ETARL.GT.0.01.AND.ETARL.LT.1.0) VD(2)=D(20)/(ETARL**D(21))
        if (ETARL.LE.0.01) VD(2)=10000.0*D(20)
        if (ETARL.GE.1.0)  VD(2)=D(20)
    END IF
    !------------------------------------------------------------------
    VD(3)=MAX(ETA,VD(3))
    !
    if  (LOADIN.EQ.0) GOTO 250
    if  (LOADIN.LT.0) GOTO 260
    !
    !**** FORM THE LOADING NG VECTOR
    !
    CALL FNVMDL(nstre,D(7),RI1,XMGC,RJ2,THETA,D(3),A1,A2,A3,VNG,1)
    ETAMAX=VD(3)
    EQP=VD(1)
    FACT1=P
    PCUT1=PCUT*1.0E-8
    FACT1=MAX(P,PCUT1)
    FACT1=MIN(P,PMAX)
    EXPF=D(24)
    !
    if (ETA.GE.ETAF) THEN ! because a little error
        FACT2=0.0
    ELSE
        FACT2=(1.-ETA/ETAF)**EXPF
    END IF
    !
    FACTV=1.0-ETA/XMGC
    !
    if (EQP.EQ.0.0) THEN
        FACTS=D(13)*D(14)
    ELSE
        FACTS=D(13)*D(14)*EXP(-D(13)*ABS(EQP))
    END IF
    !
    FACTDM=(ETA/ETAMAX)**D(16)
    !
    H=D(15)*FACT1*FACT2*(FACTV+FACTS)/FACTDM
    !
    HCUT=E*1.0E-06
    Hmid=MAX(abs(H),HCUT)    !!!97
    H=sign(hmid,h)            !!!97
    !
    !**** FORM THE ADDITIVE FACTOR FOR H
    !
    TEMP1(1)=ECONS1*VNG(1)+ECONS2*(VNG(2)+VNG(3))
    TEMP1(2)=ECONS1*VNG(2)+ECONS2*(VNG(1)+VNG(3))
    TEMP1(3)=ECONS1*VNG(3)+ECONS2*(VNG(1)+VNG(2))
    TEMP1(4)=ECONS3*VNG(4)
    !              T
    !**** CONST1=NG  DE N
    !
    CONST1=TEMP1.d.VN
    TEMP2(1)=ECONS1*VN(1)+ECONS2*(VN(2)+VN(3))
    TEMP2(2)=ECONS1*VN(2)+ECONS2*(VN(1)+VN(3))
    TEMP2(3)=ECONS1*VN(3)+ECONS2*(VN(1)+VN(2))
    TEMP2(4)=ECONS3*VN(4)
    const11=h+const1
    if (abs(const11).le.hcut) const11=sign(hcut,const11)  !!!97
    CONST2=1.0/CONST11
    !      CONST2=1.0/(H+CONST1)
    !
    !**** FORM THE DEP AND DSIG
    !
    !------------------------------------------------------!HMS
    if (isw.eq.1) THEN
        DO 311 I=1,4
            DO 311 J=1,4
311     DEP(I,J)=0.0
        DEP(1,1)=ECONS1-CONST2*TEMP1(1)*TEMP2(1)
        DEP(1,2)=ECONS2-CONST2*TEMP1(1)*TEMP2(2)
        DEP(1,3)=-CONST2*TEMP1(1)*TEMP2(4)
        DEP(2,1)=ECONS2-CONST2*TEMP1(2)*TEMP2(1)
        DEP(2,2)=ECONS1-CONST2*TEMP1(2)*TEMP2(2)
        DEP(2,3)=-CONST2*TEMP1(2)*TEMP2(4)
        DEP(3,1)=-CONST2*TEMP1(4)*TEMP2(1)
        DEP(3,2)=-CONST2*TEMP1(4)*TEMP2(2)
        DEP(3,3)=ECONS3-CONST2*TEMP1(4)*TEMP2(4)
        deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2)
        RETURN
    END IF
    !--------------------------------------------------!HMS
    !
    CONST2=CONST2*DOT_product(DEPS,TEMP2)
    DSIG(1)=DSIGE(1)-TEMP1(1)*CONST2
    DSIG(2)=DSIGE(2)-TEMP1(2)*CONST2
    DSIG(3)=DSIGE(3)-TEMP1(3)*CONST2
    DSIG(4)=DSIGE(4)-TEMP1(4)*CONST2
    GOTO 250
260 CONTINUE
    !
    !**** FORM THE UNLOADING NG VECTOR
    !
    CALL FNVMDL(nstre,D(7),RI1,XMGC,RJ2,THETA,D(3),A1,A2,A3,VNG,2)
    H=VD(2)
    !
    !**** FORM THE ADDITIVE FACTOR FOR H
    !              T
    !**** CONST1=NG  DE N
    !
    TEMP1(1)=ECONS1*VNG(1)+ECONS2*(VNG(2)+VNG(3))
    TEMP1(2)=ECONS1*VNG(2)+ECONS2*(VNG(1)+VNG(3))
    TEMP1(3)=ECONS1*VNG(3)+ECONS2*(VNG(1)+VNG(2))
    TEMP1(4)=ECONS3*VNG(4)
    CONST1=DOT_product(TEMP1,VN)
    TEMP2(1)=ECONS1*VN(1)+ECONS2*(VN(2)+VN(3))
    TEMP2(2)=ECONS1*VN(2)+ECONS2*(VN(1)+VN(3))
    TEMP2(3)=ECONS1*VN(3)+ECONS2*(VN(1)+VN(2))
    TEMP2(4)=ECONS3*VN(4)
    const11=h+const1
    if (abs(const11).le.hcut) const11=sign(hcut,const11)
    CONST2=1.0/CONST11
    !      CONST2=1.0/(H+CONST1)
    !
    !**** FORM THE DEP AND DSIG
    !
    !-----------------------------------------------------!HMS
    if (isw.eq.1) THEN
        DO 312 I=1,4
            DO 312 J=1,4
312     DEP(I,J)=0.0
        DEP(1,1)=ECONS1-CONST2*TEMP1(1)*TEMP2(1)
        DEP(1,2)=ECONS2-CONST2*TEMP1(1)*TEMP2(2)
        DEP(1,3)=-CONST2*TEMP1(1)*TEMP2(4)
        DEP(2,1)=ECONS2-CONST2*TEMP1(2)*TEMP2(1)
        DEP(2,2)=ECONS1-CONST2*TEMP1(2)*TEMP2(2)
        DEP(2,3)=-CONST2*TEMP1(2)*TEMP2(4)
        DEP(3,1)=-CONST2*TEMP1(4)*TEMP2(1)
        DEP(3,2)=-CONST2*TEMP1(4)*TEMP2(2)
        DEP(3,3)=ECONS3-CONST2*TEMP1(4)*TEMP2(4)
        deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2)
        RETURN
    END IF
    !--------------------------------------------------!HMS
    !
    CONST2=CONST2*DOT_product(DEPS,TEMP2)
    DSIG(1)=DSIGE(1)-TEMP1(1)*CONST2
    DSIG(2)=DSIGE(2)-TEMP1(2)*CONST2
    DSIG(3)=DSIGE(3)-TEMP1(3)*CONST2
    DSIG(4)=DSIGE(4)-TEMP1(4)*CONST2
250 CONTINUE
    CONST1=1.0/E
    CONST2=-XNU*CONST1
    CONST3=2.0*(1.0+XNU)*CONST1
    !
    !**** FORM THE ELASTIC STRAIN INCREMENT FROM THE INCREMENTAL STRESS GIVEN
    !
    if  (LOADIN.EQ.0) THEN
        dsig=dsige
        depse=deps
        !------------------------------------------------!HMS
        if (isw.eq.1) THEN
            DO 4002 I=1,4
                DO 4002 J=1,4
4002        DEP(I,J)=0.0
            DEP(1,1)=ECONS1
            DEP(2,2)=ECONS1
            DEP(1,2)=ECONS2
            DEP(2,1)=ECONS2
            DEP(3,3)=ECONS3
            deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2)
            RETURN
        END IF
        !------------------------------------------------!HMS
        !
    ELSE
        DEPSE(1)=CONST1*DSIG(1)+CONST2*(DSIG(2)+DSIG(3))
        DEPSE(2)=CONST1*DSIG(2)+CONST2*(DSIG(3)+DSIG(1))
        DEPSE(3)=CONST1*DSIG(3)+CONST2*(DSIG(1)+DSIG(2))
        DEPSE(4)=CONST3*DSIG(4)
    END IF
    DO 401 I=1,4
        SIG (I)=SIG (I)+DSIG(I)
        SIGU(I)=SIGU(I)+DSIG(I)
401 DEPSP(I)=DEPS(I)-DEPSE(I)
    !
    if (ISW.EQ.2) THEN
        CALL RINMDL(DEPSP,DEVP,DEQP,A1,A2)
        VD(1)=VD(1)+ABS(DEQP)
    END IF
    deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2)
    !
    END  SUBROUTINE DEPMDL

    !
    SUBROUTINE TESMDL (nstre,SIGU,SIG,DEPS,DEP,VD,LOADIN,ISW,  &
        ndiv,ntest,d)
    !******************************************************************
    !
    !**** MAIN SUBROUTINE FOR P-Z MODEL
    !
    !******************************************************************
    integer(ink) loadin,isw,ndiv,ntest,mndiv,icheck,i,nstre
    real   (irk) ctol,ds1,ds2,temp1,p,q,rj2,rj3,theta,    &
        sint3,eta,xmgc,xmfc,etaf,pu,ps,pcut,pk,pf,    &
        plimit,pinc
    real(irk) D(24),SIG(:),sigu(:),DEPS(:),DEP(:,:),VD(:),  VDA(5),VDB(5)
    real(irk), allocatable:: DSIG(:),DEPSE(:),DEPSP(:),SIGA(:), &
        SIGUA(:),DSIGA(:),SIGB(:),SIGUB(:),devia(:)
    PARAMETER (MNDIV=20,CTOL=0.05)
    !

    allocate(dsig(nstre),depse(nstre),depsp(nstre),siga(nstre),sigua(nstre),  &
        dsiga(nstre),sigb(nstre),sigub(nstre),devia(nstre))
    if (isw.eq.1) go to 1000
    GOTO (1000,2000),NTEST
    write(chkunit,*)'ERROR IN TESMDL,ntest=,',ntest
    STOP
    !
    !**** JUST ADD THE INCREMENT
    !
1000 CONTINUE
    CALL DEPMDL(SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,                 &
        DEPSP,VD,LOADIN,ISW,nstre)
    GOTO 10000
    !
    !**** CONSTANT SUBDIVISION DEPENDING ON THE DIFFERENCE
    !**** NORM: DSIG(DIFF)/(2*DSIG(MEAN))
    !
2000 CONTINUE
    siga=sig
    sigua=sigu
    vda=vd
    !
    CALL DEPMDL(SIGUA,SIGA,DEPS,DSIG,DEPSE,D,DEP,               &
        DEPSP,VDA,LOADIN,ISW,nstre)
    sigb=siga
    sigub=sigua
    vdb=vda
    CALL DEPMDL(SIGUA,SIGA,DEPS,DSIGA,DEPSE,D,DEP,            &
        DEPSP,VDA,LOADIN,ISW,nstre)
    DS1=0.0
    DS2=0.0
    DO 2001 I=1,4
        TEMP1=0.500*(DSIG(I)+DSIGA(I))
        DS1=DS1+TEMP1*TEMP1
        TEMP1=0.500*(DSIG(I)-DSIGA(I))
2001 DS2=DS2+TEMP1*TEMP1
    DS1=SQRT(DS1)
    DS2=SQRT(DS2)
    if (DS1.EQ.0.0) THEN
        NDIV=1
    ELSE
        NDIV=DS2/(CTOL*DS1)+0.99
    END IF
    NDIV=MAX(1,NDIV)
    NDIV=MIN(MNDIV,NDIV)
    if  (NDIV.NE.1) GOTO 2005
    sig=sigb
    sigu=sigub
    vd=vdb
    GOTO 10000
2005 CONTINUE
    DO 2002 I=1,4
2002 DEPS(I)=DEPS(I)/FLOAT(NDIV)
    DO 2003 I=1,NDIV
        CALL DEPMDL(SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,              &
            DEPSP,VD,LOADIN,ISW,nstre)
2003 CONTINUE

10000 CONTINUE
    ICHECK=1
    !      if(isw.eq.1) return
    !      IF(ICHECK.EQ.0) RETURN
    if (isw==1.or.icheck==0) then
        deallocate(dsig,depse,depsp,siga,sigua,  &
            dsiga,sigb,sigub,devia)
        return
    endif
    !
    !**** FORM ETA AND ETAF
    !

    CALL IVRMDL(SIG,P,Q,RJ2,RJ3,THETA,DEVIA,SINT3)
    ETA=ABS(Q/P)
    XMGC=6.0*D(3)/(3.0-D(3)*SINT3)
    XMFC=6.0*D(4)/(3.0-D(4)*SINT3)
    !      XMFC=D(5)*XMGC
    ETAF=(1.0+1.0/D(6))*XMFC
    !
    !**** CHECK 1 : AVOID TENSION STATE
    !
    PU=-(SIGU(1)+SIGU(2)+SIGU(3))/3.0
    PS=-(SIG(1)+SIG(2)+SIG(3))/3.0
    if  (PU.LE.0.0.OR.PS.LE.0.0) THEN
        PCUT=D(8)
        PLIMIT=1.0D-8*PCUT
        PK=PS-PU
        if  (PK.GT.0.0) THEN
            !**** THE SIG IS MORE COMPRESSIVE
            SIGU(1)=-PLIMIT
            SIGU(2)=-PLIMIT
            SIGU(3)=-PLIMIT
            if (SIGU(4).LE.0) SIGU(4)=ETAF*(-PLIMIT)/SQRT(3.0)
            if (SIGU(4).GT.0) SIGU(4)=ETAF*PLIMIT/SQRT(3.0)
            SIG(1)=-PK-PLIMIT
            SIG(2)=-PK-PLIMIT
            SIG(3)=-PK-PLIMIT
            p=pk+plimit
            if (SIG(4).LE.0) SIG(4)=ETAF*(-PK-PLIMIT)/SQRT(3.0)
            if (SIG(4).GT.0) SIG(4)=ETAF*(PK+PLIMIT)/SQRT(3.0)
            q=p*etaf
            eta=etaf
            xmgc=6.0*d(3)/3.0
            xmfc=6.0*d(4)/3.0
            !      xmfc=d(5)*xmgc
            etaf=(1.0+1.0/d(6))*xmfc
        ELSE
            !**** THE SIGU IS MORE COMPRESSIVE
            SIG(1)=-PLIMIT
            SIG(2)=-PLIMIT
            SIG(3)=-PLIMIT
            if (SIG(4).LE.0) SIG(4)=ETAF*(-PLIMIT)/SQRT(3.0)
            if (SIG(4).GT.0) SIG(4)=ETAF*PLIMIT/SQRT(3.0)
            SIGU(1)=PK-PLIMIT
            SIGU(2)=PK-PLIMIT
            SIGU(3)=PK-PLIMIT
            p=pk+plimit
            if (SIGU(4).LE.0) SIG(4)=ETAF*(PK-PLIMIT)/SQRT(3.0)
            if (SIGU(4).GT.0) SIG(4)=ETAF*(-PK+PLIMIT)/SQRT(3.0)
            q=p*etaf
            eta=etaf
            xmgc=6.0*d(3)/3.0
            xmfc=6.0*d(4)/3.0
            !      xmfc=d(5)*xmgc
            etaf=(1.0+1.0/d(6))*xmfc
        END IF
    END IF
    !
    !**** CHECK 2 : KEEP ETA < ETAF
    !
    if (ETA.GT.ETAF) THEN
        PF=ABS(Q/ETAF)
        PINC=PF-P
        DO 90 I=1,3
            SIG(I)=SIG(I)-PINC
90      SIGU(I)=SIGU(I)-PINC
    END IF
    deallocate(dsig,depse,depsp,siga,sigua,  &
        dsiga,sigb,sigub,devia)
    !
    END SUBROUTINE TESMDL

    SUBROUTINE IVRMDL(SIG,P,Q,RJ2,RJ3,THETA,DEVIA,SINT3)
    !******************************************************************
    !
    !**** SUBROUTINE IVRMDL FOR P-Z MODEL
    !
    !******************************************************************
    integer(ink) i
    real(irk) p,q,rj2,rj3,theta,sint3
    real(irk) rj23
    real(irk) SIG(:),DEVIA(:)
    P=-(SIG(1)+SIG(2)+SIG(3))/3.0d0
    DO 10 I=1,3
10  DEVIA(I)=SIG(I)+P
    DEVIA(4)=SIG(4)
    RJ2=0.0d0
    RJ2=RJ2+DEVIA(4)*DEVIA(4)*2.0d0
    DO 20 I=1,3
20  RJ2=RJ2+DEVIA(I)*DEVIA(I)
    RJ2=RJ2/2.0d0
    Q=SQRT(3.0d0*RJ2)
    RJ3=0.0d0
    RJ3=RJ3+DEVIA(4)*DEVIA(4)*(DEVIA(1)+DEVIA(2))*3.0d0
    DO 30 I=1,3
30  RJ3=RJ3+DEVIA(I)*DEVIA(I)*DEVIA(I)
    RJ3=RJ3/3.0d0
    RJ23=SQRT(RJ2)**3
    if (RJ23.GE.1.0D-20) THEN
        SINT3=-3.0*SQRT(3.0d0)*RJ3/(2.0d0*RJ23)
    ELSE
        SINT3=0.0D0
    END IF
    if  (SINT3.GT.1.0) SINT3=1.0
    if  (SINT3.LT.-1.0) SINT3=-1.0
    THETA=ASIN(SINT3)/3.0d0
    if  (SINT3.LT.0.0) Q=-Q
    END SUBROUTINE IVRMDL

    !
    SUBROUTINE cvoid(ic)
    !******************************************************************
    !
    !*** UPDATES void
    !ic=0, initial value; ic=1, update according to volume strain
    ! this sub. will be called at the begining(ic=0) or convergence step(ic=1)
    !the ratio in fluid (input) is the initial porosity
    !
    !******************************************************************
    character(10) fieldid,material,Sptype
    integer(ink) ic,matno,igroup,index,nnode,ielem,order_int,  &
        ngaus,igaus,ielgroup,nstre,nevab
    integer(ink), pointer::ldofs(:)
    real   (irk)  ratio,voidn,voidg,nu,volume_strain
    real   (irk), allocatable::bmatx(:,:),eldis(:),stran(:),   &
        shape(:),gpcod(:),cartd(:,:)

    DO igroup =1,ngroup
        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:2)=='UW') then
            ! get information from the group level
            matno = group(igroup)%matno
            material=props(matno)%name
            if (material(1:6)=='NSSoil') then
                index = group(igroup)%index
                if (ic==1) then
                    nnode = elkn(index)%el_field(2)%nnode_f
                    nstre=  group(igroup)%nstre
                    SPtype=    group(igroup)%SPtype
                    nevab = nnode*ndimn
                    allocate(bmatx(nstre,nevab),eldis(nevab),stran(nstre),  &
                        shape(nnode),gpcod(ndimn),cartd(ndimn,nnode))
                endif

                if (ic==0) then
                    ratio =props(matno)%mechanical%fluid%ratio
                    voidn=ratio/(1-ratio)
                endif
                if (ndimn==2.and.SPtype(1:2)=='PS') nu =props(matno)%mechanical%solid%nu
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    if (ic==1) then
                        ldofs => element(ielem)%field(1)%ldofs_f
                        eldis(1:nevab) = deltafi(ldofs(1:nevab))
                    endif
                    order_int=elkn(index)%el_field(2)%order_intrules(2)
                    ngaus = elkn(index)%ggaus(order_int)%ngaus

                    do igaus=1,ngaus

                        if (ic==0) goto 10

                        voidg =element(ielem)%egaus(order_int)%voide(igaus)
                        shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                        ! get djacb and cartd in the element level
                        gpcod=element(ielem)%egaus(order_int)%gpcod(:,igaus)
                        cartd=element(ielem)%egaus(order_int)%cartd(:,:,igaus)
                        bmatx=0.0
                        call gbmat (SPtype, nnode, bmatx, cartd, gpcod, shape)
                        ! compute strain and elastic stres increment
                        stran=matmul(bmatx,eldis)
                        if (ndimn==2.and.SPtype(1:2)=='PS')  &
                            stran(4)=-(stran(1)+stran(2))*nu/(1.-nu)
                        if (ndimn==2)volume_strain=stran(1)+stran(2)+stran(4)
                        if (ndimn==3)volume_strain=sum(stran(1:3))
                        voidn=VOIDG+(1.0+VOIDG)*volume_strain
                        if (voidn.LT.0.0) voidn=0.0
10                      element(ielem)%egaus(order_int)%voide(igaus)=voidn
                    end do   !! igaus
                    if (ic==1)nullify(ldofs)
                end do  !! ielgroup
                if (ic==1)deallocate(bmatx,eldis,stran,shape,gpcod,cartd)
            endif  !! Soil
        endif  !! appear(igroup)>0&&fieldid(1:2)==UW

    end do !! igroup

    end subroutine cvoid
    !
    SUBROUTINE Porepr
    !******************************************************************
    !
    !*** UPDATES POROSITY
    !*** UPDATES SATURATION AND PERMEABILITY
    !
    !******************************************************************
    character(10) fieldid,material
    integer(ink) matno,igroup,index,nnode,ielem,order_int,  &
        ngaus,ielgroup,order_int1,ifield
    integer(ink), pointer::lnods(:)
    real   (irk), allocatable::press(:),pwatr(:)
    real   (irk), pointer::shape(:,:)
    DO igroup =1,ngroup
        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.(fieldid(1:2)=='UW'.or.fieldid(1:1)=='W')) then
            ! get information from the group level
            matno = group(igroup)%matno
            material=props(matno)%name
            if (material(1:6)=='NSSoil') then
                index = group(igroup)%index
                ifield=1  !2006NS
                if (fieldid(1:2)=='UW')ifield=2  !2006NS
                nnode = elkn(index)%el_field(ifield)%nnode_f
                allocate(press(nnode))
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods => element(ielem)%field(ifield)%lnods_f
                    press=result_zero(nodfn(lmdofn(8),lnods))
                    !pore pressure at fluid gauss points
                    order_int=elkn(index)%el_field(ifield)%order_intrules(2)
                    ngaus = elkn(index)%ggaus(order_int)%ngaus
                    allocate(pwatr(ngaus))
                    shape => elkn(index)%ggaus(order_int)%shape
                    pwatr=transpose(shape).x.press
                    element(ielem)%egaus(order_int)%pwatr=pwatr
                    deallocate(pwatr)
                    !pore pressure at solid gauss points
                    if (ifield==2)then
                        order_int1=elkn(index)%el_field(1)%order_intrules(1)
                        if (order_int1/=order_int) then
                            order_int=order_int1
                            ngaus = elkn(index)%ggaus(order_int)%ngaus
                            allocate(pwatr(ngaus))
                            shape => elkn(index)%shapep
                            pwatr=transpose(shape).x.press
                            element(ielem)%egaus(order_int)%pwatr=pwatr
                            !write(7,*)'ie=',ielem,'order_int=',order_int,'pwatr=',pwatr
                            deallocate(pwatr)
                        endif
                    endif
                    nullify(lnods)
                end do  !! ielgroup

                deallocate(press)
            endif  !! Soil
        endif  !! appear(igroup)>0&&fieldid(1:2)==UW

    end do !! igroup

    END SUBROUTINE Porepr
    !
    SUBROUTINE Porepr_w
    !******************************************************************
    !
    !*** UPDATES POROSITY
    !*** UPDATES SATURATION AND PERMEABILITY
    !
    !******************************************************************
    character(10) fieldid,material
    integer(ink) matno,igroup,index,nnode,ielem,order_int,  &
        ngaus,ielgroup
    integer(ink), pointer::lnods(:)
    real   (irk), allocatable::press(:),pwatr(:)
    real   (irk), pointer::shape(:,:)
    DO igroup =1,ngroup
        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='W') then
            ! get information from the group level
            matno = group(igroup)%matno
            material=props(matno)%name
            if (material(1:6)=='NSSoil') then
                index = group(igroup)%index
                nnode = elkn(index)%el_field(1)%nnode_f

                allocate(press(nnode))
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods => element(ielem)%field(1)%lnods_f
                    press=result_zero(nodfn(lmdofn(8),lnods))
                    !pore pressure at fluid gauss points
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    ngaus = elkn(index)%ggaus(order_int)%ngaus
                    allocate(pwatr(ngaus))
                    shape => elkn(index)%ggaus(order_int)%shape
                    pwatr=transpose(shape).x.press
                    element(ielem)%egaus(order_int)%pwatr=pwatr
                    deallocate(pwatr)
                    nullify(lnods)
                end do  !! ielgroup

                deallocate(press)
            endif  !! Soil
        endif  !! appear(igroup)>0&&fieldid(1:1)==W

    end do !! igroup

    END SUBROUTINE Porepr_w

    !
    SUBROUTINE PROPTY
    !******************************************************************
    !
    !*** UPDATES POROSITY
    !*** UPDATES SATURATION AND PERMEABILITY
    !
    !******************************************************************
    character(10) fieldid,material
    integer(ink) matno,igroup,index,nnode,ksmsa,ielem,order_int,  &
        ngaus,igaus,npmpm, nswpw,ielgroup,ifield,        &
        intc,order_int0,order_int1,order_int2
    integer(ink), pointer::lnods(:)
    real   (irk) pwatr,dpwat,pnete,permb,pmaxm,hwatr,a,b,   &   !,gamaw 20230402
        alfa,voide,poros,satur,csmos,setar,setas,beta,   &
        gama,seta,value
    real   (irk), allocatable::press(:),shape(:),pmpwc(:),swpwc(:),pwatp(:),pwats(:)

    DO igroup =1,ngroup
        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:2)=='UW'.or.fieldid(1:1)=='W') then
            ! get information from the group level
            matno = group(igroup)%matno
            material=props(matno)%name
            if (material(1:6)=='NSSoil') then
                index = group(igroup)%index
                ifield=1 !2006NS
                if (fieldid(1:2)=='UW')ifield=2 !2006NS
                nnode = elkn(index)%el_field(ifield)%nnode_f
                allocate(press(nnode),shape(nnode))
                ksmsa = props(matno)%mechanical%fluid%ksmsa
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    lnods => element(ielem)%field(ifield)%lnods_f
                    press=result_zero(nodfn(lmdofn(8),lnods))
                    !relative permiability
                    order_int=elkn(index)%el_field(ifield)%order_intrules(1)
                    order_int0=elkn(index)%el_field(ifield)%order_intrules(2)
                    ngaus = elkn(index)%ggaus(order_int)%ngaus

                    do igaus=1,ngaus

                        if (order_int/=order_int0) then
                            shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                            pwatr=shape.d.press
                        else
                            pwatr = element(ielem)%egaus(order_int)%pwatr(igaus)
                        endif
                        if (KSMSA.EQ.0)  PERMB=1.0D0
                        !
                        if (KSMSA.EQ.1) THEN
                            npmpm=props(matno)%mechanical%fluid%npmpm
                            allocate(pmpwc(npmpm),pwatp(npmpm))
                            pwatp=props(matno)%mechanical%fluid%pwatp
                            pmpwc=props(matno)%mechanical%fluid%pmpwc
                            CALL PERMBL (PERMB ,PWATR ,NPMPm ,PWATp,PMPWC )
                            deallocate(pmpwc,pwatp)
                        END IF
                        !
                        if (KSMSA.EQ.2) THEN
                            !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
                            PNETE=PWATR
                            if (PNETE.GE.0.0) THEN
                                PERMB=1.0D0
                            ELSE
                                PMAXM=-40.0D0*980.0D0*9.81D0
                                permb=1.0D0-(PNETE/PMAXM)**2
                            END IF
                        END IF
                        !
                        if (KSMSA.EQ.3.OR.KSMSA.EQ.4.OR.KSMSA.EQ.5.OR.KSMSA.EQ.6) THEN
                            !*** AFTER VAN GENUCHTEN ET AL [1977]
                            !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
                            PNETE=PWATR
                            if (PNETE.Gt.0.0) THEN
                                PERMB=1.0D0
                            ELSE
                                !*** PARAMETERS FOR Sw - Pw CURVE
                                !   GAMAW=980.0D0*9.81D0  20230402
                                HWATR=ABS(PNETE/GAMAW)*100.0D0  ! (CM)
                                !*** PARAMETERS FOR Kw - Pw CURVE
                                A=0.050D0
                                B=4.0D0
                                ALFA=0.90D0
                                PERMB=1.0D0/((1.0D0+(A*HWATR)**B)**ALFA)
                                !       IF(PERMB.LT.0.001D0)  PERMB=0.001D0
                            END IF
                        END IF
                        element(ielem)%egaus(order_int0)%permr(igaus)=permb
                        !20220707(order_int->order_int0)
                    end do   !! igaus for permeability


                    !end relative permiability

                    !saturation and csmos
                    intc=0
                    order_int=elkn(index)%el_field(ifield)%order_intrules(2)
                    order_int0=order_int
                    ngaus = elkn(index)%ggaus(order_int)%ngaus

11                  do igaus=1,ngaus

                        if (intc==0)then

                            if (fieldid(1:2)=='UW')then
                                voide=element(ielem)%egaus(order_int)%voide(igaus)
                                poros=voide/(1+voide)
                            else
                                poros=props(matno)%mechanical%fluid%ratio
                            endif
                        endif
                        if (intc==1) then
                            shape = elkn(index)%ggaus(order_int)%shape(:,igaus)
                            pwatr=shape.d.press
                        else
                            pwatr = element(ielem)%egaus(order_int)%pwatr(igaus)
                        endif

                        if (KSMSA.EQ.0) THEN
                            SATUR=1.0D0
                            CSMOS=0.0D0
                        END IF
                        !
                        if (KSMSA.EQ.1) THEN
                            nswpw=props(matno)%mechanical%fluid%nswpw
                            allocate(swpwc(nswpw),pwats(nswpw))
                            pwats=props(matno)%mechanical%fluid%pwats
                            swpwc=props(matno)%mechanical%fluid%swpwc
                            CALL SATURT (SATUR ,CSMOS ,PWATR ,POROS ,NSWPW ,PWATs ,SWPWC )
                            deallocate(swpwc,pwats)
                        END IF
                        !
                        if (KSMSA.EQ.2) THEN
                            !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
                            PNETE=PWATR
                            if (PNETE.GE.0.0) THEN
                                SATUR=1.0D0
                                CSMOS=0.0D0
                            ELSE
                                PMAXM=-40.0D0*980.0D0*9.81D0
                                SATUR=1.0D0-(PNETE/PMAXM)**2
                                CSMOS=POROS*(-2.0D0*PNETE/(PMAXM*PMAXM))
                            END IF
                        END IF
                        !
                        if (KSMSA.EQ.3.OR.KSMSA.EQ.4.OR.KSMSA.EQ.5.OR.KSMSA.EQ.6) THEN
                            !*** AFTER VAN GENUCHTEN ET AL [1977]
                            !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
                            PNETE=PWATR
                            if (PNETE.Gt.0.0) THEN
                                SATUR=1.0D0
                                CSMOS=0.0D0
                            ELSE
                                !*** PARAMETERS FOR Sw - Pw CURVE
                                SETAR=0.04D0
                                SETAS=0.475D0
                                BETA=0.007D0
                                GAMA=2.0D0
                                if (KSMSA.EQ.4) BETA=0.00007D0
                                if (KSMSA.EQ.5) THEN
                                    SETAR=0.008D0
                                    BETA=0.035D0
                                END IF
                                if (KSMSA.EQ.6) THEN
                                    SETAR=0.004D0
                                    BETA=0.07D0
                                END IF
                                ! GAMAW=980.0D0*9.81D0  20230402
                                HWATR=ABS(PNETE/GAMAW)*100.0D0  ! (CM)
                                VALUE=(1.0D0+(BETA*HWATR)**GAMA)
                                SETA=SETAR/SETAS
                                SATUR=SETA+(1.0D0-SETA)/VALUE
                                CSMOS=POROS*(1.0D0-SETA)*BETA*GAMA*((BETA*HWATR)**(GAMA-1.0D0))         &
                                    /(GAMAW*VALUE*VALUE)*100.0D0  !  (M)
                                !        csmos=poros/gamaw
                            END IF
                        END IF
                        if (SATUR.GT.1.0.OR.SATUR.LT.0.0) THEN
                            PRINT *, 'PWATR= ', PWATR
                            PRINT *, 'SATUR=0 AND CSMOS=0'
                            SATUR=0.0D0
                            CSMOS=0.0D0
                        END IF
                        if (CSMOS.LT.0.0) PAUSE '$ PAUSE2 IN PROPTY $ '
                        if (fieldid(1:2)=='UW')  &
                            element(ielem)%egaus(order_int)%satur(igaus)=satur
                        if (intc==0) then
                            element(ielem)%egaus(order_int)%csmos(igaus)=csmos
                            if (fieldid(1:2)=='UW')  &
                                element(ielem)%egaus(order_int)%poros(igaus)=poros
                        endif
                    end do   !! igaus

                    if (fieldid(1:2)=='UW')then
                        if (intc==0) then
                            intc=1
                            order_int1=elkn(index)%couple(1)%intrule_couple(1)
                            if (order_int1/=order_int0)then
                                ngaus =elkn(index)%ggaus(order_int1)%ngaus
                                order_int=order_int1
                                goto 11
                            endif
                        else if(intc==1) then
                            intc=2
                            order_int2=elkn(index)%el_field(1)%order_intrules(1)
                            ngaus =elkn(index)%ggaus(order_int2)%ngaus
                            if (order_int2/=order_int1.and.order_int2/=order_int0) then
                                order_int=order_int2
                                goto 11
                            endif
                        endif
                    endif

                    nullify(lnods)
                end do  !! ielgroup

                deallocate(shape,press)
            endif  !! Soil
        endif  !! appear(igroup)>0&&fieldid(1:2)==UW

    end do !! igroup

    !     WRITE(chkunit,609)
    !  609 FORMAT('******* SATURATION AND PERMEABILITY UPDATED ********')
    END SUBROUTINE  PROPTY
    !
    !
    SUBROUTINE PROPTY_w
    !******************************************************************
    !
    !*** UPDATES POROSITY
    !*** UPDATES SATURATION AND PERMEABILITY
    !
    !******************************************************************
    character(10) fieldid,material
    integer(ink) matno,igroup,ksmsa,ielem,order_int,index,  &
        ngaus,igaus,npmpm, nswpw,ielgroup
    real   (irk) pwatr,dpwat,pnete,permb,pmaxm,hwatr,a,b,alfa   !,gamaw 20230402
    real   (irk), allocatable::pmpwc(:),swpwc(:),pwatp(:),pwats(:)

    DO igroup =1,ngroup
        fieldid=group(igroup)%fieldid
        if (appear(igroup)>0.and.fieldid(1:1)=='W') then
            ! get information from the group level
            matno = group(igroup)%matno
            material=props(matno)%name
            if (material(1:6)=='NSSoil') then
                index = group(igroup)%index
                ksmsa = props(matno)%mechanical%fluid%ksmsa
                ! loop for 1:nelgroup
                DO ielgroup = 1,group(igroup)%nelgroup
                    ielem = group(igroup)%list(ielgroup)
                    !relative permiability
                    order_int=elkn(index)%el_field(1)%order_intrules(1)
                    ngaus = elkn(index)%ggaus(order_int)%ngaus

                    do igaus=1,ngaus

                        pwatr = element(ielem)%egaus(order_int)%pwatr(igaus)
                        if (KSMSA.EQ.0)  PERMB=1.0D0
                        !
                        if (KSMSA.EQ.1) THEN
                            npmpm=props(matno)%mechanical%fluid%npmpm
                            allocate(pmpwc(npmpm),pwatp(npmpm))
                            pwatp=props(matno)%mechanical%fluid%pwatp
                            pmpwc=props(matno)%mechanical%fluid%pmpwc
                            CALL PERMBL (PERMB ,PWATR ,NPMPm ,PWATp,PMPWC )
                            deallocate(pmpwc,pwatp)
                        END IF
                        !
                        if (KSMSA.EQ.2) THEN
                            !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
                            PNETE=PWATR
                            if (PNETE.GE.0.0) THEN
                                PERMB=1.0D0
                            ELSE
                                !      PMAXM=-40.0D0*980.0D0*9.81D0
                                !      permb=1.0D0-(PNETE/PMAXM)**2
                                permb=1.e-3
                            END IF
                        END IF
                        !
                        if (KSMSA.EQ.3.OR.KSMSA.EQ.4.OR.KSMSA.EQ.5.OR.KSMSA.EQ.6) THEN
                            !*** AFTER VAN GENUCHTEN ET AL [1977]
                            !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
                            PNETE=PWATR
                            if (PNETE.Gt.0.0) THEN
                                PERMB=1.0D0
                            ELSE
                                !*** PARAMETERS FOR Sw - Pw CURVE
                                ! GAMAW=980.0D0*9.81D0  20230402
                                HWATR=ABS(PNETE/GAMAW)*100.0D0  ! (CM)
                                !*** PARAMETERS FOR Kw - Pw CURVE
                                A=0.050D0
                                B=4.0D0
                                ALFA=0.90D0
                                PERMB=1.0D0/((1.0D0+(A*HWATR)**B)**ALFA)
                                !       IF(PERMB.LT.0.001D0)  PERMB=0.001D0
                            END IF
                        END IF
                        element(ielem)%egaus(order_int)%permr(igaus)=permb
                    end do   !! igaus for permeability


                    !end relative permiability
                end do  !! ielgroup

            endif  !! Soil
        endif  !! appear(igroup)>0&&fieldid(1:2)==UW

    end do !! igroup

    !     WRITE(chkunit,609)
    !  609 FORMAT('******* SATURATION AND PERMEABILITY UPDATED ********')
    END SUBROUTINE  PROPTY_w
    !
    SUBROUTINE SATURT(SATUR ,CSMOS ,PWATR ,POROS ,NSWPW ,PWATs ,SWPWC)
    !******************************************************************
    !
    !*** EVALUATES SATURATION FROM WATER PRESSURE
    !
    !******************************************************************
    integer(ink) nswpw,npres,mpres,i0
    real(irk) satur,csmos,poros,pwats(:), SWPWC(:),pnete, theta, slopa,slopb  &
        ,pwatr
    !
    !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
    !
    PNETE=PWATR
    if (PNETE.GE.0.0) THEN
        SATUR=1.0D0
        CSMOS=0.0D0
    ELSE
        if ((-pnete).ge.pwats(nswpw)) THEN
            SATUR=SWPWC(NSWPW)
            CSMOS=0.0D0
        elseif((-pnete).le.pwats(1)) THEN
            SATUR=1.0D0
            CSMOS=0.0D0
        else
            do i0=1,nswpw-1
                if (((-pnete).ge.pwats(i0)).and.((-pnete).le.pwats(i0+1)))then
                    THETA=((-pnete)-pwats(i0))/(pwats(i0+1)-pwats(i0))
                    satur=(1.0D0-THETA)*swPWC(i0)+THETA*swPWC(i0+1)
                    SLOPA=(SWPWC(i0)-SWPWC(i0+1))/(pwats(i0+1)-pwats(i0))
                    if ((i0+1)<NSWPW)then
                        SLOPB=(SWPWC(i0+1)-SWPWC(i0+2))/(pwats(i0+2)-pwats(i0+1))
                    else
                        slopb=0.  !2006NS
                    endif
                    CSMOS=POROS*((1.0D0-THETA)*SLOPA+THETA*SLOPB)
                    goto 10
                END IF
            end do
10          continue
        END If
    endif


    END SUBROUTINE SATURT
    !
    SUBROUTINE PERMBL(PERMB ,PWATR ,NPMPW ,pwatp,PMPWC)
    !******************************************************************
    !
    !*** EVALUATES PERMEABILITY FROM WATER PRESSURE
    !
    !******************************************************************
    integer(ink) npmpw,npres,mpres,i0
    real(irk) permb,pwatr,pwatp(:),PMPWC(:),pnete,theta
    !
    !*** CHANGE PORE PRESSURE TO BE NEGATIVE FOR TENSION
    !
    PNETE=PWATR
    if (PNETE.GE.0.0) THEN
        PERMB=PMPWC(1)
    ELSE
        if ((-pnete).ge.pwatp(npmpw)) THEN
            PERMB=PMPWC(NPMPW)
        elseif((-pnete).le.pwatp(1)) THEN
            PERMB=PMPWC(1)
        else
            do i0=1,npmpw-1
                if (((-pnete).ge.pwatp(i0)).and.((-pnete).le.pwatp(i0+1)))then
                    THETA=((-pnete)-pwatp(i0))/(pwatp(i0+1)-pwatp(i0))
                    PERMB=(1.0D0-THETA)*PMPWC(i0)+THETA*PMPWC(i0+1)
                    goto 10
                END IF
            end do
10          continue
        END If
    endif
    END SUBROUTINE PERMBL
    !
    SUBROUTINE CHANGE (VECTR)
    real(irk) tempy,VECTR(:)
    TEMPY=VECTR(4)
    VECTR(4)=VECTR(3)
    VECTR(3)=TEMPY
    RETURN
    END SUBROUTINE CHANGE

    !20220713
    !========================================================
    SUBROUTINE mainsandpz (ielem,matno,nstre,SIGU,SIG,DEPS,DEP,VD,LOADIN,ISW,d,ntest)
    !******************************************************************
    !
    !**** MAIN SUBROUTINE FOR P-Z MODEL
    !
    !******************************************************************
    integer(ink) ielem,loadin,isw,ndiv,ntest,mndiv,icheck,i,matno,nstre,idimn,ndsig,i0
    real   (irk) ctol,ds1,ds2,temp1,p,q,rj2,rj3,theta,    &
        sint3,eta,xmgc,xmfc,etaf,pu,ps,pcut,pk,pf,    &
        plimit,pinc,sinfg,sinff
    real(irk) D(24),SIG(:),sigu(:),DEPS(:),DEP(:,:),VD(:),  VDA(6),VDB(6)
    real(irk), allocatable:: DSIG(:),DEPSE(:),DEPSP(:),SIGA(:), &
        SIGUA(:),DSIGA(:),SIGB(:),SIGUB(:),devia(:),tdsig(:)
    PARAMETER (MNDIV=20,CTOL=0.05)

    allocate(dsig(nstre),depse(nstre),depsp(nstre),siga(nstre),sigua(nstre),  &
        dsiga(nstre),sigb(nstre),sigub(nstre),devia(nstre),tdsig(nstre))
    dsig=0.;depse=0.;depsp=0.;siga=0.;sigua=0.;dsiga=0.;sigb=0.;sigub=0.;devia=0.
    tdsig=0.

    if(isw==1)then   ! go to 1000
        CALL DEPSandPZ(ielem,SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,DEPSP,VD,LOADIN,ISW,matno,nstre)
        deallocate(dsig,depse,depsp,siga,sigua,dsiga,sigb,sigub,devia)
        return
    endif

    !if(isw==2)then
    !write(7,*)'sigu=',sigu
    !write(7,*)'sig=',sig
    !write(7,*)'deps=',deps
    !endif

    if(ntest==1)then
        !**** JUST ADD THE INCREMENT
        dsig=0.
        CALL DEPSandPZ(ielem,SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,DEPSP,VD,LOADIN,ISW,matno,nstre)
        !	if(iblks==7.and.ielem==11)then
        !	write(7,*)'sigu=',sigu
        !	write(7,*)'sig=',sig
        !	endif
    elseif(ntest==2)then
        !**** CONSTANT SUBDIVISION DEPENDING ON THE DIFFERENCE
        !**** NORM: DSIG(DIFF)/(2*DSIG(MEAN))
        tdsig=0.
        siga=sig
        sigua=sigu
        vda=vd
        !if(ielem==1) &
        !write(7,*)'siga=',siga,'sigua=',sigua,'dsig=',dsig
        CALL DEPSandPZ(ielem,SIGUA,SIGA,DEPS,DSIG,DEPSE,D,DEP,DEPSP,VDA,LOADIN,ISW,matno,nstre)

        !if(ielem==1) &
        !write(7,*)'siga1=',siga,'dsig=',dsig

        sigb=siga
        sigub=sigua
        vdb=vda
        CALL DEPSandPZ(ielem,SIGUA,SIGA,DEPS,DSIGA,DEPSE,D,DEP,DEPSP,VDA,LOADIN,ISW,matno,nstre)

        !    if(ielem==1) &
        !write(7,*)'siga2=',siga,'dsig=',dsig


        DS1=0.0
        DS2=0.0

        DO I=1,nstre  !4
            TEMP1=0.500*(DSIG(I)+DSIGA(I))
            DS1=DS1+TEMP1*TEMP1
            TEMP1=0.500*(DSIG(I)-DSIGA(I))
            DS2=DS2+TEMP1*TEMP1
        END DO

        DS1=SQRT(DS1)
        DS2=SQRT(DS2)

        IF(DS1.EQ.0.0) THEN
            NDIV=1
        ELSE
            NDIV=DS2/(CTOL*DS1)+0.99
        END IF

        NDIV=MAX(1,NDIV)
        NDIV=MIN(MNDIV,NDIV)

        !write(7,*)'ndiv=',ndiv
        IF (NDIV/=1)then
            DO I=1,nstre  !4
                DEPS(I)=DEPS(I)/FLOAT(NDIV)
            END DO

            DO I=1,NDIV
                CALL DEPSandPZ(ielem,SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,DEPSP,VD,LOADIN,ISW,matno,nstre)
                tdsig=tdsig+dsig
            END DO
            dsig=tdsig
            !    if(ielem==1) &
            !write(7,*)'tdsig=',tdsig
        else
            sig=sigb
            sigu=sigub
            vd=vdb
        end if

        !    if(ielem==1) &
        !write(7,*)'sig=',sig


        !	DO  I=1,nstre  !4
        !	DEPS(I)=DEPS(I)/40
        !	enddo
        !	DO  I=1,40
        !	CALL DEPSandPZ(SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,DEPSP,VD,LOADIN,ISW,matno,nstre)
        !	enddo
        !	DEPS=DEPS*40
    else
        print *,'ntest only can be 1 or 2. now, ntest=',ntest
    endif

    !**** FORM ETA AND ETAF

    call invart(matno,nstre,devia,sig,theta,q,p,rj2,rj3,sint3)
    ETA=ABS(Q/P)
    sinfg=3*d(3)/(6.+d(3))
    sinff=3*d(5)/(6.+d(5))
    XMGC=6.0*sinfg/(3.0-sinfg*SINT3)
    XMFC=6.0*sinff/(3.0-sinff*SINT3)
    !	XMFC=D(5)*XMGC
    ETAF=(1.0+1.0/D(6))*XMFC

    !goto 222   ！20220728
    if(eta>etaf) then  !1111
        !       if(ielem==1) &
        !write(7,*)'ie=',ielem,'eta=',eta,'etaf=',etaf
        ndsig=1  !20
        do i0=1, ndsig
            sig=sigu+i0*dsig/ndsig
            call invart(matno,nstre,devia,sig,theta,q,p,rj2,rj3,sint3)
            ETA=ABS(Q/P)
            sinfg=3*d(3)/(6.+d(3))
            sinff=3*d(5)/(6.+d(5))
            XMGC=6.0*sinfg/(3.0-sinfg*SINT3)
            XMFC=6.0*sinff/(3.0-sinff*SINT3)
            ETAF=(1.0+1.0/D(6))*XMFC
            if(eta>etaf) then
                sig=sig-dsig/ndsig
                sigu=sig
                call invart(matno,nstre,devia,sig,theta,q,p,rj2,rj3,sint3)
                ETA=ABS(Q/P)
                sinfg=3*d(3)/(6.+d(3))
                sinff=3*d(5)/(6.+d(5))
                XMGC=6.0*sinfg/(3.0-sinfg*SINT3)
                XMFC=6.0*sinff/(3.0-sinff*SINT3)
                ETAF=(1.0+1.0/D(6))*XMFC
                !write(7,*)'i0=',i0,'eta=',eta,'etaf=',etaf
                goto 10
            endif
        end do
        sigu=sig
        !write(7,*)'i0=',i0,'eta=',eta,'etaf=',etaf
    else
        sigu=sig
    endif  !1111
222 sigu=sig

10  continue


    !
    !**** CHECK 1 : AVOID TENSION STATE
    !

    !if(p.le.0.) THEN

    !write(chkunit,*) 'p<0'
    !write(*,*)       'p<0'
    !stop

    !sig=0.
    !sigu=0.
    !      SIG(1)=-1.e-3
    !      SIG(2)=-1.e-3
    !      SIG(3)=-1.e-3
    !      p=1.e-3
    !      IF(SIG(4).LE.0) SIG(4)=ETAF*(-P)/SQRT(3.0)
    !      IF(SIG(4).GT.0) SIG(4)=ETAF*P/SQRT(3.0)



    !	do idimn=1,ndimn	!nzw 3DPZ	2006-06-10
    !	sig(idimn)=-1.e-3
    !	if(sig(idimn+ndimn)<=0.)then
    !	SIG(idimn+ndimn)=ETAF*(-P)/SQRT(3.0)
    !	else
    !	SIG(idimn+ndimn)=ETAF*P/SQRT(3.0)
    !	endif
    !	end do
    !	if(ndimn==2.and.nstre==4)sig(4)=-1.e-3
    !
    !	sigu=sig
    !
    !	deallocate(dsig,depse,depsp,siga,sigua,  &
    !				   dsiga,sigb,sigub,devia)
    !	return
    !endif

    goto 1003

    if(ndimn==3)then
        PU=-(SIGU(1)+SIGU(2)+SIGU(3))/3.0
        PS=-(SIG(1)+SIG(2)+SIG(3))/3.0
    elseif(ndimn==2)then
        PU=-(SIGU(1)+SIGU(2)+SIGU(4))/3.0
        PS=-(SIG(1)+SIG(2)+SIG(4))/3.0
    endif


    IF (PU<=0.0.OR.PS<=0.0) THEN
        PCUT=D(8)
        PLIMIT=1.0D-8*PCUT
        PK=PS-PU
        !if(iblks==7.and.ielem==11)then
        !write(7,*)'sigu=',sigu,'sig=',sig
        !write(7,*)'pu=',pu,'ps=',ps,'d(8)=',d(8),'pk=',pk,'plimit=',plimit
        !endif

        IF (PK>0.0) THEN
            !**** THE SIG IS MORE COMPRESSIVE
            SIGU(1:ndimn)=-PLIMIT
            if(ndimn==2)then
                IF(SIGU(3).LE.0) SIGU(3)=ETAF*(-PLIMIT)/SQRT(3.0)
                IF(SIGU(3).GT.0) SIGU(3)=ETAF*PLIMIT/SQRT(3.0)
                SIGU(4)=-PLIMIT
            elseif(ndimn==3)then
                q=sqrt(sigu(4)**2+sigu(5)**2+sigu(6)**2)    !2007
                if(q<=plimit)sigu(4:6)=-ETAF*PLIMIT/3.0
                if(q> plimit)sigu(4:6)= ETAF*PLIMIT/SQRT(3.0)*sigu(4:6)/q  !2007
            endif

            SIG(1:ndimn)=-PK-PLIMIT
            p=pk+plimit
            if(ndimn==2)then
                IF(SIG(3).LE.0) SIG(3)=ETAF*(-PK-PLIMIT)/SQRT(3.0)
                IF(SIG(3).GT.0) SIG(3)=ETAF*(PK+PLIMIT)/SQRT(3.0)
                SIG(4)=-PK-PLIMIT
            elseif(ndimn==3)then
                q=sqrt(sig(4)**2+sig(5)**2+sig(6)**2)    !2007
                if(q<=plimit)sig(4:6)=-ETAF*PLIMIT/3.0
                if(q> plimit)sig(4:6)= ETAF*(pk+PLIMIT)/SQRT(3.0)*sig(4:6)/q  !2007
            endif

            q=p*etaf
            eta=etaf
            xmgc=6.0*sinfg/3.0
            xmfc=6.0*sinff/3.0
            !		xmfc=d(5)*xmgc
            !	etaf=(1.0+1.0/d(6))*xmfc  !1018
            !if(iblks==7.and.ielem==11)then
            !   write(7,*)'sig=',sig
            !   write(7,*)'sigu=',sigu
            !   write(7,*)'p,eta,xmgc,xmfc=',p,eta,xmgc,xmfc
            !endif
        ELSE
            !**** THE SIGU IS MORE COMPRESSIVE
            SIG(1:ndimn)=-PLIMIT
            if(ndimn==2)then
                IF(SIG(3).LE.0) SIG(3)=ETAF*(-PLIMIT)/SQRT(3.0)
                IF(SIG(3).GT.0) SIG(3)=ETAF*PLIMIT/SQRT(3.0)
                SIG(4)=-PLIMIT
            else
                q=sqrt(sig(4)**2+sig(5)**2+sig(6)**2)    !2007
                if(q<=plimit)sig(4:6)=-ETAF*PLIMIT/3.0
                if(q> plimit)sig(4:6)= ETAF*PLIMIT/SQRT(3.0)*sig(4:6)/q  !2007
            endif
            SIGU(1:ndimn)=PK-PLIMIT
            p=pk+plimit
            if(ndimn==2)then
                IF(SIGU(3).LE.0) SIG(3)=ETAF*(PK-PLIMIT)/SQRT(3.0) !2007
                IF(SIGU(3).GT.0) SIG(3)=ETAF*(-PK+PLIMIT)/SQRT(3.0) !2007
                SIGU(4)=PK-PLIMIT
            else
                q=sqrt(sigu(4)**2+sigu(5)**2+sigu(6)**2)    !2007
                if(q<=plimit)sig(4:6)= ETAF*(pk-PLIMIT)/3.0
                if(q> plimit)sig(4:6)= ETAF*(-pk+PLIMIT)/SQRT(3.0)*sigu(4:6)/q  !2007
            endif
            q=p*etaf
            eta=etaf
            xmgc=6.0*sinfg/3.0
            xmfc=6.0*sinff/3.0
            !		xmfc=d(5)*xmgc
            !	etaf=(1.0+1.0/d(6))*xmfc   !1018
        END IF
    END IF

1003 continue

    !**** CHECK 2 : KEEP ETA < ETAF
    !if(iblks==7.and.ielem==11)write(7,*)'eta,etaf=',eta,etaf
    !IF(ETA.GT.ETAF) THEN
    !	PF=ABS(Q/ETAF)
    !	PINC=PF-P
    !	do idimn=1,ndimn	!nzw 3DPZ	2006-06-10
    !		sig(idimn)=sig(idimn)-pinc
    !		SIGU(idimn)=SIGU(idimn)-PINC
    !	end do
    !	if(ndimn==2.and.nstre==4)sig(4)=sig(4)-pinc
    !	if(ndimn==2.and.nstre==4)sigu(4)=sigu(4)-pinc
    !END IF
    deallocate(dsig,depse,depsp,siga,sigua,dsiga,sigb,sigub,devia,tdsig)

    !if(iblks==7.and.ielem==11.and.isw==2)then
    !write(7,*)'Nsigu=',sigu
    !write(7,*)'Nsig=',sig
    !endif

    END SUBROUTINE mainsandpz
    !====================================================================
    SUBROUTINE DEPSandPZ(ielem,SIGU,SIG,DEPS,DSIG,DEPSE,D,DEP,     &
        DEPSP,VD,LOADIN,ISW,matno,nstre)
    !******************************************************************
    !
    !**** SUBROUTINE DEPMDL FOR P-Z MODEL
    !
    !******************************************************************
    !-------------------------------------------------------------------
    !     D(24) IS THE ARRAY FOR THE GENERAL MATERIAL PARAMETERS OF
    !            THE SOIL TYPE
    !     SIG(4) THIS IS THE EFFECTIVE STRESS WHICH THE DEP MATRIX
    !            DEPENDS UPON
    !     DSIG(4) THE INCREMENTAL STRESS CALCULATED BY THE SUBROUTINE
    !             DUE TO THE PRESENT STRESS STATE AND DEPS(4)
    !     DEP(4,4) THE ELASTOPLASTIC D MATRIX AND DSIG=DEP*DEPS
    !     DEPS(4) THE INCREMENTAL STRAIN
    !     DE THE ELASTIC D MATRIX
    !     DSIGE(4) THE TRIAL STRESS INCREMENT DSIGE=DE*DEPS
    !     DEPSE(4) THE ELASTIC PART OF THE INCREMENTAL STRAIN
    !               DEPSE=DSIG/DE
    !     DEPSP(4) THE PLASTIC PART OF THE INCREMENTAL STRAIN
    !     DEVIA(4) THE DEVIATORIC STRESS CALCULATED FROM DSIG
    !     A1(4) THE A-VECTOR FOR THE I1
    !     A2(4) THE A-VECTOR FOR THE SQRT(3J2) = Q
    !           A-VECTOR IS D(SQRT(3J2))/DSIG
    !     A3(4) THE A-VECTOR FOR THE LODE ANGLE
    !     VN(4) THE N-VECTOR FOR THE LOADING DIRECTION DETERMINATION
    !     VNG(4) THE NG-VECTOR USED IN BOTH LOADING/UNLOADING CASE
    !     SIGU(4) THE MODIFIED EFFECTIVE STRESS, IT IS NOT REFERENCED IN
    !             THIS SUBROUTINE EXCEPT FOR UPDATING PURPOSE
    !     TEMP1(4) TEMP1=DEM*VNG
    !     TEMP2(4) TEMP2=DEM*VN
    !     VD(5) THE LOCAL VARIABLES FOR THE GAUSS POINT
    !-----------------------------------------------------------------------
    integer(ink) ielem,isw,icheck,icels,kload0,loadin,i,j,matno,nstre,idimn,jdimn,pztype,jload,isat
    real   (irk) p,q,rj2,rj3,theta,sint3,xmgc,xmfc,etaf,eta,pcut,    &
        plimit,pf,pinc,ri1,p0,prefv,prefs,pmax,bulk,shearm, &
        xnu,e,econs1,econs2,econs3,direct,direc1,etarl, &
        etamax,const11,eqp,fact1,fact2,expf,factv,facts,    &
        factdm,h,hcut,hmid,pcut1,const1,const2,const3, &
        deqp,devp,steff,smean,vj2,vj3,smax,qmax,ps(3),s

    real   (irk) sinfg,sinff,tt,ttmax,dirtol
    character*10 sptype,model

    real(irk) D(24),SIG(:),DEPS(:),DSIG(:),DEPSE(:),DEP(:,:),     &
        DEPSP(:),SIGU(:),    VD(:)
    real(irk), allocatable:: DEVIA(:),A1(:),A2(:),A3(:),VN(:),  &
        VNG(:),DSIGE(:),TEMP1(:),TEMP2(:),dmatx(:,:)
    !-----------------------------------------------------------------------
    !  1. DIRTOL: THE TOLERCANCE USED TO DETERMINE THE ANGLE OF
    !             THE NEUTRAL LOADING ZONE, IF THIS IS NOT USED
    !             A ROUND-OFF ERROR WILL DETERMINE THE LOADING
    !             UNLOADING DIRECTION WHICH MAY NOT BE CORRECT
    !             IN THIS SUBROUTINE, ONCE THE LOADING/UNLOADING
    !             DIRECTION IS DETERMINED FOR ONE TIME STEP
    !             IT WILL NOT BE ALTERED.
    !  2. PLIMIT THIS IS THE LOWEST CONFINING PRESSURE THAT SHOULD
    !     BE ATTAIN BY A GAUSS POINT
    !-----------------------------------------------------------------------
    !     parameter( DIRTOL=4.0D-5)
    DIRTOL=4.0D-5
    !-----------------------------------------------------------------------
    !  1. LOADIN:    +1 FOR LOADING, ONCE LOADING ALWAYS LOADING-DEP
    !                 0 NOT YET DECIDED (FIRST ITERATION OR PREVIOUS
    !                                    ITERATIONS ARE ELASTIC
    !                 -1 FOR UNLOADING, ONCE UNLOADING ALWAYS UNLOADING-DEP
    !
    !  2. SIGU(4) STANDS FOR THE STRESS STATE TO BE UPDATED
    !     SIG (4) IS THE STRESSES FOR THE DEP EVALUATION
    !     (IN SATURATED SOIL, THIS IS THE EFFECTIVE STRESS STATE)
    !------------------------------------------------------------------------
    !
    !**** FORM ETAF AND ETA (FIRST TIME)
    !
    allocate(devia(nstre),a1(nstre),a2(nstre),a3(nstre),vn(nstre),  &
        vng(nstre),dsige(nstre),temp1(nstre),temp2(nstre),dmatx(nstre,nstre))
    devia=0.;a1=0.;a2=0.;a3=0.;vn=0.;vng=0.;dsige=0.;temp1=0.;temp2=0.;dmatx=0.

    pztype=props(matno)%mechanical%solid%SandPZ%pztype

    call invart(matno,nstre,devia,sig,theta,q,p,rj2,rj3,sint3)

    sinfg=3*d(3)/(6.+d(3))
    sinff=3*d(5)/(6.+d(5))



    XMGC=6.0*sinfg/(3.0-sinfg*SINT3)
    XMFC=6.0*sinff/(3.0-sinff*SINT3)

    RI1=-P
    ETA=ABS(Q/P)
    ETAF=(1.0+1.0/D(6))*XMFC  ! nzw PHD Thesis, (3.8.28a)


    !**** CHECK 1: AVOID TENSION STATE
    ICHECK=1  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    goto 333  !1030tcl
    !IF(ICHECK.EQ.0) go to 666  !1030tcl
    PCUT=D(8)
    PLIMIT=1.0D-8*PCUT
    IF (P.LE.0.0) THEN

        !	p=plimit
        !	do idimn=1,ndimn	!nzw 3DPZ	2006-06-10
        !		sig(idimn)=-PLIMIT
        !		if(sig(idimn+ndimn)<=0.)then
        !			SIG(idimn+ndimn)=ETAF*(-PLIMIT)/SQRT(3.0)
        !		else
        !			SIG(idimn+ndimn)=ETAF*PLIMIT/SQRT(3.0)
        !		endif
        !	end do
        !	if(ndimn==2.and.nstre==4)sig(4)=-PLIMIT

        SIG(1:ndimn)=-PLIMIT
        p=plimit
        if(ndimn==2)then
            IF(SIG(3).LE.0) SIG(3)=ETAF*(-PLIMIT)/SQRT(3.0)  !need to be modified-2007
            IF(SIG(3).GT.0) SIG(3)=ETAF*PLIMIT/SQRT(3.0)     !need to be modified-2007
            SIG(4)=-PLIMIT
        elseif(ndimn==3)then
            q=sqrt(sig(4)**2+sig(5)**2+sig(6)**2)    !2007
            sig(4:6)=ETAF*PLIMIT/SQRT(3.0)*sig(4:6)/q  !2007
        endif

        q=p*etaf
        eta=etaf
        xmgc=6.0*sinfg/3.0
        xmfc=6.0*sinff/3.0
        etaf=(1.0+1.0/d(6))*xmfc            ! nzw PHD Thesis, (3.8.28a)
    END IF

333 continue !1030tcl
    !**** CHECK 2: KEEP ETA < ETAF
    !IF (ETA.GT.ETAF) THEN
    !  write(7,*)'ie eta>etaf in deppz=',ielem,'eta=',eta,'etaf=',etaf
    !	write(7,*)'isw=',isw
    !	write(7,*)'sig=',sig
    !	PF=ABS(Q/ETAF)
    !	PINC=PF-P
    !	do idimn=1,ndimn	!nzw 3DPZ	2006-06-10
    !	sig(idimn)=sig(idimn)-pinc
    !	end do
    !	if(ndimn==2.and.nstre==4)sig(4)=sig(4)-pinc
    !END IF

    !
    !**** FORM INVARIANTS AND ETA (SECOND TIME) , ETAF IS NOT CHANGED !
    !

    !	call invart(matno,nstre,devia,sig,theta,q,p,rj2,rj3,sint3)

666 continue
    RI1=-P
    ETA=ABS(Q/P)
    !
    !**** SINCE THE MODEL HAS A SINGULARITY AT PURE COMRESSION
    !     THE ETA IS SLIGHTLY MODIFIED

    IF (ETA.LT.0.000100)ETA=0.000100

    !**** FIND THE ELASTIC CONSTANTS (CHECK IF THEY ARE VARIABLE WITH P

    P0=VD(5)
    PREFV=P0
    PREFS=P0
    ICELS=D(15)+0.5
    PCUT=D(8)
    PMAX=1.0D+7
    IF (ICELS.EQ.0.OR.ICELS.EQ.2) PREFV=MIN(P,PMAX)
    IF (ICELS.EQ.0.OR.ICELS.EQ.1) PREFS=MIN(P,PMAX)
    IF (ICELS.EQ.0.OR.ICELS.EQ.2) PREFV=MAX(P,PCUT)
    IF (ICELS.EQ.0.OR.ICELS.EQ.1) PREFS=MAX(P,PCUT)

    if(pztype==11)then  !get e and xnu with DC model
        model=props(matno)%mechanical%solid%DuncanChang%model

        !    CALL invart (matno,nstre,devia,sig,theta,steff,smean,vj2,vj3,sint3)
        steff=steff/sqrt(3.d0);smean=-smean   !因PZ材料在invart子程序里求p、q时与常规不太一样

        smax=0.0;qmax=0.0;ps=0.
        if(model=='EV'.or.model=='CR') then
            call DUNE(matno,smean,steff,theta,smax,Qmax,s,e,ps(3))   !20220718
            call DUNV(matno,smean,s,xnu)
        elseif(model=='EB') then
            isat=0
            call EBMOD(isat,matno,smean,steff,theta,smax,Qmax,s,e,xnu,ps(3))
        endif
    elseif(pztype==12)then    ! get e and xnu with PZ model
        BULK=D(1)*PREFV
        SHEARM=D(2)*PREFS/3.0D0
        XNU=(3.0*BULK-2.0*SHEARM)/(6.0*BULK+2.0*SHEARM)
        E=3.0*BULK*(1.0-2.0*XNU)
    else    ! get e and xnu with PZ model
        BULK=D(1)*p/P0
        SHEARM=D(2)*p/P0   !/3.0D0

        XNU=(3.0*BULK-2.0*SHEARM)/(6.0*BULK+2.0*SHEARM)
        E=3.0*BULK*(1.0-2.0*XNU)
    endif


    !**** FORM THE ELASTIC ELASTICITY MATRIX DE
    ECONS1=E*(1.0-XNU)/((1.0+XNU)*(1.0-2.0*XNU))
    ECONS2=ECONS1*XNU/(1.-XNU)
    ECONS3=ECONS1*(1.-2.*XNU)*0.5/(1.-XNU)

    !**** FORM THE A-VECTORS IN ORDER TO CALCULATE THE N AND NG VECTORS
    CALL FAVMDL(nstre,A1,A2,A3,DEVIA,RJ2,RJ3,THETA,RI1)  !20220718

    !**** FORM THE N-VECTOR
    CALL FNVMDL(nstre,d(6),RI1,XMFC,RJ2,THETA,sinff,A1,A2,A3,VN,1)

    !**** FORM THE ELASTIC STRESS INCREMENT DEFINED AS DSIGE=DE*DEPS
    if(ISW==1)sptype='PE'
    if(ISW==2)sptype='PE'
    call ecmat(sptype,dmatx,e,xnu)

    DSIGE=(dmatx.x.deps)
    !	if(iblks==7.and.ielem==11)write(7,*)'sige=',dsige

    !**** CHECK LOADING OR UNLOADING
    KLOAD0=LOADIN

    !**** FORMING NT.DE.DEPS FOR DIRECTION DETERMINATION
    !**** FIND THE COSINE BETWEEN THE TWO VECTORS (ACTUALLY BOTH ARE TENSORS)
    DIRECT=VN.d.DSIGE
    DIREC1=SQRT(dot_product(DSIGE,DSIGE)*dot_product(VN,VN))

    IF (DIREC1.NE.0.0) THEN
        DIRECT=DIRECT/DIREC1
    ELSE
        IF (DIRECT.NE.0.0) THEN
            STOP 'STOP IN DEPMDL'
        END IF
    END IF


    !以下求nzw PHD Thesis,P79, (3.8.27)中的eatmax
    tt=1.-d(4)*eta/d(3)/(1.+d(4))
    if(tt.le.0.) then
        tt=0.
    else
        tt=tt**(-1./d(4))
    endif
    tt=p*tt
    vd(3)=max(tt,vd(3))
    !------------------------------------------------------------------
    LOADIN=0
    IF (DIRECT.GT.DIRTOL) LOADIN=1
    IF (DIRECT.LT.-DIRTOL) LOADIN=-1

    if(eta>=etaf)eta=.99*etaf   !!1115tcl

    jload=loadin
    !	if(isw==1.and.type_nl==4)jload=0
    if(jload>0)then		!nzw 2006-04-18
        !**** FORM THE LOADING NG VECTOR
        CALL FNVMDL(nstre,D(4),RI1,XMGC,RJ2,THETA,sinfg,A1,A2,A3,VNG,1)
        FACT1=P
        PCUT1=PCUT*1.0E-8
        FACT1=MAX(P,PCUT1)
        FACT1=MIN(P,PMAX)

        EXPF=d(14)
        IF(ETA.GE.ETAF) THEN ! because a little error
            FACT2=0.0
        ELSE
            FACT2=(1.-ETA/ETAF)**EXPF       ! nzw PHD Thesis P79, some of (3.8.27)
        END IF

        FACTV=1.0-ETA/XMGC                  ! nzw PHD Thesis P79, (3.8.28b)

        EQP=VD(1)			!累积偏应变
        IF(EQP.EQ.0.0) THEN
            FACTS=d(9)*d(10)
        ELSE
            FACTS=d(9)*d(10)*EXP(-d(9)*ABS(EQP))    ! nzw PHD Thesis P79, (3.8.28c)
        END IF

        ETAMAX=VD(3)		!历史上的最大偏应变
        tt=1.-d(4)*eta/d(3)/(1.+d(4))
        if(tt.le.0.) then
            tt=0.
            FACTDM=1.
        else
            tt=tt**(-1./d(4))
            tt=p*tt
            ttmax=vd(3)
            FACTDM=(ttmax/tt)**d(11)       ! nzw PHD Thesis P79, some of (3.8.27)
        endif

        H=d(7)*FACT1*FACT2*(FACTV+FACTS)*FACTDM     ! nzw PHD Thesis P79, (3.8.27)

        HCUT=E*1.0E-06
        Hmid=MAX(abs(H),HCUT)     !!!97
        H=sign(hmid,h)            !!!97

        !**** FORM THE ADDITIVE FACTOR FOR H
        TEMP1=dmatx.x.VNG

        !**** CONST1=NG  DE N
        CONST1=TEMP1.d.VN
        TEMP2=dmatx.x.VN
        const11=h+const1
        if(abs(const11).le.hcut) const11=sign(hcut,const11)  !!!97
        CONST2=1.0/CONST11

        !**** FORM THE DEP AND DSIG
        IF(isw.eq.1) THEN
            DEP=0.0
            do idimn=1,nstre
                do jdimn=1,nstre
                    dep(idimn,jdimn)=dmatx(idimn,jdimn)-const2*temp1(idimn)*temp2(jdimn)
                end do
            end do
            deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2,dmatx)
            RETURN
        END IF

        CONST2=CONST2*DOT_product(DEPS,TEMP2)
        dsig=dsige-const2*temp1
    elseif(jload<0)then  !nzw 2006-04-18
        !**** UPDATE Hu WHEN REVERSAL

        ETARL=ETA/XMGC
        if(etarl<=0.01)then
            VD(2)=d(12)*0.0001**(-1.0*d(13))
        elseif(etarl>=1.0)then
            VD(2)=D(12)
        else
            VD(2)=d(12)*ETARL**(-1.0*d(13))    ! nzw PHD Thesis P80, (3.8.30)
        endif
        !	if(q.lt.0.)then
        !	    vd(2)=vd(2)*d(16)          !modify unloading module
        !	endif
        H=VD(2)


        !**** FORM THE UNLOADING NG VECTOR
        CALL FNVMDL(nstre,d(4),RI1,XMGC,RJ2,THETA,sinfg,A1,A2,A3,VNG,2)
        !
        !**** FORM THE ADDITIVE FACTOR FOR H
        !**** CONST1=NG  DE N

        TEMP1=dmatx.x.VNG
        CONST1=DOT_product(TEMP1,VN)

        TEMP2=dmatx.x.VN
        const11=h+const1
        if(abs(const11).le.hcut) const11=sign(hcut,const11)
        CONST2=1.0/CONST11
        !**** FORM THE DEP AND DSIG

        !-----------------------------------------------------!HMS
        IF(isw.eq.1) THEN
            DEP=0.0
            do idimn=1,nstre
                do jdimn=1,nstre
                    dep(idimn,jdimn)=dmatx(idimn,jdimn)-const2*temp1(idimn)*temp2(jdimn)
                end do
            end do
            deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2,dmatx)
            RETURN
        END IF
        !--------------------------------------------------!HMS
        !
        CONST2=CONST2*DOT_product(DEPS,TEMP2)
        dsig=dsige-temp1*const2
    elseif(jload==0)then

        !------------------------------------------------!HMS
        IF(isw.eq.1) THEN
            dep=0.
            dep=dmatx
            deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2,dmatx)
            RETURN
        END IF
        !------------------------------------------------!HMS
        dsig=dsige
        depse=deps
    else
        print *,'ERROR LOADIN=',loadin
        stop
    end if

    CONST1=1.0/E
    CONST2=-XNU*CONST1
    CONST3=2.0*(1.0+XNU)*CONST1

    !**** FORM THE ELASTIC STRAIN INCREMENT FROM THE INCREMENTAL STRESS GIVEN

    IF (jload/=0) THEN
        DEPSE(1)=CONST1*DSIG(1)+CONST2*(DSIG(2)+DSIG(3))
        DEPSE(2)=CONST1*DSIG(2)+CONST2*(DSIG(3)+DSIG(1))
        DEPSE(3)=CONST1*DSIG(3)+CONST2*(DSIG(1)+DSIG(2))
        do idimn=1,ndimn
            DEPSE(idimn+ndimn)=CONST3*DSIG(idimn+ndimn)
        end do
        if(ndimn==2.and.nstre==4) DEPSE(4)=CONST1*DSIG(4)+CONST2*(DSIG(1)+DSIG(2))
    END IF
    !    if(iblks==7.and.ielem==11.and.ielem==11)write(7,*)'dsig=',dsig


    DO I=1,nstre !4
        SIG (I)=SIG (I)+DSIG(I)
        SIGU(I)=SIGU(I)+DSIG(I)   !1111tcl  !20220726
        DEPSP(I)=DEPS(I)-DEPSE(I)
    end do

    IF(ISW.EQ.2) THEN
        CALL RINMDL(DEPSP,DEVP,DEQP,A1,A2)
        !	if(ndimn==2)then
        !	DEQP=sqrt(2./3.)*sqrt(DEPSP(1)**2+DEPSP(2)**2+DEPSP(4)**2+2.*DEPSP(3)**2)
        !	else
        !	DEQP=sqrt(2./3.)*sqrt(DEPSP(1)**2+DEPSP(2)**2+DEPSP(3)**2+2.*(DEPSP(4)**2+DEPSP(5)**2+DEPSP(6)**2))
        !	endif
        VD(1)=VD(1)+ABS(DEQP)
    END IF
    deallocate(devia,a1,a2,a3,vn,vng,dsige,temp1,temp2,dmatx)

    END  SUBROUTINE DEPSandPZ

    !20220713

    !ifs 2006
    SUBROUTINE stiff_ifs2006

    character(100)text
    integer(ink) tedge,iedge,sedge,nnode,index,ikind,edimn,ngaus,inode,i0,ig,ipoin,jedge,    &
        idimn,bkind,ievab,idofn,ndof,selem,igroup,ielem,imats,jdimn,order_int,aqu_group,      &
        iidofn,jevab,jgroup,jelem,igaus,jnode,nptwd,xdir,zdir,nsect,npseczx,npsecxz,i1,i2  !20220330
    real   (irk) djacb,weigp,aa,yx,dens,c,dvolu,coefsymetry,addmwp(2)
    integer(ink),allocatable::lnods(:)
    real   (irk),allocatable::shape(:),cartd(:,:),deriv(:,:),s(:,:),rr(:,:),a3(:),elcod(:,:), &
        elcod0(:,:),cnd(:),normal(:),rotation(:,:),ax(:),xxxx(:,:),xjaci(:,:),     &
        l(:,:),matrix(:,:)

    !Icaddmass=1:重力坝动水压力附加质量；Icaddmass=2: 渡槽动水压力附加质量+动水压力
    if(Icaddmass/=0)then
        allocate(addmp(ndimn,npoin),icmp(npoin))
        addmp=0.
        icmp=0
    endif
    if(Icaddmass>=2)then !20220330
        read(mwaqu_unit,*)text
        read(mwaqu_unit,*)aqu_group,nptwd,xdir,zdir,nsect,npseczx,npsecxz
        read(mwaqu_unit,*)text
        do i0=1,nptwd
            read(mwaqu_unit,*)i1,ipoin,addmwp(:)
            icmp(ipoin)=1
            addmp(xdir,ipoin)=addmwp(1)
            addmp(zdir,ipoin)=addmwp(2)
        end do
        !write(chk_unit,*)'section pressure x to z'
        allocate(dwpre_aqu)
        dwpre_aqu%aqu_group=aqu_group
        dwpre_aqu%xdir=xdir;dwpre_aqu%zdir=zdir;dwpre_aqu%nsect=nsect
        dwpre_aqu%npseczx=npseczx;dwpre_aqu%npsecxz=npsecxz
        allocate(dwpre_aqu%listp_seczx(npseczx,nsect),dwpre_aqu%listp_secxz(npsecxz,nsect), &
            dwpre_aqu%pzx(npseczx,nsect),dwpre_aqu%pxz(npsecxz,nsect),dwpre_aqu%jnode(nsect))

        allocate(dwpre_aqu%ldofszx(npseczx*nsect),dwpre_aqu%ldofsxz(npsecxz*nsect))
        allocate(dwpre_aqu%eloadzx(npseczx*nsect),dwpre_aqu%eloadxz(npsecxz*nsect))
        dwpre_aqu%eloadzx=0.;dwpre_aqu%eloadxz=0.

        read(mwaqu_unit,*)text
        read(mwaqu_unit,*)dwpre_aqu%jnode
        read(mwaqu_unit,*)text
        do i0=1,nsect
            do i1=1,npseczx
                read(mwaqu_unit,*)i2,ipoin,dwpre_aqu%listp_seczx(i1,i0),dwpre_aqu%pzx(i1,i0)
            end do
        end do

        idofn=0
        do i0=1,nsect
            do i1=1,npseczx
                idofn=idofn+1
                ipoin=dwpre_aqu%listp_seczx(i1,i0)
                dwpre_aqu%ldofszx(idofn)=nodfn(zdir,ipoin)
            end do
        end do


        read(mwaqu_unit,*)text
        print *,text
        do i0=1,nsect
            do i1=1,npsecxz
                read(mwaqu_unit,*)i2,ipoin,dwpre_aqu%listp_secxz(i1,i0),dwpre_aqu%pxz(i1,i0)
                !print *,'i0=',i0,'i1=',i1,'dwpre_aqu%listp_secxz(i1,i0),dwpre_aqu%pxz(i1,i0)=',  &
                !    dwpre_aqu%listp_secxz(i1,i0),dwpre_aqu%pxz(i1,i0)
            end do
        end do

        idofn=0
        do i0=1,nsect
            do i1=1,npsecxz
                idofn=idofn+1
                ipoin=dwpre_aqu%listp_secxz(i1,i0)
                dwpre_aqu%ldofsxz(idofn)=nodfn(xdir,ipoin)
            end do
        end do


    endif !20220330

    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_ifs2006_title_1,0)
    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)ifsnedge
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_ifs2006_ifs_edge_count,0)
    print *,text
    print *,'ifsnedge=',ifsnedge

    if (ifsnedge==0) return
    allocate(ifsedges(ifsnedge))
    tedge=0
    do while(tedge<ifsnedge)
        read(ifsunit,*)text
        read(ifsunit,*)sedge,nnode,index,bkind

        edimn=elkn(index)%ndimn
        !order_int=elkn(index)%el_field(1)%order_intrules(2)
        order_int=elkn(index)%el_field(1)%order_intrules(1) !for icaddmass nnode==ngaus
        ngaus=elkn(index)%ggaus(order_int)%ngaus

        do iedge=1,sedge

            tedge=tedge+1
            ifsedges(tedge)%nnode=nnode
            ifsedges(tedge)%ndimn=edimn
            ifsedges(tedge)%ngaus=ngaus
            ifsedges(tedge)%bkind=bkind
            ifsedges(tedge)%index=index
            ifsedges(tedge)%order_int=order_int
            allocate(ifsedges(tedge)%lnods(nnode))
            if (bkind==2)read(ifsunit,*)i0,ifsedges(tedge)%lnods(1:nnode),ifsedges(tedge)%felem,ifsedges(tedge)%selem
            if (bkind/=2)read(ifsunit,*)i0,ifsedges(tedge)%lnods(1:nnode),ifsedges(tedge)%felem
        enddo
    enddo

    do iedge=1,ifsnedge
        index=ifsedges(iedge)%index
        nnode=ifsedges(iedge)%nnode
        bkind=ifsedges(iedge)%bkind
        edimn=ifsedges(iedge)%ndimn
        ngaus=ifsedges(iedge)%ngaus
        order_int=ifsedges(iedge)%order_int
        allocate(ifsedges(iedge)%edgegaus(ngaus))
        allocate(lnods(nnode),elcod(nnode,edimn+1))
        lnods=0 ; elcod=0.
        lnods=ifsedges(iedge)%lnods
        do inode=1,nnode
            elcod(inode,:)=coord(:,lnods(inode))
        end do
        allocate(shape(nnode),deriv(edimn,nnode),cartd(edimn,nnode))
        allocate(s(edimn+1,edimn+1),a3(edimn+1),elcod0(edimn,nnode))
        allocate(rr(ndimn,ndimn),normal(ndimn),xjaci(edimn,edimn))
        normal=0. ; shape=0. ; deriv=0. ; cartd=0. ; s=0. ; a3=0. ; elcod0=0. ; rr = 0.

        do ig=1,ngaus

            allocate(ifsedges(iedge)%edgegaus(ig)%cartd(edimn,nnode),       &
                ifsedges(iedge)%edgegaus(ig)%shape(nnode),             &
                ifsedges(iedge)%edgegaus(ig)%rotation(edimn+1,edimn+1),&
                ifsedges(iedge)%edgegaus(ig)%normal(edimn+1),          &
                ifsedges(iedge)%normal(edimn+1))

            shape=elkn(index)%ggaus(order_int)%shape(:,ig)
            deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
            weigp=elkn(index)%ggaus(order_int)%weigp(ig)

            ifsedges(iedge)%edgegaus(ig)%shape=shape

            s(1:edimn,:)=MATMUL(deriv,elcod)
            if  ((edimn+1).eq.3) then
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
            normal=normal+a3
            ifsedges(iedge)%edgegaus(ig)%normal=a3
            call cosc(edimn+1,a3,elcod0,elcod,rr)
            call jacob(iedge, edimn, nnode,elcod0,deriv,cartd, djacb,xjaci)

            ifsedges(iedge)%edgegaus(ig)%djacb   =djacb*weigp
            ifsedges(iedge)%edgegaus(ig)%cartd   =cartd
            ifsedges(iedge)%edgegaus(ig)%rotation=transpose(rr)

        end do !!ig

        ifsedges(iedge)%normal=normal/ngaus
        iidofn=lmdofn(8)
        if  (bkind/=2)then
            allocate(ifsedges(iedge)%ldofs(nnode),ifsedges(iedge)%eload(nnode))
            ifsedges(iedge)%eload=0.
            idofn=0
            do inode=1,nnode
                idofn=idofn+1
                ifsedges(iedge)%ldofs(idofn)=nodfn(iidofn,lnods(inode))
            enddo
        endif
        if  (bkind==2)then
            selem=ifsedges(iedge)%selem
            igroup=element(selem)%group
            ndof=group(igroup)%dof(1)%nfdof !special
            allocate(ifsedges(iedge)%eload(nnode*(ndof+1)),ifsedges(iedge)%ldofs(nnode*(ndof+1)), &
                ifsedges(iedge)%ldofs_s(nnode*ndof),ifsedges(iedge)%ldofs_f(nnode))
            ifsedges(iedge)%eload=0.

            do inode=1,nnode
                do idimn=1,ndof
                    idofn=(inode-1)*ndof+idimn
                    ifsedges(iedge)%ldofs_s(idofn)=nodfn(idimn,lnods(inode))
                enddo
            enddo
            do inode=1,nnode
                ifsedges(iedge)%ldofs_f(inode)=nodfn(iidofn,lnods(inode))
            enddo
            ifsedges(iedge)%ldofs(1:nnode*ndof)=ifsedges(iedge)%ldofs_s
            ifsedges(iedge)%ldofs(nnode*ndof+1:nnode*(ndof+1))=ifsedges(iedge)%ldofs_f
        endif

        deallocate (shape,deriv,cartd,s,a3,elcod0,elcod,lnods,rr,normal,xjaci)
    enddo

    ! ifs2006 Icaddmass  !modify by Li 20220330


    !write(7,*)'addtional mass matrix'   !2017/04/16
    if(Icaddmass>=1) then  !（面板坝、重力坝、拱坝规范算法）!20220330
        allocate(ax(npoin),norp(ndimn,npoin),xxxx(ndimn,ndimn),l(ndimn,1))
        ax=0. ; norp=0. ;  xxxx=0. ; l=0.
        do iedge=1,ifsnedge !iedge
            bkind=ifsedges(iedge)%bkind
            if (bkind/=2)cycle
            ngaus=ifsedges(iedge)%ngaus
            nnode=ifsedges(iedge)%nnode
            ielem=ifsedges(iedge)%felem
            igroup=element(ielem)%group
            imats =matno_process(igroup,1)
            dens  =props(imats)%mechanical%fluid%density
            allocate(lnods(nnode))
            lnods=ifsedges(iedge)%lnods
            do inode=1,nnode
                ipoin=lnods(inode)
                ax(ipoin)=ax(ipoin)+ifsedges(iedge)%edgegaus(inode)%djacb !nnode==ngaus
                norp(:,ipoin)=norp(:,ipoin)+ifsedges(iedge)%normal
                icmp(ipoin)=icmp(ipoin)+1
            enddo
            deallocate(lnods)
        enddo

        do ipoin=1,npoin
            if (icmp(ipoin)==0)cycle
            norp(:,ipoin)=norp(:,ipoin)/icmp(ipoin)
            if (ifswater>0)yx=swlifs2006-coord(ifswater,ipoin)
            if (ifswater<0)yx=coord(ifswater,ipoin)-swlifs2006
            if (yx<0)yx=0.
            !addmp(:,ipoin)=7.0/8.0*dens*ax(ipoin)*sqrt(toth*yx) !*norp(:,ipoin)
            l(:,1)=norp(:,ipoin)
            xxxx=matmul(l,transpose(l))
            do idimn=1,ndimn
                l(idimn,1)=0
                do jdimn=1,ndimn
                    l(idimn,1)=l(idimn,1)+xxxx(idimn,jdimn)
                enddo
            enddo
            do idimn=1,ndimn
                addmp(idimn,ipoin)=7.0/8.0*dens*ax(ipoin)*sqrt(toth*yx)*xxxx(idimn,idimn)
            enddo
            !write(7,10)ipoin, addmp(:,ipoin)

        enddo

        !10 format(i10,3f25.5)
        deallocate(ax,xxxx,l)
    endif  ! !20220330

    do iedge=1,ifsnedge !iedge
        index=ifsedges(iedge)%index
        nnode=ifsedges(iedge)%nnode
        bkind=ifsedges(iedge)%bkind
        ngaus=ifsedges(iedge)%ngaus
        edimn=ifsedges(iedge)%ndimn
        ielem =ifsedges(iedge)%felem
        igroup=element(ielem)%group
        if (bkind==2)then
            jelem=ifsedges(iedge)%selem
            jgroup=element(jelem)%group
            ndof=group(jgroup)%dof(1)%nfdof !special
        endif

        imats=matno_process(igroup,1)
        c     =props(imats)%mechanical%fluid%c
        dens  =props(imats)%mechanical%fluid%density

        if (bkind==2)allocate(matrix(nnode,nnode*ndof))
        if (bkind/=2)allocate(matrix(nnode,nnode))
        allocate(shape(nnode),cartd(edimn,nnode),normal(ndimn))
        shape=0. ; cartd=0. ; normal=0.
        matrix=0.

        do igaus=1,ngaus
            shape   =ifsedges(iedge)%edgegaus(igaus)%shape
            cartd   =ifsedges(iedge)%edgegaus(igaus)%cartd
            dvolu   =ifsedges(iedge)%edgegaus(igaus)%djacb
            normal  =ifsedges(iedge)%edgegaus(igaus)%normal

            if  (bkind==2)then
                do inode=1,nnode
                    ievab=inode
                    do jnode=1,nnode
                        do idimn=1,ndof
                            jevab=(jnode-1)*ndof+idimn
                            matrix(ievab,jevab)=matrix(ievab,jevab)+ &  !pay more attention
                                dvolu*shape(inode)*normal(idimn)*shape(jnode)
                        enddo
                    enddo
                enddo
            endif

            if  (bkind/=2)then
                do inode=1,nnode
                    do jnode=1,nnode
                        matrix(inode,jnode)=matrix(inode,jnode)+dvolu*shape(inode)*shape(jnode)
                    enddo
                enddo
            endif
        enddo !igaus
        deallocate(shape,cartd,normal)
        if (bkind==2)allocate(ifsedges(iedge)%matrix0(nnode,nnode*ndimn),ifsedges(iedge)%matrix(nnode,nnode*ndimn))
        if (bkind/=2)allocate(ifsedges(iedge)%matrix0(nnode,nnode),ifsedges(iedge)%matrix(nnode,nnode))

        if (bkind==1)matrix=matrix/ifsgravity
        if (bkind==2)matrix=matrix*dens
        if (bkind==3)matrix=matrix/c
        if (bkind==4)matrix=-matrix*(absorb-1.0)/(absorb+1.0)/c
        ifsedges(iedge)%matrix0=matrix

        deallocate(matrix)

    enddo

    end subroutine stiff_ifs2006

    subroutine assemble_stiff_ifs2006

    integer(ink) iedge,bkind,ielem,igroup,felem,nevab,nevabs,nevabf,ievab,jevab,itotv,jtotv, &
        ieq,jeq,colum,colum0,jgroup,selem,imats,ipoin,idimn,k,ie0,i0
    integer(ink),pointer::ldofs(:),ldofs_s(:),ldofs_f(:)
    real   (irk),pointer::matrix(:,:)
    real   (irk) coef,coefsymetry,dens

    do iedge=1,ifsnedge
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        imats=matno_process(igroup,iblks) !special
        dens  =props(imats)%mechanical%fluid%density
        coefsymetry=-beeta2*ditime**2/dens
        ifsedges(iedge)%matrix=ifsedges(iedge)%matrix0*coefsymetry
    enddo

    do iedge=1,ifsnedge !iedge
        bkind =ifsedges(iedge)%bkind
        ielem =ifsedges(iedge)%felem
        igroup=element(ielem)%group
        if (bkind==2)cycle
        coef=beeta1*ditime
        if (bkind==1)coef=1.0
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        if (appear(igroup)==0)cycle
        matrix=>ifsedges(iedge)%matrix
        ldofs=>ifsedges(iedge)%ldofs
        nevab=size(ldofs)
        do jevab=1,nevab
            jtotv=ldofs(jevab)
            jeq  =totveq(jtotv)
            if  (jeq/=0)then
                colum0=iseq(jeq)-jeq
                do ievab=1,nevab
                    itotv=ldofs(ievab)
                    ieq  =totveq(itotv)
                    if(type_solver=='PROFILE')then
                        if(ieq/=0.and.ieq<=jeq) then
                            colum=colum0+ieq
                            global_stiff1(colum)=global_stiff1(colum)+matrix(ievab,jevab)*coef
                            if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+matrix(jevab,ievab)*coef
                        endif
                    elseif(type_solver=='PARDISO')then
                        !if(ieq/=0.and.ieq<=jeq)then
                        if(ieq/=0)then !20240312 YL
                            if(nonsym==0.and.ieq>jeq)cycle
                            do k=iseq(ieq),iseq(ieq+1)-1
                                if(jeq==nndex(k))then
                                    global_stiff1(k)=global_stiff1(k)+matrix(Ievab,Jevab)*coef
                                    exit
                                endif
                            enddo
                        endif
                    else
                        write(*,*)'***********集成assemble_stiff_ifs2006出错，没有种求解方式************'
                        stop
                    endif

                enddo
            endif
        enddo
        nullify(matrix,ldofs)
    enddo

    do iedge=1,ifsnedge !iedge
        bkind =ifsedges(iedge)%bkind
        ielem =ifsedges(iedge)%felem
        igroup=element(ielem)%group
        if (bkind/=2)cycle
        coef=1.0
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        selem=ifsedges(iedge)%selem
        jgroup=element(selem)%group
        if (appear(igroup)==0.or.appear(jgroup)==0)cycle
        matrix=>ifsedges(iedge)%matrix
        ldofs_s=>ifsedges(iedge)%ldofs_s
        ldofs_f=>ifsedges(iedge)%ldofs_f
        nevabs=size(ldofs_s)
        nevabf=size(ldofs_f)
        do ievab=1,nevabf
            itotv=ldofs_f(ievab)
            ieq  =totveq(itotv)
            if  (ieq/=0)then
                do jevab=1,nevabs
                    jtotv=ldofs_s(jevab)
                    jeq  =totveq(jtotv)

                    if(type_solver=='PROFILE')then
                        if (jeq==0.or.ieq<jeq)cycle   !20210118
                        colum=iseq(ieq)-(ieq-jeq)
                        global_stiff1(colum)=global_stiff1(colum)+matrix(Ievab,Jevab)*coef
                        if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+matrix(jevab,ievab)*coef
                    elseif(type_solver=='PARDISO')then
                        !if (jeq==0.or.ieq<jeq)cycle   !20210118
                        if(jeq==0)cycle !20240312 YL
                        if(nonsym==0.and.ieq<jeq)cycle
                        do k=iseq(jeq),iseq(jeq+1)-1
                            if(ieq==nndex(k))then
                                global_stiff1(k)=global_stiff1(k)+matrix(Ievab,Jevab)*coef
                                exit
                            endif
                        enddo
                    else
                        write(*,*)'***********集成assemble_stiff_ifs2006出错，没有种求解方式************'
                        stop
                    endif
                enddo
            endif
        enddo
        nullify(matrix,ldofs_s,ldofs_f)
    enddo

    !ifs2006 zhao, 06/03/29 , icaddmass
    if (icaddmass/=0)then
        do ipoin=1,npoin
            if (icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if (itotv==0)cycle
                ieq=totveq(itotv)
                if (ieq==0)cycle
                !             colum=iseq(ieq)
                !             global_stiff1(colum)=global_stiff1(colum)+addmp(idimn,ipoin)
                if(type_solver=='PROFILE')then
                    colum=iseq(ieq)
                    global_stiff1(colum)=global_stiff1(colum)+addmp(idimn,ipoin)
                elseif(type_solver=='PARDISO')then
                    do k=iseq(ieq),iseq(ieq+1)-1
                        if(Ieq==nndex(k))then
                            global_stiff1(k)=global_stiff1(k)+addmp(idimn,ipoin)
                            exit
                        endif
                    enddo
                else
                    write(*,*)'***********集成assemble_stiff_ifs2006出错，没有种求解方式************'
                    stop
                endif


            enddo
        enddo
    endif

    end subroutine assemble_stiff_ifs2006


    subroutine assemble_stiff_ifs2006_SSORPBCG

    integer(ink) iedge,bkind,ielem,igroup,felem,nevab,nevabs,nevabf,ievab,jevab,itotv,jtotv, &
        ieq,jeq,colum,colum0,jgroup,selem,imats,ipoin,idimn,K
    integer(ink),pointer::ldofs(:),ldofs_s(:),ldofs_f(:)
    real   (irk),pointer::matrix(:,:)
    real   (irk) coef,coefsymetry,dens

    do iedge=1,ifsnedge
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        imats=matno_process(igroup,iblks) !special
        dens  =props(imats)%mechanical%fluid%density
        coefsymetry=-beeta2*ditime**2/dens
        ifsedges(iedge)%matrix=ifsedges(iedge)%matrix0*coefsymetry
    enddo

    do iedge=1,ifsnedge !iedge
        bkind =ifsedges(iedge)%bkind
        ielem =ifsedges(iedge)%felem
        igroup=element(ielem)%group
        if (bkind==2)cycle
        coef=beeta1*ditime
        if (bkind==1)coef=1.0
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        if (appear(igroup)==0)cycle
        matrix=>ifsedges(iedge)%matrix
        ldofs=>ifsedges(iedge)%ldofs
        nevab=size(ldofs)
        do jevab=1,nevab
            jtotv=ldofs(jevab)
            jeq  =totveq(jtotv)
            do ievab=1,nevab
                itotv=ldofs(ievab)
                ieq  =totveq(itotv)
                if (ieq==0.or.jeq==0)cycle
                if (ieq<jeq)cycle
                if  (ieq==1)then
                    global_stiff1(1)=global_stiff1(1)+matrix(ievab,jevab)*coef
                    cycle
                endif
                do k=iseq(ieq-1)+1,iseq(ieq)
                    if (jeq==nndex(k))then
                        global_stiff1(k)=global_stiff1(k)+matrix(ievab,jevab)*coef
                    endif
                enddo

                !if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+matrix(jevab,ievab)*coef

            ENDDO
        enddo
        nullify(matrix,ldofs)
    enddo

    do iedge=1,ifsnedge !iedge
        bkind =ifsedges(iedge)%bkind
        ielem =ifsedges(iedge)%felem
        igroup=element(ielem)%group
        if (bkind/=2)cycle
        coef=1.0
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        selem=ifsedges(iedge)%selem
        jgroup=element(selem)%group
        if (appear(igroup)==0.or.appear(jgroup)==0)cycle
        matrix=>ifsedges(iedge)%matrix
        ldofs_s=>ifsedges(iedge)%ldofs_s
        ldofs_f=>ifsedges(iedge)%ldofs_f
        nevabs=size(ldofs_s)
        nevabf=size(ldofs_f)
        do ievab=1,nevabf
            itotv=ldofs_f(ievab)
            ieq  =totveq(itotv)
            !if (ieq/=0)then
            do jevab=1,nevabs
                jtotv=ldofs_s(jevab)
                jeq  =totveq(jtotv)
                if (ieq==0.or.jeq==0)cycle
                if (ieq<jeq)cycle
                if  (ieq==1)then
                    global_stiff1(1)=global_stiff1(1)+matrix(ievab,jevab)*coef
                    cycle
                endif
                do k=iseq(ieq-1)+1,iseq(ieq)
                    if (jeq==nndex(k))then
                        global_stiff1(k)=global_stiff1(k)+matrix(ievab,jevab)*coef
                    endif
                enddo
                !if (jeq==0.or.ieq<jeq)cycle
                !colum=iseq(ieq)-(ieq-jeq)
                !global_stiff1(colum)=global_stiff1(colum)+matrix(ievab,jevab)*coef
                !if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+matrix(jevab,ievab)*coef !special ??
            enddo
            !endif
        enddo
        nullify(matrix,ldofs_s,ldofs_f)
    enddo

    !ifs2006 zhao, 06/03/29 , icaddmass
    if (icaddmass/=0)then
        !STOP 'STOP FOR SSOR ICADDMASS'
        do ipoin=1,npoin
            if (icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if (itotv==0)cycle
                ieq=totveq(itotv)
                if (ieq==0)cycle

                if  (ieq==1)then
                    global_stiff1(1)=global_stiff1(1)+addmp(idimn,ipoin)
                    cycle
                endif
                do k=iseq(ieq-1)+1,iseq(ieq)
                    if (ieq==nndex(k))then
                        global_stiff1(k)=global_stiff1(k)+addmp(idimn,ipoin)
                    endif
                enddo
            enddo
        enddo
    endif

    end subroutine assemble_stiff_ifs2006_SSORPBCG

    subroutine assemble_stiff_ifs2006_w

    integer(ink) iedge,bkind,ielem,igroup,felem,nevab,nevabs,nevabf,ievab,jevab,itotv,jtotv, &
        ieq,jeq,colum,colum0,jgroup,selem,imats,ipoin,idimn
    integer(ink),pointer::ldofs(:),ldofs_s(:),ldofs_f(:)
    real   (irk),pointer::matrix(:,:)
    real   (irk) dens
    complex(irk) coef,coefsymetry

    do iedge=1,ifsnedge
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        imats=matno_process(igroup,iblks) !special
        dens  =props(imats)%mechanical%fluid%density
        ifsedges(iedge)%matrix=ifsedges(iedge)%matrix0/dens
    enddo

    do iedge=1,ifsnedge !iedge
        bkind =ifsedges(iedge)%bkind
        ielem =ifsedges(iedge)%felem
        igroup=element(ielem)%group
        if (bkind==1)coef=cmplx(-1.0,0.)
        if (bkind==2)cycle
        if (bkind==3.or.bkind==4)coef=cmplx(0.,-1.0/ttime)
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        if (appear(igroup)==0)cycle
        matrix=>ifsedges(iedge)%matrix
        ldofs=>ifsedges(iedge)%ldofs
        nevab=size(ldofs)
        do jevab=1,nevab
            jtotv=ldofs(jevab)
            jeq  =totveq(jtotv)
            if  (jeq/=0)then
                colum0=iseq(jeq)-jeq
                do ievab=1,nevab
                    itotv=ldofs(ievab)
                    ieq  =totveq(itotv)
                    if  (ieq/=0.and.ieq<=jeq)then
                        colum=colum0+ieq
                        global_stiff1w(colum)=global_stiff1w(colum)+matrix(ievab,jevab)*coef
                        if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+matrix(jevab,ievab)*coef
                    endif
                enddo
            endif
        enddo
        nullify(matrix,ldofs)
    enddo

    do iedge=1,ifsnedge !iedge
        bkind =ifsedges(iedge)%bkind
        ielem =ifsedges(iedge)%felem
        igroup=element(ielem)%group
        if (bkind/=2)cycle
        coef=cmplx(-1.,0.)
        felem=ifsedges(iedge)%felem
        igroup=element(felem)%group
        selem=ifsedges(iedge)%selem
        jgroup=element(selem)%group
        if (appear(igroup)==0.or.appear(jgroup)==0)cycle
        matrix=>ifsedges(iedge)%matrix
        ldofs_s=>ifsedges(iedge)%ldofs_s
        ldofs_f=>ifsedges(iedge)%ldofs_f
        nevabs=size(ldofs_s)
        nevabf=size(ldofs_f)
        do ievab=1,nevabf
            itotv=ldofs_f(ievab)
            ieq  =totveq(itotv)
            if  (ieq/=0)then
                do jevab=1,nevabs
                    jtotv=ldofs_s(jevab)
                    jeq  =totveq(jtotv)
                    if  (jeq==0.or.ieq<jeq)cycle
                    colum=iseq(ieq)-(ieq-jeq)
                    global_stiff1w(colum)=global_stiff1w(colum)+matrix(ievab,jevab)*coef
                    if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+matrix(jevab,ievab)*coef !special ??
                enddo
            endif
        enddo
        nullify(matrix,ldofs_s,ldofs_f)
    enddo

    !ifs2006 zhao, 06/03/29 , icaddmass

    if (icaddmass/=0)then
        coef=cmplx(-ttime**2,0.)
        do ipoin=1,npoin
            if (icmp(ipoin)==0)cycle
            do idimn=1,ndimn
                itotv=nodfn(idimn,ipoin)
                if (itotv==0)cycle
                ieq=totveq(itotv)
                if (ieq==0)cycle
                colum=iseq(ieq)
                global_stiff1w(colum)=global_stiff1w(colum)+addmp(idimn,ipoin)*coef
            enddo
        enddo
    endif

    end subroutine assemble_stiff_ifs2006_w


    !!ifs2000
    SUBROUTINE stiff_interface_fluid_solid

    character(10) text
    integer(ink) tedge,iedge,i0,index,ngaus,ig,idofn,jdofn,    &
        inode,sedge,nnode,edimn,order_int,jnode,idimn,iidofn

    integer(ink),allocatable::lnode(:)
    real    (irk) aa,weigp,djacb
    real    (irk),allocatable::a3(:),shape(:),elcod(:,:),         &
        deriv(:,:),elcod0(:,:),cartd(:,:),xjaci(:,:), &
        s(:,:),rr(:,:)

    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_interface_fluid_solid_title_1,0)
    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)nifsgroup
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_interface_fluid_solid_ifs_group_count,0)
    print *,text
    print *,'nifsgroup=',nifsgroup
    if (nifsgroup==0) return
    allocate(tifs(nifsgroup))
    tedge=0
    do while(tedge<nifsgroup)
        read(ifsunit,*)text                               !4
        read(ifsunit,*)sedge,nnode,index

        edimn=elkn(index)%ndimn
        order_int=elkn(index)%el_field(1)%order_intrules(2)
        ngaus=elkn(index)%ggaus(order_int)%ngaus
        allocate(shape(nnode),deriv(edimn,nnode),cartd(edimn,nnode))
        allocate(s(edimn+1,edimn+1),a3(edimn+1),elcod0(edimn,nnode))
        allocate(rr(ndimn,ndimn),xjaci(edimn,edimn))
        allocate(lnode(nnode),elcod(nnode,edimn+1))

        do iedge=1,sedge   !3

            tedge=tedge+1

            allocate(tifs(tedge)%lnods(nnode),tifs(tedge)%ldofs(nnode*(ndimn+1)))
            allocate(tifs(tedge)%estif(nnode*(ndimn+1),nnode*(ndimn+1)))
            allocate(tifs(tedge)%eload(nnode*(ndimn+1)))

            read(ifsunit,*)i0,tifs(tedge)%lnods(1:nnode),tifs(tedge)%aelemf,  &
                tifs(tedge)%aelems
            lnode=tifs(tedge)%lnods

            idofn=0
            do inode=1,nnode
                do idimn=1,ndimn
                    idofn=idofn+1
                    tifs(tedge)%ldofs(idofn)=nodfn(idimn,lnode(inode))
                end do
            end do

            iidofn=lmdofn(8)
            do inode=1,nnode
                idofn=idofn+1
                tifs(tedge)%ldofs(idofn)=nodfn(iidofn,lnode(inode))
            end do
            do inode=1,nnode
                elcod(inode,:)=coord(:,lnode(inode))
            end do

            tifs(tedge)%estif=0.
            do ig=1,ngaus
                shape=elkn(index)%ggaus(order_int)%shape(:,ig)
                deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
                weigp=elkn(index)%ggaus(order_int)%weigp(ig)
                s(1:edimn,:)=MATMUL(deriv,elcod)
                if ((edimn+1).eq.3) then
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
                call cosc(edimn+1,a3,elcod0,elcod,rr)
                call jacob(iedge, edimn, nnode,elcod0,deriv,cartd, djacb,xjaci)



                do inode=1,nnode
                    do idimn=1,ndimn
                        idofn=(inode-1)*ndimn+idimn
                        do jnode=1,nnode
                            jdofn=nnode*ndimn+jnode
                            tifs(tedge)%estif(jdofn,idofn)=tifs(tedge)%estif(jdofn,idofn)  &
                                -shape(jnode)*a3(idimn)*shape(inode)*djacb*weigp !-  outer normal of water
                            tifs(tedge)%estif(idofn,jdofn)=tifs(tedge)%estif(jdofn,idofn)
                        end do
                    end do
                end do
            end do       !!ig
            !tifs(tedge)%estif=transpose(tifs(tedge)%estif) !incorrect
        end do                                        !3
        deallocate (shape,deriv,cartd,s,a3,elcod0,elcod,lnode,rr,xjaci)
    end do                                               !4

    end subroutine stiff_interface_fluid_solid
    !!
    SUBROUTINE stiff_absorb_fluid

    character(10) text
    integer(ink) tedge,iedge,i0,index,ngaus,ig,idofn,    &
        inode,sedge,nnode,edimn,order_int,jnode,imat

    integer(ink),allocatable::lnode(:)
    real    (irk) aa,weigp,djacb,alfa,dens,cx
    real    (irk),allocatable::a3(:),shape(:),elcod(:,:),         &
        deriv(:,:),elcod0(:,:),cartd(:,:),xjaci(:,:), &
        s(:,:),rr(:,:)

    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_absorb_fluid_title_1,0)
    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)nabsfgroup
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_absorb_fluid_absorb_fluid_count,0)
    print *,text
    print *,'nabsfgroup=',nabsfgroup
    if (nabsfgroup==0) return
    allocate(tabsf(nabsfgroup))
    tedge=0
    do while(tedge<nabsfgroup)
        read(ifsunit,*)text                               !4
        read(ifsunit,*)sedge,nnode,index !,alfa

        edimn=elkn(index)%ndimn
        order_int=elkn(index)%el_field(1)%order_intrules(2)
        ngaus=elkn(index)%ggaus(order_int)%ngaus
        allocate(shape(nnode),deriv(edimn,nnode),cartd(edimn,nnode))
        allocate(s(edimn+1,edimn+1),a3(edimn+1),elcod0(edimn,nnode))
        allocate(rr(ndimn,ndimn),xjaci(edimn,edimn))
        allocate(lnode(nnode),elcod(nnode,edimn+1))

        do iedge=1,sedge                            !3
            tedge=tedge+1

            allocate(tabsf(tedge)%lnods(nnode),tabsf(tedge)%ldofs(nnode))
            allocate(tabsf(tedge)%estif(nnode,nnode))
            allocate(tabsf(tedge)%eload(nnode))

            read(ifsunit,*)i0,tabsf(tedge)%lnods(1:nnode),tabsf(tedge)%aelemf

            imat=element(tabsf(tedge)%aelemf)%matno
            dens=props(imat)%mechanical%fluid%density
            cx  =props(imat)%mechanical%fluid%c
            alfa=1.0/dens/cx

            lnode=tabsf(tedge)%lnods

            idofn=0

            do inode=1,nnode
                idofn=idofn+1
                tabsf(tedge)%ldofs(idofn)=nodfn(lmdofn(8),lnode(inode))
            end do

            do inode=1,nnode
                elcod(inode,:)=coord(:,lnode(inode))
            end do

            tabsf(tedge)%estif=0.
            do ig=1,ngaus
                shape=elkn(index)%ggaus(order_int)%shape(:,ig)
                deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
                weigp=elkn(index)%ggaus(order_int)%weigp(ig)
                s(1:edimn,:)=MATMUL(deriv,elcod)
                if ((edimn+1).eq.3) then
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
                call cosc(edimn+1,a3,elcod0,elcod,rr)
                call jacob(iedge, edimn, nnode,elcod0,deriv,cartd, djacb,xjaci)

                do inode=1,nnode
                    do jnode=1,nnode
                        tabsf(tedge)%estif(inode,jnode)=tabsf(tedge)%estif(inode,jnode)  &
                            +shape(jnode)*shape(inode)*djacb*weigp*alfa
                    end do
                end do
            end do       !!ig

        end do                                        !3
        deallocate (shape,deriv,cartd,s,a3,elcod0,elcod,lnode,rr,xjaci)
    end do                                               !4

    end subroutine stiff_absorb_fluid

    !!
    !!
    SUBROUTINE stiff_absorb_solid !hxl2006 VIE

    character(10) text,SPtype
    integer(ink) tedge,iedge,i0,index,ngaus,ig,idofn,    &
        inode,sedge,nnode,edimn,order_int,idimn, &
        jdimn,nevab,matno,cdbound,itdis,itveloc

    integer(ink),allocatable::lnode(:)
    real    (irk) aa,weigp,djacb,density,e,nu,alfa,g,rgpcod
    real    (irk),allocatable::a3(:),shape(:),elcod(:,:),xjaci(:,:),         &
        deriv(:,:),elcod0(:,:),xyz0(:),gpcod(:),spring(:),cartd(:,:),       &
        s(:,:),rr(:,:),speed(:),shapes(:,:),shapet(:,:),estif(:,:), &
        shapeb(:,:),speedb(:,:),rrb(:,:),estif_mid1(:,:),estif_mid2(:,:),estif_mid3(:,:)

    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_absorb_solid_title_1,0)
    read(ifsunit,*,iostat=yl_ios,iomsg=yl_msg)nabssgroup   !,exx,uxx,densxx
    call diag_check_read(yl_ios,yl_msg,RD_IFS_stiff_absorb_solid_absorb_solid_count,0)
    print *,text
    print *,'nabssgroup=',nabssgroup
    if (nabssgroup==0) return
    allocate(tabss(nabssgroup))
    tedge=0
    do while(tedge<nabssgroup)
        allocate(speed(ndimn),xyz0(ndimn),gpcod(ndimn),spring(ndimn))
        read(ifsunit,*)text                               !4
        read(ifsunit,*)sedge,nnode,index,xyz0(1:ndimn),cdbound   !!hxl_l

        edimn=elkn(index)%ndimn
        order_int=elkn(index)%el_field(1)%order_intrules(2)
        ngaus=elkn(index)%ggaus(order_int)%ngaus
        allocate(shape(nnode),deriv(edimn,nnode),cartd(edimn,nnode),xjaci(edimn,edimn))
        allocate(s(edimn,edimn),a3(ndimn),elcod0(ndimn,nnode))
        allocate(rr(ndimn,ndimn))
        allocate(lnode(nnode),elcod(nnode,ndimn))
        nevab=nnode*ndimn
        allocate(shapes(ndimn,nevab),shapet(nevab,ndimn),estif(nevab,nevab))
        allocate(shapeb(ndimn,nevab),speedb(ndimn,ndimn),rrb(nevab,nevab),   &
            estif_mid1(ndimn,nevab),estif_mid2(nevab,nevab),            &
            estif_mid3(nevab,nevab))


        do iedge=1,sedge                            !3
            tedge=tedge+1
            !print *,'iedge=',iedge,'tedge=',tedge
            tabss(tedge)%cdbound=cdbound   !!hxl_l
            !tabss(tedge)%itdis=itdis       !!hxl_l
            !tabss(tedge)%itveloc=itveloc   !!hxl_l
            allocate(tabss(tedge)%lnods(nnode))
            allocate(tabss(tedge)%ldofs(nevab))

            allocate(tabss(tedge)%estif(nevab,nevab),tabss(tedge)%estif0(nevab,nevab),tabss(tedge)%cordzfree(ndimn))
            allocate(tabss(tedge)%eload(nevab),tabss(tedge)%eload_s(nevab,nevab),tabss(tedge)%rr(ndimn,ndimn))

            !tabss(tedge)%cordzfree=xyz0
            !
            !write(7,*)'tedge=',tedge,'cordzfree=', tabss(tedge)%cordzfree
            read(ifsunit,*)i0,tabss(tedge)%lnods(1:nnode),tabss(tedge)%aelems

            matno=element(tabss(tedge)%aelems)%matno
            SPtype=    group(element(tabss(tedge)%aelems)%group)%SPtype

            density=props(matno)%mechanical%solid%density  !densxx !
            e=props(matno)%mechanical%solid%e  !exx !
            nu=props(matno)%mechanical%solid%nu !uxx !
            alfa = e*(1-nu)/((1.+nu)*(1.-2.*nu))
            if (SPtype=='PS')alfa=e/(1.0-nu**2)
            G    = e/(2.*(1.+nu))
            speed(ndimn)=sqrt(alfa/density)
            speed(1:(ndimn-1))=sqrt(g/density)
            if(tedge==1)write(7,*)'speed=',speed
            spring(ndimn)=e !alfa*.5  !.25 是任选的参数 zhao 05/08/18
            spring(1:(ndimn-1))=G !*.5  !!.25 是任选的参数 zhao 05/08/18

            lnode=tabss(tedge)%lnods

            idofn=0

            do inode=1,nnode
                do idimn=1,ndimn
                    idofn=idofn+1
                    tabss(tedge)%ldofs(idofn)=nodfn(idimn,lnode(inode))
                end do
            end do

            do inode=1,nnode
                elcod(inode,:)=coord(:,lnode(inode))
            end do

            tabss(tedge)%estif=0.
            tabss(tedge)%estif0=0.
            tabss(tedge)%eload_s=0.
            do ig=1,ngaus
                call normal_local_b(nnode,index,lnode,a3)
                call direct(a3,rr,ndimn)
                call cosc(ndimn,a3,elcod0,elcod,rr)

                shape=elkn(index)%ggaus(order_int)%shape(:,ig)
                deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
                weigp=elkn(index)%ggaus(order_int)%weigp(ig)
                call jacob(iedge, edimn, nnode,elcod0,deriv,cartd, djacb,xjaci)
                !!!!!!!!!!!!!!!!!!!!!!!!!!!
                shapeb=0.
                do inode=1,nnode
                    do idimn=1,ndimn
                        shapeb(idimn,(inode-1)*ndimn+idimn)=shape(inode)
                    end do
                end do
                speedb=0.
                do idimn=1,ndimn
                    speedb(idimn,idimn)=speed(idimn)
                end do

                rrb=0.
                do inode=1,nnode
                    rrb((inode-1)*ndimn+1:inode*ndimn,(inode-1)*ndimn+1:inode*ndimn)=rr
                end do
                tabss(tedge)%rr=rr  !事实上是用最后一个高斯点的数值

                estif_mid1=speedb.x.shapeb
                estif_mid2=transpose(shapeb).x.estif_mid1
                estif_mid3=estif_mid2.x.rrb
                estif=transpose(rrb).x.estif_mid3
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


                tabss(tedge)%estif=tabss(tedge)%estif  &
                    +djacb*weigp*density*estif

                tabss(tedge)%eload_s=tabss(tedge)%eload_s+djacb*weigp*(transpose(shapeb).x.shapeb)

                do idimn=1,ndimn
                    gpcod(idimn)=elcod(1:nnode,idimn).d.shape(1:nnode)
                end do
                rgpcod=sum((gpcod(:)-xyz0(:))**2)
                rgpcod=sqrt(rgpcod)

                do inode=1,nnode
                    do idimn=1,ndimn
                        do jdimn=1,ndimn
                            idofn=(inode-1)*ndimn+jdimn
                            shapes(idimn,idofn)=rr(idimn,jdimn)*spring(idimn)*shape(inode)
                            shapet(idofn,idimn)=rr(idimn,jdimn)*shape(inode)
                        end do
                    end do
                end do
                estif=0.
                estif=shapet.x.shapes

                tabss(tedge)%estif0=tabss(tedge)%estif0  &
                    +(djacb*weigp/2./rgpcod)*estif


            end do       !!ig

        end do                                        !3
        deallocate (shape,deriv,cartd,s,a3,elcod0,elcod,xjaci,  &
            lnode,rr,shapes,shapet,speed,estif,gpcod,spring,xyz0)
        deallocate(shapeb,speedb,rrb,estif_mid1,estif_mid2,estif_mid3)
    end do                                               !4

    end subroutine stiff_absorb_solid

    subroutine normal_local_b(nnode,index,lnods,rotation)
    integer(ink) lnods(:)
    integer(ink) index,nnode,edimn,order_int,ngaus,ig,inode,nnode1
    integer(ink),allocatable::lnode(:)
    real   (irk) rotation(:),weigp,aa
    real   (irk),allocatable::elcod(:,:),deriv(:,:),s(:,:),a3(:)
    real   (irk),allocatable::shape(:)
    !index=1        !2017/02/14
    !if (ndimn==3)index=5    !2017/02/14
    !nnode=2      !2017/02/14
    !!if (ndimn==3)nnode=4  !2017/02/14
    ! nnode1=size(lnods)  !2017/02/14
    !index=1      !2017/02/14
    !if(ndimn==3.and.nnode1==8)index=5   !2017/02/14
    !if(ndimn==3.and.nnode1==6)index=3   !2017/02/14
    !
    !nnode=2
    !if(ndimn==3.and.nnode1==8)nnode=4   !2017/02/14
    !if(ndimn==3.and.nnode1==6)nnode=3   !2017/02/14

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
        if ((edimn+1).eq.3) then
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

    deallocate(lnode,elcod,shape,deriv,s,a3)

    end subroutine normal_local_b

    !!
    !!
    subroutine cosc(idm,a3,elcod0,elcod,rr)
    integer(ink) idm,idj,nnode,ind
    real   (irk) a3(:),elcod0(:,:),elcod(:,:),rr(:,:)

    call direct(a3,rr,idm)

    nnode=size(elcod,dim=1)
    do idj=1,idm-1
        do ind=1,nnode
            elcod0(idj,ind)=rr(idj,:).d.elcod(ind,:)
        end do
    end do

    end subroutine cosc



    subroutine assemble_interface_fluid_solid
    integer(ink) ielem,aelemf,aelems,igroup,jgroup,nevab,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1,ipea2,k
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    real   (irk) coef

    coef=theta1*ditime

    do ielem=1,nifsgroup
        aelemf=tifs(ielem)%aelemf
        aelems=tifs(ielem)%aelems
        ipea1=0
        igroup=element(aelemf)%group
        if (appear(igroup)>0)ipea1=1
        ipea2=1
        if (aelems/=0) then
            jgroup=element(aelems)%group
            if (appear(jgroup)<=0)ipea2=0
        endif
        if (ipea1==1.and.ipea2==1) then
            ldofs=>tifs(ielem)%ldofs
            estif=>tifs(ielem)%estif
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    colum0=iseq(jeq)-jeq
                    do i=1,nevab
                        idofn=ldofs(i)
                        ieq  =totveq(idofn)
                        if(type_solver=='PROFILE')then
                            if(ieq/=0.and.ieq<=jeq) then
                                colum=colum0+ieq
                                global_stiff1(colum)=global_stiff1(colum)+estif(i,j)*coef
                                if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                                    estif(j,i)*coef
                            endif
                        elseif(type_solver=='PARDISO')then
                            if(ieq/=0.and.ieq<=jeq)then
                                do k=iseq(ieq),iseq(ieq+1)-1
                                    if(jeq==nndex(k))then
                                        global_stiff1(k)=global_stiff1(k)+estif(i,j)*coef
                                        exit
                                    endif
                                enddo
                            endif
                        else
                            write(*,*)'***********集成流固耦合矩阵时出错，没有种求解方式************'
                            stop
                        endif
                        !                   if (ieq/=0.and.ieq<=jeq) then
                        !                      colum=colum0+ieq
                        !                      global_stiff1(colum)=global_stiff1(colum)+estif(i,j)*coef
                        !                      if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                        !                      estif(j,i)*coef
                        !                   endif
                    end do
                endif
            end do
            nullify(ldofs,estif)
        endif
    end do
    end subroutine assemble_interface_fluid_solid

    subroutine assemble_interface_fluid_solid_ssorpbcg

    integer(ink) ielem,aelemf,aelems,igroup,jgroup,nevab,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1,ipea2,k
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    real   (irk) coef

    coef=theta1*ditime

    do ielem=1,nifsgroup
        aelemf=tifs(ielem)%aelemf
        aelems=tifs(ielem)%aelems
        ipea1=0
        igroup=element(aelemf)%group
        if (appear(igroup)>0)ipea1=1
        ipea2=1
        if (aelems/=0) then
            jgroup=element(aelems)%group
            if (appear(jgroup)<=0)ipea2=0
        endif
        if (ipea1==1.and.ipea2==1) then
            ldofs=>tifs(ielem)%ldofs
            estif=>tifs(ielem)%estif
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                do i=1,nevab
                    idofn=ldofs(i)
                    ieq  =totveq(idofn)
                    if (ieq==0.or.jeq==0)cycle
                    if (ieq<jeq)cycle

                    if  (ieq==1)then
                        global_stiff1(1)=global_stiff1(1)+estif(i,j)*coef
                        cycle
                    endif
                    do k=iseq(ieq-1)+1,iseq(ieq)
                        if (jeq==nndex(k))then
                            global_stiff1(k)=global_stiff1(k)+estif(i,j)*coef
                        endif
                    enddo

                end do
            end do
            nullify(ldofs,estif)
        endif
    end do
    end subroutine assemble_interface_fluid_solid_ssorpbcg


    subroutine assemble_interface_fs_w !freq2006
    integer(ink) ielem,aelemf,aelems,igroup,jgroup,nevab,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1,ipea2
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    complex(irk) coef

    coef=cmplx(1.,0.)

    do ielem=1,nifsgroup
        aelemf=tifs(ielem)%aelemf
        aelems=tifs(ielem)%aelems
        ipea1=0
        igroup=element(aelemf)%group
        if (appear(igroup)>0)ipea1=1
        ipea2=1
        if (aelems/=0) then
            jgroup=element(aelems)%group
            if (appear(jgroup)<=0)ipea2=0
        endif
        if (ipea1==1.and.ipea2==1) then
            ldofs=>tifs(ielem)%ldofs
            estif=>tifs(ielem)%estif
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    colum0=iseq(jeq)-jeq
                    do i=1,nevab
                        idofn=ldofs(i)
                        ieq  =totveq(idofn)
                        if (ieq/=0.and.ieq<=jeq) then
                            colum=colum0+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+estif(i,j)*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+ &
                                estif(j,i)*coef
                        endif
                    end do
                endif
            end do
            nullify(ldofs,estif)
        endif
    end do
    end subroutine assemble_interface_fs_w

    subroutine assemble_absorb_fluid
    integer(ink) ielem,aelemf,igroup,nevab,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1,k
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    real   (irk) coef

    coef=-theta1*ditime

    do ielem=1,nabsfgroup
        aelemf=tabsf(ielem)%aelemf
        ipea1=0
        igroup=element(aelemf)%group
        if (appear(igroup)>0)ipea1=1
        if (ipea1==1) then
            ldofs=>tabsf(ielem)%ldofs
            estif=>tabsf(ielem)%estif
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    colum0=iseq(jeq)-jeq
                    do i=1,nevab
                        idofn=ldofs(i)
                        ieq  =totveq(idofn)

                        if(type_solver=='PROFILE')then
                            if(ieq/=0.and.ieq<=jeq) then
                                colum=colum0+ieq
                                global_stiff1(colum)=global_stiff1(colum)+estif(i,j)*coef
                                if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+estif(j,i)*coef
                            endif
                        elseif(type_solver=='PARDISO')then
                            if(ieq/=0.and.ieq<=jeq)then
                                do k=iseq(ieq),iseq(ieq+1)-1
                                    if(jeq==nndex(k))then
                                        global_stiff1(k)=global_stiff1(k)+estif(i,j)*coef
                                        exit
                                    endif
                                enddo
                            endif
                        else
                            write(*,*)'***********集成流体吸收矩阵时出错，没有种求解方式************'
                            stop
                        endif

                        !                   if (ieq/=0.and.ieq<=jeq) then
                        !                      colum=colum0+ieq
                        !                      global_stiff1(colum)=global_stiff1(colum)+estif(i,j)*coef
                        !                      if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                        !                      estif(j,i)*coef
                        !                   endif
                    end do
                endif
            end do
            nullify(ldofs,estif)
        endif
    end do
    end subroutine assemble_absorb_fluid

    subroutine assemble_absorb_fluid_w !freq2006
    integer(ink) ielem,aelemf,igroup,nevab,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:)
    complex(irk) coef

    coef=-cmplx(0.,ttime)/(ttime**2)

    do ielem=1,nabsfgroup
        aelemf=tabsf(ielem)%aelemf
        ipea1=0
        igroup=element(aelemf)%group
        if (appear(igroup)>0)ipea1=1
        if (ipea1==1) then
            ldofs=>tabsf(ielem)%ldofs
            estif=>tabsf(ielem)%estif
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    colum0=iseq(jeq)-jeq
                    do i=1,nevab
                        idofn=ldofs(i)
                        ieq  =totveq(idofn)
                        if (ieq/=0.and.ieq<=jeq) then
                            colum=colum0+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+estif(i,j)*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+ &
                                estif(j,i)*coef
                        endif
                    end do
                endif
            end do
            nullify(ldofs,estif)
        endif
    end do
    end subroutine assemble_absorb_fluid_w

    subroutine assemble_absorb_solid
    integer(ink) ielem,aelems,igroup,nevab,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1,k
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:),estif0(:,:)
    real   (irk) coef,coef0

    coef=beeta1*ditime
    coef0=beeta2*ditime**2          !

    do ielem=1,nabssgroup
        aelems=tabss(ielem)%aelems
        ipea1=0
        igroup=element(aelems)%group
        if (appear(igroup)>0)ipea1=1
        if (ipea1==1) then
            ldofs=>tabss(ielem)%ldofs
            estif=>tabss(ielem)%estif
            estif0=>tabss(ielem)%estif0
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    colum0=iseq(jeq)-jeq
                    do i=1,nevab
                        idofn=ldofs(i)
                        ieq  =totveq(idofn)

                        if(type_solver=='PROFILE')then
                            if(ieq/=0.and.ieq<=jeq) then
                                colum=colum0+ieq
                                global_stiff1(colum)=global_stiff1(colum)+estif(i,j)*coef
                                global_stiff1(colum)=global_stiff1(colum)+estif0(i,j)*coef0

                                if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                                    estif(j,i)*coef
                                if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                                    estif0(j,i)*coef0

                            endif
                        elseif(type_solver=='PARDISO')then
                            if(ieq/=0.and.ieq<=jeq)then
                                do k=iseq(ieq),iseq(ieq+1)-1
                                    if(jeq==nndex(k))then
                                        global_stiff1(k)=global_stiff1(k)+estif(i,j)*coef
                                        global_stiff1(k)=global_stiff1(k)+estif0(i,j)*coef0
                                        exit
                                    endif
                                enddo
                            endif
                        else
                            write(*,*)'***********集成固体吸收矩阵时出错，没有种求解方式************'
                            stop
                        endif
                        !                   if (ieq/=0.and.ieq<=jeq) then
                        !                      colum=colum0+ieq
                        !                      global_stiff1(colum)=global_stiff1(colum)+estif(i,j)*coef
                        !                      global_stiff1(colum)=global_stiff1(colum)+estif0(i,j)*coef0
                        !
                        !                      if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                        !                      estif(j,i)*coef
                        !                      if (nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                        !                      estif0(j,i)*coef0
                        !
                        !                   endif
                    end do
                endif
            end do
            nullify(ldofs,estif,estif0)
        endif
    end do
    end subroutine assemble_absorb_solid

    !!!!!!!!!
    subroutine assemble_back_spring  !20150925
    integer(ink) ielem,itotv,ieq,colum
    real   (irk) stif_spring

    do ielem=1,nbspring
        itotv=bspring(ielem)%listdof
        stif_spring=bspring(ielem)%spring
        ieq  =totveq(itotv)
        colum=iseq(ieq)
        global_stiff1(colum)=global_stiff1(colum)+stif_spring
        if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+stif_spring
    end do
    end subroutine assemble_back_spring !20150925
    !!!!!!!!!

    subroutine assemble_absorb_solid_SSORPBCG
    integer(ink) ielem,aelems,igroup,nevab,k,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:),estif0(:,:)
    real   (irk) coef,coef0

    coef=beeta1*ditime
    coef0=beeta2*ditime**2          !

    do ielem=1,nabssgroup
        aelems=tabss(ielem)%aelems
        ipea1=0
        igroup=element(aelems)%group
        if (appear(igroup)>0)ipea1=1
        if (ipea1==1) then
            ldofs=>tabss(ielem)%ldofs
            estif=>tabss(ielem)%estif
            estif0=>tabss(ielem)%estif0
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                do i= 1,nevab
                    idofn=ldofs(i)
                    ieq  =totveq(idofn)
                    if (ieq==0.or.jeq==0)cycle
                    if (ieq<jeq)cycle
                    if  (ieq==1)then
                        global_stiff1(1)=global_stiff1(1)+estif(i,j)*coef
                        global_stiff1(1)=global_stiff1(1)+estif0(i,j)*coef0
                        cycle
                    endif
                    do k=iseq(ieq-1)+1,iseq(ieq)
                        if (jeq==nndex(k))then
                            global_stiff1(k)=global_stiff1(k)+estif(i,j)*coef
                            global_stiff1(k)=global_stiff1(k)+estif0(i,j)*coef0
                        endif
                    enddo


                    !if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                    !estif(j,i)*coef
                    !if(nonsym==1)global_stiff2(colum)=global_stiff2(colum)+ &
                    !estif0(j,i)*coef0

                end do !i
            end do !j
            nullify(ldofs,estif,estif0)
        endif
    end do
    end subroutine assemble_absorb_solid_SSORPBCG

    !!ifs2000

    subroutine assemble_absorb_solid_w !freq2006
    integer(ink) ielem,aelems,igroup,nevab,  &
        i,j,idofn,jdofn,ieq,jeq,colum,colum0,ipea1
    integer(ink),pointer::ldofs(:)
    real   (irk),pointer::estif(:,:),estif0(:,:)
    complex(irk) coef,coef0

    coef=cmplx(0.,-ttime)
    coef0=cmplx(1.,0.)          !

    do ielem=1,nabssgroup
        aelems=tabss(ielem)%aelems
        ipea1=0
        igroup=element(aelems)%group
        if (appear(igroup)>0)ipea1=1
        if (ipea1==1) then
            ldofs=>tabss(ielem)%ldofs
            estif=>tabss(ielem)%estif
            estif0=>tabss(ielem)%estif0
            nevab=size(ldofs)
            do j= 1,nevab
                jdofn=ldofs(j)
                jeq  =totveq(jdofn)
                if (jeq/=0) then
                    colum0=iseq(jeq)-jeq
                    do i=1,nevab
                        idofn=ldofs(i)
                        ieq  =totveq(idofn)
                        if (ieq/=0.and.ieq<=jeq) then
                            colum=colum0+ieq
                            global_stiff1w(colum)=global_stiff1w(colum)+estif(i,j)*coef
                            global_stiff1w(colum)=global_stiff1w(colum)+estif0(i,j)*coef0

                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+ &
                                estif(j,i)*coef
                            if (nonsym==1)global_stiff2w(colum)=global_stiff2w(colum)+ &
                                estif0(j,i)*coef0

                        endif
                    end do
                endif
            end do
            nullify(ldofs,estif,estif0)
        endif
    end do
    end subroutine assemble_absorb_solid_w


    !20220713
    subroutine main_stran_r( stemp, strem)
    !
    !      obtain the principal straines
    !
    real   (irk) devia(6), stemp(:), strem(:)
    real   (irk) root3,pei,smean,varj2,varj3,steff,sint3,theta,delta
    real   (irk) a1,a2,a,fj,abs

    if (ndimn==2) then
        delta=sqrt((stemp(1)-stemp(2))**2/4+stemp(3)**2)
        strem=0.
        if (delta.lt.1.e-15) return
        strem(1)=(stemp(1)+stemp(2))/2.+delta
        strem(2)=(stemp(1)+stemp(2))/2.-delta
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

    return
    end subroutine main_stran_r

    !====================================================================
    subroutine Get_SandPZ_lamda(matno,steff,theta,smean,stran,lamda)
    real   (irk) stran(:),lamda,lamda2,lamda3,sigmad1,sigmad2,sigmad3,strain_s,pei,ps(3),theta,steff,smean,h0
    integer(ink) matno,curvL,curvL2,curvL3
    real(irk),allocatable::stemp(:),stmin(:)

    pei   = 3.14159
    ps(3)=-(2.*steff/sqrt(3.d0)*sin(theta+2*pei/3.)+smean)
    ps(2)=-(2.*steff/sqrt(3.d0)*sin(theta         )+smean)
    ps(1)=-(2.*steff/sqrt(3.d0)*sin(theta+4*pei/3.)+smean)

    allocate(stemp(size(stran)),stmin(ndimn))
    stemp=stran
    stran(ndimn+1:3*(ndimn-1))=.5*stran(ndimn+1:3*(ndimn-1))
    call main_stran_r( stemp, stmin)

    if(ndimn==2)strain_s=abs((stmin(1)-stmin(2)))   !*0.5  !最大剪应变(2D) !zhao
    if(ndimn==3)strain_s=abs((stmin(1)-stmin(3)))   !*0.5  !最大剪应变(3D)

    sigmad1=props(matno)%mechanical%solid%SandPZ%sigmad(1)
    sigmad2=props(matno)%mechanical%solid%SandPZ%sigmad(2)
    sigmad3=props(matno)%mechanical%solid%SandPZ%sigmad(3)

    curvL =props(matno)%mechanical%solid%SandPZ%bline(1)
    curvL2=props(matno)%mechanical%solid%SandPZ%bline(2)
    curvL3=props(matno)%mechanical%solid%SandPZ%bline(3)


    call parameter_find(curvL,strain_s,lamda,h0)
    call parameter_find(curvL2,strain_s,lamda2,h0)
    call parameter_find(curvL3,strain_s,lamda3,h0)
    !write(7,*)'strain_s=',strain_s,'lamda=',lamda,'lamda2=',lamda2,'lamda3=',lamda3
    ps(3)=abs(ps(3))
    if (ps(3)>sigmad1.and.ps(3)<sigmad3) then
        lamda =((ps(3)-sigmad2)*(ps(3)-sigmad3))/((sigmad1-sigmad2)*(sigmad1-sigmad3))*lamda+((ps(3)-sigmad1)*(ps(3)-sigmad3))/((sigmad2-sigmad1)*(sigmad2-sigmad3))*lamda2+((ps(3)-sigmad1)*(ps(3)-sigmad2))/((sigmad3-sigmad1)*(sigmad3-sigmad2))*lamda3
    elseif(ps(3)>=sigmad3) then
        lamda =lamda3
    endif
    !write(7,*)'ps=',ps
    !write(7,*)'sigmad1-3=',sigmad1,sigmad2,sigmad3
    !write(7,*)'lamda=',lamda

    deallocate(stemp,stmin)
    end subroutine Get_SandPZ_lamda

    !20220713

    subroutine epcurveEP(siggpvz,matno,ep) !ep2010
    integer(ink) matno,np,igaus,ip
    real   (irk) ep,e,nu,sigz,esx,slop,siggpvz
    real   (irk),pointer::p(:),es(:)
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
    np=props(matno)%mechanical%solid%ELASTIC_EP%np
    p=>props(matno)%mechanical%solid%ELASTIC_EP%p
    es=>props(matno)%mechanical%solid%ELASTIC_EP%es
    sigz=-siggpvz
    if (sigz<=p(1))then
        ep=e
        nullify(p,es)
        return
    endif
    do ip=1,np-1
        if(sigz>p(ip).and.sigz<=p(ip+1))then
            slop=(es(ip+1)-es(ip))/(p(ip+1)-p(ip))
            esx=es(ip)+slop*(sigz-p(ip))
        endif
    enddo
    if(sigz>p(np))then
        slop=(es(np)-es(np-1))/(p(np)-p(np-1))
        esx=es(np)+slop*(sigz-p(np))
    endif
    ep=esx*(1.-2.*nu*nu/(1.-nu))
    if(ep<e)ep=e
    nullify(p,es)
    end subroutine epcurveEP

    subroutine escurveEP(sigeffect,sig0,ep,matno) !20211125

    integer(ink) matno,np,i
    real   (irk) sigeffect,ep,sig0
    real   (irk),pointer::sig(:),es(:)


    np=props(matno)%mechanical%solid%STEEL_EP%np
    sig=>props(matno)%mechanical%solid%STEEL_EP%sig
    es=>props(matno)%mechanical%solid%STEEL_EP%es
    if(sigeffect>sig(1).and.sigeffect<sig0)then  !对应于屈服后的卸载状态
        ep=es(1)
        goto 10
    endif
    do i=1,np
        if(sigeffect<sig(i))then
            ep=es(i)
            goto 10
        end if
    end do
    ep=0.
10  continue

    nullify(sig,es)
    end subroutine escurveEP   !20211125

    subroutine effect_stres_modul_for_steel_beam !20211125
    character(1)field1
    character(30)material
    integer(ink) igroup,index,matno,csigma,nstre,ielgroup,ielem
    integer(ink),pointer::lnods(:)
    real   (irk) aera,sigeffect,sig0,ep
    real   (irk),pointer::rotation(:,:)
    real   (irk),allocatable::sig(:),trot(:,:),force_e(:),force_i(:),trotx(:,:)

    allocate(sig(ndimn))
    sig=0.
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)<=0.or.field1/='U')cycle
        index = group(igroup)%index
        if (index/=20.and.index/=21) cycle
        matno = group(igroup)%matno
        material=props(matno)%mechanical%solid%material
        if(material/='STEEL_EP')cycle
        csigma=props(matno)%mechanical%solid%STEEL_EP%csigma
        aera=props(matno)%geometry%aera
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

                force_e=element(ielem)%field(1)%tload
                force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1) !20200116,(ndimn-2)->(ndimn-1)
                force_i=force_i-force_e
            else !20200205 (BM,index==20)

                force_e=element(ielem)%field(1)%tload
                force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1)  !20200116
                force_i=force_i-force_e !不需要用trot.x.force_e，%tload和%gpvar都是整体坐标系内的
                force_e=force_i
                force_i=trot.x.force_e  !转成局部坐标系下的内力
            endif
            sig(1:ndimn)=force_i(1:ndimn)/aera
            sigeffect=0.
            if(csigma==1)then
                sigeffect=abs(sig(1))
            elseif(csigma==2)then
                sigeffect=sqrt(sig(1)**2+3*(sig(2)**2+sig(3)**2))
            endif
            sig0=element(ielem)%field(1)%sigz(1)
            !write(7,*)'ielem=',ielem,'sig0=',sig0,'sigeffect=',sigeffect
            call escurveEP(sigeffect,sig0,ep,matno)
            if(sigeffect>sig0)  &
                element(ielem)%field(1)%sigz(1)=sigeffect
            !write(7,*)'sig1=',element(ielem)%field(1)%sigz(1)
            element(ielem)%field(1)%ep=ep
            nullify(lnods,rotation)
        end do
        deallocate(trot,force_e,force_i,trotx)
    end do

    deallocate(sig)
    end subroutine effect_stres_modul_for_steel_beam   !20211125


    subroutine stiffness_for_bolt_spring !20211125
    character(1)field1
    character(30)material
    integer(ink) igroup,index,matno,nstre,ielgroup,ielem
    integer(ink),pointer::lnods(:)
    real   (irk) ktheta1,ktheta2
    real   (irk),pointer::rotation(:,:),kxyz(:)
    real   (irk),allocatable::sig(:),trot(:,:),force_e(:),force_i(:),trotx(:,:)

    allocate(sig(ndimn))
    sig=0.
    DO igroup =1,ngroup
        field1= group(igroup)%fieldid(1:1)
        if (appear(igroup)<=0.or.field1/='U')cycle
        index = group(igroup)%index
        if (index/=20.and.index/=21) cycle
        matno = group(igroup)%matno
        material=props(matno)%mechanical%solid%material
        if(material/='STEEL_SP')cycle
        kxyz=>props(matno)%mechanical%solid%STEEL_SP%kxyz
        ktheta1=props(matno)%mechanical%solid%STEEL_SP%ktheta1
        ktheta2=props(matno)%mechanical%solid%STEEL_SP%ktheta2

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

                force_e=element(ielem)%field(1)%tload
                force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1) !20200116,(ndimn-2)->(ndimn-1)
                force_i=force_i-force_e
            else !20200205 (BM,index==20)

                force_e=element(ielem)%field(1)%tload
                force_i=element(ielem)%field(1)%gpvar(1:6*(ndimn-1),1)  !20200116
                force_i=force_i-force_e !不需要用trot.x.force_e，%tload和%gpvar都是整体坐标系内的
                force_e=force_i
                force_i=trot.x.force_e  !转成局部坐标系下的内力
            endif

            !element(ielem)%field(1)%kdiag(1:ndimn)=0.
            element(ielem)%field(1)%kdiag(1:ndimn)=kxyz
            if(force_i(3*(ndimn-1))>=0.)then
                element(ielem)%field(1)%kdiag(3*(ndimn-1))=ktheta1
            else
                element(ielem)%field(1)%kdiag(3*(ndimn-1))=ktheta2
            endif
            nullify(lnods,rotation)
        end do
        deallocate(trot,force_e,force_i,trotx)
        nullify(kxyz)
    end do

    deallocate(sig)
    end subroutine stiffness_for_bolt_spring   !20211125


    subroutine find_e_NOLINORMK(matno,rotation,stres,ep) !ep2010
    integer(ink) matno,np,ip,idimn
    real   (irk) ep,e,esx,slop,sigz,rotation(:,:),stres(:)
    real   (irk),pointer::p(:),es(:)
    real   (irk),allocatable::tensor(:,:),a3(:)
    allocate(tensor(ndimn,ndimn),a3(ndimn)) ; tensor=0. ; a3=0.

    e  =props(matno)%mechanical%solid%e
    np=props(matno)%mechanical%solid%np
    p=>props(matno)%mechanical%solid%normalstress
    es=>props(matno)%mechanical%solid%normale
    do idimn=1,ndimn
        tensor(idimn,idimn)=stres(idimn)
    end do
    if (ndimn==2) then
        tensor(1,2)=stres(3)
        tensor(2,1)=stres(3)
    elseif(ndimn==3) then
        tensor(1,2)=stres(4)
        tensor(1,3)=stres(6)
        tensor(2,3)=stres(5)
        tensor(2,1)=stres(4)
        tensor(3,1)=stres(6)
        tensor(3,2)=stres(5)
    endif
    do idimn=1,ndimn
        a3(idimn)=dot_product(tensor(idimn,:),rotation(1,:))
    enddo

    sigz=dot_product(a3,rotation(1,:))



    if (sigz<=p(1))then
        ep=e
        nullify(p,es)
        return
    endif
    do ip=1,np-1
        if(sigz>p(ip).and.sigz<=p(ip+1))then
            slop=(es(ip+1)-es(ip))/(p(ip+1)-p(ip))
            esx=es(ip)+slop*(sigz-p(ip))
        endif
    enddo
    if(sigz>p(np))then
        slop=(es(np)-es(np-1))/(p(np)-p(np-1))
        esx=es(np)+slop*(sigz-p(np))
    endif
    ep=esx
    if(ep<e)ep=e
    nullify(p,es)
    deallocate(tensor,a3)
    end subroutine find_e_NOLINORMK

    END MODULE     STIFFNESS_MATRIX
