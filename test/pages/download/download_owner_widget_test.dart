import 'dart:convert';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/download/download/widgets/owner.dart';
import 'package:PiliPlus/pages/download/download/view.dart';
import 'package:PiliPlus/pages/download/owner/view.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class _SettingsBox extends Fake implements Box<dynamic> {
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => defaultValue;
}

class _Images extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('AssetManifest.bin')) {
      return const StandardMessageCodec().encodeMessage(<String, dynamic>{})!;
    }
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    return ByteData.sublistView(bytes);
  }
}

class _ProgressBox extends Fake implements Box<int> {
  @override
  int? get(dynamic key, {int? defaultValue}) => defaultValue;
}

class _Downloads extends DownloadService {
  @override
  void initDownloadList() {
    waitForInitialization = Future<void>.value();
  }
}

DownloadOwnerFolder _folder(String name) {
  final seasons = [
    for (var i = 1; i <= 2; i++)
      BiliDownloadEntryInfo(
          isCompleted: true,
          totalBytes: i * 1024,
          downloadedBytes: i * 1024,
          title: '视频$i',
          cover: '',
          preferedVideoQuality: 80,
          guessedTotalBytes: i * 1024,
          totalTimeMilli: 1,
          danmakuCount: 0,
          avid: i,
          bvid: 'BV$i',
          ownerId: 10,
          ownerName: name,
          pageData: PageInfo(cid: i, page: 1, hasAlias: false, tid: 0),
        )
        ..pageDirPath = '/cache/$i'
        ..entryDirPath = '/cache/$i/entry',
  ];
  return buildDownloadRootItems([
        for (final entry in seasons)
          DownloadSeasonInfo(
            seasonInfo: null,
            pageId: entry.pageId,
            pages: [entry.toDownloadPageInfo(entry.pageId)],
          ),
      ]).single
      as DownloadOwnerFolder;
}

void main() {
  setUpAll(() {
    GStorage.setting = _SettingsBox();
    GStorage.video = _SettingsBox();
    GStorage.watchProgress = _ProgressBox();
  });

  Future<void> pumpCard(
    WidgetTester tester,
    DownloadOwnerFolder folder, {
    required VoidCallback onTap,
    VoidCallback? onDelete,
    bool selecting = false,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: DefaultAssetBundle(
            bundle: _Images(),
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 390,
                  height: 110,
                  child: DownloadOwnerItem(
                    folder: folder,
                    onTap: onTap,
                    onDelete: onDelete ?? () {},
                    updateActions: {'更新弹幕': () {}},
                    enableMultiSelect: selecting,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'home folder opens only its author list and refreshes to single and empty states',
    (tester) async {
      final folder = _folder('测试UP主');
      final downloads = _Downloads();
      downloads.downloadList.addAll(folder.group.entries);
      downloads.downloadList.add(
        BiliDownloadEntryInfo(
            isCompleted: true,
            totalBytes: 1,
            downloadedBytes: 1,
            title: '其他作者视频',
            cover: '',
            preferedVideoQuality: 80,
            guessedTotalBytes: 1,
            totalTimeMilli: 1,
            danmakuCount: 0,
            avid: 99,
            bvid: 'BV99',
            ownerId: 99,
            ownerName: '其他作者',
            pageData: PageInfo(cid: 99, page: 1, hasAlias: false, tid: 0),
          )
          ..pageDirPath = '/cache/99'
          ..entryDirPath = '/cache/99/entry',
      );
      Get.put<DownloadService>(downloads);
    addTearDown(Get.reset);
      await tester.pumpWidget(
        GetMaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          builder: (context, child) =>
              DefaultAssetBundle(bundle: _Images(), child: child!),
          home: const DownloadPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DownloadOwnerItem), findsOneWidget);
      expect(find.text('视频1'), findsNothing);
      expect(find.text('其他作者视频'), findsOneWidget);
      await tester.tap(find.text('测试UP主'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadOwnerPage), findsOneWidget);
      expect(find.text('视频1'), findsOneWidget);
      expect(find.text('视频2'), findsOneWidget);
      expect(find.text('其他作者视频'), findsNothing);
      downloads.downloadList.removeWhere((e) => e.avid == 2);
      downloads.flagNotifier.refresh();
      await tester.pumpAndSettle();
      expect(find.text('视频1'), findsOneWidget);
      expect(find.text('视频2'), findsNothing);
      downloads.downloadList.removeWhere((e) => e.ownerId == 10);
      downloads.flagNotifier.refresh();
      await tester.pumpAndSettle();
      expect(find.text('暂无缓存视频'), findsOneWidget);
      Get.back();
      await tester.pumpAndSettle();
      expect(find.byType(DownloadOwnerItem), findsNothing);
      expect(find.text('其他作者视频'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'folder shows owner title, count badge and sum, and responds to tap',
    (tester) async {
      var taps = 0;
      await pumpCard(tester, _folder('测试UP主'), onTap: () => taps++);
      expect(find.text('测试UP主'), findsOneWidget);
      expect(find.text('2个视频'), findsOneWidget);
      expect(find.text('3.00K'), findsOneWidget);
      expect(find.text('视频1'), findsNothing);
      expect(find.text('视频2'), findsNothing);
      await tester.tap(find.text('测试UP主'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long owner names and enlarged text fit without overflow', (
    tester,
  ) async {
    await pumpCard(
      tester,
      _folder('名字很长的UP主名字很长的UP主名字很长的UP主'),
      onTap: () {},
      scale: 2,
    );
    expect(find.text('2个视频'), findsOneWidget);
    expect(find.text('3.00K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'folder menu deletes the group and is disabled during selection',
    (tester) async {
      var deletes = 0;
      final folder = _folder('测试UP主');
      await pumpCard(tester, folder, onTap: () {}, onDelete: () => deletes++);
      await tester.longPress(find.text('测试UP主'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      await pumpCard(tester, folder, onTap: () {}, selecting: true);
      await tester.longPress(find.text('测试UP主'));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
