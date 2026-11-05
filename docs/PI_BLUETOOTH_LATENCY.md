# Pi Bluetooth latency tuning — 2026-10-08

Mibro Earbuds 2: A2DP SBC, 48 kHz stereo. The BlueZ transport does not expose Delay. PipeWire 1.4.2 therefore uses a 125 ms SBC transport fallback, plus codec and packet delay, to report approximately 145.1875 ms. This is not a measured acoustic delay. Changing latencyOffsetNsec would only change reporting/synchronization and was not used.

Tests:
- Original running Bluetooth quantum: 256 samples / 48 kHz (5.333 ms).
- 128 samples (2.667 ms): receiver counters remained unchanged over a roughly 30-second observation; no additional PipeWire errors during that interval.
- 64 samples (1.333 ms): new PipeWire playback errors appeared immediately; reverted.
- SBC-XQ: reported estimate decreased to 137.1875 ms, but receiver underruns rose from 2 to 12 in approximately 23 seconds. This does not prove codec causation, but the trial did not justify retaining it. Restored SBC.

Final configuration: ~/.config/wireplumber/wireplumber.conf.d/90-node-cockpit-mibro-latency.conf, matching only bluez_output.79_5E_65_C1_CF_B3.1, sets node.force-quantum=128 and node.latency=128/48000. Global clock.force-quantum was restored to 0. Reloading WirePlumber temporarily disconnected Bluetooth; the existing pairing was preserved, the connection restored, and the relay restarted through the app. No earbud firmware settings, pairing, volume controls, or latency-reporting offsets were changed.

Rollback: remove only this named configuration file and reload WirePlumber, then reconnect the earbuds and restart the relay if needed. Do not remove other WirePlumber configuration. Codec profiles are selected with wpctl using the current Bluetooth device graph ID and EnumProfile index; never persist graph IDs.

Actual earbud/acoustic delay still needs an external measurement. Smaller processing blocks do not establish an equal end-to-end audible improvement.

Sources: https://github.com/PipeWire/pipewire/blob/1.4.2/spa/plugins/bluez5/bluez5-dbus.c and https://github.com/PipeWire/pipewire/blob/1.4.2/spa/plugins/bluez5/media-sink.c
Final SBC verification: relay remained running at 128 samples with zero PipeWire sink/stream errors. Receiver underruns increased from 2 to 4 over about 34 seconds; dropped frames remained unchanged. Occasional relay input starvation remains, so this is not a claim of perfectly uninterrupted audio.

## Build 1.3.2+45 controls and monitoring

The app now offers a separate Pi playback buffer (5/10/20/40 ms), scoped Bluetooth processing blocks (Auto/128/256/512 samples), and the stereo codec profiles actually available on the selected Pi device. Stop before applying processing/codec changes: WirePlumber reloads, reconnecting Bluetooth briefly; existing pairing is preserved. The app validates the selected output and resolves fresh device IDs after reload. A failed apply restores the prior scoped configuration. Auto removes the forced block size by setting zero; it does not delete unrelated configuration. The current rule no longer forces node.latency alongside the processing block.

Hints recommend 10 ms playback buffering and SBC for reliability, disclose the failed 64-sample experiment, and explain that smaller buffers can increase dropouts. SBC-XQ is an optional trial, not a promised latency improvement.

Windows monitoring separates capture packet duration, first-frame timestamp age at read, queued PCM duration, last packet queue wait, SSH pipe-write duration and capture-to-pipe-write completion. These overlap: do not add them together. Capture-to-send excludes audio app/engine delay before loopback capture and does not imply delivery to the Pi. Invalid WASAPI timestamps display unavailable instead of zero.

Pi monitoring samples pw-top in a separate thread: actual output quantum/rate/cycle, sink and playback-stream error counters, codec, output availability, and PipeWire latency reporting. Errors are node-lifetime counters and reset when the node is recreated. Telemetry expires after 10 seconds. BlueZ transport Delay is checked; when unavailable, the reported latency is explicitly labelled an estimate. None of these readings measure acoustic delay inside the earbuds.

References: https://docs.pipewire.org/page_man_pw-top_1.html and https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudiocaptureclient-getbuffer

Build 45 live configuration test: WirePlumber reconnect initially raced its startup. Added bounded reconnect retries while resolving fresh card IDs. Applying 256 samples with SBC succeeded after that change; prior pairing was preserved. Final test configuration is 256 samples for reliability.

Initial live telemetry verified SBC, active quantum 256/48 kHz, processing cycle 5.33 ms, zero output errors, and the correctly labelled 145.19 ms fallback estimate. Silent WASAPI input correctly showed unavailable timestamp ages. PipeWire pw-cat stream resolution was corrected to follow Client process ID → Node client.id rather than assuming process ID is on the audio Node.

Final installed build live test: a quiet 15-second PCM test tone registered -43.9 dBFS and 10 ms capture packets. Queue wait and SSH pipe write each measured around 0.01–0.02 ms, round trip around 0.9 ms. Both PipeWire sink and relay-stream error counters resolved and read zero. Receiver underruns reached 4 during the short start/test, so no dropout-free guarantee is made. Windows capture timestamp age remained unavailable on this capture path even with a test tone; the app correctly withholds the dependent capture-to-send estimate. Test relay was stopped after verification.

After stopping, verified receiver state stopped and no owned pw-cat, pw-top or sender45 process remained. Final receiver underruns were 7; both PipeWire error counters remained zero. Phone package version verified as 1.3.2, versionCode 45.
