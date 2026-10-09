# Bluetooth kill switch

Pocket Cinema can use an unpaired Bluetooth Low Energy broadcast to make nearby
instances of the app show a continuous **Loading…** screen. It works without a
shared Wi-Fi network or an account.

## Set up

1. Install the current app on the Android phone and tablets.
2. On the phone, tap **Pocket Cinema** in the app bar three times within two
   seconds, choose **My phone**, and tap
   **Enable phone control**.
3. On each tablet, tap **Pocket Cinema** three times within two seconds, choose
   **Tablet**, and tap
   **Enable nearby control**.
4. Allow Android's Bluetooth/Nearby devices permission and turn Bluetooth on.

Kill switch controls are hidden from the app bar and Library Settings; the
three-tap shortcut opens their sheet from the app title, including before a media
folder is connected. One or two taps do nothing, and the tap count resets after
two seconds.

These are local roles, not Bluetooth pairing. Android 10–11 additionally requires
location permission and the system Location setting for BLE scanning. This app
does not use the scans to determine location.

## Use

Turn on **Kill switch mode** on the phone. Nearby enabled tablets cover the
library, player, and open dialogs with Loading, block touch and Back navigation,
and pause playback at its current position. The phone remains usable.

Turn the mode off on the phone to restore the tablets. Playback stays paused
until someone explicitly presses Play. The phone continues broadcasting its
current mode while the app remains alive, including while it is in the
background. After Android stops the phone's process, reopen the app to resume
broadcasting.

The loading state survives a tablet restart and losing radio contact. If the
phone is unavailable, hold the Loading spinner for five seconds, then choose
**Restore tablet**. This also disables nearby control on that tablet; enable it
again through the three-tap app-title shortcut when needed.

## Limits

Only Pocket Cinema instances with nearby control enabled respond. Other apps on
the device are unaffected. Reception depends on Bluetooth range, walls, and the
device's radio support. Phone control requires BLE advertising support; tablet
control requires BLE scanning support. Settings show permission, disabled-radio,
and unsupported-device errors.

There is no pairing or private group: a nearby Pocket Cinema controller can send
the mode to any enabled instance. Use one controller phone at a time. Broadcasts
do not provide delivery confirmations, so verify the tablet's screen when
activating the mode.

## Verification

Automated checks cover the hidden three-tap shortcut and its timeout, native
packet validation, persisted modes, Bluetooth startup failures, receive
ordering, local recovery, Back/touch blocking, and
playback activation during opening and autoplay. For a live two-device check:

1. Enable phone and tablet roles on two Android devices with Wi-Fi disconnected.
2. Start a video on the tablet, activate the mode on the phone, and confirm the
   tablet shows Loading with no audio.
3. Turn the mode off and confirm the same screen/position returns paused.
4. Repeat with a dialog open and while the video is opening.
5. Restart the tablet while active, return to radio range, and restore from the
   phone. Then test the five-second local recovery with the phone unavailable.
