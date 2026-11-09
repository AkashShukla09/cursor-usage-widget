# Cursor Usage

A macOS menu-bar app for the current Cursor billing cycle, or for Claude Code’s subscription limits. It stays out of the Dock and shows how much usage is left, without opening either dashboard.

Choose the source in Settings. Cursor shows the **Cursor Models** pool and the **Other Models** pool. Claude Code shows the 5-hour session, the weekly limit, per-model weekly limits when Claude reports them, and extra usage.

## Quick start

You need:

- macOS 14.6 or later
- A Swift toolchain that can build a macOS 14 package (Xcode or the Xcode command line tools)
- For Cursor: Cursor installed, opened at least once, and signed in
- For Claude Code: Claude Code installed and signed in (`claude`)

Build and open the app:

```bash
git clone https://github.com/AkashShukla09/cursor-usage-widget.git
cd cursor-usage-widget
scripts/build-app.sh
open CursorUsageWidget.app
```

The script builds a release binary and wraps it as `CursorUsageWidget.app` in the repo directory.

### First run

- The app has no Dock icon. Look for the usage label in the menu bar; it reads `Usage …` until the first fetch finishes.
- The app is not signed. If macOS refuses to open it, right-click the app and choose **Open**, or allow it under **System Settings → Privacy & Security**.
- It starts on Cursor. To see Claude Code instead, open **Settings** from the panel and change **Show usage for**.
- The first Claude Code fetch shows a keychain prompt for the `Claude Code-credentials` item. Choose **Always Allow** so later refreshes don’t ask again.

### Everyday use

- Click the menu-bar label to open the panel.
- **Refresh** fetches immediately, **Settings** opens the options below, and **Quit** closes the app.
- To start the app at login, move `CursorUsageWidget.app` to `/Applications`, open it from there, and turn on **Launch at login** in Settings.

### Troubleshooting

When a fetch fails, the label reads `Usage ?` and the panel shows the reason.

| Message | What to do |
| --- | --- |
| Cursor isn’t installed or hasn’t been opened yet. | Install Cursor, open it once, then refresh. |
| You’re not signed in to Cursor. / Not signed in to Cursor. | Sign in inside Cursor, then refresh. |
| Cursor’s saved session couldn’t be read. | Sign out of Cursor and back in, then refresh. |
| Not signed in to Claude Code. | Run `claude` in a terminal, sign in, then refresh. |
| Claude Code session expired. | Run `claude` once so it renews the session, then refresh. |
| Keychain access was denied. | Refresh and choose **Always Allow** on the keychain prompt. |
| Couldn’t reach Cursor. / Couldn’t reach Claude. | Check your connection, then refresh. |
| Cursor returned HTTP … / Claude returned HTTP … | Usually temporary; refresh later. If it persists, the service’s API may have changed. |

## What you see

The menu-bar label is one of:

- Cursor, compact: `C 42%  O 18%`
- Cursor, detailed: `Cursor 42% · Other 18%`
- Claude Code, compact: `S 42%  W 18%`, or `W 6%  Fable 11%` when Claude reports no 5-hour session
- Claude Code, detailed: `Session 42% · Week 18%`, or `Week 6% · Fable 11%`
- `Unlimited` on an unlimited Cursor plan
- `Usage …` while the first fetch is in progress, or `Usage ?` when the last fetch failed

The Claude label lists only the windows Claude returned: session (`S`), week (`W`), and any per-model weeks by model name. The label stays the normal menu-bar color until included usage reaches the warning threshold (80% by default), then turns amber. At 100% it turns red. The higher included pool, or the higher Claude window, sets the color.

The Cursor panel lists:

- Plan name, billing-cycle dates, and days left
- Cursor Models and Other Models, each with a percent and a bar
- On-demand status: off, or on with spend and the limit when Cursor reports one
- Models used this cycle, grouped as Cursor, Other, and Auto, with token count and dollar cost

Auto is listed on its own because a routed request can draw from either pool. The pool percents come from Cursor, not from adding up the model rows. If a plan does not include the Other Models pool, that row reads “Not included” and the compact label shows `n/a`.

The Claude Code panel lists the plan name and one row per limit window, with a reset time, plus extra usage. Claude’s usage endpoint does not include a per-model token breakdown.

## Settings

Open **Settings** from the panel.

- **Show usage for** Cursor or Claude Code. Switching sources refreshes immediately.
- **Refresh every** 1–60 minutes (default 15). The app also fetches once when it launches, and **Refresh** fetches immediately.
- **Warn at** 0–100% (default 80). Red still starts at 100%.
- **Menu bar** compact or detailed.
- **Launch at login.** This uses the system login item and needs the app in `/Applications`.

## Command-line snapshot

Print a text snapshot and exit:

```bash
CursorUsageWidget.app/Contents/MacOS/CursorUsageWidget --status
CursorUsageWidget.app/Contents/MacOS/CursorUsageWidget --status --source claude
CursorUsageWidget.app/Contents/MacOS/CursorUsageWidget --status --source cursor
```

`--status` uses the saved source. `--source cursor` or `--source claude` overrides it for that run. The Cursor snapshot includes the plan, cycle dates in UTC, days left, both pools, on-demand spend, and one line per model. The Claude snapshot includes the plan, each limit window, and extra usage.

## Tests

```bash
swift test
```

## Where the numbers come from

For Cursor, the app reads `cursorAuth/accessToken` from Cursor’s local database:

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`

It sends that session only to `cursor.com` and `api2.cursor.sh`, over HTTPS. The token stays in memory for the refresh loop and is not written to logs.

For Claude Code, the app reads the `Claude Code-credentials` item from the login keychain with the `security` command. macOS asks once for keychain access; choose **Always Allow**. The access token is sent only to `api.anthropic.com`, over HTTPS, and is not written to logs. The app does not refresh the token. If the session has expired, run `claude` once, then refresh.

This is not an official Cursor or Claude app. It depends on current local storage and dashboard APIs, so an update to either app can change or break the numbers it shows.
