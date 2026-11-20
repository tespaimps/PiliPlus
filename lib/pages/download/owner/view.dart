import 'dart:async';

import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/pages/download/season_actions.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/grid.dart';
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

  void _loadList() {
    final selected = allChecked.map(downloadSelectionKey).toSet();
    final groups = groupDownloadsByOwner(_controller.seasons);
    final group = groups.where((g) => g.key == widget.ownerKey).firstOrNull;
    _seasons.value = [...?group?.seasons]
      ..forEach((s) => s.checked = selected.contains(downloadSelectionKey(s)));
    rxCount.value = allChecked.length;
    if (rxCount.value == 0) enableMultiSelect.value = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final season in _seasons) {
      season.checked = false;
    }
    super.dispose();
  }

  @override
  void onRemove() => _controller.removeSeasons(
    allChecked.toList(),
    onRemoved: () {
      if (mounted) handleSelect();
    },
  );

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
          actions: [updateBtn()],
          child: AppBar(
            title: Text(widget.ownerName),
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
