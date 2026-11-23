import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/models_new/download/download_sort.dart';
import 'package:PiliPlus/pages/common/multi_select/base.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/pages/download/download/widgets/move_destination.dart';
import 'package:PiliPlus/pages/download/download_grid.dart';
import 'package:PiliPlus/pages/download/download_sort_dialog.dart';
import 'package:PiliPlus/pages/download/download_action_mixin.dart';
import 'package:PiliPlus/pages/download/season_actions.dart';
import 'package:PiliPlus/services/download/download_service.dart';
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
        BaseDownloadActionMixin<DownloadOwnerPage, DownloadSeasonInfo>,
        DownloadSeasonActions<DownloadOwnerPage> {
  final _controller = Get.find<DownloadController>();
  final _scroll = ScrollController();
  final _grid = GlobalKey<DownloadGridState>();
  late var _sort = _controller.sort.value;
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
    _seasons.value =
        sortDownloads(_controller.ownerSeasons(widget.ownerKey), _sort).map((
          season,
        ) {
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
    _scroll.dispose();
    super.dispose();
  }

  @override
  void onRemove() => _controller.removeSeasons(
    allChecked.toList(),
    onRemoved: () {
      if (mounted) handleSelect();
    },
  );

  Future<void> _move() async {
    if (checkedCount == 0) return;
    final selection = downloadService.captureFolderSelection(allChecked);
    final anchor = DownloadScrollAnchor.capture(_scroll, [_grid]);
    if (!await chooseDownloadDestination(context, selection) || !mounted) {
      return;
    }
    handleSelect();
    _loadList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) anchor?.restore(_scroll, [_grid]);
    });
  }

  Future<void> _changeSort() async {
    final sort = await chooseDownloadSort(context, _sort);
    if (sort == null || !mounted) return;
    _sort = sort;
    _loadList();
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
                tooltip: '排序',
                onPressed: _changeSort,
                icon: const Icon(Icons.sort),
              ),
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
          controller: _scroll,
          slivers: [
            ViewSliverSafeArea(
              sliver: _seasons.isEmpty
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('暂无缓存视频')),
                    )
                  : DownloadGrid(
                      key: _grid,
                      idAt: (index) =>
                          downloadCardSelectionKey(_seasons[index]),
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
