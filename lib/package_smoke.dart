import 'dart:convert';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'core_bridge.dart';
import 'media_pipeline.dart';
import 'models.dart';
import 'upstream_config.dart';

Future<void> runSourceSmoke(List<String> arguments) async {
  if (arguments.length != 2) exit(2);
  final report = File(arguments[1]);
  final repository = NativeRepository();
  final sources = <Map<String, Object?>>[];
  try {
    await repository.initialize();
    await refreshUpstreamConfig(repository);
    for (final source in SourceSite.values) {
      Player? player;
      PlaybackPlan? plan;
      final evidence = <String, Object?>{'source': source.id, 'ok': false};
      try {
        final catalog = await repository.catalog(source.id).timeout(const Duration(seconds: 40));
        if (catalog.items.isEmpty) throw StateError('Source catalog is empty');
        final detail = await repository.detail(catalog.items.first).timeout(const Duration(seconds: 30));
        if (detail.episodes.isEmpty) throw StateError('Source has no playable episodes');
        plan = await repository.resolve(detail.drama, detail.episodes.first).timeout(const Duration(seconds: 50));
        player = Player(configuration: const PlayerConfiguration(muted: true, vo: 'null'));
        await player.setAudioTrack(AudioTrack.no());
        await player.setVideoTrack(VideoTrack.auto());
        if (plan.decryptionKey.isNotEmpty && player.platform is NativePlayer) {
          await (player.platform as NativePlayer).setProperty('demuxer-lavf-o', 'decryption_key=${plan.decryptionKey}');
        }
        await player.open(Media(plan.url, httpHeaders: plan.headers));
        final timer = Stopwatch()..start();
        while (player.state.position.inMilliseconds < 500 || (player.state.width ?? 0) <= 0) {
          if (timer.elapsed > const Duration(seconds: 25)) throw StateError('Video did not decode');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        evidence.addAll({'ok': true, 'width': player.state.width, 'height': player.state.height, 'positionMs': player.state.position.inMilliseconds});
      } catch (error) {
        evidence['error'] = error.toString();
      } finally {
        await player?.dispose();
        if (plan != null) await repository.release(plan.session);
      }
      sources.add(evidence);
      await report.writeAsString(jsonEncode({'sources': sources}), flush: true);
    }
    final ok = sources.isNotEmpty && sources.every((source) => source['ok'] == true);
    await report.writeAsString(jsonEncode({'ok': ok, 'sources': sources}), flush: true);
    exit(ok ? 0 : 1);
  } catch (error) {
    await report.writeAsString(jsonEncode({'ok': false, 'error': error.toString(), 'sources': sources}), flush: true);
    exit(1);
  }
}

Future<void> runPackageSmoke(List<String> arguments) async {
  if (arguments.length != 3) exit(2);
  final report = File(arguments[1]), input = arguments[2];
  Player? player;
  try {
    final repository = NativeRepository();
    await repository.initialize();
    final executor = FFmpegExecutor();
    final probe = await executor.probe(input);
    verifyMediaDuration(probe, 3);
    final remuxed = File(
      '${report.parent.path}${Platform.pathSeparator}remuxed.mkv',
    );
    await executor.run([
      '-i',
      input,
      '-map',
      '0:v:0',
      '-c',
      'copy',
      remuxed.path,
    ]);
    verifyMediaDuration(await executor.probe(remuxed.path), 3);
    player = Player(
      configuration: const PlayerConfiguration(muted: true, vo: 'null'),
    );
    await player.setAudioTrack(AudioTrack.no());
    await player.setVideoTrack(VideoTrack.auto());
    final advancing = player.stream.position.firstWhere(
      (time) => time.inMilliseconds >= 400,
    );
    await player.open(Media(remuxed.path));
    await advancing.timeout(const Duration(seconds: 20));
    await report.writeAsString(
      jsonEncode({
        'ok': true,
        'nativeCore': true,
        'ffprobe': true,
        'remux': true,
        'mediaKitPlayback': true,
      }),
      flush: true,
    );
    await player.dispose();
    exit(0);
  } catch (error) {
    await player?.dispose();
    await report.writeAsString(
      jsonEncode({'ok': false, 'error': error.toString()}),
      flush: true,
    );
    exit(1);
  }
}
