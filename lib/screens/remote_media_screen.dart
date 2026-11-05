import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show Endian;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import '../ssh/ssh_session.dart';
import '../services/remote_media.dart';

class RemoteMediaScreen extends StatefulWidget {
  final Device device;
  final SshSession session;
  const RemoteMediaScreen({
    super.key,
    required this.device,
    required this.session,
  });
  @override
  State<RemoteMediaScreen> createState() => _RemoteMediaScreenState();
}

class _RemoteMediaScreenState extends State<RemoteMediaScreen>
    with WidgetsBindingObserver {
  static const audio = MethodChannel('remote_control/audio');
  MediaInventory? inventory;
  MediaInput? camera, microphone;
  Uint8List? frame;
  String? error;
  bool loading = true, starting = false;
  double volume = 1, microphoneLevel = 0;
  int generation = 0;
  final channels = <SSHSession>[];
  final subscriptions = <StreamSubscription<dynamic>>[];
  final watchdogs = <Timer>[];
  bool get streaming => channels.isNotEmpty;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final found = await discoverMedia(widget.device, widget.session);
      if (!mounted) return;
      setState(() {
        inventory = found;
        camera = found.inputs.where((i) => i.camera).firstOrNull;
        microphone = found.inputs.where((i) => !i.camera).firstOrNull;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void stop({bool repaint = true}) {
    generation++;
    for (final timer in watchdogs) {
      timer.cancel();
    }
    watchdogs.clear();
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    subscriptions.clear();
    for (final channel in channels) {
      try {
        channel.stdin.add(utf8.encode('q\n'));
        channel.kill(SSHSignal.TERM);
      } catch (_) {}
      // Give FFmpeg its quit request before closing its SSH channel.
      Timer(const Duration(milliseconds: 500), channel.close);
    }
    channels.clear();
    unawaited(audio.invokeMethod<void>('stop').catchError((Object _) {}));
    starting = false;
    microphoneLevel = 0;
    if (mounted && repaint) setState(() {});
  }

  Future<void> start() async {
    stop();
    final token = generation;
    setState(() {
      starting = true;
      error = null;
      frame = null;
    });
    try {
      final client = widget.session.client;
      if (client == null ||
          !widget.session.isConnected ||
          widget.session.deviceId != widget.device.id) {
        throw StateError('Device disconnected.');
      }
      for (final input in [camera, microphone].whereType<MediaInput>()) {
        if (!input.camera) await audio.invokeMethod<void>('start');
        if (!mounted || token != generation) {
          unawaited(audio.invokeMethod<void>('stop').catchError((Object _) {}));
          return;
        }
        final opening = client.execute(
          mediaCaptureCommand(input, inventory!.windows),
        );
        unawaited(
          opening.then<void>((channel) {
            if (!mounted || generation != token) channel.close();
          }, onError: (Object _) {}),
        );
        final channel = await opening.timeout(const Duration(seconds: 10));
        if (!mounted || generation != token) {
          channel.close();
          return;
        }
        channels.add(channel);
        final errors = StringBuffer();
        subscriptions.add(
          channel.stderr.listen((bytes) {
            if (errors.length < 4096) {
              errors.write(utf8.decode(bytes, allowMalformed: true));
            }
          }),
        );
        final frames = JpegFrames();
        final watchdog = Timer(
          const Duration(seconds: 20),
          () => fail(
            'No media received. Check remote capture permissions and whether another app is using this input.',
            token,
          ),
        );
        watchdogs.add(watchdog);
        final sub = channel.stdout.listen(null);
        subscriptions.add(sub);
        var odd = <int>[];
        sub.onData((Uint8List bytes) async {
          if (generation != token || !mounted) return;
          watchdog.cancel();
          try {
            if (input.camera) {
              final images = frames.add(bytes);
              if (images.isNotEmpty) setState(() => frame = images.last);
            } else {
              sub.pause();
              final data = Uint8List.fromList([...odd, ...bytes]);
              final even = data.length & ~1;
              odd = data.sublist(even);
              final samples = ByteData.sublistView(data);
              var peak = 0;
              for (var offset = 0; offset < even; offset += 2) {
                final sample = samples.getInt16(offset, Endian.little);
                if (sample.abs() > peak) peak = sample.abs();
                samples.setInt16(
                  offset,
                  (sample * volume).round(),
                  Endian.little,
                );
              }
              if (mounted && generation == token) {
                setState(() => microphoneLevel = peak / 32768);
              }
              if (even > 0) {
                await audio.invokeMethod<void>(
                  'write',
                  Uint8List.sublistView(data, 0, even),
                );
              }
              if (generation == token) sub.resume();
            }
          } catch (e) {
            fail('$e', token);
          }
        });
        sub.onError((Object e) => fail('$e', token));
        unawaited(
          channel.done.then<void>((_) {
            fail(
              errors.isEmpty
                  ? 'Capture ended. Start again to reconnect. Streams are limited to 10 minutes.'
                  : errors.toString(),
              token,
            );
          }, onError: (Object e) => fail('$e', token)),
        );
      }
    } catch (e) {
      fail('$e', token);
    } finally {
      if (mounted && token == generation) setState(() => starting = false);
    }
  }

  void fail(String message, int token) {
    if (!mounted || generation != token) return;
    stop();
    setState(() => error = message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stop(repaint: false);
    super.dispose();
  }

  Widget selector(bool video) {
    final options =
        inventory?.inputs.where((i) => i.camera == video).toList() ?? [];
    if (options.isEmpty) {
      return Text(
        inventory?.ffmpeg == false
            ? 'Detection needs FFmpeg on the remote device.'
            : video
            ? 'No camera detected. Check hardware and capture permissions.'
            : 'No microphone detected. Check hardware and permissions; Linux also needs alsa-utils.',
      );
    }
    return DropdownButtonFormField<MediaInput>(
      key: ValueKey('${video}_${identityHashCode(inventory)}'),
      initialValue: video ? camera : microphone,
      decoration: InputDecoration(labelText: video ? 'Camera' : 'Microphone'),
      items: [
        const DropdownMenuItem<MediaInput>(value: null, child: Text('Off')),
        for (final input in options)
          DropdownMenuItem(
            value: input,
            child: Text(input.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      isExpanded: true,
      onChanged: streaming || starting
          ? null
          : (value) => setState(() {
              if (video) {
                camera = value;
              } else {
                microphone = value;
              }
            }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.device.name} media'),
      actions: [
        IconButton(
          onPressed: streaming || starting || loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed:
                  !loading &&
                      !starting &&
                      !streaming &&
                      inventory?.ffmpeg == true &&
                      (camera != null || microphone != null)
                  ? start
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
            ),
            OutlinedButton.icon(
              onPressed: streaming || starting ? stop : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          ],
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (inventory?.ffmpeg == false)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FFmpeg unavailable',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'FFmpeg is not installed or is not available to this SSH account. Capture is disabled.',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      inventory!.windows
                          ? 'Install a Windows FFmpeg build, add its bin folder to the system PATH, reconnect SSH, then run ffmpeg -version. Enable camera and microphone access for desktop apps in Windows Settings.'
                          : 'Debian / Ubuntu / Raspberry Pi OS:\nsudo apt update\nsudo apt install ffmpeg alsa-utils\nffmpeg -version\nThe SSH account needs camera and audio device permissions.',
                    ),
                    TextButton(
                      onPressed: loading ? null : load,
                      child: const Text('Check again'),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.videocam),
                      SizedBox(width: 8),
                      Text(
                        'Camera',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!loading) selector(true),
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: ColoredBox(
                      color: Colors.black,
                      child: frame == null
                          ? const Center(
                              child: Text(
                                'Camera preview',
                                style: TextStyle(color: Colors.white70),
                              ),
                            )
                          : Image.memory(
                              frame!,
                              gaplessPlayback: true,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Center(
                                child: Text('Invalid camera frame'),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.mic),
                      SizedBox(width: 8),
                      Text(
                        'Microphone',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!loading) selector(false),
                  const SizedBox(height: 12),
                  const Text('Input activity'),
                  LinearProgressIndicator(value: microphoneLevel),
                  Row(
                    children: [
                      const Icon(Icons.volume_up),
                      Expanded(
                        child: Slider(
                          value: volume,
                          label: '${(volume * 100).round()}%',
                          onChanged: (value) => setState(() => volume = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!loading && inventory?.ffmpeg == true)
            TextButton.icon(
              onPressed: streaming || starting ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry detection'),
            ),
          const SizedBox(height: 16),
          if (starting) const LinearProgressIndicator(),
          if (streaming) const Text('Live capture active'),
          if (error != null)
            SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
