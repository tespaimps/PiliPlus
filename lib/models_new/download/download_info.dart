import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart'
    show MultiSelectData;

class DownloadPageInfo with MultiSelectData {
  final String pageId;
  final String dirPath;
  final String title;
  String cover;
  int sortKey;
  final int? seasonType;
  final List<BiliDownloadEntryInfo> entries;
  late final int totalBytes = {
    for (final entry in entries) entry.cid: entry.totalBytes,
  }.values.fold(0, (sum, bytes) => sum + bytes);

  DownloadPageInfo({
    required this.pageId,
    required this.dirPath,
    required this.title,
    required this.cover,
    required this.sortKey,
    this.seasonType,
    required this.entries,
  });
}

class DownloadSeasonInfo with MultiSelectData {
  SeasonInfo? seasonInfo;
  final String pageId;
  final List<DownloadPageInfo> pages;
  final String? folderKey;

  DownloadSeasonInfo({
    required this.seasonInfo,
    required this.pageId,
    required this.pages,
    this.folderKey,
  });
}

String downloadVideoKey(DownloadPageInfo page) =>
    downloadEntryKey(page.entries.first);

String downloadEntryKey(BiliDownloadEntryInfo entry) => entry.seasonId == null
    ? 'video:${entry.avid}'
    : 'pgc:${entry.seasonId}:${entry.ep?.seasonType ?? 0}';
