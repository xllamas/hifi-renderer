import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Adds the native third-party licences to the registry Flutter shows.
///
/// Flutter populates [LicenseRegistry] from the pub packages it resolved, which
/// means it sees the Dart side and nothing else. Everything that makes this app
/// what it is -- libusb, the ALAC decoder, dr_libs, minimp3 -- arrives through
/// CMake and a vendored `third_party` tree, so none of it is registered and the
/// licence page would silently under-report what is being distributed. LGPL,
/// Apache and CDDL all require attribution in the binary, so that omission is a
/// compliance gap rather than a cosmetic one.
///
/// The texts are loaded from the real files rather than copied into string
/// constants, so the page cannot drift away from the licences actually in the
/// tree. The asset list in `pubspec.yaml` is what carries them into the bundle.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['HiFi Renderer'],
      await rootBundle.loadString('LICENSE'),
    );

    // The attribution list itself. It is the only place dr_libs and minimp3
    // appear: their licence text lives at the end of the header files rather
    // than in a file of its own, so extracting it at build time would be a
    // parser that breaks the next time either is updated.
    yield LicenseEntryWithLineBreaks(
      const ['HiFi Renderer', 'Third-party notices'],
      await rootBundle.loadString('NOTICE'),
    );

    yield LicenseEntryWithLineBreaks(
      const ['libusb'],
      await rootBundle
          .loadString('android/app/src/main/cpp/third_party/libusb/COPYING'),
    );

    yield LicenseEntryWithLineBreaks(
      const ['Apple ALAC'],
      await rootBundle
          .loadString('android/app/src/main/cpp/third_party/alac/LICENSE'),
    );
  });
}
