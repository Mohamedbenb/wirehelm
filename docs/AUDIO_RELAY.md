# PC audio to Pi

Open a connected PC or Pi in Node Cockpit and choose **Audio relay**. Select the Pi's output and press **Start relay**. Pair/connect headphones using **Pi Bluetooth devices** first if they do not appear in the output list. The Windows PC captures its default playback output, including ordinary application audio. Protected content or applications using exclusive audio paths may not be captured.

Audio travels directly from Windows to the Pi inside SSH. The phone configures and monitors it; it does not carry audio. Leaving the screen or closing the app keeps playback running. Use **Stop relay** to stop it. A session has a six-hour limit. PC shutdown, lost playback output, or sustained connection failure also stops playback. Start again after PC sleep or a failed session.

Requirements: Windows OpenSSH client and desktop audio output; a Linux receiver with Python 3, PipeWire, `pw-cat`, `pw-dump`, `wpctl`, and SSH. No virtual audio cable, FFmpeg process, administrator install, or new network port is required. The initial Pi setup uses the app's existing authenticated SSH connection.

Prefer the Pi's wired IP for PC-to-Pi traffic. Phone access through Tailscale does not force the audio through Tailscale: the selected relay address determines that route. Both endpoints must be able to reach that address.

## Buffering and monitoring

- Application buffering is configurable from 5–200 ms, in 5 ms steps, before Start. PipeWire independently requests 10 ms. These requests do not guarantee total audible latency. Start at 40 ms; reduce it on wired Ethernet if playback remains stable.
- PCM is 48 kHz, stereo, 16-bit: approximately 192 kB/s plus SSH overhead.
- Queue depth is the current application backlog at the Pi. Signal is Windows capture RMS in dBFS. A silent PC reads near −96 dBFS.
- Underruns count periods when the receiver had to insert silence. Dropped PCM frames count discarded old backlog; a stereo frame is 1/48,000 second. Capture discontinuities come from WASAPI.
- Windows capture restarts count recovery attempts after a device/driver error. Capture is reopened up to three times for consecutive failures; repeated failures stop the relay with the failing WASAPI operation and HRESULT. Recovery creates a brief playback gap.
- Delivery ACK age indicates freshness of the Pi's telemetry. It is not one-way network latency or audible latency. Playback-driver, DAC and Bluetooth buffering are outside this measurement.

Queues are bounded. Stalls discard old audio instead of accumulating an unbounded delay. If a small buffer produces dropouts, increase it. Bluetooth earbuds typically dominate the final delay; measuring end-to-end latency requires an external acoustic or loopback measurement.

Relay volume scales only this stream on the PC. It never changes the Pi sink or Bluetooth device volume. Slider changes are coalesced and delivered through ordinary SSH without reinstalling the receiver or rediscovering devices. The Pi output can still be muted or quieter independently.

PC ↔ Pi round trip uses a zero-length protocol frame with a nonce, echoed immediately by the receiver input loop. The PC stopwatch measures request/reply duration over the existing encrypted channel. It includes SSH/OS processing but excludes the receiver playback queue and Bluetooth. It is separate from the half-second telemetry ACK and is not a one-way or acoustic delay measurement.

## Worker and key ownership

Windows stores the compiled sender, configuration, status, pinned Pi host key and a dedicated Ed25519 key under `%LOCALAPPDATA%\NodeCockpit\AudioRelay`. The folder is restricted to the current Windows user, SYSTEM and administrators. The private key stays on the PC.

Monitoring, setup and Stop use ordinary SSH requests. Only launching the capture worker uses an interactive desktop helper, keeping periodic telemetry from spawning desktop workers.

The Pi's public-key entry uses OpenSSH `restrict` and a forced receiver command. It cannot execute arbitrary shell commands, use a PTY or forward ports. The Pi host key is read over the already authenticated app connection and pinned for the PC sender. Other authorized keys are preserved. Remove the entry tagged `node-cockpit-audio-relay` to revoke relay access.

Pi receiver files live under `~/.local/share/node-cockpit/audio-relay`. One receiver at a time is enforced with an exclusive file lock. SSH EOF or a ten-second input timeout terminates the receiver's owned `pw-cat` process. Windows Stop shuts down its owned SSH child and WASAPI capture. Configuration, keys and small telemetry files remain for the next session; raw audio is not saved to disk.

## Build 43 validation

The live Windows WASAPI probe succeeded at 48 kHz stereo. A PC test tone registered around −28 dBFS; the Pi streamed to the Mibro Bluetooth output with bounded queue depth. The stream stayed active after force-closing the phone app. A second SSH session was rejected without disturbing the active receiver; an arbitrary requested command was intercepted by the forced receiver. Phone Start/Stop and telemetry were exercised on the actual devices; Stop left no sender or playback worker. A Balanced run lasting over two minutes reported one underrun, about 191–192 kB/s, and a 60–70 ms application queue. Low latency showed more underruns under load. These are observed test readings, not an audible-latency guarantee. Unit tests cover bounded queues, fragmented/truncated transport input and stale monitoring data. Audible quality and total earbud latency need a listening/physical measurement.

Sustained testing also exposed a Windows capture error and excessive desktop-helper creation during polling. Monitoring now uses ordinary SSH, and capture recovery is bounded. `scripts/test_audio_capture.ps1` exercises the real capture loop with temporary fault-injected builds: one failure recovers; repeated failures stop after three retries. Audio from those tests is discarded, and the injected code is not shipped.

## Build 44 validation

Resolved each selected output name to its current PipeWire object serial at playback start, and set explicit no-fallback/no-reconnect properties. A stale Bluetooth node cannot silently move playback to another output. Current serials are not persisted as device identities. Playback chunks are 5 ms; the PC queue is limited to two capture packets instead of eight; receiver overflow returns to the requested buffer rather than retaining maximum backlog. Unbuffered playback writes now handle partial writes.

Two 30-second silent PC-to-Pi tests completed without playback-target errors. A clock-paced run at a custom 25 ms buffer observed minimum SSH round trip 0.74 ms, two underrun episodes, and some discarded startup/backlog frames. The first probe includes session startup and inflates the mean; do not interpret that average as steady-state LAN latency. Tests are silent transport/playback tests, not listening or acoustic measurements. Queue integrity, fragmented input, volume command isolation, stale status, and capture fault recovery are checked separately.

The final APK was installed and its package verified as 1.3.1 / code 44. App Start, software volume changes (50% then 84%), refresh/readback of the applied gain, and Stop were exercised. During the second volume change the current Pi sink remained at 82%; software relay gain changed independently. Earlier in the run the sink was recreated (serial 815 → 1281); the worker recovered using the new serial. The final monitoring screenshot showed three reconnect attempts, three receiver underruns, and discarded frames associated with startup/reconnection. Network round trip readings included 0.8 ms and 2.2 ms. This confirms recovery, not uninterrupted Bluetooth playback or a listening-quality guarantee. Stop left no owned Pi receiver or pw-cat playback process. The final volume was returned to 100%.
