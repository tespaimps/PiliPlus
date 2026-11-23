import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart';
import 'package:PiliPlus/models_new/video/video_detail/stat_detail.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/download/download/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/scroll_offset_helper.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart'
    show ExtendedNestedScrollController;
import 'package:get/get.dart';

class LocalIntroController extends CommonIntroController {
  @override
  void queryVideoIntro() {}

  @override
  int get copyright => throw UnimplementedError();

  @override
  void actionLikeVideo() {}

  @override
  void actionShareVideo(context) {}

  @override
  void actionTriple() {}

  @override
  Future<void> actionFavVideo({bool isQuick = false}) async {}

  @override
  (Object, int) get getFavRidType => throw UnimplementedError();

  @override
  StatDetail? getStat() => null;

  @override
  bool get isShowOnlineTotal => false;

  @override
  void onChangeEpisode(BaseEpisodeItem episode) => throw UnimplementedError();

  late final Set<String> aidSet = {};

  @override
  void onClose() {
    aidSet.clear();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    videoDetail.value.title = videoDetailCtr.args['title'];
    final controller = Get.find<DownloadController>();
    final list = <BiliDownloadEntryInfo>[];
    for (final season in controller.seasons) {
      for (final page in season.pages) {
        final completed = page.entries.where((e) => e.isCompleted).toList()
          ..sort(downloadEntrySort);
        list.addAll(completed);
        if (completed.length == 1) {
          aidSet.add(page.pageId);
        }
      }
    }
    this.list.value = list;
    final currCid = videoDetailCtr.cid.value;
    final index = list.indexWhere((e) => e.cid == currCid);
    this.index.value = index;
    if (index >= 0 && PlatformUtils.isMobile) {
      onVideoDetailChange(list[index]);
    }
  }

  void revealPlaying(double offset, double remaining) {
    if (isClosed) return;
    final state = videoDetailCtr.scrollKey.currentState;
    if (state != null && state.mounted) {
      final positions =
          (state.innerController as ExtendedNestedScrollController)
              .nestedPositions;
      if (positions.isEmpty) return;
      final position = positions.first;
      position.localJumpTo(
        adjustScrollOffset(
          offset: offset,
          remain: remaining,
          viewportDimension: position.viewportDimension,
        ),
      );
    } else if (videoDetailCtr.introScrollCtr?.hasClients ?? false) {
      final position = videoDetailCtr.introScrollCtr!.position;
      position.jumpTo(
        adjustScrollOffset(
          offset: offset,
          remain: remaining,
          viewportDimension: position.viewportDimension,
        ),
      );
    }
  }

  final index = (-1).obs;
  final list = RxList<BiliDownloadEntryInfo>();

  @override
  bool nextPlay() {
    final next = index.value + 1;
    if (next < list.length) {
      playIndex(next);
      return true;
    } else {
      final playCtr = videoDetailCtr.plPlayerController;
      if (playCtr.playRepeat == PlayRepeat.listCycle) {
        if (list.length == 1) {
          if (playCtr.videoPlayerController case final ctr?) {
            ctr.seek(Duration.zero).whenComplete(ctr.play);
          }
        } else {
          playIndex(0);
        }
        return true;
      }
    }
    return false;
  }

  @override
  bool prevPlay() {
    final prev = index.value - 1;
    if (prev >= 0) {
      playIndex(prev);
      return true;
    }
    return false;
  }

  void playIndex(
    int index, {
    BiliDownloadEntryInfo? entry,
  }) {
    entry ??= list[index];
    videoDetailCtr
      ..onReset()
      ..cover.value = entry.cover
      ..aid = entry.avid
      ..bvid = entry.bvid
      ..cid.value = entry.cid
      ..args['dirPath'] = entry.entryDirPath
      ..initFileSource(entry)
      ..initPlayerIfNeeded(false);
    videoDetail
      ..value.title = entry.showTitle
      ..refresh();
    this.index.value = index;
    if (PlatformUtils.isMobile) {
      onVideoDetailChange(entry);
    }
  }

  void onVideoDetailChange(BiliDownloadEntryInfo entry) {
    videoPlayerServiceHandler?.onVideoDetailChange(entry, entry.cid, heroTag);
  }
}
