const express = require('express');
const puppeteer = require('puppeteer');

const app = express();
app.use(express.json());

// Browser instance (reused for performance)
let browser = null;

async function getBrowser() {
  if (!browser || !browser.isConnected()) {
    browser = await puppeteer.launch({
      headless: 'new',
      executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/chromium',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--disable-software-rasterizer',
      ],
    });
  }
  return browser;
}

// Scroll page to load lazy images
async function scrollPage(page, options = {}) {
  const { maxScrolls = 50, scrollDelay = 300, expectedImages = null } = options;

  await page.evaluate(async (maxScrolls, scrollDelay, expectedImages) => {
    await new Promise((resolve) => {
      let scrollCount = 0;
      const distance = window.innerHeight;

      const timer = setInterval(() => {
        window.scrollBy(0, distance);
        scrollCount++;

        // Check if we've loaded expected number of images
        if (expectedImages) {
          const loadedImages = document.querySelectorAll('img[src]:not([src=""])').length;
          if (loadedImages >= expectedImages) {
            clearInterval(timer);
            resolve();
            return;
          }
        }

        // Check if we've reached the bottom or max scrolls
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const scrollHeight = document.documentElement.scrollHeight;
        const clientHeight = document.documentElement.clientHeight;

        if (scrollTop + clientHeight >= scrollHeight - 10 || scrollCount >= maxScrolls) {
          clearInterval(timer);
          resolve();
        }
      }, scrollDelay);
    });

    // Scroll back to top
    window.scrollTo(0, 0);
  }, maxScrolls, scrollDelay, expectedImages);
}

// Wait for images to load
async function waitForImages(page, timeout = 10000) {
  await page.evaluate(async (timeout) => {
    const images = Array.from(document.querySelectorAll('img[src]:not([src=""])'));
    await Promise.race([
      Promise.all(images.map(img => {
        if (img.complete) return Promise.resolve();
        return new Promise((resolve) => {
          img.onload = resolve;
          img.onerror = resolve;
        });
      })),
      new Promise(resolve => setTimeout(resolve, timeout))
    ]);
  }, timeout);
}

app.post('/render', async (req, res) => {
  const { url, headers = {}, scroll = false, expectedImages = null, waitForSelector = null } = req.body;

  if (!url) {
    return res.status(400).json({ error: 'URL is required' });
  }

  let page = null;

  try {
    const browserInstance = await getBrowser();
    page = await browserInstance.newPage();

    // Set viewport for proper rendering
    await page.setViewport({ width: 1280, height: 800 });

    // Set custom headers if provided
    if (headers && Object.keys(headers).length > 0) {
      await page.setExtraHTTPHeaders(headers);
    }

    // Set a realistic user agent
    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    );

    // Navigate to the page
    await page.goto(url, {
      waitUntil: 'networkidle2',
      timeout: 30000,
    });

    // Wait for specific selector if provided
    if (waitForSelector) {
      try {
        await page.waitForSelector(waitForSelector, { timeout: 10000 });
      } catch (e) {
        console.warn(`Selector ${waitForSelector} not found within timeout`);
      }
    }

    // Scroll page if requested (for lazy-loaded content)
    if (scroll) {
      console.log(`Scrolling page: ${url}, expectedImages: ${expectedImages}`);
      await scrollPage(page, {
        maxScrolls: 100,
        scrollDelay: 200,
        expectedImages: expectedImages,
      });

      // Wait a bit more for images to finish loading
      await waitForImages(page, 5000);
    }

    // Get the rendered HTML
    const body = await page.content();

    res.json({ body });
  } catch (error) {
    console.error(`Error rendering ${url}:`, error.message);
    res.status(500).json({ error: error.message });
  } finally {
    if (page) {
      await page.close().catch(() => {});
    }
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Shutting down...');
  if (browser) {
    await browser.close();
  }
  process.exit(0);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Render server listening on port ${PORT}`);
});
