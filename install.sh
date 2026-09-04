#!/bin/bash

set -e # exit on error

print_usage_info()
{
    cat <<'EOF'
Caffeine Installation Script

USAGE:
./install.sh [--help | [--prefix=PREFIX]

 --help             Display this help text
 --prefix=PREFIX    Install library into 'PREFIX' directory
                    Default prefix='\$HOME/.local/bin'
 --network=<NET>    Build Caffeine to target given GASNet network conduit. 
                    <NET> should be one of:
                      smp: single-node shared-memory conduit (default)
                      udp: portable UDP/IP (for Ethernet networks)
                      ibv: InfiniBand IB Verbs
                      ofi: OpenFabrics Interfaces
                      ucx: Unified Communication X
 --prereqs          Display a list of prerequisite software.
 --verbose          Show verbose build commands
 --yes              Assume (yes) to all prompts for non-interactive build
 --enable-debug     Build Caffeine and GASNet in LOW-PERFORMANCE debug mode,
                    disabling optimization and enabling assertions to help find defects.
 --enable-threads   Build a thread-safe Caffeine library and link to
                    thread-safe GASNet, for use in threaded do-concurrent.

All unrecognized arguments will be passed to GASNet's configure.

Some influential environment variables:
  FC          Fortran compiler command
  FFLAGS      Fortran compiler flags
  CC          C compiler command
  CFLAGS      C compiler flags
  CPPFLAGS    C preprocessor flags, e.g. -I<include dir> if you have
              headers in a nonstandard directory <include dir>
  LDFLAGS     linker flags, e.g. -L<lib dir> if you have libraries in a
              nonstandard directory <lib dir>
  LIBS        libraries to pass to the linker, e.g. -l<library>
Use these variables to override the choices made by the installer or to help
it to find libraries and programs with nonstandard names/locations.

Report bugs to fortran@lbl.gov or at https://go.lbl.gov/caffeine

EOF
}

GASNET_VERSION="stable"
GASNET_SOURCE_URL="https://github.com/BerkeleyLab/gasnet/releases/download/gex-$GASNET_VERSION/GASNet-$GASNET_VERSION.tar.gz"
ASSERT_GIT=$(awk -F'"' '/^assert =/ {print $2}' manifest/fpm.toml.template)
ASSERT_VERSION=$(awk -F'"' '/^assert =/ {print $4}' manifest/fpm.toml.template)
JULIENNE_GIT=$(awk -F'"' '/^julienne =/ {print $2}' manifest/fpm.toml.template)
JULIENNE_VERSION=$(awk -F'"' '/^julienne =/ {print $4}' manifest/fpm.toml.template)
VERBOSE=""
YES=false
APPEND_CFLAGS=""
APPEND_LDFLAGS=""
# these variables deliberately inherited from the caller environment
GASNET_CONDUIT="${GASNET_CONDUIT:-smp}"
GASNET_THREADMODE="${GASNET_THREADMODE:-seq}"
GASNET_CODEMODE="${GASNET_CODEMODE:-opt}"
GASNET_CONFIGURE_ARGS=${GASNET_CONFIGURE_ARGS:-}


list_prerequisites()
{
    cat << EOF
Caffeine's build system has the following system software prerequisites.
If any are missing and if permission is granted, the installer will install
the latest versions using Homebrew:

  LLVM flang (or another supported Fortran compiler)
  fpm
  pkg-config
  GNU Make
  git + curl (used to download library dependencies)

The installer will also download and build the following library dependencies,
which are installed along with the Caffeine library to the install prefix:

  GASNet-EX $GASNET_VERSION
    - $GASNET_SOURCE_URL
  Assert $ASSERT_VERSION 
    - $ASSERT_GIT
  Julienne $JULIENNE_VERSION (optional, only used for unit tests)
    - $JULIENNE_GIT

EOF
}


# expand to an absolute path for $1, possibly including symlinks
abspath() {
    if [ -z "$1" ]; then
        echo "ERROR: expected a non-empty pathname" >&2
        return 1
    fi

    if [[ "$1" == /* ]] ; then
      echo "$1"
    else
      echo "$PWD/$1"
    fi
}

# like `which` but always returns an absolute path or empty
# If $2 is set then failure is suppressed in the exit code
abswhich() {
    local cmd_path
    if [ -z "$1" ]; then
        echo "ERROR: expected a non-empty pathname" >&2
        return 1
    fi
    cmd_path=$(type -P -- "$1") || return $( [[ -n "${2:-}" ]] )

    echo "$(abspath $cmd_path)"
}

# expand to the absolute path of $1 with all symlinks and non-canonical elements removed
realpath() {
    set +x
    if [ -z "$1" ]; then
        echo "ERROR: expected a non-empty pathname" >&2
        return 1
    fi

    perl -e '
        use Cwd "abs_path";
        my $abs = abs_path($ARGV[0]);
        if (defined $abs) {
            print "$abs\n";
        } else {
            print "ERROR: $ARGV[0] does not exist";
            exit 1;
        }
    ' "$1"
}

append_gasnet_configure_arg() {
  if [[ -z "$GASNET_CONFIGURE_ARGS" ]] ; then
    GASNET_CONFIGURE_ARGS="\"$1\""
  else
    # Quoting is believed sufficient for embedded whitespace but not quotes
    GASNET_CONFIGURE_ARGS+=" \"${1//\"/\\\"}\""
  fi
}

while [ "$1" != "" ]; do
    orig_arg="$1"
    PARAM=$(echo "$1" | awk -F= '{print $1}')
    VALUE=$(echo "$1" | awk -F= '{print $2}')
    case $PARAM in
        -h | --help)
            print_usage_info
            exit
            ;;
        --prereqs)
            list_prerequisites
            exit
            ;;
        --prefix)
            PREFIX=$VALUE
            ;;
        --network)
            GASNET_CONDUIT=$(tr '[:upper:]' '[:lower:]' <<< $VALUE)
            case $GASNET_CONDUIT in
              smp|udp|mpi|ibv|ofi|ucx) ;;
              *) 
                 echo "ERROR: Unrecognized --network=$GASNET_CONDUIT"
                 print_usage_info
                 exit 1
            esac
            ;;
        --verbose)
            VERBOSE="--verbose"
            set -x
            ;;
        -y | --yes)
            YES="true"
            ;;
        --enable-threads)  GASNET_THREADMODE=par ;;
        --disable-threads) GASNET_THREADMODE=seq ;;

        --enable-debug)  GASNET_CODEMODE=debug ; append_gasnet_configure_arg "$orig_arg" ;;
        --disable-debug) GASNET_CODEMODE=opt ;   append_gasnet_configure_arg "$orig_arg" ;;

        *) # Pass unrecognized args unmodified to GASNet configure
            append_gasnet_configure_arg "$orig_arg"
            ;;
    esac
    shift
done

if [[ -n "$VERBOSE" ]] ; then
( set +x
  echo Command-line arguments:
  echo PREFIX=$PREFIX
  echo GASNET_CONDUIT=$GASNET_CONDUIT
  echo GASNET_CONFIGURE_ARGS=$GASNET_CONFIGURE_ARGS
  echo GASNET_THREADMODE=$GASNET_THREADMODE
  echo GASNET_CODEMODE=$GASNET_CODEMODE
)
fi

# Early check for pre-installed Homebrew
BREW="${BREW:-brew}"
if type -P "$BREW" > /dev/null 2>&1; then
  BREW_PREFIX=`$BREW --prefix || exit 0`
  if [ -z ${BREW_PREFIX:+x} ] || [ ! -d "$BREW_PREFIX" ] ; then
    echo Warning: Failed to detect Homebrew prefix
    BREW_PREFIX=
  fi
fi

if [ -z ${FC:+x} ] || [ -z ${CC:+x} ]; then
  if type -P flang > /dev/null 2>&1; then
    FC=$(abswhich flang)
    echo "Setting FC=$FC"
    if [ -n "$BREW_PREFIX" ] && [[ $FC =~ $BREW_PREFIX ]] ; then
      # We are using Homebrew flang, so prefer Homebrew clang/clang++
      export PATH="$BREW_PREFIX/opt/llvm/bin:$PATH"
    fi
  fi
  if type -P clang > /dev/null 2>&1; then
    CC=$(abswhich clang)
    echo "Setting CC=$CC"
  fi
fi
if [ -n "$CC" ] && ! type -P "$CC" > /dev/null 2>&1; then
  echo "CC=$CC not found. If you don't yet have a C compiler, please leave environment variable CC unset."
  exit 1
fi
if [ -n "$FC" ] && ! type -P "$FC" > /dev/null 2>&1; then
  echo "FC=$FC not found. If you don't yet have a Fortran compiler, please leave environment variable FC unset."
  exit 1
fi
if [ -z ${CXX:+x} ] && [ -n "$CC" ] ; then 
  # C++ is an optional dependency
  # try to auto-detect from CC
  if [[ $(basename $CC) =~ clang ]] ; then 
    CXX_guess=clang++
  else
    CXX_guess=g++
  fi
  if [[ $CC =~ (-[0-9a-z-]+)$ ]] ; then 
    CXX_guess=${CXX_guess}${BASH_REMATCH[0]} 
  fi
  if type -P $CXX_guess > /dev/null 2>&1; then
    CXX=$(abswhich $CXX_guess)
    echo "Setting CXX=$CXX"
  fi
fi

set -u # error on use of undefined variable

# find dependencies, which we might need to install
# allow overrides via envvar
PKG_CONFIG=$(abswhich ${PKG_CONFIG:-pkg-config} silent)
  
MAKE=$(abswhich ${MAKE:-gmake} silent) # prefer 'gmake' over 'make'
MAKE=$(abswhich ${MAKE:-make} silent)

FPM=$(abswhich ${FPM:-fpm} silent)

# FPM disallows override of the git command, so don't allow it here either
# Homebrew requires git and curl to operate, so cannot be used to provide them when they are missing
GIT=$(abswhich git silent)
if [[ -z ${GIT:-} ]] ; then
  echo "git not found. Building Caffeine requires fpm, which uses git to download dependencies."
  echo "Please install git, ensure it is in your PATH, and rerun ./install.sh"
  exit 1
fi

# FPM disallows override of the curl command, so don't allow it here either
CURL=$(abswhich curl silent)
if [[ -z ${CURL:-} ]] ; then
  echo "curl not found. Please install curl, ensure it is in your PATH, and rerun ./install.sh"
  exit 1
fi

ask_permission_to_use_homebrew()
{
  cat << EOF

Either one or more of the environment variables FC and CC are unset or
one or more of the following packages are not in the PATH: pkg-config, make, fpm.
If you grant permission to install prerequisites, you will be prompted before each installation.

Press 'Enter' to choose the square-bracketed default answer:
EOF
  printf "Is it ok to use Homebrew to install prerequisite packages? [yes] "
}

ask_permission_to_install_homebrew()
{
  cat << EOF

Homebrew not found. Installing Homebrew requires sudo privileges.
If you grant permission to install Homebrew, you may be prompted to enter your password.

Press 'Enter' to choose the square-bracketed default answer:
EOF
  printf "Is it ok to download and install Homebrew? [yes] "
}

ask_permission_to_install_homebrew_package()
{
  echo ""
  printf "Is it ok to use Homebrew to install $1? [yes] "
}

CI=${CI:-"false"} # GitHub Actions workflows set CI=true

exit_if_user_declines()
{
  if [ $YES = true ]; then 
    echo " 'yes' assumed (--yes option)"
    return
  fi
  if [ $CI = true ]; then 
    echo " 'yes' assumed (GitHub Actions workflow detected)"
    return
  fi
  read answer
  if [ -n "$answer" -a "$answer" != "y" -a "$answer" != "Y" -a "$answer" != "Yes" -a "$answer" != "YES" -a "$answer" != "yes" ]; then
    echo "Installation declined."
    case ${1:-} in  
      *FC*) 
        echo "To use compilers other than Homebrew-installed LLVM flang and clang,"
        echo "please set the FC and CC environment variables and rerun './install.sh'." ;;
      *) 
        echo "Please ensure that $1 is installed and in your PATH and then rerun './install.sh'." ;;
    esac
    echo "Caffeine was not installed." 
    exit 1
  fi
}

DEPENDENCIES_DIR="build/dependencies"
if [ ! -d $DEPENDENCIES_DIR ]; then
  mkdir -p $DEPENDENCIES_DIR
fi

if [ -z ${FC:+x} ] || [ -z ${CC:+x} ] || [ -z ${PKG_CONFIG:+x} ] || [ -z ${MAKE:+x} ] || [ -z ${FPM:+x} ] ; then

  ask_permission_to_use_homebrew 
  exit_if_user_declines "brew"

  if ! type -P $BREW > /dev/null 2>&1; then

    ask_permission_to_install_homebrew
    exit_if_user_declines "brew"

    $CURL -L https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o $DEPENDENCIES_DIR/install-homebrew.sh --create-dirs
    chmod u+x $DEPENDENCIES_DIR/install-homebrew.sh

    if [ -p /dev/stdin ] && [ $CI = false ]; then
	   cat << EOF

ERROR: Pipe detected.  Installing Homebrew requires sudo privileges,
which is unlikely to work if you are installing non-interactively.
To install Caffeine non-interactively, please rerun the Caffeine installer after
executing the following command to install Homebrew:
"./$DEPENDENCIES_DIR/install-homebrew.sh"
EOF
       exit 1
    else
      ./$DEPENDENCIES_DIR/install-homebrew.sh
      rm $DEPENDENCIES_DIR/install-homebrew.sh
    fi

    if [ $(uname) = "Linux" ]; then
      BREW=/home/linuxbrew/.linuxbrew/bin/brew
      eval "$($BREW shellenv)"
    fi
  fi

  BREW_PREFIX=`$BREW --prefix || exit 0`
  if [ -z ${BREW_PREFIX:+x} ] || [ ! -d "$BREW_PREFIX" ] ; then
    echo Failed to detect Homebrew prefix
    echo 1
  fi

  # fetch the latest package definitions:
  $BREW update

  if [ -z ${FC:+x} ] || [ -z ${CC:+x} ] ; then
    ask_permission_to_install_homebrew_package "'llvm' and 'flang'"
    exit_if_user_declines "FC"
    $BREW install llvm flang

    # Homebrew does not inject clang/clang++ into PATH on macOS
    export PATH="$BREW_PREFIX/opt/llvm/bin:$PATH"
    CC="clang"
    CXX="clang++"
    FC="flang-new"
    for tool in CC CXX FC ; do
      if ! type -P ${!tool} > /dev/null 2>&1 ; then
        eval echo ERROR: Failed to detect Homebrew compiler install at ${!tool}
        exit 1
      else
        eval $tool=$(abswhich ${!tool})
      fi
    done
  fi

  if [ -z ${MAKE:+x} ] ; then
    ask_permission_to_install_homebrew_package "'make'"
    exit_if_user_declines "make"
    $BREW install make
    MAKE=$(abswhich gmake)
  fi

  if [ -z ${PKG_CONFIG:+x} ]; then
    ask_permission_to_install_homebrew_package "'pkg-config'"
    exit_if_user_declines "pkg-config"
    $BREW install pkg-config
    PKG_CONFIG=$(abswhich pkg-config)
  fi

  if [ -z ${FPM:+x} ] ; then
    ask_permission_to_install_homebrew_package "'fpm'"
    exit_if_user_declines "fpm"
    $BREW install fpm
    FPM=$(abswhich fpm)
  fi
fi

PREFIX=${PREFIX:-"${HOME}/.local"}
mkdir -p "$PREFIX"
PREFIX=$(abspath "$PREFIX")
echo "PREFIX=$PREFIX"

if [ -z ${PKG_CONFIG_PATH:+x} ]; then
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
else
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
fi
echo "PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
export PKG_CONFIG_PATH

FC="$(abswhich $FC)"
if [[ $(basename $FC) == *flang* ]]; then
  # old versions of fpm rely on basename 'flang-new' to recognize LLVM flang,
  # so look for a corresponding symlink to the same compiler
  TRY_FC=${FC/%flang-[1-9][0-9]/flang-new}
  TRY_FC=${TRY_FC/%flang/flang-new}
  if [[ -x $TRY_FC ]] && [[ $(realpath $TRY_FC) == $(realpath $FC) ]] ; then
    FC="$(abswhich $TRY_FC)"
  fi
fi
CC="$(abswhich $CC)"
CXX="$(abswhich $CXX)"

if [ "${BREW_PREFIX:-unset}" != unset ] ; then
  # fixups necessitated by using Brew flang:
  if [[ $FC =~ flang ]] && [[ $FC =~ $BREW_PREFIX ]] ; then
    # workaround issue #228: clang cannot find Homebrew flang's C header
    APPEND_CFLAGS="-I$(dirname $(find "$BREW_PREFIX/Cellar/flang" -name ISO_Fortran_binding.h | head -1))"

    if [ $(uname) = "Linux" ]; then
      # workaround brew's libflang_rt.runtime.so missing from default linker path on Linux
      APPEND_LDFLAGS="-Wl,-rpath=$(dirname $(find "$BREW_PREFIX/Cellar/flang" -name libflang_rt.runtime.so | head -1))"
    fi
  fi
fi

pkg="gasnet-$GASNET_CONDUIT-$GASNET_THREADMODE"

if ! $PKG_CONFIG $pkg ; then
  GASNET_TAR_FILE="$DEPENDENCIES_DIR/GASNet-$GASNET_VERSION.tar.gz"
  if [ ! -d $DEPENDENCIES_DIR ]; then
    mkdir -pv $DEPENDENCIES_DIR
  fi
  GASNET_DIR=$DEPENDENCIES_DIR/GASNet-$GASNET_VERSION
  if [ -d $GASNET_DIR ]; then
    # clean any existing GASNet build dir we are overwriting
    rm -Rf $GASNET_DIR
  fi
  
  $CURL -L $VERBOSE --retry 10 --retry-all-errors --fail $GASNET_SOURCE_URL -o $GASNET_TAR_FILE
  tar xvzf $GASNET_TAR_FILE -C $DEPENDENCIES_DIR
  
  ( 
      cd $GASNET_DIR
      cmd="set -x ; ./configure --prefix=\"$PREFIX\""
      # user-provided overrides:
      cmd="$cmd $GASNET_CONFIGURE_ARGS"
      # pass-thru compiler settings:
      cmd="$cmd --with-cc=\"$CC\" --with-cxx=\"$CXX\""
      # select the GASNet config settings Caffeine requires, and disable unused features:
      cmd="$cmd --enable-$GASNET_CONDUIT"
      cmd="$cmd --enable-seq --enable-par --disable-parsync"
      cmd="$cmd --disable-segment-everything"
      # TEMPORARY: disable MPI compatibility until we figure out how to support in fpm
      cmd="$cmd --disable-mpi-compat"
      eval $cmd
      $MAKE -j 8 all
      $MAKE -j 8 install
  )
fi # if ! $PKG_CONFIG $pkg ; then

exit_if_pkg_config_pc_file_missing()
{
  if ! $PKG_CONFIG $1 ; then
    echo "$1.pc pkg-config file not found"
    exit 1
  fi
}

exit_if_pkg_config_pc_file_missing "$pkg"

GASNET_LDFLAGS="`$PKG_CONFIG $pkg --variable=GASNET_LDFLAGS`"
GASNET_LIBS="`$PKG_CONFIG $pkg --variable=GASNET_LIBS`"
GASNET_CC="`$PKG_CONFIG $pkg --variable=GASNET_CC`"
GASNET_CFLAGS="`$PKG_CONFIG $pkg --variable=GASNET_CFLAGS`"
GASNET_CPPFLAGS="`$PKG_CONFIG $pkg --variable=GASNET_CPPFLAGS`"

# Check whether GASNet was installed using Spack. If yes, bail out.
# Note: relies on the fact that most Spack installations have "opt/spack"
#       in the directory path, and assumes that the first directory returned
#       by pkg-config contains the GASNet lib directory
GASNET_LIBDIR="$(echo $GASNET_LIBS | awk '{print $1};')"
GASNET_LIBDIR=${GASNET_LIBDIR#-L}
case "$GASNET_LIBDIR" in
  *spack* )
	cat << EOF
***NOTICE***: The GASNet library built by Spack is ONLY intended for
unit-testing purposes, and is generally UNSUITABLE FOR PRODUCTION USE.
The RECOMMENDED way to build GASNet is as an embedded library as configured
by the higher-level client runtime package (i.e. Caffeine), including
system-specific configuration. Exiting install.sh
EOF
    exit 1
    ;;
  * )
    GASNET_PREFIX=$(dirname $GASNET_LIBDIR)
    if [ ! -r "$GASNET_PREFIX/include/gasnetex.h" ] ; then
      echo "ERROR: Failed to detect GASNet install prefix from $GASNET_LIBS"
      exit 1
    fi
    ;; 
esac

# Strip compiler flags
# Warning: This assumes the full path doesn't contain any spaces!
GASNET_CC_STRIPPED="$(echo $GASNET_CC | awk '{print $1};')"
if [ "$(realpath $GASNET_CC_STRIPPED)" != "$(realpath $CC)" ]; then 
  echo "ERROR: C Compiler mismatch: GASNET_CC=$(realpath $GASNET_CC_STRIPPED) and CC=$(realpath $CC) don't match"
  exit 1;
fi

FPM_TOML="fpm.toml"
rm -f $FPM_TOML
echo "# DO NOT EDIT OR COMMIT -- Created by caffeine/install.sh" > $FPM_TOML
cat manifest/fpm.toml.template >> $FPM_TOML
GASNET_LIB_LOCATIONS=`echo $GASNET_LIBS | awk '{locs=""; for(i = 1; i <= NF; i++) if ($i ~ /^-L/) {locs=(locs " " $i);}; print locs; }'`
GASNET_LIB_NAMES=`echo $GASNET_LIBS | awk '{names=""; for(i = 1; i <= NF; i++) if ($i ~ /^-l/) {names=(names " " $i);}; print names; }' | sed 's/-l//g'`
if [[ $GASNET_CONDUIT == "udp" ]] ; then
  GASNET_LIB_NAMES+=" stdc++" # udp-conduit requires C++ libraries
fi
FPM_TOML_LINK_ENTRY="link = [\"$(echo ${GASNET_LIB_NAMES} | sed 's/ /", "/g')\"]"
echo "${FPM_TOML_LINK_ENTRY}" >> $FPM_TOML

CAFFEINE_PC="$PREFIX/lib/pkgconfig/caffeine.pc"
cat << EOF > $CAFFEINE_PC
CAFFEINE_FPM_LDFLAGS=$GASNET_LDFLAGS $GASNET_LIB_LOCATIONS $APPEND_LDFLAGS
CAFFEINE_FPM_FC=$FC
CAFFEINE_FPM_CC=$GASNET_CC
CAFFEINE_FPM_CFLAGS=$GASNET_CFLAGS $GASNET_CPPFLAGS $APPEND_CFLAGS
Name: caffeine
Description: The CoArray Fortran Framework of Efficient Interfaces to Network Environments (Caffeine) implements the Parallel Runtime Interface for Fortran (PRIF), providing runtime support for multi-image features in modern Fortran compilers.
URL: https://go.lbl.gov/caffeine
Version: 0.8.1
EOF

exit_if_pkg_config_pc_file_missing "caffeine"

user_compiler_flags="${CPPFLAGS:-} ${FFLAGS:-}"

# compiler-specific flag defaults
compiler_flag="-g"
compiler_flag_debug="-O0"
compiler_flag_opt="-O3"
compiler_version=$($FC --version)
if [[ $compiler_version =~ 'flang' ]]; then
  : # use defaults
elif [[ $compiler_version =~ 'GNU Fortran' ]]; then
  compiler_flag="-g -ffree-line-length-0 -Wno-unused-dummy-argument"
elif [[ $compiler_version =~ 'LFortran' ]]; then
  compiler_flag="--cpp --realloc-lhs-arrays --separate-compilation --no-style-suggestions --implicit-argument-casting"
  compiler_flag_debug="" # LFortran -g not always available and leads to bizarre errors when it's not
else # unknown compiler
  compiler_flag_opt=-O2
  echo "WARNING: Failed to detect a recognized Fortran compiler"
fi
if [[ "$GASNET_CODEMODE" == "debug" ]] ; then 
  compiler_flag="$compiler_flag_debug $compiler_flag"
else
  compiler_flag="$compiler_flag_opt $compiler_flag"
fi

# enable Assert's multi-image support with PRIF callbacks provided by libcaffeine
compiler_flag+=" -DASSERT_MULTI_IMAGE -DASSERT_PARALLEL_CALLBACKS"
# enable Julienne's multi-image support with PRIF callbacks provided by julienne-driver
compiler_flag+=" -DHAVE_MULTI_IMAGE_SUPPORT -DJULIENNE_PARALLEL_CALLBACKS"

if ! [[ "$user_compiler_flags " =~ -[DU]ASSERTIONS[=\ ] ]] ; then 
  # assertions not explicitly enabled or disabled on the command-line
  # default assertions based on codemode (--enable-debug)
  if [[ "$GASNET_CODEMODE" == "debug" ]] ; then 
    compiler_flag+=" -DASSERTIONS"
  fi
fi

if [[ $GASNET_THREADMODE == "par" ]] ; then
  compiler_flag+=" -DCAF_THREAD_SAFE"
fi

GASNET_CONDUIT_UPPER=$(tr '[:lower:]' '[:upper:]' <<<$GASNET_CONDUIT)
compiler_flag+=" -DCAF_NETWORK_$GASNET_CONDUIT_UPPER"

# Should come last to allow command-line overrides
compiler_flag+=" $user_compiler_flags"

# Ensure that certain preprocessor settings in FFLAGS are always appended to CFLAGS
APPEND_CFLAGS=""
for opt in $compiler_flag; do
  case "$opt" in
    -DASSERTIONS* | -UASSERTIONS* | -DFORCE_PRIF_* | -UFORCE_PRIF_*)
       APPEND_CFLAGS+=" $opt"
       ;;
  esac
done

case $GASNET_CONDUIT in
  ibv|ofi|ucx) 
    GASNET_RUNNER_ARG="${GASNET_RUNNER_ARG:-$GASNET_PREFIX/bin/gasnetrun_$GASNET_CONDUIT -n \${CAF_IMAGES:-2}}"
  ;;
  udp)
    GASNET_RUNNER_ARG="${GASNET_RUNNER_ARG:-$GASNET_PREFIX/bin/amudprun -n \${CAF_IMAGES:-2}}"
  ;;
  mpi)
    GASNET_RUNNER_ARG="${GASNET_RUNNER_ARG:-mpirun -n \${CAF_IMAGES:-2}}"
  ;;
  smp)
    GASNET_RUNNER_ARG="${GASNET_RUNNER_ARG:-env GASNET_PSHM_NODES=\${CAF_IMAGES:-\${GASNET_PSHM_NODES:-}}}"
  ;;
  *)
    GASNET_RUNNER_ARG="${GASNET_RUNNER_ARG:-}"
  ;;
esac

RUN_FPM_SH="run-fpm.sh"
cat << EOF > $RUN_FPM_SH
#!/bin/bash
#-- DO NOT EDIT -- created by caffeine/install.sh
FPM="${FPM}"
FC="`$PKG_CONFIG caffeine --variable=CAFFEINE_FPM_FC`"
CC="`$PKG_CONFIG caffeine --variable=CAFFEINE_FPM_CC`"
NATIVEFLAGS=""
RAWFLAGS="$compiler_flag"
FFLAGS="\$NATIVEFLAGS \$RAWFLAGS"
CFLAGS="`$PKG_CONFIG caffeine --variable=CAFFEINE_FPM_CFLAGS` $APPEND_CFLAGS"
LDFLAGS="`$PKG_CONFIG caffeine --variable=CAFFEINE_FPM_LDFLAGS`"
FPM_DRIVER=\${FPM_DRIVER:-\$([[ "\$0" == /* ]] && echo "\$0" || echo "\$PWD/\$0")}
export FPM_DRIVER
fpm_sub_cmd=\$1; shift
if echo "--help -help --version -version --list -list new update list clean publish" | grep -w -q -e "\$fpm_sub_cmd" ; then
  set -x
  exec "\$FPM" "\$fpm_sub_cmd" "\$@"
elif echo "build test run install" | grep -w -q -e "\$fpm_sub_cmd" ; then
  sed -i.bak 's/^link = .*\$/$FPM_TOML_LINK_ENTRY/' $FPM_TOML
  rm -f $FPM_TOML.bak # issue 282: this is the only portable way to use sed -i
  if test -n "$GASNET_RUNNER_ARG" && echo "test run" | grep -w -q -e "\$fpm_sub_cmd" ; then
    set -- "--runner=$GASNET_RUNNER_ARG" "\$@"
  fi
  set -x
  exec "\$FPM" "\$fpm_sub_cmd" \\
  --profile debug \\
  --compiler "\$FC" \\
  --flag "\$FFLAGS" \\
  --c-compiler "\$CC" \\
  --c-flag "\$CFLAGS" \\
  --link-flag "\$LDFLAGS" \\
  "\$@"
elif echo "set-native" | grep -w -q -e "\$fpm_sub_cmd" ; then
  set -e
  mkdir -p build
  cmd="\$FC \$RAWFLAGS app/print-native-flags.F90 -o build/print-native-flags $APPEND_LDFLAGS"
  eval \$cmd || (set -x ; eval \$cmd)
  NATIVEFLAGS="\`build/print-native-flags\`"
  rm -f build/print-native-flags
  sed -i.bak 's/^NATIVEFLAGS=.*\$/NATIVEFLAGS="'"\$NATIVEFLAGS"'"/' \$FPM_DRIVER
  rm -f \$FPM_DRIVER.bak
  echo NATIVEFLAGS=\"\$NATIVEFLAGS\"
elif echo "info" | grep -w -q -e "\$fpm_sub_cmd" ; then
  LINE=--------------------------------------------------
  SRCDIR=\$(dirname \$FPM_DRIVER)
  GASNETDIR="$GASNET_PREFIX"
  GASNETCONFIG="\$GASNETDIR/include/gasnet_config.h"
  echo \$LINE
  echo Version info:
  echo Caffeine \$(grep version \$SRCDIR/fpm.toml)
  if test -d \$SRCDIR/.git ; then
    GITVER=\$( ( cd \$SRCDIR && git describe --long --dirty --always ) 2> /dev/null)
    if test -n "\$GITVER"; then
      echo "  git describe: \$GITVER"
    fi
  fi
  if test -r "\$GASNETCONFIG"; then
    echo GASNet version \$(grep GASNETI_RELEASE_VERSION \$GASNETCONFIG | cut -d' ' -f3-)
  fi
  grep -e assert -e julienne \$SRCDIR/fpm.toml
  echo \$LINE
  echo Platform info:
  uname -a
  if test -r /etc/os-release ; then grep -e NAME -e VERSION /etc/os-release  ; fi
  if test -x /usr/bin/sw_vers ; then /usr/bin/sw_vers ; fi
  echo \$LINE
  echo Install settings:
  echo ID="\$(date) \$(whoami)"
  echo PREFIX=$PREFIX
  echo FPM=\$FPM
  echo FC=\$FC
  echo CC=\$CC
  echo FFLAGS=\$FFLAGS
  echo CFLAGS=\$CFLAGS
  echo LDFLAGS=\$LDFLAGS
  grep -e link \$SRCDIR/fpm.toml
  echo GASNET=\$GASNETDIR
  echo GASNET_CONDUIT=$GASNET_CONDUIT
  echo GASNET_CODEMODE=$GASNET_CODEMODE
  echo GASNET_THREADMODE=$GASNET_THREADMODE
  if test -r "\$GASNETCONFIG"; then
    grep -e GASNETI_BUILD_ID -e GASNETI_CONFIGURE_ARGS \$GASNETCONFIG | cut -d' ' -f2-
  fi
  for tool in FPM FC CC ; do
    echo \$LINE
    eval toolval="\\$\$tool"
    echo \$tool : \$toolval
    # strip off any arguments that might be embedded:
    toolval=\$(echo \$toolval | cut -d' ' -f1)
    eval /bin/ls -al \$toolval
    eval /bin/ls -alhL \$toolval
    \$toolval --version
  done
  echo \$LINE
else
  echo "ERROR: Unrecognized fpm subcommand \$fpm_sub_cmd"
  \$FPM list
  exit 1
fi
EOF
chmod u+x $RUN_FPM_SH
# for backwards-compatibility of instructions/scripting:
( cd build && ln -f -s ../$RUN_FPM_SH run-fpm.sh )

./$RUN_FPM_SH set-native

./$RUN_FPM_SH build $VERBOSE || \
( set +x
  echo "Defect reporting information:"
  ./$RUN_FPM_SH info
  echo
  echo Oh no, the Caffeine build appears to have failed!
  echo Please paste the ENTIRE output above into a new issue here:
  echo "   https://github.com/berkeleylab/caffeine/issues"
  exit 1
)

LIBCAFFEINE_DST=libcaffeine-$GASNET_CONDUIT-$GASNET_THREADMODE.a
LIBCAFFEINE_SRC=$(./$RUN_FPM_SH install --list 2>/dev/null | grep libcaffeine | cut -d' ' -f2)

if [ -z "$LIBCAFFEINE_SRC" ]; then
  echo "ERROR: Failed to detect libcaffeine.a from fpm"
  exit 1
else
  mkdir -p "$PREFIX/lib"
  cp -af "$LIBCAFFEINE_SRC" "$PREFIX/lib/$LIBCAFFEINE_DST"
  ln -sf "$LIBCAFFEINE_DST" "$PREFIX/lib/libcaffeine-$GASNET_CONDUIT.a"
  ln -sf "$LIBCAFFEINE_DST" "$PREFIX/lib/libcaffeine.a"
fi

mkdir -p "$PREFIX/share/caffeine"
./$RUN_FPM_SH info > "$PREFIX/share/caffeine/caffeine-info-$GASNET_CONDUIT-$GASNET_THREADMODE.txt"

cat << EOF

________________ Caffeine has been dispensed! ________________

Caffeine is now installed in $PREFIX

To rebuild or to run tests or examples via the Fortran Package
Manager (fpm) with the required compiler/linker flags, pass a
fpm command to the run-fpm.sh script. For example, run
the program example/hello.f90 as follows:

./$RUN_FPM_SH run --example hello
EOF
