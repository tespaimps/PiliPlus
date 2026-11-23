import 'dart:math' as math;

import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter/rendering.dart'
    show RenderSliverGrid, SliverConstraints, SliverGridLayout;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class _CardOrientation extends InheritedWidget {
  const _CardOrientation(this.vertical, {required super.child});
  final bool vertical;

  @override
  bool updateShouldNotify(_CardOrientation oldWidget) =>
      oldWidget.vertical != vertical;
}

class DownloadCardLayout extends StatelessWidget {
  const DownloadCardLayout({super.key, required this.children});
  final List<Widget> children;

  static bool verticalOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_CardOrientation>()
          ?.vertical ??
      false;

  @override
  Widget build(BuildContext context) => verticalOf(context)
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 5,
          children: children,
        )
      : Row(spacing: 10, children: children);
}

class DownloadGrid extends StatefulWidget {
  const DownloadGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.idAt,
    this.revealIndex,
    this.onReveal,
    this.horizontalExtent = 110,
    this.singleHorizontal = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final String Function(int)? idAt;
  final int? revealIndex;
  final void Function(double offset, double remaining)? onReveal;
  final double horizontalExtent;
  final bool singleHorizontal;

  @override
  State<DownloadGrid> createState() => DownloadGridState();
}

class DownloadGridState extends State<DownloadGrid> {
  final _sliver = GlobalKey();
  bool? _lastVertical;
  bool _didReveal = false;

  RenderSliverGrid? get _render {
    final render = _sliver.currentContext?.findRenderObject();
    return render is RenderSliverGrid &&
            render.attached &&
            render.geometry != null
        ? render
        : null;
  }

  ({double start, SliverGridLayout layout})? get _geometry {
    final render = _render;
    if (render == null) return null;
    return (
      start: render.constraints.precedingScrollExtent,
      layout: render.gridDelegate.getLayout(render.constraints),
    );
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final vertical = Get.find<DownloadService>().downloadTwoColumns.value;
    final index = widget.revealIndex;
    if (widget.onReveal != null &&
        index != null &&
        index >= 0 &&
        index < widget.itemCount &&
        (!_didReveal || _lastVertical != vertical)) {
      _didReveal = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || index >= widget.itemCount) return;
        final geometry = _geometry;
        if (geometry == null) return;
        final layout = geometry.layout;
        final offset = layout.getGeometryForChildIndex(index).scrollOffset;
        widget.onReveal?.call(
          offset,
          layout.computeMaxScrollOffset(widget.itemCount) - offset,
        );
      });
    }
    _lastVertical = vertical;
    return _CardOrientation(
      vertical,
      child: SliverGrid.builder(
        key: _sliver,
        gridDelegate: vertical
            ? _DownloadVerticalDelegate(MediaQuery.textScalerOf(context))
            : widget.singleHorizontal
            ? SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1,
                mainAxisExtent: widget.horizontalExtent,
                mainAxisSpacing: 2,
              )
            : Grid.videoCardHDelegate(mainAxisExtent: widget.horizontalExtent),
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
    );
  });
}

class _DownloadVerticalDelegate extends SliverGridDelegate {
  const _DownloadVerticalDelegate(this.scaler);
  final TextScaler scaler;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent / 2;
    final cover = math.max(0.0, width - 24) / (16 / 10);
    final details = math.max(92.0, scaler.scale(14) * 4.5 + 30);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 2,
      mainAxisExtent: cover + details + 15,
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(_DownloadVerticalDelegate oldDelegate) =>
      scaler != oldDelegate.scaler;
}

class DownloadScrollAnchor {
  const DownloadScrollAnchor._(this.ids, this.index, this.offset, this.pixels);
  final List<String> ids;
  final int index;
  final double offset;
  final double pixels;

  static DownloadScrollAnchor? capture(
    ScrollController scroll,
    List<GlobalKey<DownloadGridState>> grids,
  ) {
    if (!scroll.hasClients) return null;
    final pixels = scroll.offset;
    final ids = <String>[];
    int? index;
    var offset = 0.0;
    for (final key in grids) {
      final state = key.currentState;
      final geometry = state?._geometry;
      final count = state?.widget.itemCount ?? 0;
      final idAt = state?.widget.idAt;
      if (count == 0 || geometry == null || idAt == null) continue;
      final (:start, :layout) = geometry;
      if (index == null &&
          pixels < start + layout.computeMaxScrollOffset(count)) {
        final item = layout
            .getMinChildIndexForScrollOffset(math.max(0, pixels - start))
            .clamp(0, count - 1);
        index = ids.length + item;
        offset =
            pixels - start - layout.getGeometryForChildIndex(item).scrollOffset;
      }
      for (var i = 0; i < count; i++) {
        ids.add(idAt(i));
      }
    }
    return DownloadScrollAnchor._(
      ids,
      index ?? math.max(0, ids.length - 1),
      offset,
      pixels,
    );
  }

  void restore(
    ScrollController scroll,
    List<GlobalKey<DownloadGridState>> grids,
  ) {
    if (!scroll.hasClients) return;
    final positions =
        <String, ({double start, SliverGridLayout layout, int index})>{};
    for (final key in grids) {
      final state = key.currentState;
      final geometry = state?._geometry;
      final idAt = state?.widget.idAt;
      if (state == null || geometry == null || idAt == null) continue;
      for (var i = 0; i < state.widget.itemCount; i++) {
        positions[idAt(i)] = (
          start: geometry.start,
          layout: geometry.layout,
          index: i,
        );
      }
    }
    ({double start, SliverGridLayout layout, int index})? target;
    for (var i = index; i < ids.length && target == null; i++) {
      target = positions[ids[i]];
    }
    for (var i = index - 1; i >= 0 && target == null; i--) {
      target = positions[ids[i]];
    }
    final position = scroll.position;
    final absolute = target == null
        ? pixels
        : target.start +
              target.layout
                  .getGeometryForChildIndex(target.index)
                  .scrollOffset +
              offset;
    scroll.jumpTo(
      absolute.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }
}
