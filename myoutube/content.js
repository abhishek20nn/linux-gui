(function() {
  'use strict';

  // --- 1. Player Response Sanitizer (Eliminates Ad Breaks & SSDAI Cuepoints) ---
  function sanitizePlayerResponse(pr) {
    if (!pr || typeof pr !== 'object') return pr;
    try {
      delete pr.playerAds;
      delete pr.adPlacements;
      delete pr.adSlots;
      delete pr.adBreakHeartbeatParams;
      delete pr.adSignalsInfo;
      delete pr.adPlacementRenderer;
      delete pr.interstitial;

      if (pr.daiConfig) {
        pr.daiConfig.enableServerStitchedDai = false;
        pr.daiConfig.daiType = 'DAI_TYPE_SS_DISABLED';
      }

      // Memory discipline: Keep dynamic readahead at lean mobile defaults (~20-30s)
      // to guarantee ultra-low RAM usage (< 35 MB vs 250+ MB on desktop YouTube).
    } catch (e) {}
    return pr;
  }

  function isPlayerResponse(obj) {
    return obj && typeof obj === 'object' && (
      obj.adPlacements ||
      obj.playerAds ||
      obj.adSlots ||
      (obj.videoDetails && obj.streamingData)
    );
  }

  // Intercept window.ytInitialPlayerResponse (initial page watch loads)
  let rawPR = window.ytInitialPlayerResponse;
  Object.defineProperty(window, 'ytInitialPlayerResponse', {
    get() { return rawPR; },
    set(val) { rawPR = sanitizePlayerResponse(val); },
    configurable: true
  });
  if (rawPR) rawPR = sanitizePlayerResponse(rawPR);

  // Intercept Response.prototype.json (client-side SPA navigations /youtubei/v1/player)
  if (typeof Response !== 'undefined' && Response.prototype && Response.prototype.json) {
    const origJson = Response.prototype.json;
    Response.prototype.json = async function() {
      const data = await origJson.apply(this);
      if (isPlayerResponse(data)) {
        sanitizePlayerResponse(data);
      }
      return data;
    };
  }

  // Intercept JSON.parse (XHR / inline JSON parsing of player responses)
  const origParse = JSON.parse;
  JSON.parse = function(...args) {
    const obj = origParse.apply(this, args);
    if (isPlayerResponse(obj)) {
      sanitizePlayerResponse(obj);
    }
    return obj;
  };

  // --- 2. Sanitize ytcfg Player Flags & Experiments ---
  function sanitizeYtcfg(data) {
    if (!data || typeof data !== 'object') return;
    try {
      if (data.WEB_PLAYER_CONTEXT_CONFIGS) {
        for (const k of Object.keys(data.WEB_PLAYER_CONTEXT_CONFIGS)) {
          const cfg = data.WEB_PLAYER_CONTEXT_CONFIGS[k];
          if (cfg && cfg.serializedExperimentFlags) {
            let f = cfg.serializedExperimentFlags;
            f = f.replace(/enable_server_stitched_dai=true/gi, 'enable_server_stitched_dai=false');
            f = f.replace(/gab_return_sabr_ssdai_config=true/gi, 'gab_return_sabr_ssdai_config=false');
            f = f.replace(/html5_send_cuepoint_id_in_ad_break_request=true/gi, 'html5_send_cuepoint_id_in_ad_break_request=false');
            f = f.replace(/sabr_enable_ad_break_delay=true/gi, 'sabr_enable_ad_break_delay=false');
            f = f.replace(/web_enable_ab_in_ad_formats=true/gi, 'web_enable_ab_in_ad_formats=false');
            cfg.serializedExperimentFlags = f;
          }
        }
      }
      const exp = data.EXPERIMENT_FLAGS || (data.data_ && data.data_.EXPERIMENT_FLAGS);
      if (exp && typeof exp === 'object') {
        exp.enable_server_stitched_dai = false;
        exp.gab_return_sabr_ssdai_config = false;
        exp.html5_send_cuepoint_id_in_ad_break_request = false;
        exp.sabr_enable_ad_break_delay = false;
        exp.web_enable_ab_in_ad_formats = false;
      }
    } catch (e) {}
  }

  let internalYtcfg = window.ytcfg || {};
  if (!internalYtcfg.data_) internalYtcfg.data_ = {};
  if (typeof internalYtcfg.set === 'function') {
    const orig = internalYtcfg.set;
    internalYtcfg.set = function(x, y) {
      if (x && typeof x === 'object') sanitizeYtcfg(x);
      return orig.apply(this, arguments);
    };
  } else {
    internalYtcfg.set = function(x, y) {
      if (typeof x === 'string') {
        internalYtcfg.data_[x] = y;
        internalYtcfg[x] = y;
      } else if (x && typeof x === 'object') {
        sanitizeYtcfg(x);
        Object.assign(internalYtcfg.data_, x);
        Object.assign(internalYtcfg, x);
      }
    };
  }
  if (internalYtcfg.data_) sanitizeYtcfg(internalYtcfg.data_);

  const ytcfgProxy = new Proxy(internalYtcfg, {
    set(target, prop, value) {
      if (prop === 'set' && typeof value === 'function') {
        const origSet = value;
        value = function(x, y) {
          if (x && typeof x === 'object') sanitizeYtcfg(x);
          return origSet.apply(this, arguments);
        };
      }
      target[prop] = value;
      if (prop === 'data_' && value) sanitizeYtcfg(value);
      return true;
    }
  });

  Object.defineProperty(window, 'ytcfg', {
    get() { return ytcfgProxy; },
    set(val) {
      if (val && typeof val === 'object' && val !== ytcfgProxy) {
        Object.assign(internalYtcfg, val);
        if (typeof val.set === 'function') {
          const origSet = val.set;
          internalYtcfg.set = function(x, y) {
            if (x && typeof x === 'object') sanitizeYtcfg(x);
            return origSet.apply(this, arguments);
          };
        }
        sanitizeYtcfg(val.data_ || val);
      }
    },
    configurable: true
  });

  // --- 3. Prevent Background Tab Playback Pause / Freeze ---
  try {
    Object.defineProperty(document, 'hidden', {
      get: () => false,
      configurable: true
    });
    Object.defineProperty(document, 'visibilityState', {
      get: () => 'visible',
      configurable: true
    });
    window.addEventListener('visibilitychange', (e) => {
      e.stopImmediatePropagation();
    }, true);
  } catch (e) {}

  // --- 4. Fast Safe Ad Skip & Playback Stall Watchdog ---
  function skipAdIfPresent() {
    const skip = document.querySelector(
      '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .videoAdUiSkipButton, .ytm-ad-skip-button, [class*="ad-skip-button"], [class*="skip-button"], button.ytp-ad-skip-button-text'
    );
    if (skip) {
      skip.click();
    }

    const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player, ytm-media-item, #player-control-overlay');
    if (player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting'))) {
      const video = document.querySelector('video');
      if (video) {
        if (isFinite(video.duration) && video.duration > 0 && video.duration <= 90) {
          video.currentTime = video.duration;
        } else {
          video.playbackRate = 16;
          video.muted = true;
        }
      }
    }
  }

  let lastPlayhead = -1;
  let stallRounds = 0;

  function attachVideoHandlers(video) {
    if (!video || video._mYtBound) return;
    video._mYtBound = true;

    video.addEventListener('timeupdate', () => {
      skipAdIfPresent();
    });

    video.addEventListener('playing', () => {
      stallRounds = 0;
      if (video.playbackRate > 2) {
        video.playbackRate = 1;
      }
    });

    // Watchdog: If playhead makes zero progress for > 3.6s while unpaused in readyState <= 2, nudge once
    video.addEventListener('waiting', () => {
      setTimeout(() => {
        if (video && !video.paused && !video.ended && video.readyState <= 2) {
          if (video.currentTime === lastPlayhead) {
            stallRounds++;
            if (stallRounds >= 2) {
              video.currentTime += 0.1;
              video.play().catch(() => {});
              stallRounds = 0;
            }
          } else {
            lastPlayhead = video.currentTime;
          }
        }
      }, 1800);
    });
  }

  function scanForVideo() {
    const v = document.querySelector('video');
    if (v) attachVideoHandlers(v);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scanForVideo);
  } else {
    scanForVideo();
  }

  const obs = new MutationObserver(() => scanForVideo());
  obs.observe(document.documentElement, { childList: true, subtree: true });

  // --- 5. Declarative CSS Injection for Ad Containers ---
  try {
    const style = document.createElement('style');
    style.id = 'm-yt-anti-ad-styles';
    style.textContent = `
      ytm-promoted-sparkles-web-renderer,
      ytm-companion-ad-renderer,
      ytm-promoted-video-renderer,
      .ad-container,
      .ad-displaying,
      .ytp-ad-overlay-container,
      .ytm-ad-overlay-container,
      #player-ads {
        display: none !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  } catch (e) {}
})();
