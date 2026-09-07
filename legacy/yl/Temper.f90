    module temperature

    use yl_diag
    use yl_diag_registry
    use variable_types
    use arrayutil
    use global_var
    use materials
    use applied_load

    implicit none
    integer(ink)ntedge,ntelgroup, npipe,algo_pipe,ntemp_surface   !20230402
    
    type tgauss_edge
       real(irk),pointer::djacb,shape(:)
    end type tgauss_edge

    type tedge_define
       integer(ink) nnode,ngaus,index,aelem,ibeta_bar
       real   (irk) beta_bar
       integer(ink),pointer::lnode(:), ldofe(:)
       type(tgauss_edge),pointer::tedgegaus(:)
    end type tedge_define
    
  type pipe_cooling_define   !20200316
  integer(ink) nline,nelocal,nnodc
  real   (irk) Qw,lamda_w,density_w,Cw,begin_time,end_time,twater_curve,coef
  integer(ink),pointer::listp(:,:),liste(:),ldofe(:,:),aelem(:),line_pipe(:,:)
  real   (irk),pointer::Qconcrete(:),edstif(:,:,:)
  real   (irk),pointer::temp_var_node(:),temp_var0_node(:)
  end type pipe_cooling_define !20200316

    type group_of_tedge_load
       integer(ink) iedge,itcurve
       real   (irk),pointer::edload(:),edstif(:,:)
    end type group_of_tedge_load
    
     type temp_time_depth_curve  !20230402
       integer(ink) ntime_gap,vertical_direction,nheight
       real   (irk),pointer:: time(:),height(:),temp(:,:)
     end type temp_time_depth_curve !20230402
     
     
    type(tedge_define),allocatable::tedges(:)         !nedge
    type(group_of_tedge_load), allocatable::tedgeload(:)    !nelgroup
    type(pipe_cooling_define),allocatable::pipeinfo(:)         !20200316
    type(temp_time_depth_curve),allocatable::temp_surface(:)         !20230402

    contains

    SUBROUTINE boundt


    character(10) text
    integer(ink) itcurve,tedge,iedge,i0,aelem,index,nnode_f,            &
    inode,sedge,nnode,ipoin,edimn,order_int,jnode,jgroup,         &
    ngaus,jpoin,ig,ipegroup,indey,nline,ncool,icool, &  !20200221
      nelocal,twater_curve,ipipe,ie,nnodc,iel,jelem,nelink,igroup, &        !20200316 pipe
			  matno,ielgroup,ielem,ictran,ibeta_bar,begin_edge,end_edge,  &
              j0,ntime_gap,vertical_direction,nheight  !20230402
    integer(ink),allocatable::lnode(:),listdge(:)   &
                              ,line_pipe(:,:),icpipe(:),icpe(:)  !20200316
    real    (irk) aa,weigp,djacb,beta_bar
    real    (irk),allocatable::a3(:),shape(:),elcod(:,:),deriv(:,:),elcod0(:,:),cartd(:,:), &
    s(:,:),rr(:,:),ta(:), edload(:),edstif(:,:),xjaci(:,:)
    real    (irk)  Qw,lamda_w,density_w,Cw,begin_time,end_time,alfa1,coef ! 20200316 pipe

    
    
    if (meshc==1.or.rmesh/=0)rewind(tunit)
     if(Bparameter/=0.and.iblks==1)rewind(tunit)  !20230830
    
      print *,'ecwpipe=',ecwpipe,'iblks=',iblks,'lblks+1=',lblks+1
     if(iblks==lblks+1) then  !第一块或重新启动运行时输入下面这一部分
    	! equiv pipecooling 考虑通水冷却【等效算法】
         print *,'ecwpipe=',ecwpipe,'iblks=',iblks,'lblks+1=',lblks+1
    if(ecwpipe>=1)then   !20200221
	do igroup=1,ngroup
        allocate(group(igroup)%water_pipe)
        group(igroup)%water_pipe%pipecooling=0
        if(ecwpipe/=1) cycle  !20200221

	        read(tunit,*)text
	        read(tunit,*)ncool
            print *,'igroup=',igroup,'text=',text,'ncool=',ncool
	        group(igroup)%water_pipe%pipecooling=ncool
	        if(ncool.gt.0)then
	            allocate(group(igroup)%water_pipe%tb1(ncool),group(igroup)%water_pipe%te1(ncool), &
                         group(igroup)%water_pipe%tsw1(ncool),group(igroup)%water_pipe%taim1(ncool), &
                         group(igroup)%water_pipe%q1(ncool) )
         read(tunit,*) group(igroup)%water_pipe%gap_1,group(igroup)%water_pipe%gap_2,group(igroup)%water_pipe%L_pipe  
	            do icool=1,ncool
	                read(tunit,*)group(igroup)%water_pipe%tb1(icool),group(igroup)%water_pipe%te1(icool),  &
                group(igroup)%water_pipe%tsw1(icool),group(igroup)%water_pipe%taim1(icool),group(igroup)%water_pipe%q1(icool)
	            enddo
	        endif
    end do				  !!igroup     
	   
    endif
    
    if(outintr<0)then   !20200226
	do igroup=1,ngroup
        allocate(group(igroup)%temp_pre)
         read(tunit,*)text
	        read(tunit,*)group(igroup)%temp_pre%time0,group(igroup)%temp_pre%temp0, &
                         group(igroup)%temp_pre%temp_var_curve	       
    end do				  !!igroup     	   
    endif   !20200226
    
    
    
      endif

    if (restart==1)   then
       print *,'linet=',linet
       do i0=1,linet
          read(tunit,*)text
       end do
    end if

    !! set of edge_define structure

    if(iblks==1) then  !20230829
    read(tunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_title_1,0)
    read(tunit,*,iostat=yl_ios,iomsg=yl_msg)ntemp_surface  !20230402
    call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_temp_surface_count,0)
    if(ntemp_surface/=0)then
    !read(tunit,*)text
    allocate(temp_surface(ntemp_surface))
    
    do i0=1,ntemp_surface
        read(tunit,*)text
        read(tunit,*)ntime_gap,vertical_direction,nheight
        temp_surface(i0)%ntime_gap=ntime_gap
        temp_surface(i0)%vertical_direction=vertical_direction
        temp_surface(i0)%nheight=nheight
        allocate(temp_surface(i0)%height(nheight),temp_surface(i0)%time(ntime_gap), &
                 temp_surface(i0)%temp(ntime_gap,nheight))
        read(tunit,*)temp_surface(i0)%time(:)
        read(tunit,*)temp_surface(i0)%height(:)
     
        do j0=1,nheight
         read(tunit,*)temp_surface(i0)%temp(:,j0)   
        end do
    end do

    
    endif !20230402
    endif  !20230829
    
        read(tunit,*,iostat=yl_ios,iomsg=yl_msg)text
        call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_title_2,0)
    read(tunit,*,iostat=yl_ios,iomsg=yl_msg)ntedge  !20230402
    call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_temp_edge_count,0)

    print *,text
    print *,'ntedge=',ntedge
    
    linet=linet+2
    if (ntedge==0) goto 11
    if (allocated(tedges))deallocate(tedges)
    allocate(tedges(ntedge))
    tedge=0
    do while(tedge<ntedge)
       read(tunit,*)text                               !4
       read(tunit,*)sedge,nnode,index,beta_bar,ibeta_bar
       print *,'ibeta_bar=',ibeta_bar,'beta_bar=',beta_bar
       linet=linet+2
       do iedge=1,sedge                            !3
          tedge=tedge+1
          tedges(tedge)%nnode=nnode
          tedges(tedge)%index=index
          tedges(tedge)%beta_bar=beta_bar
          tedges(tedge)%ibeta_bar=ibeta_bar

          allocate(tedges(tedge)%lnode(nnode))
          read(tunit,*)i0,tedges(tedge)%lnode(1:nnode),tedges(tedge)%aelem
          linet=linet+1
          aelem=tedges(tedge)%aelem
          indey=element(aelem)%index
          nnode_f=elkn(indey)%el_field(1)%nnode_f
          allocate(tedges(tedge)%ldofe(nnode))
          do inode=1,nnode                  !2
             ipoin=tedges(tedge)%lnode(inode)
             do jnode=1,nnode_f        ! 11
                jpoin=element(aelem)%field(1)%lnods_f(jnode)
                if (ipoin.eq.jpoin)exit
             end do                    ! 11
             tedges(tedge)%ldofe(inode)=jnode
          end do                             !2
       end do                                        !3
    end do                                               !4

    do iedge=1,ntedge
       index=tedges(iedge)%index
       nnode=tedges(iedge)%nnode
       edimn=elkn(index)%ndimn
       order_int=elkn(index)%el_field(1)%order_intrules(2)
       ngaus=elkn(index)%ggaus(order_int)%ngaus
       tedges(iedge)%ngaus=ngaus
       allocate(tedges(iedge)%tedgegaus(ngaus))
       allocate(lnode(nnode),elcod(nnode,edimn+1))
       lnode=tedges(iedge)%lnode
       do inode=1,nnode
          elcod(inode,:)=coord(:,lnode(inode))
       end do
       allocate(shape(nnode),deriv(edimn,nnode),cartd(edimn,nnode))
       allocate(s(edimn+1,edimn+1),a3(edimn+1),elcod0(edimn,nnode))
       allocate(rr(ndimn,ndimn),xjaci(edimn,edimn))

       do ig=1,ngaus
          allocate( tedges(iedge)%tedgegaus(ig)%djacb,               &
          tedges(iedge)%tedgegaus(ig)%shape(nnode))
          shape=elkn(index)%ggaus(order_int)%shape(:,ig)
          deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
          weigp=elkn(index)%ggaus(order_int)%weigp(ig)
          tedges(iedge)%tedgegaus(ig)%shape=shape
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
          tedges(iedge)%tedgegaus(ig)%djacb=djacb*weigp
       end do       !!ig

       deallocate (shape,deriv,cartd,s,a3,elcod0,elcod,lnode,rr,xjaci)

    end do           !!iedge



    11    read(tunit,*)text
    read(tunit,*,iostat=yl_ios,iomsg=yl_msg)text
    call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_title_3,0)
    read(tunit,*,iostat=yl_ios,iomsg=yl_msg)ntelgroup
    call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_temp_elgroup_count,0)
    linet=linet+3
    if (ntelgroup==0) goto 22
    if (allocated(tedgeload)) deallocate(tedgeload)
    allocate(tedgeload(ntelgroup))
    tedge=0
    do while(tedge<ntelgroup)
       read(tunit,*)text                               !4
       read(tunit,*)sedge,itcurve,nline
       read(tunit,*)begin_edge,end_edge
       linet=linet+2
       allocate(listdge(sedge))
       do ie=begin_edge,end_edge
           iedge=ie-begin_edge+1
          listdge(iedge)=ie
       end do
       do ipegroup=1,sedge
          tedge=tedge+1
          iedge=listdge(ipegroup)
          tedgeload(tedge)%iedge=iedge
          tedgeload(tedge)%itcurve=itcurve
          index=tedges(iedge)%index
          nnode=tedges(iedge)%nnode
          ngaus=tedges(iedge)%ngaus
          aelem=tedges(iedge)%aelem
          indey=element(aelem)%index
         if(Bparameter/=0.and.tedges(iedge)%ibeta_bar/=0)then
           beta_bar=xvalue(tedges(iedge)%ibeta_bar)
          else 
           beta_bar=tedges(iedge)%beta_bar
          endif         
          allocate(ta(nnode),shape(nnode))
          allocate(edload(nnode),edstif(nnode,nnode))
          allocate(tedgeload(tedge)%edload(nnode),tedgeload(tedge)%edstif(nnode,nnode))
          edload=0.0
          edstif=0.0
          !  read(tunit,*)ta(1:nnode)
          ta=1.
          !  linet=linet+1
          do ig=1,ngaus
             djacb=tedges(iedge)%tedgegaus(ig)%djacb
             shape=tedges(iedge)%tedgegaus(ig)%shape
             do inode=1,nnode
                do jnode=1,nnode
                   edstif(inode,jnode)=edstif(inode,jnode)+shape(inode)*  &
                   shape(jnode)*djacb*beta_bar
                end do
             end do

          end do
          edload=edstif.x.ta
          tedgeload(tedge)%edload=edload
          tedgeload(tedge)%edstif=edstif

          deallocate(ta,shape,edload,edstif)
       end do
       deallocate(listdge)
    end do  ! do while
22    read(tunit,*,iostat=yl_ios,iomsg=yl_msg)text
      call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_title_4,0)
      read(tunit,*,iostat=yl_ios,iomsg=yl_msg)text
      call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_title_5,0)
      print *, text
	  read(tunit,*,iostat=yl_ios,iomsg=yl_msg)npipe,algo_pipe
   call diag_check_read(yl_ios,yl_msg,RD_TEM_boundt_pipe_count,0)
      
      print *,'npipe,algo_pipe=',npipe,algo_pipe
linet=linet+3
	  if(npipe==0) goto 32

     if(allocated(pipeinfo))deallocate(pipeinfo)
     allocate(pipeinfo(npipe))     

	 do ipipe=1,npipe
	 if(algo_pipe==1)then
     read(tunit,*) nline,igroup,nnodc,coef  !nelocal
     print *,'nline,nelocal,nnodc=',nline,nelocal,nnodc
     linet=linet+1
     
     elseif(algo_pipe>=2)then
     read(tunit,*) nline,igroup,coef  !coef is for discount of the no real pipes
     linet=linet+1
     endif
     
     read(tunit,*) Qw,lamda_w,density_w,Cw,begin_time,end_time,twater_curve
     linet=linet+1
	 print *,'Qw=',Qw,lamda_w,density_w,Cw,begin_time,end_time,twater_curve
	 pipeinfo(ipipe)%nline=nline
	 pipeinfo(ipipe)%Qw=Qw
	 pipeinfo(ipipe)%Cw=Cw
	 pipeinfo(ipipe)%lamda_w=lamda_w
	 pipeinfo(ipipe)%density_w=density_w
	 pipeinfo(ipipe)%begin_time=begin_time
	 pipeinfo(ipipe)%end_time=end_time
	 pipeinfo(ipipe)%twater_curve=twater_curve
	 pipeinfo(ipipe)%coef=coef
   if(algo_pipe<=2)then
  allocate( pipeinfo(ipipe)%Qconcrete(nline+1))
  allocate( pipeinfo(ipipe)%Temp_var_node(nline+1))
  allocate( pipeinfo(ipipe)%Temp_var0_node(nline+1))
   endif
	 if(algo_pipe==1)then
         nelocal=group(igroup)%nelgroup  !20200320
	   pipeinfo(ipipe)%nelocal= nelocal
	   pipeinfo(ipipe)%nnodc=nnodc
       allocate( pipeinfo(ipipe)%liste(nelocal))
       allocate( pipeinfo(ipipe)%listp(nnodc,nline+1))
       !read(tunit,*)pipeinfo(ipipe)%liste(1:nelocal) 
       pipeinfo(ipipe)%liste(1:nelocal) = group(igroup)%list(1:group(igroup)%nelgroup)
     linet=linet+1
	   do ie=1,nline+1
       read(tunit,*)i0,pipeinfo(ipipe)%listp(1:nnodc,ie)
     linet=linet+1
	   end do
	 elseif(algo_pipe==2)then
	             allocate(line_pipe(2,nline))
				 allocate(icpe(nelem))
				 icpe=0
	 do ie=1,nline
     read(tunit,*)i0,line_pipe(:,ie)
     linet=linet+1
	 end do
	   pipeinfo(ipipe)%nnodc=1
       allocate( pipeinfo(ipipe)%listp(1,nline+1))
       pipeinfo(ipipe)%listp(1,1)=line_pipe(1,1)
	   	 do ie=1,nline
         pipeinfo(ipipe)%listp(1,1+ie)=line_pipe(2,ie)
	     end do
		 do ie=1,nline+1
		 jpoin=pipeinfo(ipipe)%listp(1,ie)
           do i0=1,group(igroup)%np_unode  !20200321
           ipoin=group(igroup)%unode(i0)%ipoin
           if(jpoin==ipoin)then        
		 nelink=group(igroup)%unode(i0)%ne_unode
	       do iel=1,nelink
           jelem=group(igroup)%unode(i0)%list(iel)
		   icpe(jelem)=1
           end do
           end if
           end do !20200321
		 end do
		 nelocal=sum(icpe)
		 pipeinfo(ipipe)%nelocal=nelocal
         allocate( pipeinfo(ipipe)%liste(nelocal))
		 nelocal=0
		 do ie=1,nelem
         if(icpe(ie)==1)then
		 nelocal=nelocal+1
         pipeinfo(ipipe)%liste(nelocal)=ie
		 endif
		 end do
	                    deallocate(line_pipe,icpe)
	  else if(algo_pipe>=3)then
        allocate( pipeinfo(ipipe)%line_pipe(3,nline))
	    do ie=1,nline
        if(igroup/=0) &
        read(tunit,*)i0,pipeinfo(ipipe)%line_pipe(1:2,ie)
        if(igroup==0) &
        read(tunit,*)i0,pipeinfo(ipipe)%line_pipe(:,ie)
     linet=linet+1
	    end do
		allocate( pipeinfo(ipipe)%ldofe(2,nline),pipeinfo(ipipe)%edstif(2,2,nline), &
		          pipeinfo(ipipe)%aelem(nline))
    if(igroup==0) then    !20210102
              do ie=1,nline
            
              pipeinfo(ipipe)%ldofe(1:2,ie)=pipeinfo(ipipe)%line_pipe(1:2,ie)
              pipeinfo(ipipe)%aelem(ie)=pipeinfo(ipipe)%line_pipe(3,ie)
                    jgroup=element(pipeinfo(ipipe)%aelem(ie))%group
                  matno =group(jgroup)%matno
                  alfa1 = props(matno)%heat%alfa(1)
              
           pipeinfo(ipipe)%edstif(1,1,ie)=-1.; pipeinfo(ipipe)%edstif(1,2,ie)=1.
           pipeinfo(ipipe)%edstif(2,2,ie)=1.;  pipeinfo(ipipe)%edstif(2,1,ie)=-1.
           pipeinfo(ipipe)%edstif(:,:,ie)=pipeinfo(ipipe)%edstif(:,:,ie)*  &
		                 coef*alfa1*.5*(Cw*density_w*Qw)/lamda_w
             end do
        
    else    !20210102
		    matno =group(igroup)%matno
         if(Bparameter/=0.and.props(matno)%heat%ialfa/=0)then 
          alfa1=xvalue(props(matno)%heat%ialfa)
          else 
          alfa1 = props(matno)%heat%alfa(1)
          endif

            index = group(igroup)%index
            nnode = elkn(index)%el_field(1)%nnode_f
			allocate(icpipe(nnode))
        do ie=1,nline
			!ictran=0
		       DO ielgroup = 1,group(igroup)%nelgroup
               ielem = group(igroup)%list(ielgroup)
               lnods =>element(ielem)%field(1)%lnods_f
		    icpipe=0
			   do inode=1,nnode
			   ipoin=lnods(inode)
!			   if(trans(ipoin)%nintf==0)then
			   if(lnods(inode)==pipeinfo(ipipe)%line_pipe(1,ie).or.  &
                  lnods(inode)==pipeinfo(ipipe)%line_pipe(2,ie)) icpipe(inode)=1

			   end do
			   nullify(lnods)
			   if(sum(icpipe)>2) stop !'error in boundt of pipe'
			   !if(ictran==0.and.sum(icpipe)==2) goto 15
               if(sum(icpipe)==2) goto 15
			   end do
			   print *,'stop in no find element for pipes'
			   stop !'error in boundt of pipe'
	15    pipeinfo(ipipe)%aelem(ie)=ielem
                do inode=1,2                 !2
                ipoin=pipeinfo(ipipe)%line_pipe(inode,ie)
                   do jnode=1,nnode       ! 11
                   jpoin=element(ielem)%field(1)%lnods_f(jnode)

                   if(ipoin.eq.jpoin)exit

                   end do                    ! 11
                   pipeinfo(ipipe)%ldofe(inode,ie)=jnode
                end do                             !2
!write(7,*)'ie=',ie,'aelem=',pipeinfo(ipipe)%aelem(ie),'ldofe=',pipeinfo(ipipe)%ldofe(:,ie)

           pipeinfo(ipipe)%edstif(1,1,ie)=-1.; pipeinfo(ipipe)%edstif(1,2,ie)=1.
           pipeinfo(ipipe)%edstif(2,2,ie)=1.; pipeinfo(ipipe)%edstif(2,1,ie)=-1.
           pipeinfo(ipipe)%edstif(:,:,ie)=pipeinfo(ipipe)%edstif(:,:,ie)*  &
		                 coef*alfa1*.5*(Cw*density_w*Qw)/lamda_w
           !write(7,*)'ie=',ie,'edstif=',pipeinfo(ipipe)%edstif(:,:,ie)
	   end do
	       deallocate(icpipe)
           
    endif  !20210102

	  endif   !for algo_pipe
	 end do  !npipe
 
    
32    continue
    
    
    
    
    
    
    print *,'linet=',linet
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


    end subroutine boundt
    
 SUBROUTINE heat_flow_charge(solve_post) !20200316

! caculate the flowcharge at every points
     character(10) fieldid
     integer(ink) ielem, matno,igroup,inode,nelocal,twater_curve,il,ipipe,ie,  &
                  ipoin,solve_post,itotv,nnodc,inodc,ixc
     real   (irk) alfa1,Qw,Cw,lamda_w,density_w,begin_time,end_time,temp_water,dl
     real   (irk) coef
     real   (irk),pointer::tload(:),fstif(:,:)
     real   (irk),allocatable::dtw(:),value(:),eload(:)
     integer(ink),pointer::lnods(:),ldofs(:)
	 integer(ink),allocatable::icp_heat(:)

     if(algo_pipe>=3)return
	 allocate(icp_heat(npoin))


	      do ipipe=1,npipe
		  
	 nline=pipeinfo(ipipe)%nline
     allocate(dtw(nline+1))
     dtw=0.
	 nelocal=pipeinfo(ipipe)%nelocal
     nnodc=pipeinfo(ipipe)%nnodc
	 Qw=pipeinfo(ipipe)%Qw
	 Cw=pipeinfo(ipipe)%Cw
	 lamda_w=pipeinfo(ipipe)%lamda_w
	 density_w=pipeinfo(ipipe)%density_w
	 begin_time=pipeinfo(ipipe)%begin_time
	 end_time=pipeinfo(ipipe)%end_time
	 twater_curve=pipeinfo(ipipe)%twater_curve
	 coef=pipeinfo(ipipe)%coef

	 !if((ttime-begin_time).le.1.e-5)goto 10
	 temp_water=tcurves(twater_curve)%dfact
	 if(solve_post==0)then
  !   if(abs(ttime-ditime-begin_time).le.1.e-5) then
  !   pipeinfo(ipipe)%Temp_var_node(1)=temp_water
  !   pipeinfo(ipipe)%Temp_var0_node(1)=temp_water
	 !else
	  do il=1,nline+1
          itotv=nodfn(1,pipeinfo(ipipe)%listp(1,il)) 
	  pipeinfo(ipipe)%Temp_var_node(il)=result_zero(itotv)
	  end do
	  pipeinfo(ipipe)%temp_var_node(1)=temp_water
      pipeinfo(ipipe)%Temp_var0_node=pipeinfo(ipipe)%Temp_var_node
     !endif
	 goto 10
     endif
!	 pipeinfo(ipipe)%temp_var_node(1)=temp_water
!     pipeinfo(ipipe)%Temp_var0_node=pipeinfo(ipipe)%Temp_var_node

	 icp_heat=0
	 do ie=1,nline+1
     icp_heat(pipeinfo(ipipe)%listp(:,ie))=ie
	 end do
	 pipeinfo(ipipe)%Qconcrete=0.

!ixc=0
		 do ie=1,nelocal
	 	 ielem=pipeinfo(ipipe)%liste(ie)
		 igroup =element(ielem)%group
         fieldid=group(igroup)%fieldid
         matno  =group(igroup)%matno
         if(Bparameter/=0.and.props(matno)%heat%ialfa/=0)then 
          alfa1=xvalue(props(matno)%heat%ialfa)
          else 
          alfa1 = props(matno)%heat%alfa(1)
          endif
         
		 if(appear(igroup)>0.and.fieldid(1:1)=='T') then
         !eload=>element(ielem)%field(1)%eload
         !tload=>element(ielem)%field(1)%tload
         lnods=>element(ielem)%field(1)%lnods_f
       fstif=>element(ielem)%field(1)%khandmc(1)%fstif
       ldofs=>element(ielem)%field(1)%ldofs_f  
       allocate(value(size(ldofs)),eload(size(ldofs))) 
       value=result_zero(ldofs)
       eload=MATMUL(fstif,value)
    !   if(ielem==1)then
    !write(7,*)'value=',value,'fstif=',fstif
    !write(7,*)'ldofs=',ldofs
    !write(7,*)'lnods=',lnods
    !   endif
ixc=0
	  do inode=1,size(lnods)
	  ipoin=lnods(inode)
	  if(icp_heat(ipoin)>0) then
       ixc=ixc+1  
       if(ixc==1)then
        write(7,*)'ielem=',ielem
    write(7,*)'value=',value
    write(7,*)'ldofs=',ldofs
    write(7,*)'lnods=',lnods
       endif       
          
      pipeinfo(ipipe)%Qconcrete(icp_heat(ipoin))=pipeinfo(ipipe)%Qconcrete(icp_heat(ipoin))  &
         -eload(inode)/(alfa1*coef)    
	                                             !-(eload(inode)-tload(inode))/(alfa1*coef)	 
	  endif
      end do
		 !nullify(eload,tload,lnods)
      nullify(fstif,ldofs,lnods)
      deallocate(value,eload)
		 endif
         end do       ! ielem
    write(7,*)'Qconcrete=',pipeinfo(ipipe)%Qconcrete
	 !do il=1,nline
  !   pipeinfo(ipipe)%Temp_var_node(il+1)=pipeinfo(ipipe)%Temp_var_node(1)+ &
	 !        (sum(pipeinfo(ipipe)%Qconcrete(1:il)))*lamda_w/(Cw*density_w*Qw)
	 !if(il/=nline)then
	 !pipeinfo(ipipe)%Temp_var_node(il+1)=pipeinfo(ipipe)%Temp_var_node(il+1)+ &
	 !.5*pipeinfo(ipipe)%Qconcrete(il+1)*lamda_w/(Cw*density_w*Qw)
	 !else
	 !pipeinfo(ipipe)%Temp_var_node(il+1)=pipeinfo(ipipe)%Temp_var_node(il+1)+ &
	 !pipeinfo(ipipe)%Qconcrete(il+1)*lamda_w/(Cw*density_w*Qw)
	 !endif
	 !end do
  !
     do il=1,nline
       if(il/=nline)then
	 dtw(il+1)=.5*pipeinfo(ipipe)%Qconcrete(il+1)*lamda_w/(Cw*density_w*Qw)
	 else
	 dtw(il+1)=pipeinfo(ipipe)%Qconcrete(il+1)*lamda_w/(Cw*density_w*Qw)
	 endif
     end do
     
     write(7,*)'dtw=',dtw
     
     do il=1,nline
      pipeinfo(ipipe)%Temp_var_node(il+1)=pipeinfo(ipipe)%Temp_var_node(1)+sum(dtw(1:il+1))
     end do 
10 continue
    !      do il=1,nline+1
		  !dl=sum((coord(:,pipeinfo(ipipe)%listp(1,il))-coord(:,pipeinfo(ipipe)%listp(1,1)))**2)
    ! 	  dl=sqrt(dl)
		  !write(7,111)dl*lamda_w/(Cw*density_w*qw),pipeinfo(ipipe)%Temp_var_node(il)/10.
		  !end do


	  do il=1,nline+1
          write(7,*)'il=',il,'listp=',pipeinfo(ipipe)%listp(:,il)
          write(7,*)'Temp_var_node=',pipeinfo(ipipe)%Temp_var_node(il)
        do inodc=1,nnodc
       itotv=nodfn(1,pipeinfo(ipipe)%listp(inodc,il)) 
       if(itotv/=0)then
      fixed(itotv)=pipeinfo(ipipe)%Temp_var_node(il)
	  result_zero(itotv)=pipeinfo(ipipe)%Temp_var_node(il)
       end if
       end do
	  end do

deallocate(dtw)
		 end do  !ipipe

		 deallocate(icp_heat)
111 format(2f15.3)

   END SUBROUTINE heat_flow_charge   !20200316
 
    

    SUBROUTINE HTMATRX
    
    character(10)fieldid
    integer(ink) igroup, nrfields, ifield,  index,            &
    matno,   nnode, order_intx,  in,  jn,         &
    ngaus,  ielgroup, ielem, igaus, ic,  idimn,lndimn,ie0 !20200220
    real   (irk)  djacb,  elknmk
    real   (irk),allocatable::hmatx(:,:), cartd(:,:)
    real   (irk),pointer:: alfa(:)

    DO igroup =1,ngroup
       if (appear(igroup)>0) then
          nrfields=group(igroup)%nrfields
          fieldid=group(igroup)%fieldid
          ic=0
          do ifield=1,nrfields
             if (fieldid(ifield:ifield)=='T')then
                ic=1
                exit
             end if
          end do
          if (ic==0) go to 10
          ! get information from the group level
          index = group(igroup)%index
             lndimn=elkn(index)%ndimn  !20200220
          matno = group(igroup)%matno
          nnode = elkn(index)%el_field(ifield)%nnode_f
          order_intx=elkn(index)%el_field(ifield)%order_intrules(1)
          ngaus = elkn(index)%ggaus(order_intx)%ngaus
          ! allocate the arrays which will be used
          allocate (hmatx(nnode,nnode),cartd(ndimn,nnode))
          
         if(Bparameter/=0.and.props(matno)%heat%ialfa/=0)then
          allocate(alfa(ndimn))
          alfa=xvalue(props(matno)%heat%ialfa)
          else 
          alfa=>props(matno)%heat%alfa 
          endif

          ! loop for 1:nelgroup
          DO ielgroup = 1,group(igroup)%nelgroup
             ielem = group(igroup)%list(ielgroup)
             hmatx=0.0_irk
             do igaus=1,ngaus
                ! get djacb and cartd in the element level
                djacb=element(ielem)%egaus(order_intx)%djacb(igaus)
                cartd=element(ielem)%egaus(order_intx)%cartd(:,:,igaus)


                do in=1,nnode
                   do jn=1,nnode
                      elknmk=0.0
                      do idimn=1,lndimn   !20200220
                         elknmk=elknmk+alfa(idimn)*cartd(idimn,in)*cartd(idimn,jn)
                      end do
                      hmatx(in,jn)=hmatx(in,jn)+djacb*elknmk
                   end do
                end do
             end do     !!igaus
             ! assembling to element stiff matrix
             element(ielem)%field(ifield)%khandmc(1)%fstif=hmatx
        if(iblks==1.and.ielgroup==1.and.istep==inc_step.and.iiter==1)then
		    write(chkunit,*)'igroup=',igroup,'ielem=',ielem,'alfa=',alfa,'hmatx='
		    do ie0=1,size(hmatx,dim=1)
		        write(chkunit,'(30e16.5)')hmatx(ie0,:)
		    end do
		end if        
   
             
          end do       !!ielgroup
          deallocate(hmatx,cartd)
         if(Bparameter/=0.and.props(matno)%heat%ialfa/=0)then
             deallocate(alfa)
         else
          nullify(alfa)
         endif
          10 continue
       end if        !! for appear
    end do         !!  for group


    END SUBROUTINE HTMATRX

     SUBROUTINE STMATRX
    character(10)fieldid
    integer(ink) igroup, nrfields, ifield,   index,    &
    matno,   nnode,  in, type_mass,    &
    ngaus,  ielgroup, ielem,  igaus,ic, nevab,    &
    ndofn, idofn, jn, jdofn,order_intx,idimn,ie0
    real   (irk)  djacb, dvolu, tdiagm
    real   (irk),allocatable::cmatx(:,:), shape(:), diagm(:), value(:)
    DO igroup =1,ngroup
       if (appear(igroup)>0) then
          nrfields=group(igroup)%nrfields
          fieldid=group(igroup)%fieldid
          ic=0
          do ifield=1,nrfields
             if (fieldid(ifield:ifield)=='T')then
                ic=1
                exit
             end if
          end do
          if (ic==0) goto 10
          ! get information from the group level
          index    = group(igroup)%index
          matno    = group(igroup)%matno
          type_mass= group(igroup)%type_mass(ifield)

          nnode = elkn(index)%el_field(ifield)%nnode_f
          ndofn=  group(igroup)%dof(ifield)%nfdof
          nevab=    nnode*ndofn
          order_intx=elkn(index)%el_field(ifield)%order_intrules(2)
          ngaus = elkn(index)%ggaus(order_intx)%ngaus
          ! allocate the arrays which will be used
          allocate (shape(nnode))
          if (type_mass==0)allocate (diagm(nnode),cmatx(nevab,1))
          if (type_mass==1)allocate (cmatx(nevab,nevab))

          ! loop for 1:nelgroup
          DO ielgroup = 1,group(igroup)%nelgroup
             ielem = group(igroup)%list(ielgroup)
             cmatx=0.0
             if (type_mass==0)then
                diagm=0.0
                dvolu=0.0
             endif
             do igaus=1,ngaus

                shape = elkn(index)%ggaus(order_intx)%shape(:,igaus)

                ! get djacb and cartd in the element level
                djacb=element(ielem)%egaus(order_intx)%djacb(igaus)
                if (type_mass==0) then
                   do in=1,nnode
                      diagm(in)=diagm(in)+djacb*shape(in)*shape(in)
                   end do
                   dvolu=dvolu+djacb
                else
                   do in=1,nnode
                      idofn=(in-1)*ndofn
                      do jn=1,nnode
                         jdofn=(jn-1)*ndofn
                         cmatx(idofn+1:idofn+ndofn,jdofn+1:jdofn+ndofn)=                    &
                         cmatx(idofn+1:idofn+ndofn,jdofn+1:jdofn+ndofn)                    &
                         +djacb*shape(in)*shape(jn)
                      end do
                   end do
                       !do idimn=1,ndofn
                       !   do in=1,nnode
                       !      idofn=(in-1)*ndofn+idimn
                       !      do jn=1,nnode
                       !         jdofn=(jn-1)*ndofn+idimn
                       !         cmatx(idofn,jdofn)=cmatx(idofn,jdofn)+djacb*shape(in)*shape(jn)
                       !      enddo
                       !   enddo
                       !enddo
                endif
             end do     !!igaus
             if (type_mass==0)then
                tdiagm=sum(diagm)
                tdiagm=dvolu/tdiagm
                do in=1,nnode
                   idofn=(in-1)*ndofn
                   cmatx(idofn+1:idofn+ndofn,1)=tdiagm*diagm(in)
                end do
             endif
             ! assembling to element stiff matrix
             element(ielem)%field(ifield)%khandmc(2)%fstif=cmatx
               if(iblks==1.and.ielgroup==1.and.istep==inc_step.and.iiter==1)then
		    write(chkunit,*)'igroup=',igroup,'ielem=',ielem,'cmatx='
		    do ie0=1,size(cmatx,dim=1)
		        write(chkunit,'(30e16.5)')cmatx(ie0,:)
		    end do
		end if           
             
          end do       !!ielgroup
          deallocate(shape)
          if (allocated(cmatx))deallocate(cmatx)
          if (allocated(diagm))deallocate(diagm)
          if (allocated(value))deallocate(value)
          10 continue
       end if        !! for appear
    end do         !!  for group

    END SUBROUTINE STMATRX

    subroutine heat_internal
    character(10) field1
    integer(ink) index,ifield,ic,nrfields
    integer(ink) inode,nnode,ngaus,ig,matno,ielem,igroup, &
    ielgroup,order_int,source_curve
    real   (irk) djacb,coef,time0,time
    real   (irk),allocatable::shape(:)


    DO igroup =1,ngroup
       !     print *,'igroup=',igroup,'ngroup=',ngroup
       if (appear(igroup)>0) then

          field1=    group(igroup)%fieldid
          nrfields=group(igroup)%nrfields
          ic=0
          do ifield=1,nrfields
             if (field1(ifield:ifield)=='T')then
                ic=1
                exit
             end if
          end do
          !        print *,'source_curve=',source_curve,'ic=',ic
          if (ic==0) goto 1
          matno=group(igroup)%matno
          source_curve=props(matno)%heat%source_curve
          if (appear_process(igroup,iblks)==1  .and.           &
          appear_process(igroup,iblks-1)==0.and.             &
          iincs==1.and.istep==inc_step)group(igroup)%btime=ttime-ditime*inc_step
          time0=group(igroup)%btime
          time=ttime-time0
          if (source_curve==0)goto 1
          call dfact_internal_heat(source_curve,time,coef)
          !        write(chkunit,*)'igroup=',igroup,'time=',time,'time0=',time0
          !        write(chkunit,*)'source_curve=',source_curve,'coef=',coef
          index  = group(igroup)%index
          order_int=elkn(index)%el_field(ifield)%order_intrules(2)
          nnode    =elkn(index)%el_field(ifield)%nnode_f
          ngaus=elkn(index)%ggaus(order_int)%ngaus
          allocate (shape(nnode))
          DO ielgroup = 1,group(igroup)%nelgroup      !ielgroup
             ielem = group(igroup)%list(ielgroup)
             element(ielem)%field(ifield)%rload=0.0

             do ig=1,ngaus               !! ig
                shape=elkn(index)%ggaus(order_int)%shape(:,ig)
                djacb=element(ielem)%egaus(order_int)%djacb(ig)

                do inode=1,nnode
                   element(ielem)%field(ifield)%rload(inode)            &
                   =element(ielem)%field(ifield)%rload(inode)+           &
                   djacb*shape(inode)*coef
                end do
             end do                       !!ig
          end do                                     !!ielgroup
          deallocate(shape)
          1  continue
       end if    !!for appear
    END DO             !igroup

    END subroutine heat_internal
    
   subroutine heat_internal1  !20200221  equiv pipecooling from chengjing
	character(20) field1,type_curve
	integer(ink) index,ifield,ic,nrfields,icw
	integer(ink) inode,nnode,ngaus,ig,matno,ielem,igroup,water_curve, &
	             ielgroup,order_int,source_curve,curmonth,jzmonth,curyear,jzyear
	integer(ink),pointer::ldofs(:)
	real   (irk) djacb,coef,time0,time,a1,b1,coef1,coef2,tp,tp0,tem_water,time_cooling,b,s,z, &
	             tpave,tpele,gap_cooling,eata,watertime,bcooltime,alfa1
    real   (irk) time_eq,time_real,dtime_eq,dtime_real,ratio_eq  ! cj042 20191104 equivalent age    
	real   (irk),allocatable::shape(:)
	integer(ink),allocatable::bymd(:),ymd(:)
	integer (ink)bdate   !温度场开始浇筑时间，一年按360天。若从5月26日开始浇筑，则bdate=4*30+26=146
	
	!allocate(bymd(3),ymd(3))
	
	bdate=0  !265   !115  !249-->for 2003.9.7
	
	DO igroup =1,ngroup
		if(appear(igroup)>0) then
		
			field1=    group(igroup)%fieldid
			nrfields=group(igroup)%nrfields
			ic=0
			do ifield=1,nrfields
				if(field1(ifield:ifield)=='T')then
					ic=1
					exit
				end if
			end do
		
			if(ic==0) goto 1
			matno=group(igroup)%matno
			source_curve=props(matno)%heat%source_curve
			!bcooltime=props(matno)%heat%bcooltime
			index  = group(igroup)%index
			order_int=elkn(index)%el_field(ifield)%order_intrules(2)
			nnode    =elkn(index)%el_field(ifield)%nnode_f
			ngaus=elkn(index)%ggaus(order_int)%ngaus
		
			if(appear_process(igroup,iblks)==1  .and.           &
				appear_process(igroup,iblks-1)==0.and.             &
				iincs==1.and.istep==inc_step)then
				group(igroup)%btime=ttime-ditime*inc_step
				group(igroup)%water_pipe%icwater=0
			endif
		
			time0=group(igroup)%btime   !浇筑时间
			time=ttime-time0            !混凝土龄期
			coef=0.
			!time_cooling=props(matno)%heat%time_cooling
            curmonth=bdate+ttime
			curyear=curmonth/360+1
			curmonth=curmonth-curmonth/360*360
			curmonth=curmonth/30+1      !得到当前总时间所在的月份
			jzmonth=bdate+time0
			jzyear=jzmonth/360+1
			jzmonth=jzmonth-jzmonth/360*360
			jzmonth=jzmonth/30+1        !得到当前组浇筑时间所在的月份		
            
	
			tpave=0.
			DO ielgroup = 1,group(igroup)%nelgroup      !ielgroup
				ielem = group(igroup)%list(ielgroup)
				ldofs =>element(ielem)%field(1)%ldofs_f
				tpele=sum(result_zero(ldofs))/nnode
				tpave=tpave+tpele
				nullify(ldofs)
			end do
			tp=tpave/group(igroup)%nelgroup			
				
			! 三期通水
			if(group(igroup)%water_pipe%pipecooling==3)then	!pipecooling==3		
				if(time.gt.group(igroup)%water_pipe%tb1(3).or.group(igroup)%water_pipe%icwater==3)then  !cj042@126.com 2013.6.24
					tem_water=group(igroup)%water_pipe%tsw1(3)	!十一月份平均江水温度
					if(group(igroup)%water_pipe%icwater==-2)then
					    group(igroup)%water_pipe%icwater=3     !开始三期通水
					    group(igroup)%water_pipe%btwater=ttime-ditime*inc_step		!记录三期通水开始时刻
					    group(igroup)%water_pipe%tp=tp			! 开始通水时混凝土温度
					endif
				endif						
					
				if(group(igroup)%water_pipe%icwater==3)then  !icwater==3
					tp0=group(igroup)%water_pipe%tp
					if(tp<=group(igroup)%water_pipe%taim1(3).or.tem_water>tp.or.time>group(igroup)%water_pipe%te1(3))then	!若混凝土温度降到15度，或水温大于混凝土温度，则停止通水
						group(igroup)%water_pipe%icwater=-3				
						write(chkunit,'(a,5i6,4f12.3)')'三期通水停,ig,jzy,jzm,cury,curm,tp0,tp,tem_water,btwater=',igroup,jzyear,jzmonth,curyear,curmonth,tp0,tp,tem_water,group(igroup)%water_pipe%btwater
					else
						!cj042@126.com  20200115  for pipe gap and pipe length changing
                        eata=8.37*group(igroup)%water_pipe%L_pipe/(4.187*1000*group(igroup)%water_pipe%q1(3))  !8.37*200/(4.187*1000*group(igroup)%q1(2))   !0.3257
						gap_cooling=1.167*sqrt(group(igroup)%water_pipe%gap_1*group(igroup)%water_pipe%gap_2)   !2.0216     
						s=.971+.1485*eata-.0445*eata**2
						b=(2.08-1.174*eata+.256*eata**2)*(props(matno)%heat%alfa(1)/(gap_cooling**2))**s
						watertime=ttime-group(igroup)%water_pipe%btwater   !记录三期通水已经持续时间
						call coef_heat(tp0,tem_water,b,s,source_curve,time,watertime,coef)
						write(chkunit,'(a,5i6,4f12.3)')'三期通水中,ig,jzy,jzm,cury,curm,tp0,tp,tem_water,btwater=',  &
                            igroup,jzyear,jzmonth,curyear,curmonth,tp0,tp,tem_water,group(igroup)%water_pipe%btwater
						goto 20
					endif
				endif  !icwater==3
		
			endif !pipecooling==3	
			
		    ! 二期通水         
			if(group(igroup)%water_pipe%pipecooling>=2.or.group(igroup)%water_pipe%icwater==2)then
				if(time.gt.group(igroup)%water_pipe%tb1(2).or.group(igroup)%water_pipe%icwater==2)then  !cj042@126.com 2013.6.24
					tem_water=group(igroup)%water_pipe%tsw1(2)	!十一月份平均江水温度
				   if(group(igroup)%water_pipe%icwater==-1) then   !二期通水开始时间
					    group(igroup)%water_pipe%tp=tp			! 开始通水时混凝土温度
					    group(igroup)%water_pipe%icwater=2     !开始二期通水
					    group(igroup)%water_pipe%btwater=ttime-ditime*inc_step		!记录二期通水开始时刻
					endif
				endif
		
				if(group(igroup)%water_pipe%icwater==2)then
					tp0=group(igroup)%water_pipe%tp
					if(tp<=group(igroup)%water_pipe%taim1(2).or.tem_water>tp.or.time>group(igroup)%water_pipe%te1(2))then		!若混凝土温度降到8度，或水温大于混凝土温度，或通水时间达到60天，则停止通水
						group(igroup)%water_pipe%icwater=-2				
						write(chkunit,'(a,5i6,4f12.3)')'二期通水停,ig,jzy,jzm,cury,curm,tp0,tp,tem_water,btwater=',  &
                            igroup,jzyear,jzmonth,curyear,curmonth,tp0,tp,tem_water,group(igroup)%water_pipe%btwater
                    else				
						!cj042@126.com  20200115  for pipe gap and pipe length changing
                        eata=8.37*group(igroup)%water_pipe%L_pipe/(4.187*1000*group(igroup)%water_pipe%q1(2))  !8.37*200/(4.187*1000*group(igroup)%q1(2))   !0.3257
						gap_cooling=1.167*sqrt(group(igroup)%water_pipe%gap_1*group(igroup)%water_pipe%gap_2)   !2.0216          
						s=.971+.1485*eata-.0445*eata**2
						b=(2.08-1.174*eata+.256*eata**2)*(props(matno)%heat%alfa(1)/(gap_cooling**2))**s
						watertime=ttime-group(igroup)%water_pipe%btwater   !记录二期通水已经持续时间
						call coef_heat(tp0,tem_water,b,s,source_curve,time,watertime,coef)
						write(chkunit,'(a,5i6,4f12.3)')'二期通水中,ig,jzy,jzm,cury,curm,tp0,tp,tem_water,btwater=', &
                            igroup,jzyear,jzmonth,curyear,curmonth,tp0,tp,tem_water,group(igroup)%water_pipe%btwater
						goto 20
					endif
				endif	
			endif
		
10          continue	
		
		
		    ! 一期通水 
            
            !print *,'group(igroup)%water_pipe%pipecooling=',group(igroup)%water_pipe%pipecooling
            !print *,'group(igroup)%water_pipe%icwater=',group(igroup)%water_pipe%icwater
			if(group(igroup)%water_pipe%pipecooling/=0.and.group(igroup)%water_pipe%icwater/=-1)then
			    if((time-group(igroup)%water_pipe%te1(1))<-.0001.and.time>group(igroup)%water_pipe%tb1(1))then  !time>0.5指浇筑后12小时开始通水
		
				    if(group(igroup)%water_pipe%icwater==0)then
					    tem_water=group(igroup)%water_pipe%tsw1(1)  !cj042 2013.6.27 equiv pipecooling
					    if(tem_water<tp)then
					        group(igroup)%water_pipe%icwater=1
					        !group(igroup)%btwater=group(igroup)%btime+group(igroup)%tb1(1) !记录一期通水开始时刻
					        group(igroup)%water_pipe%btwater=ttime-ditime*inc_step		!记录一期通水开始时刻
					        group(igroup)%water_pipe%tp=tp			! 开始通水时混凝土温度
					    else
		                    call dfact_internal_heat(source_curve,time,coef)
						    write(chkunit,'(a,5i6,4f12.3)')'tem_water>tp,一期通水尚未开始,ig,jzy,jzm,cury,curm,tp0,tp,tem_water,btwater=', &
                                igroup,jzyear,jzmonth,curyear,curmonth,tp0,tp,tem_water,group(igroup)%water_pipe%btwater
					    endif
				    endif
    		
				    if(group(igroup)%water_pipe%icwater==1)then
					    tp0=group(igroup)%water_pipe%tp		
		                water_curve=props(matno)%heat%water_curve
		                !tem_water=tcurves(water_curve)%dfact
		                tem_water=group(igroup)%water_pipe%tsw1(1)	!十一月份平均江水温度
    		            
		                if(tp<=group(igroup)%water_pipe%taim1(1).or.tem_water>tp)then  !已达到目标温度或者水温高于混凝土平均温度
		                    group(igroup)%water_pipe%icwater=-1
		                    call dfact_internal_heat(source_curve,time,coef)
						    write(chkunit,'(a,5i6,4f12.3)')'一期通水停,ig,jzy,jzm,cury,curm,tp0,tp,tem_water,btwater=', &
                                igroup,jzyear,jzmonth,curyear,curmonth,tp0,tp,tem_water,group(igroup)%water_pipe%btwater
		                else
					        write(chkunit,'(a,5i6,4f12.3)')'一期通水中,ig,jzy,jzm,cury,curm,tp0,tp,tem_water,btwater=', &
                                igroup,jzyear,jzmonth,curyear,curmonth,tp0,tp,tem_water,group(igroup)%water_pipe%btwater			
						    !cj042@126.com  20200115  for pipe gap and pipe length changing
                            eata=8.37*group(igroup)%water_pipe%L_pipe/(4.187*1000*group(igroup)%water_pipe%q1(1))  !8.37*200/(4.187*1000*group(igroup)%q1(2))   !0.3257
						    gap_cooling=1.167*sqrt(group(igroup)%water_pipe%gap_1*group(igroup)%water_pipe%gap_2)   !2.0216                                                             
						    s=.971+.1485*eata-.0445*eata**2                                                 
						    b=(2.08-1.174*eata+.256*eata**2)
          if(Bparameter/=0.and.props(matno)%heat%ialfa/=0)then 
          alfa1=xvalue(props(matno)%heat%ialfa)
          else 
          alfa1 = props(matno)%heat%alfa(1)
          endif
                                
                            z=(alfa1/(gap_cooling**2))**s	
                            b=b* z   
					        !b=props(matno)%heat%b 
					        !s=props(matno)%heat%s		
					        watertime=ttime-group(igroup)%water_pipe%btwater   !记录一期通水已经持续时间
					        call coef_heat(tp0,tem_water,b,s,source_curve,time,watertime,coef)   
					    endif
					endif
			    elseif(source_curve/=0)then   !不通水
				    if(group(igroup)%water_pipe%icwater==1)group(igroup)%water_pipe%icwater=-1
				    call dfact_internal_heat(source_curve,time,coef)
			    endif
			elseif(source_curve/=0)then   !不通水(不含冷却水管情况）
				if(group(igroup)%water_pipe%icwater==1)group(igroup)%water_pipe%icwater=-1
                if(ecwpipe==2)then !常规算法
				call dfact_internal_heat(source_curve,time,coef)
                elseif(ecwpipe==3)then !考虑水化反应算法？
		        tpave=0.        ! cj042 20191104 equivalent age
		        DO ielgroup = 1,group(igroup)%nelgroup      !ielgroup
			        ielem = group(igroup)%list(ielgroup)
			        ldofs =>element(ielem)%field(1)%ldofs_f
			        tpele=sum(result_zero(ldofs))/nnode
			        tpave=tpave+tpele
			        nullify(ldofs)
		        end do
		        tp=tpave/group(igroup)%nelgroup	
                group(igroup)%water_pipe%tp=tp
                dtime_real=ditime
                ratio_eq=EXP(1643.0*(1/293.0-1/(tp+273.0)))  !Liu Yongjun 
                dtime_eq=ratio_eq*dtime_real
                time_eq=group(igroup)%water_pipe%time_eq
                time_eq=time_eq+dtime_eq
                time_real=time_real+dtime_real
        
                group(igroup)%water_pipe%dtime_eq=dtime_eq
                group(igroup)%water_pipe%dtime_real=dtime_real
                group(igroup)%water_pipe%time_eq=time_eq
                 group(igroup)%water_pipe%time_real=time_real
         
		        if(group(igroup)%water_pipe%icwater==1)group(igroup)%water_pipe%icwater=-1
                call dfact_internal_heat(source_curve,time_eq,coef)  !20200229
                coef=coef*ratio_eq      !20200229 
                endif
			endif
		
			20 continue
			allocate (shape(nnode))
			DO ielgroup = 1,group(igroup)%nelgroup      !ielgroup
				ielem = group(igroup)%list(ielgroup)
				element(ielem)%field(ifield)%rload=0.0
		
				do ig=1,ngaus               !! ig
					shape=elkn(index)%ggaus(order_int)%shape(:,ig)
					djacb=element(ielem)%egaus(order_int)%djacb(ig)
		
					do inode=1,nnode
						element(ielem)%field(ifield)%rload(inode)            &
							=element(ielem)%field(ifield)%rload(inode)+           &
							djacb*shape(inode)*coef
					end do
				end do     !!ig
			end do         !!ielgroup
			deallocate(shape)
		1  continue
		end if    !!for appear
	END DO             !igroup
	
  END subroutine heat_internal1 !20200221

!===================================================================
subroutine dfact_internal_heat(itcurve,time,dfact) !20200221

character(20)type_curve
real(irk) time,time1,time2,fact1,fact2,dfact,a0sin,asin,wsin,w0sin
real(irk)theta0,expon,halftime,totime   	! cj042 20191104 equivalent age
integer(ink) itcurve,itime,ntime,nstoch_curve

ntime=tcurves(itcurve)%ntime
type_curve=tcurves(itcurve)%type_curve
nstoch_curve=tcurves(itcurve)%nstoch_curve

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
    if(nstoch_curve==0)then
	time1=tcurves(itcurve)%ttime_curve(1)    !! b
	fact1=tcurves(itcurve)%dfact_curve(1)    !! a
     else
     time1=xvalue(tcurves(itcurve)%order_stoch_parameter(1))
     fact1=xvalue(tcurves(itcurve)%order_stoch_parameter(2))
    endif    
	dfact=fact1*time1*exp(fact1*time)
elseif(type_curve=='DABT')  then	!d(f)=a*b/(b+t)**2
    if(nstoch_curve==0)then
	time1=tcurves(itcurve)%ttime_curve(1)    !! a
	fact1=tcurves(itcurve)%dfact_curve(1)    !! b
    else
     time1=xvalue(tcurves(itcurve)%order_stoch_parameter(1))
     fact1=xvalue(tcurves(itcurve)%order_stoch_parameter(2))
    endif    
	dfact=fact1*time1/(fact1+time)**2
elseif(type_curve=='HTG_EQ')  then	!航塘港C35泵送 cj042  20191104
		!T(t_eq)=55*(t_eq^2.185/(0.47+t_eq^2.185))  
    theta0       =   tcurves(itcurve)%dfact_curve(1)  ;
    expon       =   tcurves(itcurve)%dfact_curve(2)  ;
    halftime    =   tcurves(itcurve)%dfact_curve(3)  ;
    totime       =   tcurves(itcurve)%dfact_curve(4)  ;
    if(time<totime)then   !5 hours  5 degree  ! cj042 20191104 equivalent age
            fact1=halftime*expon*time**(expon-1)
            fact2=(halftime+time**expon)**2
            dfact=theta0*fact1/fact2
    else
            dfact=0.
    endif              
    
  !  real(irk)theta0,expon,halftime,totime   	! cj042 20191104 equivalent age
else
	print *, 'no type_curve'
	stop
end if
end subroutine dfact_internal_heat !20200221

subroutine coef_heat(tp,tem_water,b,s,source_curve,time,watertime,coef) !20200221
character(20)type_curve
real   (irk) tp,tem_water,b,s,time,coef,a1,b1,coef1,coef2,watertime
integer(ink) source_curve

	coef1=(tp-tem_water)*(-b*s*watertime**(s-1)*exp(-b*watertime**s))
	type_curve=tcurves(source_curve)%type_curve
        
if(type_curve=='DEXPONENTIAL')  then	!d(f)=a*b*exp(-b*t)
	a1=tcurves(source_curve)%ttime_curve(1)    !! a
	b1=tcurves(source_curve)%dfact_curve(1)    !! b
	coef2=a1*(b1*exp(-b1*time)-b*exp(-b*time))*b1/(b1-b)
elseif(type_curve=='DEXPONENTIAL2')  then	!d(f)=a*b*exp(-b*t)
	a1=tcurves(source_curve)%ttime_curve(1)    !! a
	b1=tcurves(source_curve)%dfact_curve(1)    !! b
	coef2=a1*(b1*exp(-b1*time)-b*exp(-b*time))*b1/(b1-b)
	a1=tcurves(source_curve)%ttime_curve(2)    !! a
	b1=tcurves(source_curve)%dfact_curve(2)    !! b
	coef2=coef2+a1*(b1*exp(-b1*time)-b*exp(-b*time))*b1/(b1-b)
!	write(chkunit,*)'coef2=',coef2
elseif(type_curve=='DABT')  then	!d(f)=a*b/(b+t)**2
	a1=tcurves(source_curve)%ttime_curve(1)    !! a
	b1=tcurves(source_curve)%dfact_curve(1)    !! b
	call dfact_pipe_cool2(time-ditime*.5,coef,a1,b1,b)
	call dfact_pipe_cool2(time+ditime*.5,coef2,a1,b1,b)
	coef2=(coef2-coef)/ditime
else
	print *,'must be DXPONENTIAL or DABT'
	stop
endif
coef=coef1+coef2
end subroutine coef_heat  !20200221
subroutine dfact_pipe_cool2(timex,coef,a1,b1,b) !20200221
real(irk) timex,coef,a1,b1,b,deltat,t0,t1,t1of2,df
integer(ink) nindel,nindelt,i0
real(irk), allocatable::timei(:)

deltat=ditime/10.
nindel=timex/deltat
!write(*,*)'nindel=',nindel
if((timex-nindel*deltat)>.01*deltat)then
	allocate(timei(nindel+2))
	nindelt=nindel+2
else
	allocate(timei(nindel+1))
	nindelt=nindel+1
endif

timei=0.
timei(1)=0.
do i0=1,nindel
	timei(i0+1)=deltat*i0
end do

if(nindelt==nindel+2)timei(nindelt)=timex
coef=0.
do i0=1,nindelt-1
	t0=timei(i0)
	t1=timei(i0+1)
	t1of2=timex-t1-.5*deltat
	df=a1*t1/(b1+t1)-a1*t0/(b1+t0)
	coef=coef+df*exp(-b*t1of2)
end do
if(allocated(timei))deallocate(timei)
end subroutine dfact_pipe_cool2 !20200221

  subroutine assemble_pipe_estif  !20200316
  character(10)fieldid
  integer(ink) ielgroup,iedge,aelem,ndofn,igroup,nrfields, &
               idofn,jdofn,kdofn,ldofn,ifield,ipipe
  integer(ink),pointer::ldofe(:)
  real(irk),pointer::edstif(:,:)
  do ipipe=1,npipe
  nline=pipeinfo(ipipe)%nline
  do ielgroup=1,nline
  edstif=>pipeinfo(ipipe)%edstif(:,:,ielgroup)
  aelem=pipeinfo(ipipe)%aelem(ielgroup)
  ldofe=>pipeinfo(ipipe)%ldofe(:,ielgroup)
  ndofn=size(ldofe)
  igroup=element(aelem)%group
  nrfields=group(igroup)%nrfields
  fieldid=group(igroup)%fieldid
           do ifield=1,nrfields
           if(fieldid(ifield:ifield)=='T')goto 1
           end do
1     do idofn=1,ndofn
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
  end do

  end subroutine assemble_pipe_estif  !20200316
  
  
      subroutine pipe_cool_eload
    
   integer(ink) aelem,ndofn,idofn,ipoin,itotv,ipipe,ielgroup,nline,jdofn
  integer(ink),pointer::ldofe(:),lnods(:)
  real(irk),pointer::edstif(:,:)
  real(irk),allocatable::value(:),eload(:)
        
      do ipipe=1,npipe
  nline=pipeinfo(ipipe)%nline
  do ielgroup=1,nline
  edstif=>pipeinfo(ipipe)%edstif(:,:,ielgroup)
  aelem=pipeinfo(ipipe)%aelem(ielgroup)
  ldofe=>pipeinfo(ipipe)%ldofe(:,ielgroup)
  ndofn=size(ldofe)
       lnods=>element(aelem)%field(1)%lnods_f
       allocate(value(ndofn),eload(ndofn)) 
       do idofn=1,ndofn
       ipoin=lnods(ldofe(idofn))
       itotv=nodfn(1,ipoin)
       value(idofn)=result_zero(itotv)
       end do
 eload=MATMUL(edstif,value)
 if(algo_pipe==4)then
        do idofn=1,ndofn
          jdofn=ldofe(idofn)
          element(aelem)%field(1)%eload(jdofn)=     &
          element(aelem)%field(1)%eload(jdofn)+     &
          eload(idofn)
        end do
  endif
 !write(7,*)'iel=',ielgroup,'eload=',eload
 !write(7,*)'edstif=',edstif,'value=',value
 !
  nullify(ldofe,edstif)
  deallocate(eload,value)
  end do
  end do

    end subroutine pipe_cool_eload


  
    subroutine surface_point_temp_find(jfixvar,corz,temp_point)   !20230402

    real   (irk) corz,temp_point,temp_point1,temp_point2
    real   (irk) coeft,coef
    integer(ink) jfixvar,ntime_gap,nheight,i1,i2,t1,t2,i0,j0

    ntime_gap=temp_surface(jfixvar)%ntime_gap
    nheight  =temp_surface(jfixvar)%nheight
    
        coeft=1.
    if(ttime<=temp_surface(jfixvar)%time(1))then
        t1=1
        t2=2
        coeft=0.
    elseif(ttime>=temp_surface(jfixvar)%time(ntime_gap))then
        t1=ntime_gap-1
        t2=ntime_gap
    else    
        
        do j0=1,ntime_gap-1
        if(ttime>temp_surface(jfixvar)%time(j0).and.ttime<=temp_surface(jfixvar)%time(j0+1))then
            t1=j0
            t2=j0+1
            coeft=(ttime-temp_surface(jfixvar)%time(j0))/(temp_surface(jfixvar)%time(j0+1)-temp_surface(jfixvar)%time(j0))
            goto 20
        endif
        end do
        stop 'surface_point_temp_find'
20      continue
        
     end if
    
    
    coef=1.
    if(corz<=temp_surface(jfixvar)%height(1))then
        i1=1
        i2=2
        coef=0.
    elseif(corz>=temp_surface(jfixvar)%height(nheight))then
        i1=nheight-1
        i2=nheight
    else
        do i0=1,nheight-1
        if(corz>temp_surface(jfixvar)%height(i0).and.corz<=temp_surface(jfixvar)%height(i0+1))then
            i1=i0
            i2=i0+1
            coef=(corz-temp_surface(jfixvar)%height(i0))/(temp_surface(jfixvar)%height(i0+1)-temp_surface(jfixvar)%height(i0))
            goto 10
        endif
        end do
        stop 'surface_point_temp_find'
10    continue       
    endif

    temp_point1=temp_surface(jfixvar)%temp(t1,i1)*(1-coeft)+temp_surface(jfixvar)%temp(t2,i1)*coeft
    temp_point2=temp_surface(jfixvar)%temp(t1,i2)*(1-coeft)+temp_surface(jfixvar)%temp(t2,i2)*coeft
    temp_point = temp_point1*(1-coef)+temp_point2*coef

    end subroutine surface_point_temp_find   !20230402
  
  
!****


    END MODULE temperature
