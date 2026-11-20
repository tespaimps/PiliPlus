import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/download/download/widgets/owner.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download/view.dart';
import 'package:PiliPlus/pages/download/owner/view.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

import 'download_owner_test.dart' as fixture;

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
  final Box<dynamic>? folderBox;
  Object? saved;
  bool failSave = false;

  _Downloads({this.folderBox});

  @override
  void initDownloadList() {
    restoreFolderLayout('test');
    waitForInitialization = Future<void>.value();
  }

  @override
  Object? readFolderLayout(String key) => folderBox?.get(key) ?? saved;

  @override
  Future<void> writeFolderLayout(String key, Map<String, Object> data) async {
    if (failSave) throw const FileSystemException('Write failed');
    if (folderBox case final box?) {
      await box.put(key, data);
    } else {
      saved = jsonDecode(jsonEncode(data));
    }
  }
}

List<BiliDownloadEntryInfo> _folderEntries() => [
  fixture.entry(1, ownerId: 10, ownerName: '同名 UP 主', cover: 'first.jpg'),
  fixture.entry(2, ownerId: 10, ownerName: '同名 UP 主', bytes: 2),
  fixture.entry(3, ownerId: 20, ownerName: '同名 UP 主', bytes: 3),
  fixture.entry(4, ownerId: 20, ownerName: '同名 UP 主', bytes: 4),
  fixture.entry(5, ownerId: 30, ownerName: '独立作者', bytes: 5),
  fixture.entry(6, ownerId: 40, ownerName: '另一作者', bytes: 6),
];

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

  for (final (label, keys, ids) in [
    ('folder and video', ['owner:id:10', 'page:5'], [1, 2, 5]),
    ('two folders', ['owner:id:10', 'owner:id:20'], [1, 2, 3, 4]),
    ('two videos', ['page:5', 'page:6'], [5, 6]),
  ]) {
    test(
      'merges $label without folding later videos into the new group',
      () async {
        final downloads = _Downloads()..downloadList.addAll(_folderEntries());
        Get.put<DownloadService>(downloads);
        addTearDown(Get.reset);
        final selection = downloads.captureFolderSelection(
          downloads.downloadIndex.rootItems.where(
            (item) => keys.contains(downloadSelectionKey(item)),
          ),
        );
        await downloads.mergeFolders(selection, '我的文件夹');
        final folder = downloads.folderIndex.folders.singleWhere(
          (item) => item.group.name == '我的文件夹',
        );
        expect(folder.group.entries.map((e) => e.avid), ids);
        expect(folder.group.videoCount, ids.length);
        expect(folder.group.seasons.whereType<DownloadOwnerFolder>(), isEmpty);
        final restored = DownloadFolderIndex([
          ..._folderEntries(),
          fixture.entry(1, ownerId: 10, cid: 101),
          fixture.entry(7, ownerId: 10),
          fixture.entry(8, ownerId: 10),
        ], DownloadFolderLayout.fromJson(downloads.saved));
        expect(
          restored
              .folder(folder.group.key)!
              .group
              .entries
              .map((e) => e.avid)
              .toSet(),
          ids.toSet(),
        );
        expect(restored.locations('video:7'), {'id:10'});
        expect(restored.locations('video:8'), {'id:10'});
        expect(
          restored.locations('video:1'),
          ids.contains(1) ? {folder.group.key} : {'id:10'},
        );
      },
    );
  }

  test(
    'restores a renamed auto folder from Hive and keeps its author identity',
    () async {
      final temp = Directory.systemTemp.createTempSync('pili-hive-folders');
      addTearDown(() => temp.deleteSync(recursive: true));
      final box = await Hive.openBox<dynamic>(
        'folder_layout_test',
        path: temp.path,
      );
      final downloads = _Downloads(folderBox: box)
        ..downloadList.addAll(_folderEntries())
        ..initDownloadList();
      final previous = downloads.folderIndex.folder('id:10')!;
      await downloads.renameFolder(downloads.folderStorageKey, 'id:10', '我的作者');
      expect(
        downloads.folderIndex.folder('id:10')!.pages,
        same(previous.pages),
      );
      final selected = downloads.captureFolderSelection(
        downloads.downloadIndex.rootItems.where(
          (item) => item is! DownloadOwnerFolder,
        ),
      );
      await downloads.mergeFolders(selected, '持久化文件夹');
      await box.close();
      final reopened = await Hive.openBox<dynamic>(
        'folder_layout_test',
        path: temp.path,
      );
      addTearDown(reopened.close);
      final fresh = _Downloads(folderBox: reopened)
        ..downloadList.addAll([
          fixture.entry(7, ownerId: 10, ownerName: '作者换了名字'),
          ..._folderEntries(),
        ])
        ..initDownloadList();
      expect(fresh.folderIndex.folder('id:10')!.group.name, '我的作者');
      expect(fresh.folderIndex.folder('id:10')!.group.videoCount, 3);
      expect(fresh.folderIndex.folder('id:20')!.group.name, '同名 UP 主');
      final manual = fresh.folderIndex.folders.singleWhere(
        (folder) => folder.group.name == '持久化文件夹',
      );
      expect(manual.group.entries.map((e) => e.avid), [5, 6]);
      await fresh.moveToFolder(
        fresh.captureFolderSelection(manual.group.seasons),
        'id:20',
      );
      expect(fresh.folderIndex.folder(manual.group.key), isNull);
      expect(
        DownloadFolderLayout.fromJson(reopened.get('test')).names,
        isNot(contains(manual.group.key)),
      );
    },
  );

  test(
    'keeps source and target intact after write failure or a stale selection',
    () async {
      final downloads = _Downloads()
        ..downloadList.addAll(_folderEntries())
        ..initDownloadList();
      final source = downloads.folderIndex.folder('id:10')!.group.seasons.first;
      final selection = downloads.captureFolderSelection([source]);
      final snapshot = downloads.downloadIndex;
      downloads.failSave = true;
      await expectLater(
        downloads.moveToFolder(selection, 'id:20'),
        throwsA(isA<FileSystemException>()),
      );
      expect(downloads.downloadIndex, same(snapshot));
      expect(downloads.folderIndex.locations('video:1'), {'id:10'});
      downloads.failSave = false;
      await downloads.moveToFolder(selection, 'id:20');
      expect(downloads.folderIndex.folder('id:10'), isNull);
      final target = downloads.folderIndex.folder('id:20')!.group;
      expect(target.videoCount, 3);
      expect(target.totalBytes, 8);
      expect(target.cover, 'first.jpg');
      await expectLater(
        downloads.moveToFolder(selection, 'id:20'),
        throwsA(isA<DownloadFolderException>()),
      );
      final next = downloads.captureFolderSelection([
        downloads.downloadIndex.rootItems.last,
      ]);
      await expectLater(
        downloads.moveToFolder(next, 'id:10'),
        throwsA(isA<DownloadFolderException>()),
      );
    },
  );

  testWidgets(
    'cancels a blank merge then saves a named folder and renames it by long press',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final downloads = _Downloads()
        ..downloadList.addAll(_folderEntries().skip(4))
        ..downloadList.add(fixture.entry(7, ownerId: 50));
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
      await tester.tap(find.byTooltip('多选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flutter教程 7'));
      await tester.pumpAndSettle();
      final buttons = ['全选', '合并', '移动', '更新', '移除'];
      final left = buttons
          .map((text) => tester.getTopLeft(find.text(text)).dx)
          .toList();
      expect(left, [...left]..sort());
      await tester.tap(find.text('合并'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '确定'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.text('已选: 2'), findsOneWidget);
      await tester.tap(find.text('合并'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '工作资料');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('命名合并文件夹'), findsNothing);
      expect(find.text('工作资料'), findsOneWidget);
      await tester.longPress(find.text('工作资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新名称');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('重命名文件夹'), findsNothing);
      expect(find.text('新名称'), findsOneWidget);
      expect(downloads.folderIndex.folders.single.group.videoCount, 2);
      await tester.tap(find.byTooltip('多选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flutter教程 7'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新名称'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('是'));
      await tester.pumpAndSettle();
      expect(downloads.folderIndex.folders.single.group.videoCount, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'moves from a folder through search and preserves the query after declining',
    (tester) async {
      final downloads = _Downloads()
        ..downloadList.addAll(_folderEntries().skip(1));
      downloads.downloadList.insert(
        0,
        fixture.entry(1, ownerId: 10, ownerName: '同名 UP 主'),
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
      await tester.tap(find.text('同名 UP 主').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('多选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flutter教程 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadOwnerPage), findsNothing);
      expect(find.text('移动到文件夹'), findsOneWidget);
      expect(find.textContaining('UID 10'), findsNothing);
      await tester.enterText(find.byType(TextField), '  up 主 ');
      await tester.pumpAndSettle();
      final target = find.text('UID 20 · 2 个视频');
      expect(target, findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.textContaining('Flutter教程 1'), findsOneWidget);
      await tester.tap(find.text('否'));
      await tester.pumpAndSettle();
      expect(find.text('  up 主 '), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.tap(find.text('是'));
      await tester.pumpAndSettle();
      expect(find.text('移动到文件夹'), findsNothing);
      expect(downloads.folderIndex.locations('video:1'), {'id:20'});
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'reopening reuses the index and a batch publishes one new snapshot',
    () async {
      final downloads = _Downloads();
      final temp = Directory.systemTemp.createTempSync('pili-cache-batch');
      addTearDown(() => temp.deleteSync(recursive: true));
      addTearDown(Get.reset);
      for (final entry in _folder('测试UP主').group.entries) {
        downloads.downloadList.add(
          entry..pageDirPath = '${temp.path}/${entry.avid}',
        );
      }
      Get.put<DownloadService>(downloads);

      final first = DownloadController()..onInit();
      await Future<void>.delayed(Duration.zero);
      final index = downloads.downloadIndex;
      first.onSelect(first.items.single);
      first.onClose();

      final reopened = DownloadController()..onInit();
      addTearDown(reopened.onClose);
      await Future<void>.delayed(Duration.zero);
      expect(downloads.downloadIndex, same(index));
      expect(reopened.items.single.checked, isFalse);
      final flag = reopened.flag.value;

      await downloads.deletePage(pageDirPath: '${temp.path}/1', refresh: false);
      await downloads.deletePage(pageDirPath: '${temp.path}/2', refresh: false);
      expect(reopened.flag.value, flag);
      downloads.notifyDownloadListChanged();
      await Future<void>.delayed(Duration.zero);
      expect(reopened.flag.value, flag + 1);
      expect(reopened.items, isEmpty);
      expect(downloads.downloadIndex, isNot(same(index)));
    },
  );

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
      final temp = Directory.systemTemp.createTempSync('pili-cache-test');
      addTearDown(() => temp.deleteSync(recursive: true));
      downloads.downloadList.addAll(folder.group.entries);
      for (final entry in downloads.downloadList) {
        entry.pageDirPath = '${temp.path}/${entry.avid}';
      }
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
      final index = downloads.downloadIndex;
      final controller = Get.find<DownloadController>();
      final ownerSeasons = index.owners['id:10']!.seasons;
      expect(controller.ownerSeasons('id:10'), same(ownerSeasons));
      expect(controller.items.first, isNot(same(index.rootItems.first)));
      expect(find.byType(DownloadOwnerItem), findsOneWidget);
      expect(find.text('视频1'), findsNothing);
      expect(find.text('其他作者视频'), findsOneWidget);
      await tester.tap(find.text('测试UP主'));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadOwnerPage), findsOneWidget);
      expect(find.text('视频1'), findsOneWidget);
      expect(find.text('视频2'), findsOneWidget);
      expect(find.text('其他作者视频'), findsNothing);
      expect(downloads.downloadIndex, same(index));
      await tester.runAsync(
        () => downloads.deletePage(
          pageDirPath: '${temp.path}/2',
          refresh: false,
        ),
      );
      downloads.notifyDownloadListChanged();
      await tester.pumpAndSettle();
      final reduced = downloads.downloadIndex;
      expect(reduced, isNot(same(index)));
      expect(
        reduced.rootItems.any((item) => item is DownloadOwnerFolder),
        isFalse,
      );
      expect(find.text('视频1'), findsOneWidget);
      expect(find.text('视频2'), findsNothing);
      await tester.runAsync(
        () => downloads.deletePage(
          pageDirPath: '${temp.path}/1',
          refresh: false,
        ),
      );
      downloads.notifyDownloadListChanged();
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
