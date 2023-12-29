!
!     (c) 2019-2020 Guide Star Engineering, LLC
!     This Software was developed for the US Nuclear Regulatory Commission (US NRC) under contract
!     "Multi-Dimensional Physics Implementation into Fuel Analysis under Steady-state and Transients (FAST)",
!     contract # NRC-HQ-60-17-C-0007
!
submodule(caffeine_assert_m) caffeine_assert_s
  use iso_c_binding, only: c_bool
  implicit none

contains

  module procedure assert
    use caffeine_characterizable_m, only : characterizable_t
    use program_termination_m, only: prif_error_stop
    use image_queries_m, only: this_image => prif_this_image

    character(len=:), allocatable :: header, trailer
    integer :: me

    toggle_assertions: &
    if (enforce_assertions) then

      check_assertion: &
      if (.not. assertion) then

        call this_image(image_index=me)
        header = 'Assertion "' // description // '" failed on image ' // string(me)

        represent_diagnostics_as_string: &
        if (.not. present(diagnostic_data)) then

          trailer = "(none provided)"

        else

          select type(diagnostic_data)
            type is(character(len=*))
              trailer = diagnostic_data
            type is(complex)
              trailer = string(diagnostic_data)
            type is(integer)
              trailer = string(diagnostic_data)
            type is(logical)
              trailer = string(diagnostic_data)
            type is(real)
              trailer = string(diagnostic_data)
            class is(characterizable_t)
              trailer = diagnostic_data%as_character()
            class default
              trailer = "of unsupported type."
          end select

        end if represent_diagnostics_as_string

        call prif_error_stop(.false._c_bool, stop_code_char=header // ' with diagnostic data "' // trailer // '"')

      end if check_assertion

    end if toggle_assertions

  contains

    pure function string(numeric) result(number_as_string)
      !! Result is a string represention of the numeric argument
      class(*), intent(in) :: numeric
      integer, parameter :: max_len=128
      character(len=max_len) :: untrimmed_string
      character(len=:), allocatable :: number_as_string

      select type(numeric)
        type is(complex)
          write(untrimmed_string, *) numeric
        type is(integer)
          write(untrimmed_string, *) numeric
        type is(logical)
          write(untrimmed_string, *) numeric
        type is(real)
          write(untrimmed_string, *) numeric
        class default
          call prif_error_stop(.false._c_bool, &
            stop_code_char="Internal error in subroutine 'assert': unsupported type in function 'string'.")
      end select

      number_as_string = trim(adjustl(untrimmed_string))

    end function string

  end procedure

end submodule
