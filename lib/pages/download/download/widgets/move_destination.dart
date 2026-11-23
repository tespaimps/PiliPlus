import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download/widgets/folder_dialogs.dart';
import 'package:PiliPlus/pages/download/download/widgets/owner.dart';
import 'package:PiliPlus/pages/download/download_grid.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

Future<bool> chooseDownloadDestination(
  BuildContext context,
  DownloadFolderSelection selection,
) async {
  if (selection.count == 0) return false;
  if (Get.find<DownloadController>().moveTargets(selection, '').isEmpty) {
    SmartDialog.showToast('没有可移动到的其他文件夹');
    return false;
  }
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => DownloadMoveDestination(
            selection: selection,
            onClose: (moved) => Navigator.of(context).pop(moved),
          ),
        ),
      ) ??
      false;
}

class DownloadMoveDestination extends StatefulWidget {
  const DownloadMoveDestination({
    super.key,
    required this.selection,
    required this.onClose,
  });
  final DownloadFolderSelection selection;
  final ValueChanged<bool> onClose;

  @override
  State<DownloadMoveDestination> createState() =>
      _DownloadMoveDestinationState();
}

class _DownloadMoveDestinationState extends State<DownloadMoveDestination> {
  final _controller = Get.find<DownloadController>();
  final _service = Get.find<DownloadService>();
  final _scroll = ScrollController(keepScrollOffset: false);
  var _query = '';
  var _saving = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _choose(DownloadOwnerFolder folder) async {
    final yes = await confirmDownloadFolderMove(
      context,
      widget.selection,
      folder,
    );
    if (!mounted || yes != true || _saving) return;
    setState(() => _saving = true);
    try {
      await _service.moveToFolder(widget.selection, folder.group.key);
      if (mounted) widget.onClose(true);
    } on DownloadFolderException catch (error) {
      SmartDialog.showToast(error.message);
    } catch (_) {
      SmartDialog.showToast('保存文件夹归类失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !_saving) widget.onClose(false);
    },
    child: SimpleScaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消移动',
          onPressed: _saving ? null : () => widget.onClose(false),
          icon: const Icon(Icons.close),
        ),
        title: const Text('移动到文件夹'),
      ),
      body: Padding(
        padding: EdgeInsets.only(
          left: MediaQuery.viewPaddingOf(context).left,
          right: MediaQuery.viewPaddingOf(context).right,
        ),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索文件夹',
                  ),
                  onChanged: (value) {
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                    setState(() => _query = value.trim().toLowerCase());
                  },
                ),
              ),
            ),
            Obx(() {
              final folders = _controller.moveTargets(widget.selection, _query);
              if (folders.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('没有匹配的文件夹')),
                );
              }
              return DownloadGrid(
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final folder = folders[index];
                  final group = folder.group;
                  final identity = switch (group.key.split(':').first) {
                    'id' => 'UID ${group.key.substring(3)}',
                    'manual' => group.seasons.first.pages.first.title,
                    _ =>
                      _service.folderIndex.originalName(group.key) ?? '作者文件夹',
                  };
                  return DownloadOwnerItem(
                    key: ValueKey(folder.pageId),
                    folder: folder,
                    destinationHint:
                        '$identity · ${group.totalBytes.formatSize}',
                    enableMultiSelect: false,
                    updateActions: const {},
                    onTap: () {
                      if (!_saving) _choose(folder);
                    },
                  );
                },
              );
            }),
          ],
        ),
      ),
    ),
  );
}
