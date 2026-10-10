import 'dart:math';

import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/client/matrix/matrix_peer.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/code_block.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/atoms/mention.dart';
import 'package:commet/ui/atoms/rich_text/spans/link.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:commet/utils/message_timestamps.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:intl/intl.dart' as intl;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:tiamat/config/style/theme_extensions.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class MatrixHtmlParser {
  static Widget parse(String text, MatrixClient client, Room? room,
      {bool mentionsRoom = true}) {
    return MatrixHtmlState(
      text,
      client,
      room,
      mentionsRoom: mentionsRoom,
      key: GlobalKey(),
    );
  }
}

/// Vommet: the tags rendered from a message's HTML (anything else is dropped
/// with its text), for the unit test that checks them against the spec.
const Set<String> matrixAllowedHtmlTags = _MatrixHtmlStateState.allowedHtmlTags;

class MatrixHtmlState extends StatefulWidget {
  const MatrixHtmlState(this.text, this.client, this.room,
      {this.mentionsRoom = true, super.key});
  final String text;
  final MatrixClient client;
  final Room? room;
  final bool mentionsRoom;

  @override
  State<MatrixHtmlState> createState() => _MatrixHtmlStateState();
}

class _MatrixHtmlStateState extends State<MatrixHtmlState> {
  bool hideSpoiler = true;

  static final CodeBlockHtmlExtension _codeBlock = CodeBlockHtmlExtension();
  static final CodeHtmlExtension _code = CodeHtmlExtension();
  static final LineBreakHtmlExtension _lineBreak = LineBreakHtmlExtension();
  static final ColorHtmlExtension _color = ColorHtmlExtension();
  static final TimeHtmlExtension _time = TimeHtmlExtension();
  static final RoomMentionsHtmlExtension _roomMentions =
      RoomMentionsHtmlExtension();
  static const Set<String> allowedHtmlTags = {
    'body',
    'html',
    'font', // Vommet: allowed by the spec; was dropped with its text
    'del',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'p',
    'a',
    'ul',
    'ol',
    'sup',
    'sub',
    'li',
    'b',
    'i',
    's',
    'u',
    'strong',
    'em',
    'strike',
    'code',
    'hr',
    'br',
    'div',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
    'caption',
    'pre',
    'span',
    'img',
    'details',
    'summary',
    'time',
  };

  void onTap() {
    setState(() {
      hideSpoiler = !hideSpoiler;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SpoilerHtmlExtension spoiler =
        SpoilerHtmlExtension(hideSpoiler, onTap);

    var document = html_parser.parse(widget.text);
    bool big = shouldDoBigEmoji(document);

    var theme = TextTheme.of(context);
    // Making a new one of these for every message we pass might make a lot of garbage
    var extension =
        MatrixEmoticonHtmlExtension(widget.client, widget.room, big);
    var imageExtension = MatrixImageExtension(widget.client, widget.room);
    var linkify = LinkifyHtmlExtension(widget.client, widget.room, openLink);

    var result = Html(
      data: widget.text,
      extensions: [
        _time,
        extension,
        spoiler,
        _codeBlock,
        _code,
        linkify,
        _lineBreak,
        imageExtension,
        _color,
        if (widget.mentionsRoom) _roomMentions,
      ],
      style: {
        "body": Style(
          padding: HtmlPaddings.all(0),
          margin: Margins(
            bottom: Margin.zero(),
            left: Margin.zero(),
            top: Margin.zero(),
            right: Margin.zero(),
          ),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "code": Style(backgroundColor: Colors.black.withAlpha(40)),
        "blockquote": Style(
          border: Border(
              left: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          )),
          padding: HtmlPaddings(
            left: HtmlPadding(4),
          ),
          margin: Margins(
            bottom: Margin(8),
            left: Margin(8),
            top: Margin(8),
            right: Margin.zero(),
          ),
          whiteSpace: WhiteSpace.pre,
        ),
        "h1": Style.fromTextStyle(theme.headlineLarge!).copyWith(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "h2": Style.fromTextStyle(theme.headlineMedium!).copyWith(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "h3": Style.fromTextStyle(theme.headlineSmall!).copyWith(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        "ul": Style(
          margin: Margins.all(2),
          padding: HtmlPaddings.all(2),
        ),
        "li": Style(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
        ),
        "p": Style(
          margin: Margins.all(0),
          padding: HtmlPaddings.all(0),
        )
      },
      onLinkTap: (url, attributes, element) {
        LinkUtils.open(Uri.parse(url!), context: context);
      },
      onlyRenderTheseTags: allowedHtmlTags,
    );

    return result;
  }

  void onSpoilerTapped() {
    setState(() {
      hideSpoiler = !hideSpoiler;
    });
  }

  openLink(Uri uri) {
    LinkUtils.open(uri,
        clientId: widget.client.identifier,
        context: context,
        contextRoomId: widget.room?.identifier);
  }
}

bool shouldDoBigEmoji(dom.Document document) {
  if (document.body == null) return false;

  for (var node in document.body!.nodes) {
    if (node is dom.Text) {
      for (var char in node.text.characters) {
        if (char.trim() == "") continue;

        if (TextUtils.isEmoji(char)) continue;

        return false;
      }
    } else if (node is dom.Element &&
        !node.attributes.containsKey("data-mx-emoticon")) {
      return false;
    }
  }

  return true;
}

class MatrixEmoticonHtmlExtension extends HtmlExtension {
  final MatrixClient client;
  final Room? room;
  final bool bigEmoji;
  const MatrixEmoticonHtmlExtension(this.client, this.room, this.bigEmoji);

  double get emojiSize => bigEmoji ? 48 : 20;

  @override
  InlineSpan build(ExtensionContext context) {
    Uri? uri;

    if (context.node is dom.Text) {
      var spans = List<InlineSpan>.empty(growable: true);

      for (var char in context.node.text!.characters) {
        if (char.trim() == "") {
          spans.add(TextSpan(
            text: char,
          ));
        } else {
          spans.add(WidgetSpan(
              child: EmojiWidget(
            UnicodeEmoticon(char),
            height: emojiSize,
          )));
        }
      }

      return TextSpan(children: spans);
    }

    if (context.attributes.containsKey("src")) {
      uri = Uri.parse(context.attributes["src"]!);
    }

    if (uri == null) {
      return TextSpan(text: context.attributes["alt"] ?? "");
    }

    var size = emojiSize;

    var fontSize = context.style?.fontSize?.value;
    if (fontSize != null) {
      fontSize = fontSize * 1.2;
      size = max(size, fontSize);
    }

    if (room?.shouldPreviewMedia == false) {
      return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Tooltip(
              padding: const EdgeInsets.all(0),
              decoration: const BoxDecoration(
                color: Colors.transparent,
              ),
              richMessage: WidgetSpan(
                  child: EmojiWidget(
                MatrixEmoticon(uri, client.matrixClient,
                    shortcode: context.attributes["alt"] ?? "",
                    packUsage: EmoticonUsage.all,
                    usage: EmoticonUsage.emoji),
                height: 48,
              )),
              child: tiamat.Text.labelLow(context.attributes["alt"] ?? "")));
    }

    return WidgetSpan(
        child: Tooltip(
      message: context.attributes["alt"] ?? "",
      child: EmojiWidget(
        MatrixEmoticon(uri, client.matrixClient,
            shortcode: context.attributes["alt"] ?? "",
            packUsage: EmoticonUsage.all,
            usage: EmoticonUsage.emoji),
        height: size,
      ),
    ));
  }

  @override
  bool matches(ExtensionContext context) {
    // If text contains only emojis and spaces we can handle this too
    if (context.node is dom.Text) {
      if (context.node.text == null) return false;
      if (context.node.text!.trim().isEmpty) return false;

      for (var char in context.node.text!.characters) {
        if (char.trim() == "") continue;

        if (TextUtils.isEmoji(char)) continue;

        return false;
      }

      return true;
    }

    return context.attributes.containsKey("data-mx-emoticon");
  }

  static const Set<String> tags = {"img"};

  @override
  Set<String> get supportedTags => tags;
}

class CodeBlockHtmlExtension extends HtmlExtension {
  @override
  InlineSpan build(ExtensionContext context) {
    var element = context.element!.children.firstOrNull;
    element ??= context.element;

    var langauge = element?.className.replaceAll('language-', '');
    var code = element!.text;
    return WidgetSpan(
        child: ExpandableCodeBlock(
      text: code,
      language: langauge,
    ));
  }

  static const Set<String> tags = {"pre"};

  @override
  Set<String> get supportedTags => tags;
}

class LineBreakHtmlExtension extends HtmlExtension {
  @override
  InlineSpan build(ExtensionContext context) {
    var result =
        context.parser.buildFromExtension(context, extensionsToIgnore: {this});

    if (context.node is! dom.Element) {
      return result;
    }

    return TextSpan(children: [
      if (context.element?.previousElementSibling != null)
        const TextSpan(text: "\n"),
      result,
      if (context.element?.nextElementSibling != null)
        const TextSpan(text: "\n"),
    ]);
  }

  static const Set<String> tags = {"p"};

  @override
  Set<String> get supportedTags => tags;
}

class CodeHtmlExtension extends HtmlExtension {
  @override
  InlineSpan build(ExtensionContext context) {
    var color = Theme.of(context.buildContext!)
            .extension<ExtraColors>()
            ?.codeHighlight ??
        Theme.of(context.buildContext!).primaryColor;

    return TextSpan(
        text: context.node.text,
        style: TextStyle(
            fontFamily: "Code",
            color: color,
            fontFeatures: const [FontFeature.disable("calt")]));
  }

  static const Set<String> tags = {"code"};

  @override
  Set<String> get supportedTags => tags;
}

class LinkifyHtmlExtension extends HtmlExtension {
  final Room? room;
  final MatrixClient client;
  final Function(Uri uri) openLink;
  const LinkifyHtmlExtension(this.client, this.room, this.openLink);

  @override
  InlineSpan build(ExtensionContext context) {
    if (context.node.attributes.containsKey("href")) {
      var uri = context.node.attributes["href"]!;
      late Uri href;
      try {
        href = Uri.parse(uri);
      } catch (e, _) {
        href = Uri();
      }

      if (href.host == "matrix.to") {
        var result = MatrixClient.parseMatrixLink(href);
        if (result != null) {
          var mxid = result.$2;

          Widget? overrideWidget;
          if (room != null) {
            if (result.$1 == MatrixLinkType.user) {
              var user = room!.getMemberOrFallback(mxid);
              overrideWidget = MentionWidget(
                displayName: user.displayName,
                placeholderColor: user.defaultColor,
                avatar: user.avatar,
                onTap: () => openLink(href),
              );
            }
          }

          if (result.$1 == MatrixLinkType.room ||
              result.$1 == MatrixLinkType.roomAlias) {
            var mentionedRoom = client.getRoom(mxid);
            mentionedRoom ??= client.getRoomByAlias(mxid);

            var vias = client.parseAddressToIdAndVia(uri);

            overrideWidget = MentionWidget(
              displayName: mentionedRoom?.displayName ?? mxid.substring(1),
              vias: vias?.$2,
              fallbackIcon: preferences.usePlaceholderRoomAvatars.value
                  ? null
                  : mentionedRoom?.icon ?? Icons.tag,
              placeholderColor:
                  mentionedRoom?.defaultColor ?? MatrixPeer.hashColor(mxid),
              avatar: mentionedRoom?.avatar,
              onTap: () => LinkUtils.open(href,
                  clientId: client.identifier, contextRoomId: room?.identifier),
            );
          }

          if (overrideWidget != null) {
            return WidgetSpan(
                child: Transform.translate(
                    offset: Offset(0, 2),
                    // Vommet: no gap on the left, so a pill that starts a
                    // line lines up with the text above it.
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 2, 0),
                      child: overrideWidget,
                    )));
          }
        }
      }

      late Uri destination;

      try {
        destination = Uri.parse(context.node.attributes["href"]!);
      } catch (e, _) {
        destination = Uri();
      }

      return LinkSpan.create(context.node.text!,
          clientId: client.identifier,
          context: context.buildContext!,
          destination: destination);
    }

    return TextSpan(
        children: TextUtils.linkifyString(context.node.text!,
            clientId: client.identifier, context: context.buildContext!));
  }

  @override
  bool matches(ExtensionContext context) {
    if (context.node.attributes.containsKey("href")) {
      return true;
    }

    return context.node is dom.Text &&
        TextUtils.containsUrl(context.node.text!);
  }

  @override
  Set<String> get supportedTags => {};
}

class SpoilerHtmlExtension extends HtmlExtension {
  bool hide = true;
  Function() onTap;

  SpoilerHtmlExtension(this.hide, this.onTap);

  @override
  InlineSpan build(ExtensionContext context) {
    var theme = Theme.of(context.buildContext!);
    var color = theme.colorScheme.onSurface;

    var recogniser = TapGestureRecognizer();
    recogniser.onTap = onTap;
    return TextSpan(
        text: context.node.text,
        recognizer: recogniser,
        style: TextStyle(
            color: color,
            backgroundColor: hide == true ? color : color.withAlpha(20)));
  }

  @override
  bool matches(ExtensionContext context) {
    return context.attributes.containsKey("data-mx-spoiler");
  }

  @override
  Set<String> get supportedTags => {};
}

class ColorHtmlExtension extends HtmlExtension {
  ColorHtmlExtension();

  @override
  InlineSpan build(ExtensionContext context) {
    var str = context.attributes["data-mx-color"];
    str ??= context.attributes["color"];
    return TextSpan(
        text: context.node.text, style: TextStyle(color: parseColor(str)));
  }

  /// Vommet: the spec's `#RRGGBB` only, always opaque. Anything else (a
  /// colour name, `#RGB`, or 8 digits whose alpha could hide the text) gives
  /// null, so the text keeps the normal colour rather than turning white.
  static Color? parseColor(String? value) {
    final match =
        RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value?.trim() ?? "");
    if (match == null) return null;
    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }

  @override
  bool matches(ExtensionContext context) {
    return context.attributes.containsKey("data-mx-color") ||
        context.attributes.containsKey("color");
  }

  @override
  Set<String> get supportedTags => {};
}

class RoomMentionsHtmlExtension extends HtmlExtension {
  RoomMentionsHtmlExtension();

  @override
  InlineSpan build(ExtensionContext context) {
    var data = (context.node as dom.Text).data;
    return TextSpan(
        children: TextUtils.formatMatches(
      MatrixRoom.roomMentionRegex.allMatches(data),
      data,
      builder: (matchedText, theme) {
        return WidgetSpan(
            child: Transform.translate(
                offset: Offset(0, 2),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 2, 0),
                  child: MentionWidget(
                      displayName: matchedText,
                      showAvatar: false,
                      placeholderColor:
                          ColorScheme.of(context.buildContext!).primary),
                )));
      },
    ));
  }

  @override
  bool matches(ExtensionContext context) {
    if (context.node case dom.Text text) {
      return MatrixRoom.roomMentionRegex.hasMatch(text.data);
    }

    return false;
  }

  @override
  Set<String> get supportedTags => {};
}

class MatrixImageExtension extends HtmlExtension {
  final double defaultDimension;

  final MatrixClient client;
  final Room? room;
  const MatrixImageExtension(this.client, this.room,
      {this.defaultDimension = 64});

  @override
  Set<String> get supportedTags => {'img'};

  @override
  InlineSpan build(ExtensionContext context) {
    final mxcUrl = Uri.tryParse(context.attributes['src'] ?? '');

    if (mxcUrl == null) {
      return TextSpan(text: context.attributes['alt']);
    }

    if (mxcUrl.scheme != 'mxc' || room?.shouldPreviewMedia == false) {
      return LinkSpan.create(mxcUrl.toString(),
          clientId: client.identifier,
          destination: mxcUrl,
          context: context.buildContext!);
    }

    final width = double.tryParse(context.attributes['width'] ?? '');
    final height = double.tryParse(context.attributes['height'] ?? '');

    return WidgetSpan(
      child: SizedBox(
          width: width ?? height ?? defaultDimension,
          height: height ?? width ?? defaultDimension,
          child: Image(
            image: MatrixMxcImage(
              mxcUrl,
              client.matrixClient,
            ),
          )),
    );
  }
}

/// MSC3160 `<time datetime="…">`: shown in the reader's time zone, with the
/// sender's time and text in a tooltip. Without the experiment (or with an
/// unusable `datetime`) the sender's text is shown as written.
class TimeHtmlExtension extends HtmlExtension {
  static const Set<String> tags = {"time"};

  @override
  Set<String> get supportedTags => tags;

  @override
  InlineSpan build(ExtensionContext context) {
    final written = context.node.text ?? "";
    final datetime = context.attributes["datetime"];
    final time = MessageTimestamps.parseDatetime(datetime);
    if (time == null || !preferences.experimentMessageTimestamps.value) {
      return TextSpan(text: written);
    }

    final buildContext = context.buildContext!;
    final use24 = MediaQuery.of(buildContext).alwaysUse24HourFormat;
    final local = time.toLocal();
    String format(DateTime t, {bool weekday = false}) {
      final date =
          weekday ? intl.DateFormat.yMMMMEEEEd() : intl.DateFormat.yMMMd();
      return (use24 ? date.add_Hm() : date.add_jm()).format(t);
    }

    final lines = [
      "${format(local, weekday: true)} (your time)",
      MessageTimestamps.relative(time, DateTime.now()),
    ];
    final offset = MessageTimestamps.senderOffset(datetime);
    if (offset != null && offset != local.timeZoneOffset) {
      lines.add("${format(time.add(offset), weekday: true)} "
          "(UTC${MessageTimestamps.formatOffset(offset)}, sender's time)");
    }
    if (written.trim().isNotEmpty) lines.add("Written as: $written");

    final color = Theme.of(buildContext).colorScheme.onSurface;
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Tooltip(
        message: lines.join("\n"),
        triggerMode: TooltipTriggerMode.tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(format(local), style: context.style?.generateTextStyle()),
        ),
      ),
    );
  }
}
