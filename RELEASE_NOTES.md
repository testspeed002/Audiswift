# Audiswift v1.1.0 Release Notes

This release fixes Audius account sign-in, ports the route-independent
visualizer engine from the sibling Local Music App, and gives every browse
and detail view a full Apple HIG / Apple-Music–style redesign.

## What's new

### 🔐 Audius account connection
- Sign-in now works reliably with **any default browser** (Safari, Chrome,
  Helium, Arc, etc.). The redirect is delivered via the system URL scheme
  (`audiswift://oauth`) and processed by a new `application(_:open:)` handler.
- Failure paths surface a real error in the UI instead of silently swallowing
  state mismatches, HTTP errors, or malformed token responses.
- OAuth flow logs to a dedicated `os_log` subsystem (`com.openaudio.audiswift.oauth`)
  so issues can be tailed in `Console.app` even in Release builds.

### 🎨 UI redesign (Apple HIG)
Every browse and detail view now uses a consistent visual language:
blurred-artwork hero banners, prominent accent-color **Play** + glass
**Shuffle** capsule actions, palette-rendered SF Symbols, ultraThinMaterial
chips, and abbreviated counts (1.2K, 3.4M).
- **Home** — Apple-Music–style hero card for the #1 trending track.
- **Artist profile** — 320 pt hero with blurred avatar backdrop, palette
  Verified seal, AI-Attribution chip, Show-more bio.
- **Playlist & Track detail** — matching hero + action row + metadata chips.
- **Trending** — heavy rounded title, native segmented time picker, genre
  pills as glass chips with accent active state.
- **Search** — heavy title, capsule glass search bar, Browse Genres cards
  now fetch by genre **tag** (not text search).
- **Library** — Play Liked / Shuffle action row, liked + playlist counts,
  rounded playlist tiles with soft shadows.
- **Sidebar** — user profile chip moved into the List so it scrolls with the
  sidebar and never collides with the player bar.

### 🪟 Window behavior
- Hard 480×480 floor enforced via `contentMinSize` + a `windowWillResize`
  delegate clamp. The previous "shrink to 87×52 pill" was caused by an
  autosaved un-tiled frame and is fixed.
- Mini-player layout still kicks in below 860 px wide, but cannot shrink past
  the 480 px floor.

### 🎚️ Player bar
- LMA-style full-width frosted slab (`ultraThinMaterial` + accent linear
  gradient + thin top stroke) replaces the floating capsule. Controls remain
  centered and capped at 1100 px wide.
- Track title now wraps up to 2 lines; hover tooltip exposes the full title.
- (i) info popover widened to 360 pt with larger artwork tile, palette
  verified-seal next to the artist, unlimited-line title wrapping, "Released"
  row, and selectable Tags footer.

### 📊 Visualizers (route-independent)
Ported wholesale from the sibling Local Music App session:
- **FFTAnalyzer** rewritten around a 60 Hz main-thread publish timer
  draining a jitter-buffer playout ring — stereometer/oscilloscope scan and
  spectrogram scroll now run at the same speed on every audio route (built-in
  speakers vs Bluetooth, where audio callback cadence differs by ~16×).
- **StereometerView** — frame-count trail replaced with time-stamped history
  fading over 150 ms (matches the bar visualizer's decay half-life).
- **SpectrogramView** — `TimelineView`-driven wall-clock column positioning,
  uniform time-grid emission, gapless draw with left-edge clamp.

### 🐛 Bug fixes
- `playNext()` end-of-queue: explicit `player.pause()` + `isPlaying = false`
  so the bar shows ▶ (not ⏸) when the queue ends with no repeat.
- Sidebar `@handle` chip no longer gets covered by the player bar on
  short windows.

---
*Prepared by Claude*
