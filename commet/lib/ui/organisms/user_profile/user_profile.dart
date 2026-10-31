import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/timezone_picker.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_color/user_color_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/code_block.dart';
import 'package:commet/ui/atoms/inherited_offstage.dart';
import 'package:commet/ui/molecules/bundled_preview_trust_row.dart';
import 'package:commet/ui/molecules/dm_trust_banner.dart';
import 'package:commet/ui/molecules/image_select_dialog.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/profile/mutual_rooms_section.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/ui/organisms/share_history/share_history.dart';
import 'package:commet/ui/organisms/user_profile/user_profile_view.dart';
import 'package:commet/ui/organisms/user_profile/profile_contact_button.dart';
import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:commet/utils/timezone_utils.dart';
import 'package:commet/client/components/petname/petname_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/profile_open_telemetry.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UserProfile extends StatefulWidget {
  const UserProfile(
      {super.key,
      required this.userId,
      this.width = 700,
      this.bannerHeight = 230.0,
      required this.client,
      this.maxBioHeight = 200,
      this.doSafeArea = true,
      this.showMessageButton = true,
      this.showContactButton,
      this.room,
      this.dismiss});
  final Client client;
  final String userId;
  final double bannerHeight;
  final double width;
  final double maxBioHeight;
  final Function? dismiss;
  final bool doSafeArea;
  final bool showMessageButton;

  /// Vommet: the Add contact / Contact button; defaults to
  /// [showMessageButton]. The DM panel's Profile tab shows it without Message.
  final bool? showContactButton;

  /// Vommet issue 744: the room the card was opened from, for "Share
  /// history…".
  final Room? room;

  @override
  State<UserProfile> createState() => _UserProfileState();

  static Future<T?> show<T extends Object?>(
    BuildContext context, {
    required Client client,
    required String userId,
    bool scrollable = true,
    bool dismissible = true,
    double padding = 8.0,
    double initialHeightMobile = 0.5,
    Room? room,
  }) async {
    if (MediaQuery.of(context).desktop)
      return showGeneralDialog(
          context: context,
          pageBuilder: (context, animation, secondaryAnimation) {
            return Theme(
              data: Theme.of(context),
              child: Center(
                  child:
                      UserProfile(userId: userId, client: client, room: room)),
            );
          },
          barrierLabel: "USER_PROFILE_BARRIER",
          barrierDismissible: dismissible,
          transitionDuration: const Duration(milliseconds: 300),
          transitionBuilder: (context, animation, secondaryAnimation, child) =>
              SlideTransition(
                position:
                    Tween(begin: const Offset(0, 1), end: const Offset(0, 0))
                        .animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              ));

    return showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      useSafeArea: false,
      builder: (context) {
        return UserProfile(
          userId: userId,
          client: client,
          room: room,
          width: double.infinity,
        );
      },
    );
  }
}

class _UserProfileState extends State<UserProfile> {
  Profile? profile;
  ThemeData? theme;

  late UserProfileComponent component;

  ImageProvider? banner;
  String? displayName;
  ImageProvider? avatar;
  UserPresence? presence;
  String? timezone;
  String? bioText;
  List<String> pronouns = const [];
  List<ProfileBadge> badges = [];

  /// Vommet: opt-in timings of this card (`profile_open`).
  late final ProfileOpenRecord _timings;

  /// What the current colors were worked out from, so a refreshed profile
  /// with the same pictures keeps them.
  String? _colorKey;

  @override
  void initState() {
    super.initState();
    component = widget.client.getComponent<UserProfileComponent>()!;
    _timings = ProfileOpenRecord(
        ownServer: _domain(widget.userId) ==
            _domain(widget.client.self?.identifier ?? ""));
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here rather than in initState: working out the colors reads
    // the theme.
    if (_started) return;
    _started = true;
    _load();
  }

  void _load() {
    // Vommet: show what is already known at once (an earlier lookup, or the
    // member event of a room we share), then fill in the server's answer.
    // The card used to wait for the lookup, the colors from the full-size
    // banner and every picture before showing anything: 5-15 s for someone
    // on another server.
    final cached = component.cachedProfile(widget.userId);
    if (cached != null) {
      _timings.cached = true;
      stateFromProfile(cached);
    }

    final loadTimings = ProfileLoadTimings();
    final fetchStart = _timings.now();
    component
        .getProfile(widget.userId, forceRefresh: true, timings: loadTimings)
        .then((value) async {
      _timings
        ..fetchMs = _timings.now() - fetchStart
        ..profileMs = loadTimings.profileMs
        ..presenceMs = loadTimings.presenceMs
        ..fetchError = loadTimings.error
        ..fetchDone = true;
      await stateFromProfile(value);
      _timings.finishIfSettled();
    });
  }

  @override
  void dispose() {
    _timings.close();
    for (final (stream, listener) in _listeners) {
      stream.removeListener(listener);
    }
    super.dispose();
  }

  static String _domain(String userId) {
    final i = userId.indexOf(":");
    return i < 0 ? "" : userId.substring(i + 1);
  }

  /// Vommet: colors worked out from a picture, kept for this run so opening
  /// the same profile again shows its colors at once.
  static final Map<String, ColorScheme> _schemes = {};

  /// Bumped by each [stateFromProfile], so an older call that finishes
  /// later (the cached profile's colors) doesn't overwrite a newer one.
  int _generation = 0;

  Future<void> stateFromProfile(Profile? value) async {
    if (value == null || !mounted) return;
    final generation = ++_generation;

    final newBanner = _progressive(value.banner, scaled: true);
    final newAvatar = _progressive(value.avatar, scaled: false);

    // Keep the providers already showing when the pictures didn't change,
    // so a refresh doesn't start them over.
    if (newBanner == null || newBanner != banner) banner = newBanner;
    if (newAvatar == null || newAvatar != avatar) avatar = newAvatar;

    _timings
      ..hasBanner = banner != null
      ..hasAvatar = avatar != null;
    _watchImage(banner, isBanner: true);
    _watchImage(avatar, isBanner: false);

    if (value case ProfileWithBadges p) {
      p.getBadges().then((value) {
        if (mounted) setState(() => badges = value);
      });
    }

    final brightness = _brightness(value);
    final colorSource = value is ProfileWithColorScheme &&
            (value as ProfileWithColorScheme).color != null &&
            (value as ProfileWithColorScheme).brightness != null
        ? null
        : (banner ?? avatar);
    final colorKey = _keyFor(value, colorSource, brightness);

    ColorScheme? scheme;
    if (colorKey == _colorKey && theme != null) {
      scheme = theme!.colorScheme;
    } else {
      final colorStart = _timings.now();
      final pending = _scheme(value, colorSource, brightness, colorKey);
      if (profile == null) {
        // Not showing yet: give the colors a moment, so the card doesn't
        // change color right after it appears.
        scheme = await pending.timeout(const Duration(milliseconds: 350),
            onTimeout: () => null);
      } else {
        scheme = await pending;
      }
      if (!mounted) return;
      if (scheme != null) {
        _colorKey = colorKey;
        _timings.colorMs ??= _timings.now() - colorStart;
        _timings.colorDone = true;
      } else {
        pending.then((late) {
          _timings
            ..colorMs ??= _timings.now() - colorStart
            ..colorLate = true
            ..colorDone = true;
          _timings.finishIfSettled();
          if (!mounted || late == null) return;
          // A newer profile already picked its own colors.
          if (generation != _generation && _colorKey != null) return;
          _colorKey = colorKey;
          setState(() {
            theme = Theme.of(context).copyWith(colorScheme: late);
          });
        });
      }
    }

    if (!mounted || generation != _generation) return;

    scheme ??= theme?.colorScheme ??
        ColorScheme.fromSeed(
            seedColor: value.defaultColor,
            brightness: brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);

    String? newTimezone;
    if (value case ProfileWithTimezone p) newTimezone = p.timezone;
    _timings.hasTimezone = newTimezone != null;

    setState(() {
      theme = Theme.of(context).copyWith(colorScheme: scheme);
      profile = value;
      displayName = value.displayName;

      if (value case ProfileWithPronouns p) {
        pronouns = p.pronouns;
      }

      if (value case ProfileWithPresence p) {
        // A cached presence is better than none while the lookup runs.
        presence = p.precence ?? presence;
      }

      // The timezone database is loaded on first use (a few hundred ms on a
      // phone), after the card is showing.
      if (newTimezone == null || TimezoneUtils.instance.isInit) {
        timezone = newTimezone;
      }
    });
    _timings.shownMs ??= _timings.now();

    if (newTimezone != null && !TimezoneUtils.instance.isInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final start = _timings.now();
        await TimezoneUtils.instance.init();
        _timings.timezoneInitMs ??= _timings.now() - start;
        if (mounted) setState(() => timezone = newTimezone);
      });
    }
  }

  Brightness _brightness(Profile value) {
    if (value case ProfileWithColorScheme p) {
      if (p.brightness != null) return p.brightness!;
    }
    return Theme.of(context).colorScheme.brightness;
  }

  String _keyFor(
      Profile value, ImageProvider? colorSource, Brightness brightness) {
    if (colorSource == null) {
      if (value case ProfileWithColorScheme p) {
        if (p.color != null) return "color:${p.color!.toARGB32()}:$brightness";
      }
      return "seed:${value.defaultColor.toARGB32()}:$brightness";
    }
    final id = colorSource is MatrixMxcImage
        ? colorSource.identifier.toString()
        : identityHashCode(colorSource).toString();
    return "image:$id:$brightness";
  }

  Future<ColorScheme?> _scheme(Profile value, ImageProvider? colorSource,
      Brightness brightness, String key) async {
    if (colorSource == null) {
      if (value case ProfileWithColorScheme p) {
        if (p.color != null) {
          _timings.colorSource ??= "profile";
          return ColorScheme.fromSeed(
              seedColor: p.color!,
              brightness: brightness,
              dynamicSchemeVariant: DynamicSchemeVariant.content);
        }
      }
      _timings.colorSource ??= "default";
      return ColorScheme.fromSeed(
          seedColor: value.defaultColor,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);
    }

    final known = _schemes[key];
    if (known != null) {
      _timings.colorSource ??= "memory";
      return known;
    }

    try {
      // The banner's first picture (its small server thumbnail, or the full
      // one if it's on the device already) is plenty for picking colors;
      // upstream waited for the full-size original.
      final scheme = await ColorScheme.fromImageProvider(
          provider: colorSource,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);
      _timings.colorSource ??= colorSource == banner ? "banner" : "avatar";
      if (_schemes.length > 200) _schemes.remove(_schemes.keys.first);
      _schemes[key] = scheme;
      return scheme;
    } catch (e, s) {
      // Flutter gives up after 5 s without a picture; upstream let that
      // error escape and the card kept spinning.
      Log.onError(e, s, content: "Couldn't pick profile colors from a picture");
      _timings.colorSource ??= "default";
      return ColorScheme.fromSeed(
          seedColor: value.defaultColor,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot);
    }
  }

  /// Vommet: the card shows a picture's small server thumbnail first and
  /// swaps in the full one when it arrives, instead of waiting for the full
  /// one before showing anything.
  ImageProvider? _progressive(ImageProvider? image, {required bool scaled}) {
    if (image case MatrixMxcImage mxc) {
      return MatrixMxcImage(mxc.identifier, mxc.client,
          scaledThumbnail: scaled || mxc.scaledThumbnail,
          thumbnailHeight: mxc.thumbnailHeight,
          doThumbnail: true,
          doFullres: true,
          autoLoadFullRes: true);
    }
    return image;
  }

  final Set<ImageProvider> _watched = {};
  final List<(ImageStream, ImageStreamListener)> _listeners = [];

  /// Times the first picture and the full one for `profile_open`.
  void _watchImage(ImageProvider? image, {required bool isBanner}) {
    if (image == null || !_watched.add(image)) return;
    final stream = image.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      final ms = _timings.now();
      final full = stream.completer is! LODImageCompleter ||
          (stream.completer as LODImageCompleter).currentlyLoadedImage ==
              LODImageType.fullres;
      if (isBanner) {
        _timings.bannerMs ??= ms;
        if (full) _timings.bannerFullMs ??= ms;
      } else {
        _timings.avatarMs ??= ms;
        if (full) _timings.avatarFullMs ??= ms;
      }
      if (full) stream.removeListener(listener);
      _timings.finishIfSettled();
    }, onError: (_, __) {
      if (isBanner) {
        _timings.bannerFailed = true;
      } else {
        _timings.avatarFailed = true;
      }
      stream.removeListener(listener);
      _timings.finishIfSettled();
    });
    stream.addListener(listener);
    _listeners.add((stream, listener));
  }

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return SizedBox(
          height: 300, child: const Center(child: CircularProgressIndicator()));
    }

    Widget? bio;

    if (profile case ProfileWithBio p) {
      if (p.hasBio || bioText != null) {
        bio = p.buildBio(context, theme!, overrideText: bioText);
      }
    }

    if (InheritedOffstage.isOffstage(context)) {
      return Placeholder();
    }

    final room = widget.room;
    final shareHistoryRoom =
        room is MatrixRoom && ShareHistory.canShare(room, profile!.identifier)
            ? room
            : null;

    // Vommet: colors that arrive after the card shows fade in.
    var result = AnimatedTheme(
      data: theme!,
      child: UserProfileView(
        userAvatar: avatar,
        displayName: displayName!,
        identifier: profile!.identifier,
        clientId: widget.client.identifier,
        userColor: profile!.defaultColor,
        userBanner: banner,
        presence: presence,
        timezone: timezone,
        bannerHeight: widget.bannerHeight,
        width: widget.width,
        doSafeArea: widget.doSafeArea,
        maxBioHeight: widget.maxBioHeight,
        showMessageButton: widget.showMessageButton,
        isSelf: widget.client.self!.identifier == profile!.identifier,
        onMessageButtonClicked: openDirectMessage,
        onSetBanner: setBanner,
        setPreviewColor: setPreviewColor,
        setPreviewBrightness: setPreviewBrightness,
        removeTimezone: removeTimezone,
        onChangeName: changeName,
        savePreviewTheme: savePreviewTheme,
        setBio: setBio,
        clearBio: clearBio,
        badges: badges,
        editBadges: editBadges,
        bio: bio,
        mutual: widget.client.self!.identifier == profile!.identifier
            ? null
            : MutualRoomsSection(
                client: widget.client,
                userId: profile!.identifier,
                onOpenRoom: (room) {
                  EventBus.doOpenRoom(room.identifier,
                      clientId: widget.client.identifier);
                  Navigator.of(context).pop();
                },
                onOpenSpace: (space) {
                  EventBus.openSpace
                      .add((space.identifier, widget.client.identifier));
                  Navigator.of(context).pop();
                },
              ),
        contactButton: contactButton(),
        linkPreviews: widget.client.self!.identifier == profile!.identifier
            ? null
            : BundledPreviewTrustRow(
                client: widget.client,
                userId: profile!.identifier,
                name: displayName ?? profile!.identifier,
              ),
        setPetName: setPetName,
        currentPetName: widget.client
            .getComponent<PetNameComponent>()
            ?.getPetName(widget.userId),
        hasPetName: widget.client
                .getComponent<PetNameComponent>()
                ?.getPetName(widget.userId) !=
            null,
        onSetAvatar: setAvatar,
        setColorOverride: setColorOverride,
        showSource: showSource,
        onSetStatus: setStatus,
        clearStatus: clearStatus,
        shareCurrentTimezone: shareTimezone,
        pronouns: pronouns,
        isBlocked: blocking?.isBlocked(widget.userId) ?? false,
        onBlock: blocking == null ? null : block,
        onUnblock: blocking == null ? null : unblock,
        onShareHistory: shareHistoryRoom == null
            ? null
            : () => ShareHistory.show(
                context, shareHistoryRoom, profile!.identifier),
        hasColorOverride: widget.client
                .getComponent<UserColorComponent>()
                ?.getColor(profile!.identifier) !=
            null,
      ),
    );

    return result;
  }

  /// Vommet: Add contact under Message in the popup and sheet, and on the DM
  /// panel's Profile tab.
  Widget? contactButton() {
    final friends = widget.client.getComponent<FriendsComponent>();
    final show = widget.showContactButton ?? widget.showMessageButton;
    if (friends == null || !show) return null;
    return ProfileContactButton(
        friends: friends,
        userId: profile!.identifier,
        displayName: displayName ?? profile!.identifier);
  }

  Future<void> openDirectMessage() async {
    final component = widget.client.getComponent<DirectMessagesComponent>();
    if (component == null) {
      return;
    }

    var existingRooms = component.directMessageRooms.where((element) =>
        profile!.identifier == component.getDirectMessagePartnerId(element));

    if (existingRooms.isNotEmpty == true) {
      EventBus.doOpenRoom(existingRooms.first.identifier,
          clientId: widget.client.identifier);
    } else {
      // Vommet: warn first if they never set up secure messaging.
      if (!await DmTrustBanner.confirmNewDirectMessage(context, widget.client,
          profile!.identifier, displayName ?? profile!.identifier)) {
        return;
      }
      if (!mounted) return;
      var room = await component.createDirectMessage(profile!.identifier);
      if (room != null) {
        EventBus.doOpenRoom(room.identifier,
            clientId: widget.client.identifier);
      }
    }

    // Vommet: `true` tells the caller a room was opened, so dialogs under the
    // profile (e.g. Read Receipts) can close too (Vommet issue 424).
    Navigator.of(context).pop(true);
  }

  Future<void> setBanner() async {
    final action = await ImageSelectDialog.show(
      context,
      image: banner,
    );

    if (!mounted) return;

    if (action == ImageEditAction.remove) {
      await removeBanner();
      return;
    }

    if (action != ImageEditAction.pick) return;

    var result =
        await PickerUtils.pickImageAndCrop(context, aspectRatio: 700 / 230);
    if (result == null) return;

    setState(() {
      banner = Image.memory(result).image;
    });

    await component.setBanner(result);
  }

  Future<void> removeBanner() async {
    await component.removeBanner();

    setState(() {
      banner = null;
    });
  }

  Color previewColor = Colors.blue;
  Brightness previewBrightness = Brightness.dark;

  void setPreviewColor(Color color) {
    setState(() {
      previewColor = color;
      updatePreviewTheme();
    });
  }

  void updatePreviewTheme() {
    theme = Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(
          seedColor: previewColor,
          brightness: previewBrightness,
          dynamicSchemeVariant: DynamicSchemeVariant.content),
    );
  }

  Future<void> savePreviewTheme() async {
    await component.setProfileColorScheme(previewColor, previewBrightness);
  }

  Future<void> setPreviewBrightness(Brightness p1) async {
    setState(() {
      previewBrightness = p1;
      updatePreviewTheme();
    });
  }

  Future<void> setColorOverride(Color? color) async {
    var comp = widget.client.getComponent<UserColorComponent>();
    await comp?.setColor(widget.userId, color);
  }

  Future<void> changeName() async {
    var text = await AdaptiveDialog.textPrompt(
      context,
      initialText: displayName,
      title: profileChangeDisplayNameTitle,
    );
    if (text?.trim().isNotEmpty == true) {
      setState(() {
        displayName = text!.trim();

        widget.client.setDisplayName(text.trim());
      });
    }
  }

  // Vommet: blocking is an experiment.
  UserBlockingComponent? get blocking => preferences.experimentBlockUsers.value
      ? widget.client.getComponent<UserBlockingComponent>()
      : null;

  Future<void> block() async {
    final name = displayName ?? widget.userId;
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: profileBlockUserTitle(name),
        prompt: profileBlockUserPrompt,
        confirmationText: profileBlockUserConfirm,
        cancelText: profileBlockCancel,
        dangerous: true);
    if (confirmed != true) return;
    await _changeBlock(() => blocking!.block(widget.userId));
  }

  Future<void> unblock() async {
    final name = displayName ?? widget.userId;
    final confirmed = await AdaptiveDialog.confirmation(context,
        title: profileUnblockUserTitle(name),
        prompt: profileUnblockUserPrompt,
        confirmationText: profileUnblockUserConfirm,
        cancelText: profileBlockCancel);
    if (confirmed != true) return;
    await _changeBlock(() => blocking!.unblock(widget.userId));
  }

  Future<void> _changeBlock(Future<void> Function() change) async {
    try {
      await change();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change the block list");
      if (mounted) {
        AdaptiveDialog.show(context,
            title: profileBlockFailedTitle,
            builder: (_) => tiamat.Text.label(profileBlockFailedDetail));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> setPetName(String? name) async {
    var comp = widget.client.getComponent<PetNameComponent>();
    await comp?.setPetName(widget.userId, name);
    setState(() {}); // refresh so the view shows the new name
  }

  Future<void> setAvatar() async {
    var result = await PickerUtils.pickImageAndCrop(context, aspectRatio: 1.0);
    if (result == null) return;

    setState(() {
      avatar = Image.memory(result).image;
    });

    await widget.client.setAvatar(result, "");
  }

  Future<void> setStatus() async {
    var text = await AdaptiveDialog.textPrompt(
      context,
      initialText: presence?.message?.message,
      title: UserProfileViewState.promptProfileSetStatus,
    );
    if (text != null) {
      var client = widget.client;
      client.getComponent<UserProfileComponent>()?.setStatus(text);
      client
          .getComponent<UserPresenceComponent>()
          ?.setStatus(UserPresenceStatus.online, message: text);

      setState(() {
        presence = UserPresence(UserPresenceStatus.online,
            message: UserPresenceMessage(text, PresenceMessageType.userCustom));
      });
    }
  }

  Future<void> clearStatus() async {
    var client = widget.client;
    await client.getComponent<UserProfileComponent>()?.setStatus(null);

    await client.getComponent<UserPresenceComponent>()?.setStatus(
        UserPresenceStatus.online,
        message: null,
        clearMessage: true);

    setState(() {
      presence = UserPresence(UserPresenceStatus.online);
    });
  }

  void showSource() {
    AdaptiveDialog.show(
      context,
      title: "Source",
      builder: (context) {
        return SizedBox(
          width: 1000,
          child: SelectionArea(
            child: ExpandableCodeBlock(
                expanded: true, text: profile!.source, language: "json"),
          ),
        );
      },
    );
  }

  String labelConfirmShareTimezone(String timezone) => Intl.message(
      "Are you sure you want to share your timezone '$timezone' publicly?",
      name: "labelConfirmShareTimezone",
      args: [timezone],
      desc:
          "Ask the user to confirm that they want to share their current timezone as public information on their profile");

  // Vommet: pick any timezone (the device's one is a single tap), instead of
  // always sharing the device's zone after a yes/no prompt.
  Future<void> shareTimezone() async {
    final currentTimeZone = await FlutterTimezone.getLocalTimezone();
    if (!mounted) return;
    final picked = await TimezonePicker.show(context,
        deviceTimezone: currentTimeZone.identifier, current: timezone);
    if (picked == null || !mounted) return;

    setState(() {
      timezone = picked;
    });

    return widget.client
        .getComponent<UserProfileComponent>()
        ?.setTimezone(picked);
  }

  Future<void> removeTimezone() async {
    await widget.client.getComponent<UserProfileComponent>()?.removeTimezone();

    setState(() {
      timezone = null;
    });
  }

  String get promptProfileWriteBioHint => Intl.message("Write about yourself",
      name: "promptProfileWriteBioHint",
      desc: "Hint text for the profile bio editor");

  Future<void> setBio() async {
    AdaptiveDialog.show(context, builder: (context) {
      String? plaintext;

      if (profile case ProfileWithBio p) {
        plaintext = p.plaintextBio;
      }

      return SizedBox(
        width: 600,
        child: MessageInput(
          hintText: promptProfileWriteBioHint,
          initialText: bioText ?? plaintext,
          showAttachmentButton: false,
          client: widget.client,
          showGifSearch: false,
          disableEnterToSend: true,
          compact: true,
          enableKeyboardAdapter: false,
          availibleEmoticons:
              widget.client.getComponent<EmoticonComponent>()?.availablePacks,
          onSendMessage: (message, {overrideClient}) {
            widget.client.getComponent<UserProfileComponent>()?.setBio(message);

            setState(() {
              bioText = message;
            });

            Navigator.of(context).pop();

            return MessageInputSendResult.success;
          },
        ),
      );
    });
  }

  Future<void> clearBio() async {
    if (await AdaptiveDialog.confirmation(context) == true) {
      setState(() {
        bioText = null;
      });

      await widget.client.getComponent<UserProfileComponent>()?.removeBio();

      component.getProfile(widget.userId).then(stateFromProfile);
    }
  }

  String get labelProfileYourBadges => Intl.message("Your Badges",
      name: "labelProfileYourBadges",
      desc:
          "label for the ui to select which badges to display on the users profile");

  String get labelProfileNoBadgesVommet => Intl.message(
      "You don't have any badges.",
      // Vommet: new name, so the translated "donate to Commet" text is unused.
      name: "labelProfileNoBadgesVommet",
      desc: "text that is shown when the user has no badges");

  Future<void> editBadges() async {
    var availableBadges = await component.getAvailableBadges();

    if (availableBadges.isEmpty) {
      AdaptiveDialog.show(context,
          builder: (context) => SizedBox(
                height: 200,
                child: Center(
                  child: Container(
                    child: tiamat.Text.labelLow(labelProfileNoBadgesVommet),
                  ),
                ),
              ),
          title: labelProfileYourBadges);
      return;
    }

    var selectedBadges = await AdaptiveDialog.pickMultiple<ProfileBadge>(
      context,
      selected: badges,
      items: availableBadges,
      title: labelProfileYourBadges,
      itemBuilder: (context, item) {
        return Row(
          spacing: 8,
          children: [
            SizedBox(width: 30, height: 30, child: Image(image: item.image)),
            tiamat.Text.labelLow(item.body),
          ],
        );
      },
    );

    if (selectedBadges != null) {
      component.setProfileBadges(selectedBadges);
      setState(() {
        badges = selectedBadges;
      });
    }

    print("Selected badges $selectedBadges");
  }
}

String get profileChangeDisplayNameTitle => Intl.message("Change display name",
    name: "profileChangeDisplayNameTitle",
    desc:
        "Title of the dialog for changing your display name from your profile");

String profileBlockUserTitle(String name) => Intl.message("Block $name?",
    args: [name],
    name: "profileBlockUserTitle",
    desc:
        "Title of the block-user confirmation; name is their display name or user ID");

String get profileBlockUserPrompt => Intl.message(
    "You won't see their messages, invites, or calls, on any of your devices. They aren't told, and they can still see what you send in rooms you share.",
    name: "profileBlockUserPrompt",
    desc: "Body of the block-user confirmation");

String get profileBlockUserConfirm => Intl.message("Block",
    name: "profileBlockUserConfirm",
    desc: "Confirm button of the block-user dialog");

String get profileBlockCancel => Intl.message("Cancel",
    name: "profileBlockCancel",
    desc: "Cancel button of the block/unblock user dialogs");

String profileUnblockUserTitle(String name) => Intl.message("Unblock $name?",
    args: [name],
    name: "profileUnblockUserTitle",
    desc:
        "Title of the unblock-user confirmation; name is their display name or user ID");

String get profileUnblockUserPrompt => Intl.message(
    "Their messages, invites, and calls show again. Messages they sent while blocked stay hidden.",
    name: "profileUnblockUserPrompt",
    desc: "Body of the unblock-user confirmation");

String get profileUnblockUserConfirm => Intl.message("Unblock",
    name: "profileUnblockUserConfirm",
    desc: "Confirm button of the unblock-user dialog");

String get profileBlockFailedTitle =>
    Intl.message("Couldn't update your block list",
        name: "profileBlockFailedTitle",
        desc: "Title of the error dialog when blocking or unblocking failed");

String get profileBlockFailedDetail =>
    Intl.message("Your server didn't accept the change. Try again.",
        name: "profileBlockFailedDetail",
        desc: "Body of the error dialog when blocking or unblocking failed");
