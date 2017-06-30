#!/bin/bash

#===============================================================================
# TITLE    : help-interface.sh
# ABSTRACT : A BASH script that displays help messages
#
# AUTHOR   : Dennis Aldea <dennis.aldea@gmail.com>
# DATE     : 2017-06-29
#
# LICENCE  : MIT <https://opensource.org/licenses/MIT>
#===============================================================================

HELP_PROMPT="Type 'gmtools help' for usage notes."

# check that only 0 or 1 arguments were passed
if ! [[ $# -le 1 ]]; then
    echo "ERROR: Invalid number of arguments" >&2
    echo "$HELP_PROMPT"
    exit 1
fi

if [[ $1 ]]; then
    filename=$1
else
    # if no particular help message was requested, display a list of operations
    filename="operations"
fi

# search for help message in HELP directory
filepath=~/.genetic-heatmaps/HELP/${filename}

# check that help message exists
if ! [[ -f $filepath ]]; then
    echo "ERROR: Invalid operation ($filename)" >&2
    echo "$HELP_PROMPT"
    exit 1
fi

# display help message
cat $filepath