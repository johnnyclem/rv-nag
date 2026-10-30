# ReviewNagger

Nags you to do your MR/PR reviews (via webhooks) and gets more annoying the longer you put it off.

A macOS menu-bar app that listens for GitHub webhooks (PRs needing review) and escalates the annoyance of the notification the longer you ignore it.

## Escalation Stages
1. **Gentle Nudge** — soft local notification (immediate)
2. **Brighter Alert** — more prominent notification (after 25 min)
3. **Screen Windows** — floating alert window on every display
4. **Orange Overlay** — 15% opacity orange wash over all screens + windows
5. **Fullscreen** — full-screen takeover on all monitors  
   (automatically falls back to orange overlay if Zoom/Meet is detected)

## Setup

### 1. Build & Run
```bash
./scripts/bundle.sh          # builds build/ReviewNagger.app
open build/ReviewNagger.app
```
System notifications and "Launch at Login" need the app bundle. `swift run` also works for
quick testing, but without notifications (overlays and the menu still work).

The app runs as a menu-bar app (no Dock icon). Look for the bell icon; it shows the pending count.

### 2. Configure (optional)
Click the menu bar icon:
- **Set GitHub / GitLab Username** — only alert when a review is requested from *you*
  (and never for your own PRs). Leave blank to alert on every PR/MR.
- **Set Webhook Secret** — once set, deliveries must carry a valid GitHub `X-Hub-Signature-256`
  or a matching GitLab `X-Gitlab-Token`; unsigned requests get a 401.
- **Set Port** — defaults to 8080; the server restarts on change.
- **Launch at Login**

Each pending review has a submenu with **Open**, **Snooze 30 min** and **Dismiss**.

### 3. Expose the webhook
The server listens on **localhost only** (port 8080), so GitHub/GitLab need a tunnel:
```bash
ngrok http 8080
```
**GitHub** — repo → Settings → Webhooks → Add webhook:
- Payload URL: `https://your-ngrok-url.ngrok.io/webhook`
- Content type: `application/json`
- Secret: same as in the app (or blank)
- Events: **Pull requests** and **Pull request reviews**

**GitLab** — project → Settings → Webhooks:
- URL: `https://your-ngrok-url.ngrok.io/webhook`
- Secret token: same as in the app (or blank)
- Trigger: **Merge request events**

Nagging stops automatically when the PR/MR is closed or merged, you're removed as a reviewer,
it's converted to a draft, or you submit a review / approve it.

### 4. Test
Use the menu item **Simulate New PR** to see the escalation without a real webhook.

You can also `curl` a fake payload locally:
```bash
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{"action":"opened","pull_request":{"title":"Test PR","html_url":"https://github.com","number":1},"repository":{"full_name":"you/repo"}}'
```
Unit tests: `swift test`.

## Notes
- Pending items are persisted to `~/Library/Application Support/ReviewNagger/pending.json`
- Meeting detection uses a Zoom UDP-port heuristic + process check. Google Meet detection is basic.
- Fullscreen is skipped while a meeting is detected.
- The orange overlay is click-through so you can still work.
- Acknowledge / Open / Snooze from any window, notification or the menu to stop the escalation.
- Only one overlay is shown at a time (the most escalated non-snoozed item).

## Extending
- Add more events (issues, comments, etc.) in `WebhookParser` (`Sources/ReviewNaggerCore`)
- Tune intervals in `EscalationLevel.intervalMinutes`
- Make the overlay colors / messages more aggressive
- Add sound files that get louder

Built for people who need a little (or a lot of) external pressure to review code.
