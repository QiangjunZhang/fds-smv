PROGRAM FDS  
 
! Fire Dynamics Simulator, Main Program, Single CPU version

USE PRECISION_PARAMETERS
USE MESH_VARIABLES
USE GLOBAL_CONSTANTS
USE TRAN
USE DUMP
USE READ_INPUT
USE INIT
USE DIVG
USE PRES
USE MASS
USE PART
USE VELO
USE RAD
USE MEMORY_FUNCTIONS
USE COMP_FUNCTIONS, ONLY : SECOND, WALL_CLOCK_TIME, SHUTDOWN
USE MATH_FUNCTIONS, ONLY : GAUSSJ
USE DEVICE_VARIABLES
USE WALL_ROUTINES
USE FIRE
USE CONTROL_FUNCTIONS
USE EVAC

IMPLICIT NONE
 
! Miscellaneous declarations
CHARACTER(255), PARAMETER :: mainid='$Id: main.f90,v 1.41 2007/04/30 17:13:26 mcgratta Exp $'
LOGICAL  :: EX,DIAGNOSTICS
INTEGER  :: LO10,NM,IZERO
REAL(EB) :: T_MAX,T_MIN
REAL(EB), ALLOCATABLE, DIMENSION(:) :: T,DT_SYNC,DTNEXT_SYNC
INTEGER, ALLOCATABLE, DIMENSION(:) ::  ISTOP
LOGICAL, ALLOCATABLE, DIMENSION(:) ::  ACTIVE_MESH
INTEGER NOM,IMIN,IMAX,JMIN,JMAX,KMIN,KMAX,IW
INTEGER, PARAMETER :: N_DROP_ADOPT_MAX=10000
TYPE (MESH_TYPE), POINTER :: M,M4
TYPE (OMESH_TYPE), POINTER :: M2,M3

! Start wall clock timing

WALL_CLOCK_START = WALL_CLOCK_TIME()
 
! Assign a compilation date (All Nodes)
 
COMPILE_DATE   = 'May 14, 2007'
VERSION_STRING = '5_RC3+' 
VERSION_NUMBER = 5.0
 
! Read input from CHID.data file (All Nodes)

CALL READ_DATA

CALL EVAC_READ_DATA
 
! Open and write to Smokeview file 
 
CALL WRITE_SMOKEVIEW_FILE

! Stop all the processes if this is just a set-up run
 
IF (SET_UP) CALL SHUTDOWN('Stop FDS, Set-up only')
 
! Set up Time array (All Nodes)
 
ALLOCATE(ACTIVE_MESH(NMESHES),STAT=IZERO)
CALL ChkMemErr('MAIN','ACTIVE_MESH',IZERO)
ALLOCATE(T(NMESHES),STAT=IZERO)
CALL ChkMemErr('MAIN','T',IZERO)
ALLOCATE(DT_SYNC(NMESHES),STAT=IZERO)
CALL ChkMemErr('MAIN','DT_SYNC',IZERO)
ALLOCATE(DTNEXT_SYNC(NMESHES),STAT=IZERO)
CALL ChkMemErr('MAIN','DTNEXT_SYNC',IZERO)
ALLOCATE(ISTOP(NMESHES),STAT=IZERO)
CALL ChkMemErr('MAIN','ISTOP',IZERO)
T     = T_BEGIN
ISTOP = 0
CALL INITIALIZE_GLOBAL_VARIABLES
IF (RADIATION) CALL INIT_RADIATION
DO NM=1,NMESHES
   CALL INITIALIZE_MESH_VARIABLES(NM)
ENDDO
! Allocate and initialize mesh variable exchange arrays
DO NM=1,NMESHES
   CALL INITIALIZE_MESH_EXCHANGE(NM)
ENDDO
I_MIN = TRANSPOSE(I_MIN)
I_MAX = TRANSPOSE(I_MAX)
J_MIN = TRANSPOSE(J_MIN)
J_MAX = TRANSPOSE(J_MAX)
K_MIN = TRANSPOSE(K_MIN)
K_MAX = TRANSPOSE(K_MAX)
NIC   = TRANSPOSE(NIC)
 
DO NM=1,NMESHES
   CALL DOUBLE_CHECK(NM)
ENDDO
 
! Potentially read data from a previous calculation 
 
DO NM=1,NMESHES
   IF (RESTART) CALL READ_CORE(T(NM),NM)
ENDDO
 
! Initialize output files containing global data 
 
CALL INITIALIZE_GLOBAL_DUMPS

CALL INIT_EVAC_DUMPS
 
! Initialize output files that are mesh-specific
 
DO NM=1,NMESHES
   CALL INITIALIZE_MESH_DUMPS(NM)
   CALL INITIALIZE_DROPLETS(NM)
   CALL INITIALIZE_TREES(NM)
   CALL INITIALIZE_EVAC(NM)
ENDDO
 
! Write out character strings to .smv file
 
CALL WRITE_STRINGS

! Initialize Mesh Exchange Arrays (All Nodes)

CALL MESH_EXCHANGE(0)

! Make an initial dump of ambient values

DO NM=1,NMESHES
   CALL UPDATE_OUTPUTS(T(NM),NM)      
   CALL DUMP_MESH_OUTPUTS(T(NM),NM)
ENDDO
CALL DUMP_GLOBAL_OUTPUTS(T(1))

! ********************************************************************
!                      MAIN TIMESTEPPING LOOP
! ********************************************************************

MAIN_LOOP: DO  
   ICYC  = ICYC + 1 
   ! Check for program stops

   INQUIRE(FILE=TRIM(CHID)//'.stop',EXIST=EX)
   IF (EX) ISTOP = 2
 
   ! Figure out fastest and slowest meshes
   T_MAX = -1000000._EB
   T_MIN =  1000000._EB
   DO NM=1,NMESHES
      T_MIN = MIN(T(NM),T_MIN)
      T_MAX = MAX(T(NM),T_MAX)
      IF (ISTOP(NM)>0) STOP_CODE = ISTOP(NM)
   ENDDO
 
   IF (SYNCHRONIZE) THEN
      DTNEXT_SYNC(1:NMESHES) = MESHES(1:NMESHES)%DTNEXT
      DO NM=1,NMESHES
         IF (SYNC_TIME_STEP(NM)) THEN
            MESHES(NM)%DTNEXT = MINVAL(DTNEXT_SYNC,MASK=SYNC_TIME_STEP)
            T(NM) = MINVAL(T,MASK=SYNC_TIME_STEP)
            ACTIVE_MESH(NM) = .TRUE.
         ELSE
            ACTIVE_MESH(NM) = .FALSE.
            IF (T(NM)+MESHES(NM)%DTNEXT<=T_MAX) ACTIVE_MESH(NM) = .TRUE.
            IF (STOP_CODE>0) ACTIVE_MESH(NM) = .TRUE.
         ENDIF
      ENDDO
   ELSE
      ACTIVE_MESH = .FALSE.
      DO NM=1,NMESHES
         IF (T(NM)+MESHES(NM)%DTNEXT <= T_MAX) ACTIVE_MESH(NM) = .TRUE.
         IF (STOP_CODE>0) ACTIVE_MESH(NM) = .TRUE.
      ENDDO
   ENDIF
   DIAGNOSTICS = .FALSE.
   LO10 = LOG10(REAL(MAX(1,ABS(ICYC)),EB))
   IF (MOD(ICYC,10**LO10)==0 .OR. MOD(ICYC,100)==0 .OR. T_MIN>=T_END .OR. STOP_CODE>0) DIAGNOSTICS = .TRUE.
   
   ! If no meshes are due to be updated, update them all
 
   IF (ALL(.NOT.ACTIVE_MESH)) ACTIVE_MESH = .TRUE.
   CALL EVAC_MAIN_LOOP

!=====================================================================
!  Predictor Step
!=====================================================================

   PREDICTOR = .TRUE.
   CORRECTOR = .FALSE.
   
   COMPUTE_FINITE_DIFFERENCES_1: DO NM=1,NMESHES
      IF (.NOT.ACTIVE_MESH(NM)) CYCLE COMPUTE_FINITE_DIFFERENCES_1
      MESHES(NM)%DT = MESHES(NM)%DTNEXT
      NTCYC(NM)   = NTCYC(NM) + 1
      CALL INSERT_DROPLETS_AND_PARTICLES(T(NM),NM)
      CALL COMPUTE_VELOCITY_FLUX(T(NM),NM)
      CALL UPDATE_PARTICLES(T(NM),NM)
      IF (.NOT.ISOTHERMAL .OR. N_SPECIES>0) CALL MASS_FINITE_DIFFERENCES(NM)
   ENDDO COMPUTE_FINITE_DIFFERENCES_1
   
   CHANGE_TIME_STEP_LOOP: DO
      COMPUTE_DIVERGENCE_LOOP: DO NM=1,NMESHES
         IF (.NOT.ACTIVE_MESH(NM)) CYCLE COMPUTE_DIVERGENCE_LOOP
         IF (.NOT.ISOTHERMAL .OR. N_SPECIES>0) THEN
            CALL DENSITY(NM)
            CALL WALL_BC(T(NM),NM)
         ENDIF
         CALL DIVERGENCE_PART_1(T(NM),NM)
      ENDDO COMPUTE_DIVERGENCE_LOOP

      CALL EXCHANGE_DIVERGENCE_INFO
      
      COMPUTE_PRESSURE_LOOP: DO NM=1,NMESHES
         IF (.NOT.ACTIVE_MESH(NM)) CYCLE COMPUTE_PRESSURE_LOOP
         CALL DIVERGENCE_PART_2(NM)
         CALL PRESSURE_SOLVER(NM)
         CALL EVAC_PRESSURE_LOOP(NM)
      ENDDO COMPUTE_PRESSURE_LOOP
 
      IF (PRESSURE_CORRECTION) CALL CORRECT_PRESSURE
      PREDICT_VELOCITY_LOOP: DO NM=1,NMESHES
         IF (.NOT.ACTIVE_MESH(NM)) CYCLE PREDICT_VELOCITY_LOOP
         CALL VELOCITY_PREDICTOR(T(NM),NM,ISTOP(NM))
         IF (ISTOP(NM)==1) STOP_CODE = 1
      ENDDO PREDICT_VELOCITY_LOOP
      IF (STOP_CODE>0) EXIT CHANGE_TIME_STEP_LOOP

      IF (SYNCHRONIZE .AND. ANY(CHANGE_TIME_STEP)) THEN
         CHANGE_TIME_STEP = .TRUE.
         DT_SYNC(1:NMESHES) = MESHES(1:NMESHES)%DT
         DTNEXT_SYNC(1:NMESHES) = MESHES(1:NMESHES)%DTNEXT
         DO NM=1,NMESHES
            IF (EVACUATION_ONLY(NM)) CHANGE_TIME_STEP(NM) = .FALSE.
            MESHES(NM)%DTNEXT = MINVAL(DTNEXT_SYNC,MASK=SYNC_TIME_STEP)
            MESHES(NM)%DT     = MINVAL(DT_SYNC,MASK=SYNC_TIME_STEP)
         ENDDO
      ENDIF
 
      IF (.NOT.ANY(CHANGE_TIME_STEP)) EXIT CHANGE_TIME_STEP_LOOP
 
   ENDDO CHANGE_TIME_STEP_LOOP
   CHANGE_TIME_STEP = .FALSE.
   
   DO NM=1,NMESHES
      IF (ACTIVE_MESH(NM)) T(NM) = T(NM) + MESHES(NM)%DT
   ENDDO

!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! Exchange information among meshes
   CALL MESH_EXCHANGE(1)
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
!  Corrector Step
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

   CORRECTOR = .TRUE.
   PREDICTOR = .FALSE.
   COMPUTE_FINITE_DIFFERENCES_2: DO NM=1,NMESHES
      IF (.NOT.ACTIVE_MESH(NM)) CYCLE COMPUTE_FINITE_DIFFERENCES_2
      CALL COMPUTE_VELOCITY_FLUX(T(NM),NM)     
      IF (.NOT.ISOTHERMAL .OR. N_SPECIES>0) THEN
         CALL MASS_FINITE_DIFFERENCES(NM)
         CALL DENSITY(NM)
         ! Do combustion, then apply thermal, species and density boundary conditions and solve for radiation
         IF (N_REACTIONS > 0) CALL COMBUSTION (NM)
         CALL WALL_BC(T(NM),NM)
         CALL COMPUTE_RADIATION(NM)
      ENDIF
      CALL UPDATE_PARTICLES(T(NM),NM)
      CALL DIVERGENCE_PART_1(T(NM),NM)
   ENDDO COMPUTE_FINITE_DIFFERENCES_2
     
   CALL EXCHANGE_DIVERGENCE_INFO
   
   COMPUTE_PRESSURE_LOOP_2: DO NM=1,NMESHES
      IF (.NOT.ACTIVE_MESH(NM)) CYCLE COMPUTE_PRESSURE_LOOP_2
      CALL DIVERGENCE_PART_2(NM)
      CALL PRESSURE_SOLVER(NM)
      CALL EVAC_PRESSURE_LOOP(NM)
   ENDDO COMPUTE_PRESSURE_LOOP_2
   
   IF (PRESSURE_CORRECTION) CALL CORRECT_PRESSURE 
     
   CORRECT_VELOCITY_LOOP: DO NM=1,NMESHES
      IF (.NOT.ACTIVE_MESH(NM)) CYCLE CORRECT_VELOCITY_LOOP
      CALL OPEN_AND_CLOSE(T(NM),NM)
      CALL VELOCITY_CORRECTOR(T(NM),NM)
!      CALL UPDATE_OUTPUTS(T(NM),NM)      
!      CALL DUMP_MESH_OUTPUTS(T(NM),NM)
      IF (DIAGNOSTICS) CALL CHECK_DIVERGENCE(NM)
   ENDDO CORRECT_VELOCITY_LOOP

   OUTPUT_LOOP: DO NM=1,NMESHES
      IF (.NOT.ACTIVE_MESH(NM)) CYCLE OUTPUT_LOOP
!      CALL OPEN_AND_CLOSE(T(NM),NM)
!      CALL VELOCITY_CORRECTOR(T(NM),NM)
      CALL UPDATE_OUTPUTS(T(NM),NM)      
      CALL DUMP_MESH_OUTPUTS(T(NM),NM)
!      IF (DIAGNOSTICS) CALL CHECK_DIVERGENCE(NM)
   ENDDO OUTPUT_LOOP


!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
! Exchange information among meshes
   CALL MESH_EXCHANGE(2)
   CALL EVAC_EXCHANGE
!++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

   ! Write character strings out to the .smv file
 
   CALL WRITE_STRINGS

   ! Exchange info for diagnostic print out
 
   IF (DIAGNOSTICS) CALL EXCHANGE_DIAGNOSTICS

   ! Dump global quantities like HRR, MASS, and DEViCes. 
   
   CALL DUMP_GLOBAL_OUTPUTS(MINVAL(T))
   CALL UPDATE_CONTROLS(T)
 
   ! Dump out diagnostics
 
   IF (DIAGNOSTICS) CALL WRITE_DIAGNOSTICS(T)
 
   ! Stop the run
   
   IF (T_MIN>=T_END .OR. STOP_CODE>0) EXIT MAIN_LOOP
 
   ! Flush Buffers 
   
   IF (MOD(ICYC,10)==0) CALL FLUSH_BUFFERS

ENDDO MAIN_LOOP
 
!***********************************************************************
!                          END OF TIMESTEP
!***********************************************************************
 
TUSED(1,1:NMESHES) = SECOND() - TUSED(1,1:NMESHES)
 
CALL TIMINGS
 
SELECT CASE(STOP_CODE)
   CASE(0)
      CALL SHUTDOWN('STOP: FDS completed successfully')
   CASE(1)
      CALL SHUTDOWN('STOP: Numerical Instability')
   CASE(2)
      CALL SHUTDOWN('STOP: FDS stopped by user')
END SELECT
 
 
CONTAINS

 
SUBROUTINE EXCHANGE_DIVERGENCE_INFO

! Exchange information mesh to mesh used to compute global pressure integrals

INTEGER :: IPZ
REAL(EB) :: DSUM_ALL,PSUM_ALL,USUM_ALL

DO IPZ=1,N_ZONE
   DSUM_ALL = 0._EB
   PSUM_ALL = 0._EB
   USUM_ALL = 0._EB
   DO NM=1,NMESHES
      DSUM_ALL = DSUM_ALL + DSUM(IPZ,NM)
      PSUM_ALL = PSUM_ALL + PSUM(IPZ,NM)
      USUM_ALL = USUM_ALL + USUM(IPZ,NM)
   ENDDO
   DSUM(IPZ,1:NMESHES) = DSUM_ALL
   PSUM(IPZ,1:NMESHES) = PSUM_ALL
   USUM(IPZ,1:NMESHES) = USUM_ALL
ENDDO

END SUBROUTINE EXCHANGE_DIVERGENCE_INFO
 

SUBROUTINE INITIALIZE_MESH_EXCHANGE(NM)
 
! Create arrays by which info is to exchanged across meshes
 
INTEGER IMIN,IMAX,JMIN,JMAX,KMIN,KMAX,NOM,IOR,IW
INTEGER, INTENT(IN) :: NM
TYPE (MESH_TYPE), POINTER :: M2,M
LOGICAL FOUND
!
M=>MESHES(NM)
!
ALLOCATE(M%OMESH(NMESHES))
!
OTHER_MESH_LOOP: DO NOM=1,NMESHES
!
   IF (NOM==NM) CYCLE OTHER_MESH_LOOP
!
   M2=>MESHES(NOM)
   IMIN=0
   JMIN=0
   KMIN=0
   IMAX=M2%IBP1
   JMAX=M2%JBP1
   KMAX=M2%KBP1
   NIC(NOM,NM) = 0
   FOUND = .FALSE.
   SEARCH_LOOP: DO IW=1,M%NEWC
      IF (M%IJKW(9,IW)/=NOM) CYCLE SEARCH_LOOP
      NIC(NOM,NM) = NIC(NOM,NM) + 1
      FOUND = .TRUE.
      IOR = M%IJKW(4,IW)
      SELECT CASE(IOR)
         CASE( 1)
            IMIN=MAX(IMIN,M%IJKW(10,IW)-1)
         CASE(-1) 
            IMAX=MIN(IMAX,M%IJKW(10,IW))
         CASE( 2) 
            JMIN=MAX(JMIN,M%IJKW(11,IW)-1)
         CASE(-2) 
            JMAX=MIN(JMAX,M%IJKW(11,IW))
         CASE( 3) 
            KMIN=MAX(KMIN,M%IJKW(12,IW)-1)
         CASE(-3) 
            KMAX=MIN(KMAX,M%IJKW(12,IW))
      END SELECT
   ENDDO SEARCH_LOOP
!
   IF ( M2%XS>=M%XS .AND. M2%XF<=M%XF .AND. M2%YS>=M%YS .AND. M2%YF<=M%YF .AND. &
         M2%ZS>=M%ZS .AND. M2%ZF<=M%ZF ) FOUND = .TRUE.
!
   IF (.NOT.FOUND) CYCLE OTHER_MESH_LOOP
!
   I_MIN(NOM,NM) = IMIN
   I_MAX(NOM,NM) = IMAX
   J_MIN(NOM,NM) = JMIN
   J_MAX(NOM,NM) = JMAX
   K_MIN(NOM,NM) = KMIN
   K_MAX(NOM,NM) = KMAX
!
   ALLOCATE(M%OMESH(NOM)% TMP(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   ALLOCATE(M%OMESH(NOM)%   H(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   ALLOCATE(M%OMESH(NOM)%   U(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   ALLOCATE(M%OMESH(NOM)%   V(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   ALLOCATE(M%OMESH(NOM)%   W(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   ALLOCATE(M%OMESH(NOM)% FVX(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   ALLOCATE(M%OMESH(NOM)% FVY(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   ALLOCATE(M%OMESH(NOM)% FVZ(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX))
   IF (N_SPECIES>0) THEN
      ALLOCATE(M%OMESH(NOM)%  YY(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX,N_SPECIES))
      ALLOCATE(M%OMESH(NOM)% YYS(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX,N_SPECIES))
   ENDIF
!
!     Wall arrays
!
   ALLOCATE(M%OMESH(NOM)%BOUNDARY_TYPE(0:M2%NEWC))
   M%OMESH(NOM)%BOUNDARY_TYPE(0:M2%NEWC) = M2%BOUNDARY_TYPE(0:M2%NEWC)
   ALLOCATE(M%OMESH(NOM)%IJKW(12,M2%NEWC))
   M%OMESH(NOM)%IJKW(1:12,1:M2%NEWC) = M2%IJKW(1:12,1:M2%NEWC)
   !
   ALLOCATE(M%OMESH(NOM)%WALL(0:M2%NEWC))
!
!     Particle and Droplet Orphan Arrays
!
   IF (DROPLET_FILE) THEN
      M%OMESH(NOM)%N_DROP_ORPHANS = 0
      M%OMESH(NOM)%N_DROP_ORPHANS_DIM = 1000
      ALLOCATE(M%OMESH(NOM)%DROPLET(M%OMESH(NOM)%N_DROP_ORPHANS_DIM),STAT=IZERO)
      CALL ChkMemErr('INIT','DROPLET',IZERO)
   ENDIF
!
ENDDO OTHER_MESH_LOOP
!
END SUBROUTINE INITIALIZE_MESH_EXCHANGE
 
 

SUBROUTINE DOUBLE_CHECK(NM)
 
! Double check exchange pairs
 
INTEGER NOM
INTEGER, INTENT(IN) :: NM
TYPE (MESH_TYPE), POINTER :: M2,M
 
M=>MESHES(NM)
 
OTHER_MESH_LOOP: DO NOM=1,NMESHES
   IF (NOM==NM) CYCLE OTHER_MESH_LOOP
   IF (NIC(NM,NOM)==0 .AND. NIC(NOM,NM)>0) THEN
      M2=>MESHES(NOM)
      ALLOCATE(M%OMESH(NOM)%IJKW(12,M2%NEWC))
      ALLOCATE(M%OMESH(NOM)%BOUNDARY_TYPE(0:M2%NEWC))
      ALLOCATE(M%OMESH(NOM)%WALL(0:M2%NEWC))
   ENDIF
ENDDO OTHER_MESH_LOOP
 
END SUBROUTINE DOUBLE_CHECK
 
 
SUBROUTINE MESH_EXCHANGE(CODE)
USE RADCONS, ONLY :NSB,NRA 
! Exchange Information between Meshes
REAL(EB) :: TNOW 
INTEGER, INTENT(IN) :: CODE
INTEGER :: NM
 
TNOW = SECOND()
 
MESH_LOOP: DO NM=1,NMESHES
   OTHER_MESH_LOOP: DO NOM=1,NMESHES
 
      IF (CODE==0 .AND. NIC(NOM,NM)<1 .AND. NIC(NM,NOM)>0 .AND. I_MIN(NOM,NM)<0 .AND. RADIATION) THEN
         M =>MESHES(NM)
         M2=>MESHES(NOM)%OMESH(NM)
         DO IW=1,M%NEWC
            IF (M%IJKW(9,IW)==NOM) THEN
               ALLOCATE(M2%WALL(IW)%ILW(NRA,NSB))
               M2%WALL(IW)%ILW = SIGMA*TMPA4*RPI
            ENDIF
         ENDDO
      ENDIF
 
      IF (NIC(NOM,NM)==0 .AND. NIC(NM,NOM)==0) CYCLE OTHER_MESH_LOOP
      IF (CODE>0) THEN
      IF (.NOT.ACTIVE_MESH(NM) .OR. .NOT.ACTIVE_MESH(NOM)) CYCLE OTHER_MESH_LOOP
      ENDIF
      IF (DEBUG) WRITE(0,*) NOM,' receiving data from ',NM,' code=',CODE
 
      M =>MESHES(NM)
      M2=>MESHES(NOM)%OMESH(NM)
      M3=>MESHES(NM)%OMESH(NOM)
      M4=>MESHES(NOM)
 
      IMIN = I_MIN(NOM,NM)
      IMAX = I_MAX(NOM,NM)
      JMIN = J_MIN(NOM,NM)
      JMAX = J_MAX(NOM,NM)
      KMIN = K_MIN(NOM,NM)
      KMAX = K_MAX(NOM,NM)
 
      INITIALIZE_IF: IF (CODE==0 .AND. RADIATION) THEN
         DO IW=1,M%NEWC
         IF (M%IJKW(9,IW)==NOM) THEN
            ALLOCATE(M2%WALL(IW)%ILW(NRA,NSB))
            M2%WALL(IW)%ILW = SIGMA*TMPA4*RPI
            ENDIF
         ENDDO
      ENDIF INITIALIZE_IF
 
      PREDICTOR_IF: IF (CODE==1 .AND. NIC(NOM,NM)>0) THEN
         M2%TMP(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)= M%TMP(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
         M2%H(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)= M%H(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
         IF (N_SPECIES>0) M2%YYS(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX,1:N_SPECIES)= M%YYS(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX,1:N_SPECIES)
      ENDIF PREDICTOR_IF
 
      CORRECTOR_IF: IF (CODE==0 .OR. CODE==2) THEN
         IF (NIC(NOM,NM)>0) THEN
            M2%BOUNDARY_TYPE(0:M%NEWC) = M%BOUNDARY_TYPE(0:M%NEWC)
            M2%TMP(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)= M%TMP(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
            M2%H(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)=  M%H(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
            M2%U(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)=  M%U(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
            M2%V(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)=  M%V(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
            M2%W(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)=  M%W(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
            IF (N_SPECIES>0) M2%YY(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX,1:N_SPECIES)= M%YY(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX,1:N_SPECIES)
         ENDIF
         RADIATION_IF: IF (RADIATION .AND. CODE==2 .AND. NIC(NOM,NM)>0) THEN
            DO IW=1,M4%NEWC
               IF (M4%IJKW(9,IW)==NM .AND. M4%BOUNDARY_TYPE(IW)==INTERPOLATED_BOUNDARY)  &
                  M4%WALL(IW)%ILW(1:NRA,1:NSB) = M3%WALL(IW)%ILW(1:NRA,1:NSB)
            ENDDO
         ENDIF RADIATION_IF
      ENDIF CORRECTOR_IF
 
! Get Number of Droplet Orphans
 
      IF (DROPLET_FILE) THEN 
         M2%N_DROP_ADOPT = MIN(M3%N_DROP_ORPHANS,N_DROP_ADOPT_MAX)
         IF (M4%NLP+M2%N_DROP_ADOPT>M4%NLPDIM) CALL RE_ALLOCATE_DROPLETS(1,NOM,0)
      ENDIF
 
! Sending/Receiving Droplet Buffer Arrays
 
      IF_DROPLETS: IF (DROPLET_FILE) THEN 
         IF_DROPLETS_SENT: IF (M2%N_DROP_ADOPT>0) THEN
            M4%DROPLET(M4%NLP+1:M4%NLP+M2%N_DROP_ADOPT)=  M3%DROPLET(1:M2%N_DROP_ADOPT) 
            M4%NLP = M4%NLP + M2%N_DROP_ADOPT
            M3%N_DROP_ORPHANS = 0
         ENDIF IF_DROPLETS_SENT
      ENDIF IF_DROPLETS
 
   ENDDO OTHER_MESH_LOOP
ENDDO MESH_LOOP
 
TUSED(11,:)=TUSED(11,:) + SECOND() - TNOW
END SUBROUTINE MESH_EXCHANGE
 
SUBROUTINE EXCHANGE_DIAGNOSTICS
 
INTEGER  :: NM,NECYC,I
REAL(EB) :: T_SUM,TNOW
 
TNOW = SECOND()
 
MESH_LOOP: DO NM=1,NMESHES
   T_SUM = 0.
   SUM_LOOP: DO I=2,N_TIMERS
      IF (I==9 .OR. I==10) CYCLE SUM_LOOP
      T_SUM = T_SUM + TUSED(I,NM)
   ENDDO SUM_LOOP
   NECYC          = MAX(1,NTCYC(NM)-NCYC(NM))
   T_PER_STEP(NM) = (T_SUM-T_ACCUM(NM))/REAL(NECYC,EB)
   T_ACCUM(NM)    = T_SUM
   NCYC(NM)       = NTCYC(NM)
ENDDO MESH_LOOP
 
TUSED(11,:) = TUSED(11,:) + SECOND() - TNOW
END SUBROUTINE EXCHANGE_DIAGNOSTICS
 

SUBROUTINE CORRECT_PRESSURE
 
REAL(EB) :: A(NCGC,NCGC),B(NCGC),C(NMESHES),AA(NMESHES,NMESHES)
TYPE (MESH_TYPE), POINTER :: M
TYPE (OMESH_TYPE), POINTER :: OM
INTEGER :: IERROR,NM
REAL(EB)::SUM1,SUM4,SUM,SUM41,SUM14,SUM23,SUM32,SUM13,SUM31, &
SUM25,SUM52,SUM36,SUM63,SUM12,SUM21,SUM34,SUM43,SUM15,SUM51
 
MESH_LOOP_1: DO NM=1,NMESHES
   OTHER_MESH_LOOP: DO NOM=1,NMESHES
      IF (NIC(NOM,NM)==0 .AND. NIC(NM,NOM)==0) CYCLE OTHER_MESH_LOOP
      M =>MESHES(NM)
      OM=>MESHES(NOM)%OMESH(NM)
      IMIN = I_MIN(NOM,NM)
      IMAX = I_MAX(NOM,NM)
      JMIN = J_MIN(NOM,NM)
      JMAX = J_MAX(NOM,NM)
      KMIN = K_MIN(NOM,NM)
      KMAX = K_MAX(NOM,NM)
!
      OM%H(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)= M%H(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
      OM%FVX(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)= M%FVX(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
      OM%FVY(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)= M%FVY(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
      OM%FVZ(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)= M%FVZ(IMIN:IMAX,JMIN:JMAX,KMIN:KMAX)
!
   ENDDO OTHER_MESH_LOOP
ENDDO MESH_LOOP_1
!
A = 0._EB
B = 0._EB
!
MESH_LOOP_2: DO NM=1,NMESHES
   CALL COMPUTE_A_B(A,B,NM)
ENDDO MESH_LOOP_2
!
!     DO I=1,NCGC
!     WRITE(0,'(16F6.2,3X,E12.5)') (A(I,J),J=1,NCGC),B(I)
!     ENDDO
!
CALL GAUSSJ(A,NCGC,NCGC,B,1,1,IERROR)
!
IF (IERROR>0) WRITE(0,*) ' COMPUTE B IERROR= ',IERROR
!     WRITE(0,*) 
!     DO I=1,NCGC
!     WRITE(0,'(E12.5)') B(I)
!     ENDDO
!
MESH_LOOP_3: DO NM=1,NMESHES
CALL COMPUTE_CORRECTION_PRESSURE(B,NM)
ENDDO MESH_LOOP_3
!
AA = 0._EB
C = 0._EB
!
MESH_LOOP_4: DO NM=1,NMESHES
   CALL COMPUTE_C(AA,C,NM)
ENDDO MESH_LOOP_4
!
!IF (ALL(SEALED)) THEN
!   AA(1,:) = 0._EB
!   AA(1,1) = 1._EB
!   C(1)   = 0._EB
!ENDIF
!
!     DO I=1,NMESHES
!     WRITE(0,'(9E12.5,3X,E12.5)') (A(I,J),J=1,NMESHES),C(I)
!     ENDDO
!
CALL GAUSSJ(AA,NMESHES,NMESHES,C,1,1,IERROR)
IF (IERROR>0) WRITE(0,*) ' COMPUTE_C IERROR= ',IERROR
!     DO I=1,NMESHES
!     WRITE(0,'(E12.5)') C(I)
!     ENDDO
!
MESH_LOOP_5: DO NM=1,NMESHES
   CALL UPDATE_PRESSURE(C,NM)
ENDDO MESH_LOOP_5
!
SUM=0._EB
SUM1=0._EB
SUM4=0._EB
SUM14=0._EB
SUM41=0._EB
SUM23=0._EB
SUM32=0._EB
SUM25=0._EB
SUM52=0._EB
SUM36=0._EB
SUM63=0._EB
SUM12=0._EB
SUM13=0._EB
SUM31=0._EB
SUM21=0._EB
SUM34=0._EB
SUM32=0._EB
SUM43=0._EB
SUM15=0._EB
SUM51=0._EB

!DO K=1,20
!SUM12=SUM12+MESHES(1)%DZ(K)*MESHES(1)%DY(1)*MESHES(1)%U(75,1,K)
!SUM21=SUM21+MESHES(2)%DZ(K)*MESHES(2)%DY(1)*MESHES(2)%U( 0,1,K)
!SUM23=SUM23+MESHES(2)%DZ(K)*MESHES(2)%DY(1)*MESHES(2)%U(75,1,K)
!SUM32=SUM32+MESHES(3)%DZ(K)*MESHES(3)%DY(1)*MESHES(3)%U( 0,1,K)
!SUM34=SUM34+MESHES(3)%DZ(K)*MESHES(3)%DY(1)*MESHES(3)%U(75,1,K)
!SUM43=SUM43+MESHES(4)%DZ(K)*MESHES(4)%DY(1)*MESHES(4)%U( 0,1,K)
!ENDDO
!
!     WRITE(0,*) 'SUM12=',SUM12,' SUM21=',SUM21
!     WRITE(0,*) 'SUM23=',SUM23,' SUM32=',SUM32
!    IF (CORRECTOR) THEN
!    WRITE(0,*) MESHES(4)%U(0,1, 1),MESHES(4)%W(1,1, 0)
!    WRITE(0,*) MESHES(3)%U(0,1,10),MESHES(3)%W(1,1,10)
!    WRITE(0,*)
!    ENDIF
!
END SUBROUTINE CORRECT_PRESSURE

SUBROUTINE WRITE_STRINGS
 
! Write character strings out to the .smv file

INTEGER :: N,NM
 
MESH_LOOP: DO NM=1,NMESHES
   DO N=1,MESHES(NM)%N_STRINGS
      WRITE(LU4,'(A)') TRIM(MESHES(NM)%STRING(N))
   ENDDO
   MESHES(NM)%N_STRINGS = 0
ENDDO MESH_LOOP
 
END SUBROUTINE WRITE_STRINGS

SUBROUTINE DUMP_GLOBAL_OUTPUTS(T)
USE COMP_FUNCTIONS, ONLY :SECOND
REAL(EB), INTENT(IN) :: T
REAL(EB) :: TNOW

TNOW = SECOND()

! Dump out HRR info

IF (T>=HRR_CLOCK .AND. MINVAL(HRR_COUNT,MASK=.NOT.EVACUATION_ONLY)>0._EB) THEN
   CALL DUMP_HRR(T)
   HRR_CLOCK = HRR_CLOCK + DT_HRR
   HRR_SUM   = 0.
   RHRR_SUM  = 0.
   CHRR_SUM  = 0.
   FHRR_SUM  = 0.
   MLR_SUM   = 0.
   HRR_COUNT = 0.
ENDIF

! Dump out Evac info

CALL EVAC_CSV(T)

! Dump out Mass info

IF (T>=MINT_CLOCK .AND. MINVAL(MINT_COUNT,MASK=.NOT.EVACUATION_ONLY)>0._EB) THEN
   CALL DUMP_MASS(T)
   MINT_CLOCK = MINT_CLOCK + DT_MASS
   MINT_SUM   = 0._EB
   MINT_COUNT = 0._EB
ENDIF

! Dump out DEViCe data

IF (T >= DEVC_CLOCK) THEN
   IF (MINVAL(DEVICE(1:N_DEVC)%COUNT)/=0) THEN
      CALL DUMP_DEVICES(T)
      DEVC_CLOCK = DEVC_CLOCK + DT_DEVC
      DEVICE(1:N_DEVC)%VALUE = 0.
      DEVICE(1:N_DEVC)%COUNT = 0
   ENDIF
ENDIF

! Dump out ConTRoL data

IF (T >= CTRL_CLOCK) THEN
   CALL DUMP_CONTROLS(T)
   CTRL_CLOCK = CTRL_CLOCK + DT_CTRL
ENDIF

TUSED(7,1) = TUSED(7,1) + SECOND() - TNOW
   
END SUBROUTINE DUMP_GLOBAL_OUTPUTS

SUBROUTINE EVAC_READ_DATA
Implicit None
!
! Read input for EVACUATION routines
!
IF (.Not. ANY(EVACUATION_GRID)) N_EVAC = 0
IF (ANY(EVACUATION_GRID)) CALL READ_EVAC

END SUBROUTINE EVAC_READ_DATA

SUBROUTINE INITIALIZE_EVAC(NM)
Implicit None
!
! Initialize evacuation meshes
!
INTEGER, INTENT(IN) :: NM
!
IF (ANY(EVACUATION_GRID)) CALL INITIALIZE_EVACUATION(NM,ISTOP(NM))
! IF (EVACUATION_ONLY(NM)) T(NM) = -EVAC_DT_FLOWFIELD*EVAC_TIME_ITERATIONS
IF (EVACUATION_GRID(NM)) PART_CLOCK(NM) = T_EVAC + DT_PART
IF (EVACUATION_GRID(NM)) CALL DUMP_EVAC(T_EVAC,NM)
IF (ANY(EVACUATION_GRID)) ICYC = -EVAC_TIME_ITERATIONS

END SUBROUTINE INITIALIZE_EVAC

SUBROUTINE INIT_EVAC_DUMPS
Implicit None
!
! Initialize evacuation dumps
!
T_EVAC  = - EVAC_DT_FLOWFIELD*EVAC_TIME_ITERATIONS
T_EVAC_SAVE = T_EVAC
IF (ANY(EVACUATION_GRID)) CALL INITIALIZE_EVAC_DUMPS

END SUBROUTINE INIT_EVAC_DUMPS

SUBROUTINE EVAC_CSV(T)
Implicit None
REAL(EB), INTENT(IN) :: T
!
! Dump out Evac info
!
IF (T>=EVAC_CLOCK .AND. ANY(EVACUATION_GRID)) THEN
   CALL DUMP_EVAC_CSV(T)
   EVAC_CLOCK = EVAC_CLOCK + DT_HRR
ENDIF

END SUBROUTINE EVAC_CSV

SUBROUTINE EVAC_EXCHANGE
Implicit None
!
! Fire mesh information ==> Evac meshes
!
IF (.NOT.ANY(EVACUATION_GRID)) RETURN
IF (ANY(EVACUATION_GRID)) CALL EVAC_MESH_EXCHANGE(T_EVAC,T_EVAC_SAVE,I_EVAC,ICYC)

END SUBROUTINE EVAC_EXCHANGE

SUBROUTINE EVAC_PRESSURE_LOOP(NM)
Implicit None
!
! Evacuation flow field calculation
!
INTEGER, INTENT(IN) :: NM
INTEGER :: N
!
IF (EVACUATION_ONLY(NM)) THEN
   PRESSURE_ITERATION_LOOP: DO N=1,EVAC_PRESSURE_ITERATIONS
      CALL NO_FLUX
      CALL PRESSURE_SOLVER(NM)
   ENDDO PRESSURE_ITERATION_LOOP
END IF

END SUBROUTINE EVAC_PRESSURE_LOOP

SUBROUTINE EVAC_MAIN_LOOP
Implicit None
!
! Call evacuation routine and adjust time steps for evac meshes
!
REAL(EB) :: T_FIRE, FIRE_DT
!
IF (.NOT.ANY(EVACUATION_GRID)) RETURN
!
IF (ANY(EVACUATION_ONLY).AND.(ICYC <= 0)) ACTIVE_MESH = .FALSE.
EVAC_DT = EVAC_DT_STEADY_STATE
IF (ICYC < 1) EVAC_DT = EVAC_DT_FLOWFIELD
T_FIRE = T_EVAC + EVAC_DT
IF (ICYC > 0) THEN
   IF (.NOT.ALL(EVACUATION_ONLY)) THEN
      T_FIRE = MINVAL(T,MASK= (.NOT.EVACUATION_ONLY).AND.ACTIVE_MESH)
      DTNEXT_SYNC(1:NMESHES) = MESHES(1:NMESHES)%DTNEXT
      FIRE_DT = MINVAL(DTNEXT_SYNC,MASK= (.NOT.EVACUATION_ONLY).AND.ACTIVE_MESH)
      T_FIRE = T_FIRE + FIRE_DT
   ENDIF
ENDIF
EVAC_TIME_STEP_LOOP: DO WHILE (T_EVAC < T_FIRE)
   T_EVAC = T_EVAC + EVAC_DT
   DO NM=1,NMESHES
      IF (EVACUATION_ONLY(NM)) THEN
         ACTIVE_MESH(NM) = .FALSE.
         CHANGE_TIME_STEP(NM) = .FALSE.
         MESHES(NM)%DT     = EVAC_DT
         MESHES(NM)%DTNEXT = EVAC_DT
         T(NM)  = T_EVAC
         IF (ICYC <= 1 .And. .Not. BTEST(I_EVAC,2) ) THEN
            IF (ICYC <= 0) ACTIVE_MESH(NM) = .TRUE.
            IF (ICYC <= 0) T(NM) = T_EVAC + EVAC_DT_FLOWFIELD*EVAC_TIME_ITERATIONS - EVAC_DT
         ENDIF
         IF (EVACUATION_GRID(NM) ) THEN
            CALL EVACUATE_HUMANS(T_EVAC,NM,ICYC)
            IF (T_EVAC >= PART_CLOCK(NM)) THEN
               CALL DUMP_EVAC(T_EVAC,NM)
               DO
                  PART_CLOCK(NM) = PART_CLOCK(NM) + DT_PART
                  IF (PART_CLOCK(NM) >= T_EVAC) EXIT
               ENDDO
            ENDIF
         ENDIF
      ENDIF
   ENDDO
   IF (ICYC < 1) EXIT EVAC_TIME_STEP_LOOP
ENDDO EVAC_TIME_STEP_LOOP

END SUBROUTINE EVAC_MAIN_LOOP

END PROGRAM FDS
