#!/bin/bash

#===============================================================================
# TITLE    : analysis-interface.sh
# ABSTRACT : A BASH script that validates command line arguments before passing
#            them to BETA and the analysis engine
#
# AUTHOR   : Dennis Aldea <dennis.aldea@gmail.com>
# DATE     : 2017-08-17
#
# LICENSE  : MIT <https://opensource.org/licenses/MIT>
#-------------------------------------------------------------------------------
# SYNOPSIS:
#
#     ghmtools analysis [-f | -i | -n] [-d <binding-distance>] [--no-blacklist]
#         [--window <window-size>] [--] <transcription-data> <binding-data>
#         <genome> <gene-file>
#
# DESCRIPTION:
#
#     -f                     : do not prompt before overwriting files
#     -i                     : prompt before overwriting files (default)
#     -n                     : do not overwrite files
#     -d <binding-distance>  : maximum distance (in kilobases) between a bound
#                              gene and the nearest binding site (default: 10)
#     --no-blacklist         : do not remove common false positive binding sites
#                              from the ChIP-seq data
#     --window=<window-size> : number of genes to be summed to calculate a
#                              binding score (default: 10)
#     <transcription-data>   : filepath of the file containing gene
#                              transcription data
#     <binding-data>         : filepath of the file containing ChIP-seq data or
#                              a list of bound genes
#     <genome>               : genome used by BETA
#                              (options: hg19, hg38, mm9, mm10)
#     <gene-file>            : filepath where the gene activity file will be
#                              saved
#
# NOTES:
#
#     The analysis operation automatically removes common false positive binding
#     sites from the ChIP-seq data. The ENCODE blacklists
#     <https://sites.google.com/site/anshulkundaje/projects/blacklists> are used
#     to identify false positive binding sites. The --no-blacklist option
#     prevents the removal of these blacklisted binding sites.
#
#     It is not necessary to specify whether <binding-data> is a ChIP-seq data
#     file or a list of bound genes, since the analysis interface can determine
#     this automatically.
#===============================================================================

# exit program with error if any command returns an error
set -e

HELP_PROMPT="Type 'ghmtools help analysis' for usage notes"

# define option defaults
f=false
i=false
n=false
d=10
no_blacklist=false
window=10

# use GNU getopt to sort options
set +e
OPT_STRING=`getopt -o +find: -l no-blacklist,window: -n "ERROR" -- "$@"`
if [[ $? -ne 0 ]]; then
    echo "$HELP_PROMPT"
    echo "Try separating options from arguments with --"
    exit 1
fi
eval set -- $OPT_STRING
set -e

# parse sorted options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            f=true;;
        -i)
            i=true;;
        -n)
            n=true;;
        -d)
            d="$2"
            shift;;
        --no-blacklist)
            no_blacklist=true;;
        --window)
            window="$2"
            shift;;
        --)
            # end of options
            shift
            break;;
    esac
    shift
done

# determine overwrite option
if $n; then
    ow_opt="n"
elif $i; then
    ow_opt="i"
elif $f; then
    ow_opt="f"
else
    ow_opt="i"
fi

# determine use blacklist option
if $no_blacklist; then
    use_blacklist=false
else
    use_blacklist=true
fi

# regular expression to match positive numbers
positive_number_regex='^[+]?[0-9]*([.][0-9]+)?$'
# regular expression to match non-negative integers
nonnegative_integer_regex='^[+]?[0-9]+$'

# check that the binding distance is a positive number
if ! [[ $d =~ $positive_number_regex ]]; then
    echo "ERROR: Binding distance is not a positive number ($d)" >&2
    echo "$HELP_PROMPT"
    exit 1
fi
# convert the binding distance from kbp to bp, round to the nearest integer
binding_dist=$(python3 -c "print(round(1000 * $d))")

# check that the window size is a positive integer
if ! [[ $window =~ $nonnegative_integer_regex ]]; then
    echo "ERROR: Window size is not a non-negative integer ($window)" >&2
    echo "$HELP_PROMPT"
    exit 1
fi

# check that the number of arguments is valid
if ! [[ $# -eq 4 ]]; then
    echo "ERROR: Invalid number of arguments" >&2
    echo "$HELP_PROMPT"
    exit 1
fi

# check that the transcription data file is a valid file
if ! [[ -f $1 ]]; then
    if ! [[ -e $1 ]]; then
        echo "ERROR: Transcription data file does not exist ($1)" >&2
    else
        echo "ERROR: Invalid transcription data file ($1)" >&2
    fi
    echo "$HELP_PROMPT"
    exit 1
else
    transcription_path="$1"
fi

# check that the binding data file is a valid file
if ! [[ -f $2 ]]; then
    if ! [[ -e $2 ]]; then
        echo "ERROR: Binding data file does not exist ($2)" >&2
    else
        echo "ERROR: Invalid binding data file ($2)" >&2
    fi
    echo "$HELP_PROMPT"
    exit 1
else
    binding_path="$2"
fi

# check that the genome is a supported genome (i.e. has an associated blacklist)
blacklist=~/.genetic-heatmaps/blacklists/$3.bed
if [[ $blacklist ]]; then
    genome=$3
else
    # exit program with error on invalid genome
    echo "ERROR: Invalid genome ($3)" >&2
    echo "$HELP_PROMPT"
    exit 1
fi

# check that the gene data file does not exist
if [[ -e $4 ]]; then
    # if it does exist, check option to determine whether to prompt user
    case $ow_opt in
        f)
            # do not prompt user, overwrite file
            gene_path="$4";;
        i)
            # prompt user
            echo "WARNING: A file already exists at $4"
            read -p "Type y to overwrite that file, type n to exit: " yn
            if ! [[ $yn == "y" || $yn == "Y" ]]; then
                # do not overwrite file, exit program
                exit
            else
                # overwrite file
                gene_path="$4"
            fi;;
        n)
            # do not prompt user, do not overwrite, exit program with error
            echo "ERROR: A file already exists at $4" >&2
            echo "$HELP_PROMPT"
            exit 1;;
    esac
else
    gene_path="$4"
fi

# create a temporary directory to hold temporary files
temp_dir=$(mktemp -d --tmpdir "$(basename "$0").XXXXXXXXXX")

# create a temporary sub-directory to store parsed data files
mkdir $temp_dir/parsed_data

# remove comments from transcription data file
temp_transcription=$temp_dir/parsed_data/transcription_data
sed '/^#/d' < "$transcription_path" > "$temp_transcription"
# replace spaces with tabs in transcription data file
sed -i "s/ /\t/g" "$temp_transcription"

# remove comments from binding data file
temp_binding_unfiltered=$temp_dir/parsed_data/binding_data_unfiltered
temp_binding=$temp_dir/parsed_data/binding_data
sed '/^#/d' < "$binding_path" > "$temp_binding_unfiltered"
# replace spaces with tabs in binding data file
sed -i "s/ /\t/g" "$temp_binding_unfiltered"

# determine if binding data is a ChIP-seq data file or a bound gene list file
if grep -Pq "\t" "$temp_binding_unfiltered"; then
    if $use_blacklist; then
        # remove all blacklisted binding sites
        bedtools subtract -A -a "$temp_binding_unfiltered" -b "$blacklist" \
            > "$temp_binding"
    fi
    sed '/^#/d' < "$binding_path" > "$temp_binding"
    # replace spaces with tabs in binding data file
    sed -i "s/ /\t/g" "$temp_binding"
    # run the BETA genomic analysis program to generate bound gene list file
    BETA minus -p "$temp_binding" -g $genome -d $binding_dist \
        -o "$temp_dir/BETA_output" --bl > /dev/null
    # remove comments from BETA output file
    sed '/^#/d' < "$temp_dir/BETA_output/NA_targets.txt" > "$temp_binding"
else
    temp_binding=$temp_binding_unfiltered
fi

# pass validated arguments to the analysis engine
~/.genetic-heatmaps/src/analysis-engine.r "$temp_transcription" \
    "$temp_binding" $window "$gene_path"
