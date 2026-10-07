/// A wall-clock window of completed Flutter raster frames. Idle time remains in
/// the denominator; sparse UI updates must not be reported as 60 FPS.
class RenderingWindow {
  final List<RenderSample> _frames = [];
  static const windowUs = 2000000;

  void add(RenderSample frame) => _frames.add(frame);
  void clear() => _frames.clear();

  RenderSummary sample(int nowUs, double refreshHz) {
    _frames.removeWhere((frame) => frame.finishedUs <= nowUs - windowUs);
    final frames = _frames.where((frame) => frame.finishedUs <= nowUs).toList();
    final budgetUs = 1000000 / refreshHz;
    var slow = 0, worstBuildUs = 0, worstRasterUs = 0;
    for (final frame in frames) {
      if (frame.buildUs > budgetUs || frame.rasterUs > budgetUs) slow++;
      if (frame.buildUs > worstBuildUs) worstBuildUs = frame.buildUs;
      if (frame.rasterUs > worstRasterUs) worstRasterUs = frame.rasterUs;
    }
    return RenderSummary(
      fps: frames.length * 1000000 / windowUs,
      slowFrames: slow,
      buildMs: worstBuildUs / 1000,
      rasterMs: worstRasterUs / 1000,
    );
  }
}

class RenderSample {
  const RenderSample({
    required this.finishedUs,
    required this.buildUs,
    required this.rasterUs,
  });
  final int finishedUs, buildUs, rasterUs;
}

class RenderSummary {
  const RenderSummary({
    required this.fps,
    required this.slowFrames,
    required this.buildMs,
    required this.rasterMs,
  });
  final double fps, buildMs, rasterMs;
  final int slowFrames;
}
