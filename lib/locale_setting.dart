import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';

/// Which language the interface is in, and where that choice is kept.
///
/// The default is the phone's own language, which is the right default for
/// this appliance rather than a shortcut: the renderer is usually a box on a
/// shelf, and the phone reading it may not be the phone that set it up. A
/// guest who picks it up should find their own language without anyone having
/// configured anything.
///
/// The override exists for the opposite case, and it is a real one. A renderer
/// set up on a spare phone inherits whatever language that phone happens to be
/// in — often not the owner's — and changing the whole phone to fix one app is
/// a poor trade. So the choice is: follow the phone, or name a language.
///
/// The choice is stored on the Android side rather than in Dart, because the
/// service outlives the UI and the widget has to be able to read it with no
/// Flutter engine running.
class LocaleSetting extends ChangeNotifier {
  LocaleSetting._();

  static final LocaleSetting instance = LocaleSetting._();

  static const _channel = MethodChannel('com.hifirend/renderer');

  /// Null means follow the phone. Anything else overrides it.
  Locale? get locale => _locale;
  Locale? _locale;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Every language the interface exists in, in the order the picker shows
  /// them. The generated list is the source of truth for which are real.
  static List<Locale> get supported => AppLocalizations.supportedLocales;

  /// What to call each language *in that language*, which is the only naming
  /// that works in a picker: someone looking for their own language recognises
  /// it written their way, not translated into the one they cannot read.
  static String nameOf(Locale locale) {
    switch (locale.toString()) {
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'it':
        return 'Italiano';
      case 'de':
        return 'Deutsch';
      case 'zh':
        return '简体中文';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'pt_BR':
        return 'Português (Brasil)';
      // European Portuguese is the bare `pt`, which is both what gen-l10n
      // wants as the fallback behind pt_BR and what Android means by `pt`.
      // Labelled by country anyway, because next to "Português (Brasil)" an
      // unqualified "Português" reads as a third, vaguer option.
      case 'pt':
        return 'Português (Portugal)';
      default:
        return locale.toLanguageTag();
    }
  }

  Future<void> load() async {
    try {
      final tag = await _channel.invokeMethod<String>('getLanguage');
      _locale = parseTag(tag);
    } catch (_) {
      // A renderer that cannot read the setting still has to start, in the
      // phone's language, which is where it would have been anyway.
      _locale = null;
    }
    _loaded = true;
    notifyListeners();
  }

  /// [locale] null restores "follow the phone".
  Future<void> set(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    try {
      await _channel.invokeMethod('setLanguage', {
        'tag': locale == null ? '' : _tag(locale),
      });
    } catch (_) {
      // The screen already shows the new language; failing to persist it means
      // it reverts next launch, which is far better than refusing the change.
    }
  }

  /// `pt_BR` and `pt-BR` both mean the same thing; senders of this string are
  /// this app and Android, and they do not agree on the separator.
  ///
  /// Public because the interesting part is what it refuses, and that is worth
  /// testing without a platform channel.
  static Locale? parseTag(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    final parts = tag.replaceAll('-', '_').split('_');
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final parsed = parts.length > 1 && parts[1].isNotEmpty
        ? Locale(parts[0], parts[1])
        : Locale(parts[0]);
    // Only ever return a language actually shipped. A stored tag can outlive
    // the translation it names — a locale dropped in a later version would
    // otherwise leave the app in a language that no longer exists.
    return supported.any((l) => l.toString() == parsed.toString())
        ? parsed
        : null;
  }

  static String _tag(Locale locale) => locale.countryCode == null
      ? locale.languageCode
      : '${locale.languageCode}_${locale.countryCode}';
}
