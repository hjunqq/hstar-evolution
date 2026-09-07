    module prescribed

    use yl_diag
    use yl_diag_registry
    use variable_types
    use global_var
    use meshfine
    use applied_load, only: ntcurve   ! M1-03: itcurve must refer to a curve read by external_load_1

    implicit none

    integer(ink) ndofix,nfixsets  !20230216,nbackdT=2.and.itcurve=0,反演边界温度

    type freedom_prescribe
       integer(ink) itcurve,mfixset                  !associated time curve,温度插值组数（20231130）
       integer(ink) ifixvar,ifixvar0,jfixvar         !hxl2006 MIF ,jfixvar（定义水压力水头计算的方向）
       integer(ink) ldofix                   !list of global dofs
       integer(ink) ifixset                  ! 属于第几组未知温度 20230216
       real(irk)    vdofix,gamaw                   !prescribed values,gamaw（水溶重，用于由水头计算水压力）
       real(irk)    rdofix                   !fluxes or reactios
       integer(ink) nodfix                   !associated node
       integer(ink) lnefix                   !number of associated elements
       integer(ink) outfix                   !indicates whether the reaction will be recorded
       real(irk)    bfrecoord                !hxl2006 MIF
       integer(ink),pointer::leldofix(:)     !element No. of lnefix elements
       integer(ink),pointer::levdofix(:)     !associated  dofn in leldofix element
       integer(ink),pointer::lefdofix(:)     !associated field in leldofix element
       integer(ink),pointer::listep(:)       !for expolation points
       real(irk),   pointer::value_ext(:,:)
       integer(ink),pointer::ldofixb(:)      !自由度组 !hxl2006 MIF
       integer(ink),pointer::lnofixb(:)      !节点组
       integer(ink),pointer::mlist(:)      !用于表面节点温度插值特征点列表（20231130）
       real(irk),   pointer::rintf(:)      !表面节点温度由插值特征点温度插值系数（20231130）
       
    end type freedom_prescribe
    type(freedom_prescribe),allocatable::prescrib(:)

    contains

    subroutine prescrib_set

    character (50)text
    character(10)fieldid
    integer(ink) ifixvar,nfixnods,itcurve,igroup,ielgroup,jblks,tfixvar,ipoin, &
                 itotv,ig,mgroup,nextr,i0,ifixvar0,ifixset,ifixnods,idofn,lnefix,ielem, &
                 nrfields,index,jelem,outfix,ifield,nnode,ndofn,ldofn,inode,lnode,nline,&
    nelink,iel,jel,jfixvar,iphase,igaps,ipairs,ndofix0,idimn,mfixset,idofix  !20231130
    real   (irk) gamawx  !20230402
    integer(ink),allocatable::list_fix(:),listep(:)
    integer(ink),pointer::lnods(:),listdof(:)
    real(irk)   ,allocatable::val_fix(:),normal(:),disg(:) 
    
    type(freedom_prescribe),allocatable::prescribx(:)

    integer(ink) ilaymif,jpoin    !hxl2006 MIF
    integer(ink),allocatable::frecoord(:),ldofx(:),lnofx(:)
    real   (irk),allocatable::xyzx(:)

    if (allocated(iffix))deallocate(iffix)
    if (allocated(fixed))deallocate(fixed)
    allocate(iffix(ntotv),fixed(ntotv))
    iffix=5   !20171201
    fixed=0.0_irk
    if(state_change==0)then
    DO igroup = 1,ngroup
       if  (appear(igroup).gt.0) then
          index = group(igroup)%index
          DO ielgroup = 1, group(igroup)%nelgroup
             ielem = group(igroup)%list(ielgroup)
             if  (ice0(ielem)==0)then
                listdof => element(ielem)%ldofs
                iffix(listdof)=0
             endif
          end do
          nullify(listdof)
       endif
    END DO
    elseif(state_change==1)then
         DO igroup = 1,ngroup
       if  (appear(igroup).gt.0) then
          index = group(igroup)%index
           nrfields=group(igroup)%nrfields
           fieldid=group(igroup)%fieldid
           if(nrfields==2.and.fieldid=='UW')then
        iphase=state_change_process(igroup,iblks)
        if(iphase==1)then
          DO ielgroup = 1, group(igroup)%nelgroup
             ielem = group(igroup)%list(ielgroup)
             if  (ice0(ielem)==0)then
                listdof=>element(ielem)%field(1)%ldofs_f
                iffix(listdof)=0
             endif
          end do
          nullify(listdof)
        elseif(iphase==3)then  
           DO ielgroup = 1, group(igroup)%nelgroup
             ielem = group(igroup)%list(ielgroup)
             if  (ice0(ielem)==0)then
                listdof=>element(ielem)%field(2)%ldofs_f
                iffix(listdof)=0
             endif
          end do
          nullify(listdof) 
        elseif(iphase==2)then  
                  do ifield=1,nrfields
          DO ielgroup = 1, group(igroup)%nelgroup
             ielem = group(igroup)%list(ielgroup)
             if  (ice0(ielem)==0)then
                listdof=>element(ielem)%field(ifield)%ldofs_f
                iffix(listdof)=0
             endif
          end do
          nullify(listdof)
                 end do
        endif  !iphase
           else  !if(nrfields/=2.or.fieldid=='UW')then      
                  DO ielgroup = 1, group(igroup)%nelgroup
                  ielem = group(igroup)%list(ielgroup)
                  if  (ice0(ielem)==0)then
                  listdof => element(ielem)%ldofs
                   iffix(listdof)=0
                  endif
                  end do
                  nullify(listdof)
           endif
        
        
       endif  !appear
    END DO !igroup
     
     endif !state_change
    if  (rmesh>0.and.nelem1>0)then
       DO igroup=1,ngroup
          if  (appear(igroup).gt.0) then
             index=group(igroup)%index
             DO ielgroup=1,group1(igroup)%nelgroup
                ielem=group1(igroup)%list(ielgroup)
                if  (jce1(ielem)==0)then
                   listdof=>element1(ielem)%field(1)%ldofs_f
                   iffix(listdof)=0
                      endif
                end do   !! ielgroup
                nullify(listdof)
             endif
          END DO  !! igroup
       endif
       if  (rmesh>1.and.nelem2>0)then
          DO igroup = 1,ngroup
             if  (appear(igroup).gt.0) then
                index = group(igroup)%index
                DO ielgroup = 1, group2(igroup)%nelgroup
                   ielem = group2(igroup)%list(ielgroup)
                   listdof => element2(ielem)%field(1)%ldofs_f
                   iffix(listdof)=0
                end do   !! ielgroup
                nullify(listdof)
             endif
          END DO  !! igroup
       endif
      
        if(block_stab==1.and.ebody==1)then  !2015/11/17
        do igaps=1,ngaps
            do ipairs=1,gaps(igaps)%npairs
            iffix(nodfn(:,gaps(igaps)%pairnode(1,ipairs)))=0
            iffix(nodfn(:,gaps(igaps)%pairnode(2,ipairs)))=0
            end do
        end do
        endif  !2015/11/17
       

       if  (restart==1)   then
          do jblks=1,iblks-1
             read(punit,*)text
             read(punit,*)nfixsets,nline
             do ifixset=1,nline
                read(punit,*)text
             end do
          end do
       end if
       if (meshc==1.or.rmesh/=0)rewind(punit)
       if(Bparameter/=0)rewind(punit)  !20190810
       
  !!!!20231130     
    if(nbackdT==2) then  !20231130    
        
       read(punit,*)text
       read(punit,*)nfixsets,nline
       read(punit,*)ifixvar,ifixvar0,nfixnods,itcurve,tfixvar,outfix,jfixvar,gamawx,nextr  !20230402
       ndofix=nfixnods
       allocate(prescribx(ndofix))
        do idofix=1,ndofix
        read(punit,*)i0,ipoin,mfixset
         idofn=nodfn(lmdofn(ifixvar),ipoin)
         iffix(idofn)=1
        allocate(prescribx(idofix)%mlist(mfixset),prescribx(idofix)%rintf(mfixset))
        read(punit,*)prescribx(idofix)%mlist
        read(punit,*)prescribx(idofix)%rintf
        
             prescribx(idofix)%mfixset=mfixset
             !prescribx(idofix)%ifixset=ifixset  !20230216
             prescribx(idofix)%itcurve=itcurve
             prescribx(idofix)%ifixvar=ifixvar
             prescribx(idofix)%ldofix=idofn
             prescribx(idofix)%nodfix=1
             prescribx(idofix)%vdofix=0.
             prescribx(idofix)%outfix=0
             prescribx(idofix)%jfixvar=0
        end do
       
    else  !20231130 
       read(punit,*,iostat=yl_ios,iomsg=yl_msg)text
       call diag_check_read(yl_ios,yl_msg,RD_PRE_prescrib_set_title_1,0)
       read(punit,*,iostat=yl_ios,iomsg=yl_msg)nfixsets,nline
       call diag_check_read(yl_ios,yl_msg,RD_PRE_prescrib_set_set_count,0)
       ndofix=0
       do ifixset=1,nfixsets
          print *,'ifixset=',ifixset,'type_abc=',type_abc
          if (type_abc=='MIF')read(punit,*,iostat=yl_ios,iomsg=yl_msg)ifixvar,ifixvar0,nfixnods,itcurve,tfixvar,outfix,jfixvar,gamawx,nextr  !20230402
          if (type_abc=='MIF')call diag_check_read(yl_ios,yl_msg,RD_PRE_prescrib_set_reached_only_Prescrib_213,ifixset)
          if (type_abc/='MIF')read(punit,*,iostat=yl_ios,iomsg=yl_msg)ifixvar,nfixnods,itcurve,tfixvar,outfix,jfixvar,gamawx,nextr ! 20230402
          if (type_abc/='MIF')call diag_check_read(yl_ios,yl_msg,RD_PRE_prescrib_set_set_header,ifixset)
          ! M1-03 set header guard: nfixnods sizes list_fix, ifixvar indexes lmdofn, itcurve indexes tcurves (0 = no curve, R18)
          yl_idx=RD_PRE_prescrib_set_set_header
          if (type_abc=='MIF')yl_idx=RD_PRE_prescrib_set_reached_only_Prescrib_213
          if ((ifixvar==8.or.ifixvar==10).and.itcurve==0) &
             call diag_ref(yl_idx,ifixset,'itcurve',int(itcurve,i8),1_i8,int(ntcurve,i8))   ! water level / temperature sets need a real curve (R18)
          call diag_range(yl_idx,ifixset,'nfixnods',int(nfixnods,i8),1_i8,int(npoin,i8))
          call diag_range(yl_idx,ifixset,'ifixvar',int(ifixvar,i8),1_i8,int(mdofn,i8))
          call diag_ref(yl_idx,ifixset,'itcurve',int(itcurve,i8),0_i8,int(ntcurve,i8))
          call diag_flush_stage()

          ! tfixvar =0, u(or p, Pw); tfixvar=1, V or DP/Dt; tfixvar=2, a;; tfixvar=3, 虚拟约束点
          ! tfixvar indicates the time  order of the input fixed value
          allocate(list_fix(nfixnods))
          read(punit,*,iostat=yl_ios,iomsg=yl_msg)list_fix(1:nfixnods)
          call diag_check_read(yl_ios,yl_msg,RD_PRE_prescrib_set_set_nodes,ifixset)
          do ifixnods=1,nfixnods   ! M1-03: every listed node must exist (consumed by nodfn below)
             call diag_ref(RD_PRE_prescrib_set_set_nodes,ifixset,'list_fix',int(list_fix(ifixnods),i8),1_i8,int(npoin,i8))
          end do
          call diag_flush_stage()
          allocate(val_fix(nfixnods))
          read(punit,*,iostat=yl_ios,iomsg=yl_msg)val_fix(1:nfixnods)
          call diag_check_read(yl_ios,yl_msg,RD_PRE_prescrib_set_set_values,ifixset)
          
          !write(7,*)'ifixsets=',ifixset,'ifixvar=',ifixvar,'jfixvar=',jfixvar,'gamaw=',gamaw
          !write(7,*)'listfix=',list_fix

          if  (ntrans>0.and.ifixvar<=ndimn)then !hxl2006 MIF
             allocate(frecoord(nfixnods))
             read(punit,*)frecoord(1:nfixnods)   !自由面坐标
          end if

          do ifixnods=1,nfixnods
             jpoin=list_fix(ifixnods)  !hxl2006 MIF
             idofn=nodfn(lmdofn(ifixvar),list_fix(ifixnods))
             if (idofn==0)goto 1
             ndofix=ndofix+1
             iffix(idofn)=tfixvar+1
             allocate(prescribx(ndofix))
             ! 2004/9/14
             if  (nextr/=0)then
                allocate(prescribx(ndofix)%listep(2*nextr+1),listep(2*nextr+1))
                allocate(prescribx(ndofix)%value_ext(2*nextr+1,nextr))
                prescribx(ndofix)%value_ext=0.
                read(punit,*)i0,listep(1:2*nextr+1)
                prescribx(ndofix)%listep=nodfn(lmdofn(ifixvar),listep(1:2*nextr+1))
                deallocate(listep)
             endif
             !2004/9/14
             if (ndofix.gt.1)prescribx(1:ndofix-1)=prescrib(1:ndofix-1)
             prescribx(ndofix)%ifixset=ifixset  !20230216
             prescribx(ndofix)%itcurve=itcurve
             prescribx(ndofix)%ifixvar=ifixvar
             prescribx(ndofix)%ifixvar0=ifixvar0
             prescribx(ndofix)%ldofix=idofn
             prescribx(ndofix)%nodfix=list_fix(ifixnods)
             prescribx(ndofix)%vdofix=val_fix(ifixnods)
             prescribx(ndofix)%outfix=outfix
             prescribx(ndofix)%jfixvar=jfixvar  !20220304
            ! prescribx(ndofix)%gamaw=gamaw !20220304   20230402
             
             if  (ntrans>0.and.ifixvar<=ndimn)then !hxl 2006 MIF
                prescribx(ndofix)%bfrecoord=frecoord(ifixnods)  !ziyoumian  !hxl
                allocate(prescribx(ndofix)%ldofixb(nlaymif))
                allocate(prescribx(ndofix)%lnofixb(nlaymif))
                prescribx(ndofix)%ldofixb=0
                prescribx(ndofix)%lnofixb=0
                allocate(ldofx(nlaymif),lnofx(nlaymif),xyzx(ndimn))
                do ilaymif=1,nlaymif  !ilaymif
                   xyzx=coord(:,jpoin)
                   xyzx(abs(ifixvar0))=coord(abs(ifixvar0),jpoin)+(ilaymif-1)*dxmif*real(ifixvar0)/real(abs(ifixvar0))
                      i0=0
                   do ipoin=1,npoin  !ipoin
                      if  (all(abs(coord(:,ipoin)-xyzx)<=epsMIFb))then
                         ldofx(ilaymif)=nodfn(lmdofn(ifixvar),ipoin)
                         lnofx(ilaymif)=ipoin
                          i0=i0+1
                           end if
                      end do  !ipoin
                      if  (i0/=1)then   !i0/=1
                         write(*,*)'stop for i0/=1, in Prescribe.f90 , for MIF'
                         write(*,*)'i0=',i0,' ifixnods=',ifixnods
                            call diag_abort('REF',EXIT_INPUT,'Prescrib.f90:prescrib_set','MIF: '//trim(diag_itoa(int(i0,i8)))//' nodes match the layer coordinates of ifixnods='//trim(diag_itoa(int(ifixnods,i8)))//', expected exactly 1')   ! M1-03 R20
                            endif !i0/=1
                         prescribx(ndofix)%ldofixb(ilaymif)=ldofx(ilaymif)
                         prescribx(ndofix)%lnofixb(ilaymif)=lnofx(ilaymif)
                      end do !ilaymif
                      deallocate(ldofx,lnofx,xyzx)
                   endif   !hxl 2006 MIF
                   lnefix=0
                   ! new
                   do igroup=1,ngroup  !igroup
                      nrfields=group(igroup)%nrfields
                      do ig=1,listp_group(list_fix(ifixnods))%mgroup
                         if (listp_group(list_fix(ifixnods))%listg(ig)==igroup)goto 10
                      end do
                      goto 20
                      10          ipoin=listp_group(list_fix(ifixnods))%listp(ig)
                      do ifield=1,nrfields
                         ndofn =group(igroup)%dof(ifield)%nfdof
                         listdof=>group(igroup)%dof(ifield)%listdof_f
                         do idofn=1,ndofn
                            ldofn=listdof(idofn)
                            if  (ldofn.eq.ifixvar) then
                               lnefix=lnefix+group(igroup)%unode(ipoin)%ne_unode
                            endif
                         end do
                         nullify(listdof)
                      end do
                      20        continue
                   end do !igroup

                   prescribx(ndofix)%lnefix=lnefix
                   allocate(prescribx(ndofix)%leldofix(lnefix),    &
                   prescribx(ndofix)%levdofix(lnefix),    &
                   prescribx(ndofix)%lefdofix(lnefix))

                   lnefix=0
                   do igroup=1,ngroup
                      do ig=1,listp_group(list_fix(ifixnods))%mgroup
                         if (listp_group(list_fix(ifixnods))%listg(ig)==igroup)goto 30
                      end do
                      goto 40
                      30       ipoin=listp_group(list_fix(ifixnods))%listp(ig)
                      nelink=group(igroup)%unode(ipoin)%ne_unode
                      if  (nelink/=0) then
                         nrfields=group(igroup)%nrfields
                         index    = group(igroup)%index
                         do iel=1,nelink
                            ielem=group(igroup)%unode(ipoin)%list(iel)
                            do jel=1,iel-1
                               jelem=group(igroup)%unode(ipoin)%list(jel)
                               if (jelem==ielem) goto 2
                            end do
                            do ifield=1,nrfields
                               nnode =elkn(index)%el_field(ifield)%nnode_f
                               ndofn =group(igroup)%dof(ifield)%nfdof
                               listdof=>group(igroup)%dof(ifield)%listdof_f
                               lnods=>element(ielem)%field(ifield)%lnods_f
                               do inode=1,nnode
                                  lnode=lnods(inode)
                                  do idofn=1,ndofn
                                     ldofn=listdof(idofn)
                                     if  (ifixvar==ldofn.and.lnode==list_fix(ifixnods)) then !!!!
                                        lnefix=lnefix+1
                                        prescribx(ndofix)%leldofix(lnefix)=ielem
                                        prescribx(ndofix)%levdofix(lnefix)=(inode-1)*ndofn+idofn
                                        prescribx(ndofix)%lefdofix(lnefix)=ifield
                                               endif
                                     end do    ! idofn
                                  end do  ! inode
                                  nullify(listdof)
                               end do   !ifield
                               2               continue
                            end do  ! iel
                         endif
                         40        continue
                      end do
                      ! end of new
                      if (allocated(prescrib))deallocate(prescrib)
                      allocate(prescrib(ndofix))
                      prescrib=prescribx
                      deallocate(prescribx)
                      1      continue
                   end do                    !!end do ifixnods
                   deallocate(list_fix,val_fix)
                   if (allocated(frecoord))deallocate(frecoord)
       end do                        !!end do ifixset
   end if  !20231130     
       
     print *,'outind=',outind
    if (outind>0) then   !20231113
    ndofix0=ndofix
    ndofix=ndofix+outind*ndimn
    allocate(prescribx(ndofix))
    if (ndofix.gt.1)prescribx(1:ndofix0)=prescrib(1:ndofix0)       
      allocate(disg(ndimn))
      read(outindunit,*)text
      ndofix=ndofix0
      do ipoin=1,outind
         read(outindunit,*)jpoin,disg    
         do idimn=1,ndimn
         itotv=nodfn(idimn,jpoin)
         if (itotv/=0) then
           iffix(itotv)=1
           ndofix=ndofix+1
             prescribx(ndofix)%itcurve=1
             prescribx(ndofix)%ifixvar=idimn
             prescribx(ndofix)%ldofix=itotv
             prescribx(ndofix)%nodfix=jpoin
             prescribx(ndofix)%vdofix=disg(idimn)
             prescribx(ndofix)%outfix=1
         endif
         end do
      end do   
      deallocate(disg)
                      if (allocated(prescrib))deallocate(prescrib)
                      allocate(prescrib(ndofix))
                      prescrib=prescribx
                      deallocate(prescribx) 
    endif     
        

                if  (outinp>0) then
                   idofn=lmdofn(8)
                   do ipoin=1,npoin
                      itotv=nodfn(idofn,ipoin)
                      if (itotv/=0)iffix(itotv)=1
                   end do
                endif

                if  (outintr/=0) then
                   idofn=lmdofn(10)
                   do ipoin=1,npoin
                      itotv=nodfn(idofn,ipoin)
                      if (itotv/=0)iffix(itotv)=1
                   end do
                endif
                
    if(alfa_p4>0)then   !20221124
                do ipoin=1,npoin
         if(local_p4(ipoin)/=1)cycle
         itotv=nodfn(6,ipoin)
         iffix(itotv)=1
         fixed(itotv)=0.
                end do
    endif !20221124


                end  subroutine prescrib_set

                end module prescribed
