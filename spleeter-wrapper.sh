#!/bin/bash

#     A script for using spleeter with audio of any length
#     and with limited RAM on the processing machine
#
#     Author: Amaury Bodet
#
#     ---
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
#     ---
#
#     "
#     You can feed an audio file of any length into the script and the whole process
#     is not going to eat more than 2GB RAM. I think for me it was around 1.6GB.
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
#       Processes the audio twice with spleeter
#       The result is not 100% accurate: on a 3m30s track the stems were around 200ms too long.
#       I am not sure about what exactly caused the 200ms error for me. I was suspecting ffmpeg being inaccurate when splitting and joining, but I don't really know. Anyway, the resulting stems are totally acceptable.
#     "
#     From: https://github.com/deezer/spleeter/issues/391#issuecomment-633155556
#
#
#     Overlap explained by the author @amo13 on github:
#     "
#     Basically, it needs to process the input audio twice but with the
#     second processing doing one 15 seconds chunk, and then again 30s
#     chunks for the rest. Then it takes 3s around the crack in the first
#     processing from the second one, and puts everything back together.
#     It's probably not ideal but maybe someone will have a good idea how
#     to make it better.
#     "
#     From: https://github.com/deezer/spleeter/issues/437#issuecomment-652807569
#
#     TODO: "rather than doing the work of splitting up the input files, one can use the -s (aka --offset) option to the separate command.
#                  This way, you can process a single file iteratively using spleeter, rather than splitting it up manually beforehand."
#                   - @avindra, https://github.com/deezer/spleeter/issues/391#issuecomment-642986976
#

# activate anaconda / miniconda
CONDA_PATH=$(conda info | grep -i 'base environment' | awk '{print $4}')
# must use `source` since "Functions are not exported by default to be made available in subshells." https://github.com/conda/conda/issues/7980#issuecomment-441358406
source $CONDA_PATH/etc/profile.d/conda.sh
conda activate $MY_ENV # will also work if MY_ENV is not set.

FILE="$1"

# failsafe - exit if no file is provided as argument
[ "$FILE" == "" ] && exit

# remove extension, by using . as delimiter and select the 1st part (to the left).
NAME=$(printf "$FILE" | cut -f 1 -d '.')

# Do all the processing on WAV files. (Should not increase consumed disk space.)
# To ensure the parts are processed and joined together correctly.
# Before, WMA files especially had problems with long gaps and erroneous total duration (even after fixTimestamps() were run).
# This avoids that, and prevents it happening for other formats too.
ORIG_EXT=$(printf "$FILE" | awk -F . '{print $NF}')
EXT="wav" # wav will also preserve quality, since lossless

joinParts () {

  # first param is name to append to the split parts
  SPLITS="$1"

  # failsafe - exit if no file is provided as argument
  [ "$SPLITS" == "" ] && SPLITS="30"

  SPLITS="-$SPLITS"

  # create output folder
  mkdir -p separated/"$NAME"

  # save and change Internal Field Separator (IFS) which says where to split strings into array items
  OLDIFS=$IFS
  IFS=$'\n'

  # read all file names into an array, and ensure increasing order so stitched output will be correct
  fileArray=($(find $NAME-* -type f | sort -n | cut -f 1 -d '.'))

  # keep a copy of the list of files for cleanup later
  fileArrayWithExt=($(find $NAME-* -type f | sort -n))

  # restore IFS to the original value (which is: space, tab, newline)
  IFS=$OLDIFS

  # prepend separated/ to each array element
  fileArray=("${fileArray[@]/#/separated/}")

  # append /vocals.wav to each element and create arrays for the stems
  fileArrayVocals=("${fileArray[@]/%//vocals.wav}")
  fileArrayDrums=("${fileArray[@]/%//drums.wav}")
  fileArrayBass=("${fileArray[@]/%//bass.wav}")
  fileArrayPiano=("${fileArray[@]/%//piano.wav}")
  fileArrayOther=("${fileArray[@]/%//other.wav}")

  # list all files to be joined in a file for ffmpeg to use as input list
  printf "file '%s'\n" "${fileArrayVocals[@]}" > concat-list"$SPLITS".txt

  # concatenate the parts.
  ffmpeg -f concat -safe 0 -i concat-list"$SPLITS".txt -c copy separated/"$NAME"/vocals.wav
  # Make a renamed copy, so it can later be used in killCracksAndCreateOutput().
  # Also convert the result to $EXT, in case $EXT is set to something different than WAV.
  ffmpeg -i separated/"$NAME"/vocals.wav separated/"$NAME"/vocals"$SPLITS".$EXT

  # repeat for the other stems
  # drums
  printf "file '%s'\n" "${fileArrayDrums[@]}" > concat-list"$SPLITS".txt
  ffmpeg -f concat -safe 0 -i concat-list"$SPLITS".txt -c copy separated/"$NAME"/drums.wav
  ffmpeg -i separated/"$NAME"/drums.wav separated/"$NAME"/drums"$SPLITS".$EXT
  # bass
  printf "file '%s'\n" "${fileArrayBass[@]}" > concat-list"$SPLITS".txt
  ffmpeg -f concat -safe 0 -i concat-list"$SPLITS".txt -c copy separated/"$NAME"/bass.wav
  ffmpeg -i separated/"$NAME"/bass.wav separated/"$NAME"/bass"$SPLITS".$EXT
  # piano
  printf "file '%s'\n" "${fileArrayPiano[@]}" > concat-list"$SPLITS".txt
  ffmpeg -f concat -safe 0 -i concat-list"$SPLITS".txt -c copy separated/"$NAME"/piano.wav
  ffmpeg -i separated/"$NAME"/piano.wav separated/"$NAME"/piano"$SPLITS".$EXT
  # other
  printf "file '%s'\n" "${fileArrayOther[@]}" > concat-list"$SPLITS".txt
  ffmpeg -f concat -safe 0 -i concat-list"$SPLITS".txt -c copy separated/"$NAME"/other.wav
  ffmpeg -i separated/"$NAME"/other.wav separated/"$NAME"/other"$SPLITS".$EXT

  # clean up
  rm separated/"$NAME"/vocals.wav
  rm separated/"$NAME"/drums.wav
  rm separated/"$NAME"/bass.wav
  rm separated/"$NAME"/piano.wav
  rm separated/"$NAME"/other.wav

  rm concat-list"$SPLITS".txt

  OLDIFS=$IFS
  IFS=$'\n'
  rm -r $(printf "%s\n" "${fileArray[@]}") # the ones under separated/
  rm $(printf "%s\n" "${fileArrayWithExt[@]}") # the ones in the root folder
  IFS=$OLDIFS

}

# split the audio file in 30s parts, but first part only 15s
offsetSplit () {

  # split the audio in 15s parts
  ffmpeg -i "$FILE" -f segment -segment_time 15 -c copy -y "$NAME"-%03d.$EXT

  # leave the first 15s clip as is (000).
  # join the second (001) into the third clip (002), the fourth into the fifth, etc.
  cur=2 # the current clip index, 0-indexed
  curPad=$(printf "%03d" $cur) # 002, third clip
  prev=$(( $cur - 1 ))
  prevPad=$(printf "%03d" $prev)
  # in the root folder:
  while [ -f "$NAME-$curPad.$EXT" ]; do
    # correctly concat all file types, also WAV (where each file has a 46 byte file header if made with ffmpeg)
    ffmpeg -i "$NAME-$prevPad.$EXT" -i "$NAME-$curPad.$EXT" -filter_complex '[0:0][1:0]concat=n=2:v=0:a=1[out]' -map '[out]' tmp.$EXT
    rm "$NAME"-$curPad.$EXT
    rm "$NAME"-$prevPad.$EXT
    mv tmp.$EXT "$NAME"-$curPad.$EXT
    cur=$(( $cur + 2 ))
    curPad=$(printf "%03d" $cur)
    prev=$(( $cur - 1 ))
    prevPad=$(printf "%03d" $prev)
  done

}

# split the audio file in 30s parts
ffmpeg -i "$FILE" -f segment -segment_time 30 -c copy "$NAME"-%03d.$EXT

# do the separation on the parts
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated

joinParts 30 # creates separated/"$NAME"/vocals-30.wav, and similar for the other stems.

# split the orig. audio file into 30s parts, via splitting to 15s parts and joining two and two (except the first)
offsetSplit

# do the separation on the parts (which are now the split offsets of the orig. audio file)
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated

joinParts offset # creates `separated/"$NAME"/vocals-offset.wav`, and similar for the other stems.

cd separated/"$NAME"

killCracksAndCreateOutput () {

  STEM="$1"

  # failsafe - exit if no file is provided as argument
  [ "$STEM" == "" ] && STEM="vocals"

  # create temporary folders
  mkdir parts-30
  mkdir parts-offset
  
  # split the stem into 1s parts
  ffmpeg -i $STEM-30.$EXT -f segment -segment_time 1 -c copy parts-30/$STEM-30-%06d.$EXT
  ffmpeg -i $STEM-offset.$EXT -f segment -segment_time 1 -c copy parts-offset/$STEM-offset-%06d.$EXT

  # replace the 3 seconds around the cracks with the parts from the seconds processing
  x=30
  y=$(printf "%06d" $x)
  while [ -f "parts-30/$STEM-30-$y.$EXT" ]; do
    mv parts-offset/$STEM-offset-$y.$EXT parts-30/$STEM-30-$y.$EXT
    z=$(( $x - 1 ))
    z=$(printf "%06d" $z)
    mv parts-offset/$STEM-offset-$z.$EXT parts-30/$STEM-30-$z.$EXT
    z=$(( $x + 1 ))
    z=$(printf "%06d" $z)
    mv parts-offset/$STEM-offset-$z.$EXT parts-30/$STEM-30-$z.$EXT
    x=$(( $x + 30 ))
    y=$(printf "%06d" $x)
  done

  # create list of the parts, like `file 'parts-30/vocals-30-000000.wav'` etc.
  find parts-30 -name "$STEM*" | sort -n | sed 's:\ :\\\ :g'| sed "s/^/file '/" | sed "s/$/'/" > concat.txt
  # reassemble the full stem
  ffmpeg -f concat -safe 0 -i concat.txt -c copy $STEM.$EXT

  # clean up
  rm -r parts-30
  rm -r parts-offset

}

killCracksAndCreateOutput vocals
killCracksAndCreateOutput bass
killCracksAndCreateOutput drums
killCracksAndCreateOutput piano
killCracksAndCreateOutput other

# cleanup temp files
rm concat.txt
rm vocals-30.$EXT
rm vocals-offset.$EXT
rm bass-30.$EXT
rm bass-offset.$EXT
rm drums-30.$EXT
rm drums-offset.$EXT
rm piano-30.$EXT
rm piano-offset.$EXT
rm other-30.$EXT
rm other-offset.$EXT

# fix the timestamps in the output, so the file won't be treated as malformed/corrupt/invalid if later importing to Audacity or other tool.
# we presume to still be in the separated/"$NAME"/ directory here.
fixTimestamps() {
  mv $1.$EXT $1_but_invalid_timestamps.$EXT
  # recreate timestamps without re-encoding
  ffmpeg -vsync drop -i $1_but_invalid_timestamps.$EXT -map 0:a? -acodec copy $1.$EXT
  rm $1_but_invalid_timestamps.$EXT
}

fixTimestamps vocals
fixTimestamps bass
fixTimestamps drums
fixTimestamps piano
fixTimestamps other


# convert the file back to the original format, if the original format was not WAV.
if [[ $ORIG_EXT != $EXT ]]; then
  ffmpeg -i vocals.$EXT vocals.$ORIG_EXT
  rm vocals.$EXT # comment out to keep the resulting (potentially large) WAV file.
  # repeat for other stems
  ffmpeg -i bass.$EXT bass.$ORIG_EXT
  rm bass.$EXT
  ffmpeg -i drums.$EXT drums.$ORIG_EXT
  rm drums.$EXT
  ffmpeg -i piano.$EXT piano.$ORIG_EXT
  rm piano.$EXT
  ffmpeg -i other.$EXT other.$ORIG_EXT
  rm other.$EXT
fi

# deactivate anaconda / miniconda
conda deactivate
