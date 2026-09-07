module arrayutil

use variable_types 

implicit none
 
	 interface operator (.x.)
    	 module procedure mattimesmat, mattimesvector
	 end interface

    interface operator (.d.)
       module procedure dot
    end interface

    interface operator (.o.)
       module procedure tensorproduct
    end interface
    
contains
    
    function mattimesmat( a, b)
    real(irk) , intent(in),  dimension(:,:) :: a,b
    real(irk) ,  dimension( size(a,1), size(b,2) ) :: mattimesmat
    mattimesmat = matmul( a, b)
    end function  mattimesmat
    
    function mattimesvector( a, x)  
    real(irk) , intent(in),  dimension(:,:) :: a
    real(irk) , intent(in),  dimension(:) :: x
    real(irk) ,  dimension(size(a,1)) :: mattimesvector
    mattimesvector=matmul(a,x)   
    end function mattimesvector
    
    function id(n)
    integer(ink)  n, i
    real(irk) ,  dimension( n,n ) :: id
    id=0.0
    do i=1,n
       id(i,i)= 1.00
    enddo
    end function id
    
    function dot(a,b)
    real(irk) , intent(in), dimension(:) :: a
    real(irk) , intent(in), dimension(:) :: b
    real(irk) dot
    dot=dot_product(a,b)
    end function dot
    
    function tensorproduct(a,b)
    real(irk) , intent(in),  dimension(:) :: a
    real(irk) , intent(in),  dimension(:) :: b
    real(irk) ,  dimension(size(a,1),size(b,1)) :: tensorproduct
    integer(ink)  ni,nj,i,j
    
    ni=size(a,1)
    nj=size(b,1)
   
    do i=1,ni
       do j=1,nj
          tensorproduct(i,j)=a(i)*b(j)
       enddo
    enddo  
    end function tensorproduct
    
    function asm(a,lm,ng)
    integer(ink) i,ng,nl,j 
    real(irk),    intent(in), dimension(:,:) :: a
    integer(ink), intent(in), dimension(:)   :: lm
    real(irk), dimension(ng,ng) :: asm
     
    nl=size(a,1)
    asm=0.0
    do i=1,nl
       do j=1,nl
          if (lm(i).ne.0.and.lm(j).ne.0) then
             asm(lm(i),lm(j)) = a(i,j)
          endif
       enddo
    enddo
    end function asm
    
    function dcmp(a,indx)
    real(irk), intent(in), dimension(:,:) :: a
    integer(ink), intent(in), dimension(:) :: indx
    real(irk), dimension(size(a,1),size(a,2))  :: dcmp
    real(irk) d
    integer(ink) n,irst
    n=size(a,1)
    dcmp=a
    call ludcmp (dcmp,indx,n,d,irst)
    end function dcmp
    
    function readm(nf,nc)
    integer(ink) i,j,nf,nc
    real(irk), dimension(nf,nc) :: readm
    character*4 name
    read(1,*)name
    if (nc==1)then
       read(1,*)(readm(i,1),i=1,nf)
    else
       read(1,*)((readm(i,j),j=1,nc),i=1,nf)
    endif
    end function readm
    
    function readmi(nf,nc)
    integer(ink) i,j,nf,nc
    integer(ink), dimension(nf,nc) :: readmi
    character*4 name
    read(1,*) name
    if (nc==1)then
       read(1,*)(readmi(i,1),i=1,nf)
    else
       read(1,*)((readmi(i,j),j=1,nc),i=1,nf)
    endif
    
    end function readmi
    
    subroutine writem(a,nf,nc,name)
    
    integer(ink) nf,nc,i,j
    real(irk), dimension(nf,nc) :: a
    character*4 name
    write (2,*) name
    if (nc==1) then
       write(2,1)(a(i,1),i=1,nf)
    else
       do i=1,nf
          select case (nc)
          case (2)
           write (2,2) (a(i,j),j=1,nc)
          case (3)
           write (2,3) (a(i,j),j=1,nc)
          case (4)
           write (2,4) (a(i,j),j=1,nc)
          case (5)
           write (2,5) (a(i,j),j=1,nc)
          case (6)
           write (2,6) (a(i,j),j=1,nc)
          case (7)
           write (2,7) (a(i,j),j=1,nc)
          case (8)
           write (2,8) (a(i,j),j=1,nc)
          case (9)
           write (2,9) (a(i,j),j=1,nc)
          end select
       enddo
    endif
    
    1  format (  e14.4 )
    2  format ( 2e14.4 )
    3  format ( 3e14.4 )
    4  format ( 4e14.4 )
    5  format ( 5e14.4 )
    6  format ( 6e12.4 )
    7  format ( 7e11.4 )
    8  format ( 8e11.4 )
    9  format ( 9e11.4 )
    
    end subroutine writem
    
    subroutine ludcmp(a,indx,n,d,irst)
    
    real(irk), dimension(:,:):: a
    integer(ink), dimension(:) :: indx
    integer(ink) n
    real(irk) d
    integer(ink) irst
    integer(ink), parameter :: nmax=10
    real(irk), dimension(nmax) :: vv
    real(irk), parameter :: tiny=1.0e-20
    integer(ink) i,imax,j,k
    real(irk) aamax, sum, dum
    
    d=1.0
    do i=1,n
       aamax=0.
       do j=1,n
          if(abs(a(i,j)).gt.aamax) aamax=abs(a(i,j))
       enddo
       if (aamax.eq.0.) then
          irst=1
          return
       endif
       vv(i)=1./aamax
    enddo
    do j=1,n
       do i=1,j-1
          sum=a(i,j)
          do k=1,i-1
             sum=sum-a(i,k)*a(k,j)
          enddo
          a(i,j)=sum
       enddo
       aamax=0.
       do i=j,n
          sum=a(i,j)
          do k=1,j-1
             sum=sum-a(i,k)*a(k,j)
          enddo
          a(i,j)=sum
          dum=vv(i)*abs(sum)
          if (dum.ge.aamax) then
             imax=i
             aamax=dum
          endif
       enddo
       if (j.ne.imax)then
         do  k=1,n
           dum=a(imax,k)
           a(imax,k)=a(j,k)
           a(j,k)=dum
         enddo
         d=-d
         vv(imax)=vv(j)
       endif
       indx(j)=imax
       if(a(j,j).eq.0.)a(j,j)=tiny
       if (j.ne.n)then
          dum=1./a(j,j)
          do i=j+1,n
             a(i,j)=a(i,j)*dum
          enddo
       endif
    enddo
    
    end subroutine ludcmp
    
    !  (c) copr. 1986-92 numerical recipes software 0!',1-)i.
    
    function bksb(a,b,indx)
    real(irk), intent(in), dimension(:,:) ::  a
    real(irk), intent(in), dimension(:,:) ::  b
    integer(ink), intent(in), dimension(:) :: indx
    real(irk) ,  dimension(size(b,1),size(b,2)) :: bksb
    real(irk) ,  dimension(size(b,1)) :: bi
    integer(ink) n,m,i
    
    n = size(a,1)
    m = size(b,2)
    do i=1,m
       bi = b(1:n,i)
       call lubksb(a,n,bi,indx)
       bksb(1:n,i)=bi
    enddo
    
    end function bksb
    
    
    subroutine lubksb(a,n,b,indx)
    
    real(irk), dimension(:,:)  ::  a
    integer(ink) n
    real(irk), dimension(:)    ::  b
    integer(ink), dimension(:) ::  indx
    integer(ink) i,ii,j,ll
    real(irk) sum
    
    ii=0
    do i=1,n
       ll=indx(i)
       sum=b(ll)
       b(ll)=b(i)
       if (ii.ne.0)then
          do j=ii,i-1
             sum=sum-a(i,j)*b(j)
          enddo
       else if (sum.ne.0.) then
          ii=i
       endif
       b(i)=sum
    enddo
    do i=n,1,-1
       sum=b(i)
       do j=i+1,n
          sum=sum-a(i,j)*b(j)
       enddo
       b(i)=sum/a(i,i)
    enddo
    
    end subroutine lubksb
    
    !  (c) copr. 1986-92 numerical recipes software 0!',1-)i.1G
    
    subroutine svdcmp(estifh,estifhi)
    integer(ink) m,mp,n,np,NMAX
    real   (irk) estifh(:,:),estifhi(:,:)
    parameter (nmax=500)
    integer(ink) i,its,j,jj,k,l,nm
    real   (irk) rv1(nmax)
    real   (irk) scale, g, anorm, f, h,c,s, x,y,z
    real   (irk),allocatable::a(:,:),v(:,:),w(:)
    mp=size(estifh,dim=1)
    np=size(estifh,dim=2)
    m=mp
    n=np
    allocate(a(mp,np),v(mp,np),w(mp))
    do 100 i=1,mp
    do 100 j=1,np
    100 a(i,j)=estifh(i,j)
    g=0.0
    scale=0.0
    anorm=0.0
    do 25 i=1,n
       l=i+1
       rv1(i)=scale*g
       g=0.0
       s=0.0
       scale=0.0
       if (i.le.m)then
          do 11 k=i,m
             scale=scale+abs(a(k,i))
          11 continue
          if (scale.ne.0.00_irk) then
             do 12 k=i,m
                a(k,i)=a(k,i)/scale
                s=s+a(k,i)*a(k,i)
             12 continue
             f=a(i,i)
             g=-sign(sqrt(s),f)
             h=f*g-s
             a(i,i)=f-g
             do 15 j=l,n
                s=0.0
                do 13 k=i,m
                   s=s+a(k,i)*a(k,j)
                13 continue
                f=s/h
                do 14 k=i,m
                  a(k,j)=a(k,j)+f*a(k,i)
                14 continue
             15 continue
             do 16 k=i,m
                   a(k,i)=scale*a(k,i)
             16 continue
          endif
       endif
       w(i)=scale *g
       g=0.0
       s=0.0
       scale=0.0
       if ((i.le.m).and.(i.ne.n))then
          do 17 k=l,n
             scale=scale+abs(a(i,k))
          17 continue
          if (scale.ne.0.00_irk)then
             do 18 k=l,n
                a(i,k)=a(i,k)/scale
                s=s+a(i,k)*a(i,k)
             18 continue
             f=a(i,l)
             g=-sign(sqrt(s),f)
             h=f*g-s
             a(i,l)=f-g
             do 19 k=l,n
                rv1(k)=a(i,k)/h
             19 continue
             do 23 j=l,m
                s=0.0
                do 21 k=l,n
                   s=s+a(j,k)*a(i,k)
                21 continue
                do 22 k=l,n
                    a(j,k)=a(j,k)+s*rv1(k)
                22 continue
             23 continue
             do 24 k=l,n
                a(i,k)=scale*a(i,k)
             24 continue
          endif
       endif
       anorm=max(anorm,(abs(w(i))+abs(rv1(i))))
    25 continue
    do 32 i=n,1,-1
       if (i.lt.n)then
          if (g.ne.0.00_irk)then
             do 26 j=l,n
                v(j,i)=(a(i,j)/a(i,l))/g
             26 continue
             do 29 j=l,n
               s=0.0
               do 27 k=l,n
                  s=s+a(i,k)*v(k,j)
               27 continue
               do 28 k=l,n
                  v(k,j)=v(k,j)+s*v(k,i)
               28 continue
             29 continue
          endif
          do 31 j=l,n
             v(i,j)=0.0
             v(j,i)=0.0
          31 continue
       endif
       v(i,i)=1.0
       g=rv1(i)
       l=i
    32 continue
    do 39 i=min(m,n),1,-1
       l=i+1
       g=w(i)
       do 33 j=l,n
          a(i,j)=0.0
       33 continue
       if (g.ne.0.00)then
          g=1.00/g
          do 36 j=l,n
             s=0.0
             do 34 k=l,m
                s=s+a(k,i)*a(k,j)
             34 continue
             f=(s/a(i,i))*g
             do 35 k=i,m
                a(k,j)=a(k,j)+f*a(k,i)
             35 continue
          36 continue
          do 37 j=i,m
             a(j,i)=a(j,i)*g
          37 continue
       else
          do 38 j= i,m
             a(j,i)=0.0
          38 continue
       endif
       a(i,i)=a(i,i)+1.00
    39 continue
    do 49 k=n,1,-1
       do 48 its=1,30
          do 41 l=k,1,-1
             nm=l-1
             if((abs(rv1(l))+anorm).eq.anorm)  goto 2
             if((abs(w(nm))+anorm).eq.anorm)  goto 1
          41 continue
1         c=0.0
          s=1.0
          do 43 i=l,k
             f=s*rv1(i)
             rv1(i)=c*rv1(i)
             if((abs(f)+anorm).eq.anorm) goto 2
             g=w(i)
             h=pythag(f,g)
             w(i)=h
             h=1.00/h
             c= (g*h)
             s=-(f*h)
             do 42 j=1,m
                y=a(j,nm)
                z=a(j,i)
                a(j,nm)=(y*c)+(z*s)
                a(j,i)=-(y*s)+(z*c)
             42 continue
          43 continue
2         z=w(k)
          if (l.eq.k)then
             if (z.lt.0.00_irk)then
                w(k)=-z
                do 44 j=1,n
                   v(j,k)=-v(j,k)
                44 continue
             endif
             goto 3
          endif
          if(its.eq.30) pause 'no convergence in svdcmp'
          x=w(l)
          nm=k-1
          y=w(nm)
          g=rv1(nm)
          h=rv1(k)
          f=((y-z)*(y+z)+(g-h)*(g+h))/(2.00*h*y)
          g=pythag(f,1.0_irk)
          f=((x-z)*(x+z)+h*((y/(f+sign(g,f)))-h))/x
          c=1.0
          s=1.0
          do 47 j=l,nm
             i=j+1
             g=rv1(i)
             y=w(i)
             h=s*g
             g=c*g
             z=pythag(f,h)
             rv1(j)=z
             c=f/z
             s=h/z
             f= (x*c)+(g*s)
             g=-(x*s)+(g*c)
             h=y*s
             y=y*c
             do 45 jj=1,n
                x=v(jj,j)
                z=v(jj,i)
                v(jj,j)= (x*c)+(z*s)
                v(jj,i)=-(x*s)+(z*c)
             45 continue
             z=pythag(f,h)
             w(j)=z
             if (z.ne.0.00)then
                z=1.00/z
                c=f*z
                s=h*z
             endif
             f= (c*g)+(s*y)
             x=-(s*g)+(c*y)
             do 46 jj=1,m
                y=a(jj,j)
                z=a(jj,i)
                a(jj,j)= (y*c)+(z*s)
                a(jj,i)=-(y*s)+(z*c)
             46 continue
          47 continue
          rv1(l)=0.0
          rv1(k)=f
          w(k)=x
       48 continue
3      continue
    49 continue
    
    do 85 i=1,mp
       do 85 j=1,np
          estifhi(i,j)=0.0
          do 85 k=1,np
             estifhi(i,j)=estifhi(i,j)+v(i,k)*a(j,k)/w(k)
    85 continue
    write(7,*)'w=',w
    write(7,*)'v=',v
    write(7,*)'a=',a
    deallocate(a,v,w)
    
    end subroutine svdcmp
    
    !  (C) Copr. 1986-92 Numerical Recipes Software '%10(9p15%.
    
    subroutine svbksb(u,v,w,b)
    integer(ink) m,mp,n,np,NMAX
    real   (irk) b(:,:),u(:,:),v(:,:),w(:)
    PARAMETER (NMAX=500)
    integer(ink) i,j,jj,k,mm
    real(irk) tmp(NMAX)
    real(irk) s
    real(irk),allocatable::x(:,:)
    
    mp=size(u,dim=1)
    np=size(u,dim=2)
    m=mp
    n=np
    
    mm=size(b,2)
    allocate(x(m,mm))
    
    do k=1,mm
       do 12 j=1,n
          s=0.
          if (w(j).ne.0.0_irk)then
             do 11 i=1,m
                s=s+u(i,j)*b(i,k)
             11 continue
             s=s/w(j)
          endif
          tmp(j)=s
       12 continue
       do 14 j=1,n
          s=0.
          do 13 jj=1,n
             s=s+v(j,jj)*tmp(jj)
          13 continue
          x(j,k)=s
       14 continue
    end do
    b=x
    deallocate(x)
    
    end subroutine svbksb
    
    !  (C) Copr. 1986-92 Numerical Recipes Software '%10(9p15%.

    function pythag(a,b)
    real(irk) a,b,absa,absb,pythag
    absa=abs(a)
    absb=abs(b)
    if (absa.gt.absb)then
       pythag=absa*sqrt(1.00+(absb/absa)**2)
    else
       if (absb.eq.0.00)then
          pythag=0.
       else
          pythag=absb*sqrt(1.00+(absa/absb)**2)
       endif
    endif
    end function pythag
    
    subroutine householder(c,d,e)
    real(irk), intent(in), dimension(:,:) ::  c
    real(irk), intent(in), dimension(:,:) ::  d
    real(irk) ,  dimension(size(c,1),size(d,2)) :: e
    real(irk),allocatable::a(:,:),b(:),uk(:),qk(:),anew(:,:),bnew(:)
    integer(ink) n,m,ii,i,j,k,l
    real(irk) ak,betak,miuk
    
    m = size(c,1)
    n = size(c,2)
    l = size(d,2)
    
    allocate(a(m,n),b(m),Uk(m),Qk(n),Anew(m,n),Bnew(m))
    
    do ii=1,l
       a=c
       b=d(:,ii)
       ANEW=a
       BNEW=b
       do k=1,n
       
          a=Anew
          b=Bnew
          
          Ak=sqrt(sum(a(k:m,k)**2))
          Uk=a(1:m,k)
          Uk(1:k-1)=0.
          Uk(k)=a(k,k)+sign(Ak,a(k,k))
          BETAk=1./(Ak*(Ak+abs(a(k,k))))
          
          Qk=matmul(Uk,a)
          Qk=Qk*BETAk
          
          MIUk=dot_product(Uk,b)
          MIUk=Miuk*BETAk
          
          do i=1,m
             do j=1,n
                Anew(i,j)=a(i,j)-Uk(i)*Qk(j)
             end do
          end do
          
          Bnew=b-MIUk*Uk
       end do
    
       bnew(m)=bnew(m)/anew(m,n)
       do k=m-1,1,-1
          bnew(k)=(bnew(k)-dot_product(anew(k,k+1:m),bnew(k+1:m)))/a(k,k)
       end do
       e(:,ii)=bnew
    end do !ii
    
    deallocate(a,b,anew,bnew,Uk,qk)
    !write(2,*)'************A*****'
    !do i=1,m
    !write(2,*)a(i,1:n),b(i)
    !end do
    !write(2,*)'************ANEW****'
    !do i=1,m
    !write(2,*)anew(i,1:n),bnew(i)
    !end do
    end subroutine householder
    
    
    subroutine householderx(c,d,e)
     DOUBLE PRECISION, intent(in), dimension(:,:) ::  c
     DOUBLE PRECISION, intent(in), dimension(:,:) ::  d
     DOUBLE PRECISION,  dimension(size(c,1),size(d,2)) :: e
     DOUBLE PRECISION,allocatable::a(:,:),b(:),uk(:),qk(:),anew(:,:),bnew(:)
    integer n,m,ii,i,j,k,l
     DOUBLE PRECISION  ak,betak,miuk
    
    m = size(c,1)
    n = size(c,2)
    l = size(d,2)
    
    allocate(a(m,n),b(m),Uk(m),Qk(n),Anew(m,n),Bnew(m))
    
    do ii=1,l
       a=c
       b=d(:,ii)
       ANEW=a
       BNEW=b
       do k=1,n
       
          a=Anew
          b=Bnew
          
          Ak=sqrt(sum(a(k:m,k)**2))
          Uk=a(1:m,k)
          Uk(1:k-1)=0.
          Uk(k)=a(k,k)+sign(Ak,a(k,k))
          BETAk=1./(Ak*(Ak+abs(a(k,k))))
          
          Qk=matmul(Uk,a)
          Qk=Qk*BETAk
          
          MIUk=dot_product(Uk,b)
          MIUk=Miuk*BETAk
          
          do i=1,m
             do j=1,n
                Anew(i,j)=a(i,j)-Uk(i)*Qk(j)
             end do
          end do
          
          Bnew=b-MIUk*Uk
       end do
    
       bnew(m)=bnew(m)/anew(m,n)
       do k=m-1,1,-1
          bnew(k)=(bnew(k)-dot_product(anew(k,k+1:m),bnew(k+1:m)))/a(k,k)
       end do
       e(:,ii)=bnew
    end do !ii
    
    deallocate(a,b,anew,bnew,Uk,qk)
    !write(2,*)'************A*****'
    !do i=1,m
    !write(2,*)a(i,1:n),b(i)
    !end do
    !write(2,*)'************ANEW****'
    !do i=1,m
    !write(2,*)anew(i,1:n),bnew(i)
    !end do
    end subroutine householderx
    
    !C
      FUNCTION JULDATE(ID,MM,IYYY)
!C
!C======================================================================
!C
!C       PURPOSE:  THIS IS A GENERIC JULIAN DATE CALCULATOR.  THE DATE
!C             RETURNED IS THE ACTUAL JULIAN DATE
!C             (EX. MAY 23, 1968 = 2,440,000)
!C
!C       REF: "NUMERICAL RECIPES: THE ART OF SCIENTIFIC COMPUTING",
!C          CAMBRIDGE UNIVERSITY PRESS, 1986. PG 10.
!C
!C       VARIABLE DEFINITIONS:
!C       VARIABLE  I/O DESCRIPTION
!C       --------  --- -----------
!C       ID         I  DAY OF MONTH (BETWEEN 1-31)
!C       IYYY   I  YEAR WHICH THE JULIAN DATE IS CONTAINED (EX 1987)
!C       JA         L  USED IN CALCULATING CORRECTION FOR LEAP YEAR IN
!C                 INPUTTED DATE
!C       JULDATE    O  JULIAN DATE BASED ON GREGORIAN CALENDAR
!C       JM         L  MODIFIED MONTH
!C       JULIAN     L  DATE WITHOUT CORRECTION FOR LEAP YEAR
!C       JY         L  MODIFIED YEAR
!C       MM         I  THE MONTH OF THE YEAR (EX 12 = DEC, 5 = MAY)
!C
!C       CALLED FROM:
!C
!C       PROGRAMMER:  NUMERICAL RECIPES PROGRAMMER.
!C
!C       VERSION: 3.2
!C
!C======================================================================
!C
      !IMPLICIT DOUBLE PRECISION (A-H,O-Z)
      integer(ink) ID,MM,IYYY,JY,JM,JULIAN,JA,JULDATE,JUL
!C
      IF(IYYY.LE.0) THEN
        STOP'DATE SPECIFIED IN A MANAGEMENT PRACTICE IS INCORRECT'
      ENDIF
      IF(MM.GT.2) THEN
        JY=IYYY
        JM=MM+1
      ELSE
        JY=IYYY-1
        JM=MM+13
      ENDIF
!C
!C     --CALCULATE THE JULIAN DATE FOR THE SPECIFIED DATE.
!C
      JULIAN=INT(365.25*JY)+INT(30.6001*JM)+ID+1720995
      JA=INT(0.01*JY)
      JULDATE=JULIAN+2-JA+INT(0.25*JA)
!C another way to calculate JUlIAN
      JUL=INT(1461*(IYYY+4800+INT((MM-14)/12))/4)+  &
          INT((367*(MM-2-12*INT((MM-14)/12)))/12)-   &
          INT((3*INT((IYYY+4900+INT((MM-14)/12))/100))/4) &
            +ID-32075
      !RETURN
      END FUNCTION JULDATE
    
      FUNCTION JDATE(ID,MM,IYYY)
      integer(ink) ID,MM,IYYY,JY,JM,NJ,JAA,JULIAN,JA,JDATE
!C
!C======================================================================
!C
!C       PURPOSE:  THIS IS A GENERIC JULIAN DATE CALCULATOR.  THE DATE
!C             RETURNED IS THE POSITION OF THE JULIAN DATE IN THE
!C             SPECIFIED YEAR (EX. 12,05,1988 = 133RD DAY IN 1988)
!C
!C       REF: "NUMERICAL RECIPES: THE ART OF SCIENTIFIC COMPUTING",
!C          CAMBRIDGE UNIVERSITY PRESS, 1986. PG 10.
!C
!C       VARIABLE DEFINITIONS:
!C       VARIABLE  I/O DESCRIPTION
!C       --------  --- -----------
!C       ID         I  --DAY OF MONTH [EX 12).
!C       IYYY   I  THE YEAR WHICH THE JULIAN DATE IS CONTAINED (EX 1987).
!C       JA         L  USED IN CALCULATING CORRECTION FOR LEAP YEAR IN
!C                 INPUTTED DATE.
!C       JAA        L  USED IN CALCULATING CORRECTION FOR LEAP YEAR ON
!C                 FIRST DAY OF THE INPUTTED YEAR.
!C       JDATE  O  DAY OF YEAR (1-366)
!C       JM         L  MODIFIED MONTH.
!C       JULIAN     L  DATE WITHOUT CORRECTION FOR LEAP YEAR.
!C       JY         L  MODIFIED YEAR.
!C       MM         I  THE MONTH OF THE YEAR (EX 12 = DEC, 5 = MAY).
!C       NJ         L  JULIAN DATE FOR FIRST DAY OF THE INPUTTED YEAR.
!C
!C       CALLED FROM:
!C
!C       PROGRAMMER:  NUMERICAL RECIPES PROGRAMMER.
!C
!C       VERSION: 2.0
!C
!C======================================================================
!C
!      IMPLICIT DOUBLE PRECISION (A-H,O-Z)
!C

      IF(IYYY.LE.0) THEN
          STOP'DATE SPECIFIED IN A MANAGEMENT PRACTICE IS INCORRECT'
      ENDIF
      IF(MM.GT.2) THEN
        JY=IYYY
        JM=MM+1
      ELSE
        JY=IYYY-1
        JM=MM+13
      ENDIF
!C
!C     --CALCULATE THE JULIAN DATE FOR THE FIRST DAY OF THE SPECIFIED
!C     YEAR.
!C
      NJ=INT(365.25*(IYYY-1))+1721423
      JAA=INT(0.01*JY)
      NJ=NJ+2-JAA+INT(0.25*JAA)
!C
!C     --CALCULATE THE JULIAN DATE FOR THE SPECIFIED DATE.
!C
      JULIAN=INT(365.25*JY)+INT(30.6001*JM)+ID+1720995
      JA=INT(0.01*JY)
      JDATE=JULIAN+2-JA+INT(0.25*JA)-NJ
!C
!      RETURN
      END FUNCTION JDATE
      
      !C
      SUBROUTINE CJULDATE(JULDAY,id,im,IYYY)
!C
!C======================================================================
!C
!C       PURPOSE: DATE RETURNS THE DAY-OF-THE-MONTH AND THE MONTH
!C              GIVEN THE JULIAN DATE AND YEAR.
!C
!C       REF:
!C
!C       VARIABLE DEFINITIONS:
!C       VARIABLE  I/O DESCRIPTION
!C       --------  --- -----------
!C       I      L  INDEX VARIABLE
!C       ID        I/O --DAY OF MONTH [EX 12).
!C       IDAY   L  JULIAN DATE
!C       IM        I/O --MONTH OF YEAR.
!C       IYYY   I  --YEAR
!C       JDAY   I  JULIAN DAY    [1..366]
!C       KDA        L  --ARRAY OF JULIAN DATES REPRESENTING THE LAST DAY
!C                 OF THE PREVIOUS MONTH.
!C
!C       EXTERNAL REFERENCES:
!C                 NONE
!C
!C       PROGRAMMER:   KEN ROJAS
!C
!C       VERSION:  97.0
!C
!C======================================================================
!C
!      IMPLICIT DOUBLE PRECISION (A-H,O-Z)
!C
!C
    integer(ink) JULDAY,ID,IM,IYYY,L,N,I,J

      L=JULDAY+68569
	N=INT((4*L)/146097)
	L=L-INT((146097*N+3)/4)
	I=INT((4000*(L+1))/1461001)
	L=L-INT((1461*I)/4)+31
	J=INT((80*L)/2447)
	ID=L-INT((2447*J)/80)
	L=INT(J/11)
	IM=J+2-(12*L)
	IYYY=100*(N-49)+I+L
      !RETURN
      END SUBROUTINE CJULDATE

end module arrayutil
