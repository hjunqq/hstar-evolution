Module levelset
  use variable_types
  USE ARRAYUTIL
  USE GLOBAL_VAR

implicit none
 
    character(80)textl 

	integer(ink) glbunitl,gidmshl,gidresl,chkunitl,lenth,npoinl,neleml,icvel,nvfix,icpres, &
	             npfix,nabso,nbour,nfric,norder,ncompres,nfs,icdelt,icdt2,nconst,nmatsl,   &
				 ifunc,ntmax,niter,ntspd,bounchsl,nabsop,ninter,ntotg,nbucle,ntmaxpcf,     &
				 bouunitl,nedgel,icstaticp,begstepp,begsepv,icwritemesh

    real   (irk) AZERO,BZERO,OMEGA,tf,delt,csafe,timepd,xmin,csafepcf,tolep,swl,timend,timel 

    integer(ink),allocatable::otonew(:),ntoold(:),ifpcf(:),ifpre(:,:),iffixp(:),babso(:),  &
	                          babsop(:),btanr(:),ipibp(:)
	real   (irk),allocatable::const2(:),const1(:,:),unkno(:,:),tpres(:),veloc0(:,:),       &
	                          fixedp(:),wnorpr(:,:),wnor(:,:),pcf(:),rhonod(:),granel(:,:),&
							  granod(:,:),mmatl(:),rotatp(:,:,:),thetag(:)
    real   (irk),allocatable::groundv(:),groundv1(:),fachvold(:),statp(:)
!******************************************************************************from timestep
	integer(ink) itimepcf
	real   (irk) ctimpd,dtpcf,deltpcf,timepcf
	real   (irk) ,allocatable::deltel(:),flux(:,:,:),unkne(:,:),eload(:),rhs(:,:),delun(:,:),&
	                           dpres(:),tpres1(:),pcfe(:),sigfin(:),deltelpcf(:),finod12(:), &
							   granel12(:,:),sigfie12(:)
!******************************************************************************from timestep
	                     
    type gauss_edge_l
	     real(irk) djacb
         real(irk),pointer::shape(:),cartd(:,:),rotation(:,:),normal(:)
    end type gauss_edge_l

    type edge_define_l
         integer(ink) nnode,ngaus,index,aelem,ikind,ndimn,ic,selem
         integer(ink),pointer::lnods(:),lnods_f(:),ldofe(:),ipi(:)
		 real   (irk),pointer::normal(:),edload(:)
         type(gauss_edge_l),pointer::edgegaus(:)
    end  type edge_define_l

    type(edge_define_l),allocatable::edgesl(:)
 
contains

!------------------------------------------------------------------------------

    subroutine levelsetmain

!------------------------------------------------------------------------------

	integer(ink) ipoin
    real   (irk) dtmin
		
	if(istep==1)call globaldate

	if(level_set_problem==2.and.istep>=begsepv)call vpreagain !special
	!if(level_set_problem==2)call viniagain

!DO WHILE (timel<timend.and.itime<=ntmax.and.delt>=dtmin ) ! ---- LOOP  timel

    call check_delt

    timel=timel+delt

    if(timel>timend)then
	write(*,*)'stop , timel>timend!!'
	call output
	stop
	endif

	if (istep==1) dtmin=delt*1.e-9
    if (delt.lt.dtmin) then
        write(*,*) 'delt=',delt,' < ','dtmin=',dtmin
		call output
        stop
    endif

	call first_step

    call second_step

	call jacobi_solver(delun,rhs,ndimn)

	call addvelocity

    !-------- Pressure equation 

    call stiff
   
	call deltap

	call solvegc

	if(sum(eload)==0.)dpres=0
	
	call finalp

    !for eload of dynamic pressure , caculated in last step.

	if(level_set_problem==2.and.istep>=begstepp) call pressure 

    call rhsvel	 

	call jacobi_solver(delun,rhs,ndimn)

	call addvelocity

   ! af. solve N-S equ.
	
	call first_stepf

	call second_stepf

    call jacobi_solver(delun,rhs,1)

	call addthemf

	do ipoin=1,npoinl 	                                    
	   if (pcf(ipoin).gt.0.9*xmin)  pcf(ipoin)= xmin
	   if (pcf(ipoin).lt.-0.9*xmin) pcf(ipoin)=-xmin
    enddo

    !------  loop over the  timesteps,for evolving grand pcf to steady state

    itimepcf=0
	timepcf =0. 

    do  while (itimepcf.lt.ntmaxpcf) 

        itimepcf = itimepcf + 1

		call  signo (npoinl,pcf,sigfin)

        call gradfi (pcf,granel)
    
	    if (itimepcf.eq.1.and.istep==1)call  check_deltPCF

        timepcf  = timepcf + deltpcf

		call first_stepPCF

		call finod_12

		call  signo (ntotg,pcfe,sigfie12)

		call gradfi (finod12,granel12)

		call second_stepPCF

        call jacobi_solver(delun,rhs,1)

		call addthemPCF

	    do ipoin=1,npoinl
	       if (abs(pcf(ipoin)).lt.xmin)cycle                
	       if (ifpcf(ipoin).ne.0)      cycle                
           pcf(ipoin)=finod12(ipoin)
        enddo
 
		!call gradfi (pcf,granel)

    enddo

	!end loop for evolving grand pcf to steady state

	call interpol 

    ctimpd = ctimpd + delt
    
    if (ctimpd.ge.timepd) then

	   !call gradfi (pcf,granel) !only for output

	   !call output_grandfi

       call output

        ctimpd = 0.0
    endif

!END DO                                                    !----END LOOP timel 
                                                 
    end subroutine levelsetmain


!!************************************************************************************************
!!################################################################################################
!!************************************************************************************************

!------------------------------------------------------------------------------

	subroutine globaldate

!------------------------------------------------------------------------------
    integer(ink)i,imats,iconst,ielem,igroup,ip,ngaus,ipoin,igaus,index,order_int,nnode, &
	            jnode,inode,jpoin 
	real   (irk)twopi,dvolu,minedge0,minedge
	integer(ink),allocatable::ic0(:)
	integer(ink),pointer    ::lnods(:)

    glbunitl=1001
	bouunitl=1002
	gidmshl =1003
	gidresl =1004
	chkunitl=1099
    lenth=len_trim(probn)
	open(glbunitl,  file=probn(1:lenth)//'_l.glb') 
	open(bouunitl,  file=probn(1:lenth)//'_l.bou')
	open(bounchsl,  file=probn(1:lenth)//'_lbou.chs.msh')
	open(gidmshl,   file=probn(1:lenth)//'_l.flavia.msh') 
	open(gidresl,   file=probn(1:lenth)//'_l.flavia.res') 
	open(chkunitl,  file=probn(1:lenth)//'_l.chk')

	read(glbunitl,*)textl
	read(glbunitl,*)icvel,nvfix,icpres,npfix,nabso,nbour,nfric,ninter,icdelt,icdt2

	norder=1 ; ncompres=0 ; nfs=1 ; nconst=11 ; nmatsl=2 ;	ctimpd   = 0.0

    read (glbunitl,*)textl
    read (glbunitl,*)niter,ntspd,csafe,csafepcf,tolep,ntmaxpcf,swl,icstaticp,begstepp,begsepv,timend

	delt   =ditime
    timepd =ntspd*ditime 
	timel  =0 !ditime

    allocate(const2(nconst),const1(nmatsl,nconst),thetag(ndimn))
	const2=0. ; const1=0. ; thetag=0.

	read(glbunitl,*)textl
    read(glbunitl,*)const2(1:nconst)
	read(glbunitl,*)textl
	read(glbunitl,*)thetag(1:ndimn)
	twopi =4.*acos(0.0)
	thetag=thetag*twopi/360.
    read(glbunitl,*)textl
	do i=1,nmatsl
       read(glbunitl,*)imats,(const1(imats,iconst),iconst=1,nconst)
	enddo
    allocate(ic0(npoin))
	ic0=0
	neleml=0
    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
	   allocate(element(ielem)%gstif(nnode,nnode))
	   lnods=>element(ielem)%field(1)%lnods_f
	   ic0(lnods)=1
	   neleml=neleml+1
	   nullify(lnods)
	enddo
	npoinl=sum(ic0)
    write(*,*)'npoinl=',npoinl,'  neleml=',neleml
	allocate(otonew(npoin),ntoold(npoinl))
	ip=0
	do ipoin=1,npoin
	   if(ic0(ipoin)==1)then
	      ip=ip+1
		  otonew(ipoin)=ip
		  ntoold(ip)   =ipoin 
	   endif
	enddo

    allocate(ifpcf(npoinl))
	ifpcf=0
    ntotg=0
	ic0=0
	do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
	   lnods=>element(ielem)%field(1)%lnods_f

	   !! find the maxedge , as element size
	   minedge=0.
	   do inode=1,size(lnods)-1
	      ipoin=lnods(inode)
	      do jnode=inode,size(lnods)
		     jpoin=lnods(jnode)
             minedge0=sqrt(sum((coord(:,ipoin)-coord(:,jpoin))**2))
			 minedge=min(minedge0,minedge)
		  enddo
	   enddo
	   element(ielem)%minedge=minedge
	   !!end find

	   lnods=otonew(lnods)

	   if(appear_level(igroup)==2)then
	   ifpcf(lnods)=1
	   ic0(lnods)=2
	   endif

	   element(ielem)%field(1)%lnods=>lnods
	   element(ielem)%area=0.
	   do igaus=1,ngaus
	      dvolu=element(ielem)%egaus(order_int)%djacb(igaus)
          element(ielem)%area=element(ielem)%area+dvolu
	   enddo
	   ntotg=ntotg+ngaus
       element(ielem)%ktotg=ntotg-ngaus
	   nullify(lnods)	
	   element(ielem)%elength=(element(ielem)%area)**(1./ndimn)   	   
	enddo

	do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)/=1)cycle
       lnods=>element(ielem)%field(1)%lnods
       do inode=1,size(lnods)
	      ipoin=lnods(inode)
		  if(ic0(ipoin)==2)then
            ifpcf(ipoin)=1 !0
		  else
		    ifpcf(ipoin)=-1
		  endif
	   enddo
       nullify(lnods)
	enddo
	deallocate(ic0)
    allocate(unkno(ndimn,npoinl),tpres(npoinl))
	unkno=0.0 ; tpres= 0.0
	call readinitial

    allocate(ifpre(ndimn,npoinl),veloc0(ndimn,npoinl),fixedp(npoinl),iffixp(npoinl))
			ifpre=0 ; veloc0=0.0 ; fixedp=0.0 ; iffixp=0 

	call readprescrib

    allocate(babso(nabso),babsop(nabsop),btanr(nbour),wnorpr(ndimn,nbour))
	         babso=0 ; babsop=0 ; btanr=0 ; wnorpr=0.0

	call readbondary

    allocate(ipibp(npoinl),wnor(ndimn,npoinl),rotatp(ndimn,ndimn,npoinl))
	         ipibp=0 ; wnor=0.0 ; rotatp=0.0
    
	allocate(mmatl(npoinl))
	mmatl=0.0

	call getmmatl

    call boundary

	allocate(pcf(npoinl))
	pcf=0.0

	call fixpc
    
	allocate(rhonod(npoinl))
	rhonod=0.0
	call interpol

	allocate(granel(ndimn,ntotg))
	granel=0.0

	allocate(deltel(nelem),flux(ndimn,ndimn,npoinl),delun(ndimn,npoinl),eload(npoinl),     &
	         rhs(ndimn,npoinl),unkne(ndimn,ntotg),dpres(npoinl),tpres1(npoinl),pcfe(ntotg),&
			 sigfin(npoinl),granod(ndimn,npoinl),deltelpcf(nelem),finod12(npoinl),         &
             granel12(ndimn,ntotg),sigfie12(ntotg))
			 
			 deltel=0. ; flux=0. ;  delun=0. ; eload=0. ; rhs=0. ; unkne=0. ; dpres=0.  
			 tpres1=0. ; pcfe=0. ; sigfin=0. ; granod=0.; deltelpcf=0. ; finod12=0. 
			 granel12=0. ; sigfie12=0. 

	allocate(groundv(ndimn),groundv1(ndimn),fachvold(ndimn),statp(npoinl))
	groundv=0. ; groundv1=0. ;fachvold=0. ; statp=0.

	call initial_pres

	call static_pressure
    
	if(icpres==3)tpres=statp

	icwritemesh=1

    call output

    icwritemesh=0

    end subroutine globaldate

!------------------------------------------------------------------------------

	subroutine readinitial

!------------------------------------------------------------------------------
 
    integer(ink) ipoin,iicvel
	real   (irk) tpres0
	real   (irk),allocatable::velo(:)

    allocate(velo(ndimn))
	velo=0.0
!      ------  Velocity field:initial conditions

    if (icvel.ne.0) then
	   if (icvel==1)then
           read (glbunitl,*) textl
           read (glbunitl,*) velo(1:ndimn)
		   do ipoin=1,npoinl
              unkno(:,ipoin) = velo
		   enddo
	   endif
	   if(icvel>1)then
		   read(glbunitl,*)textl
		   do iicvel=1,icvel
		      read(glbunitl,*)ipoin,velo(1:ndimn)
			  ipoin=otonew(ipoin)
			  unkno(:,ipoin)=velo
		   enddo
	   endif
    endif
	deallocate(velo)

!      ------  Pressure field:initial conditions in subroutine Initial_pres  

    if (icpres.eq.0) then
        tpres= 0.
    elseif (icpres.eq.1) then
        read (glbunitl,*) textl
        read (glbunitl,*) tpres0
        tpres= tpres0
    endif

	end subroutine readinitial

!------------------------------------------------------------------------------

	subroutine readprescrib

!------------------------------------------------------------------------------

    integer(ink) ipoin,ifx,ivfix,idimn,ipfix,icode
	real   (irk) facti,yhigh,ro
	real   (irk),allocatable::presc(:),cnd(:)

!     read prescribed velocities function

    allocate(presc(ndimn),cnd(ndimn))
	presc=0. ; cnd=0. 
    read(glbunitl,*)textl
    read(glbunitl,*)ifunc,AZERO,BZERO,OMEGA,tf
	if (nvfix.ne.0) then
       read(glbunitl,*)textl	
       do ivfix=1,nvfix
          READ(glbunitl,*)ipoin,ifx,(presc(idimn),idimn=1,ndimn)
		  ipoin=otonew(ipoin)
		  if(ndimn==2)then
		     if(ifx.ge.10)then
                ifpre(1,ipoin)=ifx/10
                ifx=ifx-ifpre(1,ipoin)*10
             end if
             if(ifx.gt.0)ifpre(2,ipoin)=ifx
		  endif
		  if(ndimn==3)then
             if(ifx.ge.100)then
                ifpre(1,ipoin)=ifx/100
                ifx=ifx-ifpre(1,ipoin)*100
		     endif
			 if(ifx>=10)then
			    ifpre(2,ipoin)=ifx/10
			    ifx=ifx-ifpre(2,ipoin)*10
			 endif
             if(ifx.gt.0)ifpre(3,ipoin)=ifx
		  endif

	      do idimn=1,ndimn
	         if(ifpre(idimn,ipoin).eq.1.or.ifpre(idimn,ipoin).eq.2) &
             veloc0(idimn,ipoin)=presc(idimn)
	         if(ifpre(idimn,ipoin).eq.2) then
	            cnd=coord(:,ntoold(ipoin))
 				call functs(ifunc,timend,AZERO,BZERO,OMEGA,timel,tf,cnd,facti)
	            unkno(idimn,ipoin)=veloc0(idimn,ipoin)*facti
             endif
	      enddo
       end do
	end if
    deallocate(presc)

	if (npfix.ne.0) then 
       read(glbunitl,*)textl
       do ipfix=1,npfix
          read(glbunitl,*)icode,iffixp(otonew(icode)),fixedp(otonew(icode)),yhigh,ro
		  icode=otonew(icode)
          fixedp(icode)=fixedp(icode)+const2(1)*(yhigh-coord(2,ntoold(icode)))*ro    
	      tpres(icode)=fixedp(icode)
      end do
	endif
    deallocate(cnd)

	end subroutine readprescrib

!------------------------------------------------------------------------------

	subroutine readbondary

!------------------------------------------------------------------------------

	integer(ink) j,ibour,idimn

    if(nabso.ne.0)then
       read(glbunitl,*)textl
       read(glbunitl,*)(babso(j),j=1,nabso)
	   babso=otonew(babso)
      end if

    if(nbour.ne.0)then
       read(glbunitl,*)textl
       do ibour=1,nbour
          read(glbunitl,*)btanr(ibour),(wnorpr(idimn,ibour),idimn=1,ndimn)
		  btanr=otonew(btanr)
       end do
    end if

	end subroutine readbondary

!------------------------------------------------------------------------------
    
	subroutine getmmatl

!------------------------------------------------------------------------------

    integer(ink) ielem,index,ngaus,nnode,igaus,in,jn,inode,order_int,igroup
	real   (irk) dvolu,djacb,tdiagm
	real   (irk),allocatable::diagm(:)
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::shape(:)

	mmatl=0.0
    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
	   lnods    =>element(ielem)%field(1)%lnods

	   allocate(diagm(nnode),element(ielem)%mmat(nnode,nnode))
       element(ielem)%mmat=0.0
	   diagm=0.
	   dvolu=0.
       do igaus=1,ngaus
          shape=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          djacb=element(ielem)%egaus(order_int)%djacb(igaus)
          !lump mass matrix
          do in=1,nnode
             diagm(in)=diagm(in)+djacb*shape(in)*shape(in)
          end do
          dvolu=dvolu+djacb
          !distributional mass matrix
          do in=1,nnode
             do jn=1,nnode
                element(ielem)%mmat(in,jn)=element(ielem)%mmat(in,jn)+djacb*shape(in)*shape(jn)
             end do
          end do
          nullify(shape)
       end do     !!igaus
       tdiagm=sum(diagm)
       tdiagm=dvolu/tdiagm
	   diagm =diagm*tdiagm
	   do inode=1,nnode
		  mmatl(lnods(inode))=mmatl(lnods(inode))+diagm(inode)
	   end do
       nullify(lnods)
       deallocate(diagm)
    end do    !ielem

    end subroutine getmmatl

!------------------------------------------------------------------------------
    
	subroutine boundary

!------------------------------------------------------------------------------

! get the boundery information, line elements,nodes and tangent

    integer(ink) tedge,iedge,sedge,nnode,index,ikind,edimn,ngaus,inode,i0,ig,ipoin,jedge, &
                 ibour,idimn,ia,ic,order_int,selem,indey,nnode_f,nfdof,jnode,jpoin,i1,i2, &
				 ndofn_f,igroup,idofn
	real   (irk) djacb,weigp,aa,facti
	integer(ink),allocatable::lnods(:)
	real   (irk),allocatable::shape(:),cartd(:,:),deriv(:,:),s(:,:),rr(:,:),a3(:),elcod(:,:), &
	                          elcod0(:,:),cnd(:),normal(:),rotation(:,:),velttn(:),xjaci(:,:)

    write(bounchsl,*)'MESH dimension 3 ElemType linear  Nnode 2'
    write(bounchsl,*)'Coordinates'
    do ipoin=1,npoinl
       write(bounchsl,*)ipoin,(coord(idimn,ntoold(ipoin)),idimn=1,ndimn)
    enddo
    write(bounchsl,*)'end coordinates'
!!  new , initialize icbound
    element(1:nelem)%icbound=0

    read(bouunitl,*)textl
	read(bouunitl,*)nedgel
	tedge=0

	allocate(edgesl(nedgel))
	do while(tedge<nedgel)

       read(bouunitl,*)textl
	   read(bouunitl,*)sedge,nnode,index,ic !ic=1---for FSI , ic=2---for others 
	   if(index==1)write(bounchsl,*)'MESH dimension 3 ElemType linear  Nnode 2'
	   if(index==5)write(bounchsl,*)'MESH dimension 3 ElemType Quadrilateral  Nnode 4'
	   write(bounchsl,*)'Coordinates'
       write(bounchsl,*)'end coordinates'
	   write(bounchsl,*)'elements'
       do iedge=1,sedge 
          tedge=tedge+1
          edgesl(tedge)%nnode=nnode
          edgesl(tedge)%index=index
          edgesl(tedge)%ic   =ic
          allocate(edgesl(tedge)%lnods(nnode),edgesl(tedge)%lnods_f(nnode), &
		           edgesl(tedge)%ipi(npoinl))
          edgesl(tedge)%ipi=0
		  if(ic==1) &
          read(bouunitl,*)i0,edgesl(tedge)%lnods_f(1:nnode),edgesl(tedge)%aelem,edgesl(tedge)%selem
		  if(ic/=1) &
          read(bouunitl,*)i0,edgesl(tedge)%lnods_f(1:nnode),edgesl(tedge)%aelem	

		  edgesl(tedge)%lnods=otonew(edgesl(tedge)%lnods_f)
		  edgesl(tedge)%ipi(edgesl(tedge)%lnods)=1 
          element(edgesl(tedge)%aelem)%icbound=1

		  write(bounchsl,'(10i10)')tedge,edgesl(tedge)%lnods(1:nnode), &
		                          element(edgesl(tedge)%aelem)%group 
          if(ic/=1)cycle !ic=1--FSI boundary, ic/=1--others

          selem   =edgesl(tedge)%selem
          indey   =element(selem)%index
          nnode_f =elkn(indey)%el_field(1)%nnode_f
          ndofn_f =ndimn
	      igroup  =element(selem)%group
          nfdof   =group(igroup)%dof(1)%nfdof

          allocate(edgesl(tedge)%ldofe(nnode*ndofn_f), &
		           edgesl(tedge)%edload(ndofn_f*nnode)) !pay attention
		  edgesl(tedge)%edload=0.
          do inode=1,nnode                  
             ipoin=edgesl(tedge)%lnods_f(inode) !gbobal point!!
             do jnode=1,nnode_f        
                jpoin=element(selem)%field(1)%lnods_f(jnode)
                if(ipoin.eq.jpoin)exit
             end do                    
             do idofn=1,ndofn_f        
                i1=(inode-1)*ndofn_f+idofn
                i2=(jnode-1)*nfdof+idofn
                edgesl(tedge)%ldofe(i1)=i2
             end do                    
          end do                                                                                                                		     
	   enddo
	   write(bounchsl,*)'end elements'
	enddo

	do iedge=1,nedgel !iedge
       index    =edgesl(iedge)%index
       nnode    =edgesl(iedge)%nnode
       edimn    =elkn(index)%ndimn
       !order_int=elkn(index)%el_field(1)%order_intrules(2)  !!!(2)  ????
       order_int=elkn(index)%el_field(1)%order_intrules(1)  
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
	   edgesl(iedge)%ngaus=ngaus
	   edgesl(iedge)%ndimn=edimn
       allocate(edgesl(iedge)%edgegaus(ngaus))
       allocate(lnods(nnode),elcod(nnode,edimn+1))
	   lnods=0 ; elcod=0.
       lnods=edgesl(iedge)%lnods_f !special
       do inode=1,nnode
          elcod(inode,:)=coord(:,lnods(inode))
       end do
       allocate(shape(nnode),deriv(edimn,nnode),cartd(edimn,nnode))
       allocate(s(edimn+1,edimn+1),a3(edimn+1),elcod0(edimn,nnode))
       allocate(rr(ndimn,ndimn),normal(ndimn),xjaci(edimn,edimn))
	   normal=0. ; shape=0. ; deriv=0. ; cartd=0. ; s=0. ; a3=0. ; elcod0=0. ; rr = 0.
       do ig=1,ngaus
          allocate(edgesl(iedge)%edgegaus(ig)%cartd(edimn,nnode),       &
                   edgesl(iedge)%edgegaus(ig)%shape(nnode),             &
                   edgesl(iedge)%edgegaus(ig)%rotation(edimn+1,edimn+1),&
				   edgesl(iedge)%edgegaus(ig)%normal(edimn+1),          &
				   edgesl(iedge)%normal(edimn+1))	
          shape=elkn(index)%ggaus(order_int)%shape(:,ig)
          deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
          weigp=elkn(index)%ggaus(order_int)%weigp(ig)
          edgesl(iedge)%edgegaus(ig)%shape=shape

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
		  normal=normal+a3
          edgesl(iedge)%edgegaus(ig)%normal=a3 !special 
          call cosc(edimn+1,a3,elcod0,elcod,rr)
          call jacob(iedge, edimn, nnode,elcod0,deriv,cartd, djacb,xjaci)

          edgesl(iedge)%edgegaus(ig)%djacb   =djacb*weigp
          edgesl(iedge)%edgegaus(ig)%cartd   =cartd
          edgesl(iedge)%edgegaus(ig)%rotation=transpose(rr)
		  
       end do !!ig
       edgesl(iedge)%normal=normal/ngaus
       deallocate (shape,deriv,cartd,s,a3,elcod0,elcod,lnods,rr,normal,xjaci)
    end do !iedge

	wnor=0.0
	allocate(normal(ndimn))
	normal=0. ; ipibp=0	
	do iedge=1,nedgel
	   nnode=edgesl(iedge)%nnode
	   allocate(lnods(nnode))
	   lnods=edgesl(iedge)%lnods
	   do inode=1,nnode
	      ipoin=lnods(inode)
		  if(ipibp(ipoin)==1)cycle
		  normal=0
          do jedge=1,nedgel
		     if(edgesl(jedge)%ipi(ipoin)==0)cycle
			   normal=normal+edgesl(jedge)%normal
		  enddo
		  normal=normal/sqrt((sum(normal**2)))
	      wnor(:,ipoin)=normal
	      ipibp(ipoin)=1 !boundary point
	   enddo
	   deallocate(lnods)	   
	enddo
	deallocate(normal)	

    if(nbour.ne.0)then
       do ibour=1,nbour
          ipoin=btanr(ibour)
          wnor(:,ipoin)=wnorpr(:,ibour)			
       end do
    end if
	allocate(rr(ndimn,ndimn))
	rr=0.
	do ipoin=1,npoinl
	   if(ipibp(ipoin)==0)cycle
	   call direct_l(wnor(:,ipoin),rr,ndimn) !ndimn==edimn+1
	   rotatp(:,:,ipoin)=rr !rotation of ipoin
	enddo
    deallocate(rr)

!------------------------------------------------------------------

    allocate(cnd(ndimn),rotation(ndimn,ndimn),velttn(ndimn))
	do ipoin=1,npoinl                         	  
       if(any(ifpre(:,ipoin)==1))then
	      cnd=coord(:,ntoold(ipoin))
		  call FUNCTS(ifunc,timend,AZERO,BZERO,OMEGA,timel,tf,cnd,facti)
		  rotation=rotatp(:,:,ipoin)
		  velttn=matmul(rotation,unkno(:,ipoin)) 
		  do idimn=1,ndimn
		     if(ifpre(idimn,ipoin)==1)velttn(idimn)=-veloc0(idimn,ipoin)*facti
		  enddo
		  unkno(:,ipoin)=matmul(transpose(rotation),velttn)
	   endif
	enddo
    deallocate(cnd,rotation,velttn)

	do iedge=1,nedgel
	   allocate(lnods(nnode))
	   nullify(edgesl(iedge)%ipi)
	   nnode=edgesl(iedge)%nnode
	   lnods=edgesl(iedge)%lnods
	   do inode=1,nnode
	      ipoin=lnods(inode)
		  if(sum(ifpre(:,ipoin))/=0)cycle
		  do ia=1,nabso
		     if(babso(ia).eq.ipoin)goto 16
		  enddo
		  ifpre(:,ipoin)    =0
		  ifpre(ndimn,ipoin)=1
16	   enddo
	   deallocate(lnods)

	enddo

	end subroutine boundary

!------------------------------------------------------------------------------

    subroutine fixpc

!------------------------------------------------------------------------------

	integer(ink) ielem,ipoin,icode,igroup,nfixpcf
	real   (irk) elength,cinter,fixpcf

	cinter=const2(7)
    xmin  =0.0
    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle
	   elength=element(ielem)%elength
       if(elength.gt.xmin)xmin=elength
    end do
    write(*,*)'Maximum size =',xmin
    xmin=cinter*xmin  
	write(*,*)'Xmin=         ',xmin  
	do ipoin=1,npoinl
       pcf(ipoin)=real(ifpcf(ipoin))*xmin
	   ifpcf(ipoin)=0
    enddo

	read (glbunitl,*)textl
	read(glbunitl,*)nfixpcf
	ifpcf=0
	do ipoin=1,nfixpcf
	   read (glbunitl,*) icode, ifpcf(otonew(icode)), fixpcf
	   if (ifpcf(otonew(icode)).ne.0) pcf(otonew(icode))=fixpcf/abs(fixpcf)*xmin  
	enddo 

	read (glbunitl,*)textl
	read(glbunitl,*)icode
	if(icode==0)return
	do ipoin=1,npoinl
	   read(glbunitl,*)icode,pcf(otonew(icode))
	enddo

	end subroutine fixpc

!------------------------------------------------------------------------------

	subroutine interpol 

!------------------------------------------------------------------------------

	integer(ink) ipoin
	real   (irk) aux,slopro,ctero,pi  

	if(nmatsl.eq.2)then
	if (ninter.eq.1)then 
	   aux=0.
	   slopro=(const1(2,1)-const1(1,1))/(2.*xmin)
	   ctero = const1(1,1)
	   do ipoin=1,npoinl
	      aux=min(xmin,pcf(ipoin))     
	      aux=max(-xmin,aux)
	      rhonod(ipoin)=ctero+slopro*(aux+xmin)
       enddo
	else if (ninter.eq.2) then 
	   pi=3.141592654
	   aux=0.
	   slopro=(const1(2,1)-const1(1,1))
	   ctero = const1(1,1)
	   do ipoin=1,npoinl
	      aux=min(xmin,pcf(ipoin))     
	      aux=max(-xmin,aux)
	      rhonod(ipoin)=ctero+slopro*sin(pi*(aux+xmin)/(4.*xmin))
       enddo
	else if (ninter.eq.3) then 
	   aux=0.
	   slopro=(const1(2,1)-const1(1,1))/(2.*xmin)
	   ctero = const1(1,1)
	   do ipoin=1,npoinl
	      aux=min(xmin,pcf(ipoin))     
	      aux=max(-xmin,aux)
	      rhonod(ipoin)=ctero+slopro*(aux+xmin)**2.
       enddo
	else if (ninter.eq.4) then 
	   pi=3.141592654
	   aux=0.
	   slopro=(const1(2,1)-const1(1,1))
	   ctero = const1(1,1)
	   do ipoin=1,npoinl
	      aux=min(xmin,pcf(ipoin))     
	      aux=max(-xmin,aux)
	      rhonod(ipoin)=ctero+slopro/2.*(1.+sin(pi*aux/(2.*xmin)))
       enddo
	endif
	endif

	end subroutine interpol

!------------------------------------------------------------------------------

	subroutine initial_pres

!------------------------------------------------------------------------------

	integer(ink) ipoin

       if (icpres.eq.2) then
           do ipoin=1,npoinl
	        tpres(ipoin)=const2(1)*(30.-coord(2,ntoold(ipoin)))*rhonod(ipoin) 
           enddo
       endif

	end subroutine initial_pres

!------------------------------------------------------------------------------

	subroutine static_pressure

!------------------------------------------------------------------------------

    integer ipoin,icode

    if(icstaticp==0)then
	   return
    elseif(icstaticp==1)then
       do ipoin=1,npoinl
	      statp(ipoin)=1000*9.8*(swl-coord(2,ntoold(ipoin)))
	      if(statp(ipoin)<0.)statp(ipoin)=0.
	   enddo
    elseif(icstaticp==99)then !special for gate
       do ipoin=1,npoinl
	      if(coord(1,ntoold(ipoin))>3.2)cycle
	      statp(ipoin)=1000*9.8*(swl-coord(2,ntoold(ipoin)))
	      if(statp(ipoin)<0.)statp(ipoin)=0.
	   enddo
	elseif(icstaticp==2)then
	   read(glbunitl,*)textl
	   do ipoin=1,npoinl
	      read(glbunitl,*)icode,statp(otonew(icode))
	   enddo
	elseif(icstaticp==3)then
	   read(glbunitl,*)textl
	   do ipoin=1,npoinl
	      read(glbunitl,*)icode,statp(ntoold(icode))
	   enddo

	else
	   
	   write(*,*)'no such icstaticp'

	stop

	endif

	end subroutine static_pressure

!------------------------------------------------------------------------------

    subroutine output

!------------------------------------------------------------------------------

	integer(ink) ipoin,ielem,igroup,ngele,nnode,idimn,igele,index,jelem,ic
	real   (irk) vx,vy,v,vmax,timestep

    if(istep==inc_step.and.icwritemesh==1)then

        write(gidmshl,*)'MESH    dimension 3 ElemType Triangle  Nnode 3'
		write(gidmshl,*)'Coordinates'
        do ipoin=1,npoinl
           write(gidmshl,*) ipoin,(coord(idimn,ntoold(ipoin)),idimn=1,ndimn)
        enddo
		write(gidmshl,*)'end coordinates'
		ielem=0 ; jelem=0
        do igroup=1,ngroup

		   ngele=group(igroup)%nelgroup
	       index=group(igroup)%index

		   if(index==3)write(gidmshl,*)'MESH dimension 2 ElemType Triangle  Nnode 3'
		   if(index==5)write(gidmshl,*)'MESH dimension 2 ElemType Quadrilateral  Nnode 4'
		   if(index==9)write(gidmshl,*)'MESH dimension 3 ElemType Hexahedra  Nnode 8'
		   write(gidmshl,*)'Coordinates'
		   write(gidmshl,*)'end coordinates'
		   write(gidmshl,*)'elements'
           do igele=1,ngele
		      jelem=jelem+1
			  if(appear_level(igroup)==0)cycle
		      ielem=ielem+1
			  !if(associated(element(ielem)%field(1)%lnods)) &
              write(gidmshl,'(20i6)')ielem,element(jelem)%field(1)%lnods,igroup
           enddo
		   write(gidmshl,*)'end elements'
		enddo

    end if

    timestep=timel !istep
    write(gidresl,*)  '  veloc        1 ',timestep, ' 2   1   0'   
	do ipoin= 1,npoinl
	   write(gidresl,'(i5,2x,6(g11.4,1x))') ipoin,(unkno(idimn,ipoin),idimn=1,ndimn)
    enddo
       
    write(gidresl,*)  '   pre         1 ',timestep, '  1  1    0'   
    do ipoin  = 1,npoinl
       write(gidresl,*)  ipoin,tpres(ipoin)
    enddo

	write(gidresl,*)  '   hydrop         1 ',timestep, '  1  1    0'   
    do ipoin  = 1,npoinl
       write(gidresl,*)  ipoin,tpres(ipoin)-statp(ipoin)
    enddo

    write(gidresl,*)  '   rho         1 ',timestep, '  1  1    0'   
    do ipoin  = 1,npoinl
       write(gidresl,*)  ipoin,rhonod(ipoin)
    enddo

    write(gidresl,*)  '   pcf         1 ',timestep, '  2  1    0'  
    do ipoin  = 1,npoinl
       write(gidresl,*)  ipoin,0.,0.,pcf(ipoin)
    enddo

    !write(gidresl,*)  '   granel      1 ',timel, '  2  2    0'	 !Septiembre04

!	do ielem=1,nelem
!       write(gidresl,*) ielem, (granel(idimn,ielem),idimn=1,ndimn)
!    enddo			    

	end subroutine output

!------------------------------------------------------------------------------
	
	subroutine output_grandfi !output Grand.fi , check =1 or not	

!------------------------------------------------------------------------------
!! should get grandfi in each nnode first?  

	integer(ink) ielem,igroup,index,order_int,ngaus,ktotg,i,idimn	
	real(irk),allocatable::grandmod(:)
																
    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
	   ktotg    =element(ielem)%ktotg
	   do idimn=1,ndimn
	   write(chkunitl,'(i6,100f10.4)')idimn,granel(idimn,ktotg+1:ktotg+ngaus)
	   enddo
	   allocate(grandmod(ngaus))
	   do i=1,ngaus
	   grandmod(i)=sqrt(sum(granel(1:ndimn,i+ktotg)**2))
	   enddo
	   !write(chkunitl,'(i6,100f10.4)')ielem,(sqrt(sum(granel(:,i))),i=ktotg+1,ktotg+ngaus)
	   write(chkunitl,'(i6,100f10.4)')ielem,(grandmod(i),i=1,ngaus),sum(grandmod)/ngaus
	   deallocate(grandmod)
    enddo
	end subroutine output_grandfi
!------------------------------------------------------------------------------

      subroutine functs(i,tend,a0,b0,w,t,tff,cnd,fact)

!------------------------------------------------------------------------------

      integer(ink) i
      real   (irk) fact,tend,a0,b0,w,t,tff,cnd01,cnd02,cnd03,a,cnd(:)

      fact=1.
	  return
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
	  cnd01=cnd(1)
	  cnd02=cnd(2)
	  if(ndimn==3)cnd03=cnd(3)
!	--- constant
      fact=0.0
      if(i.eq.0) return
      if(t.gt.tend)return

!	--- constant=1.
      if(i.eq.1)then
       fact = 1.
       return
      end if

!	--- heaviside
      if(i.eq.2)then
	   a=t/tff 
       fact = min(1.0,a)
       return
      end if

!	--- escalon
      if(i.eq.3)then
       if(t.lt.tff)then
	    fact = 1.
	 else
	    fact=0.
       endif

       return
      end if

!	-- dirac delta
      if(i.eq.4)then
       if(t.eq.tff)fact=1.
       return
      end if

!	-- sinus
      if(i.eq.5)then
	 a=t/tff
       fact = (a0 + b0*sin(w*t))!*amin1(1.0,a)
       return
      end if

!	---- tangente hiperbolica
      if(i.eq.6)then
	 a=t/tff
       fact=tanh(3.0*a)
       return
      end if

!	---- functs(1,i)=x(1-x)
      if(i.eq.7)then
	  fact=cnd01*(1.-cnd01)
	  return
      end if

!	---- functs(2,i)=y(1-y)
      if(i.eq.8)then
	  fact=cnd02*(1.-cnd02)
	return
      end if

      if(i.gt.8)then
	  write(*,*) ' error writing i: must be lower than 9'
	  stop
      end if

    end subroutine functs

	!end subroutine globaldate
 !------------------------------------------------------------------------------

    subroutine cosc(idm,a3,elcod0,elcod,rr)
 
!------------------------------------------------------------------------------

    integer(ink) idm,idj,nnode,ind
    real   (irk) a3(:),elcod0(:,:),elcod(:,:),rr(:,:)

    call direct_l(a3,rr,idm)

    nnode=size(elcod,dim=1)
    do idj=1,idm-1
      do ind=1,nnode
         elcod0(idj,ind)=dot_product(rr(idj,:),elcod(ind,:))
      end do
    end do

    end subroutine cosc

!------------------------------------------------------------------------------

	subroutine direct_l(a3,r,idm)

!------------------------------------------------------------------------------

     integer(ink) idm
     real   (irk) xx,a3(:),r(:,:)

     r(idm,:)=a3
     if(idm.eq.2) then
        r(1,1)=r(2,2)
        r(1,2)=-r(2,1)
     return
     endif
     xx=a3(1)**2+a3(3)**2
       !!X,Y,Z ---global axis, x,y,z--local axis
       !!z is the normal direction of the surface
       !!    if z/=Y, x=Y*z, y=z*x
       !!    if z=y,  x=X*z, y=z*x
     if(xx.gt..001) then
      r(1,1)=r(3,3)
      r(1,2)=0.
      r(1,3)=-r(3,1)
      else
      r(1,1)=0.
      r(1,2)=-a3(3)
      r(1,3)=a3(2)
      endif
      a3=r(1,:)**2
      xx=sqrt(sum(a3))
      r(1,:)=r(1,:)/xx
      r(2,1)=r(3,2)*r(1,3)-r(3,3)*r(1,2)
      r(2,2)=r(3,3)*r(1,1)-r(3,1)*r(1,3)
      r(2,3)=r(3,1)*r(1,2)-r(3,2)*r(1,1)
      a3=r(2,:)**2
      xx=sqrt(sum(a3))
      r(2,:)=r(2,:)/xx

    end subroutine direct_l


!!************************************************************************************************
!!################################################################################################
!!************************************************************************************************

!------------------------------------------------------------------------------

	subroutine check_delt

!------------------------------------------------------------------------------

    integer(ink) inode,ipoin,ielem,nnode,index,ikind,ngaus,igaus,igroup,order_int
	real   (irk) g,theta1,theta2,xmu12,xmumed,alpha,vmax,v,dt,aux,xle,pi,pe,visco, &
	             dtnod,dtelm,dens,kf,yield

	integer(ink),pointer::lnods(:)
	real   (irk),pointer::cartd(:,:)
   
	g      = const2(1)
	theta1 = const2(3)  
	theta2 = const2(4)
	xmu12  = const1(1,2)
	xmumed = (const1(2,2)-const1(1,2))/(2.*xmin)

    alpha  =1.0/sqrt(3.0)
    if(niter.eq.1)alpha =1.0
	vmax=0.
	dt  = 1.e10
    DO ielem = 1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   dtelm = 0.0
	   do igaus=1,ngaus
          cartd=>element(ielem)%egaus(order_int)%cartd(:,:,igaus)
          DO inode =1,nnode
             ipoin =lnods(inode)
             v     =sqrt(sum(unkno(:,ipoin)**2))
	         vmax  =max(vmax,v)
		     !xle   =1./(sqrt(sum(cartd(:,inode)**2)))
			 !xle=(element(ielem)%area)**(1./ndimn)
			 !xle=element(ielem)%minedge
		     !write(99,*)ielem,xle
		     !or xle    =(sum(cartd(:,inode)**2))**(-1.0/ndimn) ?????
			 xle=element(ielem)%elength
	         aux=min(pcf(ipoin),xmin)
	         aux=max(aux,-xmin)

	         if(nmatsl.eq.2)then
	         if (ninter.eq.1)then 
	            visco=xmu12 +xmumed *(xmin+aux)
	         else if (ninter.eq.2) then 
                pi=3.141592654
	            visco=xmu12 +xmumed*(xmin*2.)*sin(pi*(aux+xmin)/(4.*xmin))
	         else if (ninter.eq.3) then 
	            visco=xmu12 +xmumed *(aux+xmin)**2.
	         else if (ninter.eq.4) then !
	            pi=3.141592654
	            visco=xmu12 +xmumed/2.*(xmin*2.)*(1.+sin(pi*aux/(2.*xmin)))
	         endif
	         endif

	         if (v.lt.1.e-6) then
			    dtnod=delt
             else
	         if(visco.lt.1.e-6) then
		       dtnod = csafe*xle/v*alpha
             else 
                Pe=(v*rhonod(ipoin)/visco)*(xle/2.)
	            dtnod=csafe*(xle/v)*(sqrt(1./Pe**2.+alpha**2.)-1./Pe)
             endif
	         endif
             if (dtnod.lt.dt) dt= dtnod
             dtelm = dtelm + dtnod
          ENDDO !inode
		  nullify(cartd)
	   enddo !igaus
	   deltel(ielem)=dtelm/real(nnode*ngaus)
	   nullify(lnods)
    ENDDO !ielem

    write(*,'(a,f8.4,a,e12.5,a,e12.5)')       '   timel=',timel,'   dt=',delt,'   dtcrit=',dt
    write(chkunitl,'(a,f8.4,a,e12.5,a,e12.5)')'   timel=',timel,'   dt=',delt,'   dtcrit=',dt

    if (icdelt.eq.1) then
        if (dt.lt.delt) then
            delt = dt
        else
            delt =delt !min(1.1*delt,dt)
        endif
    endif

    end subroutine check_delt

!------------------------------------------------------------------------------
	
	subroutine first_step

!------------------------------------------------------------------------------

	integer(ink) ipoin,inodb,ktotg,index,nnode,ikind,ngaus,igaus,in,ip,ia,ielem,ja,iedge,  &
	             inode,igroup,order_int
	real   (irk) cgra,theta,roz,dens,visco,kf,c2,twopi,coss,sinn,vt,alpha,c13,delt2,rho,sum0
	real   (irk),allocatable::gpoin(:,:),frict(:),gelem0(:),divef0(:),unkne0(:),vpoin(:,:)
    integer(ink),pointer::lnods(:)
    real   (irk),pointer::shapef(:),cartd(:,:)

    allocate(gpoin(ndimn,npoinl),frict(ndimn),gelem0(ndimn),divef0(ndimn), &
	        unkne0(ndimn),vpoin(ndimn,1))
    cgra  = const2(1)  
	theta = const2(2) 
    roz   = const2(6)  
	twopi = 4.* acos(0.0 )

    do ipoin = 1,npoinl
	   vpoin(:,1) =unkno(:,ipoin)
	   flux(:,:,ipoin) =matmul(vpoin,transpose(vpoin))
    enddo
	do ipoin=1,npoinl
	   gpoin(:,ipoin)=cgra*cos(thetag)-fachv !-result_second(97)
	enddo
!****************************************************************************************
!! Notes: This part is not finshed for 3d, but in fact we can do not include
!!        frictx,fricty . It is a friction force in the boundary , something
!!        like that f=c*v**2 , c is a kind of coef.
!****************************************************************************************

!   ------  Perform first step  timel level n+alpha*n

    alpha  = 0.5
	ktotg  =0
    DO ielem =1,nelem  

       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

       if (icdt2.eq.0) then
          delt2  = alpha*delt
       elseif (icdt2.eq.1) then
          delt2 = min(alpha*deltel(ielem),delt)
       endif

	   ktotg    =element(ielem)%ktotg
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods	

       do igaus=1,ngaus
          ktotg=ktotg+1
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus)       
	      unkne0 = 0.0
	      gelem0 = 0.0
          divef0 = 0.0
		  do in=1,nnode
		     ip=lnods(in)
             do ia=1,ndimn
                unkne0(ia) = unkne0(ia) + unkno(ia,ip)*shapef(in)
	            gelem0(ia) = gelem0(ia) + gpoin(ia,ip)*shapef(in)
				sum0=0.
				do ja=1,ndimn
				   sum0=sum0+cartd(ja,in)*flux(ia,ja,ip)
				enddo
				divef0(ia)=divef0(ia)+sum0
             enddo
		  enddo !in
		  nullify(shapef,cartd)

          unkne(:,ktotg) = unkne0(:)+delt2*(gelem0(:)-divef0(:)) 

       enddo !igaus

       nullify(lnods)
    ENDDO  
    deallocate(gpoin,frict,gelem0,divef0,unkne0,vpoin)

	end subroutine first_step

!------------------------------------------------------------------------------
	
	subroutine second_step

!------------------------------------------------------------------------------

	integer(ink) ipoin,ielem,in,inode,iposn,ia,ie,jn,index,nnode,ngaus,ikind,ktotg,igaus,     &
	             idimn,jdimn,iedge,edimn,aelem,ngausa,igroup,order_int,icbound,iiter,jnode,jpoin
	real   (irk) cgra,theta,roz,dens,visco,kf,yield,fi,xmumed,xmu12,tauy12,tauymed,fricmed,   &
	             fric12,rou,rov,aux,pi,div1,div2,dvdy,pres,cosfi,sinfi,tauy,sum1,             &
			     visco2,twopi,dvolu,denom,cm
    real   (irk),allocatable::fluxe(:,:,:),fluxe0(:,:),vgaus(:,:),granu(:,:),gcomp(:),sum0(:),&
	                          d2(:,:),rhsb(:,:,:),rhelp(:,:,:)
    integer(ink),pointer::lnods(:)
    real   (irk),pointer::shapef(:),cartd(:,:),normal(:),rotation(:,:)

	allocate(fluxe(ndimn,ndimn,ntotg),fluxe0(ndimn,ndimn),vgaus(ndimn,1),granu(ndimn,ndimn), &
	         gcomp(ndimn),sum0(ndimn),d2(ndimn,ndimn),rhsb(ndimn,ndimn,npoinl),              &
			 rhelp(ndimn,ndimn,npoinl))
			 fluxe=0. ; fluxe0=0. ; vgaus=0. ; granu=0. ;gcomp=0. ; sum0=0. ; d2=0.

    rhs  = 0.0 ; flux = 0.0 ; denom = 0.0 ; tauy  = 0.0 ; xmumed =0.0 ; xmu12  =0.0
	tauymed=0.0 ; tauy12 =0.0 ; fricmed=0.0 ; fric12 =0.0 ; rhsb=0. ; rhelp=0.

  
    cgra  = const2(1)  
	theta = const2(2)  
    roz   = const2(6) 
	kf    = const1(1,3) 

	xmumed =(const1(2,2)-const1(1,2))/(xmin*2.)
	xmu12  =const1(1,2)
	tauymed=(const1(2,4)-const1(1,4))/(xmin*2.)
	tauy12 =const1(1,4)
	fricmed=(const1(2,5)-const1(1,5))/(xmin*2.)*(2.*acos(0.)/180.)
	fric12 =const1(1,5)*2.*acos(0.)/180.

    do ielem = 1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   ktotg    =element(ielem)%ktotg
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods		

	   do igaus=1,ngaus
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus) 
		  ktotg =ktotg+1      
		  vgaus(:,1)=unkne(:,ktotg)
          aux =0.0
		  pres=0.
		  dens=0.0
          do inode=1,nnode
             ipoin=lnods(inode)
             aux  = aux+pcf(ipoin)*shapef(inode)
			 pres = pres + tpres(ipoin)*shapef(inode)
		     dens = dens + rhonod(ipoin)*shapef(inode) 
          enddo

	      pi=3.141592654          
	      aux=min(xmin,aux)     
	      aux=max(-xmin,aux)
	      if(nmats.eq.2)then
	      if (ninter.eq.1)then 
	         visco=xmu12 +xmumed *(xmin+aux)
	         yield=tauy12+tauymed*(xmin+aux)
	         fi   =fric12+fricmed*(xmin+aux)
	      else if (ninter.eq.2) then 
	         pi=3.141592654
	         visco=xmu12 +xmumed*(xmin*2.) *sin(pi*(aux+xmin)/(4.*xmin))
	         yield=tauy12+tauymed*(xmin*2.)*sin(pi*(aux+xmin)/(4.*xmin))
	         fi   =fric12+fricmed*(xmin*2.)*sin(pi*(aux+xmin)/(4.*xmin))       
	      else if (ninter.eq.3) then        
	         visco=xmu12 +xmumed *(aux+xmin)**2.
	         yield=tauy12+tauymed*(aux+xmin)**2.
	         fi   =fric12+fricmed*(aux+xmin)**2.
	      else if (ninter.eq.4) then 
	         visco=xmu12 +xmumed/2.*(xmin*2.)*(1.+sin(pi*aux/(2.*xmin)))
	         yield=tauy12+tauymed/2.*(xmin*2.)*(1.+sin(pi*aux/(2.*xmin)))
	         fi   =fric12+fricmed/2.*(xmin*2.)*(1.+sin(pi*aux/(2.*xmin)))         
	      endif
	      endif

          granu=0.
          do idimn=1,ndimn
		     do jdimn=1,ndimn
			    sum1=0.
			    do inode=1,nnode
				   in   = lnods(inode)
				   sum1=sum1+cartd(idimn,inode)*unkno(jdimn,in)
				enddo
				granu(idimn,jdimn)=sum1
			 enddo
		  enddo
		  !granu=visco*(granu+transpose(granu))
          granu=0.5*(granu+transpose(granu)) 
		  d2   =matmul(granu,granu)
		  denom=0
		  do idimn=1,ndimn
		     denom=denom+d2(idimn,idimn)
		  enddo
		  denom=sqrt(0.5*denom)
		  tauy= yield*cos(fi)+pres*sin(fi)
		  visco2=0.
          if (denom.ge.1.e-6)visco2=tauy/denom
		  if(nfric.eq.1)visco2=0.
		  granu=(visco2+2.*visco)*granu
          fluxe(:,:,ktotg)=matmul(vgaus,transpose(vgaus))-granu/dens
		  gcomp=cgra*cos(thetag)-fachv !-result_second(97)
          do inode=1,nnode
             iposn=lnods(inode)
             rhs(:,iposn)=rhs(:,iposn)+delt*gcomp*dvolu*shapef(inode)
		  enddo
		  do inode=1,nnode
             iposn=lnods(inode)
			 sum0=0.
			 do ia=1,ndimn
				sum0=sum0+cartd(ia,inode)*fluxe(:,ia,ktotg)
		     enddo
			 rhs(:,iposn)=rhs(:,iposn)+delt*dvolu*sum0
          end do
          nullify(shapef,cartd)
       enddo !igaus
	   nullify(lnods)
    enddo !ielem

!boundary integral 

!! first transfer fluxe (in gauss point) to fluxp (in point)
!! Algorithm: fe=Nfn; fe-Nfn=0; I.Nt(fe-Nfn)dw=0; Mfn=I.Ntfe dw
!! Build RHS Int(Nt.fe) Store it in rhs

    flux=0. ; rhsb=0. 
	do ielem =1,nelem
	   icbound=element(ielem)%icbound
	   if(icbound==0)cycle
	   ktotg    =element(ielem)%ktotg
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods		
	   do igaus=1,ngaus
          shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)
		  ktotg =ktotg+1  
		  do inode=1,nnode
		     rhsb(:,:,lnods(inode))=rhsb(:,:,lnods(inode))+dvolu*shapef(inode)*fluxe(:,:,ktotg)
		  enddo
		  nullify(shapef)
	   enddo
	   nullify(lnods)
	enddo

    DO iiter=1,niter
       IF (iiter.eq.1) THEN
           do ipoin=1,npoinl
		      !if(ipibp(ipoin)/=1)cycle
              cm = mmatl(ipoin)
		      flux(:,:,ipoin)=rhsb(:,:,ipoin)/cm  
           enddo
       ELSE
           rhelp=0.0
           do ielem=1,nelem
	          icbound=element(ielem)%icbound
	          if(icbound==0)cycle		      
              lnods=>element(ielem)%field(1)%lnods		
              do inode=1,size(lnods)
                 ipoin= lnods(inode)
                 do jnode=1,size(lnods)
                    jpoin=lnods(jnode)
                    cm = element(ielem)%mmat(inode,jnode)
                    rhelp(:,:,ipoin)=rhelp(:,:,ipoin)+cm*flux(:,:,jpoin)
                 enddo
              enddo
			  nullify(lnods)
           enddo
           do ipoin=1,npoinl
              cm = mmatl(ipoin)
              flux(:,:,ipoin)=flux(:,:,ipoin)+(rhsb(:,:,ipoin)-rhelp(:,:,ipoin))/cm
           enddo
       ENDIF
    ENDDO  ! ------------------------------  ends loop in iterations
	deallocate(rhelp,rhsb)

	do iedge=1,nedgel
       nnode    =edgesl(iedge)%nnode
       edimn    =edgesl(iedge)%ndimn
	   ngaus    =edgesl(iedge)%ngaus
	   lnods    =>edgesl(iedge)%lnods
	   do igaus =1,ngaus
	      shapef=>edgesl(iedge)%edgegaus(igaus)%shape
		  dvolu = edgesl(iedge)%edgegaus(igaus)%djacb
          normal=>edgesl(iedge)%edgegaus(igaus)%normal
	      do inode=1,nnode
	         ipoin=lnods(inode)
			 do idimn=1,ndimn
		        rhs(idimn,ipoin)=rhs(idimn,ipoin)- &
			    delt*dvolu*shapef(inode)*dot_product(flux(:,idimn,ipoin),normal)
			 enddo
	      enddo
		  nullify(shapef,normal) 
	   enddo
	   nullify(lnods)
	enddo
	deallocate(fluxe,vgaus,fluxe0,sum0,gcomp,granu,d2)

	end subroutine second_step

!------------------------------------------------------------------------------

	subroutine jacobi_solver(unkno,rhs,namat)

!------------------------------------------------------------------------------
    integer(ink) iiter,ipoin,iamat,ielem,inode,jnode,jpoin,namat,igroup
	real(irk)    cm,unkno(:,:),rhs(:,:) 
	real(irk),allocatable::rhelp(:,:)
    integer(ink),pointer::lnods(:)
	allocate(rhelp(ndimn,npoinl))
!      ------  u(n+1)=u(n)+inv(ML)*(Rhs-M*u(n))
!              where unkno -> u & u(0)=0
!              and   M*u(n) -> rhelp
	unkno=0.
    DO iiter=1,niter
       IF (iiter.eq.1) THEN
           do ipoin=1,npoinl
              cm = mmatl(ipoin)
              do iamat=1,namat
		         unkno(iamat,ipoin)=rhs(iamat,ipoin)/cm  
              enddo
           enddo
       ELSE
           rhelp=0.0
           do ielem=1,nelem
		      igroup=element(ielem)%group
              if(appear_level(igroup)==0)cycle
              lnods=>element(ielem)%field(1)%lnods		
              do inode=1,size(lnods)
                 ipoin= lnods(inode)
                 do jnode=1,size(lnods)
                    jpoin=lnods(jnode)
                    cm = element(ielem)%mmat(inode,jnode)
                    do iamat=1,namat
                       rhelp(iamat,ipoin)=rhelp(iamat,ipoin)+cm*unkno(iamat,jpoin)
                    enddo
                 enddo
              enddo
			  nullify(lnods)
           enddo
           do ipoin=1,npoinl
              cm = mmatl(ipoin)
              do iamat=1,namat
                 unkno(iamat,ipoin)=unkno(iamat,ipoin)+(rhs(iamat,ipoin)-rhelp(iamat,ipoin))/cm
              enddo
           enddo
       ENDIF
    ENDDO  ! ------------------------------  ends loop in iterations
	deallocate(rhelp)    

    end subroutine jacobi_solver
!------------------------------------------------------------------------------

	subroutine addvelocity

!------------------------------------------------------------------------------
    integer(ink) inode,iiter,ipoin,ielem,iamat,jpoin,jnode,nnode,idimn,igroup
	real   (irk) facti,facti2,ttime2,cm,cnd1,cnd2,cos,sin,vn,vt,d2vn,d2vt
	real   (irk),allocatable::cnd(:),rotation(:,:),velttn(:),dvelttn(:)

	allocate(cnd(ndimn),rotation(ndimn,ndimn),velttn(ndimn),dvelttn(ndimn))
    cnd=0. ; rotation=0. ; velttn=0. ; dvelttn=0.
	facti=0. ; facti2=0. 

    if(norder.eq.2.and.nbucle.eq.1) delt=delt*2.  !nbucle?
	ttime2=timel-delt

	do ipoin=1,npoinl 
	   if(any(ifpre(:,ipoin)==1))cycle
	   do iamat=1,ndimn
           if(ifpre(iamat,ipoin).eq.2) delun(iamat,ipoin)=0. 
	       unkno(iamat,ipoin)=unkno(iamat,ipoin)+delun(iamat,ipoin)
       enddo
    enddo

    do ipoin=1,npoinl		 
       if(any(ifpre(:,ipoin)==1))then
	   	  cnd=coord(:,ntoold(ipoin))      
	      call FUNCTS(ifunc,timend,AZERO,BZERO,OMEGA,timel,tf,cnd,facti)
          call FUNCTS(ifunc,timend,AZERO,BZERO,OMEGA,ttime2,tf,cnd,facti2)
		  rotation=rotatp(:,:,ipoin)
		  velttn =matmul(rotation,unkno(:,ipoin)) 
		  dvelttn=matmul(rotation,delun(:,ipoin)) 
		  do idimn=1,ndimn
		     if(ifpre(idimn,ipoin)==1)then
			 velttn (idimn)=-veloc0(idimn,ipoin)*facti
			 dvelttn(idimn)=-veloc0(idimn,ipoin)*(facti-facti2)
			 endif
		  enddo          
          unkno(:,ipoin) =matmul(transpose(rotation),velttn)
          delun(:,ipoin)=matmul(transpose(rotation),dvelttn)	  	      	   
	      unkno(:,ipoin)=unkno(:,ipoin)+delun(:,ipoin)
	   endif
    end do
    deallocate(cnd,velttn,dvelttn,rotation)

	end subroutine addvelocity

!------------------------------------------------------------------------------

    subroutine stiff

!------------------------------------------------------------------------------
    integer(ink) ielem,index,nnode,ikind,ngaus,igaus,inode,in,jn,ipoin,idimn,igroup,order_int,ktotg
	real   (irk) theta1,theta2,rho,dvolu,cm,sum
    real   (irk),allocatable::gstif(:,:)
    integer(ink),pointer::lnods(:)
    real   (irk),pointer::shapef(:),cartd(:,:)

	theta1= const2(3) 
	theta2= const2(4) 

    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods	
	   ktotg    =element(ielem)%ktotg

	   allocate(gstif(nnode,nnode))
	   gstif=0.
       do igaus=1,ngaus
          ktotg=ktotg+1
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu = element(ielem)%egaus(order_int)%djacb(igaus)
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus) 
          rho=0.
 	      do inode=1,nnode
		     ipoin=lnods(inode)	         
		     rho  =rho+rhonod(ipoin)*shapef(inode)		     
	      enddo
 	      do in=1,nnode
		     do jn=1,nnode
				sum=0.
			    do idimn=1,ndimn
				   sum=sum+cartd(idimn,in)*cartd(idimn,jn)
				enddo
				gstif(in,jn)=gstif(in,jn)+sum*(dvolu/rho)*theta1*theta2		                    
		     enddo	        		     
	      enddo	
          nullify(shapef,cartd)
       enddo !igaus
	   nullify(lnods) 
       element(ielem)%gstif=gstif
	   deallocate(gstif)
    end do    
	    
    end subroutine stiff

!------------------------------------------------------------------------------

   subroutine deltap
    
!------------------------------------------------------------------------------

    integer(ink) intcp,ielem,index,nnode,ikind,ngaus,ktotg,igaus,inode,ipoin,ieleb,ie,ip, &
	             ip1,inodb,in,jnodb,idimn,iedge,aelem,ngausa,edimn,igroup,order_int,itotv,&
				 icbound,iiter,jnode,jpoin
	real   (irk) theta1,divu,rho,dvolu,facti,facti2,ttime2,cosx,cosy,aleng,coe,cnd1,cnd2, &
	             cm,sum0,accn 
	real(4)     ,allocatable::gradp(:,:),gradp0(:)
	real   (irk),allocatable::cnd(:),vhelp(:),rhsb(:,:),rhelp(:,:)
    integer(ink),pointer::lnods(:)
    real   (irk),pointer::shapef(:),cartd(:,:),normal(:)

	allocate(gradp(ndimn,ntotg),gradp0(ndimn),cnd(ndimn),vhelp(ndimn),rhsb(ndimn,npoinl), &
	        rhelp(ndimn,npoinl)) 
	gradp=0. ; gradp0=0. ; cnd=0. ; vhelp=0. ;eload=0.0

	theta1 = const2(3)        
	intcp  = int(const2(5))  

    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   ktotg    =element(ielem)%ktotg
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods	

	   do igaus=1,ngaus
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu = element(ielem)%egaus(order_int)%djacb(igaus)
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus) 
		  ktotg = ktotg+1 
		  rho=0. 	      
          do inode=1,nnode
             ipoin=lnods(inode)
	         rho  =rho+rhonod(ipoin)*shapef(inode)
          enddo
		  divu=0.
		  do inode=1,nnode
		     ipoin=lnods(inode)
			 sum0=0.
			 do idimn=1,ndimn
			    sum0=sum0+cartd(idimn,inode)*(unkno(idimn,ipoin)+(theta1-1.)*delun(idimn,ipoin))
			 enddo
			 divu=divu+sum0
             gradp(:,ktotg)=gradp(:,ktotg)+cartd(:,inode)*tpres(ipoin)
          end do
          do inode=1,nnode
	         ipoin       =lnods(inode)
             eload(ipoin)=eload(ipoin)-dvolu*(shapef(inode)*divu/delt+1./rho*             &
			              theta1*(dot_product(cartd(:,inode),gradp(:,ktotg))))
          end do
		  nullify(shapef,cartd)
	   enddo !igaus
	   nullify(lnods)
    end do

	if(intcp.eq.0) go to 69 

!boundary integral 

!! first transfer fluxe (in gauss point) to fluxp (in point)
!! Algorithm: fe=Nfn; fe-Nfn=0; I.Nt(fe-Nfn)dw=0; Mfn=I.Ntfe dw
!! Build RHS Int(Nt.fe) Store it in rhs

    flux=0. ; rhsb=0. ; rhelp=0.
	do ielem =1,nelem
	   icbound=element(ielem)%icbound
	   if(icbound==0)cycle
	   ktotg    =element(ielem)%ktotg
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods		
	   do igaus=1,ngaus
          shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)
		  ktotg =ktotg+1  
		  do inode=1,nnode
		     rhsb(:,lnods(inode))=rhsb(:,lnods(inode))+dvolu*shapef(inode)*gradp(:,ktotg)
		  enddo
	   enddo
	enddo

    DO iiter=1,niter
       IF (iiter.eq.1) THEN
           do ipoin=1,npoinl
		      !if(ipibp(ipoin)/=1)cycle
              cm = mmatl(ipoin)
		      flux(1,:,ipoin)=rhsb(:,ipoin)/cm  
           enddo
       ELSE
           rhelp=0.0
           do ielem=1,nelem
	          icbound=element(ielem)%icbound
	          if(icbound==0)cycle		      
              lnods=>element(ielem)%field(1)%lnods		
              do inode=1,size(lnods)
                 ipoin= lnods(inode)
                 do jnode=1,size(lnods)
                    jpoin=lnods(jnode)
                    cm = element(ielem)%mmat(inode,jnode)
                    rhelp(:,ipoin)=rhelp(:,ipoin)+cm*flux(1,:,jpoin)
                 enddo
              enddo
			  nullify(lnods)
           enddo
           do ipoin=1,npoinl
              cm = mmatl(ipoin)
              flux(1,:,ipoin)=flux(1,:,ipoin)+(rhsb(:,ipoin)-rhelp(:,ipoin))/cm
           enddo
       ENDIF
    ENDDO  ! ------------------------------  ends loop in iterations

	facti=0.
	facti2=0.
	ttime2=timel-delt 
    rho=0.

	do iedge=1,nedgel
       nnode    =edgesl(iedge)%nnode
       edimn    =edgesl(iedge)%ndimn
	   ngaus    =edgesl(iedge)%ngaus
	   lnods    =>edgesl(iedge)%lnods    

	   do igaus =1,ngaus
	      shapef=>edgesl(iedge)%edgegaus(igaus)%shape
		  dvolu = edgesl(iedge)%edgegaus(igaus)%djacb
          normal=>edgesl(iedge)%edgegaus(igaus)%normal
		  gradp0=0.
		  rho=0. 	      
          do inode=1,nnode
             ipoin=lnods(inode)
	         rho  =rho+rhonod(ipoin)*shapef(inode)
			 gradp0=gradp0+flux(1,:,ipoin)*shapef(inode)
          enddo
	      do inode=1,nnode
	         ipoin=lnods(inode) 
	         if(iffixp(ipoin).ne.0)  cycle             
	         cnd=coord(:,ntoold(ipoin))
	         call functs(ifunc,timend,AZERO,BZERO,OMEGA,timel,tf,cnd,facti)
             call functs(ifunc,timend,AZERO,BZERO,OMEGA,ttime2,tf,cnd,facti2)
          
	         if (intcp.eq.1) then !Aprox: gradp(n+1)=gradp(n)	  			                                   
             eload(ipoin)= eload(ipoin)+dvolu*shapef(inode)*(dot_product(gradp0,normal))*theta1/rho

	         elseif (intcp.eq.2.and.any(ifpre(:,ipoin).ne.2)) then !Aprox: gradp(n+1)=gradp(n)
		     
             eload(ipoin)=eload(ipoin)+dvolu*shapef(inode)*(dot_product(gradp0,normal))*theta1/rho
			                       
	         elseif (intcp.eq.2.and.all(ifpre(:,ipoin).eq.2)) then 
             vhelp=veloc0(:,ipoin)*(facti-facti2)-delun(:,ipoin)
			 eload(ipoin)=eload(ipoin)-(1./delt)*dvolu*shapef(inode)*(dot_product(vhelp,normal))*theta1
             
!			 elseif(intcp==3)then !for level_set_problem=2, FSI problem.
!			 if (level_set_problem/=2)then
!			    write(*,*)' level_set_problem/=2 !!'
!			    stop
!			 endif
!             accn=0. !normal acceleration
!			 do idimn=1,ndimn
!			    itotv=nodfn(idimn,ntoold(ipoin))
!				accn=accn+(result_second(itotv)+fachv(idimn))*normal(idimn)
!				!fachv--from GHM, ground acceleration, maybe -?
!				!result_second+fachv--is absolut acceleration
!             enddo
!			 eload(ipoin)=eload(ipoin)-dvolu*shapef(inode)*accn*theta1
!			 else
!			 write(*,*)'eload integral method is not implement yet'
!			 stop
             else
			 write(*,*)'there is no such kind of intcp!'
			 stop
             endif
          enddo !inode
		  nullify(shapef,normal)
       enddo !igaus
	   nullify(lnods)
    ENDDO 			  
69  deallocate(gradp,gradp0,cnd,vhelp,rhelp,rhsb)

    end subroutine deltap 

!------------------------------------------------------------------------------

    subroutine solvegc 

!------------------------------------------------------------------------------

	integer(ink) miter,iiter
	real   (irk) rnorm0,rnorm1,rnorre
	real   (irk),allocatable::q1cg(:),rcg(:),r1cg(:),scg(:),pcg(:),apcg(:)
	 
    allocate(q1cg(npoinl),rcg(npoinl),r1cg(npoinl),scg(npoinl),pcg(npoinl),apcg(npoinl))
	q1cg=0. ; rcg=0. ; r1cg=0. ; scg=0. ; pcg=0. ;apcg=0.

    !miter=10*npoinl
    miter=10e2
!   ------   inicializa dpres    y q1cg
    rcg=eload
	dpres=0.0
	q1cg =0.0

    call getqmat (q1cg)

    call initcg (q1cg,rcg,r1cg,scg,pcg,apcg,rnorm0)

    do  iiter=1,miter
        call jcg (apcg,pcg,rcg,scg,r1cg,q1cg,rnorm0,rnorm1)
        rnorre = abs(rnorm1/rnorm0)
		!write(chkunitl,*)'iiter=',iiter,abs(rnorm1/rnorm0)
        if(abs(rnorm1/rnorm0).le.tolep) exit
    enddo
    deallocate(apcg,pcg,rcg,scg,r1cg,q1cg)

    end subroutine solvegc 

!------------------------------------------------------------------------------

    subroutine getqmat(q1cg) 

!------------------------------------------------------------------------------
    integer(ink) ielem,nnode,inode,ipoin,igroup,index
	real   (irk) q1cg(:)
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::gstif(:,:) 

!	------- Obtiene  q1 = diag(k)-1 matriz

    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index= element(ielem)%index
       nnode= elkn(index)%ggaus(1)%nnode
       lnods=>element(ielem)%field(1)%lnods
	   gstif=>element(ielem)%gstif  
       do inode=1,nnode
	      ipoin=lnods(inode)
          q1cg(ipoin)=q1cg(ipoin)+gstif(inode,inode)
       enddo
	   nullify(lnods,gstif)
    enddo
    do ipoin=1,npoinl
       if (abs(q1cg(ipoin)).le.0.000001) then
          if (iffixp(ipoin).eq.0) iffixp(ipoin)=-999
       else
          q1cg(ipoin) = 1./q1cg(ipoin)
       endif
    enddo

    end subroutine getqmat 

!------------------------------------------------------------------------------

    subroutine initcg (q1cg,rcg,r1cg,scg,pcg,apcg,rnorm0)

!------------------------------------------------------------------------------
    integer(ink) ipoin
	real   (irk) rnorm0
	real   (irk) q1cg(:),rcg(:),r1cg(:),scg(:),pcg(:),apcg(:) 

	r1cg =0.0
	scg  =0.0
	pcg  =0.0
	apcg =0.0

    do ipoin = 1,npoinl
       dpres(ipoin)=fixedp(ipoin)
       pcg(ipoin)  =dpres(ipoin)
    enddo

    call kbyp (0,apcg,pcg)

    rnorm0=0.0
    do ipoin=1,npoinl
       rcg(ipoin)=rcg(ipoin)-apcg(ipoin)
       scg(ipoin)  =q1cg(ipoin)*rcg(ipoin)
       pcg(ipoin)  =scg(ipoin)
       rnorm0 = rnorm0+rcg(ipoin)*rcg(ipoin)
    enddo

    do ipoin=1,npoinl
       if (iffixp(ipoin).ne.0) THEN
          pcg(ipoin)=0.0
          rcg(ipoin)=0.0
          scg(ipoin)=0.0
       endif
    enddo
    end subroutine initcg

!------------------------------------------------------------------------------

    subroutine jcg(apcg,pcg,rcg,scg,r1cg,q1cg,rnorm0,rnorm1)

!------------------------------------------------------------------------------
    integer(ink) ipoin
	real   (irk) rnorm0,rnorm1,prod1,prod2,alfa,prod3,beta
	real   (irk) q1cg(:),rcg(:),r1cg(:),scg(:),pcg(:),apcg(:) 

!  ------  Calcula k * p

    call kbyp(1,apcg,pcg)

!     ------ obtiene alfa = (r * s/p *ap)

    prod1 = 0.0
    prod2 = 0.0
    do ipoin=1,npoinl
       if (iffixp(ipoin).ne.0) cycle
          prod1=prod1+rcg(ipoin)*scg(ipoin)
          prod2=prod2+pcg(ipoin)*apcg(ipoin)
    enddo
    alfa = prod1/prod2

!   -----   Calcula  dpres    = dpres    + alfa*p
    prod3  = 0.0
    rnorm1 = 0.0
    do ipoin=1,npoinl
       dpres(ipoin)=dpres(ipoin)+alfa*pcg(ipoin)
       r1cg (ipoin)=rcg(ipoin)-alfa*apcg(ipoin)
       rnorm1      =rnorm1+r1cg(ipoin)*r1cg(ipoin)
       scg(ipoin)  =q1cg(ipoin)*r1cg(ipoin)
       prod3       =prod3+r1cg(ipoin)*scg(ipoin)
    enddo

!   -----  Comprueba convergencia

    if(abs(rnorm1/rnorm0).le.tolep) return

!   -----   beta = (r1*s1/r0*s0)
    beta = prod3/prod1
    do ipoin=1,npoinl
       pcg(ipoin)=scg(ipoin)+beta*pcg(ipoin)
       rcg(ipoin)=r1cg(ipoin)
    enddo

    end subroutine jcg

!------------------------------------------------------------------------------

    subroutine kbyp(iflag1,apcg,pcg)

!------------------------------------------------------------------------------

    integer(ink) iflag1,ielem,nnode,inode,ipoin,jnode,jpoin,igroup,index
	real   (irk) sum
	real   (irk) apcg(:),pcg(:)
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::gstif(:,:) 	   
!   ap = k * p

    apcg = 0.0
    do ielem = 1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index= element(ielem)%index
       nnode= elkn(index)%ggaus(1)%nnode
       lnods=>element(ielem)%field(1)%lnods
	   gstif=>element(ielem)%gstif
       do inode=1,nnode
          ipoin=lnods(inode)
          do jnode=1,nnode
             jpoin=lnods(jnode)
             sum  = gstif(inode,jnode)*pcg(jpoin)
             if (iflag1.eq.1) then
                 if(iffixp(ipoin)+iffixp(jpoin).ne.0) sum=0.
             endif
             apcg(ipoin) = apcg(ipoin) + sum
          enddo
       enddo
	   nullify(lnods,gstif)
    enddo

    end subroutine kbyp

!------------------------------------------------------------------------------

    subroutine finalp 

!------------------------------------------------------------------------------
    integer(ink) ipoin

	tpres1=tpres

    do ipoin=1,npoinl
	   if (iffixp(ipoin).eq.1)   dpres(ipoin) = 0.0
       tpres(ipoin)=tpres(ipoin)+dpres(ipoin)
    end do
		 	
    end subroutine finalp

!------------------------------------------------------------------------------

    subroutine pressure 

!------------------------------------------------------------------------------
    integer(ink) iedge,ic,index,nnode,edimn,ngaus,selem,indey,ndofn,ig,i0,inode,idofn,ipoin
	real   (irk) djacb
	integer(ink),pointer::lnods(:)
	real   (irk),allocatable::press(:,:),shape(:),rr(:,:),xload(:),edload(:)
	do iedge=1,nedgel !iedge
	   ic=edgesl(iedge)%ic
	   if(ic/=1)cycle !ic=1--FSI boundary, ic/=1--others 
       index =edgesl(iedge)%index
       nnode =edgesl(iedge)%nnode
       edimn =elkn(index)%ndimn
       ngaus =edgesl(iedge)%ngaus
       selem =edgesl(iedge)%selem
       indey =element(selem)%index
       ndofn =ndimn
	   lnods =>edgesl(iedge)%lnods
       allocate(press(edimn+1,nnode),shape(nnode),rr(edimn+1,edimn+1),xload(edimn+1),  &
	            edload(ndofn*nnode))!,edgesl(iedge)%edload(ndofn*nnode))
       edload=0.0 ; press=0.
	   do inode=1,nnode
	      ipoin=lnods(inode) ! local point!!
		  !the normal direc. is different from sideload,so there is no '-'
		  !only dynamic water pressure
	      press(ndimn,inode)=tpres(ipoin)-statp(ipoin)
	   enddo
	   nullify(lnods)
       do ig=1,ngaus
          djacb=edgesl(iedge)%edgegaus(ig)%djacb
          shape=edgesl(iedge)%edgegaus(ig)%shape
          rr   =edgesl(iedge)%edgegaus(ig)%rotation
          do i0=1,edimn+1
             xload(i0)=sum(shape(1:nnode)*press(i0,1:nnode))
          end do
          xload=matmul(rr,xload)
          do inode=1,nnode
             idofn=(inode-1)*ndofn
             edload(idofn+1:idofn+edimn+1)=edload(idofn+1:idofn+edimn+1)+        &
                                           xload*djacb*shape(inode)
          end do                                   
       end do
       edgesl(iedge)%edload=edload
       deallocate(press,shape,rr,xload,edload)
   enddo 

    end subroutine pressure
!------------------------------------------------------------------------------

    subroutine rhsvel

!------------------------------------------------------------------------------

    integer(ink) ielem,index,nnode,ikind,ngaus,igaus,ipoin,inode,igroup,order_int
	real   (irk) theta2,dvolu,rho
    double precision,allocatable:: gradp(:),gradp1(:)
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::shapef(:),cartd(:,:)

	allocate(gradp(ndimn),gradp1(ndimn))
    gradp=0. ; gradp1=0.

	theta2 = const2(4) 
	if (theta2.eq.0.) theta2=1.

    rhs=0.0
    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods	
	   do igaus=1,ngaus
	      shapef=> elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus)
	      gradp =0.0
	      gradp1=0.0
          do inode =1,nnode
             ipoin =lnods(inode)
             gradp =gradp +cartd(:,inode)*tpres(ipoin) *theta2
             gradp1=gradp1+cartd(:,inode)*tpres1(ipoin)*(1.-theta2)
          end do
		   rho=0. 	      
          do inode=1,nnode
             ipoin=lnods(inode)
	         rho  =rho+rhonod(ipoin)*shapef(inode)
          enddo
          do inode=1,nnode
             ipoin=lnods(inode)
             rhs(:,ipoin)=rhs(:,ipoin)-shapef(inode)*delt*dvolu*(gradp(:)+gradp1(:))/rho
          end do
		  nullify(shapef,cartd)
       enddo !igaus
	   nullify(lnods)
    end do
	deallocate(gradp,gradp1)   
	              
	end subroutine rhsvel

!------------------------------------------------------------------------------
       
	subroutine first_stepf 

!------------------------------------------------------------------------------
 
    integer(ink) ipoin,ielem,nnode,inode,in,ip,ngaus,igaus,index,ktotg,idimn,igroup,order_int
	real   (irk) alpha,pcfe0,divef0,delt2
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::shapef(:),cartd(:,:)

    do ipoin=1,npoinl
       flux(1,:,ipoin) = unkno(:,ipoin)*pcf(ipoin)
    enddo

!      ------  Perform first step  timel level n+alpha*n

     pcfe=0.
     alpha  = 0.5

    do ielem =1,nelem               
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   ktotg    =element(ielem)%ktotg
	   	
       if (icdt2.eq.0) then
          delt2  = alpha*delt
       elseif (icdt2.eq.1) then
          delt2 = min(alpha*deltel(ielem),delt)
       endif	
	   do igaus=1,ngaus
	      ktotg=ktotg+1
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus)
		  pcfe0=0.
		  divef0=0.	
          do in=1,nnode
             ip=lnods(in)
             pcfe0=pcfe0+pcf(ip)*shapef(in)
			 divef0=divef0+dot_product(cartd(:,in),flux(1,:,ip))
          enddo
		  nullify(shapef,cartd)
		  pcfe(ktotg) = pcfe0-delt2*divef0
       enddo
	   nullify(lnods)
     enddo !ielem 

     end subroutine first_stepf

!------------------------------------------------------------------------------

    subroutine second_stepf

!------------------------------------------------------------------------------

	integer(ink) ielem,index,nnode,ngaus,ktotg,igaus,inode,ipoin,iedge,edimn,aelem,ngausa, &
	             igroup,order_int,iiter,icbound,jnode,jpoin
	real   (irk) dvolu,cosx,cosy,aleng,coe,cm
	real   (irk),allocatable::fluxe(:,:),rhsb(:,:),rhelp(:,:)
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::shapef(:),cartd(:,:),normal(:)

	allocate(fluxe(ndimn,ntotg),rhsb(ndimn,npoinl),rhelp(ndimn,npoinl)) 
	fluxe=0.  ; unkne =0.0 ; rhs   =0.0 ; rhsb=0. ; rhelp=0.
    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   ktotg    =element(ielem)%ktotg
	   do igaus=1,ngaus
	      ktotg=ktotg+1
	      shapef=> elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus)
	      do inode=1,nnode
		     ipoin=lnods(inode)
		     unkne(:,ktotg)=unkne(:,ktotg)+unkno(:,ipoin)*shapef(inode)
		  enddo
          fluxe(:,ktotg)=unkne(:,ktotg)*pcfe(ktotg) 
		  do inode=1,nnode
		     ipoin=lnods(inode)
			 rhs(1,ipoin)=rhs(1,ipoin)+delt*dvolu*dot_product(cartd(:,inode),fluxe(:,ktotg))
		  enddo
		  nullify(cartd,shapef)
	   enddo !igaus
	   nullify(lnods)
	enddo !igelem
!boundary integral 

!! first transfer fluxe (in gauss point) to fluxp (in point)
!! Algorithm: fe=Nfn; fe-Nfn=0; I.Nt(fe-Nfn)dw=0; Mfn=I.Ntfe dw
!! Build RHS Int(Nt.fe) Store it in rhs

   ! flux=0. ; rhsb=0. ; rhelp=0.
	do ielem =1,0 !nelem
	   icbound=element(ielem)%icbound
	   if(icbound==0)cycle
	   ktotg    =element(ielem)%ktotg
	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods		
	   do igaus=1,ngaus
          shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)
		  ktotg =ktotg+1  
		  do inode=1,nnode
		     rhsb(:,lnods(inode))=rhsb(:,lnods(inode))+dvolu*shapef(inode)*fluxe(:,ktotg)
		  enddo
		  nullify(shapef)
	   enddo
	   nullify(lnods)
	enddo

    DO iiter=1,0 !niter
       IF (iiter.eq.1) THEN
           do ipoin=1,npoinl
		      !if(ipibp(ipoin)/=1)cycle
              cm = mmatl(ipoin)
		      flux(1,:,ipoin)=rhsb(:,ipoin)/cm  
           enddo
       ELSE
           rhelp=0.0
           do ielem=1,nelem
	          icbound=element(ielem)%icbound
	          if(icbound==0)cycle		      
              lnods=>element(ielem)%field(1)%lnods		
              do inode=1,size(lnods)
                 ipoin= lnods(inode)
                 do jnode=1,size(lnods)
                    jpoin=lnods(jnode)
                    cm = element(ielem)%mmat(inode,jnode)
                    rhelp(:,ipoin)=rhelp(:,ipoin)+cm*flux(1,:,jpoin)
                 enddo
              enddo
			  nullify(lnods)
           enddo
           do ipoin=1,npoinl
              cm = mmatl(ipoin)
              flux(1,:,ipoin)=flux(1,:,ipoin)+(rhsb(:,ipoin)-rhelp(:,ipoin))/cm
           enddo
       ENDIF
    ENDDO  ! ------------------------------  ends loop in iterations
	deallocate(rhelp,rhsb)

	do iedge=1,nedgel
       nnode    =edgesl(iedge)%nnode
       edimn    =edgesl(iedge)%ndimn
	   ngaus    =edgesl(iedge)%ngaus
	   lnods    =>edgesl(iedge)%lnods    

	   do igaus  =1,ngaus
	      shapef =>edgesl(iedge)%edgegaus(igaus)%shape
		  dvolu   =edgesl(iedge)%edgegaus(igaus)%djacb
          normal =>edgesl(iedge)%edgegaus(igaus)%normal	      
          do inode=1,nnode
             ipoin=lnods(inode)
			 rhs(1,ipoin)=rhs(1,ipoin)-delt*dvolu*shapef(inode)*dot_product(flux(1,:,ipoin),normal)
		  enddo
		  nullify(shapef,normal)
	   enddo !igaus
	   nullify(lnods)
	enddo
    deallocate(fluxe)

    end subroutine second_stepf

!------------------------------------------------------------------------------

    subroutine addthemf

!------------------------------------------------------------------------------

    integer(ink) i
	real   (irk) cconv,aux2

	cconv=const2(8)
	aux2=xmin*cconv

    do i=1,npoinl
	   if(ifpcf(i).ne.0) cycle
	   if (abs(pcf(i)+delun(1,i)).ge.aux2) cycle    !Septiembre04   
       pcf(i)=pcf(i)+delun(1,i)
    enddo
    
    end subroutine addthemf

!------------------------------------------------------------------------------

    subroutine signo(numb,pcf00,sigfin00) 

!------------------------------------------------------------------------------
    integer(ink) iumb,numb
	real   (irk) pcf00(:),sigfin00(:)

	do iumb=1,numb 	   

	   if (pcf00(iumb).gt.0.) sigfin00(iumb)= 1.
	   if (pcf00(iumb).lt.0.) sigfin00(iumb)=-1.	        
	   
	enddo

	end	subroutine signo 

!------------------------------------------------------------------------------

	 subroutine gradfi(pcf00,granel00)

!------------------------------------------------------------------------------
    integer(ink) ielem,index,nnode,ngaus,inode,igaus,ipoin,ktotg,igroup,order_int
    integer(ink),pointer::lnods(:)
	real   (irk),pointer::shapef(:),cartd(:,:)
	real   (irk) pcf00(:),granel00(:,:)

	granel00 =0.0

!------------Get grad at elements-----------------

    do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   ktotg    =element(ielem)%ktotg
	   do igaus=1,ngaus
	      ktotg=ktotg+1
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus)   
	      do inode=1,nnode
	         ipoin=lnods(inode)
	         granel00(:,ktotg)=granel00(:,ktotg)+pcf00(ipoin)*cartd(:,inode)
          enddo
		  nullify(cartd)
       enddo
	   nullify(lnods)
	enddo   

	end subroutine gradfi

!------------------------------------------------------------------------------

    subroutine check_deltPCF

!------------------------------------------------------------------------------
    integer(ink) ielem,index,inode,nnode,ikind,ngaus,igaus,ipoin,igroup,order_int
    real   (irk) anx,any,dt,xle,dtnod,dtelm
    integer(ink),pointer::lnods(:)
	real   (irk),pointer::cartd(:,:)

!      ------  This routine obtains dt min in nodes.
!              Uses characteristic length 1/L^2= (N,x^2+N,y^2)

	dtpcf    = 1.e10
	deltpcf  = 1.e10
    do ielem = 1,nelem	    
       dtelm = 0.0
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   do igaus=1,ngaus
          cartd =>element(ielem)%egaus(order_int)%cartd(:,:,igaus)   
          do inode = 1,nnode           
		     ipoin = lnods(inode)
			 !xle=1.0/sqrt(sum(cartd(:,inode)**2)) 
			 !xle=(element(ielem)%area)**(1./ndimn)  
			 !xle=element(ielem)%minedge 
			 xle=element(ielem)%elength        
             dtnod = csafepcf*xle/sqrt(3.0) 
             if (dtnod.lt.dtpcf)dtpcf= dtnod
             dtelm = dtelm + dtnod
          enddo 
		  nullify(cartd)
	   enddo !igaus
	   nullify(lnods)
       deltelpcf(ielem) = dtelm/real(nnode*ngaus)
    enddo

    deltpcf = dtpcf					
    write(*,*)'deltpcf=',deltpcf

    end subroutine check_deltPCF

!------------------------------------------------------------------------------

    subroutine first_stepPCF

!------------------------------------------------------------------------------

    integer(ink) ielem,index,nnode,ikind,ngaus,ktotg,igaus,in,ip,igroup,order_int
	real   (irk) alpha,gradmode,sigfie0,pcfe0,delt2
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::shapef(:)
 
    alpha  = 0.5
    
!      ------  Perform first step  timel level n+alpha*n

    do ielem =1,nelem 
	                
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   ktotg    =element(ielem)%ktotg

       delt2 = min(alpha*deltelpcf(ielem),alpha*deltpcf) 

	   do igaus=1,ngaus
	      ktotg=ktotg+1
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
		  pcfe0=0.
		  gradmode=0.
		  sigfie0=0.
          do in=1,nnode
             ip=lnods(in)                
             pcfe0    = pcfe0 + pcf(ip)*shapef(in)
			 gradmode =sqrt(sum(granel(:,ktotg)**2))
	         sigfie0  =sigfie0+sigfin(ip)*shapef(in)
			 !if(sigfin(ip).eq.0.) write(*,*) 'sigfin(',ip,')','=0.'             
          enddo
 	      if(sigfie0.gt.0.) sigfie0=1.    
 	      if(sigfie0.lt.0.) sigfie0=-1.   
		  if(sigfie0.eq.0.) then
		  !write(*,*) 'sigfie(',ielem,')','=0.'             
	      endif       
          pcfe(ktotg) = pcfe0+delt2*(sigfie0*(1.-gradmode))
		  nullify(shapef) 
       enddo !igaus	
	   nullify(lnods)	       
    enddo  

    end subroutine first_stepPCF

!------------------------------------------------------------------------------

    subroutine finod_12 

!------------------------------------------------------------------------------

    integer(ink) ielem,index,nnode,ngaus,ktotg,igaus,inode,ipoin,iiter,jnode,jpoin,igroup,order_int
	real   (irk) cm,cmm,cmmm,dvolu 
	real   (irk),allocatable:: del2(:),rhs4(:),rhelp4(:)
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::shapef(:)

	allocate(del2(npoinl),rhs4(npoinl),rhelp4(npoinl)) 
	  
	del2=0.0 ; rhs4=0.0 ; rhelp4=0. ; finod12=0.0 

!---------------Build RHS
 
	do ielem=1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   ktotg    =element(ielem)%ktotg
	   do igaus=1,ngaus
	      ktotg=ktotg+1
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)		  	
	      do inode=1,nnode
	         ipoin=lnods(inode)
	         rhs4(ipoin)=rhs4(ipoin)+pcfe(ktotg)*shapef(inode)*dvolu
          enddo
		  nullify(shapef)
		enddo !igaus
		nullify(lnods)
	enddo
!----------------Get fi at nodes in n+1/2: fi(1) = fi(0) + dt inv(Ml)*(rhs-M.fi(0)) fi(0)=0

	do ipoin= 1,npoinl
	   cm=mmatl(ipoin)
	   del2(ipoin)=del2(ipoin)+rhs4(ipoin)/cm
	enddo
	
	do iiter=2,niter
	    rhelp4=0.0
	    do ielem=1,nelem
           igroup=element(ielem)%group
           if(appear_level(igroup)==0)cycle
           lnods=>element(ielem)%field(1)%lnods
	       do inode=1,size(lnods)
	          ipoin=lnods(inode)
	          do jnode=1,size(lnods)
	             jpoin=lnods(jnode)
                 cmm  = element(ielem)%mmat(inode,jnode)				 
	             rhelp4(ipoin)=rhelp4(ipoin)+cmm*del2(jpoin)				 
	          enddo
	       enddo
		   nullify(lnods)
        enddo

!--------- fi(n+1) = fi(n) + inv(Ml)*(rhs-M.fi(n))

	    do ipoin=1,npoinl
	       cmmm=mmatl(ipoin)	       
	       del2(ipoin)=del2(ipoin)+(rhs4(ipoin)-rhelp4(ipoin))/cmmm	       
		enddo
	    
	enddo

    finod12=del2

    deallocate(del2,rhs4,rhelp4)

	end subroutine finod_12

!------------------------------------------------------------------------------
 
    subroutine second_stepPCF

!------------------------------------------------------------------------------
 
    integer(ink) ielem,index,nnode,ikind,ngaus,ktotg,igaus,inode,ipoin,igroup,order_int
	real   (irk) gradmode12,dvolu
	integer(ink),pointer::lnods(:)
	real   (irk),pointer::shapef(:)

    rhs  = 0.0 ; gradmode12=0.0

!---------------Get mod (grad fi) and sign (fi) at elements in n+1/2
	
    do ielem = 1,nelem
       igroup=element(ielem)%group
       if(appear_level(igroup)==0)cycle

	   index    =element(ielem)%index
       order_int=elkn(index)%el_field(1)%order_intrules(1)
       ngaus    =elkn(index)%ggaus(order_int)%ngaus
       nnode    =elkn(index)%ggaus(1)%nnode
       lnods    =>element(ielem)%field(1)%lnods
	   ktotg    =element(ielem)%ktotg
	   do igaus=1,ngaus
	      ktotg=ktotg+1
	      shapef=>elkn(index)%ggaus(order_int)%shape(:,igaus)
          dvolu =element(ielem)%egaus(order_int)%djacb(igaus)	

!		  if ((abs(granel12(1,ielem)).lt.1.e-10).and.(abs(granel12(2,ielem)).lt.1.e-10))then
!             gradmode12=0.
!	      else
!		     gradmode12=sqrt(sum(granel12(:,ktotg)**2))
!	      endif	

		  if (all(abs(granel12(:,ktotg)).lt.1.e-10))then
             gradmode12=0.
	      else
		     gradmode12=sqrt(sum(granel12(:,ktotg)**2))
	      endif	
		  	  	
	      do inode=1,nnode
	         ipoin=lnods(inode)             
             rhs(1,ipoin) = rhs(1,ipoin)+deltpcf*shapef(inode)*dvolu*(sigfie12(ktotg)*(1.-gradmode12))  
		  enddo
		  nullify(shapef)           
       enddo
	   nullify(lnods)
    enddo

    end subroutine second_stepPCF

!------------------------------------------------------------------------------

    subroutine addthemPCF

!------------------------------------------------------------------------------

    integer(ink) ipoin
	real   (irk) cnorm,aux2,aux   

	cnorm=const2(9)
    aux2=xmin*cnorm

!      --------adding the increments

	do ipoin=1,npoinl
	   aux=delun(1,ipoin) 
	   finod12(ipoin)=finod12(ipoin)+aux
    enddo

    end subroutine addthemPCF

!------------------------------------------------------------------------------

	subroutine vpreagain

!------------------------------------------------------------------------------

    integer(ink) iedge,inode,idimn,itotv,nnode,ic,ipoin
	real   (irk) facti
	integer(ink),pointer::lnods(:),lnods_f(:)
    real   (irk),allocatable::cnd(:),rotation(:,:),velttn(:)

	!get the ground velocity

    !groundv=groundv+(fachv+fachvold)*ditime/2.0

	do iedge  =1,nedgel
	   ic     = edgesl(iedge)%ic
	   if(ic/=1)cycle !ic=1--FSI boundary, ic/=1--others
	   nnode  = edgesl(iedge)%nnode 
	   lnods  =>edgesl(iedge)%lnods
	   lnods_f=>edgesl(iedge)%lnods_f
	   do inode=1,nnode
	      do idimn=1,ndimn
	         itotv=nodfn(idimn,lnods_f(inode))
             veloc0(idimn,lnods(inode))=result_first(itotv) !+groundv(ndimn)
             !veloc0(idimn,lnods(inode))=-result_first(itotv) 
             !due to the normal direction is the outer normal of fluid
		  enddo 
	   enddo
	   nullify(lnods,lnods_f)
	enddo
    allocate(cnd(ndimn),rotation(ndimn,ndimn),velttn(ndimn))
	cnd=0. ; rotation=0. ; velttn=0.
	do ipoin=1,npoinl                     	  
       if(any(ifpre(:,ipoin)==1))then
		  cnd=coord(:,ntoold(ipoin))
		  call FUNCTS(ifunc,timend,AZERO,BZERO,OMEGA,timel,tf,cnd,facti)
		  rotation=rotatp(:,:,ipoin)
		  velttn=matmul(rotation,unkno(:,ipoin)) 
		  veloc0(:,ipoin)=matmul(rotation,-veloc0(:,ipoin)) !transpose x-y-z to t-t-n
		  do idimn=1,ndimn
             if(ifpre(idimn,ipoin)==1)velttn(idimn)=veloc0(idimn,ipoin)*facti
		  enddo
		  unkno(:,ipoin)=matmul(transpose(rotation),velttn)
	   endif

       ! for the same point , can't be prescibed both in ttn and xyz
	   if(any(ifpre(:,ipoin)==2))then
	      do idimn=1,ndimn
	         if(ifpre(idimn,ipoin).eq.2) then
	            cnd=coord(:,ntoold(ipoin))
				call functs(ifunc,timend,AZERO,BZERO,OMEGA,timel,tf,cnd,facti)
	            unkno(idimn,ipoin)=veloc0(idimn,ipoin)*facti
             endif
	      enddo
	   endif
	enddo

    deallocate(cnd,rotation,velttn)

	end subroutine vpreagain

!------------------------------------------------------------------------------

	subroutine viniagain

!------------------------------------------------------------------------------
   integer(ink) ipoin
   real(irk),allocatable::dgroundv(:)
   allocate(dgroundv(ndimn))

    dgroundv=groundv-groundv1  !groundv1:--velocity of the end of time n
	                           !groundv :--velocity of the begain of time n+1  
    do ipoin=1,npoinl
	   unkno(:,ipoin)=unkno(:,ipoin)-dgroundv
	enddo
    groundv1=groundv
	deallocate(dgroundv)

	end subroutine viniagain

End module levelset