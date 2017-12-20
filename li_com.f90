module li_com

  implicit none
  include 'mpif.h'

! li.in primary input variables
  integer :: nx,ny,nt
  real(8) :: tol,lx,ly,dt,theta,amp
  integer :: ni,ne,initphi,ninit
  real(8) :: kapni,kapti,kapne,kapte
  real(8) :: teti,memif,memip
  integer :: eperpi,epari,weighti,eperpe,epare,weighte
  integer :: bounded,isolate,zflow,odd
  real(8) :: xshape,yshape
  integer :: nrec,nprint,nmode
  integer,dimension(:,:),allocatable :: modeindices

! additional parameters
  complex(8) :: IU
  real(8) :: dx,dy
  real(8) :: sdt,cdt,sth,cth
  real(8) :: totvol,n0
  integer :: timestep
  integer :: iseed
  real(8) :: pi,pi2
  real(8) :: res
  integer :: tni,tne
  integer :: myid,nproc,ierr !MPI

! timing variables
  real(8) :: wall_start,wall_finish,wall_total

! fft variables
  complex(8),dimension(:),allocatable :: tmpx
  complex(8),dimension(:),allocatable :: tmpy

! particle array declarations
  ! ions
  real(8),dimension(:),allocatable :: xi,yi,vxi,vyi,vzi
  real(8),dimension(:),allocatable :: wi0,wi1
  ! electrons
  real(8),dimension(:),allocatable :: xe0,ye0,xe1,ye1,vpe
  real(8),dimension(:),allocatable :: we0,we1
  

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

! fft allocation
  allocate(tmpx(0:nx-1),tmpy(0:ny-1))

! particle allocation
  allocate(xi(1:ni),yi(1:ni))
  allocate(vxi(1:ni),vyi(1:ni),vzi(1:ni))
  allocate(wi0(1:ni),wi1(1:ni))
  allocate(xe0(1:ne),ye0(1:ne),xe1(1:ne),ye1(1:ne))
  allocate(vpe(1:ne))
  allocate(we0(1:ne),we1(1:ne))

! grid allocation
  allocate(den(0:nx,0:ny),denlast(0:nx,0:ny))
  allocate(deni(0:nx,0:ny),dene(0:nx,0:ny))
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

! fft deallocation
  deallocate(tmpx,tmpy)

! particle deallocation
  deallocate(xi,yi)
  deallocate(vxi,vyi,vzi)
  deallocate(wi0,wi1)
  deallocate(xe0,ye0,xe1,ye1)
  deallocate(vpe)
  deallocate(we0,we1)

! grid deallocation
  deallocate(den,denlast)
  deallocate(deni,dene)
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
