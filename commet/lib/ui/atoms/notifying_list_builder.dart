import 'dart:async';

import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/widgets.dart';
import 'package:implicitly_animated_list/implicitly_animated_list.dart';

class NotifyingListBuilder<T> extends StatefulWidget {
  const NotifyingListBuilder(
      {required this.list,
      this.builder,
      required this.itemBuilder,
      this.shrinkWrap = false,
      this.implicitlyAnimated = true,
      this.sortFunction,
      this.physics,
      this.onSortStream,
      this.sliver = false,
      super.key});

  final INotifyingList<T> list;
  final Widget Function(BuildContext context,
      {required List<T> list, required Widget child})? builder;
  final Widget Function(BuildContext context, T value) itemBuilder;
  final Stream? onSortStream;
  final bool shrinkWrap;
  final bool implicitlyAnimated;
  final ScrollPhysics? physics;
  final int Function(T, T)? sortFunction;

  /// Vommet: build a lazy sliver (only visible rows are built) for use in a
  /// CustomScrollView, instead of a box list. [builder] must then return a
  /// sliver too. [shrinkWrap] and [physics] don't apply.
  final bool sliver;

  @override
  State<NotifyingListBuilder<T>> createState() =>
      _NotifyingListBuilderState<T>();
}

class _NotifyingListBuilderState<T> extends State<NotifyingListBuilder<T>> {
  late List<StreamSubscription> subs;

  late List<T> items;

  @override
  void initState() {
    subs = [
      widget.list.onAdd.listen(onAdd),
      widget.list.onItemUpdated.listen(onItemUpdated),
      widget.list.onRemove.listen(onRemove),
      widget.list.onListUpdated.listen(onListUpdated),
      if (widget.onSortStream != null)
        widget.onSortStream!.listen((_) => doSort()),
    ];

    items = widget.list;

    if (widget.sortFunction != null) {
      items = widget.list.toList();
      items.sort(widget.sortFunction);
    }

    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) sub.cancel();

    super.dispose();
  }

  void doSort() {
    if (widget.sortFunction != null) {
      final sorted = widget.list.toList()..sort(widget.sortFunction);
      // Vommet: no rebuild when nothing moved; the DM list now also re-sorts
      // after every sync (DirectMessagesAggregator).
      if (sorted.length == items.length &&
          List.generate(sorted.length, (i) => identical(sorted[i], items[i]))
              .every((same) => same)) {
        return;
      }
      setState(() => items = sorted);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sliver) {
      final Widget sliver = widget.implicitlyAnimated
          ? SliverImplicitlyAnimatedList(
              itemData: items,
              initialAnimation: false,
              itemBuilder: widget.itemBuilder)
          : SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  widget.itemBuilder(context, items[index]),
            );
      if (widget.builder != null) {
        return widget.builder!(context, list: items, child: sliver);
      }
      return sliver;
    }

    var result = widget.implicitlyAnimated
        ? ImplicitlyAnimatedList(
            shrinkWrap: widget.shrinkWrap,
            itemData: items,
            physics: widget.physics,
            padding: EdgeInsets.zero,
            initialAnimation: false,
            itemBuilder: widget.itemBuilder)
        : ListView.builder(
            shrinkWrap: widget.shrinkWrap,
            itemCount: items.length,
            physics: widget.physics,
            padding: EdgeInsets.zero,
            itemBuilder: (context, index) {
              var item = items[index];

              return widget.itemBuilder(context, item);
            },
          );

    if (widget.builder != null) {
      return widget.builder!(context, list: items, child: result);
    }

    return result;
  }

  void onAdd(T event) {}

  void onItemUpdated(T event) {}

  void onRemove(T event) {}

  void onListUpdated(event) {
    setState(() {
      items = widget.list;

      if (widget.sortFunction != null) {
        items = widget.list.toList();
        items.sort(widget.sortFunction);
      }
    });
  }
}
