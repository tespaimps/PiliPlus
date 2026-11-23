import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/models_new/download/download_sort.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart'
    show BaseMultiSelectMixin;
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' show Text;

class DownloadController extends GetxController
    with BaseMultiSelectMixin<DownloadSeasonInfo> {
  final _downloadService = Get.find<DownloadService>();
  DownloadListSnapshot? _snapshot;
  final sort = decodeDownloadSort(
    GStorage.setting.get(SettingBoxKey.downloadSort),
  ).obs;
  DownloadListSnapshot? _targetSnapshot;
  DownloadSort? _targetSort;
  List<DownloadOwnerFolder> _sortedFolders = const [];

  Future<void> setSort(DownloadSort value) async {
    await GStorage.setting.put(SettingBoxKey.downloadSort, [
      value.field.name,
      value.ascending,
    ]);
    sort.value = value;
    items.value = sortDownloads(items, value);
  }

  List<DownloadSeasonInfo> get seasons => _snapshot?.seasons ?? const [];
  List<DownloadSeasonInfo> ownerSeasons(String ownerKey) =>
      _snapshot?.owners[ownerKey]?.seasons ?? const [];
  String? liveFolderName(String key) =>
      flag.value == 0 ? null : _snapshot?.owners[key]?.name;
  final _checkedFolders = 0.obs;
  int _folderCount = 0;
  bool get canMove => checkedCount > 0 && _checkedFolders.value == 0;

  @override
  void onSelect(DownloadSeasonInfo item) {
    if (item is DownloadOwnerFolder) {
      _checkedFolders.value += item.checked ? -1 : 1;
    }
    super.onSelect(item);
  }

  @override
  void handleSelect({bool checked = false, bool disableSelect = true}) {
    _checkedFolders.value = checked ? _folderCount : 0;
    super.handleSelect(checked: checked, disableSelect: disableSelect);
  }

  List<DownloadOwnerFolder> moveTargets(
    DownloadFolderSelection selection,
    String query,
  ) {
    // Subscribe the picker to successful changes in membership and names.
    if (flag.value == 0) return const [];
    final current = sort.value;
    if (!identical(_targetSnapshot, _snapshot) || current != _targetSort) {
      _targetSnapshot = _snapshot;
      _targetSort = current;
      _sortedFolders = sortDownloads(
        _downloadService.folderIndex.folders,
        current,
      );
    }
    return _sortedFolders
        .where(
          (folder) =>
              !selection.sources.contains(folder.group.key) &&
              folder.group.searchName.contains(query),
        )
        .toList();
  }

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
    Timeline.timeSync('Offline cache: load root list', () {
      final snapshot = _downloadService.downloadIndex;
      if (identical(snapshot, _snapshot)) return;
      final selected = allChecked.map(downloadCardSelectionKey).toSet();
      _snapshot = snapshot;
      var count = 0;
      var checkedFolders = 0;
      var folders = 0;
      items.value = sortDownloads(snapshot.rootItems, sort.value).map((season) {
        final item = selectableDownloadSeason(season);
        final isFolder = item is DownloadOwnerFolder;
        if (isFolder) folders++;
        if (selected.contains(downloadCardSelectionKey(item))) {
          item.checked = true;
          count++;
          if (isFolder) checkedFolders++;
        }
        return item;
      }).toList();
      rxCount.value = count;
      _folderCount = folders;
      _checkedFolders.value = checkedFolders;
      if (count == 0) enableMultiSelect.value = false;
      flag.value++;
    });
  }

  @override
  void onRemove() => removeSeasons(allChecked.toList());

  void removeSeasons(
    List<DownloadSeasonInfo> selected, {
    void Function()? onRemoved,
    String title = '确定删除选中视频？',
  }) {
    showConfirmDialog(
      context: Get.context!,
      title: Text(title),
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
        _downloadService.notifyDownloadListChanged();
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
