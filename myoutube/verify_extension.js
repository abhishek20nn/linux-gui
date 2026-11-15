const fs = require('fs');
const path = require('path');

// Colors for terminal output
const RESET = '\x1b[0m';
const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const CYAN = '\x1b[36m';
const BOLD = '\x1b[1m';

let passedTests = 0;
let failedTests = 0;

function assert(condition, testName, details = '') {
  if (condition) {
    console.log(`  ${GREEN}✓ PASS:${RESET} ${testName}`);
    passedTests++;
  } else {
    console.error(`  ${RED}✗ FAIL:${RESET} ${testName} ${details ? `(${details})` : ''}`);
    failedTests++;
  }
}

async function runVerification() {
  console.log(`${BOLD}${CYAN}====================================================${RESET}`);
  console.log(`${BOLD}${CYAN}   Mobile YouTube Extension (MV3) Verification Suite${RESET}`);
  console.log(`${BOLD}${CYAN}====================================================${RESET}\n`);

  const rootDir = __dirname;
  const manifestPath = path.join(rootDir, 'manifest.json');
  const rulesPath = path.join(rootDir, 'rules.json');
  const popupHtmlPath = path.join(rootDir, 'popup.html');
  const popupJsPath = path.join(rootDir, 'popup.js');

  // --- 1. Manifest V3 Validation ---
  console.log(`${BOLD}1. Validating manifest.json (Manifest V3 Compliance)${RESET}`);
  assert(fs.existsSync(manifestPath), 'manifest.json exists on disk');

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

  assert(manifest.manifest_version === 3, 'manifest_version is exactly 3');
  assert(typeof manifest.name === 'string' && manifest.name.length > 0 && manifest.name.length <= 45, 'name is valid string <= 45 chars');
  assert(typeof manifest.version === 'string' && /^\d+(\.\d+){0,3}$/.test(manifest.version), 'version follows MV3 format (1-4 dot-separated integers)');
  assert(typeof manifest.description === 'string' && manifest.description.length <= 132, 'description is <= 132 chars');
  assert(Array.isArray(manifest.permissions) && manifest.permissions.includes('declarativeNetRequest'), 'permissions includes declarativeNetRequest');
  
  // Verify zero background scripts
  assert(manifest.background === undefined, 'No background script/service worker declared (0 MB persistent RAM footprint)');

  // Verify host permissions
  assert(Array.isArray(manifest.host_permissions), 'host_permissions is defined as an array');
  const hasWildcardSubdomain = manifest.host_permissions.some(p => p.includes('*.youtube.com'));
  const hasApexDomain = manifest.host_permissions.some(p => p.includes('youtube.com/*') && !p.includes('*.'));
  assert(hasWildcardSubdomain, 'host_permissions covers *.youtube.com/*');
  assert(hasApexDomain, 'host_permissions covers youtube.com/*');

  // Verify declarative_net_request declaration
  assert(manifest.declarative_net_request && Array.isArray(manifest.declarative_net_request.rule_resources), 'declarative_net_request.rule_resources is defined');
  const ruleset1 = manifest.declarative_net_request.rule_resources.find(r => r.id === 'ruleset_1');
  assert(ruleset1 && ruleset1.enabled === true && ruleset1.path === 'rules.json', 'ruleset_1 correctly maps to rules.json and is enabled');

  // Verify action & popup
  assert(manifest.action && manifest.action.default_popup === 'popup.html', 'action.default_popup points to popup.html');
  assert(fs.existsSync(popupHtmlPath), 'popup.html exists');
  assert(fs.existsSync(popupJsPath), 'popup.js exists');

  // Verify icons
  const iconSizes = ['16', '32', '48', '128'];
  for (const size of iconSizes) {
    const iconRelPath = manifest.icons?.[size] || manifest.action?.default_icon?.[size];
    assert(iconRelPath && fs.existsSync(path.join(rootDir, iconRelPath)), `Icon ${size}x${size} exists (${iconRelPath})`);
  }

  // --- 2. Rules.json Validation ---
  console.log(`\n${BOLD}2. Validating rules.json (DeclarativeNetRequest Specification)${RESET}`);
  assert(fs.existsSync(rulesPath), 'rules.json exists on disk');

  const rules = JSON.parse(fs.readFileSync(rulesPath, 'utf8'));
  assert(Array.isArray(rules), 'rules.json contains a JSON array');
  assert(rules.length >= 2, `Contains expected rules count (found ${rules.length})`);

  // Rule 1: Redirect
  const rule1 = rules.find(r => r.id === 1);
  assert(rule1 !== undefined, 'Rule 1 (Redirect) exists');
  assert(rule1.action?.type === 'redirect', 'Rule 1 action type is "redirect"');
  assert(rule1.action?.redirect?.transform?.scheme === 'https', 'Rule 1 redirect transform scheme is "https"');
  assert(rule1.action?.redirect?.transform?.host === 'm.youtube.com', 'Rule 1 redirect transform host is "m.youtube.com"');
  assert(Array.isArray(rule1.action?.redirect?.transform?.queryTransform?.removeParams) &&
         rule1.action.redirect.transform.queryTransform.removeParams.includes('app'),
         'Rule 1 strips "app" query parameter to prevent desktop bounce');
  assert(rule1.condition?.resourceTypes?.includes('main_frame'), 'Rule 1 condition resourceTypes targets "main_frame"');

  // Rule 2: Header Modification
  const rule2 = rules.find(r => r.id === 2);
  assert(rule2 !== undefined, 'Rule 2 (modifyHeaders) exists');
  assert(rule2.action?.type === 'modifyHeaders', 'Rule 2 action type is "modifyHeaders"');
  
  const headers = rule2.action?.requestHeaders || [];
  const uaHeader = headers.find(h => h.header?.toLowerCase() === 'user-agent');
  const chMobile = headers.find(h => h.header?.toLowerCase() === 'sec-ch-ua-mobile');
  const chPlatform = headers.find(h => h.header?.toLowerCase() === 'sec-ch-ua-platform');

  assert(uaHeader && uaHeader.operation === 'set' && /Android|Mobile/i.test(uaHeader.value),
         'Rule 2 sets User-Agent to a mobile client');
  assert(chMobile && chMobile.operation === 'set' && chMobile.value === '?1',
         'Rule 2 sets sec-ch-ua-mobile to "?1"');
  assert(chPlatform && chPlatform.operation === 'set' && chPlatform.value === '"Android"',
         'Rule 2 sets sec-ch-ua-platform to "\\"Android\\""');
  assert(rule2.condition?.requestDomains?.includes('m.youtube.com'),
         'Rule 2 targets requestDomains ["m.youtube.com"]');

  // --- 3. URL Transformation Dry-Run Simulation ---
  console.log(`\n${BOLD}3. Dry-Run URL Matching & Transformation Logic Simulation${RESET}`);

  function simulateRuleMatch(urlStr, rule) {
    const parsed = new URL(urlStr);
    const domain = parsed.hostname;
    const cond = rule.condition;

    // Check resource type (simulate main_frame navigation)
    if (cond.resourceTypes && !cond.resourceTypes.includes('main_frame')) {
      return null;
    }

    // Check requestDomains (and subdomains)
    if (cond.requestDomains) {
      const matchesReqDomain = cond.requestDomains.some(d => domain === d || domain.endsWith('.' + d));
      if (!matchesReqDomain) return null;
    }

    // Check excludedRequestDomains
    if (cond.excludedRequestDomains) {
      const isExcluded = cond.excludedRequestDomains.some(d => domain === d || domain.endsWith('.' + d));
      if (isExcluded) return null;
    }

    // Check urlFilter
    if (cond.urlFilter) {
      if (cond.urlFilter.startsWith('||')) {
        const filterDomain = cond.urlFilter.slice(2);
        const match = domain === filterDomain || domain.endsWith('.' + filterDomain);
        if (!match) return null;
      }
    }

    // Apply URL Transform
    if (rule.action.type === 'redirect' && rule.action.redirect?.transform) {
      const transform = rule.action.redirect.transform;
      const newUrl = new URL(urlStr);
      if (transform.scheme) newUrl.protocol = transform.scheme + ':';
      if (transform.host) newUrl.hostname = transform.host;
      if (transform.queryTransform?.removeParams) {
        for (const p of transform.queryTransform.removeParams) {
          newUrl.searchParams.delete(p);
        }
      }
      return newUrl.toString();
    }
    return null;
  }

  const testCases = [
    {
      input: 'https://www.youtube.com/',
      expectedRedirect: 'https://m.youtube.com/',
      description: 'Desktop home page'
    },
    {
      input: 'http://www.youtube.com/',
      expectedRedirect: 'https://m.youtube.com/',
      description: 'HTTP insecure desktop home page'
    },
    {
      input: 'https://youtube.com/',
      expectedRedirect: 'https://m.youtube.com/',
      description: 'Apex domain root'
    },
    {
      input: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      expectedRedirect: 'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
      description: 'Video watch page preserving video ID query'
    },
    {
      input: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s',
      expectedRedirect: 'https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42s',
      description: 'Video watch page preserving multiple query parameters'
    },
    {
      input: 'https://www.youtube.com/shorts/abcdef123',
      expectedRedirect: 'https://m.youtube.com/shorts/abcdef123',
      description: 'YouTube Shorts path preserved'
    },
    {
      input: 'https://www.youtube.com/results?search_query=lofi+beats',
      expectedRedirect: 'https://m.youtube.com/results?search_query=lofi+beats',
      description: 'Search results page preserved'
    },
    {
      input: 'https://www.youtube.com/?app=desktop',
      expectedRedirect: 'https://m.youtube.com/',
      description: 'Root URL stripping ?app=desktop parameter'
    },
    {
      input: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&app=desktop&feature=shared',
      expectedRedirect: 'https://m.youtube.com/watch?v=dQw4w9WgXcQ&feature=shared',
      description: 'Watch URL stripping app=desktop while preserving other params'
    },
    {
      input: 'https://m.youtube.com/',
      expectedRedirect: null,
      description: 'Mobile YouTube itself must NOT redirect (excluded domain)'
    },
    {
      input: 'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
      expectedRedirect: null,
      description: 'Mobile YouTube watch URL must NOT redirect'
    },
    {
      input: 'https://music.youtube.com/',
      expectedRedirect: null,
      description: 'YouTube Music must NOT redirect (excluded domain)'
    },
    {
      input: 'https://studio.youtube.com/',
      expectedRedirect: null,
      description: 'YouTube Studio must NOT redirect (excluded domain)'
    },
    {
      input: 'https://tv.youtube.com/',
      expectedRedirect: null,
      description: 'YouTube TV must NOT redirect (excluded domain)'
    },
    {
      input: 'https://consent.youtube.com/m?continue=https%3A%2F%2Fwww.youtube.com',
      expectedRedirect: null,
      description: 'Google/YouTube cookie consent must NOT redirect (excluded domain)'
    },
    {
      input: 'https://accounts.youtube.com/accounts/SetSID',
      expectedRedirect: null,
      description: 'YouTube authentication must NOT redirect (excluded domain)'
    }
  ];

  for (const tc of testCases) {
    const result = simulateRuleMatch(tc.input, rule1);
    if (tc.expectedRedirect === null) {
      assert(result === null, `No-redirect test: ${tc.description} (${tc.input})`);
    } else {
      assert(result === tc.expectedRedirect, `Redirect test: ${tc.description} -> ${result}`);
    }
  }

  // --- 4. Live HTTP Header & Redirect Empirical Test ---
  console.log(`\n${BOLD}4. Live HTTP Request Test (Validating Mobile User-Agent Loop Prevention)${RESET}`);
  const desktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  const mobileUA = uaHeader.value;

  try {
    console.log(`  Querying https://m.youtube.com with Desktop UA...`);
    const desktopRes = await fetch('https://m.youtube.com', {
      headers: { 'User-Agent': desktopUA },
      redirect: 'manual'
    });
    const desktopStatus = desktopRes.status;
    const desktopLocation = desktopRes.headers.get('location');
    console.log(`    Status: ${desktopStatus}, Location: ${desktopLocation}`);
    assert(desktopStatus === 302 && desktopLocation && desktopLocation.includes('app=desktop'),
           'Desktop UA receives HTTP 302 bounce to desktop (?app=desktop)');

    console.log(`  Querying https://m.youtube.com with Extension Mobile UA & Client Hints...`);
    const mobileRes = await fetch('https://m.youtube.com', {
      headers: {
        'User-Agent': mobileUA,
        'sec-ch-ua-mobile': chMobile.value,
        'sec-ch-ua-platform': chPlatform.value
      },
      redirect: 'manual'
    });
    const mobileStatus = mobileRes.status;
    const mobileLocation = mobileRes.headers.get('location');
    console.log(`    Status: ${mobileStatus}, Location: ${mobileLocation}`);
    assert(mobileStatus === 200 || (mobileStatus !== 302 && !mobileLocation?.includes('app=desktop')),
           'Mobile UA successfully loads without 302 bounce back to desktop');
  } catch (err) {
    console.warn(`  ${YELLOW}⚠ Live network fetch warning:${RESET} ${err.message}`);
  }

  // --- Final Summary ---
  console.log(`\n${BOLD}${CYAN}====================================================${RESET}`);
  console.log(`${BOLD}Verification Summary: ${GREEN}${passedTests} Passed${RESET}, ${failedTests > 0 ? `${RED}${failedTests} Failed` : `${GREEN}0 Failed`}${RESET}`);
  console.log(`${BOLD}${CYAN}====================================================${RESET}`);

  if (failedTests > 0) {
    process.exit(1);
  }
}

runVerification().catch(err => {
  console.error(err);
  process.exit(1);
});
