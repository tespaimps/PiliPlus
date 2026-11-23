import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/common/search/common_search_page.dart';
import 'package:PiliPlus/pages/download/download/widgets/folder_dialogs.dart';
import 'package:PiliPlus/pages/download/download/widgets/move_destination.dart';
import 'package:PiliPlus/pages/download/download/widgets/owner.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/pages/download/download_grid.dart';
import 'package:PiliPlus/pages/download/owner/view.dart';
import 'package:PiliPlus/pages/download/search/controller.dart';
import 'package:PiliPlus/pages/download/season_actions.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DownloadSearchPage extends StatefulWidget {
  const DownloadSearchPage({super.key, required this.progress});
  final ChangeNotifier progress;

  @override
  State<DownloadSearchPage> createState() => _DownloadSearchPageState();
}

class _DownloadSearchPageState
    extends
        CommonSearchPageState<
          DownloadSearchPage,
          List<DownloadSeasonInfo>,
          DownloadSeasonInfo
        >
    with
        BaseDownloadActionMixin<DownloadSearchPage, DownloadSeasonInfo>,
        DownloadSeasonActions<DownloadSearchPage> {
  @override
  final DownloadSearchController controller = Get.put(
    DownloadSearchController(),
  );
  @override
  final downloadService = Get.find<DownloadService>();
  final _folders = GlobalKey<DownloadGridState>();
  final _videos = GlobalKey<DownloadGridState>();
  var _saving = false;

  @override
  BaseMultiSelectMixin<DownloadSeasonInfo> get multiSelectCtr => controller;

  @override
  String get searchHint => '搜索文件夹、标题或UP主';

  @override
  bool get multiSelectActionsBelow => MediaQuery.sizeOf(context).width < 480;

  @override
  List<Widget>? get extraActions => [
    IconButton(
      tooltip: '多选',
      onPressed: () {
        if (controller.loadingState.value is! Success ||
            controller.list.isEmpty) {
          return;
        }
        controller.enableMultiSelect.value = true;
      },
      icon: const Icon(Icons.edit_note),
    ),
  ];

  @override
  List<Widget>? get multiSelectActions => [
    Obx(
      () => TextButton(
        onPressed: controller.checkedCount >= 2 && !_saving ? _merge : null,
        child: const Text('合并'),
      ),
    ),
    Obx(
      () => TextButton(
        onPressed: controller.canMove && !_saving ? _move : null,
        child: const Text('移动'),
      ),
    ),
    updateBtn(),
  ];

  Future<bool> _save(Future<void> Function() action) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await action();
      return true;
    } on DownloadFolderException catch (error) {
      SmartDialog.showToast(error.message);
      return false;
    } catch (_) {
      SmartDialog.showToast('保存文件夹归类失败，请重试');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _merge() async {
    final selection = downloadService.captureFolderSelection(
      controller.allChecked,
    );
    if (selection.count < 2) {
      SmartDialog.showToast('请至少选择两个不同的视频');
      return;
    }
    final name = await askDownloadFolderName(context);
    if (!mounted || name == null) return;
    if (await _save(() => downloadService.mergeFolders(selection, name)) &&
        mounted) {
      controller.handleSelect();
      await controller.refreshResults();
    }
  }

  Future<void> _move() async {
    final scroll = controller.scrollController;
    final grids = [_folders, _videos];
    final anchor = DownloadScrollAnchor.capture(scroll, grids);
    final selection = downloadService.captureFolderSelection(
      controller.allChecked,
    );
    if (!await chooseDownloadDestination(context, selection) || !mounted) {
      return;
    }
    controller.handleSelect();
    await controller.refreshResults();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) anchor?.restore(scroll, grids);
    });
  }

  Future<void> _rename(DownloadOwnerFolder folder) async {
    final scope = downloadService.folderStorageKey;
    final name = await askDownloadFolderName(
      context,
      current: folder.group.name,
    );
    if (!mounted || name == null || name == folder.group.name) return;
    await _save(
      () => downloadService.renameFolder(scope, folder.group.key, name),
    );
  }

  @override
  Future<bool> onUpdate(
    Future<bool> Function(BiliDownloadEntryInfo) toElement,
  ) async {
    final count = downloadService
        .captureFolderSelection(controller.allChecked)
        .count;
    if (count == 0) return false;
    if (!await showConfirmDialog(
          context: context,
          title: Text('确定更新所选内容中的 $count 个视频及其缓存分 P？'),
        ) ||
        !mounted) {
      return false;
    }
    return super.onUpdate(toElement);
  }

  Widget _folder(DownloadOwnerFolder folder) {
    final selecting = controller.enableMultiSelect.value;
    return DownloadOwnerItem(
      folder: folder,
      enableMultiSelect: selecting,
      onTap: selecting
          ? () => controller.onSelect(folder)
          : () => Get.to<void>(
              DownloadOwnerPage(
                ownerKey: folder.group.key,
                ownerName: folder.group.name,
                progress: widget.progress,
              ),
            ),
      onDelete: () => controller.removeCards([folder]),
      updateActions: {
        '重命名': () => _rename(folder),
        '更新弹幕': () => updateSeasonDm(folder),
        '更新片段': () => updateSeasonSeg(folder),
        '更新合集信息': () => updateSeasonSeasonInfo(folder),
        '更新音量均衡': () => updateSeasonVolume(folder),
        '更新字幕、分段信息': () => updateSeasonPlayInfo(folder),
      },
    );
  }

  @override
  Widget buildList(List<DownloadSeasonInfo> list) {
    final split = list.indexWhere((item) => item is! DownloadOwnerFolder);
    final folders = split < 0 ? list.length : split;
    final videos = list.length - folders;
    return SliverMainAxisGroup(
      slivers: [
        if (folders > 0) ...[
          const SliverToBoxAdapter(child: ListTile(title: Text('文件夹'))),
          DownloadGrid(
            key: _folders,
            itemCount: folders,
            idAt: (i) => downloadCardSelectionKey(list[i]),
            itemBuilder: (_, i) => _folder(list[i] as DownloadOwnerFolder),
          ),
        ],
        if (videos > 0) ...[
          const SliverToBoxAdapter(child: ListTile(title: Text('视频'))),
          DownloadGrid(
            key: _videos,
            itemCount: videos,
            idAt: (i) => downloadCardSelectionKey(list[folders + i]),
            itemBuilder: (_, i) {
              final item = list[folders + i];
              return buildSeasonItem(
                item,
                widget.progress,
                contextLabel: controller.contextLabel(item),
                searchResult: true,
              );
            },
          ),
        ],
      ],
    );
  }
}
