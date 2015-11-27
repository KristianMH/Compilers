#!/bin/sh
#
# Compile and run a FASTO program.  This script should work on Linux, Mac, and
# Windows under Cygwin.
#
# Your Mars4_5.jar simulator must be in your FASTO "bin" directory, or you must
# export its location into an environment variable MARS.
#
# Usage: ./quickrun.sh [-o] FASTO_PROGRAM

set -e # Exit on first error.

base_dir="$(dirname "$0")"

if [ "$1" = -o ]; then
    flags=-o
    shift
else
    flags=-c
fi

prog_input="$1"

if ! [ "$MARS" ]; then
    MARS="$base_dir/../bin/Mars4_5.jar"
    if [ $(uname -o 2> /dev/null) = "Cygwin" ]; then
        MARS="$(cygpath -w "$MARS")"
    fi
fi

# Compile.
"$base_dir/../bin/fasto" $flags "$1"

# Run.
java -jar "$MARS" nc \
     "$(dirname "$prog_input")/$(basename "$prog_input" .fo).asm" 2> /dev/null
