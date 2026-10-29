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
cd ReviewNagger
swift build
swift run
```
Or open `Package.swift` in Xcode (it will pull GCDWebServer).

The app runs as a menu-bar app (no Dock icon). Look for the bell icon.

### 2. Configure (optional)
Right-click the menu bar icon:
- **Set GitHub Username** — only trigger on `review_requested` events for you
- **Set Webhook Secret** — enables signature verification

### 3. Expose the webhook
The server listens on **port 8080** on all interfaces.

For GitHub to reach your machine you need a tunnel:
```bash
# Example with ngrok
ngrok http 8080
```
Then in your GitHub repo → Settings → Webhooks → Add webhook:
- Payload URL: `https://your-ngrok-url.ngrok.io/webhook`
- Content type: `application/json`
- Secret: (same as you set in the app, or leave blank)
- Events: **Pull requests** (or "Send me everything" and the app filters)

### 4. Test
Use the menu item **Simulate New PR** to see the escalation without a real webhook.

You can also `curl` a fake payload locally:
```bash
curl -X POST http://localhost:8080/webhook \
  -H "Content-Type: application/json" \
  -d '{"action":"opened","pull_request":{"title":"Test PR","html_url":"https://github.com","number":1},"repository":{"full_name":"you/repo"}}'
```

## Notes
- Pending items are persisted to `~/Library/Application Support/ReviewNagger/pending.json`
- Meeting detection uses a Zoom UDP-port heuristic + process check. Google Meet detection is basic.
- Fullscreen is skipped while a meeting is detected.
- The orange overlay is click-through so you can still work.
- Acknowledge / Open / Snooze from any window or notification to stop the escalation.

## Extending
- Add more events (issues, comments, etc.) in `WebhookServer.parseGitHubWebhook`
- Tune intervals in `EscalationLevel.intervalMinutes`
- Make the overlay colors / messages more aggressive
- Add sound files that get louder

Built for people who need a little (or a lot of) external pressure to review code.
