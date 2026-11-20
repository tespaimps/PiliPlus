import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/models_new/download/download_folder_index.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/pages/download/season_actions.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;

class DownloadOwnerPage extends StatefulWidget {
  const DownloadOwnerPage({
    super.key,
    required this.ownerKey,
    required this.ownerName,
    required this.progress,
  });
  final String ownerKey;
  final String ownerName;
  final ChangeNotifier progress;
  @override
  State<DownloadOwnerPage> createState() => _DownloadOwnerPageState();
}

class _DownloadOwnerPageState extends State<DownloadOwnerPage>
    with
        BaseMultiSelectMixin<DownloadSeasonInfo>,
        GridMixin,
        BaseDownloadActionMixin<DownloadOwnerPage, DownloadSeasonInfo>,
        DownloadSeasonActions<DownloadOwnerPage> {
  final _controller = Get.find<DownloadController>();
  final _seasons = RxList<DownloadSeasonInfo>();
  StreamSubscription? _sub;
  @override
  final downloadService = Get.find<DownloadService>();
  @override
  List<DownloadSeasonInfo> get list => _seasons;
  @override
  RxList<DownloadSeasonInfo> get state => _seasons;
  @override
  BaseMultiSelectMixin<DownloadSeasonInfo> get multiSelectCtr => this;

  @override
  void initState() {
    super.initState();
    _loadList();
    _sub = _controller.flag.listen((_) => _loadList());
  }

  void _loadList() => Timeline.timeSync('Offline cache: load author list', () {
    final selected = allChecked.map(downloadSelectionKey).toSet();
    var count = 0;
    _seasons.value = _controller.ownerSeasons(widget.ownerKey).map((season) {
      final item = selectableDownloadSeason(season);
      if (selected.contains(downloadSelectionKey(item))) {
        item.checked = true;
        count++;
      }
      return item;
    }).toList();
    rxCount.value = count;
    if (count == 0) enableMultiSelect.value = false;
  });

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  void onRemove() => _controller.removeSeasons(
    allChecked.toList(),
    onRemoved: () {
      if (mounted) handleSelect();
    },
  );

  void _move() {
    if (checkedCount == 0) return;
    final selection = downloadService.captureFolderSelection(allChecked);
    if (_controller.moveTargets(selection, '').isEmpty) {
      SmartDialog.showToast('没有可移动到的其他文件夹');
      return;
    }
    Get.back<DownloadFolderSelection>(result: selection);
  }

  @override
  Widget build(BuildContext context) => Obx(
    () => popScope(
      canPop: !enableMultiSelect.value,
      onPopInvokedWithResult: (didPop, result) {
        if (enableMultiSelect.value) handleSelect();
      },
      child: SimpleScaffold(
        appBar: MultiSelectAppBarWidget(
          ctr: this,
          actionsBelow: MediaQuery.sizeOf(context).width < 420,
          actions: [
            Obx(
              () => TextButton(
                onPressed: checkedCount > 0 ? _move : null,
                child: const Text('移动'),
              ),
            ),
            updateBtn(),
          ],
          child: AppBar(
            title: Obx(
              () => Text(
                _controller.liveFolderName(widget.ownerKey) ?? widget.ownerName,
              ),
            ),
            actions: [
              IconButton(
                tooltip: '多选',
                icon: const Icon(Icons.edit_note),
                onPressed: () {
                  if (enableMultiSelect.value) {
                    handleSelect();
                  } else if (_seasons.isNotEmpty) {
                    enableMultiSelect.value = true;
                  }
                },
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
        body: CustomScrollView(
          slivers: [
            ViewSliverSafeArea(
              sliver: _seasons.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('暂无缓存视频')),
                    )
                  : SliverGrid.builder(
                      gridDelegate: gridDelegate,
                      itemCount: _seasons.length,
                      itemBuilder: (context, index) =>
                          buildSeasonItem(_seasons[index], widget.progress),
                    ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.viewPaddingOf(context).bottom + 100,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
