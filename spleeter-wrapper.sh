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
#         `bash spleeter-wrapper.sh filename.mp3`
#         `bash spleeter-wrapper.sh filename.wma M4A`
#
#     Second param to script specifies a specific format/extension to use with Spleeter while processing.
#     Spleeter supports WAV, MP3, OGG, M4A, WMA, FLAC.
#     M4A is recommended, since it will considerably reduce the disk space used/needed during processing, compared to WAV.
#     Spleeter uses WAV by default, so this script does that too if no second param is specified.
#
#     Cracks are the reason the overlap correction in this script is needed:
#     "
#     Spleeter is adding a tiny padding after each output stem file,
#     what makes a small gap when stitching back the 30's chunks in one single stem
#     "
#     From: https://github.com/deezer/spleeter/issues/437#issue-648995964
#
#     "
#     The padding is unavoidable, due to a strange behavior of the STFT of tensorflow
#     that spleeter uses but does not compensate for.
#     "
#     From: https://github.com/deezer/spleeter/issues/437#issuecomment-652516231
#
#     "
#     You can feed an audio file of any length into the script and the whole process
#     is not going to eat more than 2GB RAM. I think for me [Amaury] it was around 1.6GB.
#
#     How it works:
#
#       1. Split the audio file into 30s parts.
#       2. Process them all with spleeter.
#       3. Join the resulting stem-parts to the full-length stems.
#       4. Split the audio file again into 30s parts but with the first part being only 15s long.
#       5. Process them again with spleeter.
#       6. Join the results to full-length stems again.
#       7. Replace 3s around every crack in the first stems with the respective 3 seconds from the second stems.
#       8. Clean up.
#
#     Downside:
#
#       1. Processes the audio twice with spleeter.
#       2. The result is not 100% accurate: on a 3m30s track the stems were around 200ms too long.
#       I am not sure about what exactly caused the 200ms error for me. I was suspecting ffmpeg being inaccurate
#       when splitting and joining, but I don't really know. Anyway, the resulting stems are totally acceptable.
#     "
#     From: https://github.com/deezer/spleeter/issues/391#issuecomment-633155556
#
#
#     Overlap correction process, explained by the original author Amaury (@amo13) on github:
#     "
#     Basically, it needs to process the input audio twice but with the
#     second processing doing one 15 seconds chunk, and then again 30s
#     chunks for the rest. Then it takes 3s around the crack in the first
#     processing from the second one, and puts everything back together.
#     It's probably not ideal but maybe someone will have a good idea how
#     to make it better.
#     "
#     From: https://github.com/deezer/spleeter/issues/437#issuecomment-652807569

# activate anaconda / miniconda
CONDA_PATH=$(conda info | grep -i 'base environment' | awk '{print $4}')
# must use `source` since "Functions are not exported by default to be made available in subshells." https://github.com/conda/conda/issues/7980#issuecomment-441358406
source "$CONDA_PATH/etc/profile.d/conda.sh"
conda activate $MY_ENV # will also work if MY_ENV is not set.

FILE="$1"

# Intermittent file format, used during processing, to conserve disk space usage.
#
# The following has no bearing on the _final_ output file format. It will always be the same as the file format of the original input file, which the user sends in as the first param to this script.
# The user may specify the file format that Spleeter and this script should use for intermittent processing, which can have serious disk usage consequences (a lossless format like WAV would multiply disk space usage 10 times).
#     Disk space usage, at most = Size of original file * amount of stems * 2 (since -30 and -offsets) * 2 (under joinAllStems when splitting into 1s clips).
#     So if processing an orig. 2h WAV audio file taking 669 MB, and we use spleeter with 5stems and spleeter's default output WAV, then it would take 669 * 5 * 2 * 2 = 13380 MB = 13.38 GB disk space during processing.
# At this time, Spleeter supports outputting either: WAV, MP3, OGG, M4A, WMA, FLAC. Use `spleeter separate -h` to see currently available formats.
SPLEETER_OUT_EXT=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]') # since spleeter only takes formats in lowercase
# Set to WAV (Spleeter's default) if no format is specified to this script.
[ "$SPLEETER_OUT_EXT" == "" ] && SPLEETER_OUT_EXT="wav" # lowercase required by spleeter

# Failsafe - exit if no file is provided as argument
[ "$FILE" == "" ] && exit

# remove extension, by using . as delimiter and select the 1st part (to the left).
NAME=$(printf "%s" "$FILE" | cut -f 1 -d '.')
EXT=$(printf "%s" "$FILE" | awk -F . '{print $NF}')


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
  fileArrayStem=( ${FILE_ARRAY[@]/%//$STEM.$LOCAL_EXT} )

  # List all files to be joined in a file for ffmpeg to use as input list
  printf "file '%s'\n" "${fileArrayStem[@]}" > concat-orig.txt # where > will overwrite the file if it already exists.

  # Concats the files in the list to destination file, e.g.: "separated/filename/vocals-30.m4a"
  ffmpeg -f concat -safe 0 -i concat-orig.txt -c copy separated/"$NAME"/$STEM$SPLITS.$LOCAL_EXT

  # Cleanup
  rm concat-orig.txt
}


# Will join all the stems presumed output by Spleeter.
joinAllStems () {

  # first param is name to append to the split parts
  local SPLITS LOCAL_EXT
  SPLITS="$1"
  LOCAL_EXT="$2"
  # Failsafe - set to 30 if no stem is provided as argument
  [ "$SPLITS" == "" ] && SPLITS="30"
  SPLITS="-$SPLITS"

  # create output folder
  mkdir -p separated/"$NAME"

  # save and change Internal Field Separator (IFS) which says where to split strings into array items
  OLDIFS=$IFS
  IFS=$'\n'
  # read all file names into an array, and ensure increasing order so stitched output will be correct
  local fileArray
  fileArray=( $(find $NAME-* -type f | sort -n | cut -f 1 -d '.') ) # not using mapfile or readarray since not supported in Bash versions below v4.
  # keep a copy of the list of files for cleanup later
  local fileArrayWithExt
  fileArrayWithExt=( $(find $NAME-* -type f | sort -n) )
  # restore IFS to the original value (which is: space, tab, newline)
  IFS=$OLDIFS

  # prepend separated/ to each array element
  local fileArray
  fileArray=( ${fileArray[@]/#/separated/} )

  # Create vocals-30.m4a or vocals-offset.m4a, to be used in killCracksAndCreateOutput() later.
  joinStem vocals "$SPLITS" $LOCAL_EXT "${fileArray[@]}"
  #joinStem accompaniment "$SPLITS" $LOCAL_EXT "${fileArray[@]}" # uncomment if spleeter is configured with 2stems, and comment out lines below
  joinStem drums "$SPLITS" $LOCAL_EXT "${fileArray[@]}"
  joinStem bass "$SPLITS" $LOCAL_EXT "${fileArray[@]}"
  joinStem piano "$SPLITS" $LOCAL_EXT "${fileArray[@]}"
  joinStem other "$SPLITS" $LOCAL_EXT "${fileArray[@]}"

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
    # Correctly concat all file types, also WAV (where each file has a 46 byte file header if made with ffmpeg)
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
# TODO:
# "Rather than doing the work of splitting up the input files, one can use the -s (aka --offset) option to the separate command.
# This way, you can process a single file iteratively using spleeter, rather than splitting it up manually beforehand."
# - @avindra, https://github.com/deezer/spleeter/issues/391#issuecomment-642986976
# BUT:
# This is not a very significant optimisation, since the if the input file is in a compressed format,
# the split files will also be compressed, thus not consuming much disk space.

# Do the separation on the parts.
# 5x: The 5x space of orig. file in M4A comes from the 5 stems.
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated -c $SPLEETER_OUT_EXT

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
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated -c $SPLEETER_OUT_EXT

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


killCracksAndCreateOutput vocals $SPLEETER_OUT_EXT
killCracksAndCreateOutput bass $SPLEETER_OUT_EXT
killCracksAndCreateOutput drums $SPLEETER_OUT_EXT
killCracksAndCreateOutput piano $SPLEETER_OUT_EXT
killCracksAndCreateOutput other $SPLEETER_OUT_EXT


conv_to_orig_format () {
  STEM="$1"
  ffmpeg -i $STEM.$SPLEETER_OUT_EXT $STEM.$EXT
  rm $STEM.$SPLEETER_OUT_EXT
}
# Convert the file back to the original format, if the original format was not the same as $SPLEETER_OUT_EXT.
if [[ "$EXT" != "$SPLEETER_OUT_EXT" ]]; then
  conv_to_orig_format vocals
  # conv_to_orig_format accompaniment # uncomment if spleeter is configured with 2stems, and comment out lines below
  conv_to_orig_format bass
  conv_to_orig_format drums
  conv_to_orig_format piano
  conv_to_orig_format other
fi


# Fix the timestamps in the output, so the file won't be treated as malformed/corrupt/invalid if later importing to Audacity or other tool.
# We presume to still be in the separated/"$NAME"/ directory here.
fixTimestamps () {
  LOCAL_EXT="$2"
  mv $1.$LOCAL_EXT $1_but_invalid_timestamps.$LOCAL_EXT
  # Recreate timestamps without re-encoding, to preserve quality.
  ffmpeg -vsync drop -i $1_but_invalid_timestamps.$LOCAL_EXT -map 0:a? -acodec copy $1.$LOCAL_EXT
  rm $1_but_invalid_timestamps.$LOCAL_EXT
}

fixTimestamps vocals $EXT
fixTimestamps bass $EXT
fixTimestamps drums $EXT
fixTimestamps piano $EXT
fixTimestamps other $EXT


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