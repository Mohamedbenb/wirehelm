# 1.3.0+43

- Relay Windows desktop audio directly to a Raspberry Pi over encrypted SSH.
- Choose the Pi playback output, including connected Bluetooth headphones, and adjust its volume.
- Select Low latency, Balanced or Stable buffering.
- Monitor PC signal level, throughput, receiver queue, underruns, dropped audio frames, capture discontinuities and reconnect attempts.
- Keep audio playing independently of the phone app; stop it explicitly from the relay screen. Sessions expire after six hours.
- Restrict the dedicated relay SSH key to the receiver command, pin the Pi host key, cap audio queues and clean up owned capture/playback processes on Stop.
- Recover from transient Windows capture failures, report capture restarts, and keep monitoring off the interactive desktop helper.

Open **Audio relay** from either device's home screen. Microphone forwarding is not included in this release. See [Audio relay](AUDIO_RELAY.md) for setup and the meaning of the monitoring readings.
