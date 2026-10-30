// Vommet issue 758: the Getting started tour. Instead of pages with pictures,
// a coach-mark tour over the real app: the screen dims except a hole around
// the real element, a bubble explains it, and some steps wait for the user
// to do the thing once (tap Home, open a space's menu). It never joins,
// leaves or creates anything. The pages stay in Settings › Help and guides.
//
// Widgets mark themselves with [TourAnchor]; the steps name anchors, so the
// tour knows nothing about the layouts. A step whose element isn't on screen
// (another layout, a closed side panel, no spaces yet) shows its bubble in
// the middle instead, or is left out where it only makes sense on the
// element. TourHost (tour_host.dart) draws it all above the app.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Set at the first sign-in on a fresh install; the main page offers the
/// tour once it's up, then clears it.
final BoolPreference tourOfferPending =
    BoolPreference("vommet_tour_offer_pending", defaultValue: false);

/// What finishes a step.
enum TourStepKind {
  /// The bubble's Next (or Done) button.
  look,

  /// A tap on the step's element.
  tap,

  /// The [TourStep.waitFor] element appearing (a menu opening).
  untilAnchor,

  /// The step's element going away (the menu closing, however).
  untilGone,

  /// A guide opening (the right-click help); Done works too.
  untilGuide,
}

class TourStep {
  const TourStep({
    required this.number,
    required this.title,
    required this.body,
    this.anchor,
    this.kind = TourStepKind.look,
    this.waitFor,
    this.onlyOnElement = false,
    this.blockOutside = true,
    this.dim = true,
  });

  /// The step number shown to the user; the parts of one step share it.
  final int number;
  final String Function() title;

  /// The text; [touch] picks "tap" over "click".
  final String Function(bool touch) body;

  /// The [TourAnchor] id to point at, if any.
  final String? anchor;
  final TourStepKind kind;

  /// For [TourStepKind.untilAnchor]: the anchor whose arrival ends the step.
  final String? waitFor;

  /// Left out when its element isn't on screen, instead of shown in the
  /// middle.
  final bool onlyOnElement;

  /// Taps outside the hole do nothing, so the user does the step's action.
  /// Off where the user has to reach something else (closing a menu).
  final bool blockOutside;

  /// Dim the rest of the screen.
  final bool dim;

  /// Whether the step can only be finished on its element (no Next).
  bool get needsElement =>
      kind == TourStepKind.tap ||
      kind == TourStepKind.untilAnchor ||
      kind == TourStepKind.untilGone;
}

/// Where the tour's elements live, by id.
class TourAnchors {
  static const spaces = "spaces";
  static const space = "space";
  static const browseRooms = "browse-rooms";
  static const home = "home";

  static final Map<String, List<TourAnchorState>> _mounted = {};

  /// Bumped when an anchor comes or goes.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static bool has(String id) => _mounted[id]?.isNotEmpty ?? false;

  /// Where [id] is on screen in [host]'s coordinates: the topmost of its
  /// instances that is laid out, on the route in front, and mostly inside
  /// [host]. Null when there's none (another layout, a closed panel).
  static Rect? rectOf(String id, RenderBox host) {
    Rect? best;
    for (final state in _mounted[id] ?? const <TourAnchorState>[]) {
      final rect = state.rectIn(host);
      if (rect == null) continue;
      if (best == null ||
          rect.top < best.top ||
          (rect.top == best.top && rect.left < best.left)) {
        best = rect;
      }
    }
    return best;
  }

  static void _add(String id, TourAnchorState state) {
    (_mounted[id] ??= []).add(state);
    _changed();
  }

  static void _remove(String id, TourAnchorState state) {
    _mounted[id]?.remove(state);
    _changed();
  }

  static void _changed() {
    // Anchors come and go while widgets build; tell the tour afterwards.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      changes.value++;
      Tour.instance.anchorsChanged();
    });
  }

  /// Visible on screen: at least half of [rect] inside [bounds].
  static bool mostlyInside(Rect rect, Rect bounds) {
    if (rect.isEmpty) return false;
    final inside = rect.intersect(bounds);
    if (inside.width <= 0 || inside.height <= 0) return false;
    return inside.width * inside.height >= rect.width * rect.height / 2;
  }
}

/// Marks [child] as the tour's element [id]. Costs nothing while no tour
/// runs: a pointer listener that lets everything through.
class TourAnchor extends StatefulWidget {
  const TourAnchor({required this.id, required this.child, super.key});

  final String id;
  final Widget child;

  @override
  State<TourAnchor> createState() => TourAnchorState();
}

class TourAnchorState extends State<TourAnchor> {
  @override
  void initState() {
    super.initState();
    TourAnchors._add(widget.id, this);
  }

  @override
  void didUpdateWidget(TourAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      TourAnchors._remove(oldWidget.id, this);
      TourAnchors._add(widget.id, this);
    }
  }

  @override
  void dispose() {
    TourAnchors._remove(widget.id, this);
    super.dispose();
  }

  Rect? rectIn(RenderBox host) {
    if (!mounted) return null;
    // A page under another (Settings, a dialog) still has its layout, but
    // can't be reached.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (!host.attached) return null;
    final Offset topLeft;
    try {
      topLeft = box.localToGlobal(Offset.zero, ancestor: host);
    } catch (_) {
      return null;
    }
    final rect = topLeft & box.size;
    if (!TourAnchors.mostlyInside(rect, Offset.zero & host.size)) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => Tour.instance.anchorTapped(widget.id),
        child: widget.child,
      );
}

enum TourState { idle, offering, running, paused }

/// The tour's progress. One per app.
class Tour extends ChangeNotifier {
  Tour({List<TourStep>? steps}) : steps = steps ?? tourSteps();

  static final Tour instance = Tour();

  final List<TourStep> steps;

  TourState _state = TourState.idle;
  TourState get state => _state;

  int _index = 0;
  int get index => _index;
  TourStep get step => steps[_index];

  /// The step numbers the user sees run 1..[total].
  int get total => steps.map((s) => s.number).reduce((a, b) => a > b ? a : b);

  /// Whether the current step's element has been on screen; a step that
  /// waits for its element going away only counts it once it was there.
  bool elementSeen = false;

  /// Asks the host whether an anchor is on screen; null (tests, no host)
  /// means "registered at all".
  bool Function(String id)? isVisible;

  bool _visible(String id) => isVisible?.call(id) ?? TourAnchors.has(id);

  /// Shows the offer card if the first sign-in queued one.
  void offerIfPending() {
    if (!tourOfferPending.value || !experimentGuides.value) return;
    if (_state != TourState.idle) return;
    _state = TourState.offering;
    notifyListeners();
  }

  /// "Not now" on the offer card.
  void decline() {
    tourOfferPending.set(false);
    _state = TourState.idle;
    notifyListeners();
  }

  void start() {
    tourOfferPending.set(false);
    _state = TourState.running;
    _enter(0, forward: true);
  }

  void next() {
    if (_state != TourState.running) return;
    if (_index + 1 >= steps.length) {
      finish();
    } else {
      _enter(_index + 1, forward: true);
    }
  }

  /// Back to the first part of the step before.
  void back() {
    if (_state != TourState.running) return;
    final number = step.number;
    var i = _index - 1;
    while (i >= 0 && (steps[i].number == number || _leftOut(steps[i]))) {
      i--;
    }
    if (i < 0) return;
    final previous = steps[i].number;
    while (
        i > 0 && steps[i - 1].number == previous && !_leftOut(steps[i - 1])) {
      i--;
    }
    _enter(i, forward: false);
  }

  /// Ends the tour, finished or skipped.
  void finish() {
    gettingStartedDone.set(true);
    tourOfferPending.set(false);
    _state = TourState.idle;
    notifyListeners();
  }

  /// The user went somewhere the step's element isn't; the tour waits as a
  /// small chip.
  void pause() {
    if (_state != TourState.running) return;
    _state = TourState.paused;
    notifyListeners();
  }

  void resume() {
    if (_state != TourState.paused) return;
    _state = TourState.running;
    _enter(_index, forward: true);
  }

  bool get hasPrevious {
    final number = step.number;
    for (var i = _index - 1; i >= 0; i--) {
      if (steps[i].number != number && !_leftOut(steps[i])) return true;
    }
    return false;
  }

  bool _leftOut(TourStep s) =>
      s.onlyOnElement && (s.anchor == null || !_visible(s.anchor!));

  void _enter(int i, {required bool forward}) {
    // Steps only about an element that isn't there are left out, and the
    // parts after them too (a menu that can't open without its space).
    while (i < steps.length && _leftOut(steps[i])) {
      final number = steps[i].number;
      i++;
      while (forward && i < steps.length && steps[i].number == number) {
        i++;
      }
    }
    if (i >= steps.length) {
      finish();
      return;
    }
    _index = i;
    elementSeen = step.anchor != null && _visible(step.anchor!);
    notifyListeners();
  }

  /// Whether the current step points at its element, or shows its bubble
  /// in the middle (and can then be finished with Next).
  bool get onElement => step.anchor != null && _visible(step.anchor!);

  void anchorTapped(String id) {
    if (_state != TourState.running) return;
    if (step.kind != TourStepKind.tap || step.anchor != id) return;
    // After the tap has done its thing.
    WidgetsBinding.instance.addPostFrameCallback((_) => next());
  }

  void anchorsChanged() {
    if (_state != TourState.running) return;
    final s = step;
    if (s.anchor != null && _visible(s.anchor!)) elementSeen = true;
    switch (s.kind) {
      case TourStepKind.untilAnchor:
        if (s.waitFor != null && _visible(s.waitFor!)) next();
      case TourStepKind.untilGone:
        if (elementSeen && s.anchor != null && !TourAnchors.has(s.anchor!)) {
          next();
        }
      default:
        break;
    }
  }

  void guideOpened() {
    if (_state != TourState.running) return;
    if (step.kind == TourStepKind.untilGuide) next();
  }

  /// For tests.
  @visibleForTesting
  void reset() {
    _state = TourState.idle;
    _index = 0;
    elementSeen = false;
    isVisible = null;
  }
}

List<TourStep> tourSteps() => [
      TourStep(
        number: 1,
        anchor: TourAnchors.spaces,
        title: () => tourSpacesTitle,
        body: (_) => tourSpacesBody,
      ),
      TourStep(
        number: 2,
        anchor: TourAnchors.space,
        kind: TourStepKind.untilAnchor,
        waitFor: TourAnchors.browseRooms,
        onlyOnElement: true,
        title: () => tourBrowseTitle,
        body: (touch) => touch ? tourBrowseBodyTouch : tourBrowseBody,
      ),
      TourStep(
        number: 2,
        anchor: TourAnchors.browseRooms,
        kind: TourStepKind.untilGone,
        onlyOnElement: true,
        blockOutside: false,
        title: () => tourBrowseMenuTitle,
        body: (touch) => touch ? tourBrowseMenuBodyTouch : tourBrowseMenuBody,
      ),
      TourStep(
        number: 3,
        dim: false,
        blockOutside: false,
        title: () => tourChatTitle,
        body: (touch) => touch ? tourChatBodyTouch : tourChatBody,
      ),
      TourStep(
        number: 4,
        dim: false,
        blockOutside: false,
        title: () => tourVoiceTitle,
        body: (touch) => touch ? tourVoiceBodyTouch : tourVoiceBody,
      ),
      TourStep(
        number: 5,
        anchor: TourAnchors.home,
        kind: TourStepKind.tap,
        title: () => tourHomeTitle,
        body: (touch) => touch ? tourHomeBodyTouch : tourHomeBody,
      ),
      TourStep(
        number: 6,
        anchor: TourAnchors.spaces,
        kind: TourStepKind.untilGuide,
        dim: false,
        blockOutside: false,
        title: () => tourHelpTitle,
        body: (touch) => touch ? tourHelpBodyTouch : tourHelpBody,
      ),
    ];

String get tourOfferTitle => Intl.message("Take a 1-minute tour?",
    name: "tourOfferTitle",
    desc: "Card on the main screen after the first sign-in, offering the tour");
String get tourOfferBody => Intl.message(
    "It points at the real buttons as you go. You can replay it anytime in Settings › Help and guides.",
    name: "tourOfferBody",
    desc: "Text of the card offering the Getting started tour");
String get tourStart => Intl.message("Start",
    name: "tourStart", desc: "Button on the card that starts the tour");
String get tourNotNow => Intl.message("Not now",
    name: "tourNotNow", desc: "Button on the card that declines the tour");

String tourStepOf(int number, int total) =>
    Intl.message("Step $number of $total",
        name: "tourStepOf",
        args: [number, total],
        desc: "Shown in each bubble of the tour, e.g. Step 2 of 6");
String get tourBack => Intl.message("Back",
    name: "tourBack", desc: "Button in a tour bubble: the step before");
String get tourNext => Intl.message("Next",
    name: "tourNext", desc: "Button in a tour bubble: the next step");
String get tourDone => Intl.message("Done",
    name: "tourDone", desc: "Button in the last tour bubble: ends the tour");
String get tourSkip => Intl.message("Skip tour",
    name: "tourSkip", desc: "Button in a tour bubble: ends the tour");
String tourResume(int number, int total) =>
    Intl.message("Resume tour ($number of $total)",
        name: "tourResume",
        args: [number, total],
        desc: "Chip shown when the user left the tour's path; tapping resumes");
String get tourEnd => Intl.message("End tour",
    name: "tourEnd",
    desc: "Tooltip on the close button of the paused tour's chip");

String get tourSpacesTitle => Intl.message("Your spaces",
    name: "tourSpacesTitle", desc: "Title of the tour step about spaces");
String get tourSpacesBody => Intl.message(
    "The icons down the left are your spaces. A space works like a Discord server. Use the + below them to make one or find one to join.",
    name: "tourSpacesBody",
    desc: "Text of the tour step about spaces");

String get tourBrowseTitle => Intl.message("Find a space's rooms",
    name: "tourBrowseTitle",
    desc: "Title of the tour step that opens a space's menu");
String get tourBrowseBody => Intl.message(
    "Joining a space doesn't join all of its rooms, so a new space can look empty. Right-click this space to open its menu.",
    name: "tourBrowseBody",
    desc: "Tour step pointing at a space icon, with a mouse");
String get tourBrowseBodyTouch => Intl.message(
    "Joining a space doesn't join all of its rooms, so a new space can look empty. Press and hold this space to open its menu.",
    name: "tourBrowseBodyTouch",
    desc: "Tour step pointing at a space icon, on a touch screen");

String get tourBrowseMenuTitle => Intl.message("Browse rooms",
    name: "tourBrowseMenuTitle",
    desc: "Title of the tour step pointing at Browse rooms in a space's menu");
String get tourBrowseMenuBody => Intl.message(
    "Browse rooms lists every room in the space, including the ones you haven't joined. Click it to look around, or click outside the menu to go on.",
    name: "tourBrowseMenuBody",
    desc: "Tour step pointing at Browse rooms, with a mouse");
String get tourBrowseMenuBodyTouch => Intl.message(
    "Browse rooms lists every room in the space, including the ones you haven't joined. Tap it to look around, or tap outside the menu to go on.",
    name: "tourBrowseMenuBodyTouch",
    desc: "Tour step pointing at Browse rooms, on a touch screen");

String get tourChatTitle => Intl.message("Chatting",
    name: "tourChatTitle", desc: "Title of the tour step about messages");
String get tourChatBody => Intl.message(
    "In a room, hover over a message to reply, react or start a thread. Your own messages can be edited or deleted the same way.",
    name: "tourChatBody",
    desc: "Tour step about messages, with a mouse");
String get tourChatBodyTouch => Intl.message(
    "In a room, press and hold a message to reply, react or start a thread. Your own messages can be edited or deleted the same way.",
    name: "tourChatBodyTouch",
    desc: "Tour step about messages, on a touch screen");

String get tourVoiceTitle => Intl.message("Voice rooms",
    name: "tourVoiceTitle", desc: "Title of the tour step about voice rooms");
String get tourVoiceBody => Intl.message(
    "Rooms with a speaker icon are voice rooms. Click one to drop in; nobody gets rung. You can share your screen or turn on your camera from there.",
    name: "tourVoiceBody",
    desc: "Tour step about voice rooms, with a mouse");
String get tourVoiceBodyTouch => Intl.message(
    "Rooms with a speaker icon are voice rooms. Tap one to drop in; nobody gets rung. You can share your screen or turn on your camera from there.",
    name: "tourVoiceBodyTouch",
    desc: "Tour step about voice rooms, on a touch screen");

String get tourHomeTitle => Intl.message("Home and direct messages",
    name: "tourHomeTitle", desc: "Title of the tour step about Home");
String get tourHomeBody => Intl.message(
    "Home has your direct messages: private chats with one person or a small group. Click Home to go there.",
    name: "tourHomeBody",
    desc: "Tour step pointing at the Home button, with a mouse");
String get tourHomeBodyTouch => Intl.message(
    "Home has your direct messages: private chats with one person or a small group. Tap Home to go there.",
    name: "tourHomeBodyTouch",
    desc: "Tour step pointing at the Home button, on a touch screen");

String get tourHelpTitle => Intl.message("Help is a right-click away",
    name: "tourHelpTitle",
    desc: "Title of the last tour step, about the help menus");
String get tourHelpBody => Intl.message(
    "Not sure what something is? Right-click it and pick the question at the bottom of the menu. Try it on the spaces column. You can replay this tour in Settings › Help and guides.",
    name: "tourHelpBody",
    desc: "Last tour step, about the right-click help, with a mouse");
String get tourHelpBodyTouch => Intl.message(
    "Not sure what something is? Press and hold it (on an empty spot, with two fingers) and pick the question at the bottom of the menu. You can replay this tour in Settings › Help and guides.",
    name: "tourHelpBodyTouch",
    desc: "Last tour step, about the help menus, on a touch screen");

String get tourCardTitle => Intl.message("Take the tour",
    name: "tourCardTitle",
    desc:
        "Title of the card in Settings › Help and guides that starts the tour");
String get tourCardBody =>
    Intl.message("A one-minute tour that points at the real buttons.",
        name: "tourCardBody",
        desc: "Text of the card in Settings that starts the tour");
String get gettingStartedPagesSubtitle => Intl.message(
    "The same tips as pages with pictures",
    name: "gettingStartedPagesSubtitle",
    desc:
        "Subtitle of the Getting started pages entry in Settings, under the tour");
