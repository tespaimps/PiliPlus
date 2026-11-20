import 'dart:async';

import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart'
    show BaseMultiSelectMixin;
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' show Text;

class DownloadController extends GetxController
    with BaseMultiSelectMixin<DownloadSeasonInfo> {
  final _downloadService = Get.find<DownloadService>();
  final seasons = RxList<DownloadSeasonInfo>();
  final items = RxList<DownloadSeasonInfo>();
  final flag = RxInt(0);

  @override
  List<DownloadSeasonInfo> get list => items;
  @override
  RxList<DownloadSeasonInfo> get state => items;

  @override
  void onInit() {
    super.onInit();
    _loadList();
    _downloadService.flagNotifier.add(_loadList);
  }

  @override
  void onClose() {
    _downloadService.flagNotifier.remove(_loadList);
    super.onClose();
  }

  Future<void> _loadList() async {
    await _downloadService.waitForInitialization;
    if (isClosed) return;
    if (_downloadService.downloadList.isEmpty) {
      seasons.clear();
      items.clear();
      rxCount.value = 0;
      enableMultiSelect.value = false;
      flag.value++;
      return;
    }
    final list = <DownloadSeasonInfo>[];
    for (final entry in _downloadService.downloadList) {
      final pageId = entry.pageId;
      final seasonInfo = entry.seasonInfo;
      final season = seasonInfo != null
          ? list.firstWhereOrNull((e) => e.seasonInfo == seasonInfo)
          : list.firstWhereOrNull((e) => e.pageId == pageId);
      if (season != null) {
        final page = season.pages.firstWhereOrNull((e) => e.pageId == pageId);
        if (page != null) {
          final aSortKey = entry.sortKey;
          final bSortKey = page.sortKey;
          if (aSortKey < bSortKey) {
            page
              ..cover = entry.cover
              ..sortKey = aSortKey;
          }
          page.entries.add(entry);
        } else {
          season.pages.add(
            entry.toDownloadPageInfo(pageId, sortKey: seasonInfo!.index),
          );
        }
      } else {
        list.add(
          DownloadSeasonInfo(
            pageId: pageId,
            seasonInfo: seasonInfo,
            pages: [
              entry.toDownloadPageInfo(pageId, sortKey: seasonInfo?.index),
            ],
          ),
        );
      }
    }
    final selected = allChecked.map(downloadSelectionKey).toSet();
    seasons.value = list;
    items.value = buildDownloadRootItems(list)
      ..forEach(
        (item) => item.checked = selected.contains(downloadSelectionKey(item)),
      );
    rxCount.value = allChecked.length;
    if (rxCount.value == 0) enableMultiSelect.value = false;
    flag.value++;
  }

  @override
  void onRemove() => removeSeasons(allChecked.toList());

  void removeSeasons(
    List<DownloadSeasonInfo> selected, {
    void Function()? onRemoved,
  }) {
    showConfirmDialog(
      context: Get.context!,
      title: const Text('确定删除选中视频？'),
      onConfirm: () async {
        SmartDialog.showLoading();
        final watchProgress = GStorage.watchProgress;
        final deletedPaths = <String>{};
        for (final season in selected) {
          for (final page in season.pages) {
            await watchProgress.deleteAll(
              page.entries.map((e) => e.cid.toString()),
            );
            if (!deletedPaths.add(page.dirPath)) continue;
            await _downloadService.deletePage(
              pageDirPath: page.dirPath,
              refresh: false,
            );
          }
        }
        _downloadService.flagNotifier.refresh();
        if (enableMultiSelect.value) {
          rxCount.value = 0;
          enableMultiSelect.value = false;
        }
        SmartDialog.dismiss();
        onRemoved?.call();
      },
    );
  }
}
