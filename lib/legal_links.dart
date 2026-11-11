import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared legal destinations and external-browser behavior for app screens.
class LegalLinks {
  static const privacyPolicyUrl =
      'https://aimlessoulapps.github.io/chessunlock-legal/';
  static const termsOfUseUrl =
      'https://aimlessoulapps.github.io/chessunlock-legal/terms.html';

  static Future<void> openPrivacyPolicy(BuildContext context) =>
      _open(context, privacyPolicyUrl, 'Couldn’t open Privacy Policy.');

  static Future<void> openTermsOfUse(BuildContext context) =>
      _open(context, termsOfUseUrl, "Couldn't open Terms of Use.");

  static Future<void> _open(
      BuildContext context, String url, String failureMessage) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}
