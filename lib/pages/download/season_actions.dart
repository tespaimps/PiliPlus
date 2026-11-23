import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/pages/download/detail/widgets/item.dart';
import 'package:PiliPlus/pages/download/download/widgets/page.dart';
import 'package:PiliPlus/pages/download/download/widgets/season.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

mixin DownloadSeasonActions<T extends StatefulWidget>
    on State<T>, BaseDownloadActionMixin<T, DownloadSeasonInfo> {
  Iterable<BiliDownloadEntryInfo> _entries(
    Iterable<DownloadSeasonInfo> seasons,
  ) => {
    for (final season in seasons)
      for (final page in season.pages)
        for (final entry in page.entries) entry.cid: entry,
  }.values;

  @override
  Future<bool> onUpdate(
    Future<bool> Function(BiliDownloadEntryInfo) toElement,
  ) => _updateEntries(
    _entries(multiSelectCtr.allChecked),
    toElement,
    resetSelection: true,
  );

  Future<bool> _updateEntries(
    Iterable<BiliDownloadEntryInfo> entries,
    Future<bool> Function(BiliDownloadEntryInfo) action, {
    bool resetSelection = false,
  }) async {
    final snapshot = entries.toList();
    if (checkUpdateCount(snapshot.length)) return false;
    var dismissed = false;
    SmartDialog.showLoading(
      onDismiss: () {
        dismissed = true;
        if (resetSelection) multiSelectCtr.handleSelect();
      },
    );
    var success = true;
    for (final chunk in snapshot.mapChunked(kUpdateConcurrency, action)) {
      final results = await Future.wait(chunk);
      if (results.any((result) => !result)) success = false;
      if (dismissed) break;
    }
    toastUpdateResult(dismissed, success);
    return success;
  }

  Future<bool> updateSeason(
    DownloadSeasonInfo season,
    Future<bool> Function(BiliDownloadEntryInfo) action,
  ) => _updateEntries(_entries([season]), action);

  Future<void> updateSeasonDm(DownloadSeasonInfo season) async {
    await updateSeason(
      season,
      (e) => downloadService.downloadDanmaku(entry: e, isUpdate: true),
    );
  }

  Future<void> updateSeasonSeg(DownloadSeasonInfo season) async {
    await updateSeason(season, downloadService.updateSegments);
  }

  Future<void> updateSeasonVolume(DownloadSeasonInfo season) async {
    await updateSeason(season, downloadService.updateVolume);
  }

  Future<void> updateSeasonPlayInfo(DownloadSeasonInfo season) async {
    await updateSeason(season, downloadService.updatePlayInfo);
  }

  Future<void> updateSeasonSeasonInfo(DownloadSeasonInfo season) async {
    downloadService.refreshIfUpdated(
      await updateSeason(season, downloadService.updateSeasonInfo),
    );
  }

  Widget buildSeasonItem(
    DownloadSeasonInfo season,
    ChangeNotifier progress, {
    String? contextLabel,
    bool searchResult = false,
  }) {
    final pages = season.pages;
    final seasonInfo = season.seasonInfo;
    if (seasonInfo != null && pages.length > 1) {
      return SeasonInfoItem(
        controller: multiSelectCtr,
        downloadService: downloadService,
        seasonInfo: seasonInfo,
        season: season,
        enableMultiSelect: multiSelectCtr.enableMultiSelect.value,
        progress: progress,
        updateSeasonDm: updateSeasonDm,
        updateSeasonSeg: updateSeasonSeg,
        updateSeasonVolume: updateSeasonVolume,
        updateSeasonPlayInfo: updateSeasonPlayInfo,
        updateSeasonSeasonInfo: updateSeasonSeasonInfo,
      );
    }
    final page = pages.first;
    if (pages.length == 1 && page.entries.length == 1) {
      final entry = page.entries.first;
      return DetailItem(
        entry: entry,
        progress: progress,
        downloadService: downloadService,
        showTitle: true,
        onDelete: () {
          downloadService.deleteDownload(entry: entry, removeList: true);
          GStorage.watchProgress.delete(entry.cid.toString());
        },
        checked: season.checked,
        onSelect: (_) => multiSelectCtr.onSelect(season),
        controller: multiSelectCtr,
        contextLabel: contextLabel,
      );
    }
    return PageInfoItem(
      controller: multiSelectCtr,
      downloadService: downloadService,
      seasonInfo: season,
      pageInfo: page,
      enableMultiSelect: multiSelectCtr.enableMultiSelect.value,
      progress: progress,
      updatePageDm: updatePageDm,
      updatePageSeg: updatePageSeg,
      updatePageVolume: updatePageVolume,
      updatePagePlayInfo: updatePagePlayInfo,
      updatePageSeasonInfo: updatePageSeasonInfo,
      contextLabel: contextLabel,
      searchVideoKey: searchResult ? downloadVideoKey(page) : null,
    );
  }
}
