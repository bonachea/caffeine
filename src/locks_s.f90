! Copyright (c), The Regents of the University of California
! Terms of use are as specified in LICENSE.txt
submodule(locks_m) locks_s

  implicit none

contains

  module procedure prif_lock
  end procedure

  module procedure prif_unlock
  end procedure

end submodule locks_s
