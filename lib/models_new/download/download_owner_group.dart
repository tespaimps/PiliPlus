import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';

class DownloadOwnerGroup {
  final String key;
  final String name;
  final List<DownloadSeasonInfo> seasons = [];

  DownloadOwnerGroup(this.name, {required this.key});

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

  int get videoCount =>
      seasons.expand((s) => s.pages).map((p) => p.pageId).toSet().length;
  int get totalBytes => entries.fold(0, (sum, entry) => sum + entry.totalBytes);
  String get cover => entries.first.cover;
}

/// A presentation-only folder; original seasons and on-disk paths stay intact.
class DownloadOwnerFolder extends DownloadSeasonInfo {
  final DownloadOwnerGroup group;

  DownloadOwnerFolder(this.group)
    : super(
        pageId: 'owner:${group.key}',
        seasonInfo: null,
        pages: group.seasons.expand((season) => season.pages).toList(),
      );
}

List<DownloadSeasonInfo> buildDownloadRootItems(
  Iterable<DownloadSeasonInfo> seasons,
) => [
  for (final group in groupDownloadsByOwner(seasons))
    if (!group.key.startsWith('unknown:') && group.videoCount > 1)
      DownloadOwnerFolder(group)
    else
      ...group.seasons,
];

String downloadSelectionKey(DownloadSeasonInfo season) =>
    season is DownloadOwnerFolder
    ? season.pageId
    : season.seasonInfo != null
    ? 'season:${season.seasonInfo!.id}'
    : 'page:${season.pageId}';

/// Keep the existing season/page objects so selection and batch actions stay shared.
List<DownloadOwnerGroup> groupDownloadsByOwner(
  Iterable<DownloadSeasonInfo> seasons,
) {
  final groups = <String, DownloadOwnerGroup>{};
  for (final season in seasons) {
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
    (groups[key] ??= DownloadOwnerGroup(name, key: key)).seasons.add(season);
  }
  return groups.values.toList();
}
