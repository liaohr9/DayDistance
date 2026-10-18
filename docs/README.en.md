<div align="center">
<img src="images/icon.png" width="112" alt="DayDistance orange hourglass icon" />
<h1>DayDistance · 日距</h1>
<p><strong>Give anticipation a date. Give memories a measure.</strong></p>
<p>A native macOS day counter with desktop widgets. Local, simple, and open source.</p>
<p><a href="https://github.com/liaohr9/DayDistance/releases/tag/v1.13.0-preview.1">Download preview</a> · <a href="../README.md">中文</a> · <a href="BUILDING.md">Build guide</a></p>
</div>

![Native event list with six fictional examples in English](images/events-en.png)

> **1.13.0 (39) is an unnotarized developer preview for Apple Silicon.** The App ZIP uses ad hoc signing, without a Developer ID certificate or Apple notarization. macOS may block downloaded builds. This is not a notarized production release; wait for a notarized version or build from source if blocked. No system-security changes are required or recommended.

## App language

Choose **简体中文** or **English** in **Settings → General → Language**. The change applies immediately across open app windows and app commands, without restarting or discarding an editor draft. Event names and tags stay unchanged, and regional date/time conventions are preserved. Included in the 1.13.0 preview; earlier installations require one manual upgrade.

## What it does

- Counts down to future dates and counts up from past dates. Choose day zero or day one for elapsed days.
- Supports all-day events, annual anniversaries, pinning, sorting, search, and day/week/calendar/anniversary formats.
- Small widget for one event; medium widget for up to three events with manual slots. Customize icon, date, and precise-clock visibility independently.
- One-time, daily, monthly, and yearly reminders with separate times. Monthly/yearly milestones follow the original event date.
- Archive, trash, restore, duplicate, multi-select, batch actions, and undo/redo.
- Full JSON import/export and up to 20 local recovery snapshots.
- Native keyboard shortcuts, optional Vim keys and menu bar, Chinese/English, and Dock icon appearance.

No accounts, subscriptions, advertisements, telemetry, or cloud sync. Events stay on your Mac.

## Get started

1. Download the **Apple Silicon preview ZIP** from [Releases](https://github.com/liaohr9/DayDistance/releases/tag/v1.13.0-preview.1). Requires Apple Silicon (arm64) and macOS14+. Tested on macOS27; other supported versions still need runtime testing.
2. Move `日距.app` into Applications, subject to the preview limitations above.
3. Press `⌘N`, enter a name and date, and save. Disable All Day to specify a time.
4. Right-click the desktop, choose Edit Widgets, and add DayDistance. Edit the widget to select events and presentation.

Before upgrading, export your events, save/cancel current editing, and quit the old build. Keep only one installed app. Checksums are available as `SHA256SUMS.txt` in the Release.

## Smart Lists (1.11 source)

Click ＋ beside Smart Lists in the sidebar. Add field / comparison / value rows and match all or any conditions. Combine titles, complete tags, date status, days away, date ranges, pinning, and yearly repetition. Counts update as you edit. Sort & Skip stays collapsed until needed.

Choose Smart Lists as a widget’s Content Source, then select a named list. Multiple widgets can reuse its rules. Appearance offers Standard, Compact, or Custom; Custom reveals icon, date, and precise-clock switches. Existing selections, manual slots, and active legacy filters remain intact. Unavailable rules show an error rather than displaying all events.

Rules have their own local storage and 20 recovery snapshots. Explicit recovery preserves damaged bytes and rejects newer formats. **Event JSON exports do not include Smart Lists.** Included in the 1.13.0 preview.

## Widgets

**Included in this preview:** tags, native custom colors, independently filtered widgets, and a large widget with 5–10 events per page.

Use comma-separated tags in the event editor; search matches names and tags. Display → Icon & Color → Custom Color… opens the native macOS color wheel and sliders. Five colored presets remain available.

Each widget independently supports date scope, all/any included tags, excluded tags, sorting, pinned priority, and skipping the first N results. Conditions apply before sorting, skipping, and pagination. To start from the second-nearest event, choose Nearest, disable pinned priority, and skip 1. Manual medium slots keep their explicit order. Large widgets show 5–10 events per page with previous/next buttons; scrolling and swiping are not supported. Widgets with identical filters, sorting, and page size share a page position; different settings keep separate positions.

Opening older data does not migrate it automatically. Saving in 1.9 writes schema 7, which 1.8 and earlier cannot read. Export a backup before downgrading.


![English small, medium, and dark widget views in a native showcase](images/widgets-en.png)

This image uses production SwiftUI widget content with fictional events in a native showcase window. It is not a desktop placement screenshot or an integration-test claim.

The small widget uses one selected event or automatic selection. Medium widgets show an automatic overview or three manual slots in the configured order. Archived/trashed events are excluded. An unavailable explicit event shows an explanation rather than silently switching to another event.

## Reminders

Open the Reminders tab in the editor to enable daily, monthly, or yearly notifications. Each has its own time. A June10 event reaches a new monthly milestone on the10th and a yearly one on June10. Short months use their last available day; leap-year dates return when available.

Permission is requested only when saving an enabled reminder. Settings show current system permission, the next actually scheduled reminder, and daily coverage. Permission changes are checked automatically while Settings are visible and when reactivated.

Background renewal is optional and off by default. Enable it and approve the macOS background item if required to renew the finite queue hourly after the app quits. Sleep, shutdown, Focus, permission and OS scheduling may affect delivery. End-to-end delivery and ongoing background behavior need additional testing across supported systems.

The main window hides the finite-coverage notice when background renewal is enabled, actual startup has been confirmed, and registration recovery has no reported error. It remains visible when background renewal is off or awaiting approval. Permission, scheduling and capacity errors remain visible. Each cold launch rebuilds an enabled background registration once, including after same-version replacement; interrupted recovery is retried on the next launch. Disabled background items are never opted in automatically.

Replacing an ad hoc development build can still encounter an AMFI launch-signing constraint rejection even while the system switch is enabled. The 1.8.2 source verifies execution, retries and retains failure messages. Recovery of every unsigned preview is not guaranteed; the observed constraint failure still needs verification with Developer ID signing.

## Keyboard and data

`⌘N` new · `⌘F` search · `⌘E` edit · `⌘D` duplicate · `⌘⇧A` archive · `⌘⇧R` restore. Use Command/Shift-click for selection and the usual Undo/Redo shortcuts.

Vim keys operate only in the list: `j/k`, `gg/G`, `/`, `v`, `Space`, `i`, `o`, `dd`, `u`, `Ctrl-r`. Text fields and dialogs retain native input.

Preview data: `~/Library/Application Support/DayDistanceLocal/events.json`. Use File → Export/Import Events for full JSON backups. Current writes use schema 7; schemas 1–7 can be read. Do not downgrade after saving the new format. Formal signed builds use an App Group and require export/import migration from preview data.

## Build and contribute

Full Xcode26+ (Icon Composer assets), Python3, and Git are required; this preview was built with Xcode27. There are no third-party runtime packages.

```bash
git clone https://github.com/liaohr9/DayDistance.git
cd DayDistance
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
bash script/build_and_run.sh --build-only
```

Output: `build.noindex/Build/Products/DebugLocal/DayDistance.app`. See [BUILDING](BUILDING.md) for preview commands and formal-signing gates. The 139 core tests do not substitute for complete widget, VoiceOver, notification-delivery or OS-compatibility acceptance.

[Contributing](../CONTRIBUTING.md) · [Changelog](../CHANGELOG.md) · [Privacy](../PRIVACY.md) · [MIT License](../LICENSE)

## 1.10 source: settings organized by task

Settings has four sidebar categories: General, Notifications & Background, Data & Backups, and Widgets. File operations reuse the existing workflow and are disabled during editing. Widget diagnostics and troubleshooting expand on demand.

The event editor has Basics, Reminder, and Display tabs sharing one draft, with fixed Cancel and Save buttons. Yearly date repetition and anniversary notifications are separate. Counting explains day 0 versus day 1.

Widget configuration shows controls for the current size and content mode. More Filters reveals tags, exclusions, and skipping; active conditions always stay visible. Existing event IDs, display preferences, filtering, and page-sharing behavior are retained. Included in the 1.13.0 preview.

### Performance and simpler editing

Basics prioritizes the name and date. Tags and yearly rules are in More Options, expanded automatically for existing rules. One color menu includes colored swatches and the native color wheel. Help has five collapsible topics; widget checks live in Settings. Calendar summaries refresh at relevant boundaries, while only precise clocks tick every second. Reminder previews reuse scheduling rules without generating the full notification queue.

## In-app updates

Open **Settings → Software Update** to toggle automatic checking, or choose **DayDistance → Check for Updates…**. While the app is open, Sparkle checks the signed GitHub feed daily. It asks before downloading and installing, verifies the feed and ZIP, then installs and reopens DayDistance. Editing and file operations defer installation. No event data is sent. Update signatures do not replace Developer ID signing or notarization.

This feature starts with 1.13.0; earlier downloads need one manual upgrade. The signed feed and release archive must be published together before online updates work.
