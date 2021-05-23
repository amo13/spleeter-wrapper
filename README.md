# spleeter-wrapper

[Spleeter](https://github.com/deezer/spleeter) is a library that uses AI/ML to extract distinct sounds/instruments (called stems) from an audio file.
It is intended to be used to separate vocals and instruments in a song. But it can also be used to extract only the voice from a noisy background in an audio recording (for example a lecture).

spleeter-wrapper is a bash shell/terminal script for using Spleeter with audio files of any length, and with limited RAM and HDD space.
This is especially important for long (1-2 hour) audio recordings. It also gives the option to decide what codec to use for processing, to control HDD usage vs lossy/lossless encoding.

`spleeter-wrapper.sh` originated in a [discussion](https://github.com/deezer/spleeter/issues/437#issuecomment-652807569) on the official spleeter repository, and was previously called `separate-overlap.sh`.

# Example usages

Use either command in your terminal:

    bash spleeter-wrapper.sh --help
    bash spleeter-wrapper.sh filename.mp3
    bash spleeter-wrapper.sh filename.wma --stems 5 --process_codec WAV

## Defaults

- `--stems 2`
- `--process_codec M4A`

These options are supplied by default, so if wanting these, no options need to be supplied.

You might want to use `--process_codec WAV` if you want to preserve lossless output from Spleeter, at the expense of needing much more HDD space during processing.

Regardless, the final output files will be returned in the same codec/extension as the audio file input to the script.

# How spleeter-wrapper works

- Splits the original file, runs Spleeter on the parts, then joins/concatenates the parts.
- Removes the padding that Spleeter adds to each part, which would otherwise be heard as cracks in the joined output audio file.

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

# Stem separation (--stems)

Example: `bash spleeter-wrapper --stems 4`

- 2 stems gives output: vocals / accompaniment
- 4 stems gives output: vocals / drums / bass / other
- 5 stems gives output: vocals / drums / bass / piano / other

# Internal processing codecs supported (--process_codec)

- `spleeter-wrapper.sh --process_codec` allows you to specify what codec the script should use internally, **to control HDD usage vs lossy/lossless encoding**.
The script will then set `spleeter` to output each of the parts/segments in this codec, and also use the same codec when joining them.
- Use `spleeter separate -h` to see currently available codecs.
- It supports **WAV, MP3 and M4A** for the internal processing.
- It is set to WAV by default. To preserve lossless processing and backwards compatibility. At the cost of more hard disk usage during processing.
- So running with `--process_codec M4A` is recommended. Even though it is a lossy codec, it has good quality, and the difference would most often be inaudible.
- You can still use `spleeter-wrapper.sh -f <file>` with any file extension (codec) that `ffmpeg` supports. Regardless of the internal `process_codec` used, the final output file will be converted to the same codec/extension that the input file had.

`--process_codec` will set `SPLEETER_OUT_EXT` which is the file extension used during processing.

## Disk space considerations: Beware of WAV

Disk space usage, at most = Size of original file * amount of stems * 2 (since -30 and -offsets) * 2 (under joinAllStems() when splitting into 1s clips).

Example:
- 2h audio file of any format, but which would take 669 MB when in WAV.
- Then with 5 stems it would take 669 * 5 * 2 * 2 = 13380 MB = **13.38 GB** disk space during processing.

So using M4A as the process codec is recommended. It reduces disk space usage to a minimum. Also don't run with more stems than you need, to save time and space.

## Intentional limitations and considerations

Spleeter itself supports outputting either: WAV, MP3, OGG, M4A, WMA, FLAC. In theory, when this script splits the audio file into parts, spleeter could output the parts in either of these codecs.
But this script has disabled using WMA, FLAC, and OGG as intermediate formats during processing, for the following reasons:

- WMA and FLAC: Could be concatenated by using `ffmpeg` with `complex_filter`. But would require extra func with 15-30 extra lines of code to maintain. See the `alt_concat_to_support_processing_with_wma_and_flac` branch, for a solution that works, but at the cost of being much slower, esp. on long audio files. When processing the 1s parts it would take ~1s to concat every part, times the nr of stems, making it infeasible for long audio clips (1-2h).
- WMA: Normal concat would leave gaps. For lossy compression, M4A is just as good as WMA. So might as well use M4A internally for processing and concatenation.
- FLAC: Normal concat will only play the first 35s of clip (possibly due to the fragment file headers not being stripped). The disk space usage with FLAC would be less than WAV, but M4A is even better, albeit lossy. FLAC could be useful if wanting optimal disk space usage with a lossless compression (while avoiding WAV).
- OGG: To use it Spleeter requires `libvorbis` codec installed locally, which is not installed with ffmpeg by default. Must also be concated with ffmpeg's `concat:` protocol to avoid `unknown keyword 'OggS'` and `Invalid data found when processing input` errors. It will still give `failed to create or replace stream` error(s) undeway, but the output sounds intact.

The above only concerns internal processing in spleeter-wrapper. It can still handle input files in all codecs that ffmpeg can handle - including WAV, MP3, OGG, M4A, WMA, FLAC - and will output to the same format as the input file.
