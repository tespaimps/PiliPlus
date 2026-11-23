import 'dart:io';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/pages/download/download_grid.dart';
import 'package:PiliPlus/pages/video/introduction/local/controller.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

class LocalIntroPanel extends StatefulWidget {
  const LocalIntroPanel({super.key, required this.heroTag});

  final String heroTag;

  @override
  State<LocalIntroPanel> createState() => _LocalIntroPanelState();
}

class _LocalIntroPanelState extends State<LocalIntroPanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final _controller = Get.find<LocalIntroController>(tag: widget.heroTag);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Obx(() {
      final currIndex = _controller.index.value;
      return DownloadGrid(
        singleHorizontal: true,
        revealIndex: currIndex,
        onReveal: _controller.revealPlaying,
        itemCount: _controller.list.length,
        itemBuilder: (context, index) {
          final item = _controller.list[index];
          return _buildItem(theme, currIndex == index, index, item);
        },
      );
    });
  }

  Widget _buildItem(
    ThemeData theme,
    bool isCurr,
    int index,
    BiliDownloadEntryInfo entry,
  ) {
    final outline = theme.colorScheme.outline;
    final cover = File(path.join(entry.entryDirPath, PathUtils.coverName));
    final cacheWidth = entry.pageData?.cacheWidth ?? false;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          if (isCurr) {
            return;
          }
          _controller.playIndex(index, entry: entry);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: DownloadCardLayout(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final height = constraints.maxHeight;
                        return cover.existsSync()
                            ? ClipRRect(
                                borderRadius: Style.mdRadius,
                                child: Image.file(
                                  cover,
                                  width: width,
                                  height: height,
                                  fit: BoxFit.cover,
                                  cacheWidth: cacheWidth
                                      ? width.cacheSize(context)
                                      : null,
                                  cacheHeight: cacheWidth
                                      ? null
                                      : height.cacheSize(context),
                                  colorBlendMode: NetworkImgLayer.reduce
                                      ? BlendMode.modulate
                                      : null,
                                  color: NetworkImgLayer.reduce
                                      ? NetworkImgLayer.reduceLuxColor
                                      : null,
                                ),
                              )
                            : NetworkImgLayer(
                                src: entry.cover,
                                width: width,
                                height: height,
                              );
                      },
                    ),
                  ),
                  PBadge(
                    text: DurationUtils.formatDuration(
                      entry.totalTimeMilli ~/ 1000,
                    ),
                    right: 6.0,
                    bottom: 6.0,
                    type: .gray,
                  ),
                  entry.qaBadge,
                ],
              ),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      spacing: 5,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: theme.textTheme.bodyMedium!.fontSize,
                            height: 1.42,
                            letterSpacing: 0.3,
                            color: isCurr ? theme.colorScheme.primary : null,
                            fontWeight: isCurr ? FontWeight.bold : null,
                          ),
                          maxLines: entry.ep != null ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (entry.pageData?.part case final part?)
                          if (part != entry.title)
                            Text(
                              part,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        if (entry.ep?.showTitle case final showTitle?)
                          Text(
                            showTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (entry.ownerName case final ownerName?)
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          ownerName,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1,
                            color: outline,
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: entry.moreBtn(theme.colorScheme),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
