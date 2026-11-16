# iOS privacy manifest

`Runner/PrivacyInfo.xcprivacy` is a Runner resource in `project.pbxproj`.
The app declares device identifiers used by optional sync/recovery as linked to
the device and its family, for app functionality. A persistent identifier relates
the device to its credential, authorizations and service activity even without a
civil name. Product interaction also covers technical sync/recovery activity
associated with that device (such as service requests and last activity). Both
categories are linked, used only for app functionality, and declared without
tracking. No analytics is added. There is no tracking domain.

Required-reason APIs checked against the locally installed dependencies:

- `shared_preferences_foundation` 2.5.7 uses `UserDefaults.standard` and the
  app's suite for local preferences. Runner declares **CA92.1** (own preferences).
  The plugin separately bundles its **1C8F.1** wrapper declaration.
- `share_plus` 13.3.1 reads `NSFileCreationDate` using
  `attributesOfItemAtPath` for files supplied by this app's sharing service.
  Runner declares **C617.1** (timestamps of files in the app container).
- `path_provider_foundation` 2.6.0 uses Foundation through FFI to resolve app
  directories; it adds no timestamp/UserDefaults category.
- `flutter_secure_storage_darwin` 0.4.3 uses Keychain; `local_auth_darwin` 2.0.5
  uses LocalAuthentication. Their bundled manifests declare no required APIs.
- `app_links` 7.2.2 and `qr_code_scanner_plus` 2.3.2 add no required-reason API
  uses in their iOS sources. Camera use is described in Info.plist and es/ca/en.
- Flutter's engine bundles its own manifest for file timestamps (**0A2A.1**,
  **C617.1**) and system boot time (**35F9.1**). Runner does not duplicate the
  engine-only boot-time use.

The checked sources are the versions resolved in `pubspec.lock`. Recheck this
inventory when updating native plugins. Windows checks validate plist contents
and Xcode resource references; a Mac archive/privacy report must still confirm
that Runner and plugin/framework manifests are present in the signed product.
