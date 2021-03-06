module model_mod

    use HRMC_Global  ! Global variables
    implicit none
    ! Derived data type for the hutches. at is a pointer to a list of the indices
    ! of the atoms in this hutch. nat is the number of atoms in this hutch.
    type hutch
        integer, dimension(:), allocatable :: at
        integer :: nat = 0
    end type hutch

    ! Derived data type for the hutch array: contains an array of hutches,
    ! plus supporting information
    type hutch_array
        ! array of hutch objects
        type(hutch), dimension(:,:,:), pointer :: h
        ! number of hutches in x, y, and z
        integer :: nhutch_x, nhutch_y, nhutch_z
        ! physical size of a hutch in Angstroms
        double precision :: hutch_size
        ! list of the hutch indices for every atom
        integer, pointer, dimension(:,:) :: atom_hutch
    end type hutch_array

    ! adjustable-size list of atom indices
    type index_list
        integer :: nat
        integer, allocatable, dimension(:) :: ind
    end type index_list

    type dble_index_list
        integer :: nat
        double precision, allocatable, dimension(:) :: ind
    end type dble_index_list


    ! Defined type for a structural model with atoms positions and a bunch of metadata
    type model
        integer :: id  ! model ID - ranges from 1 to nrot for those in rotated matrix; is 0 for the original m
        integer :: natoms  ! number of atoms in the model
        logical :: rotated  ! TRUE if model has been rotated, FALSE otherwise
        integer :: unrot_natoms  ! # of atoms in the unrotated model (can be different than natoms)
        double precision :: lx, ly, lz  ! box size, in Angstroms
        type(dble_index_list) :: xx, yy, zz  ! atom positions in Angstroms
        type(index_list) :: znum, znum_r  ! atom atomic numbers, and reduced z numbners
        integer :: nelements ! # of elements in the model
        integer, allocatable, dimension(:) :: atom_type ! array listing atomic numbers present
        type(hutch_array) :: ha  ! hutch data structure
        ! 'rot_i' is a list of which atoms in the rotated model correspond to the index i in the unrotated model
        type(index_list), dimension(:), allocatable :: rot_i
    end type model

contains

    subroutine check_for_error(istat, message)
        integer, intent(in) :: istat
        character(len=*), intent(in) :: message
        if (istat /= 0) then
            write (0,*) message
            return
        endif
    end subroutine check_for_error


    subroutine read_model(model_filename, m, istat)
        implicit none
        character (len=*),intent(in) :: model_filename
        type(model), intent(out) :: m
        integer, intent(out) :: istat      !0 for successful open, others for failure.
        integer :: i, j, atom_temp
        integer, dimension(103) :: elements=0
        character(3) :: sym
        character(3), dimension(118) :: syms

        syms = (/ "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne", "Na",  &
        "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca", "Sc", "Ti", "V",    &
        "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Ga", "Ge", "As", "Se", "Br",&
        "Kr", "Rb", "Sr", "Y", "Zr", "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", &
        "Cd", "In", "Sn", "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", &
        "Nd", "Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb", "Lu",&
        "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg", "Tl", "Pb", "Bi", &
        "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu", "Am", &
        "Cm", "Bk", "Cf", "Es", "Fm", "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh",&
        "Hs", "Mt", "Ds", "Rg", "Cn", "Uut", "Fl", "Uup", "Lv", "Uus", "Uuo" /)

        ! Set model ID to 0.
        m%id = 0

        ! Open file that contains the model information.
        open(1,file=trim(model_filename),iostat=istat,status='old')
        call check_for_error(istat, "Error in opening flie, "//model_filename)

        read(1,*) m%natoms
        read(1,*) m%lx,m%ly,m%lz

        ! Set the number of atoms in the model m and allocate space for each coordinate.
        ! Allocate the model to twice its necessary size so that we never have to reallocate ever.
        ! Note that when an atom gets rotated, it can get rotated in twice.
        allocate(m%xx%ind(m%natoms*2), m%yy%ind(m%natoms*2), m%zz%ind(m%natoms*2), m%znum%ind(m%natoms*2), stat=istat)
        m%xx%nat = m%natoms
        m%yy%nat = m%natoms
        m%zz%nat = m%natoms
        m%znum%nat = m%natoms
        m%znum_r%nat = m%natoms
        call check_for_error(istat, 'Unable to allocate memory for the model being read.')

        ! If the model is not a perfect cube then the rest of the calculations
        ! wont work, so we really should check that.
        if((m%lx /= m%ly) .or. (m%lx /= m%lz)) then
            write(0,*) "ERROR! The model is not a cube and will work correctly. Exiting."
            stop
        endif
        ! Read the atomic numbers and atom positions directly into the model.
        do i=1,m%natoms
            read(1,*) sym,m%xx%ind(i),m%yy%ind(i),m%zz%ind(i)
            do j=1,118
                if(sym .eq. syms(j)) m%znum%ind(i) = j
            enddo
            ! If this atom has atomic number z, then increment the z position in
            ! the array elements. This counts the number of each atom type we have.
            elements(m%znum%ind(i)) = elements(m%znum%ind(i)) + 1
        enddo
        close(1)

        ! Count the number of elements we have in our model.
        m%nelements=0
        do i=1, 103
            if(elements(i) /= 0) then
                m%nelements = m%nelements + 1
            end if
        end do

        ! Note: nelements is usually between 1 and 5 so these loops are tiny.
        ! Set m%atom_type to contain the atom types
        allocate(m%atom_type(m%nelements), stat=istat)
        call check_for_error(istat, 'Unable to allocate memory for m%atom_type.')
        ! i corresponds to the atomic number.
        ! j is the next open position in atom_type.
        j = 1
        do i=1, 103
            if(elements(i) /= 0) then
                ! If we reach a non-zero element in elements then there are
                ! atoms with atomic number i in the model. Append this atomc
                ! number to atom_types. Increment j to move to the next open spot.
                m%atom_type(j) = i
                j = j + 1
            end if
        end do

        ! Sort atom_type by increasing atomic order. (Insertion sort)
        do i=1, m%nelements
            do j=1, i
                if( m%atom_type(i) < m%atom_type(j) ) then
                    atom_temp = m%atom_type(i)
                    m%atom_type(i) = m%atom_type(j)
                    m%atom_type(j) = atom_temp
                end if
            end do
        end do

        ! For each atom i, add a parameter znum_r(i) that corresponds to
        ! m%atom_type for fast lookup.
        allocate(m%znum_r%ind(m%natoms*2), stat=istat)
        call check_for_error(istat, 'Unable to allocate memory for m%znum_r.')
        m%znum_r%ind = 0.0
        do i=1, m%natoms
            do j=1, m%nelements
                if(m%znum%ind(i) .eq. m%atom_type(j)) then
                    m%znum_r%ind(i) = j
                end if
            end do
        end do

        m%rotated = .FALSE.

        call check_model(m,istat)

        ! Calls hutch_position and hutch_add_atom in loops.
        ! It also does some allocation.
        call model_init_hutches(m)
    end subroutine read_model


    subroutine recenter_model(xc, yc, zc, m)
    ! Shifts the atom positions in model m so that the mid-point between the maximum and
    ! and minimum atom positions in each dimensions sits at the position (xc, yc, zc),
    ! measured in units of the model supercell.
        double precision, intent(in) :: xc, yc, zc
        type(model), intent(inout) :: m
        double precision :: xshift, yshift, zshift
        xshift = xc*m%lx - (maxval(m%xx%ind(1:m%natoms)) + minval(m%xx%ind(1:m%natoms)))/2.0
        yshift = yc*m%ly - (maxval(m%yy%ind(1:m%natoms)) + minval(m%yy%ind(1:m%natoms)))/2.0
        zshift = zc*m%lz - (maxval(m%zz%ind(1:m%natoms)) + minval(m%zz%ind(1:m%natoms)))/2.0

        m%xx%ind = m%xx%ind+xshift
        m%yy%ind = m%yy%ind+yshift
        m%zz%ind = m%zz%ind+zshift
    end subroutine recenter_model


    subroutine check_model(m, istat)
    ! simple error checking on a model.  Currently checks: are all the  
    ! atoms in the box?  Are all the atomic numbers between 1 and 103
    ! (the range for which Kirkland calculated electron scattering factors)
    ! Never called within HRMC.
        type(model), intent(in) :: m 
        integer, intent(out) :: istat
        double precision xlen, ylen, zlen 
        istat = 0

        xlen = maxval(m%xx%ind(1:m%natoms)) - minval(m%xx%ind(1:m%natoms))
        ylen = maxval(m%yy%ind(1:m%natoms)) - minval(m%yy%ind(1:m%natoms))
        zlen = maxval(m%zz%ind(1:m%natoms)) - minval(m%zz%ind(1:m%natoms))

        if ( xlen > m%lx ) then 
            write (*,*) 'Maximum x distance of ',xlen,' Ang exceeds box size ',m%lx,' Ang.'
            istat = 1
        end if

        if ( ylen > m%ly ) then 
            write (*,*) 'Maximum y distance of ',ylen,' Ang exceeds box size ',m%ly,' Ang.'
            istat = 1
        end if

        if ( zlen > m%lz ) then 
            write (*,*) 'Maximum z distance of ',zlen,' Ang exceeds box size ',m%lz,' Ang.'
            istat = 1
        end if

        if (minval(m%znum%ind(1:m%znum%nat)) < 1) then 
            write (*,*) 'Minimum atomic number of ', minval(m%znum%ind, 1), 'is less than 1.'
            istat = 1
        end if

        if (maxval(m%znum%ind(1:m%znum%nat)) > 103) then 
            write (*,*) 'Maximum atomic number of ', maxval(m%znum%ind, 1), 'is greater than 103.'
            istat = 1
        end if
    end subroutine check_model

    subroutine rotate_atom(phi, psi, theta, min, mrot, istat)
        ! Rotates model min by angles phi, psi, theta and puts the results in mrot. min is unchanged.
        ! min should be a single atom model.
        double precision, intent(in) :: theta, phi, psi
        type(model), intent(in) :: min
        type(model), intent(inout) :: mrot 
        integer, intent(out) :: istat
        double precision, dimension(3,3) :: r                         ! rotation matrix
        double precision :: cpsi, cphi, ctheta, sphi, spsi, stheta    ! sines and cosines of the angles
        integer :: i, j                                   ! loop counters
        double precision :: x, y, z                                   ! temporary positions
        double precision :: lx2, ly2, lz2                             ! half box sizes
        type(model) :: mt                                 ! temporary oversize model
        
        ! periodic continue mt to 3x3x3 of the original model
        istat = 0
        call periodic_continue_model(3, 3, 3, min, mt, .FALSE., istat)
        if (istat /= 0) return

        ! generate the members of a 3x3 rotation matrix.  Use the Goldstein "x-convention"
        ! and Euler angles phi theta, psi.
        !write(*,*) "Rotation angles:", phi, psi, theta
        cpsi = cos(psi)
        cphi = cos(phi)
        ctheta = cos(theta)
        sphi = sin(phi)
        spsi = sin(psi)
        stheta = sin(theta)

        r(1,1) = cpsi
        r(1,2) = spsi
        r(1,3) = 0.0
        r(2,1) = -ctheta*spsi
        r(2,2) = ctheta*cpsi
        r(2,3) = stheta
        r(3,1) = stheta*spsi
        r(3,2) = -stheta*cpsi
        r(3,3) = ctheta

        ! Rotate the position vectors in mt (the temporary 3x3x3 model).
        do i=1,mt%natoms
            if(abs(mt%xx%ind(i)).le.1.2*sqrt(2.0)*min%lx/2)then
                if(abs(mt%yy%ind(i)).le.1.2*sqrt(2.0)*min%ly/2)then
                    if(abs(mt%zz%ind(i)).le.1.2*sqrt(2.0)*min%lz/2)then
                        x = mt%xx%ind(i)*r(1,1) + mt%yy%ind(i)*r(1,2) + mt%zz%ind(i)*r(1,3)
                        y = mt%xx%ind(i)*r(2,1) + mt%yy%ind(i)*r(2,2) + mt%zz%ind(i)*r(2,3)
                        z = mt%xx%ind(i)*r(3,1) + mt%yy%ind(i)*r(3,2) + mt%zz%ind(i)*r(3,3)
                        mt%xx%ind(i) = x
                        mt%yy%ind(i) = y
                        mt%zz%ind(i) = z
                    endif
                endif
            endif
        end do

        ! Cut the temporary model back to the original box size.
        ! First count the atoms in the box.
        mrot%natoms = 0
        lx2 = min%lx / 2.0
        ly2 = min%ly / 2.0
        lz2 = min%lz / 2.0
        do i=1, mt%natoms
            if((mt%xx%ind(i) <= lx2 .AND. mt%xx%ind(i) >= -1.0*lx2) .and. &
               (mt%yy%ind(i) <= ly2 .AND. mt%yy%ind(i) >= -1.0*ly2) .and. &
               (mt%zz%ind(i) <= lz2 .AND. mt%zz%ind(i) >= -1.0*lz2)) then
                mrot%natoms = mrot%natoms + 1
            endif
        enddo

        mrot%unrot_natoms = min%natoms ! Better always be 1
        mrot%xx%nat = mrot%natoms
        mrot%yy%nat = mrot%natoms
        mrot%zz%nat = mrot%natoms
        mrot%znum%nat = mrot%natoms
        mrot%znum_r%nat = mrot%natoms

        ! now copy just the atoms inside the original box size 
        ! from the temp model to the rotated one.
        j=1
        do i=1, mt%natoms
            if (mt%xx%ind(i) <= lx2 .AND. mt%xx%ind(i) >= -1.0*lx2) then
                if (mt%yy%ind(i) <= ly2 .AND. mt%yy%ind(i) >= -1.0*ly2) then
                    if (mt%zz%ind(i) <= lz2 .AND. mt%zz%ind(i) >= -1.0*lz2) then
                        mrot%xx%ind(j) = mt%xx%ind(i)
                        mrot%yy%ind(j) = mt%yy%ind(i)
                        mrot%zz%ind(j) = mt%zz%ind(i)
                        mrot%znum%ind(j) = mt%znum%ind(i)
                        mrot%znum_r%ind(j) = mt%znum_r%ind(i)
                        j = j+1
                    endif
                endif
            endif
        enddo

        ! Release the memory allocated to mt
        deallocate(mt%atom_type)
        deallocate(mt%znum%ind,mt%znum_r%ind, mt%xx%ind, mt%yy%ind, mt%zz%ind)
    end subroutine rotate_atom

    subroutine rotate_model(phi, psi, theta, min, mrot, istat)
        ! Rotates model min by angles phi, psi, theta and puts the results in mrot. min is unchanged.
        double precision, intent(in) :: theta, phi, psi
        type(model), intent(in) :: min
        type(model), intent(out) :: mrot 
        integer, intent(out) :: istat
        double precision, dimension(3,3) :: r                         ! rotation matrix
        double precision :: cpsi, cphi, ctheta, sphi, spsi, stheta    ! sines and cosines of the angles
        integer :: i, j                                   ! loop counters
        double precision :: x, y, z                                   ! temporary positions
        double precision :: lx2, ly2, lz2                             ! half box sizes
        type(model) :: mt                                 ! temporary oversize model
        integer, dimension(:), allocatable :: orig_indices
        
        ! periodic continue mt to 3x3x3 of the original model
        istat = 0
        call periodic_continue_model(3, 3, 3, min, mt, .FALSE., istat)
        if (istat /= 0) return

        allocate(orig_indices(mt%natoms), stat=istat)
        orig_indices = (/ (mod(i,min%natoms)+1, i=0,mt%natoms-1) /)

        ! generate the members of a 3x3 rotation matrix.  Use the Goldstein "x-convention"
        ! and Euler angles phi theta, psi.
        ! write(*,*) "Rotation angles:", phi, psi, theta
        cpsi = cos(psi)
        cphi = cos(phi)
        ctheta = cos(theta)
        sphi = sin(phi)
        spsi = sin(psi)
        stheta = sin(theta)

        ! phi ignored
        r(1,1) = cpsi
        r(1,2) = spsi
        r(1,3) = 0.0
        r(2,1) = -ctheta*spsi
        r(2,2) = ctheta*cpsi
        r(2,3) = stheta
        r(3,1) = stheta*spsi
        r(3,2) = -stheta*cpsi
        r(3,3) = ctheta

        ! Rotate the position vectors in mt (the temporary 3x3x3 model).
        do i=1,mt%natoms
            if(abs(mt%xx%ind(i)).le.1.2*sqrt(2.0)*min%lx/2)then
                if(abs(mt%yy%ind(i)).le.1.2*sqrt(2.0)*min%ly/2)then
                    if(abs(mt%zz%ind(i)).le.1.2*sqrt(2.0)*min%lz/2)then
                        x = mt%xx%ind(i)*r(1,1) + mt%yy%ind(i)*r(1,2) + mt%zz%ind(i)*r(1,3)
                        y = mt%xx%ind(i)*r(2,1) + mt%yy%ind(i)*r(2,2) + mt%zz%ind(i)*r(2,3)
                        z = mt%xx%ind(i)*r(3,1) + mt%yy%ind(i)*r(3,2) + mt%zz%ind(i)*r(3,3)
                        mt%xx%ind(i) = x
                        mt%yy%ind(i) = y
                        mt%zz%ind(i) = z
                    endif
                endif
            endif
        end do

        ! Cut the temporary model back to the original box size.
        ! First count the atoms in the box.
        mrot%natoms = 0
        lx2 = min%lx / 2.0
        ly2 = min%ly / 2.0
        lz2 = min%lz / 2.0
        do i=1, mt%natoms
            if((mt%xx%ind(i) <= lx2 .AND. mt%xx%ind(i) >= -1.0*lx2) .and. &
               (mt%yy%ind(i) <= ly2 .AND. mt%yy%ind(i) >= -1.0*ly2) .and. &
               (mt%zz%ind(i) <= lz2 .AND. mt%zz%ind(i) >= -1.0*lz2)) then
                mrot%natoms = mrot%natoms + 1
            endif
        enddo

        mrot%nelements = min%nelements
        allocate(mrot%atom_type(mrot%nelements), stat=istat)
        call check_for_error(istat, 'Problem allocating memory in rotate_model.')
        mrot%atom_type = min%atom_type

        ! Allocate memory for the new atoms.
        mrot%unrot_natoms = min%natoms
        allocate(mrot%xx%ind(mrot%natoms*2), mrot%yy%ind(mrot%natoms*2), mrot%zz%ind(mrot%natoms*2), &
            mrot%znum%ind(mrot%natoms*2),  mrot%rot_i(mrot%unrot_natoms*2), mrot%znum_r%ind(mrot%natoms*2), stat=istat)
        call check_for_error(istat, 'Problem allocating memory in rotate_model.')
        mrot%xx%nat = mrot%natoms
        mrot%yy%nat = mrot%natoms
        mrot%zz%nat = mrot%natoms
        mrot%znum%nat = mrot%natoms
        mrot%znum_r%nat = mrot%natoms

        do i=1,mrot%unrot_natoms
           mrot%rot_i(i)%nat = 0
           if(allocated(mrot%rot_i(i)%ind)) deallocate(mrot%rot_i(i)%ind)
        enddo

        ! now copy just the atoms inside the original box size 
        ! from the temp model to the rotated one.
        j=1
        do i=1, mt%natoms
            if (mt%xx%ind(i) <= lx2 .AND. mt%xx%ind(i) >= -1.0*lx2) then
                if (mt%yy%ind(i) <= ly2 .AND. mt%yy%ind(i) >= -1.0*ly2) then
                    if (mt%zz%ind(i) <= lz2 .AND. mt%zz%ind(i) >= -1.0*lz2) then
                        mrot%xx%ind(j) = mt%xx%ind(i)
                        mrot%yy%ind(j) = mt%yy%ind(i)
                        mrot%zz%ind(j) = mt%zz%ind(i)
                        mrot%znum%ind(j) = mt%znum%ind(i)
                        mrot%znum_r%ind(j) = mt%znum_r%ind(i)
                        call add_index(mrot%rot_i(orig_indices(i)), j)
                        j = j+1
                    endif
                endif
            endif
        enddo

        ! Release the memory allocated to mt
        deallocate(mt%atom_type)
        deallocate(mt%znum%ind,mt%znum_r%ind, mt%xx%ind, mt%yy%ind, mt%zz%ind)

        ! Set the rest of of the rotated model paramters
        mrot%lx = min%lx
        mrot%ly = min%ly
        mrot%lz = min%lz
        mrot%rotated = .TRUE.
        mrot%unrot_natoms = min%natoms

        call model_init_hutches(mrot)

        if(allocated(orig_indices)) then
            deallocate(orig_indices)
        endif

        call check_model(mrot, istat)
    end subroutine rotate_model


    subroutine model_init_hutches(m)
    ! Initializes the hutch_array ha within the model m. It calcualtes the
    ! hutch_size (based on the model box size and the parameter
    ! ATOMS_PER_HUTCH) and the number of hutches in the array (nhutch_x, nhutch_y,
    ! and nhutch_z). It then assigns all the atoms in the current model atom
    ! position arrays xa, ya, and za to the appropriate hutches.  It does NOT
    ! check whether ha has already been initialized, so this routine should
    ! NEVER be called more than once for the same hutch_array.
        type(model), intent(inout) :: m
        integer :: istat, numhutches, hx, hy, hz, i
        ! Note: numhutches is not the total number of hutches, it is the number
        ! of hutches in each dimension. So numhutches^3 is the total.

        numhutches = anint( (m%natoms/ATOMS_PER_HUTCH)**(1./3.) )
        m%ha%hutch_size = m%lx / numhutches 
#ifdef DEBUG
        write (*,*) 'Hutch size is ',m%ha%hutch_size,' Angstroms.'
        write (*,*) 'Number of hutch in each dimension is: ', numhutches
#endif

        m%ha%nhutch_x = numhutches 
        m%ha%nhutch_y = numhutches 
        m%ha%nhutch_z = numhutches 

        allocate(m%ha%h(m%ha%nhutch_x, m%ha%nhutch_y, m%ha%nhutch_z), stat=istat)
        call check_for_error(istat, 'Cannot allocate memory for hutch algorithm.  Exiting.')

        allocate(m%ha%atom_hutch(m%natoms, 3), stat=istat)
        call check_for_error(istat, 'Cannot allocate memory for hutch algorithm.  Exiting.')

        m%ha%atom_hutch = 0

        ! These hutch atom arrays are allocated and initialized in
        ! hutch_add_atom. We just need to initialize them to empty 
        ! and nat to 0 so that we can add atoms to them correctly.
        do hx = 1, m%ha%nhutch_x
            do hy = 1, m%ha%nhutch_y
                do hz = 1, m%ha%nhutch_z
                    if(allocated(m%ha%h(hx,hy,hz)%at)) then
                        deallocate(m%ha%h(hx,hy,hz)%at)
                        m%ha%h(hx,hy,hz)%nat = 0
                    endif
                    m%ha%h(hx, hy, hz)%nat = 0
                end do
            end do
        end do

        ! Calculate which hutch each atom should be in and add it to that hutch.
        do i=1, m%natoms
            call hutch_position(m, m%xx%ind(i), m%yy%ind(i), m%zz%ind(i), hx, hy, hz)
            call hutch_add_atom(m, i, hx, hy, hz)
        end do
    end subroutine model_init_hutches


    subroutine hutch_position(m, xx, yy, zz, hx, hy, hz)
    ! Returns the indices of the hutch that encompasses position (xx, yy, zz) in
    ! the hutch_array in the integers (hx, hy, hz).  It assumes that the model 
    ! extends from -lx/2 to lx/2, -ly/2 to ly/2 and -lz/2 to lz/2 and does no
    ! error checking.
        type(model), intent(in) :: m 
        double precision, intent(in) :: xx, yy, zz
        integer, intent(out) :: hx, hy, hz

        ! This makes the range of hx, hy, and hz from 0 to nhutch_i, however
        ! the only time one of them will be 0 is if the position is exactly on
        ! the left edge. Thats what the next set of if statements is for: If 
        ! they are on an edge just move them a little bit over. Technically you 
        ! can get statistically more atoms in hutches on the 3 "left" edges but 
        ! it will happen extremely rarely so it wont matter. By the time we 
        ! are done hx, hy, and hz are restrained from 1 to nhutch_i so we can 
        ! convienently put them in an array.
        hx = mod(ceiling( (xx + 0.5*m%lx) / m%ha%hutch_size ), m%ha%nhutch_x+1)
        hy = mod(ceiling( (yy + 0.5*m%ly) / m%ha%hutch_size ), m%ha%nhutch_y+1)
        hz = mod(ceiling( (zz + 0.5*m%lz) / m%ha%hutch_size ), m%ha%nhutch_z+1)

        if (hx == 0) hx = 1
        if (hy == 0) hy = 1
        if (hz == 0) hz = 1
    end subroutine hutch_position


    subroutine periodic_continue_model(xp, yp, zp, min, mout, init_hutch, istat)
    ! Makes (xp, yp, zp) copies of the input model min and puts them in the output model
    ! mout.  Returns non-zero in istat is the memory can't be allocated.
        integer, intent(in):: xp, yp, zp
        type(model), intent(in) :: min
        type(model), intent(out) :: mout
        logical, intent(in) :: init_hutch
        integer, intent(out) :: istat
        integer :: i, j, k, c
        double precision :: shift_x, shift_y, shift_z

        mout%natoms = min%natoms*xp*yp*zp
        allocate(mout%xx%ind(mout%natoms), mout%yy%ind(mout%natoms), mout%zz%ind(mout%natoms), &
             mout%znum%ind(mout%natoms), mout%znum_r%ind(mout%natoms),stat=istat)
        mout%xx%nat = mout%natoms
        mout%yy%nat = mout%natoms
        mout%zz%nat = mout%natoms
        mout%znum%nat = mout%natoms
        mout%znum_r%nat = mout%natoms
        call check_for_error(istat, 'Error allocating memory for the periodic continued model.')

        mout%lx = min%lx*dble(xp)
        mout%ly = min%ly*dble(yp)
        mout%lz = min%lz*dble(zp)

        c=0
        do i = -(xp-1)/2, (xp-1)/2
            shift_x = dble(i)*min%lx
            do j = -(yp-1)/2, (yp-1)/2
                shift_y = dble(j)*min%ly
                do k = -(zp-1)/2, (zp-1)/2
                    shift_z = dble(k)*min%lz
                    mout%xx%ind(c*min%natoms+1:(c+1)*min%natoms) = min%xx%ind + shift_x
                    mout%yy%ind(c*min%natoms+1:(c+1)*min%natoms) = min%yy%ind + shift_y
                    mout%zz%ind(c*min%natoms+1:(c+1)*min%natoms) = min%zz%ind + shift_z
                    mout%znum%ind(c*min%natoms+1:(c+1)*min%natoms) = min%znum%ind
                    mout%znum_r%ind(c*min%natoms+1:(c+1)*min%natoms) = min%znum_r%ind
                    c = c+1
                end do
            end do
        end do

        mout%nelements = min%nelements
        allocate(mout%atom_type(mout%nelements), stat=istat)
        call check_for_error(istat, 'Problem allocating memory in periodic_continue_model.')
        mout%atom_type = min%atom_type

        if(init_hutch) then
            call model_init_hutches(mout)
            call check_for_error(istat, 'Cannot allocate memeory for the new hutch_array.')
        endif
    end subroutine periodic_continue_model


    subroutine hutch_list_3D(m, px, py, pz, radius, atoms, istat, nlist)
    ! Returns the atoms (aka atom indices) that are within radius 'radius' of 
    ! position (px,py,pz) in the list 'atoms'. Stores in nlist the number of
    ! atoms in this radius (i.e. size(atoms)+1 because of the original atom).
    ! Returns 1 in istat if memory allocation fails and -1 if no atoms are found.

        type(model), target, intent(in) :: m
        double precision, intent(in) :: px, py, pz
        double precision, intent(in) :: radius
        integer, pointer, dimension(:) :: atoms
        integer, intent(out) :: istat
        integer :: hx, hy, hz   ! hutch of position (px, py, pz)
        integer :: nh           ! number of hutches corresponding to diameter
        integer :: nlist        ! number of atoms in list
        integer :: i, j, k      ! counting variables
        integer, dimension(:), allocatable, target :: temp_atoms
        double precision, dimension(3) :: hcenter
        double precision :: dist2, distx, disty, distz
        integer :: i_start, i_end, j_start, j_end, k_start, k_end
        double precision :: x_start, x_end, y_start, y_end, z_start, z_end

        ! Allocatae temp_atoms with the max number of atoms so that no matter
        ! how many we find, there will always be enough room.
        allocate(temp_atoms(m%natoms), stat=istat)
        call check_for_error(istat, 'Unable to allocate memory for atom indices in hutch_list_pixel')

        x_start = px-radius*0.99999
        x_end = px+radius*0.99999
        y_start = py-radius*0.99999
        y_end = py+radius*0.99999
        z_start = pz-radius*0.99999
        z_end = pz+radius*0.99999

        ! Periodic boundary conditions
        if(x_start < -m%lx/2.0) x_start = x_start + m%lx
        if(x_end > m%lx/2.0) x_end = x_end - m%lx
        if(y_start < -m%ly/2.0) y_start = y_start + m%ly
        if(y_end > m%ly/2.0) y_end = y_end - m%ly
        if(z_start < -m%lz/2.0) z_start = z_start + m%lz
        if(z_end > m%lz/2.0) z_end = z_end - m%lz

        call hutch_position(m, x_start, y_start, z_start, i_start, j_start, k_start)
        call hutch_position(m, x_end, y_end, z_end, i_end, j_end, k_end)

        nh = 0
        nlist = 1
        do i=1, m%ha%nhutch_x
            if(i_start <= i_end) then ! This takes care of pbc. It's complicated but it works.
                if(i < i_start .or. i > i_end) cycle
            else
                if(i < i_start .and. i > i_end) cycle
            endif
            do j=1, m%ha%nhutch_y
                if(j_start <= j_end) then ! This takes care of pbc. It's complicated but it works.
                    if(j < j_start .or. j > j_end) cycle
                else
                    if(j < j_start .and. j > j_end) cycle
                endif
                do k=1, m%ha%nhutch_z
                    if(k_start <= k_end) then ! This takes care of pbc. It's complicated but it works.
                        if(k < k_start .or. k > k_end) cycle
                    else
                        if(k < k_start .and. k > k_end) cycle
                    endif
                    ! Calculate hutch centers.
                    hcenter(1) = -m%lx/2.0 + m%ha%hutch_size/2.0 + (i-1)*m%ha%hutch_size
                    hcenter(2) = -m%ly/2.0 + m%ha%hutch_size/2.0 + (j-1)*m%ha%hutch_size
                    hcenter(3) = -m%lz/2.0 + m%ha%hutch_size/2.0 + (k-1)*m%ha%hutch_size
                    ! Calculate distance.
                    distx = px-hcenter(1)
                    disty = py-hcenter(2)
                    distz = pz-hcenter(3)
                    distx = distx - m%lx*anint(distx/m%lx)
                    disty = disty - m%ly*anint(disty/m%ly)
                    distz = distz - m%lz*anint(distz/m%lz)
                    dist2 = (distx)**2 + (disty)**2 + (distz)**2
                    if( dist2 < (radius + m%ha%hutch_size*sqrt(2.0))**2 ) then
                        call hutch_position(m, hcenter(1), hcenter(2), hcenter(3), hx, hy, hz)
                        if(m%ha%h(hx, hy, hz)%nat /= 0) then
                            temp_atoms(nlist:nlist+m%ha%h(hx, hy, hz)%nat-1) = m%ha%h(hx, hy, hz)%at(1:m%ha%h(hx, hy, hz)%nat)
                            nlist = nlist + m%ha%h(hx, hy, hz)%nat
                        endif
                        nh = nh + 1
                        if(i .ne. hx .or. j .ne. hy .or. k .ne. hz) then
                            write(*,*) "ERROR Hutches:"
                            write(*,*) i,j,k
                            write(*,*) hx, hy, hz
                        endif
                    endif
                enddo
            enddo
        enddo

        ! Copy all the atoms we found in the previous loop into atoms.
        if (nlist > 1) then
            allocate(atoms(nlist-1), stat=istat)
            if (istat /= 0) then
                write (*,*) 'Unable to allocate memory for atom indices in hutch_list_pixel.'
                return
            endif
            atoms = temp_atoms(1:nlist-1)
        else
            nullify(atoms)
            istat = -1
        endif

        deallocate(temp_atoms)
    end subroutine hutch_list_3d


    subroutine hutch_list_pixel(m, px, py, diameter, atoms, istat)
    ! Makes a list of atom indices (in atoms) of the atoms in a rectangular
    ! prism with side length diameter in x and y, through the model thickness
    ! in z, centered on the hutch containing the point (px, py).
        type(model), target, intent(in) :: m
        double precision, intent(in) :: px, py, diameter
        integer, pointer, dimension(:) :: atoms
        integer, intent(out) :: istat
        integer :: hx, hy, hz   ! hutch of position (px, py, pz)
        integer :: nh           ! number of hutches corresponding to diameter
        integer :: nlist        ! number of atoms in list
        integer :: i, j, k  ! counting variables
        integer, dimension(:), allocatable, target :: temp_atoms
        double precision, dimension(3) :: hcenter
        double precision :: dist
        integer :: i_start, i_end, j_start, j_end, trash
        double precision :: x_start, x_end, y_start, y_end

        !write(*,*) "Number of hutches in the x, y, and z directions:", ha%nhutch_x, ha%nhutch_y, ha%nhutch_z

        ! Allocatae temp_atoms with the max number of atoms so that no matter
        ! how many we find, there will always be enough room.
        allocate(temp_atoms(m%natoms), stat=istat)
        if (istat /= 0) then
            write (*,*) 'Unable to allocate memory for atom indices in hutch_list_pixel'
            return
        end if

        ! I am going to do a slight approximation in this function, but it will
        ! be very close. Considering the hutches are currently so small and
        ! contain only an atom or two, the additional hutches that will be
        ! included are not detrimental. Also, it cannot affect the results.
        ! The idea is to iterate through each hutch, calculate its center,
        ! and compute the distance from its center to (px,py) in the x-y plane;
        ! if this distance is <= diameter/2 + m%ha%hutch_size/sqrt(2.0) then we
        ! include that hutchs atoms. The above sum is the sum of the radius of
        ! the area we want to include + the "radius" (half diagonal) of the
        ! hutch. The half diagonal of the hutch may be a bit of an
        ! overapprximation, but it isnt much of one.

        x_start = px-diameter/2.000001
        x_end = px+diameter/2.000001
        y_start = py-diameter/2.000001
        y_end = py+diameter/2.000001
        if(x_start < -m%lx/2.0) x_start = x_start + m%lx !PBC
        if(x_end > m%lx/2.0) x_end = x_end - m%lx !PBC
        if(y_start < -m%ly/2.0) y_start = y_start + m%ly !PBC
        if(y_end > m%ly/2.0) y_end = y_end - m%ly !PBC
        call hutch_position(m, x_start, y_start, dble(0.0), i_start, j_start, trash)
        call hutch_position(m, x_end, y_end, dble(0.0), i_end, j_end, trash)

        nh = 0
        nlist = 1
        do i = 1, m%ha%nhutch_x
            if(i_start <= i_end) then ! This takes care of pbc. It's complicated but it works.
                if(i < i_start .or. i > i_end) cycle
            else
                if(i < i_start .and. i > i_end) cycle
            endif
            do j = 1, m%ha%nhutch_y
                if(j_start <= j_end) then ! This takes care of pbc. It's complicated but it works.
                    if(j < j_start .or. j > j_end) cycle
                else
                    if(j < j_start .and. j > j_end) cycle
                endif
                do k=1, m%ha%nhutch_z
                    ! Calculate hutch centers.
                    hcenter(1) = -m%lx/2.0 + m%ha%hutch_size/2.0 + (i-1)*m%ha%hutch_size
                    hcenter(2) = -m%ly/2.0 + m%ha%hutch_size/2.0 + (j-1)*m%ha%hutch_size
                    hcenter(3) = -m%lz/2.0 + m%ha%hutch_size/2.0 + (k-1)*m%ha%hutch_size
                    ! Calculate distance.
                    dist = sqrt( (px-hcenter(1))**2 + (py-hcenter(2))**2 )
                    if( dist < diameter/2.0 + m%ha%hutch_size/sqrt(2.0) ) then
                        call hutch_position(m, hcenter(1), hcenter(2), hcenter(3), hx, hy, hz)
                        if(m%ha%h(hx, hy, hz)%nat /= 0) then
                            temp_atoms(nlist:nlist+m%ha%h(hx, hy, hz)%nat-1) = m%ha%h(hx, hy, hz)%at(1:m%ha%h(hx, hy, hz)%nat)
                            nlist = nlist + m%ha%h(hx, hy, hz)%nat
                        endif
                        nh = nh + 1
                    endif
                enddo
            enddo
        enddo

        ! Copy all the atoms we found in the previous loop into atoms.
        if (nlist > 1) then
            allocate(atoms(nlist-1), stat=istat)
            if (istat /= 0) then
                write (*,*) 'Unable to allocate memory for atom indices in hutch_list_pixel.'
                return
            endif
            atoms = temp_atoms(1:nlist-1)
        else
            nullify(atoms)
            istat = -1
        endif

        deallocate(temp_atoms)
    end subroutine hutch_list_pixel


    subroutine hutch_list_pixel_sq(m, px, py, diameter, atoms, istat)
        type(model), target, intent(in) :: m
        double precision, intent(in) :: px, py, diameter
        integer, pointer, dimension(:) :: atoms !output of atom indices
        integer, intent(out) :: istat
        integer :: nh           ! number of hutches corresponding to diameter
        integer :: nlist        ! number of atoms in list
        integer :: i, j, k      ! counting variables
        integer, dimension(:), allocatable, target :: temp_atoms
        integer :: i_start, i_end, j_start, j_end, trash
        double precision :: x_start, x_end, y_start, y_end

#ifdef DEBUG
        write(*,*) "Number of hutches in the x, y, and z directions:", m%ha%nhutch_x, m%ha%nhutch_y, m%ha%nhutch_z
#endif
        allocate(temp_atoms(m%natoms), stat=istat)
        call check_for_error(istat, 'Unable to allocate memory for atom indices in hutch_list_pixel')

        x_start = px-diameter/2.000001
        x_end = px+diameter/2.000001
        y_start = py-diameter/2.000001
        y_end = py+diameter/2.000001

        ! Periodic boundary conditions
        if(x_start < -m%lx/2.0) x_start = x_start + m%lx
        if(x_end > m%lx/2.0) x_end = x_end - m%lx
        if(y_start < -m%ly/2.0) y_start = y_start + m%ly
        if(y_end > m%ly/2.0) y_end = y_end - m%ly

        call hutch_position(m, x_start, y_start, dble(0.0), i_start, j_start, trash)
        call hutch_position(m, x_end, y_end, dble(0.0), i_end, j_end, trash)
        nh = (i_end-i_start+1)*(j_end-j_start+1)*(m%ha%nhutch_z)
        
        ! Fill in the list.
        nlist = 1
        do i = 1, m%ha%nhutch_x
            if(i_start <= i_end) then ! This takes care of pbc. It's complicated but it works.
                if(i < i_start .or. i > i_end) cycle
            else
                if(i < i_start .and. i > i_end) cycle
            endif
            do j = 1, m%ha%nhutch_y
                if(j_start <= i_end) then ! This takes care of pbc. It's complicated but it works.
                    if(j < j_start .or. j > j_end) cycle
                else
                    if(j < j_start .and. j > j_end) cycle
                endif
                do k = 1, m%ha%nhutch_z
                    if(m%ha%h(i, j, k)%nat /= 0) then
                        temp_atoms(nlist:nlist+m%ha%h(i, j, k)%nat-1) = m%ha%h(i, j, k)%at(1:m%ha%h(i, j, k)%nat)
                        nlist = nlist + m%ha%h(i, j, k)%nat
                    endif
                enddo
            enddo
        enddo

        ! Assign atoms to the subset of temp_atoms that was filled in.
        if( nlist > 1 ) then
            allocate(atoms(nlist-1), stat=istat)
            call check_for_error(istat, 'Unable to allocate memory for atom indices in hutch_list_pixel.')
            atoms = temp_atoms
        else
            nullify(atoms)
            istat = -1
        endif

        if(allocated(temp_atoms)) deallocate(temp_atoms)
    end subroutine hutch_list_pixel_sq


    subroutine hutch_move_atom(m, atom, xx, yy, zz)
    ! Moves the atom with index atom from its current hutch in hutch_array
    ! to the hutch that encompasses position (xx, yy, zz). Used to update the
    ! hutch_array for a Monte Carlo move of one atom.
        type(model), target, intent(inout) :: m
        integer, intent(in) :: atom
        double precision, intent(in) :: xx, yy, zz
        integer :: hx, hy, hz
        call hutch_remove_atom(m, atom)
        call hutch_position(m, xx, yy, zz, hx, hy, hz)
        call hutch_add_atom(m, atom, hx, hy, hz)
    end subroutine hutch_move_atom


    subroutine hutch_add_atom(m, atom, hx, hy, hz)
    ! Adds the atom with index atom to the hutch_array in hutch hx, hy, hz.
        type(model), target, intent(inout) :: m
        integer, intent(in) :: atom, hx, hy, hz
        integer :: nat, i
        integer, dimension(m%ha%h(hx, hy, hz)%nat+1) :: scratch_atoms
        integer, dimension(:,:), allocatable :: temp_atom_hutch
        type(hutch_array), pointer :: ha
        logical :: found
        ha => m%ha

#ifdef DEBUG
        found = .false.
        do i=1, ha%h(hx,hy,hz)%nat
            if(ha%h(hx,hy,hz)%at(i) .eq. atom) found = .true.
        enddo
        if(found) write(*,*) "WARNING: ERROR: Atom", atom, "already exists in hutch", hx, hy, hz
#endif

        ! ha%h(hx,hy,hz)%nat is set to 0 in a do loop in model_init_hutches,
        ! slightly before this function is called for each atom.
        nat = ha%h(hx,hy,hz)%nat
        if(nat > 0) then
            if(size(ha%h(hx,hy,hz)%at) > nat) then
                ha%h(hx,hy,hz)%at(nat+1) = atom
            else
                scratch_atoms(1:nat) = ha%h(hx, hy, hz)%at
                scratch_atoms(nat+1) = atom
                ! Reallocate with new size
                deallocate(ha%h(hx,hy,hz)%at)
                allocate(ha%h(hx,hy,hz)%at(1:nat+1)) ! +1 for extra atom
                ha%h(hx,hy,hz)%at = scratch_atoms
            endif
        else
            if(size(ha%h(hx,hy,hz)%at) .eq. 0) then
                allocate(ha%h(hx,hy,hz)%at(1:5)) ! Start with 5 spots for atoms.
            endif
            ha%h(hx,hy,hz)%at(1) = atom
        end if

        ha%h(hx,hy,hz)%nat = nat+1
        ! Create space if there isnt already.
        if( size(ha%atom_hutch) / 3 < atom ) then
            allocate(temp_atom_hutch( size(ha%atom_hutch) / 3, 3))
            temp_atom_hutch = ha%atom_hutch
            deallocate(ha%atom_hutch)
            allocate(ha%atom_hutch(m%natoms, 3))
            ha%atom_hutch = temp_atom_hutch
            deallocate(temp_atom_hutch)
        endif

        ha%atom_hutch(atom, 1) = hx
        ha%atom_hutch(atom, 2) = hy
        ha%atom_hutch(atom, 3) = hz

#ifdef DEBUG
        found = .false.
        do i=1, ha%h(hx,hy,hz)%nat
            if( ha%h(hx,hy,hz)%at(i) .eq. atom ) found = .true.
        enddo
        if( .not. found) write(*,*) "WARNING: Tried to add atom",atom,"to hutch", hx, hy, hy, "but failed!"
#endif
    end subroutine hutch_add_atom


    subroutine hutch_remove_atom(m, atom)
    ! Remove atom atom from its current hutch.  This reduces the number of atoms in hutch
    ! array by one, so it should only be used in conjunction with hutch_add_atom.
        type(model), target, intent(inout) :: m
        integer, intent(in) :: atom
        integer :: hx, hy, hz, i
        type(hutch_array), pointer :: ha
        logical :: found = .false. ! safety feature
        ha => m%ha

        hx = ha%atom_hutch(atom,1)
        hy = ha%atom_hutch(atom,2)
        hz = ha%atom_hutch(atom,3)

#ifdef DEBUG
        found = .false.
        do i=1, ha%h(hx,hy,hz)%nat
            if(ha%h(hx,hy,hz)%at(i) .eq. atom) found = .true.
        enddo
        if(.not. found) then
            write(*,*) "WARNING: ERROR: Atom", atom, "does not exist in hutch", hx, hy, hz, "and you are trying to remove it!"
        endif
#endif

        do i=1, ha%h(hx,hy,hz)%nat
            if (ha%h(hx,hy,hz)%at(i) .eq. atom) then
                ha%h(hx,hy,hz)%at( i:ha%h(hx,hy,hz)%nat-1 ) = ha%h(hx,hy,hz)%at( i+1:ha%h(hx,hy,hz)%nat )
                found = .true.
            end if
        enddo
        ha%h(hx,hy,hz)%nat = ha%h(hx,hy,hz)%nat-1

        ha%atom_hutch(atom,1) = 0
        ha%atom_hutch(atom,2) = 0
        ha%atom_hutch(atom,3) = 0
    end subroutine hutch_remove_atom


    subroutine move_atom(m, atom, xx, yy, zz)
        type(model), intent(inout) :: m
        integer, intent(in) :: atom
        double precision, intent(in) :: xx, yy, zz
        m%xx%ind(atom) = xx
        m%yy%ind(atom) = yy
        m%zz%ind(atom) = zz
        call hutch_move_atom(m, atom, xx, yy, zz)

#ifdef DEBUG
        if( m%xx%ind(atom) .ne. xx .or. m%yy%ind(atom) .ne. yy .or.  m%zz%ind(atom) .ne. zz) then
            write(*,*) "WARNING: Atom",atom,"'s positions did not get updated correctly!"
            write(*,*) m%xx%ind(atom), xx
            write(*,*) m%yy%ind(atom), yy
            write(*,*) m%zz%ind(atom), zz
        endif
#endif
    end subroutine move_atom


    subroutine add_atom(m, atom, xx, yy, zz, znum, znum_r)
        type(model), intent(inout) :: m
        integer, intent(in) :: atom ! index of atom in unroated model.
        double precision, intent(in) :: xx, yy, zz ! position of new atom
        integer, intent(in) :: znum, znum_r ! znum and znum_r of new atom
        integer :: hx, hy, hz
        ! We need to add an atom to xx, yy, zz, znum, znum_r, and the hutches.
        ! We need to increment natoms.
        ! We need to add a spot to rot_i with the correct index we used in xx, etc.
#ifdef DEBUG
        write(*,*) "A wild atom appeared!"
#endif

        ! We place the extra atom at the end of the above arrays, and therefore
        ! the new atom has index m%natoms+1.
        ! Reallocate xx, yy, zz, znum, and znum_r bigger (leaving the
        ! end empty for the new atom to fit into).

        ! Add the atom to the model.
        call add_index(m%rot_i(atom), m%natoms + 1)
        call add_index_dble(m%xx, xx)
        call add_index_dble(m%yy, yy)
        call add_index_dble(m%zz, zz)
        call add_index(m%znum, znum)
        call add_index(m%znum_r, znum_r)
        m%natoms = m%natoms + 1
        call hutch_position(m, xx, yy, zz, hx, hy, hz)
        call hutch_add_atom(m, m%natoms, hx, hy, hz)
    end subroutine add_atom


    subroutine remove_atom(m, atom, ind)
        ! We need to remove atom ind from xx, yy, zz, znum, znum_r, and the hutches.
        ! We need to decrement natoms.
        ! We need to remove the spot from rot_i with the correct index we used in xx, etc.
        type(model), intent(inout) :: m
        integer, intent(in) :: atom ! index of atom in unroated model.
        integer, intent(in) :: ind ! index of atom to remove from m
        integer :: i, j, temp, hx, hy, hz
        integer, dimension(:,:), allocatable :: temp_atom_hutch
#ifdef DEBUG
        write(*,*) "An atom ran away!"
#endif

        temp = ind
        
        ! Remove ind from xx, yy, zz, znum, znum_r, and rot_i(atom).
        ! These calls decrement the index of all atoms with a higher index than
        ! ind. That is an inconvienence that we do need to deal with. It should
        ! only matter for rot_i hereafter, however, which we fix in the
        ! next forall loop.
        call remove_index_dble(m%xx, ind)
        call remove_index_dble(m%yy, ind)
        call remove_index_dble(m%zz, ind)
        call remove_index(m%znum, ind)
        call remove_index(m%znum_r, ind)
        do i=1,m%rot_i(atom)%nat
            if(m%rot_i(atom)%ind(i) .eq. ind) then
                call remove_index(m%rot_i(atom), i)
                exit
            endif
        enddo
        ! Hereafter ind is not what it was before! Must use temp instead.

        ! Decrement every index in each rot_i that is higher than ind.
        ! We need to do this because we removed an element from each of the
        ! above arrays and therefore we need to correct the atom indices we
        ! are pointing to in rot_i.
        do i=1,m%unrot_natoms
            do j=1,m%rot_i(i)%nat
                if(m%rot_i(i)%ind(j) .gt. temp) then
                    m%rot_i(i)%ind(j) = m%rot_i(i)%ind(j) - 1
                endif
            enddo
        enddo

        ! Remove ind from its hutch.
        call hutch_remove_atom(m, temp)

        ! I also need to go through the hutches and decrement every index that
        ! is higher than ind for the same reason.
        ! Also, reallocate m%ha%atom_hutch here to one smaller.
        do i=temp+1, m%natoms
            hx = m%ha%atom_hutch(i,1)
            hy = m%ha%atom_hutch(i,2)
            hz = m%ha%atom_hutch(i,3)
            do j=1, m%ha%h(hx, hy, hz)%nat
                if( m%ha%h(hx, hy, hz)%at(j) .eq. i) then
                    m%ha%h(hx, hy, hz)%at(j) = m%ha%h(hx, hy, hz)%at(j) - 1
                endif
            enddo
        end do
        ! Reallocate m%ha%atom_hutch to one smaller.
        allocate(temp_atom_hutch( m%natoms, 3))
        temp_atom_hutch = m%ha%atom_hutch
        deallocate(m%ha%atom_hutch)
        allocate(m%ha%atom_hutch(m%natoms-1, 3))
        j = 1
        do i=1,m%natoms
            if( i /= temp) then
                m%ha%atom_hutch(j,1) = temp_atom_hutch(i,1)
                m%ha%atom_hutch(j,2) = temp_atom_hutch(i,2)
                m%ha%atom_hutch(j,3) = temp_atom_hutch(i,3)
                j = j + 1
            endif
        enddo
        deallocate(temp_atom_hutch)

        m%natoms = m%natoms - 1
    end subroutine remove_atom


    subroutine add_index(il, i)
        type(index_list), intent(inout) :: il
        integer, intent(in) :: i
        integer, dimension(:), allocatable :: scratch
        if( il%nat >= 1 ) then
            ! If there is space no need to reallocate. If not, reallocate.
            if(size(il%ind) .ge. il%nat+1) then
                if(il%nat == -1) il%nat = 0 ! We set old_index(i) to -1 sometimes
                il%nat = il%nat + 1
                il%ind(il%nat) = i
            else
                allocate(scratch(il%nat))
                scratch = il%ind
                ! Increase the size by 200%. For the rot_i's this won't matter, but for
                ! the model lists it will increase them by a few atoms so that when
                ! we rotate in and out we don't need to reallocate every single time.
                ! But only increment nat by 1. This is the size for the algorithm.
                il%nat = il%nat + 1
                deallocate(il%ind)
                allocate(il%ind( il%nat*2 ))
                il%ind(1:il%nat-1) = scratch
                il%ind(il%nat) = i
            endif
        else
            il%nat = 1
            if(.not. allocated(il%ind)) allocate(il%ind(1*5)) ! Start it with space for 5 atoms.
            il%ind(1) = i
        endif
        if(allocated(scratch)) then
            deallocate(scratch)
        endif
    end subroutine add_index


    subroutine add_index_dble(il, i)
        type(dble_index_list), intent(inout) :: il
        double precision, intent(in) :: i
        integer, dimension(:), allocatable :: scratch
        if( il%nat >= 1 ) then
            ! If there is space no need to reallocate. If not, reallocate.
            if(size(il%ind) .ge. il%nat+1) then
                il%nat = il%nat + 1
                il%ind(il%nat) = i
            else
                allocate(scratch(il%nat))
                scratch = il%ind
                ! Increase the size by 200%. For the rot_i's this won't matter, but for
                ! the model lists it will increase them by a few atoms so that when
                ! we rotate in and out we don't need to reallocate every single time.
                ! But only increment nat by 1. This is the size for the algorithm.
                il%nat = il%nat + 1
                deallocate(il%ind)
                allocate(il%ind( il%nat + il%nat*2 ))
                il%ind(1:il%nat-1) = scratch
                il%ind(il%nat) = i
            endif
        else
            il%nat = 1
            if(.not. allocated(il%ind)) allocate(il%ind(1*5)) !Start it with space for 5 atoms.
            il%ind(1) = i
        endif
        if(allocated(scratch)) then
            deallocate(scratch)
        endif
    end subroutine add_index_dble


    subroutine remove_index(il, ind)
        type(index_list), intent(inout) :: il
        integer, intent(in) :: ind
            il%ind( ind:il%nat-1 ) = il%ind( ind+1:il%nat )
            il%nat = il%nat - 1
    end subroutine remove_index


    subroutine remove_index_dble(il, ind)
        type(dble_index_list), intent(inout) :: il
        integer, intent(in) :: ind
            il%ind( ind:il%nat-1 ) = il%ind( ind+1:il%nat )
            il%nat = il%nat - 1
    end subroutine remove_index_dble


    subroutine reject_position(m, atom, xx_cur, yy_cur, zz_cur)
        type(model), intent(inout) :: m
        integer, intent(in) :: atom
        double precision, intent(in) :: xx_cur, yy_cur, zz_cur
        ! The moved atom in the original model, m, should return to their old position
        ! when the random move is rejected
        m%xx%ind(atom) = xx_cur
        m%yy%ind(atom) = yy_cur
        m%zz%ind(atom) = zz_cur
    end subroutine reject_position

end module model_mod
