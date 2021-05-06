#!/bin/bash

#     A script for using spleeter with audio of any length
#     and with limited RAM on the processing machine
#
#     Author: Amaury Bodet
#
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

# activate (mini)conda
source ~/miniconda3/etc/profile.d/conda.sh
conda activate

FILE="$1"
 
# failsafe - exit if no file is provided as argument
[ "$FILE" == "" ] && exit

NAME=$(printf "$FILE" | cut -f 1 -d '.')
EXT=$(printf "$FILE" | awk -F . '{print $NF}')

joinParts () {

  # name appended to the split parts
  SPLITS="$1"
   
  # failsafe - exit if no file is provided as argument
  [ "$SPLITS" == "" ] && SPLITS="30"

  SPLITS="-$SPLITS"

  # create output folder
  mkdir -p separated/"$NAME"

  # save and change IFS
  OLDIFS=$IFS
  IFS=$'\n'

  # read all file name into an array
  fileArray=($(find $NAME-* -type f | cut -f 1 -d '.'))

  # keep a copy of the array for cleanup later
  fileArrayOrig=($(find $NAME-* -type f | cut -f 1 -d '.'))

  fileArrayWithExt=($(find $NAME-* -type f))

  # prepend separated/ to each array element
  fileArray=("${fileArray[@]/#/separated/}")
   
  # restore it
  IFS=$OLDIFS

  # append /vocals.wav to each element and create arrays for the stems
  fileArrayVocals=("${fileArray[@]/%//vocals.wav}")
  fileArrayDrums=("${fileArray[@]/%//drums.wav}")
  fileArrayBass=("${fileArray[@]/%//bass.wav}")
  fileArrayPiano=("${fileArray[@]/%//piano.wav}")
  fileArrayOther=("${fileArray[@]/%//other.wav}")

  # list all files to be joined in a file for ffmpeg to use as input list
  printf "file '%s'\n" "${fileArrayVocals[@]}" > concat-list.txt

  # concatenate the parts and convert the result to $EXT
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/vocals.wav
  ffmpeg -i separated/"$NAME"/vocals.wav separated/"$NAME"/vocals"$SPLITS".$EXT

  # repeat for the other stems
  # drums
  printf "file '%s'\n" "${fileArrayDrums[@]}" > concat-list.txt
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/drums.wav
  ffmpeg -i separated/"$NAME"/drums.wav separated/"$NAME"/drums"$SPLITS".$EXT
  # bass
  printf "file '%s'\n" "${fileArrayBass[@]}" > concat-list.txt
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/bass.wav
  ffmpeg -i separated/"$NAME"/bass.wav separated/"$NAME"/bass"$SPLITS".$EXT
  # piano
  printf "file '%s'\n" "${fileArrayPiano[@]}" > concat-list.txt
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/piano.wav
  ffmpeg -i separated/"$NAME"/piano.wav separated/"$NAME"/piano"$SPLITS".$EXT
  # other
  printf "file '%s'\n" "${fileArrayOther[@]}" > concat-list.txt
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/other.wav
  ffmpeg -i separated/"$NAME"/other.wav separated/"$NAME"/other"$SPLITS".$EXT

  # clean up
  rm separated/"$NAME"/vocals.wav
  rm separated/"$NAME"/drums.wav
  rm separated/"$NAME"/bass.wav
  rm separated/"$NAME"/piano.wav
  rm separated/"$NAME"/other.wav
  rm concat-list.txt
  OLDIFS=$IFS
  IFS=$'\n'
  rm -r $(printf "%s\n" "${fileArray[@]}")
  rm $(printf "%s\n" "${fileArrayOrig[@]}")
  IFS=$OLDIFS

}

# split the audio file in 30s parts, but first part only 15s
offsetSplit () {

  # split the audio in 15s parts
  ffmpeg -i "$FILE" -f segment -segment_time 15 -c copy -y "$NAME"-%03d.$EXT

  # join together second and third, fourth and fifth, etc.
  x=2
  y=$(printf "%03d" $x)
  z=$(( $x - 1 ))
  z=$(printf "%03d" $z)
  while [ -f "$NAME-$y.$EXT" ]; do
    ffmpeg -i "concat:$NAME-$z.$EXT|$NAME-$y.$EXT" -acodec copy tmp.$EXT
    rm "$NAME"-$y.$EXT
    rm "$NAME"-$z.$EXT
    mv tmp.$EXT "$NAME"-$y.$EXT
    x=$(( $x + 2 ))
    y=$(printf "%03d" $x)
    z=$(( $x - 1 ))
    z=$(printf "%03d" $z)
  done
  
}

# split the audio file in 30s parts
ffmpeg -i "$FILE" -f segment -segment_time 30 -c copy "$NAME"-%03d.$EXT

# do the separation on the parts
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated

joinParts 30

# clean up
rm "$NAME"-*

# split the audio file in 30s parts, but first part only 15s
offsetSplit

# do the separation on the parts
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated

joinParts offset

# clean up
rm "$NAME"-*

cd separated/"$NAME"

killCracks () {

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

  # reassemble the full stem
  find parts-30/$STEM* | sed 's:\ :\\\ :g'| sed 's/^/file /' > concat.txt
  ffmpeg -f concat -safe 0 -i concat.txt -c copy $STEM.$EXT
  
  # clean up
  rm -r parts-30
  rm -r parts-offset

}

killCracks vocals
killCracks bass
killCracks drums
killCracks piano
killCracks other

# cleanup
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

# deactivate (mini)conda
conda deactivate
