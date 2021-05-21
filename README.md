# spleeter-wrapper

A script for using spleeter with audio files of any length, and with limited RAM and HDD space.
But also gives the option to process using WAV files, to get a fully lossless result, at the cost of using more HDD space during processing.

Originated in a [discussion](https://github.com/deezer/spleeter/issues/437#issuecomment-652807569) on the official spleeter repository.

# Example usage:

        `bash spleeter-wrapper.sh --help`
        `bash spleeter-wrapper.sh filename.mp3`
        `bash spleeter-wrapper.sh filename.wma --stems 2 --process_codec M4A`

By default (if no options supplied) the script will use Spleeter to output
5 stems and will use WAV codec (lossless) during processing.
But the final output files will be returned in the same codec/extension
as the audio file input to the script.

# How

- Splits the original file, runs Spleeter on the parts, then joins/concatenates the parts.
- Removes the padding that Spleeter adds, which would otherwise be heard as cracks in the joined output audio file.

## Why does spleeter add the padding/cracks?

"Spleeter is adding a tiny padding after each output stem file,
what makes a small gap when stitching back the 30's chunks in one single stem"
https://github.com/deezer/spleeter/issues/437#issue-648995964

"The padding is unavoidable, due to a strange behavior of the STFT of tensorflow
that spleeter uses but does not compensate for."
https://github.com/deezer/spleeter/issues/437#issuecomment-652516231

The padding/cracks are the reason the overlap correction in this script is needed.

## The processing steps

You can feed an audio file of any length into the script and the whole process
is not going to eat more than 2GB RAM. I think for me [Amaury] it was around 1.6GB.

How it works:

  1. Split the audio file into 30s parts.
  2. Process them all with spleeter.
  3. Join the resulting stem-parts to the full-length stems.
  4. Split the audio file again into 30s parts but with the first part being only 15s long.
  5. Process them again with spleeter.
  6. Join the results to full-length stems again.
  7. Replace 3s around every crack in the first stems with the respective 3 seconds from the second stems.
  8. Clean up.

Downside:

  1. Processes the audio twice with spleeter.
  2. The result is not 100% accurate: on a 3m30s track the stems were around 200ms too long.
      I am not sure about what exactly caused the 200ms error for me. I was suspecting ffmpeg being inaccurate
      when splitting and joining, but I don't really know. Anyway, the resulting stems are totally acceptable.

https://github.com/deezer/spleeter/issues/391#issuecomment-633155556

## Details on the overlap correction

Basically, it needs to process the input audio twice but with the
second processing doing one 15 seconds chunk, and then again 30s
chunks for the rest. Then it takes 3s around the crack in the first
processing from the second one, and puts everything back together.
It's probably not ideal but maybe someone will have a good idea how
to make it better.