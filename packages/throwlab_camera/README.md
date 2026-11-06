# throwlab_camera

ThrowLab's own camera plugin, Android only. It exists for one reason: to
record at the frame rate the phone's own camera app records at.

A phone that films at 120 or 240 fps does it through Camera2's constrained
high-speed session. The stock Flutter camera asks an ordinary session for the
rate, which tops out at 60 on a Samsung, so it records at 30 or 60 instead
without saying so. This plugin opens the high-speed session when a
high-speed mode is chosen, and an ordinary one otherwise.

Kept in the repo as a path dependency because `android/` is generated in
CI: this package's `android/` is a plugin module, compiled into the app like
any other plugin.

No audio is recorded. A high-speed session records none on most phones, and a
coach should not be asked for a microphone they get nothing from.
