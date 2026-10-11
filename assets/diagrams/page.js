/*
 * A diagram drawn on this page for the app (lib/editor/diagrams/diagram_bridge.dart; DiagramRenderer.kt on Android,
 * apple/DiagramRenderer.swift on a Mac and an iPhone).
 *
 * `ghostDiagram.draw(ask)` draws what `ask.code` says the way the Tauri app's src/app/editor/mermaid.ts `render` does (the
 * same settings, word for word), puts it where its widget would (`.cm-mermaid` inside the editor's boxes, as wide as
 * the note's column), and tells the web view's owner where on the page the picture is. The owner then photographs
 * that part of the page.
 *
 *   ask:    { n, code, dark, viewport, room, gutter, em, ui, note, coding, ink, timeline? }
 *
 * `timeline` is a query's gantt (src/app/editor/QueryView.tsx `GanttView`): the block is `.cm-mermaid` and the
 * card's `.gantt` too, whose rules quiet Mermaid's drawing in the inks it names ({ tick, rule, section }). Its
 * `day` is not read: Mermaid's line at today is by this page's own clock.
 *   answer: { n, ok: true, block: { width, height }, picture: { x, y, width, height }, ... }
 *           { n, ok: false, failed }        failed is Mermaid's own words; '' is "not the person's mistake"
 *
 * `n` is the picture's number. It is painted in the page's corner as a colour (#mark) in the same breath as the
 * diagram is put on the page, so a photograph that shows that colour shows that diagram, whenever it was taken. The
 * colour is one of 125 far apart (`markOf`: n's last three digits in base five, a level of red, green and blue
 * each), so a photograph that went through a screen's own colours and back still reads as its number and never as
 * the one before.
 */
(function () {
  'use strict';

  /**
   * A gantt's bars on a dark page (mermaid.ts `DARK_GANTT`): Mermaid's dark theme draws the words on and beside a
   * finished, an under-way or a late bar in a near-black ink, so beside its bar they vanished into the page.
   */
  var DARK_GANTT = {
    taskBkgColor: '#33373d',
    taskBorderColor: '#7a828c',
    taskTextColor: '#ececec',
    taskTextLightColor: '#ececec',
    taskTextDarkColor: '#ececec',
    taskTextOutsideColor: '#cfcfcf',
    activeTaskBkgColor: '#1d3f63',
    activeTaskBorderColor: '#5b9be0',
    doneTaskBkgColor: '#2a2a2a',
    doneTaskBorderColor: '#5c5c5c',
    critBkgColor: '#5c1d1f',
    critBorderColor: '#e5484d',
    gridColor: '#3a3a3a',
    todayLineColor: '#e5484d',
  };

  var root = document.documentElement;
  var mark = document.getElementById('mark');
  var content = document.getElementById('content');
  var drawn = 0;

  function tell(message) {
    var json = JSON.stringify(message);
    if (window.ghostHost && window.ghostHost.said) window.ghostHost.said(json);
    else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ghostHost) window.webkit.messageHandlers.ghostHost.postMessage(json);
    else (window.ghostSaid = window.ghostSaid || []).push(message);
  }

  function wait(ms) {
    return new Promise(function (done) {
      setTimeout(done, ms);
    });
  }

  /**
   * The page as wide as the app's window: the web view is given that width just before it is asked, and the page
   * hears of it a moment later. Heard, not looked for on a clock: a page nobody sees may have a slow one.
   */
  function wide(viewport) {
    function is() {
      return !viewport || Math.abs(window.innerWidth - viewport) <= 1;
    }
    if (is()) return Promise.resolve();
    return new Promise(function (done) {
      function look() {
        if (!is()) return;
        window.removeEventListener('resize', look);
        done();
      }
      window.addEventListener('resize', look);
      // A web view that could not be made that wide draws at the width it has.
      setTimeout(function () {
        window.removeEventListener('resize', look);
        done();
      }, 1500);
    });
  }

  /** The colour that says picture `n` is on the page. */
  function markOf(n) {
    var levels = [0, 64, 128, 192, 255];
    var k = ((n % 125) + 125) % 125;
    return 'rgb(' + levels[k % 5] + ',' + levels[Math.floor(k / 5) % 5] + ',' + levels[Math.floor(k / 25) % 5] + ')';
  }

  /** `failure`'s message when it is an Error, and `failure` as text when it is not (core/failure.ts `failureText`). */
  function failureText(failure) {
    return failure instanceof Error ? failure.message : String(failure);
  }

  /** The faces a diagram's words are measured and drawn in, here before Mermaid measures anything. */
  function faces(ask) {
    if (!document.fonts || !document.fonts.load) return Promise.resolve();
    var asked = [];
    [ask.ui, ask.note].forEach(function (family) {
      if (!family) return;
      ['', 'bold ', 'italic '].forEach(function (how) {
        asked.push(document.fonts.load(how + '16px ' + family, ask.code).catch(function () {}));
      });
    });
    // A face that never arrives must not keep a diagram waiting: it is drawn in what the page has.
    return Promise.race([Promise.all(asked), wait(3000)]);
  }

  async function draw(ask) {
    var n = ask.n;
    try {
      root.style.setProperty('--ui-font', ask.ui || 'sans-serif');
      root.style.setProperty('--note-font', ask.note || ask.ui || 'sans-serif');
      root.style.setProperty('--app-body', ask.em + 'px');
      root.style.setProperty('--app-gutter', ask.gutter + 'px');
      root.style.setProperty('--room', ask.room + 'px');
      root.style.setProperty('--ink', ask.ink || '#000');
      var timeline = ask.timeline || null;
      root.style.setProperty('--timeline-tick', timeline ? timeline.tick : '');
      root.style.setProperty('--timeline-rule', timeline ? timeline.rule : '');
      root.style.setProperty('--timeline-section', timeline ? timeline.section : '');
      root.classList.toggle('coding', !!ask.coding);
      await wide(ask.viewport);
      await faces(ask);

      var made;
      try {
        // src/app/editor/mermaid.ts `render`, as it is there.
        mermaid.initialize({
          startOnLoad: false,
          // Labels are the note's own words, but a note can come from anywhere: no HTML out of a diagram, ever.
          securityLevel: 'strict',
          theme: ask.dark ? 'dark' : 'neutral',
          themeVariables: ask.dark ? DARK_GANTT : {},
          fontFamily: 'inherit',
        });
        drawn += 1;
        made = await mermaid.render('glyph-mermaid-' + drawn, ask.code);
      } catch (failure) {
        // What Mermaid leaves on the page of a diagram it could not draw.
        ['glyph-mermaid-' + drawn, 'dglyph-mermaid-' + drawn, 'iglyph-mermaid-' + drawn].forEach(function (id) {
          var left = document.getElementById(id);
          if (left && !content.contains(left)) left.remove();
        });
        var said = failureText(failure);
        // The library itself missing is not the person's mistake, and is said differently.
        tell({ n: n, ok: false, failed: /Failed to fetch|error loading|dynamically imported module/i.test(said) ? '' : said });
        return;
      }

      var wrap = document.createElement('div');
      wrap.className = timeline ? 'cm-mermaid gantt' : 'cm-mermaid';
      wrap.setAttribute('role', 'img');
      wrap.innerHTML = made.svg;
      wrap.dataset.drawn = '';
      content.replaceChildren(wrap);
      mark.style.background = markOf(n);

      var block = wrap.getBoundingClientRect();
      var svg = wrap.querySelector('svg');
      var picture = svg ? svg.getBoundingClientRect() : block;
      // Said at once, before the page has painted it: whoever photographs looks for the mark.
      tell({
        n: n,
        ok: true,
        block: { width: block.width, height: block.height },
        // Where the picture is on the page, and where its block starts: the picture is placed in the block by these.
        origin: { x: block.left, y: block.top },
        picture: { x: picture.left, y: picture.top, width: picture.width, height: picture.height },
        viewport: window.innerWidth,
        ratio: window.devicePixelRatio,
        kind: made.diagramType || '',
        // How many of the app's faces the page has loaded: none is a page that could not read its fonts.
        faces: document.fonts ? Array.from(document.fonts).filter(function (face) { return face.status === 'loaded'; }).length : -1,
      });
    } catch (failure) {
      tell({ n: n, ok: false, failed: '', why: failureText(failure) });
    }
  }

  window.ghostDiagram = {
    draw: function (ask) {
      void draw(ask);
    },
  };
  tell({ ready: true, mermaid: typeof mermaid !== 'undefined' });
})();
