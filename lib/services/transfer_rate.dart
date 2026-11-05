/// Rolling throughput over the last three seconds, including idle samples.
class TransferRate {
  final List<({int milliseconds, int bytes})> _samples = [];
  int _lastBytes = 0;
  int? _lastProgress;

  void reset() {
    _samples.clear();
    _lastBytes = 0;
    _lastProgress = null;
  }

  double sample(int bytes, Duration elapsed) {
    final now = elapsed.inMilliseconds;
    if (bytes > _lastBytes) _lastProgress = now;
    _lastBytes = bytes;
    _samples.add((milliseconds: now, bytes: bytes));
    while (_samples.length > 2 && _samples[1].milliseconds <= now - 3000) {
      _samples.removeAt(0);
    }
    final first = _samples.first;
    final interval = now - first.milliseconds;
    return interval > 0 ? (bytes - first.bytes) * 1000 / interval : 0;
  }

  Duration idleFor(Duration elapsed) =>
      Duration(milliseconds: elapsed.inMilliseconds - (_lastProgress ?? 0));
}
