# DcmWaveform

Print the multiplex groups and channels of a waveform instance, such as an
ECG, or export their samples.

```sh
DcmWaveform ecg.dcm
DcmWaveform ecg.dcm --csv 1 > rhythm.csv
DcmWaveform ecg.dcm --json > waveforms.json
```

| Option | Output |
| --- | --- |
| none | Each multiplex group: label, channels, samples, sampling frequency, interpretation; each channel's label or source and sensitivity |
| `--csv N` | The values of multiplex group N: time in seconds, then one column per channel, in the channel's units |
| `--json` | Every multiplex group, with its stored samples and values |
