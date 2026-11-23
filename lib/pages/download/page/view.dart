import 'dart:async';

import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/download/detail/widgets/item.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download/widgets/page.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/pages/download/download_grid.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;

class DownloadPagePage extends StatefulWidget {
  const DownloadPagePage({
    super.key,
    required this.seasonInfo,
    required this.folderKey,
    required this.progress,
  });

  final SeasonInfo seasonInfo;
  final String? folderKey;
  final ChangeNotifier progress;

  @override
  State<DownloadPagePage> createState() => _DownloadPagePageState();
}

class _DownloadPagePageState extends State<DownloadPagePage>
    with
        BaseMultiSelectMixin<DownloadPageInfo>,
        BaseDownloadActionMixin<DownloadPagePage, DownloadPageInfo> {
  StreamSubscription? _sub;
  final _pages = RxList<DownloadPageInfo>();
  final _controller = Get.find<DownloadController>();

  @override
  RxList<DownloadPageInfo> get list => _pages;
  @override
  RxList<DownloadPageInfo> get state => _pages;

  @override
  final downloadService = Get.find<DownloadService>();

  @override
  BaseMultiSelectMixin<DownloadPageInfo> get multiSelectCtr => this;

  @override
  void initState() {
    super.initState();
    _loadList();
    _sub = _controller.flag.listen((_) {
      _loadList();
    });
  }

  Future<void> _closeSub() async {
    if (_sub != null) {
      await _sub?.cancel();
      _sub = null;
    }
  }

  @override
  void dispose() {
    _closeSub();
    super.dispose();
  }

  static int _sort(DownloadPageInfo a, DownloadPageInfo b) {
    if (a.sortKey == b.sortKey) {
      return b.entries.first.avid.compareTo(a.entries.first.avid);
    }
    return a.sortKey.compareTo(b.sortKey);
  }

  void _loadList() {
    final list =
        downloadService.folderIndex
            .collection(widget.folderKey, widget.seasonInfo.id)
            ?.pages
            .map(
              (page) => DownloadPageInfo(
                pageId: page.pageId,
                dirPath: page.dirPath,
                title: page.title,
                cover: page.cover,
                sortKey: page.sortKey,
                seasonType: page.seasonType,
                entries: page.entries,
              ),
            )
            .toList()
          ?..sort(_sort);
    if (list != null) {
      _pages.value = list;
    } else {
      _pages.clear();
    }
  }

  @override
  Future<bool> onUpdate(
    Future<bool> Function(BiliDownloadEntryInfo e) toElement,
  ) async {
    if (checkUpdateCount(checkedCount)) return false;

    bool dismiss = false;
    SmartDialog.showLoading(
      onDismiss: () {
        dismiss = true;
        handleSelect();
      },
    );

    bool isSuccess = true;
    for (final chunk in allChecked.mapChunked(
      kUpdateConcurrency,
      (page) async {
        bool isSuccess = true;
        for (final chunk in page.entries.mapChunked(
          kUpdateConcurrency,
          toElement,
        )) {
          final res = await Future.wait(chunk);
          if (res.any((e) => !e)) isSuccess = false;
          if (dismiss) break;
        }
        return isSuccess;
      },
    )) {
      final res = await Future.wait(chunk);
      if (res.any((e) => !e)) isSuccess = false;
      if (dismiss) break;
    }

    toastUpdateResult(dismiss, isSuccess);

    return isSuccess;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final enableMultiSelect = this.enableMultiSelect.value;
      return popScope(
        canPop: !enableMultiSelect,
        onPopInvokedWithResult: (didPop, result) {
          if (enableMultiSelect) {
            handleSelect();
          }
        },
        child: SimpleScaffold(
          appBar: MultiSelectAppBarWidget(
            ctr: this,
            actions: [updateBtn()],
            child: AppBar(
              title: Text(widget.seasonInfo.title),
              actions: [
                IconButton(
                  tooltip: '多选',
                  onPressed: () {
                    if (enableMultiSelect) {
                      handleSelect();
                    } else {
                      this.enableMultiSelect.value = true;
                    }
                  },
                  icon: const Icon(Icons.edit_note),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          body: CustomScrollView(
            slivers: [
              ViewSliverSafeArea(
                sliver: Obx(() {
                  if (_pages.isNotEmpty) {
                    return DownloadGrid(
                      itemBuilder: (context, index) {
                        final page = list[index];
                        if (page.entries.length == 1) {
                          final entry = page.entries.first;
                          return DetailItem(
                            entry: entry,
                            progress: widget.progress,
                            downloadService: downloadService,
                            showTitle: true,
                            onDelete: () {
                              downloadService.deleteDownload(
                                entry: entry,
                                removeList: true,
                              );
                              GStorage.watchProgress.delete(
                                entry.cid.toString(),
                              );
                            },
                            checked: page.checked,
                            onSelect: (_) => onSelect(page),
                            controller: this,
                          );
                        }
                        return PageInfoItem(
                          controller: this,
                          downloadService: downloadService,
                          seasonInfo: page,
                          pageInfo: page,
                          enableMultiSelect: enableMultiSelect,
                          progress: widget.progress,
                          updatePageDm: updatePageDm,
                          updatePageSeg: updatePageSeg,
                          updatePageVolume: updatePageVolume,
                          updatePagePlayInfo: updatePagePlayInfo,
                          updatePageSeasonInfo: updatePageSeasonInfo,
                        );
                      },
                      itemCount: _pages.length,
                    );
                  }
                  return const HttpError();
                }),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void onRemove() {
    showConfirmDialog(
      context: context,
      title: const Text('确定删除选中视频？'),
      onConfirm: () async {
        SmartDialog.showLoading();
        final watchProgress = GStorage.watchProgress;
        for (final page in allChecked) {
          await watchProgress.deleteAll(
            page.entries.map((e) => e.cid.toString()),
          );
          await downloadService.deletePage(
            pageDirPath: page.dirPath,
            refresh: false,
          );
        }
        downloadService.notifyDownloadListChanged();
        if (enableMultiSelect.value) {
          rxCount.value = 0;
          enableMultiSelect.value = false;
        }
        SmartDialog.dismiss();
      },
    );
  }
}
