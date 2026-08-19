# This Makefile is for internal testing use only and not intended for end-users
# To run this test with Caffeine, please execute `./run-fpm.sh run` in the top-level directory

# overridable settings
NUM_IMAGES?=4
FLAGS=
NATIVE_FLAGS=$$($(MAKE) --no-print-directory print-flags FC=$$FC)
GFORTRAN=gfortran
FC_FORCE=

# ----------------------------------------------------------------

SHELL = bash

all: gcc

print-flags:
	@$$FC print-native-flags.F90 -o print-native-flags
	@./print-native-flags -s
	@rm -f print-native-flags

gcc:
	@set -x ; \
	export FC=$(if $(FC_FORCE),$(FC_FORCE),$(GFORTRAN)) ; \
	export NATIVE_FLAGS="$(NATIVE_FLAGS)" && \
	$$FC -g -fcoarray=lib $$NATIVE_FLAGS $(FLAGS) \
	    native-multi-image.F90 -o native-multi-image-gcc -lcaf_shmem
	env GFORTRAN_NUM_IMAGES=$(NUM_IMAGES) ./native-multi-image-gcc

nag:
	@set -x ; \
	export FC=$(if $(FC_FORCE),$(FC_FORCE),nagfor) ; \
	export NATIVE_FLAGS="$(NATIVE_FLAGS)" && \
	$(GFORTRAN) -E -DNAGFOR $$NATIVE_FLAGS $(FLAGS) \
	    native-multi-image.F90 > native-multi-image.i.F90 && \
	$$FC -u -g -coarray native-multi-image.i.F90 -o native-multi-image-nag
	@rm -f native-multi-image.i.F90
	env NAGFORTRAN_NUM_IMAGES=$(NUM_IMAGES) ./native-multi-image-nag

cce:
	@set -x ; \
	export FC=$(if $(FC_FORCE),$(FC_FORCE),ftn) ; \
	export NATIVE_FLAGS="$(NATIVE_FLAGS)" && \
	$$FC -g -hcaf -O0 $$NATIVE_FLAGS $(FLAGS) \
	    native-multi-image.F90 -o native-multi-image-cce
	./native-multi-image-cce
	srun -n $(NUM_IMAGES) ./native-multi-image-cce

intel:
	@set -x ; \
	export FC=$(if $(FC_FORCE),$(FC_FORCE),ifx) ; \
	export NATIVE_FLAGS="$(NATIVE_FLAGS)" && \
	$$FC -g -coarray -O0 $$NATIVE_FLAGS $(FLAGS) \
	    native-multi-image.F90 -o native-multi-image-intel
	env FOR_COARRAY_NUM_IMAGES=$(NUM_IMAGES) ./native-multi-image-intel

clean:
	rm -f *.mod *.i.F90 native-multi-image-{gcc,nag,cce,intel}

.PHONY: nag gcc clean
