!-----------------------------------------------------------------------
!---------2D Lorentz Ion ITG Delta-f Code-------------------------------
!-----------------------------------------------------------------------

program li
  use li_com
  use fft_wrapper
  use fcnt

  implicit none
  integer :: doprint

  call mpi_init(ierr)
  call mpi_comm_size(mpi_comm_world,nproc,ierr)
  call mpi_comm_rank(mpi_comm_world,myid,ierr)

  !set start time in sec
  wall_start = mpi_wtime()

  !initialization
  call initialize
  call load
  call accumulate
  call field

  !main loop
  do timestep=1,nt

    doprint=0
    if (myid==0.and.mod(timestep,nprint).eq.0) doprint=1
    if (doprint.eq.1) print *
    if (doprint.eq.1) print *, 'timestep', timestep

    call epush

    !iterate over ipush
    res=1
    do while (res.gt.tol)
      call ipush
      call accumulate
      call field
      call residual
      if (doprint.eq.1) print *,'residual =',res
    end do

    w0=w1

    call temperature

    !file output
    call modeout(phihist,'phist',11)
    call modeout(denhist,'dhist',12)
    call modeout(temphist,'thist',13)
    !call diagnostics
    !call zdiagnostics
    if (mod(timestep,nrec).eq.0) then
      call gridout(phi0,'phixy',14)
      call gridout(den0,'denxy',15)
      call gridout(tempxy,'temxy',16)
    end if

  end do

  call finalize_com

  !set end time in sec
  wall_finish = mpi_wtime()

  call mpi_finalize(ierr)

  !time elapsed in sec
  wall_total=wall_finish-wall_start
  if (myid==0) then  
    print *
    print *, 'Wall Clock Seconds Elapsed = ',wall_total
  endif

!-----------------------------------------------------------------------

contains

!-----------------------------------------------------------------------
!---------initialize subroutines----------------------------------------
!-----------------------------------------------------------------------

subroutine initialize

  implicit none
  character*(72) dumchar
  integer :: idum,i,j,ki,kj
  real(8) :: kx,ky,kp2,filt

  do i=0,nproc-1
    if (myid==i) then
      !read parameters from li.in
      open(115,file='li.in')
      read(115,*) dumchar
      read(115,*) dumchar
      read(115,*) dumchar
      read(115,*) dumchar
      read(115,*) nx,ny,nt,tol
      read(115,*) dumchar
      read(115,*) lx,ly,dt,theta
      read(115,*) dumchar
      read(115,*) tni,amp,initphi,ninit
      read(115,*) dumchar
      read(115,*) kapn,kapt,tets,memi
      read(115,*) dumchar
      read(115,*) bounded,enlin,wnlin,odd
      read(115,*) dumchar
      read(115,*) isolate,zflow,xshape,yshape
      read(115,*) dumchar
      read(115,*) nrec,nprint,nmode
      ni=tni/nproc !particles per proc
      tni=ni*nproc !actual total particle number
      call init_com
      read(115,*) dumchar
      read(115,*) modeindices
      close(115)
    endif
    call mpi_barrier(mpi_comm_world,ierr)
  enddo

! compute remaining parameters
  IU=cmplx(0.,1.)
  pi=4.0*datan(dble(1.0))
  pi2=pi*2.0
  dx=lx/float(nx)
  dy=ly/float(ny)
  sdt=dsin(dt)
  cdt=dcos(dt)
  sth=dsin(theta)
  cth=dcos(theta)

  iseed=-(1777)
  idum=ran2(iseed)

! intialize fourier transform subrourtines
  call ccfft('x',0,nx,tmpx)
  call ccfft('y',0,ny,tmpy)

! calculate coefficients for potential
  do i=0,nx-1
    do j=0,ny-1
      coeff(i,j)=0.
      ki = min(i,nx-i)
      kj = min(j,ny-j)
      kx = 2*pi*ki/lx
      ky = 2*pi*kj/ly
      kp2 = kx*kx + ky*ky
      filt = exp(-1*(xshape**2*kx**2+yshape**2*ky**2)**2)
      if (((kj==0).and.(ki/=0)).and.((odd==1).or.(mod(ki,2)==1))) coeff(i,j) = float(zflow)*filt/(memi*tets*kp2) !ky=0
      if ((kj/=0).and.(ki/=0)) coeff(i,j) = filt !ky/=0
    end do
  end do


end

!-----------------------------------------------------------------------

subroutine load

  integer :: m

  do m=1,ni
!   load particle positions
    x0(m)=lx*revers(myid*ni+m,2)
    y0(m)=ly*(dble(myid*ni+m)-0.5)/dble(tni)
!   load maxwellian velocities
    vx0(m)=dinvnorm(revers(myid*ni+m,3))
    vy0(m)=dinvnorm(revers(myid*ni+m,5))
    vz0(m)=dinvnorm(revers(myid*ni+m,7))
!   initialize weights
    w0(m)=amp*dsin(pi2*x0(m)/lx)*dsin(pi2*y0(m)/ly)
    w1(m)=w0(m)
  end do

end

!-----------------------------------------------------------------------
!---------deposit subroutines-------------------------------------------
!-----------------------------------------------------------------------

subroutine accumulate

  implicit none
  real(8) :: xpdx,ypdy,wx,wy
  real(8) :: myden(0:nx,0:ny)
  integer :: i,j,m

  denlast=den0
  den0=0
  myden=0

  do m=1,ni
    xpdx=x0(m)/dx
    ypdy=y0(m)/dy
    i=int(xpdx)
    j=int(ypdy)
    wx=dble(i+1)-xpdx
    wy=dble(j+1)-ypdy
    myden(i,j)=myden(i,j)+w1(m)*wx*wy
    myden(i+1,j)=myden(i+1,j)+w1(m)*(1.0-wx)*wy
    myden(i,j+1)=myden(i,j+1)+w1(m)*wx*(1.0-wy)
    myden(i+1,j+1)=myden(i+1,j+1)+w1(m)*(1.0-wx)*(1.0-wy)
  end do

  call mpi_allreduce(myden,den0,(nx+1)*(ny+1),mpi_real8,mpi_sum,mpi_comm_world,ierr)

  !divide by particles per cell
  den0=den0*dble(nx)*dble(ny)/dble(tni)

  do i=0,nx
    den0(i,0)=den0(i,0)+den0(i,ny)
    den0(i,ny)=den0(i,0)
  end do

  do j=0,ny
    den0(0,j)=den0(0,j)+den0(nx,j)
    den0(nx,j)=den0(0,j)
  end do

  if ((timestep.le.ninit).and.(initphi.eq.1)) then
    do i=0,nx
      do j=0,ny
        den0(i,j)=amp*dsin(pi*i/nx)*dsin(pi2*j/ny)
      end do
    end do
  end if

end

!-----------------------------------------------------------------------
!--------field subroutines----------------------------------------------
!-----------------------------------------------------------------------

subroutine field

  implicit none
  integer :: i,j,ki,kj
  real(8) :: kx,ky
  complex(8) :: phi(0:nx-1,0:ny-1)
  complex(8) :: ex(0:nx-1,0:ny-1),ey(0:nx-1,0:ny-1)

  !set potential equal to density and transform to k-space
  phi = den0(0:nx-1,0:ny-1)

  do j=0,ny-1
    call ccfft('x',-1,nx,phi(:,j))
  end do

  do i=0,nx-1
    call ccfft('y',-1,ny,phi(i,:))
  end do

  !normalize
  phi=phi/nx/ny

  !record selected density modes
  do i=1,nmode
    denhist(i) = phi(modeindices(1,i),modeindices(2,i))
  end do

  !(optional) enforce phi=0 at x=0 and x=lx/2
  if (bounded==1) then
    do i=1,nx/2
      do j=0,ny-1
        phi(i,j)=(phi(i,j)-phi(nx-i,j))/2
        phi(nx-i,j)=-1*phi(i,j)
      end do
    end do
  end if

  !calculate phi with coefficients calculated during initialization
  do i=1,nx-1
    do j=0,ny-1
      phi(i,j) = coeff(i,j)*phi(i,j)
    end do
  end do

  !record selected modes
  do i=1,nmode
    phihist(i) = phi(modeindices(1,i),modeindices(2,i))
  end do

  !(optional) remove all modes except (1,1)=-(-1,1) and (2,0)
  if (isolate==1) then
    do i=0,nx-1
      do j=0,ny-1
        ki = min(i,nx-i)
        kj = min(j,ny-j)
        if (((ki/=1).or.(kj/=1)).and.((ki/=2).or.(kj/=0))) then
          phi(i,j)=0
        end if
      end do
    end do
  end if

  !calculate e-field
  do i=0,nx-1
    do j=0,ny-1
      if (i<=nx/2) kx = 2*pi*i/lx
      if (i>nx/2) kx = -2*pi*(nx-i)/lx
      if (j<=ny/2) ky = 2*pi*j/ly
      if (j>ny/2) ky = -2*pi*(ny-j)/ly
      ex(i,j) = -IU*kx*tets*phi(i,j)
      ey(i,j) = -IU*ky*tets*phi(i,j)
    end do
  end do

  do i=0,nx-1
    call ccfft('y',1,ny,phi(i,:))
    call ccfft('y',1,ny,ex(i,:))
    call ccfft('y',1,ny,ey(i,:))

  end do

  do j=0,ny-1
    call ccfft('x',1,nx,phi(:,j))
    call ccfft('x',1,nx,ex(:,j))
    call ccfft('x',1,nx,ey(:,j))

  end do

  !store final phi,e-field
  phi0(0:nx-1,0:ny-1)=real(phi)
  ex0(0:nx-1,0:ny-1)=real(ex)
  ey0(0:nx-1,0:ny-1)=real(ey)

  !periodic boundaries
  phi0(:,ny)=phi0(:,0)
  phi0(nx,:)=phi0(0,:)
  ex0(:,ny)=ex0(:,0)
  ex0(nx,:)=ex0(0,:)
  ey0(:,ny)=ey0(:,0)
  ey0(nx,:)=ey0(0,:)

  return

end

!-----------------------------------------------------------------------

subroutine residual

  implicit none
  integer :: i,j
  real(8) :: norm

  res=0
  norm=0

  do i=0,nx
    do j=0,ny
      res = res + (den0(i,j)-denlast(i,j))**2
      norm = norm + den0(i,j)**2
    end do
  end do
  res = (res/norm)**.5

end

!-----------------------------------------------------------------------
!--------particle push subroutines--------------------------------------
!-----------------------------------------------------------------------

subroutine epush

  implicit none
  integer :: m,i,j
  real(8) :: vdv,kap,edv
  real(8) :: ax,ay
  real(8) :: wx,wy
  real(8) :: xpdx,ypdy
  real(8) :: vxt,vyt !temp velocity storage

  do m=1,ni
    ! interpolation weights
    xpdx=x0(m)/dx
    ypdy=y0(m)/dy
    i=int(xpdx)
    j=int(ypdy)
    wx=dble(i+1)-xpdx
    wy=dble(j+1)-ypdy
    ! interpolate e-field
    ax=ex0(i,j)*wx*wy+ex0(i+1,j)*(1.0-wx)*wy+&
      ex0(i,j+1)*wx*(1.0-wy)+ex0(i+1,j+1)*(1.0-wx)*(1.0-wy)
    ay=ey0(i,j)*wx*wy+ey0(i+1,j)*(1.0-wx)*wy+&
      ey0(i,j+1)*wx*(1.0-wy)+ey0(i+1,j+1)*(1.0-wx)*(1.0-wy)
    ! 1/2 velocity push
    vx0(m)=vx0(m)+.5*dt*ax*enlin
    vy0(m)=vy0(m)+.5*dt*ay*enlin
    ! full velocity rotation (theta,dt,-theta)
    vxt=cdt*vx0(m)+sdt*cth*vy0(m)-sdt*sth*vz0(m)
    vyt=-1.0*sdt*cth*vx0(m)+(cdt*cth**2+sth**2)*vy0(m)&
      +(-1.0*cdt*sth*cth+sth*cth)*vz0(m)
    vz0(m)=sdt*sth*vx0(m)+(-1.0*cdt*sth*cth+sth*cth)*vy0(m)&
      +(cdt*sth**2+cth**2)*vz0(m)
    vx0(m)=vxt
    vy0(m)=vyt
    ! 1/2 velocity push
    vx0(m)=vx0(m)+.5*dt*ax*enlin
    vy0(m)=vy0(m)+.5*dt*ay*enlin
    ! weight equation terms
    vdv=vx0(m)**2+vy0(m)**2+vz0(m)**2
    edv=vx0(m)*ax+vy0(m)*ay
    kap=kapn+kapt*(.5*vdv-1.5)
    ! explicit 1/2 weight advance
    w0(m)=w0(m)+.5*dt*(1-w0(m)*wnlin)*(edv+cth*ay*kap)
    ! full position advance
    x0(m)=x0(m)+dt*vx0(m)
    y0(m)=y0(m)+dt*vy0(m)
    ! periodic boundaries
    x0(m)=x0(m)-lx*dble(floor(x0(m)/lx))
    y0(m)=y0(m)-ly*dble(floor(y0(m)/ly))
  end do


end

!-----------------------------------------------------------------------

subroutine ipush

  implicit none
  integer :: m,i,j
  real(8) :: vdv,kap,edv
  real(8) :: ax,ay
  real(8) :: wx,wy
  real(8) :: xpdx,ypdy

  do m=1,ni
    xpdx=x0(m)/dx
    ypdy=y0(m)/dy
    i=int(xpdx)
    j=int(ypdy)
    wx=dble(i+1)-xpdx
    wy=dble(j+1)-ypdy
    ! interpolate e-field
    ax=ex0(i,j)*wx*wy+ex0(i+1,j)*(1.0-wx)*wy+&
      ex0(i,j+1)*wx*(1.0-wy)+ex0(i+1,j+1)*(1.0-wx)*(1.0-wy)
    ay=ey0(i,j)*wx*wy+ey0(i+1,j)*(1.0-wx)*wy+&
      ey0(i,j+1)*wx*(1.0-wy)+ey0(i+1,j+1)*(1.0-wx)*(1.0-wy)
    ! weight equation terms
    vdv=vx0(m)**2+vy0(m)**2+vz0(m)**2
    edv=vx0(m)*ax+vy0(m)*ay
    kap=kapn+kapt*(.5*vdv-1.5)
    ! implicit weight advance
    w1(m)=w0(m)+.5*dt*(1-w1(m)*wnlin)*(edv+cth*ay*kap)
  end do

end

!-----------------------------------------------------------------------

subroutine temperature

  !calculate tperp on grid

  implicit none
  real(8) :: xpdx,ypdy,wx,wy
  real(8) :: mytempxy(0:nx,0:ny)
  integer :: i,j,m
  complex(8) :: ktemp(0:nx-1,0:ny-1)

  tempxy=0

  do m=1,ni
    xpdx=x0(m)/dx
    ypdy=y0(m)/dy
    i=int(xpdx)
    j=int(ypdy)
    wx=dble(i+1)-xpdx
    wy=dble(j+1)-ypdy
    mytempxy(i,j)=mytempxy(i,j)+w1(m)*wx*wy*(vx0(m)**2+(cth*vy0(m)-sth*vz0(m))**2)
    mytempxy(i+1,j)=mytempxy(i+1,j)+w1(m)*(1.0-wx)*wy*(vx0(m)**2+(cth*vy0(m)-sth*vz0(m))**2)
    mytempxy(i,j+1)=mytempxy(i,j+1)+w1(m)*wx*(1.0-wy)*(vx0(m)**2+(cth*vy0(m)-sth*vz0(m))**2)
    mytempxy(i+1,j+1)=mytempxy(i+1,j+1)+w1(m)*(1.0-wx)*(1.0-wy)*(vx0(m)**2+(cth*vy0(m)-sth*vz0(m))**2)
  end do
 
  call mpi_allreduce(mytempxy,tempxy,(nx+1)*(ny+1),mpi_real8,mpi_sum,mpi_comm_world,ierr)

  !divide by particles per cell
  tempxy=tempxy*dble(nx)*dble(ny)/dble(tni)

  do i=0,nx
    tempxy(i,0)=tempxy(i,0)+tempxy(i,ny)
    tempxy(i,ny)=tempxy(i,0)
  end do

  do j=0,ny
    tempxy(0,j)=tempxy(0,j)+tempxy(nx,j)
    tempxy(nx,j)=tempxy(0,j)
  end do

  !transform to record fourier space components
  ktemp = tempxy(0:nx-1,0:ny-1)

  do j=0,ny-1
    call ccfft('x',-1,nx,ktemp(:,j))
  end do

  do i=0,nx-1
    call ccfft('y',-1,ny,ktemp(i,:))
  end do

  ktemp = ktemp/nx/ny

  !record selected modes
  do i=1,nmode
    temphist(i) = ktemp(modeindices(1,i),modeindices(2,i))
  end do


end

!-----------------------------------------------------------------------
!--------history subroutines--------------------------------------------
!-----------------------------------------------------------------------

subroutine modeout(hist,fl,id)

  !record components of phi given by modehist

  implicit none
  integer :: i,id
  character*5 :: fl
  character*70 :: flnm
  complex(8) :: hist(1:nmode)

  if (myid==0) then
    flnm=fl//'.out'
    open(id,file=flnm,form='formatted',status='unknown',&
      position='append')
    write(id,'(f8.2)',advance="no") dt*timestep
    do i=1,nmode
      write(id,'(a2,e13.6,a2,e13.6)',advance="no") '  ',real(hist(i)),&
        '  ',imag(hist(i))
    end do
    write(id,*)
    endfile id
    close(id)
  endif

end

!-----------------------------------------------------------------------

subroutine gridout(u,fl,id)

  !record all values of grid quantity

  implicit none
  integer :: i,j,id
  real(8) :: u(0:nx,0:ny)
  character*5 :: fl
  character*70 :: flnm

  if (myid==0) then
    flnm=fl//'.out'
    open(id,file=flnm,form='formatted',status='unknown',&
      position='append')
    do j=0,ny
      do i=0,nx
        write(id,'(e11.4)') u(i,j)
      end do
    end do
    endfile id
    close(id)
  endif
  
end

!-----------------------------------------------------------------------

subroutine diagnostics

  implicit none
  integer :: id,m,i,j
  real(8) ::xpdx,ypdy,wx,wy,qx,myqx,w2sum,myw2sum
  character*5 :: fl
  character*70 :: flnm

  id=89

  qx=0
  myqx=0
  w2sum=0
  myw2sum=0
  do m=1,ni
    !net heat flux in x-direction
    myqx = myqx + w1(m)*vx0(m)*(vx0(m)**2+vy0(m)**2+vz0(m)**2)
    !weight squared sum
    myw2sum = myw2sum + w1(m)**2
  end do

  call mpi_allreduce(myqx,qx,1,mpi_real8,mpi_sum,mpi_comm_world,ierr)
  call mpi_allreduce(myw2sum,w2sum,1,mpi_real8,mpi_sum,mpi_comm_world,ierr)

  qx=qx/dble(tni)
  w2sum=w2sum/dble(tni)

  if (myid==0) then
    flnm='diagn.out'
    open(id,file=flnm,form='formatted',status='unknown',&
      position='append')
    write(id,'(f8.2)',advance="no") dt*timestep
    write(id,'(a2,e13.6,a2,e13.6)') '  ',qx,'  ',w2sum
    endfile id
    close(id)
  endif

end

!-----------------------------------------------------------------------

subroutine zdiagnostics

  implicit none
  integer :: i,m,il,ir,uyid,uzid,pxid,pyid
  character*70 :: uyflnm,uzflnm,pxflnm,pyflnm
  real(8) :: xpdx,wx,kx,p(0:nx)
  real(8) :: myuy(0:nx),myuz(0:nx),mypx(0:nx),mypy(0:nx)

  uy=0
  myuy=0
  uz=0
  myuz=0
  px=0
  mypx=0
  py=0
  mypy=0

  do m=1,ni
    xpdx=x0(m)/dx
    i=int(xpdx)
    wx=dble(i+1)-xpdx
    myuy(i)=myuy(i)+w1(m)*wx*vy0(m)
    myuy(i+1)=myuy(i+1)+w1(m)*(1.0-wx)*vy0(m)
    myuz(i)=myuz(i)+w1(m)*wx*vz0(m)
    myuz(i+1)=myuz(i+1)+w1(m)*(1.0-wx)*vz0(m)
    mypx(i)=mypx(i)+w1(m)*wx*vx0(m)**2
    mypx(i+1)=mypx(i+1)+w1(m)*(1.0-wx)*vx0(m)**2
    mypy(i)=mypy(i)+w1(m)*wx*(cth*vy0(m)-sth*vz0(m))**2
    mypy(i+1)=mypy(i+1)+w1(m)*(1.0-wx)*(cth*vy0(m)-sth*vz0(m))**2
  enddo

  call mpi_allreduce(myuy,uy,nx+1,mpi_real8,mpi_sum,mpi_comm_world,ierr)
  call mpi_allreduce(myuz,uz,nx+1,mpi_real8,mpi_sum,mpi_comm_world,ierr)
  call mpi_allreduce(mypx,px,nx+1,mpi_real8,mpi_sum,mpi_comm_world,ierr)
  call mpi_allreduce(mypy,py,nx+1,mpi_real8,mpi_sum,mpi_comm_world,ierr)

  !divide by particles per column
  uy=uy*dble(nx)/dble(tni)
  uz=uz*dble(nx)/dble(tni)
  px=px*dble(nx)/dble(tni)
  py=py*dble(nx)/dble(tni)

  !periodic boundaries
  uy(0)=uy(0)+uy(nx)
  uz(0)=uz(0)+uz(nx)
  px(0)=px(0)+px(nx)
  py(0)=py(0)+py(nx)
  uy(nx)=uy(0)
  uz(nx)=uz(0)
  px(nx)=px(0)
  py(nx)=py(0)

  uyid=99
  uzid=98
  pxid=97
  pyid=96

  uyflnm='uy.out'
  uzflnm='uz.out'
  pxflnm='px.out'
  pyflnm='py.out'

  if (myid==0) then
    open(uyid,file=uyflnm,form='formatted',status='unknown',&
      position='append')
    write(uyid,'(f8.2)',advance='no') dt*timestep
    do i=0,nx
      write(uyid,'(a2,e13.6)',advance='no') '  ',uy(i)
    end do
    write(uyid,*)
    endfile uyid
    close(uyid)
  
    open(uzid,file=uzflnm,form='formatted',status='unknown',&
      position='append')
    write(uzid,'(f8.2)',advance='no') dt*timestep
    do i=0,nx
      write(uzid,'(a2,e13.6)',advance='no') '  ',uz(i)
    end do
    write(uzid,*)
    endfile uzid
    close(uzid)
  
    open(pxid,file=pxflnm,form='formatted',status='unknown',&
      position='append')
    write(pxid,'(f8.2)',advance='no') dt*timestep
    do i=0,nx
      write(pxid,'(a2,e13.6)',advance='no') '  ',px(i)
    end do
    write(pxid,*)
    endfile pxid
    close(pxid)
  
    open(pyid,file=pyflnm,form='formatted',status='unknown',&
      position='append')
    write(pyid,'(f8.2)',advance='no') dt*timestep
    do i=0,nx
      write(pyid,'(a2,e13.6)',advance='no') '  ',py(i)
    end do
    write(pyid,*)
    endfile pyid
    close(pyid)
  endif
 
  end

!-----------------------------------------------------------------------

end
