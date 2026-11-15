document.addEventListener('DOMContentLoaded', () => {
  const openMobileYtBtn = document.getElementById('openMobileYt');
  const testRedirectBtn = document.getElementById('testRedirect');

  if (openMobileYtBtn) {
    openMobileYtBtn.addEventListener('click', () => {
      chrome.tabs.create({ url: 'https://m.youtube.com' });
    });
  }

  if (testRedirectBtn) {
    testRedirectBtn.addEventListener('click', () => {
      chrome.tabs.create({ url: 'https://www.youtube.com' });
    });
  }
});
