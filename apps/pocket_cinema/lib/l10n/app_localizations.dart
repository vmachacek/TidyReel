import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Pocket Cinema'**
  String get appTitle;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local media compatibility lab'**
  String get appSubtitle;

  /// No description provided for @diagnosticBuild.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic build'**
  String get diagnosticBuild;

  /// No description provided for @localOnly.
  ///
  /// In en, this message translates to:
  /// **'Your files stay on this device'**
  String get localOnly;

  /// No description provided for @folderSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Media folder'**
  String get folderSectionTitle;

  /// No description provided for @noFolderSelected.
  ///
  /// In en, this message translates to:
  /// **'No media folder selected'**
  String get noFolderSelected;

  /// No description provided for @folderReady.
  ///
  /// In en, this message translates to:
  /// **'Folder access ready'**
  String get folderReady;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// No description provided for @chooseFolderAgain.
  ///
  /// In en, this message translates to:
  /// **'Choose the media folder again'**
  String get chooseFolderAgain;

  /// No description provided for @releaseTestAccess.
  ///
  /// In en, this message translates to:
  /// **'Release test access'**
  String get releaseTestAccess;

  /// No description provided for @scanSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Library scan'**
  String get scanSectionTitle;

  /// No description provided for @scanMedia.
  ///
  /// In en, this message translates to:
  /// **'Scan media'**
  String get scanMedia;

  /// No description provided for @cancelScan.
  ///
  /// In en, this message translates to:
  /// **'Cancel scan'**
  String get cancelScan;

  /// No description provided for @scanIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready to scan'**
  String get scanIdle;

  /// No description provided for @scanInProgress.
  ///
  /// In en, this message translates to:
  /// **'Scanning folders…'**
  String get scanInProgress;

  /// No description provided for @scanComplete.
  ///
  /// In en, this message translates to:
  /// **'Scan complete'**
  String get scanComplete;

  /// No description provided for @scanCancelled.
  ///
  /// In en, this message translates to:
  /// **'Scan cancelled'**
  String get scanCancelled;

  /// No description provided for @discoveredLabel.
  ///
  /// In en, this message translates to:
  /// **'Discovered'**
  String get discoveredLabel;

  /// No description provided for @videosLabel.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videosLabel;

  /// No description provided for @subtitlesLabel.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitlesLabel;

  /// No description provided for @ignoredLabel.
  ///
  /// In en, this message translates to:
  /// **'Ignored'**
  String get ignoredLabel;

  /// No description provided for @mediaSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Playable media'**
  String get mediaSectionTitle;

  /// No description provided for @noPlayableMedia.
  ///
  /// In en, this message translates to:
  /// **'No MP4 or MKV files found yet'**
  String get noPlayableMedia;

  /// No description provided for @selectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selectedLabel;

  /// No description provided for @probeSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Media details'**
  String get probeSectionTitle;

  /// No description provided for @runProbe.
  ///
  /// In en, this message translates to:
  /// **'Inspect media'**
  String get runProbe;

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get durationLabel;

  /// No description provided for @containerLabel.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get containerLabel;

  /// No description provided for @resolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolutionLabel;

  /// No description provided for @videoCodecLabel.
  ///
  /// In en, this message translates to:
  /// **'Video codec'**
  String get videoCodecLabel;

  /// No description provided for @audioCodecLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audioCodecLabel;

  /// No description provided for @streamCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Streams'**
  String get streamCountLabel;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get notAvailable;

  /// No description provided for @playerSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playerSectionTitle;

  /// No description provided for @playerIdle.
  ///
  /// In en, this message translates to:
  /// **'Select a video to test direct playback'**
  String get playerIdle;

  /// No description provided for @playerReady.
  ///
  /// In en, this message translates to:
  /// **'Ready for direct playback'**
  String get playerReady;

  /// No description provided for @playerPlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing from protected device storage'**
  String get playerPlaying;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @rewindTen.
  ///
  /// In en, this message translates to:
  /// **'Back 10 seconds'**
  String get rewindTen;

  /// No description provided for @forwardTen.
  ///
  /// In en, this message translates to:
  /// **'Forward 10 seconds'**
  String get forwardTen;

  /// No description provided for @seekStart.
  ///
  /// In en, this message translates to:
  /// **'Go to beginning'**
  String get seekStart;

  /// No description provided for @closePlayer.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get closePlayer;

  /// No description provided for @failureSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get failureSectionTitle;

  /// No description provided for @rootPermissionRevoked.
  ///
  /// In en, this message translates to:
  /// **'Folder access needs repair'**
  String get rootPermissionRevoked;

  /// No description provided for @fileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That file is no longer available. Scan the folder again.'**
  String get fileUnavailable;

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'The scan stopped before it finished. Items already found are still shown.'**
  String get scanFailed;

  /// No description provided for @storageOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'The media folder could not be read.'**
  String get storageOperationFailed;

  /// No description provided for @probeFailed.
  ///
  /// In en, this message translates to:
  /// **'Media details could not be inspected.'**
  String get probeFailed;

  /// No description provided for @probeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This file does not expose readable media details.'**
  String get probeUnsupported;

  /// No description provided for @playbackSourceFailed.
  ///
  /// In en, this message translates to:
  /// **'The selected video could not be opened.'**
  String get playbackSourceFailed;

  /// No description provided for @playbackUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This video\'s format or codec is not supported.'**
  String get playbackUnsupported;

  /// No description provided for @playbackControlFailed.
  ///
  /// In en, this message translates to:
  /// **'The playback action could not be completed.'**
  String get playbackControlFailed;

  /// No description provided for @unknownFailure.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while checking this media.'**
  String get unknownFailure;

  /// No description provided for @retryScan.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get retryScan;

  /// No description provided for @subtitleWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle not loaded'**
  String get subtitleWarningTitle;

  /// No description provided for @subtitleTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The matching subtitle is too large, so video playback continued without it.'**
  String get subtitleTooLarge;

  /// No description provided for @externalSubtitleFailed.
  ///
  /// In en, this message translates to:
  /// **'The matching subtitle could not be loaded, so video playback continued without it.'**
  String get externalSubtitleFailed;

  /// No description provided for @chooseFolderCancelled.
  ///
  /// In en, this message translates to:
  /// **'No folder was selected.'**
  String get chooseFolderCancelled;

  /// No description provided for @checkingAccess.
  ///
  /// In en, this message translates to:
  /// **'Checking saved folder access…'**
  String get checkingAccess;

  /// No description provided for @openingPlayback.
  ///
  /// In en, this message translates to:
  /// **'Opening video…'**
  String get openingPlayback;

  /// No description provided for @probingMedia.
  ///
  /// In en, this message translates to:
  /// **'Inspecting media…'**
  String get probingMedia;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
