    include 'mkl_vsl.f90'
   include "errcheck.inc"
   include "statcheck.inc"
   
    module vsl_gauss_module
    
    use variable_types
    
    
        !include 'mkl_vsl.fi'
    contains
    
    
    subroutine vsl_gauss_gen_single(n,a,sigma,r)
    use mkl_vsl_type
    use mkl_vsl
    implicit none
    character(len=*), parameter :: PROCEDURE_NAME="vsl_test_gauss"
    integer n
    real :: a,sigma,r(:)
    type(vsl_stream_state) :: stream
    integer :: seed, i
    integer :: brng=VSL_BRNG_MCG31
    integer :: method=VSL_RNG_METHOD_GAUSSIAN_BOXMULLER2
    !real :: a = 5.0, sigma = 2.0
    
    integer status;
    
    
    call system_clock(count = seed)

    status = vslnewstream(stream, brng, seed)
    status = vsrnggaussian( method, stream, n, r, a, sigma )
    
    
    end subroutine vsl_gauss_gen_single    
        
    subroutine vsl_gauss_gen
    use mkl_vsl_type
    use mkl_vsl
    implicit none
    character(len=*), parameter :: PROCEDURE_NAME="vsl_test_gauss"
    integer,parameter :: n=10    !n=2000
    real :: r(n)
    type(vsl_stream_state) :: stream
    integer :: seed, i
    integer :: brng=VSL_BRNG_MCG31
    integer :: method=VSL_RNG_METHOD_GAUSSIAN_BOXMULLER2
    real :: a = 5.0, sigma = 2.0
    
    integer status;
    
    
    call system_clock(count = seed)
    print*,seed
    status = vslnewstream(stream, brng, seed)
    status = vsrnggaussian( method, stream, n, r, a, sigma )
    
    !open(11,file="gauss_random.txt")
    do i=1, n
        write(7, *) r(i)
    end do
    !close(11)
    
    end subroutine vsl_gauss_gen
    
  subroutine MKL_VSL_TEST

      USE MKL_VSL_TYPE
      USE MKL_VSL

      integer(kind=4) i,j,k
      integer(kind=4) errcode

      integer(kind=4) nn
      integer ndim,info
      integer n

      parameter(n=200,nn=5,ndim=3)

      integer brng,method,seed
      integer me

      real(kind=8) c(ndim*(ndim+1)/2),cc(ndim,ndim),a(ndim)
      real(kind=8) t(ndim*(ndim+1)/2)
      real(kind=8) r(ndim,n)
      real(kind=8) dbS(ndim),dbS2(ndim),dbMean(ndim),dbVar(ndim)
      real(kind=8) dbCovXY,dbCovXZ,dbCovYZ

      real(kind=8) S(ndim),D2(ndim),Q(ndim)
      real(kind=8) DeltaM(ndim),DeltaD(ndim)

      TYPE (VSL_STREAM_STATE) :: stream

      brng=VSL_BRNG_MCG31
      seed=7777777
      method=VSL_RNG_METHOD_GAUSSIANMV_BOXMULLER2
      me=VSL_MATRIX_STORAGE_PACKED

!     Variance-covariance matrix for test
!     (should be symmetric,positive-definite)

!     This is packed storage for dpptrf subroutine
      !c(1)=16.0D0
      !c(2)=8.0D0
      !c(3)=4.0D0
      !c(4)=13.0D0
      !c(5)=17.0D0
      !c(6)=62.0D0
      !
      !a(1)=3.0D0
      !a(2)=5.0D0
      !a(3)=2.0D0
      
      
      
     c(1)=16.0D0
      c(2)=0.0D0
      c(3)=0.0D0
      c(4)=13.0D0
      c(5)=0.0D0
      c(6)=62.0D0

      a(1)=3.0D0
      a(2)=5.0D0
      a(3)=2.0D0    

      k = 1
      do i = 1, ndim
        do j = i, ndim
          cc(i, j) = c(k)
          k = k+1
        end do
        do j = 1, i-1
          cc(i, j) = cc(j, i)
        end do
      end do

      write(7,*)'Variance-covariance matrix C'
      write (7,'(3F7.3)') cc
      write(7,*)''

      write(7,*)'Mean vector a:'
      write (7,'(3F7.3)') a
      write(7,*)''

      t = c
      call dpptrf('L',ndim,t,info)

      write(7,*)'VSL_MATRIX_STORAGE_PACKED'
      write(7,*)'-------------------------'

!     Stream initialization
      errcode=vslNewStream(stream,brng,seed)
      call CheckVslError(errcode)

!     Generating random numbers
!     from multivariate normal distribution
      errcode=vdRngGaussianMV(method,stream,n,r,ndim,me,a,t)
      call CheckVslError(errcode)

!     Printing random numbers
      write(7,11) ' Results (first ',nn,' of ',n,')'
      write(7,*)'--------------------------'
11    format(A,I1,A,I5,A)

      do i=1,nn
        write(7,12)' r(',i,')=(',r(:,i),')'
      end do
12    format(A,I1,A,3F8.3,A)
      
      do i=1,ndim
      dbmean(i)=sum(r(i,:))/n
      end do
      
      write(7,*)'dbmean=',dbmean
      
        do i=1,ndim
      dbvar(i)=sum((r(i,:)-dbmean(i))**2)/n
        end do
       write(7,*)'dbvar=',dbvar  
       
       dbcovxy=0.;dbcovxz=0.;dbcovyz=0.
       do i=1,n
           do j=i+1,n
        dbcovxy=dbcovxy+(r(1,i)-r(1,j))*(r(2,i)-r(2,j))
        dbcovxz=dbcovxz+(r(1,i)-r(1,j))*(r(3,i)-r(3,j))
        dbcovyz=dbcovyz+(r(2,i)-r(2,j))*(r(3,i)-r(3,j))
           end do
       end do
       dbcovxy=dbcovxy/n**2;dbcovyz=dbcovyz/n**2;dbcovxz=dbcovxz/n**2
       
          write(7,*)'Sample characteristics  1:'
      write(7,*)'-----------------------'
      write(7,*)'      Sample             Theory'
      write(7,13)' Mean :(',dbMean(1),dbMean(2),dbMean(3),                &
     &         ')  (',a(1),a(2),a(3),')'
      write(7,13)' Var. :(',dbVar(1),dbVar(2),dbVar(3),                   &
     &         ')  (',cc(1,1),cc(2,2),cc(3,3),')'
      write(7,14)' CovXY: ',dbCovXY,'          ',cc(1,2)
      write(7,14)' CovXZ: ',dbCovXZ,'          ',cc(1,3)
      write(7,14)' CovYZ: ',dbCovYZ,'          ',cc(2,3)

        
      write(7,*)''

      call dCalculateGaussianMVSampleCharacteristics(ndim, n, r,        &
     &      dbS, dbS2, dbMean, dbVar, dbCovXY, dbCovXZ, dbCovYZ)

!     Printing
      write(7,*)'Sample characteristics   2:'
      write(7,*)'-----------------------'
      write(7,*)'      Sample             Theory'
      write(7,13)' Mean :(',dbMean(1),dbMean(2),dbMean(3),                &
     &         ')  (',a(1),a(2),a(3),')'
      write(7,13)' Var. :(',dbVar(1),dbVar(2),dbVar(3),                   &
     &         ')  (',cc(1,1),cc(2,2),cc(3,3),')'
      write(7,14)' CovXY: ',dbCovXY,'          ',cc(1,2)
      write(7,14)' CovXZ: ',dbCovXZ,'          ',cc(1,3)
      write(7,14)' CovYZ: ',dbCovYZ,'          ',cc(2,3)
13    format(A,F5.1,F5.1,F5.1,A,F5.1,F5.1,F5.1,A)
14    format(A,F6.1,A,F6.1)
      print *,''

      errcode=dGaussianMVCheckResults(ndim, n, a, cc, dbMean, dbVar, S, &
     &      D2, Q, DeltaM, DeltaD)

      if (errcode /= 0) then
        write(7,*)"Error: sample moments"
        write(7,*)"disagree with theory"
        write(7,15) "    DeltaM: ", DeltaM(1), DeltaM(2), DeltaM(3)
        write(7,15) "    DeltaD: ", DeltaD(1), DeltaD(2), DeltaD(3)
        print *,  "   ( at least one of the Deltas > 3.0) "
        stop 1
      else
        write(7,*)"Sample moments"
        write(7,*)"agree with theory"
        write(7,15) "    DeltaM: ", DeltaM(1), DeltaM(2), DeltaM(3)
        write(7,15) "    DeltaD: ", DeltaD(1), DeltaD(2), DeltaD(3)
        write(7,*)  "   ( all Deltas < 3.0) "
      end if
15    format(A,F7.3,F7.3,F7.3)
      print *,''

!     Stream finalization
      errcode=vslDeleteStream(stream)
      call CheckVslError(errcode)

      end subroutine MKL_VSL_TEST   
!    
    end module