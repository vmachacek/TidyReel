// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pocket Cinema';

  @override
  String get appSubtitle => 'Local media compatibility lab';

  @override
  String get diagnosticBuild => 'Diagnostic build';

  @override
  String get localOnly => 'Your files stay on this device';

  @override
  String get folderSectionTitle => 'Media folder';

  @override
  String get noFolderSelected => 'No media folder selected';

  @override
  String get folderReady => 'Folder access ready';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get chooseFolderAgain => 'Choose the media folder again';

  @override
  String get releaseTestAccess => 'Release test access';

  @override
  String get scanSectionTitle => 'Library scan';

  @override
  String get scanMedia => 'Scan media';

  @override
  String get cancelScan => 'Cancel scan';

  @override
  String get scanIdle => 'Ready to scan';

  @override
  String get scanInProgress => 'Scanning folders…';

  @override
  String get scanComplete => 'Scan complete';

  @override
  String get scanCancelled => 'Scan cancelled';

  @override
  String get discoveredLabel => 'Discovered';

  @override
  String get videosLabel => 'Videos';

  @override
  String get subtitlesLabel => 'Subtitles';

  @override
  String get ignoredLabel => 'Ignored';

  @override
  String get mediaSectionTitle => 'Playable media';

  @override
  String get noPlayableMedia => 'No MP4 or MKV files found yet';

  @override
  String get selectedLabel => 'Selected';

  @override
  String get probeSectionTitle => 'Media details';

  @override
  String get runProbe => 'Inspect media';

  @override
  String get durationLabel => 'Duration';

  @override
  String get containerLabel => 'Container';

  @override
  String get resolutionLabel => 'Resolution';

  @override
  String get videoCodecLabel => 'Video codec';

  @override
  String get audioCodecLabel => 'Audio';

  @override
  String get streamCountLabel => 'Streams';

  @override
  String get notAvailable => 'Not available';

  @override
  String get playerSectionTitle => 'Playback';

  @override
  String get playerIdle => 'Select a video to test direct playback';

  @override
  String get playerReady => 'Ready for direct playback';

  @override
  String get playerPlaying => 'Playing from protected device storage';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get rewindTen => 'Back 10 seconds';

  @override
  String get forwardTen => 'Forward 10 seconds';

  @override
  String get seekStart => 'Go to beginning';

  @override
  String get closePlayer => 'Close player';

  @override
  String get failureSectionTitle => 'Needs attention';

  @override
  String get rootPermissionRevoked => 'Folder access needs repair';

  @override
  String get fileUnavailable =>
      'That file is no longer available. Scan the folder again.';

  @override
  String get scanFailed =>
      'The scan stopped before it finished. Items already found are still shown.';

  @override
  String get storageOperationFailed => 'The media folder could not be read.';

  @override
  String get probeFailed => 'Media details could not be inspected.';

  @override
  String get probeUnsupported =>
      'This file does not expose readable media details.';

  @override
  String get playbackSourceFailed => 'The selected video could not be opened.';

  @override
  String get playbackUnsupported =>
      'This video\'s format or codec is not supported.';

  @override
  String get playbackControlFailed =>
      'The playback action could not be completed.';

  @override
  String get unknownFailure =>
      'Something went wrong while checking this media.';

  @override
  String get retryScan => 'Scan again';

  @override
  String get subtitleWarningTitle => 'Subtitle not loaded';

  @override
  String get subtitleTooLarge =>
      'The matching subtitle is too large, so video playback continued without it.';

  @override
  String get externalSubtitleFailed =>
      'The matching subtitle could not be loaded, so video playback continued without it.';

  @override
  String get chooseFolderCancelled => 'No folder was selected.';

  @override
  String get checkingAccess => 'Checking saved folder access…';

  @override
  String get openingPlayback => 'Opening video…';

  @override
  String get probingMedia => 'Inspecting media…';
}
