! this file is used by install.sh to default PRIF revision forces
#if __LFORTRAN__
# if __LFORTRAN_PRIF_REV__
   -DFORCE_PRIF_REV=__LFORTRAN_PRIF_REV__
# elif __LFORTRAN_MAJOR__ == 0 && __LFORTRAN_MINOR__ <= 69
   !  PRIF 0.9 prif_init change broke backwards-compat for LFortran <= 0.69, these need 0.8
   -DFORCE_PRIF_REV=8
# endif
#endif
