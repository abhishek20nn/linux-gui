# Mobile YouTube Redirector (MV3)

An ultra-low-memory, high-performance Chrome extension built with Manifest V3 that redirects all desktop YouTube visits to Mobile YouTube (`https://m.youtube.com`), while eliminating ad-cuepoint buffering freezes, background tab pauses, and ad failures.

---

## Key Features

1. **Zero Persistent Extension RAM Overhead**:
   - Redirection and tracker blocking built directly into Chromium's native `chrome.declarativeNetRequest`.
   - Contains **no background service worker process**, consuming 0 MB idle memory.
   - Rules execute natively in Chromium's C++ network stack before requests leave the browser.

2. **Continuous Playback (Zero Cuepoint Buffering Freezes)**:
   - Eliminates mid-roll cuepoint stalls caused by mobile Server-Stitched Dynamic Ad Insertion (SSDAI) and SABR player `waitingforads` deadlocks.
   - Intercepts player responses across all channels (`window.ytInitialPlayerResponse`, `Response.prototype.json` for client-side SPA navigations, and `JSON.parse` for XHR/inline scripts).
   - Purges `playerAds`, `adPlacements`, `adSlots`, and `adBreakHeartbeatParams`, while setting `enableServerStitchedDai: false`.

3. **Background Tab Playback**:
   - Desktop YouTube continues playing when switching tabs; mobile YouTube normally pauses due to mobile OS power-saving heuristics on `visibilitychange`.
   - Preserves `document.hidden = false` and `document.visibilityState = 'visible'`, preventing background playback interruptions and spinning buffer circles.

4. **Preserved Ultra-Low Tab Memory Footprint**:
   - Preserves lean mobile buffer readahead (~20-30s) instead of ballooning video buffers.
   - Tab JS heap stays at ~10-35 MB (compared to 250-400 MB on desktop YouTube), saving ~85-90% system RAM.
   - Declarative CSS hides ad banners and promo clutter with zero layout reflow overhead.

5. **Loop Prevention via Mobile Header Injection**:
   - Spoofs Android User-Agent and Client Hints (`sec-ch-ua-mobile`, `sec-ch-ua-platform`) on requests to `m.youtube.com`, preventing 302 bounce loops back to desktop YouTube.

6. **URL Parameter Preservation**:
   - Automatically strips `app=desktop` while preserving video IDs (`v`), playlists (`list`), timestamps (`t`), and search queries (`search_query`).

---

## File Structure

```text
myoutube/
├── manifest.json        # Manifest V3 configuration with DNR ruleset & MAIN world content script
├── rules.json           # Native network redirection & DoubleClick tracker blocking rules
├── content.js           # Lightweight MAIN world script: response sanitization, Proxy ytcfg, stall watchdog
├── popup.html           # Dark-themed extension status popup
├── popup.css            # Styles for popup dashboard
├── popup.js             # Action handlers for popup buttons
├── icons/               # 16x16, 32x32, 48x48, 128x128 icons
├── verify_extension.js  # Verification suite (50 assertions)
├── test_playwright_suite.js # End-to-end Playwright integration test suite (28 assertions)
└── README.md            # Documentation and technical guide
```

---

## Technical Architecture

### 1. Declarative Net Request Rules (`rules.json`)
- **Rule 1 (Redirect)**: Redirects `youtube.com` and `www.youtube.com` to `https://m.youtube.com`, stripping `app=desktop`. Excludes `music`, `studio`, `tv`, `consent`, and `accounts` subdomains.
- **Rule 2 (Modify Headers)**: Injects mobile Android User-Agent and Client Hints for `m.youtube.com`.
- **Rules 3-5 (Block)**: Blocks DoubleClick and Google Ads telemetry (`googleads.g.doubleclick.net`, `pagead2.googlesyndication.com`, `ad_status.js`) in native C++ network stack with 0 MB JS overhead.

### 2. Main-World Content Script (`content.js`)
- Runs in `world: "MAIN"` at `run_at: "document_start"` to hook execution before YouTube's player boot.
- **Player Sanitizer**: Sanitizes `ytInitialPlayerResponse`, `Response.prototype.json`, and `JSON.parse` to remove ad cues before the SABR streaming engine can halt request pipelines.
- **ytcfg Proxy**: Sanitizes `WEB_PLAYER_CONTEXT_CONFIGS` and `EXPERIMENT_FLAGS` via an ES6 Proxy, ensuring dynamic config updates never re-enable SSDAI cuepoint requests.
- **Visibility Stub**: Prevents mobile video pause on tab backgrounding.
- **Safe Skip & Watchdog**: Fast-forwards short ad creatives (<= 90s) without risking skipping main videos, and gently nudges playheads if deadlocked for > 3.6s without entering seek storms.
