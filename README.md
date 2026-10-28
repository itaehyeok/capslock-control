# CapsLock Control

**English** · [한국어](#한국어)

A macOS menu bar utility that replaces the handful of Karabiner-Elements and
Raycast features I actually use. It is not a clone of either. No third-party
dependencies — Apple frameworks only.

## What it does

**Keyboard**

- **Caps Lock becomes a layer key.** Hold it and press another key —
  `Caps + C`, `Caps + 1` — to run whatever you assigned to that key.
- **Tap Caps Lock alone and it still toggles caps lock.** Hold it with another
  key and it is a layer; tap it by itself and it is Caps Lock.
- Advanced, off by default: **Right Command → F18** for input-source switching
  (uses the macOS shortcut) and **swap fn ↔ Left Control**.
- Unassigned keys are swallowed so **no stray characters get typed**.
  The policy can be changed in Settings › Advanced.

**What a shortcut can do**

- **Launch or focus an app** — brings it forward if running, launches it otherwise.
- **Press the same key again to toggle** — hides the app or returns to the previous
  one. Configurable per key.
- **Media control** — play/pause, next, previous. Whatever is playing receives it, or
  only Spotify, or only the YouTube Music tab in Chrome.
- **Trigger another app's global hotkey** — presses a combination like `⌃⌥⇧A` for you.
  Caps Lock is not a modifier, so other apps cannot register it directly;
  this is the way around that.

**Editing**

- **A keyboard editor shaped like a real MacBook.** Click an empty key to open the
  app picker; drag a keycap onto another key to move it (the two swap).
- The picker filters **running and installed apps** as you type, one character at a
  time. You never type a path or a bundle ID.
- Apps that are not installed show as **Missing**.

**Configuration and sync**

- Configuration is human-readable **JSON**. Edit it by hand and it is
  **picked up immediately, no restart**.
- Writes are atomic. A corrupted file is backed up rather than deleted, and the
  app starts from defaults.
- **Sync between Macs through GitHub** — Export pushes a new snapshot stamped with
  the time and the Mac's name (nothing is ever deleted); Import lets you pick one
  and **check off individual items** to pull in. A local backup is always written first.
- No tokens or keys are stored. It reuses the SSH authentication already on the machine.

**How it behaves**

- **Menu bar only**, no Dock icon. Launches at login via `SMAppService`.
- No virtual HID driver. Just Apple's own `hidutil` remapping plus a thin `CGEventTap`.
- **Quitting the app restores the keyboard**, whether by ⌘Q or a forced kill (SIGTERM).

## Getting started

### 1. Install

Download `CapsLockControl-<version>.dmg` from
[Releases](https://github.com/itaehyeok/capslock-control/releases/latest), open it,
and drag the app into Applications. It is signed and notarized, so it opens without
a warning.

**Building from source needs Xcode 26 or newer.** Command Line Tools alone will not do.

```bash
git clone https://github.com/itaehyeok/capslock-control.git
cd capslock-control
make install
```

`make install` builds it, puts it in `/Applications`, and launches it.
You do not need an Apple Developer account (it falls back to ad-hoc signing).

> If you do have one, copy `Config/Signing.local.xcconfig.example` to
> `Signing.local.xcconfig` and put your team ID in it. A stable signature means
> **macOS stops re-asking for Accessibility permission.** Ad-hoc signatures change
> on every build, so the prompt can come back.

### 2. Grant permission

On first launch a window appears and asks for Accessibility permission.
Turn on CapsLock Control in
**System Settings › Privacy & Security › Accessibility**.

If you granted it but shortcuts still do nothing, **quit and reopen the app**.
macOS sometimes needs a relaunch before the grant takes effect.

If it is *still* dead while the checkbox looks on, the grant belongs to an older
build. Accessibility permission is tied to the app's code signature, and an ad-hoc
signature changes on every build, so rebuilding leaves a stale entry that toggling
off and on does not clear. Fix it by **removing** the entry (select it, press −),
then relaunching and granting again. If that does not do it:

```bash
tccutil reset Accessibility dev.itaehyeok.CapsLockControl
```

The permission banner in the app has a "이미 켰는데도 안 될 때" button with the same
steps. To avoid this entirely, sign with a stable identity — see
`Config/Signing.local.xcconfig.example`.

### 3. If you use Karabiner

Two tools grabbing the same keys will collide. You do not have to uninstall it —
switch to an **empty profile**.

> Karabiner-Elements Settings › Profiles › Add profile › select the new one

Switching back is one click. CapsLock Control never quits another app on its own;
it only shows a warning.

**Closing the Karabiner window is not enough.** Its background daemon keeps
grabbing the keyboard, and the symptom is total silence: the engine reports
`Running · N shortcuts`, but Caps Lock produces no reaction and the `Caps`
indicator never lights. CapsLock Control watches for this and shows
`⚠︎ Karabiner-Elements conflict` in the menu bar status line.

A leftover DriverKit extension with no daemon running is harmless — the app
reports that one as a grey note, not a warning.

### 4. Create shortcuts

**You start with an empty layout.** Click any blank key in the keyboard picture and
the app picker opens. Pick from the list — that is all.

### 5. Input-source switching with Right ⌘ (optional, advanced)

Off by default. Turn it on in Settings › Advanced › Right Command → `F18`, then
set this in macOS yourself:

> System Settings › Keyboard › Keyboard Shortcuts › Input Sources →
> assign **F18** to **"Select the previous input source"**

Then Right ⌘ switches input sources. Without the macOS shortcut, Right ⌘ simply
stops doing anything.

---

### Worth knowing

**This app takes over one key** — Caps Lock, the layer key. Right Command and
fn ↔ Left Control change only if you turn them on in Settings › Advanced.
**Caps Lock still works as Caps Lock when tapped alone**, so you do not lose it
entirely.

**There is no Dock icon.** Click the keyboard icon in the menu bar for the menu.
If your menu bar is too crowded to show it, double-click
`/Applications/CapsLockControl.app` in Finder to open the window. The ⚙️ button in
the top right of that window opens Settings.

**If something goes wrong**, quitting the app restores the keyboard (⌘Q or a forced
kill, either way). If it is still odd:

```bash
make reset-hid     # or: hidutil property --set '{"UserKeyMapping":[]}'
```

A reboot also clears it. **The keyboard can never get locked** — the worst case is
that Caps Lock does nothing.

**GitHub sync is optional.** With a single Mac you never need to set it up.

## Requirements

macOS 14 or newer, Xcode 26 or newer. No third-party dependencies.

## Build

```
make build            # build
make run              # build and run (for development)
make install          # install into /Applications and run
make test             # unit tests
make icon             # regenerate the icon (Tools/make-icon.swift)
make reset-hid        # restore the keyboard after an abnormal exit
make refresh-icon-cache
make release VERSION=x.y.z  # sign, notarize, publish to GitHub Releases (paid Apple account)
```

**Launch at login only works properly if you `make install` first.**
`SMAppService` remembers the app's path at registration time, so registering from
inside `build/` fails silently once the app moves. Settings warns about this.

## Distributing a build to other people

Anyone can build this from source with no Apple account — that is the default.
The cost is an **ad-hoc signature**, which changes on every build, so macOS
re-asks for Accessibility permission each time and Gatekeeper warns on first launch.

With a **paid Apple Developer account** you can hand people a DMG they just drag
into Applications. No warning, no right-click-open, and the Accessibility grant
survives updates because the signature stays the same.

### One-time setup

**1. Create a Developer ID Application certificate.** This is not the same as
`Apple Development`, which only works on your own machines.

> Xcode › Settings › Accounts › select your account › Manage Certificates
> › + › Developer ID Application

You need the Account Holder or Admin role on the team. Check which team the
certificate belongs to — if you are a member of a company team, do not ship a
personal app under it.

**2. Store notarization credentials in the keychain.**

```bash
xcrun notarytool store-credentials CapsLockControl \
  --apple-id <your Apple ID> --team-id <your team ID> --password <app-specific password>
```

The app-specific password comes from appleid.apple.com › Sign-In and Security ›
App-Specific Passwords. It is not your account password. Neither this repository
nor the release script stores it — it lives in your keychain.

### Building a release

```bash
make release VERSION=0.2.0
```

That runs `Tools/release.sh`. One command does everything — there is nothing to
upload by hand:

1. checks it can publish before spending minutes on a build: on `main`, a clean
   tree, a version higher than the last tag, a public repository, and `gh` logged in
   as the repository owner,
2. sets `MARKETING_VERSION` to that version and commits it,
3. builds Release with Hardened Runtime and a secure timestamp,
4. checks the signature and refuses to continue if `get-task-allow` or the app
   sandbox slipped in — either one gets rejected by the notary service,
5. notarizes the app and staples the ticket to it,
6. packages a DMG with an `/Applications` symlink, signs, notarizes and staples it,
   then verifies it the way the recipient's Mac will,
7. tags `v<version>`, pushes, and creates the GitHub release with the DMG.

The release notes are the commit subjects since the previous tag unless you pass
`RELEASE_NOTES_FILE=notes.md`. Values that only fit your Mac — say, a notarization
profile stored under another name — go in `Config/Release.local.env`
(`NOTARY_PROFILE=<name>`), which is not committed.

`SKIP_NOTARIZE=1 make release` does a local dry run: it builds into `dist.noindex/`
and publishes nothing. Do not hand that DMG to anyone — Gatekeeper will block it.

### Notes specific to this app

- **The sandbox must stay off.** `CGEventTap` and `hidutil` do not work inside it.
  Developer ID distribution does not require the sandbox; only the App Store does.
- **Hardened Runtime needs one entitlement**, `com.apple.security.automation.apple-events`,
  because the Spotify and YouTube Music media shortcuts send Apple Events. It lives in
  `Config/CapsLockControl.entitlements`. Everything else — the event tap, IOKit
  caps-lock state, spawning `hidutil` and `git` — runs untouched under Hardened Runtime.
- **There is no auto-updater.** Sparkle would be an external dependency and this
  project has none. Updating means downloading the new DMG.
- **The repository has to be public.** The release assets of a private repository
  cannot be downloaded without authentication.

## Why it works the way it does

### Why an event tap alone is not enough

Caps Lock's toggle and its LED are handled **below the session event tap, in the HID
driver**. Discarding the event in a tap still lights the LED and still flips the caps
state. On top of that macOS applies a hold-delay to Caps Lock, which makes it
noticeably sluggish as a layer key. That is why Karabiner ships a virtual HID driver.

### The approach here: HID remap plus a thin event tap

Instead of a driver, this uses `UserKeyMapping` in Apple's own `/usr/bin/hidutil`.

| Physical key | After HID remap | Handled by |
|---|---|---|
| Caps Lock | F19 | CapsLock Control's event tap (the layer) |
| Right Command | F18 | macOS input-source shortcut (optional · `rightCommand.action`) |
| fn | Left Control | macOS (optional · `modifiers.swapFnAndLeftControl`) |
| Left Control | fn | macOS (optional · paired with the above) |

The fn swap is off by default and is turned on in Settings. It only works on Apple
keyboards (built-in and Magic Keyboard). fn does not live on the normal keyboard
usage page but on the Apple vendor top case page (0xFF), which hidutil also handles.
Both directions must be mapped together — map only one and both keys become Control.

The payoff is that **the event tap never touches modifiers**. No event synthesis, no
flag juggling, no re-entrancy guards. All that is left is tracking F19 and
handling ordinary keys while a layer is held.

Properties:

- No private API, no kernel extension
- Not persistent — a reboot or logout clears it
- Restored automatically when the app exits (⌘Q and SIGTERM both)
- Applies only to keyboards attached at the time, so it is reapplied on hotplug

### Recovering after a crash

If the app crashes the mapping stays behind. Caps Lock does nothing
(the keyboard is not locked), and this fixes it immediately:

```
make reset-hid
# or
hidutil property --set '{"UserKeyMapping":[]}'
```

The "Force-remove HID mapping" button in the app does the same thing. A reboot also
clears it.

## Configuration file

`~/Library/Application Support/CapsLockControl/shortcuts.json`

Created on first launch, **empty**. Shortcuts differ from person to person, so
pre-filling them would only mean deleting someone else's first. Settings that alter
the keyboard (the fn ↔ Left Control swap) also start off — a setting absent from the
file should never quietly change your keyboard.

```json
{
  "version": 1,
  "defaults": {
    "whenAlreadyActive": "hide",
    "unmappedKeyPolicy": "swallow",
    "capsLockTapTogglesCapsLock": true,
    "layerTapTimeoutMilliseconds": 250
  },
  "rightCommand": { "action": "none" },
  "modifiers": { "swapFnAndLeftControl": false },
  "layers": {
    "capsLock": {
      "c": { "type": "application",
             "bundleIdentifier": "com.google.Chrome",
             "displayName": "Google Chrome" },
      "left": { "type": "media", "command": "previous", "target": "system" }
    }
  }
}
```

- Key identifiers
  - Letters and digits: `a`–`z`, `0`–`9`
  - Punctuation: `grave` `minus` `equal` `leftBracket` `rightBracket` `backslash`
    `semicolon` `quote` `comma` `period` `slash`
  - Arrows: `left` `right` `up` `down`
  - Others: `space` `return` `tab` `delete` `escape`
  - Punctuation also reads as the literal character (`","` `"."` `"/"` `"\\"`), but
    the app always writes the name form. That avoids escaping backslashes in JSON,
    and an existing alias entry is removed so one physical key never ends up with
    two entries.
- `whenAlreadyActive`: `nothing` | `hide` | `switchToPrevious` — overridable per key
- `rightCommand.action`: `f18` | `none` (`none` leaves Right ⌘ alone)
- `media.command`: `playPause` | `next` | `previous`, `target`: `system` | `spotify` | `youTubeMusic`
- `modifiers.swapFnAndLeftControl`: swap fn ↔ Left Control (off when absent)

**Editing it by hand is fine.** The app watches the folder and re-reads on save.
No restart needed.

Safety:

- Writes are always atomic — a crash mid-write cannot leave a half file.
- A corrupted file is **kept**, moved aside as `shortcuts.broken-<time>.json`,
  and the app starts from defaults.
- A file whose version is newer than the app is treated as read-only, so this Mac
  cannot clobber a config written by a newer version on another Mac.
- Unknown keys, layers, or action types do not crash anything. That entry is skipped
  and reported as a warning.

## Calling another app's hotkey (keyStroke)

CapsLock Control presses a key combination on your behalf. Whatever app registered
that combination as a global hotkey responds as usual.

```json
"a": {
  "type": "keyStroke",
  "key": "a",
  "modifiers": ["control", "option", "shift"],
  "label": "Toggle noise cancelling"
}
```

**Why it is needed.** Caps Lock becomes F19 here, so another app cannot register
"Caps+A" directly. Instead CapsLock Control catches Caps+A and emits ⌃⌥⇧+A, and the
receiving app registers plain ⌃⌥⇧+A.

**Why it works.** Hotkeys registered with Carbon's `RegisterEventHotKey` are matched
by the WindowServer against the event stream. A synthetic event with the right
modifier flags is treated exactly like a hardware press.

**Avoiding an infinite loop.** Events we create come back into our own event tap.
Without a marker, Caps+A → emit → tap catches it → emit again, forever. Every
synthetic event carries a marker in `eventSourceUserData`, and the tap passes
anything carrying it straight through.

In the GUI: click an empty key, then the "Send key combination" field at the bottom
of the picker, then press the combination.

## Tapping Caps Lock alone

Tap Caps Lock **without combining it with another key** and the original caps lock
toggles. Hold it with a key and it is a layer; tap it alone and it is Caps Lock.

Both conditions must hold:

- **No other key was used** while it was held (the state machine remembers)
- It was held for less than `layerTapTimeoutMilliseconds` (250 ms by default,
  adjustable from 100 to 600 ms in Settings › Advanced)

The time condition exists to distinguish this from turning a layer on and then
changing your mind.

Synthesising a Caps Lock key event with CGEvent does nothing — the toggle is handled
in the HID layer, the same reason an event tap cannot block Caps Lock. The state is
set directly through IOKit's public API (`IOHIDSetModifierLockState`).

## App toggle (when it is already frontmost)

What happens when you press the same shortcut again. Same idea as Keyboard Maestro's
Toggle.

| Value | Behaviour |
|---|---|
| `hide` (default) | Same as ⌘H. macOS brings the next app forward on its own |
| `switchToPrevious` | Returns to the app that was in front before this one; falls back to `hide` |
| `nothing` | Does nothing |

`hide` is the default because it holds no state. Remembering the previous app can go
stale if that app quit or another app came in between.

**Repeat suppression**: activation is asynchronous, so pressing twice very quickly
can mean the second press sees a frontmost app that has not changed yet — making the
toggle depend on timing. To remove that ambiguity, a repeat on the same app within
250 ms is ignored.

## Media control

`target: "system"` (default) emits the same system event a hardware media key does
(`NX_KEYTYPE_*` from IOKit's public `ev_keymap.h`). macOS delivers it to whatever is
currently playing, so Spotify gets it when Spotify is playing. No extra permission,
and it keeps working if you switch to Apple Music.

`target: "spotify"` drives Spotify directly through AppleScript. It always controls
Spotify regardless of what is playing, but asks for automation permission once. If
Spotify is not running it says so rather than launching it.

**Pick `spotify` if a browser keeps stealing the keys.** "Whatever is currently
playing" includes a YouTube tab in Chrome or Safari, so with `system` those tabs
answer your play/pause just as readily as Spotify does. `spotify` never touches them.

`target: "youTubeMusic"` drives the YouTube Music tab in Chrome directly. It finds
the first `https://music.youtube.com/` tab in any window — background tabs included —
and presses the play/pause, next or previous button in its player bar through
JavaScript, exactly as a click would. Other YouTube tabs never react. It needs two
things, both once:

- **Chrome › View › Developer › Allow JavaScript from Apple Events**
  (보기 › 개발자 › Apple Events의 자바스크립트 허용). The setting is per profile, so turn
  it on in a window of the profile that has YouTube Music open.
- The automation permission prompt for Google Chrome.

If Chrome is not running or no YouTube Music tab is open, it says so rather than
opening one. The button lookup depends on YouTube Music's page structure; when it
breaks, the log names the selector that was not found (`/usr/bin/log show --predicate
'subsystem == "dev.itaehyeok.CapsLockControl" AND category == "Media"' --last 10m`).
Use the full path: in zsh, `log` can be a shell builtin that silently shadows
`/usr/bin/log`.

Both places to change it:

- **One shortcut** — select the key in Key Layout, then use the *보낼 곳* picker.
  A button below it offers to move the remaining media shortcuts along with it.
- **New shortcuts** — Settings › Advanced › 미디어 키 sets the target for shortcuts you
  create from then on, and warns when existing ones still point elsewhere.

No private frameworks such as MediaRemote are used.

## Window layout

```
┌─ [ Key Layout ] [ Status ] ─────────────────────┐  ← tabs (title bar)
│ CapsLock Control                   [Caps] Stop ⚙│  ← always-visible header
│ Running · 28 shortcuts                          │     layer lights are live
├─────────────────────────────────────────────────┤
│                           Used 28  Available 28 │
│                                                 │
│ esc `  1 2 3 4 5 6 7 8 9 0  -  =  [delete]      │
│ [tab]  Q W E R T Y U I O P  [  ]  \             │
│ [caps ]  A S D F G H J K L  ;  '  [return]      │
│ [ shift ]  Z X C V B N M  ,  .  /  [ shift ]    │
│ fn ctrl opt cmd [== space ==] cmd opt     ←↑↓→  │
└─────────────────────────────────────────────────┘
```

- It follows the **real MacBook layout**. tab / caps / shift / return / delete sit
  where they belong and the widths are proportional (tab 2u, shift 2.5u, space 5u…).
  Space runs from C's left edge to M's right edge, as on a MacBook. All four arrow
  keys are half height, with ← ↓ → along the bottom.
- Keys you **cannot** assign (shift, option…) are always drawn in grey so you can
  see what is remapped — right command shows `→ F18`, fn/control show the swap.
- Both layers **share the same keyboard view**. Switching layers only changes which
  `action` each keycap receives.
- A keycap shows the key label, the app icon, and the app name (up to two lines).
  Empty keys are a dashed outline with a `+`.
- Apps that are not installed get a red border and **Missing**.
- Permission warnings, conflict warnings, the engine switch, and the layer lights
  live outside the tabs, so they are visible from either tab.

App names on keycaps are never shortened by a heuristic. Taking the first word turns
"Google Chrome" into "Google"; taking the last turns "Microsoft Remote Desktop Beta" into
"Beta". Neither is right, so the full name is drawn across up to two lines and
truncated if it still does not fit.

## Editing shortcuts

Click a keycap. Editing the config file by hand still works too.

| Action | Result |
|---|---|
| **Click an empty key** | The app picker opens immediately |
| **Click an assigned key** | Detail panel (change / remove / behaviour when frontmost) |
| **Drag a keycap onto another** | The two **swap**. Dragging onto an empty key moves it |
| Remove | Immediately Available |

### The app picker

You never type a path or a bundle ID. Search filters **as you type**, with no Enter,
matching `localizedName` and `bundleIdentifier` case-insensitively.

- **Running** — `NSWorkspace.runningApplications` filtered to
  `activationPolicy == .regular`, so menu bar agents and background processes are
  excluded. CapsLock Control itself is added explicitly, since assigning a shortcut
  to it (open/hide its window) is a legitimate thing to do. The list updates as apps
  come and go.
- **Installed** — shown as well, because you should be able to assign an app that is
  not running. Scanned once in the background the first time the picker opens;
  entries already in the running list are removed.
- **Media** — Play/Pause · Next · Previous.
- **Hide already-assigned apps** is checked by default. Most of the time you are
  looking for a new app, not one you already bound. It tells you how many are hidden.
- If an app is already bound to another key in this layer, the row says so (`on C`).

### Conflicts

Assigning over a key already in use shows exactly what is being replaced and asks.

```
Caps + C is currently assigned to Google Chrome.
Replace with Safari?                 [Cancel] [Replace]
```

Dragging is a **swap**, so nothing is lost and no confirmation is asked.

### Development flag

Opens the app picker without click automation. DEBUG builds only.

```
open build/Build/Products/Debug/CapsLockControl.app --args -openPicker q
```

## GitHub sync — Export / Import

Two Macs share one configuration. Put the repository address in Settings › Advanced › GitHub 동기화.

| Action | What it does |
|---|---|
| **Export** | Pushes the current configuration as a **new snapshot** stamped with the time and Mac name. Nothing existing is deleted |
| **Import** | Pick one of the stored snapshots, see what would change, and **check off the items** you want |

```
<your-config-repo>/
  shortcuts.json                              ← most recent export (readable on the web)
  snapshots/
    2026-09-14_153045_my-macbook.json
    2026-09-13_091201_my-imac.json
```

### Why not automatic merging

This started as a 3-way automatic merge and was changed.

- **Export never deletes.** A bad export leaves every earlier snapshot intact, so
  undoing is one Import. A merge overwrites the result, which is hard to recover from.
- **Selective import is more expressive.** "Pull just Caps+C from my work Mac" cannot
  be expressed by an automatic merge. Conversely, what the merge did — keep changes
  from both sides — is just checking every box. It is a superset.
- **No common ancestor to track.** A merge that picks the wrong base produces a
  quietly wrong result. This approach has no such path.

The cost is that it is not automatic, so the status line says "Changes to export".

### The Import screen

Picking a snapshot shows the differences against the current configuration, grouped
into **added / changed / removed** and laid out side by side like a diff: current on
the left, snapshot on the right, with the missing side left blank. Everything is
checked initially, so pressing the button as-is imports all of it. There are
`Select all` and `Deselect all` buttons.

Import only changes this Mac. Nothing is pushed to GitHub.

Before applying, it asks whether to back up first. "Export then import" pushes the
current configuration as a snapshot so you can roll back with one Import. Either way
a local backup file is always written to
`~/Library/Application Support/CapsLockControl/backups/`.

### Authentication

No token, password, or SSH key is stored in the app. It reuses the SSH
authentication already configured on the machine. To make sure it never hangs on a
prompt it sets `GIT_TERMINAL_PROMPT=0` and `ssh -o BatchMode=yes`, and every git call
has a timeout. If the key is not in ssh-agent it fails with "authentication failed"
rather than hanging.

> If you have more than one GitHub account, the default key may belong to the wrong
> one. Use the `Host` alias from your `~/.ssh/config` in the address, for example
> `git@github-personal:user/repo.git`. `ssh -T git@github.com` tells you which
> account you authenticate as.

### How the repository is handled

- The clone lives in `~/Library/Application Support/CapsLockControl/sync/` and is
  treated as a **disposable workspace**. The config folder itself is not a repository,
  because git replacing files underneath would let the app's file watcher read a
  half-written state.
- Before exporting it runs `reset --hard origin/<branch>` + `clean -fd` to match the
  remote, then commits only the new snapshot. Our commit is therefore always a
  descendant of the remote, so a push is never rejected and no merge commit appears.
  Leftovers from a previous failure get cleaned up at the same time.
- A brand-new repository with no commits is handled. `rev-parse --abbrev-ref HEAD`
  fails in that state, so the branch name comes from `symbolic-ref --short HEAD`,
  and the reset is skipped when `origin/<branch>` does not exist.
- Snapshots are never pruned. Each is about 4 KB, and discarding history would throw
  away the whole point of this approach.

## Project layout

```
CapsLockControl/
  Core/     Pure logic, no AppKit. This is what the unit tests cover.
    KeyCode.swift            virtual key code ↔ string identifier table
    LayerKey.swift           capsLock
    ShortcutAction.swift     application / media / keyStroke / (room to grow)
    BindingTable.swift       lookup table normalised to key codes
    AppConfiguration.swift   on-disk schema + version/migration
    ConfigStore.swift        atomic writes · corrupt-file backup · folder watching
    ConfigDiff.swift         item-level comparison for Import
    LayerStateMachine.swift  pure state machine for press/release ordering
    EngineOptions.swift      engine behaviour derived from the config
    UnmappedKeyPolicy.swift  what to do with unassigned keys (default: swallow)
  Engine/   Where it meets the system
    HIDRemapper.swift        hidutil wrapper + reapply on keyboard hotplug
    EventTapController.swift CGEventTap on a dedicated thread, auto re-enable
    KeyboardEngine.swift     wires tap ↔ state machine ↔ execution
    ActionExecutor.swift     launch / focus / toggle (MainActor)
    CapsLockState.swift      reads and writes the real caps lock state
    MediaController.swift    system media keys · Spotify AppleScript · YouTube Music tab
    YouTubeMusicScript.swift AppleScript/JavaScript for the YouTube Music tab, result parsing
    KeyStrokeSender.swift    synthetic events for other apps' hotkeys
    FrontmostAppTracker.swift remembers the previous app
    GitSync.swift            export / import through system git
    DefaultConfiguration.swift the empty first-run configuration
  App/      SwiftUI entry point · AppDelegate · EngineModel · SyncController
  UI/       Keyboard editor, pickers, settings, menu bar
```

### Threading rules

The event tap callback runs on a **dedicated thread, not the main thread**. If the
main thread stalls even briefly the tap is disabled by timeout and keyboard input
stops entirely. The callback only updates state under a lock; anything real, such as
launching an app, is handed to `Task { @MainActor }`.

### State machine invariants

- A key whose keyDown was swallowed also has its keyUp swallowed — release the layer
  first and the pairing still holds
- Auto-repeat keyDown does not re-run the action
- Holding two layer keys: the most recently pressed one wins
- When the tap is re-enabled, all held-key state is forgotten

## Icon

`Tools/make-icon.swift` draws it in code. To change it, edit that file and run
`make icon && make build`.

The key idea is **reducing detail at small sizes**. A drawing that looks good at
512px becomes a smudge at 16px. The first version put an SF Symbol keyboard on it and
turned into a blur at 16–32px. The icon is now a single space-gray Caps Lock key with
its green light on. The "caps lock" legend is drawn only at 128px and up, where it can
be read; below that the legend is dropped and the light is drawn larger, and at 16px
it keeps a minimum size so it still shows as a green dot.

**Note**: rebuilding to the same path leaves Finder and the app's own keycaps showing
the old icon, because the LaunchServices icon cache keys on the path.
`make refresh-icon-cache` clears it.

## Living alongside Karabiner and Raycast

While testing, do not uninstall them. Two tools grabbing the same key will collide,
so switch Karabiner to an **empty profile** for the duration
(Settings → Profiles → Add profile). Switching back is one click.

CapsLock Control never quits another app. It only shows a warning when one is running.

---

# 한국어

[English](#capslock-control) · **한국어**

Karabiner-Elements 와 Raycast 에서 실제로 쓰던 기능만 대체하는 macOS 메뉴바
유틸리티. Karabiner 클론도, Raycast 클론도 아니다. 외부 의존성 없이 Apple
framework 만 쓴다.

## 핵심 특징

**키보드**

- **Caps Lock 을 레이어 키로** 쓴다. 누른 채로 다른 키를 치면
  (`Caps + C`, `Caps + 1`) 그 키에 지정해 둔 동작이 실행된다.
- **Caps Lock 을 혼자 짧게 치면 원래 대문자 고정**이 동작한다.
  조합해서 쓰면 레이어, 톡 치면 Caps Lock.
- 고급 설정(기본은 꺼짐): **Right Command → F18** 로 한/영 전환(macOS 입력 소스
  단축키를 그대로 쓴다), **fn ↔ 왼쪽 Control 맞바꾸기**.
- 등록하지 않은 키는 삼켜서 **엉뚱한 글자가 입력되지 않는다**. 정책은 설정 › 고급 에서 바꾼다.

**단축키로 할 수 있는 일**

- **앱 실행/전환** — 실행 중이면 앞으로, 아니면 실행.
- **같은 키를 다시 누르면 토글** — 숨기거나 직전 앱으로 돌아간다. 키마다 따로 정한다.
- **미디어 제어** — 재생/일시정지·다음·이전. 지금 재생 중인 앱이 받거나, Spotify 또는
  Chrome 의 YouTube Music 탭만 받게 할 수 있다.
- **다른 앱의 전역 단축키 호출** — `⌃⌥⇧A` 같은 조합을 대신 눌러 준다.
  Caps Lock 은 모디파이어가 아니라서 다른 앱이 직접 등록할 수 없는데, 이걸로 우회한다.

**편집**

- **실제 맥북 모양의 키보드 에디터.** 빈 키를 누르면 앱 피커가 열리고,
  키캡을 끌어서 다른 키로 옮길 수 있다(양쪽이 맞바뀐다).
- 앱 피커는 **실행 중인 앱 + 설치된 앱**을 한 글자 칠 때마다 걸러 준다.
  경로나 bundle ID 를 입력할 일이 없다.
- 설치되지 않은 앱은 **Missing** 으로 표시된다.

**설정과 동기화**

- 설정은 사람이 읽고 고칠 수 있는 **JSON** 이다. 직접 고치면 **재시작 없이 바로 반영**된다.
- 저장은 atomic. 파일이 깨져 있으면 지우지 않고 백업한 뒤 기본값으로 시작한다.
- **GitHub 로 Mac 사이 동기화** — Export 는 시각과 Mac 이름이 붙은 새 스냅샷을 쌓고
  (기존 것을 지우지 않는다), Import 는 그중 하나를 골라 **항목별로 체크해서** 가져온다.
  가져오기 전에 로컬 백업이 항상 남는다.
- 토큰·키를 저장하지 않고 이 Mac 에 이미 설정된 SSH 인증을 쓴다.

**동작 방식**

- Dock 아이콘 없는 **메뉴바 전용 앱**. 로그인 시 자동 실행(`SMAppService`).
- 가상 HID 드라이버를 만들지 않는다. Apple 이 제공하는 `hidutil` 리맵 +
  얇은 `CGEventTap` 조합이다.
- **앱을 종료하면 키보드가 원래대로 돌아간다.** ⌘Q 든 강제 종료(SIGTERM)든.

## 처음 쓰는 사람

### 1. 받아서 설치

[Releases](https://github.com/itaehyeok/capslock-control/releases/latest) 에서
`CapsLockControl-<버전>.dmg` 를 받아 열고, 앱을 응용 프로그램 폴더로 끌어다 놓는다.
서명·공증돼 있어 경고 없이 열린다.

**소스에서 빌드하려면 Xcode 26 이상이 필요하다.** Command Line Tools 만으로는 안 된다.

```bash
git clone https://github.com/itaehyeok/capslock-control.git
cd capslock-control
make install
```

`make install` 이 빌드해서 `/Applications` 에 넣고 실행까지 한다.
Apple 개발자 계정이 없어도 된다(ad-hoc 서명).

> 계정이 있으면 `Config/Signing.local.xcconfig.example` 를
> `Signing.local.xcconfig` 로 복사해 팀 ID 를 넣자. 서명이 고정되어
> **손쉬운 사용 권한을 다시 묻지 않는다.** ad-hoc 은 빌드할 때마다 서명이 달라져서
> 권한을 다시 물어볼 수 있다.

### 2. 권한 허용

첫 실행이면 창이 뜨고 손쉬운 사용 권한을 요청한다.
**시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용** 에서 CapsLock Control 을 켠다.

허용했는데 단축키가 안 먹으면 **앱을 한 번 껐다 켜자**. macOS 가 권한을 반영하는
데 재실행이 필요한 경우가 있다.

그래도 안 되는데 목록에는 켜져 있다면 **예전 빌드의 권한 기록이 남은 것**이다.
손쉬운 사용 권한은 앱의 코드 서명에 묶이는데, ad-hoc 서명은 빌드할 때마다 바뀐다.
그래서 다시 빌드하면 낡은 기록이 남고, 껐다 켜는 것으로는 안 풀린다.
목록에서 **− 로 지운 뒤**(끄는 게 아니라 삭제) 앱을 다시 켜고 허용하면 된다.
그래도 안 되면:

```bash
tccutil reset Accessibility dev.itaehyeok.CapsLockControl
```

앱의 권한 배너에 있는 **"이미 켰는데도 안 될 때"** 버튼에 같은 안내가 있다.
아예 겪고 싶지 않으면 고정된 서명을 쓰자 — `Config/Signing.local.xcconfig.example` 참고.

### 3. Karabiner 를 쓰고 있다면

같은 키를 두 도구가 가로채므로 겹친다. 지울 필요는 없고 **빈 프로필**로 바꾸면 된다.

> Karabiner-Elements 설정 › Profiles › Add profile › 새 프로필 선택

되돌리는 것도 클릭 한 번이다. CapsLock Control 은 다른 앱을 절대 자동 종료하지 않고
경고만 띄운다.

**창을 닫는 것으로는 부족하다.** 백그라운드 데몬이 계속 키보드를 잡고 있고,
증상은 완전한 침묵이다 — 앱은 `동작 중 · 단축키 N개` 라고 멀줦히 표시하는데
Caps Lock 을 눌러도 아무 반응이 없고 `Caps` 표시등도 안 들어온다. 이제는 이 경우를
감지해서 메뉴바 상태줄에 `⚠︎ Karabiner-Elements 충돌` 로 띄운다.

데몬 없이 DriverKit 드라이버 확장만 남은 상태는 무해하다 — 그건 경고가 아니라
회색 안내로만 보여 준다.

### 4. 단축키 만들기

**단축키는 비어 있는 상태로 시작한다.** 키보드 그림에서 빈 키를 누르면 앱 피커가
열린다. 목록에서 고르기만 하면 된다.

### 5. 오른쪽 ⌘ 로 한/영 전환 (선택 · 고급)

기본은 꺼져 있다. 설정 › 고급 › Right Command 를 `F18` 로 바꾼 뒤
macOS 설정에서 직접 이것을 지정한다.

> 시스템 설정 › 키보드 › 키보드 단축키 › 입력 소스 →
> **"이전 입력 소스 선택"** 에 **F18** 지정

그러면 오른쪽 ⌘ 로 한/영이 전환된다. macOS 단축키를 지정하지 않으면 오른쪽 ⌘ 만
없어지고 아무 일도 일어나지 않는다.

---

### 알아 두면 좋은 것

**이 앱은 한 키를 가져간다** — 레이어 키인 Caps Lock.
Right Command 와 fn ↔ 왼쪽 Control 은 설정 › 고급 에서 켰을 때만 바뀐다.
**Caps Lock 은 혼자 짧게 치면 원래 대문자 고정으로 동작**하니 완전히 잃는 건 아니다.

**Dock 아이콘이 없다.** 메뉴바의 키보드 아이콘을 클릭하면 메뉴가 나온다.
메뉴바가 꽉 차서 아이콘이 안 보이면, Finder 에서 `/Applications/CapsLockControl.app`
을 더블클릭하면 창이 열린다. 창 오른쪽 위 ⚙️ 로 설정에 들어간다.

**뭔가 잘못되면** 앱을 종료하면 키보드가 원래대로 돌아간다(⌘Q, 강제 종료 모두).
그래도 이상하면:

```bash
make reset-hid     # 또는 hidutil property --set '{"UserKeyMapping":[]}'
```

재부팅해도 원래대로 돌아온다. **키보드가 잠기는 일은 없다** —
최악의 경우 Caps Lock 이 아무 일도 안 하는 상태가 될 뿐이다.

**GitHub 동기화는 선택 사항이다.** Mac 이 하나면 설정하지 않아도 된다.

## 요구 사항

macOS 14 이상, Xcode 26 이상. 외부 의존성 없음.

## 빌드

```
make build            # 빌드
make run              # 빌드 후 실행 (개발용)
make install          # /Applications 로 설치하고 실행
make test             # 유닛 테스트
make icon             # 아이콘 다시 생성 (Tools/make-icon.swift)
make reset-hid        # 비정상 종료 후 키보드 복구
make refresh-icon-cache
make release VERSION=x.y.z  # 서명·공증 후 GitHub 릴리스에 올림 (유료 Apple 계정 필요)
```

**로그인 시 자동 실행을 쓰려면 `make install` 로 설치한 뒤 켜야 한다.**
`SMAppService` 는 등록 시점의 앱 경로를 기억하므로, `build/` 안에서 등록하면
앱을 옮기는 순간 조용히 실패한다. 설정 창에 이 경고가 뜬다.

## 남에게 배포하기

Apple 계정 없이도 누구나 소스에서 빌드할 수 있다 — 그게 기본값이다. 대신
**ad-hoc 서명**이라 빌드할 때마다 서명이 바뀐다. 그래서 손쉬운 사용 권한을 매번
다시 줘야 하고, 처음 열 때 Gatekeeper 경고가 뜬다.

**유료 Apple 개발자 계정**이 있으면 DMG 를 건네주면 끝이다. 받는 사람은 끌어다
놓기만 하면 된다. 경고창도, 우클릭 열기도 없고, 서명이 고정되므로 업데이트해도
손쉬운 사용 권한이 풀리지 않는다.

### 한 번만 해두는 준비

**1. Developer ID Application 인증서를 만든다.** `Apple Development` 와 다른
인증서다. 그건 내 기기에서만 쓸 수 있다.

> Xcode › Settings › Accounts › 계정 선택 › Manage Certificates
> › + › Developer ID Application

팀에서 Account Holder 또는 Admin 권한이 있어야 만들 수 있다. 인증서가 어느 팀
소속인지도 확인하자 — 회사 팀에 소속돼 있다면 개인 앱을 그 팀 이름으로 내보내면
안 된다.

**2. 공증 자격증명을 키체인에 저장한다.**

```bash
xcrun notarytool store-credentials CapsLockControl \
  --apple-id <Apple ID> --team-id <팀 ID> --password <앱 암호>
```

앱 암호는 appleid.apple.com › 로그인 및 보안 › 앱 암호 에서 만든다. 계정
비밀번호가 아니다. 이 저장소도 릴리스 스크립트도 암호를 담지 않는다 — 키체인에만
있다.

### 릴리스 만들기

```bash
make release VERSION=0.2.0
```

`Tools/release.sh` 가 명령 하나로 끝까지 한다 — 손으로 올릴 파일이 없다:

1. 빌드에 몇 분 쓰기 전에 올릴 수 있는지부터 본다: `main` 브랜치인지, 커밋 안 된
   변경이 없는지, 지난 태그보다 버전이 큰지, 저장소가 공개인지, `gh` 가 저장소
   주인 계정으로 로그인돼 있는지
2. `MARKETING_VERSION` 을 그 버전으로 바꾸고 커밋
3. 하드닝 런타임과 보안 타임스탬프를 켜고 Release 빌드
4. 서명을 확인하고, `get-task-allow` 나 샌드박스가 끼어들었으면 중단
   — 둘 중 하나만 있어도 공증이 거부된다
5. 앱을 공증하고 티켓을 앱에 붙인다(staple)
6. `/Applications` 심볼릭 링크를 넣은 DMG 를 만들어 서명·공증·스테이플하고,
   받는 사람의 Mac 이 하는 것과 같은 검사로 확인
7. `v<버전>` 태그를 달고 푸시한 뒤, DMG 를 붙여 GitHub 릴리스를 만든다

릴리스 설명은 `RELEASE_NOTES_FILE=notes.md` 를 주지 않으면 지난 태그 뒤의 커밋
제목으로 만든다. 공증 프로필을 다른 이름으로 저장해 둔 것처럼 이 맥에만 맞는 값은
`Config/Release.local.env`(`NOTARY_PROFILE=<이름>`)에 적는다. 저장소에는 올라가지 않는다.

`SKIP_NOTARIZE=1 make release` 는 로컬 점검용이다. `dist.noindex/` 에 빌드만 하고
아무것도 올리지 않는다. 그렇게 만든 DMG 는 남에게 주면 안 된다 — Gatekeeper 가 막는다.

### 이 앱에만 해당하는 것

- **샌드박스는 켜면 안 된다.** 샌드박스 안에서는 `CGEventTap` 과 `hidutil` 이
  동작하지 않는다. Developer ID 배포는 샌드박스를 요구하지 않는다. 앱스토어만
  요구한다.
- **하드닝 런타임에 entitlement 가 하나 필요하다.** Spotify·YouTube Music 미디어 단축키가 Apple
  Event 를 보내므로 `com.apple.security.automation.apple-events` 를 붙인다.
  `Config/CapsLockControl.entitlements` 에 있다. 나머지 — 이벤트탭, IOKit Caps
  Lock 상태, `hidutil` 과 `git` 실행 — 는 하드닝 런타임에서 그대로 동작한다.
- **자동 업데이트는 없다.** Sparkle 은 외부 의존성이고 이 프로젝트에는 외부
  의존성이 없다. 업데이트는 새 DMG 를 받는 것이다.
- **저장소는 공개여야 한다.** 비공개 저장소의 릴리스 파일은 인증 없이 받을 수 없다.

## 왜 이렇게 만들었나

### 왜 event tap 만으로는 안 되는가

Caps Lock 의 토글과 LED 는 세션 event tap 보다 **아래 계층(HID 드라이버)** 에서
처리된다. event tap 에서 이벤트를 버려도 LED 는 켜지고 caps 상태는 바뀐다. 게다가
macOS 는 Caps Lock 에 hold-delay 를 걸기 때문에 레이어 키로 쓰면 반응이 눈에 띄게
느리다. Karabiner 가 가상 HID 드라이버를 만드는 이유가 이것이다.

### 이 앱의 방식: HID 리맵 + 얇은 event tap

드라이버를 만드는 대신 Apple 이 제공하는 `/usr/bin/hidutil` 의 `UserKeyMapping` 을 쓴다.

| 물리 키 | HID 리맵 후 | 처리 주체 |
|---|---|---|
| Caps Lock | F19 | 이 앱의 event tap (레이어) |
| Right Command | F18 | macOS 입력 소스 단축키 (선택 · `rightCommand.action`) |
| fn | Left Control | macOS (선택 · `modifiers.swapFnAndLeftControl`) |
| Left Control | fn | macOS (선택 · 위와 한 쌍) |

fn 스왑은 기본적으로 꺼져 있고 설정 창에서 켠다. Apple 키보드(내장·Magic Keyboard)
에서만 동작한다. fn 은 일반 키보드 usage page 가 아니라 Apple vendor top case
page(0xFF) 에 있는데, hidutil 이 그 페이지도 다룬다. 양방향 두 줄을 함께 걸어야
한다. 한쪽만 걸면 두 키가 모두 Control 이 된다.

이렇게 하면 event tap 이 **모디파이어를 전혀 다루지 않는다.** 이벤트 합성도, 플래그
조작도, 재진입 방지도 필요 없다. 남는 일은 "F19 눌림 추적"과 "레이어가 켜져
있을 때의 일반 키 처리"뿐이다.

성질:

- private API 아님, 커널 확장 아님
- 영구 설정이 아니다. 재부팅/로그아웃하면 사라진다
- 앱 종료(⌘Q, SIGTERM 포함) 시 자동으로 원복한다
- 명령 실행 시점에 붙어 있던 키보드에만 적용된다 → 새 키보드가 붙으면 다시 건다

### 강제 종료 후 복구

앱이 크래시하면 매핑이 남는다. Caps Lock 이 아무 일도 하지 않는
상태가 되며(키보드가 잠기지는 않는다), 아래 명령으로 즉시 복구된다.

```
make reset-hid
# 또는
hidutil property --set '{"UserKeyMapping":[]}'
```

앱 안의 "HID 매핑 강제 해제" 버튼도 같은 일을 한다. 재부팅해도 원복된다.

## 설정 파일

`~/Library/Application Support/CapsLockControl/shortcuts.json`

처음 실행할 때 **비어 있는 상태로** 만들어진다. 단축키는 사람마다 쓰는 앱이 달라서
미리 채워 두면 대부분 지우는 일부터 해야 한다. 키보드를 바꾸는 설정
(fn ↔ 왼쪽 Control 스왑)도 꺼진 채로 시작한다. 설정 파일에 없는 항목이 조용히
키보드를 바꿔 버리면 안 된다.

```json
{
  "version": 1,
  "defaults": {
    "whenAlreadyActive": "hide",
    "unmappedKeyPolicy": "swallow",
    "capsLockTapTogglesCapsLock": true,
    "layerTapTimeoutMilliseconds": 250
  },
  "rightCommand": { "action": "none" },
  "modifiers": { "swapFnAndLeftControl": false },
  "layers": {
    "capsLock": {
      "c": { "type": "application",
             "bundleIdentifier": "com.google.Chrome",
             "displayName": "Google Chrome" },
      "left": { "type": "media", "command": "previous", "target": "system" }
    }
  }
}
```

- 키 식별자
  - 알파벳/숫자: `a`~`z`, `0`~`9`
  - 기호: `grave` `minus` `equal` `leftBracket` `rightBracket` `backslash`
    `semicolon` `quote` `comma` `period` `slash`
  - 방향키: `left` `right` `up` `down`
  - 기타: `space` `return` `tab` `delete` `escape`
  - 기호는 `","` `"."` `"/"` `"\\"` 처럼 문자로 써도 읽힌다(별칭). 다만 앱이
    저장할 때는 항상 이름 쪽으로 정리한다. JSON 에서 백슬래시를 이스케이프하는
    번거로움을 피하려는 것이고, 같은 물리 키에 두 항목이 생기지 않도록
    별칭으로 적힌 기존 항목은 지워진다.
- `whenAlreadyActive`: `nothing` | `hide` | `switchToPrevious` — 키마다 덮어쓸 수 있다
- `rightCommand.action`: `f18` | `none` (`none` 이면 오른쪽 ⌘ 를 건드리지 않는다)
- `media.command`: `playPause` | `next` | `previous`, `target`: `system` | `spotify` | `youTubeMusic`
- `modifiers.swapFnAndLeftControl`: fn ↔ 왼쪽 Control 맞바꾸기 (없으면 꺼짐)

**직접 고쳐도 된다.** 앱이 설정 폴더를 감시하고 있어서 저장하는 순간 다시 읽는다.
재시작할 필요가 없다.

안전 장치:

- 저장은 항상 atomic. 중간에 죽어도 파일이 반쪽으로 남지 않는다.
- 파일이 깨져 있으면 **지우지 않고** `shortcuts.broken-<시각>.json` 으로 보관한 뒤
  기본값으로 시작한다.
- 파일 버전이 앱보다 높으면 읽기 전용으로 다룬다. 다른 Mac 의 새 버전이 만든
  설정을 이 Mac 이 덮어쓰는 사고를 막는다.
- 모르는 키·레이어·동작 타입을 만나도 죽지 않는다. 그 항목만 건너뛰고 경고로 남긴다.

## 다른 앱의 단축키 부르기 (keyStroke)

이 앱이 키 조합을 대신 눌러 주는 동작이다. 그 조합을 전역 단축키로 등록해 둔
앱이 평소처럼 반응한다.

```json
"a": {
  "type": "keyStroke",
  "key": "a",
  "modifiers": ["control", "option", "shift"],
  "label": "노이즈 캔슬링 토글"
}
```

**왜 필요한가.** Caps Lock 은 이 앱에서 F19 로 바뀌기 때문에 다른 앱이 "Caps+A" 를
직접 등록할 수 없다. 그래서 Caps+A 를 이 앱이 받아서 ⌃⌥⇧+A 를 발생시키고,
받는 앱은 원래대로 ⌃⌥⇧+A 를 등록해 둔다.

**왜 통하는가.** `RegisterEventHotKey`(Carbon) 로 등록된 단축키는 WindowServer 가
이벤트 스트림을 보고 판정한다. 우리가 만든 이벤트도 수정자 플래그가 맞으면
하드웨어로 누른 것과 똑같이 처리된다.

**무한 루프 방지.** 우리가 만든 이벤트는 우리 event tap 에도 다시 들어온다.
표시를 남기지 않으면 Caps+A → 조합 발생 → 탭이 다시 잡음 → 또 발생 이 끝없이
반복된다. 그래서 모든 합성 이벤트의 `eventSourceUserData` 에 표시를 박고, 탭은
그 표시를 보면 손대지 않고 흘려보낸다.

GUI 에서는 빈 키를 클릭해 앱 피커를 열고 맨 아래 "키 조합 보내기" 칸을 클릭한 뒤
원하는 조합을 누른다.

## Caps Lock 단독 탭

Caps Lock 을 **다른 키와 조합하지 않고 짧게** 눌렀다 떼면 원래 기능(대문자 고정)이
동작한다. 조합해서 쓰면 레이어, 혼자 톡 치면 Caps Lock 이다.

판정은 두 조건을 모두 만족해야 한다.

- 누르고 있는 동안 **다른 키를 하나도 쓰지 않았다** (상태 기계가 기억한다)
- 누른 시간이 `layerTapTimeoutMilliseconds`(기본 250ms, 설정 › 고급 에서 100~600ms) 이내다

시간 조건이 필요한 이유는, 레이어를 켰다가 마음이 바뀌어 그냥 뗀 경우와
구분해야 하기 때문이다.

CGEvent 로 Caps Lock 키를 합성해도 소용없다. Caps Lock 토글은 HID 계층에서
처리되기 때문이다 — event tap 으로 Caps Lock 을 막지 못하는 것과 같은 이유다.
대신 IOKit 공개 API(`IOHIDSetModifierLockState`) 로 상태를 직접 바꾼다.

## 앱 토글 (이미 맨 앞일 때)

같은 단축키를 다시 눌렀을 때의 동작이다. Keyboard Maestro 의 Toggle 과 같은 개념.

| 값 | 동작 |
|---|---|
| `hide` (기본) | ⌘H 와 같다. macOS 가 알아서 다음 앱을 앞으로 가져온다 |
| `switchToPrevious` | 이 앱 직전에 앞에 있던 앱으로 되돌아간다. 기록이 없으면 `hide` 로 폴백 |
| `nothing` | 아무것도 안 한다 |

`hide` 를 기본값으로 둔 이유는 상태를 안 들고 있어서다. 직전 앱을 기억하는 방식은
그 앱이 종료됐거나 중간에 다른 앱을 거쳤을 때 기록이 어긋날 수 있다.

**연타 억제**: 앱 활성화가 비동기라서 아주 빠르게 두 번 누르면 두 번째 판정 시점에
아직 frontmost 가 안 바뀌어 있을 수 있다. 그러면 토글이 타이밍에 따라 먹기도 하고
안 먹기도 한다. 그 애매함을 없애려고 같은 앱에 대한 250ms 이내 재입력은 무시한다.

## 미디어 제어

`target: "system"` (기본) 은 하드웨어 미디어 키와 똑같은 시스템 이벤트를 만들어 보낸다
(IOKit 공개 헤더 `ev_keymap.h` 의 `NX_KEYTYPE_*`). macOS 가 "지금 재생 중인 앱"에게
전달하므로 Spotify 가 재생 중이면 Spotify 가 받는다. 권한이 따로 필요 없고
Apple Music 으로 갈아타도 그대로 동작한다.

`target: "spotify"` 는 Spotify 에만 AppleScript 로 직접 명령한다. 무엇이 재생 중이든
항상 Spotify 를 제어하지만 처음 한 번 자동화 권한을 물어본다. Spotify 가 실행 중이
아니면 실행시키지 않고 그냥 알려 준다.

**브라우저가 미디어 키를 가로채면 `spotify` 를 쓴다.** "지금 재생 중인 앱" 에는
크롬이나 사파리의 유튜브 탭도 들어간다. 그래서 `system` 이면 유튜브가 Spotify 만큼
쉽게 재생/일시정지를 받아 간다. `spotify` 는 유튜브를 건드리지 않는다.

`target: "youTubeMusic"` 은 Chrome 의 YouTube Music 탭에만 직접 명령한다. 모든 창에서
`https://music.youtube.com/` 탭을 찾아(뒤에 깔린 탭도 된다) 플레이어 바의
재생/일시정지·다음·이전 버튼을 자바스크립트로 누른다. 사람이 클릭한 것과 같다.
다른 유튜브 탭은 반응하지 않는다. 처음 한 번 두 가지가 필요하다:

- **Chrome › 보기 › 개발자 › Apple Events의 자바스크립트 허용.** 프로필마다 따로인
  설정이라 YouTube Music 을 연 프로필의 창에서 켠다.
- Google Chrome 에 대한 자동화 권한 질문에 허용.

Chrome 이 꺼져 있거나 YouTube Music 탭이 없으면 탭을 열지 않고 그냥 알려 준다.
버튼 찾기는 YouTube Music 화면 구조에 기대므로, 깨지면 로그에 못 찾은 선택자가 남는다
(`/usr/bin/log show --predicate 'subsystem == "dev.itaehyeok.CapsLockControl" AND category == "Media"' --last 10m`).
전체 경로로 써야 한다. zsh 에서는 `log` 가 셸 내장 명령이라 `/usr/bin/log` 를 조용히 가린다.

바꾸는 곳은 둘이다:

- **단축키 하나** — Key Layout 에서 키를 고르고 *보낼 곳* 선택기를 쓴다.
  그 아래에 나머지 미디어 단축키도 같이 옮길지 묻는 버튼이 나온다.
- **새로 만들 것** — 설정 › 고급 › 미디어 키 에서 앞으로 만드는 단축키의 대상을 정한다.
  이미 만든 것이 다른 곳을 보고 있으면 경고하고 한 번에 옮겨 준다.

MediaRemote 같은 private framework 는 쓰지 않는다.

## 창 구성

```
┌─ [ Key Layout ] [ Status ] ─────────────────────┐  ← 탭 (타이틀바)
│ CapsLock Control                   [Caps] 정지 ⚙│  ← 항상 보이는 헤더
│ 동작 중 · 단축키 28개                            │     레이어 표시등은 실시간
├─────────────────────────────────────────────────┤
│                           Used 28  Available 28 │
│                                                 │
│ esc `  1 2 3 4 5 6 7 8 9 0  -  =  [delete]      │
│ [tab]  Q W E R T Y U I O P  [  ]  \             │
│ [caps ]  A S D F G H J K L  ;  '  [return]      │
│ [ shift ]  Z X C V B N M  ,  .  /  [ shift ]    │
│ fn ctrl opt cmd [== space ==] cmd opt     ←↑↓→  │
└─────────────────────────────────────────────────┘
```

- **실제 맥북 배치**를 따른다. tab / caps / shift / return / delete 가 제자리에 있고
  너비도 실제 비율(tab 2u, shift 2.5u, space 5u …)이다. 스페이스는 맥북처럼
  C 왼쪽 모서리에서 M 오른쪽 모서리까지다. 방향키는 네 개 모두 반 높이인
  역T자이고 ← ↓ → 가 바닥에 나란히 붙는다.
- shift·option 처럼 **단축키로 쓸 수 없는 키도 늘 회색으로** 그려서 무엇이
  리맵돼 있는지 보여 준다(오른쪽 command 는 `→ F18`, fn/control 은 스왑 상태).
- 두 레이어가 **같은 키보드 뷰를 공유**한다. 레이어를 바꾸면 키캡에 넘기는
  `action` 만 달라진다.
- 키캡에는 키 문자 · 앱 아이콘 · 앱 이름(두 줄까지)이 들어간다.
  빈 키는 점선 테두리 + `+`.
- 설치되지 않은 앱은 빨간 테두리와 **Missing** 으로 표시된다.
- 권한 경고 · 충돌 경고 · 엔진 시작/정지 · 레이어 표시등은 탭 밖에 있어서
  어느 탭에 있어도 보인다.

키캡의 앱 이름은 줄이지 않고 전체 이름을 그대로 쓴다. 첫 단어만 쓰면
"Google Chrome" 이 "Google" 이 되고, 마지막 단어만 쓰면
"Microsoft Remote Desktop Beta" 가 "Beta" 가 된다. 어느 휴리스틱도 맞지 않아서
두 줄까지 쓰고 넘치면 말줄임한다.

## 단축키 편집

키캡을 클릭해서 편집한다. 설정 파일을 직접 고치는 방법도 계속 유효하다.

| 조작 | 결과 |
|---|---|
| **빈 키 클릭** | 앱 피커가 바로 열린다 |
| **할당된 키 클릭** | 상세 패널 (변경 / 삭제 / 이미 맨 앞일 때 동작) |
| **키캡을 다른 키로 드래그** | 두 키의 동작이 **맞바뀐다**. 빈 키로 끌면 이동이 된다 |
| 삭제 | 즉시 Available |

### 앱 피커

경로나 bundle ID 를 직접 입력하지 않는다. 목록에서 고르기만 하면 된다.
검색은 Enter 없이 **한 글자 칠 때마다** 걸러지고, `localizedName` 과
`bundleIdentifier` 를 대소문자 구분 없이 부분 일치로 본다.

- **실행 중** — `NSWorkspace.runningApplications` 중 `activationPolicy == .regular`
  인 것만. 메뉴바 전용 앱과 백그라운드 프로세스는 뺀다. 다만 **이 앱 자신은 따로
  넣어 준다** — 자기 창을 열고 닫는 단축키를 거는 건 정상적인 용도라서다.
  앱을 켜고 끄면 목록도 따라 바뀐다.
- **설치됨** — 실행 중이 아닌 앱에도 단축키를 걸 수 있어야 하므로 함께 보여 준다.
  처음 피커를 열 때 한 번만 훑고(백그라운드), 실행 중 목록과 겹치는 것은 뺀다.
- **미디어** — Play/Pause · Next · Previous.
- **이미 할당된 앱 숨기기** 는 기본으로 켜져 있다. 대부분은 새 앱을 찾으러 오지,
  이미 건 앱을 다시 찾으러 오지 않는다. 몇 개가 숨겨졌는지도 보여 준다.
- 고르려는 앱이 같은 레이어의 다른 키에 이미 걸려 있으면 `이미 C` 처럼 알려 준다.

### 충돌

이미 쓰는 키에 다른 동작을 넣으려 하면 무엇이 무엇으로 바뀌는지 보여 주고 묻는다.

```
Caps + C 는 현재 Google Chrome 에 할당되어 있습니다.
Safari 으로 교체할까요?              [취소] [교체]
```

드래그로 옮기는 것은 **맞바꾸기**라서 아무것도 잃지 않는다. 그래서 확인을 묻지 않는다.

### 개발용 플래그

클릭 자동화 없이 앱 피커 모양을 확인할 때 쓴다. DEBUG 빌드만.

```
open build/Build/Products/Debug/CapsLockControl.app --args -openPicker q
```

## GitHub 설정 동기화 — Export / Import

집 Mac 과 회사 Mac 이 같은 설정을 쓴다. 설정 › 고급 › GitHub 동기화에 저장소 주소를 넣고 쓴다.

| 동작 | 하는 일 |
|---|---|
| **Export** | 지금 설정을 **시각 + Mac 이름이 붙은 새 스냅샷**으로 올린다. 기존 것은 지우지 않는다 |
| **Import** | 쌓인 스냅샷 중 하나를 고르고, 무엇이 달라지는지 본 뒤 **항목을 체크해서** 가져온다 |

```
<내 설정 저장소>/
  shortcuts.json                              ← 가장 최근 export (GitHub 웹에서 읽기용)
  snapshots/
    2026-09-14_153045_my-macbook.json
    2026-09-13_091201_my-imac.json
```

### 왜 자동 병합이 아닌가

처음에는 3-way 자동 병합으로 만들었다가 이 방식으로 바꿨다.

- **Export 는 지우는 게 없다.** 잘못 올려도 이전 스냅샷이 그대로 있어서 되돌리는 게
  Import 한 번이다. 병합은 결과를 덮어쓰므로 잘못되면 복구가 어렵다.
- **골라 가져오기가 더 강하다.** "회사 Mac 의 Caps+C 만 가져오기" 는 자동 병합이
  표현할 수 없다. 반대로 자동 병합이 하던 "양쪽 변경을 모두 살리기" 는
  체크박스를 전부 켜면 된다. 표현력이 상위 집합이다.
- **공통 조상을 추적하지 않는다.** 병합은 base 를 잘못 잡으면 조용히 틀린 결과를
  낸다. 이 방식엔 그 경로가 없다.

대가는 자동이 아니라는 것이다. 그래서 "내보낼 변경 있음" 을 상태로 알려 준다.

### Import 화면

스냅샷을 고르면 지금 설정과의 차이가 **새로 생김 / 바뀜 / 사라짐** 으로 묶여서,
git diff 처럼 **좌우로** 뜬다. 왼쪽이 지금 설정, 오른쪽이 스냅샷이고 한쪽에만 있는
항목은 그쪽 칸에만 그린다. 처음엔 전부 체크돼 있어서 그대로 누르면 전체 가져오기가
된다. `전체 선택` · `전체 해제` 버튼도 있다.

Import 는 이 Mac 의 설정만 바꾼다. GitHub 에는 아무것도 올리지 않는다.

적용 전에 백업할지 묻는다. "Export 하고 가져오기" 는 지금 설정을 스냅샷으로 먼저
올려서 Import 한 번으로 되돌릴 수 있게 해 준다. 어느 쪽을 고르든 로컬 백업 파일이
`~/Library/Application Support/CapsLockControl/backups/` 에 항상 남는다.

### 인증

토큰·비밀번호·SSH 키를 앱에 저장하지 않는다. 이미 이 Mac 에 설정된 SSH 인증을
그대로 쓴다. 프롬프트로 멈추지 않도록 `GIT_TERMINAL_PROMPT=0` 과
`ssh -o BatchMode=yes` 를 걸고, 모든 git 호출에 타임아웃을 둔다. SSH 키가
ssh-agent 에 없으면 멈추지 않고 "인증 실패" 로 끝난다.

> GitHub 계정이 여러 개면 기본 키가 다른 계정일 수 있다. `~/.ssh/config` 의
> `Host` 별칭을 주소에 쓰자. 예: `git@github-personal:사용자/저장소.git`.
> 어느 계정으로 인증되는지는 `ssh -T git@github.com` 으로 확인한다.

### 저장소를 다루는 방식

- clone 은 `~/Library/Application Support/CapsLockControl/sync/` 에 두고 **버리는 작업
  공간**으로 취급한다. 설정 폴더 자체를 저장소로 만들지 않는 이유는, git 이 파일을
  갈아치우는 동안 앱의 파일 감시자가 중간 상태를 읽을 수 있기 때문이다.
- Export 전에 `reset --hard origin/<branch>` + `clean -fd` 로 원격에 맞춘 뒤
  새 스냅샷만 올린다. 그래서 우리 커밋은 항상 원격의 자손이고, push 가 거부되거나
  merge commit 이 생기지 않는다. 앞선 실패가 남긴 찌꺼기도 함께 정리된다.
- 커밋이 하나도 없는 새 저장소도 처리한다. `rev-parse --abbrev-ref HEAD` 는 그때
  실패하므로 브랜치 이름은 `symbolic-ref --short HEAD` 로 읽고,
  `origin/<branch>` 가 없으면 reset 을 건너뛴다.
- 스냅샷은 자동으로 지우지 않는다. 하나에 4KB 남짓이라 쌓여도 문제가 되지 않고,
  이력을 지우는 것이야말로 이 방식의 장점을 없애는 일이다.

## 구조

```
CapsLockControl/
  Core/     AppKit 의존 없는 순수 로직. 유닛 테스트 대상.
    KeyCode.swift            가상 키코드 ↔ 문자열 식별자 표
    LayerKey.swift           capsLock
    ShortcutAction.swift     application / media / keyStroke / (확장 자리)
    BindingTable.swift       키코드로 정규화된 조회 표
    AppConfiguration.swift   디스크 스키마 + version/migration
    ConfigStore.swift        atomic 저장 · 손상 파일 백업 · 폴더 감시
    ConfigDiff.swift         Import 용 항목 단위 비교
    LayerStateMachine.swift  눌림·뗌 순서를 다루는 순수 상태 기계
    EngineOptions.swift      설정에서 뽑아낸 엔진 동작 방식
    UnmappedKeyPolicy.swift  등록되지 않은 키 정책 (기본: 삼킴)
  Engine/   시스템과 맞닿는 부분
    HIDRemapper.swift        hidutil 래핑 + 키보드 핫플러그 재적용
    EventTapController.swift 전용 스레드 위의 CGEventTap, 꺼지면 자동 재활성화
    KeyboardEngine.swift     탭 ↔ 상태 기계 ↔ 실행 연결
    ActionExecutor.swift     앱 실행/활성화/토글 (MainActor)
    CapsLockState.swift      진짜 Caps Lock 상태를 읽고 쓴다
    MediaController.swift    시스템 미디어 키 · Spotify AppleScript · YouTube Music 탭
    YouTubeMusicScript.swift YouTube Music 탭용 AppleScript/자바스크립트, 결과 해석
    KeyStrokeSender.swift    다른 앱의 전역 단축키를 부르는 합성 이벤트
    FrontmostAppTracker.swift 직전 앱 기록
    GitSync.swift            시스템 git 으로 export / import
    DefaultConfiguration.swift 첫 실행 시의 빈 설정
  App/      SwiftUI 진입점 · AppDelegate · EngineModel · SyncController
  UI/       키보드 에디터, 피커, 설정, 메뉴바
```

### 스레드 규칙

이벤트 탭 콜백은 **메인 스레드가 아닌 전용 스레드**에서 돈다. 메인 스레드가 잠깐이라도
막히면 탭이 타임아웃으로 꺼지면서 키보드 입력이 통째로 먹통이 되기 때문이다.
콜백 안에서는 락 아래 상태 갱신만 하고, 앱 실행 같은 일은 `Task { @MainActor }` 로 넘긴다.

### 상태 기계 불변식

- 삼켜서 keyDown 을 없앤 키는 keyUp 도 반드시 삼킨다 (레이어를 먼저 떼도 짝이 맞는다)
- 오토리핏 keyDown 은 동작을 다시 실행하지 않는다
- 레이어 키를 겹쳐 누르면 마지막에 누른 쪽이 이긴다
- 탭이 재활성화되면 눌림 상태를 전부 잊는다

## 아이콘

`Tools/make-icon.swift` 가 코드로 그린다. 바꾸려면 그 파일을 고치고
`make icon && make build`.

핵심은 **크기별로 디테일을 줄이는 것**이다. 512px 에서 괜찮은 그림을 그대로 16px 로
줄이면 얼룩이 된다. 처음엔 SF Symbol 키보드를 얹었는데 16~32px 에서 흐릿한
덩어리가 됐다. 지금은 초록 불이 켜진 스페이스 그레이 Caps Lock 키 하나를 그린다.
"caps lock" 글자는 읽히는 128px 이상에서만 새기고, 그보다 작으면 글자를 빼고 불을
키운다. 16px 에서는 불의 최소 크기를 지켜 초록 점으로라도 남긴다.

**주의**: 같은 경로에 다시 빌드하면 Finder 와 앱 안의 키캡이 옛 아이콘을 계속
보여 준다. LaunchServices 아이콘 캐시가 경로 단위로 잡고 있어서다.
`make refresh-icon-cache` 로 갱신한다.

## 기존 도구와의 공존

검증하는 동안에는 Karabiner 와 Raycast 를 지우지 않는다. 다만 같은 키를 두 도구가
동시에 가로채면 겹치므로, 테스트할 때는 Karabiner 에 **빈 프로필**을 만들어 잠시
전환한다 (Settings → Profiles → Add profile). 되돌리기가 한 번의 클릭이다.

이 앱은 다른 앱을 절대 자동 종료하지 않는다. 실행 중이면 창에 경고만 띄운다.
