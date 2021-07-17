![elphbolt logo](./logo/elphbolt_logo.png)
# elphbolt
`elphbolt` (short for **el**ectron-**ph**onon **Bol**tzmann **t**ransport) is a modern Fortran (2018 standard) code for solving the coupled electron and phonon Boltzmann transport equations (BTEs). It is a "free as in freedom" code distributed under the GNU Public License (GPL) version 3. You can read more about the philosophy of software freedom [here](https://www.gnu.org/philosophy/free-sw.en.html).

Using *ab initio* electron-phonon and phonon-phonon interactions and a fully wave vector and electron band/phonon branch resolved formulation of the BTEs, `elphbolt` can calculate the

- phonon and electronic thermal conductivities;
- electronic conductivity;
- phonon and electronic contributions to the thermopower; and
- effect of the mutual electron-phonon drag on the transport coefficients listed above.

Stylistically, it is designed to be simple, small, fast, and extensible. Object oriented programming concepts are combined with the procedural style, which allows fast development, while resulting in a rather compact code. The symmetries of the crystal are fully exploited and the transport active Fermi window is used to allow the sampling of extremely fine wave vector meshes needed for an accurate solution of the BTEs. Parallelism is achieved through modern Fortran's intrinsic `coarrays` feature that is fully supported by recent versions of both the `gcc` and `intel` compilers.

`elphbolt` currently interfaces with the `Quantum Espresso` suite for the phonon quantities and the `EPW` code for the Wannier space information.

The project is currently in the beta phase and being used to do publication level calculations.

## Installation on HPC systems with `gcc`

### 1. Get `spglib`

`elphbolt` uses the [`spglib`](https://spglib.github.io/spglib/) library for crystal symmetry analysis. Currently, versions 1.6.0 and 1.14.1 have been tried and tested. A lot of HPCs provide this library as a module, so check before building from source.

### 2. Get `OpenCoarrays`

[`OpenCoarrays`](http://www.opencoarrays.org/) is an implementation of the `coarrays` functionalities. Some HPC systems include it (for example MareNostrum4 and, more recently, LaPalma of the Barcelona Supercomputing Center (BSC)). In that case, load it. If not, you can build it from source. I was able to build version 2.0.0 on the LaPalma system of BSC by first loading `gcc`, `openmpi`, and `cmake`, then going into the `OpenCoarrays-2.0.0` directory and saying `./install.sh`. The executables `caf` and `cafrun` were then installed in `~/OpenCoarrays-2.0.0/prerequisites/installations/bin/`. I added the above directory to my `$PATH` in my `bashrc`.

On the Sirius cluster of Boston College, I was able to build version 2.9.2 by first loading `gnu_gcc/9.2.0`, `openmpi/4.0.5gcc9.2.0`, and `cmake/3.18.4`, then going into the `OpenCoarrays-2.9.2` directory and saying `./install.sh --with-fortran /usr/public/gnu_gcc/9.2.0/bin/gfortran --with-cxx /usr/public/gnu_gcc/9.2.0/bin/g++ --with-c /usr/public/gnu_gcc/9.2.0/bin/gcc --with-mpi /usr/public/openmpi/4.0.5gcc.9.2.0/ --with-cmake /usr/public/cmake/3.18.4/bin/cmake`. The executables `caf` and `cafrun` were then installed in `~/OpenCoarrays-2.9.2/prerequisites/installations/opencoarrays/2.9.2/bin/`. I added the above directory to my `$PATH` in my `bashrc`.

(You can change the build path with the additional argument `--install-prefix <path to build directory>` to `install.sh`.)

### 3. Create your `<title>.make` file

In the `elphbolt` src directory you will find a few `<title>.make` files. Adapt them to your own architecture. Then, in the `Makefile` include your personal `<title>.make` file at the top, commenting out any exiting one.

Once you have done the above, simply say `make`. This should build the executable `elphbolt.x` one directory above.

## Installation on HPC systems with `intel`

[Working on it.]

## Singularity image

[Considering it.]

## Tests

[Working on it.]

## Workflow

This is a transport code. And it comes after doing some DFT, DFPT, and Wannier calculations. The following quantities are the inputs for a calculation with `elphbolt`:

### Input file [required]

The input file - `input.nml` - contains the information about the crystal and the various parameters of the calculation. A full description of all the input parameters will be provided soon in the documentation. I will also provide example input files for the test materials.

### Second order interatomic force constants [required]

This comes out of the usual `ph.x` and `q2r.x` calculation from `Quantum Espresso`. This file is needed to calculate phonon quantities and must be named `espresso.ifc2`.

### Third order interatomic force constants [optional]

This file, which must be named `FORCE_CONSTANTS_3RD`, is needed to calculate the 3-ph scattering rates. This is a required file if you seek a solution of the decoupled phonon BTE or the coupled electron-phonon BTEs.

This must be provided for a solution to the phonon BTE or the coupled electron-phonon BTEs. See documentation for the code [`thirdorder.py`](https://bitbucket.org/sousaw/thirdorder/src/master/) (companion of `ShengBTE`) for how to generate this file.

### Wannier space information [optional]

These are required if you want to solve a decoupled electron BTE, include phonon-electron interaction in the decoupled phonon BTE, or solve the coupled electron-phonon BTEs.

These include the files `rcells_k`, `rcells_q`, `rcells_g`, `wsdeg_k`, `wsdeg_q`, and `wsdeg_g` which must be printed out of an `EPW` calculation. I will provide a patched `EPW/src/ephwann_shuffle.f90` code which will print these quantities out during `EPW`'s Bloch -> Wannier calculation step.

We will also need the files `epmatwp1` and `epwdata.fmt`, both of which are outputted by `EPW` after the Bloch -> Wannier calculation step. The first contains the Wannier space electron-phonon matrix elements and the second contains the Wannier space dynamical matrix and Hamiltonian. The third line of this file contains the Born effective charge and the dielectric tensors. For an `intel` build of `EPW` this line is broken over multiple lines. This is not the case for a `gcc` build of `EPW`. `elphbolt` requires that there are no line breaks. So before passing this file in to `elphbolt`, fix the line break issue if you generated this file using an `intel` build of `EPW`. I am thinking about how to natively handle this from within `elphbolt`.

### High symmetry **q**/**k**-path and initial **k**-vector [optional]

You need to provide a **q**/**k**-path file named `highsympath.txt` and an initial **k**-vector file named `initialk.txt` if you want the phonon dispersions, electron bands, and electron-phonon matrix elements calculated along a high-symmetry path.
