module   elements

	use yl_diag
	use yl_diag_registry
	use variable_types 
	use arrayutil
	implicit none
 
    integer(ink) ekind
    parameter(ekind=26) !20230910
    logical,save::ele_scan_only=.false.   ! M1-03: set by read_element on a bad record; the rest of .ele is only scanned

    type gauss_global
       character (10) name
       integer(ink) ngaus,nnode
       real(irk),pointer::weigp(:),posgp(:,:),shape(:,:)
       real(irk),pointer::deriv(:,:,:)
    end type gauss_global

    type gauss_element
       real(irk),pointer::gpcod(:,:),djacb(:),cartd(:,:,:)
       real(irk),pointer::bbar(:,:,:),shapwxy(:,:,:)
       real(irk),pointer::pwatr(:),permr(:),satur(:),csmos(:),poros(:),voide(:)
       integer(ink),pointer::iload(:),iload0(:)
       real(irk),pointer::vdval(:,:),vdval0(:,:)
!pwatr, pore pressure; permr, relative permiability; satur, saturation
!poros, porosity; voidg, e at gauss point
    end type gauss_element

    type elekind_field
       integer(ink) nnode_f
       integer(ink) ngvar_f
       integer(ink) order_intrules(2) !indicator of gauss order
       integer(ink) order_time(2)     !indicator the order to time derivative
    end type elekind_field

    type elekind_couple
       integer(ink) order_couple(2)    !indicator the coupling terms in the two fields
       integer(ink) intrule_couple(2)  !indicator the order in list of nr_intrules
       integer(ink) field_couple(2)    !indicator the no. of coupling fields
    end type elekind_couple

    type elekind_lib
       character (10) name
       integer(ink) index,nnode,nevab,ndimn,nrfields,nr_intrules,ncouple
       real(irk),pointer::shapep(:,:)
       real(irk),pointer::shape_sr(:,:,:)
       type(gauss_global)  ,pointer::ggaus(:)
       type(elekind_couple),pointer::couple(:)
       type(elekind_field) ,pointer::el_field(:)
    end type elekind_lib

    type stiff_field
       real(irk),pointer::fstif(:,:),hstar(:,:)
    end type  stiff_field

    type stiff_couple
       real (irk),pointer::qmatx(:,:),qstab(:,:)
    end type  stiff_couple

 
    type element_field
       integer(ink) ngvar_f,icok
       integer(ink),pointer::lnods_f(:),lnods(:) ! lnods for levelset, lnods_f--old point 
	                                              !                     lnods  --new point 
       integer(ink),pointer::ldofs_f(:),icftcontact(:)
       integer(ink),pointer::isatu(:)  !20220409
       real(irk),   pointer::elcod_f(:,:)
       real(irk),   pointer::gpvar0(:,:),sigz(:) !for !ep2010
       real(irk),   pointer::gpvar(:,:),dmatxd(:,:,:)  !20130510
  !20231215_YL
       real(irk),    pointer::bmatx(:,:,:) !20231008
       real(irk),    pointer::gamamax(:),gamamax0(:) !yuanli20230926等效线性化方法 当前历史最大动剪应变，前一步历史最大动剪应变 ！20231008
       real(irk),    pointer::gamamax_ini(:),gamamax_error(:)!yuanli20230926等效线性化方法 前一次迭代动力过程最大动剪应变，最大动剪应变相对误差
       real(irk),pointer::relat_dis_nod0(:,:),relat_dis_nod(:,:),relat_dis_gaus0(:,:),relat_dis_gaus(:,:) !20231007 止水
  !20231215_YL
       !real(irk),   pointer::gpvar_s(:,:)  !对应于土石坝的湿化应力 20220409
       real(irk),   pointer::strain0(:,:) !对icr=2 or icr=3混凝土材料记录应变过程   
       real(irk),   pointer::strain(:,:),kdiag(:)   !20211125
       real(irk),   pointer::vkstrain0(:,:),vkstrain(:,:) !20160630 对icreep=4(burgersx徐变模型，记录开尔文粘性应变）
       real(irk),pointer::gapg0(:),gapg(:) ! contact
       real(irk),pointer::gapn0(:),gapn(:),ntstress(:,:) ! contact
       real(irk),pointer::natural_thickness(:) !contact
	   character(10),pointer::state(:),state0(:),state1(:) !zhao 25/07/22	        ! contact
	   !for creep
	   real(irk),pointer::omega(:,:,:),dsig(:,:)
       real(irk),pointer::stran0(:,:),rr(:,:,:),stran0_s(:,:)
	   !end for creep
       real(irk),pointer::tload(:),eload(:),rload(:)
       real(irk) ep  !考虑可能屈服条件的钢梁的弹性模量 !20211125
       type(stiff_field)khandmc(2)
    end type element_field

    type element_lib
       character(10) name
       integer(ink) index,group,nstre,matno,nrfields,ne_include,jblks,ktotg,icbound ! levelset
       real(irk) neqcy !20231215YL
	   real   (irk) area,minedge,elength ! levelset
       integer(ink),pointer::list_ne_include(:)
       integer(ink),pointer::point_direct(:)
       real(irk),pointer::estif(:,:),mmat(:,:),gstif(:,:) !levelset
       real(irk),pointer::rotation(:,:)
       real(irk),pointer::stres0(:,:),evk(:,:)
!! the following is for Simo & Rifai incompatiable element
	   real(irk),pointer::gmatx(:,:,:),qmatxa(:,:) 
       real(irk),pointer::rh(:),alfa(:),estift(:,:),estifh(:,:),djacb_dd(:)
       real(irk),pointer::alfa_it(:),alfa_first(:),alfa_second(:)
       integer(ink),pointer::indx(:)
!! the following is for goodman element
!! gmatx,estifh,rh for group of DD, represents cartd, estif, djacb(ngaus)
       real(irk),pointer::aera_local(:)
       integer(ink),pointer::ldofs(:)
       type(element_field),pointer::field(:)
       type(gauss_element),pointer::egaus(:)
       type(stiff_couple),pointer::cstif(:)
       integer(ink) icper !20231215YL
       real(irk),pointer::strainx0(:,:) !20231215YL
       
    end type element_lib
    type (elekind_lib),dimension(ekind):: elkn

contains

	 subroutine kinddefine

    integer(ink) lnode,lnidmn,nr_intrules,ngaus,ikind,igaus,ikg,lnodep,inode
    real   (irk) s,t,u
    real(irk),allocatable:: shape(:),posgp(:,:),deriv(:,:),weigp(:)
    real(irk),allocatable:: shapep(:),derivp(:,:),shape_sr(:,:)
    
    call   l2_define(elkn(1))
    call   l3_define(elkn(2))
    call   t3_define(elkn(3))
    call   t6_define(elkn(4))
    call   q4_define(elkn(5))
    call   q8_define(elkn(6))
    call   h4_define(elkn(7))
    call   h10_define(elkn(8))
    call   b8_define(elkn(9))
    call   b20_define(elkn(10))
    call   t6c3_define(elkn(11))
    call   q8c4_define(elkn(12))
    call   h10c4_define(elkn(13))
    call   b20c8_define(elkn(14))
    call   t3c3_define(elkn(15))
    call   q4c4_define(elkn(16))
    call   h4c4_define(elkn(17))
    call   b8c8_define(elkn(18))
    call   l2c2_define(elkn(19))
    call   b2_define(elkn(20))
    call   b2c2_define(elkn(21))
    call   p4_define(elkn(22))
    call   pr6_define(elkn(23))
    call   pr6c6_define(elkn(24))
    call   steel_define(elkn(25)) !steel 2006
    call   thin_film_define(elkn(26)) !thin_film 2023

    do ikind=1,ekind !ikind
       nr_intrules=elkn(ikind)%nr_intrules
       
       if(ikind==15) &
           write(7,*)'ikind=',ikind,'nr_intrules=',nr_intrules
       lnidmn=elkn(ikind)%ndimn
       do ikg=1,nr_intrules !ikg
          ngaus=elkn(ikind)%ggaus(ikg)%ngaus
          lnode=elkn(ikind)%ggaus(ikg)%nnode
          allocate(elkn(ikind)%ggaus(ikg)%weigp(ngaus),             &
                   elkn(ikind)%ggaus(ikg)%shape(lnode,ngaus),       &
                   elkn(ikind)%ggaus(ikg)%posgp(lnidmn,ngaus),      &
                   elkn(ikind)%ggaus(ikg)%deriv(lnidmn,lnode,ngaus))
          
          allocate(posgp(lnidmn,ngaus),weigp(ngaus),shape(lnode),deriv(lnidmn,lnode))

!! for U_P algorithm
          if (ikind>=11.and.ikind<22.and.ikg==1)then
             lnodep=elkn(ikind)%el_field(2)%nnode_f
             allocate(elkn(ikind)%shapep(lnodep,ngaus))
             allocate(shapep(lnodep),derivp(lnidmn,lnodep))
          endif
!! for Simo Rifai element
          if ((ikind==3.or.ikind==5.or.ikind==9.or.ikind==16.or.ikind==18).and.ikg==1)then
             if(ikind==5.or.ikind==16)allocate(elkn(ikind)%shape_sr(3,11,ngaus))
             if(ikind==9.or.ikind==18)allocate(elkn(ikind)%shape_sr(6,30,ngaus))
             if(ikind==5.or.ikind==16)allocate(shape_sr(3,11))
             if(ikind==9.or.ikind==18)allocate(shape_sr(6,30))
             if(ikind==3)allocate(elkn(ikind)%shape_sr(3,9,ngaus))
             if(ikind==3)allocate(shape_sr(3,9))
          endif
     
          call getgauss( lnidmn,lnode,ngaus,posgp,weigp)
          
          elkn(ikind)%ggaus(ikg)%posgp=posgp
          elkn(ikind)%ggaus(ikg)%weigp=weigp
    
          do igaus=1,ngaus !igaus
             t=0.0_irk ; u=0.0_irk   ! M1-03 R17: 1-D kinds never set t/u before shfunc
             s=posgp(1,igaus)
             if(lnidmn.ge.2)t=posgp(2,igaus)
             if(lnidmn.eq.3)u=posgp(3,igaus)   
             
             call shfunc( lnidmn,lnode,s,t,u,shape,deriv)
             
	!		 if(ikind==9)then
	!		 write(7,*)'ikind=',ikind,'ig=',igaus,'s,t,u=',s,t,u
	!		 write(7,*)'deriv='
	!		 do inode=1,8
	!		 write(7,*)deriv(:,inode)
	!		 end do
	!		 endif
			               
          
             elkn(ikind)%ggaus(ikg)%shape(:,igaus)  =shape
             elkn(ikind)%ggaus(ikg)%deriv(:,:,igaus)=deriv

! store the shape function of disp. gauss points on pressure element configration
             if (ikind>=11.and.ikind<22.and.ikg==1)then
                call shfunc( lnidmn,lnodep,s,t,u,shapep,derivp)
                elkn(ikind)%shapep(:,igaus)=shapep
             endif

! for Simo & Rifai element
             if ((ikind==3.or.ikind==5.or.ikind==9.or.ikind==16.or.ikind==18).and.ikg==1) then
                call shfunsr(ikind,s,t,u,shape_sr)
                elkn(ikind)%shape_sr(:,:,igaus)=shape_sr
             endif
          end do !igaus

          deallocate(posgp,weigp,shape,deriv)
          if(ikind>=11.and.ikind<22.and.ikg==1)deallocate(shapep,derivp)
          if((ikind==3.or.ikind==5.or.ikind==9.or.ikind==16.or.ikind==18).and.ikg==1)deallocate(shape_sr)
       end do  !ikg
    end do  !ikind

contains

    subroutine steel_define(b2) !steel 2006
    
    type (elekind_lib):: b2
    
    b2%name='steel'
    b2%index=25
    b2%nnode=2
    b2%ndimn=1 !3
    b2%nrfields=1
    b2%nr_intrules=0
    b2%ncouple=0
    
    allocate(b2%el_field(b2%nrfields))
    
    b2%el_field(1)%nnode_f=2
    b2%el_field(1)%ngvar_f=0
    
    end subroutine steel_define

    subroutine l2_define(l2)
    
    type (elekind_lib):: l2
    
    l2%name='l2'
    l2%index=1
    l2%nnode=2
    l2%ndimn=1
    l2%nrfields=1
    l2%nr_intrules=2
    
    allocate(l2%ggaus(l2%nr_intrules),l2%el_field(l2%nrfields))
    l2%el_field(1)%nnode_f=2
    l2%el_field(1)%ngvar_f=1
    l2%el_field(1)%order_intrules=(/1,1/)
    
    
    l2%ggaus(1)%name='stiff'
    l2%ggaus(1)%ngaus=2
    l2%ggaus(1)%nnode=2
    
    l2%ggaus(2)%name='mass'
    l2%ggaus(2)%ngaus=2
    l2%ggaus(2)%nnode=2
    
    end subroutine l2_define
    
    subroutine l3_define(l3)
    
    type (elekind_lib):: l3
    
    l3%name='l3'
    l3%index=2
    l3%nnode=3
    l3%ndimn=1
    l3%nrfields=1
    l3%nr_intrules=2
    
    allocate(l3%ggaus(l3%nr_intrules),l3%el_field(l3%nrfields))
    l3%el_field(1)%nnode_f=3
    l3%el_field(1)%ngvar_f=1
    l3%el_field(1)%order_intrules=(/1,2/)
    
    
    l3%ggaus(1)%name='stiff'
    l3%ggaus(1)%ngaus=2
    l3%ggaus(1)%nnode=3
    
    l3%ggaus(2)%name='mass'
    l3%ggaus(2)%ngaus=3
    l3%ggaus(2)%nnode=3
    
    end subroutine l3_define
     
    subroutine t3_define(t3)
    
    type (elekind_lib):: t3
    
    t3%name='t3'
    t3%index=3
    t3%nnode=3
    t3%ndimn=2
    t3%nrfields=1
    t3%nr_intrules=2
    
    allocate(t3%ggaus(t3%nr_intrules),t3%el_field(t3%nrfields))
    t3%el_field(1)%nnode_f=3
    t3%el_field(1)%ngvar_f=3
    t3%el_field(1)%order_intrules=(/1,2/)
    
    t3%ggaus(1)%name='stiff'
    t3%ggaus(1)%ngaus=3
    t3%ggaus(1)%nnode=3
    
    t3%ggaus(2)%name='mass'
    t3%ggaus(2)%ngaus=3
    t3%ggaus(2)%nnode=3
    
    end subroutine t3_define
    
    subroutine t6_define(t6)
    
    type (elekind_lib):: t6
    
    t6%name='t6'
    t6%index=4
    t6%nnode=6
    t6%ndimn=2
    t6%nrfields=1
    t6%nr_intrules=2
    
    allocate(t6%ggaus(t6%nr_intrules),t6%el_field(t6%nrfields))
    t6%el_field(1)%nnode_f=6
    t6%el_field(1)%ngvar_f=3
    t6%el_field(1)%order_intrules=(/1,2/)
    
    
    t6%ggaus(1)%name='stiff'
    t6%ggaus(1)%ngaus=3
    t6%ggaus(1)%nnode=6
    
    t6%ggaus(2)%name='mass'
    t6%ggaus(2)%ngaus=6
    t6%ggaus(2)%nnode=6
    
    end subroutine t6_define
    
    subroutine q4_define(q4)
    
    type (elekind_lib):: q4
    
    q4%name='q4'
    q4%index=5
    q4%nnode=4
    q4%ndimn=2
    q4%nrfields=1
    q4%nr_intrules=2
    
    allocate(q4%ggaus(q4%nr_intrules),q4%el_field(q4%nrfields))
    q4%el_field(1)%nnode_f=4
    q4%el_field(1)%ngvar_f=3
    !q4%el_field(1)%order_intrules=(/1,2/)
    q4%el_field(1)%order_intrules=(/1,1/) !20060602  2006NS
    
    q4%ggaus(1)%name='stiff'
    q4%ggaus(1)%ngaus=4
    q4%ggaus(1)%nnode=4 
    
    q4%ggaus(2)%name='mass'
    q4%ggaus(2)%ngaus=16
    q4%ggaus(2)%nnode=4
    
    end subroutine q4_define
    
    subroutine q8_define(q8)
    type (elekind_lib):: q8
    
    q8%name='q8'
    q8%index=6
    q8%nnode=8
    q8%ndimn=2
    q8%nrfields=1
    q8%nr_intrules=2
    
    allocate(q8%ggaus(q8%nr_intrules),q8%el_field(q8%nrfields))
    q8%el_field(1)%nnode_f=8
    q8%el_field(1)%ngvar_f=3
    q8%el_field(1)%order_intrules=(/1,2/)
    
    
    q8%ggaus(1)%name='stiff'
    q8%ggaus(1)%ngaus=4
    q8%ggaus(1)%nnode=8
    
    q8%ggaus(2)%name='mass'
    q8%ggaus(2)%ngaus=16
    q8%ggaus(2)%nnode=8
    
    end subroutine q8_define
    
    subroutine h4_define(h4)
    
    type (elekind_lib):: h4
    
    h4%name='h4'
    h4%index=7
    h4%nnode=4
    h4%ndimn=3
    h4%nrfields=1
    h4%nr_intrules=2
    
    allocate(h4%ggaus(h4%nr_intrules),h4%el_field(h4%nrfields))
    h4%el_field(1)%nnode_f=4
    h4%el_field(1)%ngvar_f=3
    h4%el_field(1)%order_intrules=(/1,2/)
    
    h4%ggaus(1)%name='stiff'
    h4%ggaus(1)%ngaus=1
    h4%ggaus(1)%nnode=4
    
    h4%ggaus(2)%name='mass'
    h4%ggaus(2)%ngaus=4
    h4%ggaus(2)%nnode=4
    
    end subroutine h4_define
    
    subroutine h10_define(h10)
    
    type (elekind_lib):: h10
    
    h10%name='h10'
    h10%index=8
    h10%nnode=10
    h10%ndimn=3
    h10%nrfields=1
    h10%nr_intrules=2
    
    allocate(h10%ggaus(h10%nr_intrules),h10%el_field(h10%nrfields))
    h10%el_field(1)%nnode_f=10
    h10%el_field(1)%ngvar_f=3
    h10%el_field(1)%order_intrules=(/1,2/)
    
    h10%ggaus(1)%name='stiff'
    h10%ggaus(1)%ngaus=4
    h10%ggaus(1)%nnode=10
    
    h10%ggaus(2)%name='mass'
    h10%ggaus(2)%ngaus=5
    h10%ggaus(2)%nnode=10
    
    end subroutine h10_define
    
    subroutine b8_define(b8)
    
    type (elekind_lib):: b8
    
    b8%name='b8'
    b8%index=9
    b8%nnode=8
    b8%ndimn=3
    b8%nrfields=1
    b8%nr_intrules=2
    
    allocate(b8%ggaus(b8%nr_intrules),b8%el_field(b8%nrfields))
    b8%el_field(1)%nnode_f=8
    b8%el_field(1)%ngvar_f=3
    b8%el_field(1)%order_intrules=(/1,2/)
    
    
    b8%ggaus(1)%name='stiff'
    b8%ggaus(1)%ngaus=8
    b8%ggaus(1)%nnode=8
    
    b8%ggaus(2)%name='mass'
    b8%ggaus(2)%ngaus=8
    b8%ggaus(2)%nnode=8
    
    end subroutine b8_define
    
    subroutine b20_define(b20)
    
    type (elekind_lib):: b20
    
    b20%name='b20'
    b20%index=10
    b20%nnode=20
    b20%ndimn=3
    b20%nrfields=1
    b20%nr_intrules=2
    
    allocate(b20%ggaus(b20%nr_intrules),b20%el_field(b20%nrfields))
    b20%el_field(1)%nnode_f=20
    b20%el_field(1)%ngvar_f=3
    b20%el_field(1)%order_intrules=(/1,2/)
    
    
    b20%ggaus(1)%name='stiff'
    b20%ggaus(1)%ngaus=8
    b20%ggaus(1)%nnode=20
    
    b20%ggaus(2)%name='mass'
    b20%ggaus(2)%ngaus=27
    b20%ggaus(2)%nnode=20
    
    end subroutine b20_define
    
    subroutine t6c3_define(t6c3)
    
    type (elekind_lib):: t6c3
    
    t6c3%name='t6c3'
    t6c3%index=11
    t6c3%nnode=6
    t6c3%ndimn=2
    t6c3%nrfields=2
    t6c3%nr_intrules=4
    t6c3%ncouple=1
    
    allocate(t6c3%couple(t6c3%ncouple))
    allocate(t6c3%ggaus(elkn(11)%nr_intrules),t6c3%el_field(t6c3%nrfields))
    
    t6c3%el_field(1)%nnode_f=6
    t6c3%el_field(1)%ngvar_f=3
    t6c3%el_field(1)%order_intrules=(/1,2/)
    
    t6c3%el_field(2)%nnode_f=3
    t6c3%el_field(2)%ngvar_f=0
    t6c3%el_field(2)%order_intrules=(/3,4/)
    
    
    t6c3%couple(1)%intrule_couple=(/1,4/)
    t6c3%couple(1)%field_couple=(/1,2/)
    
    
    t6c3%ggaus(1)%name='stiff'
    t6c3%ggaus(1)%ngaus=3
    t6c3%ggaus(1)%nnode=6
    t6c3%ggaus(2)%name='mass'
    t6c3%ggaus(2)%ngaus=6
    t6c3%ggaus(2)%nnode=6
    t6c3%ggaus(3)%name='hmatr'
    t6c3%ggaus(3)%ngaus=1
    t6c3%ggaus(3)%nnode=3
    t6c3%ggaus(4)%name='smatr'
    t6c3%ggaus(4)%ngaus=3
    t6c3%ggaus(4)%nnode=3
    
    end subroutine t6c3_define
    
    subroutine q8c4_define(q8c4)
    
    type (elekind_lib):: q8c4
    
    q8c4%name='q8c4'
    q8c4%index=12
    q8c4%nnode=8
    q8c4%ndimn=2
    q8c4%nrfields=2
    q8c4%nr_intrules=4
    q8c4%ncouple=1
    
    allocate(q8c4%couple(q8c4%ncouple))
    allocate(q8c4%ggaus(elkn(12)%nr_intrules),q8c4%el_field(q8c4%nrfields))
    
    q8c4%el_field(1)%nnode_f=8
    q8c4%el_field(1)%ngvar_f=3
    q8c4%el_field(1)%order_intrules=(/1,2/)
    
    q8c4%el_field(2)%nnode_f=4
    q8c4%el_field(2)%ngvar_f=0
    q8c4%el_field(2)%order_intrules=(/3,4/)
    
    
    q8c4%couple(1)%intrule_couple=(/1,4/)
    q8c4%couple(1)%field_couple=(/1,2/)
    
    q8c4%ggaus(1)%name='stiff'
    q8c4%ggaus(1)%ngaus=4
    q8c4%ggaus(1)%nnode=8
    q8c4%ggaus(2)%name='mass'
    q8c4%ggaus(2)%ngaus=16
    q8c4%ggaus(2)%nnode=8
    q8c4%ggaus(3)%name='hmatr'
    q8c4%ggaus(3)%ngaus=4
    q8c4%ggaus(3)%nnode=4
    q8c4%ggaus(4)%name='smatr'
    q8c4%ggaus(4)%ngaus=4
    q8c4%ggaus(4)%nnode=4
    
    end subroutine q8c4_define
    
    subroutine h10c4_define(h10c4)
    
    type (elekind_lib):: h10c4
    h10c4%name='h10c4'
    h10c4%index=13
    h10c4%nnode=10
    h10c4%ndimn=3
    h10c4%nrfields=2
    h10c4%nr_intrules=4
    h10c4%ncouple=1
    
    allocate(h10c4%couple(h10c4%ncouple))
    allocate(h10c4%ggaus(elkn(13)%nr_intrules),h10c4%el_field(h10c4%nrfields))
    
    h10c4%el_field(1)%nnode_f=10
    h10c4%el_field(1)%ngvar_f=3
    h10c4%el_field(1)%order_intrules=(/1,2/)
    
    h10c4%el_field(2)%nnode_f=4
    h10c4%el_field(2)%ngvar_f=0
    h10c4%el_field(2)%order_intrules=(/3,4/)
    
    h10c4%couple(1)%intrule_couple=(/1,4/)
    h10c4%couple(1)%field_couple=(/1,2/)
    
    h10c4%ggaus(1)%name='stiff'
    h10c4%ggaus(1)%ngaus=4
    h10c4%ggaus(1)%nnode=10
    h10c4%ggaus(2)%name='mass'
    h10c4%ggaus(2)%ngaus=5
    h10c4%ggaus(2)%nnode=10
    h10c4%ggaus(3)%name='hmatr'
    h10c4%ggaus(3)%ngaus=1
    h10c4%ggaus(3)%nnode=4
    h10c4%ggaus(4)%name='smatr'
    h10c4%ggaus(4)%ngaus=4
    h10c4%ggaus(4)%nnode=4
    
    end subroutine h10c4_define
    
    subroutine b20c8_define(b20c8)
    
    type (elekind_lib):: b20c8
    
    b20c8%name='b20c8'
    b20c8%index=14
    b20c8%nnode=20
    b20c8%ndimn=3
    b20c8%nrfields=2
    b20c8%nr_intrules=4
    b20c8%ncouple=1
    
    allocate(b20c8%couple(b20c8%ncouple))
    allocate(b20c8%ggaus(elkn(14)%nr_intrules),b20c8%el_field(b20c8%nrfields))
    
    b20c8%el_field(1)%nnode_f=20
    b20c8%el_field(1)%ngvar_f=3
    b20c8%el_field(1)%order_intrules=(/1,2/)
    
    b20c8%el_field(2)%nnode_f=8
    b20c8%el_field(2)%ngvar_f=0
    b20c8%el_field(2)%order_intrules=(/3,4/)
     
    b20c8%couple(1)%intrule_couple=(/1,4/)
    b20c8%couple(1)%field_couple=(/1,2/)
      
    b20c8%ggaus(1)%name='stiff'
    b20c8%ggaus(1)%ngaus=8
    b20c8%ggaus(1)%nnode=20
    b20c8%ggaus(2)%name='mass'
    b20c8%ggaus(2)%ngaus=27
    b20c8%ggaus(2)%nnode=20
    b20c8%ggaus(3)%name='hmatr'
    b20c8%ggaus(3)%ngaus=8
    b20c8%ggaus(3)%nnode=8
    b20c8%ggaus(4)%name='smatr'
    b20c8%ggaus(4)%ngaus=8
    b20c8%ggaus(4)%nnode=8
    
    end subroutine b20c8_define
    
    subroutine t3c3_define(t3c3)
    
    type (elekind_lib):: t3c3
    
    t3c3%name='t3c3'
    t3c3%index=15
    t3c3%nnode=3
    t3c3%ndimn=2
    t3c3%nrfields=2
    t3c3%nr_intrules=4 !20220707
    !t3c3%nr_intrules=1
    t3c3%ncouple=1
    
    allocate(t3c3%couple(t3c3%ncouple))
    allocate(t3c3%ggaus(elkn(15)%nr_intrules),t3c3%el_field(t3c3%nrfields))
    
    t3c3%el_field(1)%nnode_f=3
    t3c3%el_field(1)%ngvar_f=3
    t3c3%el_field(1)%order_intrules=(/1,2/) !20220707
    !t3c3%el_field(1)%order_intrules=(/1,1/)
    
    
    t3c3%el_field(2)%nnode_f=3
    t3c3%el_field(2)%ngvar_f=0
    t3c3%el_field(2)%order_intrules=(/3,4/) !20220707
    !t3c3%el_field(2)%order_intrules=(/1,1/)
    
    t3c3%couple(1)%intrule_couple=(/1,4/) !20220707
    !t3c3%couple(1)%intrule_couple=(/1,1/)
    
    t3c3%couple(1)%field_couple=(/1,2/)
    
    t3c3%ggaus(1)%name='stiff'
    t3c3%ggaus(1)%ngaus=1
    t3c3%ggaus(1)%nnode=3
    t3c3%ggaus(2)%name='mass'
    !t3c3%ggaus(2)%ngaus=1
    t3c3%ggaus(2)%ngaus=3
    t3c3%ggaus(2)%nnode=3
    t3c3%ggaus(3)%name='hmatr'
    t3c3%ggaus(3)%ngaus=1
    t3c3%ggaus(3)%nnode=3
    t3c3%ggaus(4)%name='smatr'
    t3c3%ggaus(4)%ngaus=1
    t3c3%ggaus(4)%nnode=3
    
    end subroutine t3c3_define
    
    subroutine q4c4_define(q4c4)
    
    type (elekind_lib):: q4c4
    
    q4c4%name='q4c4'
    q4c4%index=16
    q4c4%nnode=4
    q4c4%ndimn=2
    q4c4%nrfields=2
    q4c4%nr_intrules=4
    q4c4%ncouple=1
    
    allocate(q4c4%couple(q4c4%ncouple))
    allocate(q4c4%ggaus(elkn(16)%nr_intrules),q4c4%el_field(q4c4%nrfields))
    
    q4c4%el_field(1)%nnode_f=4
    q4c4%el_field(1)%ngvar_f=3
    q4c4%el_field(1)%order_intrules=(/1,2/)
    
    q4c4%el_field(2)%nnode_f=4
    q4c4%el_field(2)%ngvar_f=0
    q4c4%el_field(2)%order_intrules=(/3,4/)

    q4c4%couple(1)%intrule_couple=(/1,4/)
    q4c4%couple(1)%field_couple=(/1,2/)
    
    q4c4%ggaus(1)%name='stiff'
    q4c4%ggaus(1)%ngaus=4
    q4c4%ggaus(1)%nnode=4
    q4c4%ggaus(2)%name='mass'
    q4c4%ggaus(2)%ngaus=4
    q4c4%ggaus(2)%nnode=4
    q4c4%ggaus(3)%name='hmatr'
    q4c4%ggaus(3)%ngaus=4
    q4c4%ggaus(3)%nnode=4
    q4c4%ggaus(4)%name='smatr'
    q4c4%ggaus(4)%ngaus=4
    q4c4%ggaus(4)%nnode=4
    
    end subroutine q4c4_define
    
    subroutine h4c4_define(h4c4)
    
    type (elekind_lib):: h4c4
    
    h4c4%name='h4c4'
    h4c4%index=17
    h4c4%nnode=4
    h4c4%ndimn=3
    h4c4%nrfields=2
    h4c4%nr_intrules=4
    h4c4%ncouple=1
    
    allocate(h4c4%couple(h4c4%ncouple))
    allocate(h4c4%ggaus(elkn(17)%nr_intrules),h4c4%el_field(h4c4%nrfields))
    
    h4c4%el_field(1)%nnode_f=4
    h4c4%el_field(1)%ngvar_f=3
    h4c4%el_field(1)%order_intrules=(/1,2/)
    
    h4c4%el_field(2)%nnode_f=4
    h4c4%el_field(2)%ngvar_f=0
    h4c4%el_field(2)%order_intrules=(/3,4/)
    
    
    h4c4%couple(1)%intrule_couple=(/1,4/)
    h4c4%couple(1)%field_couple=(/1,2/)
    
    h4c4%ggaus(1)%name='stiff'
    h4c4%ggaus(1)%ngaus=1
    h4c4%ggaus(1)%nnode=4
    h4c4%ggaus(2)%name='mass'
    h4c4%ggaus(2)%ngaus=4
    h4c4%ggaus(2)%nnode=4
    h4c4%ggaus(3)%name='hmatr'
    h4c4%ggaus(3)%ngaus=1
    h4c4%ggaus(3)%nnode=4
    h4c4%ggaus(4)%name='smatr'
    h4c4%ggaus(4)%ngaus=1
    h4c4%ggaus(4)%nnode=4
    
    end subroutine h4c4_define
    
    subroutine b8c8_define(b8c8)
    
    type (elekind_lib):: b8c8
    
    b8c8%name='b8c8'
    b8c8%index=18
    b8c8%nnode=8
    b8c8%ndimn=3
    b8c8%nrfields=2
    b8c8%nr_intrules=4
    b8c8%ncouple=1
    
    allocate(b8c8%couple(b8c8%ncouple))
    allocate(b8c8%ggaus(elkn(18)%nr_intrules),b8c8%el_field(b8c8%nrfields))
    
    b8c8%el_field(1)%nnode_f=8
    b8c8%el_field(1)%ngvar_f=3
    b8c8%el_field(1)%order_intrules=(/1,2/)
    
    b8c8%el_field(2)%nnode_f=8
    b8c8%el_field(2)%ngvar_f=0
    b8c8%el_field(2)%order_intrules=(/3,4/)
    
    
    b8c8%couple(1)%intrule_couple=(/1,4/)
    b8c8%couple(1)%field_couple=(/1,2/)
      
    b8c8%ggaus(1)%name='stiff'
    b8c8%ggaus(1)%ngaus=8
    b8c8%ggaus(1)%nnode=8
    b8c8%ggaus(2)%name='mass'
    b8c8%ggaus(2)%ngaus=8
    b8c8%ggaus(2)%nnode=8
    b8c8%ggaus(3)%name='hmatr'
    b8c8%ggaus(3)%ngaus=8
    b8c8%ggaus(3)%nnode=8
    b8c8%ggaus(4)%name='smatr'
    b8c8%ggaus(4)%ngaus=8
    b8c8%ggaus(4)%nnode=8
    
    end subroutine b8c8_define
    
    subroutine l2c2_define(l2c2)
    
    type (elekind_lib):: l2c2
    
    l2c2%name='l2c2'
    l2c2%index=19
    l2c2%nnode=2
    l2c2%ndimn=1
    l2c2%nrfields=2
    l2c2%nr_intrules=2
    l2c2%ncouple=0
    
    allocate(l2c2%ggaus(elkn(18)%nr_intrules),l2c2%el_field(l2c2%nrfields))
    
    l2c2%el_field(1)%nnode_f=2
    l2c2%el_field(1)%ngvar_f=1
    l2c2%el_field(1)%order_intrules=(/1,2/)
    
    l2c2%el_field(2)%nnode_f=2
    l2c2%el_field(2)%ngvar_f=0
    l2c2%el_field(2)%order_intrules=(/1,2/)
    
    l2c2%ggaus(1)%name='stiff'
    l2c2%ggaus(1)%ngaus=2
    l2c2%ggaus(1)%nnode=2
    l2c2%ggaus(2)%name='mass'
    l2c2%ggaus(2)%ngaus=2
    l2c2%ggaus(2)%nnode=2
    end subroutine l2c2_define
            
    subroutine b2_define(b2)
    
    type (elekind_lib):: b2
    
    b2%name='b2'
    b2%index=20
    b2%nnode=2
    b2%ndimn=1
    b2%nrfields=1
    b2%nr_intrules=0
    b2%ncouple=0
    
    allocate(b2%el_field(b2%nrfields))
    
    b2%el_field(1)%nnode_f=2
    b2%el_field(1)%ngvar_f=0
    
    end subroutine b2_define
    
    subroutine b2c2_define(b2c2)
    
    type (elekind_lib):: b2c2 
    
    b2c2%name='b2c2'
    b2c2%index=21
    b2c2%nnode=2
    b2c2%ndimn=1
    b2c2%nrfields=2
    b2c2%nr_intrules=0
    b2c2%ncouple=0
    
    allocate(b2c2%el_field(b2c2%nrfields))
    b2c2%el_field(1)%nnode_f=2
    b2c2%el_field(1)%ngvar_f=0
    
    b2c2%el_field(2)%nnode_f=2
    b2c2%el_field(2)%ngvar_f=0
    
    end subroutine b2c2_define
    
    subroutine p4_define(p4)
    
    type (elekind_lib):: p4
    
    p4%name='p4'
    p4%index=22
    p4%nnode=4
    p4%ndimn=2
    p4%nrfields=1
    p4%nr_intrules=1
    
    allocate(p4%ggaus(p4%nr_intrules),p4%el_field(p4%nrfields))
    p4%el_field(1)%nnode_f=4
    p4%el_field(1)%ngvar_f=3
    p4%el_field(1)%order_intrules=(/1,1/)
    
    
    p4%ggaus(1)%name='stiff/mass'
    p4%ggaus(1)%ngaus=16
    p4%ggaus(1)%nnode=4
    
    !p4%ggaus(2)%name='mass'
    !p4%ggaus(2)%ngaus=4
    !p4%ggaus(2)%nnode=4
    
    end subroutine p4_define
    
        subroutine thin_film_define(thin_film)  !20230910
    
    type (elekind_lib):: thin_film
    
    thin_film%name='thin_film'
    thin_film%index=22
    thin_film%nnode=4
    thin_film%ndimn=2
    thin_film%nrfields=1
    thin_film%nr_intrules=1
    
    allocate(thin_film%ggaus(thin_film%nr_intrules),thin_film%el_field(thin_film%nrfields))
    thin_film%el_field(1)%nnode_f=4
    thin_film%el_field(1)%ngvar_f=3
    thin_film%el_field(1)%order_intrules=(/1,1/)
    
    
    thin_film%ggaus(1)%name='stiff/mass'
    thin_film%ggaus(1)%ngaus=4
    thin_film%ggaus(1)%nnode=4
    
    
    end subroutine thin_film_define !20230910

    
    subroutine pr6_define(pr6)
    
    type (elekind_lib):: pr6
    
    pr6%name='pr6'
    pr6%index=23
    pr6%nnode=6
    pr6%ndimn=3
    pr6%nrfields=1
    pr6%nr_intrules=2
    
    allocate(pr6%ggaus(pr6%nr_intrules),pr6%el_field(pr6%nrfields))
    pr6%el_field(1)%nnode_f=6
    pr6%el_field(1)%ngvar_f=3
    pr6%el_field(1)%order_intrules=(/1,2/)
      
    pr6%ggaus(1)%name='stiff'
    pr6%ggaus(1)%ngaus=6
    pr6%ggaus(1)%nnode=6
    
    pr6%ggaus(2)%name='mass'
    pr6%ggaus(2)%ngaus=6
    pr6%ggaus(2)%nnode=6
    
    end subroutine pr6_define
     
    subroutine pr6c6_define(pr6c6)
    
    type (elekind_lib):: pr6c6
    
    pr6c6%name='pr6c6'
    pr6c6%index=24
    pr6c6%nnode=6
    pr6c6%ndimn=3
    pr6c6%nrfields=2
    pr6c6%nr_intrules=4
    pr6c6%ncouple=1
    
    allocate(pr6c6%couple(pr6c6%ncouple))
    allocate(pr6c6%ggaus(elkn(24)%nr_intrules),pr6c6%el_field(pr6c6%nrfields))
    
    pr6c6%el_field(1)%nnode_f=6
    pr6c6%el_field(1)%ngvar_f=3
    pr6c6%el_field(1)%order_intrules=(/1,2/)
    
    pr6c6%el_field(2)%nnode_f=6
    pr6c6%el_field(2)%ngvar_f=0
    pr6c6%el_field(2)%order_intrules=(/3,4/)
    
    
    pr6c6%couple(1)%intrule_couple=(/1,4/)
    pr6c6%couple(1)%field_couple=(/1,2/)
        
    pr6c6%ggaus(1)%name='stiff'
    pr6c6%ggaus(1)%ngaus=6
    pr6c6%ggaus(1)%nnode=6
    pr6c6%ggaus(2)%name='mass'
    pr6c6%ggaus(2)%ngaus=6
    pr6c6%ggaus(2)%nnode=6
    pr6c6%ggaus(3)%name='hmatr'
    pr6c6%ggaus(3)%ngaus=6
    pr6c6%ggaus(3)%nnode=6
    pr6c6%ggaus(4)%name='smatr'
    pr6c6%ggaus(4)%ngaus=6
    pr6c6%ggaus(4)%nnode=6
    
    end subroutine pr6c6_define

    end subroutine kinddefine   !end kind define

    subroutine read_element(ielknind,igroup,name,matno,nstre,nelem,ielem,coord,iunit,element,   &
    mdof,ndimn,special,elcod_local,group_inf,src,point_direct)

    character(10) name,nameg,special
    integer(ink)ielknind,igroup,matno,ielem,nelem,nnode,ngaus,nnode_f,i0,in,ikg,ig,id,         &
    nr_intrules,iunit,ndimn,nrfields,lndimn,group_inf,ifield,nevab,nstre,aevab,    &
    inode,idimn,mdof(:),ii,src,dindex,nnode_dd,point_direct(2)
    real(irk)   djacb,weigp,elcod_local,s,t,djacb0,u,xyzmax
    real(irk),  dimension(:,:)::coord
    integer(ink),allocatable::lnods(:)

    real(irk),allocatable::shape(:),deriv(:,:),cartd(:,:),elcod(:,:),deriv_inf(:,:),posgp(:),  &
    xyz0(:),xyzg(:,:),elcod_dd(:,:),xjaci(:,:)
    real(irk),allocatable::shape_sr(:,:),gmatx(:,:),a3(:),estift(:,:),estifh(:,:),             &
    gmatx_g(:,:,:),bmatx(:,:),estifhit(:,:),f0(:,:)
    real(irk),allocatable::n1i(:,:),n2i(:,:),n3i(:,:),bbar(:,:),shapwxy(:,:),dershap(:,:,:)

    type(element_lib)::element(nelem) !why 


    nnode=elkn(ielknind)%nnode
    lndimn=elkn(ielknind)%ndimn
    nevab=0
    nrfields=elkn(ielknind)%nrfields
    do in=1,nrfields
       nnode_f=elkn(ielknind)%el_field(in)%nnode_f
       nevab=nevab+nnode_f*mdof(in)
    end do

    nr_intrules=elkn(ielknind)%nr_intrules
    element(ielem)%group=igroup
    element(ielem)%matno=matno

    allocate(lnods(nnode),elcod(ndimn,nnode))
    !read(iunit,*)i0,ii,lnods(1:nnode)
   read(iunit,*,iostat=yl_ios,iomsg=yl_msg)i0,lnods(1:nnode)
   call diag_check_read(yl_ios,yl_msg,RD_ELE_read_element_element_connectivity,ielem)
   ! M1-03: connectivity must refer to existing nodes; element id must equal record order (old code ignored i0)
   do in=1,nnode
      call diag_ref(RD_ELE_read_element_element_connectivity,ielem,'lnods',int(lnods(in),i8),1_i8,int(size(coord,2),i8))
   end do
   if(i0/=ielem)then
      if(i0>=1.and.i0<ielem)then
         call diag_dup(RD_ELE_read_element_element_connectivity,ielem,'i0',int(i0,i8))
      else
         call diag_range(RD_ELE_read_element_element_connectivity,ielem,'i0',int(i0,i8),int(ielem,i8),int(ielem,i8))
      endif
   endif
   if(any(lnods<1.or.lnods>size(coord,2)))ele_scan_only=.true.
   if(ele_scan_only)return   ! never index coord with a bad node; global_data flushes after the groups
    do in=1,nnode
       elcod(:,in)=coord(:,lnods(in))
    end do
    if (elcod_local/=0.) call normal_local_inc(ndimn,nnode,elcod,elcod_local)
 !if (elcod_local/=0.) write(7,*)'ielem=',ielem,'elcod=',elcod(2,:)


    element(ielem)%nstre=nstre
    element(ielem)%name=name
    element(ielem)%nrfields=nrfields
    element(ielem)%index=ielknind

    allocate(element(ielem)%field(nrfields))
    allocate(element(ielem)%ldofs(nevab))
    if (nr_intrules/=0)allocate(element(ielem)%egaus(nr_intrules))

    if (nnode==2.or.ielknind==22.or.ielknind==26)allocate(element(ielem)%rotation(ndimn,ndimn))  !20230910

    if  ((nnode==2.and.ielknind/=25).or.ielknind==22.or.ielknind==26)then    !20230910
        
       allocate(a3(ndimn))
       
       if(ielknind==22.or.ielknind==26)then  !20230910
       call normal_local_plate(ielknind,ndimn,elcod,a3)
       call direct_p4(ndimn,a3,element(ielem)%rotation,point_direct,coord)  
       endif
       
       if  (nnode==2) then !20200210
       djacb =sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))
       a3(:)=(elcod(:,2)-elcod(:,1))/djacb
       call direct_beam(ndimn,a3,element(ielem)%rotation,point_direct,coord)
       endif
       
       do inode=1,nnode
          do idimn=1,ndimn
             elcod(idimn,inode)=element(ielem)%rotation(idimn,:).d.coord(:,lnods(inode))
          end do
       end do
       deallocate(a3)
    endif


    ! for Simo & Rifai element

    if  ((ielknind==3.or.ielknind==5.or.ielknind==9.or.ielknind==16.or.ielknind==18).and.special(1:1)=='B')then

       if  (ndimn==2) then

          if (special(2:2)=='A') aevab=2
          if (special(2:2)=='B') aevab=4
          if (special(2:2)=='C') aevab=7
          if (special(2:2)=='D') aevab=11

          if (special(2:2)=='B'.and.ielknind==3) aevab=6
          if (special(2:2)=='C'.and.ielknind==3) aevab=9

       else if(ndimn==3) then

          if (special(2:2)=='A') aevab=3
          if (special(2:2)=='B') aevab=9
          if (special(2:2)=='C') aevab=24
          if (special(2:2)=='D') aevab=30

       endif

       ngaus=elkn(ielknind)%ggaus(1)%ngaus
       allocate(gmatx(nstre,aevab),shape_sr(3*(ndimn-1),aevab))
       allocate(element(ielem)%gmatx(nstre,aevab,ngaus))

    endif

    if  (special(1:1)=='D')then

       if (ielknind==3)nnode_dd=6
       if (ielknind==5)nnode_dd=8
       if (ielknind==9)nnode_dd=20
       ngaus=elkn(ielknind)%ggaus(1)%ngaus
       allocate(gmatx(ndimn,nnode_dd))
       allocate(element(ielem)%gmatx(ndimn,nnode_dd,ngaus), &
       element(ielem)%estifh(ndimn*nnode_dd,ndimn*nnode_dd), &
       element(ielem)%djacb_dd(ngaus))
    endif

    if  (ielknind==22.and.special(1:1)=='B') then

       ngaus=elkn(ielknind)%ggaus(1)%ngaus
       allocate(gmatx(2,4),shape_sr(2,4),estift(4,12),estifh(4,4),bmatx(2,12))
       allocate(element(ielem)%egaus(1)%bbar(2,12,ngaus),gmatx_g(2,4,ngaus))
       allocate(estifhit(4,12))

    endif

    if  (ielknind==22.and.(special(1:1)=='C'.or.special(1:1)=='S')) then
       ngaus=elkn(ielknind)%ggaus(1)%ngaus
       allocate(element(ielem)%egaus(1)%bbar(3,12,ngaus),element(ielem)%egaus(1)%shapwxy(3,4,ngaus),  &
       bbar(3,12),n1i(3,4),n2i(3,4),n3i(3,4),shapwxy(3,4),dershap(2,4,3))
    endif
    ! end for Simo & Rifai element

    do ifield=1,nrfields !ifield

       nnode=elkn(ielknind)%el_field(ifield)%nnode_f
       nevab=nnode*mdof(ifield)

       allocate(element(ielem)%field(ifield)%lnods_f(nnode))
       allocate(element(ielem)%field(ifield)%ldofs_f(nevab))
       allocate(element(ielem)%field(ifield)%elcod_f(ndimn,nnode))

       element(ielem)%field(ifield)%lnods_f=lnods(1:nnode)

       element(ielem)%field(ifield)%elcod_f(:,1:nnode)=elcod(:,1:nnode)

    end do !ifield



    if  (ielknind/=20.and.ielknind/=21)then  !!new
       !if(ielknind==22.and.special(1:1)=='S') goto 11

       do ikg=1,nr_intrules     !!!ikg

          ngaus=elkn(ielknind)%ggaus(ikg)%ngaus
          nnode=elkn(ielknind)%ggaus(ikg)%nnode
          nameg=elkn(ielknind)%ggaus(ikg)%name

          allocate(shape(nnode),deriv(lndimn,nnode),cartd(lndimn,nnode),xjaci(lndimn,lndimn))

          allocate(element(ielem)%egaus(ikg)%gpcod(ndimn,ngaus), &
          element(ielem)%egaus(ikg)%djacb(ngaus))

          if (nameg(1:4)/='mass')allocate(element(ielem)%egaus(ikg)%cartd(lndimn,nnode,ngaus))
          if (nnode==2)djacb=sqrt(sum((elcod(1:ndimn,2)-elcod(1:ndimn,1))**2))

          if  (ikg==1.and.ielknind==22.and.special(1:1)=='B') then
             estift=0.
             estifh=0.
          endif
          if  (ikg==1.and.(ielknind==3.or.ielknind==5.or.ielknind==9.or.ielknind==16.or.ielknind==18).and.special(1:1)=='B')then
             allocate(f0(3*(ndimn-1),3*(ndimn-1)),xyz0(ndimn))
             call gmatx_sr0(ndimn,nnode,elcod,djacb0,f0,xyz0)
          endif

          !coordinate for gauss points & derivatives
          do ig=1,ngaus !ig

             shape=elkn(ielknind)%ggaus(ikg)%shape(:,ig)
             deriv=elkn(ielknind)%ggaus(ikg)%deriv(:,:,ig)
             
             !if(ielem==24.or.ielem==25.and.ig==1)then
             !    write(7,*)'ie=',ielem,'ig=',ig,'ikg=',ikg
             !    write(7,*)'deriv_0'
             !    do inode=1,nnode
             !    write(7,*)deriv(:,inode)
             !    end do
             !endif
             weigp=elkn(ielknind)%ggaus(ikg)%weigp(ig)

             do id=1,ndimn
                element(ielem)%egaus(ikg)%gpcod(id,ig)=sum (elcod(id,1:nnode)*shape(1:nnode))
             end do

             if  (nnode==2)then
                cartd=deriv/djacb
             else

                ! for mapped infinite elements

                if  (group_inf/=0)then

                   allocate(posgp(ndimn),deriv_inf(ndimn,nnode))
                   posgp=elkn(ielknind)%ggaus(ikg)%posgp(:,ig)
                   deriv_inf=0.
                   if  (ielknind==5) then
                      if  (group_inf==1)then
                         deriv_inf(1,1)=(1-posgp(2))/(1-posgp(1))**2
                         deriv_inf(2,1)=-1./(1-posgp(1))
                         deriv_inf(1,4)=(1+posgp(2))/(1-posgp(1))**2
                         deriv_inf(2,4)= 1./(1-posgp(1))
                      elseif(group_inf==2)then
                         deriv_inf(1,1)=4./((1-posgp(2))*(1-posgp(1))**2)
                         deriv_inf(2,1)=4./((1-posgp(1))*(1-posgp(2))**2)
                      endif
                   elseif(ielknind==9) then
                      if  (group_inf==1)then
                         deriv_inf(1,1)= .5*(1-posgp(2))*(1-posgp(3))/(1-posgp(1))**2
                         deriv_inf(2,1)=-.5*(1-posgp(3))/(1-posgp(1))
                         deriv_inf(3,1)=-.5*(1-posgp(2))/(1-posgp(1))
                         deriv_inf(1,4)= .5*(1+posgp(2))*(1-posgp(3))/(1-posgp(1))**2
                         deriv_inf(2,4)= .5*(1-posgp(3))/(1-posgp(1))
                         deriv_inf(3,4)=-.5*(1+posgp(2))/(1-posgp(1))

                         deriv_inf(1,5)= .5*(1-posgp(2))*(1+posgp(3))/(1-posgp(1))**2
                         deriv_inf(2,5)=-.5*(1+posgp(3))/(1-posgp(1))
                         deriv_inf(3,5)= .5*(1-posgp(2))/(1-posgp(1))
                         deriv_inf(1,8)= .5*(1+posgp(2))*(1+posgp(3))/(1-posgp(1))**2
                         deriv_inf(2,8)= .5*(1+posgp(3))/(1-posgp(1))
                         deriv_inf(3,8)= .5*(1+posgp(2))/(1-posgp(1))
                      elseif(group_inf==2)then
                         deriv_inf(1,1)=2.*(1-posgp(3))/((1-posgp(2))*(1-posgp(1))**2)
                         deriv_inf(2,1)=2.*(1-posgp(3))/((1-posgp(1))*(1-posgp(2))**2)
                         deriv_inf(3,1)=-2./((1-posgp(1))*(1-posgp(2)))
                         deriv_inf(1,5)=2.*(1+posgp(3))/((1-posgp(2))*(1-posgp(1))**2)
                         deriv_inf(2,5)=2.*(1+posgp(3))/((1-posgp(1))*(1-posgp(2))**2)
                         deriv_inf(3,5)=2./((1-posgp(1))*(1-posgp(2)))
                      elseif(group_inf==3)then
                         deriv_inf(1,1)=1./((1-posgp(2))*(1-posgp(3))*(1-posgp(1))**2)
                         deriv_inf(2,1)=1./((1-posgp(3))*(1-posgp(1))*(1-posgp(2))**2)
                         deriv_inf(3,1)=1./((1-posgp(1))*(1-posgp(2))*(1-posgp(3))**2)
                      endif
                   endif
                   call jacob_inf(ielem, lndimn, nnode,elcod,deriv_inf,deriv,cartd, djacb)
                   deallocate(posgp,deriv_inf)
                else
   !                 if(ielem==25)write(7,*)'ie=',ielem,'ig=',ig
                   call jacob(ielem, lndimn, nnode,elcod,deriv,cartd, djacb,xjaci)
                endif !if (group_inf/=0)then
             endif !if (nnode==2)then

             !! for Simo & Rifai element
             if  (ikg==1.and.(ielknind==3.or.ielknind==5.or.ielknind==9.or.ielknind==16.or.ielknind==18).and.special(1:1)=='B')then

                shape_sr=elkn(ielknind)%shape_sr(1:3*(ndimn-1),1:aevab,ig)
                call gmatx_sr(3*(ndimn-1),djacb,djacb0,f0,shape_sr,gmatx)
                element(ielem)%gmatx(:,:,ig)=gmatx

             endif

             if  (ikg==1.and.ielknind==22.and.(special(1:1)=='C'.or.special(1:1)=='S')) then
                s=elkn(ielknind)%ggaus(ikg)%posgp(1,ig)
                t=elkn(ielknind)%ggaus(ikg)%posgp(2,ig)
                call der_shap_puxiaoming(s,t,elcod,bbar,shapwxy,1,dershap)
                element(ielem)%egaus(ikg)%bbar(:,:,ig)=bbar
                element(ielem)%egaus(ikg)%shapwxy(:,:,ig)=shapwxy
             endif

             10 format(12f8.3)

             if  (ikg==1.and.ielknind==22.and.special(1:1)=='B') then
                s=elkn(ielknind)%ggaus(ikg)%posgp(1,ig)
                t=elkn(ielknind)%ggaus(ikg)%posgp(2,ig)
                shape_sr=0.
                shape_sr(1,1)=s;shape_sr(1,3)=s*t
                shape_sr(2,2)=t;shape_sr(2,4)=s*t
                bmatx=0.
                do inode=1,4
                   bmatx(1,(inode-1)*3+1)= cartd(2,inode)
                   bmatx(1,(inode-1)*3+2)=-shape(inode)
                   bmatx(2,(inode-1)*3+1)= cartd(1,inode)
                   bmatx(2,(inode-1)*3+3)= shape(inode)
                end do
                call gmatx_sr_p4(2,2,nnode,elcod,djacb,shape_sr,gmatx)
                estifh=estifh+matmul(transpose(gmatx),gmatx)*djacb
                estift=estift+matmul(transpose(gmatx),bmatx)*djacb
                gmatx_g(:,:,ig)=gmatx
             endif
             !! end for Simo & Rifai element

             if (nameg/='mass')element(ielem)%egaus(ikg)%cartd(:,:,ig)=cartd
             if  (name=='AX') then
                element(ielem)%egaus(ikg)%djacb(ig)=djacb*weigp*element(ielem)%egaus(ikg)%gpcod(1,ig)
             else
                element(ielem)%egaus(ikg)%djacb(ig)=djacb*weigp
             endif
          end do !ig

          if  (ikg==1.and.ielknind==22.and.special(1:1)=='B') then
             call householder(estifh,estift,estifhit)
             do ig=1,ngaus
                element(ielem)%egaus(ikg)%bbar(:,:,ig)=gmatx_g(:,:,ig).x.estifhit
             end do
          endif
          deallocate (shape,deriv,cartd,xjaci)

          !modified simo_rifai

          if  (src==1)then
             if  (ikg==1.and.(ielknind==3.or.ielknind==5.or.ielknind==9.or.ielknind==16.or.ielknind==18).and.special(1:1)=='B')then
                allocate(xyzg(ndimn,ngaus))
                do ig=1,ngaus
                   xyzg(:,ig)=element(ielem)%egaus(ikg)%gpcod(:,ig)-xyz0
                end do
             
                do idimn=1,ndimn
                   xyzmax=maxval(abs(xyzg(idimn,:)))
                   xyzg(idimn,:)=xyzg(idimn,:)/xyzmax
                end do
                do ig=1,ngaus
                   s=xyzg(1,ig)
                   t=xyzg(2,ig)
                   u=0.
                   if (ndimn==3)u=xyzg(3,ig)
                   call shfunsrc(ielknind,s,t,u,shape_sr,special)
                   !element(ielem)%gmatx(1:3*(ndimn-1),:,ig)=djacb0/element(ielem)%egaus(ikg)%djacb(ig)*shape_sr
                   element(ielem)%gmatx(1:3*(ndimn-1),:,ig)=shape_sr
                end do
                deallocate(xyzg)
             endif
          endif
          !end modified simo_rifai
       end do        !!!ikg
       11  continue
    endif
    if  (ielknind/=20.and.ielknind/=21.and.special(1:1)=='D') then  !!new
       !!!DD
       ngaus=elkn(ielknind)%ggaus(1)%ngaus
       if  (ielknind==3)then
          nnode_dd=6
          dindex=4
       elseif(ielknind==5)then
          nnode_dd=8
          dindex=6
       elseif(ielknind==9)then
          nnode_dd=20
          dindex=10
       endif
       allocate(shape(nnode_dd),deriv(lndimn,nnode_dd),cartd(lndimn,nnode_dd),elcod_dd(ndimn,nnode_dd),  &
                xjaci(lndimn,lndimn))
       do idimn=1,ndimn
          elcod_dd(idimn,1:nnode)=elcod(idimn,:)
       end do
       do inode=1,nnode
          do idimn=1,ndimn
             if (inode<nnode) elcod_dd(idimn,inode+nnode)=.5*(elcod(idimn,inode)+elcod(idimn,inode+1))
             if (inode==nnode)elcod_dd(idimn,inode+nnode)=.5*(elcod(idimn,inode)+elcod(idimn,1))
          end do
       end do
       if  (dindex==10)then
          elcod_dd(:,17:20)=.5*(elcod(:,1:4)+elcod(:,5:8))
       endif

       write(7,*)'ielem=',ielem
       do inode=1,nnode_dd
          write(7,*)inode,elcod_dd(:,inode)
       end do
       do ig=1,ngaus
          shape=elkn(dindex)%ggaus(1)%shape(:,ig)
          deriv=elkn(dindex)%ggaus(1)%deriv(:,:,ig)
          weigp=elkn(dindex)%ggaus(1)%weigp(ig)
          call jacob(ielem, lndimn, nnode_dd,elcod_dd,deriv,cartd, djacb,xjaci)
          element(ielem)%djacb_dd(ig)=djacb*weigp
          element(ielem)%gmatx(:,:,ig)=cartd
       end do
       deallocate(shape,deriv,cartd,elcod_dd,xjaci)

    endif   !!new
    deallocate (elcod,lnods)

    if ((ielknind==3.or.ielknind==5.or.ielknind==9.or.ielknind==16.or.ielknind==18).and.special(1:1)=='B')deallocate(gmatx,shape_sr,f0,xyz0)
    if (ielknind==22.and.special(1:1)=='B')deallocate(gmatx,shape_sr,estift,estifh,gmatx_g,bmatx,estifhit)
    if (ielknind==22.and.(special(1:1)=='C'.or.special(1:1)=='S'))deallocate(n1i,n2i,n3i,bbar,shapwxy,dershap)

    !contains
    end subroutine read_element
    
       subroutine direct_beam(dim,a3,r,point_direct,coordx)  !20200113
     integer(ink) point_direct(2),dim
     real (irk) xx,r(:,:),a3(:),coordx(:,:)
    r(1,:)=a3
    if  (dim.eq.2) then
       r(2,1)=-r(1,2)    !20200113
       r(2,2)=r(1,1)     !20200113
       return
    endif
    
   if(point_direct(1)/=0.and.point_direct(2)/=0)then
      xx=sum((coordx(:,point_direct(2))-coordx(:,point_direct(1)))**2)  !20200210
	  xx=sqrt(xx)
	  r(3,:)=(coordx(:,point_direct(2))-coordx(:,point_direct(1)))/xx   !20200210
   else

    xx=a3(1)**2+a3(3)**2
    !!X,Y,Z ---global axis, x,y,z--local axis
    !!x is the axial direction of the bar
    !!    if x/=Y, z=x*Y, y=z*x
    !!    if x=Y,  z=x*Z, y=z*x
    if  (xx.gt..001) then
       r(3,1)=-a3(3)
       r(3,2)=0.
       r(3,3)=a3(1)
    else
       r(3,1)=a3(2)
       r(3,2)=-a3(1)
       r(3,3)=0.
    endif
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

    end subroutine direct_beam

    subroutine direct_p4(dim,a3,r,point_direct,coordx)    !20200210
    integer(ink) point_direct(2),dim
    real   (irk)xx, r(:,:),a3(:),coordx(:,:)

    r(dim,:)=a3
   if(point_direct(1)/=0.and.point_direct(2)/=0)then
      xx=sum((coordx(:,point_direct(2))-coordx(:,point_direct(1)))**2)  !20200210
	  xx=sqrt(xx)
	  r(1,:)=(coordx(:,point_direct(2))-coordx(:,point_direct(1)))/xx   !20200210
   else
    
    xx=a3(1)**2+a3(3)**2
    !!X,Y,Z ---global axis, x,y,z--local axis
    !!z is the normal direction of the surface
    !!    if z/=Y, x=Y*z, y=z*x
    !!    if z=y,  x=X*z, y=z*x
    if  (xx.gt..001) then
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
    endif
    r(2,1)=r(3,2)*r(1,3)-r(3,3)*r(1,2)
    r(2,2)=r(3,3)*r(1,1)-r(3,1)*r(1,3)
    r(2,3)=r(3,1)*r(1,2)-r(3,2)*r(1,1)
    a3=r(2,:)**2
    xx=sqrt(sum(a3))
    r(2,:)=r(2,:)/xx

    end subroutine direct_p4
 



    subroutine der_shap(s,t,elcod,n1i,n2i,n3i)
    real(irk) s,t,a,b,c,d,e,f,elcod(:,:),dd(4),cc(6)
    real(irk) li,lj,x1,x2,x3,x4,x5,x6,x7,x8
    real(irk) n1i(:,:),n2i(:,:),n3i(:,:),aa(4)
    integer(ink) inod
    real(irk) L1(4), L2(4)
    DATA L1/-1,1,1,-1/, L2/-1,-1,1,1/


    a=0.;b=0.;c=0.;d=0.;e=0.;f=0.;
    do inod=1,4
       a=a+l1(inod)*(1+l2(inod)*t)*elcod(1,inod)
       b=b+l2(inod)*(1+l1(inod)*s)*elcod(1,inod)
       c=c+l1(inod)*(1+l2(inod)*t)*elcod(2,inod)
       d=d+l2(inod)*(1+l1(inod)*s)*elcod(2,inod)
       e=e+l1(inod)*l2(inod)*elcod(1,inod)
       f=f+l1(inod)*l2(inod)*elcod(2,inod)
    end do
    a=a*.25;b=b*.25;c=c*.25;d=d*.25;e=e*.25;f=f*.25
    dd(1)=d/(a*d-b*c)
    dd(2)=c/(b*c-a*d)
    dd(3)=b/(b*c-a*d)
    dd(4)=a/(a*d-b*c)
    cc(1)=2*(d*e-b*f)/(b*c-d*a)*dd(1)*dd(2)
    cc(2)=2*(f*a-e*c)/(b*c-d*a)*dd(1)*dd(2)
    cc(3)=2*(d*e-b*f)/(b*c-d*a)*dd(3)*dd(4)
    cc(4)=2*(f*a-e*c)/(b*c-d*a)*dd(3)*dd(4)
    cc(5)=2*(d*e-b*f)/(b*c-d*a)*(dd(1)*dd(4)+dd(2)*dd(3))
    cc(6)=2*(f*a-e*c)/(b*c-d*a)*(dd(1)*dd(4)+dd(2)*dd(3))
    !N1

    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=2+li*s+lj*t-s**2-t**2
       x2=(1+lj*t)*li*dd(1)+(1+li*s)*lj*dd(2)
       x3=(1+li*s)*(1+lj*t)
       x4=li*dd(1)+lj*dd(2)-2*s*dd(1)-2*t*dd(2)
       x5=(1+lj*t)*li*cc(1)+2*li*lj*dd(1)*dd(2)+(1+li*s)*lj*cc(2)
       x6=li*cc(1)+lj*cc(2)-2*s*cc(1)-2*dd(1)**2-2*t*cc(2)-2*dd(2)**2
       x7=li*dd(1)+lj*dd(2)+li*lj*(s*dd(2)+t*dd(1))
       N1i(1,inod)=(x2*x4+x1*x5+x3*x6+x4*x7)*.125
    end do

    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=2+li*s+lj*t-s**2-t**2
       x2=(1+lj*t)*li*dd(3)+(1+li*s)*lj*dd(4)
       x3=(1+li*s)*(1+lj*t)
       x4=li*dd(3)+lj*dd(4)-2*s*dd(3)-2*t*dd(4)
       x5=(1+lj*t)*li*cc(3)+2*li*lj*dd(3)*dd(4)+(1+li*s)*lj*cc(4)
       x6=li*cc(3)+lj*cc(4)-2*s*cc(3)-2*dd(3)**2-2*t*cc(4)-2*dd(4)**2
       x7=li*dd(3)+lj*dd(4)+li*lj*(s*dd(4)+t*dd(3))
       N1i(2,inod)=(x2*x4+x1*x5+x3*x6+x4*x7)*.125
    end do

    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=2+li*s+lj*t-s**2-t**2
       x2=(1+lj*t)*li*dd(1)+(1+li*s)*lj*dd(2)
       x3=(1+li*s)*(1+lj*t)
       x4=li*dd(1)+lj*dd(2)-2*s*dd(1)-2*t*dd(2)

       x5=li*dd(3)+lj*dd(4)-2*s*dd(3)-2*t*dd(4)
       x6=(1+lj*t)*li*cc(5)+li*lj*(dd(4)*dd(1)+dd(3)*dd(2))+(1+li*s)*lj*cc(6)
       x7=li*cc(5)+lj*cc(6)-2*dd(1)*dd(3)-2*s*cc(5)-2*dd(2)*dd(4)-2*t*cc(6)
       x8=li*dd(3)+lj*dd(4)+li*lj*(s*dd(4)+t*dd(3))
       N1i(3,inod)=(x2*x5+x1*x6+x3*x7+x4*x8)*.125
    end do

    n1i=-n1i
    !N2

    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-t**2)*lj
       x2=(1+lj*t)*li*dd(1)+(1+li*s)*lj*dd(2)
       x3=(1+li*s)*(1+lj*t)
       x4=-2*t*lj*dd(2)
       x5=(1+lj*t)*li*cc(1)+2*li*lj*dd(1)*dd(2)+(1+li*s)*lj*cc(2)
       x6=-2*t*lj*cc(2)-2*lj*dd(2)**2
       x7=li*dd(1)+lj*dd(2)+li*lj*(s*dd(2)+t*dd(1))
       N2i(1,inod)=-(x2*x4+x1*x5+x3*x6+x4*x7)*.125
    end do



    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-lj**2)*lj
       x2=(1+lj*lj)*li*dd(3)+(1+li*li)*lj*dd(4)
       x3=(1+li*li)*(1+lj*lj)
       x4=-2*lj*lj*dd(4)
       aa(inod)=-(x1*x2+x3*x4)*.125
    end do
    if (aa(1)==0.) then
       write(7,*)'aa1=',aa
       write(7,*)'elcod='
       write(7,*)elcod(1:2,1)
       write(7,*)elcod(1:2,2)
       write(7,*)elcod(1:2,3)
       write(7,*)elcod(1:2,4)
       stop
    endif
    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-t**2)*lj
       x2=(1+lj*t)*li*dd(3)+(1+li*s)*lj*dd(4)
       x3=(1+li*s)*(1+lj*t)
       x4=-2*t*lj*dd(4)
       x5=(1+lj*t)*li*cc(3)+2*li*lj*dd(3)*dd(4)+(1+li*s)*lj*cc(4)
       x6=-2*t*lj*cc(4)-2*lj*dd(4)**2
       x7=li*dd(3)+lj*dd(4)+li*lj*(s*dd(4)+t*dd(3))
       N2i(2,inod)=-(x2*x4+x1*x5+x3*x6+x4*x7)*.125
    end do


    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-t**2)*lj
       x2=(1+lj*t)*li*dd(1)+(1+li*s)*lj*dd(2)
       x3=(1+li*s)*(1+lj*t)
       x4=-2*t*lj*dd(2)

       x5=-2*t*lj*dd(4)
       x6=(1+lj*t)*li*cc(5)+li*lj*(dd(4)*dd(1)+dd(3)*dd(2))+(1+li*s)*lj*cc(6)
       x7=-2*lj*dd(2)*dd(4)-2*t*lj*cc(6)
       x8=li*dd(3)+lj*dd(4)+li*lj*(s*dd(4)+t*dd(3))
       N2i(3,inod)=-(x2*x5+x1*x6+x3*x7+x4*x8)*.125
    end do

    do inod=1,4
       n2i(:,inod)=-n2i(:,inod)/aa(inod)
    end do

    !N3

    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-li**2)*li
       x2=(1+lj*lj)*li*dd(1)+(1+li*li)*lj*dd(2)
       x3=(1+li*li)*(1+lj*lj)
       x4=-2*li*li*dd(1)
       aa(inod)=(x1*x2+x3*x4)*.125
    end do
    if (aa(1)==0.) then
       write(7,*)'elcod='
       write(7,*)'aa2=',aa
       write(7,*)elcod(1:2,1)
       write(7,*)elcod(1:2,2)
       write(7,*)elcod(1:2,3)
       write(7,*)elcod(1:2,4)
       stop
    endif

    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-s**2)*li
       x2=(1+lj*t)*li*dd(1)+(1+li*s)*lj*dd(2)
       x3=(1+li*s)*(1+lj*t)
       x4=-2*s*li*dd(1)
       x5=(1+lj*t)*li*cc(1)+2*li*lj*dd(1)*dd(2)+(1+li*s)*lj*cc(2)
       x6=-2*s*li*cc(1)-2*li*dd(1)**2
       x7=li*dd(1)+lj*dd(2)+li*lj*(s*dd(2)+t*dd(1))
       N3i(1,inod)=(x2*x4+x1*x5+x3*x6+x4*x7)*.125
    end do

    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-s**2)*li
       x2=(1+lj*t)*li*dd(3)+(1+li*s)*lj*dd(4)
       x3=(1+li*s)*(1+lj*t)
       x4=-2*s*li*dd(3)
       x5=(1+lj*t)*li*cc(3)+2*li*lj*dd(3)*dd(4)+(1+li*s)*lj*cc(4)
       x6=-2*s*li*cc(3)-2*li*dd(3)**2
       x7=li*dd(3)+lj*dd(4)+li*lj*(s*dd(4)+t*dd(3))
       N3i(2,inod)=(x2*x4+x1*x5+x3*x6+x4*x7)*.125
    end do


    do inod=1,4
       li=l1(inod)
       lj=l2(inod)
       x1=(1-s**2)*li
       x2=(1+lj*t)*li*dd(1)+(1+li*s)*lj*dd(2)
       x3=(1+li*s)*(1+lj*t)
       x4=-2*s*li*dd(1)

       x5=-2*s*li*dd(3)
       x6=(1+lj*t)*li*cc(5)+li*lj*(dd(4)*dd(1)+dd(3)*dd(2))+(1+li*s)*lj*cc(6)
       x7=-2*li*dd(1)*dd(3)-2*s*li*cc(5)
       x8=li*dd(3)+lj*dd(4)+li*lj*(s*dd(4)+t*dd(3))
       N3i(3,inod)=(x2*x5+x1*x6+x3*x7+x4*x8)*.125
    end do

    do inod=1,4
       n3i(:,inod)=n3i(:,inod)/aa(inod)
    end do
    end subroutine der_shap

    subroutine der_shap_puxiaoming(s,t,elcod,bbar,shapwxy,ic,dershap)
    integer(ink) i0,i,j,k,i1,ic
    real(irk) elcod(:,:),bbar(:,:),shapwxy(:,:),dershap(:,:,:)
    real(irk) li,lj,nx(4),ny(4),sx(4),sy(4),dl(4),l1(4),l2(4),  &
    rx(4),ry(4),ex(4),ey(4),fx(4),fy(4),gx(4),gy(4),  &
    hx(4),hy(4),phi(3,3),tinv(3,3),bbari(3,3)
    real(irk) a,b,a1,a2,a3,a4,w1,w2,tt,dj,s,t,dis
    real(irk) n1l(3,4),n2l(3,4),n3l(3,4),n10(2,4),n20(2,4),n30(2,4)
    DATA L1/-1,1,1,-1/, L2/-1,-1,1,1/

    dl=0.
    nx=0.
    ny=0.
    sx=0.
    sy=0.
    do i0=1,4
       i1=i0+1
       if (i0==4)i1=1
       dis=sqrt((elcod(1,i1)-elcod(1,i0))**2+(elcod(2,i1)-elcod(2,i0))**2)
       if (dis>0.) then
          dl(i0)=dis
          ny(i0)=-(elcod(1,i1)-elcod(1,i0))/dl(i0)
          nx(i0)= (elcod(2,i1)-elcod(2,i0))/dl(i0)
          sx(i0)= (elcod(1,i1)-elcod(1,i0))/dl(i0)
          sy(i0)= (elcod(2,i1)-elcod(2,i0))/dl(i0)
       endif
    end do

    do i0=1,4
       li=l1(i0)
       lj=l2(i0)
       j=2+lj
       k=3-li
       rx(i0)=dl(i0)*sx(i0)/16.
       ry(i0)=dl(i0)*sy(i0)/16.
       ex(i0)=(3*dl(j)*sx(j)-dl(k)*sx(k))/48.
       ey(i0)=(3*dl(j)*sy(j)-dl(k)*sy(k))/48.
       fx(i0)=(3*dl(k)*sx(k)-dl(j)*sx(j))/48.
       fy(i0)=(3*dl(k)*sy(k)-dl(j)*sy(j))/48.
       gx(i0)=(5*dl(j)*sx(j)-dl(k)*sx(k))*5./384.
       gy(i0)=(5*dl(j)*sy(j)-dl(k)*sy(k))*5./384.
       hx(i0)=(5*dl(k)*sx(k)-dl(j)*sx(j))*5./384.
       hy(i0)=(5*dl(k)*sy(k)-dl(j)*sy(j))*5./384.
    end do

    do i=1,4
       li=l1(i)
       lj=l2(i)
       j=2+lj
       k=3-li
       n1l(1,i)=-.75*li*s-15./16.*li*lj*s*t
       n1l(2,i)=-.75*lj*t-15./16.*li*lj*s*t
       n1l(3,i)=.25*li*lj-li*lj*(3.*s**2+3*t**2-2.)*5/32.
       n2l(1,i)=-2.*li*lj*ry(j)-2*li*ry(j)*t-6*lj*ey(i)*s-6*gy(i)*s*t
       n2l(2,i)= 2.*li*lj*ry(k)+2*lj*ry(k)*s+6*li*fy(i)*t+6*hy(i)*s*t
       n2l(3,i)=-2.*li*ry(j)*s+2*lj*ry(k)*t-gy(i)*(3*s**2-1)+hy(i)*(3*t**2-1)
       n3l(1,i)= 2.*li*lj*rx(j)+2*li*rx(j)*t+6*lj*ex(i)*s+6*gx(i)*s*t
       n3l(2,i)=-2.*li*lj*rx(k)-2*lj*rx(k)*s-6*li*fx(i)*t-6*hx(i)*s*t
       n3l(3,i)= 2.*li*rx(j)*s-2*lj*rx(k)*t+gx(i)*(3*s**2-1)-hx(i)*(3*t**2-1)
       shapwxy(1,i)=.25*(1+li*s+lj*t+li*lj*s*t)-.125*li*s*(s**2-1)-.125*lj*t*(t**2-1)  &
       -li*lj*s*t*(s**2-1)*5/32.-li*lj*s*t*(t**2-1)*5/32.
       shapwxy(2,i)=-li*lj*ry(j)*(s**2-1)+li*lj*ry(k)*(t**2-1)-li*ry(j)*t*(s**2-1)  &
       +lj*ry(k)*s*(t**2-1)-lj*ey(i)*s*(s**2-1)+li*fy(i)*t*(t**2-1)  &
       -gy(i)*s*t*(s**2-1)+hy(i)*s*t*(t**2-1)
       shapwxy(3,i)= li*lj*rx(j)*(s**2-1)-li*lj*rx(k)*(t**2-1)+li*rx(j)*t*(s**2-1)  &
       -lj*rx(k)*s*(t**2-1)+lj*ex(i)*s*(s**2-1)-li*fx(i)*t*(t**2-1)  &
       +gx(i)*s*t*(s**2-1)-hx(i)*s*t*(t**2-1)
    end do

    if (ic==0) return

    do i=1,4
       li=l1(i)
       lj=l2(i)
       j=2+lj
       k=3-li
       N10(1,i)=.25*li*(1+lj*t)-.125*li*(3*s**2-1)-5./32.*li*lj*t*(3*s**2-1)  &
       -5./32.*li*lj*t*(t**2-1)
       N10(2,i)=.25*lj*(1+li*s)-.125*lj*(3*t**2-1)-5./32.*lj*li*s*(3*t**2-1)  &
       -5./32.*li*lj*s*(s**2-1)
       N20(1,i)=-2.*li*lj*ry(j)*s-2*li*ry(j)*s*t+lj*ry(k)*(t**2-1)              &
       -lj*ey(i)*(3*s**2-1)-gy(i)*t*(3*s**2-1)+hy(i)*t*(t**2-1)
       N20(2,i)= 2.*li*lj*ry(k)*t+2*lj*ry(k)*s*t-li*ry(j)*(s**2-1)              &
       +li*fy(i)*(3*t**2-1)+hy(i)*s*(3*t**2-1)-gy(i)*s*(s**2-1)
       N30(1,i)= 2.*li*lj*rx(j)*s+2*li*rx(j)*s*t-lj*rx(k)*(t**2-1)              &
       +lj*ex(i)*(3*s**2-1)+gx(i)*t*(3*s**2-1)-hx(i)*t*(t**2-1)
       N30(2,i)=-2.*li*lj*rx(k)*t-2*lj*rx(k)*s*t+li*rx(j)*(s**2-1)              &
       -li*fx(i)*(3*t**2-1)-hx(i)*s*(3*t**2-1)+gx(i)*s*(s**2-1)
    end do

    a1=0.;a2=0.;a3=0.;a4=0.;a=0.;b=0.

    do i=1,4
       a=a+l1(i)*l2(i)*elcod(1,i)
       b=b+l1(i)*l2(i)*elcod(2,i)
       a1=a1+l1(i)*elcod(1,i)
       a2=a2+l1(i)*elcod(2,i)
       a3=a3+l2(i)*elcod(1,i)
       a4=a4+l2(i)*elcod(2,i)
    end do

    tt=a1*a4-a2*a3+(b*a1-a*a2)*s+(a*a4-b*a3)*t
    w1=-(A*a4-b*a3)/tt
    w2=-(b*a1-a*a2)/tt
    dj=.25*((a1+a*t)*(a4+b*s)-(a3+a*s)*(a2+b*t))

    tinv(1,1)= (a4+b*s)**2
    tinv(1,2)= (a2+b*t)**2
    tinv(1,3)=-2*(a4+b*s)*(a2+b*t)
    tinv(2,1)= (a3+a*s)**2
    tinv(2,2)= (a1+a*t)**2
    tinv(2,3)=-2*(a3+a*s)*(a1+a*t)
    tinv(3,1)=-2*(a3+a*s)*(a4+b*s)
    tinv(3,2)=-2*(a1+a*t)*(a2+b*t)
    tinv(3,3)= 2*(a1+a*t)*(a4+b*s)+2*(a3+a*s)*(a2+b*t)
    tinv=tinv/dj/dj

    do i0=1,4
       phi(:,1)=n1l(:,i0)
       phi(:,2)=n2l(:,i0)
       phi(:,3)=n3l(:,i0)
       phi(3,1)=(phi(3,1)+w1*n10(1,i0)+w2*n10(2,i0))
       phi(3,2)=(phi(3,2)+w1*n20(1,i0)+w2*n20(2,i0))
       phi(3,3)=(phi(3,3)+w1*n30(1,i0)+w2*n30(2,i0))


       phi=-phi
       bbari=tinv.x.phi

       bbar(:,(i0-1)*3+1:i0*3)=bbari


       dershap(1,i0,1)=( (a4+b*s)*n10(1,i0)-(a3+a*s)*n10(2,i0))/dj
       dershap(2,i0,1)=(-(a2+b*t)*n10(1,i0)+(a1+a*t)*n10(2,i0))/dj
       dershap(1,i0,2)=( (a4+b*s)*n20(1,i0)-(a3+a*s)*n20(2,i0))/dj
       dershap(2,i0,2)=(-(a2+b*t)*n20(1,i0)+(a1+a*t)*n20(2,i0))/dj
       dershap(1,i0,3)=( (a4+b*s)*n30(1,i0)-(a3+a*s)*n30(2,i0))/dj
       dershap(2,i0,3)=(-(a2+b*t)*n30(1,i0)+(a1+a*t)*n30(2,i0))/dj


    end do


    end subroutine der_shap_puxiaoming


    subroutine der_shap_puli(s,t,elcod,n1i,n2i,n3i)
    integer(ink) i0,i,j,k,i1,inod
    real(irk) elcod(:,:),n1i(:,:),n2i(:,:),n3i(:,:),dn(3,9)
    real(irk) li,lj,nx(4),ny(4),sx(4),sy(4),dl(4),l1(4),l2(4),  &
    rx(4),ry(4),ex(4),ey(4),fx(4),fy(4),gx(4),gy(4),  &
    hx(4),hy(4)
    real(irk) s,t,dis,a,b,c,d,e,f,dd(4),cc(6)
    DATA L1/-1,1,1,-1/, L2/-1,-1,1,1/

    dl=0.
    nx=0.
    ny=0.
    sx=0.
    sy=0.
    do i0=1,4
       i1=i0+1
       if (i0==4)i1=1
       dis=sqrt((elcod(1,i1)-elcod(1,i0))**2+(elcod(2,i1)-elcod(2,i0))**2)
       if (dis>0.) then
          dl(i0)=dis
          ny(i0)=-(elcod(1,i1)-elcod(1,i0))/dl(i0)
          nx(i0)= (elcod(2,i1)-elcod(2,i0))/dl(i0)
          sx(i0)= (elcod(1,i1)-elcod(1,i0))/dl(i0)
          sy(i0)= (elcod(2,i1)-elcod(2,i0))/dl(i0)
       endif
    end do

    do i0=1,4
       li=l1(i0)
       lj=l2(i0)
       j=2+lj
       k=3-li
       rx(i0)=dl(i0)*sx(i0)/16.
       ry(i0)=dl(i0)*sy(i0)/16.
       ex(i0)=(3*dl(j)*sx(j)-dl(k)*sx(k))/48.
       ey(i0)=(3*dl(j)*sy(j)-dl(k)*sy(k))/48.
       fx(i0)=(3*dl(k)*sx(k)-dl(j)*sx(j))/48.
       fy(i0)=(3*dl(k)*sy(k)-dl(j)*sy(j))/48.
       gx(i0)=(5*dl(j)*sx(j)-dl(k)*sx(k))*5./384.
       gy(i0)=(5*dl(j)*sy(j)-dl(k)*sy(k))*5./384.
       hx(i0)=(5*dl(k)*sx(k)-dl(j)*sx(j))*5./384.
       hy(i0)=(5*dl(k)*sy(k)-dl(j)*sy(j))*5./384.
    end do

    a=0.;b=0.;c=0.;d=0.;e=0.;f=0.;
    do inod=1,4
       a=a+l1(inod)*(1+l2(inod)*t)*elcod(1,inod)
       b=b+l2(inod)*(1+l1(inod)*s)*elcod(1,inod)
       c=c+l1(inod)*(1+l2(inod)*t)*elcod(2,inod)
       d=d+l2(inod)*(1+l1(inod)*s)*elcod(2,inod)
       e=e+l1(inod)*l2(inod)*elcod(1,inod)
       f=f+l1(inod)*l2(inod)*elcod(2,inod)
    end do
    a=a*.25;b=b*.25;c=c*.25;d=d*.25;e=e*.25;f=f*.25
    dd(1)=d/(a*d-b*c)
    dd(2)=c/(b*c-a*d)
    dd(3)=b/(b*c-a*d)
    dd(4)=a/(a*d-b*c)
    cc(1)=2*(d*e-b*f)/(b*c-d*a)*dd(1)*dd(2)
    cc(2)=2*(f*a-e*c)/(b*c-d*a)*dd(1)*dd(2)
    cc(3)=2*(d*e-b*f)/(b*c-d*a)*dd(3)*dd(4)
    cc(4)=2*(f*a-e*c)/(b*c-d*a)*dd(3)*dd(4)
    cc(5)=2*(d*e-b*f)/(b*c-d*a)*(dd(1)*dd(4)+dd(2)*dd(3))
    cc(6)=2*(f*a-e*c)/(b*c-d*a)*(dd(1)*dd(4)+dd(2)*dd(3))

    dn(1,1)=2*(s*cc(1)+dd(1)**2)
    dn(2,1)=2*(s*cc(3)+dd(3)**2)
    dn(3,1)=2*(dd(1)*dd(3)+s*cc(5))

    dn(1,2)=2*(t*cc(2)+dd(2)**2)
    dn(2,2)=2*(t*cc(4)+dd(4)**2)
    dn(3,2)=2*(dd(2)*dd(4)+t*cc(6))

    dn(1,3)=(s**2-1)*cc(2)+2*s*dd(1)*dd(2)+2*(s*dd(2)+t*dd(1))*dd(1)+2*s*t*cc(1)
    dn(2,3)=(s**2-1)*cc(4)+2*s*dd(3)*dd(4)+2*(s*dd(4)+t*dd(3))*dd(3)+2*s*t*cc(3)
    dn(3,3)=(s**2-1)*cc(6)+2*s*dd(3)*dd(2)+2*(s*dd(4)+t*dd(3))*dd(1)+2*s*t*cc(5)

    dn(1,4)=(t**2-1)*cc(1)+2*t*dd(1)*dd(2)+2*(t*dd(1)+s*dd(2))*dd(2)+2*s*t*cc(2)
    dn(2,4)=(t**2-1)*cc(3)+2*t*dd(3)*dd(4)+2*(t*dd(3)+s*dd(4))*dd(4)+2*s*t*cc(4)
    dn(3,4)=(t**2-1)*cc(5)+2*t*dd(4)*dd(1)+2*(t*dd(3)+s*dd(4))*dd(2)+2*s*t*cc(6)

    dn(1,5)=(3*s**2-1)*cc(1)+6*s*dd(1)**2
    dn(2,5)=(3*s**2-1)*cc(3)+6*s*dd(3)**2
    dn(3,5)=(3*s**2-1)*cc(5)+6*s*dd(1)*dd(3)

    dn(1,6)=(3*t**2-1)*cc(2)+6*t*dd(2)**2
    dn(2,6)=(3*t**2-1)*cc(4)+6*t*dd(4)**2
    dn(3,6)=(3*t**2-1)*cc(6)+6*t*dd(2)*dd(4)

    dn(1,7)=s*(s**2-1)*cc(2)+(3*s**2-1)*(2*dd(1)*dd(2)+t*cc(1))+6*s*t*dd(1)**2
    dn(2,7)=s*(s**2-1)*cc(4)+(3*s**2-1)*(2*dd(3)*dd(4)+t*cc(3))+6*s*t*dd(3)**2
    dn(3,7)=s*(s**2-1)*cc(6)+(3*s**2-1)*(dd(2)*dd(3)+dd(4)*dd(1)+t*cc(5))  &
    +6*s*t*dd(1)*dd(3)

    dn(1,8)=t*(t**2-1)*cc(1)+(3*t**2-1)*(2*dd(2)*dd(1)+s*cc(2))+6*s*t*dd(2)**2
    dn(2,8)=t*(t**2-1)*cc(3)+(3*t**2-1)*(2*dd(4)*dd(3)+s*cc(4))+6*s*t*dd(4)**2
    dn(3,8)=t*(t**2-1)*cc(5)+(3*t**2-1)*(dd(1)*dd(4)+dd(3)*dd(2)+s*cc(6))  &
    +6*s*t*dd(2)*dd(4)

    dn(1,9)=2.*dd(1)*dd(2)+s*cc(2)+t*cc(1)
    dn(2,9)=2.*dd(3)*dd(4)+s*cc(4)+t*cc(3)
    dn(3,9)=dd(3)*dd(2)+dd(1)*dd(4)+s*cc(6)+t*cc(5)

    do i0=1,4
       li=l1(i0)
       lj=l2(i0)
       i=i0
       j=2+lj
       k=3-li
       n1i(1,i0)=.25*(li*cc(1)+lj*cc(2)+li*lj*dn(1,9))  &
       -.125*(li*dn(1,5)+lj*dn(1,6))-5./32.*li*lj*(dn(1,7)+dn(1,8))
       n1i(2,i0)=.25*(li*cc(3)+lj*cc(4)+li*lj*dn(2,9))  &
       -.125*(li*dn(2,5)+lj*dn(2,6))-5./32.*li*lj*(dn(2,7)+dn(2,8))
       n1i(3,i0)=.25*(li*cc(5)+lj*cc(6)+li*lj*dn(3,9))  &
       -.125*(li*dn(3,5)+lj*dn(3,6))-5./32.*li*lj*(dn(3,7)+dn(3,8))

       n2i(1,i0)=-li*lj*ry(j)*dn(1,1)+li*lj*ry(k)*dn(1,2)-li*ry(j)*dn(1,3)  &
       +lj*ry(k)*dn(1,4)-lj*ey(i)*dn(1,5)+li*fy(i)*dn(1,6)  &
       -gy(i)*dn(1,7)+hy(i)*dn(1,8)
       n2i(2,i0)=-li*lj*ry(j)*dn(2,1)+li*lj*ry(k)*dn(2,2)-li*ry(j)*dn(2,3)  &
       +lj*ry(k)*dn(2,4)-lj*ey(i)*dn(2,5)+li*fy(i)*dn(2,6)  &
       -gy(i)*dn(2,7)+hy(i)*dn(2,8)
       n2i(3,i0)=-li*lj*ry(j)*dn(3,1)+li*lj*ry(k)*dn(3,2)-li*ry(j)*dn(3,3)  &
       +lj*ry(k)*dn(3,4)-lj*ey(i)*dn(3,5)+li*fy(i)*dn(3,6)  &
       -gy(i)*dn(3,7)+hy(i)*dn(3,8)

       n3i(1,i0)= li*lj*rx(j)*dn(1,1)-li*lj*rx(k)*dn(1,2)+li*rx(j)*dn(1,3)  &
       -lj*rx(k)*dn(1,4)+lj*ex(i)*dn(1,5)-li*fx(i)*dn(1,6)  &
       +gx(i)*dn(1,7)-hx(i)*dn(1,8)
       n3i(2,i0)= li*lj*rx(j)*dn(2,1)-li*lj*rx(k)*dn(2,2)+li*rx(j)*dn(2,3)  &
       -lj*rx(k)*dn(2,4)+lj*ex(i)*dn(2,5)-li*fx(i)*dn(2,6)  &
       +gx(i)*dn(2,7)-hx(i)*dn(2,8)
       n3i(3,i0)= li*lj*rx(j)*dn(3,1)-li*lj*rx(k)*dn(3,2)+li*rx(j)*dn(3,3)  &
       -lj*rx(k)*dn(3,4)+lj*ex(i)*dn(3,5)-li*fx(i)*dn(3,6)  &
       +gx(i)*dn(3,7)-hx(i)*dn(3,8)
    end do

    n1i=-n1i
    n2i=-n2i
    n3i=-n3i


    end subroutine der_shap_puli


    subroutine gmatx_sr(ntc,djacb,djacb0,f0,shape_sr,gmatx)

    integer(ink) ntc
    real   (irk) djacb,djacb0
    real   (irk) f0(:,:),gmatx(:,:),shape_sr(:,:)
    real   (irk),allocatable::gmatx0(:,:)
    allocate(gmatx0(ntc,size(gmatx,2)))
    gmatx=0.
    !      G= Transpose(inverse(F0))*shape_sr*djacb0/djacb

    call householder(F0,shape_sr,gmatx0) !

    gmatx(1:ntc,:)=gmatx0*djacb0/djacb
    !
    deallocate(gmatx0)
    end   subroutine gmatx_sr

    subroutine gmatx_sr0(xdimn,nnode,elcod,djacb0,f0,xyz0)

    integer(ink) xdimn,nnode,idime,jdime,inode,  &
    i,j,ip1,ip2,jp1,jp2
    real   (irk) djacb0,s,t,u
    real   (irk) elcod(:,:),f0(:,:),xyz0(:)
    real   (irk),allocatable::shape(:),deriv(:,:),xj0(:,:)

    allocate(shape(nnode),deriv(xdimn,nnode),xj0(xdimn,xdimn))
    s=0.0;t=0.0;u=0.0
    call shfunc( xdimn,nnode,s,t,u,shape,deriv)

    do idime=1,xdimn
       xyz0(idime)=sum (elcod(idime,1:nnode)*shape(1:nnode))
    end do

    do 4 idime=1,xdimn
       do 4 jdime=1,xdimn
          xj0(idime,jdime)=0.0
          do 4 inode=1,nnode
             xj0(idime,jdime)=xj0(idime,jdime)+        &
             deriv(idime,inode)*elcod(jdime,inode)
             4     continue
             !
             if (xdimn==2) then
                djacb0=xj0(1,1)*xj0(2,2)-xj0(1,2)*xj0(2,1)
             else
                call det3 (xj0,djacb0)
             endif

             !
             !*** calcula la matriz F0
             !
             if (xdimn==2) then
                F0(1,1)=  xj0(1,1)*xj0(1,1)
                F0(2,1)=  xj0(2,1)*xj0(2,1)
                F0(3,1)=2*xj0(1,1)*xj0(2,1)
                !
                F0(1,2)=  xj0(1,2)*xj0(1,2)
                F0(2,2)=  xj0(2,2)*xj0(2,2)
                F0(3,2)=2*xj0(1,2)*xj0(2,2)
                !
                F0(1,3)=  xj0(1,1)*xj0(1,2)
                F0(2,3)=  xj0(2,1)*xj0(2,2)
                F0(3,3)=  xj0(1,1)*xj0(2,2)+xj0(1,2)*xj0(2,1)

             else
                call cvert(xj0,f0)
             endif


             deallocate(shape,deriv,xj0)
             end   subroutine gmatx_sr0
             !!
    SUBROUTINE CVERT(BA,TT)
    real   (irk) BA(:,:),TT(:,:)
    integer(ink) i,j
    DO 10 I=1,3
       DO 10 J=1,3
          10   TT(I,J)=BA(i,j)**2
          TT(1,4)=BA(1,1)*BA(1,2)
          TT(1,5)=BA(1,2)*BA(1,3)
          TT(1,6)=BA(1,1)*BA(1,3)
          TT(2,4)=BA(2,1)*BA(2,2)
          TT(2,5)=BA(2,2)*BA(2,3)
          TT(2,6)=BA(2,1)*BA(2,3)
          TT(3,4)=BA(3,1)*BA(3,2)
          TT(3,5)=BA(3,2)*BA(3,3)
          TT(3,6)=BA(3,1)*BA(3,3)
          TT(4,1)=2.*BA(1,1)*BA(2,1)
          TT(4,2)=2.*BA(1,2)*BA(2,2)
          TT(4,3)=2.*BA(1,3)*BA(2,3)
          TT(5,1)=2.*BA(2,1)*BA(3,1)
          TT(5,2)=2.*BA(2,2)*BA(3,2)
          TT(5,3)=2.*BA(2,3)*BA(3,3)
          TT(6,1)=2.*BA(1,1)*BA(3,1)
          TT(6,2)=2.*BA(1,2)*BA(3,2)
          TT(6,3)=2.*BA(1,3)*BA(3,3)
          TT(4,4)=BA(1,1)*BA(2,2)+BA(1,2)*BA(2,1)
          TT(4,5)=BA(1,2)*BA(2,3)+BA(1,3)*BA(2,2)
          TT(4,6)=BA(1,1)*BA(2,3)+BA(1,3)*BA(2,1)
          TT(5,4)=BA(2,1)*BA(3,2)+BA(2,2)*BA(3,1)
          TT(5,5)=BA(2,2)*BA(3,3)+BA(3,2)*BA(2,3)
          TT(5,6)=BA(2,1)*BA(3,3)+BA(2,3)*BA(3,1)
          TT(6,4)=BA(3,1)*BA(1,2)+BA(1,1)*BA(3,2)
          TT(6,5)=BA(1,2)*BA(3,3)+BA(1,3)*BA(3,2)
          TT(6,6)=BA(1,1)*BA(3,3)+BA(3,1)*BA(1,3)
          END SUBROUTINE CVERT
          !

    subroutine gmatx_sr_p4(ntc,xdimn,nnode,elcod,djacb,shape_sr,gmatx)

    integer(ink) xdimn,nnode,ntc,idime,jdime,inode
    real   (irk) djacb,djacb0,s,t,u
    real   (irk) elcod(:,:),shape_sr(:,:),gmatx(:,:)
    real   (irk),allocatable::shape(:),deriv(:,:),xj0(:,:),f0(:,:)
    allocate(shape(nnode),deriv(xdimn,nnode),xj0(xdimn,xdimn),f0(ntc,ntc))
    s=0.0;t=0.0;u=0.
    call shfunc( xdimn,nnode,s,t,u,shape,deriv)
    print *,'nnode=',nnode
    write(7,*)'elcod='
    write(7,*)elcod(1,:)
    write(7,*)elcod(2,:)
    do 4 idime=1,xdimn
       do 4 jdime=1,xdimn
          xj0(idime,jdime)=0.0
          do 4 inode=1,nnode
             xj0(idime,jdime)=xj0(idime,jdime)+        &
             deriv(idime,inode)*elcod(jdime,inode)
             4     continue

             djacb0=xj0(1,1)*xj0(2,2)-xj0(1,2)*xj0(2,1)

             !*** calcula la matriz inverse(F0)
             !
             F0(1,1)=  xj0(2,2)
             F0(1,2)= -xj0(1,2)
             F0(2,1)= -xj0(2,1)
             F0(2,2)=  xj0(1,1)
             write(7,*)'f0=',f0(1,1),f0(1,2)
             write(7,*)'f0=',f0(2,1),f0(2,2)
             !      G= Transpose(inverse(F0))*shape_sr*djacb0/djacb
             gmatx(1:ntc,:)=f0.x.shape_sr
             gmatx(1:ntc,:)=gmatx*djacb0/djacb
             !
             deallocate(shape,deriv,xj0,f0)
             end   subroutine gmatx_sr_p4




    subroutine getgauss ( ndimn,nnode,ngaus,posgp, weigp )

    !      ------  Obtains Gauss poin information

    !-------------------------------------------------------------------
    integer (ink) ndimn,nnode,ngaus
    integer (ink) iline,itria,iquad,ibrik,ipris,itetr,idimn,igaus,ig,ix,iy,iz,i,j,k
    real(irk) a1,b1,w1,a2,b2,w2,a,b,g,g1,g2,cnst3,zlegn
    real(irk),dimension(:,:) :: posgp
    real(irk),dimension(:) :: w(4),weigp
    integer(ink) LI16(16), LI9(9), LK16(16), LK9(9)
    DATA LK9/-1,-1,-1,0,0,0,1,1,1/, LI9/-1,0,1,-1,0,1,-1,0,1/
    DATA LK16/8*-1,8*1/, LI16/-1,-1,1,1,-1,-1,1,1,-1,-1,1,1,-1,-1,1,1/


    !      ------  First of all, obtain family at which elements belong

    iline=0
    itria=0
    iquad=0
    ibrik=0
    itetr=0
    ipris=0

    if  (ndimn==1) then
       iline=1
    else if (ndimn.eq.2) then
       if (nnode.eq. 4) iquad=1
       if (nnode.eq. 8) iquad=1
       if (nnode.eq. 9) iquad=1
       if (nnode.eq. 3) itria=1
       if (nnode.eq. 6) itria=1
       if (nnode.eq. 7) itria=1
       if (nnode.eq.15) itria=1
    else if (ndimn.eq.3) then
       if (nnode.eq. 4) itetr=1
       if (nnode.eq. 6) ipris=1
       if (nnode.eq.10) itetr=1
       if (nnode.eq. 8) ibrik=1
       if (nnode.eq.20) ibrik=1
       if (nnode.eq.27) ibrik=1
    endif

    !      ------  1D elements

    if  (iline.eq.1) then
       if (ngaus.eq.1) then
          posgp(1,1) = 1./2.
          weigp(1) = 1.
          return
       else  if(ngaus==2) then
          a=.2113248654
          posgp(1,1)=a
          posgp(1,2)=1-a
          weigp(1)=1./2.
          weigp(2)=1./2.
       else if(ngaus==3) then
          a=.1127016654
          posgp(1,1)=a
          posgp(1,2)=1-a
          posgp(1,3)=1./2.
          weigp(1)  =5./18.
          weigp(2)  =5./18.
          weigp(3)  =4./9.
       else
          write(*,*) 'No gauss rule for 1D elem. ngaus=',ngaus
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:getgauss','no gauss rule for 1D element, ngaus='//trim(diag_itoa(int(ngaus,i8))))   ! M1-03 R20
       endif
    ENDIF

    !      ------  2D triangular elements

    if  (itria.eq.1) then

       if (ngaus.eq.1) then
          DO idimn=1,ndimn
             posgp(idimn,1) = 1./3.
          enddo
          weigp(1) = 1./2.
          return
       else if(ngaus.eq.3) then
          DO igaus=1,ngaus
             weigp(igaus)=1/6.
          enddo
          posgp=0.5
          posgp(2,1)=0.0
          posgp(1,3)=0.0
          return
       else if (ngaus.eq.4) then   !  ------  O(h4) see OCZ Vol.I pp 176
          posgp(1,1)=1./3.         !          w div. by 2 to get Area OK
          posgp(2,1)=1./3.
          weigp(1)  = -27./96.
          posgp(1,2)=0.6
          posgp(2,2)=0.2
          posgp(1,3)=0.2
          posgp(2,3)=0.6
          posgp(1,4)=0.2
          posgp(2,4)=0.2
          DO ig=2,4
             weigp(ig)=25./96.
          enddo
       else if (ngaus==6) then

          POSGP(1,1)=0.091576213509771
          POSGP(1,2)=0.816847572980459
          POSGP(1,3)=0.091576213509771
          POSGP(1,4)=0.445948490915965
          POSGP(1,5)=0.108103018168070
          POSGP(1,6)=0.445948490915965
          POSGP(2,1)=0.091576213509771
          POSGP(2,2)=0.091576213509771
          POSGP(2,3)=0.816847572980459
          POSGP(2,4)=0.445948490915965
          POSGP(2,5)=0.445948490915965
          POSGP(2,6)=0.108103018168070
          W1=0.054975871827661
          W2=0.1116907948390055
          DO I=1,3
             J=I+3
             WEIGP(I)=W1
             WEIGP(J)=W2
          end do


       else if(ngaus.eq.7) then    !  ------  O(h6) see OCZ Vol.I
          posgp(1,1)=1./3.
          posgp(2,1)=1./3.
          weigp(1)=0.225/2.
          a1=0.0597158717
          b1=0.4701420641
          w1=0.1323941527 / 2.
          posgp(1,2)=a1
          posgp(2,2)=b1
          posgp(1,3)=b1
          posgp(2,3)=a1
          posgp(1,4)=b1
          posgp(2,4)=b1
          DO ig=2,4
             weigp(ig)=w1
          enddo
          a2=0.7974269853
          b2=0.1012865073
          w2=0.1259391805 / 2.
          posgp(1,5)=a2
          posgp(2,5)=b2
          posgp(1,6)=b2
          posgp(2,6)=a2
          posgp(1,7)=b2
          posgp(2,7)=b2
          DO ig=5,7
             weigp(ig)=w2
          enddo
       else
          write(*,*) ' Gauss rule not provided for Triang. ',ngaus
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:getgauss','no gauss rule for triangle, ngaus='//trim(diag_itoa(int(ngaus,i8))))   ! M1-03 R20
       endif

    ENDIF

    !      ------  2D quadrilateral elements

    if  (iquad.eq.1) then

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
          DO igaus=1,ngaus
             weigp(igaus)=1.00
          enddo
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
                POSGP(2,I)=G1*LI16(I)
             ELSE
                POSGP(2,I)=G2*LI16(I)
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
       else
          write(*,*) ' no gauss rule for quad ', ngaus
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:getgauss','no gauss rule for quad, ngaus='//trim(diag_itoa(int(ngaus,i8))))   ! M1-03 R20
       endif

    ENDIF

    !      ------  3D brick elements

    if  (ibrik.eq.1) then

       if (ngaus.eq.1) then
          weigp(1)   = 2.
          posgp(1,1) = 0.
          posgp(2,1) = 0.
          return
       else if(ngaus.eq.8) then
          zlegn      = 1./sqrt(3.0)
          igaus      = 0
          DO iz = -1,1,2
             DO iy = -1,1,2
                if (iy==-1) then
                   DO ix = -1,1,2
                      igaus=igaus+1
                      posgp(1,igaus) = zlegn*ix
                      posgp(2,igaus) = zlegn*iy
                      posgp(3,igaus) = zlegn*iz
                      weigp(igaus)   = 1.0
                   enddo
                elseif(iy==1) then
                   DO ix = 1,-1,-2
                      igaus=igaus+1
                      posgp(1,igaus) = zlegn*ix
                      posgp(2,igaus) = zlegn*iy
                      posgp(3,igaus) = zlegn*iz
                      weigp(igaus)   = 1.0
                   enddo
                endif
             enddo
          enddo
          return
       else if(ngaus.eq.27) then
          zlegn = sqrt(3.0/5.0)
          igaus = 0
          w(1)  = 5./9.
          w(2)  = 8./9.
          w(3)  = 5./9.
          DO iz = -1,1
             DO iy = -1,1
                DO ix = -1,1
                   igaus=igaus+1
                   posgp(1,igaus) = zlegn*ix
                   posgp(2,igaus) = zlegn*iy
                   posgp(3,igaus) = zlegn*iz
                   weigp(igaus)   = w(ix+2)*w(iy+2)*w(iz+2)
                enddo
             enddo
          enddo
          return
       else
          write(*,*) ' No gauss rule for brick with ngaus=',ngaus
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:getgauss','no gauss rule for brick, ngaus='//trim(diag_itoa(int(ngaus,i8))))   ! M1-03 R20
       endif

    ENDIF


    !      ------  3D thetraedral elements

    if  ( itetr.eq.1) then

       if (ngaus.eq.1) then
          DO idimn=1,ndimn
             posgp(idimn,1) = 0.25
          enddo
          weigp(1) = 1./6.
          return
       else if(ngaus.eq.4) then
          a = 0.58541020
          b = 0.13819660
          DO idimn=1,ndimn
             DO igaus=1,ngaus
                posgp(idimn,igaus) = b
                weigp(igaus)=1./24.
             enddo
             posgp(idimn,idimn) = a
          enddo
          return
       else   if(ngaus==5) then
          a=1./3.
          b=1./6.
          do  idimn=1,ndimn
             posgp(idimn,1)=1./4.
          end do
          weigp(1)=-0.8/6.
          do  i=2,5
             do  j=1,ndimn
                posgp(j,i)=b
                weigp(i)=0.45/6.
             end do
          end do
          posgp(1,3)=a
          posgp(2,4)=a
          posgp(3,5)=a
       else

          write(*,*) ' No gauss rule for TETR with ngaus=',ngaus
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:getgauss','no gauss rule for tetrahedron, ngaus='//trim(diag_itoa(int(ngaus,i8))))   ! M1-03 R20
       endif

    ENDIF

    !   ****** for 3D prism elements

    if  ( ipris.eq.1) then

       if (ngaus.eq.6) then
          posgp(1,1) = -.5
          posgp(2,1) = -sqrt(3.0)/6.
          posgp(3,1) = -1./sqrt(3.0)
          posgp(1,2) = .5
          posgp(2,2) = -sqrt(3.0)/6.
          posgp(3,2) = -1./sqrt(3.0)
          posgp(1,3) = 0.
          posgp(2,3) = sqrt(3.0)/3.
          posgp(3,3) = -1./sqrt(3.0)

          posgp(1,4) = -.5
          posgp(2,4) = -sqrt(3.0)/6.
          posgp(3,4) = 1./sqrt(3.0)
          posgp(1,5) = .5
          posgp(2,5) = -sqrt(3.0)/6.
          posgp(3,5) = 1./sqrt(3.0)
          posgp(1,6) = 0.
          posgp(2,6) = sqrt(3.0)/3.
          posgp(3,6) = 1./sqrt(3.0)

          weigp(1:6) = sqrt(3.0)/3.
          return

       else

          write(*,*) ' No gauss rule for TETR with ngaus=',ngaus
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:getgauss','no gauss rule for tetrahedron, ngaus='//trim(diag_itoa(int(ngaus,i8))))   ! M1-03 R20
       endif

    ENDIF


    end  subroutine getgauss


    subroutine shfunc  ( lndimn,nnode,s,t,u,shape,deriv)

    !      ------  Obtain shape functions at sampling point (x,y,z) and
    !              its derivatives

    !-------------------------------------------------------------------

    real (irk),intent(in)::s,t,u
    integer (ink), intent(in):: nnode,lndimn
    integer (ink) iline,itria,iquad,ibrik,itetr,ipris,inode,ii,jj,i,j,k
    real(irk) s1,t1,s2,t2,u2,ss,tt,uu,st,sst,stt,st2,s9,t9,  &
    r,x,y,x2,y2,fkk,gaus(3),lcop(3,8)
    real(irk) shape(:),deriv(:,:)
   


    !      ------  First of all, obtain family at which elements belong

    iline=0
    itria=0
    iquad=0
    ibrik=0
    itetr=0
    ipris=0

    if  (lndimn.eq.1) then
       iline = 1
    else if (lndimn.eq.2) then
       if (nnode.eq. 4) iquad=1
       if (nnode.eq. 8) iquad=1
       if (nnode.eq. 9) iquad=1
       if (nnode.eq. 3) itria=1
       if (nnode.eq. 6) itria=1
       if (nnode.eq. 7) itria=1
       if (nnode.eq.15) itria=1
    else if (lndimn.eq.3) then
       if (nnode.eq. 4) itetr=1
       if (nnode.eq.10) itetr=1
       if (nnode.eq. 8) ibrik=1
       if (nnode.eq.20) ibrik=1
       if (nnode.eq.27) ibrik=1
       if (nnode.eq. 6) ipris=1
    endif

    !      ------  Auxiliar variables

    s1 = s + 1.0
    t1 = t + 1.0
    s2 = s*2.0
    t2 = t*2.0
    u2 = u*2.0
    ss = s*s
    tt = t*t
    uu = u*u
    st = s*t
    sst=s*s*t
    stt=s*t*t
    st2=s*t*2.0
    s9 =s-1.0
    t9 =t-1.0

    !      ------  1D linear elements

    if  (iline.eq.1) then
       if (nnode==2) then
          shape(1)=1.-s
          shape(2)=s
          deriv(1,1)=-1.0
          deriv(1,2)= 1.0
          return
       else if(nnode==3)then
          s1=1.-s
          shape(1)=2.*s1*(s1-.5)
          shape(2)=2.*s*(s-.5)
          shape(3)=4.*s*s1
          deriv(1,1)=4.*s-3.
          deriv(1,2)=4.*s-1.
          deriv(1,3)=4.-8.*s
       else
          write(*,*) ' Message from shfunc '
          write(*,*) ' 1D element nnode=',nnode,' is not implem.'
       endif
    ENDIF

    !      ------  3D brick elements

    if  (ibrik.eq.1) then
       if (nnode==8) then
          gaus(1)=s
          gaus(2)=t
          gaus(3)=u
          do k=1,lndimn-1
             do j=1,4
                lcop(3,(k-1)*4+j)=(-1.)**k
             end do
             lcop(1,(k-1)*4+1)=-1.
             lcop(1,(k-1)*4+4)=-1.
             lcop(1,(k-1)*4+2)=1.
             lcop(1,(k-1)*4+3)=1.
             lcop(2,(k-1)*4+1)=-1.
             lcop(2,(k-1)*4+2)=-1.
             lcop(2,(k-1)*4+3)=1.
             lcop(2,(k-1)*4+4)=1.
          end do

          do inode=1,nnode
             shape(inode)=1.
             do j=1,lndimn
                shape(inode)=shape(inode)*(1.+gaus(j)*lcop(j,inode))/2.
             end do
          end do
          do  i=1,nnode
             do  j=1,lndimn
                ii=j+1
                if (ii.gt.lndimn)ii=ii-lndimn
                fkk=1.
                if (lndimn.eq.3) then
                   jj=j+2
                   if (jj.gt.lndimn)jj=jj-lndimn
                   fkk=1.+gaus(jj)*lcop(jj,i)
                endif
                deriv(j,i)=lcop(j,i)*(1.+gaus(ii)*lcop(ii,i))*     &
                fkk/2.**lndimn
    !if(ibrik==1.and.j==2.and.i==1)then
    !     write(7,*)'i=',i,'j=',j,'jj=',jj,'ii=',ii
    !     write(7,*)'lcop(j,i)=',lcop(j,i),'gaus=',gaus(ii),'lcop(ii,i)=',lcop(ii,i),'fkk=',fkk
    !    write(7,*)'deriv(j,i)=', deriv(j,i)
    ! endif
                
             end do
          end do

       else  if (nnode.eq.20) then
          shape( 1) = (1+s)*(1-t)*(1-u)*(s-t-u-2)*0.125
          deriv(1,1)= 0.125*(1-t)*(1-u)*(s2-t-u-1)
          deriv(2,1)= 0.125*(1+s)*(1-u)*(-s+t2+u+1)
          deriv(3,1)= 0.125*(1+s)*(1-t)*(-s+t+u2+1)
          shape( 2) = (1-tt)*(1+s)*(1-u)*0.25
          deriv(1,2)= 0.25*(1-tt)*(1-u)
          deriv(2,2)= 0.25*(-t2)*(1+s)*(1-u)
          deriv(3,2)= 0.25*(tt-1)*(1+s)
          shape( 3) = (1+s)*(1+t)*(1-u)*(s+t-u-2)*0.125
          deriv(1,3)= 0.125*(1+t)*(1-u)*(s2+t-u-1)
          deriv(2,3)= 0.125*(1+s)*(1-u)*(s+t2-u-1)
          deriv(3,3)= 0.125*(1+s)*(1+t)*(-s-t+u2+1)
          shape( 4) = (1-ss)*(1+t)*(1-u)*0.25
          deriv(1,4)= 0.25*(-s2)*(1+t)*(1-u)
          deriv(2,4)= 0.25*(1-ss)*(1-u)
          deriv(3,4)=-0.25*(1-ss)*(1+t)
          shape( 5) = (1-s)*(1+t)*(1-u)*(-s+t-u-2)*0.125
          deriv(1,5)= 0.125*(1+t)*(1-u)*(s2-t+u+1)
          deriv(2,5)= 0.125*(1-s)*(1-u)*(-s+t2-u-1)
          deriv(3,5)= 0.125*(1-s)*(1+t)*(s-t+u2+1)
          shape( 6) = (1-tt)*(1-s)*(1-u)*0.25
          deriv(1,6)=-0.25*(1-tt)*(1-u)
          deriv(2,6)=-0.25*(t2)*(1-s)*(1-u)
          deriv(3,6)=-0.25*(1-tt)*(1-s)
          shape( 7) = (1-s)*(1-t)*(1-u)*(-s-t-u-2)*0.125
          deriv(1,7)= 0.125*(1-t)*(1-u)*(s2+t+u+1)
          deriv(2,7)= 0.125*(1-s)*(1-u)*( s+t2+u+1)
          deriv(3,7)= 0.125*(1-s)*(1-t)*( s+t+u2+1)
          shape( 8) = (1-ss)*(1-t)*(1-u)*0.25
          deriv(1,8)=-0.25*(s2)*(1-t)*(1-u)
          deriv(2,8)=-0.25*(1-ss)*(1-u)
          deriv(3,8)=-0.25*(1-ss)*(1-t)
          shape( 9) = (1-uu)*(1+s)*(1-t)*0.25
          deriv(1,9)= 0.25*(1-uu)*(1-t)
          deriv(2,9)=-0.25*(1-uu)*(1+s)
          deriv(3,9)=-0.25*(u2)*(1+s)*(1-t)
          shape(10)  = (1-uu)*(1+s)*(1+t)*0.25
          deriv(1,10)= 0.25*(1-uu)*(1+t)
          deriv(2,10)= 0.25*(1-uu)*(1+s)
          deriv(3,10)=-0.25*(u2)*(1+s)*(1+t)
          shape(11)  = (1-uu)*(1-s)*(1+t)*0.25
          deriv(1,11)=-0.25*(1-uu)*(1+t)
          deriv(2,11)= 0.25*(1-uu)*(1-s)
          deriv(3,11)=-0.25*(u2)*(1-s)*(1+t)
          shape(12)  = (1-uu)*(1-s)*(1-t)*0.25
          deriv(1,12)=-0.25*(1-uu)*(1-t)
          deriv(2,12)=-0.25*(1-uu)*(1-s)
          deriv(3,12)=-0.25*(u2)*(1-s)*(1-t)
          shape(13)  = (1+s)*(1-t)*(1+u)*(s-t+u-2)*0.125
          deriv(1,13)= 0.125*(1-t)*(1+u)*(s2-t+u-1)
          deriv(2,13)= 0.125*(1+s)*(1+u)*(-s+t2-u+1)
          deriv(3,13)= 0.125*(1+s)*(1-t)*(s-t+u2-1)
          shape(14)  = (1-tt)*(1+s)*(1+u)*0.25
          deriv(1,14)=0.25*(1-tt)*(1+u)
          deriv(2,14)=-0.25*(t2)*(1+s)*(1+u)
          deriv(3,14)= 0.25*(1-tt)*(1+s)
          shape(15)  = (1+s)*(1+t)*(1+u)*(s+t+u-2)*0.125
          deriv(1,15)= 0.125*(1+t)*(1+u)*(s2+t+u-1)
          deriv(2,15)= 0.125*(1+s)*(1+u)*(s+t2+u-1)
          deriv(3,15)= 0.125*(1+s)*(1+t)*(s+t+u2-1)
          shape(16)  = (1-ss)*(1+t)*(1+u)*0.25
          deriv(1,16)=-0.25*(s2)*(1+t)*(1+u)
          deriv(2,16)= 0.25*(1-ss)*(1+u)
          deriv(3,16)= 0.25*(1-ss)*(1+t)
          shape(17)  = (1-s)*(1+t)*(1+u)*(-s+t+u-2)*0.125
          deriv(1,17)=-0.125*(1+t)*(1+u)*(-s2+t+u-1)
          deriv(2,17)= 0.125*(1-s)*(1+u)*(-s+t2+u-1)
          deriv(3,17)= 0.125*(1-s)*(1+t)*(-s+t+u2-1)
          shape(18)  = (1-tt)*(1-s)*(1+u)*0.25
          deriv(1,18)=-0.25*(1-tt)*(1+u)
          deriv(2,18)=-0.25*(t2)*(1-s)*(1+u)
          deriv(3,18)= 0.25*(1-tt)*(1-s)
          shape(19)  = (1-s)*(1-t)*(1+u)*(-s-t+u-2)*0.125
          deriv(1,19)=-0.125*(1-t)*(1+u)*(-s2-t+u-1)
          deriv(2,19)=-0.125*(1-s)*(1+u)*(-s-t2+u-1)
          deriv(3,19)= 0.125*(1-s)*(1-t)*(-s-t+u2-1)
          shape(20)  = (1-ss)*(1-t)*(1+u)*0.25
          deriv(1,20)=-0.25*(s2)*(1-t)*(1+u)
          deriv(2,20)=-0.25*(1-ss)*(1+u)
          deriv(3,20)= 0.25*(1-ss)*(1-t)
          return
       else
          write(*,*) ' No brick with ',nnode,' nodes in SHAPE '
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:shfunc','no shape function for brick, nnode='//trim(diag_itoa(int(nnode,i8))))   ! M1-03 R20
       endif

    ENDIF

    !      ------  Tethraedral elements

    if  (itetr.eq.1) then

       if  (nnode.eq.4) then
          shape(1)   = 1-s-t-u
          deriv(1,1) = -1.
          deriv(2,1) = -1.
          deriv(3,1) = -1.
          shape(2)   = s
          deriv(1,2) = 1.
          deriv(2,2) = 0.
          deriv(3,2) = 0.
          shape(3)   = t
          deriv(1,3) = 0.
          deriv(2,3) = 1.
          deriv(3,3) = 0.
          shape(4)   = u
          deriv(1,4) = 0.
          deriv(2,4) = 0.
          deriv(3,4) = 1.
          return
       else if (nnode.eq.10) then
          r = 1-s-t-u
          shape( 1)   = r*(2*r-1)
          deriv(1, 1) = 1-4*r
          deriv(2, 1) = 1-4*r
          deriv(3, 1) = 1-4*r
          shape( 2)   = 4*r*s
          deriv(1, 2) = 4*(r-s)
          deriv(2, 2) = -4*s
          deriv(3, 2) = -4*s
          shape( 3)   = s*(2*s-1)
          deriv(1, 3) = 4*s-1
          deriv(2, 3) = 0.
          deriv(3, 3) = 0.
          shape( 4)   = 4*s*t
          deriv(1, 4) = 4*t
          deriv(2, 4) = 4*s
          deriv(3, 4) = 0.
          shape( 5)   = t*(2*t-1)
          deriv(1, 5) = 0.
          deriv(2, 5) = 4*t-1
          deriv(3, 5) = 0.
          shape( 6)   = 4*r*t
          deriv(1, 6) = -4*t
          deriv(2, 6) = 4*(r-t)
          deriv(3, 6) = -4*t
          shape( 7)   = 4*r*u
          deriv(1, 7) = -4*u
          deriv(2, 7) = -4*u
          deriv(3, 7) = 4*(r-u)
          shape( 8)   = 4*s*u
          deriv(1, 8) = 4*u
          deriv(2, 8) = 0.
          deriv(3, 8) = 4*s
          shape( 9)   = 4*t*u
          deriv(1, 9) = 0.
          deriv(2, 9) = 4*u
          deriv(3, 9) = 4*t
          shape(10)   = u*(u2-1)
          deriv(1,10) = 0.
          deriv(2,10) = 0.
          deriv(3,10) = 4*u-1
          return
       else
          write(*,*) ' No elem. with ',nnode,' in SHAPE '
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:shfunc','no shape function for tetrahedron, nnode='//trim(diag_itoa(int(nnode,i8))))   ! M1-03 R20
       endif

    ENDIF

    !     ------  2D elements

    if  (itria.eq.1 ) then

       if  (nnode.eq.3) then
          shape (1)   = 1. -s -t
          deriv (1,1) = -1.
          deriv (2,1) = -1.
          shape (2)   = s
          deriv (1,2) = 1.
          deriv (2,2) = 0.
          shape (3)   = t
          deriv (1,3) = 0.
          deriv (2,3) = 1.
          return
       else if (nnode.eq.6) then
          shape(1) = (1-s-t)*(1-s2-t2)
          shape(4) = 4*(1-s-t)*s
          shape(2) = s*(s2-1)
          shape(5) = 4*s*t
          shape(3) = t*(t2-1)
          shape(6) = 4*t*(1-s-t)
          deriv(1,1) =  -3 + 4*s + 4*t
          deriv(2,1) =   deriv(1,1)
          deriv(1,4) =   4*(1-t-s2)
          deriv(2,4) =  -4*s
          deriv(1,2) =   4*s-1
          deriv(2,2) =   0.
          deriv(1,5) =   4*t
          deriv(2,5) =   4*s
          deriv(1,3) =   0.
          deriv(2,3) =   4*t-1
          deriv(1,6) =  -4*t
          deriv(2,6) =   4*(1-s-t2)
       else if (nnode.eq.7) then
          shape(7) =  27*s*t*(1-s-t)
          x=1./3.
          y=1./3.
          x2=2.*x
          y2=2.*y
          shape(1) = (1-s-t)*(1-s2-t2)- shape(7)*(1-x-y)*(1-x2-y2)
          shape(2) = 4*(1-s-t)*s      - shape(7)*4*(1-x-y)*x
          shape(3) = s*(s2-1)         - shape(7)*x*(x2-1)
          shape(4) = 4*s*t            - shape(7)*4*x*y
          shape(5) = t*(t2-1)         - shape(7)*y*(y2-1)
          shape(6) = 4*t*(1-s-t)      - shape(7)*4*y*(1-x-y)
          deriv(1,7) =   27*t -  54*st - 27*tt
          deriv(1,1) =  -3+4*s+4*t  - deriv(1,7)*(1-x-y)*(1-x2-y2)
          deriv(1,2) =   4*(1-t-s2) - deriv(1,7)*4*(1-x-y)*x
          deriv(1,3) =   4*s-1      - deriv(1,7)*x*(x2-1)
          deriv(1,4) =   4*t        - deriv(1,7)*4*x*y
          deriv(1,5) =   0.         - deriv(1,7)*y*(y2-1)
          deriv(1,6) =  -4*t        - deriv(1,7)*4*y*(1-x-y)
          deriv(2,7) =   27*s -  54*st -27*ss
          deriv(2,1) =  -3+4*s+4*t  - deriv(2,7)*(1-x-y)*(1-x2-y2)
          deriv(2,2) =  -4*s        - deriv(2,7)*4*(1-x-y)*x
          deriv(2,3) =   0.         - deriv(2,7)*x*(x2-1)
          deriv(2,4) =   4*s        - deriv(2,7)*4*x*y
          deriv(2,5) =   4*t-1      - deriv(2,7)*y*(y2-1)
          deriv(2,6) =   4*(1-s-t2) - deriv(2,7)*4*y*(1-x-y)
       else
          write(*,*) ' No SHAPE for Triangle nnode= ',nnode
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:shfunc','no shape function for triangle, nnode='//trim(diag_itoa(int(nnode,i8))))   ! M1-03 R20
       endif

    ENDIF

    !      ------  Quads :  Q4

    if  (iquad.eq.1) then

       if  (nnode.eq.4) then
          shape(1) = (1-t-s+st)*0.25
          shape(2) = (1-t+s-st)*0.25
          shape(3) = (1+t+s+st)*0.25
          shape(4) = (1+t-s-st)*0.25
          deriv(1,1) = (-1+t)*0.25
          deriv(1,2) = (+1-t)*0.25
          deriv(1,3) = (+1+t)*0.25
          deriv(1,4) = (-1-t)*0.25
          deriv(2,1) = (-1+s)*0.25
          deriv(2,2) = (-1-s)*0.25
          deriv(2,3) = (+1+s)*0.25
          deriv(2,4) = (+1-s)*0.25
       else  if(nnode==8) then
          SHAPE(1)=(-1.0+ST+SS+TT-SST-STT)/4.0
          SHAPE(5)=(1.0-T-SS+SST)/2.0
          SHAPE(2)=(-1.0-ST+SS+TT-SST+STT)/4.0
          SHAPE(6)=(1.0+S-TT-STT)/2.0
          SHAPE(3)=(-1.0+ST+SS+TT+SST+STT)/4.0
          SHAPE(7)=(1.0+T-SS-SST)/2.0
          SHAPE(4)=(-1.0-ST+SS+TT+SST-STT)/4.0
          SHAPE(8)=(1.0-S-TT+STT)/2.0
          !
          DERIV(1,1)=(T+S2-ST2-TT)/4.0
          DERIV(1,5)=-S+ST
          DERIV(1,2)=(-T+S2-ST2+TT)/4.0
          DERIV(1,6)=(1.0-TT)/2.0
          DERIV(1,3)=(T+S2+ST2+TT)/4.0
          DERIV(1,7)=-S-ST
          DERIV(1,4)=(-T+S2+ST2-TT)/4.0
          DERIV(1,8)=(-1.0+TT)/2.0
          DERIV(2,1)=(S+T2-SS-ST2)/4.0
          DERIV(2,5)=(-1.0+SS)/2.0
          DERIV(2,2)=(-S+T2-SS+ST2)/4.0
          DERIV(2,6)=-T-ST
          DERIV(2,3)=(S+T2+SS+ST2)/4.0
          DERIV(2,7)=(1.0-SS)/2.0
          DERIV(2,4)=(-S+T2+SS-ST2)/4.0
          DERIV(2,8)=-T+ST
       else
          write(*,*) ' no shape function for quad ', nnode
          call diag_abort('INTERNAL',EXIT_INTERNAL,'Elements.f90:shfunc','no shape function for quad, nnode='//trim(diag_itoa(int(nnode,i8))))   ! M1-03 R20
       endif

    endif
    !  prism element !pr6
    if  (ipris.eq.1) then
       gaus(1)=s
       gaus(2)=t
       gaus(3)=u

       shape(1)=.5*(1-u)*(1./3.-.5*s-sqrt(3.)/6.*t)
       shape(2)=.5*(1-u)*(1./3.+.5*s-sqrt(3.)/6.*t)
       shape(3)=.5*(1-u)*(1./3.+sqrt(3.)/3.*t)
       shape(4)=.5*(1+u)*(1./3.-.5*s-sqrt(3.)/6.*t)
       shape(5)=.5*(1+u)*(1./3.+.5*s-sqrt(3.)/6.*t)
       shape(6)=.5*(1+u)*(1./3.+sqrt(3.)/3.*t)

       deriv(1,1)=-.25*(1-u)
       deriv(2,1)=-sqrt(3.)/12.*(1-u)
       deriv(3,1)=-.5*(1./3.-.5*s-sqrt(3.)/6.*t)

       deriv(1,2)= .25*(1-u)
       deriv(2,2)=-sqrt(3.)/12.*(1-u)
       deriv(3,2)=-.5*(1./3.+.5*s-sqrt(3.)/6.*t)

       deriv(1,3)= 0.
       deriv(2,3)=sqrt(3.)/6.*(1-u)
       deriv(3,3)=-.5*(1./3.+sqrt(3.)/3.*t)

       deriv(1,4)=-.25*(1+u)
       deriv(2,4)=-sqrt(3.)/12.*(1+u)
       deriv(3,4)=.5*(1./3.-.5*s-sqrt(3.)/6.*t)

       deriv(1,5)= .25*(1+u)
       deriv(2,5)=-sqrt(3.)/12.*(1+u)
       deriv(3,5)= .5*(1./3.+.5*s-sqrt(3.)/6.*t)

       deriv(1,6)= 0.
       deriv(2,6)=sqrt(3.)/6.*(1+u)
       deriv(3,6)= .5*(1./3.+sqrt(3.)/3.*t)
    endif



    end subroutine shfunc

    subroutine shfunsr(ikind,s,t,u,shape_sr)
    integer(ink) ikind
    real(irk) s,t,u,shape_sr(:,:)
    !
    shape_sr=0.0
    if (ikind==3) then  !! 2-D
       shape_sr(1,1)=s  !! Simo & Rifai for bending
       shape_sr(1,2)=t
       shape_sr(2,3)=s
       shape_sr(2,4)=t
       shape_sr(3,5)=s
       shape_sr(3,6)=t
       shape_sr(1,7)=s*t
       shape_sr(2,8)=s*t
       shape_sr(3,9)=s*t
    elseif(ikind==5.or.ikind==16) then   !! 2-D
       shape_sr(1,1)=s  !! Simo & Rifai for bending
       shape_sr(2,2)=t
       shape_sr(3,3)=s
       shape_sr(3,4)=t
       !    if(special=='BC')then  !! Simo & Rifai for Bending and Incompressible
       shape_sr(1,5)=s*t
       shape_sr(2,6)=s*t
       shape_sr(3,7)=s*t
       shape_sr(1,8)=3*(s**2-1.)
       shape_sr(2,9)=3*(t**2-1.)
       shape_sr(3,10)=3*(s**2-1.)
       shape_sr(3,11)=3*(t**2-1.)
       !    end if
    else if(ikind==9.or.ikind==18) then        !! 3-D
       shape_sr(1,1)=s  !! Simo & Rifai for bending
       shape_sr(2,2)=t
       shape_sr(3,3)=u
       shape_sr(4,4)=s
       shape_sr(4,5)=t
       shape_sr(5,6)=t
       shape_sr(5,7)=u
       shape_sr(6,8)=s
       shape_sr(6,9)=u

       !    if(special=='BC')then  !! Simo & Rifai for Bending and Incompressible
       shape_sr(4,10)=s*u
       shape_sr(4,11)=t*u
       shape_sr(5,12)=s*t
       shape_sr(5,13)=s*u
       shape_sr(6,14)=t*s
       shape_sr(6,15)=t*u

       shape_sr(1,16)=s*t
       shape_sr(1,17)=s*u
       shape_sr(2,18)=s*t
       shape_sr(2,19)=t*u
       shape_sr(3,20)=s*u
       shape_sr(3,21)=t*u

       shape_sr(4,22)=s*t
       shape_sr(5,23)=t*u
       shape_sr(6,24)=s*u


       shape_sr(1,25)=s*t*u
       shape_sr(2,26)=s*t*u
       shape_sr(3,27)=s*t*u
       shape_sr(4,28)=s*t*u
       shape_sr(5,29)=s*t*u
       shape_sr(6,30)=s*t*u

       !    end if
    endif
    end subroutine shfunsr
    !!!!*************
    subroutine shfunsrc(ikind,s,t,u,shape_sr,special)
    character(10) special
    integer(ink) ikind
    real(irk) s,t,u,shape_sr(:,:)
    !
    shape_sr=0.0

    if (ikind==3) then  !! 2-D
       shape_sr(1,1)=s  !! Simo & Rifai for bending
       shape_sr(1,2)=t
       shape_sr(2,3)=s
       shape_sr(2,4)=t
       shape_sr(3,5)=s
       shape_sr(3,6)=t
       if (special=='BC')then
          shape_sr(1,7)=s*t
          shape_sr(2,8)=s*t
          shape_sr(3,9)=s*t
       endif
    elseif(ikind==5.or.ikind==16) then   !! 2-D        shape_sr(1,1)=s  !! Simo & Rifai for bending
       shape_sr(2,2)=t
       shape_sr(3,3)=s
       shape_sr(3,4)=t
       if (special=='BC')then  !! Simo & Rifai for Bending and Incompressible
       shape_sr(1,5)=s*t
       shape_sr(2,6)=s*t
       shape_sr(3,7)=s*t
    end if
 else if(ikind==9.or.ikind==18) then        !! 3-D
    shape_sr(1,1)=s  !! Simo & Rifai for bending
    shape_sr(2,2)=t
    shape_sr(3,3)=u
    shape_sr(4,4)=s
    shape_sr(4,5)=t
    shape_sr(5,6)=t
    shape_sr(5,7)=u
    shape_sr(6,8)=s
    shape_sr(6,9)=u

    if (special=='BC')then  !! Simo & Rifai for Bending and Incompressible
    shape_sr(4,10)=s*u
    shape_sr(4,11)=t*u
    shape_sr(5,12)=s*t
    shape_sr(5,13)=s*u
    shape_sr(6,14)=t*s
    shape_sr(6,15)=t*u

    shape_sr(1,16)=s*t
    shape_sr(1,17)=s*u
    shape_sr(2,18)=s*t
    shape_sr(2,19)=t*u
    shape_sr(3,20)=s*u
    shape_sr(3,21)=t*u

    shape_sr(4,22)=s*t
    shape_sr(5,23)=t*u
    shape_sr(6,24)=s*u


    shape_sr(1,25)=s*t*u
    shape_sr(2,26)=s*t*u
    shape_sr(3,27)=s*t*u
    shape_sr(4,28)=s*t*u
    shape_sr(5,29)=s*t*u
    shape_sr(6,30)=s*t*u

 end if
endif
end subroutine shfunsrc
!!!!*************

!  for mapped infinite elements
    subroutine jacob_inf (ielem, edimn, nnode, elcod, deriv_inf, deriv, &
    cartd, djacb  )

    !      ------  Obtains : gauss points global coordinates,
    !                        determinant of jacobian matrix
    !                        cartesian derivatives of shape functions
    !
    integer (ink) ielem,edimn,nnode, idimn,jdimn,inode,i,j,ip1,ip2,jp1,jp2
    real (irk) djacb
    real (irk) cartd(:,:), deriv_inf(:,:), deriv(:,:), elcod(:,:),&
    xjacm(edimn,edimn), xjaci(edimn,edimn)

    !      ------  Obtain jacobian matrix
    DO idimn=1,edimn
       DO jdimn=1,edimn
          xjacm(idimn,jdimn)=0.0
          DO inode=1,nnode
             xjacm(idimn,jdimn)=xjacm(idimn,jdimn)+        &
             deriv_inf(idimn,inode)*elcod(jdimn,inode)
          enddo
       enddo
    enddo

    !      ------  Get determinant and inverse
    if (edimn==1) then

       djacb=xjacm(1,1)
       xjaci(1,1)=1./djacb

    else IF (edimn.eq.2) then
       djacb=xjacm(1,1)*xjacm(2,2)-xjacm(1,2)*xjacm(2,1)
       if  (djacb.le.0.0) then
          write(7,*)' Jacob is less or equal to zero at elm. ',djacb, ielem,'nnode=',nnode
           write(7,*)'edimn=',edimn
          do inode=1,nnode
           write(7,*)    elcod(:,inode)
          end do
          !       stop
       endif
       xjaci(1,1) =  xjacm(2,2)/djacb
       xjaci(2,2) =  xjacm(1,1)/djacb
       xjaci(1,2) = -xjacm(1,2)/djacb
       xjaci(2,1) = -xjacm(2,1)/djacb
    ELSE IF (edimn.eq.3) then
       call det3 (xjacm,djacb)
       if  (djacb.le.0.0) then
          write(7,*) ' Jacob is zero at elm. ', ielem,'djacb=',djacb
          write(7,*)'xjacm1=',xjacm(1,:)
          write(7,*)'xjacm2=',xjacm(2,:)
          write(7,*)'xjacm3=',xjacm(3,:)
          !      do inode=1,nnode
          !      write(7,*)   elcod(:,inode)
          !     end do
          !     write(7,*) 'djacb=',djacb
          !              stop
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
    ENDIF

    !     ------  Obtain cartesian derivatives

    DO idimn=1,edimn
       DO inode=1,nnode
          cartd(idimn,inode)=0.0
          DO jdimn=1,edimn
             cartd(idimn,inode)=cartd(idimn,inode)+        &
             xjaci(idimn,jdimn)*deriv(jdimn,inode)
          enddo
       enddo
    enddo

    end subroutine jacob_inf
    !end of mapped infinite elements
    subroutine jacob(ielem, edimn, nnode, elcod, deriv,cartd, djacb,xjaci  )

    !      ------  Obtains : gauss points global coordinates,
    !                        determinant of jacobian matrix
    !                        cartesian derivatives of shape functions
    !
    integer (ink) ielem,edimn,nnode, idimn,jdimn,inode,i,j,ip1,ip2,jp1,jp2
    real (irk) djacb
    real (irk) cartd(:,:), deriv(:,:), elcod(:,:),xjacm(edimn,edimn),xjaci(:,:)

    !      ------  Obtain jacobian matrix
    DO idimn=1,edimn
       DO jdimn=1,edimn
          xjacm(idimn,jdimn)=0.0
          DO inode=1,nnode
             xjacm(idimn,jdimn)=xjacm(idimn,jdimn)+        &
             deriv(idimn,inode)*elcod(jdimn,inode)
          enddo
       enddo
    enddo

    !      ------  Get determinant and inverse
    if (edimn==1) then

       djacb=xjacm(1,1)
       xjaci(1,1)=1./djacb

    else IF (edimn.eq.2) then
       djacb=xjacm(1,1)*xjacm(2,2)-xjacm(1,2)*xjacm(2,1)
       if  (djacb.le.0.0) then
           write(7,*)' Jacob is less or equal to zero at elm. ',djacb, ielem,'nnode=',nnode
           write(7,*)'edimn=',edimn
          do inode=1,nnode
             write(7,*)    elcod(:,inode)
          end do
  !        stop
       endif
       xjaci(1,1) =  xjacm(2,2)/djacb
       xjaci(2,2) =  xjacm(1,1)/djacb
       xjaci(1,2) = -xjacm(1,2)/djacb
       xjaci(2,1) = -xjacm(2,1)/djacb
    ELSE IF (edimn.eq.3) then
       call det3 (xjacm,djacb)
       !write(7,*)'ielem=',ielem,'jacob=',djacb
       if  (djacb.le.0.0) then
          write(7,*) ' Jacob is zero at elm. ', ielem
        !  write(7,*)element(ielem)%field(1)%lnods_f
                do inode=1,nnode
                write(7,*)   elcod(:,inode)
               end do
               write(7,*) 'djacb=',djacb
               write(7,*)'xjacm=',xjacm(1,:)
               write(7,*)'xjacm=',xjacm(2,:)
               write(7,*)'xjacm=',xjacm(3,:)
               write(7,*)'deriv='
               do inode=1,nnode
                write(7,*)   deriv(:,inode)
               end do
               
    !                    stop
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
    ENDIF

    !     ------  Obtain cartesian derivatives

    DO idimn=1,edimn
       DO inode=1,nnode
          cartd(idimn,inode)=0.0
          DO jdimn=1,edimn
             cartd(idimn,inode)=cartd(idimn,inode)+        &
             xjaci(idimn,jdimn)*deriv(jdimn,inode)
          enddo
       enddo
    enddo

    end subroutine jacob

    subroutine det3 ( a , deter )

    !     ------  Obtains the determinant of a 3 * 3 matrix

    !-------------------------------------------------------------------

    real(irk) deter,a(3,3)

    deter = a(1,1)*(a(2,2)*a(3,3)-a(2,3)*a(3,2))  -   &
    a(1,2)*(a(2,1)*a(3,3)-a(2,3)*a(3,1))  +   &
    a(1,3)*(a(2,1)*a(3,2)-a(2,2)*a(3,1))
    end  subroutine det3

    subroutine normal_local_inc(ndimn,xnode,elcod,elcod_local)
    integer(ink) index,nnode,edimn,order_int,ngaus,ig,ndimn,xnode
    real   (irk) elcod(:,:),weigp,aa,elcod_local
    real   (irk),allocatable::deriv(:,:),s(:,:),a3(:)
    real   (irk),allocatable::shape(:),rotation(:)
    allocate(rotation(ndimn))
    index=1
    nnode=2
    if (ndimn==3) then

       if (xnode==8) then
          index=5
          nnode=4
       elseif(xnode==6) then
          index=3
          nnode=3
       endif

    endif
    edimn=ndimn-1
    order_int=elkn(index)%el_field(1)%order_intrules(1)
    ngaus=elkn(index)%ggaus(order_int)%ngaus
    allocate(shape(nnode),deriv(edimn,nnode))
    allocate(s(ndimn,ndimn),a3(ndimn))
    rotation=0.
    do ig=1,ngaus
       shape=elkn(index)%ggaus(order_int)%shape(:,ig)
       deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
       weigp=elkn(index)%ggaus(order_int)%weigp(ig)
       s(1:edimn,:)=MATMUL(deriv,transpose(elcod(:,1:nnode)))
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
    rotation=rotation/sqrt(sum(rotation**2)) !p42010
    if (ndimn==3) then
       do ig=1,nnode
          elcod(:,ig+nnode)=elcod(:,ig)+rotation*elcod_local
       end do
    else
       elcod(:,4)=elcod(:,1)+rotation*elcod_local
       elcod(:,3)=elcod(:,2)+rotation*elcod_local
       
    endif

    deallocate(shape,deriv,s,a3,rotation)

    end subroutine normal_local_inc

    subroutine normal_local_plate(index,ndimn,elcod,rotation)
    integer(ink) index,nnode,edimn,order_int,ngaus,ig,ndimn
    real   (irk) elcod(:,:),weigp,aa,rotation(:)
    real   (irk),allocatable::deriv(:,:),s(:,:),a3(:)
    real   (irk),allocatable::shape(:)
    edimn=elkn(index)%ndimn
    nnode=elkn(index)%nnode
    order_int=elkn(index)%el_field(1)%order_intrules(1)
    ngaus=elkn(index)%ggaus(order_int)%ngaus
    allocate(shape(nnode),deriv(edimn,nnode))
    allocate(s(ndimn,ndimn),a3(ndimn))
    rotation=0.
    do ig=1,ngaus
       shape=elkn(index)%ggaus(order_int)%shape(:,ig)
       deriv=elkn(index)%ggaus(order_int)%deriv(:,:,ig)
       weigp=elkn(index)%ggaus(order_int)%weigp(ig)
       s(1:edimn,:)=MATMUL(deriv,transpose(elcod(:,1:nnode)))
       if (ndimn.eq.3) then
          s(3,1)=s(1,2)*s(2,3)-s(2,2)*s(1,3)
          s(3,2)=s(1,3)*s(2,1)-s(1,1)*s(2,3)
          s(3,3)=s(1,1)*s(2,2)-s(1,2)*s(2,1)
       else
          s(2,1)=-s(1,2)
          s(2,2)=s(1,1)
       endif
       a3=s(ndimn,:)**2
       aa=sqrt(sum(a3))
       s(ndimn,:)=s(ndimn,:)/aa
       a3=s(ndimn,:)
       rotation=rotation+a3
    end do
    rotation=rotation/ngaus

    rotation=rotation/sqrt(sum(rotation**2)) !p42010

    deallocate(shape,deriv,s,a3)

    end subroutine normal_local_plate

    end  module elements

