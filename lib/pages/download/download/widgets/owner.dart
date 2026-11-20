import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/select_mask.dart';
import 'package:PiliPlus/models_new/download/download_owner_group.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class DownloadOwnerItem extends StatelessWidget {
  const DownloadOwnerItem({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onDelete,
    required this.updateActions,
    required this.enableMultiSelect,
  });

  final DownloadOwnerFolder folder;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool enableMultiSelect;
  final Map<String, VoidCallback> updateActions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final group = folder.group;
    void menu() => showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final action in {'删除': onDelete, ...updateActions}.entries)
            DialogOption(
              onPressed: () {
                Navigator.of(context).pop();
                action.value();
              },
              child: Text(action.key),
            ),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: enableMultiSelect ? null : menu,
        onSecondaryTap: PlatformUtils.isMobile || enableMultiSelect
            ? null
            : menu,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: Row(
            spacing: 10,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) => NetworkImgLayer(
                        src: group.cover,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ),
                    ),
                  ),
                  const PBadge(text: '文件夹', top: 6.0, right: 6.0),
                  PBadge(
                    text: '${group.videoCount}个视频',
                    right: 6.0,
                    bottom: 6.0,
                    isBold: false,
                    type: .gray,
                  ),
                  Positioned.fill(
                    child: selectMask(colorScheme, folder.checked),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          height: 1.42,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Text(
                      group.totalBytes.formatSize,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: colorScheme.outline,
                      ),
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
