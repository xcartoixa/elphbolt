! Copyright (C) 2020- Nakib Haider Protik <nakib.haider.protik@gmail.com>
! This file is part of elphbolt <https://github.com/nakib/elphbolt>.
!
! elphbolt is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! elphbolt is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with elphbolt. If not, see <http://www.gnu.org/licenses/>.

module params
  !! Module containing various parameters and constants.
  
  implicit none

  integer, parameter :: r_int = 12
  !! Exponent range for reals.
  integer, parameter :: r_real = 200
  !! Exponent range for reals.
  integer, parameter :: p_real = 14
  !! Number of digits for reals.
  integer, parameter :: dp = selected_real_kind(p_real, r_real)
  !! Custom real precision.
  integer, parameter :: k8 = selected_int_kind(r_int)
  !! Custom integer precision.

  !Physical constants:
  real(dp), parameter :: qe = 1.602176634e-19_dp
  !! Electron charge magnitude (C)
  real(dp), parameter :: me = 9.1093837015e-31_dp
  !! Electron mass (Kg)
  real(dp), parameter :: amu = 1.66053906660e-27_dp
  !! Atomic mass unit (Kg)
  real(dp), parameter :: hbar = 1.05457172647e-22_dp
  !! Reduced Planck's constant (J/THz = J.ps)
  real(dp), parameter :: hbar_eVps = hbar/qe
  !! Reduced Planck's constant (eV/THz = eV.ps)
  real(dp), parameter :: perm0 =  8.854187817e-12_dp
  !! Permittivity of free space (F/m)
  real(dp), parameter :: kB = 1.380649e-23_dp/qe
  !! Boltzmann constant (eV/K)
  real(dp), parameter :: pi = 4.0_dp*atan(1.0_dp)
  !! Value of pi
  real(dp), parameter :: twopi = 2.0_dp*pi
  !! Value of 2pi

  !Conversion factors:
  real(dp), parameter :: Hartree2radTHz = 27.2116_dp*qe/hbar !Hartree to rad.THz
  real(dp), parameter :: Hartree2eV = 27.2116_dp !Hartree to eV
  real(dp), parameter :: Ryd2radTHz = 0.5_dp*Hartree2radTHz !Rydberg to rad.THz
  real(dp), parameter :: Ryd2eV = 0.5_dp*Hartree2eV !Rydberg to eV
  real(dp), parameter :: Ryd2meV = Ryd2eV*1.0e3_dp !Rydberg to meV
  real(dp), parameter :: Ryd2amu = 2.0_dp*me/amu !Rydberg mass to amu
  real(dp), parameter :: bohr2nm=0.052917721092_dp !Bohr to nm
  
  !Miscellaneous
  complex(dp), parameter :: oneI = (0.0_dp,1.0_dp)
  complex(dp), parameter :: twopiI = twopi*oneI

  !The code below is adapted from ShengBTE (file data.f90):
  
  !Periodic table from ShengBTE
  character(len = 3), parameter :: periodic_table(114)=[character(len=3) :: &
       "H","He","Li","Be","B","C","N","O", &
       "F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca","Sc","Ti","V", &
       "Cr","Mn","Fe","Co","Ni","Cu","Zn","Ga","Ge","As","Se","Br","Kr","Rb", &
       "Sr","Y","Zr","Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn","Sb", &
       "Te","I","Xe","Cs","Ba","La","Ce","Pr","Nd","Pm","Sm","Eu","Gd","Tb", &
       "Dy","Ho","Er","Tm","Yb","Lu","Hf","Ta","W","Re","Os","Ir","Pt","Au","Hg", &
       "Tl","Pb","Bi","Po","At","Rn","Fr","Ra","Ac","Th","Pa","U","Np","Pu","Am", &
       "Cm","Bk","Cf","Es","Fm","Md","No","Lr","Rf","Db","Sg","Bh","Hs","Mt","Ds" ,&
       "Rg","Cn","Uuq","Uuh"]
end module params
