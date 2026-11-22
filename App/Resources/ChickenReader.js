// Chicken EPUB reader runtime. Injected into the combined book document.
// Swift drives it through `window.chicken.*` and listens on the
// `chicken` message handler for { type: 'ready' | 'progress' | 'selection' | 'tap' }.
(() => {
  if (window.chicken) return;

  const post = (message) => {
    try { window.webkit.messageHandlers.chicken.postMessage(message); } catch (_) {}
  };

  const motionQuery = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
  const state = {
    mode: 'scroll',
    nativeSwipe: false,
    scriptScrollUntil: 0,
    background: '#F8F8F7',
    turnIndex: null,
    lastWheelTurn: 0,
    lastProgressPost: 0,
    lastGlobalProgress: 0,
    restored: false,
    userInteracted: false,
    reduceMotion: Boolean(motionQuery && motionQuery.matches),
  };

  if (motionQuery && motionQuery.addEventListener) {
    motionQuery.addEventListener('change', (event) => {
      state.reduceMotion = event.matches;
    });
  }

  const isHorizontal = () => state.mode !== 'scroll';
  const isSpread = () => state.mode === 'spread';

  const sections = () => Array.from(document.querySelectorAll('[data-chicken-spine-index]'));
  const sectionIndex = (section) => Number(section?.dataset.chickenSpineIndex || 0);
  const doc = () => document.documentElement;
  const scrollX = () => window.scrollX || doc().scrollLeft || document.body.scrollLeft || 0;
  const scrollY = () => window.scrollY || doc().scrollTop || document.body.scrollTop || 0;

  // ---------------------------------------------------------------------
  // Pagination. Horizontal modes lay the book out in CSS columns; each
  // column is a virtual page and spreads advance two at a time.

  const metrics = () => {
    const width = window.innerWidth;
    const pageUnit = isSpread() ? width / 2 : width;
    const turnUnit = isSpread() ? width : pageUnit;
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
    if (behavior === 'smooth') state.scriptScrollUntil = Date.now() + 450;
    const left = isSpread() ? turn * m.turnUnit : target * m.pageUnit;
    window.scrollTo({ left: Math.min(m.maxX, left), top: 0, behavior });
  };

  const targetPageForTurn = (direction) => {
    const m = metrics();
    if (!isSpread() && !state.nativeSwipe) return Math.max(0, Math.min(m.pageCount - 1, currentPage() + direction));
    const spread = Math.max(0, Math.min(m.turnCount - 1, currentTurn() + direction));
    return Math.round((spread * m.turnUnit) / m.pageUnit);
  };

  const turnPage = (direction, instant = false) => {
    state.userInteracted = true;
    if (!isHorizontal()) {
      window.scrollBy({ top: window.innerHeight * 0.88 * direction, behavior: (instant || state.reduceMotion) ? 'auto' : 'smooth' });
      return;
    }
    const target = targetPageForTurn(direction);
    if (state.nativeSwipe) {
      scrollToPage(target, (instant || state.reduceMotion) ? 'auto' : 'smooth');
      return;
    }
    scrollToPage(target, 'auto');
    reportProgress(true);
  };

  // ---------------------------------------------------------------------
  // Position reporting.

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
    if (!all.length) return { all, active: null };
    let low = 0;
    let high = all.length - 1;
    let best = 0;
    if (isHorizontal()) {
      const page = currentPage();
      while (low <= high) {
        const mid = (low + high) >> 1;
        if (sectionPages(all[mid]).start <= page) {
          best = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      return { all, active: all[best] };
    }
    const threshold = window.innerHeight * 0.34;
    while (low <= high) {
      const mid = (low + high) >> 1;
      if (all[mid].getBoundingClientRect().top <= threshold) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return { all, active: all[best] };
  };

  const globalProgress = () => {
    const position = isHorizontal() ? scrollX() : scrollY();
    const length = isHorizontal()
      ? Math.max(doc().scrollWidth, document.body.scrollWidth) - window.innerWidth
      : Math.max(doc().scrollHeight, document.body.scrollHeight) - window.innerHeight;
    return length <= 0 ? 0 : Math.max(0, Math.min(1, position / length));
  };

  const sectionProgress = (section) => {
    if (!section) return 0;
    if (isHorizontal()) {
      const { start, end } = sectionPages(section);
      return end <= start ? 0 : Math.max(0, Math.min(1, (currentPage() - start) / (end - start)));
    }
    const length = Math.max(1, section.scrollHeight - window.innerHeight * 0.75);
    return Math.max(0, Math.min(1, (scrollY() - section.offsetTop) / length));
  };

  const snapshot = () => {
    const { active } = activeSection();
    const verticalUnit = Math.max(320, window.innerHeight * 0.86);
    let page, pageCount, pageWithinSpine = null, chapterPageCount = null;
    if (isHorizontal()) {
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
    if (!force && now - state.lastProgressPost < 200) return;
    state.lastProgressPost = now;
    post(snapshot());
  };

  // ---------------------------------------------------------------------
  // Navigation used by Swift.

  const scrollToSection = (index, progress = 0) => {
    const section = document.getElementById(`chapter-${index}`);
    if (!section) return;
    const p = Math.max(0, Math.min(1, progress || 0));
    if (isHorizontal()) {
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
    if (isHorizontal()) {
      scrollToPage(Math.round(p * Math.max(0, metrics().pageCount - 1)));
    } else {
      const length = Math.max(0, Math.max(doc().scrollHeight, document.body.scrollHeight) - window.innerHeight);
      window.scrollTo({ top: length * p, behavior: 'auto' });
    }
    reportProgress(true);
  };

  const restore = (location, allowAfterInteraction = false) => {
    if (!location) return;
    if (!allowAfterInteraction && state.userInteracted) return;
    scrollToSection(location.spineIndex, location.progression);
    if (isHorizontal() && Number.isFinite(location.pageNumber)) {
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
    }, 220);
  });

  window.addEventListener('keydown', (event) => {
    const target = event.target;
    const tag = target && target.tagName ? target.tagName : '';
    if (target && (target.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(tag))) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    const key = event.key;
    const forward = key === 'ArrowRight' || key === 'PageDown' || (key === ' ' && !event.shiftKey) || (isHorizontal() && key === 'ArrowDown');
    const back = key === 'ArrowLeft' || key === 'PageUp' || (key === ' ' && event.shiftKey) || (isHorizontal() && key === 'ArrowUp');
    if (!forward && !back) return;
    event.preventDefault();
    turnPage(forward ? 1 : -1, true);
  });

  window.addEventListener('wheel', (event) => {
    if (!isHorizontal()) return;
    const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
    if (Math.abs(delta) < 8) return;
    event.preventDefault();
    const now = Date.now();
    if (now - state.lastWheelTurn < 260) return;
    state.lastWheelTurn = now;
    turnPage(delta > 0 ? 1 : -1);
  }, { passive: false });

  let touchStart = null;
  window.addEventListener('touchstart', (event) => {
    state.userInteracted = true;
    if (event.touches.length !== 1) { touchStart = null; return; }
    const touch = event.touches[0];
    touchStart = { x: touch.clientX, y: touch.clientY, time: Date.now() };
  }, { passive: true });

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
      if (event.target && event.target.tagName === 'IMG') {
        const rect = event.target.getBoundingClientRect();
        if (rect.width >= 80 && rect.height >= 80) return;
      }
      lastTouchTap = Date.now();
      handleTap(touch.clientX);
      return;
    }
    if (!isHorizontal() || state.nativeSwipe || elapsed > 700) return;
    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.4) {
      turnPage(dx < 0 ? 1 : -1);
    }
  }, { passive: true });

  const handleTap = (clientX) => {
    const x = clientX / window.innerWidth;
    if (isHorizontal() && x < 0.25) turnPage(-1);
    else if (isHorizontal() && x > 0.75) turnPage(1);
    else post({ type: 'tap' });
  };

  const resolveFootnote = (link) => {
    const href = link.getAttribute('href') || '';
    if (!href.includes('#')) return null;
    const fragment = href.slice(href.indexOf('#') + 1);
    if (!fragment) return null;
    const epubType = (link.getAttribute('epub:type') || link.getAttribute('role') || '').toLowerCase();
    const isMarkedNote = epubType.includes('noteref') || link.classList.contains('noteref') || link.classList.contains('footnote-ref') || Boolean(link.closest('sup'));
    const escaped = CSS && CSS.escape ? CSS.escape(fragment) : fragment.replace(/([#.;?+*~':"!^$[\]()=>|/@])/g, '\\$1');
    const targetChapter = link.dataset.chickenTargetChapter !== undefined ? Number(link.dataset.chickenTargetChapter) : null;
    const scope = targetChapter !== null ? document.getElementById(`chapter-${targetChapter}`) : document;
    const targetEl = (scope && scope.querySelector(`#${escaped}`)) || document.getElementById(fragment);
    if (!targetEl) return null;
    const targetType = (targetEl.getAttribute('epub:type') || targetEl.getAttribute('role') || '').toLowerCase();
    const looksLikeFootnote = isMarkedNote
      || targetType.includes('footnote')
      || targetType.includes('endnote')
      || targetType.includes('rearnote')
      || targetType.includes('note')
      || targetEl.tagName === 'ASIDE'
      || /^(fn|note|endnote|footnote|ftn)/i.test(fragment);
    if (!looksLikeFootnote) return null;
    const container = targetEl.closest('aside, li, dd, p, div') || targetEl;
    const clone = container.cloneNode(true);
    clone.querySelectorAll('a[epub\\:type~="backlink"], a.footnote-backref, a[role="doc-backlink"]').forEach((el) => el.remove());
    const text = (clone.textContent || '').replace(/\s+/g, ' ').trim();
    if (!text || text.length > 2400) return null;
    const label = (link.textContent || '').replace(/\s+/g, ' ').trim() || 'Note';
    const chapterEl = targetEl.closest('[data-chicken-spine-index]');
    return {
      type: 'footnote',
      label,
      text,
      fragment,
      chapter: chapterEl ? sectionIndex(chapterEl) : targetChapter,
    };
  };

  window.addEventListener('click', (event) => {
    const img = event.target && event.target.tagName === 'IMG' ? event.target : null;
    if (img && !img.closest('a')) {
      const rect = img.getBoundingClientRect();
      if (rect.width >= 80 && rect.height >= 80 && img.currentSrc) {
        event.preventDefault();
        post({ type: 'image', src: img.currentSrc, alt: img.getAttribute('alt') || '' });
        return;
      }
    }
    const anchor = event.target.closest ? event.target.closest('a[href]') : null;
    if (anchor) {
      const footnote = resolveFootnote(anchor);
      if (footnote) {
        event.preventDefault();
        post(footnote);
        return;
      }
    }
    const link = event.target.closest ? event.target.closest('a[data-chicken-target-chapter]') : null;
    if (link) {
      const chapter = Number(link.dataset.chickenTargetChapter);
      const href = link.getAttribute('href') || '';
      const fragment = href.startsWith('#') ? href.slice(1) : '';
      const section = document.getElementById(`chapter-${chapter}`);
      if (section && fragment) {
        const escaped = CSS && CSS.escape ? CSS.escape(fragment) : fragment.replace(/([#.;?+*~':"!^$[\]()=>|/@])/g, '\\$1');
        const targetEl = section.querySelector(`#${escaped}`) || section;
        event.preventDefault();
        state.userInteracted = true;
        if (isHorizontal()) {
          const left = targetEl.getBoundingClientRect().left + scrollX();
          scrollToPage(Math.floor((left + 1) / metrics().pageUnit));
        } else {
          targetEl.scrollIntoView({ block: 'start', behavior: 'auto' });
        }
        reportProgress(true);
        return;
      }
    }
    if (event.button !== 0 || event.detail > 1) return;
    if (Date.now() - lastTouchTap < 600) return;
    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;
    if (event.target.closest && event.target.closest(interactive)) return;
    if (isHorizontal()) event.preventDefault();
    handleTap(event.clientX);
  });

  let snapTimer = null;
  let snapping = false;
  const snapToPage = () => {
    if (!isHorizontal() || state.nativeSwipe || snapping) return;
    const m = metrics();
    const target = isSpread() ? Math.round(scrollX() / m.turnUnit) * m.turnUnit : Math.round(scrollX() / m.pageUnit) * m.pageUnit;
    state.turnIndex = Math.round(target / m.turnUnit);
    if (Math.abs(scrollX() - target) > 1) {
      snapping = true;
      window.scrollTo({ left: Math.min(m.maxX, target), top: 0, behavior: state.reduceMotion ? 'auto' : 'smooth' });
      setTimeout(() => { snapping = false; }, 260);
    }
  };

  window.addEventListener('scroll', () => {
    if (state.nativeSwipe && Date.now() > state.scriptScrollUntil) state.turnIndex = null;
    if (!state.nativeSwipe) reportProgress();
    clearTimeout(snapTimer);
    snapTimer = setTimeout(() => {
      snapToPage();
      reportProgress(true);
    }, 150);
  }, { passive: true });

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
  // Reading aloud. Passages are the book's leaf text blocks, in order;
  // Swift asks for a batch starting at what's on screen, then the next
  // batch, and reveals each passage as it's spoken.

  const SPEAKABLE = 'p, h1, h2, h3, h4, h5, h6, li, blockquote, dd, dt, figcaption, pre, td';
  let speakable = null;
  const speakableBlocks = () => {
    if (!speakable) {
      let blocks = Array.from(document.querySelectorAll(`[data-chicken-spine-index] :is(${SPEAKABLE})`))
        .filter((el) => !el.querySelector(SPEAKABLE) && (el.textContent || '').trim().length > 0);
      if (!blocks.length) {
        blocks = Array.from(document.querySelectorAll('[data-chicken-spine-index] div'))
          .filter((el) => !el.querySelector('div') && (el.textContent || '').trim().length > 0);
      }
      speakable = blocks;
    }
    return speakable;
  };

  const isOnScreen = (el) => {
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return false;
    return rect.bottom > 0 && rect.top < window.innerHeight && rect.right > 0 && rect.left < window.innerWidth;
  };

  const readAloud = (after, limit) => {
    const blocks = speakableBlocks();
    let start = 0;
    if (after === null || after === undefined) {
      const first = blocks.findIndex(isOnScreen);
      start = first >= 0 ? first : 0;
    } else {
      start = Number(after) + 1;
    }
    return blocks.slice(start, start + (limit || 30)).map((el, offset) => ({
      id: String(start + offset),
      text: (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim(),
    }));
  };

  const revealPassage = (id) => {
    const el = speakableBlocks()[Number(id)];
    if (!el) return;
    document.querySelectorAll('.chicken-speaking').forEach((other) => other.classList.remove('chicken-speaking'));
    el.classList.add('chicken-speaking');
    if (!isOnScreen(el) || el.getBoundingClientRect().bottom > window.innerHeight) {
      if (isHorizontal()) {
        const left = el.getBoundingClientRect().left + scrollX();
        scrollToPage(Math.floor((left + 1) / metrics().pageUnit), state.reduceMotion ? 'auto' : 'smooth');
      } else {
        el.scrollIntoView({ block: 'start', behavior: state.reduceMotion ? 'auto' : 'smooth' });
      }
    }
    reportProgress(true);
  };

  const endReadingAloud = () => {
    document.querySelectorAll('.chicken-speaking').forEach((el) => el.classList.remove('chicken-speaking'));
  };

  // ---------------------------------------------------------------------

  const configure = (config) => {
    const anchor = state.lastGlobalProgress;
    const nextMode = config.mode || (config.horizontal ? (config.spread ? 'spread' : 'paged') : 'scroll');
    const modeChanged = state.mode !== nextMode;
    state.mode = nextMode;
    state.nativeSwipe = Boolean(config.nativeSwipe);
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
    readAloud,
    revealPassage,
    endReadingAloud,
  };

  post({ type: 'ready' });
})();
