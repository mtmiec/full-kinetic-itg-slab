module li_com

  implicit none
  include 'mpif.h'

! li.in primary input variables
  integer :: nx,ny,nt,order
  real(8) :: tol,lx,ly,dt,theta,amp
  integer :: ni,ne,initphi,ninit,rand,fki,gke
  real(8) :: kapni,kapti,kapne,kapte
  real(8) :: teti,memi
  integer :: eperpi,epari,weighti,eperpe,epare,weighte
  integer :: reflect,oddmodes,isolate,zflow
  real(8) :: xshape,yshape
  integer :: nrec,nprint,nmode
  integer,dimension(:,:),allocatable :: modeindices
  real(8) :: bamp
  integer :: bmode(2)

! additional parameters
  complex(8) :: IU
  real(8) :: dx,dy
  real(8) :: sdt,cdt,sth,cth
  real(8) :: totvol,n0
  integer :: tstep
  integer :: iseed
  real(8) :: pi,pi2
  real(8) :: res
  integer :: tni,tne
  integer :: myid,nproc,ierr !MPI

! timing variables
  real(8) :: wall_start,wall_finish,wall_total

! other globals
  real(8) :: fe

! particle array declarations
  ! ions
  real(8),dimension(:),allocatable :: xi,yi,vxi,vyi,vpari !vy is in rotated frame!
  real(8),dimension(:),allocatable :: wi0,wi1,wpi0,wpi1
  ! electrons
  real(8),dimension(:),allocatable :: xe0,ye0,xe1,ye1,vpare
  real(8),dimension(:),allocatable :: we0,we1,wpe0,wpe1
  real(8),dimension(:),allocatable :: mue
  

! grid array declarations
  real(8),dimension(:,:),allocatable :: den,denlast !total charge density
  real(8),dimension(:,:),allocatable :: deni,dene !ion and electron densities
  real(8),dimension(:,:),allocatable :: phi,coeff
  real(8),dimension(:,:),allocatable :: ex,ey
  real(8),dimension(:,:),allocatable :: tempxy

! ky=0 quantities
  real(8),dimension(:),allocatable :: uy,uz,px,py

! mode history allocation
  complex(8),dimension(:),allocatable :: phihist,denhist,temphist




  save

!-----------------------------------------------------------------------

contains

!-----------------------------------------------------------------------

subroutine init_com

  implicit none

! particle allocation
  if (fki == 1) allocate(xi(1:ni),yi(1:ni))
  if (fki == 1) allocate(vxi(1:ni),vyi(1:ni),vpari(1:ni))
  if (fki == 1) allocate(wi0(1:ni),wi1(1:ni))
  if (fki == 1) allocate(wpi0(1:ni),wpi1(1:ni))
  allocate(xe0(1:ne),ye0(1:ne),xe1(1:ne),ye1(1:ne))
  allocate(vpare(1:ne))
  allocate(we0(1:ne),we1(1:ne))
  allocate(wpe0(1:ne),wpe1(1:ne))
  allocate(mue(1:ne))

! grid allocation
  allocate(den(0:nx,0:ny),denlast(0:nx,0:ny))
  if (fki == 1) allocate(deni(0:nx,0:ny))
  allocate(dene(0:nx,0:ny))
  allocate(phi(0:nx,0:ny),coeff(0:nx-1,0:ny-1))
  allocate(ex(0:nx,0:ny),ey(0:nx,0:ny))
  allocate(tempxy(0:nx,0:ny))

! ky=0 quantities
  allocate(uy(0:nx),uz(0:nx),px(0:nx),py(0:nx))

! history allocation
  allocate(phihist(1:nmode),denhist(1:nmode),temphist(1:nmode))
  allocate(modeindices(2,nmode))

end

!-----------------------------------------------------------------------

subroutine finalize_com

  implicit none

! particle deallocation
  if (fki == 1) deallocate(xi,yi)
  if (fki == 1) deallocate(vxi,vyi,vpari)
  if (fki == 1) deallocate(wi0,wi1)
  if (fki == 1) deallocate(wpi0,wpi1)
  deallocate(xe0,ye0,xe1,ye1)
  deallocate(vpare)
  deallocate(we0,we1)
  deallocate(wpe0,wpe1)
  deallocate(mue)

! grid deallocation
  deallocate(den,denlast)
  if (fki == 1) deallocate(deni)
  deallocate(dene)
  deallocate(phi,coeff)
  deallocate(ex,ey)
  deallocate(tempxy)

! ky=0 quantities
  deallocate(uy,uz,px,py)

! history deallocation
  deallocate(phihist,denhist,temphist)
  deallocate(modeindices)


  end

!-----------------------------------------------------------------------

end
