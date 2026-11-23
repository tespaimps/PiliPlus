import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';

class DownloadOwnerGroup {
  final String key;
  final String name;
  late final String searchName = name.toLowerCase();
  final List<DownloadSeasonInfo> seasons;
  final int videoCount;
  final int totalBytes;
  final int oldest;
  final int newest;
  final String cover;

  DownloadOwnerGroup._(
    this.name, {
    required this.key,
    required this.seasons,
    required this.videoCount,
    required this.totalBytes,
    required this.oldest,
    required this.newest,
    required this.cover,
  });

  DownloadOwnerGroup withName(String name) => DownloadOwnerGroup._(
    name,
    key: key,
    seasons: seasons,
    videoCount: videoCount,
    totalBytes: totalBytes,
    oldest: oldest,
    newest: newest,
    cover: cover,
  );

  Iterable<BiliDownloadEntryInfo> get entries sync* {
    final seen = <int>{};
    for (final season in seasons) {
      for (final page in season.pages) {
        for (final entry in page.entries) {
          if (seen.add(entry.cid)) yield entry;
        }
      }
    }
  }
}

/// A presentation-only folder; original seasons and on-disk paths stay intact.
class DownloadOwnerFolder extends DownloadSeasonInfo {
  final DownloadOwnerGroup group;

  DownloadOwnerFolder(this.group)
    : super(
        pageId: 'owner:${group.key}',
        seasonInfo: null,
        pages: List.unmodifiable(
          group.seasons.expand((season) => season.pages),
        ),
      );

  DownloadOwnerFolder._forSelection(DownloadOwnerFolder folder)
    : group = folder.group,
      super(pageId: folder.pageId, seasonInfo: null, pages: folder.pages);

  DownloadOwnerFolder.withName(DownloadOwnerFolder folder, String name)
    : group = folder.group.withName(name),
      super(pageId: folder.pageId, seasonInfo: null, pages: folder.pages);
}

List<DownloadSeasonInfo> _rootItems(Iterable<DownloadOwnerGroup> groups) => [
  for (final group in groups)
    if (!group.key.startsWith('unknown:') && group.videoCount > 1)
      DownloadOwnerFolder(group)
    else
      ...group.seasons,
];

List<DownloadSeasonInfo> buildDownloadRootItems(
  Iterable<DownloadSeasonInfo> seasons,
) => _rootItems(groupDownloadsByOwner(seasons));

DownloadSeasonInfo selectableDownloadSeason(DownloadSeasonInfo season) =>
    season is DownloadOwnerFolder
    ? DownloadOwnerFolder._forSelection(season)
    : DownloadSeasonInfo(
        pageId: season.pageId,
        seasonInfo: season.seasonInfo,
        pages: season.pages,
        folderKey: season.folderKey,
      );

String downloadSelectionKey(DownloadSeasonInfo season) =>
    season is DownloadOwnerFolder
    ? season.pageId
    : season.seasonInfo != null
    ? 'season:${season.seasonInfo!.id}'
    : season.pages.first.entries.first.seasonId == null
    ? 'page:${season.pageId}'
    : downloadVideoKey(season.pages.first);

String downloadCardSelectionKey(DownloadSeasonInfo season) =>
    '${season.folderKey ?? ""}/${downloadSelectionKey(season)}';

({String key, String name}) downloadOwnerIdentity(DownloadSeasonInfo season) {
  final entry = season.pages.first.entries.first;
  final ownerId = entry.ownerId;
  final seasonOwnerId = season.seasonInfo?.mid;
  final id = ownerId != null && ownerId > 0
      ? ownerId
      : seasonOwnerId != null && seasonOwnerId > 0
      ? seasonOwnerId
      : null;
  final ownerName = entry.ownerName?.trim();
  final seasonOwnerName = season.seasonInfo?.uname.trim();
  final name = ownerName != null && ownerName.isNotEmpty
      ? ownerName
      : seasonOwnerName != null && seasonOwnerName.isNotEmpty
      ? seasonOwnerName
      : id != null
      ? 'UP主 $id'
      : '作者信息缺失';
  final key = id != null
      ? 'id:$id'
      : name != '作者信息缺失'
      ? 'name:$name'
      : 'unknown:${downloadSelectionKey(season)}';
  return (key: key, name: name);
}

List<DownloadOwnerGroup> groupDownloadsByOwner(
  Iterable<DownloadSeasonInfo> seasons,
) {
  final groups = <String, ({String name, List<DownloadSeasonInfo> seasons})>{};
  for (final season in seasons) {
    final (:key, :name) = downloadOwnerIdentity(season);
    (groups[key] ??= (name: name, seasons: [])).seasons.add(season);
  }
  return [
    for (final MapEntry(:key, :value) in groups.entries)
      summarizeDownloadGroup(key, value.name, value.seasons),
  ];
}

DownloadOwnerGroup summarizeDownloadGroup(
  String key,
  String name,
  List<DownloadSeasonInfo> seasons,
) {
  final pageIds = <String>{};
  final cids = <int>{};
  var totalBytes = 0;
  var oldest = 0;
  var newest = 0;
  for (final season in seasons) {
    for (final page in season.pages) {
      pageIds.add(downloadVideoKey(page));
      for (final entry in page.entries) {
        if (cids.add(entry.cid)) totalBytes += entry.totalBytes;
        final date = entry.timeCreateStamp;
        if (date > 0 && (oldest == 0 || date < oldest)) oldest = date;
        if (date > newest) newest = date;
      }
    }
  }
  return DownloadOwnerGroup._(
    name,
    key: key,
    seasons: List.unmodifiable(seasons),
    videoCount: pageIds.length,
    totalBytes: totalBytes,
    oldest: oldest,
    newest: newest,
    cover: seasons.first.pages.first.entries.first.cover,
  );
}

class DownloadListSnapshot {
  final List<DownloadSeasonInfo> seasons;
  final List<DownloadSeasonInfo> rootItems;
  final Map<String, DownloadOwnerGroup> owners;

  DownloadListSnapshot(this.seasons, this.rootItems, this.owners);

  factory DownloadListSnapshot.build(Iterable<BiliDownloadEntryInfo> entries) {
    final seasons = buildDownloadSeasons(entries);
    final owners = groupDownloadsByOwner(seasons);
    return DownloadListSnapshot(
      seasons,
      List.unmodifiable(_rootItems(owners)),
      Map.unmodifiable({for (final owner in owners) owner.key: owner}),
    );
  }
}

List<DownloadSeasonInfo> buildDownloadSeasons(
  Iterable<BiliDownloadEntryInfo> entries,
) {
  // The outer map and each page map preserve first appearance in the source.
  final groups =
      <(int?, String?), (SeasonInfo?, Map<String, DownloadPageInfo>)>{};
  for (final entry in entries) {
    final season = entry.seasonInfo;
    final pageId = entry.pageId;
    final kind = entry.seasonId == null
        ? 'video'
        : 'pgc:${entry.ep?.seasonType ?? 0}';
    final key = season == null ? (null, '$kind:$pageId') : (season.id, null);
    final (_, pages) = groups.putIfAbsent(key, () => (season, {}));
    final page = pages[pageId];
    if (page == null) {
      pages[pageId] = entry.toDownloadPageInfo(
        pageId,
        sortKey: season?.index,
      );
    } else {
      if (entry.sortKey < page.sortKey) {
        page
          ..cover = entry.cover
          ..sortKey = entry.sortKey;
      }
      page.entries.add(entry);
    }
  }
  return List.unmodifiable([
    for (final (season, pages) in groups.values)
      DownloadSeasonInfo(
        pageId: pages.keys.first,
        seasonInfo: season,
        pages: List.unmodifiable(pages.values),
      ),
  ]);
}
