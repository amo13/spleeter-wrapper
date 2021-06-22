#!/bin/bash

#     A script for using spleeter with audio of any length
#     and with limited RAM on the processing machine
#
#     Original author:    Amaury Bodet
#     Contributor(s):     Magne Matre Gåsland
#
#     License: GNU GPL v3 or later version. (See bottom of this file for the license notice, and see the LICENSE file for the full license.)
#
#     Example usage:
#
#         `bash spleeter-wrapper.sh --help`
#         `bash spleeter-wrapper.sh filename.mp3`
#         `bash spleeter-wrapper.sh filename.wma --stems 5 --process_codec WAV`
#

# activate anaconda / miniconda
CONDA_PATH=$(conda info | grep -i 'base environment' | awk '{print $4}')
# must use `source` since "Functions are not exported by default to be made available in subshells." https://github.com/conda/conda/issues/7980#issuecomment-441358406
source "$CONDA_PATH/etc/profile.d/conda.sh"
conda activate $MY_ENV # will also work if MY_ENV is not set.

# -- Handle script input options

# Initialize all the option variables.
# This ensures we are not contaminated by variables from the environment.
FILE=
TWO_STEMS=('vocals' 'accompaniment')
FOUR_STEMS=('vocals' 'drums' 'bass' 'other')
FIVE_STEMS=('vocals' 'drums' 'bass' 'piano' 'other')
# defaults, if no --stems option is set:
SPLEETER_STEMS=2stems
STEM_NAMES=( "${TWO_STEMS[@]}" )
# default, if no --process_codec option is set:
SPLEETER_OUT_EXT="m4a" # wav since it is the spleeter default. Lowercase required by spleeter.

# Usage info
show_help() {
cat << EOF

Usages:
    bash ${0##*/} [FILE]
    bash ${0##*/} [--stems INT] [--process_codec EXT] [--file FILE]
    bash ${0##*/} [-s INT] [-p EXT] [-f FILE]

Process the audio FILE and write the result to folder 'separate/FILE/'.
When no FILE or when FILE is -, then reads standard input.

    -h | --help       Display this help and exit
    -s | --stems INT   Set number of stems spleeter should output.
                          Valid: 2, 4 or 5.
                          Default: ${SPLEETER_STEMS%"stems"}.
    -p | --process_codec EXT    Set the codec/extension to be used (only) during processing.
                                  Valid: WAV, MP3, M4A.
                                  Default: $(echo $SPLEETER_OUT_EXT | tr [:lower:] [:upper:]).
                                Using a codec other than WAV can reduce disk space usage significantly,
                                at the cost of lossy compression.
    -f | --file FILE  The audio file to process. (e.g. "filename.mp3")

EOF
}

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

# Failsafe guard - exit if no file is provided as argument
if [[ $# -eq 0 ]]; then die 'ERROR: No parameters/options given to script. At least supply a file name of the audio file to process.'; fi
# If one and only one parameter, and not the help command,
# then assume it is the filename. For backwards compatibility.
if [[ $# -eq 1 && $1 != "-h" && $1 != "--help" ]]; then
  FILE="$1"
else
  # If more than 1 parameter, then assume options were input (in any order).
  # The file then has to be specified with the -f option.
  while test $# -gt 0; do
    # test the first remaining param
    case $1 in
        (-h|-\?|--help)
            show_help    # Display a usage synopsis.
            exit
            ;;
        (-s|--stems)   # Spleeter supports 2, 4 or 5 stems.
            if [ "$2" ]; then
              # Set the array of stem names based on nr of stems
              if [ $2 -eq 2 ]; then
                STEM_NAMES=( "${TWO_STEMS[@]}" )
                SPLEETER_STEMS="2stems"
              elif [ $2 -eq 4 ]; then
                STEM_NAMES=( "${FOUR_STEMS[@]}" )
                SPLEETER_STEMS="4stems"
              elif [ $2 -eq 5 ]; then
                STEM_NAMES=( "${FIVE_STEMS[@]}" )
                SPLEETER_STEMS="5stems"
              fi
            else
                die 'ERROR: "-s" or "--stems" requires a non-empty option argument.'
            fi
            shift # remove the processed option name
            ;;
        (-p|--process_codec)
            if [ "$2" ]; then
              SPLEETER_OUT_EXT=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]') # since spleeter only takes formats in lowercase
              if [[
                        $SPLEETER_OUT_EXT != "wav"
                  && $SPLEETER_OUT_EXT != "mp3"
                  # && $SPLEETER_OUT_EXT != "ogg" # requires libvorbis codec installed locally, which is not default
                  && $SPLEETER_OUT_EXT != "m4a"
                  # && $SPLEETER_OUT_EXT != "wma" # errors in concatenation
                  # && $SPLEETER_OUT_EXT != "flac" # does not remove cracks properly
                ]]; then
                die 'ERROR: "-p" or "--process_codec" only supports either: WAV, MP3, M4A.'
              fi
            else
              die 'ERROR: "-p" or "--process_codec" requires a non-empty option argument.'
            fi
            shift
            ;;
        (-f|--file)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                FILE=$2
            else
                die 'ERROR: "-f" or "--file" requires a non-empty option argument.'
            fi
            shift
            ;;
        (--file=?*)
            FILE=${1#*=} # Delete everything up to "=" and assign the remainder.
            # no shift here, so it works even if --file= comes before other options
            ;;
        (--file=)         # Handle the case of an empty --file=
            die 'ERROR: "--file=" requires a non-empty option argument.'
            ;;
        (--)              # End of all options.
            shift
            break
            ;;
        (-?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1. Did you forget to use double dash before a long option name?" >&2
            ;;
        (*)               # Default case: No more options, so break out of the loop.
            break
    esac
    shift # remove the processed option value (before continuing the while loop)
  done
fi

if [ "$FILE" == "" ]; then
  die 'ERROR: Empty FILE parameter. Did you forget to add the -f option specifier in front of the filename when running the script with several options?'
fi

echo "FILE:"
echo "${FILE}"
echo "SPLEETER_STEMS:"
echo "$SPLEETER_STEMS"
echo "STEM_NAMES:"
echo "${STEM_NAMES[@]}"
echo "SPLEETER_OUT_EXT:"
echo "$SPLEETER_OUT_EXT"

# --- End of handling script input options

# Remove extension, by using . as delimiter and select the 1st part (to the left).
NAME=$(printf "%s" "$FILE" | cut -f 1 -d '.')
EXT=$(printf "%s" "$FILE" | awk -F . '{print $NF}')
echo "Final output EXT:"
echo "$EXT"



# Will join one stem presumed output by Spleeter.
joinStem () {

  local STEM SPLITS LOCAL_EXT FILE_ARRAY fileArrayStem
  STEM="$1" # e.g. "vocals"
  SPLITS="$2" # e.g. "-30" or "-offset"
  LOCAL_EXT="$3" # e.g. "m4a"
  shift 3 # to remove the three first arguments, so that "$@" will refer to array content only
  FILE_ARRAY=( "$@" ) # e.g.: ("separated/filename-000", "separated/filename-001", "separated/filename-002", ...)

  # Append stem name and the extension spleeter outputs.
  # It will here be like: ("separated/filename-000/vocals.m4a", "separated/filename-001/vocals.m4a", ...)
  fileArrayStem=( "${FILE_ARRAY[@]/%//$STEM.$LOCAL_EXT}" ) # not using readarray/mapfile since not in Bash below v4.

  # List all files to be joined in a file for ffmpeg to use as input list
  printf "file '%s'\n" "${fileArrayStem[@]}" > concat-orig.txt # where > will overwrite the file if it already exists.

  # Concats the files in the list to destination file, e.g.: "separated/filename/vocals-30.m4a"
  ffmpeg -f concat -safe 0 -i concat-orig.txt -c copy separated/"$NAME"/$STEM$SPLITS.$LOCAL_EXT

  # Cleanup
  rm concat-orig.txt
}


# Will join all the stems presumed output by Spleeter.
joinAllStems () {

  local SPLITS LOCAL_EXT
  # first param is name to append to the split parts
  SPLITS="$1"
  LOCAL_EXT="$2"
  # Failsafe - set to 30 if no stem is provided as argument
  [ "$SPLITS" == "" ] && SPLITS="30"
  SPLITS="-$SPLITS"

  # create output folder
  mkdir -p separated/"$NAME"

  local fileArray fileArrayWithExt
  # save and change Internal Field Separator (IFS) which says where to split strings into array items
  OLDIFS=$IFS
  IFS=$'\n'
  # read all file names into an array, and ensure increasing order so stitched output will be correct
  fileArray=( $(find $NAME-* -type f | sort -n | cut -f 1 -d '.') ) # not using mapfile or readarray since not supported in Bash versions below v4.
  # keep a copy of the list of files for cleanup later
  fileArrayWithExt=( $(find $NAME-* -type f | sort -n) )
  # restore IFS to the original value (which is: space, tab, newline)
  IFS=$OLDIFS

  # prepend separated/ to each array element
  fileArray=( "${fileArray[@]/#/separated/}" )

  # Create vocals-30.m4a or vocals-offset.m4a, to be used in killCracksAndCreateOutput() later.
  for stem_name in "${STEM_NAMES[@]}"; do
    joinStem $stem_name "$SPLITS" $LOCAL_EXT "${fileArray[@]}"
  done

  OLDIFS=$IFS
  IFS=$'\n'
  rm -r $(printf "%s\n" "${fileArray[@]}") # the ones under separated/
  rm $(printf "%s\n" "${fileArrayWithExt[@]}") # the ones in the root folder
  IFS=$OLDIFS

}


# Split the full audio file to 30s parts, by utilising a 15s offset during processing.
offsetSplit () {

  local LOCAL_EXT
  LOCAL_EXT="$1"

  # First split the audio in 15s parts.
  # Can be done on original file format, since later only concatenating two and two parts, using filter_complex.
  ffmpeg -i "$FILE" -f segment -segment_time 15 -c copy -y "$NAME"-%03d.$LOCAL_EXT

  # Then leave the first 15s clip as is (000).
  # Join the second (001) into the third clip (002), the fourth into the fifth, etc. so the resulting parts are 30s clips.
  local cur curPad prev prevPad
  cur=2 # the current clip index, 0-indexed
  curPad=$(printf "%03d" $cur) # 002, third clip
  prev=$(( $cur - 1 ))
  prevPad=$(printf "%03d" $prev)
  # In the root folder:
  while [ -f "$NAME-$curPad.$LOCAL_EXT" ]; do
    # Use filter (instead of concat protocol) to correctly concat all file types, also M4A, WMA, and WAV (where each file has a 46 byte file header if made with ffmpeg).
    ffmpeg -i "$NAME-$prevPad.$LOCAL_EXT" -i "$NAME-$curPad.$LOCAL_EXT" -filter_complex '[0:0][1:0]concat=n=2:v=0:a=1[out]' -map '[out]' tmp.$LOCAL_EXT
    rm "$NAME"-$curPad.$LOCAL_EXT
    rm "$NAME"-$prevPad.$LOCAL_EXT
    mv tmp.$LOCAL_EXT "$NAME"-$curPad.$LOCAL_EXT
    cur=$(( $cur + 2 ))
    curPad=$(printf "%03d" $cur)
    prev=$(( $cur - 1 ))
    prevPad=$(printf "%03d" $prev)
  done
}


# Split the orig. audio input file into 30s parts, keeping the original format/extension.
ffmpeg -i "$FILE" -f segment -segment_time 30 -c copy "$NAME"-%03d.$EXT

# Do the separation on the parts.
# 5x: The 5x space of orig. file in M4A comes from the 5 stems.
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:$SPLEETER_STEMS -B tensorflow -o separated -c $SPLEETER_OUT_EXT

# Create separated/"$NAME"/vocals-30.m4a, and similar for the other stems.
# 5x2x: Temporarily uses 2x space of stems = $stems-30.m4a, before the joined stems are created, and orig. stems deleted, so back to 5x space of orig. file in M4A.
joinAllStems 30 $SPLEETER_OUT_EXT


# Split the orig. audio file into 30s parts, via splitting to 15s parts and joining two and two (except the first).
# Does not use $SPLEETER_OUT_EXT files, but original $EXT.
# Since it can use ffmpeg's filter_complex which works on all $EXT,
# and without overhead compared to using `ffmpeg -f concat -safe 0`.
# Since it has to work on two and two files anyway.
offsetSplit $EXT

# Do the separation on the parts (which are now the split offsets of the orig. audio file).
# 5x2x: 5x space of orig. file in M4A (old stems: vocals-30.m4a etc.) + 5x space of orig. file in M4A (new stems).
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:$SPLEETER_STEMS -B tensorflow -o separated -c $SPLEETER_OUT_EXT

# Create `separated/"$NAME"/vocals-offset.m4a`, and similar for the other stems.
# 5x2x2x: temporarily 2x space of new stems = $stems-offset.m4a (5x2x2x), when joined stems created, before orig. stems deleted, then back to: 5x2x
joinAllStems offset $SPLEETER_OUT_EXT


cd separated/"$NAME" || exit


# 5x2x2x: since 5x2x from before, plus both the 30-stems and the offset-stems are split into 1s fragments. After replacing, the offset-stems are deleted, so it's back to 5x2x
killCracksAndCreateOutput () {

  local STEM LOCAL_EXT
  STEM="$1"
  LOCAL_EXT="$2"

  # Failsafe - set to vocals if no stem is provided as argument
  [ "$STEM" == "" ] && STEM="vocals"

  # Create temporary folders
  mkdir parts-30
  mkdir parts-offset

  # Split the stem into 1s parts.
  # Logs: [segment @ 0x7ff0d0815200] Opening 'parts-30/vocals-30-000000.m4a' for writing
  ffmpeg -i $STEM-30.$LOCAL_EXT -f segment -segment_time 1 -c copy parts-30/$STEM-30-%06d.$LOCAL_EXT
  # 5x2x2x: The space consumption will be at its highest at this point.
  # clean up early
  rm $STEM-30.$LOCAL_EXT

  # Logs: [segment @ 0x7fe6c4008200] Opening 'parts-offset/vocals-offset-000000.m4a' for writing
  ffmpeg -i $STEM-offset.$LOCAL_EXT -f segment -segment_time 1 -c copy parts-offset/$STEM-offset-%06d.$LOCAL_EXT
  rm $STEM-offset.$LOCAL_EXT

  # Replace the 3 seconds around the cracks with the parts from the offset.
  local cur curPad prev prevPad next nextPad
  cur=30 # the current second, since first clip ends at 30 sec
  curPad=$(printf "%06d" $cur)
  # In the separated/"$NAME"/ folder:
  while [ -f "parts-offset/$STEM-offset-$curPad.$LOCAL_EXT" ]; do
    mv parts-offset/$STEM-offset-$curPad.$LOCAL_EXT parts-30/$STEM-30-$curPad.$LOCAL_EXT
    prev=$(( $cur - 1 ))
    prevPad=$(printf "%06d" $prev)
    mv parts-offset/$STEM-offset-$prevPad.$LOCAL_EXT parts-30/$STEM-30-$prevPad.$LOCAL_EXT
    next=$(( $cur + 1 ))
    nextPad=$(printf "%06d" $next)
    mv parts-offset/$STEM-offset-$nextPad.$LOCAL_EXT parts-30/$STEM-30-$nextPad.$LOCAL_EXT
    cur=$(( $cur + 30 ))
    curPad=$(printf "%06d" $cur)
  done

  # Free up some space early
  rm -r parts-offset

  # Create list of the parts, with lines like: `file 'parts-30/vocals-30-000000.m4a'` etc.
  find parts-30 -name "$STEM*" | sort -n | sed 's:\ :\\\ :g' | sed "s/^/file '/" | sed "s/$/'/" > concat-seconds.txt

  # Reassemble the full stem / create output.
  # Result placed in: `separated/"$NAME"/$STEM.$LOCAL_EXT`
  ffmpeg -f concat -safe 0 -i concat-seconds.txt -c copy $STEM.$LOCAL_EXT

  # Clean up rest
  rm -r parts-30 # just the folder, at this point, since content cleaned up in concat() underway.
  rm concat-seconds.txt

}


for stem_name in "${STEM_NAMES[@]}"; do
  killCracksAndCreateOutput $stem_name $SPLEETER_OUT_EXT
done


conv_to_orig_format () {
  STEM="$1"
  ffmpeg -i $STEM.$SPLEETER_OUT_EXT $STEM.$EXT
  rm $STEM.$SPLEETER_OUT_EXT
}
# Convert the file back to the original format, if the original format was not the same as $SPLEETER_OUT_EXT.
if [[ "$EXT" != "$SPLEETER_OUT_EXT" ]]; then
  for stem_name in "${STEM_NAMES[@]}"; do
    conv_to_orig_format $stem_name
  done
fi


# Fix the timestamps in the output, so the file won't be treated as malformed/corrupt/invalid if later importing to Audacity or other tool.
# We presume to still be in the separated/"$NAME"/ directory here.
fixTimestamps () {
  LOCAL_EXT="$2"
  STEM="$1"
  mv $STEM.$LOCAL_EXT ${STEM}_but_invalid_timestamps.$LOCAL_EXT
  # Recreate timestamps without re-encoding, to preserve quality.
  ffmpeg -vsync drop -i ${STEM}_but_invalid_timestamps.$LOCAL_EXT -map 0:a? -acodec copy $STEM.$LOCAL_EXT
  rm ${STEM}_but_invalid_timestamps.$LOCAL_EXT
}
for stem_name in "${STEM_NAMES[@]}"; do
  fixTimestamps $stem_name $EXT
done


# deactivate anaconda / miniconda
conda deactivate


#     --- License notice:
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
#
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#     See the file LICENSE for the full license.
#     ---