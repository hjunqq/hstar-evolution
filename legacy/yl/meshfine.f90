module   meshfine

! now npoin is limited to npoin0+50000
use variable_types
USE ARRAYUTIL
USE GLOBAL_VAR
use elements
use MATERIALS
implicit none
 
type node_inter 
    integer(ink) nintf
	integer(ink),pointer::listf(:)
	real(irk),   pointer::rintf(:)
end type node_inter

type volume_ele
    integer(ink) nnode,imat,delem,iremh
	integer(ink),pointer::list(:)
    real(irk),    pointer::gpvar0(:,:)
    real(irk),    pointer::gpvar(:,:)
    real(irk),    pointer::strain0(:,:) !对icr=2 or icr=3混凝土材料记录应变过程
    real(irk),    pointer::strain(:,:)
    real(irk),    pointer::rr(:,:,:)
end type volume_ele

type element_fine
    integer(ink) nnode,imat,npl1,npl2,npl3,nsele,group,jblks,ie,ie0
	integer(ink),pointer::lnods(:),il(:),ienf(:),list(:,:,:),listp(:,:)
	type(volume_ele),pointer::fine_ele(:)
end type element_fine

type lined
    integer(ink) npl
	integer(ink),pointer::list(:)
end type lined

type surface
    integer(ink) nnode
	integer(ink),pointer::list(:)
end type surface

type faced
    integer(ink) npl1,npl2,nnode,nsface
	integer(ink),pointer::list(:,:),il(:),surf(:)
    type(surface),pointer::fine_surface(:)
end type faced

type(element_fine), allocatable::ien0(:)
type(lined),allocatable::linex(:)
type(faced),allocatable::facex(:)

type(element_fine), allocatable::ien1(:)
type(lined),allocatable::linex1(:)
type(faced),allocatable::facex1(:)
type(node_inter),allocatable::listrp(:)
type(element_lib),allocatable::element1(:),element2(:)


integer(ink) npoinx,nelem0,nelem1,nelem2,nelem10
integer(ink) nline1,nface1,nface,nline
integer(ink),allocatable::ice0(:),jce1(:),needmesh1(:),needmesh2(:)
real(irk),allocatable::coordx(:,:),outlistrp(:)


integer(ink) mpoinx,mline1,mface1,melem1,mnode1,mlinkl

integer(ink),allocatable::iline(:,:),neline(:),ieline(:,:),ijapl(:), &
                     iface(:,:),inf(:),ieface(:),nedface(:),iedface(:,:), ijapf(:)
integer(ink),allocatable::iline1(:,:),neline1(:),ieline1(:,:),ijapl1(:), &
                     iface1(:,:),inf1(:),ieface1(:),nedface1(:),iedface1(:,:), ijapf1(:)
integer(ink),allocatable::line_divide(:),line_divide1(:)

contains

    subroutine mesh_refine(ic)

    integer(ink) ie1,ie2,imat1,imat2,ip1,ip2,ip3,ip4
    integer(ink) ipoin,i0,nnode,imat,ielem,ij,lnods(8),imesh
    integer(ink) ie,i1,i2,ic,nintf,idofn
    integer(ink),allocatable::iffixp(:)

    if (ic==1)then
       mpoinx=npoin+50000
       mline1=10000
       mface1=10000
       melem1=3000
       mnode1=4
       mlinkl=20
       nelem0=nelem
       allocate(ien0(nelem0),needmesh1(nelem0))
       do ielem=1,nelem0
          nnode=size(element(ielem)%field(1)%lnods_f)
          allocate(ien0(ielem)%lnods(nnode))
          ien0(ielem)%nnode=nnode
          ien0(ielem)%nsele=0
          ien0(ielem)%lnods=element(ielem)%field(1)%lnods_f
          ien0(ielem)%imat=group(element(ielem)%group)%matno
          ien0(ielem)%group=element(ielem)%group
       end do

       npoinx=npoin
       allocate(coordx(ndimn,mpoinx),listrp(mpoinx))
       listrp(:)%nintf=0
       coordx(:,1:npoin)=coord(:,1:npoin)

       nelem1=0
       allocate(ien1(melem1),jce1(melem1))
       jce1=0
       ien1(:)%nsele=0
       if (abs(rmesh)>1)then
          allocate(iline1(2,mline1),neline1(mline1),ieline1(mlinkl,mline1),  &
          line_divide1(mline1),ijapl1(mline1))
          allocate(inf1(mface1),iface1(mnode1,mface1),ieface1(mface1),nedface1(mface1),                &
          iedface1(2,mface1),ijapf1(mface1))
          allocate(needmesh2(melem1))
          allocate(linex1(mline1))
          linex1(:)%npl=0
          if (ndimn==3)allocate(facex1(mface1))
          nline1=0;nface1=0
          neline1=0;line_divide1=0;ijapl1=0
          ijapf1=0;iedface1=0;nedface1=0
       endif

       nline=0
       if (ndimn==2)then
          do ielem=1,nelem0
             ij=ien0(ielem)%nnode
             nline=nline+ij
          end do
       elseif(ndimn==3)then
          do ielem=1,nelem0
             ij=6
             if (ien0(ielem)%nnode==6)ij=9
             if (ien0(ielem)%nnode==8)ij=12
             nline=nline+ij
          end do
       endif
       allocate(iline(2,nline),neline(nline),ieline(mlinkl,nline))
       neline=0
       call line
       if (ndimn==2) goto 11
       nface=0
       do ielem=1,nelem0
          nface=nface+4+(ien0(ielem)%nnode-4)/2
       end do
       allocate(inf(nface),iface(4,nface),ieface(nface),nedface(nface),iedface(2,nface))
       nedface=0
       call sface
       call deface
       11    continue

       allocate(line_divide(nline))
       line_divide=0
       if (ndimn==2)then
          allocate(ijapl(nline))
          print *,'nline=',nline,'size=',size(ijapl)
          ijapl=0
       elseif(ndimn==3)then
          allocate(ijapl(nline),ijapf(nface))
          ijapl=0;ijapf=0
       endif
       allocate(linex(nline))
       linex(:)%npl=0
       if (ndimn==3)allocate(facex(nface))
    endif  !for ic==1
    !  nline1=0;nface1=0
    ! neline1=0;line_divide1=0;ijapl1=0
    ! ijapf1=0;iedface1=0;nedface1=0
    nelem10=nelem1
    write(7,*)'nelem10=',nelem10

    needmesh1=0
    if (nelc/=0)needmesh1(listnelc)=1
    if (abs(rmesh)>1)then
       needmesh2=0
       if (nelc1/=0)needmesh2(listnelc1)=1
    endif

    if (ndimn==2)then
       do ie=1,nelem0
          if (needmesh1(ie)==1)then
             ijapl(abs(ien0(ie)%il))=ijapl(abs(ien0(ie)%il))+1
          endif
       end do
    elseif(ndimn==3)then
       do ie=1,nelem0
          if (needmesh1(ie)==1)then
             ijapf(abs(ien0(ie)%ienf))=ijapf(abs(ien0(ie)%ienf))+1
             ijapl(abs(ien0(ie)%il))=ijapl(abs(ien0(ie)%il))+1
          endif
       end do
    endif

    print *,'nline1=',nline
    do i1=1,nline
       if (ijapl(i1)>0) &
       line_divide(i1)=ndefault(1)
    enddo
    call line_inter
    if (ndimn==2)then
       call elem2_inter
    elseif(ndimn==3)then
       call determine_face
       call face_inter
       call elem3_inter
    endif

    !!!!!remesh1
    !if(rmesh==1) then
    if (allocated(trans_c))deallocate(trans_c)
    if (allocated(outlistrp))deallocate(outlistrp)
    allocate(outlistrp(npoinx),trans_c(npoinx))
    trans_c(:)%nintf=0
    outlistrp(1:npoinx)=-1*listrp(1:npoinx)%nintf
    if (ndimn==3)then
       do ie=1,nface
          if (ijapf(ie)==-1.and.nedface(ie)==2)then
             do i1=1,facex(ie)%npl1
                do i2=1,facex(ie)%npl2
                   if ((i1==1.and.i2==1).or.(i1==1.and.i2==facex(ie)%npl2).or.  &
                   (i1==facex(ie)%npl1.and.i2==1).or.                       &
                   (i1==facex(ie)%npl1.and.i2==facex(ie)%npl2)) goto 10
                   ipoin=facex(ie)%list(i1,i2)
                   if (ipoin/=0) &
                   outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                   10   continue
                end do
             end do
          endif
       end do
    elseif(ndimn==2)then
       do ie=1,nline
          if (ijapl(ie)==-1.and.neline(ie)==2)then
             do i1=2,linex(ie)%npl-1
                ipoin=linex(ie)%list(i1)
                if (ipoin/=0) &
                outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
             end do
          endif
       end do
    endif
    !endif

    i0=0
    if (abs(rmesh)==1)then
       do ipoin=1,npoinx
          if (outlistrp(ipoin)>0)then
             i0=i0+1
             write(7,7)ipoin,listrp(ipoin)%nintf
             write(7,7)listrp(ipoin)%listf
             write(7,6)listrp(ipoin)%rintf
             nintf=abs(listrp(ipoin)%nintf)
             trans_c(ipoin)%nintf=nintf
             allocate(trans_c(ipoin)%listf(nintf),trans_c(ipoin)%rintf(nintf))
             trans_c(ipoin)%listf=listrp(ipoin)%listf
             trans_c(ipoin)%rintf=listrp(ipoin)%rintf
          endif
       end do
       write(7,*)'total interpolation nodes=',i0
    endif
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!
    print *,'npoin=',npoin,'npoinx=',npoinx
    allocate(iffixp(npoinx))
    iffixp=0
    do ipoin=1,npoin
       do idofn=1,cdofn
          if (nodfn(idofn,ipoin)>0) then
             if (iffix(nodfn(idofn,ipoin))==1) iffixp(ipoin)=1
          endif
       end do
    end do
    do ipoin=1,npoinx
       if (outlistrp(ipoin)<=0.and.listrp(ipoin)%nintf/=0)then
          if (all(iffixp(listrp(ipoin)%listf)==1))then
             nintf=abs(listrp(ipoin)%nintf)
             outlistrp(ipoin)=-outlistrp(ipoin)
             if (abs(rmesh)==1)then
                allocate(trans_c(ipoin)%listf(nintf),trans_c(ipoin)%rintf(nintf))
                trans_c(ipoin)%nintf=-nintf
                trans_c(ipoin)%listf=listrp(ipoin)%listf
                trans_c(ipoin)%rintf=listrp(ipoin)%rintf
             endif
          endif
       endif
    end do
    deallocate(iffixp)
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    write(7,*)'nelem1=',nelem1
    call remesh1
    if (abs(rmesh)>1) then
       if (allocated(trans_c))deallocate(trans_c)
       if (allocated(outlistrp))deallocate(outlistrp)
       allocate(outlistrp(npoinx),trans_c(npoinx))
       trans_c(:)%nintf=0

       outlistrp=-1*listrp(:)%nintf
       if (ndimn==3)then
          do ie=1,nface
             if (ijapf(ie)==-1.and.nedface(ie)==2)then
                do i1=1,facex(ie)%npl1
                   do i2=1,facex(ie)%npl2
                      if ((i1==1.and.i2==1).or.(i1==1.and.i2==facex(ie)%npl2).or.  &
                      (i1==facex(ie)%npl1.and.i2==1).or.                       &
                      (i1==facex(ie)%npl1.and.i2==facex(ie)%npl2)) goto 13
                      ipoin=facex(ie)%list(i1,i2)
                      if (ipoin/=0) &
                      outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                      13   continue
                   end do
                end do
             endif
          end do

          do ie=1,nface1
             if (ijapf1(ie)==-1.and.nedface1(ie)==2)then
                do i1=1,facex1(ie)%npl1
                   do i2=1,facex1(ie)%npl2
                      if ((i1==1.and.i2==1).or.(i1==1.and.i2==facex1(ie)%npl2).or.  &
                      (i1==facex1(ie)%npl1.and.i2==1).or.                       &
                      (i1==facex1(ie)%npl1.and.i2==facex1(ie)%npl2)) goto 12
                      ipoin=facex1(ie)%list(i1,i2)
                      if (ipoin/=0) &
                      outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                      12   continue
                   end do
                end do
             endif
          end do

          do ie=1,nface1
             if (ijapf1(ie)==-1.and.nedface1(ie)==1)then
                !!!!内部节点
                ip1=facex1(ie)%list(1,1)
                ip2=facex1(ie)%list(facex1(ie)%npl1,1)
                ip3=facex1(ie)%list(facex1(ie)%npl1,facex1(ie)%npl2)
                ip4=facex1(ie)%list(1,facex1(ie)%npl2)
                if (outlistrp(ip1)>0.or.outlistrp(ip2)>0.or.outlistrp(ip3)>0.or.outlistrp(ip4)>0)then
                   do i1=2,facex1(ie)%npl1-1
                      do i2=2,facex1(ie)%npl2-1
                         ipoin=facex1(ie)%list(i1,i2)
                         if (ipoin/=0) &
                         outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                      end do
                   end do
                endif
                !!!!四条线段
                i2=1
                ip1=facex1(ie)%list(1,1)
                ip2=facex1(ie)%list(facex1(ie)%npl1,1)
                if (outlistrp(ip1)>0.or.outlistrp(ip2)>0)then
                   do i1=2,facex1(ie)%npl1-1
                      ipoin=facex1(ie)%list(i1,i2)
                      if (ipoin/=0) &
                      outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                   end do
                endif

                i1=facex1(ie)%npl1
                ip2=facex1(ie)%list(facex1(ie)%npl1,facex1(ie)%npl2)
                ip1=facex1(ie)%list(facex1(ie)%npl1,1)
                if (outlistrp(ip1)>0.or.outlistrp(ip2)>0)then
                   do i2=2,facex1(ie)%npl2-1
                      ipoin=facex1(ie)%list(i1,i2)
                      if (ipoin/=0) &
                      outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                   end do
                endif


                i2=facex1(ie)%npl2
                ip2=facex1(ie)%list(facex1(ie)%npl1,facex1(ie)%npl2)
                ip1=facex1(ie)%list(1,facex1(ie)%npl2)
                if (outlistrp(ip1)>0.or.outlistrp(ip2)>0)then
                   do i1=2,facex1(ie)%npl1-1
                      ipoin=facex1(ie)%list(i1,i2)
                      if (ipoin/=0) &
                      outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                   end do
                endif

                i1=1
                ip1=facex1(ie)%list(1,1)
                ip2=facex1(ie)%list(1,facex1(ie)%npl2)
                if (outlistrp(ip1)>0.or.outlistrp(ip2)>0)then
                   do i2=2,facex1(ie)%npl2-1
                      ipoin=facex1(ie)%list(i1,i2)
                      if (ipoin/=0) &
                      outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                   end do
                endif

             endif  !结束单面循环
          end do
       elseif(ndimn==2)then
          do ie=1,nline
             if (ijapl(ie)==-1.and.neline(ie)==2)then
                do i1=2,linex(ie)%npl-1
                   ipoin=linex(ie)%list(i1)
                   if (ipoin/=0) &
                   outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                end do
             endif
          end do

          do ie=1,nline1
             if (ijapl1(ie)==-1)then
                ip1=linex1(ie)%list(1)
                ip2=linex1(ie)%list(linex1(ie)%npl)
                !     write(7,*)'ie=',ie,'ip1=',ip1,'ip2=',ip2,'nel=',neline1(ie)
                !     write(7,*)'ieline=',ieline1(1:neline1(ie),ie)
                if (neline1(ie)==2.or.(neline1(ie)==1.and.   &
                   (outlistrp(ip1)>0.or.outlistrp(ip2)>0)))then
                   do i1=2,linex1(ie)%npl-1
                      ipoin=linex1(ie)%list(i1)
                      if (ipoin/=0) &
                      outlistrp(ipoin)=abs(listrp(ipoin)%nintf)
                   end do
                endif
             endif
          end do
       endif
    endif

    if (abs(rmesh)>1)then
       do ipoin=1,npoinx
          if (outlistrp(ipoin)>0)then
             i0=i0+1
             write(7,7)ipoin,listrp(ipoin)%nintf
             write(7,7)listrp(ipoin)%listf
             write(7,6)listrp(ipoin)%rintf
             nintf=abs(listrp(ipoin)%nintf)
             allocate(trans_c(ipoin)%listf(nintf),trans_c(ipoin)%rintf(nintf))
             trans_c(ipoin)%nintf=nintf
             trans_c(ipoin)%listf=listrp(ipoin)%listf
             trans_c(ipoin)%rintf=listrp(ipoin)%rintf
          endif
       end do
       write(7,*)'total interpolation nodes=',i0
    endif

    !!!!!!!!!!!!!!!!!!


    allocate(iffixp(npoinx))
    iffixp=0
    do ipoin=1,npoin
       do idofn=1,cdofn
          if (nodfn(idofn,ipoin)>0) then
             if (iffix(nodfn(idofn,ipoin))==1) iffixp(ipoin)=1
          endif
       end do
    end do

    do ipoin=1,npoinx
       if (outlistrp(ipoin)<=0.and.listrp(ipoin)%nintf/=0)then
          if (all(iffixp(listrp(ipoin)%listf)==1))then
             nintf=abs(listrp(ipoin)%nintf)
             allocate(trans_c(ipoin)%listf(nintf),trans_c(ipoin)%rintf(nintf))
             trans_c(ipoin)%nintf=-nintf
             trans_c(ipoin)%listf=listrp(ipoin)%listf
             trans_c(ipoin)%rintf=listrp(ipoin)%rintf
             outlistrp(ipoin)=-outlistrp(ipoin)
          endif
       endif
    end do

    do ipoin=1,npoinx
       if (trans_c(ipoin)%nintf<0)then
          i0=i0+1
          write(7,7)ipoin,trans_c(ipoin)%nintf
          write(7,7)trans_c(ipoin)%listf
          write(7,6)trans_c(ipoin)%rintf
       endif
    end do
    write(7,*)'total interpolation nodes=',i0


    deallocate(outlistrp,iffixp)
    call group_of_refined_element(ic)
    call result_of_refined_mesh

    6 format(10f20.8)
    7 format(10i10)

    end subroutine mesh_refine
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine result_store_of_fine_mesh
    character(20)material
    integer(ink)igroup,matno,icr,iex,ie0,iremh
    integer(ink)ie,delem,nsele,ngvar,ngaus,nstre,jblks

    do ie=1,nelem
       if (ice0(ie)==0) goto 1
       icr=0
       igroup=ien0(ie)%group
       matno = group(igroup)%matno
       material=props(matno)%mechanical%solid%material
       if (material=='CONCRETE') &
       icr=props(matno)%mechanical%solid%Concrete%icr
       nsele=ien0(ie)%nsele
       do ie0=1,nsele
          delem=ien0(ie)%fine_ele(ie0)%delem
          jblks=ien0(ie)%jblks
          if (jblks==(iblks-1))then
             ngvar=size(element1(delem)%field(1)%gpvar,1)
             ngaus=size(element1(delem)%field(1)%gpvar,2)
             allocate(ien0(ie)%fine_ele(ie0)%gpvar(ngvar,ngaus))
             allocate(ien0(ie)%fine_ele(ie0)%gpvar0(ngvar,ngaus))
          endif
          ien0(ie)%fine_ele(ie0)%gpvar0=element1(delem)%field(1)%gpvar0
          ien0(ie)%fine_ele(ie0)%gpvar =element1(delem)%field(1)%gpvar
          !write(7,*)'ie=',ie,'ie0=',ie0,'delem=',delem
          !write(7,*)'gpvar=',element1(delem)%field(1)%gpvar(:,1)

          if (icr==1) then
             if (jblks==(iblks-1))then
                ngaus=size(element1(delem)%field(1)%rr,3)
                allocate(ien0(ie)%fine_ele(ie0)%rr(ndimn,ndimn,ngaus))
             endif
             ien0(ie)%fine_ele(ie0)%rr=element1(delem)%field(1)%rr
          end if

          if (icr==2.or.icr==3.or.icr==5)then !zhao09
             if (jblks==(iblks-1))then
                nstre=size(element1(delem)%field(1)%strain,1)
                ngaus=size(element1(delem)%field(1)%strain,2)
                allocate(ien0(ie)%fine_ele(ie0)%strain(nstre,ngaus))
                allocate(ien0(ie)%fine_ele(ie0)%strain0(nstre,ngaus))
             endif
             ien0(ie)%fine_ele(ie0)%strain=element1(delem)%field(1)%strain
             ien0(ie)%fine_ele(ie0)%strain0=element1(delem)%field(1)%strain0
          end if
       end do
       1 continue
    end do
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    if (abs(rmesh)==1)return
    do ie=1,nelem1
       iex=ien1(ie)%ie
       ie0=ien1(ie)%ie0
       iremh=ien0(iex)%fine_ele(ie0)%iremh
       if (iremh==0) goto 2
       nsele=ien1(ie)%nsele
       icr=0
       igroup=ien1(ie)%group
       matno = group(igroup)%matno
       material=props(matno)%mechanical%solid%material
       if (material=='CONCRETE') &
       icr=props(matno)%mechanical%solid%Concrete%icr
       do ie0=1,nsele
          delem=ien1(ie)%fine_ele(ie0)%delem
          jblks=ien1(ie)%jblks
          if (jblks==(iblks-1))then
             ngvar=size(element2(delem)%field(1)%gpvar,1)
             ngaus=size(element2(delem)%field(1)%gpvar,2)
             allocate(ien1(ie)%fine_ele(ie0)%gpvar(ngvar,ngaus))
             allocate(ien1(ie)%fine_ele(ie0)%gpvar0(ngvar,ngaus))
          endif
          ien1(ie)%fine_ele(ie0)%gpvar0=element2(delem)%field(1)%gpvar0
          ien1(ie)%fine_ele(ie0)%gpvar =element2(delem)%field(1)%gpvar

          if (icr==1) then
             if (jblks==(iblks-1))then
                ngaus=size(element2(delem)%field(1)%rr,3)
                allocate(ien1(ie)%fine_ele(ie0)%rr(ndimn,ndimn,ngaus))
             endif
             ien1(ie)%fine_ele(ie0)%rr=element2(delem)%field(1)%rr
          end if

          if (icr==2.or.icr==3.or.icr==5)then !zhao09
             if (jblks==(iblks-1))then
                nstre=size(element2(delem)%field(1)%strain,1)
                ngaus=size(element2(delem)%field(1)%strain,2)
                allocate(ien1(ie)%fine_ele(ie0)%strain(nstre,ngaus))
                allocate(ien1(ie)%fine_ele(ie0)%strain0(nstre,ngaus))
             endif
             ien1(ie)%fine_ele(ie0)%strain=element2(delem)%field(1)%strain
             ien1(ie)%fine_ele(ie0)%strain0=element2(delem)%field(1)%strain0
          end if
       end do
       2 continue
    end do

    end subroutine result_store_of_fine_mesh
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine result_of_refined_mesh
    character(10) nameg
    integer (ink) ipoin,idofn,ielgroup,idofs,kpoin,igroup
    integer (ink) inode,ndofn,ifield,nrfields,icc
    integer (ink) nelgroup,index,nnode,ielem,ngaus,id
    integer (ink) nevabt1,nevabt2,ig,nevab,nevabt,ikg,nr_intrules
    integer (ink) nnode_f,nevab_f,ndofn_f,ntotvx,nintf,jnode,itotv,jtotv,jpoin
    real    (irk) djacb,weigp,dfact
    real    (irk),allocatable::shape(:),deriv(:,:),cartd(:,:),  &
    result_zerox(:),result_firstx(:),result_secondx(:), &
    toforlx(:),torelx(:),xjaci(:,:)

    integer (ink),allocatable::lnods(:),listdof(:)
    deallocate(coord)
    allocate(coord(ndimn,npoinx))
    coord(:,1:npoinx)=coordx(:,1:npoinx)
    if (rmesh<0)then
       npoin=npoinx
       return
    endif

    if (allocated(nodfn))deallocate(nodfn)
    allocate(nodfn(cdofn,npoinx))
    nodfn=0
    write(7,*)'npoinx=',npoinx,'nelem=',nelem,'nelem1=',nelem1

    !!!original_mesh
    do igroup=1,ngroup
       nelgroup=group(igroup)%nelgroup
       index   =group(igroup)%index
       nrfields=elkn(index)%nrfields
       do ielgroup=1,nelgroup
          ielem=group(igroup)%list(ielgroup)
          if (ice0(ielem)==1)goto 3
          do ifield=1,nrfields   !!ifield
             nnode=elkn(index)%el_field(ifield)%nnode_f
             ndofn=group(igroup)%dof(ifield)%nfdof
             allocate(listdof(ndofn),lnods(nnode))
             lnods=element(ielem)%field(ifield)%lnods_f
             listdof=group(igroup)%dof(ifield)%listdof_f
             listdof=lmdofn(listdof)
             nodfn(listdof,lnods(1:nnode))=1
             deallocate(listdof,lnods)
          end do                 !!end ifield
          3   continue
       end do
    end do
    !!first layer refined mesh
    do igroup=1,ngroup
       nelgroup=group1(igroup)%nelgroup
       index   =group(igroup)%index
       nrfields=elkn(index)%nrfields
       do ielgroup=1,nelgroup
          ielem=group1(igroup)%list(ielgroup)
          if (jce1(ielem)==1) goto 4
          nevabt=0
          do ifield=1,nrfields   !!ifield
             nnode=elkn(index)%el_field(ifield)%nnode_f
             ndofn=group(igroup)%dof(ifield)%nfdof
             allocate(listdof(ndofn),lnods(nnode))
             nevab=nnode*ndofn
             nevabt=nevabt+nevab
             allocate(element1(ielem)%field(ifield)%ldofs_f(nevab))
             allocate(element1(ielem)%field(ifield)%elcod_f(ndimn,nnode))
             lnods(1:nnode)=element1(ielem)%field(ifield)%lnods_f
             element1(ielem)%field(ifield)%elcod_f(:,1:nnode)=coord(:,lnods)
             listdof=group(igroup)%dof(ifield)%listdof_f
             listdof=lmdofn(listdof)
             nodfn(listdof,lnods(1:nnode))=1
             deallocate(listdof,lnods)
          end do                 !!end ifield

          nr_intrules=elkn(index)%nr_intrules
          if (nr_intrules/=0) &
          allocate(element1(ielem)%egaus(nr_intrules))
          allocate(element1(ielem)%ldofs(nevab))
          do ikg=1,nr_intrules     !!!ikg
             ngaus=elkn(index)%ggaus(ikg)%ngaus
             nnode=elkn(index)%ggaus(ikg)%nnode
             nameg=elkn(index)%ggaus(ikg)%name
             allocate(shape(nnode),deriv(ndimn,nnode),cartd(ndimn,nnode),xjaci(ndimn,ndimn))
             allocate(element1(ielem)%egaus(ikg)%gpcod(ndimn,ngaus),  &
             element1(ielem)%egaus(ikg)%djacb(ngaus))
             if (nameg(1:4)/='mass')allocate(element1(ielem)%egaus(ikg)%cartd(ndimn,nnode,ngaus))
             do ig=1,ngaus
                shape=elkn(index)%ggaus(ikg)%shape(:,ig)
                deriv=elkn(index)%ggaus(ikg)%deriv(:,:,ig)
                weigp=elkn(index)%ggaus(ikg)%weigp(ig)
                do id=1,ndimn
                   element1(ielem)%egaus(ikg)%gpcod(id,ig)  &
                   =sum (element1(ielem)%field(1)%elcod_f(id,1:nnode)*shape(1:nnode))
                end do
                call jacob(ielem,ndimn,nnode,element1(ielem)%field(1)%elcod_f,deriv,cartd,djacb,xjaci)
                if (nameg/='mass')element1(ielem)%egaus(ikg)%cartd(:,:,ig)=cartd
                element1(ielem)%egaus(ikg)%djacb(ig)=djacb*weigp
             end do !ig
             deallocate (shape,deriv,cartd,xjaci)
          end do  !ikg
          4  continue
       end do !ielgroup
    end do  !igroup
    !!second layer refined mesh
    if (abs(rmesh)==1) goto 1
    do igroup=1,ngroup
       nelgroup=group2(igroup)%nelgroup
       index   =group(igroup)%index
       nrfields=elkn(index)%nrfields
       do ielgroup=1,nelgroup
          ielem=group2(igroup)%list(ielgroup)
          nevabt=0
          do ifield=1,nrfields   !!ifield
             nnode=elkn(index)%el_field(ifield)%nnode_f
             ndofn=group(igroup)%dof(ifield)%nfdof
             allocate(listdof(ndofn),lnods(nnode))
             nevab=nnode*ndofn
             nevabt=nevabt+nevab
             allocate(element2(ielem)%field(ifield)%ldofs_f(nevab))
             allocate(element2(ielem)%field(ifield)%elcod_f(ndimn,nnode))
             lnods(1:nnode)=element2(ielem)%field(ifield)%lnods_f
             element2(ielem)%field(ifield)%elcod_f(:,1:nnode)=coord(:,lnods)
             listdof=group(igroup)%dof(ifield)%listdof_f
             listdof=lmdofn(listdof)
             nodfn(listdof,lnods(1:nnode))=1
             deallocate(listdof,lnods)
          end do                 !!end ifield

          nr_intrules=elkn(index)%nr_intrules
          if (nr_intrules/=0) &
          allocate(element2(ielem)%egaus(nr_intrules))
          allocate(element2(ielem)%ldofs(nevab))
          do ikg=1,nr_intrules     !!!ikg
             ngaus=elkn(index)%ggaus(ikg)%ngaus
             nnode=elkn(index)%ggaus(ikg)%nnode
             nameg=elkn(index)%ggaus(ikg)%name
             allocate(shape(nnode),deriv(ndimn,nnode),cartd(ndimn,nnode),xjaci(ndimn,ndimn))
             allocate(element2(ielem)%egaus(ikg)%gpcod(ndimn,ngaus),  &
             element2(ielem)%egaus(ikg)%djacb(ngaus))
             if (nameg(1:4)/='mass')allocate(element2(ielem)%egaus(ikg)%cartd(ndimn,nnode,ngaus))
             do ig=1,ngaus
                shape=elkn(index)%ggaus(ikg)%shape(:,ig)
                deriv=elkn(index)%ggaus(ikg)%deriv(:,:,ig)
                weigp=elkn(index)%ggaus(ikg)%weigp(ig)
                do id=1,ndimn
                   element2(ielem)%egaus(ikg)%gpcod(id,ig)  &
                   =sum (element2(ielem)%field(1)%elcod_f(id,1:nnode)*shape(1:nnode))
                end do
                call jacob(ielem,ndimn,nnode,element2(ielem)%field(1)%elcod_f,deriv,cartd,djacb,xjaci)
                if (nameg/='mass')element2(ielem)%egaus(ikg)%cartd(:,:,ig)=cartd
                element2(ielem)%egaus(ikg)%djacb(ig)=djacb*weigp
             end do !ig
             deallocate (shape,deriv,cartd,xjaci)
          end do  !ikg
       end do !ielgroup
    end do  !igroup
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    1  continue
    ntotvx=0

    do ipoin=1,npoinx         !!! block for ntotv ____
       do idofn=1,cdofn                       !
          if (nodfn(idofn,ipoin)==1) then                !
             ntotvx=ntotvx+1                            !
             nodfn(idofn,ipoin)=ntotvx                  !
          endif                                !
       end do                                  !
    end do              !!!_____________________!

    !!!original mesh
    do igroup=1,ngroup
       nelgroup=group(igroup)%nelgroup
       index   =group(igroup)%index
       nnode   =elkn(index)%nnode
       nrfields=elkn(index)%nrfields
       do ielgroup=1,nelgroup
          ielem=group(igroup)%list(ielgroup)
          if (ice0(ielem)==1) goto 5
          nevabt1=0
          do ifield=1,nrfields
             nnode_f=elkn(index)%el_field(ifield)%nnode_f
             ndofn_f=group(igroup)%dof(ifield)%nfdof
             nevab_f=nnode_f*ndofn_f
             nevabt1=nevabt1+1
             nevabt2=nevabt1+nevab_f-1
             idofs=0
             allocate(listdof(ndofn_f),lnods(nnode_f))
             lnods=element(ielem)%field(ifield)%lnods_f
             listdof=group(igroup)%dof(ifield)%listdof_f
             listdof=lmdofn(listdof)
             do inode=1,nnode_f
                kpoin=lnods(inode)
                do idofn=1,ndofn_f
                   if (nodfn(listdof(idofn),kpoin)/=0) then
                      idofs=idofs+1
                      element(ielem)%field(ifield)%ldofs_f(idofs)    &
                      =nodfn(listdof(idofn),kpoin)
                   endif
                end do
             end do
             element(ielem)%ldofs(nevabt1:nevabt2)=         &
             element(ielem)%field(ifield)%ldofs_f(1:nevab_f)
             nevabt1=nevabt2
             deallocate(listdof,lnods)
          end do       !!end ifield
          5  continue
       end do

    end do
    !!!!!
    !!!first refine mesh
    do igroup=1,ngroup
       nelgroup=group1(igroup)%nelgroup
       index   =group(igroup)%index
       nnode   =elkn(index)%nnode
       nrfields=elkn(index)%nrfields
       do ielgroup=1,nelgroup
          ielem=group1(igroup)%list(ielgroup)
          if (jce1(ielem)==1)goto 6
          nevabt1=0
          do ifield=1,nrfields
             nnode_f=elkn(index)%el_field(ifield)%nnode_f
             ndofn_f=group(igroup)%dof(ifield)%nfdof
             nevab_f=nnode_f*ndofn_f
             nevabt1=nevabt1+1
             nevabt2=nevabt1+nevab_f-1
             idofs=0
             allocate(listdof(ndofn_f),lnods(nnode_f))
             lnods=element1(ielem)%field(ifield)%lnods_f
             listdof=group(igroup)%dof(ifield)%listdof_f
             listdof=lmdofn(listdof)
             do inode=1,nnode_f
                kpoin=lnods(inode)
                do idofn=1,ndofn_f
                   if (nodfn(listdof(idofn),kpoin)/=0) then
                      idofs=idofs+1
                      element1(ielem)%field(ifield)%ldofs_f(idofs)    &
                      =nodfn(listdof(idofn),kpoin)
                   endif
                end do
             end do
             element1(ielem)%ldofs(nevabt1:nevabt2)=         &
             element1(ielem)%field(ifield)%ldofs_f(1:nevab_f)
             nevabt1=nevabt2
             deallocate(listdof,lnods)
          end do       !!end ifield
          6  continue
       end do

    end do
    !!!!!
    !!!second refine mesh
    if (abs(rmesh)==1) goto 2
    do igroup=1,ngroup
       nelgroup=group2(igroup)%nelgroup
       index   =group(igroup)%index
       nnode   =elkn(index)%nnode
       nrfields=elkn(index)%nrfields
       do ielgroup=1,nelgroup
          ielem=group2(igroup)%list(ielgroup)
          nevabt1=0
          do ifield=1,nrfields
             nnode_f=elkn(index)%el_field(ifield)%nnode_f
             ndofn_f=group(igroup)%dof(ifield)%nfdof
             nevab_f=nnode_f*ndofn_f
             nevabt1=nevabt1+1
             nevabt2=nevabt1+nevab_f-1
             idofs=0
             allocate(listdof(ndofn_f),lnods(nnode_f))
             lnods=element2(ielem)%field(ifield)%lnods_f
             listdof=group(igroup)%dof(ifield)%listdof_f
             listdof=lmdofn(listdof)
             do inode=1,nnode_f
                kpoin=lnods(inode)
                do idofn=1,ndofn_f
                   if (nodfn(listdof(idofn),kpoin)/=0) then
                      idofs=idofs+1
                      element2(ielem)%field(ifield)%ldofs_f(idofs)    &
                      =nodfn(listdof(idofn),kpoin)
                   endif
                end do
             end do
             element2(ielem)%ldofs(nevabt1:nevabt2)=         &
             element2(ielem)%field(ifield)%ldofs_f(1:nevab_f)
             nevabt1=nevabt2
             deallocate(listdof,lnods)
          end do       !!end ifield
       end do

    end do
    !!!!!!change the result
    2 continue
    if (allocated(result_zero))then
       allocate(result_zerox(ntotvx))
       result_zerox=0.
       result_zerox(1:ntotv)=result_zero(1:ntotv)
       deallocate(result_zero)
       allocate(result_zero(ntotvx))
       result_zero=result_zerox
       deallocate(result_zerox)
    endif

    if (allocated(result_first))then
       allocate(result_firstx(ntotvx))
       result_firstx=0.
       result_firstx(1:ntotv)=result_first(1:ntotv)
       deallocate(result_first)
       allocate(result_first(ntotvx))
       result_first=result_firstx
       deallocate(result_firstx)
    endif

    if (allocated(result_second))then
       allocate(result_secondx(ntotvx))
       result_secondx=0.
       result_secondx(1:ntotv)=result_second(1:ntotv)
       deallocate(result_second)
       allocate(result_second(ntotvx))
       result_second=result_secondx
       deallocate(result_secondx)
    endif

    if (allocated(torel))then
       allocate(torelx(ntotvx))
       torelx=0.
       torelx(1:ntotv)=torel(1:ntotv)
       deallocate(torel)
       allocate(torel(ntotvx))
       torel=torelx
       deallocate(torelx)
    endif

    if (allocated(toforl))then
       allocate(toforlx(ntotvx))
       toforlx=0.
       toforlx(1:ntotv)=toforl(1:ntotv)
       deallocate(toforl)
       allocate(toforl(ntotvx))
       toforl=toforlx
       deallocate(toforlx)
    endif

    !print *,'npoinx=',npoinx,'npoin=',npoin,'ntotvx=',ntotvx,'ntotv=',ntotv
    ntotv=ntotvx
    npoin=npoinx

    ! write(7,*)'result_zero_0'
    !do ipoin=1,npoin
    !write(7,*)ipoin,result_zero(nodfn(1:2,ipoin))
    !end do


    if (allocated(trans))deallocate(trans)
    allocate(trans(ntotv))
    trans(:)%nintf=0

    do ipoin=1,npoin
       nintf=trans_c(ipoin)%nintf
       !    write(7,*)'ipoin=',ipoin,'nintf=',nintf,'cdofn=',cdofn
       if (nintf==0)goto 10
       do idofn=1,cdofn
          itotv=nodfn(idofn,ipoin)
          icc=0
          if (itotv/=0.and.nintf>0)icc=1
          if (itotv/=0.and.nintf<0)then
             if (all(iffix(nodfn(idofn,trans_c(ipoin)%listf(:)))==1))icc=1
          endif
          if (icc==1)then
             nintf=abs(nintf)
             trans(itotv)%nintf=nintf
             allocate(trans(itotv)%listf(nintf),trans(itotv)%rintf(nintf))
             result_zero(itotv)=0.
             if (allocated(result_first))result_first(itotv)=0.
             if (allocated(result_second))result_second(itotv)=0.
             if (allocated(torel))        torel(itotv)=0.
             if (allocated(toforl))       toforl(itotv)=0.

             do jnode=1,nintf
                !  write(7,*)'ipoin=',ipoin,'jnode=',jnode
                !  write(7,*)'jpoin=',trans_c(ipoin)%listf(jnode)
                jpoin=trans_c(ipoin)%listf(jnode)
                dfact=trans_c(ipoin)%rintf(jnode)
                jtotv=nodfn(idofn,jpoin)
                trans(itotv)%listf(jnode)=jtotv
                trans(itotv)%rintf(jnode)=dfact
                result_zero(itotv)=result_zero(itotv)+result_zero(jtotv)*dfact
                !   write(7,*)'itotv=',itotv,'jtotv=',jtotv,'dfact=',dfact,'rj=',result_zero(jtotv)
                if (allocated(result_first))result_first(itotv)=result_first(itotv)+dfact*result_first(jtotv)
                if (allocated(result_second))result_second(itotv)=result_second(itotv)+dfact*result_second(jtotv)
                if (allocated(torel))        torel(itotv)=torel(itotv)+dfact*torel(jtotv)
                if (allocated(toforl))       toforl(itotv)=toforl(itotv)+dfact*toforl(itotv)

             end do  !jnode
          endif  !if(itotv/=0)
       end do  !idofn
       10   continue
    end do  !ipoin

    ! write(7,*)'result_zero_1'
    ! do ipoin=1,npoin
    ! write(7,*)ipoin,result_zero(nodfn(1:2,ipoin))
    ! end do



    end subroutine result_of_refined_mesh

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine  group_of_refined_element(ic)
    character(20) material
    integer(ink) ic,nelemx,nnode,ie,ie0,icr,nevab,jblks
    integer(ink) nelgroup,nsele,igroup,index,nrfields,matno,ngaus,ngvar,nstre

    if (ic==1)allocate(group1(ngroup))

    if (allocated(element1))deallocate(element1)
    allocate(element1(nelem1))

    nelemx=0
    jce1=0
    do igroup=1,ngroup  !igroup

       index = group(igroup)%index
       matno = group(igroup)%matno
       material=props(matno)%mechanical%solid%material
       ngaus =elkn(index)%ggaus(1)%ngaus
       ngvar=group(igroup)%ngvar
       nstre=group(igroup)%nstre
       nelgroup=0
       do ie=1,nelem0
          if (ien0(ie)%group==igroup)then
             nsele=ien0(ie)%nsele
             nelgroup=nelgroup+nsele
          endif
       end do
       if (associated(group1(igroup)%list))deallocate(group1(igroup)%list)
       allocate(group1(igroup)%list(nelgroup))
       group1(igroup)%nelgroup=nelgroup
       nelgroup=0
       do ie=1,nelem0
          if (ien0(ie)%group==igroup)then
             nsele=ien0(ie)%nsele
             do ie0=1,nsele
                jblks=ien0(ie)%jblks
                nelgroup=nelgroup+1
                nelemx=nelemx+1
                jce1(nelemx)=ien0(ie)%fine_ele(ie0)%iremh
                group1(igroup)%list(nelgroup)=nelemx
                element1(nelemx)%index=index
                element1(nelemx)%group=igroup
                element1(nelemx)%matno=matno
                element1(nelemx)%nrfields=group(igroup)%nrfields
                element1(nelemx)%nstre=nstre
                nnode = elkn(group(igroup)%index)%nnode
                nevab = nnode*group(igroup)%dof(1)%nfdof
                allocate(element1(nelemx)%field(group(igroup)%nrfields))
                allocate(element1(nelemx)%field(1)%lnods_f(nnode))
                allocate(element1(nelemx)%field(1)%tload(nevab))
                allocate(element1(nelemx)%field(1)%eload(nevab))
                allocate(element1(nelemx)%field(1)%rload(nevab))
                allocate(element1(nelemx)%field(1)%khandmc(1)%fstif(nevab,nevab))
                element1(nelemx)%field(1)%khandmc(1)%fstif=0.0


                element1(nelemx)%field(1)%lnods_f=ien0(ie)%fine_ele(ie0)%list
                element1(nelemx)%jblks=ien0(ie)%jblks
                ien0(ie)%fine_ele(ie0)%delem=nelemx
                element1(nelemx)%field(1)%ngvar_f=ngvar
                allocate(element1(nelemx)%field(1)%gpvar0(ngvar,ngaus))
                allocate(element1(nelemx)%field(1)%gpvar(ngvar,ngaus))
                if (material=='CONCRETE')then
                   icr=props(matno)%mechanical%solid%Concrete%icr
                   if (icr==1)then
                      allocate(element1(nelemx)%field(1)%rr(ndimn,ndimn,ngaus))
                      element1(nelemx)%field(1)%rr=0.
                   endif
                   if (icr==2.or.icr==3.or.icr==5)then !zhao09
                      allocate(element1(nelemx)%field(1)%strain0(nstre,ngaus),element1(nelemx)%field(1)%strain(nstre,ngaus))
                      element1(nelemx)%field(1)%strain0=0.;element1(nelemx)%field(1)%strain=0.
                   endif
                endif
                element1(nelemx)%field(1)%gpvar0=0.0
                element1(nelemx)%field(1)%gpvar=0.0
                if (iblks>jblks) &
                element1(nelemx)%field(1)%gpvar=ien0(ie)%fine_ele(ie0)%gpvar
                if (iblks>jblks) &
                element1(nelemx)%field(1)%gpvar0=ien0(ie)%fine_ele(ie0)%gpvar0
                !   write(7,*)'nelemx=',nelemx,'ie=',ie,'ie0=',ie0,'iblks=',iblks,'jblks=',jblks
                !   write(7,*)'gpvar0=',element1(nelemx)%field(1)%gpvar0(:,1)
                if (iblks>jblks.and.icr==1) &
                element1(nelemx)%field(1)%rr=ien0(ie)%fine_ele(ie0)%rr
                if (iblks>jblks.and.(icr==2.or.icr==3.or.icr==5)) & !zhao09
                element1(nelemx)%field(1)%strain=ien0(ie)%fine_ele(ie0)%strain
                if (iblks>jblks.and.(icr==2.or.icr==3.or.icr==5)) & !zhao09
                element1(nelemx)%field(1)%strain0=ien0(ie)%fine_ele(ie0)%strain0
             end do !ie0
          endif
       end do !ie
    end do    !igroup

    if (abs(rmesh)==2.and.ic==1)allocate(group2(ngroup))
    nelem2=0
    do ie=1,nelem1
       nelem2=nelem2+ien1(ie)%nsele
    end do

    if (nelem2==0) goto 10
    if (allocated(element2))deallocate(element2)
    allocate(element2(nelem2))
    nelemx=0
    do igroup=1,ngroup  !igroup

       index = group(igroup)%index
       matno = group(igroup)%matno
       material=props(matno)%mechanical%solid%material
       ngaus =elkn(index)%ggaus(1)%ngaus
       ngvar=group(igroup)%ngvar
       nstre=group(igroup)%nstre
       nelgroup=0
       do ie=1,nelem1
          if (ien1(ie)%group==igroup)then
             nsele=ien1(ie)%nsele
             nelgroup=nelgroup+nsele
          endif
       end do
       if (associated(group2(igroup)%list))deallocate(group2(igroup)%list)
       allocate(group2(igroup)%list(nelgroup))
       group2(igroup)%nelgroup=nelgroup
       nelgroup=0
       do ie=1,nelem1
          if (ien1(ie)%group==igroup)then
             nsele=ien1(ie)%nsele
             jblks=ien1(ie)%jblks
             do ie0=1,nsele
                nelgroup=nelgroup+1
                nelemx=nelemx+1
                group2(igroup)%list(nelgroup)=nelemx
                element2(nelemx)%index=index
                element2(nelemx)%group=igroup
                element2(nelemx)%matno=matno
                element2(nelemx)%nrfields=group(igroup)%nrfields
                element2(nelemx)%nstre=nstre
                nnode = elkn(group(igroup)%index)%nnode
                nevab = nnode*group(igroup)%dof(1)%nfdof
                allocate(element2(nelemx)%field(group(igroup)%nrfields))
                allocate(element2(nelemx)%field(1)%lnods_f(nnode))
                allocate(element2(nelemx)%field(1)%tload(nevab))
                allocate(element2(nelemx)%field(1)%eload(nevab))
                allocate(element2(nelemx)%field(1)%rload(nevab))
                allocate(element2(nelemx)%field(1)%khandmc(1)%fstif(nevab,nevab))
                element2(nelemx)%field(1)%khandmc(1)%fstif=0.0



                element2(nelemx)%field(1)%lnods_f=ien1(ie)%fine_ele(ie0)%list
                ien1(ie)%fine_ele(ie0)%delem=nelemx
                element2(nelemx)%jblks=ien1(ie)%jblks

                element2(nelemx)%field(1)%ngvar_f=ngvar
                allocate(element2(nelemx)%field(1)%gpvar0(ngvar,ngaus))
                allocate(element2(nelemx)%field(1)%gpvar(ngvar,ngaus))
                if (material=='CONCRETE')then
                   icr=props(matno)%mechanical%solid%Concrete%icr
                   if (icr==1)then
                      allocate(element2(nelemx)%field(1)%rr(ndimn,ndimn,ngaus))
                      element2(nelemx)%field(1)%rr=0.
                   endif
                   if (icr==2.or.icr==3) then
                      allocate(element2(nelemx)%field(1)%strain0(nstre,ngaus),element2(nelemx)%field(1)%strain(nstre,ngaus))
                      element2(nelemx)%field(1)%strain0=0.;element2(nelemx)%field(1)%strain=0.
                   endif
                endif
                element2(nelemx)%field(1)%gpvar0=0.0
                element2(nelemx)%field(1)%gpvar=0.0
                if (iblks>jblks) &
                element2(nelemx)%field(1)%gpvar=ien1(ie)%fine_ele(ie0)%gpvar
                if (iblks>jblks) &
                element2(nelemx)%field(1)%gpvar0=ien1(ie)%fine_ele(ie0)%gpvar0
                if (iblks>jblks.and.icr==1) &
                element2(nelemx)%field(1)%rr=ien1(ie)%fine_ele(ie0)%rr
                if (iblks>jblks.and.(icr==2.or.icr==3.or.icr==5)) & !zhao09
                element2(nelemx)%field(1)%strain=ien1(ie)%fine_ele(ie0)%strain
                if (iblks>jblks.and.(icr==2.or.icr==3.or.icr==5)) & !zhao09
                element2(nelemx)%field(1)%strain0=ien1(ie)%fine_ele(ie0)%strain0
             end do  !ie0
          endif
       end do  !ie
    end do    !igroup


    10 continue

    !  do ie=1,nelem1
    !  write(7,*)ie,element1(ie)%field(1)%lnods_f
    !  end do


    end subroutine  group_of_refined_element

    !!!!!!!!!!!!!!!!!!!!!!!!*****************************************************
    subroutine remesh1
    integer(ink) ie,nsele,i,nnode,imat,delem,nelemx,igroup
    integer(ink) ij,iside(2,12),ijline(12),j,i0,j0,i1,j1,iex,ie0
    integer(ink) n1,ib(6),iface_e(4,6),inf_e(6),n2,ij0,ij1,nsd0,nsd1,  &
    k,l,jk,j2,ijk(4),ijface(6)

    do ie=1,nelem0
       nsele=ien0(ie)%nsele
       if (nsele/=0.and.ice0(ie)==0)then
          ice0(ie)=1
          do i=1,nsele
             ien0(ie)%fine_ele(i)%delem=0
             ien0(ie)%fine_ele(i)%iremh=0
             nnode=ien0(ie)%fine_ele(i)%nnode
             imat=ien0(ie)%fine_ele(i)%imat
             nelem1=nelem1+1
             ien1(nelem1)%nnode=nnode
             ien1(nelem1)%imat=imat
             allocate(ien1(nelem1)%lnods(nnode))
             ien1(nelem1)%lnods=ien0(ie)%fine_ele(i)%list
             ien1(nelem1)%group=ien0(ie)%group
             ien1(nelem1)%ie=ie
             ien1(nelem1)%ie0=i
          end do
          !     elseif(nsele/=0.and.ice0(ie)==1)then
          !          do i=1,nsele
          !          write(7,*)'ie=',ie,'i=',i,'delem=',ien0(ie)%fine_ele(i)%delem
          !        end do
       endif
    end do
    !!!!!!!
    !!!!!!!
    if (abs(rmesh)==1)return

    !!!!!!!!第一层网格线段组
    do 10 ie=nelem10+1,nelem1
       !     delem=ien1(ie)%delem
       !     if(jce1(delem)==1) goto 10
       ij=0
       if (ndimn==3)then
          if (ien1(ie)%nnode==6)ij=9
          if (ien1(ie)%nnode==8)ij=12
       elseif(ndimn==2)then
          ij=ien1(ie)%nnode
       endif
       allocate(ien1(ie)%il(ij))
       iside=0;ijline=0
       call sdn1(ie,ij,iside)
       do 20 i=1,ij
          i0=iside(1,i)
          j0=iside(2,i)
          ijline(i)=0
          do 30 j=1,nline1
             i1=iline1(1,j)
             j1=iline1(2,j)
             if ((i0.eq.i1.and.j0.eq.j1).or.(i0.eq.j1.and.j0.eq.i1)) then
                ijline(i)=j
                if ((i0.eq.j1.and.j0.eq.i1))ijline(i)=-j
                goto 20
             endif
             30    continue
             20    continue
             do 40 i=1,ij
                if (ijline(i).eq.0) then
                   nline1=nline1+1
                   iline1(1,nline1)=iside(1,i)
                   iline1(2,nline1)=iside(2,i)
                   ien1(ie)%il(i)=nline1
                   neline1(nline1)=neline1(nline1)+1
                   ieline1(neline1(nline1),nline1)=ie
                else
                   j=ijline(i)
                   ien1(ie)%il(i)=j
                   neline1(abs(j))=neline1(abs(j))+1
                   ieline1(neline1(abs(j)),abs(j))=ie
                endif
                40    continue
                10    continue

                !!!! 第一层网格面组
                if (ndimn==2)goto 210

                do 100 ie=nelem10+1,nelem1
                   !     delem=ien1(ie)%delem
                   !     if(jce1(delem)==1) goto 100
                   n1=4+(ien1(ie)%nnode-4)/2
                   allocate(ien1(ie)%ienf(n1))

                   if  (n1.eq.5) then
                      ib(1)=132
                      ib(2)=456
                      ib(3)=2541
                      ib(4)=1463
                      ib(5)=3652
                   else
                      ib(1)=8415
                      ib(2)=3762
                      ib(3)=1265
                      ib(4)=8734
                      ib(5)=4321
                      ib(6)=7856
                   endif
                   do j=1,n1
                      n2=3
                      if ((n1.eq.5.and.j.gt.2).or.n1.eq.6) n2=4
                      call ijcx(ib(j),n2,ijk)
                      inf_e(j)=n2
                      iface_e(1:n2,j)=ien1(ie)%lnods(ijk(1:n2))
                   end do

                   do i=1,n1
                      ijface(i)=0
                      ij0=inf_e(i)
                      nsd0=sum(iface_e(1:ij0,i))

                      do 200 j=1,nface1
                         ij1=inf1(j)
                         if (ij1.ne.ij0) goto 200
                         nsd1=sum(iface1(1:ij1,j))
                         if (nsd1.ne.nsd0) goto 200
                         jk=0
                         do 13 k=1,ij0
                            do 14 l=1,ij1
                               if (iface_e(k,i).eq.iface1(l,j)) then
                                  jk=jk+1
                                  i0=k
                                  j0=l
                                  goto 15
                               endif
                            14    continue
                            15    continue
                         13   continue
                         if (jk.eq.ij1) then
                            j1=i0+1
                            if (j1.gt.ij1) j1=j1-ij1
                            j2=j0+1
                            if (j2.gt.ij1) j2=j2-ij1
                            ijface(i)=j
                            if (iface_e(j1,i).ne.iface1(j2,j)) ijface(i)=-j
                         endif
                         200  continue
                      end do  !i=1,n1

                      do 400  i=1,n1
                         if (ijface(i)==0)then
                            nface1=nface1+1
                            ien1(ie)%ienf(i)=nface1
                            inf1(nface1)=n2
                            ieface1(nface1)=ie
                            iface1(1:n2,nface1)=iface_e(1:n2,i)
                            nedface1(nface1)=nedface1(nface1)+1
                            iedface1(1,nface1)=ie
                         else
                            j=ijface(i)
                            ien1(ie)%ienf(i)=j
                            nedface1(abs(j))=nedface1(abs(j))+1
                            iedface1(nedface1(abs(j)),abs(j))=ie
                         endif
                      400  continue

                      100   continue
                      210   continue
                      !!!!!!refine
                      do ie=1,nelem1
                         iex=ien1(ie)%ie
                         ie0=ien1(ie)%ie0
                         delem=ien0(iex)%fine_ele(ie0)%delem
                         if (delem/=0)then
                            if (needmesh2(delem)==1)then
                               ien0(iex)%fine_ele(ie0)%iremh=1
                               if (ndimn==2) &
                               ijapl1(abs(ien1(ie)%il))=ijapl1(abs(ien1(ie)%il))+1
                               if (ndimn==3) &
                               ijapf1(abs(ien1(ie)%ienf))=ijapf1(abs(ien1(ie)%ienf))+1
                               if (ndimn==3) &
                               ijapl1(abs(ien1(ie)%il))=ijapl1(abs(ien1(ie)%il))+1
                            endif
                         endif
                      end do


                      do i1=1,nline1
                         if (ijapl1(i1)>0) &
                         line_divide1(i1)=ndefault(2)
                      enddo
                      call line_inter1
                      if (ndimn==2)then
                         call elem2_inter1
                      elseif(ndimn==3)then
                         call determine_face1
                         call face_inter1
                         call elem3_inter1
                      endif
                      end subroutine remesh1
                               !*********************************************************
    subroutine elem3_inter
    integer(ink) ib(6),n1,n2,npl1,npl2,npl3,j,ifa,ic,icp,ii,i,k,ie &
    ,nsele,i1,i2,di,idimn,inode,jnode,nnode
    integer(ink),allocatable::list1(:),list2(:),list(:,:,:),ij0(:)
    real(irk)    s,t,u,shape(8)
    do ie=1,nelem0
       if (needmesh1(ie)==0) goto 10
       nnode=ien0(ie)%nnode
       n1=5
       if (nnode==8)n1=6
       if  (n1.eq.5) then
          ib(1)=123
          ib(2)=456
          ib(3)=1254
          ib(4)=1364
          ib(5)=2365
       else
          ib(1)=1485
          ib(2)=2376
          ib(3)=1265
          ib(4)=4378
          ib(5)=1234
          ib(6)=5678
       endif

       ien0(ie)%jblks=iblks

       !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
       if (nnode==8)then
          npl1=linex(abs(ien0(ie)%il(1)))%npl
          npl2=linex(abs(ien0(ie)%il(4)))%npl
          npl3=linex(abs(ien0(ie)%il(9)))%npl
          allocate(list(npl1,npl2,npl3))
          do j=1,n1
             n2=3
             if ((n1.eq.5.and.j.gt.2).or.n1.eq.6) n2=4
             allocate(list1(n2),list2(n2),ij0(n2))
             ifa=abs(ien0(ie)%ienf(j))
             list1=facex(ifa)%surf
             call ijcx(ib(j),n2,ij0)
             list2=ien0(ie)%lnods(ij0)
             call find4_surf_character(n2,ic,icp,list1,list2)
             if (ic==1) call list_surf_fine_81(ifa,j,icp,npl1,npl2,npl3,list,facex(ifa)%list)
             if (ic==-1)call list_surf_fine_82(ifa,j,icp,npl1,npl2,npl3,list,facex(ifa)%list)
             deallocate(list1,list2,ij0)
          end do
          do k=1,npl3-2
             do j=1,npl2-2
                do i=1,npl1-2
                   s=float(i)/float((npl1-1))
                   s=2.*s-1
                   t=float(j)/float((npl2-1))
                   t=2.*t-1
                   u=float(k)/float((npl3-1))
                   u=2.*u-1
                   npoinx=npoinx+1
                   call cor3(nnode,s,t,u,ie,shape)

                   !     listrp(npoinx)%nintf=nnode
                   !       allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                   !       listrp(npoinx)%listf(1:nnode)=ien0(ie)%lnods(1:nnode)
                   !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                   list(i+1,j+1,k+1)=npoinx
                end do
             end do
          end do

          nsele=(npl1-1)*(npl2-1)*(npl3-1)
          ien0(ie)%nsele=nsele
          allocate(ien0(ie)%fine_ele(nsele))
          nsele=0
          do k=1,npl3-1
             do j=1,npl2-1
                do i=1,npl1-1
                   nsele=nsele+1
                   ien0(ie)%fine_ele(nsele)%nnode=8
                   allocate(ien0(ie)%fine_ele(nsele)%list(8))
                   ien0(ie)%fine_ele(nsele)%list(1)=list(i,j,k)
                   ien0(ie)%fine_ele(nsele)%list(2)=list(i+1,j,k)
                   ien0(ie)%fine_ele(nsele)%list(3)=list(i+1,j+1,k)
                   ien0(ie)%fine_ele(nsele)%list(4)=list(i,j+1,k)

                   ien0(ie)%fine_ele(nsele)%list(5)=list(i,j,k+1)
                   ien0(ie)%fine_ele(nsele)%list(6)=list(i+1,j,k+1)
                   ien0(ie)%fine_ele(nsele)%list(7)=list(i+1,j+1,k+1)
                   ien0(ie)%fine_ele(nsele)%list(8)=list(i,j+1,k+1)
                   ien0(ie)%fine_ele(nsele)%imat=ien0(ie)%imat
                end do
             end do
          end do
          allocate(ien0(ie)%list(npl1,npl2,npl3))
          ien0(ie)%npl1=npl1
          ien0(ie)%npl2=npl2
          ien0(ie)%npl3=npl3
          ien0(ie)%list=list
          deallocate(list)
       else if(nnode==6)then
          npl1=linex(abs(ien0(ie)%il(1)))%npl
          npl2=linex(abs(ien0(ie)%il(3)))%npl
          npl3=linex(abs(ien0(ie)%il(7)))%npl
          allocate(list(npl1,npl2,npl3))
          do j=1,n1
             n2=3
             if ((n1.eq.5.and.j.gt.2).or.n1.eq.6) n2=4
             allocate(list1(n2),list2(n2),ij0(n2))
             ifa=abs(ien0(ie)%ienf(j))
             list1=facex(ifa)%surf
             call ijcx(ib(j),n2,ij0)
             list2=ien0(ie)%lnods(ij0)
             if (n2==4) &
             call find4_surf_character(n2,ic,icp,list1,list2)
             if (n2==3) &
                call find3_surf_character(n2,ic,list1,list2)
                if (n2==4)then
                   if (ic==1) call list_surf_fine_641(ifa,j,icp,npl1,npl2,npl3,list,facex(ifa)%list)
                   if (ic==-1)call list_surf_fine_642(ifa,j,icp,npl1,npl2,npl3,list,facex(ifa)%list)
                else
                   call list_surf_fine_3(ic,ifa,j,npl3,list,facex(ifa)%list)
                endif
                deallocate(list1,list2,ij0)
             end do

             do k=1,npl3-2
                do j=1,npl1-2
                   do i=1,npl1-2-j
                      i1=list(1,j+1,k+1)
                      i2=list(npl1-j,j+1,k+1)

                      di=npl1-j-1
                      s=float(i)/float(di)
                      t=1.-s
                      npoinx=npoinx+1
                      do idimn=1,ndimn
                         coordx(idimn,npoinx)=t*coordx(idimn,i1)+s*coordx(idimn,i2)
                      end do

                      shape=0.
                      do inode=1,nnode
                         do jnode=1,listrp(i1)%nintf
                            if (ien0(ie)%lnods(inode)==listrp(i1)%listf(jnode))then
                               shape(inode)=shape(inode)+t*listrp(i1)%rintf(jnode)
                            endif
                         end do
                      end do
                      do inode=1,nnode
                         do jnode=1,listrp(i2)%nintf
                            if (ien0(ie)%lnods(inode)==listrp(i2)%listf(jnode))then
                               shape(inode)=shape(inode)+s*listrp(i2)%rintf(jnode)
                            endif
                         end do
                      end do
                      !     listrp(npoinx)%nintf=nnode
                      !       allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                      !       listrp(npoinx)%listf(1:nnode)=ien0(ie)%lnods(1:nnode)
                      !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                      list(i+1,j+1,k+1)=npoinx
                   end do
                end do
             end do

             nsele=facex(abs(ien0(ie)%ienf(1)))%nsface*(npl3-1)
             ien0(ie)%nsele=nsele
             allocate(ien0(ie)%fine_ele(nsele))
             nsele=0
             do k=1,npl3-1
                do j=1,npl2-1
                   do i=1,npl1-j
                      nsele=nsele+1
                      if (i==(npl1-j))then
                         ien0(ie)%fine_ele(nsele)%nnode=6
                         allocate(ien0(ie)%fine_ele(nsele)%list(6))
                         ien0(ie)%fine_ele(nsele)%list(1)=list(i,j,k)
                         ien0(ie)%fine_ele(nsele)%list(2)=list(i+1,j,k)
                         ien0(ie)%fine_ele(nsele)%list(3)=list(i,j+1,k)

                         ien0(ie)%fine_ele(nsele)%list(4)=list(i,j,k+1)
                         ien0(ie)%fine_ele(nsele)%list(5)=list(i+1,j,k+1)
                         ien0(ie)%fine_ele(nsele)%list(6)=list(i,j+1,k+1)
                         ien0(ie)%fine_ele(nsele)%imat=ien0(ie)%imat
                      else
                         ien0(ie)%fine_ele(nsele)%nnode=8
                         allocate(ien0(ie)%fine_ele(nsele)%list(8))
                         ien0(ie)%fine_ele(nsele)%list(1)=list(i,j,k)
                         ien0(ie)%fine_ele(nsele)%list(2)=list(i+1,j,k)
                         ien0(ie)%fine_ele(nsele)%list(3)=list(i+1,j+1,k)
                         ien0(ie)%fine_ele(nsele)%list(4)=list(i,j+1,k)

                         ien0(ie)%fine_ele(nsele)%list(5)=list(i,j,k+1)
                         ien0(ie)%fine_ele(nsele)%list(6)=list(i+1,j,k+1)
                         ien0(ie)%fine_ele(nsele)%list(7)=list(i+1,j+1,k+1)
                         ien0(ie)%fine_ele(nsele)%list(8)=list(i,j+1,k+1)
                         ien0(ie)%fine_ele(nsele)%imat=ien0(ie)%imat
                      endif
                   end do
                end do
             end do
             allocate(ien0(ie)%list(npl1,npl2,npl3))
             ien0(ie)%npl1=npl1
             ien0(ie)%npl2=npl2
             ien0(ie)%npl3=npl3
             ien0(ie)%list=list
             deallocate(list)
          endif !for nnode==8

          10     continue
       end do

       7 format(10i10)

       end subroutine elem3_inter
       !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
       !*********************************************************
    subroutine elem3_inter1
    integer(ink) ib(6),n1,n2,npl1,npl2,npl3,j,ifa,ic,icp,ii,i,k,ie, &
    nsele,i1,i2,di,idimn,inode,jnode,nnode
    integer(ink),allocatable::list1(:),list2(:),list(:,:,:),ij0(:)
    real(irk)    s,t,u,shape(8)
    do ie=1,nelem1
       if (needmesh2(ie)==0) goto 10
       nnode=ien1(ie)%nnode
       n1=5
       ien1(ie)%jblks=iblks
       if (nnode==8)n1=6
       if  (n1.eq.5) then
          ib(1)=123
          ib(2)=456
          ib(3)=1254
          ib(4)=1364
          ib(5)=2365
       else
          ib(1)=1485
          ib(2)=2376
          ib(3)=1265
          ib(4)=4378
          ib(5)=1234
          ib(6)=5678
       endif

       !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
       if (nnode==8)then
          npl1=linex1(abs(ien1(ie)%il(1)))%npl
          npl2=linex1(abs(ien1(ie)%il(4)))%npl
          npl3=linex1(abs(ien1(ie)%il(9)))%npl
          allocate(list(npl1,npl2,npl3))
          do j=1,n1
             n2=3
             if ((n1.eq.5.and.j.gt.2).or.n1.eq.6) n2=4
             allocate(list1(n2),list2(n2),ij0(n2))
             ifa=abs(ien1(ie)%ienf(j))
             list1=facex1(ifa)%surf
             call ijcx(ib(j),n2,ij0)
             list2=ien1(ie)%lnods(ij0)
             call find4_surf_character(n2,ic,icp,list1,list2)
             if (ic==1) call list_surf_fine_81(ifa,j,icp,npl1,npl2,npl3,list,facex1(ifa)%list)
             if (ic==-1)call list_surf_fine_82(ifa,j,icp,npl1,npl2,npl3,list,facex1(ifa)%list)
             deallocate(list1,list2,ij0)
          end do
          do k=1,npl3-2
             do j=1,npl2-2
                do i=1,npl1-2
                   s=float(i)/float((npl1-1))
                   s=2.*s-1
                   t=float(j)/float((npl2-1))
                   t=2.*t-1
                   u=float(k)/float((npl3-1))
                   u=2.*u-1
                   npoinx=npoinx+1
                   call cor31(nnode,s,t,u,ie,shape)

                   list(i+1,j+1,k+1)=npoinx
                end do
             end do
          end do

          nsele=(npl1-1)*(npl2-1)*(npl3-1)
          ien1(ie)%nsele=nsele
          allocate(ien1(ie)%fine_ele(nsele))
          nsele=0
          do k=1,npl3-1
             do j=1,npl2-1
                do i=1,npl1-1
                   nsele=nsele+1
                   ien1(ie)%fine_ele(nsele)%nnode=8
                   allocate(ien1(ie)%fine_ele(nsele)%list(8))
                   ien1(ie)%fine_ele(nsele)%list(1)=list(i,j,k)
                   ien1(ie)%fine_ele(nsele)%list(2)=list(i+1,j,k)
                   ien1(ie)%fine_ele(nsele)%list(3)=list(i+1,j+1,k)
                   ien1(ie)%fine_ele(nsele)%list(4)=list(i,j+1,k)

                   ien1(ie)%fine_ele(nsele)%list(5)=list(i,j,k+1)
                   ien1(ie)%fine_ele(nsele)%list(6)=list(i+1,j,k+1)
                   ien1(ie)%fine_ele(nsele)%list(7)=list(i+1,j+1,k+1)
                   ien1(ie)%fine_ele(nsele)%list(8)=list(i,j+1,k+1)
                   ien1(ie)%fine_ele(nsele)%imat=ien1(ie)%imat
                end do
             end do
          end do
          allocate(ien1(ie)%list(npl1,npl2,npl3))
          ien1(ie)%npl1=npl1
          ien1(ie)%npl2=npl2
          ien1(ie)%npl3=npl3
          ien1(ie)%list=list
          deallocate(list)
       else if(nnode==6)then
          npl1=linex1(abs(ien1(ie)%il(1)))%npl
          npl2=linex1(abs(ien1(ie)%il(3)))%npl
          npl3=linex1(abs(ien1(ie)%il(7)))%npl
          allocate(list(npl1,npl2,npl3))
          do j=1,n1
             n2=3
             if ((n1.eq.5.and.j.gt.2).or.n1.eq.6) n2=4
             allocate(list1(n2),list2(n2),ij0(n2))
             ifa=abs(ien1(ie)%ienf(j))
             list1=facex1(ifa)%surf
             call ijcx(ib(j),n2,ij0)
             list2=ien1(ie)%lnods(ij0)
             if (n2==4) &
             call find4_surf_character(n2,ic,icp,list1,list2)
             if (n2==3) &
                call find3_surf_character(n2,ic,list1,list2)
                if (n2==4)then
                   if (ic==1) call list_surf_fine_641(ifa,j,icp,npl1,npl2,npl3,list,facex1(ifa)%list)
                   if (ic==-1)call list_surf_fine_642(ifa,j,icp,npl1,npl2,npl3,list,facex1(ifa)%list)
                else
                   call list_surf_fine_3(ic,ifa,j,npl3,list,facex1(ifa)%list)
                endif
                deallocate(list1,list2,ij0)
             end do

             do k=1,npl3-2
                do j=1,npl1-2
                   do i=1,npl1-2-j
                      i1=list(1,j+1,k+1)
                      i2=list(npl1-j,j+1,k+1)

                      di=npl1-j-1
                      s=float(i)/float(di)
                      t=1.-s
                      npoinx=npoinx+1
                      do idimn=1,ndimn
                         coordx(idimn,npoinx)=t*coordx(idimn,i1)+s*coordx(idimn,i2)
                      end do

                      shape=0.
                      do inode=1,nnode
                         do jnode=1,listrp(i1)%nintf
                            if (ien1(ie)%lnods(inode)==listrp(i1)%listf(jnode))then
                               shape(inode)=shape(inode)+t*listrp(i1)%rintf(jnode)
                            endif
                         end do
                      end do
                      do inode=1,nnode
                         do jnode=1,listrp(i2)%nintf
                            if (ien1(ie)%lnods(inode)==listrp(i2)%listf(jnode))then
                               shape(inode)=shape(inode)+s*listrp(i2)%rintf(jnode)
                            endif
                         end do
                      end do

                      list(i+1,j+1,k+1)=npoinx
                   end do
                end do
             end do

             nsele=facex1(abs(ien1(ie)%ienf(1)))%nsface*(npl3-1)
             ien1(ie)%nsele=nsele
             allocate(ien1(ie)%fine_ele(nsele))
             nsele=0
             do k=1,npl3-1
                do j=1,npl2-1
                   do i=1,npl1-j
                      nsele=nsele+1
                      if (i==(npl1-j))then
                         ien1(ie)%fine_ele(nsele)%nnode=6
                         allocate(ien1(ie)%fine_ele(nsele)%list(6))
                         ien1(ie)%fine_ele(nsele)%list(1)=list(i,j,k)
                         ien1(ie)%fine_ele(nsele)%list(2)=list(i+1,j,k)
                         ien1(ie)%fine_ele(nsele)%list(3)=list(i,j+1,k)

                         ien1(ie)%fine_ele(nsele)%list(4)=list(i,j,k+1)
                         ien1(ie)%fine_ele(nsele)%list(5)=list(i+1,j,k+1)
                         ien1(ie)%fine_ele(nsele)%list(6)=list(i,j+1,k+1)
                         ien1(ie)%fine_ele(nsele)%imat=ien1(ie)%imat
                      else
                         ien1(ie)%fine_ele(nsele)%nnode=8
                         allocate(ien1(ie)%fine_ele(nsele)%list(8))
                         ien1(ie)%fine_ele(nsele)%list(1)=list(i,j,k)
                         ien1(ie)%fine_ele(nsele)%list(2)=list(i+1,j,k)
                         ien1(ie)%fine_ele(nsele)%list(3)=list(i+1,j+1,k)
                         ien1(ie)%fine_ele(nsele)%list(4)=list(i,j+1,k)

                         ien1(ie)%fine_ele(nsele)%list(5)=list(i,j,k+1)
                         ien1(ie)%fine_ele(nsele)%list(6)=list(i+1,j,k+1)
                         ien1(ie)%fine_ele(nsele)%list(7)=list(i+1,j+1,k+1)
                         ien1(ie)%fine_ele(nsele)%list(8)=list(i,j+1,k+1)
                         ien1(ie)%fine_ele(nsele)%imat=ien1(ie)%imat
                      endif
                   end do
                end do
             end do
             allocate(ien1(ie)%list(npl1,npl2,npl3))
             ien1(ie)%npl1=npl1
             ien1(ie)%npl2=npl2
             ien1(ie)%npl3=npl3
             ien1(ie)%list=list
             deallocate(list)
          endif !for nnode==8

          10     continue
       end do

       7 format(10i10)

       end subroutine elem3_inter1
       !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine find4_surf_character(n2,ic,icp,list1,list2)
    integer(ink) ic,icp,list1(:),list2(:),i1,n2,i0
    do  i0=1,n2
       if (list1(1).eq.list2(i0)) goto 2
    end do
    print *,'error in elem_surface_connection'
    print *,'1list1=',list1
    print *,'1list2=',list2
    stop
    2    continue
    i1=i0+1
    if (i1>n2)i1=i1-n2
    ic=1
    if (list1(2)/=list2(i1))ic=-1
    if (i0==1)icp=1
    if (i0==4)icp=2
    if (i0==3)icp=3
    if (i0==2)icp=4
    end subroutine find4_surf_character
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine find3_surf_character(n2,ic,list1,list2)
    integer(ink) ic,list1(:),list2(:),i1,n2,i0
    do  i0=1,n2
       if (list1(1).eq.list2(i0)) goto 2
    end do
    print *,'list1=',list1
    print *,'list2=',list2
    print *,'error in elem_surface_connection'
    stop
    2    continue
    i1=i0+1
    if (i1>n2)i1=i1-n2
    ic=1
    if (list1(2)/=list2(i1))ic=-1
    if (i0/=1)then
       print *,'err in find3_sur,i0/=1'
       stop
    endif
    end subroutine find3_surf_character
    !!!!!!!!
    subroutine list_surf_fine_81(ifa,j,icp,npl1,npl2,npl3,list,listx)
    integer(ink) ifa,i,j,icp,npl1,npl2,npl3,list(:,:,:),nl1,nl2,listx(:,:)
    !          nl1=facex(ifa)%npl1
    !          nl2=facex(ifa)%npl2
    nl1=size(listx,1)
    nl2=size(listx,2)
    if (icp==1)then !!1
       if (j==1)list(1,:,:)=listx
       if (j==2)list(npl1,:,:)=listx
       if (j==3)list(:,1,:)=listx
       if (j==4)list(:,npl2,:)=listx
       if (j==5)list(:,:,1)=listx
       if (j==6)list(:,:,npl3)=listx
    elseif(icp==2)then !!2
       if (j==1)then
          do i=1,nl2
             list(1,i,1:nl1)=listx(nl1:1:-1,i)
          end do
       elseif(j==2)then
          do i=1,nl2
             list(npl1,i,1:nl1)=listx(nl1:1:-1,i)
          end do
       elseif(j==3)then
          do i=1,nl2
             list(i,1,1:nl1)=listx(nl1:1:-1,i)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(i,npl2,1:nl1)=listx(nl1:1:-1,i)
          end do
       elseif(j==5)then
          do i=1,nl2
             list(i,1:nl1,1)=listx(nl1:1:-1,i)
          end do
       elseif(j==6)then
          do i=1,nl2
             list(i,1:nl1,npl3)=listx(nl1:1:-1,i)
          end do
       end if
    elseif(icp==3)then    !!3
       if (j==1)then
          do i=1,nl1
             list(1,i,1:nl2)=listx(nl1-i+1,nl2:1:-1)
          end do
       elseif(j==2)then
          do i=1,nl1
             list(npl1,i,1:nl2)=listx(nl1-i+1,nl2:1:-1)
          end do
       elseif(j==3)then
          do i=1,nl1
             list(i,1,1:nl2)=listx(nl1-i+1,nl2:1:-1)
          end do
       elseif(j==4)then
          do i=1,nl1
             list(i,npl2,1:nl2)=listx(nl1-i+1,nl2:1:-1)
          end do
       elseif(j==5)then
          do i=1,nl1
             list(i,1:nl2,1)=listx(nl1-i+1,nl2:1:-1)
          end do
       elseif(j==6)then
          do i=1,nl1
             list(i,1:nl2,npl3)=listx(nl1-i+1,nl2:1:-1)
          end do
       endif
    elseif(icp==4)then    !!3
       if (j==1)then
          do i=1,nl1
             list(1,1:nl2,i)=listx(i,nl2:1:-1)
          end do
       elseif(j==2)then
          do i=1,nl1
             list(npl1,1:nl2,i)=listx(i,nl2:1:-1)
          end do
       elseif(j==3)then
          do i=1,nl1
             list(1:nl2,1,i)=listx(i,nl2:1:-1)
          end do
       elseif(j==4)then
          do i=1,nl1
             list(1:nl2,npl2,i)=listx(i,nl2:1:-1)
          end do
       elseif(j==5)then
          do i=1,nl1
             list(1:nl2,i,1)=listx(i,nl2:1:-1)
          end do
       elseif(j==6)then
          do i=1,nl1
             list(1:nl2,i,npl3)=listx(i,nl2:1:-1)
          end do
       endif
    endif
    end subroutine list_surf_fine_81
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!
    subroutine list_surf_fine_641(ifa,j,icp,npl1,npl2,npl3,list,listx)
    integer(ink) ifa,i,j,icp,npl1,npl2,npl3,list(:,:,:),nl1,nl2,i0,j0,listx(:,:)
    !          nl1=facex(ifa)%npl1
    !          nl2=facex(ifa)%npl2
    nl1=size(listx,1)
    nl2=size(listx,2)
    if (icp==1)then !!1
       if (j==3)list(:,1,:)=listx
       if (j==4)list(1,:,:)=listx
       if (j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl1-i0+1,i0,j0)=listx(i0,j0)
             end do
          end do
       endif
    elseif(icp==2)then !!2
       if (j==3)then
          do i=1,nl2
             list(i,1,1:nl1)=listx(nl1:1:-1,i)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(1,i,1:nl1)=listx(nl1:1:-1,i)
          end do
       elseif(j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl2-j0+1,j0,i0)=listx(nl1-i0+1,j0)
             end do
          end do
       end if
    elseif(icp==3)then    !!3
       if (j==3)then
          do i=1,nl1
             list(i,1,1:nl2)=listx(nl1-i+1,nl2:1:-1)
          end do
       elseif(j==4)then
          do i=1,nl1
             list(1,i,1:nl2)=listx(nl1-i+1,nl2:1:-1)
          end do
       elseif(j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl1-i0+1,i0,j0)=listx(nl1-i0+1,nl2-j0+1)
             end do
          end do
       endif
    elseif(icp==4)then    !!3
       if (j==3)then
          do i=1,nl1
             list(1:nl2,1,i)=listx(i,nl2:1:-1)
          end do
       elseif(j==4)then
          do i=1,nl1
             list(1,1:nl2,i)=listx(i,nl2:1:-1)
          end do
       elseif(j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl2-j0+1,j0,i0)=listx(i0,nl2-j0+1)
             end do
          end do
       endif
    endif
    end subroutine list_surf_fine_641
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!
    subroutine list_surf_fine_82(ifa,j,icp,npl1,npl2,npl3,list,listx)
    integer(ink) ifa,i,j,icp,npl1,npl2,npl3,list(:,:,:),nl1,nl2,listx(:,:)
    !          nl1=facex(ifa)%npl1
    !          nl2=facex(ifa)%npl2
    nl1=size(listx,1)
    nl2=size(listx,2)
    if (icp==1)then !!1
       if (j==1)then
          do i=1,nl2
             list(1,i,1:nl1)=listx(1:nl1,i)
          end do
       elseif(j==2)then
          do i=1,nl2
             list(npl1,i,1:nl1)=listx(1:nl1,i)
          end do
       elseif(j==3)then
          do i=1,nl2
             list(i,1,1:nl1)=listx(1:nl1,i)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(i,npl2,1:nl1)=listx(1:nl1,i)
          end do
       elseif(j==5)then
          do i=1,nl2
             list(i,1:nl1,1)=listx(1:nl1,i)
          end do
       elseif(j==6)then
          do i=1,nl2
             list(i,1:nl1,npl3)=listx(1:nl1,i)
          end do
       end if
    elseif(icp==2)then !!2
       if (j==1)then
          do i=1,nl1
             list(1,i,1:nl2)=listx(i,nl2:1:-1)
          end do
       elseif(j==2)then
          do i=1,nl1
             list(npl1,i,1:nl2)=listx(i,nl2:1:-1)
          end do
       elseif(j==3)then
          do i=1,nl1
             list(i,1,1:nl2)=listx(i,nl2:1:-1)
          end do
       elseif(j==4)then
          do i=1,nl1
             list(i,npl2,1:nl2)=listx(i,nl2:1:-1)
          end do
       elseif(j==5)then
          do i=1,nl1
             list(i,1:nl2,1)=listx(i,nl2:1:-1)
          end do
       elseif(j==6)then
          do i=1,nl1
             list(i,1:nl2,npl3)=listx(i,nl2:1:-1)
          end do
       end if
    elseif(icp==3)then    !!3
       if (j==1)then
          do i=1,nl2
             list(1,i,1:nl1)=listx(nl1:1:-1,nl2-i+1)
          end do
       elseif(j==2)then
          do i=1,nl2
             list(npl1,i,1:nl1)=listx(nl1:1:-1,nl2-i+1)
          end do
       elseif(j==3)then
          do i=1,nl2
             list(i,1,1:nl1)=listx(nl1:1:-1,nl2-i+1)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(i,npl2,1:nl1)=listx(nl1:1:-1,nl2-i+1)
          end do
       elseif(j==5)then
          do i=1,nl2
             list(i,1:nl1,1)=listx(nl1:1:-1,nl2-i+1)
          end do
       elseif(j==6)then
          do i=1,nl2
             list(i,1:nl1,npl3)=listx(nl1:1:-1,nl2-i+1)
          end do
       endif
    elseif(icp==4)then    !!3
       if (j==1)then
          do i=1,nl2
             list(1,1:nl1,i)=listx(nl1:1:-1,i)
          end do
       elseif(j==2)then
          do i=1,nl2
             list(npl1,1:nl1,i)=listx(nl1:1:-1,i)
          end do
       elseif(j==3)then
          do i=1,nl2
             list(1:nl1,1,i)=listx(nl1:1:-1,i)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(1:nl1,npl2,i)=listx(nl1:1:-1,i)
          end do
       elseif(j==5)then
          do i=1,nl2
             list(1:nl1,i,1)=listx(nl1:1:-1,i)
          end do
       elseif(j==6)then
          do i=1,nl2
             list(1:nl1,i,npl3)=listx(nl1:1:-1,i)
          end do
       endif
    endif
    end subroutine list_surf_fine_82
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!
    subroutine list_surf_fine_642(ifa,j,icp,npl1,npl2,npl3,list,listx)
    integer(ink) ifa,i,j,icp,npl1,npl2,npl3,list(:,:,:),nl1,nl2,i0,j0,listx(:,:)
    !          nl1=facex(ifa)%npl1
    !          nl2=facex(ifa)%npl2
    nl1=size(listx,1)
    nl2=size(listx,2)

    if (icp==1)then !!1
       if (j==3)then
          do i=1,nl2
             list(i,1,1:nl1)=listx(1:nl1,i)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(1,i,1:nl1)=listx(1:nl1,i)
          end do
       elseif(j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl2-j0+1,j0,i0)=listx(i0,j0)
             end do
          end do
       end if
    elseif(icp==2)then !!2
       if (j==3)then
          do i=1,nl1
             list(i,1,1:nl2)=listx(i,nl2:1:-1)
          end do
       elseif(j==4)then
          do i=1,nl1
             list(1,i,1:nl2)=listx(i,nl2:1:-1)
          end do
       elseif(j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl1-i0+1,i0,j0)=listx(i0,nl2-j0+1)
             end do
          end do
       end if
    elseif(icp==3)then    !!3
       if (j==3)then
          do i=1,nl2
             list(i,1,1:nl1)=listx(nl1:1:-1,nl2-i+1)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(1,i,1:nl1)=listx(nl1:1:-1,nl2-i+1)
          end do
       elseif(j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl2-j0+1,j0,i0)=listx(nl1-i0+1,nl2-j0+1)
             end do
          end do
       endif
    elseif(icp==4)then    !!3
       if (j==3)then
          do i=1,nl2
             list(1:nl1,1,i)=listx(nl1:1:-1,i)
          end do
       elseif(j==4)then
          do i=1,nl2
             list(1,1:nl1,i)=listx(nl1:1:-1,i)
          end do
       elseif(j==5)then
          do j0=1,nl2
             do i0=1,nl1
                list(nl1-i0+1,i0,j0)=listx(nl1-i0+1,j0)
             end do
          end do
       endif
    endif
    end subroutine list_surf_fine_642
    !!!!!!!!
    subroutine list_surf_fine_3(ic,ifa,j0,npl3,list,listx)
    integer(ink) ifa,i,j,ic,npl3,list(:,:,:),nl1,j0,listx(:,:)
    nl1=facex(ifa)%npl1
    if (ic==1)then !!1
       if (j0==1)then
          do j=1,nl1
             do i=1,nl1-j+1
                list(i,j,1)=listx(i,j)
             end do
          end do
       elseif(j0==2)then
          do j=1,nl1
             do i=1,nl1-j+1
                list(i,j,npl3)=listx(i,j)
             end do
          end do
       end if
    elseif(ic==-1)then
       if (j0==1)then
          do j=1,nl1
             do i=1,nl1-j+1
                list(i,j,1)=listx(j,i)
             end do
          end do
       elseif(j0==2)then
          do j=1,nl1
             do i=1,nl1-j+1
                list(i,j,npl3)=listx(j,i)
             end do
          end do
       end if
    endif
    end subroutine list_surf_fine_3
    !!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine determine_face
    integer(ink) i0,j0,ie,npl1,npl2,npl3,npl4
    !     allocate(facex(nface))
    do i0=1,nface
       if (ijapf(i0)<1) goto 22
       allocate(facex(i0)%surf(inf(i0)),facex(i0)%il(inf(i0)))
       facex(i0)%surf(1:inf(i0))=iface(1:inf(i0),i0)
       facex(i0)%nnode=inf(i0)
       ie=iedface(1,i0)
       do j0=1,size(ien0(ie)%ienf)
          if (ien0(ie)%ienf(j0)==i0) goto 11
       end do
       print *,' error in surface connection with elements'
       stop
       11    continue
       if (ien0(ie)%nnode==8)then
          if (j0==1)then
             facex(i0)%il(1)=-ien0(ie)%il(12);facex(i0)%il(2)= ien0(ie)%il(4)
             facex(i0)%il(3)= ien0(ie)%il( 9);facex(i0)%il(4)=-ien0(ie)%il(8)
          elseif(j0==2)then
             facex(i0)%il(1)=ien0(ie)%il(11);facex(i0)%il(2)=-ien0(ie)%il(6)
             facex(i0)%il(3)=-ien0(ie)%il(10);facex(i0)%il(4)= ien0(ie)%il(2)
          elseif(j0==3)then
             facex(i0)%il(1)= ien0(ie)%il(1);facex(i0)%il(2)= ien0(ie)%il(10)
             facex(i0)%il(3)=-ien0(ie)%il(5);facex(i0)%il(4)=-ien0(ie)%il(9)
          elseif(j0==4)then
             facex(i0)%il(1)=-ien0(ie)%il(7);facex(i0)%il(2)=-ien0(ie)%il(11)
             facex(i0)%il(3)= ien0(ie)%il(3);facex(i0)%il(4)= ien0(ie)%il(12)
          elseif(j0==5)then
             facex(i0)%il(1)=-ien0(ie)%il(3);facex(i0)%il(2)=-ien0(ie)%il(2)
             facex(i0)%il(3)=-ien0(ie)%il(1);facex(i0)%il(4)=-ien0(ie)%il(4)
          elseif(j0==6)then
             facex(i0)%il(1)=ien0(ie)%il(7);facex(i0)%il(2)=ien0(ie)%il(8)
             facex(i0)%il(3)=ien0(ie)%il(5);facex(i0)%il(4)=ien0(ie)%il(6)
          endif
          npl1=linex(abs(facex(i0)%il(1)))%npl
          npl2=linex(abs(facex(i0)%il(2)))%npl
          npl3=linex(abs(facex(i0)%il(3)))%npl
          npl4=linex(abs(facex(i0)%il(4)))%npl
          if (npl1/=npl3.or.npl2/=npl4)then
             print *,'npl1,npl3=',npl1,npl3,'npl2,npl4=',npl2,npl4
             print *,'different mesh numbers in surface=',i0,'j0=',j0
             print *,'il=',abs(facex(i0)%il(1:4))
             stop
          endif
          facex(i0)%npl1=npl1;facex(i0)%npl2=npl2
       elseif(ien0(ie)%nnode==6)then
          if (j0==1)then
             facex(i0)%il(1)=-ien0(ie)%il(3);facex(i0)%il(2)=-ien0(ie)%il(2)
             facex(i0)%il(3)=-ien0(ie)%il(1)
          elseif(j0==2)then
             facex(i0)%il(1)=ien0(ie)%il(4);facex(i0)%il(2)=ien0(ie)%il(5)
             facex(i0)%il(3)=ien0(ie)%il(6)
          elseif(j0==3)then
             facex(i0)%il(1)= ien0(ie)%il(8);facex(i0)%il(2)=-ien0(ie)%il(4)
             facex(i0)%il(3)=-ien0(ie)%il(7);facex(i0)%il(4)= ien0(ie)%il(1)
          elseif(j0==5)then
             facex(i0)%il(1)= ien0(ie)%il(9);facex(i0)%il(2)=-ien0(ie)%il(5)
             facex(i0)%il(3)=-ien0(ie)%il(8);facex(i0)%il(4)= ien0(ie)%il(2)
          elseif(j0==4)then
             facex(i0)%il(1)= ien0(ie)%il(7);facex(i0)%il(2)=-ien0(ie)%il(6)
             facex(i0)%il(3)=-ien0(ie)%il(9);facex(i0)%il(4)= ien0(ie)%il(3)
          endif
          if (inf(i0)==4)then
             npl1=linex(abs(facex(i0)%il(1)))%npl
             npl2=linex(abs(facex(i0)%il(2)))%npl
             npl3=linex(abs(facex(i0)%il(3)))%npl
             npl4=linex(abs(facex(i0)%il(4)))%npl
             if (npl1/=npl3.or.npl2/=npl4)then
                print *,'different mesh numbers in surface=',i0,'j0=',j0
                stop
             endif
          elseif(inf(i0)==3)then
             npl1=linex(abs(facex(i0)%il(1)))%npl
             npl2=linex(abs(facex(i0)%il(2)))%npl
             npl3=linex(abs(facex(i0)%il(3)))%npl
             if (npl1/=npl3.or.npl1/=npl2)then
                print *,'different mesh numbers in surface=',i0,'j0=',j0
                stop
             endif
          endif
          facex(i0)%npl1=npl1;facex(i0)%npl2=npl2
       endif
       22   continue
    end do

    end subroutine determine_face
    !!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine determine_face1
    integer(ink) i0,j0,ie,npl1,npl2,npl3,npl4
    !     allocate(facex1(nface))
    do i0=1,nface1
       if (ijapf1(i0)<1) goto 22
       allocate(facex1(i0)%surf(inf1(i0)),facex1(i0)%il(inf1(i0)))
       facex1(i0)%surf(1:inf1(i0))=iface1(1:inf1(i0),i0)
       facex1(i0)%nnode=inf1(i0)
       ie=iedface1(1,i0)
       do j0=1,size(ien1(ie)%ienf)
          if (ien1(ie)%ienf(j0)==i0) goto 11
       end do
       print *,' error in surface connection with elements'
       stop
       11    continue
       if (ien1(ie)%nnode==8)then
          if (j0==1)then
             facex1(i0)%il(1)=-ien1(ie)%il(12);facex1(i0)%il(2)= ien1(ie)%il(4)
             facex1(i0)%il(3)= ien1(ie)%il( 9);facex1(i0)%il(4)=-ien1(ie)%il(8)
          elseif(j0==2)then
             facex1(i0)%il(1)=ien1(ie)%il(11);facex1(i0)%il(2)=-ien1(ie)%il(6)
             facex1(i0)%il(3)=-ien1(ie)%il(10);facex1(i0)%il(4)= ien1(ie)%il(2)
          elseif(j0==3)then
             facex1(i0)%il(1)= ien1(ie)%il(1);facex1(i0)%il(2)= ien1(ie)%il(10)
             facex1(i0)%il(3)=-ien1(ie)%il(5);facex1(i0)%il(4)=-ien1(ie)%il(9)
          elseif(j0==4)then
             facex1(i0)%il(1)=-ien1(ie)%il(7);facex1(i0)%il(2)=-ien1(ie)%il(11)
             facex1(i0)%il(3)= ien1(ie)%il(3);facex1(i0)%il(4)= ien1(ie)%il(12)
          elseif(j0==5)then
             facex1(i0)%il(1)=-ien1(ie)%il(3);facex1(i0)%il(2)=-ien1(ie)%il(2)
             facex1(i0)%il(3)=-ien1(ie)%il(1);facex1(i0)%il(4)=-ien1(ie)%il(4)
          elseif(j0==6)then
             facex1(i0)%il(1)=ien1(ie)%il(7);facex1(i0)%il(2)=ien1(ie)%il(8)
             facex1(i0)%il(3)=ien1(ie)%il(5);facex1(i0)%il(4)=ien1(ie)%il(6)
          endif
          npl1=linex1(abs(facex1(i0)%il(1)))%npl
          npl2=linex1(abs(facex1(i0)%il(2)))%npl
          npl3=linex1(abs(facex1(i0)%il(3)))%npl
          npl4=linex1(abs(facex1(i0)%il(4)))%npl
          if (npl1/=npl3.or.npl2/=npl4)then
             print *,'npl1,npl3=',npl1,npl3,'npl2,npl4=',npl2,npl4
             print *,'different mesh numbers in surface=',i0,'j0=',j0
             print *,'il=',abs(facex1(i0)%il(1:4))
             stop
          endif
          facex1(i0)%npl1=npl1;facex1(i0)%npl2=npl2
       elseif(ien1(ie)%nnode==6)then
          if (j0==1)then
             facex1(i0)%il(1)=-ien1(ie)%il(3);facex1(i0)%il(2)=-ien1(ie)%il(2)
             facex1(i0)%il(3)=-ien1(ie)%il(1)
          elseif(j0==2)then
             facex1(i0)%il(1)=ien1(ie)%il(4);facex1(i0)%il(2)=ien1(ie)%il(5)
             facex1(i0)%il(3)=ien1(ie)%il(6)
          elseif(j0==3)then
             facex1(i0)%il(1)= ien1(ie)%il(8);facex1(i0)%il(2)=-ien1(ie)%il(4)
             facex1(i0)%il(3)=-ien1(ie)%il(7);facex1(i0)%il(4)= ien1(ie)%il(1)
          elseif(j0==5)then
             facex1(i0)%il(1)= ien1(ie)%il(9);facex1(i0)%il(2)=-ien1(ie)%il(5)
             facex1(i0)%il(3)=-ien1(ie)%il(8);facex1(i0)%il(4)= ien1(ie)%il(2)
          elseif(j0==4)then
             facex1(i0)%il(1)= ien1(ie)%il(7);facex1(i0)%il(2)=-ien1(ie)%il(6)
             facex1(i0)%il(3)=-ien1(ie)%il(9);facex1(i0)%il(4)= ien1(ie)%il(3)
          endif
          if (inf(i0)==4)then
             npl1=linex1(abs(facex1(i0)%il(1)))%npl
             npl2=linex1(abs(facex1(i0)%il(2)))%npl
             npl3=linex1(abs(facex1(i0)%il(3)))%npl
             npl4=linex1(abs(facex1(i0)%il(4)))%npl
             if (npl1/=npl3.or.npl2/=npl4)then
                print *,'different mesh numbers in surface=',i0,'j0=',j0
                stop
             endif
          elseif(inf(i0)==3)then
             npl1=linex1(abs(facex1(i0)%il(1)))%npl
             npl2=linex1(abs(facex1(i0)%il(2)))%npl
             npl3=linex1(abs(facex1(i0)%il(3)))%npl
             if (npl1/=npl3.or.npl1/=npl2)then
                print *,'different mesh numbers in surface=',i0,'j0=',j0
                stop
             endif
          endif
          facex1(i0)%npl1=npl1;facex1(i0)%npl2=npl2
       endif
       22   continue
    end do

    end subroutine determine_face1
    !!!!!!!!!!!!!!!!!!!
    subroutine face_inter
    integer(ink) i0,nnode,npl1,npl2,jl,i,j,nsface,di,ii,i1,i2,idimn,inode,jnode,ijx
    real(irk)    s,t,shape(4)
    integer(ink),allocatable::list(:,:)

    do i0=1,nface
       if (ijapf(i0)<1) goto 10
       ijx=ijapf(i0)
       if (ijx==1)ijapf(i0)=-1
       if (ijx==2)ijapf(i0)=0
       nnode=facex(i0)%nnode
       npl1=facex(i0)%npl1
       npl2=facex(i0)%npl2
       allocate(list(npl1,npl2),facex(i0)%list(npl1,npl2))
       list=0
       if (nnode==4)then
          jl=facex(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex(-jl)%list(npl1:1:-1)
          endif
          jl=-facex(i0)%il(3)
          if (jl>0)then
             list(1:npl1,npl2)=linex(jl)%list(1:npl1)
          else
             list(1:npl1,npl2)=linex(-jl)%list(npl1:1:-1)
          endif
          jl=-facex(i0)%il(4)
          if (jl>0)then
             !        print *,'jl=',jl,'i0=',i0,'npl2=',npl2,'size=',size(linex(jl)%list)
             list(1,1:npl2)=linex(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex(-jl)%list(npl2:1:-1)
          endif
          jl= facex(i0)%il(2)
          if (jl>0)then
             list(npl1,1:npl2)=linex(jl)%list(1:npl2)
          else
             list(npl1,1:npl2)=linex(-jl)%list(npl2:1:-1)
          endif
          do j=1,npl2-2
             do i=1,npl1-2
                s=float(i)/float((npl1-1))
                s=2.*s-1
                t=float(j)/float((npl2-1))
                t=2.*t-1
                npoinx=npoinx+1
                call cor2(nnode,s,t,i0,shape)

                listrp(npoinx)%nintf=nnode
                allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                listrp(npoinx)%listf(1:nnode)=facex(i0)%surf(1:nnode)
                listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsface=(npl1-1)*(npl2-1)
          facex(i0)%nsface=nsface
          allocate(facex(i0)%fine_surface(nsface))
          nsface=0
          do j=1,npl2-1
             do i=1,npl1-1
                nsface=nsface+1
                facex(i0)%fine_surface(nsface)%nnode=4
                allocate(facex(i0)%fine_surface(nsface)%list(4))
                facex(i0)%fine_surface(nsface)%list(1)=list(i,j)
                facex(i0)%fine_surface(nsface)%list(2)=list(i+1,j)
                facex(i0)%fine_surface(nsface)%list(3)=list(i+1,j+1)
                facex(i0)%fine_surface(nsface)%list(4)=list(i,j+1)
             end do
          end do
          facex(i0)%list=list
       elseif(nnode==3)then
          if (npl1/=npl2)then
             print *,'err refined mesh for npl1/=npl2 when nnode=3,iface=',i0
             stop
          endif
          jl=facex(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex(-jl)%list(npl1:1:-1)
          endif
          jl=-facex(i0)%il(3)
          if (jl>0)then
             list(1,1:npl2)=linex(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex(-jl)%list(npl2:1:-1)
          endif
          jl= facex(i0)%il(2)
          if (jl>0)then
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex(jl)%list(ii)
             end do
          else
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex(-jl)%list(npl1-ii+1)
             end do
          endif
          do j=1,npl1-2
             do i=1,npl1-2-j
                i1=list(1,j+1)
                i2=list(npl1-j,j+1)
                di=npl1-j-1
                s=float(i)/float(di)
                t=1.-s
                npoinx=npoinx+1
                do idimn=1,ndimn
                   coordx(idimn,npoinx)=t*coordx(idimn,i1)+s*coordx(idimn,i2)
                end do

                shape=0.
                do inode=1,nnode
                   do jnode=1,listrp(i1)%nintf
                      if (facex(i0)%surf(inode)==listrp(i1)%listf(jnode))then
                         shape(inode)=shape(inode)+t*listrp(i1)%rintf(jnode)
                      endif
                   end do
                end do
                do inode=1,nnode
                   do jnode=1,listrp(i2)%nintf
                      if (facex(i0)%surf(inode)==listrp(i2)%listf(jnode))then
                         shape(inode)=shape(inode)+s*listrp(i2)%rintf(jnode)
                      endif
                   end do
                end do

                listrp(npoinx)%nintf=nnode
                allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                listrp(npoinx)%listf(1:nnode)=facex(i0)%surf(1:nnode)
                listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsface=0
          do i=1,npl1-1
             nsface=nsface+i
          end do
          facex(i0)%nsface=nsface
          allocate(facex(i0)%fine_surface(nsface))
          nsface=0
          do j=1,npl1-1
             do i=1,npl1-j
                nsface=nsface+1
                if (i==(npl1-j))then
                   facex(i0)%fine_surface(nsface)%nnode=3
                   allocate(facex(i0)%fine_surface(nsface)%list(3))
                   facex(i0)%fine_surface(nsface)%list(1)=list(i,j)
                   facex(i0)%fine_surface(nsface)%list(2)=list(i+1,j)
                   facex(i0)%fine_surface(nsface)%list(3)=list(i,j+1)
                else
                   facex(i0)%fine_surface(nsface)%nnode=4
                   allocate(facex(i0)%fine_surface(nsface)%list(4))
                   facex(i0)%fine_surface(nsface)%list(1)=list(i,j)
                   facex(i0)%fine_surface(nsface)%list(2)=list(i+1,j)
                   facex(i0)%fine_surface(nsface)%list(3)=list(i+1,j+1)
                   facex(i0)%fine_surface(nsface)%list(4)=list(i,j+1)
                endif
             end do
          end do
          facex(i0)%list=list
       endif
       deallocate(list)
       10      continue
    end do
    end subroutine face_inter
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine face_inter1
    integer(ink) i0,nnode,npl1,npl2,jl,i,j,nsface,di,ii,i1,i2,idimn,inode,jnode,ijx
    integer(ink) nintf,lnintf
    real(irk)    s,t,shape(4),i3,i4
    integer(ink),allocatable::list(:,:),listf(:),ijcx(:)
    real(irk)   ,allocatable::rintf(:)

    do i0=1,nface1
       if (ijapf1(i0)<1) goto 10
       ijx=ijapf1(i0)
       if (ijx==1)ijapf1(i0)=-1
       if (ijx==2)ijapf1(i0)=0
       nnode=facex1(i0)%nnode
       npl1=facex1(i0)%npl1
       npl2=facex1(i0)%npl2
       allocate(list(npl1,npl2),facex1(i0)%list(npl1,npl2))
       list=0
       if (nnode==4)then
          jl=facex1(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex1(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex1(-jl)%list(npl1:1:-1)
          endif
          jl=-facex1(i0)%il(3)
          if (jl>0)then
             list(1:npl1,npl2)=linex1(jl)%list(1:npl1)
          else
             list(1:npl1,npl2)=linex1(-jl)%list(npl1:1:-1)
          endif
          jl=-facex1(i0)%il(4)
          if (jl>0)then
             !        print *,'jl=',jl,'i0=',i0,'npl2=',npl2,'size=',size(linex(jl)%list)
             list(1,1:npl2)=linex1(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex1(-jl)%list(npl2:1:-1)
          endif
          jl= facex1(i0)%il(2)
          if (jl>0)then
             list(npl1,1:npl2)=linex1(jl)%list(1:npl2)
          else
             list(npl1,1:npl2)=linex1(-jl)%list(npl2:1:-1)
          endif
          do j=1,npl2-2
             do i=1,npl1-2
                s=float(i)/float((npl1-1))
                s=2.*s-1
                t=float(j)/float((npl2-1))
                t=2.*t-1
                npoinx=npoinx+1
                call cor21(nnode,s,t,i0,shape)


                !!!!!!!!!!!!!!!!!!!!!!!!!!!!
                lnintf=nnode
                do i1=1,nnode
                   i2=facex1(i0)%surf(i1)
                   if (outlistrp(i2)>0)lnintf=lnintf+listrp(i2)%nintf-1
                enddo
                allocate(listf(lnintf),rintf(lnintf))

                lnintf=0
                do i1=1,nnode
                   i2=facex1(i0)%surf(i1)
                   if (outlistrp(i2)>0)then
                      do i3=1,listrp(i2)%nintf
                         lnintf=lnintf+1
                         listf(lnintf)=listrp(i2)%listf(i3)
                         rintf(lnintf)=shape(i1)*listrp(i2)%rintf(i3)
                      end do
                   else
                      lnintf=lnintf+1
                      listf(lnintf)=i2
                      rintf(lnintf)=shape(i1)
                   endif
                end do

                allocate(ijcx(lnintf))
                ijcx=1
                do i1=1,lnintf
                   if (ijcx(i1)/=0)then
                      do i2=1,lnintf
                         if (i1/=i2.and.ijcx(i2)/=0)then
                            if (listf(i2)==listf(i1))then
                               rintf(i1)=rintf(i1)+rintf(i2)
                               ijcx(i2)=0
                            endif
                         endif
                      end do
                   endif
                end do

                nintf=sum(ijcx)
                listrp(npoinx)%nintf=nintf
                allocate(listrp(npoinx)%listf(nintf),listrp(npoinx)%rintf(nintf))
                nintf=0
                do i1=1,lnintf
                   if (ijcx(i1)==1)then
                      nintf=nintf+1
                      listrp(npoinx)%listf(nintf)=listf(i1)
                      listrp(npoinx)%rintf(nintf)=rintf(i1)
                   endif
                end do
                deallocate(ijcx,listf,rintf)
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!

                !     listrp(npoinx)%nintf=nnode
                !       allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                !       listrp(npoinx)%listf(1:nnode)=facex1(i0)%surf(1:nnode)
                !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsface=(npl1-1)*(npl2-1)
          facex1(i0)%nsface=nsface
          allocate(facex1(i0)%fine_surface(nsface))
          nsface=0
          do j=1,npl2-1
             do i=1,npl1-1
                nsface=nsface+1
                facex1(i0)%fine_surface(nsface)%nnode=4
                allocate(facex1(i0)%fine_surface(nsface)%list(4))
                facex1(i0)%fine_surface(nsface)%list(1)=list(i,j)
                facex1(i0)%fine_surface(nsface)%list(2)=list(i+1,j)
                facex1(i0)%fine_surface(nsface)%list(3)=list(i+1,j+1)
                facex1(i0)%fine_surface(nsface)%list(4)=list(i,j+1)
             end do
          end do
          facex1(i0)%list=list
       elseif(nnode==3)then
          if (npl1/=npl2)then
             print *,'err refined mesh for npl1/=npl2 when nnode=3,iface=',i0
             stop
          endif
          jl=facex1(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex1(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex1(-jl)%list(npl1:1:-1)
          endif
          jl=-facex1(i0)%il(3)
          if (jl>0)then
             list(1,1:npl2)=linex1(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex1(-jl)%list(npl2:1:-1)
          endif
          jl= facex1(i0)%il(2)
          if (jl>0)then
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex1(jl)%list(ii)
             end do
          else
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex1(-jl)%list(npl1-ii+1)
             end do
          endif
          do j=1,npl1-2
             do i=1,npl1-2-j
                i1=list(1,j+1)
                i2=list(npl1-j,j+1)
                di=npl1-j-1
                s=float(i)/float(di)
                t=1.-s
                npoinx=npoinx+1
                do idimn=1,ndimn
                   coordx(idimn,npoinx)=t*coordx(idimn,i1)+s*coordx(idimn,i2)
                end do

                shape=0.
                do inode=1,nnode
                   do jnode=1,listrp(i1)%nintf
                      if (facex1(i0)%surf(inode)==listrp(i1)%listf(jnode))then
                         shape(inode)=shape(inode)+t*listrp(i1)%rintf(jnode)
                      endif
                   end do
                end do
                do inode=1,nnode
                   do jnode=1,listrp(i2)%nintf
                      if (facex1(i0)%surf(inode)==listrp(i2)%listf(jnode))then
                         shape(inode)=shape(inode)+s*listrp(i2)%rintf(jnode)
                      endif
                   end do
                end do
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!
                lnintf=nnode
                do i1=1,nnode
                   i2=facex1(i0)%surf(i1)
                   if (outlistrp(i2)>0)lnintf=lnintf+listrp(i2)%nintf-1
                enddo
                allocate(listf(lnintf),rintf(lnintf))

                lnintf=0
                do i1=1,nnode
                   i2=facex1(i0)%surf(i1)
                   if (outlistrp(i2)>0)then
                      do i3=1,listrp(i2)%nintf
                         lnintf=lnintf+1
                         listf(lnintf)=listrp(i2)%listf(i3)
                         rintf(lnintf)=shape(i1)*listrp(i2)%rintf(i3)
                      end do
                   else
                      lnintf=lnintf+1
                      listf(lnintf)=i2
                      rintf(lnintf)=shape(i1)
                   endif
                end do

                allocate(ijcx(lnintf))
                ijcx=1
                do i1=1,lnintf
                   if (ijcx(i1)/=0)then
                      do i2=1,lnintf
                         if (i1/=i2.and.ijcx(i2)/=0)then
                            if (listf(i2)==listf(i1))then
                               rintf(i1)=rintf(i1)+rintf(i2)
                               ijcx(i2)=0
                            endif
                         endif
                      end do
                   endif
                end do

                nintf=sum(ijcx)
                listrp(npoinx)%nintf=nintf
                allocate(listrp(npoinx)%listf(nintf),listrp(npoinx)%rintf(nintf))
                nintf=0
                do i1=1,lnintf
                   if (ijcx(i1)==1)then
                      nintf=nintf+1
                      listrp(npoinx)%listf(nintf)=listf(i1)
                      listrp(npoinx)%rintf(nintf)=rintf(i1)
                   endif
                end do
                deallocate(ijcx,listf,rintf)
                !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                !     listrp(npoinx)%nintf=nnode
                !       allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                !       listrp(npoinx)%listf(1:nnode)=facex1(i0)%surf(1:nnode)
                !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsface=0
          do i=1,npl1-1
             nsface=nsface+i
          end do
          facex1(i0)%nsface=nsface
          allocate(facex1(i0)%fine_surface(nsface))
          nsface=0
          do j=1,npl1-1
             do i=1,npl1-j
                nsface=nsface+1
                if (i==(npl1-j))then
                   facex1(i0)%fine_surface(nsface)%nnode=3
                   allocate(facex1(i0)%fine_surface(nsface)%list(3))
                   facex1(i0)%fine_surface(nsface)%list(1)=list(i,j)
                   facex1(i0)%fine_surface(nsface)%list(2)=list(i+1,j)
                   facex1(i0)%fine_surface(nsface)%list(3)=list(i,j+1)
                else
                   facex1(i0)%fine_surface(nsface)%nnode=4
                   allocate(facex1(i0)%fine_surface(nsface)%list(4))
                   facex1(i0)%fine_surface(nsface)%list(1)=list(i,j)
                   facex1(i0)%fine_surface(nsface)%list(2)=list(i+1,j)
                   facex1(i0)%fine_surface(nsface)%list(3)=list(i+1,j+1)
                   facex1(i0)%fine_surface(nsface)%list(4)=list(i,j+1)
                endif
             end do
          end do
          facex1(i0)%list=list
       endif
       deallocate(list)
       10      continue
    end do
    end subroutine face_inter1
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    !!!!!!!!!!!!!!!!!!!
    subroutine elem2_inter
    integer(ink) i0,nnode,npl1,npl2,jl,i,j,nsele,di,ii,i1,i2,idimn,inode,jnode,imat
    real(irk)    s,t,shape(4)
    integer(ink),allocatable::list(:,:)

    do i0=1,nelem0
       if (needmesh1(i0)==0)goto 10
       nnode=ien0(i0)%nnode
       imat=ien0(i0)%imat
       npl1=linex(abs(ien0(i0)%il(1)))%npl
       npl2=linex(abs(ien0(i0)%il(2)))%npl
       ien0(i0)%npl1=npl1
       ien0(i0)%npl2=npl2
       allocate(list(npl1,npl2),ien0(i0)%listp(npl1,npl2))
       list=0
       ien0(i0)%jblks=iblks
       if (nnode==4)then
          jl=ien0(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex(-jl)%list(npl1:1:-1)
          endif
          jl=-ien0(i0)%il(3)
          if (jl>0)then
             list(1:npl1,npl2)=linex(jl)%list(1:npl1)
          else
             list(1:npl1,npl2)=linex(-jl)%list(npl1:1:-1)
          endif
          jl=-ien0(i0)%il(4)
          if (jl>0)then
             !        print *,'jl=',jl,'i0=',i0,'npl2=',npl2,'size=',size(linex(jl)%list)
             list(1,1:npl2)=linex(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex(-jl)%list(npl2:1:-1)
          endif
          jl= ien0(i0)%il(2)
          if (jl>0)then
             list(npl1,1:npl2)=linex(jl)%list(1:npl2)
          else
             list(npl1,1:npl2)=linex(-jl)%list(npl2:1:-1)
          endif
          do j=1,npl2-2
             do i=1,npl1-2
                s=float(i)/float((npl1-1))
                s=2.*s-1
                t=float(j)/float((npl2-1))
                t=2.*t-1
                npoinx=npoinx+1
                call cor22(nnode,s,t,i0,shape)

                !     listrp(npoinx)%nintf=nnode
                !       allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                !       listrp(npoinx)%listf(1:nnode)=ien0(i0)%lnods(1:nnode)
                !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsele=(npl1-1)*(npl2-1)
          ien0(i0)%nsele=nsele
          allocate(ien0(i0)%fine_ele(nsele))
          nsele=0
          do j=1,npl2-1
             do i=1,npl1-1
                nsele=nsele+1
                ien0(i0)%fine_ele(nsele)%nnode=4
                ien0(i0)%fine_ele(nsele)%imat=imat
                allocate(ien0(i0)%fine_ele(nsele)%list(4))
                ien0(i0)%fine_ele(nsele)%list(1)=list(i,j)
                ien0(i0)%fine_ele(nsele)%list(2)=list(i+1,j)
                ien0(i0)%fine_ele(nsele)%list(3)=list(i+1,j+1)
                ien0(i0)%fine_ele(nsele)%list(4)=list(i,j+1)
             end do
          end do
          ien0(i0)%listp=list
       elseif(nnode==3)then
          if (npl1/=npl2)then
             print *,'err refined mesh for npl1/=npl2 when nnode=3,iface=',i0
             stop
          endif
          jl=ien0(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex(-jl)%list(npl1:1:-1)
          endif
          jl=-ien0(i0)%il(3)
          if (jl>0)then
             list(1,1:npl2)=linex(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex(-jl)%list(npl2:1:-1)
          endif
          jl= ien0(i0)%il(2)
          if (jl>0)then
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex(jl)%list(ii)
             end do
          else
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex(-jl)%list(npl1-ii+1)
             end do
          endif
          do j=1,npl1-2
             do i=1,npl1-2-j
                i1=list(1,j+1)
                i2=list(npl1-j,j+1)
                di=npl1-j-1
                s=float(i)/float(di)
                t=1.-s
                npoinx=npoinx+1
                do idimn=1,ndimn
                   coordx(idimn,npoinx)=t*coordx(idimn,i1)+s*coordx(idimn,i2)
                end do

                shape=0.
                do inode=1,nnode
                   do jnode=1,listrp(i1)%nintf
                      if (ien0(i0)%lnods(inode)==listrp(i1)%listf(jnode))then
                         shape(inode)=shape(inode)+t*listrp(i1)%rintf(jnode)
                      endif
                   end do
                end do
                do inode=1,nnode
                   do jnode=1,listrp(i2)%nintf
                      if (ien0(i0)%lnods(inode)==listrp(i2)%listf(jnode))then
                         shape(inode)=shape(inode)+s*listrp(i2)%rintf(jnode)
                      endif
                   end do
                end do

                !     listrp(npoinx)%nintf=nnode
                !       allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                !       listrp(npoinx)%listf(1:nnode)=ien0(i0)%lnods(1:nnode)
                !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsele=0
          do i=1,npl1-1
             nsele=nsele+i
          end do
          ien0(i0)%nsele=nsele
          allocate(ien0(i0)%fine_ele(nsele))
          nsele=0
          do j=1,npl1-1
             do i=1,npl1-j
                nsele=nsele+1
                if (i==(npl1-j))then
                   ien0(i0)%fine_ele(nsele)%nnode=3
                   ien0(i0)%fine_ele(nsele)%imat=imat
                   allocate(ien0(i0)%fine_ele(nsele)%list(3))
                   ien0(i0)%fine_ele(nsele)%list(1)=list(i,j)
                   ien0(i0)%fine_ele(nsele)%list(2)=list(i+1,j)
                   ien0(i0)%fine_ele(nsele)%list(3)=list(i,j+1)
                else
                   ien0(i0)%fine_ele(nsele)%nnode=4
                   ien0(i0)%fine_ele(nsele)%imat=imat
                   allocate(ien0(i0)%fine_ele(nsele)%list(4))
                   ien0(i0)%fine_ele(nsele)%list(1)=list(i,j)
                   ien0(i0)%fine_ele(nsele)%list(2)=list(i+1,j)
                   ien0(i0)%fine_ele(nsele)%list(3)=list(i+1,j+1)
                   ien0(i0)%fine_ele(nsele)%list(4)=list(i,j+1)
                endif
             end do
          end do
          ien0(i0)%listp=list
       endif
       deallocate(list)
       10      continue
    end do
    end subroutine elem2_inter
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine elem2_inter1
    integer(ink) i0,nnode,npl1,npl2,jl,i,j,nsele,di,ii,i1,i2,idimn,inode,jnode,imat
    integer(ink) iex,ie0,delem
    real(irk)    s,t,shape(4)
    integer(ink),allocatable::list(:,:)

    do i0=1,nelem1
       iex=ien1(i0)%ie
       ie0=ien1(i0)%ie0
       delem=ien0(iex)%fine_ele(ie0)%delem
       if (delem==0)goto 10
       if (needmesh2(delem)==0)goto 10
       nnode=ien1(i0)%nnode
       imat=ien1(i0)%imat
       npl1=linex1(abs(ien1(i0)%il(1)))%npl
       npl2=linex1(abs(ien1(i0)%il(2)))%npl
       ien1(i0)%npl1=npl1
       ien1(i0)%npl2=npl2
       allocate(list(npl1,npl2),ien1(i0)%listp(npl1,npl2))
       list=0
       ien1(i0)%jblks=iblks
       if (nnode==4)then
          jl=ien1(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex1(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex1(-jl)%list(npl1:1:-1)
          endif
          jl=-ien1(i0)%il(3)
          if (jl>0)then
             list(1:npl1,npl2)=linex1(jl)%list(1:npl1)
          else
             list(1:npl1,npl2)=linex1(-jl)%list(npl1:1:-1)
          endif
          jl=-ien1(i0)%il(4)
          if (jl>0)then
             !        print *,'jl=',jl,'i0=',i0,'npl2=',npl2,'size=',size(linex(jl)%list)
             list(1,1:npl2)=linex1(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex1(-jl)%list(npl2:1:-1)
          endif
          jl= ien1(i0)%il(2)
          if (jl>0)then
             list(npl1,1:npl2)=linex1(jl)%list(1:npl2)
          else
             list(npl1,1:npl2)=linex1(-jl)%list(npl2:1:-1)
          endif
          do j=1,npl2-2
             do i=1,npl1-2
                s=float(i)/float((npl1-1))
                s=2.*s-1
                t=float(j)/float((npl2-1))
                t=2.*t-1
                npoinx=npoinx+1
                call cor22_1(nnode,s,t,i0,shape)

                !     listrp(npoinx)%nintf=nnode
                !      allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                !       listrp(npoinx)%listf(1:nnode)=ien1(i0)%lnods(1:nnode)
                !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsele=(npl1-1)*(npl2-1)
          ien1(i0)%nsele=nsele
          allocate(ien1(i0)%fine_ele(nsele))
          nsele=0
          do j=1,npl2-1
             do i=1,npl1-1
                nsele=nsele+1
                ien1(i0)%fine_ele(nsele)%nnode=4
                ien1(i0)%fine_ele(nsele)%imat=imat
                allocate(ien1(i0)%fine_ele(nsele)%list(4))
                ien1(i0)%fine_ele(nsele)%list(1)=list(i,j)
                ien1(i0)%fine_ele(nsele)%list(2)=list(i+1,j)
                ien1(i0)%fine_ele(nsele)%list(3)=list(i+1,j+1)
                ien1(i0)%fine_ele(nsele)%list(4)=list(i,j+1)
             end do
          end do
          ien1(i0)%listp=list
       elseif(nnode==3)then
          if (npl1/=npl2)then
             print *,'err refined mesh for npl1/=npl2 when nnode=3,iface=',i0
             stop
          endif
          jl=ien1(i0)%il(1)
          if (jl>0)then
             list(1:npl1,1)=linex1(jl)%list(1:npl1)
          else
             list(1:npl1,1)=linex1(-jl)%list(npl1:1:-1)
          endif
          jl=-ien1(i0)%il(3)
          if (jl>0)then
             list(1,1:npl2)=linex1(jl)%list(1:npl2)
          else
             list(1,1:npl2)=linex1(-jl)%list(npl2:1:-1)
          endif
          jl= ien1(i0)%il(2)
          if (jl>0)then
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex1(jl)%list(ii)
             end do
          else
             do ii=1,npl1
                list(npl1-ii+1,ii)=linex1(-jl)%list(npl1-ii+1)
             end do
          endif
          do j=1,npl1-2
             do i=1,npl1-2-j
                i1=list(1,j+1)
                i2=list(npl1-j,j+1)
                di=npl1-j-1
                s=float(i)/float(di)
                t=1.-s
                npoinx=npoinx+1
                do idimn=1,ndimn
                   coordx(idimn,npoinx)=t*coordx(idimn,i1)+s*coordx(idimn,i2)
                end do

                shape=0.
                do inode=1,nnode
                   do jnode=1,listrp(i1)%nintf
                      if (ien1(i0)%lnods(inode)==listrp(i1)%listf(jnode))then
                         shape(inode)=shape(inode)+t*listrp(i1)%rintf(jnode)
                      endif
                   end do
                end do
                do inode=1,nnode
                   do jnode=1,listrp(i2)%nintf
                      if (ien1(i0)%lnods(inode)==listrp(i2)%listf(jnode))then
                         shape(inode)=shape(inode)+s*listrp(i2)%rintf(jnode)
                      endif
                   end do
                end do

                !     listrp(npoinx)%nintf=nnode
                !       allocate(listrp(npoinx)%listf(nnode),listrp(npoinx)%rintf(nnode))
                !       listrp(npoinx)%listf(1:nnode)=ien1(i0)%lnods(1:nnode)
                !       listrp(npoinx)%rintf(1:nnode)=shape(1:nnode)

                list(i+1,j+1)=npoinx
             end do
          end do

          nsele=0
          do i=1,npl1-1
             nsele=nsele+i
          end do
          ien1(i0)%nsele=nsele
          allocate(ien1(i0)%fine_ele(nsele))
          nsele=0
          do j=1,npl1-1
             do i=1,npl1-j
                nsele=nsele+1
                if (i==(npl1-j))then
                   ien1(i0)%fine_ele(nsele)%nnode=3
                   ien1(i0)%fine_ele(nsele)%imat=imat
                   allocate(ien1(i0)%fine_ele(nsele)%list(3))
                   ien1(i0)%fine_ele(nsele)%list(1)=list(i,j)
                   ien1(i0)%fine_ele(nsele)%list(2)=list(i+1,j)
                   ien1(i0)%fine_ele(nsele)%list(3)=list(i,j+1)
                else
                   ien1(i0)%fine_ele(nsele)%nnode=4
                   ien1(i0)%fine_ele(nsele)%imat=imat
                   allocate(ien1(i0)%fine_ele(nsele)%list(4))
                   ien1(i0)%fine_ele(nsele)%list(1)=list(i,j)
                   ien1(i0)%fine_ele(nsele)%list(2)=list(i+1,j)
                   ien1(i0)%fine_ele(nsele)%list(3)=list(i+1,j+1)
                   ien1(i0)%fine_ele(nsele)%list(4)=list(i,j+1)
                endif
             end do
          end do
          ien1(i0)%listp=list
       endif
       deallocate(list)
       10      continue
    end do
    end subroutine elem2_inter1
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine cor22(nnode,s,t,i0,shape)
    integer(ink) nnode,i0,idimn,inode
    real(irk) s,t,st,shape(:)
    st=s*t
    if (nnode==4)then
       shape(1) = (1-t-s+st)*0.25
       shape(2) = (1-t+s-st)*0.25
       shape(3) = (1+t+s+st)*0.25
       shape(4) = (1+t-s-st)*0.25
       do idimn=1,ndimn
          coordx(idimn,npoinx)=0.
          do inode=1,nnode
             coordx(idimn,npoinx)=coordx(idimn,npoinx)+shape(inode)*coordx(idimn,ien0(i0)%lnods(inode))
          end do
       end do
    end if
    end subroutine cor22
    !!!!!!!!!!!!!!!!!
    subroutine cor22_1(nnode,s,t,i0,shape)
    integer(ink) nnode,i0,idimn,inode
    real(irk) s,t,st,shape(:)
    st=s*t
    if (nnode==4)then
       shape(1) = (1-t-s+st)*0.25
       shape(2) = (1-t+s-st)*0.25
       shape(3) = (1+t+s+st)*0.25
       shape(4) = (1+t-s-st)*0.25
       do idimn=1,ndimn
          coordx(idimn,npoinx)=0.
          do inode=1,nnode
             coordx(idimn,npoinx)=coordx(idimn,npoinx)+shape(inode)*coordx(idimn,ien1(i0)%lnods(inode))
          end do
       end do
    end if
    end subroutine cor22_1
    !!!!!!!!!!!!!!


    subroutine cor2(nnode,s,t,i0,shape)
    integer(ink) nnode,i0,idimn,inode
    real(irk) s,t,st,shape(:)
    st=s*t
    if (nnode==4)then
       shape(1) = (1-t-s+st)*0.25
       shape(2) = (1-t+s-st)*0.25
       shape(3) = (1+t+s+st)*0.25
       shape(4) = (1+t-s-st)*0.25
       do idimn=1,ndimn
          coordx(idimn,npoinx)=0.
          do inode=1,nnode
             coordx(idimn,npoinx)=coordx(idimn,npoinx)+shape(inode)*coordx(idimn,facex(i0)%surf(inode))
          end do
       end do
    end if
    end subroutine cor2
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine cor21(nnode,s,t,i0,shape)
    integer(ink) nnode,i0,idimn,inode
    real(irk) s,t,st,shape(:)
    st=s*t
    if (nnode==4)then
       shape(1) = (1-t-s+st)*0.25
       shape(2) = (1-t+s-st)*0.25
       shape(3) = (1+t+s+st)*0.25
       shape(4) = (1+t-s-st)*0.25
       do idimn=1,ndimn
          coordx(idimn,npoinx)=0.
          do inode=1,nnode
             coordx(idimn,npoinx)=coordx(idimn,npoinx)+shape(inode)*coordx(idimn,facex1(i0)%surf(inode))
          end do
       end do
    end if
    end subroutine cor21
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    subroutine cor3(nnode,s,t,u,i0,shape)
    integer(ink) nnode,i0,idimn,inode,j,k
    real(irk) s,t,u,shape(:),gaus(3),lcop(3,8)
    gaus(1)=s;gaus(2)=t;gaus(3)=u
    if (nnode==8)then
       do k=1,ndimn-1
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
          do j=1,ndimn
             shape(inode)=shape(inode)*(1.+gaus(j)*lcop(j,inode))/2.
          end do
       end do
       do idimn=1,ndimn
          coordx(idimn,npoinx)=0.
          do inode=1,nnode
             coordx(idimn,npoinx)=coordx(idimn,npoinx)+shape(inode)*coordx(idimn,ien0(i0)%lnods(inode))
          end do
       end do
    end if
    end subroutine cor3
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine cor31(nnode,s,t,u,i0,shape)
    integer(ink) nnode,i0,idimn,inode,j,k
    real(irk) s,t,u,shape(:),gaus(3),lcop(3,8)
    gaus(1)=s;gaus(2)=t;gaus(3)=u
    if (nnode==8)then
       do k=1,ndimn-1
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
          do j=1,ndimn
             shape(inode)=shape(inode)*(1.+gaus(j)*lcop(j,inode))/2.
          end do
       end do
       do idimn=1,ndimn
          coordx(idimn,npoinx)=0.
          do inode=1,nnode
             coordx(idimn,npoinx)=coordx(idimn,npoinx)+shape(inode)*coordx(idimn,ien1(i0)%lnods(inode))
          end do
       end do
    end if
    end subroutine cor31
    !***************************************
    subroutine line_inter
    integer(ink) i0,i1,i2,j0,idimn,ijx
    real(irk) dis
    real(irk),allocatable::rr(:)


    do i0=1,nline
       if (ijapl(i0)<1)goto 10
       ijx=ijapl(i0)
       if (ijx==1)ijapl(i0)=-1
       if (ijx==2)ijapl(i0)=0
       linex(i0)%npl=line_divide(i0)+1
       allocate(linex(i0)%list(linex(i0)%npl))
       i1=iline(1,i0)
       i2=iline(2,i0)
       linex(i0)%list(1)=i1
       linex(i0)%list(linex(i0)%npl)=i2

       if (linex(i0)%npl>2)then  !>2
          do j0=1,linex(i0)%npl-2
             npoinx=npoinx+1

             listrp(npoinx)%nintf=2
             allocate(listrp(npoinx)%listf(2),listrp(npoinx)%rintf(2))
             listrp(npoinx)%listf(1)=i1;listrp(npoinx)%listf(2)=i2

             listrp(npoinx)%rintf(1)=1.-float(j0)/line_divide(i0)
             listrp(npoinx)%rintf(2)=   float(j0)/line_divide(i0)
             do idimn=1,ndimn
                coordx(idimn,npoinx)=coordx(idimn,i1)+j0*(coordx(idimn,i2)-coordx(idimn,i1))/line_divide(i0)
             end do

             linex(i0)%list(j0+1)=npoinx
          end do
       endif  !>2
       10 continue
    end do
    end subroutine line_inter
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    subroutine line_inter1
    integer(ink) i0,i1,i2,j0,idimn,lnintf,nintf,i,j,ijx
    integer(ink),allocatable::listf(:),ijcx(:)
    real(irk) dis
    real(irk),allocatable::rr(:),rintf(:)


    do i0=1,nline1
       write(7,*)i0,'ijapl1=',ijapl1(i0),'npl=',linex1(i0)%npl
       if (ijapl1(i0)<1)goto 10
       ijx=ijapl1(i0)
       if (ijx==1)ijapl1(i0)=-1
       if (ijx==2)ijapl1(i0)=0
       linex1(i0)%npl=line_divide1(i0)+1
       write(7,*)i0,'ijapl1=',ijapl1(i0),'npl=',linex1(i0)%npl
       allocate(linex1(i0)%list(linex1(i0)%npl))
       i1=iline1(1,i0)
       i2=iline1(2,i0)
       linex1(i0)%list(1)=i1
       linex1(i0)%list(linex1(i0)%npl)=i2

       if (linex1(i0)%npl>2)then  !>2
          do j0=1,linex1(i0)%npl-2
             npoinx=npoinx+1

             lnintf=2
             !     write(7,*)'npoinx=',npoinx
             !     write(7,*)'i0=',i0,'j0=',j0
             !     write(7,*)'listrp=',listrp(i1)%nintf
             !     write(7,*)'outlistrp=',outlistrp(i1),outlistrp(i2)
             if (outlistrp(i1)>0)lnintf=lnintf+listrp(i1)%nintf-1
             if (outlistrp(i2)>0)lnintf=lnintf+listrp(i2)%nintf-1
             allocate(listf(lnintf),rintf(lnintf))

             if (outlistrp(i1)>0.and.outlistrp(i2)>0)then
                listf(1:listrp(i1)%nintf)=listrp(i1)%listf
                listf(listrp(i1)%nintf+1:lnintf)=listrp(i2)%listf
                rintf(1:listrp(i1)%nintf)=(1.-float(j0)/line_divide1(i0))*listrp(i1)%rintf
                rintf(listrp(i1)%nintf+1:lnintf)=(float(j0)/line_divide1(i0))*listrp(i2)%rintf
             elseif(outlistrp(i1)>0.and.outlistrp(i2)<=0)then
                listf(1:listrp(i1)%nintf)=listrp(i1)%listf
                listf(listrp(i1)%nintf+1)=i2
                rintf(1:listrp(i1)%nintf)=(1.-float(j0)/line_divide1(i0))*listrp(i1)%rintf
                rintf(listrp(i1)%nintf+1)=(float(j0)/line_divide1(i0))
             elseif(outlistrp(i1)<=0.and.outlistrp(i2)>0)then
                listf(1)=i1
                listf(2:lnintf)=listrp(i2)%listf
                rintf(1)=(1.-float(j0)/line_divide1(i0))
                rintf(2:lnintf)=(float(j0)/line_divide1(i0))*listrp(i2)%rintf
             else
                listf(1)=i1;listf(2)=i2
                rintf(1)=1.-float(j0)/line_divide1(i0)
                rintf(2)=   float(j0)/line_divide1(i0)
             endif

             allocate(ijcx(lnintf))
             ijcx=1
             do i=1,lnintf
                if (ijcx(i)/=0)then
                   do j=1,lnintf
                      if (i/=j.and.ijcx(j)/=0)then
                         if (listf(j)==listf(i))then
                            rintf(i)=rintf(i)+rintf(j)
                            ijcx(j)=0
                         endif
                      endif
                   end do
                endif
             end do

             nintf=sum(ijcx)
             listrp(npoinx)%nintf=nintf
             allocate(listrp(npoinx)%listf(nintf),listrp(npoinx)%rintf(nintf))
             nintf=0
             do i=1,lnintf
                if (ijcx(i)==1)then
                   nintf=nintf+1
                   listrp(npoinx)%listf(nintf)=listf(i)
                   listrp(npoinx)%rintf(nintf)=rintf(i)
                endif
             end do
             deallocate(ijcx)
             !     write(7,*)'npoinx=',npoinx
             !     write(7,*)'nintf=',nintf
             !     write(7,*)'listf=',listrp(npoinx)%listf
             !     write(7,*)'rintf=',listrp(npoinx)%rintf
             deallocate(listf,rintf)
             do idimn=1,ndimn
                coordx(idimn,npoinx)=coordx(idimn,i1)+j0*(coordx(idimn,i2)-coordx(idimn,i1))/line_divide1(i0)
             end do

             linex1(i0)%list(j0+1)=npoinx
          end do
       endif  !>2
       10 continue
    end do


    end subroutine line_inter1



    !*************************************************

    subroutine line
    integer(ink) ie,ij,i,j,i0,j0,i1,j1
    integer(ink),allocatable::ijline(:),iside(:,:)

    nline=0
    do 10 ie=1,nelem0
       ij=0
       if (ndimn==3)then
          if (ien0(ie)%nnode==6)ij=9
          if (ien0(ie)%nnode==8)ij=12
       elseif(ndimn==2)then
          ij=ien0(ie)%nnode
       endif
       allocate(iside(2,ij),ijline(ij),ien0(ie)%il(ij))
       call sdn(ie,ij,iside)
       do 20 i=1,ij
          i0=iside(1,i)
          j0=iside(2,i)
          ijline(i)=0
          do 30 j=1,nline
             i1=iline(1,j)
             j1=iline(2,j)
             if ((i0.eq.i1.and.j0.eq.j1).or.(i0.eq.j1.and.j0.eq.i1)) then
                ijline(i)=j
                if ((i0.eq.j1.and.j0.eq.i1))ijline(i)=-j
                goto 20
             endif
             30    continue
             20    continue
             do 40 i=1,ij
                if (ijline(i).eq.0) then
                   nline=nline+1
                   iline(1,nline)=iside(1,i)
                   iline(2,nline)=iside(2,i)
                   ien0(ie)%il(i)=nline
                   neline(nline)=neline(nline)+1
                   ieline(neline(nline),nline)=ie
                else
                   j=ijline(i)
                   ien0(ie)%il(i)=j
                   neline(abs(j))=neline(abs(j))+1
                   ieline(neline(abs(j)),abs(j))=ie
                endif
                40    continue
                deallocate(iside,ijline)
                10    continue
                return
                end subroutine line

    subroutine sdn(ie,ij,isdt)
    integer(ink) i,j,ie,ij,isdt(:,:)
    integer(ink) li5(9),lj5(9),li6(12),lj6(12)
    data li5/1,2,3,4,5,6,1,2,3/,lj5/2,3,1,5,6,4,4,5,6/
    data li6/1,2,3,4,5,6,7,8,1,2,3,4/
    data lj6/2,3,4,1,6,7,8,5,5,6,7,8/
    do 10 i=1,ij
       if (ndimn==2)then
          isdt(1,i)=ien0(ie)%lnods(i)
          j=i+1
          if (j>ien0(ie)%nnode)j=1
          isdt(2,i)=ien0(ie)%lnods(j)
       elseif(ndimn==3)then
          if (ij.eq.9) then
             isdt(1,i)=ien0(ie)%lnods(li5(i))
             isdt(2,i)=ien0(ie)%lnods(lj5(i))
          else if(ij.eq.12) then
             isdt(1,i)=ien0(ie)%lnods(li6(i))
             isdt(2,i)=ien0(ie)%lnods(lj6(i))
          endif
       endif
       10   continue
       return
       end subroutine sdn

    subroutine sdn1(ie,ij,isdt)
    integer(ink) i,j,ie,ij,isdt(:,:)
    integer(ink) li5(9),lj5(9),li6(12),lj6(12)
    data li5/1,2,3,4,5,6,1,2,3/,lj5/2,3,1,5,6,4,4,5,6/
    data li6/1,2,3,4,5,6,7,8,1,2,3,4/
    data lj6/2,3,4,1,6,7,8,5,5,6,7,8/
    do 10 i=1,ij
       if (ndimn==2)then
          isdt(1,i)=ien1(ie)%lnods(i)
          j=i+1
          if (j>ien1(ie)%nnode)j=1
          isdt(2,i)=ien1(ie)%lnods(j)
       elseif(ndimn==3)then
          if (ij.eq.9) then
             isdt(1,i)=ien1(ie)%lnods(li5(i))
             isdt(2,i)=ien1(ie)%lnods(lj5(i))
          else if(ij.eq.12) then
             isdt(1,i)=ien1(ie)%lnods(li6(i))
             isdt(2,i)=ien1(ie)%lnods(lj6(i))
          endif
       endif
       10   continue
       return
       end subroutine sdn1
       !**********************************************************************
       !      Sub. sface is used to calculate the surface of 3-d elements    *
       !         The element can be 4, 6, 8 nodes                            *
       !**********************************************************************
    subroutine sface
    integer(ink) j,ie,ib(6),ij0(4),n1,n2
    nface=0
    do 10 ie=1,nelem0
       !     if(needmesh1(ien0(ie)%imat)==1)then
       n1=4+(ien0(ie)%nnode-4)/2
       allocate(ien0(ie)%ienf(n1))

       if  (n1.eq.5) then
          ib(1)=132
          ib(2)=456
          ib(3)=2541
          ib(4)=1463
          ib(5)=3652
       else
          ib(1)=8415
          ib(2)=3762
          ib(3)=1265
          ib(4)=8734
          ib(5)=4321
          ib(6)=7856
       endif
       do j=1,n1
          n2=3
          if ((n1.eq.5.and.j.gt.2).or.n1.eq.6) n2=4
          call ijcx(ib(j),n2,ij0)
          nface=nface+1
          ien0(ie)%ienf(j)=nface
          inf(nface)=n2
          ieface(nface)=ie
          iface(1:n2,nface)=ien0(ie)%lnods(ij0(1:n2))
       end do
       !     end if
       10   continue
       end subroutine sface
       !**********************************************************************
       !       This sub. eliminate the internal sunfaces and keep the        *
       !             external  surfaces                                      *
       !**********************************************************************
    subroutine deface
    integer(ink) i,j,k,l,i0,j0,jk,j1,j2,ie,nsd0,nsd1,ndface,ij0,ij1,n1
    integer(ink),allocatable::ijface(:),idface(:,:),infd(:)

    allocate(ijface(nface),idface(4,nface),infd(nface))
    ijface=0
    ndface=0

    do 10 i=1,nface
       ij0=inf(i)
       if (ijface(i).ne.0) goto 10
       ndface=ndface+1
       ijface(i)=ndface
       infd(ndface)=inf(i)
       nedface(ndface)=1
       iedface(1,ndface)=ieface(i)
       nsd0=sum(iface(1:ij0,i))
       idface(1:ij0,ndface)=iface(1:ij0,i)
       do 20 j=i+1,nface
          if (ijface(j).ne.0) goto 20
          ij1=inf(j)
          if (ij1.ne.ij0) goto 20
          nsd1=sum(iface(1:ij1,j))
          if (nsd1.ne.nsd0) goto 20
          jk=0
          do 13 k=1,ij0
             do 14 l=1,ij1
                if (iface(k,j).eq.iface(l,i)) then
                   jk=jk+1
                   i0=k
                   j0=l
                   goto 15
                endif
                14    continue
                15    continue
                13   continue
                if (jk.eq.ij1) then
                   j1=i0+1
                   if (j1.gt.ij1) j1=j1-ij1
                   j2=j0+1
                   if (j2.gt.ij1) j2=j2-ij1
                   ijface(j)=ndface
                   if (iface(j1,j).ne.iface(j2,i)) ijface(j)=-ndface
                   nedface(ndface)=nedface(ndface)+1

                   if (nedface(ndface).gt.2) then
                      print *,'surface connected elements more than 2!'
                      print *,'surface='
                      print *,iface(1:inf(i),i)
                      print *,'elements=',iedface(1:2,ndface),ieface(j)
                      stop
                   endif
                   iedface(nedface(ndface),ndface)=ieface(j)
                endif
                20   continue
                10   continue
                do 30 ie=1,nelem0
                   !     if(needmesh1(ien0(ie)%imat)==1)then
                   n1=4+(ien0(ie)%nnode-4)/2
                   do 40 i=1,n1
                      j=ien0(ie)%ienf(i)
                      ien0(ie)%ienf(i)=ijface(j)
                      40    continue
                      !       endif
                      30    continue

                      deallocate(inf,iface)
                      allocate(inf(nface),iface(4,nface))
                      nface=ndface
                      inf(1:ndface)=infd(1:ndface)
                      do 50 i=1,nface
                         do 60 j=1,inf(i)
                            iface(j,i)=idface(j,i)
                            60    continue
                            50    continue
                            deallocate(ijface,idface,infd)
                            end  subroutine deface

    subroutine ijcx(ij,n1,ij0)
    integer(ink) i,n1,ij0(:),ij,ij1
    ij1=ij
    do 10 i=1,n1
       ij0(i)=ij1/10**(n1-i)
       ij1=ij1-ij0(i)*10**(n1-i)
       10    continue
       end subroutine ijcx


  end  module meshfine