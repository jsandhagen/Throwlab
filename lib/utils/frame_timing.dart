/// How a seek position and a frame identify each other.
///
/// The player renders the first frame at or *after* a seek position: every
/// decoded frame whose timestamp falls before the seek target is discarded
/// unrendered (ExoPlayer treats everything before the seek as decode-only).
/// So a seek that has to land on a particular frame must aim *before* that
/// frame's own timestamp. Aiming inside the frame's display window — halfway
/// into it, which is what "land in the middle of the frame you want" suggests
/// — lands on the *next* frame instead, every time. That is what made a scrub
/// end one frame past the still it had been showing: the still was right, and
/// the video that replaced it was one frame ahead.
///
/// Everything that converts between a position and a frame goes through this
/// convention: [seekTargetSeconds] to build a position, [nearestFrame] to read
/// one back.
library;

import 'dart:math' as math;

/// How far before a frame's own timestamp a seek aims, as a fraction of the
/// gap to the previous frame.
///
/// Anything in (previous frame, this frame] renders this frame, so the only
/// job of the lead is to stay clear of both ends: a quarter of a frame leaves
/// the seek free to drift a quarter of a frame late (or three quarters early)
/// — timestamp rounding, an inexact frame rate, a clip that is not quite
/// constant-rate — and still land on the frame that was asked for.
const double kSeekLead = 0.25;

/// Position (seconds) to seek to so the player shows the frame whose
/// timestamp is [time]; [gap] is the distance to the frame before it.
/// Clamped at zero — the first frame is rendered by any seek at or before it.
double seekTargetSeconds(double time, double gap) =>
    math.max(0, time - kSeekLead * gap);

/// Reads a position back as a frame number: [frames] is the position measured
/// in frames, and the answer is the frame whose timestamp is nearest — ties
/// going to the earlier frame, so a position exactly between two frames names
/// the one it is level with rather than the one it is heading for.
///
/// Nearest, not a floor of the window: seek targets deliberately sit a
/// [kSeekLead] short of the frame they name, and a floor would report the
/// frame before every one of them.
int nearestFrame(double frames) => (frames + 0.5 - 1e-6).floor();
