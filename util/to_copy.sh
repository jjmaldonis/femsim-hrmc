#!/bin/bash

# This file will create directories for running models multiple times.
# The seeds are changed automatically but you may want to do them by hand.
# Copy this file above the hrmc directory then chmod and run it.
# You are expected to have the setup for your specific instance set up in hrmc/.
# You will have to change file names in this file to copy the correct ones.

# Make 10 directories, from 0 to 9.
for i in `seq 0 9`;
do
    echo r$i
    # If the run directory doesn't exist, make one.
    if [ ! -d "r$i" ]; then
        mkdir r$i
    fi
    if [ ! -d "r$i/models" ]; then
        mkdir r$i/models
    fi
    if [ ! -d "r$i/data" ]; then
        mkdir r$i/data
    fi
    if [ ! -d "r$i/parameters" ]; then
        mkdir r$i/parameters
    fi
    if [ ! -d "r$i/potentials" ]; then
        mkdir r$i/potentials
    fi
    if [ ! -d "r$i/potentials/reformatted" ]; then
        mkdir r$i/potentials/reformatted
    fi
    if [ ! -d "r$i/submits" ]; then
        mkdir r$i/submits
    fi

    # Copy in the paramfile and change the seed.
    cp femsim-hrmc/parameters/hrmc.in r$i/parameters/
    sed -i "10s/.*/$((10470+$i))           # seed/" r$i/parameters/hrmc.in

    # Copy the eam file, fem file, and starting modelfile
    cp femsim-hrmc/potentials/reformatted/NiP.lammps.eam r$i/potentials/reformatted/
    cp femsim-hrmc/models/Ni80P20_1586atoms_hrmc_start.xyz r$i/models/
    cp femsim-hrmc/data/Ni80P20_data_t*_half.txt r$i/data/

    # Copy the submit files we need
    cp femsim-hrmc/submits/slurm_submit.py r$i/submits/
    cp femsim-hrmc/submits/slurm.sh r$i/submits/

    # Symbolic link to hrmc/hrmc -- don't forget to make it!
    if [ ! -h "r$i/hrmc" ]; then
        ln -s /work/02916/maldonis/Ni80P20/t1/femsim-hrmc/hrmc r$i/hrmc
    fi
done

