import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/vertical_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// 用固定 key 挂载，保证 `active` 变化时是 `didUpdateWidget` 而不是重建 State。
  Future<void> pumpFeed(
    WidgetTester tester, {
    required RouteRepository repository,
    required ScriptedPlayer player,
    required LocalStore store,
    required bool active,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: VerticalFeedScreen(
            key: const ValueKey('feed'),
            repository: repository,
            store: store,
            embedded: true,
            singleDrama: FixtureRepository.free,
            active: active,
            playerFactory: () => Player(platformPlayer: player),
            // 测试环境不创建 VideoController（会走原生通道并失败）。
            videoBuilder: (controls) => controls,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<(LocalStore, RouteRepository, ScriptedPlayer)> setUpFeed(
    WidgetTester tester, {
    required bool active,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 880);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues(const {});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    await pumpFeed(
      tester,
      repository: repository,
      player: player,
      store: store,
      active: active,
    );
    return (store, repository, player);
  }

  testWidgets('当前页能正常开始加载并播放（回归：0.3.5 曾卡在"正在加载视频…"）', (tester) async {
    final (_, _, player) = await setUpFeed(tester, active: true);
    expect(
      player.opened,
      hasLength(1),
      reason: '当前页挂载后必须真的把媒体交给播放器，否则界面会一直卡在加载中',
    );
    expect(find.text('正在加载视频…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未激活的页面不创建播放器，变为当前页后才加载', (tester) async {
    final (store, repository, player) = await setUpFeed(tester, active: false);
    expect(player.opened, isEmpty);
    await pumpFeed(
      tester,
      repository: repository,
      player: player,
      store: store,
      active: true,
    );
    expect(player.opened, hasLength(1));
  });

  testWidgets('Windows 播放快捷键在普通和全屏画面均可使用', (tester) async {
    final fullscreen = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        if (call.method == 'setFullScreen') {
          fullscreen.add((call.arguments as Map)['isFullScreen'] as bool);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    final (store, repository, player) = await setUpFeed(tester, active: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(player.state.playing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(player.state.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(player.state.position, const Duration(seconds: 5));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    expect(player.state.position, Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester);
    expect(player.state.volume, 95);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(tester);
    expect(player.state.volume, 100);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await settle(tester);
    expect(player.state.volume, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await settle(tester);
    expect(player.state.volume, 100);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.state.rate, 3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    expect(player.state.rate, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await settle(tester);
    expect(fullscreen.last, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(player.state.playing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await settle(tester);
    expect(fullscreen.last, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await settle(tester);
    expect(fullscreen.last, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(fullscreen.last, isFalse);
    final toggles = fullscreen.length;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(fullscreen, hasLength(toggles));
    await pumpFeed(
      tester,
      repository: repository,
      player: player,
      store: store,
      active: false,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await settle(tester);
    expect(player.state.volume, 100);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
