# Vommet patch to just_the_tooltip 0.0.12

Vendored from pub.dev just_the_tooltip 0.0.12 (MIT, `LICENSE`), used through a
`dependency_overrides` path entry in `commet/pubspec.yaml`. Only `lib/` is
changed, in `lib/src/just_the_tooltip.dart` (marked `Vommet:`):

- `_createEntry` draws nothing while the target's render box is detached or not
  laid out. The overlay can rebuild the tooltip entry in the frame its target
  leaves the tree (`deactivate` hides the entry only after that frame), and
  `localToGlobal` on the detached box threw a `_TypeError` in
  `RenderObject.getTransformTo` (seen in Linux telemetry).
- `ensureTooltipVisible` does nothing once the state is unmounted (a show
  timer or post-frame callback outliving the target).

Drop this copy if upstream fixes it.
