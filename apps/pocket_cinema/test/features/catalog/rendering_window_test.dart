import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_cinema/features/catalog/rendering_window.dart';

void main() {
  test(
    'Sparse rendering includes idle time instead of claiming display FPS',
    () {
      final window = RenderingWindow();
      window.add(
        const RenderSample(finishedUs: 1000000, buildUs: 1000, rasterUs: 1000),
      );
      expect(window.sample(2000000, 60).fps, 0.5);
      expect(window.sample(4000000, 60).fps, 0);
    },
  );

  test('Slow frame detection uses the current display budget and expires', () {
    final window = RenderingWindow();
    window.add(
      const RenderSample(finishedUs: 1000000, buildUs: 9000, rasterUs: 2000),
    );
    window.add(
      const RenderSample(finishedUs: 1500000, buildUs: 2000, rasterUs: 40000),
    );
    expect(window.sample(2000000, 60).slowFrames, 1);
    final fastDisplay = window.sample(2000000, 120);
    expect(fastDisplay.slowFrames, 2);
    expect(fastDisplay.rasterMs, 40);
    expect(window.sample(4000000, 120).slowFrames, 0);
  });
}
