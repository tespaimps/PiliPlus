import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:flutter_test/flutter_test.dart';

BiliDownloadEntryInfo entry(
  int aid, {
  int? ownerId,
  String? ownerName,
  SeasonInfo? season,
  int? cid,
  int bytes = 1,
  String cover = '',
}) => BiliDownloadEntryInfo(
  isCompleted: true,
  totalBytes: bytes,
  downloadedBytes: 1,
  title: 'Flutter教程 $aid',
  cover: cover,
  preferedVideoQuality: 80,
  guessedTotalBytes: 1,
  totalTimeMilli: 1000,
  danmakuCount: 0,
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
)..pageDirPath = '/cache/$aid';

DownloadSeasonInfo video(BiliDownloadEntryInfo e) => DownloadSeasonInfo(
  seasonInfo: e.seasonInfo,
  pageId: e.pageId,
  pages: [e.toDownloadPageInfo(e.pageId)],
);

void main() {
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
