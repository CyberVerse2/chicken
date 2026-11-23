(() => {
  const bootEl = document.getElementById('chicken-boot');
  if (!bootEl || window.chicken) return;

  let boot = {};
  try { boot = JSON.parse(bootEl.textContent || '{}'); } catch (_) {}

  const post = (message) => {
    try { window.webkit.messageHandlers.chicken.postMessage(message); } catch (_) {}
  };

  const motionQuery = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
  const doc = () => document.documentElement;
  const stage = () => document.getElementById('chicken-stage') || document.body;
  const scrollX = () => window.scrollX || doc().scrollLeft || document.body.scrollLeft || 0;
  const scrollY = () => window.scrollY || doc().scrollTop || document.body.scrollTop || 0;

  const state = {
    mode: boot.mode || 'scroll',
    nativeSwipe: Boolean(boot.nativeSwipe),
    background: boot.background || '#FAF8F4',
    textColor: boot.textColor || '#1C1A17',
    mutedColor: boot.mutedColor || '#6B655D',
    layoutKey: boot.layoutKey || '',
    spineCount: Math.max(1, Number(boot.spineCount || 1)),
    spineWeights: Array.isArray(boot.spineWeights) && boot.spineWeights.length ? boot.spineWeights : [512],
    cumulativeWeights: Array.isArray(boot.cumulativeWeights) && boot.cumulativeWeights.length ? boot.cumulativeWeights : [0, 512],
    totalWeight: Math.max(1, Number(boot.totalWeight || 512)),
    activeChapter: Number(boot.initialChapter || 0),
    mountedFirst: Number(boot.initialChapter || 0),
    mountedLast: Number(boot.initialChapter || 0),
    highlightsByChapter: boot.highlightsByChapter || {},
    chapterPageCounts: new Map(),
    chapterCache: new Map(),
    inFlightChapters: new Map(),
    scriptScrollUntil: 0,
    turnIndex: null,
    lastWheelTurn: 0,
    lastProgressPost: 0,
    lastPostedKey: '',
    lastGlobalProgress: 0,
    restored: false,
    userInteracted: false,
    reduceMotion: Boolean(motionQuery && motionQuery.matches),
    scrollExpanding: false,
    navigationToken: 0,
    speakableCache: null,
    speakableChapter: -1,
    metrics: null,
  };

  if (motionQuery && motionQuery.addEventListener) {
    motionQuery.addEventListener('change', (event) => {
      state.reduceMotion = event.matches;
    });
  }

  const isHorizontal = () => state.mode !== 'scroll';
  const isSpread = () => state.mode === 'spread';
  const sectionIndex = (section) => Number(section?.dataset.chickenSpineIndex || 0);

  const setThemeVars = (bg, text, muted) => {
    const rootStyle = doc().style;
    if (bg) rootStyle.setProperty('--ch-bg', bg);
    if (text) rootStyle.setProperty('--ch-text', text);
    if (muted) rootStyle.setProperty('--ch-muted', muted);
    if (bg) {
      rootStyle.background = bg;
      document.body.style.background = bg;
    }
  };

  const recomputeMetrics = () => {
    const width = Math.max(1, window.innerWidth);
    const height = Math.max(1, window.innerHeight);
    const els = Array.from(document.querySelectorAll('[data-chicken-spine-index]'));
    if (isHorizontal()) {
      const pageUnit = isSpread() ? width / 2 : width;
      const turnUnit = isSpread() ? width : pageUnit;
      const scrollW = Math.max(doc().scrollWidth || 0, document.body.scrollWidth || 0);
      const maxX = Math.max(0, scrollW - width);
      const pageCount = Math.max(1, Math.round((maxX + width) / pageUnit));
      const turnCount = Math.max(1, Math.round((maxX + width) / turnUnit));
      const baseScrollX = scrollX();
      const sections = els.map((el) => {
        const idx = sectionIndex(el);
        let start = 0;
        let end = pageCount - 1;
        if (els.length > 1) {
          const rects = el.getClientRects();
          if (rects.length) {
            let minL = Infinity;
            let maxR = -Infinity;
            for (let i = 0; i < rects.length; i++) {
              const r = rects[i];
              if (r.width > 0 || r.height > 0) {
                if (r.left < minL) minL = r.left;
                if (r.right > maxR) maxR = r.right;
              }
            }
            if (minL < Infinity) {
              start = Math.max(0, Math.floor((minL + baseScrollX + 1) / pageUnit));
              end = Math.max(start, Math.floor((maxR + baseScrollX - 1) / pageUnit));
            }
          }
        }
        return { index: idx, el, start, end };
      });
      if (sections.length === 1) {
        state.chapterPageCounts.set(sections[0].index, pageCount);
      } else {
        for (const s of sections) {
          state.chapterPageCounts.set(s.index, Math.max(1, s.end - s.start + 1));
        }
      }
      state.metrics = { width, height, pageUnit, turnUnit, maxX, pageCount, turnCount, sections };
    } else {
      const scrollH = Math.max(doc().scrollHeight || 0, document.body.scrollHeight || 0);
      const maxY = Math.max(0, scrollH - height);
      const verticalUnit = Math.max(320, height * 0.86);
      const sections = els.map((el) => ({
        index: sectionIndex(el),
        el,
        top: el.offsetTop,
        height: el.scrollHeight || verticalUnit,
      }));
      for (const s of sections) {
        state.chapterPageCounts.set(s.index, Math.max(1, Math.ceil(s.height / verticalUnit)));
      }
      state.metrics = { width, height, verticalUnit, maxY, scrollH, sections };
    }
    return state.metrics;
  };

  const getMetrics = () => state.metrics || recomputeMetrics();

  const estimatedBytesPerPage = () => {
    let observedBytes = 0;
    let observedPages = 0;
    for (const [idx, pages] of state.chapterPageCounts.entries()) {
      if (pages > 0 && idx >= 0 && idx < state.spineWeights.length) {
        observedBytes += state.spineWeights[idx];
        observedPages += pages;
      }
    }
    return observedPages > 0 ? Math.max(300, observedBytes / observedPages) : 1800;
  };

  const estimatedPagesForSpine = (idx) => {
    const known = state.chapterPageCounts.get(idx);
    if (known !== undefined) return known;
    const weight = state.spineWeights[idx] || 512;
    return Math.max(1, Math.round(weight / estimatedBytesPerPage()));
  };

  const currentPageInMounted = () => {
    const m = getMetrics();
    return Math.max(0, Math.min(m.pageCount - 1, Math.round(scrollX() / m.pageUnit)));
  };

  const currentTurnInMounted = () => {
    const m = getMetrics();
    if (Number.isFinite(state.turnIndex)) return Math.max(0, Math.min(m.turnCount - 1, state.turnIndex));
    return Math.max(0, Math.min(m.turnCount - 1, Math.round(scrollX() / m.turnUnit)));
  };

  const activeSectionEntry = () => {
    const m = getMetrics();
    const secs = m.sections;
    if (!secs.length) return null;
    if (secs.length === 1) return secs[0];
    let low = 0;
    let high = secs.length - 1;
    let best = 0;
    if (isHorizontal()) {
      const page = currentPageInMounted();
      while (low <= high) {
        const mid = (low + high) >> 1;
        if (secs[mid].start <= page) { best = mid; low = mid + 1; } else { high = mid - 1; }
      }
    } else {
      const threshold = scrollY() + m.height * 0.34;
      while (low <= high) {
        const mid = (low + high) >> 1;
        if (secs[mid].top <= threshold) { best = mid; low = mid + 1; } else { high = mid - 1; }
      }
    }
    return secs[best];
  };

  const snapshot = () => {
    const m = getMetrics();
    const active = activeSectionEntry();
    const idx = active ? active.index : state.activeChapter;
    state.activeChapter = idx;

    let pageWithinSpine = 0;
    let chapterPageCount = 1;
    let secProg = 0;

    if (isHorizontal()) {
      const localPage = currentPageInMounted();
      if (active) {
        chapterPageCount = Math.max(1, active.end - active.start + 1);
        pageWithinSpine = Math.max(0, Math.min(chapterPageCount - 1, localPage - active.start));
      } else {
        chapterPageCount = m.pageCount;
        pageWithinSpine = localPage;
      }
      secProg = chapterPageCount <= 1 ? 0 : Math.max(0, Math.min(1, pageWithinSpine / (chapterPageCount - 1)));
    } else {
      const y = scrollY();
      if (active) {
        chapterPageCount = Math.max(1, Math.ceil(active.height / m.verticalUnit));
        pageWithinSpine = Math.max(0, Math.min(chapterPageCount - 1, Math.floor((y - active.top) / m.verticalUnit)));
        const span = Math.max(1, active.height - m.height * 0.75);
        secProg = Math.max(0, Math.min(1, (y - active.top) / span));
      }
    }

    const startW = state.cumulativeWeights[idx] || 0;
    const w = state.spineWeights[idx] || 512;
    const progression = Math.max(0, Math.min(1, (startW + w * secProg) / state.totalWeight));
    state.lastGlobalProgress = progression;

    let globalPage = pageWithinSpine;
    let totalPages = chapterPageCount;
    if (state.spineCount > 1) {
      let prefixPages = 0;
      for (let i = 0; i < idx; i++) prefixPages += estimatedPagesForSpine(i);
      let suffixPages = 0;
      for (let i = idx + 1; i < state.spineCount; i++) suffixPages += estimatedPagesForSpine(i);
      globalPage = prefixPages + pageWithinSpine;
      totalPages = Math.max(1, prefixPages + chapterPageCount + suffixPages);
    }

    return {
      type: 'progress',
      index: idx,
      progression,
      sectionProgression: secProg,
      page: globalPage,
      pageCount: totalPages,
      pageWithinSpine,
      chapterPageCount,
    };
  };

  let progressRAF = null;
  const reportProgress = (force = false) => {
    const now = Date.now();
    if (!force && now - state.lastProgressPost < 200) return;
    if (!force) {
      if (progressRAF) return;
      progressRAF = requestAnimationFrame(() => {
        progressRAF = null;
        const snap = snapshot();
        const key = `${snap.index}|${snap.page}|${Math.round(snap.sectionProgression * 1000)}`;
        if (key === state.lastPostedKey) return;
        state.lastPostedKey = key;
        state.lastProgressPost = Date.now();
        post(snap);
      });
      return;
    }
    state.lastProgressPost = now;
    const snap = snapshot();
    state.lastPostedKey = `${snap.index}|${snap.page}|${Math.round(snap.sectionProgression * 1000)}`;
    post(snap);
  };

  const scrollToLocalPage = (page, behavior = 'auto') => {
    const m = getMetrics();
    const target = Math.max(0, Math.min(m.pageCount - 1, Math.round(page)));
    const turn = Math.max(0, Math.min(m.turnCount - 1, Math.round((target * m.pageUnit) / m.turnUnit)));
    state.turnIndex = turn;
    if (behavior === 'smooth') state.scriptScrollUntil = Date.now() + 450;
    const left = isSpread() ? turn * m.turnUnit : target * m.pageUnit;
    window.scrollTo({ left: Math.min(m.maxX, left), top: 0, behavior });
  };

  const fetchChapter = async (index) => {
    if (index < 0 || index >= state.spineCount) return null;
    if (state.chapterCache.has(index)) {
      const val = state.chapterCache.get(index);
      state.chapterCache.delete(index);
      state.chapterCache.set(index, val);
      return val;
    }
    if (state.inFlightChapters.has(index)) return state.inFlightChapters.get(index);
    const promise = fetch(`/__chapter/${index}`)
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => {
        state.inFlightChapters.delete(index);
        if (data) {
          state.chapterCache.set(index, data);
          if (state.chapterCache.size > 6) {
            const oldest = state.chapterCache.keys().next().value;
            state.chapterCache.delete(oldest);
          }
        }
        return data;
      })
      .catch(() => {
        state.inFlightChapters.delete(index);
        return null;
      });
    state.inFlightChapters.set(index, promise);
    return promise;
  };

  const prefetchNeighbors = (index) => {
    const run = () => {
      if (index + 1 < state.spineCount && !state.chapterCache.has(index + 1) && !state.inFlightChapters.has(index + 1)) {
        fetchChapter(index + 1);
      }
      if (index - 1 >= 0 && !state.chapterCache.has(index - 1) && !state.inFlightChapters.has(index - 1)) {
        fetchChapter(index - 1);
      }
    };
    if (window.requestIdleCallback) requestIdleCallback(run, { timeout: 300 });
    else setTimeout(run, 40);
  };

  const buildSectionElement = (chapterData) => {
    const section = document.createElement('section');
    section.className = 'chicken-spine-section';
    section.id = `chapter-${chapterData.index}`;
    section.dataset.chickenSpineIndex = String(chapterData.index);
    section.innerHTML = `${chapterData.styles || ''}\n${chapterData.body || ''}`;
    const items = state.highlightsByChapter[String(chapterData.index)];
    if (items && items.length) {
      for (const item of items) wrapText(section, item.text, item.color, item.id);
    }
    return section;
  };

  const mountSingleChapter = async (index, options = {}) => {
    const clamped = Math.max(0, Math.min(state.spineCount - 1, Number(index)));
    const token = ++state.navigationToken;
    const existing = document.getElementById(`chapter-${clamped}`);
    if (existing && state.mountedFirst === clamped && state.mountedLast === clamped) {
      applyChapterTargetPosition(clamped, options);
      prefetchNeighbors(clamped);
      return;
    }
    const data = await fetchChapter(clamped);
    if (!data || token !== state.navigationToken) return;
    const container = stage();
    container.innerHTML = '';
    const el = buildSectionElement(data);
    container.appendChild(el);
    state.mountedFirst = clamped;
    state.mountedLast = clamped;
    state.activeChapter = clamped;
    state.turnIndex = null;
    state.speakableCache = null;
    state.speakableChapter = -1;
    recomputeMetrics();
    applyChapterTargetPosition(clamped, options);
    reportProgress(true);
    prefetchNeighbors(clamped);
  };

  const applyChapterTargetPosition = (index, options = {}) => {
    const m = getMetrics();
    const sec = m.sections.find((s) => s.index === index) || m.sections[0];
    if (isHorizontal()) {
      const start = sec ? sec.start : 0;
      const end = sec ? sec.end : Math.max(0, m.pageCount - 1);
      if (options.atEnd) {
        scrollToLocalPage(end, 'auto');
      } else if (Number.isFinite(options.pageWithinSpine)) {
        const target = Math.max(start, Math.min(end, start + options.pageWithinSpine));
        scrollToLocalPage(target, 'auto');
      } else {
        const p = Math.max(0, Math.min(1, options.progress || 0));
        scrollToLocalPage(start + Math.round((end - start) * p), 'auto');
      }
    } else {
      const top = sec ? sec.top : 0;
      const height = sec ? sec.height : m.scrollH;
      if (options.atEnd) {
        window.scrollTo({ top: Math.max(0, top + height - m.height), behavior: 'auto' });
      } else {
        const p = Math.max(0, Math.min(1, options.progress || 0));
        const target = top + Math.max(0, height - m.height * 0.75) * p;
        window.scrollTo({ top: target, behavior: 'auto' });
      }
    }
  };

  const turnChapter = (delta) => {
    const next = state.activeChapter + (delta > 0 ? 1 : -1);
    if (next < 0 || next >= state.spineCount) return false;
    mountSingleChapter(next, delta > 0 ? { progress: 0 } : { atEnd: true });
    return true;
  };

  const turnPage = (direction, instant = false) => {
    state.userInteracted = true;
    const m = getMetrics();
    if (!isHorizontal()) {
      window.scrollBy({ top: m.height * 0.88 * direction, behavior: (instant || state.reduceMotion) ? 'auto' : 'smooth' });
      return;
    }
    if (direction > 0 && currentTurnInMounted() >= m.turnCount - 1) {
      if (turnChapter(1)) return;
    } else if (direction < 0 && currentTurnInMounted() <= 0) {
      if (turnChapter(-1)) return;
    }
    let target;
    if (!isSpread() && !state.nativeSwipe) {
      target = Math.max(0, Math.min(m.pageCount - 1, currentPageInMounted() + direction));
    } else {
      const spread = Math.max(0, Math.min(m.turnCount - 1, currentTurnInMounted() + direction));
      target = Math.round((spread * m.turnUnit) / m.pageUnit);
    }
    if (state.nativeSwipe) {
      scrollToLocalPage(target, (instant || state.reduceMotion) ? 'auto' : 'smooth');
      return;
    }
    scrollToLocalPage(target, 'auto');
    reportProgress(true);
  };

  const expandScrollWindowIfNeeded = async () => {
    if (isHorizontal() || state.scrollExpanding) return;
    const m = getMetrics();
    const y = scrollY();
    const nearBottom = y + m.height >= m.scrollH - m.height * 1.5;
    const nearTop = y < 180;

    if (nearBottom && state.mountedLast + 1 < state.spineCount) {
      state.scrollExpanding = true;
      const nextIdx = state.mountedLast + 1;
      const data = await fetchChapter(nextIdx);
      if (data && !isHorizontal() && nextIdx === state.mountedLast + 1) {
        const el = buildSectionElement(data);
        stage().appendChild(el);
        state.mountedLast = nextIdx;
        while (state.mountedLast - state.mountedFirst > 5) {
          const firstEl = document.getElementById(`chapter-${state.mountedFirst}`);
          if (!firstEl) break;
          const h = firstEl.offsetHeight;
          firstEl.remove();
          state.mountedFirst += 1;
          window.scrollBy(0, -h);
        }
        recomputeMetrics();
        prefetchNeighbors(nextIdx);
      }
      state.scrollExpanding = false;
    } else if (nearTop && state.mountedFirst > 0) {
      state.scrollExpanding = true;
      const prevIdx = state.mountedFirst - 1;
      const data = await fetchChapter(prevIdx);
      if (data && !isHorizontal() && prevIdx === state.mountedFirst - 1) {
        const container = stage();
        const prevH = container.scrollHeight;
        const el = buildSectionElement(data);
        container.insertBefore(el, container.firstChild);
        const deltaH = container.scrollHeight - prevH;
        if (deltaH > 0) window.scrollBy(0, deltaH);
        state.mountedFirst = prevIdx;
        while (state.mountedLast - state.mountedFirst > 5) {
          const lastEl = document.getElementById(`chapter-${state.mountedLast}`);
          if (!lastEl) break;
          lastEl.remove();
          state.mountedLast -= 1;
        }
        recomputeMetrics();
        prefetchNeighbors(prevIdx);
      }
      state.scrollExpanding = false;
    }
  };

  const scrollToSection = (index, progress = 0) => {
    const idx = Math.max(0, Math.min(state.spineCount - 1, Number(index)));
    const existing = document.getElementById(`chapter-${idx}`);
    if (existing) {
      applyChapterTargetPosition(idx, { progress });
      reportProgress(true);
      prefetchNeighbors(idx);
      return Promise.resolve();
    }
    return mountSingleChapter(idx, { progress });
  };

  const scrollToProgress = (progress) => {
    const p = Math.max(0, Math.min(1, progress || 0));
    const targetByte = p * state.totalWeight;
    let low = 0;
    let high = state.spineCount - 1;
    let best = 0;
    while (low <= high) {
      const mid = (low + high) >> 1;
      if (state.cumulativeWeights[mid] <= targetByte) { best = mid; low = mid + 1; } else { high = mid - 1; }
    }
    const startW = state.cumulativeWeights[best] || 0;
    const w = state.spineWeights[best] || 512;
    const localProg = w > 0 ? Math.max(0, Math.min(1, (targetByte - startW) / w)) : 0;
    return scrollToSection(best, localProg);
  };

  const restore = (location, allowAfterInteraction = false) => {
    if (!location) return;
    if (!allowAfterInteraction && state.userInteracted) return;
    const targetSpine = Math.max(0, Math.min(state.spineCount - 1, Number(location.spineIndex || 0)));
    const opts = {
      progress: Number(location.progression || 0),
      pageWithinSpine: Number.isFinite(location.pageWithinSpine) ? Number(location.pageWithinSpine) : undefined,
    };
    const existing = document.getElementById(`chapter-${targetSpine}`);
    if (existing) {
      recomputeMetrics();
      applyChapterTargetPosition(targetSpine, opts);
      state.restored = true;
      reportProgress(true);
    } else {
      mountSingleChapter(targetSpine, opts).then(() => {
        state.restored = true;
        reportProgress(true);
      });
    }
  };

  const highlightSearchMatch = async (query, spineIndex, occurrenceIndex = 0) => {
    if (!query) return false;
    const idx = Math.max(0, Math.min(state.spineCount - 1, Number(spineIndex)));
    if (!document.getElementById(`chapter-${idx}`)) {
      await mountSingleChapter(idx, { progress: 0 });
    }
    const root = document.getElementById(`chapter-${idx}`);
    if (!root) return false;
    const lowerQuery = query.toLowerCase();
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let seen = 0;
    let matchedRange = null;
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const text = node.nodeValue || '';
      const lowerText = text.toLowerCase();
      let from = 0;
      while (from < lowerText.length) {
        const at = lowerText.indexOf(lowerQuery, from);
        if (at < 0) break;
        if (seen === occurrenceIndex) {
          matchedRange = document.createRange();
          matchedRange.setStart(node, at);
          matchedRange.setEnd(node, at + query.length);
          break;
        }
        seen += 1;
        from = at + Math.max(1, lowerQuery.length);
      }
      if (matchedRange) break;
    }
    if (!matchedRange) return false;
    const sel = window.getSelection();
    if (sel) {
      sel.removeAllRanges();
      sel.addRange(matchedRange);
    }
    const rect = matchedRange.getBoundingClientRect();
    const m = getMetrics();
    if (isHorizontal()) {
      const left = rect.left + scrollX();
      scrollToLocalPage(Math.floor((left + 1) / m.pageUnit), 'auto');
    } else {
      window.scrollTo({ top: Math.max(0, rect.top + scrollY() - m.height * 0.25), behavior: 'auto' });
    }
    reportProgress(true);
    return true;
  };

  const search = (query, backwards) => {
    if (!query) return false;
    const found = window.find(query, false, !!backwards, true, false, false, false);
    if (found) setTimeout(() => { snapToPage(); reportProgress(true); }, 60);
    return found;
  };

  const unwrapHighlights = () => {
    const marks = document.querySelectorAll('mark.chicken-hl');
    if (!marks.length) return;
    marks.forEach((mark) => {
      const parent = mark.parentNode;
      while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
      parent.removeChild(mark);
      parent.normalize();
    });
  };

  const wrapText = (root, needle, color, id) => {
    const target = (needle || '').replace(/\s+/g, ' ').trim();
    if (!target.length) return;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const nodes = [];
    let full = '';
    while (walker.nextNode()) {
      const val = walker.currentNode.nodeValue;
      nodes.push({ node: walker.currentNode, start: full.length, len: val.length });
      full += val;
    }
    let normalized = '';
    const map = [];
    let previousSpace = false;
    for (let i = 0; i < full.length; i++) {
      const code = full.charCodeAt(i);
      const isSpace = code === 32 || code === 9 || code === 10 || code === 13 || code === 160;
      if (isSpace && previousSpace) continue;
      normalized += isSpace ? ' ' : full[i];
      map.push(i);
      previousSpace = isSpace;
    }
    const at = normalized.indexOf(target);
    if (at < 0) return;
    const startOriginal = map[at];
    const endOriginal = map[at + target.length - 1] + 1;
    for (const entry of nodes) {
      const end = entry.start + entry.len;
      if (end <= startOriginal || entry.start >= endOriginal) continue;
      if (!entry.node.nodeValue.trim()) continue;
      const range = document.createRange();
      range.setStart(entry.node, Math.max(0, startOriginal - entry.start));
      range.setEnd(entry.node, Math.min(entry.len, endOriginal - entry.start));
      const mark = document.createElement('mark');
      mark.className = 'chicken-hl';
      mark.dataset.id = id;
      mark.style.background = color;
      mark.style.color = 'inherit';
      try { range.surroundContents(mark); } catch (_) {}
    }
  };

  const applyHighlights = (items) => {
    const grouped = {};
    for (const item of items || []) {
      const k = String(item.spineIndex);
      if (!grouped[k]) grouped[k] = [];
      grouped[k].push(item);
    }
    state.highlightsByChapter = grouped;
    unwrapHighlights();
    for (let idx = state.mountedFirst; idx <= state.mountedLast; idx++) {
      const list = grouped[String(idx)];
      if (!list || !list.length) continue;
      const root = document.getElementById(`chapter-${idx}`);
      if (!root) continue;
      for (const item of list) wrapText(root, item.text, item.color, item.id);
    }
  };

  let selectionTimer = null;
  document.addEventListener('selectionchange', () => {
    clearTimeout(selectionTimer);
    selectionTimer = setTimeout(() => {
      const selection = window.getSelection();
      const text = selection && !selection.isCollapsed ? selection.toString().trim() : '';
      if (text.length < 3) { post({ type: 'selection', text: null }); return; }
      let node = selection.anchorNode;
      while (node && !(node.dataset && node.dataset.chickenSpineIndex !== undefined)) node = node.parentNode;
      post({ type: 'selection', text, index: node ? sectionIndex(node) : state.activeChapter });
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

  const resolveFootnote = async (link) => {
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
    const label = (link.textContent || '').replace(/\s+/g, ' ').trim() || 'Note';

    if (targetEl) {
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
      const chapterEl = targetEl.closest('[data-chicken-spine-index]');
      return {
        type: 'footnote',
        label,
        text,
        fragment,
        chapter: chapterEl ? sectionIndex(chapterEl) : targetChapter,
      };
    }

    if (targetChapter !== null && (isMarkedNote || /^(fn|note|endnote|footnote|ftn)/i.test(fragment))) {
      try {
        const res = await fetch(`/__footnote/${targetChapter}/${encodeURIComponent(fragment)}`);
        if (res.ok) {
          const payload = await res.json();
          if (payload && payload.text) {
            return { type: 'footnote', label, text: payload.text, fragment, chapter: targetChapter };
          }
        }
      } catch (_) {}
    }
    return null;
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
      const href = anchor.getAttribute('href') || '';
      if (href.includes('#')) {
        const targetChapter = anchor.dataset.chickenTargetChapter !== undefined ? Number(anchor.dataset.chickenTargetChapter) : null;
        event.preventDefault();
        resolveFootnote(anchor).then((footnote) => {
          if (footnote) {
            post(footnote);
            return;
          }
          if (targetChapter !== null) {
            state.userInteracted = true;
            const frag = href.slice(href.indexOf('#') + 1);
            mountSingleChapter(targetChapter, { progress: 0 }).then(() => {
              if (!frag) return;
              const escaped = CSS && CSS.escape ? CSS.escape(frag) : frag;
              const sec = document.getElementById(`chapter-${targetChapter}`);
              const el = sec ? sec.querySelector(`#${escaped}`) : null;
              if (el) {
                if (isHorizontal()) {
                  const left = el.getBoundingClientRect().left + scrollX();
                  scrollToLocalPage(Math.floor((left + 1) / getMetrics().pageUnit));
                } else {
                  el.scrollIntoView({ block: 'start', behavior: 'auto' });
                }
                reportProgress(true);
              }
            });
          } else if (href.startsWith('#')) {
            const frag = href.slice(1);
            const el = frag ? document.getElementById(frag) : null;
            if (el) {
              if (isHorizontal()) {
                const left = el.getBoundingClientRect().left + scrollX();
                scrollToLocalPage(Math.floor((left + 1) / getMetrics().pageUnit));
              } else {
                el.scrollIntoView({ block: 'start', behavior: 'auto' });
              }
              reportProgress(true);
            }
          }
        });
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
    const m = getMetrics();
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
    if (!isHorizontal()) expandScrollWindowIfNeeded();
    clearTimeout(snapTimer);
    snapTimer = setTimeout(() => {
      snapToPage();
      reportProgress(true);
    }, 150);
  }, { passive: true });

  let resizeTimer = null;
  let resizeAnchor = null;
  const handleResize = () => {
    if (!state.restored) return;
    if (resizeAnchor === null) resizeAnchor = state.lastGlobalProgress;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      recomputeMetrics();
      scrollToProgress(resizeAnchor);
      resizeAnchor = null;
    }, 120);
  };
  window.addEventListener('resize', handleResize);
  if (window.ResizeObserver) {
    new ResizeObserver(() => {
      if (state.restored) {
        recomputeMetrics();
      }
    }).observe(doc());
  }

  const SPEAKABLE = 'p, h1, h2, h3, h4, h5, h6, li, blockquote, dd, dt, figcaption, pre, td';
  const speakableBlocksForChapter = (chapterIdx) => {
    if (state.speakableCache && state.speakableChapter === chapterIdx) return state.speakableCache;
    const root = document.getElementById(`chapter-${chapterIdx}`);
    if (!root) return [];
    let blocks = Array.from(root.querySelectorAll(`:is(${SPEAKABLE})`))
      .filter((el) => !el.querySelector(SPEAKABLE) && (el.textContent || '').trim().length > 0);
    if (!blocks.length) {
      blocks = Array.from(root.querySelectorAll('div'))
        .filter((el) => !el.querySelector('div') && (el.textContent || '').trim().length > 0);
    }
    state.speakableCache = blocks;
    state.speakableChapter = chapterIdx;
    return blocks;
  };

  const isOnScreen = (el) => {
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return false;
    return rect.bottom > 0 && rect.top < window.innerHeight && rect.right > 0 && rect.left < window.innerWidth;
  };

  const readAloud = async (after, limit = 30) => {
    let chapterIdx = state.activeChapter;
    let start = 0;
    if (after !== null && after !== undefined && String(after).includes(':')) {
      const parts = String(after).split(':');
      chapterIdx = Number(parts[0]);
      start = Number(parts[1]) + 1;
    } else {
      const blocks = speakableBlocksForChapter(chapterIdx);
      const first = blocks.findIndex(isOnScreen);
      start = first >= 0 ? first : 0;
    }
    let blocks = speakableBlocksForChapter(chapterIdx);
    while (start >= blocks.length && chapterIdx + 1 < state.spineCount) {
      chapterIdx += 1;
      start = 0;
      if (!document.getElementById(`chapter-${chapterIdx}`)) {
        await mountSingleChapter(chapterIdx, { progress: 0 });
      }
      blocks = speakableBlocksForChapter(chapterIdx);
    }
    return blocks.slice(start, start + limit).map((el, offset) => ({
      id: `${chapterIdx}:${start + offset}`,
      text: (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim(),
    }));
  };

  const revealPassage = async (id) => {
    const parts = String(id).split(':');
    const chapterIdx = parts.length === 2 ? Number(parts[0]) : state.activeChapter;
    const blockIdx = parts.length === 2 ? Number(parts[1]) : Number(id);
    if (!document.getElementById(`chapter-${chapterIdx}`)) {
      await mountSingleChapter(chapterIdx, { progress: 0 });
    }
    const el = speakableBlocksForChapter(chapterIdx)[blockIdx];
    if (!el) return;
    document.querySelectorAll('.chicken-speaking').forEach((other) => other.classList.remove('chicken-speaking'));
    el.classList.add('chicken-speaking');
    if (!isOnScreen(el) || el.getBoundingClientRect().bottom > window.innerHeight) {
      if (isHorizontal()) {
        const left = el.getBoundingClientRect().left + scrollX();
        scrollToLocalPage(Math.floor((left + 1) / getMetrics().pageUnit), state.reduceMotion ? 'auto' : 'smooth');
      } else {
        el.scrollIntoView({ block: 'start', behavior: state.reduceMotion ? 'auto' : 'smooth' });
      }
    }
    reportProgress(true);
  };

  const endReadingAloud = () => {
    document.querySelectorAll('.chicken-speaking').forEach((el) => el.classList.remove('chicken-speaking'));
  };

  const configure = (config) => {
    setThemeVars(config.background, config.textColor, config.mutedColor);
    state.background = config.background || state.background;
    state.textColor = config.textColor || state.textColor;
    state.mutedColor = config.mutedColor || state.mutedColor;
    if (config.themeOnly) return;

    const anchor = state.lastGlobalProgress;
    const nextMode = config.mode || (config.horizontal ? (config.spread ? 'spread' : 'paged') : 'scroll');
    const modeChanged = state.mode !== nextMode;
    state.mode = nextMode;
    state.nativeSwipe = Boolean(config.nativeSwipe);
    state.turnIndex = null;
    if (config.layoutKey) state.layoutKey = config.layoutKey;

    let style = document.getElementById('chicken-reader-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'chicken-reader-style';
      document.head.appendChild(style);
    }
    if (config.css) style.textContent = config.css;

    if (isHorizontal() && state.mountedLast > state.mountedFirst) {
      mountSingleChapter(state.activeChapter, { progress: 0 }).then(() => {
        if (state.restored && (modeChanged || config.preservePosition)) scrollToProgress(anchor);
      });
      return;
    }

    recomputeMetrics();
    if (state.restored && (modeChanged || config.preservePosition)) {
      requestAnimationFrame(() => {
        recomputeMetrics();
        scrollToProgress(anchor);
      });
    }
  };

  window.chicken = {
    configure,
    restore,
    scrollToSection,
    scrollToProgress,
    turnPage,
    turnChapter,
    highlightSearchMatch,
    search,
    applyHighlights,
    clearSelection: () => window.getSelection()?.removeAllRanges(),
    snapshot,
    readAloud,
    revealPassage,
    endReadingAloud,
  };

  setThemeVars(state.background, state.textColor, state.mutedColor);
  const initialHighlights = state.highlightsByChapter[String(state.activeChapter)];
  if (initialHighlights && initialHighlights.length) {
    const root = document.getElementById(`chapter-${state.activeChapter}`);
    if (root) {
      for (const item of initialHighlights) wrapText(root, item.text, item.color, item.id);
    }
  }
  recomputeMetrics();
  if (boot.restore) {
    applyChapterTargetPosition(state.activeChapter, boot.restore);
  }
  state.restored = true;
  const initialSnap = snapshot();
  state.lastPostedKey = `${initialSnap.index}|${initialSnap.page}|${Math.round(initialSnap.sectionProgression * 1000)}`;
  state.lastProgressPost = Date.now();
  prefetchNeighbors(state.activeChapter);
  post({
    type: 'ready',
    index: initialSnap.index,
    progression: initialSnap.progression,
    sectionProgression: initialSnap.sectionProgression,
    page: initialSnap.page,
    pageCount: initialSnap.pageCount,
    pageWithinSpine: initialSnap.pageWithinSpine,
    chapterPageCount: initialSnap.chapterPageCount,
  });
})();
