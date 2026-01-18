const express = require('express');
const puppeteer = require('puppeteer');

const app = express();
app.use(express.json());

// Browser instance (reused for performance)
let browser = null;

// Simple logger with timestamps
function log(level, message, meta = {}) {
  const timestamp = new Date().toISOString();
  const metaStr = Object.keys(meta).length > 0 ? ` ${JSON.stringify(meta)}` : '';
  console.log(`[${timestamp}] [${level.toUpperCase()}] ${message}${metaStr}`);
}

async function getBrowser() {
  if (!browser || !browser.isConnected()) {
    log('info', 'Launching new browser instance');
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
    log('info', 'Browser launched successfully');
  }
  return browser;
}

// Scroll page to load lazy images
async function scrollPage(page, options = {}) {
  const { maxScrolls = 50, scrollDelay = 300, expectedImages = null } = options;

  const result = await page.evaluate(async (maxScrolls, scrollDelay, expectedImages) => {
    const logs = [];
    let scrollCount = 0;
    const distance = window.innerHeight;
    const startTime = Date.now();

    await new Promise((resolve) => {
      const timer = setInterval(() => {
        window.scrollBy(0, distance);
        scrollCount++;

        const loadedImages = document.querySelectorAll('img[src]:not([src=""])').length;

        // Log progress every 10 scrolls
        if (scrollCount % 10 === 0) {
          logs.push({
            scroll: scrollCount,
            images: loadedImages,
            elapsed: Date.now() - startTime
          });
        }

        // Check if we've loaded expected number of images
        if (expectedImages && loadedImages >= expectedImages) {
          logs.push({
            event: 'target_reached',
            scroll: scrollCount,
            images: loadedImages,
            elapsed: Date.now() - startTime
          });
          clearInterval(timer);
          resolve();
          return;
        }

        // Check if we've reached the bottom or max scrolls
        const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
        const scrollHeight = document.documentElement.scrollHeight;
        const clientHeight = document.documentElement.clientHeight;

        if (scrollTop + clientHeight >= scrollHeight - 10 || scrollCount >= maxScrolls) {
          logs.push({
            event: scrollCount >= maxScrolls ? 'max_scrolls' : 'bottom_reached',
            scroll: scrollCount,
            images: loadedImages,
            elapsed: Date.now() - startTime
          });
          clearInterval(timer);
          resolve();
        }
      }, scrollDelay);
    });

    // Scroll back to top
    window.scrollTo(0, 0);

    const finalImages = document.querySelectorAll('img[src]:not([src=""])').length;
    return {
      totalScrolls: scrollCount,
      finalImageCount: finalImages,
      totalTime: Date.now() - startTime,
      logs
    };
  }, maxScrolls, scrollDelay, expectedImages);

  return result;
}

// Wait for images to load and return count
async function waitForImages(page, timeout = 10000) {
  const result = await page.evaluate(async (timeout) => {
    const startTime = Date.now();
    const images = Array.from(document.querySelectorAll('img[src]:not([src=""])'));
    const totalImages = images.length;

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

    const loadedImages = images.filter(img => img.complete && img.naturalWidth > 0).length;
    return {
      total: totalImages,
      loaded: loadedImages,
      elapsed: Date.now() - startTime
    };
  }, timeout);

  return result;
}

// Count images on page
async function countImages(page) {
  return await page.evaluate(() => {
    return document.querySelectorAll('img[src]:not([src=""])').length;
  });
}

app.post('/render', async (req, res) => {
  const { url, headers = {}, scroll = false, expectedImages = null, waitForSelector = null } = req.body;
  const requestStart = Date.now();

  if (!url) {
    return res.status(400).json({ error: 'URL is required' });
  }

  log('info', 'Render request received', { url, scroll, expectedImages });

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
    const navStart = Date.now();
    log('info', 'Navigation started', { url });

    await page.goto(url, {
      waitUntil: 'networkidle2',
      timeout: 30000,
    });

    const navTime = Date.now() - navStart;
    const initialImages = await countImages(page);
    log('info', 'Page loaded', {
      url,
      navigationTime: `${navTime}ms`,
      initialImageCount: initialImages
    });

    // Wait for specific selector if provided
    if (waitForSelector) {
      try {
        log('debug', 'Waiting for selector', { selector: waitForSelector });
        await page.waitForSelector(waitForSelector, { timeout: 10000 });
        log('debug', 'Selector found', { selector: waitForSelector });
      } catch (e) {
        log('warn', 'Selector not found within timeout', { selector: waitForSelector });
      }
    }

    // Scroll page if requested (for lazy-loaded content)
    let scrollResult = null;
    let imageWaitResult = null;

    if (scroll) {
      log('info', 'Starting scroll', {
        url,
        expectedImages,
        maxScrolls: 100,
        scrollDelay: 200
      });

      scrollResult = await scrollPage(page, {
        maxScrolls: 100,
        scrollDelay: 200,
        expectedImages: expectedImages,
      });

      log('info', 'Scroll completed', {
        url,
        totalScrolls: scrollResult.totalScrolls,
        imagesAfterScroll: scrollResult.finalImageCount,
        scrollTime: `${scrollResult.totalTime}ms`
      });

      // Wait a bit more for images to finish loading
      log('debug', 'Waiting for images to fully load');
      imageWaitResult = await waitForImages(page, 5000);
      log('info', 'Images loaded', {
        url,
        totalImages: imageWaitResult.total,
        loadedImages: imageWaitResult.loaded,
        waitTime: `${imageWaitResult.elapsed}ms`
      });
    }

    // Get the rendered HTML
    const body = await page.content();
    const finalImages = await countImages(page);
    const totalTime = Date.now() - requestStart;

    log('info', 'Render complete', {
      url,
      finalImageCount: finalImages,
      expectedImages: expectedImages || 'not specified',
      totalTime: `${totalTime}ms`,
      success: !expectedImages || finalImages >= expectedImages
    });

    // Warn if we got fewer images than expected
    if (expectedImages && finalImages < expectedImages) {
      log('warn', 'Fewer images than expected', {
        url,
        expected: expectedImages,
        actual: finalImages,
        missing: expectedImages - finalImages
      });
    }

    res.json({ body });
  } catch (error) {
    const totalTime = Date.now() - requestStart;
    log('error', 'Render failed', {
      url,
      error: error.message,
      totalTime: `${totalTime}ms`
    });
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
  log('info', 'Shutting down...');
  if (browser) {
    await browser.close();
  }
  process.exit(0);
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  log('info', `Render server listening on port ${PORT}`);
});
