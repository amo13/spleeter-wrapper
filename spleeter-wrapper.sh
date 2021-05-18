#!/bin/bash

#     A script for using spleeter with audio of any length
#     and with limited RAM on the processing machine
#
#     Original author:    Amaury Bodet
#     Contributor(s):     Magne Matre Gåsland
#
#     License: GNU GPL v3 or later version. (See bottom of this file for entire license notice.)
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
#
#     TODO: "rather than doing the work of splitting up the input files, one can use the -s (aka --offset) option to the separate command.
#                  This way, you can process a single file iteratively using spleeter, rather than splitting it up manually beforehand."
#                   - @avindra, https://github.com/deezer/spleeter/issues/391#issuecomment-642986976
#
#     Disk space usage, at most: Size of original file when converted to WAV * # of stems * 2 (since -30 and -offsets) * 2 (under joinParts when splitting into 1s clips).
#     So if an orig. 2h audio file in WAV is 669 MB, and we use spleeter with 5stems, then it would take 669 * 5 * 2 * 2 = 13380 MB = 13.38 GB disk space during processing.

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
EXT=$(printf "$FILE" | awk -F . '{print $NF}')

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
  printf "file '%s'\n" "${fileArrayVocals[@]}" > concat-list.txt
  # concatenate the parts, and create vocals-30.wav or vocals-offset.wav, to be used in killCracksAndCreateOutput() later.
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/vocals"$SPLITS".wav
  # Convert back to orig. format, to not consume so much disk space going forward (during the second run of spleeter and joinParts).
  # Might be lossy, if the original format $EXT is a lossy format. But keeping all intermedite files in WAV all the time would blow
  # up the script disk space usage too much (possibly require many GB free HDD space with a long, 2h, audio file).
  ffmpeg -i separated/"$NAME"/vocals"$SPLITS"{.wav,.$EXT}
  rm separated/"$NAME"/vocals"$SPLITS".wav

  # Repeat the same concatenation process for the other stems:
  # drums
  printf "file '%s'\n" "${fileArrayDrums[@]}" > concat-list.txt # where > will overwrite file, not append
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/drums"$SPLITS".wav
  ffmpeg -i separated/"$NAME"/drums"$SPLITS"{.wav,.$EXT}
  rm separated/"$NAME"/drums"$SPLITS".wav
  # bass
  printf "file '%s'\n" "${fileArrayBass[@]}" > concat-list.txt
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/bass"$SPLITS".wav
  ffmpeg -i separated/"$NAME"/bass"$SPLITS"{.wav,.$EXT}
  rm separated/"$NAME"/bass"$SPLITS".wav
  # piano
  printf "file '%s'\n" "${fileArrayPiano[@]}" > concat-list.txt
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/piano"$SPLITS".wav
  ffmpeg -i separated/"$NAME"/piano"$SPLITS"{.wav,.$EXT}
  rm separated/"$NAME"/piano"$SPLITS".wav
  # other
  printf "file '%s'\n" "${fileArrayOther[@]}" > concat-list.txt
  ffmpeg -f concat -safe 0 -i concat-list.txt -c copy separated/"$NAME"/other"$SPLITS".wav
  ffmpeg -i separated/"$NAME"/other"$SPLITS"{.wav,.$EXT}
  rm separated/"$NAME"/other"$SPLITS".wav

  rm concat-list.txt

  OLDIFS=$IFS
  IFS=$'\n'
  rm -r $(printf "%s\n" "${fileArray[@]}") # the ones under separated/
  rm $(printf "%s\n" "${fileArrayWithExt[@]}") # the ones in the root folder
  IFS=$OLDIFS

}

# Split the audio file in 30s parts, but first part only 15s
offsetSplit () {

  # First split the audio in 15s parts.
  # Can be done on original file format, since later only concatenating two and two parts, using filter_complex.
  ffmpeg -i "$FILE" -f segment -segment_time 15 -c copy -y "$NAME"-%03d.$EXT

  # Then leave the first 15s clip as is (000).
  # Join the second (001) into the third clip (002), the fourth into the fifth, etc. so the resulting parts are 30s clips.
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

# Split the orig. audio file into 30s parts
ffmpeg -i "$FILE" -f segment -segment_time 30 -c copy "$NAME"-%03d.$EXT

# Do the separation on the parts. Spleeter will here output WAV files, one for each stem (consuming a lot of hard drive space).
# 5x: The 5x space of orig. file in WAV comes from the 5 stems.
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated

# Create separated/"$NAME"/vocals-30.wav, and similar for the other stems.
# 5x2x: Temporarily uses 2x space of stems = $stems-30.wav, before the joined stems are created, and orig. stems deleted, so back to 5x space of orig. file in WAV.
joinParts 30


# Split the orig. audio file into 30s parts, via splitting to 15s parts and joining two and two (except the first).
# Does not use WAV files, but original $EXT.
offsetSplit

# Do the separation on the parts (which are now the split offsets of the orig. audio file).
# Spleeter will here output WAV files, one for each stem (consuming a lot of hard drive space).
# 5x2x: 5x space of orig. file in WAV (old stems: vocals-30.wav etc.) + 5x space of orig. file in WAV (new stems).
nice -n 19 spleeter separate -i "$NAME"-* -p spleeter:5stems -B tensorflow -o separated

# Create `separated/"$NAME"/vocals-offset.wav`, and similar for the other stems.
# 5x2x2x: temporarily 2x space of new stems = $stems-offset.wav (5x2x2x), when joined stems created, before orig. stems deleted, then back to: 5x2x
joinParts offset


cd separated/"$NAME"

# 5x2x2x: since 5x2x from before, plus both the 30-stems and the offset-stems are split into 1s fragments. After replacing, the offset-stems are deleted, so it's back to 5x2x
killCracksAndCreateOutput () {

  STEM="$1"

  # Failsafe - set to vocals if no stem is provided as argument
  [ "$STEM" == "" ] && STEM="vocals"

  # Create temporary folders
  mkdir parts-30
  mkdir parts-offset

  # Split the stem into 1s parts.
  # It's important that this is done on WAV files. Since some formats like WMA will
  # otherwise have pauses and corrupt duration when reassembled later.
  #
  # Convert from original format to WAV, so it will split and concat correctly, regardless of input format (even WMA).
  ffmpeg -i $STEM-30{.$EXT,.wav}
  rm $STEM-30.$EXT
  # Logs: [segment @ 0x7ff0d0815200] Opening 'parts-30/vocals-30-000000.wav' for writing
  ffmpeg -i $STEM-30.wav -f segment -segment_time 1 -c copy parts-30/$STEM-30-%06d.wav
  # 5x2x2x: The space consumption will be at its highest at this point.
  # rm, since multiple WAV files existing simultaneously would consume much HDD space going forward.
  rm $STEM-30.wav

  ffmpeg -i $STEM-offset{.$EXT,.wav}
  rm $STEM-offset.$EXT
  # Logs: [segment @ 0x7fe6c4008200] Opening 'parts-offset/vocals-offset-000000.wav' for writing
  ffmpeg -i $STEM-offset.wav -f segment -segment_time 1 -c copy parts-offset/$STEM-offset-%06d.wav
  rm $STEM-offset.wav

  # Replace the 3 seconds around the cracks with the parts from the offset.
  cur=30 # the current second, since first clip ends at 30 sec
  curPad=$(printf "%06d" $cur)
  # In the separated/"$NAME"/ folder:
  while [ -f "parts-offset/$STEM-offset-$curPad.wav" ]; do
    mv parts-offset/$STEM-offset-$curPad.wav parts-30/$STEM-30-$curPad.wav
    prev=$(( $cur - 1 ))
    prevPad=$(printf "%06d" $prev)
    mv parts-offset/$STEM-offset-$prevPad.wav parts-30/$STEM-30-$prevPad.wav
    next=$(( $cur + 1 ))
    nextPad=$(printf "%06d" $next)
    mv parts-offset/$STEM-offset-$nextPad.wav parts-30/$STEM-30-$nextPad.wav
    cur=$(( $cur + 30 ))
    curPad=$(printf "%06d" $cur)
  done

  # Free up some space early
  rm -r parts-offset

  # Create list of the parts, like `file 'parts-30/vocals-30-000000.wav'` etc.
  find parts-30 -name "$STEM*" | sort -n | sed 's:\ :\\\ :g'| sed "s/^/file '/" | sed "s/$/'/" > concat.txt

  # Reassemble the full stem / create output.
  ffmpeg -f concat -safe 0 -i concat.txt -c copy $STEM.wav

  # Convert to orig format, to save space going forward
  ffmpeg -i $STEM{.wav,.$EXT}
  rm $STEM.wav

  # Clean up rest
  rm -r parts-30
  rm concat.txt

}

killCracksAndCreateOutput vocals
killCracksAndCreateOutput bass
killCracksAndCreateOutput drums
killCracksAndCreateOutput piano
killCracksAndCreateOutput other

# Fix the timestamps in the output, so the file won't be treated as malformed/corrupt/invalid if later importing to Audacity or other tool.
# we presume to still be in the separated/"$NAME"/ directory here.
fixTimestamps() {
  mv $1.wav $1_but_invalid_timestamps.wav
  # recreate timestamps without re-encoding
  ffmpeg -vsync drop -i $1_but_invalid_timestamps.wav -map 0:a? -acodec copy $1.wav
  rm $1_but_invalid_timestamps.wav
}

fixTimestamps vocals
fixTimestamps bass
fixTimestamps drums
fixTimestamps piano
fixTimestamps other


# convert the file back to the original format, if the original format was not WAV.
if [[ $EXT != "wav" ]]; then
  ffmpeg -i vocals.wav vocals.$EXT
  rm vocals.wav # comment out to keep the resulting (potentially large) WAV file.
  # repeat for other stems
  ffmpeg -i bass.wav bass.$EXT
  rm bass.wav
  ffmpeg -i drums.wav drums.$EXT
  rm drums.wav
  ffmpeg -i piano.wav piano.$EXT
  rm piano.wav
  ffmpeg -i other.wav other.$EXT
  rm other.wav
fi

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
#     ---