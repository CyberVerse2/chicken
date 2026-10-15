// Chicken EPUB reader runtime. Injected into the combined book document.
// Swift drives it through `window.chicken.*` and listens on the
// `chicken` message handler for { type: 'ready' | 'progress' | 'selection' | 'tap' }.
(() => {
  if (window.chicken) return;

  const post = (message) => {
    try { window.webkit.messageHandlers.chicken.postMessage(message); } catch (_) {}
  };

  const state = {
    horizontal: false,
    spread: false,
    background: '#F5F1E8',
    turnIndex: null,
    turning: false,
    lastWheelTurn: 0,
    lastProgressPost: 0,
    lastGlobalProgress: 0,
    restored: false,
    reduceMotion: window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches,
  };

  const sections = () => Array.from(document.querySelectorAll('[data-chicken-spine-index]'));
  const sectionIndex = (section) => Number(section?.dataset.chickenSpineIndex || 0);
  const doc = () => document.documentElement;
  const scrollX = () => window.scrollX || doc().scrollLeft || document.body.scrollLeft || 0;
  const scrollY = () => window.scrollY || doc().scrollTop || document.body.scrollTop || 0;

  // ---------------------------------------------------------------------
  // Pagination. Horizontal modes lay the book out in CSS columns; each
  // column is a virtual page and spreads advance two at a time.

  // Columns are exactly one viewport wide (half in spread mode), so a page
  // is the viewport width and a turn is one or two pages.
  const metrics = () => {
    const width = window.innerWidth;
    const pageUnit = state.spread ? width / 2 : width;
    const turnUnit = state.spread ? width : pageUnit;
    const maxX = Math.max(0, Math.max(doc().scrollWidth || 0, document.body.scrollWidth || 0) - width);
    return {
      pageUnit,
      turnUnit,
      maxX,
      pageCount: Math.max(1, Math.round((maxX + width) / pageUnit)),
      turnCount: Math.max(1, Math.round((maxX + width) / turnUnit)),
    };
  };

  const currentPage = () => {
    const m = metrics();
    return Math.max(0, Math.min(m.pageCount - 1, Math.round(scrollX() / m.pageUnit)));
  };

  const currentTurn = () => {
    const m = metrics();
    if (Number.isFinite(state.turnIndex)) return Math.max(0, Math.min(m.turnCount - 1, state.turnIndex));
    return Math.max(0, Math.min(m.turnCount - 1, Math.round(scrollX() / m.turnUnit)));
  };

  const scrollToPage = (page, behavior = 'auto') => {
    const m = metrics();
    const target = Math.max(0, Math.min(m.pageCount - 1, Math.round(page)));
    const turn = Math.max(0, Math.min(m.turnCount - 1, Math.round((target * m.pageUnit) / m.turnUnit)));
    state.turnIndex = turn;
    const left = state.spread ? turn * m.turnUnit : target * m.pageUnit;
    window.scrollTo({ left: Math.min(m.maxX, left), top: 0, behavior });
  };

  const targetPageForTurn = (direction) => {
    const m = metrics();
    if (!state.spread) return Math.max(0, Math.min(m.pageCount - 1, currentPage() + direction));
    const spread = Math.max(0, Math.min(m.turnCount - 1, currentTurn() + direction));
    return Math.round((spread * m.turnUnit) / m.pageUnit);
  };

  // A page turn dips a veil in the page color, jumps, then lifts it, so a
  // turn reads as a page swap rather than a sideways slide.
  const veil = () => {
    let element = document.getElementById('chicken-page-veil');
    if (!element) {
      element = document.createElement('div');
      element.id = 'chicken-page-veil';
      element.setAttribute('aria-hidden', 'true');
      document.body.appendChild(element);
    }
    element.style.cssText = `position: fixed; inset: 0; z-index: 9999; pointer-events: none; opacity: 0; background: ${state.background};`;
    return element;
  };

  const turnPage = async (direction) => {
    if (!state.horizontal) {
      window.scrollBy({ top: window.innerHeight * 0.88 * direction, behavior: state.reduceMotion ? 'auto' : 'smooth' });
      return;
    }
    if (state.turning) return;
    const target = targetPageForTurn(direction);
    if (state.reduceMotion) { scrollToPage(target); return; }
    state.turning = true;
    const v = veil();
    v.style.transition = 'opacity 110ms cubic-bezier(0.25, 1, 0.5, 1)';
    v.style.opacity = '0.92';
    await new Promise((resolve) => setTimeout(resolve, 110));
    scrollToPage(target);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    v.style.transition = 'opacity 150ms cubic-bezier(0.25, 1, 0.5, 1)';
    v.style.opacity = '0';
    setTimeout(() => { state.turning = false; }, 160);
  };

  // ---------------------------------------------------------------------
  // Position reporting.

  // Page span of a section in horizontal modes. A chapter that flows over
  // several columns has one client rect per column fragment.
  const sectionPages = (section) => {
    const rects = Array.from(section.getClientRects()).filter((r) => r.width > 0 || r.height > 0);
    const { pageUnit } = metrics();
    if (!rects.length) {
      const start = Math.round(section.offsetLeft / pageUnit);
      return { start, end: start };
    }
    const left = Math.min(...rects.map((r) => r.left)) + scrollX();
    const right = Math.max(...rects.map((r) => r.right)) + scrollX();
    const start = Math.max(0, Math.floor((left + 1) / pageUnit));
    const end = Math.max(start, Math.floor((right - 1) / pageUnit));
    return { start, end };
  };

  const activeSection = () => {
    const all = sections();
    let active = all[0];
    if (state.horizontal) {
      const page = currentPage();
      for (const section of all) {
        if (sectionPages(section).start <= page) active = section; else break;
      }
      return { all, active };
    }
    for (const section of all) {
      if (section.getBoundingClientRect().top <= window.innerHeight * 0.34) active = section; else break;
    }
    return { all, active };
  };

  const globalProgress = () => {
    const position = state.horizontal ? scrollX() : scrollY();
    const length = state.horizontal
      ? Math.max(doc().scrollWidth, document.body.scrollWidth) - window.innerWidth
      : Math.max(doc().scrollHeight, document.body.scrollHeight) - window.innerHeight;
    return length <= 0 ? 0 : Math.max(0, Math.min(1, position / length));
  };

  const sectionProgress = (section) => {
    if (!section) return 0;
    if (state.horizontal) {
      const { start, end } = sectionPages(section);
      return end <= start ? 0 : Math.max(0, Math.min(1, (currentPage() - start) / (end - start)));
    }
    const length = Math.max(1, section.scrollHeight - window.innerHeight * 0.75);
    return Math.max(0, Math.min(1, (scrollY() - section.offsetTop) / length));
  };

  const snapshot = () => {
    const { all, active } = activeSection();
    const index = all.indexOf(active);
    const next = index >= 0 ? all[index + 1] : null;
    const verticalUnit = Math.max(320, window.innerHeight * 0.86);
    let page, pageCount, pageWithinSpine = null, chapterPageCount = null;
    if (state.horizontal) {
      const m = metrics();
      page = currentPage();
      pageCount = m.pageCount;
      if (active) {
        const { start, end } = sectionPages(active);
        chapterPageCount = Math.max(1, end - start + 1);
        pageWithinSpine = Math.max(0, Math.min(chapterPageCount - 1, page - start));
      }
    } else {
      page = Math.floor(scrollY() / verticalUnit);
      pageCount = Math.max(1, Math.ceil(Math.max(doc().scrollHeight, document.body.scrollHeight) / verticalUnit));
      if (active) {
        chapterPageCount = Math.max(1, Math.ceil((active.scrollHeight || verticalUnit) / verticalUnit));
        pageWithinSpine = Math.max(0, Math.min(chapterPageCount - 1, Math.floor((scrollY() - active.offsetTop) / verticalUnit)));
      }
    }
    const progression = globalProgress();
    state.lastGlobalProgress = progression;
    return {
      type: 'progress',
      index: sectionIndex(active),
      progression,
      sectionProgression: sectionProgress(active),
      page,
      pageCount,
      pageWithinSpine,
      chapterPageCount,
    };
  };

  const reportProgress = (force = false) => {
    const now = Date.now();
    if (!force && now - state.lastProgressPost < 220) return;
    state.lastProgressPost = now;
    post(snapshot());
  };

  // ---------------------------------------------------------------------
  // Navigation used by Swift.

  const scrollToSection = (index, progress = 0) => {
    const section = document.getElementById(`chapter-${index}`);
    if (!section) return;
    const p = Math.max(0, Math.min(1, progress || 0));
    if (state.horizontal) {
      const { start, end } = sectionPages(section);
      scrollToPage(start + Math.round((end - start) * p));
    } else {
      const target = section.offsetTop + Math.max(0, section.scrollHeight - window.innerHeight * 0.75) * p;
      window.scrollTo({ top: target, behavior: 'auto' });
    }
    reportProgress(true);
  };

  const scrollToProgress = (progress) => {
    const p = Math.max(0, Math.min(1, progress || 0));
    if (state.horizontal) {
      scrollToPage(Math.round(p * Math.max(0, metrics().pageCount - 1)));
    } else {
      const length = Math.max(0, Math.max(doc().scrollHeight, document.body.scrollHeight) - window.innerHeight);
      window.scrollTo({ top: length * p, behavior: 'auto' });
    }
    reportProgress(true);
  };

  // Restores by spine item and progress within it, which survives changes
  // in font size, window size, or reading mode. A saved page number is used
  // only when it still falls inside the same spine item.
  const restore = (location) => {
    if (!location) return;
    scrollToSection(location.spineIndex, location.progression);
    if (state.horizontal && Number.isFinite(location.pageNumber)) {
      const section = document.getElementById(`chapter-${location.spineIndex}`);
      const target = location.pageNumber - 1;
      if (section) {
        const { start, end } = sectionPages(section);
        if (target >= start && target <= end) scrollToPage(target);
      }
    }
    state.restored = true;
    reportProgress(true);
  };

  const search = (query, backwards) => {
    if (!query) return false;
    const found = window.find(query, false, !!backwards, true, false, false, false);
    if (found) setTimeout(() => { snapToPage(); reportProgress(true); }, 60);
    return found;
  };

  // ---------------------------------------------------------------------
  // Highlights. Each is located by its text within its spine section;
  // whitespace is normalised because selections collapse it.

  const unwrapHighlights = () => {
    document.querySelectorAll('mark.chicken-hl').forEach((mark) => {
      const parent = mark.parentNode;
      while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
      parent.removeChild(mark);
      parent.normalize();
    });
  };

  const wrapText = (root, needle, color, id) => {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const nodes = [];
    let full = '';
    while (walker.nextNode()) {
      nodes.push({ node: walker.currentNode, start: full.length });
      full += walker.currentNode.nodeValue;
    }
    let normalized = '';
    const map = [];
    let previousSpace = false;
    for (let i = 0; i < full.length; i++) {
      const isSpace = /\s/.test(full[i]);
      if (isSpace && previousSpace) continue;
      normalized += isSpace ? ' ' : full[i];
      map.push(i);
      previousSpace = isSpace;
    }
    const target = needle.replace(/\s+/g, ' ').trim();
    const at = normalized.indexOf(target);
    if (at < 0 || !target.length) return;
    const startOriginal = map[at];
    const endOriginal = map[at + target.length - 1] + 1;
    for (const { node, start } of nodes) {
      const end = start + node.nodeValue.length;
      if (end <= startOriginal || start >= endOriginal) continue;
      if (!node.nodeValue.trim()) continue;
      const range = document.createRange();
      range.setStart(node, Math.max(0, startOriginal - start));
      range.setEnd(node, Math.min(node.nodeValue.length, endOriginal - start));
      const mark = document.createElement('mark');
      mark.className = 'chicken-hl';
      mark.dataset.id = id;
      mark.style.background = color;
      mark.style.color = 'inherit';
      try { range.surroundContents(mark); } catch (_) {}
    }
  };

  const applyHighlights = (items) => {
    unwrapHighlights();
    for (const item of items || []) {
      const root = document.getElementById(`chapter-${item.spineIndex}`) || document.body;
      wrapText(root, item.text, item.color, item.id);
    }
  };

  // ---------------------------------------------------------------------
  // Input.

  let selectionTimer = null;
  document.addEventListener('selectionchange', () => {
    clearTimeout(selectionTimer);
    selectionTimer = setTimeout(() => {
      const selection = window.getSelection();
      const text = selection && !selection.isCollapsed ? selection.toString().trim() : '';
      if (text.length < 3) { post({ type: 'selection', text: null }); return; }
      let node = selection.anchorNode;
      while (node && !(node.dataset && node.dataset.chickenSpineIndex !== undefined)) node = node.parentNode;
      post({ type: 'selection', text, index: node ? sectionIndex(node) : sectionIndex(activeSection().active) });
    }, 250);
  });

  window.addEventListener('keydown', (event) => {
    const target = event.target;
    const tag = target && target.tagName ? target.tagName : '';
    if (target && (target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(tag))) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const key = event.key;
    const forward = key === 'ArrowRight' || key === 'PageDown' || (key === ' ' && !event.shiftKey) || (state.horizontal && key === 'ArrowDown');
    const back = key === 'ArrowLeft' || key === 'PageUp' || (key === ' ' && event.shiftKey) || (state.horizontal && key === 'ArrowUp');
    if (!forward && !back) return;
    event.preventDefault();
    turnPage(forward ? 1 : -1);
  });

  // Trackpad swipes become single page turns in horizontal modes.
  window.addEventListener('wheel', (event) => {
    if (!state.horizontal) return;
    const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
    if (Math.abs(delta) < 8) return;
    event.preventDefault();
    const now = Date.now();
    if (now - state.lastWheelTurn < 320) return;
    state.lastWheelTurn = now;
    turnPage(delta > 0 ? 1 : -1);
  }, { passive: false });

  // Touch swipes (iPhone, iPad).
  let touchStart = null;
  window.addEventListener('touchstart', (event) => {
    if (event.touches.length !== 1) { touchStart = null; return; }
    const touch = event.touches[0];
    touchStart = { x: touch.clientX, y: touch.clientY, time: Date.now() };
  }, { passive: true });
  // iOS sends no click for a tap on plain text, so taps are read from the
  // touch itself; the click that sometimes follows is then ignored.
  let lastTouchTap = 0;
  const interactive = 'a, button, input, textarea, select, [contenteditable], [role=button]';
  window.addEventListener('touchend', (event) => {
    if (!touchStart) return;
    const touch = event.changedTouches[0];
    const dx = touch.clientX - touchStart.x;
    const dy = touch.clientY - touchStart.y;
    const elapsed = Date.now() - touchStart.time;
    touchStart = null;
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    if (Math.abs(dx) < 10 && Math.abs(dy) < 10 && elapsed < 350) {
      if (event.target.closest && event.target.closest(interactive)) return;
      lastTouchTap = Date.now();
      handleTap(touch.clientX);
      return;
    }
    if (!state.horizontal || elapsed > 700) return;
    // Pages turn with a swipe either way: sideways like a book, or up and
    // down like scrolling.
    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.4) {
      turnPage(dx < 0 ? 1 : -1);
    } else if (Math.abs(dy) > 50 && Math.abs(dy) > Math.abs(dx) * 1.4) {
      turnPage(dy < 0 ? 1 : -1);
    }
  }, { passive: true });

  // Taps: edges turn pages (like a printed book), the middle toggles chrome.
  const handleTap = (clientX) => {
    const x = clientX / window.innerWidth;
    if (state.horizontal && x < 0.28) turnPage(-1);
    else if (state.horizontal && x > 0.72) turnPage(1);
    else post({ type: 'tap' });
  };
  window.addEventListener('click', (event) => {
    if (event.button !== 0 || event.detail > 1) return;
    if (Date.now() - lastTouchTap < 600) return;
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    if (event.target.closest && event.target.closest(interactive)) return;
    if (state.horizontal) event.preventDefault();
    handleTap(event.clientX);
  });

  // After any free scroll settles (drag, momentum, find), realign to a
  // page boundary so a column is never left half in view.
  let snapTimer = null;
  let snapping = false;
  const snapToPage = () => {
    if (!state.horizontal || snapping) return;
    const m = metrics();
    const target = state.spread ? Math.round(scrollX() / m.turnUnit) * m.turnUnit : Math.round(scrollX() / m.pageUnit) * m.pageUnit;
    state.turnIndex = Math.round(target / m.turnUnit);
    if (Math.abs(scrollX() - target) > 1) {
      snapping = true;
      window.scrollTo({ left: Math.min(m.maxX, target), top: 0, behavior: state.reduceMotion ? 'auto' : 'smooth' });
      setTimeout(() => { snapping = false; }, 320);
    }
  };

  window.addEventListener('scroll', () => {
    reportProgress();
    clearTimeout(snapTimer);
    snapTimer = setTimeout(() => { snapToPage(); reportProgress(true); }, 180);
  }, { passive: true });

  // Keep the reader's place when the window or font changes the layout.
  let resizeTimer = null;
  let resizeAnchor = null;
  window.addEventListener('resize', () => {
    if (!state.restored) return;
    if (resizeAnchor === null) resizeAnchor = state.lastGlobalProgress;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      scrollToProgress(resizeAnchor);
      resizeAnchor = null;
    }, 120);
  });

  // ---------------------------------------------------------------------

  const configure = (config) => {
    const anchor = state.lastGlobalProgress;
    const modeChanged = state.horizontal !== config.horizontal || state.spread !== config.spread;
    state.horizontal = config.horizontal;
    state.spread = config.spread;
    state.background = config.background;
    state.turnIndex = null;
    let style = document.getElementById('chicken-reader-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'chicken-reader-style';
      document.head.appendChild(style);
    }
    style.textContent = config.css;
    doc().style.background = config.background;
    document.body.style.background = config.background;
    if (state.restored && (modeChanged || config.preservePosition)) {
      requestAnimationFrame(() => scrollToProgress(anchor));
    }
  };

  window.chicken = {
    configure,
    restore,
    scrollToSection,
    scrollToProgress,
    turnPage,
    search,
    applyHighlights,
    clearSelection: () => window.getSelection()?.removeAllRanges(),
    snapshot,
  };

  post({ type: 'ready' });
})();
