import 'package:commet/client/components/profile/profile_component.dart';
import 'package:flutter/material.dart';

class ErrorProfile implements Profile {
  ErrorProfile({String? reason}) : reason = _shorten(reason);

  /// Why the account failed to load, shown on its row in Manage Accounts
  /// (Vommet issue 321). Cut short: exception text can run to many lines
  final String? reason;

  static const int maxReasonLength = 160;

  static String? _shorten(String? reason) {
    if (reason == null) return null;
    var text = reason.replaceAll(RegExp(r"\s+"), " ").trim();
    if (text.isEmpty) return null;
    if (text.length > maxReasonLength) {
      text = "${text.substring(0, maxReasonLength - 1)}…";
    }
    return text;
  }

  @override
  ImageProvider<Object>? get avatar => null;

  @override
  Color get defaultColor => Colors.red;

  @override
  String? get detail => null;

  @override
  String get displayName => "Error";

  @override
  String get identifier => "Error";

  @override
  String get userName => "Error";

  @override
  ImageProvider<Object>? get banner => null;

  @override
  String get source => "";
}
