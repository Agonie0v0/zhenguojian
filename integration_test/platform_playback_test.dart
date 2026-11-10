import 'dart:io';

import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/media_pipeline.dart';
import 'package:duanju_app/vertical_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart' show DeviceFixtureRepository;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native video decode, HLS, CENC, seek, swipe and remux', (tester) async {
    MediaKit.ensureInitialized();
    final repository = DeviceFixtureRepository();
    await repository.initialize();
    final store = LocalStore(await SharedPreferences.getInstance());
    final detail = await repository.detail(DeviceFixtureRepository.drama);
    final samples = <Map<String, Object?>>[];

    Future<void> until(bool Function() ready, String label) async {
      final timer = Stopwatch()..start();
      while (!ready()) {
        if (timer.elapsed > const Duration(seconds: 45)) fail('Timeout: $label');
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    for (final episode in detail.episodes) {
      final plan = await repository.resolve(detail.drama, episode);
      final player = Player();
      final controller = VideoController(player);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Video(controller: controller))));
      if (plan.decryptionKey.isNotEmpty && player.platform is NativePlayer) {
        await (player.platform as NativePlayer).setProperty('demuxer-lavf-o', 'decryption_key=${plan.decryptionKey}');
      }
      await player.setVolume(0);
      await player.open(Media(plan.url, httpHeaders: plan.headers));
      await until(() => (player.state.width ?? 0) > 0 && player.state.position.inMilliseconds > 500, 'decode ${episode.number}');
      await player.seek(const Duration(seconds: 5));
      await until(() => player.state.position.inSeconds >= 5, 'seek');
      await player.pause();
      expect(player.state.playing, isFalse);
      await player.setRate(1.5);
      await player.play();
      samples.add({'episode': episode.number, 'width': player.state.width, 'height': player.state.height, 'positionMs': player.state.position.inMilliseconds});
      await tester.pumpWidget(const SizedBox.shrink());
      await player.dispose();
      await repository.release(plan.session);
    }

    final temporary = await Directory.systemTemp.createTemp('zgj-integration-');
    try {
      final executor = FFmpegExecutor();
      final output = '${temporary.path}/remuxed.mkv';
      const base = String.fromEnvironment('FIXTURE_BASE_URL');
      await executor.run(['-i', '$base/clear.mp4', '-map', '0', '-c', 'copy', output]);
      verifyMediaDuration(await executor.probe(output), 20);
    } finally {
      await temporary.delete(recursive: true);
    }

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VerticalFeedScreen(repository: repository, store: store, singleDrama: detail.drama))));
    await until(() => find.byType(Video).evaluate().isNotEmpty, 'feed player');
    Player feedPlayer() => tester.widget<Video>(find.byType(Video).first).controller.player;
    await until(() => (feedPlayer().state.width ?? 0) > 0, 'feed decoded');
    await tester.fling(find.byType(Video).first, const Offset(0, -300), 1200);
    await until(() => repository.resolved.last == 2 && (feedPlayer().state.width ?? 0) > 0, 'swipe to episode 2');
    expect(tester.takeException(), isNull);
    binding.reportData = {'platform': Platform.operatingSystem, 'decodedSamples': samples, 'remux': true, 'feedSwipe': true};
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    store.dispose();
  });
}
