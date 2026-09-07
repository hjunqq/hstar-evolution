    module applied_load

    use yl_diag
    use yl_diag_registry
    use variable_types
    use global_var
    use materials
    use arrayutil
    use meshfine

    implicit none

    !! time_curve ----define the facts of the load in each time step( or incremental step
    !!                the increment is ditime)
    integer(ink) nplgroup,nedge,edge_load_group,delgroup,ntcurve,nbeamload,nplateload
    real   (irk) gravy
    integer(ink),allocatable::tcurvegravity(:),appear_group_pload(:)            
    real   (irk), allocatable::factg(:),factf(:)

    type time_curve
       integer(ink) ntime,nstoch_curve
       character(20)type_curve
       real(irk) dfact
       real(irk),pointer:: dtrec,dtend,dtbegin,ample !hxl
       real(irk),pointer:: ttime_curve(:)             !! not for sesmic wave  & arclength
       real(irk),pointer:: dfact_curve(:)
       real(irk),pointer:: time_begin,detal,fact_inc  !! only for arclength
       real(irk),pointer:: a0sin,asin,wsin,w0sin      !! only for HARMONIC
       real(irk),pointer:: dx,Ca                      !! only for extrapolation
        real(irk),pointer:: AI(:),omega(:)  !! only for FouierSeries
       integer(ink),pointer:: nalgo,ncdis,piter,giter,Nextr,NFS,order_stoch_parameter(:)
    end type time_curve

    !! pxyz is the unit load, the real load increment is pxyz*dfact
    !! nudofn is the total number of displacement freedom (e.g, =6 for 3-D beam)
    !! point load is  put  into the eload of the first element: unode(lnode)%list(1)

    type group_of_point_load
       integer(ink) order_time_curve
       integer(ink) nudofn,npload
       real   (irk),pointer:: pxyz(:)
       integer(ink),pointer:: list(:)
       integer(ink),pointer:: listep(:,:)
    end type group_of_point_load

    type group_of_beam_load
       integer(ink) itcurve
       integer(ink) aelem
       real   (irk),pointer:: edload(:)
    end type group_of_beam_load
    
    type group_of_water_pressure     !2013/3/18
       integer(ink) water           !2013/3/18
       real   (irk) cor0,cor1,p0,p1,fact  !2013/3/18
    end type group_of_water_pressure  !2013/3/18
    
    
    type group_of_plate_load
       integer(ink) itcurve
       integer(ink) aelem
       real   (irk),pointer:: edload(:)
    end type group_of_plate_load
!! the following is to define the edges for which the loads will be considered
!! Notation:
!! (1) the edge load will be put into eload of the aelem-th element
!!      which is associated
!! (2) nnode is the node no. of the edge and the index is the order in element kind
!! (3) lnode is the connectivity of the edge, ldofe is the freedom order in the
!!     aelem-th element
!! (4) rotation(ndimn,ndimn)    defines the normal direction of the edge in
!!     each gauss point.
!! (5) the integeration rule will use that for mass matrix
    
    type gauss_edge
       real(irk),pointer::djacb,shape(:),cartd(:,:),rotation(:,:)
    end type gauss_edge
    
    type edge_define
       integer(ink) nnode,ngaus,index,aelem,vdimn
       integer(ink),pointer::lnode(:), ldofe(:)
       type(gauss_edge),pointer::edgegaus(:)
    end     type edge_define
    
    type group_of_edge_load
       integer(ink) iedge,itcurve,idelgroup  !2013/3/18
       real   (irk),pointer::edload(:)
    end type group_of_edge_load
    
    type point_load_inter  !20210502
    integer(ink) nintf,order_time_curve,nudofn
	integer(ink),pointer::listf(:)
	real(irk),   pointer::rintf(:),pxyz(:,:)
    end type point_load_inter



    type(time_curve),          allocatable::tcurves(:)     !ntcurve
    type(group_of_point_load), allocatable::pload(:)       !nplgroup
    type(edge_define),         allocatable::edges(:)       !nedge
    type(group_of_edge_load),  allocatable::edgeload(:)    !edge_load_group
    type(group_of_beam_load),  allocatable::beamload(:)    !beam_load_group
    type(group_of_plate_load), allocatable::plateload(:)   !plate_load_group (water_pressure)
    type(group_of_water_pressure), allocatable::gpwater(:)   !group of water_pressure, step by step !2013/3/18
    type(point_load_inter),allocatable::ploadr(:) !20210502

    
    contains

    subroutine external_load_1

    character(20) text,type_curve
    integer(ink) itcurve,npload,iplgroup,tedge,iedge,             &
                 i0,aelem,index,nnode_f,ndofn_f,inode,            &
                 sedge,nnode,ipoin,edimn,order_int,jnode,         &
                 ngaus,jpoin,ig,idofn,i1,i2,nudofn,igroup,nfdof,  &
                 ipegroup,ndofn,ntime,indey,nline,ncdis,nevab,    &
                 begin_edge,end_edge,water,ibeamload,kpload,      &
                 iplateload,i3,i4,jedge,nextr,ip,tplateload,nstoch_curve, &
                 Tnplgroup,order_time_curve,j0,vdimn
    integer(ink),allocatable::lnode(:)
    integer(ink),pointer::lnods(:)
    real    (irk) aa,weigp,djacb,cor0,cor1,p0,p1,fact,dcor,dl,cc, &
                  f1,f2,f3,f4,f5,f6,corx
    real    (irk),allocatable::a3(:),shape(:),elcod(:,:),gcom(:), &
                               deriv(:,:),elcod0(:,:),cartd(:,:),pxyz(:), &
                               s(:,:),rr(:,:),press(:,:),xload(:), corlist(:), &
                               edload(:),trot(:,:),rload(:),xjaci(:,:),      &
                               rload1(:),gloc(:),ppp(:),pppx(:),trotx(:,:) !steel 2006
    real    (irk),pointer::rotation(:,:)

    !! set of time-dfact curves in the iblks-th BLOCK
    
    if (restart==1)then
       print *,'lineload=',lineload
       do i1=1,lineload
          read(loadunit,*)text
       end do
    end if

    if (meshc==1.or.rmesh/=0)rewind(loadunit)
     if(Bparameter/=0)rewind(loadunit)  !20190810

    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_title_1,0)
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)ntcurve
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_curve_count,0)
    if (allocated(tcurves)) deallocate(tcurves)
    if (ntcurve.ne.0)allocate(tcurves(ntcurve))
    lineload=lineload+2

    do itcurve=1,ntcurve
        !print *,'itcurve=',itcurve

       read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)ntime,type_curve,nstoch_curve,nline
       call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_curve_header,0)
       tcurves(itcurve)%nstoch_curve=nstoch_curve
       print *,'ntime=',ntime,type_curve,nstoch_curve,nline
       lineload=lineload+1
       tcurves(itcurve)%ntime=ntime
       tcurves(itcurve)%type_curve=type_curve
       tcurves(itcurve)%dfact=0.
       allocate(tcurves(itcurve)%dfact_curve(ntime))
       
       if(nstoch_curve/=0)then
        allocate(tcurves(itcurve)%order_stoch_parameter(nstoch_curve))
        read(loadunit,*)tcurves(itcurve)%order_stoch_parameter
       endif

       select case(type_curve)
       case('HARMONIC') 
       allocate(tcurves(itcurve)%a0sin,tcurves(itcurve)%asin,tcurves(itcurve)%wsin,tcurves(itcurve)%w0sin,tcurves(itcurve)%dtbegin,tcurves(itcurve)%dtend)
       !read(loadunit,*)text
       read(loadunit,*)tcurves(itcurve)%a0sin,tcurves(itcurve)%asin,tcurves(itcurve)%wsin,tcurves(itcurve)%w0sin,tcurves(itcurve)%dtbegin,tcurves(itcurve)%dtend
       case('FOURIERSERIES') 
           
        allocate(tcurves(itcurve)%NFS,tcurves(itcurve)%dtbegin,tcurves(itcurve)%dtend)
      
        read(loadunit,*)tcurves(itcurve)%NFS,tcurves(itcurve)%dtbegin,tcurves(itcurve)%dtend   
        
       allocate(tcurves(itcurve)%AI(tcurves(itcurve)%NFS),tcurves(itcurve)%omega(tcurves(itcurve)%NFS))   
        
        read(loadunit,*)tcurves(itcurve)%AI(:)
        read(loadunit,*)tcurves(itcurve)%omega(:)
       case('WATERLEVEL')
       allocate(tcurves(itcurve)%ttime_curve(ntime))
       do i0=1,ntime
       read(loadunit,*)tcurves(itcurve)%ttime_curve(i0),tcurves(itcurve)%dfact_curve(i0)
       end do
       case('SEISMIC')
       allocate(tcurves(itcurve)%dtrec,tcurves(itcurve)%dtbegin,tcurves(itcurve)%dtend,tcurves(itcurve)%ample)
       read(loadunit,*)tcurves(itcurve)%dtrec,tcurves(itcurve)%dtbegin,tcurves(itcurve)%dtend,&
       tcurves(itcurve)%ample
       case('EXTRAPOLATION')
       allocate(tcurves(itcurve)%Nextr,tcurves(itcurve)%ca,tcurves(itcurve)%dx)
       read(loadunit,*)tcurves(itcurve)%nextr,tcurves(itcurve)%ca,tcurves(itcurve)%dx
       print *,'extra',tcurves(itcurve)%nextr,tcurves(itcurve)%ca,tcurves(itcurve)%dx
       case('ARCLENGTH')
       arc_curve=itcurve
       allocate(tcurves(itcurve)%time_begin,tcurves(itcurve)%detal,tcurves(itcurve)%fact_inc, &
       tcurves(itcurve)%nalgo     ,tcurves(itcurve)%piter,tcurves(itcurve)%giter)
       read(loadunit,*)tcurves(itcurve)%time_begin,tcurves(itcurve)%fact_inc,  &
       tcurves(itcurve)%nalgo,                                 &
       tcurves(itcurve)%giter
       if (tcurves(itcurve)%nalgo==2)then
          allocate(tcurves(itcurve)%ncdis)
          read(loadunit,*)inode,idofn
          ncdis=nodfn(idofn,inode)
          tcurves(itcurve)%ncdis=ncdis
          if (ncdis==0) then
             stop 'error in input of arclength control'
          endif
       endif
       case default
       allocate(tcurves(itcurve)%ttime_curve(ntime))
       read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)tcurves(itcurve)%ttime_curve(1:ntime)
       call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_curve_points,0)
       end select
       if (type_curve=='SEISMIC') then
        read(loadunit,*)tcurves(itcurve)%dfact_curve
   
       !    do i1=1,ntime
       !read(loadunit,*)tcurves(itcurve)%dfact_curve(i1) 
       !    end do
       elseif (type_curve/='ARCLENGTH'.and.type_curve/='EXTRAPOLATION'   &
           .and.type_curve/='HARMONIC'.and.type_curve/='WATERLEVEL') then
        read(loadunit,*)tcurves(itcurve)%dfact_curve(1:ntime) !!one record 
        endif
       lineload=lineload+nline
    end do
print *,'ok waterlevel'
    !! set of point_load structure in the iblks-th BLOCK

    if (allocated(pload)) deallocate(pload)
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_title_2,0)
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)nplgroup,kpload
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_point_load_count,0)
    lineload=lineload+2
    print *,'nplgroup=',nplgroup
    if (nplgroup==0) goto 11
if(kpload==1)then !20210502
    allocate(pload(nplgroup))
    do iplgroup=1,nplgroup
       read(loadunit,*)pload(iplgroup)%order_time_curve,             &
                       pload(iplgroup)%nudofn,                       &
                       pload(iplgroup)%npload,nline
       lineload=lineload+1

       nudofn=pload(iplgroup)%nudofn
       npload=pload(iplgroup)%npload

       allocate(pload(iplgroup)%pxyz(nudofn))
       allocate(pload(iplgroup)%list(npload))
       read(loadunit,*)pload(iplgroup)%pxyz(1:nudofn)

       type_curve=tcurves(pload(iplgroup)%order_time_curve)%type_curve
       if (type_curve/='EXTRAPOLATION')then
          read(loadunit,*)pload(iplgroup)%list(1:npload)
          !steel 2006
          do ip=1,npload
             ipoin=pload(iplgroup)%list(ip)
             if (icpnorm(ipoin)==0)cycle
    !         if (ip>1)then                        !special , one point, one group!
    !            write(*,*)'stop for ip>1!!'
				!stop
    !         endif
             allocate(ppp(ndimn),pppx(ndimn))
             ppp=0. ; pppx=0.
             nudofn=pload(iplgroup)%nudofn
             ppp(1:nudofn)=pload(iplgroup)%pxyz
             pppx=prot(:,:,ipoin).x.ppp
             deallocate(pload(iplgroup)%pxyz)
             allocate(pload(iplgroup)%pxyz(ndimn))
             pload(iplgroup)%pxyz=pppx
             pload(iplgroup)%nudofn=ndimn
             deallocate(ppp,pppx)
          enddo
          !steel 2006
       elseif(type_curve=='EXTRAPOLATION')then
          nextr=tcurves(pload(iplgroup)%order_time_curve)%nextr
          allocate(pload(iplgroup)%listep(npload,2*nextr+1))
          read(loadunit,*)text
          do i0=1,npload
             !read(loadunit,*)i1,pload(iplgroup)%list(i0),pload(iplgroup)%listep(i0,1:2*nextr+1)
             read(loadunit,*)i1,pload(iplgroup)%listep(i0,1:2*nextr+1)
             pload(iplgroup)%list(i0)=pload(iplgroup)%listep(i0,1)
          end do
       endif

       lineload=lineload+nline
    end do
elseif(kpload==2)then !20210502
    
 allocate(appear_group_pload(ngroup),ploadr(nplgroup))
 allocate(corlist(ndimn))

Do iplgroup=1,nplgroup
    
 read(loadunit,*)order_time_curve,nudofn  !,npload
 read(loadunit,*)appear_group_pload
 lineload=lineload+2

allocate(pxyz(nudofn))
read(loadunit,*)pxyz(1:nudofn)
read(loadunit,*)corlist(:)
 lineload=lineload+2

call find_pload_points(iplgroup,corlist) !20210502
ploadr(iplgroup)%order_time_curve=order_time_curve
ploadr(iplgroup)%nudofn=nudofn
nintf=ploadr(iplgroup)%nintf
allocate(ploadr(iplgroup)%pxyz(nudofn,nintf))
do i0=1,ploadr(iplgroup)%nintf
ploadr(iplgroup)%pxyz(:,i0)=pxyz*ploadr(iplgroup)%rintf(i0)
end do
deallocate(pxyz)
end do

Tnplgroup=sum(ploadr(:)%nintf)
allocate(pload(Tnplgroup))

Tnplgroup=0
do i0=1,nplgroup
    order_time_curve=ploadr(i0)%order_time_curve
    nudofn=ploadr(i0)%nudofn
   
    do j0=1,ploadr(i0)%nintf
    Tnplgroup=Tnplgroup+1
     npload=1
    pload(Tnplgroup)%order_time_curve=order_time_curve
    pload(Tnplgroup)%nudofn=nudofn
    pload(Tnplgroup)%npload=npload
       allocate(pload(Tnplgroup)%pxyz(nudofn))
       allocate(pload(Tnplgroup)%list(npload))
    pload(Tnplgroup)%pxyz=ploadr(i0)%pxyz(:,j0)
    pload(Tnplgroup)%list(1)=ploadr(i0)%listf(j0)
    end do
    end do
nplgroup=Tnplgroup
!write(7,*)'nplgroup=',nplgroup
!
!    do iplgroup=1,nplgroup
!write(7,*)pload(iplgroup)%order_time_curve,pload(iplgroup)%nudofn,pload(iplgroup)%npload
!write(7,*)pload(iplgroup)%pxyz(1:nudofn)
!write(7,*)pload(iplgroup)%list(:)
!   end do

deallocate(appear_group_pload,ploadr,corlist)

endif  !kpload=1  20210502


    11  continue

    !! set of edge_define structure

    if (allocated(edges)) deallocate(edges)
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_title_3,0)
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)nedge
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_1_edge_count,0)
    print *,'nedge=',nedge
    lineload=lineload+2
    if (nedge==0) goto 22
    allocate(edges(nedge))
    tedge=0
    do while(tedge<nedge)
       read(loadunit,*)text                               !4
       read(loadunit,*)sedge,nnode,index,vdimn  !20211028
       lineload=lineload+2
       do iedge=1,sedge
          tedge=tedge+1
          edges(tedge)%nnode=nnode
          edges(tedge)%index=index
          edges(tedge)%vdimn=vdimn !20211028
          allocate(edges(tedge)%lnode(nnode))
          read(loadunit,*)i0,edges(tedge)%lnode(1:nnode),edges(tedge)%aelem
        !if(vdimn==3)write(7,*)'tedge=',tedge,'iedge=',iedge
          !print *, i0,edges(tedge)%lnode(1:nnode),edges(tedge)%aelem
          lineload=lineload+1
          aelem=edges(tedge)%aelem
          indey=element(aelem)%index
          nnode_f=elkn(indey)%el_field(1)%nnode_f
          ndofn_f=ndimn
          igroup=element(aelem)%group
          nfdof=group(igroup)%dof( 1)%nfdof
          allocate(edges(tedge)%ldofe(nnode*ndofn_f))
          do inode=1,nnode                  !2
             ipoin=edges(tedge)%lnode(inode)
             do jnode=1,nnode_f        ! 11
                jpoin=element(aelem)%field(1)%lnods_f(jnode)
                if (ipoin.eq.jpoin)exit
             end do                    ! 11
             do idofn=1,ndofn_f        ! 12
                i1=(inode-1)*ndofn_f+idofn
                i2=(jnode-1)*nfdof+idofn
                edges(tedge)%ldofe(i1)=i2
             end do                    ! 12
          end do                             !2
          
          !write(7,*)'tedge=',tedge,'aelem=',aelem,'ldofe=',edges(tedge)%ldofe
          !write(7,*)'nnode=',nnode,'igroup=',igroup,'nfdof=',nfdof,'ipoin=',ipoin,'jpoin=',jpoin
          !write(7,*)'inode=',inode,'jnode=',jnode
       end do                                        !3
    end do                                               !4

    do iedge=1,nedge
       vdimn=edges(iedge)%vdimn  !20211031
       index=edges(iedge)%index
       nnode=edges(iedge)%nnode
       edimn=elkn(index)%ndimn
       order_int=elkn(index)%el_field(1)%order_intrules(2)
       ngaus=elkn(index)%ggaus(order_int)%ngaus
       edges(iedge)%ngaus=ngaus
       allocate(edges(iedge)%edgegaus(ngaus))
       allocate(lnode(nnode),elcod(nnode,edimn+1))
       lnode=edges(iedge)%lnode
       do inode=1,nnode
          elcod(inode,:)=coord(:,lnode(inode))
          if(vdimn/=0)  elcod(inode,vdimn)=0.  !20211028
       end do

       allocate(shape(nnode),deriv(edimn,nnode),cartd(edimn,nnode))
       allocate(s(edimn+1,edimn+1),a3(edimn+1),elcod0(edimn,nnode))
       allocate(rr(ndimn,ndimn),xjaci(edimn,edimn))

       do ig=1,ngaus
          allocate(edges(iedge)%edgegaus(ig)%cartd(edimn,nnode),  &
          edges(iedge)%edgegaus(ig)%djacb,               &
          edges(iedge)%edgegaus(ig)%shape(nnode),        &
          edges(iedge)%edgegaus(ig)%rotation(edimn+1,edimn+1))
          shape=elkn(index)%ggaus(order_int)%shape(:,ig)
          deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
          weigp=elkn(index)%ggaus(order_int)%weigp(ig)
          edges(iedge)%edgegaus(ig)%shape=shape
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
          !print *,'iedge=',iedge,'aa=',aa
          s(edimn+1,:)=s(edimn+1,:)/aa
          a3=s(edimn+1,:)

          call cosc(edimn+1,a3,elcod0,elcod,rr)
          call jacob(iedge, edimn, nnode,elcod0,deriv,cartd, djacb,xjaci)
          edges(iedge)%edgegaus(ig)%djacb=djacb*weigp
          edges(iedge)%edgegaus(ig)%cartd=cartd
          edges(iedge)%edgegaus(ig)%rotation=transpose(rr)
          !if(vdimn==3)write(7,*)'ig=',ig,'aa=',aa,'rotation(ndimn)=',edges(iedge)%edgegaus(ig)%rotation(ndimn,:)
       end do       !!ig

       deallocate (shape,deriv,cartd,s,a3,elcod0,elcod,lnode,rr,xjaci)

    end do           !!iedge

 
22  continue
    print *, 'iblks=',iblks,'lineload=',lineload

    contains

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


    END SUBROUTINE external_load_1
    
     subroutine find_pload_points(icpoin,xyz)  !20210502
integer(ink) ielem,jgroup,i0,jpoin,idimn,icpoin,inout,iiter,inode, &
             nplink,nnode,ie,linke
integer(ink),allocatable::lnods(:),liste(:),list_link(:)
real(irk)   s,t,u,xyz(:),djacb
real(irk),allocatable::xyzl(:),xyzmin(:,:),xyzmax(:,:),elcod(:,:),local(:),shape(:),deriv(:,:), &
        residu(:),xyz_star(:),dlocal(:),locale(:,:),shape_intp(:,:),factor(:),factor_link(:), &
        cartd(:,:),ratio(:),xjaci(:,:)

allocate(xyzl(ndimn),xyzmin(ndimn,nelem),xyzmax(ndimn,nelem),local(ndimn))
 allocate(residu(ndimn),xyz_star(ndimn),dlocal(ndimn),ratio(ndimn))
 allocate(locale(ndimn,20),liste(20),shape_intp(8,20))

do ielem=1,nelem
    jgroup=element(ielem)%group
    index=group(jgroup)%index
	nnode=elkn(index)%nnode
    if(appear_group_pload(jgroup)/=1)cycle
	allocate(lnods(nnode))
    lnods=element(ielem)%field(1)%lnods_f
    !write(chk_unit,*)'ie=',ielem,'lnods=',lnods
	allocate(elcod(ndimn,nnode))
	elcod=coord(:,lnods)
		do idimn=1,ndimn
		xyzmax(idimn,ielem)=maxval(elcod(idimn,:))
		xyzmin(idimn,ielem)=minval(elcod(idimn,:))
		end do
	deallocate(lnods,elcod)
end do

!!!1
print *,'xyz=',xyz
linke=0

do ielem=1,nelem
    jgroup=element(ielem)%group
    index=group(jgroup)%index
	nnode=elkn(index)%nnode

	if(appear_group_pload(jgroup)/=1) cycle
    ratio=(xyz-xyzmin(:,ielem))/(xyzmax(:,ielem)-xyzmin(:,ielem))
   if(all(ratio>-1.e-5).and.all(ratio<(1+1.e-5))) then   !! 1
        print *,'ielem=',ielem,'ratio=',ratio,'miter=',miter
   
    xyzl=xyz      
	allocate(lnods(nnode))
	lnods=element(ielem)%field(1)%lnods_f
	allocate(elcod(ndimn,nnode))
	elcod=coord(:,lnods)


	local=0.
	allocate(shape(nnode),deriv(ndimn,nnode),cartd(ndimn,nnode),xjaci(ndimn,ndimn))

if((index==23.or.index==24).and.miter==0)then
	call element_in_out(xyzl,elcod,local,inout)
	if (inout==1) then
		s=local(1)
		if(ndimn>1)t=local(2)
		if(ndimn>2)u=local(3)
		call shfunc(ndimn,nnode,s,t,u,shape,deriv)
		linke=linke+1
		liste(linke)=ielem
		locale(:,linke)=local(1:ndimn)
		shape_intp(1:nnode,linke)=shape
	end if !end if inout==1
else

	do iiter=1,10	  !!iiter
	    shape=0.;deriv=0.
		s=local(1)
		if(ndimn>1)t=local(2)
		if(ndimn>2)u=local(3)
		call shfunc(ndimn,nnode,s,t,u,shape,deriv)
        call jacob(ielem,ndimn,nnode,elcod,deriv,cartd,djacb,xjaci)

		xyz_star=matmul(elcod,shape)
		residu=(xyzl-xyz_star)
		if(all(abs(residu).le.1.e-3)) then   !20200825
			if(all(abs(local).le.(1+1.e-3))) then    !!this is modefy point's clearness
				linke=linke+1
				liste(linke)=ielem
				locale(:,linke)=local(1:ndimn)
				shape_intp(1:nnode,linke)=shape
			endif
		goto 10
		endif
		dlocal=matmul(transpose(xjaci),residu)
		local=local+dlocal
    end do		!end do iiter
    10 continue
end if  !end if elemshape
	deallocate(shape,deriv,cartd,elcod,lnods,xjaci)
   endif	!!1
end do		!end do ielem

deallocate(xyzl)

	allocate(factor(npoin))
	factor=0.

	do ie=1,linke
		ielem=liste(ie)
    jgroup=element(ielem)%group
    index=group(jgroup)%index
	nnode=elkn(index)%nnode

		allocate(lnods(nnode))
	lnods=element(ielem)%field(1)%lnods_f
			do inode=1,nnode
			factor(lnods(inode))=factor(lnods(inode))+shape_intp(inode,ie)
			end do
		deallocate(lnods)
	end do

	factor=factor/linke
   
	nplink=0.

	do jpoin=1,npoin
		if(abs(factor(jpoin)).ge.1.e-5) then !20200825
		nplink=nplink+1
		endif
	end do

	allocate(list_link(nplink),factor_link(nplink))
	nplink=0

	do jpoin=1,npoin
	if(abs(factor(jpoin)).ge.1.e-5) then !20200825
	nplink=nplink+1
	list_link(nplink)=jpoin
	factor_link(nplink)=factor(jpoin)
	endif
    end do
    
    ploadr(icpoin)%nintf=nplink
    allocate(ploadr(icpoin)%listf(nplink),ploadr(icpoin)%rintf(nplink))
    ploadr(icpoin)%listf=list_link
    ploadr(icpoin)%rintf=factor_link


	if(nplink==0) then
	print *,'error in finding nodal loads for point:'
    print *,'xyz=',xyz
    stop
    endif

	deallocate(factor,list_link,factor_link)

    
 deallocate(xyzmin,xyzmax,local,residu,xyz_star,dlocal)
 deallocate(locale,liste,shape_intp,ratio)



     end subroutine find_pload_points !20210502
  !==========================================================================
subroutine element_in_out(xyz,elcod,local,inout)
real(irk) xyz(:),elcod(:,:),local(:),jacobi(3,3),b(3,1),x(3,1),res(3,1)
real(irk) detjacobi,err,minerr,err0,err1,sumlocal
integer(ink) inout,i
jacobi=0.
inout=0
minerr=1.e-6
b(:,1)=xyz(:)-elcod(:,1)

do i=2,4
	jacobi(:,i-1)=elcod(:,i)-elcod(:,1)
end do
call det3(jacobi,detjacobi)

if (abs(detjacobi)<1.e-5) then
	inout=0
else
	call lin_sol_gen(jacobi, b, x)
	res = b - matmul(jacobi,x)
	err = maxval(abs(res))
	if (err <= 1.e-5) then
		local(:)=x(:,1)
		err0=minval(local)
		err1=maxval(local)
		sumlocal=sum(local)
		if(err0>=(0.0-minerr).and.err1<=(1+minerr).and.sumlocal<=(1+minerr))inout=1
	else
		print *,'error when solver'
		write(chkunit,*)'error when solver'
!			stop
	end if
end if

end subroutine element_in_out
   
     subroutine lin_sol_gen(xjacm, b, x)
!      ------  Obtains : gauss points global coordinates,
!                        determinant of jacobian matrix
!                        cartesian derivatives of shape functions
!
    integer(ink) i,j,ip1,ip2,jp1,jp2
    real(irk)    djacb
    real(irk)   xjacm(3,3), xjaci(3,3),b(3,1),x(3,1)


          call det3 (xjacm,djacb)                
          djacb =  xjacm(1,1)*                  &
                  (xjacm(2,2)*xjacm(3,3)-xjacm(2,3)*xjacm(3,2))  &
                 - xjacm(1,2)*                  &
                  (xjacm(2,1)*xjacm(3,3)-xjacm(2,3)*xjacm(3,1))  &
                 + xjacm(1,3)*                  &
                  (xjacm(2,1)*xjacm(3,2)-xjacm(2,2)*xjacm(3,1))
          if (djacb.le.0.0) then
           print *, ' Jacob is less than zero = ', djacb
              stop
          endif
          DO i=1,3
             ip1=i+1-i/3*3
             ip2=ip1+1-ip1/3*3
             DO j=1,3
                jp1=j+1-j/3*3
                jp2=jp1+1-jp1/3*3
                xjaci(j,i) =  (xjacm(ip1,jp1)*xjacm(ip2,jp2)   &
                            -  xjacm(ip2,jp1)*xjacm(ip1,jp2)) / djacb
             enddo
          enddo

         x=matmul(xjaci,b)

      end subroutine lin_sol_gen

   
     
  !!!!!!!!!
  
    subroutine external_load_2

    character(20) text,type_curve
    integer(ink) itcurve,npload,iplgroup,tedge,iedge,             &
                 i0,aelem,index,nnode_f,ndofn_f,inode,            &
                 sedge,nnode,ipoin,edimn,order_int,jnode,         &
                 ngaus,jpoin,ig,idofn,i1,i2,nudofn,igroup,nfdof,  &
                 ipegroup,ndofn,ntime,indey,nline,ncdis,nevab,    &
                 begin_edge,end_edge,water,ibeamload,    &
                 iplateload,i3,i4,jedge,nextr,ip,tplateload,vdimn,code_load !20211031
    integer(ink),allocatable::lnode(:)
    integer(ink),pointer::lnods(:)
    real    (irk) aa,weigp,djacb,cor0,cor1,p0,p1,fact,dcor,dl,cc, &
                  f1,f2,f3,f4,f5,f6,corx
    real    (irk) rn,cor01,cor11,p01,p11,fact1  !20211031
    real    (irk),allocatable::a3(:),shape(:),elcod(:,:),gcom(:), &
                               deriv(:,:),elcod0(:,:),cartd(:,:), &
                               s(:,:),rr(:,:),press(:,:),xload(:),&
                               edload(:),trot(:,:),rload(:),      &
                               rload1(:),gloc(:),ppp(:),pppx(:),trotx(:,:) !steel 2006
    real    (irk),pointer::rotation(:,:)

   

    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_title_1,0)
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_title_2,0)
    print *,text
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)edge_load_group,delgroup
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_edge_load_groups,0)
    
    print *,'edge_load_group=',edge_load_group,'delgroup=',delgroup
    lineload=lineload+3
    if (edge_load_group==0) goto 33
    if (allocated(edgeload)) deallocate(edgeload)
    if (allocated(gpwater)) deallocate(gpwater)
    allocate(edgeload(edge_load_group))
    allocate(gpwater(delgroup)) !2013/3/18
    jedge=0
    do ipegroup=1,delgroup
       read(loadunit,*)begin_edge,end_edge,itcurve,water,code_load
       gpwater(ipegroup)%water=water    !2013/3/18
       lineload=lineload+1
       !!
       if (water/=0) then
          read(loadunit,*)cor0,cor1,p0,p1,fact
           gpwater(ipegroup)%cor0=cor0     !2013/3/18
           gpwater(ipegroup)%cor1=cor1     !2013/3/18
           gpwater(ipegroup)%p0=p0         !2013/3/18
           gpwater(ipegroup)%p1=p1         !2013/3/18
           gpwater(ipegroup)%fact=fact     !2013/3/18
           
          lineload=lineload+1
       endif
          if (code_load/=0) then !20211031  ，默认正侧部分，增加负侧部分
          read(loadunit,*)cor01,cor11,p01,p11,fact1
          lineload=lineload+1
           endif

       !!
       do iedge=begin_edge,end_edge
          jedge=jedge+1
          edgeload(jedge)%iedge=iedge
          edgeload(jedge)%idelgroup=ipegroup  !2013/3/18
          
          edgeload(jedge)%itcurve=itcurve
          index=edges(iedge)%index
          nnode=edges(iedge)%nnode
          ngaus=edges(iedge)%ngaus
          edimn=elkn(index)%ndimn
          aelem=edges(iedge)%aelem
          vdimn=edges(iedge)%vdimn  !20211031
             
          ndofn=ndimn
          allocate(press(edimn+1,nnode),shape(nnode),rr(edimn+1,edimn+1),xload(edimn+1))
          allocate(edload(ndofn*nnode))
          allocate(edgeload(jedge)%edload(ndofn*nnode))

          edload=0.0
!! special for water_pressure
          if (water/=0) then
               press=0.0
  if(vdimn/=3) then  !常规水压力计算  !20211031 
             do inode=1,nnode
                if(vdimn==0)then
			    corx=coord(abs(water),edges(iedge)%lnode(inode))
                else
			    corx=coord(3,edges(iedge)%lnode(inode))
                endif
                if (water>0) then
                   dcor=cor0-corx
                   if (dcor.le.0.)dcor=0.
                   press(ndimn,inode)=-(p0+dcor/(cor0-cor1)*(p1-p0))*fact
                else
                   dcor=corx-cor0
                   if (dcor.le.0.)dcor=0.
                   press(ndimn,inode)=-(p0+dcor/(cor0-cor1)*(p1-p0))*fact
                endif
				if (cor0>=cor1)then
				   if(corx>(cor0+0.01).or.corx<(cor1-0.01))press(ndimn,inode)=0.
				else
				   if(corx>(cor1+0.01).or.corx<(cor0-0.01))press(ndimn,inode)=0.
				endif
             end do
  else  !隧洞按规范计算侧向和垂直向水土压力
       if(vdimn/=abs(water))cycle
       rn=edges(iedge)%edgegaus(1)%rotation(ndimn,3)
       if(abs(rn-1)<.01)then
                do inode=1,nnode
			    corx=coord(1,edges(iedge)%lnode(inode))
                if (water>0) then
                   dcor=cor0-corx
                   if (dcor.le.0.)dcor=0.
                   press(ndimn,inode)=-(p0+dcor/(cor0-cor1)*(p1-p0))*fact
                else
                   dcor=corx-cor0
                   if (dcor.le.0.)dcor=0.
                   press(ndimn,inode)=-(p0+dcor/(cor0-cor1)*(p1-p0))*fact
                endif
				if (cor0>=cor1)then
				   if(corx>(cor0+0.01).or.corx<(cor1-0.01))press(ndimn,inode)=0.
				else
				   if(corx>(cor1+0.01).or.corx<(cor0-0.01))press(ndimn,inode)=0.
				endif
             end do

       elseif(abs(rn+1)<.01)then
                do inode=1,nnode
			    corx=coord(1,edges(iedge)%lnode(inode))
                if (water>0) then
                   dcor=cor01-corx
                   if (dcor.le.0.)dcor=0.
                   press(ndimn,inode)=-(p01+dcor/(cor01-cor11)*(p11-p01))*fact1
                else
                   dcor=corx-cor01
                   if (dcor.le.0.)dcor=0.
                   press(ndimn,inode)=-(p01+dcor/(cor01-cor11)*(p11-p01))*fact1
                endif
				if (cor01>=cor11)then
				   if(corx>(cor01+0.01).or.corx<(cor11-0.01))press(ndimn,inode)=0.
				else
				   if(corx>(cor11+0.01).or.corx<(cor01-0.01))press(ndimn,inode)=0.
				endif
             end do

       endif
 endif
             
             
!! end of special considering
          else
             press=0.
             read(loadunit,*)i0,(press(edimn+1,inode),inode=1,nnode)   !(press(1:edimn+1,inode),inode=1,nnode)
             lineload=lineload+1
          endif
          do ig=1,ngaus
             djacb=edges(iedge)%edgegaus(ig)%djacb
             shape=edges(iedge)%edgegaus(ig)%shape
             rr=edges(iedge)%edgegaus(ig)%rotation
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
          edgeload(jedge)%edload=edload
          
          !write(7,*)'jedge=',jedge,'edload=',edgeload(jedge)%edload


          deallocate(press,shape,rr,xload,edload)
       end do !iedge
    end do !ipegroup

    ! get time curve for each group in the block
    ! only the increment is considered.
    ! if(tcurvegravity(igroup)==0.or.appear(igroup)<=0),
    !                                 no gravity in igroup
33  if(.not.allocated(factg))allocate(factg(ndimn))
    if (.not.allocated(factf))allocate(factf(ndimn))
    read (loadunit,*,iostat=yl_ios,iomsg=yl_msg) text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_title_3,0)
    read (loadunit,*,iostat=yl_ios,iomsg=yl_msg) gravy,factg(1:ndimn),factf(1:ndimn)
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_gravity,0)
    print *,'gray=',gravy,factg(1:ndimn),factf(1:ndimn)
    lineload=lineload+2


    if (.not.allocated(tcurvegravity))allocate(tcurvegravity(ngroup))
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)text,nline
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_gravity_curve_title,0)
    read(loadunit,*,iostat=yl_ios,iomsg=yl_msg)tcurvegravity(1:ngroup)
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_gravity_curves,0)
print *,'tcurv=',tcurvegravity(1:ngroup)

    lineload=lineload+nline+1

    read (loadunit,*,iostat=yl_ios,iomsg=yl_msg) text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_title_4,0)
    read (loadunit,*,iostat=yl_ios,iomsg=yl_msg) nbeamload
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_beam_load_count,0)
	
    lineload=lineload+2
    if (nbeamload/=0) then
       nevab=6
       if (ndimn==3)nevab=12
       if (allocated(beamload))deallocate(beamload)
       allocate(beamload(nbeamload))
       allocate(edload(nevab),gcom(ndimn),elcod(ndimn,2),trot(nevab,nevab),  &
       rload(nevab),rload1(nevab),gloc(ndimn),trotx(nevab,nevab))
       do ibeamload=1,nbeamload
          allocate(beamload(ibeamload)%edload(nevab))
          read(loadunit,*)i0,aelem,itcurve,gloc(1:ndimn),cc
          !read(loadunit,*)i0,aelem,itcurve,gloc(1:ndimn)
          !cc=dl
          lineload=lineload+1
          beamload(ibeamload)%aelem=aelem
          beamload(ibeamload)%itcurve=itcurve
          rotation=>element(aelem)%rotation
          gcom=rotation.x.gloc
          lnods=>element(aelem)%field(1)%lnods_f
          elcod=coord(:,lnods)
          dl=sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))
          cc=cc*dl

          rload=0.
          trot=0.
          f1=1.-.5*cc/dl
          f2=(2.-2*(cc/dl)**2+(cc/dl)**3)*cc/2.
          f3=(6.-8.*cc/dl+3.*(cc/dl)**2)*cc**2/12.
          f4=.5*cc/dl
          f5=cc-f2
          f6=(4.-3.*cc/dl)*cc**3/12./dl
          if (ndimn==2)then
             trot(1:ndimn,1:ndimn)=rotation
             trot(3,3)=1.
             trot(4:5,4:5)=rotation
             trot(6,6)=1.
             rload(1)=gcom(1)*f1;    rload(4)=gcom(1)*f4
             rload(2)=gcom(2)*f2;    rload(5)=gcom(2)*f5
             rload(3)=-gcom(2)*f3;   rload(6)=gcom(2)*f6
          else if(ndimn==3) then
             trot(1:3,1:3)=rotation; trot(4:6,4:6)=rotation
             trot(7:9,7:9)=rotation; trot(10:12,10:12)=rotation
             rload(1)=gcom(1)*f1;      rload(7) =gcom(1)*f4
             rload(2)=gcom(2)*f2;      rload(8) =gcom(2)*f5
             rload(3)=gcom(3)*f2;      rload(9) =gcom(3)*f5
             rload(5)=-gcom(3)*f3;     rload(11)=gcom(3)*f6
             rload(6)=-gcom(2)*f3;     rload(12)=gcom(2)*f6
          endif
          !write(chkunit,*)'ielem=',ielem,'rload=',rload
          rload1=transpose(trot).x.rload
          !write(chkunit,*)'ielem=',ielem,'rload1=',rload1

          igroup=element(aelem)%group
          !steel 2006
          if (any(listglocbeam==igroup))then
             if (ndimn==2)then
                trotx=0.
                trotx(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
                trotx(3,3)=1.
                trotx(4:5,4:5)=prot(:,:,lnods(2))
                trotx(6,6)=1.
             elseif(ndimn==3)then
                trotx=0.
                trotx(1:3,1:3)=prot(:,:,lnods(1)); trotx(4:6,4:6)=prot(:,:,lnods(1))
                trotx(7:9,7:9)=prot(:,:,lnods(2)); trotx(10:12,10:12)=prot(:,:,lnods(2))
             endif
             rload=trotx.x.rload1
			 rload1=rload
          endif
		  
          !steel 2006
          beamload(ibeamload)%edload=rload1
          nullify(lnods,rotation)
       end do
       deallocate(trot,elcod,rload,rload1,gloc,trotx)
    endif
    read (loadunit,*,iostat=yl_ios,iomsg=yl_msg) text
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_title_5,0)
    read (loadunit,*,iostat=yl_ios,iomsg=yl_msg) nplateload
    call diag_check_read(yl_ios,yl_msg,RD_LOA_external_load_2_plate_load_count,0)
    
    if(nplateload==0)return
    nevab=24    !20200113
    if (allocated(plateload))deallocate(plateload)
    if (allocated(edload))deallocate(edload)  !20200113
    allocate(plateload(nplateload),edload(nevab))

	iplateload=0
    do while (iplateload<nplateload)
       read (loadunit,*) text
       read (loadunit,*) igroup,itcurve,water
       tplateload=group(igroup)%nelgroup
       read(loadunit,*)cor0,cor1,p0,p1,fact
       lineload=lineload+3
       do iedge=1,group(igroup)%nelgroup
	      iplateload=iplateload+1
          aelem=group(igroup)%list(iedge) !20200606
          lineload=lineload+1
          allocate(plateload(iplateload)%edload(nevab))
          call plate_water(aelem,water,cor0,cor1,p0,p1,fact,edload)
          plateload(iplateload)%aelem=aelem
          plateload(iplateload)%itcurve=itcurve
          plateload(iplateload)%edload=edload
       end do

    enddo

    print *, 'iblks=',iblks,'lineload=',lineload

    END SUBROUTINE external_load_2
    

    
    subroutine step_water_pressure  !2023/04/01
    integer(ink) jedge,iedge,idelgroup,water,index,nnode,ngaus,edimn,ndofn,ig,i0,inode,idofn
       real(irk) coef,cor00,cor0,cor1,p0,p1,dcor,corx,djacb   !,fact  20230402
     real(irk),allocatable:: press(:,:),shape(:),rr(:,:),xload(:),edload(:)
     
      
      
     do jedge=1,edge_load_group
       iedge=edgeload(jedge)%iedge
       
          index=edges(iedge)%index
          nnode=edges(iedge)%nnode
          ngaus=edges(iedge)%ngaus
          edimn=elkn(index)%ndimn
          ndofn=ndimn
          
          allocate(press(edimn+1,nnode),shape(nnode),rr(edimn+1,edimn+1),xload(edimn+1))
          allocate(edload(ndofn*nnode))         
   
          edload=0.0;  press=0.0   
       
       idelgroup=edgeload(jedge)%idelgroup
       water=gpwater(idelgroup)%water 
       
       if(water==0) stop 'error in step_water_pressure for water=0'
       coef=coef_water(idelgroup,istep)
       !fact=gpwater(idelgroup)%fact    !2013/3/18
                       
      
!! special for water_pressure
           
             do inode=1,nnode
			    corx=coord(abs(water),edges(iedge)%lnode(inode))
                 if(water>0)dcor=coef-corx
                 if(water<0)dcor=corx-coef
             if (dcor.le.0.)dcor=0.
                  press(ndimn,inode)=-dcor*gamaw    !20230402 fact  !20230401
                

             end do
!! end of special considering

10 continue   
          do ig=1,ngaus
             djacb=edges(iedge)%edgegaus(ig)%djacb
             shape=edges(iedge)%edgegaus(ig)%shape
             rr=edges(iedge)%edgegaus(ig)%rotation
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
          edgeload(jedge)%edload=edload
          !write(7,*)'jedge=',jedge,'edload=',edgeload(jedge)%edload
            
       deallocate(press,shape,rr,xload,edload)
       end do !jedge
    
     
       
     end subroutine step_water_pressure

    subroutine direct(a3,r,idm)
    integer(ink) idm
    real   (irk) xx,a3(:),r(:,:)
    real   (irk),allocatable::ax(:)
    if (idm==3)then
       allocate(ax(size(a3)))
       ax=a3
    endif
    r(idm,:)=a3
    if (idm.eq.2) then
       r(1,1)=r(2,2)
       r(1,2)=-r(2,1)
       return
    endif
    xx=a3(1)**2+a3(3)**2
    !!X,Y,Z ---global axis, x,y,z--local axis
    !!z is the normal direction of the surface
    !!    if z/=Y, x=Y*z, y=z*x
    !!    if z=y,  x=X*z, y=z*x
    if (xx.gt..001) then
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
    a3=ax
    deallocate(ax)
    end subroutine direct

     subroutine direct_goodman(a3,r,idm,a1)
     integer(ink) idm
     real   (irk) xx,a3(:),r(:,:),a1(:)
     real   (irk),allocatable::ax(:)
     r(idm,:)=a3
     if(idm.eq.2) then
        r(1,1)=r(2,2)
        r(1,2)=-r(2,1)
     return
     endif
      r(1,:)=a1(:)
	  allocate(ax(size(a3)))
      r(2,1)=r(3,2)*r(1,3)-r(3,3)*r(1,2)
      r(2,2)=r(3,3)*r(1,1)-r(3,1)*r(1,3)
      r(2,3)=r(3,1)*r(1,2)-r(3,2)*r(1,1)
      ax=r(2,:)**2
      xx=sqrt(sum(ax))
      r(2,:)=r(2,:)/xx
	  deallocate(ax)
      end subroutine direct_goodman

    subroutine gravity
    character(10)fieldid,field1,name,special
    integer(ink) index,nrfields,ifield
    integer(ink) iaxe,i0,idimn !20231113
    integer(ink) inode,nnode,ngaus,ig,ndofn,nevab,matno,ielem,igroup, &
    ielgroup,idofn,order_int,uplift_ic,kind_wt  !20220409
    real   (irk) density,ratio,tdensity,djacb,density_s,poros,satur,thick,dl,ppp,  &
    gcomi(3),rloadi(24),rloadg(24),density_w !20220409
    real   (irk),allocatable::shape(:),gcom(:),elcod(:,:),trot(:,:),  &
    rload(:),rload1(:),trotx(:,:)
    real   (irk),pointer::rotation(:,:),shapwxy(:,:)
    integer(ink),pointer::lnods(:),ldofs(:)
    real   (irk) cor1,cor2,coef1,coef2,coefx  !20221104
    real   (irk),pointer::gpcod(:)  !20221104
    real   (irk),allocatable::gcomQ(:)   !20221104



!write(7,*)'gravity','block_stab=',block_stab
    DO igroup =1,ngroup
!write(7,*)'igroup=',igroup,'appear(igroup)=',appear(igroup),'tcurve=',tcurvegravity(igroup)
      !if ((block_stab/=0.and.tcurvegravity(igroup)/=0).or.(appear(igroup)>0.and.tcurvegravity(igroup)/=0)) then  !20200220
         if (tcurvegravity(igroup)/=0) then    !2017/11/19
          field1=    group(igroup)%fieldid(1:1)
          if  (field1=='U') then
             index  = group(igroup)%index
             if(index==25)cycle
             nrfields= group(igroup)%nrfields
             fieldid= group(igroup)%fieldid
             special= group(igroup)%special
             order_int=elkn(index)%el_field(1)%order_intrules(1)
             nnode    =elkn(index)%el_field(1)%nnode_f
             ndofn=group(igroup)%dof(1)%nfdof
             nevab=ndofn*nnode
	         uplift_ic=group(igroup)%uplift_ic !20220409
             
             
             if (index/=20.and.index/=21)ngaus=elkn(index)%ggaus(order_int)%ngaus
             matno = group(igroup)%matno
             name=props(matno)%name
             density_s=props(matno)%mechanical%solid%density
             density_w=props(matno)%mechanical%solid%density_w
              kind_wt=props(matno)%mechanical%solid%kind_wt

             ratio=props(matno)%mechanical%solid%ratio    

             allocate (gcom(ndimn),shape(nnode))
             if(Qstatic/=0.or.outind==-1) allocate (gcomQ(ndimn))  !20231113
             if(Qstatic/=0) allocate (gpcod(ndimn))  !20231113

             thick=1.
             if (ndimn==2.or.index==22.or.index==26)thick=props(matno)%mechanical%solid%thickness !20230910
             if (nnode==2)thick  =props(matno)%geometry%aera
             if (index==20.or.index==21.or.index==1) then
                allocate(trot(nevab,nevab),rload(nevab),rload1(nevab),elcod(ndimn,nnode),trotx(nevab,nevab)) !steel 2006
             endif
             DO ielgroup = 1,group(igroup)%nelgroup      !ielgroup
                ielem = group(igroup)%list(ielgroup)
                if (ice0(ielem)==1)goto 100
                element(ielem)%field(1)%rload=0.0
                
                if (index/=20.and.index/=21) then !not for beam
                   do ig=1,ngaus               !! ig
            tdensity=density_s*ratio  !作单相介质考虑时，density_s作为骨架重量；
            !作两相介质考虑时，density_s作为土体颗粒重量
            !if (fieldid(1:2)=='UW')tdensity=density_s*ratio  !20220502
                      shape=elkn(index)%ggaus(order_int)%shape(:,ig)
                      djacb=element(ielem)%egaus(order_int)%djacb(ig)
             if(nrfields==1.and.uplift_ic/=0.and.kind_wt/=0)then  !!20220409(单相介质考虑湿容重）
			   if(element(ielem)%field(1)%isatu(ig)>=1)  &
                   tdensity=tdensity+density_w*(1-ratio)
               !write(7,*)'ie=',ielem,'ig=',ig,'tdensity=',tdensity
              endif   !!!  20220409           
                      
                      if (fieldid(2:2)=='W') then
                         density=props(matno)%mechanical%fluid%density
                         if (name(1:6)=='NSSoil') then
                            !order_int=elkn(index)%el_field(2)%order_intrules(2)
                            poros=element(ielem)%egaus(order_int)%poros(ig)
                            satur=element(ielem)%egaus(order_int)%satur(ig)
                            tdensity=density_s+density*poros*satur
                         else
                            ldofs=>element(ielem)%field(2)%ldofs_f
                            ratio  =props(matno)%mechanical%fluid%ratio
                            ppp=result_zero(ldofs).d.shape
                            if (ppp>-0.01)tdensity=density_s+density*ratio
                            nullify(ldofs)
                         endif
                      endif

                      gcom=factg*gravy*tdensity*thick
                      
                      if(outind==-1) then  !20231113
                            ldofs=>element(ielem)%field(1)%lnods_f
                            do idimn=1,ndimn
                            gcomQ(idimn)=thick*accq(idimn,ldofs).d.shape
                            end do
                            nullify(ldofs)
                            gcom=gcom+gcomQ
                      endif !20231113
                      
                    if(Qstatic/=0) then  !20221104
                        if(qstatic_force%appearg(igroup)/=0)then
                        iaxe=qstatic_force%iaxe
                       gpcod=element(ielem)%egaus(order_int)%gpcod(:,ig)
                           do i0=1,Qstatic-1
                            cor1=qstatic_force%cor_coef(1,i0)
                            cor2=qstatic_force%cor_coef(1,i0+1)
                            coef1=qstatic_force%cor_coef(2,i0)
                            coef2=qstatic_force%cor_coef(2,i0+1)
                            if((gpcod(iaxe)>=cor1.and.gpcod(iaxe)<=cor2).or.   &
                               (gpcod(iaxe)>=cor2.and.gpcod(iaxe)<=cor1))then
                               coefx=coef1+(coef2-coef1)*(gpcod(iaxe)-cor1)/(cor2-cor1)
                        !write(7,*)'ie=',ielem,'igaus=',ig,'gpcod=',gpcod,'coefx=',coefx !20221104
                        
                               goto 11
                            endif
                           end do
                         print *, 'stop  for error in find position for qstatic_force'
                         stop
11                       continue             
                         gcomQ=thick*coefx*qstatic_force%qfactor
                         !write(7,*)'gcomQ=',gcomQ   !20221104
                          gcom=gcom+gcomQ
                        endif
                    endif  !20221104
                      
                      
                      
                      !write(7,*)'igroup=',igroup,'factg=',factg,'gravy=',gravy,'tdensity=',tdensity,'gcom=',gcom

                      if (index==22.and.(special(1:1)=='C'.or.special(1:1)=='S')) then

                         rotation=>element(ielem)%rotation
                         lnods=>element(ielem)%field(1)%lnods_f

                         shapwxy=>element(ielem)%egaus(1)%shapwxy(:,:,ig)
                         gcomi=rotation.x.gcom
                         rloadi=0.;rloadg=0.
                         do inode=1,nnode
                            idofn=(inode-1)*ndofn
                            rloadi(idofn+1:idofn+2)=djacb*shape(inode)*gcomi(1:2)
                            rloadi(idofn+3:idofn+5)=djacb*shapwxy(:,inode)*gcomi(3)
                         end do
                         do inode=1,nnode
                            idofn=(inode-1)*ndofn
                            rloadg(idofn+1:idofn+3)=transpose(rotation).x.rloadi(idofn+1:idofn+3)
                            rloadg(idofn+4:idofn+6)=transpose(rotation).x.rloadi(idofn+4:idofn+6)
                         end do
                         element(ielem)%field(1)%rload=element(ielem)%field(1)%rload+rloadg
                         nullify(shapwxy,rotation,lnods)

                      elseif(index/=1)then

                         do inode=1,nnode
                            idofn=(inode-1)*ndofn
                            element(ielem)%field(1)%rload(idofn+1:idofn+ndimn)            &
                            =element(ielem)%field(1)%rload(idofn+1:idofn+ndimn)+      &
                            djacb*shape(inode)*gcom
                         end do
                         
                         !write(7,*)'ie=',ielem,'ig=',igaus,'rload=',element(ielem)%field(1)%rload
					  else !杆单元 !barsteel
					     lnods=>element(ielem)%field(1)%lnods_f
                         if (any(listglocbeam==igroup))then
                            if (ndimn==2)then
                               trotx=0.
                               trotx(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
                               trotx(3:3,3:4)=prot(:,:,lnods(2))
                            elseif(ndimn==3)then
                               trotx=0.
                               trotx(1:3,1:3)=prot(:,:,lnods(1))
							   trotx(4:6,4:6)=prot(:,:,lnods(2))
                            endif
							rload1=0.
                            do inode=1,nnode
                               idofn=(inode-1)*ndofn
                               rload1(idofn+1:idofn+ndimn)=djacb*shape(inode)*gcom
                            enddo
                            rload=trotx.x.rload1
                            element(ielem)%field(1)%rload=element(ielem)%field(1)%rload+rload
						 else
                            do inode=1,nnode
                               idofn=(inode-1)*ndofn
                               element(ielem)%field(1)%rload(idofn+1:idofn+ndimn)            &
                               =element(ielem)%field(1)%rload(idofn+1:idofn+ndimn)+      &
                               djacb*shape(inode)*gcom
                            end do
                         endif
                         nullify(lnods)
                      endif
                   end do                       !!ig
                else ! for beam
                   rotation=>element(ielem)%rotation
                   gcom=rotation.x.factg
                   gcom=gcom*gravy*tdensity*thick
                   lnods=>element(ielem)%field(1)%lnods_f
                   elcod=coord(:,lnods)
                   dl=sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))
                   rload=0.
                   trot=0.
                   if (ndimn==2)then
                      trot(1:ndimn,1:ndimn)=rotation
                      trot(3,3)=1.
                      trot(4:5,4:5)=rotation
                      trot(6,6)=1.
                      rload(1)=gcom(1)*dl/2.;    rload(4)=gcom(1)*dl/2.
                      rload(2)=gcom(2)*dl/2.;    rload(5)=gcom(2)*dl/2.
                      rload(3)=-gcom(2)*dl**2/12.;rload(6)=gcom(2)*dl**2/12.
                   else if(ndimn==3) then
                      trot(1:3,1:3)=rotation; trot(4:6,4:6)=rotation
                      trot(7:9,7:9)=rotation; trot(10:12,10:12)=rotation
                      rload(1)=gcom(1)*dl/2.;    rload(7)=gcom(1)*dl/2.
                      rload(2)=gcom(2)*dl/2.;    rload(8)=gcom(2)*dl/2.
                      rload(3)=gcom(3)*dl/2.;    rload(9)=gcom(3)*dl/2.
                      rload(5)=-gcom(3)*dl**2/12.;rload(11)=gcom(3)*dl**2/12.
                      rload(6)=-gcom(2)*dl**2/12.;rload(12)=gcom(2)*dl**2/12.
                   endif
                   rload1=transpose(trot).x.rload
                   !steel 2006
                   if (any(listglocbeam==igroup))then
                      if (ndimn==2)then
                         trotx=0.
                         trotx(1:ndimn,1:ndimn)=prot(:,:,lnods(1))
                         trotx(3,3)=1.
                         trotx(4:5,4:5)=prot(:,:,lnods(2))
                         trotx(6,6)=1.
                      elseif(ndimn==3)then
                         trotx=0.
                         trotx(1:3,1:3)=prot(:,:,lnods(1)); trotx(4:6,4:6)=prot(:,:,lnods(1))
                         trotx(7:9,7:9)=prot(:,:,lnods(2)); trotx(10:12,10:12)=prot(:,:,lnods(2))
                      endif
                      rload=trotx.x.rload1				   
					  rload1=rload
                   endif

                   !steel 2006
                   element(ielem)%field(1)%rload           &
                   =element(ielem)%field(1)%rload+rload1
                   nullify(lnods,rotation)
                endif
                100     continue
             end do                                     !!ielgroup
             deallocate(gcom,shape)
             if(Qstatic/=0.or.outind==-1)deallocate(gcomQ)  !20231113
             if(Qstatic/=0)deallocate(gpcod)  !20231113
             if (index==20.or.index==21.or.index==1)deallocate(trot,rload,rload1,elcod,trotx)
          end if   !! for displacement field
       end if    !!for appear>0 && tcurvegravity!=0
    END DO             !igroup

    END subroutine gravity

    !!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine gravity1
    
    character(10)fieldid,field1,name,special
    integer(ink) index,nrfields,ifield
    integer(ink) inode,nnode,ngaus,ig,ndofn,nevab,matno,ielem,igroup, &
    ielgroup,idofn,order_int
    real   (irk) density,ratio,tdensity,djacb,density_s,poros,satur,thick,ppp,  &
    gcomi(3)
    real   (irk),allocatable::shape(:),gcom(:),elcod(:,:)
    integer(ink),pointer::lnods(:),ldofs(:)

    DO igroup =1,ngroup

       !if (appear(igroup)>0.and.tcurvegravity(igroup)/=0) then
         if (tcurvegravity(igroup)/=0) then    !2017/11/19

          field1=    group(igroup)%fieldid(1:1)
          if  (field1=='U') then
             index  = group(igroup)%index
             nrfields= group(igroup)%nrfields
             fieldid= group(igroup)%fieldid
             special= group(igroup)%special
             order_int=elkn(index)%el_field(1)%order_intrules(2)
             nnode    =elkn(index)%el_field(1)%nnode_f
             ndofn=group(igroup)%dof(1)%nfdof
             nevab=ndofn*nnode
             if (index/=20.and.index/=21)ngaus=elkn(index)%ggaus(order_int)%ngaus
             matno = group(igroup)%matno
             allocate (gcom(ndimn),shape(nnode))

             thick=1.
             if (ndimn==2.or.index==22.or.index==26)thick=props(matno)%mechanical%solid%thickness
             if (nnode==2)thick  =props(matno)%geometry%aera
             DO ielgroup = 1,group1(igroup)%nelgroup      !ielgroup
                ielem = group1(igroup)%list(ielgroup)
                element1(ielem)%field(1)%rload=0.0
                if (jce1(ielem)==1) goto 100
                name=props(matno)%name
                density_s=props(matno)%mechanical%solid%density
                tdensity=density_s

                do ig=1,ngaus               !! ig
                   tdensity=density_s
                   shape=elkn(index)%ggaus(order_int)%shape(:,ig)
                   djacb=element1(ielem)%egaus(order_int)%djacb(ig)
                   if (fieldid(2:2)=='W') then
                      density=props(matno)%mechanical%fluid%density
                      if (name(1:6)=='NSSoil') then
                         order_int=elkn(index)%el_field(2)%order_intrules(2)
                         poros=element1(ielem)%egaus(order_int)%poros(ig)
                         satur=element1(ielem)%egaus(order_int)%satur(ig)
                         tdensity=density_s+density*poros*satur
                      else
                         ldofs=>element1(ielem)%field(2)%ldofs_f
                         ratio  =props(matno)%mechanical%fluid%ratio
                         ppp=result_zero(ldofs).d.shape
                         if (ppp>-0.01)tdensity=density_s+density*ratio
                         nullify(ldofs)
                      endif
                   endif

                   gcom=factg*gravy*tdensity*thick
                   do inode=1,nnode
                      idofn=(inode-1)*ndofn
                      element1(ielem)%field(1)%rload(idofn+1:idofn+ndimn)            &
                      =element1(ielem)%field(1)%rload(idofn+1:idofn+ndimn)+      &
                      djacb*shape(inode)*gcom
                   end do
                end do                       !!ig
                100    continue
             end do                                     !!ielgroup
             deallocate(gcom,shape)
          end if   !! for displacement field
       end if    !!for appear>0 && tcurvegravity!=0
    END DO             !igroup

    END subroutine gravity1
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    subroutine gravity2
    
    character(10)fieldid,field1,name,special
    integer(ink) index,nrfields,ifield
    integer(ink) inode,nnode,ngaus,ig,ndofn,nevab,matno,ielem,igroup, &
    ielgroup,idofn,order_int
    real   (irk) density,ratio,tdensity,djacb,density_s,poros,satur,thick,ppp,  &
    gcomi(3)
    real   (irk),allocatable::shape(:),gcom(:),elcod(:,:)
    integer(ink),pointer::lnods(:),ldofs(:)

    DO igroup =1,ngroup

       !if (appear(igroup)>0.and.tcurvegravity(igroup)/=0) then
   if (tcurvegravity(igroup)/=0) then   !2017/11/19
          field1=    group(igroup)%fieldid(1:1)
          if  (field1=='U') then
             index  = group(igroup)%index
             nrfields= group(igroup)%nrfields
             fieldid= group(igroup)%fieldid
             special= group(igroup)%special
             order_int=elkn(index)%el_field(1)%order_intrules(2)
             nnode    =elkn(index)%el_field(1)%nnode_f
             ndofn=group(igroup)%dof(1)%nfdof
             nevab=ndofn*nnode
             if (index/=20.and.index/=21)ngaus=elkn(index)%ggaus(order_int)%ngaus
             matno = group(igroup)%matno
             allocate (gcom(ndimn),shape(nnode))

             thick=1.
             if (ndimn==2.or.index==22.or.index==26)thick=props(matno)%mechanical%solid%thickness
             if (nnode==2)thick  =props(matno)%geometry%aera
             DO ielgroup = 1,group2(igroup)%nelgroup      !ielgroup
                ielem = group2(igroup)%list(ielgroup)
                element2(ielem)%field(1)%rload=0.0
                name=props(matno)%name
                density_s=props(matno)%mechanical%solid%density
                tdensity=density_s

                do ig=1,ngaus               !! ig
                   tdensity=density_s
                   shape=elkn(index)%ggaus(order_int)%shape(:,ig)
                   djacb=element2(ielem)%egaus(order_int)%djacb(ig)
                   if (fieldid(2:2)=='W') then
                      density=props(matno)%mechanical%fluid%density
                      if (name(1:6)=='NSSoil') then
                         order_int=elkn(index)%el_field(2)%order_intrules(2)
                         poros=element2(ielem)%egaus(order_int)%poros(ig)
                         satur=element2(ielem)%egaus(order_int)%satur(ig)
                         tdensity=density_s+density*poros*satur
                      else
                         ldofs=>element2(ielem)%field(2)%ldofs_f
                         ratio  =props(matno)%mechanical%fluid%ratio
                         ppp=result_zero(ldofs).d.shape
                         if (ppp>-0.01)tdensity=density_s+density*ratio
                         nullify(ldofs)
                      endif
                   endif

                   gcom=factg*gravy*tdensity*thick
                   do inode=1,nnode
                      idofn=(inode-1)*ndofn
                      element2(ielem)%field(1)%rload(idofn+1:idofn+ndimn)            &
                      =element2(ielem)%field(1)%rload(idofn+1:idofn+ndimn)+      &
                      djacb*shape(inode)*gcom
                   end do
                end do                       !!ig
                100    continue
             end do                                     !!ielgroup
             deallocate(gcom,shape)
          end if   !! for displacement field
       end if    !!for appear>0 && tcurvegravity!=0
    END DO             !igroup

    END subroutine gravity2
    
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    subroutine plate_water(ielem,water,cor0,cor1,p0,p1,fact,rload)
    
    integer(ink) index,water,ielem
    integer(ink) inode,nnode,ngaus,ig,ndofn,nevab,matno,igroup, &
    idofn,order_int
    real   (irk) djacb,gcomi(3),rloadi(24),rloadg(24),rload(:),       &
    cor0,cor1,p0,p1,fact,pressg,dcor,press(4)
    real   (irk),allocatable::shape(:),gcom(:)
    real   (irk),pointer::rotation(:,:),shapwxy(:,:)
    integer(ink),pointer::lnods(:)


    igroup =element(ielem)%group
    index  = group(igroup)%index
    order_int=elkn(index)%el_field(1)%order_intrules(2)
    nnode    =elkn(index)%el_field(1)%nnode_f
    ndofn=group(igroup)%dof(1)%nfdof
    nevab=ndofn*nnode
    ngaus=elkn(index)%ggaus(order_int)%ngaus
    rotation=>element(ielem)%rotation
    lnods=>element(ielem)%field(1)%lnods_f
    allocate (gcom(ndimn),shape(nnode))

    rload=0.
    do ig=1,ngaus               !! ig
       shape=elkn(index)%ggaus(order_int)%shape(:,ig)
       djacb=element(ielem)%egaus(order_int)%djacb(ig)

       pressg=0.
       if (water/=0) then
          press=0.0
          do inode=1,nnode
             if (water>0) then
                dcor=cor0-coord(water,lnods(inode))
                if (dcor.le.0.)dcor=0.
                press(inode)=-(p0+dcor/(cor0-cor1)*(p1-p0))*fact
             else
                dcor=coord(-water,lnods(inode))-cor0
                if (dcor.le.0.)dcor=0.
                press(inode)=-(p0+dcor/(cor0-cor1)*(p1-p0))*fact
             endif
             pressg=press.d.shape
          end do
       endif

       gcom=0.
       shapwxy=>element(ielem)%egaus(1)%shapwxy(:,:,ig)
       gcomi=rotation.x.gcom
       if (water/=0)gcomi(3)=gcom(3)+pressg

       rloadi=0.;rloadg=0.
       do inode=1,nnode
          idofn=(inode-1)*ndofn
          rloadi(idofn+1:idofn+2)=djacb*shape(inode)*gcomi(1:2)
          rloadi(idofn+3:idofn+5)=djacb*shapwxy(:,inode)*gcomi(3)
       end do
       do inode=1,nnode
          idofn=(inode-1)*ndofn
          rloadg(idofn+1:idofn+3)=transpose(rotation).x.rloadi(idofn+1:idofn+3)
          rloadg(idofn+4:idofn+6)=transpose(rotation).x.rloadi(idofn+4:idofn+6)
       end do
       rload=rload+rloadg
    end do                       !!ig

    nullify(shapwxy,rotation,lnods)
    deallocate(gcom,shape)

    END subroutine plate_water
    !
    SUBROUTINE LOADFL
    
    !******************************************************************
    !
    !*** FORMS RIGHT HAND SIDE OF FLOW EQUATION. FLOW DUE TO BODY FORCE.
    !
    !******************************************************************
    
    character(10) fieldid,name
    integer(ink)igroup,nrfields,ifield,matno,order_int,nnode,    &
    inode,igaus,ngaus,nevab,lnode,idimn,icdofn,      &
    itotv,ielgroup,ielem,index,order_intx
    integer(ink),pointer::lnods(:)
    real   (irk) djacb,density,coef,permr
    real   (irk),allocatable::gxcom(:),rload(:),accex(:),        &
    bodyx(:),valux(:),accein(:,:),     &
    shape(:),cartd(:,:),permx(:)
    real   (irk),pointer::perme(:)


    DO igroup =1,ngroup

       if (appear(igroup)>0.and.tcurvegravity(igroup)/=0) then
          nrfields = group(igroup)%nrfields
          fieldid  = group(igroup)%fieldid


          do ifield=1,nrfields
             if (fieldid(ifield:ifield)=='W')then
                index    = group(igroup)%index
                matno    = group(igroup)%matno
                density  = props(matno)%mechanical%fluid%density

if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
              allocate(perme(ndimn))
              perme=xvalue(props(matno)%mechanical%fluid%iperm)
else    
              perme=> props(matno)%mechanical%fluid%permeability
endif
          
                
                order_int=elkn(index)%el_field(ifield)%order_intrules(1)
                nnode    =elkn(index)%el_field(ifield)%nnode_f
                ngaus=elkn(index)%ggaus(order_int)%ngaus
                nevab=nnode*group(igroup)%dof(ifield)%nfdof

                allocate(gxcom(ndimn),rload(nevab),bodyx(ndimn),    &
                valux(ndimn),shape(nnode),cartd(ndimn,nnode),permx(ndimn))
                if (kgmat/=0)allocate(accein(ndimn,nnode),accex(ndimn))

                gxcom=factf*gravy

                coef=-1.0  ! coef is for symmetric coupling requirement
                if (type_problem/='Q')then
                   coef=-theta1*ditime
                   if (type_problem=='F'.and.nrfields==2)coef=-theta1/beeta1
                endif

                DO ielgroup =1,group(igroup)%nelgroup      !ielgroup
                   ielem = group(igroup)%list(ielgroup)
                   !allocate(element(ielem)%field(1)%rload(nevab))
                   rload=0.0

                   if (kgmat/=0) then       !! take out the acceleartion
                      lnods=> element(ielem)%field(ifield)%lnods_f
                      accein=0.0
                      do inode=1,nnode
                         lnode=lnods(inode)
                         do idimn=1,ndimn
                            icdofn=lmdofn(idimn)
                            if (icdofn>0) then
                               itotv=nodfn(icdofn,lnode)
                               accein(idimn,inode)=result_second(itotv)
                            endif
                         end do
                      end do
                   endif


                   do igaus=1,ngaus               !! igaus
                      djacb=element(ielem)%egaus(order_int)%djacb(igaus)
                      shape=elkn(index)%ggaus(order_int)%shape(:,igaus)
                      cartd=element(ielem)%egaus(order_int)%cartd(:,:,igaus)

                      permx=perme
                      if (fieldid(1:2)=='UW') then
                         name=props(matno)%name
                         if (name(1:6)=='NSSoil') then

                            order_intx=elkn(index)%el_field(2)%order_intrules(1)
                            permr=element(ielem)%egaus(order_intx)%permr(igaus)
                            permx=perme*permr

                         endif
                      elseif(fieldid(1:1)=='W') then
                         name=props(matno)%name
                         if (name(1:6)=='NSSoil') then

                            order_intx=elkn(index)%el_field(1)%order_intrules(1)
                            permr=element(ielem)%egaus(order_intx)%permr(igaus)
                            permx=perme*permr

                         endif
                      endif

                      if (kgmat/=0) then
                         accex=matmul(accein,shape)
                      endif
                      BODYX=GXCOM
                      if (allocated(fachv))bodyx=bodyx-FACHV   !! fachv--excitation
                      if (kgmat/=0) then
                         bodyx=bodyx+accex
                      endif
                      VALUX=permx*DENSITY*BODYX

                      do inode=1,nnode
                         rload(inode)=rload(inode)+                        &
                         djacb*dot_product(valux,cartd(:,inode))
                      end do

                   end do   !! for igaus

                   element(ielem)%field(ifield)%rload=rload*coef
                   nullify(lnods)
                end do  !! ielgroup
                deallocate(gxcom,rload,bodyx,valux,permx)
                if (kgmat/=0)deallocate(accein,accex)
                deallocate(shape,cartd)
            if(Bparameter/=0.and.props(matno)%mechanical%fluid%iperm/=0)then
             deallocate(perme)
             else
                nullify(perme)
             endif
             endif
          end do    !! for ifield
       endif
    end do    !! for igroup

    END SUBROUTINE LOADFL

    END   MODULE APPLIED_LOAD
