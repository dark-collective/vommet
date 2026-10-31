# Vommet patch to crop_image 1.0.17

Vendored from pub.dev crop_image 1.0.17 (MIT, `LICENSE`), used through a
`dependency_overrides` path entry in `commet/pubspec.yaml`. Only `lib/` is
changed, in `lib/src/crop_image.dart` (marked `Vommet:`):

- The crop grid's `GestureDetector` uses `DragStartBehavior.down`, so
  `onPanStart` looks for the corner under the point the finger went down on.
  With the default (`start`), a drag that has to win the gesture arena against
  another recognizer starts only after the pointer has moved past the pan slop.
  The corner is then looked up at that later point, outside the corner's touch
  area (`touchSize`), so it was taken as a move of a full-size crop box, which
  can't move. The picture editor puts the cropper inside an `InteractiveViewer`
  (zoom), so on touch screens the crop handles didn't move at all
  (Vommet issue 942). A mouse's slop is about 2 px, so desktop worked. When the
  pan recognizer is alone in the arena it wins on pointer down and both
  behaviors start at the same point, so nothing changes there.

Drop this copy if upstream exposes `dragStartBehavior` or makes this change.
