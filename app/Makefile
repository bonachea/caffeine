# This Makefile is for internal testing use only and not intended for end-users
# To run this test with Caffeine, please execute `./run-fpm.sh run` in the top-level directory

# overridable settings
export NAGFORTRAN_NUM_IMAGES?=4
export GFORTRAN_NUM_IMAGES?=4
FLAGS=
NATIVE_FLAGS=$$($(MAKE) --no-print-directory print-flags FC=$$FC)
GFORTRAN=gfortran

# ----------------------------------------------------------------

all: gcc

print-flags:
	@$$FC print-native-flags.F90 -o print-native-flags
	@./print-native-flags -s
	@rm -f print-native-flags

nag:
	@set -x ; \
	export FC=nagfor ; \
	export NATIVE_FLAGS="$(NATIVE_FLAGS)" && \
	$(GFORTRAN) -E -DNAGFOR $$NATIVE_FLAGS $(FLAGS) \
	    native-multi-image.F90 > native-multi-image.i.F90 && \
	$$FC -u -g -coarray native-multi-image.i.F90 -o native-multi-image-nag
	@rm -f native-multi-image.i.F90
	env NAGFORTRAN_NUM_IMAGES=$(NAGFORTRAN_NUM_IMAGES) ./native-multi-image-nag

gcc:
	@set -x ; \
	export FC=$(GFORTRAN) ; \
	export NATIVE_FLAGS="$(NATIVE_FLAGS)" && \
	$$FC -g -fcoarray=lib $$NATIVE_FLAGS $(FLAGS) \
	    native-multi-image.F90 -o native-multi-image-gcc -lcaf_shmem
	env GFORTRAN_NUM_IMAGES=$(GFORTRAN_NUM_IMAGES) ./native-multi-image-gcc

clean:
	rm -f *.mod *.i.F90 native-multi-image-nag native-multi-image-gcc

.PHONY: nag gcc clean
