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
import 'package:PiliPlus/pages/download/download/widgets/owner.dart';
import 'package:PiliPlus/pages/download/owner/view.dart';
import 'package:PiliPlus/pages/download/season_actions.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/pages/download/search/view.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/grid.dart';
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
        GridMixin,
        BaseDownloadActionMixin<DownloadPage, DownloadSeasonInfo>,
        DownloadSeasonActions<DownloadPage> {
  final _progress = ChangeNotifier();
  final _controller = Get.put(DownloadController());
  final _scroll = ScrollController(keepScrollOffset: false);
  DownloadFolderSelection? _moving;
  String _folderQuery = '';
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
    if (!downloadService.folderIndex.folders.any(
      (folder) => !selection.sources.contains(folder.group.key),
    )) {
      SmartDialog.showToast('没有可移动到的其他文件夹');
      return;
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _folderQuery = '';
      _moving = selection;
    });
  }

  void _cancelMove() {
    if (!_savingFolder) setState(() => _moving = null);
  }

  Future<void> _confirmMove(
    DownloadFolderSelection selection,
    DownloadOwnerFolder folder,
  ) async {
    final yes = await confirmDownloadFolderMove(context, selection, folder);
    if (!mounted || yes != true) return;
    if (await _saveFolder(
          () => downloadService.moveToFolder(selection, folder.group.key),
        ) &&
        mounted) {
      _controller.handleSelect();
      _cancelMove();
    }
  }

  Widget _movePage(DownloadFolderSelection selection) => popScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancelMove();
    },
    child: SimpleScaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消移动',
          onPressed: _savingFolder ? null : _cancelMove,
          icon: const Icon(Icons.close),
        ),
        title: const Text('移动到文件夹'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索文件夹',
              ),
              onChanged: (value) =>
                  setState(() => _folderQuery = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: Obx(() {
              final folders = _controller.moveTargets(selection, _folderQuery);
              if (folders.isEmpty) return const Center(child: Text('没有匹配的文件夹'));
              return ListView.builder(
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final group = folders[index].group;
                  final identity = switch (group.key.split(':').first) {
                    'id' => 'UID ${group.key.substring(3)}',
                    'manual' => '手动 · ${group.seasons.first.pages.first.title}',
                    _ =>
                      downloadService.folderIndex.originalName(group.key) ??
                          '作者文件夹',
                  };
                  return ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(group.name),
                    subtitle: Text(
                      '$identity · ${group.videoCount} 个视频',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: _savingFolder
                        ? null
                        : () => _confirmMove(selection, folders[index]),
                  );
                },
              );
            }),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_moving case final selection?) return _movePage(selection);
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
                        SliverGrid.builder(
                          gridDelegate: gridDelegate,
                          itemCount: _controller.items.length,
                          itemBuilder: (context, index) {
                            final item = _controller.items[index];
                            if (item is DownloadOwnerFolder) {
                              return DownloadOwnerItem(
                                key: ValueKey(item.pageId),
                                folder: item,
                                enableMultiSelect: enableMultiSelect,
                                onTap: () async {
                                  if (enableMultiSelect) {
                                    _controller.onSelect(item);
                                  } else {
                                    final selection =
                                        await Get.to<DownloadFolderSelection>(
                                          DownloadOwnerPage(
                                            ownerKey: item.group.key,
                                            ownerName: item.group.name,
                                            progress: _progress,
                                          ),
                                        );
                                    if (mounted && selection != null) {
                                      _beginMove(selection);
                                    }
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
