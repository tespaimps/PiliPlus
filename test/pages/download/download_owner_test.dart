import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/models_new/download/download_sort.dart';
import 'package:flutter_test/flutter_test.dart';

BiliDownloadEntryInfo entry(
  int aid, {
  int? ownerId,
  String? ownerName,
  SeasonInfo? season,
  int? cid,
  int bytes = 1,
  String cover = '',
  int created = 0,
}) =>
    BiliDownloadEntryInfo(
        isCompleted: true,
        totalBytes: bytes,
        downloadedBytes: 1,
        title: 'Flutter教程 $aid',
        cover: cover,
        preferedVideoQuality: 80,
        guessedTotalBytes: 1,
        totalTimeMilli: 1000,
        danmakuCount: 0,
        timeUpdateStamp: 1000000 - aid,
        timeCreateStamp: created,
        avid: aid,
        bvid: 'BV$aid',
        ownerId: ownerId,
        ownerName: ownerName,
        seasonInfo: season,
        pageData: PageInfo(
          cid: cid ?? aid,
          page: 1,
          hasAlias: false,
          tid: 0,
          part: '第一节',
        ),
      )
      ..pageDirPath = '/cache/$aid'
      ..entryDirPath = '/cache/$aid/${cid ?? aid}';

DownloadSeasonInfo video(BiliDownloadEntryInfo e) => DownloadSeasonInfo(
  seasonInfo: e.seasonInfo,
  pageId: e.pageId,
  pages: [e.toDownloadPageInfo(e.pageId)],
);

void main() {
  test('sorts folders using date bounds, size, displayed name and type', () {
    final index = DownloadFolderIndex([
      entry(1, ownerId: 10, created: 10, bytes: 3),
      entry(2, ownerId: 10, created: 90, bytes: 4),
      entry(3, ownerId: 30, created: 50, bytes: 20),
      entry(4),
    ], DownloadFolderLayout(names: {'id:10': 'A folder'}));
    final items = index.snapshot().rootItems;
    List<String> order(DownloadSortField field, bool ascending) =>
        sortDownloads(items, (
          field: field,
          ascending: ascending,
        )).map(downloadSelectionKey).toList();
    expect(order(DownloadSortField.created, true), [
      'owner:id:10',
      'page:3',
      'page:4',
    ]);
    expect(order(DownloadSortField.created, false), [
      'owner:id:10',
      'page:3',
      'page:4',
    ]);
    expect(order(DownloadSortField.size, false).first, 'page:3');
    expect(order(DownloadSortField.name, true).first, 'owner:id:10');
    expect(order(DownloadSortField.type, false).first, 'owner:id:10');
    expect(order(DownloadSortField.type, true).last, 'owner:id:10');
    expect(decodeDownloadSort(['size', true]), (
      field: DownloadSortField.size,
      ascending: true,
    ));
    expect(decodeDownloadSort(['missing', true]), defaultDownloadSort);
  });

  test('indexes matching parts under one searchable manuscript', () {
    final index = DownloadFolderIndex([
      entry(1, ownerId: 10, ownerName: 'UP主'),
      entry(1, ownerId: 10, cid: 101),
    ], DownloadFolderLayout());
    final video = index.searchVideos.values.single;
    expect(video.card.pages.single.entries, hasLength(2));
    expect(video.matches('第一'), isTrue);
    expect(video.matchingPart('第一'), '第一节');
    expect(video.matches('up主'), isTrue);
  });

  final fixtureRoot = Platform.environment['PILI_CACHE_PROFILE_FIXTURES'];
  for (final size in [1000, 10000]) {
    test('renames and moves only affected groups in a $size video library', () {
      var visits = 0;
      final layout = DownloadFolderLayout();
      final index = DownloadFolderIndex(
        Iterable.generate(size, (i) {
          visits++;
          return entry(i + 1, ownerId: (i ~/ 2) + 1);
        }),
        layout,
      );
      final untouched = index.folder('id:3')!;
      final target = index.folder('id:2')!;
      final rename = layout.copy()..names['id:2'] = 'Target Folder';
      index.apply(rename, renamed: 'id:2');
      expect(index.folder('id:2')!.pages, same(target.pages));
      expect(
        index.folders
            .where((f) => f.group.searchName.contains('target'))
            .single
            .group
            .key,
        'id:2',
      );
      final move = rename.copy()..destinations['video:1'] = 'id:2';
      index.apply(move, moved: {'video:1'});
      expect(index.folder('id:3'), same(untouched));
      expect(index.folder('id:2')!.group.videoCount, 3);
      expect(index.folder('id:2')!.group.name, 'Target Folder');
      expect(index.snapshot().rootItems.length, size ~/ 2);
      final cards = index.searchVideos;
      expect(cards.length, size);
      final hits = cards.values
          .where((video) => video.matches('教程'))
          .map((v) => v.card);
      expect(sortDownloads(hits, defaultDownloadSort).length, size);
      expect(index.searchVideos, same(cards));
      expect(visits, size);
    });

    test('indexes $size cache entries with a single source traversal', () {
      final source = [
        for (var i = 0; i < size; i++)
          entry(
            i + 1,
            ownerId: i < size ~/ 2 ? 1 : i + 1,
            ownerName: i < size ~/ 2 ? '性能样本 UP 主' : '作者 ${i + 1}',
          ),
      ];
      var visits = 0;
      final snapshot = DownloadListSnapshot.build(
        source.map((entry) {
          visits++;
          return entry;
        }),
      );
      final group = snapshot.owners['id:1']!;
      expect(snapshot.seasons.length, size);
      expect(snapshot.rootItems.length, size ~/ 2 + 1);
      expect(group.videoCount, size ~/ 2);
      expect(group.totalBytes, size ~/ 2);
      expect(visits, size);
      if (fixtureRoot != null && fixtureRoot.isNotEmpty) {
        final target = Directory('$fixtureRoot/cache-$size');
        if (target.existsSync()) {
          throw StateError(
            'Choose a new fixture output directory: ${target.path}',
          );
        }
        for (final video in source) {
          File(
              '${target.path}/${video.avid}/${video.cid}/entry.json',
            )
            ..createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(video.toJson()));
        }
      }
    });
  }

  test('splits collection navigation by folder while preserving parts', () {
    final collection = SeasonInfo(
      index: 0,
      id: 7,
      title: '合集',
      cover: '',
      mid: 10,
      uname: '作者',
    );
    final partOne = entry(11, ownerId: 10, season: collection);
    final partTwo = entry(11, ownerId: 10, season: collection, cid: 111);
    final next = entry(12, ownerId: 10, season: collection);
    final index = DownloadFolderIndex(
      [
        partOne,
        partTwo,
        next,
        entry(13, ownerId: 10),
      ],
      DownloadFolderLayout(
        names: {'manual:test': '手动'},
        destinations: {'video:11': 'manual:test'},
      ),
    );
    expect(index.collection('id:10', 7)!.pages.single.pageId, '12');
    expect(index.collection('manual:test', 7)!.pages.single.pageId, '11');
    expect(index.pageAt(partOne.pageDirPath)!.entries, [partOne, partTwo]);
    expect(index.folder('manual:test')!.group.videoCount, 1);
  });

  test(
    'index preserves part order and distinguishes collections from videos',
    () {
      final collection = SeasonInfo(
        index: 2,
        id: 7,
        title: '合集',
        cover: '',
        mid: 10,
        uname: '作者',
      );
      final first = entry(
        7,
        ownerId: 10,
        cover: 'first.jpg',
        season: collection,
      );
      final standalone = entry(7, ownerId: 10, cid: 107);
      final part = entry(
        7,
        ownerId: 10,
        cid: 207,
        cover: 'part.jpg',
        season: collection,
      );
      final next = entry(8, ownerId: 10, cover: 'next.jpg');
      final snapshot = DownloadListSnapshot.build([
        first,
        standalone,
        part,
        next,
      ]);
      expect(snapshot.seasons.map(downloadSelectionKey), [
        'season:7',
        'page:7',
        'page:8',
      ]);
      expect(snapshot.seasons.first.pages.single.entries, [first, part]);
      expect(snapshot.seasons.first.pages.single.cover, 'part.jpg');
      expect(snapshot.owners['id:10']!.cover, 'first.jpg');
      expect(
        DownloadListSnapshot.build([standalone, next]).owners['id:10']!.cover,
        standalone.cover,
      );
      expect(
        DownloadListSnapshot.build([next]).rootItems.single,
        isNot(isA<DownloadOwnerFolder>()),
      );
    },
  );

  test(
    'two videos, a multipart video and a collection become exactly one folder',
    () {
      final a = video(entry(1, ownerId: 10, cover: 'first.jpg'));
      final b = video(entry(2, ownerId: 10));
      final multipart = video(entry(3, ownerId: 10, bytes: 10));
      multipart.pages.first.entries.add(
        entry(3, cid: 303, ownerId: 10, bytes: 20),
      );
      final info = SeasonInfo(
        index: 0,
        id: 99,
        title: '合集',
        cover: '',
        mid: 10,
        uname: '作者',
      );
      final collection = video(entry(4, ownerId: 10, season: info));
      final last = entry(5, ownerId: 10, season: info);
      collection.pages.add(last.toDownloadPageInfo(last.pageId));
      final folder =
          buildDownloadRootItems([a, b, multipart, collection]).single
              as DownloadOwnerFolder;
      expect(folder.group.videoCount, 5);
      expect(folder.group.totalBytes, 34);
      expect(folder.group.cover, 'first.jpg');
      expect(folder.group.seasons, [
        same(a),
        same(b),
        same(multipart),
        same(collection),
      ]);
      expect(folder.group.seasons[2].pages.single.entries.length, 2);
      expect(folder.group.seasons[3].seasonInfo, same(info));
    },
  );

  test('root folds multiple videos but keeps single videos and unknown owners direct', () {
    final a = video(
      entry(1, ownerId: 10, ownerName: '作者', bytes: 100, cover: 'first.jpg'),
    );
    a.pages.first.entries.add(entry(1, cid: 101, ownerId: 10, bytes: 200));
    final b = video(entry(2, ownerId: 10, ownerName: '作者', bytes: 300));
    final single = video(entry(3, ownerId: 20, ownerName: '另一个作者'));
    final unknownA = video(entry(4));
    final unknownB = video(entry(5));
    final items = buildDownloadRootItems([a, single, b, unknownA, unknownB]);
    expect(items.length, 4);
    final folder = items.first as DownloadOwnerFolder;
    expect(folder.group.cover, 'first.jpg');
    expect(folder.group.videoCount, 2);
    expect(folder.group.totalBytes, 600);
    expect(folder.group.seasons, [same(a), same(b)]);
    expect(folder.pages.first.entries.length, 2);
    expect(items.skip(1), [same(single), same(unknownA), same(unknownB)]);
    expect(buildDownloadRootItems([a]).single, same(a));
    expect(
      buildDownloadRootItems([b]).single.pages.first.entries.first.title,
      b.pages.first.title,
    );
    expect(buildDownloadRootItems([]), isEmpty);
  });

  test(
    'folders keep collections intact and deduplicate bytes by cached cid',
    () {
      final info = SeasonInfo(
        index: 0,
        id: 99,
        title: '合集',
        cover: 'collection.jpg',
        mid: 10,
        uname: '作者',
      );
      final collection = video(
        entry(1, ownerId: 10, season: info, bytes: 100, cover: 'video.jpg'),
      );
      final next = entry(2, ownerId: 10, season: info, bytes: 200);
      collection.pages.add(next.toDownloadPageInfo(next.pageId));
      collection.pages.last.entries.add(next);
      final other = video(entry(3, ownerId: 10, bytes: 300));
      final folder =
          buildDownloadRootItems([collection, other]).single
              as DownloadOwnerFolder;
      expect(folder.group.videoCount, 3);
      expect(folder.group.totalBytes, 600);
      expect(folder.group.cover, 'video.jpg');
      expect(folder.group.seasons.first.seasonInfo, same(info));
      expect(folder.group.seasons.first.pages.length, 2);
      expect(buildDownloadRootItems([other]).single, same(other));
    },
  );

  test('keeps season and part structure while counting videos', () {
    expect(groupDownloadsByOwner([]), isEmpty);
    final first = entry(1, ownerId: 10, ownerName: '作者');
    final season = video(first);
    season.pages.first.entries.add(
      entry(1, cid: 101, ownerId: 10, ownerName: '作者'),
    );
    final second = entry(2, ownerId: 10, ownerName: '作者');
    season.pages.add(second.toDownloadPageInfo(second.pageId));
    final group = groupDownloadsByOwner([season]).single;
    expect(group.videoCount, 2);
    expect(group.seasons.single, same(season));
    expect(group.seasons.single.pages.first.entries.length, 2);
  });

  test('groups by identity across names and preserves selectable objects', () {
    final a = video(entry(1, ownerId: 10, ownerName: '作者'))..checked = true;
    final b = video(entry(2, ownerId: 20, ownerName: '作者'));
    final c = video(entry(3, ownerId: 10, ownerName: '作者改名'));
    final groups = groupDownloadsByOwner([a, b, c]);
    expect(groups.map((g) => g.videoCount), [2, 1]);
    expect(groups.first.seasons, [same(a), same(c)]);
    expect(groups.first.seasons.first.checked, isTrue);
  });

  test('falls back to season metadata, names and missing-author group', () {
    final season = SeasonInfo(
      index: 0,
      id: 1,
      title: '合集',
      cover: '',
      mid: 10,
      uname: '合集作者',
    );
    final groups = groupDownloadsByOwner([
      video(entry(1, season: season)),
      video(entry(2, ownerId: 10, ownerName: '合集作者')),
      video(entry(3, ownerName: '独立作者')),
      video(entry(4, ownerName: ' 独立作者 ')),
      video(entry(5)),
    ]);
    expect(groups.map((g) => g.name), ['合集作者', '独立作者', '作者信息缺失']);
    expect(groups.map((g) => g.videoCount), [2, 2, 1]);
  });

  test(
    'search matches partial author, title, part and season author offline',
    () {
      final e = entry(1, ownerName: '技术UP主Alice');
      expect(e.matchesDownloadSearch('  alice  '), isTrue);
      expect(e.matchesDownloadSearch('UP主'), isTrue);
      expect(e.matchesDownloadSearch('flutter'), isTrue);
      expect(e.matchesDownloadSearch('第一'), isTrue);
      expect(e.matchesDownloadSearch('无关作者'), isFalse);
      expect(entry(2).matchesDownloadSearch('作者'), isFalse);
      e.seasonInfo = SeasonInfo(
        index: 0,
        id: 1,
        title: '',
        cover: '',
        mid: 10,
        uname: '合集作者',
      );
      expect(e.matchesDownloadSearch('集作'), isTrue);
    },
  );
}
