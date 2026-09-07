 	module node_optimization
    use variable_types
    use global_var
    implicit none

			 ! optimization(ndimn,npoin,nelem,mnode,coord,ien,gelem,melem)
	real(irk),allocatable:: coordn(:,:)
	integer(ink),allocatable::ip(:,:),ipn(:,:),nod1(:)

contains

subroutine ngaps_pairs_lable(iter_rl_tot,iter_rl_had)
	integer(ink) iter_rl_tot,iter_rl_had
    integer(ink) ntpairs,igaps,igapb,npgblock,i0,ipairs,jgaps,itpairs,i,j,neq

	  ntpairs=0
	    do igaps=1,ngaps
        ntpairs=ntpairs+gaps(igaps)%npairs
       end do

    do igapb=1,ngapb
     npgblock=gapb(igapb)%npgblock
	 allocate(gapb(igapb)%list_tpairs(npgblock))
       do i0=1,npgblock
          ipairs=gapb(igapb)%nodegblock_ipairs(i0)
          igaps=gapb(igapb)%nodegblock_igaps(i0)
		itpairs=0
		  do jgaps=1,igaps-1
		  itpairs=itpairs+gaps(jgaps)%npairs
		  end do
		itpairs=itpairs+ipairs
		gapb(igapb)%list_tpairs(i0)=itpairs
		end do
	end do


	allocate(ip(ndimn,ntpairs),nod1(ntpairs))
  	 ip=1
      call relab_gap(ntpairs,iter_rl_tot,iter_rl_had,nod1)
     do  i=1,ntpairs
	 do  j=1,ndimn
	 if(ip(j,i)/=1) cycle
	 neq=neq+1
	 ip(j,i)=neq
     end do
     end do

	 call HX22gap(Neq,ip,ndimn)

	deallocate(ip,nod1)
end subroutine ngaps_pairs_lable



	subroutine optimization(iter_rl_tot,iter_rl_had)
	integer(ink) iter_rl_tot,iter_rl_had
    integer(ink) ipoin,idimn,igroup,ielgroup,ie,index,nnode,np1,neq

	allocate(ip(ndimn,npoin),coordn(ndimn,npoin),ipn(ndimn,npoin),nod1(npoin))
	ip=1

	coordn=coord
	ipn=ip
      call relab(iter_rl_tot,iter_rl_had,nod1)
	 do ipoin=1,npoin
	 np1=nod1(ipoin)
	  do idimn=1,ndimn
	coordn(idimn,np1)=coord(idimn,ipoin)
	ipn(idimn,np1)=ip(idimn,ipoin)
	 end do
	end do

    DO igroup =1,ngroup
          DO ielgroup = 1,group(igroup)%nelgroup
          ie = group(igroup)%list(ielgroup)
          index = group(igroup)%index
          nnode = elkn(index)%el_field(1)%nnode_f
          allocate(lnods(nnode))
		  lnods=element(ie)%field(1)%lnods_f
          element(ie)%field(1)%lnods_f=nod1(lnods)
		  deallocate(lnods)
		  end do
	end do

	 call link(ipn,neq,ndimn)
	 call HX22P(Neq,ipn,ndimn)

	deallocate(coordn,ip,ipn,nod1)
end subroutine optimization
!--------------------------------------------------------
	subroutine link(ip,neq,ndofn)
	integer(ink) i,j,neq,ndofn,ip(:,:)
	 
	 neq=0
	 do  i=1,npoin
	 do  j=1,ndofn
	 if(ip(j,i)/=1) cycle
	 neq=neq+1
	 ip(j,i)=neq
     end do
     end do

    end subroutine
!------------------------------------------------------------
	SUBROUTINE HX22P(Neq,ip,ndofn)
	integer(ink) neq,ndofn,ip(:,:)
    integer(ink) igroup,ielgroup,ie,index,nnode,k,l,j0,j1,j,k0,k1,mx,icnp,icnq,i,ih
	integer(ink),allocatable::IA(:),icn(:)
    integer(ink),pointer::lnods(:)

	allocate(ia(neq))

    ia=0

    DO igroup =1,ngroup
          DO ielgroup = 1,group(igroup)%nelgroup
          ie = group(igroup)%list(ielgroup)
          index = group(igroup)%index
          nnode = elkn(index)%el_field(1)%nnode_f
  allocate(icn(nnode*ndofn),lnods(nnode))
		  lnods=element(ie)%field(1)%lnods_f
  icn=0
	  do  k=1,nnode
	  if(lnods(k)==0) cycle
	  do  l=1,ndofn
	  if(ip(l,lnods(k)).ne.0)icn((k-1)*ndofn+l)=ip(l,lnods(k))
      end do
      end do

	  DO  j0=1,nnode
          do  j1=1,ndofn
          j=(j0-1)*ndofn+j1
	  ICNP=ICN(J)
	  IF(ICNP.EQ.0) cycle
	  DO  k0=1,nnode
          do  k1=1,ndofn
          k=(k0-1)*ndofn+k1
	  ICNQ=ICN(K)
	  IF((ICNQ.EQ.0).OR.(IA(ICNP).GT.(ICNP-ICNQ)))cycle
	  IA(ICNP)=ICNP-ICNQ
          end do
      end do
        end do
		end do
  deallocate(icn,lnods)
      end do
	end do

	MX=0
	IA(1)=1
	DO  I=2,Neq
	IF(MX.GE.IA(I))GOTO 5
	MX=IA(I)
  5     IA(I)=IA(I)+IA(I-1)+1
    end do
	MX=MX+1
	IH=IA(Neq) 

	deallocate(ia)
	WRITE(7,4)MX,Neq,IH
 4     FORMAT(5X,3HMX=,I8,5X,2HN=,I8,5X,3HIH=,I20)
	 END  subroutine
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	SUBROUTINE HX22gap(Neq,ip,ndofn)
	integer(ink) neq,ndofn,ip(:,:)
    integer(ink) igapb,nnode,k,l,j0,j1,j,k0,k1,mx,icnp,icnq,i,ih
	integer(ink),allocatable::IA(:),icn(:)
    integer(ink),pointer::lnods(:)

	allocate(ia(neq))

    ia=0

    do igapb=1,ngapb
     nnode=gapb(igapb)%npgblock
	 allocate(lnods(nnode),icn(nnode*ndofn))
		lnods=gapb(igapb)%list_tpairs
  icn=0
	  do  k=1,nnode
	  if(lnods(k)==0) cycle
	  do  l=1,ndofn
	  if(ip(l,lnods(k)).ne.0)icn((k-1)*ndofn+l)=ip(l,lnods(k))
      end do
      end do

	  DO  j0=1,nnode
          do  j1=1,ndofn
          j=(j0-1)*ndofn+j1
	  ICNP=ICN(J)
	  IF(ICNP.EQ.0) cycle
	  DO  k0=1,nnode
          do  k1=1,ndofn
          k=(k0-1)*ndofn+k1
	  ICNQ=ICN(K)
	  IF((ICNQ.EQ.0).OR.(IA(ICNP).GT.(ICNP-ICNQ)))cycle
	  IA(ICNP)=ICNP-ICNQ
          end do
      end do
        end do
		end do
  deallocate(icn,lnods)
      end do

	MX=0
	IA(1)=1
	DO  I=2,Neq
	IF(MX.GE.IA(I))GOTO 5
	MX=IA(I)
  5     IA(I)=IA(I)+IA(I-1)+1
    end do
	MX=MX+1
	IH=IA(Neq) 

	deallocate(ia)
	WRITE(7,4)MX,Neq,IH
 4     FORMAT(5X,3HMX=,I8,5X,2HN=,I8,5X,3HIH=,I20)
	 END  subroutine
!-----------------------------------------------------

      subroutine relab(iter_rl_tot,iter_rl_had,nod1)

    integer(ink) iter_rl_tot,iter_rl_had,iter_rl
    integer(ink) igroup,ielgroup,ie,inode,lnode,nnode,index,jj,l,ll,k,kl,ndkl,i0,i,ikl,ikn
    integer(ink) nod1(:)
	integer(ink),pointer::lnods(:)
	integer(ink),allocatable::iaa(:),ipp(:),nod(:),nnd(:)


	allocate(iaa(npoin),ipp(npoin),nod(npoin))
	 do i=1,npoin
	nod(i)=i
	nod1(i)=i
	end do
	if(iter_rl_had.ne.0) then
	do i=1,npoin
	read(relabnode_unit,*)i0,nod(i),nod1(i)
	end do
	endif
	   if(iter_rl_tot==0) return
       iter_rl=iter_rl_had+1
300	do i=1,npoin
	iaa(i)=0
	ipp(i)=npoin
	end do
  !     print *,'iter=',iter,'iter_tot=',iter_tot

    DO igroup =1,ngroup
          DO ielgroup = 1,group(igroup)%nelgroup
          ie = group(igroup)%list(ielgroup)
          index = group(igroup)%index
          nnode = elkn(index)%el_field(1)%nnode_f
		  lnods=>element(ie)%field(1)%lnods_f
	allocate(nnd(nnode))
	     do inode=1,nnode
	      lnode=lnods(inode)
	      nnd(inode)=nod1(lnode)
      	end do
       l=npoin
	 ll=0
	      do inode=1,nnode
	         i0=nnd(inode)
	         if(i0.lt.l) l=i0
        	     if(i0.gt.ll)ll=i0
	      end do

	do inode=1,nnode
	jj=nnd(inode)
	if(ll.gt.iaa(jj))iaa(jj)=ll
	if(l.lt.ipp(jj)) ipp(jj)=l
	end do
	   nullify(lnods)
	   deallocate(nnd)
	  end do  !ielgroup
	  end do  !igroup

	 do i=1,npoin
	iaa(i)=iaa(i)+ipp(i)
	 end do
       kl=1
200    ndkl=npoin-kl-1
        do k=1,ndkl+1
	if(iaa(k).gt.iaa(k+1)) then
	 ikn=nod(k)
	ikl=iaa(k)
	iaa(k)=iaa(k+1)
	nod(k)=nod(k+1)
	iaa(k+1)=ikl
	nod(k+1)=ikn
	nod1(nod(k))=k
	nod1(ikn)=k+1
	endif
	  end do
	if(kl.eq.(npoin-2))then
	if(iter_rl.ne.iter_rl_tot) then
	iter_rl=iter_rl+1
	goto 300
	endif
	else
	kl=kl+1
	goto 200
	end if

	do i=1,npoin
	write(relabnode_unit,*)i,nod(i),nod1(i)
	end do

	deallocate(iaa,nod,ipp)
	end	 subroutine

      subroutine relab_gap(ntpairs,iter_rl_tot,iter_rl_had,nod1)

    integer(ink) iter_rl_tot,iter_rl_had,iter_rl,ntpairs
	integer(ink) inode,lnode,nnode,jj,l,ll,k,kl,ndkl,i0,i,ikl,ikn,igapb
    integer(ink) nod1(:)
	integer(ink),pointer::lnods(:)
	integer(ink),allocatable::iaa(:),ipp(:),nod(:),nnd(:)

    print *,'ntpairs=',ntpairs
	allocate(iaa(ntpairs),ipp(ntpairs),nod(ntpairs))
	 do i=1,ntpairs
	nod(i)=i
	nod1(i)=i
	end do
	if(iter_rl_had.ne.0) then
	do i=1,ntpairs
	read(relabnode_unit,*)i0,nod(i),nod1(i)
	end do
	endif
	   if(iter_rl_tot==0) return
       iter_rl=iter_rl_had+1
300	do i=1,ntpairs
	iaa(i)=0
	ipp(i)=ntpairs
	end do
  !     print *,'iter=',iter,'iter_tot=',iter_tot

  do igapb=1,ngapb
     nnode=gapb(igapb)%npgblock
		lnods=>gapb(igapb)%list_tpairs
	allocate(nnd(nnode))
	     do inode=1,nnode
	      lnode=lnods(inode)
	      nnd(inode)=nod1(lnode)
      	end do
       l=npoin
	 ll=0
	      do inode=1,nnode
	         i0=nnd(inode)
	         if(i0.lt.l) l=i0
        	     if(i0.gt.ll)ll=i0
	      end do

	do inode=1,nnode
	jj=nnd(inode)
	if(ll.gt.iaa(jj))iaa(jj)=ll
	if(l.lt.ipp(jj)) ipp(jj)=l
	end do
	   nullify(lnods)
	   deallocate(nnd)
	  end do  !igap

	 do i=1,ntpairs
	iaa(i)=iaa(i)+ipp(i)
	 end do
       kl=1
200    ndkl=ntpairs-kl-1
        do k=1,ndkl+1
	if(iaa(k).gt.iaa(k+1)) then
	 ikn=nod(k)
	ikl=iaa(k)
	iaa(k)=iaa(k+1)
	nod(k)=nod(k+1)
	iaa(k+1)=ikl
	nod(k+1)=ikn
	nod1(nod(k))=k
	nod1(ikn)=k+1
	endif
	  end do
	if(kl.eq.(ntpairs-2))then
	if(iter_rl.ne.iter_rl_tot) then
	iter_rl=iter_rl+1
	goto 300
	endif
	else
	kl=kl+1
	goto 200
	end if


	do i=1,ntpairs
	write(relabnode_unit,*)i,nod(i),nod1(i)
	end do

    do igapb=1,ngapb
     nnode=gapb(igapb)%npgblock
	 allocate(lnods(nnode))
	lnods=gapb(igapb)%list_tpairs
    gapb(igapb)%list_tpairs=nod1(lnods)
	 deallocate(lnods)
	 end do

	deallocate(iaa,nod,ipp)
	end	 subroutine


	end	module node_optimization