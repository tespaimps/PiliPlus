import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/models_new/download/download_sort.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/common/search/common_search_controller.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:get/get.dart';

class DownloadSearchController
    extends CommonSearchController<List<DownloadSeasonInfo>, DownloadSeasonInfo>
    with BaseMultiSelectMixin<DownloadSeasonInfo> {
  final _service = Get.find<DownloadService>();
  final _root = Get.find<DownloadController>();
  final _matchedParts = <String, String>{};
  String _query = '';
  Worker? _sortWorker;
  final _checkedFolders = 0.obs;
  int _folderCount = 0;
  DownloadFolderIndex? _matchIndex;
  String? _matchQuery;
  DownloadSort? _videoSort;
  List<DownloadSeasonInfo> _matches = const [];
  List<DownloadSeasonInfo> _sortedVideos = const [];
  DownloadListSnapshot? _resultSnapshot;
  String? _resultQuery;
  DownloadSort? _resultSort;

  @override
  List<DownloadSeasonInfo> get list => switch (loadingState.value) {
    Success(:final response) => response ?? const [],
    _ => const [],
  };
  @override
  Rx<LoadingState<List<DownloadSeasonInfo>?>> get state => loadingState;
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

  String? contextLabel(DownloadSeasonInfo item) {
    final key = downloadVideoKey(item.pages.first);
    final index = _service.folderIndex;
    final folders = index
        .locations(key)
        .map(index.folder)
        .nonNulls
        .map((folder) => folder.group.name)
        .toSet();
    final part = _matchedParts[key];
    final labels = [
      if (part != null) '命中 $part',
      if (folders.isNotEmpty) '所在文件夹 ${folders.join('、')}',
    ];
    return labels.isEmpty ? null : labels.join(' · ');
  }

  @override
  void onInit() {
    super.onInit();
    _service.flagNotifier.add(refreshResults);
    _sortWorker = ever(_root.sort, (_) => refreshResults());
  }

  @override
  void onClose() {
    _service.flagNotifier.remove(refreshResults);
    _sortWorker?.dispose();
    super.onClose();
  }

  @override
  void onClear() {
    _query = '';
    handleSelect();
    super.onClear();
  }

  @override
  Future<void> onRefresh() async {
    final query = editController.text.trim().toLowerCase();
    if (query.isEmpty) return;
    focusNode.unfocus();
    if (_query != query) {
      handleSelect();
      _query = query;
      if (scrollController.hasClients) scrollController.jumpTo(0);
    }
    await refreshResults();
  }

  @override
  Future<void> onReload() => onRefresh();

  @override
  Future<LoadingState<List<DownloadSeasonInfo>>> customGetData() async =>
      Success(_results());

  List<DownloadSeasonInfo> _results() {
    if (_query.isEmpty) return [];
    final index = _service.folderIndex;
    final sort = _root.sort.value;
    final folders = index.folders.where(
      (folder) => folder.group.searchName.contains(_query),
    );
    if (!identical(index, _matchIndex) || _query != _matchQuery) {
      _matchIndex = index;
      _matchQuery = _query;
      _videoSort = null;
      _matches = [];
      _matchedParts.clear();
      for (final entry in index.searchVideos.entries) {
        final video = entry.value;
        if (video.matches(_query)) {
          _matches.add(video.card);
          if (video.matchingPart(_query) case final part?) {
            _matchedParts[entry.key] = part;
          }
        }
      }
    }
    if (_videoSort != sort) {
      _videoSort = sort;
      _sortedVideos = sortDownloads(_matches, sort);
    }
    return [...sortDownloads(folders, sort), ..._sortedVideos];
  }

  Future<void> refreshResults() async {
    await _service.waitForInitialization;
    if (isClosed || _query.isEmpty) return;
    final snapshot = _service.downloadIndex;
    final sort = _root.sort.value;
    if (identical(snapshot, _resultSnapshot) &&
        _query == _resultQuery &&
        sort == _resultSort &&
        loadingState.value is Success) {
      return;
    }
    _resultSnapshot = snapshot;
    _resultQuery = _query;
    _resultSort = sort;
    final selected = allChecked.map(downloadCardSelectionKey).toSet();
    var count = 0;
    var folderCount = 0;
    var checkedFolders = 0;
    final results = _results().map((template) {
      final item = selectableDownloadSeason(template);
      final folder = item is DownloadOwnerFolder;
      if (folder) folderCount++;
      if (selected.contains(downloadCardSelectionKey(item))) {
        item.checked = true;
        count++;
        if (folder) checkedFolders++;
      }
      return item;
    }).toList();
    loadingState.value = Success(results);
    rxCount.value = count;
    _folderCount = folderCount;
    _checkedFolders.value = checkedFolders;
    if (count == 0) enableMultiSelect.value = false;
  }

  @override
  void onRemove() => removeCards(allChecked.toList());

  void removeCards(List<DownloadSeasonInfo> cards) {
    final count = _service.captureFolderSelection(cards).count;
    if (count == 0) return;
    _root.removeSeasons(
      cards,
      title: '确定删除所选内容中的 $count 个视频及其缓存分 P？',
      onRemoved: handleSelect,
    );
  }
}
