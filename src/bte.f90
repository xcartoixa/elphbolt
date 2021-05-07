module bte_module
  !! Module containing type and procedures related to the solution of the
  !! Boltzmann transport equation (BTE).

  use params, only: dp, k8, qe
  use misc, only: print_message, exit_with_message, write2file_rank2_real, &
       distribute_points, demux_state, binsearch
  use numerics_module, only: numerics
  use crystal_module, only: crystal
  use symmetry_module, only: symmetry
  use phonon_module, only: phonon
  use electron_module, only: electron
  use interactions, only: calculate_ph_rta_rates, read_transition_probs_3ph, &
       read_transition_probs_eph, calculate_el_rta_rates
  use bz_sums, only: calculate_transport_coeff

  implicit none

  private
  public bte

  type bte
     !! Data and procedures related to the BTE.

     real(dp), allocatable :: ph_rta_rates_ibz(:,:)
     !! Phonon RTA scattering rates on the IBZ.
     real(dp), allocatable :: ph_field_term(:,:,:)
     !! Phonon field coupling term on the FBZ.
     real(dp), allocatable :: ph_response(:,:,:)
     !! Phonon response function on the FBZ.
     
     real(dp), allocatable :: el_rta_rates_ibz(:,:)
     !! Electron RTA scattering rates on the IBZ.
     real(dp), allocatable :: el_field_term(:,:,:)
     !! Electron field coupling term on the FBZ.
     real(dp), allocatable :: el_response(:,:,:)
     !! electron response function on the FBZ.
   contains

     procedure :: solve_bte
     
  end type bte

contains

  subroutine solve_bte(bt, num, crys, sym, ph, el)
    !! Subroutine to solve the BTE

    class(bte), intent(out) :: bt
    type(numerics), intent(in) :: num
    type(crystal), intent(in) :: crys
    type(symmetry), intent(in) :: sym
    type(phonon), intent(in) :: ph
    type(electron), intent(in), optional :: el

    !Local variables
    character(len = 1024) :: tag, Tdir
    integer(k8) :: iq, ik, it
    real(dp), allocatable :: rates_3ph(:,:), rates_phe(:,:), rates_eph(:,:)

    call print_message("Solving BTE in the RTA...")
    
    !Create output folder tagged by temperature and change into it
    write(tag, "(E9.3)") crys%T
    Tdir = trim(adjustl(num%cwd))//'/T'//trim(adjustl(tag))
    if(this_image() == 1) then
       call system('mkdir '//trim(adjustl(Tdir)))
    end if
    sync all

    if(num%phbte) then
       !Calculate RTA scattering rates
       if(present(el)) then
          call calculate_ph_rta_rates(rates_3ph, rates_phe, num, crys, ph, el)
       else
          call calculate_ph_rta_rates(rates_3ph, rates_phe, num, crys, ph)
       end if

       !Allocate total RTA scattering rates
       allocate(bt%ph_rta_rates_ibz(ph%nq_irred, ph%numbranches))
       
       !Matthiessen's rule
       bt%ph_rta_rates_ibz = rates_3ph + rates_phe

       !Calculate field term (F0 or G0)
       call calculate_field_term('ph', 'T', ph%nequiv, ph%ibz2fbz_map, &
            crys%T, 0.0_dp, ph%ens, ph%vels, bt%ph_rta_rates_ibz, bt%ph_field_term)

       !Symmetrize field term
       do iq = 1, ph%nq
          bt%ph_field_term(iq,:,:)=transpose(&
               matmul(ph%symmetrizers(:,:,iq),transpose(bt%ph_field_term(iq,:,:))))
       end do

       !RTA solution of BTE
       allocate(bt%ph_response(ph%nq, ph%numbranches, 3))
       bt%ph_response = bt%ph_field_term

       !Calculate transport coefficient
       call calculate_transport_coeff('ph', 'T', crys%T, 1_k8, 0.0_dp, ph%ens, ph%vels, &
            crys%volume, ph%qmesh, bt%ph_response)

       !Change to data output directory
       call chdir(trim(adjustl(Tdir)))

       !Write RTA scattering rates to file
       call write2file_rank2_real('ph.W_rta_3ph', rates_3ph)
       call write2file_rank2_real('ph.W_rta_phe', rates_phe)
       call write2file_rank2_real('ph.W_rta', bt%ph_rta_rates_ibz)
    end if

    if(num%ebte) then
       !Calculate RTA scattering rates
       call calculate_el_rta_rates(rates_eph, num, crys, el)

       !Allocate total RTA scattering rates
       allocate(bt%el_rta_rates_ibz(el%nk_irred, el%numbands))
       bt%el_rta_rates_ibz = rates_eph ! + other channels
       
       !Calculate field term (I0 or J0)
       call calculate_field_term('el', 'E', el%nequiv, el%ibz2fbz_map, &
            crys%T, el%chempot, el%ens, el%vels, bt%el_rta_rates_ibz, bt%el_field_term, el%indexlist)

       !Symmetrize field term
       do ik = 1, el%nk
          bt%el_field_term(ik,:,:)=transpose(&
               matmul(el%symmetrizers(:,:,ik),transpose(bt%el_field_term(ik,:,:))))
       end do
       
       !RTA solution of BTE
       allocate(bt%el_response(el%nk, el%numbands, 3))
       bt%el_response = bt%el_field_term
       
       !Calculate transport coefficient
       call calculate_transport_coeff('el', 'E', crys%T, el%spindeg, el%chempot, el%ens, el%vels, &
            crys%volume, el%kmesh, bt%el_response)
       !...
       !...
       !...

       !Change to data output directory
       call chdir(trim(adjustl(Tdir)))

       !Write RTA scattering rates to file
       call write2file_rank2_real('el.W_rta_eph', rates_eph)
    end if
    
    !Change back to cwd
    call chdir(trim(adjustl(num%cwd)))

!!$    !!!!
!!$    !TODO Need a more elegant solution to jumping between directories...
!!$    !!!!
!!$    
    !Start iterator
    do it = 1, 20
       if(num%phbte) then
          call iterate_bte_ph(crys%T, num%datadumpdir, .False., ph%nequiv, ph%equiv_map, &
               ph%ibz2fbz_map, bt%ph_rta_rates_ibz, bt%ph_field_term, bt%ph_response)

          !Symmetrize response function
          do iq = 1, ph%nq
             bt%ph_response(iq,:,:)=transpose(&
                  matmul(ph%symmetrizers(:,:,iq),transpose(bt%ph_response(iq,:,:))))
          end do

          !Calculate transport coefficient
          call calculate_transport_coeff('ph', 'T', crys%T, 1_k8, 0.0_dp, ph%ens, ph%vels, &
               crys%volume, ph%qmesh, bt%ph_response)
       end if

       if(num%ebte) then
          !call iterate_bte_el(crys%T, num%datadumpdir, .False., el%indexlist, &
          !     el%nequiv, el%equiv_map, el%ibz2fbz_map, bt%el_rta_rates_ibz, &
          !     bt%el_field_term, bt%el_response)

          call iterate_bte_el(crys%T, num%datadumpdir, .False., el, bt%el_rta_rates_ibz, &
               bt%el_field_term, bt%el_response)

          !Symmetrize response function
          do ik = 1, el%nk
             bt%el_response(ik,:,:)=transpose(&
                  matmul(el%symmetrizers(:,:,ik),transpose(bt%el_response(ik,:,:))))
          end do

          !Calculate transport coefficient
          call calculate_transport_coeff('el', 'E', crys%T, el%spindeg, el%chempot, el%ens, el%vels, &
               crys%volume, el%kmesh, bt%el_response)
       end if
       
       !if(is_converged(coeff_new, coeff_old)) exit
    end do
  end subroutine solve_bte

  subroutine calculate_field_term(species, field, nequiv, ibz2fbz_map, &
       T, chempot, ens, vels, rta_rates_ibz, field_term, el_indexlist)
    !! Subroutine to calculate the field coupling term of the BTE.
    !!
    !! species Type of particle
    !! field Type of field
    !! nequiv List of the number of equivalent points for each IBZ wave vector
    !! ibz2fbz_map Map from an FBZ wave vectors to its IBZ wedge image
    !! T Temperature in K
    !! ens FBZ energies
    !! vels FBZ velocities
    !! chempot Chemical potential (should be 0 for phonons)
    !! rta_rates_ibz IBZ RTA scattering rates
    !! field_term FBZ field-coupling term of the BTE
    !! el_indexlist [Optional] 

    character(len = 2), intent(in) :: species
    character(len = 1), intent(in) :: field
    integer(k8), intent(in) :: nequiv(:), ibz2fbz_map(:,:,:)
    real(dp), intent(in) :: T, chempot, ens(:,:), vels(:,:,:), rta_rates_ibz(:,:)
    real(dp), allocatable, intent(out) :: field_term(:,:,:)
    integer(k8), intent(in), optional :: el_indexlist(:)
    
    !Local variables
    integer(k8) :: ik_ibz, ik_fbz, ieq, ib, nk_ibz, nk, nbands, pow, &
         im, chunk, num_active_images
    integer(k8), allocatable :: start[:], end[:]
    real(dp), allocatable :: field_term_reduce(:,:,:)[:]
    real(dp) :: A
    logical :: trivial_case

    !Set constant and power of energy depending on species and field type
    if(species == 'ph') then
       A = 1.0_dp/T
       pow = 1
       if(chempot /= 0.0_dp) then
          call exit_with_message("Phonon chemical potential non-zero in calculate_field_term. Exiting.")
       end if
    else if(species == 'el') then
       if(field == 'T') then
          A = 1.0_dp/T
          pow = 1
       else if(field == 'E') then
          A = qe
          pow = 0
       else
          call exit_with_message("Unknown field type in calculate_field_term. Exiting.")
       end if
    else
       call exit_with_message("Unknown particle species in calculate_field_term. Exiting.")
    end if

    !Number of IBZ wave vectors
    nk_ibz = size(rta_rates_ibz(:,1))
    
    !Number of FBZ wave vectors
    nk = size(ens(:,1))

    !Number of bands
    nbands = size(ens(1,:))
    
    !Allocate and initialize field term
    allocate(field_term(nk, nbands, 3))
    field_term(:,:,:) = 0.0_dp

    !No field-coupling case
    trivial_case = species == 'ph' .and. field == 'E'
    
    if(.not. trivial_case) then
       !Allocate start and end coarrays
       allocate(start[*], end[*])

       !Divide IBZ states among images
       call distribute_points(nk_ibz, chunk, start, end, num_active_images)
       
       !Allocate and initialize field term coarrays
       allocate(field_term_reduce(nk, nbands, 3)[*])
       field_term_reduce(:,:,:) = 0.0_dp

       !Work the active images only:
       do ik_ibz = start, end
          do ieq = 1, nequiv(ik_ibz)
             if(species == 'ph') then
                ik_fbz = ibz2fbz_map(ieq, ik_ibz, 2)
             else
                !Find index of electron in indexlist
                call binsearch(el_indexlist, ibz2fbz_map(ieq, ik_ibz, 2), ik_fbz)
             end if
             do ib = 1, nbands
                if(rta_rates_ibz(ik_ibz, ib) /= 0.0_dp) then
                   field_term_reduce(ik_fbz, ib, :) = A*vels(ik_fbz, ib, :)*&
                        (ens(ik_fbz, ib) - chempot)**pow/rta_rates_ibz(ik_ibz, ib)
                end if
             end do
          end do
       end do
       
       sync all

       !Reduce field term coarrays
       do im = 1, num_active_images
          field_term(:,:,:) = field_term(:,:,:) + field_term_reduce(:,:,:)[im] !nm.eV/K
       end do
    end if
    sync all
  end subroutine calculate_field_term

  subroutine iterate_bte_ph(T, datadumpdir, drag, nequiv, equiv_map, ibz2fbz_map, rta_rates_ibz, &
       field_term, response_ph)
    !! Subroutine to iterate the phonon BTE one step.
    !! 
    !! 

    logical, intent(in) :: drag
    integer(k8), intent(in) :: nequiv(:), equiv_map(:,:), ibz2fbz_map(:,:,:)
    real(dp), intent(in) :: T, rta_rates_ibz(:,:), field_term(:,:,:)
    real(dp), intent(inout) :: response_ph(:,:,:)
    character(len = *), intent(in) :: datadumpdir

    !Local variables
    integer(k8) :: nstates_irred, nprocs, chunk, istate1, numbranches, s1, &
         iq1_ibz, ieq, iq1_sym, iq1_fbz, iproc, iq2, s2, iq3, s3, im, nq, num_active_images
    integer(k8), allocatable :: istate2_plus(:), istate3_plus(:), &
         istate2_minus(:), istate3_minus(:), start[:], end[:]
    real(dp) :: tau_ibz
    real(dp), allocatable :: Wp(:), Wm(:), response_ph_reduce(:,:,:)[:]
    character(len = 1024) :: filepath_Wm, filepath_Wp, Wdir, tag

    !Set output directory of transition probilities
    write(tag, "(E9.3)") T
    Wdir = trim(adjustl(datadumpdir))//'W_T'//trim(adjustl(tag))
    
    !Number of phonon branches
    numbranches = size(rta_rates_ibz(1,:))

    !Number of FBZ wave vectors
    nq = size(field_term(:,1,1))
    
    !Total number of IBZ states
    nstates_irred = size(rta_rates_ibz(:,1))*numbranches

    !Total number of 3-phonon processes for a given initial phonon state.
    nprocs = nq*numbranches**2

    !Allocate arrays
    allocate(Wp(nprocs), Wm(nprocs))
    allocate(istate2_plus(nprocs), istate3_plus(nprocs), &
         istate2_minus(nprocs), istate3_minus(nprocs))
    
    !Allocate coarrays
    allocate(start[*], end[*])
    allocate(response_ph_reduce(nq, numbranches, 3)[*])

    !Initialize coarray
    response_ph_reduce(:,:,:) = 0.0_dp
    
    !Divide phonon states among images
    call distribute_points(nstates_irred, chunk, start, end, num_active_images)
    
    !Run over first phonon IBZ states
    do istate1 = start, end
       !Demux state index into branch (s) and wave vector (iq1_ibz) indices
       call demux_state(istate1, numbranches, s1, iq1_ibz)

       !RTA lifetime
       tau_ibz = 0.0_dp
       if(rta_rates_ibz(iq1_ibz, s1) /= 0.0_dp) then
          tau_ibz = 1.0_dp/rta_rates_ibz(iq1_ibz, s1)
       end if

       !Set W+ filename
       write(tag, '(I9)') istate1
       filepath_Wp = trim(adjustl(Wdir))//'/Wp.istate'//trim(adjustl(tag))

       !Read W+ from file
       call read_transition_probs_3ph(trim(adjustl(filepath_Wp)), Wp, &
            istate2_plus, istate3_plus)

       !Set W- filename
       filepath_Wm = trim(adjustl(Wdir))//'/Wm.istate'//trim(adjustl(tag))

       !Read W- from file
       call read_transition_probs_3ph(trim(adjustl(filepath_Wm)), Wm, &
            istate2_minus, istate3_minus)

       !Sum over the number of equivalent q-points of the IBZ point
       do ieq = 1, nequiv(iq1_ibz)
          iq1_sym = ibz2fbz_map(ieq, iq1_ibz, 1) !symmetry
          iq1_fbz = ibz2fbz_map(ieq, iq1_ibz, 2) !image due to symmetry

          !Sum over scattering processes
          do iproc = 1, nprocs
             !Self contribution from plus processes:
             
             !Grab 2nd and 3rd phonons
             call demux_state(istate2_plus(iproc), numbranches, s2, iq2)
             call demux_state(istate3_plus(iproc), numbranches, s3, iq3)

             response_ph_reduce(iq1_fbz, s1, :) = response_ph_reduce(iq1_fbz, s1, :) + &
                  Wp(iproc)*(response_ph(equiv_map(iq1_sym, iq3), s3, :) - &
                  response_ph(equiv_map(iq1_sym, iq2), s2, :))

             !Self contribution from minus processes:
             
             !Grab 2nd and 3rd phonons
             call demux_state(istate2_minus(iproc), numbranches, s2, iq2)
             call demux_state(istate3_minus(iproc), numbranches, s3, iq3)

             response_ph_reduce(iq1_fbz, s1, :) = response_ph_reduce(iq1_fbz, s1, :) + &
                  0.5_dp*Wm(iproc)*(response_ph(equiv_map(iq1_sym, iq3), s3, :) + &
                  response_ph(equiv_map(iq1_sym, iq2), s2, :))
          end do

          !Iterate BTE
          response_ph_reduce(iq1_fbz, s1, :) = field_term(iq1_fbz, s1, :) + &
               response_ph_reduce(iq1_fbz, s1, :)*tau_ibz          
       end do
    end do

    sync all

    !Update the response function
    response_ph(:,:,:) = 0.0_dp
    do im = 1, num_active_images
       response_ph(:,:,:) = response_ph(:,:,:) + response_ph_reduce(:,:,:)[im]
    end do
    sync all
  end subroutine iterate_bte_ph

  !subroutine iterate_bte_el(T, datadumpdir, drag, indexlist, nequiv, equiv_map, &
  !     ibz2fbz_map, rta_rates_ibz, field_term, response_el)
  subroutine iterate_bte_el(T, datadumpdir, drag, el, rta_rates_ibz, field_term, response_el)
    !! Subroutine to iterate the electron BTE one step.
    !! 
    !!
    
    type(electron), intent(in) :: el
    logical, intent(in) :: drag
    !integer(k8), intent(in) :: indexlist(:), nequiv(:), equiv_map(:,:), ibz2fbz_map(:,:,:)
    real(dp), intent(in) :: T, rta_rates_ibz(:,:), field_term(:,:,:)
    real(dp), intent(inout) :: response_el(:,:,:)
    character(len = *), intent(in) :: datadumpdir

    !Local variables
    integer(k8) :: nstates_irred, nprocs, chunk, istate, numbands, numbranches, &
         ik_ibz, m, ieq, ik_sym, ik_fbz, iproc, ikp, n, iq, s, im, nk, &
         num_active_images, aux
    integer(k8), allocatable :: istate_el(:), istate_ph(:), start[:], end[:]
    real(dp) :: tau_ibz
    real(dp), allocatable :: Xplus(:), Xminus(:), response_el_reduce(:,:,:)[:]
    character(len = 1024) :: filepath_Xminus, filepath_Xplus, Xdir, tag

    !Set output directory of transition probilities
    write(tag, "(E9.3)") T
    Xdir = trim(adjustl(datadumpdir))//'X_T'//trim(adjustl(tag))

    !Number of electron bands
    numbands = size(rta_rates_ibz(1,:))

    !Number of in-window FBZ wave vectors
    nk = size(field_term(:,1,1))

    !Total number of IBZ states
    nstates_irred = size(rta_rates_ibz(:,1))*numbands

    !Allocate coarrays
    allocate(start[*], end[*])
    allocate(response_el_reduce(nk, numbands, 3)[*])

    !Initialize coarray
    response_el_reduce(:,:,:) = 0.0_dp
    
    !Divide electron states among images
    call distribute_points(nstates_irred, chunk, start, end, num_active_images)

    !Run over electron IBZ states
    do istate = start, end
       !Demux state index into band (m) and wave vector (ik_ibz) indices
       call demux_state(istate, numbands, m, ik_ibz)

       !Apply energy window to initial (IBZ blocks) electron
       if(abs(el%ens_irred(ik_ibz, m) - el%enref) > el%fsthick) cycle

       !RTA lifetime
       tau_ibz = 0.0_dp
       if(rta_rates_ibz(ik_ibz, m) /= 0.0_dp) then
          tau_ibz = 1.0_dp/rta_rates_ibz(ik_ibz, m)
       end if

       !Set X+ filename
       write(tag, '(I9)') istate
       filepath_Xplus = trim(adjustl(Xdir))//'/Xplus.istate'//trim(adjustl(tag))

       !Read X+ from file
       call read_transition_probs_eph(trim(adjustl(filepath_Xplus)), nprocs, Xplus, &
            istate_el, istate_ph)

       !Set X- filename
       write(tag, '(I9)') istate
       filepath_Xminus = trim(adjustl(Xdir))//'/Xminus.istate'//trim(adjustl(tag))

       !Read X- from file
       call read_transition_probs_eph(trim(adjustl(filepath_Xminus)), nprocs, Xminus)

       !Sum over the number of equivalent q-points of the IBZ point
       do ieq = 1, el%nequiv(ik_ibz)
          ik_sym = el%ibz2fbz_map(ieq, ik_ibz, 1) !symmetry
          !ik_fbz = el%ibz2fbz_map(ieq, ik_ibz, 2) !image due to symmetry
          call binsearch(el%indexlist, el%ibz2fbz_map(ieq, ik_ibz, 2), ik_fbz)

          !Sum over scattering processes
          do iproc = 1, nprocs
             !Self contribution from X+ processes:
             
             !Grab electron and phonon
             call demux_state(istate_el(iproc), numbands, n, ikp)
!!$             !call demux_state(istate_ph(iproc), numbranches, s, iq)

             call binsearch(el%indexlist, el%equiv_map(ik_sym, ikp), aux)
             response_el_reduce(ik_fbz, m, :) = response_el_reduce(ik_fbz, m, :) + &
                  response_el(aux, n, :)*(Xplus(iproc) + Xminus(iproc))
          end do

          !Iterate BTE
          response_el_reduce(ik_fbz, m, :) = field_term(ik_fbz, m, :) + &
               response_el_reduce(ik_fbz, m, :)*tau_ibz
       end do
    end do

    sync all

    !Update the response function
    response_el(:,:,:) = 0.0_dp
    do im = 1, num_active_images
       response_el(:,:,:) = response_el(:,:,:) + response_el_reduce(:,:,:)[im]
    end do
    sync all
  end subroutine iterate_bte_el
end module bte_module
