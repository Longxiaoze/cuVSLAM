# cuVSLAM Design Concepts

This document captures architectural decisions and design principles for cuVSLAM.
Follow these when making code changes or designing new features.

---

## 1. Runtime parameter overrides are stateless — no setters

**Rule:** Parameters that can change on a per-call basis must be passed explicitly through
the runtime API. Do not use setter functions or mutable state on long-lived objects to
change them.

**Why:** Setters create implicit shared state between frames. A parameter change made
during one `Track()` call can silently bleed into the next frame if the setter mutates an
object that is reused across calls. This makes behaviour hard to reason about, test, and
reproduce.

**How it works in cuVSLAM:**

The public `Track()` API accepts a `TrackOptions` struct that carries all per-frame
overrides. `TrackOptions` has default values matching the construction-time config, so
callers only specify what they actually want to change. Internally, this is converted to a
`TrackPerFrameSettings` and threaded down the call stack without modifying any stored state.

```cpp
// Caller — override feature count for one frame only
TrackOptions opts;
opts.num_desired_tracks = 200;
odometry.Track(images, {}, {}, opts);  // next call is unaffected
```

The stored `svo_settings` on `Odometry::Impl` is construction-time config only. It is
never mutated after construction.

**What to avoid:**

```cpp
// BAD — setter mutates shared state, bleeds across frames
odometry.SetNumDesiredTracks(200);
odometry.Track(images);
```

**Where to add new runtime parameters:**

1. Add the field (with a default value) to `cuvslam::TrackOptions` in `cuvslam2.h`.
2. Map it into `odom::TrackPerFrameSettings` in `BuildTrackFrameSettings()` in `cuvslam2.cpp`.
3. Add the field to the appropriate sub-struct of `TrackPerFrameSettings` (`sof` or `kf`)
   or add a new sub-struct for a new category (e.g. `pnp`, `icp`).
4. Thread it through the call chain — do not store it.

---

## 2. Optionals belong at the top-level API; internal APIs always receive concrete values

**Rule:** `std::optional<T>` is appropriate at the public boundary (e.g. `Odometry::Track`)
where a caller may genuinely not have a value. Internal APIs — everything below the public
API boundary — must accept concrete values, not optionals.

**Why:** Optionals at every layer of the call stack force every internal function to check
`has_value()` before use. This is noise. Once the public API has resolved an optional to a
concrete value (using a default), the rest of the system should not need to know the value
was ever absent.

**How it works in cuVSLAM:**

The public `Track()` API converts `TrackOptions` (which has defaults for everything) into
`TrackPerFrameSettings` — a plain struct of concrete values. From that point on, no
optional-checking is needed anywhere in the call chain.

```text
TrackOptions{} (public, fields have defaults)
    └─► BuildTrackFrameSettings() resolves to concrete TrackPerFrameSettings
            └─► IVisualOdometry::track(TrackPerFrameSettings&)   // no optional
                    └─► IMultiSOF::trackNextFrame(TrackPerFrameSettings&)  // no optional
                            └─► IMonoSOF::track(Settings&)  // no optional
```

**What to avoid:**

```cpp
// BAD — optional leaks into internal API
void trackNextFrame(..., std::optional<Settings> sof_settings = std::nullopt);

// BAD — internal function must check presence
if (sof_settings.has_value()) { ... }
```

**Corollary — no default arguments on internal functions:**

Internal functions should not have `= {}` default arguments. That is just a hidden optional.
Every call site should pass the struct explicitly, making the data flow visible in the code.

```cpp
// BAD — hides that data is being passed; caller can silently get wrong defaults
void track(const Settings& sof_settings = {});

// GOOD — caller always states what settings it is using
void track(const Settings& sof_settings);
```

---

## 3. Bundle related parameters into a struct rather than growing argument lists

**Rule:** When a group of parameters is always used together or represents a coherent
configuration unit, wrap them in a named struct. Do not add individual parameters to
function signatures.

**Why:** Long argument lists are fragile (easy to reorder), hard to extend, and obscure
what a function actually needs. A named struct documents intent, can be forwarded as a
single argument through multiple layers, and makes adding new fields backwards-compatible
at the struct level.

**How it works in cuVSLAM:**

- `sof::Settings` — all feature tracking parameters.
- `odom::KeyFrameSettings` — keyframe selection thresholds.
- `odom::TrackPerFrameSettings` — bundles the above two for passing through the VO layer.
- `sba::Settings`, `pnp::PNPSettings`, etc. — each subsystem owns its config struct.

When a new per-frame parameter category is needed (e.g. ICP overrides), add a new
sub-struct to `TrackPerFrameSettings` rather than adding individual fields or new function
parameters:

```cpp
struct TrackPerFrameSettings {
  sof::Settings sof;
  KeyFrameSettings kf;
  // Add new categories here, not as additional function parameters
};
```

---

## 4. Construction-time config vs runtime overrides

Parameters fall into two categories:

| Category | Example | Where it lives |
|---|---|---|
| **Construction-time** | GPU on/off, SBA mode, camera model | `Odometry::Config`, passed to constructor, stored in `svo_settings` |
| **Per-frame runtime** | Feature count, border sizes, KF threshold | `TrackOptions`, passed to `Track()`, never stored |

If a parameter only makes sense to set once (at startup), it belongs in `Config`.
If a parameter is useful to change per-frame (e.g. reduce features for a dark frame),
it belongs in `TrackOptions`. When in doubt, start with `Config`; promote to `TrackOptions`
when a concrete use case for per-frame variation exists.
