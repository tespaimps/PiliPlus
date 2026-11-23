import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/download/detail/widgets/item.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download/widgets/folder_dialogs.dart';
import 'package:PiliPlus/pages/download/download/widgets/move_destination.dart';
import 'package:PiliPlus/pages/download/download/widgets/owner.dart';
import 'package:PiliPlus/pages/download/owner/view.dart';
import 'package:PiliPlus/pages/download/season_actions.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/pages/download/download_grid.dart';
import 'package:PiliPlus/pages/download/download_sort_dialog.dart';
import 'package:PiliPlus/pages/download/search/view.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage>
    with
        BaseDownloadActionMixin<DownloadPage, DownloadSeasonInfo>,
        DownloadSeasonActions<DownloadPage> {
  final _progress = ChangeNotifier();
  final _controller = Get.put(DownloadController());
  final _scroll = ScrollController(keepScrollOffset: false);
  final _grid = GlobalKey<DownloadGridState>();
  DownloadFolderSelection? _moving;
  DownloadScrollAnchor? _moveAnchor;
  bool _savingFolder = false;

  @override
  final downloadService = Get.find<DownloadService>();

  @override
  BaseMultiSelectMixin<DownloadSeasonInfo> get multiSelectCtr => _controller;

  @override
  void dispose() {
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<bool> _saveFolder(Future<void> Function() save) async {
    if (_savingFolder) return false;
    setState(() => _savingFolder = true);
    try {
      await save();
      return true;
    } on DownloadFolderException catch (error) {
      SmartDialog.showToast(error.message);
      return false;
    } catch (_) {
      SmartDialog.showToast('保存文件夹归类失败，请重试');
      return false;
    } finally {
      if (mounted) setState(() => _savingFolder = false);
    }
  }

  Future<void> _merge() async {
    if (_controller.checkedCount < 2 || _savingFolder) return;
    final selection = downloadService.captureFolderSelection(
      _controller.allChecked,
    );
    if (selection.count < 2) return;
    final name = await askDownloadFolderName(context);
    if (!mounted || name == null) return;
    if (await _saveFolder(
          () => downloadService.mergeFolders(selection, name),
        ) &&
        mounted) {
      _controller.handleSelect();
    }
  }

  Future<void> _rename(DownloadOwnerFolder folder) async {
    if (_savingFolder) return;
    final scope = downloadService.folderStorageKey;
    final name = await askDownloadFolderName(
      context,
      current: folder.group.name,
    );
    if (!mounted || name == null || name == folder.group.name) return;
    await _saveFolder(
      () => downloadService.renameFolder(scope, folder.group.key, name),
    );
  }

  void _beginMove(DownloadFolderSelection selection) {
    if (selection.count == 0) return;
    if (_controller.moveTargets(selection, '').isEmpty) {
      SmartDialog.showToast('没有可移动到的其他文件夹');
      return;
    }
    _moveAnchor = DownloadScrollAnchor.capture(_scroll, [_grid]);
    setState(() => _moving = selection);
  }

  void _finishMove(bool moved) {
    if (moved) _controller.handleSelect();
    setState(() => _moving = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _moveAnchor?.restore(_scroll, [_grid]);
      _moveAnchor = null;
    });
  }

  Future<void> _sort() async {
    final value = await chooseDownloadSort(context, _controller.sort.value);
    if (value == null || !mounted) return;
    try {
      await _controller.setSort(value);
    } catch (_) {
      SmartDialog.showToast('保存排序失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_moving case final selection?) {
      return DownloadMoveDestination(
        selection: selection,
        onClose: _finishMove,
      );
    }
    final padding = MediaQuery.viewPaddingOf(context);
    return Obx(() {
      final enableMultiSelect = _controller.enableMultiSelect.value;
      return popScope(
        canPop: !enableMultiSelect,
        onPopInvokedWithResult: (didPop, result) {
          if (enableMultiSelect) {
            _controller.handleSelect();
          }
        },
        child: SimpleScaffold(
          appBar: MultiSelectAppBarWidget(
            ctr: _controller,
            actionsBelow: MediaQuery.sizeOf(context).width < 480,
            actions: [
              Obx(
                () => TextButton(
                  onPressed: _controller.checkedCount >= 2 && !_savingFolder
                      ? _merge
                      : null,
                  child: const Text('合并'),
                ),
              ),
              Obx(
                () => TextButton(
                  onPressed: _controller.canMove && !_savingFolder
                      ? () => _beginMove(
                          downloadService.captureFolderSelection(
                            _controller.allChecked,
                          ),
                        )
                      : null,
                  child: const Text('移动'),
                ),
              ),
              updateBtn(),
            ],
            child: AppBar(
              title: const Text('离线缓存'),
              actions: [
                IconButton(
                  tooltip: '排序',
                  onPressed: _sort,
                  icon: const Icon(Icons.sort),
                ),
                IconButton(
                  tooltip: '搜索',
                  onPressed: () async {
                    await downloadService.waitForInitialization;
                    if (!mounted) return;
                    Get.to(DownloadSearchPage(progress: _progress));
                  },
                  icon: const Icon(Icons.search),
                ),
                IconButton(
                  tooltip: '多选',
                  onPressed: () {
                    if (enableMultiSelect) {
                      _controller.handleSelect();
                    } else {
                      _controller.enableMultiSelect.value = true;
                    }
                  },
                  icon: const Icon(Icons.edit_note),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          body: Padding(
            padding: EdgeInsets.only(left: padding.left, right: padding.right),
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                Obx(() {
                  final entry =
                      downloadService.waitDownloadQueue.firstWhereOrNull(
                        (e) => e.cid == downloadService.curCid,
                      ) ??
                      downloadService.waitDownloadQueue.firstOrNull;
                  if (entry != null) {
                    return SliverMainAxisGroup(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.only(left: 12, bottom: 7),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              '正在缓存 (${downloadService.waitDownloadQueue.length})',
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 110,
                            child: DetailItem(
                              entry: entry,
                              progress: _progress,
                              downloadService: downloadService,
                              showTitle: true,
                              isCurr: true,
                              controller: _controller,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return const SliverToBoxAdapter();
                }),
                Obx(() {
                  if (_controller.items.isNotEmpty) {
                    return SliverMainAxisGroup(
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.only(
                            left: 12,
                            bottom: 7,
                            top: downloadService.waitDownloadQueue.isEmpty
                                ? 0
                                : 7,
                          ),
                          sliver: const SliverToBoxAdapter(
                            child: Text('已缓存视频'),
                          ),
                        ),
                        DownloadGrid(
                          key: _grid,
                          idAt: (index) => downloadCardSelectionKey(
                            _controller.items[index],
                          ),
                          itemCount: _controller.items.length,
                          itemBuilder: (context, index) {
                            final item = _controller.items[index];
                            if (item is DownloadOwnerFolder) {
                              return DownloadOwnerItem(
                                key: ValueKey(item.pageId),
                                folder: item,
                                enableMultiSelect: enableMultiSelect,
                                onTap: () {
                                  if (enableMultiSelect) {
                                    _controller.onSelect(item);
                                  } else {
                                    Get.to(
                                      DownloadOwnerPage(
                                        ownerKey: item.group.key,
                                        ownerName: item.group.name,
                                        progress: _progress,
                                      ),
                                    );
                                  }
                                },
                                onDelete: () =>
                                    _controller.removeSeasons([item]),
                                updateActions: {
                                  '重命名': () => _rename(item),
                                  '更新弹幕': () => updateSeasonDm(item),
                                  '更新片段': () => updateSeasonSeg(item),
                                  '更新合集信息': () => updateSeasonSeasonInfo(item),
                                  '更新音量均衡': () => updateSeasonVolume(item),
                                  '更新字幕、分段信息': () => updateSeasonPlayInfo(item),
                                },
                              );
                            }
                            return buildSeasonItem(item, _progress);
                          },
                        ),
                      ],
                    );
                  }
                  if (downloadService.waitDownloadQueue.isNotEmpty) {
                    return const SliverToBoxAdapter();
                  }
                  return const HttpError();
                }),
                SliverToBoxAdapter(
                  child: SizedBox(height: padding.bottom + 100),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
